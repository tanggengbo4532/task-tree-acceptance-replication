# R190 scene79 扬州城石街面白名单（map75）

## 采样
- 团队槽2 scene78 → 从 evt1487 进 scene79 落点 (416,1056)，HUD target **evt1497 (1104,1320) N=84**；
- 逐格采样 85 格，bottom ids：**28(30),43(22),46(18),57(4),62/48/54/85/87(各2),63(1)**；
- 可走集：**{28,43,46,48,54,57,62,63,85,87}**；草/void/墙不在集内。

## 实现（R190-S79STONE-1）
- scene79 进图 native 路径建 evt1497 ±48 走廊；
- 可走 = id 集或走廊且 native 非墙/void；
- 非法落点 ground rescue 到最近走廊格；
- HUD/N 同源，N=0 evt1497；未改地图（before=after）。

## headless
- 落点 (416,1056)：HUD target evt1497 **N=84**，场 has=true；
- 静态沿场 **84步** 到 (1088,1312)，**N=0、bad=0**；
- boot exit0；槽1/槽2 未写、未开窗。

## tester
- 从 scene78 evt1487 进79，HUD N84→0→evt1497→SPACE→scene81；
- 石街面可走，草/void/墙不可走；下一批 scene81 及后续第4章。
