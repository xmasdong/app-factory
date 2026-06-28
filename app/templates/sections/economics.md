<!--
ECONOMICS 章节模板 — A-GATE 0 必填
要求: 单位成本表 + 反薅清单 ≥5 条 + 价格阶梯单调性 + 多区域定价占位
脚本 sg_app_economics_monotone 自动验证.
-->

## ECONOMICS

> ViraSnap 教训: $0.04/张 × 月配额 vs 订阅价 没事先算 → 用户狂刷 = 单 ARPU 倒贴.
> 月价 / 年价折月 / 月配额 必须单调递增, 否则白送配额.

### 单位成本 (Unit Cost)

> 列出**每一次用户操作**对应的后端单次成本. 不只 AI 调用费, 包括存储/带宽/推送/短信.

| 资源 | 单次成本 (USD) | 提供方 | 备注 |
|------|--------------|--------|------|
| 图像生成 (AI) | `<TBD: 0.04>` | `<TBD: OpenAI/Replicate>` | <TBD: 模型/参数> |
| 文本生成 (AI) | `<TBD: 0.0001>` | `<TBD>` | per 1K token, 估算 X token/次 |
| 对象存储 | `<TBD: 0.005>` | `<TBD: R2/S3>` | per GB·month, 估算 X MB/用户 |
| CDN 带宽 | `<TBD: 0.01>` | `<TBD>` | per GB, 估算 X 次访问 |
| 推送 (APNs/FCM) | `<TBD: 0>` | Apple/Google | 免费 (但 DAU 高需开 HTTP/2 实例) |
| 短信验证 | `<TBD: 0.04>` | `<TBD: Twilio>` | per SMS |
| 邮件 | `<TBD: 0.0001>` | `<TBD: SES/Postmark>` | per email |
| 数据库读写 | `<TBD: 0.0001>` | `<TBD: Supabase/Firebase>` | per request |
| 其他 | `<TBD>` | `<TBD>` | <TBD> |

### 月配额成本估算

> 假设用户用满配额, 单用户月成本是多少? 必须 < 订阅价 × 毛利目标 (建议 60%+).

| 套餐 | 月配额 (主资源) | 单次成本 | 月成本估算 (USD) | 订阅价 (USD) | 毛利率 |
|------|---------------|---------|---------------|------------|--------|
| 免费 | `<TBD: 5 张/月>` | `<TBD>` | `<TBD>` | 0 | N/A (拉新成本) |
| 月套 (basic) | `<TBD: 50 张/月>` | `<TBD>` | `<TBD>` | `<TBD>` | `<TBD: %>` |
| 月套 (pro) | `<TBD: 200 张/月>` | `<TBD>` | `<TBD>` | `<TBD>` | `<TBD: %>` |
| 年套 (basic) | `<TBD>` | `<TBD>` | `<TBD>` | `<TBD>` (年价/12) | `<TBD: %>` |
| 年套 (pro) | `<TBD>` | `<TBD>` | `<TBD>` | `<TBD>` (年价/12) | `<TBD: %>` |

### LTV vs CAC 估算

- 平均订阅周期 (月): `<TBD>` (行业经验值: 订阅类 App 4-8 个月)
- 月 ARPU: `<TBD>` (订阅价 × 转化率 + 广告/IAP)
- LTV: `<TBD>` (ARPU × 周期 × 毛利率)
- 目标 CAC: `<TBD>` (LTV/3 ~ LTV/4)
- 备注: <TBD>

### 价格阶梯单调性表

> **硬约束 (脚本验证):**
>   1. 月配额按套餐递增: free < monthly-basic < monthly-pro < yearly-pro (按月折)
>   2. **月配额/月价** (每美元能获得的配额数) 必须**单调递增** — 否则年套月配额 < 月套 = 用户反向选择 = 业务自杀
>   3. 年套折月价 < 月套月价 (常规价格策略, 否则年套无吸引力)

| 套餐 | 周期 | 价格 (USD) | 月配额 | 折月价 | 月配额/月价 |
|------|------|----------|--------|--------|------------|
| free | n/a | 0 | `<TBD: 5>` | 0 | ∞ (反薅风险, 见下) |
| monthly-basic | 月 | `<TBD: 4.99>` | `<TBD: 50>` | `<TBD: 4.99>` | `<TBD: 10.0>` |
| monthly-pro | 月 | `<TBD: 9.99>` | `<TBD: 200>` | `<TBD: 9.99>` | `<TBD: 20.0>` |
| yearly-basic | 年 | `<TBD: 39.99>` | `<TBD: 600>` (月均 50) | `<TBD: 3.33>` | `<TBD: 15.0>` |
| yearly-pro | 年 | `<TBD: 79.99>` | `<TBD: 3000>` (月均 250) | `<TBD: 6.67>` | `<TBD: 37.5>` |

> 自检: yearly-basic 月均配额 ≥ monthly-basic? yearly-pro 月均配额 ≥ monthly-pro? 月配额/月价 是否单调递增?

### 反薅漏洞清单 (≥5 条, 强制)

> ViraSnap 教训: 7 天免费试用没设防 = 用户开通 → 用满 → 退款 → 重开. 每条必须有具体防护策略.

1. **免费试用退款漏洞** — 用户试用 7 天用满配额后申请退款. 防护: <TBD: 试用期内配额上限 = 免费档配额 + 设备 ID 绑定首次试用记录, 退款过的设备不再发放试用>
2. **多设备共享同账号** — 一个订阅, 全家共享拉低 ARPU. 防护: <TBD: 同时在线设备数 ≤ N (App Store family sharing 例外), 后端 device_id session 强校验>
3. **看广告解锁重复触发** — 广告 callback 被前端篡改双花. 防护: <TBD: SSV (server-side verification), 广告平台签名校验 + 单次 token 防重放>
4. **多账号刷免费配额** — 注册 N 个账号每个领免费额. 防护: <TBD: 设备指纹 (IDFA/AAID + iCloud KeyValue) 反指认 + 手机号验证一次>
5. **越狱/Root 用户伪造 IAP** — 本地 receipt 伪造. 防护: <TBD: 服务端 Apple verifyReceipt / Google Play Developer API 校验, 永不信任客户端 receipt>
6. **后端配额校验滞后** — 客户端并发请求 N 次, 后端来不及扣配额. 防护: <TBD: 配额扣减用原子操作 (Redis INCR / DB SELECT FOR UPDATE), 客户端预占 + 后端结算>
7. <TBD: 自定义防护> — `<TBD>`

### 多区域定价

| 区域 | monthly-basic | monthly-pro | yearly-basic | yearly-pro | 备注 |
|------|--------------|-------------|--------------|-----------|------|
| US (Tier 5) | `<TBD: $4.99>` | `<TBD: $9.99>` | `<TBD: $39.99>` | `<TBD: $79.99>` | 基准定价 |
| EU | `<TBD>` | `<TBD>` | `<TBD>` | `<TBD>` | 含 VAT, App Store/Play 自动 |
| CN (人民币) | `<TBD: ¥18>` | `<TBD: ¥30>` | `<TBD: ¥128>` | `<TBD: ¥298>` | 价格敏感, 通常 50-60% US |
| JP (日元) | `<TBD: ¥500>` | `<TBD: ¥1000>` | `<TBD: ¥4000>` | `<TBD: ¥8000>` | 接近 US 价 |
| IN/BR/TR/EG | `<TBD>` | `<TBD>` | `<TBD>` | `<TBD>` | 新兴市场, 通常 30-40% US |

**注:** App Store Connect 自动按 Apple Pricing Matrix tier 映射, 但需明确选择 Base Tier. Play Console 同理. 单调性要求**在每个区域内**满足.
