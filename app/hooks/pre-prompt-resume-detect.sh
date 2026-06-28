#!/bin/bash
# pre-prompt-resume-detect.sh — UserPromptSubmit hook
# 检测用户输入"推进/go/proceed" 等信号 → 写 AUTONOMOUS=true + CURRENT_GATE → A-GATE Lockdown
# 仅当 PROJECT_TYPE=app + discover 已通过 + 还未进 Lockdown 时触发
#
# 这是 2-touch workflow 的关键: TOUCH 2 (用户决定推进) 触发 AUTONOMOUS 模式

set -uo pipefail

INPUT=$(cat 2>/dev/null || true)
ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATUS_FILE="$ROOT/docs/status.md"

# 仅 app 项目
[[ ! -f "$STATUS_FILE" ]] && exit 0
PROJECT_TYPE=$(grep -oE 'PROJECT_TYPE:[[:space:]]*[A-Za-z_-]+' "$STATUS_FILE" 2>/dev/null | head -1 | awk -F: '{gsub(/[[:space:]]/,"",$2); print $2}')
[[ "$PROJECT_TYPE" != "app" ]] && exit 0

# 仅当 discover 已通过
[[ ! -f "$ROOT/.claude/state/clearance-discover.json" ]] && exit 0

# 仅当 CURRENT_GATE 还在 Discovery (没进 Lockdown/Shape/...)
CURRENT_GATE=$(grep -E "^CURRENT_GATE:" "$STATUS_FILE" 2>/dev/null | head -1 | sed 's/^CURRENT_GATE:[[:space:]]*//')
if echo "$CURRENT_GATE" | grep -qiE "Lockdown|Shape|Build|QA|Ship"; then
  exit 0
fi

# 抽用户输入
PROMPT=$(echo "$INPUT" | jq -r '.user_prompt // .prompt // .text // ""' 2>/dev/null)
[[ -z "$PROMPT" ]] && exit 0

# === 检测"推进" 信号 ===
if echo "$PROMPT" | grep -qiE '^[[:space:]]*(推进|go|proceed|上|继续|确认|approve|同意|开干|跑起来|可以|OK|ok|ship.*it|let.?s.?go|啊好的)[[:space:]]*[.!。!]?[[:space:]]*$'; then
  # 写 AUTONOMOUS=true
  if grep -q "^AUTONOMOUS:" "$STATUS_FILE"; then
    sed -i '' 's/^AUTONOMOUS:.*/AUTONOMOUS: true/' "$STATUS_FILE"
  else
    sed -i '' '/^PROJECT_TYPE:/a\
AUTONOMOUS: true
' "$STATUS_FILE"
  fi

  # 更新 CURRENT_GATE → A-GATE Lockdown
  if grep -q "^CURRENT_GATE:" "$STATUS_FILE"; then
    sed -i '' 's/^CURRENT_GATE:.*/CURRENT_GATE: A-GATE Lockdown/' "$STATUS_FILE"
  else
    sed -i '' '/^PROJECT_TYPE:/a\
CURRENT_GATE: A-GATE Lockdown
' "$STATUS_FILE"
  fi

  jq -nc '{
    systemMessage: "[ai-rules autonomous] 用户已确认推进. status.md 已写 AUTONOMOUS=true + CURRENT_GATE=A-GATE Lockdown. 立即进入 /lockdown skill, 不再询问决策. 全自动跑到 ship."
  }' 2>/dev/null
  exit 0
fi

# === 检测"换方向" 信号 ===
if echo "$PROMPT" | grep -qiE '^[[:space:]]*(换方向|换个|换思路|不行|换|reject|另选|重新探索|换 ?[a-z]+)'; then
  TS=$(date +%Y%m%dT%H%M%S)
  mkdir -p "$ROOT/.claude/state/discarded-concepts/$TS" 2>/dev/null

  # 1. mockup 存档
  if [[ -d "$ROOT/.claude/state/concept-visuals" ]]; then
    cp -r "$ROOT/.claude/state/concept-visuals" "$ROOT/.claude/state/discarded-concepts/$TS/visuals" 2>/dev/null
  fi
  if [[ -d "$ROOT/docs/mockups" ]]; then
    cp -r "$ROOT/docs/mockups" "$ROOT/.claude/state/discarded-concepts/$TS/mockups" 2>/dev/null
  fi

  # 2. 抽 spec.md 的 ## 产品定位 5 字段 + 理由, append 到 discarded-directions.txt
  if [[ -f "$ROOT/docs/spec.md" ]]; then
    {
      echo "=== Discarded at $TS ==="
      awk '/^## 产品定位/,/^## [^产]/' "$ROOT/docs/spec.md" 2>/dev/null
      echo ""
    } >> "$ROOT/.claude/state/discarded-directions.txt"
  fi

  # 3. 累计计数: 3 次"换方向"未满意 → 提示 fuse
  DISC_COUNT=$(ls -d "$ROOT/.claude/state/discarded-concepts"/*/ 2>/dev/null | wc -l | tr -d ' ')

  MSG_CORE="用户要求换方向. 当前方向已归档到 .claude/state/discarded-concepts/${TS}/. 5 字段 + 理由已 append 到 .claude/state/discarded-directions.txt. 回到 /discover Step 0 重新跑, 本轮 5 字段至少 2 项必须与上轮不同 (读 discarded-directions.txt)."
  if (( DISC_COUNT >= 3 )); then
    MSG_CORE="$MSG_CORE 注意: 已累计 ${DISC_COUNT} 次换方向, 可能产品方向本身不清晰. 建议追问用户更具体的需求或暂停."
  fi

  jq -nc --arg msg "[ai-rules] $MSG_CORE" '{ systemMessage: $msg }' 2>/dev/null
  exit 0
fi

# === 检测"暂停" 信号 ===
if echo "$PROMPT" | grep -qiE '^[[:space:]]*(暂停|pause|稍等|wait|hold|放一下)'; then
  jq -nc '{
    systemMessage: "[ai-rules] 用户要求暂停. 不动任何状态. 等用户回来再说."
  }' 2>/dev/null
  exit 0
fi

exit 0
