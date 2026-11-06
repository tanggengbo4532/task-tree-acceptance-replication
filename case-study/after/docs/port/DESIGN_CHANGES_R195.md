# R195 夜间客栈提示循环修复（scene94 evt1741 提示抢 HUD）

## 根因
- evt1548 正常 → scene94 (816,904)；
- c3 scene94 此时真实目标为 **evt1731 客栈上楼**（HUD 上楼 N50，N 每步−1）；
- 但 `_scan_extra_interact` 中 evt1741（客栈夜间剧情，坐标784,856）只要玩家在120半径内就显示
  「按空格进入客栈/触发夜间剧情（第 4 章）」，**覆盖并抢占** HUD 中央提示；玩家按 SPACE 会重复触发 evt1741 脚本，看起来“走1步就回客栈提示循环”。
- 实际 N 一直在 −1（49/48/47…），只是提示文字错误引导。

## 修复（R195-A33PROMPT-1）
- scene94 evt1741 SPACE 提示增加条件 **`_a19g_target_evt == 1741`**：
  只有引导目标真的是 evt1741 时才显示；目标为 evt1731/1732/1728 时不再抢占 HUD。
- 未改剧情/脚本/地图；SPACE 只在目标正确时出现。

## headless 复现/验证
- scene83 evt1548 N0 SPACE → scene94 (816,904)，HUD「客栈上楼」target evt1731 **N=50**；
- 走 4 步：N 50→49→48→47→46，HUD 始终「客栈上楼/按↑」，**不再出现客栈提示循环**；
- boot exit0；槽1/槽2 未写、未开窗。

## 锚点档（不写游戏槽）
- `round78/slot4_scene94_night_entry_anchor.sav/json`：scene94 (816,904)，vars 团队槽2；读档 HUD target evt1731 N50；
- scene83 入口锚点：`slot4_scene83_entry_anchor`（1008,1024）。

## tester
- 从 scene83 evt1548 进94：按 HUD 上楼（evt1731）N50→0；不要被旧客栈提示误导；
- 到 evt1731 触发上楼后按 c3 后续（evt1732/evt1728）；继续夜探流程→evt1557。
