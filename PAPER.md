# 论文材料索引（Paper Artifacts）

> 本仓库同时是论文《Task-Tree-Guided Multi-Agent Acceptance Testing: Human-AI Collaboration
> and Agent-Originated Interface Evolution》的**唯一**材料仓库。论文正文引用的所有数据与案例
> 都在这两个目录里，不另外拆分仓库；**请引用下面的固定路径，不要引用某个提交里的行号**。

## 固定入口（可直接放进论文附录 / README / DOI 说明）

| 材料 | 路径 | 内容 | 稳定锚点 |
|---|---|---|---|
| 框架本体 | [`SKILL.md`](../SKILL.md) · [`README.md`](../README.md) | 四要素任务树、4 Agent、三重确认、双进度、禁作弊 | v4.0.0 起 |
| 后端契约 | [`scripts/backends/CONTRACT.md`](../scripts/backends/CONTRACT.md) | 引擎无关动作契约（输入/观测/门禁/退出码） | CONTRACT v4 |
| 实验数据与复现包 | [`experiments/`](experiments/) | 实验 A（HUD 6 路线 × 3 变体 × 3 seeds = 54 runs）、实验 B（经验消融 4 节点 × 3 条件 × 2 seeds = 24 runs）、repro 清单与审计 | 见下方"数据版本" |
| 案例研究（修复前 / 修复后） | [`case-study/`](case-study/) | PAL98 Godot 移植，`before/` 与 `after/` 可直接 `diff -r` 对比 | 见 `case-study/README.md` |
| 任务树快照 | [`experiments/repro/task_tree/`](experiments/repro/task_tree/) | 实验执行时使用的任务树 | 快照文件自带版本号 |
| 经验库副本 | [`experiments/repro/experience/`](experiments/repro/experience/) | 实验时的经验库与规则 | 同上 |
| 审计报告 | [`experiments/repro/audit/`](experiments/repro/audit/) | 只读审计（含审稿人关切项的回答） | 同上 |

**永久链接写法**：仓库地址 + 上面的路径即可，例如
`https://github.com/tanggengbo4532/task-tree-acceptance-replication/tree/main/experiments`。
需要锁定到某一版时用 **tag**（见 `CHANGELOG.md` 的版本号），不要用 commit 短哈希写进正文——
正文一旦写死哈希，后续勘误就无法在同一路径更新。

## 数据版本

| 字段 | 值 |
|---|---|
| 数据对应的代码 HEAD | 见 `experiments/README.md`「数据来源与边界」 |
| 实验环境 | Godot 4.7.2 Mono；Python 3.12.14；固定帧率 240 |
| 槽策略 | 团队槽 2 可覆盖；用户槽 1 只读（前后 hash 校验） |
| 不含 | 商业游戏资源、用户存档、个人路径 |

## 复现边界（正文需如实声明）

- **可自动复现**：walker 结果、CSV/JSON 派生指标、文件 SHA-256。
- **必须人工判断**：HUD 可读性、剧情语义、用户观感与接受度；headless 指标不能替代人工结论。
- **前置条件**：运行案例需要使用者自备合法安装的游戏数据（见 `case-study/README.md`）。

## 与框架版本的关系

实验数据在 v3.2–v3.4 时期产生。v4.0.0 重构了工具（`hud_walker` 不再假通过、新增 `step_runner`、
后端统一分发），**不改变实验的结论方向**，但：

- 若要用 v4 工具重跑，请用 `examples/pal98-walk-specs.json` 提供走位规格（v4 起不再内置案例路径）；
- `hud_walker` 的判定更严格，重跑时**失败数可能上升**——那是旧版"吞键也通过"被修正的结果，
  应在论文勘误或版本说明中注明。
