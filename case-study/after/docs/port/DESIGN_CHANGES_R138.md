# R138 逃跑保护圈内移动锁死修复（auto 脚本也暂停）

## 现场（r137 tester）
- 逃跑后离开原遭遇圈可移动；**一进入原遭遇圈移动再次锁死**（N 恒 641），仍在世界画面。
- 说明：R136 只拦了 `_check_touch_triggers` 的触碰触发，但遭遇事件还有 **auto 脚本**在 `_update_event_updates` 每帧推进；
  进圈后 auto 脚本重新启动战斗/等待状态，世界移动被 VM/等待锁住。

## 修复（world.gd R138-FLEEGUARD-2）
- 在 `_update_event_updates` 的 auto 脚本推进前加同一保护：
  - 若 `id == _flee_guard_evt` 且（保护期未到 或 距原事件环 < ring）→ `continue`；
  - 只有时间到且离开原圈+8 才清除 guard，恢复该事件 auto/触碰。
- `_check_touch_triggers` 的 R136 保护保留（同一事件保护期内/圈内跳过）。
- **保护只 skip 该事件，不设置 `player_busy`、不改 `_wait_release`、不清方向输入**；移动照常。

## 验证（headless，槽2 只读）
- 模拟逃跑保护态（guard=evt1429, until=frames+600, ring=120），站进 evt1429 圈内 (1328,1568)：
  - `busy=false、vm_active=false、real_battle=false`；
  - 按方向键：← 成功移动 (1328,1568)→(1312,1568)（↓ 被地图阻挡属正常），**圈内不锁移动**。
- boot exit0；无 SCRIPT ERROR；槽1 只读；未开窗。

## tester 复测点（新 hash）
1. 槽2 scene77 N690 → 触发遭遇 → 金蝉脱壳逃跑；
2. 回世界移动正常；**重新走进原遭遇圈**仍可自由移动（不会 N 冻结/重进战斗）；
3. 离开原圈+8 后再回来 → 可再次正常触发遭遇；
4. 继续按 scene77 路线文件走剩余段。
