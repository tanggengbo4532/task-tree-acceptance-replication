# R265 锁妖塔 scene154/153 近点锚点 + 153→178 链重验

## 背景
用户离开，团队自治续测 scene154 锁妖塔（第5章末→第6章）。用户最新槽1 **14B5CFBD…** 只读；tester quit_trace scene=154 pos=(1680,408)。

## 锚点（用户槽1只读副本，写团队槽2/文件）
- `round78/slot2_scene153_tower_inside_anchor.sav/.json` ← **推荐 tester 续测**
  - SHA256(sav) **9AEF108304805A04DCB672FC37666CCB371931CA749A3A8AFA7C8A3072BC986C**
  - scene153 (1680,408)，a34_done=1、a35_stage=2、a36=1、a37=1、a38=1、a39/a40/a41=0；李290/290、林339/339，maxidx=1
  - HUD「按空格深入锁妖塔（救灵儿/月如）」
- `round78/slot2_scene154_tower_entry_anchor.sav/.json`
  - SHA256(sav) **B37F88872359BC8FF6232F86704DE61E3854A400CCD0D48F59814F2139391E19**
  - scene154 (1680,408)，同战斗/剧情状态；仅位置对照（读档抑制 onEnter，HUD空；原版 scene154 onEnter24148→0x59 153）
- 载入说明：`round78/slot2_scene154_tower_anchor_README.md`
- 用户槽1未写；当前槽2恢复用户最新档14B5CFBD

## 链重验（headless q2039，从 scene153 锚点；当前构建 R264 HEAD 8235b47）
- **153 (1680,408)**：HUD「按空格深入锁妖塔」→ SPACE
- **155 (1680,408)**：a39_stage=1；HUD「锁妖塔内：救灵儿/月如」
- **SPACE → 156 (1024,1600)**：a40_stage=1；HUD「锁妖塔顶：月如/塔倒」
- **SPACE → 178 (1408,704)**：a41_stage=1；HUD「已离开蜀山，到苗疆·圣姑居（第6章）」
- 场景序列：**153→155→156→178**（scene154 为入口，onEnter 正常→153）
- 最终 maxidx=1；无 SCRIPT ERROR；**此链无需改代码**
- N 表：这三个节点均为 SPACE 门/剧情，HUD N=0；无长距离行走
- 下一步：scene178 onEnter27955（A42圣姑/灵儿线）→175/177/187/188/185 等（待续）

## 状态
- boot exit0；用户槽1只读；未开窗；未碰槽1/3/4/5/9
- 文档：本文件
