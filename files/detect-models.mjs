#!/usr/bin/env node
//
// 探测当前 Copilot 套餐实际可用的最高级模型，结果写入
// ~/.claude-copilot-models.json，供 proxy.mjs 读取。
//
// 每家不同（个人 Pro vs Business vs Enterprise），同一家不同时间也会变
// （Copilot 后端动态上下架）。所以装机时实测，不写死。
//
// 用法：node detect-models.mjs
// 重测：claude-cp-detect-models（install.sh 已自动 alias）
//
import { readFileSync, writeFileSync, existsSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

const AUTH_FILE = join(homedir(), ".claude-copilot-auth.json")
const OUT_FILE = join(homedir(), ".claude-copilot-models.json")

// 必须跟 proxy.mjs 完全一致的 header 集合 — 缺 x-initiator 会 403
const COMMON_HEADERS = {
  "Copilot-Integration-Id": "vscode-chat",
  "Editor-Version": "vscode/1.110.1",
  "Editor-Plugin-Version": "copilot-chat/0.38.2",
  "x-github-api-version": "2025-10-01",
  "Openai-Intent": "conversation-agent",
  "User-Agent": "GitHubCopilotChat/0.38.2",
  "x-initiator": "user",  // 关键：Copilot 用这个区分合法客户端
}

// ─── Step 1: 加载 OAuth token，换发短期 Bearer ──────────────────────────────
// VSCode Copilot 实际做法：先用 ghu_ OAuth token 调 /copilot_internal/v2/token
// 换一个短期 Bearer（tid=...），用它打 /chat/completions。直接拿 OAuth 当 Bearer
// 会触发抗滥用限流，返回 403/400 抖动结果。
if (!existsSync(AUTH_FILE)) {
  console.error(`❌ 没找到 ${AUTH_FILE}，先跑 install.sh 走 GitHub Device Flow`)
  process.exit(1)
}

const auth = JSON.parse(readFileSync(AUTH_FILE, "utf8"))
const githubToken = auth.access_token

if (!githubToken) {
  console.error(`❌ ${AUTH_FILE} 格式不对，缺 access_token`)
  process.exit(1)
}

console.log(`✓ 加载 OAuth token (${githubToken.slice(0, 8)}...)`)
console.log(`→ 换发 Copilot 短期 Bearer (api.github.com/copilot_internal/v2/token)...`)

const exchangeRes = await fetch(
  "https://api.github.com/copilot_internal/v2/token",
  {
    headers: {
      Authorization: `token ${githubToken}`,
      ...COMMON_HEADERS,
    },
  }
)
if (!exchangeRes.ok) {
  const body = await exchangeRes.text()
  console.error(`❌ 换发短期 Bearer 失败 (HTTP ${exchangeRes.status}):`)
  console.error(body.slice(0, 300))
  process.exit(1)
}
const exchangeData = await exchangeRes.json()
const copilotToken = exchangeData.token
const COPILOT_API_BASE = exchangeData.endpoints?.api || "https://api.githubcopilot.com"
console.log(`  ✓ 拿到 Bearer (${copilotToken.slice(0, 12)}...)`)
console.log(`  ✓ Copilot API endpoint: ${COPILOT_API_BASE}`)

// ─── Step 2: 候选模型（从最新到最老）──────────────────────────
const FAMILIES = {
  opus: [
    "claude-opus-4.7",
    "claude-opus-4.6",
    "claude-opus-4.5",
    "claude-opus-4.1",
  ],
  sonnet: [
    "claude-sonnet-4.7",
    "claude-sonnet-4.6",
    "claude-sonnet-4.5",
    "claude-sonnet-4",
  ],
  haiku: ["claude-haiku-4.5"],
}

// 用 /chat/completions（OpenAI 协议端点）而非 /v1/messages（Anthropic 端点）
// 跟 proxy.mjs 转发用的端点保持一致，避免端点差异带来的可用性误差
// 加重试 + 间隔，避免短时间连发触发 Copilot 抗滥用风控
async function sleep(ms) { return new Promise(r => setTimeout(r, ms)) }

async function probe(model, attempt = 1) {
  try {
    const res = await fetch(`${COPILOT_API_BASE}/chat/completions`, {
      method: "POST",
      headers: {
        ...COMMON_HEADERS,
        Authorization: `Bearer ${copilotToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model,
        max_tokens: 5,
        messages: [{ role: "user", content: "hi" }],
      }),
    })
    // 429/限流时退避重试，最多 3 次
    if ((res.status === 429 || res.status === 403) && attempt < 3) {
      await sleep(2000 * attempt)
      return probe(model, attempt + 1)
    }
    return { ok: res.ok, status: res.status }
  } catch (e) {
    return { ok: false, status: 0, error: e.message }
  }
}

// 探测策略：每家从最新版本开始，**命中第一个就停**，不再测后面的旧版本。
// 9 个候选短时间连发会触发 Copilot 风控（403/429），命中即停最多 3 个 HTTP 请求。
console.log("\n→ 探测各模型可用性（按从新到旧，命中即停）...\n")
const result = {}
for (const [family, models] of Object.entries(FAMILIES)) {
  console.log(`  [${family}]`)
  for (const m of models) {
    const r = await probe(m)
    const mark = r.ok ? "✓" : "✗"
    console.log(`    ${mark} ${m.padEnd(22)} HTTP ${r.status}`)
    if (r.ok) {
      result[family] = m
      break  // 命中即停，避免触发限流
    }
    await sleep(800)  // 请求之间间隔，给 Copilot 喘息
  }
  console.log("")
}

// ─── Step 3: Haiku/Sonnet/Opus 不可用时的兜底 ────────────────────
// 注意先检查 opus —— 它是最后兜底锚点，没了别的没法挂靠
if (!result.opus) {
  console.error("\n❌ Opus 系列全部不可用 —— 探测请求全 400/403")
  console.error("\n常见原因：")
  console.error("  1) ~/.claude-copilot-auth.json 里 token 不是 ghu_ 类型")
  console.error("     （Device Flow 拿的 user-to-server token 才有 Copilot Chat 权限，")
  console.error("      gho_/ghp_/ghs_ 等同账号但权限不同的 token 全部 400）")
  console.error("     修法: rm ~/.claude-copilot-auth.json && cd ~/claude-code-copilot && node scripts/auth.mjs")
  console.error("")
  console.error("  2) 网络没走梯子 / 梯子规则不覆盖 api.githubcopilot.com")
  console.error("     检查: HTTPS_PROXY 是否设置、ClashX 配置里 anthropic/copilot 是否走代理")
  console.error("")
  console.error("  3) 账号 Copilot 订阅过期 / 公司收回")
  console.error("     检查: https://github.com/settings/copilot")
  process.exit(1)
}
if (!result.sonnet) {
  console.log(`⚠ Sonnet 全家不可用，兜底映射到 ${result.opus}`)
  result.sonnet = result.opus
}
if (!result.haiku) {
  console.log(`⚠ Haiku 全家不可用，兜底映射到 ${result.sonnet}`)
  result.haiku = result.sonnet
}

writeFileSync(OUT_FILE, JSON.stringify(result, null, 2) + "\n")
console.log(`✓ 写入 ${OUT_FILE}`)
console.log(JSON.stringify(result, null, 2))
console.log("\n  Claude Code 请求的 Anthropic 模型会被映射到这些 Copilot 模型。")
console.log("  代理服务下次重启自动加载（或现在跑 claude-cp-restart）。")
