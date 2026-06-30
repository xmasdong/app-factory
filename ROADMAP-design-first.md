# ROADMAP — Design-First 增强

> App Factory 的 design-first 增强设计文档 / 路线图。给仓库留痕、给协作者看。
> 本文 = 蓝图(blueprint)+ 落地优先级。务实、诚实,不画饼。
> 与现有脊柱(`ORCHESTRATION.md` 的 7 关)互补,**不另开一条轨**。

---

## 0. TL;DR(一段话)

把"导入一张图 / 一个设计稿"接进现有 `scaffold→discover→lockdown→shape→build→qa→ship` 脊柱:加 **2 个可单跑的真 skill**(`design-restore` 把设计还原成高保真前端、`backend-forge` 把功能/契约长成后端 API),它们经 shape/build/qa **内部调用**——**不进路由、不进 hook 状态机**。两份 FROZEN 机读产物当唯一真相源(`docs/design/design-manifest.json` 管 UI、`api/openapi.yaml` 管后端),下游全从机读产物派生,**机制消灭 drift 而不是靠纪律**。闸门初期一律 `sg_run_soft`(advisory 不阻塞),与现有"建议优先"哲学一致。

---

## 1. 终极目标

辅助:**导入一张图 / 一个设计稿 → 产出能上线生产的 app**(高保真前端 + 完整后端 API 服务)。

不是目标:取代设计师、取代后端工程师、一键全自动无人值守。这是**辅助管线**:把"看图 → 还原 → 接后端"这条最耗体力、最易出错的链路自动化到 80%,剩下 20%(业务规则、越权边界、视觉验收阈值)**显式留给人确认**。诚实天花板见 §9。

---

## 2. 推荐架构(已定,不要改)

### 决策
- **不开新轨、不动 hook 状态机。** 复用现有 7 关脊柱:`scaffold→discover→lockdown→shape→build→qa→ship`。
- **2 个新「真 skill」**:
  - `design-restore` — 设计 → 高保真 app(抽取 + reify)
  - `backend-forge` — 功能 / 契约 → 后端 API
  - 两者**可单跑**(`/design-restore`、`/backend-forge`),也被 shape/build/qa **内部调用**;**不进路由(`app-factory` facade)、不进 hook 状态机**。
- **2 份 FROZEN 机读产物当唯一真相源**(下游只认机读产物,**不直接解析原始 `.pen`/Figma**)。

### 理由(为什么是嵌入式骨架 + 两可单跑引擎 + 两份机读产物当桥)

| 选择 | 替代方案 | 为什么选它 |
|---|---|---|
| **嵌入进 7 关,不开新轨** | 开一条 design→build 平行轨 | 平行轨要重做闸门 / clearance / hook 续接,维护翻倍;且 design-first 和"做 X"主线共享 lockdown(命名/合规/经济)、qa(截图/审核)、ship(上架)——拆开就是重复造轮子 |
| **不动 hook 状态机** | 给 hook 加 design 状态 | hook 状态机是脆弱区,一动就可能破坏现有自动续接;新能力以"被调用的 skill"形态存在,状态机无感知,**回归风险 = 0** |
| **2 个可单跑引擎** | 把逻辑塞进 shape/build | 单跑 = 可独立测试、可被非 app-factory 项目复用、debug 时能孤立运行;塞进脊柱则耦合死、无法 A/B |
| **2 份机读产物当桥** | 下游直接读 `.pen`/Figma | 原始设计格式易变、需要桌面 app/网络、解析昂贵;机读产物是**稳定快照 + 单一真相源**,FROZEN 后下游一致,且 manifest/openapi 可 diff、可进 git、可机器校验 |

---

## 3. 端到端流程(7 关复用,design-first 各关做什么 / 跳什么)

design-first 是脊柱的一个**输入模式**,不是新流程。下表给每关的增量:

| 关 | 普通模式 | design-first 增量 | 跳什么 |
|---|---|---|---|
| **scaffold** | 建骨架 + 装 hook | 多建 `docs/design/`、`api/` 目录占位;`PROJECT_TYPE=app` 不变 | — |
| **discover** | 抽词→市场调研→AI 自决形态 | 形态/视觉**已由设计稿给定**,discover 退化为"验证这个设计对应的需求真存在"(市场证据仍要跑) | **跳概念 mockup 生成**(设计稿即视觉真相,不再用 codex-image 凭空造) |
| **lockdown** | spike/经济/命名/合规 | 多产 `backend-readiness.md` 写**后端选型**(见 §7);命名/经济/合规照跑 | — |
| **shape** | PRD/矩阵/数据契约/任务 | 调 `design-restore`(抽取段)产 `design-manifest.json` + `tokens.json` + baseline PNG;调 `backend-forge`(派生段)产 `api/openapi.yaml` 草稿;**manifest.screens[].fields 同源喂数据契约**(见 §5) | **不再用 frontend-design 从零定设计系统**(设计稿即设计系统;token 从设计稿抽,不另造) |
| **build** | 逐任务实现 | `design-restore`(reify 段)只**引用 token** 实现各屏;`backend-forge` 从 openapi 生后端骨架 + mock + client SDK;截图 diff 闭环逼近 baseline | — |
| **qa** | 覆盖契约/smoke/审核预演 | 多跑 UI 视觉/ token diff(advisory)+ 后端契约测试 + 越权负向测试 | — |
| **ship** | ASO/商店材料/上传 | 完全复用,无增量 | — |

> 关键:**discover/shape 的"视觉创造"环节被设计稿替代为"视觉还原"**;其余闸门(市场证据、命名、合规、经济、上架)一个都不少。

---

## 4. 两个新 skill 的职责

### `design-restore`(设计 → 高保真 app)
- **作用**:把设计稿 reify 成高保真前端。**reify ≠ create**——它还原既有设计,**不和 `frontend-design` 抢"创造 UI"**。
- **两段**:
  1. **抽取段**(shape 内调):把 `.pen`/Figma/截图 → `design-manifest.json` + `tokens.json` + baseline PNG。机械能抽的标 `extracted`,LLM 推断的标 `inferred`。
  2. **reify 段**(build 内调):按 manifest 逐屏实现,**实现处只引用 token、禁硬编码值**;跑截图 diff 闭环逼近 baseline。
- **铁律**:见 §6 UI 三层闸门 + §8 缓解。

### `backend-forge`(功能 / 契约 → 后端 API)
- **作用**:把功能需求 / 数据契约长成完整后端 API 服务。
- **核心**:`api/openapi.yaml`(OpenAPI 3.1)当 SSOT;一份同时生 **前端 mock(prism/msw)+ 各端 client SDK + 后端骨架 + 契约测试**。
- **派生**:`screen → entity → endpoint` 的推断**只是草稿,`inferred` 需人确认**;强制 **ownership 越权矩阵**(谁能 CRUD 谁的数据);Supabase RLS 声明式落地。
- **铁律**:见 §6 后端三层闸门 + §8 缓解。

> 两个 skill 都用 frontmatter(`--- name: / description: ---`)+ **作用** + INPUT_CONTRACT + 执行计划 + 分步骤 + OUTPUT_GATE,与 `skills/shape/SKILL.md` 同款结构。不绑任何具体 app。

---

## 5. 核心桥:两份 SSOT,机制消灭 drift

### 5.1 两份 FROZEN 机读产物(路径 + schema 固定)

**1) `docs/design/design-manifest.json` — 设计 → UI 真相源**
```jsonc
{
  "source": "pen" | "figma" | "screenshot",
  "tokens": {                                  // W3C DTCG 风格
    "color": {}, "space": {}, "radius": {}, "type": {},
    "theme": ["light", "dark"]
  },
  "components": [
    { "name": "", "reusable": true, "props": [], "states": [] }
  ],
  "screens": [
    {
      "id": "", "name": "", "baseline_png": "",
      "layout_tree": {}, "texts": [], "nav_to": [],
      "inferred_states": ["empty", "loading", "error", "..."],
      "fields": [],                            // ← 同源:既喂前端契约,又被后端派生
      "inferred_entities": [],
      "inferred_endpoints": []
    }
  ]
  // 每字段标 confidence: "extracted"(机械抽,可信) | "inferred"(LLM 推断,需人确认)
}
```

**2) `docs/design/tokens.json` — W3C DTCG token**
喂 Style Dictionary 出各端:SwiftUI / Flutter / Compose / Tailwind。

**3) `docs/design/baseline/<platform>/<viewport>/<screen>.png` — 设计基线图**
视觉 diff 的基准。

**4) `api/openapi.yaml` — OpenAPI 3.1,功能 → 后端唯一真相源(SSOT)**
一份同时生:前端 mock(prism/msw)+ 各端 client SDK + 后端骨架 + 契约测试。

### 5.2 `manifest.screens[].fields` 同源机制(怎么消灭 drift)

```
                  manifest.screens[].fields  (单一字段定义源, extracted 优先)
                   /                       \
       喂前端契约(数据契约消费方)      被后端派生(backend-forge → openapi schema)
                   \                       /
                    api/openapi.yaml  (SSOT)
                   /        |          \
            前端 mock    后端骨架      契约测试
          (prism/msw)  (Supabase)  (Schemathesis)
```

- **同一份 `fields`**:前端契约(数据契约消费方)和后端 schema 派生**共用同一来源**,而不是各写一份再"对齐"。
- **机制消灭 drift,不靠纪律**:
  - `extracted` 字段 + `openapi.yaml` 默认 **FROZEN**。
  - 前端 mock、后端骨架、契约测试**全部从 `openapi.yaml` 生成**——三者天生一致,不存在"忘了同步"。
  - 要改字段?**回到 shape 重算**,重新派生,而不是在某一端手改。

---

## 6. 保真 / 正确性闸门(UI 三层 + 后端三层,advisory 优先)

> 闸门函数名固定。**初期全 `sg_run_soft`(advisory,不阻塞)**,与现有"建议优先"哲学一致。要硬闸门:`export APP_FACTORY_MODE=strict`。

### UI 三层(design-restore)
1. **`sg_app_design_baseline_exists`** — baseline PNG 存在且与 manifest.screens 对齐(每屏有图)。
2. **`sg_app_design_token_match`** — 实现只引用 token、无硬编码颜色/间距值(静态扫代码)。
3. **`sg_app_ui_visual_diff`** — 截图 vs baseline 的视觉 diff;**停止判据 = 分数单调下降才继续,不降即停上报**(不追求 0,追求"还在变好")。

### 后端三层(backend-forge)
1. **`sg_app_openapi_artifact`** — `api/openapi.yaml` 存在、合法 OpenAPI 3.1、可解析。
2. **`sg_app_contract_test`** — Schemathesis 契约测试 + **越权负向测试**(用户 A token 取用户 B 资源应 403)。
3. **`sg_app_e2e_contract_smoke`** — 端到端契约冒烟(前端 mock ↔ 后端骨架 ↔ client SDK 走通一条核心链路)。

### 跨层 / shape 内
- **`sg_app_data_contract`**(MVP-0 补实)— 数据契约消费方含 ≥2 端 + 端侧独有字段子章节;design-first 下额外校验 `fields` 与 manifest 同源。

> **契约测试 ≠ 业务正确。** 契约测试只保证"形状对、越权挡住";**业务规则正确性走 ACCEPT 三重夹**(见 §8),不在自动闸门内假装能验。

---

## 7. 后端选型

| 选型 | 用途 | 为什么 |
|---|---|---|
| **Supabase(默认)** | 绝大多数 app | Postgres + **声明式 RLS**,把"越权"这个 AI 头号幻觉区变成**可审计 SQL**(而不是散落代码里的 if 判断) |
| Firebase | 仅实时同步场景 | 实时强,但**警惕账单**(读多即烧钱);非默认 |
| PocketBase | 极简副业 | 单文件、零运维;能力上限低,只配最小 app |

选型结论写进 **lockdown 的 `backend-readiness.md`**(含:选哪个 / 为什么 / RLS 越权矩阵草稿 / 账单风险)。

---

## 8. 对抗检查表(每个风险配缓解)

| # | 风险(它会怎么坑你) | 缓解 |
|---|---|---|
| 1 | **设计吸收失真** — 抽取阶段就把设计读歪,后面全错 | 优先 `get_variables`/`get_editor_state` **机械抽**(标 `extracted`);LLM 推断的标 `inferred` 隔离;baseline PNG 留底可回溯对照 |
| 2 | **还原不像** — reify 出来和设计稿差很远 | 截图 diff 闭环,**停止判据 = 分数单调下降**;不降即停并上报,不硬刷;只引用 token 减少凭空发挥 |
| 3 | **后端幻觉业务规则** — AI 编造"应该有"的规则/权限 | 派生 endpoint 全标 `inferred` **需人确认**;业务规则**不进自动闸门**,走 ACCEPT 三重夹;强制 ownership 越权矩阵 |
| 4 | **前后端 drift** — 前端和后端字段/契约慢慢分叉 | `openapi.yaml` 单一真相源,mock+后端+测试**全从它生成**(机制非纪律);`extracted` 字段 + openapi **FROZEN by default**,变更回 shape 重算 |
| 5 | **断点 state 隐形** — empty/loading/error 等状态被漏掉 | manifest 每屏强制 `inferred_states`;reify 时逐 state 实现;qa 对账覆盖契约时校验 state 覆盖 |
| 6 | **闸门沦摆设** — advisory 久了没人看 | 闸门产**机读 signal**(进 `verify-report.json`);strict 模式可一键转硬闸;MVP 阶段至少保证"分数单调下降"这条**自动可比**的硬信号不靠人眼 |

### 视觉 diff 的误杀防护(并入风险 2 的具体落地)
- **禁动画**(diff 前冻结)。
- **mask 动态区**(头像 / 时间 / 随机内容)——否则纯像素 diff **误杀 30-40%**。
- **固定 DPR**(避免缩放伪差异)。

### `.pen` 不可达的降级链(并入风险 1)
pencil MCP 依赖桌面 app 运行(`get_editor_state` 可能报 *WebSocket not connected*)。**必须有降级链**:
```
.pen 可达 → pencil MCP 全抽(get_variables → batch_get 屏清单 → 组件 → 逐屏 layout_tree → snapshot_layout → export_nodes PNG)
.pen 不可达 → 退到导出的 PNG → 走截图档(VLM 抽)→ manifest 如实标低置信度(confidence: inferred)
```

---

## 9. 诚实天花板(不画饼)

1. **`screen → entity → endpoint` 反推有结构性上限。** 从界面**反推不出**:多对多关系的连接表、软删除/审计字段、事务边界、复杂权限、计费规则。这些**必须人确认**,manifest/openapi 里全标 `inferred`,**不假装自动派生正确**。
2. **视觉 diff 阈值无先验,需要攒。** "diff 多少算够像"没有放之四海的数字——不同 app/不同屏阈值不同。**初期不设硬阈值**,只用"单调下降"这条相对信号;阈值靠跨项目积累(写进 lessons)后才敢硬化。
3. **截图是一等输入,不是退路。** 用户**多用 codex-image 出的 PNG mockup**,而非干净 Figma。截图档(VLM 抽)必须和 `.pen` 档一样被认真对待、一样产合法 manifest(只是 confidence 标低),**不是 fallback 二等公民**。
4. **契约测试 ≠ 业务正确;还原像 ≠ 设计意图对。** 自动闸门能保证"形状/越权/像素",**保证不了"产品逻辑对"**。这部分诚实地留给人(ACCEPT 三重夹 / 人确认 inferred)。

---

## 10. MVP 优先级(先补地基,推断半条最后做)

> 原则:先把**已有契约补实**和**两份桥**立住(确定性高、收益大),把**最不确定的推断**(screen→endpoint 反推)放最后,且只做"半条"(草稿 + 人确认),不假装全自动。

| 阶段 | 做什么 | 产物 / 闸门 | 为什么这个顺序 |
|---|---|---|---|
| **MVP-0** | 补实 `sg_app_data_contract`(shape 已有但要落 design-first 同源校验) | `sg_app_data_contract` 可跑 | 地基:`fields` 同源是后面两座桥的共同支点,先立住 |
| **MVP-1** | **后端桥** — `backend-forge` + `api/openapi.yaml` SSOT + 从它生 mock/后端/SDK/契约测试 | `sg_app_openapi_artifact` / `sg_app_contract_test` / `sg_app_e2e_contract_smoke` | 后端确定性高(OpenAPI 是成熟标准,工具链齐),先拿确定收益 |
| **MVP-2** | **设计桥** — `design-restore` 抽取段 + `design-manifest.json` + `tokens.json` + baseline PNG + token diff | `sg_app_design_baseline_exists` / `sg_app_design_token_match` / `sg_app_ui_visual_diff` | 设计抽取比后端不确定(依赖 pencil/VLM),放第二 |
| **MVP-3** | **推断半条**(最后)— `screen→entity→endpoint` 反推草稿 + 强制人确认回路 | inferred 标注 + 人确认 gate | 最不确定、结构性上限最低(见 §9.1),**只做半条**:出草稿 + 逼人确认,不全自动 |

---

## 附:固定命名速查(改动须保持全文一致)

- **新 skill**:`design-restore`、`backend-forge`
- **桥产物**:`docs/design/design-manifest.json`、`docs/design/tokens.json`、`docs/design/baseline/<platform>/<viewport>/<screen>.png`、`api/openapi.yaml`
- **闸门函数**(初期全 `sg_run_soft` advisory):
  `sg_app_data_contract`(MVP-0 补实)/ `sg_app_openapi_artifact` / `sg_app_design_baseline_exists` / `sg_app_ui_visual_diff` / `sg_app_design_token_match` / `sg_app_contract_test` / `sg_app_e2e_contract_smoke`
- **后端默认**:Supabase(选型写进 lockdown 的 `backend-readiness.md`)
