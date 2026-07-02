#!/usr/bin/env bash
# ============================================================================
# ios-sim-harness.sh — 原生 iOS/watchOS 模拟器回路(编译→装→跑→截图,全 CLI)
#
# 目标:把「原生端能不能真跑」从 honor system 变成机械证据。
#   xcodebuild 编译(模拟器目标,免签名)→ 找 .app → 读 bundle id
#   → simctl boot → install → launch → 截图 N 张
#   → 写 .claude/state/native-run.json(gate sg_app_native_run 读)
#
# 已在真产品验证:Daily Sudoku Watch App(xcodebuild → watchOS sim → 真主界面截图)。
# 注意:这些游戏 iOS 侧常是 watch-only shell(ITSWatchOnlyContainer)装不上 iPhone,
#       手表游戏一律 --platform watchos。
#
# 用法:
#   ios-sim-harness.sh --project <x.xcodeproj> --scheme <名> \
#     [--platform ios|watchos]  (默认 ios)
#     [--device <模拟器名>]     (默认: ios=iPhone 17 / watchos=Apple Watch Series 11 (46mm))
#     [--shots N]               (截图张数,默认 1,间隔 3s —— 多张可看进入动画后状态)
#     [--launch-wait S]         (launch 后等几秒再截,默认 4)
#     [--keep-booted]           (跑完不关模拟器)
#     [--workspace <x.xcworkspace>] (代替 --project)
#
# 产物:
#   .claude/state/native-run.json:
#     { result:"PASS"|"FAIL", step:"build|install|launch|screenshot|done",
#       scheme, platform, device, bundle_id, app_path,
#       screenshots:[...], notes }
#   截图:.claude/state/native-screens/<scheme-slug>-N.png
#
# 读 $CLAUDE_PROJECT_DIR 当项目根,缺则 pwd。依赖:xcodebuild / xcrun simctl / plutil|PlistBuddy / jq。
# ============================================================================
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE_DIR="$ROOT/.claude/state"
OUT="$STATE_DIR/native-run.json"
SHOT_DIR="$STATE_DIR/native-screens"

PROJECT=""; WORKSPACE=""; SCHEME=""; PLATFORM="ios"; DEVICE=""
SHOTS=1; LAUNCH_WAIT=4; KEEP_BOOTED=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)     PROJECT="${2:-}"; shift 2 ;;
    --workspace)   WORKSPACE="${2:-}"; shift 2 ;;
    --scheme)      SCHEME="${2:-}"; shift 2 ;;
    --platform)    PLATFORM="${2:-}"; shift 2 ;;
    --device)      DEVICE="${2:-}"; shift 2 ;;
    --shots)       SHOTS="${2:-}"; shift 2 ;;
    --launch-wait) LAUNCH_WAIT="${2:-}"; shift 2 ;;
    --keep-booted) KEEP_BOOTED=true; shift ;;
    -h|--help)     grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "错误: 未知参数 '$1'" >&2; exit 2 ;;
  esac
done

die_json() { # $1=step $2=notes → 写 FAIL JSON 并退出 1
  mkdir -p "$STATE_DIR"
  jq -n --arg step "$1" --arg scheme "$SCHEME" --arg platform "$PLATFORM" \
        --arg device "${DEVICE:-}" --arg notes "$2" \
    '{result:"FAIL", step:$step, scheme:$scheme, platform:$platform, device:$device,
      bundle_id:null, app_path:null, screenshots:[], notes:$notes}' > "$OUT"
  echo "[ios-sim] ✗ $1 失败: $2" >&2
  exit 1
}

command -v xcodebuild >/dev/null 2>&1 || die_json env "缺 xcodebuild (装 Xcode)"
command -v jq >/dev/null 2>&1 || { echo "缺 jq" >&2; exit 1; }
[[ -n "$SCHEME" ]] || die_json args "缺 --scheme"
[[ -n "$PROJECT$WORKSPACE" ]] || die_json args "缺 --project 或 --workspace"

case "$PLATFORM" in
  ios)     DEST_PLATFORM="iOS Simulator";     DEVICE="${DEVICE:-iPhone 17}" ;;
  watchos) DEST_PLATFORM="watchOS Simulator"; DEVICE="${DEVICE:-Apple Watch Series 11 (46mm)}" ;;
  *) die_json args "--platform 只支持 ios|watchos (得到 $PLATFORM)" ;;
esac

SRC_ARGS=()
[[ -n "$PROJECT" ]]   && SRC_ARGS+=( -project "$PROJECT" )
[[ -n "$WORKSPACE" ]] && SRC_ARGS+=( -workspace "$WORKSPACE" )

DD="$(mktemp -d -t ios-sim-dd)"
trap 'rm -rf "$DD"' EXIT
mkdir -p "$STATE_DIR" "$SHOT_DIR"

# ---- 1. build ---------------------------------------------------------------
echo "[ios-sim] build: $SCHEME → $DEST_PLATFORM,$DEVICE" >&2
BUILD_LOG="$DD/build.log"
if ! xcodebuild "${SRC_ARGS[@]}" -scheme "$SCHEME" \
      -destination "platform=$DEST_PLATFORM,name=$DEVICE" \
      -configuration Debug -derivedDataPath "$DD" \
      CODE_SIGNING_ALLOWED=NO build >"$BUILD_LOG" 2>&1; then
  tail -20 "$BUILD_LOG" >&2
  die_json build "xcodebuild 失败, 见上方日志尾"
fi
echo "[ios-sim] BUILD SUCCEEDED" >&2

# ---- 2. 找 .app + bundle id -------------------------------------------------
APP="$(find "$DD/Build/Products" -maxdepth 2 -name '*.app' 2>/dev/null | head -1)"
[[ -n "$APP" ]] || die_json build "编译成功但没找到 .app 产物"
BID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist" 2>/dev/null)"
[[ -n "$BID" ]] || die_json build "读不到 CFBundleIdentifier"
# watch-only shell 检测(iOS 平台装 shell 会失败,提前给明确报错)
if [[ "$PLATFORM" == "ios" ]] && /usr/libexec/PlistBuddy -c 'Print :ITSWatchOnlyContainer' "$APP/Info.plist" >/dev/null 2>&1; then
  die_json install "该 app 是 watch-only shell (ITSWatchOnlyContainer), 不能装 iPhone — 用 --platform watchos + Watch App scheme"
fi
echo "[ios-sim] app=$APP bid=$BID" >&2

# ---- 3. boot 模拟器 ----------------------------------------------------------
UDID="$(xcrun simctl list devices available -j | jq -r --arg n "$DEVICE" \
  '.devices | to_entries[] | .value[] | select(.name==$n) | .udid' | head -1)"
[[ -n "$UDID" ]] || die_json boot "没找到可用模拟器: $DEVICE (simctl list devices available 查名字)"
xcrun simctl boot "$UDID" 2>/dev/null || true   # 已启动则忽略
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || die_json boot "模拟器 boot 超时: $DEVICE"

# ---- 4. install + launch ----------------------------------------------------
xcrun simctl install "$UDID" "$APP" 2>&1 || die_json install "simctl install 失败"
xcrun simctl launch "$UDID" "$BID" >/dev/null 2>&1 || die_json launch "simctl launch 失败 ($BID)"
echo "[ios-sim] launched $BID" >&2
sleep "$LAUNCH_WAIT"

# ---- 5. 截图 -----------------------------------------------------------------
SLUG="$(printf '%s' "$SCHEME" | tr ' /' '--' | tr '[:upper:]' '[:lower:]')"
SHOTS_JSON="[]"
for ((i=1; i<=SHOTS; i++)); do
  P="$SHOT_DIR/${SLUG}-${i}.png"
  if xcrun simctl io "$UDID" screenshot "$P" >/dev/null 2>&1 && [[ $(wc -c <"$P") -gt 5000 ]]; then
    SHOTS_JSON=$(jq -c --arg p "$P" '. + [$p]' <<<"$SHOTS_JSON")
    echo "[ios-sim] screenshot $i ✓ ($(wc -c <"$P" | tr -d ' ') B)" >&2
  else
    die_json screenshot "截图 $i 失败或 <5KB (可能白屏/崩溃)"
  fi
  (( i < SHOTS )) && sleep 3
done

$KEEP_BOOTED || xcrun simctl shutdown "$UDID" 2>/dev/null || true

# ---- 6. 写 state -------------------------------------------------------------
jq -n --arg scheme "$SCHEME" --arg platform "$PLATFORM" --arg device "$DEVICE" \
      --arg bid "$BID" --arg app "$APP" --argjson shots "$SHOTS_JSON" \
  '{result:"PASS", step:"done", scheme:$scheme, platform:$platform, device:$device,
    bundle_id:$bid, app_path:$app, screenshots:$shots,
    notes:"编译→boot→install→launch→截图 全链真跑通"}' > "$OUT"
echo "[ios-sim] 写出: $OUT" >&2
jq '{result, scheme, platform, device, bundle_id, shots:(.screenshots|length)}' "$OUT" >&2
exit 0
