# App Factory — AI 驱动的「产品 → 上架」全流程 skill 工厂

把一句话产品想法,经 AI 自主流水线,带硬闸门地推到 **App Store / Google Play 可提审**。

> 这是把现有零散的 app 开发 skill **合并成一条统一流水线**的编排仓。
> 脊柱 = 7-skill 出海生命周期(scaffold→discover→lockdown→shape→build→qa→ship);工具 skill(出图/截图/过审/上传/UI 设计)插进对应闸门。

## 一句话流程

**入口:`/app-factory`**(读 `docs/status.md` 自动派到当前关;7 关也可各自单调)

```
/app-factory → scaffold → discover(选品+技术栈初选) → 🛑你看mockup → lockdown(真验证+技术栈定稿)
            → shape(规格) → build(实现+UI+美术) → qa(验收) → ship(上架材料+真上传)
```

全程 AI 自主,**只在看 mockup 时找你一次**(2-touch)。每关有机械验收闸门,过不了不放行。

## 完整流水线(脊柱 + 插入的工具 skill)

| 阶段 | Gate | 脊柱 skill | 插入工具 skill | 产物 |
|---|---|---|---|---|
| 0 初始化 | — | `scaffold` | — | app 项目骨架(hooks/模板/PROJECT_TYPE=app) |
| 1 探索 | Discovery | `discover` | `codex-image-bridge`(出 mockup) | 产品定位+市场调研+概念视觉+summary |
| 🛑 TOUCH | — | _你看 mockup_ | — | 推进 / 换方向 / 暂停 |
| 2 锚定 | Lockdown | `lockdown` | `app-store-review-survival`(合规) | 技术spike+单位经济+命名锁定+后端+合规 |
| 3 规格 | A-GATE 1 | `shape` | `frontend-design`(设计方向) | 完整 spec(PRD挑战/多端矩阵/数据契约/任务) |
| 4 实现 | A-GATE 2 | `build` | `frontend-design` + `polish/animate/colorize/harden`(UI 质量) | 代码+测试+commit |
| 5 验收 | A-GATE 3 | `qa` | `audit`(无障碍/性能) + `app-store-screenshots`(截图) + `app-store-review-survival`(复扫) | 多端smoke+截图存档+审核员预演 |
| 6 发布判定 | — | _generic release_ | — | release-ready |
| 7 上架 | A-GATE 4 | `ship` | `app-store-screenshots`(商店图) + `app-store-review-survival`(终扫) + `ios-ship-cli`(真上传) | 商店材料 + TestFlight/App Store 提交 |

## 为什么靠谱(不是玩具)

- **每关机械验收**(`sg_app_*` 硬检查函数),过不了阻塞
- **AI 自决要附证据**(市场调研禁用训练记忆,必须真 URL/API 响应)
- **决策生命周期**(optimistic / deferred / frozen / fused)+ 熔断器防死循环
- **多端一致性**强约束(PLATFORM 字段贯穿任务/数据契约/能力矩阵)

## 现状

- ✅ 脊柱 7 skill 已内置 `skills/`(scaffold/discover/lockdown/shape/build/qa/ship),去项目耦合、可移植
- ✅ 工具 skill 已内置:app-store-review-survival / app-store-screenshots / codex-image-bridge / ios-ship-cli + frontend-design 簇(21)
- ✅ 3 缺口已接:UI 簇 → shape/build/qa;ios-ship-cli → ship;app-store-screenshots → qa/ship
- ✅ 依赖(rules/templates/hooks/scripts)全内置,无硬编码路径,clone 即用
- 📋 详细编排 + 机械闸门 + 仓库结构:**见 `ORCHESTRATION.md`**

## 详见

`ORCHESTRATION.md` — 主编排 runbook(逐关细节 + 合并动作 + 机械闸门 + 仓库结构)
