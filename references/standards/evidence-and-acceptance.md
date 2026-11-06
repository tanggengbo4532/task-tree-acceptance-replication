# 标准 · 证据与验收（目录/日志/三重确认/人读报告）

> 目标：结论**可追溯、可复现、可审计**；报告**只增不覆盖**、版本化。
> 相关：`templates/evidence-index.md`、`templates/report-template.md`、`templates/acceptance-report-user.md`、`tools/evidence/manifest.py`。

## 1. 证据目录与命名

```text
<project>/
├─ _playtest_regress/roundNN/        # 测试侧：每轮一个目录，不覆盖上一轮
│  ├─ tester-report.md               # 本轮报告（只写这个+EXPERIENCE）
│  ├─ EXPERIENCE.md                  # 经验库（S/F/R）
│  ├─ rNN_*.png                      # 截图：前缀 rNN_（轮次）+ 序号 + 语义
│  ├─ rNN_run.log / rNN.err.log      # 运行日志/错误日志（err 期望 0B）
│  └─ rNN_hold_*/rNN_walk_*          # 探针采样图（walk/hold）
├─ _playtest_regress_dev/roundNN/    # 开发侧：探针日志/审计/修复报告（与测试目录分离）
└─ giveUser/                         # 给用户的交付（只增版本化：v1/v2/v3…）
```

规范：**轮次前缀唯一**（`r75_`/`r76b_`/`r76c_`…），禁覆盖旧文件；关键帧文件名带语义（`_before`/`_after`/`_blocked`/`_pass`）；截图与日志同轮归档。

## 2. 日志与取证

- 启动时**重定向 stderr/stdout**：`err.log` 期望 **0B**；非 0 需解释（警告/崩溃/取证）。
- 崩溃/进程退出类问题：需留**退出取证**（如 `quit_trace.log`：时间/场景/坐标/busy/VM ip/栈）与系统事件；无法复现时如实记"未复现+取证能力已加"。
- 时序类问题：修完**站定观察 3~5 秒**再截结论帧；截图/回放/日志多源交叉。
- 反作弊：证据不得来自调试模式/调试键（见 `no-cheat.md`）。

## 3. 截图与裁剪

- 关键通过/阻塞**各 ≥1 张**；对比类问题给"修复前/修复后"同位置帧；
- 需要读提示/数字时用 `tools/screen/crop_region.py` 裁剪提示区域（README 中 `capture.crop_hint` 同源），避免整图看不清；
- 截图抗伪：PrintWindow 空白/全黑时回退屏幕拷贝；判定"真实画面 vs 截图黑"用多方法（PrintWindow/实屏/GetWindowDC）交叉，不能只看一种；
- 证据清单自动生成：`python tools/evidence/manifest.py --dir <证据目录> --out evidence-index.md`（路径/sha256/分组/张数；只增归档）。

## 4. 三重确认（写进每个节点）

| 步骤 | 负责 | 产物 |
|---|---|---|
| ① 测试自判 | 测试 | 结论（通过/未通过/阻塞）+ 逐条验收对照 + 证据编号 + 未达成项 |
| ② 开发复核 | 开发 | 证据充分性/可复现性/是否满足验收标准；同意/不同意（理由） |
| ③ Lead 宣布 | Lead | 宣布通过/继续本节点/组织复核；宣布后派记录归档 |

任一方未完成→继续；双方不一致→Lead 组织复核（必要时用户裁定）；**Lead 不得单方面宣布通过**；测试无权自宣通过。

## 5. 报告规范（只增、版本化）

- **测试单节点报告**：`templates/report-template.md`（结论/证据/问题+建议/未达成）。
- **记录六项归档**：`templates/recorder-log.md`（缺一不合格）。
- **技术验收报告**：`templates/acceptance-report.md`（节点/改动/验证/回归）。
- **给用户的人读版**：`templates/acceptance-report-user.md`，硬要求：
  1) 三分钟看懂（一句话目标+节点总表+代码总账）；
  2) 节点从哪到哪（初状态→末状态+证据+三重确认）；
  3) 发现的 bug（现象→根因→修复 commit，含"未完成项如实"）；
  4) **代码变动用 git diff**：`-` 基线 / `+` 验收，**只放两头、不列中间迭代**，每处中文解释；附完整未删减 diff 文件；
  5) 关键配图（相对路径，≥1 通过/阻塞）；
  6) 遗留/下一步/锚点未变声明。
- **版本化**：`ACCEPTANCE_REPORT_vN_...`、`mainline-task-tree_regress_vN`、素材 `PAPER_*_vN`；历史保留，不覆盖。

## 6. 审核清单（记录/Lead 用）

- [ ] 构建 hash 与证据一致；[ ] 证据编号可 Test-Path；[ ] err.log 0B 或已解释；
- [ ] 锚点未覆盖、读档次数已记；[ ] 无作弊手段/调试键取证；[ ] 三重确认记录齐全；
- [ ] 报告只增版本化；[ ] 未完成/未覆盖项如实列出；[ ] 数据（token/用时）标注估算口径。
