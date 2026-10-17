import Foundation

enum CheckInError: LocalizedError {
    case message(String)
    case sessionExpired(String)
    case network(safeToRetry: Bool)
    case busy
    case timeBudget

    var errorDescription: String? {
        switch self {
        case .message(let text), .sessionExpired(let text): return text
        case .network(true): return "提交前网络暂时不可用，可稍后安全重试"
        case .network(false): return "提交后网络中断，签到状态未知；请查看网页结果，不会自动重复提交"
        case .busy: return "已有签到任务正在执行，请稍后查看结果"
        case .timeBudget: return "本次后台时间不足，已停止继续请求"
        }
    }
}

enum CheckInPolicy {
    static func day(_ date: Date = Date()) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "Asia/Shanghai")
        format.dateFormat = "yyyy-MM-dd"
        return format.string(from: date)
    }

    static func nextDate(time: String, now: Date = Date(), completed: Bool = false) throws -> Date {
        guard time.range(of: #"^(?:[01][0-9]|2[0-3]):[0-5][0-9]$"#, options: .regularExpression) != nil else {
            throw CheckInError.message("签到时间格式无效，请重新保存设置")
        }
        let parts = time.split(separator: ":").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let today = calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: now)!
        if completed { return calendar.date(byAdding: .day, value: 1, to: today)! }
        // An overdue, unfinished day gets a catch-up opportunity, not silently tomorrow.
        return today > now ? today : now.addingTimeInterval(5)
    }

    static func isCaptchaRejected(_ message: String) -> Bool {
        let lower = message.lowercased()
        let captcha = message.contains("验证码") || lower.contains("captcha")
        return captcha && ["错误", "不正确", "失败", "过期", "超时", "刷新", "invalid", "expired", "incorrect"]
            .contains { lower.contains($0) }
    }

    static func consensus(_ votes: [String: Int]) -> String? {
        guard let best = votes.values.max(), best >= 2 else { return nil }
        let winners = votes.filter { $0.value == best }
        return winners.count == 1 ? winners.first?.key : nil
    }
}
