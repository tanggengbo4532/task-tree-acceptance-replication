class_name DialogBox
extends Control
## 320×200 像素风对话框（移植 sdlpal text.c 的 PAL_StartDialog / PAL_ShowDialogText /
## PAL_DialogWaitForKey / PAL_ClearDialog / PAL_EndDialog + TEXT_DisplayText 控制码）。
##
## 坐标/排版严格对齐 text.c：
##   kDialogUpper   标题 (12,8)  文本 (44,26)    有头像时 (80,8)/(96,26)
##   kDialogCenter  文本 (80,40)（无边框）
##   kDialogLower   标题 (12,108) 文本 (44,126)  有头像时 (4,108)/(20,126)
##   kDialogCenterWindow 单行小窗，居中，1.4s 后自动关闭
##   行高 18px，每页 4 行（text.c: nCurrentDialogLine > 3 时 PAL_DialogWaitForKey）
##   文字带三重黑影（sdlpal PAL_DrawTextUnescape 的 fShadow 分支）
##
## 说明 1：sdlpal 原版对 kDialogUpper/kDialogLower 并**不绘制**边框/底色（文字直接叠在场景上），
##   本移植按任务要求提供像素框（可 set_boxed(false) 关闭以还原 sdlpal 行为）。
## 说明 2：sdlpal 的对话文本是瞬间整行出现（isDialog=TRUE 时不做逐字延时）；本移植按任务
##   要求加入逐字打字机（速度由 `$NN` 控制，缺省 24ms/字），按键可跳过 → 记录为增强/偏差。
##
## 用法（World hook 建议）：
##   var box := DialogBox.new(); ui.add_child(box); box.scale = Vector2(2, 2)   # 320×200 → 640×400
##   # script_dialog 时：box.push_line(text)
##   # 按键时：if box.advance(): pass   # 消费按键（打字中→立即显示；否则翻页/关闭）
##   # 也可 await box.show_text(text) 等待整段对白关闭；await box.show_choice() 取得是/否

signal advanced
signal closed
signal page_turned
signal choice_made(yes: bool)

enum Style {
	UPPER = 0,        # kDialogUpper
	CENTER = 1,       # kDialogCenter
	LOWER = 2,        # kDialogLower
	CENTER_WINDOW = 3, # kDialogCenterWindow
}

const SCREEN_W := 320
const SCREEN_H := 200
const FONT_SIZE := 16
const LINE_HEIGHT := 18
const LINES_PER_PAGE := 4

const BOX_FILL := Color8(10, 12, 26, 236)
const BOX_BORDER := Color8(196, 184, 172)
const BOX_INNER := Color8(86, 74, 52, 200)
const SHADOW := Color8(0, 0, 0)
const CHOICE_CURSOR := Color8(255, 236, 150)

var style: int = Style.UPPER
var boxed: bool = true
var capture_input: bool = false
var font: Font = null
var face_id: int = 0
var lines_per_page: int = LINES_PER_PAGE
## 对白基础字色（sdlpal PAL_StartDialog 的 bFontColor；0 表示用默认色 FONT_COLOR_DEFAULT）
var base_color: int = 0

var _active: bool = false
var _typing: bool = false
var _waiting: bool = false
var _visible: int = 0
var _type_accum: float = 0.0
var _next_delay: int = 24
var _icon: int = 0
var _icon_blink: float = 0.0
var _auto_close: float = -1.0

var _cur_lines: Array = []          # 当前页：Array[Array[token]]
var _pending_lines: Array = []      # 溢出到下一页的行
var _title_tokens: Array = []
var _flat: Array = []               # 当前页（含标题）的扁平 token 流，用于打字机计数

var _face_tex: ImageTexture = null
var _choice_active: bool = false
var _choice_yes: String = "是"
var _choice_no: String = "否"
var _choice_sel: int = 0


func _ready() -> void:
	size = Vector2(SCREEN_W, SCREEN_H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if font == null:
		font = _make_default_font()
	set_process(true)


func _make_default_font() -> Font:
	var f := SystemFont.new()
	# 宋体是原版 16×16 点阵字形的最近似系统字体；缺省回退雅黑/黑体
	f.font_names = PackedStringArray(["SimSun", "NSimSun", "宋体", "Microsoft YaHei", "SimHei"])
	if f.get("antialiasing") != null:
		f.set("antialiasing", TextServer.FONT_ANTIALIASING_NONE)
	if f.get("subpixel_positioning") != null:
		f.set("subpixel_positioning", TextServer.SUBPIXEL_POSITIONING_DISABLED)
	if f.get("hinting") != null:
		f.set("hinting", TextServer.HINTING_NORMAL)
	return f


# ---------------------------------------------------------------- 对外 API

func set_style(s: int) -> void:
	var ns := clampi(s, 0, 3)
	if ns == style:
		return
	style = ns
	if _active:
		close()
	queue_redraw()


func set_boxed(b: bool) -> void:
	boxed = b
	queue_redraw()


func set_face(p_face: int) -> void:
	face_id = p_face
	_face_tex = null
	if face_id > 0:
		var img := PALText.face_image(face_id)
		if img != null:
			_face_tex = ImageTexture.create_from_image(img)
	queue_redraw()


## 设置基础字色（sdlpal PAL_StartDialog 的 bFontColor；0 = 默认色）。
## 只影响文本中“未显式改色”的部分（`'`/`-`/`@` 仍然覆盖）。
func set_base_color(color_id: int) -> void:
	base_color = color_id
	# 已显示内容同步换色
	if base_color != 0:
		for line in _cur_lines:
			for t in line:
				if int(t["color"]) == int(PALText.FontColor.DEFAULT):
					t["color"] = base_color
		for t in _title_tokens:
			pass
		_rebuild_flat()
	queue_redraw()


func is_active() -> bool:
	return _active or _choice_active


func is_typing() -> bool:
	return _typing


## 打字已结束、等待玩家按键（翻页或关闭）。
func is_waiting() -> bool:
	return (_active and not _typing) or _choice_active


## 推入对白（对应 sdlpal PAL_ShowDialogText，非阻塞）。
## text 可以是单行，也可以是含 "\n" 的整页（PALText.paginate 的输出）；
## 页满（4 行）后继续推入的内容会缓存到下一页；名字行（以 “：”/“:” 结尾）按标题绘制。
func push_line(text: String, wrap: bool = true) -> void:
	if text == "":
		return
	for part in text.split("\n"):
		_push_one_line(str(part), wrap)


func _push_one_line(text: String, wrap: bool = true) -> void:
	if text == "":
		return
	var info := PALText.parse_codes(text, true)
	var tokens: Array = info["tokens"]
	# 基础字色（bFontColor）：只替换未显式改色的字
	if base_color != 0 and base_color != int(PALText.FontColor.DEFAULT):
		for t in tokens:
			if int(t["color"]) == int(PALText.FontColor.DEFAULT):
				t["color"] = base_color
	var plain := str(info["text"])
	if tokens.is_empty() and int(info["icon"]) == 0:
		return
	if int(info["icon"]) != 0:
		_icon = int(info["icon"])
	if not _active:
		_begin_page()
	# 名字行：当前页尚无内容时按标题绘制（text.c PAL_ShowDialogText 的末尾冒号特判）
	if _cur_lines.is_empty() and _flat.is_empty() and _title_tokens.is_empty() \
			and style != Style.CENTER_WINDOW and _is_name_line(plain):
		_title_tokens = tokens
		_rebuild_flat()
		_start_typing_if_needed()
		queue_redraw()
		return
	# 折行
	var wrapped: Array = []
	if wrap and style != Style.CENTER_WINDOW:
		wrapped = PALText.wrap_tokens(tokens, _text_area_width())
	else:
		wrapped = [tokens]
	for line in wrapped:
		if _cur_lines.size() >= lines_per_page:
			_pending_lines.append(line)
		else:
			_cur_lines.append(line)
	_rebuild_flat()
	_start_typing_if_needed()
	queue_redraw()


## push_line 的别名（World 的 script_dialog 可直接调用）。
func show_line(text: String, wrap: bool = true) -> void:
	push_line(text, wrap)


## 显示对白并 await 到玩家把它关闭。
## content 可以是 String（单条消息）或 PackedStringArray/Array（PALText.paginate 的页列表）。
## 内部按 text.c 逐页等待按键：跳字 → 翻页 → 关闭。
func show_text(content = "") -> void:
	if typeof(content) == TYPE_STRING:
		push_line(str(content))
	elif typeof(content) == TYPE_PACKED_STRING_ARRAY or typeof(content) == TYPE_ARRAY:
		for page in content:
			push_line(str(page))
	else:
		push_line(str(content))
	if not _active:
		return
	await closed


## 结束当前页/整段对白（不改样式，对应 PAL_ClearDialog(TRUE)）。
func clear() -> void:
	var was := _active or _choice_active
	_reset_content()
	_active = false
	_choice_active = false
	queue_redraw()
	if was:
		closed.emit()


## PAL_EndDialog：关闭并恢复缺省样式（上框）。
func end_dialog() -> void:
	clear()
	style = Style.UPPER
	_icon = 0
	queue_redraw()


## 立即结束逐字显示；返回是否真的跳过了打字。
func finish_typing() -> bool:
	if not _typing:
		return false
	_finish_typing_internal()
	return true


## 玩家按键：打字中 → 立即显示；否则翻页/关闭；选项框 → 确认。返回是否消费该按键。
func advance() -> bool:
	if _choice_active:
		confirm_choice(_choice_sel == 0)
		return true
	if not _active:
		return false
	if _typing:
		_finish_typing_internal()
		advanced.emit()
		return true
	if style == Style.CENTER_WINDOW:
		close()
		return false          # 关闭 = 交给调用方推进脚本（world: not advance() -> vm.advance_dialog）
	if not _pending_lines.is_empty():
		_start_next_page()
		page_turned.emit()
		advanced.emit()
		return true
	close()
	return false              # 关闭 = 交出推进权


# ---------------------------------------------------------------- 选项

## 打开是/否选项框（对应脚本 0x000A / PAL_ConfirmMenu），非阻塞。
func open_choice(yes_text: String = "是", no_text: String = "否", initial_yes: bool = true) -> void:
	_reset_content()
	_choice_active = true
	_active = false
	_choice_yes = yes_text
	_choice_no = no_text
	_choice_sel = 0 if initial_yes else 1
	queue_redraw()


## 以程序方式确认选项（测试/脚本用；玩家输入走 advance + 方向键）。
func confirm_choice(yes: bool) -> void:
	if not _choice_active:
		return
	_choice_active = false
	_active = false
	style = Style.UPPER
	queue_redraw()
	choice_made.emit(yes)
	closed.emit()


## 显示是/否选项并 await 结果；true = 是。
## 兼容两种调用：show_choice(true)（初选“是”）/ show_choice("是","否")。
func show_choice(yes_no = true, no_text: String = "否") -> bool:
	var yes_text := "是"
	var initial := true
	if typeof(yes_no) == TYPE_BOOL:
		initial = bool(yes_no)
		yes_text = "是"
	elif typeof(yes_no) == TYPE_STRING:
		yes_text = str(yes_no)
	open_choice(yes_text, no_text, initial)
	var yes: bool = await choice_made
	return yes


# ---------------------------------------------------------------- 输入

func _input(event: InputEvent) -> void:
	if not capture_input:
		return
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	if _choice_active:
		match k.keycode:
			KEY_LEFT, KEY_UP, KEY_A, KEY_W:
				_choice_sel = (_choice_sel + 1) % 2
				queue_redraw()
				get_viewport().set_input_as_handled()
			KEY_RIGHT, KEY_DOWN, KEY_D, KEY_S:
				_choice_sel = (_choice_sel + 1) % 2
				queue_redraw()
				get_viewport().set_input_as_handled()
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				confirm_choice(_choice_sel == 0)
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				confirm_choice(false)
				get_viewport().set_input_as_handled()
		return
	if _active and (k.keycode == KEY_SPACE or k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER):
		advance()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 每帧

func _process(delta: float) -> void:
	if _choice_active:
		return
	if not _active:
		return
	var dirty := false
	if _typing:
		_type_accum += delta * 1000.0
		var guard := 0
		while _typing and _type_accum >= float(_next_delay) and guard < 4000:
			_type_accum -= float(maxi(1, _next_delay))
			_visible += 1
			guard += 1
			if _visible >= _flat.size():
				_finish_typing_internal()
				break
			_next_delay = int(_flat[_visible - 1]["delay_ms"])
			dirty = true
		if dirty:
			queue_redraw()
	elif style == Style.CENTER_WINDOW and _auto_close > 0.0:
		_auto_close -= delta
		if _auto_close <= 0.0:
			close()
	else:
		_icon_blink += delta
		if _icon_blink >= 0.4:
			_icon_blink = 0.0
			queue_redraw()


# ---------------------------------------------------------------- 状态机

func _begin_page() -> void:
	_active = true
	_typing = false
	_waiting = false
	_visible = 0
	_type_accum = 0.0
	_next_delay = 24
	_auto_close = -1.0
	_cur_lines = []
	_pending_lines = []
	_title_tokens = []
	_flat = []
	_icon = 0


func _reset_content() -> void:
	_active = false
	_typing = false
	_waiting = false
	_visible = 0
	_type_accum = 0.0
	_auto_close = -1.0
	_cur_lines = []
	_pending_lines = []
	_title_tokens = []
	_flat = []
	_icon = 0


func _start_typing_if_needed() -> void:
	# sdlpal text.c: kDialogCenterWindow 不逐字，直接显示整句，1.4s 后自动关闭
	if style == Style.CENTER_WINDOW:
		_typing = false
		_visible = _flat.size()
		_waiting = true
		if _auto_close <= 0.0:
			_auto_close = 1.4
		queue_redraw()
		return
	if _flat.is_empty():
		_waiting = true
		_typing = false
		return
	if _visible >= _flat.size():
		_waiting = true
		_typing = false
		return
	_typing = true
	_type_accum = 0.0
	if _visible <= 0:
		# 首字立即出现，之后按该字的速度逐字
		_visible = 1
		_next_delay = int(_flat[0]["delay_ms"])
		if _visible >= _flat.size():
			_finish_typing_internal()


func _finish_typing_internal() -> void:
	_typing = false
	_visible = _flat.size()
	if style == Style.CENTER_WINDOW:
		_waiting = true
		_auto_close = 1.4
	else:
		_waiting = true
	queue_redraw()


func _start_next_page() -> void:
	var next: Array = []
	while next.size() < lines_per_page and not _pending_lines.is_empty():
		next.append(_pending_lines.pop_front())
	_cur_lines = next
	_title_tokens = []
	_icon = 0
	_visible = 0
	_type_accum = 0.0
	_rebuild_flat()
	_start_typing_if_needed()
	queue_redraw()


func close() -> void:
	var was := _active
	_reset_content()
	queue_redraw()
	if was:
		closed.emit()


func _rebuild_flat() -> void:
	_flat = []
	for t in _title_tokens:
		_flat.append(t)
	for line in _cur_lines:
		for t in line:
			_flat.append(t)


func _is_name_line(plain: String) -> bool:
	if plain.is_empty():
		return false
	var last := plain[plain.length() - 1]
	return last == "：" or last == ":"


# ---------------------------------------------------------------- 排版参数

func _has_face() -> bool:
	return _face_tex != null and (style == Style.UPPER or style == Style.LOWER)


func _title_pos() -> Vector2i:
	match style:
		Style.UPPER:
			return Vector2i(80, 8) if _has_face() else Vector2i(12, 8)
		Style.LOWER:
			return Vector2i(4, 108) if _has_face() else Vector2i(12, 108)
		_:
			return Vector2i(12, 8)


func _text_origin() -> Vector2i:
	match style:
		Style.UPPER:
			return Vector2i(96, 26) if _has_face() else Vector2i(44, 26)
		Style.LOWER:
			return Vector2i(20, 126) if _has_face() else Vector2i(44, 126)
		Style.CENTER:
			return Vector2i(80, 40)
		_:
			return Vector2i(0, 0)


func _text_area_width() -> int:
	var origin := _text_origin()
	var right := 8
	var w := SCREEN_W - origin.x - right
	match style:
		Style.CENTER:
			w = SCREEN_W - 80 - right
		_:
			pass
	return maxi(32, w)


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	if _choice_active:
		_draw_choice()
		return
	if not _active:
		return
	match style:
		Style.UPPER:
			if boxed:
				_draw_box(Rect2(0, 0, SCREEN_W, 102))
		Style.LOWER:
			if boxed:
				_draw_box(Rect2(0, 102, SCREEN_W, 98))
		Style.CENTER:
			pass
		Style.CENTER_WINDOW:
			_draw_center_window()
			return
	_draw_face()
	# 文字（按打字机进度绘制）
	var drawn := 0
	if not _title_tokens.is_empty() and style != Style.CENTER:
		var tpos := _title_pos()
		var tx := tpos.x
		var ty := tpos.y
		for t in _title_tokens:
			if drawn >= _visible:
				break
			var ch := str(t["ch"])
			_draw_char(ch, Vector2i(tx, ty), PALText.color_of(int(PALText.FontColor.CYAN_ALT)))
			tx += PALText.char_width_px(ch)
			drawn += 1
	var origin := _text_origin()
	var last_x := origin.x
	var last_y := origin.y
	for li in range(_cur_lines.size()):
		var line: Array = _cur_lines[li]
		var x := origin.x
		var y := origin.y + li * LINE_HEIGHT
		for t in line:
			if drawn >= _visible:
				break
			var ch := str(t["ch"])
			_draw_char(ch, Vector2i(x, y), PALText.color_of(int(t["color"])))
			x += PALText.char_width_px(ch)
			drawn += 1
		if drawn >= _visible:
			last_x = x
			last_y = y
			break
		last_x = x
		last_y = y
	# 等待图标（Data.mkf#12 的 ▼，闪烁；纹理已在 PALText.init 预建，避免 _draw 内建纹理变白）
	if _waiting and not _typing and style != Style.CENTER and (int(_icon_blink * 2.5) % 2 == 0):
		var icon_tex := PALText.dialog_icon_texture(_icon)
		if icon_tex != null:
			draw_texture_rect(icon_tex, Rect2(Vector2(last_x, last_y), Vector2(16, 16)), false)
		else:
			_draw_wait_arrow(Vector2(last_x, last_y))


func _draw_char(ch: String, pos: Vector2i, color: Color) -> void:
	var asc := int(font.get_ascent(FONT_SIZE))
	var p := Vector2(pos.x, pos.y + asc)
	# sdlpal 三重阴影
	draw_string(font, p + Vector2(1, 0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, SHADOW)
	draw_string(font, p + Vector2(0, 1), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, SHADOW)
	draw_string(font, p + Vector2(1, 1), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, SHADOW)
	draw_string(font, p, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)


func _draw_box(rect: Rect2) -> void:
	draw_rect(rect, BOX_FILL, true)
	draw_rect(rect, BOX_BORDER, false, 1.0)
	var inner := Rect2(rect.position + Vector2(1, 1), rect.size - Vector2(2, 2))
	draw_rect(inner, BOX_INNER, false, 1.0)


func _draw_center_window() -> void:
	# 中窗宽度按可见文本计算（text.c: pos = 160 - len*4，box 宽 (len+1)/2 列）
	var plain := ""
	if not _flat.is_empty():
		var n := mini(_visible, _flat.size())
		for i in range(n):
			plain += str(_flat[i]["ch"])
	var w := PALText.text_width_px(plain)
	var bx := SCREEN_W / 2 - (w / 2 + 8)
	var by := 40 - 10
	var rect := Rect2(bx, by, w + 16, 32)
	_draw_box(rect)
	draw_rect(rect, SHADOW, false, 1.0)
	var drawn := 0
	var x: int = int(bx) + 8
	var y: int = int(by) + 10
	for t in _flat:
		if drawn >= _visible:
			break
		var ch := str(t["ch"])
		_draw_char(ch, Vector2i(x, y), PALText.color_of(int(t["color"])))
		x += PALText.char_width_px(ch)
		drawn += 1


func _draw_face() -> void:
	if _face_tex == null:
		return
	var w := _face_tex.get_width()
	var h := _face_tex.get_height()
	var center := Vector2(48, 55) if style == Style.UPPER else Vector2(270, 144)
	var pos := Vector2(center.x - w / 2.0, center.y - h / 2.0)
	draw_texture(_face_tex, pos)
	# 头像底色（避免透明处露出场景，原版头像不透明；[unk] 具体底色由 RGM 精灵自带）
	draw_rect(Rect2(pos + Vector2(-1, -1), Vector2(w + 2, h + 2)), BOX_BORDER, false, 1.0)


func _draw_wait_arrow(pos: Vector2) -> void:
	var pts := PackedVector2Array([
		pos + Vector2(2, 4), pos + Vector2(12, 4), pos + Vector2(7, 11),
	])
	draw_colored_polygon(pts, Color8(240, 232, 180))


func _draw_choice() -> void:
	var rect := Rect2(96, 66, 128, 58)
	_draw_box(rect)
	var y0 := rect.position.y + 8
	var x := rect.position.x + 24
	_draw_char("是", Vector2i(int(x), int(y0)), PALText.color_of(int(PALText.FontColor.DEFAULT)))
	_draw_char("否", Vector2i(int(x), int(y0 + 22)), PALText.color_of(int(PALText.FontColor.DEFAULT)))
	var cy := y0 + (0 if _choice_sel == 0 else 22)
	var cur := PackedVector2Array([
		Vector2(rect.position.x + 12, cy + 4),
		Vector2(rect.position.x + 18, cy + 8),
		Vector2(rect.position.x + 12, cy + 12),
	])
	draw_colored_polygon(cur, CHOICE_CURSOR)
