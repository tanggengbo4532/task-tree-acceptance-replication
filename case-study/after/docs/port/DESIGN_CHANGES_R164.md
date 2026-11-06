# R164 宽限清场后恢复遭遇事件（避免局部永久无怪）

## Lead 反馈
- r163 PASS，但 `cleared 5 encounter events` 用了 `state=0/auto=0`；若永久，会让该场景遭遇长时间消失（过少）。
- 要求：宽限内临时跳过，宽限后恢复；验证恢复时间与可触发。

## 修复（R164-GUARDRESTORE-1）
1) 新增 `_guard_event_backup`：首次清场时按场景保存每个 encounter 事件的
   `state / auto_script / vanish` 原值；重复清场不覆盖快照。
2) 宽限内仍临时 `state=0、vanish=max(600)、auto=0` + touch/auto 墙钟跳过（保持 r163 不连战）。
3) **墙钟宽限到期后**（`Time.get_ticks_msec() >= _battle_guard_until_ms`）：
   `_restore_encounter_events_after_guard()` 恢复 `state` 与 `auto_script`，`vanish=0`，清空快照；
   每帧在 `_update_event_updates` 最前检查；日志 `[battleguard] restored N encounter events after guard`。
4) 场景切换/读档时快照清空（新地图按原数据重置）。

## headless 验证（槽1只读）
- scene71 evt1385 flee：
  - 立即：`backed up 5`、`cleared 5 (temporary, restore after guard)`、evt1385 `state=0/auto=0/vanish=600`；
  - 真实 sleep **11s** 后：`[battleguard] restored 5 encounter events after guard (scene 71)`；
    evt1385 `state=-2（原值）/auto=41100（原值）/vanish=0`，`backup=0`；
    `battle_guard_check` blocked=false（宽限到期，可正常再战）。
- boot exit0；槽1未写；未开窗。

## 恢复时间说明
- flee 后 10s、win 后 5s 内遭遇被临时隐藏/跳过；
- 到期自动恢复该场景遭遇事件的原 state/auto，遇敌频率回到正常（不会永久消失，也不会立刻连战）。

## tester4 抽验
1. flee 后等约 10s（或走远再回来），该图遭遇应重新出现/可触发；
2. 100 步场数应正常（非 0、非连战）；
3. B4 不重测；固定怪不改。
