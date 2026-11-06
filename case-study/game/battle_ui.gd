class_name BattleUI
extends CanvasLayer
## 战斗画面渲染（320×200 游戏帧缓冲 + 640×400 覆盖层 UI）。
##
## 对应 sdlpal battle.c / uibattle.c：
##   * 场景帧缓冲 = 320×200：先画 FBP 战场背景，再按 pos.y 排序画我方/敌方/法术精灵；
##   * UI 层（菜单图标、玩家 HP/MP 框、伤害数字、提示文字）叠加在帧缓冲之上。
## 移植约定：
##   * 帧缓冲坐标 = 游戏坐标（320×200），显示时整体 ×2（与 game/world.gd 一致，nearest 过滤）；
##   * 文字/数字用 Label（system 字体），位置换算到 640×400 屏幕坐标；
##   * 调色板脉冲（sdlpal iColorShift）用叠加半透明色块近似 [inf]——原版是调色板偏移，
##     同一像素只能有一个调色板索引，本实现以 RGBA 直接绘制，只能近似表现受击闪白/红。

const GAME_W := 320
const GAME_H := 200
const SCALE := 2
const SHOT_DIR := "<LOCAL_PATH>"

const COLOR_NORMAL := Color(1, 1, 1, 1)
const COLOR_SELECTED := Color(1.0, 0.85, 0.25, 1.0)
const COLOR_DISABLED := Color(0.55, 0.55, 0.55, 1.0)
const COLOR_CONFIRMED := Color(0.4, 0.9, 1.0, 1.0)
const COLOR_DAMAGE := Color(1.0, 0.9, 0.3, 1.0)
const COLOR_HEAL := Color(0.4, 1.0, 0.5, 1.0)
const COLOR_MP := Color(0.4, 0.85, 1.0, 1.0)
const COLOR_MISS := Color(0.8, 0.8, 0.8, 1.0)

var battle: Node = null

var _screen: Sprite2D
var _img: Image
var _tex: ImageTexture
var _bg: Image
var _arrow_pool: Array[Label] = []
var _numbers: Array[Dictionary] = []
var _flash_cache: Dictionary = {}

var _font: SystemFont
var _msg: Label
var _title: Label
var _list_labels: Array[Label] = []
var _main_icons: Array[Label] = []
var _player_labels: Array[Label] = []
var _fade: ColorRect
var _hint: Label


func _ready() -> void:
	layer = 50
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei", "SimSun", "SimHei"])
	_build_nodes()


func _build_nodes() -> void:
	_img = Image.create_empty(GAME_W, GAME_H, false, Image.FORMAT_RGBA8)
	_img.fill(Color(0, 0, 0, 1))
	_tex = ImageTexture.create_from_image(_img)
	_screen = Sprite2D.new()
	_screen.name = "BattleScreen"
	_screen.centered = false
	_screen.texture = _tex
	_screen.scale = Vector2(SCALE, SCALE)
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_screen)

	_title = _make_label(Vector2(0, 8), Vector2(640, 28), 20, COLOR_CONFIRMED, HORIZONTAL_ALIGNMENT_CENTER)
	_title.visible = false

	_msg = _make_label(Vector2(20, 120), Vector2(600, 90), 20, COLOR_NORMAL, HORIZONTAL_ALIGNMENT_CENTER)
	_msg.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_msg.visible = false

	# 主菜单：四向图标（sdlpal 用 SPRITENUM_BATTLEICON_*，此处用文字等价物）
	var icon_pos := [Vector2(52, 280), Vector2(8, 318), Vector2(96, 318), Vector2(52, 356)]
	for i in range(4):
		var l := _make_label(icon_pos[i], Vector2(56, 34), 20, COLOR_NORMAL, HORIZONTAL_ALIGNMENT_CENTER)
		_main_icons.append(l)
		l.visible = false

	# 列表菜单（仙术/物品/杂项）：最多 8 行（放中上部，避免压住底部状态行）
	for i in range(8):
		var l := _make_label(Vector2(220, 112 + i * 24), Vector2(400, 24), 18, COLOR_NORMAL, HORIZONTAL_ALIGNMENT_LEFT)
		_list_labels.append(l)
		l.visible = false

	# 底部玩家信息框：最多 3 人，x = (91 + 77*i) * 2
	for i in range(3):
		var l := _make_label(Vector2(172 + 154 * i, 350), Vector2(170, 46), 14, COLOR_NORMAL, HORIZONTAL_ALIGNMENT_LEFT)
		_player_labels.append(l)
		l.visible = false

	for i in range(5):
		var arrow := _make_label(Vector2(-100, -100), Vector2(40, 30), 22, COLOR_SELECTED, HORIZONTAL_ALIGNMENT_CENTER)
		arrow.text = "▼"
		arrow.visible = false
		_arrow_pool.append(arrow)

	_hint = _make_label(Vector2(8, 4), Vector2(624, 20), 14, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_RIGHT)
	_hint.text = "方向键选择  空格确认  ESC取消（攻击↑ 仙术← 合击→ 其他↓）"
	_hint.visible = false

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)

	var font := _font


func _make_label(pos: Vector2, size: Vector2, font_size: int, color: Color, align: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = size
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", _font)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


# ------------------------------------------------------------------ 帧缓冲

func set_background(bg: Image) -> void:
	_bg = bg
	if _bg != null:
		_img.copy_from(_bg)


## 合成一帧：背景 + 精灵序列（按传入顺序，调用方已按 pos.y 排序）。
## draw_list 元素：{img: Image, x: int, y: int, flash: bool}
func render(draw_list: Array) -> void:
	if _bg != null:
		_img.copy_from(_bg)
	for d in draw_list:
		if d.is_empty():
			continue
		var img: Image = d.get("img")
		if img == null or img.get_width() <= 0 or img.get_height() <= 0:
			continue
		var x := int(d.get("x", 0))
		var y := int(d.get("y", 0))
		_blit_clipped(img, x, y)
		if bool(d.get("flash", false)):
			_overlay_flash(img, x, y, d.get("flash_color", Color(1, 0.25, 0.2, 0.45)))
	if _tex != null:
		_tex.update(_img)


func _blit_clipped(src: Image, x: int, y: int) -> void:
	var w := src.get_width()
	var h := src.get_height()
	var sx0 := maxi(0, -x)
	var sy0 := maxi(0, -y)
	if sx0 >= w or sy0 >= h:
		return
	var dw := mini(w - sx0, GAME_W - x - sx0)
	var dh := mini(h - sy0, GAME_H - y - sy0)
	if dw <= 0 or dh <= 0:
		return
	_img.blend_rect(src, Rect2i(sx0, sy0, dw, dh), Vector2i(x + sx0, y + sy0))


func _overlay_flash(src: Image, x: int, y: int, color: Color) -> void:
	# 只对精灵不透明像素做染色，避免在精灵包围盒上出现色块
	var w := src.get_width()
	var h := src.get_height()
	var sx0 := maxi(0, -x)
	var sy0 := maxi(0, -y)
	var ex := mini(w, GAME_W - x)
	var ey := mini(h, GAME_H - y)
	if sx0 >= ex or sy0 >= ey:
		return
	var a := color.a
	for py in range(sy0, ey):
		for px in range(sx0, ex):
			if src.get_pixel(px, py).a <= 0.0:
				continue
			var c := _img.get_pixel(x + px, y + py)
			_img.set_pixel(x + px, y + py, c.lerp(Color(color.r, color.g, color.b, 1.0), a))


# ------------------------------------------------------------------ 文字/菜单

func set_message(text: String, visible: bool = true) -> void:
	_msg.text = text
	_msg.visible = visible
	_msg.modulate = Color(1, 1, 1, 1)


func set_title(text: String, visible: bool = true) -> void:
	_title.text = text
	_title.visible = visible


func hide_menus() -> void:
	for l in _main_icons:
		l.visible = false
	for l in _list_labels:
		l.visible = false
	_title.visible = false
	_hint.visible = false
	for a in _arrow_pool:
		a.visible = false


## 主菜单：items 长度 4（攻击/仙术/合击/其他），selected 为下标，disabled 为下标数组。
func set_main_menu(items: Array, selected: int, disabled: Array = []) -> void:
	_hint.visible = true
	for i in range(_main_icons.size()):
		var l := _main_icons[i]
		if i >= items.size():
			l.visible = false
			continue
		l.visible = true
		l.text = str(items[i])
		if i == selected:
			l.add_theme_color_override("font_color", COLOR_SELECTED)
		elif i in disabled:
			l.add_theme_color_override("font_color", COLOR_DISABLED)
		else:
			l.add_theme_color_override("font_color", COLOR_NORMAL)


## 列表菜单（垂直）。selected = -1 表示仅展示。
func set_list_menu(title_text: String, items: PackedStringArray, selected: int, enabled: Array = []) -> void:
	_hint.visible = true
	set_title(title_text, title_text != "")
	for i in range(_list_labels.size()):
		var l := _list_labels[i]
		if i >= items.size():
			l.visible = false
			continue
		l.visible = true
		l.text = ("▶ " if i == selected else "   ") + items[i]
		if i == selected:
			l.add_theme_color_override("font_color", COLOR_SELECTED)
		elif not enabled.is_empty() and not (i in enabled):
			l.add_theme_color_override("font_color", COLOR_DISABLED)
		else:
			l.add_theme_color_override("font_color", COLOR_NORMAL)


## 目标箭头：list 为若干 {x, y, w, h}（游戏坐标，x/y 为精灵左上角）。
func set_arrows(targets: Array) -> void:
	for i in range(_arrow_pool.size()):
		var a := _arrow_pool[i]
		if i >= targets.size():
			a.visible = false
			continue
		var t: Dictionary = targets[i]
		var gx := int(t.get("x", 0)) + int(t.get("w", 0)) / 2
		var gy := int(t.get("y", 0)) - 14
		a.position = Vector2(gx * SCALE - 20, maxf(0, gy * SCALE))
		a.visible = true


## 玩家信息框（sdlpal uibattle.c PAL_PlayerInfoBox 的简化文字版）。
## rows 元素：{name, hp, max_hp, mp, max_mp, status: PackedStringArray}
func update_player_panels(rows: Array) -> void:
	for i in range(_player_labels.size()):
		var l := _player_labels[i]
		if i >= rows.size():
			l.visible = false
			continue
		var r: Dictionary = rows[i]
		l.visible = true
		var status := ""
		var st = r.get("status", [])
		if st is Array and st.size() > 0:
			status = " [" + " ".join(PackedStringArray(st)) + "]"
		l.text = "%s Lv%s\nHP %s/%s  MP %s/%s%s" % [
			str(r.get("name", "")), str(r.get("level", "")),
			str(r.get("hp", 0)), str(r.get("max_hp", 0)),
			str(r.get("mp", 0)), str(r.get("max_mp", 0)), status,
		]


## 战斗内飘字（伤害/回复）。坐标 = 游戏坐标。
func show_number(value: int, gx: int, gy: int, color: Color = COLOR_DAMAGE) -> void:
	var text := str(value)
	if value > 0 and color == COLOR_HEAL:
		text = "+" + text
	if value < 0:
		text = str(-value)
	var l := Label.new()
	l.text = text
	l.position = Vector2(gx * SCALE, gy * SCALE)
	l.size = Vector2(100, 30)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", _font)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	_numbers.append({"label": l, "life": 22})


## sdlpal 的“显示了数字”判定：一个动作里可能同时显示多个数字。
func clear_numbers() -> void:
	for n in _numbers:
		var l: Label = n["label"]
		if is_instance_valid(l):
			l.queue_free()
	_numbers.clear()


func _process(_delta: float) -> void:
	for i in range(_numbers.size() - 1, -1, -1):
		var n: Dictionary = _numbers[i]
		var l: Label = n["label"]
		if not is_instance_valid(l):
			_numbers.remove_at(i)
			continue
		n["life"] = int(n["life"]) - 1
		l.position.y -= 0.8
		l.modulate.a = clampf(float(n["life"]) / 22.0, 0.0, 1.0)
		if int(n["life"]) <= 0:
			l.queue_free()
			_numbers.remove_at(i)


# ------------------------------------------------------------------ 淡入淡出 / 截图

func fade_from_black() -> void:
	_fade.visible = true
	_fade.color = Color(0, 0, 0, 1)
	var tween := create_tween()
	tween.tween_property(_fade, "color", Color(0, 0, 0, 0), 0.6)
	await tween.finished


func fade_to_black() -> void:
	_fade.visible = true
	_fade.color = Color(0, 0, 0, 0)
	var tween := create_tween()
	tween.tween_property(_fade, "color", Color(0, 0, 0, 1), 0.6)
	await tween.finished


func screenshot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var vp := get_viewport()
	if vp == null:
		return
	var shot := vp.get_texture().get_image()
	if shot == null:
		return
	var path := SHOT_DIR + "battle_%s.png" % tag
	shot.save_png(path)
	print("[battle] SHOT ", path)
