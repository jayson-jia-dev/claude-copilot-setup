#!/usr/bin/env bash
#
# 一键全面诊断 — Claude × Copilot Setup
#
# 用法:
#   bash ~/claude-copilot-setup/scripts/diagnose.sh
#
# 输出全部贴回去就够定位问题，不用再来回问。
#
set +e

AUTH_FILE="$HOME/.claude-copilot-auth.json"
MODELS_FILE="$HOME/.claude-copilot-models.json"
PROXY_DIR="$HOME/claude-code-copilot"
PLIST="$HOME/Library/LaunchAgents/com.jayson.claude-copilot-proxy.plist"
OUT_LOG="$HOME/Library/Logs/claude-copilot-proxy.out.log"
ERR_LOG="$HOME/Library/Logs/claude-copilot-proxy.err.log"
SETUP_DIR="$HOME/claude-copilot-setup"

section() { echo ""; echo "════════════════════════════════════════════════════════"; echo "  $1"; echo "════════════════════════════════════════════════════════"; }
sub() { echo ""; echo "── $1 ──"; }

# ──────────────────────────────────────────────────────────
section "Claude × Copilot 全面诊断"
echo "执行时间: $(date '+%Y-%m-%d %H:%M:%S %z')"
echo "主机名  : $(hostname)"
echo "macOS   : $(sw_vers -productVersion 2>/dev/null) ($(uname -m))"

# ──────────────────────────────────────────────────────────
section "[1] 安装包版本"
sub "本地仓库 commit"
if [ -d "$SETUP_DIR/.git" ]; then
    git -C "$SETUP_DIR" log -1 --pretty='  %h %s (%ar)'
else
    echo "  ⚠ $SETUP_DIR 不是 git 仓库或不存在"
fi

sub "proxy.mjs 关键功能开关（看代码是否更到最新）"
PROXY_FILE="$PROXY_DIR/scripts/proxy.mjs"
if [ -f "$PROXY_FILE" ]; then
    has_token_exchange=$(grep -c "getCopilotBearer\|/copilot_internal/v2/token" "$PROXY_FILE")
    has_client_hdrs=$(grep -c "COPILOT_CLIENT_HEADERS" "$PROXY_FILE")
    has_user_overrides=$(grep -c "USER_MODEL_OVERRIDES" "$PROXY_FILE")
    echo "  token 换发逻辑 (getCopilotBearer)   : $has_token_exchange (期望 ≥ 3)"
    echo "  VSCode client headers              : $has_client_hdrs (期望 ≥ 2)"
    echo "  实测覆盖加载 (USER_MODEL_OVERRIDES) : $has_user_overrides (期望 ≥ 2)"
else
    echo "  ⚠ $PROXY_FILE 不存在 — 没跑过 install.sh？"
fi

# ──────────────────────────────────────────────────────────
section "[2] Token 信息"
if [ ! -f "$AUTH_FILE" ]; then
    echo "❌ 不存在 $AUTH_FILE，先跑 install.sh"
    TOKEN=""
else
    TOKEN=$(python3 -c "import json; print(json.load(open('$AUTH_FILE'))['access_token'])" 2>/dev/null)
    echo "  文件   : $AUTH_FILE"
    echo "  权限   : $(stat -f '%Sp %Su:%Sg' "$AUTH_FILE")"
    echo "  prefix : ${TOKEN:0:8}..."
    echo "  长度   : ${#TOKEN}"

    sub "Token 对应 GitHub 账号"
    USER_JSON=$(curl -s -H "Authorization: token $TOKEN" https://api.github.com/user)
    echo "  $USER_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f\"  login : {d.get('login','??')}\")
print(f\"  id    : {d.get('id','??')}\")
print(f\"  name  : {d.get('name','??')}\")
" 2>/dev/null

    sub "OAuth scope / client id"
    curl -sI -H "Authorization: token $TOKEN" https://api.github.com/user \
        | grep -iE '^x-oauth-scopes:|^x-oauth-client-id:|^x-accepted-oauth-scopes:' \
        | sed 's/^/  /'
fi

# ──────────────────────────────────────────────────────────
section "[3] /copilot_internal/v2/token 短期 Bearer 换发"
if [ -n "$TOKEN" ]; then
    EXCHANGE_BODY=$(curl -s -w "\n__HTTP_STATUS__%{http_code}__" \
        -H "Authorization: token $TOKEN" \
        -H "Copilot-Integration-Id: vscode-chat" \
        -H "Editor-Version: vscode/1.110.1" \
        -H "Editor-Plugin-Version: copilot-chat/0.38.2" \
        -H "User-Agent: GitHubCopilotChat/0.38.2" \
        https://api.github.com/copilot_internal/v2/token \
        --max-time 10)
    EXCHANGE_STATUS=$(echo "$EXCHANGE_BODY" | grep -oE '__HTTP_STATUS__[0-9]+__' | tr -d '_HTPSAU')
    EXCHANGE_BODY=$(echo "$EXCHANGE_BODY" | sed 's|__HTTP_STATUS__[0-9]*__||')
    echo "  HTTP $EXCHANGE_STATUS"
    if [ "$EXCHANGE_STATUS" = "200" ]; then
        echo "$EXCHANGE_BODY" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f\"  chat_enabled        : {d.get('chat_enabled')}\")
print(f\"  copilot_plan        : {d.get('copilot_plan','??')}\")
print(f\"  organization_list   : {d.get('organization_list', [])}\")
print(f\"  endpoints.api       : {d.get('endpoints',{}).get('api','??')}\")
print(f\"  endpoints.proxy     : {d.get('endpoints',{}).get('proxy','??')}\")
print(f\"  expires_at          : {d.get('expires_at','??')}\")
tid = d.get('token','')
print(f\"  token prefix        : {tid[:20]}...\")

# 把 tid 和 api 写到临时文件给后面用
# tid bearer 含分号（tid=xxx;sku=...;proxy-ep=...），必须单引号包起来
# 否则 bash source 时分号会被当语句分隔符截断 token
import shlex
with open('/tmp/copilot-diag.env', 'w') as f:
    f.write(f\"TID={shlex.quote(tid)}\nAPI_BASE={shlex.quote(d.get('endpoints',{}).get('api','https://api.githubcopilot.com'))}\n\")
"
    else
        echo "  body: $(echo "$EXCHANGE_BODY" | head -c 300)"
    fi
fi

# ──────────────────────────────────────────────────────────
section "[4] Copilot Chat 实测各模型可用性"
if [ -f /tmp/copilot-diag.env ]; then
    source /tmp/copilot-diag.env
    echo "  endpoint: $API_BASE"
    echo ""
    for MODEL in "claude-opus-4.7" "claude-opus-4.6" "claude-opus-4.5" \
                 "claude-sonnet-4.6" "claude-sonnet-4.5" "claude-haiku-4.5" "gpt-4o"; do
        STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
            -X POST "$API_BASE/chat/completions" \
            -H "Authorization: Bearer $TID" \
            -H "Content-Type: application/json" \
            -H "Copilot-Integration-Id: vscode-chat" \
            -H "Editor-Version: vscode/1.110.1" \
            -H "Editor-Plugin-Version: copilot-chat/0.38.2" \
            -H "x-github-api-version: 2025-10-01" \
            -H "User-Agent: GitHubCopilotChat/0.38.2" \
            -H "x-initiator: user" \
            -d "{\"model\":\"$MODEL\",\"max_tokens\":5,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}" \
            --max-time 15)
        case "$STATUS" in
            200) MARK="✓" ;;
            400) MARK="✗ model_not_supported" ;;
            403) MARK="✗ forbidden (TOS / rate)" ;;
            429) MARK="✗ rate_limited" ;;
            *)   MARK="✗" ;;
        esac
        echo "  $MODEL → HTTP $STATUS $MARK"
        sleep 0.5  # 间隔避免限流
    done
    rm -f /tmp/copilot-diag.env
else
    echo "  跳过（步骤 3 换发 token 失败）"
fi

# ──────────────────────────────────────────────────────────
section "[5] 实测模型映射文件"
if [ -f "$MODELS_FILE" ]; then
    cat "$MODELS_FILE" | sed 's/^/  /'
else
    echo "  ⚠ $MODELS_FILE 不存在（detect-models 没成功跑过）"
fi

# ──────────────────────────────────────────────────────────
section "[6] launchd 服务状态"
sub "service 在不在 launchd 里"
launchctl list 2>/dev/null | grep claude-copilot-proxy | sed 's/^/  /'

sub "端口监听"
lsof -nP -iTCP:18080 -sTCP:LISTEN 2>/dev/null | sed 's/^/  /'

sub "plist 文件"
if [ -f "$PLIST" ]; then
    echo "  ✓ $PLIST"
    # 检查 plist 里 HTTPS_PROXY 设置
    grep -A1 "HTTPS_PROXY" "$PLIST" | grep -A1 "<string>" | head -2 | sed 's/^/    /'
else
    echo "  ⚠ $PLIST 不存在"
fi

# ──────────────────────────────────────────────────────────
section "[7] 走 proxy 实测（端到端 + 抓 debug 请求体）"
if lsof -nP -iTCP:18080 -sTCP:LISTEN >/dev/null 2>&1; then
    # 标记当前日志行数，触发后只看新增内容
    LOG_OUT_LINES_BEFORE=$(wc -l < "$OUT_LOG" 2>/dev/null || echo 0)
    LOG_ERR_LINES_BEFORE=$(wc -l < "$ERR_LOG" 2>/dev/null || echo 0)

    echo "  对 proxy 18080 发请求，模型 claude-opus-4-7..."
    PROXY_RESP=$(curl -s -X POST http://localhost:18080/v1/messages \
        -H "Content-Type: application/json" \
        -H "anthropic-version: 2023-06-01" \
        -H "x-api-key: copilot-proxy" \
        -d '{"model":"claude-opus-4-7","max_tokens":10,"messages":[{"role":"user","content":"reply: ok"}]}' \
        --max-time 25 -w "\n__HTTP_STATUS__%{http_code}__")
    PROXY_STATUS=$(echo "$PROXY_RESP" | grep -oE '__HTTP_STATUS__[0-9]+__' | tr -d '_HTPSAU')
    PROXY_BODY=$(echo "$PROXY_RESP" | sed 's|__HTTP_STATUS__[0-9]*__||')
    echo "  HTTP $PROXY_STATUS"
    echo "  body: $(echo "$PROXY_BODY" | head -c 300)"

    sleep 1
    # 抓 proxy 这次请求产生的新日志（重点是 [debug:req] / [debug:resp]）
    sub "本次请求 proxy out log 增量"
    if [ "$LOG_OUT_LINES_BEFORE" -gt 0 ]; then
        tail -n +$((LOG_OUT_LINES_BEFORE + 1)) "$OUT_LOG" | sed 's/^/  /'
    fi
    sub "本次请求 proxy err log 增量"
    if [ "$LOG_ERR_LINES_BEFORE" -gt 0 ]; then
        tail -n +$((LOG_ERR_LINES_BEFORE + 1)) "$ERR_LOG" | sed 's/^/  /'
    fi
else
    echo "  ⚠ proxy 没在 18080 监听，跳过端到端测"
fi

# ──────────────────────────────────────────────────────────
section "[7b] 切换到「每次请求换发新 tid」模式重测"
sub "为何要测这个"
echo "  proxy 缓存了启动时换发的 tid，可能这个 tid 被 Copilot 实验分流到"
echo "  '无 Claude 权限' 实验组，长期失败。NO_BEARER_CACHE=1 强制每请求"
echo "  换新 tid，看是否能稳定 200。"

PLIST_DST="$HOME/Library/LaunchAgents/com.jayson.claude-copilot-proxy.plist"
if [ -f "$PLIST_DST" ] && grep -q "COPILOT_NO_BEARER_CACHE" "$PLIST_DST"; then
    echo "  ✓ plist 已含 NO_BEARER_CACHE，跳过修改"
else
    echo "  → 临时给 plist 加 COPILOT_NO_BEARER_CACHE=1 并重启"
    # 在 EnvironmentVariables dict 末尾插入这一对 key/string
    if [ -f "$PLIST_DST" ]; then
        cp "$PLIST_DST" "${PLIST_DST}.bak-$(date +%s)"
        # 用 macOS 自带的 plutil 改 plist，避开 python plistlib 在 3.14 的 expat bug
        plutil -insert 'EnvironmentVariables.COPILOT_NO_BEARER_CACHE' \
            -string '1' "$PLIST_DST" 2>/dev/null \
            || plutil -replace 'EnvironmentVariables.COPILOT_NO_BEARER_CACHE' \
                -string '1' "$PLIST_DST"
        echo "  ✓ plist 已注入 COPILOT_NO_BEARER_CACHE=1"
        launchctl kickstart -k "gui/$(id -u)/com.jayson.claude-copilot-proxy" 2>/dev/null
        sleep 3
    fi
fi

if lsof -nP -iTCP:18080 -sTCP:LISTEN >/dev/null 2>&1; then
    LOG_OUT_LINES_BEFORE2=$(wc -l < "$OUT_LOG" 2>/dev/null || echo 0)
    LOG_ERR_LINES_BEFORE2=$(wc -l < "$ERR_LOG" 2>/dev/null || echo 0)

    echo ""
    echo "  连续 3 次请求 sonnet-4-6，每次换新 tid，看是否都 200:"
    for i in 1 2 3; do
        STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
            -X POST http://localhost:18080/v1/messages \
            -H "Content-Type: application/json" \
            -H "anthropic-version: 2023-06-01" \
            -H "x-api-key: copilot-proxy" \
            -d '{"model":"claude-sonnet-4-6","max_tokens":10,"messages":[{"role":"user","content":"ping"}]}' \
            --max-time 25)
        echo "    第 $i 次 → HTTP $STATUS"
        sleep 2
    done

    sub "三次请求 proxy 增量日志"
    if [ "$LOG_OUT_LINES_BEFORE2" -gt 0 ]; then
        tail -n +$((LOG_OUT_LINES_BEFORE2 + 1)) "$OUT_LOG" | grep -E "copilot-auth|debug:req|debug:resp|→" | sed 's/^/  /'
    fi
fi

# ──────────────────────────────────────────────────────────
section "[8] proxy 日志最近 40 行 (out)"
if [ -f "$OUT_LOG" ]; then
    tail -40 "$OUT_LOG" | sed 's/^/  /'
else
    echo "  ⚠ 没有 out 日志"
fi

sub "proxy 日志最近 20 行 (err)"
if [ -f "$ERR_LOG" ]; then
    tail -20 "$ERR_LOG" | sed 's/^/  /'
else
    echo "  ⚠ 没有 err 日志"
fi

# ──────────────────────────────────────────────────────────
section "[9] 网络代理状态"
echo "  HTTPS_PROXY (env)  : ${HTTPS_PROXY:-<未设置>}"
echo "  https_proxy (env)  : ${https_proxy:-<未设置>}"
echo "  NO_PROXY (env)     : ${NO_PROXY:-<未设置>}"

sub "本地代理端口扫描"
for PORT in 7890 7891 7897 7898 6152 8001 1087 10809; do
    if nc -z 127.0.0.1 "$PORT" 2>/dev/null; then
        echo "  ✓ $PORT 在监听"
    fi
done

sub "出口 IP 对比（curl vs Node fetch）"
echo "  curl 出口 IP  : $(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo 'fail')"
NODE_IP=$(node -e "fetch('https://api.ipify.org').then(r=>r.text()).then(t=>console.log(t)).catch(e=>console.log('ERR:'+e.message))" 2>/dev/null)
echo "  Node fetch IP : $NODE_IP"
echo ""
echo "  → 如果两者 IP 不同，说明 Node fetch 没走 HTTPS_PROXY（直连）"
echo "  → home/家庭 IP 调 Copilot 会被风控成 400"
echo "  → 修法：proxy.mjs 要用 undici ProxyAgent 强制走代理（最新代码已加）"

# ──────────────────────────────────────────────────────────
section "[10] Claude Code 客户端"
sub "wrapper"
if [ -f "$HOME/.local/bin/claude-cp" ]; then
    echo "  ✓ $HOME/.local/bin/claude-cp ($(stat -f '%Sp' $HOME/.local/bin/claude-cp))"
else
    echo "  ⚠ 没装 wrapper"
fi

sub "PATH 上的 claude（wrapper 实际会用的）"
for cand in "$HOME/.local/bin/claude" "$HOME/.bun/bin/claude" "/opt/homebrew/bin/claude" "/usr/local/bin/claude" $(ls -d "$HOME"/.nvm/versions/node/*/bin/claude 2>/dev/null); do
    if [ -x "$cand" ]; then
        ver=$("$cand" --version 2>/dev/null | head -1)
        echo "  $cand → $ver"
    fi
done

# ──────────────────────────────────────────────────────────
section "诊断结束"
echo "完整输出全部贴回去，对照 [4] 模型实测和 [7] 端到端、[8] 日志即可定位。"
echo ""
