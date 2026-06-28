#!/bin/bash
# UserPromptSubmit hook: 交付模式下注入 tail-marker 提醒
#
# 原理: 预防 > 惩罚.
#   Stop hook 在 AI 忘写标记后阻塞 → 用户看到 "Stop hook error" 噪音.
#   此 hook 在 AI 写回复前注入 1 行提醒 → AI 一次写对 → Stop hook 不触发 → 零噪音.
#
# 只在交付模式生效 (status.md 存在 + 有待办任务). 无交付流时静默.

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# 非交付模式: 静默
[[ ! -f "$ROOT/docs/status.md" ]] && exit 0
grep -qE '^\s*-\s*\[ \]' "$ROOT/docs/status.md" 2>/dev/null || exit 0

echo "回复末尾须带结束标记 (独占最后一行): \`完成:\` / \`等你:\` / \`停住:\`"
exit 0
