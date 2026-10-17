import Foundation

enum DiagnosticLog {
    private static let lock = NSLock()
    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DounaiDiagnostics/runtime.log")
    }

    // Call sites must supply only fixed events, stages, numeric codes and counts.
    // Never pass errors' localized descriptions, URLs, cookies or notification settings.
    static func add(_ event: String) {
        lock.lock(); defer { lock.unlock() }
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let format = ISO8601DateFormatter()
            format.timeZone = TimeZone(identifier: "Asia/Shanghai")
            let safe = event.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
            let line = "\(format.string(from: Date())) uptime=\(Int(ProcessInfo.processInfo.systemUptime)) pid=\(ProcessInfo.processInfo.processIdentifier) \(safe)\n"
            if !FileManager.default.fileExists(atPath: url.path) {
                try Data().write(to: url)
                #if os(iOS)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
                #endif
            }
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            if size > 512 * 1024 {
                let data = try Data(contentsOf: url)
                var kept = Data(data.suffix(384 * 1024))
                if let end = kept.firstIndex(of: 10) { kept.removeSubrange(...end) }
                try kept.write(to: url)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch { /* Diagnostics must never interrupt check-in. */ }
    }

    static func read() -> String {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url) else { return "尚无运行日志" }
        return String(decoding: data, as: UTF8.self)
    }

    static func clear() {
        lock.lock()
        try? Data().write(to: url)
        lock.unlock()
        add("log cleared")
    }

    static func category(_ error: Error) -> String {
        if error is CancellationError { return "cancelled" }
        if let error = error as? CheckInError {
            switch error {
            case .network(let safe): return "network safeToRetry=\(safe)"
            case .sessionExpired: return "session-expired"
            case .busy: return "already-running"
            case .timeBudget: return "time-budget"
            case .message: return "check-in-rejected"
            }
        }
        return "other code=\((error as NSError).code)"
    }
}
