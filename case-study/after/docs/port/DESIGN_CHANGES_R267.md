# R267 scene187 HUD 绕行侧门 + scene188/185 锚点

## 1) scene187 HUD 路径避开真实侧门
- 原现象：HUD 目标 evt3135(224,1376)→188，但自动路径进 evt3134(1168,1080) 触发圈→179（后又 hit 3132→180）
- 修复（R267）：`_s4g_avoid_events`，在 scene187 目标 evt3135 时把 **3131/3132/3133/3134** 真实侧门触发圈加入 HUD BFS 障碍；门本身保留、可手动触发，只影响 HUD 寻路
- headless q2043：scene187 (1808,1160) HUD **N180** → 绕开全部侧门 → **scene188 (1504,976) PASS**
- 新卡点：scene188 落点 HUD target evt3152 N0「等待/绕行中」——HUD BFS 在该落点找不到 evt3152 可达环；需后续修 188 落点/寻路或 tester 实走

## 2) 锚点
- `round78/slot2_scene188_forest_gate_anchor.sav/.json`
  - SHA256(sav) **0175C54B6D14EDB080A4A92F6A7C889F573A7D76E2D6CED693A4CE2927D6ACC9**
  - scene188 (1504,976)，a42=1/a43=0，李290/林339 maxidx1
- `round78/slot2_scene185_forest_anchor.sav/.json`
  - SHA256(sav) **0A8D734A6327ACB228C8D679B759ABF3D93AAE6F81C1F102C2747E279D0254C1**
  - scene185 (736,1152)，a42=1/a43=1/a44=0，李290/林339 maxidx1
  - HUD「按空格深入神木林（凤凰蛋/树洞）」→ 真实脚本26192 team203
- README：`slot2_scene188_185_forest_anchor_README.md`
- 用户槽1未写；槽2恢复用户最新档14B5CFBD

## 状态/下一步
- HEAD 提交后见回执；boot exit0，无 SCRIPT ERROR
- 下一步：修 scene188→evt3152→185 的 HUD/落点寻路；或从185锚点直接验 A44（26192/team203）→189→207→206→247→255→253
- 不 auto-win/不传送/不空格跳场景
