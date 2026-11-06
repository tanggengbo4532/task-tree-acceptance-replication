# R122 战斗金钱倍率 ×10 → ×5（经验 ×2 不变）

- 用户调整：战斗获得金钱倍率由 **×10** 改为 **×5**；经验倍率保持 **×2**。
- 修改：`battle.gd _battle_won()`：
  - `exp_gained *= int(PALState.EXP_SCALE)`（EXP_SCALE=2，未改）；
  - `cash_gained *= 5`（原 ×10；R122-CASH-1）；
  - 胜利结算文字「获得经验 … 获得文钱 …」直接使用同源 `exp_gained/cash_gained`，实际入账 `PALState.cash += cash_gained` 也同源。
- 验收：任意真实战斗胜利后，公告与金钱实际增加均为 ×5（例：敌人 cash=10 → +50）；经验仍 ×2。
