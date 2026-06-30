// build.workflow.js — ultracode Workflow 编排:status.md 未完成 TASK → 实现+测试通过+commit(A-GATE 2)
// 怎么跑:AI 调用 Workflow 工具(Claude Code 内置·非 shell CLI),script = 本文件内容(Read 后传入)。
//   不存在 `claude workflow` 命令。在目标业务项目根执行,确保 CLAUDE_PROJECT_DIR 指向它。
//   skill 无法自己开 ultracode(那是用户手动开的会话高级模式);本文件只是 AI 用 Workflow 工具时的编排脚本。
//   推荐用户开 ultracode 模式(AI 默认倾向调 Workflow);未开/不便编排时走 SKILL.md 单 agent 降级路径。
//
// 产物(随项目根):生产代码 + 测试 + docs/status.md 任务 [x] + git commit + .claude/state/skill-signal.json
//                 闸门 state 由 scripts/ 下既有确定性 .sh 产出(勿改其 key)。
//
// 四质量模式归位(对照 design-restore / backend-forge 同款判据):
//   pipeline 串数据      = 顶层 pipeline(tasks):逐 TASK 串行(跨 TASK 不并行,依赖 + 逐 commit 闸门 + PLATFORM 隔离/scope/bundle 串行语义)
//   fan-out 全覆盖       = Phase 1 单 TASK 内 parallel(实现A ‖ 测试B ‖ 美术C),三条无依赖子轨
//   loop-until-converge  = Phase 2 单 agent for 循环:跑测试 → fail 数单调降才继续,3 轮熔断(同 design-restore 判据)
//   adversarial verify   = Phase 3 parallel(critic-1 diff 挑刺 ‖ critic-2 stub/mock 审),独立于实现者,有 P0 有限回灌
//
// Workflow runtime 全局:phase(title) / parallel(fns[]) / pipeline(items, ...stages) / agent(prompt,{label,phase,schema}) / log()
// 每个 agent 返回须符合 schema;每个并行 worker 必须 .catch 兜底成合法 fallback,否则一崩全崩。
// 唯一写 state 的点 = Phase 3 末尾让 agent 用 Bash 调既有 .sh 产 JSON(agent 不直接写 state key,与 design-restore Synthesis 同构)。

export const meta = {
  name: 'build-orchestrated',
  description: '读 status.md 未完成 TASK → pipeline 逐 TASK 串行 × 每 TASK 内 4 phase(合同闸门→并行实现/测试/美术→测试 loop 熔断→对抗 review + 确定性闸门 commit)',
  phases: [
    { title: 'Contract-Gate',           detail: 'single agent 前置闸门 — INPUT_CONTRACT + GATE1 三问 → 冻结 ACCEPT/FILES/PLATFORM' },
    { title: 'Implement',               detail: 'parallel × 无依赖子轨 — A 生产代码 ‖ B 测试(TDD) ‖ C 美术(仅 UI 任务)' },
    { title: 'Test-Loop',               detail: 'loop-until-converge — 单 agent for 1..3:fail 数单调降才继续,不降即停,3 轮软熔断' },
    { title: 'Adversarial-Review+Gate', detail: 'parallel critic 对抗验证 → 确定性 .sh 落闸门 state + commit + status.md + skill-signal' },
  ],
}

const ROOT = process.env.CLAUDE_PROJECT_DIR || process.cwd()
const K_ROUNDS = 3            // Step 7:最多 3 轮 fix→retest
const SOFT_FUSE_LIMIT = 2     // 连续 2 个软熔断 → 硬熔断停等人

// ── phase 0(顶层前置):读 status.md 解析未完成 TASK 列表(含 PLATFORM/ACCEPT/FILES)──
// 这是 pipeline 喂入前的唯一真相源抽取(扇出前 FROZEN),不并行。
phase('Contract-Gate')
const taskList = await agent(
  `读 ${ROOT}/docs/status.md。校 INPUT_CONTRACT:顶部含 PROJECT_TYPE: app + CURRENT_GATE: A-GATE 2;
   ${ROOT}/.claude/state/clearance-lockdown.json 与 ${ROOT}/.claude/state/clearance-shape.json 存在(Lockdown/Shape 前置已过)。
   解析任务清单里所有【未完成】TASK(- [ ]),每个抽出:id、一句话目标、ACCEPT(验收条件)、FILES(允许改的文件)、PLATFORM 字段。
   PLATFORM 缺失的 TASK 标 contract_ok=false(回 /shape 补 TASK-TEMPLATE),不要替它瞎补。
   不要在此实现任何代码,只做清单抽取 + 合同体检。按【依赖/声明顺序】返回 tasks[](pipeline 将逐个串行喂入,不打乱)。`,
  { label: 'task-list', phase: 'Contract-Gate', schema: {
      type: 'object', required: ['contract_ok', 'tasks'],
      properties: {
        contract_ok: { type: 'boolean' },
        reason: { type: 'string' },
        tasks: { type: 'array', items: {
          type: 'object', required: ['id', 'goal', 'accept', 'files', 'platform'],
          properties: {
            id: { type: 'string' },
            goal: { type: 'string' },
            accept: { type: 'array', items: { type: 'string' } },
            files: { type: 'array', items: { type: 'string' } },
            platform: { type: 'string' },
            is_ui: { type: 'boolean' } } } } } } }
)

if (!taskList.contract_ok) {
  log(`INPUT_CONTRACT 不满足 → 整关阻塞,不进 pipeline。reason=${taskList.reason || 'see status.md'}`)
  return { status: 'blocked', stage: 'Contract-Gate', reason: taskList.reason || 'INPUT_CONTRACT 不满足', tasks: [] }
}

// ── 顶层 pipeline:逐 TASK 串行(保 PLATFORM 隔离 / scope / bundle 串行语义;跨 TASK 绝不并行)──
// 每个 item 内部走 4 phase(其中 Phase 0 已抽清单,这里做单 TASK 的合同闸门 = GATE 1 三问 + 冻结)。
let softFuseStreak = 0
const results = await pipeline(taskList.tasks || [],

  // ───────── 每 TASK · Phase 0「Contract-Gate」(single agent 前置闸门,非编排)─────────
  async (task) => {
    const gate = await agent(
      `TASK=${task.id}「${task.goal}」PLATFORM=${task.platform}。做 GATE 1 三问体检(非实现):
       ① 一句话做什么 ② ACCEPT 是否可测试(给出可执行断言) ③ 改哪些文件(必须就是 FILES 列表)。
       INPUT_CONTRACT 复核:本 TASK 有 PLATFORM 字段(=${task.platform})。任一不满足 → gate_pass=false 给 reason。
       通过则把 ACCEPT/FILES/PLATFORM 收敛为 FROZEN(后续 phase 唯一输入,不可漂)。
       FROZEN 候选:accept=${JSON.stringify(task.accept)} files=${JSON.stringify(task.files)}。`,
      { label: `gate:${task.id}`, phase: 'Contract-Gate', schema: {
          type: 'object', required: ['gate_pass', 'frozen_accept', 'frozen_files', 'platform', 'is_ui'],
          properties: {
            gate_pass: { type: 'boolean' },
            reason: { type: 'string' },
            frozen_accept: { type: 'array', items: { type: 'string' } },
            frozen_files: { type: 'array', items: { type: 'string' } },
            platform: { type: 'string' },
            is_ui: { type: 'boolean' } } } }
    ).catch(e => ({ gate_pass: false, reason: 'gate agent error: ' + String(e), frozen_accept: [], frozen_files: [], platform: task.platform, is_ui: false }))

    if (!gate.gate_pass) {
      log(`TASK ${task.id} GATE 1 不过 → blocked,pipeline 不进 Phase 1。reason=${gate.reason}`)
      return { id: task.id, status: 'blocked', stage: 'Contract-Gate', reason: gate.reason }
    }
    return { id: task.id, gate, frozen: { accept: gate.frozen_accept, files: gate.frozen_files, platform: gate.platform, is_ui: gate.is_ui } }
  },

  // ───────── 每 TASK · Phase 1「Implement」(parallel × 无依赖子轨,仅当 ACCEPT FROZEN)─────────
  async (carry) => {
    if (carry.status === 'blocked') return carry      // 闸门没过的 TASK 直接透传,不实现
    const { id, frozen } = carry
    const A = frozen.accept, F = frozen.files, P = frozen.platform

    // worker A = 生产代码(Mock 路由:bundle/IAP/push token 未锁 → 硬阻塞 blocked,不 mock 推进;允许项 optimistic)
    const workerA = agent(
      `TASK=${id} PLATFORM=${P}。实现【生产代码】满足 FROZEN ACCEPT=${JSON.stringify(A)},只改 FILES=${JSON.stringify(F)}。
       Mock 路由(硬规则):bundle id / IAP product id / 推送 token 字段 / 支付服务端验证 未锁 → 不 mock 推进,返回 status='blocked' + reason。
       允许 mock 项(后端 schema 已 FROZEN / IAP 沙盒 ready)可写 optimistic,但必须标识 + 待 Phase3 记入 status.md 并指明被替换文件路径。
       禁止静默降级(返假数据不报错不记日志)。禁止预建抽象/幽灵依赖/防御性冗余/范围蠕变。返回改动文件 + optimistic 项。`,
      { label: `impl:${id}`, phase: 'Implement', schema: {
          type: 'object', required: ['status'],
          properties: { status: { enum: ['done', 'partial', 'blocked'] }, reason: { type: 'string' },
            files: { type: 'array', items: { type: 'string' } },
            optimistic: { type: 'array', items: { type: 'object',
              properties: { item: { type: 'string' }, replaces_path: { type: 'string' } } } } } } }
    ).catch(e => ({ status: 'failed', reason: 'impl error: ' + String(e), files: [], optimistic: [] }))

    // worker B = 测试(TDD:与 A 同源 ACCEPT 并行,可先于/并行实现;stabilizing 起含 E2E)
    const workerB = agent(
      `TASK=${id} PLATFORM=${P}。为 FROZEN ACCEPT=${JSON.stringify(A)} 写【测试】(单元 + 集成;stabilizing 阶段起含 E2E)。
       测试基于 ACCEPT 断言,不读实现细节(TDD,与实现 worker 并行,可先于实现存在)。只落在 FILES/测试目录内。返回测试文件 + 覆盖的 ACCEPT 条目。`,
      { label: `test:${id}`, phase: 'Implement', schema: {
          type: 'object', required: ['status'],
          properties: { status: { enum: ['done', 'partial', 'failed'] }, reason: { type: 'string' },
            test_files: { type: 'array', items: { type: 'string' } },
            covered: { type: 'array', items: { type: 'string' } } } } }
    ).catch(e => ({ status: 'failed', reason: 'test error: ' + String(e), test_files: [], covered: [] }))

    // worker C = 美术(仅 UI/含美术任务才有;纯 backend/native 逻辑任务此轨缺席 → Phase1 退化为 A‖B)
    const workerC = frozen.is_ui
      ? agent(
          `TASK=${id}。用 codex-image-bridge 生成本 UI 任务所需图标/插画/素材。约束:
           App Store 图标无 alpha 通道(RGB 不透明);watchOS 图标不能深色/黑底(明亮彩色满底);各平台尺寸齐全。返回生成的素材路径。`,
          { label: `art:${id}`, phase: 'Implement', schema: {
              type: 'object', required: ['status'],
              properties: { status: { enum: ['done', 'partial', 'failed', 'skipped'] }, reason: { type: 'string' },
                assets: { type: 'array', items: { type: 'string' } } } } }
        ).catch(e => ({ status: 'failed', reason: 'art error: ' + String(e), assets: [] }))
      : Promise.resolve({ status: 'skipped', reason: '纯逻辑任务无美术轨', assets: [] })

    const [impl, test, art] = await Promise.all([workerA, workerB, workerC])
    if (impl.status === 'blocked') {
      log(`TASK ${id} 实现硬阻塞(未锁 bundle/IAP/push)→ blocked,不推进。reason=${impl.reason}`)
      return { id, status: 'blocked', stage: 'Implement', reason: impl.reason, frozen, impl, test, art }
    }
    return { id, frozen, impl, test, art }
  },

  // ───────── 每 TASK · Phase 2「Test-Loop」(loop-until-converge,单 agent for + 熔断,复用 design-restore 判据)─────────
  async (carry) => {
    if (carry.status === 'blocked') return carry
    const { id, frozen } = carry
    const rounds = []
    let prevFail = Infinity, stop = 'fuse_3_rounds'
    for (let r = 1; r <= K_ROUNDS; r++) {
      const round = await agent(
        `TASK=${id} 第 ${r} 轮。跑测试套件(单元+集成+E2E,适配项目命令)。返回 pass_count/fail_count/score(=fail 数)/failures[]。
         若 r>1 且仍有 fail:只针对 failures[] 做最小修复再准备复测(不顺手重构、不扩范围),修复仍限 FILES=${JSON.stringify(frozen.files)}。`,
        { label: `testloop:${id}#${r}`, phase: 'Test-Loop', schema: {
            type: 'object', required: ['pass_count', 'fail_count', 'score'],
            properties: { pass_count: { type: 'integer' }, fail_count: { type: 'integer' },
              score: { type: 'number' }, failures: { type: 'array', items: { type: 'string' } } } } }
      ).catch(e => ({ pass_count: 0, fail_count: prevFail === Infinity ? 99 : prevFail, score: prevFail === Infinity ? 99 : prevFail, failures: ['loop error: ' + String(e)] }))
      rounds.push({ round: r, ...round })
      if (round.fail_count === 0) { stop = 'converged'; break }
      // loop-until-converge:fail 数单调降才继续;不降即停(不为压绿死磕)
      if (round.score >= prevFail) { stop = 'score_not_monotonic'; break }
      prevFail = round.score
    }
    const last = rounds[rounds.length - 1]
    const converged = stop === 'converged'
    if (!converged) {
      // 软熔断:本 TASK 跳过,记 status;连 2 软熔断 → 硬熔断(在 pipeline 外用 softFuseStreak 维持,见下)
      log(`TASK ${id} Test-Loop 未收敛 stop=${stop} → 软熔断候选(fail=${last ? last.fail_count : '?'})`)
      return { id, status: 'soft_fuse', stage: 'Test-Loop', stop_reason: stop, frozen, rounds, ...carry }
    }
    return { id, frozen, rounds, stop_reason: stop, converged: true, impl: carry.impl, test: carry.test, art: carry.art }
  },

  // ───────── 每 TASK · Phase 3「Adversarial-Review + Gate」(parallel critic + 确定性闸门 commit)─────────
  async (carry) => {
    if (carry.status === 'blocked') return carry
    if (carry.status === 'soft_fuse') {
      // 软熔断处理:计数 + 写 status 跳过;连 2 软熔断 → 硬熔断停等人(由顶层在 pipeline 收尾判,见返回结构)
      softFuseStreak += 1
      const hard = softFuseStreak >= SOFT_FUSE_LIMIT
      await agent(
        `TASK=${carry.id} 三轮 fix→retest 未转绿(stop=${carry.stop_reason})→ 软熔断。
         用 Bash 把本 TASK 在 ${ROOT}/docs/status.md 记为软熔断跳过(写明轮次与剩余 failures),不要 commit 半成品代码。`,
        { label: `softfuse:${carry.id}`, phase: 'Adversarial-Review+Gate', schema: {
            type: 'object', required: ['recorded'], properties: { recorded: { type: 'boolean' } } } }
      ).catch(() => ({ recorded: false }))
      log(`TASK ${carry.id} 软熔断已记;softFuseStreak=${softFuseStreak}${hard ? ' → 硬熔断:停等人' : ''}`)
      return { id: carry.id, status: hard ? 'hard_fuse' : 'soft_fuse', stage: 'Test-Loop', stop_reason: carry.stop_reason }
    }
    softFuseStreak = 0   // 一旦有 TASK 正常通过,软熔断连击清零
    const { id, frozen, impl } = carry
    const A = frozen.accept, F = frozen.files, P = frozen.platform

    // 对抗验证:两个 critic 并行,独立于实现者
    const critic1 = agent(
      `critic-1(独立于实现者)。用 Bash 取 \`git diff\`,对照 FROZEN ACCEPT=${JSON.stringify(A)} 与【禁止模式表】挑刺:
       预建抽象(只一个实现者却造接口/基类/工厂)/ 幽灵依赖(依赖清单冒出任务没要求的条目)/ 防御性冗余(同检查 >1 层重复无跨层契约)/ 范围蠕变(改动删掉验收仍通过)。
       逐条给 severity(P0|P1|P2)+ 文件位置。返回 findings[]。`,
      { label: `critic1:${id}`, phase: 'Adversarial-Review+Gate', schema: {
          type: 'object', required: ['findings'],
          properties: { findings: { type: 'array', items: { type: 'object', required: ['severity', 'desc'],
            properties: { severity: { enum: ['P0', 'P1', 'P2'] }, desc: { type: 'string' }, file: { type: 'string' } } } } } } }
    ).catch(e => ({ findings: [{ severity: 'P0', desc: 'critic1 error: ' + String(e) }] }))

    const critic2 = agent(
      `critic-2(stub/mock 审,独立于实现者)。用 Bash 扫 \`git diff\`:① 静默降级(返假数据不报错不记日志)= P0;
       ② 每个 optimistic 项(impl 自报=${JSON.stringify(impl.optimistic || [])})是否都在 ${ROOT}/docs/status.md 有记录且指明被替换的文件路径,缺记录 = P0;
       ③ 未声明的 mock/stub(不含 Mock/Stub/Placeholder/Fake 命名、无 MOCK_* 门控、不在 STUB_REMAINING) = P0。返回 findings[]。`,
      { label: `critic2:${id}`, phase: 'Adversarial-Review+Gate', schema: {
          type: 'object', required: ['findings'],
          properties: { findings: { type: 'array', items: { type: 'object', required: ['severity', 'desc'],
            properties: { severity: { enum: ['P0', 'P1', 'P2'] }, desc: { type: 'string' }, file: { type: 'string' } } } } } } }
    ).catch(e => ({ findings: [{ severity: 'P0', desc: 'critic2 error: ' + String(e) }] }))

    const [c1, c2] = await Promise.all([critic1, critic2])
    const p0 = [...(c1.findings || []), ...(c2.findings || [])].filter(f => f.severity === 'P0')
    if (p0.length) {
      // 有 P0 → 有限回灌(非无限):本 TASK 让 agent 按 findings 修一轮再过闸门
      log(`TASK ${id} 对抗 review 有 ${p0.length} 个 P0 → 有限回灌修复一轮`)
      await agent(
        `TASK=${id}。按以下 P0 findings 修复(只改 FILES=${JSON.stringify(F)},不扩范围):${JSON.stringify(p0)}。
         修完准备过确定性闸门。返回 fixed=true/false。`,
        { label: `refix:${id}`, phase: 'Adversarial-Review+Gate', schema: {
            type: 'object', required: ['fixed'], properties: { fixed: { type: 'boolean' } } } }
      ).catch(() => ({ fixed: false }))
    }

    // 唯一写 state 的点:agent 收束 → 用 Bash 调既有确定性脚本落闸门 state JSON(勿改 key)+ commit + status.md + skill-signal
    const gateAndCommit = await agent(
      `TASK=${id} PLATFORM=${P}。对抗 review 已过,现用【确定性脚本】落闸门并收尾(严禁手写 state JSON——和闸门 key 错位即整关失效)。
       FROZEN FILES=${JSON.stringify(F)}。用 Bash 跑(脚本在 ${ROOT}/scripts/ 或本 skill 仓 scripts/;先 \`head\` 读 usage 再按参数跑):
       1) scope 闸门:改动 ⊆ FILES 且 PLATFORM 隔离 —— pre-commit-scope.sh(若仓内无独立文件,用 \`bash ${ROOT}/scripts/app-gate.sh app-gate build\` 等价校验)。
       2) bundle 一致:\`bash ${ROOT}/scripts/app-gate.sh\` 触发 sg_app_bundle_coherence(bundle id 跨文件一致 + 禁 \${VAR}/$(...) 变量拼接)。
       3) stub-scan:无未声明 mock 残留。
       4) 全过后 git commit(信息含 TASK 编号,ai-rules 已授权自动 commit)+ 按 DONE-TEMPLATE 更新 ${ROOT}/docs/status.md(任务 [x] + TESTS/SMOKE/STUB_REMAINING/PENDING_CONFIRM/COMMIT)。
       5) 写 ${ROOT}/.claude/state/skill-signal.json {"skill":"build","epoch":<unix秒>}。
       6) 终检:\`bash ${ROOT}/scripts/app-gate.sh app-gate build\`(及 stop-app-audit 若存在)做 OUTPUT_GATE。
       任一闸门不过 → 返回 gate_pass=false + 把 stderr 放 reason,不要硬 commit。返回 commit hash。`,
      { label: `gate-commit:${id}`, phase: 'Adversarial-Review+Gate', schema: {
          type: 'object', required: ['gate_pass'],
          properties: { gate_pass: { type: 'boolean' }, reason: { type: 'string' },
            commit: { type: 'string' }, status_updated: { type: 'boolean' } } } }
    ).catch(e => ({ gate_pass: false, reason: 'gate/commit error: ' + String(e) }))

    if (!gateAndCommit.gate_pass) {
      log(`TASK ${id} OUTPUT_GATE 不过 → blocked。reason=${gateAndCommit.reason}`)
      return { id, status: 'gate_blocked', stage: 'Adversarial-Review+Gate', reason: gateAndCommit.reason,
               critics: { c1: c1.findings, c2: c2.findings } }
    }
    log(`完成: ${id} 已实现并 commit(${gateAndCommit.commit || 'n/a'}),测试 PASS。`)
    return { id, status: 'done', commit: gateAndCommit.commit, status_updated: gateAndCommit.status_updated,
             critics: { c1: c1.findings, c2: c2.findings } }
  }
)

// ── pipeline 尾标记(沿用 SKILL.md 三态:完成 / 检查点 / 阻塞)──
const done = results.filter(r => r && r.status === 'done')
const blocked = results.filter(r => r && (r.status === 'blocked' || r.status === 'gate_blocked'))
const softFused = results.filter(r => r && r.status === 'soft_fuse')
const hardFused = results.filter(r => r && r.status === 'hard_fuse')

let tail
if (hardFused.length) {
  tail = `等人: 连续 ${SOFT_FUSE_LIMIT} 个软熔断 → 硬熔断,停下等人介入(见 ${hardFused.map(r => r.id).join(', ')})`
} else if (blocked.length || softFused.length) {
  tail = `检查点/阻塞: done=${done.length} blocked=${blocked.map(r => r.id).join(',') || '-'} soft_fuse=${softFused.map(r => r.id).join(',') || '-'}`
} else {
  const lastId = done.length ? done[done.length - 1].id : '?'
  tail = `完成: ${lastId} 已实现并 commit,测试 PASS;全部未完成 TASK 处理完毕`
}
log(tail)

return { status: hardFused.length ? 'hard_fuse' : (blocked.length || softFused.length ? 'partial' : 'done'),
         done: done.map(r => r.id), blocked: blocked.map(r => r.id),
         soft_fuse: softFused.map(r => r.id), hard_fuse: hardFused.map(r => r.id),
         tail, results }
