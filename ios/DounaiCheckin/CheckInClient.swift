import Foundation
import CryptoKit

struct CheckInOutcome: Sendable {
    let message: String
    let cookie: String
    var skipped = false
}

enum CheckInService {
    static func run(_ settings: AppSettingsSnapshot, automatic: Bool = false) async throws -> CheckInOutcome {
        try await CheckInRunner.shared.run(settings, automatic: automatic)
    }
}

private actor CheckInRunner {
    static let shared = CheckInRunner()
    private var running = false

    func run(_ settings: AppSettingsSnapshot, automatic: Bool) async throws -> CheckInOutcome {
        guard !running else { throw CheckInError.busy }
        running = true
        defer { running = false }
        try Task.checkCancellation()
        let defaults = UserDefaults.standard
        if automatic && (!settings.automaticEnabled || !defaults.bool(forKey: "automatic_enabled")) {
            DiagnosticLog.add("check-in skipped auto-disabled")
            return CheckInOutcome(message: "自动签到已关闭", cookie: settings.cookie, skipped: true)
        }
        if automatic && defaults.string(forKey: "last_success_day") == CheckInPolicy.day()
            && defaults.string(forKey: "last_success_site") == settings.siteURL {
            DiagnosticLog.add("check-in skipped already-successful-today")
            return CheckInOutcome(message: "今日已签到", cookie: settings.cookie, skipped: true)
        }
        if automatic && defaults.string(forKey: "uncertain_submission_day") == CheckInPolicy.day()
            && defaults.string(forKey: "uncertain_submission_site") == settings.siteURL {
            DiagnosticLog.add("check-in blocked unresolved-prior-submission")
            throw CheckInError.message("此前提交结果尚未确认，请查看网页签到状态后决定是否手动重试")
        }
        DiagnosticLog.add("check-in start automatic=\(automatic)")
        var client = try CheckInClient(settings: settings, budget: automatic ? 20 : 60, submissionStateChange: { uncertain in
            if uncertain {
                defaults.set(settings.siteURL, forKey: "uncertain_submission_site")
                defaults.set(CheckInPolicy.day(), forKey: "uncertain_submission_day")
            } else {
                defaults.removeObject(forKey: "uncertain_submission_day")
                defaults.removeObject(forKey: "uncertain_submission_site")
            }
        })
        defer {
            if KeychainStore.read("site_cookie") == settings.cookie {
                KeychainStore.write(client.cookieHeader, for: "site_cookie")
            }
        }
        do {
            let outcome = try await client.checkIn()
            try Task.checkCancellation()
            guard KeychainStore.read("site_cookie") == settings.cookie else { throw CancellationError() }
            defaults.set(CheckInPolicy.day(), forKey: "last_success_day")
            defaults.set(settings.siteURL, forKey: "last_success_site")
            defaults.removeObject(forKey: "uncertain_submission_day")
            defaults.removeObject(forKey: "uncertain_submission_site")
            defaults.removeObject(forKey: "auto_failure_day")
            defaults.removeObject(forKey: "network_retry_count")
            DiagnosticLog.add("check-in success")
            return outcome
        } catch {
            DiagnosticLog.add("check-in failed category=\(DiagnosticLog.category(error))")
            throw error
        }
    }
}

struct CheckInClient {
    private let baseURL: URL
    private let userAgent: String
    private var cookies: [String: String]
    private let sessionConfiguration: URLSessionConfiguration
    private let recognize: (String) async throws -> String
    private let interactionDelay: () async throws -> Void
    private let deadline: TimeInterval
    private let submissionStateChange: (Bool) -> Void
    private var submitted = false

    init(settings: AppSettingsSnapshot, budget: TimeInterval = 60,
         configuration: URLSessionConfiguration = .ephemeral,
         recognize: @escaping (String) async throws -> String = CaptchaSolver.solve,
         interactionDelay: @escaping () async throws -> Void = {
             try await Task.sleep(nanoseconds: UInt64(Int.random(in: 4_000...7_000)) * 1_000_000)
         }, submissionStateChange: @escaping (Bool) -> Void = { _ in }) throws {
        guard let url = URL(string: settings.siteURL), url.scheme?.lowercased() == "https",
              url.host != nil, url.path.isEmpty || url.path == "/" else {
            throw CheckInError.message("站点地址必须是 HTTPS 根地址")
        }
        baseURL = url
        userAgent = settings.userAgent
        cookies = Self.parseCookieHeader(settings.cookie)
        sessionConfiguration = configuration
        self.recognize = recognize
        self.interactionDelay = interactionDelay
        self.submissionStateChange = submissionStateChange
        deadline = ProcessInfo.processInfo.systemUptime + budget
        guard !cookies.isEmpty else {
            throw CheckInError.sessionExpired("没有登录信息，请先在应用中登录")
        }
    }

    mutating func checkIn() async throws -> CheckInOutcome {
        for submissionAttempt in 0..<2 {
            var ticket = "", code = ""
            for recognitionAttempt in 0..<2 {
                try checkBudget()
                DiagnosticLog.add("check-in stage=panel submissionAttempt=\(submissionAttempt) recognitionAttempt=\(recognitionAttempt)")
                let page = try await request(method: "GET", path: "/user/panel")
                try requireAuthenticated(page)
                guard let found = Self.firstMatch(in: page.body,
                    pattern: #"(?:var\s+checkinTicket\s*=|id=[\"']checkin-submit-btn[\"'][^>]*data-ticket=)\s*[\"']([^\"']+)[\"']"#) else {
                    throw CheckInError.message("签到页面未返回完整的人机校验信息，请在网页中手动签到")
                }
                ticket = found
                DiagnosticLog.add("check-in stage=captcha-fetch")
                let captcha = try await request(method: "GET", path: "/auth/captcha?type=checkin&_=" + String(Int(Date().timeIntervalSince1970 * 1000)), ajax: true)
                try requireAuthenticated(captcha)
                guard let data = captcha.body.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      (json["ret"] as? Int) == 1, let markup = json["svg"] as? String, !markup.isEmpty else {
                    if recognitionAttempt == 0 {
                        DiagnosticLog.add("captcha fetch invalid; refreshing once")
                        continue
                    }
                    throw CheckInError.message("两次均未取得有效验证码，已停止提交")
                }
                do {
                    code = try await recognize(markup)
                    break
                } catch is CancellationError { throw CancellationError() }
                catch {
                    try Task.checkCancellation()
                    DiagnosticLog.add("captcha recognition failed attempt=\(recognitionAttempt)")
                    if recognitionAttempt == 1 {
                        throw CheckInError.message("两张验证码均无法可靠识别，已停止提交以保护剩余机会")
                    }
                }
            }
            guard !code.isEmpty else { throw CheckInError.message("验证码无效，已停止提交") }
            let token = SHA256.hash(data: Data("\(ticket)_\(code)".utf8)).map { String(format: "%02x", $0) }.joined()
            try checkBudget(minimum: 8)
            try await interactionDelay()
            try checkBudget(minimum: 1)
            let values = [URLQueryItem(name: "captcha_code", value: code), URLQueryItem(name: "checkin_secret", value: ""),
                          URLQueryItem(name: "checkin_ticket", value: ticket), URLQueryItem(name: "checkin_token", value: token)]
            var components = URLComponents()
            components.queryItems = values
            DiagnosticLog.add("check-in stage=submit attempt=\(submissionAttempt)")
            submitted = true
            submissionStateChange(true)
            let response = try await request(method: "POST", path: "/user/checkin", body: components.percentEncodedQuery ?? "", ajax: true)
            try requireAuthenticated(response)
            guard let data = response.body.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CheckInError.message("签到响应无法解析")
            }
            let message = (json["msg"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard (json["ret"] as? Int) == 1, Self.isConfirmedSuccess(message) else {
                if CheckInPolicy.isCaptchaRejected(message) {
                    submitted = false
                    submissionStateChange(false)
                    if submissionAttempt == 0 {
                        DiagnosticLog.add("captcha rejected; refreshing and retrying once")
                        continue
                    }
                }
                throw CheckInError.message(message.isEmpty ? "签到未被服务端确认" : message)
            }
            return CheckInOutcome(message: message, cookie: cookieHeader)
        }
        throw CheckInError.message("验证码补试后仍未通过，已停止提交")
    }

    private mutating func request(method: String, path: String, body: String? = nil,
                                  ajax: Bool = false) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw CheckInError.message("请求地址无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        try checkBudget(minimum: 0.5)
        request.timeoutInterval = min(10, deadline - ProcessInfo.processInfo.systemUptime)
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
        let configuration = sessionConfiguration.copy() as! URLSessionConfiguration
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var received: (Data, URLResponse)?
        let safe = method == "GET" && !submitted
        for networkAttempt in 0..<(safe ? 2 : 1) {
            try Task.checkCancellation()
            do {
                received = try await session.data(for: request)
                break
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
                let transient: Set<URLError.Code> = [.timedOut, .cannotFindHost, .cannotConnectToHost,
                    .networkConnectionLost, .dnsLookupFailed, .notConnectedToInternet, .resourceUnavailable]
                guard let network = error as? URLError, transient.contains(network.code) else { throw error }
                DiagnosticLog.add("network failure safeToRetry=\(safe) attempt=\(networkAttempt) code=\(network.code.rawValue)")
                if safe && networkAttempt == 0 && deadline - ProcessInfo.processInfo.systemUptime > 12 {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    request.timeoutInterval = min(10, deadline - ProcessInfo.processInfo.systemUptime)
                    continue
                }
                throw CheckInError.network(safeToRetry: safe)
            }
        }
        guard let (data, rawResponse) = received else { throw CheckInError.network(safeToRetry: safe) }
        try Task.checkCancellation()
        guard let response = rawResponse as? HTTPURLResponse else {
            throw CheckInError.message("服务端没有返回 HTTP 响应")
        }
        DiagnosticLog.add("check-in HTTP method=\(method) status=\(response.statusCode)")
        if safe && [408, 429, 500, 502, 503, 504].contains(response.statusCode) {
            throw CheckInError.network(safeToRetry: true)
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

    var cookieHeader: String {
        cookies.keys.sorted().compactMap { key in cookies[key].map { "\(key)=\($0)" } }.joined(separator: "; ")
    }

    private func checkBudget(minimum: TimeInterval = 0) throws {
        try Task.checkCancellation()
        guard deadline - ProcessInfo.processInfo.systemUptime > minimum else { throw CheckInError.timeBudget }
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
