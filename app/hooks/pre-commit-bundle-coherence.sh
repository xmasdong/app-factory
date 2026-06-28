#!/bin/bash
# PreToolUse hook: commit 前校验 bundle id 在所有配置文件中完全一致
# 触发: Bash, command 匹配 ^git commit
# 退出码: 0=放行, 2=阻塞
#
# 逻辑:
#   1. PROJECT_TYPE 不是 app → 放行
#   2. 从 spec.md 的 NAMING-LOCK 章节 grep bundle id 锚定值
#   3. 扫所有可能出现 bundle id 的配置文件
#   4. 全部值 sort -u, 数量必须为 1, 且必须等于锚定值 (或所有值一致)
#   5. 不一致 → 列出冲突文件 + 阻塞

set -u

INPUT=$(cat 2>/dev/null || true)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)

# 只拦截 git commit
if ! echo "$COMMAND" | grep -qE '^[[:space:]]*git[[:space:]]+commit'; then
  exit 0
fi

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATUS_FILE="$ROOT/docs/status.md"
SPEC_FILE="$ROOT/docs/spec.md"

# --- 1. PROJECT_TYPE 判定 ---
if [[ ! -f "$STATUS_FILE" ]]; then
  exit 0
fi
PROJECT_TYPE=$(grep -oE 'PROJECT_TYPE:[[:space:]]*[A-Za-z_-]+' "$STATUS_FILE" 2>/dev/null \
  | head -1 | awk -F: '{gsub(/[[:space:]]/,"",$2); print $2}')
if [[ "$PROJECT_TYPE" != "app" ]]; then
  exit 0
fi

# 没有 spec.md → 让别的 gate 处理
if [[ ! -f "$SPEC_FILE" ]]; then
  exit 0
fi

# --- 2. 从 NAMING-LOCK 章节抽 bundle id 锚定值 ---
# 章节范围: ## NAMING-LOCK 到下一个 ^## 之间
ANCHOR_BUNDLE=$(awk '
  /^## *NAMING-LOCK/{flag=1; next}
  /^## /{flag=0}
  flag && /[Bb]undle[[:space:]]*ID|bundle id/ {in_section=1}
  flag && in_section && /value:/ {
    match($0, /value:[[:space:]]*[`"]?([^`"\n]+)[`"]?/, arr)
    if (arr[1]) { print arr[1]; exit }
  }
' "$SPEC_FILE" 2>/dev/null | tr -d '`"' | awk '{$1=$1;print}')

# Fallback: 用 grep 兼容 macOS awk
if [[ -z "$ANCHOR_BUNDLE" ]]; then
  ANCHOR_BUNDLE=$(awk '/^## *NAMING-LOCK/,/^## [^N]/' "$SPEC_FILE" 2>/dev/null \
    | grep -A1 -iE 'bundle[[:space:]]*id' \
    | grep -oE 'value:[[:space:]]*[`"]?[a-zA-Z0-9._-]+' \
    | head -1 | sed -E 's/value:[[:space:]]*[`"]?//')
fi

if [[ -z "$ANCHOR_BUNDLE" || "$ANCHOR_BUNDLE" == "<TBD>" ]]; then
  # NAMING-LOCK 没填 bundle id → 让 A-GATE 0 阻塞 commit
  # shellcheck disable=SC1091
  source "$ROOT/.claude/hooks/_lib.sh" 2>/dev/null || true
  MSG="A-GATE 0 不全: spec.md NAMING-LOCK 缺 bundle id (value 字段为空或 <TBD>).
commit 之前必须把 bundle id 锁定. 先 /app-anchor."
  if declare -F emit_blocked >/dev/null 2>&1; then
    emit_blocked "pre-commit-bundle-coherence" "bundle id 未锁定" "$MSG"
  else
    echo "$MSG" >&2
  fi
  exit 2
fi

# --- 3. 扫配置文件 ---
declare -a FILES_TO_CHECK=()
declare -a FOUND_BUNDLES=()
declare -a CONFLICTS=()

# 候选文件 pattern (用 find)
while IFS= read -r f; do
  [[ -f "$f" ]] && FILES_TO_CHECK+=("$f")
done < <(find "$ROOT" \
  \( -name 'Info.plist' -o -name '*.entitlements' \
     -o -name 'build.gradle' -o -name 'build.gradle.kts' \
     -o -name 'AndroidManifest.xml' \
     -o -name 'app.config.js' -o -name 'app.config.ts' -o -name 'app.json' \
     -o -name 'google-services.json' -o -name 'GoogleService-Info.plist' \
     -o -name 'project.pbxproj' \) \
  -not -path '*/node_modules/*' \
  -not -path '*/.git/*' \
  -not -path '*/build/*' \
  -not -path '*/dist/*' \
  -not -path '*/Pods/*' \
  2>/dev/null)

# 没找到任何配置文件 → 早期项目, 跳过 (没东西冲突)
if [[ ${#FILES_TO_CHECK[@]} -eq 0 ]]; then
  exit 0
fi

# bundle id 形如 reverse-DNS (com.foo.bar), 抽不同文件里的实际值
for f in "${FILES_TO_CHECK[@]}"; do
  basename_f=$(basename "$f")
  case "$basename_f" in
    Info.plist|*.entitlements|GoogleService-Info.plist)
      # plist: <key>CFBundleIdentifier</key><string>com.x.y</string>
      val=$(grep -A1 -E 'CFBundleIdentifier|BUNDLE_ID' "$f" 2>/dev/null \
        | grep -oE '<string>[^<]+</string>' | head -1 | sed -E 's/<\/?string>//g')
      [[ -z "$val" ]] && val=$(grep -oE '"BUNDLE_ID"[[:space:]]*:[[:space:]]*"[^"]+"' "$f" 2>/dev/null | head -1 | sed -E 's/.*"([^"]+)"$/\1/')
      ;;
    build.gradle|build.gradle.kts)
      val=$(grep -oE 'applicationId[[:space:]=]+["'\''][^"'\'']+["'\'']' "$f" 2>/dev/null \
        | head -1 | sed -E 's/.*["'\'']([^"'\'']+)["'\'']/\1/')
      ;;
    AndroidManifest.xml)
      val=$(grep -oE 'package[[:space:]]*=[[:space:]]*"[^"]+"' "$f" 2>/dev/null | head -1 | sed -E 's/.*"([^"]+)"/\1/')
      ;;
    app.config.js|app.config.ts|app.json)
      val=$(grep -oE '(bundleIdentifier|package)["[:space:]]*:[[:space:]]*"[^"]+"' "$f" 2>/dev/null | head -1 | sed -E 's/.*"([^"]+)"$/\1/')
      ;;
    google-services.json)
      val=$(grep -oE '"package_name"[[:space:]]*:[[:space:]]*"[^"]+"' "$f" 2>/dev/null | head -1 | sed -E 's/.*"([^"]+)"$/\1/')
      ;;
    project.pbxproj)
      val=$(grep -oE 'PRODUCT_BUNDLE_IDENTIFIER[[:space:]=]+[^;]+' "$f" 2>/dev/null \
        | head -1 | sed -E 's/.*=[[:space:]]*([a-zA-Z0-9._-]+).*/\1/' | tr -d '"')
      ;;
    *)
      val=""
      ;;
  esac

  if [[ -n "$val" ]]; then
    FOUND_BUNDLES+=("$val")
    if [[ "$val" != "$ANCHOR_BUNDLE" ]]; then
      CONFLICTS+=("$f → $val (期望 $ANCHOR_BUNDLE)")
    fi
  fi
done

# --- 4. 判定 ---
UNIQUE_COUNT=$(printf '%s\n' "${FOUND_BUNDLES[@]}" | sort -u | wc -l | tr -d ' ')

if [[ "${#FOUND_BUNDLES[@]}" -eq 0 ]]; then
  exit 0  # 配置文件存在但没识别到 bundle id, 不阻塞 (可能是早期 placeholder)
fi

if [[ "${#CONFLICTS[@]}" -gt 0 || "$UNIQUE_COUNT" -gt 1 ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/.claude/hooks/_lib.sh" 2>/dev/null || true
  MSG="bundle id 跨文件不一致, commit 被阻塞.

NAMING-LOCK 锚定 bundle id: $ANCHOR_BUNDLE

冲突文件 (${#CONFLICTS[@]} 处):
$(printf '  - %s\n' "${CONFLICTS[@]}")

修复方式 (选一):
  A. 全部替换为锚定值 ($ANCHOR_BUNDLE) → 直接改文件
  B. 锚定值本身要改 → 先回 A-GATE 0 重新锁定 NAMING-LOCK, 再统一改所有文件
  C. 接受不一致 (强烈不建议) → 需在 spec.md 显式注明白名单, 并 export AI_RULES_BUNDLE_COHERENCE_SKIP=1

ViraSnap 教训: 重命名 5 处错位上线后不可逆, 直接报废 bundle id."
  if declare -F emit_blocked >/dev/null 2>&1; then
    emit_blocked "pre-commit-bundle-coherence" "bundle id 跨文件不一致" "$MSG"
  else
    echo "$MSG" >&2
  fi

  # 逃生舱
  if [[ "${AI_RULES_BUNDLE_COHERENCE_SKIP:-0}" == "1" ]]; then
    echo "⚠️ AI_RULES_BUNDLE_COHERENCE_SKIP=1, 放行 (但仍记录原因到 last-stop-reason)" >&2
    exit 0
  fi
  exit 2
fi

exit 0
