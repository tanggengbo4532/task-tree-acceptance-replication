# R200 A34 真实链接通：evt1661 明确交互 → scene91 → evt1664 → scene93

## 数据确认
- scene90 evt1650 对话后同位置有 **evt1661 (1056,1104) mode4 state1 脚本14632**：
  脚本内 0x25/0x59 → **scene91**；这是 A34 入口。
- scene91 有 **evt1664 (960,1008) mode5 脚本14647 → scene93 (16,85,0)**；evt1663→85 作为返回兼容。
- 之前只靠 mode4 自动触碰不触发（实测玩家到环内也不切换），需要显式 SPACE 触发。

## 实现（R200-A34-1）
1) R198 后院对话完成后 c3 scene90 由 evt1649 改指 **evt1661**「继续查案（女飞贼案后续）」；
2) 新增 scene90 evt1661 显式交互：
   - 条件：target=1661、a33_backyard≥1、距离<120、N=0；
   - 提示「按空格继续查案（前往 scene91）」；
   - kind `a34start`：写 `a34_stage=1`，调用真实 `_start_script(14632,1661)`；
3) scene91 c3 → **evt1664**「前往查案（女飞贼案后续）」；
4) scene93 c3 入口先指 **evt1691 (848,1528)**「继续查案（女飞贼案后续）」（后续再逐段细化）；
5) 保留 R199 done 后不回 evt1579 循环逻辑；evt1663→85 返回兼容保留。

## headless
- 从 tester 槽2/场景90 后院位置：
  - HUD target evt1661 N=0，interact=1661，prompt「按空格继续查案（前往 scene91）」；
  - SPACE → **scene91 (1024,1112)**，HUD target evt1664 **N=17**，`a34_stage=1`；
- boot exit0；槽1/槽2 未写、未开窗。

## tester
- 后院对话后按 HUD 到 evt1661 N=0 按 SPACE → scene91；
- 跟着 HUD 到 evt1664（N=17）按 SPACE → scene93；
- 下一批接 scene93 剧情（evt1691/1689/1690/1697…）+ scene94/98/85/87 白名单。
