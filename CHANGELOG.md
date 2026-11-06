

- 恢复完整 `templates/task-tree.md`（A1~A12 主线 + A59~A62 回归映射 + 节点验收）；
- 验证自动化（锚点/walker/run_verify/test-fast 契约）保留为「任务树 + 锚点断言」。

# CHANGELOG · game-playtest 插件

> 版本号与 `plugin.json` 保持一致。本文件记录对外可见的变化（框架/角色/标准/模板/工具）。

## v3.4.0（2026-11-05）· 任务树四要素（人 / 地点 / 做到什么 / 时间）

> 用户拍板：任务树升级为**四要素**，新增 **时间** 作为**任务节点的唯一标识**（不只记录字段）。
> 纯文档/模板/角色规则变更，不改变脚本、工具、backend 行为；与 v3.3.x 兼容（旧三要素节点自动按编号回填 `t_node`）。

- `SKILL.md`：标题 v3.4.0；§2 改为「线路 → **四要素**任务树 → 节点」，新增时间要素规范（`t_node` 逻辑时间主标识 + `t_exec` 物理时间元数据；单调排序、`t_node#retryN` 复测、证据/报告统一引用）；§3 测试执行要求以 `t_node` 命名证据。
- `templates/task-tree.md` **重写**：四要素定义表；新增「时间要素规范（双时间）」；节点表增加 `时间标识 t_node` / `t_exec` 列；状态迁移/锚点/阻塞/粒度审查/快照/重复问题全部改用 `t_node` 关联；四要素粒度审查（时间含糊/不唯一=不合格）。
- `templates/lead-dispatch.md`：派测试增加「四要素 + 时间（t_node；t_exec 测试侧记录）」；证据命名 `r<t_node>_*`；回执要求带 t_node/t_exec。
- `templates/report-template.md`：结论增加 `t_node`/`t_exec` 行。
- `templates/acceptance-report-user.md`：节点总表列改 `节点（t_node）`；节点详情增加「节点时间标识（t_node/t_exec，复测 t_node#retryN）」。
- `references/roles/lead.md`：派单模板改「四要素」+ 时间；交付证据引用 `t_node`。
- `references/roles/developer.md`：节点设计/粒度审查改四要素（时间为必填）。
- `references/roles/tester.md`：回执增加 `【时间】t_node/t_exec`，证据按 `r<t_node>_*`。
- `README.md` / `plugin.json`：版本与任务树描述同步为四要素。

## v3.3.3（2026-10-29）· 槽安全铁律（用户槽不可变 / 自动化输入门禁）

> **事故背景（P0）**：2026-10-29 测试自动化在**存档菜单**盲按 SPACE×20（误走「战斗/对白恢复」），触发「储存→默认进度一→确认」，**覆盖用户进度一**（原 scene40 次数13 08:18 → scene45 次数33 09:16，**无法精确恢复**）。团队槽2 正常、槽3/4/5 未变；**第3章 PASS 结论不变**（用户验收）。
> 本节为由此事故写死的**槽安全铁律**。

### 新增文档
- `references/standards/slot-safety.md`（**新**）：四条铁律——①**用户槽不可变**（任何情况不写用户槽；自动化只写团队槽）②**自动化输入前置状态门禁**（截图/状态分类确认 UI=游戏世界；菜单/存档/对话框/战斗/过场禁止盲按；禁止「SPACE×N」猜恢复；战斗恢复必须截图判断）③**保存/读档显式槽位+归属校验**（禁止默认槽位；团队槽白名单）④**误覆盖=P0**（立即停手、保留证据、如实上报、不覆盖恢复）；含事故案例/执行器要求/检查清单/FAQ。

### 更新
- `references/testing/human-ai-dual-progress.md`（v3.3.3）：补槽安全（用户槽不可变、自动化只写团队槽、输入门禁）与 slot-safety 关联。
- `references/testing/progress-first.md`（v3.3.3）：bug 先存**团队进度二**；禁写用户槽；自动化输入门禁/只写团队槽。
- `templates/anchor-ledger.md`：补「槽安全铁律」说明（用户槽不可变/自动化只写团队槽/输入门禁/显式槽位归属/P0）。
- `references/roles/{tester,lead,recorder}.md`：槽安全职责（tester 不盲按/不写用户槽；lead 误覆盖=P0 上报；recorder 事故归档字段）。
- `SKILL.md`：标题 v3.3.3；§1 增加槽安全铁律；§12 standards **7 篇**（+slot-safety）；计数以最终 `plugin.json` 为准。
- `README.md`：新增「槽安全铁律（v3.3.3）」章节；标准 7 篇；相关文档/目录树/计数。
- `plugin.json`：dev2 更新为 **3.3.3**（description/keywords + slot-safety；references 清单以 dev2 最终为准）。

### 项目侧归档
- `_playtest_regress/round83/incident_slot1_overwrite.md`（P0 事故报告：时间线/根因/影响/证据/补救/预防）。
- `bug-ledger.md` 追加 `R83-INCIDENT-1` 事故条目（只增）；**第3章 PASS 结论不变**。

### 兼容性
- **纯文档/角色/模板规则变更**：不改变脚本/工具/backend 行为；与 v3.3.2 双进度、v3.3.1 进度优先/单次判定、v3.3.0 三要素兼容。
- **no-cheat 不变**：真实输入、禁传送/跳步/自动置 stage；**新增槽安全**：用户槽不可变、自动化输入门禁、保存/读档显式槽位归属、误覆盖 P0。
## v3.3.2（2026-10-29）· 双进度人机协同

> 用户定义新人机协同模式：**进度一=用户专用**（用户测试+保存）；**进度二=团队专用**（团队测试/续测保存）；团队**不写进度一**（只读载入后另存进度二）；**用户测过的节点→团队直接记录 PASS、不再复测**；团队从用户进度一接着往下做；团队跑过的进度交用户复测，用户确认后**双进度对齐**到通过点；下一轮继续从进度一出发；报告/交接 5 项。

### 新增文档
- `references/testing/human-ai-dual-progress.md`（**新**）：三个槽位角色（进度一用户/进度二团队/固定锚点可选）、四条规则、团队跑过进度→用户复测→双进度对齐流程、反例合集、槽位保护、报告 5 项字段、FAQ。

### 更新
- `references/testing/progress-first.md`（v3.3.2）：团队进度槽明确为**进度二**、进度一=用户专用（团队只读不写）；用户 PASS 节点直接记录不复测；报告 5 项。
- `templates/anchor-ledger.md`（v3.3.2）：**三类记录**——§1 固定锚点（可选、只读）+ §2 进度一（用户专用、团队只读）+ §3 进度二（团队专用、可覆盖）+ 双进度记录/槽保护/每轮核对/归档审核。
- `references/roles/{tester,lead,recorder}.md`：双进度职责（tester 从进度一再续做、写进度二、用户 PASS 直接记录；lead 双进度协调/5 项汇报；recorder 归档双进度/PASS/待复测/下一步）。
- `SKILL.md`：标题 v3.3.2；§1/§2/§3 增加双进度规则（步骤 13）；§12 testing **6 篇**；计数以最终 `plugin.json` 为准。
- `README.md`：新增「双进度人机协同（v3.3.2）」章节；锚点台账三类记录；测试文档 6 篇；相关文档/目录树/计数。
- `plugin.json`：dev2 更新为 **3.3.2**（description/keywords：dual-progress/user-slot/team-slot/user-acceptance；**references 清单保持 18 项，未增 human-ai-dual-progress**，该文件随 `references/` 目录安装）。

### 兼容性
- **纯文档/模板/规则变更**：不改变脚本、工具、backend 行为；与 v3.3.1（进度优先/单次判定）、v3.3.0 三要素任务树兼容；v3.3.1「团队唯一进度槽」细化为「进度一用户 / 进度二团队」。
- **no-cheat 不变**：进度来自真实操作/合法存档；团队不写用户进度、不伪造；禁传送/跳步/自动置 stage。
## v3.3.1（2026-10-29）· 进度优先与单次判定（验收纪律）

> 用户指示：测试发现 bug **先保存进度**（团队进度槽，下次从该进度继续）；**节点判定通过即通过、不复测**；团队**全程一个进度槽**、**至少留一个槽给用户**、**用户槽只读不写**；报告/交接写清进度槽/PASS/未完成/下次续测位置。

### 新增文档
- `references/testing/progress-first.md`（**新**）：四条规则（①bug 先存进度再报 ②PASS 不复测、仅用户新报 bug/节点代码变更才重开 ③团队唯一进度槽+用户槽保护 ④进度槽 vs 固定锚点）+ 反例合集/报告字段/每轮检查清单/FAQ。
- `templates/anchor-ledger.md`（**重构**）：§1 **固定锚点**（只读、不覆盖）+ §2 **团队进度槽**（唯一、可覆盖、当前续测点）+ 槽位分配/用户槽保护/每轮核对/归档审核。

### 角色更新
- `references/roles/tester.md`：遇 bug **先存进度槽再报**；单次判定、PASS 不复测；槽位纪律。
- `references/roles/lead.md`：**PASS 后不派复测**（仅用户新报 bug/节点代码变更重开）；推进度优先；槽位与用户槽保护。
- `references/roles/recorder.md`：六项/章节验收归档必须写 **进度槽/PASS/未完成/下次续测位置/锚点使用/用户槽未读写声明**。

### 更新
- `SKILL.md`：标题与 §1/§2/§3 增加进度优先/单次判定纪律；§12 测试文档 5 篇；插件计数以最终 `plugin.json` 为准。
- `README.md`：新增「进度优先与单次判定（v3.3.1）」章节；锚点台账两类表；测试文档 5 篇；相关文档/目录树/计数校正（templates 16 / references 18，以 dev2 最终 `plugin.json` 为准）。
- `plugin.json`：dev2 更新为 **3.3.1**（version/description/keywords；**references 清单未增 `progress-first.md`，保持 18 项**；`progress-first.md` 随 `references/` 目录安装）；本节不改 plugin.json/工具代码。

### 兼容性
- **纯文档/模板/角色规则变更**：不改变脚本、工具、backend 行为；与 v3.3.0 三要素任务树、v3.2 验证自动化兼容。
- **no-cheat 不变**：真实输入、禁传送/跳步/自动置 stage；保存进度=合法存档操作，不是改状态；进度槽≠测试后门。
## v3.3.0（2026-10-29）· 任务树三要素架构（人 / 地点 / 做到什么）

> 用户拍板：任务树不再以“路线/实现细节”描述剧情，统一为可定位的三要素节点；插件模板与角色/标准同步替换。

### 变更
- `templates/task-tree.md` **重写**：节点表改为 `编号/线路/人（谁）/地点（在哪）/做到什么（事）/前置/锚点/状态`；新增三要素定义、三要素粒度审查、快照格式；历史 A59~A62 回归映射与 A6 stage 机**不再写进插件通用模板**（归项目自己的 task-tree-v8/历史附录）。
- `SKILL.md` §2：模型改为「线路 → 三要素任务树 → 节点」；节点描述固定为“人→地点→做到什么”，验收标准由地点+事推导。
- `README.md` 任务树章节：替换为三要素架构说明；删除旧 A59~A62 映射作为插件通用内容。
- `references/roles/developer.md`：节点设计步骤改为按三要素输出 + 三要素粒度审查。
- `references/roles/lead.md`：派单模板新增 `【三要素】人/地点/做到什么` 一行。
- `plugin.json`：版本 3.3.0；`conventions.task_tree_doc` 指向项目 `_playtest_regress/task-tree-v8.md`。

### 兼容性
- 纯文档/模板变更：不改变插件脚本、工具、backend 行为；v3.2.x 项目可继续用旧详细附录，新任务树按三要素登记。
- no-cheat 边界不变：真实输入、禁合成触发/强制落点/传送验收。


## v3.2.1（2026-10-28）· 架构铁律：禁止测试后门 / 禁止为测试改游戏

> 用户拍板（架构 overfit 纠正）：验证自动化提效**不得靠改游戏代码/加测试钩子**。本节为**文档铁律**；plugin.json 版本号是否 bump 以 dev 最终为准（若 dev 保持 3.2.0，本节内容并入 v3.2.0 文档更新，不改代码/工具行为）。
> 触发：round78 曾为自动走位/复验加合成上下楼触发/落点校正/任意位置 SPACE → 用户否决并回退。

### 新增 / 更新文档
- `references/standards/no-cheat.md` **§6 架构铁律**：禁止清单（合成触发/强制落点/任意位置 SPACE/test-only 分支/后门/stub）；**自动化只允许外部真实按键 + 外部观测**；test-fast/失败快照必须构建外工具或独立 debug 构建、默认不进正式包；**真实案例**（round78 合成上下楼/落点校正被用户否决，已回退为真实脚本/真实门；证据 DEV_REPORT §九十三~§九十五、bug-ledger R77-EXIT-6/R78-STREET-5）；允许 vs 不允许对照；审计关键词与处理（该轮作废/回退/节点重开/上报用户）。
- `references/testing/efficiency.md` **§12 测试与游戏的边界（铁律）**：交叉引用 no-cheat §6，明确锚点/快照/run_verify=构建外工具、test-fast 边界、真实案例与正确做法。
- `README.md`：质量门与红线新增「禁止测试后门（架构铁律 v3.2.1）」；v3.2「边界」补充"自动化只允许外部输入/观测，游戏代码不得为测试加钩子"。
- `CHANGELOG.md`：本节。

### 兼容性
- **纯文档补充**：不改 plugin.json/install.ps1/工具代码/模板行为；与 v3.2.0 完全兼容（同样适用于 v3.0/v3.1 流程）；
- 与既有 no-cheat §1（测试过程禁作弊）叠加：§1 管"测试/验收过程"，§6 管"游戏代码不得因测试而改"。
## v3.2.0（2026-10-28）· 验证自动化层（verification automation）


### 新增文档 / 模板
- `templates/anchor-ledger.md`（**升级为节点锚点库**）：节点 id/场景/楼层/坐标/槽位/用途/关键状态/只读/建立构建/有效性校验（anchor_check JSON）/每轮核对/归档审核；用户槽冻结只读、测试槽 3/4/5 作锚点。
- `scripts/backends/CONTRACT.md` **§6 verification backend 契约**：`keys`（真实注入）、`shot/screenshot`、`state`（导出 `scene/floor/pos/central_text/objective/flags/busy`）、`test_fast`（仅测试构建时间缩放）、`failure_snapshot`（截图+按键+状态）；缺失能力显式 `UNSUPPORTED`，旧 backend 可降级 OCR/人工。

### 工具（`tools/verify/`，v3.2.0 已落盘）
- `common.py`（verification backend 抽象：state/keys/shot/test_fast/failure_snapshot 命令调用）、`anchor_check.py`（锚点校验：`--backend --ledger [--record|--selfcheck]`）、`hud_walker.py`（HUD 走位器+断言：`--backend --path A12/A14_1F/A14_2F/A13_PRE/DOCK [--jsonl --max-steps --specs --selfcheck]`；exit 0/1/2）、`run_verify.py`（一键回归：`--backend --paths --jsonl --ledger` → PASS/FAIL 清单）、`selftest.py`（verify 自检 `ALL OK`）。项目侧参考 `_playtest_regress_dev/tools_r78/`。

### 更新
- `README.md`：新增「验证自动化（v3.2）」章节（分层/七能力/一条链用法/边界）；工具清单 +verify 五件套实际命令行；模板 anchor-ledger 说明升级；测试文档 6 篇；目录树/相关文档同步。
- `plugin.json` v3.2.0（dev）：`tools.verify` 五件套；templates **19** / references **19** / examples **3**；`references/testing/efficiency.md` 与 `templates/anchor-ledger.md` 已入清单。
- `CHANGELOG.md`：本节。

### 兼容性（与 v3.1.0）
- 旧 backend 不实现 verification 能力时：v3.1 流程照跑，walker 自动降级 OCR/人工并标注局限；
- **no-cheat 不变**：真实按键、禁传送/跳剧情/自动胜/改状态；**test-fast ≠ cheat**（只缩放时间）；自动断言通过 ≠ 节点通过（仍需三重确认）。

### 参考（真实项目数据，非虚构）
- 锚点替代重走：round77 用槽一用户存档（场景4 一楼大厅）直接复验 A12，过去需从头长距离重走（20+ 分钟）→ 目标 <2 分钟/节点；
- 走位器排门：round76 经验 `F-R76e-1` 自动走位被场景门误导（画面变化被误判为可走）→ walker 必须**排门**并以 state 判位移；
- A12 用户验收基线：tester `round77/tester-report.md §77-L`；修复 `c77ae7a`/归档 `971aced`。
## v3.0.0（2026-10-27）· 通用化蒸馏版

> 主题：**引擎无关 + backend 可插拔 + 4 Agent 验收闭环 + 可观测性/量化**。
> 来源：真实项目 `PAL98 Godot（REA port）` 的 round75/round76 多轮黑盒验收蒸馏（数据/案例标来源路径，未虚构）。

### 框架 / SKILL
- 重写 `SKILL.md`（≤20KB 中文蒸馏版）：保留 4 Agent 固定编制与职责边界、线路/任务树/节点模型、节点循环与**三重确认验收门**（测试自判→开发复核→Lead 宣布）、经验库复用/边界、同类问题第 2 次→设计层修复、困难即停、锚点/存档纪律、证据/报告规范、**禁作弊红线**、只增报告与版本化。
- 新增：**引擎无关 + backend 可插拔**（`scripts/backends/CONTRACT.md`）、**测试可观测性设计原则**（引导同源/单一提示/目标单调/等待有界/输入缓冲/遮挡淡出/性能缓存）、**量化探针**（walk/hold/fps）、**度量工具**（可选）、**用户现场 bug 修复流程**。
- 明确 Lead 只协调（不写代码/不跑测试/不写记录）、测试不得自宣通过、开发监控测试完成度。

### 新增 references/
- `references/roles/{lead,developer,tester,recorder}.md`：可直接作为 subagent prompt 的角色说明（职责/流程/回执模板/红线）。
- `references/standards/`：
  - `no-cheat.md`（红线+审计清单+清理记录模板+正常启动 0 调试输出验证）
  - `anchors-and-saves.md`（锚点/存档纪律+台账）
  - `evidence-and-acceptance.md`（证据目录/前缀/日志/反伪/三重确认/人读报告+git diff）
  - `experience-library.md`（S/F/R 格式、复用/边界/误迁移）
  - `engineering-patterns.md`（7 类可观测性模式；示例引 round76 真实数据并标来源）
  - `troubleshooting.md`（Windows 窗口/焦点/DPI/截图空白/单实例/吞键/长按语义/回放不保真/像素检测局限）
- `references/testing/`（测试角色维护）：黑盒手册、探针用法、通用案例（v3 新增）。

### 新增 templates/
- `acceptance-report-user.md`（给用户的人读版验收报告：三分钟看懂+节点总表+git diff+配图+遗留）
- `node-metrics.csv`（节点度量：轮次/用时/token 估算/构建/证据/是否一次通过）
- `defect-table.csv`（缺陷表：类别/根因/修复 commit/是否设计层/状态）
- `ablation-plan.md`（消融/对照实验：臂设计/指标/局限/结论）
- `anchor-ledger.md`（锚点台账+每轮核对）
- `evidence-index.md`（证据索引：目录/前缀分组/关键帧/日志/manifest）

### 更新 templates/
- `playtest.json` 升级 **v2 schema**：`backend`、`capture{method,dpi_aware,topmost_ms,crop_hint}`、`keys{default_hold_ms,gap_ms,allow_postmessage}`、`evidence{dir,manifest,append_only}`、`metrics{sessions_dir,window}`；旧 v1 字段向后兼容（如 `hint_region`）。

### 工程侧（v3 同步，由工程角色维护）
- `scripts/backends/CONTRACT.md`：backend 动作契约（launch/close/focus/info/keys/hold/diag/shot/hint + 可选 read_text），Web/Unity/Godot/桌面实现指引。
- `scripts/windows/PlaytestKit.ps1` + `scripts/windows/Capture.ps1`：Windows 参考实现（启动/发键/长按/截图/裁剪/提示）；`scripts/PlaytestKit.ps1` 保留兼容转发。
- `tools/`：`probes/{walkprobe,holdprobe,fps_probe,common}.py`、`screen/{image_ops,crop_region}.py`、`evidence/manifest.py`、`metrics/dsh_metrics.py`、`tests/selftest.py`。
- `install.ps1`：`-Target/-Force/-DryRun/-Backup`；`examples/`：`pal98-godot.json`、`generic-desktop.json`、`godot-project.md`；`plugin.json` v3（scripts/backends/tools/templates/references/examples/engines/requires/install/conventions）。

### 移除 / 迁移
- 删除 `_user_meta.json`（安装元数据不上传到包内）。
- 文档侧不再使用"三 Agent"表述，统一为 **4 Agent**（Lead/开发/测试/记录）。

### 兼容性
- 旧 `playtest.json`（v1）继续可用（缺省值补齐）；旧 `scripts/PlaytestKit.ps1` 路径保留兼容壳。
- 文档路径变化：角色/标准从 SKILL 内联迁移到 `references/`；旧引用需更新（README/SKILL 已同步）。

## v2.0.0（历史基线，2026-10-23）
- 4 Agent 任务树黑盒验收框架、Lead/开发/测试/记录职责、节点循环、三重确认、经验库、同类问题第 2 次设计层修复、禁作弊红线、验收报告模板、PlaytestKit.ps1（Windows）。
- 本版为 `E:\plugin` 的铺底基线；v3.0.0 在其上蒸馏与工程化。
