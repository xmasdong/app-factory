// qa (A-GATE 3 验收关).workflow.js — A-GATE 3 验收关 多 agent 编排
//
// 怎么跑(关键·别误会):
//   主执行路径 = AI(Claude)在会话内调用【Workflow 工具】(Claude Code 内置·不是 shell),
//   传 script = 本文件内容(Read 后传入)。**不存在 `claude workflow` 这种命令行。**
//   推荐用户先开 ultracode 模式(让 AI 默认倾向用 Workflow 工具编排);
//   未开 ultracode / 不便编排时,走 SKILL.md 顶部的「单 agent 顺序降级」路径(逻辑等价,慢但不丢覆盖)。
//   在目标业务项目根执行,确保 CLAUDE_PROJECT_DIR 指向它。
//
// 四质量模式归位(本关灵魂在 phase3 对抗验):
//   fan-out 全覆盖     = phase2 parallel(platforms) 每端一 worker / phase4 parallel(9 合规节)
//   pipeline 串数据    = phase2 端 worker 内:跑链路 → 截 3 viewport → 自报 PASS/FAIL
//   adversarial verify = phase3 每条 reviewer claim 起 N 个 skeptic 独立质疑(不看彼此),多数过才 safe
//   completeness critic= phase5 单 agent 核完整性 + 用确定性脚本写闸门 state(唯一可信产出口,严禁手写 key)
//
// Workflow runtime 全局:phase(title) / parallel(fns[]) / pipeline(items,...stages)
//                        / agent(prompt,{label,phase,schema}) / log()
//   顶层 await 可用。每个并行 worker 必须 .catch 兜底成合法 fallback,否则一崩全崩(保守判 fail/unsafe)。
//
// 产物(随项目根,key 与 scripts/app-gate.sh 完全对齐,勿改):
//   .claude/state/verify-report.json          ← sg_app_multiplatform_smoke 读 .multi_platform_status
//   .claude/state/reviewer-walkthrough/       ← sg_app_reviewer_path 读 目录+文件数(≥3)+演示账号引用
//   .claude/state/asr-survival-scan.json      ← sg_app_compliance_real_scan 读 .result == "PASS"
//   .claude/state/verify-screenshots/<p>/<viewport>/<page>.png  ← phase2 截图存档(phase5 机械验)

export const meta = {
  name: 'qa-agate3-orchestrated',
  description:
    'A-GATE 3 验收关:契约定稿 → 多端 smoke 扇出(跑链路→截3viewport pipeline)→ 审核员路径对抗验证(N skeptic + 反绕过/paywall/IAP沙盒)→ 合规 9 节扇出 → Synthesis 用确定性脚本写 verify-report.json/asr-survival-scan.json/reviewer-walkthrough 并复核三闸门',
  phases: [
    { title: 'Contract-Recon',           detail: 'single agent — 读 spec.md 契约/PLATFORM-MATRIX/BACKEND-READINESS,定稿扇出输入清单;演示账号缺 <TBD> → contract_unmet 回 /lockdown' },
    { title: 'Multi-Platform-Smoke',      detail: 'parallel × platform — 每端 worker 内 pipeline:跑核心链路→截3viewport→存档→自报 PASS/FAIL;deferred 端不跑' },
    { title: 'Adversarial-Reviewer-Path', detail: 'parallel × claim × N skeptic — 反绕过/paywall七要素/真SKU 默认怀疑,多数 safe 才过;IAP沙盒单串行 worker 跑(抢账号)' },
    { title: 'Compliance-Scan',           detail: 'parallel × 9 节(A-I) — 按 app-store-review-survival skill 逐项取证 PASS/FAIL/N_A' },
    { title: 'Synthesis',                 detail: 'completeness critic — 跑确定性脚本写 verify-report.json/asr-survival-scan.json + app-gate qa 复核三闸门 + 推进 A-GATE 4' },
  ],
}

const ROOT = process.env.CLAUDE_PROJECT_DIR || process.cwd()
const N_SKEPTIC = 3

// ── phase 1: Contract-Recon —— 扇出前的真相源,必须先定稿 ────────────────────
phase('Contract-Recon')
const contract = await agent(
  `你是扇出前的真相源。读以下三处并定稿 fan-out 输入清单(后续所有并行都以此为准):
   - ${ROOT}/docs/spec.md  §覆盖契约     → 抽出每条核心链路 core_paths[](文字描述,如"登录→导出高清→付费墙")
   - ${ROOT}/docs/spec.md  §PLATFORM-MATRIX → 抽出矩阵声明的端 platforms[],每端标 required|deferred(deferred 必须有理由)
   - ${ROOT}/docs/spec.md  §BACKEND-READINESS → 抽出 demo_accounts:{reviewer_notes_account, sandbox_apple_id, google_test_account, demo_account}
   判定:demo_accounts 任一 == "<TBD>" 或缺失 → contract_unmet=true(并在 reason 里列出待补字段,提示回 /lockdown 补,**不进 phase2**)。
   platforms 每项形如 {name:'ios', required:true} 或 {name:'harmony', required:false, reason:'launch 不含'}。`,
  { label: 'contract-recon', phase: 'Contract-Recon', schema: {
      type: 'object', required: ['platforms', 'core_paths', 'demo_accounts', 'contract_unmet'],
      properties: {
        platforms: { type: 'array', items: { type: 'object', required: ['name', 'required'],
          properties: { name: { type: 'string' }, required: { type: 'boolean' }, reason: { type: 'string' } } } },
        core_paths: { type: 'array', items: { type: 'string' } },
        demo_accounts: { type: 'object' },
        contract_unmet: { type: 'boolean' },
        reason: { type: 'string' } } } }
).catch(e => ({ platforms: [], core_paths: [], demo_accounts: {}, contract_unmet: true, reason: 'contract-recon 出错 → 保守判 contract_unmet: ' + String(e) }))

if (contract.contract_unmet) {
  log('contract_unmet=true → 停在 A-GATE 3 入口,不进多端 smoke。回 /lockdown 补演示账号。reason=' + (contract.reason || ''))
  return { contract, decision: 'send-back', stopped_at: 'Contract-Recon', risks: ['契约未满足:' + (contract.reason || '演示账号 <TBD>')] }
}

const platforms = contract.platforms || []
const VIEWPORTS = ['phone-portrait', 'tablet', 'phone-landscape']

// ── phase 2: Multi-Platform-Smoke —— fan-out × platform,每 worker 内 pipeline ──
phase('Multi-Platform-Smoke')
const smoke = await parallel(platforms.map(p => async () => {
  // deferred 端不跑,直接返回理由
  if (p.required === false) {
    return { platform: p.name, status: 'deferred', reason: p.reason || 'PLATFORM-MATRIX 声明本端不在 launch 范围' }
  }
  // 端 worker 内 pipeline:跑核心链路 → 截 3 viewport → 存档 → 自报
  const out = await pipeline(
    [p],
    // stage 1:跑该端核心链路
    async (plat) => agent(
      `端=${plat.name}。跑 spec.md 覆盖契约的核心链路(${JSON.stringify(contract.core_paths)})。
       工具按端 dispatch:web=playwright / ios=simctl / flutter=flutter screenshot;鸿蒙=DevEco+真机手动 / 小程序=微信开发者工具手动(honor)。
       每条链路自报 PASS(全跑通·无空状态/报错弹框)/ FAIL(断在中间·闪退·error toast)。返回 link_results[] 与整体 status。`,
      { label: `run:${plat.name}`, phase: 'Multi-Platform-Smoke', schema: {
          type: 'object', required: ['status'], properties: {
            status: { enum: ['pass', 'fail'] }, link_results: { type: 'array', items: { type: 'string' } } } } }
    ),
    // stage 2:对每个 viewport 截图并存档(沿用 ui-snapshot.sh)
    async (runRes, plat) => agent(
      `端=${plat.name},链路自报=${JSON.stringify(runRes)}。
       对 3 个 viewport(phone-portrait / tablet / phone-landscape)各截核心页:
       用 Bash 调 ${ROOT}/scripts/design-first/ui-snapshot.sh(先 \`head ui-snapshot.sh\` 读 usage)按端 dispatch 截图,
       存到 ${ROOT}/.claude/state/verify-screenshots/${plat.name}/<viewport>/<page>.png(viewport 用上面三个名)。
       要求每端 ≥3 张、每张 ≥5KB(非空 PNG)。返回 screenshot_count 与存档目录。`,
      { label: `shot:${plat.name}`, phase: 'Multi-Platform-Smoke', schema: {
          type: 'object', required: ['screenshot_count'], properties: {
            screenshot_count: { type: 'integer' }, dir: { type: 'string' } } } }
    ),
  )
  const runRes = out[0]
  const shotRes = out[1]
  return { platform: p.name, status: (runRes && runRes.status) || 'fail',
           link_results: (runRes && runRes.link_results) || [],
           screenshot_count: (shotRes && shotRes.screenshot_count) || 0,
           dir: (shotRes && shotRes.dir) || '' }
}).map(pr => pr.catch(e => ({ platform: '?', status: 'fail', _err: String(e) }))))

// ── phase 3: Adversarial-Reviewer-Path —— 本关灵魂:每 claim × N skeptic 独立质疑 ──
phase('Adversarial-Reviewer-Path')
const claims = [
  'reviewer_notes_account 无法用初始资源绕过付费墙(反绕过:全新/重置账号触发付费功能必弹付费墙,无内部账号自动 VIP 逻辑)',
  'paywall 七要素齐全:subscription title / length / price / auto-renew 文案 / Privacy URL / Terms URL / Restore Purchases',
  '看广告/试用机制走真实 SKU 验证非直接解锁(仅当 spec 声明此机制;若 spec 无则判 N_A safe)',
]
const reviewerClaims = await parallel(claims.map(claim => async () => {
  // N 个 skeptic 互不看彼此结论,默认怀疑
  const votes = await parallel(Array.from({ length: N_SKEPTIC }, (_, i) => () =>
    agent(
      `默认怀疑此 claim:"${claim}"。
       除非在 ${ROOT}/.claude/state/reviewer-walkthrough/screenshots/ 有【真实】的 reviewer-walkthrough 截图/GIF 证据
       (反绕过=no-bypass.png / paywall 七要素=paywall-full.png / 沙盒=iap-sandbox.png)且证据是真账号真实演示(非占位/非空 PNG,≥5KB),
       否则一律判 unsafe。用 Bash 核证据文件是否存在+大小;不看其他 skeptic 的结论。
       (若 claim 末尾标"仅当 spec 声明"而 spec 无此机制 → 判 safe 并注 N_A。)`,
      { label: `skeptic#${i}:${claim.slice(0, 22)}`, phase: 'Adversarial-Reviewer-Path', schema: {
          type: 'object', required: ['safe'], properties: {
            safe: { type: 'boolean' }, reason: { type: 'string' } } } }
    ).catch(() => ({ safe: false, reason: 'skeptic 出错 → 保守判 unsafe' }))
  ))
  const valid = votes.filter(Boolean)
  const safe = valid.filter(v => v.safe).length > N_SKEPTIC / 2
  return { claim, safe, votes: valid.length, detail: valid }
}).map(pr => pr.catch(e => ({ claim: '?', safe: false, votes: 0, _err: String(e) }))))

// Step 4.4 IAP 沙盒(真账号副作用)—— 单独串行 worker,不进 N-skeptic 并行,避免抢 sandbox_apple_id
const iapSandbox = await agent(
  `串行单跑(独占 sandbox_apple_id=${JSON.stringify((contract.demo_accounts || {}).sandbox_apple_id)},别与其他 worker 并发抢账号)。
   用 sandbox_apple_id 完整跑:购买 → receipt → 服务端验证 → 应用内权益激活;再删 app 重装 Restore → 权益回归。
   截图沙盒确认弹框(右上须有 [Environment: Sandbox])与 Restore 后状态,存到
   ${ROOT}/.claude/state/reviewer-walkthrough/screenshots/iap-sandbox.png 与 restore.png(各 ≥5KB)。
   另写 ${ROOT}/.claude/state/reviewer-walkthrough/walkthrough-notes.md(用户视角 + 引用真实演示账号,给 reviewer 当 Review Notes 草稿),
   并尽量产出 paywall-walkthrough.gif。返回 produced[](实际落盘文件名)与 sandbox_ok。`,
  { label: 'iap-sandbox', phase: 'Adversarial-Reviewer-Path', schema: {
      type: 'object', required: ['sandbox_ok'], properties: {
        sandbox_ok: { type: 'boolean' }, produced: { type: 'array', items: { type: 'string' } }, notes: { type: 'string' } } } }
).catch(e => ({ sandbox_ok: false, produced: [], notes: 'iap-sandbox 出错 → 保守 false: ' + String(e) }))

// ── phase 4: Compliance-Scan —— fan-out × 9 节(A-I)──
phase('Compliance-Scan')
const sections = ['A_categories', 'B_privacy', 'C_permissions', 'D_iap', 'E_account_deletion', 'F_ipad_watch', 'G_screenshots', 'H_build_number', 'I_demo_account']
const compliance = await parallel(sections.map(sec => async () => {
  const r = await agent(
    `按 app-store-review-survival skill 对照本合规节取证并判 PASS / FAIL / N_A,理由必须引【具体文件/字段】
     (如 Info.plist usage string 原文 / ASC 字段 / build number 值 / 隐私 nutrition label / 应用内删除账号路径)。
     本节 = ${sec}。
       A_categories=Kids 陷阱与主类目; B_privacy=首屏 consent/Privacy URL/nutrition label; C_permissions=usage strings 具体化+多语言;
       D_iap=3.1.2 完整披露; E_account_deletion=5.1.1(v) 应用内自助; F_ipad_watch=Universal/平板手表;
       G_screenshots=尺寸/格式/真实性; H_build_number=单调递增; I_demo_account=Review Notes 演示账号一致。`,
    { label: `compliance:${sec}`, phase: 'Compliance-Scan', schema: {
        type: 'object', required: ['result'], properties: {
          result: { enum: ['PASS', 'FAIL', 'N_A'] }, notes: { type: 'string' } } } }
  ).catch(e => ({ result: 'FAIL', notes: '扫描出错保守判 FAIL: ' + String(e) }))
  return { section: sec, result: r.result, notes: r.notes || '' }
}).map(pr => pr.catch(e => ({ section: '?', result: 'FAIL', notes: '并发出错保守 FAIL: ' + String(e) }))))

// ── phase 5: Synthesis —— completeness critic + 确定性脚本写闸门 state(唯一可信产出口)──
phase('Synthesis')
const synth = await agent(
  `你是 completeness critic + 唯一可信产出口。严禁手写 JSON key——key 必须与 ${ROOT}/scripts/app-gate.sh 对齐,错位即整关失效。
   输入:
     契约 contract=${JSON.stringify(contract)}
     多端 smoke=${JSON.stringify(smoke)}
     审核员 claims=${JSON.stringify(reviewerClaims.map(c => ({ claim: c.claim, safe: c.safe, votes: c.votes })))}
     IAP 沙盒=${JSON.stringify(iapSandbox)}
     合规 9 节=${JSON.stringify(compliance)}

   【1】完整性核(决定 decision/overall):
       - 任一端 status=='fail' → decision='send-back'(列 fail 端)。
       - 任一 reviewer claim 多数 unsafe(safe==false) → 阻塞 send-back(列证据缺口:缺哪张 no-bypass/paywall-full/iap-sandbox)。
       - 任一合规节 result=='FAIL' → overall='needs-fix' → decision='send-back'(列 blocking_sections)。
       - 全清 → decision='pass'、合规 overall='ready-for-submit'、result='PASS'。

   【2】机械验截图(用 Bash,不要人眼放过):对每个 required 端核 ${ROOT}/.claude/state/verify-screenshots/<p>/<viewport>/ :
       每端 ≥3 张、每张 ≥5KB、mtime 不旧于最后 commit 30min(\`git log -1 --format=%ct\` 比对 \`stat\`)。不达标的端按 fail 处理并入风险。
       审核员产物同理核 ${ROOT}/.claude/state/reviewer-walkthrough/(目录存在 + 文件数 ≥3 + walkthrough-notes.md 非空且引用真实演示账号)。

   【3】用确定性脚本/Bash 写两份闸门 state(key 严格如下,**勿增删 key**):
       (a) ${ROOT}/.claude/state/verify-report.json =
           {
             "decision": "<pass|send-back>",
             "contract_status": { "core_paths": "covered", "frozen_changes": [] },
             "multi_platform_status": { "<每端名>": "<pass|fail|deferred>" },   // 注意:此对象的每个【值】会被 sg_app_multiplatform_smoke 逐行比对 PASS/DEFERRED/N/A(大小写不敏感),非 pass/deferred 即判失败
             "reviewer_walkthrough_path": ".claude/state/reviewer-walkthrough/",
             "compliance_scan_result": { "scan_file": ".claude/state/asr-survival-scan.json", "overall": "<ready-for-submit|needs-fix>", "blocking_sections": [<FAIL 节名>] },
             "new_paths_proposed_by_user": []
           }
       (b) ${ROOT}/.claude/state/asr-survival-scan.json =
           {
             "scanned_at": "<ISO8601 now>",
             "skill_version": "app-store-review-survival@<commit-hash 或 SKILL.md mtime>",
             "result": "<PASS 当且仅当 9 节无 FAIL,否则 FAIL>",   // ★ sg_app_compliance_real_scan 读的是顶层 .result,必须有此 key
             "sections": { "A_categories": {"result":"...","notes":"..."}, ... 全 9 节 ... },
             "overall": "<ready-for-submit|needs-fix>",
             "blocking_sections": [<FAIL 节名>]
           }
       两份都用 Bash 写盘(可借 jq -n 构造,保证合法 JSON)。截图存档已在 phase2 用 ui-snapshot.sh 产出,这里只机械验+组装,不重截。

   【4】复核:跑 \`bash ${ROOT}/scripts/app-gate.sh app-gate qa\`(确认 sg_app_reviewer_path / sg_app_multiplatform_smoke 读到),
       再单独跑 \`bash ${ROOT}/scripts/app-gate.sh app-gate lockdown\` 中的合规检查或直接确认 sg_app_compliance_real_scan 读到 asr-survival-scan.json .result==PASS。
       把每条闸门的通过/失败原文回填到返回里。

   【5】仅当 decision=='pass' 且三闸门全 PASS 才:
       写 ${ROOT}/.claude/state/skill-signal.json = {"skill":"qa","epoch":<date +%s>};
       更新 ${ROOT}/docs/status.md 顶部 CURRENT_GATE → A-GATE 4 并勾上 A-GATE 3。
       否则保持 A-GATE 3 不推进。

   返回写入摘要 + risks(fail 端 + 多数 unsafe 的 claim + FAIL 合规节)。`,
  { label: 'synthesis', phase: 'Synthesis', schema: {
      type: 'object', required: ['decision', 'gate_recheck', 'risks'],
      properties: {
        decision: { enum: ['pass', 'send-back'] },
        wrote: { type: 'array', items: { type: 'string' } },
        gate_recheck: { type: 'object' },
        advanced_to: { type: 'string' },
        risks: { type: 'array', items: { type: 'string' } } } } }
).catch(e => ({ decision: 'send-back', wrote: [], gate_recheck: {}, risks: ['Synthesis 出错 → 保守 send-back: ' + String(e)] }))

return { contract, smoke, reviewerClaims, iapSandbox, compliance, synth }
