import Foundation
import UIKit
import Vision

enum CheckInError: LocalizedError {
    case message(String)
    case sessionExpired(String)

    var errorDescription: String? {
        switch self {
        case .message(let text), .sessionExpired(let text): return text
        }
    }
}

enum CaptchaSolver {
    private static let replacements: [(String, String)] = [
        (" ", ""), ("　", ""), ("×", "*"), ("✕", "*"), ("✖", "*"), ("＊", "*"),
        ("x", "*"), ("X", "*"), ("乘", "*"), ("÷", "/"), ("／", "/"), ("除", "/"),
        ("＋", "+"), ("加", "+"), ("−", "-"), ("－", "-"), ("减", "-"),
        ("＝", "="), ("?", ""), ("？", ""), ("零", "0"), ("〇", "0"),
        ("一", "1"), ("壹", "1"), ("二", "2"), ("两", "2"), ("贰", "2"), ("貳", "2"),
        ("三", "3"), ("叁", "3"), ("參", "3"), ("四", "4"), ("肆", "4"),
        ("五", "5"), ("伍", "5"), ("六", "6"), ("陆", "6"), ("七", "7"),
        ("柒", "7"), ("八", "8"), ("捌", "8"), ("九", "9"), ("玖", "9"),
        ("０", "0"), ("１", "1"), ("２", "2"), ("３", "3"), ("４", "4"),
        ("５", "5"), ("６", "6"), ("７", "7"), ("８", "8"), ("９", "9")
    ]

    static func solve(_ markup: String) async throws -> String {
        if markup.range(of: "<svg", options: .caseInsensitive) != nil {
            return try evaluate(try SVGTextParser.text(from: markup))
        }
        guard let expression = try await recognizeImage(in: markup) else {
            throw CheckInError.message("验证码图片无法识别")
        }
        return try evaluate(expression)
    }

    static func evaluate(_ raw: String) throws -> String {
        var normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        replacements.forEach { normalized = normalized.replacingOccurrences(of: $0.0, with: $0.1) }
        normalized = normalized.replacingOccurrences(of: "\n", with: "")
        if normalized.hasSuffix("=") { normalized.removeLast() }
        if normalized.range(of: #"^[0-9]{4}$"#, options: .regularExpression) != nil { return normalized }

        let regex = try NSRegularExpression(pattern: #"^([0-9]{1,2})([+\-*/])([0-9]{1,2})$"#)
        let range = NSRange(normalized.startIndex..., in: normalized)
        guard let match = regex.firstMatch(in: normalized, range: range),
              let leftRange = Range(match.range(at: 1), in: normalized),
              let opRange = Range(match.range(at: 2), in: normalized),
              let rightRange = Range(match.range(at: 3), in: normalized),
              let left = Int(normalized[leftRange]), let right = Int(normalized[rightRange]) else {
            throw CheckInError.message("验证码不是四位数字或简单算式")
        }
        let value: Int
        switch normalized[opRange] {
        case "+": value = left + right
        case "-": value = left - right
        case "*": value = left * right
        case "/":
            guard right != 0, left % right == 0 else {
                throw CheckInError.message("验证码除法结果不是整数")
            }
            value = left / right
        default: throw CheckInError.message("验证码运算符无法识别")
        }
        return String(value)
    }

    private static func recognizeImage(in markup: String) async throws -> String? {
        let regex = try NSRegularExpression(pattern: #"data:image/[^;]+;base64,([A-Za-z0-9+/=]+)"#, options: .caseInsensitive)
        let range = NSRange(markup.startIndex..., in: markup)
        guard let match = regex.firstMatch(in: markup, range: range),
              let valueRange = Range(match.range(at: 1), in: markup),
              let data = Data(base64Encoded: String(markup[valueRange])),
              let image = UIImage(data: data), let cgImage = image.cgImage else { return nil }

        return try await Task.detached(priority: .userInitiated) {
            var candidates: [String] = []
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                candidates = observations.compactMap { $0.topCandidates(3).first?.string }
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
            let joined = candidates.joined()
            if (try? evaluate(joined)) != nil { return joined }
            return candidates.first { (try? evaluate($0)) != nil }
        }.value
    }
}

private final class SVGTextParser: NSObject, XMLParserDelegate {
    private var insideText = false
    private var output = ""

    static func text(from markup: String) throws -> String {
        guard let data = markup.data(using: .utf8) else {
            throw CheckInError.message("SVG 验证码编码无效")
        }
        let delegate = SVGTextParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), !delegate.output.isEmpty else {
            throw CheckInError.message("SVG 验证码没有可识别文字")
        }
        return delegate.output
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName.lowercased() == "text" { insideText = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideText { output += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName.lowercased() == "text" { insideText = false }
    }
}
