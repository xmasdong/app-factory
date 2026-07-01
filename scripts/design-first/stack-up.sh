#!/usr/bin/env bash
# ============================================================================
# stack-up.sh — 真实环境联调基建:一键把全栈拉起来
#
# 目标:qa 的 seam/contract/integration 门要「打真后端」,但后端得先真起来。
#       这脚本负责 boot 整个栈(后端 + 依赖 + 可选前端),等健康,把前端 env
#       指向真后端,并记录 pid/compose 供 stack-down.sh 收摊。
#
# boot 策略(自动选):
#   1. compose 优先:ROOT 有 docker-compose.yml / compose.yaml 且定义了服务
#      → `docker compose up -d`(把 PG/Redis/后端/前端一把拉起)
#   2. native 兜底:无 compose 时按后端类型起进程
#      - python: backend/app/main.py|main.py + (.venv) → uvicorn app.main:app
#      - node:   backend/package.json 有 start/dev    → npm run start|dev
#      - go:     backend/main.go                      → go run .
#   起在后台, pid 落 .claude/state/stack.pids
#   3. 等后端健康(/healthz|/health|/api/health|/ 任一 <500),超时判失败
#   4. 写前端 env(frontend/.env.local:NEXT_PUBLIC_API_BASE/_API_URL/VITE_API_BASE
#      = 真后端地址),让前端 build/dev 指向真后端而非 mock
#   5.(可选 --frontend)起前端 dev,等其端口
#   6. 写 .claude/state/stack-up.json { method, backend_url, backend_ready,
#      frontend_url, pids, compose, notes }
#
# 用法:
#   stack-up.sh [--backend-dir backend] [--frontend-dir frontend]
#               [--backend-port 8000] [--frontend-port 3000]
#               [--frontend] [--timeout 60]
#
# 读 $CLAUDE_PROJECT_DIR 当项目根,缺则 pwd。收摊:stack-down.sh。
# ============================================================================
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE_DIR="$ROOT/.claude/state"
OUT="$STATE_DIR/stack-up.json"
PIDFILE="$STATE_DIR/stack.pids"
LOGDIR="$STATE_DIR/stack-logs"

BACKEND_DIR=""
FRONTEND_DIR=""
BACKEND_PORT=8000
FRONTEND_PORT=3000
START_FRONTEND=false
FORCE_NATIVE=false
TIMEOUT=60

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend-dir)  BACKEND_DIR="${2:-}"; shift 2 ;;
    --frontend-dir) FRONTEND_DIR="${2:-}"; shift 2 ;;
    --backend-port) BACKEND_PORT="${2:-}"; shift 2 ;;
    --frontend-port) FRONTEND_PORT="${2:-}"; shift 2 ;;
    --frontend)     START_FRONTEND=true; shift ;;
    --native)       FORCE_NATIVE=true; shift ;;   # 跳过 compose,直接进程起(快回路/CI/无 docker)
    --timeout)      TIMEOUT="${2:-}"; shift 2 ;;
    -h|--help)      grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "错误: 未知参数 '$1'" >&2; exit 2 ;;
  esac
done

command -v curl >/dev/null 2>&1 || { echo "错误: 缺 curl" >&2; exit 1; }
HAVE_JQ=false; command -v jq >/dev/null 2>&1 && HAVE_JQ=true

mkdir -p "$STATE_DIR" "$LOGDIR"
: > "$PIDFILE"
BACKEND_URL="http://127.0.0.1:$BACKEND_PORT"
FRONTEND_URL="http://127.0.0.1:$FRONTEND_PORT"
METHOD=""
COMPOSE=false

# 自动定位目录
[[ -z "$BACKEND_DIR" ]] && for d in backend server api-server app; do
  [[ -d "$ROOT/$d" ]] && { BACKEND_DIR="$ROOT/$d"; break; }
done
[[ -n "$BACKEND_DIR" && "$BACKEND_DIR" != /* ]] && BACKEND_DIR="$ROOT/$BACKEND_DIR"
[[ -z "$FRONTEND_DIR" ]] && for d in frontend web client app; do
  [[ -d "$ROOT/$d" && -f "$ROOT/$d/package.json" ]] && { FRONTEND_DIR="$ROOT/$d"; break; }
done
[[ -n "$FRONTEND_DIR" && "$FRONTEND_DIR" != /* ]] && FRONTEND_DIR="$ROOT/$FRONTEND_DIR"

health_ok() {
  local hp code
  for hp in /healthz /health /api/health /api/healthz /; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$BACKEND_URL$hp" 2>/dev/null || echo 000)
    [[ "$code" != "000" && "$code" -lt 500 ]] && return 0
  done
  return 1
}
wait_health() {
  local i
  for ((i=0; i<TIMEOUT; i++)); do
    health_ok && return 0
    sleep 1
  done
  return 1
}

# ---- 1. compose 优先 ------------------------------------------------------
COMPOSE_FILE=""
for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
  [[ -f "$ROOT/$f" ]] && { COMPOSE_FILE="$ROOT/$f"; break; }
done

if [[ "$FORCE_NATIVE" == false && -n "$COMPOSE_FILE" ]] && command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  echo "[stack-up] 用 docker compose 拉起($COMPOSE_FILE)" >&2
  METHOD="compose"; COMPOSE=true
  ( cd "$ROOT" && docker compose -f "$COMPOSE_FILE" up -d ) >"$LOGDIR/compose.log" 2>&1
  echo "compose" >> "$PIDFILE"
else
  # ---- 2. native 兜底 -----------------------------------------------------
  METHOD="native"
  if [[ -n "$BACKEND_DIR" && -d "$BACKEND_DIR" ]]; then
    echo "[stack-up] native 起后端($BACKEND_DIR)" >&2
    if [[ -f "$BACKEND_DIR/app/main.py" || -f "$BACKEND_DIR/main.py" ]]; then
      # python / uvicorn
      local_mod="app.main:app"; [[ -f "$BACKEND_DIR/main.py" && ! -f "$BACKEND_DIR/app/main.py" ]] && local_mod="main:app"
      (
        cd "$BACKEND_DIR"
        [[ -f .venv/bin/activate ]] && source .venv/bin/activate 2>/dev/null
        [[ -f .env.example && ! -f .env ]] && cp .env.example .env 2>/dev/null
        exec python -m uvicorn "$local_mod" --host 127.0.0.1 --port "$BACKEND_PORT" --log-level warning
      ) >"$LOGDIR/backend.log" 2>&1 &
      echo $! >> "$PIDFILE"
    elif [[ -f "$BACKEND_DIR/package.json" ]]; then
      local_scr="start"; grep -q '"dev"' "$BACKEND_DIR/package.json" && local_scr="dev"
      ( cd "$BACKEND_DIR"; exec env PORT="$BACKEND_PORT" npm run "$local_scr" ) >"$LOGDIR/backend.log" 2>&1 &
      echo $! >> "$PIDFILE"
    elif [[ -f "$BACKEND_DIR/main.go" ]]; then
      ( cd "$BACKEND_DIR"; exec env PORT="$BACKEND_PORT" go run . ) >"$LOGDIR/backend.log" 2>&1 &
      echo $! >> "$PIDFILE"
    else
      echo "[stack-up] ⚠️ 后端目录识别不出启动方式($BACKEND_DIR),跳过 native boot" >&2
    fi
  else
    echo "[stack-up] ⚠️ 找不到后端目录,无法 native boot" >&2
  fi
fi

# ---- 3. 等健康 ------------------------------------------------------------
BACKEND_READY=false
if wait_health; then
  BACKEND_READY=true
  echo "[stack-up] 后端就绪 $BACKEND_URL" >&2
else
  echo "[stack-up] ✗ 后端 ${TIMEOUT}s 内没起来,见 $LOGDIR/backend.log|compose.log" >&2
fi

# ---- 4. 写前端 env 指向真后端 ---------------------------------------------
if [[ -n "$FRONTEND_DIR" && -d "$FRONTEND_DIR" ]]; then
  {
    echo "# 由 stack-up.sh 写入 —— 联调时前端指向真后端(非 mock)"
    echo "NEXT_PUBLIC_API_BASE=$BACKEND_URL"
    echo "NEXT_PUBLIC_API_URL=$BACKEND_URL"
    echo "VITE_API_BASE=$BACKEND_URL"
    echo "VITE_API_URL=$BACKEND_URL"
    echo "REACT_APP_API_BASE=$BACKEND_URL"
  } > "$FRONTEND_DIR/.env.local"
  echo "[stack-up] 写前端 env → $FRONTEND_DIR/.env.local(指向 $BACKEND_URL)" >&2
fi

# ---- 5. 可选起前端 --------------------------------------------------------
FRONTEND_STARTED=false
if $START_FRONTEND && [[ -n "$FRONTEND_DIR" && -f "$FRONTEND_DIR/package.json" ]]; then
  local_fscr="dev"; grep -q '"dev"' "$FRONTEND_DIR/package.json" || local_fscr="start"
  echo "[stack-up] 起前端($local_fscr,:$FRONTEND_PORT)" >&2
  ( cd "$FRONTEND_DIR"; exec env PORT="$FRONTEND_PORT" npm run "$local_fscr" ) >"$LOGDIR/frontend.log" 2>&1 &
  echo $! >> "$PIDFILE"
  for ((i=0; i<TIMEOUT; i++)); do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$FRONTEND_URL" 2>/dev/null || echo 000)
    [[ "$code" != "000" ]] && { FRONTEND_STARTED=true; break; }
    sleep 1
  done
fi

# ---- 6. 写 state ----------------------------------------------------------
PIDS_JSON="[]"
if $HAVE_JQ; then
  while IFS= read -r p; do
    [[ -n "$p" ]] && PIDS_JSON=$(jq -c --arg p "$p" '. + [$p]' <<<"$PIDS_JSON")
  done < "$PIDFILE"
  jq -n \
    --arg method "$METHOD" --arg backend_url "$BACKEND_URL" \
    --argjson backend_ready "$BACKEND_READY" \
    --arg frontend_url "$FRONTEND_URL" --argjson frontend_started "$FRONTEND_STARTED" \
    --argjson compose "$COMPOSE" --argjson pids "$PIDS_JSON" \
    --arg notes "$( $BACKEND_READY && echo '栈已起,可跑 seam/contract/integration' || echo '后端未起,联调门会判 FAIL' )" \
    '{method:$method, backend_url:$backend_url, backend_ready:$backend_ready,
      frontend_url:$frontend_url, frontend_started:$frontend_started,
      compose:$compose, pids:$pids, notes:$notes}' > "$OUT"
else
  echo "{\"method\":\"$METHOD\",\"backend_url\":\"$BACKEND_URL\",\"backend_ready\":$BACKEND_READY}" > "$OUT"
fi

echo "[stack-up] 写出: $OUT" >&2
$HAVE_JQ && jq '{method, backend_url, backend_ready, frontend_started, compose}' "$OUT" >&2

$BACKEND_READY && exit 0 || exit 1
