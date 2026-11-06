class_name Ending
extends Node
## 结局演出（移植 sdlpal ending.c: PAL_EndingScreen / PAL_ShowFBP / PAL_ScrollFBP /
## PAL_EndingAnimation / PAL_EndingSetEffectSprite）。
##
## 由 world.script_end_game() 实例化并 add_child；节点在 _ready() 里自行播放整段结局。
## 数据：Fbp.mkf（YJ2 → 320×200 8bpp）、Mgo.mkf（ending 特效精灵 571/572/0x27B）、
##       Pat.mkf（调色板 0/4/5/8）、Rng.mkf（RngPlayer 播放）、PALAudio（BGM）。
##
## 已知偏差（必须在文档中记录）：
##   * AVI：原版 Win95 结局先播 4.AVI / 5.AVI / 6.AVI；Godot 无 AVI 解码器，
##     本实现直接跳过并写日志（AVI 文件在数据目录中存在，9~82MB）。
##   * PAL_ShowFBP 的 6 相位抖动淡入、PAL_ColorFade、PAL_ApplyWave（水波）未逐像素移植，
##     这里用整体 alpha 淡入淡出替代，视觉近似。
##   * gpGlobals->iCurPlayingRNG（进入结局前脚本播放的 RNG 号）world 未暴露，暂用 0 [unk]。
##   * ScrollFBP 的 220 步循环保留（speed=0xF 时约 11 秒），可用 fast_mode 加速。

signal finished

const SCREEN_W := 320
const SCREEN_H := 200
const SHOT_DIR := "<LOCAL_PATH>"
const CANVAS_LAYER := 20
const OVERLAY_LAYER := 22
const RNG_LAYER := 21

## 快速模式（--ending-test 用）：所有延时 ×time_scale
var time_scale: float = 1.0
var fast_mode: bool = false

var data_dir: String = ""
var fbp_mkf: MkfFile = null
var mgo_mkf: MkfFile = null
var pat_mkf: MkfFile = null
var rng_player: RngPlayer = null

var _layer: CanvasLayer = null
var _sprite: Sprite2D = null
var _overlay: ColorRect = null
var _image: Image = null
var _texture: ImageTexture = null
var _palette_num: int = 0
var _palettes: Dictionary = {}
var _rng_segment: RngPlayer = null
var _key_pressed: bool = false
var _skip: bool = false


func _ready() -> void:
	add_to_group("ending")
	data_dir = PalConfig.require_data_dir()
	if data_dir == "":
		push_error("Ending: 数据目录不可用")
		finished.emit()
		return
	fbp_mkf = MkfFile.open_asset(data_dir, "Fbp.mkf")
	mgo_mkf = MkfFile.open_asset(data_dir, "Mgo.mkf")
	pat_mkf = MkfFile.open_asset(data_dir, "Pat.mkf")
	_setup_display()
	if "--auto" in OS.get_cmdline_args():
		_skip = true      # 自动验收：跳过按键等待，尽快跑完结局流程
	if "--ending-test" in OS.get_cmdline_args():
		fast_mode = true
		time_scale = 0.02
	call_deferred("_play_sequence")


func _setup_display() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "EndingLayer"
	_layer.layer = CANVAS_LAYER
	add_child(_layer)
	_image = Image.create_empty(SCREEN_W, SCREEN_H, false, Image.FORMAT_RGBA8)
	_image.fill(Color(0, 0, 0, 1))
	_texture = ImageTexture.create_from_image(_image)
	_sprite = Sprite2D.new()
	_sprite.name = "EndingScreen"
	_sprite.centered = false
	_sprite.scale = Vector2(2, 2)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.texture = _texture
	_layer.add_child(_sprite)
	var ov := CanvasLayer.new()
	ov.name = "EndingFade"
	ov.layer = OVERLAY_LAYER
	add_child(ov)
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(_overlay)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		_key_pressed = true


# ---------------------------------------------------------------- 资源

func _palette(n: int) -> PackedColorArray:
	if _palettes.has(n):
		return _palettes[n]
	var pal := PackedColorArray()
	if pat_mkf != null and n >= 0 and n < pat_mkf.chunk_count:
		var raw := pat_mkf.chunk(n)
		if raw.size() >= 768:
			pal = PalSprite.palette_from_bytes(raw.slice(0, 768))
	if pal.is_empty():
		pal.resize(256)
		pal.fill(Color(0, 0, 0, 1))
	pal[0] = Color(0, 0, 0, 1)
	_palettes[n] = pal
	return pal


func _load_fbp(chunk: int) -> Image:
	if fbp_mkf == null or chunk < 0 or chunk >= fbp_mkf.chunk_count:
		return null
	var raw := fbp_mkf.decompressed(chunk)
	if raw.size() < SCREEN_W * SCREEN_H:
		return null
	return _indexed_to_rgba(raw, _palette(_palette_num))


func _indexed_to_rgba(buf: PackedByteArray, pal: PackedColorArray) -> Image:
	var img := Image.create_empty(SCREEN_W, SCREEN_H, false, Image.FORMAT_RGBA8)
	for y in range(SCREEN_H):
		var row := y * SCREEN_W
		for x in range(SCREEN_W):
			img.set_pixel(x, y, pal[buf[row + x]])
	return img


func _mgo_frames(chunk: int) -> Array:
	if mgo_mkf == null or chunk < 0 or chunk >= mgo_mkf.chunk_count:
		return []
	var raw := mgo_mkf.decompressed(chunk)
	return PalSprite.decode_sprite(raw, _palette(_palette_num))


# ---------------------------------------------------------------- 显示原语

func _set_image(img: Image) -> void:
	if img == null:
		return
	_image = img
	_texture.update(_image)


func _show_fbp(chunk: int, fade: int = 0) -> void:
	var img := _load_fbp(chunk)
	if img == null:
		push_warning("Ending: FBP %d 读取失败" % chunk)
		return
	_set_image(img)
	_sprite.visible = true
	if fade > 0:
		await _fade_in(0.25 * clampf(float(fade) / 7.0, 0.3, 2.0))


func _await(seconds: float) -> void:
	var t := maxf(0.0, seconds) * time_scale
	if t <= 0.0:
		return
	await get_tree().create_timer(t).timeout


func _fade_out(seconds: float = 0.4) -> void:
	_overlay.color = Color(0, 0, 0, _overlay.color.a)
	var tw := create_tween()
	tw.tween_property(_overlay, "color:a", 1.0, maxf(0.01, seconds * time_scale))
	await tw.finished


func _fade_in(seconds: float = 0.4) -> void:
	var tw := create_tween()
	tw.tween_property(_overlay, "color:a", 0.0, maxf(0.01, seconds * time_scale))
	await tw.finished


func _fill_black() -> void:
	_image.fill(Color(0, 0, 0, 1))
	_texture.update(_image)
	_sprite.visible = true


## 直接设定黑幕透明度（不做 tween）；RNG 等整屏重画时用来清除黑幕。
func _set_overlay_alpha(a: float) -> void:
	if _overlay != null:
		_overlay.color = Color(0, 0, 0, clampf(a, 0.0, 1.0))


## PAL_ScrollFBP：图从屏幕外滚动进入（用两个 region Sprite 实现环绕滚动，不逐像素合成）。
func _scroll_fbp(chunk: int, speed: int, scroll_down: bool) -> void:
	var img := _load_fbp(chunk)
	if img == null:
		return
	_set_image(img)
	_sprite.visible = false
	var tex := _texture
	var a := Sprite2D.new()
	a.centered = false
	a.scale = Vector2(2, 2)
	a.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	a.texture = tex
	a.region_enabled = true
	_layer.add_child(a)
	var b := Sprite2D.new()
	b.centered = false
	b.scale = Vector2(2, 2)
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	b.texture = tex
	b.region_enabled = true
	_layer.add_child(b)
	var spd := maxi(1, speed)
	var per := 800.0 / float(spd) / 1000.0 * time_scale
	var steps := 200
	for i in range(steps + 1):
		var off := i
		if not scroll_down:
			off = steps - i
		var h := 200 - off
		if h > 0:
			a.region_rect = Rect2(0, 0, SCREEN_W, h)
			a.position = Vector2(0, off * 2)
		else:
			a.region_rect = Rect2(0, 0, 0, 0)
		if off > 0:
			b.region_rect = Rect2(0, h, SCREEN_W, off)
			b.position = Vector2(0, 0)
		else:
			b.region_rect = Rect2(0, 0, 0, 0)
		if i % 4 == 0 or i == steps:
			await _await(per * 4)
		if _skip:
			break
	a.queue_free()
	b.queue_free()
	_sprite.visible = true


## PAL_EndingAnimation：上下两张 FBP 合拢 + 妖兽/少女精灵。
func _ending_animation() -> void:
	_palette_num = 4
	var upper := _load_fbp(69)
	var lower := _load_fbp(70)
	_palette_num = 4
	var beast_frames := _mgo_frames(571)
	var girl_frames := _mgo_frames(572)
	var img := Image.create_empty(SCREEN_W, SCREEN_H, false, Image.FORMAT_RGBA8)
	var y_girl := 180
	var steps := 400
	var step_delay := 0.05 * time_scale
	for i in range(steps):
		img.fill(Color(0, 0, 0, 1))
		var half := i / 2
		var lh := 200 - half
		if lower != null and lh > 0:
			img.blit_rect(lower, Rect2i(0, 0, SCREEN_W, lh), Vector2i(0, half))
		if upper != null and half > 0:
			img.blit_rect(upper, Rect2i(0, 200 - half, SCREEN_W, half), Vector2i(0, 0))
		# 妖兽（两帧，分别从上下方入场）
		if beast_frames.size() >= 2:
			_blend_sprite(img, beast_frames[0], 0, -400 + i)
			_blend_sprite(img, beast_frames[1], 0, -200 + i)
		# 少女
		if not girl_frames.is_empty():
			y_girl -= i & 1
			if y_girl < 80:
				y_girl = 80
			var gf: Image = girl_frames[(i / 3) % girl_frames.size()]
			_blend_sprite(img, gf, 220, y_girl)
		_set_image(img.duplicate())
		if i == 150:
			await _shot("anim150")
		if i % 2 == 0:
			await _await(step_delay * 2)
		if _skip:
			break


func _blend_sprite(dst: Image, spr: Image, x: int, y: int) -> void:
	if spr == null:
		return
	var w := spr.get_width()
	var h := spr.get_height()
	var sx0 := maxi(0, -x)
	var sy0 := maxi(0, -y)
	if sx0 >= w or sy0 >= h:
		return
	var dw := mini(w - sx0, SCREEN_W - x - sx0)
	var dh := mini(h - sy0, SCREEN_H - y - sy0)
	if dw <= 0 or dh <= 0:
		return
	dst.blend_rect(spr, Rect2i(sx0, sy0, dw, dh), Vector2i(x + sx0, y + sy0))


## RNG 片段播放：用独立 RngPlayer（layer 21，位于结局画面之上、淡入淡出之下）。
func _play_rng_segment(rng_id: int, start_frame: int, end_frame: int, speed: int) -> void:
	if rng_player == null:
		rng_player = RngPlayer.new()
		rng_player.name = "EndingRng"
		add_child(rng_player)
	var spd := speed
	if fast_mode:
		spd = maxi(1, int(float(speed) / maxf(0.01, time_scale)))
	# 注意：若片段为空，play_full 会同步 emit finished，直接 await 会永久挂起；
	# 先连回调再看 is_playing。
	var done := [false]
	var cb := func() -> void:
		done[0] = true
	rng_player.finished.connect(cb, CONNECT_ONE_SHOT)
	rng_player.play_full(rng_id, start_frame, end_frame, spd, 0, 0, RNG_LAYER)
	while not done[0] and rng_player != null and rng_player.is_playing():
		await get_tree().process_frame
	await get_tree().process_frame


func _wait_key(max_seconds: float = 0.0) -> void:
	_key_pressed = false
	if max_seconds <= 0.0:
		while not _key_pressed and not _skip:
			await get_tree().process_frame
	else:
		await _await(max_seconds)
	_key_pressed = false


# ---------------------------------------------------------------- 主流程（ending.c: PAL_EndingScreen，WIN95 分支）

func _play_sequence() -> void:
	print("[Ending] 开始结局演出（AVI 段跳过：Godot 无 AVI 解码）")
	_play_music(26, true)  # AUDIO_PlayMusic(0x1a, TRUE, 0)

	# PAL_RNGPlay(gpGlobals->iCurPlayingRNG, 110, 150, 7); PAL_RNGPlay(..., 151, -1, 9)
	var cur_rng: int = int(PALState.current_rng) if PALState != null else 0
	await _play_rng_segment(cur_rng, 110, 150, 7)
	await _play_rng_segment(cur_rng, 151, -1, 9)
	_rng_player_hide()

	await _fade_out(0.8)
	_play_music(25, true)  # 0x19
	_palette_num = 0
	await _show_fbp(75, 0)
	await _fade_in(0.8)
	await _shot("fbp75")
	await _scroll_fbp(74, 0xf, true)
	await _fade_out(0.5)

	# PAL_FadeOut(1) → 全黑 → palette 4 → PAL_EndingAnimation（内部 fNeedToFadeIn 淡入）
	_fill_black()
	_palette_num = 4
	await _fade_in(1.0)
	await _ending_animation()
	_play_music(0, false)  # 停止
	await _await(0.5)
	_play_music(17, true)  # 0x11

	# PAL_ColorFade(7,15,FALSE) 淡到黑 → 全黑 → palette 0 → RNG 0xb
	await _fade_out(0.8)
	_fill_black()
	_palette_num = 0
	_set_overlay_alpha(0.0)   # RNG 直接重画整屏，不再压黑
	await _play_rng_segment(11, 0, -1, 7)
	await _fade_out(0.8)

	# palette 8 → RNG 10 → ShowFBP(77..)
	_fill_black()
	_palette_num = 8
	_set_overlay_alpha(0.0)
	await _play_rng_segment(10, 0, -1, 6)
	_rng_player_hide()
	_set_effect_sprite(0)
	await _show_fbp(77, 10)
	await _shot("fbp77")
	await _show_fbp(76, 7)   # 原版带特效精灵 0x27b
	_palette_num = 5
	await _show_fbp(73, 7)
	await _scroll_fbp(72, 0xf, true)
	await _show_fbp(71, 7)
	await _show_fbp(68, 7)
	_set_effect_sprite(0)
	await _show_fbp(68, 6)
	await _shot("fbp68")
	await _wait_key(3.0)
	_play_music(0, false)
	await _await(0.5)

	# 6.AVI 跳过 → PAL_ScrollFBP(67..59)
	_play_music(9, true)
	for c in range(67, 58, -1):
		await _scroll_fbp(c, 0xf, true)
	_play_music(0, false)
	await _fade_out(1.2)

	print("[Ending] 结局演出结束（AVI 段与抖动淡入/水波为已知偏差）")
	finished.emit()
	await _await(0.3)
	if fast_mode:
		get_tree().quit(0)


func _rng_player_hide() -> void:
	if rng_player != null:
		rng_player.stop()
		rng_player.set_screen_visible(false)
		rng_player.queue_free()
		rng_player = null


## --ending-test 截图取证（仅窗口模式）
func _shot(tag: String) -> void:
	if not fast_mode or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(SHOT_DIR + "ending_%s.png" % tag)
		print("[Ending] SHOT %sending_%s.png" % [SHOT_DIR, tag])


var _effect_sprite_id: int = 0


func _set_effect_sprite(id: int) -> void:
	_effect_sprite_id = id


func _play_music(num: int, loop: bool) -> void:
	if PALAudio != null and PALAudio.ready_flag:
		PALAudio.play_music(num, loop)


# ---------------------------------------------------------------- --ending-test

static func run_self_test() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var e := Ending.new()
	e.name = "EndingSelfTest"
	e.fast_mode = true
	e.time_scale = 0.02
	tree.root.add_child(e)
