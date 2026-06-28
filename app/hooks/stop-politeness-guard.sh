#!/bin/bash
# Stop hook: allow-list 校验 AI 最后一条消息是否以合法结束标记收尾
#
# 收敛思路:
#   不再追关键词黑名单 (continue-check). 改为显式语法 allow-list.
#   每条 assistant 消息必须以 完成:/等你:/停住: (或 DONE:/AWAIT:/HALT:) 之一独占最后一行.
#   与措辞无关, 纯语法级判定 → AI 随机性产生的变体都会被同一条规则捕获.
#
# 原理:
#   Stop 钩子读 transcript_path, 取最后一条 assistant 文本消息
#   调用 ai-rules.sh tail-marker-check 校验
#   违规 → exit 2 + stderr 回灌强制下一轮补标记
#   stop_hook_active=true 时静默 (防无限循环)

INPUT=$(cat)

STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
if [[ "$STOP_ACTIVE" == "true" ]]; then
  exit 0
fi

TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null)
if [[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]]; then
  exit 0
fi

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SCRIPT="$ROOT/scripts/ai-rules.sh"
[[ ! -x "$SCRIPT" ]] && exit 0

# 语义门禁: 只在"交付模式"生效 (status.md 存在且有待办任务)
# - ai-rules 元开发仓 (无 status.md): 豁免, 作者可裸回复
# - 纯 Q&A 会话: 豁免
# - 下游交付项目: 强制 tail-marker
# 规则目的是规范交付流节奏, 无交付流时不规范.
if [[ ! -f "$ROOT/docs/status.md" ]] || ! grep -qE '^\s*-\s*\[ \]' "$ROOT/docs/status.md" 2>/dev/null; then
  exit 0
fi

# 取最后一条 assistant 文本消息
LAST_MSG=""
while IFS= read -r LINE_NUM; do
  LAST_MSG=$(sed -n "${LINE_NUM}p" "$TRANSCRIPT" | jq -r '.message.content[]? | select(.type == "text") | .text' 2>/dev/null)
  [[ -n "$LAST_MSG" ]] && break
done < <(grep -n '"type":"assistant"' "$TRANSCRIPT" | tail -5 | sort -rn -t: -k1 | cut -d: -f1)

if [[ -z "$LAST_MSG" ]]; then
  exit 0
fi

# tail-marker-check: exit 0 = 合法, exit 1 = 缺失/非法 (stdout 含诊断)
RESULT=$(echo "$LAST_MSG" | "$SCRIPT" tail-marker-check 2>&1)
RC=$?

if [[ "$RC" -eq 0 ]]; then
  exit 0
fi

# 落盘审计
LOG_DIR="$ROOT/.claude/state"
mkdir -p "$LOG_DIR" 2>/dev/null
LOG_FILE="$LOG_DIR/hook-log.jsonl"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if command -v jq >/dev/null 2>&1; then
  jq -nc --arg ts "$TS" --arg hook "stop-tail-marker" --arg msg "$RESULT" \
    --arg last "$(echo "$LAST_MSG" | tail -c 300)" \
    '{ts:$ts, hook:$hook, msg:$msg, last_msg_tail:$last}' >> "$LOG_FILE" 2>/dev/null || true
fi

# 轻量阻塞: tail-marker 缺失是 auto-correcting (AI 补一行就过),
# 不走 emit_blocked (那是给真阻塞设计的, 输出 15 行恐慌文案).
# 只给 AI 一行指令 + 告知用户正在自动修正.
ACTUAL_LAST=$(echo "$LAST_MSG" | grep -v '^[[:space:]]*$' | tail -1 | cut -c1-80)
echo "缺结束标记 (收到: \"${ACTUAL_LAST}\"). 补 \`完成:/等你:/停住:\` 收尾即可." >&2
exit 2
