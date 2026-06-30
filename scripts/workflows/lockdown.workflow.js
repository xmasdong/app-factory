// lockdown.workflow.js — 编排【蓝图参考】:Phase B 锚定(2-touch 的 TOUCH 2 之后 AUTONOMOUS 段)推荐的多 agent 扇出结构
// 本文件性质:它是【蓝图参考】,展示该关推荐的多 agent 扇出结构(扇出哪些子任务、parallel/pipeline、对抗验证什么、loop 到什么条件、各 agent 干啥、产物落哪),不是本项目的可执行脚本。
// 真执行时:用户手动开 ultracode 模式,AI(Claude)用 Claude 内置的【Workflow 工具】参考本蓝图当场组合编排(script 由 AI 现场写,非加载本文件运行)。
//   ⚠️ Workflow 工具归 Claude/ultracode,非本项目定义;本项目不拥有 workflow 运行时,也没有 `claude workflow` 这种命令。
//   ⚠️ ultracode 是用户手动开的会话高级模式;开了之后 AI 才默认倾向用 Workflow 工具编排。skill/脚本本身开不了用户模式。
//   在目标 app 项目根执行,确保 CLAUDE_PROJECT_DIR 指向它。
// 产物(随项目根,沿用 SKILL.md 既定路径,本编排只负责并行调度,真 state 仍由既有脚本/路径产出):
//   spec.md 新增 5 章节(spike / economics / naming-lock / backend-readiness / compliance)
//   .claude/state/spike-results.json + asr-survival-scan.json + naming-candidates.json + naming-check-result.md
//   .claude/state/evidence/*  +  .claude/state/clearance-lockdown.json(由 app-gate.sh 写,勿手写)
//
// 四质量模式归位:
//   fan-out 全覆盖     = phase1 五路锚定 parallel([spike, economics, naming, backend, compliance])
//   pipeline 串数据    = naming 走 pipeline:gen → check(25 次并发查重)→ pick(冲突回 gen,≤3 轮)
//   loop-until-converge= spike 内 FAIL 切备选 retry(≤3);naming 全冲突避词重生成(≤3 轮)
//   adversarial verify = phase2 红队 parallel([econ_red, naming_red, compliance_red]),发现→只回写对应 worker 重跑
//   completeness critic= phase3 单 agent 汇总 inline spec.md + 跑确定性闸门(唯一可信产出口)
//
// 蓝图里用到的编排原语(由 Claude 内置 Workflow 工具提供,非本项目定义):phase(title) / parallel(fns[]) / pipeline(items, ...stages) / agent(prompt,{label,phase,schema}) / log()
// 每个 agent 返回须符合 schema;每个并行 worker 必须 .catch 兜底成合法 fallback,否则一崩全崩。

export const meta = {
  name: 'lockdown-orchestrated',
  title: 'lockdown Phase B 锚定',
  gate: 'lockdown',
  description: '入口校验 → 五路锚定扇出(spike/economics/naming-pipeline/backend/compliance)→ 对抗红队复审 → 汇总 inline spec.md + 跑 app-gate.sh app-gate lockdown 确定性闸门 → 写信号续接 /shape',
  phases: [
    { title: 'Gate-In',      detail: '顺序·不并行 — 校验 INPUT_CONTRACT + 从 spec.md 抽输入写 lockdown-inputs.json' },
    { title: 'Anchor-Fanout', detail: 'parallel × 5 — spike / economics / naming(pipeline) / backend / compliance,各自 .catch 兜底' },
    { title: 'Red-Team',     detail: 'parallel × 3 — 经济/命名/合规红队找漏洞,发现回写对应 worker 重跑(不重跑全部)' },
    { title: 'Synthesis',    detail: 'completeness critic — inline spec.md 5 章节 + app-gate.sh app-gate lockdown(唯一写 clearance)' },
    { title: 'Signal',       detail: '写 skill-signal.json + status.md CURRENT_GATE → A-GATE Shape,续接 /shape' },
  ],
}

const ROOT = process.env.CLAUDE_PROJECT_DIR || process.cwd()
const NAMING_ROUNDS = 3   // naming 避词重生成熔断轮数
const SPIKE_RETRY = 3     // spike 切备选内部 loop 上限

// ============================================================================
// phase 0: 入口校验(顺序,不并行)+ 抽输入
// ============================================================================
phase('Gate-In')
const gateIn = await agent(
  `你是 lockdown 入口校验官。严格按序,不进 phase 1 除非 CONTRACT 满足。
   1) 用 Bash 校验 INPUT_CONTRACT(全满足才继续):
      - test -f ${ROOT}/.claude/state/clearance-discover.json
      - grep -q 'AUTONOMOUS: *true' ${ROOT}/docs/status.md
      - grep -q 'CURRENT_GATE: *A-GATE Lockdown' ${ROOT}/docs/status.md
      任一不满足 → 返回 {ok:false, reason:"<缺哪项 + 提示(缺 clearance-discover → 先跑 /discover;AUTONOMOUS 未 true → 提示用户回'推进')>"},
      不要做任何写操作。
   2) 满足则从 ${ROOT}/docs/spec.md 抽取(供下游 worker 读,别让它们各自再解析 spec):
      - 概念视觉 mockup 的关键交互(喂 spike)
      - 产品定位 PRODUCT_FORM / TARGET_USER / TARGET_MARKET(喂命名)
      写 ${ROOT}/.claude/state/lockdown-inputs.json:
        {"key_interactions":[...], "PRODUCT_FORM":"", "TARGET_USER":"", "TARGET_MARKET":""}
      返回 {ok:true, key_interactions_count:N}`,
  { label: 'gate-in', phase: 'Gate-In', schema: {
      type: 'object', required: ['ok'],
      properties: { ok: { type: 'boolean' }, reason: { type: 'string' }, key_interactions_count: { type: 'integer' } } } }
).catch(e => ({ ok: false, reason: 'gate-in error: ' + String(e) }))

if (!gateIn.ok) {
  log('lockdown CONTRACT 不满足,中止:' + (gateIn.reason || '未知'))
  return { aborted: true, reason: gateIn.reason }
}

// ============================================================================
// phase 1: parallel 五路锚定扇出(核心并行段)
// 每路 .catch 兜底 → {result:'deferred', reason},不拖垮其它路。
// ============================================================================
phase('Anchor-Fanout')

// ── w_spike ──(交互内 FAIL→切备选 retry,loop ≤3)
const w_spike = (async () => agent(
  `读 ${ROOT}/.claude/state/lockdown-inputs.json 的 key_interactions。
   每个关键交互写 1 条【双语】spike(≥3 条总):工程视角验证步骤(代码/命令/预期输出)+ 用户视角成功信号(含可量化指标)+ 失败信号 + 回退方案。
   逐条【实际跑】。FAIL → 切回退方案 retry,内部 loop ≤${SPIKE_RETRY},3 次仍 FAIL 标 fallback_taken。
   产物:写 ${ROOT}/.claude/state/spike-results.json(schema:{spikes:[{id,result,evidence,fallback_taken}]})+ 每条 evidence 落 ${ROOT}/.claude/state/evidence/spike-*.txt。
   同时把双语 4 字段 markdown 落 ${ROOT}/.claude/state/economics.md 同级的 spike 草稿片段(供 phase3 inline)。`,
  { label: 'spike', phase: 'Anchor-Fanout', schema: {
      type: 'object', required: ['spikes'],
      properties: { spikes: { type: 'array', items: { type: 'object',
        properties: { id: { type: 'string' }, result: { enum: ['PASS', 'FAIL'] },
          evidence: { type: 'string' }, fallback_taken: { type: 'string' } } } } } } }
))().catch(e => ({ result: 'deferred', reason: 'spike: ' + String(e), spikes: [] }))

// ── w_economics ──(真数字 + 单调递减阶梯 + 反薅 ≥5)
const w_economics = (async () => agent(
  `锚定单位经济。硬规则:禁"约/可能/待估/TBD"模糊词(机械检查 sg_app_economics_real 会卡)。
   1) 单次成本表:每操作给真数字(USD)。
   2) 价格阶梯:Free→Tier1→Tier2,均价/单位单调递减。
   3) 反薅漏洞清单 ≥5 条,每条 = 具体漏洞 + 防护。
   产物:写 spec.md 草稿片段 ${ROOT}/.claude/state/economics.md(phase3 合并入 spec.md ## 单位经济)。`,
  { label: 'economics', phase: 'Anchor-Fanout', schema: {
      type: 'object', required: ['cost_table', 'price_tiers', 'abuse_list'],
      properties: { cost_table: { type: 'array' }, price_tiers: { type: 'array' },
        abuse_list: { type: 'array', minItems: 5, items: { type: 'string' } } } } }
))().catch(e => ({ result: 'deferred', reason: 'economics: ' + String(e) }))

// ── w_naming ──(pipeline: gen → check(25 并发查重)→ pick;全冲突回 gen,≤3 轮)
const w_naming = (async () => pipeline(
  Array.from({ length: NAMING_ROUNDS }, (_, i) => i + 1),  // 轮次驱动 fuse
  // stage1 gen
  async (round) => {
    const gen = await agent(
      `第 ${round} 轮命名生成。读 ${ROOT}/.claude/state/lockdown-inputs.json 的 PRODUCT_FORM/TARGET_USER/TARGET_MARKET。
       生成 ≥5 候选(≤12 字符·易拼·易记·不数字开头·不连字符;海外纯英文/国内中英双向顺),列 name+meaning+fit(1-10)。
       ${round > 1 ? '⚠️ 避开上轮已冲突的候选词根,换新方向。' : ''}
       写 ${ROOT}/.claude/state/naming-candidates.json {candidates:[{name,meaning,fit}]}。返回 names[]。`,
      { label: `naming:gen#${round}`, phase: 'Anchor-Fanout', schema: {
          type: 'object', required: ['names'], properties: { names: { type: 'array', items: { type: 'string' } } } } }
    )
    return { round, names: gen.names || [] }
  },
  // stage2 check — Bash for 循环并发跑 5候选×5源 = 25 次查重(curl 后台 + wait)
  async ({ round, names }) => {
    await agent(
      `对 ${ROOT}/.claude/state/naming-candidates.json 每候选并发跑 5 源查重(itunes / play / rdap 域名 / npm / github)。
       用一个 Bash for 循环把 curl 丢后台(&)再 wait,压时间(这是 IO 密集点)。
       每候选证据落 ${ROOT}/.claude/state/evidence/naming-check-<name>/{appstore.json,play-*,domain-*.txt,npm.txt,github.json}。
       (play 无 API → 用 scraper/Playwright 抓搜索页存证据,抓不到标 honor-check。)返回 checked names[]。`,
      { label: `naming:check#${round}`, phase: 'Anchor-Fanout', schema: {
          type: 'object', required: ['checked'], properties: { checked: { type: 'array', items: { type: 'string' } } } } }
    )
    return { round, names }
  },
  // stage3 pick — 解析,选全 5 项干净 + fit 最高;全冲突 → 抛出触发下一轮(pipeline 重入 gen)
  async ({ round, names }) => {
    const pick = await agent(
      `解析 ${ROOT}/.claude/state/evidence/naming-check-* 证据,生成查重矩阵写 ${ROOT}/.claude/state/naming-check-result.md。
       选【全 5 项干净 + fit 最高】的一个为最终名。
       选定后对其 finalize 6 项 evidence(brand/domain/appstore/play/bundle/iap)落 ${ROOT}/.claude/state/evidence/<项>-<name>.*(每文件 ≥10 字节,禁含"待跑/TODO/TBD/PROPOSED/待填")。
       写 spec.md 草稿片段供 phase3 inline 入 ## 命名锁定 (NAMING-LOCK)。
       若【全部候选都有冲突】→ 返回 {picked:null} 不要选(由编排回 gen 重生成)。返回 {picked:"<name>"|null}。`,
      { label: `naming:pick#${round}`, phase: 'Anchor-Fanout', schema: {
          type: 'object', required: ['picked'], properties: { picked: { type: ['string', 'null'] } } } }
    )
    if (!pick.picked) {
      if (round >= NAMING_ROUNDS) {
        // 3 轮 fuse → 软熔断,返回 deferred 不抛(交给 phase3 / status.md 标记)
        return { result: 'deferred', reason: 'naming: 3 轮全冲突,fuse 软熔断,等用户介入', picked: null }
      }
      throw new Error(`naming round ${round} 全冲突 → 回 gen 重生成`)  // pipeline 捕获 → 下一轮
    }
    return { picked: pick.picked }
  },
  { retries: NAMING_ROUNDS }  // pipeline 内置 loop-until:抛出则带下一轮入参重入(≤3)
))().catch(e => ({ result: 'deferred', reason: 'naming: ' + String(e), picked: null }))

// ── w_backend ──(每项具体值或显式 deferred,禁待注册/TODO;默认 Supabase + 声明式 RLS)
const w_backend = (async () => agent(
  `锚定后端就绪。每项给【具体值】或【显式 deferred:<理由+预计日期>】,禁"待注册/待跑/TODO"。
   项:用户体系 / 鉴权(auth)/ 推送(APNs key ID + FCM project number)/ 支付(RevenueCat entitlement 或 Stripe secret env 名)/
       删号接口(具体 API path,Apple 5.1.1(v))/ 演示账号(email+password)/ 域名+SSL / 监控。
   默认后端选型 = Supabase + 声明式 RLS(把"越权"这个头号幻觉区变可审计 SQL)——backend-readiness.md 写一行【后端选型决策】。
   产物:写 spec.md 草稿片段 ${ROOT}/.claude/state/backend-readiness.md(phase3 inline 入 ## 后端就绪)。`,
  { label: 'backend', phase: 'Anchor-Fanout', schema: {
      type: 'object', required: ['user_system', 'auth', 'push', 'payment', 'delete_api', 'demo_acct', 'domain', 'monitor'],
      properties: {
        user_system: { type: 'string' }, auth: { type: 'string' }, push: { type: 'string' },
        payment: { type: 'string' }, delete_api: { type: 'string' }, demo_acct: { type: 'string' },
        domain: { type: 'string' }, monitor: { type: 'string' } } } }
))().catch(e => ({ result: 'deferred', reason: 'backend: ' + String(e) }))

// ── w_compliance ──(调 app-store-review-survival skill 扫 8 项;result 必须 PASS)
const w_compliance = (async () => agent(
  `锚定合规。调 app-store-review-survival skill(或按其清单手扫)扫 8 项:
   隐私政策 URL(live 可访问)/ EULA(订阅必填)/ 删号 path(5.1.1(v))/ GDPR consent+EU 跳转 /
   ATT 文案(NSUserTrackingUsageDescription)/ Kids·COPPA 分类 / 网络授权时机(隐私同意后)/ 权限文案中英双语(NSCameraUsageDescription 等)。
   产物:写 ${ROOT}/.claude/state/asr-survival-scan.json {result:"PASS"|"FAIL", checks:{<8 项>}}(result 必须 PASS 才放行)。`,
  { label: 'compliance', phase: 'Anchor-Fanout', schema: {
      type: 'object', required: ['result', 'checks'],
      properties: { result: { enum: ['PASS', 'FAIL'] }, checks: { type: 'object' } } } }
))().catch(e => ({ result: 'deferred', reason: 'compliance: ' + String(e), checks: {} }))

const [spike, economics, naming, backend, compliance] =
  await parallel([() => w_spike, () => w_economics, () => w_naming, () => w_backend, () => w_compliance])

// ============================================================================
// phase 2: 对抗复审(parallel,推荐;喂 ultracode)
// 红队各自啃一项 phase1 产物找漏洞,发现 → 只回写对应 worker 重跑该项(不重跑全部)。
// ============================================================================
phase('Red-Team')
const reds = await parallel([
  // 经济红队:验"反薅是否真堵死"
  () => agent(
    `经济红队。读 ${ROOT}/.claude/state/economics.md。逐条审反薅漏洞:是否真堵死?有无遗漏的薅羊毛路径(多账号/退款/试用循环/共享)?成本数字是否仍含模糊词?
     发现缺陷 → 用 Bash 回写并指示重跑 economics 节(只补这一节,不动其它)。返回 {ok, gaps:[...]}。`,
    { label: 'red:econ', phase: 'Red-Team', schema: {
        type: 'object', required: ['ok'], properties: { ok: { type: 'boolean' }, gaps: { type: 'array', items: { type: 'string' } } } } }
  ).catch(e => ({ ok: true, gaps: ['red:econ skipped: ' + String(e)] })),
  // 命名红队:验"是否漏查商标/近似名"
  () => agent(
    `命名红队。读 ${ROOT}/.claude/state/naming-check-result.md + 选定名 evidence。验:有无漏查商标(USPTO/国内)/ 近似名 / 同类目同名?5 项 evidence 文件是否真存在 ≥10 字节且无占位字样?
     发现缺陷 → 补查重 / 触发命名 pipeline 重选。返回 {ok, gaps:[...]}。`,
    { label: 'red:naming', phase: 'Red-Team', schema: {
        type: 'object', required: ['ok'], properties: { ok: { type: 'boolean' }, gaps: { type: 'array', items: { type: 'string' } } } } }
  ).catch(e => ({ ok: true, gaps: ['red:naming skipped: ' + String(e)] })),
  // 合规红队:复核 8 项无侥幸 PASS
  () => agent(
    `合规红队。读 ${ROOT}/.claude/state/asr-survival-scan.json。复核 8 项每项是否有真依据,排查侥幸 PASS(尤其删号 path / ATT 文案 / 权限中英 / 网络授权时机)。
     发现侥幸 → 把对应 check 翻 FAIL 并指示重跑 compliance 节。返回 {ok, gaps:[...]}。`,
    { label: 'red:compliance', phase: 'Red-Team', schema: {
        type: 'object', required: ['ok'], properties: { ok: { type: 'boolean' }, gaps: { type: 'array', items: { type: 'string' } } } } }
  ).catch(e => ({ ok: true, gaps: ['red:compliance skipped: ' + String(e)] })),
])

// ============================================================================
// phase 3: pipeline 汇总 + 机械验收(顺序,必须串行)
// completeness critic:inline spec.md 5 章节 + 跑确定性闸门(唯一写 clearance 的口)。
// ============================================================================
phase('Synthesis')
const synth = await agent(
  `完整性审查 + 跑【确定性闸门】产出 clearance(唯一可信产出口,严禁手写 clearance JSON——和闸门 key 错位即整关失效)。
   输入摘要:spike=${JSON.stringify(spike).slice(0, 400)} ; economics=${JSON.stringify(economics).slice(0, 200)} ;
            naming=${JSON.stringify(naming).slice(0, 200)} ; backend=${JSON.stringify(backend).slice(0, 200)} ;
            compliance=${JSON.stringify(compliance).slice(0, 200)} ; red_team_gaps=${JSON.stringify(reds).slice(0, 400)}。
   1) 用 Bash 把 5 路草稿片段 inline 进 ${ROOT}/docs/spec.md 的 5 章节:
      ## 技术 spike(双语)/ ## 单位经济 (ECONOMICS) / ## 命名锁定 (NAMING-LOCK) / ## 后端就绪 (BACKEND-READINESS) / ## 合规扫描 (COMPLIANCE)
      源:.claude/state/economics.md / backend-readiness.md / naming-check-result.md 与已落盘 spike/asr JSON。
   2) 跑确定性闸门(勿改其 key,直接接现有脚本):
        bash ${ROOT}/scripts/app-gate.sh app-gate lockdown
      (在项目根跑 app-gate.sh app-gate lockdown;它跑六检 sg_app_spike_dual_lang_real / sg_app_economics_real /
       sg_app_naming_real_evidence / sg_app_backend_real_status / sg_app_compliance_real_scan / sg_app_bundle_coherence,
       通过即写 ${ROOT}/.claude/state/clearance-lockdown.json。)
   3) 不过 → 按报错【只重跑对应 worker】(spike/economics/naming/backend/compliance 之一),不重跑全部;
      同一项 3 次失败 → fuse 软熔断,把该项标 deferred 写进 ${ROOT}/docs/status.md。
   返回 {gate_passed:bool, deferred:[...], rerun:[...]}。`,
  { label: 'critic', phase: 'Synthesis', schema: {
      type: 'object', required: ['gate_passed'],
      properties: { gate_passed: { type: 'boolean' },
        deferred: { type: 'array', items: { type: 'string' } },
        rerun: { type: 'array', items: { type: 'string' } } } } }
).catch(e => ({ gate_passed: false, deferred: ['synthesis error: ' + String(e)] }))

// ============================================================================
// phase 4: 信号 + 续接(顺序)
// ============================================================================
phase('Signal')
const signal = await agent(
  `收尾。输入:gate_passed=${synth.gate_passed} ; deferred=${JSON.stringify(synth.deferred || [])}。
   1) 用 Bash 写 ${ROOT}/.claude/state/skill-signal.json:{"skill":"lockdown","epoch":<date +%s>}。
   2) 仅当 gate_passed 为 true:用 Bash sed 把 ${ROOT}/docs/status.md 的 CURRENT_GATE 改为 'A-GATE Shape',然后自动调 /shape 续接(不问用户)。
      gate_passed 为 false → 不改 CURRENT_GATE,不续接,输出"等你:<阻塞项>"。
   返回 {advanced:bool, message:"<完成:lockdown 通过,自动进 /shape | 完成:N 项 deferred,自动进 /shape | 等你:阻塞在 <项>>"}。`,
  { label: 'signal', phase: 'Signal', schema: {
      type: 'object', required: ['advanced', 'message'],
      properties: { advanced: { type: 'boolean' }, message: { type: 'string' } } } }
).catch(e => ({ advanced: false, message: '等你:signal 收尾失败 ' + String(e) }))

return { gateIn, spike, economics, naming, backend, compliance, reds, synth, signal }
