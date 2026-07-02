---
name: scaffold
description: "Scaffold a new app-track project — copy spec/status templates, install app-specific hooks, register Stop/PreCommit hooks, write status.md with PROJECT_TYPE=app and CURRENT_GATE=A-GATE 0. One-shot initialization, run once per project."
---

# /scaffold — 初始化 app 主线项目

> 🎨 **design-first 入口**:Step1 入口判定加第三态——用户**已有完整设计稿**(.pen/Figma/截图目录)时,置 `PROJECT_TYPE=design-first`(**不新增 CURRENT_GATE 取值**),并建 `docs/design/` 与 `api/` 目录占位。后续:discover 轻量旁路、shape 调 design-restore + backend-forge。终极目标=导入图/设计稿→产出能上线生产的 app。

**作用:** 把空目录或已有项目改造成可走 5 道 A-GATE 的 app 主线项目. 一次性脚手架, 跑完后由 /anchor 接手.

**INPUT_CONTRACT:**
- 用户大致知道要做什么 app (一句话产品描述)
- 已确认走 app 主线 (有 iOS / Android 原生构建产物 + 计划上架)
- 目标目录可写 (空目录, 或用户明确确认在已有目录初始化)

**CONTRACT 不满足时:** 拒绝执行. 输出三选一:
1. "你这个项目有 iOS / Android 原生构建产物吗? 是否上架? 不上架 → 用 generic /setup, 不是 /scaffold"
2. "项目目录是? 空目录还是已有代码"
3. "一句话描述要做什么 app"

**与 generic /setup 的关系:** /scaffold 不调 /setup, 是独立分支. 思想层共享 (任务链续接 / 决策生命周期, 参照 `.claude/rules/core.md`), 产出物不同 — /scaffold 输出 5 个 A-GATE 骨架 + PLATFORM-MATRIX 占位 + bundle id 锁定模板.

**OUTPUT → `docs/spec.md` (app 骨架) + `docs/status.md` (PROJECT_TYPE=app) + `.claude/hooks/` (app 专属 hook 注册) + skill-signal.json**

---

## 执行计划

```
- [ ] Step 1: 确认项目类型 = app
- [ ] Step 2: 询问技术栈预期 (4 条问答)
- [ ] Step 3: 复制模板到项目根
- [ ] Step 4: 复制 app 专属 hook
- [ ] Step 5: 注册 hook 到 .claude/settings.json
- [ ] Step 6: 初始化 status.md (顶部含 PROJECT_TYPE / CURRENT_GATE)
- [ ] Step 7: 写完成信号
```

---

## Step 1: 确认项目类型

直接问:

> "你这个项目是 app 主线吗? 两条确认:
> 1. 有 iOS 或 Android **原生构建产物** (Xcode archive / Android App Bundle) 或基于 Flutter / RN / Capacitor / Tauri 等可输出原生包的框架?
> 2. **计划上架** App Store / Google Play / 第三方商店, 或下发到企业 MDM?
>
> 两条都是 → app 主线 (本 skill). 任一不是 → 用 generic /setup, 走 4 道 GATE."

用户确认 → 继续. 用户犹豫 → 引用 README.md "何时选 app 主线".

---

## Step 2: 询问技术栈预期

```
1. 跨端方案: SwiftUI 原生 / Kotlin 原生 / Flutter / React Native / Capacitor / Tauri / 其他
2. 后端: 已有 / 待建 / 不需要 (纯端)
3. AI 调用: OpenAI / Anthropic / 本地推理 / 无
4. 商业模式: 免费 / IAP 订阅 / IAP 一次性 / 广告 / 待定
```

**重要:** Step 2 是**预期**, 真实可行性由 A-GATE 0 (`/anchor`) 的 technical spike 验证. 这步只为填模板, 不锁定技术决策.

---

## Step 3: 复制模板到项目

```bash
# PROJECT_ROOT = 目标项目根;AI_RULES_ROOT = app-factory 仓库根。
# ⭐ Step 0(开箱兜底):用户没 export AI_RULES_ROOT 时,从 skill 软链自动反推仓路径——
#   安装时 skills/* 被软链进 ~/.claude/skills/,readlink 回去就是仓。推不出才要求用户设。
if [[ -z "${AI_RULES_ROOT:-}" || ! -d "${AI_RULES_ROOT:-}/app/templates" ]]; then
  for _cand in "$PROJECT_ROOT/.claude/skills/scaffold" "./.claude/skills/scaffold" "$HOME/.claude/skills/scaffold"; do
    _lnk="$(readlink "$_cand" 2>/dev/null)" || continue
    [[ -n "$_lnk" ]] || continue
    _root="$(cd "$(dirname "$_lnk")/.." 2>/dev/null && pwd)"
    [[ -d "$_root/app/templates" ]] && { AI_RULES_ROOT="$_root"; break; }
  done
fi
if [[ -z "${AI_RULES_ROOT:-}" || ! -d "$AI_RULES_ROOT/app/templates" ]]; then
  echo "❌ 找不到 app-factory 仓:请 export AI_RULES_ROOT=<clone路径>(见仓 README 安装第3步),或确认 skills 已软链进 ~/.claude/skills/" >&2
  # AI:把上面这句原样告诉用户并停住,不要在错误路径上继续 cp
fi

mkdir -p "$PROJECT_ROOT/docs"
mkdir -p "$PROJECT_ROOT/.claude/hooks"
mkdir -p "$PROJECT_ROOT/.claude/state/evidence"
mkdir -p "$PROJECT_ROOT/.claude/rules"
mkdir -p "$PROJECT_ROOT/.claude/scripts"

# spec 骨架 (含 5 个 A-GATE 0 占位章节)
cp "$AI_RULES_ROOT/app/templates/spec.md.tmpl" "$PROJECT_ROOT/docs/spec.md"

# status 骨架 (含 PROJECT_TYPE / CURRENT_GATE)
cp "$AI_RULES_ROOT/app/templates/status.md.tmpl" "$PROJECT_ROOT/docs/status.md"

# CLAUDE.md (项目主入口)
cp "$AI_RULES_ROOT/app/CLAUDE.md.tmpl" "$PROJECT_ROOT/CLAUDE.md"

# app 门禁规则 (core + generic 兜底, CLAUDE.md 都引用)
cp "$AI_RULES_ROOT/app/rules/core.md" "$PROJECT_ROOT/.claude/rules/core.md"
cp "$AI_RULES_ROOT/app/rules/generic-core.md" "$PROJECT_ROOT/.claude/rules/generic-core.md"
# ⭐ 通用约束(判断力地基, build-constraints + core.md/CLAUDE 都引用, /self-correct 读它)
cp "$AI_RULES_ROOT/app/rules/build-constraints.md" "$PROJECT_ROOT/.claude/rules/build-constraints.md"

# ⭐ app-gate.sh 机械验收脚本 —— 必拷:hooks 在 $ROOT/.claude/scripts/app-gate.sh 找它,不拷=闸门全跑不了
cp "$AI_RULES_ROOT/scripts/app-gate.sh" "$PROJECT_ROOT/.claude/scripts/app-gate.sh"
chmod +x "$PROJECT_ROOT/.claude/scripts/app-gate.sh"

# ⭐ env-probe.sh 环境预检 —— /preflight 用它扫本机工具链+MCP,喂技术栈/后端决策矩阵
cp "$AI_RULES_ROOT/scripts/env-probe.sh" "$PROJECT_ROOT/.claude/scripts/env-probe.sh"
chmod +x "$PROJECT_ROOT/.claude/scripts/env-probe.sh"

# ⭐ ai-rules.sh 执行工具 —— 必拷:stop-skill-gate/pre-commit-scope/post-commit-next-task/
#   stop-politeness-guard 等 hook 都在 $PROJECT_ROOT/scripts/ai-rules.sh 找它;不拷 = 这些
#   hook 静默退化 honor system(无人值守时机械验收整层失效)。文件名保留 ai-rules.sh 是
#   hook 兼容需要(历史名),工具本身通用无耦合。
mkdir -p "$PROJECT_ROOT/scripts"
cp "$AI_RULES_ROOT/scripts/ai-rules.sh" "$PROJECT_ROOT/scripts/ai-rules.sh"
# ⭐ 步骤台账工具(闸门验台账;治"凭记忆复刻流程")
cp "$AI_RULES_ROOT/scripts/skill-ledger.sh" "$PROJECT_ROOT/scripts/skill-ledger.sh"
chmod +x "$PROJECT_ROOT/scripts/ai-rules.sh"

# ⭐ 游戏项目:提示挂基座(juice_kit path 依赖 + 资产工位),别从零写质感件
#   见 $AI_RULES_ROOT/bases/game-flutter/README.md(pubspec: juice_kit path 依赖)
# (可选) design-first 确定性脚本 —— 走 design-first 时才需要
if [[ -d "$AI_RULES_ROOT/scripts/design-first" ]]; then
  cp -R "$AI_RULES_ROOT/scripts/design-first" "$PROJECT_ROOT/.claude/scripts/design-first"
fi
```

**模板占位符必须由 AI 主动填:**
- `${PROJECT_NAME}` → 用户提供
- `${TECH_STACK}` → Step 2 答案组合
- `${IOS_BUNDLE_ID}` / `${ANDROID_APP_ID}` / `${STORE_NAME}` / `${DOMAIN}` → 标 `<TBD: A-GATE 0 锁定>`, 不凭空填
- `${RUN_CMD}` / `${TEST_CMD}` / `${IOS_BUILD_CMD}` / `${ANDROID_BUILD_CMD}` / `${LINT_CMD}` → Step 2 答案默认值, 用户确认

---

## Step 4: 复制 app 专属 hook

```bash
# app-factory 把所有 hook 统一放在 app/hooks/(含 _lib.sh + pre-commit-scope + post-commit-next-task
# + stop-politeness-guard + stop-skill-gate + stop-app-audit + pre-compact-dump + pre-anchor-check
# + pre-prompt-resume-detect + pre-edit-design-remind 等)。一条 cp 全拷。
cp "$AI_RULES_ROOT/app/hooks/"*.sh "$PROJECT_ROOT/.claude/hooks/"
chmod +x "$PROJECT_ROOT/.claude/hooks/"*.sh
```

**app 专属 hook 与 generic hook 协调:**

| Hook | 作用 |
|------|-----|
| `stop-app-audit.sh` (app) | 检测 A-GATE 状态 + 验收 app 产出物; PROJECT_TYPE != app → exit 0 不干扰 |
| `pre-commit-bundle-coherence.sh` (app) | 验 bundle id 跨文件一致, 改 Info.plist/build.gradle/app.json 时触发 |
| `pre-anchor-check.sh` (app) | A-GATE 0 命名锁验证, /anchor skill 触发 |
| `stop-skill-gate.sh` (generic) | 通用 skill 完成信号检测 |

---

## Step 5: 注册 hook

如项目无 `.claude/settings.json`, 创建(⭐ **app 项目注入 `APP_FACTORY_MODE=strict`**:无人值守自收敛 loop 的前提是硬闸;advisory 只给建议不阻塞,回灌无从谈起。工厂仓自身/非 app 项目维持 advisory):

```json
{
  "env": { "APP_FACTORY_MODE": "strict" },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/pre-commit-scope.sh"},
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/pre-commit-bundle-coherence.sh"}
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/post-commit-next-task.sh"}
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/stop-app-audit.sh"},
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/stop-skill-gate.sh"},
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/stop-politeness-guard.sh"}
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/pre-compact-dump.sh"}
        ]
      }
    ]
  }
}
```

**Stop hook 顺序:** `stop-app-audit` 在 `stop-skill-gate` 之前. app-audit 先跑, PROJECT_TYPE != app → exit 0 不阻塞链; app-audit 发现 A-GATE 验收失败 → exit 2 阻塞, skill-gate 不会再跑.

---

## Step 6: 初始化 status.md

写入项目根 `docs/status.md`, **顶部必须包含**:

```markdown
# 项目状态

PROJECT_TYPE: app
PROJECT_PHASE: building
CURRENT_GATE: A-GATE 0
AUTONOMOUS: false

## A-GATE 进度
- [ ] A-GATE 0 外部锚定 (命名 / 经济 / spike / 后端 / 合规)
- [ ] A-GATE 1 产品认知 (spec.md 主体 + 多端能力矩阵)
- [ ] A-GATE 2 实现 (代码 + 测试)
- [ ] A-GATE 3 验收 (测试通过 + 截图 + 审核员路径)
- [ ] A-GATE 4 上架 (ASO + 商店材料 + 隐私问卷)

## 当前状态
项目刚初始化. 下一步: 进入 A-GATE 0, 执行 /anchor 锁定外部世界.

## 任务进度
(由 /shape 之后产出)

## 放弃的方案
(stabilizing 阶段起强制存在)

## 待确认清单
(GATE 2 决策, 待 /anchor 阶段填入)

## 技术决策
- 跨端方案: <TBD, A-GATE 0 spike 后锁定>
- 后端: <TBD, A-GATE 0 backend-readiness 锁定>
- 商业模式: <TBD, A-GATE 0 economics 锁定>

## 下一步
执行 `/anchor` 进入 A-GATE 0.
```

**为什么 PROJECT_TYPE 在顶部:** `stop-app-audit.sh` 第一件事就是 grep `PROJECT_TYPE: app`. 这是 app 主线和 generic 主线"互不串扰"的根基.

---

## Step 7: 写完成信号

```bash
mkdir -p "$PROJECT_ROOT/.claude/state"
echo "{\"skill\":\"app-setup\",\"epoch\":$(date +%s)}" > "$PROJECT_ROOT/.claude/state/skill-signal.json"
```

**注意:** signal 文件 `skill` 字段保持 `app-setup` (与 app-gate.sh 内部 cmd_skill_gate 调用名一致). 用户面向 `/scaffold`, 内部 clearance/signal 保持 `app-setup`.

---

## OUTPUT_GATE

`stop-app-audit.sh` 在 AI 宣称 /scaffold 完成时机械检查:

1. `docs/spec.md` 存在
2. `docs/status.md` 存在 + 顶部含 `PROJECT_TYPE: app` + `PROJECT_PHASE: building` + `CURRENT_GATE: A-GATE 0`
3. `.claude/hooks/stop-app-audit.sh` 存在且可执行
4. `.claude/hooks/pre-commit-bundle-coherence.sh` 存在
5. `.claude/settings.json` 注册了 stop-app-audit hook
6. `CLAUDE.md` 存在且声明 app 主线

任一缺失 → 阻塞 + 列缺失项.

---

## 不做的事

- 不创建第三方依赖 (npm install / pod install / gradle sync) — 留给 spike 阶段
- 不写代码 — A-GATE 0/1 未过, 写代码 = 跳门禁
- 不假设技术栈细节 — Step 2 只是预期, spike 才真验证

---

## 完成后下一步

告诉用户:

> "/scaffold 完成. **下一步先跑 `/preflight`**(扫本机工具链+MCP → 问发布目标 → 环境约束下定栈/后端),再进 `/discover`(A-GATE 0)。
> preflight 是为了别在真空里选栈——装了 Xcode 才推 iOS 原生、装了 flutter 且要全端才推 Flutter、Supabase 要先授权 MCP 才算可用。"

**可选:scaffold 末尾直接跑一次环境预检**,让用户马上看到本机底牌:

```bash
bash "$PROJECT_ROOT/.claude/scripts/env-probe.sh"
```

`完成: /scaffold 已初始化 app 主线骨架, 下一步执行 /preflight(环境预检+定栈)→ /discover 进入 A-GATE 0`
