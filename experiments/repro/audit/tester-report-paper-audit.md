# round84 · tester4 · 论文材料只读核对报告（paper audit）

> 核对者：tester4｜时间：2026-11-06 06:20–06:35（Asia/Shanghai）
> 模式：**只读**（未开窗、未注入按键、未写槽1/2/3/4/5/9、未运行任何实验、未修改 `_playtest_regress/paper/` 任何文件；仅 Get-FileHash/读文件；临时审计脚本已删除）
> 核对对象：`_playtest_regress/paper/`（PAPER_DRAFT_MAIN.md、FINAL_ACCEPTANCE_CHECKLIST.md、HUD_EVALUATION.md、hud_eval_results.csv/json、raw_eval_route*_*.txt、raw_git_log.txt、raw_hud_commits.txt）
> 参照：`round84/tester-report-r*.md`（124 份）、`_playtest_regress/round82/r*_*` 证据、`_playtest_regress_dev/round78` 锚点、git log、当前槽位文件
> 当前代码 HEAD：**`2d3070f`（docs/paper，2026-11-06 05:26）**；代码提交 `f9972eb`（R311）
> 当前槽1：**`8880C3219A03BA0C…`（mtime 2026-11-05 08:29:26）**；用户最新档 `8FB38168…` 已丢失（见 §1）

---

## 1) 槽1 当前状态（只读确认，未恢复/未覆盖）

- 当前 `pal_save_1.sav`：sha256 前16 = **`8880C3219A03BA0C`**，mtime **2026-11-05 08:29:26**，size 190064。
- 用户最新档：**`8FB38168C3D1C4B3…`（2026-11-05 17:13 曾为槽1）**——当前不在槽1；P0 已确认丢失。
- 只读扫描 `_playtest_regress*`、`giveUser` 全部 `*.sav`：**未发现任何 8FB38168 的副本**（0 命中）；`%APPDATA%\Godot\app_userdata` 下仅当前 `8880C321`（另一项目 PAL4Godot 的 slot1 与本项目无关，2026-10-20）。
- **我未恢复、未覆盖、未写入槽1**；本审计仅读取 hash/mtime。

---

## 2) 核对结论：基本一致项 ✅（材料↔仓库/证据）

| 项 | 材料声称 | 只读核对结果 |
|---|---|---|
| 构建 marker | checklist:5-7「HEAD f9972eb，`[BUILD] R311-a49-once`」 | 代码 `world.gd:1185` 打印 **`[BUILD] R311-a49-once floor-source=location_name`** ✅（HEAD 现为 2d3070f，仅 docs 提交，代码未变——见 D10） |
| A1 阶段 commit 表 | 28 个 commit（5c5d0f8…f9972eb） | `git cat-file -e` **28/28 存在** ✅（含 baseline `26404ee`） |
| HUD raw→CSV/JSON | 7 个 raw 文件 ↔ 7 行 CSV | **7/7 数值一致**（route/variant/completed/steps/moved/blocked/frames/start/end/N/metric/scene/shortest/path_err/mis_trigger 全同；仅我比较脚本的布尔格式差异）✅ |
| Route1 锚点 | `anchor.sav` | 文件存在，sha16 **C18606EF2EAF672F**，位置 **(1024,1600) scene207** = CSV start ✅ |
| Route3 锚点 | `anchor.sav` | 文件存在，sha16 **CAE77CAF4EA66CB7**，位置 **(1488,1592) scene206** = CSV start ✅ |
| 场外锚点（B2） | checklist:106「7C922D…」 | 锚点文件（dev 目录）sha16 **7C922D7CFD7F74D3**，位置 **(1680,1640) scene255**，与声称 hash 一致；但**路径写错**（见 D5）✅/⚠ |
| Route1 结果 vs 实机 | C：239 步、N 242→78、结束 scene206 | 与 `round84/tester-report-r295.md`（实机 207→206：N 242→184→124→64→4→自动进 206、206 起点 N78）**一致** ✅ |
| Route3 结果 vs 实机 | C：71 步、N 78→7、结束 scene206、dlg=true | 与 `tester-report-r296.md`（实机 N 78→10→0 → 自动剧情）**一致**（headless 以 metric<40 提前完成，N7 合理）✅ |
| 失败/排除项 | route1 A/B 未完成（207 内，end_N 252）；route2 valid=false | raw 日志相符：route1 A/B `completed=false end_scene=207 end_N=252`；route2 HUD「等待/绕行中」且 `[battle]` 触发 → 排除合理 ✅（但 raw 文件无 valid 字段，见 D7） |
| 计数项 | tester 报告 124；近期修复提交 113；HUD 提交 314；DESIGN_CHANGES 198；锚点 48/53；raw eval 7；recorder 57 | 全部核对 **一致** ✅（`round84/tester-report-r*.md`=124；含 R2xx/R3xx subject 提交=113；`raw_hud_commits.txt` 有效行=314；DESIGN_CHANGES=198；`_playtest_regress_dev/round78` `*anchor*.sav`=48、`.sav`=53；recorder-report=57） |

---

## 3) 差异清单（需材料侧修正；本审计未改材料）

### D1（P0 关键）「用户槽1 未覆盖 / 0 overwrites」表述与实际不符
- `PAPER_DRAFT_MAIN.md:12`：「preserving the user's save across all revisions (**0 overwrites** after the protocol was adopted)」
- `PAPER_DRAFT_MAIN.md:54`：表「用户存档覆盖事故（协议采用后）| **0**」
- `PAPER_DRAFT_MAIN.md:72`：「用户存档 **0 覆盖**」
- `HUD_EVALUATION.md:99`：「实验结束后已从备份把用户槽1**恢复为原 hash `8880C321…`（只读内容不变）**；槽1未用于本实验存档/测量」
- `FINAL_ACCEPTANCE_CHECKLIST.md:105`：「用户槽1：`pal_save_1` sha256 8880C321…；**本轮只读，未覆盖**」
- 实际：用户最新槽1 `8FB38168…`（11-05 17:13）**在 HUD 实验期间被覆盖丢失**；当前槽1 为旧档 `8880C321…`（08:29），全仓库无 8FB38168 副本（§1）。
- 建议统一改为：「用户槽1 最新档 `8FB38168…` 在 HUD 三变体实验模板加载/恢复流程中丢失（1 次槽位事故）；当前槽1=`8880C321…`（旧档 08:29）；用户最终签收**待确认**」。

### D2 checklist「仓库内未发现独立 tester 报告文件」错误
- `FINAL_ACCEPTANCE_CHECKLIST.md:89`：称「仓库内未发现独立 tester 报告文件，故本表标记为会话记录，不按正式归档 PASS」
- 实际：`round84/tester-report-r*.md` **124 份**（另有 198 份 md 总计）；关键 PASS 报告均在：
  - `tester-report-r299.md`（R309：A PASS、B1 战斗第1/2页+第2/2页 PASS）
  - `tester-report-r300.md`（B2 场外仙术说明 PASS，第1/1页共10项+说明行）
  - `tester-report-r296.md`（R303 206 石阶两段 PASS）
  - `tester-report-r295.md`（R302 207 入口恢复+207→206 PASS；206 blocked FAIL）
  - `tester-report-r293.md`（R292/R293 窄道 PASS）
- 建议：把「Lead 转述」条目改为**引用具体 tester 报告文件**，并把 r299/r300 纳入 A3 的正式归档 PASS 证据。

### D3 checklist「R303 tester 复测未归档」错误
- `FINAL_ACCEPTANCE_CHECKLIST.md:78`：「tester 复测未归档」
- 实际：`tester-report-r296.md` 已归档（206 锚点段 + 用户档全链 PASS，含截图/stderr/quit_trace）。
- 建议改为「tester 复测已归档：r296」。

### D4 B2 状态过时（多处）
- `FINAL_ACCEPTANCE_CHECKLIST.md:82`：「B2 待锚点」；`:87`「待 tester 实机 B2」；`:97`「B2 待锚点复测」；`:132`「未解决事项：B2 场外仙术菜单实机补测」
- 实际：**B2 已在 `tester-report-r300.md` PASS**（2026-11-05 13:00，锚点 `7C922D`，页码「第1/1页 共10项」，梦蛇/夺魂/雷神说明行原文见报告），锚点提交 `03d70c5`。
- 建议：删除「B2 待补测」，改引 r300；未解决事项仅保留「R310/R311 用户实机确认 + 全量 A1–A52 未在 f9972eb 重跑」。

### D5 场外锚点路径错误（checklist:106）
- 声称：`_playtest_regress/round78/anchor.sav`（sha 7C922D…）
- 实际：该路径**不存在**；真实文件在 **`_playtest_regress_dev/round78/anchor.sav`**（7C922D ✓）；`_playtest_regress/round78` 下仅有 `anchor.sav`（同 hash）。
- 建议更正路径并注明「实际 scene255」。

### D6 HUD route2 锚点 (752,1160) 无法复核（不可复现）
- `HUD_EVALUATION.md:59` 声称 route2 锚点 `scene185 锚点 (752,1160)`。
- 实际：只读扫描 `_playtest_regress*` 全部 `.sav`，**不存在位置 (752,1160) scene185 的存档**（0 命中）；最近保留锚点 `anchor.sav` 位置 **(736,1152)**，sha16 `389DADE20B831B8B`。raw_eval_route2_C 的 start=(752,1160) 与任何已归档锚点不符。
- 结论：route2 的锚点若为临时修改档，材料未保留/未说明 → 该排除路线**不可复现**；应补锚点文件+hash 或明确「临时档未保存」。

### D7 `raw_eval_route2_C.txt` 没有 `valid=false` 字段
- `HUD_EVALUATION.md:59`：「原始日志 `raw_eval_route2_C.txt` 标记 `valid=false`」
- 实际：raw 文件内 `[eval]` JSON 无 `valid` 键；`valid=false` 仅存在于 CSV/JSON 汇总。建议改写引用（「CSV/JSON 汇总标 valid=false」）+ 在 raw 说明里注明排除原因（HUD 等待/绕行 + 触发战斗）。

### D8 证据数量 2,953 与实测不符
- `PAPER_DRAFT_MAIN.md:50`：「round82/round84 近期证据文件（r2xx/r3xx）| 2,953」
- 实测：`_playtest_regress/round82` 下 `r2*/r3*` 文件 = **5,328**（其中 PNG 5,142）；`round84` 下 `r2*/r3*` 文件 = **71**；合计 **5,399**（PNG 5,142）。
- 2,953 的来源（是否只统计某轮/去重/仅报告引用文件）未在材料中说明 → 需重算并注明口径。

### D9 round78 目录文件数陈旧
- `PAPER_DRAFT_MAIN.md:51`：「round78 … 目录 2,460 个文件」
- 实测：`_playtest_regress_dev/round78` 下文件 **2,547**（当前）；锚点 48/53 一致。

### D10 HEAD/提交数快照陈旧
- `FINAL_ACCEPTANCE_CHECKLIST.md:5-7`：「当前代码 HEAD `f9972eb`」；`PAPER_DRAFT_MAIN.md:5` 同；「总提交数 547」（checklist:11、paper:47）
- 实测：仓库 HEAD **`2d3070f`**（2026-11-06 05:26，docs/paper）；提交总数 **549**（比 547 多 `094db58`、`2d3070f` 两份 docs/paper 提交，代码未变）。
- 建议：材料标「快照时间：checklist 生成时 HEAD=f9972eb；当前仓库 HEAD=2d3070f（仅 docs 提交）」；提交数改为「checklist 快照 547 / 当前 549」。
- 另：`2d3070f`/`094db58` commit message 也使用「slot1 restored to 8880C321」措辞（与 D1 同一错误框架），建议论文不引用该措辞。

### D11 HUD 实验「槽1 未使用」表述不准确 + 格式瑕疵
- `HUD_EVALUATION.md:99`：「槽1**未用于**本实验存档/测量」——但 7 份 raw 日志**每次启动均有 `[save] LOAD slot=1 current_loaded=1`**（模板以槽1做运行时初始化），之后才 `LOAD slot=2` 锚点测量。
- 建议改为：「实验模板启动时会**加载**槽1作为运行时初始化（只读加载，不用于判定）；测量使用 `load_game(2)`+锚点；**该模板的槽1加载/恢复流程是本次槽1覆盖事故的相关风险点**」。
- 同句含字面 `\n`（Markdown 转义未生效）→ 排版修正。

### D12 R308/R309 实机结论混写（应区分 FAIL 与 PASS）
- `HUD_EVALUATION.md:48`：「载入 scene253 冻结/输入无响应，stderr 洪水 → R308/R309 → 实机 A PASS（Lead 转述 2026-11-05）」
- 实际归档：`tester-report-r298.md` = **R308 实机 A FAIL**（stderr 17MB、`_apply_wave` ERROR 洪水）；`tester-report-r299.md` = **R309 实机 A PASS**（stderr 0B、不冻结、输入正常）+ B1 PASS。
- 建议拆开写明「R308 FAIL → R309 PASS（r298/r299）」，避免把 R309 的 PASS 回填给 R308。

### D13 checklist A3 中「Lead 转述」应改为报告引用
- `FINAL_ACCEPTANCE_CHECKLIST.md:82/84/89/97`：多处「A PASS、B1 PASS（Lead 转述）」/「实机 A PASS（Lead 转述）」。
- 实际：有独立 tester 报告 r299/r300（及 r298 FAIL 记录）。建议全部改为文件引用（含 stderr 证据），以符合「证据可审计」的论文主张。

### D14（轻微）checklist「A3 当前可下结论」措辞
- `:76-87` 列 PASS/FAIL 结论可以，但第 4 行声明「未复测一律标未复测，不写 PASS」与实际把部分实机 PASS 已归档的状态不一致（r293/r295/r296/r299/r300 已复测并有 PASS/FAIL 报告）；建议统一口径：「已归档 tester 报告见 r293/r295/r296/r299/r300」。
- 另 `:62` 把 R308/R309 描述为「实机 A PASS/B1 PASS」需按 D12 拆开。

---

## 4) HUD 三变体实验专项核对（真实锚点/路线/汇总）

| 项 | 结论 |
|---|---|
| Route1 真实锚点 | ✅ `anchor.sav` C18606EF，pos(1024,1600,207) = CSV start；目标 evt3461(464,280)；C 完成→scene206，N242→78 |
| Route3 真实锚点 | ✅ `anchor.sav` CAE77CAF，pos(1488,1592,206) = CSV start；目标 evt3442(864,1280)；A/B/C 均 71 步完成（简单走廊） |
| Route2 | ⚠ 锚点 (752,1160) 无对应 .sav（最近 forest anchor (736,1152) 389DADE2）；raw start=(752,1160) → **不可复现**；排除理由（HUD 等待/绕行 + 自动战斗）本身在 raw 中可见，属如实排除，但需补锚点/说明 |
| raw vs CSV/JSON | ✅ 7/7 一致（数值全同）；raw 无 valid 字段（D7） |
| 结论口径 | ✅ HUD_EVALUATION §4 局限（自动化、2 条有效路线、单次、A/B 为简化对照、不能外推）与数据一致，未发现夸大 |
| 风险点 | ⚠ 实验模板启动 `LOAD slot=1`（7/7 raw 可见）→ 与 P0 槽1 覆盖事故直接相关；材料需如实说明 |

---

## 5) 一致性总评

- **证据链主体一致**：HUD 实验 raw/CSV/JSON/锚点/路线与 tester 实机报告吻合；构建 marker 与 commit 表真实存在；主要计数（124 报告、113 修复提交、314 HUD 提交、198 DESIGN_CHANGES、48/53 锚点、57 recorder）核对通过。
- **但材料存在 1 类 P0 级错误表述**（槽1/存档安全：D1、D11，共 4 份材料 6 处）与 **1 类归档事实错误**（D2：否认 tester 报告存在；D3/D4/D12/D13：部分状态过时/混写），以及若干路径/计数/快照陈旧（D5–D10）。
- **未发现材料伪造实验数据**：HUD 三变体 raw 与汇总一致、失败/排除如实；主要问题是**结论表述与归档引用**需修正（特别是「0 overwrites」与用户签收口径）。

## 6) 仅需材料侧修正（我不改材料、不跑实验）
1. 统一改写用户槽1 事故事实（D1/D11），并停止使用「0 overwrites / 已恢复原 hash」措辞；
2. 补引 tester 报告（r293/r295/r296/r298/r299/r300），修正 D2/D3/D4/D12/D13；
3. 修正 D5 路径、D6 route2 锚点证据（或标不可复现）、D7 raw valid 引用；
4. 重算 D8 证据数口径、更新 D9 文件数、标注 D10 HEAD/提交数快照时间。

---

## 7) 槽/窗口纪律记录

- 未开窗、未注入按键、未运行任何游戏/实验；
- 未写槽1/2/3/4/5/9（仅 Get-FileHash/LastWriteTime 读取）；
- `pal_save_1.sav` 保持 `8880C3219A03BA0C`（mtime 2026-11-05 08:29:26）——**未恢复、未覆盖**；
- 未修改 `_playtest_regress/paper/`；临时 python 审计脚本已删除。

---

tester4 · 2026-11-06 06:35
