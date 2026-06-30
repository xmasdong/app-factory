// discover.workflow.js — ultracode Workflow 编排:一句话方向 → 自决 5 字段 + 一手证据 + mockup + 闸门
// 怎么跑:AI 调用 Workflow 工具(Claude Code 内置·非 shell CLI),script = 本文件内容(Read 后传入)。
//   ⚠️ 不存在 `claude workflow` shell 命令;ultracode 是用户手动开的会话模式,只让 AI 默认倾向用 Workflow 工具。
//   在目标业务项目根执行,确保 CLAUDE_PROJECT_DIR 指向它。降级见 skills/discover/SKILL.md(单 agent 顺序)。
// 产物(随项目根,唯一写文件点在 Phase4):
//   docs/spec.md(产品定位/市场调研/概念视觉 3 章节,严禁 lockdown 章节)
//   docs/discovery-summary.md(≤120 行,5 段齐)
//   docs/mockups/ 或 .claude/state/concept-visuals/<concept>/(hero+screen-*)
//   .claude/state/market-research/(appstore-<r>-<kw>.json + reviews-*.json,一手样本)
//   .claude/state/clearance-discover.json + skill-signal.json(闸门读;key 由 app-gate.sh 产,不手写)
//
// 四质量模式归位:
//   fan-out 全覆盖     = parallel(sources × actions 笛卡尔积) 每 worker 一手证据,不抽样
//   pipeline 串数据    = Phase2 propose→attack 顺序串(proposer 喂 red-team)
//   adversarial verify = Phase2 独立 red-team agent 专职攻击 proposer 方向(≥3 反方 + ≥1 死亡案例)
//   loop(轻量熔断)    = red-team 判字段证据不足 → 回灌定向 Phase1 补一轮(最多 1 次)
//   completeness critic= Phase4 单 agent 核覆盖 + 用确定性脚本写 state(唯一可信产出口,避并行写冲突)
//
// Workflow runtime 全局:phase(title) / parallel(fns[]) / pipeline(items,...stages) / agent(prompt,{label,phase,schema}) / log()
// 每个 agent 返回须符合 schema;每个并行 worker 必须 .catch 兜底成合法 fallback,否则一崩全崩(降级不静默,记 reason)。

export const meta = {
  name: 'discover-orchestrated',
  description: 'Frame 抽关键词(FROZEN)→ sources×actions 扇出堆一手证据 → propose→red-team 对抗自决 5 字段(可回灌补证)→ mockup → completeness critic 跑 app-gate.sh 产 clearance-discover.json',
  phases: [
    { title: 'Frame',     detail: 'single agent — 抽关键词/形态/用户/平台 + 读 discarded + 判市场,扇出前唯一输入 FROZEN' },
    { title: 'Research',   detail: 'parallel × (sources×actions 笛卡尔积) — 商店/社交/差评各 worker 堆带 URL 一手证据,不下结论' },
    { title: 'Decide',     detail: 'pipeline propose→attack — proposer 自决 5 字段,独立 red-team 攻击,证据不足回灌补一轮' },
    { title: 'Visualize',  detail: 'codex-image-bridge 出 hero+screen-1/2/3(design-first 旁路整步跳过)' },
    { title: 'Synthesis',  detail: 'completeness critic — 唯一写文件点,核覆盖 + 跑 app-gate.sh 产 clearance-discover.json' },
  ],
}

const ROOT = process.env.CLAUDE_PROJECT_DIR || process.cwd()
const PROJECT_TYPE = process.env.PROJECT_TYPE || ''
const DESIGN_FIRST = PROJECT_TYPE === 'design-first'
const SOCIAL = ['reddit', 'xiaohongshu', 'x', 'producthunt', 'tiktok']
const MAX_BACKFILL = 1  // red-team 触发定向补证的最多轮数(熔断)

// ── Phase 0: Frame(single agent — 扇出前唯一输入,FROZEN)──
phase('Frame')
const frame = await agent(
  `从用户一句话方向抽:领域 / 形态线索(Tool/Content/Community/Commerce/Hybrid)/ 用户线索(年龄+性别+场景)/ 平台线索(iOS/Android/小程序)。
   读 ${ROOT}/.claude/state/discarded-directions.txt(存在则:本轮约束 = 5 字段至少 2 项须与上轮不同,把上轮方向摘要写进 avoid)。
   目标市场预判:关键词中文/"国内"→regions=['cn'];英文/"海外"/全球→regions=['us'];模糊→regions=['us','cn](双扫,Phase2 输出"为什么选这个市场")。
   ⛔ 输入太抽象("做点东西"/"做个 app")→ 直接 hard-stop 反问让用户补 ≥1 句具体描述,不接受空泛(此时返回 keywords:[] 让 AI 在会话内停下来问)。
   只抽关键词,不调研、不下结论。返回 {keywords[], regions[], avoid}。`,
  { label: 'frame', phase: 'Frame', schema: {
      type: 'object', required: ['keywords', 'regions'],
      properties: {
        keywords: { type: 'array', items: { type: 'string' } },
        regions: { type: 'array', items: { enum: ['us', 'cn'] } },
        avoid: { type: 'string' } } } }
)
// 抽象输入熔断:Frame 已 hard-stop 反问,无关键词即停止编排(不空跑扇出)。
if (!frame.keywords || frame.keywords.length === 0) {
  log('Frame hard-stop:输入太抽象,已反问用户补具体描述。停止编排。')
  return { frame, halted: 'abstract_input_hard_stop' }
}
// FROZEN:扇出前唯一输入,后续 phase 不得改写。
const KEYWORDS = frame.keywords
const REGIONS = (frame.regions && frame.regions.length) ? frame.regions : ['us']
const AVOID = frame.avoid || ''

// ── Phase 1: Research(parallel × sources×actions 笛卡尔积 — fan-out 全覆盖,只堆一手证据)──
// 构造 worker 任务池:storeSources(region×kw) + socialSources(平台) + reviewWorker。
function buildResearchTasks(keywords) {
  const tasks = []
  // storeSources = regions × keywords:各 region 一个 worker,curl itunes API 写样本
  for (const r of REGIONS) for (const kw of keywords) tasks.push({ kind: 'store', region: r, kw })
  // socialSources:各平台一个 worker,WebSearch/WebFetch 取一手帖,标年份
  for (const p of SOCIAL) tasks.push({ kind: 'social', platform: p, kw: keywords[0] })
  // reviewWorker:Top10 差评抓样
  tasks.push({ kind: 'reviews', kw: keywords[0] })
  return tasks
}

function researchWorker(t) {
  if (t.kind === 'store') {
    return agent(
      `商店扫描 region=${t.region} keyword=${t.kw}。Bash 跑:
       curl -sf "https://itunes.apple.com/search?term=${encodeURIComponent(t.kw)}&country=${t.region}&entity=software&limit=50" \
         > ${ROOT}/.claude/state/market-research/appstore-${t.region}-${t.kw}.json
       (先 mkdir -p ${ROOT}/.claude/state/market-research)。解析 Top50 变现分布(订阅/IAP/Ads/免费占比)、评分、价格带。
       不下结论,只产带 URL/响应的一手证据。返回 {source:'appstore-${t.region}', evidence:[{url,year,quote}], stale:bool}。`,
      { label: `store:${t.region}:${t.kw}`, phase: 'Research', schema: RESEARCH_SCHEMA }
    ).catch(e => ({ source: `appstore-${t.region}`, evidence: [], stale: false, _err: String(e), reason: 'store worker failed' }))
  }
  if (t.kind === 'social') {
    return agent(
      `社交一手调研 平台=${t.platform} keyword=${t.kw}。用 WebSearch/WebFetch 取一手帖(非训练记忆)。
       每条证据带 url + year + quote。⚠️ 2024 年前的标 stale:true 且在 quote 前加 [STALE-DATA]。
       不下结论,只堆证据。返回 {source:'${t.platform}', evidence:[{url,year,quote}], stale:bool}。`,
      { label: `social:${t.platform}`, phase: 'Research', schema: RESEARCH_SCHEMA }
    ).catch(e => ({ source: t.platform, evidence: [], stale: false, _err: String(e), reason: 'social worker failed' }))
  }
  // reviews:Top10 差评抓样(itunes RSS,≥100 条 1-2 星)
  return agent(
    `差评抓样 keyword=${t.kw}。对同领域 Top10 app,用 iTunes RSS customerreviews feed 抓 1-2 星 review,目标 ≥100 条。
     写 ${ROOT}/.claude/state/market-research/reviews-${t.kw}.json。提炼用户画像 + 高频痛点。
     返回 {source:'reviews', evidence:[{url,year,quote}], stale:bool}。`,
    { label: `reviews:${t.kw}`, phase: 'Research', schema: RESEARCH_SCHEMA }
  ).catch(e => ({ source: 'reviews', evidence: [], stale: false, _err: String(e), reason: 'review worker failed' }))
}

const RESEARCH_SCHEMA = {
  type: 'object', required: ['source', 'evidence'],
  properties: {
    source: { type: 'string' },
    evidence: { type: 'array', items: {
      type: 'object', required: ['url'],
      properties: { url: { type: 'string' }, year: { type: 'string' }, quote: { type: 'string' } } } },
    stale: { type: 'boolean' } },
}

let evidencePool = []
if (DESIGN_FIRST) {
  // 🎨 design-first 旁路:跳过市场重调研,只留极简证据池(Phase2 仍能引设计稿反推)。
  log('design-first 旁路:跳过 Phase1 全量市场调研。')
} else {
  phase('Research')
  const tasks = buildResearchTasks(KEYWORDS)
  evidencePool = await parallel(tasks.map(t => () => researchWorker(t)))
    .then(rs => rs.map(r => r || { source: '?', evidence: [], stale: false, reason: 'null result' }))
}

// ── Phase 2: Decide + RedTeam(pipeline propose → attack,2 agent 对抗 + 轻量回灌 loop)──
phase('Decide')

function proposeStage(pool, backfillNote) {
  return agent(
    `你是 proposer。吃 Phase1 证据池(${pool.length} 个 source)自决 5 字段,每条附"含具体数据引用"的理由 + 1 句反方风险:
       PRODUCT_FORM / TARGET_MARKET[FROZEN,改=全调研重做] / TARGET_USER / REVENUE_MODEL / TECH_STACK。
     理由硬规则:引 Top50 变现分布 / 差评用户画像 / 技术依赖度;禁"通常这样定""经验上"。
     TARGET_MARKET 从 regions=${JSON.stringify(REGIONS)} 选,模糊则比量级定并写"为什么选这个市场"。
     TECH_STACK 用 app/templates/sections/tech-stack-decision.md:≥2 候选对比矩阵含 AI-可建性 维度,难分标"待 spike 定"。
     ${AVOID ? `本轮约束(上轮已弃,≥2 字段须不同):${AVOID}` : ''}
     ${DESIGN_FIRST ? '🎨 design-first:PRODUCT_FORM/TARGET_USER 从设计稿+用户一句话反推,REVENUE/TARGET_MARKET 照常定。' : ''}
     ${backfillNote || ''}
     证据池=${JSON.stringify(pool).slice(0, 8000)}。返回 5 字段终值 + 各自理由(已含反方风险句)。`,
    { label: 'proposer', phase: 'Decide', schema: {
        type: 'object', required: ['fields'],
        properties: { fields: {
          type: 'object',
          required: ['PRODUCT_FORM', 'TARGET_MARKET', 'TARGET_USER', 'REVENUE_MODEL', 'TECH_STACK'],
          properties: {
            PRODUCT_FORM: FIELD_SCHEMA, TARGET_MARKET: FIELD_SCHEMA, TARGET_USER: FIELD_SCHEMA,
            REVENUE_MODEL: FIELD_SCHEMA, TECH_STACK: FIELD_SCHEMA } } } } }
  ).catch(e => ({ fields: {}, _err: String(e), reason: 'proposer failed' }))
}
const FIELD_SCHEMA = { type: 'object', required: ['value', 'reason'],
  properties: { value: { type: 'string' }, reason: { type: 'string' } } }

function attackStage(proposal, pool) {
  return agent(
    `你是独立 red-team,专职攻击 proposer 的方向(不替它辩护)。proposal=${JSON.stringify(proposal.fields)}。
     强制产出:
       1) ≥3 条反方论据,商业/技术/合规/竞争各角度覆盖,每条带 URL。
       2) ≥1 个已死同品类(app 名 + 死因 + URL)。
       3) 标出 proposer 引用里的 stale-data(2024 前未二次验证的)。
       4) 给每个字段补"可能错在哪"。
       5) 逐字段判 evidence_ok:bool。若某字段证据不足 → needs_more 列该字段名(触发对该字段定向补一轮 Phase1,最多 ${MAX_BACKFILL} 次)。
     证据池=${JSON.stringify(pool).slice(0, 6000)}。`,
    { label: 'red-team', phase: 'Decide', schema: {
        type: 'object', required: ['counter_evidence', 'dead_apps', 'needs_more'],
        properties: {
          counter_evidence: { type: 'array', minItems: 3, items: {
            type: 'object', required: ['angle', 'url', 'point'],
            properties: { angle: { enum: ['business', 'tech', 'compliance', 'competition'] },
              url: { type: 'string' }, point: { type: 'string' } } } },
          dead_apps: { type: 'array', minItems: 1, items: {
            type: 'object', required: ['name', 'cause', 'url'],
            properties: { name: { type: 'string' }, cause: { type: 'string' }, url: { type: 'string' } } } },
          stale_flags: { type: 'array', items: { type: 'string' } },
          field_risks: { type: 'object' },
          needs_more: { type: 'array', items: { type: 'string' } } } } }
  ).catch(e => ({ counter_evidence: [], dead_apps: [], needs_more: [], _err: String(e), reason: 'red-team failed' }))
}

// pipeline:propose → attack;红队判证据不足则对该字段回灌定向 Phase1 补证(轻量 loop,熔断 MAX_BACKFILL)。
let proposal = await proposeStage(evidencePool, '')
let redteam = await attackStage(proposal, evidencePool)
let backfills = 0
while (!DESIGN_FIRST && redteam.needs_more && redteam.needs_more.length && backfills < MAX_BACKFILL) {
  backfills++
  log(`red-team 判证据不足:${redteam.needs_more.join(',')} → 定向补证第 ${backfills} 轮`)
  // 定向补:对 needs_more 字段相关关键词补跑社交+商店 worker,并入证据池。
  const extra = await parallel(redteam.needs_more.map(f => () =>
    agent(
      `定向补证:字段「${f}」证据不足。用 WebSearch/WebFetch + itunes API 针对 keyword=${KEYWORDS[0]} 补这一维度的一手证据(带 URL+year)。
       返回 {source:'backfill-${f}', evidence:[{url,year,quote}], stale:bool}。`,
      { label: `backfill:${f}`, phase: 'Decide', schema: RESEARCH_SCHEMA }
    ).catch(e => ({ source: `backfill-${f}`, evidence: [], stale: false, _err: String(e), reason: 'backfill failed' }))
  ))
  evidencePool = evidencePool.concat(extra)
  proposal = await proposeStage(evidencePool, `定向补证已并入(${redteam.needs_more.join(',')}),请用新证据收口这些字段。`)
  redteam = await attackStage(proposal, evidencePool)
}

// ── Phase 3: Visualize(codex-image-bridge — design-first 旁路整步跳过)──
let visuals = { skipped: DESIGN_FIRST, paths: [] }
if (DESIGN_FIRST) {
  log('design-first 旁路:设计稿即真图,跳过 Phase3 mockup 生成。')
} else {
  phase('Visualize')
  // 默认顺序(按屏 parallel 收益薄);存 docs/mockups/。涉付费再加付费墙屏。
  const wantPaywall = /sub|iap|付费|订阅|内购/i.test(proposal.fields?.REVENUE_MODEL?.value || '')
  const viz = await agent(
    `基于方向 ${JSON.stringify(proposal.fields)},用 codex-image-bridge skill 出 mockup,存 ${ROOT}/docs/mockups/(无则 .claude/state/concept-visuals/<concept>/):
       hero.png(产品定调)/ screen-1-entry.png / screen-2-core.png / screen-3-result.png${wantPaywall ? ' / screen-4-monetize.png(付费墙)' : ''}。
     ≤6 张。codex-image-bridge 不可用 → 退 ASCII/文字线稿(每屏 ≥3 句:布局/主色/关键元素),但优先真图。
     返回生成的文件路径数组。`,
    { label: 'visualize', phase: 'Visualize', schema: {
        type: 'object', required: ['paths'],
        properties: { paths: { type: 'array', items: { type: 'string' } } } } }
  ).catch(e => ({ paths: [], _err: String(e), reason: 'visualize failed' }))
  visuals = { skipped: false, paths: viz.paths || [] }
}

// ── Phase 4: Synthesis + Gate(single agent 收口 — completeness critic,唯一写文件点)──
phase('Synthesis')
const synth = await agent(
  `完整性收口 — 这是整个 workflow 唯一写文件的点(避免并行写冲突)。严禁手写闸门 JSON(key 错位即整关失效)。
   输入:fields=${JSON.stringify(proposal.fields)} ; red-team=${JSON.stringify({ counter_evidence: redteam.counter_evidence, dead_apps: redteam.dead_apps, stale_flags: redteam.stale_flags })} ; evidence_sources=${evidencePool.map(e => e.source).join(',')} ; visuals=${JSON.stringify(visuals)} ; design_first=${DESIGN_FIRST}。
   1) 写 ${ROOT}/docs/spec.md 3 章节:
        ## 产品定位(5 字段终值 + 理由,理由已吸收红队反方风险句;TARGET_MARKET 标 [FROZEN])
        ## 市场调研(5 子节:商店榜单 / 差评样本 / 多源信号 / 已死同品类 / 数据时效;引 counter_evidence + dead_apps)
        ## 概念视觉(mockup 路径 + 每张一句话;design-first 则写"设计稿即真图")
      ⛔ 严禁写 ## 单位经济 / ## 命名锁定 / ## 后端就绪 / ## 合规扫描 / ## 技术 spike(那是 lockdown 的)。
   2) 写 ${ROOT}/docs/discovery-summary.md(≤120 行,5 段:AI 自决方向 / 市场 highlights / 概念视觉路径 / 用户动线 / 决策待答;
      有 discarded-directions.txt 则加"本轮 vs 上轮"对比表)。
   3) 覆盖性核查(critic):5 字段每条有理由?counter_evidence ≥3?dead_apps ≥1?market-research 目录有样本?mockup ≥1(design-first 豁免)?缺则补齐再写。
   4) 用 Bash 跑确定性闸门脚本(key 由脚本产,不手写,对齐 sg_app_* 5 检查项):
        bash ${ROOT}/scripts/app-gate.sh app-gate discover   # → 写 ${ROOT}/.claude/state/clearance-discover.json
      (脚本在本仓 scripts/ 下;若业务项目根另有 scripts/app-gate.sh 优先用项目根的。)
   5) 写 ${ROOT}/.claude/state/skill-signal.json,phase=awaiting-decision:
        echo '{"skill":"discover","epoch":'$(date +%s)',"phase":"awaiting-decision"}' > ${ROOT}/.claude/state/skill-signal.json
   6) 以 "等你: 看 mockup 决策 推进/换方向/暂停" 收尾,⛔ 不准续跑 lockdown。
   返回写入摘要 + gate 结果 + 未达项 gaps[]。`,
  { label: 'critic', phase: 'Synthesis', schema: {
      type: 'object', required: ['spec_written', 'summary_written', 'gate', 'gaps'],
      properties: {
        spec_written: { type: 'boolean' }, summary_written: { type: 'boolean' },
        gate: { type: 'object' }, gaps: { type: 'array', items: { type: 'string' } } } } }
)

return { frame, evidencePool, proposal, redteam, backfills, visuals, synth }
