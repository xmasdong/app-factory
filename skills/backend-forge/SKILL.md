---
name: backend-forge
description: "功能/契约 → 完整后端 API 服务。从 shape 数据契约 + manifest.screens 派生 screen→entity→endpoint(草稿,inferred 需人确认),产出 api/openapi.yaml(OpenAPI 3.1 SSOT),强制 ownership 越权矩阵,codegen 可靠区(Supabase migration+RLS / DTO / 校验 / SDK / 测试骨架),Schemathesis 契约测试 + 越权负向 + 业务规则三重夹。可单跑,经 shape/build/qa 内部调用,不进路由、不进 hook 状态机。"
---

# /backend-forge — 功能/契约 → 完整后端 API(App Factory 真 skill)

> 🔗 **App Factory 集成**:本 skill 是 design-first 增强的后端半边,与 design-restore(设计→前端)对称。
> - **唯一真相源**:`api/openapi.yaml`(OpenAPI 3.1,SSOT)。前端 mock(prism/msw)、各端 client SDK、后端骨架、契约测试**全从它生成**——前后端不 drift 靠机制(单一真相源)消灭,不靠纪律。
> - **不开新轨**:不进 7 关脊柱路由、不动 hook 状态机。可单跑(`/backend-forge`),也由 `shape`(派生数据契约后调本 skill 出 openapi)、`build`(后端任务实现时调)、`qa`(契约测试)内部调用。
> - **闸门初期全 advisory**(`sg_run_soft`,不阻塞),与"建议优先"哲学一致。

**作用:** 把"功能 + 数据契约"塑形成**能上线生产的后端 API 服务**。职责见契约:① 从 screen 派生 entity 再派生 endpoint(草稿,inferred 字段需人确认)→ 落 `api/openapi.yaml`;② 强制 **ownership 越权矩阵**(谁能 CRUD 谁的数据);③ codegen 可靠区(Supabase migration + RLS / DTO / 校验 / SDK / 测试骨架);④ 测试夹幻觉(Schemathesis property-based + 越权负向 + 业务规则走 ACCEPT 三重夹)。

**防幻觉铁律(讲死):**
- screen→entity→endpoint 派生**只是草稿**。`extracted` 字段可直接用,`inferred` 字段**必须人确认**才能 FROZEN。
- 强制 **ownership 越权矩阵**——"越权"是 AI 头号幻觉区,在 Supabase 用**声明式 RLS** 变成可审计 SQL。
- **三重夹**:Schemathesis 契约测试(schema 符合性)+ 越权负向测试(用户 A 的 token 取用户 B 的资源应 403)+ 业务规则走 ACCEPT(契约对≠业务对)。**契约测试不等于业务正确**,三者缺一不可。
- openapi.yaml + extracted 字段**默认 FROZEN**,变更**回 shape 重算**,不在本 skill 或 build 里默默改。

---

## INPUT_CONTRACT

必须同时满足(三选一缺则降级或拒绝):

1. **shape 数据契约表**(主输入):`docs/spec.md § 数据契约` 已存在,含字段 / 类型 / 单位·格式 / 生产者 / 消费方(按端)。高风险字段(金额/时间/枚举/ID)已声明单位值域。
2. **manifest.screens[].fields**(派生输入):`docs/design/design-manifest.json` 存在,`screens[]` 含 `id / name / fields[] / inferred_entities[] / inferred_endpoints[]`,且每字段标 `confidence: "extracted" | "inferred"`。
3. **lockdown 选定栈**(选型输入):`docs/lockdown/backend-readiness.md` 已选后端(Supabase 默认 / Firebase / PocketBase),含主体·收款资质决策。

**CONTRACT 不满足时:**
- 无数据契约表 **且** 无 manifest.screens → 拒绝执行,提示先跑 `/shape`(补数据契约)或 `/design-restore`(出 manifest)。
- 有 manifest 但无 lockdown 选型 → **降级默认 Supabase**,在 backend-readiness.md 如实标"选型由 backend-forge 默认推断,需人确认"。
- manifest 全字段 `confidence: inferred`(无任何 extracted)→ 不直接出 FROZEN openapi,先走 Step 1 派生草稿 + 强制人确认闸,再继续。
- 数据契约高风险字段缺单位/值域(金额无"分/元"、时间无格式、枚举无值域)→ 阻塞,回 shape 补全后重入。

**OUTPUT → `api/openapi.yaml`(OpenAPI 3.1 SSOT)+ ownership 越权矩阵 + codegen 产物 + 契约测试骨架 + `.claude/state/skill-signal.json`**

参照 `.claude/rules/core.md § 决策生命周期`(optimistic/confirmed/deferred/invalidated/fused)、`§ 禁止模式`(预建抽象 / 幽灵依赖 / 防御性冗余)。

---

## 执行计划

```
- [ ] Step 0: 读 lockdown/backend-readiness.md(选型) + spec.md 数据契约 + manifest.screens
- [ ] Step 1: 派生契约草稿 (screen→entity→endpoint),标 extracted/inferred
- [ ] Step 1.5: inferred 人确认闸 (inferred 字段/实体/端点逐条确认)
- [ ] Step 2: 高风险字段落 schema (金额=分/时间=ISO8601/枚举=enum/ID=format)
- [ ] Step 3: ownership 越权矩阵 (谁能 CRUD 谁的数据) — 强制
- [ ] Step 4: 写 api/openapi.yaml (OpenAPI 3.1 SSOT) + FROZEN 标注
- [ ] Step 5: codegen 可靠区 (Supabase migration+RLS / DTO / 校验 / SDK / 测试骨架)
- [ ] Step 6: 三重夹测试 (Schemathesis + 越权负向 + 业务规则 ACCEPT)
- [ ] Step 7: 写完成信号 + 更新 status.md
```

---

## Step 1: 派生契约草稿 (screen→entity→endpoint)

**为什么必填:** 后端不是凭空设计,而是从前端需要的数据**反推**。manifest.screens 的 fields 是机械抽出来的需求信号——派生让"屏需要什么数据"变成"后端提供什么端点"。

**⚠️ 这一步只产草稿。** `extracted` 字段(机械抽,可信)可直接进派生;`inferred` 字段(LLM 推断)进派生但**必须打 `inferred` 标**,等 Step 1.5 人确认。

### 派生规则(screen 类型 → endpoint)

| screen 类型(从 manifest 推断) | 派生 entity | 派生 endpoint |
|------------------------------|-----------|-------------|
| **list 屏**(列表/feed/卡片流) | 集合实体 | `GET /<entities>` 集合 + **分页**(cursor/offset)+ 过滤/排序 query |
| **detail 屏**(详情页) | 单实体 | `GET /<entities>/{id}` |
| **表单屏**(创建/编辑) | 写实体 | 创建 → `POST /<entities>`;编辑 → `PATCH /<entities>/{id}` |
| **删除按钮 / 状态钮**(归档/完成/取消) | 状态转换 | 删除 → `DELETE /<entities>/{id}`;状态切换 → `PATCH /<entities>/{id}`(改 status 字段) |
| **搜索屏** | 集合查询 | `GET /<entities>?q=&...` + 分页 |
| **auth 屏** | 会话 | `POST /auth/*`(委托后端栈,Supabase Auth / Firebase Auth) |

**分页强制:** 任何 list 屏派生的 `GET 集合` **必须**含分页参数(默认 cursor-based:`?cursor=&limit=`),并在 response 含 `next_cursor`。无分页 = 草稿不合格。

### 草稿格式(写入 `api/draft-derivation.md`,人确认后才进 openapi)

```markdown
## screen: <screen.id> (<list|detail|form|...>)

派生 entity: <Entity>  [confidence: extracted | inferred]
派生 endpoints:
- GET /entities?cursor=&limit=  → 集合 + 分页   [extracted]
- GET /entities/{id}            → 详情          [extracted]
- POST /entities                → 创建          [inferred ← form 屏推断,需确认动作语义]
字段来源: manifest.screens[<id>].fields + spec 数据契约 §<n>
```

---

## Step 1.5: inferred 人确认闸(强制)

**为什么必填:** 防幻觉铁律——AI 推断的 entity/endpoint/字段可能是幻觉(屏上有个按钮 ≠ 后端真要这个端点)。`extracted` 自动过,`inferred` **逐条等人确认**。

逐条列出所有 `inferred` 项,每项一个处置(三选一):

- `confirmed` — 人确认,升级为可进 openapi(去掉 inferred 标)。
- `deferred` — 本 release 不做这个端点/字段,给理由。
- `invalidated` — 推断错了(屏上的按钮不对应后端动作),删掉,给理由。

**不允许把 inferred 直接当 extracted 进 openapi。** 全部 inferred 项处置完(或显式 `confirmed`)才进 Step 2。参照 `.claude/rules/core.md § 决策生命周期`。

---

## Step 2: 高风险字段落 schema

**为什么必填:** 高风险字段是前后端 drift + 生产事故的高发区。spec 数据契约已声明单位值域,本步把它**机械落进 OpenAPI schema 的 `format` / `enum`**,让"分还是元""ISO8601 还是 Unix"不再靠口头约定。

| 字段类 | OpenAPI schema 落法 |
|-------|-------------------|
| **金额** | `type: integer, format: int64` + `description: "单位=分(cent),禁止小数"`。**永远存分**,前端展示再除 100。 |
| **时间** | `type: string, format: date-time` + `description: "ISO8601 UTC,如 2026-06-30T12:00:00Z"`。禁混用 Unix。 |
| **枚举** | `type: string, enum: [pending, paid, shipped, completed, cancelled]`。**值域全列**,不留"其他"。 |
| **ID** | `type: string, format: uuid`(或 `int64`,与 spec 一致)。`x-ownership` 标谁拥有(见 Step 3)。 |
| **分页游标** | `cursor: {type: string, nullable: true}`,opaque,禁前端解析。 |

每个高风险字段的 `format`/`enum` 必须**可追溯到 spec 数据契约的 SOURCE**(`§章节` / `FROZEN: 字段名`)。无追溯 = 该字段不合格。

---

## Step 3: ownership 越权矩阵(强制)

**为什么必填:** "越权"是 AI 头号幻觉区——AI 写 endpoint 时默认"登录就能访问",忘记"只能访问自己的数据"。这一步把"谁能 CRUD 谁的数据"**显式建表**,再落成 Supabase 声明式 RLS(可审计 SQL),并产出 Step 6 的越权负向测试。

### 越权矩阵(写入 `api/ownership-matrix.md`)

```markdown
| Entity | owner 字段 | 角色 | Create | Read | Update | Delete | 越权边界 |
|--------|-----------|------|--------|------|--------|--------|---------|
| order  | user_id   | owner| ✅自己  | ✅自己 | ✅自己  | ❌      | 只能读写 user_id=auth.uid() 的行 |
| order  | user_id   | admin| ❌      | ✅全部 | ✅status| ✅      | admin 可读全部,只能改 status |
| order  | user_id   | 匿名 | ❌      | ❌    | ❌      | ❌      | 未登录全拒 |
| post   | author_id | 作者 | ✅      | ✅公开 | ✅自己  | ✅自己  | 改/删限 author_id=auth.uid() |
```

**强制规则:**
1. **每个 entity 必须有 owner 字段**(`user_id` / `author_id` / `team_id` …)。无所有者的全局只读资源显式标"public,无 owner"。
2. **每个角色 × 每个 CRUD 动作必须有明确判定**(✅/❌/受限),不留空。
3. **越权边界一句话写死**:owner 角色的边界必须是"行级 = `<owner字段> = auth.uid()`"或等价表述。
4. 矩阵的每一行**对应一条 Step 5 的 RLS policy** 和一条 Step 6 的越权负向测试——三者数量对账。

### 落 OpenAPI

每个 endpoint 的 schema 加 `x-ownership` 扩展:

```yaml
paths:
  /orders/{id}:
    get:
      x-ownership: { entity: order, rule: "owner OR admin", owner_field: user_id }
      security: [{ bearerAuth: [] }]
```

---

## Step 4: 写 api/openapi.yaml(OpenAPI 3.1 SSOT)

把 Step 1-3 的产物合成**唯一真相源**:

```yaml
openapi: 3.1.0
info: { title: <app> API, version: 0.1.0 }
x-frozen: true          # extracted 字段 + 本文件默认 FROZEN
x-backend: supabase     # 来自 lockdown 选型
paths:
  /orders:
    get:                # list 屏派生,含分页
      parameters:
        - { name: cursor, in: query, schema: { type: string, nullable: true } }
        - { name: limit,  in: query, schema: { type: integer, default: 20, maximum: 100 } }
      responses:
        '200':
          content:
            application/json:
              schema:
                type: object
                properties:
                  items: { type: array, items: { $ref: '#/components/schemas/Order' } }
                  next_cursor: { type: string, nullable: true }
    post:               # 表单屏派生
      requestBody: { $ref: '#/components/requestBodies/OrderCreate' }
      responses: { '201': { ... }, '403': { description: 越权 }, '422': { description: 校验失败 } }
components:
  schemas:
    Order:
      type: object
      required: [id, user_id, amount, status, created_at]
      properties:
        id:         { type: string, format: uuid }
        user_id:    { type: string, format: uuid, description: "owner(RLS: =auth.uid())" }
        amount:     { type: integer, format: int64, description: "单位=分" }
        status:     { type: string, enum: [pending, paid, shipped, completed, cancelled] }
        created_at: { type: string, format: date-time, description: "ISO8601 UTC" }
```

**硬规则:**
- 每个写端点必须显式声明 `403`(越权)和 `422`(校验失败)response。
- `x-frozen: true` + 顶部注释"变更回 /shape 重算数据契约,不在 build 改"。
- OpenAPI 3.1 用 JSON Schema 2020-12,`nullable` 用 `type: [string, "null"]` 或保留兼容写法,统一一种。

由 `sg_app_openapi_artifact` 验收(文件存在 + 3.1 合法 + 每写端点含 403/422 + 高风险字段含 format/enum)。

---

## Step 5: codegen 可靠区(机制消灭 drift)

**从 openapi.yaml 单向生成**,不手写、不反向回填。codegen 区 = "可靠区"(机械生成,低幻觉),手写区 = 业务逻辑(高风险,需 Step 6 业务测试夹)。

| 产物 | 工具(Supabase 栈) | 说明 |
|-----|------------------|-----|
| **DB migration + RLS** | 从 schema + ownership 矩阵生成 `supabase/migrations/*.sql` | 每张表 + 每条 ownership 行 → 一条 `CREATE POLICY ... USING (auth.uid() = user_id)` |
| **DTO / 类型** | `openapi-typescript` / 各端 codegen | 服务端 + 各端共享类型,杜绝字段名 drift |
| **请求校验** | 从 schema 生成 zod / pydantic validator | 金额是 int、枚举值域、必填——边界由 schema 保证 |
| **client SDK** | `openapi-generator` per platform(Swift/Kotlin/TS) | 前端不手写 HTTP,SDK 从 SSOT 生成 |
| **前端 mock** | `prism mock api/openapi.yaml` / msw handler | 前端不等后端,mock 也从 SSOT 生成(前后端同源) |
| **测试骨架** | Schemathesis 从 openapi 自动生成用例 + 越权/业务测试桩 | 见 Step 6 |

**RLS 生成铁律(Supabase):**
- 每个 entity 默认 `ALTER TABLE <t> ENABLE ROW LEVEL SECURITY;`(默认全拒,显式放行)。
- ownership 矩阵的每一行 → 一条 policy,owner 角色固定 `USING (auth.uid() = <owner_field>)`。
- admin 角色用 `auth.jwt() ->> 'role' = 'admin'` 判定,**不在应用层判越权**(应用层判 = 头号幻觉)。
- 生成的 SQL 必须可 `supabase db reset` 重放。

遵循 `.claude/rules/core.md § 禁止模式`:codegen 产物不算"预建抽象"(它有真实消费者=各端 SDK);但**手写**为"将来可能"加的端点/字段算违规。

---

## Step 6: 三重夹测试(测试夹幻觉)

**为什么必填:** 契约对≠业务对。三层各夹一类幻觉,缺一不可。

### 夹 1 — Schemathesis 契约测试(schema 符合性,property-based)

```bash
schemathesis run api/openapi.yaml --base-url $TEST_API --checks all
```
- property-based:自动从 schema 生成边界/异常输入,验证 response 永远符合 schema。
- 夹的幻觉:实现返回了 schema 没声明的字段 / 缺必填 / 类型错 / 状态码不在声明集。

### 夹 2 — 越权负向测试(ownership 矩阵每行一条)

**核心断言:用户 A 的 token 访问用户 B 的资源 → 必须 403(不是 200 空、不是 404 混淆、不是 500)。**

```
为 ownership-matrix.md 每一行生成:
- 正向: owner 用自己 token 访问自己资源 → 2xx
- 负向: 用户A token 访问用户B 资源 → 403   ← 头号幻觉拦截点
- 匿名: 无 token 访问受保护资源 → 401
- 越权写: 用户A 试图 PATCH 用户B 资源 → 403 且 B 的数据未变(读回验证)
```
- 夹的幻觉:RLS 写漏 / 应用层误判 / "登录即可访问"。
- 越权测试**数量必须 = ownership 矩阵行数**(Step 3 对账)。

### 夹 3 — 业务规则走 ACCEPT(契约测试管不到的语义)

契约测试只验"形状",验不了"满员后不能再下单""金额不能为负""取消后不能支付"这类**业务规则**。这些走 spec 的 ACCEPT(Given/When/Then):

```
ACCEPT (来自 spec § 故障想象力 / PRD 挑战):
- Given 库存=0, When POST /orders, Then 返回 409 且不创建订单
- Given order.status=cancelled, When PATCH status=paid, Then 返回 422 拒绝非法状态转换
- Given amount<0, When POST /orders, Then 422
```
- 夹的幻觉:schema 合法但业务非法(状态机乱转 / 余额穿透 / 重复扣款)。
- 业务 ACCEPT 必须可追溯到 spec(§故障想象力 / §PRD 挑战 / §核心难点的状态机)。

由 `sg_app_contract_test`(夹1+夹2)+ `sg_app_e2e_contract_smoke`(夹3 关键链路)验收。三层缺任一 → 测试不完整。

---

## Step 7: 写完成信号

```bash
mkdir -p .claude/state
echo "{\"skill\":\"backend-forge\",\"epoch\":$(date +%s)}" > .claude/state/skill-signal.json
```

更新 `docs/status.md`:勾上 backend-forge 进度 + 记 openapi.yaml 路径 + FROZEN 状态 + 任何 deferred 端点。

---

## OUTPUT_GATE(advisory,初期 sg_run_soft 不阻塞)

| 检查项 | 函数 |
|-------|-----|
| `api/openapi.yaml` 存在 + OpenAPI 3.1 合法 | sg_app_openapi_artifact |
| 数据契约 extracted 字段全落 schema + 高风险字段含 format/enum | sg_app_data_contract |
| 每写端点含 403(越权)+ 422(校验)response | sg_app_openapi_artifact |
| ownership 越权矩阵存在 + 每 entity 有 owner + 每角色×CRUD 有判定 | sg_app_contract_test |
| inferred 项全部处置(confirmed/deferred/invalidated) | sg_app_data_contract |
| Schemathesis 契约测试通过(夹1) | sg_app_contract_test |
| 越权负向测试存在且数量=矩阵行数,A 取 B 资源=403(夹2) | sg_app_contract_test |
| 业务规则 ACCEPT 关键链路冒烟(夹3) | sg_app_e2e_contract_smoke |
| Supabase migration+RLS 可重放,每 entity 已 ENABLE RLS | sg_app_contract_test |

**OUTPUT_GATE 不通过时(advisory 模式):**
- 失败回灌为 stderr 建议,不硬阻塞(初期与"建议优先"哲学一致)。
- inferred 未处置 / 越权测试缺失 / 高风险字段无 format 是**强建议必补**项。
- 后期可切 `sg_run_hard` 升为阻塞。

变更 extracted 字段或 openapi schema → **回 /shape 重算数据契约**,不在本 skill 或 /build 静默改。参照 `.claude/rules/core.md § 决策生命周期 → FROZEN`。

---

## 完成后下一步

`完成: /backend-forge 已产出 api/openapi.yaml(SSOT)+ ownership 越权矩阵 + codegen 产物 + 三重夹测试, 前端可从同源 mock 开发, /build 后端任务从 openapi 续接`

或回 shape:

`停住: Step 1.5 发现 inferred 端点 POST /payments 语义不明(表单屏推断不出是创建还是确认), 回 /shape 补数据契约动作语义后重 /backend-forge`

或 advisory 提示:

`建议: 越权负向测试覆盖了 4/5 矩阵行, post.delete 缺 A 删 B 的负向用例, 建议补全后再进 /qa`
