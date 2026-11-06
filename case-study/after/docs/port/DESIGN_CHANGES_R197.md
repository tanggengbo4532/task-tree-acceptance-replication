# R197 scene90 衙门后院 evt1650 SPACE 无反应修复

## 只读现场
- tester 槽2 `29B00E0B…` 实际是 **scene90 (1024,1104)**（不是 scene85）；
- vars：a32_stage=1、a33_stage=1、a33_stairs=1、a33_down=1，即女飞贼战已结束，进入后院查案；
- HUD target evt1650=(1056,1104)，N=0，但旧提示仅「已到触发点：按空格/走近触发」；
- 原因：**evt1650 mode2 脚本13882 没有 SPACE 交互分发**，`_scan_extra_interact` 没接该事件，所以按 SPACE 无反应；提示也不是 N=0 专用。

## 修复（R197-S90NPC-1）
- 新增 scene90 evt1650 交互扫描：
  - 条件：当前引导目标 evt1650、事件 state>0、距离<120、**`_a14g_left==0`**；
  - 显示「按空格继续查案（衙门后院·第 4 章）」；
- 输入分发 kind `a33backyard`：**真实调用 `_start_script(13882, 1650)`**；
- 未改剧情脚本/地图；N=0 才提示。

## headless（tester 槽2 同位置）
- 读档 scene90 (1024,1104)：HUD「按空格继续查案（衙门后院）」target evt1650 N=0，interact=1650；
- SPACE → **对话框打开**（dlg=true），脚本13882 已开始（不再无反应）；
- boot exit0；槽1/槽2 未写、未开窗。

## tester
- 现场按 SPACE 应进入剧情对话，用 SPACE/ENTER 推进；剧情结束后 c3 会切下一目标；
- 若剧情中途仍卡，请给对话文本/坐标；下一批 scene94/98 + 85/87 白名单。
