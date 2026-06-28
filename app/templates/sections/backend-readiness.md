<!--
BACKEND-READINESS 章节模板 — A-GATE 0 必填
ViraSnap 教训: Cloudflare Workers / RevenueCat / APNs 全程边搭边问. /impl 第一周浪费在配凭证.
每项是 checkbox + 日期 (honor system). 脚本验证 ≥6 项打勾才放行 A-GATE 0.
-->

## BACKEND-READINESS

> 所有"AI 无法代办"的后端基础设施清单. 用户必须亲自完成并打勾 + 写日期.
> 仅勾未填日期视为未完成. 至少 6 项打勾才能进入 /impl.

### 1. 云服务账号 (选一并 commit)

> 主后端的承载平台. 一次选好, 后续不轻易换 (迁移成本极高).

- [ ] **Cloudflare Workers** — 注册账号 + 添加付款方式 — 完成日期: `<TBD: YYYY-MM-DD>`
- [ ] **Supabase** — 注册账号 + 创建 organization — 完成日期: `<TBD>`
- [ ] **Firebase / Google Cloud** — 创建 project + 启用付款 — 完成日期: `<TBD>`
- [ ] **AWS** — 注册账号 + IAM 子用户 — 完成日期: `<TBD>`
- [ ] **自建 VPS** — 服务器准备 + SSH 密钥配置 — 完成日期: `<TBD>`
- [ ] **其他** (`<TBD>`) — 完成日期: `<TBD>`

> 选择记录: 本项目使用 `<TBD>`. 原因: `<TBD: 价格/熟悉度/团队约束>`.

### 2. CLI 登录 (本机)

> AI 不能用 OAuth flow 替你登录. 完成后 AI 才能直接 deploy/migrate.

- [ ] `wrangler login` (Cloudflare) — 验证: `wrangler whoami` 返回邮箱 — 完成日期: `<TBD>`
- [ ] `supabase login` — 验证: `supabase projects list` 不报权限错 — 完成日期: `<TBD>`
- [ ] `firebase login` — 验证: `firebase projects:list` 显示项目 — 完成日期: `<TBD>`
- [ ] `aws configure` + IAM Access Key — 验证: `aws sts get-caller-identity` — 完成日期: `<TBD>`
- [ ] `gh auth login` (GitHub, 用于 Actions) — 完成日期: `<TBD>`

### 3. 数据库 / 存储 / 队列 服务创建

- [ ] **数据库** (Postgres/MySQL/D1/Firestore/DynamoDB) — 创建 + connection string 写入 `.env` — 完成日期: `<TBD>`
- [ ] **对象存储** (R2/S3/GCS/Supabase Storage) — bucket 创建 + 公开/私有策略配置 — 完成日期: `<TBD>`
- [ ] **队列/异步** (Cloudflare Queues / SQS / Cloud Tasks, 如需要) — 完成日期: `<TBD>`
- [ ] **KV 缓存** (Redis / Upstash / Cloudflare KV, 如需要) — 完成日期: `<TBD>`
- [ ] **初始 schema 已 migrate** (跑过一次) — 验证: 表存在 — 完成日期: `<TBD>`

### 4. 域名 DNS 配置 + SSL

- [ ] **域名注册商** (Namecheap/Cloudflare/Google Domains) — 已购买 NAMING-LOCK 中的域名 — 完成日期: `<TBD>`
- [ ] **DNS 指向后端** (A/CNAME 记录) — 验证: `dig <域名>` 返回正确 IP — 完成日期: `<TBD>`
- [ ] **SSL 证书激活** (Let's Encrypt / Cloudflare Universal / ACM) — 验证: `curl -I https://<域名>` 返回 200 + 有效证书 — 完成日期: `<TBD>`
- [ ] **www subdomain 处理** (重定向或独立) — 完成日期: `<TBD>`

### 5. 支付 (IAP / 订阅)

> Apple/Google IAP 配置极其细致, AI 无法点 App Store Connect UI. 这里是最容易卡几天的环节.

- [ ] **Apple IAP** — App Store Connect 创建 App + 添加 IAP product (与 NAMING-LOCK Section 6 prefix 一致) — 完成日期: `<TBD>`
- [ ] **Apple IAP Shared Secret** — App-Specific Shared Secret 已生成并写入后端 `.env` 的 `APPLE_IAP_SHARED_SECRET` — 完成日期: `<TBD>`
- [ ] **Apple Sandbox 测试账号** — 至少 2 个 (一个未付费, 一个已付费, 重置过订阅) — 完成日期: `<TBD>`
- [ ] **Google Play Billing** — Play Console 创建 subscription product + base plans + offers — 完成日期: `<TBD>`
- [ ] **Google Play Service Account** — JSON key 已生成并写入后端 `.env` 的 `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` — 完成日期: `<TBD>`
- [ ] **RevenueCat** (如使用) — 项目创建 + Apple/Google App 关联 + Entitlements 定义 + Webhook 指向后端 — 完成日期: `<TBD>`
- [ ] **Stripe** (如有 Web 付款) — Account 激活 + Restricted Key 写入后端 — 完成日期: `<TBD>`

### 6. 推送通知

- [ ] **APNs Auth Key (.p8)** — 生产 + Sandbox 都生成, key id + team id 记录到 `.env` — 完成日期: `<TBD>`
- [ ] **APNs Topic** = bundle id (与 NAMING-LOCK 一致) — 验证 — 完成日期: `<TBD>`
- [ ] **FCM Project** — server key 生成 + 写入后端 — 完成日期: `<TBD>`
- [ ] **测试推送已发通** — 自己手机收到一条 hello world 推送 — 完成日期: `<TBD>`

### 7. 监控 / 日志 / 报警

- [ ] **Sentry** (或 Crashlytics / Bugsnag) — Project 创建 + DSN 写入 client + 已收到一条测试 error — 完成日期: `<TBD>`
- [ ] **后端日志收集** (Cloudflare Logs / CloudWatch / Stackdriver / 自建) — 可查询 — 完成日期: `<TBD>`
- [ ] **关键报警通道** (Slack/邮件/PagerDuty) — 触发一次测试 alert — 完成日期: `<TBD>`
- [ ] **uptime monitoring** (UptimeRobot / Better Stack, 如需要) — 完成日期: `<TBD>`

### 8. App 审核员演示账号

> Apple/Google 审核员登录需要的演示账号. 不能给"创建账号就送 100 张配额"这种会绕过付费墙的初始资源.

- [ ] **审核员账号已创建** — 邮箱: `<TBD>` (建议格式 `appreview+<random>@<域名>`) — 完成日期: `<TBD>`
- [ ] **审核员账号密码已设置** — 密码: `<TBD: 写在 App Store Connect Review notes, 不写本仓库>` — 完成日期: `<TBD>`
- [ ] **初始资源不绕过付费墙** — 该账号默认只有免费档配额 (不允许预充值 / 不允许 entitlement override) — 自查通过日期: `<TBD>`
- [ ] **审核员引导路径已写入 Review notes** — App Store Connect → App Review Information → Demo Account — 完成日期: `<TBD>`
- [ ] **测试: 审核员账号能完成最小功能演示** — 自查 — 完成日期: `<TBD>`

---

### 完成度统计 (Hook 自动计数)

> 脚本扫 `- [x]` 计数. **至少 6 项打勾**才放行 A-GATE 0. 这是粗糙阈值,
> 实际项目根据后端复杂度自行调整 (纯前端 App + Firebase 简单, 自建后端可能 ≥15 项).

- 当前完成: `<TBD: N>` / 总项数 ~30
- 阈值: ≥6 (默认), `<TBD: 自定义>` (建议根据项目复杂度)

### 提醒

- 这些**全是 honor system**: AI 无法登录你的账户验账号是否真存在.
- AI 在 /impl 中遇到无法继续的步骤 (如缺 token) → 不应"边搭边问", 应回 A-GATE 0 补充清单.
- "前置已就绪"声明前, 强烈建议跑一次 `./scripts/bootstrap.sh --preflight` (如有), 一次性验所有凭证可用.
