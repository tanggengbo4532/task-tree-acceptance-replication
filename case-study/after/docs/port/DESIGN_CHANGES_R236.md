# R236 A50 二段战 + 结局（scene253→267/34335）

## 数据
- A49 首战真实脚本33673（evt4441）battle team315 八头蛇；
- A50 二段战真实脚本 **33570（evt4443 mode6 at 480,448）**，同为 battle team315；
- **A50_ENDING_SCENE=267**，scene267 onEnter **34335**（结局演出）；
- 原版 A50 代码占位 `_a50_step` 无 setter，本批用战斗结果 `_last_battle_result` 驱动。

## 实现（R236-A50-1）
1) `_update_a49`：A49 首战 `a49_fight_started>=1` 且 `_last_battle_result=="win"` → `a50_ready=1`，显示「已击败水魔兽→追击」。
   - a49fight 扫描加 `a50_ready<1` 门，防止再次触发首战；
2) scene253 且 `a50_ready>=1 && a50_stage<1`：
   - 提示「按空格追击拜月教主（二段战/结局）」；
   - SPACE → `a50_started=1`、清空 `_last_battle_result`、调用**真实脚本33570/evt4443**（二次 battle team315）；
3) `_update_a50`：`a50_started>=1` 且战斗结束且 `_last_battle_result=="win"` →
   - `a50_stage=1`、`_debug_jump_scene(267)`、`_start_script(34335,0)`（原版结局）；
   - HUD「已击败拜月教主/水魔兽→结局（第7章 G3）」；
4) 不伪造胜负：只有真实 win 才推进；不跳过战斗数值。

## headless（模拟胜利回调，未实际打斗）
- scene253：A49 胜利标记后 `a50_ready=1`，prompt「按空格追击拜月教主」；
- SPACE → `a50_started=1`；
- 模拟 `_last_battle_result="win"` → **scene267 (960,736)，a50_stage=1**，HUD「已击败拜月教主/水魔兽→结局（第7章G3）」；
- boot exit0；槽1/槽2 未写、未开窗。

## 锚点（团队槽2 备份/恢复）
- `round78/slot4_scene253_afterA49win_anchor`：scene253 (336,376)，a49=1/a49_fight_started=1/a50_ready=1（二段战前）
- `round78/slot4_scene267_ending_anchor`：scene267 (960,736)，a50=1（结局）

## tester
- 先实际打赢八头蛇（team315），确认后出现「按空格追击拜月教主」；
- 第二战胜利后应自动进 scene267 结局；
- 真实胜负判定依赖 battle.finished→`_last_battle_result`，不伪造。
