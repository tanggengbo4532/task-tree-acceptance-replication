# R149 A33 战后 scene85→90 真实链（不再直指未开启 evt1610）

## 现场
- 槽2 `80C067B8…`：scene85 (512,280)，a33 完成状态（ev1630>0、ev1741=0、ev1786=0）。
- HUD 中央为空：c3 指向 **evt1610**，但 evt1610 真实 **state=0**（未开启），
  `_c3_target_triggerable()` 正确拒绝显示“已到触发点”。
- evt1610 开启脚本是 **14223（scene87 evt1632）**，而 evt1632 由 **scene90 evt1651（脚本13887）** 开启；
  直接指 evt1610 跳过了 scene90 前置。

## 真实链
- A33 完成后 scene85 真实出口：**evt1579 (1152,432)** mode5 脚本13087 → **scene90（衙门后院）**。
- scene90 剧情节点：**evt1650 (1056,1104)** mode2 脚本13882（继续查案对白）→ 后续 evt1651/13887 开启 scene87 evt1632→evt1610。
- evt1610 (528,280) 脚本13409 → scene93（A34），需上述前置开启后才可触发。

## 修复（world.gd R148-A33DONE-2 / R149）
1) `_a33_done_state()` 后 scene85 目标改 **evt1579「前往衙门后院（女飞贼案后续）」**；
2) c3 场景列表加入 **90**；新增 scene90 目标 **evt1650「衙门后院剧情（女飞贼案后续）」**；
3) `_c3_target_triggerable()` 语义保持：state=0 目标不显示“已到触发点”，自动落到下一可触发节点；
4) R148 的 0x0007 战斗分支/evt1724 mode 修复保留。

## headless 验证（槽2 只读）
- scene85 (512,280)：guide=`目标 第4章：前往衙门后院（女飞贼案后续）｜↑剩75格`，
  target evt1579 (1152,432)，targetable=true。
- scene90 载入：guide=`目标 第4章：衙门后院剧情（女飞贼案后续）`，target evt1650 (1056,1104)，targetable=true
  （落点视图需要刷新，tester 实际进门后按 HUD 走）。
- boot exit0；槽1 只读；未开窗。

## tester 从槽2继续
1. 新构建载入槽2 scene85 (512,280)：HUD 应 `↑剩75格` → **evt1579 (1152,432)** → SPACE → scene90；
2. scene90 按 HUD 找 **evt1650 (1056,1104)**（mode2 NPC/剧情，走近按 SPACE）；
3. 剧情后按 HUD 继续（evt1651→evt1632→evt1610）→ scene93（A34）；
4. 到 scene93 先存槽2 报位置，我接 A34 女飞贼案后续。
