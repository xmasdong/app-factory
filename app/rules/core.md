# app 主线核心规则 (6 个 A-GATE)

> 本文件定义 app 主线门禁的完整检查项。与 generic `../../.claude/rules/core.md` 冲突时, 以本文件为准 (PROJECT_TYPE=app 项目)。
>
> 思想层 (任务链 / 熔断 / 决策生命周期) 仍走 generic `../../CLAUDE.md`, 本文件不重复。

## 先读:通用约束 + 本文件怎么用

> ⭐ **交付质量的地基不在这份 gate 清单里,在 [`build-constraints.md`](build-constraints.md)**(8 条透镜式约束 + 元则:*别走最省事的直译,别用最弱证据自证*)。建东西前、宣称"完成"前,先用它自省(或跑 `/self-correct`)。gate 是流程骨架,build-constraints 是判断力。

**这份文件是「就本产品该回答的问题」,不是「必须填满的死字段」:**
- 下面的检查项、表格列、数字(3 档价格 / ≥3 假设 / CAC×0.3 / 具体设备列 等)都是**默认与示例,不是法律**。按**当前产品**判断哪些适用——不适用的**显式说明为什么跳过**(写进 status.md 决策清单),而不是硬填或空着。
- advisory 模式(默认)下,gate 给建议不阻塞;跳过某项 = 记一句理由即可。真正不可协商的只有下面标 **NEVER/MUST 的少数不可逆护栏**(命名一致 / 价格单调 / 合规 / 密钥 / 删号)——那是客观正确性,不是想象力枷锁。
- 产品形态不止"原生 iOS/Android 商店 app":也可能是 Web/PWA、手表、小程序、单机游戏。**gate 里凡假设了某种形态的具体项,按你的形态重映射**(如 PWA 的"上架"= 部署 + Web Push,不是 App Store 提审)。别被写死的商店术语框住。

## 6 个 A-GATE 总览

```
A-GATE Discovery  → /discover  — TOUCH 1 后: 产品定位 + 市场调研 + mockup, Step 0.8 hard stop
A-GATE Lockdown   → /lockdown  — TOUCH 2 后 AUTONOMOUS: spike + 经济 + 命名(推荐→查重→选) + 后端 + 合规
A-GATE Shape      → /shape     — Lockdown 后自动续: PRD + 多端矩阵 + 任务拆分
A-GATE Build      → /build     — Shape 后自动续: 实现 + 测试
A-GATE QA         → /qa        — Build 后自动续: 验收 + 审核员路径
A-GATE Ship      → /ship      — QA 后自动续: ASO + 商店材料 + 上架
                   初始化       → /scaffold (一次性脚手架)
```

每关 CHECK → IF NOT → IF YES → OUTPUT 自检, 由 `app/scripts/app-gate.sh` 机械验收。

---

## A-GATE 0: 外部锚定 (新, app 主线核心差异)

```
CHECK: 能回答以下全部 (5 个子产物)?
  1. 命名锁定: bundle id / Application ID / 商店显示名 / 域名 / IAP product id 是否查重 + 锁定?
  2. 单位经济: LTV / CAC / 单次成本 / 价格阶梯是否算清且单调?
  3. 技术 spike: 关键技术假设是否跑过最小实验且 PASS?
  4. 后端就绪: 用户系统 / 鉴权 / 推送 / 支付服务端 / 删号接口是否到位 (或显式 deferred)?
  5. 合规扫描: 隐私 / 儿童 / 订阅披露 / EULA / 删号 / 权限文案是否过预审?
IF NOT → 不许进 A-GATE 1, 不许写一行业务代码
IF YES → 进入 A-GATE 1 (产品认知)
OUTPUT → docs/spec.md 中 5 个子章节齐全 (引用 spec.md.tmpl 中的占位)
```

**执行顺序** (技术 spike → 经济 → 命名 → 后端, 合规并行):

| 步骤 | 子产物 | 为什么这个顺序 |
|------|--------|--------------|
| 1 | 技术 spike | 技术路径不通, 后面全白搭 — 先验证最大不确定性 |
| 2 | 单位经济 | spike PASS 后才知道实际单次成本, 才能算价格阶梯 |
| 3 | 命名锁定 | 单位经济定了商业模式, 才知道注册什么公司主体, 才能查重 |
| 4 | 后端就绪 | 命名 + 模式定了才知道后端要支持什么 (账号体系 / IAP 验证 / 删号) |
| - | 合规扫描 | 并行进行 (合规问题可能反过来推翻命名 / 经济 / 技术选型) |

### 子产物 1: 命名锁定

**6 项必须全过, 缺一项不进 A-GATE 1**:

```
□ bundle id (iOS) 已查重 (App Store Connect 注册占位) + 锁定
□ application id (Android) 已查重 (Play Console 注册占位) + 锁定
□ 商店显示名 (iOS + Android) 已在两端搜索查重, 无冲突或近似名
□ 域名已注册 + 持有人 = 公司主体 (审核交叉验证)
□ IAP product id 命名规则定义 (前缀 / 单数复数 / 阶梯命名), 不可重命名
□ 公司主体 / 开发者账号 (Apple Developer + Google Play) 已开通 + 主体一致
```

**FROZEN by default**: 命名锁定后写入 spec.md `## 命名锁定` 章节, 标注 `FROZEN 2026-xx-xx`。任何变更回 A-GATE 0 重新走完 6 项, 不在下游吸收。

**bundle id 一旦上架不可改**: 改 = 重新提交一个新 App, 历史用户全部丢失, IAP 续费链路断裂。这是 app 主线最致命的灾难, 优先级高于一切其他锁定。

### 子产物 2: 单位经济

**先判本产品要不要这一节**:
- **有变现(订阅/内购/买断)** → 经济必须闭合(下方全套按需填)。
- **免费 / 纯 ASO 引流 / 先跑通后变现**(很多游戏、工具属此) → **这一节大幅简化**:只需说清"当前不变现,靠什么活(自然量/引流/后续加)+ 唯一硬约束=单次核心操作成本不能失控"。**别硬套价格阶梯/LTV/CAC** —— 没订阅时那些是空转摩擦,记一句"无变现,经济节 N/A(理由)"即可。

有变现时的清单(按适用取,非全必填):
```
□ 单次成本表: 每次核心操作的实际成本 (云函数 / AI 推理 / 第三方 API / 存储 / 带宽) —— 有真实云成本就必算
□ 价格阶梯表: 若多档订阅, 阶梯**单调** (单位时间均价递减) —— 单一买断/单档不涉及
□ LTV / CAC: 能估就估 (留存 × 月均付费 / 获取成本), 早期无数据 → 标假设 + 待真实数据校准, 别编精确数
□ IAP 价格层级映射: 与商店 tier 一致
□ 退款 / 续费失败兜底
```

**唯一硬约束(有多档订阅时才触发)**:**价格阶梯单调** —— 月费 ¥30 → 年费 ¥360(=¥30/月,没优惠)= 错;年费均价必须 < 月费均价。脚本 `sg_app_economics_monotone` **只在检测到多档价格时**校验单调,单档/免费不触发。(CAC ≤ LTV×0.3 之类是**经验参考不是硬线**,按品类判断。)

### 子产物 3: 技术 spike

**关键技术假设逐个跑最小实验**, 而不是规划阶段直接选型:

```
□ 列出关键技术假设 (≥3 条, 项目无关都至少有: 性能 / 兼容性 / 集成成本)
□ 每个假设有可执行的最小验证 (代码 + 命令 + 预期信号)
□ 实际跑过, 结果记入 spec.md `## 技术 spike` 章节
□ 失败的假设有备选方案, 不在错误方向上堆代码
```

典型 spike (按项目类型):
- AI 项目: 端上推理延迟 / 模型大小 / 兼容性 (iPhone 8 能不能跑)
- 多媒体: 编码效率 / 内存峰值 / 录制中断恢复
- 跨端: iOS / Android 平台差异 (权限弹窗 / 后台行为 / 推送 token)
- 实时通信: WebSocket 重连 / 弱网降级 / 长连保活

### 子产物 4: 后端就绪

```
□ 用户体系: 账号注册 / 登录 / Apple ID / Google Sign-In / 微信登录 — 选哪个, 谁实现
□ 鉴权: token 颁发 / 刷新 / 失效, 服务端实现状态
□ 推送: APNs (iOS) + FCM (Android) 凭证配置, 证书有效期 ≥6 个月
□ 支付服务端验证: App Store Server Notifications / Google Play Real-time Developer Notifications 接入
□ 删号接口: 用户主动注销 + 后台清理 (Apple 强制 5.1.1(v) / Google 类似要求)
□ 数据合规: 用户数据存储位置 (国内 / 跨境) + 加密方案
```

后端 deferred 不阻塞 spike, 但阻塞 A-GATE 2 实现。记入 status.md deferred 清单, 谁来实现 / 何时完成必须明确。

### 子产物 5: 合规扫描

**定位 = 情报性预审,不是生产闸**(用户价值函数:合规可后置,产出优先)。前置扫的价值是"早知道风险"——发现拒因**记进 status.md COMPLIANCE-RISKS 清单,继续产出**,不停线;**硬校验点在 ship 提审前**(终扫必须清零,那才是不可逆点)。常见审核拒因前置识别:

```
□ 隐私: 数据收集类型 (设备 ID / 位置 / 通讯录 / 麦克风 / 摄像头) + Info.plist 用途字符串 (中英双语)
□ 儿童类: 是否被识别为 Kids Category (主题 / 角色 / 互动方式), 如是, App Review 1.3 全套加码
□ 订阅披露: 自动续费 App 必须在购买前显示 — 价格 / 周期 / 续费规则 / 取消方式 / EULA 链接
□ EULA: 非 Apple 标准 EULA 必须独立 URL 可访问 + 在订阅前展示链接
□ 删号: App 内必须有用户注销入口 (不能只让发邮件), 流程不超过 3 步
□ 权限文案: 每个权限申请都有中英双语的清晰用途说明 (NSCameraUsageDescription 等)
□ IAP review screenshot: 沙盒账号下截图 4 张 (订阅入口 / 价格披露 / EULA / 恢复购买)
```

合规问题预审通过的标志: 调用 `app-store-review-survival` skill 的预审清单全部 PASS。

---

## A-GATE 1: 产品认知 (复用 generic GATE 0 + 多端补丁)

```
CHECK: generic GATE 0 全部检查通过, 且追加的"多端能力矩阵"已完成?
IF NOT → 回 generic GATE 0 (../../.claude/rules/core.md) 补全
IF YES → 进入 A-GATE 2
OUTPUT → docs/spec.md 完整 (PRD 挑战 / 故障想象力 / 数据契约 / 多端矩阵 / TASK 清单)
```

**直接复用 generic GATE 0 全部内容** (不在此重复):
- 前置人工动作清单
- 视觉规格 (DESIGN.md 9 章节)
- PRD 挑战 (5 视角)
- 故障想象力 (维度枚举)
- 核心难点识别 ([CRITICAL] 模块)
- 外部文档对账

**A-GATE 1 显式新增: 多端能力矩阵**

原则:**能力 × "本产品真正相关的部署轴"** 逐格声明,不留空白、每个非全支持的格给理由。

**轴由你按当前形态选,不是写死的那几列。** 先问:*这个产品实际要覆盖哪些维度?* 再据此列。举例(选用,不是必填):
- 原生跨端 app → 最低/主版本 OS、平板、横屏、折叠屏、暗色
- 手表游戏 → 表盘尺寸档、离线、省电、表冠是否用到
- Web/PWA → 浏览器矩阵、移动/桌面视口、离线、安装态
- 单机游戏 → 目标机型性能档、屏幕比例、暗色

下面是**形式示例**(列请按你选的轴换掉):

```
| 能力 | <轴1> | <轴2> | <轴3> | ... |
|------|-------|-------|-------|-----|
| 核心功能 A | ✓ | ✓ | 降级(理由) | ... |
```

**纪律(这几条是原则,跨形态都成立)**:
- 轴至少覆盖:**最低目标环境 + 主目标环境 + 这个产品最容易翻车的那个维度**(手表=小屏手感、照片=尺寸规格、跨端=平台差异…)。轴选得对不对,自己判断并说明。
- 每个 `n/a / 降级 / deferred` **必须有理由**,不留空白格。
- 大量 deferred → 在第一个检查点跟用户对齐是否真能延后(数量阈值自己拿捏,别机械卡 3)。
- 脚本 `sg_app_platform_matrix` 只校验"矩阵存在 + 无空白格 + ≥N 行",**不规定你用哪些轴**。

---

## A-GATE 2: 实现 (复用 generic GATE 1 + GATE 2)

```
CHECK: generic GATE 1 (理解门禁) + GATE 2 (能力门禁) 全部通过?
IF NOT → 回 generic 对应 GATE (../../.claude/rules/core.md)
IF YES → 进入 A-GATE 3
OUTPUT → 代码 + 测试 + status.md 更新 + commit hash
```

**直接复用 generic 内容**:
- 理解门禁: 任务三问 (做什么 / 验收 / 改哪些文件) + IMPACT 自检 + SMOKE 自检 + 实现中范围检查 + Mock/Stub 规则
- 能力门禁: 测试分层 (单元 / 集成 / E2E) + 假不可知 vs 真不可知 + 回滚成本路由 + 决策生命周期 + 冻结边界 + 批量检查点

**A-GATE 2 不引入新检查项**, 仅在以下细节加补丁 (写入 status.md 默认值):

- iOS 项目: E2E 必须包含真机或 Simulator 跑通, Xcode UI Test 或 fastlane snapshot 二选一
- Android 项目: E2E 必须包含 Espresso 或 UiAutomator
- 多端项目: 任何修改 `bridge` / `native module` 的任务 IMPACT 必须包含双端
- 涉及 IAP 的实现必须有 sandbox 测试用例, mock 不算

---

## A-GATE 3: 验收 (复用 generic GATE 3 + 审核员路径)

```
CHECK: generic GATE 3 (状态门禁) 全部通过, 且审核员路径已备?
IF NOT → 回 generic GATE 3 (../../.claude/rules/core.md) 补全
IF YES → 进入 A-GATE 4
OUTPUT → status.md 更新 + 审核员路径文件齐全
```

**直接复用 generic GATE 3 内容**:
- 代码已 commit / status.md 已更新 / 关键决策入文件 / 放弃方案记录 / 结构信号教训 (lessons.md)

**A-GATE 3 显式新增: 审核员路径**

在 `docs/reviewer-path.md` 中提供:

```
□ Sandbox 账号: App Review 用的测试账号 (用户名 + 密码 + 注册的服务端环境)
□ Demo 视频: 核心功能 60 秒内完整演示 (中英字幕, 不依赖测试账号外的数据)
□ Review Notes: 给审核员的说明文档 (中英双语)
  - 如何登录测试账号
  - 如何触发核心功能 (前 3 步操作)
  - 如果需要后端配合的特殊数据怎么获取
  - 已知不影响审核但可能引起疑问的细节
□ 截图归档: A-GATE 3 验收阶段的 verify-screenshots 目录, 文件命名规则: 平台_页面_状态.png
```

脚本 `sg_app_reviewer_path` 在 AI 宣称 /qa 完成时自动检测 `docs/reviewer-path.md` + `.claude/state/verify-screenshots/` 是否齐全。

---

## A-GATE 4: 上架 (新, app 主线核心差异)

```
CHECK: 能回答以下全部?
  1. ASO 关键词清单: iOS / Android 各自的关键词 + 描述 + 副标题已定 (≥3 个候选关键词集)
  2. 截图脚本: fastlane snapshot 或等价工具配置完成, 截图可一键重新生成
  3. 商店材料: 名称 / 描述 / 关键词 / 推广文本 / What's New / 隐私问卷 / 分级问卷 / 联系信息全部就绪
  4. 合规复扫: 调用 app-store-review-survival skill 二次扫描全部 PASS
  5. 提审前 checklist: 版本号 / build number / 签名 / TestFlight 内部测试通过 / 隐私 manifest
IF NOT → 不许提审
IF YES → 提审 (人工执行, AI 不能代提)
OUTPUT → docs/store-materials/ 完整 + 提审记录
```

### 子产物 1: ASO 关键词

```
□ iOS 关键词字段 (100 字符限制) + 副标题 + 描述前 3 行 (商店列表预览)
□ Android: 短描述 + 长描述 + 商店标签
□ 至少 3 套候选 (A/B 测试或地区差异化), 标注主推
□ 关键词不能与商店搜索算法已知违规模式冲突 (堆砌 / 竞品名 / 误导)
```

### 子产物 2: 截图脚本

```
□ fastlane snapshot / Maestro / 自研脚本三选一, 配置入仓
□ 截图覆盖: iPhone 6.7" / 6.1" / iPad / Android 手机 / Android 平板, 各 5-10 张
□ 截图含: 启动页 / 核心功能 1-3 / 付费墙 / 设置页
□ 一键重跑: 文案 / 截图变更后 5 分钟内重新出图, 不靠人肉截
```

### 子产物 3: 商店材料

完整清单引用 `app-store-review-survival` skill, 核心:

```
□ 应用名称 (与 bundle id 商店配置一致)
□ 副标题 / 简短描述
□ 完整描述 (含订阅披露 — 自动续费 App 必须)
□ 关键词字段
□ 隐私问卷 (App Privacy questionnaire) — 数据收集类型清单
□ 年龄分级问卷
□ EULA URL (非 Apple 标准 EULA)
□ 联系信息 / 支持 URL / 营销 URL
□ What's New 文案 (中英双语)
□ Promotional Text
```

### 子产物 4: 合规复扫

A-GATE 0 子产物 5 已扫一遍, 上架前再扫一遍 (代码 / 文案 / 截图 / 商店材料对账)。重点变化:

```
□ 实际实现是否漂离 A-GATE 0 的合规承诺 (例如 A-GATE 0 说不收集位置, 代码里偷偷申请了)
□ 截图是否暴露了不该展示的数据 (真实用户名 / 测试服 logo)
□ EULA / 隐私政策 URL 是否仍可访问且与商店材料一致
```

### 子产物 5: 提审前 checklist

```
□ 版本号符合语义化版本规范
□ build number 单调递增 (Apple 强制)
□ 签名证书未过期 + Provisioning Profile 匹配
□ TestFlight 内部测试至少 1 轮 + 外部测试 ≥3 人
□ iOS 17+: 隐私 manifest (PrivacyInfo.xcprivacy) 已配置
□ Android: targetSdk 不低于 Play Console 当前要求
```

### A-GATE 4 与 generic /release 的关系

generic `/release` 输出 `release-ready` / `ready-for-staging` 是 A-GATE 4 (/ship) 的**前置**, 不是替代。app 主线在 generic /release 通过后, 还需要走 /ship 上架专属检查, 才能真正提审。

---

## 硬规则 app 补丁 (在 generic 硬规则之上追加)

- **NEVER bundle id 锁定后变更** (一旦上架就是新 App, 历史用户全丢)
- **NEVER 价格阶梯非单调** (年费 / 月费 / 终身均价必须递减, 否则商业模式有缺陷或定价失误)
- **NEVER 命名 6 项未全过就进 A-GATE 1** (查重 / 商店占位 / 域名 / IAP 命名 / 公司主体 / 开发者账号)
- **NEVER 跳过技术 spike 直接选型** (关键技术假设未验证 = 在错误方向上堆代码的最大风险)
- **NEVER 沙盒测试没跑就发版** (IAP / 推送 / 删号必须沙盒走一遍)
- **NEVER 签名私钥 / IAP 共享密钥 / App-Specific Password 入 git**
- **NEVER iOS 审核被拒后在对话里临场拍方案** (必须调用 `app-store-review-survival` skill, 这个 skill 知道审核规则的精确条款)
- **MUST 多端项目改 native bridge 任务 IMPACT 列双端文件**
- **MUST 涉及订阅的页面在 A-GATE 0 子产物 2 同步定义 (价格阶梯 → 实现 → 截图)**
- **MUST A-GATE 4 提审前 reviewer-path.md 齐全, 缺一项不许提**

## 禁止模式 app 补丁

| 禁止 | 识别信号 | 正确做法 |
|------|---------|---------|
| 没查重就选名字 | spec.md 中应用名 / bundle id 没有"查重通过 + 日期"标注 | A-GATE 0 子产物 1 全过再 lock |
| 没算单位经济就上订阅 | 实现了 IAP 但 spec.md 无 `## 单位经济` 章节 | A-GATE 0 子产物 2 必填 + 价格阶梯单调 |
| 没跑 spike 就选技术栈 | 选型理由是"业界主流"或"我熟悉", 没有最小实验日志 | A-GATE 0 子产物 3 必填 + 失败方案在 status.md 放弃方案章节 |
| 后端 deferred 但实现已经依赖 | status.md deferred 列表里有"账号系统"但代码已经在调登录接口 | 解锁 deferred 或回 A-GATE 0 |
| 审核被拒临场改文案 | 收到拒信后直接改 Info.plist 用途字符串 + 提交 | 调用 `app-store-review-survival` skill, 按条款评估再改 |
| 上架前没复扫合规 | A-GATE 0 后没再次跑合规扫描 | A-GATE 4 子产物 4 必跑 |

---

## 与 generic 主线的过渡

如果项目原本是 generic, 后来增加了 native 包想上架:
1. 在 `docs/status.md` 顶部加 `PROJECT_TYPE: app` + `CURRENT_GATE: A-GATE 0`
2. **强制回到 A-GATE 0**, 不能跳过 (即使之前 generic GATE 0 已通过)
3. A-GATE 0 通过后, 原 generic GATE 0 产物自动归入 A-GATE 1 (无需重做)
4. 后续走 A-GATE 2/3/4
