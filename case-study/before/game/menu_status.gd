extends RefCounted
## 角色状态页（sdlpal uigame.c PAL_PlayerStatus）。
##
## 背景 = FBP.MKF #0（STATUS_BACKGROUND_FBPNUM，背景里已烘入“頭戴/披掛/…/吉運”等
## 繁体标签）；本移植在其上绘制：头像、名字、经验/等级/HP/MP、五项属性、六件装备、
## 毒状态。坐标取自 palcfg.c 默认 SCREENLAYOUT（sdlpal 默认 fUseCustomScreenLayout=FALSE，
## 但数值/头像仍按该布局绘制）。
##
## 导航：←↑ 上一个角色，→↓/回车 下一个角色，越界即退出（对齐原版行为）。

# 调色板索引
const COL_ITEM := 0x4F
const COL_CONFIRMED := 0x2C
const COL_EQUIP := 0xBE

# 词条号（ui.h / Word.dat）
const LABEL_EXP := 2
const LABEL_LEVEL := 48
const LABEL_HP := 49
const LABEL_MP := 50
const LABEL_ATTACK := 51
const LABEL_MAGIC := 52
const LABEL_DEFENSE := 53
const LABEL_DEXTERITY := 54
const LABEL_FLEE := 55

# palcfg.c 默认布局（逻辑坐标）
const ROLE_NAME := Vector2i(110, 8)
const ROLE_IMAGE := Vector2i(110, 30)
const ROLE_CURR_EXP := Vector2i(58, 6)
const ROLE_NEXT_EXP := Vector2i(58, 15)
const ROLE_LEVEL := Vector2i(54, 35)
const ROLE_CUR_HP := Vector2i(42, 56)
const ROLE_MAX_HP := Vector2i(63, 61)
const ROLE_HP_SLASH := Vector2i(65, 58)
const ROLE_CUR_MP := Vector2i(42, 78)
const ROLE_MAX_MP := Vector2i(63, 83)
const ROLE_MP_SLASH := Vector2i(65, 80)
const ROLE_STATUS_VALUES := [
	Vector2i(42, 102), Vector2i(42, 122), Vector2i(42, 142),
	Vector2i(42, 162), Vector2i(42, 182),
]
const ROLE_EQUIP_IMAGE_BOXES := [
	Vector2i(189, -1), Vector2i(247, 39), Vector2i(251, 101),
	Vector2i(201, 133), Vector2i(141, 141), Vector2i(81, 125),
]
const ROLE_EQUIP_NAMES := [
	Vector2i(195, 38), Vector2i(253, 78), Vector2i(257, 140),
	Vector2i(207, 172), Vector2i(147, 180), Vector2i(87, 164),
]
const ROLE_POISON_NAMES := [
	Vector2i(185, 58), Vector2i(185, 76), Vector2i(185, 94), Vector2i(185, 112),
	Vector2i(185, 130), Vector2i(185, 148), Vector2i(185, 166), Vector2i(185, 184),
	Vector2i(185, 184), Vector2i(185, 184),
]


class StatusController extends RefCounted:
	var menu = null
	var index: int = 0

	func setup(p_menu) -> void:
		menu = p_menu

	func build() -> void:
		var kit = menu.kit
		var roles: Array = menu.party_roles()
		if roles.is_empty():
			kit.dim(0.6)
			kit.text("队伍为空", 130, 96, kit.col(COL_ITEM), 26)
			return
		index = clampi(index, 0, roles.size() - 1)
		var role: int = int(roles[index])
		# 背景（FBP #0 = 状态页）
		kit.bg_fbp(0)
		# 头像
		var avatar := int(menu.role_value("avatar", role))
		if avatar > 0:
			kit.avatar_img(avatar, ROLE_IMAGE.x, ROLE_IMAGE.y)
		# 名字
		kit.text(menu.player_name(role), ROLE_NAME.x, ROLE_NAME.y, kit.col(COL_CONFIRMED), 28)
		# 标签（uigame.c PAL_PlayerStatus：labels0 画在 RoleExp/Level/HP/MP Label 位置，
		# 五项属性标签画在 RoleStatusLabels；WIN95 背景 FBP#0 并未烘入文字，必须自绘）
		var labels0 := [LABEL_EXP, LABEL_LEVEL, LABEL_HP, LABEL_MP]
		var label_pos0 := [
			Vector2i(6, 6), Vector2i(6, 32), Vector2i(6, 54), Vector2i(6, 76),
		]
		for i in range(4):
			kit.text(menu.word(labels0[i]), label_pos0[i].x, label_pos0[i].y, kit.col(COL_ITEM), 22)
		var labels1 := [LABEL_ATTACK, LABEL_MAGIC, LABEL_DEFENSE, LABEL_DEXTERITY, LABEL_FLEE]
		var label_pos1 := [98, 118, 138, 158, 178]
		for i in range(5):
			kit.text(menu.word(labels1[i]), 6, label_pos1[i], kit.col(COL_ITEM), 22)
		# 经验（当前/升级所需）
		var exp_cur := 0
		if PALState != null and PALState.exp.has("primary"):
			exp_cur = int(PALState.exp["primary"][role]["exp"])
		kit.num_yellow(exp_cur, 5, ROLE_CURR_EXP.x, ROLE_CURR_EXP.y)
		var lv := int(menu.role_value("level", role))
		var exp_next := 0
		if PALTables != null and lv >= 0 and lv < PALTables.level_up_exp.size():
			exp_next = int(PALTables.level_up_exp[lv])
		kit.num_cyan(exp_next, 5, ROLE_NEXT_EXP.x, ROLE_NEXT_EXP.y)
		kit.num_yellow(lv, 2, ROLE_LEVEL.x, ROLE_LEVEL.y)
		# HP / MP
		kit.image(menu.ui.frame(39), ROLE_HP_SLASH.x, ROLE_HP_SLASH.y)
		kit.num_yellow(int(menu.role_value("hp", role)), 4, ROLE_CUR_HP.x, ROLE_CUR_HP.y)
		kit.num_blue(int(menu.role_value("max_hp", role)), 4, ROLE_MAX_HP.x, ROLE_MAX_HP.y)
		kit.image(menu.ui.frame(39), ROLE_MP_SLASH.x, ROLE_MP_SLASH.y)
		kit.num_yellow(int(menu.role_value("mp", role)), 4, ROLE_CUR_MP.x, ROLE_CUR_MP.y)
		kit.num_blue(int(menu.role_value("max_mp", role)), 4, ROLE_MAX_MP.x, ROLE_MAX_MP.y)
		# 五项属性
		var stats := [
			menu.get_attack(role), menu.get_magic_strength(role), menu.get_defense(role),
			menu.get_dexterity(role), menu.get_flee(role),
		]
		for i in range(5):
			kit.num_yellow(int(stats[i]), 4, ROLE_STATUS_VALUES[i].x, ROLE_STATUS_VALUES[i].y)
		# 六件装备：图标 + 名称
		for part in range(6):
			var item: int = menu.equipment_of(role, part)
			if item == 0:
				continue
			var box: Vector2i = ROLE_EQUIP_IMAGE_BOXES[part]
			var bitmap := int(menu.item_of(item)["bitmap"])
			if bitmap > 0:
				kit.icon(bitmap, box.x + 1, box.y + 1)
			var pos: Vector2i = ROLE_EQUIP_NAMES[part]
			var name: String = menu.item_name(item)
			# 右越界时左移（对齐 sdlpal 的 offset 处理）
			var w: int = name.length() * 16
			var ox := 0
			if pos.x + w > 320:
				ox = 320 - pos.x - w
			kit.text(name, pos.x + ox, pos.y, kit.col(COL_EQUIP), 20)
		# 毒状态（最多 10 行；PALState 按 role 下标存放，兼查 party 下标 [inf]）
		var poisons := _poison_list(index, role)
		for j in range(poisons.size()):
			var p: Dictionary = poisons[j]
			var pos2: Vector2i = ROLE_POISON_NAMES[mini(j, ROLE_POISON_NAMES.size() - 1)]
			kit.text(menu.word(int(p["poison_id"])), pos2.x, pos2.y, kit.col(int(p["color"])), 20)
		# 提示
		kit.text("←→ 切换角色    Esc 返回", 8, 190, kit.col(COL_ITEM), 16)
		kit.text("%d / %d" % [index + 1, roles.size()], 290, 190, kit.col(COL_ITEM), 16)

	## 收集毒：[{poison_id,color}]；PALState.poison_status 第二维在移植里按 role 存，
	## 原版按队伍下标存（PAL_AddPoisonForPlayer 内部做 role→party 转换），这里两者都查 [inf]。
	func _poison_list(party_index: int, role: int) -> Array:
		var out: Array = []
		if PALState == null:
			return out
		for i in range(16):
			var entry: Dictionary = {}
			if i < PALState.poison_status.size():
				var row: Array = PALState.poison_status[i]
				if role < row.size():
					entry = row[role]
				if int(entry.get("poison_id", 0)) == 0 and party_index < row.size():
					entry = row[party_index]
			var pid := int(entry.get("poison_id", 0))
			if pid == 0:
				continue
			var info: Dictionary = menu.poison_of(pid)
			if int(info.get("poison_level", 0)) > 3:
				continue
			out.append({"poison_id": pid, "color": 10 + int(info.get("color", 0))})
		return out

	func handle(key: int) -> bool:
		var roles: Array = menu.party_roles()
		match key:
			KEY_LEFT, KEY_UP:
				index -= 1
				if index < 0:
					menu.pop_controller()
				return true
			KEY_RIGHT, KEY_DOWN, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				index += 1
				if index >= roles.size():
					menu.pop_controller()
				return true
		return false
