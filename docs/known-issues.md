# 已知坑（血泪经验）

## 1. cc-switch 的全局本地路由 bug

**版本**：实测于 cc-switch 截至 2026-05-12 的最新版

**症状**：
启用 GitHub Copilot profile 时，cc-switch 会自动打开「启用本地路由」全局开关，并在 `~/.claude/settings.json` 的 `env` 段注入 `ANTHROPIC_BASE_URL=http://localhost:xxxx`。所有正在跑的 Claude Code 窗口下次 API 调用会被劫持到 cc-switch 的本地路由，返回：

```
API Error: 400 bad request: Authorization header is badly formatted
```

**为什么切回 default 也没用**：「启用本地路由」是**独立的全局开关**，不跟随 profile 切换。即使把当前 profile 切回 default（空 env），本地路由进程依然在跑、依然劫持请求，所以 400 不消失。

**唯一解决办法**：在 cc-switch 设置里**手动关闭**「启用本地路由」开关。此时 settings.json 的 env 被清空，恢复正常。但**期间所有 Claude Code 会话已经报错挂掉**，正在跑的对话上下文丢失（jsonl 还在磁盘可 resume，但要重新加载）。

**永久预防**：
- 永远不要打开「启用本地路由」开关
- 删除 cc-switch 里的 Copilot profile（避免误启用）
- 用本包的旁路方案代替

## 2. GitHub Copilot Business 套餐的模型可用性谜团

Copilot API 在返回 400 时附带 "Available models" 列表，但**这个列表不准**。实测：

| 模型 | API 列表说 | 实际状态 |
|---|---|---|
| `claude-opus-4.7` | ✅ 在列表里 | ❌ 实际 400 model_not_supported |
| `claude-opus-4.6` | ❌ 不在列表里 | ✅ 实际能用 |
| `claude-opus-4.5` | ✅ 在列表里 | ✅ 能用 |
| `claude-sonnet-4.5` | ✅ 在列表里 | ✅ 能用 |
| `claude-haiku-4.5` | ✅ 在列表里 | ❌ 实际 403 ToS forbidden |

**推断**：
- 列表是 Copilot 整体的可用模型清单，与具体 integrator-id（用户身份）的实际权限不一致
- Business 套餐对某些模型有 ToS 限制（如 Haiku 不开放）
- 模型上下架在 Copilot 后端动态变化，列表更新有延迟

**应对策略**：
- 不要盲信 API 返回的列表
- 实际通过 curl 测一遍才算数
- proxy.mjs 的模型映射保守一点，遇到 400/403 就 fallback 到一个**已实测可用**的模型
- 模型可用性周期性 review（建议每季度跑一次本包里的测试脚本验证）

## 3. Claude Code 启动时的 Auth Conflict 警告

**症状**：跑 `claude-cp` 时显示：
```
Auth conflict: Both a token (claude.ai) and an API key (ANTHROPIC_API_KEY) are set.
This may lead to unexpected behavior.
```

**实际行为**：警告归警告，实际请求会用 API key + 自定义 BASE_URL 路径走代理。只要 `ANTHROPIC_BASE_URL` 不是 `api.anthropic.com`，Claude Code 不会用 claude.ai 订阅 token。

**为什么不消除警告**：消除需要 `claude /logout`，但那会清掉 Keychain 全局订阅 token，**所有其它正在跑的 Claude Code 窗口**会一起挂掉。代价远大于警告本身。

**接受现状**。

## 4. Claude Code Banner 显示的模型 ≠ 实际使用的模型

**症状**：`claude-cp` 启动后顶部显示 `Opus 4.7 (1M context)`，让人以为在用 4.7。

**真相**：那个 banner 是 Claude Code 客户端的标签，跟实际请求出去的模型无关。代理会偷偷把模型名改成 `claude-opus-4.6`。

**验证方式**：看 `claude-cp-log`，里面有 `→ claude-opus-4-7 → claude-opus-4.6` 的映射记录，那个**右侧**的才是真正发到 Copilot 的模型名。

## 5. ClashX 路由要正确覆盖 githubcopilot.com

**症状**：偶尔 timeout 或 SSL 握手失败。

**原因**：ClashX 默认规则可能把 `api.githubcopilot.com` 走「直连」，国内直连不一定通。

**验证**：
```bash
curl -v https://api.githubcopilot.com/ --max-time 5
```
看输出里 `Trying 127.0.0.1:7890` → 走代理，OK；如果直接 Trying 公网 IP → 没走代理，可能不通。

**修复**：在 ClashX 配置里加规则：
```yaml
- DOMAIN-SUFFIX,githubcopilot.com,Proxy
```

## 6. 长期 token 过期处理

GitHub OAuth token 长期有效，但以下情况会失效：

- 你在 GitHub 设置里手动撤销
- 公司 IT 收回你的 Copilot 订阅
- GitHub 检测到异常使用（多机器并发？）

失效后 `claude-cp-log` 会报 401。重新授权：
```bash
rm ~/.claude-copilot-auth.json
cd ~/claude-code-copilot
node scripts/auth.mjs
claude-cp-restart
```

## 7. 跨机器 token 复制的隐私风险

GitHub OAuth token 是凭证，跟 SSH 私钥同级。复制到别的机器 = 那台机器有完整 Copilot 调用权限，消耗你的额度。

**建议**：新机器走一遍 Device Flow（30 秒事），不要复制 token 文件。

如果非要复制（离线环境）：传输过程必须加密（不要走明文 IM/邮件），传完立刻删中转副本。
