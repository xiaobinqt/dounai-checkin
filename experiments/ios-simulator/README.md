# GitHub Actions iOS 模拟器实验

目标：让 GitHub macOS runner 启动 iOS Simulator，安装并在前台运行实验应用，验证不依赖手机后台常驻的签到方案。它不是完整手机系统镜像，也不控制你的真机。

实验应用直接编译 `main` 的 iOS 签到、验证码和日志代码，固定版本为 `06b1e92b0ac6ce00a674c577ab05c00ebc41d378`，不会修改或重新安装你的手机应用。实验入口不包含网页登录 UI，真实运行需要提前准备登录 Cookie。

## 三种模式

| 模式 | 行为 | 能说明什么 |
| --- | --- | --- |
| `smoke`（默认） | 启动模拟器、安装应用；真实 Vision PNG 识别、SVG 算式、模拟 HTTP 签到、验证码补试、POST 中断不重试、Cookie 更新 | 证明 iOS 程序和 OCR 能在 runner 的模拟器中实际运行，不是只编译成功 |
| `inspect` | 只 GET 签到页面和验证码接口，记录 HTTP 状态、JSON 类型/字段存在性、固定消息分类 | 诊断验证码为何未被接受，不识别验证码、不调用签到 POST；`inspected` 不代表签到成功 |
| `checkin` | 携带指定 Cookie 请求真实站点，运行一次现有 iOS 签到流程 | 只有此模式返回 `passed` 才代表云端真实签到或服务器确认今日已签到 |

`smoke` 的 HTTP 全部由进程内 URLProtocol 接管，不访问网站、不消耗真实验证码、不发送通知。`checkin` 保留 iOS 核心的有限验证码安全补试；不会在外层重试整个任务，也不会因 POST 超时自动再提交。实验暂不发送 Bark/邮件，以 Actions 摘要为准。

`inspect` 使用模拟器中的原生 URLSession 和同样的 iOS User-Agent、Cookie/AJAX 请求头；拒绝跳转，不向其他源转发 Cookie。输出白名单中的字段及分类，并仅在私有运行中记录脱敏后的 `msg`（`messageRedacted`）：先去除请求与响应 Cookie 值，再遮盖邮箱、IP、URL、凭据字段和长令牌，合并成单行并限制为 320 字。不输出任意 JSON 键名、票据、图片或完整响应正文。它会请求一张验证码，但绝不提交答案。离线回归同时检查诊断的脱敏和仅 GET 边界。

## 云端运行

公开源码分支 `.github/workflows/ios-simulator-probe.yml` 在实验代码推送后仅运行 `smoke`。它也提供 `workflow_call`，供私有 runner 仓库手动测试真实账号。

将 [私有 runner 模板](../../examples/ios-simulator-runner.yml) 复制到你已有私有 runner 仓库默认分支的 `.github/workflows/ios-simulator.yml`。不需要替换旧 Go 工作流，也没有新增每日计划。

在**私有 runner 仓库**配置：

- `DOUNAI_URL`：HTTPS 站点根地址。
- `DOUNAI_COOKIE`：手动登录后复制的完整 Cookie。
- `DOUNAI_USER_AGENT`：可选；与获取 Cookie 时的浏览器保持一致，默认使用 iOS 应用的 User-Agent。
- `COOKIE_UPDATE_TOKEN`：可选；仅该私有仓库 `Secrets: Read and write` 权限的 PAT。服务器更新 Cookie 时自动保存；不配置会提示新 Cookie 被丢弃，不影响本次已确认的签到。创建方式见根目录 README。

进入 `Actions → Dounai iOS simulator experiment → Run workflow`：先选择 `smoke`，再视需要选择 `inspect` 或 `checkin`。凭据只放 Secrets，不放 workflow 输入或源码。公开源码分支不是默认分支，所以手动入口放在私有仓库默认分支，不依赖直接在此分支注册 `workflow_dispatch`。

真实测试尽量选当天尚未签到时进行。若服务端只返回“今日已签到”，只能证明本次会话被服务器接受，不能据此推断新的验证码挑战已经通过。若提交后断网或超时，先查看网页状态，不要直接重跑。

## 本地验证

需要完整 Xcode、已安装的 iOS 18 或更新模拟器运行时、`jq`，以及上述固定版本且无 iOS 源码修改的 `main` checkout：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  bash experiments/ios-simulator/run.sh /path/to/main-checkout /tmp/new-probe-output
```

输出目录必须不存在，防止把旧结果误认为新结果。脚本创建专用模拟器，结束后只关闭并删除这个临时设备，不触碰已有模拟器或 iPhone。模拟器启动等待有 10 分钟上限，应用结果等待有 120 秒上限；云端将编译和启动分成独立步骤，不主动取消正在执行的任务。生成的无凭据编译目录会保留，便于检查；凭据和完整容器不会上传为 artifact。`result.json` 和日志输出固定事件、分类、HTTP 状态、数量，以及私有诊断中的脱敏 `msg`，不输出完整网站正文、Cookie、验证码或未经脱敏的服务端消息。Cookie 单独存为权限 `0600` 的 `cookie` 文件；本地真实测试后请妥善保管或删除它。

## 验证记录

2026-10-17：本地 iOS 模拟器验证通过；[GitHub macOS runner 的完整离线实验通过](https://github.com/xiaobinqt/dounai-checkin/actions/runs/39003449123)，耗时约 5 分钟，包含真实 Vision PNG 识别及模拟 HTTP 回归。尚未验证云端真实账号签到，不能据此宣称网站风控问题已解决。

## 尚未解决的限制

- GitHub 云端出口 IP 不会因模拟器改变；网站风控、Cookie 的 IP/设备绑定能否通过必须真实验证。
- 新 job 没有上次模拟器的数据；当前通过 Secrets 导入/回写 Cookie，不同步手机 Keychain。
- 当前只做手动实验，不保证每日签到。尚无跨 job 的成功日/提交未知状态持久化，不应直接加 schedule 或自动失败重跑。
- 未验证 Android 模拟器；当前实验不修改 Android 构建。
