# R264 六脚蜘蛛脚本战败后剧情修复 + 敌方回合脚本/调色板

## 数据结论（按原 Data.mkf）
- scene139 evt2342 trigger script21692 本身是门脚本；六脚蜘蛛战来自 **team42 脚本战脚本**：
  - 入口 **21805**：`0x0007 a0=42 a1=0 a2=0`（team42；a1/lose=0；a2/win=0，Boss 不可逃）
  - 战后脚本从 21806 继续（场景/对白/剑圣森林过场）
- team42 = `[435, 0xFFFF…]`；obj435 = enemy_id38 六脚蜘蛛，HP **32767**，**script_on_turn_start=41533**
- 敌方回合脚本 41533 是**分块脚本**：
  - 41533 0x0047 音效 → 对白 → **0x0001**（stop/next entry）
  - 41537/41538/… 后续块继续；最终 **41553 `0x0089 0`** → `set_result(0)`=win
  - 旧实现每回合从固定 41533 重跑，0x0001 后不推进 → 永远到不了 0x89；**是“回合不自动推进/卡住”的根因**
- 败后分支：0x0007 a1=0 → VM lose 后 ip+1 继续败后剧情；**不是无败后脚本**
- 过场确实调用 `script_set_palette`，此前 world 未实现，`missing_hooks={"script_set_palette":1}`；本次实现

## 修复
1. **battle.gd 敌方回合脚本跨回合推进**：
   - enemy 增加 `turn_script_entry`；`_run_enemy_turn_script(i)` 每次执行后取 VM `next_entry` 存回；
   - 0x0001 语义按“stop + 设下一入口”逐回合推进；
   - 战前/每回合结束均走该 helper；0x0089 0 可正常 set_result(win)。
2. **world.gd `script_set_palette(pal_num, night)`**：安全应用调色板并继续 VM；missing_hooks 消除。
3. **脚本战 lose 剧情通路**：
   - `on_battle_finished` 若 result=lose 且 VM 仍 active：清 `_last_battle_result`、加安全帧、置 `_a36_scripted_loss`；
   - 不再触发全灭 GameOver；`_update_a36` 在 scene141 到达时 `_restore_party_story_hp_mp()`，恢复李/林满状态和 maxidx=1；
   - 保留“无脚本随机战败才 GameOver”的规则。
4. 移除临时敌方脚本 debug print。

## headless 验证（anchor slot2_scene139_spider_anchor）
- 进战队伍：李290/290、林339/339；敌方六脚蜘蛛 HP32767；team42 flee_disabled=true
- 自动战斗真实回合到 **lose（7回合）**（不 auto-win/不降难度）
- 败后 VM 继续：`entry=21692 ip=21812` → 蜘蛛精对白/剑圣森林过场 → `script_set_palette` 调用无 missing
- 最终日志：
  - `[party] R261-PARTY5-1 restore story party=李逍遥+林月如 scene=141`
  - `[post] scene=141 pos=(1344,1328) a36=1 vm_active=true entry=21898`
  - `[qe] FINAL scene=141 pos=(1344,1328) a36=1 maxidx=1 hp0=290 hp2=339 gameover=false missing={}`
- 自动战斗 PASS（此前 R263 q2026）：选自动后第2..10回合自动攻击、无物品、无重复自动菜单。

## 状态
- boot exit0，无 SCRIPT ERROR
- 槽1 `14B5CFBD…` 只读未变；槽2已恢复用户最新档14B5CFBD；锚点文件不变
- 未开窗/未写槽1/3/4/5/9

## 结论
- 六脚蜘蛛是**脚本战**，败后剧情被数据支持；无需打赢、不降难度、不 auto-win。
- 敌回合 0x89 0 已实现可到达；本战因 HP32767 在到达 0x89 前正常 lose，随后败后剧情到 scene141 a36=1/maxidx正常。
