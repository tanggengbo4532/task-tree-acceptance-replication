# R212 scene81 角色走不动修复：`_is_obstacle` 最前白名单

## 根因（日志证据）
- R211 后 HUD 已正常（↓·N324），但移动仍被拒；
- 在 `_update_movement` 加 `[mv81]` 日志：
  ```
  [mv81] pos=(288,416) dir=0 target=(288,424) walk=true obst=true ...
  [mv81] blocked obstacle target=(288,424)
  ```
- 即：`_walk_target_ok` 已允许（walk=true），但**移动碰撞用的 `_is_obstacle(target)` 仍返回 true**；
- 原因：`_is_obstacle` 里 scene81 白名单块在**native 墙/void 判定之后**，目标格先被 native 障碍 return true，白名单根本没执行；
- HUD BFS 用 `_s4g_walk_ok`/`_walk_target_ok`（已提前走白名单）所以显示可走，实际移动仍走旧障碍 → 走不动。

## 修复（R212-S81MOVE-1）
- 在 `_is_obstacle` **函数最开头**加：
  ```
  if scene==81 and _s81_restrict_scene==81:
      return not _s81_ground_cell_ok(Vector2i(x,y))
  ```
- 移动碰撞、HUD、guide 三处现在完全同源；
- 删除临时 `[mv81]` 调试日志。

## headless（用户槽1 4A8CE9CE… scene81 288,416）
- HUD：↓·N324（无等待）；
- 真实按键模拟连续走 12 步：
  - pos (288,416)→(288,424)→…→(336,488)
  - N 324→323→…→312（每步−1）
  - HUD 方向从 ↓ 切换到 →，无卡住；
- 静态全程 324 步→N=0（evt1507 1696,1136）；
- boot exit0；槽1/槽2 未写、未开窗。

## tester（卡点档 1B16A4C8/9E180DCE）
- 载入 scene81 应 HUD ↓·N324；
- 方向键实际位移、N 每步−1；
- 沿 HUD 走满 324 步 → N0 → evt1507 → SPACE → scene84；
- 若中途遇敌/卡点，给坐标/截图。
