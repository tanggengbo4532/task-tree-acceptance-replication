# R238 收尾交付报告（第4章收尾 → 第5/6/7章 → 最终战/结局）

## 最终构建
- 代码/文档提交：R238（本文件提交后的 HEAD；上一提交 `0d2161825995439fdd184a32082407c0fd21f73c` = R237）。
- boot：`--headless --path proj --quit-after 3` exit0，无 SCRIPT ERROR。
- 槽1 只读、团队槽2 测试后备份/恢复；未开窗、插件未动。

## 已通的章节节点（真实数据/门优先）
- 第4章收尾：A33/A34 完成 → 复命 → 街坊（R217/R219/R220）。
- 第5章：scene85 真实蜀山入口脚本21692→scene141（R223）；scene141 剑圣脚本23623（R226）；scene154 onEnter24148→153 塔内（R227）；scene153 深入→scene155（A39脚本23694）→scene156 塔顶（onEnter22445）→scene178 苗疆（onEnter27955，R227/R228）。
- 第6章：A42/A43 圣姑→真实门链 175→177→187→188→185 神木林（R229）；A44 凤凰蛋真实脚本26192（team203 凤凰 HP3000）→scene189 树洞→scene207 火麒麟洞（R230）；A45 守卫/女兵对白 + scene207 evt3461→scene206 白苗族大厅（R231）；A46 族长剧情 evt3442/脚本29504；A47 南诏 scene206→247（onEnter32455，R232）；A48 黑苗王宫 scene247 evt4365→255（R233）。
- 第7章：A49 最终战 scene255→253（R234 入口）；R235 用真实 evt4441 触发脚本33673，battle team315 八头蛇 HP7800（in_battle=true）；A50 二段战真实33570/evt4443→scene267/onEnter34335 结局（R236，线路已用 win 回调验证）。

## R234-R237 变更清单
- R234（A49A50-1）：scene255 SPACE 决战→真实 load scene253；load253 置 a49_stage；记录 battle 未自动触发。
- R235（A49BATTLE-1）：修 battle 触发根因（evt4441 state0/mode7），scene253 调真实脚本33673；headless in_battle=true。
- R236（A50-1）：a49 胜利读 `_last_battle_result=="win"`→a50_ready；scene253 二段战调用真实33570/evt4443；二段 win→`_debug_jump_scene(267)`+`_start_script(34335)`；a49fight 加 a50_ready 门。
- R237（VERIFY-1）：满 HP/MP 锚点、难度结论、afterA49win/ending 验证。

## A49/A50 线路与难度结论
- 线路：scene255→scene253（A49 首战 team315 八头蛇）→ 胜利后 scene253 prompt「追击」→ 真实33570 二段战 → 胜利 → scene267 结局 onEnter34335。
- 难度：活跃队伍 Lv12/9/12、atk 87/36/79；八头蛇 HP7800/Lv40/physical_resistance3；实测伤害1-2、3-5回合 lose。结论：**当前低等级流程正常打无法获胜；需练级/补给。未改 Data 数值、未伪造胜利。**
- 满状态锚点仅修复剧情残血，不解决等级差距。

## 锚点（团队槽2 方式；`_playtest_regress_dev/round78/`）
- 最终战：`slot4_scene253_finalbattle_anchor`（scene253 336,376，a49=1）
- 满状态：`slot4_scene253_fullhp_anchor`（全队 HP/MP 满，scene253 336,376）
- 二段战前：`slot4_scene253_afterA49win_anchor`（a50_ready=1，prompt「追击」）
- 结局：`slot4_scene267_ending_anchor`（scene267 960,736，a50=1；读档跳过 onEnter，实际通关播34335）
- 其它：scene141/153/155/156/175/178/185/189/206/207/247/255 等各章锚点。

## 未通/阻塞
- 八头蛇最终战：等级不足（难度阻塞，非数据损坏；不改数值）。
- scene267 结局在读档锚点时 HUD 为空（引擎读档跳过 onEnter）；实际二段战胜利流程会播，已用 loaded_from_save=false 验证 dlg=true。
- 部分章节无普通 evt 直达门，按真实脚本/onEnter 场景加载（A41/A45/A47/A49）；已标注，不伪造路面/传送。
- 用户槽5 原档丢失（已上报），不再使用槽3/4/5/9。
- 剩余白名单/次要节点（scene98 等）未覆盖，需后续数据/用户指示。

## 槽位
- 槽1 用户：`2127780653E24E862AD456A5FA029FF561E0C25CA4AA3395ECF95F5C6BEA97BA`（只读）。
- 团队槽2：当前 `4AC20CAA031DE0B2201A9209664A2BBE3D28C539A8E853F229371FEC95C100D7`（tester 新写入；我测试时备份/恢复，原备份 `backup_slot2_preR237.*`）。
- 未写槽1/槽3/4/5/9；未开窗。


## R239 最终确认补充（tester r232）
### 1) 战败自动重开 = 原版 Game Over → 读档
- A49/A50 的 0x0007 操作数均为 `0x7 315 41075 0`：a1（失败分支）=41075；
- 41075 起指令：`0x43 1 1`(BGM) → `0x4F`(画面淡入红色 Game Over) → 对白 → `0x4C/0x3` 循环 → `0x4E`(读取最近存档)；
- VM 注释 R156 明确：41075 是“胜败乃兵家常事…大侠请重新来过”+0x4E 读档失败分支，随机遭遇同用；**不是 battle 重试偏移**。
- 结论：lose→自动回到最近存档（本锚点即决战前）符合原版；tester 看到“重开”是 GameOver 读档，不是重试战斗。
### 2) scene267 后日谈
- 真实 win 流程 `_debug_jump_scene(267)` + `_start_script(34335)`，onEnter 34335 会播结局；已验证 loaded_from_save=false 时 dlg=true、vm active。
- 但 HUD「全剧终·按空格进入后日谈」目前**没有对应交互/事件**：A51 后日谈依赖 `a51_stage/_a51_move_pending`，代码/数据无 setter；读档锚点还会跳过 onEnter。
- 所以 SPACE 不触发是**后日谈未接的已知占位**，不是结局脚本失败；实际 win 能播 34335 结局。
- 未通点：后日谈 scene267→268 等需后续接线。
