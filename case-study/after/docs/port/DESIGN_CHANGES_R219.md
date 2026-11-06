# R219 修正 R218 错误：真实太守事件 evt1608/1609；scene100 实为居民

## 发现（原版数据）
- R218 误把 scene100 evt1797 当太守；实际脚本15076 文本：
  - 5139「居民：」、5140「为什么随便闯进我家」、5141「居民：」、5142「不要乱来喔！还不赶快出去。」
  - **scene100 是居民住宅，没有太守**；
- 真正的太守事件在 **scene85**：
  - evt1608 (704,464) mode2 脚本14180；
  - evt1609 (672,448) mode2 脚本14191；
  - 初始 state0，由原版 **scene83 evt1562 脚本13339** 设为 state2（本移植未播该段，事件一直未开）；
  - 脚本引用的消息为 4832+「太守：」段。
- 先前的回环：a34_done 后 c3 scene85 指 evt1581→scene100，而 scene100 exit 回85 又指 evt1581 → 循环。

## 修复（R219-TAISHOU-1）
1) c3 scene85 `a34_done>=1` 且 `a35_talked<1`：
   - 按原版状态开启 **evt1608/1609 state=2**；
   - target **evt1608「面见太守（女飞贼案后续）」**；
2) 新增 scene85 太守交互：
   - 目标1608/1609、140内、N=0 →「按空格面见太守」；
   - SPACE → `run_script_entry_sync(14180/14191)` 显示**真实太守对白**；写 `a35_talked=1/a35_stage=1`，事件state0 防重复；
3) a35_talked 后 c3 scene85 → **evt1574「返回街道（A34 已完成）」**，不再回 scene100；
4) scene100 保留为可选居民住宅：
   - c3 文案「与居民对话（可选）」；exit「离开民居」；不再作为主线节点。

## headless（团队槽2 + a34_case/a34_done=1）
- scene85 (544,304)：HUD target **evt1608 N=46**；
- 实走 **46步→N=0**（pos 672,464），prompt「按空格面见太守」；
- SPACE → **dlg=true，真实太守对白**；`a35_talked=1`；
- 对话关闭后 HUD → **evt1574 N=48「返回街道（A34 已完成）」**，无回环；
- boot exit0；槽1/槽2 未写、未开窗。

## 锚点（更新）
- `slot4_scene85_a34done_anchor`（scene85 544,304）期望 HUD 改为 **evt1608 N=46（面见太守）**；
- `slot4_scene100_taishou_anchor` 更名为实际居民住宅测试（非主线）：HUD evt1797 与居民对话可选。
