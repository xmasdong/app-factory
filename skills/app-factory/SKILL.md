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
2. 按下表派活,**派之前先列**:当前在哪关 + 下一步一句话

| 状态 | 派给 | 说明 |
|---|---|---|
| 无 status.md / 空目录 | `scaffold` → 然后 `discover` | 从头:初始化骨架 + 选品 |
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
  scaffold → discover → 🛑你看mockup → lockdown → shape → build → qa → release → ship
                                       └── 之后 hook 自动续接 ──┘
  贯穿:codex-image-bridge(mockup/图标/素材) · frontend-design 簇(UI) · app-store-review-survival(过审)
```

## 关键约束(路由也不能破)

- **不绕闸门**:每关 OUTPUT_GATE 机械验收(`sg_app_*`)照旧,过不了不放行
- **2-touch 停点保留**:discover 后必须等用户看 mockup,不自动推进
- **安全底线**:`.env` / 密钥 / `force push` 永远等人
- 路由只读状态 + 调对应 skill,不改任何产物

## 与各关 skill 的关系

`/app-factory` 是**门面**;`scaffold/discover/lockdown/shape/build/qa/ship` 是**实干者**,任何一关都能被单独调(调试/重跑某关)。详见 `ORCHESTRATION.md`。
