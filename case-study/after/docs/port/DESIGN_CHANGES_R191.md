# R191 scene81 扬州街道白名单（map77）

## 采样
- 团队槽2 scene79 → evt1497 进 scene81 落点 (288,448)；
- HUD target **evt1507 (1728,1136)**，N=370；
- 沿 HUD 路线 371 格采样 bottom ids（39种，主用）：
  441/29/98/24/23/21/26/13/95/116/59/273/94/122/275/157/327/278/28/266/100/282/2/284/102/306…；
- 全部作为可走集 `S81_GROUND_IDS`；墙/void 仍由 native blocked 挡。

## 实现（R191-S81STONE-1）
- 进图 native 路径建 evt1507 ±48 走廊（1396格）；
- 可走 = id 集或走廊且 native 非墙/void；
- 非法落点 ground rescue 到最近走廊格；
- HUD/N 同源；N=0 evt1507；未改地图（before=after）。

## headless
- 落点 (288,448)：HUD target evt1507 **N=370**，场 has=true；
- 静态沿场 **370步** 到 (1696,1136)，**N=0、bad=0**；
- boot exit0；槽1/槽2 未写、未开窗。

## tester
- 从 scene79 evt1497 进81，HUD N370→0→evt1507→SPACE→scene84；
- 街面可走、墙/void不可走；下一批 84/80/83/85/87/90/94/98。
