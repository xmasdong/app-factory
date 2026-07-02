# ROADMAP — 一次性产出(One-Shot Production)v2

> **终极目的**:一句话进 →(启动第一问 + 少数分叉签字)→ 无人值守内部收敛 → **交付即可提审成品**。用户只剩:看成品点头、按提审键。
>
> **核心认知**:约束是判卷,不是会做。门只能事后发现缺,不能改变生成时的分布。实证:质感规则齐备的会话,首版照样 2 资产零触感裸奔。
>
> **解法总纲:把约束变资产,把返工变内部收敛,把代理指标变实证。**
>
> v2 = v1 经 3 路红队(可行性/目的达成/排序 ROI)修订:2 个 fatal(hook 层回灌与现有架构矛盾、grep 代理门无人值守必 Goodhart 假绿)+ 排序倒置 + 缺件(难度曲线门/内容闸/资产一致性 QC/OSR 采集机制)全部吸收。

---

## 交付等级(先定义,防自欺)

- **可提审成品**:qa 全绿 + `open_items` 为空 → 计入 OSR 统计
- **草稿交付**:熔断后 open_items 非空 → 诚实交付但**不许自称可提审**,单独统计熔断率
- OSR(交付后用户要求返工轮数,目标 ≤1)只对"可提审成品"计——open_items 非空还算 OSR = 度量自欺

## 主指标(红队修正:OSR 是低频项目级指标,几个月才有统计意义)

- **每门首过率 + 内部收敛轮数**(每项目每门一个数据点,一款就有信号)→ 驱动"基座下一个补强点"
- OSR 保留为长期北极星,只记录不驱动短期决策
- **环境故障 ≠ 门失败**:codex 限流/模拟器 flaky/网络抽风 → 重试不计收敛轮数

---

## 里程碑(红队重排:便宜、零前置、直接对症的先做)

### M0 — 度量埋点 + strict 翻转(~1 小时,全表最便宜,先做拿基线)
- status.md 模板加三字段:每门首过率 / 内部收敛轮数 / OSR(回填);**ship 门机械要求 osr 字段存在**;`/app-factory` router 开新项目时检查上一项目 OSR 是否回填,未填提醒——用机制不靠自觉
- **strict 翻转策略**:杠杆③的前提是硬闸;scaffold 对 app 项目在 `.claude/settings.json` 注入 `APP_FACTORY_MODE=strict`(工厂仓自身/非 app 项目维持 advisory)

### M1 — 投料单前置(半天,零前置,直接对症"首版裸奔")
- shape 产 `docs/DESIGN-FEED.md`,**定位钉死 = 投料(prompt-feed),不是对账契约**:
  - 机器提取段(标 extracted):从用户拍板的 mockup 提色板/圆角(design-restore 抽取段现成)
  - VLM 风格基因段(标 inferred):字体气质/纹理/情绪词
  - 资产清单 + juice 件选用表
- **投料单落成可执行物,不是又一份散文**:token 直接生成 `theme.dart` 变量赋值文件——UI 任务最省事路径 = import 主题;想裸奔反而要多写代码(顺拉力设计的真正落点)
- **明文禁止**把 AI mockup 接进 ui-diff/token-match 硬门(AI 图的假文案/幻觉布局会把实现往"像素复刻幻觉"上逼);视觉验收走质感门 + VLM 建议档
- build Step 4 改造:UI 任务实现前,DESIGN-FEED + 基座组件目录注入生成上下文;Step 7.3 保留当验收

### M2 — qa 内部自收敛 loop + 门判据实证化(1-2 天;fatal 修正后的杠杆③)
**架构(红队 fatal ①)**:loop 在 **qa SKILL 会话内部**跑(与 design-restore 3 轮熔断同构):验 → 查失败→修复映射表 → 补做 → 重验;轮数计 `.claude/state/qa-loop.json`(文件态,防 compaction 丢);Stop hook 只保留一道兜底(qa-loop 显示未收敛且未打包 open_items → block 一次);**不依赖 hook 多轮回灌**(stop_hook_active 机制下那是幻觉)。

**门判据实证化(红队 fatal ②,防 Goodhart 假绿)**:
- 资产门:文件数 → **像素实证**(尺寸/非纯色占比/与 manifest 及代码引用点接线对账)
- 庆祝/触感:grep → **证据门**:ios-sim-harness 截图序列喂 codex VLM 判"结算屏可见庆祝元素?",写 verify-report
- **风格一致性硬门**:全套产出图 + DESIGN-FEED 色板喂 VLM 问"这是同一款游戏的吗",不过=资产工位重出
- 每轮自动修复的 diff 强制记入交付包附录 → 给 touch-2 的人一个抽查面

**失败→修复映射表**(qa SKILL 内):

| 门失败 | 自动补做 |
|---|---|
| game_feel / product_feel | 资产工位出缺件 + juice 接线 → 重验(VLM 实证) |
| contract-test | 漂移五大模式速查 → backend 修复 → 重跑 |
| seam / integration | stack-up 重起 + 按 broken 清单修 → 重跑 |
| native_run | 按 native-run.json 的 step 对症 |
| reviewer_path / aso | 补产材料 |

### M3 — M1a:juice kit + 资产工位(1 天,**不等 drawguess**,独立可复用件)
红队修正:这两层玩法无关,从历史手表游戏经验直接兑现,别绑在 drawguess 后面。
- **juice kit**(local pub package):BounceButton / 庆祝系统(confetti+mascot 钩子)/ HapticService 分级 / 过渡包 / 计时器件 / **SFX 槽位**(按钮/得分/失败短音效,默认极简包可关;**排除的是 BGM,不是音效**)
- **资产工位**(脚本 + prompt 包),核心对策 = 风格漂移(用户 game-asset-lab 线已交过学费):
  1. **key art 先行**:先出 1 张主视觉,后续所有图走 codex `--image` 参考(image-to-image 锁风格基因)
  2. 出图后机械校验:主色板 vs DESIGN-FEED token 对账
  3. **identity_qc + autoretry**(复用 game-asset-lab 模式):不合格自动重出,不靠人挑
  4. 图标全尺寸切割(AppStore 无 alpha 自动处理)+ 接线 manifest 约定

### M4 — 完整游戏基座 v0(drawguess 交付后 +2-3 天;排期诚实:前置是一整个项目)
- **基座分层(防 n=1 过拟合)**:
  - **通用层**(v0 只收这三样):juice kit + 资产工位(来自 M3)/ 状态屏(how-to/结算/空/错误)/ 合规预置(privacy manifest/4+/COMPLIANCE-RISKS 骨架)
  - **genre 插件层**:drawguess 反抽的 FSM(setup→play→reveal→result)只当**回合制插件**;≥2 款后才升通用
  - **范围声明**:v0 只覆盖 Flutter widget-tree 游戏;**Flame/canvas 实时族 out-of-scope**(另立 base,别硬套)
- **换皮验证(DoD,防自证)**:demo 玩法**预先钉死为实时类**(如 flappy 移植)——禁止建基座的 agent 自选玩法(它会挑贴骨架的自证通用);验收人 = **用户**(第二 touch 签字),不许 AI 自评过
- 基座自身吃全套门:sim-harness + game_feel(实证版)+ 陌生人测试
- **基座回流机制**(挂 ship 门 checklist):每款交付后,收敛轮里产生的通用修复 → 评估回流 bases/;基座版本号 + 派生项目记录所用版本;防过拟合补丁:回流只收"≥2 款都撞过"的
- scaffold 接线:PRODUCT_FORM=游戏 → 从基座起(copy+rename+DESIGN-FEED 主题注入);基座缺席退回现行路径

### M5 — app 基座 v0(M4 模式验证后,1-2 天;服务瓦片/医疗线)
token 系统 + onboarding 件 + 空/骨架/错误/重试组件族 + 设置/关于/隐私屏 + paywall 槽(默认关)+ 人话文案库。DoD 同 M4(product_feel 实证版 + 换皮 + 用户签字)。

### M6 — 毕业考(红队修正:n=1 证明不了任何事)
- **首跑 = 有人旁观的排练**(第一次全链无人值守大概率在调试 loop 本身,不是验收产品)
- **毕业标准 = 连续 2-3 款不同玩法新游戏 OSR≤1**,摊进后续真实生产滚动验收,不专门造样本

---

## 新增门(红队补缺,进 game_feel 家族)

- **可玩性/难度曲线 checklist**(30% 生成部分唯一的质量闸;手表游戏线的 Difficulty Curve Rule 回收进厂):首关 30 秒可懂 / 失败可归因 / 难度单调渐进 / 每局有"再来一把"钩子
- **内容质量闸**:词库/关卡数据的可解性(生成关卡必须可解)、去重、适龄性(4+ 分级词条筛查)

## 风险与诚实边界

- **消不掉的残余**:审美最后一眼 / 真机手感 / Apple 审核随机性 → 2-touch 第二眼消化,**不追 0-touch**
- **基座不解决创意**:玩法逻辑那 30% 靠生成 + 可玩性门;基座解决"创意之外一切不该重新发明"
- **无人值守的资源预算**:codex 登录态过期/限流、模拟器单轮 5-10 分钟 → 环境故障重试不计轮(见主指标)
- Goodhart 是永恒对手:每次把门变严,先问"无人值守下最省事的过门方式是什么"——如果答案不是"把事做对",门就还没设计完
