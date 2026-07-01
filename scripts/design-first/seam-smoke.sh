#!/usr/bin/env bash
# ============================================================================
# seam-smoke.sh — 前后端合体 seam 冒烟(证明"两个半体真能握手")
#
# 问题:app-factory 会分别产出「后端(测试绿)」+「前端(build 绿)」两个半体,
#       但两半各自绿 ≠ 合体能跑。trade-copilot 实战暴露:前端全程 mock fallback、
#       后端单独跑,seam(前端声明要调的 endpoint 在真后端是否存在/可握手)从没验过。
#
# 本脚本做的事(只握手,不 boot —— 后端须已在 --base-url 运行,boot 是调用方/qa skill 的活):
#   1. 探测健康: /healthz | /health | /api/health | /  任一 HTTP < 500 => backend_boot=true
#   2. 抽取「前端 api-client 声明要调的 endpoint」:
#        grep --frontend-dir 里的 path 字面量('/api/...'、"/users/..." 等)
#        缺 --frontend-dir / 抽不到 => 退回读 --openapi 的 paths(弱化版:验后端自证契约)
#   3. 逐 endpoint 真 HTTP 探测(path 参数用占位值 1;GET 探活):
#        - 连接失败 / HTTP 000            => 断裂(后端没起 / 不可达)
#        - 无参 path 返回 404             => 断裂(前端指向后端不存在的路由)
#        - 200/201/400/401/403/405/422 等 => 路由存在(鉴权/校验错误不算断,握手成功)
#        - 含参 path 的 404               => 记 warn 不判断裂(资源不存在 vs 路由不存在 二义)
#   4. 写 .claude/state/seam-smoke.json(key 对齐 app-gate.sh sg_app_seam_smoke):
#        { result:"PASS"|"FAIL", base_url, backend_boot:bool, source:"frontend"|"openapi",
#          frontend_endpoints:N, checks:[{path,method,status,ok}], broken:[...], warn:[...], notes:"" }
#        result = PASS iff backend_boot=true 且 broken 数 = 0
#
# 用法:
#   seam-smoke.sh --base-url http://127.0.0.1:8000 \
#     [--frontend-dir frontend] [--openapi api/openapi.yaml] \
#     [--api-client frontend/lib/api.ts] [--timeout 5]
#
# 读 $CLAUDE_PROJECT_DIR 当项目根,缺则 pwd。依赖:curl + jq。
# ============================================================================
set -euo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# ---- defaults -------------------------------------------------------------
BASE_URL=""
FRONTEND_DIR=""
OPENAPI="$ROOT/api/openapi.yaml"
API_CLIENT=""
TIMEOUT=5
STATE_DIR="$ROOT/.claude/state"
OUT="$STATE_DIR/seam-smoke.json"

usage() {
  cat >&2 <<'EOF'
seam-smoke.sh — 前后端合体 seam 冒烟,产 .claude/state/seam-smoke.json

用法:
  seam-smoke.sh --base-url <URL> [选项]

必填:
  --base-url <URL>        已运行的真后端基址 (本脚本不 boot,须先起好)

选项:
  --frontend-dir <dir>    前端目录, 从中抽取 api-client 声明的 endpoint
                          (默认自动探测: frontend/ | web/ | app/ | src/)
  --api-client <file>     显式指定 api-client 文件 (默认在 frontend-dir 里找
                          lib/api.* | src/api.* | services/api.* | api/client.*)
  --openapi <path>        OpenAPI spec (默认 $ROOT/api/openapi.yaml);
                          抽不到前端 endpoint 时退回用它的 paths
  --timeout <sec>         每次 curl 超时秒 (默认 5)
  -h, --help              显示本帮助

依赖: curl, jq
EOF
}

# ---- parse args -----------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url)     BASE_URL="${2:-}"; shift 2 ;;
    --frontend-dir) FRONTEND_DIR="${2:-}"; shift 2 ;;
    --api-client)   API_CLIENT="${2:-}"; shift 2 ;;
    --openapi)      OPENAPI="${2:-}"; shift 2 ;;
    --timeout)      TIMEOUT="${2:-}"; shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "错误: 未知参数 '$1'" >&2; usage; exit 2 ;;
  esac
done

die() { echo "错误: $*" >&2; exit 1; }
[[ -n "$BASE_URL" ]] || { echo "错误: 缺 --base-url" >&2; usage; exit 2; }
command -v curl >/dev/null 2>&1 || die "缺依赖 curl"
command -v jq   >/dev/null 2>&1 || die "缺依赖 jq (brew install jq)"

BASE_URL="${BASE_URL%/}"     # 去尾 /
mkdir -p "$STATE_DIR"

# ---- 探测后端健康 ---------------------------------------------------------
http_code() {
  # $1=method $2=url -> 打印 HTTP 状态码 (连接失败=000)
  curl -s -o /dev/null -w '%{http_code}' -X "$1" \
    --max-time "$TIMEOUT" "$2" 2>/dev/null || echo "000"
}

BACKEND_BOOT=false
for hp in /healthz /health /api/health /api/healthz /; do
  code=$(http_code GET "$BASE_URL$hp")
  if [[ "$code" != "000" && "$code" -lt 500 ]]; then
    BACKEND_BOOT=true
    break
  fi
done

# ---- 抽取前端声明的 endpoint ----------------------------------------------
# 自动探测前端目录
if [[ -z "$FRONTEND_DIR" ]]; then
  for d in frontend web app src client; do
    if [[ -d "$ROOT/$d" ]]; then FRONTEND_DIR="$ROOT/$d"; break; fi
  done
else
  [[ "$FRONTEND_DIR" = /* ]] || FRONTEND_DIR="$ROOT/$FRONTEND_DIR"
fi

# 收集候选 api-client 文件
CLIENT_FILES=()
if [[ -n "$API_CLIENT" ]]; then
  [[ "$API_CLIENT" = /* ]] || API_CLIENT="$ROOT/$API_CLIENT"
  [[ -f "$API_CLIENT" ]] && CLIENT_FILES+=("$API_CLIENT")
elif [[ -n "$FRONTEND_DIR" && -d "$FRONTEND_DIR" ]]; then
  while IFS= read -r f; do CLIENT_FILES+=("$f"); done < <(
    find "$FRONTEND_DIR" -type f \
      \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
         -o -name '*.dart' -o -name '*.swift' -o -name '*.kt' \) \
      -not -path '*/node_modules/*' -not -path '*/.next/*' -not -path '*/build/*' 2>/dev/null \
    | xargs grep -lE "['\"\`]/(api|v1|users|auth|positions|triggers|market|review|deepdive|chat|push|me)[/\"'\`]" 2>/dev/null \
    | head -40
  )
fi

# 先从 openapi 算「合法 API 前缀集合」(每条 openapi path 的首段, 如 /api)。
# 关键:前端 api-client 里既有后端调用('/api/chat')又有前端页面路由('/chat'、'/me'),
# 只按关键词抓会把页面路由误判成 endpoint(假阳性)。用 openapi 首段过滤 → 只认真后端路由。
declare -a API_PREFIXES=()
if [[ -f "$OPENAPI" ]]; then
  while IFS= read -r seg; do
    [[ -n "$seg" ]] && API_PREFIXES+=("$seg")
  done < <(
    grep -oaE "^[[:space:]]{2}/[A-Za-z0-9_./{}-]+:" "$OPENAPI" 2>/dev/null \
      | sed -E 's/^[[:space:]]+//; s/:[[:space:]]*$//' \
      | sed -E 's#^(/[A-Za-z0-9_-]+).*#\1#' | sort -u
  )
fi
# 缺 openapi / 抽不到 → 默认认 /api /v1 (最常见 API 前缀)
[[ ${#API_PREFIXES[@]} -eq 0 ]] && API_PREFIXES=(/api /v1)

is_api_path() {
  # $1=path -> 首段是否 ∈ API_PREFIXES(是真后端 endpoint,不是前端页面路由)
  local seg pre
  seg=$(printf '%s' "$1" | sed -E 's#^(/[A-Za-z0-9_-]+).*#\1#')
  for pre in "${API_PREFIXES[@]}"; do
    [[ "$seg" == "$pre" ]] && return 0
  done
  return 1
}

# 从 client 文件抽 path 字面量, 按 API 前缀过滤;抽不到则退回 openapi
declare -a RAW_PATHS=()
SOURCE="frontend"
PAGE_ROUTES_SKIPPED=0
if [[ ${#CLIENT_FILES[@]} -gt 0 ]]; then
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    if is_api_path "$p"; then
      RAW_PATHS+=("$p")
    else
      PAGE_ROUTES_SKIPPED=$((PAGE_ROUTES_SKIPPED+1))   # 前端页面路由/非 API,跳过
    fi
  done < <(
    grep -ohaE "['\"\`]/[A-Za-z0-9_./{}$:-]+['\"\`]" "${CLIENT_FILES[@]}" 2>/dev/null \
      | sed -E "s/^['\"\`]//; s/['\"\`]\$//" \
      | grep -E '^/' | sort -u
  )
fi

if [[ ${#RAW_PATHS[@]} -eq 0 ]]; then
  # 退回 openapi paths
  SOURCE="openapi"
  if [[ -f "$OPENAPI" ]]; then
    while IFS= read -r p; do
      [[ -n "$p" ]] && RAW_PATHS+=("$p")
    done < <(grep -oaE "^[[:space:]]{2}/[A-Za-z0-9_./{}-]+:" "$OPENAPI" 2>/dev/null | sed -E 's/^[[:space:]]+//; s/:[[:space:]]*$//' | sort -u)
  fi
fi

# ---- 逐 endpoint 探测 ------------------------------------------------------
CHECKS_JSON="[]"
BROKEN_JSON="[]"
WARN_JSON="[]"
N=0

norm_path() {
  # 归一 path 参数为占位值 1;去掉 query;去掉模板插值
  local p="$1"
  p="${p%%\?*}"                                   # 去 query
  p=$(printf '%s' "$p" | sed -E 's/\$\{[^}]*\}/1/g')   # ${x} -> 1
  p=$(printf '%s' "$p" | sed -E 's/\{[^}]*\}/1/g')     # {id} -> 1
  p=$(printf '%s' "$p" | sed -E 's#/:[A-Za-z0-9_]+#/1#g')  # /:id -> /1
  printf '%s' "$p"
}

has_param() {
  # 原始 path 是否含参数占位
  case "$1" in
    *'{'*|*':'*|*'${'*) return 0 ;;
    *) return 1 ;;
  esac
}

for raw in "${RAW_PATHS[@]}"; do
  # 跳过明显非 endpoint(纯静态资源/含空格)
  [[ "$raw" == *" "* ]] && continue
  probe=$(norm_path "$raw")
  [[ "$probe" == /* ]] || continue
  N=$((N+1))
  code=$(http_code GET "$BASE_URL$probe")
  ok=true
  reason=""
  if [[ "$code" == "000" ]]; then
    ok=false; reason="连接失败/后端不可达"
  elif [[ "$code" == "404" ]]; then
    if has_param "$raw"; then
      reason="含参 path 404(资源缺失,路由存疑)"   # warn,不判断裂
    else
      ok=false; reason="路由不存在(前端指向后端没有的 endpoint)"
    fi
  fi
  CHECKS_JSON=$(jq -c --arg p "$raw" --arg m GET --arg s "$code" --argjson ok "$ok" \
    '. + [{path:$p, method:$m, status:$s, ok:$ok}]' <<<"$CHECKS_JSON")
  if [[ "$ok" == "false" ]]; then
    BROKEN_JSON=$(jq -c --arg p "$raw" --arg s "$code" --arg r "$reason" \
      '. + [{path:$p, status:$s, reason:$r}]' <<<"$BROKEN_JSON")
  elif [[ -n "$reason" ]]; then
    WARN_JSON=$(jq -c --arg p "$raw" --arg s "$code" --arg r "$reason" \
      '. + [{path:$p, status:$s, reason:$r}]' <<<"$WARN_JSON")
  fi
done

# ---- 判定 -----------------------------------------------------------------
BROKEN_COUNT=$(jq 'length' <<<"$BROKEN_JSON")
RESULT="PASS"
NOTES=""
if [[ "$BACKEND_BOOT" != "true" ]]; then
  RESULT="FAIL"; NOTES="后端未在 $BASE_URL 起来(健康探测全失败)—— 先 boot 后端再跑 seam"
elif (( N == 0 )); then
  RESULT="FAIL"; NOTES="没抽到任何前端声明的 endpoint,也没 openapi paths —— 无法验 seam"
elif (( BROKEN_COUNT > 0 )); then
  RESULT="FAIL"; NOTES="$BROKEN_COUNT 个前端 endpoint 在真后端断裂(见 broken)"
else
  NOTES="seam 握手通过:$N 个 endpoint 全在真后端可达(source=$SOURCE;跳过 ${PAGE_ROUTES_SKIPPED} 个前端页面路由/非 API 路径)"
fi

# ---- 写 state JSON --------------------------------------------------------
jq -n \
  --arg result "$RESULT" \
  --arg base_url "$BASE_URL" \
  --argjson backend_boot "$BACKEND_BOOT" \
  --arg source "$SOURCE" \
  --argjson frontend_endpoints "$N" \
  --argjson page_routes_skipped "$PAGE_ROUTES_SKIPPED" \
  --argjson checks "$CHECKS_JSON" \
  --argjson broken "$BROKEN_JSON" \
  --argjson warn "$WARN_JSON" \
  --arg notes "$NOTES" \
  '{result:$result, base_url:$base_url, backend_boot:$backend_boot, source:$source,
    frontend_endpoints:$frontend_endpoints, page_routes_skipped:$page_routes_skipped,
    checks:$checks, broken:$broken, warn:$warn, notes:$notes}' \
  > "$OUT"

echo "[seam-smoke] 写出: $OUT" >&2
jq '{result, backend_boot, source, frontend_endpoints, broken_count:(.broken|length), warn_count:(.warn|length), notes}' "$OUT" >&2

[[ "$RESULT" == "PASS" ]] && exit 0 || exit 1
