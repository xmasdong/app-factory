# App Factory — AI 驱动的「产品 → 上架」全流程 skill 工厂

把一句话产品想法,经 AI 自主流水线,带硬闸门地推到 **App Store / Google Play 可提审**。

> 这是把现有零散的 app 开发 skill **合并成一条统一流水线**的编排仓。
> 脊柱 = 7-skill 出海生命周期(scaffold→discover→lockdown→shape→build→qa→ship);工具 skill(出图/截图/过审/上传/UI 设计)插进对应闸门。

## 一句话流程

**入口:`/app-factory`**(读 `docs/status.md` 自动派到当前关;7 关也可各自单调)

```
/app-factory → scaffold → discover(选品+技术栈初选) → 🛑你看mockup → lockdown(真验证+技术栈定稿)
            → shape(规格) → build(实现+UI+美术) → qa(验收) → ship(上架材料+真上传)
```

全程 AI 自主,**只在看 mockup 时找你一次**(2-touch)。每关有机械验收闸门,过不了不放行。

## 闸门哲学:建议优先,不硬锁

每个人开发 app 都按自己的要求来。**本工厂的闸门默认是「建议」不是「强制」** —— 跑出自检清单、列出没满足的项,但**不阻塞你**,你自行决定取舍。

- **默认(advisory)**:闸门 = 建议清单,照样放行
- **严格(strict)**:`export APP_FACTORY_MODE=strict` → 闸门硬阻塞(适合 CI、或想被流程逼着做全的自用场景)

机制:所有闸门 hook 经 `app/hooks/_lib.sh` 的 `emit_blocked`,默认建议模式下只提示 + 放行。

## 安装 / 使用

**前置**:[Claude Code](https://claude.com/claude-code)(skill 机制依赖它)。skill 内容中文为主。

```bash
# 1. clone
git clone git@github.com:xmasdong/app-factory.git

# 2. 让 Claude Code 发现 skill —— 软链进个人 skill 目录(所有项目可用)
ln -s "$(pwd)/app-factory/skills/"* ~/.claude/skills/
#    (或拷贝;或软链到 <某项目>/.claude/skills/ 做项目级)

# 3. 设运行依赖 —— scaffold 从这里拷模板/规则/hooks 到新项目
echo 'export AI_RULES_ROOT="'$(pwd)'/app-factory"' >> ~/.zshrc && source ~/.zshrc
```

**用**:
```
# 在一个空目录(你要做的新 app)开 Claude Code
/app-factory          # 一个命令进,读 docs/status.md 自动派到当前关
# 或从头:/scaffold 描述"做 X" → /discover → 看 mockup 回"推进" → 自动链到上架
```

**各工具 skill 按需的凭证**:
- `codex-image-bridge`(出图/图标/素材)→ ChatGPT / Codex 登录
- `ios-ship-cli`(真上传 TestFlight/App Store)→ fastlane + Apple Developer 账号
- `app-store-review-survival` / `app-store-screenshots` / `frontend-design` 簇 → 无需额外凭证

> ⚠️ 跨端原生构建(iOS/Android)需各自工具链(Xcode / Android SDK / Flutter 等);本工厂管流程与产物,不替代构建环境。

---

## 完整流水线(脊柱 + 插入的工具 skill)

| 阶段 | Gate | 脊柱 skill | 插入工具 skill | 产物 |
|---|---|---|---|---|
| 0 初始化 | — | `scaffold` | — | app 项目骨架(hooks/模板/PROJECT_TYPE=app) |
| 0.5 环境预检 | — | `preflight` | — | env-probe.json(本机工具链+MCP)→ 发布目标→环境约束定栈/后端 |
| 1 探索 | Discovery | `discover` | `codex-image-bridge`(出 mockup) | 产品定位+市场调研+概念视觉+summary |
| 🛑 TOUCH | — | _你看 mockup_ | — | 推进 / 换方向 / 暂停 |
| 2 锚定 | Lockdown | `lockdown` | `app-store-review-survival`(合规) | 技术spike+单位经济+命名锁定+后端+合规 |
| 3 规格 | A-GATE 1 | `shape` | `frontend-design`(设计方向) | 完整 spec(PRD挑战/多端矩阵/数据契约/任务) |
| 4 实现 | A-GATE 2 | `build` | `frontend-design` + `polish/animate/colorize/harden`(UI 质量) | 代码+测试+commit |
| 5 验收 | A-GATE 3 | `qa` | `audit`(无障碍/性能) + `app-store-screenshots`(截图) + `app-store-review-survival`(复扫) | 多端smoke+**拉真栈联调(stack-up→seam+端到端+契约→stack-down)**+截图存档+审核员预演 |
| 6 发布判定 | — | _generic release_ | — | release-ready |
| 7 上架 | A-GATE 4 | `ship` | `app-store-screenshots`(商店图) + `app-store-review-survival`(终扫) + `ios-ship-cli`(真上传) | 商店材料 + TestFlight/App Store 提交 |

## 为什么靠谱(不是玩具)

- **每关机械自检**(`sg_app_*` 检查函数)——**默认只给建议、不阻塞**(尊重各人开发流程,我们只提供建议);要硬闸门(CI / 严格自用):`export APP_FACTORY_MODE=strict`
- **AI 自决要附证据**(市场调研禁用训练记忆,必须真 URL/API 响应)
- **决策生命周期**(optimistic / deferred / frozen / fused)+ 熔断器防死循环
- **多端一致性**强约束(PLATFORM 字段贯穿任务/数据契约/能力矩阵)

## 现状

- ✅ 脊柱 7 skill 已内置 `skills/`(scaffold/discover/lockdown/shape/build/qa/ship),去项目耦合、可移植
- ✅ 工具 skill 已内置:app-store-review-survival / app-store-screenshots / codex-image-bridge / ios-ship-cli + frontend-design 簇(21)
- ✅ 3 缺口已接:UI 簇 → shape/build/qa;ios-ship-cli → ship;app-store-screenshots → qa/ship
- 🎨 **design-first**(导入图/设计稿 → 高保真 app + 完整后端 API):新增 `design-restore`(设计→高保真app)+ `backend-forge`(功能/契约→后端API)两 skill,经 manifest + openapi 两份机读产物当桥,接进 shape/build/qa(闸门 advisory)。详见 **`ROADMAP-design-first.md`**
  - **执行模型**:这两 skill 主路径 = AI 在会话内调用 **Workflow 工具**(Claude 内置工具)做多 agent 编排;skill 用自然语言描述编排意图(扇出哪些子任务 / parallel / pipeline / 对抗验证 / loop 条件 / 各 agent 职责 / 产物落点),AI 据此**现场组合并执行 script**。`scripts/design-first/*.workflow.js` **不是传给工具运行的脚本,而是编排蓝图参考**(展示推荐扇出结构,供 AI / 人参考)。**推荐用户开 ultracode 会话模式**(让 AI 默认倾向编排,非 skill 可强制);未开 / 不便编排时降级为单 agent 顺序。**不存在 `claude workflow` shell 命令。**
- 🧭 **preflight 环境预检**(新):`env-probe.sh` 扫本机工具链(flutter/xcode/android/node/wrangler/supabase/docker...)+ 已配置 MCP → 推导构建能力 + 后端可选项;`preflight` skill 问发布目标(全端→Flutter)→ **只推环境能真正构建/授权的栈**,没装没授权的标 `how_to_enable`(如 Supabase 需先授权 MCP)。喂 `tech-stack-decision.md` 决策矩阵 §0 环境闸。
- 🔌 **qa 补硬门**(新):全栈 app(真后端+前端 api-client)→ `seam-smoke.sh`(真 HTTP 探测前端声明的 endpoint 在真后端是否都可握手)+ `contract-test.sh --target real` + `e2e-contract.sh` **升为硬门**——堵住"两半各自绿、合体从没跑过"的坑(trade-copilot 实战暴露)。非全栈/design-only 维持 advisory。
- 🧠 **通用约束 + 自纠正**(新,核心):从 16 个历史 app/游戏 build 的 111 条「用户不得不纠正 AI」提炼出 `app/rules/build-constraints.md` —— **8 条透镜式通用约束 + 元则(别走最省事直译、别用最弱证据自证)**,刻意**不写死案例**(换产品就失效 + 杀判断),给 AI 自问句让它自己推当前产品该注意啥。配 `/self-correct` skill:交付前拿 8 约束自省(问题固定、答案现推),build 收尾 + qa 前自触发。同时**把 core.md 里限制死没想象力的规则改成原则式**(多端矩阵去写死列→声明本产品相关轴;单位经济免费/ASO 可跳;通篇"就本产品该答的问题,不适用说明跳过"),保留不可逆护栏(命名/价格单调/合规/密钥)。
- 🔗 **真实环境联调基建**(新):`stack-up.sh` 一键拉起全栈(docker compose 优先起 PG/Redis/后端;`--native` 进程起零依赖)+ 写前端 env 指向真后端;`integration-test.py` 打真后端跑**真端到端联调**(注册→拿 token→带 token 取受保护数据,从 live `/openapi.json` 自动派生或读 `api/integration-flow.json` 黄金流);`stack-down.sh` 收摊。qa Step 1.5 串起「拉栈→seam+联调+契约→收摊」,`integration-test.json` result=PASS 才是**"联调成功"硬证据**。已在 trade-copilot 实测:register→token→`/api/positions` 200 全绿。
- ✅ 依赖(rules/templates/hooks/scripts)全内置,无硬编码路径,clone 即用
- 📋 详细编排 + 机械闸门 + 仓库结构:**见 `ORCHESTRATION.md`**

## 详见

`ORCHESTRATION.md` — 主编排 runbook(逐关细节 + 合并动作 + 机械闸门 + 仓库结构)
