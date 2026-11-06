extends SceneTree

## 诊断：用工程内的 PalMap 解码指定地图，输出帧数/像素统计并保存 PNG，与 python 参考渲染对比。
## 用法：--headless --path <proj> --script res://tools/probe_map.gd

const MkfFile = preload("res://pal/mkf.gd")
const PalMap = preload("res://pal/pal_map.gd")
const PalSprite = preload("res://pal/pal_sprite.gd")


func _init() -> void:
	var dir := _find_data_dir()
	if dir == "":
		print("[probe] data dir not found")
		quit(1)
		return
	var map_mkf = MkfFile.open_asset(dir, "Map.mkf")
	var gop_mkf = MkfFile.open_asset(dir, "Gop.mkf")
	var pat_mkf = MkfFile.open_asset(dir, "Pat.mkf")
	print("[probe] map chunks=", map_mkf.chunk_count, " gop chunks=", gop_mkf.chunk_count)
	var palette: PackedColorArray = PalMap.load_palette(pat_mkf, 0, false)
	print("[probe] palette[0..3]=", palette[0], palette[1], palette[2], palette[3])
	for map_id in [10, 12, 2, 6]:
		var gop: PackedByteArray = gop_mkf.chunk(map_id)
		var frames: Array = PalSprite.decode_sprite(gop, palette)
		var nonempty := 0
		for f in frames:
			if f == null:
				continue
			var im: Image = f
			var cnt := 0
			for yy in range(mini(im.get_height(), 16)):
				for xx in range(mini(im.get_width(), 32)):
					if im.get_pixel(xx, yy).a > 0.01:
						cnt += 1
			if cnt > 0:
				nonempty += 1
		print("[probe] map ", map_id, " gop_bytes=", gop.size(),
			" frames=", frames.size(), " nonempty=", nonempty)
		var mp = PalMap.load_map(map_mkf, gop_mkf, map_id, palette)
		if mp == null:
			print("[probe] map ", map_id, " load NULL")
			continue
		var img: Image = mp.bottom
		var used := 0
		var samples := []
		for yy in range(0, img.get_height(), 97):
			for xx in range(0, img.get_width(), 89):
				var c := img.get_pixel(xx, yy)
				if c.r + c.g + c.b > 0.02:
					used += 1
					if samples.size() < 4:
						samples.append(c)
		print("[probe] map ", map_id, " bottom=", img.get_size(),
			" colored_samples=", used, " sample=", samples)
		var out := "user://probe_map_%d.png" % map_id
		img.save_png(out)
		print("[probe] saved ", ProjectSettings.globalize_path(out))
	quit(0)


func _find_data_dir() -> String:
	var cands := [
		"<LOCAL_PATH>",
		"<LOCAL_PATH>",
	]
	for d in cands:
		if DirAccess.dir_exists_absolute(d) and FileAccess.file_exists(d + "/Map.mkf"):
			return d + "/"
	return ""
