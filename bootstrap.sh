#!/usr/bin/env bash
#
# Claude Code × GitHub Copilot bootstrap
# 用法：
#   curl -fsSL https://raw.githubusercontent.com/jayson-jia-dev/claude-copilot-setup/main/bootstrap.sh | bash
#
# 国内（端口按你梯子改）：
#   HTTPS_PROXY=http://127.0.0.1:7890 bash -c "$(curl -fsSL https://raw.githubusercontent.com/jayson-jia-dev/claude-copilot-setup/main/bootstrap.sh)"
#
set -e

REPO_URL="https://github.com/jayson-jia-dev/claude-copilot-setup.git"
REPO_DIR="$HOME/claude-copilot-setup"

echo "════════════════════════════════════════════════════════════"
echo "  Claude Code × GitHub Copilot bootstrap"
echo "════════════════════════════════════════════════════════════"

if [ -d "$REPO_DIR/.git" ]; then
    echo "→ 已有 $REPO_DIR，拉取最新..."
    git -C "$REPO_DIR" pull --rebase --autostash 2>&1 | tail -3
else
    echo "→ 克隆到 $REPO_DIR"
    git clone --depth 1 "$REPO_URL" "$REPO_DIR"
fi

echo ""
echo "→ 跑安装器..."
echo ""
bash "$REPO_DIR/scripts/install.sh"
