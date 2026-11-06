# R254 用户批准 2：补可见路廊到 evt1583 + C 新增 scene106↔109 门

## 用户决定
- 用户否决 evt1581 替代门，要求保留 **scene85 evt1583(1824,384)→scene106**，并补一段**真实可见路廊/桥**到 evt1583；
- 保留用户批准 C 的 **scene106↔scene109 新桥门**，后续真实链 109→118→140→139→evt2342→141。

## 实现
### 1. S85 可见石路廊（R254-GATE1583）
- 在当前 S85 可走集（A35 后附近）到 evt1583 之间铺 **tile_id=4 同风格石面**（运行时改 map80 的 bottom/top 图与 `_bottom_index/_top_index/blocked/has_content`，**不改 MKF 底图**）。
- 路廊 tile 坐标（27 格，x,y）：
  `(39,32)→(40,32)→…→(57,32)→(57,31)→…→(57,24)`
  - 完整表：`s85_gate_road_tiles.json`
  - 说明：从 (39,32) 现有街面出发，沿东侧铺石面到城楼前，再向北石阶到 evt1583(1824,384)；均为可见路廊，不隐形开墙/水/void。
- before/after：`map80_gate_road_before_after.png`；after单独：`map80_gate_road_after.png`。
- 路廊 tile 写进 `S85_WALK_BITS_B64`（473 tile），HUD/移动同源。

### 2. scene85 出城门恢复 evt1583
- c3：a35_stage>=1 且 a36_stage<1 → target **evt1583**，HUD「前往蜀山（出城·新路廊）」；
- evt1581 恢复原语义（→scene100），不再作蜀山替代门；
- evt1583 真实脚本15459 → scene106(224,1072)。

### 3. 保留 C 新增门
- scene106 桥左端 evt1966(160,1104) → scene109 花园桥(672,1888)；
- scene109 花园桥反向门 → scene106；
- 后续原版真实门：109 evt1996→118；118 evt2152 锚点(640,1672)→140；140 evt2346→139；139 evt2342(真实事件脚本21692)→141。

## headless（槽1只读，分段实测）
| 段 | HUD/N | 结果 |
|---|---|---|
| scene85 (480,544) | 「出城·新路廊」**N128**→ | 走128步到 evt1583，SPACE→scene106(224,1072)（q1993） |
| scene106 | evt1966 **N6**→ | 新桥门→scene109(672,1888)（q1986） |
| scene109 | evt1996 **N170**→ | scene118(256,1872)（q1986） |
| scene118 | 锚点(640,1672) N?→ | SPACE→scene140(480,1808)（q1990，入口到锚点路径已在可走图） |
| scene140 | evt2346 **N276**→ | 真实门→scene139(1552,1432)（q1995 到 N0/触发） |
| scene139 | evt2342 **N16**→ | 真实事件脚本21692→scene141(1344,1328)，a36=1（q1992 已验证） |

- 视觉路廊补图/不伪造：`map80_gate_road_before_after.png`
- boot exit0，无 SCRIPT ERROR；槽1 hash `CB1A22F7…` 未变；槽2未写、未开窗。

## tester
1. 读槽1→A34/A35完成后 HUD「出城·新路廊」N128，沿石路廊走到 evt1583，SPACE→scene106；
2. 按 HUD 走桥门→109→118→140（N276 长路）→139（N16）→scene141；
3. 重点检查新路廊视觉/是否穿墙；若路口/落点不对给坐标+截图。

## 文件
- `DESIGN_CHANGES_R254.md`；`map80_gate_road_before_after.png`、`map80_gate_road_after.png`、`s85_gate_road_tiles.json`
