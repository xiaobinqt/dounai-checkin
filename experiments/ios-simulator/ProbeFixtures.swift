import Foundation
import CoreText
import ImageIO

final class ProbeHTTP: URLProtocol {
    struct Reply {
        let body: String
        var error: URLError? = nil
        var cookie: String? = nil
    }
    static var replies: [Reply] = []
    static var methods: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.methods.append(request.httpMethod ?? "")
        guard !Self.replies.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let reply = Self.replies.removeFirst()
        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: reply.cookie.map { ["Set-Cookie": $0] })!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

enum ProbeFixtures {
    static let panel = ProbeHTTP.Reply(body: #"<script>var checkinTicket = "test-ticket";</script>"#)
    static let captcha = ProbeHTTP.Reply(body: #"{"ret":1,"svg":"<svg><text>六-二=</text></svg>"}"#)
    static let success = ProbeHTTP.Reply(body: #"{"ret":1,"msg":"签到成功"}"#, cookie: "session=rotated; Path=/")
    static let rejected = ProbeHTTP.Reply(body: #"{"ret":0,"msg":"验证码已过期，请刷新重试"}"#)

    static func client(_ replies: [ProbeHTTP.Reply]) throws -> CheckInClient {
        ProbeHTTP.replies = replies
        ProbeHTTP.methods = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProbeHTTP.self]
        return try CheckInClient(settings: Probe.settings(site: "https://example.invalid", cookie: "session=test"),
                                 configuration: configuration, interactionDelay: {})
    }

    static func run() async throws {
        let svg = try await CaptchaSolver.solve("<svg><text>玖-伍=</text></svg>")
        try require(svg == "4")
        DiagnosticLog.add("probe svg passed")
        let png = try readablePNG()
        let answer = try await CaptchaSolver.solve("<img src=\"data:image/png;base64,\(png.base64EncodedString())\">")
        try require(answer == "1234")
        DiagnosticLog.add("probe vision-png passed")

        var normal = try client([panel, captcha, success])
        let outcome = try await normal.checkIn()
        try require(outcome.message == "签到成功")
        try require(ProbeHTTP.methods == ["GET", "GET", "POST"] && ProbeHTTP.replies.isEmpty)
        try require(normal.cookieHeader == "session=rotated")
        DiagnosticLog.add("probe normal-checkin passed")

        var retry = try client([panel, captcha, rejected, panel, captcha, success])
        _ = try await retry.checkIn()
        try require(ProbeHTTP.methods == ["GET", "GET", "POST", "GET", "GET", "POST"] && ProbeHTTP.replies.isEmpty)
        DiagnosticLog.add("probe captcha-retry passed")

        var uncertain = try client([panel, captcha, .init(body: "", error: URLError(.networkConnectionLost))])
        do {
            _ = try await uncertain.checkIn()
            throw ProbeFailure.assertion
        } catch CheckInError.network(safeToRetry: false) {
            try require(ProbeHTTP.methods == ["GET", "GET", "POST"] && ProbeHTTP.replies.isEmpty)
        }
        DiagnosticLog.add("probe post-not-retried passed")

        let sensitive = "do-not-log-this-session-or-challenge"
        let response = HTTPURLResponse(url: URL(string: "https://example.invalid/auth/captcha")!,
                                       statusCode: 200, httpVersion: nil, headerFields: nil)!
        let data = try JSONSerialization.data(withJSONObject: ["ret": 0, "msg": "请先完成人机交互验证 " + sensitive,
            "svg": "", "challenge": sensitive, "unexpected_secret_key": sensitive])
        let summary = CaptchaInspection.summarize(data, response: response, stage: "captcha")
        let encoded = try JSONSerialization.data(withJSONObject: summary)
        try require(!String(decoding: encoded, as: UTF8.self).contains(sensitive))
        try require(!String(decoding: encoded, as: UTF8.self).contains("unexpected_secret_key"))
        try require(summary["messageCategory"] as? String == "interaction-required")
        try require(summary["retClass"] as? String == "zero")
        try require(summary["clientCaptchaGuardPasses"] as? Bool == false)
        let reason = "通过云服务器或托管流水线发起自动化签到请求"
        try require(CaptchaInspection.redactMessage(reason, sensitiveValues: []) == reason)
        let redacted = CaptchaInspection.redactMessage(
            "请稍后再试\nuid=1234 user@example.com 192.0.2.5 https://example.invalid/private token=abcd " + sensitive,
            sensitiveValues: [sensitive, "example-cookie-value"])
        for secret in [sensitive, "1234", "user@example.com", "192.0.2.5", "https://example.invalid/private", "abcd", "\n"] {
            try require(!redacted.contains(secret))
        }
        let shortCookie = CaptchaInspection.redactMessage("拒绝 k9", sensitiveValues: ["k9"])
        try require(!shortCookie.contains("k9"))
        try require(CaptchaInspection.redactMessage(String(repeating: "测", count: 400), sensitiveValues: []).count == 321)
        try require(!CaptchaInspection.redactMessage("\u{0060}\u{0060}\u{0060}::error::\n消息", sensitiveValues: []).contains("::error::"))
        DiagnosticLog.add("probe inspection-redaction passed")

        ProbeHTTP.replies = [panel, success]
        ProbeHTTP.methods = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProbeHTTP.self]
        let inspection = try await CaptchaInspection.run(settings: Probe.settings(site: "https://example.invalid", cookie: "session=test"),
                                                         configuration: configuration)
        try require(ProbeHTTP.methods == ["GET", "GET"] && ProbeHTTP.replies.isEmpty)
        try require(inspection.cookie == "session=rotated")
        try require(inspection.metadata.count == 2)
        DiagnosticLog.add("probe inspection-read-only passed")
    }

    private static func readablePNG() throws -> Data {
        guard let context = CGContext(data: nil, width: 240, height: 80, bitsPerComponent: 8,
            bytesPerRow: 240 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ProbeFailure.assertion }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 240, height: 80))
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 48, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "1234", attributes: attributes))
        context.textPosition = CGPoint(x: 30, y: 20)
        CTLineDraw(line, context)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil),
              let image = context.makeImage() else { throw ProbeFailure.assertion }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ProbeFailure.assertion }
        return data as Data
    }
}
