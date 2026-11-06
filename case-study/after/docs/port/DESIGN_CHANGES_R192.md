# R192 scene84 街面白名单（map78）

## 采样
- 团队槽2 scene84 (224,848)，HUD target **evt1572 (1760,720)** N=290；
- 沿 HUD 291 格采样 bottom ids（28种）：
  346/133/89/155/115/114/226/93/307/121/88/160/282/153/308/352/331/316/328/127/274/269/161/325/270/272/228；
- 全部作为可走集；墙/void native 挡。

## 实现（R192-S84STONE-1）
- 进图 native 路径建 evt1572 ±48 走廊（2079格）；
- 可走=id集或走廊且native非墙/void；非法落点 ground rescue；N同源；
- 未改地图（before=after）。

## headless
- 落点 (224,848)：HUD target evt1572 **N=290**，场 has=true；
- 静态沿场 **290步** 到 (1728,720)，**N=0、bad=0**；
- boot exit0；槽1/槽2 未写、未开窗。

## tester
- scene84 HUD N290→0→evt1572→SPACE→scene80；
- 下一批 scene80/83/85/87/90/94/98。
