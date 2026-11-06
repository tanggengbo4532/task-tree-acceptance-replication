# R250 进度一后续链修复（S100OPT / A34REPORT / A35RANGE）

## 背景
R249 已修 scene85 旧起点救援、scene93 屋外门、scene82 审案目标。继续自动跟随后发现：
1. scene100 居民对话为可选，但目标 NPC 点(576,304)在地图94不可达（障碍），HUD 被可选对话占住，N0 实际落在出口 evt1795/1796，SPACE 回 scene85 → 与 scene85复命目标形成 S85↔S100 循环；
2. scene85复命目标 evt1594 不可达时，HUD 实际指向门 evt1582 → scene100；进入 scene100 后 `a34_done` 仍未置1，A34 复命线未接通；
3. A35 向街坊打听目标 evt1608：HUD N0 落点(800,488)与目标(704,464)距离144，旧交互阈值140差4格，SPACE无提示。

## 修复（R250）
- **S100OPT-1**：scene100 c3 先判断 evt1797 是否可达；不可达则直接指出口 evt1795，不再让可选居民对话占 HUD。
- **A34REPORT-1**：`a34_case>=1` 且进入 scene100 且 `a34_done<1` → 置 `a34_done=1`、`a34_stage=4`，复命线接通；之后 scene85 HUD 进入 A35。
- **A35RANGE-1**：A35 街坊打听交互半径 140→176，HUD N0 落点可触发；a35_talked/a35_stage 正常置1。

## headless 全链（用户槽1 CB1A…只读）
| 阶段 | 结果 |
|---|---|
| 读档 | scene85 救援(480,544)，HUD N68↑ |
| 85→91→93→82 | 68步→scene91；34步→93；24步→屋内；审案选择IP15388（是）→scene89 |
| 89→85→100 | 64步→scene85；复命线→scene100（可选已改出口） |
| 100→85 | 出口回 scene85，a34_done=1，HUD“向街坊打听消息” |
| A35 | 对话触发，a35_talked=1、a35_stage=1；HUD“按空格前往蜀山” |
| A36蜀山 | SPACE→script21692→**scene141**（蜀山，pos1344,1328），a35_stage=2 |
- boot exit0，无 SCRIPT ERROR；槽1 hash 未变 `CB1A22F7…`；槽2未写。

## 文件
- 本文件；代码 world.gd（R250三处）。
- 未开窗；槽1只读。

## 下一步
- 继续 scene141 第5章后续节点自动测（蜀山剧情/下一场景）。
