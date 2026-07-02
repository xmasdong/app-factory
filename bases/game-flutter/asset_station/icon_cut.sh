#!/usr/bin/env bash
# icon_cut.sh — 1024 母图 → iOS AppIcon 全尺寸 + 去 alpha(AppStore 硬约束)
# 用法: icon_cut.sh <母图1024.png> <输出目录(通常 ios/Runner/Assets.xcassets/AppIcon.appiconset)>
set -euo pipefail
SRC="${1:?用法: icon_cut.sh <母图.png> <输出目录>}"
OUT="${2:?缺输出目录}"
mkdir -p "$OUT"
# 去 alpha(拍到白底;母图本应满底无透明,这是兜底)
FLAT="$(mktemp -t icon_flat).png"
sips -s format png --setProperty formatOptions best "$SRC" --out "$FLAT" >/dev/null
# iOS 常用尺寸(single-size 时代 1024 即可,但兼容老配置切全套)
for SZ in 1024 180 167 152 120 87 80 76 60 58 40 29 20; do
  sips -z "$SZ" "$SZ" "$FLAT" --out "$OUT/icon_${SZ}.png" >/dev/null
done
echo "✓ 切出 $(ls "$OUT" | wc -l | tr -d ' ') 张 → $OUT(记得核 Contents.json 映射)"
