extends Control
## 标题画面（移植 main.c 开场菜单 / PAL_OpeningMenu 的三项结构）。
## 背景：Fbp.mkf 第 0 块（320×200 压缩图），按 PAT.mkf 0 号调色板着色。
## 菜单项文字：原版词条来自 Word.dat，本移植阶段先用等价中文（记录为未知项）。
##
## 「旧的回忆」→ 弹出 5 槽读档列表（原版 PAL_LoadGameMenu 行为）：
##   ↑↓ 选槽；空格/回车 读取选中槽；Esc 返回标题菜单。
##   空槽显示「（空）」，确认时只提示、不加载；槽位摘要复用 save_system.slot_summary
##   （与游戏内菜单同一套数据/判定，避免两套逻辑行为不一致）。

signal start_requested
signal load_requested(slot: int)
signal quit_requested

const MENU_ITEMS := ["新的故事", "旧的回忆", "结束游戏"]
## 原版 WIN95 开场画面块号（sdlpal main.c）：FBP 3/4 为上/下半屏，MGO 0x47 标题字。
const SPLASH_FBP_UP := 3
const SPLASH_MGO_TITLE := 0x47
## 手动存档槽数（原版 5 个：1.rpg..5.rpg ↔ user://pal_save_<slot>.sav）
const SLOT_COUNT := 5
const SLOT_NAMES := ["进度一", "进度二", "进度三", "进度四", "进度五"]
const SAVE_SYSTEM := preload("res://game/save_system.gd")

enum Mode { MENU, LOAD }

var _index: int = 0
var _labels: Array[Label] = []
var _bg: Sprite2D
var _palette: PackedColorArray
var _tip: Label
var _font: SystemFont
var _mode: int = Mode.MENU
var _load_panel: Control
var _load_rows: Array[Label] = []
var _load_tip: Label
var _load_index: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dir := PalConfig.data_dir()
	if dir != "":
		_palette = PalMap.load_palette(MkfFile.open_asset(dir, "Pat.mkf"), 1)
		var fbp := MkfFile.open_asset(dir, "Fbp.mkf")
		var mgo := MkfFile.open_asset(dir, "Mgo.mkf")
		if fbp != null:
			var bg_img := _decode_fbp(fbp, SPLASH_FBP_UP)
			if bg_img != null:
				var logo: Image = null
				if mgo != null:
					var raw := mgo.decompressed(SPLASH_MGO_TITLE)
					var frames := PalSprite.decode_sprite(raw, _palette)
					if frames.size() > 0:
						logo = frames[0]
				if logo != null:
					var lx := (320 - logo.get_width()) / 2
					bg_img.blend_rect(logo, Rect2i(0, 0, logo.get_width(), logo.get_height()),
						Vector2i(maxi(0, lx), 40))
				_bg = Sprite2D.new()
				_bg.centered = false
				_bg.scale = Vector2(2, 2)
				_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				_bg.texture = ImageTexture.create_from_image(bg_img)
				add_child(_bg)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "SimSun", "SimHei"])
	_font = font
	for i in range(MENU_ITEMS.size()):
		var l := Label.new()
		l.text = MENU_ITEMS[i]
		l.position = Vector2(360, 250 + i * 44)
		l.size = Vector2(260, 40)
		l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", 26)
		l.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("shadow_offset_x", 2)
		l.add_theme_constant_override("shadow_offset_y", 2)
		add_child(l)
		_labels.append(l)
	var tip := Label.new()
	tip.text = "↑↓ 选择   空格/回车 确定"
	tip.position = Vector2(24, 362)
	tip.add_theme_font_override("font", font)
	tip.add_theme_font_size_override("font_size", 16)
	tip.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	add_child(tip)
	_tip = tip
	_build_load_panel()
	_refresh()


## 扫描 5 个存档槽，返回第一个存在的槽位；0 = 没有存档。
## 保留此函数给自动化/存档锚点脚本判断"是否有档"；玩家入口改走列表选择。
func find_save_slot() -> int:
	for slot in range(1, SLOT_COUNT + 1):
		if FileAccess.file_exists("user://pal_save_%d.sav" % slot):
			return slot
	return 0


## 读档列表：全屏压暗 + 5 行槽位摘要。开始隐藏，选「旧的回忆」才显示。
func _build_load_panel() -> void:
	_load_panel = Control.new()
	_load_panel.name = "LoadPanel"
	_load_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_panel.visible = false
	add_child(_load_panel)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_panel.add_child(dim)

	var header := Label.new()
	header.text = "读 取 进 度"
	header.position = Vector2(80, 62)
	header.size = Vector2(480, 44)
	header.add_theme_font_override("font", _font)
	header.add_theme_font_size_override("font_size", 30)
	header.add_theme_color_override("font_color", Color(1, 0.95, 0.4))
	header.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	header.add_theme_constant_override("shadow_offset_x", 2)
	header.add_theme_constant_override("shadow_offset_y", 2)
	_load_panel.add_child(header)

	for i in range(SLOT_COUNT):
		var row := Label.new()
		row.position = Vector2(80, 128 + i * 44)
		row.size = Vector2(500, 38)
		row.add_theme_font_override("font", _font)
		row.add_theme_font_size_override("font_size", 20)
		row.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		row.add_theme_constant_override("shadow_offset_x", 2)
		row.add_theme_constant_override("shadow_offset_y", 2)
		_load_panel.add_child(row)
		_load_rows.append(row)

	_load_tip = Label.new()
	_load_tip.position = Vector2(80, 358)
	_load_tip.size = Vector2(500, 30)
	_load_tip.add_theme_font_override("font", _font)
	_load_tip.add_theme_font_size_override("font_size", 16)
	_load_tip.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_load_panel.add_child(_load_tip)


## 刷新 5 行槽位文本：存在则「进度N  场景X  次数Y  时间」，否则「进度N  （空）」。
func _refresh_load_rows() -> void:
	for i in range(SLOT_COUNT):
		if i >= _load_rows.size():
			return
		var info: Dictionary = SAVE_SYSTEM.slot_summary(i + 1)
		var line: String = SLOT_NAMES[i]
		if bool(info.get("exists", false)):
			line += "   场景 %d   存档次数 %d   %s" % [
				int(info.get("scene", 0)), int(info.get("saved_times", 0)),
				str(info.get("time_text", ""))]
			if not bool(info.get("compatible", true)):
				line += "  [格式存疑]"
		else:
			line += "   （空）"
		var selected := i == _load_index
		_load_rows[i].text = ("▶ " if selected else "  ") + line
		_load_rows[i].add_theme_color_override("font_color",
			Color(1, 0.95, 0.4) if selected else Color(0.75, 0.72, 0.6))
	_load_tip.text = "↑↓ 选择   空格/回车 读取   Esc 返回"


## 打开读档列表：默认停在第一个有存档的槽（保留"继续上次进度"的顺手路径）。
func _open_load() -> void:
	_mode = Mode.LOAD
	_load_index = 0
	for i in range(SLOT_COUNT):
		var info: Dictionary = SAVE_SYSTEM.slot_summary(i + 1)
		if bool(info.get("exists", false)):
			_load_index = i
			break
	_refresh_load_rows()
	_load_panel.visible = true
	for l in _labels:
		l.visible = false
	_tip.visible = false


## 关闭读档列表，回到标题菜单三项。
func _close_load() -> void:
	_mode = Mode.MENU
	_load_panel.visible = false
	for l in _labels:
		l.visible = true
	_tip.visible = true


func _decode_fbp(fbp: MkfFile, chunk: int) -> Image:
	var raw := fbp.decompressed(chunk)
	if raw.size() < 320 * 200:
		return null
	var img := Image.create_empty(320, 200, false, Image.FORMAT_RGBA8)
	var pal := _palette
	# 标题背景里索引 0 视作不透明黑（原版整屏直接输出调色板颜色）
	pal[0] = Color(0, 0, 0, 1)
	for y in range(200):
		for x in range(320):
			img.set_pixel(x, y, pal[raw[y * 320 + x]])
	return img


func _refresh() -> void:
	for i in range(_labels.size()):
		var selected := i == _index
		_labels[i].add_theme_color_override("font_color",
			Color(1, 0.95, 0.4) if selected else Color(0.75, 0.72, 0.6))


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: int = event.keycode
	if _mode == Mode.LOAD:
		_handle_load_key(key)
		get_viewport().set_input_as_handled()
		return
	match key:
		KEY_UP, KEY_W:
			_index = (_index + MENU_ITEMS.size() - 1) % MENU_ITEMS.size()
			_refresh()
			get_viewport().set_input_as_handled()
		KEY_DOWN, KEY_S:
			_index = (_index + 1) % MENU_ITEMS.size()
			_refresh()
			get_viewport().set_input_as_handled()
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			match _index:
				0:
					start_requested.emit()
				1:
					_open_load()
				2:
					quit_requested.emit()
			get_viewport().set_input_as_handled()


## 读档列表内的按键：↑↓/WS 选槽，空格/回车 读取，Esc 返回标题菜单。
func _handle_load_key(key: int) -> void:
	match key:
		KEY_UP, KEY_W:
			_load_index = (_load_index + SLOT_COUNT - 1) % SLOT_COUNT
			_refresh_load_rows()
		KEY_DOWN, KEY_S:
			_load_index = (_load_index + 1) % SLOT_COUNT
			_refresh_load_rows()
		KEY_ESCAPE:
			_close_load()
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			_confirm_load()


func _confirm_load() -> void:
	var slot := _load_index + 1
	var info: Dictionary = SAVE_SYSTEM.slot_summary(slot)
	if not bool(info.get("exists", false)):
		_load_tip.text = "进度%s 是空槽：请用 ↑↓ 换一个进度，或按 Esc 返回" % [
			["一", "二", "三", "四", "五"][_load_index]]
		return
	load_requested.emit(slot)
