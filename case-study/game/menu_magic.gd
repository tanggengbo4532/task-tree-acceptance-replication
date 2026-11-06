extends RefCounted
## 仙术菜单（sdlpal uigame.c PAL_InGameMagicMenu + magicmenu.c PAL_MagicSelectionMenu）。
##
## MagicController      —— 选择施法角色（原版：队伍多人时先选人，1 人时直接进仙术列表）
## MagicListController  —— 仙术列表（3 列 × 5 行，MP 检查，描述脚本）
## MagicTargetController—— 选择施法对象（原版：底部角色信息框 + 上箭头光标）
##
## MP/可用性判断对齐 magicmenu.c PAL_MagicSelectionMenuInit：
##   enabled = (magic_def.wCostMP <= 角色当前MP) && (magic.flags & kMagicFlagUsableOutsideBattle)

const ITEMS_PER_LINE := 3       # 32 / dwWordLength(10)
const LINES_PER_PAGE := 5       # 5 - ExtraMagicDescLines(0)
const CELL_W := 87              # 8*dwWordLength + 7
const CURSOR_X := 25            # dwWordLength*5/2
const PAGE_LINE_OFFSET := 2     # iLinesPerPage/2

const COL_ITEM := 0x4F
const COL_INACTIVE := 0x18
const COL_SELECTED := 0xF9
const COL_SEL_INACTIVE := 0x1C
const COL_DESC := 0x3C
const COL_CONFIRMED := 0x2C

const MAGIC_FLAG_OUTSIDE_BATTLE := 0x01
const MAGIC_FLAG_IN_BATTLE := 0x02
const MAGIC_FLAG_APPLY_TO_ALL := 0x10


# =====================================================================
#  施法角色选择（uigame.c PAL_InGameMagicMenu 上半段）
# =====================================================================
class MagicController extends RefCounted:
	var menu = null
	var index: int = 0

	func setup(p_menu) -> void:
		menu = p_menu

	func build() -> void:
		var kit = menu.kit
		var roles: Array = menu.party_roles()
		kit.dim(0.32)
		# 底部角色信息框（PAL_PlayerInfoBox((45+78i,165), role, 100, ...)）
		for i in range(roles.size()):
			var role: int = int(roles[i])
			kit.player_info_box(45 + 78 * i, 165, role,
				int(menu.role_value("hp", role)), int(menu.role_value("max_hp", role)),
				int(menu.role_value("mp", role)), int(menu.role_value("max_mp", role)))
		# 角色名选择框 PAL_CreateBox((35,62), maxIndex, MenuTextMaxWidth-1, 0)
		var cols: int = maxi(0, _max_width(roles) - 1)
		kit.box(35, 62, maxi(roles.size() - 1, 0), cols, 0, 6)
		for i in range(roles.size()):
			var c: Color = kit.col(COL_SELECTED if i == index else COL_ITEM)
			kit.text(menu.player_name(int(roles[i])), 48, 75 + 18 * i, c, 26)
		kit.text("选择施法者   Esc 返回", 40, 46, kit.col(COL_ITEM), 18)

	func _max_width(roles: Array[int]) -> int:
		var r := 0
		for role in roles:
			var t: String = menu.player_name(role)
			var n: int = 0
			for ch in t:
				n += 2 if ch.unicode_at(0) > 0x7F else 1
			r = maxi(r, (n * 8 + 8) >> 4)
		return maxi(r, 1)

	func handle(key: int) -> bool:
		var roles: Array = menu.party_roles()
		match key:
			KEY_UP, KEY_LEFT:
				index = (index + roles.size() - 1) % roles.size()
				return true
			KEY_DOWN, KEY_RIGHT:
				index = (index + 1) % roles.size()
				return true
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				menu.push_controller(menu.make_magic_list(int(roles[index])))
				return true
		return false


# =====================================================================
#  仙术列表（magicmenu.c PAL_MagicSelectionMenuUpdate）
# =====================================================================
class MagicListController extends RefCounted:
	var menu = null
	var role: int = 0
	var index: int = 0
	var _list: Array = []

	func setup(p_menu) -> void:
		menu = p_menu

	func _magics() -> Array:
		_list = []
		if PALState == null:
			return _list
		var ids: Array = PALState.player_magics(role)
		ids.sort()
		for mid in ids:
			var cost: int = menu.magic_cost(int(mid))
			var flags := int(menu.magic_obj_of(int(mid))["flags"])
			var enabled: bool = cost <= int(menu.role_value("mp", role)) and (flags & MAGIC_FLAG_OUTSIDE_BATTLE) != 0
			_list.append({"magic": int(mid), "cost": cost, "enabled": enabled})
		if index >= _list.size():
			index = maxi(0, _list.size() - 1)
		return _list

	func build() -> void:
		var kit = menu.kit
		var list := _magics()
		kit.dim(0.32)
		# 仙术框 PAL_CreateBoxWithShadow((10,42), iLinesPerPage-1, 16, 1, FALSE, 0)
		kit.box(10, 42, LINES_PER_PAGE - 1, 16, 1, 0)
		# MP 框 PAL_CreateSingleLineBox((0,0), 5)
		kit.line_box(0, 0, 5, 6)
		kit.image(menu.ui.frame(39), 45, 14)      # SPRITENUM_SLASH
		var cur_magic := 0
		var cur_cost := 0
		if list.size() > 0:
			cur_magic = int(list[index]["magic"])
			cur_cost = int(list[index]["cost"])
		kit.num_yellow(cur_cost, 4, 15, 14)        # 需要 MP（MagicMPNeededPos）
		kit.num_cyan(int(menu.role_value("mp", role)), 4, 50, 14)  # 当前 MP
		# 描述（脚本 0xFFFF 文本序列）
		if cur_magic != 0:
			var desc: PackedStringArray = menu.magic_desc_lines(cur_magic)
			var dy := 3
			for line in desc:
				kit.text(line, 102, dy, kit.col(COL_DESC), 18)
				dy += 15
		# 列表
		var start: int = (index / ITEMS_PER_LINE) * ITEMS_PER_LINE - ITEMS_PER_LINE * PAGE_LINE_OFFSET
		start = maxi(start, 0)
		for j in range(LINES_PER_PAGE):
			for k in range(ITEMS_PER_LINE):
				var i: int = start + j * ITEMS_PER_LINE + k
				if i >= list.size():
					break
				var e: Dictionary = list[i]
				var c: Color = kit.col(COL_ITEM)
				if i == index:
					c = kit.col(COL_SELECTED if bool(e["enabled"]) else COL_SEL_INACTIVE)
				elif not bool(e["enabled"]):
					c = kit.col(COL_INACTIVE)
				kit.text(menu.item_name(int(e["magic"])), 35 + k * CELL_W, 54 + j * 18, c, 24)
				if i == index:
					kit.cursor(35 + CURSOR_X + k * CELL_W, 64 + j * 18)
		# 底部队伍信息框（magicmenu.c 在列表下方回调 PAL_PlayerInfoBox）
		var roles: Array = menu.party_roles()
		for i in range(roles.size()):
			var r: int = int(roles[i])
			kit.player_info_box(45 + 78 * i, 165, r,
				int(menu.role_value("hp", r)), int(menu.role_value("max_hp", r)),
				int(menu.role_value("mp", r)), int(menu.role_value("max_mp", r)))
		# 角色名 + 提示
		kit.text(menu.player_name(role), 250, 6, kit.col(COL_CONFIRMED), 20)
		kit.text("↑↓←→ 选择  回车确定  Esc 返回", 10, 186, kit.col(COL_ITEM), 16)

	func handle(key: int) -> bool:
		var list := _magics()
		if list.is_empty():
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
				index = list.size() - 1
				return true
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				var e: Dictionary = list[index]
				if not bool(e["enabled"]):
					menu.toast("MP 不足或战斗外不可用")
					return true
				var magic := int(e["magic"])
				var flags := int(menu.magic_obj_of(magic)["flags"])
				if (flags & MAGIC_FLAG_APPLY_TO_ALL) != 0:
					menu.use_magic(role, magic, -1)
				else:
					menu.push_controller(menu.make_magic_target(role, magic))
				return true
		if delta != 0:
			index = clampi(index + delta, 0, list.size() - 1)
			return true
		return false


# =====================================================================
#  施法对象（uigame.c PAL_InGameMagicMenu 下半段）
# =====================================================================
class MagicTargetController extends RefCounted:
	var menu = null
	var role: int = 0
	var magic: int = 0
	var index: int = 0

	func setup(p_menu) -> void:
		menu = p_menu

	func build() -> void:
		var kit = menu.kit
		var roles: Array = menu.party_roles()
		if index >= roles.size():
			index = 0
		kit.dim(0.35)
		for i in range(roles.size()):
			var r: int = int(roles[i])
			kit.player_info_box(45 + 78 * i, 165, r,
				int(menu.role_value("hp", r)), int(menu.role_value("max_hp", r)),
				int(menu.role_value("mp", r)), int(menu.role_value("max_mp", r)))
		# 上箭头光标（SPRITENUM_CURSOR_UP），原版 (75+78*wPlayer, 158)
		if index < roles.size():
			kit.image(menu.ui.frame(67), 75 + 78 * index, 158)
		kit.line_box(0, 40, 7, 6)
		kit.text("「%s」用于：" % menu.item_name(magic), 14, 50, kit.col(COL_CONFIRMED), 22)
		kit.text("←→ 选择对象   回车确定   Esc 返回", 14, 70, kit.col(COL_ITEM), 16)
		if index < roles.size():
			kit.text(menu.player_name(int(roles[index])), 14, 96, kit.col(COL_SELECTED), 22)

	func handle(key: int) -> bool:
		var roles: Array = menu.party_roles()
		if roles.is_empty():
			return false
		match key:
			KEY_LEFT, KEY_UP:
				index = (index + roles.size() - 1) % roles.size()
				return true
			KEY_RIGHT, KEY_DOWN:
				index = (index + 1) % roles.size()
				return true
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				menu.use_magic(role, magic, int(roles[index]))
				menu.pop_controller()
				return true
		return false
