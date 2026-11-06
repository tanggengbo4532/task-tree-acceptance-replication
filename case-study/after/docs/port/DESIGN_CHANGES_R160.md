# R160 flee 冷却覆盖 auto 脚本路径（修复 0 步连续再战）

## 现场（r159 FAIL）
- HEAD 4f740a9，slot1 E44079CB scene71 固定遭遇：
  第1场 flee → N 保持；走 4 步→第2场 flee → **0 步→第3场 flee → 0 步→第4场**（4连），越逃越快。
- r159 只拦了 `_check_touch_triggers`（触碰触发路径）；**`_update_event_updates` 的 auto 脚本仍每帧推进**：
  evt1382-1386 的 auto=41099 含 `0x004C` 追击，会持续追着玩家；R136 只暂停 `_flee_guard_evt` 同一个 id，
  旁边同队怪/换 event 仍可重新开战；且 auto 可能把事件重新 arm。

## 修复（world.gd R159-FLEECOOLDOWN-2 / R160）
1) **auto 脚本路径**：在 `_update_event_updates` 中，`state>0` 且处于 10s 脱战窗口时，
   对**所有 `_is_encounter_event(id)`** 跳过 auto 脚本推进（不只同一 id），防止 0x4C 追击/重新开战/re-arm。
2) 触碰路径：窗口内跳过所有遭遇/追击事件（r159 已有）。
3) 逃跑：当前事件 vanish=max(300,原值)、同事件 guard 600 帧、圈 max(96,ring+32)、窗口 600 帧。
4) 胜利：当前遭遇事件 vanish=300，并给全遭遇 **5s 冷却**（`_flee_guard_all_until`）。
5) `_is_encounter_event` 覆盖触发脚本 0x0007 与 auto 脚本 0x004C（按场景缓存，只读）。

## headless 验证（槽1只读，模拟帧循环而非单次触发）
- scene71 evt1385 触发 team33 → `on_battle_finished("flee")`：
  - evt1385 vanish=300、guard_all_until=+600、战斗节点释放；
  - 把玩家放回事件附近，**推进 ~700 帧并每 4 步移动一次**：
    每轮 battles=0、mode=null；`max_battles_during_window=0`。
- boot exit0；槽1未写；未开窗。

## tester4 复测（A）
1. 固定遭遇点 flee → 原地/走 10~20 步（多按方向键推进帧），确认不再 0 步/2 步连战；
2. 再走 100 步统计战斗场数（可继续 flee），应明显下降；
3. B4 已 PASS 不重测；固定怪 HP1800 不改。
- 若仍有 0 步连战，请记录“第几次 flee、当时是否移动、事件怪是否还在追击”，并给场景/坐标。
