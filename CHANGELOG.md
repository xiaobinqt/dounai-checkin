# 更新日志

这里记录会影响部署、配置或运行行为的变更。只拉取公开仓库最新代码并不总是足够；标有“需要操作”的版本还要同步私有 runner 工作流或更新 Secrets。

## 2026-09-05：签到验证码与单次执行策略

### 主要变化

- 签到前请求同域 `/auth/captcha?type=checkin&_=随机值`，随后将答案作为 `captcha_code` 提交到 `/user/checkin`。
- 优先直接读取 SVG 的 `<text>` 内容，支持阿拉伯数字、中文大小写数字、全角字符以及加减乘除；旧版 Base64 PNG 继续通过 `go-ddddocr` 识别。
- Go 版本升级到 1.25；PNG 识别需要 `go-ddddocr` 模型和 ONNX Runtime 1.23.2。
- 每次任务只尝试签到一次。签到失败后程序立即退出，当天也不再安排自动补偿签到；仍可在 Actions 页面手动运行 `checkin`。
- 验证码或签到失败时，按请求顺序记录验证码 URL、验证码完整 response body、提取出的算式或字符、提交的 `captcha_code` 以及签到完整 response body；JSON 中的 Unicode 转义会显示为可读文字，日志不会包含 Cookie 值。
- 请求保留 Cookie、User-Agent、Accept、Accept-Language、Referer、Origin、Content-Type 和 X-Requested-With，不再伪造 `Sec-CH-UA*`、`Sec-Fetch-*`、`Priority`。

### 需要操作：同步私有 Runner 工作流

使用私有 `dounai-checkin-runner` 仓库的用户必须把最新的 [examples/checkin-runner.yml](examples/checkin-runner.yml) 覆盖到私有仓库的：

```text
.github/workflows/checkin.yml
```

新版私有工作流包含以下必要变化：

- `actions/setup-go` 根据公开源码的 `go.mod` 安装 Go 1.25。
- 下载 `common_old.onnx`、`charsets_old.json` 和 ONNX Runtime 1.23.2。
- 为签到进程设置 `DOUNAI_OCR_MODEL_DIR=${{ github.workspace }}/source/models`。
- 每天只在北京时间 `09:17` 自动签到一次；每三小时的任务始终只执行保活。
- 删除签到补偿计划和每日签到 Actions Cache。

如果不更新私有 YAML，旧 PNG 验证码可能报 `models/libonnxruntime.so: no such file or directory`，旧计划也会在同一天重复触发签到。

### 需要检查：私有仓库 Secrets

- `DOUNAI_URL`：如果服务域名已经变化，更新为当前完整 HTTPS 地址；源码不固定域名。
- `DOUNAI_COOKIE`：从当前域名的浏览器请求中重新复制完整 Cookie，不能只复制个别字段。通常应包含会话 Cookie 和 `uid`、`email`、`key`、`ip`、`expire_in` 等站点字段。
- 其他 Secret 名称没有变化。`BARK_KEY` 仍为必填；邮件通知和 `COOKIE_UPDATE_TOKEN` 仍为可选。

同步后，在私有仓库依次手动运行一次 `keepalive` 和 `checkin`。确认成功后再依赖定时任务。

### Docker 和本地运行

- Docker 用户需要重新构建镜像。新版 Dockerfile 会按 AMD64 或 ARM64 自动安装对应的 ONNX Runtime。
- 本地直接运行二进制时，需要准备模型目录，并通过 `DOUNAI_OCR_MODEL_DIR` 指向它；详细说明见 [README](README.md)。

## 2026-09-02：Cookie 会话模式

- 登录改为由用户在浏览器中手动完成，程序复用 `DOUNAI_COOKIE`，不再保存豆奶账号密码。
- 增加每三小时登录态保活、服务端 Cookie 轮换接收，以及可选的私有仓库 Secret 自动回写。
- 推荐使用“公开源码仓库 + 私有 runner 仓库”部署结构，避免 Cookie 和通知凭据进入公开仓库。
