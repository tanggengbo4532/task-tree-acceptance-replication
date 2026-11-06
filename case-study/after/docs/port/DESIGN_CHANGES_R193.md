# R193 scene80 街面白名单（map79）

## 采样
- scene84 evt1572 进 scene80 落点 (416,1456)；
- HUD target **evt1505 (624,1256)**（线索2），N=36；
- 路线37格 bottom ids：**10,36,9,39,41**；全部作为可走集；墙/void native 挡。

## 实现（R193-S80STONE-1）
- 进图 native 路径建 evt1505 ±48 走廊（1714格）；
- 可走=id集或走廊且native非墙/void；非法落点 ground rescue；
- HUD/N 同源；N=0 evt1505；未改地图（before=after）。

## headless
- 落点 (416,1456)：HUD target evt1505 **N=36**，场 has=true；
- 静态沿场 **36步** 到 (592,1256)，**N=0、bad=0**；
- boot exit0；槽1/槽2 未写、未开窗。

## tester
- scene84 evt1572 进80，HUD N36→0→evt1505（线索2）→后续 evt1501→scene83；
- 下一批 scene83（evt1557 线索1）+场景78白名单。
