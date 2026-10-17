import Foundation

// Read-only native URLSession probe. It never creates a check-in POST, runs OCR,
// persists response bodies, or exports arbitrary JSON keys. Only msg may be
// exported as bounded, single-line, credential-redacted text in private runs.
enum CaptchaInspection {
    struct Outcome {
        let metadata: [[String: Any]]
        let cookie: String
    }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            // Do not send a manually supplied Cookie to a redirected origin.
            completionHandler(nil)
        }
    }

    static func run(settings: AppSettingsSnapshot,
                    configuration: URLSessionConfiguration = .ephemeral) async throws -> Outcome {
        // Reuse the core's HTTPS-root and Cookie validation, without calling checkIn().
        let validated = try CheckInClient(settings: settings)
        let base = URL(string: settings.siteURL)!
        var cookies = validated.cookieHeader
        let config = configuration.copy() as! URLSessionConfiguration
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var metadata: [[String: Any]] = []
        for stage in ["panel", "captcha"] {
            let path = stage == "panel" ? "/user/panel" : "/auth/captcha?type=checkin&_=" + String(Int(Date().timeIntervalSince1970 * 1000))
            let url = URL(string: path, relativeTo: base)!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 10
            request.setValue(cookies, forHTTPHeaderField: "Cookie")
            request.setValue(settings.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            request.setValue(stage == "panel" ? "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" : "application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
            if stage == "captcha" {
                request.setValue(base.appendingPathComponent("user/panel").absoluteString, forHTTPHeaderField: "Referer")
                request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            }
            let (data, raw) = try await session.data(for: request)
            guard let response = raw as? HTTPURLResponse, data.count <= 2 * 1024 * 1024 else {
                throw CheckInError.message("Invalid inspection response")
            }
            let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, item in
                if let key = item.key as? String, let value = item.value as? String { result[key] = value }
            }
            var values = cookies.split(separator: ";").reduce(into: [String: String]()) { result, part in
                let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
                if pair.count == 2 { result[pair[0].trimmingCharacters(in: .whitespaces)] = pair[1] }
            }
            for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url) {
                if cookie.expiresDate.map({ $0 <= Date() }) == true {
                    values.removeValue(forKey: cookie.name)
                } else { values[cookie.name] = cookie.value }
            }
            let oldValues = cookies.split(separator: ";").compactMap { part -> String? in
                let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
                return pair.count == 2 ? pair[1].trimmingCharacters(in: .whitespaces) : nil
            }
            metadata.append(summarize(data, response: response, stage: stage,
                sensitiveValues: oldValues + Array(values.values) + [settings.siteURL]))
            cookies = values.keys.sorted().map { "\($0)=\(values[$0]!)" }.joined(separator: "; ")
            DiagnosticLog.add("inspection stage=\(stage) status=\(response.statusCode)")
            if !(200..<300).contains(response.statusCode) { break }
        }
        return Outcome(metadata: metadata, cookie: cookies)
    }

    static func summarize(_ data: Data, response: HTTPURLResponse, stage: String,
                          sensitiveValues: [String] = []) -> [String: Any] {
        let text = String(decoding: data, as: UTF8.self).lowercased()
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let originalMessage = json?["msg"] as? String ?? ""
        let message = originalMessage.lowercased()
        let svg = json?["svg"] as? String ?? ""
        let ret = json?["ret"]
        let retType: String
        if let value = ret as? NSNumber {
            retType = CFGetTypeID(value) == CFBooleanGetTypeID() ? "boolean" : "number"
        } else if ret is String { retType = "string" }
        else { retType = ret == nil ? "missing" : "other" }
        let retClass: String
        if let value = ret as? Int { retClass = value == 1 ? "one" : value == 0 ? "zero" : "other" }
        else if let value = ret as? String { retClass = value == "1" ? "one" : value == "0" ? "zero" : "other" }
        else { retClass = "unavailable" }
        let category: String
        if ["人机", "交互", "interaction", "human"].contains(where: message.contains) { category = "interaction-required" }
        else if ["登录", "login", "session"].contains(where: message.contains) { category = "login-required" }
        else if ["频繁", "too many", "rate limit"].contains(where: message.contains) { category = "rate-limited" }
        else if ["已签到", "已经签到", "已续过命", "已经续过命"].contains(where: message.contains) { category = "already-checked-in" }
        else if message.contains("验证码") || message.contains("captcha") { category = "captcha-related" }
        else { category = message.isEmpty ? "empty" : "other" }
        return [
            "stage": stage == "panel" ? "panel" : "captcha",
            "httpStatus": response.statusCode,
            "bodyBytes": data.count,
            "jsonObject": json != nil,
            "retType": retType,
            "retClass": retClass,
            "svgPresent": !svg.isEmpty,
            "imageDataPresent": svg.contains("data:image/"),
            "challengePresent": json?["challenge"] != nil,
            "saltMaskPresent": json?["salt_mask"] != nil,
            "seedPresent": json?["seed"] != nil,
            "messageCategory": category,
            "messageRedacted": redactMessage(originalMessage, sensitiveValues: sensitiveValues),
            "loginPageMarker": text.contains("/auth/login") && text.contains("captcha_code"),
            "cloudChallengeMarker": text.contains("cf-chl-") || text.contains("challenge-platform"),
            "clientCaptchaGuardPasses": (ret as? Int) == 1 && !svg.isEmpty
        ]
    }

    static func redactMessage(_ raw: String, sensitiveValues: [String]) -> String {
        var text = raw
        // Explicitly mask both request and newly rotated response Cookie values.
        for value in Set(sensitiveValues).filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
            text = text.replacingOccurrences(of: value, with: "[REDACTED]")
        }
        let patterns = [
            #"(?i)\b(?:https?|wss?)://[^\s<>"']+"#,
            #"(?i)[A-Z0-9.!#$%&'*+/=?^_{|}~-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            #"\b(?:\d{1,3}\.){3}\d{1,3}(?::\d{1,5})?\b"#,
            #"(?i)(?<![a-z0-9])(?:[0-9a-f]{0,4}:){2,}[0-9a-f:.]*(?:%[a-z0-9]+)?"#,
            #"(?i)(?:cookie|phpsessid|session(?:id|_id)?|token|key|uid|email|ip|challenge|salt_mask|seed|验证码|票据)\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^\s,;]+)"#,
            #"\b[A-Za-z0-9_+/=-]{20,}\b"#
        ]
        for pattern in patterns {
            text = text.replacingOccurrences(of: pattern, with: "[REDACTED]", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: .regularExpression)
        text = String(text.unicodeScalars.map { scalar -> Character in
            if CharacterSet.controlCharacters.contains(scalar) || (0x202A...0x202E).contains(scalar.value)
                || (0x2066...0x2069).contains(scalar.value) { return " " }
            return Character(String(scalar))
        })
        // Keep server text from introducing Markdown fences or Actions commands.
        text = text.replacingOccurrences(of: "\u{0060}", with: "'")
            .replacingOccurrences(of: "::", with: ": :")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > 320 ? String(text.prefix(320)) + "…" : text
    }
}
