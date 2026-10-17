import Foundation

enum NotificationSender {
    static func send(title: String, body: String, settings: AppSettingsSnapshot) async -> String {
        DiagnosticLog.add("notifications start barkConfigured=\(!settings.barkKey.isEmpty) emailConfigured=\(settings.email.enabled)")
        async let bark = result(channel: "Bark") {
            try await BarkClient.send(title: title, body: body, settings: settings)
        }
        async let email = result(channel: "邮件") {
            try await EmailClient.send(title: title, body: body, configuration: settings.email)
        }
        let errors = await [bark, email].filter { !$0.isEmpty }
        return errors.isEmpty ? "" : "；通知失败：" + errors.joined(separator: "；")
    }

    private static func result(channel: String, operation: () async throws -> Void) async -> String {
        do {
            try Task.checkCancellation()
            try await operation()
            DiagnosticLog.add("notification channel=\(channel) completed=true")
            return ""
        } catch {
            DiagnosticLog.add("notification channel=\(channel) completed=false category=\(DiagnosticLog.category(error))")
            return channel + "：" + error.localizedDescription
        }
    }
}
