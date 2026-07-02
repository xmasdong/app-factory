# bases/game-flutter — 游戏基座(v0 = 玩法无关层)

> ROADMAP-oneshot M3 产物。**范围声明:v0 只覆盖 Flutter widget-tree 游戏;Flame/canvas 实时族 out-of-scope。**
> 状态:juice_kit(质感件+状态屏件,tests 绿)+ asset_station + compliance 预置 + theme 模板 + **genre_turn_based 回合机插件**(反抽自首款回合制,tests 绿)+ **demo_skins/tapbird 换皮验证**(实时类,待用户签字)。

## juice_kit(local package,`flutter analyze` 零告警)

项目 pubspec 加:
```yaml
dependencies:
  juice_kit:
    path: <app-factory>/bases/game-flutter/juice_kit
```
| 件 | 干什么 |
|---|---|
| `BounceButton` | 按压回弹+触感+SFX,一个包装解决"按钮硬邦邦" |
| `Haptics` | 触感分级 light/medium/heavy/error/tick,全局开关 |
| `CelebrationController` + `CelebrationOverlay` | 猜对/过关一行 `fire()`:自绘彩带+重触感+correct 音+mascot 钩子 |
| `ScorePop` | 得分数字弹跳 |
| `JuicyRoute.slideUp/fade` / `PopIn` | 页面过渡/元素进场,禁硬切 |
| `JuicyTimerRing` | 环形倒计时,最后 10 秒自动变色+脉冲 |
| `Sfx` | SFX 槽:默认系统点击音,项目可注入真 player;**BGM 不做**(价值函数) |

## asset_station(资产工位)

风格漂移是已交学费的硬问题(game-asset-lab):**prompt ≠ 一致输出**。工位三板斧:
1. **key art 先行**(`prompts/style-genes.md` 第 0 条)锁风格基因
2. 其余全部 `--image key-art` 参考生成(image-to-image)
3. **identity_qc**:每张出完 VLM 判一致性,不过 autoretry ≤2

```bash
export STYLE="children's crayon drawing, wobbly outlines, warm paper texture"   # 从 DESIGN-FEED 取
bases/game-flutter/asset_station/make_assets.sh <项目根>
bases/game-flutter/asset_station/icon_cut.sh <项目根>/assets/art/icon-master.png ios/Runner/Assets.xcassets/AppIcon.appiconset
```
产出:key-art / icon 母图 / 背景纹理 / 庆祝贴纸 / mascot×3 表情 + manifest.json。
**接线才算配套**:pubspec 声明 + 代码引用(`sg_app_game_feel` 会验)。

## genre_turn_based(回合制插件,local package)

`RoundMachine<P>`:idle→playing→resolving(可异步)→result→ended;`PromptPool` 接口(词/关卡/题);计分/连击/回合上限;**异步判定序号守卫**(在途取消/迟到响应静默丢弃——反抽自"让 AI 猜"场景)。`onCorrect` 直接接 `CelebrationController.fire`。
⚠️ n=1 泛化:第二款回合制接入时校准,别当万能。实时类玩法**不要**硬套(用 Ticker 自己写循环,见 demo)。

## demo_skins/tapbird(换皮验证)

实时点按飞行类(刻意≠反抽来源的回合制)+ 纸剪贴风(刻意≠首款蜡笔风)——双重验证基座的玩法/风格无关性。全程基座件,`flutter analyze` 零告警。跑法:`cd demo_skins/tapbird && flutter run`。
