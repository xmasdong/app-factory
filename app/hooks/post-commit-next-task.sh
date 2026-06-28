#!/bin/bash
# Post-commit hook: commit 完成后注入"下一步"提醒
# 作用：消除 AI 在任务间续接处"礼貌性询问"的 reflex
#
# 原理：
#   PostToolUse 钩子，匹配 `git commit *`
#   调用 ai-rules.sh next-task 生成提示
#   exit 2 + stderr 会被 Claude Code 作为 tool result addendum 回灌到模型上下文
#   → 相当于强制 system-reminder，比 CLAUDE.md 规则权重更高

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)

# 只拦截 git commit（且排除 --amend，amend 不是推进任务链）
if ! echo "$COMMAND" | grep -q "^git commit"; then
  exit 0
fi
if echo "$COMMAND" | grep -q -- "--amend"; then
  exit 0
fi

# 只在 commit 实际成功时注入（tool_response 无错误）
TOOL_ERROR=$(echo "$INPUT" | jq -r '.tool_response.is_error // false' 2>/dev/null)
if [[ "$TOOL_ERROR" == "true" ]]; then
  exit 0
fi

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SCRIPT="$ROOT/scripts/ai-rules.sh"

# 脚本不存在则静默（graceful degradation）
[[ ! -x "$SCRIPT" ]] && exit 0

# commit 成功 → 有进展 → 软重置熔断计数
"$SCRIPT" fuse reset --soft 2>/dev/null || true

MSG=$("$SCRIPT" next-task 2>/dev/null)

# 无消息 → 静默放行
if [[ -z "$MSG" ]]; then
  exit 0
fi

# 有消息 → 写 stderr + exit 2，Claude Code 会把 stderr 作为上下文回灌
# 同时落盘到 .claude/state/hook-log.jsonl 供事后审计（Claude Code 不持久化 blocking hook 的 stderr）
LOG_DIR="$ROOT/.claude/state"
mkdir -p "$LOG_DIR" 2>/dev/null
LOG_FILE="$LOG_DIR/hook-log.jsonl"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# 用 jq 生成安全的 JSON（消息含换行和中文）
if command -v jq >/dev/null 2>&1; then
  jq -nc --arg ts "$TS" --arg hook "post-commit-next-task" --arg msg "$MSG" \
    '{ts:$ts, hook:$hook, msg:$msg}' >> "$LOG_FILE" 2>/dev/null || true
fi

SUMMARY=$(echo "$MSG" | head -1 | cut -c1-120)
# shellcheck disable=SC1091
source "$(dirname "$0")/_lib.sh"
emit_blocked "post-commit-next-task" "$SUMMARY" "$MSG"
exit 2
