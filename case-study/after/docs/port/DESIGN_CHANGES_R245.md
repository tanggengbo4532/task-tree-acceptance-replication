# R245 全灭兜底严格化（DEADGUARD-1）

## 用户反馈
R244 已保证 GameOver→读最近档，但审案对白中途仍出现 GameOver（不应因每帧全灭兜底判负）。

## 槽1队伍状态（只读检查）
- `4E7BD4EA…` scene93 slot1，max_party_member_index=1：
  - 李逍遥 role0：Lv12 HP **0**/290，MP142/230（存档时已阵亡）；
  - 林月如 role2：Lv12 HP334/339，MP118/188（存活）。
- 读档瞬间 `_party_all_dead()=false`；但剧情脚本中途 `max_party_member_index`/party 变化时，旧每帧兜底会误判“全灭”。

## 根因
`_process` 在 `not player_busy and (vm==null or !active)` 时每帧检查 `_party_all_dead()` → `_game_over()`；
审案对白期间 `player_busy` 可能为 false、且队伍成员数组临时只含已阵亡的李逍遥 → 被误判为全灭。

## 修复（R245-DEADGUARD-1）
全灭兜底增加严格前置条件，仅在**真实战败结束、玩家可操作、无脚本/对白/菜单**时允许：
```
not _game_over_shown
and not player_busy
and _mode_node == null
and (vm == null or !vm.is_active())
and not _dialog_tail
and not _dialog_box.is_active()
and _last_battle_result == "lose"
and current_map != null and _party_all_dead()
```
-> 才 `_game_over()`（R244：优先当前槽/最新槽1-5 读档）。
对白/过场/审案/菜单/VM 活动中**绝不触发**；保留战败脚本 41075/0x4E 正路。

## headless 证据
- q1951：审案对白中强制“李逍遥HP0 + maxidx=0 + last_battle_result=lose”→ 等待 480 帧，`dlg=true, go=false, dead=true`，**无 GAME_OVER**。
- q1940：强制全灭后直接 `_game_over()`→ scene93 (736,1512), slot1（R244 读档路径仍有效）。
- q1941：脚本14669 战斗失败→41075→0x4E→scene93 slot1（正路未受影响）。
- boot exit0；slot1 hash 未变；slot2 未写。

## 槽位
- 槽1只读；槽2未写；未开窗；插件未动。
