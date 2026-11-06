# R259 scene106↔109 桥门 ping-pong 修复

## 实机问题（tester r249）
出城→evt1583→scene106桥门 SPACE→scene109落点(672,1888)后立刻出现反向门提示，SPACE→回scene106，循环27次；HUD 恒「蜀山驿路 N6」，无scene109 N170前向引导。

## 根因
1. scene106 桥门拦截条件含 `a36_stage<1`；旧档 `a36_stage=1` 时拦截不生效/状态残留，scene109 前向 c3 不进；
2. scene109 落点附近的原版事件1997（脚本15619）+ R253反向拦截会被SPACE直接触发，形成反向传送；
3. 反向交互 hook 仅用 a36_stage/距离，未覆盖刚落地帧，且原版事件触发未拦截；
4. 前向 HUD 在旧状态/落点帧没有优先显示 evt1996 N170。

## 修复（R259）
1. **scene106桥门拦截**：只要 `a35_stage>=1` 即生效；进入时清除旧 `a36_stage=0`、置 `a36_route=1`，并设 180帧到达保护；
2. **scene109前向优先**：到达后 c3 立即指 evt1996，HUD N170；
3. **反向门三重限制**：
   - 180帧落点保护内不可触发；
   - 距桥落点(672,1888) `<160` 不可触发；
   - 必须 `a36_stage>=1` 且 target_evt≠1996；
   - 原版事件1997脚本15619在落点保护/距离<160时**被吞掉，不反向跳**；
4. scene106 桥门落点保持 (160,1104) 附近；没有空格跳场景/传送/改地图。

## headless 验证（用户槽1只读）
- q2005（故意置 stale a36_stage=1）：
  - scene106 桥门 SPACE→scene109 (672,1888)，HUD **N170 target evt1996**；
  - 在落点再按 SPACE：`[c3] R259 reverse gate blocked at bridge landing d=0`，**仍停在scene109 N170**，无ping-pong。
- q1997：scene109 N170→走至N0→evt1996→scene118锚点(640,1672)；
- q2004：scene85出城 N142→evt1583→scene106 N6→桥门→scene109 N170→scene118→scene140 N276；
- q1995：scene140 evt2346 N0→scene139(1552,1432)；
- q1992：scene139 N16→scene141(1344,1328)，a36=1。

## 场景序列/N表
85(A34 N68→91 N34→93 N24→82 N49→89 N64→85复命N6)→出城N142→evt1583→106桥门N6→109 N170→evt1996→118锚点→140 N276→139 N16→141。
- 说明：scene140 N276 自动 loop 只到 N237（迭代上限），门段用 q1995 近门验证 N0→scene139；tester实机按HUD走完。

## 状态
- boot exit0，无 SCRIPT ERROR；槽1只读、槽2未写、未开窗。
- 文件：本文件；代码 world.gd。
