# Bellek sızıntısı ölçümü: oyun sahnesi (hücre + koridorda 7 karakter + patlama + maç sonu) kurulur, silinir,
# yeniden kurulur (menüye dönüş = sahnenin yeniden yüklenmesi). Her turdan sonra düğüm/nesne/bellek sayıları
# yazılır; ilk turdan sonra sabit kalmalı (önbellekler bir kez dolar).
# Kullanım: Godot --path . --resolution 1280x720 --script res://tools/sizinti_olc.gd -- [tur=4]
extends SceneTree

const LOOKS := [
	{"govde": "erkek", "sac": "ayrik", "sakal": "dolgun", "aksesuar": "zincir"},
	{"govde": "kadin", "sac": "ikiz_orgu", "aksesuar": "kupe"},
	{"govde": "erkek", "sac": "rasta", "sakal": "keci", "aksesuar": "gunes"},
	{"govde": "kadin", "sac": "uzun_duz", "aksesuar": "inci"},
	{"govde": "erkek", "sac": "kisa", "sapka": "ters_kep", "dovme": "ejderha"},
	{"govde": "kadin", "sac": "kivircik", "aksesuar": "gozluk"},
	{"govde": "erkek", "sac": "mohawk", "sakal": "pala"},
]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var turns := int(args.get("tur", "4"))
	for t in turns:
		var main: Node = load("res://main.tscn").instantiate()
		root.add_child(main)
		current_scene = main
		await process_frame
		_yetim("acilis")
		main._start_solo()
		_yetim("solo")
		main.playing = true
		var base: Vector3 = Vector3(3.9, 0, main.cells[0].position.z + 3.0)
		main.cells[0].set_door(true, true)
		main.player.global_position = base
		for i in LOOKS.size():
			var id := 50 + i
			main.net.players.append({"id": id, "name": "Bot %d" % i, "cell": i, "g": LOOKS[i]})
			var p := base + Vector3((i % 2) * 1.1 - 0.55, 0, -2.0 - i * 1.6)
			main._on_remote_state(id, {"p": [p.x, p.z], "y": PI, "o": false})
		for i in 30:
			await process_frame
		_yetim("kalabalik")
		if args.get("patlama", "1") == "1":
			preload("res://scripts/modlar/props.gd").explosion(main, base + Vector3(0, 1, -3), 0.0)
		var ms = load("res://scripts/mac_sonu.gd").new()
		var tbl := []
		var pl := []
		for i in 4:
			tbl.append({"id": 50 + i, "name": "Bot %d" % i, "score": 30 - i * 5, "p": [3, 2, 1], "g": LOOKS[i]})
			pl.append({"id": 50 + i, "g": LOOKS[i]})
		ms.setup({"table": tbl, "oyunlar": [{"ad": "Kara Tahta"}, {"ad": "Rulet"}, {"ad": "C4"}], "winner": 50}, 50, pl)
		var katman := CanvasLayer.new()
		main.add_child(katman)
		if args.get("macsonu", "1") == "1":
			katman.add_child(ms)
		else:
			ms.free()
		for i in 180:
			await process_frame
		_yetim("macsonu")
		# menüye dönüş: sahne baştan yüklenir (main.gd reload_current_scene ile aynı)
		main.queue_free()
		for i in 10:
			await process_frame
		print("[sizinti] tur %d: dugum %d, nesne %d, yetim dugum %d, kaynak %d, bellek %.1f MB, vram %.0f MB, doku %.0f MB" % [t + 1,
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT),
			Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0])
		_onbellek()
		print("[sizinti]   kok baglanti: size_changed %d, node_added %d, process_frame %d" % [root.size_changed.get_connections().size(), node_added.get_connections().size(), process_frame.get_connections().size()])
	if args.has("yetim"):
		Node.print_orphan_nodes()
	quit()


func _yetim(an: String) -> void:
	if an == "acilis" and ClassDB.class_has_method("Node", "get_orphan_node_ids"):
		for id in Node.get_orphan_node_ids():
			var o := instance_from_id(id)
			if o is Label:
				print("[sizinti]   yetim Label: \"%s\" boyut %d %s" % [(o as Label).text, (o as Label).get_theme_font_size("font_size"), str((o as Label).get_meta_list())])
	print("[sizinti]   %s: yetim %d" % [an, Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)])


# Statik önbelleklerin boyu: tur başına büyüyen varsa sızıntı odur.
func _onbellek() -> void:
	var out := []
	for pair in [["ui", "_tex"], ["model_body", "_mask_cache"], ["model_body", "_band_cache"], ["model_body", "_parts"], ["model_body", "_ink"],
			["hair", "_real_mats"], ["hair", "_mats"], ["hair", "_gray_cache"], ["hair", "_profiles"], ["hair", "_beard_cache"], ["dunya", "_cache"],
			["thumbs", "_cache"], ["aksesuar", "_mats"], ["body", "_mat_cache"], ["telefon", "_mats"], ["telefon", "_snd"]]:
		var sc: GDScript = load("res://scripts/%s.gd" % pair[0])
		var d = sc.get(pair[1])
		out.append("%s.%s=%d" % [pair[0], pair[1], (d as Dictionary).size() if d is Dictionary else -1])
	print("[sizinti]   onbellek: ", " ".join(out))
