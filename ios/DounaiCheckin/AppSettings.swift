import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    @Published var siteURL: String
    @Published var automaticEnabled: Bool
    @Published var checkInTime: String
    @Published var barkServer: String
    @Published var barkKey: String
    @Published var emailEnabled: Bool
    @Published var emailAddress: String
    @Published var emailRecipient: String
    @Published var emailHost: String
    @Published var emailPort: Int
    @Published var emailPassword: String
    @Published var lastResult: String
    @Published var lastResultAt: Date?
    @Published var userAgent: String

    private let defaults = UserDefaults.standard

    init() {
        siteURL = defaults.string(forKey: "site_url") ?? "https://dounai.win"
        automaticEnabled = defaults.bool(forKey: "automatic_enabled")
        checkInTime = defaults.string(forKey: "checkin_time") ?? "09:17"
        barkServer = defaults.string(forKey: "bark_server") ?? "https://api.day.app"
        barkKey = KeychainStore.read("bark_key")
        emailEnabled = defaults.bool(forKey: "email_enabled")
        emailAddress = defaults.string(forKey: "email_address") ?? ""
        emailRecipient = defaults.string(forKey: "email_recipient") ?? ""
        emailHost = defaults.string(forKey: "email_host") ?? ""
        emailPort = defaults.object(forKey: "email_port") as? Int ?? 465
        emailPassword = KeychainStore.read("email_password")
        lastResult = defaults.string(forKey: "last_checkin_result") ?? defaults.string(forKey: "last_result") ?? "尚无签到记录"
        lastResultAt = defaults.object(forKey: "last_checkin_at") as? Date ?? defaults.object(forKey: "last_result_at") as? Date
        userAgent = defaults.string(forKey: "user_agent") ?? AppSettings.defaultUserAgent
    }

    var cookie: String {
        get { KeychainStore.read("site_cookie") }
        set { KeychainStore.write(newValue, for: "site_cookie") }
    }

    func save() {
        defaults.set(siteURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "site_url")
        defaults.set(automaticEnabled, forKey: "automatic_enabled")
        defaults.set(checkInTime, forKey: "checkin_time")
        defaults.set(barkServer.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "bark_server")
        KeychainStore.write(barkKey.trimmingCharacters(in: .whitespacesAndNewlines), for: "bark_key")
        defaults.set(emailEnabled, forKey: "email_enabled")
        defaults.set(emailAddress.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "email_address")
        defaults.set(emailRecipient.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "email_recipient")
        defaults.set(emailHost.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "email_host")
        defaults.set(emailPort, forKey: "email_port")
        KeychainStore.write(emailPassword, for: "email_password")
        defaults.set(userAgent, forKey: "user_agent")
    }

    func updateResult(_ result: String) {
        lastResult = result
        lastResultAt = Date()
        defaults.set(result, forKey: "last_checkin_result")
        defaults.set(lastResultAt, forKey: "last_checkin_at")
        defaults.set(result, forKey: "last_result")
        defaults.set(Date(), forKey: "last_result_at")
    }

    var hasSucceededToday: Bool {
        defaults.string(forKey: "last_success_day") == CheckInPolicy.day()
            && defaults.string(forKey: "last_success_site") == siteURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func reloadResult() {
        lastResult = defaults.string(forKey: "last_checkin_result") ?? defaults.string(forKey: "last_result") ?? "尚无签到记录"
        lastResultAt = defaults.object(forKey: "last_checkin_at") as? Date ?? defaults.object(forKey: "last_result_at") as? Date
    }

    func logout() {
        defaults.removeObject(forKey: "uncertain_submission_day")
        defaults.removeObject(forKey: "uncertain_submission_site")
        defaults.removeObject(forKey: "last_success_day")
        defaults.removeObject(forKey: "last_success_site")
        defaults.removeObject(forKey: "auto_failure_day")
        defaults.removeObject(forKey: "network_retry_day")
        defaults.removeObject(forKey: "network_retry_count")
        automaticEnabled = false
        defaults.set(false, forKey: "automatic_enabled")
        KeychainStore.delete("site_cookie")
        updateResult("已退出账号")
    }

    nonisolated static let defaultUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
}
