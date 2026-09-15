# 豆奶签到 Android 版

手机应用在应用内登录站点，保存当前站点的 Cookie，然后每天在北京时间指定时间提交一次签到。开启自动签到后还会约每 3 小时访问 `/user` 保持登录态并接收服务端更新的 Cookie。后台签到支持 SVG 算式验证码与 PNG 图片 OCR，签到成功或失败可发送 Bark 和邮件通知；服务端明确判定登录失效时会发一次 Bark 提醒。

使用步骤：安装 APK；在首页输入豆奶站点的 HTTPS 根地址并打开签到页，在站点原页面填写邮箱、密码和算式验证码，直接点击网页登录按钮。APK 会调整 WebView 密码栏的输入模式并在顶部显示实际输入的字符数，验证码仍由网站原页面输入、验证；APK 不保存密码。返回应用后进入“自动签到设置”，勾选每天自动签到，配置签到时间和可选通知并保存。通知可单独测试。首页的“立即签到一次”会手动尝试一次签到，失败不重试。

Android 的 WorkManager 会持久化每日签到和每 3 小时一次的登录态刷新任务，但省电、断网、关机等情况可能延迟运行。刷新也依赖服务端愿意延长会话，因此不能保证永不需要重新登录。登录失效的 Bark 提醒需要配置 Bark Key，普通网络故障不按失效处理。通知凭据保存在应用私有数据中，Android 备份已关闭。

项目使用 Go 版相同的 `common_old.onnx` 与 `charsets_old.json` 模型，并通过 ONNX Runtime Android 执行本机 OCR。模型来自 `go-ddddocr` v1.0.1。APK 支持 Android 7.0 及以上的 ARM64 与 ARMv7 手机。

构建需要 JDK 17、Android SDK Platform 35 和 Android Gradle Plugin 8.13.2。用 Android Studio 打开 `android` 目录并运行 `assembleDebug`，或在该目录执行：

```sh
./gradlew assembleDebug
```

生成文件为 `app/build/outputs/apk/debug/app-debug.apk`。Debug APK 已自动签名，可以直接安装；v1.0.0 与 v1.0.1 的调试签名不同，升级需先卸载旧版，旧版数据也会被清除。
