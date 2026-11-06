class_name BattleData
extends RefCounted
## 《仙剑98》战斗数据层。
##
## 对应 sdlpal：global.c `PAL_ReadGlobalGameData` / `PAL_LoadDefaultGame`、
## battle.c `PAL_LoadBattleSprites` / `PAL_LoadBattleBackground`、
## uibattle.c `PAL_PlayerInfoBox` 所需的数据。
##
## 数据来源与结构（全部有字节级证据，见 docs/rea/evidence/assets/MISC-FORMAT.md）：
##   * Data.mkf（原样存储，15 块）：
##       #0  STORE[21]            9×u16
##       #1  ENEMY[154]          35×u16（70B）        -> enemies
##       #2  ENEMYTEAM[380]       5×u16（10B）        -> enemy_teams（存的是 OBJECT 号）
##       #3  PLAYERROLES          450×u16（900B）     -> player_roles
##       #4  MAGIC[104]          16×u16（32B）        -> magic_defs
##       #5  BATTLEFIELD[58]      6×u16（12B）        -> battle_fields
##       #6  LEVELUPMAGIC_ALL[20] 5×(level,magic)=20B -> level_up_magic
##       #10 战斗打击特效 sprite（sdlpal lpEffectSprite）
##       #11 rgwBattleEffectIndex 10×2×u16（40B）
##       #13 ENEMYPOS             5×5×(x,y)（100B）
##       #14 rgLevelUpExp[100]    100×u16（200B）
##   * SSS.MKF #2：OBJECT[565]，14B/条 = 7×u16（WIN95 版，global.h tagOBJECT）
##   * F.MKF  ：我方战斗精灵（YJ2 压缩块 + sprite RLE），块号 = PLAYERROLES.sprite_in_battle
##   * Abc.mkf：敌方战斗精灵（YJ2 压缩块 + sprite RLE），块号 = OBJECT.enemy.wEnemyID
##   * Fire.mkf：法术效果帧（YJ2 压缩块 + sprite RLE），块号 = MAGIC.wEffect
##   * Fbp.mkf：战场背景，块解压后恒为 320×200×8bpp 索引图（64000B）
##   * Pat.mkf：调色板（6bit VGA）
##
## 降级策略：优先复用 autoload `PALTables` 的 `data_mkf` / `sss`（避免重复 IO）；
## 若 PALTables 尚未填充（Lead 实现期间），本类自行从数据目录解析同一份表格，
## 保证战斗系统可独立调试。字段命名 = sdlpal 字段去掉 w/rg 前缀的 snake_case。
## 未逐函数对照原版二进制的公式/语义在注释中标 [inf]。

# ------------------------------------------------------------------ 常量

const MAX_PARTY := 3             # MAX_PLAYERS_IN_PARTY
const MAX_ROLES := 6             # MAX_PLAYER_ROLES
const MAX_ENEMIES := 5           # MAX_ENEMIES_IN_TEAM
const MAX_EQUIPMENTS := 6        # MAX_PLAYER_EQUIPMENTS（+1 = kBodyPartExtra 装备脚本槽）
const MAX_PLAYER_MAGICS := 32    # MAX_PLAYER_MAGICS
const NUM_ELEMENTAL := 5         # NUM_MAGIC_ELEMENTAL
const MAX_POISONS := 16          # MAX_POISONS
const MAX_LEVELS := 99
const OBJ_COUNT := 565

# 敌方战斗动作帧区间语义（fight.c/battle.c 引用 wCurrentFrame 的方式）[inf]：
#   idle      : [0, wIdleFrames)
#   magic     : [wIdleFrames, wIdleFrames + wMagicFrames)
#   attack    : [wIdleFrames + wMagicFrames - 1, wIdleFrames + wMagicFrames + wAttackFrames]
const ENEMY_FIELDS: Array[String] = [
	"idle_frames", "magic_frames", "attack_frames", "idle_anim_speed", "act_wait_frames",
	"y_pos_offset", "attack_sound", "action_sound", "magic_sound", "death_sound", "call_sound",
	"health", "exp", "cash", "level", "magic", "magic_rate",
	"attack_equiv_item", "attack_equiv_item_rate", "steal_item", "steal_item_count",
	"attack_strength", "magic_strength", "defense", "dexterity", "flee_rate",
	"poison_resistance", "elem_resistance", "physical_resistance", "dual_move", "collect_value",
]

# global.h tagMAGIC（16×u16；rgSpecific 联合体在 WIN95 版只有 sLayerOffset/wSummonEffect 两种用法）
const MAGIC_FIELDS: Array[String] = [
	"effect", "type", "x_offset", "y_offset", "specific", "speed", "keep_effect",
	"fire_delay", "effect_times", "shake", "wave", "unknown", "cost_mp",
	"base_damage", "elemental", "sound",
]

# ------------------------------------------------------------------ 装载状态

var data_dir: String = ""
var tables: Node = null            # PALTables（可空）
var sss_objects_raw: PackedByteArray = PackedByteArray()
var data_mkf: MkfFile = null

var fbp_mkf: MkfFile = null
var abc_mkf: MkfFile = null
var f_mkf: MkfFile = null
var fire_mkf: MkfFile = null
var pat_mkf: MkfFile = null

var palette: PackedColorArray = PackedColorArray()       # 精灵用：索引 0 = 透明
var palette_bg: PackedColorArray = PackedColorArray()    # 背景用：索引 0 = 不透明黑

var enemies: Array = []            # Array[Dictionary]，下标 = ENEMY 定义号
var enemy_teams: Array = []        # Array[Array[int]]，每个 5 个 OBJECT 号（0xFFFF 空位）
var magic_defs: Array = []         # Array[Dictionary]
var battle_fields: Array = []      # Array[Dictionary]
var level_up_magic: Array = []     # Array[Dictionary]{level,magic} 每项 5 个角色
var battle_effect_index: Array = []  # [10][2] int
var enemy_pos: Array = []          # enemy_pos[i][max_enemy_index] -> Vector2i
var level_up_exp: Array = []       # [100] int
var objects: Array = []            # Array[Dictionary]（OBJECT 的 5 种视图）
var player_roles: Dictionary = {}  # 字段名 -> Array[int]（长度 6 / 5×6 / 32×6 / 6×6）

var loaded: bool = false

var _cache_enemy_frames: Dictionary = {}
var _cache_player_frames: Dictionary = {}
var _cache_fire_frames: Dictionary = {}
var _cache_bg: Dictionary = {}
var _cache_effect_frames: Dictionary = {}


# ------------------------------------------------------------------ 初始化

## 装载全部战斗数据。p_tables 可传 autoload PALTables（推荐），也可省略。
func init(p_data_dir: String, p_tables: Node = null) -> bool:
	data_dir = p_data_dir
	if data_dir == "":
		push_error("BattleData: 数据目录为空")
		return false
	tables = p_tables
	_load_containers()
	_load_tables()
	loaded = true
	return true


func _load_containers() -> void:
	pat_mkf = MkfFile.open_asset(data_dir, "Pat.mkf")
	fbp_mkf = MkfFile.open_asset(data_dir, "Fbp.mkf")
	abc_mkf = MkfFile.open_asset(data_dir, "Abc.mkf")
	f_mkf = MkfFile.open_asset(data_dir, "F.mkf")
	fire_mkf = MkfFile.open_asset(data_dir, "Fire.mkf")
	var pal := PalMap.load_palette(pat_mkf, 0)
	palette = pal.duplicate()
	palette_bg = pal.duplicate()
	if palette_bg.size() > 0:
		palette_bg[0] = Color(0, 0, 0, 1)


func _load_tables() -> void:
	if tables == null:
		tables = _find_tables()
	data_mkf = null
	if tables != null and tables.get("data_mkf") != null:
		data_mkf = tables.data_mkf
	if data_mkf == null:
		data_mkf = MkfFile.open_asset(data_dir, "Data.mkf")
	if data_mkf == null:
		push_error("BattleData: Data.mkf 不可用")
		return

	sss_objects_raw = PackedByteArray()
	if tables != null:
		var s = tables.get("sss")
		if s != null and s.get("objects_raw") is PackedByteArray:
			sss_objects_raw = s.objects_raw
	if sss_objects_raw.is_empty():
		var sss_mkf := MkfFile.open_asset(data_dir, "Sss.mkf")
		if sss_mkf != null and sss_mkf.chunk_count > 2:
			sss_objects_raw = sss_mkf.chunk(2)

	_parse_enemies(data_mkf.chunk(1))
	_parse_enemy_teams(data_mkf.chunk(2))
	_parse_player_roles(data_mkf.chunk(3))
	_parse_magics(data_mkf.chunk(4))
	_parse_battle_fields(data_mkf.chunk(5))
	_parse_level_up_magic(data_mkf.chunk(6))
	_parse_battle_effect_index(data_mkf.chunk(11))
	_parse_enemy_pos(data_mkf.chunk(13))
	_parse_level_up_exp(data_mkf.chunk(14))
	_parse_objects(sss_objects_raw)


func _find_tables() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("PALTables")
	return null


# ------------------------------------------------------------------ 字节工具

static func u16(b: PackedByteArray, off: int) -> int:
	if off < 0 or off + 1 >= b.size():
		return 0
	return b[off] | (b[off + 1] << 8)


static func s16(b: PackedByteArray, off: int) -> int:
	var v := u16(b, off)
	return v - 0x10000 if v >= 0x8000 else v


# ------------------------------------------------------------------ 表格解析

func _parse_enemies(data: PackedByteArray) -> void:
	enemies.clear()
	var n := data.size() / 70
	for i in range(n):
		var o := i * 70
		var e := {
			"id": i,
			"idle_frames": u16(data, o + 0),
			"magic_frames": u16(data, o + 2),
			"attack_frames": u16(data, o + 4),
			"idle_anim_speed": u16(data, o + 6),
			"act_wait_frames": u16(data, o + 8),
			"y_pos_offset": u16(data, o + 10),
			"attack_sound": s16(data, o + 12),
			"action_sound": s16(data, o + 14),
			"magic_sound": s16(data, o + 16),
			"death_sound": s16(data, o + 18),
			"call_sound": s16(data, o + 20),
			"health": u16(data, o + 22),
			"exp": u16(data, o + 24),
			"cash": u16(data, o + 26),
			"level": u16(data, o + 28),
			"magic": u16(data, o + 30),
			"magic_rate": u16(data, o + 32),
			"attack_equiv_item": u16(data, o + 34),
			"attack_equiv_item_rate": u16(data, o + 36),
			"steal_item": u16(data, o + 38),
			"steal_item_count": u16(data, o + 40),
			"attack_strength": s16(data, o + 42),
			"magic_strength": s16(data, o + 44),
			"defense": s16(data, o + 46),
			"dexterity": s16(data, o + 48),
			"flee_rate": u16(data, o + 50),
			"poison_resistance": u16(data, o + 52),
			"elem_resistance": [
				u16(data, o + 54), u16(data, o + 56), u16(data, o + 58),
				u16(data, o + 60), u16(data, o + 62),
			],
			"physical_resistance": u16(data, o + 64),
			"dual_move": u16(data, o + 66),
			"collect_value": u16(data, o + 68),
		}
		enemies.append(e)


func _parse_enemy_teams(data: PackedByteArray) -> void:
	enemy_teams.clear()
	var n := data.size() / 10
	for i in range(n):
		var team: Array[int] = []
		for j in range(MAX_ENEMIES):
			team.append(u16(data, i * 10 + j * 2))
		enemy_teams.append(team)


## PLAYERROLES 解析：与 PALTables.ROLE_FIELDS 一致，用**扁平一维数组**存字段
## （equipment=36 = 部位*6+角色；elemental_resistance=30 = 属性*6+角色；magic=192 = 槽*6+角色），
## 这样与 PALState.roles / PALTables.player_roles 布局完全一致（数组是引用类型，可直接复用）。
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


func _parse_player_roles(data: PackedByteArray) -> void:
	player_roles = {}
	var pos := 0
	for f in ROLE_FIELDS:
		var key: String = f[0]
		var n: int = f[1]
		var arr: Array[int] = []
		for k in range(n):
			arr.append(u16(data, pos))
			pos += 2
		player_roles[key] = arr


func _parse_magics(data: PackedByteArray) -> void:
	magic_defs.clear()
	var n := data.size() / 32
	for i in range(n):
		var o := i * 32
		magic_defs.append({
			"id": i,
			"effect": u16(data, o + 0),
			"type": u16(data, o + 2),
			"x_offset": s16(data, o + 4),
			"y_offset": s16(data, o + 6),
			"specific": s16(data, o + 8),
			"speed": s16(data, o + 10),
			"keep_effect": u16(data, o + 12),
			"fire_delay": u16(data, o + 14),
			"effect_times": u16(data, o + 16),
			"shake": u16(data, o + 18),
			"wave": u16(data, o + 20),
			"unknown": u16(data, o + 22),
			"cost_mp": u16(data, o + 24),
			"base_damage": s16(data, o + 26),
			"elemental": u16(data, o + 28),
			"sound": s16(data, o + 30),
		})


func _parse_battle_fields(data: PackedByteArray) -> void:
	battle_fields.clear()
	var n := data.size() / 12
	for i in range(n):
		var o := i * 12
		battle_fields.append({
			"id": i,
			"screen_wave": u16(data, o + 0),
			"magic_effect": [
				s16(data, o + 2), s16(data, o + 4), s16(data, o + 6),
				s16(data, o + 8), s16(data, o + 10),
			],
		})


func _parse_level_up_magic(data: PackedByteArray) -> void:
	level_up_magic.clear()
	var n := data.size() / 20
	for i in range(n):
		var rec: Array = []
		for role in range(5):  # MAX_PLAYABLE_PLAYER_ROLES
			var o := i * 20 + role * 4
			rec.append({"level": u16(data, o), "magic": u16(data, o + 2)})
		level_up_magic.append(rec)


func _parse_battle_effect_index(data: PackedByteArray) -> void:
	battle_effect_index = []
	for i in range(10):
		if i * 4 + 3 >= data.size():
			break
		battle_effect_index.append([u16(data, i * 4), u16(data, i * 4 + 2)])


func _parse_enemy_pos(data: PackedByteArray) -> void:
	enemy_pos = []
	for i in range(MAX_ENEMIES):
		var row: Array = []
		for j in range(MAX_ENEMIES):
			var o := (i * MAX_ENEMIES + j) * 4
			row.append(Vector2i(u16(data, o), u16(data, o + 2)))
		enemy_pos.append(row)


func _parse_level_up_exp(data: PackedByteArray) -> void:
	level_up_exp = []
	for i in range(MAX_LEVELS + 1):
		level_up_exp.append(u16(data, i * 2))


func _parse_objects(data: PackedByteArray) -> void:
	objects.clear()
	var n := data.size() / 14
	for i in range(n):
		var o := i * 14
		var raw: Array[int] = []
		for k in range(7):
			raw.append(u16(data, o + k * 2))
		objects.append({
			"raw": raw,
			"player": {
				"script_on_friend_death": raw[2],
				"script_on_dying": raw[3],
			},
			"item": {
				"bitmap": raw[0], "price": raw[1],
				"script_on_use": raw[2], "script_on_equip": raw[3],
				"script_on_throw": raw[4], "script_desc": raw[5], "flags": raw[6],
			},
			"magic": {
				"magic_number": raw[0], "reserved1": raw[1],
				"script_on_success": raw[2], "script_on_use": raw[3],
				"script_desc": raw[4], "reserved2": raw[5], "flags": raw[6],
			},
			"enemy": {
				"enemy_id": raw[0], "resistance_to_sorcery": raw[1],
				"script_on_turn_start": raw[2], "script_on_battle_end": raw[3],
				"script_on_ready": raw[4],
			},
			"poison": {
				"poison_level": raw[0], "color": raw[1],
				"player_script": raw[2], "reserved": raw[3], "enemy_script": raw[4],
			},
		})


# ------------------------------------------------------------------ 表格访问

func valid_object(id: int) -> bool:
	return id >= 0 and id < objects.size()


func object_view(id: int, kind: String) -> Dictionary:
	if not valid_object(id):
		return {}
	return objects[id][kind]


func enemy_object(id: int) -> Dictionary:
	return object_view(id, "enemy")


func item_object(id: int) -> Dictionary:
	return object_view(id, "item")


func magic_object(id: int) -> Dictionary:
	return object_view(id, "magic")


func player_object(id: int) -> Dictionary:
	return object_view(id, "player")


func poison_object(id: int) -> Dictionary:
	return object_view(id, "poison")


func enemy_def(enemy_id: int) -> Dictionary:
	if enemy_id < 0 or enemy_id >= enemies.size():
		return {}
	return enemies[enemy_id]


func magic_def(magic_id: int) -> Dictionary:
	if magic_id < 0 or magic_id >= magic_defs.size():
		return {}
	return magic_defs[magic_id]


## 取队伍定义（5 个 OBJECT 号；0xFFFF 表示空位，同 sdlpal PAL_StartBattle）。
func team(team_id: int) -> Array[int]:
	var out: Array[int] = []
	if team_id < 0 or team_id >= enemy_teams.size():
		return out
	for v in enemy_teams[team_id]:
		out.append(int(v))
	return out


func field(field_id: int) -> Dictionary:
	if field_id < 0 or field_id >= battle_fields.size():
		return {}
	return battle_fields[field_id]


func role_value(field_name: String, role: int) -> int:
	var arr = player_roles.get(field_name)
	if arr is Array and role >= 0 and role < arr.size():
		return int(arr[role])
	return 0


## 元素抗性（rgwElementalResistance[attrib][role] 扁平化 = attrib*6+role）。
func elem_resistance_of(role: int) -> Array[int]:
	var out: Array[int] = []
	var arr = player_roles.get("elemental_resistance")
	for e in range(NUM_ELEMENTAL):
		if arr is Array and e * MAX_ROLES + role < arr.size():
			out.append(int(arr[e * MAX_ROLES + role]))
		else:
			out.append(0)
	return out


func equipment_of(role: int) -> Array[int]:
	var out: Array[int] = []
	var arr = player_roles.get("equipment")
	for part in range(MAX_EQUIPMENTS):
		if arr is Array and part * MAX_ROLES + role < arr.size():
			out.append(int(arr[part * MAX_ROLES + role]))
		else:
			out.append(0)
	return out


## 角色在战斗中可用的仙术 OBJECT 号（rgwMagic[slot][role] 扁平化 = slot*6+role）。
func role_magics(role: int) -> Array[int]:
	var out: Array[int] = []
	var arr = player_roles.get("magic")
	if arr is Array:
		for slot in range(MAX_PLAYER_MAGICS):
			var idx := slot * MAX_ROLES + role
			if idx < arr.size():
				var v := int(arr[idx])
				if v != 0:
					out.append(v)
	return out


# ------------------------------------------------------------------ 玩家实体

## 构造一个玩家战斗实体（不含战斗运行期字段）。
## 优先调用 PALState（autoload，对应 global.c PAL_GetPlayer* 一组函数，已含装备效果）；
## PALState 不可用时退回本类解析的 Data#3 默认值（无装备效果）。
func build_player_base(role: int, state: Node) -> Dictionary:
	if state != null and state.has_method("get_player_attack_strength"):
		return _build_player_from_state(role, state)
	var base := {
		"role": role,
		"name_word": role_value("name", role),
		"level": role_value("level", role),
		"max_hp": role_value("max_hp", role),
		"max_mp": role_value("max_mp", role),
		"hp": role_value("hp", role),
		"mp": role_value("mp", role),
		"attack_strength": role_value("attack_strength", role),
		"magic_strength": role_value("magic_strength", role),
		"defense": role_value("defense", role),
		"dexterity": role_value("dexterity", role),
		"flee_rate": role_value("flee_rate", role),
		"poison_resistance": role_value("poison_resistance", role),
		"elem_resistance": elem_resistance_of(role),
		"can_attack_all": role_value("attack_all", role) != 0,
		"cooperative_magic": role_value("cooperative_magic", role),
		"battle_sprite": role_value("sprite_in_battle", role),
		"magics": role_magics(role),
		"equipment": equipment_of(role),
		"covered_by": role_value("covered_by", role),
		"death_sound": role_value("death_sound", role),
		"attack_sound": role_value("attack_sound", role),
		"weapon_sound": role_value("weapon_sound", role),
		"critical_sound": role_value("critical_sound", role),
		"magic_sound": role_value("magic_sound", role),
		"cover_sound": role_value("cover_sound", role),
		"dying_sound": role_value("dying_sound", role),
	}
	return base


func _build_player_from_state(role: int, state: Node) -> Dictionary:
	var elem: Array[int] = []
	for e in range(NUM_ELEMENTAL):
		elem.append(int(state.get_player_elemental_resistance(role, e)))
	var magics := tokens_to_ints(state.player_magics(role))
	var base := {
		"role": role,
		"name_word": role_value("name", role),
		"level": int(state.level(role)),
		"max_hp": int(state.max_hp(role)),
		"max_mp": int(state.max_mp(role)),
		"hp": int(state.hp(role)),
		"mp": int(state.mp(role)),
		"attack_strength": int(state.get_player_attack_strength(role)),
		"magic_strength": int(state.get_player_magic_strength(role)),
		"defense": int(state.get_player_defense(role)),
		"dexterity": int(state.get_player_dexterity(role)),
		"flee_rate": int(state.get_player_flee_rate(role)),
		"poison_resistance": int(state.get_player_poison_resistance(role)),
		"elem_resistance": elem,
		"can_attack_all": bool(state.player_can_attack_all(role)),
		"cooperative_magic": int(state.get_player_cooperative_magic(role)),
		"battle_sprite": int(state.get_player_battle_sprite(role)),
		"magics": magics,
		"equipment": equipment_of(role),
		"covered_by": role_value("covered_by", role),
		"death_sound": role_value("death_sound", role),
		"attack_sound": role_value("attack_sound", role),
		"weapon_sound": role_value("weapon_sound", role),
		"critical_sound": role_value("critical_sound", role),
		"magic_sound": role_value("magic_sound", role),
		"cover_sound": role_value("cover_sound", role),
		"dying_sound": role_value("dying_sound", role),
	}
	# 运行时 PLAYERROLES 里的名字/覆盖者/音效以 PALState.roles 为准
	var st_roles = state.get("roles")
	if st_roles is Dictionary:
		var names = st_roles.get("name")
		if names is Array and role < names.size():
			base["name_word"] = int(names[role])
		var cb = st_roles.get("covered_by")
		if cb is Array and role < cb.size():
			base["covered_by"] = int(cb[role])
		for key in ["death_sound", "attack_sound", "weapon_sound", "critical_sound",
				"magic_sound", "cover_sound", "dying_sound"]:
			var arr = st_roles.get(key)
			if arr is Array and role < arr.size():
				base[key] = int(arr[role])
	return base


func tokens_to_ints(src) -> Array[int]:
	var out: Array[int] = []
	for v in src:
		out.append(int(v))
	return out


# ------------------------------------------------------------------ 敌方实体

## 用 ENEMY 定义构造敌方战斗实体（wObjectID 对应 OBJECT 号）。
func build_enemy_base(object_id: int) -> Dictionary:
	var eo := enemy_object(object_id)
	if eo.is_empty():
		return {}
	var eid := int(eo.get("enemy_id", 0))
	var ed := enemy_def(eid)
	if ed.is_empty():
		return {}
	return {
		"object_id": object_id,
		"enemy_id": eid,
		"stats": ed.duplicate(true),     # 战斗内 HP 等在此副本上修改
		"script_on_turn_start": int(eo.get("script_on_turn_start", 0)),
		"script_on_battle_end": int(eo.get("script_on_battle_end", 0)),
		"script_on_ready": int(eo.get("script_on_ready", 0)),
		"resistance_to_sorcery": int(eo.get("resistance_to_sorcery", 0)),
	}


# ------------------------------------------------------------------ 精灵/背景装载

func enemy_frames(enemy_id: int) -> Array[Image]:
	if _cache_enemy_frames.has(enemy_id):
		return _cache_enemy_frames[enemy_id]
	var out: Array[Image] = []
	# Abc.mkf 块 0 为空（证据：154 块中 1 块空），有效敌人精灵号 >= 1；
	# 但这里仍允许 0 以保持与 sprite 块号一致。
	if abc_mkf != null and enemy_id >= 0 and enemy_id < abc_mkf.chunk_count:
		var raw := abc_mkf.decompressed(enemy_id)
		if raw.size() > 4:
			out = PalSprite.decode_sprite(raw, palette)
	_cache_enemy_frames[enemy_id] = out
	return out


func player_frames(sprite_num: int) -> Array[Image]:
	if _cache_player_frames.has(sprite_num):
		return _cache_player_frames[sprite_num]
	var out: Array[Image] = []
	# F.MKF 只有 19 块且块 0 有效（李逍遥 sprite_in_battle=0），必须允许 0。
	if f_mkf != null and sprite_num >= 0 and sprite_num < f_mkf.chunk_count:
		var raw := f_mkf.decompressed(sprite_num)
		if raw.size() > 4:
			out = PalSprite.decode_sprite(raw, palette)
	_cache_player_frames[sprite_num] = out
	return out


func fire_frames(effect_num: int) -> Array[Image]:
	if _cache_fire_frames.has(effect_num):
		return _cache_fire_frames[effect_num]
	var out: Array[Image] = []
	# Fire.mkf 55 块，块号 = MAGIC.wEffect，从 0 起有效。
	if fire_mkf != null and effect_num >= 0 and effect_num < fire_mkf.chunk_count:
		var raw := fire_mkf.decompressed(effect_num)
		if raw.size() > 4:
			out = PalSprite.decode_sprite(raw, palette)
	_cache_fire_frames[effect_num] = out
	return out


## Data.mkf #10 战斗打击特效 sprite（sdlpal g_Battle.lpEffectSprite）。
func effect_frames() -> Array[Image]:
	if _cache_effect_frames.has("all"):
		return _cache_effect_frames["all"]
	var out: Array[Image] = []
	if data_mkf != null and data_mkf.chunk_count > 10:
		var raw := data_mkf.chunk(10)
		if raw.size() > 4:
			out = PalSprite.decode_sprite(raw, palette)
	_cache_effect_frames["all"] = out
	return out


## 战场背景：Fbp.mkf 第 field 块（YJ2 解压后 64000B = 320×200 索引图）。
## 失败时退回第 6 块（证据：FBP 块 6 起为典型战斗背景）。
func background(field_num: int) -> Image:
	var key := field_num
	if _cache_bg.has(key):
		return _cache_bg[key]
	var img := _decode_fbp(field_num)
	if img == null or img.get_width() != 320:
		img = _decode_fbp(6)
	if img == null:
		img = Image.create_empty(320, 200, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 1))
	_cache_bg[key] = img
	return img


func _decode_fbp(field_num: int) -> Image:
	if fbp_mkf == null or field_num < 0 or field_num >= fbp_mkf.chunk_count:
		return null
	var idx := fbp_mkf.decompressed(field_num)
	if idx.size() != 320 * 200:
		return null
	var rgba := PackedByteArray()
	rgba.resize(320 * 200 * 4)
	for i in range(320 * 200):
		var c := palette_bg[idx[i]]
		var o := i * 4
		rgba[o] = c.r8
		rgba[o + 1] = c.g8
		rgba[o + 2] = c.b8
		rgba[o + 3] = 255
	return Image.create_from_data(320, 200, false, Image.FORMAT_RGBA8, rgba)


# ------------------------------------------------------------------ 其它查询

## 等级升级所需经验（rgLevelUpExp[level]）。
func exp_to_next_level(level: int) -> int:
	var i := clampi(level, 0, MAX_LEVELS)
	if i < level_up_exp.size():
		return int(level_up_exp[i])
	return 0


## 玩家战斗精灵号（装备可覆盖 sprite_in_battle，见 global.c PAL_GetPlayerBattleSprite）。
func battle_sprite_of(role: int, state: Node) -> int:
	if state != null and state.has_method("get_player_battle_sprite"):
		return int(state.get_player_battle_sprite(role))
	var s := role_value("sprite_in_battle", role)
	for part in _equip_effects(state):
		if part is Dictionary:
			var arr = part.get("sprite_in_battle")
			if arr is Array and role < arr.size() and int(arr[role]) != 0:
				s = int(arr[role])
	return s


## 装备效果表：[7] 份 PLAYERROLES 形态的字典（PALState.equipment_effect，字段为扁平数组）。
func _equip_effects(state: Node) -> Array:
	if state == null:
		return []
	var e = state.get("equipment_effect")
	if e is Array and e.size() > 0:
		return e
	return []


## 取装备叠加的某项属性（字段名 = PLAYERROLES 字段名）。
## 注意 PALState.roles 的字段是扁平数组（普通属性 len=6，可直接 arr[role]）。
func equip_bonus(state: Node, role: int, field_name: String) -> int:
	var total := 0
	for part in _equip_effects(state):
		if part is Dictionary:
			var arr = part.get(field_name)
			if arr is Array and role >= 0 and role < arr.size():
				total += int(arr[role])
	return total


## 取装备叠加的元素抗性（5 项；扁平布局 = attib*6+role）。
func equip_elem_bonus(state: Node, role: int, elem: int) -> int:
	var total := 0
	for part in _equip_effects(state):
		if part is Dictionary:
			var arr = part.get("elemental_resistance")
			var idx := elem * MAX_ROLES + role
			if arr is Array and idx >= 0 and idx < arr.size():
				total += int(arr[idx])
	return total
