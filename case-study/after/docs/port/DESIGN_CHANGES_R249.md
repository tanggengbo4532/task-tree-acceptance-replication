# R249 进度一卡住修复（S93DOOR-1 / S82TARGET-1 / S85POSTRESCUE-1）

## 用户槽1
`CB1A22F7…`（11-03 00:40，只读）：scene85，存档落点 (432,1000) 墙顶；HUD target(1152,432) N68；busy=false、无对白/菜单。

## headless 定位
1. 载入槽1：R248 救援锚点应到 (480,544)；但部分场景门脚本在 `load_scene` 之后用 0x0046 把队伍重新放回旧起点 (432,1000)，R248 的 load_scene 末尾救援被覆盖 → HUD N0/等待、角色卡住。
2. 继续跟 HUD 自动推进：scene85→91→93→82 后发现两处路线断点：
   - **scene93**（屋内）：从 scene91 门脚本落点 (512,1360)，c3 目标 evt1691 实际是屋内 NPC(848,1528) 障碍/不可达，HUD 为空；屋内门 evt1692 脚本14651 在 (736,1456) 才可进屋。
   - **scene82**（太守府）：a34_case 未完成时去审案 evt1683(928,1328) 会路过出口；旧 near82 兜底把 HUD 目标切到出口 evt1666，SPACE 直接去 scene89 跳过审案。

## 修复
1. **R249-S93DOOR-1**：
   - scene93 若队伍不在 NPC 附近（<300），c3 目标先指屋内门 evt1692，HUD 锚点固定 (736,1456)；
   - 新增 evt1692 交互（SPACE → 脚本14651 滚动进屋，kind=a34enter）；
   - 进屋/靠近 NPC 后 c3 切回 evt1691 NPC 脚本14318。
2. **R249-S82TARGET-1**：scene82 只有 `a34_case>=1` 才指出口 evt1666；未完成审案始终指 evt1683，避免路过出口被切目标/跳过。
3. **R249-S85POSTRESCUE-1**：scene85 空闲帧再次调用 `_s85_wall_rescue()`，修复门脚本 0x0046 把队伍放回旧起点覆盖救援的问题。

## headless（用户槽1只读）
| 顺序 | 结果 |
|---|---|
| 载入 | scene85 → 救援 (480,544)；HUD target(1152,432) N68 |
| 实走 | 68步 N0（1120,432），blocked0 |
| SPACE | scene91 (816,1224) N34 |
| 继续 | scene93 门 HUD N24→24步→SPACE进屋→NPC对话→scene82 审案 |
| 审案 | 选择框 IP15388（是）→ scene89 → scene85 复命 evt1594 N30 |
| 复命 | scene85→scene100 对话链（自动跟随仍在继续测，当前到 scene100/复命循环） |

- boot exit0，无 SCRIPT ERROR；槽1 hash 未变 `CB1A22F7…`；槽2未写。

## 槽位
- 槽1只读；槽2未写；未开窗；插件未动。
- 文档：本文件。
