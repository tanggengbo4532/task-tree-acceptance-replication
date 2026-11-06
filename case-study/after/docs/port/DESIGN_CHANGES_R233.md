# R233 A48 黑苗王宫（找灵儿）接线

## 数据
- scene247（南诏）onEnter 32455；
- **evt4365 (896,1152) mode6 脚本32753**：脚本内 `0x59 255` → **scene255 黑苗王宫**；
- scene255 onEnter **32787**（A48 剧情）；scene255 map193，事件4466→249、4467-4482 NPC；
- A48 常量：`A48_PALACE_SCENE=255`、`A48_TALK_SCRIPT=32787`。

## 实现（R233-A48-1）
1) c3 scene247 → **evt4365「第7章 G1：去黑苗王宫（找灵儿）」**（真实 mode6 门，N0/空格触发）；
2) evt4365 真实脚本32753 播前置对白后 `0x59 255` → 黑苗王宫；
3) `load_scene(255)` 且 a47_stage>=1 → **a48_stage=1**；
4) HUD 引导列表加255；不伪造门。

## headless
- scene247：HUD target **evt4365 N=92 方向↑**；
- 到点 SPACE → dlg=true（前置对白）；对白推进后 **scene255 (1680,1720)，a48_stage=1**；
- boot exit0；槽1/槽2 未写、未开窗。

## 锚点（团队槽2 备份/恢复）
- `round78/slot4_scene247_beforepalace_anchor`：scene247 (896,1104)，a47=1（王宫门前）
- `round78/slot4_scene255_palace_anchor`：scene255 (1680,1720)，a48=1（黑苗王宫内）

## tester
- scene247 跟 HUD 到 evt4365 → SPACE → 前置对白 → scene255 黑苗王宫；
- 下一步：A49 拜月教主/水魔兽最终战（scene255→253，脚本33561/evt4442）接线。
