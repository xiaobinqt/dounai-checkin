import Foundation

private final class FakeSMTP: SMTPTransport {
    var replies: [String]
    var writes: [String] = []
    var events: [String] = []
    var failTLS = false
    var failQuit = false
    var closed = false

    init(_ replies: [String]) { self.replies = replies }
    func open(implicitTLS: Bool) throws { events.append(implicitTLS ? "implicitTLS" : "plain") }
    func enableTLS() throws {
        events.append("upgradeTLS")
        if failTLS { throw EmailError.transport }
    }
    func write(_ text: String) throws {
        events.append(text)
        writes.append(text)
        if failQuit && text == "QUIT\r\n" { throw EmailError.transport }
    }
    func readLine() throws -> String {
        guard !replies.isEmpty else { throw EmailError.transport }
        return replies.removeFirst()
    }
    func close() { closed = true }
}

@main
enum EmailClientTests {
    static func configuration(port: Int = 465, address: String = "sender@example.com",
                              recipient: String = "receiver@example.com") -> EmailConfiguration {
        EmailConfiguration(enabled: true, address: address, recipient: recipient,
                           host: "smtp.example.com", port: port, password: "secret-do-not-log")
    }

    static func fails(containing text: String, _ operation: () throws -> Void) {
        do { try operation(); fatalError("Expected failure: \(text)") }
        catch {
            precondition(error.localizedDescription.contains(text), error.localizedDescription)
            precondition(!error.localizedDescription.contains("secret-do-not-log"))
        }
    }

    static func main() async throws {
        if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--probe" {
            let port = Int(CommandLine.arguments[3])!
            let stream = try SMTPStream(host: CommandLine.arguments[2], port: port)
            defer { stream.close() }
            try stream.open(implicitTLS: port == 465)
            try SMTPDelivery.expect(stream, code: 220)
            try stream.write("EHLO dounai-checkin\r\n")
            try SMTPDelivery.expect(stream, code: 250)
            if port == 587 {
                try stream.write("STARTTLS\r\n")
                try SMTPDelivery.expect(stream, code: 220)
                try stream.enableTLS()
                try stream.write("EHLO dounai-checkin\r\n")
                try SMTPDelivery.expect(stream, code: 250)
            }
            print("TLS and SMTP greeting verified; no authentication or email sent")
            return
        }

        let accepted = ["334 username", "334 password", "235 authenticated", "250 sender", "251 forwarded", "354 data", "250 accepted"]
        let tls = FakeSMTP(["220 ready", "250-server", "250 AUTH LOGIN"] + accepted)
        tls.failQuit = true
        try SMTPDelivery.send(configuration: configuration(), title: "签到成功", body: "中文\n.\nhello", wire: tls)
        precondition(tls.events.first == "implicitTLS" && tls.closed)
        precondition(tls.writes.filter { $0.hasPrefix("From:") }.count == 1)
        precondition(tls.writes.contains("RCPT TO:<receiver@example.com>\r\n"))
        let mime = tls.writes.first { $0.hasPrefix("From:") }!
        precondition(mime.contains("Content-Transfer-Encoding: base64\r\n"))
        precondition(mime.hasSuffix("\r\n.\r\n"))
        let content = mime.components(separatedBy: "\r\n\r\n")[1]
            .replacingOccurrences(of: "\r\n.\r\n", with: "")
        precondition(String(data: Data(base64Encoded: content, options: .ignoreUnknownCharacters)!, encoding: .utf8) == "中文\n.\nhello")

        let startTLS = FakeSMTP(["220 ready", "250-server", "250 STARTTLS", "220 upgrade", "250 AUTH LOGIN"] + accepted)
        try SMTPDelivery.send(configuration: configuration(port: 587), title: "测试", body: "test", wire: startTLS)
        precondition(startTLS.events.first == "plain")
        let upgradeIndex = startTLS.events.firstIndex(of: "upgradeTLS")!
        let authIndex = startTLS.events.firstIndex(of: "AUTH LOGIN\r\n")!
        precondition(upgradeIndex < authIndex)
        precondition(startTLS.writes.filter { $0 == "EHLO dounai-checkin\r\n" }.count == 2)

        let noTLS = FakeSMTP(["220 ready", "250 AUTH LOGIN"])
        fails(containing: "未提供 STARTTLS") {
            try SMTPDelivery.send(configuration: configuration(port: 587), title: "t", body: "b", wire: noTLS)
        }
        precondition(!noTLS.writes.contains("AUTH LOGIN\r\n") && noTLS.closed)

        let badTLS = FakeSMTP(["220 ready", "250 STARTTLS", "220 upgrade"])
        badTLS.failTLS = true
        fails(containing: "TLS") {
            try SMTPDelivery.send(configuration: configuration(port: 587), title: "t", body: "b", wire: badTLS)
        }
        precondition(!badTLS.writes.contains("AUTH LOGIN\r\n"))

        let auth = FakeSMTP(["220 ready", "250 AUTH LOGIN", "334 u", "334 p", "535 denied"])
        fails(containing: "535") {
            try SMTPDelivery.send(configuration: configuration(), title: "t", body: "b", wire: auth)
        }
        precondition(!auth.writes.contains("DATA\r\n"))

        let unknown = FakeSMTP(["220 ready", "250 AUTH LOGIN"] + Array(accepted.dropLast()))
        fails(containing: "发送状态未知") {
            try SMTPDelivery.send(configuration: configuration(), title: "t", body: "b", wire: unknown)
        }
        precondition(unknown.writes.filter { $0.hasPrefix("From:") }.count == 1 && unknown.closed)

        let rejected = FakeSMTP(["220 ready", "250 AUTH LOGIN"] + Array(accepted.dropLast()) + ["550 denied"])
        fails(containing: "550") {
            try SMTPDelivery.send(configuration: configuration(), title: "t", body: "b", wire: rejected)
        }

        for invalid in ["250-begin", "250xinvalid", "250\ninvalid", "25 bad"] {
            fails(containing: invalid == "250-begin" ? "连接" : "格式") {
                try SMTPDelivery.expect(FakeSMTP([invalid]), code: 250)
            }
        }
        fails(containing: "格式") {
            try SMTPDelivery.expect(FakeSMTP(["250-more", "220 wrong"]), code: 250)
        }
        fails(containing: "过长") {
            try SMTPDelivery.expect(FakeSMTP(Array(repeating: "250-more", count: 64)), code: 250)
        }
        fails(containing: "邮箱") { try configuration(address: "a@example.com\r\nBcc:x@y.com").validate() }
        fails(containing: "邮箱") { try configuration(recipient: "a@b.com,b@c.com").validate() }
        fails(containing: "465") { try configuration(port: 25).validate() }
        print("SMTP tests passed: TLS ordering, fail-closed, AUTH errors, MIME, injection validation, strict responses, accepted/unknown delivery")
    }
}
