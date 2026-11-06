# R135 scene56 A30 HUD + scene56→68 分段路线

## 现场
- 槽2（sha `F7F6F3F5…`）：scene56 绝对 (1728,1488)，a28_stage=1，a29/a30 未写。
- scene56 HUD 原为空：`_build_merged_guide`/`_a19_c3_guide_active`/floor 的 scene 列表未包含 56/71/69/70/77/68；
  目标场其实已建好（target evt934, N312），只是文案不显示。

## 修复（world.gd R135-A30CHAIN-2）
- 把 A30 后段场景 **56/71/69/70/77/68** 加入：
  - `_a19_c3_guide_active()` 场景列表；
  - `_build_merged_guide` 的 c3 分支列表（显示目标/方向/N）；
  - “暂无导航目标”兜底列表；
  - `_update_floor_label` 新增 56/71/69/70/77 与 68 的 floor 文案。
- scene56 实测：floor=`第 3 章后段：沿村道前往扬州方向`；
  guide=`目标 第 3 章后段：经韩医仙家外前往扬州方向｜下一步按【↓】键 · 剩 312 格`（target evt934）。

## 分段路线文件（`_playtest_regress_dev/round82/`，按地图一段）
| 文件 | 起点 | 终点（门环） | 步数 | SHA256 |
|---|---|---|---|---|
| keys_r135_55_scene56_a30.txt | scene56 (1728,1488) N312 | evt934 (208,1512) N0 | 312 | `820E9A768C0D4E753999ACF19630F8460440563BC935BCB88E4B8A4E81C8AFE9` |
| keys_r135_56_scene71_a30.txt | scene71 (1632,720) N206 | evt1380 (1568,1024) N0 | 206 | `522AA4ECBC396DAF727FB59B62D3898A3EA21F88FDAC6EA11E2250728710AC32` |
| keys_r135_57_scene69_a30.txt | scene69 (1696,1728) N414 | evt1368 (592,520) N0 | 414 | `9A3B538A82132BD29E90D421F2DD8A22CFC1324B0043254BD40465A2ADBAA29E` |
| keys_r135_58_scene70_a30.txt | scene70 (560,1848) N254 | evt1372 (1456,808) N0 | 254 | `52462BE577AF8335355D6141C88ACC3B9BCAD47584BC1FBF222470B02500E825` |
| keys_r135_59_scene77_a30.txt | scene77 (976,1880) N690 | evt1428 (448,496) N0 | 690 | `53B83B14328AA155C9555C895E9E927A3B865AED6B0C0766F2CE80A75EE0A009` |
| keys_r135_60_scene68_a30.txt | scene68 (816,1704) N154 | evt1343 (1280,1024) N0 | 154 | `FF6C596E466EB59B5E2B21EC3001FD9F2114DFCE557BA292DFDF2D597D895C46` |

- 每张地图段末在目标 SPACE 门圈内，**按 SPACE → 下一张图**；下一段文件起点的落地坐标已写入文件头。
- scene68 段末 evt1343 是土灵珠剧情 trigger（脚本12655，mode7 走近触发）：到 N0 圈内后继续向目标靠近，触发真实战斗/对白；位置不变，剧情后进入 **scene78 扬州**。
- 途中遇怪：打赢/逃跑后位置不变，继续按当前坐标下一步；开放水面不可走。
- 每键 keydown+keyup、按后等坐标变化或 >=220ms；每10步 OCR 核对；N 每步应 −1。
- 生成方式：headless 用槽2 载入，逐图取真实 `_a19g_dist` BFS 路径（每步 N 严格−1），并用 SPACE 实际过渡验证落点；
  共 6 张图，文件名按地图段给 tester 顺序执行。

## 后续 scene78（扬州）
- 真实入口：scene68 evt1343 脚本12655 → scene78 (map24)，onEnter 脚本12820；
- A31 维护代码已在 world 中（scene78/79 到达扬州城触发），等 tester 到 scene78 后再出 A31 引导/路由。
