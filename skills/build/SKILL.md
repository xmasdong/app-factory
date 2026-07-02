---
name: build
description: "Build one task to passing tests with PLATFORM isolation, bundle id coherence enforcement, multi-platform mock routing, and scope discipline. A-GATE 2 implementation entry for app projects."
---

# /build — A-GATE 2 实现 (app 主线)

> ⚙️ **主执行路径 = 用 Claude 内置的 Workflow 工具，按本 skill 描述的编排意图当场组合 script 并执行**：pipeline 逐 TASK 串行 × 每 TASK 内 4 phase(合同闸门 → 并行实现/测试/美术 → 测试 loop 熔断 → 对抗 review + 确定性闸门 commit)。编排结构可参考蓝图 `scripts/workflows/build.workflow.js`（仅为展示推荐扇出形状的**参考蓝图**，**不是**传给工具运行的脚本；Workflow 工具归 Claude，本项目不定义 workflow、不拥有任何 workflow 运行时）。**推荐在 ultracode 模式下做**（ultracode = 用户手动开启的会话高级模式；开启后 AI 用 Claude 内置的 Workflow 工具，按上述编排意图现场组合 script 执行；skill 强制不了用户模式）。
>
> **降级路径(未开 ultracode / 不便编排):单 agent 顺序执行下面 11 步,完全可用且是 build 的自然形态(主干本就串行)。** 对应关系:Step 1-3 = 合同 / GATE1 三问 / PLATFORM 自检;Step 4-5 = **先写测试再实现**(同一 agent 顺序做,失去并行但不失正确性);Step 7 = 自己跑 `fix→retest` 最多 3 轮(loop 退化成 agent 自循环,熔断逻辑用 retry 计数手动维持:连续 3 轮不转绿 = 软熔断跳过本任务,连续 2 个软熔断 = 硬熔断停等人);对抗验证退化成 agent **自审一遍禁止模式表 + stub-scan**(承认弱于独立 critic,补偿:可显式让 `/code-review` 或 `simplify` skill 跑一遍 diff 当外部第二视角);Step 6/8 = 调 `pre-commit-scope.sh` + `app-gate.sh`(`sg_app_bundle_coherence`)+ `stub-scan`;Step 9-11 = status.md + commit + skill-signal.json。**闸门 `.sh` 脚本无论走哪条路径都一样跑,所以降级只丢「并行加速 + 独立对抗视角」,不丢任何 gate 保证。** 这里的「编排路径」指 AI 用 Claude 内置 Workflow 工具按蓝图当场组合的扇出执行，并非本项目自有的可运行 workflow 版本。 对纯逻辑(非 UI、无美术)任务,降级与编排路径差距最小(Phase 1 本就只剩 A‖B 两轨)—— **优先直接降级以省 agent 开销**。

> 🎨 **design-first**:UI 任务以 `docs/design/tokens.json` 为**硬基准**(只引用 token 禁硬编码值);Backend 通道挂 `backend-forge` codegen 产物;前端 mock **必须由 `api/openapi.yaml` 生成**(prism/msw)= 前后端同源不 drift。UI 还原走 `design-restore` 渲染+diff 段(reify≠create,别和 frontend-design 抢)。

> 🔗 **App Factory 集成 — UI 与美术**:
> - UI 类任务实现后调 UI 簇:`frontend-design`(界面质感)+ `polish`(对齐间距)/`animate`(动效)/`colorize`(配色)/`harden`(错误处理/i18n/文字溢出),把"能跑"升到"有设计感"。
> - **美术/素材调 `codex-image-bridge`**:app 图标、应用内插画/图标/素材、效果图。⚠️图标约束:App Store 图标**无 alpha 通道**(RGB 不透明);watchOS 图标**不能深色/黑底**(需明亮彩色满底);各平台尺寸齐全。

**作用:** 拿一个任务到测试通过 + commit. 在 generic 实现规则之上, 加 app 主线的 PLATFORM 隔离、bundle id 一致性、多端 mock 路由.

**INPUT_CONTRACT:**
- A-GATE 0/1 已过: `clearance-anchor.json` + `clearance-shape.json` 存在
- 当前任务在 `docs/status.md` 任务清单中, 含 `PLATFORM:` 字段
- `docs/status.md` 顶部含 `PROJECT_TYPE: app` + `CURRENT_GATE: A-GATE 2`

**CONTRACT 不满足时:**
- A-GATE 0/1 未过 → 拒绝执行, 提示先跑 /anchor 或 /shape
- TASK 缺 PLATFORM 字段 → 提示回 /shape 补全 TASK-TEMPLATE
- PROJECT_TYPE 不是 app → 提示走 generic 实现 skill

**OUTPUT → 代码 + 测试 + status.md 更新 + commit hash + skill-signal.json**

参照 `.claude/rules/core.md § GATE 1 理解门禁`、`§ GATE 2 能力门禁`、`§ 决策生命周期`、`§ 禁止模式` (预建抽象 / 幽灵依赖 / 防御性冗余 / 范围蠕变).

---

## 执行计划

```
- [ ] Step 1: 读 status.md 找当前 TASK, 确认 PLATFORM 字段
- [ ] Step 2: GATE 1 三问 (一句话做什么 / ACCEPT 可测试 / 改哪些文件)
- [ ] Step 3: PLATFORM 隔离自检
- [ ] Step 4: 实现代码 (遵循 Mock/Stub + 禁止模式 + 决策生命周期)
- [ ] Step 5: 写测试 (单元 + 集成; stabilizing 起含 E2E)
- [ ] Step 6: bundle id 一致性自检 (改 Info.plist/build.gradle/package.json 时强制)
- [ ] Step 7: 跑测试, 失败 → 最多 3 轮 fix→retest (熔断器接管)
- [ ] Step 7.3: **质感工序**(必经:游戏走「游戏质感工序」/非游戏 app 走「App 质感工序」)——见下方两节
- [ ] Step 7.5: 跑 `/self-correct` — 拿 `app/rules/build-constraints.md` 8 约束对本产物自省(元则:别直译省事版、别用弱证据自证),自纠能修的、诚实标出需真机/用户的。**宣称"完成"前的自 QA,不是过写死清单**
- [ ] Step 8: scope check (改动 ⊆ TASK.FILES, 受 PLATFORM 约束)
- [ ] Step 9: 更新 status.md (任务状态 + optimistic/deferred 清单)
- [ ] Step 10: commit
- [ ] Step 11: 写 skill-signal.json
```

---

## Step 3: PLATFORM 隔离自检

每个 TASK 的 `PLATFORM:` 字段约束允许修改的目录:

| PLATFORM | 允许目录 |
|----------|---------|
| iOS | `ios/`, `*.swift`, `*.m`, `*.h`, `Podfile*`, `*.xcconfig` |
| Android | `android/`, `*.kt`, `*.java`, `build.gradle*`, `AndroidManifest.xml` |
| Backend | `backend/`, `api/`, `server/`, `*.go`, `*.py`, `*.ts` (服务端) |
| Web | `web/`, `admin/`, `*.tsx`, `*.vue`, `*.html` |
| 鸿蒙 | `harmony/`, `*.ets`, `*.har` |
| 小程序 | `miniapp/`, `wxapp/`, `pages/`, `app.json` |
| All | 任何目录 (ACCEPT 显式说明跨端理由) |

**违规检测:**
- TASK.PLATFORM=iOS 但改了 `android/` → 阻塞. 拆任务或改 PLATFORM=All
- 反之同理
- **例外:** native bridge / 多端共享 model — 必须 PLATFORM=All 且 IMPACT 显式列双端消费方

由 `pre-commit-scope.sh` + `sg_app_bundle_coherence` 触发校验.

---

## Step 4: 实现规则 (核心)

### Mock/Stub (生产代码路径)

`.claude/rules/core.md § 禁止模式` 和硬规则 11/12 要求:

- 生产代码中的 mock/stub 必须满足至少一项:
  a) 函数/文件名含 `Mock`/`Stub`/`Placeholder`/`Fake`
  b) 环境变量门控 (`MOCK_*=1`), 非生产环境输出 WARNING 日志
  c) `DONE-TEMPLATE.STUB_REMAINING` 显式声明
- **静默降级** (返回假数据且不报错不记日志) **生产路径禁止**
- `stub-scan` 脚本在 commit 前 + /build 验收时自动检测

### app 主线 mock 路由 (额外约束)

**允许 mock 推进** (前端不阻塞):
- 后端 API schema 已在 spec.md 数据契约 + FROZEN
- IAP 沙盒环境配置 ready, 真实 IAP 暂用 mock

**禁止 mock 推进** (硬阻塞):
- bundle id / IAP product id 未锁 (生产环境立刻暴露)
- 推送 token 字段未定 (APNs / FCM 格式不同, mock 让真集成时全部错)
- 支付服务端验证流程未定 (mock 让前端写错 IAP 收据上送格式)

mock 必须显式标识 + 记入 status.md optimistic 清单 + 指明被替换的文件路径.

### 决策生命周期

实现中遇 spec 未定义的决策 (空状态处理 / 边界行为) → 不默默推断. 按 `.claude/rules/core.md § 决策生命周期` 分类:

- **optimistic** — 已按默认方案实现, 等检查点确认 (低回滚成本, 累 ≥5 触发检查点)
- **deferred** — 跳过先做别的 (高回滚成本但不阻塞)
- **阻塞** — 停下等人 (高回滚成本 + 阻塞后续任务)

所有 optimistic 项必须能在 status.md 找到记录 + 指明被替换的明确文件路径.

### 禁止模式 (与 `.claude/rules/core.md § 禁止模式` 对齐)

| 禁止 | 信号 |
|------|-----|
| 预建抽象 | 为"将来可能需要"写接口/基类/工厂, 当前只有一个实现者 |
| 幽灵依赖 | package.json/go.mod 出现任务未要求的新条目 |
| 防御性冗余 | 同一检查逻辑在 >1 层重复且无跨层契约 |
| 范围蠕变 | 改动与当前 ACCEPT 无关, 删掉后验收仍通过 |

---

## Step 6: bundle id 跨文件一致性

**触发条件**: 改动以下任一文件:
- `ios/*/Info.plist`
- `ios/*.xcodeproj/project.pbxproj`
- `android/app/build.gradle*`
- `app.config.js` / `app.json` / `package.json`
- `*.entitlements`
- IAP 配置 / RevenueCat dashboard 配置

**校验** (调 `app-gate.sh sg_app_bundle_coherence`):

1. 从 spec.md `## 命名锁定` 章节提取 bundle id (formal value)
2. grep 代码库所有出现位置, 必须全部 = locked value
3. 禁止 `${VAR}` / `$(...)` 变量拼接 (硬阻塞)
4. 不一致 → 阻塞 commit + stderr 列冲突文件

**变更 bundle id 必须回 /anchor**, 重新走命名锁定 6 项, 不在 /build 静默修改. 参照 `.claude/rules/core.md § 硬规则 app 补丁 → NEVER bundle id 锁定后变更`.

---

## Step 8: scope check

`pre-commit-scope.sh` 在 commit 前对照 TASK.FILES 检查改动:
- 改动文件 ⊆ FILES → 放行
- 改动文件 ⊃ FILES → 阻塞. 评估是任务定义不准 (更新 FILES) 还是 scope creep (拆新任务)
- PLATFORM=iOS 但改了 Android 目录 → 阻塞 (即使 FILES 列了, FILES 与 PLATFORM 不一致也得修)

---

## Step 9-10: status.md + commit

按 `.claude/rules/core.md § DONE-TEMPLATE` 填:
- 任务状态 `- [x]`
- TESTS / SMOKE_RESULT / STUB_REMAINING / HUMAN_STATUS / PENDING_CONFIRM / COMMIT / STATUS_UPDATED

commit 信息含 TASK 编号. ai-rules CLAUDE.md 硬规则授权 commit 自动执行 (无需每次请示).

---

## Step 11: 写完成信号

```bash
mkdir -p .claude/state
echo "{\"skill\":\"build\",\"epoch\":$(date +%s)}" > .claude/state/skill-signal.json
```

---

## OUTPUT_GATE

由 `stop-app-audit.sh` 验收:
- 测试通过 + scope 在 TASK.FILES 内
- PLATFORM 隔离 OK + bundle id 一致
- stub-scan 无未声明的 mock 残留
- commit 成功 + status.md 任务状态 `- [x]`
- skill-signal.json 写入

**OUTPUT_GATE 不通过时:**
- 失败回灌为 stderr
- AI 补全后才能进下一任务
- 连续 3 次失败触发熔断器 (软熔断: 跳过当前任务; 连续 2 个软熔断 → 硬熔断, 等人)

---

## 游戏质感工序(游戏类产品必经;BGM 除外)

> **为什么必经:** 游戏跑通 ≠ 游戏能上架。「功能完成+测试绿」只到"能用";用户付钱/留下的原因在"想玩"。历史实况:一款儿童游戏 build 完只有 2 个美术资产文件、零触感零庆祝——全部界面是代码画的近似。这一层不做,产品就是半成品。**BGM 明确排除**(用户价值函数);短音效可选,触感可替。

**判定是不是游戏**:PRODUCT_FORM 含 游戏/game/玩法。是 → 本工序必经,产物过 `sg_app_game_feel` 检查。

### ① 美术资产 pass(codex-image-bridge 出全套,替换代码近似)

代码画的圆角矩形不是美术。用 `codex-image-bridge` 生成**成套**资产(同一 prompt 风格基因,保证风格一致):

- **App 图标 + 启动屏**(商店第一眼;注意平台约束:AppStore 无 alpha)
- **背景纹理**(纸纹/织物/蜡笔涂层——"质感"的地基,纯色背景=没质感)
- **按钮/卡片贴纸化**(手绘边、投影、微倾斜,九宫格切图或整图)
- **庆祝元素**(confetti/星星/奖杯/mascot 表情集——庆祝时刻要有真图可撒)
- **mascot ≥3 表情**(常态/庆祝/失败——有反应的吉祥物才是活的)

资产必须**真接线**:进 pubspec/xcassets 并被代码引用——躺在目录里不算配套。

### ② 质感 pass(手感层,重点)

| 件 | 最低标准 |
|---|---|
| **微交互** | 按钮按压回弹(scale/bounce)、页面进出场过渡——没有硬切 |
| **触感** | 关键动作带 haptic(落笔/猜对/按钮),轻重分级 |
| **庆祝时刻** | 猜对/过关必须有可感知的高光(confetti+mascot 反应+弹分数),不是弹个对话框 |
| **字体** | 儿童/休闲风禁系统默认黑体——圆体/手写体(注意字体授权) |
| **空/过场状态** | 加载、空列表、传机等待——每个状态都带风格,不裸奔 |
| 短音效 | 可选(猜对叮/落笔沙沙);不做则触感补位。**BGM 不做** |

### ③ 收尾判据(不是清单,是那封信第 3 条)

以真实玩家身份**完整玩一局**(模拟器/真机),问自己:"爽了没?哪一步感觉廉价?"感觉廉价的地方 = 质感缺口,回 ①/② 补。机械底线由 `sg_app_game_feel` 验(资产数/图标/触感与庆祝代码引用);"爽"由你诚实作答,写进 self-correct findings。

---

## App 质感工序(非游戏 app 必经)

> 游戏有游戏的半条命,app 有 app 的:**「CRUD 全绿」到「像个上架产品」之间隔着一整层**。默认 Material/Cupertino 裸奔 + 转圈 loading + 空白空状态 + 开发者语言报错 = 用户一眼"糙"。工厂武器全在库里(frontend-design/polish/animate/onboard/harden/clarify + codex-image-bridge),本工序把它们串成必经。

### ① 视觉系统 pass

- **设计 token 先行**(色板/字阶/圆角/间距/阴影成体系,禁散落硬编码)——调 `frontend-design`(或已有 DESIGN.md/tokens 就对齐它)
- **App 图标 + 启动屏**(codex 出;AppStore 图标无 alpha)
- **禁默认控件裸奔**:关键界面必须有品牌感(哪怕只是统一的圆角+主色+留白节奏)

### ② 状态完备 pass(app 质感的照妖镜)

| 状态 | 最低标准 |
|---|---|
| **空状态** | 带插画/图标 + 一句引导 + 行动按钮——不是白屏或"暂无数据" |
| **加载** | 骨架屏(skeleton)优先,禁全屏转圈 |
| **错误** | 人话 + **可重试**——不是抛错误码;网络错和业务错分开说 |
| 离线/弱网 | 核心读路径有缓存兜底或明确提示 |
| **首次使用** | onboarding/引导到第一次价值(调 `onboard`)——新用户 30 秒内明白这 app 干嘛 |

### ③ 微交互 pass

按压反馈(视觉+触感)、页面过渡(禁硬切)、列表项进场、下拉刷新;**暗色模式**适配(或 spec 显式声明"仅亮色/仅暗色 + 理由")。文案过一遍 `clarify`:界面上不许出现开发者语言(如 "request failed: 500")。

### ④ 收尾判据

以**全新用户**身份从安装后第一屏走完核心路径:"顺不顺?哪里像半成品?"像半成品的地方 = 缺件,回 ①②③ 补。机械底线由 `sg_app_product_feel` 验(图标/空状态/错误重试/暗色声明/动效引用);"像不像上架产品"由你诚实作答,写进 self-correct findings。

---

## 完成后下一步

任务链自动续接 (参照 `.claude/rules/core.md § 任务链自动续接`):
- 下一任务存在且无阻塞 → 直接开始, 不问用户
- 触发检查点 (optimistic ≥5 / 依赖触发 / 里程碑) → 输出检查点, 等用户确认
- 全部完成或全部阻塞 → 停, 汇报状态

尾标记:

`完成: T<N> 已实现并 commit, 测试 PASS, 下一任务 T<N+1> 进入 /build`

或检查点触发:

`等你: optimistic 项累计 5 个, 触发检查点, 请审下表`

或阻塞:

`停住: T<N> 依赖 deferred 决策"账号体系", 跳到 T<N+2> 实现"导出报表" (无阻塞)`
