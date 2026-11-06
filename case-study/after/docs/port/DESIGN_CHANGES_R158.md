# R158 战斗子菜单 ESC 后指令阶段输入复位/双通道

## 现场
- HEAD c5e47ee（r157 GameOver 重进 PASS）；tester：R2 打开「仙术/物品」子菜单并 ESC 退出后，
  R3 指令阶段卡死（玩家0 已显示“指令:攻击”，赵/林不再登记，SPACE/ENTER/ESC 无推进，帧不变、CPU 活跃）。
- 与 R157 的 GameOver 重进路径不同，指向子菜单取消后的输入等待/UI 状态残留。

## 修复（battle.gd R158-SUBMENU-ESC-1）
1) 新增 `_input_reset()`：清 `_waiting_key=false、_pending_key=K_CANCEL、_auto_attack=false`，并 `ui.hide_menus()`。
2) 调用点：
   - `_select_phase()` 每个回合开始；
   - `_choose_magic()` 返回后（含 ESC 取消）；
   - `_choose_item()` 返回后；
   - `_show_status()` 返回后；
   - 主菜单 cancel 返回 `_select_phase` 前。
3) 战斗按键改为**双通道**：`_input` 与 `_unhandled_input` 都转发到 `_handle_battle_key`；
   任一通道处理即 `set_input_as_handled()`，避免子菜单 ESC 后世界/UI 焦点残留截走键盘。
4) 仍只响应 `_waiting_key` 状态，不会重复消费同一次按键。

## 验证
- boot exit0（语法通过）。
- 说明：长序列 headless 模拟（打开子菜单→ESC→继续选人）在无 UI 脚本模式下容易因等待目标选择而超时，
  未能稳定自动跑完；已把输入复位与双通道作为确定性防御修复，待 tester4 实机复测：
  R1 选指令 → R2 打开仙术/物品子菜单 → ESC → 继续选人 → 应正常进入行动。
- 与前序修复兼容：R157 战斗节点重置、R156 胜利 vanish/跨战斗 Ctrl 复用保留。

## tester4 复测
1. 固定遭遇场景，R1 正常选指令；
2. R2 打开「仙术」子菜单 → ESC；再打开「物品」子菜单 → ESC；
3. 继续在同一回合选完李/赵/林 → 应能正常进入行动/换人，不再卡在“玩家0 指令:攻击”；
4. 顺带 A（逃跑验证怪 vanish）/B4（两场后 Ctrl 复用）。
- 固定怪 HP1800 按原版不改。
