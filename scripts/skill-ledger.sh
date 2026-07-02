#!/usr/bin/env bash
# skill-ledger.sh — 步骤台账:治「执行者凭记忆复刻流程,软工序静默蒸发」(毕业考排练实锤的漏工模式)。
#
# 机制:skill 开跑第一动作 = init(把 SKILL.md 执行计划物化成 state JSON);
#       每步完成 done / 跳过 skip(必须给理由);带「⇒回执:」标注的步骤,check 时验证回执文件真实存在。
#       闸门验台账 —— 漏掉的步骤从"没人知道"变"机械红灯"。
#
# 用法:
#   skill-ledger.sh init  <skill>                 # 解析 SKILL.md 执行计划 → .claude/state/skill-run/<skill>.json
#   skill-ledger.sh done  <skill> <step号|关键词>  # 标完成
#   skill-ledger.sh skip  <skill> <step号|关键词> <理由>   # 显式跳过(必须理由)
#   skill-ledger.sh check <skill>                 # 全部 done/skip 且回执文件在 → 0;否则列缺 → 1
#
# SKILL.md 里的回执标注(可选,在步骤行尾):  ⇒回执: .claude/state/xxx.json
set -uo pipefail
ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
DIR="$ROOT/.claude/state/skill-run"
CMD="${1:-}"; SKILL="${2:-}"
[[ -n "$CMD" && -n "$SKILL" ]] || { grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
command -v jq >/dev/null || { echo "缺 jq" >&2; exit 1; }
LEDGER="$DIR/$SKILL.json"

find_skill_md() {
  local c
  for c in "$ROOT/.claude/skills/$SKILL/SKILL.md" "$HOME/.claude/skills/$SKILL/SKILL.md" \
           "${AI_RULES_ROOT:-/nonexistent}/skills/$SKILL/SKILL.md"; do
    [[ -f "$c" ]] && { echo "$c"; return 0; }
  done
  return 1
}

case "$CMD" in
  init)
    MD="$(find_skill_md)" || { echo "找不到 $SKILL/SKILL.md" >&2; exit 1; }
    mkdir -p "$DIR"
    # 抓执行计划里的 checklist 行(- [ ] Step ...),抽回执标注
    grep -E '^- \[ \] Step' "$MD" | jq -R -s --arg skill "$SKILL" '
      split("\n") | map(select(length>0)) | to_entries | map({
        id: (.key + 1),
        text: (.value | sub("^- \\[ \\] "; "") | .[0:160]),
        receipt: (.value | capture("⇒回执[::]\\s*(?<r>[A-Za-z0-9_./-]+)"; "x").r // null),
        status: "pending", reason: null
      }) | {skill: $skill, steps: .}' > "$LEDGER"
    echo "台账建立: $LEDGER($(jq '.steps|length' "$LEDGER") 步,$(jq '[.steps[]|select(.receipt)]|length' "$LEDGER") 步带回执)" >&2
    ;;
  done|skip)
    [[ -f "$LEDGER" ]] || { echo "先 init(台账不存在)" >&2; exit 1; }
    KEY="${3:-}"; REASON="${4:-}"
    [[ "$CMD" == "skip" && -z "$REASON" ]] && { echo "skip 必须给理由" >&2; exit 1; }
    # 匹配优先级:精确 id 命中则只改它;否则才按文本子串(防 "4" 误伤含"A-GATE 4"的步)
    jq --arg k "$KEY" --arg st "$([[ $CMD == done ]] && echo done || echo skipped)" --arg r "$REASON" '
      ([.steps[]|select((.id|tostring)==$k)]|length) as $byid
      | .steps |= map(
          if ($byid>0 and (.id|tostring)==$k) or ($byid==0 and (.text|contains($k)))
          then .status=$st | .reason=(if $r=="" then null else $r end) else . end)' \
      "$LEDGER" > "$LEDGER.tmp" && mv "$LEDGER.tmp" "$LEDGER"
    jq -r --arg k "$KEY" '.steps[]|select(((.id|tostring)==$k) or (.text|contains($k)))|"  [\(.status)] Step \(.id): \(.text[0:60])"' "$LEDGER" >&2
    ;;
  check)
    [[ -f "$LEDGER" ]] || { echo "无台账(执行者没建账 = 凭记忆复刻流程的信号)"; exit 1; }
    MISS=$(jq -r '.steps[]|select(.status=="pending")|"  未处理: Step \(.id) \(.text[0:70])"' "$LEDGER")
    NOREASON=$(jq -r '.steps[]|select(.status=="skipped" and (.reason==null or .reason==""))|"  跳过无理由: Step \(.id)"' "$LEDGER")
    RCPT=""
    while IFS=$'\t' read -r id path; do
      [[ -z "$path" ]] && continue
      p="$path"; [[ "$p" != /* ]] && p="$ROOT/$p"
      [[ -s "$p" ]] || RCPT+=$'  回执缺失: Step '"$id → $path"$'\n'
    done < <(jq -r '.steps[]|select(.receipt and .status=="done")|[(.id|tostring),.receipt]|@tsv' "$LEDGER")
    OUT="${MISS}${MISS:+$'\n'}${NOREASON}${NOREASON:+$'\n'}${RCPT}"
    if [[ -n "${OUT//[[:space:]]/}" ]]; then echo "$OUT"; exit 1; fi
    echo "台账全清: $(jq '[.steps[]|select(.status=="done")]|length' "$LEDGER") done / $(jq '[.steps[]|select(.status=="skipped")]|length' "$LEDGER") skipped(有理由)"
    ;;
  *) echo "未知命令 $CMD" >&2; exit 2 ;;
esac
