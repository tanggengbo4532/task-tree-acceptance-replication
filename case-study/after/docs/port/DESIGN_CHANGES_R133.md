# R133 A30 后段真实链引导（scene50/55 → scene68 → 扬州）

## 现场
- tester4 已从槽1 走完 scene58→55→evt924→scene50（2 场真实战斗）。
- 槽2 最新 sha `BC97964…`：scene50 (960,624)，`a28_stage=1`，a29/a30 未写。
- 旧 HUD 仍指「出村前往将军冢」回桥头，A30 未推进。

## 真实链（Sss 事件脚本核对，事件号=数据下标+1）
- scene58 → scene55：evt945 脚本11114（已通）。
- scene55 → scene50：evt924 脚本9683（已通，回村）。
- **A30 后段去扬州**：
  - scene50 → scene55：evt802 脚本9712（同一座石桥，A28 后改为 A30 第一段）
  - scene55 → scene56：evt926 脚本9688
  - scene56 → scene71：evt934 脚本10237
  - scene71 → scene69：evt1380 脚本12571
  - scene69 → scene70：evt1368 脚本12565
  - scene70 → scene77：evt1372 脚本12615（或 evt1373）
  - scene77 → scene68：evt1428 脚本12631
  - scene68 → scene78（扬州）：evt1343 脚本12655（A30_TALK）
- 另：A29_BOSS_EVT=1049 在 scene60，不在当前 50/55 链上；先不阻塞 A30。

## 修复（world.gd，R133-A30CHAIN-1）
1) `_c3_scene_step(50)`：a28_stage≥1 → **evt802「第3章后段：出村前往扬州方向（经白河村外）」**；floor 同步。
2) `_c3_scene_step(55)`：a28_stage≥1 → **evt926「第3章后段：经村道前往扬州方向」**；floor 同步；不再指 evt924 回村循环。
3) 新增 scene56/71/69/70/77/68 的 A30 门引导（上表 evt）。
4) scene50 石桥 guide 文案按 a28 分支显示「第3章后段：出村前往扬州方向（过小桥触发）」。

## headless 验证
- 槽2 载入 scene50：floor=`第 3 章后段：走过小桥出村 → 扬州方向`；
  guide=`目标 第 3 章后段：出村前往扬州方向（过小桥触发）｜下一步按【↓】键 · 剩 44 格`。
- scene55 (416,544)：floor=`将军墓外：按空格出村 → 扬州方向（第 3 章）`；
  guide=`目标 第 3 章后段：经村道前往扬州方向｜下一步按【↑】键 · 剩 138 格`（target evt926）。
- boot exit0；槽1 只读、槽2 可覆盖；未开窗。
- 跨 7 张地图的完整 268? 步 keyseq 尚在生成（单图分段），先让 tester 用 HUD 走到 scene56，随后补每张地图的分段文件。
