<!--
UI-FIDELITY-GATE 章节模板 — design-restore 高保真闸门 (qa 阶段内部调用)
要求: 三层叠加判定 (结构/布局 diff + token 对账 + VLM 语义残差) + 抗误杀强制项.
脚本 sg_app_ui_visual_diff / sg_app_design_token_match 验证. 初期 sg_run_soft=advisory 不阻塞.

为什么必填:
  纯像素 diff 误杀率 30-40% (动画/时间戳/头像/抗锯齿/DPR 差异全算"不一致").
  design-restore 的停止判据是"分数单调下降才继续", 没有一个稳定、可解释、不误杀的
  保真分数, 整个截图 diff 闭环就会假阳性刷屏 → 人放弃看 → 闸门形同虚设.

填写原则:
  1. reify ≠ create: 本闸门只验"实现是否还原了设计基线", 不评判设计好坏 (那是 frontend-design 的事).
  2. baseline 来自 docs/design/baseline/<platform>/<viewport>/<screen>.png (design-manifest 桥产物).
  3. 三层是**叠加**判定, 不是择一: 像素 diff 给定位, token 对账给根因, VLM 给"人眼是否真的不一样".
  4. VLM 语义残差**绝不单独硬挡** — 只做"像素 fail 但可能是误杀"的复核仲裁, 强制 JSON 输出.
  5. 抗误杀强制项是闸门生效的前提, 缺任意一项 → 本次 diff 结果不可信, 标 inconclusive 重跑.
  6. 阈值表 FROZEN by default, 改阈值 = 回 shape 记录理由 (放宽阈值是在花预算买误判).

$AI_RULES_ROOT 用法: 截图脚本 / VLM prompt / 阈值表均落在 $AI_RULES_ROOT 下, 保持项目间可移植.
  - 截图器: $AI_RULES_ROOT/scripts/design-first/ui-snapshot.sh
  - diff 器:  $AI_RULES_ROOT/scripts/design-first/visual-diff.mjs
  - VLM 仲裁: $AI_RULES_ROOT/scripts/design-first/ui-vlm-residual.mjs
  - 阈值表:  $AI_RULES_ROOT/config/ui-fidelity-thresholds.json
-->

## UI-FIDELITY-GATE

> 设计基线 → 实现的视觉保真闸门. 三层叠加 (结构/布局 diff · token 对账 · VLM 语义残差).
> 输入: docs/design/baseline/<platform>/<viewport>/<screen>.png + 实现态截图.
> 停止判据: 保真分数**单调下降**才继续迭代, 不降即停并上报 (见 §停止判据).

---

### 第 1 层 — 结构 / 布局 像素 diff (pixelmatch · SSIM, per-viewport 阈值表)

> 机械层: 给"哪里不一样"的坐标定位. 输出 diff overlay PNG + mismatch 百分比 + SSIM.
> pixelmatch 抓"逐像素差异比例", SSIM 抓"结构相似度" (对亮度/对比/抗锯齿更稳). 两者都看.

**每端 / 每视口阈值表 (FROZEN, 来自 $AI_RULES_ROOT/config/ui-fidelity-thresholds.json):**

| 平台 | 视口 (viewport) | 模拟器型号 (锁定) | DPR (锁定) | mismatch 阈值 | SSIM 阈值 |
|------|----------------|------------------|-----------|--------------|-----------|
| iOS | 390×844 (iPhone 15/16) | `<TBD: iPhone 16, iOS 18.x>` | `<TBD: 3>` | ≤3% pass / 3-8% warn / >8% fail | ≥0.97 |
| iOS | 430×932 (Pro Max) | `<TBD: iPhone 16 Pro Max>` | `<TBD: 3>` | ≤3% pass / 3-8% warn / >8% fail | ≥0.97 |
| Android | 412×915 (Pixel) | `<TBD: Pixel 8, API 35>` | `<TBD: 2.625>` | ≤3% pass / 3-8% warn / >8% fail | ≥0.96 |
| Web | 1440×900 (desktop) | `<TBD: Chrome headless 固定版本>` | `<TBD: 2>` | ≤3% pass / 3-8% warn / >8% fail | ≥0.97 |
| Web | 390×844 (mobile web) | `<TBD: Chrome headless 固定版本>` | `<TBD: 3>` | ≤3% pass / 3-8% warn / >8% fail | ≥0.96 |

**三档判定语义 (per screen × viewport):**

- **mismatch ≤ 3% → pass**: 视为还原成功, 不进 VLM 层.
- **3% < mismatch ≤ 8% → warn**: 不阻塞, 但**强制进第 3 层 VLM 复核**, 在报告里列出 diff 区域坐标.
- **mismatch > 8% → fail**: 候选不通过. 但**必须先过第 2 层 token 对账 + 第 3 层 VLM 仲裁**才落定 (防误杀).

> 注: 阈值是 per-viewport 的, 不允许全局一个数. 高 DPR / 字体渲染差异大的端 SSIM 阈值天然要松一档.

---

### 第 2 层 — token 对账定位器 (根因层)

> diff 告诉你"红了", token 对账告诉你"为什么红". 实现处**只引用 token 禁硬编码值**
> (见 design-manifest tokens.json / W3C DTCG). 本层把视觉差异映射回具体 token 偏差.

| 对账维度 | 定位方法 | pass 判据 |
|---------|---------|----------|
| 颜色 (color) | 在 diff 热区采样实现态主色 → 反查最近 token → 比对 manifest 期望 token | ΔE00 ≤ `<TBD: 2.0>` 且命中同一 token id |
| 间距 (space) | 量取关键盒模型边距 (padding/gap) → 比对 space token 阶梯 | 偏差 ≤ `<TBD: 1px 或 1 个 token 阶>` |
| 圆角 (radius) | 量取 border-radius → 比对 radius token | 命中同一 radius token |
| 字体 (type) | 比对 font-family / size / weight / line-height vs type token | 全字段命中 token, 无 fallback 字体 |
| 主题 (theme) | light / dark 各跑一遍, 比对对应主题 token 集 | 两套主题分别 pass |

**硬规则: 发现任意"硬编码值" (实现里写死颜色/尺寸而非引用 token) → 本屏标 token-drift, 即使像素 pass 也记一条整改项.**
> 根因可解释 = diff 可信. token 对账是 pixel diff 与 VLM 之间的"翻译层", 让 fail 能直接给整改指令.

---

### 第 3 层 — VLM 语义残差 (复核仲裁层, 强制 JSON, 绝不单独硬挡)

> 像素 fail / warn 时的人眼代理. 回答唯一问题: "撇开抗锯齿/渲染微差, 这两张图给用户的观感是否实质不同?"
> **绝不单独硬挡**: VLM 不能凭空把 pixel-pass 改成 fail, 也不能单独定 fail — 只做仲裁与降级/升级建议.

**调用条件 (省钱 + 防滥用):** 仅当第 1 层结果为 warn 或 fail 时调用. pass 不调.

**强制 JSON 输出契约 (脚本只解析 JSON, 自然语言一律丢弃):**

```json
{
  "screen": "<screen id>",
  "viewport": "<viewport>",
  "perceptual_diff": "none|minor|major",
  "is_false_positive": true,
  "diff_regions": [
    { "area": "<语义区域名, 如 顶部导航/价格卡>", "kind": "color|spacing|text|layout|missing|extra", "severity": "low|med|high" }
  ],
  "verdict_suggestion": "pass|warn|fail",
  "reason": "<一句话根因, 给整改用>"
}
```

**仲裁规则 (三层合议):**

| 第1层像素 | 第2层 token | 第3层 VLM is_false_positive | 最终判定 |
|----------|------------|----------------------------|---------|
| warn | 无 drift | true | **pass** (像素噪声, 误杀拦截成功) |
| warn | 有 drift | any | **warn** (有真实 token 偏差, 列整改) |
| fail | 无 drift | true (perceptual_diff=none) | **warn** (疑似纯渲染差, 标人工复核, 不直接 fail) |
| fail | 有 drift | false (major) | **fail** (像素+根因+人眼三方坐实) |
| fail | 任意 | false | **fail** |

> VLM 只能在"像素已 warn/fail"的范围内做**降级 (拦误杀)** 或**坐实**, 不能凭空升级 pass. 这是"绝不单独硬挡"的具体落地.

---

### 抗误杀强制项 (本闸门生效的前提, 缺一项 → 结果 inconclusive 重跑)

> 纯像素 diff 误杀 30-40% 全来自这些非确定性源. 截图前必须逐项锁死, 否则 diff 数字无意义.

- [ ] **禁动画 / 关过渡**: 截图前注入 `* { animation: none !important; transition: none !important; }` (或平台等价), 等待布局 settle.
- [ ] **冻结时间 / 固定随机种子**: 时钟 mock 到固定时刻, RNG 固定 seed, 列表数据用固定 fixture (禁实时数据).
- [ ] **mask 动态区**: 头像 / 时间戳 / 倒计时 / 随机插图 / 广告位等动态区域在 baseline 与实现两侧**用同色块遮罩**后再 diff.
- [ ] **固定 DPR**: 模拟器与截图器 DPR 锁到阈值表中的值 (iOS=3 / Android=2.625 / Web 自定), baseline 与实现同 DPR.
- [ ] **固定字体**: 字体文件嵌入并预加载完成再截 (禁系统字体回退); 关闭字体平滑差异 (subpixel → grayscale 统一).
- [ ] **固定模拟器型号 / OS 版本**: 锁阈值表中的型号与 OS, 不允许"手边什么模拟器用什么".
- [ ] **等待网络/图片加载完成**: 所有 `<img>` / 远程资源 decode 完成 (或被 mask) 再截, 禁半加载态截图.
- [ ] **统一缩放裁切**: baseline 与实现按相同 viewport 截全屏后对齐裁切, 尺寸不一致直接 inconclusive (不缩放硬比).

> 任一项未满足 → 本次 diff 标 **inconclusive**, 不计入 pass/fail, 修复后重跑. 宁可不判, 不可误判.

---

### 停止判据 (design-restore 迭代闭环)

> 闸门服务于迭代: 每轮修改后重跑三层, 看综合保真分数 (mismatch + token-drift 数 + VLM severity 加权).

1. **分数单调下降 → 继续迭代** (还原在收敛).
2. **分数不降 (持平或回升) → 立即停, 上报**: 列出当前 top diff 区域 + token-drift + VLM reason, 交人决策 (改实现 / 改 baseline / 接受差异).
3. **达到全屏 pass → 收尾**: 所有 screen × viewport × theme 均 pass.
4. 禁止"无限刷 diff": 同一屏连续 `<TBD: 3>` 轮分数不降 → 强制停并标 stuck.

---

### 验收硬规则 (sg_app_ui_visual_diff / sg_app_design_token_match)

1. baseline 必须存在 (sg_app_design_baseline_exists 前置), 缺 baseline → 本闸门 skip 并记 "无基线, 未验保真".
2. 三层全部产出: 每 screen × viewport 必须有 {像素结果, token 对账结果, (warn/fail 时) VLM JSON}.
3. 抗误杀强制项 8 条逐项可证 (截图脚本日志体现), 缺项 → 结果 inconclusive.
4. VLM 输出必须是合法 JSON 且含 `is_false_positive` / `verdict_suggestion`, 否则丢弃该屏 VLM 结果按"无仲裁"处理 (fail 维持 fail).
5. 最终判定按"仲裁规则"三层合议表落定, 任何单层不得独立改写最终 verdict (尤其 VLM 不得单独硬挡).
6. 阈值表与 token 对账阈值 FROZEN, 改动回 shape 记录理由 (sg_run_soft=advisory, 初期不阻塞只告警).
