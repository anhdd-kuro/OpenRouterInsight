//
//  OpenRouterCreditManager.swift
//  OpenRouterCreditMenuBar
//

import Foundation
import UserNotifications

class OpenRouterCreditManager: ObservableObject {
    @Published var currentCredit: Double?
    @Published var totalUsage: Double?
    @Published var apiKeyUsages: [APIKeyUsageData] = []
    @Published var activityEntries: [ActivityEntry] = []
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var isTestingConnection = false
    @Published var errorMessage: String?
    @Published var warningThreshold: Double = 10
    @Published var connectionTestResult: Bool?
    @Published var connectionTestMessage: String?
    @Published var isKeyAnomalyAlertEnabled: Bool = true {
        didSet {
            userDefaults.set(isKeyAnomalyAlertEnabled, forKey: "alert_key_anomaly_enabled")
            if isKeyAnomalyAlertEnabled {
                requestNotificationPermissionIfNeeded()
            }
        }
    }
    @Published var isLowCreditAlertEnabled: Bool = true {
        didSet {
            userDefaults.set(isLowCreditAlertEnabled, forKey: "alert_low_credit_enabled")
            if isLowCreditAlertEnabled {
                requestNotificationPermissionIfNeeded()
            }
        }
    }

    private let userDefaults = UserDefaults.standard
    private var refreshTimer: Timer?
    private var activityCacheEntries: [ActivityEntry] = []
    private var activityCacheFetchedAt: Date?
    private let spikeMultiplier = 2.0
    private let minimumSpikeDailyUsage = 1.0

    var enabledAPIKeyCount: Int {
        apiKeyUsages.count
    }

    var lastUsedAPIKeyName: String {
        apiKeyUsages.first?.displayName ?? "-"
    }

    var apiKey: String {
        get {
            userDefaults.string(forKey: "openrouter_api_key") ?? ""
        }
        set {
            userDefaults.set(newValue, forKey: "openrouter_api_key")
            setupTimer()
        }
    }

    private func detectAndNotifyLowCreditIfNeeded(remainingCredit: Double) {
        guard isLowCreditAlertEnabled else { return }
        guard remainingCredit <= warningThreshold else { return }

        let today = Self.dayKey(for: Date())
        let defaultsKey = "low_credit_alert_notified_day"
        if userDefaults.string(forKey: defaultsKey) == today {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Low credit balance"
        content.body = "Remaining credit is $\(String(format: "%.2f", remainingCredit)), below threshold $\(String(format: "%.2f", warningThreshold))."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "low-credit-\(today)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLogger.shared.write("notification_send_failed", details: error.localizedDescription)
                return
            }

            AppLogger.shared.write("notification_sent", details: "type=low_credit,remaining=\(remainingCredit)")
        }

        userDefaults.set(today, forKey: defaultsKey)
    }

    var isEnabled: Bool {
        get {
            if userDefaults.object(forKey: "app_enabled") == nil {
                return true
            }
            return userDefaults.bool(forKey: "app_enabled")
        }
        set {
            userDefaults.set(newValue, forKey: "app_enabled")
            if newValue {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }

    var refreshInterval: Double {
        get {
            let interval = userDefaults.double(forKey: "refresh_interval")
            return interval > 0 ? interval : 300  // default 5 minutes
        }
        set {
            userDefaults.set(newValue, forKey: "refresh_interval")
            setupTimer()
        }
    }

    var isNearWarningPoint: Bool {
        if let keyUsage = apiKeyUsages.first, let keyLimitRemaining = keyUsage.limit_remaining {
            return keyLimitRemaining <= warningThreshold
        }

        if let currentCredit {
            return currentCredit <= warningThreshold
        }

        return false
    }

    init() {
        let savedWarningThreshold = userDefaults.double(forKey: "warning_threshold")
        if savedWarningThreshold > 0 {
            warningThreshold = savedWarningThreshold
        }

        if userDefaults.object(forKey: "alert_key_anomaly_enabled") != nil {
            isKeyAnomalyAlertEnabled = userDefaults.bool(forKey: "alert_key_anomaly_enabled")
        }
        if userDefaults.object(forKey: "alert_low_credit_enabled") != nil {
            isLowCreditAlertEnabled = userDefaults.bool(forKey: "alert_low_credit_enabled")
        }

        if isKeyAnomalyAlertEnabled || isLowCreditAlertEnabled {
            requestNotificationPermissionIfNeeded()
        }
        setupTimer()
        AppLogger.shared.write("manager_initialized", details: "isEnabled=\(isEnabled), hasApiKey=\(!apiKey.isEmpty)")
    }

    private func setupTimer() {
        refreshTimer?.invalidate()

        guard isEnabled && !apiKey.isEmpty else { return }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { _ in
            Task {
                await self.fetchCredit(showLoadingText: false)
            }
        }
    }

    func startMonitoring() {
        AppLogger.shared.write("monitoring_start", details: "interval=\(refreshInterval)")
        setupTimer()
        Task {
            await fetchCredit(showLoadingText: false)
        }
    }

    func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        AppLogger.shared.write("monitoring_stop")
    }

    func fetchCredit(showLoadingText: Bool = false) async {
        guard !apiKey.isEmpty && isEnabled else {
            await MainActor.run {
                self.isLoading = false
                self.isRefreshing = false
                self.errorMessage = nil
                self.currentCredit = nil
                self.apiKeyUsages = []
                self.activityEntries = []
            }
            AppLogger.shared.write("fetch_skipped", details: "isEnabled=\(isEnabled), hasApiKey=\(!apiKey.isEmpty)")
            return
        }

        AppLogger.shared.write("fetch_started")

        await MainActor.run {
            isLoading = showLoadingText
            isRefreshing = true
            errorMessage = nil
        }

        defer {
            Task { @MainActor in
                self.isLoading = false
                self.isRefreshing = false
                self.userDefaults.set(self.warningThreshold, forKey: "warning_threshold")
            }
        }

        do {
            let creditData = try await fetchCreditFromAPI()
            let remainingCredit = creditData.total_credits - creditData.total_usage
            await MainActor.run {
                self.currentCredit = remainingCredit
                self.totalUsage = creditData.total_usage
            }
            detectAndNotifyLowCreditIfNeeded(remainingCredit: remainingCredit)
            AppLogger.shared.write("fetch_credits_success", details: "remaining=\(remainingCredit)")
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
            AppLogger.shared.write("fetch_credits_failed", details: error.localizedDescription)
        }

        do {
            let keyUsages = try await fetchAllKeyUsagesFromAPI()
            await MainActor.run {
                self.apiKeyUsages = keyUsages
            }
            detectAndNotifyKeyUsageAnomalies(keyUsages)
            AppLogger.shared.write("fetch_keys_success", details: "count=\(keyUsages.count)")
        } catch {
            do {
                let fallbackKeyUsage = try await fetchKeyUsageFromAPI()
                await MainActor.run {
                    self.apiKeyUsages = [fallbackKeyUsage]
                }
                detectAndNotifyKeyUsageAnomalies([fallbackKeyUsage])
                AppLogger.shared.write("fetch_keys_fallback_success")
            } catch {
                await MainActor.run {
                    self.apiKeyUsages = []
                }
                AppLogger.shared.write("fetch_keys_failed", details: error.localizedDescription)
            }
        }

        do {
            let activityData = try await fetchActivityFromAPI()
            let parseableDateCount = activityData.filter { $0.parsedDate != nil }.count
            let models = Set(activityData.map { $0.model }).sorted()
            await MainActor.run {
                self.activityEntries = activityData
            }
            AppLogger.shared.write(
                "fetch_activity_success",
                details: "count=\(activityData.count), parseableDates=\(parseableDateCount), models=\(models.prefix(6).joined(separator: ","))"
            )
        } catch {
            await MainActor.run {
                self.activityEntries = []
            }
            AppLogger.shared.write("fetch_activity_failed", details: error.localizedDescription)
        }

        AppLogger.shared.write("fetch_finished")
    }

    func testConnection() async {
        guard !apiKey.isEmpty else {
            await MainActor.run {
                self.connectionTestResult = false
                self.connectionTestMessage = "API key is empty"
            }
            return
        }

        await MainActor.run {
            self.connectionTestResult = nil
            self.connectionTestMessage = nil
            self.isTestingConnection = true
        }

        do {
            _ = try await fetchCreditFromAPI()
            await MainActor.run {
                self.connectionTestResult = true
                self.connectionTestMessage = "Connection successful"
                self.isTestingConnection = false
            }
            AppLogger.shared.write("test_connection_success")
        } catch {
            await MainActor.run {
                self.connectionTestResult = false
                self.connectionTestMessage = error.localizedDescription
                self.errorMessage = error.localizedDescription
                self.isTestingConnection = false
            }
            AppLogger.shared.write("test_connection_failed", details: error.localizedDescription)
        }
    }

    private func fetchCreditFromAPI() async throws -> CreditData {
        guard let url = URL(string: "https://openrouter.ai/api/v1/credits") else {
            throw URLError(.badURL)
        }

        let (data, httpResponse) = try await performLoggedRequest(url: url, context: "credits")

        guard httpResponse.statusCode == 200 else {
            throw parseAPIError(data: data, statusCode: httpResponse.statusCode)
        }

        let creditResponse = try JSONDecoder().decode(CreditResponse.self, from: data)
        return creditResponse.data
    }

    private func fetchKeyUsageFromAPI() async throws -> APIKeyUsageData {
        guard let url = URL(string: "https://openrouter.ai/api/v1/key") else {
            throw URLError(.badURL)
        }

        let (data, httpResponse) = try await performLoggedRequest(url: url, context: "key")

        guard httpResponse.statusCode == 200 else {
            throw parseAPIError(data: data, statusCode: httpResponse.statusCode)
        }

        let keyResponse = try JSONDecoder().decode(KeyUsageResponse.self, from: data)
        return keyResponse.data
    }

    private func fetchAllKeyUsagesFromAPI() async throws -> [APIKeyUsageData] {
        guard let url = URL(string: "https://openrouter.ai/api/v1/keys") else {
            throw URLError(.badURL)
        }

        let (data, httpResponse) = try await performLoggedRequest(url: url, context: "keys")

        guard httpResponse.statusCode == 200 else {
            throw parseAPIError(data: data, statusCode: httpResponse.statusCode)
        }

        let keyListResponse = try JSONDecoder().decode(KeyListResponse.self, from: data)

        return keyListResponse.data
            .filter { !$0.disabled }
            .sorted { lhs, rhs in
                lhs.lastUsedSortDate > rhs.lastUsedSortDate
            }
    }

    private func fetchActivityFromAPI() async throws -> [ActivityEntry] {
        if let activityCacheFetchedAt,
           Date().timeIntervalSince(activityCacheFetchedAt) < 60,
           !activityCacheEntries.isEmpty
        {
            AppLogger.shared.write(
                "fetch_activity_cache_hit",
                details: "ageSeconds=\(Int(Date().timeIntervalSince(activityCacheFetchedAt))), count=\(activityCacheEntries.count)"
            )
            return activityCacheEntries
        }

        guard let url = URL(string: "https://openrouter.ai/api/v1/activity") else {
            throw URLError(.badURL)
        }

        let (data, httpResponse) = try await performLoggedRequest(url: url, context: "activity")

        AppLogger.shared.write("fetch_activity_http", details: "status=\(httpResponse.statusCode), bytes=\(data.count)")

        guard httpResponse.statusCode == 200 else {
            throw parseAPIError(data: data, statusCode: httpResponse.statusCode)
        }

        if let raw = String(data: data, encoding: .utf8) {
            let sample = String(raw.prefix(300)).replacingOccurrences(of: "\n", with: " ")
            AppLogger.shared.write("fetch_activity_payload_sample", details: sample)
        }

        let activityResponse = try JSONDecoder().decode(ActivityResponse.self, from: data)
        activityCacheEntries = activityResponse.data
        activityCacheFetchedAt = Date()
        return activityResponse.data
    }

    private func performLoggedRequest(url: URL, method: String = "GET", context: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        AppLogger.shared.write("api_call_start", details: "context=\(context), method=\(method), url=\(url.absoluteString)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            AppLogger.shared.write("api_call_invalid_response", details: "context=\(context), url=\(url.absoluteString)")
            throw OpenRouterAPIError(message: "Invalid response from OpenRouter")
        }

        AppLogger.shared.write(
            "api_call_response",
            details: "context=\(context), status=\(httpResponse.statusCode), bytes=\(data.count), url=\(url.absoluteString)"
        )

        if httpResponse.statusCode >= 400, let raw = String(data: data, encoding: .utf8) {
            let sample = String(raw.prefix(300)).replacingOccurrences(of: "\n", with: " ")
            AppLogger.shared.write("api_call_error_payload", details: "context=\(context), payload=\(sample)")
        }

        return (data, httpResponse)
    }

    private func parseAPIError(data: Data, statusCode: Int) -> OpenRouterAPIError {
        if let apiErrorResponse = try? JSONDecoder().decode(OpenRouterErrorResponse.self, from: data),
            let message = apiErrorResponse.error?.message
        {
            return OpenRouterAPIError(message: "[\(statusCode)] \(message)")
        }

        if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
            return OpenRouterAPIError(message: "[\(statusCode)] \(raw)")
        }

        return OpenRouterAPIError(message: "OpenRouter request failed with status \(statusCode)")
    }

    private func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                AppLogger.shared.write("notification_permission_failed", details: error.localizedDescription)
                return
            }
            AppLogger.shared.write("notification_permission_result", details: "granted=\(granted)")
        }
    }

    private func detectAndNotifyKeyUsageAnomalies(_ keyUsages: [APIKeyUsageData]) {
        guard isKeyAnomalyAlertEnabled else { return }

        for keyUsage in keyUsages {
            let baseline = max(0, keyUsage.usage_weekly / 7)
            let daily = keyUsage.usage_daily

            guard baseline > 0 else { continue }
            guard daily >= minimumSpikeDailyUsage else { continue }
            guard daily >= baseline * spikeMultiplier else { continue }

            let keyHash = keyUsage.hash
            let today = Self.dayKey(for: Date())
            let defaultsKey = "key_usage_anomaly_notified_day_by_key"
            let notifiedByKey = userDefaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]

            if notifiedByKey[keyHash] == today {
                continue
            }

            sendKeyAnomalyNotification(for: keyUsage, baseline: baseline)

            var next = notifiedByKey
            next[keyHash] = today
            userDefaults.set(next, forKey: defaultsKey)

            AppLogger.shared.write(
                "key_usage_anomaly_detected",
                details: "key=\(keyUsage.displayName), daily=\(daily), baseline=\(baseline)"
            )
        }
    }

    private func sendKeyAnomalyNotification(for keyUsage: APIKeyUsageData, baseline: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Key usage spike detected"
        content.body = "\(keyUsage.displayName): daily $\(String(format: "%.2f", keyUsage.usage_daily)) vs baseline $\(String(format: "%.2f", baseline))."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "key-usage-anomaly-\(keyUsage.hash)-\(Self.dayKey(for: Date()))",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLogger.shared.write("notification_send_failed", details: error.localizedDescription)
                return
            }

            AppLogger.shared.write("notification_sent", details: "type=key_usage_anomaly,key=\(keyUsage.displayName)")
        }
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct CreditResponse: Codable {
    let data: CreditData
}

struct CreditData: Codable {
    let total_credits: Double
    let total_usage: Double
}

struct KeyUsageResponse: Codable {
    let data: APIKeyUsageData
}

struct KeyListResponse: Codable {
    let data: [APIKeyUsageData]
}

struct ActivityResponse: Decodable {
    let data: [ActivityEntry]
}

struct ActivityEntry: Decodable, Identifiable {
    let id: UUID = UUID()
    let date: String
    let model: String
    let usage: Double
    let requests: Int
    let prompt_tokens: Int
    let completion_tokens: Int
    let reasoning_tokens: Int

    enum CodingKeys: String, CodingKey {
        case date
        case model
        case model_permaslug
        case usage
        case requests
        case prompt_tokens
        case completion_tokens
        case reasoning_tokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model)
            ?? container.decodeIfPresent(String.self, forKey: .model_permaslug)
            ?? "unknown"
        usage = try container.decodeIfPresent(Double.self, forKey: .usage) ?? 0
        requests = try container.decodeIfPresent(Int.self, forKey: .requests) ?? 0
        prompt_tokens = try container.decodeIfPresent(Int.self, forKey: .prompt_tokens) ?? 0
        completion_tokens = try container.decodeIfPresent(Int.self, forKey: .completion_tokens) ?? 0
        reasoning_tokens = try container.decodeIfPresent(Int.self, forKey: .reasoning_tokens) ?? 0
    }

    var parsedDate: Date? {
        let isoFormatter = ISO8601DateFormatter()

        if let isoDate = isoFormatter.date(from: date) {
            return isoDate
        }

        let timestampFormatter = DateFormatter()
        timestampFormatter.locale = Locale(identifier: "en_US_POSIX")
        timestampFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        timestampFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        if let timestampDate = timestampFormatter.date(from: date) {
            return timestampDate
        }

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return dayFormatter.date(from: date)
    }

    var totalTokens: Int {
        prompt_tokens + completion_tokens + reasoning_tokens
    }
}

struct APIKeyUsageData: Codable, Identifiable {
    var id: String { hash }

    let hash: String
    let name: String?
    let label: String?
    let disabled: Bool
    let limit: Double?
    let limit_reset: String?
    let limit_remaining: Double?
    let usage: Double
    let usage_daily: Double
    let usage_weekly: Double
    let usage_monthly: Double
    let created_at: String?
    let last_used_at: String?
    let updated_at: String?

    enum CodingKeys: String, CodingKey {
        case hash
        case name
        case label
        case disabled
        case limit
        case limit_reset
        case limit_remaining
        case usage
        case usage_daily
        case usage_weekly
        case usage_monthly
        case created_at
        case last_used_at
        case updated_at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let fallbackHash = "fallback_\((try? container.decodeIfPresent(String.self, forKey: .label)) ?? "unknown")"

        hash = try container.decodeIfPresent(String.self, forKey: .hash) ?? fallbackHash
        name = try container.decodeIfPresent(String.self, forKey: .name)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
        limit = try container.decodeIfPresent(Double.self, forKey: .limit)
        limit_reset = try container.decodeIfPresent(String.self, forKey: .limit_reset)
        limit_remaining = try container.decodeIfPresent(Double.self, forKey: .limit_remaining)
        usage = try container.decodeIfPresent(Double.self, forKey: .usage) ?? 0
        usage_daily = try container.decodeIfPresent(Double.self, forKey: .usage_daily) ?? 0
        usage_weekly = try container.decodeIfPresent(Double.self, forKey: .usage_weekly) ?? 0
        usage_monthly = try container.decodeIfPresent(Double.self, forKey: .usage_monthly) ?? 0
        created_at = try container.decodeIfPresent(String.self, forKey: .created_at)
        last_used_at = try container.decodeIfPresent(String.self, forKey: .last_used_at)
        updated_at = try container.decodeIfPresent(String.self, forKey: .updated_at)
    }

    var displayName: String {
        if let name, !name.isEmpty {
            return name
        }

        if let label, !label.isEmpty {
            return label
        }

        return String(hash.prefix(10))
    }

    var lastUsedSortDate: Date {
        let isoFormatter = ISO8601DateFormatter()

        if let last_used_at, let date = isoFormatter.date(from: last_used_at) {
            return date
        }

        if let updated_at, let date = isoFormatter.date(from: updated_at) {
            return date
        }

        if let created_at, let date = isoFormatter.date(from: created_at) {
            return date
        }

        return .distantPast
    }
}

struct OpenRouterErrorResponse: Codable {
    let error: OpenRouterErrorBody?
}

struct OpenRouterErrorBody: Codable {
    let message: String?
}

struct OpenRouterAPIError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
