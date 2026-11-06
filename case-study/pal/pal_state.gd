extends Node
## 可变全局状态（autoload `PALState`）。
## 移植 sdlpal global.h: GLOBALVARS + global.c 的整组工具函数
## （PAL_LoadDefaultGame / PAL_InitGameData / 背包 / 装备 / 状态 / 毒 / 仙术 / 升级 / 存读档）。
## 说明：角色数值数组用 Array（引用可变），equipment_effect 对应 rgEquipmentEffect[7]。

signal stats_changed

const MAX_PLAYER_ROLES := 6
const MAX_PLAYABLE_PLAYER_ROLES := 5
const MAX_PLAYERS_IN_PARTY := 3
const MAX_INVENTORY := 256
const MAX_POISONS := 16
const MAX_PLAYER_EQUIPMENTS := 6
const MAX_PLAYER_MAGICS := 32
const MAX_LEVELS := 99
const MAX_SCENES := 300
const MAX_OBJECTS := 600
const MAX_EVENT_OBJECTS := 5500
const STATUS_ALL := 9

# 状态枚举（sdlpal tagSTATUS；kStatusParalyzed 与 kStatusSleep 合并）
const STATUS_CONFUSED := 0
const STATUS_SLOW := 1
const STATUS_SLEEP := 2
const STATUS_SILENCE := 3
const STATUS_PUPPET := 4
const STATUS_BRAVERY := 5
const STATUS_PROTECT := 6
const STATUS_HASTE := 7
const STATUS_DUAL_ATTACK := 8

# 装备部位
const BODY_HEAD := 0
const BODY_BODY := 1
const BODY_SHOULDER := 2
const BODY_HAND := 3
const BODY_FEET := 4
const BODY_WEAR := 5

var data: PalData = null
var tables: Node = null          # PALTables

# ---------------- 场景/画面
var scene: int = 1
var palette: int = 0
var night_palette: bool = false
var music: int = 0
var battle_music: int = 0
var battle_field: int = 0
var collect_value: int = 0
var screen_wave: int = 0
var wave_progression: int = 0
var chase_range: int = 1
var chase_speed_cycles: int = 0
var follower_count: int = 0
var cash: int = 0
var layer: int = 0
var viewport: Vector2i = Vector2i.ZERO
var party_offset: Vector2i = Vector2i(160, 112)
var party_dir: int = 0
var max_party_member_index: int = 0
var battle_speed: int = 2
var saved_times: int = 0
var current_save_slot: int = 0
var current_rng: int = 0   # 最近播放的 RNG 号（对应 sdlpal iCurPlayingRNG）
var loaded_from_save: bool = false   # 读档后本帧不跑 onEnter（sdlpal global.c:634）
var entering_scene: bool = true
var need_fade_in: bool = true
var in_battle: bool = false

# ---------------- 队伍/角色/背包
var party: Array = []            # [{role,x,y,frame,image_offset}]
var trail: Array = []            # [{x,y,dir}]
var roles: Dictionary = {}       # = PLAYERROLES
var equipment_effect: Array = [] # [7] 份 PLAYERROLES 效果
var status: Array = []           # [6][9]
var poison_status: Array = []    # [MAX_POISONS][6] [{poison_id, script}]
var inventory: Array = []        # [{item, amount, in_use}]
var exp: Dictionary = {}         # ALLEXPERIENCE
var vars: Dictionary = {}        # 移植补充变量（脚本/剧情）
var script_runner: Callable = Callable()   # 由 World 注入：run_script(entry, evt_id)


func _ready() -> void:
	tables = PALTables


# ------------------------------------------------------------------ 初始化

func reset_defaults() -> void:
	# 对齐 global.c: PAL_LoadDefaultGame
	scene = 1
	music = 0
	palette = 0
	collect_value = 0
	night_palette = false
	max_party_member_index = 0
	viewport = Vector2i.ZERO
	layer = 0
	follower_count = 0
	chase_range = 1
	battle_speed = 2
	battle_field = 0
	cash = 0
	party_dir = 0
	party_offset = Vector2i(160, 112)
	entering_scene = true
	need_fade_in = true
	in_battle = false
	vars = {}
	roles = _deep_copy_roles(tables.player_roles)
	equipment_effect = []
	for i in range(MAX_PLAYER_EQUIPMENTS + 1):
		equipment_effect.append(_zero_roles())
	status = []
	for r in range(MAX_PLAYER_ROLES):
		var row: Array = []
		for s in range(STATUS_ALL):
			row.append(0)
		status.append(row)
	poison_status = []
	for i in range(MAX_POISONS):
		var row2: Array = []
		for r in range(MAX_PLAYER_ROLES):
			row2.append({"poison_id": 0, "script": 0})
		poison_status.append(row2)
	inventory = []
	for i in range(MAX_INVENTORY):
		inventory.append({"item": 0, "amount": 0, "in_use": 0})
	exp = _zero_exp()
	for r in range(MAX_PLAYER_ROLES):
		var lv := int(roles["level"][r])
		for k in exp.keys():
			exp[k][r]["level"] = lv
	party = []
	trail = []
	for i in range(MAX_PLAYABLE_PLAYER_ROLES):
		party.append({"role": 0, "x": 0, "y": 0, "frame": 0, "image_offset": 0})
		trail.append({"x": 0, "y": 0, "dir": 0})
	stats_changed.emit()


func init_game_data(slot: int) -> void:
	current_save_slot = slot
	reset_defaults()
	if slot > 0:
		if not load_game(slot):
			push_warning("PALState: 读档 %d 失败，使用新游戏默认值" % slot)
			reset_defaults()
	update_equipments()


func _deep_copy_roles(src: Dictionary) -> Dictionary:
	var out := {}
	for key in src.keys():
		out[key] = (src[key] as Array).duplicate()
	return out


func _zero_roles() -> Dictionary:
	var out := {}
	for key in tables.player_roles.keys():
		var src: Array = tables.player_roles[key]
		var arr: Array = []
		for i in range(src.size()):
			arr.append(0)
		out[key] = arr
	return out


func _zero_exp() -> Dictionary:
	var keys := ["primary", "health", "magic", "attack", "magic_power", "defense", "dexterity", "flee"]
	var out := {}
	for k in keys:
		var arr: Array = []
		for r in range(MAX_PLAYER_ROLES):
			arr.append({"exp": 0, "level": 0})
		out[k] = arr
	return out


# ------------------------------------------------------------------ 背包

func count_item(item_id: int) -> int:
	if item_id == 0:
		return 0
	var count := 0
	for i in range(MAX_INVENTORY):
		var it: Dictionary = inventory[i]
		if int(it["item"]) == item_id:
			count = int(it["amount"])
			break
		elif int(it["item"]) == 0:
			break
	for i in range(max_party_member_index + 1):
		var w := int(party[i]["role"])
		for j in range(MAX_PLAYER_EQUIPMENTS):
			if int(roles["equipment"][j * 6 + w]) == item_id:
				count += 1
	return count


## 返回背包下标；-1 表示不存在。
func get_item_index(item_id: int) -> int:
	for i in range(MAX_INVENTORY):
		var it: Dictionary = inventory[i]
		if int(it["item"]) == item_id:
			return i
		elif int(it["item"]) == 0:
			return -1
	return -1


func get_item_amount(item_id: int) -> int:
	var idx := get_item_index(item_id)
	if idx < 0:
		return 0
	return int(inventory[idx]["amount"])


## 增/减物品；正数增加、负数减少。返回 1 成功 / 0 失败 / 负数表示用光了。
func add_item(item_id: int, num: int) -> int:
	if item_id == 0:
		return 0
	if num == 0:
		num = 1
	var idx := get_item_index(item_id)
	if num > 0:
		if idx < 0:
			# 找空位
			idx = -1
			for i in range(MAX_INVENTORY):
				if int(inventory[i]["item"]) == 0:
					idx = i
					break
			if idx < 0:
				return 0
			inventory[idx]["item"] = item_id
			inventory[idx]["amount"] = num
			inventory[idx]["in_use"] = 0
		else:
			inventory[idx]["amount"] = int(inventory[idx]["amount"]) + num
		return 1
	# 减少
	if idx < 0:
		return 0
	var amount := int(inventory[idx]["amount"])
	amount += num
	if amount <= 0:
		inventory[idx]["item"] = 0
		inventory[idx]["amount"] = 0
		inventory[idx]["in_use"] = 0
		compress_inventory()
		return -1
	inventory[idx]["amount"] = amount
	return 1


func compress_inventory() -> void:
	var write := 0
	for read in range(MAX_INVENTORY):
		if int(inventory[read]["item"]) != 0:
			if read != write:
				inventory[write] = inventory[read]
				inventory[read] = {"item": 0, "amount": 0, "in_use": 0}
			write += 1


func inventory_items() -> Array[int]:
	var out: Array[int] = []
	for i in range(MAX_INVENTORY):
		var id := int(inventory[i]["item"])
		if id == 0:
			break
		out.append(id)
	return out


# ------------------------------------------------------------------ 装备/属性

func update_equipments() -> void:
	# 对齐 global.c: PAL_UpdateEquipments —— 先清空效果，再逐个装备执行 wScriptOnEquip 脚本
	for part in range(MAX_PLAYER_EQUIPMENTS):
		for r in range(MAX_PLAYER_ROLES):
			_remove_effect_entry(part, r)
	for i in range(max_party_member_index + 1):
		var role := int(party[i]["role"])
		for part in range(MAX_PLAYER_EQUIPMENTS):
			var item := int(roles["equipment"][part * 6 + role])
			if item != 0:
				var obj: Dictionary = tables.item_of(item)
				var entry := int(obj["script_on_equip"])
				if entry != 0 and script_runner.is_valid():
					# sdlpal global.c PAL_UpdateEquipments：装备脚本以“角色号”作为 wEventObjectID
					script_runner.call(entry, role)
	stats_changed.emit()


func remove_equipment_effect(role: int, part: int) -> void:
	_remove_effect_entry(part, role)
	# sdlpal: 手部重置双击状态，佩戴部位清 99 级毒
	if part == BODY_HAND:
		status[role][STATUS_DUAL_ATTACK] = 0
	stats_changed.emit()


func _remove_effect_entry(part: int, role: int) -> void:
	if part < 0 or part >= equipment_effect.size():
		return
	var eff: Dictionary = equipment_effect[part]
	for key in eff.keys():
		var arr: Array = eff[key]
		if arr.size() % MAX_PLAYER_ROLES == 0:
			var g := 0
			while g * MAX_PLAYER_ROLES < arr.size():
				arr[g * MAX_PLAYER_ROLES + role] = 0
				g += 1


## 供脚本 0x0017 写设备效果（part, role, field, value）
func set_equipment_effect(part: int, role: int, field: String, value: int) -> void:
	if part < 0 or part >= equipment_effect.size():
		return
	var eff: Dictionary = equipment_effect[part]
	if eff.has(field):
		var arr: Array = eff[field]
		if role < arr.size():
			arr[role] = value


func _equip_sum(field: String, role: int) -> int:
	var total := int(roles[field][role])
	for i in range(MAX_PLAYER_EQUIPMENTS + 1):
		var ef: Dictionary = equipment_effect[i]
		if ef.has(field):
			total += int(ef[field][role])
	return total


func get_player_attack_strength(role: int) -> int:
	return _equip_sum("attack_strength", role)


func get_player_magic_strength(role: int) -> int:
	return _equip_sum("magic_strength", role)


func get_player_defense(role: int) -> int:
	return _equip_sum("defense", role)


func get_player_dexterity(role: int) -> int:
	return _equip_sum("dexterity", role)


func get_player_flee_rate(role: int) -> int:
	return _equip_sum("flee_rate", role)


func get_player_poison_resistance(role: int) -> int:
	return mini(100, _equip_sum("poison_resistance", role))


func get_player_elemental_resistance(role: int, attrib: int) -> int:
	var flat: int = attrib * MAX_PLAYER_ROLES + role
	var total := int(roles["elemental_resistance"][flat])
	for i in range(MAX_PLAYER_EQUIPMENTS + 1):
		var ef: Dictionary = equipment_effect[i]
		total += int(ef["elemental_resistance"][flat])
	return mini(100, total)


func get_player_battle_sprite(role: int) -> int:
	var w := int(roles["sprite_in_battle"][role])
	for i in range(MAX_PLAYER_EQUIPMENTS + 1):
		var v := int(equipment_effect[i]["sprite_in_battle"][role])
		if v != 0:
			w = v
	return w


func get_player_cooperative_magic(role: int) -> int:
	return int(roles["cooperative_magic"][role])


func player_can_attack_all(role: int) -> bool:
	return int(roles["attack_all"][role]) != 0


func hp(role: int) -> int:
	return int(roles["hp"][role])


func max_hp(role: int) -> int:
	return int(roles["max_hp"][role])


func mp(role: int) -> int:
	return int(roles["mp"][role])


func max_mp(role: int) -> int:
	return int(roles["max_mp"][role])


func level(role: int) -> int:
	return int(roles["level"][role])


func increase_hpmp(role: int, dhp: int, dmp: int) -> bool:
	var orig := int(roles["hp"][role]) != 0
	var h := int(roles["hp"][role])
	var m := int(roles["mp"][role])
	if h > 0:
		h += dhp
		h = clampi(h, 0, int(roles["max_hp"][role]))
		m += dmp
		m = clampi(m, 0, int(roles["max_mp"][role]))
	roles["hp"][role] = h
	roles["mp"][role] = m
	stats_changed.emit()
	return orig


# ------------------------------------------------------------------ 毒

func add_poison(role: int, poison_id: int) -> void:
	if poison_id <= 0:
		return
	for i in range(MAX_POISONS):
		var row: Array = poison_status[i]
		if int(row[role]["poison_id"]) == 0:
			var obj: Dictionary = tables.poison_obj_of(poison_id)
			row[role] = {"poison_id": poison_id, "script": int(obj["player_script"])}
			return


func cure_poison_by_kind(role: int, poison_id: int) -> void:
	for i in range(MAX_POISONS):
		var row: Array = poison_status[i]
		if int(row[role]["poison_id"]) == poison_id:
			row[role] = {"poison_id": 0, "script": 0}


func _poison_level(poison_id: int) -> int:
	if poison_id <= 0:
		return 0
	return int(tables.poison_obj_of(poison_id)["poison_level"])


func cure_poison_by_level(role: int, max_level: int) -> void:
	for i in range(MAX_POISONS):
		var row: Array = poison_status[i]
		var id := int(row[role]["poison_id"])
		if id == 0:
			continue
		if _poison_level(id) <= max_level:
			row[role] = {"poison_id": 0, "script": 0}


func is_poisoned_by_level(role: int, min_level: int) -> bool:
	for i in range(MAX_POISONS):
		var id := int(poison_status[i][role]["poison_id"])
		if id != 0 and _poison_level(id) >= min_level:
			return true
	return false


func is_poisoned_by_kind(role: int, poison_id: int) -> bool:
	for i in range(MAX_POISONS):
		if int(poison_status[i][role]["poison_id"]) == poison_id:
			return true
	return false


func poison_scripts(role: int) -> Array[int]:
	var out: Array[int] = []
	for i in range(MAX_POISONS):
		var e: Dictionary = poison_status[i][role]
		if int(e["poison_id"]) != 0:
			out.append(int(e["script"]))
	return out


func cure_all_poisons_by_level(max_level: int) -> void:
	for role in range(MAX_PLAYER_ROLES):
		cure_poison_by_level(role, max_level)


# ------------------------------------------------------------------ 仙术

func add_magic(role: int, magic_obj_id: int) -> bool:
	var slots: Array = roles["magic"]
	for i in range(MAX_PLAYER_MAGICS):
		var flat := i * MAX_PLAYER_ROLES + role
		if int(slots[flat]) == 0:
			slots[flat] = magic_obj_id
			return true
		elif int(slots[flat]) == magic_obj_id:
			return false
	return false


func remove_magic(role: int, magic_obj_id: int) -> bool:
	var slots: Array = roles["magic"]
	for i in range(MAX_PLAYER_MAGICS):
		var flat := i * MAX_PLAYER_ROLES + role
		if int(slots[flat]) == magic_obj_id:
			slots[flat] = 0
			return true
	return false


func player_magics(role: int) -> Array[int]:
	var out: Array[int] = []
	var slots: Array = roles["magic"]
	for i in range(MAX_PLAYER_MAGICS):
		var id := int(slots[i * MAX_PLAYER_ROLES + role])
		if id != 0:
			out.append(id)
	return out


# ------------------------------------------------------------------ 状态

func set_player_status(role: int, status_id: int, rounds: int) -> bool:
	if status_id < 0 or status_id >= STATUS_ALL:
		return false
	if status_id == STATUS_SLOW and int(status[role][STATUS_HASTE]) > 0:
		remove_player_status(role, STATUS_HASTE)
		return true
	if status_id == STATUS_HASTE and int(status[role][STATUS_SLOW]) > 0:
		remove_player_status(role, STATUS_SLOW)
		return true
	match status_id:
		STATUS_CONFUSED, STATUS_SLEEP, STATUS_SILENCE, STATUS_SLOW:
			if int(status[role][status_id]) == 0:
				status[role][status_id] = rounds
		STATUS_PUPPET:
			if int(roles["hp"][role]) == 0:
				if int(status[role][status_id]) < rounds:
					status[role][status_id] = rounds
			else:
				return false
		STATUS_BRAVERY, STATUS_PROTECT, STATUS_DUAL_ATTACK, STATUS_HASTE:
			if int(roles["hp"][role]) != 0 and int(status[role][status_id]) < rounds:
				status[role][status_id] = rounds
	return true


func remove_player_status(role: int, status_id: int) -> void:
	if int(status[role][status_id]) <= 999:
		status[role][status_id] = 0


func clear_all_player_status() -> void:
	for r in range(MAX_PLAYER_ROLES):
		for s in range(STATUS_ALL):
			if int(status[r][s]) <= 999:
				status[r][s] = 0


func has_status(role: int, status_id: int) -> bool:
	return int(status[role][status_id]) > 0


# ------------------------------------------------------------------ 升级

func player_level_up(role: int, num_levels: int) -> void:
	roles["level"][role] = mini(MAX_LEVELS, int(roles["level"][role]) + num_levels)
	for i in range(num_levels):
		roles["max_hp"][role] = int(roles["max_hp"][role]) + 10 + randi_range(0, 7)
		roles["max_mp"][role] = int(roles["max_mp"][role]) + 8 + randi_range(0, 5)
		roles["attack_strength"][role] = int(roles["attack_strength"][role]) + 4 + randi_range(0, 1)
		roles["magic_strength"][role] = int(roles["magic_strength"][role]) + 4 + randi_range(0, 1)
		roles["defense"][role] = int(roles["defense"][role]) + 2 + randi_range(0, 1)
		roles["dexterity"][role] = int(roles["dexterity"][role]) + 2 + randi_range(0, 1)
		roles["flee_rate"][role] = int(roles["flee_rate"][role]) + 2
	for key in ["max_hp", "max_mp", "attack_strength", "magic_strength", "defense", "dexterity", "flee_rate"]:
		roles[key][role] = mini(999, int(roles[key][role]))
	exp["primary"][role]["exp"] = 0
	exp["primary"][role]["level"] = int(roles["level"][role])
	# 升级学仙术（Data#6: level_up_magic[level] 每角色 {level,magic}）
	_learn_level_up_magic(role)
	stats_changed.emit()


func _learn_level_up_magic(role: int) -> void:
	var lv := int(roles["level"][role])
	if lv >= 0 and lv < tables.level_up_magic.size():
		var per_role: Array = tables.level_up_magic[lv]
		if role < per_role.size():
			var magic_id := int(per_role[role]["magic"])
			if magic_id != 0:
				add_magic(role, magic_id)


## 需要多少经验升级（Data#14 rgLevelUpExp[level]）
func exp_for_level(lv: int) -> int:
	if lv >= 0 and lv < tables.level_up_exp.size():
		return int(tables.level_up_exp[lv])
	return 0


# ------------------------------------------------------------------ 存档（SAVEDGAME_WIN 兼容二进制 + vars JSON）

func save_dir() -> String:
	return "user://"


func save_path(slot: int) -> String:
	return "user://pal_save_%d.sav" % slot


func extra_path(slot: int) -> String:
	return "user://pal_save_%d.json" % slot


func save_game(slot: int) -> bool:
	var w := PackedInt32Array()
	saved_times += 1
	_w(w, saved_times)
	_w(w, viewport.x)
	_w(w, viewport.y)
	_w(w, max_party_member_index)          # sdlpal: nPartyMember = wMaxPartyMemberIndex（最大下标）
	_w(w, scene)
	_w(w, palette)
	_w(w, party_dir)
	_w(w, music)
	_w(w, battle_music)
	_w(w, battle_field)
	_w(w, screen_wave)
	_w(w, battle_speed)
	_w(w, collect_value)
	_w(w, layer)
	_w(w, chase_range)
	_w(w, chase_speed_cycles)
	_w(w, follower_count)
	for i in range(3):
		_w(w, 0)
	_w(w, cash & 0xFFFF)
	_w(w, (cash >> 16) & 0xFFFF)
	# PARTY[5] × 5
	for i in range(MAX_PLAYABLE_PLAYER_ROLES):
		var p: Dictionary = party[i]
		_w(w, int(p["role"]))
		_w(w, int(p["x"]) & 0xFFFF)
		_w(w, int(p["y"]) & 0xFFFF)
		_w(w, int(p["frame"]))
		_w(w, int(p["image_offset"]))
	# TRAIL[5] × 3
	for i in range(MAX_PLAYABLE_PLAYER_ROLES):
		var t: Dictionary = trail[i]
		_w(w, int(t["x"]) & 0xFFFF)
		_w(w, int(t["y"]) & 0xFFFF)
		_w(w, int(t["dir"]))
	# ALLEXPERIENCE: 8 groups × 6 roles × 4 words
	for key in ["primary", "health", "magic", "attack", "magic_power", "defense", "dexterity", "flee"]:
		for r in range(MAX_PLAYER_ROLES):
			var e: Dictionary = exp[key][r]
			_w(w, int(e["exp"]))
			_w(w, 0)
			_w(w, int(e["level"]))
			_w(w, 0)
	# PLAYERROLES（450 words）
	w = _write_roles(w, roles)
	# 毒 [16][5] × 2
	for i in range(MAX_POISONS):
		for r in range(MAX_PLAYABLE_PLAYER_ROLES):
			var e: Dictionary = poison_status[i][r]
			_w(w, int(e["poison_id"]))
			_w(w, int(e["script"]))
	# 背包 256×3
	for i in range(MAX_INVENTORY):
		var it: Dictionary = inventory[i]
		_w(w, int(it["item"]))
		_w(w, int(it["amount"]))
		_w(w, int(it["in_use"]))
	# 场景表 300×4（来自 PALTables.sss）
	for i in range(MAX_SCENES):
		var sc: Array = tables.sss.scene(i + 1)
		for k in range(4):
			_w(w, int(sc[k]))
	# OBJECT 600×7（来自 PALTables）
	for i in range(MAX_OBJECTS):
		var d: PackedInt32Array = tables.object_raw(i)
		for k in range(7):
			_w(w, d[k])
	# EVENTOBJECT 5500×16（活表：脚本/场景切换会改）
	for i in range(MAX_EVENT_OBJECTS):
		var eo: Array = []
		if i < tables.sss.events.size():
			eo = tables.sss.events[i]
		for k in range(16):
			_w(w, int(eo[k]) if k < eo.size() else 0)

	var bytes := PackedByteArray()
	bytes.resize(w.size() * 2)
	for i in range(w.size()):
		bytes[i * 2] = w[i] & 0xFF
		bytes[i * 2 + 1] = (w[i] >> 8) & 0xFF
	var fa := FileAccess.open(save_path(slot), FileAccess.WRITE)
	if fa == null:
		push_error("PALState: 无法写入存档 %s" % save_path(slot))
		return false
	fa.store_buffer(bytes)
	fa.close()
	var fj := FileAccess.open(extra_path(slot), FileAccess.WRITE)
	if fj != null:
		fj.store_string(JSON.stringify({"vars": vars, "cash": cash}, "  "))
		fj.close()
	return true


func load_game(slot: int) -> bool:
	var p := save_path(slot)
	if not FileAccess.file_exists(p):
		return false
	loaded_from_save = true          # 读档路径不重播 onEnter（sdlpal global.c:634）
	var fa := FileAccess.open(p, FileAccess.READ)
	var bytes := fa.get_buffer(fa.get_length())
	fa.close()
	var n := bytes.size() / 2
	var w := PackedInt32Array()
	w.resize(n)
	for i in range(n):
		w[i] = bytes[i * 2] | (bytes[i * 2 + 1] << 8)
	var p2 := 0
	saved_times = w[p2]; p2 += 1
	viewport = Vector2i(w[p2], w[p2 + 1]); p2 += 2
	var nparty := w[p2]; p2 += 1
	scene = w[p2]; p2 += 1
	palette = w[p2]; p2 += 1
	party_dir = w[p2]; p2 += 1
	music = w[p2]; p2 += 1
	battle_music = w[p2]; p2 += 1
	battle_field = w[p2]; p2 += 1
	screen_wave = w[p2]; p2 += 1
	battle_speed = w[p2]; p2 += 1
	collect_value = w[p2]; p2 += 1
	layer = w[p2]; p2 += 1
	chase_range = w[p2]; p2 += 1
	chase_speed_cycles = w[p2]; p2 += 1
	follower_count = w[p2]; p2 += 1
	p2 += 3
	cash = w[p2] | (w[p2 + 1] << 16); p2 += 2
	max_party_member_index = clampi(nparty, 0, MAX_PLAYABLE_PLAYER_ROLES - 1)
	party = []
	for i in range(MAX_PLAYABLE_PLAYER_ROLES):
		party.append({"role": w[p2], "x": _s16(w[p2 + 1]), "y": _s16(w[p2 + 2]),
			"frame": w[p2 + 3], "image_offset": w[p2 + 4]})
		p2 += 5
	trail = []
	for i in range(MAX_PLAYABLE_PLAYER_ROLES):
		trail.append({"x": _s16(w[p2]), "y": _s16(w[p2 + 1]), "dir": w[p2 + 2]})
		p2 += 3
	exp = _zero_exp()
	var keys := ["primary", "health", "magic", "attack", "magic_power", "defense", "dexterity", "flee"]
	for key in keys:
		for r in range(MAX_PLAYER_ROLES):
			exp[key][r] = {"exp": w[p2], "level": w[p2 + 2]}
			p2 += 4
	var parsed := _read_roles(w, p2)
	roles = parsed[0]
	p2 = parsed[1]
	for i in range(MAX_POISONS):
		for r in range(MAX_PLAYABLE_PLAYER_ROLES):
			poison_status[i][r] = {"poison_id": w[p2], "script": w[p2 + 1]}
			p2 += 2
	for i in range(MAX_INVENTORY):
		inventory[i] = {"item": w[p2], "amount": w[p2 + 1], "in_use": w[p2 + 2]}
		p2 += 3
	# 场景/对象/事件表：存档里的副本覆盖运行期（对齐原版：读档后所有事件状态回滚）
	for i in range(MAX_SCENES):
		if i < tables.sss.scenes.size():
			var sc: Array = tables.sss.scenes[i]
			for k in range(4):
				sc[k] = w[p2 + k]
		p2 += 4
	for i in range(MAX_OBJECTS):
		if i < tables.objects.size():
			var d: Array = tables.objects[i]["data"]
			for k in range(7):
				d[k] = w[p2 + k]
		p2 += 7
	for i in range(MAX_EVENT_OBJECTS):
		if i < tables.sss.events.size():
			var eo: Array = tables.sss.events[i]
			for k in range(16):
				eo[k] = w[p2 + k]
		p2 += 16

	# 额外变量
	var fj := FileAccess.open(extra_path(slot), FileAccess.READ)
	if fj != null:
		var parsed_json = JSON.parse_string(fj.get_as_text())
		fj.close()
		if typeof(parsed_json) == TYPE_DICTIONARY:
			vars = parsed_json.get("vars", {})
	stats_changed.emit()
	return true
	loaded_from_save = true


func _w(w: PackedInt32Array, v: int) -> void:
	w.append(v & 0xFFFF)


func _s16(v: int) -> int:
	return v - 0x10000 if v >= 0x8000 else v


func _write_roles(w: PackedInt32Array, r: Dictionary) -> PackedInt32Array:
	for key in tables.player_roles.keys():
		var arr: Array = r[key]
		for i in range(arr.size()):
			_w(w, int(arr[i]))
	return w


## 返回 [roles, new_pos]
func _read_roles(w: PackedInt32Array, pos: int) -> Array:
	var out := {}
	for key in tables.player_roles.keys():
		var n: int = (tables.player_roles[key] as Array).size()
		var arr: Array = []
		for i in range(n):
			arr.append(_s16(w[pos + i]))
		out[key] = arr
		pos += n
	return [out, pos]
