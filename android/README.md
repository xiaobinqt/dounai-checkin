# 豆奶签到 Android 版

手机应用在应用内登录站点，保存当前站点的 Cookie，然后每天在北京时间指定时间提交一次签到。后台签到支持 SVG 算式验证码与 PNG 图片 OCR，签到成功或失败可发送 Bark 和邮件通知。登录态失效时需要重新打开应用登录。

使用步骤：安装 APK；在首页输入豆奶站点的 HTTPS 根地址并打开签到页，完成网页登录；进入“自动签到设置”，勾选每天自动签到，配置签到时间和可选通知并保存。通知可单独测试。首页的“立即签到一次”会手动尝试一次签到，失败不重试。

Android 的 WorkManager 会持久化后台任务，但省电、断网、关机等情况可能延迟或阻止当天运行。任务结束后会安排下一天；首次配置前先登录，Cookie 到期后重新登录。通知凭据保存在应用私有数据中，Android 备份已关闭。

项目使用 Go 版相同的 `common_old.onnx` 与 `charsets_old.json` 模型，并通过 ONNX Runtime Android 执行本机 OCR。模型来自 `go-ddddocr` v1.0.1。APK 支持 Android 7.0 及以上的 ARM64 与 ARMv7 手机。

构建需要 JDK 17、Android SDK Platform 35 和 Android Gradle Plugin 8.13.2。用 Android Studio 打开 `android` 目录并运行 `assembleDebug`，或在该目录执行：

```sh
./gradlew assembleDebug
```

生成文件为 `app/build/outputs/apk/debug/app-debug.apk`。Debug APK 已自动签名，可以直接安装；后续更新若使用不同签名证书，需要先卸载旧版。
