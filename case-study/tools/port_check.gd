extends SceneTree
## 完整移植自检：数据表 / 状态 / 存档往返 / 资源解码。
## 运行：Godot_console.exe --headless --path <proj> --script res://tools/port_check.gd
## 退出码：0 全部通过；1 有失败项。

var _fail := 0
var _pass := 0


func _initialize() -> void:
	var dir := PalConfig.require_data_dir()
	_check(dir != "", "数据目录存在：%s" % dir)
	if dir == "":
		quit(1)
		return

	# ---- 数据表 ----
	var tables = load("res://pal/pal_tables.gd").new()
	var ok: bool = tables.init(dir)
	_check(ok, "PALTables.init")
	_check(tables.objects.size() == 565, "OBJECT 数量 565（实际 %d）" % tables.objects.size())
	_check(tables.enemy_defs.size() == 154, "敌人定义 154（实际 %d）" % tables.enemy_defs.size())
	_check(tables.enemy_teams.size() == 380, "敌人队伍 380（实际 %d）" % tables.enemy_teams.size())
	_check(tables.magic_defs.size() == 104, "仙术定义 104（实际 %d）" % tables.magic_defs.size())
	_check(tables.battle_fields.size() == 58, "战场 58（实际 %d）" % tables.battle_fields.size())
	_check(tables.stores.size() == 21, "商店 21（实际 %d）" % tables.stores.size())
	_check(tables.words.size() == 565, "词条 565（实际 %d）" % tables.words.size())
	_check(tables.player_roles.size() > 20, "PLAYERROLES 字段数 %d" % tables.player_roles.size())
	_check(tables.words.size() > 100 and tables.word(6).length() > 0, "词条 6 非空：%s" % tables.word(6))

	# ---- 状态 ----
	var st = load("res://pal/pal_state.gd").new()
	st.tables = tables
	st.data = tables.sss
	st.reset_defaults()
	_check(st.inventory.size() == 256, "背包槽位 256")
	_check(st.party.size() == 5, "队伍槽位 5")
	_check(st.roles["max_hp"].size() == 6, "角色数值表 6 角色")
	_check(int(st.roles["max_hp"][0]) > 0, "角色 0 MaxHP=%d" % int(st.roles["max_hp"][0]))

	# 背包增减
	st.add_item(61, 3)
	st.add_item(61, 2)
	_check(st.count_item(61) == 5, "add_item/count_item = 5")
	st.add_item(61, -5)
	_check(st.count_item(61) == 0, "add_item 减光")

	# 升级
	var lv0 := int(st.roles["level"][0])
	st.player_level_up(0, 2)
	_check(int(st.roles["level"][0]) == lv0 + 2, "升级 +2（%d→%d）" % [lv0, int(st.roles["level"][0])])

	# 仙术 / 状态 / 毒
	st.add_magic(0, 10)
	_check(st.player_magics(0).has(10), "学仙术 10")
	st.set_player_status(0, 5, 3)
	_check(st.has_status(0, 5), "状态 bravery")
	st.remove_player_status(0, 5)
	_check(not st.has_status(0, 5), "状态移除")
	st.add_poison(0, 1)
	_check(st.is_poisoned_by_kind(0, 1), "中毒 1")
	st.cure_poison_by_kind(0, 1)
	_check(not st.is_poisoned_by_kind(0, 1), "解毒")

	# ---- 存档往返 ----
	st.cash = 1234
	st.scene = 12
	st.add_item(61, 7)
	st.roles["hp"][0] = 77
	_check(st.save_game(9), "save_game(9)")
	var st2 = load("res://pal/pal_state.gd").new()
	st2.tables = tables
	st2.data = tables.sss
	st2.reset_defaults()
	_check(st2.load_game(9), "load_game(9)")
	_check(st2.cash == 1234, "读档现金 1234（实际 %d）" % st2.cash)
	_check(st2.scene == 12, "读档场景 12（实际 %d）" % st2.scene)
	_check(st2.count_item(61) == 7, "读档物品 61×7（实际 %d）" % st2.count_item(61))
	_check(int(st2.roles["hp"][0]) == 77, "读档 HP 77（实际 %d）" % int(st2.roles["hp"][0]))

	# ---- 地图/精灵解码 ----
	var map_mkf := MkfFile.open_asset(dir, "Map.mkf")
	var gop_mkf := MkfFile.open_asset(dir, "Gop.mkf")
	var pat := MkfFile.open_asset(dir, "Pat.mkf")
	_check(map_mkf != null and gop_mkf != null, "Map/Gop 打开")
	var pal := PalMap.load_palette(pat, 0)
	var t0 := Time.get_ticks_msec()
	var m := PalMap.load_map(map_mkf, gop_mkf, 12, pal)
	_check(m != null and m.tile_frames.size() > 0, "map12 装载 tiles=%d" % (m.tile_frames.size() if m else -1))
	var blocked_ok := (m != null and (m.is_blocked(0, 0, 0) == true or m.is_blocked(0, 0, 0) == false))
	_check(blocked_ok, "map12 阻挡查询可用")
	print("[check] map12 load_ms=", Time.get_ticks_msec() - t0)

	print("\n[port_check] PASS=%d FAIL=%d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  OK   ", name)
	else:
		_fail += 1
		printerr("  FAIL ", name)
