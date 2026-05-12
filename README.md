<div align="center">

# claude-copilot-setup

**用你的 GitHub Copilot 订阅跑 Claude Code**
*Run Claude Code through your GitHub Copilot subscription — local proxy, zero Anthropic API cost.*

[![Platform](https://img.shields.io/badge/platform-macOS-blue.svg)](#-局限--注意)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Node](https://img.shields.io/badge/node-%E2%89%A518-brightgreen.svg)](https://nodejs.org/)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-%E2%89%A52.0-orange.svg)](https://docs.anthropic.com/en/docs/claude-code)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](#-贡献)

让 [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 借道你已经付过钱的 GitHub Copilot，无需 Anthropic API key、不烧 Anthropic 订阅 quota。

[快速开始](#-快速开始) ·
[原理](#-原理) ·
[FAQ](#-faq) ·
[踩坑实录](#-踩坑实录) ·
[升级 / 卸载](#-升级--卸载)

</div>

---

## 🚀 快速开始

**一条命令搞定**（已配代理或国外网络）：

```bash
curl -fsSL https://raw.githubusercontent.com/jayson-jia-dev/claude-copilot-setup/main/bootstrap.sh | bash
```

**国内未配 git 代理**（端口换成你梯子的实际端口）：

```bash
HTTPS_PROXY=http://127.0.0.1:7890 bash -c "$(curl -fsSL https://raw.githubusercontent.com/jayson-jia-dev/claude-copilot-setup/main/bootstrap.sh)"
```

跟着提示走完 GitHub Device Flow 扫码（30 秒），重开终端跑 `claude-cp`。

> **前置依赖**：Node 18+、git、Claude Code CLI、GitHub Copilot 订阅（任何套餐都行）

---

## 💡 原理

在本机起一个**伪装成 VSCode Copilot Chat 插件**的 Node 代理（监听 `localhost:18080`）：

1. Claude Code 用 Anthropic 协议向 `localhost:18080` 发请求
2. 代理把 Anthropic Messages API 翻译成 OpenAI Chat Completions
3. 代理用你的 GitHub OAuth token 换出 Copilot 短期 Bearer
4. 套上 VSCode 标识头（`Copilot-Integration-Id: vscode-chat` 等），转发到 `api.githubcopilot.com`

Copilot 服务端把它当 VSCode 看待，你的订阅照常工作，Claude Code 不知道自己被劫持了。

```
┌──────────────┐    ① Anthropic API     ┌─────────────┐    ② OpenAI API     ┌──────────────────────┐
│ Claude Code  │ ─────────────────────▶ │   Proxy     │ ──────────────────▶ │ api.githubcopilot.com│
│              │  POST /v1/messages     │ :18080      │ + VSCode 伪装头     │                      │
└──────────────┘                        └─────────────┘                     └──────────────────────┘
                                              │
                                              ▼
                                     ~/.claude-copilot-auth.json
                                     (GitHub OAuth token)
```

---

## ✨ 特性

- **零 Anthropic 成本** — 走 Copilot 订阅，配额按 Copilot 计算
- **装机时实测模型可用性** — 自动探测当前套餐能用的最高级 opus/sonnet/haiku，不用人工配
- **跨套餐自适应** — Pro / Business / Enterprise 都行，模型不同自动处理
- **跨梯子自适应** — ClashX / Clash Verge / Mihomo / Surge / V2RayX 端口都识别
- **不污染订阅** — `claude` 和 `claude-cp` 双命令并存，订阅功能完整保留
- **launchd 守护** — 开机自启、崩溃自恢复，零运维
- **透明日志** — 每个请求的模型映射都写进日志，所见即所得

---

## 📦 安装详解

### 1. 装 Claude Code CLI（如果还没装）

```bash
# 国外
curl -fsSL https://claude.ai/install.sh | bash

# 国内（端口按你梯子改）
HTTPS_PROXY=http://127.0.0.1:7890 curl -fsSL https://claude.ai/install.sh | bash
```

⚠ **关键提醒**：检查你梯子的「直连规则 / Bypass List」，**严禁**把 `*.anthropic.com` / `claude.ai` / `*.claude.com` 加到绕过列表 —— Claude Code 必须完整走代理，否则启动时的 region check 会被 GFW 拦掉。

### 2. 跑 bootstrap

见上方 [快速开始](#-快速开始)。bootstrap 做的事：

- 克隆本仓库到 `~/claude-copilot-setup`
- 调用 `scripts/install.sh`

### 3. install.sh 自动完成

| 步骤 | 内容 |
|---|---|
| 1 | 检测 node / git / claude 版本 |
| 2 | 克隆 [samarth777/claude-code-copilot](https://github.com/samarth777/claude-code-copilot)，用本仓库改过的 `proxy.mjs` 覆盖 |
| 3 | 触发 GitHub Device Flow 拿 Copilot OAuth token |
| 4 | 探测本地 HTTP 代理端口（ClashX/Verge/Surge/V2Ray 全覆盖） |
| 5 | 生成 launchd plist 并加载 |
| 6 | 跑 `detect-models.mjs` 实测当前套餐可用的最高级模型 |
| 7 | 装 wrapper 到 `~/.local/bin/claude-cp`、写辅助 alias |
| 8 | curl 自测代理通路 |

### 4. 首次启动 `claude-cp` 三个对话框

| 对话框 | 选什么 |
|---|---|
| **Detected a custom API key** | **1. Yes**（默认是 No, recommended，要手动改）|
| **Accessing workspace - Trust this folder** | **1. Yes, I trust this folder** |
| **Use Claude Code's terminal setup** | 任选（与 Copilot 无关）|

### 5. 验证装好了

```bash
# A. 服务有没有跑
claude-cp-status
# 期望看到：
#   <PID>    0    com.jayson.claude-copilot-proxy
#   node   <PID>   ... TCP *:18080 (LISTEN)

# B. 端到端 smoke test（不开 Claude Code 也能跑）
curl -s -X POST http://localhost:18080/v1/messages \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -H "x-api-key: copilot-proxy" \
  -d '{"model":"claude-sonnet-4-5","max_tokens":15,"messages":[{"role":"user","content":"reply: ok"}]}'
# 期望返回:  {"id":"msg_...","content":[{"type":"text","text":"ok"}],...}

# C. 看实测可用模型清单
cat ~/.claude-copilot-models.json
# 例: {"opus": "claude-opus-4.6", "sonnet": "claude-sonnet-4.6", "haiku": "claude-haiku-4.5"}

# D. 看代理实时映射 Claude 请求
claude-cp-log
# Claude Code 跑起来后会看到:
#   → claude-opus-4-7  → claude-opus-4.6  | stream | 5 messages
```

如果 A/B/C 任意一步不对，跳到 [踩坑实录](#-踩坑实录) 找相似症状。

---

## 🛠 日常使用

```bash
claude                    # Anthropic 订阅
claude-cp                 # 走 Copilot 代理
claude-cp-status          # 看代理 PID / 端口
claude-cp-log             # 实时跟踪代理日志
claude-cp-restart         # 重启代理服务
claude-cp-detect-models   # 重新探测可用模型（套餐升级 / 模型上下架时跑）
```

代理监听 `http://localhost:18080`，日志在 `~/Library/Logs/claude-copilot-proxy.{out,err}.log`。

---

## 🤔 FAQ

**Q：界面顶部显示 "Opus 4.7"，是真的吗？**
A：不是。那是 Claude Code 客户端的标签，跟实际用什么模型无关。实际发到 Copilot 的模型由代理决定。跑 `claude-cp-log` 看 `→` 右侧才是真模型名。

**Q：这违反 GitHub Copilot 服务条款吗？**
A：技术上代理伪装成 VSCode Copilot Chat 插件，跟 VSCode 行为差异不大。但严格说这是 reverse-engineered 用法，GitHub 没明确背书。**不建议在生产/商业场景重度依赖**——既要无限额度，又要合规，需要走 GitHub 官方支持的 API（目前没有等价接口）。

**Q：会被 GitHub 封号吗？**
A：截至 README 写作时，社区有大量类似工具（[copilot-api](https://github.com/ericc-ch/copilot-api)、[claude-code-copilot](https://github.com/samarth777/claude-code-copilot) 等），没听到批量封号事件。但**理论存在风险**，特别是大量并发 / 异常 token 用法。**Business / Enterprise 账号比个人账号更稳妥**。

**Q：模型清单不对怎么办？**
A：Copilot 后端会动态上下架模型。`claude-cp-detect-models` 一键重测，结果写入 `~/.claude-copilot-models.json`，重启代理后生效。

**Q：和 cc-switch 啥关系？**
A：cc-switch 是 GUI 多 provider 切换工具，理论上也能切 Copilot。**但它的 Copilot 实现有全局污染 bug**，会让所有 Claude Code 窗口被劫持，见 [踩坑实录 #7](#-踩坑实录)。本仓库旁路了它，独立进程跑、日志透明。

**Q：为什么用 wrapper 脚本而不是 shell alias？**
A：alias 优先级高于 PATH 二进制，但 alias 内部的 `claude` 还是走 PATH 解析——容易抓到老版本。wrapper 主动扫所有可能的 claude 安装位置（nvm / Bun / Homebrew / 官方 installer），按版本号挑最新的用，完全无视 PATH 顺序。

**Q：会改我的 Anthropic 订阅吗？**
A：不会。`claude-cp` 通过 env 变量（`ANTHROPIC_BASE_URL`、`ANTHROPIC_API_KEY`）临时切到 localhost，订阅 OAuth token 在 Keychain 里完全没动。`claude` 命令行为如常。

**Q：能不能改默认端口？**
A：能。改 `proxy.mjs` 里的 `PORT` 常量（或 env `COPILOT_PROXY_PORT`），同步改 wrapper 的 `PROXY_URL`，重启代理。

---

## 🐛 踩坑实录

搭建过程踩过的所有真坑 —— 别人撞过的雷，你不必再撞。

<details>
<summary><b>#1 proxy 漏发 Copilot client header → Haiku 莫名 403</b></summary>

最早 proxy.mjs 转发到 Copilot 时只带 `Authorization` 和 `User-Agent`，没带
`Copilot-Integration-Id` / `Editor-Version` / `Editor-Plugin-Version`。
Copilot 后端把它识别成 `copilot-language-server` 通道（权限受限），所以 Haiku 4.5
等模型返回 `403 Access to this endpoint is forbidden`。

**修法**：显式声明 `Copilot-Integration-Id: vscode-chat` 整套 VSCode 插件标识。
Haiku 直接 200 通过。

</details>

<details>
<summary><b>#2 不同套餐能用的模型不同 → 写死 MODEL_MAP 必坑</b></summary>

早期 proxy.mjs 硬编码 `claude-opus-4-7 → claude-opus-4.6`，假定所有人都跟我一样卡在 4.6。
实际 Copilot 套餐有 Pro / Business / Enterprise / 教育版等，能用的模型清单完全不同，
并且 Copilot 后端会动态上下架。

**修法**：`detect-models.mjs` 装机时直接打 Copilot API 实测，写入
`~/.claude-copilot-models.json`，proxy 优先用实测映射。

</details>

<details>
<summary><b>#3 claude.ai 在国内被 GFW 屏蔽 → install.sh 静默失败</b></summary>

`curl https://claude.ai/install.sh | bash` 在国内返回 "App unavailable in region" 的 HTML 页，
bash 当 shell script 执行报 syntax error。

**修法**：install.sh 主动探测本地代理端口，检测到就生成带 `https_proxy=` 前缀的可粘贴 curl 命令。

</details>

<details>
<summary><b>#4 Clash Verge 默认端口 7897，不是 ClashX 的 7890</b></summary>

代理端口探测列表早期只有 ClashX 的 7890。Clash Verge / Verge Rev 默认 7897 被漏掉，
导致没写 HTTPS_PROXY 到 plist，Claude Code 启动 health check 直连 api.anthropic.com 被拦。

**修法**：探测列表扩到 `7890 / 7897 / 7891 / 7898 / 6152 / 8001 / 1087 / 10809`。

</details>

<details>
<summary><b>#5 v2.1.81 失败被误判为「不支持 BASE_URL」</b></summary>

第一次发现老版 Claude Code 跑 `claude-cp` 不去 localhost:18080，仍然连 api.anthropic.com，
误以为是版本太老不识别 `ANTHROPIC_BASE_URL`，把版本门一路保守上调到 2.1.130。

后来发现真因：**Claude Code 启动时的 region health check 不读 BASE_URL**，固定打
api.anthropic.com。国内没配 HTTPS_PROXY 时被 GFW 拦，跟版本无关。

**修法**：版本门降到 2.0.0 sanity check，关键是装机时同时写 HTTPS_PROXY 到 `~/.zshrc`
和 launchd plist（让两条路径都能走梯子）。

</details>

<details>
<summary><b>#6 zsh alias 优先级高于 PATH binary</b></summary>

早期用 alias 实现 `claude-cp`，alias 内部的 `claude` 走 PATH 解析就抓到了
`/usr/local/bin/claude` 老版本（v2.1.81）。版本升级了 PATH 上还残留老 claude 时，
alias 永远赢，wrapper 永远没机会跑。

**修法**：改用可执行 wrapper 脚本，脚本内主动扫所有可能的 claude 安装位置
（`.local/bin`、各 nvm 版本、Bun、Volta、Homebrew 等），按版本号挑最新的用。

</details>

<details>
<summary><b>#7 复用 cc-switch 的 Copilot profile 全局污染</b></summary>

最早想着「cc-switch 有 Copilot profile 的功能，直接用它就行」。结果 cc-switch 的
「启用本地路由」是**全局开关，profile 切换不清理状态**，打开后所有 Claude Code 窗口
都被劫持到 localhost，订阅会话全挂，关掉 Copilot profile 也没用，必须**手动关本地路由**
才能恢复——期间所有 Claude Code 上下文全部丢失。

**修法**：旁路 cc-switch，独立 Node + launchd 进程，日志透明、不污染全局配置。

</details>

<details>
<summary><b>#8 梯子直连规则不能放 anthropic.com 白名单</b></summary>

某些梯子的预设规则会把"AI/办公"类域名分流到直连，导致 Claude Code 自检请求
被 GFW 拦截，报 "App unavailable in region"。

**修法**：检查梯子的「直连规则 / Bypass List」，把 `*.anthropic.com` / `claude.ai` /
`*.claude.com` 全改成走代理。ClashX 的话打开配置文件搜 `anthropic` 或 `claude`。

</details>

---

## 🏛 架构

```
~/Library/LaunchAgents/com.jayson.claude-copilot-proxy.plist   ← 守护进程定义
            │ (RunAtLoad + KeepAlive，开机自启、崩溃自恢复)
            ▼
~/claude-code-copilot/scripts/proxy.mjs                        ← Node 代理本体
            │ 监听 localhost:18080
            ▼
~/.claude-copilot-auth.json    ← GitHub OAuth token (Device Flow 拿到)
~/.claude-copilot-models.json  ← 实测可用模型映射 (detect-models.mjs 写入)
~/.local/bin/claude-cp         ← 入口 wrapper (主动扫描 claude 二进制)
```

详见 [`docs/architecture.md`](docs/architecture.md)。

---

## 📊 vs 其它方案

| 方案 | 优点 | 缺点 |
|---|---|---|
| **本仓库** | 装机时实测套餐、不污染全局配置、launchd 守护、日志透明 | 你看到的就是全部 |
| [cc-switch](https://github.com/farion1231/cc-switch) | GUI 切多 provider | Copilot 实现有全局污染 bug，profile 切换不清理状态 |
| [copilot-api](https://github.com/ericc-ch/copilot-api) | 暴露 Copilot 成 OpenAI API，可配多 client | 不直接给 Anthropic 协议，要再套一层 |
| 原版 [claude-code-copilot](https://github.com/samarth777/claude-code-copilot) | 协议翻译实现完整 | 不发 VSCode client header，限制模型；MODEL_MAP 写死 |

---

## 🔄 升级 / 卸载

**升级到最新版本**：
```bash
# bootstrap 内置 'git pull --rebase'，重跑即升级
curl -fsSL https://raw.githubusercontent.com/jayson-jia-dev/claude-copilot-setup/main/bootstrap.sh | bash
```

**只想重测套餐模型**（不重装其它）：
```bash
claude-cp-detect-models
```

**重新走 GitHub OAuth**（token 失效 / 换账号）：
```bash
rm ~/.claude-copilot-auth.json
cd ~/claude-code-copilot && node scripts/auth.mjs
claude-cp-restart
```

**完全卸载**：
```bash
# 1. 停 launchd 服务
launchctl unload ~/Library/LaunchAgents/com.jayson.claude-copilot-proxy.plist
rm ~/Library/LaunchAgents/com.jayson.claude-copilot-proxy.plist

# 2. 删代理代码 + token + 实测映射
rm -rf ~/claude-code-copilot ~/claude-copilot-setup
rm ~/.claude-copilot-auth.json ~/.claude-copilot-models.json

# 3. 删 wrapper + 日志
rm ~/.local/bin/claude-cp
rm ~/Library/Logs/claude-copilot-proxy.{out,err}.log

# 4. 手动从 ~/.zshrc 删掉 claude-cp 相关 alias 和 PATH 那几行
#    （install.sh 加的注释 '# Claude Code × Copilot 辅助 alias' 那段）

# 5. （可选）按需保留 Anthropic 订阅路径用的 HTTPS_PROXY
#    那几行不是本项目专用，国内访问 claude.ai 还需要它
```

`claude` 命令本身不会被卸载（那是 Anthropic 官方装的），订阅状态完全不受影响。

---

## 🔒 安全 & 隐私

- **Token 全在本机**：GitHub OAuth token 存在 `~/.claude-copilot-auth.json`（权限 0600），不外发
- **代理日志只记元数据**：模型映射、HTTP 状态码、请求时间。**不记录** prompt 内容或响应正文
- **流量路径**：你的代码/对话 → 本机 18080 → Copilot 服务器。中间没有第三方
- **GitHub Copilot 隐私政策对内容的处理**：跟你日常用 VSCode Copilot 一致，请参考 [GitHub Copilot Privacy](https://docs.github.com/en/site-policy/privacy-policies/github-copilot-privacy-statement)
- **审计**：本仓库代码 ~500 行 Node，可读完。Token 处理逻辑集中在 `proxy.mjs` 顶部

---

## ⚠ 局限 & 注意

- **macOS only** —— 用 launchd 守护，Linux/Windows 没适配（但 `proxy.mjs` 跨平台，自己起进程即可）
- **依赖 Claude Code 客户端的实现细节** —— Anthropic 升级 Claude Code 改了请求格式时，可能需要更新协议翻译
- **依赖 Copilot 内部 token 端点** —— `api.github.com/copilot_internal/v2/token` 不是官方稳定 API，GitHub 改了会断
- **模型可用性 ≠ 配额无限** —— Copilot 每月 quota 上限按你套餐算，不是无限白嫖

---

## 🤝 贡献

欢迎 Issue 和 PR。在提 issue 前请先：
1. 跑 `claude-cp-status` 和 `claude-cp-log` 看是否能自助定位
2. 翻 [踩坑实录](#-踩坑实录)，可能你的问题已经记录过修法
3. 提 issue 时附上：`claude --version`、`node --version`、`cat ~/.claude-copilot-models.json`、相关日志片段

特别需要帮助的方向：
- Linux / Windows 适配（目前只测过 macOS）
- 个人 Pro 套餐的模型可用性数据点
- 国内其它代理工具的默认端口补充

---

## 🙏 致谢

- 代理实现 fork 自 [samarth777/claude-code-copilot](https://github.com/samarth777/claude-code-copilot)
- 借鉴了 [ericc-ch/copilot-api](https://github.com/ericc-ch/copilot-api) 的 OAuth 流程设计
- VSCode Copilot Chat 插件提供了 client header 范本（让 Copilot 把代理识别成合法 client）

---

## 📜 License

[MIT](LICENSE) © 2026 jayson-jia-dev
