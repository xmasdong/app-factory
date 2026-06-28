#!/bin/bash
# PreToolUse hook: A-GATE 0 未过, 阻塞业务代码编辑
# 触发: Edit / Write on app/ 业务代码
# 退出码: 0=放行, 2=阻塞
#
# 逻辑:
#   1. PROJECT_TYPE 不是 app → 不管, 放行
#   2. 是 app → 读 clearance-app-anchor.json
#   3. clearance 齐 (6 项命名 locked + 经济单调 + 后端 ≥6 项 + spec_hash 匹配) → 放行
#   4. clearance 不齐 + 改的是业务代码 (非 docs/spec/.claude) → 阻塞, 提示先 /app-anchor

set -u

INPUT=$(cat 2>/dev/null || true)

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATUS_FILE="$ROOT/docs/status.md"
CLEARANCE="$ROOT/.claude/state/clearance-lockdown.json"  # 业务代码必须等 lockdown 通过
SPEC_FILE="$ROOT/docs/spec.md"

# --- 1. PROJECT_TYPE 判定 ---
if [[ ! -f "$STATUS_FILE" ]]; then
  exit 0  # 没 status.md 不归 A-GATE 0 管
fi

PROJECT_TYPE=$(grep -oE 'PROJECT_TYPE:[[:space:]]*[A-Za-z_-]+' "$STATUS_FILE" 2>/dev/null \
  | head -1 | awk -F: '{gsub(/[[:space:]]/,"",$2); print $2}')

if [[ "$PROJECT_TYPE" != "app" ]]; then
  exit 0  # 非 app 项目, 不干涉
fi

# --- 2. 解析被编辑的文件路径 ---
TARGET_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null)

if [[ -z "$TARGET_PATH" ]]; then
  exit 0  # 取不到路径放行 (兼容其他 tool)
fi

# --- 3. 排除清单: 这些路径任何时刻都能编辑 (允许 AI 写 spec/状态/规则文件) ---
case "$TARGET_PATH" in
  */docs/*|*/\.claude/*|*/CLAUDE.md|*/README*|*/LICENSE*|*/templates/*|*/scripts/ai-rules.sh|*/scripts/app-gate.sh|*/hooks/*|*/rules/*)
    exit 0
    ;;
esac

# 不在 app/ 子树下的 (如根目录的 setup.py, package.json 顶层) — 也允许 (init 项目脚手架阶段)
# 业务代码识别: 含 src/ / lib/ / ios/ / android/ / app/ / backend/ / api/ 这类子串
case "$TARGET_PATH" in
  */src/*|*/lib/*|*/ios/*|*/android/*|*/backend/*|*/api/*|*/worker/*|*/functions/*|*.swift|*.kt|*.dart|*.tsx|*.ts|*.jsx|*.js)
    : # 进入下一步 clearance 校验
    ;;
  *)
    exit 0  # 其他文件不算业务代码
    ;;
esac

# --- 4. clearance 校验 ---
if [[ ! -f "$CLEARANCE" ]]; then
  # shellcheck disable=SC1091
  source "$(dirname "$0")/../../.claude/hooks/_lib.sh" 2>/dev/null \
    || source "$ROOT/.claude/hooks/_lib.sh" 2>/dev/null \
    || true
  MSG="A-GATE 0 (外部锚定) 尚未通过, 不能写业务代码: $TARGET_PATH

未找到 .claude/state/clearance-app-anchor.json.
先跑 /app-anchor (或 ./scripts/ai-rules.sh skill-gate app-anchor) 完成:
  - NAMING-LOCK 6 项 (品牌/域名/AppStore/Play/bundleId/IAP prefix)
  - ECONOMICS 单调性 + 反薅 ≥5
  - BACKEND-READINESS ≥6 项打勾

只允许编辑: docs/, .claude/, templates/, scripts/, hooks/, rules/, CLAUDE.md, README.md"

  if declare -F emit_blocked >/dev/null 2>&1; then
    emit_blocked "pre-anchor-check" "A-GATE 0 未过, 阻塞业务代码编辑" "$MSG"
  else
    echo "$MSG" >&2
  fi
  exit 2
fi

# clearance 存在 → 检查 spec_hash 是否匹配 (spec 改动后 clearance 失效)
if command -v jq >/dev/null 2>&1; then
  SAVED_HASH=$(jq -r '.spec_hash // ""' "$CLEARANCE" 2>/dev/null)
  if [[ -n "$SAVED_HASH" && -f "$SPEC_FILE" ]]; then
    CURRENT_HASH=$(git -C "$ROOT" hash-object "$SPEC_FILE" 2>/dev/null \
      || md5 -q "$SPEC_FILE" 2>/dev/null \
      || md5sum "$SPEC_FILE" 2>/dev/null | awk '{print $1}')
    if [[ -n "$CURRENT_HASH" && "$SAVED_HASH" != "$CURRENT_HASH" ]]; then
      # shellcheck disable=SC1091
      source "$ROOT/.claude/hooks/_lib.sh" 2>/dev/null || true
      MSG="A-GATE 0 clearance 已过期 (spec.md 在 clearance 后被改动).

clearance.spec_hash = $SAVED_HASH
spec.md  current   = $CURRENT_HASH

重跑 /app-anchor 让 clearance 与最新 spec 对齐, 再继续业务代码改动."
      if declare -F emit_blocked >/dev/null 2>&1; then
        emit_blocked "pre-anchor-check" "A-GATE 0 clearance 过期" "$MSG"
      else
        echo "$MSG" >&2
      fi
      exit 2
    fi
  fi

  # 检查各项 OK
  STATUS=$(jq -r '.status // "unknown"' "$CLEARANCE" 2>/dev/null)
  if [[ "$STATUS" != "ok" && "$STATUS" != "pass" ]]; then
    # shellcheck disable=SC1091
    source "$ROOT/.claude/hooks/_lib.sh" 2>/dev/null || true
    MSG="A-GATE 0 clearance 显示未通过 (status=$STATUS).
重跑 /app-anchor 并确保所有子项 ok 后再继续."
    if declare -F emit_blocked >/dev/null 2>&1; then
      emit_blocked "pre-anchor-check" "A-GATE 0 clearance 未通过" "$MSG"
    else
      echo "$MSG" >&2
    fi
    exit 2
  fi
fi

exit 0
