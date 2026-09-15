# dounai-checkin

豆奶每日签到工具。Android APK 在手机本地自动签到；原有 Go 命令行和 GitHub Actions 部署仍可使用。

## 手机 APK 签到（推荐）

Android 版在手机上每天自动签到，支持 Bark 和邮件通知。先从 [GitHub Releases](https://github.com/xiaobinqt/dounai-checkin/releases) 下载 APK 安装。首次使用在首页填写豆奶站点的 HTTPS 根地址，点击“打开签到页”，在应用内完成网页登录。应用会把该站点的登录 Cookie 留在手机应用私有数据中，后台任务直接使用它；不要把 Cookie 提交到仓库或发到聊天中。

在“自动签到设置”中勾选每天自动签到，填写北京时间的签到时间（默认 `09:17`），点击“保存并安排每日任务”。可选填写 Bark 设备 Key；邮件通知需填写邮箱地址、SMTP 主机、端口和授权码，支持 `465` 直接 TLS 或 `587` STARTTLS。点击“发送测试通知”可以单独验证通知配置。“立即签到一次”会手动提交一次签到任务，失败不会自动重试。

手机端会先打开 `/user/panel`，获取并解答签到验证码，再提交一次签到请求；支持 SVG 算式和 PNG 图片识别，并接收服务端轮换的 Cookie。APK 集成了 ONNX 模型，详情和本地构建方法见 [Android 工程说明](android/README.md)。Android 后台任务受省电策略、联网状态和系统调度影响，可能晚于设置时间执行；手机关机或长期断网时无法保证当天签到。登录态失效时需要重新在应用内登录。

旧的 GitHub-hosted Runner 方案容易受到数据中心出口 IP 与登录环境差异的影响，当前不推荐作为默认签到方式。下面的 GitHub Actions、命令行和常驻部署说明保留给已有部署。

**升级现有 Go 部署前，请先查看 [更新日志与升级说明](CHANGELOG.md)，其中会注明是否需要同步私有 runner 的 YAML 或更新 Secrets。**

## Go 命令行与旧部署功能

- 每三小时检查并刷新登录态
- 每天定时签到，也支持手动签到
- 每次任务只尝试签到一次，失败后不自动重试
- 登录态失效时发送 Bark 提醒；北京时间 00:00–08:59 静默
- 签到成功或失败时发送 Bark 通知
- 自动接收服务端更新的 Cookie，并可安全回写 runner 的 GitHub Secret
- 支持 GitHub Actions、本地命令和常驻模式

## 旧 GitHub Actions 工作方式

旧部署使用“公开源码 + 私有 Runner”结构：

```text
xiaobinqt/dounai-checkin (Public)
              ↓ 每次拉取最新 main
你的 dounai-checkin-runner (Private)
              ↓
     keepalive（每 3 小时）
     checkin（每天 09:17，一次请求）
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
| `COOKIE_UPDATE_TOKEN` | 否 | GitHub 生成的完整 Fine-grained PAT，不是 `true/false`；通常以 `github_pat_` 开头，仅授权当前私有 runner 仓库的 `Secrets: Read and write` |
| `BARK_KEY` | 是 | Bark 推送地址最后一段的设备 Key |
| `BARK_SERVER` | 否 | Bark 服务地址，默认 `https://api.day.app` |
| `EMAIL` | 否 | 邮件通知的发件人和收件人邮箱 |
| `EMAIL_HOST` | 否 | SMTP 服务器地址；启用邮件通知时必填 |
| `EMAIL_PORT` | 否 | SMTP 端口；启用邮件通知时必填 |
| `EMAIL_AUTH_CODE` | 否 | SMTP 授权码或密码；启用邮件通知时必填 |
| `EMAIL_TLS` | 否 | 是否使用 SMTP TLS/SSL，默认 `false`；使用 `465` 端口时必须设为 `true` |

邮件通知整组可选；完全不配置时程序会静默跳过。配置邮件通知时，`EMAIL`、`EMAIL_HOST`、`EMAIL_PORT` 和 `EMAIL_AUTH_CODE` 必须同时提供。

`EMAIL_TLS` 本身不是必填项，具体取值取决于 SMTP 端口：

- 使用 SMTP `465` 端口：必须设置 `EMAIL_TLS=true`。
- 使用 SMTP `587` 或 `25` 端口：通常不设置，或设置 `EMAIL_TLS=false`。

多数邮箱服务要求填写 SMTP 授权码或应用专用密码，而不是网页登录密码。可选通知发送失败会记录错误，但不会把已经成功的签到改判为失败。

不再需要豆奶登录用的 `DOUNAI_EMAIL` 和 `DOUNAI_PASSWORD`。上面的 `EMAIL` 和 `EMAIL_AUTH_CODE` 只用于可选的 SMTP 通知，Action 不会使用它们登录豆奶。

#### 创建 `COOKIE_UPDATE_TOKEN`

GitHub 默认提供给工作流的 `GITHUB_TOKEN` 不能修改 Actions Secrets。若要让保活自动保存服务端返回的新 Cookie，需要单独创建一个最小权限的 fine-grained personal access token：

`COOKIE_UPDATE_TOKEN` 的值是 GitHub 最后生成并显示的完整 token 字符串，不是布尔开关，不能填写 `true`、`false`、token 名称或仓库名称。格式通常类似下面这样，实际值会更长：

```text
github_pat_11AAAAAAA0_example_redacted
```

上面只是脱敏格式示例，不能直接使用。

1. 登录 GitHub，打开 [Fine-grained personal access tokens](https://github.com/settings/personal-access-tokens)，点击 `Generate new token`。
2. `Token name` 填写 `dounai-cookie-updater`。
3. `Expiration` 选择合适的有效期，例如 `90 days`。到期前需要生成新 token 并覆盖下面的 Secret。
4. `Resource owner` 选择拥有私有 `dounai-checkin-runner` 仓库的个人账号或组织。
5. `Repository access` 选择 `Only select repositories`，然后只勾选 `dounai-checkin-runner`。不要选择全部仓库。
6. 展开 `Repository permissions`，找到 `Secrets`，设置为 `Read and write`；其他可选权限保持 `No access`。`Metadata: Read-only` 是 GitHub 自动授予的基础权限。
7. 点击 `Generate token`，立即复制生成的 token。GitHub 只会完整显示一次。
8. 进入私有 runner 仓库：`Settings → Secrets and variables → Actions → New repository secret`。
9. `Name` 填写 `COOKIE_UPDATE_TOKEN`，`Secret` 粘贴第 7 步复制的完整 `github_pat_...` token，然后保存。不要填写 `true` 或 `false`。这个 Secret 必须建在私有 runner 仓库，不能建在公开源码仓库。
10. 进入 `Actions → Dounai session → Run workflow`，手动运行一次 `keepalive`。如果本次服务端旋转了 Cookie，日志会出现 `DOUNAI_COOKIE was updated`；没有返回新 Cookie 时，任务摘要会明确显示 Secret 保持不变。

工作流只在 Cookie 的名称或值实际变化时调用 GitHub API，并通过 `gh secret set` 在 runner 本地加密后覆盖 `DOUNAI_COOKIE`。没有变化时不重写相同 Secret；`DOUNAI_COOKIE` 的更新时间不是会话健康指标，`keepalive` 成功才表示当前会话有效。未配置 token 时签到和保活仍正常运行，但 Cookie 发生变化时不会自动回写。token 等同于密码，不要放进源码、README、Issue、聊天或 Actions 日志。若 token 显示为 `Pending`，说明所属组织要求管理员审批，批准前无法更新 Secret。详细流程见 [GitHub 官方 PAT 文档](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-fine-grained-personal-access-token)。

### 5. 手动验证

进入私有仓库：

```text
Actions → Dounai session → Run workflow
```

先选择 `keepalive`，确认 Cookie 有效；再选择 `checkin` 测试签到。`keepalive` 成功时不会打扰手机，失败时通常会发送 Bark；北京时间 00:00–08:59 只将 Action 标记为失败，不发送 Bark 或邮件。`checkin` 成功和失败都会通知，不受静默时段影响。

### 6. 自动运行时间

模板包含保活和每日一次签到两个北京时间计划：

Actions 运行列表会直接显示 `Dounai checkin` 或 `Dounai keepalive`，便于区分本次触发类型。

```yaml
schedule:
  - cron: "23 */3 * * *"
    timezone: "Asia/Shanghai"
  - cron: "17 9 * * *"
    timezone: "Asia/Shanghai"
```

- 每天 `00:23、03:23、06:23……` 保活一次。
- 每天 `09:17` 自动签到一次，失败后当天不再自动签到；仍可手动触发。
- 保活任务始终只执行保活，不会因为延迟启动而变为签到。
- 每次签到前都会先加载实际包含签到按钮的 `/user/panel` 页面并接收服务端更新的 Cookie，再以页面相同的 AJAX 请求方式调用 `/user/checkin`。
- 只有明确返回奖励到账、签到成功或今日已签到时才会标记成功；其他响应立即按失败处理。

GitHub Actions 定时任务可能因平台负载而延迟，甚至丢弃单次事件，因此不保证在 `09:17` 准点启动。工作流必须存在于默认分支。详见 [GitHub schedule 文档](https://docs.github.com/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)。

## Cookie 保活的限制

`keepalive` 会携带登录 Cookie 请求 `/user`，并检查以下结果：

- HTTP 2xx：当前会话有效。
- HTTP 401、403 或跳回登录页：会话失效，让 Action 失败；北京时间 09:00–23:59 发送 Bark 提醒。
- 服务端返回新的 `Set-Cookie`：当前进程会立即使用新 Cookie；配置 `COOKIE_UPDATE_TOKEN` 后，runner 只在 Cookie 名称或值实际变化时安全覆盖 `DOUNAI_COOKIE`，供下次任务使用。

有两个服务端行为无法由本工具保证：

1. 如果 Cookie 是固定期限而非滑动过期，或服务端没有通过 `Set-Cookie` 下发可续期凭据，到期后仍需手动登录并更新 `DOUNAI_COOKIE`。
2. Cookie 中包含 `ip`。如果服务端校验登录 IP，浏览器登录 IP 与 GitHub 托管 Runner IP 不同会导致会话失效；此时应使用固定网络出口的 [self-hosted runner](local-to-remote.md)。

## 本地使用

构建：

```shell
go build -trimpath -ldflags="-s -w" -o dounai .
```

项目使用 `go-ddddocr` 识别签到验证码，并自动计算简单的加减乘除验证码。构建需要 Go 1.25，运行目录的 `models` 子目录中需要放置 `common_old.onnx`、`charsets_old.json` 和 ONNX Runtime 1.23.2 动态库。也可通过 `DOUNAI_OCR_MODEL_DIR` 指定模型目录。Docker 镜像和示例 GitHub Actions 工作流会自动安装这些文件。

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
| `--bark_key` | `BARK_KEY` | Action 模板必填 | - | Bark 设备 Key |
| `--bark_server` | `BARK_SERVER` | 否 | `https://api.day.app` | Bark 服务地址 |
| `--checkin_time` | `CHECKIN_TIME` | 仅 `start` | `10:00` | 常驻模式签到时间，UTC+8 |

邮件通知参数 `EMAIL`、`EMAIL_HOST`、`EMAIL_PORT`、`EMAIL_AUTH_CODE` 和 `EMAIL_TLS` 均为可选。

## 安全说明

- Cookie 等同于登录凭据，只能保存在 GitHub Secrets 或其他专用密钥存储中。
- 不要把 Cookie 写入命令行参数、README、工作流源码、构建产物或日志。
- 私有 Runner 仓库应保持 Private，工作流权限保持 `contents: read`。
- 程序不会记录 Cookie 内容，错误消息也不会包含 Cookie。
- HTTP 客户端使用正常 TLS 证书校验，不再跳过 HTTPS 证书验证。
- Cookie 失效后，在浏览器重新登录并替换 `DOUNAI_COOKIE` 即可。

## 开发验证

```shell
go test -race ./...
go vet ./...
```

测试使用本地模拟服务，不需要真实 Cookie，也不会访问豆奶账号。
