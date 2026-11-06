# R205 scene82 出口→scene89 修复 + 真 after_case 锚点

## 复现结论
- tester 槽2 C4366F28（scene82 992,1328）：脚本13207 本身没有卡死；
- headless 在 evt1666 N0 按 SPACE → **scene89 (448,1568)**，player_busy/dialog 均正常结束；
- 真正问题是 **c3 没有 scene89 目标**：切到 scene89 后 HUD 空/残留「离开太守府」，看起来像卡住；
- 另外 after_case 锚点原 .sav 复制自团队槽2，位置 (992,1328) 离出口 N>0，且 vars 依赖 JSON；给 tester 造成“拿错/非 after case”。

## 实现（R205-S89EXIT-1）
1) 新增 c3 **scene89 → evt1647 (416,1840) 脚本13091 → scene85**「返回衙门（女飞贼案后续）」；
2) 89 加入 c3 引导场景列表；
3) c3 scene82 出口条件增加 **位置判定**：队伍距 evt1666<160 时也直接指 evt1666（`.sav-only` 锚点可用）；
4) 未改剧情/地图/队伍。

## 真 after_case 锚点（不写游戏槽，sha 与 tester 槽2 不同）
- `round78/slot4_scene82_after_case_anchor.sav`（sha **e058a61b…**）
- `...json`
- scene82 **(1088,1240)**，已到出口触发点；不依赖 JSON 也可识别；
- 期望 HUD：target **evt1666 N=0**「离开太守府」；
- 按 SPACE → **scene89 (448,1568)**，HUD target **evt1647 N=64**「返回衙门」。

## headless（tester 槽2 同位置复现）
- scene82 (1088,1240)：HUD evt1666 N=0；
- SPACE → scene89 (448,1568)，HUD evt1647 N=64；
- boot exit0；槽1/槽2 未写、未开窗。

## tester
- 用 after_case 锚点：HUD evt1666 N0→SPACE→scene89（evt1647 N64）；
- 若仍遇 HUD 空，请给坐标/是否在 scene89；
- 下一批：scene82/93 白名单 + scene89/94/98/85/87。
