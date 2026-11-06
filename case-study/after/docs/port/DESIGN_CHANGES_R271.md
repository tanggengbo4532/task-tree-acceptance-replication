# R271 第6章队伍修复（李逍遥+阿奴）+ 凤凰战数据

## A) 队伍（重要）
- 数据：玩家角色 role 索引：0 李逍遥 /1 赵灵儿 /2 林月如 /3 巫后 /4 **阿奴** /5 盖罗娇
- 用户档 role4 阿奴：**LV35 HP564/564 MP480 atk196**（与 tester 早期见过的阿奴HP564一致）
- 林月如 role2 是第5章队伍；第6章苗疆应为 **李逍遥+阿奴**
- 修复 `R271-PARTY6-1`：
  - `_is_story_chapter6()`：a42_stage>=1 或 scene∈{175,177,187,188,185,189,207,206,247,255,253}
  - `_ensure_story_party_chapter6()`：party[1]=role4，后续槽role4，maxidx=1；HP/MP回满
  - `_restore_party_story_hp_mp()` 先 chapter5/再 chapter6；scene175/185 load_scene 也调用
  - chapter5 helper 在 chapter6 状态不再强行放林月如
- headless q2060：恢复后 **maxidx=1，party[0]=0/李 290，party[1]=4/阿奴 HP564 MP480**
- 锚点重建（用户最新槽1 14B5CFBD只读副本）：
  - `slot2_scene185_forest_anchor.sav` 新 SHA **389DADE20B831B8BA5BADCA9FB5C48FC7CAF395A95FD588396D92E27EE4F1CB0**
    - scene185 (736,1152)，李290+阿奴564/480，a42=1/a43=1/a44=0；HUD A44
  - `slot2_scene188_door_anchor.sav` 新 SHA **872E7CBA380257A21B02623292E116ABB744326E203FCF4698B9C2CC2872243E**
    - scene188 (368,1256)，evt3152旁，李+阿奴满状态；HUD已到触发点 interact3152
- 槽1未写；槽2已恢复用户最新档

## B) team203 凤凰战数据（不降难度/不auto-win）
- team203=[obj464]；obj464=凤凰 eid67 **HP3000**；script_on_turn_start/end/ready=0 → 无0x89/自动结束
- A44脚本26192：`0x0007 team=203 lost=41075 flee=0` → 正常击败、Boss不可逃
- 队伍修复后：李LV12/HP290/atk87；阿奴LV35/HP564/atk196（tester实测72-82/击）
- 数据判断：凤凰HP3000需要约40回合；敌法术141-283，阿奴HP564约2-3击；原版此战要求正常击败，属**难度/练级/补给阻塞**，不降难度/不auto-win

## C) 188 (1440,960) movement
- R269 HUD已指向evt3152 N126；q2052手动LEFT正常，q2053自动循环仍停(1440,960)
- 仍未打通188→evt3152→185；下一步查到点后VM/event状态

## 状态
- boot exit0；槽1只读；槽2用户最新档；未开窗
