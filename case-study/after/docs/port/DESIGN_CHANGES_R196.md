# R196 scene83 街面白名单（当前夜间后“返回衙门”段）

## 采样
- 团队槽2 scene83 (704,568)，HUD target **evt1546 (1744,424)**「返回衙门（继续查案）」N=113；
- 沿路线 114 格采样 ids：36/9/49/47/131/46/111/37/10/243/12/11/299/247/245；
- 全部作为可走集；墙/void native 挡。

## 实现（R196-S83STONE-1）
- 进图 native 路径建 evt1546 ±48 走廊（839格）；
- 可走=id集或走廊且native非墙/void；非法落点 ground rescue；
- HUD/N 同源，N=0 evt1546；未改地图（before=after）。

## headless
- 落点 (704,568)：HUD N113，场 has=true；
- 静态沿场 **113步 → N=0、bad=0** 到 (1712,424)；
- boot exit0；槽1/槽2 未写、未开窗。

## tester
- scene83 夜间链回衙门段：N113→0→evt1546（→scene85）；
- 下一批 scene94 夜间区域、scene98、85/87/90/94。
