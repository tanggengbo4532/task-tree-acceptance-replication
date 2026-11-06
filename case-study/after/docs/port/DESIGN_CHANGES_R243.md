# R243 审案选择“选是仍重复”修复（ONENTER-1 / CONFIRMYES-1）

## 用户现象
槽1 `4E7BD4EA…`（scene93，13:43）从进度一玩到 scene82 审案「你招是不招！？」选择框；
选「是」后同样重复同一段审案/选择，无法推进。

## 根因（数据 + headless 定位）
1. scene82 的 **onEnter 脚本 = 14343**（数据 `scenes[82].wScriptOnEnter=14343`）。
   该脚本在 IP14486 有 `0x000A a0=43511` 选择：
   - 是：14487…14551，结尾 `0x0004 13041` 调子脚本；
   - 否：43511 → `0x0003 14462` 跳回问句前（原版“不招就再问”循环，保留不改）。
2. 子脚本 13041 = `0x0059 85` → scene85，而 scene85 的 onEnter 被 14318 的 `0x006D 85 14553` 设为 14553；
   14553 又 `0x0059 82` 回 scene82 → **scene82 onEnter14343 再次执行 → 同一选择再次出现**。
3. 原版 `play.c` 会把 `PAL_RunTriggerScript()` 的返回入口写回 `wScriptOnEnter`（脚本 end 后通常为下一行/停止）；
   本移植 VM 异步执行、没有写回，导致 scene85/scene82 的 onEnter **永久保留、每次重进重播**。

## 修复
1. `world.load_scene`：启动 onEnter/onTeleport 脚本时**消费该入口**（置 0），等价于原版返回停止入口；
   防止 scene82 onEnter14343 / scene85 onEnter14553 循环重播。
2. `menu.gd::ScriptConfirmController.index` 默认 **1（是）**：玩家直接回车=选是，推进剧情；
   左/↑=否，右/↓=是；Esc=否（原版“否”循环保留）。
3. R242 选择框置顶 layer20 保持不变；footer「←→ 选择 回车确定 Esc 否」保留。

## headless 证据（槽1只读）
- 修复前 q1927：choice IP14486，直接 Enter 选是 → IP14494，随后**再次 CHOICE_AGAIN ip=14486**（重复）。
- 修复后 q1930：到达 choice 时 `scene82.onEnter=0, scene85.onEnter=0`；
  直接 Enter 选是 → IP14494，`waiting_choice=false`，300 帧后无重复 choice，仍 scene82。
- 静态数据：是分支 14486→14487…14551→子脚本13041(0x59 85)→14553→0x59 82；onEnter 已消费，故不再回到 choice。
- boot exit0，无 SCRIPT ERROR。

## 槽位
- 槽1只读；槽2未写；未开窗；插件未动。
- 图：无新增截图（headless 无法渲染）；请 tester 实机复测“一直选是能推进到出府”。
