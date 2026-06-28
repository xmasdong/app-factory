#!/bin/bash
# PreToolUse: Edit/Write — 编辑 UI 文件时提醒 AI 参照 DESIGN.md
#
# 原理: AI 写 .tsx/.vue/.css 时经常忽视 DESIGN.md, 用 system-ui + 默认样式.
#   此 hook 在 Edit/Write UI 文件时 stderr 注入 1 行提醒.
#   不阻塞 (exit 0), 仅提醒. 防抖: 同一文件 60 秒内不重复.

set -u
ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
DM="$ROOT/DESIGN.md"

# 无 DESIGN.md → 静默
[[ ! -f "$DM" ]] && exit 0

INPUT=$(cat 2>/dev/null || true)
FP=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FP" ]] && exit 0

# 只对 UI 文件触发
case "$FP" in
  *.tsx|*.jsx|*.vue|*.svelte|*.css|*.scss|*.less) ;;
  *) exit 0 ;;
esac

# 防抖 60s (同一文件)
STAMP_DIR="$ROOT/.claude/state/.design-remind"
mkdir -p "$STAMP_DIR" 2>/dev/null
BASENAME=$(basename "$FP" | tr '.' '_')
STAMP="$STAMP_DIR/$BASENAME"
NOW=$(date +%s)
if [[ -f "$STAMP" ]]; then
  LAST=$(cat "$STAMP" 2>/dev/null || echo 0)
  (( NOW - LAST < 60 )) && exit 0
fi
echo "$NOW" > "$STAMP"

# 提取 DESIGN.md 关键 token (前 5 个 CSS 变量) 供 AI 参考
TOKENS=$(grep -oE -- '--[a-zA-Z][a-zA-Z0-9-]+' "$DM" 2>/dev/null | head -5 | tr '\n' ' ')
if [[ -n "$TOKENS" ]]; then
  echo "UI 文件编辑: 参照 DESIGN.md token (${TOKENS}...). 颜色/间距/字号以 DESIGN.md 为准." >&2
else
  echo "UI 文件编辑: 参照 DESIGN.md 设计系统. 颜色/间距/字号以 DESIGN.md 为准, 不自由发挥." >&2
fi

exit 0
