# 部署到阿里云 CentOS 7

本文提供两种部署方式：

1. 直接运行 Linux x86_64 静态二进制，并使用 systemd 守护。
2. 构建 `linux/amd64` Docker 镜像，上传后运行。

## 方式一：二进制 + systemd

### 1. 本地构建

在 macOS ARM 机器上生成 CentOS 7 x86_64 可执行文件：

```shell
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
  go build -trimpath -ldflags="-s -w" \
  -o dounai-linux-amd64 .

file dounai-linux-amd64
shasum -a 256 dounai-linux-amd64
```

`file` 的输出应包含 `ELF 64-bit`、`x86-64` 和 `statically linked`。

### 2. 上传并安装

```shell
scp dounai-linux-amd64 root@服务器IP:/tmp/dounai

ssh root@服务器IP
install -m 755 /tmp/dounai /usr/local/bin/dounai
/usr/local/bin/dounai start --help
```

如果服务器上存在旧版本，可用以下命令确认实际执行路径：

```shell
type -a dounai
command -v dounai
sha256sum "$(command -v dounai)"
```

### 3. 创建配置

```shell
vi /etc/dounai.env
```

写入：

```shell
DOUNAI_EMAIL=你的邮箱
DOUNAI_PASSWORD=登录密码
DOUNAI_URL=https://example.com
CHECKIN_TIME=10:00
EMAIL_HOST=smtp.163.com
EMAIL_PORT=465
EMAIL_AUTH_CODE=邮箱授权码
EMAIL_TLS=true
```

限制配置文件权限：

```shell
chmod 600 /etc/dounai.env
```

如果不需要邮件通知，可以从配置文件和后面的 `ExecStart` 中删除所有 `EMAIL_*` 邮件参数。

### 4. 创建 systemd 服务

```shell
vi /etc/systemd/system/dounai.service
```

写入：

```ini
[Unit]
Description=Dounai Auto Checkin
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/dounai.env
ExecStart=/usr/local/bin/dounai start --dounai_url=${DOUNAI_URL} --email=${DOUNAI_EMAIL} --password=${DOUNAI_PASSWORD} --checkin_time=${CHECKIN_TIME} --email_host=${EMAIL_HOST} --email_port=${EMAIL_PORT} --email_auth_code=${EMAIL_AUTH_CODE} --email_tls=${EMAIL_TLS}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

启动并设置开机自启：

```shell
systemctl daemon-reload
systemctl enable --now dounai
```

查看状态和日志：

```shell
systemctl status dounai
journalctl -u dounai -f
```

修改 `/etc/dounai.env` 后重启服务：

```shell
systemctl restart dounai
```

## 方式二：Docker

### 1. 本地构建并打包 x86_64 镜像

```shell
(docker image rm --force checkin:latest >/dev/null 2>&1 || true) && \
rm -f ./checkin-latest.tar.gz && \
docker buildx build \
  --platform=linux/amd64 \
  --tag=checkin:latest \
  --load \
  . && \
docker image inspect checkin:latest \
  --format='{{.Os}}/{{.Architecture}}' && \
(docker save checkin:latest | gzip > ./checkin-latest.tar.gz)
```

预期输出：

```text
linux/amd64
```

### 2. 上传

```shell
rsync -avP \
  ./checkin-latest.tar.gz \
  root@服务器IP:/root/
```

### 3. 服务器清理并加载镜像

```shell
(docker container rm --force dounai-checkin >/dev/null 2>&1 || true) && \
(docker image rm --force checkin:latest >/dev/null 2>&1 || true) && \
(gunzip -c /root/checkin-latest.tar.gz | docker load) && \
docker image inspect checkin:latest \
  --format='{{.Os}}/{{.Architecture}}'
```

### 4. 启动容器

`DOUNAI_URL` 是必填项，必须传入完整的 HTTPS URL。程序不会再从其他页面解析域名。

CentOS 7 上使用 `--network=host` 让容器共享宿主机网络栈，避免 Docker bridge 的 DNS 或转发异常。本程序不监听入站端口。

```shell
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
  checkin:latest
```

查看容器状态和日志：

```shell
docker ps --filter=name=dounai-checkin
docker logs -f dounai-checkin
```

使用镜像内置的 `curl` 测试容器到豆奶服务的网络连通性：

```shell
docker exec -it dounai-checkin sh -c \
  'curl --insecure --head --connect-timeout 10 --max-time 20 "$DOUNAI_URL"'
```

返回 HTTP 响应头说明容器已通过宿主机网络完成 DNS 解析并访问外部 HTTPS 服务。如果仍然超时，需要检查宿主机网络、防火墙、阿里云安全组或 DNS。

## 手动测试

测试邮件连通性：

```shell
/usr/local/bin/dounai test-email \
  --email="你的邮箱" \
  --email_host="smtp.163.com" \
  --email_port="465" \
  --email_auth_code="邮箱授权码" \
  --email_tls="true"
```

手动前台启动：

```shell
/usr/local/bin/dounai start \
  --dounai_url="https://example.com" \
  --email="你的邮箱" \
  --password="登录密码" \
  --checkin_time="10:00"
```

## 安全提示

- 示例中只使用占位符，不要把真实密码、邮箱或授权码提交到 Git。
- 当前程序会忽略登录、签到和 SMTP TLS 连接的证书校验。
- 程序不再访问域名发现页；域名变更后，需要更新 `DOUNAI_URL` 并重启服务。
- 如果真实凭据曾出现在文档或 Git 历史中，请立即在对应服务端轮换。
