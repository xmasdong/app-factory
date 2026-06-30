---
name: design-restore
description: "把设计稿(.pen / Figma / 截图)还原成高保真 app 前端 —— 三段式:①抽取(三管线归一成 design-manifest.json + tokens.json + baseline PNG,每字段标 extracted/inferred)②代码化(Style Dictionary 把 DTCG token 出各端,实现只引用 token)③闭环 diff(截图 vs baseline 跑 pixelmatch/SSIM + token 对账 + VLM 残差,3 轮熔断,停止判据=分数单调降)。真 skill,可单跑,经 shape 调抽取段、build/qa 调渲染+diff 段,不进路由、不进 hook 状态机。"
---

# /design-restore — 设计 → 高保真 app(真 skill,非脊柱关)

> 🔗 **App Factory 集成 — reify≠create**:本 skill 只做**还原(reify)**,不做**创造(create)**。视觉方向 / 设计系统的"从无到有"由 `frontend-design` 负责;本 skill 拿到既有设计稿后**忠实还原**。两者职责不重叠:有设计稿走 design-restore,无设计稿(只有需求)走 frontend-design。
>
> 🔗 **调用关系**:本 skill 可单跑,也被脊柱关内部调用 —
> - **shape** 调本 skill 的【段一:抽取】把设计稿固化成 design-manifest.json,作为 spec.md「视觉方向」的机读真相源
> - **build** 调本 skill 的【段二:代码化 + 段三:diff】把 token 出各端 + 渲染后跟 baseline 对账
> - **qa** 调本 skill 的【段三:闭环 diff】做视觉回归验收
> 每段内部都有「单跑 / 被调用」两种入口说明,见各段开头。

**作用:** 导入设计稿(.pen / Figma / 截图任一),产出**能上线生产**的高保真前端 —— 三段式流水线:抽取(归一化成 FROZEN 机读产物)→ 代码化(token 中间层,实现只引用 token)→ 闭环 diff(截图 vs baseline 量化对账,分数不单调下降即停上报)。

---

**INPUT_CONTRACT:**
- 至少一种设计源可达(三选一,优先级从高到低):
  - `source=pen` — `.pen` 文件路径 + pencil MCP 桌面 app 在跑(`get_editor_state` 不报 WebSocket not connected)
  - `source=figma` — Figma file key + REST token(env `FIGMA_TOKEN`)
  - `source=screenshot` — 一张或多张 PNG 截图(用户多用 codex-image mockup,**截图是一等输入**)
- 目标平台已知:`<platform> ∈ {SwiftUI, Flutter, Compose, Tailwind}`(可多选)
- 目标视口已知:`<viewport>`(如 iPhone-390x844 / Android-360x800 / web-1440x900)
- **被调用模式**额外要求:调用方传入 `docs/design/` 目标目录 + 当前所处段(extract / codegen / diff)

**CONTRACT 不满足时:**
- 三种源全不可达 → 拒绝执行,提示至少给一张截图
- `source=pen` 但 `get_editor_state` 报 WebSocket not connected → **走降级链**(见段一),不硬失败:退到 .pen 导出的 PNG 走截图档,manifest 如实标低置信度
- 目标平台不在 4 个合法值内 → 提示 Style Dictionary 暂不支持该端

**OUTPUT → `docs/design/design-manifest.json` + `docs/design/tokens.json` + `docs/design/baseline/<platform>/<viewport>/<screen>.png` 系列 + 各端 token 文件 + `.claude/state/design-diff-result.json` + skill-signal.json**

桥产物路径 + schema 固定(下游只认机读产物,不直接解析原始 .pen/Figma),参照锁定契约「桥产物」节。

---

## 执行计划

```
段一:抽取(归一化)
- [ ] Step 1.0: 探源 + 选管线 + 降级链判定
- [ ] Step 1.1: 抽 token(最确定先抽)→ 落 tokens.json (W3C DTCG)
- [ ] Step 1.2: 抽屏清单 + 组件清单
- [ ] Step 1.3: 逐屏抽布局树 + text + nav + 推断态/字段/实体/端点
- [ ] Step 1.4: 导 baseline PNG(每屏每视口)
- [ ] Step 1.5: 写 design-manifest.json,每字段标 extracted/inferred
- [ ] Step 1.6: 抽取段验收(sg_app_design_baseline_exists)

段二:代码化(token → 各端)
- [ ] Step 2.0: Style Dictionary 读 tokens.json
- [ ] Step 2.1: 出各端 token 产物(SwiftUI/Flutter/Compose/Tailwind)
- [ ] Step 2.2: 按 manifest.components 生成组件 + 按 screens 组装屏
- [ ] Step 2.3: 硬编码值反扫(实现处只引用 token,禁字面量)

段三:闭环 diff(截图 vs baseline)
- [ ] Step 3.0: 渲染目标屏 → 截图(固定 DPR / 视口)
- [ ] Step 3.1: 屏蔽动态区(动画 / 头像 / 时间)防误杀
- [ ] Step 3.2: 像素 diff(pixelmatch)+ 结构 diff(SSIM)
- [ ] Step 3.3: token 对账(渲染态 computed style vs tokens.json)
- [ ] Step 3.4: VLM 残差(语义级"哪里不像")
- [ ] Step 3.5: 复用 build 修复循环,3 轮熔断,停止判据=分数单调降
- [ ] Step 3.6: 写 design-diff-result.json + 闭环段验收
- [ ] Step 4: 写信号
```

---

# 段一:抽取(归一化)

> **单跑入口:** 用户给设计源 → 本段产出三件 FROZEN 机读产物。
> **被调用入口(shape):** shape 在「视觉方向」步调本段,把设计稿固化成 design-manifest.json,后续 spec 的 components/screens 直接引用其字段。shape 只读 manifest,不重抽。

## Step 1.0: 探源 + 选管线 + 降级链

```
get_editor_state()  # 仅 source=pen 时
```

| 源 | 管线 | 降级链 |
|----|------|--------|
| `pen` | pencil MCP(见下序列) | MCP 不可达 → 退 .pen 导出 PNG → 走 screenshot 档,manifest 标 `source:"screenshot"` + 全字段 confidence 降级 |
| `figma` | Figma REST(`/v1/files/:key` + `/v1/images`) | token 失效 / 限流 → 退已导出 PNG → 走 screenshot 档 |
| `screenshot` | VLM 视觉抽取 | 无降级(已是最底档);截图模糊 → 标 `inferred` 并在 manifest 记 `low_confidence_reason` |

**降级铁律:** 任何降级**不静默** —— manifest 顶部 `extraction_meta` 必须记 `requested_source` / `actual_source` / `degraded:true/false` / `reason`。下游据此知道置信度天花板。

## Step 1.1: 抽 token(最确定先抽)

**为什么先抽 token:** token 是设计稿里**最机械、最可信**的部分(变量表 / 颜色 / 间距),先固化它,后面布局抽取的不确定性不污染 token。

### pen 管线
```
get_variables()        # → 直接拿到设计变量,最确定,优先全抽
```
把 pencil 变量映射到 W3C DTCG 结构。

### figma 管线
读 `styles` + `variables`(Figma Variables REST),映射到 DTCG。

### screenshot 管线
VLM 抽主色板 / 字号阶梯 / 圆角 / 间距,**全部标 `inferred`**(像素量出来的不是设计意图)。

### 落 `tokens.json`(W3C DTCG 风格)
```json
{
  "$schema": "https://design-tokens.github.io/community-group/format/",
  "color": { "primary": { "$value": "#3B82F6", "$type": "color", "$extensions": { "confidence": "extracted" } } },
  "space": { "md": { "$value": "16", "$type": "dimension", "$extensions": { "confidence": "extracted" } } },
  "radius": { "card": { "$value": "12", "$type": "dimension" } },
  "type":  { "body": { "$value": { "fontFamily": "Inter", "fontSize": "16", "lineHeight": "1.5" }, "$type": "typography" } },
  "theme": ["light", "dark"]
}
```
每个 token 的 `$extensions.confidence` 标 `extracted` | `inferred`。

## Step 1.2: 抽屏清单 + 组件清单

### pen 管线
```
batch_get(patterns: [{ type: "frame" }])          # 屏清单
batch_get(patterns: [{ reusable: true }])         # 可复用组件清单
```

### figma 管线
顶层 `CANVAS` → 子 `FRAME` = 屏;`COMPONENT` / `COMPONENT_SET` = 可复用组件。

### screenshot 管线
一张截图 = 一屏;组件由 VLM 切分推断,标 `inferred`。

## Step 1.3: 逐屏抽布局树 + text + 推断

### pen 管线
```
# 逐屏:
batch_get(nodeIds: [frameId], readDepth: 3, resolveInstances: true)   # 布局树 + text,readDepth≤3 控规模
snapshot_layout(problemsOnly: true)                                   # 拿布局问题(重叠/越界)
```

### 每屏抽这些字段(对应 manifest.screens[]):
| 字段 | 来源 | confidence |
|------|------|-----------|
| `layout_tree` | 抽取(布局树) | extracted |
| `texts[]` | 抽取(文本节点) | extracted |
| `nav_to[]` | 抽取(链接/跳转)或 LLM 推断 | extracted / inferred |
| `inferred_states[]` | LLM 推断(empty/loading/error/...) | **inferred** |
| `fields[]` | LLM 从表单/输入推断 | **inferred** |
| `inferred_entities[]` | LLM 从屏内容推断业务实体 | **inferred** |
| `inferred_endpoints[]` | LLM 从实体派生后端端点草稿 | **inferred** |

**reify≠create 红线:** 抽取段只**记录看到的 + 标注推断的**,不发明 UI。`inferred_*` 字段全部是**草稿**,需人确认(与 backend-forge 的 inferred 一致姿态);下游 shape/backend-forge 拿来当起点,不当定论。

## Step 1.4: 导 baseline PNG

### pen 管线
```
export_nodes(nodeIds: [...], format: "png")    # 每屏导 baseline
```
按 `docs/design/baseline/<platform>/<viewport>/<screen>.png` 落盘。

### figma 管线
`GET /v1/images/:key?ids=...&format=png&scale=<DPR>`。

### screenshot 管线
原始截图**即** baseline(本来就是图),复制到 baseline 路径并记 `baseline_is_source:true`。

**DPR 固定:** baseline 导出 DPR 必须记进 manifest,段三渲染截图用同一 DPR(纯像素 diff 误杀 30-40% 的主因之一是 DPR 不一致)。

## Step 1.5: 写 design-manifest.json

```json
{
  "extraction_meta": { "requested_source": "pen", "actual_source": "pen", "degraded": false, "reason": null, "dpr": 2 },
  "source": "pen",
  "tokens": { "...见 tokens.json,此处可引用或内联摘要..." },
  "components": [
    { "name": "PrimaryButton", "reusable": true, "props": ["label","disabled"], "states": ["default","pressed","disabled"], "confidence": "extracted" }
  ],
  "screens": [
    { "id": "home", "name": "首页", "baseline_png": "baseline/SwiftUI/iPhone-390x844/home.png",
      "layout_tree": { "...": "..." }, "texts": ["..."], "nav_to": ["detail"],
      "inferred_states": ["empty","loading","error"], "fields": [],
      "inferred_entities": ["Item"], "inferred_endpoints": ["GET /items"],
      "confidence_map": { "layout_tree": "extracted", "inferred_states": "inferred", "inferred_entities": "inferred" } }
  ]
}
```

**每字段标 confidence**(`extracted` = 机械抽可信 / `inferred` = LLM 推断需人确认)。可逐字段标,也可用 `confidence_map`。

## Step 1.6: 抽取段验收

| 检查项 | 函数 |
|-------|-----|
| design-manifest.json 存在 + 含 extraction_meta + screens ≥1 | sg_app_data_contract(借用,MVP 后独立) |
| tokens.json 存在 + W3C DTCG 结构 + 每 token 有 confidence | sg_app_design_token_match(抽取侧) |
| 每屏有 baseline PNG 真文件 + DPR 已记 | sg_app_design_baseline_exists |
| 每字段有 confidence 标注 + degraded 时 reason 非空 | sg_app_design_baseline_exists |

初期全 `sg_run_soft`(advisory 不阻塞),与现有"建议优先"哲学一致。

---

# 段二:代码化(token → 各端)

> **被调用入口(build):** build 在实现 UI 时调本段,先把 token 出各端,再按 manifest 组装组件/屏。build 不重抽设计,只消费 manifest + tokens.json。
> **单跑入口:** 给定 tokens.json + manifest + 目标平台,产出各端 token 产物 + 组件骨架。

## Step 2.0–2.1: Style Dictionary 出各端

用 Style Dictionary 读 `tokens.json`(DTCG),按目标平台出产物:

| 平台 | 产物 | 引用方式 |
|------|------|---------|
| SwiftUI | `DesignTokens.swift`(`enum Color/Spacing`) | `Color.primary` / `Spacing.md` |
| Flutter | `design_tokens.dart`(`abstract class AppTokens`) | `AppTokens.primary` |
| Compose | `Tokens.kt`(`object`) | `Tokens.primary` |
| Tailwind | `tailwind.config.js` theme extend | `bg-primary` / `p-md` |

token 是**中间层**:设计改 token → 各端自动同步(机制消灭 drift,非纪律)。

## Step 2.2: 按 manifest 组装

- 对 `manifest.components[]`(reusable=true)→ 各端生成一个可复用组件,props/states 对齐
- 对 `manifest.screens[]` → 按 `layout_tree` 组装屏,引用已生成组件

## Step 2.3: 硬编码值反扫(铁律)

**实现处只引用 token,禁硬编码字面量。** 逐文件扫:

1. 颜色字面量(`#RRGGBB` / `Color(red:...)` / `rgb(...)`)出现在组件实现 → 阻塞,要求换 token 引用
2. 间距/圆角魔数(`16` / `12` 等裸数字用于 padding/radius)→ 阻塞,要求换 `Spacing.*` / `radius.*`
3. 字号/字体字面量 → 换 `type.*`
4. **唯一例外:** Style Dictionary 生成的 token 定义文件本身(它是字面量的合法归宿)
5. 不一致 → 阻塞,列出文件:行

由 `sg_app_design_token_match`(实现侧)机械验证:渲染态 computed value 必须能回溯到某 token。

---

# 段三:闭环 diff(截图 vs baseline)

> **被调用入口(qa / build):** qa 做视觉回归验收调本段;build 修复 UI 后调本段确认收敛。
> **单跑入口:** 给定已渲染 app + baseline + tokens.json,产出 diff 报告。

## Step 3.0: 渲染目标屏 → 截图

渲染实现的屏,**用 manifest.extraction_meta.dpr 同一 DPR + 同一视口**截图。截图落 `.claude/state/design-render/<platform>/<viewport>/<screen>.png`。

## Step 3.1: 屏蔽动态区(防误杀铁律)

纯像素 diff 误杀 30-40%。截图前/diff 前 **mask 掉动态区**:

- **动画区** — 任何带动画的节点(过渡中帧不稳)
- **mask 动态内容** — 头像(随机图)/ 时间戳 / 实时数据 / 随机占位
- 在 manifest 里给这类节点标 `dynamic:true`,diff 时按 mask 区域排除

固定 DPR + mask 动态区 = 把误杀压到可用区间。

## Step 3.2: 像素 diff + 结构 diff

```
pixelmatch(render.png, baseline.png) → diff_ratio (错配像素 / 总像素)
ssim(render.png, baseline.png)       → ssim_score (1=完全一致)
```
两个指标互补:pixelmatch 抓局部偏移,SSIM 抓结构/感知差异。

## Step 3.3: token 对账

渲染态的 computed style(实际渲染出的颜色/间距/字号)逐项对照 `tokens.json`:
- 渲染出的 primary 色 ≠ token primary → 记 `token_mismatch`
- 这一层抓"像素 diff 看不出但 token 错了"的情况(如近似色),是段二硬编码反扫的运行时复核

## Step 3.4: VLM 残差(语义级)

把 render + baseline 喂 VLM,问"哪里不像 + 严重度"。VLM 抓 pixelmatch/SSIM 抓不到的**语义错位**(图标错了 / 层级错了 / 文案截断),输出结构化残差清单。

## Step 3.5: 复用 build 修复循环 + 3 轮熔断

**停止判据 = 分数单调下降(变好)才继续修。**

```
轮 N:
  score_N = 加权(diff_ratio, 1-ssim, token_mismatch_count, vlm_severity)
  若 score_N < score_{N-1}(在变好)→ 继续修下一轮
  若 score_N >= score_{N-1}(没变好 / 变差)→ 立即停,上报"修不动了"
  最多 3 轮(复用 build 的修复循环机制),3 轮未收敛 → 熔断上报
```

**铁律:** 不为了"过 diff 阈值"无脑循环 —— 分数不单调降即停,把当前最优 + 残差清单上报人,不死循环(与 lockdown 的 fuse 软熔断同哲学)。

## Step 3.6: 写 design-diff-result.json

```json
{
  "screens": [
    { "screen": "home", "platform": "SwiftUI", "viewport": "iPhone-390x844",
      "rounds": [
        { "round": 1, "diff_ratio": 0.08, "ssim": 0.91, "token_mismatch": 2, "vlm_severity": "minor", "score": 0.42 },
        { "round": 2, "diff_ratio": 0.03, "ssim": 0.97, "token_mismatch": 0, "vlm_severity": "none", "score": 0.11 }
      ],
      "converged": true, "stop_reason": "monotonic_improving_then_passed",
      "residual": [] }
  ],
  "halted": [],
  "result": "PASS"
}
```

`stop_reason` 合法值:`converged` / `score_not_monotonic`(没变好停) / `fuse_3_rounds`(熔断)。

## 闭环段验收

| 检查项 | 函数 |
|-------|-----|
| 每屏有 render PNG + 跑了 pixelmatch + SSIM | sg_app_ui_visual_diff |
| 动态区已 mask(manifest dynamic 标注被 diff 消费) | sg_app_ui_visual_diff |
| token 对账跑过 + 渲染态可回溯 token | sg_app_design_token_match |
| 修复循环 ≤3 轮 + 每轮有 score + stop_reason 合法 | sg_app_ui_visual_diff |
| design-diff-result.json 存在 + result 字段 | sg_app_ui_visual_diff |

初期全 `sg_run_soft`(advisory)。

---

## Step 4: 写信号

```bash
mkdir -p .claude/state
echo "{\"skill\":\"design-restore\",\"epoch\":$(date +%s)}" > .claude/state/skill-signal.json
```

被脊柱关调用时:把控制权交回调用方(shape/build/qa),不自行推进 CURRENT_GATE。
单跑时:不动 hook 状态机(本 skill 不进路由),只产出机读产物。

---

## OUTPUT_GATE(产物校验)

| 检查项 | 函数 | 段 |
|-------|-----|----|
| design-manifest.json 存在 + extraction_meta + screens≥1 + 每字段 confidence | sg_app_data_contract | 一 |
| tokens.json 存在 + DTCG 结构 + theme + 每 token confidence | sg_app_design_token_match | 一 |
| 每屏 baseline PNG 真文件 + DPR 记录 + degraded 时 reason 非空 | sg_app_design_baseline_exists | 一 |
| 各端 token 产物生成 + 实现处无硬编码字面量(token 定义文件除外) | sg_app_design_token_match | 二 |
| 每屏跑过 pixelmatch + SSIM + 动态区 mask | sg_app_ui_visual_diff | 三 |
| 渲染态 computed value 可回溯 token | sg_app_design_token_match | 三 |
| 修复循环 ≤3 轮 + 停止判据=分数单调降 + stop_reason 合法 | sg_app_ui_visual_diff | 三 |
| design-diff-result.json 存在 + result + halted 项有残差上报 | sg_app_ui_visual_diff | 三 |

闸门函数初期全 `sg_run_soft=advisory`(不阻塞,与现有"建议优先"哲学一致)。任一软失败 → 列缺失项 + 当前最优上报,不死循环。

---

## 完成后下一步

单跑:

`完成: /design-restore 已产出 design-manifest.json + tokens.json + baseline + 各端 token + diff 报告(result=PASS),设计已高保真还原`

被脊柱关调用:

`完成: design-restore 【段X】产物已落 docs/design/,控制权交回 /<调用方>`

熔断 / 降级:

`停住: 段三 diff 在 home 屏 3 轮未收敛(分数非单调降),已上报当前最优 + 残差清单,需人介入`

`降级: .pen 不可达(WebSocket not connected),已退到导出 PNG 走截图档,manifest 标 actual_source=screenshot + 低置信度,继续`
