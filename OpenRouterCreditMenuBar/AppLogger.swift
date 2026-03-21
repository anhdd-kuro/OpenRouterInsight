import Foundation

final class AppLogger {
    static let shared = AppLogger()

    private let queue = DispatchQueue(label: "com.kttizz.OpenRouterCreditMenuBar.logger", qos: .utility)
    private let logFileURL: URL

    private init() {
        self.logFileURL = AppLogger.resolveLogFileURL()
        self.write("logger_initialized", details: "path=\(logFileURL.path)")
    }

    func write(_ event: String, details: String = "") {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(event)\(details.isEmpty ? "" : " | \(details)")\n"

        queue.async {
            do {
                let folder = self.logFileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

                if !FileManager.default.fileExists(atPath: self.logFileURL.path) {
                    try line.data(using: .utf8)?.write(to: self.logFileURL)
                    return
                }

                let handle = try FileHandle(forWritingTo: self.logFileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
            } catch {
                NSLog("AppLogger write failed: \(error.localizedDescription)")
            }
        }
    }

    func deleteLogFiles() {
        let fileManager = FileManager.default

        for url in Self.candidateLogFileURLs() {
            guard fileManager.fileExists(atPath: url.path) else { continue }

            do {
                try fileManager.removeItem(at: url)
            } catch {
                NSLog("AppLogger delete failed at \(url.path): \(error.localizedDescription)")
            }
        }
    }

    private static func resolveLogFileURL() -> URL {
        if let bundleLogsURL = Bundle.main.resourceURL?.appendingPathComponent("Logs", isDirectory: true) {
            let testURL = bundleLogsURL.appendingPathComponent("runtime.log")
            if isWritable(url: bundleLogsURL) {
                return testURL
            }
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let fallback = appSupport
            .appendingPathComponent("OpenRouterCreditMenuBar", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
        return fallback.appendingPathComponent("runtime.log")
    }

    private static func candidateLogFileURLs() -> [URL] {
        var urls: [URL] = []

        if let bundleLogsURL = Bundle.main.resourceURL?.appendingPathComponent("Logs", isDirectory: true) {
            urls.append(bundleLogsURL.appendingPathComponent("runtime.log"))
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let fallback = appSupport
            .appendingPathComponent("OpenRouterCreditMenuBar", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
        urls.append(fallback.appendingPathComponent("runtime.log"))

        return urls
    }

    private static func isWritable(url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            return FileManager.default.isWritableFile(atPath: url.path)
        }

        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return FileManager.default.isWritableFile(atPath: url.path)
        } catch {
            return false
        }
    }
}
