# 实验数据与可复现包（Experiments）

本目录存放论文《Task-Tree-Guided Multi-Agent Acceptance Testing: Human-AI Collaboration and Agent-Originated Interface Evolution》引用的实验数据与可复现材料。

## 数据来源与边界

- 代码 HEAD：`f9972eb`（R311，未改生产代码）
- Godot 4.7.2 Mono；Python 3.12.14；固定帧率 240
- 团队槽 2；用户槽 1 只读，前后 hash 校验
- 不含商业游戏资源、用户存档、隐私路径

## 实验 A：HUD 三变体对照（6 路线 × 3 变体 × 3 seeds = 54 runs）

| 变体 | 成功 |
|---|---|
| A（无 HUD，随机+撞墙） | 5/18 |
| B（简单导航，轴向贪心） | 12/18 |
| C（当前 HUD，多源 BFS 距离场） | 18/18 |

- 汇总：`hud_eval_summary.md` / `hud_eval_summary.json`
- 逐 run：`hud_eval_runs.csv`（54 行）
- 原始日志：`raw/full_*.txt`
- 路线/锚点：`route_matrix.md` / `route_matrix.csv`

## 实验 B：经验规则消融（4 节点 × 3 条件 × 2 seeds = 24 runs）

| 条件 | 成功 |
|---|---|
| with_rules | 8/8 |
| no_rules | 2/8 |
| clear_context | 2/8 |

- 汇总：`experience_ablation.md`
- 逐 run：`ablation/experience_ablation.csv`
- 原始日志：`ablation/raw/*.txt`

> 说明：实验 A/B 均为**自动化执行器（headless）结果**，不是人类受试者或 LLM 受试者实验；B 为规则级消融。数值范围以本目录原始 CSV 为准。

## 可复现包（repro/）

- `build_info.json`：构建/模型/槽策略
- `commands.txt`：复现命令
- `manifest.json`：文件清单与 SHA-256
- `task_tree/`：任务树快照
- `experience/`：经验库副本
- `audit/`：只读审计报告

## 复现须知

- 自动化可复现：walker 结果、CSV/JSON 派生指标、文件 hash。
- 必须人工判断：HUD 可读性、剧情语义、用户观感/接受度，不得由 headless 指标替代。
- 运行需要用户自备合法安装的游戏数据。
