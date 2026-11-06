# IST A · HUD 三变体实验结果（6 routes × 3 variants × 3 seeds）

> 生成：developer3｜2026-11-06（Asia/Shanghai）｜代码 HEAD **`f9972eb`**（R311，未改）
> 实验：headless Godot `--fixed-fps 240`；团队槽2；用户槽1只读，runner 前后 hash 不变（`8880C321…`）
> 性质：**自动化 walker 实验**，不是人类受试者实验；不可外推为用户研究。

## 1. 路线（C 基线已 verified）

| ID | 类别 | start→target | expected | N0 | anchor(sha256前16) |
|---|---|---|---|---|---|
| R1 | complex | 207(1024,1600)→evt3461(464,280) | scene206 | 242 | `C18606EF…` |
| R2 | simple | 206(1488,1592)→evt3442(864,1280) | A46 dialogue/VM（同场景） | 78 | `CAE77CAF…` |
| R3 | simple | 153(1680,408)→A39(960,1056) | scene155 | 179 | `9AEF1083…` |
| R4 | simple | 255(1680,1640)→A49点(1680,1720) | scene253 | 10 | `7C922D7C…` |
| R5E | simple | 247(896,1104)→evt4365(896,1152) | scene255 | 2 | `C026F578…` |
| R6 | detached/detour | 139(1552,1432)→evt2342(1376,1360) | 触发区/VM（battle=false 如实记录；不要求战斗/胜利） | 16 | `73922E9D…` |

- R5 原 scene247 nanzhao 锚点 C preflight **失败**（36步后随机战/VM，未到门），按 Lead 授权替换为 R5E（beforepalace 锚点）。候选 **R5A**（scene185 forest）载入即战斗/0步、**R5B**（scene188 forest gate）500步未到门、**R5C**（scene188 door）与 **R5D**（scene178 圣姑居）均为 **0步 success**：锚点载入位置已在目标/触发区内，C 未真正行走；仅作 preflight 语义记录，均不纳入正式 6 条。
- 成功判据按 Lead 确认写死：R2 无场景切换、以 A46 VM/dlg 为成功；R6 到达触发区/VM（battle=false 如实记录；不要求战斗/胜利）。

## 2. 变体

| 变体 | walker |
|---|---|
| A | **无 HUD**：不知道目标/路线；随机方向 + 撞墙后随机换向（seeds 101/202/303） |
| B | **简单导航**：知道目标坐标，轴向贪心；撞墙仅尝试次轴，无 BFS/绕行 |
| C | **当前 HUD**：读 `_a14g_key` 方向 + N；多源 BFS 距离场（游戏内） |

## 3. 结果总表（3 seeds；成功数为 seed 通过数）

| Route | A 无HUD | B 简单导航 | C 当前HUD |
|---|---:|---:|---:|
| R1 complex | 0/3 | 0/3 | **3/3** |
| R2 simple | 0/3 | 3/3 | **3/3** |
| R3 simple | 0/3 | 0/3 | **3/3** |
| R4 simple | 2/3 | 3/3 | **3/3** |
| R5E simple | 2/3 | 3/3 | **3/3** |
| R6 detached/detour | 1/3 | 3/3 | **3/3** |
| **合计** | **5/18（27.8%）** | **15/18（83.3%）** | **18/18（100%）** |

### 关键指标（均值；成功 run 的路径偏差按 N0 基线）

| Route | Variant | success | steps | invalid | wrong_dir | recovery | frames | path_dev_abs |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| R1 | A | 0/3 | 520 | 0 | 262.7 | 0 | 6753 | – |
| R1 | B | 0/3 | 520 | 0 | 255.0 | 0 | 6753 | – |
| R1 | C | 3/3 | 239 | 0 | 23 | 0 | 3100 | -3 |
| R2 | A | 0/3 | 320 | 0 | 147.3 | 0 | 4153 | – |
| R2 | B | 3/3 | 71 | 0 | 0 | 0 | 916 | -7 |
| R2 | C | 3/3 | 71 | 0 | 0 | 0 | 916 | -7 |
| R3 | A | 0/3 | 420 | 17 | 199 | 5.7 | 5383 | – |
| R3 | B | 0/3 | 421 | 204 | 0 | 0 | 5866 | – |
| R3 | C | 3/3 | 170 | 0 | 29 | 0 | 2203 | -9 |
| R4 | A | 2/3 | 74.7 | 4 | 34.7 | 0.7 | 950.7 | 27 |
| R4 | B | 3/3 | 3 | 0 | 1 | 0 | 32 | -7 |
| R4 | C | 3/3 | 3 | 0 | 1 | 0 | 32 | -7 |
| R5E | A | 2/3 | 117.3 | 2.7 | 60 | 0 | 1529 | 24 |
| R5E | B | 3/3 | 1 | 0 | 0 | 0 | 42 | – |
| R5E | C | 3/3 | 1 | 0 | 0 | 0 | 42 | – |
| R6 | A | 1/3 | 218 | 38.3 | 72.7 | 10.3 | 2682 | 117 |
| R6 | B | 3/3 | 22 | 6 | 0 | 0 | 250 | 6 |
| R6 | C | 3/3 | 16 | 0 | 0 | 0 | 201 | 0 |

- `path_dev_abs = steps - N0`（N0=start_N，HUD 距离基线；BFS 精确目标不可达时回退 N0；负值表示目标触发环早于中心/短于 N0，并非作弊）。
- **F4：raw `shortest` 字段是 BFS 到精确目标的估计；CSV 的 `path_deviation_*`/`path_baseline` 使用 N0 作为统一基线**（`path_baseline_source` 标注来源），两者语义不同；原始 raw 不覆盖，CSV 为派生指标。
- `wrong_dir` 按“移动后到目标的 metric 比移动前增加”计数；`recovery` 按连续受阻后恢复/空格推进计数；`invalid` 为 `_tap` 无位移。
- **确定性**：B/C 在三个 seed 下每条路线结果完全相同（std=0），如实记录；A 的随机 seed 造成 R4/R5E/R6 成功率和步数差异（R1/R2/R3 A 均失败但 wrong_direction 数字随种子略变）。
- R4/R5E 的 3 步/1 步成功是**真实短门/触发点**，不是传送；C 与 B 在简单路线一致，说明 HUD 收益主要出现在复杂/受阻路线（R1/R3）。
- R6 C 成功时 `vm_active=true`、`battle=false`：到达 evt2342 触发区并由剧情 VM 接管；**不暗示必然进入战斗**，按 Lead 约定不要求胜利。

## 4. 结论（证据边界内）

1. R1（207 石阶/栅栏 complex）和 R3（153 塔内）上：A/B 失败，C 成功；R1 C 239步 vs B 520步，R3 C 170步 vs B 421步；B 在 R3 撞墙 204次。
2. R2/R4/R5E 这类简单/短门路线，B 与 C 均成功；不能把 HUD 说成所有路线都优于简单导航。
3. R6 detached/detour：B/C 成功，A 仅 1/3；A 的 38.3 invalid、10.3 recovery 显示随机+撞墙启发在复杂起点不稳定。
4. **A 是固定随机种子的自动化 walker，不是人类“无 HUD”能力**；B/C 在 headless 固定 fps 下确定，三 seed 完全相同；样本为 6 路线×3 变体×3 seed，不做显著性推断。

## 5. 原始数据/复现

- 每条 run 原始日志：`raw/full_<route>_<variant>_seed<seed>.txt`
- 全量结果：`hud_eval_runs.csv`（54行）/ `hud_eval_summary.json`
- C preflight：`preflight_final.csv`、`raw/preflight_*.txt`
- 路线/锚点：`route_matrix.md`/`route_matrix.csv`
- 配置：`run_config.json`（fixed_fps=240、seeds、变体、max_steps）
- harness：`_playtest_regress_dev/round78/run_probe_stream.py` + `dev3_probe.py` 的 `dev3ist`（已跟踪；runner 禁止槽1并做前后 hash guard）
- 代码/正式游戏：**未改**；未开窗；用户槽1未写。

## 6. 局限

- 自动化 walker 不是人类受试者；不能声称用户可用性/偏好。
- 仅 6 条固定路线、3 seeds；确定性 B/C 的 3 次重复不是独立样本。
- path baseline 使用 HUD N0；BFS 精确目标不可达时标 N0，路径偏差为近似指标。
- A 的随机+撞墙启发是最弱对照，不代表“所有无 HUD 人类玩家”。
- **F10：R3B 421步、R6A 261步比 max_steps 多1**：alternate/retry tap 也计入 steps，而 max_steps 限制主循环尝试数；不是超时或伪造。
- **F9：`full_stdout.txt` 是 PowerShell 重定向的 UTF-16LE；`raw/full_*.txt` 为 UTF-8**；机器处理请用 `hud_eval_runs.csv`。
- 结果依赖 `f9972eb` 构建与真实锚点；更换构建需重跑。
