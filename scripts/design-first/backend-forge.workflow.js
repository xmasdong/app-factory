// backend-forge.workflow.js — 编排【蓝图参考】:功能/契约 → 完整后端 API 推荐的多 agent 扇出结构
// 本文件性质:它是【蓝图参考】,展示该关推荐的多 agent 扇出结构(扇出哪些子任务、parallel/pipeline、对抗验证什么、loop 到什么条件、各 agent 干啥、产物落哪),不是本项目的可执行脚本。
// 真执行时:用户手动开 ultracode 模式,AI(Claude)用 Claude 内置的【Workflow 工具】参考本蓝图当场组合编排(script 由 AI 现场写,非加载本文件运行)。
//   ⚠️ Workflow 工具归 Claude/ultracode,非本项目定义;本项目不拥有 workflow 运行时,也没有 `claude workflow` 这种命令。
//   ⚠️ ultracode 是用户手动开的会话高级模式;开了之后 AI 才默认倾向用 Workflow 工具编排。
//   在目标业务项目根执行,确保 CLAUDE_PROJECT_DIR 指向它。
// 产物(随项目根):api/openapi.yaml(SSOT)+ 服务端骨架/迁移/RLS + client SDK
//                 .claude/state/contract-test.json + .claude/state/e2e-contract.json(闸门读)
//
// 四质量模式归位:
//   fan-out 全覆盖     = parallel(endpoints) 每 endpoint 一 worker,不抽样
//   pipeline 串数据    = endpoint worker 内 impl→contract→authz 顺序串
//   adversarial verify = 每条业务规则 N 个 skeptic 独立质疑(不看彼此),多数过才留
//   completeness critic= Synthesis 单 agent 核覆盖 + 用确定性脚本写 state(唯一可信产出口)
//
// 蓝图里用到的编排原语(由 Claude 内置 Workflow 工具提供,非本项目定义):phase(title) / parallel(fns[]) / agent(prompt,{label,phase,schema})
// 每个 agent 返回须符合 schema;每个并行 worker 必须 .catch 兜底成合法 fallback,否则一崩全崩。

export const meta = {
  name: 'backend-forge-orchestrated',
  description: 'openapi SSOT → 按 endpoint 扇出(实现→契约→越权 pipeline)→ 业务规则对抗验证 → 确定性脚本产 contract-test.json/e2e-contract.json',
  phases: [
    { title: 'OpenAPI-SSOT',      detail: 'single agent — 派生并定稿 api/openapi.yaml,扇出前唯一真相源' },
    { title: 'Per-Endpoint',      detail: 'parallel × endpoint — 每 endpoint 内 pipeline:实现→契约→越权负向' },
    { title: 'Adversarial-Rules', detail: 'parallel × rule × N skeptic — 多数过才留(adversarial verify)' },
    { title: 'Synthesis',         detail: 'completeness critic — 跑确定性脚本写 contract-test.json/e2e-contract.json' },
  ],
}

const ROOT = process.env.CLAUDE_PROJECT_DIR || process.cwd()
const N_SKEPTIC = 3

// ── phase 1: openapi 先定稿(SSOT,扇出前必须存在)──
phase('OpenAPI-SSOT')
const ssot = await agent(
  `读 ${ROOT}/docs/spec.md §数据契约 + ${ROOT}/docs/design/design-manifest.json screens[].fields。
   screen→entity→endpoint 派生(list→GET 集合+分页 / detail→GET{id} / 表单→POST·PATCH / 删除·状态钮→DELETE·PATCH)。
   inferred 端点标注(草稿,需人确认,别当真)。高风险字段落 schema format/enum(金额=分/时间=ISO8601/枚举全列)。
   每写端点声明 403/422。每 entity 建一行 ownership 越权矩阵(谁能 CRUD 谁的数据)。默认 Supabase:RLS 用声明式 SQL。
   写 ${ROOT}/api/openapi.yaml(OpenAPI 3.1)。返回 endpoints[] + ownership_rows + 业务规则 rules[]。`,
  { label: 'ssot', phase: 'OpenAPI-SSOT', schema: {
      type: 'object', required: ['endpoints', 'ownership_rows'],
      properties: { endpoints: { type: 'array', items: { type: 'string' } },
        ownership_rows: { type: 'integer' }, rules: { type: 'array', items: { type: 'string' } } } } }
)

// ── phase 2: 按 endpoint 扇出,每 worker 内 pipeline 实现→契约→越权 ──(fan-out + pipeline)
phase('Per-Endpoint')
const perEp = await parallel((ssot.endpoints || []).map(ep => async () => {
  const impl = await agent(
    `endpoint=${ep}。按 ${ROOT}/api/openapi.yaml 实现(Supabase migration + RLS policy 或服务端 handler)。
     RLS/权限走声明式 SQL,不手写 if。返回实现状态 + 改动文件。`,
    { label: `impl:${ep}`, phase: 'Per-Endpoint', schema: {
        type: 'object', required: ['result'], properties: { result: { enum: ['done', 'partial'] }, files: { type: 'array', items: { type: 'string' } } } } }
  ).catch(e => ({ result: 'partial', files: [], _err: String(e) }))
  // 契约/越权测试由 phase3 的确定性脚本统一跑;此处只产实现 + 自报
  return { endpoint: ep, impl: impl.result }
}).map(p => p.catch(() => ({ endpoint: '?', impl: 'partial' }))))

// ── phase 3: 业务规则对抗验证(N skeptic 独立质疑,多数过才留)──(adversarial verify)
phase('Adversarial-Rules')
const rules = ssot.rules || []
const judged = await parallel(rules.map(rule => async () => {
  const votes = await parallel(Array.from({ length: N_SKEPTIC }, (_, i) => () =>
    agent(
      `质疑业务规则:"${rule}"。它是否真被实现+测试正确防住?(契约只验结构,不验业务对错。)
       默认怀疑:除非有明确实现+断言证据,否则判 unsafe。不看其他 skeptic 结论。`,
      { label: `skeptic#${i}:${rule.slice(0, 20)}`, phase: 'Adversarial-Rules', schema: {
          type: 'object', required: ['safe'], properties: { safe: { type: 'boolean' }, reason: { type: 'string' } } } }
    ).catch(() => ({ safe: false, reason: 'skeptic error → 保守判 unsafe' }))
  ))
  const safe = votes.filter(Boolean).filter(v => v.safe).length > N_SKEPTIC / 2
  return { rule, safe, votes: votes.filter(Boolean).length }
}).map(p => p.catch(() => ({ rule: '?', safe: false, votes: 0 }))))

// ── phase 4: completeness critic + 用确定性脚本写闸门 state(唯一可信产出口)──
phase('Synthesis')
const synth = await agent(
  `完整性审查 + 用【确定性脚本】产出闸门 state(严禁手写 JSON——和闸门 key 错位即整关失效)。
   输入 perEp=${JSON.stringify(perEp)} ; 业务规则裁决=${JSON.stringify(judged)} ; ownership_rows=${ssot.ownership_rows}。
   1) 核覆盖:每 endpoint 都有实现?越权用例数 ≥ ownership_rows?有 impl=partial 或 业务规则 safe=false 的列入风险上报。
   2) 起 mock(prism)或对真后端,用 Bash 跑本 skill 仓 scripts/design-first/ 下确定性脚本(与本 .workflow.js 同目录;先 head 读 usage 再按参数跑):
      - contract-test.sh   → Schemathesis 打 api/openapi.yaml → 写 ${ROOT}/.claude/state/contract-test.json {target(mock|real),result,failures}
      - e2e-contract.sh    → 真实响应字段对照 openapi → 写 ${ROOT}/.claude/state/e2e-contract.json {result,missing_fields,extra_fields}
      - ownership-probe.sh → 用户A token 取用户B 资源断言 403 → 结果并入 e2e-contract.json
      key 已对齐 app-gate.sh。⚠️ target=mock 只算半通过,上线前必须对 real 复跑。
   3) 跑完 \`bash scripts/app-gate.sh app-gate build\`(及 qa)复核闸门读到。
   返回写入摘要 + risks(partial 端点 + unsafe 业务规则)。`,
  { label: 'critic', phase: 'Synthesis', schema: {
      type: 'object', required: ['contract_test', 'risks'],
      properties: { contract_test: { type: 'object' }, e2e: { type: 'object' },
        risks: { type: 'array', items: { type: 'string' } } } } }
)

return { ssot, perEp, judged, synth }
