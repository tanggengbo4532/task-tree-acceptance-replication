# R151 将军墓 scene58 出口 evt945 同源兜底（只做该节点）

## 最新现场（用户槽1）
- sha **`DD2EF726…`**（11:11:48），scene58，绝对坐标 **(1504,1848)**，队伍 nparty=2；
- evt945：state=1、mode=5、坐标 (1520,1848)，脚本11114 → scene55（白河村外）；
- HUD：`目标 将军墓：离开将军墓 → 白河村外（第 3 章）｜已到触发点：按空格/走近触发`。

## 复现结论（headless，最新槽1只读）
- `_scan_space_door` 正常布防：`interact=945 kind=space_door prompt=按空格前往`；
- 按 **SPACE → scene55 (416,544) 成功**（复测两次）。
- 当前 HEAD 下 evt945 真实可触发；未复现“按空格无反应”。

## R151 兜底（防止读档/到点保护/提示让位等边缘导致交互未布防）
- 在 `_unhandled_input` 的 SPACE 处理里新增：当
  - `not player_busy`、`_interact_id==0`、`_a14g_key==""`（HUD 已到点）、
  - c3 目标事件 `state>0 && trigger_mode>=4`、有触发脚本、且玩家在其触发环+12 内，
  → 直接 `_start_script(目标脚本, 目标事件)`（与真实门同一脚本），并打印 `[c3] R151-A28EXIT-1 SPACE fallback`。
- 只对 c3 引导目标生效，不影响普通门/其它 SPACE 行为。

## 地图外问题（数据结论）
- 用户脚下 tile：map125 (47,116) h=0，**bottom tile=1（草地菱形）**、top tile=7，**blocked 位=0**；
- 这是原版 MAP 数据本身标记为可走的 exterior 草地（map125 2048x2048，用户位置在墓外草地/道路区域）；
- R150 已修“top overlay 单独把 void 格变可走”；当前脚下是真实 opaque 草地，不是 void/黑底；
- 若用户仍看到“地图外”，需要截图里具体位置/坐标（或脚下 tile），否则无法判断是哪一格；目前数据不支持把 (1504,1848) 草地封掉。

## headless 验证
- 最新槽1 load：pos (1504,1848)，interact=945，SPACE→scene55；
- R151 兜底代码编译通过（boot exit0）；正常门逻辑未变。

## tester4 复测（只测这一节点）
1. 用新 hash 重载最新槽1（DD2EF726…）scene58；
2. HUD 到 evt945 环内 → 按 **SPACE**（或走近触碰）→ 应进 **scene55**；
3. 若仍无反应：记录按空格时是否有 `按空格前往` 小提示/是否读档后未移动/游戏窗口版本 hash；
4. “地图外”若仍有：截一张带小地图/坐标的图（或报脚下 tile），我按具体格修。
