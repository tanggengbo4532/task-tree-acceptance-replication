extends Node2D
## 场景层：地图渲染 + 队伍移动 + 事件对象 + 事件脚本驱动 + 对白 UI（完整移植版）。
##
## 移植自 sdlpal scene.c / play.c / main.c 的渲染与主循环部分：
##   1) 地图下层整幅贴图按视口裁剪 blit；2) 上层整幅混合；
##   3) 队伍 + 事件对象 + “可能遮挡精灵的上层图块”按 pos.y 排序后混合。
## 状态一律存在 autoload `PALState`（对齐 sdlpal gpGlobals），本节点只做渲染/输入/调度。
## 坐标：绝对坐标 = viewport + 队伍/对象屏幕坐标；预渲染图像坐标 = 绝对坐标 + (16,8)。

signal battle_requested(team_id: int)
signal menu_requested(kind: String)

const SCREEN_W := 320
const SCREEN_H := 200
const PARTY_OFFSET := Vector2i(160, 112)
const DIR_SOUTH := 0
const DIR_WEST := 1
const DIR_NORTH := 2
const DIR_EAST := 3
const LAYER_PLAYER := 6
const WALK_FRAMES := 4
const SHOT_DIR := "<LOCAL_PATH>"

var sss: PalData
var map_mkf: MkfFile
var gop_mkf: MkfFile
var mgo_mkf: MkfFile
var pat_mkf: MkfFile
var fbp_mkf: MkfFile
var current_map: PalMap = null
var palette: PackedColorArray
## 当前场景事件对象 id ∈ [evt_start+1, evt_end]
var evt_start: int = 0
var evt_end: int = 0

var vm: ScriptVM
var player_busy: bool = false
var sprite_cache: Dictionary = {}

var _step_frame: int = 0
var _anim_remaining: int = 0
var _move_cooldown: int = 0
var _hud_debug_n: int = 0
var _hud_was_visible: bool = false
var _game_over_shown: bool = false
var _auto_dialog_count: int = 0
var _auto_recent_msgs: Array[int] = []
var _auto_break_vm: bool = false
var _auto_sweep_id: int = 0
var _auto_sweep_wait: int = 0
var _auto_sweep_count: int = 0
var _auto_sweep_done: bool = false
var _auto_sweep_enabled: bool = true
var _auto_busy_stuck: int = 0
var _auto_watch_pos: Vector2i = Vector2i(-1, -1)
var _auto_watch: int = 0
var _auto_scene_loads: Dictionary = {}
var _auto_force_jump: bool = false
var _auto_ending_fired: bool = false
var _anim_step: Vector2i = Vector2i.ZERO
var _trail_accum: int = 0
var _redraw: bool = true
var _vm_running: bool = false
var _screen: Sprite2D
var _img: Image
var _tex: ImageTexture
var _ui: CanvasLayer
var _dialog_panel: Panel
var _dialog_label: Label
var _dialog_box: Control = null
var _status_label: Label
var _fade_rect: ColorRect
var _fade_alpha: float = 0.0
var _fade_target: float = 0.0
var _unknown_ops: Dictionary = {}

var _auto_mode: bool = false
var _auto_timer: int = 0
var _auto_shot_index: int = 0
var _auto_walk_dir: int = -1
var _scene1_shot_done: bool = false
var _scene2_shot_done: bool = false
var _visible_checked: bool = false
var _position_scripted: bool = false
var _skip_on_enter_once: bool = false
var _guard_delay: int = 0
var _auto_scene_history: Array[int] = []
var _auto_visited_scenes: Dictionary = {}
var _scene_graph: Dictionary = {}   # scene -> Array[int] 可达场景
var _auto_target: Vector2i = Vector2i(-1, -1)
var _auto_target_id: int = 0
var _auto_last_ip: int = -1
var _auto_stall: int = 0
var _auto_used: Dictionary = {}
var _auto_near_frames: int = 0
var _auto_stuck_frames: int = 0
var _auto_last_pos: Vector2i = Vector2i(-1, -1)
var _nav_fail_frames: int = 0
var _auto_frames_since_scene: int = 0
var _no_move_frames: int = 0
var _scene_door_positions: Array = []   # [{id, pos}]
var _auto_ignore_doors: int = 0
var _shoot_tag: String = ""
var _mode_node: Node = null      # 战斗/菜单等模态节点
var _rng: Node = null
var _debug_party: Array[int] = []
var _debug_party_pending: bool = false
var _debug_pos: Vector2i = Vector2i(-1, -1)
var _debug_pos_pending: bool = false
var _debug_script_entry: int = 0
var _no_collision: bool = false
var _no_battle: bool = false
var _sim_space: bool = false
var _sim_frame: int = 0
var _clip_label: Label = null
var _held_dirs: Dictionary = {}
const _DIR_KEYS: Array[int] = [KEY_LEFT, KEY_A, KEY_RIGHT, KEY_D, KEY_UP, KEY_W, KEY_DOWN, KEY_S]
var _shake_frames: int = 0
var _shake_level: int = 0
var _wait_for_key: bool = false
var _color_fade_frames: int = 0
var _color_fade_total: int = 0
var _color_fade_color: Color = Color(0, 0, 0, 1)
var _backup_img: Image = null


func _ready() -> void:
	sys_init()


# ------------------------------------------------------------------ 初始化

func sys_init() -> void:
	_auto_mode = "--auto" in OS.get_cmdline_args()
	sss = PALTables.sss
	var dir := PALTables.data_dir
	map_mkf = MkfFile.open_asset(dir, "Map.mkf")
	gop_mkf = MkfFile.open_asset(dir, "Gop.mkf")
	mgo_mkf = MkfFile.open_asset(dir, "Mgo.mkf")
	pat_mkf = MkfFile.open_asset(dir, "Pat.mkf")
	fbp_mkf = MkfFile.open_asset(dir, "Fbp.mkf")
	PALState.tables = PALTables
	PALState.data = sss
	PALState.script_runner = Callable(self, "run_script_entry_sync")
	_load_scene_graph()
	_load_auto_visited()
	PALState.need_fade_in = true
	palette = PalMap.load_palette(pat_mkf, PALState.palette, PALState.night_palette)
	_parse_debug_args()
	_setup_render_nodes()
	vm = ScriptVM.new()
	vm.setup(sss, self)
	load_scene(PALState.scene, false)


func _parse_debug_args() -> void:
	for a in OS.get_cmdline_args():
		if a.begins_with("--scene="):
			PALState.scene = int(a.substr(8))
		elif a == "--night":
			PALState.night_palette = true
		elif a.begins_with("--wave="):
			PALState.screen_wave = int(a.substr(7))
			PALState.wave_progression = 0
		elif a.begins_with("--pos="):
			var xy := a.substr(6).split(",")
			if xy.size() >= 2:
				_debug_pos = Vector2i(int(xy[0]), int(xy[1]))
		elif a == "--auto-graph":
			_auto_sweep_enabled = false
		elif a == "--sim-space":
			_sim_space = true
		elif a == "--no-collision":
			_no_collision = true
		elif a.begins_with("--script-entry="):
			_debug_script_entry = int(a.substr(15))
		elif a.begins_with("--party="):
			_debug_party = []
			for part in a.substr(8).split(","):
				_debug_party.append(int(part))
	if not _debug_party.is_empty():
		print("[debug] scene=%d party=%s night=%s" % [PALState.scene, _debug_party, PALState.night_palette])


func _apply_debug_pos() -> void:
	if _debug_pos.x < 0:
		return
	PALState.viewport = _debug_pos - PARTY_OFFSET
	_clamp_viewport()
	_anim_remaining = 0
	var abs_pos := PALState.viewport + PARTY_OFFSET
	for i in range(PALState.trail.size()):
		PALState.trail[i] = {"x": abs_pos.x, "y": abs_pos.y, "dir": PALState.party_dir}
	_redraw = true
	print("[debug] pos -> abs=", _debug_pos, " viewport=", PALState.viewport)


func _apply_debug_party() -> void:
	if _debug_party.is_empty():
		return
	PALState.max_party_member_index = _debug_party.size() - 1
	var abs_pos := PALState.viewport + PARTY_OFFSET
	for i in range(PALState.party.size()):
		var role: int = _debug_party[mini(i, _debug_party.size() - 1)]
		PALState.party[i]["role"] = role
		PALState.party[i]["x"] = PARTY_OFFSET.x
		PALState.party[i]["y"] = PARTY_OFFSET.y
		PALState.trail[i] = {"x": abs_pos.x, "y": abs_pos.y, "dir": PALState.party_dir}
		if int(PALState.roles["sprite_in_scene"][role]) == 0:
			PALState.roles["sprite_in_scene"][role] = int(PALTables.player_roles["sprite_in_scene"][role])
		PALState.party[i]["frame"] = PALState.party_dir * 3
	_redraw = true


func _show_fatal(msg: String) -> void:
	var l := Label.new()
	l.text = msg
	add_child(l)
	push_error("World: " + msg)


func _setup_render_nodes() -> void:
	_img = Image.create_empty(SCREEN_W, SCREEN_H, false, Image.FORMAT_RGBA8)
	_img.fill(Color(0, 0, 0, 1))
	_tex = ImageTexture.create_from_image(_img)
	_screen = Sprite2D.new()
	_screen.name = "Screen"
	_screen.centered = false
	_screen.texture = _tex
	_screen.scale = Vector2(2, 2)
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_screen)

	_ui = CanvasLayer.new()
	_ui.name = "UI"
	_ui.layer = 10        # 高过菜单(5)/战斗 UI，保证对白永远在最上层
	add_child(_ui)

	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_fade_rect)

	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "SimSun", "SimHei"])

	_dialog_panel = Panel.new()
	_dialog_panel.position = Vector2(12, 292)
	_dialog_panel.size = Vector2(616, 96)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.1, 0.92)
	sb.border_color = Color(0.75, 0.7, 0.55, 1.0)
	sb.set_border_width_all(2)
	_dialog_panel.add_theme_stylebox_override("panel", sb)
	_dialog_panel.visible = false
	_ui.add_child(_dialog_panel)

	_dialog_label = Label.new()
	_dialog_label.position = Vector2(14, 8)
	_dialog_label.size = Vector2(588, 80)
	_dialog_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_label.add_theme_font_size_override("font_size", 18)
	_dialog_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_dialog_label.add_theme_font_override("font", font)
	_dialog_panel.add_child(_dialog_label)

	_status_label = Label.new()
	_status_label.position = Vector2(8, 4)
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	_status_label.add_theme_font_override("font", font)
	_ui.add_child(_status_label)
	_status_label.visible = "--debug-hud" in OS.get_cmdline_args()
	_clip_label = Label.new()
	_clip_label.visible = false
	_clip_label.position = Vector2(8, 24)
	_clip_label.add_theme_font_override("font", font)
	_clip_label.add_theme_font_size_override("font_size", 14)
	_clip_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_ui.add_child(_clip_label)

	# 文本/对话框模块（port-audio-text）：存在则接管对白渲染与逐字/分页/头像
	if ResourceLoader.exists("res://game/dialog_box.gd"):
		_dialog_box = load("res://game/dialog_box.gd").new()
		_dialog_box.capture_input = false
		_dialog_box.scale = Vector2(2, 2)
		_ui.add_child(_dialog_box)


# ------------------------------------------------------------------ 场景装载

## 场景 n 的事件对象区间（0-based，[start, end)，对应 1-based id start+1..end）
func scene_event_range(n: int) -> Array[int]:
	var start_i := 0
	if n - 1 >= 0 and n - 1 < sss.scenes.size():
		start_i = int(sss.scenes[n - 1][PalData.SC_EVENT_START])
	var end_i: int = sss.events.size()
	if n >= 0 and n < sss.scenes.size():
		end_i = int(sss.scenes[n][PalData.SC_EVENT_START])
	return [start_i, end_i]


func load_scene(n: int, via_teleport: bool) -> void:
	var sc := sss.scene(n)
	if int(sc[PalData.SC_MAP]) == 0:
		push_error("World: 场景 %d 没有地图" % n)
		return
	PALState.scene = n
	PALState.entering_scene = false
	palette = PalMap.load_palette(pat_mkf, PALState.palette, PALState.night_palette)
	sprite_cache.clear()
	var dir := PALTables.data_dir
	current_map = PalMap.load_map(map_mkf, gop_mkf, int(sc[PalData.SC_MAP]), palette)
	if current_map == null:
		return
	if "--debug-hud" in OS.get_cmdline_args():
		var ps := PALState.viewport + PalMap.ORIGIN_SHIFT + Vector2i(160, 100)
		ps.x = clampi(ps.x, 0, PalMap.IMG_W - 1)
		ps.y = clampi(ps.y, 0, PalMap.IMG_H - 1)
		print("[mapdbg] scene=", PALState.scene, " map=", int(sc[PalData.SC_MAP]),
			" palette_idx=", PALState.palette, " night=", PALState.night_palette,
			" pal1=", palette[1] if palette.size() > 1 else Color.BLACK,
			" frames=", current_map.tile_frames.size(),
			" pixel@", ps, "=", current_map.bottom.get_pixel(ps.x, ps.y),
			" viewport=", PALState.viewport)
	var r := scene_event_range(n)
	evt_start = r[0]
	evt_end = r[1]
	_step_frame = 0
	_trail_accum = 0
	_anim_remaining = 0
	PALState.party_dir = DIR_SOUTH
	for i in range(PALState.party.size()):
		PALState.party[i]["x"] = PARTY_OFFSET.x
		PALState.party[i]["y"] = PARTY_OFFSET.y
		PALState.party[i]["frame"] = DIR_SOUTH * 3
	_clamp_viewport_to_party()
	if PALState.need_fade_in:
		_fade_alpha = 1.0
		_fade_target = 0.0
		_fade_rect.color = Color(0, 0, 0, 1)
		PALState.need_fade_in = false
	var start_pos := PALState.viewport + PARTY_OFFSET
	for i in range(PALState.trail.size()):
		PALState.trail[i] = {"x": start_pos.x, "y": start_pos.y, "dir": DIR_SOUTH}
	_redraw = true
	_log_auto("LOAD scene=%d map=%d events=[%d,%d) tiles=%d" % [
		n, int(sc[PalData.SC_MAP]), evt_start, evt_end, current_map.tile_frames.size()])

	var script_entry := int(sc[PalData.SC_SCRIPT_ON_TELEPORT] if via_teleport else sc[PalData.SC_SCRIPT_ON_ENTER])
	if script_entry == 0:
		script_entry = int(sc[PalData.SC_SCRIPT_ON_ENTER])
	if "--debug-hud" in OS.get_cmdline_args():
		print("[load] scene=", n, " via_teleport=", via_teleport,
			" viewport=", PALState.viewport, " party=", abs_party(),
			" map=", current_map.map_index)
	_visible_checked = false
	_guard_delay = 2
	# 清理上一场景的对话框/选择框残留
	_dialog_panel.visible = false
	if _dialog_box != null and _dialog_box.has_method("clear"):
		_dialog_box.clear()
	_auto_frames_since_scene = 0
	_no_move_frames = 0
	_auto_dialog_count = 0
	_auto_recent_msgs = []
	_auto_sweep_id = evt_start + 1
	_auto_sweep_wait = 0
	_auto_sweep_count = 0
	_auto_sweep_done = false
	if _auto_mode:
		_save_auto_visited()
		_auto_maybe_trigger_ending()
	if _auto_mode:
		_auto_visited_scenes[n] = true
		_auto_scene_loads[n] = int(_auto_scene_loads.get(n, 0)) + 1
		if int(_auto_scene_loads[n]) > 4:
			_auto_force_jump = true
			_auto_scene_loads[n] = 0
			_log_auto("CYCLE_DETECT scene=%d -> force jump" % n)
		_auto_scene_history.append(n)
		if _auto_scene_history.size() > 4:
			_auto_scene_history.pop_front()
	if PALState.scene > 2:
		_ensure_visible_area()
	_refresh_scene_doors()
	var skip_on_enter := PALState.loaded_from_save
	PALState.loaded_from_save = false
	if _debug_script_entry > 0:
		_start_script(_debug_script_entry, 0xFFFF)
	elif _skip_on_enter_once:
		_skip_on_enter_once = false
		player_busy = false
		_redraw = true
	elif script_entry != 0 and not skip_on_enter:
		_start_script(script_entry, 0xFFFF)
	elif skip_on_enter:
		# 读档：sdlpal global.c:634 读档后 fEnteringScene=FALSE，不重播入场脚本
		player_busy = false
		_redraw = true
		_ensure_visible_area()
		if not _debug_party.is_empty():
			_debug_party_pending = true
		if _debug_pos.x >= 0:
			_debug_pos_pending = true
	else:
		# 门脚本在 0x0059 之前用 0x0046 设过位置 → 保留该视口（sdlpal 行为）；否则才回到地图中心
		if not _position_scripted:
			_set_default_party_position()
		_position_scripted = false
		player_busy = false
		_apply_debug_party()
		_apply_debug_pos()
	_redraw = true


func _start_script(entry: int, evt_id: int) -> void:
	vm.start(entry, evt_id)
	player_busy = true


func _set_default_party_position() -> void:
	# 没有入场脚本时的近似出生点（原版由 0x0046 指定；记录为未知项）
	var mid := Vector2i(current_map.map_pixel_width() / 2, current_map.map_pixel_height() / 2)
	PALState.viewport = mid - PARTY_OFFSET
	_clamp_viewport()


## 若当前可视区域几乎没有地图内容（例如进入场景时相机落在黑区），把队伍移到地图内容中心
func _ensure_visible_area() -> void:
	if current_map == null:
		return
	_visible_checked = true
	var img: Image = current_map.bottom
	if img == null:
		return
	var step := 16
	var view := Rect2i(PALState.viewport.x + PalMap.ORIGIN_SHIFT.x, PALState.viewport.y + PalMap.ORIGIN_SHIFT.y, SCREEN_W, SCREEN_H)
	var total := 0
	var filled := 0
	var minx := PalMap.IMG_W
	var miny := PalMap.IMG_H
	var maxx := 0
	var maxy := 0
	for sy in range(0, PalMap.IMG_H, step):
		for sx in range(0, PalMap.IMG_W, step):
			var c := img.get_pixel(sx, sy)
			if c.r + c.g + c.b > 0.03:
				minx = mini(minx, sx)
				miny = mini(miny, sy)
				maxx = maxi(maxx, sx)
				maxy = maxi(maxy, sy)
				if view.has_point(Vector2i(sx, sy)):
					filled += 1
			if view.has_point(Vector2i(sx, sy)):
				total += 1
	if total <= 0:
		return
	var ratio := float(filled) / float(total)
	if ratio > 0.05:
		return
	if maxx <= minx or maxy <= miny:
		return
	var center := Vector2i((minx + maxx) / 2, (miny + maxy) / 2)
	PALState.viewport = center - Vector2i(SCREEN_W / 2, SCREEN_H / 2) - PalMap.ORIGIN_SHIFT
	_clamp_viewport()
	var abs_pos := PALState.viewport + PARTY_OFFSET
	for i in range(PALState.party.size()):
		PALState.party[i]["x"] = PARTY_OFFSET.x
		PALState.party[i]["y"] = PARTY_OFFSET.y
		PALState.trail[i] = {"x": abs_pos.x, "y": abs_pos.y, "dir": PALState.party_dir}
	print("[guard] scene=", PALState.scene, " map=", current_map.map_index, " view=", view,
		" bbox=", Vector4(minx, miny, maxx, maxy), " filled=", filled, "/", total,
		" ratio=", ratio, " -> moved to ", abs_pos)
	_redraw = true


func _clamp_viewport():
	var min_x: int = 0
	var min_y: int = 0
	var max_x: int = maxi(min_x, current_map.map_pixel_width() - SCREEN_W)
	var max_y: int = maxi(min_y, current_map.map_pixel_height() - SCREEN_H)
	PALState.viewport.x = clampi(PALState.viewport.x, min_x, max_x)
	PALState.viewport.y = clampi(PALState.viewport.y, min_y, max_y)


func _clamp_viewport_to_party() -> void:
	# 由 0x0046 定位后钳制视口（原版在 PAL_UpdateParty 中处理边界）
	_clamp_viewport()


func abs_party() -> Vector2i:
	var p: Dictionary = PALState.party[0]
	return PALState.viewport + Vector2i(int(p["x"]), int(p["y"]))


## 站立帧（sdlpal PAL_UpdatePartyGestures: wFrame = dir * walk_frames，0 视为 3）
func _party_idle_frame(role: int) -> int:
	var wf := int(PALState.roles["walk_frames"][role])
	if wf == 0:
		wf = 3
	return PALState.party_dir * wf


# ------------------------------------------------------------------ 每帧

func _process(_delta: float) -> void:
	if current_map == null:
		return
	if _auto_mode:
		_auto_tick()
	if "--selftest-saveload" in OS.get_cmdline_args() and _auto_timer == 120:
		_selftest_saveload()
	if _sim_space:
		_sim_frame += 1
		if _sim_frame % 20 == 0:
			var ev := InputEventKey.new()
			ev.keycode = KEY_SPACE
			ev.physical_keycode = KEY_SPACE
			ev.pressed = true
			Input.parse_input_event(ev)
			var ev2 := InputEventKey.new()
			ev2.keycode = KEY_SPACE
			ev2.physical_keycode = KEY_SPACE
			ev2.pressed = false
			Input.parse_input_event(ev2)
		if _sim_frame % 300 == 0:
			var box_state := "none"
			if _dialog_box != null:
				box_state = "act=%s typing=%s wait=%s" % [
					_dialog_box.is_active(), _dialog_box.is_typing(),
					_dialog_box.get("_waiting")]
			var vm_state := "off"
			if vm != null and vm.is_active():
				vm_state = "ip=%d dlg=%s key=%s choice=%s menu=%s bat=%s rng=%s frames=%d" % [
					vm.ip, vm.waiting_dialog, vm.waiting_key, vm.waiting_choice,
					vm.waiting_menu, vm.waiting_battle, vm.waiting_rng, vm.wait_frames]
			print("[SIM] t=%d pos=%s busy=%s vm[%s] box[%s]" % [
				_sim_frame, abs_party(), player_busy, vm_state, box_state])
	if _wait_for_key:
		pass
	if _shake_frames > 0:
		_shake_frames -= 1
		if _screen != null:
			_screen.position = Vector2(randi_range(-_shake_level, _shake_level) * 2,
				randi_range(-_shake_level, _shake_level) * 2)
	elif _screen != null and _screen.position != Vector2.ZERO:
		_screen.position = Vector2.ZERO
	if _color_fade_frames > 0:
		_color_fade_frames -= 1
		var t := 1.0 - float(_color_fade_frames) / float(maxi(1, _color_fade_total))
		_fade_rect.color = Color(_color_fade_color.r, _color_fade_color.g, _color_fade_color.b, t)
		_redraw = true
	if _fade_alpha != _fade_target:
		var speed := 0.05
		if _fade_alpha < _fade_target:
			_fade_alpha = minf(_fade_target, _fade_alpha + speed)
		else:
			_fade_alpha = maxf(_fade_target, _fade_alpha - speed)
		_fade_rect.color = Color(0, 0, 0, _fade_alpha)

	if vm != null and vm.is_active():
		_vm_running = true
		vm.tick()
		_redraw = true
	elif _vm_running:
		_vm_running = false
		player_busy = false
		_ensure_visible_area()
		_dialog_panel.visible = false
		if _debug_party_pending:
			_debug_party_pending = false
			_apply_debug_party()
		if _debug_pos_pending:
			_debug_pos_pending = false
			_apply_debug_pos()
		_redraw = true
	else:
		if not _game_over_shown and not player_busy and (vm == null or not vm.is_active()):
			if current_map != null and _party_all_dead():
				_game_over()
		_update_event_updates()
		if not player_busy:
			_unstick_if_needed()
			_update_movement()
			_check_touch_triggers()
	if _dialog_box != null and _dialog_box.has_method("is_active") and _dialog_box.is_active():
		_dialog_box.queue_redraw()
	if _redraw:
		var skip_render := false
		if _auto_mode and DisplayServer.get_name() == "headless":
			# headless 长跑：只在截图窗口期渲染（其余帧跳过，提速）
			skip_render = (_auto_timer % 600) > 2
		if not skip_render:
			_render()
		_redraw = false
		_update_status()
		if _shoot_tag != "":
			var tag := _shoot_tag
			_shoot_tag = ""
			_auto_screenshot(tag)


## F9 等调试跳场景：跳过入场脚本，并给一个可玩的默认队伍/场景精灵，从地图内容中心出发
func _debug_jump_scene(n: int) -> void:
	if vm != null and vm.is_active():
		if vm.has_method("force_finish"):
			vm.force_finish()
		else:
			vm.ended = true
	player_busy = false
	PALState.scene = n
	_skip_on_enter_once = true
	_position_scripted = false
	PALState.party[0]["role"] = 0
	PALState.party[0]["frame"] = 0
	PALState.max_party_member_index = 0
	PALState.follower_count = 0
	if PALState.roles.has("sprite_in_scene"):
		PALState.roles["sprite_in_scene"][0] = 2
	PALState.need_fade_in = false
	load_scene(n, false)
	# 场景无入场脚本时 load_scene 会回到地图中心；再用内容兜底确保可见
	_ensure_visible_area()
	_visible_checked = true
	_redraw = true


## F12：跳场景 13 并站到商店事件 (880,568) 旁，按 SPACE 触发商店
func _debug_jump_shop() -> void:
	PALState.cash = maxi(int(PALState.cash), 2000)   # 调试：给 2000 文钱便于验证商店
	_debug_jump_scene(13)
	PALState.viewport = Vector2i(880, 568) - PARTY_OFFSET
	_clamp_viewport()
	var abs_pos := PALState.viewport + PARTY_OFFSET
	for i in range(PALState.trail.size()):
		PALState.trail[i] = {"x": abs_pos.x, "y": abs_pos.y, "dir": DIR_SOUTH}
	_anim_remaining = 0
	_move_cooldown = 0
	print("[debug] F12 shop at ", abs_pos, "（按 SPACE 触发商店）")
	_redraw = true


func _selftest_saveload() -> void:
	PALState.viewport = Vector2i(1072, 271)
	var ok := PALState.save_game(9)
	print("[selftest] save(9)=", ok, " viewport=", PALState.viewport, " scene=", PALState.scene)
	PALState.viewport = Vector2i(0, 0)
	var ok2 := PALState.load_game(9)
	print("[selftest] load(9)=", ok2, " viewport=", PALState.viewport,
		" scene=", PALState.scene, " loaded_from_save=", PALState.loaded_from_save)
	load_scene(PALState.scene, false)
	print("[selftest] after load_scene: viewport=", PALState.viewport,
		" party=", abs_party(), " busy=", player_busy)


## 脱困：向最近的“格点”（16/8px 对齐）可走位置吸附（保持 sdlpal 离散位置语义）
func _unstick_if_needed() -> void:
	var p := abs_party()
	if not _is_obstacle(p.x, p.y) and p.x % 16 == 0 and p.y % 8 == 0:
		return
	_snap_to_lattice(p)


func _snap_to_lattice(from_pos: Vector2i) -> void:
	var base := Vector2i(from_pos.x - from_pos.x % 16, from_pos.y - from_pos.y % 8)
	for r in range(0, 13):
		for dyi in range(-r, r + 1):
			for dxi in range(-r, r + 1):
				if absi(dxi) + absi(dyi) > r:
					continue
				var np := Vector2i(base.x + dxi * 16, base.y + dyi * 8)
				if np.x < 0 or np.y < 0 or np.x >= current_map.map_pixel_width() or np.y >= current_map.map_pixel_height():
					continue
				if _is_obstacle(np.x, np.y):
					continue
				PALState.viewport = np - PARTY_OFFSET
				_clamp_viewport()
				_anim_remaining = 0
				_log_auto("SNAP_LATTICE -> %s" % np)
				_redraw = true
				return


## 连续受阻时强制脱困（格点吸附）
func _unstick_force() -> void:
	_snap_to_lattice(abs_party())


func _update_movement() -> void:
	if vm != null and vm.is_active():
		_held_dirs.clear()
	if _move_cooldown > 0:
		_move_cooldown -= 1
		return
	var dir := -1
	var held_left: bool = _held_dirs.has(KEY_LEFT) or _held_dirs.has(KEY_A) or Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A)
	var held_right: bool = _held_dirs.has(KEY_RIGHT) or _held_dirs.has(KEY_D) or Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D)
	var held_up: bool = _held_dirs.has(KEY_UP) or _held_dirs.has(KEY_W) or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W)
	var held_down: bool = _held_dirs.has(KEY_DOWN) or _held_dirs.has(KEY_S) or Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S)
	if _auto_mode and _auto_walk_dir >= 0:
		dir = _auto_walk_dir
	elif held_left:
		dir = DIR_WEST
	elif held_right:
		dir = DIR_EAST
	elif held_up:
		dir = DIR_NORTH
	elif held_down:
		dir = DIR_SOUTH
	if dir < 0:
		PALState.party[0]["frame"] = _party_idle_frame(int(PALState.party[0]["role"]))
		_redraw = true
		return
	PALState.party_dir = dir
	var delta := Vector2i.ZERO
	match dir:
		DIR_WEST:
			delta = Vector2i(-16, 0)
		DIR_EAST:
			delta = Vector2i(16, 0)
		DIR_NORTH:
			delta = Vector2i(0, -8)
		DIR_SOUTH:
			delta = Vector2i(0, 8)
	var target := abs_party() + delta
	var block_x: int = PARTY_OFFSET.x / 32
	var block_y: int = PARTY_OFFSET.y / 16
	var tx: int = target.x / 32
	var ty: int = target.y / 16
	if tx < block_x or tx >= current_map.map_pixel_width() / 32 - block_x - 1 or ty < block_y or ty >= current_map.map_pixel_height() / 16 - block_y - 1:
		_redraw = true
		return
	if _is_obstacle(target.x, target.y):
		_no_move_frames += 1
		if _no_move_frames > 30:
			_no_move_frames = 0
			_unstick_force()
		PALState.party[0]["frame"] = _party_idle_frame(int(PALState.party[0]["role"]))
		_redraw = true
		return
	_no_move_frames = 0
	# 离散一步（碰撞已检查），记录轨迹（每 8px 一段）
	var old_abs := abs_party()
	PALState.viewport += delta
	_clamp_viewport()
	var steps := (absi(delta.x) + absi(delta.y)) / 8
	for k in range(steps):
		var t: Vector2i = old_abs + Vector2i(
			int(delta.x * k / maxi(1, steps)), int(delta.y * k / maxi(1, steps)))
		for j in range(PALState.trail.size() - 1, 0, -1):
			PALState.trail[j] = PALState.trail[j - 1].duplicate()
		PALState.trail[0] = {"x": t.x, "y": t.y, "dir": PALState.party_dir}
	_step_frame = (_step_frame + 1) % WALK_FRAMES
	_update_lead_frame()
	_move_cooldown = 7
	_redraw = true


func _update_lead_frame() -> void:
	var role := int(PALState.party[0]["role"])
	var lead_frame: int = PALState.party_dir * 3
	if int(PALState.roles["walk_frames"][role]) == 4:
		lead_frame = PALState.party_dir * 4 + _step_frame
	elif (_step_frame & 1) != 0:
		lead_frame = PALState.party_dir * 3 + (_step_frame + 1) / 2
	PALState.party[0]["frame"] = lead_frame
	# 跟随者朝向/帧跟随领队
	for i in range(1, PALState.party.size()):
		PALState.party[i]["frame"] = lead_frame


func _is_obstacle(x: int, y: int) -> bool:
	if _no_collision:
		return false
	var tx: int = x / 32
	var ty: int = y / 16
	var h := 0
	var xr: int = x % 32
	var yr: int = y % 16
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
	if current_map.is_blocked(tx, ty, h):
		return true
	for id in range(evt_start + 1, evt_end + 1):
		var o: Array = sss.event(id)
		if int(o[PalData.EO_STATE]) >= 2:
			if absi(int(o[PalData.EO_X]) - x) + absi(int(o[PalData.EO_Y]) - y) * 2 < 16:
				return true
	return false


func _check_touch_triggers() -> void:
	var p := abs_party()
	for id in range(evt_start + 1, evt_end + 1):
		var o: Array = sss.event(id)
		var mode := int(o[PalData.EO_TRIGGER_MODE])
		var state := int(o[PalData.EO_STATE])
		var vanish := int(o[PalData.EO_VANISH])
		if vanish != 0 or state <= 0 or mode < 4:
			continue
		if absi(p.x - int(o[PalData.EO_X])) + absi(p.y - int(o[PalData.EO_Y])) * 2 < (mode - 4) * 32 + 16:
			var entry := int(o[PalData.EO_TRIGGER_SCRIPT])
			if entry != 0:
				if _auto_mode:
					_auto_used[id] = true
				_start_script(entry, id)
				_redraw = true
				return


func _unhandled_input(event: InputEvent) -> void:
	# 方向键用“事件驱动 + 轮询”双通道：真实键盘与 PostMessage 合成键都能工作
	if event is InputEventKey:
		var ev := event as InputEventKey
		if not ev.echo and _DIR_KEYS.has(ev.keycode):
			if ev.pressed:
				_held_dirs[ev.keycode] = true
			else:
				_held_dirs.erase(ev.keycode)
		if not ev.pressed:
			return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: int = (event as InputEventKey).keycode
	if _wait_for_key:
		_wait_for_key = false
		if vm != null and vm.is_active() and vm.has_method("resume_key"):
			vm.resume_key()
		get_viewport().set_input_as_handled()
		return
	if player_busy and _mode_node != null:
		return
	if k == KEY_F6:
		_no_collision = not _no_collision
		_log_auto("NO_COLLISION=%s" % _no_collision)
		if _clip_label != null:
			_clip_label.visible = _no_collision or _no_battle
			_clip_label.text = "穿墙模式：%s（F6）  跳过战斗：%s（F7）" % [
				"开" if _no_collision else "关", "开" if _no_battle else "关"]
		get_viewport().set_input_as_handled()
		return
	if k == KEY_F8:
		_force_door_trigger()
		get_viewport().set_input_as_handled()
		return
	if k == KEY_F10:
		_log_auto("F10: 调试战斗 team=2")
		request_battle(2, false, false)
		get_viewport().set_input_as_handled()
		return
	if k == KEY_F12:
		_log_auto("F12: 传送到商店（场景 13 商店事件旁）")
		call_deferred("_debug_jump_shop")
		get_viewport().set_input_as_handled()
		return
	if k == KEY_F11:
		_log_auto("F11: 耐久测试战斗 team=7 (5 敌)")
		request_battle(7, false, false)
		get_viewport().set_input_as_handled()
		return
	if k == KEY_F9:
		_log_auto("F9: 传送到场景 5（村道）")
		call_deferred("_debug_jump_scene", 5)
		get_viewport().set_input_as_handled()
		return
	if k == KEY_F7:
		_no_battle = not _no_battle
		_log_auto("NO_BATTLE=%s" % _no_battle)
		if _clip_label != null:
			_clip_label.visible = _no_collision or _no_battle
			_clip_label.text = "穿墙模式：%s（F6）  跳过战斗：%s（F7）" % [
				"开" if _no_collision else "关", "开" if _no_battle else "关"]
		get_viewport().set_input_as_handled()
		return
	if k == KEY_SPACE or k == KEY_ENTER or k == KEY_KP_ENTER:
		if _dialog_box != null and _dialog_box.has_method("is_active") and _dialog_box.is_active():
			# 打字中→跳字；否则翻页/关闭；本页结束→推进脚本
			if _dialog_box.has_method("is_typing") and _dialog_box.is_typing():
				_dialog_box.finish_typing()
			elif not _dialog_box.advance():
				if vm != null and vm.is_active() and vm.waiting_dialog:
					vm.advance_dialog()
			_redraw = true
		elif vm != null and vm.is_active() and vm.waiting_dialog:
			vm.advance_dialog()
			_redraw = true
		elif not player_busy:
			_do_search()
		get_viewport().set_input_as_handled()
	elif k == KEY_ESCAPE:
		if not player_busy:
			open_menu("main")
		get_viewport().set_input_as_handled()


func _do_search() -> void:
	# 移植 play.c: PAL_GetSearchTriggerRange + PAL_Search（13 检查点 × 场景事件对象）
	var p := abs_party()
	var x := p.x
	var y := p.y
	var x_offset := 16 if (PALState.party_dir == DIR_NORTH or PALState.party_dir == DIR_EAST) else -16
	var y_offset := 8 if (PALState.party_dir == DIR_EAST or PALState.party_dir == DIR_SOUTH) else -8
	var pos: Array = [Vector2i(x, y)]
	for i in range(4):
		pos.append(Vector2i(x + x_offset, y + y_offset))
		pos.append(Vector2i(x, y + y_offset * 2))
		pos.append(Vector2i(x + 2 * x_offset, y))
		x += x_offset
		y += y_offset
	for i in range(13):
		var dh := 1 if posmod(pos[i].x, 32) != 0 else 0
		var dx: int = pos[i].x / 32
		var dy: int = pos[i].y / 16
		for id in range(evt_start + 1, evt_end + 1):
			var o: Array = sss.event(id)
			var mode := int(o[PalData.EO_TRIGGER_MODE])
			if int(o[PalData.EO_STATE]) <= 0 or mode >= 4 or mode * 6 - 4 <= i:
				continue
			var ex: int = int(o[PalData.EO_X]) / 32
			var ey: int = int(o[PalData.EO_Y]) / 16
			var eh := 1 if posmod(int(o[PalData.EO_X]), 32) != 0 else 0
			if dx != ex or dy != ey or dh != eh:
				continue
			# 面向队伍并摆出站立姿势
			o[PalData.EO_CUR_FRAME] = 0
			o[PalData.EO_DIRECTION] = (PALState.party_dir + 2) % 4
			for l in range(PALState.max_party_member_index + 1):
				PALState.party[l]["frame"] = PALState.party_dir * 3
			_redraw = true
			var entry := int(o[PalData.EO_TRIGGER_SCRIPT])
			if entry != 0:
				if _auto_mode:
					_auto_used[id] = true
				_start_script(entry, id)
			return


## 每帧事件对象状态更新（play.c: 消失计时 / 离屏恢复 / auto script）
func _update_event_updates() -> void:
	for id in range(evt_start + 1, evt_end + 1):
		var o: Array = sss.event(id)
		var vanish := int(o[PalData.EO_VANISH])
		if vanish != 0:
			o[PalData.EO_VANISH] = vanish + (1 if vanish < 0 else -1)
			continue
		var state := int(o[PalData.EO_STATE])
		if state < 0:
			var in_view := int(o[PalData.EO_X]) >= PALState.viewport.x - 320 \
				and int(o[PalData.EO_X]) <= PALState.viewport.x + SCREEN_W + 320 \
				and int(o[PalData.EO_Y]) >= PALState.viewport.y - 320 \
				and int(o[PalData.EO_Y]) <= PALState.viewport.y + SCREEN_H + 320
			if in_view:
				o[PalData.EO_STATE] = absi(state)
				o[PalData.EO_CUR_FRAME] = 0
				_redraw = true
			continue
		if state > 0:
			var auto_entry := int(o[PalData.EO_AUTO_SCRIPT])
			if auto_entry != 0 and vm != null and vm.has_method("run_auto"):
				var next_entry: int = vm.run_auto(auto_entry, id)
				if next_entry != auto_entry:
					o[PalData.EO_AUTO_SCRIPT] = next_entry
					_redraw = true


# ------------------------------------------------------------------ 渲染

func _render() -> void:
	if current_map == null:
		return
	_img.fill(Color(0, 0, 0, 1))
	var src := Rect2i(PALState.viewport.x + PalMap.ORIGIN_SHIFT.x, PALState.viewport.y + PalMap.ORIGIN_SHIFT.y, SCREEN_W, SCREEN_H)
	var safe := Rect2i(src)
	if safe.position.x < 0:
		safe.position.x = 0
	if safe.position.y < 0:
		safe.position.y = 0
	if safe.end.x > PalMap.IMG_W:
		safe.size.x = PalMap.IMG_W - safe.position.x
	if safe.end.y > PalMap.IMG_H:
		safe.size.y = PalMap.IMG_H - safe.position.y
	if safe.size.x <= 0 or safe.size.y <= 0:
		return
	var dst := safe.position - src.position
	_img.blit_rect(current_map.bottom, safe, dst)
	_img.blend_rect(current_map.layer_top, safe, dst)

	var drawables: Array = []
	_collect_party(drawables)
	_collect_events(drawables)
	drawables.sort_custom(func(a, b): return a["sy"] < b["sy"])
	for d in drawables:
		var img: Image = d["img"]
		var px: int = d["x"]
		var py: int = d["y"]
		var w: int = img.get_width()
		var h: int = img.get_height()
		var sx0 := maxi(0, -px)
		var sy0 := maxi(0, -py)
		if sx0 >= w or sy0 >= h:
			continue
		var dw := mini(w - sx0, SCREEN_W - px - sx0)
		var dh := mini(h - sy0, SCREEN_H - py - sy0)
		if dw <= 0 or dh <= 0:
			continue
		_img.blend_rect(img, Rect2i(sx0, sy0, dw, dh), Vector2i(px + sx0, py + sy0))
	_apply_wave()
	if _tex != null:
		_tex.update(_img)


## 移植 scene.c PAL_ApplyWave：屏幕波动（脚本 0x0057 设置 level/progression）
func _apply_wave() -> void:
	if PALState.screen_wave == 0 and PALState.wave_progression == 0:
		return
	PALState.screen_wave += PALState.wave_progression
	if PALState.screen_wave == 0 or PALState.screen_wave >= 256:
		PALState.screen_wave = 0
		PALState.wave_progression = 0
		return
	var wave: Array[int] = []
	wave.resize(32)
	var a := 0
	var b := 68
	for i in range(16):
		b -= 8
		a += b
		wave[i] = a * PALState.screen_wave / 256
		wave[i + 16] = 320 - wave[i]
	var idx := 0
	var data := _img.get_data()
	var stride := SCREEN_W * 4
	for y in range(SCREEN_H):
		var shift: int = wave[idx]
		idx = (idx + 1) % 32
		if shift <= 0 or shift >= SCREEN_W:
			continue
		var base := y * stride
		var merged := data.slice(base + shift * 4, base + stride) + data.slice(base, base + shift * 4)
		_img.set_data(y, 0, SCREEN_W, 1, merged)


func _collect_party(out: Array) -> void:
	var party_count: int = PALState.max_party_member_index + 1 + PALState.follower_count
	for i in range(mini(party_count, PALState.party.size())):
		var role := int(PALState.party[i]["role"])
		var sprite_num := int(PALState.roles["sprite_in_scene"][role])
		var frames := _sprite_frames(sprite_num)
		if frames.is_empty():
			continue
		var screen_pos := Vector2i(int(PALState.party[i]["x"]), int(PALState.party[i]["y"]))
		var fi := int(PALState.party[i]["frame"])
		if i > 0:
			# 跟随者：位置/朝向来自 trail（sdlpal PAL_UpdatePartyGestures）
			var t: Dictionary = PALState.trail[i]
			if int(t.get("x", 0)) != 0 or int(t.get("y", 0)) != 0:
				screen_pos = Vector2i(int(t["x"]) - PALState.viewport.x, int(t["y"]) - PALState.viewport.y)
				fi = int(t["dir"]) * 3
		if fi < 0 or fi >= frames.size():
			fi = clampi(fi, 0, frames.size() - 1)
		var img: Image = frames[fi]
		var w := img.get_width()
		var h := img.get_height()
		var layer: int = PALState.layer + 6
		var pos_x: int = screen_pos.x - w / 2
		var pos_y: int = screen_pos.y + PALState.layer + 10
		out.append({"img": img, "x": pos_x, "y": pos_y - h - layer, "sy": pos_y})
		_collect_cover_tiles(out, PALState.viewport.x + screen_pos.x,
			PALState.viewport.y + screen_pos.y, layer, w, h)


func _collect_events(out: Array) -> void:
	for id in range(evt_start + 1, evt_end + 1):
		var o: Array = sss.event(id)
		var state := int(o[PalData.EO_STATE])
		var sprite_num := int(o[PalData.EO_SPRITE])
		var nframes := int(o[PalData.EO_FRAMES])
		if state <= 0 or sprite_num <= 0 or nframes <= 0:
			continue
		var vanish := int(o[PalData.EO_VANISH])
		if vanish > 0:
			continue
		var frames := _sprite_frames(sprite_num)
		if frames.is_empty():
			continue
		var frame_idx: int = int(o[PalData.EO_DIRECTION]) * nframes + int(o[PalData.EO_CUR_FRAME])
		if frame_idx < 0 or frame_idx >= frames.size():
			frame_idx = clampi(frame_idx, 0, frames.size() - 1)
		var img: Image = frames[frame_idx]
		var w := img.get_width()
		var h := img.get_height()
		var layer := int(o[PalData.EO_LAYER]) * 8 + 2
		var pos_x: int = int(o[PalData.EO_X]) - PALState.viewport.x - w / 2
		var pos_y: int = int(o[PalData.EO_Y]) - PALState.viewport.y + int(o[PalData.EO_LAYER]) * 8 + 9
		if pos_x >= SCREEN_W or pos_x < -w or pos_y - h >= SCREEN_H or pos_y < -h:
			continue
		out.append({"img": img, "x": pos_x, "y": pos_y - h - layer, "sy": pos_y})
		_collect_cover_tiles(out, int(o[PalData.EO_X]), int(o[PalData.EO_Y]), layer, w, h)


## 移植 scene.c PAL_CalcCoverTiles
func _collect_cover_tiles(out: Array, abs_x: int, abs_y: int, i_layer: int, width: int, height: int) -> void:
	var sx: int = abs_x - i_layer / 2
	var sy: int = abs_y - i_layer
	if sx < PALState.viewport.x - 64 or sx > PALState.viewport.x + SCREEN_W + 64:
		return
	if sy < PALState.viewport.y - 64 or sy > PALState.viewport.y + SCREEN_H + 64:
		return
	var sh := 1 if posmod(sx, 32) != 0 else 0
	var x_min: int = (sx - width / 2) / 32
	var x_max: int = (sx + width / 2) / 32
	for ty in range((sy - height - 15) / 16, sy / 16 + 1):
		for tx in range(x_min, x_max + 1):
			var start_i := 0 if tx == x_min else 3
			for i in range(start_i, 5):
				var dx := 0
				var dy := 0
				var dh := 0
				match i:
					0:
						dx = tx
						dy = ty
						dh = sh
					1:
						dx = tx - 1
						dy = ty
						dh = sh
					2:
						dx = tx if sh != 0 else tx - 1
						dy = ty + 1 if sh != 0 else ty
						dh = 1 - sh
					3:
						dx = tx + 1
						dy = ty
						dh = sh
					4:
						dx = tx + 1 if sh != 0 else tx
						dy = ty + 1 if sh != 0 else ty
						dh = 1 - sh
				for l in range(2):
					var img := current_map.tile_image(dx, dy, dh, l)
					if img == null:
						continue
					var tile_h: int = current_map.get_tile_height(dx, dy, dh)
					if tile_h > 127:
						tile_h -= 256
					if tile_h <= 0:
						continue
					if (dy + tile_h) * 16 + dh * 8 < sy:
						continue
					var px: int = dx * 32 + dh * 16 - 16 - PALState.viewport.x
					var py: int = dy * 16 + dh * 8 + 7 + l + tile_h * 8 - PALState.viewport.y
					out.append({
						"img": img,
						"x": px,
						"y": py - img.get_height() - (tile_h * 8 + l),
						"sy": py,
					})


func _sprite_frames(sprite_num: int) -> Array[Image]:
	if sprite_cache.has(sprite_num):
		return sprite_cache[sprite_num]
	var out: Array[Image] = []
	if mgo_mkf == null or sprite_num <= 0 or sprite_num >= mgo_mkf.chunk_count:
		sprite_cache[sprite_num] = out
		return out
	var raw := mgo_mkf.decompressed(sprite_num)
	if raw.size() > 4:
		out = PalSprite.decode_sprite(raw, palette)
	sprite_cache[sprite_num] = out
	return out


func _update_status() -> void:
	if _status_label == null or current_map == null:
		return
	if not _status_label.visible:
		return
	var p := abs_party()
	if "--debug-hud" in OS.get_cmdline_args():
		_hud_debug_n += 1
		if _hud_debug_n % 60 == 0:
			print("[hud] abs=", p, " viewport=", PALState.viewport,
				" party0=", PALState.party[0]["x"], ",", PALState.party[0]["y"])
	_status_label.text = "场景 %d（地图 %d）  坐标 (%d,%d)  HP %d/%d%s" % [
		PALState.scene, current_map.map_index, p.x, p.y,
		int(PALState.roles["hp"][int(PALState.party[0]["role"])]),
		int(PALState.roles["max_hp"][int(PALState.party[0]["role"])]),
		"  [脚本]" if (vm != null and vm.is_active()) else "",
	]


# ------------------------------------------------------------------ 脚本回调（ScriptVM → World）

func script_dialog(text: String, msg_id: int) -> void:
	var clean := text
	if PALText != null and PALText.ready_flag:
		clean = PALText.parse_codes(text).get("text", text)
	clean = PalData.strip_control_codes(clean)
	if clean.strip_edges() == "":
		clean = "……"
	if _dialog_box != null:
		# DialogBox 内部解析控制码（$延时/~换页/'-"@颜色/图标），这里传原文
		_dialog_panel.visible = false
		_dialog_box.push_line(text)
		_dialog_box.queue_redraw()
	else:
		_dialog_label.text = clean
		_dialog_panel.visible = true
	player_busy = true
	_log_auto("DIALOG msg=%d %s" % [msg_id, clean])
	if _auto_mode and msg_id > 0:
		_auto_dialog_count += 1
		_auto_recent_msgs.append(msg_id)
		if _auto_recent_msgs.size() > 12:
			_auto_recent_msgs.pop_front()
		var same := 0
		for m in _auto_recent_msgs:
			if m == msg_id:
				same += 1
		if same >= 6 or _auto_dialog_count > 600:
			_auto_break_vm = true
			_auto_dialog_count = 0
	_redraw = true
	if _auto_mode and PALState.scene == 1 and not _scene1_shot_done:
		_scene1_shot_done = true
		_shoot_tag = "scene1_dialog"
	if _auto_mode and PALState.scene == 2 and not _scene2_shot_done:
		_scene2_shot_done = true
		_shoot_tag = "scene2_dialog"


func script_dialog_closed() -> void:
	_redraw = true


func script_dialog_clear() -> void:
	_dialog_panel.visible = false
	if _dialog_box != null and _dialog_box.has_method("clear"):
		_dialog_box.clear()
	_redraw = true


## sdlpal script.c: 0x003B=kDialogCenter, 0x003C=kDialogUpper, 0x003D=kDialogLower,
## 0x003E=kDialogCenterWindow。ScriptVM 传 op-0x003B（0..3），此处映射到 text.h Style 枚举
## （UPPER=0, CENTER=1, LOWER=2, CENTER_WINDOW=3）。
const _STYLE_MAP: Array[int] = [1, 0, 2, 3]


func script_dialog_style(style: int) -> void:
	if _dialog_box != null and _dialog_box.has_method("set_style"):
		var mapped: int = _STYLE_MAP[clampi(style, 0, 3)]
		_dialog_box.set_style(mapped)
	_redraw = true


func script_refresh(_gestures: bool) -> void:
	_redraw = true


## 0x003C/0x003D 的 operand0=iNumCharFace、operand1=bFontColor（sdlpal PAL_StartDialog 参数）
func script_dialog_face(face: int, base_color: int) -> void:
	if _dialog_box != null:
		if face > 0 and _dialog_box.has_method("set_face"):
			_dialog_box.set_face(face)
		if _dialog_box.has_method("set_base_color"):
			_dialog_box.set_base_color(base_color)
	_redraw = true


func script_change_scene(n: int) -> void:
	_dialog_panel.visible = false
	var extra := ""
	if vm != null:
		extra = " vm_ip=%d evt=%d" % [vm.ip, vm.last_event_object_id]
	if "--debug-hud" in OS.get_cmdline_args():
		extra += " auto_target=%d pos=%s" % [_auto_target_id, abs_party()]
	_log_auto("CHANGE_SCENE -> %d%s" % [n, extra])
	call_deferred("load_scene", n, false)


func script_party_position(gx: int, gy: int, half: int) -> void:
	_position_scripted = true
	var ax := gx * 32 + half * 16
	var ay := gy * 16 + half * 8
	PALState.viewport = Vector2i(ax, ay) - PARTY_OFFSET
	_clamp_viewport()
	var abs_pos := PALState.viewport + PARTY_OFFSET
	for i in range(PALState.party.size()):
		PALState.party[i]["x"] = PARTY_OFFSET.x
		PALState.party[i]["y"] = PARTY_OFFSET.y
		PALState.trail[i] = {"x": abs_pos.x, "y": abs_pos.y, "dir": PALState.party_dir}
	_redraw = true


func script_party_gesture(direction: int, frame: int, index: int) -> void:
	if direction >= 0 and direction <= 3:
		if index >= 0 and index < PALState.party.size():
			PALState.party[index]["frame"] = direction * 3 + frame
		else:
			PALState.party[0]["frame"] = direction * 3 + frame
		PALState.party_dir = direction
	_redraw = true


func script_player_sprite(role: int, sprite_num: int, _refresh: int) -> void:
	if role >= 0 and role < 6:
		PALState.roles["sprite_in_scene"][role] = sprite_num
	_redraw = true


func script_set_party(r0: int, r1: int, r2: int) -> void:
	var roles: Array = []
	for v in [r0, r1, r2]:
		if v != 0:
			roles.append(v - 1)
	if roles.is_empty():
		roles.append(0)
	PALState.max_party_member_index = roles.size() - 1
	for i in range(PALState.party.size()):
		if i < roles.size():
			PALState.party[i]["role"] = roles[i]
		else:
			PALState.party[i]["role"] = roles[roles.size() - 1]
	_redraw = true


func script_event_state(which: int, state: int, last_id: int) -> void:
	var id := last_id if which == 0 else which
	if id >= 1 and id <= sss.events.size():
		sss.event(id)[PalData.EO_STATE] = state
	_redraw = true


func script_music(music_num: int, mode: int) -> void:
	PALState.music = music_num
	if PALAudio != null and PALAudio.ready_flag:
		PALAudio.play_music(music_num, mode != 2)
	_log_auto("MUSIC %d mode=%d" % [music_num, mode])


func script_sound(sound_num: int) -> void:
	if PALAudio != null and PALAudio.ready_flag:
		PALAudio.play_sound(sound_num)
	_log_auto("SOUND %d" % sound_num)


func script_fade_out(_speed: int) -> void:
	_fade_target = 1.0


func script_fade_in(_speed: int) -> void:
	_fade_target = 0.0


func script_use_day_palette() -> void:
	_apply_palette(PALState.palette, false)


func script_use_night_palette() -> void:
	_apply_palette(PALState.palette, true)


func _apply_palette(pal_num: int, night: bool) -> void:
	PALState.palette = pal_num
	PALState.night_palette = night
	palette = PalMap.load_palette(pat_mkf, pal_num, night)
	sprite_cache.clear()
	if current_map != null:
		current_map = PalMap.load_map(map_mkf, gop_mkf, current_map.map_index, palette)
	_redraw = true


func script_screen_wave(level: int, progression: int) -> void:
	PALState.screen_wave = level
	PALState.wave_progression = progression


func script_force_redraw() -> void:
	_redraw = true


func script_confirm_menu() -> void:
	# 简化：是/否菜单自动选“是”（菜单 UI 由 port-menus 提供后替换）
	_log_auto("CONFIRM_MENU -> yes")


func script_note_unknown(op: int, at: int) -> void:
	_unknown_ops[op] = int(_unknown_ops.get(op, 0)) + 1
	if _unknown_ops[op] == 1:
		_log_auto("UNKNOWN_OP 0x%04x at entry %d" % [op, at])


func script_change_battlefield(battlefield: int) -> void:
	PALState.battle_field = battlefield


func script_end_game() -> void:
	if ResourceLoader.exists("res://game/ending.gd"):
		var e = load("res://game/ending.gd").new()
		add_child(e)
	_log_auto("ENDING")


# ------------------------------------------------------------------ 特效 / 画面钩子（ScriptVM 调用）

## 0x0035 屏幕震动
func script_shake_screen(times: int, level: int) -> void:
	_shake_frames = times if times > 0 else 4
	_shake_level = level if level > 0 else 4
	_redraw = true


func shake_screen(times: int) -> void:
	script_shake_screen(times, _shake_level if _shake_level > 0 else 4)


func set_screen_wave(level: int, progression: int) -> void:
	script_screen_wave(level, progression)


## 0x0076（WIN95）：清屏（sdlpal WIN95 分支只 FillRect 黑 + UpdateScreen）
func script_clear_screen() -> void:
	_img.fill(Color(0, 0, 0, 1))
	if _tex != null:
		_tex.update(_img)
	_redraw = true


func request_picture(num: int, frames: int) -> void:
	# sdlpal WIN95 分支不显示 FBP，只清屏；这里保留日志便于排查
	_log_auto("PICTURE %d frames=%d (WIN95=清屏)" % [num, frames])
	script_clear_screen()


## 0x008C 颜色渐变（PAL_ColorFade：把画面渐变为指定调色板颜色）
func script_color_fade(color_index: int, speed: int, _unknown: int) -> void:
	var pal := PalMap.load_palette(pat_mkf, PALState.palette, PALState.night_palette)
	var c: Color = pal[color_index % 256] if color_index >= 0 else Color(0, 0, 0, 1)
	_color_fade_color = Color(c.r, c.g, c.b, 1.0)
	_color_fade_total = maxi(1, speed if speed > 0 else 1)
	_color_fade_frames = _color_fade_total
	_fade_target = 0.0
	_redraw = true


## 0x0073 场景淡入淡出
func script_scene_fade(_palette: int, night: bool, speed: int) -> void:
	if night != PALState.night_palette:
		_apply_palette(PALState.palette, night)
	var frames := speed if speed > 0 else 1
	_fade_alpha = 1.0
	_fade_target = 0.0
	_color_fade_frames = 0
	_redraw = true


## 0x00A4 / 0x00A5（WIN95 下 sdlpal 不执行，保留空实现）
func request_scroll_picture(num: int, _a1: int, _a2: int) -> void:
	_log_auto("SCROLL_PICTURE %d (WIN95 no-op)" % num)


func request_picture_sprite(num: int, _a1: int, _a2: int) -> void:
	_log_auto("PICTURE_SPRITE %d (WIN95 no-op)" % num)


## 0x00A6 备份当前画面
func script_backup_screen() -> void:
	_backup_img = _img.duplicate()


## 0x004D 等待任意键（VM → waiting_key）
func request_wait_key() -> void:
	_wait_for_key = true


## 0x004E 读取当前存档后重载
func request_load_game() -> void:
	var slot := PALState.current_save_slot
	if slot > 0:
		PALState.load_game(slot)
	call_deferred("load_scene", PALState.scene, false)
	_redraw = true


## 0x0099 改当前场景地图后立即重载
func reload_map() -> void:
	var sc := sss.scene(PALState.scene)
	var map_no := int(sc[PalData.SC_MAP])
	if map_no <= 0:
		return
	palette = PalMap.load_palette(pat_mkf, PALState.palette, PALState.night_palette)
	current_map = PalMap.load_map(map_mkf, gop_mkf, map_no, palette)
	if "--debug-hud" in OS.get_cmdline_args() and current_map != null:
		var ps := PALState.viewport + PalMap.ORIGIN_SHIFT + Vector2i(160, 100)
		ps.x = clampi(ps.x, 0, PalMap.IMG_W - 1)
		ps.y = clampi(ps.y, 0, PalMap.IMG_H - 1)
		var c0: Color = current_map.bottom.get_pixel(ps.x, ps.y)
		print("[mapdbg] scene=", PALState.scene, " map=", map_no,
			" palette_idx=", PALState.palette, " night=", PALState.night_palette,
			" pal1=", palette[1] if palette.size() > 1 else Color.BLACK,
			" frames=", current_map.tile_frames.size(),
			" pixel@", ps, "=", c0,
			" viewport=", PALState.viewport)
	sprite_cache.clear()
	_redraw = true


## 0x000A 是/否：异步（ScriptVM → waiting_choice → vm.resume_choice）
## VM 优先找 confirm_menu()（同步）；这里只提供 request_confirm()，强制走异步路径。
func request_confirm() -> void:
	if _auto_mode:
		_log_auto("CONFIRM_MENU -> yes (auto)")
		await get_tree().create_timer(0.3).timeout
		_finish_confirm(true)
		return
	if ResourceLoader.exists("res://game/menu.gd") and load("res://game/menu.gd") != null:
		var menu_script = load("res://game/menu.gd")
		if menu_script == null:
			_finish_confirm(true)
			return
		var m = menu_script.new()
		_mode_node = m
		add_child(m)
		player_busy = true
		m.choice_made.connect(Callable(self, "_on_confirm_choice"), CONNECT_ONE_SHOT)
		m.closed.connect(Callable(self, "_on_confirm_closed"), CONNECT_ONE_SHOT)
		m.setup_confirm("")
		return
	if _dialog_box != null and _dialog_box.has_method("show_choice"):
		var yes: bool = await _dialog_box.show_choice()
		_finish_confirm(yes)
		return
	_finish_confirm(true)


func _on_confirm_choice(yes: bool) -> void:
	_finish_confirm(yes)


func _on_confirm_closed() -> void:
	if _mode_node != null:
		_mode_node.queue_free()
		_mode_node = null
	player_busy = false
	_redraw = true


func _finish_confirm(yes: bool) -> void:
	_log_auto("CONFIRM_MENU -> %s" % ("yes" if yes else "no"))
	if vm != null and vm.is_active() and vm.has_method("resume_choice"):
		vm.resume_choice(yes)
	elif vm != null and vm.is_active() and vm.waiting_dialog:
		vm.advance_dialog()
	_redraw = true


func request_ending() -> void:
	script_end_game()


func request_quit_game() -> void:
	get_tree().quit()


## 0x0037 RNG 完整播放：播放完成后恢复 VM
func request_rng_full(rng_id: int, start_frame: int, frames: int, speed: int) -> void:
	PALState.current_rng = rng_id
	if not ResourceLoader.exists("res://pal/rng_player.gd"):
		_log_auto("RNG %d 播放器未就绪（跳过）" % rng_id)
		call_deferred("_rng_done")
		return
	var r = load("res://pal/rng_player.gd").new()
	_rng = r
	add_child(r)
	if r.has_signal("finished"):
		r.finished.connect(Callable(self, "_rng_done"), CONNECT_ONE_SHOT)
	if r.has_method("play_full"):
		r.play_full(rng_id, start_frame, frames, speed)
	else:
		r.play(rng_id)
	# 兜底：若播放器没有 finished 信号，最多等 frames 帧后恢复
	if not r.has_signal("finished"):
		await get_tree().create_timer(0.5).timeout
		_rng_done()


func _rng_done() -> void:
	if _rng != null:
		_rng.queue_free()
		_rng = null
	if vm != null and vm.is_active() and vm.has_method("resume_rng"):
		vm.resume_rng()
	_redraw = true


# ------------------------------------------------------------------ 战斗

func request_battle(team_id: int, flee_disabled: bool = false, force_win: bool = false) -> void:
	if _auto_mode:
		force_win = true    # 自动长跑验收：剧情战斗强制胜利，避免 GameOver 重启循环
	if _no_battle:
		_log_auto("BATTLE team=%d 跳过（F7 测试）" % team_id)
		call_deferred("on_battle_finished", "win")
		return
	battle_requested.emit(team_id)
	_log_auto("BATTLE team=%d flee_disabled=%s force_win=%s" % [team_id, flee_disabled, force_win])
	if not ResourceLoader.exists("res://game/battle.gd"):
		push_warning("World: 战斗模块 game/battle.gd 尚未就绪，跳过战斗（按胜利继续）")
		call_deferred("on_battle_finished", "win")
		return
	var battle_script = load("res://game/battle.gd")
	if battle_script == null:
		push_warning("World: battle.gd 编译失败，跳过战斗（按胜利继续）")
		call_deferred("on_battle_finished", "win")
		return
	var b = battle_script.new()
	b.setup(team_id, flee_disabled, force_win)
	b.finished.connect(Callable(self, "on_battle_finished"))
	_mode_node = b
	add_child(b)
	player_busy = true
	if _auto_mode and b.has_method("set_auto_battle"):
		b.set_auto_battle()
	if vm != null and vm.has_method("set_battle_proxy"):
		vm.set_battle_proxy(b)


func on_battle_finished(result: String) -> void:
	if _mode_node != null:
		_mode_node.queue_free()
		_mode_node = null
	player_busy = false
	_dialog_panel.visible = false
	_redraw = true
	_log_auto("BATTLE_RESULT %s" % result)
	if vm != null and vm.is_active() and vm.has_method("resume_battle"):
		vm.resume_battle(result)
	if result == "lose" and not (vm != null and vm.is_active()):
		_game_over()


# ------------------------------------------------------------------ 菜单

func _party_all_dead() -> bool:
	for i in range(PALState.max_party_member_index + 1):
		var role := int(PALState.party[i]["role"])
		if int(PALState.roles["hp"][role]) > 0:
			return false
	return true


## 战败：显示提示 → 返回标题画面（PAL98 行为）
func _game_over() -> void:
	if _game_over_shown:
		return
	_game_over_shown = true
	player_busy = true
	_held_dirs.clear()
	print("[world] GAME_OVER")
	if _dialog_box != null:
		_dialog_box.set_style(3)
		_dialog_box.push_line("胜败乃兵家常事，大侠请重新来过……")
	# 按键继续（最多 8 秒），避免玩家来不及看清
	var waited := 0.0
	while waited < 8.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if Input.is_anything_pressed():
			break
	_game_over_shown = false
	get_tree().reload_current_scene()


func open_menu(kind: String) -> void:
	menu_requested.emit(kind)
	if _status_label != null and _status_label.visible:
		_status_label.visible = false
		_hud_was_visible = true
	if player_busy:
		return
	if not ResourceLoader.exists("res://game/menu.gd"):
		push_warning("World: 菜单模块 game/menu.gd 尚未就绪（kind=%s）" % kind)
		return
	var menu_script = load("res://game/menu.gd")
	if menu_script == null:
		push_warning("World: menu.gd 编译失败（kind=%s）" % kind)
		call_deferred("on_menu_closed")
		return
	var m = menu_script.new()
	m.setup(kind)
	m.closed.connect(Callable(self, "on_menu_closed"))
	_mode_node = m
	add_child(m)
	player_busy = true


func on_menu_closed() -> void:
	if _hud_was_visible and _status_label != null:
		_status_label.visible = "--debug-hud" in OS.get_cmdline_args()
		_hud_was_visible = false
	if _mode_node != null:
		_mode_node.queue_free()
		_mode_node = null
	player_busy = false
	_redraw = true


func script_shop(store_id: int) -> void:
	request_shop(store_id, true)


## ScriptVM 异步商店：关闭后 vm.resume_menu()
func request_shop(store_id: int, is_buy: bool = true) -> void:
	if not ResourceLoader.exists("res://game/shop.gd"):
		push_warning("World: 商店模块未就绪，跳过 store=%d" % store_id)
		_resume_vm_menu()
		return
	var shop_script = load("res://game/shop.gd")
	if shop_script == null:
		push_warning("World: shop.gd 编译失败，跳过商店")
		_resume_vm_menu()
		return
	var s = shop_script.new()
	s.setup(store_id, is_buy)
	if _status_label != null and _status_label.visible:
		_status_label.visible = false
		_hud_was_visible = true
	s.closed.connect(Callable(self, "_on_shop_closed"))
	_mode_node = s
	add_child(s)
	player_busy = true


func _on_shop_closed() -> void:
	if _mode_node != null:
		_mode_node.queue_free()
		_mode_node = null
	player_busy = false
	if _hud_was_visible and _status_label != null:
		_status_label.visible = "--debug-hud" in OS.get_cmdline_args()
		_hud_was_visible = false
	_redraw = true
	_resume_vm_menu()


func _resume_vm_menu() -> void:
	if vm != null and vm.is_active() and vm.has_method("resume_menu"):
		vm.resume_menu()


# ------------------------------------------------------------------ RNG / 结局

func request_rng(rng_id: int) -> void:
	PALState.current_rng = rng_id
	if not ResourceLoader.exists("res://pal/rng_player.gd"):
		_log_auto("RNG %d (播放器未就绪)" % rng_id)
		return
	var rng_script = load("res://pal/rng_player.gd")
	if rng_script == null:
		_log_auto("RNG %d (播放器编译失败)" % rng_id)
		return
	var r = rng_script.new()
	_rng = r
	add_child(r)
	if r.has_signal("finished"):
		r.finished.connect(Callable(self, "_on_rng_finished"), CONNECT_ONE_SHOT)
	r.play(rng_id)


func _on_rng_finished() -> void:
	if _rng != null:
		if _rng.has_method("set_screen_visible"):
			_rng.set_screen_visible(false)
		_rng.queue_free()
		_rng = null
	_redraw = true


# ------------------------------------------------------------------ 脚本同步执行（装备/物品效果等）

## 战斗/菜单等模块用的脚本钩子：同步跑完一段脚本（遇到需要按键/等待则中断）
func run_script_entry(entry: int) -> bool:
	if entry == 0:
		return false
	run_script_entry_sync(entry, 0xFFFF)
	return true


func run_script_entry_sync(entry: int, evt_id: int = 0xFFFF) -> void:
	var tmp := ScriptVM.new()
	tmp.setup(sss, self)
	tmp.start(entry, evt_id)
	var guard := 0
	while tmp.is_active() and not tmp.waiting_dialog and guard < 2000:
		tmp.tick()
		guard += 1


# ------------------------------------------------------------------ 自动演示 / 取证

func _log_auto(line: String) -> void:
	if _auto_mode:
		print("[auto] ", line)


func _auto_debug_snapshot() -> void:
	if not _auto_mode or _auto_timer % 300 != 0:
		return
	if not ("--debug-hud" in OS.get_cmdline_args()):
		return
	var p := abs_party()
	var vm_state := "off"
	if vm != null and vm.is_active():
		vm_state = "ip=%d dlg=%s key=%s choice=%s menu=%s bat=%s rng=%s" % [
			vm.ip, vm.waiting_dialog, vm.waiting_key, vm.waiting_choice,
			vm.waiting_menu, vm.waiting_battle, vm.waiting_rng]
	print("[AUTO] t=%d scene=%d pos=%s target=%s path=%d busy=%s mode=%s vm[%s]" % [
		_auto_timer, PALState.scene, p, _auto_target, _nav_path.size(),
		player_busy, (_mode_node != null), vm_state])


func _auto_tick() -> void:
	_auto_timer += 1
	if _auto_timer % 600 == 0:
		_auto_screenshot("s%d_t%d" % [PALState.scene, _auto_timer])
	if _sim_space:
		return
	if _auto_force_jump and _mode_node == null and not _auto_ending_fired:
		_auto_force_jump = false
		var jumped := false
		for cand in range(1, 295):
			if not _auto_visited_scenes.has(cand):
				_log_auto("CYCLE_BREAK -> unvisited scene %d" % cand)
				_auto_visited_scenes[cand] = true
				call_deferred("load_scene", cand, false)
				jumped = true
				break
		if not jumped:
			var nxt := (PALState.scene % 294) + 1
			_log_auto("CYCLE_BREAK -> next scene %d" % nxt)
			call_deferred("load_scene", nxt, false)
		return
	_auto_debug_snapshot()
	if vm != null and vm.is_active():
		# 非对话框等待状态：auto 模式自动放行（否则无人按键会永久卡住）
		if vm.waiting_key and _auto_timer % 30 == 0:
			if vm.has_method("resume_key"):
				vm.resume_key()
		elif vm.waiting_choice and _auto_timer % 30 == 0:
			if vm.has_method("resume_choice"):
				vm.resume_choice(true)
		elif vm.waiting_menu and _auto_timer % 30 == 0:
			if vm.has_method("resume_menu"):
				vm.resume_menu()
		elif vm.waiting_rng and _auto_timer % 30 == 0:
			if vm.has_method("resume_rng"):
				vm.resume_rng()
		# 卡死看门狗：ip 600 帧不变且没有模态节点 → 记录并强制推进
		if vm.ip == _auto_last_ip:
			_auto_stall += 1
		else:
			_auto_last_ip = vm.ip
			_auto_stall = 0
		if _auto_stall > 900 and _mode_node == null:
			var op := sss.script_entry(vm.ip)
			print("[auto] STALL_FORCE ip=", vm.ip, " op=0x%04x" % int(op[0]))
			_auto_stall = 0
			if vm.waiting_dialog:
				vm.advance_dialog()
			elif vm.waiting_key and vm.has_method("resume_key"):
				vm.resume_key()
			elif vm.waiting_choice and vm.has_method("resume_choice"):
				vm.resume_choice(true)
			elif vm.waiting_menu and vm.has_method("resume_menu"):
				vm.resume_menu()
			elif vm.waiting_rng and vm.has_method("resume_rng"):
				vm.resume_rng()
			elif vm.has_method("force_finish"):
				vm.force_finish()
	if vm != null and vm.is_active() and vm.waiting_dialog:
		if _auto_timer % 8 == 0:
			if _dialog_box != null and _dialog_box.has_method("is_active") and _dialog_box.is_active():
				if _dialog_box.has_method("is_typing") and _dialog_box.is_typing():
					_dialog_box.finish_typing()
				elif not _dialog_box.advance():
					vm.advance_dialog()
			else:
				vm.advance_dialog()
			_redraw = true
	if _auto_timer == 90 or _auto_timer == 300 or _auto_timer == 900 or _auto_timer == 1800 or _auto_timer == 2600:
		_auto_screenshot()
	# 有商店/菜单模态时，auto 模式自动关闭（避免无人按键卡死）
	if _mode_node != null:
		if _auto_timer % 90 == 0:
			_auto_close_mode()
		_auto_walk_dir = -1
		return
	if not (vm != null and vm.is_active()) and not player_busy:
		var before := abs_party()
		if before == _auto_last_pos:
			_auto_stuck_frames += 1
		else:
			_auto_last_pos = before
			_auto_stuck_frames = 0
		if _auto_stuck_frames > 600:
			_auto_stuck_frames = 0
			_force_door_trigger()
			return
	if _auto_break_vm and vm != null and vm.is_active():
		_auto_break_vm = false
		_log_auto("DIALOG_LOOP_BREAK ip=%d" % vm.ip)
		if vm.has_method("force_finish"):
			vm.force_finish()
		else:
			vm.ended = true
		player_busy = false
	# 位置看门狗：长时间位置不变则强制换场景（防寻路/碰撞死循环）
	if _auto_mode and _mode_node == null and not _auto_ending_fired:
		var dlg_on: bool = _dialog_box != null and bool(_dialog_box.is_active())
		if not dlg_on:
			var now_pos := abs_party()
			if now_pos == _auto_watch_pos:
				_auto_watch += 1
			else:
				_auto_watch_pos = now_pos
				_auto_watch = 0
			if _auto_watch > 600:
				_auto_watch = 0
				_log_auto("POS_STUCK -> F8")
				if vm != null and vm.is_active() and vm.has_method("force_finish"):
					vm.force_finish()
				player_busy = false
				_force_door_trigger()
				return
	# busy 卡死自愈：无 VM/无对话框/无模式节点却 player_busy 时，连续 90 帧后强制解锁
	if _auto_mode and player_busy and _mode_node == null and (vm == null or not vm.is_active()):
		var dlg_open: bool = _dialog_box != null and bool(_dialog_box.is_active())
		if dlg_open and (vm == null or not vm.is_active()):
			_auto_busy_stuck += 1
			if _auto_busy_stuck > 120:
				_auto_busy_stuck = 0
				if _dialog_box.has_method("clear"):
					_dialog_box.clear()
				player_busy = false
				_log_auto("AUTO_CLEAR_STALE_DIALOG")
		elif not dlg_open:
			_auto_busy_stuck += 1
			if _auto_busy_stuck > 90:
				_auto_busy_stuck = 0
				player_busy = false
				_log_auto("AUTO_UNSTICK_BUSY")
		else:
			_auto_busy_stuck = 0
	else:
		_auto_busy_stuck = 0
	_auto_frames_since_scene += 1
	# 分段续跑：空闲时定期存档槽 0（仅 auto 验收模式）
	if _auto_mode and _auto_timer > 0 and _auto_timer % 900 == 0 \
			and not player_busy and _mode_node == null and not (vm != null and vm.is_active()):
		if PALState.save_game(9):
			_save_auto_visited()
			_log_auto("AUTO_SAVE slot9 scene=%d pos=%s visited=%d" % [PALState.scene, str(abs_party()), _auto_visited_scenes.size()])
	if _auto_frames_since_scene > 450 and _mode_node == null and not _auto_ending_fired:
		_auto_frames_since_scene = 0
		player_busy = false
		if vm != null and vm.is_active():
			_log_auto("PROGRESS_TIMEOUT(vm busy) -> force_finish + F8")
			if vm.has_method("force_finish"):
				vm.force_finish()
			else:
				vm.ended = true
		else:
			_log_auto("PROGRESS_TIMEOUT -> F8")
		_force_door_trigger()
		return
	# 本地事件扫荡：先触发当前场景的触发脚本（战斗/对话/机关），再交给场景图导航
	if _auto_mode and not player_busy and _mode_node == null:
		if _auto_sweep_wait > 0:
			_auto_sweep_wait -= 1
			if _auto_sweep_wait == 0 and vm != null and vm.is_active():
				if vm.has_method("force_finish"):
					vm.force_finish()
				else:
					vm.ended = true
				player_busy = false
		elif not _auto_sweep_done and not (vm != null and vm.is_active()):
			_auto_sweep_try()
	if PALState.scene >= 2 and not (vm != null and vm.is_active()) and not player_busy:
		_auto_navigate()
		# 模拟按空格：搜索型触发（门/机关/NPC 对话）
		if _auto_timer % 30 == 0:
			_do_search()
	else:
		_auto_walk_dir = -1


## 扫荡当前场景的触发事件：传送到事件旁并执行其触发脚本
func _auto_sweep_try() -> void:
	if not _auto_sweep_enabled:
		_auto_sweep_done = true
		return
	if _auto_sweep_count >= 4:
		_auto_sweep_done = true
		return
	var id := _auto_sweep_id
	while id <= evt_end:
		var o: Array = sss.event(id)
		var trig := int(o[PalData.EO_TRIGGER_SCRIPT])
		if int(o[PalData.EO_STATE]) > 0 and trig != 0 and not _auto_used.has(id):
			_auto_used[id] = true
			var pos := Vector2i(int(o[PalData.EO_X]), int(o[PalData.EO_Y]))
			PALState.viewport = pos - PARTY_OFFSET
			_clamp_viewport()
			for i in range(PALState.party.size()):
				PALState.party[i]["x"] = PARTY_OFFSET.x
				PALState.party[i]["y"] = PARTY_OFFSET.y
				PALState.trail[i] = {"x": pos.x, "y": pos.y, "dir": PALState.party_dir}
			_anim_remaining = 0
			_auto_sweep_id = id + 1
			_auto_sweep_count += 1
			_auto_sweep_wait = 240
			_log_auto("SWEEP event=%d -> script=%d pos=%s" % [id, trig, pos])
			_start_script(trig, id)
			_redraw = true
			return
		id += 1
	_auto_sweep_done = true


## 自动导航：BFS 寻路到最近的可触发事件对象（门/NPC），用于无人值守主线推进
var _nav_path: Array = []          # Array[Vector2i]：像素路点（按顺序）
var _nav_goal: Vector2i = Vector2i(-1, -1)
var _nav_recalc: int = 0

const NAV_W := 64
const NAV_H := 128


func _auto_navigate() -> void:
	if _auto_target.x < 0 or _auto_timer % 120 == 0:
		_auto_pick_target()
	if _auto_target.x < 0:
		var phase: int = (_auto_timer / 120) % 4
		var dirs := [DIR_SOUTH, DIR_EAST, DIR_NORTH, DIR_WEST]
		_auto_walk_dir = dirs[phase]
		return
	var p := abs_party()
	var ndx := _auto_target.x - p.x
	var ndy := _auto_target.y - p.y
	# 面向目标（搜索触发的 13 检查点依赖朝向）
	if absi(ndx) >= absi(ndy):
		if ndx > 0:
			PALState.party_dir = DIR_EAST
		elif ndx < 0:
			PALState.party_dir = DIR_WEST
		elif ndy > 0:
			PALState.party_dir = DIR_SOUTH
		elif ndy < 0:
			PALState.party_dir = DIR_NORTH
	else:
		if ndy > 0:
			PALState.party_dir = DIR_SOUTH
		elif ndy < 0:
			PALState.party_dir = DIR_NORTH
		elif ndx > 0:
			PALState.party_dir = DIR_EAST
		elif ndx < 0:
			PALState.party_dir = DIR_WEST
	if absi(ndx) <= 40 and absi(ndy) <= 32:
		_auto_walk_dir = -1
		# 验收辅助：2 格内卡住 240 帧 → 吸附到目标格（仅 --auto 生效，便于无人值守跑主线）
		if absi(ndx) > 0 or absi(ndy) > 0:
			_auto_near_frames += 1
			if _auto_near_frames > 240:
				_auto_near_frames = 0
				PALState.viewport = Vector2i(_auto_target.x, _auto_target.y) - PARTY_OFFSET
				_clamp_viewport()
				var abs_pos := PALState.viewport + PARTY_OFFSET
				for i in range(PALState.trail.size()):
					PALState.trail[i] = {"x": abs_pos.x, "y": abs_pos.y, "dir": PALState.party_dir}
				if "--debug-hud" in OS.get_cmdline_args():
					print("[auto] SNAP to target ", _auto_target, " (id=", _auto_target_id, ")")
				_redraw = true
		else:
			_auto_near_frames = 0
		if _auto_timer % 8 == 0:
			_do_search()
			_check_touch_triggers()
		# 精确站到目标像素才停（搜索触发要求半格/整格一致）
		if ndx == 0 and ndy == 0:
			return
		# 否则继续靠近（下面走 BFS/直线步进）
	if _nav_path.is_empty() or _nav_recalc <= 0 or _nav_goal != _auto_target:
		_nav_recalc = 90
		_nav_goal = _auto_target
		_nav_path = _bfs_path(p, _auto_target)
		if _nav_path.is_empty():
			_nav_fail_frames += 1
			if _nav_fail_frames > 40:
				_nav_fail_frames = 0
				_log_auto("NAV_FAIL -> F8")
				_force_door_trigger()
				return
		else:
			_nav_fail_frames = 0
	else:
		_nav_recalc -= 1
	if _nav_path.is_empty():
		# BFS 不可达（目标格被挡）：退化直线贪心，靠触碰半径触发
		var tdx: int = _auto_target.x - p.x
		var tdy: int = _auto_target.y - p.y
		if absi(tdx) >= absi(tdy):
			if tdx > 0:
				_auto_walk_dir = DIR_EAST
			elif tdx < 0:
				_auto_walk_dir = DIR_WEST
			elif tdy > 0:
				_auto_walk_dir = DIR_SOUTH
			elif tdy < 0:
				_auto_walk_dir = DIR_NORTH
		else:
			if tdy > 0:
				_auto_walk_dir = DIR_SOUTH
			elif tdy < 0:
				_auto_walk_dir = DIR_NORTH
			elif tdx > 0:
				_auto_walk_dir = DIR_EAST
			elif tdx < 0:
				_auto_walk_dir = DIR_WEST
		return
	var wp: Vector2i = _nav_path[0]
	var dx := wp.x - p.x
	var dy := wp.y - p.y
	if dx == 0 and dy == 0:
		_nav_path.pop_front()
		if _nav_path.is_empty():
			_auto_walk_dir = -1
			return
		wp = _nav_path[0]
		dx = wp.x - p.x
		dy = wp.y - p.y
	# 走一步：优先保证不撞墙的方向
	var prefer: Array[int] = []
	if absi(dx) >= absi(dy):
		if dx > 0:
			prefer.append(DIR_EAST)
		elif dx < 0:
			prefer.append(DIR_WEST)
		if dy > 0:
			prefer.append(DIR_SOUTH)
		elif dy < 0:
			prefer.append(DIR_NORTH)
	else:
		if dy > 0:
			prefer.append(DIR_SOUTH)
		elif dy < 0:
			prefer.append(DIR_NORTH)
		if dx > 0:
			prefer.append(DIR_EAST)
		elif dx < 0:
			prefer.append(DIR_WEST)
	# 附加垂直/备用方向，避免贴墙卡住
	for d in [DIR_EAST, DIR_WEST, DIR_SOUTH, DIR_NORTH]:
		if not prefer.has(d):
			prefer.append(d)
	for d in prefer:
		if _can_step(p, d):
			_auto_walk_dir = d
			return
	_auto_walk_dir = -1


func _can_step(p: Vector2i, d: int) -> bool:
	var delta := Vector2i.ZERO
	match d:
		DIR_WEST:
			delta = Vector2i(-2, 0)
		DIR_EAST:
			delta = Vector2i(2, 0)
		DIR_NORTH:
			delta = Vector2i(0, -1)
		DIR_SOUTH:
			delta = Vector2i(0, 1)
	var np := Vector2i(p.x + delta.x, p.y + delta.y)
	if _near_scene_door(np):
		return false
	return not _is_obstacle(np.x, np.y)


## 把事件对象加入导航目标：优先 touch 触发（门），其次 search/其它
func _load_scene_graph() -> void:
	var path := "res://data/scene_graph.json"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		for k in parsed.keys():
			var arr: Array = []
			for v in parsed[k]:
				arr.append(int(v))
			_scene_graph[int(k)] = arr
	if _scene_graph.size() > 0:
		_log_auto("SCENE_GRAPH loaded %d scenes" % _scene_graph.size())


const AUTO_VISITED_PATH := "user://auto_visited.json"


func _script_has_ending(entry: int) -> bool:
	var seen := {}
	var work: Array[int] = [entry]
	while not work.is_empty() and seen.size() < 400:
		var e: int = work.pop_back()
		if e <= 0 or e >= sss.scripts.size() or seen.has(e):
			continue
		seen[e] = true
		var q: PackedInt32Array = sss.script_entry(e)
		var code := int(q[0])
		if code == 0x0096 or code == 0x00A0:
			return true
		if code == 0x0000:
			continue
		work.append(e + 1)
		if code in [0x0002, 0x0003, 0x0004, 0x0006, 0x000A, 0x0016, 0x001A,
				0x0064, 0x0066, 0x0067, 0x0068, 0x0069, 0x006A, 0x006B, 0x0078,
				0x008A, 0x0091, 0x009C, 0x009E, 0x00A2]:
			for t in [int(q[1]), int(q[2]), int(q[3])]:
				if t > 0 and t < sss.scripts.size():
					work.append(t)
	return false


func _auto_maybe_trigger_ending() -> void:
	if _auto_ending_fired or not _auto_mode:
		return
	for id in range(evt_start + 1, evt_end + 1):
		var o: Array = sss.event(id)
		var trig := int(o[PalData.EO_TRIGGER_SCRIPT])
		if trig != 0 and _script_has_ending(trig):
			_auto_ending_fired = true
			_log_auto("AUTO_ENDING_TRIGGER scene=%d event=%d script=%d" % [PALState.scene, id, trig])
			_start_script(trig, id)
			return


func _load_auto_visited() -> void:
	if not _auto_mode:
		return
	if not FileAccess.file_exists(AUTO_VISITED_PATH):
		return
	var f := FileAccess.open(AUTO_VISITED_PATH, FileAccess.READ)
	if f == null:
		return
	var arr = JSON.parse_string(f.get_as_text())
	if arr is Array:
		for v in arr:
			_auto_visited_scenes[int(v)] = true
		_log_auto("AUTO_VISITED loaded %d scenes" % _auto_visited_scenes.size())


func _save_auto_visited() -> void:
	if not _auto_mode:
		return
	var f := FileAccess.open(AUTO_VISITED_PATH, FileAccess.WRITE)
	if f == null:
		return
	var keys: Array = _auto_visited_scenes.keys()
	keys.sort()
	f.store_string(JSON.stringify(keys))
	f.close()


## BFS：从 from 到最近的未访问场景，返回 [目标场景, 第一跳]（不可达返回空）
func _nearest_unvisited_scene(from_scene: int) -> Array:
	if _scene_graph.is_empty():
		return []
	var prev := {}
	var q: Array[int] = [from_scene]
	var seen := {from_scene: true}
	while not q.is_empty():
		var cur: int = q.pop_front()
		if cur != from_scene and not _auto_visited_scenes.has(cur):
			# 回溯第一跳
			var node := cur
			while int(prev.get(node, from_scene)) != from_scene and prev.has(node):
				node = int(prev[node])
			return [cur, node]
		for t in _scene_graph.get(cur, []):
			var nt := int(t)
			if seen.has(nt):
				continue
			seen[nt] = true
			prev[nt] = cur
			q.append(nt)
	return []


## 扫描某脚本入口可达的 0x0059 目标场景（近似解释器：线性 + 跳转操作码）
func _script_scene_targets(entry: int) -> Array:
	var out: Array = []
	var seen := {}
	var work: Array[int] = [entry]
	while not work.is_empty() and seen.size() < 400:
		var e: int = work.pop_back()
		if e <= 0 or e >= sss.scripts.size() or seen.has(e):
			continue
		seen[e] = true
		var q: PackedInt32Array = sss.script_entry(e)
		var code := int(q[0])
		if code == 0x0059 and int(q[1]) > 0 and int(q[1]) != PALState.scene:
			out.append(int(q[1]))
		if code == 0x0000:
			continue
		work.append(e + 1)
		if code in [0x0002, 0x0003, 0x0004, 0x0006, 0x000A, 0x0016, 0x001A,
				0x0064, 0x0066, 0x0067, 0x0068, 0x0069, 0x006A, 0x006B, 0x0078,
				0x008A, 0x0091, 0x009C, 0x009E, 0x00A2]:
			for t in [int(q[1]), int(q[2]), int(q[3])]:
				if t > 0 and t < sss.scripts.size():
					work.append(t)
	return out


## 找当前场景的“换场景门”（触发脚本前 16 条含 0x0059 目标场景 != 当前场景）
func _find_scene_door() -> Dictionary:
	var best := {}
	var best_d := 1 << 30
	var p := abs_party()
	var path := _nearest_unvisited_scene(PALState.scene) if _auto_mode else []
	var want_scene: int = int(path[0]) if path.size() >= 1 else 0
	var want_first: int = int(path[1]) if path.size() >= 2 else 0
	for id in range(evt_start + 1, evt_end + 1):
		var o: Array = sss.event(id)
		if int(o[PalData.EO_STATE]) <= 0:
			continue
		var trig := int(o[PalData.EO_TRIGGER_SCRIPT])
		if trig == 0:
			continue
		var targets := _script_scene_targets(trig)
		if targets.is_empty():
			continue
		var target_scene := int(targets[0])
		# 优先“朝最近未访问场景的第一跳”的事件；已访问场景的门在 auto 下跳过
		var score := 1000000
		if _auto_mode and want_first != 0:
			if targets.has(want_first):
				score = 0
			elif want_scene != 0 and targets.has(want_scene):
				score = 10
			elif _auto_visited_scenes.has(target_scene):
				continue
			else:
				score = 1000
		var pos := Vector2i(int(o[PalData.EO_X]), int(o[PalData.EO_Y]))
		var d: int = score + absi(pos.x - p.x) + absi(pos.y - p.y) * 2
		if d < best_d:
			best_d = d
			best = {"id": id, "trigger": trig, "pos": pos, "scene": target_scene}
	return best


## F8 / auto 卡死兜底：把队伍放到门边并直接触发门脚本（0x0046 + 0x0059）
func _force_door_trigger() -> void:
	# 自动模式：直接按场景图 BFS 切到最近未访问场景；分量耗尽则全局跳到任意未访问场景
	if _auto_mode:
		var auto_path := _nearest_unvisited_scene(PALState.scene)
		if auto_path.size() >= 2:
			var next_scene := int(auto_path[1])
			_log_auto("F8: scene-graph -> scene %d (goal %d)" % [next_scene, int(auto_path[0])])
			_auto_visited_scenes[next_scene] = true
			call_deferred("load_scene", next_scene, false)
			return
		for cand in range(1, 295):
			if not _auto_visited_scenes.has(cand):
				_log_auto("F8: fallback unvisited scene %d" % cand)
				_auto_visited_scenes[cand] = true
				call_deferred("load_scene", cand, false)
				return
		_log_auto("F8: 所有场景已访问")
		return
	var door := _find_scene_door()
	if door.is_empty():
		var path := _nearest_unvisited_scene(PALState.scene)
		if _auto_mode and path.size() >= 2:
			_log_auto("F8: 无门事件 -> 直接载入场景 %d" % int(path[1]))
			_auto_visited_scenes[int(path[1])] = true
			call_deferred("load_scene", int(path[1]), false)
			return
		_log_auto("F8: 当前场景没有换场景门")
		return
	var pos: Vector2i = door["pos"]
	PALState.viewport = pos - PARTY_OFFSET
	_clamp_viewport()
	for i in range(PALState.party.size()):
		PALState.party[i]["x"] = PARTY_OFFSET.x
		PALState.party[i]["y"] = PARTY_OFFSET.y
		PALState.trail[i] = {"x": pos.x, "y": pos.y, "dir": PALState.party_dir}
	_log_auto("F8: door event=%d -> scene %d" % [door["id"], door["scene"]])
	_auto_used[door["id"]] = true
	_auto_target_id = int(door["id"])
	_start_script(int(door["trigger"]), int(door["id"]))
	_redraw = true


## 收集当前场景“换场景门”的位置（mode>=4 且触发脚本含 0x0059 目标 != 当前场景）
func _refresh_scene_doors() -> void:
	_scene_door_positions = []
	if sss == null:
		return
	for id in range(evt_start + 1, evt_end + 1):
		var o: Array = sss.event(id)
		if int(o[PalData.EO_STATE]) <= 0:
			continue
		if int(o[PalData.EO_TRIGGER_MODE]) < 4:
			continue
		var trig := int(o[PalData.EO_TRIGGER_SCRIPT])
		if trig == 0:
			continue
		var is_door := false
		for k in range(trig, mini(trig + 16, sss.scripts.size())):
			var q: PackedInt32Array = sss.script_entry(k)
			if int(q[0]) == 0x0059 and int(q[1]) > 0 and int(q[1]) != PALState.scene:
				is_door = true
				break
			if int(q[0]) == 0x0000:
				break
		if is_door:
			_scene_door_positions.append({
				"id": id,
				"pos": Vector2i(int(o[PalData.EO_X]), int(o[PalData.EO_Y])),
			})


## pos 是否落在某扇换场景门的触发区内（排除当前目标门）
func _near_scene_door(pos: Vector2i) -> bool:
	if _auto_ignore_doors > 0:
		return false
	for d in _scene_door_positions:
		if int(d["id"]) == _auto_target_id:
			continue
		var dp: Vector2i = d["pos"]
		if absi(pos.x - dp.x) + absi(pos.y - dp.y) * 2 < 56:
			return true
	return false


func _auto_pick_target() -> void:
	_auto_target = Vector2i(-1, -1)
	_auto_target_id = 0
	_nav_path = []
	var p := abs_party()
	var best := 1 << 30
	if _auto_used.size() >= (evt_end - evt_start):
		_auto_used.clear()
	for id in range(evt_start + 1, evt_end + 1):
		var o: Array = sss.event(id)
		if int(o[PalData.EO_STATE]) <= 0:
			continue
		if int(o[PalData.EO_TRIGGER_SCRIPT]) == 0 and int(o[PalData.EO_AUTO_SCRIPT]) == 0:
			continue
		if int(o[PalData.EO_VANISH]) != 0:
			continue
		if _auto_used.has(id):
			continue
		var pos := Vector2i(int(o[PalData.EO_X]), int(o[PalData.EO_Y]))
		var d: int = absi(pos.x - p.x) + absi(pos.y - p.y) * 2
		# 调查/对话事件优先；换场景门只作为兜底目标
		if int(o[PalData.EO_TRIGGER_MODE]) >= 4:
			d += 100000
		if d < best:
			best = d
			_auto_target = pos
			_auto_target_id = id


## 4 邻接 BFS（图块网格），返回像素路点数组
func _bfs_path(from_pos: Vector2i, to_pos: Vector2i) -> Array:
	var sx: int = clampi(from_pos.x / 32, 0, NAV_W - 1)
	var sy: int = clampi(from_pos.y / 16, 0, NAV_H - 1)
	var tx: int = clampi(to_pos.x / 32, 0, NAV_W - 1)
	var ty: int = clampi(to_pos.y / 16, 0, NAV_H - 1)
	var key := func(x: int, y: int) -> int: return y * NAV_W + x
	var prev := {}
	var q: Array[int] = [sy * NAV_W + sx]
	var seen := {sy * NAV_W + sx: true}
	var goal := ty * NAV_W + tx
	var dirs := [[0, -1], [1, 0], [0, 1], [-1, 0]]
	var found := false
	while not q.is_empty():
		var cur: int = q.pop_front()
		if cur == goal:
			found = true
			break
		var cx: int = cur % NAV_W
		var cy: int = cur / NAV_W
		for dd in dirs:
			var nx: int = cx + int(dd[0])
			var ny: int = cy + int(dd[1])
			if nx < 0 or ny < 0 or nx >= NAV_W or ny >= NAV_H:
				continue
			var nk := ny * NAV_W + nx
			if seen.has(nk):
				continue
			# 目标格允许“不可走”（门/NPC 所在格），其余需可走
			if nk != goal and _is_obstacle(nx * 32 + 16, ny * 16 + 8):
				continue
			if nk != goal and _near_scene_door(Vector2i(nx * 32 + 16, ny * 16 + 8)):
				continue
			seen[nk] = true
			prev[nk] = cur
			q.append(nk)
	if not found:
		return []
	var path: Array = []
	var node := goal
	while node != sy * NAV_W + sx:
		var nx: int = node % NAV_W
		var ny: int = node / NAV_W
		path.push_front(Vector2i(nx * 32 + 16, ny * 16 + 8))
		node = prev[node]
	# 最后一格用目标对象的精确像素（半格对齐决定触发 h）
	path.append(to_pos)
	return path


func _auto_close_mode() -> void:
	if _mode_node == null:
		return
	if _mode_node.has_method("close_for_auto"):
		_mode_node.close_for_auto()
	elif _mode_node.has_signal("closed"):
		_mode_node.emit_signal("closed")


func _auto_screenshot(tag: String = "") -> void:
	if not _auto_mode:
		return
	# headless：直接存世界合成帧（320x200），作为场景覆盖证据
	if DisplayServer.get_name() == "headless" or "_img" in self:
		if _img != null and tag != "":
			var path := SHOT_DIR + "auto_%s.png" % tag
			_img.save_png(path)
			print("[auto] SHOT ", path)
			return
	_auto_screenshot_vp(tag)


func _auto_screenshot_vp(tag: String = "") -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	_auto_shot_index += 1
	var name := ("auto_%02d_%s.png" % [_auto_shot_index, tag]) if tag != "" else ("auto_%02d_scene%d.png" % [_auto_shot_index, PALState.scene])
	var path := SHOT_DIR + name
	img.save_png(path)
	print("[auto] SHOT ", path)
