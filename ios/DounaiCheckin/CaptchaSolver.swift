import Foundation
import ImageIO
import Vision

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
        guard let answer = try await recognizeImage(in: markup) else {
            throw CheckInError.message("验证码无法得到可靠的识别共识，已停止提交")
        }
        return answer
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
              let data = Data(base64Encoded: String(markup[valueRange])), data.count <= 2 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
              cgImage.width <= 1024, cgImage.height <= 1024 else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = false
        let operation = Task.detached(priority: .userInitiated) { () throws -> String? in
            var votes: [String: Int] = [:]
            let images = try variants(cgImage)
            for image in images {
                try Task.checkCancellation()
                try VNImageRequestHandler(cgImage: image).perform([request])
                let observations = request.results ?? []
                let joined = observations.compactMap { $0.topCandidates(1).first?.string }.joined()
                var candidates = [joined]
                if observations.count == 1 {
                    candidates += observations[0].topCandidates(3).filter { $0.confidence >= 0.4 }.map(\.string)
                }
                // A variant casts at most one vote; conflicting answers cast none.
                let answers = Set(candidates.compactMap { try? evaluate($0) })
                if answers.count == 1, let answer = answers.first { votes[answer, default: 0] += 1 }
            }
            let answer = CheckInPolicy.consensus(votes)
            DiagnosticLog.add("captcha variants=\(images.count) agreeingVariants=\(votes.values.max() ?? 0) accepted=\(answer != nil)")
            return answer
        }
        return try await withTaskCancellationHandler {
            let result = try await operation.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            request.cancel()
            operation.cancel()
        }
    }

    private static func variants(_ image: CGImage) throws -> [CGImage] {
        let width = image.width * 3, height = image.height * 3
        var pixels = [UInt8](repeating: 255, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return false }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw CheckInError.message("验证码预处理失败") }
        // Vision works more reliably with dark text on a light background.
        if pixels.reduce(0, { $0 + Int($1) }) / pixels.count < 128 {
            pixels = pixels.map { 255 - $0 }
        }
        var histogram = [Int](repeating: 0, count: 256)
        for pixel in pixels { histogram[Int(pixel)] += 1 }
        let total = pixels.count
        let sum = histogram.enumerated().reduce(0.0) { $0 + Double($1.offset * $1.element) }
        var count = 0, partial = 0.0, best = -1.0, threshold = 127
        for index in 0..<255 {
            count += histogram[index]
            partial += Double(index * histogram[index])
            guard count > 0, count < total else { continue }
            let difference = partial / Double(count) - (sum - partial) / Double(total - count)
            let score = Double(count) * Double(total - count) * difference * difference
            if score > best { best = score; threshold = index }
        }
        var seen = Set<Data>()
        var result: [CGImage] = []
        let versions = [pixels] + [-20, 0, 20].map { offset in
            pixels.map { Int($0) <= max(0, min(254, threshold + offset)) ? UInt8(0) : UInt8(255) }
        }
        for version in versions {
            let data = Data(version)
            guard seen.insert(data).inserted else { continue }
            let paddedWidth = width + 48, paddedHeight = height + 48
            var padded = [UInt8](repeating: 255, count: paddedWidth * paddedHeight)
            for row in 0..<height {
                padded.replaceSubrange(((row + 24) * paddedWidth + 24)..<((row + 24) * paddedWidth + 24 + width),
                                       with: version[(row * width)..<((row + 1) * width)])
            }
            guard let provider = CGDataProvider(data: Data(padded) as CFData),
                  let variant = CGImage(width: paddedWidth, height: paddedHeight, bitsPerComponent: 8, bitsPerPixel: 8,
                                        bytesPerRow: paddedWidth, space: CGColorSpaceCreateDeviceGray(),
                                        bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
                                        decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { continue }
            result.append(variant)
        }
        return result
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
