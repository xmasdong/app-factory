---
name: app-factory
description: Unified entry / router for the App Factory app-dev pipeline. Reads docs/status.md CURRENT_GATE and dispatches to the right gate skill (scaffold→discover→lockdown→shape→build→qa→ship). Use when starting a new app ("做 X") or resuming an app project and unsure which gate to run. Routes only — the gate skills do the work; hooks keep auto-chaining.
---

# /app-factory — 统一入口 / 路由

**作用:** App Factory 流水线的**单一入口**。读 `docs/status.md` 的 `CURRENT_GATE`,派给对应关的 skill。**本身不干活,只调度。** 7 关仍各自可独立调,hook 继续自动续接。

## 何时用

- 新 app:空目录,想从头("做 X")
- 接手已有 app 项目,不确定该跑哪一关
- 想看整条流水线 + 当前进度

## 路由逻辑

1. 读 `docs/status.md` 顶部 `PROJECT_TYPE` + `CURRENT_GATE`(文件不存在 → 视为新项目)
   - ⭐ 开新项目时顺手问一句:上一款交付的项目 OSR 回填了吗?(status.md ## 度量;没回填=飞轮断供——门的失败模式反哺基座全靠这几个数)
2. 按下表派活,**派之前先列**:当前在哪关 + 下一步一句话

| 状态 | 派给 | 说明 |
|---|---|---|
| 无 status.md / 空目录 | `scaffold` → `preflight` → **问一次"要不要市场调研?"** → 要:`discover`;不要:记 skipped 直接 `lockdown` | 从头;调研与否是用户的取舍,机器只把两条路代价说清 |
| `PROJECT_TYPE: design-first`(已有设计稿) | `scaffold` → `preflight` → `discover`(轻量旁路)→ shape 调 `design-restore`+`backend-forge` | 导入图/设计稿→高保真app+后端API,见 `ROADMAP-design-first.md` |
| 无 `.claude/state/env-probe.json`(还没定栈) | `preflight`(扫工具链+MCP → 问发布目标 → 环境约束定栈/后端) | 别在真空选栈:装了才推,没授权标 how_to_enable |
| `PROJECT_TYPE` ≠ app | 提示走 generic 轨(setup/spec/impl/check/verify/release) | 非 app 项目 |
| `CURRENT_GATE: A-GATE Discovery` | `discover`;若 `phase: awaiting-decision` → 提示用户看 mockup 回「推进/换方向/暂停」 | 2-touch 停点 |
| `CURRENT_GATE: A-GATE Lockdown` | `lockdown` | 用户已回"推进" |
| `CURRENT_GATE: A-GATE 1`(Shape) | `shape` | |
| `CURRENT_GATE: A-GATE 2` | `build`(逐任务循环) | |
| `CURRENT_GATE: A-GATE 3` | `qa` | |
| `CURRENT_GATE: A-GATE 4` | `ship` | |
| 任务清单全 `- [x]` + ship 完 | 提示:已可提审,跑 `ios-ship-cli` 真上传 | |

## 流程总览

```
/app-factory(从这进)
  scaffold → preflight → discover → 🛑你看mockup → lockdown → shape → build → qa → release → ship
                                                   └── 之后 hook 自动续接 ──┘
  preflight:扫本机工具链+MCP → 问发布目标(全端→Flutter)→ 环境约束定栈/后端(env-probe.json)
  贯穿:codex-image-bridge(mockup/图标/素材) · frontend-design 簇(UI) · app-store-review-survival(过审)
```

## 关键约束(路由也不能破)

- **闸门 = 建议优先**:每关 OUTPUT_GATE 自检(`sg_app_*`)**默认只给建议、不阻塞**(尊重各人开发流程);`export APP_FACTORY_MODE=strict` 才硬挡。详见 README「闸门哲学」
- **2-touch 停点保留**:discover 后必须等用户看 mockup,不自动推进
- **安全底线**:`.env` / 密钥 / `force push` 永远等人(不受 advisory 影响)
- 路由只读状态 + 调对应 skill,不改任何产物

## 与各关 skill 的关系

`/app-factory` 是**门面**;`scaffold/discover/lockdown/shape/build/qa/ship` 是**实干者**,任何一关都能被单独调(调试/重跑某关)。详见 `ORCHESTRATION.md`。
