# R311 A49 胜利后重复第一战修复（a49_fight_started 未置位）

## 复现/数据判定
- 用户槽1 `8880C321…`：a49=1、**a49_fight_started 为空**、a50_ready=0
- 原版 Data：
  - scene253 onEnter **33561**：A49 剧情 + `0x0007 315 41075`（八头蛇战）
  - evt4441 script33673：同样 team315 的独立战斗脚本
  - A50 script **33570**（evt4443 mode6）：剧情 + `0x0007 315 41075`，胜利后由代码进入 scene267/34335
- 旧流程 bug：自动开第一战只调 `_start_script(33673,4441)`，**没写 `a49_fight_started=1`**；
  胜利后 `_update_a49` 的解锁条件要求 `a49_fight_started>=1`，a50_ready 永远不置位；
  `_update_a50` 第一战条件持续满足 → 每帧/每次重开同一第一战，形成完全相同的重复战斗。

## 修复（R311，不改Data/战斗数值）
1. `load_scene(253)` 且 a48>=1：a49_stage=1 时同步 **a49_fight_started=1**（onEnter33561 已启动第一战）
2. `_update_a50` 第一战触发：写 `a49_fight_started=1`、`a50_ready=0`、清 last_battle_result
3. `_update_a50` 第二战触发：写 `a50_started=1`、`a50_ready=1`、清 last_battle_result
4. 第一战胜利 → `_update_a49` 置 a50_ready=1；HUD切换「已击败水魔兽→追击」
5. 第二战胜利 → a50_started + win → scene267 onEnter34335 结局

## headless 全流程验证
q2197（调试进程强制 `_finish("win")` 模拟胜利；正式战斗仍真实，不auto-win）：
```
[qa] afterA49 scene=253 mode=null a50r=1 a50s=1 db=true
[qb] second_battle=true scene=253 mode=Battle a50r=1 a50s=1 a50stage=0
[qc] afterA50 scene=267 pos=(960,736) mode=null a50r=1 a50s=1 a50stage=1
     HUD=[已击败拜月教主/水魔兽 → 结局（第7章G3）]
```
- 第一战后不再重开第一战；自动推进到唯一第二战，再进 scene267 结局
- 第二战脚本/Data 是原版 **33570/evt4443，team315**（与第一战同八头蛇队）；这是原版二段战脚本数据，不是重复第一战
- q2195 对照：修复前 first win 后 a50r=0（重复）；q2197 修复后 a50r=1、second battle→267

## marker/状态
- **`[BUILD] R311-a49-once`**
- 槽1只读8880；槽2=场外锚点；开发未开窗/未实机（用户自己测）
- 文档本文件
