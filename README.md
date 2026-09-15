# dounai-checkin

豆奶每日签到工具。Android APK 在手机本地自动签到；Go 命令行可在本地手动运行。原 GitHub Actions 定时签到方案已失效。

## 手机 APK 签到（推荐）

Android 版在手机上每天自动签到，支持 Bark 和邮件通知。下载并安装 [Android v1.0.1 APK](https://github.com/xiaobinqt/dounai-checkin/releases/download/android-v1.0.1/dounai-checkin-android-v1.0.1.apk)（[发布说明](https://github.com/xiaobinqt/dounai-checkin/releases/tag/android-v1.0.1)）。首次在首页填写豆奶站点的 HTTPS 根地址并打开登录页；邮箱、密码和算式验证码都在网站原页面输入并提交。APK 会修复手机 WebView 中密码栏的输入问题，顶部显示实际输入的密码字符数；不保存登录密码。应用会把登录 Cookie 留在手机应用私有数据中供后台任务使用。

网页登录成功后返回应用，在“自动签到设置”中勾选每天自动签到，填写北京时间的签到时间（默认 `09:17`），点击“保存并安排每日任务”。此时会同时安排约每 3 小时一次的登录态刷新，访问 `/user` 并接收更新的 Cookie。服务端明确判定登录失效时会发一次 Bark 提醒，请配置 Bark 设备 Key；临时断网不会误报。邮件通知需填写邮箱地址、SMTP 主机、端口和授权码，支持 `465` 直接 TLS 或 `587` STARTTLS。点击“发送测试通知”可以单独验证通知配置。“立即签到一次”会手动提交一次签到任务，失败不会自动重试。

手机端会先打开 `/user/panel`，获取并解答签到验证码，再提交一次签到请求；支持 SVG 算式和 PNG 图片识别，并接收服务端轮换的 Cookie。APK 集成了 ONNX 模型，详情和本地构建方法见 [Android 工程说明](android/README.md)。Android 后台任务受省电策略、联网状态和系统调度影响，可能晚于设置时间执行；手机关机或长期断网时无法保证当天签到，也不能保证 Cookie 一定被延长。登录态失效时需要重新在应用内登录。v1.0.0 与 v1.0.1 的调试签名不同，升级需先卸载旧版；卸载会清除旧版的 Cookie 和通知配置。

GitHub Actions 定时签到方案已失效，详见下文。旧部署变更记录见 [CHANGELOG.md](CHANGELOG.md)。

## Go 命令行功能

- 每三小时检查并刷新登录态
- 每天定时签到，也支持手动签到
- 每次任务只尝试签到一次，失败后不自动重试
- 登录态失效时发送 Bark 提醒；北京时间 00:00–08:59 静默
- 签到成功或失败时发送 Bark 通知
- 自动接收服务端更新的 Cookie；可按需写入本地受保护文件
- 支持本地命令和常驻模式

## GitHub Actions 签到方案（已失效）

原先使用 GitHub-hosted runner 或私有 self-hosted runner 定时调用豆奶签到接口的方案，当前已经无法可靠完成签到，项目不再提供这条部署路径。原有私有仓库中的签到和保活计划应停用，避免继续对真实账号重复请求；保存的 Cookie 和用于回写 Secret 的 token 可按需清理。手机 APK 在本机使用网站登录页和手机网络执行任务。

本仓库的 [Android APK 发布工作流](.github/workflows/android-release.yml) 只在 Android 版本标签推送时构建 Release；[Docker 镜像构建工作流](.github/workflows/docker.yaml) 已改为手动触发。两者都不负责定时签到。Go 命令行仍可在本地手动使用，运行结果受站点当前规则与账号状态影响。

## 本地使用

构建：

```shell
go build -trimpath -ldflags="-s -w" -o dounai .
```

项目使用 `go-ddddocr` 识别签到验证码，并自动计算简单的加减乘除验证码。构建需要 Go 1.25，运行目录的 `models` 子目录中需要放置 `common_old.onnx`、`charsets_old.json` 和 ONNX Runtime 1.23.2 动态库。也可通过 `DOUNAI_OCR_MODEL_DIR` 指定模型目录。Docker 镜像会包含这些文件。

为避免 Cookie 出现在 shell 历史中，可静默读取：

```shell
read -rsp "DOUNAI_COOKIE: " DOUNAI_COOKIE_INPUT
echo

DOUNAI_URL="https://example.com" \
DOUNAI_COOKIE="$DOUNAI_COOKIE_INPUT" \
BARK_KEY="你的 Bark Key" \
./dounai keepalive
```

执行一次签到：

```shell
DOUNAI_URL="https://example.com" \
DOUNAI_COOKIE="$DOUNAI_COOKIE_INPUT" \
BARK_KEY="你的 Bark Key" \
./dounai checkin

unset DOUNAI_COOKIE_INPUT
```

`checkin` 是 `once` 的别名。

### 命令

| 命令 | 说明 |
| --- | --- |
| `keepalive` | 检查登录态；失败时通知 |
| `once` / `checkin` | 签到一次并退出 |
| `start` | 常驻运行，每三小时保活并按配置时间签到 |
| `test-email` | 测试可选的邮件通知 |

### 参数与环境变量

| 参数 | 环境变量 | 必填 | 默认值 | 说明 |
| --- | --- | --- | --- | --- |
| `--dounai_url` | `DOUNAI_URL` | 是 | - | 豆奶服务完整 HTTPS URL |
| `--cookie_output` | `DOUNAI_COOKIE_OUTPUT` | 否 | - | Cookie 发生变化时，将完整请求头以 `0600` 权限写入指定文件 |
| `--cookie` | `DOUNAI_COOKIE` | 是 | - | 完整 Cookie 请求头 |
| `--bark_key` | `BARK_KEY` | 否 | - | Bark 设备 Key |
| `--bark_server` | `BARK_SERVER` | 否 | `https://api.day.app` | Bark 服务地址 |
| `--checkin_time` | `CHECKIN_TIME` | 仅 `start` | `10:00` | 常驻模式签到时间，UTC+8 |

邮件通知参数 `EMAIL`、`EMAIL_HOST`、`EMAIL_PORT`、`EMAIL_AUTH_CODE` 和 `EMAIL_TLS` 均为可选。

## 安全说明

- Cookie 等同于登录凭据，应保存在手机应用私有数据或本地受保护的密钥存储中。
- 不要把 Cookie 写入命令行参数、README、工作流源码、构建产物或日志。
- 程序不会记录 Cookie 内容，错误消息也不会包含 Cookie。
- HTTP 客户端使用正常 TLS 证书校验，不再跳过 HTTPS 证书验证。
- Cookie 失效后，在浏览器重新登录并替换 `DOUNAI_COOKIE` 即可。

## 开发验证

```shell
go test -race ./...
go vet ./...
```

测试使用本地模拟服务，不需要真实 Cookie，也不会访问豆奶账号。
