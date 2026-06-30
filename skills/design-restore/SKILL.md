---
name: design-restore
description: "把设计稿(.pen / Figma / 截图)还原成高保真 app 前端 —— 三段式:①抽取(三管线归一成 design-manifest.json + tokens.json + baseline PNG,每字段标 extracted/inferred)②代码化(Style Dictionary 把 DTCG token 出各端,实现只引用 token)③闭环 diff(渲染截图 vs baseline 跑 pixelmatch/SSIM + token 对账 + codex-image-bridge VLM 残差,3 轮熔断,停止判据=分数单调降)。真 app 跑时必须用 Workflow 编排(按屏×视口扇出 + 每屏 loop-until-converge),线性 Step 仅作单 agent 降级档。经 shape 调抽取段、build/qa 调渲染+diff 段,不进路由、不进 hook 状态机。"
---

# /design-restore — 设计 → 高保真 app(真 skill,非脊柱关)

> 🔗 **App Factory 集成 — reify≠create**:本 skill 只做**还原(reify)**,不做**创造(create)**。视觉方向 / 设计系统的"从无到有"由 `frontend-design` 负责;本 skill 拿到既有设计稿后**忠实还原**。两者职责不重叠:有设计稿走 design-restore,无设计稿(只有需求)走 frontend-design。
>
> 🔗 **调用关系**:本 skill 可单跑,也被脊柱关内部调用 —
> - **shape** 调本 skill 的【段一:抽取】把设计稿固化成 design-manifest.json,作为 spec.md「视觉方向」的机读真相源
> - **build** 调本 skill 的【段二:代码化 + 段三:diff】把 token 出各端 + 渲染后跟 baseline 对账
> - **qa** 调本 skill 的【段三:闭环 diff】做视觉回归验收
> 每段内部都有「单跑 / 被调用」两种入口说明,见各段开头。

**作用:** 导入设计稿(.pen / Figma / 截图任一),产出**能上线生产**的高保真前端 —— 三段式流水线:抽取(归一化成 FROZEN 机读产物)→ 代码化(token 中间层,实现只引用 token)→ 闭环 diff(渲染截图 vs baseline 量化对账,分数不单调下降即停上报)。

> ⚠️ **真 app 跑时不走线性 Step,改用 Workflow 编排:**
> ```bash
> # AI 调用 Workflow 工具(Claude Code 内置·非 shell CLI),script 取以下文件内容: /Users/xmasdong/opc/app-factory/scripts/design-first/design-restore.workflow.js
> ```
> 线性 Step(下方段一~段三)仅作**单 agent 降级档**(无 Workflow runtime 时手跑)。见末尾【## 用 ultracode 编排执行(强制)】。

---

**INPUT_CONTRACT:**
- 至少一种设计源可达(三选一,优先级从高到低):
  - `source=pen` — `.pen` 文件路径 + pencil MCP 桌面 app 在跑(`get_editor_state` 不报 WebSocket not connected)
  - `source=figma` — Figma file key + REST token(env `FIGMA_TOKEN`)
  - `source=screenshot` — 一张或多张 PNG 截图(用户多用 codex-image mockup,**截图是一等输入**)
- 目标平台已知:`<platform> ∈ {SwiftUI, Flutter, Compose, Tailwind}`(可多选)
- 目标视口已知:`<viewport>`(如 iPhone-390x844 / Android-360x800 / web-1440x900)
- **被调用模式**额外要求:调用方传入 `docs/design/` 目标目录 + 当前所处段(extract / codegen / diff)
- **Workflow 模式**额外要求:`CLAUDE_PROJECT_DIR` 已 export 指向目标项目根(否则 ROOT 落到 cwd,state JSON 写错位置闸门读不到)

**CONTRACT 不满足时:**
- 三种源全不可达 → 拒绝执行,提示至少给一张截图
- `source=pen` 但 `get_editor_state` 报 WebSocket not connected → **走降级链**(见段一),不硬失败:退到 .pen 导出的 PNG 走截图档,manifest 如实标低置信度
- 目标平台不在 4 个合法值内 → 提示 Style Dictionary 暂不支持该端
- `CLAUDE_PROJECT_DIR` 未设 → Workflow 退化用 `process.cwd()`,提示用户确认 cwd 是项目根

**OUTPUT(机读产物 + 闸门 state):**
- 桥产物:`docs/design/design-manifest.json` + `docs/design/tokens.json` + `docs/design/baseline/<platform>/<viewport>/<screen>.png` 系列 + 各端 token 文件
- **闸门 state(Workflow 的 Synthesis critic 唯一写入点,key 严格对齐 `app-gate.sh`):**
  - `.claude/state/ui-diff.json` → `{ "mismatch": <int 0-100>, "per_screen": [{screen, mismatch}] }`
  - `.claude/state/token-match.json` → `{ "hardcoded_count": <int>, "mismatched_count": <int>, "details": [...] }`
- `skill-signal.json`

桥产物路径 + schema 固定(下游只认机读产物,不直接解析原始 .pen/Figma),参照锁定契约「桥产物」节。

---

## 闸门 state 契约(STATE_CONTRACT — 逐字对齐 app-gate.sh,写错即整关失效)

| state JSON | key(严格) | 闸门判据(`sg_app_*`) |
|------------|-----------|----------------------|
| `.claude/state/ui-diff.json` | `mismatch:<int 0-100>`(取所有屏 `per_screen[].mismatch` 最大值)+ `per_screen:[{screen,mismatch}]` | `mismatch ≤3` pass / `3-8` WARN / `>8` FAIL |
| `.claude/state/token-match.json` | `hardcoded_count:<int>` + `mismatched_count:<int>` + `details:[{file,line,value,reason}]` | `hardcoded_count>0` 或 `mismatched_count>0` 即 FAIL |

- `mismatch` = 最后一轮 `diff_ratio*100` 取整。**顶层 key 是 `.mismatch`**(不是 `max_mismatch`,虽然 gate 有 fallback),`per_screen[].mismatch` 是 int。
- `hardcoded_count` = 实现处硬编码字面量数;`mismatched_count` = 渲染态 computed value 回溯不到 token 的数。
- 手验 key 对齐:
  ```bash
  jq '.mismatch, (.per_screen|length)' .claude/state/ui-diff.json
  jq '.hardcoded_count, .mismatched_count' .claude/state/token-match.json
  bash /Users/xmasdong/opc/app-factory/scripts/app-gate.sh build   # 读 ui-diff/token-match 验收
  ```

---

## 执行计划

> **真 app:跑 Workflow(下方第一行命令)。** 以下线性 Step = 降级档(单 agent 手跑)。

```
真 app(默认):
  $ # AI 调用 Workflow 工具(Claude Code 内置·非 shell CLI),script 取以下文件内容: \
      /Users/xmasdong/opc/app-factory/scripts/design-first/design-restore.workflow.js

降级档(无 Workflow runtime 时单 agent 顺序跑):
段一:抽取(归一化)
- [ ] Step 1.0: 探源 + 选管线 + 降级链判定
- [ ] Step 1.1: 抽 token(最确定先抽)→ 落 tokens.json (W3C DTCG)
- [ ] Step 1.2: 抽屏清单 + 组件清单
- [ ] Step 1.3: 逐屏抽布局树 + text + nav + 推断态/字段/实体/端点
- [ ] Step 1.4: 导 baseline PNG(每屏每视口)
- [ ] Step 1.5: 写 design-manifest.json,每字段标 extracted/inferred
- [ ] Step 1.6: 抽取段验收

段二:代码化(token → 各端)
- [ ] Step 2.0: Style Dictionary 读 tokens.json
- [ ] Step 2.1: build 出各端 token 产物(SwiftUI/Flutter/Compose/Tailwind)
- [ ] Step 2.2: 按 manifest.components 生成组件 + 按 screens 组装屏
- [ ] Step 2.3: 硬编码值反扫(实现处只引用 token,禁字面量)

段三:闭环 diff(渲染截图 vs baseline)
- [ ] Step 3.0: 渲染目标屏 → 截图(固定 DPR / 视口)
- [ ] Step 3.1: 屏蔽动态区(动画 / 头像 / 时间)防误杀
- [ ] Step 3.2: 像素 diff(pixelmatch)+ 结构 diff(SSIM)
- [ ] Step 3.3: token 对账(渲染态 computed style vs tokens.json)
- [ ] Step 3.4: VLM 残差(codex-image-bridge 语义级"哪里不像")
- [ ] Step 3.5: 局部重生修复循环,3 轮熔断,停止判据=分数单调降
- [ ] Step 3.6: critic 写 ui-diff.json + token-match.json + 闭环段验收
- [ ] Step 4: 写信号
```

---

# 段一:抽取(归一化)

> **单跑入口:** 用户给设计源 → 本段产出三件 FROZEN 机读产物。
> **被调用入口(shape):** shape 在「视觉方向」步调本段,把设计稿固化成 design-manifest.json,后续 spec 的 components/screens 直接引用其字段。shape 只读 manifest,不重抽。
> **Workflow 对应:** `phase('Extract')` 单 agent —— 这是扇出前唯一输入,产 `screens[] + dpr`。

## Step 1.0: 探源 + 选管线 + 降级链(真命令)

```
mcp__pencil__get_editor_state()    # 仅 source=pen;返回 WebSocket not connected → 触发降级
```

| 源 | 真工具/命令 | 降级链 |
|----|------------|--------|
| `pen` | pencil MCP(`get_editor_state` → `get_variables` → `batch_get` → `export_nodes`) | MCP 不可达 → `export_nodes` 退不了 → 用 .pen 旁已导出 PNG → 走 screenshot 档,manifest 标 `actual_source:"screenshot"` + 全字段 confidence 降级 |
| `figma` | `curl -H "X-Figma-Token: $FIGMA_TOKEN" https://api.figma.com/v1/files/<key>` + `/v1/images` | token 失效 / 429 限流 → 退已导出 PNG → 走 screenshot 档 |
| `screenshot` | codex-image-bridge VLM 视觉抽取 | 无降级(已是最底档);截图模糊 → 标 `inferred` 并记 `low_confidence_reason` |

**降级铁律:** 任何降级**不静默** —— manifest 顶部 `extraction_meta` 必须记 `requested_source` / `actual_source` / `degraded:true/false` / `reason`。下游据此知道置信度天花板。
→ **产出:** `extraction_meta`(进 design-manifest.json),Workflow 里是 `extract` agent 返回对象的一部分。

## Step 1.1: 抽 token(最确定先抽 → tokens.json)

**为什么先抽 token:** token 是设计稿里**最机械、最可信**的部分(变量表 / 颜色 / 间距),先固化它,后面布局抽取的不确定性不污染 token。

### pen 管线(pencil MCP 确切调用序列)
```
mcp__pencil__get_variables()                          # 直接拿设计变量,最确定,优先全抽
mcp__pencil__search_all_unique_properties()           # 补:扫散落在节点上的颜色/间距字面量(无变量化的)
mcp__pencil__get_guidelines(category:"tokens")        # 拿 .pen 的 token 命名规范,映射时对齐
```
把 pencil 变量映射到 W3C DTCG 结构。

### figma 管线
```
curl -H "X-Figma-Token: $FIGMA_TOKEN" \
  "https://api.figma.com/v1/files/<key>/variables/local"   # Variables REST(需 Enterprise)
curl ... "https://api.figma.com/v1/files/<key>/styles"      # 退档:无 Variables 时读 styles
```
映射到 DTCG。

### screenshot 管线
codex-image-bridge VLM 抽主色板 / 字号阶梯 / 圆角 / 间距,**全部标 `inferred`**(像素量出来的不是设计意图)。

### 落 `tokens.json`(W3C DTCG)+ Style Dictionary 校验
```json
{
  "$schema": "https://design-tokens.github.io/community-group/format/",
  "color":  { "primary": { "$value": "#3B82F6", "$type": "color", "$extensions": { "confidence": "extracted" } } },
  "space":  { "md": { "$value": "16", "$type": "dimension", "$extensions": { "confidence": "extracted" } } },
  "radius": { "card": { "$value": "12", "$type": "dimension" } },
  "type":   { "body": { "$value": { "fontFamily": "Inter", "fontSize": "16", "lineHeight": "1.5" }, "$type": "typography" } },
  "theme":  ["light", "dark"]
}
```
每个 token 的 `$extensions.confidence` 标 `extracted` | `inferred`。落盘后立刻验 DTCG 合法:
```bash
npx style-dictionary build --config sd.config.json --dry-run   # 解析失败=DTCG 结构错,当场修
```
→ **产出:** `docs/design/tokens.json`(Workflow `extract` agent 写)。

## Step 1.2: 抽屏清单 + 组件清单

### pen 管线
```
mcp__pencil__batch_get(patterns: [{ type: "frame" }])      # 屏清单
mcp__pencil__batch_get(patterns: [{ reusable: true }])     # 可复用组件清单
```

### figma 管线
顶层 `CANVAS` → 子 `FRAME` = 屏;`COMPONENT` / `COMPONENT_SET` = 可复用组件(走 `/v1/files/<key>` 节点树)。

### screenshot 管线
一张截图 = 一屏;组件由 codex-image-bridge VLM 切分推断,标 `inferred`。

## Step 1.3: 逐屏抽布局树 + text + 推断

### pen 管线(确切序列)
```
# 逐屏:
mcp__pencil__batch_get(nodeIds: [frameId], readDepth: 3, resolveInstances: true)   # 布局树 + text,readDepth≤3 控规模
mcp__pencil__snapshot_layout(problemsOnly: true)                                   # 拿布局问题(重叠/越界)
```

### 每屏抽这些字段(对应 manifest.screens[]):
| 字段 | 来源 | confidence |
|------|------|-----------|
| `layout_tree` | 抽取(布局树) | extracted |
| `texts[]` | 抽取(文本节点) | extracted |
| `nav_to[]` | 抽取(链接/跳转)或 LLM 推断 | extracted / inferred |
| `dynamic` | 标动态节点(动画/头像/时间)供段三 mask | extracted |
| `inferred_states[]` | LLM 推断(empty/loading/error/...) | **inferred** |
| `fields[]` | LLM 从表单/输入推断 | **inferred** |
| `inferred_entities[]` | LLM 从屏内容推断业务实体 | **inferred** |
| `inferred_endpoints[]` | LLM 从实体派生后端端点草稿 | **inferred** |

**reify≠create 红线:** 抽取段只**记录看到的 + 标注推断的**,不发明 UI。`inferred_*` 字段全部是**草稿**,需人确认(与 backend-forge 的 inferred 一致姿态);下游 shape/backend-forge 拿来当起点,不当定论。

## Step 1.4: 导 baseline PNG(真命令)

### pen 管线
```
mcp__pencil__export_nodes(nodeIds: [...], format: "png", scale: <DPR>)    # 每屏导 baseline,scale=manifest DPR
```
按 `docs/design/baseline/<platform>/<viewport>/<screen>.png` 落盘。

### figma 管线
```
curl -H "X-Figma-Token: $FIGMA_TOKEN" \
  "https://api.figma.com/v1/images/<key>?ids=<nodeId>&format=png&scale=<DPR>"   # 返回 S3 URL 再 curl 下载
```

### screenshot 管线
原始截图**即** baseline(本来就是图),`cp` 到 baseline 路径并记 `baseline_is_source:true`。

**DPR 固定铁律:** baseline 导出 DPR 必须记进 `extraction_meta.dpr`,段三渲染截图用**同一 DPR**(纯像素 diff 误杀 30-40% 的头号原因是 DPR 不一致)。
→ **产出:** `docs/design/baseline/<platform>/<viewport>/<screen>.png` 系列。

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
      "dynamic": ["avatar","clock"],
      "inferred_states": ["empty","loading","error"], "fields": [],
      "inferred_entities": ["Item"], "inferred_endpoints": ["GET /items"],
      "confidence_map": { "layout_tree": "extracted", "inferred_states": "inferred", "inferred_entities": "inferred" } }
  ]
}
```

**每字段标 confidence**(`extracted` = 机械抽可信 / `inferred` = LLM 推断需人确认)。可逐字段标,也可用 `confidence_map`。
→ **产出:** `docs/design/design-manifest.json`(Workflow `extract` agent 写,返回 `screens[] + dpr`)。

## Step 1.6: 抽取段验收

| 检查项 | 命令/函数 |
|-------|-----------|
| design-manifest.json 存在 + 含 extraction_meta + screens ≥1 | `jq '.extraction_meta, (.screens\|length)' docs/design/design-manifest.json` |
| tokens.json 存在 + W3C DTCG 结构 + 每 token 有 confidence | `npx style-dictionary build --dry-run`(解析过=结构合法) |
| 每屏有 baseline PNG 真文件 + DPR 已记 | `ls docs/design/baseline/**/*.png && jq '.extraction_meta.dpr' ...` |
| 每字段有 confidence 标注 + degraded 时 reason 非空 | `sg_app_design_baseline_exists`(app-gate.sh) |

初期全 `sg_run_soft`(advisory 不阻塞),与现有"建议优先"哲学一致。

---

# 段二:代码化(token → 各端)

> **被调用入口(build):** build 在实现 UI 时调本段,先把 token 出各端,再按 manifest 组装组件/屏。build 不重抽设计,只消费 manifest + tokens.json。
> **单跑入口:** 给定 tokens.json + manifest + 目标平台,产出各端 token 产物 + 组件骨架。
> **Workflow 对应:** 此段在 `Per-Screen` worker 的"局部重生"子步内被各屏消费;token 出各端是 worker 渲染前的前置。

## Step 2.0–2.1: Style Dictionary 出各端(真命令)

```bash
# sd.config.json 指 source=["docs/design/tokens.json"],platforms 各端各一
npx style-dictionary build --config sd.config.json
```

| 平台 | 产物 | 引用方式 |
|------|------|---------|
| SwiftUI | `DesignTokens.swift`(`enum Color/Spacing`) | `Color.primary` / `Spacing.md` |
| Flutter | `design_tokens.dart`(`abstract class AppTokens`) | `AppTokens.primary` |
| Compose | `Tokens.kt`(`object`) | `Tokens.primary` |
| Tailwind | `tailwind.config.js` theme extend | `bg-primary` / `p-md` |

token 是**中间层**:设计改 token → `style-dictionary build` 重跑 → 各端自动同步(机制消灭 drift,非纪律)。

## Step 2.2: 按 manifest 组装

- 对 `manifest.components[]`(reusable=true)→ 各端生成一个可复用组件,props/states 对齐
- 对 `manifest.screens[]` → 按 `layout_tree` 组装屏,引用已生成组件

## Step 2.3: 硬编码值反扫(铁律 → 喂 token-match.json)

**实现处只引用 token,禁硬编码字面量。** 逐文件扫,命中即计入 `token-match.json.hardcoded_count`:

```bash
# 颜色字面量(组件实现处,token 定义文件除外):
grep -rnE '#[0-9a-fA-F]{6}|Color\(red:|rgb\(' src/ --include='*.swift' --include='*.dart' \
  | grep -v DesignTokens
# 间距/圆角魔数 + 字号字面量同理逐类扫
```
1. 颜色字面量(`#RRGGBB` / `Color(red:...)` / `rgb(...)`)在组件实现 → 阻塞,换 token 引用
2. 间距/圆角魔数(裸数字用于 padding/radius)→ 换 `Spacing.*` / `radius.*`
3. 字号/字体字面量 → 换 `type.*`
4. **唯一例外:** Style Dictionary 生成的 token 定义文件本身(字面量的合法归宿)
5. 命中数 → `hardcoded_count`,明细 → `details:[{file,line,value,reason}]`

由段三 token 对账(运行时复核)+ 本步(静态扫)双层验证。→ **产出贡献:** `.claude/state/token-match.json` 的 `hardcoded_count` + `details`。

---

# 段三:闭环 diff(渲染截图 vs baseline)

> **被调用入口(qa / build):** qa 做视觉回归验收调本段;build 修复 UI 后调本段确认收敛。
> **单跑入口:** 给定已渲染 app + baseline + tokens.json,产出 diff 报告。
> **Workflow 对应:** `phase('Per-Screen')` 每个 (屏×视口) worker 内部就是本段 3.0~3.5 的 **loop-until-converge**;`phase('Synthesis')` critic 干 3.6。

## Step 3.0: 渲染目标屏 → 截图(真命令,固定 DPR)

```bash
# 用 manifest.extraction_meta.dpr 同一 DPR + 同一视口:
npx playwright screenshot --device="iPhone 13" --scale-factor=<DPR> <url> \
  .claude/state/design-render/<platform>/<viewport>/<screen>.png
# 原生端:SwiftUI 用 XCUITest snapshot / Flutter 用 integration_test screenshot,同 DPR
```

## Step 3.1: 屏蔽动态区(防误杀铁律)

纯像素 diff 误杀 30-40%。diff 前 **mask 掉 `manifest.screens[].dynamic` 标注的节点**:
- **动画区** — 任何带动画的节点(过渡中帧不稳)
- **mask 动态内容** — 头像(随机图)/ 时间戳 / 实时数据 / 随机占位
- mask 实现:diff 前把 render+baseline 同坐标矩形涂同色(pngjs 改像素),再喂 pixelmatch

## Step 3.2: 像素 diff + 结构 diff(真命令)

```bash
npx pixelmatch render.png baseline.png diff.png 0.1   # 退出码=错配像素数;diff_ratio=错配/总像素
node -e "const ssim=require('image-ssim'); /* render vs baseline → ssim_score */"   # 或 ssim.js / odiff
```
两个指标互补:pixelmatch 抓局部偏移,SSIM 抓结构/感知差异。

## Step 3.3: token 对账(运行时复核)

渲染态的 computed style(实际渲染出的颜色/间距/字号)逐项对照 `tokens.json`:
- 渲染出的 primary 色 ≠ token primary → 记 `mismatched_count++`,明细进 `details`
- 抓"像素 diff 看不出但 token 错了"的情况(如近似色),是段二硬编码反扫的运行时复核
→ **产出贡献:** `.claude/state/token-match.json` 的 `mismatched_count`。

## Step 3.4: VLM 残差(codex-image-bridge 语义级)

```bash
# 把 render + baseline 喂 codex-image-bridge VLM,问"哪里不像 + 严重度":
codex-image-bridge compare --a render.png --b baseline.png \
  --prompt "列出 render 相对 baseline 的语义错位(图标错/层级错/文案截断)+ severity(none/minor/major)"
```
VLM 抓 pixelmatch/SSIM 抓不到的**语义错位**,输出结构化残差清单 → `vlm_severity`。

## Step 3.5: 局部重生修复循环 + 3 轮熔断(loop-until-converge)

**停止判据 = 分数单调下降(变好)才继续修。** 这是 Workflow `Per-Screen` worker 内的 `for` 循环:

```
轮 N:
  渲染→mask→pixelmatch+SSIM→token 对账→VLM 定位残差→局部重生修最差区
  score_N = 加权(diff_ratio, 1-ssim, token_mismatch_count, vlm_severity)
  若 score_N >= score_{N-1}(没变好 / 变差)→ 立即停,stop_reason='score_not_monotonic'
  若 diff_ratio*100 ≤ 3 且 token_mismatch == 0       → 停,stop_reason='converged'
  最多 K=3 轮,到顶                                    → 停,stop_reason='fuse_3_rounds'
```

**铁律:** 不为了"过 diff 阈值"无脑循环 —— 分数不单调降即停(会烧 token 且可能越改越坏),把当前最优 + 残差清单上报人(与 lockdown 的 fuse 软熔断同哲学)。

## Step 3.6: critic 写闸门 state(唯一写入点)

Workflow `phase('Synthesis')` 单 critic agent 核覆盖后写两份 state(**只此一处写,保 key 严格对齐**):

```json
// .claude/state/ui-diff.json
{ "mismatch": 3, "per_screen": [ { "screen": "home", "mismatch": 3 }, { "screen": "detail", "mismatch": 2 } ] }
```
```json
// .claude/state/token-match.json
{ "hardcoded_count": 0, "mismatched_count": 0, "details": [] }
```
- `mismatch` = 所有 `per_screen[].mismatch` 取最大(= 最差屏最后一轮 `diff_ratio*100` 取整)。
- critic 还核:每 (屏×视口) 都跑了 pixelmatch+SSIM+token 对账?动态区都 mask?有屏 `stop_reason≠converged` → 进 `halted` 上报。

## 闭环段验收

| 检查项 | 命令/函数 |
|-------|-----------|
| 每屏有 render PNG + 跑了 pixelmatch + SSIM | `sg_app_ui_visual_diff` |
| 动态区已 mask(manifest dynamic 标注被 diff 消费) | `sg_app_ui_visual_diff` |
| token 对账跑过 + 渲染态可回溯 token | `sg_app_design_token_match` |
| 修复循环 ≤3 轮 + 每轮有 score + stop_reason 合法 | `sg_app_ui_visual_diff` |
| ui-diff.json + token-match.json 存在 + key 对齐 | `jq '.mismatch' .claude/state/ui-diff.json && jq '.hardcoded_count' .claude/state/token-match.json` |

初期全 `sg_run_soft`(advisory)。

---

## 用 ultracode 编排执行(强制)

> ⚠️ **"用 ultracode"到底怎么操作**:Workflow/ultracode 是 **Claude Code 会话内的【工具】**,由 **AI(你)调用**(给它传 `script` 参数)——**不存在 `claude workflow` 这种 shell 命令**。所以"执行本 skill"=你调用 **Workflow 工具**,`script` = `scripts/design-first/design-restore.workflow.js` 的内容(先 Read 它再传)。脚本里的 agent 用 **Bash 调本仓 `scripts/design-first/` 的确定性脚本**(`visual-diff.mjs` / `token-match.mjs`)产出闸门读取的 state JSON——这些脚本是唯一可信的 state 产出口,不要让 agent 手写 JSON。

> **真 app 跑时,本 skill 必须用 Workflow 工具编排,不是单 agent 顺序硬写。** 单 agent 顺序跑只是降级档。

**为什么必须编排:** 一个 app 有 N 屏 × M 视口,顺序还原既慢又无并行覆盖;且每屏要 loop-until-converge(渲染→diff→定位→局部重生,分数单调降才继续),单 agent 没法既扇出又对每屏独立熔断。Workflow 把四质量模式落地:

- **fan-out 全覆盖** = `parallel(screen × viewport 笛卡尔积)`,每组合一个 worker,一屏不漏。
- **loop-until-converge** = screen worker 内 `for` + 分数单调降判据 + K=3 轮熔断。
- **completeness critic** = `phase('Synthesis')` 单 agent 核覆盖(每屏每视口是否都跑了 pixelmatch+SSIM+token 对账、动态区是否都 mask、是否有屏未收敛漏报),**唯一写 state JSON 的点**,保证 key 严格对齐 `app-gate.sh`。

**跑法(在目标项目根):**
```bash
# AI 调用 Workflow 工具(Claude Code 内置·非 shell CLI),script 取以下文件内容: \
  /Users/xmasdong/opc/app-factory/scripts/design-first/design-restore.workflow.js
```

**Workflow 脚本模板(已落盘 `scripts/design-first/design-restore.workflow.js`,此处内嵌全文,改了同步)**

```js
export const meta = {
  name: 'design-restore-orchestrated',
  description: '抽 manifest → 按屏×视口并行还原(loop-until-converge:渲染→diff→定位→局部重生,单调降才继续)→ 汇总产 ui-diff.json/token-match.json',
  phases: [
    { title: 'Extract',    detail: 'single agent — 三管线归一 → design-manifest.json + tokens.json + baseline PNG' },
    { title: 'Per-Screen', detail: 'parallel × (screen×viewport) — 每屏 loop-until-converge,最多 k 轮' },
    { title: 'Synthesis',  detail: 'completeness critic — 写 ui-diff.json/token-match.json' },
  ],
}

const ROOT = process.env.CLAUDE_PROJECT_DIR || process.cwd()
const K_ROUNDS = 3
const VIEWPORTS = ['iPhone-390x844', 'Android-360x800']
const PLATFORM = 'SwiftUI'

// ── phase 1: 抽取 manifest(扇出前唯一输入,FROZEN)──
phase('Extract')
const extract = await agent(
  `三管线(pen/figma/screenshot)归一,reify≠create:只记录看到的 + 标注推断,不发明 UI。
   降级链:source=pen 且 get_editor_state 报 WebSocket not connected → 退 .pen 导出 PNG 走 screenshot 档,
   extraction_meta 记 requested_source/actual_source/degraded/reason(降级不静默)。
   先抽 token(最确定)→ ${ROOT}/docs/design/tokens.json(W3C DTCG,每 token $extensions.confidence=extracted|inferred)。
   抽屏清单+组件+逐屏布局树,inferred_* 字段标注为草稿。动态区(动画/头像/时间戳)标 dynamic:true。
   导 baseline PNG 到 ${ROOT}/docs/design/baseline/<platform>/<viewport>/<screen>.png(DPR 记进 extraction_meta.dpr)。
   写 ${ROOT}/docs/design/design-manifest.json。返回 screens[] + dpr。`,
  { label: 'extract', phase: 'Extract', schema: {
      type: 'object', required: ['screens', 'dpr'],
      properties: { screens: { type: 'array', items: { type: 'string' } }, dpr: { type: 'number' } } } }
)

// ── phase 2: 按屏 × 视口扇出,每 worker 内 loop-until-converge ──(fan-out + loop)
phase('Per-Screen')
const combos = extract.screens.flatMap(s => VIEWPORTS.map(v => ({ screen: s, viewport: v })))
const perScreen = await parallel(combos.map(({ screen, viewport }) => async () => {
  const rounds = []
  let prevScore = Infinity, stop = 'fuse_3_rounds'
  for (let r = 1; r <= K_ROUNDS; r++) {
    const round = await agent(
      `屏=${screen} 视口=${viewport} 第 ${r} 轮。用 dpr=${extract.dpr} 同一 DPR 渲染→截图(playwright/各端截图)。
       mask 动态区(manifest dynamic:true 节点:动画/头像/时间),否则纯像素 diff 误杀 30-40%。
       npx pixelmatch render.png baseline.png diff.png 0.1 → diff_ratio;SSIM → ssim。
       token 对账:渲染态 computed style vs tokens.json,回溯不到 token 的计 token_mismatch。
       codex-image-bridge VLM 定位语义残差(图标错/层级错/文案截断)→ vlm_severity。
       局部重生只修最差区。返回 diff_ratio/ssim/token_mismatch/vlm_severity/score(加权)。`,
      { label: `${screen}@${viewport}#${r}`, phase: 'Per-Screen', schema: {
          type: 'object', required: ['score', 'diff_ratio', 'ssim', 'token_mismatch'],
          properties: {
            diff_ratio: { type: 'number' }, ssim: { type: 'number' },
            token_mismatch: { type: 'integer' }, vlm_severity: { enum: ['none', 'minor', 'major'] },
            score: { type: 'number' } } } }
    ).catch(e => ({ score: prevScore, diff_ratio: 1, ssim: 0, token_mismatch: 99, vlm_severity: 'major', _err: String(e) }))
    rounds.push({ round: r, ...round })
    // loop-until-converge:分数单调降才继续,不降即停(不为压阈值死磕)
    if (round.score >= prevScore) { stop = 'score_not_monotonic'; break }
    prevScore = round.score
    if (round.diff_ratio * 100 <= 3 && round.token_mismatch === 0) { stop = 'converged'; break }
  }
  const last = rounds[rounds.length - 1]
  return { screen, viewport, platform: PLATFORM, rounds, stop_reason: stop,
           mismatch: Math.round((last.diff_ratio || 0) * 100), token_mismatch: last.token_mismatch || 0,
           converged: stop === 'converged' }
}).map(p => p.catch(e => ({ screen: '?', viewport: '?', platform: PLATFORM, rounds: [],
    stop_reason: 'fuse_3_rounds', mismatch: 100, token_mismatch: 99, converged: false }))))

// ── phase 3: completeness critic + 写闸门 JSON(唯一写 state 的点,保 key 严格对齐 app-gate.sh)──
phase('Synthesis')
const synth = await agent(
  `完整性审查 + 写闸门 state(严格按 key,写错即整关失效)。输入 perScreen=${JSON.stringify(perScreen)}。
   核对:每 (屏×视口) 都跑了 pixelmatch+SSIM+token 对账?动态区都 mask?有屏未收敛(stop_reason≠converged)需上报?
   写 ${ROOT}/.claude/state/ui-diff.json = {mismatch:<int 0-100,取所有 per_screen.mismatch 最大值>, per_screen:[{screen,mismatch}]}
   写 ${ROOT}/.claude/state/token-match.json = {hardcoded_count:<int 实现处硬编码字面量数,>0 即 FAIL>, mismatched_count:<int sum token_mismatch,>0 即 FAIL>, details:[{file,line,value,reason}]}
   返回写入摘要 + halted(未收敛屏)。`,
  { label: 'critic', phase: 'Synthesis', schema: {
      type: 'object', required: ['ui_diff', 'token_match', 'halted'],
      properties: { ui_diff: { type: 'object' }, token_match: { type: 'object' },
        halted: { type: 'array', items: { type: 'string' } } } } }
)

return { extract, perScreen, synth }
```

**编排坑(必读):**
- **DPR 不一致是误杀头号原因**:`extract` 必须把 baseline 导出 DPR 写进 `extraction_meta.dpr`,每个 screen worker 渲染用同一 DPR。动态区 diff 前必须 mask,否则假阳性爆表。
- **每个 parallel worker 必须 `.catch` 兜底成符合 schema 的 fallback 对象**(见脚本 worker 末尾 `.map(p=>p.catch(...))`),否则一屏崩了整个 parallel reject、其它已完成屏全丢。
- **停止判据是"分数单调降才继续",不是"过阈值才停"**:`score_N >= score_{N-1}` 立即停报 `score_not_monotonic`,不要为压 `mismatch≤3` 无脑死磕(烧 token + 可能越改越坏)。K=3 硬熔断。
- **critic 是唯一写 state 的点**:`ui-diff.json` 顶层 key 是 `.mismatch`(int)、`per_screen[].mismatch` 是 int;`token-match.json` 是 `hardcoded_count`/`mismatched_count`(>0 即 FAIL)。别在别处分散写 state。
- **`CLAUDE_PROJECT_DIR` 必须 export**:脚本随 app-factory 仓库分发,但跑时在各业务项目根跑;不 export → `ROOT` 落到 cwd,state 写错位置闸门读不到。

**降级链(无 Workflow runtime / .pen 不可达):**
1. 无 `Workflow 工具` 可用 → 退线性段一~段三,单 agent 顺序跑,手写两份 state JSON(key 仍严格对齐)。
2. `.pen` 不可达(WebSocket not connected)→ `export_nodes` 退 .pen 旁 PNG → 走 screenshot 档,`extraction_meta.actual_source="screenshot"` + degraded:true + 全字段低置信度。

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
| **ui-diff.json 顶层 .mismatch int + per_screen[]** | sg_app_ui_visual_diff | 三 |
| **token-match.json hardcoded_count + mismatched_count(>0 即 FAIL)** | sg_app_design_token_match | 三 |

闸门函数初期全 `sg_run_soft=advisory`(不阻塞,与现有"建议优先"哲学一致)。任一软失败 → 列缺失项 + 当前最优上报,不死循环。

---

## 完成后下一步

真 app(Workflow):

`完成: /design-restore 已用 Workflow 按屏×视口扇出还原,critic 写 ui-diff.json(mismatch=N)+ token-match.json(hardcoded=0/mismatched=0),设计已高保真还原`

被脊柱关调用:

`完成: design-restore 【段X】产物已落 docs/design/,控制权交回 /<调用方>`

熔断 / 降级:

`停住: Per-Screen 在 home@iPhone 3 轮未收敛(stop_reason=score_not_monotonic),critic 已 halted 上报当前最优 + 残差,需人介入`

`降级: .pen 不可达(WebSocket not connected),已退到导出 PNG 走截图档,extraction_meta.actual_source=screenshot + degraded:true,继续`

`降级: 无 Workflow 工具(AI 调用·非CLI)time,已退线性段一~段三单 agent 顺序跑,两份 state JSON 手写(key 仍对齐闸门)`
