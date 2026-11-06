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

## R120-WATER-1：真实地图数据里的“水面底图”图块（tile 序号是每张地图局部索引）。
## map46（scene50 白河村郊外）tile 307 = 水面底图（整块纯色菱形水纹）；
## 同格的 top 层 overlay 是木桥/栈道（top>=0）——桥面保持可走；只有“水面底图且无 top overlay”
## 才判定为不可走的开放水域。数据来自原版 MAP.MKF 图块号，不按像素亮度判定。
const WATER_TILE_IDS := {
	46: [307],
}

var map_index: int = 0
var bottom: Image = null
var layer_top: Image = null
var tile_frames: Array[Image] = []
var blocked: PackedByteArray = PackedByteArray()     # (y*64+x)*2+h
var tile_height: PackedByteArray = PackedByteArray() # 同上，每半格一个
## R99-BLACK-2：图块内容掩码（1=该半格有图块，0=空/黑色无内容）。
## 黑区（无地砖）一律不可走且保持黑色；地图连通依靠真实门/传送点，不做补地面、不改连通性。
## R124-GROUND-1：图块号 0 是合法底图（如 map46 的 tile0=草地/泥地），不能当“空”封掉；
## 改为按图块位图是否真的有非透明像素（tile 数据属性，不按屏幕像素亮度）判断“有内容”。
var has_content: PackedByteArray = PackedByteArray()
var _bottom_index: PackedInt32Array = PackedInt32Array()
var _top_index: PackedInt32Array = PackedInt32Array()
var _frame_opaque: PackedByteArray = PackedByteArray()


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
	# R124-GROUND-1：预计算每个 tile 位图是否真有非透明像素（数据属性，不看屏幕亮度）。
	m._frame_opaque.resize(m.tile_frames.size())
	for fi in range(m.tile_frames.size()):
		var fim: Image = m.tile_frames[fi]
		var op := 0
		if fim != null:
			var fd := fim.get_data()
			var k := 3
			while k < fd.size():
				if fd[k] != 0:
					op = 1
					break
				k += 4
		m._frame_opaque[fi] = op
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
	m.has_content = PackedByteArray()
	m.has_content.resize(MAP_W * MAP_H * HALVES)

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
				# R98-BLACK-1b：按 tile id / 层号判定“有地砖”，不按像素亮度（避免深色洞窟地砖被误判为空）。
				# R124-GROUND-1：tile id 0 也是合法底图（map46 tile0=草地/泥地），改为按该 tile 位图
				# 是否真有非透明像素判断；只有该图块整块透明（或 top 有内容）才没有可走地面。
				var bot_has := false
				if idx_bottom >= 0:
					var bfi := idx_bottom
					if bfi < m._frame_opaque.size():
						bot_has = int(m._frame_opaque[bfi]) != 0
					else:
						bot_has = true
				# R150-VOID-1：只有“底层地砖位图非透明”才算真正地面；top overlay 是桥/屋顶/装饰层，
				# 不能单独把 void/黑底格变成可走（用户 scene58 报“走到原本地图外”）。
				# 合法桥面/栈道都有底层水面/地面 opaque，因此不受影响。
				m.has_content[slot] = 1 if bot_has else 0
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
	var slot := (y * MAP_W + x) * HALVES + h
	# R99-BLACK-2：黑区（无任何地砖内容的半格）一律不可走、渲染保持黑色；
	# 地图连通依靠真实门/传送点（不改连通性、不补地面、不伪造）。
	if blocked[slot] != 0:
		return true
	if has_content.size() > slot and has_content[slot] == 0:
		return true
	# R120-WATER-1：无桥/栈道 overlay 的水面底图不可走（桥面 top>=0 保持可走）。
	if is_open_water(x, y, h):
		return true
	return false


## R120-WATER-1：像素坐标 → 半格下标（与 sdlpal PAL_CheckObstacle 同一套菱形换算）。
func slot_at_pixel(px: int, py: int) -> int:
	if px < 0 or py < 0 or px >= IMG_W or py >= IMG_H:
		return -1
	var tx := px / 32
	var ty := py / 16
	var h := 0
	var xr := px % 32
	var yr := py % 16
	if xr + yr * 2 >= 16:
		if xr + yr * 2 >= 48:
			tx += 1
			ty += 1
		elif 32 - xr + yr * 2 < 16:
			tx += 1
		elif 32 - xr + yr * 2 < 48:
			h = 1
		else:
			ty += 1
	if tx < 0 or ty < 0 or tx >= MAP_W or ty >= MAP_H:
		return -1
	return (ty * MAP_W + tx) * HALVES + h


func has_top_overlay_at(px: int, py: int) -> bool:
	var slot := slot_at_pixel(px, py)
	if slot < 0 or slot >= _top_index.size():
		return false
	return _top_index[slot] >= 0


## R120-WATER-1：该半格是否为“不可走的开放水域”（水面底图且该格没有 top 层 overlay）。
## 桥/码头等合法通道由 top 层图块覆盖，直接返回 false 保持可走。
## R120-WATER-1c：水面“紧贴桥/栈道/码头 overlay”的一圈保留可走（浅滩/岸边），
## 否则封水会把原版“沿岸窄道/桥头”断开，导致主线门不可达（用户 (1600,720) 即此情况）。
func is_open_water(x: int, y: int, h: int) -> bool:
	if x < 0 or y < 0 or x >= MAP_W or y >= MAP_H or h < 0 or h >= HALVES:
		return false
	var slot := (y * MAP_W + x) * HALVES + h
	if slot < 0 or slot >= _bottom_index.size():
		return false
	if _top_index.size() > slot and _top_index[slot] >= 0:
		return false
	var water_ids: Array = WATER_TILE_IDS.get(int(map_index), [])
	if water_ids.is_empty():
		return false
	if not water_ids.has(int(_bottom_index[slot])):
		return false
	# 桥面/栈道/码头紧邻的浅水边缘保持可走（只放宽 1 步内的 overlay 邻格）
	var px := x * TILE_W + h * 16
	var py := y * TILE_H + h * 8
	# R134-BRIDGELINK-1：桥面/栈道/码头紧邻 1 步内的浅水边缘保持可走（恢复桥头两岸连通）。
	# 说明：R127 “仅两侧夹 overlay” 规则过严，把白河村石桥主通路断开（scene50 起始/桥头两连通块），
	# A30 目标不可达 → HUD 退回 evt830 商铺街（用户 r133 BLOCKED）。这里恢复单侧浅水可走，
	# 但其它约束（blocked/黑区/开放水域、引导目标过滤、SPACE 门让位）仍保留。
	var neighbors := [Vector2i(16, 0), Vector2i(-16, 0), Vector2i(0, 8), Vector2i(0, -8),
		Vector2i(16, 8), Vector2i(-16, 8), Vector2i(16, -8), Vector2i(-16, -8)]
	for no in neighbors:
		if has_top_overlay_at(px + no.x, py + no.y):
			return false
	return true


## R120-WATER-1：像素坐标 → 半格，判断该像素是否落在开放水域（供读档救援用）。
func is_open_water_at(px: int, py: int) -> bool:
	var tx := px / 32
	var ty := py / 16
	var h := 0
	var xr := px % 32
	var yr := py % 16
	if xr + yr * 2 >= 16:
		if xr + yr * 2 >= 48:
			tx += 1
			ty += 1
		elif 32 - xr + yr * 2 < 16:
			tx += 1
		elif 32 - xr + yr * 2 < 48:
			h = 1
		else:
			ty += 1
	return is_open_water(tx, ty, h)


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
