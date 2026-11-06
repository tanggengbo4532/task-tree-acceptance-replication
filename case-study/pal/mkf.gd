class_name MkfFile
extends RefCounted
## MKF 容器读取 + WIN95 版块解压（YJ2）。
##
## REA 证据（对目标文件的字节观测）：
##   * 文件头 4 字节 = data_start（= 4 * (chunk_count + 1)）；
##   * 偏移表从 offset 0 开始读，第 i 块跨 [u32[4i], u32[4(i+1)])；
##   * 因此 u32[0] 即 data_start，u32[chunk_count] 即文件长度。
##   验证：Sss.mkf 头=24 → 5 块，块长 162464/2360/7910/54056/348456，
##   与 SSS 结构（EVENTOBJECT 32×5077 / SCENE 8×295 / ...）逐字节吻合。
##
## 压缩块（Map/Mgo/Gop/Fbp/...）：块首 4 字节 = 解压后长度（LE），随后是
## YJ2 位流；YJ2 解压器移植自 sdlpal yj1.c（自适应 Huffman + LZ 回引）。

const YJ2_DATA1: Array[int] = [
	0x3f, 0x0b, 0x17, 0x03, 0x2f, 0x0a, 0x16, 0x00, 0x2e, 0x09, 0x15, 0x02, 0x2d, 0x01, 0x08, 0x00,
	0x3e, 0x07, 0x14, 0x03, 0x2c, 0x06, 0x13, 0x00, 0x2b, 0x05, 0x12, 0x02, 0x2a, 0x01, 0x04, 0x00,
	0x3d, 0x0b, 0x11, 0x03, 0x29, 0x0a, 0x10, 0x00, 0x28, 0x09, 0x0f, 0x02, 0x27, 0x01, 0x08, 0x00,
	0x3c, 0x07, 0x0e, 0x03, 0x26, 0x06, 0x0d, 0x00, 0x25, 0x05, 0x0c, 0x02, 0x24, 0x01, 0x04, 0x00,
	0x3b, 0x0b, 0x17, 0x03, 0x23, 0x0a, 0x16, 0x00, 0x22, 0x09, 0x15, 0x02, 0x21, 0x01, 0x08, 0x00,
	0x3a, 0x07, 0x14, 0x03, 0x20, 0x06, 0x13, 0x00, 0x1f, 0x05, 0x12, 0x02, 0x1e, 0x01, 0x04, 0x00,
	0x39, 0x0b, 0x11, 0x03, 0x1d, 0x0a, 0x10, 0x00, 0x1c, 0x09, 0x0f, 0x02, 0x1b, 0x01, 0x08, 0x00,
	0x38, 0x07, 0x0e, 0x03, 0x1a, 0x06, 0x0d, 0x00, 0x19, 0x05, 0x0c, 0x02, 0x18, 0x01, 0x04, 0x00,
	0x37, 0x0b, 0x17, 0x03, 0x2f, 0x0a, 0x16, 0x00, 0x2e, 0x09, 0x15, 0x02, 0x2d, 0x01, 0x08, 0x00,
	0x36, 0x07, 0x14, 0x03, 0x2c, 0x06, 0x13, 0x00, 0x2b, 0x05, 0x12, 0x02, 0x2a, 0x01, 0x04, 0x00,
	0x35, 0x0b, 0x11, 0x03, 0x29, 0x0a, 0x10, 0x00, 0x28, 0x09, 0x0f, 0x02, 0x27, 0x01, 0x08, 0x00,
	0x34, 0x07, 0x0e, 0x03, 0x26, 0x06, 0x0d, 0x00, 0x25, 0x05, 0x0c, 0x02, 0x24, 0x01, 0x04, 0x00,
	0x33, 0x0b, 0x17, 0x03, 0x23, 0x0a, 0x16, 0x00, 0x22, 0x09, 0x15, 0x02, 0x21, 0x01, 0x08, 0x00,
	0x32, 0x07, 0x14, 0x03, 0x20, 0x06, 0x13, 0x00, 0x1f, 0x05, 0x12, 0x02, 0x1e, 0x01, 0x04, 0x00,
	0x31, 0x0b, 0x11, 0x03, 0x1d, 0x0a, 0x10, 0x00, 0x1c, 0x09, 0x0f, 0x02, 0x1b, 0x01, 0x08, 0x00,
	0x30, 0x07, 0x0e, 0x03, 0x1a, 0x06, 0x0d, 0x00, 0x19, 0x05, 0x0c, 0x02, 0x18, 0x01, 0x04, 0x00,
]

const YJ2_DATA2: Array[int] = [
	0x08, 0x05, 0x06, 0x04, 0x07, 0x05, 0x06, 0x03, 0x07, 0x05, 0x06, 0x04, 0x07, 0x04, 0x05, 0x03,
]

var path: String = ""
var bytes: PackedByteArray = PackedByteArray()
var chunk_count: int = 0
var offsets: PackedInt32Array = PackedInt32Array()


static func open_asset(dir: String, filename: String) -> MkfFile:
	var f := MkfFile.new()
	f.path = dir + filename
	var fa := FileAccess.open(f.path, FileAccess.READ)
	if fa == null:
		push_error("MkfFile: 打不开 %s" % f.path)
		return null
	f.bytes = fa.get_buffer(fa.get_length())
	fa.close()
	if f.bytes.size() < 8:
		push_error("MkfFile: 文件过短 %s" % f.path)
		return null
	var data_start := f.u32(0)
	if data_start < 8 or data_start > f.bytes.size() or (data_start % 4) != 0:
		push_error("MkfFile: 头部非法 %s data_start=%d" % [f.path, data_start])
		return null
	f.chunk_count = (data_start >> 2) - 1
	f.offsets.resize(f.chunk_count + 1)
	for i in range(f.chunk_count + 1):
		f.offsets[i] = f.u32(i * 4)
	return f


func u32(off: int) -> int:
	return bytes[off] | (bytes[off + 1] << 8) | (bytes[off + 2] << 16) | (bytes[off + 3] << 24)


func u16(off: int) -> int:
	return bytes[off] | (bytes[off + 1] << 8)


func chunk(i: int) -> PackedByteArray:
	if i < 0 or i >= chunk_count:
		return PackedByteArray()
	return bytes.slice(offsets[i], offsets[i + 1])


## 解压一个 WIN95 压缩块；块首 4 字节 = 解压后长度。
func decompressed(i: int) -> PackedByteArray:
	var raw := chunk(i)
	if raw.size() < 5:
		return PackedByteArray()
	var size := raw[0] | (raw[1] << 8) | (raw[2] << 16) | (raw[3] << 24)
	if size <= 0 or size > 4 * 1024 * 1024:
		return PackedByteArray()
	return yj2_decompress(raw, 4, size)


static func yj2_decompress(src: PackedByteArray, src_start: int, size: int) -> PackedByteArray:
	# 自适应 Huffman 树：641 个节点，前 0x141 个为叶子（值 0..0x140）。
	# 注意：PackedInt32Array 是值类型，传入辅助函数会被复制；树状态必须用
	# 引用类型的 Array[int]（或字典）共享，否则 _yj2_adjust 的修改丢失。
	var node_w: Array[int] = []
	var node_v: Array[int] = []
	var node_p: Array[int] = []
	var node_l: Array[int] = []
	var node_r: Array[int] = []
	node_w.resize(641)
	node_v.resize(641)
	node_p.resize(641)
	node_l.resize(641)
	node_r.resize(641)
	var list: Array[int] = []
	list.resize(321)
	for i in range(641):
		node_v[i] = i
		node_w[i] = 1
		node_p[i] = -1
		node_l[i] = 0
		node_r[i] = 0
	for i in range(321):
		list[i] = i
	node_p[0x280] = 0x280
	# 建树：内部节点 0x141..0x280，左右孩子按顺序两两配对。
	# 注意权重必须边建边算（后面的内部节点可能挂在更早的内部节点下）。
	# C: for (i = 0, ptr = 0x141; ptr <= 0x280; i += 2, ptr++)
	for cur in range(0x141, 0x281):
		var i := (cur - 0x141) * 2
		node_l[cur] = i
		node_r[cur] = i + 1
		node_p[i] = cur
		node_p[i + 1] = cur
		node_w[cur] = node_w[i] + node_w[i + 1]

	var dest := PackedByteArray()
	dest.resize(size)
	var dpos := 0
	var src_end := src.size()
	var bitpos := 0
	var bits_left := (src_end - src_start) * 8

	while true:
		var node := 0x280
		while node_v[node] > 0x140:
			if bitpos >= bits_left:
				return dest
			var byte_i := src_start + (bitpos >> 3)
			var bit := (src[byte_i] >> (bitpos & 7)) & 1
			node = node_r[node] if bit != 0 else node_l[node]
			bitpos += 1
		var val := node_v[node]

		if node_w[0x280] == 0x8000:
			for i in range(0x141):
				var leaf := list[i]
				if (node_w[leaf] & 1) != 0:
					_yj2_adjust(node_w, node_v, node_p, node_l, node_r, list, i)
			for i in range(0x281):
				node_w[i] = node_w[i] >> 1
		_yj2_adjust(node_w, node_v, node_p, node_l, node_r, list, val)

		if val > 0xff:
			var temp := 0
			var i := 0
			while i < 8:
				if bitpos >= bits_left:
					return dest
				var byte_i2 := src_start + (bitpos >> 3)
				temp |= (((src[byte_i2] >> (bitpos & 7)) & 1) << i)
				bitpos += 1
				i += 1
			var tmp := temp & 0xff
			var target: int = YJ2_DATA2[tmp & 0xf] + 6
			while i < target:
				if bitpos >= bits_left:
					return dest
				var byte_i3 := src_start + (bitpos >> 3)
				temp |= (((src[byte_i3] >> (bitpos & 7)) & 1) << i)
				bitpos += 1
				i += 1
			temp = temp >> YJ2_DATA2[tmp & 0xf]
			var pos := (temp & 0x3f) | (YJ2_DATA1[tmp] << 6)
			if pos == 0xfff:
				break
			var pre := dpos - pos - 1
			var count := val - 0xfd
			for k in range(count):
				if dpos >= size or pre < 0:
					return dest
				dest[dpos] = dest[pre]
				dpos += 1
				pre += 1
		else:
			if dpos >= size:
				return dest
			dest[dpos] = val
			dpos += 1
		if dpos >= size:
			break
	return dest


static func _yj2_adjust(
	w: Array[int], v: Array[int], p: Array[int],
	l: Array[int], r: Array[int], list: Array[int],
	value: int
) -> void:
	var node := list[value]
	while v[node] != 0x280:
		var temp := node + 1
		while temp < 641 and w[node] == w[temp]:
			temp += 1
		temp -= 1
		if temp != node:
			var tmp1 := p[node]
			p[node] = p[temp]
			p[temp] = tmp1
			if v[node] > 0x140:
				p[l[node]] = temp
				p[r[node]] = temp
			else:
				list[v[node]] = temp
			if v[temp] > 0x140:
				p[l[temp]] = node
				p[r[temp]] = node
			else:
				list[v[temp]] = node
			# 交换两个数组位置上的节点内容（对应 C 里的 *node <-> *temp）
			var tv := v[node]
			v[node] = v[temp]
			v[temp] = tv
			var tw := w[node]
			w[node] = w[temp]
			w[temp] = tw
			var tp := p[node]
			p[node] = p[temp]
			p[temp] = tp
			var tl := l[node]
			l[node] = l[temp]
			l[temp] = tl
			var tr := r[node]
			r[node] = r[temp]
			r[temp] = tr
			node = temp
		w[node] += 1
		node = p[node]
	w[node] += 1
