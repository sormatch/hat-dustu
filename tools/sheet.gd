# Bir kerelik araç: klasördeki tüm PNG'leri dama arka planlı tek bir özet resimde toplar.
extends SceneTree

func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1]
	var dir: String = args.klasor
	var files := Array(DirAccess.get_files_at(dir)).filter(func(f: String) -> bool: return f.ends_with(".png"))
	files.sort()
	var tile := 180
	var cols := 8
	var rows := ceili(files.size() / float(cols))
	var out := Image.create(cols * tile, rows * tile, false, Image.FORMAT_RGBA8)
	for y in out.get_height():
		for x in out.get_width():
			out.set_pixel(x, y, Color(0.35, 0.35, 0.38) if ((x / 12 + y / 12) % 2 == 0) else Color(0.5, 0.5, 0.53))
	var sizes := []
	for i in files.size():
		var img := Image.load_from_file(dir + "/" + files[i])
		img.convert(Image.FORMAT_RGBA8)
		sizes.append("%d:%s %dx%d" % [i, files[i].get_basename(), img.get_width(), img.get_height()])
		var sc := minf(float(tile - 8) / img.get_width(), float(tile - 8) / img.get_height())
		img.resize(maxi(1, int(img.get_width() * sc)), maxi(1, int(img.get_height() * sc)))
		var px := (i % cols) * tile + (tile - img.get_width()) / 2
		var py := (i / cols) * tile + (tile - img.get_height()) / 2
		out.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(px, py))
	print(", ".join(sizes))
	out.save_png(args.cikti)
	quit()
