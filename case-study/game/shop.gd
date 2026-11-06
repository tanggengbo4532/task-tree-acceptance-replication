extends CanvasLayer
## 商店（sdlpal uigame.c PAL_BuyMenu / PAL_SellMenu，脚本操作码 0x0026 买 / 0x0027 卖）。
##
## 由 World 实例化：`shop.gd.new()` → `setup(store_id[, is_buy])` → `closed` 信号。
## 买：
##   * 菜单框 PAL_CreateBox((122,8), 8, 8, 1)
##   * 物品名 (150, 21+18i)、价格 (238, 26+18i)
##   * 物品图标框 (40,8) + 图标 (48,15)
##   * “现有数量”单行框 (20,100)、“金钱”单行框 (20,141)
## 卖：
##   * 可卖物品列表（itemmenu.c PAL_ItemSelectMenu 布局，kItemFlagSellable）
##   * 现金框 (100,150)、售价框 (224,150)，售价 = wPrice/2
## 确认框：ui.c PAL_ConfirmMenu 风格（否 / 是）。
##
## 与 sdlpal 的差异：[inf] sdlpal 的商店买卖是脚本用 0x0026/0x0027 连续调起；
## 本移植允许 `setup(store_id, false)` 直接打开卖出页，价格/金钱校验规则一致。

signal closed

const MAX_STORE_ITEM := 9
const ITEMS_PER_LINE := 3
const LINES_PER_PAGE := 7
const CELL_W := 100
const CURSOR_X := 25
const AMOUNT_X := 81
const PAGE_LINE_OFFSET := 4

# 调色板索引
const COL_ITEM := 0x4F
const COL_INACTIVE := 0x18
const COL_SELECTED := 0xF9
const COL_SEL_INACTIVE := 0x1C
const COL_CONFIRMED := 0x2C
const COL_EQUIP := 0xBE

# 物品 flags
const FLAG_SELLABLE := 0x20

# 词条号
const LABEL_CASH := 21
const LABEL_SELL_PRICE := 25
const LABEL_CURRENT := 35
const LABEL_NO := 19
const LABEL_YES := 20

const SHOT_DIR := "<LOCAL_PATH>"

var store_id: int = 0
var is_buy: bool = true

var _ui: UIAssets = null
var _kit = null
var _root: Control = null
var _closed: bool = false
var _index: int = 0
var _confirming: bool = false
var _confirm_index: int = 0
var _list: Array = []


func setup(p_store_id: int, p_is_buy: bool = true) -> void:
	store_id = p_store_id
	is_buy = p_is_buy


func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["SimSun", "Microsoft YaHei", "SimHei", "Noto Sans CJK SC"])
	_ui = UIAssets.new()
	_ui.init()
	_kit = PalMenu.UiKit.new(_root, _ui, font)
	_refresh()


# ---------------------------------------------------------------- 数据
func word(id: int) -> String:
	return PALTables.word(id).strip_edges() if PALTables != null else ""


func item_of(id: int) -> Dictionary:
	return PALTables.item_of(id) if PALTables != null else {"bitmap": 0, "price": 0, "flags": 0}


func item_name(id: int) -> String:
	return PALTables.item_name(id).strip_edges() if PALTables != null else word(id)


func cash() -> int:
	return int(PALState.cash) if PALState != null else 0


func add_item(id: int, n: int) -> int:
	return PALState.add_item(id, n) if PALState != null else 0


func item_amount(id: int) -> int:
	return PALState.get_item_amount(id) if PALState != null else 0


func _store_list() -> Array:
	_list = []
	if PALTables == null:
		return _list
	var ids := PALTables.store_items(store_id)
	for it in ids:
		if int(it) != 0:
			_list.append(int(it))
	if _index >= _list.size():
		_index = maxi(0, _list.size() - 1)
	return _list


func _sell_list() -> Array:
	_list = []
	if PALState == null:
		return _list
	PALState.compress_inventory()
	for i in range(256):
		var e: Dictionary = PALState.inventory[i]
		var id := int(e["item"])
		if id == 0:
			break
		if (int(item_of(id)["flags"]) & FLAG_SELLABLE) != 0 and int(e["amount"]) > int(e["in_use"]):
			_list.append(id)
	if _index >= _list.size():
		_index = maxi(0, _list.size() - 1)
	return _list


# ---------------------------------------------------------------- 绘制
func _refresh() -> void:
	if _kit == null:
		return
	_kit.clear()
	if is_buy:
		_draw_buy()
	else:
		_draw_sell()
	if _confirming:
		_draw_confirm()
	else:
		_kit.text("Tab 买卖切换   ↑↓选择   空格/回车确定   Esc返回", 110, 2, _kit.col(0x4F), 18)


func _draw_buy() -> void:
	var kit = _kit
	var items := _store_list()
	var cur: int = int(items[_index]) if items.size() > 0 else 0
	kit.dim(0.35)
	# 菜单框
	kit.box(122, 8, 8, 8, 1, 6)
	for i in range(mini(items.size(), MAX_STORE_ITEM)):
		var id: int = int(items[i])
		var c: Color = kit.col(COL_SELECTED if i == _index else COL_ITEM)
		kit.text(item_name(id), 150, 21 + 18 * i, c, 24)
		kit.num_yellow(int(item_of(id)["price"]), 6, 238, 26 + 18 * i)
	# 选中物品图
	if items.size() > 0:
		kit.image(_ui.frame(70), 40, 8)
		var bitmap := int(item_of(cur)["bitmap"])
		if bitmap > 0:
			kit.icon(bitmap, 48, 15)
	# 现有数量
	kit.line_box(20, 100, 5, 6)
	kit.text(word(LABEL_CURRENT), 30, 110, kit.col(0x00), 22)
	kit.num_yellow(item_amount(cur) if cur > 0 else 0, 6, 69, 115)
	# 金钱
	kit.line_box(20, 141, 5, 6)
	kit.text(word(LABEL_CASH), 30, 151, kit.col(0x00), 22)
	kit.num_yellow(cash(), 6, 69, 156)
	_draw_toast()


func _draw_sell() -> void:
	var kit = _kit
	var items := _sell_list()
	kit.dim(0.35)
	# 物品列表（itemmenu.c 布局，去掉底部大图，给现金/售价框留位置）
	kit.box(2, 0, 4, 17, 1, 0)
	var start: int = (_index / ITEMS_PER_LINE) * ITEMS_PER_LINE - ITEMS_PER_LINE * PAGE_LINE_OFFSET
	start = maxi(start, 0)
	for j in range(4):
		for k in range(ITEMS_PER_LINE):
			var i: int = start + j * ITEMS_PER_LINE + k
			if i >= items.size():
				break
			var id: int = int(items[i])
			var c: Color = kit.col(COL_SELECTED if i == _index else COL_ITEM)
			var lx: int = 15 + k * CELL_W
			var ly: int = 12 + j * 18
			kit.text(item_name(id), lx, ly, c, 24, CELL_W - 6)
			var amount := item_amount(id)
			if amount > 1:
				kit.num_cyan(amount, 2, 15 + AMOUNT_X + k * CELL_W, 17 + j * 18)
			if i == _index:
				kit.cursor(15 + CURSOR_X + k * CELL_W, 22 + j * 18)
	# 现金
	kit.line_box(100, 150, 5, 6)
	kit.text(word(LABEL_CASH), 110, 160, kit.col(0x00), 20)
	kit.num_yellow(cash(), 6, 148, 165)
	# 售价
	kit.line_box(224, 150, 5, 6)
	if items.size() > 0:
		var cur: int = int(items[_index])
		if (int(item_of(cur)["flags"]) & FLAG_SELLABLE) != 0:
			kit.text(word(LABEL_SELL_PRICE), 234, 160, kit.col(0x00), 20)
			kit.num_yellow(int(item_of(cur)["price"]) / 2, 6, 272, 165)
	_draw_toast()


func _draw_toast() -> void:
	if _toast_text == "":
		return
	_kit.line_box(148, 2, 7, 6)
	_kit.text(_toast_text, 158, 12, _kit.col(0x0F), 20, 130)


func _draw_confirm() -> void:
	var kit = _kit
	kit.dim(0.45)
	kit.box(100, 78, 2, 7, 0, 6)
	var prompt := ""
	if is_buy:
		var items := _store_list()
		if items.size() > 0:
			var cur: int = int(items[_index])
			prompt = "买「%s」%d 文？" % [item_name(cur), int(item_of(cur)["price"])]
	else:
		prompt = "卖出选中物品？"
	kit.text(prompt, 110, 90, kit.col(COL_ITEM), 22)
	kit.line_box(112, 118, 2, 6)
	kit.text(word(LABEL_NO), 122, 128, kit.col(COL_SELECTED if _confirm_index == 0 else COL_ITEM), 26)
	kit.line_box(200, 118, 2, 6)
	kit.text(word(LABEL_YES), 210, 128, kit.col(COL_SELECTED if _confirm_index == 1 else COL_ITEM), 26)
	kit.text("←→ 选择   回车确定   Esc 取消", 80, 160, kit.col(COL_ITEM), 16)


# ---------------------------------------------------------------- 输入
func debug_key(key: int) -> void:
	if _closed:
		return
	_toast_text = ""
	if key == KEY_TAB:
		is_buy = not is_buy
		_index = 0
		_refresh()
		return
	if _confirming:
		_handle_confirm(key)
		_refresh()
		return
	match key:
		KEY_ESCAPE, KEY_BACKSPACE, KEY_M:
			close_shop()
			return
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			_start_confirm()
			_refresh()
			return
		KEY_UP, KEY_LEFT:
			var delta := -ITEMS_PER_LINE if (not is_buy and key == KEY_UP) else -1
			if is_buy and key == KEY_UP:
				delta = -1
			_move(delta)
		KEY_DOWN, KEY_RIGHT:
			var delta2 := ITEMS_PER_LINE if (not is_buy and key == KEY_DOWN) else 1
			if is_buy and key == KEY_DOWN:
				delta2 = 1
			_move(delta2)
		_:
			return
	_refresh()


func _move(delta: int) -> void:
	var n := _list.size()
	if n <= 0:
		return
	_index = posmod(_index + delta, n)


func _start_confirm() -> void:
	if _list.is_empty():
		return
	if is_buy:
		var cur: int = int(_list[_index])
		if int(item_of(cur)["price"]) > cash():
			_show_toast("金钱不足")
			return
	_confirming = true
	_confirm_index = 0


func _handle_confirm(key: int) -> void:
	match key:
		KEY_LEFT, KEY_UP:
			_confirm_index = 0
		KEY_RIGHT, KEY_DOWN:
			_confirm_index = 1
		KEY_ESCAPE, KEY_BACKSPACE, KEY_M:
			_confirming = false
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			_confirming = false
			if _confirm_index == 1:
				_do_trade()
		_:
			pass


func _do_trade() -> void:
	if _list.is_empty():
		return
	var cur: int = int(_list[_index])
	if is_buy:
		var price := int(item_of(cur)["price"])
		if price <= cash():
			PALState.cash -= price
			add_item(cur, 1)
	else:
		if add_item(cur, -1):
			PALState.cash += int(item_of(cur)["price"]) / 2


var _toast_text: String = ""


func _show_toast(s: String) -> void:
	_toast_text = s


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	debug_key((event as InputEventKey).keycode)
	get_viewport().set_input_as_handled()


func close_shop() -> void:
	if _closed:
		return
	_closed = true
	closed.emit()
	if is_inside_tree():
		queue_free()


func _exit_tree() -> void:
	if not _closed:
		_closed = true
		closed.emit()


# ---------------------------------------------------------------- 调试入口
## `--shop-test=<store>` 由 main.gd 尚未接入；保留可直接调用的自测截图接口 [inf]
func debug_screenshot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(SHOT_DIR + "shop_%s.png" % tag)
		print("[shop-test] SHOT ", SHOT_DIR + "shop_%s.png" % tag)
