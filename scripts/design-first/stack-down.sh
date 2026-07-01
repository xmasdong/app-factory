#!/usr/bin/env bash
# ============================================================================
# stack-down.sh — 收摊 stack-up.sh 拉起的全栈(联调完清理)
#
# 读 .claude/state/stack.pids:
#   - "compose" 行 → docker compose down
#   - 数字 pid    → kill(优雅 TERM,再 KILL 兜底)
# 幂等:文件不存在 / 进程已退 都安静返回 0。
# ============================================================================
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE_DIR="$ROOT/.claude/state"
PIDFILE="$STATE_DIR/stack.pids"

[[ -f "$PIDFILE" ]] || { echo "[stack-down] 无 stack.pids,无需收摊" >&2; exit 0; }

COMPOSE_FILE=""
for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
  [[ -f "$ROOT/$f" ]] && { COMPOSE_FILE="$ROOT/$f"; break; }
done

while IFS= read -r entry; do
  [[ -z "$entry" ]] && continue
  if [[ "$entry" == "compose" ]]; then
    if [[ -n "$COMPOSE_FILE" ]] && command -v docker >/dev/null 2>&1; then
      echo "[stack-down] docker compose down" >&2
      ( cd "$ROOT" && docker compose -f "$COMPOSE_FILE" down ) >/dev/null 2>&1 || true
    fi
  elif [[ "$entry" =~ ^[0-9]+$ ]]; then
    if kill -0 "$entry" 2>/dev/null; then
      echo "[stack-down] kill $entry" >&2
      kill "$entry" 2>/dev/null || true
      # 给 2s 优雅退,再 KILL
      for _ in 1 2; do kill -0 "$entry" 2>/dev/null || break; sleep 1; done
      kill -9 "$entry" 2>/dev/null || true
    fi
  fi
done < "$PIDFILE"

# 兜底:清掉可能残留的 uvicorn(本项目 backend)
pkill -f "uvicorn .*--port" 2>/dev/null || true

rm -f "$PIDFILE"
echo "[stack-down] 收摊完成" >&2
exit 0
