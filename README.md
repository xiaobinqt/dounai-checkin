# dounai-checkin

豆奶 Cookie 签到与登录态保活工具。适用于登录页启用验证码后的场景：用户在浏览器中手动完成一次登录，程序复用登录 Cookie，不识别或绕过验证码。

## 功能

- 每三小时检查并刷新登录态
- 每天定时签到，也支持手动签到
- 签到失败时最多重试三次
- 登录态失效时发送 Bark 提醒；北京时间 00:00–08:59 静默
- 签到成功或失败时发送 Bark 通知
- 服务端在当前进程中更新 Cookie 时自动接收新值
- 支持 GitHub Actions、本地命令和常驻模式

## 工作方式

推荐使用“公开源码 + 私有 Runner”结构：

```text
xiaobinqt/dounai-checkin (Public)
              ↓ 每次拉取最新 main
你的 dounai-checkin-runner (Private)
              ↓
     keepalive（每 3 小时）
     checkin（09:17 后补偿重试并按天去重）
              ↓
       Cookie 失效时 Bark 提醒
```

账号 Cookie 和 Bark Key 只保存在私有 Runner 仓库。公开源码更新后，下一次 Action 自动使用新版本，不需要向两个仓库重复推送代码。

## GitHub Actions 配置

### 1. 创建私有 Runner 仓库

打开 [GitHub 新建仓库页面](https://github.com/new?name=dounai-checkin-runner&visibility=private)，创建空的 Private 仓库：

```text
Repository name: dounai-checkin-runner
Visibility: Private
```

### 2. 添加工作流

复制 [examples/checkin-runner.yml](examples/checkin-runner.yml) 到私有仓库：

```text
.github/workflows/checkin.yml
```

模板默认拉取 `xiaobinqt/dounai-checkin` 的 `main` 分支，不需要额外 GitHub Token。

### 3. 获取 Cookie

1. 在浏览器打开豆奶登录页，手动输入验证码并登录。
2. 按 `F12` 打开开发者工具，进入 `Network`。
3. 登录后刷新 `/user` 页面，点击 Network 中的 `/user` 请求。
4. 在 `Headers → Request Headers` 找到 `Cookie`，复制完整值。

格式类似：

```text
uid=...; email=...; key=...; ip=...; expire_in=...; PHPSESSID=...
```

如果 Network 没有显示，可进入：

```text
Application → Storage → Cookies → 对应豆奶域名
```

复制该域名下的全部 Cookie，并用 `; ` 拼接。不要把 Cookie 发到聊天、Issue 或 Action 日志中。

### 4. 配置 Secrets

在私有 Runner 仓库打开：

```text
Settings → Secrets and variables → Actions → New repository secret
```

添加：

| Secret | 必填 | 说明 |
| --- | --- | --- |
| `DOUNAI_URL` | 是 | 豆奶服务完整 HTTPS 地址 |
| `DOUNAI_COOKIE` | 是 | 浏览器中复制的完整 Cookie 请求头 |
| `BARK_KEY` | 是 | Bark 推送地址最后一段的设备 Key |
| `BARK_SERVER` | 否 | Bark 服务地址，默认 `https://api.day.app` |
| `EMAIL` | 否 | 邮件通知的发件人和收件人邮箱 |
| `EMAIL_HOST` | 否 | SMTP 服务器地址；启用邮件通知时必填 |
| `EMAIL_PORT` | 否 | SMTP 端口；启用邮件通知时必填 |
| `EMAIL_AUTH_CODE` | 否 | SMTP 授权码或密码；启用邮件通知时必填 |
| `EMAIL_TLS` | 否 | 是否使用 SMTP TLS/SSL，默认 `false` |

邮件通知整组可选；完全不配置时程序会静默跳过。配置邮件通知时，`EMAIL`、`EMAIL_HOST`、`EMAIL_PORT` 和 `EMAIL_AUTH_CODE` 必须同时提供。

不再需要豆奶登录用的 `DOUNAI_EMAIL` 和 `DOUNAI_PASSWORD`。上面的 `EMAIL` 和 `EMAIL_AUTH_CODE` 只用于可选的 SMTP 通知，Action 不会使用它们登录豆奶。

### 5. 手动验证

进入私有仓库：

```text
Actions → Dounai session → Run workflow
```

先选择 `keepalive`，确认 Cookie 有效；再选择 `checkin` 测试签到。`keepalive` 成功时不会打扰手机，失败时通常会发送 Bark；北京时间 00:00–08:59 只将 Action 标记为失败，不发送 Bark 或邮件。`checkin` 成功和失败都会通知，不受静默时段影响。

### 6. 自动运行时间

模板包含保活和签到补偿两个北京时间计划：

Actions 运行列表会直接显示 `Dounai checkin` 或 `Dounai keepalive`，便于区分本次触发类型。

```yaml
schedule:
  - cron: "23 */3 * * *"
    timezone: "Asia/Shanghai"
  - cron: "17,47 9,10 * * *"
    timezone: "Asia/Shanghai"
```

- 每天 `00:23、03:23、06:23……` 保活一次。
- 每天 `09:17、09:47、10:17、10:47` 提供签到触发机会。
- 任意定时任务实际启动时若已过 `09:17` 且当天尚未签到，会自动改为签到。例如 `06:23` 的保活延迟到 `09:26` 才启动时，也会成为签到兜底。
- 签到成功后使用只包含北京时间日期的 Actions Cache 标记当天状态；后续补偿任务直接跳过，原本的三小时保活仍正常运行。
- 每次签到前都会先刷新 `/user` 页面并接收服务端更新的 Cookie，再请求 `/user/checkin`。
- 只有明确返回奖励到账、签到成功或今日已签到时才会标记成功；`ret=1` 但提示“请刷新页面后重试”仍按失败处理并继续补偿。

GitHub Actions 定时任务可能因平台负载而延迟，甚至丢弃单次事件。错峰补偿和保活兜底能提高当天最终签到成功率，但不保证在 `09:17` 准点启动。工作流必须存在于默认分支。详见 [GitHub schedule 文档](https://docs.github.com/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)。

## Cookie 保活的限制

`keepalive` 会携带登录 Cookie 请求 `/user`，并检查以下结果：

- HTTP 2xx：当前会话有效。
- HTTP 401、403 或跳回登录页：会话失效，让 Action 失败；北京时间 09:00–23:59 发送 Bark 提醒。
- 服务端返回新的 `Set-Cookie`：当前进程会使用新 Cookie，但 GitHub Secret 不会被自动改写。

有两个服务端行为无法由本工具保证：

1. 如果 Cookie 是固定期限而非滑动过期，定时访问不会无限续期，到期后仍需手动登录并更新 `DOUNAI_COOKIE`。
2. Cookie 中包含 `ip`。如果服务端校验登录 IP，浏览器登录 IP 与 GitHub 托管 Runner IP 不同会导致会话失效；此时应使用固定网络出口的 [self-hosted runner](local-to-remote.md)。

## 本地使用

构建：

```shell
go build -trimpath -ldflags="-s -w" -o dounai .
```

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
| `--cookie` | `DOUNAI_COOKIE` | 是 | - | 完整 Cookie 请求头 |
| `--bark_key` | `BARK_KEY` | Action 模板必填 | - | Bark 设备 Key |
| `--bark_server` | `BARK_SERVER` | 否 | `https://api.day.app` | Bark 服务地址 |
| `--checkin_time` | `CHECKIN_TIME` | 仅 `start` | `10:00` | 常驻模式签到时间，UTC+8 |

邮件通知参数 `EMAIL`、`EMAIL_HOST`、`EMAIL_PORT`、`EMAIL_AUTH_CODE` 和 `EMAIL_TLS` 均为可选。

## 安全说明

- Cookie 等同于登录凭据，只能保存在 GitHub Secrets 或其他专用密钥存储中。
- 不要把 Cookie 写入命令行参数、README、工作流源码、构建产物或日志。
- 私有 Runner 仓库应保持 Private，工作流权限保持 `contents: read`。
- Actions Cache 中的每日签到标记只包含日期，不保存 Cookie、URL 或通知配置。
- 程序不会记录 Cookie 内容，错误消息也不会包含 Cookie。
- HTTP 客户端使用正常 TLS 证书校验，不再跳过 HTTPS 证书验证。
- Cookie 失效后，在浏览器重新登录并替换 `DOUNAI_COOKIE` 即可。

## 开发验证

```shell
go test -race ./...
go vet ./...
```

测试使用本地模拟服务，不需要真实 Cookie，也不会访问豆奶账号。
