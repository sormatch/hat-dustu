# Dikey görsellerden küçük montaj: Godot --headless --path . -s D:/HatDustu/magaza/araclar/dikey_montaj.gd -- klasor=<klasör> cikti=<png> [sutun=4] [gen=480]
extends SceneTree


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var klasor := str(args.get("klasor", ""))
	var dosyalar: Array = []
	for f in DirAccess.get_files_at(klasor):
		if f.ends_with(".png") or f.ends_with(".jpg"):
			dosyalar.append(klasor.path_join(f))
	dosyalar.sort()
	var sutun := int(args.get("sutun", "4"))
	var gen := int(args.get("gen", "480"))
	var pay := int(gen * 0.05)
	var ilk := Image.load_from_file(dosyalar[0])
	var yuk := int(float(gen) * ilk.get_height() / ilk.get_width())
	var satir := int(ceil(dosyalar.size() / float(sutun)))
	var out := Image.create(sutun * gen + (sutun + 1) * pay, satir * yuk + (satir + 1) * pay, false, Image.FORMAT_RGB8)
	out.fill(Color("#141716"))
	for i in dosyalar.size():
		var im := Image.load_from_file(dosyalar[i])
		im.convert(Image.FORMAT_RGB8)
		im.resize(gen, yuk, Image.INTERPOLATE_LANCZOS)
		out.blit_rect(im, Rect2i(0, 0, gen, yuk), Vector2i(pay + (i % sutun) * (gen + pay), pay + (i / sutun) * (yuk + pay)))
	out.save_png(str(args.get("cikti", "")))
	print("montaj ", out.get_size())
	quit()
