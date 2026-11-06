extends RefCounted
## VM 全场景压测（295 场景 onEnter/onTeleport + 事件触发脚本 + 自动脚本）。
##
## 启动方式（**不能**用 `--script`：该模式不注册 autoload，ScriptVM 无法编译）：
##   Godot_console.exe --headless --path <proj> --auto --vm-sweep
## 入口在 `pal/script_vm.gd: setup()`（检测到 --vm-sweep 时调用本文件 run_all()）。
## 输出：_rea_runtime/out/vm_sweep.json + 控制台 PASS/FAIL 汇总。
##
## 设计：
##   - MockWorld 只实现 `game/world.gd` 真实提供的钩子（缺的让 VM 走 has_method 兜底并计入
##     missing_hooks），从而报告可直接对照真实缺口；
##   - 每段脚本驱动到结束或帧上限：对白自动确认、战斗按胜利、菜单/RNG/按键/选择立刻回调；
##   - 统计 unknown opcode、missing hook、帧上限、以及 PALState 的不变量（队伍/角色/场景/背包）。

const OUT_PATH := "<LOCAL_PATH>"
const SCENE_COUNT := 295
const SCRIPT_COUNT := 43557
const EVENT_COUNT := 5077

const MAX_FRAMES_SCENE := 5000      # onEnter/onTeleport 每段脚本帧上限
const MAX_FRAMES_TRIGGER := 2500    # 事件触发脚本帧上限
const AUTO_STEPS := 1500            # 每个自动脚本最多推进的指令数（自动脚本每帧一条）

var sss: PalData = null
var mock: MockWorld = null
var stats := {}
var scene_snapshot: Array = []     # 初始 SCENE 表快照（每场景隔离压测用）
var event_snapshot: Array = []     # 初始 EVENTOBJECT 表快照

# 最近一次运行的报告（供 JSON 输出）
var scene_rows: Array = []
var trigger_rows: Array = []
var auto_rows: Array = []
var unknown_ops: Dictionary = {}
var missing_hooks: Dictionary = {}
var cap_hits: Array = []
var sanity_issues: Dictionary = {}
var dialog_samples: Array = []
# 累计计数
var scene_entry_count: int = 0
var trigger_script_count: int = 0
var auto_script_count: int = 0
# 交互类 opcode 的采样（0x0007 战斗 / 0x0026 商店 / 0x0037 RNG / 0x0059 切场景）
var interactions: Dictionary = {"battles": [], "shops": [], "rngs": [], "scene_changes": []}


# ================================================================== Mock 世界
## 最小地图：永远不阻挡，尺寸按 sdlpal 2048×2048 像素。
class MockMap:
	var map_index: int = 0
	var tile_frames: Array = []

	func is_blocked(_x: int, _y: int, _h: int) -> bool:
		return false

	func map_pixel_width() -> int:
		return 2048

	func map_pixel_height() -> int:
		return 2048

	func get_tile_height(_x: int, _y: int, _h: int) -> int:
		return 0

	func tile_image(_x: int, _y: int, _h: int, _l: int) -> Image:
		return null


## 模拟 game/world.gd：方法名/签名与其保持一致，实现为无渲染的状态更新 + 计数。
class MockWorld extends Node:
	var sss: PalData = null
	var current_map = MockMap.new()
	var evt_start: int = 0
	var evt_end: int = 0
	var counts: Dictionary = {}
	var dialogs: Array = []
	var scene_changes: Array = []
	var battles: Array = []
	var shops: Array = []
	var rngs: Array = []


	func reset_counts() -> void:
		counts = {
			"dialogs": 0, "face": 0, "music": 0, "sound": 0, "refresh": 0,
			"battles": 0, "shops": 0, "rngs": 0, "choices": 0, "keys": 0,
			"fades": 0, "palette": 0, "pictures": 0, "ending": 0, "load_game": 0,
			"scene_events": 0, "party_gesture": 0, "party_position": 0,
			"player_sprite": 0, "set_party": 0, "shake": 0, "wave": 0,
			"battlefield": 0, "backup": 0, "reload_map": 0, "menu_open": 0,
		}
		dialogs = []
		scene_changes = []
		battles = []
		shops = []
		rngs = []


	func _inc(key: String, n: int = 1) -> void:
		counts[key] = int(counts.get(key, 0)) + n


	# ---- 对白/对话框
	func script_dialog(text: String, msg_id: int) -> void:
		_inc("dialogs")
		if dialogs.size() < 50:
			dialogs.append([msg_id, PalData.strip_control_codes(text).substr(0, 24)])


	func script_dialog_closed() -> void:
		pass


	func script_dialog_clear() -> void:
		pass


	func script_dialog_style(_style: int) -> void:
		pass


	func script_dialog_face(_face: int, _base_color: int) -> void:
		_inc("face")


	# ---- 刷新/场景
	func script_refresh(_gestures: bool) -> void:
		_inc("refresh")


	func script_change_scene(n: int) -> void:
		scene_changes.append(n)


	func script_party_position(gx: int, gy: int, half: int) -> void:
		_inc("party_position")
		var abs_pos := Vector2i(gx * 32 + half * 16, gy * 16 + half * 8)
		PALState.viewport = abs_pos - Vector2i(160, 112)
		for i in range(PALState.party.size()):
			PALState.party[i]["x"] = 160
			PALState.party[i]["y"] = 112
		_clamp_viewport()


	func script_party_gesture(direction: int, frame: int, index: int) -> void:
		_inc("party_gesture")
		if direction >= 0 and direction <= 3:
			if index >= 0 and index < PALState.party.size():
				PALState.party[index]["frame"] = direction * 3 + frame
			else:
				PALState.party[0]["frame"] = direction * 3 + frame
			PALState.party_dir = direction


	func script_player_sprite(role: int, sprite_num: int, _refresh: int) -> void:
		_inc("player_sprite")
		if role >= 0 and role < 6:
			PALState.roles["sprite_in_scene"][role] = sprite_num


	func script_set_party(r0: int, r1: int, r2: int) -> void:
		_inc("set_party")
		var roles: Array = []
		for v in [r0, r1, r2]:
			if v != 0:
				roles.append(v - 1)
		if roles.is_empty():
			roles.append(0)
		PALState.max_party_member_index = roles.size() - 1
		for i in range(PALState.party.size()):
			PALState.party[i]["role"] = roles[mini(i, roles.size() - 1)]


	func script_event_state(which: int, state: int, last_id: int) -> void:
		_inc("scene_events")
		var id := last_id if which == 0 else which
		if id >= 1 and id <= sss.events.size():
			sss.event(id)[PalData.EO_STATE] = state


	# ---- 音频/画面
	func script_music(music_num: int, _mode: int) -> void:
		_inc("music")
		PALState.music = music_num


	func script_sound(_sound_num: int) -> void:
		_inc("sound")


	func script_fade_out(_speed: int) -> void:
		_inc("fades")


	func script_fade_in(_speed: int) -> void:
		_inc("fades")


	func script_use_day_palette() -> void:
		_inc("palette")
		PALState.night_palette = false


	func script_use_night_palette() -> void:
		_inc("palette")
		PALState.night_palette = true


	func script_set_palette(num: int, night: bool) -> void:
		_inc("palette")
		PALState.palette = num
		PALState.night_palette = night


	func script_screen_wave(level: int, progression: int) -> void:
		_inc("wave")
		PALState.screen_wave = level
		PALState.wave_progression = progression


	func set_screen_wave(level: int, progression: int) -> void:
		script_screen_wave(level, progression)


	func script_shake_screen(_times: int, _level: int) -> void:
		_inc("shake")


	func shake_screen(_times: int) -> void:
		_inc("shake")


	func script_color_fade(_color_index: int, _speed: int, _unknown: int) -> void:
		_inc("fades")


	func script_scene_fade(_palette: int, night: bool, _speed: int) -> void:
		_inc("fades")
		PALState.night_palette = night


	func request_picture(_num: int, _frames: int) -> void:
		_inc("pictures")


	func request_scroll_picture(_num: int, _a1: int, _a2: int) -> void:
		_inc("pictures")


	func request_picture_sprite(_num: int, _a1: int, _a2: int) -> void:
		_inc("pictures")


	func script_clear_screen() -> void:
		_inc("pictures")


	func script_backup_screen() -> void:
		_inc("backup")


	func request_ending() -> void:
		_inc("ending")


	func request_quit_game() -> void:
		_inc("ending")


	func script_end_game() -> void:
		_inc("ending")


	func script_change_battlefield(battlefield: int) -> void:
		_inc("battlefield")
		PALState.battle_field = battlefield


	func script_force_redraw() -> void:
		pass


	# ---- 交互（异步：由 sweep 主循环立刻 resume）
	func request_confirm() -> void:
		_inc("choices")


	func request_wait_key() -> void:
		_inc("keys")


	func request_load_game() -> void:
		_inc("load_game")


	func request_battle(team_id: int, flee_disabled: bool = false, force_win: bool = false) -> void:
		_inc("battles")
		if battles.size() < 20:
			battles.append([team_id, flee_disabled, force_win])
		PALState.in_battle = true


	func request_shop(store_id: int, is_buy: bool = true) -> void:
		_inc("shops")
		if shops.size() < 20:
			shops.append([store_id, is_buy])


	func script_shop(store_id: int) -> void:
		_inc("shops")
		if shops.size() < 20:
			shops.append([store_id, true])


	func request_rng(rng_id: int) -> void:
		_inc("rngs")
		if rngs.size() < 20:
			rngs.append(rng_id)


	func request_rng_full(rng_id: int, start_frame: int, frames: int, speed: int) -> void:
		_inc("rngs")
		if rngs.size() < 20:
			rngs.append([rng_id, start_frame, frames, speed])


	func open_menu(kind: String) -> void:
		_inc("menu_open")
		if shops.size() < 20:
			shops.append([kind, true])


	func on_menu_closed() -> void:
		pass


	func reload_map() -> void:
		_inc("reload_map")


	# ---- 脚本同步执行（PALState.script_runner / 0x0004 自动脚本）
	func run_script_entry(entry: int) -> bool:
		if entry == 0:
			return false
		run_script_entry_sync(entry, 0xFFFF)
		return true


	func run_script_entry_sync(entry: int, evt_id: int = 0xFFFF) -> void:
		if entry == 0:
			return
		var tmp := ScriptVM.new()
		tmp.setup(sss, self)
		drive(tmp, entry, evt_id, 600)


	# ---- 每帧驱动（与 world._process 的等待处理同构）
	func drive(vm: ScriptVM, entry: int, evt_id: int, cap: int) -> Dictionary:
		vm.start(entry, evt_id)
		var frames := 0
		while vm.is_active() and frames < cap:
			vm.tick()
			if vm.waiting_dialog:
				vm.advance_dialog()
			elif vm.waiting_battle:
				vm.resume_battle("won")
				PALState.in_battle = false
			elif vm.waiting_menu:
				vm.resume_menu()
			elif vm.waiting_rng:
				vm.resume_rng()
			elif vm.waiting_choice:
				vm.resume_choice(true)
			elif vm.waiting_key:
				vm.resume_key()
			frames += 1
		var cap_hit := vm.is_active()
		if cap_hit:
			vm.cancel()
		return {"frames": frames, "cap_hit": cap_hit, "report": vm.get_report()}


	func _clamp_viewport() -> void:
		var max_x: int = maxi(0, 2048 - 320)
		var max_y: int = maxi(0, 2048 - 200)
		PALState.viewport.x = clampi(PALState.viewport.x, 0, max_x)
		PALState.viewport.y = clampi(PALState.viewport.y, 0, max_y)


	func abs_party() -> Vector2i:
		if PALState.party.is_empty():
			return PALState.viewport
		var p: Dictionary = PALState.party[0]
		return PALState.viewport + Vector2i(int(p["x"]), int(p["y"]))


	func script_note_unknown(_op: int, _at: int) -> void:
		pass


# ================================================================== 压测主体

func run_all() -> void:
	var t0 := Time.get_ticks_msec()
	sss = PALTables.sss
	PALState.tables = PALTables
	PALState.data = sss
	PALState.reset_defaults()
	# 快照初始 SCENE / EVENTOBJECT 表：脚本会原地修改它们（0x006D/0x0099/0x0049…），
	# 每场景压测前恢复，保证 295 个场景各自从初始数据状态起跑（可重复、互不污染）。
	scene_snapshot = []
	for sc in sss.scenes:
		scene_snapshot.append((sc as Array).duplicate())
	event_snapshot = []
	for eo in sss.events:
		event_snapshot.append((eo as Array).duplicate())
	# 初始队伍与真实开局一致：role 0 单人
	PALState.max_party_member_index = 0
	for i in range(PALState.party.size()):
		PALState.party[i]["role"] = 0
		PALState.party[i]["x"] = 160
		PALState.party[i]["y"] = 112
		PALState.party[i]["frame"] = 0
	mock = MockWorld.new()
	mock.sss = sss
	mock.reset_counts()
	PALState.script_runner = Callable(mock, "run_script_entry_sync")

	_sweep_scene_entries()
	_sweep_trigger_scripts()
	_sweep_auto_scripts()

	var elapsed := Time.get_ticks_msec() - t0
	var auto_caps := 0
	var auto_cycles := 0
	var trigger_caps := 0
	for r in auto_rows:
		auto_caps += int(r.get("caps", 0))
		auto_cycles += int(r.get("cycles", 0))
	for r in trigger_rows:
		trigger_caps += int(r.get("caps", 0))
	var result := {
		"generated_by": "tools/vm_scene_sweep.gd",
		"settings": {
			"scenes": SCENE_COUNT,
			"max_frames_scene": MAX_FRAMES_SCENE,
			"max_frames_trigger": MAX_FRAMES_TRIGGER,
			"auto_steps": AUTO_STEPS,
		},
		"summary": {
			"elapsed_ms": elapsed,
			"scene_rows": scene_rows.size(),
			"scene_entries": scene_entry_count,
			"trigger_rows": trigger_rows.size(),
			"trigger_scripts": trigger_script_count,
			"auto_scripts": auto_script_count,
			"unknown_ops": unknown_ops,
			"missing_hooks": missing_hooks,
			"script_cap_hits": cap_hits.size(),
			"script_cap_samples": cap_hits.slice(0, 40),
			"trigger_cap_rows": trigger_caps,
			"auto_cap_scripts": auto_caps,
			"auto_cycles": auto_cycles,
			"sanity_issues": sanity_issues,
			"dialog_samples": dialog_samples.slice(0, 20),
			"interactions": interactions,
			"fail": (unknown_ops.size() > 0 or sanity_issues.size() > 0 or missing_hooks.size() > 0),
		},
		"scene_rows": scene_rows,
		"trigger_rows": trigger_rows,
		"auto_rows": auto_rows,
	}
	_write_json(result)
	_print_summary(result)


func _scene_range(n: int) -> Array[int]:
	var start_i := 0
	if n - 1 >= 0 and n - 1 < sss.scenes.size():
		start_i = int(sss.scenes[n - 1][PalData.SC_EVENT_START])
	var end_i := sss.events.size()
	if n >= 0 and n < sss.scenes.size():
		end_i = int(sss.scenes[n][PalData.SC_EVENT_START])
	return [start_i, end_i]


func _prepare_scene(n: int) -> void:
	PALState.scene = n
	PALState.in_battle = false
	# 恢复 SCENE 表 + 本场景事件对象到初始状态（隔离各场景）
	for i in range(sss.scenes.size()):
		if i < scene_snapshot.size():
			var src: Array = scene_snapshot[i]
			var dst: Array = sss.scenes[i]
			for k in range(mini(4, mini(src.size(), dst.size()))):
				dst[k] = src[k]
	var r := _scene_range(n)
	for id in range(maxi(1, r[0] + 1), mini(r[1], sss.events.size()) + 1):
		if id - 1 < event_snapshot.size():
			var src_e: Array = event_snapshot[id - 1]
			var dst_e: Array = sss.events[id - 1]
			for k in range(mini(16, mini(src_e.size(), dst_e.size()))):
				dst_e[k] = src_e[k]
	mock.evt_start = r[0]
	mock.evt_end = r[1]
	mock.current_map = MockMap.new()
	mock.current_map.map_index = int(sss.scene(n)[PalData.SC_MAP])


## 1) 295 场景 × onEnter/onTeleport
func _sweep_scene_entries() -> void:
	for n in range(1, SCENE_COUNT + 1):
		if n - 1 >= sss.scenes.size():
			break
		_prepare_scene(n)
		var sc := sss.scene(n)
		# 先快照两个入口地址：onEnter 脚本可能用 0x006D 改写本场景的 onTeleport
		var entries: Array = [
			["onEnter", int(sc[PalData.SC_SCRIPT_ON_ENTER])],
			["onTeleport", int(sc[PalData.SC_SCRIPT_ON_TELEPORT])],
		]
		var row := {"scene": n, "entries": [], "status": "no_script", "issues": []}
		for kind in entries:
			var entry := int(kind[1])
			if entry == 0:
				continue
			var r := _run_entry(n, str(kind[0]), entry, 0xFFFF, MAX_FRAMES_SCENE)
			row["entries"].append(r)
			row["status"] = "ran"
			scene_entry_count += 1
		if row["entries"].is_empty():
			row["status"] = "no_script"
		scene_rows.append(row)
		# 场景间对白样本（前 30 个）
		for d in mock.dialogs:
			if dialog_samples.size() < 30:
				dialog_samples.append([n, d[0], d[1]])
			break
		mock.reset_counts()
		_sanity_check("scene:%d" % n, row["issues"])


## 2) 每场景事件对象的触发脚本（state>0 才有意义，仍全部跑一遍）
func _sweep_trigger_scripts() -> void:
	for n in range(1, SCENE_COUNT + 1):
		if n - 1 >= sss.scenes.size():
			break
		_prepare_scene(n)
		var r := _scene_range(n)
		var row := {"scene": n, "scripts": 0, "status": "ran", "unknown": {}, "sample": [], "caps": 0}
		for id in range(maxi(1, r[0] + 1), mini(r[1], sss.events.size()) + 1):
			var eo: Array = sss.event(id)
			var entry := int(eo[PalData.EO_TRIGGER_SCRIPT])
			if entry == 0:
				continue
			var res := _run_entry(n, "trigger#%d" % id, entry, id, MAX_FRAMES_TRIGGER)
			row["scripts"] += 1
			trigger_script_count += 1
			record_aggregate(res, row)
			if res["cap_hit"]:
				row["caps"] += 1
			if row["sample"].size() < 10:
				row["sample"].append([id, int(res["frames"]), res["cap_hit"], int(res["ip"])])
		if row["scripts"] == 0:
			row["status"] = "no_script"
		trigger_rows.append(row)
		mock.reset_counts()


## 3) 每场景事件对象的自动脚本（每帧一条指令）
func _sweep_auto_scripts() -> void:
	for n in range(1, SCENE_COUNT + 1):
		if n - 1 >= sss.scenes.size():
			break
		_prepare_scene(n)
		var vm := ScriptVM.new()
		vm.setup(sss, mock)
		var r := _scene_range(n)
		var row := {"scene": n, "scripts": 0, "steps": 0, "status": "ran", "unknown": {}, "caps": 0, "cycles": 0, "cap_entries": []}
		for id in range(maxi(1, r[0] + 1), mini(r[1], sss.events.size()) + 1):
			var eo: Array = sss.event(id)
			var entry := int(eo[PalData.EO_AUTO_SCRIPT])
			if entry == 0:
				continue
			row["scripts"] += 1
			auto_script_count += 1
			var cur := entry
			var steps := 0
			var seen := {}
			for k in range(AUTO_STEPS):
				if seen.has(cur):
					# 自动脚本的「每帧一条指令」循环（如 0x000F→0x0002 回跳）是正常动画，不是卡死
					row["cycles"] += 1
					break
				seen[cur] = true
				var nxt := vm.run_auto(cur, id)
				steps += 1
				row["steps"] += 1
				if nxt == cur:
					break
				if nxt <= 0:
					break
				cur = nxt
			if steps >= AUTO_STEPS:
				row["caps"] += 1
				if row["cap_entries"].size() < 10:
					row["cap_entries"].append([id, entry, steps])
		if row["scripts"] == 0:
			row["status"] = "no_script"
		var rep := vm.get_report()
		row["unknown"] = rep.get("unknown_ops", {})
		_merge_dict(unknown_ops, row["unknown"])
		_merge_dict(missing_hooks, rep.get("missing_hooks", {}))
		_collect_interactions()
		auto_rows.append(row)
		mock.reset_counts()


# ------------------------------------------------------------------ 单段脚本

func _run_entry(n: int, kind: String, entry: int, evt_id: int, cap: int) -> Dictionary:
	var vm := ScriptVM.new()
	vm.setup(sss, mock)
	mock.reset_counts()
	var driven: Dictionary = mock.drive(vm, entry, evt_id, cap)
	var rep: Dictionary = driven["report"]
	_merge_dict(unknown_ops, rep.get("unknown_ops", {}))
	_merge_dict(missing_hooks, rep.get("missing_hooks", {}))
	if driven["cap_hit"]:
		cap_hits.append([kind, n, entry, int(driven["frames"]), int(rep.get("ip", 0))])
	var row := {
		"kind": kind,
		"entry": entry,
		"frames": int(driven["frames"]),
		"cap_hit": driven["cap_hit"],
		"ip": int(rep.get("ip", 0)),
		"ended": bool(rep.get("ended", false)),
		"script_success": bool(rep.get("script_success", true)),
		"unknown_ops": rep.get("unknown_ops", {}),
		"missing_hooks": rep.get("missing_hooks", {}),
		"scene_changes": mock.scene_changes.duplicate(),
		"counts": mock.counts.duplicate(),
	}
	_collect_interactions()
	return row


## 把 MockWorld 采样的交互类调用并入全局样本（最多各存 100 条）。
func _collect_interactions() -> void:
	var mapping := {
		"battles": mock.battles,
		"shops": mock.shops,
		"rngs": mock.rngs,
		"scene_changes": mock.scene_changes,
	}
	for key in mapping.keys():
		var dst: Array = interactions[key]
		for v in (mapping[key] as Array):
			if dst.size() >= 100:
				break
			dst.append(v)


func record_aggregate(res: Dictionary, row: Dictionary) -> void:
	_merge_dict(unknown_ops, res["unknown_ops"])
	_merge_dict(missing_hooks, res["missing_hooks"])
	for k in (res["unknown_ops"] as Dictionary).keys():
		row["unknown"][k] = int(row["unknown"].get(k, 0)) + int(res["unknown_ops"][k])


func _merge_dict(dst: Dictionary, src: Variant) -> void:
	if not (src is Dictionary):
		return
	for k in src.keys():
		dst[k] = int(dst.get(k, 0)) + int(src[k])


# ------------------------------------------------------------------ 不变量检查

func _sanity_check(tag: String, issues: Array) -> void:
	var add := func(key: String, detail: String) -> void:
		if not issues.has(key):
			issues.append(key)
		if not sanity_issues.has(key):
			sanity_issues[key] = {"examples": []}
		var ex: Array = sanity_issues[key]["examples"]
		if ex.size() < 12:
			ex.append("%s %s" % [tag, detail])

	if PALState.scene < 1 or PALState.scene > SCENE_COUNT:
		add.call("scene_out_of_range", str(PALState.scene))
	if PALState.max_party_member_index < 0 or PALState.max_party_member_index > 4:
		add.call("party_index_out_of_range", str(PALState.max_party_member_index))
	if PALState.party.size() != 5:
		add.call("party_size", str(PALState.party.size()))
	if PALState.trail.size() != 5:
		add.call("trail_size", str(PALState.trail.size()))
	for i in range(PALState.party.size()):
		var role := int(PALState.party[i].get("role", 0))
		if role < 0 or role >= 6:
			add.call("party_role_out_of_range", "i=%d role=%d" % [i, role])
	for key in ["hp", "max_hp", "mp", "max_mp", "level", "equipment", "magic"]:
		if not PALState.roles.has(key):
			add.call("roles_missing_key", key)
		elif (PALState.roles[key] as Array).size() < 6:
			add.call("roles_short_array", "%s size=%d" % [key, (PALState.roles[key] as Array).size()])
	for i in range(mini(PALState.inventory.size(), 256)):
		var slot: Dictionary = PALState.inventory[i]
		if int(slot.get("amount", 0)) < 0:
			add.call("inventory_negative", "i=%d" % i)
	if PALState.viewport.x < -4096 or PALState.viewport.x > 8192:
		add.call("viewport_x_absurd", str(PALState.viewport.x))
	if PALState.viewport.y < -4096 or PALState.viewport.y > 8192:
		add.call("viewport_y_absurd", str(PALState.viewport.y))


# ------------------------------------------------------------------ 输出

func _write_json(result: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(OUT_PATH.get_base_dir())
	var fa := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if fa == null:
		push_error("vm_sweep: 无法写入 %s" % OUT_PATH)
		return
	fa.store_string(JSON.stringify(result, " "))
	fa.close()


func _print_summary(result: Dictionary) -> void:
	var s: Dictionary = result["summary"]
	print("[vm_sweep] ===================================================")
	print("[vm_sweep] 场景 %d 个 / onEnter+onTeleport 脚本 %d 段 / 触发脚本 %d 段 / 自动脚本 %d 个 / 耗时 %dms"
		% [s["scene_rows"], s["scene_entries"], s["trigger_scripts"], s["auto_scripts"], s["elapsed_ms"]])
	print("[vm_sweep] UNKNOWN_OPS: ", s["unknown_ops"])
	print("[vm_sweep] MISSING_HOOKS: ", s["missing_hooks"])
	print("[vm_sweep] 脚本帧上限命中 %d 段 / 触发脚本帧上限 %d 段 / 自动脚本帧上限 %d 个（动画循环 %d 个）"
		% [int(s["script_cap_hits"]), int(s["trigger_cap_rows"]),
		   int(s["auto_cap_scripts"]), int(s["auto_cycles"])])
	if s["script_cap_samples"].size() > 0:
		print("[vm_sweep]   脚本帧上限样例: ", s["script_cap_samples"])
	var issues: Dictionary = s["sanity_issues"]
	print("[vm_sweep] 不变量问题: ", issues.keys())
	if issues.size() > 0:
		print("[vm_sweep]   详情: ", JSON.stringify(issues).substr(0, 1200))
	var it: Dictionary = s["interactions"]
	print("[vm_sweep] 交互样本: 战斗=%d 商店=%d RNG=%d 切场景=%d"
		% [(it["battles"] as Array).size(), (it["shops"] as Array).size(),
		   (it["rngs"] as Array).size(), (it["scene_changes"] as Array).size()])
	print("[vm_sweep] 输出: ", OUT_PATH)
	var ok: bool = not s["fail"]
	print("[vm_sweep] ", "PASS" if ok else "FAIL")
	# 收尾：恢复全局状态，避免 world.sys_init 继续执行时用压测残留的场景号；释放 mock
	PALState.scene = 1
	PALState.in_battle = false
	PALState.viewport = Vector2i(0, 0)
	if mock != null:
		mock.free()
		mock = null
	var loop := Engine.get_main_loop()
	if loop != null:
		loop.quit(0 if ok else 1)
