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
		var kit = menu.kit
		var roles: Array = menu.party_roles()
		if roles.is_empty():
			kit.dim(0.6)
			kit.text("队伍为空", 130, 96, kit.col(COL_ITEM), 26)
			return
		index = clampi(index, 0, roles.size() - 1)
		var role: int = int(roles[index])
		kit.bg_fbp(1)
		# 待装备物品图标
		var bitmap := int(menu.item_of(item_id)["bitmap"])
		if item_id != 0 and bitmap > 0:
			kit.icon(bitmap, EQUIP_IMAGE_BOX.x + 8, EQUIP_IMAGE_BOX.y + 8)
		# 当前装备名 + 五项属性
		for part in range(6):
			var it: int = menu.equipment_of(role, part)
			if it != 0:
				kit.text(menu.item_name(it), EQUIP_NAMES[part].x, EQUIP_NAMES[part].y, kit.col(COL_ITEM), 20)
		var stats := [
			menu.get_attack(role), menu.get_magic_strength(role), menu.get_defense(role),
			menu.get_dexterity(role), menu.get_flee(role),
		]
		for i in range(5):
			kit.num_cyan(int(stats[i]), 4, EQUIP_STATUS_VALUES[i].x, EQUIP_STATUS_VALUES[i].y)
		# 角色名列表（PAL_CreateBox(EquipRoleListBox, maxIndex, WordMaxWidth(36,4)-1)）
		var cols: int = maxi(0, _role_name_width() - 1)
		kit.box(EQUIP_ROLE_LIST_BOX.x, EQUIP_ROLE_LIST_BOX.y, maxi(roles.size() - 1, 0), cols, 0, 6)
		var flags := int(menu.item_of(item_id)["flags"])
		for i in range(roles.size()):
			var r: int = int(roles[i])
			var can := (flags & (FLAG_EQUIPABLE_BY_ROLE << r)) != 0
			var c: Color = kit.col(COL_ITEM)
			if i == index:
				c = kit.col(COL_CYAN if can else COL_SEL_INACTIVE)
			elif not can:
				c = kit.col(COL_INACTIVE)
			kit.text(menu.player_name(r), EQUIP_ROLE_LIST_BOX.x + 13,
				EQUIP_ROLE_LIST_BOX.y + 13 + 18 * i, c, 24)
		# 物品名 + 数量
		if item_id != 0:
			kit.text(menu.item_name(item_id), EQUIP_ITEM_NAME.x, EQUIP_ITEM_NAME.y, kit.col(COL_CONFIRMED), 24)
			kit.num_cyan(menu.item_amount(item_id), 2, EQUIP_ITEM_AMOUNT.x, EQUIP_ITEM_AMOUNT.y)
		kit.text("↑↓ 选择角色   回车装备   Esc 返回", 8, 186, kit.col(COL_ITEM), 16)

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
