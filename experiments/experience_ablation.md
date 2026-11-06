# IST B · 经验规则消融（自动化执行器，非 LLM 受试者实验）

> 生成：developer3｜2026-11-06｜代码 HEAD **`f9972eb`**（R311；未改生产代码）
> **重要**：这是**自动化规则消融**，不是 LLM 受试者实验；不可写成“模型能力/人类学习”结论。
> 团队槽2；用户槽1只读；runner 前后 slot1 hash 一致。

## 1. 节点（4 个，同构建/同锚点）

| Node | 路线 | 类别 | anchor |
|---|---|---|---|
| R1 | 207(1024,1600)→evt3461(464,280) | complex | `anchor.sav` |
| R3 | 153(1680,408)→A39(960,1056) | simple | `anchor.sav` |
| R4 | 255(1680,1640)→A49点(1680,1720) | simple | `anchor.sav` |
| R6 | 139(1552,1432)→evt2342(1376,1360) | detached/detour | `anchor.sav` |

## 2. 三个条件

| 条件 | 执行器规则 |
|---|---|
| **with_rules** | 使用经验库蒸馏规则：HUD 严格跟随方向/N；撞墙后按 HUD 替代方向恢复；对话/VM 用 Space 有界推进；已知锚点载入/关对话框。对应 A 实验 C 变体 |
| **no_rules** | 仅任务规格（知道 target 坐标），轴向贪心；**不读 HUD、无撞墙绕行、无等待/恢复规则**。对应 A 实验 B 变体 |
| **clear_context** | 同 no_rules，并在载入前后显式清空 `_a14g_key/_a14g_left/_a19g_dist/_a19g_t` 等运行期引导缓存；每次独立进程/锚点重载，不携带跨条件状态 |

- 每 node×condition 跑 **2 次**（seed 101/202）。数据确定性：同条件两次结果完全一致（如实记录，不是伪造方差）。
- 指标：success、steps、invalid_moves、wrong_direction、repeated_failures（同一受阻点≥3次）、recovery_count、frames、VM/battle。

## 3. 结果

### 3.1 每节点成功数（2 runs）

| Node | with_rules | no_rules | clear_context |
|---|---:|---:|---:|
| R1 complex | **2/2** | 0/2 | 0/2 |
| R3 simple | **2/2** | 0/2 | 0/2 |
| R4 simple（短门） | 2/2 | 2/2 | 2/2 |
| R6 detached/detour | **2/2** | 0/2 | 0/2 |
| **合计** | **8/8（100%）** | **2/8（25%）** | **2/8（25%）** |

### 3.2 均值指标

| Condition | success | steps | invalid | wrong_dir | repeated_fail | recovery | frames mean |
|---|---:|---:|---:|---:|---:|---:|---:|
| with_rules | 8/8 | 107.0 | 0 | 13.25 | 0 | 0 | — |
| no_rules | 2/8 | 300.75 | 167.0 | 64.0 | 0.5 | 0 | — |
| clear_context | 2/8 | 300.75 | 167.0 | 64.0 | 0.5 | 0 | — |

### 3.3 关键现象
- R1：with_rules 239步→206；no_rules/clear_context 520步耗尽、仍在207（R1 无规则轴向在石阶/栅栏卡住）。
- R3：with_rules 170步→155；no_rules/clear_context 420步、**invalid 408**、重复受阻点 1，仍在153。
- R6：with_rules 16步、VM/dlg 成功；no_rules/clear_context 260步、**invalid 260**、重复受阻点 1，未触发。
- R4：短门路线三个条件都3步成功；**简单路线不能区分规则增益**。
- no_rules 与 clear_context **完全相同**（两次均一致）：本实验每个 run 已独立进程+锚点重载，清空缓存未改变结果；如实记录，不强行制造差异。

## 4. 解释与结论（证据边界内）

- 在 R1/R3/R6 上，经验蒸馏规则（HUD 严格跟随+受阻恢复+对话推进）把自动化执行器从失败带到成功；R4 短门无差异。
- **这是规则消融，不是 LLM 受试者实验**：不能推断 LLM 使用经验库的学习效果；不能声称人类可用性。
- clear_context 与 no_rules 无差异，说明本 harness 的跨条件状态已被进程隔离；只有规则内容本身造成差异。
- 样本 4 节点×2 runs，未做显著性检验；结果依赖 `f9972eb` 与真实锚点。

## 5. 原始数据/复现

- `ablation/experience_ablation.csv`（24行：4节点×3条件×2 seeds）
- `ablation/experience_ablation_summary.json`（聚合）
- `ablation/raw/<node>_<condition>_seed<seed>.txt`
- `ablation/ablation_meta.json`（slot1 before/after、slot2 restore）
- `ablation_runner.py`（路径参数化，见 env `IST_ROOT/IST_DIR/PAL98_APPDATA/IST_PYTHON/IST_RUNNER`）
- 规则来源（文本副本将放入 `repro/experience/`）：`_playtest_regress/EXPERIENCE_NODES.md`、`_playtest_regress/round78/EXPERIENCE.md`；本实验仅抽取与 HUD/移动/等待/锚点有关的 S/F/R 规则。

## 6. 规则 1–3 → 经验库真实条目（R6/R7）
- 见 `repro/experience_rules_applied.md` 的映射表：HUD 严格跟随→S216/S217/S218+F90；撞墙恢复→F92/F94/F96/F99/F100+S219/S220/S222；等待/剧情→F86+S208+S234/S235（全部为真实条目，未虚构 ID）。
- **消融变量仅为规则 1–3**；规则4锚点方法在各条件固定；这不是 LLM/人类受试者实验。
