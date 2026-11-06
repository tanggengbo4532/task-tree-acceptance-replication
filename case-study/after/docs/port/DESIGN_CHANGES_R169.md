# R169 scene69 洞口卡顿：可达性 BFS 改目标侧集合缓存（每场景一次，O(1) 查询）

## 根因
- R167 `_a30_can_reach_evt1368(p)` / `_a30_can_reach_evt1360(p)` 在**每帧 c3 HUD 更新**里直接 `_s4g_build`：
  - 每次对 evt1368/evt1360 做 16k+ cells BFS；
  - 且 c3 的目标场和 guide 的目标场共用 `_s4g_dist` 缓存：当玩家在洞口、c3 判 evt1368 不可达→目标 evt1360 时，
    两套目标每帧互相踢缓存 → **反复重建 16k BFS**，导致 scene69 洞口/村道走动明显卡顿。
- R154 装饰只在 `load_scene` 载入 map59 时执行一次（不是每帧）；`_is_encounter_event` 已有场景缓存。

## 修复（R169-REACHCACHE-1）
- 每个场景只建一次**可达集合**：
  - `_a30_reach_set_1368`：从 evt1368 目标环做一次 BFS，存所有可达格；
  - `_a30_reach_set_1360`：同理；
  - 场景切换/读档时清空（随 load_scene 重置）。
- `_a30_can_reach_evt1368/1360` 改为 **Dictionary.has(p)** O(1)，不再每帧 `_s4g_build`、不再与 guide 缓存互相踢。
- 目标选择逻辑不变（可达→村道 evt1368；不可达→山洞 evt1360；都不可达→空等待）。

## headless 验证（槽1只读）
- scene69 南侧 (1408,1168)：
  - 缓存建立一次：`reach_scene=69`、`set1368=16647 cells`、`set1360=16797 cells`；
  - idle 120 帧耗时 **827ms（≈6.9ms/帧）**；期间无 BFS 重建；
  - 走 40 步：`per_step_ms≈119`（含固定 15 帧输入等待；headless 帧率约145fps），
    `switched=0`、N 306→266、target 始终保持 evt1368。
- 无 `[perf]`/战斗调试日志上屏（仅 --debug 输出）。
- boot exit0；槽1未写；未开窗。

## 说明
- 这是把“每帧/每次 HUD 更新的 16k BFS”变成“每场景一次 BFS + O(1) 查询”；
  洞口区域不再有重复 BFS 抖动；主路线/N 逻辑保持不变。
- 若实机仍有卡顿，请抓 `--debug-hud` 的帧耗时日志，我再查其它每帧路径。
