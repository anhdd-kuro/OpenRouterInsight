import Charts
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var creditManager: OpenRouterCreditManager

    private enum UsageViewMode: String {
        case slider
        case table
        case list
    }

    private let primaryColor = Color(red: 100 / 255, green: 103 / 255, blue: 242 / 255)

    @State private var selectedKeyIndex = 0
    @AppStorage("usage_view_mode") private var usageViewMode: UsageViewMode = .slider
    @State private var autoSlideEnabled = true
    @State private var selectedActivityTimeFilter: ActivityTimeFilter = .week
    @State private var selectedActivityModelFilter = "All Models"
    @State private var isLeftArrowHovered = false
    @State private var isRightArrowHovered = false
    @State private var hoveredActionIcon: String?
    @State private var hoveredExternalLinkModel: String?
    @State private var modelUsageSortMetric: ModelUsageSortMetric = .spend
    @State private var modelUsageSortAscending = false
    @State private var modelUsageLimit = 5
    @State private var keyUtilizationSortMetric: KeyUtilizationSortMetric = .utilization
    @State private var keyUtilizationSortAscending = false
    @State private var isHoveringCreditLink = false
    @State private var isHoveringEnabledKeysLink = false

    private let autoSlideTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private var selectedKeyUsage: APIKeyUsageData? {
        guard creditManager.apiKeyUsages.indices.contains(selectedKeyIndex) else {
            return creditManager.apiKeyUsages.first
        }

        return creditManager.apiKeyUsages[selectedKeyIndex]
    }

    private var filteredActivityEntries: [ActivityEntry] {
        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: Date())
        let startDay = calendar.date(byAdding: .day, value: -(selectedActivityTimeFilter.days - 1), to: endDay) ?? endDay

        return creditManager.activityEntries.filter { entry in
            guard let parsedDate = entry.parsedDate else { return false }
            let day = calendar.startOfDay(for: parsedDate)
            guard day >= startDay && day <= endDay else { return false }
            if selectedActivityModelFilter == "All Models" {
                return true
            }
            return entry.model == selectedActivityModelFilter
        }
    }

    private func sortKeyUtilizationButton(_ title: String, metric: KeyUtilizationSortMetric) -> some View {
        Button {
            if keyUtilizationSortMetric == metric {
                keyUtilizationSortAscending.toggle()
            } else {
                keyUtilizationSortMetric = metric
                keyUtilizationSortAscending = false
            }
        } label: {
            HStack(spacing: 2) {
                Text(title)
                if keyUtilizationSortMetric == metric {
                    Image(systemName: keyUtilizationSortAscending ? "arrow.up" : "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .font(.caption2)
            .foregroundColor(.white.opacity(0.95))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(keyUtilizationSortMetric == metric ? primaryColor.opacity(0.45) : Color.white.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(keyUtilizationSortMetric == metric ? 0.5 : 0.25), lineWidth: 1)
        )
    }

    private var keyUtilizationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Key Utilization Ranking", systemImage: "key.horizontal.fill")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                sortKeyUtilizationButton("Key", metric: .key)
                sortKeyUtilizationButton("Used", metric: .used)
                sortKeyUtilizationButton("Util", metric: .utilization)
            }

            simpleTableSection(
                headers: [
                    .init(title: "#", width: 34, alignment: .leading),
                    .init(title: "Key", width: nil, alignment: .leading),
                    .init(title: "Used/Limit", width: 108, alignment: .trailing),
                    .init(title: "Util", width: 56, alignment: .trailing)
                ],
                rows: keyUtilizationRows
            )

            Text("Sorted by highest limit utilization.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var modelConcentrationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Model Concentration Insight", systemImage: "chart.pie.fill")
                .font(.caption)
                .foregroundColor(.secondary)

            if modelConcentrationSlices.isEmpty {
                Text("No spend data available for current filters.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Chart(modelConcentrationSlices) { slice in
                    SectorMark(
                        angle: .value("Spend", slice.spend),
                        innerRadius: .ratio(0.58),
                        angularInset: 1
                    )
                    .foregroundStyle(by: .value("Model", slice.label))
                }
                .chartLegend(position: .trailing, spacing: 6)
                .frame(height: 138)

                Text("Top 5 share: \(Int((topFiveShareRatio * 100).rounded()))% of spend (Others = rank 6+).")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var topModelUsageRows: [[TableCell]] {
        var grouped: [String: ModelUsageSummary] = [:]

        for entry in filteredActivityEntries {
            let split = providerAndModel(from: entry.model)
            var summary = grouped[entry.model] ?? ModelUsageSummary(provider: split.provider, model: split.model, spend: 0, requests: 0, tokens: 0)
            summary.spend += entry.usage
            summary.requests += entry.requests
            summary.tokens += entry.totalTokens
            grouped[entry.model] = summary
        }

        let sorted = grouped.values.sorted { lhs, rhs in
            let ordered: Bool = switch modelUsageSortMetric {
            case .provider:
                lhs.provider.localizedCaseInsensitiveCompare(rhs.provider) == .orderedAscending
            case .model:
                lhs.model.localizedCaseInsensitiveCompare(rhs.model) == .orderedAscending
            case .spend:
                lhs.spend < rhs.spend
            case .requests:
                lhs.requests < rhs.requests
            case .tokens:
                lhs.tokens < rhs.tokens
            }
            return modelUsageSortAscending ? ordered : !ordered
        }

        return Array(sorted.prefix(modelUsageLimit).enumerated()).map { index, item in
            [
                TableCell(value: "#\(index + 1)", width: 34, alignment: .leading),
                TableCell(value: item.provider, width: 70, alignment: .leading),
                TableCell(value: item.model, width: nil, alignment: .leading, bold: true),
                TableCell(value: "$\(formatAmount(item.spend))", width: 62, alignment: .trailing),
                TableCell(value: "\(item.requests)", width: 44, alignment: .trailing),
                TableCell(value: compactTokenText(item.tokens), width: 54, alignment: .trailing)
            ]
        }
    }

    private var keyUtilizationRows: [[TableCell]] {
        let ranked = creditManager.apiKeyUsages.compactMap { item -> KeyUtilizationSummary? in
            guard let limit = item.limit, limit > 0 else { return nil }
            let remaining = item.limit_remaining ?? limit
            let used = max(0, limit - remaining)
            let ratio = max(0, min(1, used / limit))
            return KeyUtilizationSummary(
                keyName: item.displayName,
                used: used,
                limit: limit,
                utilizationRatio: ratio
            )
        }
        .sorted { lhs, rhs in
            let ordered: Bool = switch keyUtilizationSortMetric {
            case .key:
                lhs.keyName.localizedCaseInsensitiveCompare(rhs.keyName) == .orderedAscending
            case .used:
                lhs.used < rhs.used
            case .utilization:
                lhs.utilizationRatio < rhs.utilizationRatio
            }
            return keyUtilizationSortAscending ? ordered : !ordered
        }

        return Array(ranked.enumerated()).map { index, item in
            [
                TableCell(value: "#\(index + 1)", width: 34, alignment: .leading),
                TableCell(value: item.keyName, width: nil, alignment: .leading, bold: true),
                TableCell(value: "$\(formatAmount(item.used))/$\(formatAmount(item.limit))", width: 108, alignment: .trailing),
                TableCell(value: "\(Int(item.utilizationRatio * 100))%", width: 56, alignment: .trailing, color: item.utilizationRatio > 0.85 ? .orange : .primary)
            ]
        }
    }

    private var modelConcentrationSlices: [ConcentrationSlice] {
        let groupedSpend = filteredActivityEntries.reduce(into: [String: Double]()) { partial, entry in
            partial[entry.model, default: 0] += entry.usage
        }

        let sorted = groupedSpend
            .map { ConcentrationSlice(label: $0.key, spend: $0.value) }
            .sorted { lhs, rhs in
                lhs.spend > rhs.spend
            }

        let topFive = Array(sorted.prefix(5))
        let othersSpend = sorted.dropFirst(5).reduce(0) { $0 + $1.spend }

        if othersSpend > 0 {
            return topFive + [ConcentrationSlice(label: "Others", spend: othersSpend)]
        }

        return topFive
    }

    private var topFiveShareRatio: Double {
        let total = modelConcentrationSlices.reduce(0) { $0 + $1.spend }
        guard total > 0 else { return 0 }

        let topFive = modelConcentrationSlices
            .filter { $0.label != "Others" }
            .reduce(0) { $0 + $1.spend }

        return topFive / total
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 12) {
            HStack(spacing: 6) {
                Label("Open-router Insight", systemImage: "creditcard")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                actionIconButton(systemName: "arrow.clockwise", tooltip: "Refresh") {
                    Task {
                        await creditManager.fetchCredit(showLoadingText: true)
                    }
                }

                actionIconButton(systemName: "chart.xyaxis.line", tooltip: "View Rankings") {
                    if let url = URL(string: "https://openrouter.ai/rankings") {
                        NSWorkspace.shared.open(url)
                    }
                }

                actionIconButton(systemName: "gearshape", tooltip: "Settings") {
                    NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
                }

                actionIconButton(systemName: "power", tooltip: "Quit", iconColor: .red) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.top, 8)

            Divider()

            if creditManager.isLoading {
                VStack(spacing: 4) {
                    Text("Available Credit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading...")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    Text("Enabled Keys: \(creditManager.enabledAPIKeyCount)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Last Used: \(creditManager.lastUsedAPIKeyName)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else if let credit = creditManager.currentCredit {
                VStack(spacing: 4) {
                    Text("Available Credit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button {
                        if let url = URL(string: "https://openrouter.ai/settings/credits") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text("$\(formatAmount(credit))")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(credit <= 0 ? .red : .primary)
                            .underline(isHoveringCreditLink)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isHoveringCreditLink = hovering
                    }
                    .help("Open OpenRouter credits settings")

                    Button {
                        if let url = URL(string: "https://openrouter.ai/settings/keys") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text("Enabled Keys: \(creditManager.enabledAPIKeyCount)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .underline(isHoveringEnabledKeysLink)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isHoveringEnabledKeysLink = hovering
                    }
                    .help("Open OpenRouter keys settings")
                    Text("Last Used: \(creditManager.lastUsedAPIKeyName)")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if creditManager.isNearWarningPoint {
                        Label("Low balance warning", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .padding(.top, 2)
                    }
                }
            } else if let error = creditManager.errorMessage {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Error")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(error)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    modeButton("Slider", mode: .slider)
                    modeButton("Table", mode: .table)
                    modeButton("List", mode: .list)
                }

                if creditManager.apiKeyUsages.isEmpty {
                    Text("No API key usage data")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    switch usageViewMode {
                    case .slider:
                        Toggle("Autoplay", isOn: $autoSlideEnabled)
                            .font(.caption2)
                            .toggleStyle(.switch)

                        if let selectedKeyUsage {
                            keyUsageCard(for: selectedKeyUsage)
                                .frame(height: 170)
                                .gesture(
                                    DragGesture(minimumDistance: 20)
                                        .onEnded { value in
                                            if value.translation.width < -25 {
                                                moveSlideRight()
                                            } else if value.translation.width > 25 {
                                                moveSlideLeft()
                                            }
                                        }
                                )
                        }

                        HStack(spacing: 8) {
                            sliderArrowButton(systemName: "chevron.left", isHovered: $isLeftArrowHovered) {
                                moveSlideLeft()
                            }
                            .disabled(creditManager.apiKeyUsages.count <= 1)

                            HStack(spacing: 6) {
                                ForEach(creditManager.apiKeyUsages.indices, id: \.self) { index in
                                    Circle()
                                        .fill((usageViewMode == .slider ? Color.white : primaryColor).opacity(index == selectedKeyIndex ? 1.0 : 0.5))
                                        .frame(width: 6, height: 6)
                                        .onTapGesture {
                                            selectedKeyIndex = index
                                        }
                                }
                            }
                            .frame(maxWidth: .infinity)

                            sliderArrowButton(systemName: "chevron.right", isHovered: $isRightArrowHovered) {
                                moveSlideRight()
                            }
                            .disabled(creditManager.apiKeyUsages.count <= 1)
                        }
                    case .table:
                        keyUsageTable
                    case .list:
                        keyUsageList
                    }
                }
            }
            .onChange(of: creditManager.apiKeyUsages.count) { _, count in
                if count == 0 {
                    selectedKeyIndex = 0
                    return
                }

                if selectedKeyIndex >= count {
                    selectedKeyIndex = max(0, count - 1)
                }
            }
            .onReceive(autoSlideTimer) { _ in
                guard usageViewMode == .slider else { return }
                guard autoSlideEnabled else { return }
                guard creditManager.apiKeyUsages.count > 1 else { return }
                moveSlideRight()
            }
            .onChange(of: usageViewMode) { _, mode in
                guard mode != .slider else { return }
                guard creditManager.apiKeyUsages.isEmpty else { return }
                guard !creditManager.isRefreshing else { return }
                Task {
                    await creditManager.fetchCredit(showLoadingText: false)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Activity", systemImage: "waveform.path.ecg")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Circle()
                        .fill(creditManager.activityEntries.isEmpty ? Color.orange : Color.green)
                        .frame(width: 7, height: 7)

                    Spacer()
                }

                ActivityChartsView(
                    entries: creditManager.activityEntries,
                    selectedTimeFilter: $selectedActivityTimeFilter,
                    selectedModelFilter: $selectedActivityModelFilter
                )
            }

            Divider()

            recentTransactionsSection

            Divider()

            keyUtilizationSection

            Divider()

            modelConcentrationSection

            }
            .padding()
        }
        .frame(width: 400)
        .onAppear {
            guard creditManager.apiKeyUsages.isEmpty else { return }
            guard !creditManager.isRefreshing else { return }
            Task {
                await creditManager.fetchCredit(showLoadingText: false)
            }
        }
        .tint(primaryColor)
    }

    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Label("Top Model Usage", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Picker("Top N", selection: $modelUsageLimit) {
                    Text("Top 5").tag(5)
                    Text("Top 10").tag(10)
                    Text("Top 15").tag(15)
                    Text("Top 20").tag(20)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 74)
            }

            HStack(spacing: 4) {
                sortMetricButton("Provider", metric: .provider)
                sortMetricButton("Model", metric: .model)
                sortMetricButton("Credit", metric: .spend)
                sortMetricButton("Requests", metric: .requests)
                sortMetricButton("Tokens", metric: .tokens)
            }

            simpleTableSection(
                headers: [
                    .init(title: "#", width: 34, alignment: .leading),
                    .init(title: "Provider", width: 70, alignment: .leading),
                    .init(title: "Model", width: nil, alignment: .leading),
                    .init(title: "Credit", width: 62, alignment: .trailing),
                    .init(title: "Req", width: 44, alignment: .trailing),
                    .init(title: "Tokens", width: 54, alignment: .trailing)
                ],
                rows: topModelUsageRows
            )

            Text("Calculated from current Activity filters (range + model).")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var keyUsageTable: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Key")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Daily")
                    .frame(width: 48, alignment: .trailing)
                Text("Monthly")
                    .frame(width: 56, alignment: .trailing)
                Text("Remain")
                    .frame(width: 52, alignment: .trailing)
                Text("Limit")
                    .frame(width: 68, alignment: .trailing)
            }
            .font(.caption2)
            .foregroundColor(.secondary)

            ForEach(Array(creditManager.apiKeyUsages.enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(item.displayName)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("$\(formatAmount(item.usage_daily))")
                        .frame(width: 48, alignment: .trailing)
                    Text("$\(formatAmount(item.usage_monthly))")
                        .frame(width: 56, alignment: .trailing)
                    Text("$\(formatAmount(item.limit_remaining ?? 0))")
                        .frame(width: 52, alignment: .trailing)
                    Text(limitUsageText(for: item))
                        .foregroundColor(.orange)
                        .frame(width: 68, alignment: .trailing)
                }
                .font(.caption2)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var keyUsageList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(Array(creditManager.apiKeyUsages.enumerated()), id: \.offset) { _, item in
                    keyUsageCard(for: item)
                }
            }
            .padding(1)
        }
        .frame(maxHeight: 300)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func keyUsageCard(for keyUsage: APIKeyUsageData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("API Key Usage")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Text(keyUsage.displayName)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    Button {
                        if let url = URL(string: "https://openrouter.ai/keys") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(hoveredExternalLinkModel == keyUsage.hash ? primaryColor : .secondary)
                    .onHover { hovering in
                        hoveredExternalLinkModel = hovering ? keyUsage.hash : nil
                    }
                    .help("Open OpenRouter keys")
                }
            }

            VStack(spacing: 6) {
                usageRow(title: "Daily", value: keyUsage.usage_daily)
                usageRow(title: "Weekly", value: keyUsage.usage_weekly)
                usageRow(title: "Monthly", value: keyUsage.usage_monthly)
                usageRow(title: "Total", value: keyUsage.usage)
            }

            if let limit = keyUsage.limit, let limitRemaining = keyUsage.limit_remaining, limit > 0 {
                let usageRatio = max(0, min(1, (limit - limitRemaining) / limit))

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Limit")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("$\(formatAmount(max(0, limit - limitRemaining))) / $\(formatAmount(limit))")
                            .font(.caption2)
                            .foregroundColor(limitRemaining <= creditManager.warningThreshold ? .orange : .secondary)
                    }

                    ProgressView(value: usageRatio)
                        .tint(limitRemaining <= creditManager.warningThreshold ? .orange : primaryColor)

                    if let limitReset = keyUsage.limit_reset, !limitReset.isEmpty {
                        Text("Resets: \(limitReset)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func modeButton(_ title: String, mode: UsageViewMode) -> some View {
        Button(title) {
            usageViewMode = mode
        }
        .buttonStyle(.plain)
        .font(.caption2)
        .foregroundColor(.white.opacity(0.95))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(usageViewMode == mode ? primaryColor.opacity(0.45) : Color.white.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(usageViewMode == mode ? 0.5 : 0.25), lineWidth: 1)
        )
    }

    private func sortMetricButton(_ title: String, metric: ModelUsageSortMetric) -> some View {
        Button {
            if modelUsageSortMetric == metric {
                modelUsageSortAscending.toggle()
            } else {
                modelUsageSortMetric = metric
                modelUsageSortAscending = false
            }
        } label: {
            HStack(spacing: 2) {
                Text(title)
                if modelUsageSortMetric == metric {
                    Image(systemName: modelUsageSortAscending ? "arrow.up" : "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .font(.caption2)
            .foregroundColor(.white.opacity(0.95))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(modelUsageSortMetric == metric ? primaryColor.opacity(0.45) : Color.white.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(modelUsageSortMetric == metric ? 0.5 : 0.25), lineWidth: 1)
        )
    }

    private func actionIconButton(systemName: String, tooltip: String, iconColor: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 24, height: 24)
                .padding(3)
        }
        .buttonStyle(.plain)
        .foregroundColor(iconColor)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(hoveredActionIcon == systemName ? 0.2 : 0))
        )
        .onHover { hovering in
            hoveredActionIcon = hovering ? systemName : nil
        }
        .help(tooltip)
    }

    private func sliderArrowButton(systemName: String, isHovered: Binding<Bool>, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .foregroundColor(.primary)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(isHovered.wrappedValue ? 0.6 : 0.5))
        )
        .onHover { hovering in
            isHovered.wrappedValue = hovering
        }
    }

    private func moveSlideLeft() {
        guard !creditManager.apiKeyUsages.isEmpty else { return }
        if selectedKeyIndex == 0 {
            selectedKeyIndex = creditManager.apiKeyUsages.count - 1
            return
        }
        selectedKeyIndex -= 1
    }

    private func moveSlideRight() {
        guard !creditManager.apiKeyUsages.isEmpty else { return }
        selectedKeyIndex = (selectedKeyIndex + 1) % creditManager.apiKeyUsages.count
    }

    private func usageRow(title: String, value: Double) -> some View {
        HStack {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            Text("$\(formatAmount(value))")
                .font(.caption2)
        }
    }

    private func formatAmount(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func compactTokenText(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    private func simpleTableSection(headers: [TableColumn], rows: [[TableCell]]) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    Text(header.title)
                        .frame(width: header.width, alignment: header.alignment)
                        .frame(maxWidth: header.width == nil ? .infinity : nil, alignment: header.alignment)
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)

            if rows.isEmpty {
                HStack {
                    Text("No data")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 4) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell.value)
                                .font(cell.bold ? .caption : .caption2)
                                .fontWeight(cell.bold ? .semibold : .regular)
                                .foregroundColor(cell.color)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(width: cell.width, alignment: cell.alignment)
                                .frame(maxWidth: cell.width == nil ? .infinity : nil, alignment: cell.alignment)
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }

    private func limitUsageText(for item: APIKeyUsageData) -> String {
        guard let limit = item.limit, limit > 0 else { return "-" }
        let remaining = item.limit_remaining ?? limit
        let used = max(0, limit - remaining)
        return "$\(formatAmount(used))/$\(formatAmount(limit))"
    }

    private func providerAndModel(from rawModel: String) -> (provider: String, model: String) {
        let parts = rawModel.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            return (provider: "unknown", model: rawModel)
        }

        return (provider: String(parts[0]), model: String(parts[1]))
    }
}

private struct TableColumn {
    let title: String
    let width: CGFloat?
    let alignment: Alignment
}

private enum ModelUsageSortMetric {
    case provider
    case model
    case spend
    case requests
    case tokens
}

private enum KeyUtilizationSortMetric {
    case key
    case used
    case utilization
}

private struct ModelUsageSummary {
    let provider: String
    let model: String
    var spend: Double
    var requests: Int
    var tokens: Int
}

private struct KeyUtilizationSummary {
    let keyName: String
    let used: Double
    let limit: Double
    let utilizationRatio: Double
}

private struct ConcentrationSlice: Identifiable {
    var id: String { label }
    let label: String
    let spend: Double
}

private struct TableCell {
    let value: String
    let width: CGFloat?
    let alignment: Alignment
    let color: Color
    let bold: Bool

    init(value: String, width: CGFloat? = nil, alignment: Alignment = .leading, color: Color = .primary, bold: Bool = false) {
        self.value = value
        self.width = width
        self.alignment = alignment
        self.color = color
        self.bold = bold
    }
}
