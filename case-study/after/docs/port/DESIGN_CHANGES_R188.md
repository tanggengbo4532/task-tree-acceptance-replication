# R188 scene77 遭遇压制被 restore 覆盖修复 + 锚点

## 根因
- R164 `_restore_encounter_events_after_guard()` 在宽限结束时按 `_guard_event_backup` 恢复 scene77 全部 encounter 的 state/auto，
  会把 R186/R187 对普通遭遇的压制（取消追击/收起）**恢复成原样**；且 load 时压制若早于场景事件载入也会被覆盖。
- 表现为锚点 N300 附近仍每 8 步一场、10 场全部回来。

## 修复（R188-S77PRESSURE-3）
1) scene77 压制改为 **deferred**（场景事件载入后再应用）；
2) `_restore_encounter_events_after_guard` 恢复完成后，若当前 scene==77 **立即重新应用**压制；
3) `_process` 每 120 帧对 scene77 重新 apply 一次兜底；
4) 普通遭遇只保留 **1 场**（第3个，state1）；其余 state0；**全部 auto_script=0 不追击**；
   Boss/剧情事件不在压制范围；
5) 战后宽限保持 **40s/60s**（普通胜利/逃跑）。
- 用户已批准“遇敌过频可修”。

## 验证（headless，团队槽2）
- 载入 scene77 后统计 evt1425-1487：
  - encounter **total=10，alive_state=1，chase=0**（仅1场可见、全部不追击）；
- 锚点档：
  - N50：scene77 (832,704) → evt1428；
  - N300：scene77 (1616,968) → evt1428；
  - 两档由同一场虚拟路径得到；读档后 deferred 压制同样生效。
- R185 同源 BFS：入口 N=690 → 静态 690→0；boot exit0；槽1/槽2 未写、未开窗。

## tester
1. N300/N50 锚点读档：N 每步−1，最多1场普通战；到 evt1428→SPACE→scene68；
2. 全程从18:25 scene70 出发，目标不再连续全灭。
