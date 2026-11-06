# 主线自动推进验收（Story Run）

> 目的：用 `--auto` 无人工操作让脚本/场景/战斗/对话系统沿主线自动运行，作为“可通关”过程证据。
> 该模式仅用于验收（战斗强制胜利、场景图直跳等只在该模式下启用），不改变正常游戏行为。

## 命令

```
Godot_v4.7.2-stable_mono_win64_console.exe --headless --path <proj> \
  --fixed-fps 600 --auto --auto-graph --log-file <out.log> --quit-after 250000
```

- `--fixed-fps 600` 让 headless 以最高吞吐运行。
- `--log-file` 逐行 flush，可实时观察进度（stdout 重定向到文件有缓冲，不适合监控）。
- 日志：`_rea_runtime/out/*.log`；截图：`_rea_runtime/out/shots/auto_sN_tT.png`。
- 分段续跑：`--auto-continue` 从自动存档槽 9 继续（visited 场景集合持久化在 `user://auto_visited.json`）。

## 自动策略（world.gd）

1. **对话**：`waiting_dialog` 每 8 帧推进（打字机→翻页→关闭→`vm.advance_dialog`）。
2. **移动**：BFS 寻路到最近可触发事件（调查/对话优先，门兜底）；16/8px 离散格点步 + 7 帧冷却。
3. **换场景**：正常走门触发 0x0059；自动模式用**场景图 BFS 到最近未访问场景**（`data/scene_graph.json`，
   由 `tools/gen_scene_graph.py` 从 SSS 生成），直接 `load_scene(第一跳)`；连通分量耗尽时全局跳到任意未访问场景。
4. **卡死自愈**：450 帧无场景进展 / 600 帧同坐标 / `player_busy` 残留 / 对话框残留 → force_finish + F8；
   同场景载入 >4 次判定循环 → 跳到未访问场景（`CYCLE_DETECT/CYCLE_BREAK`）。
5. **战斗**：自动出招，`--auto` 下 `request_battle` 强制 `force_win`（验收用）。
6. **结局**：进入含 0x0096/0x00A0 操作码的场景（scene 282）时自动执行对应触发脚本（事件 4801/脚本 35464），
   并暂停所有强制跳转，让终局战斗/对白/结局演出跑完。

## 覆盖率记录

| 运行 | 场景覆盖 | 说明 |
|---|---|---|
| **t_story_final（新游戏→结局，250k 帧）** | **275/294 场景**（含 282 结局场景、286–294） | 40+ 剧情战斗；scene282 自动触发结局事件 → 终局 BOSS team=313 → `ENDING` → `[Ending] 开始结局演出`；0 SCRIPT ERROR |
| t_long2（新游戏，250k 帧） | 294/294 场景 | 纯覆盖遍历（`--auto-graph` 跳过本地事件，未触发结局） |
| t_autoLL（60k 帧，场景图导航） | 65 场景 | 中期记录 |
| t_autoBB（60k 帧，旧门逻辑） | 26 场景 | 余杭镇→仙灵岛→苏州线 |
| t_autoX | 20 场景 | 未加死循环保护时卡在“小豆子”对话循环 |

### 已覆盖剧情区域

- 余杭镇/客栈/村道（1–14）、仙灵岛（22–33）、苏州线（35–41）、隐龙窟/白河村/扬州（42–66+）、
  京城/蜀山/锁妖塔方向（90–200+）、终局与结局后场景（278–294）
- 证据：`docs/port/evidence/story_final_run_summary.log`、`docs/port/screenshots/29~43_*.png`

## 结局链路（已验证）

- 结局触发脚本：事件 4801（脚本入口 35464，场景 282/地图 194），含终局 BOSS 战与终局对白。
- `AUTO_ENDING_TRIGGER scene=282 event=4801 script=35464` → 终局 BOSS team=313（force_win）→
  对白 msg 12220 → `[auto] ENDING` → `[Ending] 开始结局演出`。
- `--ending-test` 可完整跑 `[Ending] 开始… → 结束`，生成 `ending_fbp75/77/68/anim150` 截图。
- 证据：`docs/port/evidence/ending_auto_trigger.log`、`docs/port/screenshots/36、37、38、43_*.png`。

## 已知限制

- 自动通关使用 **force_win（剧情战斗强制胜利）** 与 **场景图跳转**（验收模式专用，正常游戏逻辑不受影响）；
  它证明主线脚本/场景/战斗/对话/结局链路可从新游戏连续跑到结局，不等价于人工操作完整通关。
- 部分场景存在对话/自动脚本循环，靠看门狗跳出（日志可见 `CYCLE_DETECT`/`PROGRESS_TIMEOUT`）。
