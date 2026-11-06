extends RefCounted
## 存档槽位封装 + SAVEDGAME_WIN 兼容性说明/校验（数据读写本体在 PALState）。
##
## 二进制格式（sdlpal global.c: tagSAVEDGAME_WIN，小端；DWORD dwCash 按 16 位字写入）：
##
##   字偏移  字节偏移  字段
##   ------------------------------------------------------------------
##   0       0         wSavedTimes            存档次数
##   1       2         wViewportX
##   2       4         wViewportY
##   3       6         nPartyMember           队伍人数-1
##   4       8         wNumScene              场景号
##   5       10        wPaletteOffset         夜色调色板 = 0x180
##   6       12        wPartyDirection
##   7       14        wNumMusic
##   8       16        wNumBattleMusic
##   9       18        wNumBattleField
##   10      20        wScreenWave
##   11      22        wBattleSpeed
##   12      24        wCollectValue
##   13      26        wLayer
##   14      28        wChaseRange
##   15      30        wChasespeedChangeCycles
##   16      32        nFollower
##   17..19  34..39    rgwReserved2[3]
##   20..21  40..43    dwCash（低 16 位在前，等价小端 DWORD）
##   22      44        PARTY rgParty[5]     每项 5 字：role, x, y, frame, imageOffset
##   47      94        TRAIL rgTrail[5]     每项 3 字：x, y, dir
##   62      124       ALLEXPERIENCE Exp    8 组 × 6 角色 × 4 字（exp,0,level,0）
##   254     508       PLAYERROLES          450 字（900 B = Data.mkf #3）
##   704     1408      POISONSTATUS[16][5]  每项 2 字
##   864     1728      INVENTORY[256]       每项 3 字：item, amount, amountInUse
##   1632    3264      SCENE[300]           每项 4 字（来自 SSS#1）
##   2832    5664      OBJECT[600]          每项 7 字（来自 SSS#2 的 WIN 版联合体）
##   7032    14064     EVENTOBJECT[n]       每项 16 字（sdlpal 写 SSS#0 原始 5077 条 = 162464 B）
##
## 文件长度：
##   * sdlpal 原版 WIN95：14064 + 5077*32 = **168128** 字节（PAL_SaveGame_Common 按
##     `chunkSize(SSS#0) + sizeof - MAX_EVENT_OBJECTS*sizeof(EVENTOBJECT)` 截断写出）；
##   * 本移植 PALState.save_game：写满 5500 条事件槽 = **190064** 字节（仍与原版读取兼容，
##     多出的 5500-5077 条为零/未用槽）。
## 加载端两者都接受（PAL_LoadGame_Common 只要求 ≥ 14064 字节）。
##
## 与原始存档的差异（兼容性说明）：
##   1. 文件名/目录：原版为游戏目录下 `1.rpg..5.rpg`；本移植为 `user://pal_save_<slot>.sav`，
##      二进制内容可改名后直接被 sdlpal 读取（或反之，把 1.rpg 改名成 pal_save_1.sav）。
##   2. 事件对象表：原版写 SSS#0 原始副本；本移植写运行时活表（脚本会改事件状态），
##      读档时回滚运行期事件表 —— 语义更接近原版意图。
##   3. 额外 vars 字典另存 `user://pal_save_<slot>.json`（sdlpal 无对应概念，忽略即可）。

const MAX_PLAYER_ROLES := 6
const MAX_PLAYABLE_PLAYER_ROLES := 5
const MAX_POISONS := 16
const MAX_INVENTORY := 256
const MAX_SCENES := 300
const MAX_OBJECTS := 600
const MAX_EVENT_OBJECTS := 5500
const MAX_PLAYER_EQUIPMENTS := 6

# 字偏移（见文件头表）
const W_SAVED_TIMES := 0
const W_VIEWPORT_X := 1
const W_VIEWPORT_Y := 2
const W_NPARTY_MEMBER := 3
const W_NUM_SCENE := 4
const W_PALETTE_OFFSET := 5
const W_PARTY_DIRECTION := 6
const W_NUM_MUSIC := 7
const W_NUM_BATTLE_MUSIC := 8
const W_NUM_BATTLE_FIELD := 9
const W_SCREEN_WAVE := 10
const W_BATTLE_SPEED := 11
const W_COLLECT_VALUE := 12
const W_LAYER := 13
const W_CHASE_RANGE := 14
const W_CHASE_CYCLES := 15
const W_FOLLOWER := 16
const W_CASH_LO := 20
const W_CASH_HI := 21
const W_PARTY := 22
const W_TRAIL := 47
const W_EXP := 62
const W_ROLES := 254
const W_POISON := 704
const W_INVENTORY := 864
const W_SCENES := 1632
const W_OBJECTS := 2832
const W_EVENTS := 7032

## 原版写出的文件长度（5077 条事件）
const SDLPAL_FILE_SIZE := 168128
## 本移植写满 5500 条事件槽的长度
const GODOT_FILE_SIZE := 190064
## 事件表之前的公共前缀字节数
const COMMON_PREFIX_SIZE := 14064


# ---------------------------------------------------------------- 路径

static func slot_path(slot: int) -> String:
	if PALState != null and PALState.has_method("save_path"):
		return str(PALState.save_path(slot))
	return "user://pal_save_%d.sav" % slot


static func slot_extra_path(slot: int) -> String:
	if PALState != null and PALState.has_method("extra_path"):
		return str(PALState.extra_path(slot))
	return "user://pal_save_%d.json" % slot


# ---------------------------------------------------------------- 读取

## 只读前 44 字节头部（槽位菜单显示用）。
## 注意：nPartyMember 语义已由 Lead 对齐 sdlpal —— 字段 = **队伍最大下标**（0 起），
## 人数 = 字段 + 1（本移植 190064 文件同样如此，pal_state.gd 已修正）。
static func read_header(slot: int) -> Dictionary:
	var out := {"valid": false, "saved_times": 0, "scene": 1, "cash": 0,
		"party_size": 1, "n_party_field": 0, "battle_speed": 2,
		"palette_night": false, "size": 0}
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return out
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return out
	var size := fa.get_length()
	if size < 44:
		fa.close()
		return out
	var bytes := fa.get_buffer(mini(44, size))
	fa.close()
	var words := _words(bytes)
	out["size"] = size
	out["valid"] = true
	out["saved_times"] = words[W_SAVED_TIMES]
	out["scene"] = words[W_NUM_SCENE]
	out["n_party_field"] = words[W_NPARTY_MEMBER]
	out["party_size"] = maxi(1, words[W_NPARTY_MEMBER] + 1)
	out["palette_night"] = words[W_PALETTE_OFFSET] != 0
	out["battle_speed"] = words[W_BATTLE_SPEED]
	out["cash"] = words[W_CASH_LO] | (words[W_CASH_HI] << 16)
	return out


## 槽位摘要（存档/读档菜单显示）：次数 / 场景号 / 时间 / 兼容性。
static func slot_summary(slot: int) -> Dictionary:
	var path := slot_path(slot)
	var info := {"slot": slot, "exists": FileAccess.file_exists(path), "path": path,
		"saved_times": 0, "scene": 0, "cash": 0, "party_size": 0,
		"time_text": "", "compatible": true, "size": 0, "layout": "none"}
	if not bool(info["exists"]):
		return info
	var h := read_header(slot)
	info["saved_times"] = int(h["saved_times"])
	info["scene"] = int(h["scene"])
	info["cash"] = int(h["cash"])
	info["party_size"] = int(h["party_size"])
	info["size"] = int(h["size"])
	info["compatible"] = int(h["size"]) >= COMMON_PREFIX_SIZE
	info["layout"] = "godot-190064" if int(h["size"]) >= GODOT_FILE_SIZE else (
		"sdlpal-168128" if int(h["size"]) >= SDLPAL_FILE_SIZE else "truncated")
	var mtime := FileAccess.get_modified_time(path)
	var dt := Time.get_datetime_dict_from_unix_time(mtime + Time.get_time_zone_from_system().bias * 60)
	info["time_text"] = "%02d-%02d %02d:%02d" % [
		int(dt["month"]), int(dt["day"]), int(dt["hour"]), int(dt["minute"])]
	return info


## 额外 vars JSON（PALState.save_game 写出的 user://pal_save_N.json）
static func read_extra(slot: int) -> Dictionary:
	var path := slot_extra_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return {}
	var parsed = JSON.parse_string(fa.get_as_text())
	fa.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}


## 结构校验：返回 {ok, size, layout, errors:[...]}，用于排错与兼容性说明。
static func validate(slot: int) -> Dictionary:
	var out := {"ok": false, "size": 0, "layout": "none", "errors": []}
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		out["errors"].append("文件不存在")
		return out
	var fa := FileAccess.open(path, FileAccess.READ)
	out["size"] = fa.get_length()
	fa.close()
	var size: int = int(out["size"])
	if size < COMMON_PREFIX_SIZE:
		out["errors"].append("长度 %d < 公共前缀 %d" % [size, COMMON_PREFIX_SIZE])
		return out
	if size % 2 != 0:
		out["errors"].append("长度非偶数（WORD 结构）")
	if size == SDLPAL_FILE_SIZE:
		out["layout"] = "sdlpal-168128"
	elif size == GODOT_FILE_SIZE:
		out["layout"] = "godot-190064"
	elif size >= COMMON_PREFIX_SIZE:
		out["layout"] = "partial-%d" % size
		out["errors"].append("非标准长度（可被 PAL_LoadGame_Common 读取，但非原版写出长度）")
	out["ok"] = size % 2 == 0
	return out


## 布局说明（供 docs/调试打印；返回各段 [字偏移, 字节偏移, 字数]）。
static func layout() -> Dictionary:
	return {
		"saved_times": [W_SAVED_TIMES, W_SAVED_TIMES * 2, 17],
		"cash": [W_CASH_LO, W_CASH_LO * 2, 2],
		"party": [W_PARTY, W_PARTY * 2, MAX_PLAYABLE_PLAYER_ROLES * 5],
		"trail": [W_TRAIL, W_TRAIL * 2, MAX_PLAYABLE_PLAYER_ROLES * 3],
		"exp": [W_EXP, W_EXP * 2, 8 * MAX_PLAYER_ROLES * 4],
		"player_roles": [W_ROLES, W_ROLES * 2, 450],
		"poison": [W_POISON, W_POISON * 2, MAX_POISONS * MAX_PLAYABLE_PLAYER_ROLES * 2],
		"inventory": [W_INVENTORY, W_INVENTORY * 2, MAX_INVENTORY * 3],
		"scenes": [W_SCENES, W_SCENES * 2, MAX_SCENES * 4],
		"objects": [W_OBJECTS, W_OBJECTS * 2, MAX_OBJECTS * 7],
		"events": [W_EVENTS, W_EVENTS * 2, MAX_EVENT_OBJECTS * 16],
	}


## 兼容性说明文本（写进报告/调试输出）
static func compatibility_note() -> String:
	return ("SAVEDGAME_WIN 兼容：%d 字节公共前缀（含 PARTY/TRAIL/Exp/PLAYERROLES/毒/背包/"
		+ "场景表/OBJECT 表）与 sdlpal global.c 完全同构；事件表从 %d 字节开始。"
		+ "sdlpal 原版写出 %d 字节（5077 事件），本移植写出 %d 字节（5500 槽）。"
		+ "nPartyMember 字段 = 最大下标（已对齐 sdlpal）。"
		+ "文件名不同（原版 1.rpg..5.rpg，本移植 user://pal_save_N.sav），二进制可互换。") % [
		COMMON_PREFIX_SIZE, COMMON_PREFIX_SIZE, SDLPAL_FILE_SIZE, GODOT_FILE_SIZE]


# ---------------------------------------------------------------- 内部
static func _words(bytes: PackedByteArray) -> PackedInt32Array:
	var n := bytes.size() / 2
	var w := PackedInt32Array()
	w.resize(n)
	for i in range(n):
		w[i] = bytes[i * 2] | (bytes[i * 2 + 1] << 8)
	return w
