---
name: preflight
description: "开局环境预检 + 发布目标问询 → 环境约束下的技术栈/后端决策。先扫本机真装了什么工具链(flutter/xcode/android/node/wrangler/supabase/docker...)+ 哪些 MCP 配置授权了,再问用户发布目标(全端→Flutter),据此只推荐环境能真正构建/授权的栈;没装没授权的标『需先装 X / 需先授权 Y MCP』。产 .claude/state/env-probe.json 喂 lockdown/backend-forge 决策矩阵。scaffold 后、lockdown 选型前跑。"
---

# /preflight — 环境预检 + 栈决策地基

> **为什么要这一步:** 技术栈不该在真空里拍脑袋。「装了 Xcode 才推 iOS 原生」「装了 flutter 且要全端才推 Flutter」「装了 wrangler 才把 Cloudflare Workers/D1/Container 当可用后端」「Supabase 要先配置并授权 Supabase MCP 才算就绪」。**能力受环境约束** —— 推一个本机构建不了、或没授权的栈 = 让用户卡在第一步(trade-copilot 窗口就卡过环境)。

**作用:** ① 机械扫描本机工具链 + 已配置 MCP → `env-probe.json`;② 问用户**发布目标**(这是真·用户决策,不替他定);③ 在环境约束下给栈 + 后端推荐(可用的推,不可用的说清缺什么/怎么开)。产物喂 `tech-stack-decision.md` 矩阵 + `backend-forge`。

**何时跑:** `/scaffold` 之后、`/lockdown` 技术选型之前。也可单跑复检环境。

**INPUT:** 项目已 scaffold(有 `.claude/scripts/env-probe.sh`)。若无 → 先 `/scaffold`。

**OUTPUT:** `.claude/state/env-probe.json` + 在 `docs/status.md` / `docs/lockdown/backend-readiness.md` 记下发布目标 + 选定栈(带环境依据)。

---

## 执行计划

```
- [ ] Step 0: 跑 env-probe.sh → env-probe.json + 人读摘要
- [ ] Step 1: 给用户看「本机已装能力」
- [ ] Step 2: 问发布目标(全端 / iOS / Android / Web / 桌面)→ 映射前端栈
- [ ] Step 3: 环境约束下推荐后端(只推 available;不可用标 how_to_enable)
- [ ] Step 4: 记决策(status.md 发布目标 + tech-stack + backend-readiness)
```

---

## Step 0: 跑环境预检

```bash
bash .claude/scripts/env-probe.sh
#  → .claude/state/env-probe.json:
#     toolchains{flutter/xcodebuild/swift/adb/node/wrangler/supabase/docker/...: {present,version,path}}
#     mcp_servers{configured:[...], backend_relevant:{supabase,cloudflare,firebase}}
#     capabilities{build_ios_native, build_android_native, build_cross_platform_flutter, build_web}
#     stack_by_publish_target{ios_only, android_only, all_platforms, web_only}
#     backend_options[{option, available, why, how_to_enable}]
```

**只读探测,不改系统、不打印任何密钥。** 缺 `jq` → 退化 present-only(仍可用,信息少)。

---

## Step 1: 给用户看本机能力

把 env-probe.json 的摘要念给用户(已装工具链 + 构建能力 + 已配置 MCP + 后端可选项)。目的:让用户在**知道机器真实底牌**的前提下选发布目标,而不是选完才发现缺 SDK。

---

## Step 2: 问发布目标 → 映射前端栈(核心用户决策)

**必须问用户**(用 AskUserQuestion / 直接问),不替他定发布范围:

| 发布目标 | 环境就绪时推荐 | 环境不满足时 |
|---|---|---|
| **全端**(iOS+Android[+Web/桌面]) | **Flutter**(一套码多端;批量换皮/微创新出海首选)——需 `flutter`+`dart` | 缺 flutter → 提示装,或退 RN(需 node) |
| iOS only | SwiftUI 原生 —— 需 `xcodebuild`+`swift` | 缺 Xcode → 装 Xcode CLT,或走 Flutter/RN |
| Android only | Kotlin/Compose —— 需 Android SDK(`adb`/`gradle`) | 缺 → 装 Android Studio |
| Web / PWA | Next.js/React/Vite —— 需 `node` | 缺 node → 装 |
| 混合/快速验证 | Flutter 或 Web PWA 覆移动 | 按已装的来 |

**铁律:推荐必须落在 `capabilities` 为 true 的范围内。** 若用户要的目标本机构建不了 → **明说"缺 X,先装 or 换目标"**,不静默选一个跑不起来的栈。发布目标写进 `docs/status.md`(如 `PUBLISH_TARGET: all-platforms`)。

> 与既有决策生命周期一致:发布目标是 optimistic 决策,lockdown spike 可复核。

---

## Step 3: 环境约束下推荐后端

读 `env-probe.json` 的 `backend_options`,**只把 available=true 的当默认候选**;unavailable 的列出来但标 `how_to_enable`,让用户主动选择是否去装/授权。

决策仍走 `tech-stack-decision.md` 后端矩阵(7 维),但**候选池被环境闸掉**:

- **Supabase**(矩阵默认,RLS 抗越权最佳)→ 但**需 `supabase` CLI 或已配置+授权 Supabase MCP**。未就绪 → 告诉用户:"Supabase 要先 `brew install supabase/tap/supabase` 或 在 Claude 配置并授权 Supabase MCP;在此之前它不是可用选项。" 用户授权后复跑 env-probe 即变 available。
- **Cloudflare**(AI 基建友好:Workers AI/Vectorize/AI Gateway;边缘;成本可预测)→ 装了 `wrangler` 即可用 Workers/Pages/D1/R2/Queues/Container。⚠️ D1 无 RLS → backend-forge 对 CF 栈**越权负向测试 ≥ 矩阵行数 ×2**。
- **docker-selfhost / python-fastapi / node-server / go-server** → 对应运行时装了就可用(自建 Postgres/Redis 走 docker)。
- **Firebase** → 需 firebase-tools/MCP。

**输出:** 选定后端写进 `docs/lockdown/backend-readiness.md`(backend-forge Step 0 读它),注明"环境依据:env-probe.json 中 <option>.available=true"。

---

## Step 4: 记决策

- `docs/status.md`:加 `PUBLISH_TARGET: <目标>` + `TECH_STACK: <前端栈 + 后端>`(替换模板 `${TECH_STACK}` 占位)
- `docs/lockdown/backend-readiness.md`:选定后端 + 环境依据
- 若用户选的栈缺工具链/MCP → 在 status.md 决策清单记 deferred:"待装 <X> / 待授权 <MCP>",并把它当 lockdown 的前置人工动作

---

## 规则

- **只读探测**,env-probe.sh 绝不改系统、不打印密钥。
- **发布目标归用户**:不替用户定全端还是单端;但必须在他知道本机能力后再问。
- **不推环境构建不了的栈**:capabilities=false 的目标 → 明确"缺什么、怎么补",不硬选。
- **MCP 类后端(Supabase 等)未授权 = 不可用**:列为候选但标 how_to_enable,授权后复跑 env-probe 转 available。
- 环境会变(装新工具/授权新 MCP)→ env-probe 可随时复跑刷新 `env-probe.json`。

---

## 完成后下一步

`完成: 环境预检出 env-probe.json,发布目标=<X> → 栈=<Y> + 后端=<Z>(环境已就绪),下一步 /lockdown 定稿选型`

或阻塞:

`等你: 目标要 <全端/Supabase 等> 但本机缺 <flutter / Supabase MCP 授权>,先装/授权还是换目标?`
