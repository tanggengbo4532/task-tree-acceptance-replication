# R198 scene90 后院剧情“无对话”真正修复：0xFFFF 对白同步捕获显示 + 剧情后接出口

## 根因（R197 后仍无反应）
- evt1650 脚本13882 只有 4 条 **0xFFFF 消息**（4612-4615），没有 0x003D/等待翻页；
- 正常 `_start_script` 启动后 VM 在同一 tick 内跑完 4 条消息并结束；当前 VM 0xFFFF 只在“页满/需要翻页”时阻塞，
  因此 **对话框没有稳定显示/瞬间结束**，玩家看到“按空格无反应、无对话”。
- 同时 c3 scene90 永远指回 evt1650，剧情后无下一目标 → 提示循环。

## 修复（R198-S90STORY-1）
1) `a33backyard` 分发改为：
   - `run_script_entry_sync(13882,1650)` 同步捕获 4 条对白；
   - 逐条 `script_dialog` 显示到 DialogBox，设置 `_dialog_tail=true / player_busy=true`；
   - 若捕获为空才回退 `_start_script`；
2) 显示后写 `PALState.vars["a33_backyard"]=1`；
3) c3 scene90：若 `a33_backyard>=1` → HUD 改指真实出口 **evt1649 (768,1248) → scene85**「离开衙门后院（返回街道）」；
4) 未改剧情脚本/地图。

## headless（tester 槽2 29B00E0B → 最新 c5d45425 同位置）
- 读档 scene90 (1040,1112)：HUD「按空格继续查案」N=0，interact=1650；
- SPACE → **dialog active=true，4 条对白已显示**（同步捕获日志：婢女：…主人不在…晚点再来）；
- ENTER/SPACE 推进 → 对话关闭，HUD 切「离开衙门后院（返回街道）」target evt1649 **N=32**；
- boot exit0；槽1/槽2 未写、未开窗。

## tester
- 现场 SPACE 应看到婢女对白；翻完页后 HUD 指向后院出口 evt1649 N32；
- 走到 evt1649 SPACE → scene85，继续查案链。
