# Mağaza küçük resimlerini (scripts/thumbs.gd) dosyaya döker: verilen eşyalar için tek tek üretip bir ızgarada birleştirir.
# Kullanım (görüntü gerekir, --headless değil):
#   Godot --path . --script res://tools/kucuk_resim_cek.gd -- esyalar=sapka:korsan,aksesuar:canta,... cikti=build/x.png [govde=kadin] [sutun=6]
extends SceneTree

const Thumbs := preload("res://scripts/thumbs.gd")
const Catalog := preload("res://scripts/catalog.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var items: Array = str(args.get("esyalar", "")).split(",", false)
	var look := Catalog.sanitize({"govde": args.get("govde", "erkek"), "sac": args.get("sac", "kisa"), "ten": int(args.get("ten", "1")), "sac_renk": int(args.get("sac_renk", "0"))})
	var th: Node = Thumbs.new()
	root.add_child(th)
	var cols := int(args.get("sutun", "6"))
	var cell := 256
	var rows := ceili(items.size() / float(cols))
	var out := Image.create(cols * cell, rows * cell, false, Image.FORMAT_RGBA8)
	out.fill(Color("#2a2d36"))
	for i in items.size():
		var p: PackedStringArray = str(items[i]).split(":")
		var tex: Texture2D = await th._render(look, p[0], p[1])
		var img := tex.get_image()
		img.convert(Image.FORMAT_RGBA8)
		out.blend_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i((i % cols) * cell, (i / cols) * cell))
		print(items[i], " tamam")
	var path := str(args.get("cikti", "build/kucuk_resimler.png"))
	print("kayit ", path, " -> ", out.save_png(path))
	quit()
