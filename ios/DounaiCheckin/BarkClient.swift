import Foundation

enum BarkClient {
    static func send(title: String, body: String, settings: AppSettingsSnapshot) async throws {
        guard !settings.barkKey.isEmpty else { return }
        guard var components = URLComponents(string: settings.barkServer),
              components.scheme?.lowercased() == "https" else {
            throw CheckInError.message("Bark 服务地址必须使用 HTTPS")
        }
        let cleanPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [cleanPath, settings.barkKey]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        guard let url = components.url else { throw CheckInError.message("Bark 地址无效") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "title": title,
            "body": body,
            "group": "豆奶签到"
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw CheckInError.message("Bark 请求失败")
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = json["code"] as? Int, code != 200 {
            throw CheckInError.message((json["message"] as? String) ?? "Bark 服务拒绝通知")
        }
    }
}

struct AppSettingsSnapshot: Sendable {
    let siteURL: String
    let cookie: String
    let automaticEnabled: Bool
    let checkInTime: String
    let barkServer: String
    let barkKey: String
    let userAgent: String

    @MainActor
    init(_ settings: AppSettings) {
        siteURL = settings.siteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        cookie = settings.cookie
        automaticEnabled = settings.automaticEnabled
        checkInTime = settings.checkInTime
        barkServer = settings.barkServer.trimmingCharacters(in: .whitespacesAndNewlines)
        barkKey = settings.barkKey.trimmingCharacters(in: .whitespacesAndNewlines)
        userAgent = settings.userAgent
    }

    static func stored() -> AppSettingsSnapshot {
        let defaults = UserDefaults.standard
        return AppSettingsSnapshot(
            siteURL: defaults.string(forKey: "site_url") ?? "https://dounai.win",
            cookie: KeychainStore.read("site_cookie"),
            automaticEnabled: defaults.bool(forKey: "automatic_enabled"),
            checkInTime: defaults.string(forKey: "checkin_time") ?? "09:17",
            barkServer: defaults.string(forKey: "bark_server") ?? "https://api.day.app",
            barkKey: KeychainStore.read("bark_key"),
            userAgent: defaults.string(forKey: "user_agent") ?? AppSettings.defaultUserAgent
        )
    }

    private init(siteURL: String, cookie: String, automaticEnabled: Bool, checkInTime: String,
                 barkServer: String, barkKey: String, userAgent: String) {
        self.siteURL = siteURL
        self.cookie = cookie
        self.automaticEnabled = automaticEnabled
        self.checkInTime = checkInTime
        self.barkServer = barkServer
        self.barkKey = barkKey
        self.userAgent = userAgent
    }
}
