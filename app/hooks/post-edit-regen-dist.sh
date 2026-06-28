#!/bin/bash
# PostToolUse: Edit/Write — 源文件改动时自动 regen dist/install.sh
#
# 目的: 防止 build-install.sh 被忘, 导致 dist/install.sh 落后于源, 消费项目装到陈旧脚本.
# 防抖: 5 秒窗口内不重复跑 (连续多次 Edit 只触发一次).
# 失败不阻塞 AI (异步后台 + 日志).

set -u
ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
BUILD="$ROOT/scripts/build-install.sh"

[[ ! -x "$BUILD" ]] && exit 0

INPUT=$(cat 2>/dev/null || true)
FP=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FP" ]] && exit 0

# 命中源文件集才触发 (集合必须与 build-install.sh 头部源列表一致)
case "$FP" in
  "$ROOT"/CLAUDE.md) ;;
  "$ROOT"/.claude/rules/*.md) ;;
  "$ROOT"/.claude/skills/*/SKILL.md) ;;
  "$ROOT"/scripts/ai-rules.sh) ;;
  "$ROOT"/scripts/quality-gate.sh) ;;
  "$ROOT"/scripts/release-gate.sh) ;;
  "$ROOT"/scripts/.env.quality-gate.example) ;;
  "$ROOT"/.claude/hooks/*.sh) ;;
  *) exit 0 ;;
esac

# 防抖 5s
STAMP="$ROOT/.claude/state/.last-regen-dist"
mkdir -p "$(dirname "$STAMP")" 2>/dev/null
NOW=$(date +%s)
if [[ -f "$STAMP" ]]; then
  LAST=$(cat "$STAMP" 2>/dev/null || echo 0)
  (( NOW - LAST < 5 )) && exit 0
fi
echo "$NOW" > "$STAMP"

# 后台跑, 日志落盘, 不阻塞 AI
LOG="$ROOT/.claude/state/build-install.log"
(
  if bash "$BUILD" > "$LOG" 2>&1; then
    echo "[regen-dist ok] $(date '+%Y-%m-%d %H:%M:%S') trigger=$FP" >> "$LOG"
  else
    echo "[regen-dist FAIL] $(date '+%Y-%m-%d %H:%M:%S') trigger=$FP see $LOG" >&2
  fi
) &

exit 0
