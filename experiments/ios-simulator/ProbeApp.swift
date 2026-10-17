import UIKit

// This separate test application links the unmodified, pinned iOS check-in core.
// It neither installs nor changes the user's normal iPhone application.
@main
final class ProbeApplication: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Probe", sessionRole: session.role)
        configuration.delegateClass = ProbeScene.self
        return configuration
    }
}

final class ProbeScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let controller = UIViewController()
        controller.view.backgroundColor = .systemBackground
        let label = UILabel(frame: CGRect(x: 24, y: 100, width: 330, height: 120))
        label.numberOfLines = 0
        label.text = "Dounai simulator experiment\nRunning…"
        controller.view.addSubview(label)
        window = UIWindow(windowScene: scene)
        window?.rootViewController = controller
        window?.makeKeyAndVisible()
        Task { @MainActor in
            let passed = await Probe.run()
            label.text = passed ? "Simulator experiment passed" : "Simulator experiment failed"
        }
    }
}

enum Probe {
    static let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    static func settings(site: String, cookie: String, userAgent: String = AppSettings.defaultUserAgent) -> AppSettingsSnapshot {
        AppSettingsSnapshot(siteURL: site, cookie: cookie, automaticEnabled: false,
                            checkInTime: "09:17", barkServer: "https://api.day.app", barkKey: "",
                            userAgent: userAgent,
                            email: EmailConfiguration(enabled: false, address: "", recipient: "",
                                                      host: "", port: 465, password: ""))
    }

    @MainActor
    static func run() async -> Bool {
        let env = ProcessInfo.processInfo.environment
        let mode = env["DOUNAI_PROBE_MODE"] ?? "smoke"
        var result: [String: Any] = ["mode": mode == "checkin" ? "checkin" : "smoke", "status": "failed"]
        var client: CheckInClient?
        var originalCookie = ""
        DiagnosticLog.clear()
        do {
            guard mode == "smoke" || mode == "checkin" else { throw ProbeFailure.configuration }
            if mode == "smoke" {
                try await ProbeFixtures.run()
                result["checks"] = ["svg", "vision-png", "normal-checkin", "captcha-retry", "post-not-retried"]
            } else {
                guard env["DOUNAI_CONFIRM_CHECKIN"] == "yes",
                      let site = env["DOUNAI_URL"], !site.isEmpty,
                      let cookie = env["DOUNAI_COOKIE"], !cookie.isEmpty else { throw ProbeFailure.configuration }
                originalCookie = cookie
                client = try CheckInClient(settings: settings(site: site, cookie: cookie,
                    userAgent: env["DOUNAI_USER_AGENT"].flatMap { $0.isEmpty ? nil : $0 } ?? AppSettings.defaultUserAgent))
                // No outer retry: a timed-out POST must not cause another account submission.
                _ = try await client!.checkIn()
            }
            result["status"] = "passed"
        } catch {
            // Do not log localized errors, server messages, URLs, captcha answers or cookies.
            result["category"] = error is ProbeFailure ? "probe-validation" : DiagnosticLog.category(error)
        }
        // Keep updated credentials separate from the public result, including on failure.
        if let client, client.cookieHeader != originalCookie {
            do {
                let cookieURL = documents.appendingPathComponent("cookie")
                try Data(client.cookieHeader.utf8).write(to: cookieURL, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cookieURL.path)
                result["cookieChanged"] = true
            } catch {
                result["status"] = "failed"
                result["category"] = "cookie-persistence"
            }
        }
        do {
            try Data(DiagnosticLog.read().utf8).write(to: documents.appendingPathComponent("diagnostics.log"), options: .atomic)
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            // The host treats this atomic file as the completion signal, not simctl's launch status.
            try data.write(to: documents.appendingPathComponent("result.json"), options: .atomic)
        } catch { return false }
        return result["status"] as? String == "passed"
    }
}

enum ProbeFailure: Error { case configuration, assertion }

func require(_ condition: @autoclosure () -> Bool) throws {
    guard condition() else { throw ProbeFailure.assertion }
}
