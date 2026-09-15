# 更新日志

这里记录会影响部署、配置或运行行为的变更。下方旧版本中的 GitHub Actions 签到配置已是历史记录；该方案现已失效，相关模板已移除。

## 2026-09-15：Android 1.0.1

- 网站登录页改为全屏显示；修复网站原密码栏连续输入时字符被覆盖的问题，顶部显示实际输入的字符数。邮箱、密码和算式验证码都由网站原页面输入并提交。APK 不保存登录密码。
- 开启每日自动签到后，每约 3 小时访问 `/user` 刷新并接收服务端 Cookie。明确登录失效时只发一次 Bark 提醒，临时断网不按登录失效处理。
- v1.0.0 和 v1.0.1 使用不同的自动调试签名；安装 v1.0.1 前须先卸载 v1.0.0，旧版 Cookie 和通知配置会被清除。Go 命令行不需要修改；旧 GitHub Actions 定时签到方案已失效。

## 2026-09-05：签到验证码与单次执行策略

### 主要变化

- 签到前请求同域 `/auth/captcha?type=checkin&_=随机值`，随后将答案作为 `captcha_code` 提交到 `/user/checkin`。
- 支持新版 challenge 校验：使用网页相同的 SHA-256 规则生成 `checkin_token`，并保持蜜罐字段 `checkin_secret` 为空；验证码请求的 `_` 参数改为浏览器一致的纯数字格式。
- 跟进新版动态盐校验：读取验证码响应中的 `seed` 和 `salt_mask`，结合 challenge nonce 生成动态盐，再计算本次签到的 `checkin_token`；旧版固定盐继续兼容。
- PNG OCR 字符范围增加中文数字以及“加、减、乘、除”，避免新版图片算式中的中文字符被过滤。
- 整图 OCR 缺字时，按验证码固定布局分区识别两个操作数和运算符，再组合计算，降低随机颜色和干扰线造成的漏字概率。
- 对原图及两档高对比度图分别执行整图、分区 OCR；算术验证码至少两条路径得到相同答案才提交，无法达成共识时安全停止。
- 当时已经同步私有 Runner YAML 的用户无需再改 YAML 或 Secrets；此记录不再适用于现在的签到部署。
- 优先直接读取 SVG 的 `<text>` 内容，支持阿拉伯数字、中文大小写数字、全角字符以及加减乘除；旧版 Base64 PNG 继续通过 `go-ddddocr` 识别。
- Go 版本升级到 1.25；PNG 识别需要 `go-ddddocr` 模型和 ONNX Runtime 1.23.2。
- 每次任务只尝试签到一次。签到失败后程序立即退出，当天也不再安排自动补偿签到；仍可在 Actions 页面手动运行 `checkin`。
- 验证码或签到失败时，按请求顺序记录验证码 URL、验证码完整 response body、提取出的算式或字符、提交的 `captcha_code` 以及签到完整 response body；JSON 中的 Unicode 转义会显示为可读文字，日志不会包含 Cookie 值。

### 历史记录：当时需要同步私有 Runner 工作流

这段是旧版本的部署记录。当时的签到工作流模板已移除，不应再复制到私有仓库：

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
- 当时使用“公开源码仓库 + 私有 runner 仓库”部署结构；这条 GitHub Actions 签到路径现在已失效。
