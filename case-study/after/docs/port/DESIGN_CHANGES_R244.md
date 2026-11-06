# R244 GameOver 读回存档修复（GAMEOVER-LOADSAVE-1）

## 用户现象
审案推进到“师爷建议利用他们”后出现 `[world] GAME_OVER`，**不是红屏读档**，而是重开新游戏 scene2 李大娘开场；2/2 复现。

## 根因
1. 原版战败分支：脚本失败入口 **41075**（`0x004F` 红屏 + 13135-13137 台词 + **0x004E 读取当前档**）；
2. 本移植还有一层兜底：world 每帧在无 VM/无 busy 时检查 `_party_all_dead()` → `_game_over()`；
3. `_game_over()` 旧实现结束白后 `get_tree().reload_current_scene()` → 重载 main.tscn（标题/新游戏），
   未读回存档，也不会覆盖存档；tester 看到 scene2 开场即此路径（战败/全灭兜底）。
4. 0x004E 本身 q1941 已验证正确：脚本14669 战斗失败入口→41075→0x4E→`PALState.current_save_slot=1`→scene93(736,1512)。

## 修复
- `world._game_over()`：不再 `reload_current_scene()`；
  - 优先 `PALState.current_save_slot`（存在且文件在）；
  - 否则扫描槽1-5，取**修改时间最新**的存档；
  - 设置 `current_save_slot` 后走 `request_load_game()`（真实 0x004E 同路径：清战斗/VM/对白→load_game→load_scene）；
  - 无任何存档才回标题（不创建/覆盖存档）。
- 新增 `_latest_save_slot_for_gameover()`；不写任何槽。

## headless 证据（槽1只读，slot1 hash 前后不变）
- q1940：scene93 slot1 强制队伍全灭→`_game_over()`→700帧后 **scene93 (736,1512), slot=1**，未进 scene2；
- q1941：脚本14669 战斗失败→`on_battle_finished("lose")`→41075/0x4E→ **scene93 (736,1512), slot1**，HUD“继续查案”；
- boot exit0，无 SCRIPT ERROR；slot2 未写。

## 选择序列
- 审案「你招是不招」选 **是**（默认，回车）；选否是原版循环（不改）。
- 后续若因战斗失败触发 GameOver，按原版回最近档重试；本轮修复保证不再重开新游戏/覆盖存档。

## 槽位
- 槽1只读；槽2未写；未开窗；插件未动。
