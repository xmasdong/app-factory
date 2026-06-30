#!/usr/bin/env bash
# ui-snapshot.sh — 渲染实现并截图(供 visual-diff.mjs 比对)。按目标端 dispatch。
# 用法: ui-snapshot.sh <web|ios|flutter> <out-dir> [url 或 scheme]
set -euo pipefail
PLATFORM="${1:?usage: ui-snapshot.sh <web|ios|flutter> <out-dir> [url|scheme]}"
OUT="${2:?out dir}"; TARGET="${3:-}"
mkdir -p "$OUT"
case "$PLATFORM" in
  web)     command -v npx >/dev/null || { echo "需 npx/playwright" >&2; exit 3; }
           npx playwright screenshot --full-page "$TARGET" "$OUT/screen.png" ;;
  ios)     command -v xcrun >/dev/null || { echo "需 Xcode/simctl" >&2; exit 3; }
           xcrun simctl io booted screenshot "$OUT/screen.png" ;;
  flutter) command -v flutter >/dev/null || { echo "需 flutter" >&2; exit 3; }
           flutter screenshot --out="$OUT/screen.png" ;;
  *) echo "未知端 $PLATFORM (web|ios|flutter)" >&2; exit 2 ;;
esac
echo "截图 → $OUT/screen.png"
