# R261 第5章队伍成员恢复 + 遭遇战数据核对

## tester r252
scene140 随机战斗队伍只有李逍遥，赵灵儿/林月如缺席；敌跳蚤 HP586 打 86-102，5回合 lose；读档重跑必败。

## 用户槽1实际数据
- `max_party_member_index=0`；5 个 party 槽位全部 role=0（李逍遥）
- 李逍遥 role0：HP 0/290，MP142/230（残血/倒地）
- 林月如 role2：HP334/339，MP118/188，LV12（真实角色数据存在）
- 赵灵儿 role1：HP0/288，LV9（存档不在队；第5章此阶段原版队伍应为李+林，未强行加入）
- 剧情 vars：a24_stage=1、a28_stage=1、a32_clue1=1、a33_stage=1；a34/a35 尚未（用户推进中）

## 修复（R261-PARTY5-1）
新增 `_ensure_story_party_chapter5()`，在 `_restore_party_story_hp_mp()` 开头调用：
- 若 `a35_stage>=1` 且当前存档仍是单人（maxidx=0），把真实存在的林月如 role2 放入战斗队伍：
  - `party[1]["role"]=2`，后续槽位 role2，`max_party_member_index=1`；
- 然后 `_restore_party_story_hp_mp()` 对 Li/林 HP/MP 回满（HP0→max），运行期 only，不写档；
- 赵灵儿 role1 HP0/非队，按原版此阶段不强行加入；若用户后续确认原版应有赵，再由剧情恢复。

## 验证（headless q2010）
- 载入槽1→设 a35_stage=1→调用剧情恢复：
  - maxidx=**1**；party[0] role0 **HP290/290 MP230**；party[1] role2 **HP339/339 MP188**；party[2..] role2
- boot exit0，无 SCRIPT ERROR。

## 遭遇战数据核对（未改数值/未 auto-win）
- enemy object411 名“跳蚤”，enemy id14：**HP586，LV20，exp42**；
- 队伍表 team139=[跳蚤×1]；team141=[跳蚤×3]；
- DesignTuning 的 ENEMY_OVERRIDES 只覆盖队伍15/16/17/40，**139/141 无覆盖**；属原版 Data.mkf 数值；
- 随机遭遇 flee_disabled 默认 false（非 boss），玩家菜单有“逃跑”选项；
- 结论：数据本身合理，不是 team 映射/移植改值；单人必败合理。加入林月如后需 tester 重测；若仍必败，给完整战斗日志（我方成员/HP/敌HP/伤害/逃跑选项），再判断是等级/道具/原版难度问题，不做 auto-win。

## 状态
- 槽1只读、槽2未写、未开窗；N 表沿用 R258/R259（85→…→141）。
- 文档：本文件。
