#!/bin/bash
# Pre-commit hook: 检查改动范围是否超出任务声明
# 退出码 0=放行，2=阻塞 commit

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)

# 只拦截 git commit
if ! echo "$COMMAND" | grep -q "^git commit"; then
  exit 0
fi

# 找项目根目录
ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SCRIPT="$ROOT/scripts/ai-rules.sh"

# 脚本不存在则放行（graceful degradation）
if [[ ! -x "$SCRIPT" ]]; then
  exit 0
fi

# 执行 scope 检查
RESULT=$("$SCRIPT" scope 2>&1)
EXIT_CODE=$?

if [[ $EXIT_CODE -ne 0 ]]; then
  # shellcheck disable=SC1091
  source "$(dirname "$0")/_lib.sh"
  FULL="$RESULT

Scope check failed. 改动范围可能超出任务声明。
运行 ./scripts/ai-rules.sh scope [TASK-ID] 查看详情。"
  emit_blocked "pre-commit-scope" "改动范围超出任务 FILES 声明" "$FULL"
  exit 2  # 阻塞 commit
fi

# DRIFTED 时输出警告但不阻塞
if echo "$RESULT" | grep -q "DRIFTED"; then
  echo "$RESULT" >&2
  echo "" >&2
  echo "Warning: 改动范围有漂移，建议检查。" >&2
fi

# ---- spec 质量卡口 ----
# 如果 spec.md 存在于仓库中，验证其质量
# 只有当 commit 包含非文档文件时才检查（允许 commit 文档修复本身）
SPEC_IN_REPO=$(git -C "$ROOT" ls-files docs/spec.md 2>/dev/null)
if [[ -n "$SPEC_IN_REPO" ]]; then
  STAGED_FILES=$(echo "$COMMAND" | grep -q "\-\-amend" && git -C "$ROOT" diff HEAD~1 --name-only 2>/dev/null || git -C "$ROOT" diff --cached --name-only 2>/dev/null)
  HAS_SRC=$(echo "$STAGED_FILES" | grep -cvE '^(docs/|scripts/|\.claude/|CLAUDE\.md|README|LICENSE)' 2>/dev/null) || HAS_SRC=0

  if [[ "$HAS_SRC" -gt 0 ]]; then
    # clearance 缓存: spec 已通过且未变 → 跳过重检, 防追溯拦截
    SKIP_SPEC=false
    CLEARANCE="$ROOT/.claude/state/clearance-spec.json"
    if [[ -f "$CLEARANCE" ]] && command -v jq >/dev/null 2>&1; then
      SAVED_HASH=$(jq -r '.spec_hash // ""' "$CLEARANCE" 2>/dev/null)
      if [[ -n "$SAVED_HASH" ]]; then
        CURRENT_HASH=$(git -C "$ROOT" hash-object "$ROOT/docs/spec.md" 2>/dev/null || md5 -q "$ROOT/docs/spec.md" 2>/dev/null || echo "")
        [[ "$SAVED_HASH" = "$CURRENT_HASH" ]] && SKIP_SPEC=true
      fi
    fi

    if [[ "$SKIP_SPEC" = true ]]; then
      : # spec 未变 + 有 clearance → 静默放行
    else
    SPEC_RESULT=$("$SCRIPT" skill-gate spec --check-only 2>&1)
    SPEC_EXIT=$?
    if [[ $SPEC_EXIT -ne 0 ]]; then
      # shellcheck disable=SC1091
      source "$(dirname "$0")/_lib.sh"
      FULL="[pre-commit spec 质量检查]
$SPEC_RESULT

spec.md 质量不达标，请补全后再 commit 源码。
（仅 commit docs/ 修复 spec 本身不受此限制）"
      emit_blocked "pre-commit-scope (spec 质量)" "spec.md 质量未达标, commit 被阻塞" "$FULL"
      exit 2
    fi
    fi # else (no clearance)
  fi
fi

exit 0
