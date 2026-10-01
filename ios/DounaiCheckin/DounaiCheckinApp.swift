import SwiftUI

@main
struct DounaiCheckinApp: App {
    @StateObject private var settings = AppSettings()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BackgroundScheduler.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                settings.save()
                BackgroundScheduler.scheduleNext(AppSettingsSnapshot(settings))
            }
        }
    }
}
