# dounai-checkin

豆豆豆奶每日自动签到工具，支持自定义签到时间和邮件通知。

## 前置条件

必须是豆豆豆奶/豆奶的用户。为了遵守网站公约，本项目不提供网站地址及使用说明。

## 参数

`start` 命令支持以下参数：

| 参数 | 必填 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `--dounai_url` | 是 | - | 豆奶服务地址，必须是完整的 HTTPS URL |
| `--email` | 是 | - | 豆奶账号（邮箱） |
| `--password` | 是 | - | 登录密码 |
| `--checkin_time` | 否 | `10:00` | 每日签到时间，UTC+8，格式为 `HH:MM` |
| `--email_host` | 否 | - | SMTP 服务器地址 |
| `--email_port` | 否 | `0` | SMTP 服务器端口 |
| `--email_auth_code` | 否 | - | 邮箱客户端授权码 |
| `--email_tls` | 否 | `false` | 是否使用 SMTP TLS/SSL |

所有长参数示例统一使用 `--参数=值` 的写法。

## 编译和运行

```shell
go build -trimpath -ldflags="-s -w" -o dounai .

./dounai start \
  --dounai_url="https://example.com" \
  --email="你的邮箱" \
  --password="登录密码" \
  --checkin_time="10:00"
```

例如，每天 UTC+8 的 08:30 签到：

```shell
./dounai start \
  --dounai_url="https://example.com" \
  --email="你的邮箱" \
  --password="登录密码" \
  --checkin_time="08:30"
```

`--checkin_time` 必须是有效的 24 小时制时间，例如 `00:05`、`08:30` 或 `23:59`。程序每个自然日最多执行一次签到。

## 邮件通知

以 163 邮箱的 465 TLS/SSL 端口为例：

```shell
./dounai start \
  --dounai_url="https://example.com" \
  --email="你的邮箱" \
  --password="登录密码" \
  --checkin_time="10:00" \
  --email_host="smtp.163.com" \
  --email_port="465" \
  --email_auth_code="邮箱授权码" \
  --email_tls="true"
```

阿里云 ECS 默认可能限制 TCP 25 端口的出方向访问，建议使用邮箱服务商提供的 TLS/SSL 端口，例如 465。

### 测试邮箱连通性

```shell
./dounai test-email \
  --email="你的邮箱" \
  --email_host="smtp.163.com" \
  --email_port="465" \
  --email_auth_code="邮箱授权码" \
  --email_tls="true"
```

如果邮件参数不完整，签到仍会正常执行，但不会发送通知邮件。

## Linux x86_64 / CentOS 7

在 macOS ARM 机器上交叉编译 Linux x86_64 静态二进制：

```shell
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
  go build -trimpath -ldflags="-s -w" \
  -o dounai-linux-amd64 .

file dounai-linux-amd64
shasum -a 256 dounai-linux-amd64
```

上传到阿里云：

```shell
scp dounai-linux-amd64 root@服务器IP:/tmp/dounai

ssh root@服务器IP
install -m 755 /tmp/dounai /usr/local/bin/dounai
/usr/local/bin/dounai start --help
```

CentOS 7 上建议使用 systemd 常驻运行，详见 [local-to-remote.md](local-to-remote.md)。

## Docker

### 源码构建

```shell
docker build --progress=plain -t dounai-checkin:latest .

docker run -d \
  --name=dounai-checkin \
  --restart=always \
  --network=host \
  -e DOUNAI_URL="https://example.com" \
  -e PASSWORD="登录密码" \
  -e EMAIL="你的邮箱" \
  -e CHECKIN_TIME="10:00" \
  -e EMAIL_HOST="smtp.163.com" \
  -e EMAIL_PORT="465" \
  -e EMAIL_AUTH_CODE="邮箱授权码" \
  -e EMAIL_TLS="true" \
  dounai-checkin:latest
```

Linux 服务器上使用 `--network=host` 让容器共享宿主机网络栈，可避免 Docker bridge 的 DNS 或转发异常。本程序不监听入站端口。

查看容器日志：

```shell
docker logs -f dounai-checkin
```

使用镜像内置的 `curl` 测试容器到豆奶服务的网络连通性：

```shell
docker exec -it dounai-checkin sh -c \
  'curl --insecure --head --connect-timeout 10 --max-time 20 "$DOUNAI_URL"'
```

## 其他命令

```shell
# 查看版本
./dounai version
```

程序不会自动发现或刷新豆奶域名。域名变更后，需要更新 `--dounai_url` 或 Docker 的 `DOUNAI_URL` 并重启服务。

## 安全说明

- 当前代码会跳过登录、签到和 SMTP TLS 连接的证书校验，用于兼容证书无法验证的服务；这会降低连接安全性。
- 不要将真实密码或邮箱授权码写入 Git 仓库、镜像或公开日志。
- 如果凭据曾经出现在文档或 Git 历史中，应立即在对应服务端轮换。
