import SwiftUI

@main
struct DounaiCheckinApp: App {
    @StateObject private var settings = AppSettings()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BackgroundScheduler.register()
        DiagnosticLog.add("app process started")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                DiagnosticLog.add("app entered background")
                settings.save()
                BackgroundScheduler.scheduleNext(AppSettingsSnapshot(settings))
            } else if phase == .active {
                settings.reloadResult()
                BackgroundScheduler.capture(reason: "app-active-before-restore")
                BackgroundScheduler.scheduleNext(AppSettingsSnapshot(settings))
            }
        }
    }
}
