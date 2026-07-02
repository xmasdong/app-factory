---
name: shape
description: "Shape product cognition into a complete spec.md — PRD challenge (5 views), fault imagination, data contract with per-platform consumers, multi-platform capability matrix, task breakdown with PLATFORM field. A-GATE 1 entry for app projects."
---

# /shape — A-GATE 1 产品认知 (app 主线)

> ⚙️ **数字不是法律**:PRD 挑战 5 视角、多端矩阵行数、数据契约消费端数 等都是**常备透镜清单(起点非上限,更非配额)**:就本产品哪些真适用?每个适用的照出真实缺口没有?不适用的显式写「不涉及 + 理由」跳过,**不凑数量**;本产品有清单外的关键维度(强实时/离线优先/多租户)自己加。判断标准=另一个 AI 读完能不能不问就补齐,而非填满 N 个。真护栏照旧:每条挑战必须有主语+具体动作+具体画面(禁「同上」「通用错误处理」)、fallback 必须具体、数据契约高风险字段单位值域全列。判断力地基见 `build-constraints.md`。

> 🎨 **design-first 核心**:① Step1.0 调 `design-restore` 抽取段 → `docs/design/design-manifest.json` + `tokens.json` + baseline PNG(视觉方向改为"读 manifest 体检补缺")② Step1.8 数据契约用 `manifest.screens[].fields` 做种子 ③ 新增 Step1.85 调 `backend-forge` 契约段 → `api/openapi.yaml`(SSOT)+ 越权矩阵 ④ coverage 升维三维(屏×断点×state)。**两份机读产物(manifest + openapi)= 设计↔app↔后端唯一真相源,机制消灭前后端 drift**。闸门 `sg_app_data_contract` / `sg_app_openapi_artifact`(advisory)。

> 🔗 **App Factory 集成**:本关「视觉方向」调 `frontend-design` skill 定**设计系统**(配色/排版/组件基调/避 AI 通用脸),写进 spec.md「视觉方向」章节,给 /build 当 UI 实现基准。

**作用:** 把产品需求塑形成完整 spec.md. /anchor 锁了外部世界, /shape 锁产品内部 — 用户故事 / 故障想象力 / 任务清单 / 多端能力矩阵 / 数据契约. 这是 app 写代码前的最后一关.

**INPUT_CONTRACT:**
- A-GATE 0 已过: `.claude/state/clearance-anchor.json` 存在 + 5 子节 locked
- `docs/spec.md` 已有 5 子节 (命名锁定 / 单位经济 / 技术 spike / 后端就绪 / 合规扫描)
- 用户已描述产品需求 (一句话以上)
- `docs/status.md` 顶部含 `PROJECT_TYPE: app` + `CURRENT_GATE: A-GATE 1`

**CONTRACT 不满足时:**
- A-GATE 0 未过 → 拒绝执行, 提示先跑 /anchor
- PROJECT_TYPE 不是 app → 提示走 generic 主线
- CURRENT_GATE ≠ A-GATE 1 → 提示走对应 gate

**OUTPUT 追加(UI/游戏类)→ `docs/DESIGN-FEED.md` + `lib/theme/design_feed.dart`(或对应栈的主题变量文件)**

**OUTPUT → `docs/spec.md` 完整 + `.claude/state/clearance-shape.json` + skill-signal.json**

参照 `.claude/rules/core.md § A-GATE 1` (复用项) 和 `.claude/rules/core.md § 决策生命周期` (optimistic/confirmed/deferred/invalidated/fused 状态).

---

## 编排意图 (开 ultracode 后, AI 用内置 Workflow 工具现场组合)

**编排建议: 推荐用户手动开启 ultracode 会话高级模式** (skill/脚本无法自己开它)。开了之后, AI(Claude)用内置 Workflow 工具——这是 Claude Code 的内置工具, 不是 shell, 也不存在 `claude workflow` 命令——按本 skill 描述的编排意图当场组合 script 并执行(script 由 AI 现场写, 不从本仓任何文件加载来运行)。本仓 `scripts/workflows/shape.workflow.js` 仅作【编排蓝图参考/示例】, 展示推荐的扇出结构, 供 AI 或人参考, 不是『传给 Workflow 工具去跑的可执行脚本』, 本项目也不拥有任何 workflow 运行时。

该 .workflow.js 蓝图参考展示的是 fan-out-then-converge 编排形状 (两次扇出 + completeness critic 收敛), AI 现场组合 script 时可照此结构 (非加载该文件运行):

```
Precheck   (串行) — 校验 INPUT_CONTRACT + 读 lessons.md, 不满足 throw 终止
Cognition  (单 agent, FROZEN) — 全局认知 + 枚举 features[] (扇出唯一输入)
Challenge  (parallel × 5 PRD 视角 + PLATFORM-MATRIX) — 第一次扇出, 逐功能列 gaps[]
Fault      (单 agent) — 故障想象力, 吃 Challenge.gaps (SKILL §91 依赖关系落地)
Contract   (单 agent) — 数据契约逐字段对账 + 多端消费方
Tasks      (单 agent) — TASK-TEMPLATE 拆任务含 PLATFORM + [CRITICAL] + 覆盖契约
Review     (parallel × 4 角色: 需求/证据/范围/多端体验) — 第二次扇出, 对抗审查
Synthesis  (单 agent = 唯一写 state 口) — 汇编完整 spec.md + 跑 app-gate.sh shape 产 clearance-shape.json
```

收尾闸门一致: 无论主路径还是降级, Synthesis/收尾都跑 `bash scripts/app-gate.sh app-gate shape` 产 `clearance-shape.json`, 机械验收挡住偷工 (worker 只产『发现 JSON』, 确定性 state 仍由 scripts/ 脚本生成, 严禁手写)。

### 降级: 单 agent 顺序 (兜底, 下方"## 执行计划"现有路径即此)

未开 ultracode / Workflow 工具不可用 / 项目过小 (单端 + 无 [CRITICAL] 模块) / 用户不想多 agent 时, 降级为**一个 agent 按 Step0→6 串行跑**。把本来并行的两处改为「同一助理消息内一次性产出多份」而非真并发:

- **Step 1.5**: 在一条消息里**依次对 5 个视角逐一扫** (不开 5 subagent), 逐功能列 gaps。
- **Step 3**: 在一条消息里**以 4 个角色口吻各写一段审查** (Step 3 "并发" 降级为"串行多角色自审"), 仍验收 `roles[]` ≥4 含"多端体验"子串。
- 故障想象力 / PLATFORM-MATRIX / 数据契约 / 拆任务 本就串行, 无差异。

**代价**: 并行扇出能让每个视角/角色独立深挖、互不污染上下文 (避免 5 视角写成"同上"套话、4 角色越权互相妥协); 单 agent 降级下质量靠 prompt 纪律保。**最终闸门一致** — 哪条路收尾都跑 `app-gate.sh app-gate shape` 产 `clearance-shape.json` 机械验收。

---

## 执行计划

```
- [ ] Step 0: 读 docs/lessons.md (历史教训)
- [ ] Step 1: 全局认知 (产品定义 / 用户故事 / 不做清单 / 视觉方向)
- [ ] Step 1.5: PRD 挑战 (5 视角)
- [ ] Step 1.6: 故障想象力 (维度枚举 + 对账)
- [ ] Step 1.65: **产 DESIGN-FEED(投料单,UI/游戏类必产)**——见下方「DESIGN-FEED」节
- [ ] Step 1.7: 多端能力矩阵 PLATFORM-MATRIX (app 特有)
- [ ] Step 1.8: 数据契约 (多端消费方 + 端侧独有字段)
- [ ] Step 1.9: 核心难点识别 ([CRITICAL] 模块)
- [ ] Step 1.10: 覆盖契约 (核心链路 + 不覆盖链路, FROZEN)
- [ ] Step 2: 拆任务 (TASK-TEMPLATE 含 PLATFORM 字段)
- [ ] Step 2.5: 任务 PLATFORM 字段反扫
- [ ] Step 3: 多视角审查 (4 角色: 需求/证据/范围/多端)
- [ ] Step 4: 前置人工动作反扫 (app 端侧补遗)
- [ ] Step 5: 写入 spec.md 完整版
- [ ] Step 6: 写完成信号
```

---

## Step 1.5: PRD 挑战 (5 视角)

**为什么必填:** spec 不是翻译 PRD, 而是挑战 PRD. PRD 缺口不在已写内容的排列组合里, 在作者没想到的维度. 5 个结构化视角逐一探查.

**对每个核心功能, 逐一检查:**

### 1. 状态完整性
列每个业务实体的所有状态 + 所有合法状态转换. PRD 未定义的转换 = 缺口.
*例 (活动报名):* 满员后有人取消 → 回"上线"还是保持"满员"?

### 2. 边界条件
每个数值/集合/时间: 0 时 / 1 时 / 上限 / 超限的行为. PRD 未定义的边界 = 缺口.
*例:* 0 人报名时列表页显示什么?

### 3. 多角色一致性
每个写操作: 其他角色实时/延迟看到什么? PRD 未定义的跨角色行为 = 缺口.
*例:* 组织者修改活动时间 → 已报名用户看到旧时间还是新时间?

### 4. 时序敏感
每个多步流程: 每一步超时/中断/重试时的行为. PRD 未定义的中断恢复 = 缺口.
*例:* 报名接口超时, 用户重试 → 会不会产生两条记录?

### 5. 数据生命周期
每个数据实体: 何时创建/修改/软删/硬删/归档? 谁有权操作? PRD 未定义的生命周期 = 缺口.
*例:* 活动结束后报名记录保留多久?

**每个缺口必须有处置 (三选一):**
- `补入 spec` — **立即补充** (默认), 不等人确认. 补充内容必须含具体定义 + 对应 ACCEPT 或新 TASK.
- `deferred` — 当前不处理, 给理由
- `不适用` — 该视角不涉及本功能, 给理由

**自动补充原则:** AI 通过结构化视角发现的缺口往往是人没想到的维度, 等人确认只多一次往返. 默认补入, 用户在最终审 spec 时不认可再删 — 这与 `.claude/rules/core.md § GATE 0` 的"补充后审"姿态一致.

---

## Step 1.6: 故障想象力 (维度枚举)

**为什么必填:** PRD 挑战找"PRD 没定义什么", 故障想象力找"这玩意炸了用户会看到什么". 两者互补.

**PRD 挑战的产出直接喂给故障想象力**:
- 每个状态转换 → "这个转换失败了会怎样?"
- 每个边界条件 → "越界时用户看到什么?"
- 每个跨角色操作 → "不一致时谁看到错误?"
- 每个时序节点 → "中断后重试会怎样?"

**补充维度枚举 (覆盖技术故障):**
- 故障主体: 用户操作 / 网络 / 数据库 / 第三方 / 并发 / 缓存 / 权限
- 故障时机: 操作前 / 操作中 / 操作后 / 跨操作
- 故障表现: 数据丢失 / 数据错乱 / 静默失败 / 状态卡死 / 重复执行

**格式: 如果这个功能在生产上炸了, 新闻标题会怎么写?**

要求:
- 写"用户视角的具体糟糕结局", 不是"代码层面的异常" (❌"空指针异常" ✅"未登录用户看到所有活动都显示已报名")
- 每条必须有主语 (哪种用户) + 具体动作 + 看到的具体画面
- 不允许"同上"/"通用错误处理"等套话

*示例 (活动报名):*
1. "未登录用户看到所有活动都显示已报名" (权限 × 操作前 × 数据错乱)
2. "活动满员后第 N+1 个用户仍然报名成功" (并发 × 操作中 × 数据错乱)
3. "同一用户重复点击产生 N 条报名记录" (时序 × 重试 × 重复执行)

**对账 (强制, 不对账视为未完成):**
- 每条糟糕结局, 对照 spec 检查: 是否被某个 ACCEPT 防住?
- 被防住 → 在该 ACCEPT 旁标注 `防 故障#N` (每编号独立写, 不可简写 `#2 #3`)
- 没防住 → **立即补 ACCEPT 或新 TASK**. 用户明确说"不用防"才写 `deferred`.

**多端反扫:**
- 每条故障是否针对**多端**适用? 还是只 iOS / Android?
- 例: "用户报名后刷新页面状态消失" 在小程序场景一样吗? 小程序 storage 限制 + back-and-forth 跳转可能产生独有故障
- 多端故障 = 单端故障 × N, 不可只为 iOS 写 ACCEPT

---

## Step 1.7: 多端能力矩阵 PLATFORM-MATRIX

**为什么必填:** 多端能力差异是产品决策, 不是实现细节. 不在 spec 阶段拍死, /build 阶段发现 "Android 不支持 X" = 用户故事失效 = 回 A-GATE 0 重算 ECONOMICS.

### 执行

1. 复制模板: `cat "$AI_RULES_ROOT/app/templates/sections/platform-matrix.md" >> docs/spec.md`

2. 对照模板按「声明端 × 真分叉能力」填行(单端可很少;下面 8 类是示例透镜池非配额)。**声明相关的轴不允许 `<TBD>`**;不涉及的显式写「不涉及」:
   - 抠图 / 人脸 / AR / 视觉算子
   - 推送 (即时下发)
   - 支付 / 订阅
   - 文件 / 相册 / 相机访问
   - 网络 (HTTP / WebSocket / QUIC)
   - 后台任务 / 唤醒
   - 推送点击行为 / Deep Link
   - 收款资质 / 主体

3. **fallback 列必须具体**, 不接受"降级到 server-side"一刀切:
   - ❌ "降级到 server-side"
   - ✅ "iOS 17- → Vision Foundation, iOS 18+ → ImageAnalysisInteraction"
   - ✅ "设备不支持 → server-side onnx, 单次成本 +$0.001, 用户感知延迟 +300ms"

4. **"不支持的端"章节必须存在** (即使全做也要写"无不支持的端"). 不写 = 隐式承诺全端.

5. **跨端一致性 FROZEN 决策** 必须列: 哪些维度各端必须一致 (数据格式/价格阶梯/核心功能可用性) / 哪些允许差异 (UI 风格遵循平台 HIG / 推送 payload 结构).

### 验收硬规则 (sg_app_platform_matrix)
- 章节存在 + ≥1 行真数据(声明端×相关能力;已去僵化,单端不凑 8)+ 每行 fallback 非空且不含一刀切语 + "不支持的端"显式 + 跨端一致性子章节存在(单端写"无跨端问题"也算)

---

## Step 1.8: 数据契约 (多端消费方)

**为什么必填:** 多端项目里"消费方"不只是后端调用方, 还有 iOS / Android / 小程序 / 后台. 同一字段不同端展示要求不同 (iOS 用 ISO8601, 小程序用 Unix 毫秒), spec 阶段不列死, /build 一端改 schema 另一端不知道 = 客户端崩.

### 数据契约表格 (消费方列含端区分, 强制)

```markdown
| 字段 | 类型 | 单位/格式 | 生产者 | 消费方 (按端) |
|------|------|----------|--------|-------------|
| price | int64 | 分 | backend /api/item | iOS: ItemDetail.swift, Android: ItemDetail.kt, 小程序: item-detail/index.js |
| created_at | string | ISO8601 (UTC) | backend | iOS: ISO8601DateFormatter, Android: java.time.Instant, 小程序: dayjs |
| order_status | enum | pending/paid/shipped/completed/cancelled | backend | iOS: OrderStatus.swift, Android: OrderStatus.kt, 小程序: status-map.js |
```

**高风险字段必须声明:**
- 金额类 → 单位 (分/元/cent)
- 时间类 → 格式 (Unix 秒/毫秒/ISO8601)
- 状态枚举 → 值域 (列所有合法值)
- ID 类 → 类型 (int64/string/uuid)

### 端侧独有字段子章节

```markdown
| 字段 | 仅存在于 | 用途 | 同步到后端? |
|------|---------|-----|-----------|
| apns_token | iOS | APNs 推送 | 是 |
| fcm_token | Android | FCM 推送 | 是 |
| openid | 微信小程序 | 微信账户绑定 | 是 |
| device_id | iOS/Android | 本地匿名标识 | 否 |
```

即使为空也要写"无端侧独有字段".

### FROZEN by default

数据契约**默认 FROZEN**. 变更 = 回 A-GATE 0 重算多端影响 + 回本 skill 重 spec. 不在 /build 中默默改. 参照 `.claude/rules/core.md § 决策生命周期 → FROZEN`.

---

## Step 1.9: 核心难点识别

**识别标准 (命中任一 → `[CRITICAL]`):**
- 多模块协作: ≥3 个模块协作 (如"下单"涉及库存/支付/订单/通知)
- 并发/一致性: 竞态 / 分布式事务 / 幂等性 / 锁竞争
- 方案不唯一: 实现路径 ≥2 个, 各有显著 trade-off
- 高扇出依赖: 其他 ≥3 个模块依赖此模块输出
- 调试密集: 需特定条件 (并发/时序/数据量) 才能复现
- 领域复杂: 业务规则本身就复杂 (多条件定价/审批流/状态机 >5 个状态)

**`[CRITICAL]` 模块必须在 spec.md 有方案简述:**
```
### [CRITICAL] 模块名

**为什么是难点:** 命中了哪条标准
**方案选择 (≥2 方案):** 表格列 描述/优势/劣势
**选择理由:** 一句话
**验证策略:** 最小验证 + 失败信号 + 回退方案
```

**对任务拆分的影响:**
- `[CRITICAL]` 任务必须**优先排序** (任务清单前段)
- 第一个任务应是**方案验证** (最小实验), 不是直接完整实现
- HUMAN 字段默认"阻塞"— 方案需人确认后才能开始

没有核心难点的项目写"无核心难点"即可, 但**显式声明**.

---

## Step 1.10: 覆盖契约

业务链路组合无界, "完整覆盖"是伪命题. /qa 不回答"还有没有遗漏" — 它对照覆盖契约判断是否完成. 新增链路 = 修改契约 = 回本 skill, 不在 /qa 吸收.

```markdown
## 覆盖契约 (FROZEN)

### 核心链路 (本 release 必须 E2E 覆盖)
1. 用户注册 → 登录 → 浏览物品 → 加入收藏
2. 用户下单 → 支付 → 收到确认 → 查看订单
3. ...

### 显式不覆盖的链路 (本 release 不做 E2E, 走 SMOKE)
1. 管理员后台导出报表
2. ...
```

---

## Step 2: 拆任务 (TASK-TEMPLATE 含 PLATFORM)

每个 TASK 块**必须**含 PLATFORM 字段:

```
TASK: [一句话描述]
ACCEPT: [Given/When/Then 可断言结果]
SOURCE: [ACCEPT 数值来源: §章节 / fixture: 路径 / FROZEN: 字段名]
FILES: [文件路径 + 一句话改什么]
IMPACT: [数据消费方, 多仓库格式 [仓库名]/path]
SMOKE: [最小可执行验证 + 业务断言]
BOUNDARY: [明确不改什么]
COVERAGE: [本任务覆盖什么/不覆盖什么/为什么]
HUMAN: [action:<前置清单> / decision:optimistic/deferred/阻塞 / 无(AI 自动化: <理由>)]
DEP: [依赖任务编号 / 无]
PLATFORM: <iOS|Android|Backend|Web|鸿蒙|小程序|All|None>
```

`PLATFORM` 合法值:
- `iOS` / `Android` / `Backend` / `Web` / `鸿蒙` / `小程序` — 只动单端代码
- `All` — 跨多端不可分拆 (慎用, 通常应拆为多个单端任务)
- `None` — 文档/配置/spec 任务

---

## Step 2.5: PLATFORM 字段反扫

拆任务完成后, 逐 TASK 块扫:

1. FILES 含 `ios/` 或 `*.swift` / `*.m` → 强制 PLATFORM 含 iOS
2. FILES 含 `android/` 或 `*.kt` / `build.gradle` → 强制 PLATFORM 含 Android
3. FILES 含 `server/` / `backend/` / `api/` → 强制 PLATFORM 含 Backend
4. FILES 同时含多端路径 → PLATFORM=All 且 BOUNDARY 必须说明"为什么不拆"
5. PLATFORM 必须出现在 PLATFORM-MATRIX 实际支持的端列表中
6. 不一致 → 阻塞, 要求修正

由 `sg_app_task_platform_field` 机械验证.

---

## Step 3: 多视角审查 (4 角色)

generic 要求 ≥3 必选角色, app 主线**追加第 4 角色**:

| 角色 | 只允许质疑这一类问题 |
|------|------------------|
| 需求审查员 | 用户故事完整性 / 验收标准可测 / 业务规则一致 |
| 证据审查员 | ACCEPT 数值来源 / SOURCE 字段引用真实 / fixture 路径存在 |
| 范围审查员 | TASK 边界清晰 / BOUNDARY 显式 / 无 scope creep |
| **多端体验审查员 (app 特有)** | iOS/Android/小程序 体验一致? 端侧能力差异在 PLATFORM-MATRIX 显式? 推送/支付/文件访问端差异在 spec 拍死? |

**调用模式:** 同一助理消息内并发 4 个 Agent. 验收 `roles[]` 长度 ≥4 含"多端体验"子串.

---

## Step 4: 前置人工动作反扫 (app 端侧补遗)

A-GATE 0 /anchor 已锁大部分前置动作 (Apple Developer / Play Console / 域名 / Stripe / RevenueCat). 此步补 A-GATE 0 未覆盖的端侧动作:

- 微信小程序主体注册 (公司主体, 6-7 天审批)
- 鸿蒙开发者公司主体 (国内身份证 + 公司证件)
- 国内 Android 推送多通道聚合 (极光/个推) 主账号
- APNs Auth Key 申请 (1 年有效, 到期需续)

每条按 generic 反扫规则: HUMAN: action:XX + 聚合到 spec.md 顶部"前置人工动作清单". 参照 `.claude/rules/core.md § GATE 0 → 前置人工动作清单`.

---

## Step 5: 写入 spec.md 完整版

```markdown
# spec.md (app 主线)

## A-GATE 0 产出 (来自 /anchor, 不在本 skill 修改)
- 命名锁定 / 单位经济 / 技术 spike / 后端就绪 / 合规扫描

## A-GATE 1 产出 (本 skill)
- 前置人工动作清单 (顶部)
- 全局认知 (产品定义 / 用户故事 / 不做清单 / 视觉方向)
- 覆盖契约 (FROZEN)
- 故障想象力
- PRD 挑战
- 核心难点
- PLATFORM-MATRIX (✨ app 特有)
- 数据契约 (含多端消费方 + 端侧独有字段)
- 多视角审查结果 (4 角色)
- 人确认清单
- 冻结边界
- 任务清单 (含 PLATFORM 字段)
- 风险
```

---

## Step 6: 写完成信号

```bash
mkdir -p .claude/state
echo "{\"skill\":\"shape\",\"epoch\":$(date +%s)}" > .claude/state/skill-signal.json
```

更新 `docs/status.md` 顶部 `CURRENT_GATE: A-GATE 2` + 勾上 A-GATE 1 进度.

---

## OUTPUT_GATE (stop-app-audit 验收)

15 项机械检查 + 追加 3 项 app 专属:

| 检查项 | 函数 |
|-------|-----|
| PROJECT_TYPE=app + CURRENT_GATE=A-GATE 1 | sg_app_project_type |
| PLATFORM-MATRIX 章节 + ≥8 行 + fallback 非空 | sg_app_platform_matrix |
| 每个 TASK 块含 PLATFORM 字段 + FILES 与 PLATFORM 一致 | sg_app_task_platform_field |
| PRD 挑战 ≥3 视角 + 缺口编号 + 处置标注 + ACCEPT 承接 | sg_app_prd_challenge |
| 故障想象力 ≥2 维度 + 主语 ≥60% + 对账标注 ≥1 + ACCEPT 覆盖 | sg_app_fault_imagination |
| 数据契约消费方含 ≥2 端 + 端侧独有字段子章节存在 | sg_app_data_contract |
| 覆盖契约 (核心+不覆盖) 章节存在 + FROZEN 标注 | sg_app_coverage_contract |

任一失败 → 阻塞 + 列缺失项. 5 分钟去重防死循环.

---

## DESIGN-FEED(投料单 —— 杠杆②:让最省事的路径 = 对的路径)

> **定位钉死:投料(prompt-feed),不是对账契约。** 明文禁止把 AI 生成的 mockup 接进 ui-diff/token-match 像素硬门——AI 图的假文案/幻觉布局会把实现往「像素复刻幻觉」上逼。视觉验收走质感门(实证版)+ VLM 建议档。
>
> **为什么要可执行物**:把要求写进 prompt 已被实证打脸(质感规则齐备照样裸奔)。真正改变生成分布的是:**对的做法成为最省事的做法**。

产两份:

**① `docs/DESIGN-FEED.md`(人读 + 喂 build 生成上下文)**
- 机器提取段(标 extracted):从用户拍板的 mockup 提色板/圆角(design-restore 抽取段现成可调)
- VLM 风格基因段(标 inferred):字体气质/纹理关键词/情绪词(如「蜡笔/纸纹/贴纸/圆胖」)
- 资产清单:本项目要出哪些图(图标/背景/按钮/庆祝件/mascot),各自风格要点
- juice/组件选用表:用基座哪些件(有基座时)

**② `lib/theme/design_feed.dart`(可执行物 —— 核心;照抄底:`bases/game-flutter/theme/design_feed_template.dart`,填 EXTRACTED 槽)**
把 ① 的 token 直接落成主题变量代码(色板/圆角/间距/字体槽赋值)。**UI 任务最省事路径 = import 这个主题**;想硬编码裸奔反而要多写代码。非 Flutter 栈落对应形态(SwiftUI Theme struct / CSS vars)。

**build 消费约定**:build Step 4 对任何 UI 任务,把 DESIGN-FEED.md + 基座组件目录注入实现上下文(开写之前,不是写完 Step 7.3 才见——7.3 保留当验收)。

## 完成后下一步

`完成: /shape 已产出 A-GATE 1 spec.md, 含 PLATFORM-MATRIX 和任务清单, 下一步 /build 进入 A-GATE 2`

或回到 A-GATE 0:

`停住: Step 3 多视角审查发现命名锁有漏 (P0-1), 回 /anchor 补完后重 /shape`
