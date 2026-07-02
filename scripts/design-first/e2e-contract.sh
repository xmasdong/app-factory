#!/usr/bin/env bash
# ============================================================================
# e2e-contract.sh — E2E 字段对照 (真实响应 vs OpenAPI 声明)
#
# 对一条真实请求抓响应,提取 JSON 字段名,与 OpenAPI spec 在该 path/方法/状态码
# 下声明的字段对照,算 missing_fields (声明了但响应缺) 与 extra_fields (响应有
# 但未声明)。结果写 .claude/state/e2e-contract.json,key 严格对齐 app-gate.sh:
#   { "result": "PASS"|"FAIL", "missing_fields": [...], "extra_fields": [...] }
# missing/extra 任一非空 → 闸门判 drift。
#
# 可对多个 endpoint 累加: 重复调用时用 --merge 把本次结果并入已有 JSON。
#
# 用法:
#   e2e-contract.sh --base-url <URL> --method GET --path /users/{id} \
#                   --request-path /users/123 [--spec <path>] \
#                   [--status 200] [--token <bearer>] [--data <json>] \
#                   [--response-pointer <jq-filter>] [--merge]
#
# 读 $CLAUDE_PROJECT_DIR 当项目根,缺则 pwd。
# ============================================================================
set -euo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

BASE_URL=""
METHOD="GET"
OAS_PATH=""           # openapi 里的模板 path, 如 /users/{id}
REQ_PATH=""           # 实际请求 path, 如 /users/123 (缺则用 OAS_PATH)
SPEC="$ROOT/api/openapi.yaml"
STATUS="200"
TOKEN=""
DATA=""
# 响应里取对象的 jq 过滤器: 默认整个 body; 列表接口可传 '.[0]' 或 '.data[0]'
RESP_POINTER="."
MERGE=0
STATE_DIR="$ROOT/.claude/state"
OUT="$STATE_DIR/e2e-contract.json"

usage() {
  cat >&2 <<'EOF'
e2e-contract.sh — 真实响应字段 vs OpenAPI 声明对照,产 .claude/state/e2e-contract.json

用法:
  e2e-contract.sh --base-url <URL> --path <openapi-path> [选项]

必填:
  --base-url <URL>          API 基址
  --path <openapi-path>     OpenAPI 里的模板 path, 如 /users/{id}

选项:
  --method <M>              HTTP 方法 (默认: GET)
  --request-path <p>        实际请求 path (含具体 id), 如 /users/123
                            缺则用 --path 原样请求
  --spec <path>             OpenAPI spec (默认: $ROOT/api/openapi.yaml)
  --status <code>           期望响应状态码, 用于定位 schema (默认: 200)
  --token <bearer>          Authorization: Bearer <token>
  --data <json>             请求体 (POST/PUT/PATCH)
  --response-pointer <jq>   从响应 body 取待校验对象的 jq 过滤器
                            列表接口用 '.[0]' / '.data[0]' (默认: '.')
  --merge                   把本次 missing/extra 并入已有 e2e-contract.json
                            (多 endpoint 累加时用)
  -h, --help                帮助

依赖: jq, curl
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url)          BASE_URL="${2:-}"; shift 2 ;;
    --method)            METHOD="${2:-}"; shift 2 ;;
    --path)              OAS_PATH="${2:-}"; shift 2 ;;
    --request-path)      REQ_PATH="${2:-}"; shift 2 ;;
    --spec)              SPEC="${2:-}"; shift 2 ;;
    --status)            STATUS="${2:-}"; shift 2 ;;
    --token)             TOKEN="${2:-}"; shift 2 ;;
    --data)              DATA="${2:-}"; shift 2 ;;
    --response-pointer)  RESP_POINTER="${2:-}"; shift 2 ;;
    --merge)             MERGE=1; shift ;;
    -h|--help)           usage; exit 0 ;;
    *) echo "错误: 未知参数 '$1'" >&2; usage; exit 2 ;;
  esac
done

die() { echo "错误: $*" >&2; exit 1; }

[[ -n "$BASE_URL" ]] || { echo "错误: 缺 --base-url" >&2; usage; exit 2; }
[[ -n "$OAS_PATH" ]] || { echo "错误: 缺 --path" >&2; usage; exit 2; }

command -v jq   >/dev/null 2>&1 || die "缺依赖 jq。请安装: brew install jq"
command -v curl >/dev/null 2>&1 || die "缺依赖 curl。"
[[ -f "$SPEC" ]] || die "找不到 OpenAPI spec: $SPEC"

[[ -z "$REQ_PATH" ]] && REQ_PATH="$OAS_PATH"
METHOD_UPPER="$(printf '%s' "$METHOD" | tr '[:lower:]' '[:upper:]')"

mkdir -p "$STATE_DIR"

# ---- 解析 openapi 声明的字段 ----------------------------------------------
# 取 paths[OAS_PATH][method].responses[status].content["application/json"].schema
# 的顶层 properties 键集 (含 $ref 一层解引用)。
# 注: yaml -> 用 jq 需 json; 这里用 python3 读 yaml/json 两吃, 无 python3 退回纯 jq(要求 spec 为 json)。
declare_fields_via_python() {
  python3 - "$SPEC" "$OAS_PATH" "$METHOD_UPPER" "$STATUS" <<'PY'
import sys, json
spec_path, oas_path, method, status = sys.argv[1:5]
method = method.lower()
def load(p):
    txt = open(p, encoding="utf-8").read()
    try:
        return json.loads(txt)
    except Exception:
        try:
            import yaml
        except Exception:
            sys.stderr.write("需要 PyYAML 解析 yaml spec: pip install pyyaml\n")
            sys.exit(3)
        return yaml.safe_load(txt)
spec = load(spec_path)
def deref(node, root, seen=None):
    seen = seen or set()
    while isinstance(node, dict) and "$ref" in node:
        ref = node["$ref"]
        if ref in seen: break
        seen.add(ref)
        if not ref.startswith("#/"):
            break
        cur = root
        for part in ref[2:].split("/"):
            part = part.replace("~1","/").replace("~0","~")
            cur = cur.get(part, {}) if isinstance(cur, dict) else {}
        node = cur
    return node
paths = spec.get("paths", {})
op = paths.get(oas_path, {}).get(method, {})
resp = op.get("responses", {})
r = resp.get(status) or resp.get(int(status) if status.isdigit() else status) or resp.get("default") or {}
r = deref(r, spec)
content = r.get("content", {})
js = content.get("application/json") or content.get("application/*+json") or {}
schema = deref(js.get("schema", {}), spec)
# 列表: 取 items
if schema.get("type") == "array":
    schema = deref(schema.get("items", {}), spec)
# allOf 合并
props = {}
def collect(s):
    s = deref(s, spec)
    for sub in s.get("allOf", []) or []:
        collect(sub)
    for k in (s.get("properties", {}) or {}):
        props[k] = True
collect(schema)
print("\n".join(sorted(props.keys())))
PY
}

DECLARED="$(declare_fields_via_python 2>/dev/null || true)"
if [[ -z "$DECLARED" ]]; then
  echo "警告: 未能从 spec 解析出 $METHOD_UPPER $OAS_PATH 的 $STATUS 响应字段 (无 python3/pyyaml 或 spec 无此声明)。" >&2
  echo "      将以空声明集对照, missing 恒空, extra=全部响应字段。" >&2
fi

# ---- 发真实请求抓响应 ------------------------------------------------------
URL="${BASE_URL%/}${REQ_PATH}"
CURL_ARGS=( -sS -X "$METHOD_UPPER" -H "Accept: application/json" )
[[ -n "$TOKEN" ]] && CURL_ARGS+=( -H "Authorization: Bearer $TOKEN" )
if [[ -n "$DATA" ]]; then
  CURL_ARGS+=( -H "Content-Type: application/json" --data "$DATA" )
fi

echo "[e2e-contract] $METHOD_UPPER $URL" >&2
BODY_FILE="$(mktemp -t e2e-body.XXXXXX)"
trap 'rm -f "$BODY_FILE"' EXIT
HTTP_CODE="$(curl "${CURL_ARGS[@]}" -o "$BODY_FILE" -w '%{http_code}' "$URL" 2>/dev/null || echo "000")"
echo "[e2e-contract] HTTP $HTTP_CODE" >&2

RESULT="PASS"
ACTUAL=""
if [[ "$HTTP_CODE" != "$STATUS" ]]; then
  echo "警告: 实际状态码 $HTTP_CODE != 期望 $STATUS" >&2
  RESULT="FAIL"
fi

# 提取实际响应字段(对象取 keys;数组取首元素 keys —— 列表端点声明的是 item 字段)
EMPTY_ARRAY=0
if jq -e . "$BODY_FILE" >/dev/null 2>&1; then
  ACTUAL="$(jq -r --arg p "$RESP_POINTER" '
      (try ('"$RESP_POINTER"') catch .) as $obj
      | ($obj // {})
      | if type=="object" then (keys_unsorted[])
        elif type=="array" and length>0 then (.[0] | if type=="object" then keys_unsorted[] else empty end)
        else empty end' \
      "$BODY_FILE" 2>/dev/null | sort -u || true)"
  if jq -e --arg p "$RESP_POINTER" '(try ('"$RESP_POINTER"') catch .) | type=="array" and length==0' "$BODY_FILE" >/dev/null 2>&1; then
    EMPTY_ARRAY=1
    echo "警告: 响应为空数组, 无 item 可对照 → 本 endpoint 跳过字段对照(先造一条真数据再跑才有效)" >&2
  fi
else
  echo "警告: 响应非合法 JSON" >&2
  RESULT="FAIL"
fi

# ---- 计算 missing / extra --------------------------------------------------
# 空数组响应:没有 item 可对照 → 两侧清空(不判漂移,警告已在上面给出)
if [[ "$EMPTY_ARRAY" == "1" ]]; then
  DECLARED=""; ACTUAL=""
fi
DECLARED_SORTED="$(printf '%s\n' "$DECLARED" | sed '/^$/d' | sort -u)"
ACTUAL_SORTED="$(printf '%s\n' "$ACTUAL" | sed '/^$/d' | sort -u)"

# missing = declared - actual ; extra = actual - declared
MISSING="$(comm -23 <(printf '%s\n' "$DECLARED_SORTED") <(printf '%s\n' "$ACTUAL_SORTED") | sed '/^$/d')"
EXTRA="$(comm -13 <(printf '%s\n' "$DECLARED_SORTED") <(printf '%s\n' "$ACTUAL_SORTED") | sed '/^$/d')"

# 用 path 前缀标注字段来源, 便于多 endpoint 聚合排查
tag() { local f; while IFS= read -r f; do [[ -n "$f" ]] && printf '%s%s\n' "$1" "$f"; done; return 0; }
MISSING_TAGGED="$(printf '%s\n' "$MISSING" | tag "${METHOD_UPPER} ${OAS_PATH}#")"
EXTRA_TAGGED="$(printf '%s\n' "$EXTRA"   | tag "${METHOD_UPPER} ${OAS_PATH}#")"

MISSING_JSON="$(printf '%s\n' "$MISSING_TAGGED" | jq -R . | jq -s 'map(select(length>0))')"
EXTRA_JSON="$(printf '%s\n'   "$EXTRA_TAGGED"   | jq -R . | jq -s 'map(select(length>0))')"

# missing/extra 非空 → drift → FAIL
if [[ "$(printf '%s' "$MISSING_JSON" | jq 'length')" -gt 0 || "$(printf '%s' "$EXTRA_JSON" | jq 'length')" -gt 0 ]]; then
  RESULT="FAIL"
fi

# ---- 写 / 合并 state JSON --------------------------------------------------
if [[ "$MERGE" -eq 1 && -f "$OUT" ]]; then
  jq \
    --argjson missing "$MISSING_JSON" \
    --argjson extra "$EXTRA_JSON" \
    --arg result "$RESULT" \
    '
    .missing_fields = ((.missing_fields // []) + $missing | unique)
    | .extra_fields = ((.extra_fields // []) + $extra | unique)
    | .result = ( if ($result=="FAIL" or (.result=="FAIL")) then "FAIL"
                  elif ((.missing_fields|length)>0 or (.extra_fields|length)>0) then "FAIL"
                  else "PASS" end )
    ' "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
else
  jq -n \
    --arg result "$RESULT" \
    --argjson missing "$MISSING_JSON" \
    --argjson extra "$EXTRA_JSON" \
    '{result:$result, missing_fields:$missing, extra_fields:$extra}' \
    > "$OUT"
fi

echo "[e2e-contract] 写出: $OUT" >&2
jq '{result, missing:(.missing_fields|length), extra:(.extra_fields|length)}' "$OUT" >&2

[[ "$(jq -r .result "$OUT")" == "PASS" ]] && exit 0 || exit 1
