# R214 scene83 线索后无路可达 evt1548 → 红衣路人处真实门脚本进客栈

## 卡点
- tester 槽2 `052DDAC0`：scene83 (448,1232)，clue1 已得后 c3 指 evt1548(768,512)「前往客栈（夜间前置）」；
- evt1548 在当前区域 **native 不可达**（`_s4g_build` has=false，raw dist 无起点）；
- 当前区域 BFS 可达事件只有 evt1502-1506（路人）与 evt1566-1569（红衣路人 idle），**没有任何通向外场景的门** → 无法步行到 evt1548。

## 修复（R214-S83INN-1，按用户“必要时从 NPC 处直接进入剧情”）
1) c3 scene83：clue1 已得且 `a32_night_started<1` → 指近旁红衣路人 **evt1569**「向红衣路人询问客栈方向」；
2) 新增红衣路人第二段交互：目标 evt1569、在 evt1566-1569 任一120内、N=0 →
   提示「按空格前往客栈（夜间前置·第 4 章）」；
3) SPACE → 写 `a32_night_started=1`，调用 **真实 evt1548 门脚本 `_start_script(12982,1548)`** → scene94 客栈 (816,904)；
4) 不伪造路、不开放草/void；只是把真实门脚本从可达 NPC 处触发。

## headless（tester 卡点档 052DDAC0 / 团队槽2）
- 读档 scene83：HUD「按空格前往客栈（夜间前置）」interact=1569，prompt 同源；
- SPACE → **scene94 (816,904)**，`a32_night_started=1`；
- HUD 切 **「客栈夜间剧情（前置）」target evt1741 (784,856) N=3**；
- boot exit0；槽1/槽2 未写、未开窗。

## tester
- scene83 红衣路人旁按 SPACE → 直接进入 scene94 客栈；之后按 HUD N3→0 → evt1741 继续夜链；
- 若 scene94 后续卡住，给坐标（之前 R195 夜链锚点可用）。
