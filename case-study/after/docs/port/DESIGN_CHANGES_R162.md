# R162 战斗启动全路径日志 + 最低层守卫（诊断 r161 无 [battleguard]）

## 诊断结论（先证明真实路径）
- 全工程 grep 战斗创建路径：
  - 正常：`ScriptVM 0x0007 _start_battle → world.request_battle → battle.gd.new()`；
  - 另有 `main.gd --battle-test` 调试入口直接 new（非正常游玩）；
  - 无其它正常战斗创建路径。
- 在 **VM _start_battle / request_battle / battle._begin** 三处加**无条件 print**（非 debug 门控）：
  `[battle-entry] from=vm_0x0007 / request_battle / battle._begin ...`。
- headless 已实际打印出真实路径：
  `[battle-entry] from=vm_0x0007 team=33 ... → from=request_battle → from=battle._begin`；
  说明该遭遇确实走 request_battle，r161 无日志只能是旧构建/日志未采集；现新构建会必打日志。

## 最低层守卫（R162-BATTLEGUARD-2）
1) `world.battle_guard_check(team_id, src_evt)`：统一检查上一场结果/队伍/来源/时间，打印 `guard_check PASS/BLOCKED`。
2) `world.battle_guard_mark_blocked()`：统一清场（来源事件 state=0、vanish=max(300)、auto=0），
   打印 `[battleguard] blocked ... stack=...` 与 `cleared evt=...`。
3) `request_battle` 使用上述统一检查并打印 `from=request_battle`。
4) **`battle.gd _begin()` 最前**再次调用 `battle_guard_check`（战斗节点实例化处最后防线）：
   命中则打印 `[battleguard] blocked at battle._begin`、清场、`queue_free()`、不显示战斗/不动输入。
   ——即使任何路径绕过 request_battle，也会在节点层被拦。
5) 来源判定：team 相同或来源 event 相同；若来源 event 每次变化，team 同队仍会被拦。

## headless 验证（槽1只读，真实帧循环）
- scene71 evt1385/team33 → flee：
  - 日志：`[battle-entry] from=vm_0x0007 team=33 lost=41075 flee=41073 last_evt=1385 ip=41231`；
  - 宽限内 request_battle：`[battle-entry] guard_check BLOCKED ...`、`[battleguard] blocked re-entry ... stack=battle_guard_mark_blocked <- request_battle`；
  - `[battleguard] cleared evt=1385 state=0 vanish=300 auto=0`。
- 放进事件附近、推进约 700+ 帧、每 4 步移动：`max_battles=0`，guard 保持。
- boot exit0；槽1未写；未开窗。

## tester4 复测（A）
1. 固定遭遇点 flee；原地/走 20 步（推进帧）确认不再战；
2. 再走 100 步统计场数（可 flee），应明显下降；
3. 若仍复现，抓 stdout 中最近 `[battle-entry] from=...` 与 `[battleguard] blocked ... stack=...` 发给开发，
   可直接看出是哪条路径/哪次调用。
- B4 已 PASS 不重测；固定怪 HP1800 不改。
