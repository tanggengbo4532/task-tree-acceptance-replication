# R141 A32 线索 NPC 交互补接（scene80 evt1505 / scene83 evt1557）

## 现场（r140 BLOCKED）
- 槽2 scene80 evt1505 (624,1256) 环内；中央「已到触发点：按空格/走近触发」，但 SPACE/ENTER/走近全无反应。
- 原因：evt1505/evt1557 在真实表里是 **mode2 NPC 交谈**（不是 SPACE 门）；
  R140 只加了 c3 引导目标，未给这两个 NPC 接“走近按 SPACE 执行真实脚本”的交互入口。

## 真实事件
- scene80 evt1505：(624,1256)，mode2，脚本 **15109**（A32 线索2：路人偷盗案线索）。
- scene83 evt1557：(992,784)，mode2，脚本 **15149**（A32 线索1：女飞贼专偷恶霸）。
- 后续：scene80 evt1501 (432,1192) mode5 脚本13230 → scene83。

## 修复（world.gd R141-A32TALK-1）
1) `_scan_extra_interact` 新增 scene80/evt1505、scene83/evt1557 专用交互：
   - 距 NPC <120 metric 时设置 `_interact_id/_interact_trig`，提示：
     - 「按空格打听偷盗案线索（第 4 章）」（scene80）
     - 「按空格打听女飞贼线索（第 4 章）」（scene83）
   - kind = `a32clue2` / `a32clue1`，SPACE 走真实脚本15109/15149。
2) SPACE 分派写进度：
   - `a32_clue2=1`（线索2已得）；
   - `a32_clue1=1` 且 `a32_stage=1`（线索1已得/A32 完成）。
3) c3 目标随进度切换：
   - scene80 线索2后 → evt1501「前往另一条线索（女飞贼）」；
   - scene83 线索1后 → 空（A33 后续再接）。

## headless 验证（槽2 只读）
- scene80 传送到 (624,1248)：`interact=1505 kind=a32clue2 prompt=按空格打听偷盗案线索（第 4 章）`；
  按 SPACE：脚本启动后 `a32_clue2=1`；HUD 切 `目标 第4章：前往另一条线索（女飞贼）｜←剩17格`（evt1501）。
- scene83 传送到 (992,776)：`interact=1557 kind=a32clue1 prompt=按空格打听女飞贼线索（第 4 章）`；
  按 SPACE：`a32_clue1=1、a32_stage=1`。
- boot exit0；槽1 只读；未开窗。

## tester 复测点（新 hash）
1. 槽2 scene80（BA965810…）→ 到 evt1505 (624,1256) 环内：中央应显示「按空格打听偷盗案线索（第 4 章）」；
2. 按 **SPACE**：应播真实对白/脚本，不再无反应；HUD 切「前往另一条线索（女飞贼）←剩17格」；
3. 到 evt1501 (432,1192) 按 SPACE → scene83；
4. scene83 到 evt1557 (992,784) 环内：显示「按空格打听女飞贼线索」→ SPACE 播真实脚本，a32_stage=1；
5. 完成后存槽2报位置，我接 A33 夜探衙门。
