import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    @Published var siteURL: String
    @Published var automaticEnabled: Bool
    @Published var checkInTime: String
    @Published var barkServer: String
    @Published var barkKey: String
    @Published var lastResult: String
    @Published var userAgent: String

    private let defaults = UserDefaults.standard

    init() {
        siteURL = defaults.string(forKey: "site_url") ?? "https://dounai.win"
        automaticEnabled = defaults.bool(forKey: "automatic_enabled")
        checkInTime = defaults.string(forKey: "checkin_time") ?? "09:17"
        barkServer = defaults.string(forKey: "bark_server") ?? "https://api.day.app"
        barkKey = KeychainStore.read("bark_key")
        lastResult = defaults.string(forKey: "last_result") ?? "尚无签到记录"
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
        defaults.set(userAgent, forKey: "user_agent")
    }

    func updateResult(_ result: String) {
        lastResult = result
        defaults.set(result, forKey: "last_result")
        defaults.set(Date(), forKey: "last_result_at")
    }

    func logout() {
        automaticEnabled = false
        defaults.set(false, forKey: "automatic_enabled")
        KeychainStore.delete("site_cookie")
        updateResult("已退出账号")
    }

    nonisolated static let defaultUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
}
