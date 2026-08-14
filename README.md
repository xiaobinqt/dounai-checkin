# dounai-checkin

豆豆豆奶每日自动签到工具。推荐使用 GitHub Actions：每天启动一次临时 Runner，完成登录、签到和 Bark 通知后立即退出，不需要 VPS 或常驻容器。

## 功能

- GitHub Actions 每天自动签到
- 支持在 Actions 页面手动签到
- 签到失败时最多自动重试三次
- 签到成功、失败均可发送 Bark 通知
- 保留邮件通知、本地常驻和 Docker 运行方式

## 前置条件

必须是豆豆豆奶/豆奶的用户。为了遵守网站公约，本项目不提供网站地址及使用说明。

## 使用 GitHub Actions（推荐）

推荐使用“公开源码 + 私有 Runner”方式。源码始终从本项目获取，个人账号和 Bark Key 只保存在自己的私有仓库中：

```text
xiaobinqt/dounai-checkin (Public)
              ↓ 每次拉取最新 main
你的 dounai-checkin-runner (Private)
              ↓
          test → build → once
              ↓
        豆奶签到 + Bark 通知
```

这种方式不需要 Fork，也不需要在两个仓库之间同步代码。公开源码更新后，下一次 Action 会自动使用最新版本。

### 1. 创建私有 Runner 仓库

打开 [GitHub 新建仓库页面](https://github.com/new?name=dounai-checkin-runner&visibility=private)，创建一个空仓库：

```text
Repository name: dounai-checkin-runner
Visibility: Private
```

不要初始化 README、`.gitignore` 或 License。

### 2. 复制工作流模板

本项目提供了可直接使用的 [examples/checkin-runner.yml](examples/checkin-runner.yml)。在新建的私有仓库中选择：

```text
Add file
→ Create new file
→ 文件名填写 .github/workflows/checkin.yml
→ 复制 examples/checkin-runner.yml 的全部内容
→ Commit changes
```

模板默认会从 `xiaobinqt/dounai-checkin` 的 `main` 分支拉取公开源码，不需要额外 GitHub Token。

### 3. 配置 Secrets

打开刚创建的私有 Runner 仓库：

```text
Settings
→ Secrets and variables
→ Actions
→ New repository secret
```

添加以下 Repository Secrets：

| Secret | 必填 | 说明 |
| --- | --- | --- |
| `DOUNAI_URL` | 是 | 豆奶服务完整地址，例如 `https://example.com` |
| `DOUNAI_EMAIL` | 是 | 豆奶登录邮箱 |
| `DOUNAI_PASSWORD` | 是 | 豆奶登录密码 |
| `BARK_KEY` | 是 | Bark 首页推送地址最后一段的设备 Key |
| `BARK_SERVER` | 否 | Bark 服务地址，默认 `https://api.day.app` |

`BARK_KEY` 示例：如果 Bark App 中显示的地址是：

```text
https://api.day.app/abcdefg
```

则只保存：

```text
abcdefg
```

不要把完整地址或 Key 直接写进工作流文件。

### 4. 手动测试

工作流和 Secrets 配置完成后，进入私有 Runner 仓库：

```text
Actions
→ Daily check-in
→ Run workflow
```

第一次应先手动运行，不要等到第二天。运行成功时，`Check in` 步骤会显示签到结果，配置了 `BARK_KEY` 时手机也会收到通知。

### 5. 每天自动运行

模板会每天自动触发一次：

```yaml
schedule:
  - cron: "17 10 * * *"
    timezone: "Asia/Shanghai"
```

这表示每天北京时间 10:17。要改为每天 08:30：

```yaml
schedule:
  - cron: "30 8 * * *"
    timezone: "Asia/Shanghai"
```

建议避开 `xx:00` 整点；GitHub Actions 调度高峰时可能延迟，签到不保证秒级准时。关于时区、默认分支和调度限制可查看 [GitHub schedule 官方文档](https://docs.github.com/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)。

如果没有自动触发，请检查：

- `.github/workflows/checkin.yml` 是否已经提交到默认分支
- 仓库的 Actions 是否启用
- `Daily check-in` 工作流是否被手动禁用
- Secrets 名称是否与上表完全一致

工作流位于私有 Runner 仓库，不受公开仓库连续 60 天无活动时自动停用 scheduled workflow 的规则影响。

## 工作流安全设计

- 账号、密码和 Bark Key 只通过 GitHub Secrets 注入。
- 私有 Runner 每次运行时拉取公开源码，不需要复制或同步源码仓库。
- Secrets 只提供给配置校验和最终签到步骤，checkout、Go 环境安装和构建步骤无法读取这些凭据。
- 工作流只有 `contents: read` 权限。
- `concurrency` 防止手动任务与定时任务重复运行。
- 单次任务最多运行 10 分钟，程序不会像常驻服务一样持续占用 Runner。
- 每次签到前先运行单元测试，代码异常时不会继续使用凭据请求签到服务。

## 本地执行一次

推荐用环境变量，避免凭据出现在命令行历史中：

```shell
go build -trimpath -ldflags="-s -w" -o dounai .

DOUNAI_URL="https://example.com" \
DOUNAI_EMAIL="你的邮箱" \
DOUNAI_PASSWORD="登录密码" \
BARK_KEY="你的 Bark Key" \
./dounai once
```

`checkin` 是 `once` 的别名：

```shell
./dounai checkin \
  --dounai_url="https://example.com" \
  --email="你的邮箱" \
  --password="登录密码" \
  --bark_key="你的 Bark Key"
```

`once` 会登录、最多重试三次签到、发送通知，然后立即退出。签到失败会返回非零退出码，因此 GitHub Actions 会将任务标记为失败。

## 命令参数与环境变量

| 参数 | 环境变量 | `once` 必填 | 默认值 | 说明 |
| --- | --- | --- | --- | --- |
| `--dounai_url` | `DOUNAI_URL` | 是 | - | 豆奶服务完整 HTTPS URL |
| `--email` | `DOUNAI_EMAIL` | 是 | - | 豆奶登录邮箱 |
| `--password` | `DOUNAI_PASSWORD` | 是 | - | 豆奶登录密码 |
| `--bark_key` | `BARK_KEY` | 否 | - | Bark 设备 Key |
| `--bark_server` | `BARK_SERVER` | 否 | `https://api.day.app` | Bark 服务地址 |
| `--email_host` | `EMAIL_HOST` | 否 | - | SMTP 服务器地址 |
| `--email_port` | `EMAIL_PORT` | 否 | `0` | SMTP 服务器端口 |
| `--email_auth_code` | `EMAIL_AUTH_CODE` | 否 | - | 邮箱客户端授权码 |
| `--email_tls` | `EMAIL_TLS` | 否 | `false` | 是否使用 SMTP TLS/SSL |
| `--checkin_time` | `CHECKIN_TIME` | 仅 `start` | `10:00` | 常驻模式签到时间，UTC+8 |

命令行参数优先于环境变量。Bark 推送使用官方 JSON POST 接口，格式可参考 [Bark 官方教程](https://github.com/Finb/Bark/blob/master/docs/en-us/tutorial.md)。

## 邮件通知（可选）

GitHub Secrets 还可以配置：

```text
EMAIL_HOST
EMAIL_PORT
EMAIL_AUTH_CODE
EMAIL_TLS
```

以 163 邮箱 465 TLS/SSL 端口为例，本地测试：

```shell
./dounai test-email \
  --email="你的邮箱" \
  --email_host="smtp.163.com" \
  --email_port="465" \
  --email_auth_code="邮箱授权码" \
  --email_tls="true"
```

邮件参数不完整时不会影响签到和 Bark 通知。

## 常驻与 Docker 模式（兼容）

`start` 仍然支持本地服务器常驻运行，它会每 20 秒检查一次时间：

```shell
./dounai start \
  --dounai_url="https://example.com" \
  --email="你的邮箱" \
  --password="登录密码" \
  --checkin_time="10:00"
```

Docker 源码构建：

```shell
docker build --progress=plain -t dounai-checkin:latest .

docker run -d \
  --name=dounai-checkin \
  --restart=always \
  -e DOUNAI_URL="https://example.com" \
  -e EMAIL="你的邮箱" \
  -e PASSWORD="登录密码" \
  -e CHECKIN_TIME="10:00" \
  dounai-checkin:latest
```

服务器二进制、systemd 和 Docker 的旧部署说明见 [local-to-remote.md](local-to-remote.md)。GitHub Actions 模式不需要 Dockerfile，也不需要服务器。

## 安全说明

- 不要将真实密码、Bark Key 或邮箱授权码提交到 Git 仓库、镜像或日志。
- 无论仓库是 Public 还是 Private，都应始终使用 GitHub Secrets 保存凭据。
- 当前豆奶登录、签到和 SMTP TLS 连接会跳过证书校验，用于兼容证书无法验证的服务；这会降低连接安全性。Bark 通知使用正常的 TLS 证书校验。
- 如果凭据曾出现在文档或 Git 历史中，应立即在对应服务端轮换。
- 程序不会自动发现豆奶域名；域名变更后需要更新 `DOUNAI_URL`。
