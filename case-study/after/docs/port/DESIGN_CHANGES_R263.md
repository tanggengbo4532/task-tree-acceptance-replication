# R263 自动战斗修复 + scene139 六脚蜘蛛战前锚点

## A) 自动战斗 bug（battle.gd）
### 根因
- tester 在战斗菜单选择「其他→自动战斗」后，旧实现只 `_auto_attack=true; continue`：
  - 当前玩家仍停留在菜单等待输入；
  - 每回合 `_select_phase()` 开头 `_input_reset()` 会清 `_auto_attack=false`；
  - 于是反复出现「自动战斗开启」、回合不自动推进；残留输入/子菜单导致 AI 看起来只用物品（大蒜）。
### 修复
- 新增 **`_auto_mode` 持久标记**（`_auto_attack` 保留为当前选择瞬态）：
  - `_auto_mode` 只在战斗 `_begin` 重置，不再被 `_input_reset` 清除；
  - 菜单「自动战斗」：`_auto_mode=true; _auto_attack=true; return _auto_attack_action(p)`，当前玩家立即出招；
  - `_select_phase()` 判断 `_auto_attack or _auto_mode`，后续玩家/后续回合自动普通攻击；
  - `set_auto_battle()` 同步置 `_auto_mode=true`。
- 未改伤害公式/难度/胜负判定；无 auto-win。
### headless 证据（q2026，team139）
- 通过真实菜单按键选择「其他→自动战斗」；
- 日志：第1回合 自动战斗开启→玩家0/1 攻击；第2..10回合每回合自动选择「攻击」，**不再弹自动战斗菜单/不重复开启**；
- 无物品行动；战斗 10 回合后 `result=lose`（敌方真实数值，不伪胜）；
- boot exit0，无 SCRIPT ERROR。

## B) scene139 六脚蜘蛛战前锚点
- 来源：用户最新槽1 **14B5CFBD…** 只读副本
- 文件：
  - `_playtest_regress_dev/round78/slot2_scene139_spider_anchor.sav` SHA256 **73922E9D…**
  - `_playtest_regress_dev/round78/slot2_scene139_spider_anchor.json` SHA256 **124346C0…**
- 状态：scene139，pos(1552,1432)，maxidx=1；李 HP290/290、林 HP339/339、MP满；a34_done=1/a35=1/a36_route=1/a36_stage=0；HUD target evt2342 N16
- 载入说明：`_playtest_regress_dev/round78/slot2_scene139_spider_anchor_README.md`
  - 复制为团队槽2 `pal_save_2.sav/.json`；用户槽1不写；tester 读槽2

## C) 六脚蜘蛛战 headless 结果（不 auto-win）
- battle **team=42**，`flee_disabled=true`
- 敌：obj435 / enemy_id38 **六脚蜘蛛 HP32767/32767**
- 开战：李290/290、林339/339
- 逃跑尝试：因 flee_disabled 无法结束战斗
- 自动战斗：10回合后 **lose**；退出到 scene139，**a36_stage=0，未到141**，HP归零
- 结论：**scene139 六脚蜘蛛战是当前阻塞**（HP32767/flee_disabled，非自动战斗卡死）；需用户/tester确认该战数据/设计或提供应对。

## N 表（用户最新档14B5CFBD，并集1828）
- 读档 scene85 raw(160,112)→(720,552)，HUD evt1579 N54
- A34: 85 N54→91 N34→93 N24→82 N49→89 N64→85复命 N198；A34 done/A35 stage1，结束(560,472)
- 出城：evt1583 **N152**（从560,472；从锚点528,568为N142）→106 **N6**
- 106→109 **N170**→118 **N0**→140 **N276**→139 **N16**→141（a36=1，但战斗败后 maxidx=0）
- 场景序列：85→91→93→82→89→85→106→109→118→140→139→141

## 状态
- boot exit0；HEAD 提交后见回执
- 槽1=14B5CFBD只读未变；槽2已恢复用户最新档14B5CFBD（锚点复制前请按README）
- 未开窗；未碰槽1/3/4/5/9
