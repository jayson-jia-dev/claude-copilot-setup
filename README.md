# Claude Code × GitHub Copilot

在本机跑一个伪装成 VSCode Copilot 插件的 Node 代理（监听 `localhost:18080`），把 [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 发出的 Anthropic 协议请求翻译成 OpenAI 协议、换上你的 Copilot OAuth token，再转发到 `api.githubcopilot.com` — 等于让 Claude Code 借你的 Copilot 订阅跑。

- `claude` → Anthropic 订阅
- `claude-cp` → 本地代理 → Copilot

## 一行命令搞定

**国外网络 / 已配好梯子**：
```bash
curl -fsSL https://raw.githubusercontent.com/jayson-jia-dev/claude-copilot-setup/main/bootstrap.sh | bash
```

**国内没配 git 代理**（端口按你梯子改）：
```bash
HTTPS_PROXY=http://127.0.0.1:7890 bash -c "$(curl -fsSL https://raw.githubusercontent.com/jayson-jia-dev/claude-copilot-setup/main/bootstrap.sh)"
```

跑完跟着提示走完 GitHub 扫码授权（30 秒），**重开终端** → `claude-cp` 即可。

> 前置依赖：Node 18+、git、Claude Code (>= 2.1.130)、GitHub Copilot 订阅。
> Claude Code 装法见下方「装 Claude Code」一节。

## ⚠ 关于模型版本：界面显示 vs 实际使用

Claude Code 顶部 banner 会显示 `Opus 4.7 (1M context) · API Usage Billing`，
**但这只是客户端自己的标签，是个假象**。

实际发到 Copilot 的请求被本地代理改写成 `claude-opus-4.6`：
- Copilot Business 套餐里 4.7 返回 `model_not_supported`（API 列表说有但实际禁用）
- 4.6 反而能用（虽然 API 列表里没列），是当前可用的最高版本

想看实际用的哪个模型，跑 `claude-cp-log`，看 `→` 右边那个名字：
```
→ claude-opus-4-7 → claude-opus-4.6 | stream ...
                    ↑ 实际跑的是这个
```

如果对模型有要求（重推理任务必须用 4.7），就跑 `claude` 走订阅而非 `claude-cp`。

---

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
| 跨机器适应性 | 看 PATH 命运 | **完全无视 PATH**，稳 |

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
- 每台机器装的时候各自走 GitHub 账号授权，互不干扰

## 日常运维

| 命令 | 作用 |
|---|---|
| `claude-cp` | 启动 Claude Code 走 Copilot |
| `claude-cp-status` | 看代理服务状态（PID + 端口） |
| `claude-cp-restart` | 改了 proxy.mjs 后重启代理服务 |
| `claude-cp-log` | 实时跟踪代理日志 |

代理监听 `http://localhost:18080`，日志写到 `~/Library/Logs/claude-copilot-proxy.{out,err}.log`。

## 实测踩坑记录

搭建过程中真实踩到的问题，每条都对应一次失败 + 一次修正。

### 1. proxy 漏发 Copilot client header → Haiku 莫名 403

最早 proxy.mjs 转发到 Copilot 时只带了 `Authorization` 和 `User-Agent`，没带
`Copilot-Integration-Id` / `Editor-Version` / `Editor-Plugin-Version`。
Copilot 后端把它识别成 `copilot-language-server` 通道（权限受限），
所以 Haiku 4.5 等模型返回 `403 Access to this endpoint is forbidden`。

**修法**：proxy.mjs 显式声明 `Copilot-Integration-Id: vscode-chat` 整套 VSCode
插件标识。补上之后 Haiku 直接 200 通过。

### 2. 不同套餐能用的模型不同 → 写死 MODEL_MAP 必坑

最早 proxy.mjs 硬编码 `claude-opus-4-7 → claude-opus-4.6`，假定所有人都跟我一样
卡在 4.6。但 Copilot 套餐有 Pro / Business / Enterprise / 教育版等，
能用的模型清单完全不同，并且 Copilot 后端会动态上下架。

**修法**：装机时跑 `detect-models.mjs` 直接打 Copilot API 实测 opus / sonnet /
haiku 各家最高可用版本，写入 `~/.claude-copilot-models.json`，proxy 优先用
这份实测映射。每家 Mac 自适应自己的套餐。重测命令 `claude-cp-detect-models`。

### 3. Claude.ai 国内被 GFW 屏蔽 → install.sh 静默失败

`curl https://claude.ai/install.sh | bash` 在国内会返回 "App unavailable in
region" 的 HTML 页，bash 当 shell script 执行报 syntax error。

**修法**：install.sh 主动探测本地代理端口（7890 / 7897 / 6152 / 8001 …），
检测到就在错误提示里**带前缀生成可粘贴的 curl 命令**。

### 4. Clash Verge 默认端口 7897，不是 ClashX 的 7890

代理端口探测列表早期只有 ClashX 的 7890。Clash Verge / Verge Rev 默认 7897，
被漏掉，导致没写 HTTPS_PROXY 到 plist，Claude Code 启动 health check
直连 api.anthropic.com 被拦。

**修法**：探测列表扩到 7890 / 7897 / 7891 / 7898 / 6152 / 8001 / 1087 / 10809。

### 5. v2.1.81 失败被误判为「不支持 BASE_URL」

第一次发现老版 Claude Code 跑 `claude-cp` 时不去 localhost:18080，仍然连
api.anthropic.com，以为是版本太老不识别 `ANTHROPIC_BASE_URL`，于是把版本门
设到 2.1.130 一路保守上调。后来发现真正原因是：**Claude Code 启动时的 region
health check 不读 BASE_URL**，固定打 api.anthropic.com。国内没配 HTTPS_PROXY
时被 GFW 拦掉，跟版本无关。

**修法**：版本门降到 2.0.0 sanity check，关键是装机时同时写 HTTPS_PROXY 到
`~/.zshrc`（让订阅路径也能走梯子）和 plist（让 proxy 进程拉 Copilot token
时也能走梯子）。

### 6. zsh alias 优先级高于 PATH binary

早期方案用 alias 实现 `claude-cp`，结果 alias 直接拼成 `... claude` 命令，
`claude` 走 PATH 解析就抓到了 `/usr/local/bin/claude` 那个老版本（v2.1.81）。
版本升级了 PATH 上还残留老 claude 时，alias 永远赢，wrapper 永远没机会跑。

**修法**：改用可执行 wrapper 脚本（`~/.local/bin/claude-cp`），脚本内主动扫
所有可能的 claude 安装位置（`.local/bin`、各 nvm 版本、Bun、Volta、Homebrew
等），按版本号挑最新的用。完全无视 PATH 顺序。

### 7. 复用 cc-switch 的 Copilot profile 灾难现场

最早想着「cc-switch 有 Copilot profile 的功能，直接用它就行」。结果
cc-switch 的「启用本地路由」是**全局开关，profile 切换不清理状态**，
打开后所有 Claude Code 窗口都被劫持到 localhost，订阅会话全挂，
关掉 Copilot profile 也没用，必须**手动关本地路由**才能恢复——
期间所有 Claude Code 上下文全部丢失。

**修法**：旁路 cc-switch，自己用 Node + launchd 起独立代理，
日志透明、不污染全局配置。

### 8. Claude.ai 必须**完整**走代理（直连规则不能放白名单）

`claude-cp` 走 localhost 代理 → Copilot，**不依赖**外网到 Anthropic。
但 `claude` 走订阅时直连 `api.anthropic.com`，必须走梯子。

install.sh 探测到本地代理时会**自动**往 `~/.zshrc` 写：

```bash
export HTTPS_PROXY="http://127.0.0.1:7890"   # 端口按实测改
export HTTP_PROXY="http://127.0.0.1:7890"
export NO_PROXY="localhost,127.0.0.1,*.local"
```

**⚠ 关键警告**：检查梯子的「直连规则 / Bypass List / 绕过域名」，
**严禁**把以下域名加到绕过列表：

- `*.anthropic.com`
- `api.anthropic.com`
- `claude.ai`
- `*.claude.com`

某些梯子预设规则会把"AI/办公"类域名分流到直连，导致 Claude Code
自检请求被 GFW 拦截。ClashX 的话打开配置文件搜 `anthropic` 或
`claude`，有任何 `DIRECT` 规则全改成走代理。

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
