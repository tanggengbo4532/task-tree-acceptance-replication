# R194 scene80 线索2/夜间入口：SPACE 提示只在 N=0 出现 + scene83 入口锚点

## 复现
- 团队槽2 vars：a31_stage=1、a32_clue1=1、a32_clue2=1、a32_stage=1；
- scene80 evt1501=(432,1192) 脚本13230 是真实 **→scene83** 门（mode5/state2）；
- headless 在 N=0 位置 (416,1192) 按 SPACE：**成功进 scene83**，HUD 切「前往客栈（夜间前置）」target evt1548 N77；
- 在 N≈5 时提示「按空格打听…」若提前按 SPACE，会触发 NPC 对话/未到门环，造成“只弹掌柜对话、不推进”的观感。

## 修复（R194-A32N0-1）
- scene80 evt1505 线索2、scene83 evt1557 线索1 的 SPACE 提示条件增加 **`_a14g_left == 0`**：
  只有 HUD 真实 N=0（到 NPC 触发环）才提示；N>0 只显示方向/N，避免提前按 SPACE 弹对话卡流程。
- 未改剧情/脚本/地图。

## scene83 入口锚点档（不写游戏槽）
- `_playtest_regress_dev/round78/slot4_scene83_entry_anchor.sav/.json`
- scene83 落点 **(1008,1024)**，vars 保持团队槽2（clue1/clue2 已得、a32_stage=1）；
- 读档预期 HUD「前往客栈（夜间前置）」target evt1548 N77（随 vars 正常变化）。
- 供 tester 分段验 scene83。

## 验证
- headless：scene80 (416,1192) N0 SPACE → **scene83 (1008,1024)**，HUD target evt1548 N77；
- boot exit0；槽1/槽2 未写、未开窗。

## 下一步
- scene83 白名单+走廊（按当前 c3 target evt1548/后续真实门）→ 85/87/90/94/98。
