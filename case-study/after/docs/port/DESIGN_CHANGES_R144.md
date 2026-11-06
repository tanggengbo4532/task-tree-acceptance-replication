# R144 客栈夜间剧情后引导 + 对白 SPACE 支持

## 现场（r143 tester）
- scene94 客栈 evt1741 SPACE 触发夜间对白；SPACE 连按无反应，**ENTER 可翻页**。
- 夜间剧情后 HUD「目标 第4章：前往夜探街道｜等待/绕行中」，找不到 evt1728，无法进 scene98。

## 根因
1) 对白推进：世界输入里 SPACE 先被若干交互/门分支处理，夜间剧情时 `player_busy` 可能为 false，
   SPACE 被提前吞掉，只有 ENTER 走到对白分支 → 与真实“SPACE/ENTER 都能翻页”不一致。
2) evt1728 (1248,704) 在 **客栈上层**，从当前层不可直达；上层入口是楼梯 **evt1731 (496,728)** 脚本35655（上楼）。
   旧 c3 直接把目标设为 evt1728 → 距离场不可达 → HUD 变“等待/绕行中”。

## 修复（world.gd）
1) **R144-DIALOGKEY-1**：在 `_unhandled_input` 最前面加对白优先处理：
   `SPACE/ENTER/KP_ENTER` 且对话框 active → 打字中跳字/翻页/关闭+推进 VM；随后 set_input_as_handled + return。
   SPACE 与 ENTER 行为完全一致，不再被门口/NPC 分支抢先。
2) **R144-STAIR94-1**：
   - scene94 在 evt1786 已开启且未上过楼时，c3 目标先指 **evt1731 (496,728)「客栈上楼」**；
   - 触发 evt1731/脚本35655 时写 `a33_stairs=1`；
   - 上楼后再指 **evt1728 (1248,704)** → scene98。
3) scene94 后续：夜间完成（ev1786>0）→ 先上楼 evt1731；上楼后 evt1728；案件开启后 evt1724 返回 scene83。

## 验证（headless，槽2 只读）
- 当前槽2 scene94 (816,904)：ev1786=0、ev1630=0；guide=`目标 第4章：客栈夜间剧情（前置）｜↑剩3格`（evt1741，fb=false）。
- boot exit0；无 SCRIPT ERROR；槽1 只读、未开窗。

## tester 从槽2 scene94 继续（新 hash）
1. 按 HUD **↑剩3格** → evt1741 → **SPACE**（现在 SPACE/ENTER 都能翻页）读完夜间剧情；
2. 剧情后 HUD 应变 `目标 第4章：客栈上楼（前往夜探街道入口）`，目标 **evt1731 (496,728)**；
3. 走到 evt1731（楼梯，mode4 触碰）→ 上楼脚本35655；HUD 切 `前往夜探街道`，目标 **evt1728 (1248,704)**；
4. 到 evt1728 → SPACE → scene98；
5. scene98 HUD → evt1786 (400,504) 触发 → 开启 A33；
6. 按 HUD 返回 scene98→94→83→85→87，scene87 目标切 **evt1630 (1296,280)**；走近触发夜遇女飞贼（BATTLE team=29）。
