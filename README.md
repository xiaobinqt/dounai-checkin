# 豆奶签到

在手机上完成豆奶站点登录，并在本机保存登录信息、执行签到。`main` 分支采用单仓库多平台结构：Android 与 iOS 各自使用独立工程，公共说明和发布工作流保留在仓库根目录。

## Android

[下载 Android v1.0.4 APK](https://github.com/xiaobinqt/dounai-checkin/releases/download/android-v1.0.4/dounai-checkin-android-v1.0.4.apk) · [查看发布说明](https://github.com/xiaobinqt/dounai-checkin/releases/tag/android-v1.0.4) · [Android 使用与构建说明](android/README.md)

**推荐使用 Android 版。** 当前版本已经在真实 Android 手机上完成网页登录、亮屏手动签到、黑屏签到和后台任务测试，APK 可以直接安装使用。

Android 版支持每天自动签到、约每 3 小时刷新登录态、Bark 与邮件通知，以及电量低于 10% 时发送一次 Bark。APK 支持 Android 7.0 及以上的 ARM64 与 ARMv7 手机。

锁屏、黑屏、从最近任务列表划掉应用，或应用进程被系统正常回收后，自动签到通常仍会执行。不要在系统设置中点“强行停止”；强行停止后，必须重新打开一次应用，系统才会恢复后台任务。华为等后台管理较严格的手机，建议允许应用自动启动和后台活动，并关闭针对本应用的电池优化。

安装后输入站点的 HTTPS 根地址并打开网页。邮箱、验证码和登录按钮都使用网站原页面；密码可通过应用提供的系统密码框完整填入当前网页，应用不会保存密码。登录成功后返回应用，设置每天签到的北京时间即可。

部分手机的 WebView 会在密码已经完整填入后仍只显示 **1 个圆点**。这是网页密码控件的显示问题，请以应用顶部显示的实际字符数为准。详细操作见 [Android 说明](android/README.md)。

## iOS

[iOS 工程与使用说明](ios/README.md)

iOS 源码与 Android 一同保存在 `main` 分支。初版支持在网站原页面登录、保存 Cookie、手动签到、后台签到请求、Bark 通知和退出账号。验证码与登录按钮仍由网站原页面处理，应用没有单独实现登录表单。当前仅通过模拟器编译检查，尚未完成 iPhone 真机签到测试。

iOS 的后台执行时间由系统决定，不能保证每天精确到指定分钟。iOS 版目前先提供源码，还没有可直接下载的安装包。想装到自己的 iPhone，需要用 Mac 打开 Xcode，选中自己的 Apple 账号后点运行。

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

`main` 分支中的 [Android APK 发布工作流](.github/workflows/android-release.yml) 只在推送 `android-v*` 标签时构建 APK 并创建 GitHub Release；[iOS 构建工作流](.github/workflows/ios-build.yml) 只校验 Xcode 工程能否通过编译。两个工作流都不执行账号签到。

原 Go、Docker 和 GitHub Actions 签到代码保存在 [`script-checkin`](https://github.com/xiaobinqt/dounai-checkin/tree/script-checkin) 分支。GitHub-hosted runner 目前无法可靠通过站点的人机交互校验，因此脚本和 Actions 签到只作为历史实现保留，当前推荐使用手机应用。

## 安全说明

- Cookie 等同于登录凭据，不要发送到聊天、Issue、日志或公开仓库。
- Android 和 iOS 应用都不保存登录密码。
- 站点地址只接受 HTTPS 根地址，网络请求使用正常 TLS 证书校验。
