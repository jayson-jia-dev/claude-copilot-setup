#!/usr/bin/env bash
#
# Claude Code × GitHub Copilot 一键安装脚本
# 新 Mac 上把这个文件夹拷过去后：bash scripts/install.sh
#
# 不假设任何用户特定路径。所有依赖都从环境检测。
#
set -e

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
for c in \
    "$HOME/.local/bin/claude" \
    $(ls -d "$HOME"/.nvm/versions/node/*/bin/claude 2>/dev/null | sort -rV) \
    "/opt/homebrew/bin/claude" \
    "$(command -v claude 2>/dev/null)" \
    "/usr/local/bin/claude"
do
    [ -z "$c" ] && continue
    [ -x "$c" ] || continue
    ver=$("$c" --version 2>/dev/null | awk '{print $1}')
    [ -z "$ver" ] && continue
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
    echo "  ⚠ 未找到 Claude Code >= $MIN_CLAUDE。装一个："
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
    echo "    或者通过 npm（如果 npm registry 可达）："
    echo "      npm i -g @anthropic-ai/claude-code"
    echo ""
    echo "    装完重开终端再跑这个安装器。"
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
echo "命令一览："
echo "  claude               # 走订阅 / 默认配置"
echo "  claude-cp            # 走 Copilot 代理"
echo "  claude-cp-status     # 看代理状态"
echo "  claude-cp-restart    # 重启代理"
echo "  claude-cp-log        # 看代理日志"
echo ""
