---
name: qa
description: "Quality-assure the app before store submission — multi-platform smoke runs, 3-viewport screenshot archive, reviewer-account walkthrough (anti-bypass), compliance rescan via app-store-review-survival. A-GATE 3 verification entry."
---

# /qa — A-GATE 3 验收 (app 主线)

> ⚙️ **推荐执行形态 = AI 用内置 Workflow 工具按本 skill 描述的编排意图现场组合并执行**(现场组合的 script 由 AI 即时编写,不是从本仓加载某文件来跑)。`scripts/workflows/qa.workflow.js` 仅为**编排蓝图参考**(展示推荐扇出结构,供 AI/人参考,非可执行脚本、非传给工具运行)。
> 推荐用户先开 **ultracode 模式**(让 AI 默认倾向多 agent 编排;skill/脚本无法自行开启它,也不存在 `claude workflow` shell 命令)。
> 蓝图建议的四质量形状(供 AI 现场组合 Workflow 工具时参考):fan-out(每端/每合规节一 worker)+ pipeline(端内 跑链路→截3viewport)+ adversarial verify(每条 reviewer claim × N skeptic 独立质疑,多数过)+ completeness critic(Synthesis 单 agent 用确定性脚本写闸门 state)。
>
> **降级:未开 ultracode 或 AI 未走多 agent 编排时**(对比是 Claude 内置 Workflow 工具现场编排 vs 单 agent 串行),单 agent 按下方 SKILL.md 原 7 步顺序串行执行,**产物与闸门 key 一字不差**:
> - **Step 1 覆盖契约**:逐链路对账(串行逐条)。
> - **Step 1.5 联调真跑**(全栈 app 硬门):`stack-up.sh` 拉起真栈 → 依次跑 `seam-smoke.sh` / `integration-test.py` / `contract-test.sh --target real` / `e2e-contract.sh`(产 4 个 state JSON)→ `stack-down.sh` 收摊。单 agent 也必须跑,不因降级跳过。
> - **Step 2 多端 smoke**:对 PLATFORM-MATRIX 声明的端逐端跑核心链路、各端用 `ui-snapshot.sh` 截 3 viewport,deferred 端写理由。失去并行只是更慢,逻辑等价。
> - **Step 4 反绕过 + paywall**:不开 N-skeptic,改为单 agent 自检 + **强制截图证据**(`no-bypass.png` / `paywall-full.png` / `iap-sandbox.png`)作为最强证据(本文件第 275 行已承认此步归 honor system),把"对抗"降级为"**必须有真实登录截图否则判 FAIL**"的硬证据闸门。
> - **Step 5 合规 9 节**:逐节串行扫。
> - **Step 6/7**:写 `verify-report.json` + `asr-survival-scan.json`,跑 `bash scripts/app-gate.sh app-gate qa` 复核,过则写 `skill-signal.json` + 推进 A-GATE 4。
>
> **降级核心**:并行→串行(慢但不丢覆盖);对抗多投票→单 agent + 强制截图证据(防 LARP 的兜底)。所有写入仍走确定性脚本 / 固定 schema,闸门 state 与编排路径一字不差。

> 🔗 **App Factory 集成**:Step 3 截图存档调 `app-store-screenshots`(3 视口 × 每端);追加 `audit` skill 做无障碍/性能/响应式/反模式技术检查;合规复扫调 `app-store-review-survival`(已集成)。

**作用:** 在写完代码后, 把整个 app 当成"审核员要看的产品"再走一遍. 覆盖契约对账 + 多端 smoke + 截图存档 + 审核员路径预演 + 合规复扫. 没过 /qa 不允许进 /ship.

**INPUT_CONTRACT:**
- A-GATE 0/1/2 已过 (clearance + 任务清单全 `- [x]`)
- `docs/spec.md` 中 BACKEND-READINESS 演示账号字段非 `<TBD>` (demo_account / sandbox_apple_id / google_test_account / reviewer_notes_account)
- `docs/spec.md` PLATFORM-MATRIX 章节声明了支持的端
- `docs/status.md` 顶部含 `CURRENT_GATE: A-GATE 3`

**CONTRACT 不满足时:**
- 缺 PROJECT_TYPE → 提示走 generic /verify
- 缺演示账号 → 拒绝执行, 列 BACKEND-READINESS 待补字段, 提示先回 /anchor 补
- 缺 PLATFORM-MATRIX → 提示先回 /shape

**OUTPUT → `.claude/state/verify-report.json` (扩展 schema) + `.claude/state/asr-survival-scan.json` + reviewer-walkthrough 产物 + skill-signal.json**

参照 `.claude/rules/core.md § A-GATE 3` 和 `.claude/rules/core.md § 交付前 5 自检` (多项目归属 / 通看成品 / 数据卫生 等).

---

## 执行计划

```
- [ ] Step 0: 验 INPUT_CONTRACT
- [ ] Step 0.5: 跑 `/self-correct` — 拿 `app/rules/build-constraints.md` 8 约束对成品自省(证据强度/直译/以用户走全程/主次/可玩性等),自纠 + 把"需真机/用户"项带进本次 not_verified
- [ ] Step 1: 覆盖契约对账 (核心链路全部覆盖, 不覆盖链路显式)
- [ ] Step 1.5: 前后端 seam 握手 + 契约真跑 (全栈 app 必跑, 硬门)
- [ ] Step 2: 多端 smoke (Multi-Platform Smoke)
- [ ] Step 3: UI 截图存档 (3 viewport × 每端)
- [ ] Step 4: 审核员路径预演 (含反绕过)
- [ ] Step 5: 合规自检 (调 app-store-review-survival skill, 9 节 A-I)
- [ ] Step 6: 写 verify-report.json + asr-survival-scan.json
- [ ] Step 7: 写完成信号 + 更新 status.md CURRENT_GATE → A-GATE 4
```

---

## Step 1: 覆盖契约对账

读 spec.md `## 覆盖契约` 章节. 每条核心链路对照已跑的测试 + smoke 截图, 判定 PASS / FAIL.

**重要:** /qa 不回答"还有没有遗漏". 只对照覆盖契约判断完整性. 发现链路缺失 → `new_paths_proposed_by_user` 字段记录, 回 /shape 修订契约, 不在本 skill 吸收.

**⚠️ Step 1 是纸面对照(对着测试判 PASS),不证明前后端合体能跑。** 真握手在 Step 1.5。

---

## Step 1.5: 前后端 seam 握手 + 契约真跑 (全栈 app 硬门)

> **为什么必填 (trade-copilot 实战教训):** app-factory 会分别产出「后端(测试绿)」+「前端(build 绿)」两个半体。**两半各自绿 ≠ 合体能跑** —— 前端可能全程 mock fallback、后端单独跑,seam(前端声明要调的 endpoint 在真后端是否存在/可握手)从没验过,`npm run dev` 从没指向真后端。Step 1 的纸面对照抓不到这个。这一步用真 HTTP 打通那条缝。

**适用判定:** 项目同时有「真后端(`backend/`|`server/`|`api/openapi.yaml`)」+「前端 api-client(引用 `/api/...`)」= **全栈 app** → 本步为**硬门**(不过不许进 /ship)。纯前端 / 纯后端 / design-only → advisory(仍建议跑,不阻塞)。若确要跳过本地合体验证,须在 `docs/status.md` 决策日志显式写 `seam ... deferred` 理由。

### 1.5.1 一键拉起全栈(stack-up 联调基建)

**别手动 boot** —— 用基建脚本一把拉起真栈(compose 优先起 PG/Redis/后端;无 compose 则按后端类型 native 起),等健康,并把**前端 env 写成指向真后端**(非 mock):

```bash
# compose 有则用(真 PG/Redis);快回路/CI/无 docker → 加 --native(进程起,零基建依赖)
bash .claude/scripts/design-first/stack-up.sh            # 或 --native --timeout 30
#  → .claude/state/stack-up.json { method, backend_url, backend_ready, pids, ... }
#  → 写 frontend/.env.local:NEXT_PUBLIC_API_BASE 等 = 真后端地址
```

`backend_ready=false`(超时没起)→ 联调门直接 FAIL,**不许**假装 PASS。起不来先修依赖/env(这本身就是"真实环境能不能联调"的一部分)。

### 1.5.2 打真后端跑四个确定性脚本(产 state JSON,闸门据此判)

```bash
BASE=$(jq -r .backend_url .claude/state/stack-up.json)   # 真后端基址

# ① seam 冒烟:前端声明的 endpoint 在真后端是否都存在/可握手
bash .claude/scripts/design-first/seam-smoke.sh --base-url "$BASE"
#    → seam-smoke.json { result, backend_boot, broken:[...] }

# ② 端到端联调(最强证据):真跑通 注册→拿 token→带 token 取受保护数据
python3 .claude/scripts/design-first/integration-test.py --base-url "$BASE"
#    → integration-test.json { result, token_obtained, steps:[...] }
#    (有 api/integration-flow.json 则按黄金流跑;否则从 live /openapi.json 自动派生)

# ③ 契约测试(schemathesis 打真后端,target=real,不是 mock)
bash .claude/scripts/design-first/contract-test.sh --base-url "$BASE" --target real
#    → contract-test.json { target:"real", result, failures }

# ④ E2E 字段对照:真实响应字段 vs openapi/manifest 声明
bash .claude/scripts/design-first/e2e-contract.sh --base-url "$BASE"
#    → e2e-contract.json { result, missing_fields, extra_fields }
```

### 1.5.3 收摊 + 判定(硬门)

```bash
bash .claude/scripts/design-first/stack-down.sh   # 联调完收摊(kill 进程 / docker compose down)
```

- `stack-up.json`: `backend_ready=true`(栈真起来了)
- `seam-smoke.json`: `backend_boot=true` 且 `broken`=0 → 前端每个 endpoint 在真后端可达
- `integration-test.json`: `result=PASS`(真 HTTP 鉴权 round-trip 通)→ **这才是"联调成功"的硬证据**
- `contract-test.json`: `target=real` 且 `result=PASS`(**mock-only 不算**)
- `e2e-contract.json`: `missing_fields`=0 且 `extra_fields`=0

**关键:** 由 `app-gate.sh app-gate qa` 的 `sg_app_seam_smoke` / `sg_app_integration_test` / `sg_app_contract_test` / `sg_app_e2e_contract_smoke` 读 state JSON 机械判。全栈 app 下它们是 `sg_run`(硬),不产 state = 缺证据 = 不过。**不许**手写 state JSON 造假(必须脚本真跑产出)。

### 1.5.4 前端指向真后端(人工确认放行清单)

seam 脚本证明「路由存在」,但前端 build 是否真的把 base-url 指向了这个后端(而非 mock/占位)属半机械 —— 记入 `not_verified`:前端 `NEXT_PUBLIC_API_BASE` / `.env` / api-client baseURL 是否 = 真后端地址,且 mock fallback 只在后端真不可达时兜底、不静默吞真错误。

---

## Step 2: 多端 smoke

每端跑 spec.md 覆盖契约里的核心链路, 每端独立判定 PASS / FAIL / DEFERRED.

| 端 | 跑什么 | 工具 | 必填? |
|----|--------|------|-------|
| iOS | 真机/模拟器跑完核心链路, 截图 | XCUITest / Detox / Maestro / 手动 | 矩阵声明则必填 |
| Android | 真机/模拟器跑完核心链路, 截图 | Espresso / Detox / Maestro / 手动 | 矩阵声明则必填 |
| 鸿蒙 | DevEco Studio + 真机 | hvigor + 手动 | 矩阵声明则必填 |
| 小程序 | 微信开发者工具 / 真机预览 | miniprogram-automator + 手动 | 矩阵声明则必填 |
| Web | Playwright headed mode, 多浏览器 | Playwright | 矩阵声明则必填 |

**判定:**
- PASS — 核心链路全跑通, 截图无空状态/报错弹框
- FAIL — 任一链路断在中间 / 闪退 / error toast
- DEFERRED — 矩阵显式声明本端不在 launch 范围 (写理由, status.md 记录)

**所有端 PASS 或 DEFERRED** 才能进 Step 3. 任一 FAIL → /qa 整体 send-back.

**反 LARP 检测 (机械验):**
- 每端必须有截图存到 `.claude/state/verify-screenshots/<platform>/`
- 截图 mtime 不早于最后 commit 30 分钟 (防"上次跑的截图复用")
- 截图 ≥ 1 KB (防空 PNG / 0 byte 占位)

---

## Step 3: UI 截图存档 (3 viewport)

每端 3 个 viewport 截图, 验证响应式 / 横竖屏 / 平板自适应:

| viewport | 尺寸示例 | 用途 |
|----------|---------|------|
| 手机竖屏 | iPhone 14 Pro (393×852) / Pixel 7 (412×915) | 主流用户视图 |
| 平板 | iPad 11" (834×1194) / Galaxy Tab S9 (800×1280) | 大屏布局扩展 |
| 手机横屏 | 同上 rotate | 横屏不能直接崩 / 内容必须重排 (4.0 design 拒因) |

**存档路径:**
```
.claude/state/verify-screenshots/
  ios/
    phone-portrait/<page>.png
    tablet/<page>.png
    phone-landscape/<page>.png
  android/
    ...
```

**机械验收:**
- 每端 ≥3 张截图 (3 viewport × 1)
- 每张 ≥5 KB (防空白屏)
- 总数 ≥ (端数 × 3 × 核心链路数)

**审美判定** (放行清单 not_verified):
- 字体 / 间距 / 配色是否符合 DESIGN.md
- 暗色模式渲染
- 国际化文案溢出

→ 这些归 GATE 2 真不可知, 检查点人工确认.

---

## Step 4: 审核员路径预演 (核心)

**为什么必填:** themeWeek 实测教训 — Apple 审核员用初始资源直接绕过付费墙 → 2.1 拒. 不在自动化测试里跑这条路径, 永远发现不了.

### 4.1 准备演示账号

从 `docs/spec.md` BACKEND-READINESS 章节读:
- `demo_account.username` + `password`
- `sandbox_apple_id` (iOS IAP 沙盒, 来自 ASC → Users and Access → Sandbox)
- `google_test_account` (Play Console 内部测试人员邮箱)
- `reviewer_notes_account` (写在 App Review Information 给苹果的账号)

**关键: 这四个账号可同一可分开, 但 reviewer_notes_account 必须等于 ASC 提交时填的那个.**

### 4.2 预演核心付费墙触发链路

每条都必须录 GIF/视频或截图序列, 存 `.claude/state/reviewer-walkthrough/`:

1. **订阅页 (paywall) 完整呈现**
   - 用 reviewer_notes_account 登录
   - 进入触发付费墙的核心动作 (如"导出高清" / "解锁第 11 个模板")
   - 截图: paywall 必须完整显示 subscription title / length / price / auto-renew 文案 / Privacy URL / Terms URL / Restore Purchases / Manage Subscription
   - 缺任一项 → 3.1.2 拒, 阻塞 /qa

2. **看广告解锁 (若 spec 有此机制)**
   - 触发看广告按钮 → 沙盒广告网络回包 → 解锁成功
   - 截图: 触发前 / 广告播放中 / 解锁后
   - 验证: 不能"广告播完直接解锁付费功能" (要走真实 SKU 验证)

3. **试用激活 (若 spec 有此机制)**
   - 触发试用 → 沙盒 IAP 弹框 → 确认 → 应用内状态切换 trial active
   - 截图四段: 触发前 / 沙盒弹框 / 试用激活后 / "管理订阅"路径可见

### 4.3 反绕过验证 (反 LARP 核心)

**审核员账号无法用初始资源绕过付费墙** — 必须主动测:

- 用 reviewer_notes_account 创建全新账号 / 重置到初始状态
- 直接尝试触发付费功能 → 必须弹付费墙 (不能因为账号是"内部账号"绕过)
- 如果存在"内部测试账号自动 VIP"逻辑 → 必须在 release 前关闭, 或仅对 sandbox_apple_id 生效不对 reviewer_notes_account 生效
- 验证证据: 截图 reviewer_notes_account 触发付费功能时看到完整 paywall

**themeWeek 教训:** 团队加了"@example.com 邮箱自动 VIP"逻辑没改, reviewer_notes_account 用了这个域名 → 审核员看不到 paywall → 3.1.2 拒.

### 4.4 IAP 沙盒环境验证

- 用 sandbox_apple_id 完整跑通: 购买 → receipt → 服务端验证 → 应用内权益激活
- 截图沙盒确认弹框 (右上角必须有 `[Environment: Sandbox]`, 否则不是沙盒)
- 验证 Restore Purchases: 删 app → 重装 → Restore → 权益回归
- 验证退款/取消: 通过 sandbox 后台触发 refund → 应用内权益回收

### 4.5 输出产物

存 `.claude/state/reviewer-walkthrough/`:
- `paywall-walkthrough.gif` (或 `.mp4`)
- `screenshots/paywall-full.png`, `iap-sandbox.png`, `restore.png`, `no-bypass.png`
- `walkthrough-notes.md` — 用户视角描述, 给 reviewer 当 Review Notes 草稿

**机械验收 (sg_app_reviewer_path):**
- BACKEND-READINESS 演示账号字段非 `<TBD>`
- 目录存在 + 文件数 ≥4
- 每文件 ≥5 KB
- `walkthrough-notes.md` 存在 + 非空 + 引用真实演示账号

---

## Step 5: 合规自检

调 `app-store-review-survival` skill (在 `~/.claude/skills/`).

按其 Pre-submission Checklist 9 分节 (A-I) 逐项过, 每项 PASS/FAIL/N_A + 理由:

- A. Categories (Kids 陷阱)
- B. Privacy & Consent (首屏 consent / Privacy URL / nutrition label)
- C. Permissions (Info.plist usage strings 具体化 + 多语言化)
- D. IAP / Subscriptions (3.1.2 完整披露)
- E. Account Deletion (5.1.1(v) 应用内自助路径)
- F. iPad / Watch / Universal
- G. Screenshots (尺寸 / 格式 / 内容真实性)
- H. Build Number (单调递增)
- I. Demo Account / Review Notes

**输出 `.claude/state/asr-survival-scan.json`:**
```json
{
  "scanned_at": "<ISO8601>",
  "skill_version": "app-store-review-survival@<commit-hash-or-mtime>",
  "sections": {
    "A_categories": {"result": "PASS", "notes": "Primary = Photo & Video, kids OFF"},
    "C_permissions": {"result": "FAIL", "notes": "NSPhotoLibraryUsageDescription vague"},
    ...
  },
  "overall": "needs-fix",
  "blocking_sections": ["C_permissions"]
}
```

**机械验收 (sg_app_compliance_scan):**
- spec.md `## 合规扫描` 章节 8 项 `status: locked`
- `asr-survival-scan.json` JSON 合法 + 全 9 sections
- 任一 FAIL → /qa 整体 send-back
- mtime 不旧于最后 commit 30 分钟

---

## Step 6: 写 verify-report.json

```json
{
  "decision": "pass",
  "contract_status": { "core_paths": "covered", "frozen_changes": [] },
  "fault_coverage": [ {"fault_id": "F-001", "covered_by_accept": "T3.A2"} ],
  "failures": [],
  "new_paths_proposed_by_user": [],
  "multi_platform_status": {
    "ios": "pass",
    "android": "pass",
    "harmony": "deferred",
    "miniprogram": "deferred",
    "web": "pass"
  },
  "reviewer_walkthrough_path": ".claude/state/reviewer-walkthrough/",
  "compliance_scan_result": {
    "scan_file": ".claude/state/asr-survival-scan.json",
    "overall": "ready-for-submit",
    "blocking_sections": []
  }
}
```

**字段语义:**
- `multi_platform_status` — 每端 pass/fail/deferred. 任一 fail → decision 必须是 send-back
- `reviewer_walkthrough_path` — 相对路径, 必须实际存在 + ≥4 文件
- `compliance_scan_result.overall` — ready-for-submit / needs-fix; needs-fix → decision=send-back

---

## Step 7: 写完成信号

```bash
echo "{\"skill\":\"qa\",\"epoch\":$(date +%s)}" > .claude/state/skill-signal.json
```

更新 `docs/status.md` `CURRENT_GATE: A-GATE 4` + 勾上 A-GATE 3.

---

## OUTPUT_GATE 硬要求

- verify-report.json 存在 + decision 合法
- `multi_platform_status` 任一非 pass/deferred → send-back
- `reviewer_walkthrough_path` 实际存在 + ≥4 文件
- `compliance_scan_result.overall == "ready-for-submit"`
- **(全栈 app)** `stack-up.json` backend_ready=true(真栈拉得起来)
- **(全栈 app)** `seam-smoke.json` result=PASS(后端起 + 前端 endpoint 全可达)
- **(全栈 app)** `integration-test.json` result=PASS(真跑通端到端联调:注册→token→取数据)
- **(全栈 app)** `contract-test.json` target=real & result=PASS(mock-only 不算)
- **(全栈 app)** `e2e-contract.json` result=PASS(前后端字段无 drift)

任一不通过 → 阻塞 + 列缺失项.

---

## 规则

- /qa 是有界的: 不回答"还有没有遗漏". 对照覆盖契约判断.
- 4 个新维度 (多端 / 截图 / 审核员路径 / 合规扫描) 必须完整, 不接受"deferred 但没记录".
- Step 4 审核员路径无法 100% 机械自动化 → reviewer_notes_account 真实登录 + 反绕过截图作为最强证据, 其余归 honor system.
- Step 5 合规扫描必须基于最新版 app-store-review-survival skill, 不 cache 旧扫描结果.

---

## 完成后下一步

`完成: /qa 全部 PASS, A-GATE 3 通过, 下一步 /ship 进入 A-GATE 4`

或失败:

`停住: Step 4 反绕过验证失败 (reviewer_notes_account 自动 VIP), 修代码后重 /qa`
