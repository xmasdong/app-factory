<!--
NAMING-LOCK 章节模板 — A-GATE 0 必填
所有 6 个子节都必须 status: locked, 业务代码才能动笔.
evidence 指向 .claude/state/evidence/<hash>.txt (查重原文留底)
-->

## NAMING-LOCK

> 6 项命名锚 + 跨锚一致性. ViraSnap 教训: 域名买了 PawSnap → App Store 重名 → bundle id 已用 com.x.pawsnap → 仓库改名后 5 处错位上线不可逆.

### 1. 品牌名 (Brand Name)
- value: `<TBD>`
- evidence: `.claude/state/evidence/<TBD>.txt`  <!-- 商标局查询截图 + USPTO/CNIPA/EUIPO 搜索结果原文 -->
- checked_at: `<TBD: YYYY-MM-DD HH:MM>`
- status: `pending`  <!-- locked / pending -->
- 备注: <TBD: 同名风险评估, 是否注册 TM, 哪个 class>

### 2. 域名 (Domain)
- value: `<TBD>`  <!-- 如 example.app, 必须当下可注册或已注册 -->
- evidence: `.claude/state/evidence/<TBD>.txt`  <!-- whois 输出 + 注册商收据 -->
- checked_at: `<TBD>`
- status: `pending`
- 备注: <TBD: 备用域名 ≥1 个, 防主域名被抢注>

### 3. App Store 名 (iOS Listing Name)
- value: `<TBD>`  <!-- ≤30 字符. iTunes Connect Reserve 后填 -->
- evidence: `.claude/state/evidence/<TBD>.txt`  <!-- App Store search 截图证明无同名首位 + Reserve 邮件 -->
- checked_at: `<TBD>`
- status: `pending`
- 备注: <TBD: 副标题, 关键词差异化>

### 4. Play Store 名 (Android Listing Name)
- value: `<TBD>`  <!-- ≤30 字符 -->
- evidence: `.claude/state/evidence/<TBD>.txt`  <!-- Play Console reserve 截图 + Play Store search 截图 -->
- checked_at: `<TBD>`
- status: `pending`
- 备注: <TBD: 同 iOS 名是否一致 (品牌一致性 vs SEO 差异化)>

### 5. Bundle ID (Reverse-DNS 标识)
- value: `<TBD>`  <!-- 如 com.example.myapp. 一旦发布到 App Store/Play Store 永远不可改 -->
- evidence: `.claude/state/evidence/<TBD>.txt`  <!-- Apple Developer Identifier 注册截图 + Play Console package name 截图 -->
- checked_at: `<TBD>`
- status: `pending`
- 备注: <TBD: 与品牌名/域名 reverse-DNS 关系>

### 6. IAP Product ID Prefix
- value: `<TBD>`  <!-- 如 com.example.myapp.iap. 所有 in-app product 共享此前缀 -->
- evidence: `.claude/state/evidence/<TBD>.txt`  <!-- 命名规范文档 + 与 RevenueCat entitlement 映射表 -->
- checked_at: `<TBD>`
- status: `pending`
- 备注: <TBD: 命名约定: <prefix>.<period>.<tier>, 如 .month.basic / .year.pro>

---

### 跨锚一致性自检表

> commit 前 bundle id / package name / 品牌字符串必须在下列文件中**完全一致**.
> Hook `pre-commit-bundle-coherence.sh` 自动验证, 不一致直接阻塞 commit.

| 出现位置 | 文件路径 | 期望值字段 | 状态 |
|---------|---------|----------|------|
| iOS 主配置 | `ios/<App>/Info.plist` → `CFBundleIdentifier` | bundle id | `<TBD>` |
| iOS Entitlements | `ios/<App>/<App>.entitlements` → APS / IAP 配置 | bundle id | `<TBD>` |
| iOS 项目文件 | `ios/<App>.xcodeproj/project.pbxproj` → `PRODUCT_BUNDLE_IDENTIFIER` | bundle id | `<TBD>` |
| Android 主配置 | `android/app/build.gradle` → `applicationId` | bundle id | `<TBD>` |
| Android Manifest | `android/app/src/main/AndroidManifest.xml` → `package` | bundle id | `<TBD>` |
| Expo/React Native | `app.config.js` / `app.json` → `ios.bundleIdentifier`, `android.package` | bundle id | `<TBD>` |
| Flutter | `ios/Runner/Info.plist`, `android/app/build.gradle` | bundle id | `<TBD>` |
| RevenueCat | RevenueCat dashboard → Project → App 配置 | bundle id | `<TBD>` (honor system) |
| APNs 证书 | `*.p12` / `*.p8` 关联的 bundle id | bundle id | `<TBD>` (honor system) |
| Firebase / FCM | `google-services.json`, `GoogleService-Info.plist` | bundle id | `<TBD>` |
| DNS / 域名 | DNS provider → A/CNAME → 域名 value | 域名 | `<TBD>` (honor system) |

**status 字段含义:**
- `<TBD>` — 尚未确定, A-GATE 0 未过
- `OK` — 已写入文件且与 NAMING-LOCK value 一致 (机械检测)
- `pending-honor` — AI 无法验, 用户自报已配置 (RevenueCat / APNs / DNS / App Store Connect)

**重命名禁区:** 一旦 bundle id 已发布 (App Store TestFlight / Play Internal Testing 首次提交后), 不可改. 改 = 新 App = 全部用户重新下载. 此时若发现品牌冲突需重起项目 (见 `feedback_new_project_independence.md`).
