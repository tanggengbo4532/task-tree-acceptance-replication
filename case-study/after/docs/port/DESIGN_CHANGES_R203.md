# R203 scene93 审案后续接 scene82 + 锚点 .sav-only 修复

## 1) scene93 剧情14318 后续（真实数据）
脚本14318：0x49 开事件1594-1599 → 0x6d 设置 scene85 进场脚本14553 → **0x59 85**；
scene85 的进场脚本14553 再 0x59 **82**，最终队伍落在 **scene82 (1504,1008)**；
headless：SPACE 14318 → 连续翻页 → scene82，HUD 旧提示残留（c3 原无82）。

## 2) 修复
- c3 新增 **scene82 → evt1683 (928,1328) mode6 脚本15383**「继续审案（女飞贼案后续）」；
- 新增 scene82 evt1683 SPACE 交互（target=1683、距离<120、N=0）→ kind `a34case` 真实启动脚本15383；
- 把 82 加入 c3 引导场景列表；
- **scene93 锚点 .sav-only 修复**：c3 scene93 不再只依赖 vars `a34_room`，
  若队伍坐标距 evt1691 <160 也直接指 evt1691（锚点只复制 .sav 也能正确进屋）。

## 3) 锚点档（不写游戏槽）
- 已有 `slot4_scene93_room_npc_anchor`（scene93 832,1536）：**.sav-only 也有效**，读档 HUD target evt1691 N0（headless 已验，room=NA 仍正确）；
- 新增 `round78/slot4_scene82_evt1683_anchor.sav/.json`：
  scene82 **(1504,1008)**，a34_stage=2；读档 HUD target **evt1683 N=72**。

## 4) headless
- scene82 从 (1504,1008)：HUD target evt1683 **N=72**；
- 静态走到 (992,1328) **N=0**，interact=1683，prompt「按空格继续审案」；
- SPACE → **对话打开**（dlg=true，脚本15383 启动）；
- boot exit0；槽1/槽2 未写、未开窗。

## tester
- 读 scene82 锚点：HUD evt1683 N72→N0→SPACE 审案对话；
- scene93 锚点：现在直接 HUD evt1691 N0，SPACE 剧情。
- 下一批：scene93/scene82 白名单 + 85/87 收尾。
