---
name: ship
description: "Ship the app to App Store / Google Play — lock ASO keywords, generate store screenshots via fastlane/Maestro, assemble store materials (privacy questionnaire, EULA, reviewer notes), rescan compliance, finalize multi-language. A-GATE 4 store submission preparation."
---

# /ship — A-GATE 4 上架 (app 主线核心差异)

> 🔗 **App Factory 集成**:Step 3 截图调 `app-store-screenshots`(商店上架图);Step 7 合规终扫调 `app-store-review-survival`(已集成);**新增末尾步:调 `ios-ship-cli` 真上传 TestFlight/App Store**(fastlane 命令行)。本关原只备材料,集成后闭环到实际提交。
>
> ⚙️ **设备/语言/尺寸清单是示例池,不是强制清单**:先声明本产品实际支持的**设备类 + 目标市场语言集**,截图数量/尺寸服从"该商店该尺寸的当前硬上限"(如 iOS 单尺寸 ≤10),语言由目标市场推导。文里写死的具体尺寸/语言/张数(6.5"/iPad/各 5-10 张/≥3 语言)是默认锚点——不涉及的设备线/语言显式跳过,别为凑清单铺满。也别假设一定是原生商店:Web/PWA 的"上架"= 部署 + Web Push,不走这套。**真护栏照旧**(平台硬约束/审核拒因):≤100 字符、build number 单调递增、Rejected build 烧号、RGB 非 RGBA、不含竞品名、隐私政策 URL、以 ASC 当前提示为准。判断力地基见 `build-constraints.md`。

**作用:** 把 /qa 已通过的产品包装成"商店审核可提交"状态. 关心 ASO + 商店材料 + 合规复扫 + 商店截图 — 这些是 generic /release 不覆盖的维度.

**与 generic /release 的关系:**
generic /release 关心"代码能不能发"; /ship 关心"商店材料能不能提审 + 审核能不能过". generic /release 输出 `release-ready` 是 /ship 的**前置**, 不是替代.

**INPUT_CONTRACT:**
- A-GATE 0/1/2/3 全过 (`clearance-anchor.json` + `clearance-shape.json` + `clearance-qa.json` 存在)
- 任务清单全 `- [x]`
- generic /release 已输出 `release-ready` 或 `ready-for-staging` (在 `.claude/state/release-report.json`)
- 审核员路径产物齐 (`.claude/state/reviewer-walkthrough/`)
- `docs/status.md` 顶部含 `CURRENT_GATE: A-GATE 4`

**CONTRACT 不满足时:**
- 前置 clearance 缺失 → 拒绝执行, 提示对应 skill 重跑
- 任务未全完 → 提示先 /build
- 审核员路径产物缺 → 提示先 /qa

**OUTPUT → `docs/store-materials/` 完整 + 扩展 release-report.json + skill-signal.json**

参照 `.claude/rules/core.md § A-GATE 4` (上架完整检查项) 和 `.claude/rules/core.md § 硬规则 app 补丁` (上架前必扫).

---

## 执行计划

```
- [ ] Step 1: 前置 gate 检查 (5 个 clearance + generic /release report)
- [ ] Step 2: ASO 关键词定稿
- [ ] Step 3: 截图脚本就绪
- [ ] Step 4: 商店材料 (隐私问卷 / 分级 / 演示账号 / EULA)
- [ ] Step 5: 内容营销物料 (honor system, 不阻塞)
- [ ] Step 6: 多语言定稿
- [ ] Step 7: 合规最终扫描 (调 app-store-review-survival skill 二次扫)
- [ ] Step 8: 输出 release-report.json (扩展 schema)
- [ ] Step 9: 写完成信号
```

---

## Step 1: 前置 gate 检查

必须全部存在 + clearance 文件的 spec_hash 与当前 spec.md 一致:

```
.claude/state/clearance-anchor.json
.claude/state/clearance-shape.json
.claude/state/clearance-qa.json
.claude/state/check-report.json   (generic /check)
.claude/state/verify-report.json  (generic /verify + 本 skill /qa 已扩展)
.claude/state/release-report.json (generic /release, 必须 decision in {release-ready, ready-for-staging})
```

任一缺失/过期 → 阻塞, 提示对应 skill 重跑.

---

## Step 2: ASO 关键词定稿

写 `docs/spec.md` `## A-GATE 4 上架材料 → ASO 关键词` 子节:

**iOS:**
- `app_name`: ≤30 字符
- `subtitle`: ≤30 字符
- `keywords`: ≤100 字符总长, 逗号分隔, ≥5 独立词
- `description`: 4 行简介 (前 3 行在搜索结果显示)
- `promotional_text`: 170 字符 (随时可改, 不需 review)
- `whats_new`: 4000 字符, 每次发版更新

**Android (Google Play):**
- `short_description`: ≤80 字符
- `full_description`: ≤4000 字符
- `app_name`: ≤50 字符
- `tags`: 5 个

**多语言**: ≥3 种 (en / zh-Hans / 主目标市场), 每种独立定稿.

**关键词规则:**
- 不堆砌 (不重复同义词刷字符)
- 不含竞品名
- 不误导 (描述功能必须 app 实际有)
- 大小写敏感 (App Store 视 "App" 和 "app" 为不同词)

**机械验收**: `sg_app_aso_complete` 检测字段齐全 + 字符数限制.

---

## Step 3: 截图脚本就绪

**必须自动化**, 禁止手动截图 (文案改了重新截要 5 分钟内出图).

工具选择:
- iOS: `fastlane snapshot` (推荐) 或 Xcode UI Test
- Android: `fastlane screengrab` 或 Maestro
- React Native / Flutter: Maestro (跨平台)

**截图覆盖**:
- iPhone 6.5"+: 5-10 张
- iPad Pro 13": 5-10 张
- Android 手机: 5-10 张
- Android 平板 (可选): 5-10 张

**内容覆盖**: 启动 / 核心功能 / 付费墙 / 设置 / 关于 — 每个核心场景至少 1 张.

**机械验收**: `scripts/screenshots.sh` 或 `fastlane/Snapfile` 存在 + 一键可重跑.

---

## Step 4: 商店材料完整清单

调 `app-store-review-survival` skill 协助核对:

- 应用名称 (与 bundle id / 商店配置一致, sg_app_bundle_coherence)
- 副标题 / 简短描述 (跨语言)
- 完整描述 (订阅 App 必须含自动续费披露)
- 关键词字段
- 隐私问卷 (App Privacy questionnaire) — 数据收集类型清单
- 年龄分级问卷 (Apple + Google 双套)
- EULA URL (非 Apple 标准必填)
- 隐私政策 URL (强制)
- 演示账号 (Reviewer Demo Account): 引 spec.md `## 后端就绪` 演示账号字段
- 联系信息 / 支持 URL / 营销 URL
- What's New 文案 (每语言独立)
- Promotional Text

写入 `docs/store-materials/`, 每语言一个子目录.

---

## Step 5: 内容营销物料 (honor system)

不阻塞流程, 但**强烈建议**:
- 小红书首发文案 (中)
- X / Twitter 发布帖 (英)
- Reddit 相关 sub 帖子模板
- Product Hunt 提交准备
- 微信推文

写 `docs/marketing/`, AI 不验真, 用户打勾标记完成日期.

---

## Step 6: 多语言定稿

```
□ 截图脚本支持的所有语言 (en / zh-Hans / zh-Hant / ja / ko / es / pt-BR / 主目标市场)
□ 价格本地化 (App Store 价格层级 / Google Play 国家定价)
□ 节日 / 文化 / 法规适配 (例: 德国必须显示 VAT, 日本不显示 fractional 价格)
```

每语言独立审, 不靠机翻. 如时间紧, 至少 en + zh-Hans 完整, 其它先 deferred.

---

## Step 7: 合规最终扫描 (二次扫)

A-GATE 0 子产物 5 已扫一遍, /qa 又扫一遍, 上架前**再扫一遍** (代码 / 文案 / 截图 / 商店材料对账).

调 `app-store-review-survival` skill:

```bash
./scripts/ai-rules.sh skill-gate app-store-review-survival --check-only
```

**重点变化检测:**
- A-GATE 0 子产物 5 (合规扫描) 与当前实现是否漂离 (例: A-GATE 0 说不收集位置, 代码里偷偷申请了)
- 截图是否暴露真实用户数据 / 测试服 logo
- EULA / 隐私政策 URL 是否仍可访问且与商店材料一致
- iOS 17+: 隐私 manifest (`PrivacyInfo.xcprivacy`) 已配置
- Android: targetSdk 不低于 Play Console 当前要求
- build number 单调递增 (Apple 强制)

任一不过 → 阻塞提审.

---

## Step 8: 输出 release-report.json (扩展)

写入 `.claude/state/release-report.json` (覆盖 generic /release 输出, 增加 app 字段):

```json
{
  "decision": "ready-for-submit",
  "preflight_checks": {
    "aso_complete": true,
    "screenshot_script": true,
    "store_materials": true,
    "marketing_materials_honor": true,
    "multi_language": "en, zh-Hans (P0); ja, es (P1 deferred)",
    "compliance_rescan": "pass",
    "bundle_id_coherence": "pass",
    "generic_release_status": "release-ready"
  },
  "submission_blockers": [],
  "next_action": "human submits via App Store Connect / Play Console",
  "submission_at": "<TBD>",
  "timestamp": "<unix>"
}
```

`decision` 可能值:
- `ready-for-submit` — 全就绪, 用户可手动提审
- `blocked-by-<category>` — 某类未过, 阻塞清单写 `submission_blockers`
- `needs-human` — 涉及合规判断/商业决策, AI 不能决

---

## Step 9: 写完成信号

```bash
echo "{\"skill\":\"ship\",\"epoch\":$(date +%s)}" > .claude/state/skill-signal.json
```

---

## OUTPUT_GATE

由 `stop-app-audit.sh` 自动验收:
- release-report.json 存在 + decision 合法
- ASO 字段齐全 (字符数 + 关键词数)
- 截图脚本可执行
- store-materials/ 目录完整 (每语言子目录 + 必填项)
- 合规复扫 PASS

不通过 → 阻塞收尾, 列缺什么.

---

## 提审是人的工作, 不是 AI 的

AI 不上传 IPA / AAB, 不点击 "Submit for Review". AI 输出 `ready-for-submit` 后, **用户自己**:
1. 在 App Store Connect / Play Console 上传构建产物
2. 填 ASO 关键词 / 描述 (从 `docs/store-materials/` 拷)
3. 上传截图 (从 `scripts/screenshots/` 产物拷)
4. 提交审核

AI 在用户提交后可帮:
- 监控审核状态
- 处理被拒后的对账 (调 `app-store-review-survival` skill)
- 起草 reply 给审核员的文案

---

## 完成后下一步

`完成: /ship 已产出 ready-for-submit, 商店材料齐全, 等你在 App Store Connect / Play Console 提审`

或阻塞:

`停住: Step 7 合规复扫发现 PrivacyInfo.xcprivacy 缺 NSUserDefaults 字段, 修后重 /ship`

## weapp 分支(发布目标含微信小程序/小游戏时)

读 `.claude/rules/platform-weapp.md` §5/§7/§8:cli upload 传体验版;mp 后台提审=人工(类目/隐私保护指引/测试账号/审核备注)进 HUMAN 清单;
备案/版号/商户号未就绪=不可逆点硬卡(合规后置到此为止)。审核周期 1-7 天,排期留 buffer。

## 自建 Docker 后端上线(选型=自建时)

ship 阶段后端上线 = 跑 backend-forge「自建 Docker 部署」的 deploy.sh 真部署+健康检查绿+域名 https 可达;
服务器/DNS/TLS/registry 凭证未就绪 = HUMAN 硬前置(不可逆点,同提审待遇)。
