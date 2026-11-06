# R295 用户 MapAnnotator scene185 窄道路线解析并应用

## 用户工程
- `round78/MapAnnotator_scene185_route_area_clean_grid/`
- base：`scene185_route_area_clean_grid.png` 1440×1280（我们的 x640–1360 / y1040–1680，2×裁切）
- grid：origin(894.117,622.99)、u(34.471,17.259)、v(-29.514,16.713)（图像像素，2×）
- layers：1层「图层1」#2ea8ff=蓝=可走/保留，**206 cells**
- 语义：用户用蓝层画出约2格宽的窄道可走带

## 解析
- 图像→地图像素：`map = image/2 + (640,1040)`
- cell 中心→最近地图 slot：**206 cells → 206 unique slots**（无重复）
- slot tile 范围：tx22–42、ty69–95；地图覆盖 x≈738–1369、y≈1113–1532
- 用户画的是 **等距菱形格**；为适配游戏8px/16px移动网格，按 cell 多边形展开成 **439 个移动格点**（x%16=0,y%8=0）
- 文件：
  - `scene185_user_route_slots.json/csv`（slot明细）
  - `scene185_user_route_points.txt`（439可走格点）
  - `scene185_user_route_overlay.png`（绿=用户蓝层，黄框=R292/R293新增格）
  - `scene185_user_route_gridpoints.png`（绿点=实际应用移动格点）

## 应用
- `world.gd` 新增 scene185 用户路线白名单 `S185_USER_WALK_PAIRS`（439格点）；
  - `_is_obstacle` 对白名单返回可走；HUD/移动/救援同源
  - 与已有可走集**合并**（不关闭原有地面）；不改水/void/墙与任务/战斗
- A44 目标点随用户路线端点改为 **(768,1216)**（用户蓝层上的可达点；事件3014仍在736,1200）

## headless（用户档3F7BEFBC只读副本）
```
起始 scene185 pos=(1136,1408) N=104（原路径）
应用用户路线后 → N=63（更直接的路线）
沿HUD走到 pos=(960,1200) N=0
HUD「神木林：已走到凤凰蛋/树洞，剧情触发（第6章F2）」
49步，无 [R293] blocked
```
- 路线连通、N连续递减、到点自动触发A44；无空格/无传送

## 状态
- boot exit0；槽1只读3F7B；槽2=该档副本；未开窗/未实机（用户自己测）
- 改动文件：`world.gd`、round78解析/预览文件
