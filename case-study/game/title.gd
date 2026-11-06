extends Control
## 标题画面（移植 main.c 开场菜单 / PAL_OpeningMenu 的三项结构）。
## 背景：Fbp.mkf 第 0 块（320×200 压缩图），按 PAT.mkf 0 号调色板着色。
## 菜单项文字：原版词条来自 Word.dat，本移植阶段先用等价中文（记录为未知项）。

signal start_requested
signal load_requested(slot: int)
signal quit_requested

const MENU_ITEMS := ["新的故事", "旧的回忆", "结束游戏"]
## 原版 WIN95 开场画面块号（sdlpal main.c）：FBP 3/4 为上/下半屏，MGO 0x47 标题字。
const SPLASH_FBP_UP := 3
const SPLASH_MGO_TITLE := 0x47

var _index: int = 0
var _labels: Array[Label] = []
var _bg: Sprite2D
var _palette: PackedColorArray
var _tip: Label


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
	_refresh()


## 扫描 5 个存档槽，返回第一个存在的槽位；0 = 没有存档。
func find_save_slot() -> int:
	for slot in range(1, 6):
		if FileAccess.file_exists("user://pal_save_%d.sav" % slot):
			return slot
	return 0


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
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
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
						var slot := find_save_slot()
						if slot > 0:
							load_requested.emit(slot)
						elif _tip != null:
							_tip.text = "没有存档（读档 UI 由游戏内菜单提供）"
					2:
						quit_requested.emit()
				get_viewport().set_input_as_handled()
