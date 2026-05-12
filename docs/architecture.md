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

源自 `samarth777/claude-code-copilot`，做了三处本地修改：

**修改 1：补 VSCode Copilot Chat client header**

原版只发 `Authorization` 和 `User-Agent`，Copilot 后端把它识别成 `copilot-language-server` 通道（权限受限）。补上：
```js
const COPILOT_CLIENT_HEADERS = {
  "Copilot-Integration-Id": "vscode-chat",
  "Editor-Version": "vscode/1.110.1",
  "Editor-Plugin-Version": "copilot-chat/0.38.2",
  "x-github-api-version": "2025-10-01",
  "Openai-Intent": "conversation-agent",
}
```
被识别为 `vscode-chat` 通道后，权限范围明显扩大（例如 Haiku 从 403 变 200）。

**修改 2：实测覆盖优先级**

每次安装跑 `detect-models.mjs` 探测当前 Copilot 套餐能用的最高级模型，写到
`~/.claude-copilot-models.json`。proxy 启动时加载，优先于硬编码 MODEL_MAP：
```js
let USER_MODEL_OVERRIDES = null
if (existsSync(USER_MODELS_FILE)) {
  USER_MODEL_OVERRIDES = JSON.parse(readFileSync(USER_MODELS_FILE, "utf8"))
}
```

**修改 3：mapModel 三级优先级**

```
USER_MODEL_OVERRIDES (实测)  >  MODEL_MAP (硬编码精确版本)  >  模式匹配 fallback
```
fallback 已校正：sonnet 系列默认兜底到 4.6（不是远古的 sonnet-4），opus 兜底到 4.6，
haiku 兜底到 4.5 自身。

### 2. launchd 服务 `com.jayson.claude-copilot-proxy.plist`

macOS 原生进程管理器，等价于 Linux 的 systemd user unit。配置要点：

- `RunAtLoad: true` → 开机自启
- `KeepAlive: true` → 进程崩了自动重启
- `EnvironmentVariables` → install.sh 探测系统代理后注入 `HTTPS_PROXY`，让代理拉 Copilot token 时也能走梯子（国内必需）
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
