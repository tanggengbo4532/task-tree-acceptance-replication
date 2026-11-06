# R294 第6章战斗队伍重复阿奴修复

## 用户实机 bug（R293 PASS后）
- 槽2载入 3F7BEFBC→神木林窄道通过→A44凤凰战
- 战斗队伍显示 **2×阿奴(role4)**，李逍遥不见；一回合 lose

## 解析
q2125 载入该档：
```
maxidx=1
party=[{role:4},{role:4},{role:4},{role:4},{role:4}]
hp role4=564/564 level35（重复）
```
- 存档 party 全部 role4 阿奴；`_ensure_story_party_chapter6` 只修 party[1]，没修 party[0]
- 且读档路径只调 `_repair_story_party_on_load`（maxidx>=1直接return），未调 chapter6 恢复
- 战斗按 maxidx=1 取 party[0],party[1] → 两个阿奴

## 修复
1. `_ensure_story_party_chapter6` 强制：
   - party[0] = 李逍遥(role0)
   - party[1] = 阿奴(role4)
   - 其余槽=role4，maxidx=1
   - 保留 scene253 原版终战(巫后+李)例外
2. 读档 `PALState.loaded_from_save` 分支：`_repair_story_party_on_load()` 后调用 `_restore_party_story_hp_mp()`，确保第6章每读档即恢复 [0,4] 并补 HP/MP
3. A44 自动触发开战前再调一次 `_restore_party_story_hp_mp()`
4. 不改存档文件/等级/战斗数值；只在运行期修正队伍编成

## headless 验证（q2125，同档）
```
scene=185 maxidx=1
party=[role0, role4, role4, role4, role4]
member0 role=0 hp=302/302 level=13
member1 role=4 hp=564/564 level=35
```
- 队伍唯一：李逍遥+阿奴；不再两个阿奴
- 重启读档同路径同样恢复（读档调用同一 helper）
- 战斗/状态菜单按 party[0..maxidx] 取成员 → 李+阿奴

## 状态
- boot exit0；槽1只读3F7B；槽2=该档副本；未开窗/未实机
- 文件：`world.gd`；R293窄道2格修复保留
