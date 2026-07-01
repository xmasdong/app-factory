#!/bin/bash
# app-gate.sh — app 主线 skill-gate 验收脚本
# 与 generic scripts/ai-rules.sh 平行, 通过 source 复用其 sg_* helper

set -uo pipefail

# 找项目根
APP_GATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# 自包含, 不 source generic ai-rules.sh (避免它的 main 接管参数解析)
# 共享思想 (sg_run / clearance / honor system 边界) 在本文件独立实现

# ============================================================================
# Helpers
# ============================================================================

_app_get_status_field() {
  # 从 docs/status.md 顶部抽取字段 (如 PROJECT_TYPE / CURRENT_GATE)
  local field="$1"
  local file="$ROOT/docs/status.md"
  [[ ! -f "$file" ]] && return
  grep -E "^${field}:" "$file" 2>/dev/null | head -1 | sed "s/^${field}:[[:space:]]*//"
}

_app_section_exists() {
  local section="$1"
  local file="${2:-$ROOT/docs/spec.md}"
  [[ ! -f "$file" ]] && return 1
  grep -qE "^##[[:space:]]+${section}" "$file" 2>/dev/null
}

_app_section_content() {
  # 抽某章节内容 (## 到下一个 ## 之间)
  local section="$1"
  local file="${2:-$ROOT/docs/spec.md}"
  [[ ! -f "$file" ]] && return
  awk -v s="$section" '
    $0 ~ "^## " s {flag=1; next}
    /^## / && flag {exit}
    flag {print}
  ' "$file"
}

# ============================================================================
# sg_app_* 函数集
# ============================================================================

sg_app_project_type() {
  # 检测 status.md 顶部 PROJECT_TYPE 字段, 必须 = app 或 design-first(同走 app 主线闸门)
  local pt
  pt=$(_app_get_status_field "PROJECT_TYPE")
  if [[ -z "$pt" ]]; then
    echo "status.md 缺 PROJECT_TYPE 字段 (期望 app 或 design-first)"
    return
  fi
  if [[ "$pt" != "app" && "$pt" != "design-first" ]]; then
    echo "PROJECT_TYPE=${pt}, app 主线不该被触发 (合法: app / design-first)"
    return
  fi
}

sg_app_naming_real_evidence() {
  # 命名锁定 6 项: status: locked OR PROPOSED 显式; locked 必须有真 evidence 文件
  # (文件存在 + ≥10 字节 + 不含 待跑/TODO/TBD/PROPOSED 占位词)
  # 至少 4 项真 locked (域名/AppStore/Play/bundle id 关键四项)
  local file="$ROOT/docs/spec.md"
  [[ ! -f "$file" ]] && { echo "spec.md 不存在"; return; }
  _app_section_exists "命名锁定" || _app_section_exists "NAMING-LOCK" || { echo "spec.md 缺 ## 命名锁定 章节"; return; }

  local content
  content=$(_app_section_content "命名锁定" "$file")
  [[ -z "$content" ]] && content=$(_app_section_content "NAMING-LOCK" "$file")

  # 6 个子项必须出现 (品牌名/域名/AppStore/Play/bundle id/IAP prefix)
  local missing=()
  for item in "品牌名|brand" "域名|domain" "App[[:space:]]*Store|AppStore" "Play[[:space:]]*Store|Play" "bundle[[:space:]]*id|bundleId" "IAP|product[[:space:]]*id"; do
    if ! echo "$content" | grep -qiE "$item"; then
      missing+=("$item")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    echo "命名锁定缺子项: ${missing[*]} (需要 6 项全列出)"
    return
  fi

  # 每行必须有 status: locked 或 status: PROPOSED 显式
  local status_lines
  status_lines=$(echo "$content" | grep -ciE "status:[[:space:]]*(locked|proposed)" 2>/dev/null) || status_lines=0
  if (( status_lines < 6 )); then
    echo "命名锁定 status 标注数 ${status_lines} < 6 (每项需 status: locked 或 status: PROPOSED)"
    return
  fi

  # 验真: locked 行的 evidence 路径必须存在且不是空壳
  local locked_real=0
  local invalid=()
  while IFS= read -r line; do
    # 只看含 status: locked 的行
    echo "$line" | grep -qiE "status:[[:space:]]*locked" || continue
    local path
    path=$(echo "$line" | grep -oE "evidence:[[:space:]]*[^[:space:],\(\)]+" | sed -E 's|evidence:[[:space:]]*||')
    if [[ -z "$path" ]]; then
      invalid+=("locked 行缺 evidence 路径")
      continue
    fi
    # 相对路径解析
    [[ "${path:0:1}" != "/" ]] && path="$ROOT/$path"
    if [[ ! -f "$path" ]]; then
      invalid+=("文件不存在: ${path#$ROOT/}")
    elif [[ $(wc -c <"$path" 2>/dev/null || echo 0) -lt 10 ]]; then
      invalid+=("文件 <10 字节: ${path#$ROOT/}")
    elif grep -qiE "待跑|TODO|TBD|待填|PROPOSED" "$path" 2>/dev/null; then
      invalid+=("含占位词: ${path#$ROOT/}")
    else
      locked_real=$((locked_real + 1))
    fi
  done <<< "$content"

  if (( ${#invalid[@]} > 0 )); then
    local sample="${invalid[*]:0:3}"
    echo "命名 evidence 无效 (${#invalid[@]} 处): ${sample}"
    return
  fi

  if (( locked_real < 4 )); then
    echo "真 locked 项数 ${locked_real} < 4 (至少 4 项: 域名/AppStore/Play/bundle id)"
    return
  fi
}

sg_app_economics_real() {
  # 价格阶梯 + 反薅 ≥5 + 不允许模糊数字 (约/可能/待估/TBD/TODO)
  local file="$ROOT/docs/spec.md"
  [[ ! -f "$file" ]] && { echo "spec.md 不存在"; return; }
  _app_section_exists "单位经济" || _app_section_exists "ECONOMICS" || { echo "spec.md 缺 ## 单位经济 章节"; return; }

  local content
  content=$(_app_section_content "单位经济" "$file")
  [[ -z "$content" ]] && content=$(_app_section_content "ECONOMICS" "$file")

  # 松绑:非订阅型产品(买断/免费/纯本地/ASO 引流/无变现)显式声明后放行 —— 不硬套价格阶梯+反薅。
  # 目标是无人值守能跑完,不是逼免费游戏编订阅表。
  if echo "$content" | grep -qiE "无变现|不变现|买断|一次性(定价|购买)|纯本地|无订阅|免费(引流|跑通|ASO)|无按次成本|无可套利|经济.{0,4}N/?A"; then
    return   # 已声明非订阅模式,经济节按其模式即可,不卡订阅专属项
  fi

  # 以下仅对「订阅/配额型」产品生效(检测到价格阶梯才查反薅)
  if echo "$content" | grep -qE "价格阶梯|price[[:space:]]*tier|月套|月配额|订阅价"; then
    # 有试用/配额/订阅 → 至少要有反薅防护(数量匹配真实薅点,不再强凑 5)
    local antiabuse_count
    antiabuse_count=$(echo "$content" | awk '/反薅|anti.?abuse/,/^##/' | grep -cE "^[[:space:]]*[-*0-9]" 2>/dev/null) || antiabuse_count=0
    if (( antiabuse_count < 1 )); then
      echo "检测到订阅/配额但反薅漏洞清单为空 (有试用/配额至少堵 1 个真实薅点)"
      return
    fi
  else
    # 既未声明非订阅,又无价格阶梯 → 提示补(advisory 下不阻塞)
    echo "经济章节未声明变现模式(订阅?买断?免费?)—— 补一句「钱从哪来」再推进"
    return
  fi

  # 加严: 模糊数字词 (约¥/约$/可能/待估/TBD/TODO) > 2 处 = 未真测算
  local vague_count
  vague_count=$(echo "$content" | grep -cE "约[¥$0-9]|可能|待估|TBD|TODO" 2>/dev/null) || vague_count=0
  if (( vague_count > 2 )); then
    echo "经济章节含模糊词 ${vague_count} 处 (约/可能/待估/TBD), 必须真数据"
    return
  fi
}

sg_app_bundle_coherence() {
  # bundle id 跨文件一致性
  local file="$ROOT/docs/spec.md"
  [[ ! -f "$file" ]] && return  # 没 spec 不验

  # 从 spec.md 命名锁定中 grep bundle id
  local lock_bid
  lock_bid=$(_app_section_content "命名锁定" "$file" 2>/dev/null | grep -oE "com\.[a-zA-Z0-9._-]+" | head -1)
  [[ -z "$lock_bid" ]] && lock_bid=$(_app_section_content "NAMING-LOCK" "$file" 2>/dev/null | grep -oE "com\.[a-zA-Z0-9._-]+" | head -1)
  [[ -z "$lock_bid" ]] && return  # 锁定值未写就不检查

  # 扫各处 bundle id 文件
  local found_ids
  found_ids=$(grep -rhoE "com\.[a-zA-Z0-9._-]+" \
    "$ROOT/ios/" "$ROOT/android/" "$ROOT/app.config.js" "$ROOT/app.json" \
    "$ROOT/package.json" 2>/dev/null \
    | grep -vE "^(com\.apple|com\.google|com\.facebook|com\.android|com\.amazon)" \
    | sort -u 2>/dev/null)

  [[ -z "$found_ids" ]] && return  # 没找到代码中的 bundle id

  # 检测是否含 ${VAR} 拼接变量 (硬阻塞)
  if echo "$found_ids" | grep -qE '\$\{|\$\('; then
    echo "代码含变量拼接的 bundle id, 禁止: $(echo "$found_ids" | grep -E '\$' | head -1)"
    return
  fi

  # 唯一性: 所有 bundle id 必须相同
  local unique_count
  unique_count=$(echo "$found_ids" | wc -l | tr -d ' ')
  if (( unique_count > 1 )); then
    echo "bundle id 不一致 (锁定=${lock_bid}, 代码中存在 ${unique_count} 个不同值): $(echo "$found_ids" | tr '\n' ' ')"
    return
  fi

  # 必须与锁定值一致
  local actual_bid
  actual_bid=$(echo "$found_ids" | head -1)
  if [[ "$actual_bid" != "$lock_bid" ]]; then
    echo "bundle id 代码 (${actual_bid}) 与锁定 (${lock_bid}) 不一致"
    return
  fi
}

sg_app_platform_matrix() {
  # 多端能力矩阵: 表格行数 + fallback 字段非空
  local file="$ROOT/docs/spec.md"
  [[ ! -f "$file" ]] && { echo "spec.md 不存在"; return; }
  _app_section_exists "多端能力矩阵" || _app_section_exists "PLATFORM-MATRIX" || { echo "spec.md 缺 ## 多端能力矩阵 章节"; return; }

  local content
  content=$(_app_section_content "多端能力矩阵" "$file")
  [[ -z "$content" ]] && content=$(_app_section_content "PLATFORM-MATRIX" "$file")

  # 表格数据行数 (排除表头和分隔行)。已松绑:只要求矩阵存在 + ≥1 行真数据
  # (声明的端 × 相关能力);不再强制凑满 8 行 —— 单端 app(iOS 游戏/PWA/手表)天然不分叉。
  local rows
  rows=$(echo "$content" | grep -E "^\|" | grep -vE "^\|[-:]+" | grep -cv "^|[[:space:]]*能力\|^|[[:space:]]*Capability" 2>/dev/null) || rows=0
  if (( rows < 1 )); then
    echo "多端能力矩阵缺真数据行 (声明端 × 相关能力 至少 1 行;单端也要列版本兼容/核心能力)"
    return
  fi

  # fallback 列不能写"降级到 server-side" 一刀切
  local lazy_fallback
  lazy_fallback=$(echo "$content" | grep -c "降级到 server-side\|降级到后端\|后端兜底$" 2>/dev/null) || lazy_fallback=0
  if (( lazy_fallback > 2 )); then
    echo "fallback 列懒惰填写 (${lazy_fallback} 行写 '降级到 server-side' 一刀切)"
    return
  fi
}

sg_app_task_platform_field() {
  # 每个 TASK 含 PLATFORM 字段
  local file="$ROOT/docs/spec.md"
  [[ ! -f "$file" ]] && return

  local task_count platform_count
  task_count=$(grep -cE "^TASK:" "$file" 2>/dev/null) || task_count=0
  platform_count=$(grep -cE "^PLATFORM:" "$file" 2>/dev/null) || platform_count=0

  (( task_count == 0 )) && return  # 还没拆任务不验

  if (( platform_count < task_count )); then
    echo "TASK 数 ${task_count} 但 PLATFORM 字段数 ${platform_count} (每个任务必须含 PLATFORM)"
    return
  fi
}

sg_app_backend_real_status() {
  # 后端就绪 checkbox 打勾 ≥6 项 + 打勾行不允许含"待"字样
  local file="$ROOT/docs/spec.md"
  [[ ! -f "$file" ]] && { echo "spec.md 不存在"; return; }
  _app_section_exists "后端就绪" || _app_section_exists "BACKEND-READINESS" || { echo "spec.md 缺 ## 后端就绪 章节"; return; }

  local content
  content=$(_app_section_content "后端就绪" "$file")
  [[ -z "$content" ]] && content=$(_app_section_content "BACKEND-READINESS" "$file")

  local checked
  checked=$(echo "$content" | grep -cE "^[[:space:]]*-[[:space:]]*\[[xX]\]" 2>/dev/null) || checked=0
  if (( checked < 6 )); then
    echo "后端就绪 checkbox 打勾 ${checked} < 6 项"
    return
  fi

  # 加严: 打勾行不允许含"待"字样 (待注册/待跑/TODO/待填)
  local pending_count
  pending_count=$(echo "$content" | grep -E "^[[:space:]]*-[[:space:]]*\[[xX]\]" | grep -cE "待注册|待跑|待填|TODO|TBD" 2>/dev/null) || pending_count=0
  if (( pending_count > 0 )); then
    echo "checked 行含 ${pending_count} 个'待/TODO'字样 (应是真值, 或改 - [ ] 显式 deferred)"
    return
  fi
}

sg_app_compliance_real_scan() {
  # 合规 8 项必填 + app-store-review-survival 真扫输出 PASS
  local file="$ROOT/docs/spec.md"
  [[ ! -f "$file" ]] && { echo "spec.md 不存在"; return; }
  _app_section_exists "合规" || _app_section_exists "COMPLIANCE" || { echo "spec.md 缺 ## 合规 章节"; return; }

  local content
  content=$(_app_section_content "合规" "$file")
  [[ -z "$content" ]] && content=$(_app_section_content "COMPLIANCE" "$file")

  # 必填关键词存在性
  local missing=()
  for item in "隐私政策|privacy" "EULA" "删除账号|delete[[:space:]]*account" "GDPR" "ATT" "Kids|COPPA" "网络授权|network[[:space:]]*permission" "权限文案"; do
    if ! echo "$content" | grep -qiE "$item"; then
      missing+=("$item")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    echo "合规扫描缺关键项: ${missing[*]}"
    return
  fi

  # 加严: app-store-review-survival skill 真扫产物
  local asr="$ROOT/.claude/state/asr-survival-scan.json"
  if [[ ! -f "$asr" ]]; then
    echo "缺 .claude/state/asr-survival-scan.json (app-store-review-survival skill 未跑)"
    return
  fi
  if command -v jq >/dev/null 2>&1; then
    local result
    result=$(jq -r '.result // ""' "$asr" 2>/dev/null)
    if [[ "$result" != "PASS" ]]; then
      echo "asr-survival-scan.json result=${result:-空} (期望 PASS)"
      return
    fi
  else
    # 无 jq 时 grep 兜底
    if ! grep -qE '"result"[[:space:]]*:[[:space:]]*"PASS"' "$asr"; then
      echo "asr-survival-scan.json 未含 result: PASS"
      return
    fi
  fi
}

sg_app_product_lock() {
  # 产品定位 5 字段齐全 + 非空
  local file="$ROOT/docs/spec.md"
  [[ ! -f "$file" ]] && { echo "spec.md 不存在"; return; }
  _app_section_exists "产品定位" || { echo "spec.md 缺 ## 产品定位 章节"; return; }

  local content
  content=$(_app_section_content "产品定位" "$file")

  local missing=()
  local no_reason=()
  for field in "PRODUCT_FORM" "TARGET_MARKET" "TARGET_USER" "REVENUE_MODEL" "TECH_STACK"; do
    # 字段必须存在且后面有非空值
    if ! echo "$content" | grep -qE "^${field}:[[:space:]]*\S"; then
      missing+=("${field}")
      continue
    fi
    # 加严: 必须含 "—" 或 "(理由" 或 "—" (em-dash) 后非空 (AI 自决理由)
    local field_line
    field_line=$(echo "$content" | grep -E "^${field}:" | head -1)
    if ! echo "$field_line" | grep -qE "(—|--|\(理由|reason:|因为|because)" 2>/dev/null; then
      no_reason+=("${field}")
      continue
    fi
    # 理由后必须有 ≥10 字符 (防"— —" 这种空理由)
    local reason_part
    reason_part=$(echo "$field_line" | sed -E 's/^[A-Z_]+:[[:space:]]*[^—]*—//' | head -c 100)
    if (( ${#reason_part} < 10 )); then
      no_reason+=("${field}(理由 <10 字)")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    echo "产品定位缺字段或值空: ${missing[*]}"
    return
  fi
  if (( ${#no_reason[@]} > 0 )); then
    echo "产品定位字段缺理由 (应为 '<值> — <调研依据>'): ${no_reason[*]}"
    return
  fi

  # TARGET_MARKET 必须 FROZEN 标注
  if ! echo "$content" | grep -qiE "TARGET_MARKET:.*\[?(FROZEN|locked)\]?"; then
    echo "TARGET_MARKET 缺 [FROZEN] 标注 (默认 FROZEN by default)"
    return
  fi
}

sg_app_market_evidence() {
  # 市场调研 5 子节 + 反方 ≥3 + 死亡案例 ≥1 + 原始数据目录
  local file="$ROOT/docs/spec.md"
  [[ ! -f "$file" ]] && { echo "spec.md 不存在"; return; }
  _app_section_exists "市场调研" || { echo "spec.md 缺 ## 市场调研 章节"; return; }

  local content
  content=$(_app_section_content "市场调研" "$file")

  # 5 子节存在
  local missing=()
  for sub in "商店榜单扫描" "差评样本" "多源调研" "已死同品类" "反方论据"; do
    if ! echo "$content" | grep -qE "^### ${sub}"; then
      missing+=("${sub}")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    echo "市场调研缺子节: ${missing[*]}"
    return
  fi

  # 反方论据 ≥3 条 (在该子节下 list item 计数, 用 - 或 * 或数字.)
  local counter_count
  counter_count=$(echo "$content" | awk '/^### 反方论据/{flag=1;next} /^###|^##/{flag=0} flag' | grep -cE "^[[:space:]]*([-*]|[0-9]+\.)" 2>/dev/null) || counter_count=0
  if (( counter_count < 3 )); then
    echo "反方论据 ${counter_count} 条 < 3"
    return
  fi

  # 死亡案例 ≥1
  local dead_count
  dead_count=$(echo "$content" | awk '/^### 已死同品类/{flag=1;next} /^###|^##/{flag=0} flag' | grep -cE "^[[:space:]]*([-*]|[0-9]+\.)" 2>/dev/null) || dead_count=0
  if (( dead_count < 1 )); then
    echo "已死同品类案例数 ${dead_count} < 1"
    return
  fi

  # 市场调研原始数据样本目录存在 (honor system)
  if [[ ! -d "$ROOT/.claude/state/market-research" ]]; then
    echo "缺市场调研原始数据目录 .claude/state/market-research/ (商店榜单/差评样本需存证)"
    return
  fi
}

sg_app_visual_artifact() {
  # 每个候选概念有视觉产物
  local visuals_dir="$ROOT/.claude/state/concept-visuals"
  if [[ ! -d "$visuals_dir" ]]; then
    echo "缺概念视觉目录 .claude/state/concept-visuals/ (每个候选必须有视觉效果图)"
    return
  fi

  local has_visuals=0
  for d in "$visuals_dir"/*/; do
    [[ -d "$d" ]] || continue
    local count
    count=$(find "$d" -maxdepth 2 -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.svg" -o -name "*.pdf" \) 2>/dev/null | wc -l | tr -d ' ')
    if (( count > 0 )); then
      has_visuals=$((has_visuals + 1))
    fi
  done

  if (( has_visuals < 1 )); then
    echo "concept-visuals/ 下无候选概念含图片 (期望 ≥1 个候选有 ≥1 张效果图)"
    return
  fi
}

sg_app_discovery_summary() {
  # Step 0.8 决策卡口: docs/discovery-summary.md 1 页可读完
  # 文件存在 + ≤150 行 + 含 5 段 (产品定位/市场 highlight/mockup/用户动线/决策待答)
  local file="$ROOT/docs/discovery-summary.md"
  if [[ ! -f "$file" ]]; then
    echo "缺 docs/discovery-summary.md (决策卡口必须产物)"
    return
  fi
  local lines
  lines=$(wc -l < "$file" | tr -d ' ')
  if (( lines > 150 )); then
    echo "discovery-summary.md ${lines} 行 > 150 (应 ≤120, 用户 1 页能看完)"
    return
  fi
  # 5 段关键章节存在 (任一别名命中即可)
  local missing=()
  if ! grep -qiE "产品定位|positioning" "$file"; then missing+=("产品定位"); fi
  if ! grep -qiE "市场.*高亮|highlights?|市场[[:space:]]*关键" "$file"; then missing+=("市场highlight"); fi
  if ! grep -qiE "mockup|视觉|概念图" "$file"; then missing+=("mockup/视觉"); fi
  if ! grep -qiE "用户动线|user[[:space:]]*flow|用户流程" "$file"; then missing+=("用户动线"); fi
  if ! grep -qiE "决策|decision|待答" "$file"; then missing+=("决策待答"); fi
  if (( ${#missing[@]} > 0 )); then
    echo "discovery-summary.md 缺章节: ${missing[*]}"
    return
  fi
}

sg_app_spike_dual_lang_real() {
  # 技术 spike 双语 4 字段 + 真 PASS/FAIL 信号
  local file="$ROOT/docs/spec.md"
  [[ ! -f "$file" ]] && { echo "spec.md 不存在"; return; }

  # spike 章节存在
  if ! _app_section_exists "技术 spike" && ! _app_section_exists "技术[Ss]pike" && ! _app_section_exists "[Ss]pike"; then
    echo "spec.md 缺 ## 技术 spike 章节"
    return
  fi

  local content
  content=$(_app_section_content "技术 spike" "$file" 2>/dev/null)
  [[ -z "$content" ]] && content=$(_app_section_content "Spike" "$file" 2>/dev/null)

  # 至少含: 工程视角 + 用户视角成功信号 + 失败信号 + 回退方案
  local missing=()
  for keyword in "工程视角|engineering" "用户视角.*成功|success.*user|user.*success" "失败信号|fail.*signal|failure" "回退|fallback|rollback"; do
    if ! echo "$content" | grep -qiE "$keyword"; then
      missing+=("$(echo "$keyword" | cut -d'|' -f1)")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    echo "技术 spike 缺双语字段: ${missing[*]}"
    return
  fi

  # 加严: 真 PASS/FAIL 信号 — 二选一
  # (1) .claude/state/spike-results.json 存在且含 PASS/FAIL 标记
  # (2) spec.md spike 章节明确写 **结果**: PASS 或 **结果**: FAIL → 切 <备选>
  local sr="$ROOT/.claude/state/spike-results.json"
  local has_signal=0
  if [[ -f "$sr" ]]; then
    if grep -qE '"result"[[:space:]]*:[[:space:]]*"(PASS|FAIL)"' "$sr" 2>/dev/null; then
      has_signal=1
    fi
  fi
  if (( has_signal == 0 )); then
    if echo "$content" | grep -qE "\*\*结果\*\*[[:space:]]*[:：][[:space:]]*(PASS|FAIL)"; then
      has_signal=1
    fi
  fi
  if (( has_signal == 0 )); then
    echo "技术 spike 缺 PASS/FAIL 信号 (.claude/state/spike-results.json 或 spec.md 中 **结果**: PASS/FAIL)"
    return
  fi
}

sg_app_reviewer_path() {
  # A-GATE 3: 审核员路径预演证据
  local rw_dir="$ROOT/.claude/state/reviewer-walkthrough"
  if [[ ! -d "$rw_dir" ]]; then
    echo "缺审核员路径目录 .claude/state/reviewer-walkthrough/"
    return
  fi

  local artifact_count
  artifact_count=$(find "$rw_dir" -type f \( -name "*.png" -o -name "*.gif" -o -name "*.mp4" -o -name "*.md" \) 2>/dev/null | wc -l | tr -d ' ')
  if (( artifact_count < 3 )); then
    echo "审核员路径产物 < 3 (期望: 截图/GIF + Review Notes)"
    return
  fi

  # BACKEND-READINESS 中演示账号字段非空
  local content
  content=$(_app_section_content "后端就绪" "$ROOT/docs/spec.md" 2>/dev/null)
  [[ -z "$content" ]] && content=$(_app_section_content "BACKEND-READINESS" "$ROOT/docs/spec.md" 2>/dev/null)

  if ! echo "$content" | grep -qiE "演示账号|reviewer[[:space:]]*account|sandbox[[:space:]]*account"; then
    echo "后端就绪章节缺演示账号字段 (审核员路径前置)"
    return
  fi
}

sg_app_aso_complete() {
  # A-GATE 4: ASO 关键词 / 截图脚本 / 商店材料
  local file="$ROOT/docs/spec.md"
  [[ ! -f "$file" ]] && return

  # ASO 章节存在
  if ! _app_section_exists "ASO" && ! _app_section_exists "上架材料"; then
    echo "spec.md 缺 ## ASO 或 ## 上架材料 章节"
    return
  fi

  local content
  content=$(_app_section_content "ASO" "$file" 2>/dev/null)
  [[ -z "$content" ]] && content=$(_app_section_content "上架材料" "$file" 2>/dev/null)

  # 必填: app_name / subtitle / keywords / description
  local missing=()
  for item in "app[[:space:]]*name|应用名" "subtitle|副标题" "keyword|关键词" "description|简介"; do
    if ! echo "$content" | grep -qiE "$item"; then
      missing+=("$item")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    echo "ASO 缺字段: ${missing[*]}"
    return
  fi

  # 关键词数 >= 5
  local kw_count
  kw_count=$(echo "$content" | grep -cE "^[[:space:]]*-[[:space:]]*[Kk]eyword|^[[:space:]]*[0-9]\.[[:space:]]*[a-zA-Z]" 2>/dev/null) || kw_count=0
  # 截图脚本存在
  local has_screenshot_script=0
  if [[ -f "$ROOT/scripts/screenshots.sh" || -f "$ROOT/scripts/screenshots.js" || -f "$ROOT/fastlane/Snapfile" ]]; then
    has_screenshot_script=1
  fi
  if (( has_screenshot_script == 0 )); then
    echo "缺截图脚本 (scripts/screenshots.* 或 fastlane/Snapfile)"
    return
  fi
}

sg_app_multiplatform_smoke() {
  # 多端 smoke 在 verify-report.json 中
  local report="$ROOT/.claude/state/verify-report.json"
  [[ ! -f "$report" ]] && return  # 没 verify 不验

  if ! command -v jq >/dev/null 2>&1; then
    return
  fi

  local mp_status
  mp_status=$(jq -r '.multi_platform_status // ""' "$report" 2>/dev/null)
  if [[ -z "$mp_status" || "$mp_status" == "null" ]]; then
    echo "verify-report.json 缺 multi_platform_status 字段"
    return
  fi

  # 每端必须 PASS 或显式 DEFERRED
  local bad
  bad=$(echo "$mp_status" | grep -ivE "^(PASS|DEFERRED|N/A)$" 2>/dev/null | head -3 | tr '\n' ',')
  if [[ -n "$bad" ]]; then
    echo "多端 smoke 状态有非 PASS/DEFERRED: $bad"
    return
  fi
}

# ============================================================================
# design-first 增强: 7 个新 sg_app_* 函数(初期全 advisory,经 sg_run_soft 调用)
# ============================================================================

# ============================================================================
# design-first 增强: 7 个新 sg_app_* 函数 + sg_run_soft (如已有可跳过)
# 风格: 无依赖项 → echo 缺失原因 return; 通过 → 静默 return
# 路径常量: $ROOT 已在文件顶部定义
# ============================================================================

# ----------------------------------------------------------------------------
# 1. sg_app_data_contract — SKILL.md 已声明但本文件未实现, 现补
#    验: spec.md ## 数据契约 章节存在 + 含契约表 + 消费端 ≥2 + 端侧独有字段子章节
# ----------------------------------------------------------------------------
sg_app_data_contract() {
  local file="$ROOT/docs/spec.md"
  [[ ! -f "$file" ]] && { echo "spec.md 不存在"; return; }
  _app_section_exists "数据契约" || _app_section_exists "DATA-CONTRACT" || { echo "spec.md 缺 ## 数据契约 章节"; return; }

  local content
  content=$(_app_section_content "数据契约" "$file")
  [[ -z "$content" ]] && content=$(_app_section_content "DATA-CONTRACT" "$file")

  # 契约表存在 (markdown 表格数据行 ≥1)
  local rows
  rows=$(echo "$content" | grep -E "^\|" | grep -vE "^\|[[:space:]:|-]+\|?[[:space:]]*$" 2>/dev/null | wc -l | tr -d ' ')
  if (( rows < 2 )); then
    echo "数据契约缺契约表 (字段/类型/来源 表格数据行 ${rows} < 2)"
    return
  fi

  # 消费方含 ≥2 端 (从 ios/android/web/flutter/swiftui/compose/server 命中数)
  local consumer_count
  consumer_count=$(echo "$content" | grep -oiE "iOS|Android|Web|Flutter|SwiftUI|Compose|server|后端|前端" 2>/dev/null | sort -u | wc -l | tr -d ' ')
  if (( consumer_count < 2 )); then
    echo "数据契约消费方 < 2 端 (期望 ≥2 个端, 当前命中 ${consumer_count})"
    return
  fi

  # 端侧独有字段子章节存在
  if ! echo "$content" | grep -qiE "^### .*(独有|platform.?specific|端侧|specific)"; then
    echo "数据契约缺 ### 端侧独有字段 子章节"
    return
  fi
}

# ----------------------------------------------------------------------------
# 2. sg_app_openapi_artifact — api/openapi.yaml 存在 + OpenAPI 3.1 + 覆盖核心链路
# ----------------------------------------------------------------------------
sg_app_openapi_artifact() {
  local oas="$ROOT/api/openapi.yaml"
  [[ ! -f "$oas" ]] && oas="$ROOT/api/openapi.yml"
  if [[ ! -f "$oas" ]]; then
    echo "缺 api/openapi.yaml (backend-forge 后端 SSOT 未产出)"
    return
  fi

  # OpenAPI 3.1 声明
  if ! grep -qE "^openapi:[[:space:]]*[\"']?3\.1" "$oas" 2>/dev/null; then
    echo "openapi.yaml 非 OpenAPI 3.1 (缺 openapi: 3.1.x 声明)"
    return
  fi

  # 合法性: 有 jq/swagger-cli/redocly 则真校验, 否则结构兜底
  if command -v redocly >/dev/null 2>&1; then
    if ! redocly lint "$oas" >/dev/null 2>&1; then
      echo "openapi.yaml redocly lint 失败 (非合法 OpenAPI 文档)"
      return
    fi
  elif command -v swagger-cli >/dev/null 2>&1; then
    if ! swagger-cli validate "$oas" >/dev/null 2>&1; then
      echo "openapi.yaml swagger-cli validate 失败"
      return
    fi
  else
    # 兜底: 必须含 info: 和 paths:
    if ! grep -qE "^info:" "$oas" || ! grep -qE "^paths:" "$oas"; then
      echo "openapi.yaml 缺 info:/paths: 顶级键 (结构不合法)"
      return
    fi
  fi

  # 覆盖核心链路: paths 下 endpoint 数 ≥1
  local ep_count
  ep_count=$(grep -cE "^[[:space:]]{2}/[A-Za-z0-9{}/_-]+:" "$oas" 2>/dev/null) || ep_count=0
  if (( ep_count < 1 )); then
    echo "openapi.yaml paths 下无 endpoint (未覆盖核心链路)"
    return
  fi
}

# ----------------------------------------------------------------------------
# 3. sg_app_design_baseline_exists — design-manifest.json + baseline PNG
# ----------------------------------------------------------------------------
sg_app_design_baseline_exists() {
  local manifest="$ROOT/docs/design/design-manifest.json"
  if [[ ! -f "$manifest" ]]; then
    echo "缺 docs/design/design-manifest.json (design-restore 设计真相源未产出)"
    return
  fi

  # manifest 合法 + 含 screens
  if command -v jq >/dev/null 2>&1; then
    if ! jq -e '.' "$manifest" >/dev/null 2>&1; then
      echo "design-manifest.json 非合法 JSON"
      return
    fi
    local screen_count
    screen_count=$(jq -r '(.screens // []) | length' "$manifest" 2>/dev/null) || screen_count=0
    if (( screen_count < 1 )); then
      echo "design-manifest.json screens 为空 (无屏可还原)"
      return
    fi
  else
    if ! grep -qE '"screens"' "$manifest"; then
      echo "design-manifest.json 缺 screens 字段"
      return
    fi
  fi

  # baseline PNG 存在 (docs/design/baseline/ 下 ≥1 张 png)
  local png_count
  png_count=$(find "$ROOT/docs/design/baseline" -type f -name "*.png" 2>/dev/null | wc -l | tr -d ' ')
  if (( png_count < 1 )); then
    echo "缺 baseline PNG (docs/design/baseline/<platform>/<viewport>/<screen>.png 下无图)"
    return
  fi
}

# ----------------------------------------------------------------------------
# 4. sg_app_ui_visual_diff — 读 .claude/state/ui-diff.json
#    mismatch ≤3 pass / 3-8 warn (echo 但 advisory) / >8 fail
# ----------------------------------------------------------------------------
sg_app_ui_visual_diff() {
  local diff="$ROOT/.claude/state/ui-diff.json"
  if [[ ! -f "$diff" ]]; then
    echo "缺 .claude/state/ui-diff.json (截图视觉 diff 未跑)"
    return
  fi

  local mismatch
  if command -v jq >/dev/null 2>&1; then
    mismatch=$(jq -r '.mismatch // .max_mismatch // empty' "$diff" 2>/dev/null)
  else
    mismatch=$(grep -oE '"mismatch"[[:space:]]*:[[:space:]]*[0-9]+' "$diff" 2>/dev/null | grep -oE '[0-9]+$' | head -1)
  fi
  if [[ -z "$mismatch" || ! "$mismatch" =~ ^[0-9]+$ ]]; then
    echo "ui-diff.json 缺 mismatch 数值字段"
    return
  fi

  if (( mismatch > 8 )); then
    echo "视觉 diff mismatch=${mismatch} > 8 (FAIL, 与基线偏差过大)"
    return
  fi
  if (( mismatch > 3 )); then
    echo "视觉 diff mismatch=${mismatch} 落在 3-8 WARN 区 (建议复核, 确认非动态区误杀)"
    return
  fi
  # ≤3 → PASS, 静默
}

# ----------------------------------------------------------------------------
# 5. sg_app_design_token_match — 读 token 对账产物
# ----------------------------------------------------------------------------
sg_app_design_token_match() {
  local rep="$ROOT/.claude/state/token-match.json"
  if [[ ! -f "$rep" ]]; then
    echo "缺 .claude/state/token-match.json (token 对账未跑)"
    return
  fi

  if command -v jq >/dev/null 2>&1; then
    local hardcoded mismatched
    hardcoded=$(jq -r '.hardcoded_count // 0' "$rep" 2>/dev/null)
    mismatched=$(jq -r '.mismatched_count // 0' "$rep" 2>/dev/null)
    [[ "$hardcoded" =~ ^[0-9]+$ ]] || hardcoded=0
    [[ "$mismatched" =~ ^[0-9]+$ ]] || mismatched=0
    if (( hardcoded > 0 )); then
      echo "token 对账: ${hardcoded} 处硬编码值 (实现处必须只引用 token, 禁硬编码)"
      return
    fi
    if (( mismatched > 0 )); then
      echo "token 对账: ${mismatched} 处 token 值与 manifest 不一致"
      return
    fi
  else
    if grep -qE '"hardcoded_count"[[:space:]]*:[[:space:]]*[1-9]' "$rep"; then
      echo "token 对账含硬编码值 (实现处禁硬编码, 只引用 token)"
      return
    fi
  fi
}

# ----------------------------------------------------------------------------
# 6. sg_app_contract_test — 读 .claude/state/contract-test.json
#    区分 target=mock|real
# ----------------------------------------------------------------------------
sg_app_contract_test() {
  local ct="$ROOT/.claude/state/contract-test.json"
  if [[ ! -f "$ct" ]]; then
    echo "缺 .claude/state/contract-test.json (Schemathesis 契约测试未跑)"
    return
  fi

  local target result
  if command -v jq >/dev/null 2>&1; then
    target=$(jq -r '.target // "unknown"' "$ct" 2>/dev/null)
    result=$(jq -r '.result // ""' "$ct" 2>/dev/null)
  else
    target=$(grep -oE '"target"[[:space:]]*:[[:space:]]*"[^"]+"' "$ct" 2>/dev/null | sed -E 's/.*"([^"]+)"$/\1/')
    result=$(grep -oE '"result"[[:space:]]*:[[:space:]]*"[^"]+"' "$ct" 2>/dev/null | sed -E 's/.*"([^"]+)"$/\1/')
    [[ -z "$target" ]] && target="unknown"
  fi

  if [[ "$result" != "PASS" ]]; then
    echo "契约测试 target=${target} result=${result:-空} (期望 PASS)"
    return
  fi
  # target=mock → 前后端尚未对齐真后端, 仅 advisory 提示 (不当失败, 但点名)
  if [[ "$target" == "mock" ]]; then
    echo "契约测试仅跑在 mock (target=mock), real 后端尚未验证, 上线前需对 real 复跑"
    return
  fi
  # target=real & PASS → 静默
}

# ----------------------------------------------------------------------------
# 7. sg_app_e2e_contract_smoke — E2E 字段对照
#    读 .claude/state/e2e-contract.json: 实际响应字段 vs openapi/manifest 声明
# ----------------------------------------------------------------------------
sg_app_e2e_contract_smoke() {
  local e2e="$ROOT/.claude/state/e2e-contract.json"
  if [[ ! -f "$e2e" ]]; then
    echo "缺 .claude/state/e2e-contract.json (E2E 字段对照 smoke 未跑)"
    return
  fi

  if command -v jq >/dev/null 2>&1; then
    local result missing_fields extra_fields
    result=$(jq -r '.result // ""' "$e2e" 2>/dev/null)
    missing_fields=$(jq -r '(.missing_fields // []) | length' "$e2e" 2>/dev/null)
    extra_fields=$(jq -r '(.extra_fields // []) | length' "$e2e" 2>/dev/null)
    [[ "$missing_fields" =~ ^[0-9]+$ ]] || missing_fields=0
    [[ "$extra_fields" =~ ^[0-9]+$ ]] || extra_fields=0
    if (( missing_fields > 0 )); then
      echo "E2E 字段对照: ${missing_fields} 个声明字段在实际响应缺失 (前后端 drift)"
      return
    fi
    if (( extra_fields > 0 )); then
      echo "E2E 字段对照: ${extra_fields} 个实际响应字段未在契约声明 (前后端 drift)"
      return
    fi
    if [[ -n "$result" && "$result" != "PASS" ]]; then
      echo "E2E 字段对照 result=${result} (期望 PASS)"
      return
    fi
  else
    if ! grep -qE '"result"[[:space:]]*:[[:space:]]*"PASS"' "$e2e"; then
      echo "e2e-contract.json 未含 result: PASS"
      return
    fi
  fi
}

# ----------------------------------------------------------------------------
# 8. sg_app_seam_smoke — 前后端合体 seam 冒烟(证明两半体真能握手)
#    读 .claude/state/seam-smoke.json(由 scripts/design-first/seam-smoke.sh 产出):
#      { result, backend_boot, frontend_endpoints, broken:[...], ... }
#    两半各自绿 ≠ 合体能跑 —— trade-copilot 实战暴露的最大坑就是 seam 从没验过。
# ----------------------------------------------------------------------------
sg_app_seam_smoke() {
  local ss="$ROOT/.claude/state/seam-smoke.json"
  if [[ ! -f "$ss" ]]; then
    echo "缺 .claude/state/seam-smoke.json (前后端合体 seam 冒烟未跑;boot 后端后跑 scripts/design-first/seam-smoke.sh --base-url <URL>)"
    return
  fi
  if ! command -v jq >/dev/null 2>&1; then
    grep -qE '"result"[[:space:]]*:[[:space:]]*"PASS"' "$ss" || { echo "seam-smoke.json 未含 result: PASS"; return; }
    return
  fi
  local result boot broken_count notes
  result=$(jq -r '.result // ""' "$ss" 2>/dev/null)
  boot=$(jq -r '.backend_boot // false' "$ss" 2>/dev/null)
  broken_count=$(jq -r '(.broken // []) | length' "$ss" 2>/dev/null)
  notes=$(jq -r '.notes // ""' "$ss" 2>/dev/null)
  [[ "$broken_count" =~ ^[0-9]+$ ]] || broken_count=0
  if [[ "$boot" != "true" ]]; then
    echo "seam 冒烟: 后端未起来 (backend_boot=false) — 前后端从未合体验证"
    return
  fi
  if (( broken_count > 0 )); then
    local first
    first=$(jq -r '.broken[0] | "\(.path) → \(.status) \(.reason)"' "$ss" 2>/dev/null)
    echo "seam 冒烟: ${broken_count} 个前端 endpoint 在真后端断裂 (首个: ${first})"
    return
  fi
  if [[ -n "$result" && "$result" != "PASS" ]]; then
    echo "seam 冒烟 result=${result} (${notes})"
    return
  fi
  # PASS → 静默
}

# ----------------------------------------------------------------------------
# 9. sg_app_integration_test — 真实环境端到端联调证明(最强"合体能跑"证据)
#    读 .claude/state/integration-test.json(integration-test.py 打真后端产出):
#      { result, token_obtained, steps:[...], notes }
#    比 seam(endpoint 存在探测)更进一步:真跑通 注册→拿 token→带 token 取受保护数据。
# ----------------------------------------------------------------------------
sg_app_integration_test() {
  local it="$ROOT/.claude/state/integration-test.json"
  if [[ ! -f "$it" ]]; then
    echo "缺 .claude/state/integration-test.json (端到端联调未跑;stack-up 起后端后跑 integration-test.py --base-url <URL>)"
    return
  fi
  if ! command -v jq >/dev/null 2>&1; then
    grep -qE '"result"[[:space:]]*:[[:space:]]*"PASS"' "$it" || { echo "integration-test.json 未含 result: PASS"; return; }
    return
  fi
  local result notes
  result=$(jq -r '.result // ""' "$it" 2>/dev/null)
  notes=$(jq -r '.notes // ""' "$it" 2>/dev/null)
  if [[ "$result" != "PASS" ]]; then
    echo "端到端联调 result=${result:-空} (${notes})"
    return
  fi
  # PASS → 静默
}

# ----------------------------------------------------------------------------
# _app_is_fullstack — 侦测「全栈 app」(同时有真后端 + 前端 api-client)
#   命中 → qa 关把 seam + real-contract 升为硬门(合体能不能跑是正确性,不是风格)
#   未命中(纯前端/纯后端/design-only)→ 维持 advisory
#   显式豁免:status.md 决策日志含 "seam" 且 "defer"(用户主动 defer 本地合体验证)
# ----------------------------------------------------------------------------
_app_is_fullstack() {
  # 显式豁免
  if [[ -f "$ROOT/docs/status.md" ]] && grep -iqE 'seam.*defer|defer.*seam' "$ROOT/docs/status.md" 2>/dev/null; then
    return 1
  fi
  # 后端信号:backend/ 目录 或 api/openapi.yaml 或 常见后端入口
  local has_backend=false
  if [[ -d "$ROOT/backend" || -d "$ROOT/server" || -d "$ROOT/api" ]] \
     || [[ -f "$ROOT/api/openapi.yaml" || -f "$ROOT/api/openapi.yml" ]] \
     || compgen -G "$ROOT/**/main.py" >/dev/null 2>&1; then
    has_backend=true
  fi
  # 前端信号:frontend/ web/ app/ src/ 里有 api-client(引用 /api 路径)
  local has_frontend=false
  local d
  for d in frontend web app src client; do
    if [[ -d "$ROOT/$d" ]]; then
      if find "$ROOT/$d" -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.dart' \) \
           -not -path '*/node_modules/*' 2>/dev/null \
           | xargs grep -lE "['\"\`]/(api|v1)/" 2>/dev/null | grep -q .; then
        has_frontend=true
        break
      fi
    fi
  done
  [[ "$has_backend" == "true" && "$has_frontend" == "true" ]]
}

# ============================================================================
# Router: cmd_app_gate <discover|lockdown|shape|build|qa|ship|scaffold>
# (anchor 保留为 legacy alias → 自动转 discover)
# ============================================================================

cmd_app_gate() {
  local gate="${1:-}"
  if [[ -z "$gate" ]]; then
    echo "Usage: app-gate.sh app-gate <discover|lockdown|shape|build|qa|ship|scaffold>"
    exit 1
  fi

  # Legacy alias: anchor → discover (2-touch workflow 拆分后)
  if [[ "$gate" == "anchor" ]]; then
    echo "⚠️  'anchor' 已弃用, 改用 'discover' (Phase A) 或 'lockdown' (Phase B). 本次按 discover 跑." >&2
    gate="discover"
  fi

  local failures=()
  local verified=()
  local heuristic_warnings=()

  sg_run() {
    local result="$1"
    if [[ -n "$result" ]]; then
      failures+=("$result")
    else
      verified+=("$2")
    fi
  }

  sg_run_soft() {
    local result="$1"
    local label="$2"
    if [[ -n "$result" ]]; then
      heuristic_warnings+=("${label}: ${result}")
    else
      verified+=("$label")
    fi
  }

  # 公共前置: PROJECT_TYPE=app
  sg_run "$(sg_app_project_type)" "PROJECT_TYPE=app"

  case "$gate" in
    discover)
      # Phase A: 定位 + (市场/mockup 视情况) + 决策卡口
      sg_run "$(sg_app_product_lock)" "Step 0: 产品定位 5 字段齐(有 PRD 时从 PRD 读)"
      # 市场调研 + mockup 仅「从模糊点子起」才必须;有 PRD / 设计稿 / 明确产品定义 → 可选(不强制、不报缺)
      if compgen -G "$ROOT/docs/PRD*" >/dev/null 2>&1 || compgen -G "$ROOT/docs/prd*" >/dev/null 2>&1 \
         || [[ -f "$ROOT/docs/design/design-manifest.json" ]] \
         || [[ "$(_app_get_status_field PROJECT_TYPE)" == "design-first" ]]; then
        echo "ℹ️  检测到 PRD/设计稿/明确产品定义 → 市场调研 + mockup 视为【可选】(产品已定义,不强制、不报缺)。需要时仍可手动跑。" >&2
      else
        # 从模糊点子起步:市场验证 + mockup 是核心,必跑
        sg_run "$(sg_app_market_evidence)" "Step 0.5: 市场调研 5 子节 + 反方 ≥3"
        sg_run "$(sg_app_visual_artifact)" "Step 0.7: 概念视觉 mockup"
      fi
      sg_run "$(sg_app_discovery_summary)" "Step 0.8: discovery-summary.md 决策卡口产物"
      ;;
    lockdown)
      # Phase B: 真验证 (AUTONOMOUS)
      sg_run "$(sg_app_spike_dual_lang_real)" "Step 2.1: 技术 spike 双语 + 真 PASS/FAIL 信号"
      sg_run "$(sg_app_economics_real)" "Step 2.2: 单位经济真数据 (无待估/约/可能)"
      sg_run "$(sg_app_naming_real_evidence)" "Step 2.3: 命名锁定真 evidence 文件落盘"
      sg_run "$(sg_app_backend_real_status)" "Step 2.4: 后端就绪真值或显式 deferred"
      sg_run "$(sg_app_compliance_real_scan)" "Step 2.5: 合规真扫 + app-store-review-survival PASS"
      sg_run "$(sg_app_bundle_coherence)" "bundle id 跨文件一致"
      ;;
    shape)
      sg_run "$(sg_app_platform_matrix)" "多端能力矩阵(声明端×相关能力 ≥1 行 + 无懒惰 fallback)"
      sg_run "$(sg_app_task_platform_field)" "TASK PLATFORM 字段全填"
      # design-first: 数据契约(补实)+ openapi(仅 design-first 项目),全 advisory
      sg_run_soft "$(sg_app_data_contract)" "数据契约表 + 消费端 ≥2 + 端侧独有字段"
      [[ -d "$ROOT/api" || -f "$ROOT/docs/design/design-manifest.json" ]] && \
        sg_run_soft "$(sg_app_openapi_artifact)" "openapi.yaml 3.1 合法 + 覆盖核心链路 (design-first)"
      ;;
    build)
      sg_run "$(sg_app_bundle_coherence)" "bundle id 一致"
      ;;
    qa)
      sg_run "$(sg_app_reviewer_path)" "审核员路径产物"
      sg_run_soft "$(sg_app_multiplatform_smoke)" "多端 smoke"
      # design-first: 保真闸门,全 advisory(初期不阻塞)
      sg_run_soft "$(sg_app_design_baseline_exists)" "设计基线 manifest + baseline PNG"
      sg_run_soft "$(sg_app_ui_visual_diff)" "UI 视觉 diff (mismatch ≤3 pass)"
      sg_run_soft "$(sg_app_design_token_match)" "design token 对账 (无硬编码/不一致)"
      # 前后端 seam + 契约:全栈 app(有真后端 + 前端 api-client)→ 硬门
      #   理由:两半各自绿 ≠ 合体能跑;合体能不能握手是「正确性」不是「风格」,
      #   跟 build 过一样属于硬闸(trade-copilot 实战暴露的最大坑就是 seam 从没验过)。
      #   纯前端/纯后端/design-only/显式 defer → 维持 advisory。
      if _app_is_fullstack; then
        echo "ℹ️  检测到全栈 app(真后端 + 前端 api-client)→ 联调 + real 契约升为【硬门】(先 stack-up 起栈)。" >&2
        sg_run "$(sg_app_seam_smoke)" "前后端合体 seam 冒烟(真 HTTP 握手,后端起+endpoint 全可达)"
        sg_run "$(sg_app_integration_test)" "端到端联调(真跑通 注册→拿 token→带 token 取受保护数据)"
        sg_run "$(sg_app_contract_test)" "契约测试 target=real PASS(schemathesis 打真后端)"
        sg_run "$(sg_app_e2e_contract_smoke)" "E2E 字段对照(前后端响应字段无 drift)"
      else
        sg_run_soft "$(sg_app_seam_smoke)" "前后端合体 seam 冒烟"
        sg_run_soft "$(sg_app_integration_test)" "端到端联调"
        sg_run_soft "$(sg_app_contract_test)" "契约测试 PASS (mock/real)"
        sg_run_soft "$(sg_app_e2e_contract_smoke)" "E2E 字段对照 (前后端无 drift)"
      fi
      ;;
    ship)
      sg_run "$(sg_app_aso_complete)" "ASO 字段 + 截图脚本"
      sg_run "$(sg_app_compliance_real_scan)" "合规复扫"
      ;;
    scaffold)
      # 一次性脚手架: 仅前置 PROJECT_TYPE=app 验证, 无额外检查
      :
      ;;
    *)
      echo "Unknown gate: $gate (合法: discover|lockdown|shape|build|qa|ship|scaffold)"
      exit 1
      ;;
  esac

  # 输出结果
  local total=$(( ${#failures[@]} + ${#verified[@]} ))
  if (( ${#failures[@]} > 0 )); then
    echo "❌ A-GATE ${gate}: ${#failures[@]}/${total} 项未通过"
    for f in "${failures[@]}"; do
      echo "  - $f"
    done
    [[ ${#heuristic_warnings[@]} -gt 0 ]] && {
      echo ""
      echo "⚠️  启发式警告 (不阻塞):"
      for w in "${heuristic_warnings[@]}"; do echo "  - $w"; done
    }
    exit 1
  fi

  echo "✅ A-GATE ${gate}: ${#verified[@]} 项通过"
  for v in "${verified[@]}"; do echo "  ✓ $v"; done

  # 写 clearance (verb 名, 无 "app-" 前缀)
  local clearance="$ROOT/.claude/state/clearance-${gate}.json"
  mkdir -p "$(dirname "$clearance")" 2>/dev/null
  local spec_hash=""
  [[ -f "$ROOT/docs/spec.md" ]] && spec_hash=$(git -C "$ROOT" hash-object "$ROOT/docs/spec.md" 2>/dev/null || md5 -q "$ROOT/docs/spec.md" 2>/dev/null || echo "")
  cat > "$clearance" <<EOF
{
  "gate": "$gate",
  "verified_count": ${#verified[@]},
  "spec_hash": "$spec_hash",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "not_verified": ["商标查询(USPTO/国内)", "Google Play 同名(无 API)", "云凭证就绪(无法检测)", "Apple 审核员账号真实性"]
}
EOF
  echo ""
  echo "clearance written: $clearance"
}

# ============================================================================
# Main dispatcher
# ============================================================================

# 如果是被 source 的 (Track A 模式), 不执行 main
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  return 0 2>/dev/null || true
fi

case "${1:-}" in
  app-gate)
    shift
    cmd_app_gate "$@"
    ;;
  --help|-h|"")
    cat <<'EOF'
app-gate.sh — app 主线 skill-gate 验收

用法:
  app-gate.sh app-gate <discover|lockdown|shape|build|qa|ship|scaffold>

GATE 对应 (2-touch workflow):
  discover  → Phase A: 产品定位 + 市场 + 概念 mockup + 决策卡口 (docs/discovery-summary.md)
  lockdown  → Phase B: 真验证 (spike PASS/FAIL + 经济真数据 + 命名 evidence + 后端真值 + 合规真扫)
  shape     → A-GATE 1 产品认知 (多端矩阵 + TASK PLATFORM 字段)
  build     → A-GATE 2 实现 (bundle id 一致性)
  qa        → A-GATE 3 验收 (审核员路径 + 多端 smoke)
  ship      → A-GATE 4 上架 (ASO + 商店材料 + 合规复扫)
  scaffold  → 一次性脚手架 (仅 PROJECT_TYPE=app 校验)

Legacy alias:
  anchor    → 自动转 discover (打印 deprecation warning)

依赖:
  - docs/status.md (含 PROJECT_TYPE: app)
  - docs/spec.md (含 A-GATE 章节)
  - docs/discovery-summary.md (discover 卡口)
  - .claude/state/spike-results.json 或 spec 中 **结果**: PASS/FAIL (lockdown)
  - .claude/state/asr-survival-scan.json (lockdown 合规真扫)

输出:
  - .claude/state/clearance-<gate>.json
EOF
    ;;
  *)
    echo "Unknown command: $1"
    exit 1
    ;;
esac
