# R213 scene83 红衣路人线索接通（用户现场 E495CDE1 / 卡点797920CD）

## 现场
- 用户槽1 `E495CDE1...`：scene83 **(448,1232)**；
- HUD：target evt1557(992,784)「向路人打探女飞贼线索｜等待/绕行」，`_s83_path_cells=0`；
- 附近真实事件：**evt1566-1569 (432,1192 / 416,1184 / 448,1200)**，mode0 state2 auto35633（红衣路人 idle 组）；
- c3 却指远处 evt1557，且 evt1557 与当前点无 native 路可达 → 等待/绕行、SPACE 无反应。

## 修复（R213-S83NPC-1）
1) scene83 clue1 阶段 c3 改指**近旁红衣路人 evt1569 (448,1200)**「向红衣路人打探女飞贼线索」；
2) 新增 scene83 红衣路人 SPACE 交互：
   - 目标 evt1569、玩家在 evt1566-1569 任一 120 半径内、N=0；
   - 提示「按空格向红衣路人打探女飞贼线索（第 4 章）」；
3) SPACE → `run_script_entry_sync(15149,1557)` 取真实线索对白，逐条显示（DialogBox），写 `a32_clue1=1 / a32_stage=1`；
4) 随后重置 scene83 白名单并 `call_deferred(_a30_s83_prepare)`，按新 c3 目标重建走廊。

## headless（用户槽1 E495CDE1 scene83 448,1232）
- 读档：HUD **「按空格向红衣路人打探女飞贼线索」**，interact=1569，prompt 同源（不再空等待）；
- SPACE → **dialog active=true，线索对白显示**；`a32_clue1=1`；
- ENTER 推进后 HUD 切 **「前往客栈（夜间前置）」target evt1548(768,512)**；
- boot exit0；槽1/槽2 未写、未开窗。

## 已知后续
- 切到 evt1548 后 HUD 仍“等待/绕行”：从 (448,1232) 到 evt1548(768,512) 的 native 路不可达（`_s83_path_cells=0`）；
- 需确认：evt1548 是否真实门/是否需要从别的入口进；请 tester/用户给当前 HUD 截图或允许改指真实可达门。
