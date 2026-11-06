# R110 第3章：scene54 韩医仙家（A25 自动对白）与回程路线

## 1) 卡点结论：不是家具/局部极小，是 A25 剧情自动对白正在播放
- scene54 进入落点 **(1280,880)**；`_update_a25` 会在 scene54 **玩家空闲约 1.2 秒后自动启动 A25 求医对白**
  （脚本 A25_TALK_SCRIPT=10081；`player_busy=true`、vm active、dialog 显示）。
- 对白播放期间**四向移动被剧情锁住是预期行为**；此时应 **按 SPACE 翻页/跳字**（实测约16次），
  对白结束后 `a25_stage=1`，HUD 自动变为「韩医仙家：回白河村找糯米（第3章）」。
- headless 实测：进入 scene54 后 dialog=true/busy=true/vm=true；SPACE×16 后 a25_stage=1、dialog=false，
  HUD 目标变为 evt904 (1312,896)，↓ 剩2格；下走2步到 (1280,896) 后 SPACE → scene53 落点 (896,832)。
- 因此 tester 报「U N=-1 被拒、R/D 反增、L 被拒」是**对白锁输入时的方向/刷新时序**，不是道路阻挡；
  先 SPACE 结束对白再走即可。

## 2) scene54 确定性 keyseq
文件：`_playtest_regress_dev/round82/keys_r110_16_scene54_a25_evt904.txt`
（SHA256 `3BFD428A24AD357E54793F952F8CF036B110BDE5913085589729F173744F7EE4`）
- 进入 scene54（evt886 SPACE）后站在 (1280,880) 等待约1.2s → 自动对白开始 → **SPACE 反复翻页**（文件示例 SPACE×16，
  以对白关闭/HUD变“回白河村找糯米”为准）；
- 对白结束后 `D×1 (1280,880→888) N2→1`、`D×1 (888→896) N1→0`、`SPACE` → **scene53 落点 (896,832)**（evt904）。
- 若 1.2s 后没有自动对白：再等 1~2 秒/站定不动；仍无则记录 dialog/busy 与截图（旧进程未热更需重启）。

## 3) 之后链路：scene53 回白河村找糯米
- a25_stage=1 后 `_c3_scene_step(53)` 指向回程门 **evt885 (384,1280)**（mode5 SPACE → scene50 落点 (1600,720)）。
- 文件：`_playtest_regress_dev/round82/keys_r110_17_scene53_return_evt885.txt`
  （SHA256 `F266B4DC9743A32A460C4B1329719BCE72AA217674F5A3B6BBDF72231BADB332`）
  - 起点 (896,832) → evt885 ring48：共 **86 步，N 86→0**；末行 SPACE。
- 回白河村后 HUD 指向 evt833「打听糯米线索」；按提示 SPACE 对白 → 糯米 item76/a26_clue=1，
  HUD 切回韩医仙家（evt803）→ scene53 evt886 → scene54 交药引（a26_stage=1）→ 出村将军冢。

## 4) HUD 修正
- `_c3_scene_step(54)` 首次显示改为「韩医仙家：求医（自动对白，按空格翻页）」（原“走近触发”会误导玩家找触发点）。
- 对白完成 a25_stage=1 后显示「韩医仙家：回白河村找糯米（第3章）」→ evt904；
  a26_stage=1 后显示「韩医仙家：回白河村（出村前往将军冢）」。
