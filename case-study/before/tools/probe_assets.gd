extends SceneTree
## 资源层自检：REA 证据落地验证（MKF 容器 / YJ2 解压 / MAP 预渲染 / MGO 精灵 / SSS 表 / 对白）。
## 运行：Godot_console.exe --headless --path <proj> --script res://tools/probe_assets.gd

const OUT_DIR := "<LOCAL_PATH>"


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var dir := PalConfig.require_data_dir()
	print("[probe] data_dir = ", dir)
	if dir == "":
		quit(1)
		return

	var sss := MkfFile.open_asset(dir, "Sss.mkf")
	print("[probe] Sss.mkf chunks=", sss.chunk_count, " sizes=", _chunk_sizes(sss))
	var map_mkf := MkfFile.open_asset(dir, "Map.mkf")
	var gop_mkf := MkfFile.open_asset(dir, "Gop.mkf")
	var mgo_mkf := MkfFile.open_asset(dir, "Mgo.mkf")
	var pat := MkfFile.open_asset(dir, "Pat.mkf")
	print("[probe] Map chunks=", map_mkf.chunk_count, " Gop chunks=", gop_mkf.chunk_count,
		" Mgo chunks=", mgo_mkf.chunk_count, " Pat chunks=", pat.chunk_count)

	var m1 := map_mkf.decompressed(1)
	print("[probe] Map chunk1 decompressed = ", m1.size(), " (expect 65536)")

	var data := PalData.new()
	var ok := data.load_all(dir)
	print("[probe] PalData.load_all = ", ok, " scenes=", data.scenes.size(),
		" events=", data.events.size(), " script_words=", data.scripts.size(),
		" msg_offsets=", data.msg_offsets.size(), " msgs=", data.msgs.size())
	print("[probe] msg[0] = ", data.msg(0))

	var pal := PalMap.load_palette(pat, 0)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for mi in [20, 12]:
		var t1 := Time.get_ticks_msec()
		var m := PalMap.load_map(map_mkf, gop_mkf, mi, pal)
		if m == null:
			print("[probe] map ", mi, " LOAD FAILED")
			continue
		print("[probe] map ", mi, " tiles=", m.tile_frames.size(), " load_ms=", Time.get_ticks_msec() - t1)
		m.bottom.save_png(OUT_DIR + "map_%d_bottom.png" % mi)
		m.layer_top.save_png(OUT_DIR + "map_%d_top.png" % mi)

	for sn in [2, 3, 193]:
		if sn < mgo_mkf.chunk_count:
			var raw := mgo_mkf.decompressed(sn)
			var frames := PalSprite.decode_sprite(raw, pal)
			var dims := ""
			for f in frames:
				dims += "%dx%d " % [f.get_width(), f.get_height()]
			print("[probe] MGO ", sn, " bytes=", raw.size(), " frames=", frames.size(), " dims=", dims)
			if frames.size() > 0:
				_save_sheet(frames, OUT_DIR + "mgo_%d.png" % sn)
	print("[probe] total_ms=", Time.get_ticks_msec() - t0)
	quit(0)


func _chunk_sizes(m: MkfFile) -> String:
	var s := ""
	for i in range(m.chunk_count):
		s += "%d " % (m.offsets[i + 1] - m.offsets[i])
	return s


func _save_sheet(frames: Array[Image], path: String) -> void:
	var w := 0
	var h := 0
	for f in frames:
		w = maxi(w, f.get_width())
		h = maxi(h, f.get_height())
	var cols := 6
	var rows := (frames.size() + cols - 1) / cols
	var sheet := Image.create_empty(cols * w, rows * h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.1, 0.1, 0.1, 1))
	for i in range(frames.size()):
		var f: Image = frames[i]
		sheet.blend_rect(f, Rect2i(0, 0, f.get_width(), f.get_height()),
			Vector2i((i % cols) * w, (i / cols) * h))
	sheet.save_png(path)
