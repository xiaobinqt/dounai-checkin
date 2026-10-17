import Foundation
import BackgroundTasks
import UIKit

@MainActor
enum BackgroundScheduler {
    static let identifier = "com.dounai.checkin.refresh"
    private static var revision = 0

    static func register() {
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in handle(refreshTask) }
        }
        DiagnosticLog.add("background registration success=\(registered)")
    }

    static func scheduleNext(_ settings: AppSettingsSnapshot, force: Bool = false, notBefore: Date? = nil) {
        revision += 1
        let current = revision
        guard settings.automaticEnabled else { cancel(); return }
        if force, let target = notBefore {
            // Reserve a known next run synchronously before work/expiration can race.
            let request = BGAppRefreshTaskRequest(identifier: identifier)
            request.earliestBeginDate = target
            do {
                try BGTaskScheduler.shared.submit(request)
                UserDefaults.standard.set(settings.siteURL + "|" + settings.checkInTime, forKey: "schedule_signature")
                UserDefaults.standard.set(target, forKey: "planned_background_at")
                DiagnosticLog.add("background scheduled target=\(stamp(target)) forced=true")
            } catch {
                DiagnosticLog.add("background schedule failed code=\((error as NSError).code)")
            }
            return
        }
        Task {
            let pending = await requests()
            guard current == revision else { return }
            let defaults = UserDefaults.standard
            let today = CheckInPolicy.day()
            let done = (defaults.string(forKey: "last_success_day") == today && defaults.string(forKey: "last_success_site") == settings.siteURL)
                || (defaults.string(forKey: "auto_failure_day") == today && defaults.string(forKey: "auto_failure_site") == settings.siteURL)
                || (defaults.string(forKey: "uncertain_submission_day") == today && defaults.string(forKey: "uncertain_submission_site") == settings.siteURL)
            do {
                let target = try notBefore ?? CheckInPolicy.nextDate(time: settings.checkInTime, completed: done)
                let signature = settings.siteURL + "|" + settings.checkInTime
                if !force, defaults.string(forKey: "schedule_signature") == signature,
                   let existing = pending.first(where: { $0.identifier == identifier }),
                   (existing.earliestBeginDate ?? .distantPast) <= target {
                    DiagnosticLog.add("background pending request preserved target=\(stamp(existing.earliestBeginDate))")
                    return
                }
                let request = BGAppRefreshTaskRequest(identifier: identifier)
                request.earliestBeginDate = target
                // Replacing the same identifier avoids a cancel-then-submit gap.
                try BGTaskScheduler.shared.submit(request)
                defaults.set(signature, forKey: "schedule_signature")
                defaults.set(target, forKey: "planned_background_at")
                DiagnosticLog.add("background scheduled target=\(stamp(target)) forced=\(force)")
            } catch {
                DiagnosticLog.add("background schedule failed code=\((error as NSError).code)")
                defaults.set("后台计划登记失败，请检查后台 App 刷新权限及运行日志", forKey: "schedule_status")
            }
        }
    }

    static func cancel() {
        revision += 1
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        DiagnosticLog.add("background schedule cancelled")
    }

    private static func handle(_ task: BGAppRefreshTask) {
        DiagnosticLog.add("background launched")
        capture(reason: "background-launch")
        let settings = AppSettingsSnapshot.stored()
        let tomorrow = try? CheckInPolicy.nextDate(time: settings.checkInTime, completed: true)
        scheduleNext(settings, force: true, notBefore: tomorrow)
        BackgroundExecution(task: task).start()
    }

    static func capture(reason: String) {
        let app = UIApplication.shared
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        DiagnosticLog.add("state reason=\(reason) version=\(version) os=\(UIDevice.current.systemVersion) appState=\(app.applicationState.rawValue) refreshStatus=\(app.backgroundRefreshStatus.rawValue) lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled) protectedData=\(app.isProtectedDataAvailable)")
        Task {
            let pending = await requests()
            let own = pending.filter { $0.identifier == identifier }
            DiagnosticLog.add("background pending count=\(own.count) reason=\(reason)")
            for request in own { DiagnosticLog.add("background pending target=\(stamp(request.earliestBeginDate))") }
        }
    }

    private static func requests() async -> [BGTaskRequest] {
        await withCheckedContinuation { continuation in
            BGTaskScheduler.shared.getPendingTaskRequests { continuation.resume(returning: $0) }
        }
    }

    private static func stamp(_ date: Date?) -> String {
        date.map { ISO8601DateFormatter().string(from: $0) } ?? "immediate"
    }
}

@MainActor
private final class BackgroundExecution {
    private let task: BGAppRefreshTask
    private var operation: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var finished = false
    private let started = ProcessInfo.processInfo.systemUptime

    init(task: BGAppRefreshTask) { self.task = task }

    func start() {
        task.expirationHandler = { Task { @MainActor in self.expire(reason: "system-expiration") } }
        operation = Task {
            guard !finished, !Task.isCancelled else {
                DiagnosticLog.add("background work skipped expired-before-start")
                return
            }
            let result = await execute()
            finish(success: result)
        }
        guard !finished else {
            operation?.cancel()
            operation = nil
            return
        }
        watchdog = Task {
            do { try await Task.sleep(nanoseconds: 25_000_000_000) }
            catch { return }
            expire(reason: "25-second-budget")
        }
    }

    private func execute() async -> Bool {
        let settings = AppSettingsSnapshot.stored()
        do {
            let outcome = try await CheckInService.run(settings, automatic: true)
            try Task.checkCancellation()
            guard !outcome.skipped else { return true }
            record(outcome.message)
            let errors = await NotificationSender.send(title: "豆奶签到成功", body: outcome.message, settings: settings)
            try Task.checkCancellation()
            record(outcome.message + errors)
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            DiagnosticLog.add("background result category=\(DiagnosticLog.category(error))")
            record(error.localizedDescription)
            let defaults = UserDefaults.standard
            let today = CheckInPolicy.day()
            if case CheckInError.network(safeToRetry: true) = error {
                let sameDay = defaults.string(forKey: "network_retry_day") == today
                let count = sameDay ? defaults.integer(forKey: "network_retry_count") : 0
                if count < 3 {
                    defaults.set(today, forKey: "network_retry_day")
                    defaults.set(count + 1, forKey: "network_retry_count")
                    let delay = TimeInterval((count + 1) * 5 * 60)
                    BackgroundScheduler.scheduleNext(settings, force: true, notBefore: Date().addingTimeInterval(delay))
                    DiagnosticLog.add("background safe network retry requested attempt=\(count + 1) delaySeconds=\(Int(delay))")
                    return false
                }
            }
            if case CheckInError.busy = error {
                BackgroundScheduler.scheduleNext(settings, force: true, notBefore: Date().addingTimeInterval(5 * 60))
                return false
            }
            defaults.set(today, forKey: "auto_failure_day")
            defaults.set(settings.siteURL, forKey: "auto_failure_site")
            let errors = await NotificationSender.send(title: "豆奶签到提醒", body: error.localizedDescription, settings: settings)
            if !Task.isCancelled { record(error.localizedDescription + errors) }
            return false
        }
    }

    private func record(_ message: String) {
        UserDefaults.standard.set(message, forKey: "last_checkin_result")
        UserDefaults.standard.set(Date(), forKey: "last_checkin_at")
        UserDefaults.standard.set(message, forKey: "last_result")
        UserDefaults.standard.set(Date(), forKey: "last_result_at")
    }

    private func expire(reason: String) {
        guard !finished else { return }
        DiagnosticLog.add("background expired reason=\(reason)")
        operation?.cancel()
        finish(success: false)
    }

    private func finish(success: Bool) {
        guard !finished else { return }
        finished = true
        watchdog?.cancel()
        task.expirationHandler = nil
        DiagnosticLog.add("background completed success=\(success) seconds=\(Int(ProcessInfo.processInfo.systemUptime - started))")
        task.setTaskCompleted(success: success)
        operation = nil
        watchdog = nil
    }
}
