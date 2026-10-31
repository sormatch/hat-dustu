# Açılıştan kare dizisi: gerçek akış (yukleyici.tscn: GIF -> sabit son kare altında kurulum -> perde kalkar) farklı
# en-boy oranlarında (--resolution) denetim için.
# Kullanım: Godot --path . --resolution 1560x720 --script res://tools/acilis_kare.gd -- server=ws://127.0.0.1:8794 profil=acilistest kademeli=1 ad=19x9 klasor=build/mobil/acilis
# Anlar (anlar=0.0,0.3,...): GIF saati (sn). Ek olarak "tut" (GIF bitti, kurulum sürerken sabit son kare) ve "kalk"
# (perde solarken) kareleri ve 1 sn sonra menü alınır.
extends SceneTree

var args := {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var dir := str(args.get("klasor", "build/mobil/acilis"))
	DirAccess.make_dir_recursive_absolute(dir)
	var ad := str(args.get("ad", "x"))
	var t0 := Time.get_ticks_msec()
	var yuk: Node = load("res://yukleyici.tscn").instantiate()
	root.add_child(yuk)
	current_scene = yuk
	var perde: Node = yuk.get("perde")
	var anlar: Array = [0.0, 0.2, 0.5, 0.9, 1.1, 1.3, 1.5, 1.75, 2.1, 2.29]
	if args.has("anlar"):
		anlar = Array(str(args.anlar).split(",")).map(func(s: String) -> float: return s.to_float())
	var i := 0
	var tut := false
	var kalk := false
	while Time.get_ticks_msec() - t0 < 90000 and is_instance_valid(perde):
		await process_frame
		var dosya := ""
		if i < anlar.size() and float(perde.get("saat")) >= float(anlar[i]) and not perde.get("gif_bitti"):
			dosya = "%s_%02d_t%.2f_k%d.png" % [ad, i, float(perde.get("saat")), int(perde.get("gosterilen"))]
			i += 1
		elif not tut and perde.get("gif_bitti"):
			tut = true
			dosya = "%s_tut.png" % ad
		elif tut and not kalk and perde.get("_kalkiyor") and perde.get("_kok").modulate.a < 0.7:
			kalk = true
			dosya = "%s_kalk.png" % ad
		if dosya != "":
			await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_png(dir.path_join(dosya))
		if kalk:
			break
	await create_timer(1.0).timeout
	root.get_viewport().get_texture().get_image().save_png(dir.path_join("%s_menu.png" % ad))
	quit()
