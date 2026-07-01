---
name: backend-forge
description: "功能/契约 → 完整后端 API 服务。从 shape 数据契约 + manifest.screens 派生 screen→entity→endpoint(草稿,inferred 需人确认),openapi.yaml(3.1)先定稿当 SSOT,强制 ownership 越权矩阵,codegen 可靠区(Supabase migration+RLS / DTO / 校验 / SDK),三重夹测试(Schemathesis 契约 + 越权负向 + 业务规则)。真 app 跑时由 AI 调用 Workflow 工具编排(按 endpoint 扇出 + 业务规则对抗验证);推荐用户开 ultracode 模式;无法编排时降级单 agent 顺序,产 .claude/state/contract-test.json + e2e-contract.json 喂闸门。可单跑,经 shape/build/qa 调用,不进路由、不进 hook 状态机。"
---

# /backend-forge — 功能/契约 → 完整后端 API(App Factory 真 skill)

> 🔗 **App Factory 集成**:本 skill 是 design-first 增强的后端半边,与 design-restore(设计→前端)对称。
> - **唯一真相源**:`api/openapi.yaml`(OpenAPI 3.1,SSOT)。前端 mock(prism/msw)、各端 client SDK、后端骨架、契约测试**全从它生成**——前后端 drift 靠机制(单一真相源)消灭,不靠纪律。
> - **不开新轨**:不进 7 关脊柱路由、不动 hook 状态机。可单跑(`/backend-forge`),也由 `shape`(派生数据契约后调本 skill 出 openapi)、`build`(后端任务实现时调)、`qa`(契约测试)内部调用。
> - **闸门初期全 advisory**(`sg_run_soft`,不阻塞),与"建议优先"哲学一致。

> ⚠️ **真 app 跑法(读到这里先看这条)**:为真实 app 跑 backend-forge **不走下面的线性 Step**,而是
> `# 真 app 跑:你(AI)用内置 Workflow 工具按 skill 编排意图当场组合 script 执行;扇出结构参考蓝图 /Users/xmasdong/opc/app-factory/scripts/design-first/backend-forge.workflow.js(仅参考蓝图)`
> 即由 AI 用内置 Workflow 工具做**多 agent 编排**(ultracode 模式下 AI 默认倾向用它):openapi 先定稿当 SSOT → **按 endpoint 扇出**(每 endpoint:生成实现 → 契约测试 → 越权负向,pipeline 串)→ **业务规则对抗验证**(N skeptic 各自质疑,多数过才留)→ completeness critic 汇总写闸门 JSON。
> **线性 Step 1..7 仅作单 agent 降级档**(会话未开 ultracode、AI 未用 Workflow 工具编排时手跑)。详见 [## 主执行路径:AI 调用 Workflow 工具编排(推荐用户开 ultracode;降级=单 agent 顺序)](#主执行路径ai-调用-workflow-工具编排推荐用户开-ultracode降级单-agent-顺序)。

**作用:** 把"功能 + 数据契约"塑形成**能上线生产的后端 API 服务**。职责见契约:① 从 screen 派生 entity 再派生 endpoint(草稿,inferred 字段需人确认)→ openapi.yaml **先定稿当 SSOT**;② 强制 **ownership 越权矩阵**(谁能 CRUD 谁的数据);③ codegen 可靠区(Supabase migration + RLS / DTO / 校验 / SDK / 测试骨架);④ 三重夹测试(Schemathesis property-based 契约 + 越权负向 + 业务规则走 ACCEPT)。

**防幻觉铁律(讲死,Workflow 与线性档都遵守):**
- screen→entity→endpoint 派生**只是草稿**。`extracted` 字段可直接用,`inferred` 字段**必须人确认**才能 FROZEN。
- 强制 **ownership 越权矩阵**——"越权"是 AI 头号幻觉区,在 Supabase 用**声明式 RLS** 变成可审计 SQL。越权负向测试**数量必须 = 矩阵行数**。
- **三重夹**:契约测试(schema 符合性)+ 越权负向(用户 A 的 token 取用户 B 的资源应 403)+ 业务规则走 ACCEPT(契约对≠业务对)。**契约测试不等于业务正确**,三者缺一不可。
- **mock ≠ real**:对 prism mock 跑 → `target=mock`(闸门会点名上线前对 real 复跑);只有对真后端跑过才填 `target=real`。**别把 mock 谎报成 real。**
- openapi.yaml + extracted 字段**默认 FROZEN**,**先定稿再扇出**:endpoint 扇出从已写盘的 openapi.yaml 解析 path,**扇出过程中不能改 SSOT**(并行 worker 同时改 openapi.yaml 会互相覆盖)。改字段**回 /shape 重算**。

---

## INPUT_CONTRACT

必须同时满足(三选一缺则降级或拒绝):

1. **shape 数据契约表**(主输入):`docs/spec.md § 数据契约` 已存在,含字段 / 类型 / 单位·格式 / 生产者 / 消费方(按端)。高风险字段(金额/时间/枚举/ID)已声明单位值域。
2. **manifest.screens[].fields**(派生输入):`docs/design/design-manifest.json` 存在,`screens[]` 含 `id / name / fields[] / inferred_entities[] / inferred_endpoints[]`,且每字段标 `confidence: "extracted" | "inferred"`。
3. **lockdown 选定栈**(选型输入):`docs/lockdown/backend-readiness.md` 已选后端(Supabase 默认 / Cloudflare / Firebase / PocketBase),含主体·收款资质决策。选定栈**必须是 `env-probe.json.backend_options.available=true` 的**(见 `/preflight`);选了没就绪的(缺 CLI / 未授权 Supabase MCP)→ codegen 会卡在工具链缺失,先让用户装/授权。

**CONTRACT 不满足时:**
- 无数据契约表 **且** 无 manifest.screens → 拒绝执行,提示先跑 `/shape`(补数据契约)或 `/design-restore`(出 manifest)。
- 有 manifest 但无 lockdown 选型 → 读 `env-probe.json`,**降级默认为"环境已就绪的最优后端"**(有 Supabase(CLI/MCP)则 Supabase;否则按矩阵在 available 候选里选,如 Cloudflare/自建),在 backend-readiness.md 如实标"选型由 backend-forge 按环境默认推断,需人确认"。
- manifest 全字段 `confidence: inferred`(无任何 extracted)→ 不直接出 FROZEN openapi,先走 Step 1 派生草稿 + 强制人确认闸,再继续。
- 数据契约高风险字段缺单位/值域(金额无"分/元"、时间无格式、枚举无值域)→ 阻塞,回 shape 补全后重入。

**OUTPUT(桥产物 + 闸门 state):**
- `api/openapi.yaml`(OpenAPI 3.1 SSOT)+ `api/ownership-matrix.md` + codegen 产物
- **`api/integration-flow.json`(联调黄金流,SHOULD 产)**:qa Step 1.5 的 `integration-test.py` 优先读它跑真端到端联调(无则从 live `/openapi.json` 自动派生,可靠性略低)。格式:
  ```json
  { "steps": [
    { "name":"register", "method":"POST", "path":"/api/auth/register",
      "body":{"email":"itest@example.com","password":"Itest_x!aB9"},
      "expect":[201], "save_token":true },
    { "name":"list", "method":"GET", "path":"/api/positions", "auth":true, "expect":[200] }
  ] }
  ```
  从 ownership 矩阵 + 核心链路挑一条"注册→鉴权→读/写自己的数据"happy-path 落成此文件 = 联调可复现的锚。
- **`docker-compose.yml`(全栈项目 SHOULD 产)**:后端 + 依赖(PG/Redis)+ 前端一把拉起,让 `stack-up.sh` 一键起真栈联调(dev 设 SQLite/内存 KV fallback → 零外部依赖也能 boot)。
- **闸门 JSON**(Workflow 的 Synthesis critic / 线性 Step 6 写):
  - `.claude/state/contract-test.json` = `{target, result, failures}`(夹1+夹2 汇总)
  - `.claude/state/e2e-contract.json` = `{result, missing_fields, extra_fields}`(夹3 业务链路字段对照)
- `.claude/state/skill-signal.json`(完成信号)

参照 `.claude/rules/core.md § 决策生命周期`(optimistic/confirmed/deferred/invalidated/fused)、`§ 禁止模式`(预建抽象 / 幽灵依赖 / 防御性冗余)。

---

## 执行计划(线性档 — 仅单 agent 降级用)

> 真 app 跑请直接跳到 [## 主执行路径:AI 调用 Workflow 工具编排(推荐用户开 ultracode;降级=单 agent 顺序)](#主执行路径ai-调用-workflow-工具编排推荐用户开-ultracode降级单-agent-顺序),不要顺序硬写下面这些 Step。

```
- [ ] Step 0: 读 lockdown/backend-readiness.md(选型) + spec.md 数据契约 + manifest.screens
- [ ] Step 1: 派生契约草稿 (screen→entity→endpoint),标 extracted/inferred
- [ ] Step 1.5: inferred 人确认闸 (inferred 字段/实体/端点逐条确认)
- [ ] Step 2: 高风险字段落 schema (金额=分/时间=ISO8601/枚举=enum/ID=format)
- [ ] Step 3: ownership 越权矩阵 (谁能 CRUD 谁的数据) — 强制
- [ ] Step 4: 写 api/openapi.yaml (OpenAPI 3.1 SSOT) + FROZEN 标注 ← 这步是「先定稿」,定稿前不扇出
- [ ] Step 5: codegen 可靠区 (Supabase migration+RLS / DTO / 校验 / SDK / 测试骨架)
- [ ] Step 6: 三重夹测试 + 写 contract-test.json / e2e-contract.json
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

**为什么必填:** "越权"是 AI 头号幻觉区——AI 写 endpoint 时默认"登录就能访问",忘记"只能访问自己的数据"。这一步把"谁能 CRUD 谁的数据"**显式建表**,再落成 Supabase 声明式 RLS(可审计 SQL),并产出夹2 越权负向测试。

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
4. 矩阵的每一行**对应一条 Step 5 的 RLS policy** 和一条夹2 越权负向测试——**三者数量对账**(Workflow 的 Synthesis critic 也核这个数)。

### 落 OpenAPI(`x-ownership` 扩展)

```yaml
paths:
  /orders/{id}:
    get:
      x-ownership: { entity: order, rule: "owner OR admin", owner_field: user_id }
      security: [{ bearerAuth: [] }]
```

---

## Step 4: 写 api/openapi.yaml(OpenAPI 3.1 SSOT)— 先定稿,定稿前不扇出

把 Step 1-3 的产物合成**唯一真相源**。这是所有后续扇出的**唯一真相源,定稿前不扇出**。

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

**校验(真命令):**

```bash
# 1) OpenAPI 3.1 结构合法
npx @redocly/cli@latest lint api/openapi.yaml
# 2) 起 prism mock(给夹1 当 base-url,见 Step 6 mock 档)
npx @stoplight/prism-cli@latest mock api/openapi.yaml --port 4010   # → http://127.0.0.1:4010
```

**硬规则:**
- 每个写端点必须显式声明 `403`(越权)和 `422`(校验失败)response。
- `x-frozen: true` + 顶部注释"变更回 /shape 重算数据契约,不在 build 改"。
- OpenAPI 3.1 用 JSON Schema 2020-12,`nullable` 统一一种写法(`type: [string, "null"]` 或保留兼容,二选一)。
- **此文件落盘 = SSOT FROZEN**。Workflow 工具编排的 endpoint 扇出从这里解析 path,扇出中**不许改它**。

由 `sg_app_openapi_artifact` 验收(文件存在 + 3.1 合法 + 每写端点含 403/422 + 高风险字段含 format/enum)。

---

## Step 5: codegen 可靠区(机制消灭 drift)

**从 openapi.yaml 单向生成**,不手写、不反向回填。codegen 区 = "可靠区"(机械生成,低幻觉),手写区 = 业务逻辑(高风险,需夹3 业务测试)。

| 产物 | 工具(真命令,Supabase 栈) |
|-----|------------------|
| **DTO / 类型** | `npx openapi-typescript api/openapi.yaml -o src/types/api.d.ts`(各端共享类型,杜绝字段名 drift) |
| **client SDK** | `npx @openapitools/openapi-generator-cli generate -i api/openapi.yaml -g swift5 -o sdk/ios`(Kotlin/TS 换 `-g`) |
| **请求校验** | 从 schema 生成 zod / pydantic validator(金额是 int、枚举值域、必填——边界由 schema 保证) |
| **DB migration + RLS** | 从 schema + ownership 矩阵生成 `supabase/migrations/*.sql`,`supabase db reset` 可重放 |
| **前端 mock** | `prism mock api/openapi.yaml`(见 Step 4;前端不等后端,mock 也从 SSOT 生成同源) |

**RLS 生成铁律(Supabase):**
- 每个 entity 默认 `ALTER TABLE <t> ENABLE ROW LEVEL SECURITY;`(默认全拒,显式放行)。
- ownership 矩阵的每一行 → 一条 policy,owner 角色固定 `USING (auth.uid() = <owner_field>)`。
- admin 角色用 `auth.jwt() ->> 'role' = 'admin'` 判定,**不在应用层判越权**(应用层判 = 头号幻觉)。
- 生成的 SQL 必须可 `supabase db reset` 重放。

**栈分支(非 Supabase 时,codegen 路径 + 权限处理不同;选型见 `tech-stack-decision.md` 后端矩阵):**

| 栈 | codegen 路径(真命令) | 越权防护 |
|---|---|---|
| **Supabase**(默认) | 上表 + `supabase/migrations/*.sql` RLS | 声明式 RLS(抗幻觉最佳) |
| **Cloudflare**(AI 重/边缘/低成本) | Workers handler + `wrangler d1 migrations apply`(D1=SQLite)+ R2;AI 能力走 Workers AI / Vectorize / AI Gateway | ⚠️ **D1 无 RLS → 权限写 Worker 代码 = AI 幻觉区**。补偿:**ownership 矩阵 + 越权负向测试加倍严**——非 RLS 栈,越权负向用例数 **≥ 矩阵行数 × 2**(读+写+无 token 全覆盖),每条手写权限检查必过对抗验证 |
| Firebase | Functions + Firestore security rules | rules(易错,需测,同 ≥2×) |
| PocketBase / 自建 | 手写 handler / API rules | 应用层判,全压负向测试(≥2×) |

> **通用铁律**:权限不能声明式(RLS)时,越权防护全靠 backend-forge 夹2 负向测试——所以非 Supabase 栈,Synthesis critic 对"越权用例数 vs 矩阵行数"对账按 **≥2×** 卡,补 RLS 缺位。

遵循 `.claude/rules/core.md § 禁止模式`:codegen 产物不算"预建抽象"(它有真实消费者=各端 SDK);但**手写**为"将来可能"加的端点/字段算违规。

---

## Step 6: 三重夹测试 + 写闸门 JSON

**为什么必填:** 契约对≠业务对。三层各夹一类幻觉,缺一不可。

### 夹 1 — Schemathesis 契约测试(schema 符合性,property-based)

```bash
# real 后端:
schemathesis run api/openapi.yaml --base-url $TEST_API --checks all --hypothesis-max-examples 50
# 只对真后端跑过才算 target=real;对上面 prism mock(:4010)跑 → target=mock
schemathesis run api/openapi.yaml --base-url http://127.0.0.1:4010 --checks all   # → target=mock
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
- 越权测试**数量必须 = ownership 矩阵行数**(Step 3 对账)。

### 夹 3 — 业务规则走 ACCEPT(契约测试管不到的语义)

契约测试只验"形状",验不了"满员后不能再下单""金额不能为负""取消后不能支付"这类**业务规则**。走 spec ACCEPT(Given/When/Then):

```
ACCEPT (来自 spec § 故障想象力 / PRD 挑战):
- Given 库存=0, When POST /orders, Then 返回 409 且不创建订单
- Given order.status=cancelled, When PATCH status=paid, Then 返回 422 拒绝非法状态转换
- Given amount<0, When POST /orders, Then 422
```
- 业务 ACCEPT 必须可追溯到 spec(§故障想象力 / §PRD 挑战 / §核心难点的状态机)。

### 写闸门 JSON(严格按 key — 写错即整关失效)

```bash
mkdir -p .claude/state
# 夹1+夹2 汇总(target 由 base-url 是 prism 还是真 API 决定;任一 endpoint 的夹1/夹2 fail → FAIL)
cat > .claude/state/contract-test.json <<'JSON'
{ "target": "mock", "result": "PASS",
  "failures": [ ] }
JSON
# 夹3 业务链路字段对照(missing/extra 任一非空 → 闸门判 drift)
cat > .claude/state/e2e-contract.json <<'JSON'
{ "result": "PASS", "missing_fields": [], "extra_fields": [] }
JSON
```
- `contract-test.json` = `{target:'mock'|'real', result:'PASS'|'FAIL', failures:[{endpoint,check:'schema'|'authz',detail}]}`。
- `e2e-contract.json` = `{result:'PASS'|'FAIL', missing_fields:[openapi 声明但响应缺], extra_fields:[响应有但未声明]}`。

由 `sg_app_contract_test`(夹1+夹2)+ `sg_app_e2e_contract_smoke`(夹3)验收。三层缺任一 → 测试不完整。

---

## Step 7: 写完成信号

```bash
mkdir -p .claude/state
echo "{\"skill\":\"backend-forge\",\"epoch\":$(date +%s)}" > .claude/state/skill-signal.json
```

更新 `docs/status.md`:勾上 backend-forge 进度 + 记 openapi.yaml 路径 + FROZEN 状态 + 任何 deferred 端点。

---

## 主执行路径:AI 调用 Workflow 工具编排(推荐用户开 ultracode;降级=单 agent 顺序)

> ⚠️ **主路径到底怎么操作**:**Workflow 是 Claude Code 会话内的【工具】,由 AI(你)调用**(给它传 `script` 参数)——**不存在 `claude workflow` 这种 shell 命令**。**ultracode 是用户手动开的会话高级模式**(让 AI 默认倾向调 Workflow),skill/脚本无法自己开启它,只能推荐用户开。所以"执行本 skill 主路径"=你(AI)用内置 Workflow 工具,按本 skill 描述的编排意图当场组合 script 并执行;`scripts/design-first/backend-forge.workflow.js` 只是推荐扇出结构的【参考蓝图】,可读来参考,不是传给工具去跑的脚本。你现场组合的 script 里的 agent 用 **Bash 调本仓 `scripts/design-first/` 的确定性脚本**(`contract-test.sh` / `e2e-contract.sh` / `ownership-probe.sh`)产出闸门读取的 state JSON——这些脚本是唯一可信的 state 产出口,不要让 agent 手写 JSON。

**真 app 跑 backend-forge 的主路径 = AI 调用 Workflow 工具编排,不是单 agent 顺序硬写(单 agent 仅降级档)。** 单 agent 顺序写时,几十个 endpoint 的"生成实现→契约→越权"和每条业务规则的对抗验证会被压成一条线、互相污染上下文、且没有"覆盖核对"这一环——漏一个 endpoint 没越权测试也发现不了。Workflow 把它拆成**四个 phase**,把 Workflow 四编排模式归位:

| Workflow 编排模式 | 在本脚本的落点 |
|---|---|
| **fan-out 全覆盖** | `parallel(endpoints)` — 每 endpoint 一个 worker,全量覆盖,不抽样 |
| **adversarial verify** | `parallel(N skeptic)` 对每条业务规则独立质疑,多数投票 keep/kill(各 skeptic **不看彼此结论**,否则是回声室) |
| **pipeline 串数据** | 每 endpoint worker 内 `impl → contract → authz` 前一步喂后一步 |
| **completeness critic** | `Synthesis` phase 单 agent 核覆盖(每 endpoint 都有契约+越权?越权用例数=矩阵行数?),**唯一写闸门 JSON 的点**,保证 key 严格对齐 app-gate.sh |

### 跑法

```bash
mkdir -p /Users/xmasdong/opc/app-factory/scripts/design-first
# 在目标业务项目根跑,CLAUDE_PROJECT_DIR 指向该项目(否则 ROOT 落到 cwd,state 写错位置闸门读不到):
# 真 app 跑:你(AI)用内置 Workflow 工具,按本 skill 描述的编排意图当场组合 script 并执行;扇出结构可参考蓝图 /Users/xmasdong/opc/app-factory/scripts/design-first/backend-forge.workflow.js(仅参考,非传给工具运行的脚本)
# 跑完用闸门验收 key 对齐:
bash /Users/xmasdong/opc/app-factory/scripts/app-gate.sh build
jq '.target, .result, (.failures|length)' .claude/state/contract-test.json
jq '.result, (.missing_fields|length), (.extra_fields|length)' .claude/state/e2e-contract.json
```

### 编排蓝图参考(落 `scripts/design-first/backend-forge.workflow.js` 当扇出结构示例,供 AI/人参考;非传给 Workflow 工具运行的脚本)

> 内置 Workflow 工具组合 script 时可用的全局(Claude 提供):`phase(title)`、`parallel(fns[])`、`agent(prompt, {label, phase, schema})`(schema 是 JSON Schema,agent 必须按 schema 返回结构化对象)。脚本体是顶层 await。`pipeline` 用 `for await` / 顺序 `await` 串 agent 实现。**每个 parallel worker 必须 `.catch` 兜底成符合 schema 的 fallback 对象**,否则一个 endpoint 崩了整个 parallel reject、其它已完成的工作全丢。

```js
export const meta = {
  name: 'backend-forge-orchestrated',
  description: 'openapi SSOT → 按 endpoint 扇出(实现→契约→越权 pipeline)→ 业务规则对抗验证 → 汇总产 contract-test.json/e2e-contract.json',
  phases: [
    { title: 'OpenAPI-SSOT',     detail: 'single agent — 派生并定稿 api/openapi.yaml,扇出前唯一真相源' },
    { title: 'Per-Endpoint',     detail: 'parallel × endpoint — 每 endpoint 内部 pipeline:实现→契约测试→越权负向' },
    { title: 'Adversarial-Rules',detail: 'parallel × rule × N skeptic — 多数过才留(adversarial verify)' },
    { title: 'Synthesis',        detail: 'completeness critic — 核覆盖 + 写 contract-test.json/e2e-contract.json' },
  ],
}
const ROOT = process.env.CLAUDE_PROJECT_DIR || process.cwd()
const N_SKEPTIC = 3
const EP_SCHEMA = { type:'object', required:['endpoint','impl','contract','authz'], properties:{
  endpoint:{type:'string'}, impl:{enum:['done','partial']},
  contract:{type:'object',properties:{result:{enum:['PASS','FAIL']},failures:{type:'array',items:{type:'string'}}}},
  authz:{type:'object',properties:{result:{enum:['PASS','FAIL']},cases:{type:'integer'},failures:{type:'array',items:{type:'string'}}}} } }

// ── phase 1: openapi 先定稿(SSOT,扇出前必须存在)──
phase('OpenAPI-SSOT')
const ssot = await agent(
  `读 ${ROOT}/docs/spec.md §数据契约 + ${ROOT}/docs/design/design-manifest.json screens[]。
   screen→entity→endpoint 派生,inferred 字段标注。高风险字段落 format/enum(金额=分/时间=ISO8601/枚举全列)。
   每写端点声明 403+422。每 entity 建 ownership 越权矩阵行。
   写 ${ROOT}/api/openapi.yaml(OpenAPI 3.1)。返回 endpoint 列表 + ownership 矩阵行数 + 业务规则列表。`,
  { label:'ssot', phase:'OpenAPI-SSOT', schema:{ type:'object', required:['endpoints','ownership_rows'], properties:{
      endpoints:{type:'array',items:{type:'string'}}, ownership_rows:{type:'integer'}, rules:{type:'array',items:{type:'string'}} } } }
)

// ── phase 2: 按 endpoint 扇出,每 endpoint 内部 pipeline(fan-out 全覆盖)──
phase('Per-Endpoint')
const perEndpoint = await parallel(ssot.endpoints.map(ep => async () => {
  // pipeline 步1:生成实现
  const impl = await agent(`endpoint=${ep}。从 ${ROOT}/api/openapi.yaml 该 path 生成实现:Supabase migration+RLS(ENABLE RLS,owner=auth.uid())、handler、zod/pydantic 校验、DTO。只引用 SSOT,不改 openapi。`,
    { label:`impl:${ep}`, phase:'Per-Endpoint', schema:{type:'object',properties:{status:{enum:['done','partial']},files:{type:'array',items:{type:'string'}}}} })
  // pipeline 步2:契约测试(吃步1输出)
  const contract = await agent(`endpoint=${ep} 实现已落(${JSON.stringify(impl.files)})。跑 schemathesis run ${ROOT}/api/openapi.yaml --base-url $TEST_API --checks all --hypothesis-max-examples 50,只针对该 path。返回 result+failures。`,
    { label:`contract:${ep}`, phase:'Per-Endpoint', schema:{type:'object',required:['result'],properties:{result:{enum:['PASS','FAIL']},failures:{type:'array',items:{type:'string'}}}} })
  // pipeline 步3:越权负向(吃步1输出)
  const authz = await agent(`endpoint=${ep}。对 ownership 矩阵该行生成负向:A token 取 B 资源→必 403;无 token→401;A PATCH B→403 且 B 数据未变(读回验证)。返回 result+cases+failures。`,
    { label:`authz:${ep}`, phase:'Per-Endpoint', schema:{type:'object',required:['result','cases'],properties:{result:{enum:['PASS','FAIL']},cases:{type:'integer'},failures:{type:'array',items:{type:'string'}}}} })
  return { endpoint:ep, impl:impl.status, contract, authz }
}).map(p => p.catch(e => ({ endpoint:'?', impl:'partial', contract:{result:'FAIL',failures:[String(e)]}, authz:{result:'FAIL',cases:0,failures:[String(e)]} }))))

// ── phase 3: 业务规则对抗验证(N skeptic 并行,多数过才留;adversarial verify)──
phase('Adversarial-Rules')
const ruleVerdicts = await parallel((ssot.rules||[]).map(rule => async () => {
  const votes = await parallel(Array.from({length:N_SKEPTIC}, (_,i) => () =>
    agent(`你是 skeptic #${i+1}。独立质疑这条业务规则的实现是否对/边界是否漏:"${rule}"(来自 spec ACCEPT)。
           检查状态机非法转换/金额为负/余额穿透/满员后下单。只回 keep 或 kill + 一句理由。`,
      { label:`skeptic${i+1}:${rule.slice(0,20)}`, phase:'Adversarial-Rules', schema:{type:'object',required:['vote'],properties:{vote:{enum:['keep','kill']},why:{type:'string'}}} })
      .catch(()=>({vote:'kill',why:'skeptic error→保守 kill'}))))   // 出错保守投 kill,宁漏留也别假阳性留错规则
  const keeps = votes.filter(v=>v.vote==='keep').length
  return { rule, verdict: keeps > N_SKEPTIC/2 ? 'keep' : 'kill', votes: votes.map(v=>v.vote), why: votes.map(v=>v.why).join(' | ') }
}))

// ── phase 4: completeness critic + 写闸门 JSON(唯一写 state 的点,key 严格)──
phase('Synthesis')
const synth = await agent(
  `完整性审查 + 写闸门 state(严格按 key)。输入:
   endpoints=${JSON.stringify(perEndpoint)}
   rules=${JSON.stringify(ruleVerdicts)}
   覆盖核对:每 endpoint 都有 contract+authz?越权用例数 = ownership 行数(${ssot.ownership_rows})?有 kill 规则需上报?
   写 ${ROOT}/.claude/state/contract-test.json = {target:(base-url 是 prism→'mock' 否则'real'), result:(任一 contract/authz FAIL→'FAIL' 否则'PASS'), failures:[{endpoint,check:'schema'|'authz',detail}]}
   写 ${ROOT}/.claude/state/e2e-contract.json = {result:(业务 ACCEPT 链路冒烟 PASS/FAIL), missing_fields:[openapi 声明但响应缺], extra_fields:[响应有但未声明]}
   返回写入摘要 + 未覆盖项。`,
  { label:'critic', phase:'Synthesis', schema:{type:'object',required:['contract_test','e2e_contract','gaps'],properties:{
      contract_test:{type:'object'}, e2e_contract:{type:'object'}, gaps:{type:'array',items:{type:'string'}} } } }
)
return { ssot, perEndpoint, ruleVerdicts, synth }
```

### 编排坑(逐字对齐,否则白跑)

- **闸门 key 逐字对齐**:`contract-test.json` 的 `target` 只能 `'mock'|'real'`(target=mock 时闸门会点名"real 后端尚未验证"即使 PASS);`e2e-contract.json` 的 `missing_fields`/`extra_fields` 任一非空闸门直接判 drift,别塞无关字段。
- **openapi 先定稿再扇出**:endpoint worker 只读已写盘的 `api/openapi.yaml`,**不许并行改它**(并行 worker 同时写会互相覆盖)。SSOT FROZEN,改字段回 `/shape` 重算。
- **对抗验证别做成单 agent 自问自答**:N 个 skeptic 必须 `parallel` 独立 prompt,各自不看彼此结论。skeptic 出错保守投 `kill`。
- **越权用例数 = ownership 矩阵行数**:critic 必须核这个数;A 取 B 资源期望严格 `403`(不是 200 空、不是 404、不是 500),越权写还要读回验证 B 数据未变。
- **每个 worker `.catch` 兜底**成符合 schema 的 fallback,否则一个 endpoint 崩整个 parallel reject。
- **schemathesis target 别谎报**:对 prism mock 跑填 `mock`,只有对真后端跑过才填 `real`。
- **CLAUDE_PROJECT_DIR 必须 export** 指向目标项目根,否则 state 写到 cwd 闸门读不到。该蓝图随 app-factory 仓库分发(当参考),但你(AI)现场组合的 script **跑时在各业务项目根执行**。

---

## OUTPUT_GATE(advisory,初期 sg_run_soft 不阻塞)

| 检查项 | 函数 |
|-------|-----|
| `api/openapi.yaml` 存在 + OpenAPI 3.1 合法 | sg_app_openapi_artifact |
| 数据契约 extracted 字段全落 schema + 高风险字段含 format/enum | sg_app_data_contract |
| 每写端点含 403(越权)+ 422(校验)response | sg_app_openapi_artifact |
| ownership 越权矩阵存在 + 每 entity 有 owner + 每角色×CRUD 有判定 | sg_app_contract_test |
| inferred 项全部处置(confirmed/deferred/invalidated) | sg_app_data_contract |
| 契约测试 result=PASS(夹1;target=mock 时点名上线前对 real 复跑) | sg_app_contract_test |
| 越权负向测试存在且数量=矩阵行数,A 取 B 资源=403(夹2) | sg_app_contract_test |
| 业务规则 ACCEPT 关键链路 e2e 字段对照 result=PASS 且 missing/extra 为空(夹3) | sg_app_e2e_contract_smoke |
| Supabase migration+RLS 可重放,每 entity 已 ENABLE RLS | sg_app_contract_test |

**OUTPUT_GATE 不通过时(advisory 模式):**
- 失败回灌为 stderr 建议,不硬阻塞(初期与"建议优先"哲学一致)。
- inferred 未处置 / 越权测试缺失 / 高风险字段无 format / `target=mock` 未对 real 复跑是**强建议必补**项。
- 后期可切 `sg_run_hard` 升为阻塞。

变更 extracted 字段或 openapi schema → **回 /shape 重算数据契约**,不在本 skill 或 /build 静默改。参照 `.claude/rules/core.md § 决策生命周期 → FROZEN`。

---

## 完成后下一步

`完成: /backend-forge 已产出 api/openapi.yaml(SSOT)+ ownership 越权矩阵 + codegen 产物 + 三重夹测试(Workflow 扇出全覆盖), contract-test.json/e2e-contract.json 已喂闸门, 前端可从同源 mock 开发, /build 后端任务从 openapi 续接`

或回 shape:

`停住: OpenAPI-SSOT phase 发现 inferred 端点 POST /payments 语义不明(表单屏推断不出是创建还是确认), 回 /shape 补数据契约动作语义后重 /backend-forge`

或 advisory 提示:

`建议: Synthesis critic 报 越权负向覆盖 4/5 矩阵行, post.delete 缺 A 删 B 的负向用例; 且 contract-test target=mock, 上线前需对 real 后端复跑 schemathesis, 再进 /qa`
