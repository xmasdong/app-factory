# 风格基因 prompt 包(资产工位)

> 用法:先出 key art 锁风格,后续一切图用 `--image <key-art>` 参考生成(image-to-image 锁基因)。
> `{STYLE}` 槽从 DESIGN-FEED 的风格基因段填(如 "children's crayon drawing, wobbly outlines, warm paper texture, sticker-like")。
> 每张出完过 identity_qc(VLM 问一致性),不过 autoretry ≤2 —— 学费来自 game-asset-lab。

## 0. KEY ART(先行,唯一不带参考的)
Key art for a mobile game, {STYLE}. Main character/mascot centered, background showing the game's world/mood, square 1024. No text, no UI, no watermark.

## 1. App 图标(母图 1024,后续 icon_cut.sh 切全尺寸)
App icon, {STYLE}. Single centered subject from the key art, bold silhouette readable at 60px, bright saturated background filling the full square, NO alpha/transparency, no text.

## 2. 启动屏
Launch screen background, {STYLE}. Calm composition from key art world, safe empty center area for logo, portrait 1290x2796.

## 3. 背景纹理(质感地基)
Seamless-ish background texture, {STYLE}. Subtle, low-contrast so UI reads on top. Portrait phone.

## 4. 按钮贴纸(每色一张或一张多态)
Sticker-style button plate, {STYLE}. Rounded hand-drawn border, soft drop shadow, blank center for label, transparent background PNG.

## 5. 庆祝元素(confetti 补充件/奖杯/星星)
Celebration sticker set on transparent background, {STYLE}: stars, trophy, party elements. Matching the key art palette.

## 6. Mascot 表情集(≥3:常态/庆祝/失败)
Mascot from the key art, {STYLE}, same identity, transparent background: (a) neutral idle pose (b) celebrating cheering pose (c) sad/oops pose. One per generation, use key art as identity reference.

## identity_qc 问法(VLM)
"这张图和参考 key art 是同一款游戏的同一美术风格吗?配色/线条/质感一致吗?只答 YES/NO+一句原因。"
