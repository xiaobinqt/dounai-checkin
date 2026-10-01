# 豆奶签到 Android

在 Android 手机上完成网页登录，并按北京时间每天自动签到。支持 Bark 和邮件通知，登录 Cookie 只保存在应用私有数据中。

[下载 Android v1.0.2 APK](https://github.com/xiaobinqt/dounai-checkin/releases/download/android-v1.0.2/dounai-checkin-android-v1.0.2.apk) · [查看发布说明](https://github.com/xiaobinqt/dounai-checkin/releases/tag/android-v1.0.2) · [历史脚本分支](https://github.com/xiaobinqt/dounai-checkin/tree/script-checkin)

## 安装和登录

1. 下载 APK 并直接安装。支持 Android 7.0 及以上的 ARM64 与 ARMv7 手机。
2. 在首页填写豆奶站点的 HTTPS 根地址，例如 `https://dounai.win`，然后点“打开签到页”。
3. 邮箱、算式验证码和登录按钮都使用网站原页面。点击网页密码框或顶部“输入密码”，在系统输入框中完整输入密码，再点“填入网页”。APK 不保存登录密码。
4. 网页登录成功后点“返回应用”。进入“自动签到设置”，勾选每天自动签到，选择北京时间的签到时间并保存。
5. 可以先点“立即签到一次”验证完整流程。每次任务只提交一次，失败不会自动连续重试。

### 网页密码栏只显示 1 个圆点

部分手机的 WebView 在密码已经完整填入后，网页密码栏仍只画出 **1 个圆点**。这只是网页控件的显示问题，不表示密码只有一个字符，也不表示后一个字符覆盖了前一个字符。

请以 APK 顶部的“密码已完整填入 N 个字符”为准。数量不对时点“重新输入密码”；需要核对内容时，可以先在系统密码输入框勾选“显示密码”，确认后再点“填入网页”。不要直接在网页密码栏里连续输入。

## 自动签到

手机端会按网站当前流程执行一次签到：

1. 打开 `/user/panel` 获取本次页面票据。
2. 加载并识别 SVG 或 PNG 算式验证码。
3. 等待 4–7 秒，模拟正常的人机操作间隔。
4. 保持隐藏蜜罐字段为空，使用页面票据和验证码生成令牌并提交。
5. 接收服务端更新的 Cookie，并记录本次结果。

开启自动签到后，应用还会约每 3 小时访问 `/user` 刷新登录态。刷新依赖服务端是否延长会话，Cookie 已失效时仍需重新在应用内登录。首页“退出账号”会清除登录 Cookie，关闭每日签到和登录态刷新任务，同时保留通知配置。

## 通知

- Bark：填写设备 Key。签到成功或失败会推送通知；服务端明确判定登录失效时会额外提醒重新登录。
- 邮件：填写邮箱、SMTP 主机、端口和授权码。支持 `465` 直接 TLS 和 `587` STARTTLS。
- “发送测试通知”只验证通知配置，不会触发签到。

Bark 和邮件均为可选配置。通知凭据保存在应用私有数据中，Android 备份已关闭。

## 运行限制

Android 使用 WorkManager 安排后台任务。省电策略、断网、关机或厂商后台限制可能使任务晚于设置时间执行；手机关机或长期断网时无法保证当天签到。

GitHub Release 中的 APK 使用自动调试签名，可以直接安装。不同版本签名不一致时，Android 会要求先卸载旧版；卸载会清除 Cookie 和通知配置。

## GitHub Actions 说明

`main` 分支中的 [Android APK 发布工作流](.github/workflows/android-release.yml) 只负责在推送 `android-v*` 标签时构建 GitHub Release，不执行账号签到。

原 Go、Docker 和 GitHub Actions 签到代码已经移到 [`script-checkin`](https://github.com/xiaobinqt/dounai-checkin/tree/script-checkin) 分支。该分支用于保留历史实现；GitHub-hosted runner 签到目前无法可靠通过站点的人机交互校验，不再作为推荐方案。

## 本地构建

详细说明见 [构建文档](BUILDING.md)。基本构建命令：

```shell
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
./gradlew assembleDebug
```

APK 生成在 `app/build/outputs/apk/debug/app-debug.apk`。

## 安全说明

- Cookie 等同于登录凭据，不要发送到聊天、Issue、日志或公开仓库。
- APK 不保存登录密码，只将本次输入写入当前网站登录页。
- 站点地址只接受 HTTPS 根地址，网络请求使用正常 TLS 证书校验。
