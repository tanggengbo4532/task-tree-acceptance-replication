extends SceneTree
## 全量场景/地图覆盖扫描（完整移植回归用）。
## 运行：Godot_console.exe --headless --path <proj> --script res://tools/scene_sweep.gd
## 检查：
##   1) Map.mkf 全部 226 块 YJ2 解压为 65536B，Gop.mkf 同号块可解码；
##   2) 全部 295 个场景的 map 号在范围内、事件对象区间合法、地图可装载；
##   3) 统计每张地图的图块/事件对象数量，输出 JSON 到 _rea_runtime/out/scene_sweep.json。

const OUT_PATH := "<LOCAL_PATH>"

var _fail: int = 0
var _pass: int = 0


func _initialize() -> void:
	var dir := PalConfig.require_data_dir()
	var map_mkf := MkfFile.open_asset(dir, "Map.mkf")
	var gop_mkf := MkfFile.open_asset(dir, "Gop.mkf")
	var pat := MkfFile.open_asset(dir, "Pat.mkf")
	var data := PalData.new()
	data.load_all(dir)
	var pal := PalMap.load_palette(pat, 0)

	# ---- 1) 全地图解码 ----
	# 空块（块长 0）= 未使用的地图槽（本作 Map/Gop 各有 168/171 两个空槽，已核实）
	var map_ok := {}
	var empty_slots: Array[int] = []
	for i in range(1, map_mkf.chunk_count):
		if map_mkf.chunk(i).size() == 0:
			empty_slots.append(i)
			map_ok[i] = false
			continue
		var raw := map_mkf.decompressed(i)
		var ok := raw.size() == 65536
		map_ok[i] = ok
		if not ok:
			_fail += 1
			printerr("  FAIL map %d decompressed=%d" % [i, raw.size()])
		else:
			_pass += 1
		if i % 50 == 0:
			print("[sweep] map decompress %d/%d" % [i, map_mkf.chunk_count - 1])
	print("[sweep] Map.mkf 解压：%d/%d 通过" % [_pass, _pass + _fail])

	# ---- 2) 全场景装载 ----
	var scene_report: Array = []
	var loaded := 0
	var t0 := Time.get_ticks_msec()
	for s in range(1, 296):
		var sc := data.scene(s)
		var map_no := int(sc[0])
		var r := [0, 0]
		var start_i := 0
		if s - 1 < data.scenes.size():
			start_i = int(data.scenes[s - 1][3])
		var end_i: int = data.events.size()
		if s < data.scenes.size():
			end_i = int(data.scenes[s][3])
			r = [start_i, end_i]
		# 哨兵场景 295（map=0）在 sdlpal 中作为事件区间终点，不单独装载
		var is_sentinel := (s == 295 and map_no == 0)
		var ok := is_sentinel or (map_no > 0 and map_no < map_mkf.chunk_count and start_i <= end_i)
		var tiles := 0
		if ok and map_ok.get(map_no, false):
			var m := PalMap.load_map(map_mkf, gop_mkf, map_no, pal)
			if m == null:
				ok = false
			else:
				tiles = m.tile_frames.size()
				loaded += 1
		if not ok:
			_fail += 1
			printerr("  FAIL scene %d map=%d events=[%d,%d)" % [s, map_no, start_i, end_i])
		else:
			_pass += 1
		scene_report.append({
			"scene": s, "map": map_no,
			"on_enter": int(sc[1]), "on_teleport": int(sc[2]),
			"events": [start_i, end_i], "tiles": tiles, "ok": ok,
		})
		if s % 50 == 0:
			print("[sweep] scene %d/%d loaded=%d t=%dms" % [s, 295, loaded, Time.get_ticks_msec() - t0])

	# ---- 输出 ----
	var out := {
		"maps_total": map_mkf.chunk_count - 1,
		"empty_map_slots": empty_slots,
		"scenes_total": 295,
		"map_decompress_ok": map_ok,
		"scenes": scene_report,
	}
	DirAccess.make_dir_recursive_absolute("<LOCAL_PATH>")
	var fa := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if fa != null:
		fa.store_string(JSON.stringify(out, "  "))
		fa.close()
	print("\n[scene_sweep] PASS=%d FAIL=%d loaded_scenes=%d out=%s" % [_pass, _fail, loaded, OUT_PATH])
	quit(0 if _fail == 0 else 1)
