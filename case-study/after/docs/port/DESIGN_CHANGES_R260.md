# R260 GameOver 读档循环修复 + A35剧情恢复 + 桥门复核

## tester r251
- scene140 随机战斗（存档 HP1）→败→GAME_OVER 48次循环（加载最近档后立刻再 GameOver），阻塞 139/141；
- scene106↔109 桥门已 PAAS，但 scene109 落点反向门仍可能抢键（R259已修）。

## A) GameOver 读档循环修复
1. `request_load_game()` 开头统一 `_reset_after_save_load()`：
   - `_last_battle_result=""`、`_last_battle_team/evt/frame=0`；
   - `_battle_guard_until=0`、`_battle_guard_until_ms=0`；
   - `_game_over_shown=false`；`_load_safe_frames=180`；
   - 释放 battle 节点/VM/对白/输入锁，`PALState.in_battle=false`；
2. 菜单直接读档调用 `host.on_save_loaded()`，同样清残留+180帧保护；
3. 全灭兜底 `_dead_safe` 增加 `_load_safe_frames<=0`；且 `_game_over()` 一进入先清 `_last_battle_result`，避免 await 期间重复触发；
4. `_game_over()` 仍只回最近档，不新游戏/不覆盖档；0x4E 读档链路不会再触发 GameOver。

## B) A35/出城剧情恢复（用户此前接受同类剧情残血修复，可撤）
- 新增 `_restore_party_story_hp_mp()`：对当前队伍 HP/MP 回满，HP0成员也恢复到 max_hp/max_mp 可战斗状态；仅改运行期 PALState，**不写用户档**；
- 调用点：
  - A35 街坊对话完成（a35taishou）后；
  - 出城场景106桥门进入第5章时（双保险）。

## C) headless 验证
- **q2006**：载入槽1→故意设 HP0、`_last_battle_result="lose"`→`request_load_game()`：
  - 240/540帧后 `GAME_OVER` 未出现；`_last_battle_result=""`；`_load_safe_frames`正常归0；场景保持85；
- **q2005**（stale a36）：scene106桥门→scene109(672,1888) HUD **N170**；落点SPACE被吞，不再反向；
- **q2004**：scene85出城 N142→evt1583→106桥门 N6→109 N170→118→140 N276（长路自动loop到N237迭代上限；门段q1995验证）；
- **q1995**：140 evt2346 N0→139；**q1992**：139 N16→141 a36=1。
- boot exit0，无 SCRIPT ERROR；槽1只读、槽2未写、未开窗。

## N 表
85(A34 N68→91 N34→93 N24→82 N49→89 N64→85复命N6)→出城N142→evt1583→106桥门N6→**109 N170**→evt1996→118锚点→140 N276→139 N16→141。

## 文件
- 本文件；代码 world.gd/menu.gd。
