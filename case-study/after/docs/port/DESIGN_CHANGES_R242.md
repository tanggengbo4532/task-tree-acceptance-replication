# R242 选择框置顶修复（CONFIRMTOP-1）

## 问题
用户槽1 `4E7BD4EA4E5B84F2DBEDAF7DA69ED3F750836DDC0BCA74047CDFEAF712DD97E0`（scene93，13:43）
推进到太守审案「你招是不招」是/否选择框时，选项框被人物对话/头像 UI 挡住。

## 根因（headless UI 树确认）
- `world._ui` = **CanvasLayer.layer 10**（对白 DialogBox、头像、提示 HUD 全在此层）；
- 脚本 0x000A 的确认框走 `world.request_confirm()` → `PalMenu`，其 `_ready` 固定 **CanvasLayer.layer 5**；
- 因此 PalMenu 整体位于对白/头像层之下：dim + 是/否选项框被 DialogBox 覆盖，只露出上沿，无法读选项/看光标。

## 修复
1. `world.request_confirm()`：`add_child(m)` 后设 **`m.layer = 20`**（高于 `_ui` 的10）；
2. `menu.gd::_rebuild()` 全局规则：
   - 当前栈顶为 `ScriptConfirmController` 或 `ConfirmController` → **layer=20**；
   - 普通主菜单/物品/仙术/状态/系统/存读档 → 恢复 **layer=5**；
   这样对话内所有确认/选择框都置顶，普通菜单层级不变（商店/物品菜单不受影响）。
3. 对话框/头像仍保持 layer10，在选择框置顶时作为背景可读（选择框自带 dim 0.40）。

## headless 验证（用户槽1只读）
- 读档 scene93 (736,1512)，触发脚本 14318；
- 推进到 waiting_choice：`PalMenu.layer=20 > _ui.layer=10`，MenuRoot 640×400 visible；
- 方向键右 + 回车：`waiting_choice=false`，菜单关闭，脚本继续（scene82，pos1504,1008）；
- Esc：`waiting_choice=false`，脚本继续；普通菜单 `layer=5`、kind=main；
- boot exit0，无 SCRIPT ERROR。

## 交付物
- `_playtest_regress_dev/round78/choice_layer_before_after.png`：UI 层级示意图（BEFORE layer5 被盖 / AFTER layer20 置顶；headless 无法渲染真实画面，实机截图由 tester 补）；
- 本文件。
- 代码：`world.gd`（request_confirm layer20）、`menu.gd`（_rebuild 确认框 layer20 / 普通菜单 layer5）。

## R242-ESCCONFIRM-1：对话/选择框内 Esc 不退出
- 期望：选择框 Esc = 选「否/取消」；对话中 Esc 至少被消耗，不强制结束脚本/打开菜单（用户反馈疑似回标题）。
- 修复：`world._unhandled_input` 的 `KEY_ESCAPE` 分支最前增加：
  - `_dialog_box.is_active()` 或 `vm.waiting_dialog / vm.waiting_choice` 时，**只消耗 Esc**（若 DialogBox 内部 `_choice_active` 则 `confirm_choice(false)`），不再 `_force_end_script()`/`open_menu("main")`；
  - 普通场景（无对白/选择）Esc 仍打开菜单。
- PalMenu 确认框（layer20）的 Esc 仍由 `ScriptConfirmController.handle(KEY_ESCAPE)` 处理为“否”。
- headless 复核（q1914/q1916）：choice 内 Esc → waiting_choice=false、菜单关闭、脚本继续 scene82；对话中 Esc → mode 仍 null、不打开菜单；普通菜单 layer5/kind=main。
- 普通场景复核（q1917）：无对白时 Esc → 菜单 mode=CanvasLayer kind=main layer=5；再按 Esc 关闭回世界；normal Esc 行为不变。
- boot exit0，无 SCRIPT ERROR。

## 槽位
- 槽1只读；槽2未写；未开窗；插件未动。
