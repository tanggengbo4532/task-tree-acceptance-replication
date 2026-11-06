# R234 A49 最终战入口（scene255→253）+ 数据核对

## 原版数据
- `A49_BATTLE_SCENE=253`，scene253 onEnter **33561**；
- 脚本33561：设事件4442/4441，`0x4a 18` 战场、`0x45 45` 音乐、**`0x7 battle team=315`**；
- **team315 = object547 → enemy150「八头蛇」health=7800, exp=3050, level=40, atk=20, def=0**（原版 Data.mkf）；
- 结局常量：`A50_FINAL_SCRIPT=33570`、`A50_ENDING_SCENE=267`、`A50_ENDING_SCRIPT=34335`（scene267 onEnter 34335）。

## 实现（R234-A49A50-1 入口部分）
1) scene255（a48_stage>=1）新增 SPACE 交互：
   - 提示 **「按空格决战（拜月教主/水魔兽）」**；
   - SPACE → `a49_started=1`、`loaded_from_save=false`、真实 `load_scene(253)`，由原版 onEnter 33561 播最终战；
2) `load_scene(253)` 且 a48>=1 → **a49_stage=1**；
3) HUD 引导列表加253。

## headless
- scene255：prompt「按空格决战」→ SPACE → **scene253 (336,376)，a49_stage=1**；
- **注意**：headless 未自动进入战斗（`in_battle=false, vm=false, dlg=false`；事件4441:0/4442:0/4443:1），脚本 onEnter 33561 可能被条件/状态跳过；需要下一步修 A49 battle 触发（或按原版 event4442 状态开启）；
- 当前不伪造战斗、不跳过；tester 若同样看不到战斗，按此卡点上报。
- boot exit0；槽1/槽2 未写、未开窗。

## 锚点（团队槽2 备份/恢复）
- `round78/slot4_scene255_palace_anchor`：scene255 (1680,1720)，a48=1（决战前）
- `round78/slot4_scene253_finalbattle_anchor`：scene253 (336,376)，a49=1（决战地）

## 待办
- 修 scene253 onEnter33561 未触发 battle team315 的原因（事件4442/4441 条件/脚本分支）；
- 再接 A50 二段战33570→结局34335（scene267）。
