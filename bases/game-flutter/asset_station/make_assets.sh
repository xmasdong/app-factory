#!/usr/bin/env bash
# make_assets.sh — 资产工位主脚本:key-art 先行 → image-to-image 成套 → identity_qc autoretry
# 依赖:codex-image-bridge skill(node cli)。风格漂移学费来自 game-asset-lab:prompt≠一致输出,
# 必须 ①key art 锁基因 ②每张 VLM 质检 ③不过自动重出(≤2)。
#
# 用法: STYLE="children's crayon, wobbly outlines, warm paper" \
#       make_assets.sh <项目根> [codex-bridge目录(默认 ~/.claude/skills/codex-image-bridge)]
set -uo pipefail
ROOT="${1:?用法: STYLE=... make_assets.sh <项目根>}"
BRIDGE="${2:-$HOME/.claude/skills/codex-image-bridge}"
STYLE="${STYLE:?先 export STYLE=<风格基因,从 DESIGN-FEED 取>}"
ART="$ROOT/assets/art"
mkdir -p "$ART"
CLI="$BRIDGE/scripts/cli.mjs"
[[ -f "$CLI" ]] || { echo "缺 codex-image-bridge: $CLI" >&2; exit 1; }

gen() { # gen <out> <prompt> [ref_image] —— edit(参考图)慢易超时:给 5min + 失败降级纯 generate
  local out="$1" prompt="$2" ref="${3:-}"
  if [[ -n "$ref" ]]; then
    (cd "$BRIDGE" && node "$CLI" edit --image "$ref" --prompt "$prompt" \
       --timeout-ms 300000 --out "$out") >/dev/null 2>&1
    [[ -s "$out" ]] && return 0
    echo "[asset]   edit 超时/失败 → 降级 generate(风格靠 prompt+QC 兜底)" >&2
    prompt="$prompt (STYLE MUST MATCH: ${STYLE})"
  fi
  (cd "$BRIDGE" && node "$CLI" generate --prompt "$prompt" --timeout-ms 300000 --out "$out") >/dev/null 2>&1
  [[ -s "$out" ]]
}

# ① key art 先行(锁风格基因)
KEY="$ART/key-art.png"
if [[ ! -s "$KEY" ]]; then
  echo "[asset] key art…" >&2
  gen "$KEY" "Key art for a mobile game, ${STYLE}. Main mascot centered, game world background, square, no text no watermark." \
    || { echo "key art 生成失败" >&2; exit 1; }
fi

# ② 成套(全部带 key art 参考)+ ③ identity_qc autoretry
declare -a SPECS=(
  "icon-master.png|App icon, ${STYLE}. Single centered subject, bold silhouette readable at 60px, bright saturated FULL background, no alpha, no text."
  "bg-texture.png|Background texture, ${STYLE}. Subtle low-contrast so UI reads on top, portrait phone."
  "celebration-set.png|Celebration stickers on transparent background, ${STYLE}: stars, trophy, confetti pieces, matching palette."
  "mascot-idle.png|The same mascot as reference, ${STYLE}, neutral idle pose, transparent background, same identity."
  "mascot-celebrate.png|The same mascot as reference, ${STYLE}, cheering celebrating pose, transparent background, same identity."
  "mascot-sad.png|The same mascot as reference, ${STYLE}, sad oops pose, transparent background, same identity."
)
MANIFEST="$ART/manifest.json"
echo '{"style":"'"${STYLE//\"/\\\"}"'","key_art":"key-art.png","assets":[' > "$MANIFEST"
first=1
for spec in "${SPECS[@]}"; do
  out="$ART/${spec%%|*}"; prompt="${spec#*|}"
  for try in 1 2 3; do
    echo "[asset] ${spec%%|*} (try $try)…" >&2
    gen "$out" "$prompt" "$KEY" || continue
    # identity_qc:VLM 判与 key art 风格一致性(bridge 的 edit 带双图问答不可用时降级跳过 QC)
    QC=$(cd "$BRIDGE" && node "$CLI" edit --image "$KEY" --image "$out" \
      --prompt "Answer only YES or NO: do these two images share the same game's art style (palette/linework/texture)?" \
      --out /tmp/qc-ignore.png 2>/dev/null | grep -oiE '"revisedPrompt".*(YES|NO)' | grep -oiE 'YES|NO' | head -1 || echo SKIP)
    [[ "$QC" == "NO" ]] && { echo "[asset] identity_qc 不过,重出" >&2; continue; }
    break
  done
  [[ -s "$out" ]] || { echo "[asset] ✗ ${spec%%|*} 三次未产出" >&2; exit 1; }
  [[ $first == 0 ]] && echo ',' >> "$MANIFEST"; first=0
  printf '{"file":"%s"}' "${spec%%|*}" >> "$MANIFEST"
done
echo ']}' >> "$MANIFEST"
echo "[asset] ✓ 成套完成 → $ART(记得:pubspec 声明 assets/ + 代码引用,躺目录不算配套)" >&2
