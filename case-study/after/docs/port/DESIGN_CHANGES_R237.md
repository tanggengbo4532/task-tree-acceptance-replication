# R237 最终战满状态锚点 + 难度结论 + A50 线路验证

## 1) 满状态锚点（只改队伍 HP/MP，不改敌人/Data）
- 文件：`round78/slot4_scene253_fullhp_anchor.sav/.json`
- scene253 **(336,376)**；vars a36..a49=1（a49_stage=1，未开战）
- 队伍角色 HP/MP 已写满（角色0-5）：
  - 实测：hp=[290,288,339,966,564,999] = maxhp；mp=[230,286,188,920,480,820] = maxmp；
  - 活跃队伍：Lv12/9/12，HP 290/288/339 满；
- 锚点通过**临时写团队槽2→读取验证→恢复备份**生成，槽2 已恢复原 sha `48B31583…`；
- 不改敌人 HP/属性、不改升级经验。

## 2) 难度结论（如实记录，不改数值）
- 队伍：活跃角色 Lv12/9/12，attack_strength 87/36/79；
- 最终战 team315 → enemy150「八头蛇」：HP **7800**、Lv**40**、atk20、physical_resistance=3；
- tester 实测伤害 1-2/击、3-5 回合 lose：**等级/练度不足**，不是数据损坏；
- 结论：**用户低等级流程下正常打无法赢**；需要练级/补给（原版玩家可练级），本移植**不修改 Data 数值、不伪造胜利**。
- 满状态锚点只解决“剧情残血”问题，不解决等级差距。

## 3) A50 线路验证
- `slot4_scene253_afterA49win_anchor`（a49=1/a49_fight_started=1/a50_ready=1）：
  - 载入后实测 prompt **「按空格追击拜月教主（二段战/结局）」**，HUD 一致；
- `slot4_scene267_ending_anchor`（scene267 a50=1）：
  - 载入 scene267 可正常显示场景（HUD 空，因读档会跳过 onEnter）；
  - 用 `loaded_from_save=false` 加载 scene267 时 onEnter **34335 真实结局脚本**已执行：**dlg=true、player_busy=true、vm active**；
- 实际流程：二段战真实 win → `_debug_jump_scene(267)` + `_start_script(34335,0)`，结局会播。

## 4) 交付
- 代码 HEAD：本次提交（R237，含 R236 的 a49fight 门防止重复开战）；
- 槽1只读、团队槽2备份/恢复（原 sha 48B31583…）、未开窗；
- tester：
  - 公平战斗验：用 `slot4_scene253_fullhp_anchor`（满血但等级仍低，预期仍难）；
  - 线路验：用 `slot4_scene253_afterA49win_anchor` → 二段战→结局；
  - 结局演出可用 `slot4_scene267_ending_anchor` 看场景，但读档不播 onEnter 是引擎设定，实际通关会播。
