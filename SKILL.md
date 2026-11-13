---
name: game-playtest
description: 通用应用黑盒验收框架（桌面软件/Web/游戏；引擎无关 + backend 可插拔）：固定 4 Agent（Lead 只协调 / 开发白盒 / 测试黑盒 / 记录只读），按「线路→任务树→节点」逐节点验收，节点用四要素描述（人/地点/做到什么/时间=节点唯一标识），节点完成需三重确认（测试自判→开发复核→Lead 宣布）；禁作弊红线（只走用户可达路径、不直接改状态/数据）；用户数据与测试数据隔离；经验库复用、困难即停、锚点纪律、只增证据；附可观测性设计原则、通用步骤执行器、量化探针、证据/归档/人读验收模板。
---

# 通用应用测试框架 v4.0（4 Agent · 四要素任务树验收 · 应用无关 · backend 可插拔）

> **一句话**：把"像真实用户一样把应用用通"拆成**任务树节点**，由固定 4 个 Agent 分工闭环：
> Lead 协调、开发白盒修、测试黑盒验、记录只读归档；**节点全部通过才算整体通过**，
> 全程真实输入、禁作弊、证据留痕。适用于**任意带界面的应用**：桌面软件、Web/Electron、游戏。

## 0. 什么时候用

- 应用/游戏做完一版，需要"像真实用户一样"验收（而不是只跑单元测试/只看日志）；
- 使用线路多、周期长，需要**可存档、可断点续测**的结构（测过的节点不重测）；
- 需要可问责闭环：Lead 派单、开发修、测试验、记录留痕、用户可随时查看进度。

## 1. 编制与职责边界（写死）

> **团队只有 4 个 Agent：Lead、开发、测试、记录（各一名，不允许第五个角色）。**
> 顺序：Lead 统筹 → 开发（白盒设计/修复）→ 测试（黑盒验收）→ 记录（六项归档）→ Lead 汇报。

| 角色 | 视角 | 职责（只做这些） | 禁止 |
|---|---|---|---|
| **Lead** | 协调 | 与用户沟通、确认需求/取舍、拆节点并派单、收集结果、**宣布**节点结论、向用户汇报；维护锚点/窗口/单实例纪律 | 不写业务代码、不跑黑盒、不写归档；不越权替任何角色干活 |
| **开发** | 白盒 | 通读代码/数据，设计**线路→任务树**；按问题清单修复（含**同类第 2 次→设计层修复**）；回归；给测试复验口径；监控测试是否真正完成 | 不替测试做黑盒验收、不写测试/归档、不用作弊手段让节点"通过" |
| **测试** | 黑盒 | **不读源码/内存/调试日志内部**；真实键鼠/触控/文本输入逐节点验收；维护经验库（复用成功/避开踩坑）；困难即停上报问题+改进建议；节点自判（结论+证据+未达成项） | 不写验收报告/任务树/归档；**不得自宣通过**（通过需开发复核 + Lead 宣布） |
| **记录** | 只读 | Lead 显式调用后按**固定六项**归档；核对测试问题↔开发回复；维护主线任务树快照 | 不改代码、不跑应用、不读被测数据内容、不参与测试判断 |

**数据隔离铁律（v4 起，写死；游戏存档即一类实例）**：**任何情况不改用户数据**（账号、数据库、配置、
文档、存档）；自动化只操作**测试数据/测试实例**；**注入输入前必须确认当前界面状态可接收输入**
（弹窗/确认框/表单未就绪/不可交互的遮罩层禁止盲输）；破坏性操作（删除、支付、提交、覆盖）必须显式目标
+ 归属校验；**误操作到用户数据=P0 立即停手上报**。游戏版本的具体做法见
`references/standards/slot-safety.md`（用户槽/团队槽/固定锚点），应用版本按"测试账号/测试库/临时配置目录"对应。

**进度与判定纪律（写死）**：发现 bug **先保存团队进度（可复现的起始状态）再报**，下次从该状态继续、
不从头重走；节点判定 **PASS 后不复测**（用户测过的节点团队直接记录 PASS、不复测；仅用户新报该节点 bug
或该节点实现变更才重开）；**进度一=用户专用（团队只读、不写）**、**进度二=团队专用（团队续测、可覆盖）**；
团队从用户进度一接着往下做，团队跑过的进度交用户复测，用户确认后双进度对齐。详见
`references/testing/progress-first.md`、`references/testing/human-ai-dual-progress.md`。

**成员复用纪律**：节点失败/阻塞/中断 → **原成员继续**（保留经验与上下文），不换人、不按轮新建；Lead 只在
"需要设计/修复、有可测构建、节点要归档"三类时机唤醒成员，不并行、不重复唤醒。

## 2. 模型：线路 → 四要素任务树 → 节点

- **线路**：开发白盒通读后列出**所有可能的使用线路**：主流程、次要流程/分支、异常路径（错操作、边界、中断恢复）。
- **节点 = 一条线路上一段"可独立验收的最小闭环"**（应用例：完成注册并收到确认页；Web：填表提交后列表出现新条目；
  游戏例：完成一场战斗并返回地图）。
- **每个节点只用四要素描述：人（谁）→ 地点（在哪）→ 做到什么（事）→ 时间（节点标识）**；做完"事"即进入下一行"地点/状态"。
  - 人：用户，或必须交互的关键对象（控件/服务/第三方），可辨认、有真实定位；
  - 地点：页面/窗口/路由/场景 + 入口（URL、菜单路径、坐标/控件），真实可到达；
  - 做到什么：真实输入/操作 → 系统响应 → 下一地点/状态；不靠直接改数据/调内部接口/合成状态；
  - **时间（节点标识，v3.4.0 起）**：节点的**唯一标识与排序依据**，双时间：
    - `t_node`（**逻辑时间，主标识**）：单调递增的节点序号（如 `L1-N12`），用于唯一标识、排序、复测区分与离线复现；
    - `t_exec`（**物理时间，元数据**）：实际执行/取证时间（ISO-8601），用于对齐日志/截图时间线；
    - 禁止只拿 wall clock 当主键；同一节点复测标记 `t_node#retryN`（ID 不变，不新建节点）。
- **节点顺序 = 前进方向（写死）**：每节点起点=上一节点终点，只向前推进；**不做回头路验收**；防回归项单独标注、只做一次。
- 节点附加字段：编号、线路、前置、**起始锚点**、**时间标识（t_node/t_exec）**、状态、证据前缀。
- 状态机：`未开始 → 测试中 → 阻塞 → 修复中 → 已通过（存档）`；**全部线路所有节点通过 = 整体通过**。
- **双进度 + 固定锚点**：**进度一=用户专用**（只读、不写）；**进度二=团队专用**（可覆盖）；**固定锚点**=节点稳定起点
  （只读，读档/重置数据/直达 URL）。台账见 `templates/anchor-ledger.md`；机器校验用 `tools/verify/anchor_check.py`
  （追加式锚点、按 id 比对、位置容差），只读、绝不写应用状态。

## 3. 节点循环与验收门（三重确认）

1. **Lead 派开发**：设计/细化当前节点、维护任务树（含锚点）；**派测试**：只给验收标准+锚点+经验库路径，**不给代码信息**。
2. **测试执行**：先读经验库 → 真实输入按引导/路径走 → 每阶段截图+记录界面原文 → 节点自判（通过/未通过+证据+未达成项）；
   **报告与证据命名引用节点 `t_node`**（如 `r<t_node>_*`），`t_exec` 记录执行时间。
3. **困难即停**：看不懂/推不动/卡点（游戏按 **8 分钟**；Agent 另外按**步数/连续无变化**计，推荐 `step_runner` 的步数上限
   与 `hud_walker` 的 `stall_limit`）→ 停手，整理问题清单（现象/位置/截图/复现步骤/期望vs实际）+ 改进建议。
4. **开发修复**：先判**主线相关**（主线相关立即停手上报 Lead→用户给方案，用户批准前不得绕行）；非主线按普通流程修；
   测试建议逐条回应（采纳/不采纳+理由）。
5. **同类问题第 2 次 → 设计层修复**：先做设计/架构审查（提示与触发是否同源、状态是否单一收尾、数据与表现是否解耦、
   可观测性），写 `ARCH_REVIEW`（根因/为何补丁无效/改哪层/风险与回归），再修具体点；**不得用临时豁免/调试开关/让测试绕过来"通过"**。
6. **复测循环**：修完→复测，**未过不跳步**；开发可主动发起完成判定（结论+证据+复现步骤）交测试验证。
7. **三重确认（写死）**：**测试自判**（结论+证据+未达成项）→ **开发复核**（证据充分性/可复现性/验收标准）→ **Lead 宣布**
   （并可要求记录归档）。任一方说未完成→继续本节点；双方不一致→组织复核（必要时用户裁定），**Lead 不得单方面宣布通过**。
   **自动化（`step_runner`/`hud_walker`）通过 ≠ 节点通过**，它是证据来源之一。
8. **通过存档 + 颗粒度复盘**：开发更新任务树锚点并审查节点颗粒度（过粗拆/过细并/依赖与锚点调整，写理由）；任务树只记主线。
9. **记录归档**（Lead 显式调用）：固定六项，缺一不合格；同一节点多次复测**追加"复测轮次"**（`t_node#retryN`）。
10. **Lead 汇报**：按**节点完成情况**（不是轮数）向用户汇报；人读验收报告按 `templates/acceptance-report-user.md`
    （含 git diff：`-` 基线 / `+` 验收，只放两头、不要中间迭代，配图）。
11. **进度优先**：遇 bug/卡点 → **先保存团队进度**并记录位置/状态/构建 → 再报问题；后续从该进度继续。
12. **单次判定即通过**：节点 PASS 后不再复测；用户测过直接记录 PASS；仅用户新报 bug 或节点实现变更才重开。
13. **双进度人机协同**：报告 5 项：用户进度/团队进度/用户 PASS/待用户复测/下一步。

## 4. 经验库（测试侧资产，每轮必用）

- 每轮开始先读 `EXPERIENCE.md`：**成功经验 S\*** 直接复用、**踩坑经验 F\*** 主动避开；每轮结束写回新 S/F/验证状态；
  同类失败第 2 次记 `R*` 并停止硬试、给可执行建议。
- 只记"怎么做/哪里坑/怎么验证"，**不抄源码、不写实现细节**；经验可迁移但有边界（起点/视角/帧率/提示一致性变化时可能失效，需注明适用条件）。
- 详细规范：`references/standards/experience-library.md`。

## 5. 禁作弊红线（全框架适用，写死）

**禁止任何形式的"让节点看起来通过"**：跳过必经流程、自动判定成功、绕过界面直接改状态/数据库/内部接口、
跳过入场/初始化、自动置标志位、宽区域伪交互、放宽判定条件、伪造数据或截图、用调试模式/调试参数取证充当验收。

- 必须**真实输入**、页面/对白逐页/逐条确认；正常启动（无调试参数）验收；
- **主线相关问题先停手**：开发/测试先判主线相关性，主线相关立即停止操作、整理现象+证据+候选方案（≥2）上报 Lead，
  由用户决策；用户批准的取舍必须标注"用户批准"，否则结论作废；
- 每轮结束做**去作弊审计**（grep 关键词+正常启动 0 调试输出+回归），清单与清理记录见 `references/standards/no-cheat.md`。
- **游戏专用术语 → 通用含义**：传送/跳场景=直接改位置；自动胜=直接改结果；跳过对白/战斗=跳过必经流程；
  槽=用户数据实例；锚点=可复现起始状态。游戏规则见 `references/standards/slot-safety.md`、`no-cheat.md` §6。

## 6. 证据与报告规范

- **每轮独立证据目录**（`evidence/roundNN/`），文件前缀区分轮次/角色，**只增不覆盖**
  （工具已强制：同名截图自动加后缀；`tools/evidence/manifest.py` 记录 sha256 并拒绝覆盖清单）。
- 关键证据：通过/阻塞各 ≥1 张截图；异常必留 stderr 与退出取证；**每次输入追加 `input-log.jsonl`**（时间/动作/值/方式）；
  截图抗伪（PrintWindow 失败回退屏幕拷贝，判定真实画面）。
- **报告只增、版本化**：记录/验收报告用新版本文件（v1/v2/v3…），历史保留；给用户的验收报告含"三分钟看懂"+节点总表+
  git diff+配图+遗留项。
- 详细规范：`references/standards/evidence-and-acceptance.md`。

## 7. 引擎无关 + backend 可插拔

框架不绑定引擎/平台：**backend = 一组动作契约**（启动/关闭/聚焦/信息/键鼠与点击/文本/滚动/截图/读文本/状态导出），
由各平台适配实现；测试代码与工具只依赖契约。

- 契约：`scripts/backends/CONTRACT.md`（v4）。所有工具经 `tools/backendlib.py` 分发，按 `playtest.json` 的 `backend` 选后端。
- 内置后端：
  - `windows`（`scripts/windows/PlaytestKit.ps1` + `Common.ps1` + `Capture.ps1`）：键、长按、组合键、点击、文本输入、滚动、
    截图/裁剪提示条；`postmessage`（不抢光标）与 `sendinput`（真实全局输入，强制前台门禁）两种注入方式。
  - `web`（`scripts/backends/web/adapter.py`）：Edge/Chrome DevTools 协议，零第三方依赖；`click css=/text=` 只用于定位，
    真实鼠标事件，隐藏/禁用/被遮挡元素拒绝点击；`state` 导出 URL/标题/可见文本/焦点/滚动；临时独立浏览器配置（不登录、不同步、close 删除）。
- 配置：`playtest.json`（v3 schema）——`backend`、`launch/args/process_name/title_pattern/startup_ms`、
  `input{method}`、`capture{method,dpi_aware,topmost_ms,crop_hint}`、`keys{default_hold_ms,gap_ms}`、`web{...}`；
  模板 `templates/playtest.json`。
- **单实例纪律**：同一时刻只允许一个被测实例；**定位信息缺失时后端拒绝工作**（绝不匹配任意窗口）；匹配到多个候选即报错。
  多实例会导致输入/截图串目标、结论不可信。

## 8. 测试可观测性设计原则（让应用"可被验收"）

> 引擎无关、加在**被测验应用**侧（钩子/探针/调试门控），目的是让黑盒测试可判定、可量化。
> 详细模式与真实案例：`references/standards/engineering-patterns.md`。

1. **引导与可操作性同源**：提示的"下一步"必须来自与真实交互同一套可操作性判定，**禁止**提示层另行估算。
2. **提示单一来源**：同一时刻只允许一个"下一步指令源"，禁止多套提示并存/重复（重复引导=0 为验收指标）。
3. **目标链单调**：跨页面/区域的引导目标必须单调推进，不得来回翻转。
4. **等待有界**：所有等待（加载/动画/过场/网络/提交）必须有超时兜底，禁止 `busy` 永真；超时只清理 stale 状态，不跳过用户内容。
5. **输入缓冲**：低帧率/繁忙时短按可能被吞；应缓冲 1 个待处理输入步，而不是让用户"按了没反应"。
6. **遮挡与可见性**：关键控件不得被浮层永久遮挡；**不接受点击的元素必须不可点击**（禁用态要真的有禁用语义）。
7. **性能缓存**：每帧重活（全图渲染/全量查询/重建文本/同步 IO）必须缓存/节流/debug 门控；诊断日志仅在 debug 模式开启。
8. **可观测状态**：为验收提供**只读**状态出口（相当于后端 `state`），字段稳定、语义单一；正式包不得含测试后门。

## 9. 量化探针与自动验证（可选但推荐）

| 用途 | 工具（`tools/`） | 输出 |
|---|---|---|
| **通用步骤执行器（应用首选）** | `verify/step_runner.py` | 每步"真实输入→期望响应"、超时轮询、失败快照、JSONL 轨迹 |
| 轻按成功率/吞键、画面变化 | `probes/walkprobe.py` | changed/total、吞键率、最长冻结（JSON+人读） |
| 长按帧采样/卡顿 | `probes/holdprobe.py` | 变化帧、最长冻结、gap_max（JSON+人读） |
| 低帧率/卡死判断 | `probes/fps_probe.py` | 画面变化率估计 |
| HUD/引导走位（游戏） | `verify/hud_walker.py` | N 严格递减、吞键即停、位置不动即停、意外换场景即停、步数上限 |
| 起始状态校验 | `verify/anchor_check.py` | 追加式锚点、按 id 比对、位置容差 |
| 一键跑多节点 | `verify/run_verify.py` | PASS/FAIL/skip 表；能力缺失=skip 不是 PASS |
| 截图裁剪/区域哈希/像素采样 | `screen/image_ops.py`、`crop_region.py` | 裁剪图、区域差异/颜色统计 |
| 证据清单 | `evidence/manifest.py` | `evidence-index.md`（路径/sha256/分组/张数） |
| 节点 token/用时估算（可选） | `metrics/dsh_metrics.py` | 按步数占比分摊的估算 md/csv（**标注估算**） |

阈值建议（可按项目调整）：轻按成功率 <90% 判输入丢失；长按 800ms 内最长冻结 >150ms 判卡顿；
画面变化帧 <8/10 判低帧率/停顿。**量化数据必须与截图/日志同轮留档**，不能只报结论。

节点步骤文件（`templates/steps.json`）示例：

```json
{"node": "L1-N01", "steps": [
  {"do": "click", "value": "css=#user"},
  {"do": "type", "value": "ann", "expect": {"state": {"focus.value": "ann"}}},
  {"do": "click", "value": "css=#signin",
   "expect": {"text_contains": ["Welcome, ann"], "location_contains": "#/list"}, "timeout_ms": 3000, "shot": true}
]}
```

```powershell
python -B tools/verify/step_runner.py --backend playtest.json --steps n01.json --jsonl trace.jsonl
python -B tools/verify/run_verify.py  --backend playtest.json --steps "L1-N01:n01.json,L1-N02:n02.json" --anchor N01-start
```

## 10. 用户现场 bug 修复流程（用户报告的问题优先）

1. **记录原话**：用户描述（现象/场景/操作），转成可复现步骤与验收标准；
2. **黑盒复现**：测试按用户路径复现并**量化**（冻结 ms、吞键率、引导重复数、截图编号），区分主线/非主线；
3. **白盒定位**：开发只读定位根因（证据/日志/探针），出候选方案与风险；
4. **真实修复**：按根因修（同类第 2 次→设计层）；**禁作弊**；改后回归（正常启动/无调试输出/无作弊）；
5. **tester 复验**：按用户路径 + 回归清单复测；明确未覆盖项；
6. **回执新 hash**：给 Lead/用户可复测的新构建 hash + 复验清单 + 已知遗留；用户实机确认后再出报告新版本。

## 11. 快速开始

```text
1) 安装：  powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun   # 预演
           powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Force    # 安装
2) 配置：  复制 templates/playtest.json 到项目根，填 backend/launch/定位（示例见 examples/）
3) 自检：  python -B tools/tests/selftest.py ；python -B tests/Test-WebBackend.py
4) 建团：  Lead + 开发 + 测试 + 记录（各 1）；把 references/roles/*.md 作为成员 prompt
5) 开测：  Lead 派开发设计线路/任务树 → 派测试逐节点验（step_runner + 人工观感）→ 修复/复测 → 三重确认 → 记录归档
```

## 12. 文件与引用

- `README.md`：概述/架构/安装/接入/配置/工具/模板/FAQ/目录
- `references/roles/`（4 篇）：`lead.md`、`developer.md`、`tester.md`、`recorder.md`（可直接作 subagent prompt）
- `references/standards/`（7 篇）：`no-cheat.md`、`slot-safety.md`（数据隔离铁律的游戏版）、`anchors-and-saves.md`、
  `evidence-and-acceptance.md`、`experience-library.md`、`engineering-patterns.md`、`troubleshooting.md`
- `references/testing/`（6 篇，由测试角色维护）：`playbook.md`、`probes-and-metrics.md`、`case-studies.md`、
  `efficiency.md`、`progress-first.md`、`human-ai-dual-progress.md`
- `scripts/`：Windows 参考后端（`Common.ps1`/`PlaytestKit.ps1`/`Capture.ps1`）、Web 后端（`backends/web/adapter.py`）、
  契约 `backends/CONTRACT.md`
- `tools/`：`backendlib.py`（统一分发）、`verify/`（step_runner / hud_walker / anchor_check / run_verify）、
  `probes/`、`screen/`、`evidence/`、`metrics/`（Python 3.8+）
- `templates/`（17 个）：playtest.json、**steps**、task-tree、tester/developer/lead prompt、experience-log、bug-ledger、
  recorder-log、report、acceptance-report、acceptance-report-user、node-metrics、defect-table、ablation-plan、
  anchor-ledger、evidence-index
- `examples/`：`web-app.json`、`generic-desktop.json`、`pal98-godot.json`、`pal98-walk-specs.json`、`godot-project.md`
- `tests/`：打包自检 `Test-Plugin.ps1`、Windows 后端真机测试 `Test-Backend.ps1`（fixture 窗口）、
  Web 后端端到端 `Test-WebBackend.py`（headless）
- 插件清单以 `plugin.json` 为准（v4.0.0：2 个参考后端；templates 17 / references 20 / examples 5）。
