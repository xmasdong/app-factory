# 微信小程序 / 小游戏 平台知识包(weapp)

> 工厂第三端形态(原生 app / API 后端之外)。**单一真源:各 gate SKILL 只引用本文,不复制。**
> 具体数字(包体积/抽成/门槛)随微信官方文档演进,标 ⚓ 的是锚点值,动手前以
> https://developers.weixin.qq.com/miniprogram/dev/framework/ 现值为准——数字对不上以官方为准,别信本文刻舟。

## 0. 先分清两个东西(选错=全错)

- **小程序(miniprogram)**:WXML/WXSS 页面栈应用 → 工具/内容/电商类走这
- **小游戏(minigame)**:无 WXML,canvas/WebGL 渲染,游戏引擎(Cocos Creator/Laya/Unity WebGL 转)→ games 线走这
- 两者审核类目、能力集、变现、体积规则都不同。discover/lockdown 第一步就要定型。

## 1. 架构要点(写码前必知)

- **双线程模型**:逻辑层(JS,无 DOM/window/document)+ 渲染层(WebView 或 Skyline),通信靠 `setData` 序列化——
  **setData 是性能命门**:单次 ⚓≤1MB、高频调用/大对象整传 = 卡顿主因;只 diff 传变化路径(`this.setData({'list[3].done':true})`)
- **包体积** ⚓:主包 2MB / 普通分包单个 2MB / 整包 30MB(小游戏:首包 4MB / 整包 30MB)。
  **体积预算是硬约束,shape 就要做分包规划**(主包只留首屏+骨架,其余分包+预下载;资产走 CDN 不进包)
- **页面栈 ⚓≤10 层**:navigateTo 有深度上限,超了必须 redirectTo/reLaunch——导航设计时算层数
- 尺寸单位 **rpx**(750rpx=屏宽);自定义组件体系;app.json 全局配置/页面 json 局部配置
- **网络白名单**:request/uploadFile/downloadFile/WebSocket 域名必须 https + ICP 备案 + 在 mp 后台逐个配置——
  **后端域名是前置人工动作**(HUMAN 清单),开发期用开发者工具"不校验域名"开关,上线前必须真配
- **Skyline 渲染引擎**(新):性能更好但组件兼容面窄,默认 WebView 稳妥;动画用 worklet
- 无热更新:发版必过审;`UpdateManager` 做强更提示

## 2. 账号体系与登录(与原生 app 完全不同)

- `wx.login()` → code → **服务端** `code2Session` → openid/session_key(**session_key 永不下发前端**)
- unionid:需绑定微信开放平台,跨小程序/公众号/App 同主体互认才有
- `getUserProfile` 已废弃 → 头像昵称用「头像昵称填写能力」(用户主动填)
- 手机号:「手机号快速验证组件」**企业主体专属且按次收费**——需要手机号的产品,主体决策提前做

## 3. 主体决策(lockdown 必答,影响面比技术选型大)

| 能力 | 个人主体 | 企业主体 |
|---|---|---|
| 微信支付/虚拟支付 | ❌ | ✅(需商户号) |
| web-view 组件 | ❌ | ✅ |
| 手机号获取 | ❌ | ✅(付费) |
| 可选类目 | 窄(游戏/工具/生活等) | 全 |
| 认证 | 无需 | 需(对公验证) |

- **ICP 备案** ⚓:新小程序须完成备案才能上架(2023.9 起)——花时间的人工前置,写进 HUMAN 清单
- **小游戏版号红线** ⚓:**内购变现需游戏版号;纯广告变现不需要**;软著建议备好。
  出海主线的 games 项目转小游戏 = 进国内监管域,economics 必须重算(这不是技术问题,是牌照问题)

## 4. 变现(economics 直接抄这里的约束)

- **iOS 端虚拟支付受苹果限制**:小程序 iOS 不能引导虚拟商品购买(连引导文案都会被拒)——
  双端变现模型必须分开算:安卓可内购,iOS 只能广告/实物/线下
- 广告(流量主):⚓需累计独立访客(UV)≥1000 才能开通;小游戏主流=激励视频(eCPM 看类目),banner/插屏辅助
- 虚拟支付抽成/渠道费:以官方现行协议为准(别拍脑袋填 economics 表)
- 订阅消息:模板消息已废弃;一次性订阅需用户点击触发授权——"推送唤回"能力远弱于原生 APNs,留存设计别依赖推送

## 5. 合规与审核红线(asr 小程序版)

- **隐私协议必填**:mp 后台《小程序用户隐私保护指引》+ 代码侧 `wx.requirePrivacyAuthorize`(涉及隐私接口先弹授权)
- **UGC 必接内容安全**:`msgSecCheck`(文本)/`mediaCheckAsync`(图片音视频)——不接=过审死+运营下架风险
- 类目资质:教育/医疗/金融/社交等需对应资质证照,discover 选品时就查(资质拿不到=方向直接毙)
- 审核高频拒因:诱导分享(强制转发才能玩)/诱导关注/iOS 虚拟支付引导/类目不符/隐私弹窗缺失/测试账号没给
- 灰度发布可用;审核周期不定(1-7 天),ship 排期留 buffer

## 6. 技术栈选型(tech-stack-decision 的 weapp 行)

- **原生小程序**(WXML/TS):AI-可建性最高(语料多),单端最稳 → 默认
- **Taro(React 语法)/ uni-app(Vue 语法)**:要"小程序+H5+App 多端同码"才值得上,单发小程序=白付抽象税
- **小游戏引擎**:Cocos Creator(主流,AI 语料够)> Laya;Unity WebGL 转小游戏体积/性能税重,慎选
- 云开发(TCB):个人/极简后端可用(云函数+云数据库),但锁定腾讯云;有自建后端能力时仍走自家 API

## 7. 工具链与工厂接线(preflight/build/qa/ship)

- **开发者工具 CLI**(env-probe 探测):macOS `/Applications/wechatwebdevtools.app/Contents/MacOS/cli`
  - `cli auto --project <path>` 自动化端口 / `cli preview` 真机预览二维码 / `cli upload --version x.y.z` 上传体验版
- **qa 回路 = miniprogram-automator**(npm 包):驱动开发者工具跑真页面——`automator.launch()` →
  `miniProgram.reLaunch('/pages/index/index')` → `page.$('selector')` → **`miniProgram.screenshot()`**。
  这是 weapp 版 sim-harness:截图喂 VLM 实证门照用;体验评分(Audits)面板出性能分
- 真机预览验证(preview 二维码扫码)= weapp 版"真机跑通";体积预算超标 = 构建失败级硬门
- ship:cli upload → mp 后台提审(**人工步骤:类目/隐私指引/审核备注+测试账号**,列 HUMAN 清单)

## 8. 工厂各关的 weapp 差异速查

| 关 | 差异动作 |
|---|---|
| preflight | 探测 devtools CLI + node;无 CLI → how_to_enable=装微信开发者工具并开服务端口 |
| discover | 定型:小程序 or 小游戏;类目资质预查;国内监管域提示(备案/版号) |
| lockdown | 主体决策(个人/企业)+ 备案/版号/商户号进 HUMAN 清单;命名查重=微信公众平台(不是 App Store);economics 按 §4 约束 |
| shape | 分包规划(体积预算表)+ 页面栈深度 ≤10 校验 + 数据契约标注 setData 热路径 |
| build | rpx/组件化/setData diff 纪律;体积预算随构建自检;域名白名单开发态豁免、上线态必配 |
| qa | miniprogram-automator 截图回路 + 体验评分 + 真机预览;内容安全接口联调(UGC 类) |
| ship | cli upload + mp 提审材料(隐私指引/类目/测试账号);审核红线自扫(§5) |
