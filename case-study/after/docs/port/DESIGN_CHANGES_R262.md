# R262 scene85 并集1828 落地（用户 MapAnnotator 新增）

## 数据来源（用户最新槽1）
- 用户最新槽1：`pal_save_1.sav` SHA256 前缀 **14B5CFBD7A56D5B9**（09:15:08，只读，未写）
- 旧 CB1A22F7 已被用户覆盖，不再引用
- 只读副本已复制到团队槽2：`pal_save_2.sav` **14B5CFBD…**（原团队槽2 `12DEA6A6…` 备份到 `_playtest_regress_dev/round78/save_backup/`）
- MapAnnotator 工程：`_playtest_regress_dev/round78/map_annotator_project.json`（v2.1，UTF-8）
  - 1图层 `可走` / `可走tile` / `#2ea8ff`；cells **1542**
  - image `map80_allwalk_full.png` 2064×2064，与 map80 世界像素 1:1
  - grid origin(786.305,689.604) u(14.5,7.625) v(14.875,-7.75)
- 解析映射：cell center→`slot_at_pixel`（h0/h1），并用 cell 多边形覆盖>50% 复核：
  - 用户可走 slot **1382**（h0 696/h1 686）
  - 当前冻结461：交集15 / 用户新增1367 / 当前独有446
  - **并集 = 461 ∪ 1382 = 1828 slot**（去重）
  - 4方向像素 BFS：起点(1088,384)→城门 evt1583(1824,384) **True**（3656 pixels）
  - 用户集合单独不连通（起点/城门不在绿色内）；并入当前461后连通（共享15 slot 簇 x576..640/y480..520）

## 代码改动
- `proj/game/world.gd`：`S85_WALK_BITS_B64` 更新为 **union1828 位图**
  - 文件：`_playtest_regress_dev/round78/map80_union1828_walk.b64`
  - 强制起点(1088,384)/城门(1824,384)在并集内
  - 移动/障碍/HUD 仍共用同一 bitset 源（`_s85_ground_cell_ok` / `_is_obstacle` / `_walk_target_ok` / `_a14g` 路径）
- 未改其它玩法/地图/无 RUN 时铺路、无空格跳场景、无 auto-win

## 锚点复核（并集位图）
- `S85_START_ANCHOR=(528,568)` slot4513：**inU True**（保留）
- `S85_SAVE_START=(432,1000)` slot7963：**inU True**（用户标注新增覆盖；读档不再强制救援）
- `S85_REPORT_ANCHOR=(480,528)` slot4254：inU True
- 强制起点(1088,384) slot3140、城门(1824,384) slot3186：inU True
- 旧锚点(528,568)仍在集内，保留。

## headless 验证（槽2只读副本 14B5CFBD）
### A34/A35（q2014，真实用户当前状态）
- 读档 scene85 raw(160,112)→救援(720,552)，a34_stage=1；HUD target evt1579 N54
- scene85 **N54**→scene91 **N34**→scene93 **N24**→scene82 **N49**→scene89 **N64**→scene85复命 **N198**（target evt1594）
- A34 done=1、A35 stage=1；结束 scene85 pos(560,472)，HUD 按空格向街坊打听消息

### 出城→141（q2019/q2024；路线验证时临时屏蔽随机遭遇，战斗由 tester 实机）
- 用户最新档实际 A35 完成后 pos(560,472)：HUD evt1583 **N152**（q2023/q2024）
- q2019 从锚点(528,568)起测：**N142**（仅作对照；tester 从560,472实际位置走）
- scene106桥门：**N6**→scene109落点(672,1888)：**N170**
- scene118锚点(640,1672)：**N0**→scene140(480,1808)：**N276**
- scene140 evt2346→scene139(1552,1432)：**N16**
- scene139 door evt2342→scene141(1344,1328)：**a36_stage=1**；最终 **scene141 到达**
- 场景序列：85→91→93→82→89→85→106→109→118→140→139→141

## 卡点（重要）
- q2019/q2024 在 scene139 触发战斗 **“六脚蜘蛛” HP32767**，自动攻击 11/9 回合 **lose**；该战斗未被随机遭遇屏蔽（疑似 `flee_disabled=true`/剧情/固定战），headless 未能验证正常胜利。
- 之后探针仍到 scene141/a36=1，但队伍状态非正常（maxidx=0），不能算战斗 PASS；**tester 实机必须复测该战斗**，若必败/无法逃跑则需单独处理（不 auto-win/不降难度）。
- 其余路线 N/门/场景到达正常。

## 状态
- boot exit0，无 SCRIPT ERROR（改动后）
- 槽1只读14B5CFBD未变；槽2=用户副本14B5CFBD（原团队档备份）
- 未开窗；未改槽1/3/4/5/9
