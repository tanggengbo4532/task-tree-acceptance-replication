# R215 用户最终槽1“无下一节点”修复：scene85 → A34 真实链

## 现场（用户槽1 21277806，07:20:08）
- scene85 **(240,376)**；`a33_stage=1`（女飞贼已完成）；a34 阶段未开启；
- HUD 原文：「目标 第 4 章：返回街道（继续查案）｜下一步按【←】键 · 剩 4 格」target evt1574(176,360) N=4；
- 走到 evt1574 回 scene83 后，scene83 的 c3 对 `_a33_done_state()` 又指 evt1546→85，形成“回街道↔衙门”无明确下一节点。

## 根因
- R199 为防 scene85↔scene90 A↔B 循环，把 scene85 done 分支从 evt1579 改成 evt1574→83；
- 但 A34 真实链现在已接通（R200/R202/R203/R214）：**scene85 evt1579→scene90→evt1650/evt1661→scene91→evt1664→scene93→…**；
- 继续指 evt1574 会把玩家送回街道，没有 A34 下一步。

## 修复（R215-A34NEXT-1）
- c3 scene85 `_a33_done_state()`：
  - 若 evt1610 state>0 → evt1610（原有 A34 支线）；
  - 否则 → **evt1579 (1152,432)「前往衙门后院（女飞贼案后续）」→ scene90**（A34 主链），不再回 evt1574→83；
- scene90 的 c3 在 a33_backyard 未设时指 evt1650（婢女对话），之后 R200 evt1661→scene91→R202 scene93→R203 scene82 链路已存在。

## headless（用户槽1 21277806）
- 读档 scene85：HUD target **evt1579 N=84**（不是回街道）；
- 实按 HUD 84 步：pos (240,376)→(1120,432)，**N 84→0**；
- SPACE → **scene90 (816,1224)**；
- HUD 切 **「衙门后院剧情」target evt1650(1056,1104) N=28**；
- boot exit0；槽1/槽2 未写、未开窗。

## tester
- 用用户槽1/卡点档：scene85 HUD 应指 evt1579 N84；
- 走完 N0 → SPACE → scene90（evt1650 N28）→ 继续 A34；
- 若 scene90 后续卡住，给坐标。
