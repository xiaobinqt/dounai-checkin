# 豆奶签到

在手机上完成豆奶站点登录，并在本机保存登录信息、执行签到。`main` 分支采用单仓库多平台结构：Android 与 iOS 各自使用独立工程，公共说明和发布工作流保留在仓库根目录。

**作者目前正在日常使用 iOS 版，推荐使用 iOS 版。** 后续会优先维护 iOS，功能更新和问题修复会更及时。此推荐基于作者的使用与维护重心；iOS 后台任务仍受系统限制，不能保证每天自动或准点签到。

## iOS（推荐）

[iOS 工程、安装与使用说明](ios/README.md)

iOS 版支持网页登录、保存 Cookie、手动签到、后台签到请求、Bark 与邮件通知、验证码安全补试，以及可复制的运行日志。首页顶部显示当天签到状态和最近结果，今日已成功时再次手动签到需要确认。作者已在 iPhone 真机上验证受控任务签到成功、Bark 通知、当日去重和系统终止处理。

iOS 的后台执行时间由系统决定，不能保证每天精确到指定分钟；从多任务界面上划关闭后，通常需要重新打开才能恢复后台机会。真机受控测试通过不等于自然后台唤醒已验证，详细边界与测试记录见 [iOS 说明](ios/README.md)。

iOS 版目前提供源码，还没有可直接下载的安装包。安装到自己的 iPhone，需要用 Mac 的 Xcode 打开工程，配置自己的 Apple 账号和开发签名后构建安装。

## Android

[下载 Android v1.0.12 APK](https://github.com/xiaobinqt/dounai-checkin/releases/download/android-v1.0.12/dounai-checkin-android-v1.0.12.apk) · [查看发布说明](https://github.com/xiaobinqt/dounai-checkin/releases/tag/android-v1.0.12) · [Android 使用与构建说明](android/README.md)

Android 版已经在真实 Android 手机上完成网页登录、亮屏手动签到、黑屏签到和后台任务测试，APK 可以直接安装使用。

Android 版支持每天自动签到、约每 3 小时刷新登录态、Bark 与邮件通知，以及电量低于 10% 时发送一次 Bark。APK 支持 Android 7.0 及以上的 ARM64 与 ARMv7 手机。

锁屏、黑屏、从最近任务列表划掉应用，或应用进程被系统正常回收后，自动签到通常仍会执行。v1.0.9 同时使用 WorkManager 和系统唤醒闹钟，并会在应用升级和系统时间变化后恢复计划。Android 重启后会尝试自动恢复，但部分华为/EMUI 真机即使已经允许自启动，仍可能不投递开机广播；手机重启并解锁后请手动打开一次应用，确认后台计划已经重新登记。首页的“运行日志”可以查看计划时间、实际唤醒时间、屏幕状态、重试与通知结果；日志不包含 Cookie、密码或通知密钥。不要在系统设置中点“强行停止”；强行停止后，也必须重新打开一次应用。华为等后台管理较严格的手机，建议关闭“自动管理”，同时允许“自动启动、关联启动、后台活动”，并关闭针对本应用的电池优化；设置完成后重新打开一次应用。

安装后输入站点的 HTTPS 根地址并打开网页。邮箱、验证码和登录按钮都使用网站原页面；密码可通过应用提供的系统密码框完整填入当前网页，应用不会保存密码。登录成功后返回应用，设置每天签到的北京时间即可。

部分手机的 WebView 会在密码已经完整填入后仍只显示 **1 个圆点**。这是网页密码控件的显示问题，请以应用顶部显示的实际字符数为准。详细操作见 [Android 说明](android/README.md)。

## 仓库结构

```text
.
├── android/                 Android Gradle 工程、使用说明和发布说明
├── ios/                     iOS Xcode 工程和使用说明
├── .github/workflows/       移动端构建与发布工作流
├── CHANGELOG.md             产品更新记录
└── README.md                项目入口
```

这种结构让两个平台独立使用各自的构建工具，也能在同一分支统一维护产品说明和版本变更。

## GitHub Actions 与历史脚本

`main` 分支中的 [Android APK 发布工作流](.github/workflows/android-release.yml) 只在推送 `android-v*` 标签时构建 APK 并创建 GitHub Release；[iOS 构建工作流](.github/workflows/ios-build.yml) 执行邮件与签到策略回归测试，并校验模拟器编译。两个工作流都不执行真实账号签到。

原 Go、Docker 和 GitHub Actions 签到代码保存在 [`script-checkin`](https://github.com/xiaobinqt/dounai-checkin/tree/script-checkin) 分支。GitHub-hosted runner 目前无法可靠通过站点的人机交互校验，因此脚本和 Actions 签到只作为历史实现保留，当前推荐使用手机应用。

## 安全说明

- Cookie 等同于登录凭据，不要发送到聊天、Issue、日志或公开仓库。
- Android 和 iOS 应用都不保存登录密码。
- 站点地址只接受 HTTPS 根地址，网络请求使用正常 TLS 证书校验。
