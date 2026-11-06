# R148 ARCH_REVIEW：引导提示与真实触发不同源（evt1741/1728/1724 连续无响应）

## ARCH_REVIEW 结论
1) **战斗脚本分支映射错误（根因，影响所有 0x0007 战斗）**
   - Sss 0x0007 参数：`a0=敌队, a1=胜利脚本, a2=失败脚本`。
   - 旧 `ScriptVM.resume_battle`：`BATTLE_LOST → jump(a1)`、**BATTLE_WON 没有跳分支**（走 ip+1）。
   - 结果：战斗胜/败脚本走反/走漏；A33 女飞贼（evt1630 脚本13834 `0x7 29 41075 0`）战败时本应落到
     13839 起的“战后剧情+设置 evt1741/1724 等”，实际跳去胜利分支 41075，后续事件状态没按真实分支设置。
   - 现存档表现：evt1741=0（被消耗）、ev1786=0、**evt1724 trigger_mode=0**（scene98 脚本13606 曾设0，
     战后本应由 13850 `0x40 1724 5` 恢复5，但战败分支没执行）。
2) **HUD“已到触发点”与真实交互分发不同源**
   - 旧 `_build_merged_guide` 只看距离场到环（`_a14g_key==""` + `_a19g_cd0`）就显示“已到触发点”，
     不检查目标事件本身是否还能被触发（mode0/state0 也显示）。
   - 因此 evt1724(mode0)/evt1741(state0) 显示“到点按空格/走近”但 SPACE/走近无反应。

## 修复（设计层）
1) **ScriptVM.resume_battle 统一映射**（R148-BATTLEBRANCH-1）：
   - BATTLE_WON → jump(a1)（a1 非0），否则顺序执行；
   - BATTLE_LOST/BATTLE_FLEED → jump(a2)（a2 非0），否则顺序执行。
   - 影响面：所有脚本战斗胜/败分支；这是修“战后事件状态不对”的公共根因。
2) **提示=真实触发同源**（R148-TRIGGERSRC-1）：
   - 新增 `_c3_target_triggerable()`：目标事件 state>0 且 trigger_mode>0 才可触发
     （mode>=4 门/触碰；mode1-3 由 NPC/专用交互扫描处理；mode0/state0 不可）。
   - c3 引导在 `_a14g_key==""` 时若目标不可触发 → 返回空，不显示“已到触发点”，不占用中央伪提示。
3) **存档侧补偿**（R148-A33REPAIR-1）：
   - 旧档 A33 已完成（evt1630>0、evt1741=0、ev1786=0）但 evt1724 因旧 bug 仍 mode0 时，
     scene94 自动把 evt1724 trigger_mode 补回5，SPACE 门恢复；日志 `[a33] R148-A33REPAIR-1`。
4) **A33 完成后目标**：`_a33_done_state()` 判定；scene83→evt1546「返回衙门（继续查案）」；
   scene85→**evt1610 (528,280)**「继续查案（女飞贼案后续）」→ scene93（A34）。

## headless 验证（槽2只读，A123CD6D）
- 载入 scene94：`[a33] R148-A33REPAIR-1 evt1724 mode -> 5`；
  HUD=目标 第4章：返回衙门（女飞贼案后续）｜↓剩110格。
- 传送到 evt1724 圈内：interact=1724 kind=space_door prompt=按空格前往；
  按 **SPACE** → **scene83**（pos 704,544），验证真实可触发。
- 引导环内文字现在受 `_c3_target_triggerable` 门禁；已消耗/不可触发目标不再显示“到点按空格/走近”。
- boot exit0；槽1 只读；未开窗。

## tester 从槽2 A123CD6D 继续
1. 新构建载入槽2 scene94：HUD `↓ 剩110格` → 走到 **evt1724 (768,928)**；
2. **SPACE** → scene83（已验证）；
3. 按 HUD 回 scene83→evt1546→scene85；
4. scene85（A33 已完成）HUD 应指 **evt1610 (528,280)**「继续查案（女飞贼案后续）」→ SPACE → scene93；
5. 到 scene93 后存槽2 报位置，我接 A34 女飞贼案后续/战斗。
