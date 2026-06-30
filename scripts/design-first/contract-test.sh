#!/usr/bin/env bash
# ============================================================================
# contract-test.sh — Schemathesis 契约测试包装器
#
# 对一个 OpenAPI spec (默认 api/openapi.yaml) 跑 schemathesis 全套 checks,
# 解析结果写 .claude/state/contract-test.json,key 严格对齐 app-gate.sh:
#   { "target": "mock"|"real", "result": "PASS"|"FAIL", "failures": [...] }
#
# target 由 base-url 决定:
#   - 指向 prism mock (localhost prism 默认 4010, 或 URL 含 'prism'/'mock') → "mock"
#   - 其它(真后端)                                                         → "real"
#   可用 --target mock|real 显式覆盖。
#
# 用法:
#   contract-test.sh --base-url <URL> [--spec <path>] [--target mock|real]
#                    [--max-examples N] [--path <openapi-path>]
#
# 读 $CLAUDE_PROJECT_DIR 当项目根,缺则 pwd。
# ============================================================================
set -euo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# ---- defaults -------------------------------------------------------------
BASE_URL=""
SPEC="$ROOT/api/openapi.yaml"
TARGET=""                 # 空 => 自动推断
MAX_EXAMPLES=50
ONLY_PATH=""              # 仅测某个 openapi path (传给 schemathesis --include-path)
STATE_DIR="$ROOT/.claude/state"
OUT="$STATE_DIR/contract-test.json"

usage() {
  cat >&2 <<'EOF'
contract-test.sh — Schemathesis 契约测试,产 .claude/state/contract-test.json

用法:
  contract-test.sh --base-url <URL> [选项]

必填:
  --base-url <URL>        被测 API 基址 (mock 或 real)

选项:
  --spec <path>           OpenAPI spec 路径 (默认: $ROOT/api/openapi.yaml)
  --target mock|real      显式标注目标; 缺省时按 base-url 自动推断
                          (含 prism/mock 或 端口 4010 → mock, 否则 real)
  --max-examples N        每个 endpoint 的 hypothesis 用例上限 (默认: 50)
  --path <openapi-path>   仅测指定 path, 如 /users/{id} (默认: 全部)
  -h, --help              显示本帮助

环境:
  CLAUDE_PROJECT_DIR      项目根 (缺则用 pwd)

依赖:
  schemathesis (pip install schemathesis) — 命令名 schemathesis 或 st
  jq (写/校验 JSON)

示例:
  # 对 prism mock 跑 (target 自动判为 mock):
  contract-test.sh --base-url http://127.0.0.1:4010
  # 对真后端跑:
  contract-test.sh --base-url https://api.example.com --target real
EOF
}

# ---- parse args -----------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url)     BASE_URL="${2:-}"; shift 2 ;;
    --spec)         SPEC="${2:-}"; shift 2 ;;
    --target)       TARGET="${2:-}"; shift 2 ;;
    --max-examples) MAX_EXAMPLES="${2:-}"; shift 2 ;;
    --path)         ONLY_PATH="${2:-}"; shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "错误: 未知参数 '$1'" >&2; usage; exit 2 ;;
  esac
done

# ---- friendly dependency / arg checks -------------------------------------
die() { echo "错误: $*" >&2; exit 1; }

[[ -n "$BASE_URL" ]] || { echo "错误: 缺 --base-url" >&2; usage; exit 2; }

command -v jq >/dev/null 2>&1 || die "缺依赖 jq。请安装: brew install jq"

# schemathesis: 优先 'schemathesis run', 退回 'st run'
ST_CMD=""
if command -v schemathesis >/dev/null 2>&1; then
  ST_CMD="schemathesis"
elif command -v st >/dev/null 2>&1; then
  ST_CMD="st"
else
  die "缺依赖 schemathesis。请安装: pip install schemathesis (提供 schemathesis / st 命令)"
fi

[[ -f "$SPEC" ]] || die "找不到 OpenAPI spec: $SPEC (先跑 /shape 或 backend-forge OpenAPI-SSOT 阶段定稿 api/openapi.yaml)"

# ---- infer target ---------------------------------------------------------
if [[ -z "$TARGET" ]]; then
  lc_url="$(printf '%s' "$BASE_URL" | tr '[:upper:]' '[:lower:]')"
  if [[ "$lc_url" == *prism* || "$lc_url" == *mock* || "$lc_url" == *:4010* ]]; then
    TARGET="mock"
  else
    TARGET="real"
  fi
fi
case "$TARGET" in
  mock|real) ;;
  *) die "--target 只能是 mock 或 real (得到: $TARGET)" ;;
esac

mkdir -p "$STATE_DIR"

# ---- run schemathesis -----------------------------------------------------
RAW_LOG="$(mktemp -t contract-test.XXXXXX)"
trap 'rm -f "$RAW_LOG"' EXIT

ST_ARGS=( run "$SPEC" )
# base url: schemathesis 4.x 用 --url, 3.x 用 --base-url (探测)
if "$ST_CMD" run --help 2>/dev/null | grep -q -- '--url'; then
  ST_ARGS+=( --url "$BASE_URL" )
else
  ST_ARGS+=( --base-url "$BASE_URL" )
fi
# checks: 3.x 有 --checks all; 4.x 默认全跑(无 --checks)
if "$ST_CMD" run --help 2>/dev/null | grep -q -- '--checks '; then
  ST_ARGS+=( --checks all )
fi
# hypothesis 用例上限: 新旧版本参数名不同, 探测后择一
if "$ST_CMD" run --help 2>/dev/null | grep -q -- '--max-examples'; then
  ST_ARGS+=( --max-examples "$MAX_EXAMPLES" )
elif "$ST_CMD" run --help 2>/dev/null | grep -q -- '--hypothesis-max-examples'; then
  ST_ARGS+=( --hypothesis-max-examples "$MAX_EXAMPLES" )
fi
# 限定单 path
if [[ -n "$ONLY_PATH" ]]; then
  if "$ST_CMD" run --help 2>/dev/null | grep -q -- '--include-path'; then
    ST_ARGS+=( --include-path "$ONLY_PATH" )
  elif "$ST_CMD" run --help 2>/dev/null | grep -q -- '--endpoint'; then
    ST_ARGS+=( --endpoint "$ONLY_PATH" )
  else
    echo "警告: 当前 schemathesis 不支持 path 过滤, 将测全部 path" >&2
  fi
fi

echo "[contract-test] 跑: $ST_CMD ${ST_ARGS[*]}" >&2
ST_EXIT=0
"$ST_CMD" "${ST_ARGS[@]}" >"$RAW_LOG" 2>&1 || ST_EXIT=$?

# 回显 schemathesis 输出供人排查
cat "$RAW_LOG" >&2

# ---- parse result ---------------------------------------------------------
# schemathesis 退出码: 0=全过; 非0=有失败/错误。
# 解析失败行: 形如 "<METHOD> /path -> ... FAILED" 或 check 名行。
RESULT="PASS"
if (( ST_EXIT != 0 )); then
  RESULT="FAIL"
fi

# 抽取失败 endpoint + check 名 -> failures 数组。
# 兼容多版本输出: 抓含 FAILED / failed checks / "1 failures" 的行,
# 以及 "FAILED" 块里的 "METHOD /path" 行。
FAILURES_JSON="[]"
if [[ "$RESULT" == "FAIL" ]]; then
  FAILURES_JSON="$( {
    grep -aE 'FAILED|failed|ERROR|error' "$RAW_LOG" \
      | grep -aoE '(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS) +[^ ]+|(status_code_conformance|response_schema_conformance|content_type_conformance|response_headers_conformance|negative_data_rejection|use_after_free|not_a_server_error|ignored_auth)' \
      | sort -u \
      | jq -R . | jq -s '
          map(select(length>0)) as $items
          | if ($items|length)==0
            then [{endpoint:"unknown", check:"schema", detail:"schemathesis 报失败但无法精确解析行, 见 raw 日志"}]
            else
              ($items | map(select(test("^(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS) ")))) as $eps
              | ($items | map(select(test("^(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS) ")|not)))     as $chks
              | (if ($eps|length)>0 then $eps else ["unknown"] end) as $eps2
              | [ $eps2[] as $e
                  | { endpoint:$e,
                      check:( if ($chks|length)>0 then ($chks[0]) else "schema" end),
                      detail:"see schemathesis output" } ]
            end'
  } 2>/dev/null || true )"
  # jq 任何一步失败兜底成非空数组(保证 FAIL 时 failures 非空)
  if ! printf '%s' "$FAILURES_JSON" | jq -e 'type=="array"' >/dev/null 2>&1; then
    FAILURES_JSON='[{"endpoint":"unknown","check":"schema","detail":"解析失败, 见 schemathesis 原始输出"}]'
  fi
fi

# ---- write state JSON (严格 key) ------------------------------------------
jq -n \
  --arg target "$TARGET" \
  --arg result "$RESULT" \
  --argjson failures "$FAILURES_JSON" \
  '{target:$target, result:$result, failures:$failures}' \
  > "$OUT"

echo "[contract-test] 写出: $OUT" >&2
jq '{target, result, failure_count:(.failures|length)}' "$OUT" >&2

# 退出码透传(失败时非0,便于 worker 标 fail)
[[ "$RESULT" == "PASS" ]] && exit 0 || exit 1
