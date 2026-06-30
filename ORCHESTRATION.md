# 主编排 Runbook — App Factory

> 把现有 skill 合并成一条「产品→上架」流水线。本文 = 蓝图(blueprint)。
> 落地动作见末尾「合并动作清单」。

---

## 0. 组成(全内置于本仓 `skills/`)

**入口(路由)**:`app-factory` — 读 `docs/status.md` 当前关,派给对应 skill;不干活只调度,7 关仍各自可单调。新 app / 接手不确定在哪关时从这进。

**脊柱(app 出海生命周期,7 个)**:
`scaffold → discover → lockdown → shape → build → qa → ship`(带 5 道 A-GATE + 机械验收)

**工具 skill**:
`codex-image-bridge`(出图)· `app-store-review-survival`(过审)· `app-store-screenshots`(商店截图)· `ios-ship-cli`(fastlane 上传)· `frontend-design` + 20 动词簇(UI 设计/打磨)

**design-first 引擎(导入图/设计稿 → app + 后端)**:
`design-restore`(设计→高保真app,reify≠create)· `backend-forge`(功能/契约→完整后端API)。经 `docs/design/design-manifest.json` + `api/openapi.yaml` 两份 FROZEN 机读产物当桥,挂在 shape/build/qa 内(不进路由/不进 hook)。详见 `ROADMAP-design-first.md`。
这两 skill 真跑时主路径 = 用户手动开 ultracode 会话后,AI(Claude)用其【内置 Workflow 工具】,按 skill 用自然语言描述的编排意图当场组合并执行 script(script 是 AI 现场写的);`scripts/design-first/*.workflow.js` 仅作【编排蓝图参考】(展示推荐扇出结构,供 AI/人参考),不是传给工具运行的可执行 script。本项目不定义 workflow、不拥有 workflow 运行时。未开 ultracode/不便编排时降级 = 单 agent 顺序。不存在 `claude workflow` shell 命令。

**可选前置(通用开发轨,非本仓必需)**:`setup → spec → impl → check → verify → release` 这类 generic 开发流水线;若使用,app 轨 `ship` 以 generic `release` 的 release-ready 为前置。本仓 app 轨自带闸门即可独立运行。

⚠️ **版本说明**:旧文档提到 `/anchor`(A-GATE 0),现已折进 `lockdown`。以实际 7 skill 为准。

---

## 1. 逐关编排(每关:输入 → 主skill → 插入工具 → 产物 → 机械闸门)

### 阶段 0 · scaffold(一次性)
- **输入**:空目录 + 一句话产品描述
- **主**:`scaffold` — 复制 spec/status 模板,装 app hooks,写 `PROJECT_TYPE=app`
- **产物**:项目骨架
- **闸门**:—

### 阶段 1 · discover(A-GATE Discovery,自主)
- **输入**:`PROJECT_TYPE=app` + 用户"做 X"
- **主**:`discover` — 抽词→市场调研(iTunes API榜单/差评≥100/死亡案例≥1/反方≥3,**禁训练记忆**)→AI自决 5字段(形态/市场/用户/变现/技术栈,每条附证据理由+风险)→出 mockup
- **插入**:`codex-image-bridge` → 生成 ≥4 张真 mockup(hero/entry/core/result)
- **产物**:spec(产品定位+市场调研+概念视觉)+ `discovery-summary.md`
- **闸门**:`sg_app_product_lock` / `sg_app_market_evidence` / `sg_app_visual_artifact` / `sg_app_discovery_summary`
- 🛑 **HARD STOP** → 等用户:推进 / 换方向 / 暂停

### 阶段 2 · lockdown(A-GATE Lockdown,用户"推进"后自主)
- **输入**:`clearance-discover.json` + `AUTONOMOUS=true`
- **主**:`lockdown` — 技术spike真跑(PASS/FAIL+回退)→单位经济(真数字+反薅≥5)→命名锁定(≥5候选×5 API查重 AppStore/域名/npm/GitHub/PyPI,evidence落盘,≥4真locked)→后端就绪→合规扫描
- **插入**:`app-store-review-survival` → 合规扫描(8 项)产 `asr-survival-scan.json` 必须 PASS
- **产物**:spec +5章节
- **闸门**:`sg_app_spike_dual_lang_real` / `sg_app_economics_real` / `sg_app_naming_real_evidence` / `sg_app_backend_real_status` / `sg_app_compliance_real_scan` / `sg_app_bundle_coherence`
- → 自动续接 shape

### 阶段 3 · shape(A-GATE 1,规格)
- **主**:`shape` — PRD挑战(5视角)+故障想象力+多端能力矩阵(≥8行)+数据契约(多端消费方)+核心难点+覆盖契约(FROZEN)+任务拆分(每个带 PLATFORM)+4角色审查
- **插入(缺口)**:`frontend-design` → 定**设计方向/设计系统**(配色/排版/组件基调),写进 spec「视觉方向」,给 build 当 UI 基准
- **产物**:完整 `spec.md`
- **闸门**:`sg_app_platform_matrix` / `sg_app_task_platform_field` / `sg_app_prd_challenge` / `sg_app_fault_imagination` / `sg_app_data_contract` / `sg_app_coverage_contract`

### 阶段 4 · build(A-GATE 2,实现,逐任务循环)
- **主**:`build` — 逐任务到测试通过,PLATFORM隔离+bundle id一致+多端mock+范围纪律+3轮fix熔断+commit
- **插入(缺口)**:UI 类任务做完调
  - `frontend-design` → 出有设计感的界面(避 AI 通用脸)
  - `polish`(对齐间距收尾)· `animate`(动效)· `colorize`(配色)· `harden`(错误处理/i18n/文字溢出)· `delight`/`typeset` 按需
- **产物**:代码+测试+commit
- **闸门**:generic GATE 1/2 + `sg_app_bundle_coherence`

### 阶段 5 · qa(A-GATE 3,验收)
- **主**:`qa` — 覆盖契约对账+多端smoke+审核员路径预演(反绕过)
- **插入**:
  - `audit`(缺口)→ 无障碍/性能/响应式/反模式技术检查
  - `app-store-screenshots`(缺口)→ 3 视口 × 每端 截图存档(替"手动截图")
  - `app-store-review-survival` → 合规复扫(9 节 A-I)
- **产物**:`verify-report.json` + 截图存档 + 审核员预演产物
- **闸门**:覆盖契约全 PASS + asr-scan PASS

### 阶段 6 · release(generic,发布判定)
- **主**:generic `release` — 输出 `release-ready` / `ready-for-staging`(代码层能不能发)
- **产物**:`release-report.json`(ship 的前置)

### 阶段 7 · ship(A-GATE 4,上架)
- **主**:`ship` — ASO关键词定稿+商店材料(隐私问卷/EULA/分级/演示账号/审核notes)+多语言+合规终扫
- **插入**:
  - `app-store-screenshots`(缺口)→ 商店上架截图页(替泛"fastlane/Maestro")
  - `app-store-review-survival` → 合规终扫(二次)
  - `ios-ship-cli`(缺口)→ **真上传 TestFlight/App Store**(fastlane,命令行)
- **产物**:`store-materials/` + 实际提交
- **闸门**:5 个 clearance + spec_hash 一致 + release-ready

---

> 🎨 **美术/素材贯穿全程(app 开发的"画图"环节)**:
> - `codex-image-bridge` → mockup/效果图(discover)+ **app 图标 / 应用内插画素材 / 效果图(build)**
> - `app-store-screenshots` → 商店上架截图(qa / ship)
> - 图标约束:App Store 图标无 alpha;watchOS 图标不能深色底(明亮彩色满底)

## 2. 已接的缺口(合并重点)

| 缺口 skill | 现状 | 接到哪 | 价值 |
|---|---|---|---|
| **frontend-design 簇** | 完全没接 | shape(设计方向)+ build(UI实现)+ qa(audit) | UI 从"能跑"升到"有设计感",过审+留存都受益 |
| **ios-ship-cli** | 没接(ship 只备材料) | ship 末尾 | 真把包推上去,闭环最后一步 |
| **app-store-screenshots** | ship 用泛 fastlane | qa(截图存档)+ ship(商店图) | 程序化出多端上架截图,省手工 |
| **技术栈决策**(新增) | 原只 AI 自决一行 + spike 验可行 | discover(初选≥2候选矩阵)+ lockdown(spike 定稿) | 能力需求驱动 + AI-可建性权重 + 不确定 spike,选型不拍脑袋(模板 `sections/tech-stack-decision.md`) |
| **app-factory 路由**(新增) | 无统一入口 | 门面入口 | 读 status 派关,一个命令进,7 关仍可单调 |

---

## 3. 合并状态(已完成)

- ✅ 脊柱 7 skill + 工具 skill + UI 簇 已内置 `skills/`,去项目耦合、可移植(无硬编码路径)
- ✅ 依赖已内置:`app/rules/core.md`(决策生命周期+gate规则)、`scripts/app-gate.sh`(机械验收)、`app/templates/`(spec/status/sections)、`app/hooks/`(闸门+自动续接)
- ✅ 3 缺口已接:UI 簇 → shape/build/qa;`ios-ship-cli` → ship;`app-store-screenshots` → qa/ship
- ✅ 7 关各自可独立调 + hook 自动续接;入口见本 runbook
- 可移植:`clone` 后设 `AI_RULES_ROOT=<仓库根>` 即可被 scaffold 引用

---

## 4. 目标仓库结构(GitHub)

```
app-factory/
├── README.md                  # 总览 + 流水线图
├── ORCHESTRATION.md           # 本文:主编排
├── skills/                    # 合并后的 skill(Phase B 填充)
│   ├── scaffold/  discover/  lockdown/  shape/  build/  qa/  ship/   # 脊柱(7-skill 出海生命周期)
│   ├── app-store-review-survival/   # 工具(过审)
│   ├── app-store-screenshots/       # 工具(商店截图)
│   ├── codex-image-bridge/          # 工具(出图)
│   ├── ios-ship-cli/                # 工具(fastlane 上传)
│   └── frontend-design/  (+ polish/animate/colorize/audit/harden ...)  # UI 簇
├── rules/
│   └── core.md                # 决策生命周期 / A-GATE 规则 / 禁止模式
├── scripts/
│   └── app-gate.sh            # 机械验收(sg_app_* 函数集)
└── templates/
    ├── spec.md  status.md
    └── sections/  (platform-matrix / market-evidence ...)
```

---

## 5. 用法(合并完成后)

```
# 新 app:在空目录
/scaffold  → 描述"做 X"
/discover  → AI 跑选品 → 看 mockup → 回"推进"
（之后自动链:lockdown → shape → build → qa → release → ship）
# 中途只在看 mockup 时介入一次;每关闸门挡不合格产物
```

---

## 待确认(给作者)

- [ ] 脊柱升级:整仓 self-contained,还是引用 `~/.claude/skills/` 的工具 skill?(GitHub 发布建议 self-contained 全内置)
- [ ] 语言:README/SKILL 中文为主 还是 出英文版扩国际受众?
- [ ] 是否要一个「一键全自动」主 skill,还是保持 7 关各自可调 + hook 续接(现状)
