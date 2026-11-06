# R154 scene55/map59 草地装饰（运行时同 tileset，不改碰撞/路线/N）

## 用户需求
- scene55/map59 村外大草地空旷突兀；用**已有 MAP.MKF tileset、同美术风格**补装饰；
- 只做视觉，不改 blocked/可行走性/事件/HUD N/路线。

## 方案（世界层运行时装饰，不改 MAP.MKF 原文件）
- `world.gd` 新增 `_decorate_map59()`：在 `load_scene` 载入 **scene55 且 map==59** 后，
  把 **map59 自带 tile frame** blend 到已预渲染的 `current_map.bottom` / `current_map.layer_top` 图像上。
- **不修改** `_bottom_index` / `_top_index` / `blocked` / `has_content`，不新增/移动事件；
  因此碰撞、可走格、HUD BFS 距离场、N 全部不变。
- 装饰素材全部来自 map59 自己的 tileset：
  - 草色/土色变体（帧 10/12/14/15/16/20/21/41/49/63/81/82/93/162/193/507）；
  - 小花/草丛/碎石 top overlay（帧 4/13/8/5/11/6/22/39/36/24/52/19/26/54/95/37/85/30/61）。
- 分布：沿用户当前 (160,432) 附近的草地、村道两侧及到 evt926 的走廊布置 16 个装饰簇 + 村道两侧碎石/花簇引导；
  只落在 `_is_obstacle(x,y)==false` 的可站格上，且只写图像、不占用碰撞。
- 注意：top overlay 仅视觉层，角色仍可走过/穿过；没有增加任何“树占格”阻挡。

## 验证（headless，槽1只读）
- 载入用户最新槽1 `4C6B54CA…`：scene55/map59，pos (160,432)，HUD **N=118**、target evt926 不变；
- `_is_obstacle(160,432)=false` 不变；路径/距离场未改（装饰不写索引与 blocked）；
- 装饰前后同位置截图：
  - 前：`proj/docs/port/shots/R154_map59_before.png`
  - 后：`proj/docs/port/shots/R154_map59_after.png`（含 tile 层 before/after top：`R154_map59_after_top.png`）
- boot exit0；槽1 未写；未开窗。

## 视觉说明
- 原版该区域是将军墓外/白河村外村道边缘的开阔草地（数据本身 blocked=0、bottom=草），
  R154 只是在这一片草地上补了同素材的草色变化、花丛、草丛、碎石和小片地被过渡，让视线沿村道向下（扬州方向）有层次；
  不影响任何可达性。
