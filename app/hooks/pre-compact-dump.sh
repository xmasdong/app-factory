#!/bin/bash
# PreCompact hook: 压缩前把"进行中的任务状态"落盘, 防丢关键信息
#
# 背景:
#   GATE 3 只防"任务完成后"的信息丢失 (commit + status.md).
#   实际观测: 任务执行中途就会被 auto-compact, 导致"已做的决策 / 刚改的文件 / 中间思路"丢失.
#
# 本 hook 在压缩前触发, 做两件事:
#   1. 直接落盘 — 从 transcript 抽最近 N 条 assistant 消息尾部 + git 状态 +
#      status.md 尾部, 写入 .claude/state/pre-compact/<ts>.md (保留最近 5 份)
#   2. 注入 additionalContext — 告诉压缩后的 AI "读这个 dump 恢复上下文"
#
# AI 不参与这个 hook (压缩已触发, AI 没机会响应). 完全由 hook 脚本独立完成.

INPUT=$(cat)
ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null)
TRIGGER=$(echo "$INPUT" | jq -r '.trigger // "auto"' 2>/dev/null)

DUMP_DIR="$ROOT/.claude/state/pre-compact"
mkdir -p "$DUMP_DIR" 2>/dev/null
TS=$(date +%Y%m%dT%H%M%S)
DUMP_FILE="$DUMP_DIR/${TS}.md"

{
  echo "# Pre-compact dump — $TS ($TRIGGER)"
  echo ""
  echo "> 压缩前落盘的进行中任务上下文. 压缩后恢复时 AI 应读此文件."
  echo ""

  # 1. 当前 git 状态
  echo "## git 状态"
  echo ""
  echo '```'
  git -C "$ROOT" status --short 2>/dev/null | head -30
  echo '```'
  echo ""
  echo "## 最近 5 个 commit"
  echo ""
  echo '```'
  git -C "$ROOT" log --oneline -5 2>/dev/null
  echo '```'
  echo ""

  # 2. status.md 尾部 (通常含当前任务进展)
  if [[ -f "$ROOT/docs/status.md" ]]; then
    echo "## docs/status.md 尾部 (100 行)"
    echo ""
    echo '```markdown'
    tail -100 "$ROOT/docs/status.md" 2>/dev/null
    echo '```'
    echo ""
  fi

  # 3. 最近修改的文件 (过去 30 分钟)
  echo "## 最近 30 分钟修改的文件"
  echo ""
  echo '```'
  find "$ROOT" -type f -mmin -30 \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/.claude/state/*" \
    -not -path "*/dist/*" \
    -not -path "*/build/*" \
    2>/dev/null | head -40
  echo '```'
  echo ""

  # 4. transcript 最后 N 条 assistant 文本 (抽尾部, 保留思路)
  if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
    echo "## 对话尾部 (最后 10 条 assistant 文本消息)"
    echo ""
    echo '```'
    grep -n '"type":"assistant"' "$TRANSCRIPT" 2>/dev/null | tail -10 | cut -d: -f1 | while read -r LN; do
      sed -n "${LN}p" "$TRANSCRIPT" 2>/dev/null \
        | jq -r '.message.content[]? | select(.type == "text") | .text' 2>/dev/null \
        | head -20
      echo "---"
    done
    echo '```'
    echo ""
  fi

  echo "## 恢复指引"
  echo ""
  echo "压缩后 AI 恢复会话时应:"
  echo "1. 读 CLAUDE.md + docs/status.md 确认全局"
  echo "2. 读本 dump 确认压缩前的进行中细节"
  echo "3. 检查 git 状态: 有未 commit 改动 → 判断是否属于当前任务 → 补 commit 或说明"
  echo "4. 若本任务未完成, 继续推进; 已完成, 按 DONE-TEMPLATE 收尾"
} > "$DUMP_FILE" 2>/dev/null

# 保留最近 5 份 dump, 删旧
ls -t "$DUMP_DIR"/*.md 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null

# 输出 systemMessage 提示用户 dump 路径
# 注: PreCompact 不支持 hookSpecificOutput.additionalContext (schema 只白名单 PreToolUse/UserPromptSubmit/PostToolUse).
# 改用顶层 systemMessage. AI 恢复时读 dump 由 CLAUDE.md 恢复指引兜底.
REL_PATH=".claude/state/pre-compact/${TS}.md"
MSG="会话压缩前已落盘进行中状态到 ${REL_PATH}. 恢复时先读此文件 + docs/status.md."

jq -nc --arg msg "$MSG" '{ systemMessage: $msg }' 2>/dev/null

exit 0
