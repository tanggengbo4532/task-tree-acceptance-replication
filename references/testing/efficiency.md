# 测试效率架构 · 验证自动化层（v3.2）

> 版本：**v3.2.0**｜状态：**新增验证自动化层**（任务树 + 锚点/walker 断言，不替代人工验收）
> 目标：把"对错可自动判"的部分交给机器、把"观感/手感"留给人——**单节点自动验证目标 < 2 分钟**（过去长距离重走 20+ 分钟）。
> 路径说明：插件侧工具为 `tools/verify/{common,hud_walker,anchor_check,run_verify,selftest}.py`（v3.2.0 已落盘）；项目侧参考实现 `_playtest_regress_dev/tools_r78/`（同名 Python 工具；`run_verify.ps1` 为项目侧旧脚本参考）。相关：`references/backends/CONTRACT.md`（若存在；否则见 `scripts/backends/CONTRACT.md` §6）、`references/testing/playbook.md`、`templates/anchor-ledger.md`。

## 0. 一句话与分层

**自动跑"对错"，人工跑"观感"**：
- **自动断言（机器）**：引导方向/剩余步数是否严格递减、方向是否可走、是否抖动、是否意外切场景、门/阶段/战斗链路是否通、回归套件是否绿；
- **人工观察（人）**：画面/文案是否正确、手感/动画/UI、剧情语义与剧情节点卡是否一致、异常现象复现与描述。

> 前提：**仍是真实按键**（注入方向键，不传送/不跳剧情/不改状态）；自动化只是"快速走+自动核对"，不是作弊。

## 1. 节点锚点库（合法测试存档锚点）

- **是什么**：为每个可验收节点/章节段准备**合法测试存档锚点**（测试专用槽位，如槽三/四/五；**绝不使用用户进度槽**），读档即到节点起点，替代"从头长距离重走"。
- **收益（实测口径）**：单节点验证从 **~20 分钟 → ~1~2 分钟**（读档 + 走关键段），报告可写明"读档 N 次、未存档、锚点未覆盖"。
- **纪律（写死）**：
  1. **只读**：只载入不覆盖/不删除原槽；除必要读档外全程不存档；
  2. **合法**：禁用调试跳转/传送/内存改状态制造锚点；合成状态必须标注"合成"，结论单独定性；
  3. **登记**：新锚点需 Lead 批准并写入 `templates/anchor-ledger.md`（节点 id/场景/楼层/坐标/槽位/用途/有效性校验）；
  4. **有效性校验**：读档后用 `anchor_check.py`（或 backend `state` 导出）输出 `scene/floor/pos/flags/central_text`，与台账一致才算有效；漂移=停止并报告；
  5. **版本兼容**：改场景表/存档字段后，dev 回执必须写"旧档可用/需迁移/不可用"；不可用则保留旧档、重建并更新台账。
- **锚点粒度**：节点（或章节段）级别；锚点缺失=节点过粗 → 先拆/补锚点，不得"从头全跑当进度"。

## 2. Headless HUD 走位器（自动断言）

- **输入（实际 CLI）**：`--backend <backend.json>`（verification backend 配置）、`--path <内置路径名>`（A12/A14_1F/A14_2F/A13_PRE/DOCK）或 `--specs <自定义 JSON>`、`--jsonl <输出轨迹>`、`--max-steps`（默认 ≤1200）、`--selfcheck`（无窗口自检）；退出码 0=通过/1=断言失败/2=backend 不支持或配置错误。
- **循环**：读取当前 HUD 状态（backend `state` 导出或中央提示解析：`scene/floor/pos/central_text/objective`）→ 从中央提示解析**下一步方向 + 剩余 N** → 注入方向键（`keys`/`hold`，**真实按键**）→ 记录 JSONL 一步。
- **JSONL 每步字段**：`ts, scene, floor, pos, N, dir, central_text, objective, key, moved`。
- **自动断言（fail 即停 + 失败快照）**：
  | 断言 | 判据 |
  |---|---|
  | N 严格递减 | 连续 2 步 N 不下降/回升 → fail |
  | 方向可走 | 同方向按键连续 3 步位移 0 → fail（被挡/指向不可走） |
  | N 不抖动 | 相邻方向反复（A→B→A）超过阈值（如 3 次）→ fail |
  | 无意外切场景 | 出现非目标场景切换（尤其门/出口误传）→ fail（**排门**：场景门引起的大帧变化不得当作"走成功"） |
  | 超时/步数上限 | > 1200 步 → fail |
- **输出**：`walk-report.md`（节点/路径/每步 N/失败点/证据路径）+ 失败时 `failures/` 快照；按任务树节点验收点直接核对并记录证据。
- **已知坑（真实案例 F-R76e-1）**：以"画面变化=走成功"自动选方向时，街道↔客栈场景门切换的大变化会被误判为可走 → 角色被带回上一场景并卡角落。**必须排门 + 以状态导出（pos/scene）判位移，不以画面变化判移动**。

## 3. 任务树节点核对

- 走位器/手动记录（ts/scene/floor/pos/N/dir/central_text）直接对照 `templates/task-tree.md` 节点验收点；证据进验收报告。
- 差异类型：缺失（该到的节点没到）/多余（去了不该去的场景）/位置（scene/floor/pos 不符）/引导（central_text 与剧情节点卡 guidance 不符）/阶段（objective 未推进/回退）；
- 产出进验收报告；**判对错的是 diff，判原因的是开发**（tester 不判原因）。

## 4. 分层测试（谁测什么）

| 层 | 内容 | 谁做 | 说明 |
|---|---|---|---|
| **自动断言层** | 引导（方向/N/抖动/意外切场景）、门/出口、阶段推进、战斗链路、回归套件 | `hud_walker` + `run_verify`（机器） | 失败即快照+停；结果进报告 |
| **人工观感层** | 画面/文案/UI/手感/动画、剧情语义、卡点描述、异常复现 | tester（黑盒人） | 自动化跑过的基础不再重复手走；tester 专注"看起来/玩起来对不对" |
| **白盒层** | 根因定位/设计层修复/数据校验 | developer | 自动断言失败时用快照+trace 定位，真实的修复仍必须真实触发 |
| **归档层** | 结论/证据/章节报告/剧情树 status | recorder | 只读，锚点次数/未覆盖声明入档 |

> 分层不是降标准：**自动断言通过 ≠ 节点通过**；仍需 tester 观感 + dev 复核 + Lead 宣布（三重确认不变）。

## 5. test-fast 测试开关（仅测试构建）

- **只加速时间**：过场/淡入淡出/对白打字/ride 动画等**时间缩放**（如 10×），默认关闭；
- **不改逻辑**：不跳剧情、不跳战斗、不改状态/道具/阶段；**与 cheat 严格区分**（cheat=授予/跳过，test-fast 只改时间）；
- 开启时 HUD 显示**测试模式角标**；证据/报告必须注明"test-fast=on"；正常启动无参数默认关闭；
- 用途：长过场/对白/骑乘段的回归提速；**验收观感类**（动画是否自然/文案节奏）不得用 test-fast 结论。

## 6. 失败快照（fail 现场三件套）

- **何时**：走位器断言 fail / 回归项 fail / 手动测试发现阻断瞬间；
- **保存内容**（到 `_playtest_regress_dev/roundNN/failures/` 或项目约定失败目录）：
  1. **截图**：失败瞬间完整客户区帧（绝对路径）；
  2. **最近 30 帧按键**：时间/键/按下时长/间隔；
  3. **状态 JSON**：`scene/floor/pos/flags/central_text/objective/busy/…`；
- **命名**：`fail_<节点>_<yyyymmdd-HHMMSS>_<seq>`；报告登记路径；快照是证据，不进版本库大文件（按项目约定）；
- 用途：tester 复现/开发定位/归档证据；**快照不替代验收结论**。

## 7. 回归套件 `run_verify`（一条命令）

- 把"可自动跑"的回归项打包：P0 新开局链、fadecheck、cheat 扫描、streetkeys、a9exit/room、RNG 残留、走位器覆盖节点路径（A12~A15 等）；
- **一条命令**：`python -B tools/verify/run_verify.py --backend backend.json --paths A12,A14_1F,A14_2F,A13_PRE,DOCK --jsonl walk-report.jsonl --ledger anchor-ledger.json` → 输出 **PASS/FAIL 清单**（每项：名称/结果/耗时/证据路径/失败快照）；退出码 0=全过；项目侧参考 `_playtest_regress_dev/tools_r78/run_verify.ps1`。
- 用法：每次提交后跑；全绿才进入人工验收；FAIL 项逐条修/复验（同类第 2 次→设计层修复）；
- 插件侧：`tools/verify/run_verify.py`（v3.2.0 已落盘，参数见上）；`common.py` 为共享 backend 调用层。

## 8. 指标（必须记录，防"自动化后反而更慢"）

| 指标 | 定义 | 目标/口径 |
|---|---|---|
| 单节点验证耗时 | 锚点读档→walk-report 完成（含人工观感） | **< 2 分钟/节点**（目标）；记录实测 |
| 复走次数 | 同一节点重跑次数（含失败重试） | 越少越好；失败重试计入 |
| 误报率 | 自动断言 fail 但人工判非问题 | 定期抽样；高则修断言/排门 |
| 漏报率 | 自动断言 pass 但人工/用户发现的问题 | 反向抽样；高则补断言/改人工层 |
| 锚点复用率 | 用锚点启动的节点数/总节点数 | 尽量高；缺锚点先补 |
| 回归耗时 | run_verify 全跑时长 | 记录基线，防止退化 |

> 数据只用于优化测试流程，不得当验收证据；指标与结论分开写。

## 9. 引擎无关 backend 需求（verification backend）

自动断言依赖 backend 能**导出状态**与**注入按键**；最小契约（详见后端契约 §6）：
- `keys`（真实按键注入，必需）、`shot`/`screenshot`（证据，必需）、`state`（导出 `scene/floor/pos/central_text/objective/flags`，verification 必需；无则退化为截图 OCR 并标注局限）、`screenshot`（失败快照用）、`test_fast`（可选，仅测试构建）、`failure_snapshot`（可选，工具侧也可自己拼）；
- 任何动作失败必须非 0 退出 + stderr 可读；无能力（如 OCR/state）显式 `UNSUPPORTED`，不得假装成功；
- **只读**：state 导出只能读，不得写状态/跳阶段；test_fast 只缩放时间。

## 10. 落地清单与风险

**落地顺序（建议）**：①锚点库（先覆盖高频节点）→ ②hud_walker 覆盖 1~2 条主链 → ③trace diff 接入 → ④run_verify 打包 → ⑤test-fast 接入长过场 → ⑥指标记录/调优。
**风险/边界**：
- 自动断言只验"对错"，**不能替代观感/语义**；用户可见问题仍可能漏（漏报率要抽样）；
- 锚点/剧情树/断言需随版本维护（改场景/引导后旧锚点/期望失效 → 先更新再跑）；
- 自动走位遇到**场景门/陷阱/战斗**要显式建模或退化人工，不得用"画面变化"硬判；
- no-cheat 红线不变：禁传送/跳剧情/自动胜/改状态；test-fast 不是 cheat；失败不得用复位掩盖。

## 11. 与既有文档关系

- `references/testing/playbook.md`：黑盒总纪律（本文件是效率层细化）；
- `references/testing/probes-and-metrics.md`：卡顿/吞键量化（walker 指标互补）；

- `templates/task-tree.md`：节点/验收点（walker 目标/期望来源）；
- `templates/anchor-ledger.md`：锚点台账；
- `references/backends/CONTRACT.md`（若存在）/`scripts/backends/CONTRACT.md` §6：verification backend 契约。

## 12. 测试与游戏的边界（铁律，v3.2.1）

> 自动化效率再高，也**不得靠改游戏代码/加测试钩子**来变快。完整铁律见 `references/standards/no-cheat.md` §6。

- **游戏代码不得为测试添加逻辑**：禁合成触发、强制落点/坐标校正、任意位置 SPACE、test-only 分支/后门/stub；不得为让 walker 通过而改数据/验收标准；
- **自动化只允许**：外部真实按键注入 + 外部观测（截图/状态导出）；锚点库/失败快照/run_verify 都是**构建外工具**；
- **test-fast**：仅独立 debug 构建/测试构建的时间缩放，默认不进正式包；正式包不得含测试分支；
- **真实案例（round78，用户否决已回退）**：合成上下楼触发/落点校正/任意位置 SPACE 属 overfit，已回退为真实脚本/真实门（DEV_REPORT §九十三~§九十五、bug-ledger R77-EXIT-6/R78-STREET-5）；
- **正确做法**：真实问题修数据/碰撞/事件/引导；测试效率问题用锚点/外部工具/分层测试——**不向游戏加钩子**。
> 本文件为**架构文档**，具体 CLI/路径以 dev 最终落盘与 `--help` 为准；项目实测数据（锚点/耗时/失败项）以 tester/dev 回执为准，不虚构。
