# R258 冻结规则最终落地：scene85 cov>50% final50b 461 tile + 全链

## 用户确认
- `map80_final50b` 干净图已确认：461 tile、4方向连通、无 GAP；
- 规则冻结：cov>50% 可走，其余不可走；起点/终点 forced；
- 不改地图/不铺路/不空格跳场景；保留 C 桥门 scene106↔109。

## 代码落地
- `S85_WALK_BITS_B64` = final50b **461 tile**（主蓝笔+城市门蓝路+用户终点补画合并，cov>50 ∪ forced）；
- `_s85_ground_cell_ok` / `_is_obstacle` / `_walk_target_ok` 三处同源使用该位图；
- 读档/落点救援：旧起点/不可走落点→frozen 同分量锚点(528,568)；
- 复命锚点(480,528)、A35锚点(592,472)、scene89→85复命落点救援；
- 未改 map80 底图、未运行时铺 tile、无空格跳场景；
- boot exit0，无 SCRIPT ERROR。

## headless N 表（槽1 CB1A22F7 只读）
| 段 | HUD/N | 结果 |
|---|---|---|
| scene85 载入 | 救援(528,568) | A34 目标 evt1578 **N68** ↑ |
| scene85→91 | **N68** | 到点 N0→SPACE→scene91(816,1224) |
| scene91 | **N34** | →scene93(512,1360) |
| scene93 | **N24** | 门 evt1692→SPACE→进屋→NPC→scene82 |
| scene82 | **N49** | 审案 choice IP15388→scene89 |
| scene89 | **N64** | 门→scene85 |
| scene85 复命 | 救援(528,568)，复命 **N6** | 复命/A35 完成 |
| scene85 出城 | **N142**（从起点锚点） | evt1583 N3 from report pos；SPACE→scene106(224,1072) |
| scene106 | 桥门 evt1966 **N6** | SPACE→scene109(672,1888) |
| scene109 | 前向 evt1996 **N170** | N0→SPACE→scene118锚点(640,1672) |
| scene118 | 山口锚点 **N0 提示** | SPACE→scene140(480,1808) |
| scene140 | 山门 evt2346 **N276** | 近门N0 SPACE（q1995验证）→scene139(1552,1432) |
| scene139 | 山门 evt2342 **N16** | N0→scene141(1344,1328)，a36=1（q1992验证） |

- 场景序列：85→91→93→82→89→85→(出城)106→109→118→140→139→141
- 说明：scene140 的长路 N276 已由 HUD 给出；自动 loop 到 N237 因迭代上限停止，门段用 q1995 从近门点验证 N0→scene139；tester 实机按 HUD 走 N276。

## 文件
- 位图：`map80_final50b_walk.b64`（461 tile；代码内置）
- 清洁图：`map80_final50b_full.png` / `_zoom.png`
- 报告/数据：`map80_final50b_report.md`、stats
- 本文件
