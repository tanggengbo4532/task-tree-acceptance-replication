class_name UIAssets
extends RefCounted
## UI 资产层：DATA.MKF #9 UI 精灵（边框/按钮/数字/光标/头像框）、BALL.MKF 物品图标、
## RGM.MKF 角色头像、FBP.MKF 全屏背景。
##
## 证据与纠偏：
##   * sdlpal `ui.c: PAL_InitUI` 用 `CHUNKNUM_SPRITEUI`（ui.h 定义 = **9**）读 DATA.MKF：
##     实测 Data.mkf 块 9 = 25532 B，解出 **71 帧** sprite（帧表 + RLE）；
##     Data.mkf 块 12 = 282 B 是对话图标（sdlpal text.c bufDialogIcons），不是 UI 精灵表。
##   * BALL.MKF 每块是**单幅 RLE 位图**（块首 4 字节 0x00000002 头 + u16 w/h + RLE），
##     sdlpal itemmenu.c 直接 `PAL_MKFReadChunk + PAL_RLEBlitToSurface`，没有帧偏移表。
##   * RGM.MKF 每块同上（单幅 RLE 位图），sdlpal uigame.c: PAL_PlayerStatus 直接 RLE blit。
##   * FBP.MKF 每块 YJ2 压缩 → 64000 B = 320×200 8bpp 索引图（MISC-FORMAT.md §1）。
##
## 本层只负责“字节 → Godot Image/Texture”，布局与交互在 game/menu*.gd。

# ---------------------------------------------------------------- 常量
## sdlpal ui.h: CHUNKNUM_SPRITEUI = 9（任务书的 #12 为误记，见文件头说明）
const CHUNK_SPRITE_UI := 9
## 备用块（Data#12 对话框图标，非 UI 边框；仅当 #9 不可用时兜底探测）
const CHUNK_DIALOG_ICONS := 12

## 帧号（sdlpal ui.h SPRITENUM_*）
const SPR_SLASH := 39
const SPR_ITEMBOX := 70
const SPR_CURSOR_YELLOW_UP := 66
const SPR_CURSOR_UP := 67
const SPR_CURSOR_YELLOW := 68
const SPR_CURSOR := 69
const SPR_PLAYERINFOBOX := 18
const SPR_PLAYERFACE := 48
const SPR_ARROW := 47
## 数字帧起点：黄 19、蓝 29、青 56（ui.c PAL_DrawNumber）
const NUM_YELLOW := 19
const NUM_BLUE := 29
const NUM_CYAN := 56
## 边框九宫格：样式 0 = 帧 0..8，样式 1 = 帧 9..17（ui.c PAL_CreateBox）
const BOX_STYLE_0 := 0
const BOX_STYLE_1 := 9
## 大边框阴影偏移（PAL_CreateBoxWithShadow 默认 6）
const BOX_SHADOW := 6
## 单行框三帧（ui.c PAL_CreateSingleLineBox：44/45/46）
const LINEBOX_LEFT := 44
const LINEBOX_MID := 45
const LINEBOX_RIGHT := 46

## 数字颜色
enum NumColor { YELLOW, BLUE, CYAN }
## 数字对齐（ui.c NUMALIGN）
enum NumAlign { LEFT, MID, RIGHT }

## 调色板索引 → 菜单颜色（sdlpal ui.h）
const MENU_COLOR_ITEM := 0x4F
const MENU_COLOR_INACTIVE := 0x18
const MENU_COLOR_CONFIRMED := 0x2C
const MENU_COLOR_SELECTED_INACTIVE := 0x1C
const MENU_COLOR_SELECTED_FIRST := 0xF9
const MENU_COLOR_EQUIPPEDITEM := 0xC8
const DESC_COLOR := 0x3C

var ok: bool = false
var data_dir: String = ""
## 精灵调色板：索引 0 透明（PalSprite.palette_from_bytes 已处理）
var palette: PackedColorArray = PackedColorArray()
## 背景调色板：索引 0 不透明黑（FBP 整屏图用）
var palette_bg: PackedColorArray = PackedColorArray()

var frames: Array[Image] = []
var _tex_cache: Dictionary = {}          # frame idx -> ImageTexture
var _box_cache: Dictionary = {}          # "rows,cols,style" -> Image
var _linebox_cache: Dictionary = {}      # "len" -> Image
var _num_cache: Dictionary = {}          # "v,len,color,align" -> Image
var _icon_cache: Dictionary = {}         # bitmap id -> Image
var _avatar_cache: Dictionary = {}       # avatar id -> Image
var _fbp_cache: Dictionary = {}          # chunk -> Image
var _ball: MkfFile = null
var _rgm: MkfFile = null
var _fbp: MkfFile = null
var _data: MkfFile = null


func init(p_dir: String = "") -> bool:
	ok = false
	frames = []
	data_dir = p_dir
	if data_dir == "":
		if PALTables != null and PALTables.data_dir != "":
			data_dir = PALTables.data_dir
		elif PalConfig.data_dir() != "":
			data_dir = PalConfig.data_dir()
	if data_dir == "":
		push_error("UIAssets: 未找到数据目录")
		return false
	# DATA.MKF：优先复用 PALTables 已打开的实例（autoload 装载时已打开）
	_data = PALTables.data_mkf if PALTables != null else null
	if _data == null:
		_data = MkfFile.open_asset(data_dir, "Data.mkf")
	if _data == null or _data.chunk_count <= CHUNK_SPRITE_UI:
		push_error("UIAssets: DATA.MKF 不可用")
		return false

	_ball = MkfFile.open_asset(data_dir, "Ball.mkf")
	_rgm = MkfFile.open_asset(data_dir, "Rgm.mkf")
	_fbp = MkfFile.open_asset(data_dir, "Fbp.mkf")
	var pat := MkfFile.open_asset(data_dir, "Pat.mkf")
	if pat != null:
		palette = PalMap.load_palette(pat, 0)
		palette_bg = palette.duplicate()
		if palette_bg.size() > 0:
			palette_bg[0] = Color(0, 0, 0, 1)
	if palette.is_empty():
		palette = PackedColorArray()
		palette.resize(256)
		palette.fill(Color(1, 1, 1, 1))
		palette[0] = Color(0, 0, 0, 0)
		palette_bg = palette.duplicate()
		palette_bg[0] = Color(0, 0, 0, 1)

	# UI 精灵块：原样存储（Data.mkf 全部块未压缩，MISC-FORMAT §9）
	var raw := _data.chunk(CHUNK_SPRITE_UI)
	frames = PalSprite.decode_sprite(raw, palette)
	if frames.size() < SPR_ITEMBOX + 1:
		push_warning("UIAssets: UI 精灵帧数异常 %d" % frames.size())
	ok = frames.size() >= 45
	return ok


# ---------------------------------------------------------------- 基础帧

func frame(i: int) -> Image:
	if i < 0 or i >= frames.size():
		return null
	return frames[i]


func texture(i: int) -> ImageTexture:
	if _tex_cache.has(i):
		return _tex_cache[i]
	var img := frame(i)
	if img == null:
		_tex_cache[i] = null
		return null
	var t := ImageTexture.create_from_image(img)
	_tex_cache[i] = t
	return t


func color(idx: int) -> Color:
	if idx >= 0 and idx < palette.size():
		return palette[idx]
	return Color(1, 1, 1, 1)


func num_color_index(c: int) -> int:
	match c:
		NumColor.BLUE:
			return NUM_BLUE
		NumColor.CYAN:
			return NUM_CYAN
		_:
			return NUM_YELLOW


# ---------------------------------------------------------------- 九宫格边框

## 复刻 ui.c PAL_CreateBoxWithShadow：rows/cols 为**内容**行列数（不含边框）。
## 返回带阴影的合成图（透明背景），可直接按逻辑坐标贴到 320×200 画面上。
func box_image(rows: int, cols: int, style: int = BOX_STYLE_0, shadow: int = BOX_SHADOW) -> Image:
	var key := "%d,%d,%d,%d" % [rows, cols, style, shadow]
	if _box_cache.has(key):
		return _box_cache[key]
	if frames.size() < style + 9:
		return null
	var bw: int = 0
	var bh: int = 0
	for i in range(3):
		if i == 1:
			var mid_top := frame(style + 0 * 3 + 1)
			var mid_left := frame(style + 1 * 3 + 0)
			if mid_top == null or mid_left == null:
				return null
			bw += mid_top.get_width() * cols
			bh += mid_left.get_height() * rows
		else:
			var edge_h := frame(style + 0 * 3 + i)
			var edge_v := frame(style + i * 3 + 0)
			if edge_h == null or edge_v == null:
				return null
			bw += edge_h.get_width()
			bh += edge_v.get_height()
	var total_w: int = bw + shadow
	var total_h: int = bh + shadow
	var img := Image.create_empty(total_w, total_h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var n_rows: int = rows + 2
	var n_cols: int = cols + 2
	var y: int = 0
	for i in range(n_rows):
		var x: int = 0
		var m: int = 0 if i == 0 else (2 if i == n_rows - 1 else 1)
		for j in range(n_cols):
			var n: int = 0 if j == 0 else (2 if j == n_cols - 1 else 1)
			var bmp := frame(style + m * 3 + n)
			if bmp == null:
				continue
			if shadow > 0:
				_blit_shadow(img, bmp, x + shadow, y + shadow)
			_blit(img, bmp, x, y)
			x += bmp.get_width()
		var row_h := frame(style + m * 3 + 0)
		if row_h != null:
			y += row_h.get_height()
	_box_cache[key] = img
	return img


## 复刻 ui.c PAL_CreateSingleLineBoxWithShadow：len = 中间帧重复次数。
func linebox_image(line_len: int, shadow: int = BOX_SHADOW) -> Image:
	var key := "%d,%d" % [line_len, shadow]
	if _linebox_cache.has(key):
		return _linebox_cache[key]
	var left := frame(LINEBOX_LEFT)
	var mid := frame(LINEBOX_MID)
	var right := frame(LINEBOX_RIGHT)
	if left == null or mid == null or right == null:
		return null
	var w: int = left.get_width() + mid.get_width() * line_len + right.get_width() + shadow
	var h: int = left.get_height() + shadow
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var x: int = 0
	if shadow > 0:
		_blit_shadow(img, left, x + shadow, shadow)
		var sx: int = x + left.get_width()
		for _i in range(line_len):
			_blit_shadow(img, mid, sx + shadow, shadow)
			sx += mid.get_width()
		_blit_shadow(img, right, sx + shadow, shadow)
	_blit(img, left, x, 0)
	x += left.get_width()
	for _i in range(line_len):
		_blit(img, mid, x, 0)
		x += mid.get_width()
	_blit(img, right, x, 0)
	_linebox_cache[key] = img
	return img


## 复刻 ui.c PAL_DrawNumber 的位图数字：返回宽度 6*length、高 8 的合成图。
func number_image(value: int, length: int, num_color: int, align: int) -> Image:
	var key := "%d,%d,%d,%d" % [value, length, num_color, align]
	if _num_cache.has(key):
		return _num_cache[key]
	if length <= 0:
		return null
	var base := num_color_index(num_color)
	if frames.size() < base + 10:
		return null
	var actual: int = 0
	var v: int = value
	while v > 0:
		v /= 10
		actual += 1
	actual = mini(actual, length)
	if actual == 0:
		actual = 1
	var img := Image.create_empty(6 * length, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var offset: int = 0
	match align:
		NumAlign.LEFT:
			offset = 6 * actual
		NumAlign.MID:
			offset = 3 * (length + actual)
		_:
			offset = 6 * length
	var x: int = -6 + offset
	var n: int = value
	for _i in range(actual):
		var bmp := frame(base + n % 10)
		if bmp != null:
			_blit(img, bmp, x, 0)
		x -= 6
		n /= 10
	_num_cache[key] = img
	return img


# ---------------------------------------------------------------- 物品图标/头像/背景

## BALL.MKF 物品图标（wBitmap 块号）→ Image；块是单幅 RLE 位图。
func ball_icon(bitmap_id: int) -> Image:
	if _icon_cache.has(bitmap_id):
		return _icon_cache[bitmap_id]
	var img: Image = null
	if _ball != null and bitmap_id > 0 and bitmap_id < _ball.chunk_count:
		var raw := _ball.chunk(bitmap_id)
		if raw.size() > 8:
			img = PalSprite.decode_frame(raw, 0, palette)
	if img == null or img.get_width() <= 1:
		img = Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	_icon_cache[bitmap_id] = img
	return img


## RGM.MKF 头像（rgwAvatar 块号）→ Image。
func avatar_image(avatar_id: int) -> Image:
	if _avatar_cache.has(avatar_id):
		return _avatar_cache[avatar_id]
	var img: Image = null
	if _rgm != null and avatar_id > 0 and avatar_id < _rgm.chunk_count:
		var raw := _rgm.chunk(avatar_id)
		if raw.size() > 8:
			img = PalSprite.decode_frame(raw, 0, palette)
	if img == null or img.get_width() <= 1:
		img = Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	_avatar_cache[avatar_id] = img
	return img


## FBP.MKF 全屏背景（块号）→ 320×200 RGBA。
func fbp_background(chunk_index: int) -> Image:
	if _fbp_cache.has(chunk_index):
		return _fbp_cache[chunk_index]
	var img: Image = null
	if _fbp != null and chunk_index >= 0 and chunk_index < _fbp.chunk_count:
		var raw := _fbp.decompressed(chunk_index)
		if raw.size() >= 320 * 200:
			img = Image.create_empty(320, 200, false, Image.FORMAT_RGBA8)
			for y in range(200):
				for x in range(320):
					img.set_pixel(x, y, palette_bg[raw[y * 320 + x]])
	if img == null:
		img = Image.create_empty(320, 200, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 1))
	_fbp_cache[chunk_index] = img
	return img


## UI 精灵单帧纹理快捷方式（带缓存）。
func frame_texture(i: int) -> ImageTexture:
	return texture(i)


# ---------------------------------------------------------------- 内部绘制

## 把 src 的可见像素以黑色投影到 dst（对应 PAL_RLEBlitToSurfaceWithShadow 的 bShadow）。
func _blit_shadow(dst: Image, src: Image, x: int, y: int) -> void:
	var sil := _silhouette(src)
	_blit(dst, sil, x, y)


var _sil_cache: Dictionary = {}


func _silhouette(src: Image) -> Image:
	# 用像素数据抽样校验和做缓存键（PackedByteArray 无 hash() 成员）
	var data := src.get_data()
	var key: int = data.size()
	var step: int = maxi(1, data.size() / 64)
	var i := 0
	while i < data.size():
		key = (key * 131 + int(data[i])) & 0x7FFFFFFF
		i += step
	if _sil_cache.has(key):
		return _sil_cache[key]
	var out := Image.create_empty(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	for y in range(src.get_height()):
		for x in range(src.get_width()):
			var c := src.get_pixel(x, y)
			if c.a > 0.0:
				out.set_pixel(x, y, Color(0, 0, 0, 1))
	_sil_cache[key] = out
	return out


## 带边界裁剪的 blend（Image.blend_rect 要求源矩形在图内，目标可越界则手动裁）。
func _blit(dst: Image, src: Image, x: int, y: int) -> void:
	if src == null or dst == null:
		return
	var sw := src.get_width()
	var sh := src.get_height()
	if sw <= 0 or sh <= 0:
		return
	var sx0: int = maxi(0, -x)
	var sy0: int = maxi(0, -y)
	var dx: int = maxi(0, x)
	var dy: int = maxi(0, y)
	var w: int = mini(sw - sx0, dst.get_width() - dx)
	var h: int = mini(sh - sy0, dst.get_height() - dy)
	if w <= 0 or h <= 0:
		return
	dst.blend_rect(src, Rect2i(sx0, sy0, w, h), Vector2i(dx, dy))
