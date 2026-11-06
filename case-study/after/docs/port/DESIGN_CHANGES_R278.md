# R278 scene85 新标注替换（3030 cells）

## 解析结果（project.json，UTF-8）
- 1 层可见，3030 cells；grid origin(1216.362,871.289) u(15.525,8.171) v(15.525,-7.844)
- 按 cell 中心 → map80 slot（旧 `slot_at_pixel` 同算法）：
  - **3030 cells → 2952 个唯一 in-map slot**（78 个 cell 重复映射到同一 slot 或越界；其中越界5）
  - 起点 slot3140 (1088,384) **在集内**；城门 slot3186 (1824,384) **在集内**，无需额外强制
- cell 多边形 20×20 采样、slot 覆盖 >50% 复核：
  - 严格集 **2547 slot**，**不连通**；GAP 约 (1520,528) slot4319 ↔ (1632,496) slot4070，距离约144px
  - 这是网格与 slot 半格错位导致的窄缝；本轮**未硬塞通道/未并入旧1828集**
- 采用**中心映射 2952 slot**替换（符合“同此前 cell center→slot 方法”），4方向像素 BFS：**1088,384→1824,384 连通 PASS**

## 代码
- `S85_WALK_BITS_B64` 已由旧 union1828 **替换**为新标注中心集（2952 slot，非并集）
- boot exit0，无 SCRIPT ERROR

## 覆盖图（给用户）
- `round78/map80_s85_replace_full.png`（2064²）：绿=新可走2952；蓝=起点，黄=城门；红=严格>50%复核的GAP（仅提示）
- `round78/map80_s85_replace_zoom.png`（2400×1536，1.5x）
- `round78/map80_s85_replace_gap_zoom.png`（严格覆盖集GAP放大3x）
- 解析数据 `map80_replace_analysis.json`、`map80_s85_replace_center.b64`

## headless 路线（用户最新槽1 0C276D75 只读副本→槽2；随机战临时屏蔽仅路线验证）
- scene85 (560,472) HUD evt1583 **N132**
- → scene106 (224,1072) **N6** → scene109 (672,1888) **N170** → scene118 (640,1672) **N0 SPACE**
- → scene140 (480,1808) **N276** → scene139 (1552,1432) **N16**
- → 真实剧情门/六脚蜘蛛脚本战（lose）→ 败后剧情 → **scene141 (1344,1328)，a36=1，maxidx=1**
- q2024: `scene=141 pos=(1344,1328) moves=551 dialogs=37 HUD= a36=1 maxidx=1`
- 说明：q2024 以 A34 完成/A35 前置状态进入；A34/A35 具体剧情节点仍以 tester 实机为准，路线可通
- N表：85 N132→106 N6→109 N170→118 N0→140 N276→139 N16→141

## 状态
- 槽1 `0C276D75…` 只读未变；槽2=该用户档副本；未开窗
- 用户上机验证：新绿集是否与预期一致；严格>50%复核GAP是否需要补画
