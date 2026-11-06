extends Node
## 只读数据表（autoload `PALTables`）。
## 移植 sdlpal global.c: PAL_ReadGlobalGameData / PAL_LoadDefaultGame / PAL_InitGlobalGameData。
## 布局以 global.h 结构体为准；Data.mkf 块号与 struct 大小已按证据校验：
##   0 STORE(9w) / 1 ENEMY(35w) / 2 ENEMYTEAM(5w) / 3 PLAYERROLES(450w=900B)
##   4 MAGIC(16w) / 5 BATTLEFIELD(6w) / 6 LEVELUPMAGIC_ALL(5×2w) / 11 BattleEffectIndex(10×2w)
##   13 ENEMYPOS(5×5×2w) / 14 rgLevelUpExp(MAX_LEVELS+1 w) / 12 对话图标(282B)
## SSS 块 2 = OBJECT[565]（14B/条，WIN 版 7 words）；SSS 块 0/1/3/4 由 PalData 解析。

const MAX_PLAYER_ROLES := 6
const MAX_PLAYABLE_PLAYER_ROLES := 5
const MAX_LEVELS := 99
const MAX_OBJECTS := 600
const MAX_STORE_ITEM := 9
const MAX_ENEMIES_IN_TEAM := 5
const NUM_MAGIC_ELEMENTAL := 5
const MAX_PLAYER_EQUIPMENTS := 6
const MAX_PLAYER_MAGICS := 32

var ready_flag: bool = false
var data_dir: String = ""
var sss: PalData = null
var data_mkf: MkfFile = null
var words: PackedStringArray = PackedStringArray()

## OBJECT 表：0-based，id 0 保留。每项 = {data: PackedInt32Array(7)}（联合体原始字段）
var objects: Array = []
var player_roles: Dictionary = {}          # 默认 PLAYERROLES（Data#3）
var enemy_defs: Array = []                  # Data#1 tagENEMY
var enemy_teams: Array = []                 # Data#2，Array[PackedInt32Array(5)]
var magic_defs: Array = []                  # Data#4 tagMAGIC
var battle_fields: Array = []               # Data#5 {screen_wave:int, magic_effect:Array[int](5)}
var level_up_magic: Array = []              # Data#6，Array[Array[5]{level,magic}]
var battle_effect_index: Array = []         # Data#11，10×[a,b]
var enemy_pos: Array = []                   # Data#13，[5][5] Vector2i
var level_up_exp: PackedInt32Array = PackedInt32Array()   # Data#14，MAX_LEVELS+1
var stores: Array = []                      # Data#0，Array[PackedInt32Array(9)]
var dialog_icons: PackedByteArray = PackedByteArray()     # Data#12

## PLAYERROLES 字段顺序（u16 连续读）
const ROLE_FIELDS: Array = [
	["avatar", 6], ["sprite_in_battle", 6], ["sprite_in_scene", 6], ["name", 6],
	["attack_all", 6], ["unknown1", 6], ["level", 6], ["max_hp", 6], ["max_mp", 6],
	["hp", 6], ["mp", 6],
	["equipment", 36],
	["attack_strength", 6], ["magic_strength", 6], ["defense", 6], ["dexterity", 6],
	["flee_rate", 6], ["poison_resistance", 6],
	["elemental_resistance", 30],
	["unknown2", 6], ["unknown3", 6], ["unknown4", 6], ["covered_by", 6],
	["magic", 192],
	["walk_frames", 6], ["cooperative_magic", 6], ["unknown5", 6], ["unknown6", 6],
	["death_sound", 6], ["attack_sound", 6], ["weapon_sound", 6], ["critical_sound", 6],
	["magic_sound", 6], ["cover_sound", 6], ["dying_sound", 6],
]

## ENEMY 字段顺序（35 words）
const ENEMY_FIELDS: Array = [
	"idle_frames", "magic_frames", "attack_frames", "idle_anim_speed", "act_wait_frames",
	"y_pos_offset", "attack_sound", "action_sound", "magic_sound", "death_sound", "call_sound",
	"health", "exp", "cash", "level", "magic", "magic_rate", "attack_equiv_item",
	"attack_equiv_item_rate", "steal_item", "steal_item_count", "attack_strength",
	"magic_strength", "defense", "dexterity", "flee_rate", "poison_resistance",
	"elem_resistance_0", "elem_resistance_1", "elem_resistance_2", "elem_resistance_3",
	"elem_resistance_4", "physical_resistance", "dual_move", "collect_value",
]

## MAGIC 字段顺序（16 words）
const MAGIC_FIELDS: Array = [
	"effect", "type", "x_offset", "y_offset", "specific", "speed", "keep_effect",
	"fire_delay", "effect_times", "shake", "wave", "unknown", "cost_mp", "base_damage",
	"elemental", "sound",
]


func init(p_data_dir: String) -> bool:
	data_dir = p_data_dir
	ready_flag = false
	var s := PalData.new()
	if not s.load_all(p_data_dir):
		push_error("PALTables: SSS 装载失败")
		return false
	sss = s
	data_mkf = MkfFile.open_asset(p_data_dir, "Data.mkf")
	if data_mkf == null:
		push_error("PALTables: Data.mkf 打开失败")
		return false
	_load_words()
	_load_objects()
	_load_player_roles()
	_load_enemy_defs()
	_load_enemy_teams()
	_load_magic_defs()
	_load_battle_fields()
	_load_level_up_magic()
	_load_battle_effect_index()
	_load_enemy_pos()
	_load_level_up_exp()
	_load_stores()
	_load_dialog_icons()
	ready_flag = true
	print("[PALTables] objects=%d enemies=%d teams=%d magics=%d fields=%d stores=%d words=%d" % [
		objects.size(), enemy_defs.size(), enemy_teams.size(), magic_defs.size(),
		battle_fields.size(), stores.size(), words.size()])
	return true


# ------------------------------------------------------------------ 基础读取

func _chunk_words(chunk_index: int) -> PackedInt32Array:
	var b := data_mkf.chunk(chunk_index)
	var out := PackedInt32Array()
	out.resize(b.size() / 2)
	for i in range(out.size()):
		out[i] = b[i * 2] | (b[i * 2 + 1] << 8)
	return out


func _b16(b: PackedByteArray, off: int) -> int:
	if off + 1 >= b.size():
		return 0
	return b[off] | (b[off + 1] << 8)


# ------------------------------------------------------------------ Word.dat

func _load_words() -> void:
	words = PackedStringArray()
	var p := "res://data/word_zh.json"
	if FileAccess.file_exists(p):
		var fa := FileAccess.open(p, FileAccess.READ)
		var parsed = JSON.parse_string(fa.get_as_text())
		fa.close()
		if typeof(parsed) == TYPE_ARRAY:
			words = PackedStringArray(parsed)
	if words.is_empty():
		push_warning("PALTables: 缺少 data/word_zh.json（先用 tools/extract_word.py 生成）")


func word(id: int) -> String:
	if id >= 0 and id < words.size():
		return words[id]
	return ""


func player_name(role: int) -> String:
	if role < 0 or role >= MAX_PLAYER_ROLES:
		return ""
	var names: Array = player_roles.get("name", [])
	if role < names.size():
		return word(int(names[role]))
	return ""


## 名称约定（[obs] sdlpal：菜单/战斗都直接 PAL_GetWord(对象ID)，名字来自 Word.dat）
func item_name(item_id: int) -> String:
	return word(item_id)


func magic_name(magic_obj_id: int) -> String:
	return word(magic_obj_id)


func enemy_name(enemy_obj_id: int) -> String:
	return word(enemy_obj_id)


## 便捷取表（供 battle/menus 使用；越界返回空）
func enemy_def(enemy_id: int) -> Dictionary:
	if enemy_id > 0 and enemy_id < enemy_defs.size():
		return enemy_defs[enemy_id]
	return {}


func enemy_team(team_id: int) -> PackedInt32Array:
	if team_id > 0 and team_id < enemy_teams.size():
		return enemy_teams[team_id]
	return PackedInt32Array([0, 0, 0, 0, 0])


func battle_field_def(id: int) -> Dictionary:
	if id > 0 and id < battle_fields.size():
		return battle_fields[id]
	return {"screen_wave": 0, "magic_effect": [0, 0, 0, 0, 0]}


func store_items(store_id: int) -> PackedInt32Array:
	if store_id >= 0 and store_id < stores.size():
		return stores[store_id]
	return PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0])


# ------------------------------------------------------------------ OBJECT（SSS#2）

func _load_objects() -> void:
	objects = []
	var raw := sss.objects_raw
	var n := raw.size() / 14
	for i in range(n):
		var d := PackedInt32Array()
		d.resize(7)
		for k in range(7):
			d[k] = _b16(raw, i * 14 + k * 2)
		objects.append({"data": d})


func object_raw(id: int) -> PackedInt32Array:
	if id <= 0 or id >= objects.size():
		return PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
	return objects[id]["data"]


# 联合体视图（sdlpal global.h: OBJECT union, WIN 版 7 words）
func item_of(id: int) -> Dictionary:
	var d := object_raw(id)
	return {
		"bitmap": d[0], "price": d[1], "script_on_use": d[2], "script_on_equip": d[3],
		"script_on_throw": d[4], "script_desc": d[5], "flags": d[6],
	}


func magic_obj_of(id: int) -> Dictionary:
	var d := object_raw(id)
	return {
		"magic_number": d[0], "reserved1": d[1], "script_on_success": d[2],
		"script_on_use": d[3], "script_desc": d[4], "reserved2": d[5], "flags": d[6],
	}


func enemy_obj_of(id: int) -> Dictionary:
	var d := object_raw(id)
	return {
		"enemy_id": d[0], "resistance_to_sorcery": d[1], "script_on_turn_start": d[2],
		"script_on_battle_end": d[3], "script_on_ready": d[4],
	}


func poison_obj_of(id: int) -> Dictionary:
	var d := object_raw(id)
	return {
		"poison_level": d[0], "color": d[1], "player_script": d[2], "reserved": d[3],
		"enemy_script": d[4],
	}


func player_obj_of(id: int) -> Dictionary:
	var d := object_raw(id)
	return {
		"reserved0": d[0], "reserved1": d[1], "script_on_friend_death": d[2],
		"script_on_dying": d[3],
	}


## 物品对象 id 列表（按 item 视图过滤）
func item_ids() -> Array[int]:
	var out: Array[int] = []
	for id in range(1, objects.size()):
		var it := item_of(id)
		if int(it["bitmap"]) != 0 or int(it["price"]) != 0 or int(it["flags"]) != 0:
			out.append(id)
	return out


func magic_obj_ids() -> Array[int]:
	var out: Array[int] = []
	for id in range(1, objects.size()):
		if int(magic_obj_of(id)["magic_number"]) != 0:
			out.append(id)
	return out


func enemy_obj_ids() -> Array[int]:
	var out: Array[int] = []
	for id in range(1, objects.size()):
		if int(enemy_obj_of(id)["enemy_id"]) != 0:
			out.append(id)
	return out


func poison_obj_ids() -> Array[int]:
	var out: Array[int] = []
	for id in range(1, objects.size()):
		if int(poison_obj_of(id)["poison_level"]) != 0:
			out.append(id)
	return out


func magic_def_for(magic_obj_id: int) -> Dictionary:
	var num := int(magic_obj_of(magic_obj_id)["magic_number"])
	if num > 0 and num < magic_defs.size():
		return magic_defs[num]
	return {}


# ------------------------------------------------------------------ 其它表

func _fill_fields(words_arr: PackedInt32Array, fields: Array, offset: int, count: int) -> Dictionary:
	var out := {}
	var p := offset
	for f in fields:
		var key: String = f[0]
		var n: int = f[1]
		var arr: Array = []
		for k in range(n):
			arr.append(words_arr[p + k])
		out[key] = arr
		p += n
	return out


func _load_player_roles() -> void:
	var w := _chunk_words(3)
	player_roles = _fill_fields(w, ROLE_FIELDS, 0, MAX_PLAYER_ROLES)


func _load_enemy_defs() -> void:
	var w := _chunk_words(1)
	var stride := ENEMY_FIELDS.size()
	var n := w.size() / stride
	enemy_defs = []
	for i in range(n):
		var d := {}
		for k in range(stride):
			d[ENEMY_FIELDS[k]] = w[i * stride + k]
		enemy_defs.append(d)


func _load_enemy_teams() -> void:
	var w := _chunk_words(2)
	var stride := MAX_ENEMIES_IN_TEAM
	enemy_teams = []
	for i in range(w.size() / stride):
		var a := PackedInt32Array()
		for k in range(stride):
			a.append(w[i * stride + k])
		enemy_teams.append(a)


func _load_magic_defs() -> void:
	var w := _chunk_words(4)
	var stride := MAGIC_FIELDS.size()
	magic_defs = []
	for i in range(w.size() / stride):
		var d := {}
		for k in range(stride):
			d[MAGIC_FIELDS[k]] = w[i * stride + k]
		magic_defs.append(d)


func _load_battle_fields() -> void:
	var w := _chunk_words(5)
	var stride := 1 + NUM_MAGIC_ELEMENTAL
	battle_fields = []
	for i in range(w.size() / stride):
		var d := {"screen_wave": w[i * stride], "magic_effect": []}
		for k in range(NUM_MAGIC_ELEMENTAL):
			d["magic_effect"].append(w[i * stride + 1 + k])
		battle_fields.append(d)


func _load_level_up_magic() -> void:
	var w := _chunk_words(6)
	var stride := MAX_PLAYABLE_PLAYER_ROLES * 2
	level_up_magic = []
	for i in range(w.size() / stride):
		var per_role: Array = []
		for r in range(MAX_PLAYABLE_PLAYER_ROLES):
			per_role.append({"level": w[i * stride + r * 2], "magic": w[i * stride + r * 2 + 1]})
		level_up_magic.append(per_role)


func _load_battle_effect_index() -> void:
	var w := _chunk_words(11)
	battle_effect_index = []
	for i in range(w.size() / 2):
		battle_effect_index.append([w[i * 2], w[i * 2 + 1]])


func _load_enemy_pos() -> void:
	var w := _chunk_words(13)
	enemy_pos = []
	var p := 0
	for i in range(MAX_ENEMIES_IN_TEAM):
		var row: Array = []
		for j in range(MAX_ENEMIES_IN_TEAM):
			row.append(Vector2i(w[p], w[p + 1]))
			p += 2
		enemy_pos.append(row)


func _load_level_up_exp() -> void:
	level_up_exp = _chunk_words(14)


func _load_stores() -> void:
	var w := _chunk_words(0)
	stores = []
	for i in range(w.size() / MAX_STORE_ITEM):
		var a := PackedInt32Array()
		for k in range(MAX_STORE_ITEM):
			a.append(w[i * MAX_STORE_ITEM + k])
		stores.append(a)


func _load_dialog_icons() -> void:
	dialog_icons = data_mkf.chunk(12)
