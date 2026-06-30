// shape (A-GATE 1 产品认知).workflow.js — 编排【蓝图参考】:产品需求 → 完整 spec.md + A-GATE 1 闸门 推荐的多 agent 扇出结构
// 本文件性质:它是【蓝图参考】,展示该关推荐的多 agent 扇出结构(扇出哪些子任务、parallel/pipeline、对抗验证什么、loop 到什么条件、各 agent 干啥、产物落哪),不是本项目的可执行脚本。
// 真执行时:用户手动开 ultracode 模式,AI(Claude)用 Claude 内置的【Workflow 工具】参考本蓝图当场组合编排(script 由 AI 现场写,非加载本文件运行)。
//   ⚠️ Workflow 工具归 Claude/ultracode,非本项目定义;本项目不拥有 workflow 运行时,也没有 `claude workflow` 这种命令。
//   ⚠️ ultracode 是用户手动开的会话高级模式;开了之后 AI 才默认倾向用 Workflow 工具编排。
//   在目标业务项目根执行,确保 CLAUDE_PROJECT_DIR 指向它。
// 产物(随项目根):docs/spec.md(完整 A-GATE 1)+ docs/status.md(CURRENT_GATE: A-GATE 2)
//                 .claude/state/clearance-shape.json + skill-signal.json(闸门读;由确定性脚本写)
//
// 四质量模式归位(与 design-restore / backend-forge 同契约):
//   fan-out 全覆盖     = phase('Challenge') parallel(5 PRD 视角 + PLATFORM-MATRIX),不抽样
//   pipeline 串依赖    = Cognition → Challenge → Fault(吃 Challenge.gaps)→ Contract → Tasks 顺序串
//   adversarial verify = phase('Review') parallel × 4 角色(每角色只质疑本类,互不污染上下文)
//   completeness critic= phase('Synthesis') 单 agent 核覆盖 + 用确定性脚本写 state(唯一可信产出口)
//
// 接现有闸门 state:Synthesis 是【唯一写 state 的点】。worker 只产『发现 JSON』;
//   确定性闸门由 scripts/app-gate.sh 机械产出(严格复用现有 key sg_app_* / clearance-shape.json,
//   不新增 key、不改 app-gate.sh)。与 design-restore.workflow.js 第 82-88 行同一契约:
//   agent 产料 → Bash 跑确定性脚本产 state。
//
// 蓝图里用到的编排原语(由 Claude 内置 Workflow 工具提供,非本项目定义):phase(title) / parallel(fns[]) / agent(prompt,{label,phase,schema}) / log()
// 每个 agent 返回须符合 schema;每个并行 worker 必须 .catch 兜底成合法 fallback,否则一崩全崩。

export const meta = {
  name: 'shape-a-gate-1-orchestrated',
  description: '产品认知扇出:全局认知(FROZEN 输入)→ PRD 挑战 5 视角 + PLATFORM-MATRIX 并行 → 故障想象力吃挑战产出 → 数据契约 → 拆任务 → 4 角色对抗审查并行 → completeness critic 跑 app-gate.sh shape 产 clearance-shape.json',
  phases: [
    { title: 'Cognition', detail: 'single agent — 全局认知(产品定义/用户故事/不做清单/视觉方向 via frontend-design)+ 枚举 features[],扇出前唯一 FROZEN 输入' },
    { title: 'Challenge', detail: 'parallel × (5 PRD 视角 + PLATFORM-MATRIX) — 每视角逐功能列 gaps[](fan-out 全覆盖)' },
    { title: 'Fault',     detail: 'single agent — 故障想象力,吃 Challenge.gaps(SKILL §91:PRD 挑战产出直接喂故障想象力)' },
    { title: 'Contract',  detail: 'single agent — 数据契约逐字段对账 + 多端消费方 + 端侧独有字段(种子=manifest.fields + openapi)' },
    { title: 'Tasks',     detail: 'single agent — TASK-TEMPLATE 拆任务含 PLATFORM 字段 + Step2.5 反扫 + [CRITICAL] 排前 + 覆盖契约' },
    { title: 'Review',    detail: 'parallel × 4 角色(需求/证据/范围/多端体验)— 对抗审查,每角色只质疑本类(adversarial verify)' },
    { title: 'Synthesis', detail: 'completeness critic — 汇编写完整 spec.md + 前置人工动作反扫 + 跑 app-gate.sh shape 产 clearance-shape.json(唯一写 state 口)' },
  ],
}

const ROOT = process.env.CLAUDE_PROJECT_DIR || process.cwd()

// PRD 挑战 5 视角(SKILL Step1.5):每视角绑定一个结构化探查角度,并行独立深挖互不污染。
const PRD_VIEWS = [
  { key: 'state',     name: '状态完整性',   probe: '列每个业务实体的所有状态 + 所有合法状态转换;PRD 未定义的转换 = 缺口(例:满员后取消→回上线还是保持满员?)' },
  { key: 'boundary',  name: '边界条件',     probe: '每个数值/集合/时间的 0 时 / 1 时 / 上限 / 超限行为;PRD 未定义的边界 = 缺口(例:0 人报名列表页显示什么?)' },
  { key: 'multirole', name: '多角色一致性', probe: '每个写操作:其他角色实时/延迟看到什么;PRD 未定义的跨角色行为 = 缺口(例:组织者改时间→已报名用户看旧还是新?)' },
  { key: 'timing',    name: '时序敏感',     probe: '每个多步流程:每一步超时/中断/重试的行为;PRD 未定义的中断恢复 = 缺口(例:报名超时重试→会不会两条记录?)' },
  { key: 'lifecycle', name: '数据生命周期', probe: '每个数据实体:何时创建/修改/软删/硬删/归档,谁有权操作;PRD 未定义的生命周期 = 缺口(例:活动结束后报名记录留多久?)' },
]

// ── 前置(串行,扇出前必须成立)──
// INPUT_CONTRACT 校验 + 读 docs/lessons.md。Step1.0 design-restore / Step1.85 backend-forge 作为前置
// 子编排(可由 SKILL 顺序先调那两份 .workflow.js,或在此 phase 0 单 agent 串行确认其产物已落盘)。
phase('Precheck')
const pre = await agent(
  `A-GATE 1 前置校验(不满足任一 → throw 终止,不静默放行)+ 读历史教训。在 ${ROOT} 下用 Bash 机械核查:
   1) 读 ${ROOT}/docs/lessons.md(历史教训,无文件则记 lessons_present=false 继续)。
   2) INPUT_CONTRACT 硬闸:
      - ${ROOT}/.claude/state/clearance-lockdown.json 存在(Lockdown 已过);若不存在 → throw "Lockdown 未过,先跑 /lockdown"。
      - docs/spec.md 已有 5 子节(命名锁定/单位经济/技术 spike/后端就绪/合规扫描)且各子节 locked;缺 → throw "spec.md 5 子节未锁,先跑 /lockdown"。
      - docs/status.md 顶部 PROJECT_TYPE: app;非 app → throw "PROJECT_TYPE≠app,走 generic 主线"。
      - docs/status.md 顶部 CURRENT_GATE: A-GATE 1;不符 → throw "CURRENT_GATE≠A-GATE 1,走对应 gate"。
   3) 前置子编排核查(只确认产物,不在此重跑):design-restore 产物 docs/design/design-manifest.json + tokens.json 是否已落盘;
      backend-forge 产物 api/openapi.yaml 是否已落盘。缺则记 degraded 并在返回里点名(不 throw:数据契约阶段可降级用 spec 文字种子)。
   返回前置体检结果。`,
  { label: 'precheck', phase: 'Precheck', schema: {
      type: 'object', required: ['contract_ok'],
      properties: {
        contract_ok: { type: 'boolean' },
        lessons_present: { type: 'boolean' },
        manifest_present: { type: 'boolean' },
        openapi_present: { type: 'boolean' },
        notes: { type: 'array', items: { type: 'string' } } } } }
)
if (!pre.contract_ok) throw new Error('INPUT_CONTRACT 不满足,A-GATE 1 终止;见 precheck.notes')

// ── phase 1: 全局认知(扇出的唯一输入,FROZEN)──
phase('Cognition')
const cognition = await agent(
  `产出「全局认知」——后面所有并行 worker 的共享 FROZEN 输入(本 phase 后不再改)。在 ${ROOT}:
   1) 产品定义 / 用户故事(每条 Given-When-Then 可断言)/ 不做清单(显式 scope-out)。
   2) 视觉方向:调 frontend-design skill 定【设计系统】(配色/排版/组件基调/避 AI 通用脸);
      若已有 docs/design/design-manifest.json(manifest_present=${pre.manifest_present}),改为「读 manifest 体检补缺」而非凭空造。
   3) 枚举【核心功能清单 features[]】——这是 Challenge phase 5 视角 × 每功能逐一探查的对象,必须穷尽核心功能,别漏。
   4) 草稿:把全局认知章节写入 ${ROOT}/docs/spec.md「全局认知」段(产品定义/用户故事/不做清单/视觉方向)。
   返回 features[] + user_stories[] + visual_direction。`,
  { label: 'cognition', phase: 'Cognition', schema: {
      type: 'object', required: ['features', 'user_stories', 'visual_direction'],
      properties: {
        features: { type: 'array', items: { type: 'string' } },
        user_stories: { type: 'array', items: { type: 'object' } },
        visual_direction: { type: 'object' } } } }
)
const FEATURES = cognition.features || []

// ── phase 2: PRD 挑战 5 视角 + PLATFORM-MATRIX 并行扇出(核心扇出 #1)──(fan-out 全覆盖)
// 每视角独立深挖、互不污染上下文(避免 5 视角写成「同上」套话)。
phase('Challenge')
const challengeWorkers = PRD_VIEWS.map(view => async () => {
  const out = await agent(
    `PRD 挑战 · 视角=【${view.name}】。对【全部核心功能】逐一从本视角探查(features=${JSON.stringify(FEATURES)})。
     探查角度(只用本视角,不越权写别的视角):${view.probe}
     spec 不是翻译 PRD 而是挑战 PRD:缺口不在已写内容里,在作者没想到的维度。
     每个缺口必须有处置(三选一):补入spec(默认,立即补具体定义+对应 ACCEPT 或新 TASK)/ deferred(给理由)/ 不适用(给理由)。
     默认补入(AI 结构化视角发现的缺口往往是人没想到的,等人确认只多一次往返,用户终审不认可再删)。
     返回 gaps[]{编号, 功能, 缺口描述, 处置, 承接}(承接=ACCEPT 编号或新 TASK 描述)。`,
    { label: `prd:${view.key}`, phase: 'Challenge', schema: {
        type: 'object', required: ['view', 'gaps'],
        properties: {
          view: { type: 'string' },
          gaps: { type: 'array', items: {
            type: 'object', required: ['编号', '功能', '缺口描述', '处置'],
            properties: {
              '编号': { type: 'string' }, '功能': { type: 'string' },
              '缺口描述': { type: 'string' },
              '处置': { enum: ['补入spec', 'deferred', '不适用'] },
              '承接': { type: 'string' } } } } } } }
  ).catch(e => ({ view: view.name, gaps: [], _err: String(e) }))
  return out
})
// PLATFORM-MATRIX worker 与 5 视角并行(无相互依赖)。
const platformWorker = async () => agent(
  `填【多端能力矩阵 PLATFORM-MATRIX】(SKILL Step1.7,app 特有)。在 ${ROOT}:
   先 \`cat "$AI_RULES_ROOT/app/templates/sections/platform-matrix.md" >> docs/spec.md\`(无模板则手写等价表)。
   填 8 行能力维度 × 各端,逐行:① 各端支持/fallback ② 不支持的端 ③ 跨端一致性 FROZEN。
   8 维度:抠图/人脸/AR/视觉算子 · 推送即时下发 · 支付/订阅 · 文件/相册/相机 · 网络(HTTP/WS/QUIC) · 后台任务/唤醒 · 推送点击/Deep Link · 收款资质/主体。
   硬规则(sg_app_platform_matrix):≥8 行 + 每行 fallback 非空且【不含一刀切语】(禁"降级到 server-side"笼统)+ "不支持的端"章节显式存在(即使写"无")+ 跨端一致性 FROZEN 子章节存在。
   fallback 必须具体(✅"iOS17- Vision Foundation / iOS18+ ImageAnalysisInteraction" / "设备不支持→server-side onnx +$0.001 +300ms")。
   写入 ${ROOT}/docs/spec.md「多端能力矩阵」章节。返回 rows(行数)+ unsupported_explicit + frozen_consistency_present。`,
  { label: 'platform-matrix', phase: 'Challenge', schema: {
      type: 'object', required: ['rows'],
      properties: {
        rows: { type: 'integer' },
        unsupported_explicit: { type: 'boolean' },
        frozen_consistency_present: { type: 'boolean' } } } }
).catch(e => ({ rows: 0, unsupported_explicit: false, frozen_consistency_present: false, _err: String(e) }))

const challengeResults = await parallel([...challengeWorkers, platformWorker]
  .map(fn => () => fn().catch(() => ({ view: '?', gaps: [] }))))
const prdViews = challengeResults.filter(r => Array.isArray(r.gaps))
const platformMatrix = challengeResults.find(r => 'rows' in r) || { rows: 0 }
const allGaps = prdViews.flatMap(v => (v.gaps || []).map(g => ({ ...g, view: v.view })))

// ── phase 3: 故障想象力(吃 Challenge.gaps;因有依赖,单独成 phase 串在 Challenge 之后)──(pipeline 串依赖)
// SKILL §91 明文:PRD 挑战的产出直接喂给故障想象力。
phase('Fault')
const fault = await agent(
  `故障想象力(SKILL Step1.6)。输入 = PRD 挑战汇总 gaps(${JSON.stringify(allGaps)})。
   PRD 挑战找"PRD 没定义什么",故障想象力找"这玩意炸了用户会看到什么"。逐缺口转故障:
     每个状态转换→"转换失败会怎样?" / 每个边界→"越界用户看到什么?" / 每个跨角色→"不一致谁看到错误?" / 每个时序→"中断重试会怎样?"
   补充技术维度三元组:主体(用户操作/网络/数据库/第三方/并发/缓存/权限)× 时机(操作前/中/后/跨操作)× 表现(数据丢失/错乱/静默失败/卡死/重复执行)。
   格式 = "如果生产上炸了,新闻标题会怎么写":每条须有主语(哪种用户)+ 具体动作 + 看到的具体画面;
     ❌"空指针异常" ✅"未登录用户看到所有活动都显示已报名";禁"同上"/"通用错误处理"套话。
   对账(强制,不对账=未完成):每条对照 spec 查是否被某 ACCEPT 防住——
     防住→标 \`防 故障#N\`(每编号独立写不可简写)/ 未防→立即补 ACCEPT 或新 TASK(用户明说"不用防"才 deferred)。
   多端反扫:每条是否多端适用?多端故障 = 单端 × N,不可只为 iOS 写 ACCEPT(例:小程序 storage 限制 + 跳转产生独有故障)。
   写入 ${ROOT}/docs/spec.md「故障想象力」章节。返回 disasters[]{主语动作画面, 维度三元组, 对账}。`,
  { label: 'fault', phase: 'Fault', schema: {
      type: 'object', required: ['disasters'],
      properties: {
        disasters: { type: 'array', items: {
          type: 'object', required: ['主语动作画面', '维度三元组', '对账'],
          properties: {
            '主语动作画面': { type: 'string' },
            '维度三元组': { type: 'string' },
            '对账': { type: 'string' } } } } } } }
).catch(e => ({ disasters: [], _err: String(e) }))

// ── phase 4: 数据契约(串行 — 逐字段虽可并行但量小且需统一成一张表,串行更省协调成本)──
phase('Contract')
const contract = await agent(
  `数据契约(SKILL Step1.8)。种子 = design-restore 的 manifest.screens[].fields(${ROOT}/docs/design/design-manifest.json,present=${pre.manifest_present})
   + backend-forge 的 ${ROOT}/api/openapi.yaml(present=${pre.openapi_present});缺则降级用 spec 文字推断并点名。
   高风险字段逐字段对账(金额=单位分/元 · 时间=Unix秒/毫秒/ISO8601 · 状态枚举=列全合法值 · ID=int64/string/uuid)。
   契约表【消费方列必须含端区分】(强制):| 字段 | 类型 | 单位/格式 | 生产者 | 消费方(按端 iOS/Android/小程序/后台)|。
   端侧独有字段子章节(### 端侧独有字段):| 字段 | 仅存在于 | 用途 | 同步到后端? |(即使空也写"无端侧独有字段")。
   FROZEN by default:变更=回 A-GATE 0 重算多端影响 + 回本 skill 重 spec,不在 /build 默改。
   硬规则(sg_app_data_contract):## 数据契约 章节存在 + 契约表数据行 ≥2 + 消费方命中 ≥2 端 + ### 端侧独有字段 子章节存在。
   写入 ${ROOT}/docs/spec.md「数据契约」章节。返回 fields(对账字段数)+ consumer_platforms(命中端数)+ platform_specific_section(子章节存在)。`,
  { label: 'contract', phase: 'Contract', schema: {
      type: 'object', required: ['fields', 'consumer_platforms', 'platform_specific_section'],
      properties: {
        fields: { type: 'integer' },
        consumer_platforms: { type: 'integer' },
        platform_specific_section: { type: 'boolean' } } } }
).catch(e => ({ fields: 0, consumer_platforms: 0, platform_specific_section: false, _err: String(e) }))

// ── phase 5: 拆任务(串行 — 单一任务清单文档不可并发写)──
phase('Tasks')
const tasks = await agent(
  `拆任务(SKILL Step2 + 2.5 + 1.9 + 1.10)。输入 = features=${JSON.stringify(FEATURES)} + gaps + disasters 承接的 ACCEPT/TASK。在 ${ROOT}:
   1) 每 TASK 块按 TASK-TEMPLATE,必须含字段:TASK/ACCEPT/SOURCE/FILES/IMPACT/SMOKE/BOUNDARY/COVERAGE/HUMAN/DEP/【PLATFORM】。
      PLATFORM 合法值:iOS/Android/Backend/Web/鸿蒙/小程序(单端)| All(跨端不可拆,慎用,BOUNDARY 说明为何不拆)| None(文档/配置)。
   2) Step2.5 PLATFORM 反扫(逐 TASK):FILES 含 ios//*.swift→PLATFORM 含 iOS;android//*.kt/build.gradle→Android;server//backend//api/→Backend;
      多端路径→All 且 BOUNDARY 说明;PLATFORM 必须在 PLATFORM-MATRIX 实际支持端内;不一致→阻塞修正。
   3) [CRITICAL] 模块识别(命中任一:≥3 模块协作 / 并发一致性 / 方案≥2 trade-off / 高扇出≥3 依赖 / 调试密集 / 领域复杂):
      必须有方案简述(≥2 方案表 + 选择理由 + 验证策略)+ 排在任务清单【前段】+ 第一个任务是方案验证(最小实验)+ HUMAN 默认阻塞。无则显式写"无核心难点"。
   4) 覆盖契约(## 覆盖契约 FROZEN):### 核心链路(本 release 必须 E2E)+ ### 显式不覆盖的链路(走 SMOKE)。新增链路=改契约=回本 skill。
   硬规则:sg_app_task_platform_field(每 TASK 含 PLATFORM 且与 FILES 一致)+ sg_app_coverage_contract(核心+不覆盖+FROZEN)。
   写入 ${ROOT}/docs/spec.md「任务清单」+「核心难点」+「覆盖契约」章节。返回 task_count + platform_field_count + critical_count + coverage_present。`,
  { label: 'tasks', phase: 'Tasks', schema: {
      type: 'object', required: ['task_count', 'platform_field_count'],
      properties: {
        task_count: { type: 'integer' },
        platform_field_count: { type: 'integer' },
        critical_count: { type: 'integer' },
        coverage_present: { type: 'boolean' } } } }
).catch(e => ({ task_count: 0, platform_field_count: 0, critical_count: 0, coverage_present: false, _err: String(e) }))

// ── phase 6: 对抗审查 4 角色并行(核心扇出 #2:每角色只质疑本类,互不污染避免越权妥协)──(adversarial verify)
phase('Review')
const REVIEW_ROLES = [
  { key: 'requirement', name: '需求审查员',       scope: '用户故事完整性 / 验收标准可测 / 业务规则一致' },
  { key: 'evidence',    name: '证据审查员',       scope: 'ACCEPT 数值来源 / SOURCE 字段引用真实 / fixture 路径存在' },
  { key: 'scope',       name: '范围审查员',       scope: 'TASK 边界清晰 / BOUNDARY 显式 / 无 scope creep' },
  { key: 'multiend',    name: '多端体验审查员',   scope: 'iOS/Android/小程序 体验一致? 端侧能力差异在 PLATFORM-MATRIX 显式? 推送/支付/文件访问端差异在 spec 拍死?' },
]
const reviews = await parallel(REVIEW_ROLES.map(role => async () => {
  const out = await agent(
    `对抗审查 · 角色=【${role.name}】(app 主线 4 角色之一)。读 ${ROOT}/docs/spec.md 已写章节。
     只允许质疑这一类问题(越权质疑别类无效,不与其他角色妥协):${role.scope}
     发现问题逐条:severity(P0/P1/P2/P3)+ 问题 + 建议。P0 = 阻塞性(如命名锁有漏 / 用户故事失效),会触发回 /lockdown。
     返回 role(本角色名)+ findings[]。`,
    { label: `review:${role.key}`, phase: 'Review', schema: {
        type: 'object', required: ['role', 'findings'],
        properties: {
          role: { type: 'string' },
          findings: { type: 'array', items: {
            type: 'object', required: ['severity', '问题', '建议'],
            properties: {
              severity: { enum: ['P0', 'P1', 'P2', 'P3'] },
              '问题': { type: 'string' }, '建议': { type: 'string' } } } } } } }
  ).catch(e => ({ role: role.name, findings: [], _err: String(e) }))
  return out
}).map(p => p.catch(() => ({ role: '?', findings: [] }))))
const roles = reviews.map(r => r.role)
const hasP0 = reviews.some(r => (r.findings || []).some(f => f.severity === 'P0'))

// ── phase 7: completeness critic + 用确定性脚本写闸门 state(唯一写 state 的点)──
phase('Synthesis')
const synth = await agent(
  `完整性审查 + 汇编 spec.md + 用【确定性脚本】产闸门 state(唯一可信产出口,严禁手写 JSON——手写易和闸门 key 错位致整关失效)。在 ${ROOT}:
   输入:cognition=${JSON.stringify(cognition).slice(0, 400)}… ; platformMatrix=${JSON.stringify(platformMatrix)} ;
        gaps 数=${allGaps.length} ; disasters 数=${(fault.disasters || []).length} ; contract=${JSON.stringify(contract)} ;
        tasks=${JSON.stringify(tasks)} ; review_roles=${JSON.stringify(roles)} ; hasP0=${hasP0}。

   1) 汇编写【完整 docs/spec.md】(SKILL Step5 结构,逐章节落齐,不留草稿):
      前置人工动作清单(顶部)/ 全局认知 / 覆盖契约 / 故障想象力 / PRD 挑战 / 核心难点 / 多端能力矩阵 PLATFORM-MATRIX /
      数据契约(多端消费方 + 端侧独有字段)/ 多视角审查结果(4 角色)/ 人确认清单 / 冻结边界 / 任务清单(含 PLATFORM)/ 风险。

   2) Step4 前置人工动作反扫(补 A-GATE 0 未覆盖的端侧动作)聚合到 spec 顶部「前置人工动作清单」:
      微信小程序主体注册(6-7 天)/ 鸿蒙开发者公司主体 / 国内 Android 推送多通道(极光/个推)主账号 / APNs Auth Key(1 年有效)。
      每条 HUMAN: action:XX。

   3) 用 Bash 跑【确定性脚本】产闸门 state(严禁手写 JSON;key 已对齐,勿改 app-gate.sh):
      \`bash ${ROOT}/scripts/app-gate.sh app-gate shape\`
      该脚本机械验证 sg_app_* 并写 ${ROOT}/.claude/state/clearance-shape.json:
        sg_app_project_type(PROJECT_TYPE=app + CURRENT_GATE)/ sg_app_platform_matrix(≥8 行 + 无懒惰 fallback)/
        sg_app_task_platform_field(每 TASK 含 PLATFORM 且与 FILES 一致)/ sg_app_data_contract(契约表 + 消费端 ≥2 + 端侧独有字段)/
        sg_app_openapi_artifact(advisory,仅 design-first 项目)。
      ⚠️ 注意:SKILL OUTPUT_GATE 表还列了 sg_app_prd_challenge / sg_app_fault_imagination / sg_app_coverage_contract 三项 —
        这些章节已在 spec.md 落齐(PRD 挑战 ≥3 视角 + 缺口编号 + 处置 + ACCEPT 承接;故障 ≥2 维度 + 主语 + 对账;覆盖契约核心+不覆盖+FROZEN),
        以满足将来这些 sg_ 实现时的机械验收;本次以脚本实际输出为准,不手写其 state。
      然后写完成信号:\`mkdir -p .claude/state && echo "{\\"skill\\":\\"shape\\",\\"epoch\\":$(date +%s)}" > .claude/state/skill-signal.json\`。

   4) 解析脚本输出:任一 sg_(失败项,即 app-gate.sh 退出码 ≠ 0 或 ❌ 行)→ 把缺失项填入 blocked[],
      不静默放行(对接 OUTPUT_GATE「任一失败→阻塞 + 列缺失项」)。脚本全过 → blocked 为空。

   5) 全过则更新 ${ROOT}/docs/status.md 顶部 CURRENT_GATE: A-GATE 2,并勾上 A-GATE 1 进度。

   6) 若 hasP0=true(Review 出 P0)→ next_signal 写「停住:回 /lockdown 补完后重 /shape」(对接 SKILL 末尾回退分支);
      否则 next_signal 写「完成:/shape 已产出 A-GATE 1 spec.md,下一步 /build 进入 A-GATE 2」。

   返回写入摘要 + blocked + next_signal。`,
  { label: 'critic', phase: 'Synthesis', schema: {
      type: 'object', required: ['clearance', 'blocked', 'next_signal'],
      properties: {
        clearance: { type: 'object' },
        blocked: { type: 'array', items: { type: 'string' } },
        gate_passed: { type: 'boolean' },
        next_signal: { type: 'string' } } } }
)

return { pre, cognition, prdViews, platformMatrix, fault, contract, tasks, reviews, synth }
