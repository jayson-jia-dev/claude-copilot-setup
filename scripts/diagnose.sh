#!/usr/bin/env bash
# 诊断 token 为什么调 Copilot 失败
# 用法: curl -fsSL https://raw.githubusercontent.com/jayson-jia-dev/claude-copilot-setup/main/scripts/diagnose.sh | bash

set -e

AUTH_FILE="$HOME/.claude-copilot-auth.json"

echo "════════════════════════════════════════════════════════"
echo "  Claude × Copilot Token 诊断"
echo "════════════════════════════════════════════════════════"
echo ""

# ─── Step 1: token 基本信息 ──────────────────────────────────
echo "[1] Token 基本信息"
if [ ! -f "$AUTH_FILE" ]; then
    echo "  ❌ 不存在 $AUTH_FILE，先跑 install.sh"
    exit 1
fi

TOKEN=$(python3 -c "import json; print(json.load(open('$AUTH_FILE'))['access_token'])")
echo "  prefix: ${TOKEN:0:8}..."
echo "  长度  : ${#TOKEN}"

# ─── Step 2: 验证 token 是谁 ──────────────────────────────────
echo ""
echo "[2] Token 对应的 GitHub 账号"
USER_INFO=$(curl -s -H "Authorization: token $TOKEN" https://api.github.com/user)
echo "  login : $(echo "$USER_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('login','??'))")"
echo "  id    : $(echo "$USER_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id','??'))")"

# ─── Step 3: OAuth Scope 与 Client ───────────────────────────
echo ""
echo "[3] Token OAuth scope 和 client id（决定 Copilot 权限的关键）"
HEADERS=$(curl -sI -H "Authorization: token $TOKEN" https://api.github.com/user)
echo "$HEADERS" | grep -i '^x-oauth-scopes:' | sed 's/^/  /'
echo "$HEADERS" | grep -i '^x-oauth-client-id:' | sed 's/^/  /'
echo "$HEADERS" | grep -i '^x-accepted-oauth-scopes:' | sed 's/^/  /'

# ─── Step 4: 直接调 Copilot Chat 试试 ────────────────────────
echo ""
echo "[4] 直调 Copilot /chat/completions (走 HTTPS_PROXY=${HTTPS_PROXY:-<无>})"
RESP=$(curl -s -o /tmp/copilot-diag-body.json -w "%{http_code}" \
    -X POST https://api.githubcopilot.com/chat/completions \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "Copilot-Integration-Id: vscode-chat" \
    -H "Editor-Version: vscode/1.110.1" \
    -H "Editor-Plugin-Version: copilot-chat/0.38.2" \
    -H "x-github-api-version: 2025-10-01" \
    -H "User-Agent: GitHubCopilotChat/0.38.2" \
    -H "x-initiator: user" \
    -d '{"model":"claude-sonnet-4.5","max_tokens":5,"messages":[{"role":"user","content":"hi"}]}' \
    --max-time 15 2>&1)
echo "  HTTP $RESP"
echo "  body: $(head -c 300 /tmp/copilot-diag-body.json)"
echo ""
rm -f /tmp/copilot-diag-body.json

# ─── Step 5: 内部 token 换发端点是否可达 ─────────────────────
echo ""
echo "[5] /copilot_internal/v2/token 是否可达"
INT_RESP=$(curl -s -o /tmp/copilot-int-body.json -w "%{http_code}" \
    -H "Authorization: token $TOKEN" \
    -H "User-Agent: GitHubCopilotChat/0.38.2" \
    -H "Editor-Version: vscode/1.110.1" \
    -H "Editor-Plugin-Version: copilot-chat/0.38.2" \
    https://api.github.com/copilot_internal/v2/token \
    --max-time 10 2>&1)
echo "  HTTP $INT_RESP"
echo "  body: $(head -c 300 /tmp/copilot-int-body.json)"
rm -f /tmp/copilot-int-body.json

echo ""
echo "════════════════════════════════════════════════════════"
echo "  诊断完成。把上面全部输出贴回去对比"
echo "════════════════════════════════════════════════════════"
