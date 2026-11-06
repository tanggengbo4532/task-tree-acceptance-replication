# R225 第5章 A37/A38 数据定位 + 战斗桩核实

## 战斗桩（team42 六脚蜘蛛）
- 对象435 字段：`[enemy_id=38, resistance=10, script_on_turn_start=41533, 0,0,0,0]`；
- 脚本 **41533**（敌方回合开始）末尾：
  - `0x67 317/318/319`（设置敌方仙术）→ 对白13259-13267 → **`0x89 0`（set_result 0 = BATTLE_TERMINATED）**；
- battle.gd 在敌方回合开始调用 `script_on_turn_start`（L452/L1578），因此这场战斗**不靠打赢**，敌方回合脚本会自动结束（结果0），HP32767 不影响流程；
- 结论：无需改数值/不需要赢；tester 只需确认战斗能进入、敌方回合后自动退出、剧情继续。

## A37 剑圣（真实数据，不在 scene141）
- **scene147 (map141)** evt2405 **(1296,504) mode6 script23623**；
- script23623 内容：`0x49 2406 1`（开事件2406）+ 对白，无 0x59 换场景；
- old 注释“scene141 剑圣”不准确；剑圣在 **scene147 蜀山派大殿**。
- scene147 入口：scene165.onEnter 22666 等链（不是从141单门）；原版路径需要 141→142/143/144/156/146…→147 的 onEnter 链。

## A38 锁妖塔
- **scene154 (map74) onEnter script24148**，事件2479-2489 多为 state0 动画；
- scene154 的加载地址 24111 位于**非事件引用的子脚本**中，不由 scene141/147 的普通 event 0x59 触发；
- 需要继续按原版 onEnter/teleport 链接，当前未伪造。

## 锚点（团队槽2 备份/恢复）
- `round78/slot4_scene141_shushan_anchor`：scene141 (1344,1328)，a35_stage=2/a36_stage=1；
- `round78/slot4_scene147_jiansheng_anchor`：scene147 **(1296,504)**，剑圣 evt2405 旁；
- `round78/slot4_scene154_tower_anchor`：scene154 **(1456,456)**，锁妖塔内。

## 状态
- 代码 HEAD `d83b27e`（R223）；本批仅文档+锚点，不改代码；
- 槽1只读、团队槽2未写、未开窗。
- A37/A38 未见从 scene141 的单一真实门，需继续实现 onEnter 链；下一步优先验证 scene141→142 的 onEnter 流程是否已在移植中执行（21898 脚本设 142/143/156）。
