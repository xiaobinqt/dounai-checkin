import SwiftUI
import WebKit

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var showingLogin = false
    @State private var running = false
    @State private var message = ""
    @State private var time = Date()
    @State private var confirmingRepeat = false

    var body: some View {
        NavigationStack {
            Form {
                Section("签到状态") {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(settings.hasSucceededToday ? "今日已签到" : "尚未确认今日签到成功",
                              systemImage: settings.hasSucceededToday ? "checkmark.circle.fill" : "clock")
                            .font(.title3.bold())
                            .foregroundStyle(settings.hasSucceededToday ? Color.green : Color.primary)
                        Text(settings.lastResult)
                            .font(.body.weight(.medium))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        if let updatedAt = settings.lastResultAt {
                            Text("最近结果更新：" + resultTime(updatedAt))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
                    }
                    .padding(.vertical, 6)
                    Button(settings.hasSucceededToday ? "今日已签到 · 再次签到…" : "立即签到一次") {
                        if settings.hasSucceededToday { confirmingRepeat = true }
                        else { runNow() }
                    }
                    .disabled(running || settings.cookie.isEmpty)
                    NavigationLink("运行日志") { LogView() }
                }

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
                    Button("退出账号", role: .destructive) { logout() }
                        .disabled(settings.cookie.isEmpty)
                }

                Section("自动签到") {
                    Toggle("每天自动签到", isOn: $settings.automaticEnabled)
                    DatePicker("北京时间", selection: $time, displayedComponents: .hourAndMinute)
                    Text("iOS 会在系统允许的后台时机尝试执行，实际时间可能延迟。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("保存自动签到设置") { saveSchedule() }
                    Text("回到桌面或锁屏后可能执行；从多任务界面划掉应用后，请重新打开以恢复后台机会。")
                        .font(.footnote).foregroundStyle(.secondary)
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

                Section("邮件通知") {
                    Toggle("发送签到结果邮件", isOn: $settings.emailEnabled)
                    if settings.emailEnabled {
                        TextField("发件邮箱（同时作为登录账号）", text: $settings.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("收件邮箱（留空则发给自己）", text: $settings.emailRecipient)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("SMTP 主机，例如 smtp.qq.com", text: $settings.emailHost)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Picker("加密连接", selection: $settings.emailPort) {
                            Text("TLS · 465").tag(465)
                            Text("STARTTLS · 587").tag(587)
                        }
                        SecureField("SMTP 授权码", text: $settings.emailPassword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Text("请在邮箱服务中开启 SMTP，并使用授权码。授权码保存在本机钥匙串。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("保存邮件设置") { saveEmail() }
                        Button("发送测试邮件") { testEmail() }
                    } else {
                        Button("保存邮件设置") { saveEmail() }
                    }
                }

            }
            .navigationTitle("豆奶签到")
            .disabled(running)
            .overlay { if running { ProgressView().controlSize(.large) } }
            .sheet(isPresented: $showingLogin, onDismiss: {
                settings.reloadResult()
                message = settings.cookie.isEmpty ? "尚未登录" : "已保存登录信息"
            }) {
                LoginView(settings: settings)
            }
            .onAppear { time = date(from: settings.checkInTime) }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .receive(on: RunLoop.main)) { _ in settings.reloadResult() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                settings.reloadResult()
            }
            .confirmationDialog("今天已经签到成功，仍要再次签到吗？", isPresented: $confirmingRepeat, titleVisibility: .visible) {
                Button("仍然签到") { runNow() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("已记录北京时间今天签到成功，通常无需重复提交。")
            }
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
                settings.updateResult(outcome.message)
                message = "签到完成，正在发送通知…"
                let errors = await NotificationSender.send(title: "豆奶签到成功", body: outcome.message, settings: snapshot)
                settings.updateResult(outcome.message + errors)
                message = "签到完成" + errors
            } catch {
                settings.updateResult(error.localizedDescription)
                message = error.localizedDescription
                let errors = await NotificationSender.send(title: "豆奶签到提醒", body: error.localizedDescription, settings: snapshot)
                settings.updateResult(error.localizedDescription + errors)
                message = error.localizedDescription + errors
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
        UserDefaults.standard.removeObject(forKey: "auto_failure_day")
        BackgroundScheduler.scheduleNext(AppSettingsSnapshot(settings), force: true)
        message = settings.automaticEnabled ? "已请求后台计划；实际登记结果请查看运行日志" : "自动签到已关闭"
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

    private func saveEmail() {
        do {
            try AppSettingsSnapshot(settings).email.validate()
            settings.save()
            message = settings.emailEnabled ? "邮件设置已保存" : "邮件通知已关闭"
        } catch { message = error.localizedDescription }
    }

    private func testEmail() {
        let configuration = AppSettingsSnapshot(settings).email
        do { try configuration.validate() }
        catch { message = error.localizedDescription; return }
        settings.save()
        running = true
        message = "正在发送测试邮件…"
        Task {
            do {
                try await EmailClient.send(title: "豆奶签到通知测试", body: "邮件通知配置正常。", configuration: configuration)
                message = "服务器已接收测试邮件，请检查收件箱或垃圾邮件"
            } catch { message = "测试邮件失败：" + error.localizedDescription }
            running = false
        }
    }

    private func date(from value: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return formatter.date(from: value) ?? Date()
    }

    private func resultTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter.string(from: date) + "（北京时间）"
    }
}
