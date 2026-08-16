# 使用固定出口的 self-hosted runner

如果豆奶 Cookie 校验登录 IP，浏览器获得的 Cookie 可能无法在 GitHub 托管 Runner 上使用。此时可在家中设备或 VPS 安装 GitHub self-hosted runner，让保活和签到从固定网络出口执行。

## 1. 准备主机

主机需要：

- 能访问豆奶服务和 GitHub
- 固定或较稳定的公网出口 IP
- Go 环境
- 长期在线

不要把 Cookie 写入主机镜像、安装脚本或公开配置文件。

## 2. 注册 Runner

在私有 `dounai-checkin-runner` 仓库打开：

```text
Settings → Actions → Runners → New self-hosted runner
```

根据 GitHub 页面为对应操作系统生成的命令完成下载、配置和服务安装。注册令牌是短期敏感凭据，不要提交到仓库。

官方说明见 [Adding self-hosted runners](https://docs.github.com/actions/hosting-your-own-runners/managing-self-hosted-runners/adding-self-hosted-runners)。

## 3. 修改工作流

将私有仓库 `.github/workflows/checkin.yml` 中：

```yaml
runs-on: ubuntu-latest
```

改为：

```yaml
runs-on: [self-hosted, linux, x64]
```

标签应与 GitHub Runners 页面显示的标签一致。

## 4. 获取并配置 Cookie

最好让浏览器登录和 self-hosted runner 使用同一公网出口。手动完成验证码登录后，从浏览器 `/user` 请求复制完整 Cookie，保存为私有仓库的 `DOUNAI_COOKIE` Repository Secret。

其他必填 Secrets：

```text
DOUNAI_URL
BARK_KEY
```

若希望 self-hosted runner 也自动保存服务端旋转后的 Cookie，可按主 README 的说明配置仅限当前私有仓库、具有 `Secrets: Read and write` 权限的 `COOKIE_UPDATE_TOKEN`。

## 5. 验证

在 Actions 页面手动执行：

1. `keepalive`
2. `checkin`

如果 `keepalive` 仍返回 401/403，重新登录获取 Cookie，并确认浏览器和 Runner 的公网出口 IP 相同。

## 安全提示

- self-hosted runner 只用于受信任的私有仓库和工作流。
- 定期更新操作系统、GitHub Runner 和 Go。
- 不要在 Runner 日志中输出环境变量。
- Cookie 无法继续保活后只需更新 GitHub Secret，不需要修改源码。
