## 技术栈决策 (TECH-STACK-DECISION)

> 选型不是拍脑袋,是**环境约束 + 能力需求驱动 + 对比矩阵 + 不确定就 spike**。
> discover 出初选(≥2 候选),lockdown spike 验证/定稿。

### 0. 环境预检约束(先跑 /preflight,再谈选型)

> **地基:候选栈必须落在本机能真正构建/授权的范围内。** 推一个装不了、没授权的栈 = 让用户卡在第一步。

`/preflight` 跑 `env-probe.sh` → `.claude/state/env-probe.json`,本节所有候选**先被它闸一遍**:

- **前端**:`capabilities` 决定可选面 —— `build_ios_native`(xcode+swift)、`build_android_native`(Android SDK)、`build_cross_platform_flutter`(flutter+dart)、`build_web`(node)。**发布目标由用户定(全端→Flutter)**,推荐必须落在 true 的能力里;要的目标缺工具链 → 明说"装 X 或换目标",不硬选。
- **后端**:候选池 = `env-probe.json.backend_options` 里 `available=true` 的。unavailable 的(如未装 CLI / 未授权 Supabase MCP)**列出但标 `how_to_enable`**,不当默认。
- 环境变了(装新工具/授权新 MCP)→ 复跑 env-probe 刷新。

**没跑 /preflight 就选型 = 悬空**;下面的矩阵在 env-probe 闸过的候选里评分。

### 1. 能力需求驱动(从 PLATFORM-MATRIX 倒推)

| 关键能力 | 本项目需要? | 对栈的硬约束 |
|---|---|---|
| 原生重交互(AR / 人脸 / 相机算子 / 高帧动画) | <是/否> | 需要 → 偏原生 / Flutter;RN、web 壳偏弱 |
| 一份码多端(iOS + Android) | <是/否> | 需要 → Flutter / RN |
| 同源出 web / 小程序 | <是/否> | 需要 → 考虑 web 技术 / 跨端框架 |
| 后台任务 / 推送深度 | <是/否> | 重后台 → 原生更稳 |
| 离线优先 / 本地大数据 | <是/否> | 影响存储与同步方案 |

### 2. 候选对比矩阵(≥2 候选,1-5 分,5 最佳)

| 维度 | <候选 A> | <候选 B> | <候选 C> |
|---|---|---|---|
| 满足上面能力需求 | | | |
| 性能(动画 / 启动 / 内存) | | | |
| 原生 API 触达 | | | |
| 包体积 | | | |
| 生态 / 库成熟度 | | | |
| **AI-可建性**(LLM 对该栈熟练度——本流水线全 AI 驱动,此项权重高) | | | |
| 团队 / 作者技能 | | | |
| **合计** | | | |

> AI-可建性参考:Flutter/Dart、React/TS、SwiftUI 在主流 LLM 训练数据中覆盖好,AI 写得顺;冷门 DSL/新框架 AI 易错。

### 3. 决策

- **选定:** `<栈>` — <一句话理由,引用矩阵最高分项 + 能力需求命中>
- **反方风险:** <这个选择可能错在哪(1 句)>
- **不确定 → spike:** <若两候选接近,lockdown 技术 spike 跑哪个关键能力来定>

### 4. 后端选型矩阵(后端项目必填;与前端同级严谨)

> 默认 Supabase,但要按**能力需求**对比,不是无脑默认。备选含 **Cloudflare(AI 基建友好)**。
> ⚠️ **候选先过 §0 环境闸**:矩阵只在 `env-probe.json.backend_options.available=true` 的候选里评分。默认 Supabase **仅当它 available**(装了 CLI 或授权了 Supabase MCP);否则从环境已就绪的里选(如本机只有 wrangler+docker → 默认候选是 Cloudflare / 自建),并把"启用 Supabase 需装 CLI/授权 MCP"作为可选升级项告诉用户。

| 维度(1-5,5 最佳) | Supabase | Cloudflare | Firebase | PocketBase |
|---|---|---|---|---|
| 关系型 SSOT(schema 当真相源) | 5 | 3(D1=SQLite) | 1(NoSQL) | 4 |
| **权限/越权可声明(抗 AI 幻觉)** | **5(RLS)** | 2(写 Worker 代码) | 3(rules) | 3 |
| 实时同步 | 4 | 4(Durable Objects) | 5 | 3 |
| **AI 基建友好**(跑模型/向量/LLM 网关/RAG/边缘) | 3(pgvector) | **5(Workers AI+Vectorize+AI Gateway)** | 3(Vertex) | 1 |
| 成本上限可控(避失控账单) | 4 | **5(定价可预测)** | 2(账单易失控) | 5(自托管) |
| 低锁定 / 可自托管 | 5 | 3 | 1 | 5 |
| **agent 自助部署**(CLI) | 4(supabase) | **5(wrangler)** | 3 | 3 |

### 5. 后端决策逻辑

- **默认 Supabase**:关系型 + 权限复杂(越权 matters)→ **RLS 把"越权"这个 AI 头号幻觉区变可审计 SQL**,最值。大多数 CRUD / 记录类 app 走这。
- **选 Cloudflare** 当:① app 本身 **AI 重**(RAG/向量检索/跑模型/LLM 网关)② 要**边缘/全球低延迟** ③ 怕失控账单要**可预测成本** ④ 重 **agent 自助部署**(wrangler)。
  - ⚠️ **代价**:D1 无 RLS,权限写在 Worker 代码 = **回到 AI 幻觉区** → backend-forge 对 CF 栈**强制 ownership 越权矩阵 + 负向测试加倍严**(数量 = 矩阵行数,且每条手写权限要过对抗验证)来补 RLS 的缺位。
- **Firebase**:实时同步是核心(聊天/协作)且接受锁定 + 账单风险(必设预算告警)。
- **PocketBase**:纯副业极简自托管。

**选定写进 `backend-readiness.md`**,backend-forge Step 0 读它。

### FROZEN by default

技术栈定稿后默认 FROZEN。变更 = 回 discover/lockdown 重评 + 回 shape 重算多端影响(PLATFORM-MATRIX 可能变)。参照决策生命周期 § FROZEN。
