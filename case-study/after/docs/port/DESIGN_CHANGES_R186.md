# R186 scene77 锚点档 + 遭遇压力调整

## 1) scene77 锚点测试档（不写游戏存档目录）
从团队槽2（scene70）headless 到 scene77 虚拟沿 HUD 路线 N=50：
- 锚点坐标：**scene77 (832,704)**，HUD target evt1428，**N=50**；
- 文件（从团队槽2复制、只改 scene/viewport/vars；队伍/物品保持槽2）：
  - `_playtest_regress_dev/round78/slot4_scene77_near_evt1428_anchor.sav`
  - `...json`（vars 补 a30_s69_phase=2，其余保持）
- tester 可复制到空闲槽（备份/确认）读档，预期 HUD N=50；沿石砖路走 50 步 N=0 到 evt1428，SPACE→scene68。

## 2) 遭遇压力调整（R186-S77PRESSURE-1，用户曾批准遇敌过频可修）
- scene77 普通可见遭遇（evt1429-1438）：
  - **全部取消追击**（auto_script=0；仍可在触发圈内触碰）；
  - **一半普通遭遇收起**（偶数索引 state=0），保留约5个；
  - Boss/剧情事件不在此范围，不受影响；
- 战后脱战宽限延长：
  - 普通胜利后 **20s** 内不再被普通遭遇拉战（原5s）；
  - 逃跑后 **30s**（原10s）；
  - `battle_guard_check` 仍只拦 `flee_disabled=false` 的非Boss战。
- 目标：Lv11-12 沿 690 步允许打几场，但不再连续全灭。

## 3) 验证
- scene77 入口 HUD N=690，静态路径 690→0 已由同源 BFS 验证（R185）；
- 锚点档位置由同一场虚拟走 640 步到 N=50 得到，未写游戏槽；
- boot exit0；槽1/槽2 未写、未开窗。

## tester
1. 锚点档：N=50→0→evt1428→SPACE→scene68；
2. 全程档：从用户18:25 scene70 出发，观察遭遇场次是否明显下降、能否走完；FAIL 给坐标/截图。
- 下一批继续 scene68/78/79。
