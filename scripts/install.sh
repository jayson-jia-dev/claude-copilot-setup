#!/usr/bin/env bash
#
# Claude Code × GitHub Copilot 一键安装脚本
# 新 Mac 上把这个文件夹拷过去后：bash scripts/install.sh
#
# 不假设任何用户特定路径。所有依赖都从环境检测。
#
set -e
# 强制 UTF-8，避免 curl|bash 时某些 shell 的 LANG=C 把中文显示成乱码
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_DIR="$(dirname "$SCRIPT_DIR")"

echo "════════════════════════════════════════════════════════════"
echo "  Claude Code × GitHub Copilot 安装器"
echo "════════════════════════════════════════════════════════════"
echo ""

# ─── [1/8] 检查依赖 ────────────────────────────────────────────
echo "[1/8] 检查依赖..."
command -v node >/dev/null 2>&1 || { echo "❌ 未装 node。先装 nvm + Node 18+ 后再来。"; exit 1; }
command -v git  >/dev/null 2>&1 || { echo "❌ 未装 git"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "❌ 未装 curl"; exit 1; }

NODE_BIN="$(which node)"
NODE_DIR="$(dirname "$NODE_BIN")"
NODE_VER="$(node --version)"
echo "  ✓ node: $NODE_VER ($NODE_BIN)"

# 自动找一个 ≥ 2.1.130 的 claude，没有就提示用户装
MIN_CLAUDE="2.1.130"
CLAUDE_FOUND=""
CLAUDE_SCANNED=""  # 调试用：记录扫过哪些版本，失败时打印出来给同事看

# 候选路径合集（从最权威到最兜底）
CANDIDATES=(
    "$HOME/.local/bin/claude"                    # Anthropic 官方安装器
    "$HOME/.bun/bin/claude"                      # Bun 全局
    "/opt/homebrew/bin/claude"                   # Apple Silicon Homebrew / npm
    "/usr/local/bin/claude"                      # Intel Homebrew / 老 npm
    "$HOME/.volta/bin/claude"                    # Volta
    "$HOME/.config/yarn/global/node_modules/.bin/claude"  # Yarn 全局
    "$(command -v claude 2>/dev/null)"           # PATH 兜底
)
# nvm 各版本（多个 node 版本可能各自装了一份）
if [ -d "$HOME/.nvm/versions/node" ]; then
    while IFS= read -r p; do
        CANDIDATES+=("$p")
    done < <(ls -d "$HOME"/.nvm/versions/node/*/bin/claude 2>/dev/null | sort -rV)
fi
# fnm / n 等其它 node 管理器
for p in "$HOME"/.fnm/node-versions/*/installation/bin/claude \
         "$HOME"/.n/bin/claude \
         "$HOME"/.asdf/installs/nodejs/*/.npm/bin/claude; do
    [ -x "$p" ] && CANDIDATES+=("$p")
done

seen=""
for c in "${CANDIDATES[@]}"; do
    [ -z "$c" ] && continue
    [ -x "$c" ] || continue
    case ":$seen:" in *":$c:"*) continue ;; esac  # 去重
    seen="$seen:$c"

    ver=$("$c" --version 2>/dev/null | awk '{print $1}')
    [ -z "$ver" ] && continue
    CLAUDE_SCANNED="${CLAUDE_SCANNED}    $c → $ver"$'\n'

    if printf '%s\n%s\n' "$MIN_CLAUDE" "$ver" | sort -V -C 2>/dev/null; then
        echo "  ✓ claude: $ver ($c)"
        CLAUDE_FOUND="$c"
        break
    fi
done
if [ -z "$CLAUDE_FOUND" ]; then
    # 国内访问 claude.ai 会被地区屏蔽（返回 HTML 错误页），
    # 探测下用户是否有可用代理，给出能直接复制粘贴的命令
    PROXY_HINT=""
    for port in 7890 7891 6152 8001 1087; do
        if nc -z 127.0.0.1 "$port" 2>/dev/null; then
            PROXY_HINT="https_proxy=http://127.0.0.1:$port "
            break
        fi
    done

    # 区分两种场景：装过但太老（升级）vs 完全没装（首次安装）
    if [ -n "$CLAUDE_SCANNED" ]; then
        echo "  ⚠ 你装的 Claude Code 版本太老，需要升级到 >= ${MIN_CLAUDE}"
        echo ""
        echo "  当前扫到的版本："
        printf '%s' "$CLAUDE_SCANNED"
        echo ""
        echo "  升级方法（按你当前的安装方式选）："
        echo ""
        echo "  ▸ 如果当前 claude 在 /opt/homebrew/bin 或 /usr/local/bin（Homebrew 装的）："
        echo "      brew update && brew upgrade claude-code"
        echo ""
        echo "  ▸ 如果是 npm 装的（任何 node 包管理器）："
        echo "      npm i -g @anthropic-ai/claude-code@latest --registry=https://registry.npmjs.org/"
        echo ""
        echo "  ▸ 不确定？直接用官方 installer 覆盖装最新版（推荐，最稳）："
        echo "      curl -fsSL https://claude.ai/install.sh | bash"
        if [ -n "$PROXY_HINT" ]; then
            echo "      # 国内（已探测到本地代理 ${PROXY_HINT%% *}）："
            echo "      ${PROXY_HINT}curl -fsSL https://claude.ai/install.sh | bash"
        fi
        echo ""
        echo "  升级完后**重开终端**，再跑刚才那条 bootstrap 命令。"
    else
        echo "  ⚠ 系统里没装 Claude Code，先装一个："
        echo ""
        echo "    国外网络："
        echo "      curl -fsSL https://claude.ai/install.sh | bash"
        echo ""
        if [ -n "$PROXY_HINT" ]; then
            echo "    国内（已探测到本地代理 ${PROXY_HINT%% *}）："
            echo "      ${PROXY_HINT}curl -fsSL https://claude.ai/install.sh | bash"
        else
            echo "    国内（需要代理，自行替换端口）："
            echo "      https_proxy=http://127.0.0.1:7890 curl -fsSL https://claude.ai/install.sh | bash"
        fi
        echo ""
        echo "    或者通过 npm："
        echo "      npm i -g @anthropic-ai/claude-code@latest --registry=https://registry.npmjs.org/"
        echo ""
        echo "    装完**重开终端**，再跑刚才那条 bootstrap 命令。"
    fi
    exit 1
fi

# ─── [2/8] 部署代理代码 ────────────────────────────────────────
TARGET_DIR="$HOME/claude-code-copilot"
echo ""
echo "[2/8] 部署代理代码到 $TARGET_DIR..."
if [ -d "$TARGET_DIR/.git" ]; then
    echo "  ⚠ 目录已存在，跳过 clone"
else
    git clone --depth 1 https://github.com/samarth777/claude-code-copilot.git "$TARGET_DIR"
fi

echo "  → 覆盖 proxy.mjs（含 Opus 4.7→4.6 映射、Haiku→Sonnet 兜底）"
cp "$PKG_DIR/files/proxy.mjs" "$TARGET_DIR/scripts/proxy.mjs"

# ─── [3/8] GitHub Copilot OAuth ───────────────────────────────
echo ""
echo "[3/8] GitHub Copilot 认证..."
AUTH_FILE="$HOME/.claude-copilot-auth.json"
if [ -f "$AUTH_FILE" ]; then
    echo "  ✓ token 已存在 ($AUTH_FILE)"
else
    echo "  → 启动 GitHub Device Flow（浏览器会自动打开）"
    cd "$TARGET_DIR"
    node scripts/auth.mjs
    cd - > /dev/null
fi

# ─── [4/8] 探测网络代理 ──────────────────────────────────────
echo ""
echo "[4/8] 探测系统 HTTP 代理..."
UPSTREAM_PROXY=""
# 优先用当前 shell 已经 export 的
if [ -n "$HTTPS_PROXY" ]; then
    UPSTREAM_PROXY="$HTTPS_PROXY"
elif [ -n "$https_proxy" ]; then
    UPSTREAM_PROXY="$https_proxy"
fi
# 没设的话，探测常见本地端口（ClashX/Mihomo 7890、Surge 6152、V2RayX 8001）
if [ -z "$UPSTREAM_PROXY" ]; then
    for port in 7890 7891 6152 8001 1087; do
        if nc -z 127.0.0.1 "$port" 2>/dev/null; then
            UPSTREAM_PROXY="http://127.0.0.1:$port"
            echo "  → 自动探测到本地代理: $UPSTREAM_PROXY"
            break
        fi
    done
fi
if [ -n "$UPSTREAM_PROXY" ]; then
    echo "  ✓ 代理: $UPSTREAM_PROXY"
else
    echo "  ⚠ 未探测到代理。如果在国内/api.githubcopilot.com 不通，请手动编辑 plist 加 HTTPS_PROXY。"
fi

# ─── [5/8] 生成 launchd plist ─────────────────────────────────
echo ""
echo "[5/8] 生成 launchd plist..."
PLIST_LABEL="com.jayson.claude-copilot-proxy"
PLIST_DST="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

# 直接生成 plist（不用模板，更可控）
if [ -n "$UPSTREAM_PROXY" ]; then
    PROXY_BLOCK="
        <key>HTTPS_PROXY</key>
        <string>${UPSTREAM_PROXY}</string>
        <key>HTTP_PROXY</key>
        <string>${UPSTREAM_PROXY}</string>
        <key>NO_PROXY</key>
        <string>localhost,127.0.0.1</string>"
else
    PROXY_BLOCK=""
fi

cat > "$PLIST_DST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${NODE_BIN}</string>
        <string>${TARGET_DIR}/scripts/proxy.mjs</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${TARGET_DIR}</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>${NODE_DIR}:/usr/local/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>${HOME}</string>${PROXY_BLOCK}
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${HOME}/Library/Logs/claude-copilot-proxy.out.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/Library/Logs/claude-copilot-proxy.err.log</string>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
EOF
echo "  ✓ 写入 $PLIST_DST"

# ─── [6/8] 启动 launchd 服务 ──────────────────────────────────
echo ""
echo "[6/8] 启动 launchd 服务..."
launchctl unload "$PLIST_DST" 2>/dev/null || true
launchctl load "$PLIST_DST"
sleep 2
if launchctl list | grep -q "${PLIST_LABEL}"; then
    echo "  ✓ 服务已启动"
else
    echo "  ❌ 启动失败，看日志: tail ~/Library/Logs/claude-copilot-proxy.err.log"
    exit 1
fi

# ─── [7/8] 安装 wrapper 脚本 + alias ─────────────────────────
echo ""
echo "[7/8] 安装 claude-cp wrapper 和辅助 alias..."
mkdir -p "$HOME/.local/bin"
cp "$PKG_DIR/files/claude-cp" "$HOME/.local/bin/claude-cp"
chmod 755 "$HOME/.local/bin/claude-cp"  # 显式 rwxr-xr-x，避免 umask 留坑
echo "  ✓ wrapper: ~/.local/bin/claude-cp"

# 清理早期版本可能留下的老 alias（zsh alias 优先级高于 PATH 二进制，
# 不清理会让 wrapper 失效）
if grep -q "^alias claude-cp='ANTHROPIC_BASE_URL" "$HOME/.zshrc" 2>/dev/null; then
    sed -i.bak "/^alias claude-cp='ANTHROPIC_BASE_URL/d" "$HOME/.zshrc"
    echo "  ✓ 检测到旧版 claude-cp alias，已清理（备份在 ~/.zshrc.bak）"
fi

# 确保 ~/.local/bin 在 PATH 中
if ! grep -q '\.local/bin' "$HOME/.zshrc" 2>/dev/null; then
    echo '' >> "$HOME/.zshrc"
    echo '# claude-cp 安装器追加' >> "$HOME/.zshrc"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
    echo "  ✓ 已追加 PATH 导出到 ~/.zshrc"
elif ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    echo "  ⚠ ~/.zshrc 里已有 .local/bin 字样但当前 shell PATH 未生效"
    echo "    重开终端或 'source ~/.zshrc' 一下"
fi

# 写辅助 alias（status/restart/log）
if grep -q "claude-cp-status" "$HOME/.zshrc" 2>/dev/null; then
    echo "  ⚠ 辅助 alias 已存在，跳过"
else
    {
        echo ''
        echo '# Claude Code × Copilot 辅助 alias'
        cat "$PKG_DIR/files/zshrc-aliases.sh" | grep '^alias'
    } >> "$HOME/.zshrc"
    echo "  ✓ 辅助 alias 已追加"
fi

# 让 `claude`（订阅路径）也能走代理 — 否则国内用户 claude 直接报地区屏蔽
# claude-cp 不依赖这个（走 localhost），但 claude 直连 api.anthropic.com 必须有
if [ -n "$UPSTREAM_PROXY" ]; then
    if grep -qE "^export[[:space:]]+HTTPS_PROXY=" "$HOME/.zshrc" 2>/dev/null; then
        echo "  ⚠ ~/.zshrc 里已有 HTTPS_PROXY 配置，跳过（不覆盖用户设置）"
    else
        {
            echo ''
            echo '# Claude Code 订阅路径（claude 命令）走系统代理'
            echo "# 由 claude-copilot-setup 安装器探测后追加 (端口: ${UPSTREAM_PROXY##*:})"
            echo "export HTTPS_PROXY=\"${UPSTREAM_PROXY}\""
            echo "export HTTP_PROXY=\"${UPSTREAM_PROXY}\""
            echo 'export NO_PROXY="localhost,127.0.0.1,*.local"'
        } >> "$HOME/.zshrc"
        echo "  ✓ HTTPS_PROXY 已追加（让 \`claude\` 命令能直连 Anthropic）"
        echo ""
        echo "  ⚠ 重要：检查你梯子的「直连/绕过规则」"
        echo "    严禁把 *.anthropic.com / claude.ai / api.claude.com 加到绕过列表"
        echo "    Claude Code 必须**完整**走代理，否则一样会被地区屏蔽"
    fi
fi

# ─── [8/8] 验证 ────────────────────────────────────────────────
echo ""
echo "[8/8] 验证代理可用性..."
sleep 1
RESPONSE=$(curl -s -X POST http://localhost:18080/v1/messages \
    -H "Content-Type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -H "x-api-key: copilot-proxy" \
    -d '{"model":"claude-sonnet-4-5","max_tokens":15,"messages":[{"role":"user","content":"reply: ok"}]}' \
    --max-time 30)

if echo "$RESPONSE" | grep -q '"text":"ok"'; then
    echo "  ✓ 代理正常工作，Copilot 返回了 'ok'"
else
    echo "  ⚠ 验证未通过。响应:"
    echo "  $RESPONSE" | head -3
    echo "  排查: cat ~/Library/Logs/claude-copilot-proxy.err.log"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  ✅ 安装完成"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "下一步："
echo "  1. 开个新终端（让 PATH 和 alias 重新加载）"
echo "  2. 跑: claude-cp"
echo ""
echo "首次启动 claude-cp 会问你三个对话框："
echo ""
echo "  ① Detected a custom API key in your environment"
echo "     ANTHROPIC_API_KEY: sk-ant-...copilot-proxy"
echo "     Do you want to use this API key?"
echo "     ┌────────────────────────────────────────────────┐"
echo "     │ → 选 1. Yes                                    │"
echo "     │   （我们就是故意用这个 key 走代理的，必须 Yes）│"
echo "     │   注意：默认选项是 No (recommended)，要手动改 │"
echo "     └────────────────────────────────────────────────┘"
echo ""
echo "  ② Accessing workspace: /Users/<你>"
echo "     Quick safety check: Is this a project you trust?"
echo "     ┌────────────────────────────────────────────────┐"
echo "     │ → 选 1. Yes, I trust this folder              │"
echo "     │   你在自己电脑自己 home 目录下，安全           │"
echo "     │   选 No 会直接退出 Claude Code                 │"
echo "     └────────────────────────────────────────────────┘"
echo ""
echo "  ③ Use Claude Code's terminal setup?"
echo "     (Option+Enter for newlines and visual bell)"
echo "     ┌────────────────────────────────────────────────┐"
echo "     │ → 任选都行                                     │"
echo "     │   选 Yes：开启 Option+Enter 输入换行（推荐）  │"
echo "     │   选 No：保持默认，以后随时 /terminal-setup    │"
echo "     │   跟 Copilot 功能无关，只是 Claude 自身偏好    │"
echo "     └────────────────────────────────────────────────┘"
echo ""
echo "⚠ 重要提示："
echo "  界面顶部显示 'Opus 4.7 (1M context) · API Usage Billing'"
echo "  ← 这只是 Claude Code 客户端自己的标签，是假象。"
echo ""
echo "  实际发到 Copilot 的请求被代理改写成 claude-opus-4.6"
echo "  （Business 套餐里 4.7 不可用，4.6 是实测能用的最高版本）。"
echo ""
echo "  想看实际用了哪个模型：claude-cp-log，看 '→' 右边那个名字。"
echo ""
