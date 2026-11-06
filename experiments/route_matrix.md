# IST A route matrix（已确认 + C-only preflight）

> 生成：developer3｜2026-11-06｜代码 HEAD `f9972eb`（R311）
> Lead 已确认 v0；本轮完成 **C-only preflight**（含 R5 替换）并写入 verified；随后已执行 6×3×3 全量（结果见 `hud_eval_summary.md` / `hud_eval_runs.csv`）。

## 最终 6 条路线（全部真实 .sav；团队槽2只读载入）

| ID | 类别 | start | target | expected | start_N | anchor .sav | sha256 | C preflight |
|---|---|---|---|---|---|---|---|---|
| R1 | complex | scene207 (1024,1600) | evt3461 (464,280) | scene206 | 242 | `_playtest_regress_dev/round78/anchor.sav` | `C18606EF2EAF672F02A4E1C1DCA36D012BA42883134D0A47ED76D0CF1FD30725` | **verified** 239 steps 207→206, N242→78 |
| R2 | simple | scene206 (1488,1592) | evt3442 (864,1280) | scene206 + A46 dialogue/VM | 78 | `anchor.sav` | `CAE77CAF4EA66CB76886E29B80763A48B9503835047A8D4D8005D4E07C0B571A` | **verified** 71 steps, N78→7, VM/dlg=true |
| R3 | simple | scene153 (1680,408) | A39 (960,1056) | scene155 | 179 | `anchor.sav` | `9AEF108304805A04DCB672FC37666CCB371931CA749A3A8AFA7C8A3072BC986C` | **verified** 170 steps → scene155 |
| R4 | simple | scene255 (1680,1640) | A49点 (1680,1720) | scene253 | 10 | `anchor.sav` | `7C922D7CFD7F74D32198ECFF6B6BE1A9F157DA982CD8180FBFFCCDE8FEC8BB7B` | **verified** 3 steps → scene253, battle=true |
| R5E | simple | scene247 (896,1104) | evt4365 (896,1152) | scene255 | 2 | `anchor.sav` | `C026F578AACCD7B89037D240D37254B053953F924E1943E599DE5EB16F26BAB0` | **verified** 1 step → scene255 |
| R6 | detached/detour | scene139 (1552,1432) | evt2342 (1376,1360) | trigger/VM（battle=false 如实记录；不要求战斗/胜利） | 16 | `anchor.sav` | `73922E9D51EA89E9C62E0265B13BF58BB80284AF2385EFCCAADA6B6F5DDEAF54` | **verified** 16 steps; VM/dlg true |

## 类别覆盖
- simple：R2/R3/R4/R5E
- complex：R1
- detached/detour：R6（真实战后恢复/剧情门，不是人为造断连）

## 成功判据（已按 Lead 确认）
- R1：到达 evt3461 触发区并进入 scene206
- R2：到达 evt3442 触发区并触发 A46 对话/VM（scene 仍 206；无场景切换）
- R3：到达 A39 并进入 scene155
- R4：走到 A49 点并进入 scene253（可进入终战，battle=true）
- R5E：走到 evt4365 并进入 scene255
- R6：到达 evt2342 触发区并由剧情 VM 接管（battle=false 也如实记录为成功；不要求战斗胜利、不 auto-win）

## R5 替换记录
- 原 R5（`anchor.sav`，start 1568,1696→evt4365）C preflight **失败**：36步后在 (1136,1768) 触发随机战/VM，success=false。
- 按 Lead 授权替换为 **R5E**（`anchor.sav`，start 896,1104→evt4365），C preflight 成功。
- 探索候选：**R5A**（scene185 森林）载入即战斗/0步；**R5B**（scene188 forest gate）500步未到门；**R5C**（scene188 door）与 **R5D**（scene178 圣姑居）均为 **0步 success**——锚点载入位置已在目标/触发区内，C 未真正行走，仅作 preflight 语义记录；均不纳入正式 6 条，raw 保留在 `raw/`。

## 纪律
- 所有 anchor 只复制到团队槽2；不加载/不写用户槽1；runner 前后 slot1 hash guard 通过。
- 未见人为制造断连；R6 的 disconnected/detour 来自真实存档/剧情门。
- 完整 sha256 见 `route_matrix.csv`；原始 preflight 日志见 `raw/preflight_*.txt`。

## F1 · R3 起点修正
- v0 `(1504,408)`/N168 → verified `(1680,408)`/N179；**理由：以 C preflight 实测锚点载入落点为准修正**（不是手动改坐标）；完整字段见 `route_matrix.csv`。
