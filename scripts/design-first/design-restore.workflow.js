// design-restore.workflow.js — 编排【蓝图参考】:设计稿 → 高保真前端 推荐的多 agent 扇出结构
// 本文件性质:它是【蓝图参考】,展示该关推荐的多 agent 扇出结构(扇出哪些子任务、parallel/pipeline、对抗验证什么、loop 到什么条件、各 agent 干啥、产物落哪),不是本项目的可执行脚本。
// 真执行时:用户手动开 ultracode 模式,AI(Claude)用 Claude 内置的【Workflow 工具】参考本蓝图当场组合编排(script 由 AI 现场写,非加载本文件运行)。
//   ⚠️ Workflow 工具归 Claude/ultracode,非本项目定义;本项目不拥有 workflow 运行时,也没有 `claude workflow` 这种命令。
//   ⚠️ ultracode 是用户手动开的会话高级模式;开了之后 AI 才默认倾向用 Workflow 工具编排。
//   在目标业务项目根执行,确保 CLAUDE_PROJECT_DIR 指向它。
// 产物(随项目根):docs/design/{design-manifest,tokens}.json + baseline PNG
//                 .claude/state/ui-diff.json + .claude/state/token-match.json(闸门读)
//
// 四质量模式归位:
//   fan-out 全覆盖   = parallel(screen × viewport 笛卡尔积)
//   loop-until-converge = screen worker 内 for + 分数单调降判据 + k 轮熔断
//   completeness critic = Synthesis phase 单 agent 核覆盖再写 state JSON
//
// 蓝图里用到的编排原语(由 Claude 内置 Workflow 工具提供,非本项目定义):phase(title) / parallel(fns[]) / agent(prompt,{label,phase,schema})
// 每个 agent 返回必须符合 schema(JSON Schema)。每个并行 worker 必须 .catch 兜底成合法 fallback。

export const meta = {
  name: 'design-restore-orchestrated',
  description: '抽 manifest → 按屏×视口并行还原(loop-until-converge:渲染→diff→定位→局部重生,单调降才继续)→ 汇总产 ui-diff.json/token-match.json',
  phases: [
    { title: 'Extract',    detail: 'single agent — 三管线归一 → design-manifest.json + tokens.json + baseline PNG' },
    { title: 'Per-Screen', detail: 'parallel × (screen×viewport) — 每屏 loop-until-converge,最多 k 轮' },
    { title: 'Synthesis',  detail: 'completeness critic — 写 ui-diff.json/token-match.json' },
  ],
}

const ROOT = process.env.CLAUDE_PROJECT_DIR || process.cwd()
const K_ROUNDS = 3
const VIEWPORTS = ['iPhone-390x844', 'Android-360x800']
const PLATFORM = 'SwiftUI'

// ── phase 1: 抽取 manifest(扇出前唯一输入,FROZEN)──
phase('Extract')
const extract = await agent(
  `三管线(pen/figma/screenshot)归一,reify≠create:只记录看到的 + 标注推断,不发明 UI。
   降级链:source=pen 且 get_editor_state 报 WebSocket not connected → 退 .pen 导出 PNG 走 screenshot 档,
   extraction_meta 记 requested_source/actual_source/degraded/reason(降级不静默)。
   先抽 token(最确定)→ ${ROOT}/docs/design/tokens.json(W3C DTCG,每 token $extensions.confidence=extracted|inferred)。
   抽屏清单+组件+逐屏布局树,inferred_* 字段标注为草稿。动态区(动画/头像/时间戳)标 dynamic:true。
   导 baseline PNG 到 ${ROOT}/docs/design/baseline/<platform>/<viewport>/<screen>.png(DPR 记进 extraction_meta.dpr)。
   写 ${ROOT}/docs/design/design-manifest.json。返回 screens[] + dpr。`,
  { label: 'extract', phase: 'Extract', schema: {
      type: 'object', required: ['screens', 'dpr'],
      properties: { screens: { type: 'array', items: { type: 'string' } }, dpr: { type: 'number' } } } }
)

// ── phase 2: 按屏 × 视口扇出,每 worker 内 loop-until-converge ──(fan-out + loop)
phase('Per-Screen')
const combos = extract.screens.flatMap(s => VIEWPORTS.map(v => ({ screen: s, viewport: v })))
const perScreen = await parallel(combos.map(({ screen, viewport }) => async () => {
  const rounds = []
  let prevScore = Infinity, stop = 'fuse_3_rounds'
  for (let r = 1; r <= K_ROUNDS; r++) {
    const round = await agent(
      `屏=${screen} 视口=${viewport} 第 ${r} 轮。用 dpr=${extract.dpr} 同一 DPR 渲染→截图(playwright/各端截图)。
       mask 动态区(manifest dynamic:true 节点:动画/头像/时间),否则纯像素 diff 误杀 30-40%。
       npx pixelmatch render.png baseline.png diff.png 0.1 → diff_ratio;SSIM → ssim。
       token 对账:渲染态 computed style vs tokens.json,回溯不到 token 的计 token_mismatch。
       codex-image-bridge VLM 定位语义残差(图标错/层级错/文案截断)→ vlm_severity。
       局部重生只修最差区。返回 diff_ratio/ssim/token_mismatch/vlm_severity/score(加权)。`,
      { label: `${screen}@${viewport}#${r}`, phase: 'Per-Screen', schema: {
          type: 'object', required: ['score', 'diff_ratio', 'ssim', 'token_mismatch'],
          properties: {
            diff_ratio: { type: 'number' }, ssim: { type: 'number' },
            token_mismatch: { type: 'integer' }, vlm_severity: { enum: ['none', 'minor', 'major'] },
            score: { type: 'number' } } } }
    ).catch(e => ({ score: prevScore, diff_ratio: 1, ssim: 0, token_mismatch: 99, vlm_severity: 'major', _err: String(e) }))
    rounds.push({ round: r, ...round })
    // loop-until-converge:分数单调降才继续,不降即停(不为压阈值死磕)
    if (round.score >= prevScore) { stop = 'score_not_monotonic'; break }
    prevScore = round.score
    if (round.diff_ratio * 100 <= 3 && round.token_mismatch === 0) { stop = 'converged'; break }
  }
  const last = rounds[rounds.length - 1]
  return { screen, viewport, platform: PLATFORM, rounds, stop_reason: stop,
           mismatch: Math.round((last.diff_ratio || 0) * 100), token_mismatch: last.token_mismatch || 0,
           converged: stop === 'converged' }
}).map(p => p.catch(e => ({ screen: '?', viewport: '?', platform: PLATFORM, rounds: [],
    stop_reason: 'fuse_3_rounds', mismatch: 100, token_mismatch: 99, converged: false }))))

// ── phase 3: completeness critic + 写闸门 JSON(唯一写 state 的点,保 key 严格对齐 app-gate.sh)──
phase('Synthesis')
const synth = await agent(
  `完整性审查 + 用【确定性脚本】产出闸门 state(唯一可信产出口,严禁手写 JSON——手写易和闸门 key 错位)。输入 perScreen=${JSON.stringify(perScreen)}。
   1) 核覆盖:每 (屏×视口) 都渲染+diff 了?动态区都 mask?stop_reason≠converged 的屏列入 halted 上报。
   2) 用 Bash 跑本 skill 仓 scripts/design-first/ 下的确定性脚本(与本 .workflow.js 同目录;先 \`head\` 读其顶部 usage 再按参数跑):
      - visual-diff.mjs  → 比 ${ROOT}/docs/design/baseline 与实现截图 → 写 ${ROOT}/.claude/state/ui-diff.json
      - token-match.mjs  → 比 ${ROOT}/docs/design/tokens.json 与实现 computed 样式 → 写 ${ROOT}/.claude/state/token-match.json
      二者确定性产出 {mismatch,per_screen} / {hardcoded_count,mismatched_count},key 已对齐 app-gate.sh。
   3) 跑完用 \`bash scripts/app-gate.sh app-gate qa\` 复核闸门读到这两份。
   返回写入摘要 + halted(未收敛屏)。`,
  { label: 'critic', phase: 'Synthesis', schema: {
      type: 'object', required: ['ui_diff', 'token_match', 'halted'],
      properties: { ui_diff: { type: 'object' }, token_match: { type: 'object' },
        halted: { type: 'array', items: { type: 'string' } } } } }
)

return { extract, perScreen, synth }
