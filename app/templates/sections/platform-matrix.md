<!--
PLATFORM-MATRIX 章节模板 — A-GATE 1 必填
要求: 8 个能力维度逐行列出每端支持情况 + 具体 fallback 策略 + "不支持的端" 显式声明.
脚本 sg_app_platform_matrix 自动验证 (行数 ≥8, fallback 列非空, 不接受 "降级到 server-side" 一刀切).

为什么必填:
  ViraSnap 教训: 抠图只在 iOS Vision 跑通, Android ML Kit 没测试 → 上架 Play Store 后大量
  Android 用户抠图失败. 多端能力差异不是"实现细节", 是必须在 spec 阶段就拍死的产品决策.
  事到了 /impl 才发现某端不支持 = 用户故事失效 = 回 A-GATE 0 重算单位经济.

填写原则:
  1. iOS / Android 必填. 鸿蒙 / 小程序 / Web 按是否在产品计划内决定填或写 "不做"
  2. fallback 必须**具体**: "降级到 server-side" 不算填 (用户体验差异 + 成本差异不可忽略).
     合格示例: "iOS 17- → Vision Foundation, iOS 18+ → ImageAnalysisInteraction"
  3. 不支持的端必须显式声明 + 理由 (审核员 / 商务方会问)
  4. 单次决策放进 status.md FROZEN 锁定, 改 = 回 A-GATE 0
-->

## PLATFORM-MATRIX

> 8 个能力维度 × 5 个端的支持矩阵. 每行 fallback 必填.

| 能力 | iOS | Android | 鸿蒙 | 小程序 | Web | fallback 策略 |
|------|-----|---------|------|--------|-----|--------------|
| 1. 抠图 / 人脸检测 / AR / 视觉算子 | `<TBD: Vision>` | `<TBD: ML Kit>` | `<TBD: HMS Core>` | `<TBD: 不做>` | `<TBD: WASM>` | `<TBD: 设备不支持 → server-side onnx, 单次成本 $0.001>` |
| 2. 推送 (即时下发) | `<TBD: APNs>` | `<TBD: FCM>` | `<TBD: 华为推送>` | `<TBD: 订阅消息>` | `<TBD: Web Push>` | `<TBD: 国内 Android 无 Google Play → 走极光/小米/华为推送聚合>` |
| 3. 支付 / 订阅 | `<TBD: Apple IAP + StoreKit 2>` | `<TBD: Play Billing v6+>` | `<TBD: 鸿蒙 IAP>` | `<TBD: 微信支付>` | `<TBD: Stripe>` | `<TBD: 沙盒账号 / 用户区域限制, 国内 Android 不接 Play Billing → 微信支付>` |
| 4. 文件 / 相册 / 相机访问 | `<TBD: PhotoKit + 受限相册>` | `<TBD: SAF + READ_MEDIA_IMAGES>` | `<TBD: HMS Media>` | `<TBD: wx.chooseImage>` | `<TBD: <input file>>` | `<TBD: iOS 14+ 受限相册 / Android 13+ 分桶权限 / 拒绝授权 fallback 到示例图>` |
| 5. 网络 (HTTP / WebSocket / QUIC) | `<TBD: URLSession HTTP/3>` | `<TBD: OkHttp 5+ QUIC>` | `<TBD: HMS Network>` | `<TBD: 小程序 wx.request>` | `<TBD: fetch + WS>` | `<TBD: QUIC 不通 → 降级 HTTP/2, 弱网超时 30s + 重试 2 次>` |
| 6. 后台任务 / 唤醒 | `<TBD: BGTask + BGAppRefresh>` | `<TBD: WorkManager 周期任务>` | `<TBD: 鸿蒙后台任务>` | `<TBD: 小程序 background-fetch (限制多)>` | `<TBD: Service Worker>` | `<TBD: iOS 后台时长无保证 → 关键任务移到 server 端 cron>` |
| 7. 推送点击行为 / Deep Link | `<TBD: Universal Link + APNs payload>` | `<TBD: App Link + FCM data>` | `<TBD: 鸿蒙 deep link>` | `<TBD: 订阅消息跳转>` | `<TBD: URL handling>` | `<TBD: 主域名未配置 .well-known/apple-app-site-association → 退化为 custom scheme>` |
| 8. 收款资质 / 主体 | `<TBD: Apple Developer 个人/公司>` | `<TBD: Play Console 个人/公司>` | `<TBD: 华为开发者公司主体>` | `<TBD: 微信公众平台主体>` | `<TBD: Stripe Account>` | `<TBD: 个人开发者无法接微信支付 → 小程序端不做付费, 或走聚合支付>` |

---

### 不支持的端 (显式声明)

> 列出本次明确**不做**的端 + 理由. 不写 = 默认全端必做, /impl 阶段发现做不动 = 灾难.

- **小程序**: `<TBD: 不做, 因为核心功能依赖端侧 ML 推理, 小程序无 native module>`
- **鸿蒙**: `<TBD: 不做, 因为目标用户海外为主, 鸿蒙国内市占 <5%>`
- **Web**: `<TBD: 不做, 因为离线场景是核心卖点, Web 离线体验有限>`
- **iPad / 折叠屏 / 横屏适配**: `<TBD: 仅竖屏手机, 平板用 iPhone 模式运行>`

或者全做时写: "无不支持的端, 全 5 端覆盖"

---

### 跨端一致性 FROZEN 决策

> 涉及用户感知的功能, 哪些必须各端一致 / 哪些允许差异. 一旦锁定 = FROZEN, 改 = 回 A-GATE 0.

| 维度 | 一致性要求 | 备注 |
|------|----------|------|
| 数据展示格式 | 必须一致 (金额单位 / 时间格式 / 状态文案) | 见 §数据契约 |
| 核心功能可用性 | 各端最低支持版本下都必须可用 | 列出最低支持版本: iOS `<TBD>` / Android `<TBD>` |
| UI 风格 | 各端遵循平台 HIG, 但品牌色 / 关键交互一致 | 见 §DESIGN.md |
| 推送文案 | 各端文案一致, 但 payload 结构按平台差异 | iOS APNs aps.alert / Android FCM notification |
| 价格展示 | 各端价格阶梯 (Apple 90 元 / Google 65 元 / 微信 60 元) 必须**单调** | 见 §ECONOMICS |

---

### 验收硬规则 (sg_app_platform_matrix)

1. 必须 ≥ 8 行 (8 个能力维度), 缺一行直接阻塞
2. 每行 fallback 列非空, 不接受 "降级到 server-side" 一刀切
3. "不支持的端" 章节必须显式存在 (即使全做也要写 "无不支持的端")
4. 跨端一致性 FROZEN 决策必须存在 (价格阶梯单调由 sg_app_economics_monotone 验)
5. 与 SPEC §任务清单 PLATFORM 字段对账: 每个 PLATFORM=X 必须在矩阵中实际支持
