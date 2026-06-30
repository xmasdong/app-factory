<!--
BACKEND-CONTRACT-GATE 章节模板 — backend-forge 契约闸门 (qa 阶段内部调用)
要求: OpenAPI 3.1 生成规约 + 契约测试命令 (Schemathesis, target=mock|real 区分真假 pass)
      + E2E 字段对照断言清单 + 越权负向测试清单.
脚本 sg_app_contract_test / sg_app_e2e_contract_smoke / sg_app_openapi_artifact 验证.
初期 sg_run_soft=advisory 不阻塞.

为什么必填:
  AI 后端的头号幻觉区: (1) 前后端字段漂移 (mock 跑通 ≠ 真后端跑通);
  (2) 越权 (用户 A 能读到用户 B 的数据, RLS 漏配); (3) 契约测试过 ≠ 业务正确.
  api/openapi.yaml 是功能→后端的**唯一真相源 (SSOT)**: mock + 后端骨架 + client SDK +
  契约测试全部从它生成, 用机制 (而非纪律) 消灭 drift.

填写原则:
  1. openapi.yaml extracted 字段 FROZEN by default, 变更回 shape 重算 (不在实现处手改).
  2. 契约测试必须区分 target: mock 过只证"schema 自洽", real 过才证"真后端守约". 只有 real pass 才算真 pass.
  3. 越权负向测试是**强制项**: 来自 design-manifest 的 ownership 越权矩阵 (谁能 CRUD 谁的数据).
  4. 契约测试 (schema 合规) ≠ 业务正确 (金额算对/状态机合法). 业务规则走单独 ACCEPT 断言, 三重夹.
  5. 后端默认 Supabase + 声明式 RLS, 把"越权"从代码审查变成可审计 SQL (见 backend-readiness §1).

$AI_RULES_ROOT 用法: 测试命令脚本 / 断言清单 / 越权矩阵模板落在 $AI_RULES_ROOT 下, 项目间可移植.
  - 契约测试: $AI_RULES_ROOT/scripts/contract-test.sh   (封装 schemathesis, 透传 --target)
  - E2E smoke: $AI_RULES_ROOT/scripts/e2e-contract-smoke.sh
  - 越权矩阵: api/ownership-matrix.yaml (来自 design-manifest inferred_entities, 需人确认)
-->

## BACKEND-CONTRACT-GATE

> 功能契约 (api/openapi.yaml) 与真实后端的一致性闸门.
> SSOT = api/openapi.yaml (OpenAPI 3.1): mock + 后端骨架 + client SDK + 契约测试全从它生成.
> 核心断言: 真后端守约 (Schemathesis real) + 字段对照不漂移 + 越权被拒 + 业务规则成立.

---

### 1. OpenAPI 3.1 生成规约 (SSOT)

> 一份 api/openapi.yaml 同时生四样: 前端 mock (prism/msw) + 各端 client SDK + 后端骨架 + 契约测试.
> screen→entity→endpoint 派生只是**草稿**, inferred 字段需人确认后才 FROZEN.

| 规约项 | 要求 |
|--------|------|
| 版本 | OpenAPI **3.1.0** (JSON Schema 2020-12 对齐, 支持 `null` / `examples` / webhooks) |
| 来源 | 由 backend-forge 从 design-manifest `inferred_endpoints` 派生草稿 → 人确认 → FROZEN |
| 每端点必填 | `operationId` (唯一) · `summary` · 全部参数带 `schema` · 请求/响应 `content` 带 `schema` |
| 响应覆盖 | 每端点至少声明 `200/201` + `400` + `401` + `403` (越权) + `404` + `409` (业务冲突, 如适用) |
| 数据类型铁律 | 金额=整数分 (`type:integer`) · 时间=`format:date-time` (ISO 8601) · 枚举状态=`enum:[...]` 显式 |
| 鉴权 | `securitySchemes` 声明 (bearer JWT / Supabase) + 每端点 `security` 标注 |
| 字段置信度溯源 | manifest 中 `extracted` 字段 FROZEN; `inferred` 字段必须在 yaml `description` 标 `(inferred, 待确认)` |
| 校验 | yaml 必须过 `openapi spec validate` / `redocly lint`, 不过直接阻塞 |

> 变更纪律: extracted 字段改动 = 回 shape 重算 manifest, 不允许在 openapi.yaml 或实现处单边修改 (否则 drift 复活).

---

### 2. 契约测试命令 (Schemathesis, target=mock|real 区分真假 pass)

> Schemathesis 拿 openapi.yaml 生成属性测试 (fuzz 边界值/类型), 验"实现是否守 schema".
> **关键区分**: target=mock 只证 schema 自洽 + 前端 mock 一致; target=real 才证真后端守约. **只有 real pass 才算真 pass.**

```bash
# --- target=mock: 跑 prism/msw mock, 证 "schema 自洽 + 前端 mock 守约" (快, CI 每次跑) ---
$AI_RULES_ROOT/scripts/contract-test.sh --target mock \
  --schema api/openapi.yaml \
  --base-url http://localhost:4010 \
  --checks all --hypothesis-max-examples 50

# 等价底层命令:
schemathesis run api/openapi.yaml \
  --url http://localhost:4010 \
  --checks all \
  --report

# --- target=real: 跑真后端 (Supabase/部署实例), 证 "真后端守约" → 唯一真 pass ---
$AI_RULES_ROOT/scripts/contract-test.sh --target real \
  --schema api/openapi.yaml \
  --base-url "$REAL_API_BASE_URL" \
  --auth-token "$TEST_USER_A_JWT" \
  --checks all --hypothesis-max-examples 100
```

**Schemathesis checks 至少开启:** `status_code_conformance` · `response_schema_conformance` ·
`content_type_conformance` · `response_headers_conformance`.

**判定语义:**

| target | 通过含义 | 是否算"真 pass" |
|--------|---------|----------------|
| mock | schema 自洽 + 前端 mock 与契约一致 | 否 (仅 schema 层绿灯) |
| real | 真后端对契约 fuzz 全守约 | **是 (唯一真 pass)** |

> mock 绿、real 未跑 → 闸门标 `schema-only`, 不得宣称"后端契约通过".

---

### 3. E2E 字段对照断言清单 (跑真后端, 字段级硬断言)

> 契约测试是属性 fuzz; 本清单是**确定性字段对照**: 真后端返回的关键字段必须满足类型与语义约束.
> 逐字段断言, 任一不满足 = drift, 直接 fail.

- [ ] **金额字段 = 整数分**: 所有 amount/price/total 字段 `Number.isInteger(v) === true` 且单位为分 (无浮点小数, 无元/分混用).
- [ ] **时间字段 = ISO 8601**: 所有 *_at / *_time 字段匹配 `^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$`.
- [ ] **status ∈ 枚举**: 所有 status/state 字段值 `∈ openapi.yaml 声明的 enum 集`, 出现枚举外值 = fail.
- [ ] **id 类型一致**: id/外键字段类型与契约一致 (string uuid 不退化为 int, 反之亦然).
- [ ] **必填字段非空**: openapi `required` 列出的字段在真响应中存在且非 null.
- [ ] **分页契约一致**: 列表端点返回 `{ items, total/next_cursor }` 结构与契约逐字段对齐.
- [ ] **错误体契约一致**: 4xx/5xx 错误体结构 (`{ code, message }` 或约定结构) 与契约一致, 不返回裸字符串/HTML.
- [ ] **空/边界字段**: 空列表返回 `[]` 而非 `null`; 可空字段类型声明 `nullable`/`["T","null"]` 与实际一致.

> 断言落在 $AI_RULES_ROOT/scripts/e2e-contract-smoke.sh, 对 real 后端跑一遍核心用户流后逐字段校验.

---

### 4. 越权负向测试清单 (强制项 — ownership 越权矩阵)

> AI 后端头号安全幻觉: RLS/鉴权漏配 → 用户 A 能 CRUD 用户 B 的数据.
> 来源: design-manifest `inferred_entities` 派生的 ownership 越权矩阵 (api/ownership-matrix.yaml, 需人确认).
> 默认后端 Supabase 声明式 RLS → 越权从"读代码"变成"可审计 SQL policy".

**核心断言: 用户 A 的 token 访问用户 B 拥有的资源 → 必须 403 (或 404, 按"不泄露存在性"策略), 绝不 200.**

| # | 负向用例 | 期望 | 备注 |
|---|---------|------|------|
| 1 | A 的 token **读** B 的资源 (`GET /resource/{B_id}`) | 403 / 404 | 逐 owned 实体跑 |
| 2 | A 的 token **改** B 的资源 (`PUT/PATCH /resource/{B_id}`) | 403 / 404 | |
| 3 | A 的 token **删** B 的资源 (`DELETE /resource/{B_id}`) | 403 / 404 | |
| 4 | A 的 token **列举** 全量 (`GET /resource`) | 仅返回 A 拥有的项 | 不得越权返回 B 的项 |
| 5 | A 创建资源时**伪造 owner_id=B** | 拒绝 / 强制覆写为 A | server 端绝不信任 client 传的 owner |
| 6 | 无 token / 过期 token 访问受保护端点 | 401 | 与 403 区分 |
| 7 | 普通用户访问**管理员端点** | 403 | 角色越权 (如适用) |
| 8 | 直改 IDOR: 遍历 `{id}` 探测他人资源 | 全 403/404 | 抽样多个非自有 id |

```bash
# 越权负向测试 (需要 A、B 两个真测试用户的 token)
$AI_RULES_ROOT/scripts/contract-test.sh --target real --negative-ownership \
  --schema api/openapi.yaml \
  --ownership-matrix api/ownership-matrix.yaml \
  --user-a-jwt "$TEST_USER_A_JWT" \
  --user-b-jwt "$TEST_USER_B_JWT"
```

> 任一越权用例返回 200 (拿到了不该拿的数据) = **硬 fail, 不可降级**. 这是安全闸门, 不走 advisory.
> Supabase 项目: 每条 owned 实体必须有对应 RLS policy, 缺 policy 的表直接列整改.

---

### 5. 三重夹: 契约 ≠ 业务正确

> 契约测试 (schema 合规) 只证"形状对", 不证"算得对". 三层各管一段, 缺一段都不算后端可信:

| 层 | 工具 | 证明什么 | 通过 ≠ |
|----|------|---------|--------|
| 契约 (Schemathesis real) | schemathesis | 真后端守 schema (类型/状态码/字段) | ≠ 业务对 |
| 字段对照 (E2E smoke) | e2e-contract-smoke.sh | 关键字段语义约束 (分/ISO/枚举) | ≠ 流程对 |
| **业务规则 (ACCEPT)** | 项目自定 ACCEPT 断言 | 金额算对 / 状态机合法 / 幂等 / 库存不超卖 等 | — |

> 业务规则 ACCEPT 断言由项目按核心用户故事自行补 (如"下单后余额=原余额-订单分"), 写进 ACCEPT 清单.
> 三重全绿才宣称后端通过; 只有契约绿 = "形状对但可能算错".

---

### 验收硬规则 (sg_app_contract_test / sg_app_e2e_contract_smoke / sg_app_openapi_artifact)

1. api/openapi.yaml 存在且过 spec validate (sg_app_openapi_artifact), 不过直接阻塞.
2. 契约测试必须有 target=mock 与 target=real **两次记录**; 只有 real pass 才计入"真 pass", 否则标 schema-only.
3. E2E 字段对照 8 项逐项可证 (金额=分 / 时间=ISO8601 / status∈枚举 强制), 缺项记整改.
4. 越权负向测试 8 类全跑, 任一返回 200 (越权成功) = 硬 fail (本项**不走 advisory**, 安全红线).
5. ownership 越权矩阵 (api/ownership-matrix.yaml) 必须存在且 inferred 项已人确认.
6. 业务规则 ACCEPT 断言存在 (三重夹第三层), 缺则标 "仅契约+字段, 未验业务正确".
7. openapi.yaml extracted 字段 FROZEN, 变更回 shape 重算 (sg_run_soft=advisory, 初期不阻塞只告警; 第 4 条越权除外).
