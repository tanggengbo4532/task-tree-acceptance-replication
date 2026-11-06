# R218 A34 复命后下一节点：入府见太守（scene85 evt1581→scene100）

## 原版数据
- scene85 evt1581 (608,432) mode5 脚本13179 → **scene100 (20,28,1)**；
- scene100 map94，事件：
  - evt1795 (592,488) → scene85；
  - evt1796 (1184,416) → scene85；
  - **evt1797 (576,304) mode2 脚本15076**（太守对白 5139-5142）；
  - evt1798/1799/1800 其它 NPC；
- evt1583 (1824,384)→scene106 虽存在，但从复命位置 **native 不可达**（BFS 到 evt1583 无路），故不用。
- 结论：A34 复命完成后，可达真实下一节点是 **evt1581→scene100 太守府内 → evt1797 与太守对话**。

## 实现（R218-A34NEXT-2）
1) c3 scene85 `a34_done>=1` → target **evt1581「入府见太守（下一节点）」**；
2) 新增 c3 scene100：
   - `a35_talked<1` → target **evt1797「与太守对话」**；
   - 之后 → evt1795「离开太守府（返回街道）」；
3) scene100 加入 c3 引导场景列表；
4) 新增 scene100 evt1797 SPACE 交互：
   - 目标1797、120内、N=0 →「按空格与太守对话」；
   - SPACE → `run_script_entry_sync(15076)` 显示真实对白，写 `a35_talked=1/a35_stage=1`；
5) 不伪造路，evt1581/evt1797 均真实事件。

## headless
- scene85 复命位置 (544,304)，`a34_case=1/a34_done=1`：
  - HUD target **evt1581 N=44**；
  - 实走 44 步到 (608,448) N=0 → SPACE → **scene100 (544,464)**；
  - HUD target **evt1797 N=24**「与太守对话」；
- boot exit0；槽1/槽2 未写、未开窗。

## tester
- 从 scene85 复命后：HUD 应指 evt1581 N44；走 N0→SPACE→scene100；
- scene100 HUD evt1797 N24；走 N0→SPACE→太守对白；之后 HUD 指 evt1795 离开。
