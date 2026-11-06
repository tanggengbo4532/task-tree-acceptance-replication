# R137 逃跑成功后世界移动冻结修复

## 现场（r136 tester）
- scene77 逃跑成功回世界后：N 恒 647，四方向/长按 7 次均无位移；ESC 可开菜单（输入正常）；读档恢复移动。
- 说明战斗结算本身完成，但世界侧留下“等待/脚本锁”，`_update_movement` 被静默挂起。

## 根因
- 逃跑结束 `on_battle_finished("flee")` 只清 `player_busy/_real_battle_active`，随后 `vm.resume_battle("flee")` 继续脚本；
  部分随机遭遇脚本没有 flee 分支/收尾等待，`resume_battle` 后 VM 仍 active/waiting（无对白可推进），
  `_update_movement` 开头检测 `vm.is_active()` 每帧清空方向输入 → 世界移动冻结；ESC 菜单不依赖此路径所以正常。
- 读档会强制结束 VM/清等待，所以能恢复。

## 修复（world.gd R136-FLEEUNLOCK-1）
- 在 `on_battle_finished` 的 `resume_battle(result)` 之后，对 **result=="flee"**：
  - 若 VM 仍 active → `force_finish()`（或 `ended=true`）并清 `waiting_battle`；
  - 清 `_dialog_tail=false、player_busy=false、_wait_release=false、_held_dirs、_pending_move_dir、_search_lock=0`；
  - `PALState.in_battle=false、_real_battle_active=false`；
  - 打 `FLEEUNLOCK` 日志。
- 逃跑保护仍保留：同一事件 180 帧 + 未离开原圈 +8 时不再重触发（R136-FLEEGUARD-1）；换场景时清 guard。
- 胜利逻辑不变。

## 验证（headless）
- 模拟逃跑结束态（scene77, vm.last_event_object_id=1429, player_busy/_real_battle_active=true, vm.waiting_battle=true）调用 `on_battle_finished("flee")`：
  - `busy=false、vm_active=false、guard=1429、real_battle=false`；
  - 立刻按方向键：位置 (976,1880)→(976,1888) **移动成功**，N 随位置变化（证明世界移动已解锁）。
- boot exit0；无 SCRIPT ERROR；槽1 只读；未开窗。

## tester 复测点（新 hash）
1. 槽2 载入 scene77（N690）→ 走到遭遇圈触发 → 金蝉脱壳逃跑；
2. 回世界后**立即**四方向可移动（不再 N 冻结）；
3. 离开原遭遇圈（>原事件环+8）后再回来可再次触发；原地停留 3s 内/圈内不重进；
4. 继续按 scene77 路线文件走剩余段；胜利/失败路径不受影响。
