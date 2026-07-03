#!/usr/bin/env bash
set -euo pipefail

# ai-rules 执行工具 v1.7.0
# 子命令集，验证方法论规则的实际执行情况。
#
# Usage:
#   ./scripts/ai-rules.sh index              — 生成项目状态索引（新会话恢复用）
#   ./scripts/ai-rules.sh scope [TASK-ID]    — 检查 commit 范围是否超出任务声明
#   ./scripts/ai-rules.sh checkpoint         — 检查是否需要触发确认检查点
#   ./scripts/ai-rules.sh lessons            — 扫描结构信号，写入 docs/lessons.md
#
# 无外部依赖，仅需 bash + git。
# 没有安装时方法论退化为 honor system，不影响正常工作。

# ---- 公共函数 ----

find_root() {
  # 优先使用 Claude Code hook 环境变量，避免 cwd 与项目根不一致
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" && -f "${CLAUDE_PROJECT_DIR}/CLAUDE.md" ]]; then
    echo "$CLAUDE_PROJECT_DIR"
    return 0
  fi
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/CLAUDE.md" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  echo "$PWD"
}

ROOT=$(find_root)
STATUS_FILE="$ROOT/docs/status.md"
SPEC_FILE="$ROOT/docs/spec.md"
INDEX_FILE="$ROOT/.claude/state/index.json"
LESSONS_FILE="$ROOT/docs/lessons.md"

# 读取 PROJECT_PHASE
get_phase() {
  if [[ -f "$STATUS_FILE" ]]; then
    local result
    result=$(sed -n 's/^PROJECT_PHASE:[[:space:]]*\([a-zA-Z_]*\).*/\1/p' "$STATUS_FILE" 2>/dev/null | head -1)
    echo "${result:-unknown}"
  else
    echo "unknown"
  fi
}

# 从 status.md 提取任务统计
count_tasks() {
  local status="$1"  # x 或 空格
  if [[ -f "$STATUS_FILE" ]]; then
    local count
    count=$(grep -cE "^\s*-\s*\[$status\]" "$STATUS_FILE" 2>/dev/null) || true
    echo "${count:-0}"
  else
    echo "0"
  fi
}

# 从 status.md 提取 optimistic/deferred/confirmed 计数
count_decisions() {
  local keyword="$1"
  if [[ -f "$STATUS_FILE" ]]; then
    local count
    count=$(grep -ci "$keyword" "$STATUS_FILE" 2>/dev/null) || true
    echo "${count:-0}"
  else
    echo "0"
  fi
}

# 安全 JSON 字符串转义
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  echo "$s"
}

# ---- 子命令: index ----
# 扫描项目状态，生成结构化索引供新会话快速恢复

cmd_index() {
  local phase
  phase=$(get_phase)

  local done_count todo_count
  done_count=$(count_tasks "x")
  todo_count=$(count_tasks " ")
  local total_count=$((done_count + todo_count))

  local optimistic_count deferred_count confirmed_count
  optimistic_count=$(count_decisions "optimistic")
  deferred_count=$(count_decisions "deferred")
  confirmed_count=$(count_decisions "confirmed")

  # 检查点是否到期
  local checkpoint_due="false"
  if [[ "$optimistic_count" -ge 5 ]]; then
    checkpoint_due="true"
  fi

  # 最近 commit
  local last_hash last_msg last_date
  last_hash=$(git -C "$ROOT" log -1 --format="%h" 2>/dev/null || echo "none")
  last_msg=$(json_escape "$(git -C "$ROOT" log -1 --format="%s" 2>/dev/null || echo "no commits")")
  last_date=$(git -C "$ROOT" log -1 --format="%ci" 2>/dev/null | cut -d' ' -f1 || echo "unknown")

  # 工作区状态
  local uncommitted
  uncommitted=$(git -C "$ROOT" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

  # 下一个 TODO 任务（从 status.md 提取第一个未完成的）
  local next_task="null"
  if [[ -f "$STATUS_FILE" ]]; then
    local raw
    raw=$(grep -m1 -E '^\s*-\s*\[ \]' "$STATUS_FILE" 2>/dev/null || true)
    if [[ -n "$raw" ]]; then
      raw=$(echo "$raw" | sed 's/^[[:space:]]*-[[:space:]]*\[ \][[:space:]]*//')
      next_task="\"$(json_escape "$raw")\""
    fi
  fi

  # status.md 新鲜度（距上次修改的 commit 数）
  local status_age="unknown"
  if [[ -f "$STATUS_FILE" ]]; then
    local status_last_commit
    status_last_commit=$(git -C "$ROOT" log -1 --format="%H" -- "docs/status.md" 2>/dev/null || echo "")
    if [[ -n "$status_last_commit" ]]; then
      status_age=$(git -C "$ROOT" rev-list --count "$status_last_commit..HEAD" 2>/dev/null || echo "unknown")
    fi
  fi

  # 输出 JSON
  mkdir -p "$(dirname "$INDEX_FILE")"
  cat > "$INDEX_FILE" << JSONEOF
{
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "project_phase": "$phase",
  "tasks": {
    "total": $total_count,
    "done": $done_count,
    "pending": $todo_count
  },
  "decisions": {
    "optimistic": $optimistic_count,
    "deferred": $deferred_count,
    "confirmed": $confirmed_count,
    "checkpoint_due": $checkpoint_due
  },
  "git": {
    "last_commit": "$last_hash",
    "last_message": "$last_msg",
    "last_date": "$last_date",
    "uncommitted_files": $uncommitted
  },
  "next_task": $next_task,
  "status_md_age_commits": "$status_age",
  "files": {
    "claude_md": $([ -f "$ROOT/CLAUDE.md" ] && echo "true" || echo "false"),
    "status_md": $([ -f "$STATUS_FILE" ] && echo "true" || echo "false"),
    "spec_md": $([ -f "$SPEC_FILE" ] && echo "true" || echo "false")
  }
}
JSONEOF

  cat "$INDEX_FILE"
}

# ---- 子命令: scope ----
# 对比任务声明的 FILES 和 git 实际改动，报告范围漂移

cmd_scope() {
  local task_id="${1:-}"

  # 获取 staged + unstaged 改动文件（排除 docs/）
  local actual_files
  actual_files=$(
    {
      git -C "$ROOT" diff --name-only HEAD 2>/dev/null
      git -C "$ROOT" diff --name-only --cached 2>/dev/null
      git -C "$ROOT" ls-files --others --exclude-standard 2>/dev/null
    } | sort -u | grep -v '^docs/' | grep -v '^\.' || true
  )

  local actual_count
  actual_count=$(echo "$actual_files" | grep -c . 2>/dev/null || echo "0")

  # 尝试从 status.md 找到任务的 FILES 声明
  local declared_files=""
  local declared_count=0
  local task_desc="unknown"

  if [[ -n "$task_id" && -f "$STATUS_FILE" ]]; then
    # 搜索任务块中的 FILES 行
    local in_task=false
    while IFS= read -r line; do
      if echo "$line" | grep -q "$task_id"; then
        in_task=true
        task_desc=$(echo "$line" | sed "s/.*$task_id[[:space:]]*[:：]*//" | sed 's/^[[:space:]]*//')
      fi
      if $in_task && echo "$line" | grep -qiE '^FILES:'; then
        declared_files=$(echo "$line" | sed 's/^FILES:[[:space:]]*//')
        break
      fi
      # 遇到下一个任务则停止
      if $in_task && echo "$line" | grep -qE '^(TASK|DONE|---|\*\*\*)' && ! echo "$line" | grep -q "$task_id"; then
        break
      fi
    done < "$STATUS_FILE"
  fi

  if [[ -n "$declared_files" ]]; then
    declared_count=$(echo "$declared_files" | tr ',' '\n' | grep -c . 2>/dev/null || echo "0")
  fi

  # 计算 drift ratio
  local verdict="UNKNOWN"
  local drift_ratio="N/A"
  local suggestion=""

  if [[ "$declared_count" -gt 0 ]]; then
    if command -v bc &>/dev/null; then
      drift_ratio=$(echo "scale=1; $actual_count / $declared_count" | bc 2>/dev/null || echo "N/A")
    else
      drift_ratio="$actual_count/$declared_count"
    fi

    if [[ "$actual_count" -le "$((declared_count + declared_count / 2))" ]]; then
      verdict="OK"
    elif [[ "$actual_count" -le "$((declared_count * 3))" ]]; then
      verdict="DRIFTED"
      suggestion="实际改动 $actual_count 文件，声明 $declared_count 文件。考虑更新 FILES 或拆分任务。"
    else
      verdict="EXPLODED"
      suggestion="实际改动 $actual_count 文件，声明 $declared_count 文件。建议回 GATE 1 重新评估。"
    fi
  else
    if [[ "$actual_count" -gt 0 ]]; then
      verdict="NO_DECLARATION"
      suggestion="找不到任务的 FILES 声明。请确保 TASK-TEMPLATE 已填写。"
    else
      verdict="CLEAN"
    fi
  fi

  # 输出
  echo "=== SCOPE CHECK ==="
  if [[ -n "$task_id" ]]; then
    echo "Task: $task_id — $task_desc"
  fi
  echo "Declared files: $declared_count"
  echo "Actual changed: $actual_count"
  echo "Drift ratio:    $drift_ratio"
  echo "Verdict:        $verdict"

  if [[ -n "$actual_files" ]]; then
    echo ""
    echo "Changed files:"
    echo "$actual_files" | head -20 | sed 's/^/  /'
    if [[ "$actual_count" -gt 20 ]]; then
      echo "  ... and $((actual_count - 20)) more"
    fi
  fi

  if [[ -n "$suggestion" ]]; then
    echo ""
    echo "Suggestion: $suggestion"
  fi

  # 退出码
  case "$verdict" in
    OK|CLEAN) exit 0 ;;
    DRIFTED|NO_DECLARATION) exit 0 ;;  # warn 但不阻塞
    EXPLODED) exit 1 ;;
    *) exit 0 ;;
  esac
}

# ---- 子命令: checkpoint ----
# 检查是否需要触发确认检查点

cmd_checkpoint() {
  if [[ ! -f "$STATUS_FILE" ]]; then
    echo "No status.md found. Skipping checkpoint check."
    exit 0
  fi

  local optimistic_count deferred_count
  optimistic_count=$(count_decisions "optimistic")
  deferred_count=$(count_decisions "deferred")

  # 检查 AUTONOMOUS 模式
  local autonomous="false"
  if grep -qi 'AUTONOMOUS:\s*true' "$STATUS_FILE" 2>/dev/null; then
    autonomous="true"
  fi

  local threshold=5
  if [[ "$autonomous" == "true" ]]; then
    threshold=10
  fi

  local checkpoint_needed="false"
  local reasons=""

  # 条件 1：optimistic 累积超过阈值
  if [[ "$optimistic_count" -ge "$threshold" ]]; then
    checkpoint_needed="true"
    reasons="${reasons}optimistic 项已达 ${optimistic_count} (阈值 ${threshold}); "
  fi

  # 条件 2：deferred 项被过多任务依赖（简化检查：deferred > 3 就警告）
  if [[ "$deferred_count" -ge 3 ]]; then
    checkpoint_needed="true"
    reasons="${reasons}deferred 项已达 ${deferred_count}, 可能存在隐式依赖; "
  fi

  # 输出
  echo "=== CHECKPOINT CHECK ==="
  echo "Mode:           $([ "$autonomous" == "true" ] && echo "autonomous" || echo "supervised")"
  echo "Threshold:      $threshold"
  echo "Optimistic:     $optimistic_count"
  echo "Deferred:       $deferred_count"
  echo "Checkpoint due: $checkpoint_needed"

  if [[ "$checkpoint_needed" == "true" ]]; then
    echo ""
    echo "Reasons: $reasons"
    echo ""
    if [[ "$autonomous" == "true" ]]; then
      echo "Action: 写入 status.md 检查点记录，继续执行。"
    else
      echo "Action: 触发检查点，输出待确认项清单，等待用户确认。"
    fi
    exit 1  # 非零退出码，提示需要处理
  fi

  exit 0
}

# ---- 子命令: lessons ----
# 扫描结构信号写入 docs/lessons.md（append-only，一行一条）
# 原则：不让 AI 自证。教训来自可机械检测的外部信号，不来自 AI 反思。
#
# 扫描源：
#   1. status.md 中 `invalidated` 状态的决策
#   2. status.md "放弃的方案" 章节
#   3. git log: 短期返工（一个 commit 修改了前 N 个 commit 刚加的代码）
#   4. 任务实际 FILES 与声明偏差 > 50%（依赖 scope 检查历史）

cmd_lessons() {
  local phase
  phase=$(get_phase)
  local today
  today=$(date +%Y-%m-%d)

  mkdir -p "$(dirname "$LESSONS_FILE")"
  if [[ ! -f "$LESSONS_FILE" ]]; then
    cat > "$LESSONS_FILE" << 'HEADEOF'
# 历史教训（lessons.md）

> 由 `scripts/ai-rules.sh lessons` 基于结构信号自动追加。不手动编辑。
> 消费点：每次 /spec 开始时强制 grep，作为新需求评估的输入。
>
> 格式：[日期] [phase] [信号类型] [一句话摘要] [相关文件]

HEADEOF
  fi

  local added=0
  local tmpfile
  tmpfile=$(mktemp)

  # -------- 信号 1: invalidated 决策 --------
  if [[ -f "$STATUS_FILE" ]]; then
    # 匹配格式：`...invalidated...` 行，取同行或上下文的描述
    # 注意：grep 无匹配返回 1，配合 || true 避免 pipefail 终止脚本
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local summary
      summary=$(echo "$line" | sed 's/^[0-9]*://' | tr -d '\n' | head -c 200)
      # 去重：已存在则跳过
      if ! grep -Fq "$summary" "$LESSONS_FILE" 2>/dev/null; then
        echo "[$today] [$phase] [invalidated] $summary [status.md]" >> "$tmpfile"
      fi
    done < <(grep -nE 'invalidated' "$STATUS_FILE" 2>/dev/null || true)
  fi

  # -------- 信号 2: 放弃的方案 --------
  if [[ -f "$STATUS_FILE" ]]; then
    # 从 "## 放弃的方案" 章节提取条目
    while IFS= read -r entry; do
      [[ -z "$entry" ]] && continue
      local summary
      summary=$(echo "$entry" | sed 's/^-[[:space:]]*//' | tr -d '\n' | head -c 200)
      if [[ -n "$summary" ]] && ! grep -Fq "$summary" "$LESSONS_FILE" 2>/dev/null; then
        echo "[$today] [$phase] [abandoned] $summary [status.md]" >> "$tmpfile"
      fi
    done < <(awk '
      /^##[[:space:]]*放弃的方案/ { in_section=1; next }
      /^##[[:space:]]/ && in_section { in_section=0 }
      in_section && /^-[[:space:]]/ { print }
    ' "$STATUS_FILE" 2>/dev/null || true)
  fi

  # -------- 信号 3: 短期返工（git log 分析） --------
  # 一个 commit 修改了最近 5 个 commit 刚加的文件 → 标记
  # 放宽 set -eu 约束，任何单步失败静默跳过（该信号非关键路径）
  if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    set +eu
    local recent_commits commit_array=() c
    recent_commits=$(git -C "$ROOT" log --format="%H" -20 2>/dev/null)
    while IFS= read -r c; do
      [[ -n "${c:-}" ]] && commit_array+=("$c")
    done <<< "$recent_commits"

    local i=0 len=${#commit_array[@]}
    while [[ $i -lt $((len - 5)) ]] 2>/dev/null; do
      local cur="${commit_array[$i]}"
      local cur_files
      cur_files=$(git -C "$ROOT" show --name-only --format="" "$cur" 2>/dev/null | sort -u)
      if [[ -n "$cur_files" ]]; then
        local j=$((i + 1))
        local lookahead_end=$((i + 6))
        [[ $lookahead_end -gt $len ]] && lookahead_end=$len
        while [[ $j -lt $lookahead_end ]]; do
          local prev="${commit_array[$j]}"
          local prev_files
          prev_files=$(git -C "$ROOT" show --name-only --format="" "$prev" 2>/dev/null | sort -u)
          local overlap=0
          if [[ -n "$prev_files" ]]; then
            overlap=$(comm -12 <(printf '%s\n' "$cur_files") <(printf '%s\n' "$prev_files") 2>/dev/null | wc -l | tr -d ' ')
            overlap=${overlap:-0}
          fi
          if [[ "$overlap" =~ ^[0-9]+$ ]] && [[ "$overlap" -ge 2 ]]; then
            local cur_msg short_hash summary
            cur_msg=$(git -C "$ROOT" log -1 --format="%s" "$cur" 2>/dev/null)
            cur_msg=${cur_msg:-"(no message)"}
            short_hash=${cur:0:7}
            summary="短期返工 — ${cur_msg} (${overlap} 个文件与前 commit 重叠)"
            if ! grep -Fq "$short_hash" "$LESSONS_FILE" 2>/dev/null; then
              echo "[$today] [$phase] [rework] $summary [$short_hash]" >> "$tmpfile"
            fi
            break
          fi
          j=$((j + 1))
        done
      fi
      i=$((i + 1))
    done
    set -eu
  fi

  # -------- 写入 --------
  if [[ -s "$tmpfile" ]]; then
    added=$(wc -l < "$tmpfile" | tr -d ' ')
    cat "$tmpfile" >> "$LESSONS_FILE"
  fi
  rm -f "$tmpfile"

  echo "=== LESSONS SCAN ==="
  echo "Target:    $LESSONS_FILE"
  echo "Phase:     $phase"
  echo "Added:     $added new entries"
  echo "Total:     $(grep -c '^\[' "$LESSONS_FILE" 2>/dev/null || echo 0) entries"
  echo ""
  echo "Consumption point: 每次 /spec 开始时由 AI 强制 grep 此文件。"

  exit 0
}

# ---- 子命令: next-task ----
# 在 commit 完成后，根据 status.md 判断下一步行动
# 输出一段 system-reminder 文案，由 post-commit hook 注入到 AI 上下文
# 目的：消除 AI 在任务间续接处"礼貌性询问"的 reflex
#
# 输出格式（始终到 stdout，退出码始终 0）：
#   无 status.md 或无待办     → 空输出（hook 不注入）
#   待办存在 + 检查点未触发   → CONTINUE 提示
#   待办存在 + optimistic≥5   → CHECKPOINT 提示
#   全部完成                 → ALL_DONE 提示

cmd_next_task() {
  [[ ! -f "$STATUS_FILE" ]] && exit 0

  local pending done_count optimistic deferred
  pending=$(count_tasks " ")
  done_count=$(count_tasks "x")
  optimistic=$(count_decisions "optimistic")
  deferred=$(count_decisions "deferred")

  # 无任何任务清单 → 静默
  if [[ "$pending" -eq 0 && "$done_count" -eq 0 ]]; then
    exit 0
  fi

  # AUTONOMOUS 模式阈值调整
  local threshold=5
  if grep -qi 'AUTONOMOUS:\s*true' "$STATUS_FILE" 2>/dev/null; then
    threshold=10
  fi

  if [[ "$pending" -eq 0 ]]; then
    cat <<EOF
[ai-rules next-task] status.md 中所有任务已完成。
可以停下来汇报状态，不需要继续。
EOF
    exit 0
  fi

  if [[ "$optimistic" -ge "$threshold" ]]; then
    cat <<EOF
[ai-rules next-task] CHECKPOINT REQUIRED
optimistic 项累计 ${optimistic} (阈值 ${threshold}).
根据 core.md 批量检查点规则，必须先输出"待确认项清单"让用户过目，
不要直接进入下一个任务。清单格式见 core.md "检查点输出格式"。
EOF
    exit 0
  fi

  # 检查熔断状态
  local fuse_level="none"
  if [[ -f "$ROOT/.claude/state/fuse-state.json" ]] && command -v jq >/dev/null 2>&1; then
    fuse_level=$(jq -r '.level // "none"' "$ROOT/.claude/state/fuse-state.json" 2>/dev/null)
  fi

  # 硬熔断 → 停止一切
  if [[ "$fuse_level" == "hard" ]]; then
    cat <<EOF
[ai-rules next-task] 硬熔断中 — 停止所有执行。
连续多个任务触发软熔断，可能存在全局性问题。
等待人工介入。解锁命令: scripts/ai-rules.sh fuse reset
**不要继续执行任何任务。**
EOF
    exit 0
  fi

  # 提取下一个未完成且未熔断的任务（跳过 [FUSED] 标记的任务）
  local next_desc=""
  next_desc=$(grep -E '^\s*-\s*\[ \]' "$STATUS_FILE" 2>/dev/null \
    | grep -v '\[FUSED\]' \
    | head -1 \
    | sed 's/^[[:space:]]*-[[:space:]]*\[ \][[:space:]]*//' \
    | cut -c1-120)

  # 如果所有未完成任务都被 fused/阻塞
  if [[ -z "$next_desc" && "$pending" -gt 0 ]]; then
    cat <<EOF
[ai-rules next-task] status.md 中有 $pending 个待办任务，但全部被标记为 [FUSED] 或阻塞。
停下汇报状态。运行 scripts/ai-rules.sh fuse report 查看详情。
EOF
    exit 0
  fi

  # 检测下一任务是否阻塞在人工动作（HUMAN: action:XX 引用前置清单）
  local task_id="" actions=""
  task_id=$(echo "$next_desc" | grep -oE 'T[0-9]+' | head -1)
  if [[ -n "$task_id" && -f "$ROOT/docs/spec.md" ]]; then
    local task_block
    # 提取 TASK: T{N} 开始到下一个 TASK: 或 --- 之间的内容
    task_block=$(awk -v tid="$task_id" '
      /^TASK:/ { if (in_block) exit; if ($0 ~ tid"[^0-9]" || $0 ~ tid"$") { in_block=1 } }
      in_block { print }
      /^---$/ && in_block && NR > 1 { exit }
    ' "$ROOT/docs/spec.md" 2>/dev/null)
    actions=$(echo "$task_block" | grep -oE 'action:[A-D][0-9]+' 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//' || true)
  fi

  if [[ -n "$actions" ]]; then
    # 抽取对应前置清单条目摘要
    local summary="" id
    for ref in $(echo "$actions" | tr ',' ' '); do
      id="${ref#action:}"
      local line
      line=$(grep -E "^[[:space:]]*-[[:space:]]*\[[[:space:]]*\][[:space:]]+${id}[:：]" "$ROOT/docs/spec.md" 2>/dev/null | head -1 | sed -E 's/^[[:space:]]*-[[:space:]]*\[[[:space:]]*\][[:space:]]+//' | cut -c1-100)
      [[ -n "$line" ]] && summary="${summary}${line}; "
    done
    summary="${summary%; }"
    cat <<EOF
[ai-rules next-task] 下一任务 ${task_id} 阻塞在人工动作: ${actions}

前置清单摘要: ${summary:-（未找到对应条目, 检查 spec 顶部前置清单编号）}

根据 /impl SKILL.md "人工动作交接"硬规则:
你的最后一行必须输出（单独一行）:
「等你: ${summary:-<spec 前置清单条目>}。完成后说"前置已就绪"。」

不要直接进下一任务开干, 不要只在 status.md 写"下一步", 必须在对话里明说等谁做什么。
EOF
    exit 0
  fi

  cat <<EOF
[ai-rules next-task] commit 完成。status.md 中还有 $pending 个待办任务。
下一个：${next_desc:-（未能自动解析，请查 status.md）}

按 CLAUDE.md "任务链自动续接" 规则：
  清单里有任务、无阻塞、未触发检查点 → 直接开始下一个。
  **禁止问"要继续吗？"**。
  下一条消息应直接进入下一个任务的 GATE 1 自检，不做铺垫。

若该任务有 deferred 依赖、[FUSED] 标记或其他阻塞，跳过它找下一个无阻塞的任务；
全部阻塞才停下汇报。
EOF
  exit 0
}

# ---- 子命令: continue-check ----
# 从 stdin 读取最后一条 assistant 消息，检测 politeness reflex 模式
# 目的：覆盖 post-commit hook 覆盖不到的场景——调试中间的临时决策被包装成提问
#
# 触发条件（全部满足才注入）：
#   1. 消息命中 politeness reflex 关键词
#   2. status.md 存在且有待办任务
#   3. 消息中没有显式的 BLOCKED: 或"不可逆操作"声明（escape hatch）
#
# 输出：violation 时写提醒到 stdout，退出码 0
#       无违规时静默，退出码 0
# hook 层面根据 stdout 是否为空决定是否 exit 2

cmd_continue_check() {
  local msg
  msg=$(cat)

  if [[ -z "$msg" ]]; then
    exit 0
  fi

  # Politeness reflex 模式（具体短语，避免误伤正常 clarification）
  # 含裸结尾型：继续？/继续?/下一个？/下一步？/开始吗？ 独立成句（末尾或后跟空白/换行）
  local patterns='要我继续吗|要继续吗|是否继续|需要你定|需要您定|需要你决定|需要您决定|要不要我继续|要不要继续|要不要我做|要不要做|两条路.*需要你|两条路.*您选|两种方案.*你选|两种方案.*您选|您来决定|你来决定|(^|[。！；.\n[:space:]])继续[?？]($|[[:space:]])|(^|[。！；.\n[:space:]])下一个[?？]($|[[:space:]])|(^|[。！；.\n[:space:]])下一步[?？]($|[[:space:]])|可以开始吗|可以继续吗|开始吗[?？]|(^|[。！；.\n[:space:]])哪[边个条种][?？]|先做.*还是.*[?？]|优先做.*还是.*[?？]|(^|[。！；.\n[:space:]])选哪[边个条种个]'

  if ! echo "$msg" | grep -qE "$patterns"; then
    exit 0
  fi

  # Escape hatch：显式声明不可逆操作或硬阻塞
  if echo "$msg" | grep -qE 'BLOCKED:|EXPLICIT_BLOCK:|不可逆操作|硬阻塞|无法自动化|需要人工权限'; then
    exit 0
  fi

  # 必须有 status.md 上下文才干预（避免干扰非方法论项目）
  if [[ ! -f "$STATUS_FILE" ]]; then
    exit 0
  fi

  local pending
  pending=$(count_tasks " ")
  if [[ "$pending" -eq 0 ]]; then
    exit 0
  fi

  # 输出提醒
  cat <<EOF
[ai-rules continue-check] 检测到 politeness reflex 模式。

命中关键词：上一条回复包含"要继续吗/需要你定/两条路..."这类询问模式。
当前状态：status.md 有 $pending 个待办任务，未声明 BLOCKED 或不可逆操作。

根据 core.md GATE 2 回滚成本路由：
  - 可测试的 → 不问，写测试验证
  - 技术路径选择且双方案都可逆（低回滚成本）→ 选默认方案继续，记为 optimistic
  - 高回滚成本但不阻塞后续 → 标记 deferred，做别的任务
  - 真正的阻塞（不可逆 / 安全底线 / 硬约束）→ 在消息中显式写 "BLOCKED: <原因>"

请重新评估上一条回复并继续：
  - 若是任务续接 → 直接进入下一个任务的 GATE 1 自检
  - 若是路径选择 → 选择默认方案执行，把备选方案记入 status.md 待确认清单
  - 若是真阻塞 → 重写回复，开头加 "BLOCKED: <具体原因>"
EOF
  exit 0
}

# ---- 子命令: tail-marker-check ----
# 从 stdin 读取最后一条 assistant 消息, 校验是否以合法结束标记收尾
# 允许列表 (allow-list): 完成:/等你:/停住: (ASCII 等价: DONE:/AWAIT:/HALT:)
#
# 核心收敛逻辑:
#   1. 剥 fenced code blocks (```...```)
#   2. 取最后非空行
#   3. 顶格 + 标记 + 冒号 + ≥1 可见字符 → 放行
#   4. 否则 emit 缺失诊断
#
# 相比关键词 denylist: 封闭 allow-list, 语法级判定, 与措辞无关
# 退出码: 0 = 合法结尾, 1 = 缺失/非法, stdout 带诊断

cmd_tail_marker_check() {
  local msg
  msg=$(cat)

  if [[ -z "$msg" ]]; then
    echo "EMPTY_MESSAGE: 最后一条 assistant 消息为空, 无法校验结束标记"
    exit 1
  fi

  # 剥 fenced code block (``` 起止, 含语言标签如 ```bash)
  local clean
  clean=$(echo "$msg" | awk '
    /^```/ { fenced = !fenced; next }
    !fenced { print }
  ')

  # 最后非空行 (trim trailing blanks)
  local last_line
  last_line=$(echo "$clean" | awk 'NF { line = $0 } END { print line }')

  # 严格语法: 顶格 + (完成|等你|停住|DONE|AWAIT|HALT) + 冒号(半/全角) + SP* + \S
  if echo "$last_line" | grep -qE '^(完成|等你|停住|DONE|AWAIT|HALT)[:：][[:space:]]*[^[:space:]]'; then
    exit 0
  fi

  cat <<EOF
STOP_MARKER_MISSING
AI 最后一条消息未以合法结束标记收尾。必须以下列之一独占最后一行:
  完成: <一句话全部交付描述>   — 任务链跑完, 无待办
  等你: <具体等谁做什么>        — 阻塞在人工动作/决策
  停住: <hook 阻塞原因>         — 响应 emit_blocked
  DONE: / AWAIT: / HALT: 同义 ASCII 版

规则:
  - 标记必须在最后一条文本 message 的最后非空行
  - 标记必须顶格 (无缩进)
  - 标记必须不在 \`\`\` 代码块内
  - 冒号 (半角: 或全角：) 之后 ≥ 1 个可见字符

实际最后一行收到: $(echo "$last_line" | head -c 120)

下一回复必须以合法标记收尾。这不是黑名单关键词规避, 是显式语法约定。
EOF
  exit 1
}

# ---- 原子检查函数 ----
# 每个函数：检查一件事，通过返回空串，不通过返回失败描述
# 所有函数可独立调用、独立测试

# -- spec 检查项 --

sg_spec_file_exists() {
  [[ -f "$1" ]] || echo "docs/spec.md 不存在"
}

sg_spec_size_warning() {
  # Read 工具默认 2000 行截断，1800 行开始预警。仅 warning，不阻塞。
  # 超限时建议拆 docs/spec/{tasks,failures,coverage,frozen}.md 并升级 skill-gate 多文件扫描。
  local file="$1"
  [[ ! -f "$file" ]] && return
  local lines
  lines=$(wc -l <"$file" 2>/dev/null | tr -d ' ') || lines=0
  if [[ "$lines" -gt 1800 ]]; then
    echo "spec.md 已 ${lines} 行，逼近 Read 工具 2000 行截断阈值。建议按 INDEX 路由拆分 docs/spec/ 子目录，并同步升级 skill-gate 为多文件扫描"
  fi
}

_is_ui_project() {
  # 判断是否为 UI 项目。返回 0=是，1=否
  local root="$1"
  [[ ! -d "$root" ]] && return 1
  local fe_files
  fe_files=$(find "$root" -maxdepth 4 \
    \( -name "*.vue" -o -name "*.tsx" -o -name "*.jsx" \
    -o -name "*.svelte" -o -name "*.css" -o -name "*.scss" \
    -o -name "*.wxml" -o -name "*.wxss" \) \
    2>/dev/null | grep -v node_modules | grep -v '.claude' | head -1)
  [[ -n "$fe_files" ]] && return 0
  if [[ -f "$ROOT/docs/spec.md" ]]; then
    grep -qiE '页面|UI|前端|[Ff]rontend|组件|[Cc]omponent|布局|[Ll]ayout' "$ROOT/docs/spec.md" 2>/dev/null && return 0
  fi
  return 1
}

sg_spec_design_md() {
  # UI 项目必须有 DESIGN.md + 内容完整（9 个标准章节）
  local root="$1"
  _is_ui_project "$root" || return
  # 1. 文件存在
  if [[ ! -f "$root/DESIGN.md" ]]; then
    echo "检测到 UI 项目但缺少 DESIGN.md (可用 npx getdesign@latest add <brand> 获取参考)"
    return
  fi
  local dm="$root/DESIGN.md"
  # 2. 9 个标准章节完整性检查
  local missing_sections=""
  local missing_count=0
  # 章节名 → 正则（支持中英文）
  local section_patterns=(
    "Visual Theme|视觉主题|视觉风格|设计风格"
    "Color Palette|颜色|色彩|配色"
    "Typography|排版|字体"
    "Component Styl|组件样式|组件规范"
    "Layout|布局"
    "Depth|Elevation|阴影|层级"
    "Do.*Don|护栏|设计规范"
    "Responsive|响应式|断点"
    "Agent Prompt|Prompt Guide|快速参考"
  )
  local section_names=(
    "Visual Theme" "Color Palette" "Typography" "Component Stylings"
    "Layout" "Depth & Elevation" "Do's and Don'ts" "Responsive" "Agent Prompt Guide"
  )
  for idx in 0 1 2 3 4 5 6 7 8; do
    if ! grep -qiE "^#+\s.*(${section_patterns[$idx]})" "$dm" 2>/dev/null; then
      missing_sections="${missing_sections} [${section_names[$idx]}]"
      missing_count=$((missing_count + 1))
    fi
  done
  if [[ "$missing_count" -gt 3 ]]; then
    echo "DESIGN.md 缺少 ${missing_count} 个标准章节:${missing_sections} (需要 9 章节中至少 6 个)"
    return
  fi
  # 3. 颜色章节有 hex 值
  local hex_count
  hex_count=$(grep -coE '#[0-9a-fA-F]{6}|#[0-9a-fA-F]{3}' "$dm" 2>/dev/null) || hex_count=0
  if [[ "$hex_count" -lt 3 ]]; then
    echo "DESIGN.md 颜色定义不足 (仅 ${hex_count} 个 hex 值，需要至少 3 个定义主色/强调色/中性色)"
    return
  fi
  # 4. 排版章节有层级表（至少有 | 分隔的表格行）
  local typo_section
  typo_section=$(awk '/^#+\s.*(Typography|排版|字体)/{found=1;next} found&&/^#+/{exit} found{print}' "$dm" 2>/dev/null)
  if [[ -n "$typo_section" ]]; then
    local typo_rows
    typo_rows=$(echo "$typo_section" | grep -cE '^\|[^-].*\|' 2>/dev/null) || typo_rows=0
    if [[ "$typo_rows" -lt 3 ]]; then
      echo "DESIGN.md 排版章节缺少层级表 (需要字号/字重/行高的层级对照表)"
    fi
  fi
  # 5. 组件章节有实际组件定义
  local comp_section
  comp_section=$(awk '/^#+\s.*(Component|组件)/{found=1;next} found&&/^##[^#]/{exit} found{print}' "$dm" 2>/dev/null)
  if [[ -n "$comp_section" ]]; then
    local comp_count=0
    echo "$comp_section" | grep -qiE '[Bb]utton|按钮' 2>/dev/null && comp_count=$((comp_count + 1))
    echo "$comp_section" | grep -qiE '[Cc]ard|卡片' 2>/dev/null && comp_count=$((comp_count + 1))
    echo "$comp_section" | grep -qiE '[Ii]nput|[Ff]orm|输入|表单' 2>/dev/null && comp_count=$((comp_count + 1))
    echo "$comp_section" | grep -qiE '[Nn]av|导航' 2>/dev/null && comp_count=$((comp_count + 1))
    if [[ "$comp_count" -lt 2 ]]; then
      echo "DESIGN.md 组件章节内容不足 (需要至少定义按钮/卡片/输入框/导航中的 2 种)"
    fi
  fi
}

sg_impl_design_token_consumed() {
  # UI 项目：前端源码必须实际消费 DESIGN.md 里定义的 CSS 变量 token，
  # 防止 "DESIGN.md 完整但代码里用 system-ui + 默认样式" 的静默跑偏。
  local root="$1"
  _is_ui_project "$root" || return
  local dm="$root/DESIGN.md"
  [[ ! -f "$dm" ]] && return

  # 1. 提取 DESIGN.md 中定义的 token 名（形如 `--bg-base`、`--accent-primary`）。
  local tokens
  tokens=$(grep -oE -- '--[a-zA-Z][a-zA-Z0-9-]+' "$dm" 2>/dev/null | sort -u)
  local token_count
  token_count=$(printf '%s\n' "$tokens" | grep -c . 2>/dev/null) || token_count=0
  [[ "$token_count" -lt 5 ]] && return

  # 2. 聚合前端源码（排除 node_modules / build 产物 / playwright test-results）
  local src_files
  src_files=$(find "$root" -maxdepth 6 \
    \( -name "*.css" -o -name "*.scss" -o -name "*.tsx" -o -name "*.jsx" \
    -o -name "*.vue" -o -name "*.svelte" \) \
    -not -path "*/node_modules/*" \
    -not -path "*/.claude/*" \
    -not -path "*/dist/*" \
    -not -path "*/build/*" \
    -not -path "*/test-results/*" \
    -not -path "*/playwright-report/*" \
    2>/dev/null)
  local src_count
  src_count=$(printf '%s\n' "$src_files" | grep -c . 2>/dev/null) || src_count=0
  [[ "$src_count" -lt 3 ]] && return

  # 3. 扫描实际 token 引用（var(--xxx) 或直接 --xxx 出现在源码中）
  local consumed=0
  while IFS= read -r tok; do
    [[ -z "$tok" ]] && continue
    if printf '%s\n' "$src_files" | xargs grep -lF -e "$tok" 2>/dev/null | grep -q .; then
      consumed=$((consumed + 1))
    fi
  done <<< "$tokens"

  # 4. 阈值：消费率 < 30% 且绝对数 < 5 → 判定未按 DESIGN.md 实现
  local coverage_pct=0
  [[ "$token_count" -gt 0 ]] && coverage_pct=$((consumed * 100 / token_count))
  if [[ "$coverage_pct" -lt 30 && "$consumed" -lt 5 ]]; then
    echo "前端代码未消费 DESIGN.md token (DESIGN.md 定义 ${token_count} 个，源码引用 ${consumed} 个，覆盖率 ${coverage_pct}%)。需在 CSS/组件中使用 var(--xxx) 或 import 设计 token，不能用 system-ui + 内联默认样式"
  fi
}

sg_spec_page_specs() {
  # UI 项目的 spec.md 必须有页面规格（按页校验, 非关键词计数）
  # 双层检查:
  #   L1: 全局状态类型覆盖 — 4 类中 ≥ 3 类出现过
  #   L2: 按页覆盖率 — 有页面 header 时, ≥50% 页面各自有 ≥2 种状态定义
  local file="$1" root="$2"
  [[ ! -f "$file" ]] && return
  _is_ui_project "$root" || return

  # L1: 全局 — 4 类状态中覆盖 ≥ 3 类
  local types_covered=0
  grep -qiE '组件清单|组件列表|[Cc]omponent.*[Ll]ist' "$file" 2>/dev/null && types_covered=$((types_covered + 1))
  grep -qiE '空状态|[Ee]mpty.*[Ss]tate|无数据时' "$file" 2>/dev/null && types_covered=$((types_covered + 1))
  grep -qiE '加载态|[Ll]oading.*[Ss]tate|骨架屏|[Ss]keleton' "$file" 2>/dev/null && types_covered=$((types_covered + 1))
  grep -qiE '错误态|[Ee]rror.*[Ss]tate|失败态|重试按钮' "$file" 2>/dev/null && types_covered=$((types_covered + 1))

  if [[ "$types_covered" -lt 3 ]]; then
    echo "UI 项目 spec.md 状态类型覆盖不足 (${types_covered}/4 类, 需 ≥3: 组件清单/空状态/加载态/错误态)"
    return
  fi

  # L2: 按页 — 提取页面 section, 每个 section 内 ≥2 种状态
  local page_lines
  page_lines=$(grep -nE '^#{2,3}\s+.*(页|[Pp]age|[Vv]iew|[Ss]creen|[Dd]ialog|[Mm]odal|[Pp]anel|列表|详情|设置|首页|仪表|[Dd]ashboard)' "$file" 2>/dev/null)
  [[ -z "$page_lines" ]] && return  # 无页面 header, L1 已过, 足够

  local total_pages=0 covered_pages=0 uncovered_names=""
  local file_lines
  file_lines=$(wc -l < "$file")

  while IFS= read -r header_line; do
    [[ -z "$header_line" ]] && continue
    local lnum="${header_line%%:*}"
    local htext="${header_line#*:}"
    htext=$(echo "$htext" | sed 's/^#*\s*//' | cut -c1-40)
    total_pages=$((total_pages + 1))
    # 取 header 后 40 行 (或到文件末)
    local end=$((lnum + 40))
    [[ "$end" -gt "$file_lines" ]] && end="$file_lines"
    local chunk
    chunk=$(sed -n "$((lnum + 1)),${end}p" "$file" 2>/dev/null)
    # 遇到下一个同级 header 截断
    chunk=$(echo "$chunk" | sed '/^#{2,3}\s/,$d')
    local sec_types=0
    echo "$chunk" | grep -qiE '组件清单|组件列表|[Cc]omponent' 2>/dev/null && sec_types=$((sec_types + 1))
    echo "$chunk" | grep -qiE '空状态|[Ee]mpty|无数据' 2>/dev/null && sec_types=$((sec_types + 1))
    echo "$chunk" | grep -qiE '加载态|[Ll]oading|骨架屏' 2>/dev/null && sec_types=$((sec_types + 1))
    echo "$chunk" | grep -qiE '错误态|[Ee]rror.*[Ss]tate|失败|重试' 2>/dev/null && sec_types=$((sec_types + 1))
    if [[ "$sec_types" -ge 2 ]]; then
      covered_pages=$((covered_pages + 1))
    else
      uncovered_names="${uncovered_names} [${htext}]"
    fi
  done <<< "$page_lines"

  if [[ "$total_pages" -ge 2 ]]; then
    local coverage_pct=$((covered_pages * 100 / total_pages))
    if [[ "$coverage_pct" -lt 50 ]]; then
      echo "UI 页面状态覆盖率 ${coverage_pct}% (${covered_pages}/${total_pages} 页). 缺状态定义:${uncovered_names}. 每页需组件清单+空状态/加载态/错误态中 ≥2 种"
    fi
  fi
}

sg_spec_prd_challenge() {
  local file="$1"
  # 1. 章节存在
  if ! grep -qE '^#{2,4}\s.*(PRD.*挑战|PRD.*[Cc]hallenge|需求挑战|[Rr]equirement.*[Cc]hallenge)' "$file" 2>/dev/null; then
    echo "spec.md 缺少「PRD 挑战」章节"
    return
  fi
  # 提取 PRD 挑战章节：从标题行到下一个同级或更高级标题
  # 使用 awk 而非 sed，因为子标题（###/####）属于章节内部不应截断
  local section
  section=$(awk '
    /^#{2,4} .*(PRD.*挑战|PRD.*[Cc]hallenge|需求挑战|Rr]equirement.*[Cc]hallenge)/ { found=1; level=0; for(i=1;i<=length($1);i++) if(substr($1,i,1)=="#") level++; next }
    found && /^#{2,4} / { cur=0; for(i=1;i<=length($1);i++) if(substr($1,i,1)=="#") cur++; if(cur<=level) exit }
    found { print }
  ' "$file" 2>/dev/null)
  # 2. 五个视角覆盖至少 3 个（在 PRD 挑战章节内或整个文件中搜索子标题）
  local lens_count=0
  echo "$section" | grep -qiE '状态完整性|[Ss]tate.*[Cc]ompleteness|状态转换' 2>/dev/null && lens_count=$((lens_count + 1))
  echo "$section" | grep -qiE '边界条件|[Bb]oundary.*[Cc]ondition' 2>/dev/null && lens_count=$((lens_count + 1))
  echo "$section" | grep -qiE '多角色一致性|[Mm]ulti.*[Aa]ctor|角色一致' 2>/dev/null && lens_count=$((lens_count + 1))
  echo "$section" | grep -qiE '时序敏感|[Tt]emporal|时序' 2>/dev/null && lens_count=$((lens_count + 1))
  echo "$section" | grep -qiE '数据生命周期|[Dd]ata.*[Ll]ifecycle|数据生命' 2>/dev/null && lens_count=$((lens_count + 1))
  if [[ "$lens_count" -lt 3 ]]; then
    echo "PRD 挑战仅覆盖 ${lens_count} 个视角 (需要状态完整性/边界条件/多角色一致性/时序敏感/数据生命周期中至少 3 个)"
    return
  fi
  # 3. 有编号缺口条目
  local gap_count
  gap_count=$(echo "$section" | grep -cE '^\s*[-*]\s|^\s*[0-9]+[\.\、)）]') || gap_count=0
  if [[ "$gap_count" -eq 0 ]]; then
    echo "PRD 挑战有视角但无具体缺口条目"
    return
  fi
  # 4. 缺口有处置标注
  local annotated
  annotated=$(echo "$section" | grep -ciE '补入|deferred|不适用|已补|spec.*补|N/A|covered') || annotated=0
  if [[ "$annotated" -eq 0 ]]; then
    echo "PRD 挑战有 ${gap_count} 个缺口但无处置标注 (需标注 补入spec/deferred/不适用)"
    return
  fi
  # 5. "补入 spec" 的缺口必须有对应 TASK 或 ACCEPT（内容可追溯性）
  local adopt_count adopt_no_task
  adopt_count=$(echo "$section" | grep -ciE '补入\s*spec|补入$') || adopt_count=0
  if [[ "$adopt_count" -gt 0 ]]; then
    # 提取补入 spec 的缺口编号（G-N 或纯数字）
    adopt_no_task=0
    while IFS= read -r line; do
      # 从缺口行提取关键词（去掉编号和标注后的核心描述，取前 6 个字）
      local keywords
      keywords=$(echo "$line" | sed -E 's/.*缺口\s*[A-Za-z]*-?[0-9]*[：:]\s*//' | sed -E 's/\s*—.*//' | head -c 30)
      [[ -z "$keywords" ]] && continue
      # 检查 spec 全文（排除 PRD 挑战章节本身）是否有对应 TASK/ACCEPT 引用
      if ! grep -qiE 'ACCEPT:|TASK:' "$file" 2>/dev/null; then
        adopt_no_task=$((adopt_no_task + adopt_count))
        break
      fi
    done <<< "$(echo "$section" | grep -iE '补入\s*spec|补入$')"
    # 简化检查：有"补入 spec"标注但全文无 TASK/ACCEPT → 缺口没落地
    if ! grep -qiE '^TASK:|^ACCEPT:' "$file" 2>/dev/null; then
      echo "PRD 挑战有 ${adopt_count} 个「补入 spec」缺口但 spec 中无 TASK/ACCEPT 承接"
    fi
  fi
  # 6. 每个视角标题下必须有 ≥1 个缺口（不能空挂标题）
  local empty_lenses=""
  local empty_lens_count=0
  local lens_patterns=("状态完整性|[Ss]tate.*[Cc]ompleteness" "边界条件|[Bb]oundary" "多角色一致性|[Mm]ulti.*[Aa]ctor" "时序敏感|[Tt]emporal" "数据生命周期|[Dd]ata.*[Ll]ifecycle")
  local lens_names=("状态完整性" "边界条件" "多角色一致性" "时序敏感" "数据生命周期")
  for idx in 0 1 2 3 4; do
    local pat="${lens_patterns[$idx]}"
    local name="${lens_names[$idx]}"
    # 检查该视角是否出现在章节中
    if echo "$section" | grep -qiE "$pat" 2>/dev/null; then
      # 提取该视角到下一个视角之间的内容
      local lens_section
      lens_section=$(echo "$section" | awk -v pat="$pat" '
        BEGIN { IGNORECASE=1 }
        $0 ~ pat { found=1; next }
        found && /^###/ { exit }
        found { print }
      ')
      local lens_gaps
      lens_gaps=$(echo "$lens_section" | grep -cE '^\s*[-*]\s|^\s*[0-9]+[\.\、)）]|缺口') || lens_gaps=0
      if [[ "$lens_gaps" -eq 0 ]]; then
        empty_lenses="${empty_lenses} ${name}"
        empty_lens_count=$((empty_lens_count + 1))
      fi
    fi
  done
  if [[ "$empty_lens_count" -gt 0 ]]; then
    echo "PRD 挑战中以下视角有标题但无具体缺口:${empty_lenses}"
  fi
}

sg_spec_failure_imagination() {
  local file="$1"
  # 1. 章节存在
  if ! grep -qE '^#{2,3}\s.*(故障想象力|故障.*标题|[Ff]ailure.*[Ii]magination|[Ff]ailure.*[Hh]eadline)' "$file" 2>/dev/null; then
    echo "spec.md 缺少「故障想象力」章节"
    return
  fi
  local section
  section=$(sed -nE '/^#{2,3} .*(故障想象力|故障.*标题|[Ff]ailure.*[Ii]magination)/,/^#{2,3}[^#]/p' "$file" 2>/dev/null)
  # 2. 维度枚举（至少 2 个维度头）
  local dim_count=0
  echo "$section" | grep -qiE '故障主体|[Ff]ault.*[Ss]ubject' 2>/dev/null && dim_count=$((dim_count + 1))
  echo "$section" | grep -qiE '故障时机|[Ff]ault.*[Tt]iming' 2>/dev/null && dim_count=$((dim_count + 1))
  echo "$section" | grep -qiE '故障表现|[Ff]ault.*[Mm]anifestation' 2>/dev/null && dim_count=$((dim_count + 1))
  if [[ "$dim_count" -lt 2 ]]; then
    echo "故障想象力缺少维度枚举 (需要故障主体/故障时机/故障表现中至少 2 个维度，当前 ${dim_count} 个)"
    return
  fi
  # 3. 有编号条目（不设固定阈值，但必须有）
  local count
  count=$(echo "$section" | grep -cE '^\s*[0-9]+[\.\、)）]') || count=0
  if [[ "$count" -eq 0 ]]; then
    echo "故障想象力有维度枚举但无编号条目"
  fi
}

sg_spec_critical_modules() {
  local file="$1"
  # 1. 章节必须存在（"核心难点"或"无核心难点"显式声明）
  if grep -qiE '无核心难点|no.*critical|无难点' "$file" 2>/dev/null; then
    return  # 显式声明无难点，通过
  fi
  if ! grep -qiE '^#{2,4}\s.*(核心难点|[Cc]ritical.*[Mm]odule|[Cc]ore.*[Dd]ifficult)' "$file" 2>/dev/null; then
    echo "spec.md 缺少「核心难点」章节 (如无难点请显式声明「无核心难点」)"
    return
  fi
  # 2. 有 [CRITICAL] 标记时，必须有方案选择（≥2 方案行）
  local critical_count
  critical_count=$(grep -c '\[CRITICAL\]' "$file" 2>/dev/null) || critical_count=0
  if [[ "$critical_count" -gt 0 ]]; then
    # 检查方案表格：至少有 2 行以 | 开头且包含方案内容（排除表头分隔行）
    local section
    section=$(awk '/^#{2,4} .*(核心难点|[Cc]ritical)/{found=1;level=0;for(i=1;i<=length($1);i++)if(substr($1,i,1)=="#")level++;next} found&&/^#{2,4} /{cur=0;for(i=1;i<=length($1);i++)if(substr($1,i,1)=="#")cur++;if(cur<=level)exit} found{print}' "$file" 2>/dev/null)
    local plan_rows
    plan_rows=$(echo "$section" | grep -cE '^\|[^-].*\|.*\|' 2>/dev/null) || plan_rows=0
    # 减去表头行（通常 1 行表头）
    if [[ "$plan_rows" -lt 3 ]]; then
      echo "核心难点有 ${critical_count} 个 [CRITICAL] 标记但方案选择不足 (需要 ≥2 个方案的对比表格)"
      return
    fi
    # 验证策略三件套：最小验证 + 失败信号 + 回退方案
    local verify_count=0
    echo "$section" | grep -qiE '最小验证|[Mm]inimal.*[Vv]erif|最小实验' 2>/dev/null && verify_count=$((verify_count + 1))
    echo "$section" | grep -qiE '失败信号|[Ff]ailure.*[Ss]ignal|失败标志' 2>/dev/null && verify_count=$((verify_count + 1))
    echo "$section" | grep -qiE '回退方案|[Ff]allback|[Rr]ollback.*[Pp]lan|回退|备选' 2>/dev/null && verify_count=$((verify_count + 1))
    if [[ "$verify_count" -lt 2 ]]; then
      echo "核心难点有方案对比但验证策略不完整 (需要最小验证/失败信号/回退方案中至少 2 项，当前 ${verify_count} 项)"
    fi
  fi
}

sg_spec_coverage_contract() {
  local file="$1"
  grep -qiE '覆盖契约|coverage.*contract' "$file" 2>/dev/null || echo "spec.md 缺少「覆盖契约」章节"
}

sg_spec_task_template() {
  local file="$1"
  local task_count accept_count files_count
  task_count=$(grep -cE '^TASK:' "$file" 2>/dev/null) || task_count=0
  accept_count=$(grep -cE '^ACCEPT:' "$file" 2>/dev/null) || accept_count=0
  files_count=$(grep -cE '^FILES:' "$file" 2>/dev/null) || files_count=0
  if [[ "$task_count" -eq 0 ]]; then
    echo "spec.md 没有 TASK-TEMPLATE 格式的任务"
    return
  fi
  if [[ "$accept_count" -lt "$task_count" ]]; then
    echo "有 ${task_count} 个 TASK 但只有 ${accept_count} 个 ACCEPT 验收标准"
  fi
  if [[ "$files_count" -lt "$task_count" ]]; then
    echo "有 ${task_count} 个 TASK 但只有 ${files_count} 个 FILES 声明"
  fi
}

sg_status_file_exists() {
  [[ -f "$1" ]] || echo "docs/status.md 不存在"
}

# -- spec 故障想象力质量 proxy --

sg_spec_fi_has_subjects() {
  # 每条故障必须有主语（用户/调用者/管理员等），少于 60% 有主语 → 打回
  local file="$1"
  local section
  section=$(sed -nE '/故障想象力|故障.*标题|[Ff]ailure.*[Ii]magination/,/^##[^#]/p' "$file" 2>/dev/null)
  if [[ -z "$section" ]]; then
    return  # 章节不存在由其他检查负责
  fi
  local total with_subject
  total=$(echo "$section" | grep -cE '^\s*[0-9]+[\.\、)）]') || total=0
  if [[ "$total" -eq 0 ]]; then
    return
  fi
  with_subject=$(echo "$section" | grep -E '^\s*[0-9]+[\.\、)）]' \
    | grep -ciE '用户|调用者|管理员|访客|未登录|买家|卖家|开发者|客户端|服务端|第三方|user|admin|caller|client') || with_subject=0
  local threshold=$(( (total * 60 + 99) / 100 ))  # ceil(total * 0.6)
  if [[ "$with_subject" -lt "$threshold" ]]; then
    echo "故障想象力中仅 ${with_subject}/${total} 条有明确主语 (要求 ≥60%)"
  fi
}

sg_spec_fi_no_duplicates() {
  # 提取每条故障的核心片段（去掉编号和主语后前 15 字），unique 数太少 → 套话
  local file="$1"
  local section
  section=$(sed -nE '/故障想象力|故障.*标题|[Ff]ailure.*[Ii]magination/,/^##[^#]/p' "$file" 2>/dev/null)
  if [[ -z "$section" ]]; then
    return
  fi
  local total
  total=$(echo "$section" | grep -cE '^\s*[0-9]+[\.\、)）]') || total=0
  if [[ "$total" -lt 3 ]]; then
    return  # 太少无法判断重复
  fi
  # 提取每条，去编号和末尾差异字符，取前 8 个中文字（约 24 字节）作为指纹
  local unique_count
  unique_count=$(echo "$section" | grep -E '^\s*[0-9]+[\.\、)）]' \
    | sed -E 's/^\s*[0-9]+[\.\、)）]\s*//' \
    | sed -E 's/.{0,4}$//' \
    | sort -u | wc -l | tr -d ' ')
  local min_unique=$(( (total + 1) / 2 ))  # ceil(total / 2)
  if [[ "$unique_count" -lt "$min_unique" ]]; then
    echo "故障想象力 ${total} 条中仅 ${unique_count} 条有独立描述 (疑似套话)"
  fi
}

sg_spec_fi_cross_check() {
  # 故障想象力的对账：spec 中是否有"防 故障#N"标注
  local file="$1"
  local section
  section=$(sed -nE '/故障想象力|故障.*标题|[Ff]ailure.*[Ii]magination/,/^##[^#]/p' "$file" 2>/dev/null)
  if [[ -z "$section" ]]; then
    return
  fi
  local fi_count
  fi_count=$(echo "$section" | grep -cE '^\s*[0-9]+[\.\、)）]') || fi_count=0
  if [[ "$fi_count" -eq 0 ]]; then
    return
  fi
  local cross_ref_count
  cross_ref_count=$(grep -coE '防\s*故障#?[0-9]' "$file" 2>/dev/null) || cross_ref_count=0
  if [[ "$cross_ref_count" -eq 0 ]]; then
    echo "故障想象力有 ${fi_count} 条但 spec 中无「防 故障#N」对账标注"
    return
  fi
  # 验证引用的编号在故障章节中真实存在（防止引用不存在的编号）
  local fi_numbers
  fi_numbers=$(echo "$section" | grep -oE '^\s*([0-9]+)[\.\、)）]' | grep -oE '[0-9]+')
  if [[ -z "$fi_numbers" ]]; then
    return
  fi
  local ref_numbers
  ref_numbers=$(grep -oE '防\s*故障#?([0-9]+)' "$file" 2>/dev/null | grep -oE '[0-9]+' | sort -u)
  local phantom=""
  local phantom_count=0
  while IFS= read -r ref_num; do
    [[ -z "$ref_num" ]] && continue
    if ! echo "$fi_numbers" | grep -qx "$ref_num" 2>/dev/null; then
      phantom="${phantom} #${ref_num}"
      phantom_count=$((phantom_count + 1))
    fi
  done <<< "$ref_numbers"
  if [[ "$phantom_count" -gt 0 ]]; then
    echo "对账标注引用了不存在的故障编号:${phantom} (故障章节中无这些编号)"
  fi
}

# -- status.md 质量检查 --

sg_status_has_phase() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    return  # 文件不存在由其他检查负责
  fi
  local phase
  phase=$(grep -oE 'PROJECT_PHASE:\s*(building|stabilizing|live)' "$file" 2>/dev/null | head -1)
  if [[ -z "$phase" ]]; then
    echo "status.md 缺少 PROJECT_PHASE 或值不合法 (应为 building/stabilizing/live)"
  fi
}

sg_status_has_abandoned() {
  # stabilizing/live 阶段必须有"放弃的方案"章节
  local file="$1" phase="$2"
  if [[ ! -f "$file" ]]; then
    return
  fi
  case "$phase" in
    stabilizing|live)
      if ! grep -qE '^##.*放弃的方案|^##.*[Aa]bandoned' "$file" 2>/dev/null; then
        echo "status.md 缺少「放弃的方案」章节 (${phase} 阶段必填)"
      fi
      ;;
  esac
}

sg_status_freshness() {
  # status.md 的最后修改 commit 不应落后 HEAD 太多
  local file="$1" root="$2" max_commits="${3:-3}"
  if [[ ! -f "$file" ]]; then
    return
  fi
  if ! git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    return
  fi
  local behind
  behind=$(git -C "$root" log --oneline -- . ':!docs/status.md' 2>/dev/null \
    | head -"$((max_commits + 1))" | wc -l | tr -d ' ')
  # 如果 HEAD 之后有超过 max_commits 个不含 status.md 变更的 commit → 警告
  local status_in_recent
  status_in_recent=$(git -C "$root" log -"$max_commits" --name-only --pretty=format: 2>/dev/null \
    | grep -c 'docs/status.md') || status_in_recent=0
  if [[ "$behind" -gt "$max_commits" && "$status_in_recent" -eq 0 ]]; then
    echo "最近 ${max_commits} 个 commit 都未更新 status.md"
  fi
}

# -- impl 检查项 --

sg_impl_has_done_tasks() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "docs/status.md 不存在"
    return
  fi
  local done_count
  done_count=$(grep -cE '^\s*-\s*\[x\]' "$file" 2>/dev/null) || done_count=0
  if [[ "$done_count" -eq 0 ]]; then
    echo "status.md 中没有已完成的任务 (- [x])"
  fi
}

sg_impl_recent_commit() {
  local root="$1" max_sec="${2:-600}"
  if ! git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    return  # 非 git 仓库，跳过
  fi
  local last_epoch now_epoch diff_sec
  last_epoch=$(git -C "$root" log -1 --format="%ct" 2>/dev/null) || last_epoch=0
  now_epoch=$(date +%s)
  diff_sec=$((now_epoch - last_epoch))
  if [[ "$diff_sec" -gt "$max_sec" ]]; then
    echo "最近的 commit 在 $((diff_sec / 60)) 分钟前 (预期 /impl 刚 commit)"
  fi
}

# 反 LARP: 并发 impl 批次真实性校验
# 仅在 impl-batch.json 存在时生效 (单任务路径不触发)
sg_impl_agent_invocations() {
  local root="$1"
  local batch="$root/.claude/state/impl-batch.json"
  [[ ! -f "$batch" ]] && return  # 未声明并发批次 → 跳过
  if ! jq -e . "$batch" >/dev/null 2>&1; then
    echo "impl-batch.json 不是合法 JSON"
    return
  fi
  local tasks_n inv_n
  tasks_n=$(jq -r '.tasks | length' "$batch" 2>/dev/null) || tasks_n=0
  inv_n=$(jq -r '.agent_invocations | length' "$batch" 2>/dev/null) || inv_n=0
  if (( tasks_n < 2 )); then
    echo "impl-batch.json tasks 数 ${tasks_n} < 2 (单任务不应写并发批次文件)"
    return
  fi
  if (( inv_n != tasks_n )); then
    echo "impl-batch.json agent_invocations 数(${inv_n}) != tasks 数(${tasks_n}) → 自扮演嫌疑"
    return
  fi
  local missing
  missing=$(jq -r '[.agent_invocations[] | select((.tool_use_id // "") == "" or (.task_id // "") == "" or (.launched_at // "") == "")] | length' "$batch" 2>/dev/null) || missing=0
  if (( missing > 0 )); then
    echo "impl-batch.json agent_invocations 有 ${missing}/${inv_n} 条缺 tool_use_id/task_id/launched_at"
    return
  fi
  local max_ts min_ts max_e min_e span
  max_ts=$(jq -r '[.agent_invocations[].launched_at] | max' "$batch" 2>/dev/null)
  min_ts=$(jq -r '[.agent_invocations[].launched_at] | min' "$batch" 2>/dev/null)
  max_e=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$max_ts" +%s 2>/dev/null || date -d "$max_ts" +%s 2>/dev/null || echo 0)
  min_e=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$min_ts" +%s 2>/dev/null || date -d "$min_ts" +%s 2>/dev/null || echo 0)
  span=$((max_e - min_e))
  if (( span > 60 )); then
    echo "impl-batch.json agent_invocations 跨度 ${span}s > 60s (串行调用而非并发)"
  fi
}

# 并行 subagent 宽限期判定: 合法并行模式下 subagent 未 commit 不应拦 audit
# 触发条件:
#   1. impl-batch.json 存在 + no_commit_in_subagent=true
#   2. tasks >= 2 (单任务不认宽限, 避免伪造)
#   3. agent_invocations 数 == tasks 数 (反自扮演)
#   4. epoch 到 now 不超过 1800s (30min, 单批 subagent 最长跨度)
# 输出 "1" 表示宽限期内, 空串表示不在宽限期 (正常拦)
sg_impl_batch_grace_active() {
  local root="$1"
  local batch="$root/.claude/state/impl-batch.json"
  [[ ! -f "$batch" ]] && return
  jq -e . "$batch" >/dev/null 2>&1 || return
  local no_commit
  no_commit=$(jq -r '.no_commit_in_subagent // false' "$batch" 2>/dev/null)
  [[ "$no_commit" != "true" ]] && return
  local tasks_n inv_n
  tasks_n=$(jq -r '.tasks | length' "$batch" 2>/dev/null) || tasks_n=0
  inv_n=$(jq -r '.agent_invocations | length' "$batch" 2>/dev/null) || inv_n=0
  (( tasks_n < 2 )) && return
  (( inv_n != tasks_n )) && return
  local epoch now age
  epoch=$(jq -r '.epoch // 0' "$batch" 2>/dev/null) || epoch=0
  (( epoch == 0 )) && return
  now=$(date +%s)
  age=$((now - epoch))
  (( age < 0 )) && return      # 时钟漂移保护
  (( age >= 1800 )) && return  # 30min 宽限上限, 超时恢复严格拦
  echo "1"
}

# -- upstream 新鲜度检测 (L2) --
# 消费项目 skill-gate 入口调用. 对比本地 project-gate.sh / ai-rules.sh 与 upstream 副本 sha256.
# 不一致 -> stderr warn + 给出 cp 修复命令 (不阻塞).
# upstream 探测优先级: env AI_RULES_UPSTREAM / AI_RUNNER_UPSTREAM > ~/ai-rules > ~/ai-runner/skills-kit.
# 未找到 upstream / 同仓自测 / sha256 一致 -> 静默. 5min 内不重复 warn.
sg_upstream_staleness_warn() {
  local root="$1"
  local local_gate=""
  if [[ -f "$root/scripts/project-gate.sh" ]]; then
    local_gate="$root/scripts/project-gate.sh"
  elif [[ -f "$root/scripts/ai-rules.sh" ]]; then
    local_gate="$root/scripts/ai-rules.sh"
  fi
  [[ -z "$local_gate" ]] && return

  local upstream=""
  # env override
  if [[ -n "${AI_RUNNER_UPSTREAM:-}" && -f "${AI_RUNNER_UPSTREAM}/scripts/project-gate.sh" ]]; then
    upstream="${AI_RUNNER_UPSTREAM}/scripts/project-gate.sh"
  elif [[ -n "${AI_RULES_UPSTREAM:-}" && -f "${AI_RULES_UPSTREAM}/scripts/ai-rules.sh" ]]; then
    upstream="${AI_RULES_UPSTREAM}/scripts/ai-rules.sh"
  # 约定路径
  elif [[ "$(basename "$local_gate")" = "project-gate.sh" && -f "$HOME/ai-runner/skills-kit/scripts/project-gate.sh" ]]; then
    upstream="$HOME/ai-runner/skills-kit/scripts/project-gate.sh"
  # ai-rules.sh 的真源=app-factory(AI_RULES_ROOT 或默认克隆位);老 ~/ai-rules(2026-05 遗留)
  # 只当最后兜底——guadagua 实锤:scaffold 自 app-factory 的项目被拿去跟老仓比 sha 必误报。
  elif [[ "$(basename "$local_gate")" = "ai-rules.sh" && -n "${AI_RULES_ROOT:-}" && -f "${AI_RULES_ROOT}/scripts/ai-rules.sh" ]]; then
    upstream="${AI_RULES_ROOT}/scripts/ai-rules.sh"
  elif [[ "$(basename "$local_gate")" = "ai-rules.sh" && -f "$HOME/opc/app-factory/scripts/ai-rules.sh" ]]; then
    upstream="$HOME/opc/app-factory/scripts/ai-rules.sh"
  elif [[ "$(basename "$local_gate")" = "ai-rules.sh" && -f "$HOME/ai-rules/scripts/ai-rules.sh" ]]; then
    upstream="$HOME/ai-rules/scripts/ai-rules.sh"
  fi

  [[ -z "$upstream" ]] && return
  # 同仓自测跳过 (main repo 自身运行)
  [[ "$(cd "$(dirname "$upstream")" && pwd)" = "$(cd "$(dirname "$local_gate")" && pwd)" ]] && return

  local local_sha up_sha
  local_sha=$(shasum -a 256 "$local_gate" 2>/dev/null | awk '{print $1}')
  up_sha=$(shasum -a 256 "$upstream" 2>/dev/null | awk '{print $1}')
  [[ -z "$local_sha" || -z "$up_sha" ]] && return
  [[ "$local_sha" = "$up_sha" ]] && return

  # 5min 防骚扰
  local stamp="$root/.claude/state/.upstream-warn"
  mkdir -p "$(dirname "$stamp")" 2>/dev/null
  local now last
  now=$(date +%s)
  if [[ -f "$stamp" ]]; then
    last=$(cat "$stamp" 2>/dev/null || echo 0)
    (( now - last < 300 )) && return
  fi
  echo "$now" > "$stamp"

  local local_short="${local_sha:0:12}"
  local up_short="${up_sha:0:12}"
  echo "⚠️ [upstream-stale] 本地 $(basename "$local_gate") 与 upstream 不一致." >&2
  echo "   local:    $local_gate  sha=$local_short" >&2
  echo "   upstream: $upstream  sha=$up_short" >&2
  echo "   修复:     cp '$upstream' '$local_gate' && bash '$local_gate' self-test" >&2
  echo "   (静默 5min. 设 AI_RULES_UPSTREAM / AI_RUNNER_UPSTREAM 可改 upstream 路径)" >&2
}

# -- 前置人工动作清单检查（GATE 0 主动前置人工介入）--

# 检查 spec.md 顶部是否有"前置人工动作清单"章节
sg_spec_preflight_section() {
  local file="$1"
  [[ ! -f "$file" ]] && { echo "spec.md 不存在"; return; }
  if ! grep -qE '^##[[:space:]]+前置人工动作清单' "$file"; then
    echo "spec.md 缺「前置人工动作清单」章节 (AI 需在 GATE 0 主动扫描本机/凭证/服务/审批类用户必做事项)"
    return
  fi
  # 检查是否显式声明"无"或至少有 1 条编号条目 (A1/B1/C1/D1)
  local section
  section=$(sed -nE '/^##[[:space:]]+前置人工动作清单/,/^##[^#]/p' "$file" 2>/dev/null)
  if echo "$section" | grep -qE '无前置人工动作|^\s*-\s*\[\s*\]\s*无\s*$'; then
    return  # 显式声明无
  fi
  local entry_count
  entry_count=$(echo "$section" | grep -cE '^\s*-\s*\[\s*\]\s+[A-D][0-9]+[:：]' 2>/dev/null) || entry_count=0
  if (( entry_count == 0 )); then
    echo "「前置人工动作清单」章节为空 (应含 A1/B1/C1... 编号条目, 或显式声明「无前置人工动作」)"
  fi
}

# 检查每个 TASK 的 HUMAN 字段中 action:XX 引用在前置清单中存在
sg_spec_preflight_mapped() {
  local file="$1"
  [[ ! -f "$file" ]] && return
  # 提取所有 HUMAN 字段中的 action:XX 引用
  local refs
  refs=$(grep -oE 'action:[A-D][0-9]+' "$file" 2>/dev/null | sort -u)
  [[ -z "$refs" ]] && return  # 没有 action 引用 → 不校验
  # 提取前置清单中的编号
  local section
  section=$(sed -nE '/^##[[:space:]]+前置人工动作清单/,/^##[^#]/p' "$file" 2>/dev/null)
  local defined
  defined=$(echo "$section" | grep -oE '[A-D][0-9]+[:：]' | sed -E 's/[:：]//' | sort -u)
  local missing=""
  while IFS= read -r ref; do
    local id="${ref#action:}"
    if ! echo "$defined" | grep -qxF "$id"; then
      missing="${missing}${id} "
    fi
  done <<< "$refs"
  if [[ -n "$missing" ]]; then
    echo "TASK HUMAN 字段引用了前置清单未定义的条目: ${missing}(请补全 spec 顶部「前置人工动作清单」)"
  fi
}

# 反向扫描：TASK 内容含"人动作关键词"但 HUMAN:无 → BLOCK
# 白名单严格限定"人一次性动作"，不覆盖可被 AI 自动化的 install/setup
sg_spec_task_human_complete() {
  local file="$1"
  [[ ! -f "$file" ]] && return
  # 逐个 TASK 代码块扫描
  local offenders=""
  local in_block=0
  local block_buf=""
  local task_id=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^\`\`\` ]]; then
      if [[ $in_block -eq 0 ]]; then
        in_block=1
        block_buf=""
      else
        in_block=0
        # 块结束，检查是否为 TASK 块
        if echo "$block_buf" | grep -qE '^TASK:'; then
          local human_line
          human_line=$(echo "$block_buf" | grep -E '^HUMAN:' | head -1)
          # 未匹配 HUMAN: 行时跳过
          if [[ -n "$human_line" ]]; then
            # 提取任务标识（从 TASK 行开头）
            task_id=$(echo "$block_buf" | grep -E '^TASK:' | head -1 | sed -E 's/^TASK:[[:space:]]*//' | cut -c1-40)
            # 白名单触发词（严格，人一次性动作）
            local hit
            hit=$(echo "$block_buf" | grep -oE 'huggingface-cli login|gh auth login|gcloud auth login|apply.*[Kk]ey|申请.*[Kk]ey|申请.*[Tt]oken|注册.*账号|开通.*服务|accept.*terms|接受.*条款|同意.*协议|brew install|apt-get install|apt install|xcode-select --install|Apple Developer|Google Play Console|export [A-Z_]+_(TOKEN|KEY|SECRET)=' | head -1)
            if [[ -n "$hit" ]]; then
              # HUMAN:无 且无逃生舱（AI 自动化:...）→ 违规
              if echo "$human_line" | grep -qE '^HUMAN:[[:space:]]*无[[:space:]]*$'; then
                offenders="${offenders}[${task_id}] 命中\"${hit}\" 但 HUMAN:无；\n"
              elif echo "$human_line" | grep -qE '^HUMAN:[[:space:]]*无[[:space:]]*\(AI 自动化[:：]'; then
                : # 逃生舱放行
              elif ! echo "$human_line" | grep -qE 'action:[A-D][0-9]+'; then
                offenders="${offenders}[${task_id}] 命中\"${hit}\" 但 HUMAN 无 action:XX 引用；\n"
              fi
            fi
          fi
        fi
        block_buf=""
      fi
      continue
    fi
    if [[ $in_block -eq 1 ]]; then
      block_buf="${block_buf}${line}"$'\n'
    fi
  done < "$file"
  if [[ -n "$offenders" ]]; then
    printf "TASK 含人动作触发词但 HUMAN 未声明 action:XX (逃生舱: HUMAN:无(AI 自动化:<理由>)):\n%b" "$offenders"
  fi
}

# -- diff-based 覆盖缺口检测 --

sg_spec_coverage_gaps() {
  # 检查故障想象力中的条目是否全部被 ACCEPT 标注覆盖（"防 故障#N"）
  # 返回未覆盖的故障编号列表，空串=全覆盖
  local file="$1"
  local section
  section=$(sed -nE '/故障想象力|故障.*标题|[Ff]ailure.*[Ii]magination/,/^##[^#]/p' "$file" 2>/dev/null)
  if [[ -z "$section" ]]; then
    return
  fi
  # 收集所有故障编号
  local fi_numbers
  fi_numbers=$(echo "$section" | grep -oE '^\s*([0-9]+)[\.\、)）]' | grep -oE '[0-9]+')
  if [[ -z "$fi_numbers" ]]; then
    return
  fi
  # 收集所有被引用的故障编号（"防 故障#N"）
  local ref_numbers
  ref_numbers=$(grep -oE '防\s*故障#?([0-9]+)' "$file" 2>/dev/null | grep -oE '[0-9]+')
  # 找出未被覆盖的编号
  local gaps=""
  local gap_count=0
  while IFS= read -r num; do
    if ! echo "$ref_numbers" | grep -qx "$num" 2>/dev/null; then
      gaps="${gaps} #${num}"
      gap_count=$((gap_count + 1))
    fi
  done <<< "$fi_numbers"
  if [[ "$gap_count" -gt 0 ]]; then
    echo "故障想象力中${gaps} 未被任何 ACCEPT 标注覆盖 (缺「防 故障#N」)"
  fi
}

# -- 外部文档覆盖检查 --

sg_spec_external_coverage() {
  local file="$1"
  [[ ! -f "$file" ]] && return

  # 条件触发：有 SOURCE 标记时才检查
  local has_source
  has_source=$(grep -cE '^SOURCE:' "$file" 2>/dev/null) || has_source=0
  [[ "$has_source" -eq 0 ]] && return  # 无外部文档，跳过

  # 1. "外部文档覆盖"章节必须存在
  if ! grep -qiE '^##.*外部文档覆盖|^##.*[Ee]xternal.*[Cc]overage' "$file" 2>/dev/null; then
    echo "有 SOURCE 引用 (${has_source} 处) 但缺少「外部文档覆盖」章节"
    return
  fi

  # 2. 所有 S-NNN 条目必须有状态标注
  local total annotated gap
  total=$(grep -cE '^\|\s*S-[0-9]+' "$file" 2>/dev/null) || total=0
  [[ "$total" -eq 0 ]] && return  # 章节存在但无条目，可能还在填写

  annotated=$(grep -cE '^\|\s*S-[0-9]+.*(covered|deferred|out.of.scope)' "$file" 2>/dev/null) || annotated=0
  gap=$((total - annotated))
  if [[ "$gap" -gt 0 ]]; then
    echo "外部文档覆盖表中 ${gap}/${total} 条未标注状态 (需 covered/deferred/out_of_scope)"
  fi
}

# -- spec 增量与契约回溯检查（源自 RecordToMes v0.5 Round 4 归因）--
#
# 红队自检 (每函数实现完必须过):
#   1. 空 spec / 无 TASK 能绕吗? → 正确: 静默 return, 不触发
#   2. 关键词以 code fence 出现能绕吗? → 现在仍会抓 (宽精度换召回), 人审复核
#   3. SOURCE 行值为 "TBD" / 空 能绕吗? → TBD 必须带 "-after-T<编号>" 后缀, 裸 TBD 视为缺
#   4. bug 关键词被动语态伪装能绕吗? → 白名单词多维度, 语义漏网转人审 (诚实边界)

sg_spec_frozen_delta() {
  # 挡 P0-10 类: 新章节 API 路径单复数不一致, 违反 §API 契约 FROZEN
  local file="$1"
  [[ ! -f "$file" ]] && return
  local paths
  paths=$(grep -oE '/api/[a-z_]+' "$file" 2>/dev/null | sort -u)
  [[ -z "$paths" ]] && return
  local conflicts=""
  local count=0
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    [[ "$p" = *s ]] && continue
    local plural="${p}s"
    if echo "$paths" | grep -qFx "$plural"; then
      conflicts="${conflicts} ${p}↔${plural}"
      count=$((count + 1))
    fi
  done <<< "$paths"
  if (( count > 0 )); then
    echo "spec.md API 路径单复数不一致 (${count} 对):${conflicts} — §API 契约 FROZEN 要求严格一致, 新章节别改命名空间"
  fi
}

sg_spec_bug_phase() {
  # 挡 P0-13/14 类: 章节含 bug 关键词但未声明"已过 Bug 定性前置"
  local file="$1"
  [[ ! -f "$file" ]] && return
  local bug_keywords='始终写\s*0\.|始终写\s*0"|worker.*bug|逻辑层.*bug|漏写|漏项|未实现|实际未|错误地.*实现|误实现|未明说|hardcoded.*始终'
  local phase_keywords='Bug 定性|已过.*定性|性质[::]\s*bug|层级[=:]\s*(展示|逻辑|数据)|非新功能|反 LARP.*bug'
  if ! grep -qiE "$bug_keywords" "$file" 2>/dev/null; then
    return
  fi
  if grep -qiE "$phase_keywords" "$file" 2>/dev/null; then
    return
  fi
  local first_line
  first_line=$(grep -niE "$bug_keywords" "$file" 2>/dev/null | head -1)
  echo "spec.md 出现 bug/漏项关键词 (首例 L${first_line%%:*}) 但未声明'已过 Bug 定性前置: 层级=展示/逻辑/数据' — 先定性再写章节, 防 bug 被包装成新功能"
}

sg_task_accept_source() {
  # 挡 P0-3/4/5/7 类: ACCEPT 数值无来源溯源
  local file="$1"
  [[ ! -f "$file" ]] && return
  local task_count
  task_count=$(grep -cE '^TASK:' "$file" 2>/dev/null) || task_count=0
  [[ "$task_count" -eq 0 ]] && return
  local missing
  missing=$(awk '
    BEGIN { in_task=0; tname=""; tline=0; has_src=0 }
    /^TASK:/ {
      if (in_task && !has_src) { printf "L%d %s\n", tline, tname }
      in_task=1; tname=$0; tline=NR; has_src=0
    }
    in_task && /^SOURCE:[[:space:]]*[^[:space:]]/ {
      line=$0
      sub(/^SOURCE:[[:space:]]*/, "", line)
      if (line ~ /^TBD[[:space:]]*$/) next
      if (line == "") next
      has_src=1
    }
    END {
      if (in_task && !has_src) { printf "L%d %s\n", tline, tname }
    }
  ' "$file")
  if [[ -n "$missing" ]]; then
    local miss_count
    miss_count=$(echo "$missing" | wc -l | tr -d ' ')
    echo "spec.md ${miss_count}/${task_count} 个 TASK 块缺 SOURCE 行或值为裸 TBD (ACCEPT 数值必须引: §章节 / fixture:路径 / FROZEN / TBD-after-T<编号>):"
    echo "$missing" | head -3 | sed 's/^/  /'
  fi
}

# -- Step 3 多视角审查产物检查（anti-LARP）--

sg_step3_triggered() {
  # 返回 "1" 表示本项目要求 Step 3 产物（复杂项目或已声明审查章节）
  local spec_file="$1"
  [[ ! -f "$spec_file" ]] && return
  # 信号 1：spec 里已有"多视角审查"章节 → 必须有产物
  if grep -qE '^##.*多视角审查|^##.*[Mm]ulti.*[Rr]eview' "$spec_file" 2>/dev/null; then
    echo 1; return
  fi
  # 信号 2：复杂项目（TASK ≥ 10 或 FILES 引用 ≥ 15）
  local task_count files_count
  task_count=$(grep -cE '^TASK:' "$spec_file" 2>/dev/null) || task_count=0
  files_count=$(grep -cE '^FILES:' "$spec_file" 2>/dev/null) || files_count=0
  if (( task_count >= 10 || files_count >= 15 )); then
    echo 1; return
  fi
}

sg_step3_file_exists() {
  local root="$1"
  local dir="$root/.claude/state/step3"
  if [[ ! -d "$dir" ]]; then
    echo "Step 3 产物目录缺失：.claude/state/step3/ (审查章节声明了但无产物 → 可能 LARP)"
    return
  fi
  local latest
  latest=$(ls -t "$dir"/round-*.json 2>/dev/null | head -1)
  if [[ -z "$latest" ]]; then
    echo "Step 3 产物缺失：.claude/state/step3/round-*.json 一个都没有"
  fi
}

sg_step3_latest_json() {
  # 辅助：echo 最新 round JSON 路径
  local root="$1"
  ls -t "$root"/.claude/state/step3/round-*.json 2>/dev/null | head -1
}

sg_step3_json_valid() {
  local root="$1"
  local latest
  latest=$(sg_step3_latest_json "$root")
  [[ -z "$latest" ]] && return  # 前置检查会挡住
  if ! jq empty "$latest" 2>/dev/null; then
    echo "Step 3 产物 JSON 解析失败：$(basename "$latest")"
    return
  fi
  # 必须字段
  local missing=""
  for field in round roles dissents no_dissent; do
    if ! jq -e "has(\"$field\")" "$latest" >/dev/null 2>&1; then
      missing="${missing} ${field}"
    fi
  done
  if [[ -n "$missing" ]]; then
    echo "Step 3 产物缺字段：$(basename "$latest") 缺${missing}"
  fi
}

sg_step3_roles_complete() {
  local root="$1"
  local latest
  latest=$(sg_step3_latest_json "$root")
  [[ -z "$latest" ]] && return
  local roles_count
  roles_count=$(jq -r '.roles | length' "$latest" 2>/dev/null) || roles_count=0
  if (( roles_count < 3 )); then
    echo "Step 3 角色数 ${roles_count} < 3（三必选：需求/证据/范围）"
    return
  fi
  # 三必选角色
  local missing=""
  for role in "需求" "证据" "范围"; do
    if ! jq -e ".roles[] | select(contains(\"$role\"))" "$latest" >/dev/null 2>&1; then
      missing="${missing} ${role}"
    fi
  done
  if [[ -n "$missing" ]]; then
    echo "Step 3 缺三必选角色：${missing}"
  fi
}

sg_step3_three_elements() {
  # 每条 DISSENT 必须有 evidence + suggestion + impact（挡没证据的泛泛评论）
  local root="$1"
  local latest
  latest=$(sg_step3_latest_json "$root")
  [[ -z "$latest" ]] && return
  local total incomplete
  total=$(jq -r '.dissents | length' "$latest" 2>/dev/null) || total=0
  [[ "$total" -eq 0 ]] && return
  incomplete=$(jq -r '[.dissents[] | select((.evidence // "") == "" or (.suggestion // "") == "" or (.impact // "") == "")] | length' "$latest" 2>/dev/null) || incomplete=0
  if (( incomplete > 0 )); then
    echo "Step 3 有 ${incomplete}/${total} 条 DISSENT 缺 evidence/suggestion/impact 三要素"
  fi
}

sg_step3_verification_nonempty() {
  # NO_DISSENT 角色必须有非空 verification（挡空头"无异议"）
  local root="$1"
  local latest
  latest=$(sg_step3_latest_json "$root")
  [[ -z "$latest" ]] && return
  local total empty
  total=$(jq -r '.no_dissent | length' "$latest" 2>/dev/null) || total=0
  [[ "$total" -eq 0 ]] && return
  empty=$(jq -r '[.no_dissent[] | select((.verification // "") == "")] | length' "$latest" 2>/dev/null) || empty=0
  if (( empty > 0 )); then
    echo "Step 3 有 ${empty}/${total} 条 NO_DISSENT 缺 verification（空头无异议 = LARP 嫌疑）"
  fi
}

sg_step3_agent_invocations() {
  # 反 LARP 核心检查：Step 3 必须用 Agent tool 并发拉 subagent，不可自扮演
  # JSON 必须有 agent_invocations 字段，每条记录真实 tool_use_id + 并发时间窗
  local root="$1"
  local latest
  latest=$(sg_step3_latest_json "$root")
  [[ -z "$latest" ]] && return
  # 字段存在性
  if ! jq -e 'has("agent_invocations")' "$latest" >/dev/null 2>&1; then
    echo "Step 3 缺 agent_invocations 字段 (未证明真用 Agent tool 拉 subagent → 自扮演 LARP 嫌疑)"
    return
  fi
  local roles_n inv_n
  roles_n=$(jq -r '.roles | length' "$latest" 2>/dev/null) || roles_n=0
  inv_n=$(jq -r '.agent_invocations | length' "$latest" 2>/dev/null) || inv_n=0
  if (( inv_n != roles_n )); then
    echo "Step 3 agent_invocations 数(${inv_n}) != roles 数(${roles_n}) → 角色与实际拉起的 subagent 不匹配"
    return
  fi
  # 每条必须有 tool_use_id + subagent_type + launched_at
  local missing
  missing=$(jq -r '[.agent_invocations[] | select((.tool_use_id // "") == "" or (.subagent_type // "") == "" or (.launched_at // "") == "")] | length' "$latest" 2>/dev/null) || missing=0
  if (( missing > 0 )); then
    echo "Step 3 agent_invocations 有 ${missing}/${inv_n} 条缺 tool_use_id/subagent_type/launched_at (无法证明真实调用)"
    return
  fi
  # 并发信号：launched_at 时间跨度 < 60s（同一消息内并发触发的典型窗口）
  # 转 epoch 再算 max-min；兼容 ISO8601
  local max_ts min_ts span
  max_ts=$(jq -r '[.agent_invocations[].launched_at] | max' "$latest" 2>/dev/null)
  min_ts=$(jq -r '[.agent_invocations[].launched_at] | min' "$latest" 2>/dev/null)
  local max_e min_e
  max_e=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$max_ts" +%s 2>/dev/null || date -d "$max_ts" +%s 2>/dev/null || echo 0)
  min_e=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$min_ts" +%s 2>/dev/null || date -d "$min_ts" +%s 2>/dev/null || echo 0)
  span=$((max_e - min_e))
  if (( span > 60 )); then
    echo "Step 3 agent_invocations 时间跨度 ${span}s > 60s (串行调用而非并发 → 违反 Step 3 并发规则)"
  fi
}

sg_step3_prior_round_refs() {
  # 解 C 类：Round N+1 必须引 Round N 的 P0 编号（挡补丁引入的新表面积问题）
  local root="$1"
  local dir="$root/.claude/state/step3"
  [[ ! -d "$dir" ]] && return
  local rounds
  rounds=$(ls "$dir"/round-*.json 2>/dev/null | wc -l | tr -d ' ')
  # 只有一轮时无需差分
  (( rounds < 2 )) && return
  local latest
  latest=$(sg_step3_latest_json "$root")
  # 检查 references_prior_round 字段
  local refs_count
  refs_count=$(jq -r '.references_prior_round | length' "$latest" 2>/dev/null) || refs_count=0
  if (( refs_count == 0 )); then
    echo "Step 3 Round >= 2 但缺 references_prior_round 字段（差分审查未执行 → 无法挡补丁引入的新问题）"
    return
  fi
  # 差分断言：必须有 prior_p0_verified 字段列出前轮 P0 被再核验
  if ! jq -e 'has("prior_p0_verified")' "$latest" >/dev/null 2>&1; then
    echo "Step 3 Round >= 2 缺 prior_p0_verified 字段（未对前轮 P0 逐条再核验）"
  fi
}

sg_step3_prior_p0_strict() {
  # 挡"多轮审查无 carry-over"根因 (RecordToMes Round 4 prior_p0_verified=[] 实测)
  # Round >=2 必须逐条核验前轮 P0: 非空 + {prior_id, verified_how, new_issues_found}
  # prior_id 必须真实存在于前轮 P0 列表
  local root="$1"
  local dir="$root/.claude/state/step3"
  [[ ! -d "$dir" ]] && return
  local rounds
  rounds=$(ls "$dir"/round-*.json 2>/dev/null | wc -l | tr -d ' ')
  (( rounds < 2 )) && return
  local latest prev
  latest=$(ls -t "$dir"/round-*.json 2>/dev/null | head -1)
  prev=$(ls -t "$dir"/round-*.json 2>/dev/null | sed -n '2p')
  [[ -z "$latest" || -z "$prev" ]] && return
  # 前轮若无 P0, 本规则不约束本轮 carry-over (无可核验对象)
  local prev_p0_count
  prev_p0_count=$(jq -r '[.dissents[] | select(.severity=="P0")] | length' "$prev" 2>/dev/null) || prev_p0_count=0
  (( prev_p0_count == 0 )) && return
  # 本轮必须有非空 prior_p0_verified
  local verified_count
  verified_count=$(jq -r '(.prior_p0_verified // []) | length' "$latest" 2>/dev/null) || verified_count=0
  if (( verified_count == 0 )); then
    echo "Step 3 Round >= 2: 前轮 ${prev_p0_count} 条 P0 但本轮 prior_p0_verified 为空/缺失 (carry-over 未执行, Round N 通过 ≠ 问题修了)"
    return
  fi
  # 每条必须含 prior_id + verified_how + new_issues_found
  local bad
  bad=$(jq -r '
    (.prior_p0_verified // []) | to_entries[]
    | select(
        (.value.prior_id // "" | tostring | . == "") or
        (.value.verified_how // "" | tostring | . == "") or
        (.value | has("new_issues_found") | not)
      )
    | "#\(.key): prior_id=\(.value.prior_id // "MISSING") verified_how=\(.value.verified_how // "MISSING")"
  ' "$latest" 2>/dev/null)
  if [[ -n "$bad" ]]; then
    local bad_count
    bad_count=$(echo "$bad" | grep -c . 2>/dev/null) || bad_count=0
    echo "Step 3 prior_p0_verified 有 ${bad_count} 条缺 {prior_id, verified_how, new_issues_found} 三件套 (首例: $(echo "$bad" | head -1))"
    return
  fi
  # prior_id 必须真实存在于前轮 P0
  local prev_ids
  prev_ids=$(jq -r '[.dissents[] | select(.severity=="P0") | .id] | join("|")' "$prev" 2>/dev/null)
  [[ -z "$prev_ids" ]] && return
  local cited_ids ghost=""
  cited_ids=$(jq -r '(.prior_p0_verified // []) | .[] | .prior_id // empty' "$latest" 2>/dev/null)
  while IFS= read -r cid; do
    [[ -z "$cid" ]] && continue
    # 用单词边界匹配, 防 P0-1 匹到 P0-10
    if ! echo "|$prev_ids|" | grep -qE "\|${cid}\|"; then
      ghost="${ghost} ${cid}"
    fi
  done <<< "$cited_ids"
  if [[ -n "$ghost" ]]; then
    echo "Step 3 prior_p0_verified 引用前轮不存在的 P0 编号:${ghost} (造假 prior_id)"
  fi
}

sg_step3_roles_for_context() {
  # 解 B 类：spec 扫关键词，命中时要求额外角色（技术可行性/安全/覆盖面）
  local spec_file="$1" root="$2"
  [[ ! -f "$spec_file" ]] && return
  local latest
  latest=$(sg_step3_latest_json "$root")
  [[ -z "$latest" ]] && return
  local roles_blob
  roles_blob=$(jq -r '.roles | join("|")' "$latest" 2>/dev/null) || return
  local missing=""
  # 触发词 → 必选角色
  # 技术栈关键词：模型/GPU/MPS/CUDA/embedding/推理 → 技术可行性
  if grep -qiE '(GPU|MPS|CUDA|Metal|推理|embedding|transformer|LLM|pyannote|whisper)' "$spec_file"; then
    if [[ "$roles_blob" != *"技术可行性"* && "$roles_blob" != *"技术栈"* ]]; then
      missing="${missing} 技术可行性"
    fi
  fi
  # 权限/鉴权/数据 → 安全与权限
  if grep -qiE '(鉴权|权限|token|认证|OAuth|session|密钥|secret)' "$spec_file"; then
    if [[ "$roles_blob" != *"安全"* && "$roles_blob" != *"权限"* ]]; then
      missing="${missing} 安全与权限"
    fi
  fi
  # 部署/CI/staging → 运维
  if grep -qiE '(staging|CI/CD|部署|Docker|k8s|kubernetes|nginx)' "$spec_file"; then
    if [[ "$roles_blob" != *"运维"* && "$roles_blob" != *"部署"* ]]; then
      missing="${missing} 运维与部署"
    fi
  fi
  if [[ -n "$missing" ]]; then
    echo "Step 3 项目上下文要求额外角色但未上：${missing}"
  fi
}

sg_step3_absorbed_as_valid() {
  # 每条 P0 必须有 absorbed_as，且引用的位置（TASK 编号 或 # 锚点）在 spec.md 中真实存在
  local root="$1" spec_file="$2"
  local latest
  latest=$(sg_step3_latest_json "$root")
  [[ -z "$latest" ]] && return
  [[ ! -f "$spec_file" ]] && return
  local p0_total p0_missing_absorb
  p0_total=$(jq -r '[.dissents[] | select(.severity == "P0")] | length' "$latest" 2>/dev/null) || p0_total=0
  [[ "$p0_total" -eq 0 ]] && return
  p0_missing_absorb=$(jq -r '[.dissents[] | select(.severity == "P0") | select((.absorbed_as // "") == "")] | length' "$latest" 2>/dev/null) || p0_missing_absorb=0
  if (( p0_missing_absorb > 0 )); then
    echo "Step 3 有 ${p0_missing_absorb}/${p0_total} 条 P0 缺 absorbed_as（空头吸收）"
    return
  fi
  # 引用真实性：提取 absorbed_as 中的 TASK 编号（T\d+）和锚点（#\d+[.\d]*），检查 spec.md 存在
  local refs
  refs=$(jq -r '.dissents[] | select(.severity == "P0") | .absorbed_as' "$latest" 2>/dev/null)
  local broken=0 total_refs=0
  while IFS= read -r r; do
    [[ -z "$r" ]] && continue
    # 提取 T\d+ 类 TASK ID
    for task_id in $(echo "$r" | grep -oE 'T[0-9]+' | sort -u); do
      total_refs=$((total_refs + 1))
      if ! grep -qE "^TASK:.*${task_id}\b|^${task_id}\b|\b${task_id}\b" "$spec_file" 2>/dev/null; then
        broken=$((broken + 1))
      fi
    done
  done <<< "$refs"
  if (( broken > 0 )); then
    echo "Step 3 absorbed_as 有 ${broken}/${total_refs} 个 TASK 引用在 spec.md 中找不到（grep-matcher 作弊嫌疑）"
  fi
}

# -- check/verify/release 检查项 --

sg_json_field() {
  local file="$1" field="$2" label="$3"
  if [[ ! -f "$file" ]]; then
    echo "${label} 不存在"
    return
  fi
  local val
  val=$(jq -r ".${field} // empty" "$file" 2>/dev/null)
  if [[ -z "$val" ]]; then
    echo "${label} 缺少 ${field} 字段"
  fi
}

sg_release_decision_valid() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "release-report.json 不存在"
    return
  fi
  local decision
  decision=$(jq -r '.decision // empty' "$file" 2>/dev/null)
  case "$decision" in
    not-ready|ready-for-staging|release-ready|needs-human) ;;
    *) echo "release-report.json decision='${decision}' 不是合法值" ;;
  esac
}

# -- sanity 检查项（运行时可验证的静态一致性）--

# 硬编码地址检测：源码中不应出现 localhost/127.0.0.1（应走环境变量）
sg_sanity_hardcoded_addrs() {
  local root="$1"
  # 收集源码文件（排除配置/文档/框架文件/测试/node_modules/.env*）
  local src_files
  src_files=$(git -C "$root" ls-files 2>/dev/null \
    | grep -vE '^(docs/|scripts/|\.claude/|CLAUDE\.md|package|\.git|\.env|README|LICENSE|node_modules/|dist/|build/|\.next/)' \
    | grep -vE '\.(md|json|lock|yaml|yml|toml|ini|conf|cfg|env|env\..*)$' \
    | grep -vE '(test|spec|__test__|__spec__|\.test\.|\.spec\.)' \
    || true)

  if [[ -z "$src_files" ]]; then
    return
  fi

  local hits=""
  local hit_count=0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    local full="$root/$f"
    [[ ! -f "$full" ]] && continue
    # 排除注释行（简单启发式：# 或 // 开头的行）
    local matches
    matches=$(grep -nE '(localhost|127\.0\.0\.1|0\.0\.0\.0)' "$full" 2>/dev/null \
      | grep -vE '^\s*(#|//|/?\*|\*/)' \
      | grep -vE '(\.env|process\.env|os\.environ|os\.Getenv|viper\.)' \
      | head -3 || true)
    if [[ -n "$matches" ]]; then
      hits="${hits}${f}:\n${matches}\n"
      hit_count=$((hit_count + 1))
    fi
  done <<< "$src_files"

  if [[ "$hit_count" -gt 0 ]]; then
    echo "源码中检测到 ${hit_count} 个文件含硬编码地址 (localhost/127.0.0.1)，应使用环境变量"
  fi
}

# 构建产物新鲜度：build/dist 目录存在时，最新源码必须比构建产物新
sg_sanity_build_freshness() {
  local root="$1"
  # 常见构建输出目录
  local build_dir=""
  for d in dist build out .next; do
    if [[ -d "$root/$d" ]]; then
      build_dir="$root/$d"
      break
    fi
  done
  [[ -z "$build_dir" ]] && return

  # 取 build_dir 内最新文件的 mtime (不是 dir 本身 mtime — macOS 写入已有文件不推 dir mtime)
  local build_epoch
  build_epoch=$(find "$build_dir" -type f \( -exec stat -f %m {} + 2>/dev/null \) \
                | sort -rn | head -1)
  # Linux fallback (stat -f 不可用)
  if [[ -z "$build_epoch" ]]; then
    build_epoch=$(find "$build_dir" -type f -exec stat -c %Y {} + 2>/dev/null \
                  | sort -rn | head -1)
  fi
  # 空目录兜底
  build_epoch="${build_epoch:-0}"

  # 获取最近源码 commit 的时间
  local src_epoch
  src_epoch=$(git -C "$root" log -1 --format="%ct" -- \
    ':!docs/' ':!scripts/' ':!.claude/' ':!CLAUDE.md' ':!*.md' ':!package-lock.json' \
    ':!dist/' ':!build/' ':!out/' ':!.next/' \
    2>/dev/null) || src_epoch=0

  if [[ "$src_epoch" -gt 0 && "$build_epoch" -gt 0 ]]; then
    if [[ "$src_epoch" -gt "$build_epoch" ]]; then
      local diff_min=$(( (src_epoch - build_epoch) / 60 ))
      echo "构建产物过期：源码比 ${build_dir##*/}/ 新 ${diff_min} 分钟，需要重新构建"
    fi
  fi
}

# 测试证据新鲜度：检查测试报告是否存在且与最近 commit 时间匹配
sg_sanity_test_evidence() {
  local root="$1"
  # 常见测试报告位置
  local found_stale=0
  local found_any=0
  local now_epoch
  now_epoch=$(date +%s)
  local last_commit_epoch
  last_commit_epoch=$(git -C "$root" log -1 --format="%ct" 2>/dev/null) || last_commit_epoch=0

  for report in \
    "$root/.claude/state/check-report.json" \
    "$root/.claude/state/verify-report.json" \
    "$root/coverage/lcov.info" \
    "$root/test-results.xml" \
    "$root/junit.xml"; do
    if [[ -f "$report" ]]; then
      found_any=1
      local report_mtime
      report_mtime=$(stat -f %m "$report" 2>/dev/null || stat -c %Y "$report" 2>/dev/null || echo 0)
      # 测试报告比最后 commit 早超过 30 分钟 → 过期
      if [[ "$last_commit_epoch" -gt 0 && "$report_mtime" -gt 0 ]]; then
        if [[ "$((last_commit_epoch - report_mtime))" -gt 1800 ]]; then
          found_stale=1
        fi
      fi
    fi
  done

  if [[ "$found_stale" -gt 0 ]]; then
    echo "测试报告过期：最近 commit 之后未重新运行测试"
  fi
}

# 未验证维度声明：列出机械检查无法覆盖的维度（写入放行清单的 not_verified）
sg_sanity_unverified_dimensions() {
  local root="$1"
  local dims=()

  # 有前端代码 → 视觉/交互无法自动验证
  if git -C "$root" ls-files 2>/dev/null | grep -qE '\.(tsx|jsx|vue|svelte)$'; then
    dims+=("visual_accuracy:前端视觉效果需人工确认")
  fi

  # 有移动端代码
  if git -C "$root" ls-files 2>/dev/null | grep -qE '\.(swift|kt|dart)$'; then
    dims+=("device_compatibility:真机兼容性需人工测试")
  fi

  # 有外部 API 调用
  if git -C "$root" ls-files 2>/dev/null | grep -vE '^(docs/|scripts/|\.claude/|node_modules/)' \
    | xargs grep -lE '(fetch|axios|http\.request|httpClient|requests\.(get|post))' 2>/dev/null | head -1 | grep -q .; then
    dims+=("external_api:外部 API 可达性和响应格式需运行时验证")
  fi

  if [[ ${#dims[@]} -gt 0 ]]; then
    printf '%s\n' "${dims[@]}"
  fi
}

# -- verify 专项检查 --
#
# 这组检查挡的是"AI 宣称 verify 通过但实际从未打开过成品"的盲区。
# 源头：UI 项目后端 pytest 全绿, AI 自认交付, 用户一看就崩。
#
# == 维护规则: 新增 sg_* 函数必须附 red team fixture ==
# 每个机械门禁都是"门只挡老实人"的候选。实现完后必须立刻从红队视角自问:
#   1. 空对象/空数组能绕吗? (jq `// empty` 不过滤 `{}`, to_entries + select 才行)
#   2. touch 0-byte / 改后缀的空壳文件能绕吗? (size + magic bytes 双重校验)
#   3. 路径字符串前缀匹配能被尾缀同名攻击吗? (normalize + 精确相等或 `/` 分隔前缀)
#   4. JSON 字段为 null / 空字符串 / "null" 字面量能绕吗? (显式过滤空值)
#   5. 正则能被同词反义句子匹配吗? (边界锚 + 否定上下文检查)
# 回答"不能"之前必须在 cmd_self_test 里补至少 2 条恶意输入 fixture 证明挡住。
# 无 red team fixture 的 sg_* 函数视为未完成, 不能合并到主分支。

sg_verify_fault_coverage() {
  # 故障想象力每条编号 → verify-report.json 必须声明测试承接
  # 期望 verify-report.json 含 fault_coverage 数组, 每项 {fault_id, verified_by}
  local root="$1"
  local spec="$root/docs/spec.md"
  local report="$root/.claude/state/verify-report.json"
  [[ ! -f "$spec" ]] && return
  [[ ! -f "$report" ]] && return

  local section
  section=$(sed -nE '/故障想象力|[Ff]ailure.*[Ii]magination/,/^##[^#]/p' "$spec" 2>/dev/null)
  [[ -z "$section" ]] && return
  local fault_ids
  fault_ids=$(echo "$section" | grep -oE '^\s*([0-9]+)\.' | grep -oE '[0-9]+' | sort -u)
  [[ -z "$fault_ids" ]] && return
  local fault_count
  fault_count=$(echo "$fault_ids" | wc -l | tr -d ' ')

  if ! jq -e '.fault_coverage' "$report" >/dev/null 2>&1; then
    echo "verify-report.json 缺少 fault_coverage 数组 (spec 故障想象力有 ${fault_count} 条, 每条必须声明测试承接)"
    return
  fi

  local missing=""
  local missing_count=0
  local bogus=""
  local bogus_count=0
  while IFS= read -r fid; do
    [[ -z "$fid" ]] && continue
    local verified_by
    verified_by=$(jq -r --arg id "$fid" '.fault_coverage[] | select(.fault_id == ($id | tonumber) or .fault_id == $id) | .verified_by' "$report" 2>/dev/null)
    if [[ -z "$verified_by" || "$verified_by" == "null" || "$verified_by" == "" ]]; then
      missing="${missing} #${fid}"
      missing_count=$((missing_count + 1))
      continue
    fi
    # F1 修: verified_by 解析出文件 path, 必须真实存在
    local fpath="${verified_by%%::*}"
    fpath="${fpath%%:*}"
    fpath="${fpath# }"; fpath="${fpath% }"
    local abs_path
    if [[ "$fpath" = /* ]]; then
      abs_path="$fpath"
    else
      abs_path="$root/$fpath"
    fi
    if [[ ! -f "$abs_path" ]]; then
      bogus="${bogus} #${fid}→${fpath}"
      bogus_count=$((bogus_count + 1))
    fi
  done <<< "$fault_ids"
  if [[ "$missing_count" -gt 0 ]]; then
    echo "verify-report.json fault_coverage 未承接以下故障编号:${missing} (每条故障必须对应一个测试文件/断言)"
  fi
  if [[ "$bogus_count" -gt 0 ]]; then
    echo "verify-report.json fault_coverage 引用的测试文件不存在:${bogus} (verified_by 必须指向真实文件, 不能凭空编造)"
  fi
}

sg_verify_ui_screenshots() {
  # UI 项目: /verify 必须产出核心页面截图到 .claude/state/verify-screenshots/
  local root="$1"
  _is_ui_project "$root" || return
  local dir="$root/.claude/state/verify-screenshots"
  if [[ ! -d "$dir" ]]; then
    echo "UI 项目 /verify 缺少截图目录 .claude/state/verify-screenshots/ (核心页面 Playwright/curl 截图)"
    return
  fi
  local shots
  shots=$(find "$dir" -maxdepth 2 -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.webp' \) 2>/dev/null)
  local shot_count
  shot_count=$(echo "$shots" | grep -c . 2>/dev/null) || shot_count=0
  if [[ "$shot_count" -lt 1 ]]; then
    echo "UI 项目 /verify 截图目录为空 (核心链路每条至少一张截图证明成品真被打开过)"
    return
  fi
  # F2 修: 每张截图必须 ≥1024 bytes 且是真实图像
  local invalid_count=0
  local invalid_first=""
  while IFS= read -r shot; do
    [[ -z "$shot" ]] && continue
    local size
    size=$(stat -f %z "$shot" 2>/dev/null || stat -c %s "$shot" 2>/dev/null || echo 0)
    if [[ "$size" -lt 1024 ]]; then
      invalid_count=$((invalid_count + 1))
      [[ -z "$invalid_first" ]] && invalid_first="$(basename "$shot"): ${size} bytes"
      continue
    fi
    if command -v file >/dev/null 2>&1; then
      if ! file -b "$shot" 2>/dev/null | grep -qiE 'image|PNG|JPEG|Web[PM]'; then
        invalid_count=$((invalid_count + 1))
        [[ -z "$invalid_first" ]] && invalid_first="$(basename "$shot"): 非图像"
      fi
    fi
  done <<< "$shots"
  if [[ "$invalid_count" -gt 0 ]]; then
    echo "UI 截图有 ${invalid_count} 张无效 (首例: ${invalid_first}, 需真实 PNG/JPEG 且 ≥1KB, 不允许 touch 空文件)"
    return
  fi
  local last_commit_epoch
  last_commit_epoch=$(git -C "$root" log -1 --format="%ct" 2>/dev/null) || last_commit_epoch=0
  if [[ "$last_commit_epoch" -gt 0 ]]; then
    local newest
    newest=$(find "$dir" -maxdepth 2 -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.webp' \) -exec stat -f %m {} \; 2>/dev/null | sort -n | tail -1)
    [[ -z "$newest" ]] && newest=$(find "$dir" -maxdepth 2 -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.webp' \) -exec stat -c %Y {} \; 2>/dev/null | sort -n | tail -1)
    if [[ -n "$newest" && "$((last_commit_epoch - newest))" -gt 1800 ]]; then
      echo "UI 截图过期: 最近 commit 之后未重新截图 (/verify 必须在本次改动后重跑 E2E 截图)"
    fi
  fi
}

sg_verify_project_ownership() {
  # UI 项目: .claude/state/verify-ownership.json 声明服务进程 pid+cwd 与当前 project_root
  # 防"访问 :5173 看到别项目 UI 当自己 UI 交付"的硬失败
  local root="$1"
  _is_ui_project "$root" || return
  local f="$root/.claude/state/verify-ownership.json"
  if [[ ! -f "$f" ]]; then
    echo "UI 项目 /verify 缺少 .claude/state/verify-ownership.json (需声明前后端进程 cwd 与 project_root, 防串项目)"
    return
  fi
  if ! jq -e . "$f" >/dev/null 2>&1; then
    echo "verify-ownership.json 不是合法 JSON"
    return
  fi
  local declared
  declared=$(jq -r '.project_root // empty' "$f" 2>/dev/null)
  if [[ -z "$declared" ]]; then
    echo "verify-ownership.json 缺少 project_root 字段"
    return
  fi
  # F3 修: 路径精确匹配或 monorepo 父目录关系 (root 是 declared 的子目录)
  local d_norm="${declared%/}" r_norm="${root%/}"
  if [[ "$d_norm" != "$r_norm" && "$r_norm" != "$d_norm"/* ]]; then
    echo "verify-ownership.json project_root ($declared) 与当前项目 ($root) 不匹配 — 路径必须精确相等或为 monorepo 父目录"
    return
  fi
  # F4 修: meta 对象必须含实质字段
  local fe_len be_len
  fe_len=$(jq -r '(.frontend_meta // {}) | to_entries | map(select(.value != null and .value != "")) | length' "$f" 2>/dev/null)
  be_len=$(jq -r '(.backend_meta // {}) | to_entries | map(select(.value != null and .value != "")) | length' "$f" 2>/dev/null)
  fe_len=${fe_len:-0}
  be_len=${be_len:-0}
  if [[ "$fe_len" -lt 1 && "$be_len" -lt 1 ]]; then
    echo "verify-ownership.json frontend_meta/backend_meta 均为空 (至少一个需含 pid/cwd/url/project_name 等实质字段)"
  fi
}

# ---- 子命令: stub-scan ----
# 扫描生产代码中的 stub/mock/placeholder 信号
# 分级输出：BLOCK（空函数体等高置信度 stub）/ WARN（TODO/placeholder）/ INFO（mock 引用）
# 退出码：0 = 无 BLOCK，1 = 有 BLOCK 级发现

cmd_stub_scan() {
  if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "[ai-rules stub-scan] 非 git 仓库，跳过"
    exit 0
  fi

  # 收集源码文件（排除 test/mock/fixture/vendor/node_modules/docs/scripts/framework）
  local src_files
  src_files=$(git -C "$ROOT" ls-files 2>/dev/null \
    | grep -vE '^(docs/|scripts/|\.claude/|CLAUDE\.md|node_modules/|vendor/|dist/|build/|\.next/)' \
    | grep -vE '(test|spec|mock|fake|fixture|stub|__test__|__spec__|__mock__|_test\.go$|\.test\.|\.spec\.)' \
    | grep -vE '\.(md|json|lock|yaml|yml|toml|ini|conf|cfg|env)$' \
    || true)

  if [[ -z "$src_files" ]]; then
    echo "[ai-rules stub-scan] 无源码文件，跳过"
    exit 0
  fi

  local -a blocks=()
  local -a warns=()
  local -a infos=()
  local block_count=0 warn_count=0 info_count=0

  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    local full="$ROOT/$f"
    [[ ! -f "$full" ]] && continue

    # ---- BLOCK: 空函数体 / stub 函数 ----

    # Go: 函数体只有 return nil/return ""/return 0 或空体
    if [[ "$f" == *.go ]]; then
      local empty_funcs
      empty_funcs=$(grep -nE 'func\s+\w+.*\{' "$full" 2>/dev/null \
        | while IFS=: read -r line_num line_content; do
          # 查看函数体的下一行是否是 } 或 return nil/""
          local next_lines
          next_lines=$(sed -n "$((line_num + 1)),$((line_num + 3))p" "$full" 2>/dev/null)
          if echo "$next_lines" | head -1 | grep -qE '^\s*\}\s*$'; then
            echo "$f:$line_num"
          elif echo "$next_lines" | head -1 | grep -qE '^\s*return\s*(nil|""|0|false)\s*$' \
            && echo "$next_lines" | sed -n '2p' | grep -qE '^\s*\}\s*$'; then
            echo "$f:$line_num"
          fi
        done || true)
      if [[ -n "$empty_funcs" ]]; then
        while IFS= read -r loc; do
          [[ -n "$loc" ]] && blocks+=("$loc — 空函数体（Go）") && block_count=$((block_count + 1))
        done <<< "$empty_funcs"
      fi
    fi

    # Vue/TS: handler 方法体只有 ElMessage/console.log/占位/placeholder
    if [[ "$f" == *.vue || "$f" == *.ts || "$f" == *.js ]]; then
      local stub_handlers
      stub_handlers=$(grep -nE '(handle|on)[A-Z]\w*\s*\(' "$full" 2>/dev/null \
        | while IFS=: read -r line_num _; do
          local body
          body=$(sed -n "$((line_num)),$((line_num + 5))p" "$full" 2>/dev/null)
          if echo "$body" | grep -qiE '(ElMessage\.info|console\.log|alert)\s*\(\s*['\''"].*占位\|placeholder\|todo\|功能开发中'; then
            echo "$f:$line_num"
          fi
        done || true)
      if [[ -n "$stub_handlers" ]]; then
        while IFS= read -r loc; do
          [[ -n "$loc" ]] && blocks+=("$loc — stub handler（占位/placeholder）") && block_count=$((block_count + 1))
        done <<< "$stub_handlers"
      fi
    fi

    # ---- WARN: TODO/FIXME/PLACEHOLDER/HACK 在代码中 ----
    local todo_hits
    todo_hits=$(grep -nE '(TODO|FIXME|HACK|XXX|PLACEHOLDER)' "$full" 2>/dev/null \
      | grep -vE '^\s*(//|#|/?\*|\*).*stub-scan:ignore' \
      | head -5 || true)
    if [[ -n "$todo_hits" ]]; then
      while IFS= read -r hit; do
        [[ -n "$hit" ]] && warns+=("$f:$hit") && warn_count=$((warn_count + 1))
      done <<< "$todo_hits"
    fi

    # ---- INFO: 生产代码 import/引用了 mock/fake/stub 路径 ----
    if [[ "$f" == *.go || "$f" == *.ts || "$f" == *.js || "$f" == *.vue ]]; then
      local mock_imports
      mock_imports=$(grep -nE '(import|require|from)\s.*["\x27](.*mock|.*fake|.*stub|.*placeholder)' "$full" 2>/dev/null \
        | head -3 || true)
      if [[ -n "$mock_imports" ]]; then
        while IFS= read -r imp; do
          [[ -n "$imp" ]] && infos+=("$f:$imp — 生产代码引用 mock/fake 路径") && info_count=$((info_count + 1))
        done <<< "$mock_imports"
      fi
    fi

  done <<< "$src_files"

  # ---- 输出（safe expansion for set -u）----
  local has_output=0

  if [[ $block_count -gt 0 ]]; then
    has_output=1
    echo "[stub-scan] BLOCK (${block_count} 项 — 高置信度 stub，阻塞)："
    for b in ${blocks[@]+"${blocks[@]}"}; do
      echo "  BLOCK: $b"
    done
  fi

  if [[ $warn_count -gt 0 ]]; then
    has_output=1
    echo ""
    echo "[stub-scan] WARN (${warn_count} 项 — TODO/FIXME/PLACEHOLDER，需确认)："
    local count=0
    for w in ${warns[@]+"${warns[@]}"}; do
      echo "  WARN: $w"
      count=$((count + 1))
      [[ $count -ge 20 ]] && echo "  ... (截断，共 ${warn_count} 项)" && break
    done
  fi

  if [[ $info_count -gt 0 ]]; then
    has_output=1
    echo ""
    echo "[stub-scan] INFO (${info_count} 项 — mock 引用，需人判断)："
    for i in ${infos[@]+"${infos[@]}"}; do
      echo "  INFO: $i"
    done
  fi

  # 写入报告文件
  mkdir -p "$ROOT/.claude/state" 2>/dev/null
  if command -v jq >/dev/null 2>&1; then
    local blocks_json="[]" warns_json="[]" infos_json="[]"
    for b in ${blocks[@]+"${blocks[@]}"}; do
      blocks_json=$(echo "$blocks_json" | jq --arg d "$b" '. + [$d]')
    done
    for w in ${warns[@]+"${warns[@]}"}; do
      warns_json=$(echo "$warns_json" | jq --arg d "$w" '. + [$d]')
    done
    for i in ${infos[@]+"${infos[@]}"}; do
      infos_json=$(echo "$infos_json" | jq --arg d "$i" '. + [$d]')
    done
    jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --argjson blocks "$blocks_json" \
      --argjson warns "$warns_json" \
      --argjson infos "$infos_json" \
      '{ts:$ts, blocks:$blocks, warns:$warns, infos:$infos}' \
      > "$ROOT/.claude/state/stub-scan-report.json" 2>/dev/null
  fi

  if [[ $has_output -eq 0 ]]; then
    echo "[ai-rules stub-scan] 通过，未检测到 stub/mock 残留"
  fi

  if [[ $block_count -gt 0 ]]; then
    exit 1
  fi
  exit 0
}

# ---- 子命令: sanity ----
# 静态一致性检查：不运行代码，通过 grep/stat/git 检测常见部署问题
# 退出码：0 = 通过或无项目，1 = 有问题

cmd_sanity() {
  local -a issues=()
  local -a warnings=()
  local issue_count=0 warning_count=0

  if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "[ai-rules sanity] 非 git 仓库，跳过"
    exit 0
  fi

  # 1. 硬编码地址
  local result
  result=$(sg_sanity_hardcoded_addrs "$ROOT")
  if [[ -n "$result" ]]; then
    issues+=("$result") && issue_count=$((issue_count + 1))
  fi

  # 2. 构建产物新鲜度
  result=$(sg_sanity_build_freshness "$ROOT")
  if [[ -n "$result" ]]; then
    issues+=("$result") && issue_count=$((issue_count + 1))
  fi

  # 3. 测试证据新鲜度
  result=$(sg_sanity_test_evidence "$ROOT")
  if [[ -n "$result" ]]; then
    warnings+=("$result") && warning_count=$((warning_count + 1))
  fi

  # 4. 未验证维度（收集但不阻塞）
  local dims
  dims=$(sg_sanity_unverified_dimensions "$ROOT")

  # 写入 sanity 报告
  mkdir -p "$ROOT/.claude/state" 2>/dev/null
  local sanity_file="$ROOT/.claude/state/sanity-report.json"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  if command -v jq >/dev/null 2>&1; then
    local issues_json="[]"
    for i in ${issues[@]+"${issues[@]}"}; do
      issues_json=$(echo "$issues_json" | jq --arg d "$i" '. + [$d]')
    done
    local warnings_json="[]"
    for w in ${warnings[@]+"${warnings[@]}"}; do
      warnings_json=$(echo "$warnings_json" | jq --arg d "$w" '. + [$d]')
    done
    local dims_json="[]"
    if [[ -n "$dims" ]]; then
      while IFS= read -r d; do
        [[ -n "$d" ]] && dims_json=$(echo "$dims_json" | jq --arg d "$d" '. + [$d]')
      done <<< "$dims"
    fi

    jq -nc --arg ts "$ts" \
      --argjson issues "$issues_json" \
      --argjson warnings "$warnings_json" \
      --argjson not_verified "$dims_json" \
      '{ts:$ts, issues:$issues, warnings:$warnings, not_verified:$not_verified}' \
      > "$sanity_file" 2>/dev/null
  fi

  # 输出
  if [[ $issue_count -gt 0 ]]; then
    echo "[ai-rules sanity] 检测到 ${issue_count} 个问题："
    for i in ${issues[@]+"${issues[@]}"}; do
      echo "  - $i"
    done
    if [[ $warning_count -gt 0 ]]; then
      echo ""
      echo "警告："
      for w in ${warnings[@]+"${warnings[@]}"}; do
        echo "  - $w"
      done
    fi
    exit 1
  fi

  if [[ $warning_count -gt 0 ]]; then
    echo "[ai-rules sanity] 通过（${warning_count} 条警告）："
    for w in ${warnings[@]+"${warnings[@]}"}; do
      echo "  - $w"
    done
    exit 0
  fi

  echo "[ai-rules sanity] 通过，无问题"
  exit 0
}

# ---- 子命令: skill-gate ----
# 组合原子检查函数，验收 Skill 产出物
# 退出码：0 = 通过，1 = 不达标

cmd_skill_gate() {
  local skill="${1:-}"
  if [[ -z "$skill" ]]; then
    echo "Usage: ai-rules.sh skill-gate <spec|impl|check|verify|release>"
    exit 1
  fi

  local failures=()
  local verified=()
  local heuristic_warnings=()

  # L2: upstream 新鲜度警告 (不阻塞)
  sg_upstream_staleness_warn "$ROOT"

  sg_run() {
    local result="$1"
    if [[ -n "$result" ]]; then
      failures+=("$result")
    else
      verified+=("$2")  # 第二个参数：检查项描述（通过时记录）
    fi
  }

  # 启发式检查：fail 不阻塞 Stop，写入 clearance not_verified + heuristic-log
  # LARP detector 类检查（主语覆盖率、去重、新鲜度等）用此包装
  sg_run_soft() {
    local result="$1"
    local label="$2"
    if [[ -n "$result" ]]; then
      heuristic_warnings+=("${label}: ${result}")
      # 写入审计日志供检查点复查
      local hlog="$ROOT/.claude/state/heuristic-log.txt"
      mkdir -p "$(dirname "$hlog")" 2>/dev/null
      echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ${skill} ${label}: ${result}" >> "$hlog" 2>/dev/null || true
    else
      verified+=("$label")
    fi
  }

  case "$skill" in
    spec)
      sg_run "$(sg_spec_file_exists "$SPEC_FILE")" "spec.md 文件存在"
      if [[ -f "$SPEC_FILE" ]]; then
        sg_run_soft "$(sg_spec_size_warning "$SPEC_FILE")" "spec.md 行数未逼近 Read 截断阈值"
        sg_run "$(sg_spec_prd_challenge "$SPEC_FILE")" "PRD 挑战（≥3 视角 + 缺口处置）"
        sg_run "$(sg_spec_failure_imagination "$SPEC_FILE")" "故障想象力维度枚举"
        sg_run_soft "$(sg_spec_fi_has_subjects "$SPEC_FILE")" "故障条目 ≥60% 有主语"
        sg_run_soft "$(sg_spec_fi_no_duplicates "$SPEC_FILE")" "故障条目非套话"
        sg_run "$(sg_spec_fi_cross_check "$SPEC_FILE")" "故障条目有对账标注"
        sg_run "$(sg_spec_coverage_gaps "$SPEC_FILE")" "故障条目全部被 ACCEPT 覆盖"
        sg_run "$(sg_spec_critical_modules "$SPEC_FILE")" "核心难点识别"
        sg_run "$(sg_spec_coverage_contract "$SPEC_FILE")" "覆盖契约章节存在"
        sg_run "$(sg_spec_task_template "$SPEC_FILE")" "TASK/ACCEPT/FILES 数量匹配"
        sg_run "$(sg_spec_external_coverage "$SPEC_FILE")" "外部文档覆盖完整"
        # Step 3 多视角审查产物（anti-LARP）：复杂项目 or 已声明审查章节时强制
        if [[ "$(sg_step3_triggered "$SPEC_FILE")" == "1" ]]; then
          sg_run "$(sg_step3_file_exists "$ROOT")" "Step 3 产物文件存在"
          if [[ -n "$(sg_step3_latest_json "$ROOT")" ]]; then
            sg_run "$(sg_step3_json_valid "$ROOT")" "Step 3 JSON 结构合法"
            sg_run "$(sg_step3_roles_complete "$ROOT")" "Step 3 三必选角色"
            sg_run "$(sg_step3_three_elements "$ROOT")" "Step 3 DISSENT 三要素 (evidence/suggestion/impact)"
            sg_run "$(sg_step3_verification_nonempty "$ROOT")" "Step 3 NO_DISSENT 非空 verification"
            sg_run "$(sg_step3_absorbed_as_valid "$ROOT" "$SPEC_FILE")" "Step 3 P0 absorbed_as 引用有效"
            sg_run "$(sg_step3_prior_round_refs "$ROOT")" "Step 3 差分审查（Round N+1 引前轮 P0）"
            sg_run "$(sg_step3_prior_p0_strict "$ROOT")" "Step 3 前轮 P0 逐条 carry-over (反 Round 通过≠问题修)"
            sg_run "$(sg_step3_roles_for_context "$SPEC_FILE" "$ROOT")" "Step 3 上下文角色（技术/安全/运维）"
            sg_run "$(sg_step3_agent_invocations "$ROOT")" "Step 3 真实并发 Agent 调用（反自扮演）"
          fi
        fi
      fi
      sg_run "$(sg_spec_frozen_delta "$SPEC_FILE")" "spec API 路径单复数一致 (防 §API FROZEN 漂移)"
      sg_run "$(sg_spec_bug_phase "$SPEC_FILE")" "bug 关键词触发 Bug 定性前置声明"
      sg_run "$(sg_task_accept_source "$SPEC_FILE")" "TASK ACCEPT 数值必须引 SOURCE"
      sg_run "$(sg_spec_design_md "$ROOT")" "UI 项目 DESIGN.md 完整"
      sg_run "$(sg_spec_page_specs "$SPEC_FILE" "$ROOT")" "UI 项目页面规格"
      sg_run "$(sg_spec_preflight_section "$SPEC_FILE")" "前置人工动作清单存在"
      sg_run "$(sg_spec_preflight_mapped "$SPEC_FILE")" "前置清单条目与 TASK HUMAN 对账"
      sg_run "$(sg_spec_task_human_complete "$SPEC_FILE")" "TASK 人动作反扫 (人一次性动作 → HUMAN:action)"
      sg_run "$(sg_status_file_exists "$STATUS_FILE")" "status.md 存在"
      if [[ -f "$STATUS_FILE" ]]; then
        sg_run "$(sg_status_has_phase "$STATUS_FILE")" "PROJECT_PHASE 合法"
      fi
      ;;
    impl)
      # UI 项目前置检查：DESIGN.md 必须在 /impl 前就绪
      sg_run "$(sg_spec_design_md "$ROOT")" "UI 项目 DESIGN.md 就绪"
      # UI 项目：前端代码必须实际消费 DESIGN.md token（防止文档与代码脱钩）
      sg_run "$(sg_impl_design_token_consumed "$ROOT")" "前端代码消费 DESIGN.md token"
      sg_run "$(sg_impl_has_done_tasks "$STATUS_FILE")" "有已完成任务"
      sg_run "$(sg_impl_recent_commit "$ROOT")" "最近有 commit"
      sg_run "$(sg_impl_agent_invocations "$ROOT")" "并发批次 agent_invocations 真实性"
      if [[ -f "$STATUS_FILE" ]]; then
        sg_run "$(sg_status_has_phase "$STATUS_FILE")" "PROJECT_PHASE 合法"
        local phase
        phase=$(grep -oE 'PROJECT_PHASE:\s*(building|stabilizing|live)' "$STATUS_FILE" 2>/dev/null \
          | sed -E 's/PROJECT_PHASE:\s*//' | head -1)
        sg_run "$(sg_status_has_abandoned "$STATUS_FILE" "${phase:-building}")" "放弃方案章节"
        sg_run_soft "$(sg_status_freshness "$STATUS_FILE" "$ROOT")" "status.md 更新新鲜度"
      fi
      # stub-scan: 生产代码中的 BLOCK 级 stub 残留
      local stub_result
      stub_result=$(cmd_stub_scan 2>&1) || true
      local stub_blocks
      stub_blocks=$(echo "$stub_result" | grep -c 'BLOCK:' 2>/dev/null) || stub_blocks=0
      if [[ "$stub_blocks" -gt 0 ]]; then
        failures+=("生产代码中检测到 ${stub_blocks} 个 stub 残留（空函数体/占位 handler）。运行 stub-scan 查看详情，或在 DONE-TEMPLATE 的 STUB_REMAINING 中声明保留理由")
      else
        verified+=("无 BLOCK 级 stub 残留")
      fi
      ;;
    check)
      sg_run "$(sg_json_field "$ROOT/.claude/state/check-report.json" "result" "check-report.json")" "check-report.json result 字段"
      ;;
    verify)
      sg_run "$(sg_json_field "$ROOT/.claude/state/verify-report.json" "decision" "verify-report.json")" "verify decision 字段"
      sg_run "$(sg_json_field "$ROOT/.claude/state/verify-report.json" "contract_status" "verify-report.json")" "verify contract_status 字段"
      # 测试证据新鲜度：verify 阶段测试报告不能比最后 commit 旧
      sg_run "$(sg_sanity_test_evidence "$ROOT")" "测试证据新鲜度"
      # 故障想象力每条编号必须在 verify-report.json 的 fault_coverage 中承接
      sg_run "$(sg_verify_fault_coverage "$ROOT")" "故障编号测试承接完整"
      # UI 项目: 必须有核心页面截图 (通看成品 gate)
      sg_run "$(sg_verify_ui_screenshots "$ROOT")" "UI 项目核心页面截图"
      # UI 项目: 必须声明服务进程归属 (防串项目)
      sg_run "$(sg_verify_project_ownership "$ROOT")" "UI 项目服务归属验证"
      ;;
    release)
      sg_run "$(sg_release_decision_valid "$ROOT/.claude/state/release-report.json")" "release decision 合法"
      if [[ ! -f "$ROOT/.claude/state/check-report.json" ]]; then
        failures+=("前置条件缺失：check-report.json 不存在")
      fi
      # 构建产物新鲜度：有构建目录时，不能比源码旧
      sg_run "$(sg_sanity_build_freshness "$ROOT")" "构建产物新鲜度"
      # 测试证据新鲜度
      sg_run "$(sg_sanity_test_evidence "$ROOT")" "测试证据新鲜度"
      # 硬编码地址
      sg_run "$(sg_sanity_hardcoded_addrs "$ROOT")" "无硬编码地址"
      ;;
    *)
      echo "Unknown skill: $skill (可选: spec, impl, check, verify, release)"
      exit 1
      ;;
  esac

  if [[ ${#failures[@]} -gt 0 ]]; then
    echo "[ai-rules skill-gate] /${skill} 产出验收不通过 (${#failures[@]} 项缺失)："
    for f in ${failures[@]+"${failures[@]}"}; do
      echo "  - $f"
    done
    echo ""
    echo "请补全以上缺失项后再宣称完成。"
    exit 1
  fi

  # ---- 放行清单 ----
  # 机械验收通过，生成结构化收据 + 语义提示
  local clearance_dir="$ROOT/.claude/state"
  mkdir -p "$clearance_dir" 2>/dev/null
  local clearance_file="$clearance_dir/clearance-${skill}.json"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # 每个 skill 的语义审查项（机械检查不了的维度）
  local beyond=""
  case "$skill" in
    spec)
      beyond=$(cat <<'BM'
故障想象力条目是否真的覆盖核心风险(而非形式凑数)
ACCEPT 验收标准是否真的可断言、可自动化测试
覆盖契约的边界划分是否合理(不做清单是否遗漏)
TASK 间的 DEP 依赖关系是否完整
BM
) ;;
    impl)
      beyond=$(cat <<'BM'
DONE-TEMPLATE 的 TESTS 输出是否真实(而非编造)
commit 内容是否与 ACCEPT 验收标准对应
status.md 更新是否反映真实进度(而非抄模板)
BM
) ;;
    check)
      beyond=$(cat <<'BM'
check-report 的 result 是否与实际测试输出一致
人工确认项的状态判定是否准确
BM
) ;;
    verify)
      beyond=$(cat <<'BM'
覆盖契约 contract_status 是否与实际测试覆盖匹配
回归测试范围是否充分
BM
) ;;
    release)
      beyond=$(cat <<'BM'
前置 check-report 的可信度
release decision 是否与实际证据链匹配
BM
) ;;
  esac

  # 写入 JSON 放行清单
  local verified_json="[]"
  if command -v jq >/dev/null 2>&1; then
    verified_json="[]"
    for v in ${verified[@]+"${verified[@]}"}; do
      verified_json=$(echo "$verified_json" | jq --arg d "$v" '. + [$d]')
    done
    local beyond_json="[]"
    while IFS= read -r line; do
      [[ -n "$line" ]] && beyond_json=$(echo "$beyond_json" | jq --arg d "$line" '. + [$d]')
    done <<< "$beyond"

    # 记录 spec hash 用于跨会话校验
    local spec_hash=""
    if [[ "$skill" == "spec" && -f "$SPEC_FILE" ]]; then
      spec_hash=$(git -C "$ROOT" hash-object "$SPEC_FILE" 2>/dev/null || md5 -q "$SPEC_FILE" 2>/dev/null || echo "")
    fi

    # 收集未验证维度
    local not_verified_json="[]"
    local dims_output
    dims_output=$(sg_sanity_unverified_dimensions "$ROOT" 2>/dev/null || true)
    if [[ -n "$dims_output" ]]; then
      while IFS= read -r dline; do
        [[ -n "$dline" ]] && not_verified_json=$(echo "$not_verified_json" | jq --arg d "$dline" '. + [$d]')
      done <<< "$dims_output"
    fi

    # 启发式 warning 合并入 not_verified（LARP detector 类检查，不阻塞但要人看）
    local heuristic_json="[]"
    for hw in ${heuristic_warnings[@]+"${heuristic_warnings[@]}"}; do
      heuristic_json=$(echo "$heuristic_json" | jq --arg d "$hw" '. + [$d]')
      not_verified_json=$(echo "$not_verified_json" | jq --arg d "启发式: $hw" '. + [$d]')
    done

    jq -nc --arg skill "$skill" --arg ts "$ts" --arg spec_hash "$spec_hash" \
      --argjson verified "$verified_json" \
      --argjson beyond "$beyond_json" \
      --argjson not_verified "$not_verified_json" \
      --argjson heuristic_warnings "$heuristic_json" \
      '{skill:$skill, ts:$ts, spec_hash:$spec_hash, verified:$verified, beyond_mechanical:$beyond, not_verified:$not_verified, heuristic_warnings:$heuristic_warnings}' \
      > "$clearance_file" 2>/dev/null
  fi

  # --check-only 模式：只验证，不生成 clearance 文件
  if [[ "${2:-}" == "--check-only" ]]; then
    echo "[ai-rules skill-gate] /${skill} 产出验收通过 (${#verified[@]} 项机械验证)"
    [[ "${#heuristic_warnings[@]}" -gt 0 ]] && echo "  (含 ${#heuristic_warnings[@]} 项启发式 WARN，不阻塞)"
    exit 0
  fi

  # stdout: 简洁通过消息
  local pass_msg="[ai-rules skill-gate] /${skill} 产出验收通过 (${#verified[@]} 项机械验证)"
  [[ "${#heuristic_warnings[@]}" -gt 0 ]] && pass_msg="${pass_msg}，${#heuristic_warnings[@]} 项启发式 WARN"
  echo "$pass_msg"

  # 放行清单的语义提示写到单独文件，由 hook 读取输出
  # 不直接写 stdout，因为 cmd_skill_gate 的 stdout 被 hook 捕获判断
  local hint_file="$clearance_dir/clearance-hint-${skill}.txt"
  {
    echo "以下维度超出脚本验证能力，请在检查点时人工确认："
    while IFS= read -r line; do
      [[ -n "$line" ]] && echo "  - $line"
    done <<< "$beyond"
    if [[ "${#heuristic_warnings[@]}" -gt 0 ]]; then
      echo ""
      echo "启发式 WARN（不阻塞但值得看一眼）："
      for hw in "${heuristic_warnings[@]}"; do
        echo "  - $hw"
      done
    fi
  } > "$hint_file" 2>/dev/null

  exit 0
}

# ---- 子命令: self-test ----
# 用内置 fixture 对每个原子检查函数做快速自检
# 任何一个断言失败 → 输出失败详情 + exit 1

cmd_self_test() {
  local pass=0 fail=0 total=0
  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" EXIT
  local ROOT_BACKUP="$ROOT"

  _assert_empty() {
    local label="$1" actual="$2"
    total=$((total + 1))
    if [[ -z "$actual" ]]; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
      echo "FAIL [$label]: expected empty, got: $actual"
    fi
  }

  _assert_not_empty() {
    local label="$1" actual="$2"
    total=$((total + 1))
    if [[ -n "$actual" ]]; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
      echo "FAIL [$label]: expected non-empty, got empty"
    fi
  }

  _assert_contains() {
    local label="$1" actual="$2" substr="$3"
    total=$((total + 1))
    if echo "$actual" | grep -qF "$substr"; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
      echo "FAIL [$label]: expected to contain '$substr', got: $actual"
    fi
  }

  # --- fixture: 完整的 spec.md ---
  local good_spec="$tmpdir/good-spec.md"
  cat > "$good_spec" <<'FIXTURE'
# Spec

## PRD 挑战

### 状态完整性
1. 报名状态取消后能否重新报名 — 补入 spec

### 边界条件
2. 0 人报名时列表显示 — 补入 spec

### 多角色一致性
3. 组织者改时间已报名用户看什么 — deferred

### 时序敏感
4. 报名超时重试是否重复 — 补入 spec

## 故障想象力

故障主体：用户操作、网络、数据库
故障时机：操作前、操作中、操作后
故障表现：数据丢失、静默失败、状态卡死

1. 用户故障一
2. 用户故障二
3. 用户故障三
4. 管理员故障四
5. 调用者故障五

## 覆盖契约

核心链路

TASK: 任务一
ACCEPT: Given X When Y Then Z
FILES: a.ts
FIXTURE

  # --- fixture: 缺故障想象力的 spec ---
  local no_fi_spec="$tmpdir/no-fi-spec.md"
  cat > "$no_fi_spec" <<'FIXTURE'
# Spec

## 覆盖契约

TASK: 任务一
ACCEPT: Given X When Y Then Z
FILES: a.ts
FIXTURE

  # --- fixture: 正文含"故障想象力"关键词但实际章节在后面（回归测试：防正则假阳性）---
  local fi_body_mention_spec="$tmpdir/fi-body-mention-spec.md"
  cat > "$fi_body_mention_spec" <<'FIXTURE'
# Spec

## 板块说明

- spec 质量指标（故障想象力条目数、主语覆盖率）

## 故障想象力

故障主体：用户操作、网络、权限
故障时机：操作前、操作中、操作后

1. 未登录用户看到所有活动
2. 用户报名后刷新状态消失
3. 管理员删除后用户无通知
4. 访客在满员活动仍能报名
5. 调用者传入过期 token 成功

## 覆盖契约

TASK: 任务一
ACCEPT: Given X When Y Then Z
FILES: a.ts
FIXTURE

  # --- fixture: 只有 4 条故障的 spec ---
  # 有故障章节但无维度枚举（旧格式，不达标）
  local no_dim_fi_spec="$tmpdir/no-dim-fi-spec.md"
  cat > "$no_dim_fi_spec" <<'FIXTURE'
# Spec

## 故障想象力

1. 故障一
2. 故障二
3. 故障三
4. 故障四

## 覆盖契约

TASK: 任务一
ACCEPT: Given X When Y Then Z
FILES: a.ts
FIXTURE

  # --- fixture: TASK 多于 ACCEPT ---
  local bad_task_spec="$tmpdir/bad-task-spec.md"
  cat > "$bad_task_spec" <<'FIXTURE'
# Spec

## 故障想象力

故障主体：用户操作、网络
故障时机：操作中、操作后

1. a
2. b
3. c
4. d
5. e

## 覆盖契约

TASK: 任务一
ACCEPT: Given X When Y Then Z
FILES: a.ts
TASK: 任务二
FILES: b.ts
FIXTURE

  # --- fixture: 故障想象力质量测试 ---
  local good_fi_spec="$tmpdir/good-fi-spec.md"
  cat > "$good_fi_spec" <<'FIXTURE'
# Spec

## 故障想象力

故障主体：用户操作、网络、权限、并发
故障时机：操作前、操作中、操作后
故障表现：数据错乱、静默失败、状态卡死

1. 未登录用户看到所有活动都显示已报名
2. 用户报名后刷新页面状态消失
3. 管理员删除活动后已报名用户收不到通知
4. 访客在满员活动上仍能点击报名按钮
5. 开发者调用 API 时传入过期的 token 仍然成功

ACCEPT 某某功能（防 故障#1）
ACCEPT 状态持久化（防 故障#2）

## 覆盖契约

核心链路

TASK: 任务一
ACCEPT: Given X When Y Then Z
FILES: a.ts
FIXTURE

  # --- fixture: 故障全覆盖 spec（每条都有对账）---
  local full_coverage_spec="$tmpdir/full-coverage-spec.md"
  cat > "$full_coverage_spec" <<'FIXTURE'
# Spec

## 故障想象力

故障主体：用户操作、权限、数据库
故障时机：操作前、操作后

1. 未登录用户看到所有活动
2. 用户报名后刷新状态消失
3. 管理员删除后用户无通知

ACCEPT 认证功能（防 故障#1）
ACCEPT 状态持久化（防 故障#2）
ACCEPT 通知模块（防 故障#3）

## 覆盖契约

TASK: 任务一
ACCEPT: Given X When Y Then Z
FILES: a.ts
FIXTURE

  local no_subject_spec="$tmpdir/no-subject-spec.md"
  cat > "$no_subject_spec" <<'FIXTURE'
# Spec

## 故障想象力

故障主体：系统、网络、数据库
故障时机：运行时、启动时

1. 空指针异常
2. 数据库连接超时
3. 页面加载失败
4. 接口返回 500
5. 缓存未命中

## 覆盖契约

TASK: 任务一
ACCEPT: Given X When Y Then Z
FILES: a.ts
FIXTURE

  local dup_fi_spec="$tmpdir/dup-fi-spec.md"
  cat > "$dup_fi_spec" <<'FIXTURE'
# Spec

## 故障想象力

故障主体：用户操作、数据库
故障表现：数据错乱

1. 用户看到错误的数据A
2. 用户看到错误的数据B
3. 用户看到错误的数据C
4. 用户看到错误的数据D
5. 用户看到错误的数据E

## 覆盖契约

TASK: 任务一
ACCEPT: Given X When Y Then Z
FILES: a.ts
FIXTURE

  # --- fixture: status.md 质量测试 ---
  local good_status="$tmpdir/good-status.md"
  cat > "$good_status" <<'FIXTURE'
# Status
PROJECT_PHASE: building
- [x] 任务一
- [ ] 任务二
FIXTURE

  local empty_status="$tmpdir/empty-status.md"
  cat > "$empty_status" <<'FIXTURE'
# Status
- [ ] 任务一
FIXTURE

  local stab_status="$tmpdir/stab-status.md"
  cat > "$stab_status" <<'FIXTURE'
# Status
PROJECT_PHASE: stabilizing
- [x] 任务一

## 放弃的方案
- 方案A：尝试了 X，失败原因 Y，改用 Z
FIXTURE

  local stab_no_abandoned="$tmpdir/stab-no-abandoned.md"
  cat > "$stab_no_abandoned" <<'FIXTURE'
# Status
PROJECT_PHASE: stabilizing
- [x] 任务一
FIXTURE

  # --- fixture: JSON reports ---
  local good_check="$tmpdir/check-report.json"
  echo '{"result":"pass","details":"all good"}' > "$good_check"

  local bad_check="$tmpdir/bad-check.json"
  echo '{"details":"missing result"}' > "$bad_check"

  local good_verify="$tmpdir/verify-report.json"
  echo '{"decision":"pass","contract_status":"complete"}' > "$good_verify"

  local bad_verify="$tmpdir/bad-verify.json"
  echo '{"decision":"pass"}' > "$bad_verify"

  local good_release="$tmpdir/release-report.json"
  echo '{"decision":"release-ready"}' > "$good_release"

  local bad_release="$tmpdir/bad-release.json"
  echo '{"decision":"yolo"}' > "$bad_release"

  echo "=== sg_spec_file_exists ==="
  _assert_empty    "存在的文件"   "$(sg_spec_file_exists "$good_spec")"
  _assert_not_empty "不存在的文件" "$(sg_spec_file_exists "$tmpdir/nope.md")"

  echo "=== sg_spec_size_warning ==="
  local small_spec="$tmpdir/spec-small.md"
  awk 'BEGIN{for(i=0;i<1000;i++) print "line"}' > "$small_spec"
  _assert_empty    "1000 行无告警"  "$(sg_spec_size_warning "$small_spec")"
  local big_spec="$tmpdir/spec-big.md"
  awk 'BEGIN{for(i=0;i<1900;i++) print "line"}' > "$big_spec"
  _assert_contains "1900 行告警"    "$(sg_spec_size_warning "$big_spec")" "逼近"
  _assert_empty    "不存在的文件"   "$(sg_spec_size_warning "$tmpdir/nope-size.md")"

  echo "=== sg_spec_design_md ==="
  # fixture: 有前端文件但无 DESIGN.md
  local ui_project="$tmpdir/ui-project"
  mkdir -p "$ui_project/src"
  touch "$ui_project/src/App.vue"
  ROOT="$ui_project"
  _assert_not_empty "有前端文件无DESIGN" "$(sg_spec_design_md "$ui_project")"
  # fixture: 有前端文件 + 完整 DESIGN.md
  cat > "$ui_project/DESIGN.md" <<'DESIGNFIX'
# Design System
## 1. Visual Theme & Atmosphere
Clean modern style.
## 2. Color Palette & Roles
- Primary: #533afd
- Background: #ffffff
- Text: #061b31
- Accent: #ea2261
## 3. Typography Rules
| Role | Size | Weight | Line Height |
|------|------|--------|-------------|
| Heading | 32px | 300 | 1.1 |
| Body | 16px | 400 | 1.4 |
| Caption | 12px | 400 | 1.3 |
## 4. Component Stylings
### Buttons
Primary: #533afd bg, white text, 4px radius
### Cards
White bg, 1px border #e5edf5, 6px radius
### Inputs
1px border #e5edf5, focus #533afd
### Navigation
Sticky header, white bg
## 5. Layout Principles
8px base grid.
## 6. Depth & Elevation
Standard shadow: rgba(50,50,93,0.25) 0px 30px 45px -30px
## 7. Do's and Don'ts
### Do
Use brand colors consistently
### Don't
Use arbitrary colors
## 8. Responsive Behavior
Mobile: <640px, Tablet: 640-1024px, Desktop: >1024px
## 9. Agent Prompt Guide
Primary CTA: #533afd, Background: #ffffff
DESIGNFIX
  _assert_empty     "完整DESIGN通过" "$(sg_spec_design_md "$ui_project")"
  # fixture: DESIGN.md 存在但内容空（无章节）
  echo "# Design System" > "$ui_project/DESIGN.md"
  _assert_not_empty "空DESIGN检出"   "$(sg_spec_design_md "$ui_project")"
  # fixture: DESIGN.md 有章节但无颜色 hex
  cat > "$ui_project/DESIGN.md" <<'DESIGNFIX'
# Design
## Visual Theme
## Color Palette
Primary: blue
## Typography
| Role | Size |
|------|------|
| H1 | 32px |
| Body | 16px |
| Small | 12px |
## Component Stylings
### Buttons
Blue background
### Cards
White cards
## Layout
8px grid
## Depth & Elevation
Standard shadow
## Do's and Don'ts
Do: be consistent
## Responsive
Mobile first
## Agent Prompt Guide
Use blue
DESIGNFIX
  _assert_contains  "颜色不足"       "$(sg_spec_design_md "$ui_project")" "hex"
  # fixture: 无前端文件（非 UI 项目）
  local backend_project="$tmpdir/backend-project"
  mkdir -p "$backend_project/src"
  touch "$backend_project/src/main.go"
  _assert_empty     "非UI项目跳过" "$(sg_spec_design_md "$backend_project")"
  ROOT="$ROOT_BACKUP"

  echo "=== sg_impl_design_token_consumed ==="
  # fixture: DESIGN.md 有 token 但源码完全没消费
  local ui_no_token="$tmpdir/ui-no-token"
  mkdir -p "$ui_no_token/src"
  cat > "$ui_no_token/DESIGN.md" <<'TOKENFIX'
# Design
## Color
| Token | Hex |
|-------|-----|
| `--bg-base` | #0E0F12 |
| `--bg-surface` | #16181D |
| `--text-primary` | #E8EAED |
| `--accent-primary` | #4FC3F7 |
| `--border-subtle` | #2A2E37 |
| `--accent-success` | #66BB6A |
TOKENFIX
  cat > "$ui_no_token/src/App.tsx" <<'APPFIX'
export default function App() {
  return <main style={{ fontFamily: "system-ui", padding: 24 }}>Hello</main>;
}
APPFIX
  cat > "$ui_no_token/src/main.tsx" <<'MAINFIX'
import App from './App';
console.log(App);
MAINFIX
  cat > "$ui_no_token/src/Other.tsx" <<'OTHERFIX'
export const x = 1;
OTHERFIX
  _assert_contains  "token 未消费"   "$(sg_impl_design_token_consumed "$ui_no_token")" "未消费"
  # fixture: 源码消费了 token
  local ui_with_token="$tmpdir/ui-with-token"
  mkdir -p "$ui_with_token/src"
  cp "$ui_no_token/DESIGN.md" "$ui_with_token/DESIGN.md"
  cat > "$ui_with_token/src/global.css" <<'CSSFIX'
:root {
  --bg-base: #0E0F12;
  --bg-surface: #16181D;
  --text-primary: #E8EAED;
  --accent-primary: #4FC3F7;
  --border-subtle: #2A2E37;
}
body { background: var(--bg-base); color: var(--text-primary); }
CSSFIX
  cat > "$ui_with_token/src/App.tsx" <<'APPFIX'
import './global.css';
export default function App() {
  return <main style={{ background: "var(--bg-surface)", border: "1px solid var(--border-subtle)" }}>Hi</main>;
}
APPFIX
  cat > "$ui_with_token/src/Button.tsx" <<'BTNFIX'
export const Button = () => <button style={{ background: "var(--accent-primary)" }}>Go</button>;
BTNFIX
  _assert_empty     "token 已消费"   "$(sg_impl_design_token_consumed "$ui_with_token")"
  # fixture: scaffold 阶段（源文件 < 3 个）跳过
  local ui_scaffold="$tmpdir/ui-scaffold"
  mkdir -p "$ui_scaffold/src"
  cp "$ui_no_token/DESIGN.md" "$ui_scaffold/DESIGN.md"
  cat > "$ui_scaffold/src/App.tsx" <<'APPFIX'
export default function App() { return <div>Scaffold</div>; }
APPFIX
  _assert_empty     "scaffold 跳过"  "$(sg_impl_design_token_consumed "$ui_scaffold")"
  # fixture: DESIGN.md 无 token 定义（tailwind 原子类体系）跳过
  local ui_no_vars="$tmpdir/ui-no-vars"
  mkdir -p "$ui_no_vars/src"
  cat > "$ui_no_vars/DESIGN.md" <<'NOVARFIX'
# Design
## Colors
Primary: #533afd
Use tailwind: bg-blue-500 text-white
NOVARFIX
  cat > "$ui_no_vars/src/App.tsx" <<'APPFIX'
export default function App() { return <div className="bg-blue-500">Hi</div>; }
APPFIX
  cat > "$ui_no_vars/src/Button.tsx" <<'BTNFIX'
export const B = () => <button className="text-white">Go</button>;
BTNFIX
  cat > "$ui_no_vars/src/Card.tsx" <<'CARDFIX'
export const C = () => <div className="p-4">Card</div>;
CARDFIX
  _assert_empty     "无 token 体系跳过"  "$(sg_impl_design_token_consumed "$ui_no_vars")"

  echo "=== sg_spec_page_specs ==="
  ROOT="$ui_project"
  # L1: 全局 4 类状态 ≥ 3 → pass
  local ui_spec_good="$tmpdir/ui-spec-good.md"
  cat > "$ui_spec_good" <<'FIXTURE'
# Spec
## 首页
组件清单：团购卡片列表、搜索栏、底部导航
空状态：显示"暂无团购"插画
加载态：骨架屏
错误态：重试按钮
FIXTURE
  _assert_empty     "L1 通过 (4/4 类)" "$(sg_spec_page_specs "$ui_spec_good" "$ui_project")"

  # L1 失败: 0 类状态 → 报错
  local ui_spec_bad="$tmpdir/ui-spec-bad.md"
  cat > "$ui_spec_bad" <<'FIXTURE'
# Spec
## 功能
用户可以浏览团购列表
FIXTURE
  _assert_contains  "L1 失败 (0/4 类)" "$(sg_spec_page_specs "$ui_spec_bad" "$ui_project")" "状态类型覆盖不足"

  # L1 失败: 只有 2 类 → 不够
  local ui_spec_2type="$tmpdir/ui-spec-2type.md"
  cat > "$ui_spec_2type" <<'FIXTURE'
# Spec
## 首页
组件清单：团购卡片列表
空状态：显示空
FIXTURE
  _assert_contains  "L1 失败 (2/4 类)" "$(sg_spec_page_specs "$ui_spec_2type" "$ui_project")" "状态类型覆盖不足"

  # L2: 多页面, 部分无状态 → 覆盖率 < 50% → 报错
  local ui_spec_partial="$tmpdir/ui-spec-partial.md"
  cat > "$ui_spec_partial" <<'FIXTURE'
# Spec
## 首页
组件清单：卡片列表
空状态：暂无数据
加载态：骨架屏
错误态：重试按钮
## 详情页
展示物品详细信息
## 设置页
修改用户偏好
## 列表页
浏览所有物品
FIXTURE
  _assert_contains  "L2 覆盖率不足" "$(sg_spec_page_specs "$ui_spec_partial" "$ui_project")" "页面状态覆盖率"

  # L2: 多页面, 全部有状态 → pass
  local ui_spec_full="$tmpdir/ui-spec-full.md"
  cat > "$ui_spec_full" <<'FIXTURE'
# Spec
## 首页
组件清单：卡片列表
空状态：暂无数据
加载态：骨架屏
错误态：重试按钮
## 详情页
组件清单：详情卡片
空状态：找不到物品
加载态：loading 动画
## 设置页
组件清单：设置项列表
空状态：无设置
错误态：保存失败重试
FIXTURE
  _assert_empty     "L2 全覆盖" "$(sg_spec_page_specs "$ui_spec_full" "$ui_project")"
  ROOT="$ROOT_BACKUP"

  echo "=== sg_spec_prd_challenge ==="
  _assert_empty     "有视角+缺口+标注"  "$(sg_spec_prd_challenge "$good_spec")"
  _assert_not_empty "无PRD挑战章节"     "$(sg_spec_prd_challenge "$no_fi_spec")"
  _assert_not_empty "无PRD挑战章节2"    "$(sg_spec_prd_challenge "$good_fi_spec")"

  # fixture: PRD 挑战只有 2 个视角（不够 3 个）
  local few_lens="$tmpdir/few-lens.md"
  cat > "$few_lens" <<'FIXTURE'
# Spec
## PRD 挑战
### 状态完整性
1. 缺口一 — 补入 spec
### 边界条件
2. 缺口二 — deferred
FIXTURE
  _assert_contains  "仅覆盖 2"        "$(sg_spec_prd_challenge "$few_lens")" "仅覆盖 2"

  # fixture: 有视角但无缺口条目
  local no_gaps="$tmpdir/no-gaps.md"
  cat > "$no_gaps" <<'FIXTURE'
# Spec
## PRD 挑战
### 状态完整性
### 边界条件
### 多角色一致性
FIXTURE
  _assert_contains  "无具体缺口"      "$(sg_spec_prd_challenge "$no_gaps")" "无具体缺口"

  # fixture: 有缺口但无处置标注
  local no_annot="$tmpdir/no-annot.md"
  cat > "$no_annot" <<'FIXTURE'
# Spec
## PRD 挑战
### 状态完整性
1. 取消后能否重新报名
### 边界条件
2. 0 人报名时显示什么
### 时序敏感
3. 超时重试是否重复
FIXTURE
  _assert_contains  "无处置标注"      "$(sg_spec_prd_challenge "$no_annot")" "无处置标注"

  # fixture: 有"补入 spec"但全文无 TASK/ACCEPT 承接
  local adopt_no_task="$tmpdir/adopt-no-task.md"
  cat > "$adopt_no_task" <<'FIXTURE'
# Spec
## PRD 挑战
### 状态完整性
- 缺口 G-1：取消后能否重新报名 — **补入 spec**
### 边界条件
- 缺口 G-2：0 人时显示什么 — **补入 spec**
### 多角色一致性
- 缺口 G-3：管理员和用户看到的不同 — **deferred**
FIXTURE
  _assert_contains  "无TASK承接"      "$(sg_spec_prd_challenge "$adopt_no_task")" "无 TASK/ACCEPT 承接"

  # fixture: 视角有标题但无缺口
  local empty_lens="$tmpdir/empty-lens.md"
  cat > "$empty_lens" <<'FIXTURE'
# Spec
## PRD 挑战
### 状态完整性
- 缺口 G-1：取消后能否重新报名 — **补入 spec**
### 边界条件
这个视角没什么问题
### 多角色一致性
也没什么问题
FIXTURE
  _assert_contains  "空挂标题"        "$(sg_spec_prd_challenge "$empty_lens")" "无具体缺口"

  echo "=== sg_spec_critical_modules ==="
  # good_spec 没有核心难点章节也没有声明，应该报错
  _assert_not_empty "无难点章节"      "$(sg_spec_critical_modules "$good_spec")"

  # fixture: 显式声明无核心难点
  local no_critical="$tmpdir/no-critical.md"
  cat > "$no_critical" <<'FIXTURE'
# Spec
无核心难点
FIXTURE
  _assert_empty     "声明无难点"      "$(sg_spec_critical_modules "$no_critical")"

  # fixture: 有 CRITICAL 标记 + 方案表格
  local has_critical="$tmpdir/has-critical.md"
  cat > "$has_critical" <<'FIXTURE'
# Spec
## 核心难点
### [CRITICAL] 库存扣减：并发安全的库存操作
| 方案 | 描述 | 优势 | 劣势 |
|------|------|------|------|
| A 乐观锁 | CAS 重试 | 无锁竞争 | 高并发下重试多 |
| B 悲观锁 | SELECT FOR UPDATE | 简单可靠 | 吞吐受限 |
最小验证：10 协程并发抢 1 库存
失败信号：超卖数 > 0
回退方案：切换悲观锁
FIXTURE
  _assert_empty     "有CRITICAL+方案+验证" "$(sg_spec_critical_modules "$has_critical")"

  # fixture: 有 CRITICAL 但无方案表格
  local critical_no_plan="$tmpdir/critical-no-plan.md"
  cat > "$critical_no_plan" <<'FIXTURE'
# Spec
## 核心难点
### [CRITICAL] 库存扣减
用乐观锁实现
FIXTURE
  _assert_contains  "方案不足"        "$(sg_spec_critical_modules "$critical_no_plan")" "方案选择不足"

  # fixture: 有方案表格但无验证策略
  local critical_no_verify="$tmpdir/critical-no-verify.md"
  cat > "$critical_no_verify" <<'FIXTURE'
# Spec
## 核心难点
### [CRITICAL] 库存扣减
| 方案 | 描述 | 优势 | 劣势 |
|------|------|------|------|
| A 乐观锁 | CAS 重试 | 无锁竞争 | 高并发下重试多 |
| B 悲观锁 | SELECT FOR UPDATE | 简单可靠 | 吞吐受限 |
FIXTURE
  _assert_contains  "验证策略不完整" "$(sg_spec_critical_modules "$critical_no_verify")" "验证策略不完整"

  echo "=== sg_spec_failure_imagination ==="
  _assert_empty     "有维度+条目"    "$(sg_spec_failure_imagination "$good_spec")"
  _assert_not_empty "无故障章节"     "$(sg_spec_failure_imagination "$no_fi_spec")"
  _assert_contains  "缺维度"         "$(sg_spec_failure_imagination "$no_dim_fi_spec")" "维度"
  _assert_empty     "正文提及不误判"  "$(sg_spec_failure_imagination "$fi_body_mention_spec")"

  echo "=== sg_spec_fi_has_subjects ==="
  _assert_empty     "有主语的故障"   "$(sg_spec_fi_has_subjects "$good_fi_spec")"
  _assert_not_empty "无主语的故障"   "$(sg_spec_fi_has_subjects "$no_subject_spec")"
  _assert_contains  "主语比例"       "$(sg_spec_fi_has_subjects "$no_subject_spec")" "主语"

  echo "=== sg_spec_fi_no_duplicates ==="
  _assert_empty     "独立描述"       "$(sg_spec_fi_no_duplicates "$good_fi_spec")"
  _assert_not_empty "套话检测"       "$(sg_spec_fi_no_duplicates "$dup_fi_spec")"
  _assert_contains  "套话提示"       "$(sg_spec_fi_no_duplicates "$dup_fi_spec")" "套话"

  echo "=== sg_spec_fi_cross_check ==="
  _assert_empty     "有对账标注"     "$(sg_spec_fi_cross_check "$good_fi_spec")"
  _assert_not_empty "无对账标注"     "$(sg_spec_fi_cross_check "$no_subject_spec")"

  # fixture: 对账标注引用了不存在的故障编号
  local phantom_ref="$tmpdir/phantom-ref.md"
  cat > "$phantom_ref" <<'FIXTURE'
# Spec
## 故障想象力
故障主体：用户
故障时机：操作中
1. 用户看到错误页面
2. 用户数据丢失
ACCEPT: 防 故障#1
ACCEPT: 防 故障#2
ACCEPT: 防 故障#99
FIXTURE
  _assert_contains  "幽灵引用"       "$(sg_spec_fi_cross_check "$phantom_ref")" "#99"

  echo "=== sg_spec_coverage_gaps ==="
  _assert_empty     "全覆盖"       "$(sg_spec_coverage_gaps "$full_coverage_spec")"
  _assert_not_empty "部分覆盖"     "$(sg_spec_coverage_gaps "$good_fi_spec")"
  _assert_contains  "缺失编号"     "$(sg_spec_coverage_gaps "$good_fi_spec")" "#3"

  echo "=== sg_spec_external_coverage ==="
  # fixture: 有 SOURCE 但无覆盖章节
  local ext_no_chapter="$tmpdir/ext-no-chapter.md"
  cat > "$ext_no_chapter" <<'FIXTURE'
# Spec
SOURCE: 流程图 — PRD — 用户提供
## 故障想象力
1. a
2. b
3. c
4. d
5. e
FIXTURE
  _assert_not_empty "有SOURCE无章节" "$(sg_spec_external_coverage "$ext_no_chapter")"

  # fixture: 有覆盖章节且全标注
  local ext_complete="$tmpdir/ext-complete.md"
  cat > "$ext_complete" <<'FIXTURE'
# Spec
SOURCE: 流程图 — PRD — 用户提供
## 外部文档覆盖
| S-001 | 流程图#1 | 审批 | TASK-1 | covered |
| S-002 | 流程图#2 | 退款 | — | deferred |
FIXTURE
  _assert_empty "全标注" "$(sg_spec_external_coverage "$ext_complete")"

  # fixture: 有覆盖章节但有未标注
  local ext_gap="$tmpdir/ext-gap.md"
  cat > "$ext_gap" <<'FIXTURE'
# Spec
SOURCE: 流程图 — PRD — 用户提供
## 外部文档覆盖
| S-001 | 流程图#1 | 审批 | TASK-1 | covered |
| S-002 | 流程图#2 | 退款 | — | |
FIXTURE
  _assert_not_empty "有未标注" "$(sg_spec_external_coverage "$ext_gap")"

  # fixture: 无 SOURCE → 跳过
  _assert_empty "无SOURCE跳过" "$(sg_spec_external_coverage "$good_spec")"

  # === sg_spec_frozen_delta: API 路径单复数一致 ===
  echo "=== sg_spec_frozen_delta ==="
  local fd_none="$tmpdir/fd_none.md" fd_ok="$tmpdir/fd_ok.md" fd_bad="$tmpdir/fd_bad.md"
  cat > "$fd_none" <<'EOF'
# spec
纯文字，无 API 路径。
EOF
  cat > "$fd_ok" <<'EOF'
# spec
GET /api/items
POST /api/items
GET /api/users
EOF
  cat > "$fd_bad" <<'EOF'
# spec
GET /api/item 返回单个
GET /api/items 返回列表
POST /api/item 创建单个
EOF
  _assert_empty     "无 API 静默"      "$(sg_spec_frozen_delta "$fd_none")"
  _assert_empty     "单复数不冲突静默"  "$(sg_spec_frozen_delta "$fd_ok")"
  _assert_contains  "单复数冲突触发"    "$(sg_spec_frozen_delta "$fd_bad")" "单复数"

  # === sg_spec_bug_phase: bug 关键词触发 Bug 定性前置 ===
  echo "=== sg_spec_bug_phase ==="
  local bp_none="$tmpdir/bp_none.md" bp_bug_no_phase="$tmpdir/bp_bug_no_phase.md" bp_bug_phased="$tmpdir/bp_bug_phased.md"
  cat > "$bp_none" <<'EOF'
# spec
新功能设计。没有 bug 关键词。
EOF
  cat > "$bp_bug_no_phase" <<'EOF'
# spec
## 修复
worker 漏写数据，始终写 0。未实现预期逻辑。
EOF
  cat > "$bp_bug_phased" <<'EOF'
# spec
## 修复
worker 漏写数据，始终写 0。
已过 Bug 定性前置：层级=逻辑，影响 2 文件，走小任务。
EOF
  _assert_empty     "无 bug 静默"           "$(sg_spec_bug_phase "$bp_none")"
  _assert_contains  "bug 无定性触发"         "$(sg_spec_bug_phase "$bp_bug_no_phase")" "Bug 定性"
  _assert_empty     "bug 已定性静默"         "$(sg_spec_bug_phase "$bp_bug_phased")"

  # === sg_task_accept_source: ACCEPT 数值溯源 ===
  echo "=== sg_task_accept_source ==="
  local as_none="$tmpdir/as_none.md" as_ok="$tmpdir/as_ok.md" as_bad="$tmpdir/as_bad.md" as_tbd="$tmpdir/as_tbd.md"
  cat > "$as_none" <<'EOF'
# spec
无 TASK。
EOF
  cat > "$as_ok" <<'EOF'
# spec
TASK: T1 校准阈值
ACCEPT: Given 输入 When 匹配 Then θ_match = 0.72
FILES: src/a.py (新增)
IMPACT: 无
SOURCE: §5.2 校准实验, FROZEN:theta_match
SMOKE: pytest tests/test_a.py
BOUNDARY: 不改 API
COVERAGE: 覆盖核心路径
HUMAN: 无
DEP: 无
EOF
  cat > "$as_bad" <<'EOF'
# spec
TASK: T1 校准阈值
ACCEPT: Given 输入 When 匹配 Then θ_match = 0.72, 延迟 <500ms
FILES: src/a.py (新增)
IMPACT: 无
SMOKE: pytest
BOUNDARY: 无
COVERAGE: 无
HUMAN: 无
DEP: 无
EOF
  cat > "$as_tbd" <<'EOF'
# spec
TASK: T1 校准阈值
ACCEPT: Given 输入 When 匹配 Then θ_match = 0.72
FILES: src/a.py (新增)
IMPACT: 无
SOURCE: TBD
SMOKE: pytest
BOUNDARY: 无
COVERAGE: 无
HUMAN: 无
DEP: 无
EOF
  _assert_empty     "无 TASK 静默"             "$(sg_task_accept_source "$as_none")"
  _assert_empty     "有 SOURCE 静默"           "$(sg_task_accept_source "$as_ok")"
  _assert_contains  "缺 SOURCE 触发"           "$(sg_task_accept_source "$as_bad")" "SOURCE"
  _assert_contains  "裸 TBD 触发"              "$(sg_task_accept_source "$as_tbd")" "TBD"

  echo "=== sg_status_has_phase ==="
  _assert_empty     "有 PHASE"       "$(sg_status_has_phase "$good_status")"
  _assert_not_empty "无 PHASE"       "$(sg_status_has_phase "$empty_status")"

  echo "=== sg_status_has_abandoned ==="
  _assert_empty     "stabilizing 有放弃章节" "$(sg_status_has_abandoned "$stab_status" "stabilizing")"
  _assert_not_empty "stabilizing 无放弃章节" "$(sg_status_has_abandoned "$stab_no_abandoned" "stabilizing")"
  _assert_empty     "building 不要求"        "$(sg_status_has_abandoned "$good_status" "building")"

  echo "=== sg_spec_coverage_contract ==="
  _assert_empty     "有覆盖契约"  "$(sg_spec_coverage_contract "$good_spec")"
  _assert_not_empty "英文别名"    "$(sg_spec_coverage_contract "$tmpdir/nope.md")"

  echo "=== sg_spec_task_template ==="
  _assert_empty     "完整 TASK"       "$(sg_spec_task_template "$good_spec")"
  _assert_not_empty "TASK 多于 ACCEPT" "$(sg_spec_task_template "$bad_task_spec")"
  _assert_contains  "缺 ACCEPT"       "$(sg_spec_task_template "$bad_task_spec")" "ACCEPT"

  echo "=== sg_status_file_exists ==="
  _assert_empty     "存在"   "$(sg_status_file_exists "$good_status")"
  _assert_not_empty "不存在" "$(sg_status_file_exists "$tmpdir/nope.md")"

  echo "=== sg_impl_has_done_tasks ==="
  _assert_empty     "有完成任务" "$(sg_impl_has_done_tasks "$good_status")"
  _assert_not_empty "无完成任务" "$(sg_impl_has_done_tasks "$empty_status")"
  _assert_not_empty "文件不存在" "$(sg_impl_has_done_tasks "$tmpdir/nope.md")"

  # --- sg_impl_agent_invocations ---
  # --- sg_spec_preflight_section & sg_spec_preflight_mapped ---
  echo "=== sg_spec_preflight_section ==="
  local pf_good="$tmpdir/pf_good.md" pf_missing="$tmpdir/pf_missing.md" pf_empty="$tmpdir/pf_empty.md" pf_none="$tmpdir/pf_none.md"
  cat > "$pf_good" <<'EOF'
# spec

## 前置人工动作清单

### A. 环境工具
- [ ] A1: brew install ffmpeg
### B. 凭证
- [ ] B1: HF Token

## 其他
EOF
  cat > "$pf_missing" <<'EOF'
# spec
## 其他章节
EOF
  cat > "$pf_empty" <<'EOF'
# spec
## 前置人工动作清单

### A. 环境工具

## 其他
EOF
  cat > "$pf_none" <<'EOF'
# spec
## 前置人工动作清单

无前置人工动作（纯文档项目）

## 其他
EOF
  _assert_empty     "前置清单完整" "$(sg_spec_preflight_section "$pf_good")"
  _assert_contains  "缺章节"       "$(sg_spec_preflight_section "$pf_missing")" "前置人工动作清单"
  _assert_contains  "章节空"       "$(sg_spec_preflight_section "$pf_empty")" "空"
  _assert_empty     "显式无"       "$(sg_spec_preflight_section "$pf_none")"

  echo "=== sg_spec_preflight_mapped ==="
  local pf_mapped="$tmpdir/pf_mapped.md" pf_unmapped="$tmpdir/pf_unmapped.md"
  cat > "$pf_mapped" <<'EOF'
## 前置人工动作清单
- [ ] A1: ffmpeg
- [ ] B1: HF Token

## 任务
TASK: T3
HUMAN: action:A1, action:B1
EOF
  cat > "$pf_unmapped" <<'EOF'
## 前置人工动作清单
- [ ] A1: ffmpeg

## 任务
TASK: T3
HUMAN: action:A1, action:B9
EOF
  _assert_empty    "引用全部映射"   "$(sg_spec_preflight_mapped "$pf_mapped")"
  _assert_contains "引用缺失条目"   "$(sg_spec_preflight_mapped "$pf_unmapped")" "B9"

  echo "=== sg_spec_task_human_complete ==="
  local th_good="$tmpdir/th_good.md" th_bad="$tmpdir/th_bad.md" th_escape="$tmpdir/th_escape.md" th_clean="$tmpdir/th_clean.md"
  # 合法: 命中触发词 + 声明 action
  cat > "$th_good" <<'EOF'
# spec
```
TASK: 写 bootstrap.sh，执行 brew install ffmpeg 和 huggingface-cli login
ACCEPT: bootstrap 跑通
HUMAN: action:A1, action:B1
```
EOF
  # 违规: 命中触发词但 HUMAN:无
  cat > "$th_bad" <<'EOF'
# spec
```
TASK: 写 bootstrap.sh，检查 HF_TOKEN，调 huggingface-cli login
ACCEPT: bootstrap 跑通
HUMAN: 无
```
EOF
  # 逃生舱: HUMAN:无(AI 自动化:理由)
  cat > "$th_escape" <<'EOF'
# spec
```
TASK: 执行 brew install ffmpeg 的 CI 步骤 (AI runner 有 sudo)
ACCEPT: CI 绿
HUMAN: 无(AI 自动化: GitHub runner 预装 brew 无需人介入)
```
EOF
  # 干净: 无触发词
  cat > "$th_clean" <<'EOF'
# spec
```
TASK: 纯业务逻辑，计算价格
ACCEPT: 单测绿
HUMAN: 无
```
EOF
  _assert_empty    "命中+声明 action"       "$(sg_spec_task_human_complete "$th_good")"
  _assert_contains "命中但 HUMAN:无 应阻塞" "$(sg_spec_task_human_complete "$th_bad")" "HUMAN"
  _assert_empty    "逃生舱放行"             "$(sg_spec_task_human_complete "$th_escape")"
  _assert_empty    "无触发词 HUMAN:无 放行" "$(sg_spec_task_human_complete "$th_clean")"

  echo "=== sg_impl_agent_invocations ==="
  local impl_root="$tmpdir/impl_root"
  mkdir -p "$impl_root/.claude/state"

  # 1. 文件不存在 → 跳过 (单任务路径)
  rm -f "$impl_root/.claude/state/impl-batch.json"
  _assert_empty "无 impl-batch.json 跳过" "$(sg_impl_agent_invocations "$impl_root")"

  # 2. 合法并发批次
  cat > "$impl_root/.claude/state/impl-batch.json" <<'EOF'
{
  "epoch": 1718280000,
  "tasks": ["TASK-3", "TASK-4", "TASK-5"],
  "agent_invocations": [
    {"task_id": "TASK-3", "tool_use_id": "toolu_01a", "launched_at": "2026-04-22T15:00:10Z"},
    {"task_id": "TASK-4", "tool_use_id": "toolu_01b", "launched_at": "2026-04-22T15:00:12Z"},
    {"task_id": "TASK-5", "tool_use_id": "toolu_01c", "launched_at": "2026-04-22T15:00:14Z"}
  ],
  "parallel_reason": "FILES 无交集"
}
EOF
  _assert_empty "合法并发批次" "$(sg_impl_agent_invocations "$impl_root")"

  # 3. tasks < 2 (单任务不应写此文件)
  cat > "$impl_root/.claude/state/impl-batch.json" <<'EOF'
{"tasks":["TASK-1"],"agent_invocations":[{"task_id":"TASK-1","tool_use_id":"x","launched_at":"2026-04-22T15:00:00Z"}]}
EOF
  _assert_contains "单任务批次告警" "$(sg_impl_agent_invocations "$impl_root")" "单任务"

  # 4. 数量不匹配
  cat > "$impl_root/.claude/state/impl-batch.json" <<'EOF'
{"tasks":["TASK-1","TASK-2","TASK-3"],"agent_invocations":[{"task_id":"TASK-1","tool_use_id":"x","launched_at":"2026-04-22T15:00:00Z"}]}
EOF
  _assert_contains "数量不匹配自扮演" "$(sg_impl_agent_invocations "$impl_root")" "自扮演"

  # 5. 串行调用 (时间跨度 > 60s)
  cat > "$impl_root/.claude/state/impl-batch.json" <<'EOF'
{
  "tasks": ["TASK-1", "TASK-2"],
  "agent_invocations": [
    {"task_id": "TASK-1", "tool_use_id": "a", "launched_at": "2026-04-22T15:00:00Z"},
    {"task_id": "TASK-2", "tool_use_id": "b", "launched_at": "2026-04-22T15:10:00Z"}
  ]
}
EOF
  _assert_contains "串行跨度告警" "$(sg_impl_agent_invocations "$impl_root")" "串行"

  # 6. 缺字段
  cat > "$impl_root/.claude/state/impl-batch.json" <<'EOF'
{
  "tasks": ["TASK-1", "TASK-2"],
  "agent_invocations": [
    {"task_id": "TASK-1", "tool_use_id": "", "launched_at": "2026-04-22T15:00:00Z"},
    {"task_id": "TASK-2", "tool_use_id": "b", "launched_at": "2026-04-22T15:00:05Z"}
  ]
}
EOF
  _assert_contains "缺 tool_use_id" "$(sg_impl_agent_invocations "$impl_root")" "tool_use_id"

  # === sg_impl_batch_grace_active: 并行 subagent 宽限期 ===
  echo "=== sg_impl_batch_grace_active ==="
  local now_epoch stale_epoch
  now_epoch=$(date +%s)
  stale_epoch=$((now_epoch - 2000))  # 超 30min

  # 1. 无 impl-batch.json → 非宽限
  rm -f "$impl_root/.claude/state/impl-batch.json"
  _assert_empty "无 batch 非宽限" "$(sg_impl_batch_grace_active "$impl_root")"

  # 2. 合法并行 + 新鲜 epoch → 宽限激活
  cat > "$impl_root/.claude/state/impl-batch.json" <<EOF
{
  "epoch": ${now_epoch},
  "tasks": ["T1","T2"],
  "agent_invocations": [
    {"task_id":"T1","tool_use_id":"a","launched_at":"2026-04-23T17:00:00Z"},
    {"task_id":"T2","tool_use_id":"b","launched_at":"2026-04-23T17:00:01Z"}
  ],
  "no_commit_in_subagent": true
}
EOF
  _assert_contains "新鲜并行批次激活宽限" "$(sg_impl_batch_grace_active "$impl_root")" "1"

  # 3. no_commit_in_subagent=false → 不激活
  cat > "$impl_root/.claude/state/impl-batch.json" <<EOF
{
  "epoch": ${now_epoch},
  "tasks": ["T1","T2"],
  "agent_invocations": [
    {"task_id":"T1","tool_use_id":"a","launched_at":"2026-04-23T17:00:00Z"},
    {"task_id":"T2","tool_use_id":"b","launched_at":"2026-04-23T17:00:01Z"}
  ],
  "no_commit_in_subagent": false
}
EOF
  _assert_empty "未声明 no_commit 非宽限" "$(sg_impl_batch_grace_active "$impl_root")"

  # 4. 超 30min → 宽限失效
  cat > "$impl_root/.claude/state/impl-batch.json" <<EOF
{
  "epoch": ${stale_epoch},
  "tasks": ["T1","T2"],
  "agent_invocations": [
    {"task_id":"T1","tool_use_id":"a","launched_at":"2026-04-23T17:00:00Z"},
    {"task_id":"T2","tool_use_id":"b","launched_at":"2026-04-23T17:00:01Z"}
  ],
  "no_commit_in_subagent": true
}
EOF
  _assert_empty "超 30min 宽限失效" "$(sg_impl_batch_grace_active "$impl_root")"

  # 5. 单任务 → 不认宽限 (防伪造)
  cat > "$impl_root/.claude/state/impl-batch.json" <<EOF
{
  "epoch": ${now_epoch},
  "tasks": ["T1"],
  "agent_invocations": [
    {"task_id":"T1","tool_use_id":"a","launched_at":"2026-04-23T17:00:00Z"}
  ],
  "no_commit_in_subagent": true
}
EOF
  _assert_empty "单任务不认宽限" "$(sg_impl_batch_grace_active "$impl_root")"

  # 6. invocations 数不匹配 (自扮演嫌疑) → 不认宽限
  cat > "$impl_root/.claude/state/impl-batch.json" <<EOF
{
  "epoch": ${now_epoch},
  "tasks": ["T1","T2","T3"],
  "agent_invocations": [
    {"task_id":"T1","tool_use_id":"a","launched_at":"2026-04-23T17:00:00Z"}
  ],
  "no_commit_in_subagent": true
}
EOF
  _assert_empty "invocations 不匹配非宽限" "$(sg_impl_batch_grace_active "$impl_root")"

  # 清理 batch 文件避免影响后续测试
  rm -f "$impl_root/.claude/state/impl-batch.json"

  echo "=== sg_json_field ==="
  _assert_empty     "字段存在"   "$(sg_json_field "$good_check" "result" "check-report.json")"
  _assert_not_empty "字段缺失"   "$(sg_json_field "$bad_check" "result" "check-report.json")"
  _assert_not_empty "文件不存在" "$(sg_json_field "$tmpdir/nope.json" "result" "nope.json")"

  echo "=== sg_release_decision_valid ==="
  _assert_empty     "合法 decision" "$(sg_release_decision_valid "$good_release")"
  _assert_not_empty "非法 decision" "$(sg_release_decision_valid "$bad_release")"
  _assert_contains  "非法值提示"    "$(sg_release_decision_valid "$bad_release")" "yolo"

  # --- fuse 测试 ---
  echo "--- fuse 测试 ---"

  # 保存原始 FUSE_STATE，测试用临时状态文件
  local orig_fuse_state="$FUSE_STATE"
  FUSE_STATE="$tmpdir/fuse-state.json"

  # 测试 1: 初始状态为 none
  _fuse_reset > /dev/null 2>&1
  local fuse_level
  fuse_level=$(jq -r '.level' "$FUSE_STATE" 2>/dev/null)
  _assert_contains "fuse 初始 none" "$fuse_level" "none"

  # 测试 2: 2 次 gate-fail 不触发熔断
  _fuse_reset > /dev/null 2>&1
  _fuse_check gate-fail "task-test-1" 2>/dev/null || true
  _fuse_check gate-fail "task-test-1" 2>/dev/null || true
  fuse_level=$(jq -r '.level' "$FUSE_STATE" 2>/dev/null)
  _assert_contains "2次未熔断" "$fuse_level" "none"

  # 测试 3: 3 次 gate-fail 触发软熔断
  _fuse_reset > /dev/null 2>&1
  _fuse_check gate-fail "t1" 2>/dev/null || true
  _fuse_check gate-fail "t1" 2>/dev/null || true
  local fuse_exit=0
  _fuse_check gate-fail "t1" 2>/dev/null || fuse_exit=$?
  total=$((total + 1))
  if [[ "$fuse_exit" -eq 10 ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL [3次gate-fail→软熔断]: expected exit 10, got $fuse_exit"
  fi

  # 测试 4: 软熔断后 gate 计数器重置，再 3 次触发第二次软熔断 → 升级硬熔断
  fuse_exit=0
  _fuse_check gate-fail "t2" 2>/dev/null || true
  _fuse_check gate-fail "t2" 2>/dev/null || true
  _fuse_check gate-fail "t2" 2>/dev/null || fuse_exit=$?
  total=$((total + 1))
  if [[ "$fuse_exit" -eq 20 ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL [连续软熔断→硬熔断]: expected exit 20, got $fuse_exit"
  fi

  # 测试 5: 硬熔断后继续 check 仍返回 20
  fuse_exit=0
  _fuse_check gate-fail "t3" 2>/dev/null || fuse_exit=$?
  total=$((total + 1))
  if [[ "$fuse_exit" -eq 20 ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL [硬熔断维持]: expected exit 20, got $fuse_exit"
  fi

  # 测试 6: 完全重置后回到 none
  _fuse_reset > /dev/null 2>&1
  fuse_level=$(jq -r '.level' "$FUSE_STATE" 2>/dev/null)
  _assert_contains "完全重置→none" "$fuse_level" "none"

  # 测试 7: 软重置清除 gate 计数
  _fuse_check gate-fail "t4" 2>/dev/null || true
  _fuse_check gate-fail "t4" 2>/dev/null || true
  local gate_before
  gate_before=$(jq -r '.consecutive_gate_failures' "$FUSE_STATE" 2>/dev/null)
  _fuse_reset --soft > /dev/null 2>&1
  local gate_after
  gate_after=$(jq -r '.consecutive_gate_failures' "$FUSE_STATE" 2>/dev/null)
  total=$((total + 1))
  if [[ "$gate_before" == "2" && "$gate_after" == "0" ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL [软重置清gate计数]: before=$gate_before after=$gate_after"
  fi

  # 测试 8: file-churn 信号触发软熔断
  _fuse_reset > /dev/null 2>&1
  fuse_exit=0
  _fuse_check file-churn "src/main.ts:6" 2>/dev/null || fuse_exit=$?
  total=$((total + 1))
  if [[ "$fuse_exit" -eq 10 ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL [file-churn→软熔断]: expected exit 10, got $fuse_exit"
  fi

  # 测试 9: fused_tasks 记录
  _fuse_reset > /dev/null 2>&1
  _fuse_check gate-fail "my-task" 2>/dev/null || true
  _fuse_check gate-fail "my-task" 2>/dev/null || true
  _fuse_check gate-fail "my-task" 2>/dev/null || true
  local fused_list
  fused_list=$(jq -r '.fused_tasks | join(",")' "$FUSE_STATE" 2>/dev/null)
  _assert_contains "fused_tasks记录" "$fused_list" "my-task"

  # 恢复
  FUSE_STATE="$orig_fuse_state"

  # --- Step 3 多视角审查产物测试 ---
  echo "--- step3 测试 ---"
  local step3_root="$tmpdir/step3-project"
  mkdir -p "$step3_root/docs" "$step3_root/.claude/state/step3"
  # spec 含多视角审查章节 + 有技术关键词（whisper）
  cat > "$step3_root/docs/spec.md" <<'SPEC'
# Spec
## 多视角审查结果
存在
TASK: T10 任务十
ACCEPT: Given X When Y Then Z
FILES: a.ts
实现用 whisper 模型跑 ASR
SPEC

  # 测试: 触发判定
  echo "=== sg_step3_triggered ==="
  _assert_contains "审查章节触发" "$(sg_step3_triggered "$step3_root/docs/spec.md")" "1"

  # 测试: 产物缺失
  echo "=== sg_step3_file_exists ==="
  rm -rf "$step3_root/.claude/state/step3"
  _assert_not_empty "无产物目录" "$(sg_step3_file_exists "$step3_root")"
  _assert_contains "LARP 提示" "$(sg_step3_file_exists "$step3_root")" "LARP"

  # 测试: 合法 round JSON
  mkdir -p "$step3_root/.claude/state/step3"
  cat > "$step3_root/.claude/state/step3/round-1.json" <<'J'
{"round":1,"roles":["需求审查员","证据审查员","范围审查员","技术可行性审查员"],"agent_invocations":[{"role":"需求审查员","subagent_type":"general-purpose","tool_use_id":"t1","launched_at":"2026-04-22T14:58:12Z"},{"role":"证据审查员","subagent_type":"general-purpose","tool_use_id":"t2","launched_at":"2026-04-22T14:58:14Z"},{"role":"范围审查员","subagent_type":"general-purpose","tool_use_id":"t3","launched_at":"2026-04-22T14:58:15Z"},{"role":"技术可行性审查员","subagent_type":"general-purpose","tool_use_id":"t4","launched_at":"2026-04-22T14:58:16Z"}],"dissents":[{"id":"P0-1","role":"需求","severity":"P0","issue":"X","evidence":"Y","suggestion":"Z","impact":"W","absorbed_as":"T10"}],"no_dissent":[{"role":"证据","verification":"grep T10 命中"}],"anti_cheat":{}}
J
  _assert_empty "合法 JSON" "$(sg_step3_json_valid "$step3_root")"
  _assert_empty "角色齐" "$(sg_step3_roles_complete "$step3_root")"
  _assert_empty "三要素齐" "$(sg_step3_three_elements "$step3_root")"
  _assert_empty "verification 非空" "$(sg_step3_verification_nonempty "$step3_root")"
  _assert_empty "absorbed_as 真实 (T10 在 spec)" "$(sg_step3_absorbed_as_valid "$step3_root" "$step3_root/docs/spec.md")"
  _assert_empty "上下文角色齐 (whisper 要求技术可行性，已有)" "$(sg_step3_roles_for_context "$step3_root/docs/spec.md" "$step3_root")"
  _assert_empty "agent_invocations 合法并发" "$(sg_step3_agent_invocations "$step3_root")"

  # 测试: agent_invocations 缺字段
  echo "=== sg_step3_agent_invocations (negative) ==="
  cat > "$step3_root/.claude/state/step3/round-1.json" <<'J'
{"round":1,"roles":["需求审查员","证据审查员","范围审查员"],"dissents":[],"no_dissent":[]}
J
  _assert_contains "缺 agent_invocations 字段" "$(sg_step3_agent_invocations "$step3_root")" "自扮演"

  # 测试: agent_invocations 数量不匹配
  cat > "$step3_root/.claude/state/step3/round-1.json" <<'J'
{"round":1,"roles":["需求审查员","证据审查员","范围审查员"],"agent_invocations":[{"role":"需求","subagent_type":"general-purpose","tool_use_id":"t1","launched_at":"2026-04-22T14:58:12Z"}],"dissents":[],"no_dissent":[]}
J
  _assert_contains "数量不匹配" "$(sg_step3_agent_invocations "$step3_root")" "不匹配"

  # 测试: agent_invocations 串行（时间跨度 > 60s）
  cat > "$step3_root/.claude/state/step3/round-1.json" <<'J'
{"round":1,"roles":["需求审查员","证据审查员","范围审查员"],"agent_invocations":[{"role":"需求","subagent_type":"general-purpose","tool_use_id":"t1","launched_at":"2026-04-22T14:58:12Z"},{"role":"证据","subagent_type":"general-purpose","tool_use_id":"t2","launched_at":"2026-04-22T15:05:00Z"},{"role":"范围","subagent_type":"general-purpose","tool_use_id":"t3","launched_at":"2026-04-22T15:10:00Z"}],"dissents":[],"no_dissent":[]}
J
  _assert_contains "串行调用触发" "$(sg_step3_agent_invocations "$step3_root")" "串行"

  # 测试: 三必选角色缺失
  echo "=== sg_step3_roles_complete (negative) ==="
  cat > "$step3_root/.claude/state/step3/round-1.json" <<'J'
{"round":1,"roles":["需求审查员","证据审查员"],"dissents":[],"no_dissent":[]}
J
  _assert_not_empty "角色数不足" "$(sg_step3_roles_complete "$step3_root")"

  # 测试: 三要素缺失
  echo "=== sg_step3_three_elements (negative) ==="
  cat > "$step3_root/.claude/state/step3/round-1.json" <<'J'
{"round":1,"roles":["需求审查员","证据审查员","范围审查员"],"dissents":[{"id":"P0-1","severity":"P0","issue":"X","evidence":"","suggestion":"Z","impact":"W"}],"no_dissent":[]}
J
  _assert_contains "空 evidence 触发" "$(sg_step3_three_elements "$step3_root")" "三要素"

  # 测试: 空 verification
  echo "=== sg_step3_verification_nonempty (negative) ==="
  cat > "$step3_root/.claude/state/step3/round-1.json" <<'J'
{"round":1,"roles":["需求审查员","证据审查员","范围审查员"],"dissents":[],"no_dissent":[{"role":"证据","verification":""}]}
J
  _assert_contains "空 verification 触发" "$(sg_step3_verification_nonempty "$step3_root")" "LARP"

  # 测试: absorbed_as 引用伪造（TASK 编号 spec 里没有）
  echo "=== sg_step3_absorbed_as_valid (negative) ==="
  cat > "$step3_root/.claude/state/step3/round-1.json" <<'J'
{"round":1,"roles":["需求审查员","证据审查员","范围审查员"],"dissents":[{"id":"P0-1","severity":"P0","issue":"X","evidence":"Y","suggestion":"Z","impact":"W","absorbed_as":"T99"}],"no_dissent":[]}
J
  _assert_contains "伪造引用触发" "$(sg_step3_absorbed_as_valid "$step3_root" "$step3_root/docs/spec.md")" "找不到"

  # 测试: Round 2 缺差分字段
  echo "=== sg_step3_prior_round_refs (negative) ==="
  cat > "$step3_root/.claude/state/step3/round-1.json" <<'J'
{"round":1,"roles":["需求审查员","证据审查员","范围审查员"],"dissents":[],"no_dissent":[]}
J
  cat > "$step3_root/.claude/state/step3/round-2.json" <<'J'
{"round":2,"roles":["需求审查员","证据审查员","范围审查员"],"dissents":[],"no_dissent":[]}
J
  _assert_contains "无 references_prior_round 触发" "$(sg_step3_prior_round_refs "$step3_root")" "references_prior_round"

  # 测试: prior_p0_strict carry-over (反 RecordToMes Round 4 prior_p0_verified=[])
  echo "=== sg_step3_prior_p0_strict (negative) ==="
  # 场景 1: 前轮有 P0 但本轮 prior_p0_verified 空
  cat > "$step3_root/.claude/state/step3/round-1.json" <<'J'
{"round":1,"roles":["需求审查员","证据审查员","范围审查员"],"dissents":[{"id":"P0-1","severity":"P0","from":"需求审查员","evidence":"e","suggestion":"s","impact":"i"}],"no_dissent":[]}
J
  cat > "$step3_root/.claude/state/step3/round-2.json" <<'J'
{"round":2,"roles":["需求审查员","证据审查员","范围审查员"],"dissents":[],"no_dissent":[],"references_prior_round":["P0-1"],"prior_p0_verified":[]}
J
  # round-2 mtime 需要晚于 round-1
  sleep 1; touch "$step3_root/.claude/state/step3/round-2.json"
  _assert_contains "空 prior_p0_verified 触发" "$(sg_step3_prior_p0_strict "$step3_root")" "carry-over"

  # 场景 2: 有条目但缺三件套
  cat > "$step3_root/.claude/state/step3/round-2.json" <<'J'
{"round":2,"roles":["需求审查员","证据审查员","范围审查员"],"dissents":[],"no_dissent":[],"references_prior_round":["P0-1"],"prior_p0_verified":[{"prior_id":"P0-1"}]}
J
  sleep 1; touch "$step3_root/.claude/state/step3/round-2.json"
  _assert_contains "缺三件套触发" "$(sg_step3_prior_p0_strict "$step3_root")" "三件套"

  # 场景 3: prior_id 造假 (前轮无此编号)
  cat > "$step3_root/.claude/state/step3/round-2.json" <<'J'
{"round":2,"roles":["需求审查员","证据审查员","范围审查员"],"dissents":[],"no_dissent":[],"references_prior_round":["P0-99"],"prior_p0_verified":[{"prior_id":"P0-99","verified_how":"fabricated","new_issues_found":[]}]}
J
  sleep 1; touch "$step3_root/.claude/state/step3/round-2.json"
  _assert_contains "造假 prior_id 触发" "$(sg_step3_prior_p0_strict "$step3_root")" "造假"

  # 场景 4: 合法 carry-over 应静默
  cat > "$step3_root/.claude/state/step3/round-2.json" <<'J'
{"round":2,"roles":["需求审查员","证据审查员","范围审查员"],"dissents":[],"no_dissent":[],"references_prior_round":["P0-1"],"prior_p0_verified":[{"prior_id":"P0-1","verified_how":"spec.md §X now defines Y","new_issues_found":[]}]}
J
  sleep 1; touch "$step3_root/.claude/state/step3/round-2.json"
  _assert_empty "合法 carry-over 静默" "$(sg_step3_prior_p0_strict "$step3_root")"

  # 场景 5: 前轮无 P0 则规则不约束 (静默)
  cat > "$step3_root/.claude/state/step3/round-1.json" <<'J'
{"round":1,"roles":["需求审查员","证据审查员","范围审查员"],"dissents":[],"no_dissent":[]}
J
  cat > "$step3_root/.claude/state/step3/round-2.json" <<'J'
{"round":2,"roles":["需求审查员","证据审查员","范围审查员"],"dissents":[],"no_dissent":[]}
J
  sleep 1; touch "$step3_root/.claude/state/step3/round-2.json"
  _assert_empty "前轮无 P0 静默" "$(sg_step3_prior_p0_strict "$step3_root")"

  # 测试: 上下文角色缺技术可行性
  echo "=== sg_step3_roles_for_context (negative) ==="
  rm -f "$step3_root/.claude/state/step3/round-2.json"
  cat > "$step3_root/.claude/state/step3/round-1.json" <<'J'
{"round":1,"roles":["需求审查员","证据审查员","范围审查员"],"dissents":[],"no_dissent":[]}
J
  _assert_contains "缺技术可行性触发" "$(sg_step3_roles_for_context "$step3_root/docs/spec.md" "$step3_root")" "技术可行性"

  # --- sanity 测试 ---
  echo "--- sanity 测试 ---"

  # fixture: 项目目录模拟
  local sanity_root="$tmpdir/sanity-project"
  mkdir -p "$sanity_root/src" "$sanity_root/.claude/state"

  # 初始化 git 仓库
  git -C "$sanity_root" init -q 2>/dev/null
  git -C "$sanity_root" config user.email "test@test.com" 2>/dev/null
  git -C "$sanity_root" config user.name "test" 2>/dev/null

  # 测试 1: 硬编码地址检测 — 有 localhost
  cat > "$sanity_root/src/config.ts" <<'SRC'
const API_URL = "http://localhost:3000/api";
export default API_URL;
SRC
  git -C "$sanity_root" add -A && git -C "$sanity_root" commit -q -m "init" 2>/dev/null

  echo "=== sg_sanity_hardcoded_addrs ==="
  _assert_not_empty "有硬编码地址" "$(sg_sanity_hardcoded_addrs "$sanity_root")"
  _assert_contains  "地址提示" "$(sg_sanity_hardcoded_addrs "$sanity_root")" "硬编码地址"

  # 测试 2: 硬编码地址检测 — 干净源码
  cat > "$sanity_root/src/config.ts" <<'SRC'
const API_URL = process.env.API_URL;
export default API_URL;
SRC
  git -C "$sanity_root" add -A && git -C "$sanity_root" commit -q -m "fix addr" 2>/dev/null
  _assert_empty "无硬编码地址" "$(sg_sanity_hardcoded_addrs "$sanity_root")"

  # 测试 3: 构建产物新鲜度 — 无 build 目录 → 跳过
  echo "=== sg_sanity_build_freshness ==="
  _assert_empty "无build目录" "$(sg_sanity_build_freshness "$sanity_root")"

  # 测试 4: 构建产物新鲜度 — build 目录里有陈旧文件, 源码 commit 更新
  mkdir -p "$sanity_root/dist"
  echo "old bundle" > "$sanity_root/dist/bundle.js"
  touch -t 202401010000 "$sanity_root/dist/bundle.js" 2>/dev/null || true
  cat > "$sanity_root/src/app.ts" <<'SRC'
console.log("updated");
SRC
  git -C "$sanity_root" add -A && git -C "$sanity_root" commit -q -m "update" 2>/dev/null
  _assert_not_empty "build过期" "$(sg_sanity_build_freshness "$sanity_root")"
  _assert_contains  "过期提示" "$(sg_sanity_build_freshness "$sanity_root")" "过期"

  # 测试 5: 测试证据新鲜度 — 无报告 → 无问题
  echo "=== sg_sanity_test_evidence ==="
  _assert_empty "无测试报告" "$(sg_sanity_test_evidence "$sanity_root")"

  # 测试 6: 测试证据新鲜度 — 报告比 commit 旧
  touch -t 202401010000 "$sanity_root/.claude/state/check-report.json" 2>/dev/null || true
  echo '{"result":"pass"}' > "$sanity_root/.claude/state/check-report.json"
  touch -t 202401010000 "$sanity_root/.claude/state/check-report.json" 2>/dev/null || true
  _assert_not_empty "报告过期" "$(sg_sanity_test_evidence "$sanity_root")"

  # 测试 7: 未验证维度 — 有前端代码
  echo "=== sg_sanity_unverified_dimensions ==="
  cat > "$sanity_root/src/App.tsx" <<'SRC'
export default function App() { return <div>Hello</div>; }
SRC
  git -C "$sanity_root" add -A && git -C "$sanity_root" commit -q -m "add tsx" 2>/dev/null
  _assert_not_empty "前端维度" "$(sg_sanity_unverified_dimensions "$sanity_root")"
  _assert_contains  "视觉" "$(sg_sanity_unverified_dimensions "$sanity_root")" "visual"

  # 清理
  rm -rf "$sanity_root/dist"

  # --- verify gates red team fixtures ---
  # 目的: 挡 touch 空文件 / 造假路径 / 尾缀攻击 / 空 meta 对象 等绕过尝试
  echo "=== sg_verify_fault_coverage ==="
  local vf_root="$tmpdir/vf_root"
  mkdir -p "$vf_root/docs" "$vf_root/.claude/state" "$vf_root/tests/e2e"
  _assert_empty "无 spec 不触发" "$(sg_verify_fault_coverage "$vf_root")"
  cat > "$vf_root/docs/spec.md" <<'EOF'
## 故障想象力
1. 未登录用户看到所有活动都显示已报名
2. 用户报名后刷新页面状态消失
3. 活动满员后第 N+1 个用户仍然报名成功
EOF
  _assert_empty "无 report 不触发" "$(sg_verify_fault_coverage "$vf_root")"
  cat > "$vf_root/.claude/state/verify-report.json" <<'EOF'
{ "decision": "pass" }
EOF
  _assert_contains "缺 fault_coverage 报错" "$(sg_verify_fault_coverage "$vf_root")" "fault_coverage"
  cat > "$vf_root/.claude/state/verify-report.json" <<'EOF'
{
  "decision": "pass",
  "fault_coverage": [
    {"fault_id": 1, "verified_by": "tests/e2e/ghost.spec.ts::fake_case"},
    {"fault_id": 2, "verified_by": "tests/e2e/also_ghost.spec.ts::bar"},
    {"fault_id": 3, "verified_by": "tests/e2e/exist.spec.ts::real_case"}
  ]
}
EOF
  touch "$vf_root/tests/e2e/exist.spec.ts"
  _assert_contains "造假路径被抓" "$(sg_verify_fault_coverage "$vf_root")" "测试文件不存在"
  touch "$vf_root/tests/e2e/ghost.spec.ts" "$vf_root/tests/e2e/also_ghost.spec.ts"
  _assert_empty "全部文件真实存在" "$(sg_verify_fault_coverage "$vf_root" | grep '测试文件不存在')"
  cat > "$vf_root/.claude/state/verify-report.json" <<'EOF'
{
  "decision": "pass",
  "fault_coverage": [
    {"fault_id": 1, "verified_by": "tests/e2e/exist.spec.ts::real_case"}
  ]
}
EOF
  _assert_contains "部分缺失被抓" "$(sg_verify_fault_coverage "$vf_root")" "未承接"

  echo "=== sg_verify_ui_screenshots ==="
  local vs_root="$tmpdir/vs_root"
  mkdir -p "$vs_root/src"
  _assert_empty "非 UI 项目不触发" "$(sg_verify_ui_screenshots "$vs_root")"
  echo 'export const X=1;' > "$vs_root/src/App.tsx"
  git -C "$vs_root" init -q 2>/dev/null && git -C "$vs_root" -c user.email=x@y.z -c user.name=t add -A && git -C "$vs_root" -c user.email=x@y.z -c user.name=t commit -q -m init 2>/dev/null
  _assert_contains "缺截图目录" "$(sg_verify_ui_screenshots "$vs_root")" "缺少截图目录"
  mkdir -p "$vs_root/.claude/state/verify-screenshots"
  _assert_contains "空目录被抓" "$(sg_verify_ui_screenshots "$vs_root")" "截图目录为空"
  touch "$vs_root/.claude/state/verify-screenshots/fake.png"
  _assert_contains "touch 空文件被抓" "$(sg_verify_ui_screenshots "$vs_root")" "无效"
  printf 'x%.0s' {1..2000} > "$vs_root/.claude/state/verify-screenshots/notreally.png"
  rm -f "$vs_root/.claude/state/verify-screenshots/fake.png"
  if command -v file >/dev/null 2>&1; then
    _assert_contains "假 PNG 被抓" "$(sg_verify_ui_screenshots "$vs_root")" "无效"
  fi

  echo "=== sg_verify_project_ownership ==="
  local vo_root="$tmpdir/vo_root"
  mkdir -p "$vo_root/src" "$vo_root/.claude/state"
  _assert_empty "非 UI 不触发" "$(sg_verify_project_ownership "$vo_root")"
  echo 'export const X=1;' > "$vo_root/src/App.tsx"
  _assert_contains "缺 ownership" "$(sg_verify_project_ownership "$vo_root")" "verify-ownership.json"
  echo "not json" > "$vo_root/.claude/state/verify-ownership.json"
  _assert_contains "非法 JSON 被抓" "$(sg_verify_project_ownership "$vo_root")" "合法 JSON"
  echo '{"frontend_meta": {"pid": 1}}' > "$vo_root/.claude/state/verify-ownership.json"
  _assert_contains "缺 project_root" "$(sg_verify_project_ownership "$vo_root")" "project_root"
  cat > "$vo_root/.claude/state/verify-ownership.json" <<EOF
{"project_root": "/tmp/other-project/vo_root", "frontend_meta": {"pid": 1, "cwd": "/tmp/other-project/vo_root/fe"}}
EOF
  _assert_contains "尾缀攻击被抓" "$(sg_verify_project_ownership "$vo_root")" "不匹配"
  cat > "$vo_root/.claude/state/verify-ownership.json" <<EOF
{"project_root": "$vo_root", "frontend_meta": {}, "backend_meta": {}}
EOF
  _assert_contains "空 meta 被抓" "$(sg_verify_project_ownership "$vo_root")" "均为空"
  cat > "$vo_root/.claude/state/verify-ownership.json" <<EOF
{"project_root": "$vo_root", "frontend_meta": {"pid": "", "cwd": ""}, "backend_meta": {"pid": null}}
EOF
  _assert_contains "空串 meta 被抓" "$(sg_verify_project_ownership "$vo_root")" "均为空"
  cat > "$vo_root/.claude/state/verify-ownership.json" <<EOF
{"project_root": "$vo_root", "frontend_meta": {"pid": 123, "cwd": "$vo_root/fe"}, "backend_meta": {}}
EOF
  _assert_empty "正常 ownership 不触发" "$(sg_verify_project_ownership "$vo_root")"

  # --- continue-check politeness patterns ---
  echo "=== cmd_continue_check (politeness patterns) ==="
  local cc_root="$tmpdir/cc_root"
  mkdir -p "$cc_root/docs"
  # status.md 有 pending 任务（必要前置）
  cat > "$cc_root/docs/status.md" <<'EOF'
# status
- [ ] T9 导入 API
- [ ] T10 pipeline
EOF
  # _call helper: echo msg | ROOT=... cmd_continue_check
  _cc_call() {
    local m="$1"
    ROOT="$cc_root" STATUS_FILE="$cc_root/docs/status.md" bash -c "
      source '$SELF'
      ROOT='$cc_root'; STATUS_FILE='$cc_root/docs/status.md'
      echo '$m' | cmd_continue_check 2>&1
    " 2>&1 | grep -v "^$"
  }
  # 因 cmd_continue_check 通过 exit 2 + stderr 输出，这里改用子 shell 捕获
  _cc_fire() {
    local m="$1"
    (cd "$cc_root" && echo "$m" | ROOT="$cc_root" STATUS_FILE="$cc_root/docs/status.md" \
      bash "$SCRIPT_PATH" continue-check 2>&1; echo "EXIT=$?")
  }
  local SCRIPT_PATH="${BASH_SOURCE[0]}"
  _assert_contains "裸继续？ 命中"     "$(_cc_fire '任务 T8 完成。继续？')"      "politeness"
  _assert_contains "要继续吗 命中"     "$(_cc_fire '要继续吗')"                  "politeness"
  _assert_contains "下一个？ 命中"     "$(_cc_fire '做完了。下一个？')"          "politeness"
  _assert_contains "可以开始吗 命中"   "$(_cc_fire '方案 A。可以开始吗？')"      "politeness"
  _assert_contains "哪边 命中"         "$(_cc_fire 'T12 或 T15。哪边？')"        "politeness"
  _assert_contains "先做.还是 命中"    "$(_cc_fire '先做 T12 还是 T15？')"       "politeness"
  _assert_empty    "正常结束不命中"    "$(_cc_fire '任务完成，进入下一个。' | grep politeness)"

  # --- cmd_next_task regression tests ---
  # 回归 Recording bug: pipeline 在 action:XX grep 无匹配时 pipefail 静默杀脚本
  echo "=== cmd_next_task ==="
  local nt_root="$tmpdir/nt_root"
  _nt_fire() {
    local dir="$1"
    (cd "$dir" && ROOT="$dir" STATUS_FILE="$dir/docs/status.md" \
      bash "$SCRIPT_PATH" next-task 2>&1)
  }

  # 场景 1: pending 任务, spec 无 action:XX → 必须输出"下一个：..."
  mkdir -p "$nt_root/docs"
  cat > "$nt_root/docs/status.md" <<'EOF'
# status
PROJECT_PHASE: building
- [ ] T6 做事
- [x] T5 完成
EOF
  cat > "$nt_root/docs/spec.md" <<'EOF'
TASK: T6 做事
ACCEPT: foo
HUMAN: 无
EOF
  _assert_contains "无 action 仍输出下一步" "$(_nt_fire "$nt_root")" "下一个"
  _assert_contains "无 action 禁问要继续" "$(_nt_fire "$nt_root")" "禁止问"

  # 场景 2: pending 任务, spec 有 action:A1 → 必须输出"阻塞在人工动作"
  local nt_root2="$tmpdir/nt_root2"
  mkdir -p "$nt_root2/docs"
  cat > "$nt_root2/docs/status.md" <<'EOF'
# status
PROJECT_PHASE: building
- [ ] T3 装 ffmpeg
EOF
  cat > "$nt_root2/docs/spec.md" <<'EOF'
## 前置人工动作清单
- [ ] A1: brew install ffmpeg

TASK: T3 装 ffmpeg
ACCEPT: ffmpeg -version 可用
HUMAN: action:A1
EOF
  _assert_contains "action 引用触发阻塞提示" "$(_nt_fire "$nt_root2")" "阻塞在人工动作"
  _assert_contains "引用编号回显" "$(_nt_fire "$nt_root2")" "A1"

  # 场景 3: 全部任务完成 → 输出"所有任务已完成"
  local nt_root3="$tmpdir/nt_root3"
  mkdir -p "$nt_root3/docs"
  cat > "$nt_root3/docs/status.md" <<'EOF'
# status
- [x] T1
- [x] T2
EOF
  _assert_contains "全部完成输出完成文案" "$(_nt_fire "$nt_root3")" "所有任务已完成"

  # --- cmd_tail_marker_check (allow-list grammar) ---
  echo "=== cmd_tail_marker_check ==="
  local TMC_SCRIPT="${BASH_SOURCE[0]}"
  _tmc_fire() {
    # 返回 "EXIT=N|stdout..."
    local input="$1"
    local out rc
    out=$(printf '%s' "$input" | bash "$TMC_SCRIPT" tail-marker-check 2>&1)
    rc=$?
    echo "EXIT=$rc|$out"
  }

  # 合法 (exit 0, 无诊断)
  _assert_contains "完成: 合法"      "$(_tmc_fire $'前面说了很多话。\n完成: T5 全部交付')" "EXIT=0"
  _assert_contains "等你: 合法"      "$(_tmc_fire $'做了一半。\n等你: 装 ffmpeg')"        "EXIT=0"
  _assert_contains "停住: 合法"      "$(_tmc_fire $'停住: sanity 失败')"                "EXIT=0"
  _assert_contains "DONE 合法"       "$(_tmc_fire 'DONE: shipped')"                      "EXIT=0"
  _assert_contains "AWAIT 合法"      "$(_tmc_fire 'AWAIT: need token')"                  "EXIT=0"
  _assert_contains "HALT 合法"       "$(_tmc_fire 'HALT: hook block')"                   "EXIT=0"
  _assert_contains "全角冒号合法"    "$(_tmc_fire '完成：done')"                          "EXIT=0"
  _assert_contains "末尾空行不影响"  "$(_tmc_fire $'完成: x\n\n\n')"                      "EXIT=0"

  # 非法 (exit 1 + 诊断含 STOP_MARKER_MISSING)
  _assert_contains "空消息 拒"       "$(_tmc_fire '')"                                   "EMPTY_MESSAGE"
  _assert_contains "无标记 拒"       "$(_tmc_fire '任务完成, 准备做下一个。')"            "STOP_MARKER_MISSING"
  _assert_contains "无冒号 拒"       "$(_tmc_fire '完成 T5')"                             "STOP_MARKER_MISSING"
  _assert_contains "缩进 拒"         "$(_tmc_fire '  完成: T5')"                          "STOP_MARKER_MISSING"
  _assert_contains "代码块内 拒"     "$(_tmc_fire $'```\n完成: T5\n```')"                 "STOP_MARKER_MISSING"
  _assert_contains "标记非末行 拒"   "$(_tmc_fire $'完成: T5\n后面还有字')"                "STOP_MARKER_MISSING"
  _assert_contains "冒号后空 拒"     "$(_tmc_fire '完成:')"                                "STOP_MARKER_MISSING"
  _assert_contains "拼写相似 拒"     "$(_tmc_fire '完毕: x')"                              "STOP_MARKER_MISSING"

  echo ""
  echo "=== 结果: ${pass}/${total} 通过, ${fail} 失败 ==="

  if [[ "$fail" -gt 0 ]]; then
    exit 1
  fi
  exit 0
}

# ---- 子命令: audit ----
# Stop 时文件系统状态审计
# 不管 AI 走没走 skill 流程，直接验产出物质量
# 退出码：0 = 无问题或已提醒，2 = 发现缺口需 AI 补全

cmd_audit() {
  # 元仓库豁免: 仓库根存在 .ai-rules-meta marker → 跳过审计 (此仓库是方法论本身, 不走产品项目流程)
  if [[ -f "$ROOT/.ai-rules-meta" ]]; then
    exit 0
  fi

  local issues=()

  # 获取当前所有改动（committed + staged + unstaged + untracked）
  local changed_files=""
  if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    changed_files=$(
      git -C "$ROOT" diff --name-only 2>/dev/null
      git -C "$ROOT" diff --cached --name-only 2>/dev/null
      git -C "$ROOT" diff HEAD~1 --name-only 2>/dev/null
      git -C "$ROOT" ls-files --others --exclude-standard 2>/dev/null
    ) || true
    changed_files=$(echo "$changed_files" | sort -u | grep -v '^$' || true)
  fi

  if [[ -z "$changed_files" ]]; then
    exit 0
  fi

  # 源码文件（排除 docs/ scripts/ .claude/ 配置等）
  local src_files
  src_files=$(echo "$changed_files" | grep -vE '^(docs/|scripts/|\.claude/|CLAUDE\.md|package|\.git|\.env|README|LICENSE|node_modules)' || true)
  local src_count=0
  if [[ -n "$src_files" ]]; then
    src_count=$(echo "$src_files" | wc -l | tr -d ' ')
  fi

  # ---- 检查 1: 有源码但没 commit ----
  local uncommitted_src=0
  if [[ "$src_count" -gt 0 ]]; then
    uncommitted_src=$(echo "$src_files" | while read -r f; do
      git -C "$ROOT" ls-files --error-unmatch "$f" >/dev/null 2>&1 || echo "$f"
    done | wc -l | tr -d ' ') || true
  fi
  # 也计算已修改但未暂存的源码文件（排除框架配置文件）
  local modified_not_staged=0
  modified_not_staged=$(git -C "$ROOT" diff --name-only 2>/dev/null \
    | grep -vE '^(docs/|scripts/|\.claude/|CLAUDE\.md|package|\.git|\.env|README|LICENSE|node_modules)' \
    | wc -l | tr -d ' ') || true

  local total_uncommitted=$((uncommitted_src + modified_not_staged))
  local grace_active
  grace_active=$(sg_impl_batch_grace_active "$ROOT")
  if [[ -n "$grace_active" ]]; then
    : # 并行 subagent 宽限期内 (impl-batch.json 声明 no_commit_in_subagent + 未超 30min) → 放行
      # parent 等 subagent 返回后按任务顺序 commit, 期间不拦
  elif [[ "$total_uncommitted" -gt 5 ]]; then
    issues+=("[未 commit] ${uncommitted_src} 个新文件 + ${modified_not_staged} 个修改文件未 commit。直接 git add + git commit（CLAUDE.md 已授权 auto-commit，不必请示用户；除非涉及 .env/密钥/force push）。")
  fi

  # ---- 检查 2: spec.md 存在就验质量（不管是不是刚改的）----
  if [[ -f "$SPEC_FILE" && "$src_count" -gt 0 ]]; then
    local spec_issues=()
    local result

    result=$(sg_spec_task_template "$SPEC_FILE")
    if [[ -n "$result" ]]; then spec_issues+=("$result"); fi

    result=$(sg_spec_coverage_contract "$SPEC_FILE")
    if [[ -n "$result" ]]; then spec_issues+=("$result"); fi

    result=$(sg_spec_prd_challenge "$SPEC_FILE")
    if [[ -n "$result" ]]; then spec_issues+=("$result"); fi

    result=$(sg_spec_critical_modules "$SPEC_FILE")
    if [[ -n "$result" ]]; then spec_issues+=("$result"); fi

    result=$(sg_spec_failure_imagination "$SPEC_FILE")
    if [[ -n "$result" ]]; then spec_issues+=("$result"); fi

    result=$(sg_spec_fi_cross_check "$SPEC_FILE")
    if [[ -n "$result" ]]; then spec_issues+=("$result"); fi

    result=$(sg_spec_fi_has_subjects "$SPEC_FILE")
    if [[ -n "$result" ]]; then spec_issues+=("$result"); fi

    result=$(sg_spec_fi_no_duplicates "$SPEC_FILE")
    if [[ -n "$result" ]]; then spec_issues+=("$result"); fi

    if [[ ${#spec_issues[@]} -gt 0 ]]; then
      issues+=("[spec.md 质量不达标] 以下检查未通过:")
      for si in ${spec_issues[@]+"${spec_issues[@]}"}; do
        issues+=("  - $si")
      done
      issues+=("修复: 在 spec.md 中补全 TASK-TEMPLATE (每个任务需要 TASK/ACCEPT/FILES 字段) + 覆盖契约章节 + 故障对账标注 (防 故障#N)")
    fi
  fi

  # ---- 检查 3: 有源码但没 spec ----
  if [[ "$src_count" -gt 3 && ! -f "$SPEC_FILE" ]]; then
    issues+=("[缺少 spec] 检测到 ${src_count} 个源码文件改动但无 docs/spec.md。标准任务需要先写 spec。")
  fi

  # ---- 检查 4: status.md 检查 ----
  if [[ -f "$STATUS_FILE" && "$src_count" -gt 0 ]]; then
    local result
    result=$(sg_status_has_phase "$STATUS_FILE")
    if [[ -n "$result" ]]; then
      issues+=("[status.md] $result")
    fi
  elif [[ "$src_count" -gt 3 && ! -f "$STATUS_FILE" ]]; then
    issues+=("[缺少 status.md] 标准任务需要 docs/status.md 记录进度和 PROJECT_PHASE。")
  fi

  # ---- 检查 5: sanity 静态一致性（仅在有源码改动时）----
  if [[ "$src_count" -gt 0 ]]; then
    local result
    result=$(sg_sanity_hardcoded_addrs "$ROOT")
    if [[ -n "$result" ]]; then
      issues+=("[sanity] $result")
    fi
    result=$(sg_sanity_build_freshness "$ROOT")
    if [[ -n "$result" ]]; then
      issues+=("[sanity] $result")
    fi
  fi

  # ---- 防重复提醒 ----
  if [[ ${#issues[@]} -gt 0 ]]; then
    local audit_state="$ROOT/.claude/state/last-audit.json"
    local issue_text=""
    for i in ${issues[@]+"${issues[@]}"}; do
      issue_text+="$i"$'\n'
    done

    # 用 issue 数量 + 第一个 issue 的长度作为去重 key（简单但有效区分不同问题组合）
    local first_len=${#issues[0]}
    local issue_key="${#issues[@]}-${first_len}"

    # 检查是否 5 分钟内已提醒过相同内容（用 epoch 避免时区问题）
    if [[ -f "$audit_state" ]] && command -v jq >/dev/null 2>&1; then
      local last_epoch last_key
      last_epoch=$(jq -r '.epoch // 0' "$audit_state" 2>/dev/null)
      last_key=$(jq -r '.key // ""' "$audit_state" 2>/dev/null)
      local now_epoch
      now_epoch=$(date +%s)

      if [[ "$last_key" == "$issue_key" && "$last_epoch" -gt 0 ]]; then
        local diff=$((now_epoch - last_epoch))
        if [[ $diff -lt 300 ]]; then
          # 5 分钟内相同问题，不重复提醒
          exit 0
        fi
      fi
    fi

    # 记录本次提醒
    mkdir -p "$ROOT/.claude/state" 2>/dev/null
    local now_epoch
    now_epoch=$(date +%s)
    if command -v jq >/dev/null 2>&1; then
      jq -nc --argjson epoch "$now_epoch" --arg key "$issue_key" '{epoch:$epoch,key:$key}' > "$audit_state" 2>/dev/null || true
    fi

    # 输出问题
    echo "---"
    echo "[GATE 审计] 文件系统状态检查发现以下问题:"
    for i in ${issues[@]+"${issues[@]}"}; do
      echo "$i"
    done
    echo "---"
    exit 2
  fi

  exit 0
}

# ---- 子命令: fuse ----
# 熔断器：检测 AI 在错误方向上死循环，分级响应
# 信号源：skill-gate 连续失败、同一文件反复修改
# 级别：soft（跳任务）、hard（停执行）
#
# 子命令：
#   fuse check <signal-type>  — 累加失败计数，检查是否触发熔断
#   fuse report               — 输出当前熔断状态
#   fuse reset [--soft]       — 重置计数器（任务成功时调用）
#
# 状态文件：.claude/state/fuse-state.json
# 格式：{
#   "consecutive_gate_failures": 0,
#   "consecutive_soft_fuses": 0,
#   "last_signal": "",
#   "last_epoch": 0,
#   "fused_tasks": [],
#   "level": "none"  // none | soft | hard
# }

FUSE_STATE="$ROOT/.claude/state/fuse-state.json"
FUSE_SOFT_THRESHOLD=3    # skill-gate 连续失败 N 次 → 软熔断
FUSE_FILE_THRESHOLD=5    # 同一文件修改 > N 次 → 软熔断
FUSE_HARD_THRESHOLD=2    # 连续 N 个任务软熔断 → 硬熔断

# 初始化或读取 fuse 状态
_fuse_read() {
  if [[ -f "$FUSE_STATE" ]] && command -v jq >/dev/null 2>&1; then
    cat "$FUSE_STATE"
  else
    echo '{"consecutive_gate_failures":0,"consecutive_soft_fuses":0,"last_signal":"","last_epoch":0,"fused_tasks":[],"level":"none"}'
  fi
}

_fuse_write() {
  local json="$1"
  mkdir -p "$ROOT/.claude/state" 2>/dev/null
  echo "$json" > "$FUSE_STATE"
}

# 记录熔断日志
_fuse_log() {
  local msg="$1"
  local LOG_DIR="$ROOT/.claude/state"
  mkdir -p "$LOG_DIR" 2>/dev/null
  local LOG_FILE="$LOG_DIR/hook-log.jsonl"
  local TS
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg ts "$TS" --arg hook "fuse" --arg msg "$msg" \
      '{ts:$ts, hook:$hook, msg:$msg}' >> "$LOG_FILE" 2>/dev/null || true
  fi
}

# fuse check <signal-type> [detail]
# signal-type: gate-fail | file-churn
# 返回：exit 0 = 未触发, exit 10 = 软熔断, exit 20 = 硬熔断
_fuse_check() {
  local signal="${1:-}"
  local detail="${2:-}"

  local state
  state=$(_fuse_read)

  local gate_fails soft_fuses level fused_tasks
  gate_fails=$(echo "$state" | jq -r '.consecutive_gate_failures // 0')
  soft_fuses=$(echo "$state" | jq -r '.consecutive_soft_fuses // 0')
  level=$(echo "$state" | jq -r '.level // "none"')
  fused_tasks=$(echo "$state" | jq -r '.fused_tasks // []')

  # 已经是硬熔断，维持
  if [[ "$level" == "hard" ]]; then
    return 20
  fi

  local now_epoch
  now_epoch=$(date +%s)

  case "$signal" in
    gate-fail)
      gate_fails=$((gate_fails + 1))
      _fuse_log "gate-fail #${gate_fails} detail=${detail}"

      if [[ "$gate_fails" -ge "$FUSE_SOFT_THRESHOLD" ]]; then
        # 触发软熔断
        soft_fuses=$((soft_fuses + 1))
        _fuse_log "SOFT FUSE triggered: gate_fails=${gate_fails}, soft_fuses=${soft_fuses}"

        # 检查是否升级为硬熔断
        if [[ "$soft_fuses" -ge "$FUSE_HARD_THRESHOLD" ]]; then
          level="hard"
          _fuse_log "HARD FUSE triggered: consecutive soft_fuses=${soft_fuses}"
          state=$(echo "$state" | jq \
            --argjson gf "$gate_fails" \
            --argjson sf "$soft_fuses" \
            --argjson ep "$now_epoch" \
            --arg sig "$signal" \
            --arg lv "hard" \
            '.consecutive_gate_failures=$gf | .consecutive_soft_fuses=$sf | .last_signal=$sig | .last_epoch=$ep | .level=$lv')
          _fuse_write "$state"
          return 20
        fi

        level="soft"
        # 记录当前任务为 fused（从 detail 提取任务描述）
        if [[ -n "$detail" ]]; then
          fused_tasks=$(echo "$state" | jq --arg t "$detail" '.fused_tasks + [$t]')
        fi
        state=$(echo "$state" | jq \
          --argjson gf "$gate_fails" \
          --argjson sf "$soft_fuses" \
          --argjson ep "$now_epoch" \
          --arg sig "$signal" \
          --arg lv "soft" \
          --argjson ft "${fused_tasks:-[]}" \
          '.consecutive_gate_failures=$gf | .consecutive_soft_fuses=$sf | .last_signal=$sig | .last_epoch=$ep | .level=$lv | .fused_tasks=$ft')
        _fuse_write "$state"
        # 重置 gate_fails 计数（软熔断已触发，下次从 0 开始计数新任务）
        state=$(echo "$state" | jq '.consecutive_gate_failures=0')
        _fuse_write "$state"
        return 10
      fi

      # 未触发，更新计数
      state=$(echo "$state" | jq \
        --argjson gf "$gate_fails" \
        --argjson ep "$now_epoch" \
        --arg sig "$signal" \
        '.consecutive_gate_failures=$gf | .last_signal=$sig | .last_epoch=$ep')
      _fuse_write "$state"
      return 0
      ;;

    file-churn)
      # detail 格式: "filename:count"
      local churn_count="${detail##*:}"
      if [[ "$churn_count" -ge "$FUSE_FILE_THRESHOLD" ]]; then
        soft_fuses=$((soft_fuses + 1))
        _fuse_log "SOFT FUSE (file-churn): file=${detail}, soft_fuses=${soft_fuses}"

        if [[ "$soft_fuses" -ge "$FUSE_HARD_THRESHOLD" ]]; then
          level="hard"
          _fuse_log "HARD FUSE triggered: consecutive soft_fuses=${soft_fuses}"
        else
          level="soft"
        fi

        state=$(echo "$state" | jq \
          --argjson sf "$soft_fuses" \
          --argjson ep "$now_epoch" \
          --arg sig "$signal" \
          --arg lv "$level" \
          '.consecutive_soft_fuses=$sf | .last_signal=$sig | .last_epoch=$ep | .level=$lv')
        _fuse_write "$state"
        [[ "$level" == "hard" ]] && return 20
        return 10
      fi
      return 0
      ;;

    *)
      echo "Unknown fuse signal: $signal (可选: gate-fail, file-churn)"
      return 1
      ;;
  esac
}

# fuse report — 输出当前状态
_fuse_report() {
  local state
  state=$(_fuse_read)
  local level
  level=$(echo "$state" | jq -r '.level // "none"')

  if [[ "$level" == "none" ]]; then
    echo "[ai-rules fuse] 状态正常，无熔断。"
    echo "$state" | jq '.'
    return 0
  fi

  local gate_fails soft_fuses fused_tasks
  gate_fails=$(echo "$state" | jq -r '.consecutive_gate_failures')
  soft_fuses=$(echo "$state" | jq -r '.consecutive_soft_fuses')
  fused_tasks=$(echo "$state" | jq -r '.fused_tasks | join(", ")')

  if [[ "$level" == "soft" ]]; then
    echo "[ai-rules fuse] ⚠ 软熔断中"
    echo "  连续 gate 失败: ${gate_fails}"
    echo "  连续软熔断任务数: ${soft_fuses}"
    echo "  已熔断任务: ${fused_tasks}"
    echo ""
    echo "当前任务被跳过，尝试下一个无阻塞的任务。"
  elif [[ "$level" == "hard" ]]; then
    echo "[ai-rules fuse] 硬熔断 — 停止所有执行"
    echo "  连续 gate 失败: ${gate_fails}"
    echo "  连续软熔断任务数: ${soft_fuses}"
    echo "  已熔断任务: ${fused_tasks}"
    echo ""
    echo "连续多个任务触发软熔断，可能存在全局性问题。"
    echo "等待人工介入。解锁命令: scripts/ai-rules.sh fuse reset"
  fi

  return 0
}

# fuse reset [--soft] — 重置计数器
# --soft: 只重置 gate 失败计数（任务成功时）
# 无参数: 完全重置（人工解锁时）
_fuse_reset() {
  local mode="${1:-full}"

  if [[ "$mode" == "--soft" ]]; then
    # 任务成功 → 重置 gate 连续失败计数，但保留 soft_fuses 历史
    local state
    state=$(_fuse_read)
    state=$(echo "$state" | jq '.consecutive_gate_failures=0')
    # 如果当前是 soft 且新任务成功了，降级回 none
    local level
    level=$(echo "$state" | jq -r '.level // "none"')
    if [[ "$level" == "soft" ]]; then
      state=$(echo "$state" | jq '.level="none" | .consecutive_soft_fuses=0')
      _fuse_log "fuse reset (soft): task succeeded, level → none"
    fi
    _fuse_write "$state"
  else
    # 完全重置
    _fuse_write '{"consecutive_gate_failures":0,"consecutive_soft_fuses":0,"last_signal":"","last_epoch":0,"fused_tasks":[],"level":"none"}'
    _fuse_log "fuse reset (full)"
  fi

  echo "[ai-rules fuse] 计数器已重置。"
}

cmd_fuse() {
  local subcmd="${1:-}"
  shift 2>/dev/null || true

  case "$subcmd" in
    check)
      _fuse_check "$@"
      ;;
    report)
      _fuse_report
      ;;
    reset)
      _fuse_reset "$@"
      ;;
    *)
      echo "Usage: ai-rules.sh fuse <check|report|reset>"
      echo "  check <gate-fail|file-churn> [detail]  — 累加信号，检查是否触发熔断"
      echo "  report                                  — 输出当前熔断状态"
      echo "  reset [--soft]                          — 重置计数器"
      exit 1
      ;;
  esac
}

# ---- 主入口 ----

usage() {
  echo "Usage: ai-rules.sh <command> [args]"
  echo ""
  echo "Commands:"
  echo "  index              生成项目状态索引（.claude/state/index.json）"
  echo "  scope [TASK-ID]    检查改动范围是否超出任务声明"
  echo "  checkpoint         检查是否需要触发确认检查点"
  echo "  lessons            扫描结构信号，写入 docs/lessons.md"
  echo "  next-task          commit 后判定下一步（由 post-commit hook 调用）"
  echo "  continue-check     [deprecated] 从 stdin 读消息，检测 politeness reflex（被 tail-marker-check 取代）"
  echo "  tail-marker-check  从 stdin 读消息，allow-list 校验结束标记（完成:/等你:/停住:）"
  echo "  skill-gate <skill> 验收 Skill 产出物（spec/impl/check/verify/release）"
  echo "  stub-scan          扫描生产代码中的 stub/mock/placeholder 残留"
  echo "  sanity             静态一致性检查（硬编码地址、构建新鲜度、测试证据）"
  echo "  fuse <sub>         熔断器（check/report/reset）— 检测死循环，分级响应"
  echo "  audit              Stop 时文件系统状态审计（由 Stop hook 调用）"
  echo "  self-test          用内置 fixture 自检所有原子检查函数"
  echo ""
  echo "v1.7.0 — 无外部依赖，仅需 bash + git"
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

CMD="$1"
shift

case "$CMD" in
  index)      cmd_index "$@" ;;
  scope)      cmd_scope "$@" ;;
  checkpoint) cmd_checkpoint "$@" ;;
  lessons)    cmd_lessons "$@" ;;
  next-task)  cmd_next_task "$@" ;;
  continue-check) cmd_continue_check "$@" ;;
  tail-marker-check) cmd_tail_marker_check "$@" ;;
  skill-gate) cmd_skill_gate "$@" ;;
  stub-scan)  cmd_stub_scan "$@" ;;
  sanity)     cmd_sanity "$@" ;;
  fuse)       cmd_fuse "$@" ;;
  audit)      cmd_audit "$@" ;;
  self-test)  cmd_self_test "$@" ;;
  -h|--help)  usage ;;
  *)          echo "Unknown command: $CMD"; usage; exit 1 ;;
esac
