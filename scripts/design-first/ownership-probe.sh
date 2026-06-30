#!/usr/bin/env bash
# ============================================================================
# ownership-probe.sh — 越权(IDOR/水平越权)负向测试骨架
#
# 用 用户A 的 token 去取/改 用户B 的资源,断言被拒(默认期望 403)。
# 覆盖三类负向:
#   1. A 读 B 资源        → 期望 403 (非 200 空 / 非 404 混淆 / 非 500)
#   2. 无 token 读资源    → 期望 401
#   3. A PATCH B 资源     → 期望 403, 且 B 数据未变 (用 B 自己 token 读回验证)
#
# 结果默认并入 .claude/state/e2e-contract.json (与 e2e 字段对照同闸门),
# 任一断言失败把该文件 result 置 FAIL 并把失败用例塞进 extra_fields(标记
# 'authz:' 前缀)。也可 --separate 单独写 .claude/state/ownership-probe.json。
#
# 用法:
#   ownership-probe.sh --base-url <URL> \
#     --token-a <A_TOKEN> --token-b <B_TOKEN> \
#     --resource-b <path-to-B-resource>          # 如 /users/B_ID 或 /orders/123
#     [--patch-data '{"name":"x"}'] [--expect-read 403] [--expect-noauth 401]
#     [--separate]
#
# 读 $CLAUDE_PROJECT_DIR 当项目根,缺则 pwd。
# ============================================================================
set -euo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

BASE_URL=""
TOKEN_A=""
TOKEN_B=""
RESOURCE_B=""             # B 拥有的资源 path
PATCH_DATA=""             # 非空则跑 A PATCH B + 读回验证
EXPECT_READ="403"         # A 读 B 期望码
EXPECT_NOAUTH="401"       # 无 token 期望码
EXPECT_WRITE="403"        # A 写 B 期望码
SEPARATE=0
STATE_DIR="$ROOT/.claude/state"
E2E_OUT="$STATE_DIR/e2e-contract.json"
SEP_OUT="$STATE_DIR/ownership-probe.json"

usage() {
  cat >&2 <<'EOF'
ownership-probe.sh — 越权负向测试 (A 取 B 资源断言 403)

用法:
  ownership-probe.sh --base-url <URL> --token-a <A> --token-b <B> \
                     --resource-b <path> [选项]

必填:
  --base-url <URL>        API 基址
  --token-a <token>       攻击者 A 的 bearer token
  --token-b <token>       受害者 B 的 bearer token (写攻击后读回验证用)
  --resource-b <path>     B 拥有的资源 path, 如 /users/<B_ID> 或 /orders/123

选项:
  --patch-data <json>     提供则跑 "A PATCH B + 读回验证 B 未变"
  --expect-read <code>    A 读 B 的期望状态码 (默认: 403)
  --expect-noauth <code>  无 token 的期望状态码 (默认: 401)
  --expect-write <code>   A 写 B 的期望状态码 (默认: 403)
  --separate              单独写 ownership-probe.json (默认并入 e2e-contract.json)
  -h, --help              帮助

依赖: jq, curl

期望严格: A 取 B 必须返回 403 (不是 200 空体, 不是 404 混淆, 不是 500)。
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url)      BASE_URL="${2:-}"; shift 2 ;;
    --token-a)       TOKEN_A="${2:-}"; shift 2 ;;
    --token-b)       TOKEN_B="${2:-}"; shift 2 ;;
    --resource-b)    RESOURCE_B="${2:-}"; shift 2 ;;
    --patch-data)    PATCH_DATA="${2:-}"; shift 2 ;;
    --expect-read)   EXPECT_READ="${2:-}"; shift 2 ;;
    --expect-noauth) EXPECT_NOAUTH="${2:-}"; shift 2 ;;
    --expect-write)  EXPECT_WRITE="${2:-}"; shift 2 ;;
    --separate)      SEPARATE=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "错误: 未知参数 '$1'" >&2; usage; exit 2 ;;
  esac
done

die() { echo "错误: $*" >&2; exit 1; }

[[ -n "$BASE_URL"   ]] || { echo "错误: 缺 --base-url" >&2; usage; exit 2; }
[[ -n "$TOKEN_A"    ]] || { echo "错误: 缺 --token-a" >&2; usage; exit 2; }
[[ -n "$RESOURCE_B" ]] || { echo "错误: 缺 --resource-b" >&2; usage; exit 2; }
# token-b 仅写回读验证必需; 无 patch 时可缺
if [[ -n "$PATCH_DATA" && -z "$TOKEN_B" ]]; then
  die "提供了 --patch-data 但缺 --token-b (写回验证 B 数据需要 B 的 token)"
fi

command -v jq   >/dev/null 2>&1 || die "缺依赖 jq。请安装: brew install jq"
command -v curl >/dev/null 2>&1 || die "缺依赖 curl。"

mkdir -p "$STATE_DIR"

URL="${BASE_URL%/}${RESOURCE_B}"

# 发请求, 回显状态码到 stdout; body 写文件
http_code() {
  # $1=method $2=token(may be empty) $3=bodyfile $4=data(optional)
  local method="$1" token="$2" bodyfile="$3" data="${4:-}"
  local args=( -sS -X "$method" -H "Accept: application/json" )
  [[ -n "$token" ]] && args+=( -H "Authorization: Bearer $token" )
  if [[ -n "$data" ]]; then
    args+=( -H "Content-Type: application/json" --data "$data" )
  fi
  curl "${args[@]}" -o "$bodyfile" -w '%{http_code}' "$URL" 2>/dev/null || echo "000"
}

TMP_DIR="$(mktemp -d -t ownprobe.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CASES_JSON='[]'        # [{name,expected,actual,result,detail}]
add_case() {
  # $1=name $2=expected $3=actual $4=result(PASS|FAIL) $5=detail
  CASES_JSON="$(printf '%s' "$CASES_JSON" | jq \
    --arg n "$1" --arg e "$2" --arg a "$3" --arg r "$4" --arg d "$5" \
    '. + [{name:$n, expected:$e, actual:$a, result:$r, detail:$d}]')"
}

OVERALL="PASS"
fail() { OVERALL="FAIL"; }

# ── case 1: A 读 B → 期望 EXPECT_READ (默认403) ─────────────────────────────
C1_BODY="$TMP_DIR/c1"
C1_CODE="$(http_code GET "$TOKEN_A" "$C1_BODY")"
if [[ "$C1_CODE" == "$EXPECT_READ" ]]; then
  add_case "A_read_B" "$EXPECT_READ" "$C1_CODE" "PASS" "A 读 B 被正确拒绝"
else
  detail="期望 $EXPECT_READ 实际 $C1_CODE"
  case "$C1_CODE" in
    200) detail="$detail (越权! A 拿到了 B 的资源)";;
    404) detail="$detail (404 混淆, 应明确 403)";;
    500) detail="$detail (500 服务器错误, 非预期拒绝)";;
  esac
  add_case "A_read_B" "$EXPECT_READ" "$C1_CODE" "FAIL" "$detail"
  fail
fi

# ── case 2: 无 token 读 → 期望 EXPECT_NOAUTH (默认401) ──────────────────────
C2_BODY="$TMP_DIR/c2"
C2_CODE="$(http_code GET "" "$C2_BODY")"
if [[ "$C2_CODE" == "$EXPECT_NOAUTH" ]]; then
  add_case "no_token_read" "$EXPECT_NOAUTH" "$C2_CODE" "PASS" "无 token 被正确拒绝"
else
  add_case "no_token_read" "$EXPECT_NOAUTH" "$C2_CODE" "FAIL" "期望 $EXPECT_NOAUTH 实际 $C2_CODE"
  fail
fi

# ── case 3: A PATCH B → 期望 EXPECT_WRITE(默认403) + 读回验证 B 未变 ─────────
if [[ -n "$PATCH_DATA" ]]; then
  # 先用 B token 读基线
  PRE_BODY="$TMP_DIR/pre"
  PRE_CODE="$(http_code GET "$TOKEN_B" "$PRE_BODY")"
  # A 尝试改 B
  C3_BODY="$TMP_DIR/c3"
  C3_CODE="$(http_code PATCH "$TOKEN_A" "$C3_BODY" "$PATCH_DATA")"
  if [[ "$C3_CODE" == "$EXPECT_WRITE" ]]; then
    add_case "A_write_B_rejected" "$EXPECT_WRITE" "$C3_CODE" "PASS" "A 改 B 被正确拒绝"
  else
    d="期望 $EXPECT_WRITE 实际 $C3_CODE"
    [[ "$C3_CODE" =~ ^2 ]] && d="$d (越权写! A 成功修改了 B)"
    add_case "A_write_B_rejected" "$EXPECT_WRITE" "$C3_CODE" "FAIL" "$d"
    fail
  fi
  # 读回验证 B 数据未变 (只有基线读成功才有意义)
  if [[ "$PRE_CODE" == "200" ]]; then
    POST_BODY="$TMP_DIR/post"
    POST_CODE="$(http_code GET "$TOKEN_B" "$POST_BODY")"
    if [[ "$POST_CODE" == "200" ]] \
       && jq -e . "$PRE_BODY" >/dev/null 2>&1 \
       && jq -e . "$POST_BODY" >/dev/null 2>&1; then
      if jq -e -s '.[0] == .[1]' "$PRE_BODY" "$POST_BODY" >/dev/null 2>&1; then
        add_case "B_data_unchanged" "identical" "identical" "PASS" "读回验证 B 数据未变"
      else
        add_case "B_data_unchanged" "identical" "changed" "FAIL" "B 数据在 A 的越权写后发生变化!"
        fail
      fi
    else
      add_case "B_data_unchanged" "identical" "unreadable" "FAIL" "读回失败(code=$POST_CODE), 无法验证 B 未变"
      fail
    fi
  else
    add_case "B_data_unchanged" "identical" "no-baseline" "FAIL" "B token 读基线失败(code=$PRE_CODE), 跳过读回比对"
    fail
  fi
fi

CASE_COUNT="$(printf '%s' "$CASES_JSON" | jq 'length')"
echo "[ownership-probe] 资源=$RESOURCE_B 跑 $CASE_COUNT 个负向用例, 总判定=$OVERALL" >&2
printf '%s' "$CASES_JSON" | jq -r '.[] | "  [\(.result)] \(.name): \(.detail)"' >&2

# ── 写 state ────────────────────────────────────────────────────────────────
if [[ "$SEPARATE" -eq 1 ]]; then
  jq -n \
    --arg resource "$RESOURCE_B" \
    --arg result "$OVERALL" \
    --argjson cases "$CASES_JSON" \
    '{resource:$resource, result:$result, cases:$cases}' \
    > "$SEP_OUT"
  echo "[ownership-probe] 写出: $SEP_OUT" >&2
else
  # 并入 e2e-contract.json: 失败用例标 'authz:' 前缀塞 extra_fields, 触发 drift。
  FAIL_TAGS="$(printf '%s' "$CASES_JSON" | jq -r --arg res "$RESOURCE_B" \
    '[ .[] | select(.result=="FAIL") | "authz:\($res):\(.name):\(.detail)" ]')"
  if [[ ! -f "$E2E_OUT" ]]; then
    jq -n \
      --arg result "$OVERALL" \
      --argjson tags "$FAIL_TAGS" \
      '{result:$result, missing_fields:[], extra_fields:$tags}' \
      > "$E2E_OUT"
  else
    jq \
      --arg result "$OVERALL" \
      --argjson tags "$FAIL_TAGS" \
      '
      .extra_fields = ((.extra_fields // []) + $tags | unique)
      | .result = ( if ($result=="FAIL" or .result=="FAIL"
                        or ((.missing_fields // [])|length)>0
                        or ((.extra_fields  // [])|length)>0)
                    then "FAIL" else "PASS" end )
      ' "$E2E_OUT" > "$E2E_OUT.tmp" && mv "$E2E_OUT.tmp" "$E2E_OUT"
  fi
  echo "[ownership-probe] 结果并入: $E2E_OUT" >&2
  jq '{result, extra:(.extra_fields|length)}' "$E2E_OUT" >&2
fi

[[ "$OVERALL" == "PASS" ]] && exit 0 || exit 1
