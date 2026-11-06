# R201 A34 锚点档 + 旧档 scene83/85 ping-pong 修复

## 1) A34 锚点档（不写游戏槽）
从团队槽2 A581BFD7 复制、只改 scene/viewport/vars，队伍数值/敌人不变：
- **scene90 后院 evt1650 提示前**
  - `round78/slot4_scene90_backyard_evt1650_anchor.sav`
  - `...json`
  - scene90 **(1040,1112)**；vars 重置 `a33_backyard=0/a33_backyard_done=0/a34_stage=0`（保留 a33_stage=1）
  - 期望 HUD：target **evt1650 N=0**「按空格继续查案（衙门后院）」
  - 流程：SPACE→4条婢女对白→翻页→HUD target evt1661 N0→SPACE→scene91；
- **scene91 N17**
  - `round78/slot4_scene91_n17_evt1664_anchor.sav`
  - `...json`
  - scene91 **(1024,1112)**；vars `a33_backyard=1/a33_backyard_done=1/a34_stage=1`
  - 期望 HUD：target **evt1664 N=17**「前往查案（女飞贼案后续）」

## 2) 旧档 A581BFD7 ping-pong 修复
- 旧档只有 `a33_backyard=1`，没有新的 `a33_backyard_done`；
- R199 scene83 只看 done → 回 evt1546→85；scene85 又 evt1574→83 → N2↔N2 ping-pong；
- 修复（R201-NOPING-1）：scene83 条件改为
  `a33_backyard_done>=1 OR a33_backyard>=1` → target **evt1557**「回街道继续查案（女飞贼案后续）」；
- headless 旧档 A581BFD7 scene83 (1712,408)：HUD target evt1557 **N=110**，不再指 evt1546→85。

## 验证
- boot exit0；槽1/槽2 未写、未开窗；锚点文件仅状态/坐标。

## tester
1. 读 scene90 锚点：SPACE 对白→翻页→evt1661 N0→SPACE→scene91；
2. 读 scene91 锚点：HUD evt1664 N17→走到 N0→SPACE→scene93；
3. 旧 A581 档：scene83 HUD 应指 evt1557，不再 A↔B。
