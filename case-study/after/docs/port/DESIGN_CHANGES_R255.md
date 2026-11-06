# R255 方案2 路廊到 evt1583 + tester r245 修复

## 用户批准
- 方案 2：保留 **scene85 evt1583(1824,384)→scene106**，补**可见石路廊**；不用 evt1581 替代门。
- 保留 C：新增 scene106↔scene109 桥门。

## 实现要点
### 1. 可见石路廊（R254-GATE1583）
- 运行时在 map80 铺 **tile_id=4 石面** 27 格（不改 MKF 底图），路径 tile：
  `(39,32)…(57,32)→(57,31)…(57,24)`（完整 `s85_gate_road_tiles.json`）。
- S85 可走位图扩到 473 tile（含路廊/evt1583）。
- before/after：`map80_gate_road_before_after.png`、`map80_gate_road_after.png`。

### 2. scene85 evt1583 出城
- c3 a35_stage≥1 & a36<1 → **evt1583** N128（从480,544实测）；
- evt1583 真实脚本15459 触发后进入 scene106 **桥门落点(160,1104)**（`R255-S85TO106`，便于接新桥门）；
- evt1581 已恢复原语义（→scene100），不再作蜀山替代门。

### 3. tester r245 修复
- **c3 引导场景列表加入 106/109/118/139/140**（所有5处列表），HUD 正常给 N/方向；
- **scene109 前向门 evt1996**：
  - 事件坐标 (1168,1048)，tile (36,65,h1)，center≈(1184,1056)；
  - 原版 mode5 SPACE、脚本15587→scene118；HUD N170，N0 出现「按空格前往」提示；
  - 触发范围=事件 mode5 的环16（游戏交互环内）；
- **scene109 反向门**：仅在 `a36_stage>=1` 且离开桥落点(672,1888) **≥96**、目标不是1996时提示；落点旁不再误触。
- **scene109→118 落点救援**：原脚本15587落点(256,1872)在墙顶，自动救到最近可达锚点 **(640,1672)**；HUD 提示「按空格前往蜀山（山口）」，SPACE→scene140。
- scene106 桥门 evt1966 在落点(160,1104) N0/提示（HUD N 显示可能仍绕行，但交互提示优先），SPACE→scene109。

## headless N 表（槽1只读）
| 场景段 | HUD/N | 结果 |
|---|---|---|
| scene85 (480,544) | 出城·新路廊 **N128** | 走128步→evt1583→scene106桥门(160,1104)（q1993） |
| scene106 桥门 | evt1966，N0提示 | SPACE→scene109(672,1888)（q2001） |
| scene109 | 前往山路 **N170** | 走170步→evt1996 N0提示→SPACE→scene118锚点(640,1672)（q1997） |
| scene118 | 山口锚点 N0提示 | SPACE→scene140(480,1808)（q1990） |
| scene140 | 山门 **N276** | 走N276→evt2346 N0提示→scene139(1552,1432)（q1995到门触发） |
| scene139 | 山门 **N16** | 走16步→evt2342→scene141(1344,1328)，a36=1（q1992） |

- boot exit0，无 SCRIPT ERROR；槽1 hash `CB1A22F7…` 未变；槽2未写、未开窗。

## tester 复测
1. 读槽1→A34/A35→出城 N128 沿石路廊到 evt1583→scene106；
2. 桥门 SPACE→scene109；scene109 HUD N170 前向门，不要在桥落点误按反向门；
3. scene109→scene118 自动救到(640,1672)，SPACE→scene140 N276→scene139 N16→scene141；
4. 反馈：路廊截图、各门 N/提示、是否有卡点。

## 文件
`map80_gate_road_before_after.png`、`map80_gate_road_after.png`、`s85_gate_road_tiles.json`、`DESIGN_CHANGES_R255.md`
