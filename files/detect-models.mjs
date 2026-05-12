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

const COMMON_HEADERS = {
  "Copilot-Integration-Id": "vscode-chat",
  "Editor-Version": "vscode/1.110.1",
  "Editor-Plugin-Version": "copilot-chat/0.38.2",
  "x-github-api-version": "2025-10-01",
  "User-Agent": "GitHubCopilotChat/0.38.2",
}

// ─── Step 1: 加载 OAuth token、换 Copilot 短期 Bearer ──────────
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

console.log("→ 换 Copilot 短期 token...")
const tokenRes = await fetch(
  "https://api.github.com/copilot_internal/v2/token",
  { headers: { Authorization: `token ${githubToken}`, ...COMMON_HEADERS } }
)
if (!tokenRes.ok) {
  console.error(`❌ 换 token 失败: ${tokenRes.status} ${tokenRes.statusText}`)
  console.error(await tokenRes.text())
  process.exit(1)
}
const { token: copilotToken } = await tokenRes.json()
console.log("  ✓ 拿到 Copilot Bearer")

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

async function probe(model) {
  try {
    const res = await fetch("https://api.githubcopilot.com/v1/messages", {
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
    return { ok: res.ok, status: res.status }
  } catch (e) {
    return { ok: false, status: 0, error: e.message }
  }
}

console.log("\n→ 探测各模型可用性（按从新到旧）...\n")
const result = {}
for (const [family, models] of Object.entries(FAMILIES)) {
  console.log(`  [${family}]`)
  for (const m of models) {
    const r = await probe(m)
    const mark = r.ok ? "✓" : "✗"
    console.log(`    ${mark} ${m.padEnd(22)} HTTP ${r.status}`)
    if (r.ok && !result[family]) {
      result[family] = m
    }
  }
  console.log("")
}

// ─── Step 3: Haiku/Sonnet 都不可用时的兜底 ──────────────────────
if (!result.haiku) {
  console.log(`⚠ Haiku 全家不可用，兜底映射到 ${result.sonnet || result.opus}`)
  result.haiku = result.sonnet || result.opus
}
if (!result.sonnet) {
  console.log(`⚠ Sonnet 全家不可用，兜底映射到 ${result.opus}`)
  result.sonnet = result.opus
}
if (!result.opus) {
  console.error("❌ Opus 系列全部不可用，套餐有问题，没法继续")
  process.exit(1)
}

writeFileSync(OUT_FILE, JSON.stringify(result, null, 2) + "\n")
console.log(`✓ 写入 ${OUT_FILE}`)
console.log(JSON.stringify(result, null, 2))
console.log("\n  Claude Code 请求的 Anthropic 模型会被映射到这些 Copilot 模型。")
console.log("  代理服务下次重启自动加载（或现在跑 claude-cp-restart）。")
