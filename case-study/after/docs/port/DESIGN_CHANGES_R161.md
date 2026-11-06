# R161 战斗启动唯一收口点战后宽限（设计层，修复 flee 后 0 步连战）

## 现场（r160 仍 FAIL）
- HEAD df3f3cb，scene71 N=182 固定遭遇：flee 后站 2.5s 无战，走 4 步再战；此后 flee→0步→战→flee→0步→战 4连。
- 说明 r159/r160 的 touch/auto 事件级跳过**未命中真实重开战路径**（事件被逐帧重新请求 battle）。

## 设计层修复（R161-BATTLEGUARD-1，只改唯一收口点）
1) **`request_battle(team_id, flee_disabled) -> bool`**：所有触发路径（VM 0x0007、追逐、调试）最终都过这里。
2) 记录上一场：`_last_battle_result / _last_battle_team / _last_battle_evt / _last_battle_frame`；
   - flee → `_battle_guard_until = now + 600`（10s）；
   - win → `now + 300`（5s）。
3) 宽限内若新战斗 **team 相同** 或 **来源 event 相同**：
   - 拒绝创建战斗，日志 `[battleguard] blocked re-entry team=... src_evt=... result=... age=... stack=...`；
   - 将来源事件 **state=0、vanish=max(300,...)、auto=0**，彻底清场；
   - 不冻结玩家移动（不进入战斗、不改变队伍/位置）。
4) **ScriptVM `_start_battle`** 读取 `request_battle` 的 bool 返回值：被拒绝时清 `waiting_battle/_pending_battle`、
   `ended=true`（结束该 auto/触发脚本），不会逐帧重复请求/卡死。
5) 事件级 touch/auto 跳过（r159/r160）保留作为双保险。

## headless 验证（槽1只读，真实帧循环）
- scene71 evt1385/team33 → flee：
  - `_last_battle_team=33、_last_battle_evt=1385、guard_until=+600`；
  - 守卫内直接调用 `request_battle(33,false)`：
    `[battleguard] blocked re-entry team=33 ... result=flee age=60`；
    accepted=false、battles=0、mode=null；
  - evt1385 被清场：state=0、vanish=300。
- 前一轮 q440 帧循环（700+帧、每4步移动）battles=0 仍保持；本守卫为最终兜底。
- boot exit0；槽1未写；未开窗。

## 诊断结论
- 真实重开战路径不在 touch/auto 的事件过滤处，而是**事件/脚本仍反复请求 battle**（auto 逐帧推进/其他触发路径）。
- 现在在唯一入口按“上一场结果+team/来源+时间”拒绝，直接封死 0 步连战，不依赖 event id 或轮询路径。

## tester4 复测（A）
1. 固定遭遇点第1场 flee；原地/走 20 步（推进帧）不再战；
2. 再走 100 步统计场数（可 flee），应明显下降；
3. 若仍复现，把 `[battleguard]` 日志发给开发（会显示 blocked 的 team/src_evt/stack）。
- B4 已 PASS 不重测；固定怪 HP1800 不改。
