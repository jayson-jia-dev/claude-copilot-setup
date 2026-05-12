#!/bin/bash
#
# Claude Code × GitHub Copilot 一键安装脚本
# 在新 Mac 上把这个文件夹拷过去后跑：bash scripts/install.sh
#
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_DIR="$(dirname "$SCRIPT_DIR")"

echo "════════════════════════════════════════════════════════════"
echo "  Claude Code × GitHub Copilot 安装器"
echo "════════════════════════════════════════════════════════════"
echo ""

# ─── 检查依赖 ──────────────────────────────────────────────────
echo "[1/7] 检查依赖..."
command -v node >/dev/null 2>&1 || { echo "❌ 未装 node。先装 nvm + Node 18+ 后再来。"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "❌ 未装 git"; exit 1; }
command -v claude >/dev/null 2>&1 || { echo "⚠ 未装 claude code（npm i -g @anthropic-ai/claude-code），后面手动装也行。"; }

NODE_BIN="$(which node)"
NODE_DIR="$(dirname "$NODE_BIN")"
NODE_VER="$(node --version)"
echo "  ✓ node: $NODE_VER ($NODE_BIN)"

# ─── 克隆原仓库 + 应用本地修改 ────────────────────────────────
TARGET_DIR="$HOME/claude-code-copilot"
echo ""
echo "[2/7] 部署代理代码到 $TARGET_DIR..."
if [ -d "$TARGET_DIR" ]; then
    echo "  ⚠ 目录已存在，跳过 clone"
else
    git clone --depth 1 https://github.com/samarth777/claude-code-copilot.git "$TARGET_DIR"
fi

echo "  → 应用本地修改过的 proxy.mjs（4.7→4.6 映射、haiku→sonnet 兜底）"
cp "$PKG_DIR/files/proxy.mjs" "$TARGET_DIR/scripts/proxy.mjs"

# ─── GitHub Copilot OAuth ─────────────────────────────────────
echo ""
echo "[3/7] GitHub Copilot 认证..."
AUTH_FILE="$HOME/.claude-copilot-auth.json"
if [ -f "$AUTH_FILE" ]; then
    echo "  ✓ token 已存在 ($AUTH_FILE)"
else
    echo "  → 启动 GitHub Device Flow（浏览器会自动打开）"
    cd "$TARGET_DIR"
    node scripts/auth.mjs
    cd - > /dev/null
fi

# ─── 生成 launchd plist ───────────────────────────────────────
echo ""
echo "[4/7] 生成 launchd plist..."
PLIST_DST="$HOME/Library/LaunchAgents/com.jayson.claude-copilot-proxy.plist"
sed -e "s|__NODE_BIN__|$NODE_BIN|g" \
    -e "s|__NODE_DIR__|$NODE_DIR|g" \
    -e "s|__HOME__|$HOME|g" \
    "$PKG_DIR/files/com.jayson.claude-copilot-proxy.plist.template" > "$PLIST_DST"
echo "  ✓ 写入 $PLIST_DST"

# ─── 启动 launchd 服务 ────────────────────────────────────────
echo ""
echo "[5/7] 启动 launchd 服务..."
launchctl unload "$PLIST_DST" 2>/dev/null || true
launchctl load "$PLIST_DST"
sleep 2
if launchctl list | grep -q claude-copilot-proxy; then
    echo "  ✓ 服务已启动"
else
    echo "  ❌ 服务启动失败，看日志: ~/Library/Logs/claude-copilot-proxy.err.log"
    exit 1
fi

# ─── 写入 zsh alias ──────────────────────────────────────────
echo ""
echo "[6/7] 写入 zsh alias..."
ZSHRC="$HOME/.zshrc"
if grep -q "claude-cp" "$ZSHRC" 2>/dev/null; then
    echo "  ⚠ alias 已存在，跳过"
else
    {
        echo ""
        cat "$PKG_DIR/files/zshrc-aliases.sh"
    } >> "$ZSHRC"
    echo "  ✓ 4 个 alias 已追加到 $ZSHRC"
fi

# ─── 验证 ──────────────────────────────────────────────────────
echo ""
echo "[7/7] 验证代理可用性..."
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
echo "  1. 开个新终端（让 zshrc 重新加载）"
echo "  2. 跑: claude-cp"
echo "  3. 进 Claude Code 后随便发一句话测试"
echo ""
echo "日常用法："
echo "  claude          # 走订阅"
echo "  claude-cp       # 走 Copilot"
echo "  claude-cp-status  / -restart / -log"
echo ""
