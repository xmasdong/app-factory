#!/bin/bash
# Stop hook: Skill 完成信号检测 + 产出物验收 + 文件系统审计
#
# 检测优先级：
#   1. 信号文件（.claude/state/skill-signal.json）— 确定性最高
#   2. Report 文件新鲜度（check/verify/release 已有 report JSON）
#   3. 正则 fallback（过渡期保留，带 warning log）
#   4. Audit 兜底（纯文件系统状态检查）
#
# stop_hook_active=true 时静默（防止无限循环）

INPUT=$(cat)

# 防止无限循环
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
if [[ "$STOP_ACTIVE" == "true" ]]; then
  exit 0
fi

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SCRIPT="$ROOT/scripts/ai-rules.sh"
[[ ! -x "$SCRIPT" ]] && exit 0

# ---- 审计日志辅助函数 ----
log_hook() {
  local hook_name="$1" msg="$2"
  local LOG_DIR="$ROOT/.claude/state"
  mkdir -p "$LOG_DIR" 2>/dev/null
  local LOG_FILE="$LOG_DIR/hook-log.jsonl"
  local TS
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg ts "$TS" --arg hook "$hook_name" --arg msg "$msg" \
      '{ts:$ts, hook:$hook, msg:$msg}' >> "$LOG_FILE" 2>/dev/null || true
  fi
}

# ---- 第 1 层：信号文件检测 ----
SIGNAL_FILE="$ROOT/.claude/state/skill-signal.json"
SKILL=""

if [[ -f "$SIGNAL_FILE" ]]; then
  SKILL=$(jq -r '.skill // ""' "$SIGNAL_FILE" 2>/dev/null)
  SIGNAL_EPOCH=$(jq -r '.epoch // 0' "$SIGNAL_FILE" 2>/dev/null)

  # 新鲜度检查：信号必须在最近 10 分钟内
  NOW_EPOCH=$(date +%s)
  # epoch 直接比较，无时区问题
  if (( NOW_EPOCH - SIGNAL_EPOCH > 600 )); then
    # 信号过期（>10 分钟），视为残留
    log_hook "stop-signal-expired" "skill=$SKILL epoch=$SIGNAL_EPOCH age=$((NOW_EPOCH - SIGNAL_EPOCH))s"
    rm -f "$SIGNAL_FILE"
    SKILL=""
  else
    # 有效信号 → 消费后删除
    rm -f "$SIGNAL_FILE"
    log_hook "stop-signal-consumed" "skill=$SKILL"
  fi
fi

# ---- 第 2 层：Report 文件新鲜度检测（check/verify/release）----
if [[ -z "$SKILL" ]]; then
  STATE_DIR="$ROOT/.claude/state"
  NOW_EPOCH=$(date +%s)

  for report_skill in check verify release; do
    REPORT_FILE="$STATE_DIR/${report_skill}-report.json"
    if [[ -f "$REPORT_FILE" ]]; then
      # macOS: stat -f %m; Linux: stat -c %Y
      REPORT_MTIME=$(stat -f %m "$REPORT_FILE" 2>/dev/null || stat -c %Y "$REPORT_FILE" 2>/dev/null || echo 0)
      if (( NOW_EPOCH - REPORT_MTIME < 600 )); then
        SKILL="$report_skill"
        log_hook "stop-report-detected" "skill=$SKILL file=$REPORT_FILE"
        break
      fi
    fi
  done
fi

# ---- 第 3 层：正则 fallback（过渡期，带 warning）----
# 硬门：只有真动过对应产出物（mtime < 10 min），才允许 regex fallback。
# 目的：挡住"讨论方法论时提到 /spec"的假阳性。
FALLBACK_ALLOWED=0
NOW=$(date +%s)
for F in "$ROOT/docs/spec.md" "$ROOT/docs/status.md"; do
  if [[ -f "$F" ]]; then
    MT=$(stat -f %m "$F" 2>/dev/null || stat -c %Y "$F" 2>/dev/null || echo 0)
    if (( NOW - MT < 600 )); then FALLBACK_ALLOWED=1; break; fi
  fi
done
# 元仓库白名单：ai-rules 方法论仓本身（有 .claude/skills/spec/SKILL.md 但无 docs/spec.md）→ 跳过
if [[ -f "$ROOT/.claude/skills/spec/SKILL.md" && ! -f "$ROOT/docs/spec.md" ]]; then
  FALLBACK_ALLOWED=0
  log_hook "stop-regex-skip" "meta-repo detected (SKILL.md without docs/spec.md) — skip regex fallback"
fi

if [[ -z "$SKILL" && "$FALLBACK_ALLOWED" -eq 1 ]]; then
  TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null)
  if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
    # 提取最后一条有文本的 assistant 消息
    LAST_MSG=""
    while IFS= read -r LINE_NUM; do
      LAST_MSG=$(sed -n "${LINE_NUM}p" "$TRANSCRIPT" | jq -r '.message.content[]? | select(.type == "text") | .text' 2>/dev/null)
      [[ -n "$LAST_MSG" ]] && break
    done < <(grep -n '"type":"assistant"' "$TRANSCRIPT" | tail -5 | sort -rn -t: -k1 | cut -d: -f1)

    if [[ -n "$LAST_MSG" ]]; then
      # 收紧的正则：不含"通过"，限制距离
      DONE='(完成|done|finished|saved|committed|写入|保存|创建)'

      if echo "$LAST_MSG" | grep -qiE "(\/spec\s.{0,6}${DONE})|(spec\.md\s.{0,6}${DONE})|(GATE.?0\s.{0,6}${DONE})"; then
        SKILL="spec"
      elif echo "$LAST_MSG" | grep -qiE "(^DONE:)|(\/impl\s.{0,6}${DONE})|(所有任务.{0,3}(完成|已完成))|(全部任务.{0,3}(完成|已完成))"; then
        SKILL="impl"
      elif echo "$LAST_MSG" | grep -qiE "(\/check\s.{0,6}${DONE})"; then
        SKILL="check"
      elif echo "$LAST_MSG" | grep -qiE "(\/verify\s.{0,6}${DONE})"; then
        SKILL="verify"
      elif echo "$LAST_MSG" | grep -qiE "(\/release\s.{0,6}${DONE})"; then
        SKILL="release"
      fi

      if [[ -n "$SKILL" ]]; then
        # 过渡期 warning：记录走了 fallback 路径
        log_hook "stop-regex-fallback" "skill=$SKILL (WARN: signal file missing, used regex detection)"
      fi
    fi
  fi
fi

# ---- 第 4 层：Audit 兜底 ----
if [[ -z "$SKILL" ]]; then
  AUDIT_RESULT=$("$SCRIPT" audit 2>&1)
  AUDIT_EXIT=$?
  if [[ "$AUDIT_EXIT" -eq 2 ]]; then
    log_hook "stop-audit" "$AUDIT_RESULT"
    # shellcheck disable=SC1091
    source "$(dirname "$0")/_lib.sh"
    AUDIT_SUMMARY=$(echo "$AUDIT_RESULT" | grep -E '^\[' | head -1 | cut -c1-140)
    [[ -z "$AUDIT_SUMMARY" ]] && AUDIT_SUMMARY="产出物审计发现问题"
    emit_blocked "stop-audit" "$AUDIT_SUMMARY" "$AUDIT_RESULT"
    exit 2
  fi
  exit 0
fi

# ---- 执行 skill-gate 验收 ----
RESULT=$("$SCRIPT" skill-gate "$SKILL" 2>&1)
EXIT_CODE=$?

# 通过 → 放行 + 重置熔断计数 + 输出语义提示（不阻塞）
if [[ "$EXIT_CODE" -eq 0 ]]; then
  # 验收通过 → 重置 gate 连续失败计数
  "$SCRIPT" fuse reset --soft 2>/dev/null || true

  HINT_FILE="$ROOT/.claude/state/clearance-hint-${SKILL}.txt"
  if [[ -f "$HINT_FILE" ]]; then
    HINT=$(cat "$HINT_FILE")
    if [[ -n "$HINT" ]]; then
      log_hook "stop-skill-gate-clearance" "skill=$SKILL"
      echo "[ai-rules clearance] /${SKILL} 机械验收通过。" >&2
      echo "$HINT" >&2
    fi
  fi
  exit 0
fi

# 不通过 → 熔断检测 + 阻塞
log_hook "stop-skill-gate-fail" "skill=$SKILL msg=$(echo "$RESULT" | head -c 200)"

# 熔断器：累加失败计数，检查是否触发熔断
FUSE_EXIT=0
"$SCRIPT" fuse check gate-fail "$SKILL" 2>/dev/null || FUSE_EXIT=$?

# shellcheck disable=SC1091
source "$(dirname "$0")/_lib.sh"

if [[ "$FUSE_EXIT" -eq 20 ]]; then
  # 硬熔断 → 停止所有执行
  FUSE_REPORT=$("$SCRIPT" fuse report 2>&1)
  FULL="$FUSE_REPORT

硬熔断已触发。AI 在多个任务上连续失败，可能存在全局性问题。
停止所有执行，等待人工介入。
解锁命令: scripts/ai-rules.sh fuse reset"
  emit_blocked "stop-skill-gate (hard-fuse)" "硬熔断: /${SKILL} 连续多任务失败, 需人工介入" "$FULL"
  exit 2
fi

if [[ "$FUSE_EXIT" -eq 10 ]]; then
  # 软熔断 → 跳过当前任务，尝试下一个
  FULL="[ai-rules fuse] 软熔断：当前 skill /${SKILL} 连续多次验收失败。
跳过当前任务，标记为 fused，尝试下一个无阻塞的任务。
在 status.md 中将当前任务标记为 [FUSED]，然后直接开始下一个任务。
不要继续修复当前任务。"
  emit_blocked "stop-skill-gate (soft-fuse)" "软熔断: /${SKILL} 连续失败, 跳当前任务" "$FULL"
  exit 2
fi

# 未触发熔断 → 正常阻塞，要求修复
GATE_SUMMARY=$(echo "$RESULT" | grep -E '^\[' | head -1 | cut -c1-140)
[[ -z "$GATE_SUMMARY" ]] && GATE_SUMMARY="/${SKILL} 机械验收未通过"
FULL="$RESULT

补全以上缺失项后，请重新写入完成信号：
echo '{\"skill\":\"${SKILL}\",\"epoch\":'\"$(date +%s)\"'}' > .claude/state/skill-signal.json"
emit_blocked "stop-skill-gate (${SKILL})" "$GATE_SUMMARY" "$FULL"
exit 2
