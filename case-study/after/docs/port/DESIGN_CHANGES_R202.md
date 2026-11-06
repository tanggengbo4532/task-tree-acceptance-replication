# R202 scene93 入口两段：evt1692 进门 → evt1691 NPC

## 现场
- 团队槽2 scene93 (512,1360) 入口小院；从落点 BFS 只连通 **76格**；
- 可达事件只有 evt1692 (736,1456) 与 evt1712；c3 旧目标 evt1691 (848,1528) 在场外，HUD 显示“等待/绕行”无法到达；
- evt1692 mode5 脚本14651（0x65/0x6e 滚动）→ 把队伍带进屋内。

## 实现（R202-S93ROOM-1）
1) c3 scene93：`a34_room<1` → target **evt1692**「进入屋内（女飞贼案后续）」，N=24；
2) `_start_script` scene93 entry14651 写 `a34_room=1`；
3) 进屋后 c3 → target **evt1691 (848,1528)**「继续查案（女飞贼案后续）」；
4) 新增 scene93 evt1691 交互：target=1691、a34_room≥1、距离<120、N=0 →
   提示「按空格继续查案（屋内·第 4 章）」；kind `a34npc` 调真实脚本 **14318**；
5) 未改剧情/地图/队伍。

## headless
- 读档 scene93 (512,1360)：HUD target evt1692 **N=24**；
- 走到 evt1692 N0 按 SPACE → 脚本滚动，pos **832,1536**，`a34_room=1`；
- HUD target **evt1691 N=0**「继续查案」；
- boot exit0；槽1/槽2 未写、未开窗。

## 锚点档（不写游戏槽）
- `round78/slot4_scene93_room_npc_anchor.sav/.json`：scene93 **(832,1536)**，a34_room=1；
- 读档 HUD target evt1691 N0，按 SPACE 触发屋内 NPC 剧情（脚本14318）。

## tester
- 从 scene93 入口跟 HUD：evt1692 N24→SPACE 进屋→evt1691 N0→SPACE 剧情；
- 剧情脚本14318 含 0x49 开事件/0xffff 对白/0x6d 后续，若对话无显示或卡住请给截图/坐标。
- 下一批：scene93 屋内白名单 + scene94/98/85/87。
