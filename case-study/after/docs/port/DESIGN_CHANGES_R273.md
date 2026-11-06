# R273 读/存动作日志 + 槽2误写保护

## 根因补齐
- 读档槽修复（R270）后仍有两个风险：
  1. `PALState.save_game(slot)` 曾把 `current_save_slot` 改成**保存目标槽**；误存到槽2会把“当前载入槽”改成2，之后 GameOver/0x4E 读错档（正是 r265 槽2被写成用户档的场景）
  2. 菜单存档允许直接覆盖团队槽2测试锚点
- 修复：
  - **保存不改变 current_save_slot**（current 只由 load_game 设置/记录）
  - 每次 load/save/request/GameOver 打印 `[save]` 日志：slot、current_loaded、scene、来源
  - SaveSlotMenu **禁止游戏内存档槽2**（toast「槽2为团队测试锚点，已禁止游戏内存档」）
  - 菜单 save/load 都有 `[save] MENU_SAVE / MENU_LOAD` 日志

## headless 证据（q2054，槽2=新185锚点）
```
[save] LOAD slot=2 current_loaded=2
[qa] scene=185 current_slot=2
[save] REQUEST_LOAD current_loaded=2 scene=185
[save] LOAD slot=2 current_loaded=2
[qc] scene=185 current_slot=2
slot1 hash 14B5CFBD… 未变
```
- 启动时模板会先 load slot1（测试模板行为），随后显式 load slot2；tester 正常流程需在标题/菜单实际选槽2。
- GameOver 只回 current_save_slot；无有效当前槽回标题，不再回槽1/最新。

## 凤凰数据（已确认可胜）
- eid67 res：风9，雷/水/火/土4；无弱点
- 阿奴天雷破（28MP/雷250）→ tester实测约300/发，10发≈3000；需治疗/道具循环
- team203 flee=0、无0x89；正常击败，不改数值

## 188 movement
- 仍停(1440,960)：手动LEFT可走、自动循环停；本轮优先读档修复，未解
