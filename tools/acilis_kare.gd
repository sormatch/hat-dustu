# Açılış animasyonundan kare dizisi: farklı en-boy oranlarında (--resolution) denetim için.
# Kullanım: Godot --path . --resolution 1560x720 --script res://tools/acilis_kare.gd -- server=ws://127.0.0.1:8794 profil=acilistest kademeli=1 ad=19x9 klasor=build/mobil/acilis
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
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var anlar: Array = [0.05, 0.6, 1.0, 1.2, 1.45, 2.2, 3.5, 6.0]
	if args.has("anlar"):  # ör. anlar=0.02,0.3,1.1 (animasyon saati, sn)
		anlar = Array(str(args.anlar).split(",")).map(func(s: String) -> float: return s.to_float())
	var i := 0
	while i < anlar.size():
		await process_frame
		var perde: Node = null
		for c in main.get_children():
			if c.get_script() == preload("res://scripts/acilis.gd"):
				perde = c
		var t: float = perde.get("_t") if perde else 99.0
		if t >= float(anlar[i]) or (perde == null and Time.get_ticks_msec() - t0 > 3000):
			await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_png(dir.path_join("%s_%02d_t%.2f.png" % [ad, i, t]))
			i += 1
		if Time.get_ticks_msec() - t0 > 30000:
			break
	quit()
