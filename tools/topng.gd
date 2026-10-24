# Bir kerelik araç: resmi küçültüp PNG olarak kaydeder (webp önizlemesi için).
extends SceneTree

func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1]
	var img := Image.load_from_file(args.giris)
	print(img.get_size())
	img.resize(int(args.get("w", "384")), int(int(args.get("w", "384")) * img.get_height() / float(img.get_width())))
	var bg := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	bg.fill(Color(0.85, 0.85, 0.85))
	bg.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
	bg.save_png(args.cikti)
	quit()
