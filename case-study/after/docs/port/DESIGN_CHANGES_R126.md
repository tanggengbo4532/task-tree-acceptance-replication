# R126 HUD 地名统一「将军冢」

## 审计结果
- 全工程 `proj/game`、`proj/pal` 源码中**没有**「将军家」字面量；scene50/相关场景的 HUD 文案本来均为「将军冢」：
  - 中央：`第 3 章：出村前往将军冢`
  - 右上：`第 3 章：按空格出村 → 将军冢方向`
- headless 槽1（scene50 1120,720）实测：
  - guide=`目标 第 3 章：出村前往将军冢｜下一步按【↓】键 · 剩 538 格…`
  - floor=`第 3 章：按空格出村 → 将军冢方向`
- 用户/tester 看到的「将军家」很可能是小字号下「冢/家」字形近似（冖/宀+豕）造成的**读图/OCR 误读**，或旧构建/旧缓存文案。

## 防御性修复（world.gd，R126-NAME-1）
- 新增 `_hud_name_fix(s)`：任何来源文案中的 **「将军家」/「将军塚」统一替换为「将军冢」**；
- 应用于全部 HUD/提示显示入口：
  - 中央 guide（`_hint_label`，含 `_build_merged_guide` 结果）
  - 右上地点/方向（`_floor_label`）
  - 场景进入提示（`_show_scene_hint`）
  - 交互提示（`_show_interact_hint`）
  - 所有 `_show_a*_goal` 目标提示
- 不改变任何游戏逻辑/路线/地图判定。

## 验证（headless）
- boot exit0；无 SCRIPT ERROR。
- 槽1 scene50：guide/floor 均显示「将军冢」；
- `_hud_name_fix("出村前往将军家方向")` → `出村前往将军冢方向`；`_hud_name_fix("将军塚")` → `将军冢`。
- 槽1/2 未写；未开窗。
