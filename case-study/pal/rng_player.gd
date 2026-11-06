class_name RngPlayer
extends Node
## Rng.mkf 命令流动画播放（移植 sdlpal rngplay.c: PAL_RNGReadFrame / PAL_RNGBlitToSurface / PAL_RNGPlay）。
##
## 格式（docs/rea/evidence/assets/MISC-FORMAT.md §5，实测复核）：
##   * Rng.mkf 顶层 12 块原样存储；每块本身是嵌套 MKF：
##       u32 @0 = 4*(n+1) = 内部偏移表字节数；块内偏移 [off[i], off[i+1])；
##       实测最后一项为空帧（off[n-1] == off[n]），有效帧数 = n-1：
##       [64, 410, 93, 140, 40, 82, 54, 70, 33, 256, 42, 180] 共 1138 帧。
##   * 每个有效帧 = YJ2 压缩流（前 4B = 解压长度）→ 解压后是 0x00..0x13 命令流。
##   * 命令流**累积**画到 320×200 8bpp 索引缓冲（不是每帧清屏），语义见 _apply_frame。
##
## 绘制：自带 CanvasLayer(5) + Sprite2D（scale=2，与 world 的 320×200 屏对齐），
##       每帧把索引缓冲用 PAT 调色板转 RGBA 后 update 纹理；不依赖 world 的帧缓冲。
##       索引 0 在 sdlpal 里是透明/黑；本移植按调色板 0 号色绘制（RNG 起始缓冲为全 0）。
##
## 与 world 的契约：
##   request_rng(id)           → new + add_child + play(id)
##   request_rng_full(id,s,e,sp) → play_full(id, s, e, sp)；播放完 emit finished
##   sdlpal PAL_RNGPlay 的 iEndFrame 语义：iEndFrame>0 时 +1（含末帧），-1/0 表示到动画结束。

signal finished
signal frame_ready(image: Image)

const SCREEN_W := 320
const SCREEN_H := 200
const BUFFER_SIZE := SCREEN_W * SCREEN_H
const DEFAULT_FPS := 16          # rngplay.c: iSpeed == 0 ? 16 : iSpeed
const CANVAS_LAYER := 5
const SHOT_DIR := "<LOCAL_PATH>"
## 实测 12 个动画的有效帧数（rng_index.json 逐块一致；合计 1464，注意 MISC-FORMAT 正文
## 里“1138 帧”为旧笔误，以本节实测/rng_index.json 为准）
const EXPECTED_FRAMES: Array[int] = [64, 410, 93, 140, 40, 82, 54, 70, 33, 256, 42, 180]
const EXPECTED_TOTAL := 1464

var data_dir: String = ""
var rng_mkf: MkfFile = null
var palette: PackedColorArray = PackedColorArray()
## 当前累积画面（320×200 索引）
var index_buffer: PackedByteArray = PackedByteArray()
var image: Image = null
var texture: ImageTexture = null

var _sprite: Sprite2D = null
var _layer: CanvasLayer = null
var _anim_cache: Dictionary = {}      # rng_id -> Array[PackedByteArray]（解压后的命令流）
var _playing: bool = false
var _last_frame: int = -1
var _palette_ready: bool = false


func _ready() -> void:
	_ensure_init()
	_setup_display()


func _ensure_init() -> void:
	if data_dir == "":
		data_dir = PalConfig.require_data_dir()
	if rng_mkf == null and data_dir != "":
		rng_mkf = MkfFile.open_asset(data_dir, "Rng.mkf")
	if palette.is_empty():
		palette = load_default_palette(data_dir)
	if index_buffer.size() != BUFFER_SIZE:
		index_buffer = PackedByteArray()
		index_buffer.resize(BUFFER_SIZE)
		index_buffer.fill(0)
	if image == null:
		image = Image.create_empty(SCREEN_W, SCREEN_H, false, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 1))
	if texture == null:
		texture = ImageTexture.create_from_image(image)


func _setup_display() -> void:
	if _layer != null:
		return
	_layer = CanvasLayer.new()
	_layer.name = "RngLayer"
	_layer.layer = CANVAS_LAYER
	add_child(_layer)
	_sprite = Sprite2D.new()
	_sprite.name = "RngScreen"
	_sprite.centered = false
	_sprite.scale = Vector2(2, 2)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.texture = texture
	_layer.add_child(_sprite)


## PAT.MKF 块 0 的 day 调色板（战斗 RNG 会按场景 palette 着色，这里默认块 0，[unk] 需上层覆盖）
static func load_default_palette(dir: String) -> PackedColorArray:
	if dir == "":
		return PackedColorArray()
	var pat := MkfFile.open_asset(dir, "Pat.mkf")
	if pat == null:
		return PackedColorArray()
	var raw := pat.chunk(0)
	if raw.size() < 768:
		return PackedColorArray()
	var pal := PalSprite.palette_from_bytes(raw.slice(0, 768))
	pal[0] = Color(0, 0, 0, 1)
	return pal


func set_palette(p: PackedColorArray) -> void:
	if p.is_empty():
		return
	palette = p
	_update_texture()


# ---------------------------------------------------------------- 帧解码

## 取某动画的全部解压帧流（缓存）。
func load_animation(rng_id: int) -> Array:
	if _anim_cache.has(rng_id):
		return _anim_cache[rng_id]
	var frames: Array = []
	if rng_mkf == null or rng_id < 0 or rng_id >= rng_mkf.chunk_count:
		_anim_cache[rng_id] = frames
		return frames
	var chunk := rng_mkf.chunk(rng_id)
	if chunk.size() < 8:
		_anim_cache[rng_id] = frames
		return frames
	var head := _u32(chunk, 0)
	var n := (head - 4) / 4
	if n <= 0 or n > 4096:
		_anim_cache[rng_id] = frames
		return frames
	for i in range(n):
		var off := _u32(chunk, 4 * i)
		var next := _u32(chunk, 4 * (i + 1))
		if next <= off or next > chunk.size():
			continue  # 末尾空帧
		var raw := chunk.slice(off, next)
		if raw.size() < 5:
			continue
		var size := _u32(raw, 0)
		if size <= 0 or size > BUFFER_SIZE * 4:
			continue
		var dec := MkfFile.yj2_decompress(raw, 4, size)
		if dec.size() > 0:
			frames.append(dec)
	_anim_cache[rng_id] = frames
	return frames


## 把一帧命令流累积画到索引缓冲（rngplay.c PAL_RNGBlitToSurface 的等价实现）。
## 返回 "ok" / "truncated" / "overflow"。
func apply_frame_to_buffer(stream: PackedByteArray) -> String:
	var buf := index_buffer
	var n := stream.size()
	var ptr := 0
	var dst := 0
	var written := false
	var result := "ok"
	while ptr < n:
		var cmd := stream[ptr]
		ptr += 1
		if cmd == 0x00 or cmd == 0x13:
			result = "ok"
			break
		elif cmd == 0x02:
			dst += 2
		elif cmd == 0x03:
			if ptr >= n:
				result = "truncated"
				break
			dst += (stream[ptr] + 1) * 2
			ptr += 1
		elif cmd == 0x04:
			if ptr + 1 >= n:
				result = "truncated"
				break
			dst += (_u16(stream, ptr) + 1) * 2
			ptr += 2
		elif cmd >= 0x06 and cmd <= 0x0a:
			# C 的 0x0a→0x09→...→0x06 fallthrough：写 (cmd-5) 对像素
			var cnt := cmd - 5
			if ptr + cnt * 2 > n:
				result = "truncated"
				break
			for k in range(cnt):
				if dst >= 0 and dst + 1 < BUFFER_SIZE:
					buf[dst] = stream[ptr]
					buf[dst + 1] = stream[ptr + 1]
					written = true
				dst += 2
				ptr += 2
		elif cmd == 0x0b:
			if ptr >= n:
				result = "truncated"
				break
			var d := stream[ptr]
			ptr += 1
			if ptr + (d + 1) * 2 > n:
				result = "truncated"
				break
			for k in range(d + 1):
				if dst >= 0 and dst + 1 < BUFFER_SIZE:
					buf[dst] = stream[ptr]
					buf[dst + 1] = stream[ptr + 1]
					written = true
				dst += 2
				ptr += 2
		elif cmd == 0x0c:
			if ptr + 1 >= n:
				result = "truncated"
				break
			var d2 := _u16(stream, ptr)
			ptr += 2
			if ptr + (d2 + 1) * 2 > n:
				result = "truncated"
				break
			for k in range(d2 + 1):
				if dst >= 0 and dst + 1 < BUFFER_SIZE:
					buf[dst] = stream[ptr]
					buf[dst + 1] = stream[ptr + 1]
					written = true
				dst += 2
				ptr += 2
		elif cmd >= 0x0d and cmd <= 0x10:
			# 用同一对像素重复 (cmd-11) 次
			if ptr + 1 >= n:
				result = "truncated"
				break
			var a := stream[ptr]
			var b := stream[ptr + 1]
			ptr += 2
			for k in range(cmd - 11):
				if dst >= 0 and dst + 1 < BUFFER_SIZE:
					buf[dst] = a
					buf[dst + 1] = b
					written = true
				dst += 2
		elif cmd == 0x11:
			if ptr >= n:
				result = "truncated"
				break
			var d3 := stream[ptr]
			ptr += 1
			if ptr + 1 >= n:
				result = "truncated"
				break
			var a3 := stream[ptr]
			var b3 := stream[ptr + 1]
			ptr += 2
			for k in range(d3 + 1):
				if dst >= 0 and dst + 1 < BUFFER_SIZE:
					buf[dst] = a3
					buf[dst + 1] = b3
					written = true
				dst += 2
		elif cmd == 0x12:
			if ptr + 1 >= n:
				result = "truncated"
				break
			var d4 := _u16(stream, ptr) + 1
			ptr += 2
			if ptr + 1 >= n:
				result = "truncated"
				break
			var a4 := stream[ptr]
			var b4 := stream[ptr + 1]
			ptr += 2
			for k in range(d4):
				if dst >= 0 and dst + 1 < BUFFER_SIZE:
					buf[dst] = a4
					buf[dst + 1] = b4
					written = true
				dst += 2
		# 其它命令: rngplay.c 中未定义/忽略
	index_buffer = buf
	# 注意：rngplay.c 不检查越界，目的缓冲实际分配 65000B（>64000），末尾几像素会写到
	# 屏幕外；本移植对越界写直接丢弃，但**不算错误**（帧流本身是合法的）。
	return result


# ---------------------------------------------------------------- 渲染到纹理

func _update_texture() -> void:
	if image == null or texture == null:
		return
	if palette.is_empty():
		return
	# indexed → RGBA8（64000 像素；用 set_pixel 逐点写，实测 16fps 可接受）
	var pal := palette
	var img := image
	var buf := index_buffer
	for y in range(SCREEN_H):
		var row := y * SCREEN_W
		for x in range(SCREEN_W):
			img.set_pixel(x, y, pal[buf[row + x]])
	texture.update(img)


func get_frame_image() -> Image:
	_update_texture()
	return image


# ---------------------------------------------------------------- 播放

## 非阻塞播放：播放完 emit finished。
func play(rng_id: int, x: int = 0, y: int = 0, layer: int = 0) -> void:
	play_full(rng_id, 0, -1, 0, x, y, layer)


## sdlpal PAL_RNGPlay(iNumRNG, iStartFrame, iEndFrame, iSpeed) 的移植。
## end_frame：>0 时按 sdlpal 语义 +1（含末帧）；-1 表示到动画结束。
func play_full(rng_id: int, start_frame: int = 0, end_frame: int = -1, speed: int = 0,
		x: int = 0, y: int = 0, layer: int = 0) -> void:
	_ensure_init()
	if rng_mkf == null:
		push_error("RngPlayer: Rng.mkf 不可用，无法播放 %d" % rng_id)
		finished.emit()
		return
	_playing = true
	_last_frame = -1
	index_buffer.fill(0)
	image.fill(Color(0, 0, 0, 1))
	if _layer != null:
		_layer.layer = layer if layer != 0 else CANVAS_LAYER
	if _sprite != null:
		_sprite.position = Vector2(x, y)
	var frames := load_animation(rng_id)
	if frames.is_empty():
		push_warning("RngPlayer: RNG %d 无有效帧" % rng_id)
		_playing = false
		finished.emit()
		return
	var fps := float(DEFAULT_FPS if speed <= 0 else speed)
	var frame := start_frame
	var stop_at := end_frame
	if stop_at > 0:
		stop_at += 1
	var played := 0
	while _playing:
		if stop_at > 0 and frame == stop_at:
			break
		if frame < 0 or frame >= frames.size():
			break
		if not _apply_and_show(frames[frame]):
			break
		_last_frame = frame
		played += 1
		frame += 1
		await get_tree().create_timer(1.0 / fps).timeout
		if not is_inside_tree():
			return
	_playing = false
	print("[RngPlayer] RNG %d 播放结束：帧 %d..%d，共 %d 帧，%.1f fps" % [
		rng_id, start_frame, _last_frame, played, fps,
	])
	finished.emit()


func _apply_and_show(stream: PackedByteArray) -> bool:
	var ok := apply_frame_to_buffer(stream)
	_update_texture()
	frame_ready.emit(image)
	return ok != "truncated"


func stop() -> void:
	_playing = false


## 隐藏自带画面（结局等上层模块切镜头用）
func set_screen_visible(v: bool) -> void:
	if _layer != null:
		_layer.visible = v


func is_playing() -> bool:
	return _playing


func get_last_frame() -> int:
	return _last_frame


# ---------------------------------------------------------------- 工具

func _u16(b: PackedByteArray, o: int) -> int:
	return b[o] | (b[o + 1] << 8)


func _u32(b: PackedByteArray, o: int) -> int:
	return b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)


# ---------------------------------------------------------------- --rng-test

## 自测：解全部 12 个动画命令流、校验帧数/消耗、渲染 RNG0 全部帧为 PNG + 拼图。
## 由 PALAudio._ready 的 --rng-test 分支调用（静态入口，无需场景）。
static func run_self_test() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var node := RngPlayer.new()
	node.name = "RngSelfTest"
	tree.root.add_child(node)
	node._run_test()


func _run_test() -> void:
	print("[rng-test] ===== 开始：Rng.mkf 命令流动画自测 =====")
	var t0 := Time.get_ticks_msec()
	_ensure_init()
	if rng_mkf == null:
		push_error("[rng-test] Rng.mkf 不可用")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var log_lines := PackedStringArray()
	log_lines.append("Rng.mkf 块数=%d 调色板=%d" % [rng_mkf.chunk_count, palette.size()])
	var fail := 0
	var ok := 0
	if rng_mkf.chunk_count != 12:
		print("[rng-test] FAIL 块数=%d（期望 12）" % rng_mkf.chunk_count)
		fail += 1
	else:
		ok += 1
	var all_frames := 0
	for id in range(mini(rng_mkf.chunk_count, EXPECTED_FRAMES.size())):
		var frames := load_animation(id)
		var expected := EXPECTED_FRAMES[id]
		var good := frames.size() == expected
		if good:
			ok += 1
		else:
			fail += 1
		all_frames += frames.size()
		var line := "RNG %d: 有效帧=%d（期望 %d）%s" % [id, frames.size(), expected, "" if good else " ✗"]
		print("[rng-test] %s" % line)
		log_lines.append(line)
	if all_frames == EXPECTED_TOTAL and ok >= 13:
		ok += 1
	else:
		fail += 1
	print("[rng-test] 全部动画帧数合计=%d（期望 %d）" % [all_frames, EXPECTED_TOTAL])
	log_lines.append("全部动画帧数合计=%d（期望 %d）" % [all_frames, EXPECTED_TOTAL])

	# 逐帧 apply 校验（全部 12 个动画，只统计终止状态，不截图）
	var truncated := 0
	var overflow := 0
	var applied := 0
	for id in range(mini(rng_mkf.chunk_count, EXPECTED_FRAMES.size())):
		index_buffer.fill(0)
		for stream in load_animation(id):
			var st := apply_frame_to_buffer(stream)
			applied += 1
			if st == "truncated":
				truncated += 1
			elif st == "overflow":
				overflow += 1
	print("[rng-test] 命令流消耗：apply=%d truncated=%d overflow=%d" % [applied, truncated, overflow])
	log_lines.append("命令流消耗：apply=%d truncated=%d overflow=%d" % [applied, truncated, overflow])
	if truncated == 0 and applied == all_frames:
		ok += 1
	else:
		fail += 1

	# RNG 0 逐帧渲染：每帧 PNG + 8 帧拼图
	var rng_id := 0
	var frames0 := load_animation(rng_id)
	index_buffer.fill(0)
	var png_count := 0
	var picks: Array[int] = [0, 1, 8, 16, 32, 48, 56, frames0.size() - 1]
	var picks_images: Array = []
	for i in range(frames0.size()):
		var st := apply_frame_to_buffer(frames0[i])
		if st == "truncated":
			break
		_update_texture()
		if i in picks:
			picks_images.append(image.duplicate())
		if DisplayServer.get_name() != "headless":
			pass  # Image 保存不依赖窗口，headless 也保存
		var path := SHOT_DIR + "rng0_frame%03d.png" % i
		image.save_png(path)
		png_count += 1
	if png_count == frames0.size():
		ok += 1
	else:
		fail += 1
	print("[rng-test] RNG0 逐帧 PNG: %d 张（期望 %d）→ %srng0_frame*.png" % [
		png_count, frames0.size(), SHOT_DIR,
	])
	log_lines.append("RNG0 逐帧 PNG: %d 张 → %srng0_frame*.png" % [png_count, SHOT_DIR])

	# 拼图 4×2（帧 0/1/8/16/32/48/56/末帧）
	if picks_images.size() >= 8:
		var montage := Image.create_empty(SCREEN_W * 4, SCREEN_H * 2, false, Image.FORMAT_RGBA8)
		montage.fill(Color(0, 0, 0, 1))
		for k in range(8):
			var src: Image = picks_images[k]
			montage.blit_rect(src, Rect2i(0, 0, SCREEN_W, SCREEN_H),
				Vector2i((k % 4) * SCREEN_W, (k / 4) * SCREEN_H))
		montage.save_png(SHOT_DIR + "rng0_montage.png")
		print("[rng-test] 拼图: %srng0_montage.png（帧 %s）" % [SHOT_DIR, str(picks)])
		log_lines.append("拼图: rng0_montage.png 帧 %s" % str(picks))

	# RNG 1 末帧（大动画）
	var frames1 := load_animation(1)
	if not frames1.is_empty():
		index_buffer.fill(0)
		for stream in frames1:
			apply_frame_to_buffer(stream)
		_update_texture()
		image.save_png(SHOT_DIR + "rng1_last.png")
		print("[rng-test] RNG1 末帧: %srng1_last.png（共 %d 帧）" % [SHOT_DIR, frames1.size()])
		log_lines.append("RNG1 末帧: rng1_last.png（共 %d 帧）" % frames1.size())

	var elapsed := Time.get_ticks_msec() - t0
	log_lines.append("用时 %d ms；%d 通过 / %d 失败" % [elapsed, ok, fail])
	var fa := FileAccess.open(SHOT_DIR + "rng_test_report.txt", FileAccess.WRITE)
	if fa != null:
		fa.store_string("\n".join(log_lines) + "\n")
		fa.close()
	print("[rng-test] 报告: %srng_test_report.txt" % SHOT_DIR)
	print("[rng-test] ===== 完成，用时 %d ms，%d 通过 / %d 失败 =====" % [elapsed, ok, fail])
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0 if fail == 0 else 1)
