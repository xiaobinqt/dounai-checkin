import Foundation
import BackgroundTasks

enum BackgroundScheduler {
    static let identifier = "com.dounai.checkin.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    static func scheduleNext(_ settings: AppSettingsSnapshot) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        guard settings.automaticEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = nextDate(time: settings.checkInTime)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        let settings = AppSettingsSnapshot.stored()
        scheduleNext(settings)
        let operation = Task {
            do {
                let outcome = try await CheckInService.run(settings)
                KeychainStore.write(outcome.cookie, for: "site_cookie")
                UserDefaults.standard.set(outcome.message, forKey: "last_result")
                UserDefaults.standard.set(Date(), forKey: "last_result_at")
                try? await BarkClient.send(title: "豆奶签到成功", body: outcome.message, settings: settings)
                task.setTaskCompleted(success: true)
            } catch {
                let message = error.localizedDescription
                UserDefaults.standard.set(message, forKey: "last_result")
                UserDefaults.standard.set(Date(), forKey: "last_result_at")
                let title = error is CheckInError ? "豆奶签到提醒" : "豆奶签到失败"
                try? await BarkClient.send(title: title, body: message, settings: settings)
                task.setTaskCompleted(success: false)
            }
        }
        task.expirationHandler = { operation.cancel() }
    }

    private static func nextDate(time: String) -> Date {
        let values = time.split(separator: ":").compactMap { Int($0) }
        let hour = values.count > 0 ? values[0] : 9
        let minute = values.count > 1 ? values[1] : 17
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let now = Date()
        let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(86_400)
    }
}
