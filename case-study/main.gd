extends Control
## 入口：初始化全局数据 → 标题画面 → 游戏世界。
## 原版 main.c 开场流程：开场画面 → 标题菜单 → 新的故事 / 读档 / 结束游戏。

## 用懒加载而不是 preload：某个模块暂时编译失败时，其他调试入口（--battle-test/--menu-test）仍可用
const TITLE_SCRIPT_PATH := "res://game/title.gd"
const WORLD_SCRIPT_PATH := "res://game/world.gd"
const SHOT_DIR := "<LOCAL_PATH>"

var _title: Control = null
var _world: Node2D = null
var _boot_error: String = ""


func _ready() -> void:
	# 测试/自动化环境常出现“窗口置顶但没有键盘焦点”→ 方向键无效；主动请求前台
	DisplayServer.window_move_to_foreground()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_boot()
	if _boot_error != "":
		_show_error(_boot_error)
		return
	_show_title()
	if "--auto" in OS.get_cmdline_args():
		_auto_start()
	var bt := _cmdline_value("--battle-test")
	if bt != "":
		_run_battle_test(int(bt))
	var mt := _cmdline_value("--menu-test")
	if mt != "":
		_run_menu_test(mt)


func _cmdline_value(prefix: String) -> String:
	for a in OS.get_cmdline_args():
		if a.begins_with(prefix + "="):
			return a.substr(prefix.length() + 1)
		if a == prefix:
			return "1"
	return ""


## 战斗调试入口：--battle-test=<team_id>，跳过标题直接打一场
func _run_battle_test(team_id: int) -> void:
	if _title != null:
		_title.queue_free()
		_title = null
	if not ResourceLoader.exists("res://game/battle.gd"):
		push_error("Main: game/battle.gd 尚未就绪")
		get_tree().quit(1)
		return
	PALState.init_game_data(0)
	var b = load("res://game/battle.gd").new()
	b.setup(team_id, false, false)
	add_child(b)
	b.finished.connect(func(r: String) -> void:
		print("[battle-test] result=", r)
		get_tree().quit(0))


## 菜单调试入口：--menu-test[=item|magic|status|equip|save|shop]
func _run_menu_test(kind: String) -> void:
	if _title != null:
		_title.queue_free()
		_title = null
	if not ResourceLoader.exists("res://game/menu.gd"):
		push_error("Main: game/menu.gd 尚未就绪")
		get_tree().quit(1)
		return
	PALState.init_game_data(0)
	var m = load("res://game/menu.gd").new()
	m.setup(kind if kind != "1" else "main")
	m.closed.connect(func() -> void: get_tree().quit(0))
	add_child(m)


func _boot() -> void:
	var dir := PalConfig.require_data_dir()
	if dir == "":
		_boot_error = "未找到仙剑98数据目录"
		return
	if not PALTables.init(dir):
		_boot_error = "游戏数据表装载失败（Data.mkf/SSS.MKF）"
		return
	PALState.data = PALTables.sss
	PALState.reset_defaults()
	if PALText != null:
		PALText.init(dir)
	if PALAudio != null:
		PALAudio.init(dir)


func _show_error(msg: String) -> void:
	var l := Label.new()
	l.text = "启动失败：" + msg
	l.position = Vector2(20, 20)
	add_child(l)
	push_error("Main: " + msg)


func _auto_start() -> void:
	await get_tree().create_timer(0.6).timeout
	_capture("title")
	await get_tree().create_timer(0.2).timeout
	if "--auto-continue" in OS.get_cmdline_args() and FileAccess.file_exists(PALState.save_path(9)):
		print("[auto] CONTINUE from auto slot0")
		_start_game_load(9)
		return
	_start_game()


func _capture(tag: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var img := get_viewport().get_texture().get_image()
	if img != null:
		var path := SHOT_DIR + "auto_00_%s.png" % tag
		img.save_png(path)
		print("[auto] SHOT ", path)


func _show_title() -> void:
	var t := Control.new()
	t.name = "Title"
	t.set_script(load(TITLE_SCRIPT_PATH))
	add_child(t)
	_title = t
	t.connect("start_requested", Callable(self, "_start_game"))
	t.connect("load_requested", Callable(self, "_start_game_load"))
	t.connect("quit_requested", Callable(self, "_quit"))


func _start_game() -> void:
	PALState.init_game_data(0)
	_open_world()


func _start_game_load(slot: int) -> void:
	PALState.init_game_data(slot)
	_open_world()


func _open_world() -> void:
	if _title != null:
		_title.queue_free()
		_title = null
	if _world != null:
		_world.queue_free()
	var w := Node2D.new()
	w.name = "World"
	w.set_script(load(WORLD_SCRIPT_PATH))
	add_child(w)
	_world = w


func _quit() -> void:
	get_tree().quit()
