import Foundation
import CryptoKit

struct CheckInOutcome: Sendable {
    let message: String
    let cookie: String
}

enum CheckInService {
    static func run(_ settings: AppSettingsSnapshot) async throws -> CheckInOutcome {
        var client = try CheckInClient(settings: settings)
        return try await client.checkIn()
    }
}

private struct CheckInClient {
    private let baseURL: URL
    private let userAgent: String
    private var cookies: [String: String]

    init(settings: AppSettingsSnapshot) throws {
        guard let url = URL(string: settings.siteURL), url.scheme?.lowercased() == "https",
              url.host != nil, url.path.isEmpty || url.path == "/" else {
            throw CheckInError.message("站点地址必须是 HTTPS 根地址")
        }
        baseURL = url
        userAgent = settings.userAgent
        cookies = Self.parseCookieHeader(settings.cookie)
        guard !cookies.isEmpty else {
            throw CheckInError.sessionExpired("没有登录信息，请先在应用中登录")
        }
    }

    mutating func checkIn() async throws -> CheckInOutcome {
        let page = try await request(method: "GET", path: "/user/panel")
        try requireAuthenticated(page)
        guard let ticket = Self.firstMatch(in: page.body,
                                           pattern: #"(?:var\s+checkinTicket\s*=|id=[\"']checkin-submit-btn[\"'][^>]*data-ticket=)\s*[\"']([^\"']+)[\"']"#) else {
            throw CheckInError.message("签到页面未返回完整的人机校验信息，请在网页中手动签到")
        }

        let captchaResponse = try await request(method: "GET", path: "/auth/captcha?type=checkin&_=" + String(Int(Date().timeIntervalSince1970 * 1000)), ajax: true)
        guard (200..<300).contains(captchaResponse.status),
              let data = captchaResponse.body.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["ret"] as? Int) == 1, let markup = json["svg"] as? String, !markup.isEmpty else {
            throw CheckInError.message("验证码获取失败")
        }
        let code = try await CaptchaSolver.solve(markup)
        let token = SHA256.hash(data: Data("\(ticket)_\(code)".utf8)).map { String(format: "%02x", $0) }.joined()
        try await Task.sleep(nanoseconds: UInt64(Int.random(in: 4_000...7_000)) * 1_000_000)

        let values = [
            URLQueryItem(name: "captcha_code", value: code),
            URLQueryItem(name: "checkin_secret", value: ""),
            URLQueryItem(name: "checkin_ticket", value: ticket),
            URLQueryItem(name: "checkin_token", value: token)
        ]
        var components = URLComponents()
        components.queryItems = values
        let response = try await request(method: "POST", path: "/user/checkin",
                                         body: components.percentEncodedQuery ?? "", ajax: true)
        try requireAuthenticated(response)
        guard let data = response.body.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CheckInError.message("签到响应无法解析")
        }
        let message = (json["msg"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard (json["ret"] as? Int) == 1, Self.isConfirmedSuccess(message) else {
            throw CheckInError.message(message.isEmpty ? "签到未被服务端确认" : message)
        }
        return CheckInOutcome(message: message, cookie: cookieHeader)
    }

    private mutating func request(method: String, path: String, body: String? = nil,
                                  ajax: Bool = false) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw CheckInError.message("请求地址无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        if ajax {
            request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
            request.setValue(baseURL.appendingPathComponent("user/panel").absoluteString, forHTTPHeaderField: "Referer")
            request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        } else {
            request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        }
        if let body {
            request.httpBody = body.data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.setValue(baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")), forHTTPHeaderField: "Origin")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let (data, rawResponse) = try await URLSession(configuration: configuration).data(for: request)
        guard let response = rawResponse as? HTTPURLResponse else {
            throw CheckInError.message("服务端没有返回 HTTP 响应")
        }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, item in
            if let key = item.key as? String, let value = item.value as? String { result[key] = value }
        }
        HTTPCookie.cookies(withResponseHeaderFields: headers, for: url).forEach {
            if $0.isExpired { cookies.removeValue(forKey: $0.name) } else { cookies[$0.name] = $0.value }
        }
        guard data.count <= 2 * 1024 * 1024 else { throw CheckInError.message("服务端响应过大") }
        return Response(status: response.statusCode, finalURL: response.url, body: String(decoding: data, as: UTF8.self))
    }

    private func requireAuthenticated(_ response: Response) throws {
        let lower = response.body.lowercased()
        if response.status == 401 || response.status == 403 || response.finalURL?.path.lowercased().contains("login") == true
            || lower.contains("/auth/login") && lower.contains("captcha_code") {
            throw CheckInError.sessionExpired("登录态已失效，请在应用中重新登录")
        }
        guard (200..<300).contains(response.status) else {
            throw CheckInError.message("服务端返回 HTTP \(response.status)")
        }
    }

    private var cookieHeader: String {
        cookies.keys.sorted().compactMap { key in cookies[key].map { "\(key)=\($0)" } }.joined(separator: "; ")
    }

    private static func parseCookieHeader(_ header: String) -> [String: String] {
        header.split(separator: ";").reduce(into: [:]) { result, part in
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { result[pair[0].trimmingCharacters(in: .whitespaces)] = pair[1].trimmingCharacters(in: .whitespaces) }
        }
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isConfirmedSuccess(_ message: String) -> Bool {
        ["已经续过命", "已续过命", "已经签到", "已签到", "签到成功", "续命成功"].contains { message.contains($0) }
            || message.range(of: #"(?:^|[^未])获得了?\s*[0-9]"#, options: .regularExpression) != nil
    }

    private struct Response {
        let status: Int
        let finalURL: URL?
        let body: String
    }
}

private extension HTTPCookie {
    var isExpired: Bool { expiresDate.map { $0 <= Date() } ?? false }
}
