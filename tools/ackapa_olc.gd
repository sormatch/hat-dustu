# Sızıntı avı: bir ekran (mağaza / envanter / ayarlar) art arda açılıp kapatılır; her turda nesne, video belleği ve
# statik önbellek boyları yazılır. İlk turdan sonra sabit kalmalı.
# Kullanım: Godot --path . --resolution 1280x720 --script res://tools/ackapa_olc.gd -- server=ws://127.0.0.1:8794 profil=ackapatest [ekran=magaza|envanter] [tur=6] [sekme=1]
extends SceneTree


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	for i in 90:
		await process_frame
	var ekran := str(args.get("ekran", "magaza"))
	var prev := {}
	for t in int(args.get("tur", "6")):
		var ch: CanvasLayer = main.open_character() if ekran == "magaza" else main.open_inventory()
		for i in 40:
			await process_frame
		if args.get("sekme", "0") == "1" and ekran == "magaza":
			for c in ch.CATS:
				ch._select_cat(c)
				for i in 8:
					await process_frame
		if ekran == "magaza":
			ch._close(false)
		else:
			ch._close()
		for i in 40:
			await process_frame
		var objs := {}
		for n in root.find_children("*", "", true, false):
			objs[n.get_class()] = int(objs.get(n.get_class(), 0)) + 1
		var diff := []
		for k in objs:
			if prev.size() > 0 and int(objs[k]) != int(prev.get(k, 0)):
				diff.append("%s %+d" % [k, int(objs[k]) - int(prev.get(k, 0))])
		prev = objs
		print("[ackapa] tur %d: nesne %d, dugum %d, yetim %d, kaynak %d, vram %.1f MB, doku %.1f MB, bellek %.1f MB | %s" % [t + 1,
			Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0,
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, ", ".join(diff)])
		var out := []
		for pair in [["ui", "_tex"], ["model_body", "_mask_cache"], ["model_body", "_band_cache"], ["model_body", "_parts"], ["model_body", "_merge_cache"], ["model_body", "_ink"],
				["hair", "_real_mats"], ["hair", "_mats"], ["hair", "_gray_cache"], ["hair", "_extra_cache"], ["hair", "_beard_cache"], ["dunya", "_cache"],
				["thumbs", "_cache"], ["aksesuar", "_mats"], ["aksesuar", "_vcache"], ["body", "_mat_cache"]]:
			var sc: GDScript = load("res://scripts/%s.gd" % pair[0])
			var d = sc.get(pair[1])
			out.append("%s.%s=%d" % [pair[0], pair[1], (d as Dictionary).size() if d is Dictionary else -1])
		print("[ackapa]   ", " ".join(out))
	if args.has("yetim"):
		Node.print_orphan_nodes()
	quit()
