# WORKFLOWS — app-factory 怎么借助 ultracode + Claude 内置 Workflow 工具做编排

> 本文说明 app-factory 各 skill 如何引导 AI 用 Claude 内置 Workflow 工具编排。读完你应该清楚:谁开 ultracode、AI 怎么编排、哪些关备有 `.workflow.js` 编排蓝图参考、不开会怎样、为什么编排不是装饰。Workflow 工具归 Claude,本项目不定义、不拥有任何 workflow 运行时。
> 一句话先记住:**借 Claude 内置 Workflow 工具做编排,是 app-factory 完成复杂需求的主路径,不是可选加分项。** 能在「真覆盖 + 真对抗 + 单点写闸门」上站住的根本原因,是 AI 在 ultracode 下用 Claude 内置 Workflow 工具、按各 skill 的编排意图现场组合并执行 script,而不是本项目自有的 workflow 系统;不开编排只是退到「能跑但慢且对抗弱」的兜底形态。

---

## ① 正确模型(先把这三个东西分清,后面全靠它)

很多混乱来自把「会话模式」「AI 的工具」「skill」搅在一起。它们是三层不同的东西:

| 概念 | 它是什么 | 谁控制它 | 关键事实 |
|---|---|---|---|
| **ultracode** | 用户开启的 Claude Code **会话「高级模式」** | **用户**(手动开) | skill / 脚本**开不了**它。它只是让 AI **默认倾向**用 Claude 内置 Workflow 工具做多 agent 编排。 |
| **Workflow** | Claude Code / ultracode 的**内置【工具】**(归 Claude,**非本项目**) | **AI** 调用 | AI 调用它时,由 AI **现场写** `script`(用 `meta`/`phase`/`parallel`/`pipeline`/`agent({schema})` 等编排原语)并执行;script **不是**从本仓某文件加载来跑的。 |
| **skill** | 一个 SKILL.md + 配套脚本的能力包 | 仓库里写死 | 只能用自然语言**描述编排意图/形状**、**指示** AI 去调 Claude 内置 Workflow 工具、**推荐**用户开 ultracode、给**降级**路径。skill **不提供可执行 workflow,不运行 workflow**。 |

**skill 能做的,只有这四件:**
1. 用自然语言**描述编排意图/形状**(扇出哪些子任务、parallel/pipeline、对抗验证什么、loop 到什么条件、各 agent 干啥、产物落哪);可附 `*.workflow.js` 作为**【编排蓝图参考/示例】**(展示推荐扇出结构,供 AI/人参考),它**不是**传给工具去跑的可执行脚本;
2. 在 SKILL.md 写明「执行本 skill 时,AI(在 ultracode 下)用 Claude 内置 Workflow 工具,按本 skill 描述的编排意图**现场组合** script 并执行;`.workflow.js` 仅作蓝图参考」;
3. **推荐(非强制)**用户开 ultracode 模式;
4. 给「未开 / 不便编排时」的单 agent 降级路径。

**skill 做不到的(别再这么写、这么想):**
- ❌ skill **开不了** ultracode(那是用户的会话模式)。
- ❌ **不存在 `claude workflow` 这种 shell 命令**。Workflow 是 AI 在会话里调的工具,不是命令行子命令。
- ❌ 所以任何「skill 强制用 ultracode」的措辞都是错的。正确措辞永远是:
  > **本 skill 主执行路径 = AI 用 Workflow 工具编排;推荐 ultracode 模式;降级 = 单 agent 顺序。**

**编排脚本里 agent 不直接写闸门 state。** `.workflow.js` 里 `agent()` 只产「发现 JSON」;真正的闸门 state 由 **Bash 调 `scripts/app-gate.sh` / `scripts/design-first/` 下的确定性脚本**产出(这些脚本已存在,key 已定死,**勿改其 key**)。这条「agent 产料 → Bash 跑确定性脚本产 state」是所有关共用的契约。

**Claude 内置 Workflow 工具在 AI 现场写的 script 里可用的编排原语**(顶层 `await`):
`phase(title)` / `parallel(fns[])` / `pipeline(items, ...stages)` / `agent(prompt, {label, phase, schema})` / `log()`。`.workflow.js` 蓝图里出现这些只是示意推荐结构。
**每个并行 worker 必须 `.catch` 兜底**成一个合法 fallback,否则一路崩会拖垮整段。

---

## ② 用户怎么开 ultracode

ultracode 是**用户侧**的开关,AI / skill 不能代开。开法二选一:

- 会话里输入 **`/effort ultracode`**(切当前会话的 effort 模式);
- 或在 Claude Code **设置**里把 effort / 模式设到 ultracode。

> **一句话原则:开了 ultracode,AI 才会默认走多 agent 编排。** 不开也能干活,但 AI 会更倾向单 agent 顺序(就是各关的降级路径)。换句话说:你想要并行扇出 + 独立红队的那套,先开 ultracode。

---

## ③ 哪些关备有 `.workflow.js` 编排蓝图参考

> 本节列的 `.workflow.js` 都是**供 AI/人参考的推荐扇出结构蓝图**,不是本项目运行的编排脚本。

主线五关备有 `.workflow.js` 编排蓝图(discover/lockdown/shape/build/qa)在 `scripts/workflows/`;design-first 前置两个(`design-restore`/`backend-forge`)在 `scripts/design-first/`。这些蓝图展示推荐扇出结构,供 AI 现场组合 script 时参考(`export const meta` + `phase()` + `parallel`/`pipeline` + `agent({label,phase,schema})` + 每 worker `.catch`)。

**已有(基线,本文照搬其契约):**
- `design-restore.workflow.js` — 设计稿 → 高保真前端(Extract / Per-Screen loop-until-converge / Synthesis)。
- `backend-forge.workflow.js` — 功能·契约 → 完整后端 API(OpenAPI-SSOT / Per-Endpoint pipeline / Adversarial-Rules / Synthesis)。

> design-restore / backend-forge 是 **shape 关的前置子编排意图**(Step1.0 / Step1.85);其 `.workflow.js` 仅是蓝图参考,AI 可参照它把对应扇出并入 shape 的编排,或由 SKILL 顺序调降级路径。

**本轮新增(app-factory 主线五关):**
- `discover.workflow.js` — Phase A 探索(关键词 → 笛卡尔积全网调研 → 提议·红队对抗 → mockup → 收口闸门)。
- `lockdown.workflow.js` — Phase B 锚定(五路并行:spike / 经济 / 命名 / 后端 / 合规 + 对抗复审 + 汇总闸门)。
- `shape.workflow.js` — A-GATE 1 产品认知(认知 → 7 路挑战扇出 → 故障想象 → 数据契约 → 拆任务 → 4 角色对抗审查 → 收口)。
- `build.workflow.js` — 逐 TASK pipeline(Contract-Gate → Implement 并行 → Test-Loop 熔断 → 对抗 review + 闸门 + commit)。
- `qa.workflow.js` — A-GATE 3 验收(契约侦察 → 多端 smoke 扇出 → 反绕过 N-skeptic 对抗 → 合规 9 节扫 → 收口)。

### 对照表:关 → 编排蓝图参考 → 落什么 state → 哪个闸门读

> 「编排蓝图参考」列的 `.workflow.js` 文件是**供参考的扇出结构蓝图**,不是传给 Workflow 工具运行的脚本。

| 关(skill) | 编排蓝图参考(`.workflow.js`) | 编排骨架(质量模式) | 落的 state 文件(随项目根) | 闸门(确定性脚本) |
|---|---|---|---|---|
| **discover** | `discover.workflow.js` | Frame(单)→ Research(parallel × sources×actions 笛卡尔积全覆盖)→ Decide+RedTeam(pipeline propose→attack 对抗)→ Visualize → Synthesis(completeness critic 单点写) | `.claude/state/market-research/*.json`、`docs/spec.md`(3章)、`docs/discovery-summary.md`、`.claude/state/clearance-discover.json`、`skill-signal.json`、`discarded-directions.txt` | `app-gate.sh app-gate discover`(sg_app_* 5 检 + discovery-summary 卡口)→ `clearance-discover.json` |
| **lockdown** | `lockdown.workflow.js` | 入口校验(单)→ 五路锚定 `parallel([spike,economics,naming,backend,compliance])`(命名内 pipeline gen→check→pick)→ 对抗复审(parallel 红队)→ 汇总+机械验收(顺序)→ 信号续接 | `spike-results.json`、`asr-survival-scan.json`、`naming-candidates.json`、`evidence/*`、`spec.md` 5 章、`clearance-lockdown.json`、`skill-signal.json` | `app-gate.sh app-gate lockdown`(spike双语真跑 / 经济真数据 / 命名真证据 / 后端真值 / 合规真扫 / bundle 一致 六检)→ `clearance-lockdown.json` |
| **shape** | `shape.workflow.js` | Cognition(单 FROZEN)→ Challenge(parallel × 5 视角 + PLATFORM-MATRIX)→ Fault(吃 Challenge.gaps)→ Contract(单)→ Tasks(单)→ Review(parallel × 4 角色对抗)→ Synthesis(单点写) | `docs/spec.md`(全量结构)、`api/openapi.yaml`(经 backend-forge 前置)、`clearance-shape.json`、`skill-signal.json`、`status.md` CURRENT_GATE | `app-gate.sh stop-app-audit`(7 项 sg_app_* + openapi_artifact advisory)→ `clearance-shape.json` |
| **build** | `build.workflow.js` | `pipeline(tasks)` 逐 TASK 串;每 TASK 内:Contract-Gate(单)→ Implement(parallel A实现/B测试/C美术)→ Test-Loop(loop-until-converge 单调降+3轮熔断)→ Adversarial-Review+Gate(parallel critic + Bash 写闸门 + commit) | 逐 commit;`status.md`(DONE-TEMPLATE)、`.claude/state/skill-signal.json` | `pre-commit-scope.sh`(改动⊆FILES+PLATFORM隔离)+ `app-gate.sh sg_app_bundle_coherence` + stub-scan + `stop-app-audit.sh` 终检 |
| **qa** | `qa.workflow.js` | Contract-Recon(单)→ Multi-Platform-Smoke(parallel × platform,worker 内 pipeline)→ Adversarial-Reviewer-Path(parallel × claim × N skeptic 对抗)→ Compliance-Scan(parallel × 9 节)→ Synthesis(单点写) | `.claude/state/verify-screenshots/<p>/*`、`reviewer-walkthrough/*`、`verify-report.json`、`asr-survival-scan.json`、`clearance-qa.json`、`skill-signal.json`、`status.md` | `app-gate.sh app-gate qa`(sg_app_multiplatform_smoke / sg_app_reviewer_path / sg_app_compliance_real_scan)→ `clearance-qa.json` |

> 三条铁律(对照表里反复出现,不是巧合):
> 1. **闸门权威只有一个**:`scripts/app-gate.sh app-gate <gate>` 跑确定性检查、产 `clearance-<gate>.json`。编排 / 降级两条路都跑它,key 完全一致。
> 2. **每关只有一个写 state 的点**(Synthesis / 收尾 phase),避免并行写冲突。worker 只产「发现 JSON」,不碰 state key。
> 3. **新增关不新造 key、不改 `app-gate.sh`**。Claude 内置 Workflow 工具只在会话内做并行调度;真 state 仍由既有确定性脚本 / 既定路径产出。`.workflow.js` 蓝图不产 state。

---

## ④ 未开 ultracode 时的单 agent 降级

没开 ultracode、Workflow 工具不可用、或用户明确要省 token 时,每关都走**单 agent 顺序降级**——这正是各 SKILL.md 里原本就有的执行计划,本来就能跑,作为 graceful degradation 保留。

**降级的统一形态:**把编排里「parallel 扇出」改成「同一条助理消息里依次产出多份」,把「独立红队 / 多 skeptic 投票」改成「同一 agent 先写正方、再切红队人格攻击自己 / 写完自检一遍」,把「loop-until-converge / loop ≤3」改成单 agent 内的普通 for 循环 + retry 计数手动维持熔断。

各关降级要点:
- **discover**:一个 agent 串行跑 6 项强制调研(curl itunes + 各平台 WebSearch + 抓差评 + 找死亡案例 + 写反方)→ 自决 5 字段并强制「先写方向再切红队人格,反方≥3 条且每条带 URL,否则重写」→ 出 ≥4 张 mockup(退化可 ASCII 线稿)→ 写 spec 3章 + summary → 跑 `app-gate.sh app-gate discover`。
- **lockdown**:Step 2.1 spike → 2.2 经济 → 2.3 命名(候选→查重→选)→ 2.4 后端 → 2.5 合规 → `app-gate.sh app-gate lockdown` → 信号续接 `/shape`。**唯一值得手动并发的 IO 点**:命名 25 次查重(5候选×5源)用一个 Bash for 循环后台 curl + wait 压时间。
- **shape**:一个 agent 按 Step0→6 串行;Step1.5 在一条消息里对 5 视角逐一扫;Step3 在一条消息里以 4 角色口吻各写一段审查(验收 `roles[]≥4` 含「多端体验」);收尾跑 `app-gate.sh stop-app-audit`。
- **build**:单 agent 跑原 11 步(合同/三问/PLATFORM 自检 → 先写测试再实现 → 自循环 fix→retest 3 轮 + retry 计数熔断 → 自审禁止模式表 + stub-scan,可显式让 `/code-review` 或 simplify 跑一遍 diff 当外部第二视角)→ `pre-commit-scope.sh` + `app-gate.sh` + stub-scan → status.md + commit + skill-signal.json。
- **qa**:逐链路对账 → 逐端 smoke 各截 3 viewport → 反绕过/paywall 改为「单 agent 自检 + 强制真实登录截图(no-bypass.png / paywall-full.png / iap-sandbox.png)否则判 FAIL」的硬证据闸门 → 合规 9 节逐节扫 → 写 `verify-report.json` + `asr-survival-scan.json` → `app-gate.sh app-gate qa`。

**降级代价(诚实说):**
1. 一手数据采集 / 多端 / 各视角**串行 → 慢**(墙钟时间是主要损失)。
2. **无独立对抗**:反方论据 / 查重完整性靠单 agent 自律,易凑数;补偿 = prompt 里强制「红队自检 checklist 否决重写」+ 必要时调外部 `/code-review`。
3. **「需补证据」无法自动回灌定向调研**(编排里那条轻量 loop),只能整段重跑。

**降级触发判据:** Workflow 工具不可用 / 项目根无 `CLAUDE_PROJECT_DIR` / 用户明确要省 token / 任务本身扇出收益低(关键词极清晰且竞品稀少、单端无 [CRITICAL] 模块、纯逻辑非 UI 任务)。

**结果等价性(关键保证):** 降级版与编排版产出**完全相同的 state 文件、过完全相同的 `app-gate.sh` 闸门、写完全相同的 `clearance-<gate>.json`**。差别只在墙钟时间(并行 vs 串行)和对抗深度(独立红队 vs 自检),**不影响正确性与续接**——lockdown / 收口 hook 链对两条路无感。

---

## ⑤ 一句话定调

**借 Claude 内置 Workflow 工具做编排,是 app-factory 完成复杂需求的主路径,不是可选装饰。**
它把「全网真覆盖(笛卡尔积扇出)+ 真对抗(独立红队 / 多 skeptic)+ 单点写闸门(确定性脚本)」三件事在多 agent 下做实;单 agent 降级只是它的兜底投影,保正确不保速度与对抗深度。推荐做法恒为:**用户开 ultracode → AI 用 Claude 内置 Workflow 工具,按各 skill 的编排意图(可参照 `.workflow.js` 蓝图)现场组合 script 并执行 → 收口跑 `app-gate.sh` 产 `clearance-<gate>.json`**;开不了再降级,降级也照样过同一道闸门。
