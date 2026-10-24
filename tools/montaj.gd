# Bir kerelik araç: verilen resimleri gri zemin üstünde ızgara halinde tek resme dizer.
extends SceneTree
func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1]
	var files: PackedStringArray = str(args.dosyalar).split(",")
	var cell := 160
	var cols := 8
	var rows := int(ceil(files.size() / float(cols)))
	var out := Image.create(cols * cell, rows * cell, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.35, 0.36, 0.4))
	for i in files.size():
		var img := Image.load_from_file(ProjectSettings.globalize_path(files[i]))
		img.convert(Image.FORMAT_RGBA8)
		var s := (cell - 10.0) / maxf(img.get_width(), img.get_height())
		img.resize(maxi(1, int(img.get_width() * s)), maxi(1, int(img.get_height() * s)))
		var at := Vector2i((i % cols) * cell + (cell - img.get_width()) / 2, (i / cols) * cell + (cell - img.get_height()) / 2)
		out.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), at)
	out.save_png(args.cikti)
	quit()
