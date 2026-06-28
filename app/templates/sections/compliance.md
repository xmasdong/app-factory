<!--
COMPLIANCE 章节模板 — A-GATE 0 必填, A-GATE 4 复扫
8 项必填, 任一空白或 status: pending → /ship 拒绝执行.
顺序就是 Apple/Google 审核员的扫描顺序, 按顺序落地最稳.
末尾"引用外部 skill"段强制调用 app-store-review-survival 做最终扫描.
-->

## COMPLIANCE

> 8 项合规锚, 每项必须有"时机标注"(在哪个用户路径上展示) + 文案 + 状态.
> 实证教训: themeWeek / ViraSnap 反复被拒不是因为没做, 而是做的时机错 — 网络授权在隐私协议同意前请求, 直接 5.1.1 拒.

---

### 1. 隐私政策 URL (Privacy Policy URL)
- url: `<TBD: https://example.com/privacy>`  <!-- 必须 200 OK, 不能是 404/邮件链接/邮箱地址 -->
- 时机: **App 进入第一屏之前展示**, 不是埋在设置里
  - 必填位置 A: ASC → App Information → Privacy Policy URL
  - 必填位置 B: 应用内 Settings → Privacy Policy (功能性链接)
  - 必填位置 C: 订阅页 / 付费墙 (3.1.2 强制)
- 内容必含: 数据类目 / 设备本地 vs 服务器处理声明 / 儿童条款 (COPPA/GDPR Art.8) / 联系邮箱 / 最后更新日期
- evidence: `.claude/state/evidence/<TBD>.txt`  <!-- 访问 URL 的 curl 响应 + content hash -->
- status: `pending`  <!-- locked / pending -->

### 2. EULA URL (终端用户许可协议, 订阅 app 必填)
- url: `<TBD>`  <!-- 默认: Apple Standard EULA https://www.apple.com/legal/internet-services/itunes/dev/stdeula/ -->
- 适用条件: 应用有任何 IAP / 订阅 / 一次性买断的数字商品
- 时机: 订阅页和 App Description 都必须有, 缺一个就 3.1.2(c) 拒
  - ASC → App Information → EULA (默认留空 = 用 Apple Standard)
  - 应用内付费墙 (必须可点开链接)
  - App Description 长文末尾 (审核员有时漏看应用内链接, 在描述里也放一遍)
- 自定义 EULA 必填条款: 自动续费 / 取消路径 / 退款政策 / 适用法律
- status: `pending`

### 3. 删除账号路径 (5.1.1(v) 强制)
- 实现位置: **应用内自助删除** — 不能"联系客服" / "发邮件给我们"
  - 路径: Settings → Account → Delete my data / Delete account
  - 可见性: 不能埋在 3 层菜单以下
- 实现要求:
  - 二次确认弹窗 (红色 destructive 按钮)
  - 删除范围: shared_preferences / NSUserDefaults / Keychain / 本地缓存 / 内存状态 / 服务端账户
  - 删除后重置同意状态 → 重新走 onboarding (Apple 实测会复跑这一步)
- 适用范围: 任何账号系统 / 注册流程 / 持久登录 / 持久本地用户 ID (即使纯离线 app 有持久用户 ID 也算)
- evidence: `.claude/state/evidence/<TBD>.txt`  <!-- 录屏 / GIF, 从入口点到删除完成的完整路径 -->
- status: `pending`

### 4. GDPR Consent 实现 (欧盟用户)
- 实现位置: 首次启动检测地理位置 / Locale = EU 时, 全屏 consent 屏幕
- 触发逻辑: 用 IP 区域 或 device locale, 二选一. 不能省略 (Apple 通过 metadata 检查 EU 支持)
- consent 屏幕内容必含:
  - 数据用途清单 (analytics / crash / 个性化 / 第三方分享)
  - 每类用途单独 opt-in 开关 (不能"全打勾")
  - "拒绝"和"接受"按钮等大, 拒绝不能引导到死路
  - 链接到完整隐私政策
- EU 跳转 URL (用户后续修改 consent): `<TBD: Settings → Privacy → Manage data consent>`
- 状态存储位置: 服务端 + 本地双写, 删除账号时清空
- status: `pending`

### 5. ATT 弹框文案 (App Tracking Transparency, iOS 14.5+)
- 文案 (purpose string in Info.plist): `<TBD>`
  - **必须具体**, 不能写"改善体验" / "提供更好服务" — 这种文案 100% 被 5.1.1 拒
  - 必须说: **采集啥** + **给谁** + **为啥**
  - 示例可用: "<App> uses your device identifier to measure ad performance for our analytics partner and to limit how often you see the same ad."
- 触发时机:
  - 首次启动 onboarding 完成后 (不在第一屏弹, 用户还没建立信任)
  - 在 consent 屏 (隐私同意) 之后
  - 在任何网络请求触发 IDFA 之前
- 字段名: `NSUserTrackingUsageDescription`
- 多语言: 每个 supported language 的 `<lang>.lproj/InfoPlist.strings` 必须有对应翻译, 英文兜底
- status: `pending`

### 6. Kids/COPPA 分类自检
- 目标用户年龄: `<TBD: 13+ / 全年龄 / 4-12 kids>`
- 自检清单:
  - [ ] App Store Connect → App Information → "Made for Kids" toggle = OFF (除非真做 kids app)
  - [ ] 主类目不是 Kids (除非真做 kids app — 见 app-store-review-survival 1.3 教训)
  - [ ] **拍照 / 相册 / 相机 / 位置 / 第三方链接 / 社交分享 / 任何形式的 IAP (除家长门) 任一存在 → 永不可选 Kids 类**
  - [ ] 如果 13 岁以下是用户群之一: App Description 措辞 "general audience, also enjoyed by..." 而非 "designed for children"
  - [ ] 数据采集策略: 13 岁以下用户绝不采集 IDFA / 精确位置 / 个人识别信息
- COPPA 合规 (美国 13 岁以下): 父母同意流程 (verifiable parental consent), 仅当主动定位 kids 时强制
- evidence: `.claude/state/evidence/<TBD>.txt`  <!-- ASC 后台截图 -->
- status: `pending`

### 7. 网络授权时机 (隐私协议同意后才能请求, ViraSnap 在此踩坑 3+ 轮)
- 硬规则: 首次启动到隐私协议接受前, **零网络请求**.
  - 包括: analytics SDK init / crash report / remote config / 第三方 SDK 自动联网
  - 包括: bundle id 上报 / device ID 上报 / 实验组分配
- 实现位置: gate 在 `MaterialApp.builder` (Flutter) / `application(didFinishLaunching)` (iOS) / `MainActivity.onCreate` (Android)
  - 隐私同意未接受 → 跳过所有 SDK init
  - 接受后 → 触发 init 链 + 重启数据采集
- 第三方 SDK 检查清单 (常见自动联网项, 必须延迟初始化):
  - [ ] Firebase Analytics
  - [ ] Sentry / Crashlytics
  - [ ] Mixpanel / Amplitude / PostHog
  - [ ] RevenueCat (configure 不算联网, 但 fetchOfferings 算)
  - [ ] AppsFlyer / Adjust / Branch
- evidence: `.claude/state/evidence/<TBD>.txt`  <!-- Charles/Wireshark 抓包, 同意前 0 个出站请求 -->
- status: `pending`

### 8. 权限文案 (相册/相机/位置/通知 等 NS*UsageDescription)
- 每个用到的 `NS*UsageDescription` 必须**具体到本 app 用途**, 不能模板话术
- 必填 key (按使用的能力勾选):
  - [ ] `NSCameraUsageDescription` — 文案: `<TBD>`
  - [ ] `NSPhotoLibraryUsageDescription` — 文案: `<TBD>`
  - [ ] `NSPhotoLibraryAddUsageDescription` — 文案: `<TBD>` (写入相册才需要)
  - [ ] `NSMicrophoneUsageDescription` — 文案: `<TBD>`
  - [ ] `NSLocationWhenInUseUsageDescription` — 文案: `<TBD>`
  - [ ] `NSLocationAlwaysAndWhenInUseUsageDescription` — 文案: `<TBD>` (后台位置才需要, 99% 的 app 不该用)
  - [ ] `NSContactsUsageDescription` — 文案: `<TBD>`
  - [ ] `NSCalendarsUsageDescription` — 文案: `<TBD>`
  - [ ] `NSFaceIDUsageDescription` — 文案: `<TBD>`
  - [ ] `NSUserTrackingUsageDescription` — 见第 5 项
- 文案模式: 动词 + 具体功能 + 不采集承诺 (示例: "用相机扫描收据上的二维码, 不会上传到服务器")
- Android 对照 (`AndroidManifest.xml` permission rationale): 同样要具体, 不能 "需要权限"
- 多语言: 每个 supported language 的 `<lang>.lproj/InfoPlist.strings` + Android `res/values-<lang>/strings.xml`
- status: `pending`

---

### 引用外部 skill (强制)

A-GATE 4 最终扫描必须调用 generic 已有 skill `app-store-review-survival` 跑完整 pre-submission checklist:

```bash
# 在 /ship 流程的 Step 7 (合规最终扫描) 中调用
# skill 路径: ~/.claude/skills/app-store-review-survival/SKILL.md
# 调用方式: AI 主动加载该 skill, 对照其 Pre-submission Checklist 9 个分节 (A-I) 逐项过
# 输出: 每个分节 PASS / FAIL / N_A (理由), 写入 .claude/state/asr-survival-scan.json
```

**为什么不在这里复制 skill 内容:**
- app-store-review-survival 维护频率高 (Apple guideline 月度更新), 复制会过期
- 本章节负责"为本项目锚定 8 项答案", skill 负责"对照最新 guideline 扫描所有可能拒因"
- 两者职责互补: 本章节是答题卡, skill 是阅卷标尺

**机械验收 (`sg_app_compliance_scan` 函数):**
1. 本章节 8 项全部 `status: locked` (不能有 `pending`)
2. 每项 evidence / url / 文案字段非空 (不能是 `<TBD>` 占位)
3. `.claude/state/asr-survival-scan.json` 存在且 `decision: ready-for-submit`
4. `asr-survival-scan.json` 不旧于本章节最后一次修改 30 分钟 (防陈旧扫描结果)

**冻结边界:**
所有 8 项一旦 `status: locked` 即进入 FROZEN. 修改需走 GATE 0 重新评估 + 影响评估 (列出所有依赖此决策的代码路径).
特别地: 删除账号路径修改 = 重新过 Apple 审核; ATT 文案修改 = 重新本地化全部语言.
