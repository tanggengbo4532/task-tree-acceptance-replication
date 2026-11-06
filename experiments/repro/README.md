# IST 可复现包（repro）

## 边界
- 本目录**不包含**任何商业游戏资源（PAL98 的 Data.mkf/Map.mkf/FBP/图片/音频等均未复制）。
- 仅包含论文实验的脚本、配置、汇总、原始日志、文本化任务树/经验库/审计报告。
- `manifest.json` 由 `build_manifest.py` 生成，覆盖本目录与已跟踪 harness；不覆盖 `proj/` 游戏数据。
- **“自动可复现”**：A/B 的 walker 结果、CSV/JSON 派生、错误/恢复计数、manifest hash（给定同一构建/同一锚点/同一 harness）。
- **“必须人工判断”**：HUD 可读性、提示语义是否清楚、用户接受度、观测到的“画面纯色/冻结”等主观或跨端现象；不得由 headless 指标替代。

## 构建/模型清单
见 `build_info.json`：
- 代码 HEAD `f9972eb`（R311），Godot 4.7.2.mono，Python 3.12.14
- 固定 fps 240；团队槽2；用户槽1只读并做前后 hash guard
- 正式游戏代码/数值未改

## 复现命令（示例；路径由 env 参数化）
```powershell
# 1) 生成 manifest（只读 hash；不运行游戏）
$env:IST_ROOT = (Get-Location).Path
python _playtest_regress/paper/ist/repro/build_manifest.py

# 2) 需要真实 PAL98 数据目录/合法游戏环境时，才可重跑实验：
#    IST_ROOT / IST_DIR / PAL98_APPDATA / IST_PYTHON / IST_RUNNER 可覆盖路径
python _playtest_regress/paper/ist/ist_runner.py
python _playtest_regress/paper/ist/ablation_runner.py
```
- `ist_runner.py`/`ablation_runner.py` 只把锚点复制到团队槽2；运行前后检查槽1 hash；不得写用户槽1。
- A 结果：`_playtest_regress/paper/ist/hud_eval_runs.csv` / `hud_eval_summary.md`；B 结果：`_playtest_regress/paper/ist/ablation/experience_ablation.csv` / `_playtest_regress/paper/ist/experience_ablation.md`。
- 重跑结果可能因 Godot/机器/随机种子不同；本包记录的是 2026-11-06 代码 `f9972eb` 的自动化结果。

## 经验规则（B 条件1）
`experience/` 是真实经验库副本；B 的 `with_rules` 只抽取与 HUD/移动/等待/锚点有关的 S/F/R（详见 `experience_rules_applied.md`），**不是 LLM 受试者实验**。

## 文件
- `manifest.json`：文件+sha256
- `task_tree/mainline-task-tree_v56.md`：历史任务树文本
- `experience/`：`EXPERIENCE_NODES.md`、`round78_EXPERIENCE.md`
- `audit/tester-report-paper-audit.md`：tester 只读审计**修正前快照**（见 `audit/SNAPSHOT_NOTE.md`，2026-11-06 06:19:19，复制于 commit `7c0eefb`）
- `commands.txt`：命令清单
- `build_info.json`：构建/harness/槽策略
