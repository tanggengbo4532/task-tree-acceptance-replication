# R199 scene85↔scene90 A↔B 循环修复

## 根因
- A33 女飞贼战后：
  - scene85 c3 `_a33_done_state()` → target evt1579 (1152,432) → scene90 后院；
  - scene90 后院剧情后（R198）→ target evt1649 出口 → scene85；
  - 两边互指，形成 A↔B 无限循环，未回街道主线。
- evt1610 (528,280) 是 A34 后续真实门（脚本13409→scene93），但当时 state=0 未开启，scene85 无法直接指它。

## 修复（R199-A33NOLOOP-1）
1) scene85 `_a33_done_state()` 分支：
   - 若 **evt1610 state>0** → HUD「继续查案（女飞贼案后续）」target evt1610；
   - 否则**不再回 evt1579**，改指真实街道门 **evt1574→scene83**「返回街道（继续查案）」；
2) `_start_script` scene90 evt1649（脚本13099）写 `a33_backyard_done=1`；
3) scene83：若 `a33_backyard_done>=1` → HUD「回街道继续查案（女飞贼案后续）」target **evt1557**（不再回 evt1546→85 循环）；
4) 未改剧情/地图；N 同源。

## headless（tester 循环点槽2）
- scene85 (1088,464)：HUD「返回街道（继续查案）」target evt1574 **N=90**（不再指 evt1579→90）；
- 到 scene83 后（a33_backyard_done=1）：HUD「回街道继续查案」target **evt1557 N=19**；
- boot exit0；槽1/槽2 未写、未开窗。

## tester
- 从循环点：跟随 evt1574→scene83，再按 HUD 到 evt1557（N19）；
- 注：evt1557 的 clue1 变量已为1，走到点是回街道；后续 A34 真实链（evt1610 state0/evt1661→scene91）数据需下一批继续接。
- 下一批 scene94/98 + 85/87 白名单。
