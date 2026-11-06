# R159 逃跑/胜利后遭遇冷却（修复 flee 后 2 步再战循环）

## 现场
- HEAD d8b84e7，槽1 E44079CB scene71 固定遭遇：
  第1场 flee → N 保持、HP/MP 保留；但走 2 步立即再战同一队；连续 3 场 flee 循环。
- 根因：
  1) `on_battle_finished("flee")` 在 `resume_battle` 后立即 `force_finish()`，a2=41073 的 `0x4B vanish` 可能来不及执行；
  2) R136 flee guard 只保护**同一个 event id** 3s，附近同队怪/追击怪换 event 仍可 2 步贴脸；
  3) 0x4C 追击怪持续追着玩家，离开旧 trigger 圈+8 后 guard 清除，立即重新触发。

## 修复（world.gd R159-FLEECOOLDOWN-1）
1) 逃跑结束显式清场：当前遭遇事件 `EO_VANISH = max(300, 原值)`（约 5s 可见 vanish），
   与原版 a2 的 0x4B 语义一致；若某脚本无 a2（不可逃）本分支不会发生。
2) **10s 脱战窗口**：`_flee_guard_all_until = frames + 600`；
   窗口内 `_check_touch_triggers` 跳过所有**遭遇/追击事件**（事件触发/自动脚本含 0x0007 或 0x004C），
   包括旁边同队怪；不冻结移动、不跳过剧情门/场景门。
3) 同一事件 guard 延长到 600 帧、圈半径 max(96, ring+32)；保留原 R136 逻辑。
4) 胜利后：若当前事件是遭遇事件，同样给 `EO_VANISH=300`，避免原地/两步内重生再战；剧情战/Boss 不受影响。
5) 事件判定 `_is_encounter_event()` 按场景缓存，只读事件脚本，不改事件/碰撞数据。

## headless 验证（槽1只读）
- scene71 触发 evt1385/team33 → 模拟 flee：
  - evt1385 `vanish=300`（清场可见）、guard_all_until=+600、战斗节点已释放；
  - 把玩家送回 evt1385 坐标并等待 150 帧：**未再触发战斗**（battles=0、mode=null）。
- boot exit0；槽1未写；未开窗。

## tester4 复测（A）
1. 固定遭遇点，第1场选择逃跑；
2. 逃跑后原地/走 10~20 步，确认不再 2 步内被同一队/旁边怪贴脸；
3. 继续走 100 步统计战斗场数（可继续用逃跑结束战斗），频率应明显下降；
4. B4 已 PASS 不需重测；固定怪 HP1800 不改。
