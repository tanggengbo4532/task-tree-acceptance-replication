extends RefCounted
## 物品菜单（sdlpal itemmenu.c + uigame.c PAL_InventoryMenu / PAL_ItemUseMenu / play.c）。
##
## 三个控制器：
##   InventoryMenu        —— 物品 → 装备 / 使用 二级选择（uigame.c PAL_InventoryMenu）
##   ItemSelectController —— 物品选择列表（itemmenu.c PAL_ItemSelectMenu）
##   ItemUseTargetController —— 使用对象选择（uigame.c PAL_ItemUseMenu）
##
## 布局全部使用原版 320×200 逻辑坐标；绘制由菜单的 UiKit 完成。
## 说明：WIN95 版物品描述来自 item.wScriptDesc 的自动脚本（0xFFFF 文本序列），
##       本移植直接线性抽取消息文本（见 PalMenu._script_desc_lines，[observation]）。

const ITEMS_PER_LINE := 3      # 32 / dwWordLength(10) = 3
const LINES_PER_PAGE := 7      # 7 - ExtraItemDescLines(0)
const CELL_W := 100            # 8*dwWordLength + 20
const CURSOR_X := 25           # dwWordLength*5/2
const AMOUNT_X := 81           # dwWordLength*8 + 1
const PAGE_LINE_OFFSET := 4    # (LINES_PER_PAGE+1)/2

# 调色板索引（sdlpal ui.h）
const COL_ITEM := 0x4F
const COL_INACTIVE := 0x18
const COL_SELECTED := 0xF9
const COL_SEL_INACTIVE := 0x1C
const COL_EQUIPED := 0xC8
const COL_DESC := 0x3C
const COL_EQUIP_TEXT := 0xBE
const COL_LABEL := 0xBB

# 物品 flags（global.h tagITEMFLAG）
const FLAG_USABLE := 0x01
const FLAG_EQUIPABLE := 0x02
const FLAG_THROWABLE := 0x04
const FLAG_CONSUMING := 0x08
const FLAG_APPLY_TO_ALL := 0x10
const FLAG_SELLABLE := 0x20

const LABEL_EQUIP := 22
const LABEL_USE := 23


# =====================================================================
#  物品二级菜单：装备 / 使用（uigame.c PAL_InventoryMenu）
# =====================================================================
class InventoryMenu extends RefCounted:
	var menu = null
	var index: int = 0

	func setup(p_menu) -> void:
		menu = p_menu

	func build() -> void:
		var kit = menu.kit
		kit.dim(0.30)
		# PAL_CreateBox((30,60), 1, MenuTextMaxWidth-1, 0)：两条词条各 2 字 → cols=1
		kit.box(30, 60, 1, 1, 0, 6)
		var labels := [LABEL_EQUIP, LABEL_USE]
		for i in range(2):
			var c: Color = kit.col(COL_SELECTED if i == index else COL_ITEM)
			kit.text(menu.word(labels[i]), 43, 73 + 18 * i, c, 26)

	func handle(key: int) -> bool:
		match key:
			KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT:
				index = 1 - index
				return true
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				var c = menu.make_item_select(FLAG_EQUIPABLE if index == 0 else FLAG_USABLE)
				menu.push_controller(c)
				return true
		return false


# =====================================================================
#  物品选择列表（itemmenu.c PAL_ItemSelectMenu）
# =====================================================================
class ItemSelectController extends RefCounted:
	var menu = null
	var item_flags: int = FLAG_USABLE
	var index: int = 0
	var _list: Array = []

	func setup(p_menu) -> void:
		menu = p_menu

	func _items() -> Array:
		_list = menu.selectable_items(item_flags)
		if index >= _list.size():
			index = maxi(0, _list.size() - 1)
		return _list

	func build() -> void:
		var kit = menu.kit
		var items := _items()
		kit.dim(0.30)
		# PAL_CreateBoxWithShadow((2,0), iLinesPerPage-1, 17, 1, FALSE, 0)
		kit.box(2, 0, LINES_PER_PAGE - 1, 17, 1, 0)
		var start: int = (index / ITEMS_PER_LINE) * ITEMS_PER_LINE - ITEMS_PER_LINE * PAGE_LINE_OFFSET
		start = maxi(start, 0)
		_draw_grid(kit, items, start)
		# 当前选中物品的图 + 描述（xBase=0, yBase=140）
		if items.size() > 0 and index >= 0 and index < items.size():
			var item_id: int = int(items[index]["item"])
			kit.image(menu.ui.frame(70), 0, 140)          # SPRITENUM_ITEMBOX
			var bitmap := int(menu.item_of(item_id)["bitmap"])
			if bitmap > 0:
				kit.icon(bitmap, 8, 147)
			var desc: PackedStringArray = menu.item_desc_lines(item_id)
			var y: int = 150
			var shown := 0
			for line in desc:
				if y > 190:
					break
				kit.text(line, 75, y, kit.col(COL_DESC), 18)
				y += 15
				shown += 1
			# 价格（原版描述脚本里通常已含效果；价格作为补充信息 [inf]，避免与末行重叠）
			var price: int = int(menu.item_of(item_id)["price"])
			if price > 0 and shown < 3:
				kit.text("价格 %d 文" % price, 75, y + 4, kit.col(COL_INACTIVE), 16)

	func _draw_grid(kit, items: Array, start: int) -> void:
		for j in range(LINES_PER_PAGE):
			for k in range(ITEMS_PER_LINE):
				var i: int = start + j * ITEMS_PER_LINE + k
				if i >= items.size():
					return
				var e: Dictionary = items[i]
				var item_id := int(e["item"])
				var amount := int(e["amount"])
				var in_use := int(e["in_use"])
				var c: Color = kit.col(COL_ITEM)
				if i == index:
					c = kit.col(COL_SELECTED)
				elif amount == 0:
					c = kit.col(COL_EQUIPED)   # 已装备的可用物品
				var lx: int = 15 + k * CELL_W
				var ly: int = 12 + j * 18
				kit.text(menu.item_name(item_id), lx, ly, c, 24, CELL_W - 6)
				var avail: int = amount - in_use if in_use != 0xFFFF else 0
				if avail > 1:
					kit.num_cyan(avail, 2, 15 + AMOUNT_X + k * CELL_W, 17 + j * 18)
				if i == index:
					kit.cursor(15 + CURSOR_X + k * CELL_W, 22 + j * 18)

	## 自测/调试：按物品 id 定位光标，返回列表下标（-1 = 不在列表）
	func find_item(item_id: int) -> int:
		var items := _items()
		for i in range(items.size()):
			if int(items[i]["item"]) == item_id:
				index = i
				return i
		return -1

	func handle(key: int) -> bool:
		var items := _items()
		if items.is_empty():
			return false
		var delta := 0
		match key:
			KEY_UP:
				delta = -ITEMS_PER_LINE
			KEY_DOWN:
				delta = ITEMS_PER_LINE
			KEY_LEFT:
				delta = -1
			KEY_RIGHT:
				delta = 1
			KEY_PAGEUP:
				delta = -(ITEMS_PER_LINE * LINES_PER_PAGE)
			KEY_PAGEDOWN:
				delta = ITEMS_PER_LINE * LINES_PER_PAGE
			KEY_HOME:
				index = 0
				return true
			KEY_END:
				index = items.size() - 1
				return true
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				_confirm(items)
				return true
		if delta != 0:
			index = clampi(index + delta, 0, items.size() - 1)
			return true
		return false

	func _confirm(items: Array) -> void:
		var e: Dictionary = items[index]
		var item_id := int(e["item"])
		var flags := int(menu.item_of(item_id)["flags"])
		if (item_flags & FLAG_USABLE) != 0:
			if (flags & FLAG_APPLY_TO_ALL) != 0:
				menu.use_item(item_id, -1)
			else:
				menu.push_controller(menu.make_item_use_target(item_id))
		elif (item_flags & FLAG_EQUIPABLE) != 0:
			menu.push_equip_item(item_id)


# =====================================================================
#  使用对象选择（uigame.c PAL_ItemUseMenu）
# =====================================================================
class ItemUseTargetController extends RefCounted:
	# STATUS_LABEL_* 词条号（ui.h）
	const LABELS := [48, 49, 50, 51, 52, 53, 54, 55]

	var menu = null
	var item_id: int = 0
	var index: int = 0

	func setup(p_menu) -> void:
		menu = p_menu

	func build() -> void:
		var kit = menu.kit
		kit.dim(0.35)
		# PAL_CreateBox((110,2), 7, 9, 0, FALSE)
		kit.box(110, 2, 7, 9, 0, 6)
		var roles: Array = menu.party_roles()
		if index >= roles.size():
			index = 0
		var role: int = roles[index]
		# 左侧状态标签
		for i in range(8):
			kit.text(menu.word(LABELS[i]), 200, 16 + 18 * i, kit.col(COL_LABEL), 20)
		# 数值（uigame.c PAL_ItemUseMenu 的坐标）
		kit.num_yellow(menu.role_value("level", role), 4, 240, 20)
		kit.image(menu.ui.frame(39), 263, 38)
		kit.num_blue(menu.role_value("max_hp", role), 4, 261, 40)
		kit.num_yellow(menu.role_value("hp", role), 4, 240, 37)
		kit.image(menu.ui.frame(39), 263, 56)
		kit.num_blue(menu.role_value("max_mp", role), 4, 261, 58)
		kit.num_yellow(menu.role_value("mp", role), 4, 240, 55)
		kit.num_yellow(menu.get_attack(role), 4, 240, 74)
		kit.num_yellow(menu.get_magic_strength(role), 4, 240, 92)
		kit.num_yellow(menu.get_defense(role), 4, 240, 110)
		kit.num_yellow(menu.get_dexterity(role), 4, 240, 128)
		kit.num_yellow(menu.get_flee(role), 4, 240, 146)
		# 队员名字
		for i in range(roles.size()):
			var c: Color = kit.col(COL_SELECTED if i == index else COL_ITEM)
			kit.text(menu.player_name(int(roles[i])), 125, 16 + 20 * i, c, 24)
		# 物品图标/名字/数量
		kit.image(menu.ui.frame(70), 120, 80)
		var bitmap := int(menu.item_of(item_id)["bitmap"])
		if bitmap > 0:
			kit.icon(bitmap, 127, 88)
		var amount: int = menu.item_amount(item_id)
		if amount > 0:
			kit.text(menu.item_name(item_id), 116, 143, kit.col(COL_EQUIP_TEXT), 20)
			kit.num_cyan(amount, 2, 170, 133)
		kit.text("↑↓ 选择对象  回车确定  Esc 返回", 120, 170, kit.col(COL_ITEM), 18)
		if amount <= 0:
			kit.text("（该物品已用完）", 120, 188, kit.col(COL_INACTIVE), 18)

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
				if menu.item_amount(item_id) > 0:
					var target: int = int(roles[index])
					menu.use_item(item_id, target)
					menu.pop_controller()
				else:
					menu.toast("该物品已用完")
				return true
		return false
