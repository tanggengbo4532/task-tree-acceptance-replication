class_name DesignTuning
extends RefCounted
## R75-GAME1（用户批准的新游戏设计，2026-10-25 Lead 审核通过）——设计参数单一入口。
##
## 目标：①追击频率适中（不整图死追）②调整怪物数值使低等级可过 ③保留真实战斗
## ④怪物提供经验帮助升级 ⑤降低 A62 难度使可正常通关。
##
## 纪律：只在本表改数值；**不改外部 Data/SSS 数据、经验曲线、升级成长公式、逃跑公式、触发半径**；
## 战斗/经验必须真实（禁自动胜/跳过/传送/自动置 stage）。
## 数值与 `_playtest_regress_dev/round75/GAME1_DESIGN.md` §2 一致；team-scoped 覆盖避免影响同 enemy 其他出场。

## 仅这些队伍应用怪物数值覆盖（场景16 密林的真实队伍）
const TEAM_SCOPE: Array[int] = [15, 16, 17, 40]

## 怪物数值覆盖（按 enemy id）：enemy100 绿叶小妖 / enemy132 绿叶妖精（风咒）
const ENEMY_OVERRIDES := {
	100: {"health": 28, "exp": 8, "cash": 3, "physical_resistance": 2},
	132: {"health": 32, "exp": 20, "cash": 8, "physical_resistance": 2, "magic_rate": 3},
}

## 敌方法术伤害系数（按 caster enemy id）：绿叶妖精风咒 45 基础伤 → ×0.45（实测 54~64 → 约 24~29）
const MAGIC_DAMAGE_SCALE := {
	132: 0.45,
}

## 追击调参（仅 scene16）：速度上限 1（=2px/帧，与玩家同速）、感知范围 ×0.55、
## 失去目标 90 帧后以速度1回出生点、胜利/逃跑后该事件 vanish 420 帧 + 追逐冷却。
const CHASE := {
	"scene": 16,
	"speed_clamp": 1,
	"range_scale": 0.55,
	"lose_frames": 90,
	"return_speed": 1,
	"post_battle_vanish": 420,
}


static func team_in_scope(team_id: int) -> bool:
	return TEAM_SCOPE.has(team_id)


static func enemy_override(enemy_id: int) -> Dictionary:
	return ENEMY_OVERRIDES.get(enemy_id, {})


static func magic_damage_scale(enemy_id: int) -> float:
	return float(MAGIC_DAMAGE_SCALE.get(enemy_id, 1.0))


## 当前场景的追击调参（{} = 不调参，只做"隐藏时不追"的 bug 修复）
static func chase_tuning(scene: int) -> Dictionary:
	if scene == int(CHASE["scene"]):
		return CHASE
	return {}
