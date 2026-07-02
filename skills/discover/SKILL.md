---
name: discover
description: "Discover product viability autonomously — extract keywords, run market research, AI decides 5 fields based on evidence, produce mockup, write summary. Hard stop at TOUCH 2 (user reviews mockup). Phase A of app track 2-touch workflow."
---

# /discover — Phase A 探索 (Autonomous;唯一例外=启动第一问)

> ⭐ **启动第一问(收到"做 X"后的第一个动作,先于一切调研)**:问用户一次——
> **「要不要先做市场调研?」**(附一句各选项含义:调研=先验证需求/竞品再建,直接建=跳过验证马上进生产编排)
> - **要** → 走本 skill 完整流程(调研 → 自决 5 字段 → mockup → hard stop)
> - **不要** → 在 `docs/status.md` 决策清单记 `MARKET_RESEARCH: skipped-by-user (日期)`,跳过调研与 mockup,只从用户一句话提炼产品定位 5 字段写进轻量 `discovery-summary.md`(给用户过目的"我理解的产品+待确认点"),然后**直接进入生产编排**(/lockdown → /shape → /build …)。闸门自动配合不报缺。
> - 用户已带 PRD/设计稿 → 走下方对应旁路,这一问也可省(产品已定义)。
>
> **为什么问**:调研要不要做是**用户的钱和时间的取舍**,不是机器该替用户预设的(授权边界)。机器的义务是把两条路的代价说清,然后执行用户的选择。这一问之后,恢复 Autonomous:中间不再问任何字段。

> ⚙️ **数字不是法律**:本文件里的采样阈值(≥3 平台 / ≥100 差评 / 4-6 张 mockup / 5 字段 等)都是**默认锚点**。判断标准是"够不够识别重复模式 / 讲不讲得清概念 / 有没绕开上轮死因",不是凑固定数——按本品类可上下调并说明。真护栏照旧:市场结论必须真 URL 证据(训练记忆不算)、TARGET_MARKET FROZEN、收尾 hook 字符串。判断力地基见 `build-constraints.md`。

> ⚙️ **执行模型(主路径 + 降级,严格遵守)**
>
> **本 skill 主执行路径 = AI 用内置 Workflow 工具**(Claude Code / ultracode 自带,归 Claude,非 shell;本项目不定义、不拥有任何 workflow 运行时)。AI 按本 skill 描述的编排意图**当场组合并执行 script**(script 是 AI 现场写的,不是从本仓文件加载来跑)。编排意图的**参考蓝图**见 `scripts/workflows/discover.workflow.js`(示例扇出结构,供 AI/人参考,非可执行脚本、非传给工具运行的文件)。推荐编排形状(AI 现场据此组合,参考蓝图同上)——Frame(抽关键词 FROZEN)→ Research(sources×actions 扇出堆一手证据)→ Decide(propose→独立 red-team 对抗,证据不足回灌补一轮)→ Visualize(codex-image-bridge)→ Synthesis(completeness critic 跑确定性脚本 `app-gate.sh` 产闸门 state)。
>
> **推荐用户手动开 ultracode 模式**(会话高级模式,让 AI 倾向用内置 Workflow 工具来编排;skill/脚本无法自己开启它,故只推荐、不强制)。
>
> **降级路径 = 单 agent 顺序**(未开 ultracode / AI 不便用 Workflow 工具编排时的 graceful degradation。下方"## 执行计划"原始步骤本来就能跑,即为此降级):
> - **Step0** 抽关键词 + 读 discarded → **Step1** 一个 agent 串行跑 6 项强制调研(curl itunes + WebSearch 各平台 + 抓差评 + 找死亡案例 + 写反方,慢但完整)→ **Step2** 同一 agent 自决 5 字段并自附反方风险(⚠️ 无独立红队:prompt 须强制"先写方向,再切换红队人格攻击自己,反方论据不得少于 3 且每条带 URL,否则重写";建议补一段红队自检 checklist 否决重写弥补)→ **Step3** codex-image-bridge 出 ≥4 张 mockup(退化可 ASCII/文字线稿)→ **Step4** 写 spec.md 3 章节 + discovery-summary.md → **Step5** 跑 `./scripts/app-gate.sh app-gate discover` 产 `clearance-discover.json` + skill-signal,以 hard-stop 收尾。
> - **降级代价**:① 一手数据采集串行,慢;② 无独立对抗,反方质量靠单 agent 自律(易凑数);③ "需补证据"无法自动回灌定向调研,只能整段重跑。
> - **触发降级的判据**:AI 不便用 Workflow 工具编排 / 项目根无 `CLAUDE_PROJECT_DIR` / 用户明确要省 token / 关键词已极清晰且竞品稀少(扇出收益低)。
> - **两条路产物完全一致**:`spec.md`(3 章节)+ `discovery-summary.md` + `clearance-discover.json` + `skill-signal.json`。lockdown hook 链对二者无感。

> 🎨 **design-first 旁路**:`PROJECT_TYPE=design-first`(已有设计稿)时——**跳过市场调研重调研 + 跳过 Step3 mockup 生成**(设计稿即真图),只确认 TARGET_MARKET(合规相关)+ 问 REVENUE_MODEL,PRODUCT_FORM/TARGET_USER 从设计稿+用户一句话反推。**但必须照常产出 `clearance-discover.json` + `discovery-summary.md`**(lockdown 硬依赖,否则 hook 链断)。

> 📄 **PRD 旁路(产品已定义就别强做市场调研/mockup)**:`docs/` 下已有 PRD、或产品已明确定义,**且用户没明确要竞品调研**时——
> - **市场调研 = 可选**:不做,或只在用户要时轻验;产品定位 5 字段**从 PRD 读**,不靠市场倒推。
> - **mockup = 不强制生成**:有 PRD-frontend-ux 等 UI 描述就用它当视觉依据;没有也可**以 spec/计划当 TOUCH-2 检查点**(给用户看"我理解的产品+待确认点",不是非得一张图)。
> - 仍产 `clearance-discover.json` + `discovery-summary.md`(summary = 从 PRD 提炼的产品定位 + 待你确认点)。
> - 闸门已配合:有 PRD/设计稿时 `sg_app_market_evidence` / `sg_app_visual_artifact` **自动跳过、不报缺**。
> - **市场调研/mockup 只在「从模糊点子起步、需先验证再建」时才是核心必跑项**——别普世强加。

> 🔗 **App Factory 集成 — 技术栈初选**:Step 2 的 `TECH_STACK` 字段不要只写一行。用 `app/templates/sections/tech-stack-decision.md` 出**初选**:从能力需求倒推 + **≥2 候选对比矩阵**(含 **AI-可建性** 维度,本流水线全 AI 驱动)。接近难分的标 `待 spike 定`,留给 lockdown spike 决。mockup 用 `codex-image-bridge`。

**作用:** 用户输入"做 X" → AI 全自动跑 (抽关键词 → 市场调研 → 自决 5 字段 → 出 mockup → 写 summary) → 在 Step 5 hard stop 等用户看 mockup 决定。

**关键约束:**
- 中间**不问用户任何字段**, AI 基于市场调研自决
- 自决每项必须附**调研依据理由** (不是概率)
- 用户介入只在 TOUCH 2 (看 mockup + summary 决定推进/换方向/暂停)
- AI 不允许跑 spike / 经济 / 命名 / 后端 / 合规 (那是 /lockdown 在用户"推进"后跑的)

---

**INPUT_CONTRACT:**
- `docs/status.md` 顶部含 `PROJECT_TYPE: app` + `CURRENT_GATE: A-GATE Discovery`
- 用户用 ≥1 句话描述了产品方向 ("做 X")

**OUTPUT → spec.md 3 章节 (产品定位 / 市场调研 / 概念视觉) + `docs/discovery-summary.md` + `.claude/state/clearance-discover.json` + skill-signal**

---

## 执行计划 (autonomous, 不问用户)

```
- [ ] Step 0: 关键词抽取 (从用户一句话, AI 自动)
- [ ] Step 1: 市场调研 (AI 跑商店/差评/多源/死亡案例/反方, 一手数据)
- [ ] Step 2: AI 自决 5 字段 (基于调研, 附理由)
- [ ] Step 3: 出 mockup ≥4 张 (基于自决方向)
- [ ] Step 4: 写 spec.md 3 章节 + docs/discovery-summary.md
- [ ] Step 5: hard stop "等你: 看 mockup 决策 推进/换方向/暂停"
```

---

## Step 0: 关键词抽取 (autonomous, 不问用户)

从用户输入抽取:
- 领域 (例: 工具 / 健身 / 学习)
- 形态线索 (例: 工具 / 内容 / 社区)
- 用户线索 (例: 女性 / 学生 / 老人)
- 平台线索 (例: iOS / Android / 小程序)

**如果用户输入太抽象** ("做点东西" / "做个 app") → 反问让用户补 ≥1 句具体描述, 不接受空泛。

**关键: 检查"换方向"历史**
```bash
if [ -f .claude/state/discarded-directions.txt ]; then
  cat .claude/state/discarded-directions.txt  # AI 读这个文件
  # 文件含上一轮 AI 自决的 5 字段, 本轮必须避开类似方向
fi
```

如有 discarded-directions.txt: AI 必须在本轮自决时**显式选择与上轮不同的方向**, 在 discovery-summary.md 里说明 "本轮避开: <上轮方向>, 改为: <本轮方向>" + 理由。

---

## Step 1: 市场调研 (AI autonomous, 不问用户)

**目的:** 一手数据 + 反方论据, AI 不许用训练记忆做调研。

**硬规则:**
- 训练记忆里"我觉得" 全部不算数, 必须有 URL / API 响应 / 截图证据
- 2024 年前数据 → 必须 2025+ 一手验证, 否则在引用旁标 `[STALE-DATA]`
- ≥3 个独立平台

### 6 项强制要求

1. **商店榜单扫描** — App Store + Google Play 同领域 Top 50, iTunes Search API:
   ```bash
   curl -sf "https://itunes.apple.com/search?term=<keyword>&country=<region>&entity=software&limit=50" \
     > .claude/state/market-research/appstore-<region>-<keyword>.json
   ```
2. **差评抓样本** — Top 10 中每个 ≥10 条 1-2 星 review, 总样本 ≥100 条 (iTunes RSS feed)
3. **多源调研** — Reddit / 小红书 / X / Product Hunt / TikTok 等 ≥3 平台
4. **已死同品类 app ≥1** — app 名 + 死因 + URL 引用
5. **反方论据 ≥3** — 商业/技术/合规/竞争 角度
6. **数据时效性** — 引用标年份, 2024 前数据需 2025+ 验证

商店地区按"目标市场预判" (基于关键词中是否有英文/中文倾向, 或对比国内 vs 海外榜单热度):
- 关键词中文 / "国内" 表述 → 优先扫 cn
- 关键词英文 / "海外"/全球 → 优先扫 us
- 模糊 → 同时扫 us + cn, 对比量级决定 (Step 2 时输出"为什么选这个市场")

写入 spec.md `## 市场调研` 章节 (格式见 sections/market-evidence-section.md, 5 子节齐全)。

---

## Step 2: AI 自决 5 字段 (附调研理由)

**关键:** AI 基于 Step 1 调研, **自己**决定 5 个字段的值。**不问用户**。每个字段必须附 1 句"为什么这么定" 理由, 引用 Step 1 的调研依据。

### 5 字段自决格式 (写入 spec.md `## 产品定位` 章节)

```markdown
## 产品定位

PRODUCT_FORM: <Tool/Content/Community/Commerce/Hybrid> — <理由: 引用 Step 1 调研数据>
TARGET_MARKET: <地理> [FROZEN] — <理由: 引用 Step 1 商店地区 / 用户密度数据>
TARGET_USER: <年龄+性别+场景> — <理由: 引用 Step 1 差评样本中的用户画像>
REVENUE_MODEL: <Subscription/IAP/Ads/Commerce/Free/Hybrid> — <理由: 引用 Step 1 同品类 Top 10 变现模型>
TECH_STACK: <Flutter/RN/原生/Tauri/鸿蒙/待 spike 定> — <理由: 引用 Step 1 技术依赖度>
```

### 理由要求 (硬)

每条理由必须:
- 含具体数据引用 (例: "Top 50 中 30 个是订阅模型, 平均 $9.99/月")
- 不接受"通常这样定" / "经验上" 等抽象理由
- 含**反方风险提示** (1 句, 说明这个决定可能错在哪里)

理由质量例:
- ✅ 好: `TARGET_MARKET: 北美 [FROZEN] — Top 50 中 38 个是英文 app, 平均评分 4.3, 国内同品类仅 12 个且评分 3.8. 风险: 跨文化美学差异可能影响产品视觉接受度.`
- ❌ 差: `TARGET_MARKET: 北美 — 海外市场大. 风险: 待评估.`

### 已死方向避让

如有 `.claude/state/discarded-directions.txt` (上轮"换方向" 记录):
- 本轮 5 字段**至少 2 项与上轮不同**
- discovery-summary.md 顶部加"本轮 vs 上轮"对比表

### TARGET_MARKET 是 FROZEN-by-default

变更 = 全市场调研重做 (商店地区/合规框架/语言/支付通道都变)。锁后写入 spec.md, 不在 /lockdown 吸收。

---

## Step 3: AI 出 mockup ≥4 张 (基于自决方向)

基于 Step 2 自决的 PRODUCT_FORM + TARGET_USER, 生成 4-6 张 mockup:

- `hero.png` — 主效果图 / 产品定调
- `screen-1-entry.png` — 用户打开第一屏
- `screen-2-core.png` — 核心交互
- `screen-3-result.png` — 结果反馈
- (可选) `screen-4-monetize.png` — 付费墙 / 订阅页 (REVENUE_MODEL 涉及付费时)

存 `docs/mockups/` 或 `.claude/state/concept-visuals/<concept_name>/`.

生成方式:
- 优先用 `codex-image-bridge` skill 自动生成 (如已安装)
- 备选: 用 Playwright 截图工具或 ASCII wireframe
- 退化: 文字描述线稿 (每屏 ≥3 句话, 含布局/主色/关键元素), 但用户可能看不出 — 应优先真图

写入 spec.md `## 概念视觉` 章节, 引用产物路径 + 每张 mockup 一句话说明.

---

## Step 4: 写 spec.md + discovery-summary.md

### spec.md 3 章节 (Step 1/2/3 产出)
- `## 产品定位` (Step 2 自决 5 字段 + 理由)
- `## 市场调研` (Step 1 一手数据 + 5 子节)
- `## 概念视觉` (Step 3 mockup 路径 + 说明)

**不要**写 `## 单位经济` / `## 命名锁定` / `## 后端就绪` / `## 合规扫描` / `## 技术 spike` 等 lockdown 章节。那是 /lockdown 在用户"推进"后跑的。

### docs/discovery-summary.md (≤120 行, 用户 1 页能看完)

```markdown
# Discovery Summary — <project_name>

## AI 自决方向

PRODUCT_FORM: <值> — <理由>
TARGET_MARKET: <值> [FROZEN] — <理由>
TARGET_USER: <值> — <理由>
REVENUE_MODEL: <值> — <理由>
TECH_STACK: <值> — <理由>

## 本轮 vs 上轮 (仅当有 discarded-directions.txt)
| 字段 | 上轮 | 本轮 | 为什么换 |
|------|------|------|---------|
| ... | ... | ... | ... |

## 市场 highlights
- 最强需求信号: <一句话 + 数据引用>
- 最强反方论据: <一句话 + 数据引用>
- 已死同品类警示: <app 名 + 死因>

## 概念视觉 (mockup) 路径
- <path>/hero.png — <一句话说明>
- <path>/screen-1-entry.png — <一句话>
- <path>/screen-2-core.png — <一句话>
- <path>/screen-3-result.png — <一句话>

## 用户动线
1. 用户打开 → 看到 <第一屏>
2. 干啥 → 触发 <核心交互>
3. 得到 <结果反馈>
4. 留存/付费 → <如何>

## 决策 (待答)

请回我:
- **推进** → AI 自动跑 lockdown → shape → build → qa → ship 到最终产物
- **换方向** → 当前方向归档, AI 基于本轮避让重新探索
- **暂停** → 不动, 待你回来再说
```

### 硬规则

- AI **不主动写"推进建议"** — 决定权归用户
- AI **不主动续跑** lockdown — 必须等用户"推进" hook 触发
- AI 写完后必须以 `等你: 看 mockup 决策 推进/换方向/暂停` 收尾

---

## Step 5: 写信号 + 收尾

```bash
# 跑机械验收
./scripts/app-gate.sh app-gate discover

# 通过 → 写信号
mkdir -p .claude/state
echo "{\"skill\":\"discover\",\"epoch\":$(date +%s),\"phase\":\"awaiting-decision\"}" > .claude/state/skill-signal.json
```

最后一行 (合规结束标记, hard stop):
```
等你: 看 mockup 决策 推进/换方向/暂停
```

**不准在此后继续工作。** 用户回"推进"后, `pre-prompt-resume-detect.sh` hook 会自动写 AUTONOMOUS=true + CURRENT_GATE=A-GATE Lockdown, 然后由 /lockdown 接管。

---

## "换方向" 流程 (用户 TOUCH 2 选了换方向)

hook 自动:
1. 把 `.claude/state/concept-visuals/` 移到 `.claude/state/discarded-concepts/<timestamp>/`
2. 把 spec.md 的 `## 产品定位` 5 字段值 + 理由抽取写入 `.claude/state/discarded-directions.txt` (append)
3. AI 进 /discover Step 0 重新跑

AI 本轮 Step 0 必读 discarded-directions.txt, Step 2 自决时**至少 2 项与上轮不同** + summary 顶部加 "本轮 vs 上轮" 对比表。

3 次"换方向" 仍不满意 → fuse 软熔断 + 提示用户介入 (可能产品方向真的不对, 用户需提供更具体的 idea)。

---

## OUTPUT_GATE (由 stop-app-audit 自动验收)

机械检查项 (sg_app_*):
1. `sg_app_project_type` — PROJECT_TYPE=app
2. `sg_app_product_lock` — 产品定位 5 字段齐 + **每字段有理由** (`—` 后非空) + TARGET_MARKET 含 FROZEN
3. `sg_app_market_evidence` — 市场调研 5 子节 + 反方 ≥3 + 死亡案例 ≥1 + 数据样本目录
4. `sg_app_visual_artifact` — 概念视觉 mockup ≥1 张
5. `sg_app_discovery_summary` — discovery-summary.md ≤150 行 + 5 段齐全

写入 `.claude/state/clearance-discover.json`. 通过即可让 hook 在用户回"推进"时触发 AUTONOMOUS=true。

---

## 完成后下一步

`/discover` 完成后, **不该继续做任何事**。等用户回应:
- "推进" → hook 自动触发 /lockdown
- "换方向" → hook 归档当前方向, AI 回 Step 0 (读 discarded-directions.txt, 必须避让)
- "暂停" → 不动
