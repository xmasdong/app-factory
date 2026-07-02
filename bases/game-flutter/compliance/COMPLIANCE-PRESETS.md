# 合规预置(游戏基座)

> 定位=情报+现成件(合规后置,产出优先;硬校验在 ship 终扫)。

## 全年龄 4+ 非 Kids Category 姿势(默认推荐)
- 儿童画风 ≠ 儿童专属定位:TARGET_USER 写「全年龄/全家咸宜」,**不勾 Kids Category** → 避开 1.3 全套加码(家长门/无三方分析/广告限制)
- 4+ 分级问卷:无暴力/无恐怖/无赌博模拟/无无限制网络访问 → 全 None
- 若真要进 Kids Category:广告禁三方行为定向、分析 SDK 白名单、外链要家长门 —— 另立专项过审清单

## 单机无网络游戏最小合规面
- PrivacyInfo.xcprivacy ← 用同目录模板(无收集/无追踪/UserDefaults CA92.1)
- App Privacy 问卷:Data Not Collected(前提:真的一个请求都不发,包括崩溃统计)
- 无账号 → 删号 5.1.1(v) N/A;无 IAP → 3.1.2 订阅披露 N/A(spec 里显式标 N/A,别留空)
- 权限:一个都不申请就一个都别声明(Info.plist 不留幽灵 usage string)

## 有网络(如 AI 猜画)追加
- 数据出设备 → App Privacy 问卷如实勾(图片数据/用户内容);隐私政策 URL 必须真可访问
- 儿童可用 + 数据出设备 = 敏感组合:上传内容不含个人信息声明 + 尽量匿名化(无账号/无设备 ID 绑定)
- COMPLIANCE-RISKS 骨架:| 风险 | 拒因条款 | 处置 | 状态(打包进 status.md)
