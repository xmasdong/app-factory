#!/usr/bin/env node
// ui-vlm-residual.mjs — VLM 语义残差(像素 diff 之上的语义层,advisory)。
// 实现截图 vs 设计基线,产结构化 JSON。走 codex-image-bridge。
// 用法: node ui-vlm-residual.mjs <actual.png> <baseline.png> <out.json>
import { execFileSync } from 'node:child_process'
import { writeFileSync } from 'node:fs'
const [actual, baseline, out] = process.argv.slice(2)
if (!actual || !baseline || !out) { console.error('usage: ui-vlm-residual.mjs <actual.png> <baseline.png> <out.json>'); process.exit(2) }
const CLI = process.env.CODEX_IMAGE_CLI || `${process.env.HOME}/.claude/skills/codex-image-bridge/scripts/cli.mjs`
const prompt = '比较两图(第一=实现,第二=设计基线)。只输出 JSON: {"same_screen":bool,"missing_elements":[],"misplaced":[],"severity":"none|minor|major"}'
let res
try {
  const o = execFileSync('node', [CLI, 'edit', '--image', actual, '--image', baseline, '--prompt', prompt], { encoding: 'utf8', timeout: 120000 })
  const m = o.match(/\{[\s\S]*\}/); res = m ? JSON.parse(m[0]) : { same_screen: null, severity: 'unknown', raw: o.slice(0, 500) }
} catch (e) { res = { same_screen: null, severity: 'unknown', error: String(e).slice(0, 300) } }
writeFileSync(out, JSON.stringify(res, null, 2))
console.log('VLM 残差 →', out)
