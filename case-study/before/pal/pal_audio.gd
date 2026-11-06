extends Node
## 音频层（autoload `PALAudio`）。
## 对应 sdlpal audio.c / sound.c / midi*.c：
##   * 音效：Sounds.mkf 505 块（142 空），非空块 = 裸 RIFF/WAVE（实测 PCM 16bit mono 22050Hz）
##           → 手工解析 RIFF 填 AudioStreamWAV（不依赖 load_from_buffer 的版本差异）。
##   * BGM：MUS.MKF（88 块，0x55AA 头，[unk] 未解码，非 RIX/MIDI 签名）；
##           但游戏目录 `Musics/NNN.mid`（001..087，缺 029）与脚本音乐号一一对应
##           （脚本 0x0043 操作数实测 0..87；MUS.MKF 非空块号同为 1..87 缺 29）。
##           Godot 无 MIDI 合成器 → 约定读取离线预渲染的 `data/bgm/NNN.wav`（或 .ogg）；
##           未找到时只打日志、不伪造播放。离线转换工具：tools/audio_midi_render.py。
##   * 语音：PAL.Administrator.ini 有 [Audio] EnableVoice（实测 0=关），故 play_voice 仅记录后跳过。
##
## 对外 API（world 已接 play_music(num, loop) / play_sound(num)）：
##   init(dir) / play_music / stop_music / play_sound / play_voice
##   另有音量、开关、音效回读/导出（--audio-test 用）。

const SHOT_DIR := "<LOCAL_PATH>"
const SOUND_PLAYER_COUNT := 8
## sdlpal palcfg.h: PAL_MAX_VOLUME = 100，缺省音量 100
const PAL_MAX_VOLUME := 100
const BGM_DIR := "res://data/bgm/"

var ready_flag: bool = false
var data_dir: String = ""

var sounds_mkf: MkfFile = null
var sound_count: int = 0
var mus_mkf: MkfFile = null
var music_count: int = 0

var music_enabled: bool = true
var sound_enabled: bool = true
var music_volume: int = PAL_MAX_VOLUME
var sound_volume: int = PAL_MAX_VOLUME

## 语音开关（读 PAL.Administrator.ini，实测 EnableVoice=0）
var voice_enabled: bool = false

## 当前/最近一次音乐号（0 = 未播放）
var music_num: int = -1

var _sound_cache: Dictionary = {}
var _play_warned: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _music_player: AudioStreamPlayer = null
var _voice_player: AudioStreamPlayer = null
var _last_sound: int = -9999
var _bgm_files: Dictionary = {}   # num -> res path（离线预渲染的 wav/ogg）

## 音频自测统计（--audio-test）
var _test_log: PackedStringArray = PackedStringArray()


func _ready() -> void:
	var args := OS.get_cmdline_args()
	if "--audio-test" in args:
		call_deferred("run_self_test")
	elif "--rng-test" in args:
		call_deferred("_run_rng_test")
	elif "--ending-test" in args:
		call_deferred("_run_ending_test")


# ---------------------------------------------------------------- 装载

func init(p_data_dir: String) -> void:
	data_dir = p_data_dir
	ready_flag = false
	_sound_cache.clear()
	_play_warned.clear()
	_last_sound = -9999

	sounds_mkf = MkfFile.open_asset(data_dir, "Sounds.mkf")
	if sounds_mkf != null:
		sound_count = sounds_mkf.chunk_count
	else:
		sound_count = 0
		push_warning("PALAudio: Sounds.mkf 打不开（音效不可用）")

	mus_mkf = MkfFile.open_asset(data_dir, "MUS.MKF")
	music_count = mus_mkf.chunk_count if mus_mkf != null else 0

	_setup_players()
	_load_config()
	_scan_bgm()
	ready_flag = true
	print("[PALAudio] init: sounds=%d mus=%d bgm预渲染=%d voice=%s" % [
		sound_count, music_count, _bgm_files.size(), "on" if voice_enabled else "off",
	])


func _setup_players() -> void:
	if _players.is_empty():
		for i in range(SOUND_PLAYER_COUNT):
			var p := AudioStreamPlayer.new()
			p.name = "SFX%d" % i
			add_child(p)
			_players.append(p)
	if _music_player == null:
		_music_player = AudioStreamPlayer.new()
		_music_player.name = "Music"
		add_child(_music_player)
	if _voice_player == null:
		_voice_player = AudioStreamPlayer.new()
		_voice_player.name = "Voice"
		add_child(_voice_player)


## 读 PAL.Administrator.ini 的 [Audio] EnableVoice（实测该游戏为 0）
func _load_config() -> void:
	voice_enabled = false
	var path := data_dir + "PAL.Administrator.ini"
	if not FileAccess.file_exists(path):
		return
	var fa := FileAccess.open(path, FileAccess.READ)
	# 该 ini 是 GBK 编码（含中文注释）；只用 ASCII 行解析 EnableVoice，避免 UTF-8 解码告警
	var text := fa.get_buffer(fa.get_length()).get_string_from_ascii()
	fa.close()
	for line in text.split("\n"):
		var s := line.strip_edges()
		if s.begins_with("EnableVoice"):
			var v := s.split("=")
			if v.size() >= 2:
				voice_enabled = int(v[1].strip_edges()) != 0


## 扫描 data/bgm 下离线预渲染的音乐（NNN.wav / NNN.ogg）
func _scan_bgm() -> void:
	_bgm_files.clear()
	for num in range(1, 256):
		for ext in [".wav", ".ogg"]:
			var p := BGM_DIR + "%03d%s" % [num, ext]
			if ResourceLoader.exists(p):
				_bgm_files[num] = p
				break


# ---------------------------------------------------------------- WAV 解析

## 把 bare RIFF/WAVE 字节解析成 AudioStreamWAV（sound.c SOUND_LoadWAVEData 的等价物）。
func stream_from_wav(data: PackedByteArray) -> AudioStreamWAV:
	if data.size() < 44:
		return null
	if _ascii(data, 0, 4) != "RIFF" or _ascii(data, 8, 4) != "WAVE":
		return null
	var pos := 12
	var fmt_tag := -1
	var channels := 1
	var rate := 22050
	var bits := 16
	var data_off := -1
	var data_len := 0
	while pos + 8 <= data.size():
		var id := _ascii(data, pos, 4)
		var sz := _u32(data, pos + 4)
		if id == "fmt " and sz >= 16 and pos + 8 + 16 <= data.size():
			fmt_tag = _u16(data, pos + 8)
			channels = _u16(data, pos + 10)
			rate = _u32(data, pos + 12)
			bits = _u16(data, pos + 22)
		elif id == "data":
			data_off = pos + 8
			data_len = mini(sz, data.size() - data_off)
			break
		pos += 8 + sz + (sz & 1)
	if data_off < 0 or fmt_tag != 1 or data_len <= 0:
		return null
	var wav := AudioStreamWAV.new()
	if bits == 16:
		wav.format = AudioStreamWAV.FORMAT_16_BITS
	elif bits == 8:
		wav.format = AudioStreamWAV.FORMAT_8_BITS
	else:
		return null
	wav.mix_rate = rate
	wav.stereo = channels == 2
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.data = data.slice(data_off, data_off + data_len)
	return wav


## 取音效流（带缓存）；num 超出/空块返回 null。
func get_sound_stream(num: int) -> AudioStreamWAV:
	if sounds_mkf == null or num < 0 or num >= sound_count:
		return null
	if _sound_cache.has(num):
		return _sound_cache[num]
	var raw := sounds_mkf.chunk(num)
	var s: AudioStreamWAV = null
	if raw.size() > 0:
		s = stream_from_wav(raw)
		if s == null:
			_warn_once("wav_bad_%d" % num, "PALAudio: 音效 %d 不是可解析的 PCM WAVE（%d 字节）" % [num, raw.size()])
	_sound_cache[num] = s
	return s


# ---------------------------------------------------------------- 播放

## 播放音效（sdlpal audio.c: AUDIO_PlaySound / sound.c: SOUND_Play）。
## sdlpal 用 iSoundNum 做“连续同号不重播”去重；force=true 可绕过。
func play_sound(num: int, force: bool = false) -> void:
	if not ready_flag or not sound_enabled or sound_volume <= 0:
		return
	var n := absi(num)
	if not force and n == _last_sound:
		return
	_last_sound = n
	var s := get_sound_stream(n)
	if s == null:
		return
	var p := _take_player()
	p.stream = s
	p.volume_db = _volume_to_db(sound_volume)
	p.play()


func _take_player() -> AudioStreamPlayer:
	# 优先空闲播放器；没有空闲就轮转覆盖最旧的一个（sdlpal 最多 8 个并发音源）
	for i in range(_players.size()):
		var idx := (_next_player + i) % _players.size()
		if not _players[idx].playing:
			_next_player = (idx + 1) % _players.size()
			return _players[idx]
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	return p


## 播放 BGM（sdlpal AUDIO_PlayMusic：num<=0 停止；loop / 淡入秒数）。
## 本移植只播放离线预渲染的 data/bgm/NNN.wav|ogg —— 原因见文件头注释。
func play_music(num: int, loop: bool = true, fade_in: float = 0.0) -> void:
	if num <= 0:
		stop_music()
		return
	music_num = num
	if not ready_flag or not music_enabled:
		return
	var path := str(_bgm_files.get(num, ""))
	if path == "":
		_warn_once("music_%d" % num, _music_missing_message(num))
		return
	var stream := _load_bgm_stream(path)
	if stream == null:
		_warn_once("music_load_%d" % num, "PALAudio: BGM %d 预渲染文件装载失败 %s" % [num, path])
		return
	if stream is AudioStreamWAV:
		var w := stream as AudioStreamWAV
		if loop:
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			# loop_end 是“帧”数；0 会被当成无长度导致立即播完
			w.loop_end = int(w.get_length() * float(maxi(1, w.mix_rate)))
		else:
			w.loop_mode = AudioStreamWAV.LOOP_DISABLED
	_music_player.stream = null
	_music_player.stream = stream
	_music_player.volume_db = _volume_to_db(music_volume)
	if fade_in > 0.0:
		_music_player.volume_db = -60.0
		_music_player.play()
		var tw := create_tween()
		tw.tween_property(_music_player, "volume_db", _volume_to_db(music_volume), fade_in)
	else:
		_music_player.play()
	if not _music_player.playing:
		_warn_once("music_play_%d" % num, "PALAudio: BGM %d play() 未进入播放（stream=%s len=%.2fs）" % [
			num, stream.get_class(), stream.get_length(),
		])


func _load_bgm_stream(path: String) -> AudioStream:
	if path.ends_with(".wav"):
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
		return null
	if path.ends_with(".ogg"):
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
		return null
	return null


## 未实现原因（日志只打一次）
func _music_missing_message(num: int) -> String:
	var midi := data_dir + "Musics/%03d.mid" % num
	var has_midi := FileAccess.file_exists(midi)
	return ("PALAudio: BGM %d 未播放 —— Godot 无 MIDI 合成器；已定位 MIDI=%s（%s）；"
		+ "若需播放请先运行 `python tools/audio_midi_render.py %d` 生成 %s%03d.wav [unk: MUS.MKF 0x55AA 未解码]") % [
		num, midi, "存在" if has_midi else "缺失", num, BGM_DIR, num,
	]


func stop_music(fade_out: float = 0.0) -> void:
	music_num = -1
	if _music_player == null:
		return
	if fade_out > 0.0 and _music_player.playing:
		var tw := create_tween()
		tw.tween_property(_music_player, "volume_db", -60.0, fade_out)
		tw.tween_callback(Callable(_music_player, "stop"))
	else:
		_music_player.stop()


func play_voice(num: int) -> void:
	if not voice_enabled:
		_warn_once("voice_disabled", "PALAudio: play_voice(%d) 跳过 —— PAL.Administrator.ini [Audio] EnableVoice=0" % num)
		return
	# 语音资源/索引（VOICE.INI）未解析，记录为 [unk]
	_warn_once("voice_unk", "PALAudio: play_voice(%d) 未实现 —— 语音格式/索引 [unk]（任务范围外）" % num)


# ---------------------------------------------------------------- 音量/开关

func _volume_to_db(v: int) -> float:
	return linear_to_db(clampf(float(v) / float(PAL_MAX_VOLUME), 0.0001, 1.0))


func set_music_volume(v: int) -> void:
	music_volume = clampi(v, 0, PAL_MAX_VOLUME)
	if _music_player != null:
		_music_player.volume_db = _volume_to_db(music_volume)


func set_sound_volume(v: int) -> void:
	sound_volume = clampi(v, 0, PAL_MAX_VOLUME)


## sdlpal AUDIO_IncreaseVolume / DecreaseVolume：步长 3（0..100）
func increase_volume() -> void:
	set_music_volume(music_volume + 3)
	set_sound_volume(sound_volume + 3)


func decrease_volume() -> void:
	set_music_volume(music_volume - 3)
	set_sound_volume(sound_volume - 3)


func enable_music(b: bool) -> void:
	music_enabled = b
	if not b:
		stop_music()


func enable_sound(b: bool) -> void:
	sound_enabled = b


func stop_sounds() -> void:
	for p in _players:
		p.stop()


# ---------------------------------------------------------------- 工具

func _u16(b: PackedByteArray, o: int) -> int:
	return b[o] | (b[o + 1] << 8)


func _u32(b: PackedByteArray, o: int) -> int:
	return b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)


func _ascii(b: PackedByteArray, o: int, n: int) -> String:
	return b.slice(o, o + n).get_string_from_ascii()


func _warn_once(key: String, msg: String) -> void:
	if _play_warned.has(key):
		return
	_play_warned[key] = true
	print(msg)


## MUS.MKF 结构摘要（[unk]：0x55AA 头，非 RIX/MIDI；用于 --audio-test 记录证据）
func mus_summary() -> String:
	if mus_mkf == null:
		return "MUS.MKF 未打开"
	var raw := mus_mkf.chunk(1)
	var head := ""
	for i in range(mini(24, raw.size())):
		head += "%02x " % raw[i]
	return "MUS.MKF 块数=%d 块1字节=%d 块1头=%s" % [music_count, raw.size(), head.strip_edges()]


# ---------------------------------------------------------------- --audio-test

func _run_rng_test() -> void:
	# rng_player.gd 已注册 class_name RngPlayer，静态入口负责建节点、渲染 PNG、退出
	RngPlayer.run_self_test()


func _run_ending_test() -> void:
	# game/ending.gd 的静态入口：fast_mode 播放整段结局后退出
	Ending.run_self_test()


func run_self_test() -> void:
	print("[audio-test] ===== 开始：音频层自测 =====")
	var t0 := Time.get_ticks_msec()
	if not ready_flag:
		var dir := PalConfig.require_data_dir()
		if dir != "":
			init(dir)
	if not ready_flag:
		push_error("[audio-test] 数据目录/音频资源不可用")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	_test_log.append("音效块数=%d 音乐块数=%d 预渲染 BGM=%d 语音=%s" % [
		sound_count, music_count, _bgm_files.size(), voice_enabled,
	])
	_test_log.append(mus_summary())
	print("[audio-test] %s" % mus_summary())

	# ---- 音效 WAV 结构校验 + 导出 ----
	var ids: Array[int] = [1, 2, 3, 4, 5, 10, 50]
	var ok := 0
	var fail := 0
	for id in ids:
		var raw := sounds_mkf.chunk(id) if sounds_mkf != null else PackedByteArray()
		var s := get_sound_stream(id)
		if raw.size() == 0 or s == null:
			print("[audio-test] FAIL 音效 %d 无法解析（%d 字节）" % [id, raw.size()])
			_test_log.append("FAIL 音效 %d 无法解析" % id)
			fail += 1
			continue
		var frames := s.data.size() / 2 if s.format == AudioStreamWAV.FORMAT_16_BITS else s.data.size()
		var dur := float(frames) / float(maxi(1, s.mix_rate))
		var line := "音效 %d: WAV %d B, fmt=%s %dch %dHz %s, data=%d B, 时长=%.3fs" % [
			id, raw.size(),
			"PCM16" if s.format == AudioStreamWAV.FORMAT_16_BITS else "PCM8",
			2 if s.stereo else 1, s.mix_rate,
			"16bit" if s.format == AudioStreamWAV.FORMAT_16_BITS else "8bit",
			s.data.size(), dur,
		]
		print("[audio-test] %s" % line)
		_test_log.append(line)
		# 直接保存原始 chunk 作为证据（就是完整 RIFF/WAVE 文件）
		var out := SHOT_DIR + "audio_sound_%03d.wav" % id
		var fa := FileAccess.open(out, FileAccess.WRITE)
		if fa != null:
			fa.store_buffer(raw)
			fa.close()
		ok += 1

	# ---- 实际播放（非 headless 才可能出声；headless 仅验证状态） ----
	var has_device := DisplayServer.get_name() != "headless"
	print("[audio-test] 音频设备: %s（%s）" % [
		"有窗口/可出声" if has_device else "headless/dummy",
		"AudioServer bus=%d" % AudioServer.get_bus_count(),
	])
	var played := 0
	for id in ids:
		var s := get_sound_stream(id)
		if s == null:
			continue
		play_sound(id, true)
		# 等一小段（< 最短音效时长），保证能读到播放进度
		await get_tree().create_timer(0.12).timeout
		var p := _players[(_next_player + _players.size() - 1) % _players.size()]
		var pos := p.get_playback_position() if p != null else -1.0
		var line := "播放音效 %d: playing=%s position=%.3fs（流时长=%.3fs）" % [
			id, str(p.playing if p != null else false), pos,
			s.get_length(),
		]
		print("[audio-test] %s" % line)
		_test_log.append(line)
		p.stop()
		played += 1

	# ---- BGM：离线预渲染检测（未生成时记录原因，不伪造） ----
	_test_log.append("BGM：MUS.MKF [unk]（0x55AA 头，非 RIX/MIDI）；Godot 无 MIDI 合成器。")
	var midi_total := 0
	for num in [1, 2, 9, 17, 25, 26]:
		if FileAccess.file_exists(data_dir + "Musics/%03d.mid" % num):
			midi_total += 1
	_test_log.append("已定位 Musics/NNN.mid（脚本音乐号 0x0043 实测 0..87，与 Musics 编号一致）；示例存在 %d/6" % midi_total)
	if _bgm_files.is_empty():
		_test_log.append("data/bgm 无预渲染 WAV：play_music() 将只打日志（未实现原因见 pal/pal_audio.gd 头注释）。")
		_test_log.append("生成方式: python tools/audio_midi_render.py 26  → data/bgm/026.wav")
		print("[audio-test] BGM: 无预渲染文件，跳过播放（原因已记录）")
	else:
		var first = _bgm_files.keys()[0]
		play_music(first, true)
		await get_tree().create_timer(0.5).timeout
		var line2 := "播放 BGM %d: playing=%s position=%.3fs path=%s" % [
			int(first), str(_music_player.playing), _music_player.get_playback_position(),
			str(_bgm_files[first]),
		]
		print("[audio-test] %s" % line2)
		_test_log.append(line2)
		stop_music()
	# 触发一次“未实现”日志，采集证据
	play_music(26, true)
	play_voice(1)

	fail += 0 if ok == ids.size() else 1
	_test_log.append("音效 WAV 校验: %d/%d 通过；实际播放 %d 个" % [ok, ids.size(), played])
	var report := "\n".join(_test_log) + "\n"
	var rfa := FileAccess.open(SHOT_DIR + "audio_test_report.txt", FileAccess.WRITE)
	if rfa != null:
		rfa.store_string(report)
		rfa.close()
	print("[audio-test] 报告: %s" % (SHOT_DIR + "audio_test_report.txt"))
	print("[audio-test] ===== 完成，用时 %d ms，失败 %d 项 =====" % [Time.get_ticks_msec() - t0, fail])
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0 if fail == 0 else 1)
