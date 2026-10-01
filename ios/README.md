# 豆奶签到 iOS 版

iOS 工程使用 SwiftUI、WKWebView、Vision 和 BackgroundTasks，不依赖第三方软件包。最低系统版本为 iOS 16。

## 当前功能

- 在应用内打开网站原页面，完成邮箱、密码和验证码登录。
- 将登录 Cookie 保存在本机 Keychain，不保存登录密码。
- 手动执行一次签到，并在请求后接收服务端更新的 Cookie。
- 设置每天的北京时间，通过系统后台刷新任务尝试自动签到。
- 发送签到成功、失败或需要重新登录的 Bark 通知。
- 退出账号并清除 Cookie 和 WebKit 网站数据。

邮件通知和低电量 Bark 当前只在 Android 版提供。

## 构建和安装

1. 在 macOS 安装完整 Xcode 16 或更高版本。
2. 用 Xcode 打开 `ios/DounaiCheckin.xcodeproj`。
3. 选择 `DounaiCheckin` target，在 Signing & Capabilities 中选择自己的 Apple 开发团队，并按需修改 Bundle Identifier。
4. 连接 iPhone，选择设备后运行。

个人免费开发签名的有效期和设备限制由 Apple 决定。仓库不包含开发者证书、描述文件或可直接安装的 IPA。

## 后台执行限制

iOS 的后台刷新由系统根据使用习惯、电量和网络状况统一调度。应用提交的时间只表示最早执行时间，系统可能延后运行，也可能在长期不打开应用时减少后台机会。手机关机、断网或应用被系统限制后台刷新时无法保证当天签到。

首次启用自动签到后，请正常返回桌面并保留系统的“后台 App 刷新”权限。每次打开应用或进入后台时，应用会更新下一次后台任务请求。

## 登录与隐私

登录全过程使用网站原页面，应用不提供独立的邮箱、密码或验证码输入接口。Cookie 和 Bark Key 保存在 Keychain；普通设置和最近结果保存在应用的 UserDefaults。退出账号会关闭自动签到并清除本机登录数据。
