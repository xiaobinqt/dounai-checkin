import SwiftUI
import WebKit

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var showingLogin = false
    @State private var running = false
    @State private var message = ""
    @State private var time = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("站点与登录") {
                    TextField("https://dounai.win", text: $settings.siteURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    Button("打开网站登录") {
                        settings.save()
                        showingLogin = true
                    }
                    LabeledContent("登录状态", value: settings.cookie.isEmpty ? "需要登录" : "已保存")
                    Button("立即签到一次") { runNow() }
                        .disabled(running || settings.cookie.isEmpty)
                    Button("退出账号", role: .destructive) { logout() }
                        .disabled(settings.cookie.isEmpty)
                }

                Section("自动签到") {
                    Toggle("每天自动签到", isOn: $settings.automaticEnabled)
                    DatePicker("北京时间", selection: $time, displayedComponents: .hourAndMinute)
                    Text("iOS 会在系统允许的后台时机尝试执行，实际时间可能延迟。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("保存自动签到设置") { saveSchedule() }
                }

                Section("Bark 通知") {
                    TextField("https://api.day.app", text: $settings.barkServer)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    SecureField("设备 Key", text: $settings.barkKey)
                    Button("发送测试通知") { testBark() }
                        .disabled(running || settings.barkKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section("最近结果") {
                    Text(settings.lastResult)
                    if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("豆奶签到")
            .disabled(running)
            .overlay { if running { ProgressView().controlSize(.large) } }
            .sheet(isPresented: $showingLogin, onDismiss: { settings.updateResult(settings.cookie.isEmpty ? "尚未登录" : "已保存登录信息") }) {
                LoginView(settings: settings)
            }
            .onAppear { time = date(from: settings.checkInTime) }
        }
    }

    private func runNow() {
        running = true
        message = "正在按正常页面流程签到…"
        settings.save()
        let snapshot = AppSettingsSnapshot(settings)
        Task {
            do {
                let outcome = try await CheckInService.run(snapshot)
                settings.cookie = outcome.cookie
                settings.updateResult(outcome.message)
                message = "签到完成"
                try? await BarkClient.send(title: "豆奶签到成功", body: outcome.message, settings: snapshot)
            } catch {
                settings.updateResult(error.localizedDescription)
                message = error.localizedDescription
                try? await BarkClient.send(title: "豆奶签到提醒", body: error.localizedDescription, settings: snapshot)
            }
            running = false
        }
    }

    private func saveSchedule() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        settings.checkInTime = formatter.string(from: time)
        settings.save()
        BackgroundScheduler.scheduleNext(AppSettingsSnapshot(settings))
        settings.updateResult(settings.automaticEnabled ? "自动签到设置已保存" : "自动签到已关闭")
    }

    private func testBark() {
        running = true
        settings.save()
        let snapshot = AppSettingsSnapshot(settings)
        Task {
            do {
                try await BarkClient.send(title: "豆奶签到", body: "Bark 通知配置正常", settings: snapshot)
                message = "测试通知已发送"
            } catch { message = error.localizedDescription }
            running = false
        }
    }

    private func logout() {
        settings.logout()
        BackgroundScheduler.cancel()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {}
        message = "本机登录信息已清除"
    }

    private func date(from value: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return formatter.date(from: value) ?? Date()
    }
}
