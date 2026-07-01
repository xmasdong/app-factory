#!/usr/bin/env bash
# ============================================================================
# env-probe.sh — 环境预检(技术栈决策的地基)
#
# 别在真空里推荐技术栈。先扫机器【真装了什么工具链】+【哪些 MCP 授权/配置了】,
# 再据此约束推荐:装了 Xcode 才推 iOS 原生;装了 flutter 且要全端才推 Flutter;
# 装了 wrangler 才把 Cloudflare Workers/D1/Container 当可用后端;Supabase 要先配 MCP。
# 没装/没授权的栈 → 标「需先装 X / 需先授权 Y MCP」,不当默认推荐。
#
# 产出:
#   .claude/state/env-probe.json  —— 机器可读, 喂 lockdown/backend-forge 决策矩阵 + gate
#   stdout                        —— 人读摘要
#
# 读 $CLAUDE_PROJECT_DIR 当项目根,缺则 pwd。依赖:jq(缺则退化为 present-only)。
# 只读探测,绝不修改系统 / 不打印任何 token 或密钥。
# ============================================================================
set -uo pipefail   # 注意:不 set -e —— 探测缺失工具是常态,不该中断

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE_DIR="$ROOT/.claude/state"
OUT="$STATE_DIR/env-probe.json"
mkdir -p "$STATE_DIR" 2>/dev/null

HAVE_JQ=false
command -v jq >/dev/null 2>&1 && HAVE_JQ=true

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

# ---- 工具链探测 -----------------------------------------------------------
# present = command -v;version 尽力而为(只对快命令取,慢命令如 flutter 只标 present)
present() { command -v "$1" >/dev/null 2>&1; }
tool_path() { command -v "$1" 2>/dev/null || echo ""; }
quick_ver() {
  # $1=命令行(仅对快速 --version 用);首个数字版本;失败/慢 → 空
  local out
  out=$("$@" 2>/dev/null | head -1 2>/dev/null) || out=""
  printf '%s' "$out" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1
}

# 探测清单:名字 → 是否取版本(慢的标 no)
TOOLS_JSON="{}"
add_tool() {
  local name="$1" getver="$2" ; shift 2
  local p="false" path="" ver=""
  if present "$name"; then
    p="true"; path="$(tool_path "$name")"
    [[ "$getver" == "yes" ]] && ver="$(quick_ver "$@")"
  fi
  if $HAVE_JQ; then
    TOOLS_JSON=$(jq -c --arg n "$name" --argjson pr "$p" --arg pa "$path" --arg v "$ver" \
      '.[$n]={present:$pr, path:$pa, version:$v}' <<<"$TOOLS_JSON")
  fi
}

# 移动/跨端
add_tool flutter    no                       # flutter --version 慢, 只标 present
add_tool dart       yes  dart --version
add_tool xcodebuild yes  xcodebuild -version
add_tool swift      no
add_tool pod        yes  pod --version        # CocoaPods (iOS)
add_tool adb        no                        # Android platform-tools
add_tool gradle     no
# Web / JS
add_tool node       yes  node --version
add_tool npm        yes  npm --version
add_tool pnpm       yes  pnpm --version
add_tool bun        yes  bun --version
# 后端语言
add_tool python3    yes  python3 --version
add_tool go         yes  go version
add_tool cargo      yes  cargo --version      # Rust
add_tool java       no
add_tool ruby       yes  ruby --version
# BaaS / 边缘 / 部署 CLI
add_tool wrangler   yes  wrangler --version   # Cloudflare
add_tool supabase   yes  supabase --version
add_tool firebase   no
add_tool vercel     no
add_tool docker     yes  docker --version
add_tool git        yes  git --version

_present() { $HAVE_JQ && [[ "$(jq -r --arg n "$1" '.[$n].present' <<<"$TOOLS_JSON")" == "true" ]]; }

# ---- MCP 探测(读 ~/.claude.json + 项目 .mcp.json,只列名不碰密钥)-----------
MCP_CONFIGURED='[]'
collect_mcp() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  $HAVE_JQ || return 0
  local keys
  keys=$(jq -r '
    ((.mcpServers // {}) | keys[]),
    ((.projects // {}) | to_entries[] | (.value.mcpServers // {}) | keys[])
  ' "$f" 2>/dev/null | sort -u)
  while IFS= read -r k; do
    [[ -n "$k" ]] || continue
    MCP_CONFIGURED=$(jq -c --arg k "$k" '. + [$k] | unique' <<<"$MCP_CONFIGURED")
  done <<<"$keys"
}
collect_mcp "$HOME/.claude.json"
collect_mcp "$ROOT/.mcp.json"
collect_mcp "$ROOT/.claude/settings.json"

mcp_has() {
  # 名字模糊匹配(supabase / cloudflare / firebase / neon ...)
  $HAVE_JQ || return 1
  jq -e --arg pat "$1" 'any(.[]; ascii_downcase | test($pat))' <<<"$MCP_CONFIGURED" >/dev/null 2>&1
}

# ---- 推导 capabilities ----------------------------------------------------
cap() { [[ "$1" == "true" ]] && echo true || echo false; }
CAP_IOS=$( _present xcodebuild && _present swift && echo true || echo false )
CAP_ANDROID=$( { _present adb || _present gradle; } && echo true || echo false )
CAP_FLUTTER=$( _present flutter && _present dart && echo true || echo false )
CAP_WEB=$( _present node && echo true || echo false )

# ---- 后端可选项(available + why + how-to-enable)--------------------------
BACKEND_JSON='[]'
add_backend() { # option available why how
  $HAVE_JQ || return 0
  BACKEND_JSON=$(jq -c \
    --arg o "$1" --argjson a "$2" --arg w "$3" --arg h "$4" \
    '. + [{option:$o, available:$a, why:$w, how_to_enable:$h}]' <<<"$BACKEND_JSON")
}
# Cloudflare(装了 wrangler 就可用 Workers/Pages/D1/R2/Queues/Container;AI 基建友好)
if _present wrangler; then
  add_backend "cloudflare" true "wrangler 就绪 → Workers/Pages/D1/R2/Queues/Container 可用;AI 基建友好(Workers AI/Vectorize/AI Gateway)" ""
else
  add_backend "cloudflare" false "缺 wrangler" "npm i -g wrangler(或 brew install cloudflare-wrangler2)"
fi
# Supabase(需 CLI 或 已配置并授权 Supabase MCP)
if _present supabase || mcp_has "supabase"; then
  add_backend "supabase" true "$( _present supabase && echo 'supabase CLI 就绪' ; mcp_has supabase && echo ' + Supabase MCP 已配置' )" ""
else
  add_backend "supabase" false "缺 supabase CLI 且未配置 Supabase MCP" "brew install supabase/tap/supabase;并在 Claude 里配置+授权 Supabase MCP 后才算就绪(RLS 抗越权是其卖点)"
fi
# Firebase
if _present firebase || mcp_has "firebase"; then
  add_backend "firebase" true "firebase-tools/MCP 就绪" ""
else
  add_backend "firebase" false "缺 firebase-tools" "npm i -g firebase-tools"
fi
# 自建(docker) + 语言运行时
_present docker  && add_backend "docker-selfhost" true "docker 就绪 → 可自建 Postgres/Redis + 任意后端容器" "" \
               || add_backend "docker-selfhost" false "缺 docker" "安装 Docker Desktop / colima"
_present python3 && add_backend "python-fastapi" true "python3 就绪 → FastAPI/Django/Flask" "" || true
_present node    && add_backend "node-server"     true "node 就绪 → Express/NestJS/Hono" ""       || true
_present go      && add_backend "go-server"       true "go 就绪 → net/http/Gin/Echo" ""            || true

# ---- publish-target → 栈建议(环境约束版)----------------------------------
# 只列环境已就绪的;未就绪的说清缺什么
STACK_JSON='{}'
if $HAVE_JQ; then
  ios_rec=$( [[ "$CAP_IOS" == true ]] && echo "SwiftUI 原生(xcodebuild+swift 就绪)" || echo "需装 Xcode(命令行工具)才能出 iOS 原生;或改 Flutter/RN 走跨端" )
  and_rec=$( [[ "$CAP_ANDROID" == true ]] && echo "Kotlin/Compose(Android SDK 就绪);确认 Android Studio/gradle" || echo "需装 Android SDK(adb/gradle)" )
  all_rec=$( [[ "$CAP_FLUTTER" == true ]] && echo "Flutter(flutter+dart 就绪)—— 一套码 iOS/Android/Web/Desktop,批量换皮/微创新出海首选" || echo "全端首选 Flutter,但缺 flutter SDK,需先装" )
  web_rec=$( [[ "$CAP_WEB" == true ]] && echo "Next.js/React 或 Vite(node 就绪);PWA 可覆移动 Web" || echo "需装 node" )
  STACK_JSON=$(jq -n \
    --arg ios "$ios_rec" --arg and "$and_rec" --arg all "$all_rec" --arg web "$web_rec" \
    '{ios_only:$ios, android_only:$and, all_platforms:$all, web_only:$web}')
fi

# ---- 写 env-probe.json ----------------------------------------------------
if $HAVE_JQ; then
  jq -n \
    --arg os "$OS" --arg arch "$ARCH" \
    --argjson toolchains "$TOOLS_JSON" \
    --argjson mcp "$MCP_CONFIGURED" \
    --argjson cap_ios "$CAP_IOS" --argjson cap_and "$CAP_ANDROID" \
    --argjson cap_flutter "$CAP_FLUTTER" --argjson cap_web "$CAP_WEB" \
    --argjson backend "$BACKEND_JSON" \
    --argjson stack "$STACK_JSON" \
    '{
      os:$os, arch:$arch,
      toolchains:$toolchains,
      mcp_servers:{configured:$mcp,
        backend_relevant:{
          supabase:($mcp|any(ascii_downcase|test("supabase"))),
          cloudflare:($mcp|any(ascii_downcase|test("cloudflare|wrangler"))),
          firebase:($mcp|any(ascii_downcase|test("firebase")))
        }},
      capabilities:{
        build_ios_native:$cap_ios,
        build_android_native:$cap_and,
        build_cross_platform_flutter:$cap_flutter,
        build_web:$cap_web
      },
      stack_by_publish_target:$stack,
      backend_options:$backend,
      note:"环境预检快照;发布目标须问用户(全端→Flutter)。不可用后端标 how_to_enable。"
    }' > "$OUT"
else
  # 无 jq 兜底:present-only 文本
  echo "{\"os\":\"$OS\",\"arch\":\"$ARCH\",\"note\":\"缺 jq,仅探测,详见 stdout\"}" > "$OUT"
fi

# ---- 人读摘要 -------------------------------------------------------------
echo "════════ 环境预检 (env-probe) ════════"
echo "OS/Arch: $OS/$ARCH"
echo ""
echo "已装工具链:"
if $HAVE_JQ; then
  jq -r '.toolchains | to_entries[] | select(.value.present==true) | "  ✓ \(.key)\(if .value.version!="" then " ("+.value.version+")" else "" end)"' "$OUT"
  echo ""
  echo "未装(相关):"
  jq -r '.toolchains | to_entries[] | select(.value.present==false) | "  ✗ \(.key)"' "$OUT" | tr '\n' ' '; echo ""
  echo ""
  echo "构建能力:"
  jq -r '.capabilities | to_entries[] | "  \(if .value then "✓" else "✗" end) \(.key)"' "$OUT"
  echo ""
  echo "已配置 MCP: $(jq -rc '.mcp_servers.configured' "$OUT")"
  echo ""
  echo "后端可选项:"
  jq -r '.backend_options[] | "  \(if .available then "✓" else "✗" end) \(.option) — \(.why)\(if .available then "" else "  ⟶ "+.how_to_enable end)"' "$OUT"
  echo ""
  echo "发布目标→栈(须问用户确定目标):"
  jq -r '.stack_by_publish_target | to_entries[] | "  • \(.key): \(.value)"' "$OUT"
fi
echo ""
echo "已写: $OUT"
