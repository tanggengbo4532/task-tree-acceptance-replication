class_name PalMenu
extends CanvasLayer
## 菜单框架（sdlpal uigame.c 的 PAL_InGameMenu / PAL_SystemMenu / PAL_SaveSlotMenu
## 与 ui.c 的通用绘制原语移植）。
##
## 结构：
##   PalMenu（本文件根类，CanvasLayer）
##     ├─ class UiKit       —— 把 ui.c 的 box/text/number/cursor 原语映射为 Godot 节点
##     ├─ MainController    —— 主菜单（状态/仙术/物品/系统）
##     ├─ SystemController  —— 系统菜单（存档/读档/音乐/音效/结束游戏）
##     ├─ SlotController    —— 5 槽存/读档界面（显示次数/场景/时间）
##     └─ ConfirmController —— 是/否确认框（PAL_ConfirmMenu）
##   子菜单在 game/menu_item.gd / menu_magic.gd / menu_status.gd / menu_equip.gd，
##   都是 RefCounted 控制器：setup(menu)、build()、handle(key)->bool。
##
## 坐标：所有布局用原版 320×200 逻辑坐标书写，UiKit 统一 ×2 到 640×400 画布。
## 像素图（边框/数字/图标/背景）用最近邻 2 倍放大；中文文本用 SystemFont 直接按 2 倍
## 逻辑坐标绘制（保留可读性；位图字体接口见 UIAssets [inf]）。
##
## 关闭约定：emit_signal("closed")，World.on_menu_closed 负责 queue_free 并复位 player_busy。

signal closed
## 是/否选择结果（0x000A 确认框；World 的 request_confirm_y/n + vm.resume_choice 用）
signal choice_made(yes: bool)

const UI_ASSETS := preload("res://pal/ui_assets.gd")
const SAVE_SYSTEM := preload("res://game/save_system.gd")
const ITEM_MENU := preload("res://game/menu_item.gd")
const MAGIC_MENU := preload("res://game/menu_magic.gd")
const STATUS_MENU := preload("res://game/menu_status.gd")
const EQUIP_MENU := preload("res://game/menu_equip.gd")

const SHOT_DIR := "<LOCAL_PATH>"
## 原版逻辑分辨率
const LOGIC_W := 320
const LOGIC_H := 200
## 把 sdlpal 的 8bpp 调色板索引转成 Godot 颜色（主要 UI 颜色）
const COL_ITEM := 0x4F          # MENUITEM_COLOR
const COL_INACTIVE := 0x18      # MENUITEM_COLOR_INACTIVE
const COL_CONFIRMED := 0x2C     # MENUITEM_COLOR_CONFIRMED
const COL_SEL_INACTIVE := 0x1C  # MENUITEM_COLOR_SELECTED_INACTIVE
const COL_SELECTED := 0xF9      # MENUITEM_COLOR_SELECTED_FIRST
const COL_DESC := 0x3C          # DESCTEXT_COLOR
const COL_EQUIP := 0xBE         # STATUS_COLOR_EQUIPMENT
const COL_EQUIPED_ITEM := 0xC8  # MENUITEM_COLOR_EQUIPPEDITEM
const COL_LABEL := 0xBB         # ITEMUSEMENU_COLOR_STATLABEL
const COL_WHITE := 0x0F
const COL_NUM_YELLOW := 0
const COL_NUM_BLUE := 1
const COL_NUM_CYAN := 2

var kind: String = "main"
var host: Node = null
var ui: UIAssets = null
var kit: UiKit = null

var _root: Control = null
var _stack: Array = []
var _closed: bool = false
var _toast: String = ""
var _initial_kind: String = "main"
var _font: Font = null
var _shot_index: int = 0
## --menu-test=auto / roundtrip* 自测
var _selftest: String = ""
## 是/否确认框（脚本 0x000A / confirm()）
var _confirm_prompt: String = "确定吗？"
var _last_choice: bool = false
var _selftest_failed: bool = false

# 字体（系统中文；原版为位图字体，见 font.c/glyph.h，本移植 [inf] 用系统字体代替）
const SYSTEM_FONTS: Array[String] = ["SimSun", "Microsoft YaHei", "SimHei", "Noto Sans CJK SC"]


# =====================================================================
#  UiKit：ui.c 绘制原语
# =====================================================================
class UiKit extends RefCounted:
	const SCALE := 2
	const TEXT_SIZE := 26
	const SMALL_SIZE := 20

	var root: Control
	var ui: UIAssets
	var font: Font

	func _init(p_root: Control, p_ui: UIAssets, p_font: Font) -> void:
		root = p_root
		ui = p_ui
		font = p_font

	func clear() -> void:
		for ch in root.get_children():
			root.remove_child(ch)
			ch.queue_free()

	func col(idx: int) -> Color:
		return ui.color(idx)

	func _p(v: int) -> float:
		return float(v * SCALE)

	## 逻辑坐标原点（左上）
	func origin(lx: int, ly: int) -> Vector2:
		return Vector2(_p(lx), _p(ly))

	# ---------------------------------------------------------- 图层
	func full_rect(c: Color) -> ColorRect:
		var r := ColorRect.new()
		r.color = c
		r.position = Vector2.ZERO
		r.size = Vector2(PalMenu.LOGIC_W * SCALE, PalMenu.LOGIC_H * SCALE)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(r)
		return r

	## 全屏 FBP 背景（status/equip 用）
	func bg_fbp(chunk: int) -> void:
		var img := ui.fbp_background(chunk)
		image(img, 0, 0)

	## 覆盖在世界画面上的压暗层
	func dim(alpha: float = 0.35) -> void:
		full_rect(Color(0, 0, 0, alpha))

	func image(img: Image, lx: int, ly: int) -> TextureRect:
		if img == null:
			return null
		return tex(ImageTexture.create_from_image(img), lx, ly)

	func tex(t: Texture2D, lx: int, ly: int) -> TextureRect:
		var tr := TextureRect.new()
		tr.texture = t
		tr.position = origin(lx, ly)
		# 用 Control 尺寸做 2 倍放大（不再同时 scale，否则会 4 倍）
		tr.size = Vector2(t.get_width() * SCALE, t.get_height() * SCALE)
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(tr)
		return tr

	# ---------------------------------------------------------- 边框
	## ui.c PAL_CreateBox：rows/cols 为内容行列数（不含边框），style 0/1
	func box(lx: int, ly: int, rows: int, cols: int, style: int = 0, shadow: int = 6) -> void:
		var img := ui.box_image(rows, cols, style, shadow)
		image(img, lx, ly)

	## ui.c PAL_CreateSingleLineBox：len = 中段重复次数
	func line_box(lx: int, ly: int, line_len: int, shadow: int = 6) -> void:
		var img := ui.linebox_image(line_len, shadow)
		image(img, lx, ly)

	# ---------------------------------------------------------- 文本/数字
	func text(s: String, lx: int, ly: int, c: Color, size: int = -1, clip_w: int = -1) -> Label:
		var l := Label.new()
		l.text = s
		l.position = Vector2(_p(lx), _p(ly) - 4.0)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", TEXT_SIZE if size < 0 else size)
		l.add_theme_color_override("font_color", c)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("shadow_offset_x", 2)
		l.add_theme_constant_override("shadow_offset_y", 2)
		if clip_w > 0:
			l.size = Vector2(_p(clip_w), float((TEXT_SIZE if size < 0 else size) + 10))
			l.clip_text = true
		root.add_child(l)
		return l

	## ui.c PAL_DrawNumber：位图数字（颜色/对齐枚举同 UIAssets）
	func num(value: int, length: int, lx: int, ly: int, num_color: int, align: int) -> void:
		var img := ui.number_image(value, length, num_color, align)
		image(img, lx, ly)

	func num_yellow(value: int, length: int, lx: int, ly: int) -> void:
		num(value, length, lx, ly, UIAssets.NumColor.YELLOW, UIAssets.NumAlign.RIGHT)

	func num_blue(value: int, length: int, lx: int, ly: int) -> void:
		num(value, length, lx, ly, UIAssets.NumColor.BLUE, UIAssets.NumAlign.RIGHT)

	func num_cyan(value: int, length: int, lx: int, ly: int) -> void:
		num(value, length, lx, ly, UIAssets.NumColor.CYAN, UIAssets.NumAlign.RIGHT)

	# ---------------------------------------------------------- 图形元素
	func cursor(lx: int, ly: int, frame: int = UIAssets.SPR_CURSOR) -> void:
		image(ui.frame(frame), lx, ly)

	func icon(bitmap_id: int, lx: int, ly: int) -> void:
		image(ui.ball_icon(bitmap_id), lx, ly)

	func avatar_img(avatar_id: int, lx: int, ly: int) -> void:
		image(ui.avatar_image(avatar_id), lx, ly)

	## 单行小提示框（右上角）；原版无此控件，便于移植期显示错误/结果 [inf]
	func toast_text(s: String) -> void:
		line_box(148, 2, 7, 6)
		text(s, 158, 12, col(0x0F), SMALL_SIZE, 130)

	## 复刻 uibattle.c PAL_PlayerInfoBox（非 PAL_CLASSIC 布局）：
	## 框 75×35 + 头像 + HP/MP 数字。时间条在菜单里不显示。
	func player_info_box(lx: int, ly: int, role: int, hp: int, max_hp: int, mp: int, max_mp: int) -> void:
		image(ui.frame(UIAssets.SPR_PLAYERINFOBOX), lx, ly)
		image(ui.frame(UIAssets.SPR_PLAYERFACE + role), lx - 2, ly - 4)
		# HP：cur 在 +26,+13，max 在 +47,+16，斜杠 +49,+14
		num_yellow(hp, 4, lx + 26, ly + 13)
		image(ui.frame(UIAssets.SPR_SLASH), lx + 49, ly + 14)
		num_yellow(max_hp, 4, lx + 47, ly + 16)
		# MP：cur 在 +26,+23，max 在 +47,+26，斜杠 +49,+24
		num_cyan(mp, 4, lx + 26, ly + 23)
		image(ui.frame(UIAssets.SPR_SLASH), lx + 49, ly + 24)
		num_cyan(max_mp, 4, lx + 47, ly + 26)


# =====================================================================
#  基础生命周期
# =====================================================================

func setup(p_kind: String) -> void:
	kind = p_kind
	_initial_kind = p_kind


func _ready() -> void:
	layer = 5   # 世界 UI（CanvasLayer 默认 layer 1）之上
	_root = Control.new()
	_root.name = "MenuRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_font = SystemFont.new()
	_font.font_names = PackedStringArray(SYSTEM_FONTS)

	ui = UIAssets.new()
	ui.init()
	kit = UiKit.new(_root, ui, _font)
	host = get_parent()
	if host != null and host.get("player_busy") != null:
		host.set("player_busy", true)

	# --menu-test 的两种用法：
	#   * `--menu-test=auto` / `roundtrip[-save|-load]` → 本文件内的自动自测
	#   * `--menu-test=item|magic|status|...` → main.gd 直接把 kind 传给 setup()，只打开该页
	for a in OS.get_cmdline_args():
		if a.begins_with("--menu-test="):
			var v := a.substr("--menu-test=".length())
			if v == "auto" or v == "selftest" or v.begins_with("roundtrip"):
				_selftest = v
	if _selftest == "" and "--menu-test=1" in OS.get_cmdline_args():
		_selftest = "auto"
	# 自测只允许“顶层菜单实例”执行（自测里会临时再 new 一个 Menu 做 World 调用顺序模拟，
	# 子实例不能重复跑整套自测）
	var is_nested_menu := get_parent() != null and get_parent() is PalMenu
	if _selftest != "" and not is_nested_menu:
		call_deferred("_run_selftest")
	else:
		_open_initial()


## 正常入口：按 world/main 传入的 kind 打开初始页面（保留主菜单作为返回栈底）
func _open_initial() -> void:
	_stack.clear()
	if _initial_kind == "confirm":
		# 仅确认框（World 的 request_confirm_* / confirm()）
		_push(ScriptConfirmController.new())
		_rebuild()
		return
	_push(MainController.new())
	match _initial_kind:
		"item":
			_push(ITEM_MENU.InventoryMenu.new())
		"magic":
			_push(MAGIC_MENU.MagicController.new())
		"status":
			_push(STATUS_MENU.StatusController.new())
		"equip":
			# 装备入口 = 可选装备的物品列表（itemmenu.c kItemFlagEquipable 过滤）
			var eq = ITEM_MENU.ItemSelectController.new()
			eq.item_flags = 0x02
			_push(eq)
		"system":
			_push(SystemController.new())
		"save":
			_push(SystemController.new())
			_push(SlotController.new(true))
		"load":
			_push(SystemController.new())
			_push(SlotController.new(false))
		_:
			pass
	_rebuild()


# =====================================================================
#  是/否确认框（ui.c PAL_SelectionMenu / script 0x000A）
# =====================================================================

## 给 World 用：直接以“确认框”作为整个菜单内容（无需主菜单）。
## 用法（两种都支持）：
##   * `m.setup_confirm(prompt); add_child(m)` —— setup 先于入树；
##   * `add_child(m); m.setup_confirm(prompt)` —— World.request_confirm 目前是这种顺序，
##     此时 _ready 已按默认 kind("main") 建过界面，这里重新切换为确认框。
func setup_confirm(prompt_text: String = "确定吗？") -> void:
	kind = "confirm"
	_initial_kind = "confirm"
	_confirm_prompt = prompt_text
	if is_inside_tree() and kit != null:
		_closed = false
		_stack.clear()
		_push(ScriptConfirmController.new())
		_rebuild()


## 可复用 await API：在当前菜单上弹出确认框并等待选择（返回是否“是”）。
## 说明：调用前本节点必须在场景树里；返回后确认框自动收起。
func confirm(prompt_text: String = "") -> bool:
	if prompt_text != "":
		_confirm_prompt = prompt_text
	if _stack.is_empty():
		_stack.append(ScriptConfirmController.new())
		_stack[0].setup(self)
		_rebuild()
	else:
		push_controller(ScriptConfirmController.new())
	var yes: bool = await choice_made
	return yes


## 确认框选择完成回调（ScriptConfirmController 调用）
func _finish_confirm(yes: bool) -> void:
	_last_choice = yes
	choice_made.emit(yes)
	if _initial_kind == "confirm":
		# 专用确认菜单：先让选择结果送达（await/连接者），下一帧再 emit closed
		call_deferred("close_menu")
	else:
		if _stack.size() > 1:
			pop_controller()
		else:
			call_deferred("close_menu")


func _push(c: RefCounted) -> void:
	if c == null:
		return
	c.setup(self)
	_stack.append(c)


func push_controller(c: RefCounted) -> void:
	_push(c)
	_rebuild()


func pop_controller() -> void:
	if _stack.is_empty():
		return
	_stack.pop_back()
	if _stack.is_empty():
		close_menu()
	else:
		_rebuild()


func close_menu() -> void:
	if _closed:
		return
	_closed = true
	closed.emit()
	if is_inside_tree():
		queue_free()


func _rebuild() -> void:
	if _closed or kit == null:
		return
	kit.clear()
	if _stack.is_empty():
		return
	var top: RefCounted = _stack.back()
	top.build()
	if _toast != "":
		kit.toast_text(_toast)


func toast(s: String) -> void:
	_toast = s
	_rebuild()


## 输入入口（键盘；自测也走这里，保证与实际操作同一条路径）
func debug_key(key: int) -> void:
	if _closed or _stack.is_empty():
		return
	_toast = ""
	var top: RefCounted = _stack.back()
	var consumed: bool = top.handle(key)
	if not consumed and (key == KEY_ESCAPE or key == KEY_BACKSPACE or key == KEY_M):
		pop_controller()
		return
	if not _closed:
		_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	debug_key((event as InputEventKey).keycode)
	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if not _closed:
		_closed = true
		closed.emit()


# =====================================================================
#  数据适配（统一走 PALTables / PALState；autoload 未初始化时给安全兜底）
# =====================================================================

func word(id: int) -> String:
	if PALTables != null and PALTables.words.size() > 0:
		return PALTables.word(id).strip_edges()
	return ""


func item_name(id: int) -> String:
	if PALTables != null and PALTables.has_method("item_name"):
		return str(PALTables.item_name(id)).strip_edges()
	return word(id)


func player_name(role: int) -> String:
	if PALTables != null:
		return str(PALTables.player_name(role)).strip_edges()
	return ""


func item_of(id: int) -> Dictionary:
	if PALTables != null:
		return PALTables.item_of(id)
	return {"bitmap": 0, "price": 0, "script_on_use": 0, "script_on_equip": 0,
		"script_on_throw": 0, "script_desc": 0, "flags": 0}


func magic_obj_of(id: int) -> Dictionary:
	if PALTables != null:
		return PALTables.magic_obj_of(id)
	return {"magic_number": 0, "reserved1": 0, "script_on_success": 0,
		"script_on_use": 0, "script_desc": 0, "reserved2": 0, "flags": 0}


func magic_def_for(id: int) -> Dictionary:
	if PALTables != null:
		return PALTables.magic_def_for(id)
	return {}


func magic_cost(magic_obj_id: int) -> int:
	var d := magic_def_for(magic_obj_id)
	return int(d.get("cost_mp", 0))


func poison_of(id: int) -> Dictionary:
	if PALTables != null:
		return PALTables.poison_obj_of(id)
	return {"poison_level": 0, "color": 0, "player_script": 0, "reserved": 0, "enemy_script": 0}


func role_array(field: String) -> Array:
	if PALState != null and PALState.roles.has(field):
		return PALState.roles[field]
	return []


func role_value(field: String, role: int) -> int:
	var a := role_array(field)
	if role >= 0 and role < a.size():
		return int(a[role])
	return 0


func equipment_of(role: int, part: int) -> int:
	var a := role_array("equipment")
	var idx := part * 6 + role
	if idx >= 0 and idx < a.size():
		return int(a[idx])
	return 0


func party_roles() -> Array[int]:
	var out: Array[int] = []
	if PALState == null:
		return out
	var n := int(PALState.max_party_member_index)
	for i in range(n + 1):
		if i < PALState.party.size():
			out.append(int(PALState.party[i]["role"]))
	if out.is_empty():
		out.append(0)
	return out


func max_party_index() -> int:
	if PALState == null:
		return 0
	return clampi(int(PALState.max_party_member_index), 0, 4)


func cash() -> int:
	return int(PALState.cash) if PALState != null else 0


func add_item(item_id: int, n: int) -> int:
	if PALState != null:
		return PALState.add_item(item_id, n)
	return 0


func item_amount(item_id: int) -> int:
	if PALState != null:
		return PALState.get_item_amount(item_id)
	return 0


func inventory_entry(index: int) -> Dictionary:
	if PALState != null and index >= 0 and index < PALState.inventory.size():
		return PALState.inventory[index]
	return {"item": 0, "amount": 0, "in_use": 0}


## 背包非空项（已按 sdlpal PAL_CompressInventory 压缩）
func inventory_entries() -> Array:
	if PALState != null:
		PALState.compress_inventory()
	var out: Array = []
	for i in range(256):
		var e := inventory_entry(i)
		if int(e["item"]) == 0:
			break
		out.append(e)
	return out


## 战斗外可用物品列表 = 背包可用物品 + 已装备的可用物品（itemmenu.c PAL_ItemSelectMenuInit）
func selectable_items(item_flags: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in inventory_entries():
		var it := int(e["item"])
		if (int(item_of(it)["flags"]) & item_flags) != 0 and int(e["amount"]) > int(e["in_use"]):
			out.append(e)
	if (item_flags & 0x01) != 0 and (PALState == null or not PALState.in_battle):
		for role in party_roles():
			for part in range(6):
				var it2 := equipment_of(role, part)
				if it2 != 0 and (int(item_of(it2)["flags"]) & 0x01) != 0:
					out.append({"item": it2, "amount": 0, "in_use": 0xFFFF})
	return out


func item_desc_lines(item_id: int) -> PackedStringArray:
	return _script_desc_lines(int(item_of(item_id)["script_desc"]))


func magic_desc_lines(magic_obj_id: int) -> PackedStringArray:
	return _script_desc_lines(int(magic_obj_of(magic_obj_id)["script_desc"]))


## WIN95 描述走“自动脚本”：线性 0x00A7 + 若干 0xFFFF 文本 + 0x0000 结束。
## [observation] 对 wScriptDesc 脚本逐条抽样（40661/40309/40485 等）确认此结构。
func _script_desc_lines(entry: int) -> PackedStringArray:
	var out := PackedStringArray()
	if entry == 0 or PALTables == null or PALTables.sss == null:
		return out
	var ip: int = entry
	var guard := 0
	while guard < 32:
		guard += 1
		var op := PALTables.sss.script_entry(ip)
		if op.size() < 4:
			break
		if op[0] == 0:
			break
		if op[0] == 0xFFFF:
			var line := PalData.strip_control_codes(PALTables.sss.msg(op[1])).strip_edges()
			if line != "":
				out.append(line)
			ip += 1
		else:
			ip += 1
	return out


func get_attack(role: int) -> int:
	if PALState != null:
		return PALState.get_player_attack_strength(role)
	return role_value("attack_strength", role)


func get_magic_strength(role: int) -> int:
	if PALState != null:
		return PALState.get_player_magic_strength(role)
	return role_value("magic_strength", role)


func get_defense(role: int) -> int:
	if PALState != null:
		return PALState.get_player_defense(role)
	return role_value("defense", role)


func get_dexterity(role: int) -> int:
	if PALState != null:
		return PALState.get_player_dexterity(role)
	return role_value("dexterity", role)


func get_flee(role: int) -> int:
	if PALState != null:
		return PALState.get_player_flee_rate(role)
	return role_value("flee_rate", role)


# =====================================================================
#  行为（对应 play.c PAL_GameUseItem / PAL_GameEquipItem、uigame.c 魔法使用）
# =====================================================================

## 运行触发脚本：World 注入的同步 runner；返回是否真的执行
func run_script(entry: int, operand: int) -> bool:
	if entry == 0:
		return false
	if PALState != null and PALState.script_runner.is_valid():
		PALState.script_runner.call(entry, operand)
		return true
	return false


## 使用物品（play.c PAL_GameUseItem）：不指定目标时 operand=0xFFFF（全队）
func use_item(item_id: int, target_role: int) -> void:
	var obj := item_of(item_id)
	var flags := int(obj["flags"])
	var operand: int = 0xFFFF if target_role < 0 else target_role
	var ran := run_script(int(obj["script_on_use"]), operand)
	if (flags & 0x08) != 0 and ran:
		add_item(item_id, -1)
	if ran:
		toast("使用了「%s」" % item_name(item_id))
	else:
		toast("「%s」效果脚本尚未接入 [inf]" % item_name(item_id))


## 装备物品：sdlpal 由 item.wScriptOnEquip 脚本（操作码 0x0018）完成换装；
## 若脚本 VM 尚未实现该操作码，则按脚本里的 0x0018 参数做最小兼容换装 [inf]。
func equip_item(item_id: int, role: int) -> void:
	var obj := item_of(item_id)
	var before := equipment_of(role, _part_hint(item_id))
	var ran := run_script(int(obj["script_on_equip"]), role)
	if not ran or equipment_of(role, _part_hint(item_id)) == before:
		_equip_fallback(item_id, role)
	if PALState != null:
		PALState.update_equipments()
	toast("装备了「%s」" % item_name(item_id))


## 从装备脚本里找 0x0018（换装）参数：operand0 = 部位 + 0x0B，operand1 = 物品 id。
## 返回部位；找不到时用物品 id 段位做经验推断 [inf]。
func _part_hint(item_id: int) -> int:
	var entry := int(item_of(item_id)["script_on_equip"])
	if entry == 0 or PALTables == null or PALTables.sss == null:
		return 3
	var ip: int = entry
	for _i in range(64):
		var op := PALTables.sss.script_entry(ip)
		if op.size() < 4 or op[0] == 0:
			break
		if op[0] == 0x0018:
			return clampi(op[1] - 0x0B, 0, 5)
		ip += 1
	return 3


func _equip_fallback(item_id: int, role: int) -> void:
	if PALState == null:
		return
	var part := _part_hint(item_id)
	var idx := part * 6 + role
	if idx < 0 or idx >= PALState.roles["equipment"].size():
		return
	var old := int(PALState.roles["equipment"][idx])
	if old == item_id:
		return
	PALState.roles["equipment"][idx] = item_id
	PALState.remove_equipment_effect(role, part)
	# 背包交换（对齐 script.c 0x0018：数量为 1 且旧装备不在背包时直接替换）
	var new_index := PALState.get_item_index(item_id)
	var old_index := PALState.get_item_index(old)
	if new_index >= 0 and int(PALState.inventory[new_index]["amount"]) == 1 and old != 0 and old_index < 0:
		PALState.inventory[new_index]["item"] = old
	else:
		PALState.add_item(item_id, -1)
		if old != 0:
			PALState.add_item(old, 1)


## 使用仙术（uigame.c PAL_InGameMagicMenu）：按 magic_obj 的 flags 决定单体/全体
func use_magic(role: int, magic_obj_id: int, target_role: int) -> void:
	var obj := magic_obj_of(magic_obj_id)
	var flags := int(obj["flags"])
	var apply_all := (flags & 0x10) != 0
	var operand: int = 0xFFFF if apply_all else target_role
	# sdlpal：先 wScriptOnUse（成功）再 wScriptOnSuccess，扣 MP 由成功决定
	var ran_use := run_script(int(obj["script_on_use"]), operand)
	var ran_success := run_script(int(obj["script_on_success"]), operand)
	if PALState != null and (ran_use or ran_success):
		var cost := magic_cost(magic_obj_id)
		PALState.roles["mp"][role] = maxi(0, int(PALState.roles["mp"][role]) - cost)
	toast("使用了「%s」" % item_name(magic_obj_id))


## 存/读档（PALState 已实现 SAVEDGAME_WIN 兼容二进制 + vars JSON）
func save_game(slot: int) -> bool:
	if PALState == null:
		return false
	_toast = ""
	return PALState.save_game(slot)


func load_game(slot: int) -> bool:
	if PALState == null:
		return false
	if not PALState.load_game(slot):
		return false
	# 当前槽位（原版 bCurrentSaveSlot；Lead 提示读档时需设置）
	if "current_save_slot" in PALState:
		PALState.current_save_slot = slot
	# 读档后重载场景（原版 PAL_ReloadInNextTick(kLoadScene)；World 用恢复后的
	# scene/viewport/party 重载并执行该场景 onEnter 脚本）
	if host != null and host.has_method("load_scene"):
		host.call_deferred("load_scene", PALState.scene, false)
	return true


func slot_summary(slot: int) -> Dictionary:
	return SAVE_SYSTEM.slot_summary(slot)


# =====================================================================
#  主菜单（uigame.c PAL_InGameMenu）
# =====================================================================
class MainController extends RefCounted:
	const LABEL_STATUS := 3      # GAMEMENU_LABEL_STATUS（词条 3 = 状态）
	const LABEL_MAGIC := 4       # GAMEMENU_LABEL_MAGIC（4 = 仙术）
	const LABEL_INVENTORY := 5   # GAMEMENU_LABEL_INVENTORY（5 = 物品）
	const LABEL_SYSTEM := 6      # GAMEMENU_LABEL_SYSTEM（6 = 系统）
	const LABEL_CASH := 21       # CASH_LABEL（21 = 金钱）

	var menu = null
	var index: int = 0

	func setup(p_menu) -> void:
		menu = p_menu
		index = clampi(int(menu._main_index), 0, 3)

	func build() -> void:
		var kit = menu.kit
		kit.dim(0.30)
		# 现金：PAL_ShowCash(0,0) 单行框 5 段，金钱标签 + 6 位数字
		kit.line_box(0, 0, 5, 6)
		kit.text(menu.word(LABEL_CASH), 10, 10, kit.col(0x00), 22)
		kit.num_yellow(menu.cash(), 6, 49, 14)
		# 主菜单框：PAL_CreateBox((3,37), 3, MenuTextMaxWidth-1, 0)
		var labels := [LABEL_STATUS, LABEL_MAGIC, LABEL_INVENTORY, LABEL_SYSTEM]
		var cols: int = maxi(0, menu_text_max_width(labels) - 1)
		kit.box(3, 37, 3, cols, 0, 6)
		for i in range(4):
			var c: Color = kit.col(PalMenu.COL_SELECTED if i == index else PalMenu.COL_ITEM)
			kit.text(menu.word(labels[i]), 16, 50 + 18 * i, c, 26)

	func menu_text_max_width(labels: Array) -> int:
		var r := 0
		for w in labels:
			var t: String = menu.word(int(w))
			var n: int = 0
			for ch in t:
				n += 2 if ch.unicode_at(0) > 0x7F else 1
			r = maxi(r, (n * 8 + 8) >> 4)
		return maxi(r, 1)

	func handle(key: int) -> bool:
		match key:
			KEY_UP, KEY_LEFT:
				index = (index + 3) % 4
				menu._main_index = index
				return true
			KEY_DOWN, KEY_RIGHT:
				index = (index + 1) % 4
				menu._main_index = index
				return true
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				match index:
					0:
						menu.push_controller(PalMenu.STATUS_MENU.StatusController.new())
					1:
						menu.push_controller(PalMenu.MAGIC_MENU.MagicController.new())
					2:
						menu.push_controller(PalMenu.ITEM_MENU.InventoryMenu.new())
					3:
						menu.push_controller(PalMenu.SystemController.new())
				return true
		return false


# =====================================================================
#  系统菜单（uigame.c PAL_SystemMenu）
# =====================================================================
class SystemController extends RefCounted:
	const LABEL_SAVE := 11
	const LABEL_LOAD := 12
	const LABEL_MUSIC := 13
	const LABEL_SOUND := 14
	const LABEL_QUIT := 15

	var menu = null
	var index: int = 0
	var labels: Array[int] = [11, 12, 13, 14, 15]

	func setup(p_menu) -> void:
		menu = p_menu
		index = clampi(int(menu._system_index), 0, labels.size() - 1)

	func build() -> void:
		var kit = menu.kit
		kit.dim(0.30)
		var cols: int = maxi(0, _max_width() - 1)
		kit.box(40, 60, labels.size() - 1, cols, 0, 6)
		for i in range(labels.size()):
			var c: Color = kit.col(PalMenu.COL_SELECTED if i == index else PalMenu.COL_ITEM)
			kit.text(menu.word(labels[i]), 53, 72 + 18 * i, c, 26)

	func _max_width() -> int:
		var r := 0
		for w in labels:
			var t: String = menu.word(int(w))
			var n: int = 0
			for ch in t:
				n += 2 if ch.unicode_at(0) > 0x7F else 1
			r = maxi(r, (n * 8 + 8) >> 4)
		return maxi(r, 1)

	func handle(key: int) -> bool:
		match key:
			KEY_UP, KEY_LEFT:
				index = (index + labels.size() - 1) % labels.size()
				menu._system_index = index
				return true
			KEY_DOWN, KEY_RIGHT:
				index = (index + 1) % labels.size()
				menu._system_index = index
				return true
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				match index:
					0:
						menu.push_controller(PalMenu.SlotController.new(true))
					1:
						menu.push_controller(PalMenu.SlotController.new(false))
					2:
						menu._toggle_audio("music")
					3:
						menu._toggle_audio("sound")
					4:
						menu.push_controller(PalMenu.ConfirmController.new("结束游戏？", Callable(menu, "_quit_game")))
				return true
		return false


# =====================================================================
#  存/读档槽位（uigame.c PAL_SaveSlotMenu 的移植增强版）
#  * 原版只显示“进度N + 已存档次数”，此移植额外显示 场景号/存档时间（任务验收要求）
#  * 槽位文件由 PALState.save_game/load_game 读写（SAVEDGAME_WIN 兼容）
# =====================================================================
class SlotController extends RefCounted:
	var menu = null
	var is_save: bool = true
	var index: int = 0

	func _init(p_is_save: bool = true) -> void:
		is_save = p_is_save

	func setup(p_menu) -> void:
		menu = p_menu

	func build() -> void:
		var kit = menu.kit
		kit.dim(0.45)
		kit.box(7, 20, 7, 16, 0, 6)
		kit.text("存 档" if is_save else "读 档", 40, 30, kit.col(PalMenu.COL_CONFIRMED), 26)
		for i in range(5):
			var y: int = 56 + 24 * i
			var info: Dictionary = menu.slot_summary(i + 1)
			var c: Color = kit.col(PalMenu.COL_ITEM)
			if i == index:
				c = kit.col(PalMenu.COL_SELECTED)
			var label: String = menu.word(43 + i)
			if label == "":
				label = "进度%d" % (i + 1)
			kit.text(label, 40, y, c, 24)
			var detail := ""
			if bool(info.get("exists", false)):
				detail = "场景 %d   次数 %d   %s" % [
					int(info.get("scene", 0)), int(info.get("saved_times", 0)),
					str(info.get("time_text", ""))]
				if not bool(info.get("compatible", true)):
					detail += "  [格式存疑]"
			else:
				detail = "（空）"
			kit.text(detail, 108, y + 2, kit.col(0x0F if i == index else 0x4F), 20)
		if index >= 0 and index < 5:
			kit.cursor(24, 58 + 24 * index, UIAssets.SPR_CURSOR)
		kit.text("↑↓ 选择    回车确定    Esc 返回", 40, 180, kit.col(0x4F), 16)

	func handle(key: int) -> bool:
		match key:
			KEY_UP, KEY_LEFT:
				index = (index + 4) % 5
				return true
			KEY_DOWN, KEY_RIGHT:
				index = (index + 1) % 5
				return true
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				if is_save:
					if menu.save_game(index + 1):
						menu.toast("%s（槽 %d）" % [menu.word(16), index + 1])
					else:
						menu.toast("存档失败 [inf]")
				else:
					var info: Dictionary = menu.slot_summary(index + 1)
					if not bool(info.get("exists", false)):
						menu.toast("此槽位没有存档")
					elif menu.load_game(index + 1):
						menu.close_menu()
					else:
						menu.toast("读档失败（格式不兼容？）")
				return true
		return false


# =====================================================================
#  确认框（ui.c PAL_SelectionMenu / PAL_ConfirmMenu）
# =====================================================================
class ConfirmController extends RefCounted:
	var menu = null
	var prompt: String = ""
	var on_yes: Callable = Callable()
	var index: int = 0   # 0 = 否, 1 = 是

	func _init(p_prompt: String = "", p_on_yes: Callable = Callable()) -> void:
		prompt = p_prompt
		on_yes = p_on_yes

	func setup(p_menu) -> void:
		menu = p_menu

	func build() -> void:
		var kit = menu.kit
		kit.dim(0.45)
		kit.box(100, 80, 2, 6, 0, 6)
		kit.text(prompt, 112, 92, kit.col(PalMenu.COL_ITEM), 26)
		# 否（词条 19）/ 是（词条 20）
		kit.line_box(112, 118, 2, 6)
		kit.text(menu.word(19), 122, 128, kit.col(PalMenu.COL_SELECTED if index == 0 else PalMenu.COL_ITEM), 26)
		kit.line_box(200, 118, 2, 6)
		kit.text(menu.word(20), 210, 128, kit.col(PalMenu.COL_SELECTED if index == 1 else PalMenu.COL_ITEM), 26)

	func handle(key: int) -> bool:
		match key:
			KEY_LEFT, KEY_UP:
				index = 0
				return true
			KEY_RIGHT, KEY_DOWN:
				index = 1
				return true
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				if index == 1 and on_yes.is_valid():
					on_yes.call()
				else:
					menu.pop_controller()
				return true
		return false


# =====================================================================
#  脚本 0x000A 专用确认框（无底层菜单；World 的 request_confirm_y/n 用）
# =====================================================================
class ScriptConfirmController extends RefCounted:
	var menu = null
	var index: int = 0   # 0 = 否, 1 = 是

	func setup(p_menu) -> void:
		menu = p_menu

	func build() -> void:
		var kit = menu.kit
		kit.dim(0.40)
		kit.box(100, 78, 2, 7, 0, 6)
		kit.text(menu._confirm_prompt, 110, 90, kit.col(PalMenu.COL_ITEM), 24, 180)
		kit.line_box(112, 118, 2, 6)
		kit.text(menu.word(19), 122, 128, kit.col(PalMenu.COL_SELECTED if index == 0 else PalMenu.COL_ITEM), 26)
		kit.line_box(200, 118, 2, 6)
		kit.text(menu.word(20), 210, 128, kit.col(PalMenu.COL_SELECTED if index == 1 else PalMenu.COL_ITEM), 26)
		kit.text("←→ 选择   回车确定   Esc 否", 90, 162, kit.col(PalMenu.COL_ITEM), 16)

	func handle(key: int) -> bool:
		match key:
			KEY_LEFT, KEY_UP:
				index = 0
				return true
			KEY_RIGHT, KEY_DOWN:
				index = 1
				return true
			KEY_ESCAPE, KEY_BACKSPACE:
				menu._finish_confirm(false)
				return true
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				menu._finish_confirm(index == 1)
				return true
		return false


# =====================================================================
#  全局小操作
# =====================================================================
var _main_index: int = 0
var _system_index: int = 0


func _toggle_audio(which: String) -> void:
	# sdlpal PAL_SystemMenu：音乐/音效开关（PAL_SwitchMenu）
	# PALAudio 的开关是属性（music_enabled/sound_enabled）+ enable_* 方法；
	# 用 get/call 访问，避免与属性/方法签名变化耦合。
	var on := true
	if PALAudio != null:
		if which == "music":
			on = not bool(PALAudio.get("music_enabled"))
			PALAudio.call("enable_music", on)
		else:
			on = not bool(PALAudio.get("sound_enabled"))
			PALAudio.call("enable_sound", on)
	toast("%s：%s" % [word(13) if which == "music" else word(14), word(18) if on else word(17)])


func _quit_game() -> void:
	get_tree().quit(0)


# =====================================================================
#  --menu-test 自测（截图 + 存读档往返断言）
# =====================================================================

func _run_selftest() -> void:
	_install_test_script_runner()
	if _selftest.begins_with("roundtrip"):
		await _selftest_roundtrip(_selftest)
		return
	await _selftest_pages()


func _wait_frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("[menu-test] SHOT_FAIL ", tag)
		return
	var path := SHOT_DIR + "menu_%02d_%s.png" % [_shot_index, tag]
	_shot_index += 1
	img.save_png(path)
	print("[menu-test] SHOT ", path)


## 自测用：把状态填充成可展示的演示数据（原版此时已通过剧情获得队伍/物品）
func _seed_demo_state() -> void:
	if PALState == null:
		return
	PALState.reset_defaults()
	PALState.cash = 1234
	PALState.scene = 12
	PALState.max_party_member_index = 2
	for i in range(5):
		PALState.party[i]["role"] = i if i < 3 else 0
	for i in range(PALState.inventory.size()):
		PALState.inventory[i] = {"item": 0, "amount": 0, "in_use": 0}
	var demo := [[99, 9], [101, 3], [61, 2], [75, 4], [77, 1], [84, 2],
		[196, 1], [163, 1], [168, 1], [201, 1], [205, 1], [212, 1]]
	var idx := 0
	for pair in demo:
		PALState.inventory[idx] = {"item": int(pair[0]), "amount": int(pair[1]), "in_use": 0}
		idx += 1
	PALState.roles["level"][0] = 1
	PALState.update_equipments()


# =====================================================================
#  自测专用脚本 runner（menu-test 下无 World/ScriptVM 时模拟 0x000A 相关效果）
#  [inf] 只实现物品使用/装备换装所需的最小子集，真实链路走 World.run_script_entry_sync。
# =====================================================================

func _install_test_script_runner() -> void:
	if PALState == null:
		return
	if not PALState.script_runner.is_valid():
		# 优先用真实 ScriptVM（world=null）；它实现了 0x0017/0x0018/0x001B..0x001F，
		# 这样菜单自测走的就是正式脚本语义（对白类操作因 world null 自然跳过）。
		PALState.script_runner = Callable(self, "_vm_script_runner")
		print("[menu-test] 安装测试脚本 runner（真实 ScriptVM，world=null）")


## 用真实 ScriptVM 同步执行一段脚本（菜单自测；正式链路是 World.run_script_entry_sync）
func _vm_script_runner(entry: int, operand: int) -> void:
	if PALTables == null or PALTables.sss == null:
		return
	if entry == 0:
		return
	var vm := ScriptVM.new()
	vm.setup(PALTables.sss, null)
	vm.start(entry, operand)
	var guard := 0
	while vm.is_active() and not vm.waiting_dialog and guard < 2000:
		vm.tick()
		guard += 1


func _test_script_runner(entry: int, operand: int) -> void:
	if PALTables == null or PALTables.sss == null:
		return
	var role := int(operand)
	var last_role := -1
	var ip := entry
	var guard := 0
	while guard < 64:
		guard += 1
		var op := PALTables.sss.script_entry(ip)
		if op.size() < 4 or op[0] == 0:
			break
		match int(op[0]):
			0x0018:
				var part18 := int(op[1]) - 0x0B
				var item18 := int(op[2])
				# 注意：PALState.update_equipments() 目前传 oper=0xFFFF（sdlpal 传 role，
				# 已反馈 Lead）；测试 runner 里按“槽位里已有该物品的角色”反查 [inf]。
				var r18 := role
				if r18 < 0 or r18 >= 6:
					r18 = _test_role_by_equipment(part18, item18)
				if r18 >= 0 and r18 < 6:
					last_role = r18
					_test_apply_equip(part18, item18, r18)
			0x0017:
				var part := int(op[1]) - 0x0B
				var field := _role_group_field(int(op[2]))
				var r17 := role
				if r17 < 0 or r17 >= 6:
					r17 = last_role
				if field != "" and part >= 0 and part < 6 and r17 >= 0 and r17 < 6 and PALState != null:
					PALState.set_equipment_effect(part, r17, field, int(op[3]))
			0x001B:
				var dhp := _s16(op[2])
				if int(op[1]) != 0:
					for r in party_roles():
						PALState.increase_hpmp(int(r), dhp, 0)
				else:
					PALState.increase_hpmp(role, dhp, 0)
			0x001C:
				var dmp := _s16(op[2])
				if int(op[1]) != 0:
					for r in party_roles():
						PALState.increase_hpmp(int(r), 0, dmp)
				else:
					PALState.increase_hpmp(role, 0, dmp)
			0x001D:
				var dv := _s16(op[2])
				if int(op[1]) != 0:
					for r in party_roles():
						PALState.increase_hpmp(int(r), dv, dv)
				else:
					PALState.increase_hpmp(role, dv, dv)
			0x001E:
				PALState.cash += _s16(op[1])
			0x001F:
				PALState.add_item(int(op[1]), _s16(op[2]))
			_:
				pass
		ip += 1


func _s16(v: int) -> int:
	return v - 0x10000 if v >= 0x8000 else v


## script.c 0x0017 的 operand1 是 PLAYERROLES 的“6 word 组号”，映射回字段名。
func _role_group_field(group: int) -> String:
	match group:
		4:
			return "attack_all"
		6:
			return "level"
		7:
			return "max_hp"
		8:
			return "max_mp"
		9:
			return "hp"
		10:
			return "mp"
		17:
			return "attack_strength"
		18:
			return "magic_strength"
		19:
			return "defense"
		20:
			return "dexterity"
		21:
			return "flee_rate"
		22:
			return "poison_resistance"
	return ""


## 按“某部位当前装备 == item_id”反查角色（测试 runner 在 oper=0xFFFF 时用）
func _test_role_by_equipment(part: int, item_id: int) -> int:
	if PALState == null or part < 0 or part >= 6 or item_id == 0:
		return -1
	var eq: Array = PALState.roles["equipment"]
	for r in range(6):
		var idx := part * 6 + r
		if idx < eq.size() and int(eq[idx]) == item_id:
			return r
	return -1


## 测试 runner 里的换装（对齐 script.c 0x0018 的背包交换，但不递归 update_equipments）
func _test_apply_equip(part: int, item_id: int, role: int) -> void:
	if PALState == null or part < 0 or part >= 6:
		return
	var idx := part * 6 + role
	if idx < 0 or idx >= PALState.roles["equipment"].size():
		return
	var old := int(PALState.roles["equipment"][idx])
	if old == item_id:
		return
	PALState.roles["equipment"][idx] = item_id
	var new_index := PALState.get_item_index(item_id)
	var old_index := PALState.get_item_index(old)
	if new_index >= 0 and int(PALState.inventory[new_index]["amount"]) == 1 and old != 0 and old_index < 0:
		PALState.inventory[new_index]["item"] = old
	else:
		PALState.add_item(item_id, -1)
		if old != 0:
			PALState.add_item(old, 1)


## 对当前栈顶“物品列表”控制器按物品 id 定位光标
func _debug_find_item(item_id: int) -> int:
	if _stack.is_empty():
		return -1
	var top: RefCounted = _stack.back()
	if top.has_method("find_item"):
		return int(top.call("find_item", item_id))
	return -1


## 自测断言：物品使用（HP+50/消耗）与装备换装（槽位/属性/背包交换）
func _selftest_item_equip() -> void:
	_install_test_script_runner()
	_reset_nav_indices()
	_seed_demo_state()
	PALState.roles["hp"][0] = 100
	PALState.update_equipments()
	var pass_all := true
	# ---------- 装备：皮帽(201) 换下默认头巾(196)，防御 +4-1 = +3 ----------
	var defense_before := int(PALState.get_player_defense(0))
	var head_before := int(PALState.roles["equipment"][0])
	var amount_196 := PALState.get_item_amount(196)
	var amount_201 := PALState.get_item_amount(201)
	debug_open("equip")
	await get_tree().process_frame
	var found := _debug_find_item(201)
	if found >= 0:
		debug_key(KEY_ENTER)      # 物品列表 → 装备界面
		await get_tree().process_frame
		debug_key(KEY_ENTER)      # 对当前角色（李逍遥）装备
		await _wait_frames(2)
	var head_after := int(PALState.roles["equipment"][0])
	var defense_after := int(PALState.get_player_defense(0))
	var equip_ok: bool = head_after == 201 and (defense_after - defense_before) == 3 \
		and PALState.get_item_amount(196) == amount_196 + 1 \
		and PALState.get_item_amount(201) == maxi(0, amount_201 - 1)
	print("[menu-test] ITEM_EQUIP equip found=%d head %d->%d defense %d->%d item196 %d->%d %s" % [
		found, head_before, head_after, defense_before, defense_after,
		amount_196, PALState.get_item_amount(196), "OK" if equip_ok else "FAIL"])
	if not equip_ok:
		pass_all = false
	# ---------- 使用：止血草(99) HP+50（100→150），数量 -1 ----------
	PALState.roles["hp"][0] = 100
	debug_open("item")
	await get_tree().process_frame
	var use_index := _debug_find_item(99)
	var amount_99 := PALState.get_item_amount(99)
	if use_index >= 0:
		debug_key(KEY_ENTER)      # 物品 → 使用对象
		await get_tree().process_frame
		debug_key(KEY_ENTER)      # 对象：李逍遥
		await _wait_frames(2)
	var hp_after := int(PALState.roles["hp"][0])
	var use_ok: bool = hp_after == 150 and PALState.get_item_amount(99) == amount_99 - 1
	print("[menu-test] ITEM_EQUIP use found=%d hp=%d item99 %d->%d %s" % [
		use_index, hp_after, amount_99, PALState.get_item_amount(99),
		"OK" if use_ok else "FAIL"])
	if not use_ok:
		pass_all = false
	print("[menu-test] ITEM_EQUIP %s" % ("PASS" if pass_all else "FAIL"))
	if not pass_all:
		_selftest_failed = true


## 重置到主菜单并打开指定页面，供截图脚本使用
func debug_open(which: String) -> void:
	_toast = ""
	_stack.clear()
	_stack.append(MainController.new())
	match which:
		"item":
			var inv = ITEM_MENU.InventoryMenu.new()
			inv.setup(self)
			_stack.append(inv)
			var sel = ITEM_MENU.ItemSelectController.new()
			sel.item_flags = 0x01
			sel.setup(self)
			_stack.append(sel)
		"magic":
			var mc = MAGIC_MENU.MagicController.new()
			mc.setup(self)
			_stack.append(mc)
		"status":
			var sc = STATUS_MENU.StatusController.new()
			sc.setup(self)
			_stack.append(sc)
		"equip":
			var ec = ITEM_MENU.ItemSelectController.new()
			ec.item_flags = 0x02
			ec.setup(self)
			_stack.append(ec)
		"system":
			var yc = SystemController.new()
			yc.setup(self)
			_stack.append(yc)
		"save":
			var yc2 = SystemController.new()
			yc2.setup(self)
			_stack.append(yc2)
			var sl = SlotController.new(true)
			sl.setup(self)
			_stack.append(sl)
		"load":
			var yc3 = SystemController.new()
			yc3.setup(self)
			_stack.append(yc3)
			var sl2 = SlotController.new(false)
			sl2.setup(self)
			_stack.append(sl2)
		"target":
			var tc = ITEM_MENU.ItemUseTargetController.new()
			tc.item_id = 99
			tc.setup(self)
			_stack.append(tc)
		"confirm":
			var cc = ScriptConfirmController.new()
			cc.setup(self)
			_stack.append(cc)
		_:
			pass
	# 栈底主菜单
	if _stack.size() > 0:
		_stack[0].setup(self)
	_rebuild()


func _make_inventory_menu() -> RefCounted:
	return ITEM_MENU.InventoryMenu.new()


## 自测用：在本菜单之上打开商店（world.script_shop 的等价路径；正常游戏由 World 负责）
func debug_open_shop(is_buy: bool = true) -> Node:
	_shop_node = load("res://game/shop.gd").new()
	var store := 0
	if PALTables != null:
		for i in range(PALTables.stores.size()):
			var arr: PackedInt32Array = PALTables.stores[i]
			if arr.size() > 0 and int(arr[0]) != 0:
				store = i
				break
	_shop_node.setup(store, is_buy)
	_shop_node.closed.connect(func() -> void: _shop_node = null)
	add_child(_shop_node)
	return _shop_node


var _shop_node: Node = null


## 自测/调试：隐藏菜单本体（让商店等独立层单独入镜）
func debug_set_menu_visible(v: bool) -> void:
	if _root != null:
		_root.visible = v


# 子菜单控制器工厂（menu_item.gd 内部也通过这两个工厂创建，避免同文件内跨类直接引用）
func make_item_select(flags: int) -> RefCounted:
	var c = ITEM_MENU.ItemSelectController.new()
	c.item_flags = flags
	c.setup(self)
	return c


## 装备流程入口：由物品列表点击“装备”进入（uigame.c PAL_EquipItemMenu）
func push_equip_item(item_id: int) -> void:
	var c = EQUIP_MENU.EquipItemController.new()
	c.item_id = item_id
	push_controller(c)


func make_magic_list(role: int) -> RefCounted:
	var c = MAGIC_MENU.MagicListController.new()
	c.role = role
	c.setup(self)
	return c


func make_magic_target(role: int, magic_obj_id: int) -> RefCounted:
	var c = MAGIC_MENU.MagicTargetController.new()
	c.role = role
	c.magic = magic_obj_id
	c.setup(self)
	return c


func make_item_use_target(item_id: int) -> RefCounted:
	var c = ITEM_MENU.ItemUseTargetController.new()
	c.item_id = item_id
	c.setup(self)
	return c


func _selftest_pages() -> void:
	await _wait_frames(4)
	_install_test_script_runner()
	# 物品使用 / 装备换装 效果断言（Lead 回归要求）
	await _selftest_item_equip()
	_seed_demo_state()
	debug_open("main")
	await _wait_frames(3)
	await _shot("00_main")
	debug_open("item")
	await _wait_frames(2)
	await _shot("01_item")
	debug_key(KEY_DOWN)
	debug_key(KEY_DOWN)
	await _wait_frames(2)
	await _shot("02_item_nav")
	debug_open("magic")
	await _wait_frames(2)
	await _shot("03_magic")
	debug_key(KEY_ENTER)          # 选角色 → 仙术列表
	await _wait_frames(2)
	await _shot("04_magic_list")
	debug_key(KEY_DOWN)
	await _wait_frames(2)
	await _shot("05_magic_list_nav")
	debug_open("status")
	await _wait_frames(2)
	await _shot("06_status")
	debug_key(KEY_RIGHT)
	await _wait_frames(2)
	await _shot("07_status_next")
	debug_open("save")
	await _wait_frames(2)
	await _shot("08_save")
	debug_key(KEY_ENTER)          # 实际存到槽 1
	await _wait_frames(3)
	await _shot("09_save_done")
	if _save_system_selftest():
		await _wait_frames(1)
		await _shot("09b_save_validate")
	debug_open("load")
	await _wait_frames(2)
	await _shot("10_load")
	debug_open("system")
	await _wait_frames(2)
	await _shot("11_system")
	debug_open("equip")
	await _wait_frames(2)
	await _shot("12_equip_list")
	debug_key(KEY_ENTER)          # 进入装备界面
	await _wait_frames(2)
	await _shot("13_equip_item")
	# 商店（等价 world.script_shop 路径）：买/卖两页；先隐藏菜单本体避免叠影
	debug_set_menu_visible(false)
	var shop := debug_open_shop(true)
	if shop != null:
		await _wait_frames(3)
		await _shot("14_shop_buy")
		shop.debug_key(KEY_DOWN)
		await _wait_frames(2)
		await _shot("15_shop_buy_nav")
		shop.close_shop()
		await _wait_frames(2)
		shop = debug_open_shop(false)
		if shop != null:
			await _wait_frames(3)
			await _shot("16_shop_sell")
			shop.close_shop()
			await _wait_frames(2)
	debug_set_menu_visible(true)
	debug_open("target")
	await _wait_frames(2)
	await _shot("17_use_target")
	# 0x000A 确认框：截图 + “是”选择路径（World 的 request_confirm_y/n 用同一控件）
	debug_open("confirm")
	_last_choice = false
	await _wait_frames(2)
	await _shot("18_confirm")
	debug_key(KEY_RIGHT)
	debug_key(KEY_ENTER)
	await _wait_frames(2)
	var confirm_ok := _last_choice and _stack.size() == 1
	print("[menu-test] CONFIRM yes=%s depth=%d %s" % [
		str(_last_choice), _stack.size(), "OK" if confirm_ok else "FAIL"])
	if not confirm_ok:
		_selftest_failed = true
	# 模拟 World.request_confirm 的真实调用顺序：先 add_child（_ready 建默认主菜单），
	# 再 setup_confirm("")；验证后配置路径能切成确认框并返回“否”。
	var wc = load("res://game/menu.gd").new()
	add_child(wc)
	await _wait_frames(2)
	wc.setup_confirm("测试：AddChild 之后配置确认框")
	await _wait_frames(2)
	await _shot("19_confirm_world_order")
	var wc_choice := {"yes": null}
	wc.choice_made.connect(func(y: bool) -> void: wc_choice["yes"] = y)
	wc.debug_key(KEY_ENTER)      # 默认光标在“否”
	await _wait_frames(2)
	var order_ok: bool = wc_choice["yes"] == false
	print("[menu-test] CONFIRM_WORLD_ORDER yes=%s %s" % [
		str(wc_choice["yes"]), "OK" if order_ok else "FAIL"])
	if not order_ok:
		_selftest_failed = true
	if is_instance_valid(wc):
		wc.close_menu()
	# 真实键盘导航冒烟：主菜单 → 状态/仙术/物品/系统 → 各回退 → Esc 关闭
	await _selftest_navigation()
	print("[menu-test] PAGES DONE shots=%d failed=%s" % [_shot_index, str(_selftest_failed)])
	if _selftest_failed:
		get_tree().quit(1)
		return
	debug_key(KEY_ESCAPE)   # 主菜单上 Esc = 关闭菜单并 emit closed（World 复位 player_busy）


## 用 debug_key 走完整导航路径（与实际玩家按键同一条派发路径），并断言栈深度。
## 注意：sdlpal 会记住主菜单/系统菜单上次位置（iCurMainMenuItem/iCurSystemMenuItem），
## 因此每个用例前先重置索引，保证断言确定。
func _selftest_navigation() -> void:
	var ok := 0
	var fail := 0
	# [起始页, 按键序列, 预期栈深度]
	var cases: Array = [
		["main", [KEY_ENTER], 2],                       # 状态
		["main", [KEY_DOWN, KEY_ENTER, KEY_ENTER], 3],  # 仙术 → 角色 → 法术列表
		["main", [KEY_DOWN, KEY_DOWN, KEY_ENTER, KEY_ENTER], 3],  # 物品 → 二级 → 列表
		["main", [KEY_DOWN, KEY_DOWN, KEY_DOWN, KEY_ENTER, KEY_ENTER], 3],  # 系统 → 存档槽
	]
	var step := 0
	for case in cases:
		_reset_nav_indices()
		debug_open(str(case[0]))
		await get_tree().process_frame
		for k in case[1]:
			debug_key(int(k))
			await get_tree().process_frame
		var depth := _stack.size()
		if depth == int(case[2]):
			ok += 1
			print("[menu-test] NAV step%d keys=%s depth=%d OK" % [step, str(case[1]), depth])
		else:
			fail += 1
			print("[menu-test] NAV step%d keys=%s depth=%d EXPECTED=%d FAIL" % [
				step, str(case[1]), depth, int(case[2])])
		# 逐级 Esc 回主菜单（同时验证返回路径）
		for _i in range(depth + 1):
			if _stack.size() <= 1:
				break
			debug_key(KEY_ESCAPE)
			await get_tree().process_frame
		if _stack.size() != 1:
			fail += 1
			print("[menu-test] NAV step%d BACK depth=%d EXPECTED=1 FAIL" % [step, _stack.size()])
		step += 1
	print("[menu-test] NAV %s" % ("PASS" if fail == 0 else "FAIL"))
	if fail != 0:
		_selftest_failed = true


func _reset_nav_indices() -> void:
	_main_index = 0
	_system_index = 0


## 打印存档结构校验/兼容性证据（返回是否通过基本校验）
func _save_system_selftest() -> bool:
	var v: Dictionary = SAVE_SYSTEM.validate(1)
	var info: Dictionary = SAVE_SYSTEM.slot_summary(1)
	print("[menu-test] SAVE_VALIDATE ", JSON.stringify(v))
	print("[menu-test] SAVE_INFO ", JSON.stringify(info))
	print("[menu-test] SAVE_LAYOUT ", JSON.stringify(SAVE_SYSTEM.layout()))
	print("[menu-test] SAVE_COMPAT ", SAVE_SYSTEM.compatibility_note())
	return bool(v.get("ok", false))


## 存/读档往返：
##   roundtrip            = 单进程：改值→存→再改→读→断言
##   roundtrip-save       = 第一进程：写已知值并存槽 5，写期望 JSON
##   roundtrip-load       = 第二进程（重开）：读槽 5，与期望 JSON 比对
func _selftest_roundtrip(mode: String) -> void:
	await _wait_frames(4)
	var exp_path := "user://menu_roundtrip_expected.json"
	var slot := 5
	if mode.contains("load"):
		var expected: Dictionary = {}
		if FileAccess.file_exists(exp_path):
			var fa := FileAccess.open(exp_path, FileAccess.READ)
			var parsed = JSON.parse_string(fa.get_as_text())
			fa.close()
			if typeof(parsed) == TYPE_DICTIONARY:
				expected = parsed
		var ok := PALState.load_game(slot)
		var checks := {
			"cash": int(PALState.cash),
			"level0": int(PALState.roles["level"][0]),
			"item99": int(PALState.get_item_amount(99)),
			"item101": int(PALState.get_item_amount(101)),
			"scene": int(PALState.scene),
			"max_party": int(PALState.max_party_member_index),
		}
		var pass_all := ok
		for k in checks.keys():
			if expected.has(k) and int(expected[k]) != int(checks[k]):
				pass_all = false
				print("[menu-test] ROUNDTRIP_MISMATCH %s expected=%s actual=%s" % [
					k, expected[k], checks[k]])
		print("[menu-test] ROUNDTRIP load ok=%s values=%s" % [ok, JSON.stringify(checks)])
		print("[menu-test] ROUNDTRIP %s" % ("PASS" if pass_all else "FAIL"))
		if not pass_all:
			get_tree().quit(1)
			return
		close_menu()
		return

	# 第一阶段（或单进程往返）
	_seed_demo_state()
	PALState.cash = 7654
	PALState.scene = 12
	PALState.roles["level"][0] = 9
	PALState.roles["hp"][0] = 111
	PALState.roles["mp"][0] = 22
	PALState.max_party_member_index = 2
	PALState.party[1]["role"] = 1
	PALState.party[2]["role"] = 2
	PALState.add_item(99, 7)
	PALState.add_item(101, 3)
	var saved := PALState.save_game(slot)
	var snapshot := {
		"cash": int(PALState.cash),
		"level0": int(PALState.roles["level"][0]),
		"item99": int(PALState.get_item_amount(99)),
		"item101": int(PALState.get_item_amount(101)),
		"scene": int(PALState.scene),
		"max_party": int(PALState.max_party_member_index),
		"hp0": int(PALState.roles["hp"][0]),
		"mp0": int(PALState.roles["mp"][0]),
	}
	if mode.contains("save"):
		var fa := FileAccess.open(exp_path, FileAccess.WRITE)
		if fa != null:
			fa.store_string(JSON.stringify(snapshot))
			fa.close()
		print("[menu-test] ROUNDTRIP save ok=%s snapshot=%s" % [saved, JSON.stringify(snapshot)])
		print("[menu-test] ROUNDTRIP SAVE-PHASE DONE")
		close_menu()
		return

	# 单进程往返：故意改乱内存后读档恢复
	PALState.cash = 1
	PALState.roles["level"][0] = 2
	PALState.add_item(99, -7)
	PALState.scene = 1
	var loaded := PALState.load_game(slot)
	var pass_all := saved and loaded
	for k in snapshot.keys():
		var actual := 0
		match k:
			"cash":
				actual = int(PALState.cash)
			"level0":
				actual = int(PALState.roles["level"][0])
			"item99":
				actual = int(PALState.get_item_amount(99))
			"item101":
				actual = int(PALState.get_item_amount(101))
			"scene":
				actual = int(PALState.scene)
			"max_party":
				actual = int(PALState.max_party_member_index)
			"hp0":
				actual = int(PALState.roles["hp"][0])
			"mp0":
				actual = int(PALState.roles["mp"][0])
		if int(snapshot[k]) != actual:
			pass_all = false
			print("[menu-test] ROUNDTRIP_MISMATCH %s expected=%d actual=%d" % [
				k, int(snapshot[k]), actual])
	print("[menu-test] ROUNDTRIP save=%s load=%s values=%s" % [saved, loaded, JSON.stringify(snapshot)])
	print("[menu-test] ROUNDTRIP %s" % ("PASS" if pass_all else "FAIL"))
	if not pass_all:
		get_tree().quit(1)
		return
	close_menu()
