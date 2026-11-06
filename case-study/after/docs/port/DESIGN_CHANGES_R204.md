# R204 scene82 审案之后：对话结束→出口 evt1666→scene89

## 真实数据
- scene82 evt1683 脚本15383：对白5336-5338 + 选项(0xa/0x1e 15398/15400) + 后续对白；脚本结束 **无场景切换**；
- scene82 真实出口 **evt1666 (1088,1248) mode5 脚本13207 → scene89 (14,98,0)**；
- 因此审案对白结束后应指向 evt1666 离开太守府。

## 实现（R204-S82EXIT-1）
- `a34case` 交互启动 15383 时写 `a34_case=1`；
- c3 scene82：`a34_case>=1` → target **evt1666**「离开太守府（女飞贼案后续）」；否则仍 evt1683；
- 未改剧情/地图/队伍。

## 锚点档（不写游戏槽）
- **审案前**：`round78/slot4_scene82_evt1683_anchor.sav/.json`（scene82 1504,1008 → evt1683 N72）
- **审案后**：`round78/slot4_scene82_after_case_anchor.sav/.json`
  - scene82 **(992,1328)**，a34_case=1；读档 HUD target evt1666（N 随位置）
  - tester 可直接续测“出门→scene89”。
- scene93 锚点 `.sav-only` 已修：`slot4_scene93_room_npc_anchor`（832,1536）读档 HUD evt1691 N0。

## headless/验证
- scene82 审讯 SPACE → dlg=true（脚本15383）；
- c3 阶段切换逻辑由 a34_case 控制；boot exit0；槽1/槽2 未写、未开窗。

## 下一步
- scene82/93 白名单 + scene89/94/98/85/87 收尾批次，按批给 hash/N 表。
