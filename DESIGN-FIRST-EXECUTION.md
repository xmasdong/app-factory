# DESIGN-FIRST-EXECUTION — 实际执行手册

> 这是 design-first 的 **执行手册（怎么动手跑）**，不是 `ROADMAP-design-first.md`（那是设计/为什么这么定）。
> 读这份是为了：装好依赖 → 从「我手上有一张设计稿」一路跑到「app + 后端能跑」→ 用闸门验收。
> 务实、真命令、可复制粘贴。所有路径用绝对路径或 `$ROOT`（= `CLAUDE_PROJECT_DIR`）。

---

## 0. 三句话先讲清

1. **真 app 跑 design-restore / backend-forge，不要走 SKILL.md 里那套线性 Step**。线性 Step 只是「单 agent 降级档」（没装 workflow、或调试单点时用）。真跑用 `Workflow 工具(AI 调用·非CLI) scripts/design-first/<skill>.workflow.js` 编排。
2. **为什么主路径是 Workflow 多 agent 编排（推荐用户开 ultracode）**：单 agent 顺序做不到「每个 endpoint / 每屏全覆盖 + 对抗验证 + 收敛环」这种质量与覆盖；ultracode 只是让 AI 默认倾向调 Workflow 工具,skill 强制不了用户会话模式（见 §3）。
3. **唯一对外接口是 4 个 state JSON**：编排跑完，闸门 `app-gate.sh` 只读这 4 个文件验收。脚本写 JSON 的 key 必须逐字对齐（见 §4），写错一个 key 整关失效。

两条真相源（FROZEN，下游全派生）：

- `api/openapi.yaml`（OpenAPI 3.1）—— 后端真相源（backend-forge 产）
- `docs/design/design-manifest.json` + `docs/design/tokens.json` —— 前端真相源（design-restore 产）

---

## 1. 前置依赖（装什么）

### 1.1 运行时

| 工具 | 版本 / 来源 | 用途 |
|---|---|---|
| node | ≥ 20（本机实测 v26 OK） | 跑 `.workflow.js` |
| claude（Claude Code） | 已装 | 提供 **Workflow 工具**(AI 调用·非 CLI)做 ultracode 编排 |
| jq | brew 自带 / `/usr/bin/jq` | 闸门解析 state JSON（**验收必需**） |

### 1.2 npm（在目标项目根装为 devDeps）

```bash
# 视觉 diff + 结构 diff（design-restore 的 screen worker 用）
npm i -D pixelmatch pngjs image-ssim
# 渲染截图（每屏渲染，用 manifest 同一 DPR）
npm i -D playwright && npx playwright install chromium
# 设计 token 出各端
npm i -D style-dictionary
# OpenAPI 校验 / lint（backend-forge 的 SSOT 阶段用）
npm i -D @redocly/cli
# DTO / SDK codegen（endpoint worker 的可靠区）
npm i -D openapi-typescript
npm i -g @openapitools/openapi-generator-cli   # 需要 Java 运行时
# OpenAPI mock（schemathesis 的 base-url，没真后端时用）
npm i -g @stoplight/prism-cli
```

> 注：`prism` 与 `openapi-generator-cli` 是全局工具，CI 里改成 `npx` 调亦可。`openapi-generator-cli` 依赖 JRE（`java -version` 要能跑），只生成 DTO/SDK 时不强制，`openapi-typescript` 已够前端用。

### 1.3 pip（契约测试）

```bash
pip install schemathesis        # endpoint worker 的契约测试夹1（本机当前未装，必须先装）
# 验证
schemathesis --version
```

### 1.4 supabase（后端落地，可选但推荐）

```bash
# 无需全局装，npx 即用：
npx supabase --version
npx supabase init           # 在项目根生成 supabase/ 目录
npx supabase start          # 起本地 Postgres + Auth + REST（Docker 必须在跑）
# migration（endpoint worker 产的 RLS/表结构落这里）
npx supabase migration new <name>
npx supabase db reset       # 应用所有 migration 到本地
```

### 1.5 一次性体检脚本

```bash
node --version; claude --version; jq --version
schemathesis --version || echo "缺 schemathesis：pip install schemathesis"
npx pixelmatch --help >/dev/null 2>&1 || echo "缺 pixelmatch：npm i -D pixelmatch pngjs"
npx prism --version 2>/dev/null || echo "缺 prism：npm i -g @stoplight/prism-cli"
npx supabase --version 2>/dev/null || echo "supabase 用 npx 即可"
```

---

## 2. 端到端实跑（从一张设计稿到 app+后端可跑）

> 假设：脊柱已到 shape 关，`PROJECT_DIR` 是你的业务项目根（不是 app-factory 仓库本身）。
> app-factory 仓库只提供脚本，**跑时在业务项目根跑**，靠 `CLAUDE_PROJECT_DIR` 指过去。

### Step A — 进项目根 + 锁定 ROOT

```bash
cd /path/to/your-app          # 业务项目根（有 docs/ api/ .claude/ 的那个）
export CLAUDE_PROJECT_DIR=$PWD   # 关键！脚本的 ROOT = 这个；不 export 会落到 cwd 写错位置
mkdir -p "$CLAUDE_PROJECT_DIR/.claude/state" "$CLAUDE_PROJECT_DIR/api" "$CLAUDE_PROJECT_DIR/docs/design"
```

### Step B — 把设计稿摆好（design-restore 的输入）

design-restore 的 Extract phase 会读你的设计源（`.pen` / Figma 导出 / 截图）。把设计稿放进项目，shape 关已产的 `docs/spec.md`（§数据契约 + screens）也要在位。确认：

```bash
ls "$CLAUDE_PROJECT_DIR/docs/spec.md"           # 后端 SSOT 的依据
ls "$CLAUDE_PROJECT_DIR/docs/design/"           # 设计稿源放这里
```

### Step C — 跑 design-restore 编排（设计 → 高保真前端）

```bash
# AI 调用 Workflow 工具(Claude Code 内置·非 shell CLI),script 取以下文件内容: \
  /Users/xmasdong/opc/app-factory/scripts/design-first/design-restore.workflow.js
```

产出（编排自动写）：

- `docs/design/design-manifest.json`、`docs/design/tokens.json`、`docs/design/baseline/<platform>/<viewport>/<screen>.png`
- `.claude/state/ui-diff.json`、`.claude/state/token-match.json`

### Step D — 跑 backend-forge 编排（功能/契约 → 后端 API）

```bash
# 没真后端时，先用 prism 起 mock 当契约测试的 base-url：
npx prism mock "$CLAUDE_PROJECT_DIR/api/openapi.yaml" --port 4010 &   # openapi 已存在才起；首跑可在 SSOT phase 后再起
export TEST_API=http://127.0.0.1:4010

# AI 调用 Workflow 工具(Claude Code 内置·非 shell CLI),script 取以下文件内容: \
  /Users/xmasdong/opc/app-factory/scripts/design-first/backend-forge.workflow.js
```

产出：

- `api/openapi.yaml`（SSOT，OpenAPI 3.1）
- `.claude/state/contract-test.json`、`.claude/state/e2e-contract.json`

> 上线前要对**真后端**复跑（把 `TEST_API` 指向真 API，target 才会写 `real`）：
> ```bash
> npx supabase start && export TEST_API=$(npx supabase status -o json | jq -r '.API_URL')
> # AI 调用 Workflow 工具(Claude Code 内置·非 shell CLI),script 取以下文件内容: /Users/xmasdong/opc/app-factory/scripts/design-first/backend-forge.workflow.js
> ```

### Step E — 编排内部真命令（agent 在 worker 里实际调的）

这些命令不用你手敲，是 worker agent 在循环里跑的；列出来便于你 debug 单点：

```bash
# 契约测试（endpoint worker 夹1）：
schemathesis run "$CLAUDE_PROJECT_DIR/api/openapi.yaml" \
  --base-url "$TEST_API" --checks all --hypothesis-max-examples 50

# 视觉 diff（screen worker loop 内）：
npx pixelmatch render.png baseline.png diff.png 0.1

# OpenAPI lint（SSOT 定稿前）：
npx redocly lint "$CLAUDE_PROJECT_DIR/api/openapi.yaml"

# DTO codegen（endpoint worker 可靠区）：
npx openapi-typescript "$CLAUDE_PROJECT_DIR/api/openapi.yaml" -o src/api/types.ts
```

### Step F — 闸门验收

```bash
bash /Users/xmasdong/opc/app-factory/scripts/app-gate.sh build
bash /Users/xmasdong/opc/app-factory/scripts/app-gate.sh qa

# 手验 JSON 形状对齐闸门解析：
jq '.mismatch, (.per_screen|length)'                       "$CLAUDE_PROJECT_DIR/.claude/state/ui-diff.json"
jq '.hardcoded_count, .mismatched_count'                   "$CLAUDE_PROJECT_DIR/.claude/state/token-match.json"
jq '.target, .result, (.failures|length)'                  "$CLAUDE_PROJECT_DIR/.claude/state/contract-test.json"
jq '.result, (.missing_fields|length), (.extra_fields|length)' "$CLAUDE_PROJECT_DIR/.claude/state/e2e-contract.json"
```

通过判据（来自 `app-gate.sh` 现有实现）：

- `ui-diff.json` `.mismatch`：≤3 pass / 3–8 WARN / >8 FAIL
- `token-match.json`：`hardcoded_count>0` 或 `mismatched_count>0` 即 FAIL
- `contract-test.json`：`result!=PASS` FAIL；`result=PASS` 但 `target=mock` → 点名「real 后端尚未验证」（advisory，不阻塞，但提示）
- `e2e-contract.json`：`missing_fields` 或 `extra_fields` 任一非空 → 判 drift FAIL；`result` 非 PASS FAIL

---

## 3. 主路径=AI 调用 Workflow 工具编排（写死）；推荐用户开 ultracode；降级=单 agent

> ⚠️ **核心澄清**:ultracode/Workflow 是 **Claude Code 会话内的【工具】**,由 **AI 调用**(传 `script` 参数)——**没有 `claude workflow` shell 命令**(本机 `claude --help` 无此子命令)。本文出现的"运行 xxx.workflow.js"一律指:**AI 调用 Workflow 工具,把该 .js 文件内容作为 `script` 传入**。`.workflow.js` 文件是仓库里留存的编排脚本源,供 AI 读取后传给工具;脚本内 agent 再用 Bash 调 `scripts/design-first/` 下的确定性脚本产出 state JSON。

### 3.1 为什么主路径是 Workflow 编排（推荐 ultracode），单 agent 仅降级

| 质量维度 | 单 agent 顺序做（降级档） | Workflow 多 agent 编排（主路径） |
|---|---|---|
| **全覆盖** | 顺序写到第 8 个 endpoint 时上下文已满，前面的覆盖会被遗忘/糊弄 | `parallel` 按 endpoint / 按屏×视口扇出，每个 worker 独立上下文，**N 个全跑到** |
| **对抗验证** | 自问自答 = 回声室，自己写的规则自己说对 | `parallel` 起 N 个独立 skeptic，各自不看彼此结论，多数票才留 |
| **收敛** | 一遍过，diff 不达标也没有再修一轮的机制 | screen worker 内 `for` 循环 + 单调降判据 + k 轮熔断，**修到收敛或停** |
| **完整性核对** | 没有「谁来检查我漏了没」 | Synthesis phase 的 completeness critic 专门核覆盖再写 state |

四个 Workflow 编排模式在脚本里的归位：

- **fan-out 全覆盖** = `parallel(endpoints)` / `parallel(screen × viewport)`
- **adversarial verify** = `parallel(N skeptic)` 多数投票
- **loop-until-converge** = screen worker 内 `for` + 单调降判据 + k 轮熔断
- **completeness critic** = Synthesis phase 单 agent 核覆盖再写 state JSON（**唯一写闸门 JSON 的点**，保证 key 严格对齐）

### 3.2 Workflow runtime API（来自 whatfish/app_build.workflow.js 实测形状）

- 顶层 `export const meta = { name, description, phases:[{title,detail}] }`
- 脚本体是顶层 await 脚本，可直接调全局：
  - `phase(title)` —— 切阶段
  - `parallel(fns[])` —— 数组里每个 `()=>Promise` 并发跑，返回结果数组
  - `agent(prompt, {label, phase, schema})` —— 起一个子 agent，`schema` 是 JSON Schema，agent 必须按 schema 返回结构化对象
  - `pipeline` 用 `for await` / 顺序 `await` 串 agent 实现（前一步输出喂下一步）
- 每个 `agent()` / worker **必须 `.catch(e=>fallback)`** 兜底成符合 schema 的对象，否则一个崩了整个 `parallel` reject、其它已完成工作全丢
- 最后 `return {...}` 汇总

### 3.3 模板一：backend-forge.workflow.js（按 endpoint 扇出 + 对抗验证）

```js
export const meta = {
  name: 'backend-forge-orchestrated',
  description: 'openapi SSOT → 按 endpoint 扇出(实现→契约→越权 pipeline)→ 业务规则对抗验证 → 汇总产 contract-test.json/e2e-contract.json',
  phases: [
    { title: 'OpenAPI-SSOT',      detail: 'single agent — 派生并定稿 api/openapi.yaml,扇出前唯一真相源' },
    { title: 'Per-Endpoint',      detail: 'parallel × endpoint — 每 endpoint 内部 pipeline:实现→契约测试→越权负向' },
    { title: 'Adversarial-Rules', detail: 'parallel × rule × N skeptic — 多数过才留(adversarial verify)' },
    { title: 'Synthesis',         detail: 'completeness critic — 核覆盖 + 写 contract-test.json/e2e-contract.json' },
  ],
}
const ROOT = process.env.CLAUDE_PROJECT_DIR || process.cwd()
const N_SKEPTIC = 3

// ── phase 1: openapi 先定稿(SSOT,扇出前必须存在,定稿后 FROZEN,worker 不许改)──
phase('OpenAPI-SSOT')
const ssot = await agent(
  `读 ${ROOT}/docs/spec.md §数据契约 + ${ROOT}/docs/design/design-manifest.json screens[]。
   screen→entity→endpoint 派生,inferred 字段标注。高风险字段落 format/enum(金额=分/时间=ISO8601/枚举全列)。
   每写端点声明 403+422。每 entity 建 ownership 越权矩阵行。
   写 ${ROOT}/api/openapi.yaml(OpenAPI 3.1)。返回 endpoint 列表 + ownership 矩阵行数 + 业务规则列表。`,
  { label:'ssot', phase:'OpenAPI-SSOT', schema:{ type:'object', required:['endpoints','ownership_rows'], properties:{
      endpoints:{type:'array',items:{type:'string'}}, ownership_rows:{type:'integer'},
      rules:{type:'array',items:{type:'string'}} } } }
)

// ── phase 2: 按 endpoint 扇出,每 endpoint 内部 pipeline(fan-out 全覆盖)──
phase('Per-Endpoint')
const perEndpoint = await parallel(ssot.endpoints.map(ep => () => (async () => {
  // pipeline 步1:生成实现(只引用 SSOT,不改 openapi)
  const impl = await agent(`endpoint=${ep}。从 ${ROOT}/api/openapi.yaml 该 path 生成实现:Supabase migration+RLS(ENABLE RLS,owner=auth.uid())、handler、zod/pydantic 校验、DTO。只引用 SSOT,不改 openapi。`,
    { label:`impl:${ep}`, phase:'Per-Endpoint', schema:{type:'object',properties:{status:{enum:['done','partial']},files:{type:'array',items:{type:'string'}}}} })
  // pipeline 步2:契约测试(吃步1输出)
  const contract = await agent(`endpoint=${ep} 实现已落(${JSON.stringify(impl.files)})。跑 schemathesis run ${ROOT}/api/openapi.yaml --base-url $TEST_API --checks all,只针对该 path。返回 result+failures。`,
    { label:`contract:${ep}`, phase:'Per-Endpoint', schema:{type:'object',required:['result'],properties:{result:{enum:['PASS','FAIL']},failures:{type:'array',items:{type:'string'}}}} })
  // pipeline 步3:越权负向(吃步1输出,A 取 B 必 403)
  const authz = await agent(`endpoint=${ep}。对 ownership 矩阵该行生成负向:A token 取 B 资源→必 403;无 token→401;A PATCH B→403 且 B 数据未变(读回验证)。返回 result+cases+failures。`,
    { label:`authz:${ep}`, phase:'Per-Endpoint', schema:{type:'object',required:['result','cases'],properties:{result:{enum:['PASS','FAIL']},cases:{type:'integer'},failures:{type:'array',items:{type:'string'}}}} })
  return { endpoint:ep, impl:impl.status, contract, authz }
})().catch(e => ({ endpoint:ep, impl:'partial', contract:{result:'FAIL',failures:[String(e)]}, authz:{result:'FAIL',cases:0,failures:[String(e)]} }))))

// ── phase 3: 业务规则对抗验证(N skeptic 并行独立,多数过才留)──(adversarial verify)
phase('Adversarial-Rules')
const ruleVerdicts = await parallel((ssot.rules||[]).map(rule => () => (async () => {
  const votes = await parallel(Array.from({length:N_SKEPTIC}, (_,i) => () =>
    agent(`你是 skeptic #${i+1}。独立质疑这条业务规则的实现是否对/边界是否漏:"${rule}"(来自 spec ACCEPT)。
           检查状态机非法转换/金额为负/余额穿透/满员后下单。只回 keep 或 kill + 一句理由。`,
      { label:`skeptic${i+1}:${rule.slice(0,20)}`, phase:'Adversarial-Rules', schema:{type:'object',required:['vote'],properties:{vote:{enum:['keep','kill']},why:{type:'string'}}} })
      .catch(()=>({vote:'kill',why:'skeptic error→保守 kill'}))))
  const keeps = votes.filter(v=>v.vote==='keep').length
  return { rule, verdict: keeps > N_SKEPTIC/2 ? 'keep' : 'kill', votes: votes.map(v=>v.vote), why: votes.map(v=>v.why).join(' | ') }
})()))

// ── phase 4: completeness critic + 写闸门 JSON(唯一写 state 的点)──
phase('Synthesis')
const synth = await agent(
  `完整性审查 + 写闸门 state(严格按 key)。输入:
   endpoints=${JSON.stringify(perEndpoint)}
   rules=${JSON.stringify(ruleVerdicts)}
   覆盖核对:每 endpoint 都有 contract+authz?越权用例数 = ownership 行数(${ssot.ownership_rows})?有 kill 规则要上报?
   写 ${ROOT}/.claude/state/contract-test.json = {target:(base-url 是 prism→'mock' 否则'real'), result:(任一 contract/authz FAIL→'FAIL' 否则'PASS'), failures:[{endpoint,check,detail}]}
   写 ${ROOT}/.claude/state/e2e-contract.json = {result:(业务 ACCEPT 链路冒烟 PASS/FAIL), missing_fields:[openapi 声明但响应缺], extra_fields:[响应有但未声明]}
   返回写入摘要 + 未覆盖项(gaps)。`,
  { label:'critic', phase:'Synthesis', schema:{type:'object',required:['contract_test','e2e_contract','gaps'],properties:{
      contract_test:{type:'object'}, e2e_contract:{type:'object'}, gaps:{type:'array',items:{type:'string'}} } } }
)
return { ssot, perEndpoint, ruleVerdicts, synth }
```

### 3.4 模板二：design-restore.workflow.js（按屏 loop-until-converge）

```js
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
const VIEWPORTS = ['iPhone-390x844','Android-360x800']
const PLATFORM = 'SwiftUI'

// ── phase 1: 抽取 manifest(扇出前唯一输入;DPR 记进 manifest,渲染必须同一 DPR)──
phase('Extract')
const extract = await agent(
  `三管线(pen/figma/screenshot)归一。先抽 token(最确定)→ ${ROOT}/docs/design/tokens.json(DTCG,每 token confidence)。
   抽屏清单+组件+逐屏布局树,inferred 标注。导 baseline PNG 到 ${ROOT}/docs/design/baseline/<platform>/<viewport>/<screen>.png(DPR 记进 extraction_meta.dpr)。
   写 ${ROOT}/docs/design/design-manifest.json。返回 screens[] + dpr。`,
  { label:'extract', phase:'Extract', schema:{ type:'object', required:['screens','dpr'], properties:{
      screens:{type:'array',items:{type:'string'}}, dpr:{type:'number'} } } }
)

// ── phase 2: 按屏 × 视口扇出,每 worker 内 loop-until-converge(fan-out + loop)──
phase('Per-Screen')
const combos = extract.screens.flatMap(s => VIEWPORTS.map(v => ({ screen:s, viewport:v })))
const perScreen = await parallel(combos.map(({screen,viewport}) => () => (async () => {
  const rounds = []
  let prevScore = Infinity, stop = 'fuse_3_rounds'
  for (let r = 1; r <= K_ROUNDS; r++) {
    const round = await agent(
      `屏=${screen} 视口=${viewport} 第 ${r} 轮。用 dpr=${extract.dpr} 同一 DPR 渲染→截图。mask 动态区(动画/头像/时间戳)。
       pixelmatch+SSIM vs baseline。token 对账(computed style vs tokens.json)。VLM 定位残差。局部重生修最差区。
       返回 diff_ratio/ssim/token_mismatch/vlm_severity/score(加权)。`,
      { label:`${screen}@${viewport}#${r}`, phase:'Per-Screen', schema:{type:'object',required:['score','diff_ratio','ssim','token_mismatch'],properties:{
          diff_ratio:{type:'number'}, ssim:{type:'number'}, token_mismatch:{type:'integer'}, vlm_severity:{enum:['none','minor','major']}, score:{type:'number'} }} }
    ).catch(e => ({ score: prevScore, diff_ratio:1, ssim:0, token_mismatch:99, vlm_severity:'major', _err:String(e) }))
    rounds.push({ round:r, ...round })
    // loop-until-converge:单调降才继续,不降即停(别死磕烧 token)
    if (round.score >= prevScore) { stop = 'score_not_monotonic'; break }
    prevScore = round.score
    if (round.diff_ratio*100 <= 3 && round.token_mismatch === 0) { stop = 'converged'; break }
  }
  const last = rounds[rounds.length-1]
  return { screen, viewport, platform:PLATFORM, rounds, stop_reason:stop,
           mismatch: Math.round((last.diff_ratio||0)*100), token_mismatch:last.token_mismatch||0, converged: stop==='converged' }
})().catch(e => ({ screen, viewport, stop_reason:'fuse_3_rounds', mismatch:100, token_mismatch:99, converged:false }))))

// ── phase 3: completeness critic + 写闸门 JSON ──
phase('Synthesis')
const synth = await agent(
  `完整性审查 + 写闸门 state(严格按 key)。输入 perScreen=${JSON.stringify(perScreen)}。
   核对:每 (屏×视口) 都跑了 pixelmatch+SSIM+token 对账?动态区都 mask?有屏未收敛(stop_reason≠converged)需上报?
   写 ${ROOT}/.claude/state/ui-diff.json = {mismatch:(所有 per_screen.mismatch 取最大), per_screen:[{screen,mismatch}]}
   写 ${ROOT}/.claude/state/token-match.json = {hardcoded_count:(实现处硬编码字面量数), mismatched_count:(sum token_mismatch), details:[{file,line,value,reason}]}
   返回写入摘要 + halted(未收敛屏)。`,
  { label:'critic', phase:'Synthesis', schema:{type:'object',required:['ui_diff','token_match','halted'],properties:{
      ui_diff:{type:'object'}, token_match:{type:'object'}, halted:{type:'array',items:{type:'string'}} } } }
)
return { extract, perScreen, synth }
```

> 这两段同时写进对应 `skills/backend-forge/SKILL.md`、`skills/design-restore/SKILL.md` 的新章节 `## 主执行路径:AI 调用 Workflow 工具编排（推荐用户开 ultracode;降级=单 agent 顺序）`，并在执行计划顶部加一句：
> 「真 app 跑时不走线性 Step，主路径 = AI 调用 Workflow 工具(非 shell CLI),script 取 `scripts/design-first/<skill>.workflow.js` 内容；推荐用户开 ultracode 模式;线性 Step 仅作单 agent 降级档。」

---

## 4. state JSON schema × 产出脚本 × 闸门读取（对照表）

| state 文件 | schema（严格 key） | 哪个脚本/phase 产 | 哪个闸门函数读 | 判据 |
|---|---|---|---|---|
| `.claude/state/ui-diff.json` | `{ mismatch:<int 0-100,所有屏最大>, per_screen:[{screen,mismatch:<int>}] }` | design-restore `Synthesis` critic | `sg_app_ui_visual_diff`（读 `.mismatch`，fallback `.max_mismatch`） | ≤3 pass / 3–8 WARN / >8 FAIL |
| `.claude/state/token-match.json` | `{ hardcoded_count:<int>, mismatched_count:<int>, details:[{file,line,value,reason}] }` | design-restore `Synthesis` critic | `sg_app_design_token_match`（读 `.hardcoded_count`/`.mismatched_count`） | 任一 >0 即 FAIL |
| `.claude/state/contract-test.json` | `{ target:'mock'\|'real', result:'PASS'\|'FAIL', failures:[{endpoint,check,detail}] }` | backend-forge `Synthesis` critic | `sg_app_contract_test`（读 `.target`/`.result`） | `result!=PASS` FAIL；PASS 但 `target=mock` → 点名 real 未验证（advisory） |
| `.claude/state/e2e-contract.json` | `{ result:'PASS'\|'FAIL', missing_fields:[...], extra_fields:[...] }` | backend-forge `Synthesis` critic | `sg_app_e2e_contract_smoke`（读 `.result`/`.missing_fields`/`.extra_fields`） | `missing_fields` 或 `extra_fields` 非空 → drift FAIL；`result` 非 PASS FAIL |

桥产物（非 state，但脚本读/写固定路径）：

| 文件 | 谁产 | 谁读 |
|---|---|---|
| `api/openapi.yaml`（OpenAPI 3.1，SSOT） | backend-forge `OpenAPI-SSOT` phase | 所有 endpoint worker + schemathesis + codegen |
| `docs/design/design-manifest.json` | design-restore `Extract` phase | 所有 screen worker + backend-forge SSOT（screens→entity） |
| `docs/design/tokens.json`（DTCG） | design-restore `Extract` phase | screen worker token 对账 + style-dictionary |
| `docs/design/baseline/<platform>/<viewport>/<screen>.png` | design-restore `Extract` phase | screen worker 的 pixelmatch baseline |

**关键不变量：critic（Synthesis phase 的单 agent）是唯一写 state JSON 的点**。worker 只返回结构化结果，critic 聚合后按上表 key 逐字写盘。这保证 key 永远对齐 `app-gate.sh`，并发 worker 不会互相覆盖 state。

---

## 5. 高频坑（踩了整关失效，逐条记住）

1. **闸门 key 逐字对齐**：`ui-diff.json` 顶层是 `.mismatch`（不是 `max_mismatch`，虽有 fallback）且 `per_screen[].mismatch` 是 int；`token-match.json` 是 `hardcoded_count`/`mismatched_count`（>0 即 FAIL）；`contract-test.json` 的 `target` 只能 `mock`/`real`（mock 时即使 PASS 也会被点名 real 未验证）；`e2e-contract.json` 的 `missing_fields`/`extra_fields` 任一非空直接判 drift，别塞无关字段。
2. **openapi 先定稿再扇出**：endpoint 扇出从已写盘的 `api/openapi.yaml` 解析 path，扇出过程中**不许改 SSOT**（并行 worker 同时改 openapi.yaml 会互相覆盖）。要改字段回 `/shape` 重算，SSOT 是 FROZEN。
3. **对抗验证别做成自问自答**：N 个 skeptic 必须 `parallel` 独立 prompt（各自不看彼此结论），否则是回声室不是对抗。skeptic 出错保守投 `kill`（宁漏留也别假阳性留错规则）。
4. **loop 停止判据是「分数单调降才继续」**，不是「过阈值才停」：`score_N >= score_{N-1}` 立即停（`stop_reason='score_not_monotonic'`），别为压 mismatch≤3 无脑死磕（烧 token 且可能越改越坏）。`k=3` 轮硬熔断。
5. **DPR 不一致是纯像素 diff 误杀 30–40% 的头号原因**：baseline 导出 DPR 必须记进 `manifest.extraction_meta.dpr`，screen worker 渲染用同一 DPR。动态区（动画/头像/时间戳）diff 前必须 mask，否则假阳性爆表。
6. **每个 worker 必须 `.catch` 兜底成符合 schema 的 fallback**（见 whatfish 脚本模式），否则一个 endpoint/屏崩了整个 `parallel` reject、其它已完成工作全丢。
7. **越权负向用例数 = ownership 矩阵行数**（critic 要核这个数）：A 取 B 资源期望严格 403（不是 200 空、不是 404 混淆、不是 500）；越权写还要读回验证 B 数据未变。
8. **`CLAUDE_PROJECT_DIR` 必须 export 指向目标项目根**，否则 ROOT 落到 cwd，state JSON 写错位置闸门读不到。脚本随 app-factory 仓库分发，但**跑时在各业务项目根跑**。
9. **schemathesis 的 target 别谎报**：对 prism mock 跑 → `target='mock'`（gate 提醒上线前对 real 复跑）；只有对真后端跑过才填 `target='real'`。
10. **schemathesis 必须先 `pip install`**（本机当前未装）；`openapi-generator-cli` 依赖 JRE，只生成 TS DTO 用 `openapi-typescript` 即可绕过 Java。
