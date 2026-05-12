# 故障排查手册

## 速查表

| 症状 | 最可能原因 | 快速验证 |
|---|---|---|
| `claude-cp` 命令找不到 | zshrc 没重新加载 | 新开终端或 `source ~/.zshrc` |
| 400 model_not_supported | Copilot 后端下架了某模型 | 看 `claude-cp-log` 找具体模型名，改 `proxy.mjs` 映射 |
| 403 forbidden | Copilot Business 套餐禁用某模型（如 Haiku） | 同上，兜底成 Sonnet |
| 401 unauthorized | GitHub OAuth token 失效 | `rm ~/.claude-copilot-auth.json && cd ~/claude-code-copilot && node scripts/auth.mjs` |
| Connection refused localhost:18080 | launchd 服务没起 | `claude-cp-status` 看 PID，`launchctl load ...plist` |
| 超时/握手失败 | ClashX 没起 / 路由规则不包括 githubcopilot.com | `curl -v https://api.githubcopilot.com/` |

## 详细诊断流程

### Step 1：代理服务是否在跑

```bash
claude-cp-status
```

预期输出两行：
```
<PID>  0  com.jayson.claude-copilot-proxy
node ... TCP *:18080 (LISTEN)
```

如果两行都没有 → 跑 `launchctl load ~/Library/LaunchAgents/com.jayson.claude-copilot-proxy.plist`

如果只有第一行没有第二行 → 进程崩了又被 KeepAlive 拉起，看错误日志：
```bash
tail -50 ~/Library/Logs/claude-copilot-proxy.err.log
```

### Step 2：代理本身能否调通 Copilot

```bash
curl -s -X POST http://localhost:18080/v1/messages \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -H "x-api-key: copilot-proxy" \
  -d '{"model":"claude-sonnet-4-5","max_tokens":15,"messages":[{"role":"user","content":"ping"}]}'
```

- 返回 `"text":"..."` → 代理通，问题在 Claude Code 端
- 返回 `"type":"error"` → 看 error message 对症下药（往下看）

### Step 3：常见错误对照

#### `Copilot API error (400): model_not_supported`

Copilot 后端不认这个模型名。两种处理：

A. **改 proxy.mjs 映射**：把对应模型映射到一个**实测可用**的：
```js
"claude-opus-4-X": "claude-opus-4.5",  // 改成 4.5 兜底
```
然后 `claude-cp-restart`

B. **看实际可用列表**：先用错误模型故意触发一次错误响应，看 error.message 里 "Available models: [...]" 列表（这个列表可能不准，但是参考）

#### `Copilot API error (403): Access to this endpoint is forbidden`

ToS 限制，某些模型在 Business 套餐里被禁。处理同上，改映射兜底到允许的模型。

历史上的禁用列表（参考，会变）：
- `claude-haiku-4.5` ← 已知禁用
- 其它可能后续被禁的会出现新的 403

#### `Copilot API error (401)`

OAuth token 失效。三种可能：
1. **Token 被用户在 GitHub 设置里撤销了** → 重新跑 Device Flow
2. **GitHub 账号失去 Copilot 订阅资格**（公司收回了？） → 跟 IT 确认
3. **Token 文件被误删 / 损坏** → 检查 `cat ~/.claude-copilot-auth.json`

重新授权：
```bash
rm ~/.claude-copilot-auth.json
cd ~/claude-code-copilot
node scripts/auth.mjs
# 浏览器自动打开，输入 user_code，授权
claude-cp-restart
```

#### `connection refused` / `timeout`

代理服务端：
- 端口冲突？`lsof -nP -iTCP:18080` 看是不是被别的进程占了
- launchd 没起？`launchctl list | grep claude-copilot-proxy`

上游网络：
```bash
curl -v https://api.githubcopilot.com/ --max-time 5
```
- TLS 握手成功 → 网络通
- timeout → 检查 ClashX 是否在跑、规则是否覆盖 `api.githubcopilot.com`

### Step 4：Claude Code 端报「Auth conflict」

启动 `claude-cp` 时如果同时有订阅 OAuth（claude.ai）和 API key，会有警告：
```
Auth conflict: Both a token (claude.ai) and an API key (ANTHROPIC_API_KEY) are set.
```

**通常可以无视**——当 `ANTHROPIC_BASE_URL` 指向非 `api.anthropic.com` 时，Claude Code 会优先用 API key 路径。

**绝对不要按警告里说的跑 `/logout`！** 那会清掉 Keychain 全局订阅 token，所有其它 Claude Code 窗口也跟着挂。

如果真的需要消除警告（强迫症），方法是单独跑一个不带订阅 token 的 Claude Code（比如新的用户账号下），太麻烦不值得。

## 验证 Copilot 真的被用了（而不是订阅）

Claude Code 的 banner 显示 "Opus 4.7" **不能作为证据**——那只是它自己的标签，跟实际用啥模型无关。

证据应该从代理日志里看：
```bash
claude-cp-log
```

会看到类似：
```
[2026-05-12T04:07:03.145Z] POST /v1/messages?beta=true
→ claude-opus-4-7 → claude-opus-4.6 | stream | 1 messages
```

`→ claude-opus-4.6` 这一段就是实际发到 Copilot 的模型名，绝对真实。

## 紧急回滚

万一代理坏了影响到正常工作，要立刻禁用：

```bash
# 1. 停服务
launchctl unload ~/Library/LaunchAgents/com.jayson.claude-copilot-proxy.plist

# 2. 之后用 claude（订阅）正常工作，不受影响
# claude-cp 命令会报 connection refused，不用管，等修好

# 修好后重新加载
launchctl load ~/Library/LaunchAgents/com.jayson.claude-copilot-proxy.plist
```

完全卸载：
```bash
launchctl unload ~/Library/LaunchAgents/com.jayson.claude-copilot-proxy.plist
rm ~/Library/LaunchAgents/com.jayson.claude-copilot-proxy.plist
rm -rf ~/claude-code-copilot
rm ~/.claude-copilot-auth.json
# 从 ~/.zshrc 里删掉 4 个 alias 行
```
