extends RefCounted
## 装备界面（sdlpal uigame.c PAL_EquipItemMenu）。
##
## 背景 = FBP.MKF #1（EQUIPMENU_BACKGROUND_FBPNUM，已烘入“頭戴/披掛/身穿/手持/腳穿/配帶”
## 与五项属性标签）；在其上绘制：
##   * 待装备物品图标（BALL.MKF，位图号 = item.wBitmap）
##   * 当前所选角色的 6 件装备名 + 五项属性
##   * 角色名列表（按 item.wFlags 的 kItemFlagEquipableByPlayerRole_First<<role 决定可选性）
##   * 物品名/数量
##
## 确认后：若脚本 VM 尚未实现 0x0018（换装）操作码，则用脚本参数做最小兼容换装
## （见 PalMenu.equip_item / _equip_fallback，[inf]），随后 PALState.update_equipments()
## 重算装备效果。

const COL_ITEM := 0x4F
const COL_INACTIVE := 0x18
const COL_CONFIRMED := 0x2C
const COL_SEL_INACTIVE := 0x1C
const COL_CYAN := 0xF9
const COL_EQUIP := 0xBE

# palcfg.c 默认布局（逻辑坐标）
const EQUIP_IMAGE_BOX := Vector2i(8, 8)
const EQUIP_ROLE_LIST_BOX := Vector2i(2, 95)
const EQUIP_ITEM_NAME := Vector2i(5, 70)
const EQUIP_ITEM_AMOUNT := Vector2i(51, 57)
const EQUIP_LABELS := [
	Vector2i(92, 11), Vector2i(92, 33), Vector2i(92, 55),
	Vector2i(92, 77), Vector2i(92, 99), Vector2i(92, 121),
]
const EQUIP_NAMES := [
	Vector2i(130, 11), Vector2i(130, 33), Vector2i(130, 55),
	Vector2i(130, 77), Vector2i(130, 99), Vector2i(130, 121),
]
const EQUIP_STATUS_LABELS := [
	Vector2i(226, 10), Vector2i(226, 32), Vector2i(226, 54),
	Vector2i(226, 76), Vector2i(226, 98),
]
const EQUIP_STATUS_VALUES := [
	Vector2i(260, 14), Vector2i(260, 36), Vector2i(260, 58),
	Vector2i(260, 80), Vector2i(260, 102),
]

const FLAG_EQUIPABLE_BY_ROLE := 0x40


class EquipItemController extends RefCounted:
	var menu = null
	var item_id: int = 0
	var index: int = 0

	func setup(p_menu) -> void:
		menu = p_menu

	func build() -> void:
		# R105-EQUIPUI-1：不再依赖 FBP #1 背景（实机全红格且文字不可见）；改为自绘高对比面板，
		# 角色/六部位装备/五项属性/物品名/效果说明全部显式绘制，保证任何调色板下可见。
		var kit = menu.kit
		var roles: Array = menu.party_roles()
		kit.dim(0.62)
		if roles.is_empty():
			kit.text("队伍为空", 130, 96, Color(1, 1, 1), 22)
			return
		index = clampi(index, 0, roles.size() - 1)
		var role: int = int(roles[index])
		kit.text("装备", 8, 3, Color(1, 1, 0.6), 18)
		# 角色列表（可选角色按 flags 高亮/灰色）
		var flags := int(menu.item_of(item_id)["flags"])
		for i in range(roles.size()):
			var r: int = int(roles[i])
			var can := (flags & (FLAG_EQUIPABLE_BY_ROLE << r)) != 0
			var c := Color(0.75, 0.75, 0.75)
			if i == index:
				c = Color(1, 1, 0.3) if can else Color(0.7, 0.5, 0.5)
			elif can:
				c = Color(0.95, 0.95, 0.95)
			kit.text(menu.player_name(r), 8, 24 + 17 * i, c, 17)
		# 六部位已装备（真实装备名）
		var part_names := ["头戴", "披挂", "身穿", "手持", "脚穿", "配带"]
		kit.text("当前装备", 74, 3, Color(0.8, 1, 0.8), 15)
		for p in range(6):
			var it: int = menu.equipment_of(role, p)
			var nm := "—"
			if it != 0:
				nm = menu.item_name(it)
			kit.text("%s：%s" % [part_names[p], nm], 74, 22 + 17 * p, Color(1, 1, 0.85), 14, 240)
		# 五项属性（当前总值）
		var stats := [
			menu.get_attack(role), menu.get_magic_strength(role), menu.get_defense(role),
			menu.get_dexterity(role), menu.get_flee(role),
		]
		kit.text("武%d 灵%d 防%d 身%d 吉%d" % [
			int(stats[0]), int(stats[1]), int(stats[2]), int(stats[3]), int(stats[4])],
			74, 126, Color(0.7, 1, 1), 14, 240)
		# 待装备物品名 + 数量 + 具体效果（Data#5 script_on_equip + flags）
		if item_id != 0:
			kit.text("待装备：%s  x%d" % [menu.item_name(item_id), menu.item_amount(item_id)],
				8, 132, Color(1, 1, 0.45), 15, 300)
			if PALTables != null and PALTables.has_method("item_equip_effect_text"):
				var eq := str(PALTables.call("item_equip_effect_text", item_id))
				if eq != "":
					kit.text(eq, 8, 151, Color(0.7, 1, 0.7), 12, 304)
		kit.text("↑↓ 选择角色   回车装备   Esc 返回", 8, 186, Color(1, 1, 1), 14, 304)

	func _role_name_width() -> int:
		var r := 0
		for w in [36, 37, 38, 39]:
			var t: String = menu.word(int(w))
			var n: int = 0
			for ch in t:
				n += 2 if ch.unicode_at(0) > 0x7F else 1
			r = maxi(r, (n * 8 + 8) >> 4)
		return maxi(r, 1)

	func handle(key: int) -> bool:
		var roles: Array = menu.party_roles()
		if roles.is_empty():
			return false
		match key:
			KEY_UP, KEY_LEFT:
				index = (index + roles.size() - 1) % roles.size()
				return true
			KEY_DOWN, KEY_RIGHT:
				index = (index + 1) % roles.size()
				return true
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				var role: int = int(roles[index])
				var flags := int(menu.item_of(item_id)["flags"])
				if (flags & (FLAG_EQUIPABLE_BY_ROLE << role)) == 0:
					menu.toast("%s 无法装备该物品" % menu.player_name(role))
					return true
				menu.equip_item(item_id, role)
				menu.pop_controller()
				return true
		return false
