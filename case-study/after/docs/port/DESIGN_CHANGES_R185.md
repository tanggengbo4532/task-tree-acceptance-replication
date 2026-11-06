# R185 scene77 石砖庭院 walkable 白名单（Lead/用户批准）

## 规则
- scene77（map72）石砖庭院：**可见石砖地面可走；石墙/阴影/黑 void 不可走**；
- 不用亮度阈值，用“路线实测 ground id 集 + HUD 路线±48px 走廊”合并，走廊内仍走 native blocked（墙/void 仍挡）。

## 实现（R185-S77STONE-1）
- 石砖地面 id 集（沿 HUD 690 步实测）：
  **0,1,3,4,8,9,15,18,19,20,22,25,26,27,29,37,39,40,41,42**；
- 进图准备 `_a30_s77_prepare()`：
  - 先用 native 可行走从入口落点建 evt1428 场；
  - 沿路径生成 ±48px 走廊（4754 格）；
  - 之后 scene77 可走 =（地面 id 集 ∈ 集 **或** 走廊内）**且** native 非墙/void；
- 非法落点 ground rescue：最近走廊格；
- HUD/N 由同源 BFS；N=0 evt1428。

## headless（用户18:25档 scene70 基线）
- scene77 入口落点 (976,1880)：HUD evt1428 **N=690**，目标场 has=true；
- 静态路径验证：沿场走 **690 步** 到 (448,496)，**N=0、无 stuck（bad=0）**；
- 实按 80 步：N 690→610，无 nomove（禁用遭遇后）；
- scene70→77 的入口/落点使用原版门，未改地图。
- boot exit0；槽1未写、未开窗。

## 说明
- 全 690 步实按在 headless 受随机遭遇/战斗打断（此前 nomove 即战斗弹出）；tester 实机按 HUD 走、遇敌正常打，路径本身已由 static BFS 690→0 验证。
- 下一批 scene68/78/79 同法（渲染+逐格表→白名单+rescue）。
