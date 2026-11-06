# R288 ESC 菜单商店落地（用户确认：随时可用/随进度原版装备池/原版价卖半价）

## 实现
1. **ESC 主菜单新增「商店」**（状态/仙术/物品/商店/系统）：
   - 主菜单5项，键盘↑↓/←→循环；Enter进入；布局行高按5项
   - 选中商店：打开现有 `shop.gd`（独立 CanvasLayer，菜单输入让位）
2. **商品池按进度**（原版装备店，未改 Data）：
   | 进度 | store id | 示例 |
   |---|---|---|
   | 早期（未到第4章） | 3 | 木剑/藤甲/草鞋/皮帽 |
   | a31（第4章） | 2 | 短刀/护肩/披风/铁履 |
   | a36（第5章） | 6 | 长剑/大刀/越女剑/铁锁衣 |
   | a41（第6章） | 10 | 九截鞭/玄铁剑/青锋剑/青铜甲 |
   | a44（第6章后段） | 16 | 苗刀/鬼牙刀/天蚕宝衣 |
   | a48（终章） | 17 | 冲天冠/鬼针胄/龙鳞靴 |
3. 买：9格原版货、价格/现金/持有/效果；确认扣钱+入包；钱不足/背包满均拒绝且不扣钱
4. 卖：背包原版可卖物品（含装备）**原价半价**；确认移除+加钱；Tab切买/卖
5. 买后不自动装备；玩家到「物品」→装备→选角色
6. 关闭商店→直接回世界；菜单不残留、player_busy复位（World.on_menu_closed）
7. 不改 Data/存档格式/战斗/任务数值；运行期只改 `cash/inventory/equipment`

## headless 证据（q2109，无窗口，PALState 模板档 cash44128/a36=1）
```
[qa] open=true store=6 buy=true list=[209,211,227,171,169,173,176,239,250] cash=44128
[qb] insufficient cash=0 amt=0 toast=金钱不足 confirming=false
[qc] buy id=209 price=400 cash 44128->43728 amt 0->1 toast=
[qd] sell_list=[84,94,...,209]
[qe] sell id=84 half=6 cash 43728->43734 amt 1->0
[qf] closed=<null> shop_node=<null> queued=true busy=false
```
- store6 与进度a36映射一致；买/卖价格精确；钱不够不扣钱；Esc关闭后菜单释放、busy=false、无脚本错误
- 菜单入口路径：main stack=1 → ↓×3 → Enter → shop open；无残留

## 操作
- ESC → ↓到「商店」→ Enter
- ↑↓选商品/背包物品；Enter → ←→选“是/否”→ Enter确认
- Tab切换 购买/出售；Esc关闭商店回世界
- 购买后打开「物品」→ 装备 → 选角色

## 状态
- 槽1只读AF；槽2=该档副本；未开窗/未实机
- 文件：`menu.gd`、`shop.gd`；UI草图 `round78/shop_menu_ui_mockup.png`
