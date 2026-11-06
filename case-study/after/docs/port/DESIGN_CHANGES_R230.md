# R230 A44 凤凰蛋 boss + A45 麒麟洞接线

## 原版数据核对
- A44 boss 脚本 **26192（evt3117）**：`0x4a 17` 设战场、`0x45 42` 战斗音乐、**`0x7 battle team=203`**；
- Data.mkf team203 = object464 → enemy67：**「凤凰」health=3000, exp=5290, level=33, atk=0, def=0**（原版数据，非调试值）；
- 脚本战后 `0x59 189` → scene189（树洞），HUD `树洞：按空格去麒麟洞（第6章 F3）`；
- A45 常量 `A45_CAVE_SCENE=207` 火麒麟洞；scene207 HUD `火麒麟洞圣地` / a45后白苗族大厅。

## 实现（R230-A44A45-1）
1) **scene185（a43_stage>=1）**：
   - 提示「按空格深入神木林（凤凰蛋/树洞）」；
   - SPACE → `a44_started=1`，调用**真实 A44 脚本26192（evt3117）**：原版战场/凤凰 boss 战；
   - 战后脚本自动 `0x59 189`；`load_scene(189)` 且 a44_started → **a44_stage=1**；
2) **scene189（a44_stage>=1）**：
   - 提示「按空格前往麒麟洞（第6章 F3）」；
   - SPACE → `a45_stage=1`、`loaded_from_save=false`、真实 `load_scene(207)` 火麒麟洞，显示 a45 goal；
3) 不伪造战斗数值/不跳过 boss；全部原版脚本/场景。

## headless
- scene185：prompt「按空格深入神木林」→ SPACE → **in_battle=true，a44_started=1**（凤凰 team203）；
- scene189：prompt「按空格前往麒麟洞」→ SPACE → **scene207 (1024,1600)，a45=1**，HUD「已到火麒麟洞：进白苗族大厅/找线索」；
- boot exit0；槽1/槽2 未写、未开窗。

## 锚点（团队槽2 备份/恢复）
- `round78/slot4_scene185_forest_anchor`：scene185 (736,1152)，a43=1（凤凰蛋 boss 前）
- `round78/slot4_scene189_treehole_anchor`：scene189 (1248,1104)，a44=1（树洞）
- `round78/slot4_scene207_qilin_anchor`：scene207 (1024,1600)，a45=1（火麒麟洞）

## tester
- 从槽2 到 scene185 → SPACE 触发凤凰蛋 boss（team203 凤凰 3000 HP），战后自动 scene189；
- scene189 SPACE → scene207 火麒麟洞；
- 下一步：A45 guard/girl 剧情脚本29122/29306、A46 白苗族大厅。
