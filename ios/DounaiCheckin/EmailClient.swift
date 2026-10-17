import Foundation
import CFNetwork

struct EmailConfiguration: Sendable {
    let enabled: Bool
    let address: String
    let recipient: String
    let host: String
    let port: Int
    let password: String

    func validate() throws {
        guard enabled else { return }
        guard Self.isMailbox(address), Self.isMailbox(recipient) else {
            throw EmailError.message("请填写有效的发件和收件邮箱；仅支持单个邮箱地址")
        }
        guard !host.isEmpty, host.utf8.count <= 253,
              host.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-").contains($0) }),
              !host.hasPrefix("."), !host.hasSuffix("."), !host.contains("..") else {
            throw EmailError.message("SMTP 主机请填写域名，例如 smtp.qq.com，不要包含协议或端口")
        }
        guard port == 465 || port == 587 else {
            throw EmailError.message("SMTP 支持 TLS 465 或 STARTTLS 587")
        }
        guard !password.isEmpty, password.utf8.count <= 4096 else {
            throw EmailError.message("请填写 SMTP 授权码")
        }
    }

    static func isMailbox(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard value.utf8.count <= 254, parts.count == 2, !parts[0].isEmpty,
              parts[0].utf8.count <= 64, !parts[0].hasPrefix("."), !parts[0].hasSuffix("."),
              !parts[0].contains("..") else { return false }
        let local = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.!#$%&'*+/=?^_`{|}~-")
        let domain = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        let labels = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        return parts[0].unicodeScalars.allSatisfy(local.contains)
            && labels.count >= 2 && labels.allSatisfy {
                !$0.isEmpty && $0.utf8.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-")
                    && $0.unicodeScalars.allSatisfy(domain.contains)
            }
    }
}

enum EmailError: LocalizedError {
    case message(String)
    case transport
    case rejected(Int)

    var errorDescription: String? {
        switch self {
        case .message(let value): return value
        case .transport: return "SMTP 连接中断、超时或 TLS 验证失败"
        case .rejected(let code): return "SMTP 服务器拒绝请求（响应码 \(code)）"
        }
    }
}

enum EmailClient {
    static func send(title: String, body: String, configuration: EmailConfiguration) async throws {
        guard configuration.enabled else { return }
        try configuration.validate()
        // Stream operations stay on a worker thread; cancellation closes them promptly.
        let operation = Task.detached(priority: .utility) {
            let wire = try SMTPStream(host: configuration.host, port: configuration.port)
            try SMTPDelivery.send(configuration: configuration, title: title, body: body, wire: wire)
        }
        try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: {
            operation.cancel()
        }
    }
}

protocol SMTPTransport: AnyObject {
    func open(implicitTLS: Bool) throws
    func enableTLS() throws
    func write(_ text: String) throws
    func readLine() throws -> String
    func close()
}

enum SMTPDelivery {
    static func send(configuration: EmailConfiguration, title: String, body: String,
                     wire: SMTPTransport) throws {
        try configuration.validate()
        var stage = "连接服务器"
        var submitted = false
        defer { wire.close() }
        do {
            try wire.open(implicitTLS: configuration.port == 465)
            try expect(wire, code: 220)
            stage = "协商连接"
            try wire.write("EHLO dounai-checkin\r\n")
            let capabilities = try expect(wire, code: 250)
            if configuration.port == 587 {
                guard capabilities.contains(where: {
                    $0.dropFirst(4).trimmingCharacters(in: .whitespaces).uppercased() == "STARTTLS"
                }) else { throw EmailError.message("SMTP 服务器未提供 STARTTLS，已停止发送") }
                stage = "建立 STARTTLS"
                try wire.write("STARTTLS\r\n")
                try expect(wire, code: 220)
                try wire.enableTLS()
                try wire.write("EHLO dounai-checkin\r\n")
                try expect(wire, code: 250)
            }
            stage = "登录"
            try command(wire, "AUTH LOGIN", code: 334)
            try command(wire, base64(configuration.address), code: 334)
            try command(wire, base64(configuration.password), code: 235)
            stage = "准备邮件"
            try command(wire, "MAIL FROM:<\(configuration.address)>", code: 250)
            try wire.write("RCPT TO:<\(configuration.recipient)>\r\n")
            try expect(wire, codes: [250, 251])
            try command(wire, "DATA", code: 354)
            stage = "提交邮件"
            submitted = true
            try wire.write(message(configuration: configuration, title: title, body: body) + ".\r\n")
            try expect(wire, code: 250)
            // The server has accepted the message; QUIT failure cannot undo that.
            try? wire.write("QUIT\r\n")
        } catch let error as EmailError {
            switch error {
            case .transport where submitted:
                throw EmailError.message("SMTP 提交时连接中断，发送状态未知，请检查收件箱；不会自动重发")
            default:
                throw EmailError.message("SMTP \(stage)失败：\(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    static func expect(_ wire: SMTPTransport, code: Int) throws -> [String] {
        try expect(wire, codes: [code])
    }

    @discardableResult
    private static func expect(_ wire: SMTPTransport, codes: [Int]) throws -> [String] {
        var response: [String] = []
        var responseCode: Int?
        for _ in 0..<64 {
            let line = try wire.readLine()
            let bytes = Array(line.utf8)
            guard bytes.count >= 4, bytes.count <= 8192,
                  bytes.prefix(3).allSatisfy({ (48...57).contains($0) }),
                  bytes[3] == 32 || bytes[3] == 45,
                  let code = Int(String(decoding: bytes.prefix(3), as: UTF8.self)),
                  responseCode == nil || responseCode == code else {
                throw EmailError.message("SMTP 响应格式无效")
            }
            responseCode = code
            response.append(line)
            if bytes[3] == 32 {
                guard codes.contains(code) else { throw EmailError.rejected(code) }
                return response
            }
        }
        throw EmailError.message("SMTP 响应过长")
    }

    private static func command(_ wire: SMTPTransport, _ text: String, code: Int) throws {
        try wire.write(text + "\r\n")
        try expect(wire, code: code)
    }

    static func message(configuration: EmailConfiguration, title: String, body: String) -> String {
        let subject = title.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        let encodedSubject = base64(String(subject.prefix(36)))
        let content = Data(body.utf8).base64EncodedString(options: [.lineLength64Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return "From: <\(configuration.address)>\r\nTo: <\(configuration.recipient)>\r\n"
            + "Date: \(formatter.string(from: Date()))\r\nMessage-ID: <\(UUID().uuidString)@dounai-checkin.local>\r\n"
            + "Subject: =?UTF-8?B?\(encodedSubject)?=\r\nMIME-Version: 1.0\r\n"
            + "Content-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n\(content)\r\n"
    }

    private static func base64(_ text: String) -> String { Data(text.utf8).base64EncodedString() }
}

final class SMTPStream: SMTPTransport {
    private let input: CFReadStream
    private let output: CFWriteStream
    private let host: String
    private let deadline = ProcessInfo.processInfo.systemUptime + 25
    private var buffer = Data()

    init(host: String, port: Int) throws {
        self.host = host
        var read: Unmanaged<CFReadStream>?
        var write: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocketToHost(nil, host as CFString, UInt32(port), &read, &write)
        guard let read, let write else { throw EmailError.transport }
        input = read.takeRetainedValue()
        output = write.takeRetainedValue()
    }

    func open(implicitTLS: Bool) throws {
        if implicitTLS { try enableTLS() }
        CFReadStreamScheduleWithRunLoop(input, CFRunLoopGetCurrent(), .defaultMode)
        CFWriteStreamScheduleWithRunLoop(output, CFRunLoopGetCurrent(), .defaultMode)
        guard CFReadStreamOpen(input), CFWriteStreamOpen(output) else { throw EmailError.transport }
    }

    func enableTLS() throws {
        guard buffer.isEmpty else { throw EmailError.message("STARTTLS 前收到多余数据，已停止发送") }
        let settings: [String: Any] = [
            kCFStreamSSLLevel as String: kCFStreamSocketSecurityLevelNegotiatedSSL,
            kCFStreamSSLPeerName as String: host,
            kCFStreamSSLValidatesCertificateChain as String: true
        ]
        guard CFReadStreamSetProperty(input, CFStreamPropertyKey(kCFStreamPropertySSLSettings), settings as CFDictionary) else {
            throw EmailError.transport
        }
    }

    func write(_ text: String) throws {
        let data = Array(text.utf8)
        var offset = 0
        while offset < data.count {
            try wait { CFWriteStreamCanAcceptBytes(self.output) }
            let count = data.withUnsafeBufferPointer {
                CFWriteStreamWrite(output, $0.baseAddress!.advanced(by: offset), data.count - offset)
            }
            guard count > 0 else { throw EmailError.transport }
            offset += count
        }
    }

    func readLine() throws -> String {
        while true {
            if let end = buffer.range(of: Data([13, 10])) {
                guard end.lowerBound - buffer.startIndex <= 8192 else { throw EmailError.message("SMTP 响应过长") }
                let line = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                buffer.removeSubrange(..<end.upperBound)
                return line
            }
            guard buffer.count <= 8192 else { throw EmailError.message("SMTP 响应过长") }
            try wait { CFReadStreamHasBytesAvailable(self.input) }
            var bytes = [UInt8](repeating: 0, count: 4096)
            let count = CFReadStreamRead(input, &bytes, bytes.count)
            guard count > 0 else { throw EmailError.transport }
            buffer.append(contentsOf: bytes.prefix(count))
        }
    }

    private func wait(until ready: () -> Bool) throws {
        while true {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < deadline,
                  ![.error, .closed, .atEnd].contains(CFReadStreamGetStatus(input)),
                  ![.error, .closed, .atEnd].contains(CFWriteStreamGetStatus(output)) else {
                throw EmailError.transport
            }
            if ready() { return }
            CFRunLoopRunInMode(.defaultMode, 0.01, false)
            Thread.sleep(forTimeInterval: 0.005)
        }
    }

    func close() {
        CFReadStreamClose(input)
        CFWriteStreamClose(output)
        CFReadStreamUnscheduleFromRunLoop(input, CFRunLoopGetCurrent(), .defaultMode)
        CFWriteStreamUnscheduleFromRunLoop(output, CFRunLoopGetCurrent(), .defaultMode)
    }
}
