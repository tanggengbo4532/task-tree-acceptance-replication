# R268 scene188 落点/HUD 卡点调查 + 门侧锚点

## 现状
- R267: scene187 HUD 避开侧门 → **187→188 PASS**
- scene188 落点 (1504,976)：HUD target evt3152(352,1264)→185，但显示「等待/绕行 N0」，`_s4g` 距离=-1（不可达）
- 探测：
  - scene188 事件范围3150..3155
  - doors：evt3151(1552,1000)→187、evt3152(352,1264)→185
  - evt3155(1328,1000) mode4 trigger script26593：0x0040/0x0014/0x0024(3153,36518)/0x0049(3153=1,3154=0)；evt3153/3154 是桥接/状态事件
  - 从落点(1504,976)到 evt3155(1328,1000) 也不可达（q2048 `_s4g` dist=-1）；3153/3154 当前 state=2
- 结论：不是单纯 HUD 目标选错，是 **scene188 落点与门/桥接事件所在连通分量不一致**；需进一步查 map/事件3153/3154桥接状态与可走集（不能删门/传送）

## 临时 tester 锚点
- `round78/slot2_scene188_door_anchor.sav/.json`
  - sav SHA256 **EAF98FB18D1C7CE2558FFBE852CF6BA7BB9DCE9F7AB90D442074C4953B3D5EBA**
  - scene188 (368,1256)，evt3152旁；李290/林339 maxidx1
  - 载入后 N1：按 ↓ 一步再 SPACE 即 evt3152→185
- `slot2_scene185_forest_anchor.sav/.json`（已提交，scene185 HUD A44）
- README `slot2_scene188_door_anchor_README.md`
- 不写用户槽1；槽2恢复用户最新档

## 下一步
1. 查 scene188 map 可走性/事件3153/3154状态对桥接格的影响，修 187 落点 → evt3155 → evt3152 的真实通路（不传送）
2. 或确认原版是否需触发 evt3155 才显出桥；若是则给 HUD 先导 evt3155
3. 185 A44（script26192 team203）继续 headless/tester
