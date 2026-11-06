# R165 scene72 洞窟支路导航 + 调试日志门控

## A) scene72 导航（用户卡在 N≈300）
- 数据核对：scene72（map64）**只有两个出口** evt1389=(1168,1080)、evt1390=(1744,1128)，均 → scene69；
  evt1382-1395 为遭遇战；**没有直接去扬州/70 的门**。
- 旧 c3 未包含 scene72，HUD 继续指远处扬州目标 → 不可达，用户看到 N 最小 ~300。
- 修复（world.gd R165-SC72-1）：
  - c3 场景列表加入 **72**；
  - `_c3_scene_step(72)` → **evt1389 (1168,1080)**「第3章：离开洞窟 → 返回村道（前往扬州方向）」。
- headless（槽1只读；scene72 从 evt1359 落点 (1120,1056) 复现）：
  - HUD `目标 第3章：离开洞窟 → 返回村道（前往扬州方向）｜↓剩5格`；
  - 按 HUD 方向 4 步：N 5→4→2→0，interact=1389「按空格前往」；
  - SPACE → **scene69**，回到村道主线。
- 回 scene69 后 HUD 指向 evt1368 (560,520)（scene69→70 主线），从落点 (1408,1168) N306；
  headless 按 HUD 实时方向走 80 步 N 306→226（每步−1，需跟随方向变化：先↑再→/←），**不是不可达**；
  用户若只按住 ↑/固定方向会卡在 ~300，需按 HUD 当前方向走。

## B) 调试日志上屏
- 新增 `_battle_dbg()`：仅 `--debug`/`--debug-hud`/`_debug_keys_enabled` 时 print；
- world 的 `[battle-entry]`/`[battleguard]`、battle.gd 的同类日志、VM `_start_battle` 日志全部改门控；
- 正常游玩 stdout 不再出现这些行（R163/R164 逻辑保留）。
- headless 普通启动（无 --debug）验证无 `[battle-entry]`/`[battleguard]` 输出。

## 验证
- boot exit0；槽1未写；未开窗。
- tester4 复测：
  1. scene72 → 按 HUD 到 evt1389 → SPACE → scene69；
  2. scene69 按 HUD **实时变化的方向**（先↑，然后→/←）走到 evt1368；N 应每步−1，不再卡 ~300；
  3. 正常游戏画面/控制台不应出现 `[battle-entry]`/`[battleguard]`。
