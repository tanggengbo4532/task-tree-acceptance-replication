# R157 GameOver 读档后重进战斗：状态机彻底重置（防指令阶段卡死）

## 现场
- HEAD b2652ad；用户槽1 scene71：14 步触发固定遭遇（苗枪卒HP1800）→ 战败 → GameOver 读档回 N=196 →
  重走 14 步同一队 → 第 2 场指令阶段卡死（李已选天剑后，赵每按 SPACE 追加一条“指令:攻击”，不推进/不换人）。
- 疑点：读档重进时旧战斗节点/状态机残留，输入落到旧实例或旧状态（队列/目标/选中/等待标志）。

## 修复（R157-BATTLERESET-1）
1) **battle.gd `_begin()` 开场重置全部战斗瞬态**：
   `phase=0、turn_no=0、result=""、_action_queue.clear()、_cur_action=0、_waiting_key=false、
    _pending_key=K_CANCEL、_auto_attack=false、_msg_hold=false、_terminated=false、_hiding_time=0、_last_action.clear()`。
2) **world.request_battle()**：创建新战斗前先 `queue_free()` 旧 `_mode_node` 并清 `_mode_node/_real_battle_active/player_busy/_dialog_tail`，
   防两个战斗实例叠加、输入双消费。
3) **world.request_load_game()**（0x004E GameOver/剧情读档）同样先释放旧战斗节点并复位战斗标记。
4) **world `_unhandled_input`**：`_real_battle_active` 或 `_mode_node != null` 时世界层直接 return，
   避免旧世界交互/引导兜底与战斗输入互相消费。
5) R151 的 c3 到点 SPACE 兜底增加 `not _real_battle_active and _mode_node == null` 门禁。

## headless 验证（槽1只读）
- scene71：触发 evt1385/team33 战斗 → 选择指令正常（李/赵/林依次，队列 6，进入行动阶段）；
- 模拟战败 `on_battle_finished("lose")` → GameOver 读档完成：旧战斗节点消失（mode=null, realbattle=false）；
- 同点再触发同一遭遇 → 新战斗实例正常进入第 1 回合选择，SPACE 可依次选完 3 人并进入行动阶段；
- 未再出现指令阶段重复追加/不推进（headless 模拟）。
- boot exit0；槽1未写；未开窗。

## tester4 复测
1. 新 hash 载入 scene71，走 14 步触发固定遭遇；
2. 故意战败 → GameOver 读档 → 重走同一队；
3. 第 2 场指令阶段：李/赵/林应能正常选择、SPACE 推进、换人、进入行动，不再反复“指令:攻击”；
4. 顺带复测 A：胜利后怪物 vanish、正常走一段遇敌频率下降；
5. B4：连胜两场后，下一场第一回合 Ctrl 仍可复用上一场最后操作。
- 固定怪 HP1800 难度按原版/数据保留不改；tester 可逃跑验证 vanish。
