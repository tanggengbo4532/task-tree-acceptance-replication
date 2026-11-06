class_name PalSprite
extends RefCounted
## MGO / GOP 精灵解码（sdlpal palcommon.c: PAL_SpriteGetFrame / PAL_RLEBlitToSurface）。
##
## 精灵块结构（[observation]，由目标文件字节解出）：
##   u16 frame_count
##   u16 frame_offset[frame_count]     ; 帧数据位置 = offset * 2（字节）
##   帧数据：RLE 位图
## RLE 位图：
##   可选 4 字节头 0x00000002（跳过）
##   u16 width, u16 height
##   RLE 流：b = byte
##     b & 0x80 且 b <= 0x80+width  → 跳过 (b-0x80) 个透明像素
##     否则                          → 复制 b 个字面像素（调色板索引）
## 调色板索引 0 为透明。

const TRANSPARENT_INDEX := 0


## 解析 sprite 块的帧偏移表。
## 结构（[observation]）：u16 表，表项 i 位于字节 2i，值为 帧数据字节位置/2；
## 表项 0 恰好等于 帧数+1（sdlpal PAL_SpriteGetNumFrames 返回该值-1），
## 因此 帧数 = u16@0 - 1，帧 i 数据位置 = u16@(2i) * 2。
static func frame_offsets(data: PackedByteArray) -> Array:
	if data.size() < 4:
		return [0, PackedInt32Array()]
	var first := data[0] | (data[1] << 8)
	var count := first - 1
	if count <= 0 or count > 512:
		return [0, PackedInt32Array()]
	var offs := PackedInt32Array()
	offs.resize(count)
	for i in range(count):
		var p := 2 * i
		if p + 1 >= data.size():
			offs[i] = 0
			continue
		offs[i] = (data[p] | (data[p + 1] << 8)) * 2
	return [count, offs]


## 解码整块 sprite 为帧图像数组（应用调色板）。
static func decode_sprite(data: PackedByteArray, palette: PackedColorArray) -> Array[Image]:
	var out: Array[Image] = []
	var info := frame_offsets(data)
	var count: int = info[0]
	var offs: PackedInt32Array = info[1]
	for i in range(count):
		var off := offs[i]
		if off <= 0 or off >= data.size():
			out.append(Image.create_empty(1, 1, false, Image.FORMAT_RGBA8))
			continue
		out.append(decode_frame(data, off, palette))
	return out


## 解码一个 RLE 帧为 RGBA8 图（调色板索引 0 透明）。
static func decode_frame(data: PackedByteArray, off: int, palette: PackedColorArray) -> Image:
	var p := off
	if p + 4 <= data.size() and data[p] == 2 and data[p + 1] == 0 and data[p + 2] == 0 and data[p + 3] == 0:
		p += 4
	if p + 4 > data.size():
		return Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	var w := data[p] | (data[p + 1] << 8)
	var h := data[p + 2] | (data[p + 3] << 8)
	p += 4
	if w <= 0 or h <= 0 or w > 1024 or h > 1024:
		return Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var total := w * h
	var i := 0
	var src := p
	while i < total and src < data.size():
		var t := data[src]
		src += 1
		if (t & 0x80) != 0 and t <= 0x80 + w:
			i += t - 0x80
		else:
			var j := 0
			while j < t and i < total:
				var idx := data[src + j]
				var x := i % w
				var y := i / w
				if idx != TRANSPARENT_INDEX:
					img.set_pixel(x, y, palette[idx])
				i += 1
				j += 1
			src += t
	return img


## 从 768 字节 6bit VGA 调色板构造 PackedColorArray（256 色）。
static func palette_from_bytes(buf: PackedByteArray) -> PackedColorArray:
	var pal := PackedColorArray()
	pal.resize(256)
	for i in range(256):
		var r := 0
		var g := 0
		var b := 0
		if (i * 3 + 2) < buf.size():
			r = mini(255, buf[i * 3] * 4)
			g = mini(255, buf[i * 3 + 1] * 4)
			b = mini(255, buf[i * 3 + 2] * 4)
		pal[i] = Color8(r, g, b, 255)
	pal[TRANSPARENT_INDEX] = Color(0, 0, 0, 0)
	return pal
