# 架构与原理

## 全局数据流

```
┌──────────────┐                                                       ┌──────────────────┐
│ Claude Code  │                                                       │  GitHub Copilot  │
│   (CLI/TUI)  │                                                       │       API        │
└──────┬───────┘                                                       └────────▲─────────┘
       │                                                                        │
       │  ① Anthropic Messages API                                              │
       │  POST /v1/messages                                                     │
       │  Authorization: Bearer copilot-proxy (从 env)                          │
       │  Model: claude-opus-4-7                                                │
       │                                                                        │
       ▼                                                                        │
┌─────────────────────────────────────────────────────────────────────┐         │
│  本地代理 (localhost:18080)                                          │         │
│  ~/claude-code-copilot/scripts/proxy.mjs                            │         │
│                                                                     │         │
│  ② 协议转换：Anthropic Messages → OpenAI Chat Completions            │         │
│  ③ 模型映射：claude-opus-4-7 → claude-opus-4.6 (实测可用)            │         │
│  ④ 删掉客户端的 Authorization 头                                    │         │
│  ⑤ 用 GitHub OAuth token 换短期 Copilot Bearer token                │         │
│     (api.github.com/copilot_internal/v2/token)                      │         │
│  ⑥ 注入 Copilot Bearer + editor identity 头：                       │         │
│     - editor-version: vscode/1.110.1                                │         │
│     - editor-plugin-version: copilot-chat/0.38.2                    │         │
│     - copilot-integration-id: vscode-chat                           │         │
│     - x-github-api-version: 2025-10-01                              │         │
│                                                                     │         │
└────────────────────────────────┬────────────────────────────────────┘         │
                                 │ ⑦ OpenAI Chat Completions 协议               │
                                 │    + Copilot Bearer + editor 伪装头          │
                                 ▼                                              │
                       ┌───────────────────┐                                    │
                       │  ClashX :7890     │  (国内必需，国外可跳过)             │
                       │  (上游 HTTP 代理) │                                    │
                       └─────────┬─────────┘                                    │
                                 │                                              │
                                 └──────────────────────────────────────────────┘
```

## 关键组件

### 1. 代理脚本 `proxy.mjs`

源自 `samarth777/claude-code-copilot`，做了两处本地修改：

**修改 1：Opus 4.7 模型映射**
```js
// 原版没有 4.7 条目，会走 fallback → claude-opus-4.6
// 但当前 Business 套餐：4.7 返回 model_not_supported（API 列表里有但实际禁用），
// 4.6 反而能用。所以显式映射 4.7 → 4.6 兜底。
"claude-opus-4-7": "claude-opus-4.6",
"claude-opus-4-7-latest": "claude-opus-4.6",
"claude-opus-4-7[1m]": "claude-opus-4.6",
```

**修改 2：Haiku 兜底成 Sonnet**
```js
// Business 套餐对 haiku 返回 403 forbidden（ToS 政策）。
// Claude Code 后台任务大量用 haiku，必须兜底，否则后台任务全挂。
"claude-haiku-4-5": "claude-sonnet-4.5",
// ...其它 haiku 别名同理
```

### 2. launchd 服务 `com.jayson.claude-copilot-proxy.plist`

macOS 原生进程管理器，等价于 Linux 的 systemd user unit。配置要点：

- `RunAtLoad: true` → 开机自启
- `KeepAlive: true` → 进程崩了自动重启
- `EnvironmentVariables` → 注入 `HTTPS_PROXY=http://127.0.0.1:7890` 让代理走 ClashX
- `StandardOutPath / StandardErrorPath` → 日志重定向到 `~/Library/Logs/`

**为什么不用 Docker**：装 Docker Desktop 太重（几百 MB 内存常驻），就为跑一个 Node 进程。launchd 是 macOS 自带的，零开销、零依赖、API 稳定 20 年。

### 3. OAuth Token 存储

`~/.claude-copilot-auth.json` 存的是 GitHub OAuth token（`ghu_...` 前缀），通过 Device Flow 拿到，scope=`read:user`。这个 token 长期有效（除非用户在 GitHub 设置里撤销）。

代理每次启动时不存任何 Copilot Bearer token——它**每次请求**都用 OAuth token 去 `api.github.com/copilot_internal/v2/token` 换一个 30 分钟有效期的 Bearer token（带 quota 信息），然后用 Bearer token 调 `api.githubcopilot.com/v1/chat/completions`。

这套 OAuth → 短期 Bearer 的换发流程跟 VSCode Copilot 插件**完全一样**，所以 Copilot 服务端把它当 VSCode 看待。

### 4. zsh Alias

四个 alias 都是字符串展开，本质是在 `claude` 前加两个 env 变量：

```bash
ANTHROPIC_BASE_URL=http://localhost:18080  # 让 Claude Code 把请求发到本地代理
ANTHROPIC_API_KEY=copilot-proxy             # 占位符，代理不验证这个 key
```

为什么是 `claude-cp` 而不是修改全局配置：
- 全局配置（`~/.claude/settings.json` 的 env 段）会影响**所有** Claude Code 窗口
- 万一代理挂了，所有窗口同时报错
- alias 方案让两条路并存，互不影响

## 为什么放弃 cc-switch

cc-switch 是个支持多 provider 切换的 GUI 工具，原本期望它能搞定 Copilot 路由。实测发现两个致命问题：

1. **「启用本地路由」是全局开关**，profile 切换不清理状态。打开后所有 Claude Code 窗口（包括正在跑订阅的）都会被劫持到 localhost。
2. **Profile 切换会改写 `~/.claude/settings.json` 的 env 段**，但只追加不清理。从 Copilot 切回 default 后 env 残留，需要手动关掉本地路由开关才能恢复。

旁路方案（本包做的事）的好处：
- 完全不碰 cc-switch 和全局配置
- 日志透明（自己写的代理，每行请求都看得见）
- 模型映射可定制（应对 Copilot 后端模型目录变化）
- 跨机器可复现（plist + proxy.mjs 是纯文本，可以版本化管理）
