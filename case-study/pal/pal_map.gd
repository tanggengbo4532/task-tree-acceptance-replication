class_name PalMap
extends RefCounted
## 地图加载与预渲染（sdlpal map.c: PAL_LoadMap / PAL_MapBlitToSurface）。
##
## MAP 块（Map.mkf 第 i 块，YJ2 解压后 65536 字节）：
##   128 行 × 64 列 × 2 个半格 × 4 字节。每个 DWORD 低 16 位为下层、高 16 位为上层，
##   其中：低层图块号 = (d & 0xFF) | ((d >> 4) & 0x100)
##         上层图块号 = ((d >> 16) & 0xFF) | ((d >> 20) & 0x100) - 1
##         低层阻挡   = (d & 0x2000) != 0，上层阻挡 = ((d >> 16) & 0x2000) != 0
##         低层高度   = (d >> 8) & 0xF，上层高度 = (d >> 24) & 0xF
##   图块位图来自 Gop.mkf 同名块（精灵帧，32×16）。
##   屏幕坐标：tile(x, y, h) 绘制于 (x*32 + h*16, y*16 + h*8)（相对地图原点偏移 (0,0)）。
##
## 预渲染图坐标约定：image_pos = game_pos + Vector2i(16, 8)。
## 因此地图图块在图像里绘制于 (x*32 + h*16, y*16 + h*8)。

const MAP_W := 64
const MAP_H := 128
const HALVES := 2
const TILE_W := 32
const TILE_H := 16
const IMG_W := MAP_W * TILE_W + 16      # 2064
const IMG_H := MAP_H * TILE_H + 16      # 2064
const ORIGIN_SHIFT := Vector2i(16, 8)

var map_index: int = 0
var bottom: Image = null
var layer_top: Image = null
var tile_frames: Array[Image] = []
var blocked: PackedByteArray = PackedByteArray()     # (y*64+x)*2+h
var tile_height: PackedByteArray = PackedByteArray() # 同上，每半格一个
var _bottom_index: PackedInt32Array = PackedInt32Array()
var _top_index: PackedInt32Array = PackedInt32Array()


static func load_palette(pat: MkfFile, pal_num: int, night: bool = false) -> PackedColorArray:
	var chunk := pat.chunk(pal_num)
	if chunk.size() < 768:
		chunk = pat.chunk(0)
	# WIN95 PAT：块长 1536 = day 768 + night 768
	if night and chunk.size() >= 1536:
		chunk = chunk.slice(768, 1536)
	return PalSprite.palette_from_bytes(chunk)


static func load_map(map_mkf: MkfFile, gop_mkf: MkfFile, index: int, palette: PackedColorArray) -> PalMap:
	if index <= 0 or index >= map_mkf.chunk_count or index >= gop_mkf.chunk_count:
		push_error("PalMap: 地图号越界 %d" % index)
		return null
	var data := map_mkf.decompressed(index)
	if data.size() < MAP_W * MAP_H * HALVES * 4:
		push_error("PalMap: 地图 %d 解压后只有 %d 字节" % [index, data.size()])
		return null
	# Gop.mkf 的图块块是原样 sprite 数据（未压缩），Map.mkf 才是 YJ2 压缩块。
	var gop := gop_mkf.chunk(index)
	if gop.size() < 4:
		push_error("PalMap: Gop.mkf 块 %d 为空" % index)
		return null

	var m := PalMap.new()
	m.map_index = index
	m.tile_frames = PalSprite.decode_sprite(gop, palette)
	m.bottom = Image.create_empty(IMG_W, IMG_H, false, Image.FORMAT_RGBA8)
	m.bottom.fill(Color(0, 0, 0, 1))
	m.layer_top = Image.create_empty(IMG_W, IMG_H, false, Image.FORMAT_RGBA8)
	m.layer_top.fill(Color(0, 0, 0, 0))
	m.blocked = PackedByteArray()
	m.blocked.resize(MAP_W * MAP_H * HALVES)
	m.tile_height = PackedByteArray()
	m.tile_height.resize(MAP_W * MAP_H * HALVES)
	m._bottom_index = PackedInt32Array()
	m._bottom_index.resize(MAP_W * MAP_H * HALVES)
	m._top_index = PackedInt32Array()
	m._top_index.resize(MAP_W * MAP_H * HALVES)

	var fallback: Image = m.tile_frames[0] if m.tile_frames.size() > 0 else null
	for y in range(MAP_H):
		for x in range(MAP_W):
			for h in range(HALVES):
				var o := ((y * MAP_W + x) * HALVES + h) * 4
				var d := data[o] | (data[o + 1] << 8) | (data[o + 2] << 16) | (data[o + 3] << 24)
				var idx_bottom := (d & 0xFF) | ((d >> 4) & 0x100)
				var idx_top := (((d >> 16) & 0xFF) | ((d >> 20) & 0x100)) - 1
				var slot := (y * MAP_W + x) * HALVES + h
				m.tile_height[slot] = (d >> 8) & 0x0F
				m.blocked[slot] = 1 if (d & 0x2000) != 0 else 0
				m._bottom_index[slot] = idx_bottom
				m._top_index[slot] = idx_top
				var px := x * TILE_W + h * 16
				var py := y * TILE_H + h * 8
				var img_bottom: Image = null
				if idx_bottom >= 0 and idx_bottom < m.tile_frames.size():
					img_bottom = m.tile_frames[idx_bottom]
				if img_bottom == null:
					img_bottom = fallback
				if img_bottom != null:
					m.bottom.blend_rect(img_bottom, Rect2i(0, 0, img_bottom.get_width(), img_bottom.get_height()), Vector2i(px, py))
				if idx_top >= 0 and idx_top < m.tile_frames.size():
					var img_top: Image = m.tile_frames[idx_top]
					m.layer_top.blend_rect(img_top, Rect2i(0, 0, img_top.get_width(), img_top.get_height()), Vector2i(px, py))
	return m


func is_blocked(x: int, y: int, h: int) -> bool:
	if x < 0 or y < 0 or x >= MAP_W or y >= MAP_H or h < 0 or h >= HALVES:
		return true
	return blocked[(y * MAP_W + x) * HALVES + h] != 0


func get_tile_height(x: int, y: int, h: int) -> int:
	if x < 0 or y < 0 or x >= MAP_W or y >= MAP_H or h < 0 or h >= HALVES:
		return 0
	return tile_height[(y * MAP_W + x) * HALVES + h]


func tile_image(x: int, y: int, h: int, layer: int) -> Image:
	if x < 0 or y < 0 or x >= MAP_W or y >= MAP_H or h < 0 or h >= HALVES:
		return null
	var slot := (y * MAP_W + x) * HALVES + h
	# 上层图块号保存在 layer_top 里；为取图块图像再读一次原始数据不划算，
	# 这里缓存每格的上层图块号（见 _top_index）。
	var idx := _top_index[slot] if layer != 0 else _bottom_index[slot]
	if idx < 0 or idx >= tile_frames.size():
		return null
	return tile_frames[idx]


func map_pixel_width() -> int:
	return MAP_W * TILE_W


func map_pixel_height() -> int:
	return MAP_H * TILE_H
