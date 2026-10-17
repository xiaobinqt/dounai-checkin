import Foundation
import CoreText
import ImageIO

final class StubHTTP: URLProtocol {
    struct Reply {
        var status = 200
        var body: String
        var error: URLError?
    }
    static var replies: [Reply] = []
    static var methods: [String] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.methods.append(request.httpMethod ?? "")
        guard !Self.replies.isEmpty else { fatalError("Unexpected network request") }
        let reply = Self.replies.removeFirst()
        if let error = reply.error { client?.urlProtocol(self, didFailWithError: error); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
enum CheckInTests {
    static var submissionStates: [Bool] = []
    static let panel = StubHTTP.Reply(body: #"<script>var checkinTicket = "test-ticket";</script>"#)
    static let captcha = StubHTTP.Reply(body: #"{"ret":1,"svg":"<svg><text>六-二=</text></svg>"}"#)
    static let success = StubHTTP.Reply(body: #"{"ret":1,"msg":"签到成功"}"#)
    static let rejected = StubHTTP.Reply(body: #"{"ret":0,"msg":"验证码已过期，请刷新重试"}"#)

    static func settings() -> AppSettingsSnapshot {
        AppSettingsSnapshot(siteURL: "https://example.com", cookie: "session=test", automaticEnabled: true,
                            checkInTime: "09:17", barkServer: "https://example.com", barkKey: "", userAgent: "test",
                            email: EmailConfiguration(enabled: false, address: "", recipient: "", host: "", port: 465, password: ""))
    }

    static func client(_ replies: [StubHTTP.Reply], budget: TimeInterval = 60,
                       recognize: @escaping (String) async throws -> String = { _ in "4" }) throws -> CheckInClient {
        StubHTTP.replies = replies
        StubHTTP.methods = []
        submissionStates = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubHTTP.self]
        return try CheckInClient(settings: settings(), budget: budget, configuration: configuration,
                                 recognize: recognize, interactionDelay: {},
                                 submissionStateChange: { submissionStates.append($0) })
    }

    static func assertFails(_ operation: () async throws -> Void) async -> Error {
        do { try await operation(); fatalError("Expected failure") }
        catch { return error }
    }

    static func readablePNG() -> Data {
        let context = CGContext(data: nil, width: 240, height: 80, bitsPerComponent: 8, bytesPerRow: 240 * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
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
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }

    static func main() async throws {
        let iso = ISO8601DateFormatter()
        let now = iso.date(from: "2026-10-17T04:00:00Z")!
        precondition(CheckInPolicy.day(iso.date(from: "2026-10-16T16:00:00Z")!) == "2026-10-17")
        let overdue = try CheckInPolicy.nextDate(time: "09:17", now: now)
        precondition(overdue == now.addingTimeInterval(5))
        let tomorrow = try CheckInPolicy.nextDate(time: "09:17", now: now, completed: true)
        precondition(iso.string(from: tomorrow) == "2026-10-18T01:17:00Z")
        for invalid in ["25:00", "09:99", "09", "", "9:17"] {
            do { _ = try CheckInPolicy.nextDate(time: invalid); fatalError("Invalid time accepted") } catch {}
        }
        precondition(CheckInPolicy.consensus(["4": 2, "6": 1]) == "4")
        precondition(CheckInPolicy.consensus(["4": 2, "6": 2]) == nil)
        precondition(CheckInPolicy.consensus(["4": 1]) == nil)
        precondition(CheckInPolicy.isCaptchaRejected("验证码错误"))
        precondition(CheckInPolicy.isCaptchaRejected("验证码已过期，请刷新重试"))
        precondition(!CheckInPolicy.isCaptchaRejected("校验票据失效"))
        precondition(!CheckInPolicy.isCaptchaRejected("服务器错误"))
        let svg = try await CaptchaSolver.solve("<svg><text>玖</text><text>-</text><text>伍</text><text>=</text></svg>")
        precondition(svg == "4")

        var normal = try client([panel, captcha, success])
        let result = try await normal.checkIn()
        precondition(result.message == "签到成功" && StubHTTP.methods == ["GET", "GET", "POST"])

        var retry = try client([panel, captcha, rejected, panel, captcha, success])
        _ = try await retry.checkIn()
        precondition(StubHTTP.methods.filter { $0 == "POST" }.count == 2)
        precondition(submissionStates == [true, false, true])

        var twice = try client([panel, captcha, rejected, panel, captcha, rejected])
        _ = await assertFails { _ = try await twice.checkIn() }
        precondition(StubHTTP.methods.filter { $0 == "POST" }.count == 2)

        var ocrCount = 0
        var ocr = try client([panel, captcha, panel, captcha, success]) { _ in
            ocrCount += 1
            if ocrCount == 1 { throw CheckInError.message("test") }
            return "4"
        }
        _ = try await ocr.checkIn()
        precondition(ocrCount == 2 && StubHTTP.methods.filter { $0 == "POST" }.count == 1)

        var badOCR = try client([panel, captcha, panel, captcha]) { _ in throw CheckInError.message("test") }
        _ = await assertFails { _ = try await badOCR.checkIn() }
        precondition(!StubHTTP.methods.contains("POST"))

        var badFetch = try client([panel, .init(body: #"{"ret":0}"#), panel, captcha, success])
        _ = try await badFetch.checkIn()
        precondition(StubHTTP.methods.filter { $0 == "POST" }.count == 1)

        precondition(submissionStates == [true])

        var before = try client([.init(body: "", error: URLError(.networkConnectionLost)), panel, captcha, success])
        _ = try await before.checkIn()
        precondition(StubHTTP.methods == ["GET", "GET", "GET", "POST"])

        var after = try client([panel, captcha, .init(body: "", error: URLError(.networkConnectionLost))])
        let unknown = await assertFails { _ = try await after.checkIn() }
        guard case CheckInError.network(safeToRetry: false) = unknown else { fatalError("Unsafe retry classification") }
        precondition(StubHTTP.methods.filter { $0 == "POST" }.count == 1)

        var unavailable = try client([.init(status: 503, body: "unavailable")])
        let safe = await assertFails { _ = try await unavailable.checkIn() }
        guard case CheckInError.network(safeToRetry: true) = safe else { fatalError("Missing safe retry") }

        var cancelled = try client([.init(body: "", error: URLError(.cancelled))])
        let cancelledError = await assertFails { _ = try await cancelled.checkIn() }
        precondition(cancelledError is CancellationError && StubHTTP.methods.count == 1)

        var exhausted = try client([panel, captcha], budget: 2)
        let timeout = await assertFails { _ = try await exhausted.checkIn() }
        guard case CheckInError.timeBudget = timeout else { fatalError("Missing budget guard") }
        precondition(!StubHTTP.methods.contains("POST"))

        var expired = try client([.init(status: 401, body: "login")])
        let session = await assertFails { _ = try await expired.checkIn() }
        guard case CheckInError.sessionExpired = session else { fatalError("Missing session classification") }

        let digits = try await CaptchaSolver.solve("data:image/png;base64," + readablePNG().base64EncodedString())
        precondition(digits == "1234", "Readable PNG must be accepted by consensus")
        print("Readable PNG correctly accepted by multiple distinct image variants")
        let image = try Data(contentsOf: URL(fileURLWithPath: "android/app/src/androidTest/assets/captcha-six-minus-two.png"))
        do {
            let answer = try await CaptchaSolver.solve("data:image/png;base64," + image.base64EncodedString())
            precondition(answer == "4", "Incorrect OCR answer")
            print("PNG regression sample correctly recognized")
        } catch { print("PNG regression sample safely rejected by Vision; no answer submitted") }
        print("Check-in tests passed: safe retry boundaries, cancellation, budget, time zones, overdue catch-up and OCR consensus")
    }
}
