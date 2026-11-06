# R310 死亡角色行动/赎魂复活修复

## 实机问题
- 巫后「赎魂」对死者无效果
- 角色 HP 0 后仍能选指令/普攻

## 根因
1. `_do_player_magic` 对辅助/复活类（type4/5/8）执行 `script_on_success` 时固定传**施法者 role**：
   `_run_script(..., role)`。赎魂脚本 0x0022 通过 `last_event_object_id` 找目标，
   结果目标变成巫后自己；死者 role 从未被复活。
2. 行动队列在 `_build_action_queue` 对 HP0 角色仍设置 `FIGHTER_ACT` 并入队（dex0），
   `_perform_phase` 仍会调用 `_player_perform`，所以死者还能普攻。
3. `_select_phase` 的 `_cannot_act` 虽为 true，但状态写成 `FIGHTER_ACT`，同样会把尸体当行动者。

## 修复
- 辅助/复活脚本目标改为**实际选中的队友 role**：
  - 单体：`players[target]["role"]`
  - 全体：对每个存活/队伍成员执行
  - 兜底：施法者
- `_build_action_queue`：HP0/睡眠/麻痹角色不加入队列，state=FIGHTER_WAIT
- `_select_phase`：不可行动角色 state=FIGHTER_WAIT
- `_player_perform`：开头再兜底，HP0且非傀儡直接 return
- `_select_player_target` 原本已允许选择死亡队友，不改；赎魂可选目标

## headless 验证（终战team315，玩家=巫后+李）
q2189：
```
[qa] battle_ready players=2
[debug-revive] caster=0 target=1
[debug-revive] after_death hp=0 cannot_act=true in_action_queue=false
[debug-revive] before_revive target_hp=0 caster_mp=990
[debug-revive] after_revive target_hp=281 (expect 281) caster_mp=960 statuses={"3":[],"0":[]}
```
- 死者 `cannot_act=true`，不进入行动队列
- 赎魂后目标 HP 281 = maxHP 938×3/10；MP 990→960（30MP）；状态清空
- 无 SCRIPT ERROR

## marker/状态
- **`[BUILD] R310-revive`**
- 槽1只读8880；槽2=场外锚点；开发未开窗/未实机（用户自己测）
- 文档本文件
