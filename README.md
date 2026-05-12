# Claude Code × GitHub Copilot 复刻包

把这个文件夹拷到新 Mac 上，跑一条命令就能复刻同样的环境。

## 是什么

让 [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 通过公司发的 GitHub Copilot Business 订阅跑（无限额度），而不消耗 Anthropic 的付费订阅 quota。

- `claude` → 走 Anthropic 订阅，Opus 4.7
- `claude-cp` → 走 Copilot，Opus 4.6（实测可用的最高版本）

两条路并存、互不干扰。

## 一键复刻（新 Mac）

```bash
# 1. 复制文件夹到新机（U 盘、AirDrop、iCloud Drive 都行）
# 2. 进入文件夹
cd ~/Desktop/claude-copilot-setup

# 3. 跑安装脚本
bash scripts/install.sh

# 4. 重开终端，跑 claude-cp 测试
```

脚本会：
- 克隆 [samarth777/claude-code-copilot](https://github.com/samarth777/claude-code-copilot) 到 `~/claude-code-copilot`
- 用本包里改过的 `proxy.mjs` 覆盖原版（含 Opus 4.7→4.6 映射、Haiku→Sonnet 兜底）
- 触发 GitHub Device Flow 授权拿 OAuth token（旧机器的 token 不带过来，原因见安全说明）
- 生成 macOS launchd plist 路径自适应到新机的 node 安装位置
- 加载 launchd 服务（开机自启 + 崩溃自重启）
- 把 4 个 alias 写入 `~/.zshrc`
- 跑 curl 验证 Copilot 通路

## 前置依赖（新 Mac 上先装好）

| 依赖 | 装法 |
|---|---|
| Node.js 18+ | `brew install nvm` 然后 `nvm install node` |
| git | macOS 自带或 `brew install git` |
| Claude Code CLI | `npm i -g @anthropic-ai/claude-code` |
| GitHub Copilot 订阅 | 公司分配的 Business / Enterprise / 个人也行 |
| 网络代理（国内）| ClashX / Surge / Mihomo，确保 `api.githubcopilot.com` 能通 |

## 文件夹结构

```
claude-copilot-setup/
├── README.md                       ← 你正在看的
├── docs/
│   ├── architecture.md             ← 原理、协议转换、数据流
│   ├── troubleshooting.md          ← 故障排查手册
│   └── known-issues.md             ← 已知坑（cc-switch、模型可用性差异）
├── files/
│   ├── proxy.mjs                   ← 改过的代理代码（关键文件）
│   ├── com.jayson.claude-copilot-proxy.plist           ← 本机当前的 plist
│   ├── com.jayson.claude-copilot-proxy.plist.template  ← 路径占位符版（安装脚本用）
│   └── zshrc-aliases.sh            ← 4 个 alias
└── scripts/
    └── install.sh                  ← 一键安装
```

## 安全说明

**这个包不包含 GitHub OAuth token**。

- 原因：那是凭证，跟 SSH 私钥同级，不能跨机器明文复制
- 后果：新机器跑 install.sh 时会走一遍 Device Flow（浏览器扫码授权）
- 一次性的事，30 秒搞定

如果你**坚持**要把 token 也带过去（比如离线环境无法走 Device Flow），手动操作：

```bash
# 在源机器上
cat ~/.claude-copilot-auth.json
# 在新机器上把内容粘到同样路径
```

但记住：token 泄露 = 别人能白嫖你的 Copilot quota，所以 U 盘也好、文件传输也好，传完赶紧删中转副本。

## 日常运维

| 命令 | 作用 |
|---|---|
| `claude-cp` | 启动 Claude Code 走 Copilot |
| `claude-cp-status` | 看代理服务状态（PID + 端口） |
| `claude-cp-restart` | 改了 proxy.mjs 后重启代理服务 |
| `claude-cp-log` | 实时跟踪代理日志 |

代理监听 `http://localhost:18080`，日志写到 `~/Library/Logs/claude-copilot-proxy.{out,err}.log`。

## 不要做的事

- ❌ **不要用 cc-switch 的 Copilot profile**（已知 bug，看 `docs/known-issues.md`）
- ❌ **不要打开 cc-switch 的「启用本地路由」全局开关**（会污染所有 Claude Code 窗口）
- ❌ **不要把 token 文件提交到 git**

## 参考

- 上游代理仓库：https://github.com/samarth777/claude-code-copilot
- 本配置初次搭建日期：2026-05-12
- 配置作者：Jayson @ Reolink
