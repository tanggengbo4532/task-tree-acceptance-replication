class_name Battle
extends Node2D
## 《仙剑98》回合制战斗系统（移植 sdlpal battle.c / fight.c / uibattle.c，PAL_CLASSIC 模式）。
##
## 入口（INTERFACES §4）：
##   var b := Battle.new(); b.setup(team_id, flee_disabled, force_win); add_child(b)
##   b.finished -> "win" / "lose" / "flee"
##
## 流程对齐 fight.c PAL_BattleStartFrame（PAL_CLASSIC 分支）：
##   1) 选择阶段（kBattlePhaseSelectAction）：逐个玩家选指令（攻击/仙术/合击/其他）；
##   2) 组行动队列（ActionQueue）：敌人敏捷=(level+6)*3+dexterity、玩家敏捷按动作类型加权，
##      各 ×RandomFloat(0.9,1.1)；降序排序（kBattlePhasePerformAction）；
##   3) 执行阶段：按队列逐个执行，玩家/敌人轮流行动；
##   4) 回合结束：清防御、结算毒与状态回合数、KO 判定（经验/金钱累计）、显示数值、
##      敌人 wScriptOnTurnStart、清空 item in-use。
##
## 数值公式逐条对齐 fight.c：[obs] PAL_CalcBaseDamage / PAL_CalcMagicDamage /
## PAL_CalcPhysicalAttackDamage / 逃跑成功率 / PAL_BattleWon 的经验与升级循环。
## 原版二进制未逐函数实证者标 [inf]（见各函数注释）。
##
## 脚本钩子：敌人 wScriptOnTurnStart/OnBattleEnd/OnReady、物品/法术 script_on_use/success
## 通过自带 ScriptVM（注入战斗代理，见“ScriptVM 战斗代理”一节）执行；
## 无 PalData 时退回 World.run_script_entry。遇到对话/等待状态即中断（[inf]）。
##
## 调试入口：`--battle-test=<team_id>`（main.gd 实例化本类）+ `--battle-test-mode=win|flee|ui|demo`
## 自动战斗并截图到 _rea_runtime/out/shots/battle_*.png。
signal finished(result: String)

# ------------------------------------------------------------------ 常量

const GAME_W := 320
const GAME_H := 200
const BATTLE_FPS := 25
const FRAME_MS := 1000 / BATTLE_FPS
const SHOT_DIR := "<LOCAL_PATH>"

const MAX_ROLES := 6
const MAX_PARTY := 3
const MAX_ENEMIES := 5

# FIGHTERSTATE（battle.h tagFIGHTERSTATE??
const FIGHTER_WAIT := 0
const FIGHTER_COM := 1
const FIGHTER_ACT := 2

# BATTLEACTIONTYPE（battle.h tagBATTLEACTIONTYPE??
const ACT_PASS := 0
const ACT_DEFEND := 1
const ACT_ATTACK := 2
const ACT_MAGIC := 3
const ACT_COOP := 4
const ACT_FLEE := 5
const ACT_THROW_ITEM := 6
const ACT_USE_ITEM := 7
const ACT_ATTACK_MATE := 8

# STATUS（global.h tagSTATUS，PAL_CLASSIC?? = paralyzed??
const ST_CONFUSED := 0
const ST_PARALYZED := 1
const ST_SLEEP := 2
const ST_SILENCE := 3
const ST_PUPPET := 4
const ST_BRAVERY := 5
const ST_PROTECT := 6
const ST_HASTE := 7
const ST_DUAL_ATTACK := 8
const STATUS_ALL := 9

# MAGIC_TYPE（global.h tagMAGIC_TYPE??
const MAGIC_NORMAL := 0
const MAGIC_ATTACK_ALL := 1
const MAGIC_ATTACK_WHOLE := 2
const MAGIC_ATTACK_FIELD := 3
const MAGIC_APPLY_TO_PLAYER := 4
const MAGIC_APPLY_TO_PARTY := 5
const MAGIC_TRANCE := 8
const MAGIC_SUMMON := 9

# ITEMFLAG / MAGICFLAG
const ITEM_USABLE := 1
const ITEM_EQUIPABLE := 2
const ITEM_THROWABLE := 4
const ITEM_CONSUMING := 8
const ITEM_APPLY_TO_ALL := 16
const MAGIC_USABLE_OUTSIDE := 1
const MAGIC_USABLE_IN_BATTLE := 2
const MAGIC_USABLE_TO_ENEMY := 8
const MAGIC_FLAG_APPLY_TO_ALL := 16

# 输入??
const K_UP := 1
const K_DOWN := 2
const K_LEFT := 3
const K_RIGHT := 4
const K_OK := 5
const K_CANCEL := 6

const STATUS_NAMES: Array[String] = ["乱", "麻", "眠", "封", "傀", "勇", "护", "速", "连"]
const STATUS_COLORS: Array[Color] = [
	Color(1, 0.5, 0.5), Color(1, 1, 0.4), Color(0.7, 0.7, 1), Color(0.8, 0.5, 1),
	Color(0.6, 0.6, 0.6), Color(1, 0.85, 0.3), Color(0.5, 1, 0.8), Color(0.5, 1, 1), Color(1, 0.7, 0.3),
]

# ------------------------------------------------------------------ 状态
var team_id: int = 0
var flee_disabled: bool = false
var force_win: bool = false
var world: Node = null

var _tables: Node = null
var _state: Node = null
var bd: BattleData = null
var ui: BattleUI = null

var players: Array = []
var enemies: Array = []
var max_enemy_index: int = -1
var phase: int = 0

var exp_gained: int = 0
var cash_gained: int = 0
var enemy_cleared: bool = false
var result: String = ""
var _is_boss: bool = false
var turn_no: int = 0

var _bg: Image = null
var _bg_field: int = 0
var _magic_fx: Dictionary = {}
var _fx_overlay: Array = []

var _waiting_key: bool = false
var _pending_key: int = K_CANCEL
var _auto_attack: bool = false
var _in_use: Dictionary = {}
var _exp_counts: Dictionary = {}

var _test_mode: bool = false
var _test_kind: String = "demo"
var _auto_play: bool = true
var _ui_test: bool = false
var _script_keys: Array[int] = []
var _script_pos: int = 0
var _shot_done: Dictionary = {}
var _action_queue: Array = []
var _cur_action: int = 0

var _pending_setup: Array = []
var _started: bool = false

# 战斗脚本运??时（??_run_script / 战斗代理??
var _script_vm = null
static var _script_vm_script: GDScript = null
var _terminated: bool = false        # 脚本 0x0089=0 / 0x0069 敌人逃跑：结束战斗但不结算胜利
var _hiding_time: int = 0
var _blow: int = 0
var _enemy_acting: bool = false


# ------------------------------------------------------------------ 生命周期

func setup(p_team_id: int, p_flee_disabled: bool = false, p_force_win: bool = false) -> void:
	team_id = p_team_id
	flee_disabled = p_flee_disabled
	force_win = p_force_win
	_pending_setup = [p_team_id, p_flee_disabled, p_force_win]


func _ready() -> void:
	if world == null:
		var par := get_parent()
		if par != null and par.has_method("run_script_entry"):
			world = par
	if not _started:
		_started = true
		_begin()


func _begin() -> void:
	_tables = get_node_or_null("/root/PALTables")
	_state = get_node_or_null("/root/PALState")
	_test_mode = _has_cmd_prefix("--battle-test")
	_test_kind = _cmd_value("--battle-test-mode")
	if _test_kind == "":
		_test_kind = "demo"
	_ui_test = _test_kind == "ui"
	# --auto 演示/集成测试下也自动出招，避免无人按键卡在指令菜单
	_auto_play = (not _ui_test) and (_test_mode or ("--auto" in OS.get_cmdline_args()))
	if _ui_test:
		# 模拟按键序列：攻????主菜单左（仙??????列表下移到天师?????????
		_script_keys = [K_OK, K_LEFT, K_OK, K_DOWN, K_OK, K_OK, K_OK, K_DOWN, K_OK]
	if _pending_setup.is_empty() and _test_mode:
		setup(1, false, false)
	var dir := PalConfig.require_data_dir()
	bd = BattleData.new()
	if not bd.init(dir, _tables):
		push_error("Battle: 战斗数据装载失败")
		_finish("lose")
		return
	ui = BattleUI.new()
	ui.name = "BattleUI"
	add_child(ui)
	ui.set_message("", false)
	_init_entities()
	if _state != null:
		_state.in_battle = true
	_bg_field = int(_state.battle_field) if _state != null else 0
	if _bg_field <= 0:
		_bg_field = 6  # [inf] 脚本 0x004A 未设置时退回首个战斗背景（FBP 块 6）
	_bg = bd.background(_bg_field)
	ui.set_background(_bg)
	_update_panels()
	_draw_scene()
	if _test_mode:
		print("[battle] team=%d 玩家=%d 敌人=%d bg_field=%d" % [team_id, players.size(), enemies.size(), _bg_field])
		for e in enemies:
			if int(e.get("object_id", 0)) != 0:
				var st: Dictionary = e["e"]
				print("[battle] ENEMY idx=%d obj=%d id=%d HP=%d Lv=%d 攻=%d 魔=%d 防=%d 敏=%d 魔率=%d" % [
					int(e["index"]), int(e["object_id"]), int(st["id"]), int(st["health"]),
					int(st["level"]), int(st["attack_strength"]), int(st["magic_strength"]),
					int(st["defense"]), int(st["dexterity"]), int(st["magic_rate"])])
		_test_grant_magic()
		_test_seed_exp()
	await _fade_in()
	await _run_battle()
	_finish(result if result != "" else "lose")


# ------------------------------------------------------------------ 战斗实体构建

## battle.c PAL_StartBattle：把 ENEMYTEAM 的 5 个 OBJECT 号展开为战斗敌人，
## 把 PALState.party 展开为战斗玩家，并按 g_rgPlayerPos / EnemyPos 表摆位。
func _init_entities() -> void:
	players.clear()
	enemies.clear()
	_in_use.clear()
	_exp_counts.clear()
	exp_gained = 0
	cash_gained = 0
	enemy_cleared = false
	result = ""
	_is_boss = flee_disabled
	# ---- 我方
	var party_roles: Array[int] = [0]
	if _state != null:
		var cnt := clampi(int(_state.max_party_member_index) + 1, 1, MAX_PARTY)
		var party = _state.party
		party_roles.clear()
		for i in range(cnt):
			var r := 0
			if party is Array and i < party.size() and party[i] is Dictionary:
				r = int((party[i] as Dictionary).get("role", 0))
			if r < 0 or r >= MAX_ROLES:
				r = i
			party_roles.append(r)
	var n := party_roles.size()
	var pos_table := _player_pos_table(n)
	for i in range(n):
		var role := party_roles[i]
		var base := bd.build_player_base(role, _state)
		var sprite := bd.battle_sprite_of(role, _state)
		var p := {
			"index": i,
			"role": role,
			"name_word": int(base.get("name_word", role)),
			"level": int(base.get("level", 1)),
			"max_hp": int(base.get("max_hp", 100)),
			"max_mp": int(base.get("max_mp", 0)),
			"attack_strength": int(base.get("attack_strength", 0)),
			"magic_strength": int(base.get("magic_strength", 0)),
			"defense": int(base.get("defense", 0)),
			"dexterity": int(base.get("dexterity", 0)),
			"flee_rate": int(base.get("flee_rate", 0)),
			"poison_resistance": int(base.get("poison_resistance", 0)),
			"elem_resistance": base.get("elem_resistance", [0, 0, 0, 0, 0]),
			"can_attack_all": bool(base.get("can_attack_all", false)),
			"cooperative_magic": int(base.get("cooperative_magic", 0)),
			"sprite_num": sprite,
			"frames": bd.player_frames(sprite),
			"pos": pos_table[i],
			"pos_original": pos_table[i],
			"frame": 0,
			"defending": false,
			"color_shift": 0,
			"hiding": 0,
			"state": FIGHTER_WAIT,
			"second_attack": false,
			"action": {"type": ACT_PASS, "id": 0, "target": -1},
			"prev_action": {"type": ACT_PASS, "id": 0, "target": -1},
			"prev_hp": 0,
			"prev_mp": 0,
			"death_sound": int(base.get("death_sound", 0)),
			"attack_sound": int(base.get("attack_sound", 0)),
			"weapon_sound": int(base.get("weapon_sound", 0)),
			"critical_sound": int(base.get("critical_sound", 0)),
			"magic_sound": int(base.get("magic_sound", 0)),
			"cover_sound": int(base.get("cover_sound", 0)),
			"dying_sound": int(base.get("dying_sound", 0)),
		}
		# ??战时队伍成员必须存活（battle.c PAL_StartBattle??
		if _hp(role) == 0:
			_set_hp(role, 1)
			_set_status(role, ST_PUPPET, 0)
		p["prev_hp"] = _hp(role)
		p["prev_mp"] = _mp(role)
		players.append(p)
	# ---- 敌方
	var team := _get_team(team_id)
	var ei := 0
	for obj_id_v in team:
		var obj_id := int(obj_id_v)
		if obj_id == 0xFFFF:
			continue
		if obj_id == 0:
			enemies.append({
				"index": ei, "object_id": 0, "e": {}, "frames": [],
				"status": [0, 0, 0, 0, 0, 0, 0, 0, 0],
				"poisons": [], "pos": Vector2i(160, 100), "pos_original": Vector2i(160, 100),
				"frame": 0, "state": FIGHTER_WAIT, "prev_hp": 0, "color_shift": 0,
				"script_on_turn_start": 0, "script_on_battle_end": 0, "script_on_ready": 0,
				"resistance_to_sorcery": 0,
			})
			ei += 1
			continue
		var eb := bd.build_enemy_base(obj_id)
		if eb.is_empty():
			ei += 1
			continue
		var st: Dictionary = (eb["stats"] as Dictionary).duplicate(true)
		var poisons: Array = []
		for k in range(16):
			poisons.append({"poison_id": 0, "script": 0})
		var e := {
			"index": ei,
			"object_id": obj_id,
			"enemy_id": int(eb["enemy_id"]),
			"e": st,
			"frames": bd.enemy_frames(int(eb["enemy_id"])),
			"status": [0, 0, 0, 0, 0, 0, 0, 0, 0],
			"poisons": poisons,
			"pos": Vector2i(160, 100),
			"pos_original": Vector2i(160, 100),
			"frame": 0,
			"state": FIGHTER_WAIT,
			"prev_hp": int(st["health"]),
			"color_shift": 0,
			"script_on_turn_start": int(eb["script_on_turn_start"]),
			"script_on_battle_end": int(eb["script_on_battle_end"]),
			"script_on_ready": int(eb["script_on_ready"]),
			"resistance_to_sorcery": int(eb["resistance_to_sorcery"]),
		}
		enemies.append(e)
		ei += 1
	max_enemy_index = ei - 1
	# 敌方摆位：EnemyPos.pos[i][wMaxEnemyIndex] + e.wYPosOffset
	for i in range(enemies.size()):
		var en: Dictionary = enemies[i]
		var ppos := Vector2i(160, 120)
		if bd.enemy_pos.size() > i and i < (bd.enemy_pos[i] as Array).size():
			var row: Array = bd.enemy_pos[i]
			var col := clampi(max_enemy_index, 0, row.size() - 1)
			ppos = row[col]
		if not (en["e"] as Dictionary).is_empty():
			ppos.y += int((en["e"] as Dictionary).get("y_pos_offset", 0))
		en["pos"] = ppos
		en["pos_original"] = ppos
	phase = 0


func _get_team(tid: int) -> Array:
	if _tables != null:
		var teams = _tables.enemy_teams
		if teams is Array and tid >= 0 and tid < teams.size():
			return teams[tid]
	return bd.team(tid)


func _player_pos_table(n: int) -> Array[Vector2i]:
	# battle.c g_rgPlayerPos[3][3][2]
	if n <= 1:
		return [Vector2i(240, 170)]
	elif n == 2:
		return [Vector2i(200, 176), Vector2i(256, 152)]
	return [Vector2i(180, 180), Vector2i(234, 170), Vector2i(270, 146)]


# ------------------------------------------------------------------ 战斗主流程
func _run_battle() -> void:
	# battle.c PAL_BattleMain：开战前跑每????人的 wScriptOnTurnStart（脚????终??战斗??
	for e in enemies:
		if int(e.get("object_id", 0)) != 0:
			await _run_script_async(int(e.get("script_on_turn_start", 0)), int(e["index"]))
	if result != "":
		# 战前脚本已结束战斗（如 0x0069 敌人逃跑），不再进入主循环
		await _on_battle_end()
		return
	if _test_mode:
		await _maybe_shot("01_start")
		ui.set_message("战斗开始！")
		await _wait(12)
		ui.set_message("", false)

	while result == "":
		turn_no += 1
		phase = 0
		if _ui_test:
			printerr("[battle-flow] turn=%d begin" % turn_no)
		print("[battle] ===== 第 %d 回合：选择指令 =====" % turn_no)
		await _select_phase()
		if result != "":
			break
		_build_action_queue()
		phase = 1
		print("[battle] ===== 第 %d 回合：行动（队列 %d）=====" % [turn_no, _action_queue.size()])
		await _perform_phase()
		if result != "":
			break
		await _end_turn_phase()

	await _on_battle_end()


# ---------------------------------------------------------------- 选择指令

func _select_phase() -> void:
	var i := 0
	while i < players.size():
		var p: Dictionary = players[i]
		if _cannot_act(p):
			p["action"] = {"type": ACT_ATTACK, "id": 0, "target": -1}
			p["state"] = FIGHTER_ACT
			i += 1
			continue
		var act: Dictionary
		if _auto_play:
			act = _test_choose_action(i)
			await _wait(2)
		elif _auto_attack:
			act = _auto_attack_action(p)
		else:
			act = await _choose_action(i)
		if act.has("cancel"):
			# sdlpal classic：kKeyMenu 回到上一????行动玩??重???
			var j := i - 1
			while j >= 0 and _cannot_act(players[j]):
				j -= 1
			if j >= 0:
				i = j
			continue
		p["action"] = act
		p["state"] = FIGHTER_ACT
		print("[battle] 玩家%d(%s) 指令: %s" % [i, _player_name(p), _action_name(act)])
		i += 1
	_ui_trace("select_phase done")

	# 记录上一回合指令，供“重复???与合击贡献判定
	for p in players:
		p["prev_action"] = (p["action"] as Dictionary).duplicate()


func _cannot_act(p: Dictionary) -> bool:
	var role := int(p["role"])
	if _hp(role) == 0 and _status(role, ST_PUPPET) == 0:
		return true
	if _status(role, ST_SLEEP) > 0 or _status(role, ST_CONFUSED) > 0 or _status(role, ST_PARALYZED) > 0:
		return true
	return false


func _auto_attack_action(p: Dictionary) -> Dictionary:
	var role := int(p["role"])
	if _player_can_attack_all(role):
		return {"type": ACT_ATTACK, "id": 0, "target": -1}
	return {"type": ACT_ATTACK, "id": 0, "target": _select_auto_enemy()}


# ---------------------------------------------------------------- 玩家菜单

## 选择一名玩家的指令；返回 {type,id,target} 或 {cancel:true}。
func _choose_action(pi: int) -> Dictionary:
	var p: Dictionary = players[pi]
	var role := int(p["role"])
	var main_sel := 0
	var menu := 0  # 0=主菜单 1=杂项 2=物品子菜单
	while true:
		if _ui_test:
			printerr("[battle-flow] choose_action player=%d menu=%d sel=%d" % [pi, menu, main_sel])
		ui.hide_menus()
		_update_panels()
		if menu == 0:
			var disabled: Array = []
			if not _can_use_magic(role):
				disabled.append(1)
			if not _can_coop(role):
				disabled.append(2)
			ui.set_main_menu(["攻击", "仙术", "合击", "其他"], main_sel, disabled)
			ui.set_message("", false)
		elif menu == 1:
			ui.set_list_menu("其他", PackedStringArray(["物品", "防御", "逃跑", "自动战斗", "状态"]), main_sel)
		else:
			ui.set_list_menu("物品", PackedStringArray(["使用", "投掷"]), main_sel)
		_draw_scene()
		var key := await _get_key()
		var count := 4 if menu == 0 else (5 if menu == 1 else 2)
		if menu == 0:
			# sdlpal classic：四向图????攻击 ??仙术 ??合击 ??其他
			match key:
				K_UP:
					main_sel = 0
				K_LEFT:
					main_sel = 1
				K_RIGHT:
					main_sel = 2
				K_DOWN:
					main_sel = 3
		else:
			match key:
				K_UP, K_LEFT:
					main_sel = posmod(main_sel - 1, count)
				K_DOWN, K_RIGHT:
					main_sel = posmod(main_sel + 1, count)
		match key:
			K_CANCEL:
				if menu == 0:
					return {"cancel": true}
				menu = 0
				main_sel = 3
			K_OK:
				if menu == 0:
					match main_sel:
						0:
							var t := await _select_enemy_target(role, true)
							if t == -2:
								continue
							return {"type": ACT_ATTACK, "id": 0, "target": t}
						1:
							var mag := await _choose_magic(role)
							if mag.is_empty():
								continue
							var target := int(mag.get("target", -1))
							if bool(mag.get("need_enemy", false)):
								var et := await _select_enemy_target(role, bool(mag.get("apply_all", false)))
								if et == -2:
									continue
								target = et
							else:
								var pt := await _select_player_target(role, bool(mag.get("apply_all", false)))
								if pt == -2:
									continue
								target = pt
							return {"type": ACT_MAGIC, "id": int(mag["id"]), "target": target}
						2:
							var coop := _coop_magic(role)
							if coop <= 0:
								_show_msg("无法使用合击")
								await _wait(10)
								continue
							var mi := bd.magic_object(coop)
							var apply_all := (int(mi.get("flags", 0)) & MAGIC_FLAG_APPLY_TO_ALL) != 0
							var ci := bd.magic_def(int(mi.get("magic_number", 0)))
							var ct := -1
							if int(ci.get("type", 0)) == MAGIC_NORMAL:
								ct = await _select_enemy_target(role, false)
								if ct == -2:
									continue
							else:
								ct = -1
							return {"type": ACT_COOP, "id": coop, "target": ct}
						3:
							menu = 1
							main_sel = 0
				elif menu == 1:
					match main_sel:
						0:
							menu = 2
							main_sel = 0
						1:
							return {"type": ACT_DEFEND, "id": 0, "target": -1}
						2:
							print("[battle] 玩家%d 选择逃跑（boss=%s 禁用=%s）" % [pi, _is_boss, flee_disabled])
							return {"type": ACT_FLEE, "id": 0, "target": -1}
						3:
							_auto_attack = true
							print("[battle] 自动战斗开启")
							continue
						4:
							await _show_status()
				else:
					match main_sel:
						0:
							var item := await _choose_item(role, ITEM_USABLE)
							if item <= 0:
								menu = 0
								main_sel = 3
								continue
							var pt := await _select_player_target(role, false)
							if pt == -2:
								continue
							return {"type": ACT_USE_ITEM, "id": item, "target": pt}
						1:
							var item2 := await _choose_item(role, ITEM_THROWABLE)
							if item2 <= 0:
								menu = 0
								main_sel = 3
								continue
							var et := await _select_enemy_target(role, false)
							if et == -2:
								continue
							return {"type": ACT_THROW_ITEM, "id": item2, "target": et}
	return {"cancel": true}


func _choose_magic(role: int) -> Dictionary:
	var list := _magic_list(role)
	if list.is_empty():
		_show_msg("没有可用的仙术")
		await _wait(10)
		return {}
	var sel := 0
	while true:
		ui.hide_menus()
		var names := PackedStringArray()
		for id in list:
			var md := bd.magic_def(int(bd.magic_object(id).get("magic_number", 0)))
			names.append("%s  (%d)" % [_word(id), int(md.get("cost_mp", 0))])
		ui.set_list_menu("仙术", names, sel)
		_draw_scene()
		var key := await _get_key()
		match key:
			K_UP, K_LEFT:
				sel = posmod(sel - 1, list.size())
			K_DOWN, K_RIGHT:
				sel = posmod(sel + 1, list.size())
			K_CANCEL:
				return {}
			K_OK:
				var id: int = list[sel]
				var mo := bd.magic_object(id)
				var flags := int(mo.get("flags", 0))
				var md := bd.magic_def(int(mo.get("magic_number", 0)))
				var mtype := int(md.get("type", 0))
				var to_enemy := (flags & MAGIC_USABLE_TO_ENEMY) != 0
				var apply_all := (flags & MAGIC_FLAG_APPLY_TO_ALL) != 0
				return {
					"id": id,
					"need_enemy": to_enemy,
					"apply_all": apply_all,
					"target": -1 if (apply_all or not to_enemy) else 0,
					"type": mtype,
				}
	return {}


func _choose_item(role: int, required_flag: int) -> int:
	var list := _item_list(required_flag)
	if list.is_empty():
		_show_msg("没有可用的物品")
		await _wait(10)
		return 0
	var sel := 0
	while true:
		ui.hide_menus()
		var names := PackedStringArray()
		for id in list:
			names.append("%s  x%d" % [_word(id), _item_available(id)])
		ui.set_list_menu("物品", names, sel)
		_draw_scene()
		var key := await _get_key()
		match key:
			K_UP, K_LEFT:
				sel = posmod(sel - 1, list.size())
			K_DOWN, K_RIGHT:
				sel = posmod(sel + 1, list.size())
			K_CANCEL:
				return 0
			K_OK:
				return int(list[sel])
	return 0


## 目标选择（敌人）。返回敌人下标；-1 = 全体；-2 = 取消。
func _select_enemy_target(role: int, allow_all: bool) -> int:
	var alive: Array[int] = []
	for i in range(max_enemy_index + 1):
		if int(enemies[i].get("object_id", 0)) != 0 and int((enemies[i]["e"] as Dictionary)["health"]) > 0:
			alive.append(i)
	if alive.is_empty():
		return -1
	if allow_all and _player_can_attack_all(role):
		return -1
	if alive.size() == 1:
		return alive[0]
	var sel := 0
	while true:
		ui.set_arrows([_enemy_target_rect(alive[sel])])
		_draw_scene()
		var key := await _get_key()
		match key:
			K_UP, K_LEFT:
				sel = posmod(sel - 1, alive.size())
			K_DOWN, K_RIGHT:
				sel = posmod(sel + 1, alive.size())
			K_CANCEL:
				ui.set_arrows([])
				return -2
			K_OK:
				ui.set_arrows([])
				return alive[sel]
	return -1


## 目标选择（我方）。返回玩家下标；-1 = 全体；-2 = 取消。
func _select_player_target(role: int, allow_all: bool) -> int:
	if allow_all:
		return -1
	if players.size() == 1:
		return 0
	var sel := 0
	while true:
		ui.set_arrows([_player_target_rect(sel)])
		_draw_scene()
		var key := await _get_key()
		match key:
			K_UP, K_LEFT:
				sel = posmod(sel - 1, players.size())
			K_DOWN, K_RIGHT:
				sel = posmod(sel + 1, players.size())
			K_CANCEL:
				ui.set_arrows([])
				return -2
			K_OK:
				ui.set_arrows([])
				return sel
	return 0


func _show_status() -> void:
	var text := ""
	for p in players:
		var role := int(p["role"])
		text += "%s Lv%d HP %d/%d MP %d/%d\n" % [
			_player_name(p), int(_level(role)), _hp(role), _max_hp(role), _mp(role), _max_mp(role)]
	_show_msg(text)
	await _wait(30)


# ------------------------------------------------------------------ 行动队列

func _enemy_dexterity(i: int) -> int:
	var e: Dictionary = enemies[i]
	var st: Dictionary = e["e"]
	return (int(st["level"]) + 6) * 3 + int(st["dexterity"])


func _player_actual_dexterity(role: int) -> int:
	var dex := _dexterity(role)
	if _status(role, ST_HASTE) != 0:
		dex *= 3
	return mini(999, dex)


func _build_action_queue() -> void:
	_action_queue.clear()
	# 敌人：先入队（wDualMove 的敌人入队两次，两??次序随机??
	for i in range(max_enemy_index + 1):
		var e: Dictionary = enemies[i]
		if int(e.get("object_id", 0)) == 0:
			continue
		var st: Dictionary = e["e"]
		var dex1 := int(float(_enemy_dexterity(i)) * randf_range(0.9, 1.1))
		_action_queue.append({"is_enemy": true, "index": i, "dexterity": dex1})
		if int(st["dual_move"]) != 0:
			var dex2 := int(float(_enemy_dexterity(i)) * randf_range(0.9, 1.1))
			_action_queue.append({"is_enemy": true, "index": i, "dexterity": dex2})
	# 玩??
	for i in range(players.size()):
		var p: Dictionary = players[i]
		var role := int(p["role"])
		var dex := 0
		if _hp(role) == 0 or _status(role, ST_SLEEP) > 0 or _status(role, ST_PARALYZED) > 0:
			dex = 0
			p["action"] = {"type": ACT_ATTACK, "id": 0, "target": -1}
			p["state"] = FIGHTER_ACT
		else:
			dex = _player_actual_dexterity(role)
			if _status(role, ST_CONFUSED) > 0:
				p["action"] = {"type": ACT_ATTACK, "id": 0, "target": -1}
				p["state"] = FIGHTER_ACT
			match int((p["action"] as Dictionary)["type"]):
				ACT_COOP:
					dex *= 10
				ACT_DEFEND:
					dex *= 5
				ACT_MAGIC:
					var mi := bd.magic_object(int((p["action"] as Dictionary)["id"]))
					if (int(mi.get("flags", 0)) & MAGIC_USABLE_TO_ENEMY) == 0:
						dex *= 3
				ACT_FLEE:
					dex /= 2
				ACT_USE_ITEM:
					dex *= 3
			if _is_player_dying(role):
				dex /= 2
			dex = int(float(dex) * randf_range(0.9, 1.1))
		_action_queue.append({"is_enemy": false, "index": i, "dexterity": dex})
	_action_queue.sort_custom(func(a, b): return int(a["dexterity"]) > int(b["dexterity"]))
	_cur_action = 0
	_ui_trace("queue=" + str(_action_queue))


# ------------------------------------------------------------------ 执行阶段

func _perform_phase() -> void:
	for q in _action_queue:
		if result != "":
			return
		if enemy_cleared:
			result = "win"
			return
		_ui_trace("perform %s" % str(q))
		if bool(q["is_enemy"]):
			var i := int(q["index"])
			if int(enemies[i].get("object_id", 0)) == 0:
				continue
			await _enemy_perform(i)
		else:
			var pi := int(q["index"])
			if int(players[pi]["state"]) != FIGHTER_ACT:
				continue
			await _player_perform(pi)
		if _all_players_dead():
			result = "lose" if not force_win else "win"
			return
		if enemy_cleared:
			result = "win"
			return
	_cur_action = 0


# ---------------------------------------------------------------- 玩家行动

func _player_perform(pi: int) -> void:
	var p: Dictionary = players[pi]
	var role := int(p["role"])
	var orig_target := int((p["action"] as Dictionary).get("target", -1))
	_validate_action(pi)
	_backup_stats()
	var act: Dictionary = p["action"]
	var target := int(act.get("target", -1))
	p["second_attack"] = false
	print("[battle] 玩家%d(%s) 执行: %s 目标=%d" % [pi, _player_name(p), _action_name(act), target])
	match int(act["type"]):
		ACT_ATTACK:
			await _do_player_attack(pi, target)
		ACT_ATTACK_MATE:
			await _do_player_attack_mate(pi)
		ACT_COOP:
			await _do_player_coop(pi, int(act["id"]), target)
		ACT_DEFEND:
			p["defending"] = true
			_exp_count(role, "defense", 2)
			_show_msg("%s 进入防御" % _player_name(p))
			await _wait(8)
		ACT_FLEE:
			await _do_player_flee(pi, role)
		ACT_MAGIC:
			await _do_player_magic(pi, role, int(act["id"]), target)
		ACT_USE_ITEM:
			await _do_player_use_item(pi, role, int(act["id"]), target)
		ACT_THROW_ITEM:
			await _do_player_throw_item(pi, role, int(act["id"]), target)
		_:
			pass
	p["state"] = FIGHTER_WAIT
	p["action"] = {"type": int(act["type"]), "id": int(act.get("id", 0)), "target": orig_target}
	await _post_action_check(false)


## fight.c PAL_BattlePlayerValidateAction
func _validate_action(pi: int) -> void:
	var p: Dictionary = players[pi]
	var act: Dictionary = p["action"]
	var role := int(p["role"])
	var to_enemy := false
	match int(act["type"]):
		ACT_ATTACK:
			to_enemy = true
		ACT_MAGIC:
			var id := int(act["id"])
			var known := _magic_list(role).has(id)
			var valid := known
			var mi := bd.magic_object(id)
			var md := bd.magic_def(int(mi.get("magic_number", 0)))
			if _status(role, ST_SILENCE) > 0:
				valid = false
			if _mp(role) < int(md.get("cost_mp", 0)):
				valid = false
			if (int(mi.get("flags", 0)) & MAGIC_USABLE_TO_ENEMY) != 0:
				if not valid:
					act["type"] = ACT_ATTACK
					act["id"] = 0
				elif (int(mi.get("flags", 0)) & MAGIC_FLAG_APPLY_TO_ALL) != 0:
					act["target"] = -1
				elif int(act.get("target", -1)) == -1:
					act["target"] = _select_auto_enemy()
				to_enemy = true
			else:
				if not valid:
					act["type"] = ACT_DEFEND
				elif (int(mi.get("flags", 0)) & MAGIC_FLAG_APPLY_TO_ALL) != 0:
					act["target"] = -1
				elif int(act.get("target", -1)) == -1:
					act["target"] = pi
		ACT_COOP:
			to_enemy = true
			var healthy := 0
			for q in players:
				if _is_player_healthy(int(q["role"])):
					healthy += 1
			if healthy <= 1:
				act["type"] = ACT_ATTACK
				act["id"] = 0
		ACT_USE_ITEM:
			if _item_available(int(act["id"])) <= 0:
				act["type"] = ACT_DEFEND
			else:
				var io := bd.item_object(int(act["id"]))
				if (int(io.get("flags", 0)) & ITEM_APPLY_TO_ALL) != 0:
					act["target"] = -1
				elif int(act.get("target", -1)) == -1:
					act["target"] = pi
		ACT_THROW_ITEM:
			to_enemy = true
			if _item_available(int(act["id"])) <= 0:
				act["type"] = ACT_ATTACK
				act["id"] = 0
			else:
				var io2 := bd.item_object(int(act["id"]))
				if (int(io2.get("flags", 0)) & ITEM_APPLY_TO_ALL) != 0:
					act["target"] = -1
				elif int(act.get("target", -1)) == -1:
					act["target"] = _select_auto_enemy()
		ACT_ATTACK_MATE:
			if _status(role, ST_CONFUSED) == 0:
				to_enemy = true
				act["type"] = ACT_ATTACK
				act["id"] = 0
		_:
			pass
	# PAL_PlayerCanAttackAll 的收尾????
	if int(act["type"]) == ACT_ATTACK:
		if int(act.get("target", -1)) == -1:
			if not _player_can_attack_all(role):
				act["target"] = _select_auto_enemy()
		elif _player_can_attack_all(role):
			act["target"] = -1
	if to_enemy and int(act.get("target", -1)) >= 0:
		var t := int(act["target"])
		if t > max_enemy_index or int(enemies[t].get("object_id", 0)) == 0:
			act["target"] = _select_auto_enemy()


func _ui_trace(msg: String) -> void:
	if _test_mode:
		printerr("[ui-trace] ", msg)


## fight.c PAL_BattlePlayerPerformAction: kBattleActionAttack
func _do_player_attack(pi: int, target: int) -> void:
	var p: Dictionary = players[pi]
	var role := int(p["role"])
	var dual := _status(role, ST_DUAL_ATTACK) > 0
	var times := 2 if dual else 1
	if target >= 0:
		for t in range(times):
			var e: Dictionary = enemies[target]
			if int(e.get("object_id", 0)) == 0:
				break
			var st: Dictionary = e["e"]
			var str := float(_attack_strength(role))
			var def := float(int(st["defense"]) + (int(st["level"]) + 6) * 4)
			var res := int(st["physical_resistance"])
			var dmg := _calc_physical_damage(str, def, res)
			dmg += _rand(1, 2)
			var critical := false
			if _rand(0, 5) == 0 or _status(role, ST_BRAVERY) > 0:
				dmg *= 3
				critical = true
			if role == 0 and _rand(0, 11) == 0:
				dmg *= 2  # 李逍遥的额外一击
				critical = true
			dmg = int(float(dmg) * randf_range(1.0, 1.125))
			if dmg <= 0:
				dmg = 1
			st["health"] = int(st["health"]) - dmg
			print("[battle]   攻击 玩家%d→敌%d 伤害=%d crit=%s HP=%d/%d%s" % [
				pi, target, dmg, critical, maxi(0, int(st["health"])),
				int(bd.enemy_def(int(e["enemy_id"])).get("health", 0)),
				(" [str=%d def=%d res=%d]" % [_attack_strength(role), int(def), res]) if _test_mode else ""])
			await _show_player_attack_anim(pi, target, critical)
	else:
		var order := [2, 1, 0, 4, 3]
		for t in range(times):
			var division := 1
			var critical2 := (_rand(0, 5) == 0 or _status(role, ST_BRAVERY) > 0)
			for idx in order:
				var i := int(idx)
				if i > max_enemy_index:
					continue
				var e2: Dictionary = enemies[i]
				if int(e2.get("object_id", 0)) == 0:
					continue
				var st2: Dictionary = e2["e"]
				var str2 := float(_attack_strength(role))
				var def2 := float(int(st2["defense"]) + (int(st2["level"]) + 6) * 4)
				var res2 := int(st2["physical_resistance"])
				var dmg2 := _calc_physical_damage(str2, def2, res2)
				if critical2:
					dmg2 *= 3
				dmg2 = int(float(dmg2) / float(division))
				if dmg2 <= 0:
					dmg2 = 1
				st2["health"] = int(st2["health"]) - dmg2
				print("[battle]   群攻 玩家%d→敌%d 伤害=%d HP=%d/%d" % [pi, i, dmg2,
					maxi(0, int(st2["health"])), int(bd.enemy_def(int(e2["enemy_id"])).get("health", 0))])
				if int(e2.get("object_id", 0)) != 0:
					division *= 2
			await _show_player_attack_all_anim(pi, critical2)
	p["second_attack"] = false
	_exp_count(role, "attack", 1)
	_exp_count(role, "health", _rand(2, 3))
	await _display_stat_change()
	await _wait(3)


func _do_player_attack_mate(pi: int) -> void:
	var p: Dictionary = players[pi]
	var role := int(p["role"])
	var alive: Array[int] = []
	for i in range(players.size()):
		if i != pi and _hp(int(players[i]["role"])) > 0:
			alive.append(i)
	if alive.is_empty():
		return
	var ti: int = alive[_rand(0, alive.size() - 1)]
	var tr := int(players[ti]["role"])
	var str := float(_attack_strength(role))
	var def := float(_defense(tr))
	if bool(players[ti]["defending"]):
		def *= 2
	var dmg := _calc_physical_damage(str, def, 2)
	if _status(tr, ST_PROTECT) > 0:
		dmg /= 2
	if dmg <= 0:
		dmg = 1
	dmg = mini(dmg, _hp(tr))
	_set_hp(tr, _hp(tr) - dmg)
	print("[battle]   混乱攻击队友 玩家%d→玩家%d 伤害=%d" % [pi, ti, dmg])
	_show_msg("%s 攻击了 %s" % [_player_name(p), _player_name(players[ti])])
	await _wait(12)
	await _display_stat_change()


func _do_player_magic(pi: int, role: int, obj_id: int, target: int) -> void:
	var p: Dictionary = players[pi]
	var mi := bd.magic_object(obj_id)
	var mnum := int(mi.get("magic_number", 0))
	var md := bd.magic_def(mnum)
	if md.is_empty():
		return
	var mtype := int(md.get("type", 0))
	_show_msg("%s 使用 %s" % [_player_name(p), _word(obj_id)])
	# PAL_BattleShowPlayerPreMagicAnim：后??蓄力（简化）
	_ui_trace("magic cast_anim begin")
	await _magic_cast_anim(pi, obj_id, target, false)
	_ui_trace("magic cast_anim done")
	if _state != null:
		_set_mp(role, _mp(role) - int(md.get("cost_mp", 0)))
	else:
		_set_mp(role, _mp(role) - int(md.get("cost_mp", 0)))
	# script_on_use / script_on_success
	_run_script(int(mi.get("script_on_use", 0)), role)
	var is_defensive := (mtype == MAGIC_APPLY_TO_PLAYER or mtype == MAGIC_APPLY_TO_PARTY or mtype == MAGIC_TRANCE)
	if is_defensive:
		_run_script(int(mi.get("script_on_success", 0)), role)
		_show_msg("%s 使用 %s" % [_player_name(p), _word(obj_id)])
		await _wait(10)
	else:
		await _play_fire_effect(mnum, target)
		_run_script(int(mi.get("script_on_success", 0)), 0xFFFF if target < 0 else target)
		_ui_trace("after script_on_success")
		if int(md.get("base_damage", 0)) > 0:
			if target == -1:
				for i in range(max_enemy_index + 1):
					var e: Dictionary = enemies[i]
					if int(e.get("object_id", 0)) == 0:
						continue
					var st: Dictionary = e["e"]
					var def := float(int(st["defense"]) + (int(st["level"]) + 6) * 4)
					var dmg := _calc_magic_damage(_magic_strength(role), def,
						_elem_res_of_enemy(st), int(st["poison_resistance"]), 1, obj_id)
					if dmg <= 0:
						dmg = 1
					st["health"] = int(st["health"]) - dmg
					print("[battle]   法术 玩家%d→敌%d 伤害=%d HP=%d" % [pi, i, dmg, int(st["health"])])
			else:
				var e2: Dictionary = enemies[target]
				if int(e2.get("object_id", 0)) != 0:
					var st2: Dictionary = e2["e"]
					var def2 := float(int(st2["defense"]) + (int(st2["level"]) + 6) * 4)
					var dmg2 := _calc_magic_damage(_magic_strength(role), def2,
						_elem_res_of_enemy(st2), int(st2["poison_resistance"]), 1, obj_id)
					if dmg2 <= 0:
						dmg2 = 1
					st2["health"] = int(st2["health"]) - dmg2
					print("[battle]   法术 玩家%d→敌%d 伤害=%d HP=%d" % [pi, target, dmg2, int(st2["health"])])
	if await _display_stat_change():
		await _wait(8)
	_exp_count(role, "magic", _rand(2, 3))
	_exp_count(role, "magic_power", 1)
	_ui_trace("magic done")
	await _wait(4)


func _do_player_coop(pi: int, obj_id: int, target: int) -> void:
	var p: Dictionary = players[pi]
	var mi := bd.magic_object(obj_id)
	var mnum := int(mi.get("magic_number", 0))
	var md := bd.magic_def(mnum)
	if md.is_empty():
		return
	var contributors: Array[int] = []
	for i in range(players.size()):
		if _is_player_healthy(int(players[i]["role"])):
			contributors.append(i)
	if contributors.size() < 2:
		return
	_show_msg("%s 发动合击！" % _player_name(p))
	await _wait(16)
	# 合击消???：从每??HP 扣除 wCostMP（sdlpal ??HP 而非 MP），至少保留 1
	for i in contributors:
		var r := int(players[i]["role"])
		var cost := int(md.get("cost_mp", 0))
		_set_hp(r, _hp(r) - cost)
		if _hp(r) <= 0:
			_set_hp(r, 1)
		players[i]["state"] = FIGHTER_WAIT
	_backup_stats()
	var str := 0.0
	for i in contributors:
		var r2 := int(players[i]["role"])
		str += float(_attack_strength(r2)) + float(_magic_strength(r2))
	str = int(str / 4.0)
	if int(md.get("type", 0)) == MAGIC_SUMMON:
		await _play_fire_effect(mnum, target)
	# 伤??
	if target == -1:
		for i in range(max_enemy_index + 1):
			var e: Dictionary = enemies[i]
			if int(e.get("object_id", 0)) == 0:
				continue
			var st: Dictionary = e["e"]
			var def := float(int(st["defense"]) + (int(st["level"]) + 6) * 4)
			var dmg := _calc_magic_damage(str, def, _elem_res_of_enemy(st),
				int(st["poison_resistance"]), 1, obj_id)
			if dmg <= 0:
				dmg = 1
			st["health"] = int(st["health"]) - dmg
			print("[battle]   合击 敌%d 伤害=%d" % [i, dmg])
	else:
		if target <= max_enemy_index:
			var e2: Dictionary = enemies[target]
			if int(e2.get("object_id", 0)) != 0:
				var st2: Dictionary = e2["e"]
				var def2 := float(int(st2["defense"]) + (int(st2["level"]) + 6) * 4)
				var dmg2 := _calc_magic_damage(str, def2, _elem_res_of_enemy(st2),
					int(st2["poison_resistance"]), 1, obj_id)
				if dmg2 <= 0:
					dmg2 = 1
				st2["health"] = int(st2["health"]) - dmg2
				print("[battle]   合击 敌%d 伤害=%d" % [target, dmg2])
	await _display_stat_change()
	await _wait(6)


func _do_player_flee(pi: int, role: int) -> void:
	var p: Dictionary = players[pi]
	var rate := _flee_rate(role)
	var def := 0
	for i in range(max_enemy_index + 1):
		var e: Dictionary = enemies[i]
		if int(e.get("object_id", 0)) == 0:
			continue
		var st: Dictionary = e["e"]
		def += int(st["dexterity"])
		def += (int(st["level"]) + 6) * 4
	if def < 0:
		def = 0
	if rate >= _rand(0, def) and not _is_boss and not flee_disabled:
		print("[battle]   逃跑成功 rate=%d def=%d" % [rate, def])
		_show_msg("逃跑成功！")
		await _wait(10)
		await _player_escape_anim()
		result = "flee"
	else:
		print("[battle]   逃跑失败 rate=%d def=%d" % [rate, def])
		p["frame"] = 1
		_show_msg("%s 逃跑失败！" % _player_name(p))
		await _wait(45)
		_exp_count(role, "flee", 2)


func _do_player_use_item(pi: int, role: int, item_id: int, target: int) -> void:
	var p: Dictionary = players[pi]
	var io := bd.item_object(item_id)
	_show_msg("%s 使用 %s" % [_player_name(p), _word(item_id)])
	await _wait(8)
	_run_script(int(io.get("script_on_use", 0)), role)
	if (int(io.get("flags", 0)) & ITEM_CONSUMING) != 0:
		_consume_item(item_id)
	if await _display_stat_change():
		await _wait(8)
	await _wait(4)


func _do_player_throw_item(pi: int, role: int, item_id: int, target: int) -> void:
	var p: Dictionary = players[pi]
	var io := bd.item_object(item_id)
	_show_msg("%s 投掷 %s" % [_player_name(p), _word(item_id)])
	await _wait(10)
	_run_script(int(io.get("script_on_throw", 0)), 0xFFFF if target < 0 else target)
	_consume_item(item_id)
	if await _display_stat_change():
		await _wait(8)
	await _wait(4)


# ---------------------------------------------------------------- 敌人行动

func _enemy_perform(i: int) -> void:
	var e: Dictionary = enemies[i]
	if int(e.get("object_id", 0)) == 0:
		return
	var st: Dictionary = e["e"]
	_backup_stats()
	if int(st["health"]) <= 0:
		return
	if _status_enemy(e, ST_SLEEP) > 0 or _status_enemy(e, ST_PARALYZED) > 0:
		return
	# 选目标（sdlpal PAL_BattleEnemySelectTargetIndex：随机存活玩家）
	var targets: Array[int] = []
	for pi in range(players.size()):
		if _hp(int(players[pi]["role"])) > 0:
			targets.append(pi)
	if targets.is_empty():
		return
	var ti: int = targets[_rand(0, targets.size() - 1)]
	var tr := int(players[ti]["role"])
	print("[battle] 敌%d(%s) 行动 → 玩家%d(%s)" % [i, _player_name_enemy(e), ti, _player_name(players[ti])])
	if _status_enemy(e, ST_CONFUSED) > 0:
		var other: Array[int] = []
		for k in range(max_enemy_index + 1):
			if k != i and int(enemies[k].get("object_id", 0)) != 0:
				other.append(k)
		if other.is_empty():
			return
		var tgt: int = other[_rand(0, other.size() - 1)]
		var est: Dictionary = enemies[tgt]["e"]
		var str := int(st["attack_strength"]) + (int(st["level"]) + 6) * 6
		var def := int(est["defense"]) + (int(est["level"]) + 6) * 4
		var dmg := int(_calc_base_damage(float(str), float(def)) * 2.0 / maxf(1.0, float(est["physical_resistance"])))
		if dmg <= 0:
			dmg = 1
		est["health"] = int(est["health"]) - dmg
		print("[battle]   敌人混乱攻击敌%d 伤害=%d" % [tgt, dmg])
		_show_msg("敌人陷入混乱")
		await _wait(12)
		await _display_stat_change()
		await _post_action_check(false)
		return
	var wmagic := int(st.get("magic", 0))
	var magic_rate := int(st.get("magic_rate", 0))
	if wmagic != 0 and _rand(0, 9) < magic_rate and _status_enemy(e, ST_SILENCE) == 0:
		if wmagic == 0xFFFF:
			return
		await _enemy_cast_magic(i, ti, wmagic, tr)
	else:
		await _enemy_normal_attack(i, ti, tr)
	await _post_action_check(true)


func _enemy_normal_attack(i: int, ti: int, tr: int) -> void:
	var e: Dictionary = enemies[i]
	var st: Dictionary = e["e"]
	var p: Dictionary = players[ti]
	var role := int(p["role"])
	var attacking := int(st["attack_strength"]) + (int(st["level"]) + 6) * 6
	if attacking < 0:
		attacking = 0
	var def := float(_defense(tr))
	if bool(p["defending"]):
		def *= 2
	# ????防御/掩护判定（fight.c 同源，简化移除了动画分支??
	var auto_defend := _rand(0, 16) >= 10
	var cover_index := -1
	var bad := _is_player_dying(tr) or _status(tr, ST_CONFUSED) > 0 or _status(tr, ST_SLEEP) > 0 or _status(tr, ST_PARALYZED) > 0
	if bad and auto_defend:
		var cover_role := _covered_by(tr)
		for k in range(players.size()):
			if int(players[k]["role"]) == cover_role:
				cover_index = k
				break
		if cover_index >= 0:
			var cr := int(players[cover_index]["role"])
			if _is_player_dying(cr) or _status(cr, ST_CONFUSED) > 0 or _status(cr, ST_SLEEP) > 0 or _status(cr, ST_PARALYZED) > 0:
				cover_index = -1
	if cover_index == -1 and (_status(tr, ST_CONFUSED) > 0 or _status(tr, ST_SLEEP) > 0 or _status(tr, ST_PARALYZED) > 0):
		auto_defend = false
	# 攻击动画：先魔法帧再攻击帧（fight.c 同源），这里??化为??次前??
	p["frame"] = 4
	await _wait(4)
	if auto_defend:
		p["frame"] = 3
		_show_msg("%s 防御了攻击" % _player_name(p))
		await _wait(10)
		p["frame"] = 0
		await _wait(4)
		return
	var dmg := _calc_physical_damage(float(attacking + _rand(0, 2)), def, 2)
	dmg += _rand(0, 1)
	if _status(tr, ST_PROTECT) > 0:
		dmg /= 2
	if _hp(tr) < dmg:
		dmg = _hp(tr)
	if dmg <= 0:
		dmg = 1
	_set_hp(tr, _hp(tr) - dmg)
	p["frame"] = 4
	print("[battle]   敌方物理攻击 玩家%d 伤害=%d HP=%d/%d" % [ti, dmg, _hp(tr), _max_hp(tr)])
	await _display_stat_change()
	await _wait(3)
	p["frame"] = 2 if _hp(tr) == 0 else (1 if _is_player_dying(tr) else 0)
	await _wait(8)
	# 附加“攻击等价物品???的??状???脚????fight.c 结尾??
	var equiv := int(st.get("attack_equiv_item", 0))
	var equiv_rate := int(st.get("attack_equiv_item_rate", 0))
	if cover_index == -1 and not auto_defend and equiv_rate >= _rand(1, 10) and _poison_resistance(tr) < _rand(1, 100):
		var io := bd.item_object(equiv)
		if not io.is_empty():
			_run_script(int(io.get("script_on_use", 0)), tr)


func _enemy_cast_magic(i: int, ti: int, wmagic: int, tr: int) -> void:
	var e: Dictionary = enemies[i]
	var st: Dictionary = e["e"]
	var mi := bd.magic_object(wmagic)
	var mnum := int(mi.get("magic_number", 0))
	var md := bd.magic_def(mnum)
	if md.is_empty():
		return
	var mtype := int(md.get("type", 0))
	var magic_str := int(st["magic_strength"]) + (int(st["level"]) + 6) * 6
	if magic_str < 0:
		magic_str = 0
	_show_msg("%s 使用 %s" % [_player_name_enemy(e), _word(wmagic)])
	await _wait(10)
	await _play_fire_effect(mnum, -1 if mtype != MAGIC_NORMAL else ti)
	_run_script(int(mi.get("script_on_use", 0)), tr)
	_run_script(int(mi.get("script_on_success", 0)), tr)
	if int(md.get("base_damage", 0)) > 0:
		var elem_res: Array[int] = []
		for x in range(5):
			elem_res.append(100 + _elem_resistance(tr, x))
		var poison_res := 100 + _poison_resistance(tr)
		var def := float(_defense(tr))
		if mtype != MAGIC_NORMAL:
			for k in range(players.size()):
				var pr := int(players[k]["role"])
				if _hp(pr) == 0:
					continue
				var auto_defend := false
				if _status(pr, ST_SLEEP) == 0 and _status(pr, ST_PARALYZED) == 0 and _status(pr, ST_CONFUSED) == 0 and _rand(0, 2) == 0:
					auto_defend = true
					players[k]["frame"] = 3
				var er: Array[int] = []
				for x2 in range(5):
					er.append(100 + _elem_resistance(pr, x2))
				var d := _calc_magic_damage(float(magic_str), float(_defense(pr)), er,
					100 + _poison_resistance(pr), 20, wmagic)
				d = int(float(d) / float((2 if bool(players[k]["defending"]) else 1) *
					(2 if _status(pr, ST_PROTECT) > 0 else 1) + (1 if auto_defend else 0)))
				if d > _hp(pr):
					d = _hp(pr)
				if d < 0:
					d = 0
				_set_hp(pr, _hp(pr) - d)
				print("[battle]   敌方法术 玩家%d 伤害=%d HP=%d/%d" % [k, d, _hp(pr), _max_hp(pr)])
				if _hp(pr) == 0:
					_sound(_sound_of(players[k], "death_sound"))
		else:
			var auto_defend2 := false
			if _status(tr, ST_SLEEP) == 0 and _status(tr, ST_PARALYZED) == 0 and _status(tr, ST_CONFUSED) == 0 and _rand(0, 2) == 0:
				auto_defend2 = true
				players[ti]["frame"] = 3
			var d2 := _calc_magic_damage(float(magic_str), def, elem_res, poison_res, 20, wmagic)
			d2 = int(float(d2) / float((2 if bool(players[ti]["defending"]) else 1) *
				(2 if _status(tr, ST_PROTECT) > 0 else 1) + (1 if auto_defend2 else 0)))
			if d2 > _hp(tr):
				d2 = _hp(tr)
			if d2 < 0:
				d2 = 0
			_set_hp(tr, _hp(tr) - d2)
			players[ti]["frame"] = 4
			print("[battle]   敌方法术 玩家%d 伤害=%d HP=%d/%d" % [ti, d2, _hp(tr), _max_hp(tr)])
			if _hp(tr) == 0:
				_sound(_sound_of(players[ti], "death_sound"))
	await _display_stat_change()
	await _wait(8)


# ---------------------------------------------------------------- 回合结束

func _end_turn_phase() -> void:
	# 清防御???恢复位????fight.c PAL_BattleStartFrame classic 分支??
	for p in players:
		p["defending"] = false
		p["pos"] = p["pos_original"]
	_backup_stats()
	# 玩??毒脚??+ 状???回合???减
	for pi in range(players.size()):
		var role := int(players[pi]["role"])
		await _run_poison_scripts(role)
		for s in range(STATUS_ALL):
			if _status(role, s) > 0:
				_set_status(role, s, _status(role, s) - 1)
	# 敌人毒脚??+ 状???回合???减
	for i in range(max_enemy_index + 1):
		var e: Dictionary = enemies[i]
		if int(e.get("object_id", 0)) == 0:
			continue
		for ps in e["poisons"]:
			if int(ps["poison_id"]) != 0:
				var po := bd.poison_object(int(ps["poison_id"]))
				await _run_script_async(int(po.get("enemy_script", 0)), i)
		for s2 in range(STATUS_ALL):
			if _status_enemy(e, s2) > 0:
				e["status"][s2] = int(e["status"][s2]) - 1
	await _post_action_check(false)
	if await _display_stat_change():
		await _wait(8)
	# 敌人回合??始脚????新回合）
	for i2 in range(max_enemy_index + 1):
		var e2: Dictionary = enemies[i2]
		if int(e2.get("object_id", 0)) != 0:
			await _run_script_async(int(e2.get("script_on_turn_start", 0)), i2)
	# 清空道具占用记录
	_in_use.clear()


func _run_poison_scripts(role: int) -> void:
	if _state == null or not _state.has_method("poison_scripts"):
		return
	for script in _state.poison_scripts(role):
		if int(script) != 0:
			await _run_script_async(int(script), role)


# ---------------------------------------------------------------- KO/结束判定

func _post_action_check(check_players: bool) -> void:
	var f_fade := false
	var remaining := false
	for i in range(max_enemy_index + 1):
		var e: Dictionary = enemies[i]
		if int(e.get("object_id", 0)) == 0:
			continue
		var st: Dictionary = e["e"]
		if int(st["health"]) <= 0:
			exp_gained += int(st["exp"])
			cash_gained += int(st["cash"])
			_sound(int(st["death_sound"]))
			print("[battle]   敌人%d 被击败：+%d 经验 +%d 文钱" % [i, int(st["exp"]), int(st["cash"])])
			e["object_id"] = 0
			f_fade = true
			continue
		remaining = true
	if not remaining:
		enemy_cleared = true
	if f_fade:
		# 原版 PAL_BattleFadeScene 调色板淡出；这里用白??????[inf]
		ui.clear_numbers()
		await _wait(6)
	if check_players and _state != null:
		# 队友死亡/濒??脚本（PAL_PlayerRoles.rgwName -> rgObject.player??
		for pi in range(players.size()):
			var role := int(players[pi]["role"])
			var eo := bd.player_object(int(players[pi].get("name_word", 0)))
			if eo.is_empty():
				continue
			var prev_hp := int(players[pi].get("prev_hp", _hp(role)))
			if _hp(role) == 0 and prev_hp > 0 and int(eo.get("script_on_friend_death", 0)) != 0:
				_run_script(int(eo.get("script_on_friend_death", 0)), role)
			elif _is_player_dying(role) and _hp(role) > 0 and prev_hp >= _max_hp(role) / 5 and int(eo.get("script_on_dying", 0)) != 0:
				_run_script(int(eo.get("script_on_dying", 0)), role)


func _all_players_dead() -> bool:
	for p in players:
		var role := int(p["role"])
		if _hp(role) != 0:
			return false
		if _status(role, ST_PUPPET) != 0:
			return false
	return true


# ---------------------------------------------------------------- 战斗结束

func _on_battle_end() -> void:
	ui.hide_menus()
	ui.clear_numbers()
	print("[battle] 战斗结束 result=%s 回合=%d 经验=%d 文钱=%d" % [result, turn_no, exp_gained, cash_gained])
	if result == "win" and not _terminated:
		await _battle_won()
	elif result == "win":
		_show_msg("战斗结束")
		await _wait(10)
	elif result == "flee":
		_show_msg("成功逃离战斗")
		await _wait(12)
	else:
		_show_msg("战斗失败……")
		await _wait(20)
	# 清理 Battle 状???（battle.c PAL_StartBattle 尾部??
	if _state != null:
		if _state.has_method("clear_all_player_status"):
			_state.clear_all_player_status()
		if _state.has_method("cure_all_poisons_by_level"):
			_state.cure_all_poisons_by_level(3)
		if _state.has_method("remove_equipment_effect"):
			for role in range(MAX_ROLES):
				_state.remove_equipment_effect(role, 6)
		_state.in_battle = false


## battle.c PAL_BattleWon：经验/金钱结算、升级、隐藏经验、学仙术、战后脚本、自动回复。
func _battle_won() -> void:
	_show_msg("打败敌人！\n获得经验 %d    获得文钱 %d" % [exp_gained, cash_gained])
	await _wait(30)
	if _test_mode:
		await _maybe_shot("04_win")
	if _state != null:
		_state.cash = int(_state.cash) + cash_gained
	# 主经验与升级
	for p in players:
		var role := int(p["role"])
		if _hp(role) == 0:
			continue
		var level := _level(role)
		var dw_exp := _primary_exp(role) + exp_gained
		if level > 99:
			level = 99
			_set_level(role, level)
		var leveled := false
		var guard := 0
		while dw_exp >= _exp_to_next(level) and guard < 200:
			guard += 1
			dw_exp -= _exp_to_next(level)
			if level < 99:
				leveled = true
				if _state.has_method("player_level_up"):
					_state.player_level_up(role, 1)
				level = _level(role)
				_set_hp(role, _max_hp(role))
				_set_mp(role, _max_mp(role))
		_set_primary_exp(role, dw_exp)
		if leveled:
			print("[battle]   %s 升级到 Lv%d（HP %d/%d MP %d/%d）" % [
				_word(int(p["name_word"])), _level(role), _hp(role), _max_hp(role), _mp(role), _max_mp(role)])
			_show_msg("%s 升级到 Lv%d！" % [_word(int(p["name_word"])), _level(role)])
			await _wait(20)
		# 隐藏经验（PAL_BattleWon CHECK_HIDDEN_EXP 宏）
		var total_count := 0
		for key in ["attack", "defense", "dexterity", "flee", "health", "magic", "magic_power"]:
			total_count += _exp_count_of(role, key)
		if total_count > 0:
			var table := [
				["health", "max_hp"], ["magic", "max_mp"], ["attack", "attack_strength"],
				["magic_power", "magic_strength"], ["defense", "defense"],
				["dexterity", "dexterity"], ["flee", "flee_rate"],
			]
			for pair in table:
				var ex_key: String = pair[0]
				var stat_key: String = pair[1]
				var cnt := _exp_count_of(role, ex_key)
				var de := exp_gained * cnt / maxi(1, total_count) * 2
				de += _exp_value(role, ex_key)
				var dlv := _exp_level(role, ex_key)
				if dlv > 99:
					dlv = 99
				var guard2 := 0
				while de >= _exp_to_next(dlv) and guard2 < 200:
					guard2 += 1
					de -= _exp_to_next(dlv)
					_add_role_stat(role, stat_key, _rand(1, 2))
					if dlv < 99:
						dlv += 1
				_exp_set(role, ex_key, de, dlv)
			if leveled:
				_set_hp(role, _max_hp(role))
				_set_mp(role, _max_mp(role))
		# 学习当前等级及以下的??有仙????battle.c ??????
		for rec in bd.level_up_magic:
			if role >= rec.size():
				continue
			var rr: Dictionary = rec[role]
			var mag := int(rr.get("magic", 0))
			if mag == 0 or int(rr.get("level", 0)) > _level(role):
				continue
			if _state != null and _state.has_method("add_magic"):
				if _state.add_magic(role, mag):
					print("[battle]   学会仙术 %s" % _word(mag))
	# 战后脚本
	for i in range(max_enemy_index + 1):
		await _run_script_async(int(enemies[i].get("script_on_battle_end", 0)), i)
	# 自动回复一半缺口（battle.c PAL_BattleWon 结尾）
	for p2 in players:
		var r2 := int(p2["role"])
		_set_hp(r2, _hp(r2) + int((_max_hp(r2) - _hp(r2)) / 2))
		_set_mp(r2, _mp(r2) + int((_max_mp(r2) - _mp(r2)) / 2))
	if _test_mode and _state != null:
		# 验收证据：结算后 PALState 的现金/主经验（用于核对 PAL_BattleWon）
		print("[battle-test] 结算后 cash=%d" % int(_state.cash))
		for p3 in players:
			var r3 := int(p3["role"])
			print("[battle-test] 结算后 角色%d primary_exp=%d level=%d hp=%d/%d mp=%d/%d" % [
				r3, _primary_exp(r3), _level(r3), _hp(r3), _max_hp(r3), _mp(r3), _max_mp(r3)])


func _finish(res: String) -> void:
	result = res
	if ui != null:
		ui.hide_menus()
		ui.clear_numbers()
	print("[battle] finished result=%s" % res)
	if is_inside_tree() and ui != null:
		await ui.fade_to_black()
	finished.emit(res)


# ------------------------------------------------------------------ ScriptVM 战斗代理
# ??_ensure_script_vm() 注入；VM ??has_method 通过??callv(method, args) 调用??# ????逐条对照 sdlpal script.c 战斗 opcode??x0021/0x0028/0x002A/0x002E/0x0033/0x0039/
# 0x003A/0x0042/0x005B/0x005C/0x005E/0x0060/0x0064/0x0066/0x0067/0x0068/0x0069/0x006A/
# 0x006B/0x0089/0x008A/0x0091/0x0092/0x009C/0x009E/0x009F）???[inf]

func damage_all(dmg: int) -> void:
	for e in enemies:
		if int(e.get("object_id", 0)) != 0:
			(e["e"] as Dictionary)["health"] = int((e["e"] as Dictionary)["health"]) - dmg


func damage_one(id: int, dmg: int) -> void:
	if id >= 0 and id <= max_enemy_index and int(enemies[id].get("object_id", 0)) != 0:
		var st: Dictionary = enemies[id]["e"]
		st["health"] = int(st["health"]) - int(dmg)


func poison_one(id: int, poison_id: int) -> void:
	if id < 0 or id > max_enemy_index or int(enemies[id].get("object_id", 0)) == 0:
		return
	var e: Dictionary = enemies[id]
	if _rand(0, 9) < int(e.get("resistance_to_sorcery", 0)):
		return
	var poisons: Array = e["poisons"]
	for i in range(poisons.size()):
		if int(poisons[i]["poison_id"]) == 0:
			var po := bd.poison_object(poison_id)
			poisons[i] = {"poison_id": poison_id, "script": int(po.get("enemy_script", 0))}
			return


func poison_all(poison_id: int) -> void:
	for i in range(max_enemy_index + 1):
		poison_one(i, poison_id)


func cure_poison_one(id: int, poison_id: int) -> void:
	if id < 0 or id > max_enemy_index:
		return
	var poisons: Array = enemies[id]["poisons"]
	for i in range(poisons.size()):
		if int(poisons[i]["poison_id"]) == poison_id:
			poisons[i] = {"poison_id": 0, "script": 0}


func cure_poison_all(poison_id: int) -> void:
	for i in range(max_enemy_index + 1):
		cure_poison_one(i, poison_id)


## 返回 false = 因法术抗性失败（VM 会跳 op2）。
func set_enemy_status(id: int, status_id: int, rounds: int) -> bool:
	if id < 0 or id > max_enemy_index or int(enemies[id].get("object_id", 0)) == 0:
		return false
	var e: Dictionary = enemies[id]
	if _rand(0, 9) > int(e.get("resistance_to_sorcery", 0)):
		e["status"][status_id] = rounds
		return true
	return false


func halve_enemy_hp(id: int, limit: int) -> void:
	if id < 0 or id > max_enemy_index:
		return
	var st: Dictionary = enemies[id]["e"]
	var v := int(st["health"]) / 2
	if v < int(limit):
		v = int(limit)
	st["health"] = v


func kill_enemy(id: int) -> void:
	if id >= 0 and id <= max_enemy_index and int(enemies[id].get("object_id", 0)) != 0:
		(enemies[id]["e"] as Dictionary)["health"] = 0


func drain_enemy_hp(id: int, dmg: int) -> void:
	damage_one(id, dmg)


func flee() -> void:
	result = "flee"


func set_result(r: int) -> void:
	match int(r):
		1:
			result = "lose"
		0xFFFF:
			result = "flee"
		0:
			_terminated = true
			result = "win"
		_:
			result = "win"


func set_auto_battle() -> void:
	_auto_attack = true
	if _state != null:
		_state.vars["auto_battle"] = true


## script.c 0x0042：模拟一次法术（不做等待动画，直接结算；[inf] 与原版时序差异见注释）。
func simulate_magic(role: int, magic_obj_id: int, base_damage: int) -> void:
	var target := -1
	if role >= 0 and role <= max_enemy_index:
		target = role
	_simulate_magic_immediate(target, magic_obj_id, base_damage)


func steal(id: int, steal_rate: int) -> void:
	_steal_immediate(id, steal_rate)


func blow(dmg: int) -> void:
	_blow = dmg


## 收集敌人（0x0033）：返回 collect_value 并累计到 PALState.collect_value。
func collect_get(id: int) -> int:
	if id < 0 or id > max_enemy_index or int(enemies[id].get("object_id", 0)) == 0:
		return 0
	var v := int((enemies[id]["e"] as Dictionary).get("collect_value", 0))
	if v != 0 and _state != null:
		_state.collect_value = int(_state.collect_value) + v
	return v


## 0x0034：由 VM 的近似兜底处理（从商店抽物品），战斗代理不接管。
func collect_to_item() -> Variant:
	return null


func is_boss() -> bool:
	return _is_boss


func is_enemy_turn() -> bool:
	return _enemy_acting


func enemy_hp_percent_gt(id: int, pct: int) -> bool:
	if id < 0 or id > max_enemy_index or int(enemies[id].get("object_id", 0)) == 0:
		return false
	var st: Dictionary = enemies[id]["e"]
	var maxhp := int(bd.enemy_def(int(enemies[id].get("enemy_id", 0))).get("health", 0))
	if maxhp <= 0:
		return false
	return int(st["health"]) * 100 > maxhp * int(pct)


func enemy_poisoned(id: int, poison_id: int) -> bool:
	if id < 0 or id > max_enemy_index:
		return false
	for ps in enemies[id]["poisons"]:
		if int(ps["poison_id"]) == poison_id:
			return true
	return false


## 是否第一个敌人（前面没有存活敌人）。
func enemy_is_first(id: int) -> bool:
	for i in range(0, mini(id, max_enemy_index + 1)):
		if int(enemies[i].get("object_id", 0)) != 0:
			return false
	return true


func pre_magic_anim(_role: int) -> void:
	pass


## 0x0067：指定敌人使用的仙术与概率。
func set_enemy_magic(id: int, magic_obj_id: int, rate: int) -> void:
	if id < 0 or id > max_enemy_index:
		return
	var st: Dictionary = enemies[id]["e"]
	st["magic"] = magic_obj_id
	st["magic_rate"] = rate


## 0x005C：隐藏一段时间（负值 = 待生效，PAL_BattleCheckHidingEffect 转正）。
func set_hiding_time(n: int) -> void:
	_hiding_time = -int(n)


## 0x0069：敌人逃跑 → 终止战斗（不结算胜利奖励，脚本继续）。
func enemy_escape() -> void:
	for e in enemies:
		e["object_id"] = 0
	_terminated = true
	result = "win"


## 0x009C：分裂（仅剩 1 个敌人且 HP>1 时成功）。
func divide(id: int, _magic: int) -> bool:
	var alive := 0
	for e in enemies:
		if int(e.get("object_id", 0)) != 0:
			alive += 1
	if alive != 1:
		return false
	if id < 0 or id > max_enemy_index:
		return false
	var src: Dictionary = enemies[id]
	if int((src["e"] as Dictionary)["health"]) <= 1:
		return false
	if enemies.size() >= MAX_ENEMIES:
		# 找到空位；没有空位则失败
		var slot := -1
		for i in range(enemies.size()):
			if int(enemies[i].get("object_id", 0)) == 0:
				slot = i
				break
		if slot < 0:
			return false
		_clone_enemy_into(slot, src)
		max_enemy_index = maxi(max_enemy_index, slot)
		return true
	_clone_enemy_into(enemies.size(), src)
	max_enemy_index = enemies.size() - 1
	return true


## 0x009E：召唤（生成 operand0 指定的敌人，数量 = max(1, operand1)）。
func summon(_id: int, magic_obj_id: int, count: int) -> bool:
	var n := maxi(1, int(count))
	var created := false
	for k in range(n):
		var slot := enemies.size()
		for i in range(enemies.size()):
			if int(enemies[i].get("object_id", 0)) == 0:
				slot = i
				break
		var src: Dictionary = {}
		var obj_id := int(magic_obj_id)
		if obj_id == 0 or obj_id == 0xFFFF:
			if _id >= 0 and _id <= max_enemy_index:
				obj_id = int(enemies[_id].get("object_id", 0))
		if obj_id == 0:
			break
		var eb := bd.build_enemy_base(obj_id)
		if eb.is_empty():
			break
		if slot >= enemies.size():
			if enemies.size() >= MAX_ENEMIES:
				break
			enters_new_enemy_slot(obj_id, eb)
		else:
			_fill_enemy_slot(slot, obj_id, eb)
		created = true
	if created:
		max_enemy_index = enemies.size() - 1
	return created


## 0x009F：敌人变身（保留当前 HP）。
func transform(id: int, object_id: int) -> void:
	if id < 0 or id > max_enemy_index or int(enemies[id].get("object_id", 0)) == 0:
		return
	var eb := bd.build_enemy_base(object_id)
	if eb.is_empty():
		return
	var e: Dictionary = enemies[id]
	var hp := int((e["e"] as Dictionary)["health"])
	e["object_id"] = object_id
	e["enemy_id"] = int(eb["enemy_id"])
	e["e"] = (eb["stats"] as Dictionary).duplicate(true)
	(e["e"] as Dictionary)["health"] = hp
	e["frames"] = bd.enemy_frames(int(eb["enemy_id"]))
	e["frame"] = 0
	e["script_on_turn_start"] = int(eb["script_on_turn_start"])
	e["script_on_battle_end"] = int(eb["script_on_battle_end"])
	e["script_on_ready"] = int(eb["script_on_ready"])
	e["resistance_to_sorcery"] = int(eb["resistance_to_sorcery"])


func _clone_enemy_into(slot: int, src: Dictionary) -> void:
	var e := {
		"index": slot,
		"object_id": int(src.get("object_id", 0)),
		"enemy_id": int(src.get("enemy_id", 0)),
		"e": (src["e"] as Dictionary).duplicate(true),
		"frames": src.get("frames", []),
		"status": (src["status"] as Array).duplicate(),
		"poisons": [],
		"pos": (src["pos"] as Vector2i) + Vector2i(_rand(-24, 24), _rand(-8, 8)),
		"pos_original": src.get("pos_original", src["pos"]),
		"frame": 0,
		"state": FIGHTER_WAIT,
		"prev_hp": int((src["e"] as Dictionary)["health"]),
		"color_shift": 0,
		"script_on_turn_start": int(src.get("script_on_turn_start", 0)),
		"script_on_battle_end": int(src.get("script_on_battle_end", 0)),
		"script_on_ready": int(src.get("script_on_ready", 0)),
		"resistance_to_sorcery": int(src.get("resistance_to_sorcery", 0)),
	}
	for k in range(16):
		e["poisons"].append({"poison_id": 0, "script": 0})
	e["pos_original"] = e["pos"]
	if slot < enemies.size():
		enemies[slot] = e
	else:
		enemies.append(e)


func enters_new_enemy_slot(object_id: int, eb: Dictionary) -> void:
	_fill_enemy_slot(enemies.size(), object_id, eb)
	enemies.append(enemies[enemies.size() - 1]) if false else null


func _fill_enemy_slot(slot: int, object_id: int, eb: Dictionary) -> void:
	var poisons: Array = []
	for k in range(16):
		poisons.append({"poison_id": 0, "script": 0})
	var st: Dictionary = (eb["stats"] as Dictionary).duplicate(true)
	var e := {
		"index": slot,
		"object_id": object_id,
		"enemy_id": int(eb["enemy_id"]),
		"e": st,
		"frames": bd.enemy_frames(int(eb["enemy_id"])),
		"status": [0, 0, 0, 0, 0, 0, 0, 0, 0],
		"poisons": poisons,
		"pos": Vector2i(160, 100),
		"pos_original": Vector2i(160, 100),
		"frame": 0,
		"state": FIGHTER_WAIT,
		"prev_hp": int(st["health"]),
		"color_shift": 0,
		"script_on_turn_start": int(eb["script_on_turn_start"]),
		"script_on_battle_end": int(eb["script_on_battle_end"]),
		"script_on_ready": int(eb["script_on_ready"]),
		"resistance_to_sorcery": int(eb["resistance_to_sorcery"]),
	}
	var ppos := Vector2i(160 + _rand(-40, 40), 120 + _rand(-20, 20))
	e["pos"] = ppos
	e["pos_original"] = ppos
	if slot < enemies.size():
		enemies[slot] = e
	else:
		enemies.append(e)


## 同步版偷窃（脚本 0x006A 用，不播动画）。
func _steal_immediate(target: int, steal_rate: int) -> void:
	if target < 0 or target > max_enemy_index:
		return
	var e: Dictionary = enemies[target]
	if int(e.get("object_id", 0)) == 0:
		return
	var st: Dictionary = e["e"]
	if int(st.get("steal_item_count", 0)) <= 0:
		return
	if not (_rand(0, 10) <= steal_rate or steal_rate == 0):
		return
	if int(st.get("steal_item", 0)) == 0:
		var c := int(st["steal_item_count"]) / _rand(2, 3)
		st["steal_item_count"] = int(st["steal_item_count"]) - c
		if _state != null:
			_state.cash = int(_state.cash) + c
		if c > 0:
			_show_msg("偷到 %d 文钱" % c)
	else:
		st["steal_item_count"] = int(st["steal_item_count"]) - 1
		var item := int(st["steal_item"])
		if _state != null and _state.has_method("add_item"):
			_state.add_item(item, 1)
		_show_msg("偷到 %s" % _word(item))


## 同步版法术模拟（脚本 0x0042/0x0066 用）。
func _simulate_magic_immediate(target: int, magic_obj_id: int, base_damage: int) -> void:
	var mi := bd.magic_object(magic_obj_id)
	if mi.is_empty():
		return
	if (int(mi.get("flags", 0)) & MAGIC_FLAG_APPLY_TO_ALL) != 0:
		target = -1
	elif target == -1:
		target = _select_auto_enemy()
	var mnum := int(mi.get("magic_number", 0))
	if base_damage > 0 or int(bd.magic_def(mnum).get("base_damage", 0)) > 0:
		if target == -1:
			for i in range(max_enemy_index + 1):
				var e: Dictionary = enemies[i]
				if int(e.get("object_id", 0)) == 0:
					continue
				var st: Dictionary = e["e"]
				var def := float(int(st["defense"]) + (int(st["level"]) + 6) * 4)
				var dmg := _calc_magic_damage(float(base_damage), def, _elem_res_of_enemy(st),
					int(st["poison_resistance"]), 1, magic_obj_id)
				if dmg < 0:
					dmg = 0
				st["health"] = int(st["health"]) - dmg
		else:
			if target <= max_enemy_index and int(enemies[target].get("object_id", 0)) != 0:
				var e2: Dictionary = enemies[target]
				var st2: Dictionary = e2["e"]
				var def2 := float(int(st2["defense"]) + (int(st2["level"]) + 6) * 4)
				var dmg2 := _calc_magic_damage(float(base_damage), def2, _elem_res_of_enemy(st2),
					int(st2["poison_resistance"]), 1, magic_obj_id)
				if dmg2 < 0:
					dmg2 = 0
				st2["health"] = int(st2["health"]) - dmg2
	_draw_scene()


# ------------------------------------------------------------------ 供脚本调用的公开接口

## fight.c PAL_BattleStealFromEnemy：从????敌人偷钱或道具???## wStealItem==0 时偷钱（数量 = nStealItem / RandomLong(2,3)），否则偷道具并??nStealItem??## 成功率：RandomLong(0,10) <= wStealRate，或 wStealRate == 0 必定成功??
func steal_from_enemy(target: int, steal_rate: int) -> void:
	if target < 0 or target > max_enemy_index:
		return
	var e: Dictionary = enemies[target]
	if int(e.get("object_id", 0)) == 0:
		return
	var st: Dictionary = e["e"]
	if int(st.get("steal_item_count", 0)) <= 0:
		return
	if not (_rand(0, 10) <= steal_rate or steal_rate == 0):
		return
	if int(st.get("steal_item", 0)) == 0:
		var c := int(st["steal_item_count"]) / _rand(2, 3)
		st["steal_item_count"] = int(st["steal_item_count"]) - c
		if _state != null:
			_state.cash = int(_state.cash) + c
		if c > 0:
			print("[battle] 偷窃成功：%d 文钱" % c)
			_show_msg("偷到 %d 文钱" % c)
			await _wait(12)
	else:
		st["steal_item_count"] = int(st["steal_item_count"]) - 1
		var item := int(st["steal_item"])
		if _state != null and _state.has_method("add_item"):
			_state.add_item(item, 1)
		print("[battle] 偷窃成功：%s" % _word(item))
		_show_msg("偷到 %s" % _word(item))
		await _wait(12)




# ------------------------------------------------------------------ 伤害公式（fight.c）
## fight.c PAL_CalcBaseDamage
func _calc_base_damage(attack: float, defense: float) -> int:
	if attack > defense:
		return int(attack * 2.0 - defense * 1.6 + 0.5)
	elif attack > defense * 0.6:
		return int(attack - defense * 0.6 + 0.5)
	return 0


## fight.c PAL_CalcPhysicalAttackDamage
func _calc_physical_damage(attack: float, defense: float, resistance: int) -> int:
	var dmg := _calc_base_damage(attack, defense)
	if resistance != 0:
		dmg = int(float(dmg) / float(resistance))
	return dmg


## fight.c PAL_CalcMagicDamage（含随机系数、元素抗性、战场属性加成）
func _calc_magic_damage(magic_strength: float, defense: float, elem_res: Array[int],
		poison_res: int, resistance_multiplier: int, magic_obj_id: int) -> int:
	var mo := bd.magic_object(magic_obj_id)
	var mnum := int(mo.get("magic_number", 0))
	var md := bd.magic_def(mnum)
	if md.is_empty():
		return 0
	var ms := magic_strength * randf_range(10.0, 11.0) / 10.0
	var dmg := int(float(_calc_base_damage(ms, defense)) / 4.0)
	dmg += int(md.get("base_damage", 0))
	var elem := int(md.get("elemental", 0))
	if elem != 0:
		if elem > 5:
			dmg = int(float(dmg) * (10.0 - float(poison_res) / float(resistance_multiplier)))
		else:
			var er := 0
			if elem - 1 < elem_res.size():
				er = int(elem_res[elem - 1])
			dmg = int(float(dmg) * (10.0 - float(er) / float(resistance_multiplier)))
		dmg = int(float(dmg) / 5.0)
		if elem <= 5:
			var field_eff := 0
			if _bg_field >= 0 and _bg_field < bd.battle_fields.size():
				var me: Array = (bd.battle_fields[_bg_field] as Dictionary).get("magic_effect", [])
				if elem - 1 < me.size():
					field_eff = int(me[elem - 1])
			dmg = int(float(dmg) * (10.0 + float(field_eff)) / 10.0)
	return dmg


## fight.c PAL_GetEnemyDexterity（classic 部分）
func _enemy_dex_value(e: Dictionary) -> int:
	var st: Dictionary = e["e"]
	return (int(st["level"]) + 6) * 3 + int(st["dexterity"])


# ------------------------------------------------------------------ 动画

func _fade_in() -> void:
	await ui.fade_from_black()
	await _wait(4)


func _show_player_attack_anim(pi: int, target: int, critical: bool) -> void:
	var p: Dictionary = players[pi]
	var role := int(p["role"])
	_sound(_sound_of(p, "critical_sound") if critical else _sound_of(p, "attack_sound"))
	var e: Dictionary = enemies[target]
	var st: Dictionary = e["e"]
	var frames: Array = e.get("frames", [])
	var eh := 0
	var fr := int(e.get("frame", 0))
	if fr < frames.size():
		eh = (frames[fr] as Image).get_height()
	var ex := int(e["pos"].x)
	var ey := int(e["pos"].y)
	var x := ex + 64
	var y := ey + 20
	p["frame"] = 8
	p["pos"] = Vector2i(x, y)
	await _wait(3)
	x -= 10
	y -= 2
	p["pos"] = Vector2i(x, y)
	await _wait(2)
	p["frame"] = 9
	_sound(_sound_of(p, "weapon_sound"))
	# 打击特效：Data#10 战斗特效 sprite（sdlpal rgwBattleEffectIndex[sprite][1]*3??
	var effects := bd.effect_frames()
	var sprite := _battle_sprite(role)
	var idx := 0
	if sprite < bd.battle_effect_index.size():
		idx = int(bd.battle_effect_index[sprite][1])
	idx *= 3
	var fx := ex
	var fy := ey - eh / 3 + 10
	for k in range(3):
		_fx_overlay.clear()
		if idx + k < effects.size():
			var img: Image = effects[idx + k]
			_blit_effect(img, fx - img.get_width() / 2, fy - img.get_height())
		e["color_shift"] = 6
		_draw_scene()
		await get_tree().process_frame
		fx -= 16
		fy += 16
	e["color_shift"] = 0
	_fx_overlay.clear()
	if _test_mode:
		await _maybe_shot("02_attack")
	await _wait(2)


func _show_player_attack_all_anim(pi: int, critical: bool) -> void:
	var p: Dictionary = players[pi]
	_sound(_sound_of(p, "critical_sound") if critical else _sound_of(p, "attack_sound"))
	p["frame"] = 8
	await _wait(4)
	p["frame"] = 9
	for i in range(max_enemy_index + 1):
		if int(enemies[i].get("object_id", 0)) != 0:
			enemies[i]["color_shift"] = 6
	_draw_scene()
	await _wait(4)
	for i2 in range(max_enemy_index + 1):
		enemies[i2]["color_shift"] = 0
	p["frame"] = 0
	await _wait(2)


func _magic_cast_anim(pi: int, obj_id: int, target: int, summon: bool) -> void:
	var p: Dictionary = players[pi]
	var role := int(p["role"])
	for i in range(4):
		p["pos"] = Vector2i(int(p["pos"].x) - (4 - i), int(p["pos"].y) - (4 - i) / 2)
		await _wait(1)
	await _wait(2)
	p["frame"] = 5
	_sound(_sound_of(p, "magic_sound"))
	if not summon:
		# sdlpal ??Data#10 特效??index = battle_effect_index[sprite][0]*10+15，共 10 ??
		var sprite := _battle_sprite(role)
		var idx := 0
		if sprite < bd.battle_effect_index.size():
			idx = int(bd.battle_effect_index[sprite][0])
		idx *= 10
		idx += 15
		var effects := bd.effect_frames()
		var x := int(p["pos"].x)
		var y := int(p["pos"].y)
		for i2 in range(10):
			_fx_overlay.clear()
			if idx + i2 < effects.size():
				var img: Image = effects[idx + i2]
				_blit_effect(img, x - img.get_width() / 2, y - img.get_height())
			_draw_scene()
			await get_tree().process_frame
		_fx_overlay.clear()
		await _wait(1)
	p["frame"] = 6
	await _wait(2)


## 法术特效：Fire.mkf 第 wEffect 块 sprite，帧序同 fight.c PAL_BattleShowPlayerOffMagicAnim。
func _play_fire_effect(magic_num: int, target: int) -> void:
	var md := bd.magic_def(magic_num)
	if md.is_empty():
		return
	var effect_num := int(md.get("effect", 0))
	var frames := bd.fire_frames(effect_num)
	if frames.is_empty():
		await _wait(6)
		return
	var n := frames.size()
	var fire_delay := int(md.get("fire_delay", 0))
	var times := int(md.get("effect_times", 0))
	var shake := int(md.get("shake", 0))
	var speed := int(md.get("speed", 0))
	var x_off := int(md.get("x_offset", 0))
	var y_off := int(md.get("y_offset", 0))
	var total := (n - fire_delay) * times + n + shake
	var mtype := int(md.get("type", 0))
	_sound(int(md.get("sound", 0)))
	_ui_trace("fire_effect effect=%d frames=%d total=%d type=%d" % [effect_num, n, total, mtype])
	var frame_wait := maxi(1, (speed + 5) * 10 / FRAME_MS)
	var pos := Vector2i(160, 100)
	var positions: Array[Vector2i] = []
	match mtype:
		MAGIC_NORMAL:
			if target >= 0 and target <= max_enemy_index:
				pos = enemies[target]["pos"]
			positions.append(pos + Vector2i(x_off, y_off))
		MAGIC_ATTACK_ALL:
			for p in [Vector2i(70, 140), Vector2i(100, 110), Vector2i(160, 100)]:
				positions.append(p + Vector2i(x_off, y_off))
		MAGIC_ATTACK_WHOLE:
			positions.append(Vector2i(120, 100) + Vector2i(x_off, y_off))
		MAGIC_ATTACK_FIELD:
			positions.append(Vector2i(160, 200) + Vector2i(x_off, y_off))
		_:
			positions.append(Vector2i(160, 100) + Vector2i(x_off, y_off))
	for i in range(total):
		var k := 0
		if i < n:
			k = i
		else:
			k = (i - fire_delay) % maxi(1, n - fire_delay) + fire_delay
			k = clampi(k, 0, n - 1)
		_magic_fx = {"frames": frames, "index": k, "positions": positions}
		_draw_scene()
		if _test_mode and i == total / 2:
			await _maybe_shot("03_magic")
		await _wait(frame_wait)
	_magic_fx = {}
	_draw_scene()
	_ui_trace("fire_effect done")


func _player_escape_anim() -> void:
	for i in range(12):
		for p in players:
			p["pos"] = Vector2i(int(p["pos"].x) + 4, int(p["pos"].y) + 3)
		await _wait(1)
	await _wait(6)


func _blit_effect(img: Image, x: int, y: int) -> void:
	_fx_overlay.append({"img": img, "x": x, "y": y})


# ------------------------------------------------------------------ 场景合成/UI

func _player_frame_image(p: Dictionary) -> Image:
	var frames: Array = p.get("frames", [])
	if frames.is_empty():
		return null
	var fi := int(p.get("frame", 0))
	fi = clampi(fi, 0, frames.size() - 1)
	return frames[fi]


func _enemy_frame_image(e: Dictionary) -> Image:
	var frames: Array = e.get("frames", [])
	if frames.is_empty():
		return null
	var fi := int(e.get("frame", 0))
	fi = clampi(fi, 0, frames.size() - 1)
	return frames[fi]


## 场景合成：背景 + 敌人/玩家 + 当前法术帧，按 pos.y 排序（sdlpal PAL_BattleMakeScene）。
func _draw_scene() -> void:
	if ui == null:
		return
	var drawables: Array = []
	for i in range(max_enemy_index + 1):
		var e: Dictionary = enemies[i]
		if int(e.get("object_id", 0)) == 0:
			continue
		var img := _enemy_frame_image(e)
		if img == null:
			continue
		var pos: Vector2i = e["pos"]
		drawables.append({
			"img": img,
			"x": pos.x - img.get_width() / 2,
			"y": pos.y - img.get_height(),
			"sy": pos.y,
			"flash": int(e.get("color_shift", 0)) != 0,
		})
	var fx_entries: Array = []
	if not _magic_fx.is_empty():
		var frames: Array = _magic_fx.get("frames", [])
		var idx := int(_magic_fx.get("index", 0))
		if idx >= 0 and idx < frames.size():
			var mimg: Image = frames[idx]
			for pos2 in _magic_fx.get("positions", []):
				var mv: Vector2i = pos2
				fx_entries.append({
					"img": mimg,
					"x": mv.x - mimg.get_width() / 2,
					"y": mv.y - mimg.get_height(),
					"sy": mv.y,
					"flash": false,
				})
	for p in players:
		if int(p.get("hiding", 0)) != 0:
			continue
		var pimg := _player_frame_image(p)
		if pimg == null:
			continue
		var ppos: Vector2i = p["pos"]
		drawables.append({
			"img": pimg,
			"x": ppos.x - pimg.get_width() / 2,
			"y": ppos.y - pimg.get_height(),
			"sy": ppos.y,
			"flash": int(p.get("color_shift", 0)) != 0,
		})
	drawables.sort_custom(func(a, b): return int(a["sy"]) < int(b["sy"]))
	fx_entries.sort_custom(func(a, b): return int(a["sy"]) < int(b["sy"]))
	var all: Array = []
	all.append_array(drawables)
	all.append_array(fx_entries)
	# 打击/吟唱特效（Data#10 sprite）叠加在??上层
	for f in _fx_overlay:
		all.append(f)
	ui.render(all)


func _update_panels() -> void:
	if ui == null:
		return
	var rows: Array = []
	for p in players:
		var role := int(p["role"])
		var st: Array = []
		for s in range(STATUS_ALL):
			if _status(role, s) > 0 and STATUS_NAMES[s] != "":
				st.append(STATUS_NAMES[s])
		rows.append({
			"name": _player_name(p),
			"level": _level(role),
			"hp": _hp(role),
			"max_hp": _max_hp(role),
			"mp": _mp(role),
			"max_mp": _max_mp(role),
			"status": st,
		})
	ui.update_player_panels(rows)


func _draw_and_panels() -> void:
	_update_panels()
	_draw_scene()


func _encounter_size() -> int:
	return players.size()


# ------------------------------------------------------------------ 状态备份/显示

func _backup_stats() -> void:
	for p in players:
		var role := int(p["role"])
		p["prev_hp"] = _hp(role)
		p["prev_mp"] = _mp(role)
	for e in enemies:
		if int(e.get("object_id", 0)) != 0:
			e["prev_hp"] = int((e["e"] as Dictionary)["health"])


## 显示 HP/MP 变化（fight.c PAL_BattleDisplayStatChange）。返回是否显示了数字。
func _display_stat_change() -> bool:
	var shown := false
	for i in range(max_enemy_index + 1):
		var e: Dictionary = enemies[i]
		if int(e.get("object_id", 0)) == 0:
			continue
		var st: Dictionary = e["e"]
		if int(e["prev_hp"]) != int(st["health"]):
			var d := int(st["health"]) - int(e["prev_hp"])
			var pos: Vector2i = e["pos"]
			ui.show_number(absi(d), pos.x - 9, maxi(10, pos.y - 115),
				BattleUI.COLOR_DAMAGE if d > 0 else BattleUI.COLOR_MP)
			shown = true
	for p in players:
		var role := int(p["role"])
		var prev_hp := int(p.get("prev_hp", _hp(role)))
		var prev_mp := int(p.get("prev_mp", _mp(role)))
		if prev_hp != _hp(role):
			var d2 := _hp(role) - prev_hp
			var ppos: Vector2i = p["pos"]
			ui.show_number(absi(d2), ppos.x - 9, maxi(10, ppos.y - 75),
				BattleUI.COLOR_DAMAGE if d2 < 0 else BattleUI.COLOR_HEAL)
			shown = true
		if prev_mp != _mp(role) and _mp(role) > prev_mp:
			var ppos2: Vector2i = p["pos"]
			ui.show_number(_mp(role) - prev_mp, ppos2.x - 9, maxi(10, ppos2.y - 67), BattleUI.COLOR_MP)
			shown = true
	if shown:
		_update_panels()
		_draw_scene()
	if shown:
		await _wait(6)
	_backup_stats()
	return shown


# ------------------------------------------------------------------ 帧驱动 / 输入

func _wait(frames: int, update_gesture: bool = true) -> void:
	var n := frames
	if _test_mode:
		n = maxi(1, frames / 2)
	for i in range(n):
		if update_gesture:
			_update_enemy_gestures()
		_draw_scene()
		await get_tree().process_frame


func _update_enemy_gestures() -> void:
	for i in range(max_enemy_index + 1):
		var e: Dictionary = enemies[i]
		if int(e.get("object_id", 0)) == 0:
			continue
		if _status_enemy(e, ST_SLEEP) > 0 or _status_enemy(e, ST_PARALYZED) > 0:
			e["frame"] = 0
			continue
		var st: Dictionary = e["e"]
		var speed := int(st["idle_anim_speed"])
		if speed > 0:
			speed -= 1
			st["idle_anim_speed"] = speed
			if speed == 0:
				e["frame"] = int(e["frame"]) + 1
				# 复位：从原??定义重新取，避免????漂移
				var ed := bd.enemy_def(int(st["id"]))
				st["idle_anim_speed"] = int(ed.get("idle_anim_speed", 1))
		var idle_frames := int(st["idle_frames"])
		if idle_frames > 0 and int(e["frame"]) >= idle_frames:
			e["frame"] = 0


func _unhandled_input(event: InputEvent) -> void:
	if not _waiting_key:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: int = (event as InputEventKey).keycode
	var mapped := 0
	match k:
		KEY_UP, KEY_W:
			mapped = K_UP
		KEY_DOWN, KEY_S:
			mapped = K_DOWN
		KEY_LEFT, KEY_A:
			mapped = K_LEFT
		KEY_RIGHT, KEY_D:
			mapped = K_RIGHT
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			mapped = K_OK
		KEY_ESCAPE, KEY_BACKSPACE:
			mapped = K_CANCEL
	if mapped == 0:
		return
	_pending_key = mapped
	_waiting_key = false
	get_viewport().set_input_as_handled()


func _get_key() -> int:
	if _ui_test:
		# UI ????化：先把当前菜单画面存档，再注入预??按键
		await _maybe_shot("menu_%02d" % _script_pos)
		await _wait(3)
		if _script_pos < _script_keys.size():
			var k := _script_keys[_script_pos]
			_script_pos += 1
			print("[battle-test] 模拟按键 #%d = %d" % [_script_pos, k])
			return k
		# 序列耗尽后交替???取?????”，保证能从任意子菜单???回主菜单并继??????
		var n := _script_pos - _script_keys.size()
		_script_pos += 1
		await _wait(3)
		return K_CANCEL if n % 2 == 0 else K_OK
	_pending_key = 0
	_waiting_key = true
	while _waiting_key:
		await get_tree().process_frame
	_waiting_key = false
	return _pending_key


# ------------------------------------------------------------------ 测试模式

func _test_grant_magic() -> void:
	# [测试专用] 新游戏默认只有李逍遥（Lv1 ????气疗????，为覆盖“法????验收路径，
	# 若队伍中没有任何????的攻击仙????则从 Data#6 升级仙术表里补授??????便宜的???
	if not _test_mode or _test_kind == "flee":
		return
	for p in players:
		var role := int(p["role"])
		var has_offensive := false
		for id in _magic_list(role):
			var mi0 := bd.magic_object(id)
			if (int(mi0.get("flags", 0)) & MAGIC_USABLE_TO_ENEMY) != 0:
				has_offensive = true
				break
		if has_offensive:
			continue
		var candidates: Array[int] = []
		for rec in bd.level_up_magic:
			if role >= rec.size():
				continue
			var mag := int((rec[role] as Dictionary).get("magic", 0))
			if mag != 0 and not candidates.has(mag):
				candidates.append(mag)
		candidates.sort_custom(func(a, b): return _magic_cost(a) < _magic_cost(b))
		for obj_id in candidates:
			var mi := bd.magic_object(obj_id)
			if mi.is_empty():
				continue
			var flags := int(mi.get("flags", 0))
			if (flags & MAGIC_USABLE_TO_ENEMY) == 0 or (flags & MAGIC_USABLE_IN_BATTLE) == 0:
				continue
			var md := bd.magic_def(int(mi.get("magic_number", 0)))
			if md.is_empty() or int(md.get("base_damage", 0)) <= 0:
				continue
			var cost := int(md.get("cost_mp", 0))
			if cost < 2 or cost > _mp(role):
				continue
			if _state != null and _state.has_method("add_magic"):
				_state.add_magic(role, obj_id)
				print("[battle-test] 为角色%d补授攻击仙术 object=%d(%s) cost=%d base=%d（仅测试用）" % [
					role, obj_id, _word(obj_id), cost, int(md.get("base_damage", 0))])
			break
	# [测试专用] 补 3 个消耗型可用物品（验证“物品”指令 + 物品脚本经战斗代理执行）
	if _state != null and _state.has_method("add_item") and _item_list(ITEM_USABLE).is_empty():
		for obj_id in range(1, bd.objects.size()):
			var io := bd.item_object(obj_id)
			if io.is_empty():
				continue
			var flags := int(io.get("flags", 0))
			if (flags & ITEM_USABLE) == 0 or (flags & ITEM_CONSUMING) == 0:
				continue
			if int(io.get("script_on_use", 0)) == 0:
				continue
			if int(io.get("price", 0)) > 100:
				continue
			_state.add_item(obj_id, 3)
			print("[battle-test] 为队伍补 3 个物品 object=%d(%s) flags=0x%x（仅测试用）" % [
				obj_id, _word(obj_id), flags])
			break


## [测试专用] 把主经验推到“再打一场必升级”的位置，用于验收 PAL_BattleWon 的升级分支。
func _test_seed_exp() -> void:
	if _state == null or _test_kind == "flee":
		return
	var t: Dictionary = _exp_table()
	var arr = t.get("primary")
	if not (arr is Array):
		return
	for p in players:
		var role := int(p["role"])
		if role >= arr.size():
			continue
		var lv := _level(role)
		var need := _exp_to_next(lv)
		if need > 1:
			(arr[role] as Dictionary)["exp"] = need - 1
			print("[battle-test] 角色%d 主经验预置为 %d/%d（胜利后应升级，仅测试用）" % [role, need - 1, need])


func _test_choose_action(pi: int) -> Dictionary:
	var p: Dictionary = players[pi]
	var role := int(p["role"])
	if _test_kind == "flee":
		return {"type": ACT_FLEE, "id": 0, "target": -1}
	# demo/win：?? 2 回合尝试??次法????其余????（足以????攻击/法术/敌方行动/胜利结算??
	if turn_no == 2 and pi == 0:
		var list := _magic_list(role)
		for id in list:
			var mi := bd.magic_object(id)
			if (int(mi.get("flags", 0)) & MAGIC_USABLE_TO_ENEMY) == 0:
				continue
			var md := bd.magic_def(int(mi.get("magic_number", 0)))
			if int(md.get("cost_mp", 0)) > _mp(role):
				continue
			var apply_all := (int(mi.get("flags", 0)) & MAGIC_FLAG_APPLY_TO_ALL) != 0
			return {"type": ACT_MAGIC, "id": int(id), "target": -1 if apply_all else _select_auto_enemy()}
	if turn_no == 3 and pi == 0:
		var usable := _item_list(ITEM_USABLE)
		if not usable.is_empty():
			return {"type": ACT_USE_ITEM, "id": int(usable[0]), "target": 0}
		if players.size() > 1:
			return {"type": ACT_DEFEND, "id": 0, "target": -1}
	if _player_can_attack_all(role):
		return {"type": ACT_ATTACK, "id": 0, "target": -1}
	return {"type": ACT_ATTACK, "id": 0, "target": _select_auto_enemy()}


func _maybe_shot(tag: String) -> void:
	if not _test_mode or _shot_done.has(tag):
		return
	_shot_done[tag] = true
	await ui.screenshot(tag)


func _has_cmd_prefix(prefix: String) -> bool:
	for a in OS.get_cmdline_args():
		if a == prefix or a.begins_with(prefix + "="):
			return true
	return false


func _cmd_value(prefix: String) -> String:
	for a in OS.get_cmdline_args():
		if a.begins_with(prefix + "="):
			return a.substr(prefix.length() + 1)
	return ""


# ------------------------------------------------------------------ 数据访问辅助

func _word(id: int) -> String:
	if _tables != null and _tables.has_method("word"):
		return str(_tables.word(id))
	return str(id)


func _player_name(p: Dictionary) -> String:
	return _word(int(p.get("name_word", 0)))


func _player_name_enemy(e: Dictionary) -> String:
	return _word(int(e.get("object_id", 0)))


func _sound_of(p: Dictionary, key: String) -> int:
	return int(p.get(key, 0))


func _action_name(act: Dictionary) -> String:
	match int(act.get("type", -1)):
		ACT_ATTACK:
			return "攻击"
		ACT_DEFEND:
			return "防御"
		ACT_MAGIC:
			return "仙术(%s)" % _word(int(act.get("id", 0)))
		ACT_COOP:
			return "合击"
		ACT_FLEE:
			return "逃跑"
		ACT_USE_ITEM:
			return "使用物品(%s)" % _word(int(act.get("id", 0)))
		ACT_THROW_ITEM:
			return "投掷物品(%s)" % _word(int(act.get("id", 0)))
		ACT_ATTACK_MATE:
			return "攻击队友"
	return "无"


func _select_auto_enemy() -> int:
	for i in range(max_enemy_index + 1):
		var e: Dictionary = enemies[i]
		if int(e.get("object_id", 0)) != 0 and int((e["e"] as Dictionary)["health"]) > 0:
			return i
	return -1


func _enemy_target_rect(i: int) -> Dictionary:
	var e: Dictionary = enemies[i]
	var img := _enemy_frame_image(e)
	var w := 40
	var h := 40
	if img != null:
		w = img.get_width()
		h = img.get_height()
	var pos: Vector2i = e["pos"]
	return {"x": pos.x - w / 2, "y": pos.y - h, "w": w, "h": h}


func _player_target_rect(i: int) -> Dictionary:
	var p: Dictionary = players[i]
	var img := _player_frame_image(p)
	var w := 40
	var h := 40
	if img != null:
		w = img.get_width()
		h = img.get_height()
	var pos: Vector2i = p["pos"]
	return {"x": pos.x - w / 2, "y": pos.y - h, "w": w, "h": h}


func _magic_cost(obj_id: int) -> int:
	var mi := bd.magic_object(obj_id)
	if mi.is_empty():
		return 999
	return int(bd.magic_def(int(mi.get("magic_number", 0))).get("cost_mp", 999))


func _magic_list(role: int) -> Array[int]:
	var out: Array[int] = []
	if _state != null and _state.has_method("player_magics"):
		for id in _state.player_magics(role):
			var mi := bd.magic_object(int(id))
			if mi.is_empty():
				continue
			if (int(mi.get("flags", 0)) & MAGIC_USABLE_IN_BATTLE) == 0:
				continue
			out.append(int(id))
		return out
	for id2 in bd.role_magics(role):
		out.append(int(id2))
	return out


func _item_list(required_flag: int) -> Array[int]:
	var out: Array[int] = []
	if _state == null:
		return out
	var inv = _state.inventory
	for it in inv:
		if not (it is Dictionary):
			continue
		var id := int(it.get("item", 0))
		if id == 0:
			continue
		if int(it.get("amount", 0)) - int(it.get("in_use", 0)) <= 0:
			continue
		var io := bd.item_object(id)
		if io.is_empty():
			continue
		if (int(io.get("flags", 0)) & required_flag) == 0:
			continue
		if not out.has(id):
			out.append(id)
	return out


func _item_available(id: int) -> int:
	if _state == null:
		return 0
	var amount := int(_state.get_item_amount(id))
	var in_use := int(_in_use.get(id, 0))
	return maxi(0, amount - in_use)


func _consume_item(id: int) -> void:
	if _state != null and _state.has_method("add_item"):
		_state.add_item(id, -1)


# ---- PALState 访问（缺方法/字段时本地兜底）

func _hp(role: int) -> int:
	if _state != null and _state.has_method("hp"):
		return int(_state.hp(role))
	return 0


func _max_hp(role: int) -> int:
	if _state != null and _state.has_method("max_hp"):
		return int(_state.max_hp(role))
	return 0


func _mp(role: int) -> int:
	if _state != null and _state.has_method("mp"):
		return int(_state.mp(role))
	return 0


func _max_mp(role: int) -> int:
	if _state != null and _state.has_method("max_mp"):
		return int(_state.max_mp(role))
	return 0


func _set_hp(role: int, v: int) -> void:
	if _state != null and _state.roles is Dictionary:
		_state.roles["hp"][role] = clampi(v, 0, _max_hp(role))


func _set_mp(role: int, v: int) -> void:
	if _state != null and _state.roles is Dictionary:
		_state.roles["mp"][role] = clampi(v, 0, _max_mp(role))


func _level(role: int) -> int:
	if _state != null and _state.has_method("level"):
		return int(_state.level(role))
	return 0


func _set_level(role: int, v: int) -> void:
	if _state != null and _state.roles is Dictionary:
		_state.roles["level"][role] = v


func _attack_strength(role: int) -> int:
	return int(_state.get_player_attack_strength(role)) if _state != null and _state.has_method("get_player_attack_strength") else 0


func _magic_strength(role: int) -> int:
	return int(_state.get_player_magic_strength(role)) if _state != null and _state.has_method("get_player_magic_strength") else 0


func _defense(role: int) -> int:
	return int(_state.get_player_defense(role)) if _state != null and _state.has_method("get_player_defense") else 0


func _dexterity(role: int) -> int:
	return int(_state.get_player_dexterity(role)) if _state != null and _state.has_method("get_player_dexterity") else 0


func _flee_rate(role: int) -> int:
	return int(_state.get_player_flee_rate(role)) if _state != null and _state.has_method("get_player_flee_rate") else 0


func _poison_resistance(role: int) -> int:
	return int(_state.get_player_poison_resistance(role)) if _state != null and _state.has_method("get_player_poison_resistance") else 0


func _elem_resistance(role: int, elem: int) -> int:
	return int(_state.get_player_elemental_resistance(role, elem)) if _state != null and _state.has_method("get_player_elemental_resistance") else 0


func _player_can_attack_all(role: int) -> bool:
	return bool(_state.player_can_attack_all(role)) if _state != null and _state.has_method("player_can_attack_all") else false


func _coop_magic(role: int) -> int:
	return int(_state.get_player_cooperative_magic(role)) if _state != null and _state.has_method("get_player_cooperative_magic") else 0


func _battle_sprite(role: int) -> int:
	return int(_state.get_player_battle_sprite(role)) if _state != null and _state.has_method("get_player_battle_sprite") else 0


func _covered_by(role: int) -> int:
	if _state != null and _state.roles is Dictionary:
		var cb = _state.roles.get("covered_by")
		if cb is Array and role < cb.size():
			return int(cb[role])
	return 0


func _is_player_dying(role: int) -> bool:
	return _hp(role) < mini(100, _max_hp(role) / 5)


func _is_player_healthy(role: int) -> bool:
	return (not _is_player_dying(role) and _status(role, ST_SLEEP) == 0 and
		_status(role, ST_CONFUSED) == 0 and _status(role, ST_SILENCE) == 0 and
		_status(role, ST_PARALYZED) == 0 and _status(role, ST_PUPPET) == 0)


func _status(role: int, id: int) -> int:
	if _state != null and _state.status is Array and role < _state.status.size():
		var row = _state.status[role]
		if row is Array and id < row.size():
			return int(row[id])
	return 0


func _set_status(role: int, id: int, v: int) -> void:
	if _state != null and _state.status is Array and role < _state.status.size():
		var row = _state.status[role]
		if row is Array and id < row.size():
			row[id] = v


func _status_enemy(e: Dictionary, id: int) -> int:
	var arr: Array = e.get("status", [])
	if id < arr.size():
		return int(arr[id])
	return 0


func _elem_res_of_enemy(st: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var arr = st.get("elem_resistance", [])
	for i in range(5):
		out.append(int(arr[i]) if i < arr.size() else 0)
	return out


func _sound(sid: int) -> void:
	if sid < 0:
		return
	var audio := get_node_or_null("/root/PALAudio")
	if audio != null and audio.has_method("play_sound"):
		audio.play_sound(sid)


# ---- 经验/计数辅助（PALState.exp：{primary,health,...}[role] = {exp,level}）
func _exp_table() -> Dictionary:
	if _state != null and _state.exp is Dictionary:
		return _state.exp
	return {}


func _primary_exp(role: int) -> int:
	var t := _exp_table()
	var arr = t.get("primary")
	if arr is Array and role < arr.size():
		return int((arr[role] as Dictionary).get("exp", 0))
	return 0


func _set_primary_exp(role: int, v: int) -> void:
	var t := _exp_table()
	var arr = t.get("primary")
	if arr is Array and role < arr.size():
		(arr[role] as Dictionary)["exp"] = v


func _exp_value(role: int, key: String) -> int:
	var t := _exp_table()
	var arr = t.get(key)
	if arr is Array and role < arr.size():
		return int((arr[role] as Dictionary).get("exp", 0))
	return 0


func _exp_level(role: int, key: String) -> int:
	var t := _exp_table()
	var arr = t.get(key)
	if arr is Array and role < arr.size():
		return int((arr[role] as Dictionary).get("level", 0))
	return 0


func _exp_set(role: int, key: String, exp_v: int, level_v: int) -> void:
	var t := _exp_table()
	var arr = t.get(key)
	if arr is Array and role < arr.size():
		(arr[role] as Dictionary)["exp"] = exp_v
		(arr[role] as Dictionary)["level"] = level_v


func _exp_to_next(level: int) -> int:
	var lv := clampi(level, 0, 99)
	if lv < bd.level_up_exp.size():
		return int(bd.level_up_exp[lv])
	return 0


func _exp_count(role: int, key: String, n: int) -> void:
	if not _exp_counts.has(role):
		_exp_counts[role] = {}
	var d: Dictionary = _exp_counts[role]
	d[key] = int(d.get(key, 0)) + n


func _exp_count_of(role: int, key: String) -> int:
	if not _exp_counts.has(role):
		return 0
	return int((_exp_counts[role] as Dictionary).get(key, 0))


func _add_role_stat(role: int, stat_key: String, n: int) -> void:
	if _state != null and _state.roles is Dictionary:
		var arr = _state.roles.get(stat_key)
		if arr is Array and role < arr.size():
			arr[role] = int(arr[role]) + n


func _show_msg(text: String) -> void:
	ui.set_message(text)


## 同??执????段战斗脚????SSS SCRIPTENTRY）???## 优先用自??ScriptVM（注入战斗代理，因??敌人/物品/法术脚本里的战斗 opcode 生效）；
## 无 PalData 时退回 World.run_script_entry。遇到对话/等待类状态即中断（[inf]：原版会阻塞等待）。
func _run_script(entry: int, evt_id: int) -> bool:
	if entry == 0:
		return false
	var vm = _ensure_script_vm()
	if vm == null:
		if world != null and world.has_method("run_script_entry"):
			world.run_script_entry(entry)
			return true
		return false
	vm.start(entry, evt_id)
	var guard := 0
	while vm.is_active() and guard < 4000:
		if vm.waiting_dialog:
			# 同步路径（物品/法术效果脚本）：对白只闪示，不阻塞战斗
			var dt := _vm_dialog_text()
			if dt != "":
				_show_msg(dt)
			vm.advance_dialog()
			continue
		if vm.waiting_battle or vm.waiting_menu or vm.waiting_rng or vm.waiting_choice or vm.waiting_key:
			break
		if vm.wait_frames > 0:
			vm.wait_frames = 0
		vm.tick()
		guard += 1
	var ok: bool = true
	if "script_success" in vm:
		ok = bool(vm.script_success)
	return ok


## 异步执行战斗脚本：对白用战斗 UI 显示并短暂停留后自动推进，等待帧按真实帧数等待，
## 这样战前/战后/回合脚本里的 0xFFFF 对白、0x0009 等待、0x0069 敌人逃跑等能完整执行。
func _run_script_async(entry: int, evt_id: int) -> bool:
	if entry == 0:
		return false
	var vm = _ensure_script_vm()
	if vm == null:
		return _run_script(entry, evt_id)
	vm.start(entry, evt_id)
	var guard := 0
	while vm.is_active() and guard < 6000:
		if vm.waiting_dialog:
			var dt := _vm_dialog_text()
			if dt != "":
				print("[battle] 脚本对白: ", dt)
				ui.set_message(dt)
				await _wait(16)
			vm.advance_dialog()
			continue
		if vm.wait_frames > 0:
			var n := int(vm.wait_frames)
			vm.wait_frames = 0
			await _wait(maxi(1, n))
			continue
		if vm.waiting_battle or vm.waiting_menu or vm.waiting_rng or vm.waiting_choice or vm.waiting_key:
			break
		vm.tick()
		guard += 1
	var ok: bool = true
	if "script_success" in vm:
		ok = bool(vm.script_success)
	return ok


## 读取当前暂停在 0xFFFF 对白上的脚本消息（VM 的 ip 仍指向该指令）。
func _vm_dialog_text() -> String:
	if _script_vm == null:
		return ""
	var d = _script_vm.data
	if d == null:
		return ""
	var e = d.script_entry(int(_script_vm.ip))
	if e.size() >= 2 and int(e[0]) == 0xFFFF:
		return str(d.msg(int(e[1])))
	return ""


func _ensure_script_vm():
	if _script_vm != null:
		return _script_vm
	var data = null
	if _state != null:
		data = _state.data
	if data == null and _tables != null:
		data = _tables.sss
	if data == null:
		return null
	if _script_vm_script == null:
		_script_vm_script = load("res://pal/script_vm.gd")
	if _script_vm_script == null:
		return null
	_script_vm = _script_vm_script.new()
	if _script_vm == null:
		return null
	# world 传 null：战斗内脚本的对白由 Battle 自己显示/推进（世界对话框在战斗画面之下）
	_script_vm.setup(data, null)
	if _script_vm.has_method("set_battle_proxy"):
		_script_vm.set_battle_proxy(self)
	return _script_vm


func _rand(a: int, b: int) -> int:
	if b < a:
		return a
	return randi_range(a, b)


func _can_use_magic(role: int) -> bool:
	return _status(role, ST_SILENCE) == 0 and _magic_list(role).size() > 0


func _can_coop(role: int) -> bool:
	if players.size() < 2 or _coop_magic(role) <= 0:
		return false
	var healthy := 0
	for p in players:
		if _is_player_healthy(int(p["role"])):
			healthy += 1
	return _is_player_healthy(role) and healthy > 1
