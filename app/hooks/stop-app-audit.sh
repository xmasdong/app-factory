#!/bin/bash
# stop-app-audit.sh — Stop event 时按 CURRENT_GATE 审计 app 主线项目
# 复用 generic stop-skill-gate.sh 的成果物质量审计思想
# 仅当 PROJECT_TYPE=app 时触发, 否则放行

set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# 复用 generic _lib.sh 的 emit_blocked
if [[ -f "$ROOT/.claude/hooks/_lib.sh" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/.claude/hooks/_lib.sh"
elif [[ -f "$(dirname "$0")/../.claude/hooks/_lib.sh" ]]; then
  # shellcheck disable=SC1091
  source "$(dirname "$0")/../.claude/hooks/_lib.sh"
else
  # 降级: 直接 echo + exit
  emit_blocked() {
    local source="$1"
    local reason="$2"
    local full="$3"
    echo "[stop-app-audit] $source: $reason" >&2
    echo "$full" >&2
    exit 2
  }
fi

# ============================================================================
# 前置: PROJECT_TYPE 检测 (不是 app 直接放行)
# ============================================================================

PROJECT_TYPE=""
if [[ -f "$ROOT/docs/status.md" ]]; then
  PROJECT_TYPE=$(grep -E "^PROJECT_TYPE:" "$ROOT/docs/status.md" 2>/dev/null | head -1 | sed 's/^PROJECT_TYPE:[[:space:]]*//')
fi

if [[ "$PROJECT_TYPE" != "app" ]]; then
  # 反向 sniff: 仓库有 ios/ android/ Info.plist 但没声明 PROJECT_TYPE=app
  if [[ -d "$ROOT/ios" || -d "$ROOT/android" || -f "$ROOT/ios/Info.plist" ]]; then
    if [[ -z "$PROJECT_TYPE" ]]; then
      # graceful: 提示不阻塞
      echo "[stop-app-audit] 检测到 ios/ android/ Info.plist 但 status.md 未声明 PROJECT_TYPE. 如是 app 项目, 请在 status.md 顶部加 'PROJECT_TYPE: app'" >&2
    fi
  fi
  exit 0
fi

# ============================================================================
# 防重复: 5 分钟内同样问题不重复触发
# ============================================================================

DEDUP_FILE="$ROOT/.claude/state/.stop-app-audit-dedup"
mkdir -p "$(dirname "$DEDUP_FILE")" 2>/dev/null
NOW=$(date +%s)
LAST=$(cat "$DEDUP_FILE" 2>/dev/null || echo 0)
GAP=$((NOW - LAST))
if (( GAP < 300 )); then
  exit 0
fi

# ============================================================================
# 按 CURRENT_GATE 路由
# ============================================================================

CURRENT_GATE=$(grep -E "^CURRENT_GATE:" "$ROOT/docs/status.md" 2>/dev/null | head -1 | sed 's/^CURRENT_GATE:[[:space:]]*//')

if [[ -z "$CURRENT_GATE" ]]; then
  emit_blocked "stop-app-audit" "status.md 缺 CURRENT_GATE 字段" \
    "app 主线项目必须在 status.md 顶部声明 CURRENT_GATE (A-GATE 0/1/2/3/4)"
  echo "$NOW" > "$DEDUP_FILE"
  exit 2
fi

# 找 app-gate.sh
APP_GATE_SCRIPT=""
for candidate in \
  "$ROOT/.claude/scripts/app-gate.sh" \
  "$ROOT/scripts/app-gate.sh" \
  "$(dirname "$0")/../scripts/app-gate.sh"; do
  if [[ -x "$candidate" ]]; then
    APP_GATE_SCRIPT="$candidate"
    break
  fi
done

if [[ -z "$APP_GATE_SCRIPT" ]]; then
  # graceful degradation
  echo "[stop-app-audit] app-gate.sh 不存在, 跳过验收" >&2
  exit 0
fi

# ============================================================================
# 按 GATE 调用对应 app-gate.sh 验收
# ============================================================================

GATE_KEY=""
case "$CURRENT_GATE" in
  *"Discovery"*|*"discover"*)        GATE_KEY="discover" ;;
  *"Lockdown"*|*"lockdown"*)         GATE_KEY="lockdown" ;;
  *"A-GATE 0"*|*"anchor"*)           GATE_KEY="discover" ;;  # legacy alias
  *"A-GATE 1"*|*"Shape"*|*"shape"*)  GATE_KEY="shape" ;;
  *"A-GATE 2"*|*"Build"*|*"build"*)  GATE_KEY="build" ;;
  *"A-GATE 3"*|*"QA"*|*"qa"*)        GATE_KEY="qa" ;;
  *"A-GATE 4"*|*"Ship"*|*"ship"*)    GATE_KEY="ship" ;;
  *)
    emit_blocked "stop-app-audit" "无法解析 CURRENT_GATE: $CURRENT_GATE" \
      "合法值: A-GATE Discovery / Lockdown / Shape / Build / QA / Ship"
    echo "$NOW" > "$DEDUP_FILE"
    exit 2
    ;;
esac

# 调用 app-gate.sh
RESULT=$("$APP_GATE_SCRIPT" app-gate "$GATE_KEY" 2>&1)
EXIT_CODE=$?

if [[ $EXIT_CODE -ne 0 ]]; then
  FULL="A-GATE ${CURRENT_GATE} 审计未通过:

$RESULT

修复后再 commit / 收尾。运行: $APP_GATE_SCRIPT app-gate $GATE_KEY"
  emit_blocked "stop-app-audit" "A-GATE ${CURRENT_GATE} 验收未通过" "$FULL"
  echo "$NOW" > "$DEDUP_FILE"
  exit 2
fi

# 通过, 不输出
exit 0
