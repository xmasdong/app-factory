#!/bin/bash
# 共享辅助函数 — 被各 hook source
#
# 设计目标: 阻塞发生时, 终端用户能立刻知道为什么停, 而不是看 AI 默默不动
#   1. 写持久化原因到 .claude/state/last-stop-reason.md (用户随时 cat 可查)
#   2. stderr 把详情给 AI (用于修复), 不再强制 AI 复读整段
#   3. tail-marker 已有收尾机制 (CLAUDE.md 硬规则), AI 用 `停住: <一句话处置>` 收尾即可

# emit_blocked <hook_name> <one_line_summary> <full_message>
# 写原因文件 + 输出 stderr (调用方自行 exit 2)
emit_blocked() {
  local hook="$1" summary="$2" msg="$3"
  local root="${ROOT:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
  local reason_file="$root/.claude/state/last-stop-reason.md"
  mkdir -p "$(dirname "$reason_file")" 2>/dev/null
  {
    echo "# 最后一次阻塞"
    echo ""
    echo "- 时间: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "- Hook: $hook"
    echo "- 一句话: $summary"
    echo ""
    echo "## 原文"
    echo ""
    echo '```'
    printf '%s\n' "$msg"
    echo '```'
    echo ""
    echo "_用户可随时运行 \`cat .claude/state/last-stop-reason.md\` 查看最近阻塞原因._"
  } > "$reason_file" 2>/dev/null

  # stderr: 详情(msg)给 AI 看用于修复; 最后一行精简指令, 不让 AI 整段复读
  echo "$msg" >&2
  echo "" >&2
  echo "⚠️ ${hook} 阻塞. 收尾单独一行 \`停住: <一句话处置意图>\`, 不要复读上文. 详情已落盘 .claude/state/last-stop-reason.md." >&2
}
