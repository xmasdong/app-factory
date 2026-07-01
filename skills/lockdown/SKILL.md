---
name: lockdown
description: "Lock down all external anchors after user approval — technical spike, unit economics, naming (real evidence), backend, compliance. Autonomous chain to Shape after PASS. Phase B of app track 2-touch workflow."
---

# /lockdown — Phase B 锚定 (2-touch workflow 的 TOUCH 2 之后, AUTONOMOUS)

> ⚙️ **数字不是法律**:本文件的采样数(spike ≥3 假设 / 反薅 ≥5 / 命名 ≥5 候选 等)是**默认锚点**,按风险面上下调并说明依据;不适用的子步显式跳过(如免费产品的单位经济,见 economics 模板"钱从哪来"透镜)。真护栏照旧:命名跨文件一致 + 5 API 查重、价格阶梯单调、密钥不入 git、合规真扫。判断力地基见 `build-constraints.md`。

> 🟢 **本 skill 推荐执行形状 = ultracode 模式下,AI 用 Claude 的内置 Workflow 工具,按本 SKILL.md 描述的编排意图现场组合 script 并执行**;`scripts/workflows/lockdown.workflow.js` 只是**编排蓝图参考**(展示推荐的五路扇出结构,供 AI/人参考,不是被传给工具运行的脚本)。本项目不拥有任何 workflow 运行时。
> Workflow 是 Claude Code / ultracode 的**内置工具**(归 Claude);AI 在会话内现场组合 script(meta + phase + parallel/pipeline + agent({schema}))并执行——script 是 AI 当场写的,不是从本仓文件加载来跑。**不存在 `claude workflow` shell 命令,skill 也开不了用户的 ultracode 模式**——只能推荐。按蓝图做五路并行锚定 + 红队对抗复审;真 state 仍由既有确定性脚本/路径产出,闸门权威仍是 `app-gate.sh app-gate lockdown`。
>
> **降级路径(未开 ultracode / 不便编排时)= 单 agent 顺序自跑,不动闸门**:
> 严格按本 SKILL.md 现有顺序:**Step 2.1 spike → 2.2 经济 → 2.3 命名(候选→查重→选) → 2.4 后端 → 2.5 合规 → Step 3 跑 `app-gate.sh app-gate lockdown` → Step 4 信号 + 续接 /shape**。
>
> 降级时三处省心做法:
> 1. 命名 25 次查重(5 候选 × 5 源)用一个 Bash for 循环并发跑(curl 丢后台 `&` + `wait`),不需 agent 并行也能压时间——这是降级里唯一值得手动并发的 IO 密集点。
> 2. 对抗复审(按蓝图编排时的 Phase 2 红队)降级为:同一 agent 写完每节后自检一遍反薅/查重完整性,不再起独立 reviewer。
> 3. loop-until(命名 3 轮避冲突 / spike 3 次切备选)仍在单 agent 内用普通循环逻辑跑,行为与编排版一致。
>
> **结果等价性**:顺序自跑路径与按蓝图编排路径产出**完全相同的 state 文件**、过**完全相同的 `app-gate.sh lockdown` 闸门**、写**相同的 `clearance-lockdown.json`**。差别只在墙钟时间(5 段串行 vs 一段并行)和对抗深度(自检 vs 独立红队),不影响正确性与续接。

> 🎨 **design-first**:命名/经济/合规/后端**四项不豁免**;Step2.1 技术 spike 源从"mockup 关键交互"改为"design-manifest 关键交互 + 后端能力假设";`backend-readiness.md` 加一行**后端选型决策**(默认 Supabase + 声明式 RLS:把"越权"这个 AI 头号幻觉区变成可审计 SQL)。

> 🔗 **App Factory 集成 — 技术栈定稿**:Step 2.1 技术 spike 同时**定稿技术栈决策**。读 discover 的初选;若标了 `待 spike 定` 或两候选接近,**spike 跑关键能力**对比后定;写满 `app/templates/sections/tech-stack-decision.md`(决策 + 反方 + FROZEN)。合规扫描调 `app-store-review-survival`。

**作用:** 用户在 /discover Step 0.8 回 "推进" → hook 写 AUTONOMOUS=true → 本 skill 自动跑 5 子节真验证 → 通过后自动续接 /shape。

**关键约束:** AUTONOMOUS 模式下 AI 自决, 不问用户 (除非熔断 / 真不可知决策 / 合规阻塞)。每个子节必须有**真 evidence**, 拒绝 PROPOSED / 待跑 / TBD 占位。

---

**INPUT_CONTRACT:**
- `.claude/state/clearance-discover.json` 存在 (discover 已通过)
- `docs/status.md` 含 `AUTONOMOUS: true` (hook 写入的)
- `docs/status.md` 含 `CURRENT_GATE: A-GATE Lockdown`
- `docs/discovery-summary.md` 存在 (用户已看过 mockup)
- `docs/spec.md` 已有 `## 产品定位` / `## 市场调研` / `## 概念视觉` 3 章节

**CONTRACT 不满足:**
- 缺 clearance-discover.json → 提示先跑 /discover
- AUTONOMOUS 未设 true → 提示用户先回"推进"

**OUTPUT → spec.md 新增 5 章节 + `.claude/state/spike-results.json` + `.claude/state/asr-survival-scan.json` + `.claude/state/evidence/<name>.txt` 系列 + `.claude/state/clearance-lockdown.json` + skill-signal**

---

## 执行计划 (autonomous, 不询问用户)

```
- [ ] Step 2.1: 技术 spike (基于 mockup, 双语描述, 自决 PASS/FAIL)
- [ ] Step 2.2: 单位经济 (真数字, 无模糊词)
- [ ] Step 2.3: 命名锁定 (6 项查重, evidence 文件落盘)
- [ ] Step 2.4: 后端就绪 (具体值或显式 deferred)
- [ ] Step 2.5: 合规扫描 (调 app-store-review-survival, 必须 PASS)
- [ ] Step 3: 写入 spec.md 5 章节 + 跑机械验收
- [ ] Step 4: 写信号 + 自动续接 /shape (CURRENT_GATE → A-GATE Shape)
```

AUTONOMOUS 自决规则:
- spike 失败 → 切备选自动 retry, 3 次失败 → fuse 软熔断, 标 deferred 进 status.md
- 经济 / 后端 / 合规某项 deferred → 不阻塞其它项, 但 clearance 标 `not_verified`
- 高回滚成本+阻塞 (例: 数据库迁移, 不可逆云服务变更) → 真硬阻塞, 写 `等你: <具体问题>` 等人
- 安全底线 (.env / 密钥 / force push) → 永远等人

---

## Step 2.1: 技术 spike (基于 mockup, 双语描述)

**目的:** 验证 discovery 中 mockup 上画的关键交互真能实现.

### 执行

1. 从 `docs/spec.md ## 概念视觉` 章节提取每张 mockup 的关键交互
2. 每个关键交互 → 1 条 spike 假设 (≥3 条总)
3. 每条 spike 双语描述 + 实际跑

### 双语描述格式

```markdown
### 假设 H1: <一句话>

- **对应 mockup:** <screen-N-xxx.png 中的什么交互>
- **工程视角验证步骤:** <代码 / 命令 / 预期输出>
- **用户视角成功信号:** <一行非技术描述, 含可量化指标>
  例: "用户提交后 3 秒内出结果, 误差 ≤5%"
- **失败信号:** <用户视角>
  例: "用户等 >10 秒 或 效果歪扭"
- **回退方案:** <spike 失败时切什么>
- **结果:** PASS / FAIL → 切 <备选>
```

### 结果落盘

写 `.claude/state/spike-results.json`:
```json
{
  "spikes": [
    {"id": "H1", "result": "PASS", "evidence": "<路径>"},
    {"id": "H2", "result": "FAIL", "fallback_taken": "<备选>"}
  ]
}
```

AUTONOMOUS 自决: FAIL 自动切备选 retry. 3 次失败 → fuse 软熔断。

---

## Step 2.2: 单位经济 (真数字)

```markdown
## 单位经济 (ECONOMICS)

#### 单次成本表
| 操作 | 单次成本 (USD) |
|------|----|
| <真数据, 无"约/可能/待估"> | <数字> |

#### 价格阶梯 (单调递减)
| 档 | 价格 | 内容 | 均价/单位 |
| Free | $0 | ... | — |
| Tier 1 | $X | ... | $A |
| Tier 2 | $Y | ... | $B (B < A) |

#### 反薅漏洞清单 (≥5 条)
1. <具体漏洞 + 防护>
...
```

硬规则: 不接受 "约/可能/待估/TBD" 模糊词 (机械检查 `sg_app_economics_real`)。

---

## Step 2.3: 命名锁定 (AI 推荐 → 查重 → 用户选 → evidence 落盘)

**关键: AI 必须先推荐多个候选, 自动查重, 把未占用的列给用户挑。不接受"用户直接给一个名字" 然后只查那一个。**

### Step 2.3.0: AI 推荐 ≥5 个候选名

基于 Step 0 产品定位 (PRODUCT_FORM / TARGET_USER / TARGET_MARKET) 生成 ≥5 个候选名。

要求:
- 短 (≤12 字符), 易拼写, 易记
- TARGET_MARKET 国内 → 中英双向都顺 (e.g., 中文名 + 对应英文名)
- TARGET_MARKET 海外 → 纯英文, 避免母语者读不出
- 避免数字开头, 避免连字符 (App Store 不友好)
- 列名字 + 寓意 + 适配度评分 (1-10)

写入 `.claude/state/naming-candidates.json`:
```json
{
  "candidates": [
    {"name": "DayMark", "meaning": "Day + Mark, 记录每一天", "fit": 8},
    {"name": "TaskMate", "meaning": "任务都交给我", "fit": 7},
    ...
  ]
}
```

### Step 2.3.1: 自动查重每个候选

对每个候选跑 5 个 API 查重, 结果落盘:

```bash
for NAME in $(jq -r '.candidates[].name' .claude/state/naming-candidates.json); do
  EVIDENCE_DIR=".claude/state/evidence/naming-check-${NAME}"
  mkdir -p "$EVIDENCE_DIR"

  # 1. App Store (iTunes Search API) — 全市场扫
  curl -sf "https://itunes.apple.com/search?term=${NAME}&entity=software&limit=10" \
    > "$EVIDENCE_DIR/appstore.json"

  # 2. Google Play (无 API, 用 google-play-scraper 或手动)
  # AI 应调用 Playwright/scraper 抓 https://play.google.com/store/search?q=<NAME>&c=apps
  # 截图存 $EVIDENCE_DIR/play-store-search.png

  # 3. 域名 RDAP
  for TLD in com app io co; do
    curl -sf -o /dev/null -w "%{http_code}" "https://rdap.org/domain/${NAME}.${TLD}" \
      > "$EVIDENCE_DIR/domain-${TLD}.txt" 2>&1
  done

  # 4. npm
  curl -sf -o /dev/null -w "%{http_code}" "https://registry.npmjs.org/${NAME}" \
    > "$EVIDENCE_DIR/npm.txt"

  # 5. GitHub org
  curl -sf "https://api.github.com/users/${NAME}" \
    > "$EVIDENCE_DIR/github.json"
done
```

### Step 2.3.2: 输出"未被占用" 候选清单 给用户

解析查重结果, 标记每个候选状态:

| 候选 | App Store | Google Play | 域名 (.app) | npm | GitHub | 综合 |
|------|----------|-------------|------------|-----|--------|------|
| DayMark | ✅ 空 | ✅ 空 | ❌ 已注册 | ✅ 空 | ✅ 空 | ⚠️ 域名冲突 |
| TaskMate | ❌ 有 ("TaskMate Inc" Inc.) | ✅ 空 | ✅ 空 | ✅ 空 | ✅ 空 | ❌ AppStore 冲突 |
| FocusKit | ✅ 空 | ✅ 空 | ✅ 空 | ✅ 空 | ✅ 空 | ✅ 全干净, 推荐 |

写入 `.claude/state/naming-check-result.md` 并 inline 入 spec.md `## 命名候选查重` 章节。

**AUTONOMOUS 模式下**: 如果 ≥1 个候选全 5 项干净 → AI 自动选"综合 ✅ 全干净" + "适配度评分最高"的一个继续。
**如果全部候选都有冲突** → 回 Step 2.3.0 重新生成 (基于上轮冲突避开关键词), 最多 3 轮, 3 轮后还冲突 → fuse, 等用户介入。

### Step 2.3.3: 锁定选定的名字 (6 项 evidence)

只对**最终选定的名字**, 把 Step 2.3.1 已有的查重证据 finalize 为 6 项 evidence:

```bash
# 域名 RDAP
curl -sf "https://rdap.org/domain/<name>.com" \
  > .claude/state/evidence/domain-<name>.txt

# App Store iTunes Search
curl -sf "https://itunes.apple.com/search?term=<name>&entity=software&limit=5" \
  > .claude/state/evidence/appstore-<name>.json

# npm
curl -sf "https://registry.npmjs.org/<name>" \
  > .claude/state/evidence/npm-<name>.json

# GitHub
curl -sf "https://api.github.com/repos/<org>/<name>" \
  > .claude/state/evidence/github-<name>.json

# PyPI
curl -sf "https://pypi.org/pypi/<name>/json" \
  > .claude/state/evidence/pypi-<name>.json
```

### 写入 spec.md `## 命名锁定 (NAMING-LOCK)` 章节

```markdown
## 命名锁定 (NAMING-LOCK)

| 项 | 锁定值 | status | evidence |
|---|---|---|---|
| **品牌名** | <name> | status: locked | evidence: .claude/state/evidence/brand-<name>.txt |
| **域名** | <name>.app | status: locked | evidence: .claude/state/evidence/domain-<name>.txt |
| **App Store name** | <name> | status: locked | evidence: .claude/state/evidence/appstore-<name>.json |
| **Play Store name** | <name> | status: locked | evidence: .claude/state/evidence/play-<name>.json |
| **bundle id** | com.<org>.<name> | status: locked | evidence: .claude/state/evidence/bundle-<name>.txt |
| **IAP product id prefix** | com.<org>.<name>.iap.* | status: locked | evidence: .claude/state/evidence/iap-<name>.txt |
```

商标 (USPTO / 国内) 和 Google Play 无 API → 列 URL 给用户作 honor system, `status: PROPOSED` 不算 locked, 不计入"4 真 locked"要求。

### 硬规则

- `status: locked` 必须配对 evidence 文件实际存在 + ≥10 字节
- 文件不能含 "待跑" / "TODO" / "TBD" / "PROPOSED" / "待填" 字样
- 至少 4 项真 locked (域名 / AppStore / Play / bundle id), 其它可 PROPOSED

---

## Step 2.4: 后端就绪 (具体值, 不是"待注册")

```markdown
## 后端就绪 (BACKEND-READINESS)

V1 设计原则: <一句>

- [x] **用户体系**: <具体方案 + 实现服务>
- [x] **鉴权**: <具体> (无 "待定")
- [x] **推送**: APNs key ID <实际值> + FCM project number <实际值>
- [x] **支付**: RevenueCat entitlement IDs <列出> / Stripe shared secret env name
- [x] **删号接口**: <具体 API path> (Apple 5.1.1(v) 合规)
- [x] **演示账号**: email <实际> / password <实际>
- [x] **域名 + SSL**: <实际域名> 已注册 (或 deferred: 待注册, 日期: YYYY-MM-DD)
- [x] **监控**: <具体方案>
```

硬规则: `- [x]` checked 行不能含 "待注册" / "待跑" / "TODO" 等字样。未就绪的项改为 `- [ ] deferred: <理由+预计日期>`, 不阻塞但 clearance 标 not_verified。

---

## Step 2.5: 合规扫描 (调 app-store-review-survival)

调用外部 skill (如已安装) 或手动按其清单扫:

```bash
# 假设 skill 安装路径已知
./scripts/run-skill.sh app-store-review-survival \
  --output .claude/state/asr-survival-scan.json
```

输出 `.claude/state/asr-survival-scan.json`:
```json
{"result": "PASS", "checks": {...}}
```

写入 spec.md `## 合规扫描 (COMPLIANCE)` 章节, 8 项:
- 隐私政策 URL (live + 可访问)
- EULA (订阅 app 必填)
- 删除账号 path (Apple 5.1.1(v))
- GDPR consent + EU 跳转
- ATT 文案 (iOS, 具体 NSUserTrackingUsageDescription)
- Kids/COPPA 分类
- 网络授权时机 (隐私协议同意后)
- 权限文案 (NSCameraUsageDescription 等中英双语)

硬规则: asr-survival-scan.json 必须存在 + result=PASS 才放行。

---

## Step 3: 写入 spec.md + 跑机械验收

```bash
./scripts/app-gate.sh app-gate lockdown
```

通过 → 写 clearance-lockdown.json
不通过 → 按报错补; 同一项 3 次失败 → fuse 软熔断, 标 deferred

---

## Step 4: 写信号 + 自动续接 /shape

```bash
echo "{\"skill\":\"lockdown\",\"epoch\":$(date +%s)}" > .claude/state/skill-signal.json

# 更新 status.md: CURRENT_GATE → A-GATE Shape
sed -i '' 's/^CURRENT_GATE:.*/CURRENT_GATE: A-GATE Shape/' docs/status.md
```

收尾:
- 全通过: `完成: lockdown 通过, 自动进 /shape`
- 部分 deferred: `完成: lockdown 通过, N 项 deferred (列入 status.md), 自动进 /shape`
- 硬阻塞: `等你: lockdown 阻塞在 <具体项>, 需人介入`

**通过后立即调 /shape (任务链自动续接, 不问用户)。**

---

## OUTPUT_GATE (由 stop-app-audit 自动验收)

由 `sg_app_*` 函数集验收:
1. `sg_app_spike_dual_lang_real` — spike 4 双语字段 + PASS/FAIL 信号
2. `sg_app_economics_real` — 经济无模糊词 + 反薅 ≥5 + 价格阶梯
3. `sg_app_naming_real_evidence` — locked 项 evidence 真文件 + ≥4 真 locked
4. `sg_app_backend_real_status` — checked 行无"待注册" + ≥6 项
5. `sg_app_compliance_real_scan` — asr-survival-scan.json + result=PASS
6. `sg_app_bundle_coherence` — bundle id 跨文件一致

通过即写 `.claude/state/clearance-lockdown.json`, 任务链自动续接 /shape。
