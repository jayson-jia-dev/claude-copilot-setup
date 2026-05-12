# Claude Code × GitHub Copilot 复刻包

让 [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 通过你的 GitHub Copilot 订阅跑（无限额度），不消耗 Anthropic 付费 quota。

- `claude` → 走 Anthropic 订阅（原来怎么用还怎么用）
- `claude-cp` → 走 Copilot 代理（无限额度，无配额焦虑）

两条路并存、互不干扰。

## 一行命令搞定

**国外网络 / 已配好梯子**：
```bash
git clone https://github.com/jayson-jia-dev/claude-copilot-setup.git ~/claude-copilot-setup && bash ~/claude-copilot-setup/scripts/install.sh
```

**国内没配 git 代理**（端口按你梯子改）：
```bash
HTTPS_PROXY=http://127.0.0.1:7890 git clone https://github.com/jayson-jia-dev/claude-copilot-setup.git ~/claude-copilot-setup && bash ~/claude-copilot-setup/scripts/install.sh
```

跑完跟着提示走完 GitHub 扫码授权（30 秒），**重开终端** → `claude-cp` 即可。

> 前置依赖：Node 18+、git、Claude Code (>= 2.1.130)、GitHub Copilot 订阅。
> Claude Code 装法见下方「装 Claude Code」一节。

## 首次启动 `claude-cp` 会问三个对话框

**对话框 ① — 必看必选**

```
Detected a custom API key in your environment
ANTHROPIC_API_KEY: sk-ant-...copilot-proxy
Do you want to use this API key?
  > 1. Yes
    2. No (recommended)   ← 默认选这个，要手动切到 1
```

→ **必须选 1. Yes**。我们就是故意用这个 key（实际上是个占位符）走本地代理的。
默认那个 "No (recommended)" 是 Claude Code 的通用建议，对我们这套场景不适用。

**对话框 ② — 工作目录信任**

```
Accessing workspace: /Users/你的用户名
Quick safety check: Is this a project you created or one you trust?
  > 1. Yes, I trust this folder
    2. No, exit
```

→ **选 1. Yes, I trust this folder**。你在自己电脑自己 home 目录下，安全的。
选 No 会直接退出 Claude Code。Claude 这个提示是为了防止你在恶意仓库里跑它误操作文件。

**对话框 ③ — 终端体验，随便选**

```
Use Claude Code's terminal setup?
For the optimal coding experience...
  > 1. Yes, use recommended settings
    2. No, maybe later with /terminal-setup
```

→ **任选都行**。这跟 Copilot 通路无关，只是 Claude Code 自身的终端体验偏好（Option+Enter 换行、视觉提醒）。
选 Yes 改终端配置，选 No 保持默认，将来想改随时 `/terminal-setup`。

安装脚本做的事（**全自动检测，无任何用户特定路径**）：
- 检查 node / git / claude 是否满足最低版本
- 克隆代理仓库到 `~/claude-code-copilot/`
- 用本包改过的 `proxy.mjs` 覆盖（含 Opus 4.7→4.6 + Haiku→Sonnet 兜底）
- 触发 GitHub Device Flow 拿 OAuth token
- **自动探测** HTTPS_PROXY（ClashX 7890、Surge 6152、V2RayX 8001 等）
- 生成 launchd plist（用当前机器的 node 路径、HOME 路径）
- 加载 launchd 服务（开机自启 + 崩溃自重启）
- 安装 `claude-cp` wrapper 到 `~/.local/bin/`（**不是 alias**，更鲁棒）
- 自动追加 `~/.local/bin` 到 PATH（如果还没在的话）
- 写辅助 alias 到 `~/.zshrc`
- curl 自测代理通路

## 装 Claude Code（国内/国外两种情况）

**国外网络可达 `claude.ai`**：
```bash
curl -fsSL https://claude.ai/install.sh | bash
```

**国内（claude.ai 被地区屏蔽，返回 HTML 错误页）**：
```bash
# 走 ClashX/Mihomo（默认 7890 端口，按你的实际改）
https_proxy=http://127.0.0.1:7890 curl -fsSL https://claude.ai/install.sh | bash
```

**任何环境也可用 npm（如果你的 npm registry 已切到国内镜像）**：
```bash
npm i -g @anthropic-ai/claude-code
```

装完**重开终端**，跑 `claude --version` 确认 >= 2.1.130 后再跑本包的 install.sh。

---

## 前置依赖

| 依赖 | 装法 | 备注 |
|---|---|---|
| Node.js 18+ | `brew install nvm && nvm install node` | 代理用 |
| git | macOS 自带或 `brew install git` | clone 用 |
| Claude Code CLI >= 2.1.130 | 见下方"装 Claude Code" | **关键**：低于这个版本不支持 ANTHROPIC_BASE_URL |
| GitHub Copilot 订阅 | 公司分配的 Business / Enterprise / 个人 Pro 都行 | 没有就没法用 |
| 网络代理（国内）| ClashX / Surge / Mihomo / V2RayX | 必须能通 `api.githubcopilot.com` |

## 为什么用 wrapper 不用 alias

| | alias（旧方案） | wrapper 脚本（现方案） |
|---|---|---|
| 实现 | `alias claude-cp='... claude'` | `~/.local/bin/claude-cp` 可执行文件 |
| `claude` 解析 | 跟 PATH 顺序走（不稳） | 主动扫描所有可能位置选最新的 |
| 老版本污染（如 /usr/local/bin/claude 是 2.1.81）| 会用到老版本，**失败** | 跳过，找下一个 |
| 同事机器适应性 | 看 PATH 命运 | **完全无视 PATH**，稳 |

wrapper 内置逻辑（按优先级查找）：
1. `~/.local/bin/claude`（Anthropic 官方安装器默认位置）
2. `~/.nvm/versions/node/*/bin/claude`（nvm 各版本，最新优先）
3. `/opt/homebrew/bin/claude`（Apple Silicon Homebrew）
4. `which claude`（PATH 兜底）
5. `/usr/local/bin/claude`（Intel Homebrew / 经典 npm）

只要任意一个版本 >= 2.1.130 就用它，找不到就报错并给出安装指引。

## 文件夹结构

```
claude-copilot-setup/
├── README.md                       ← 你正在看的
├── docs/
│   ├── architecture.md             原理 + 数据流图 + 协议转换
│   ├── troubleshooting.md          故障排查手册
│   └── known-issues.md             已知坑（cc-switch、模型可用性等）
├── files/
│   ├── proxy.mjs                   改过的代理代码（关键文件）
│   ├── claude-cp                   ★ wrapper 脚本（核心）
│   └── zshrc-aliases.sh            辅助 alias（status/restart/log）
└── scripts/
    └── install.sh                  一键安装（全自动检测）
```

## 安全说明

**本包不含 GitHub OAuth token**。

- 原因：token 是凭证，跨机器明文复制有风险
- 后果：每台机器跑 install.sh 时各自走一遍 GitHub Device Flow（浏览器扫码授权 30 秒）
- 同事用的时候各自走自己的 GitHub 账号授权，互不干扰

## 日常运维

| 命令 | 作用 |
|---|---|
| `claude-cp` | 启动 Claude Code 走 Copilot |
| `claude-cp-status` | 看代理服务状态（PID + 端口） |
| `claude-cp-restart` | 改了 proxy.mjs 后重启代理服务 |
| `claude-cp-log` | 实时跟踪代理日志 |

代理监听 `http://localhost:18080`，日志写到 `~/Library/Logs/claude-copilot-proxy.{out,err}.log`。

## 给同事用之前

1. 让同事确认自己有 Copilot 订阅（不一定是 Business，个人 Pro 也行，但模型可用性可能不一样）
2. 让同事自己装 Node + git + Claude Code（最新版）
3. 把这个文件夹给他（AirDrop / iCloud / 内网网盘 / git 仓库都行）
4. 让他在文件夹里跑 `bash scripts/install.sh`
5. 装完重开终端 → `claude-cp` 即可

如果同事是个人 Pro 而非 Business，可用模型不一样，可能需要调 `~/claude-code-copilot/scripts/proxy.mjs` 里的 `MODEL_MAP`。查实际可用模型：
```bash
~/claude-code-copilot && curl -s -X POST http://localhost:18080/v1/messages \
  -H "Content-Type: application/json" -H "x-api-key: copilot-proxy" \
  -d '{"model":"claude-opus-4-X","max_tokens":5,"messages":[{"role":"user","content":"x"}]}'
# 看 error.message 里的 "Available models: [...]" 列表
```

## 国内同事用 `claude`（订阅路径）的坑

`claude-cp` 走 localhost 代理 → Copilot，**不依赖**外网到 Anthropic。
但如果同事还想顺便用 `claude`（走他自己的订阅），就需要让 `claude` 命令也走梯子。

install.sh 探测到本地代理时会**自动**往 `~/.zshrc` 写：
```bash
export HTTPS_PROXY="http://127.0.0.1:7890"  # 端口按实测改
export HTTP_PROXY="http://127.0.0.1:7890"
export NO_PROXY="localhost,127.0.0.1,*.local"
```

**⚠ 关键警告**：检查梯子的「直连规则 / Bypass List / 绕过域名」，
**严禁**把以下域名加到绕过列表：

- `*.anthropic.com`
- `api.anthropic.com`
- `claude.ai`
- `*.claude.com`

Claude Code 必须**完整**走代理。某些梯子的预设规则会把"AI/办公"类域名当国内业务走直连，
导致 Claude Code 自检请求被 GFW 拦截，报"App unavailable in region"。
这是踩过的坑，**直连模式必死**。

ClashX 的话，打开「编辑配置文件」搜 `anthropic` 或 `claude`，
有任何 `DIRECT` 规则全改成走代理。

## 不要做的事

- ❌ 不要用 cc-switch 的 Copilot profile（已知 bug，看 `docs/known-issues.md`）
- ❌ 不要打开 cc-switch 的「启用本地路由」全局开关
- ❌ 不要把 token 文件提交到 git
- ❌ 不要跑 `claude /logout`（会清掉订阅 Keychain，所有 Claude Code 窗口一起死）
- ❌ 不要在梯子的直连规则里加 *.anthropic.com（见上面警告）

## 参考

- 上游代理仓库：https://github.com/samarth777/claude-code-copilot
- 本配置初次搭建：2026-05-12
- 配置作者：Jayson @ Reolink
