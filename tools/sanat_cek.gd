# 3D sanat kontrolü: arayüzsüz birkaç bakıştan ekran görüntüsü alır (hücre, koridor, kulübe, bekleme salonu).
# Kullanım: Godot --path . --resolution 1280x720 --script res://tools/sanat_cek.gd -- klasor=<dizin> kalite=1 [bak=lobi,koridor]
extends SceneTree


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var dir: String = args.get("klasor", "user://sanat")
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.profile.settings.kalite = int(args.get("kalite", "1"))
	if args.get("bak", "") == "menu":
		# menü arka plan sahnesi: 2D menüyü gizle, menü kamerasından çek
		main.apply_settings()
		main.menu.visible = false
		if args.get("buhar", "1") == "0":
			for c in main.get_children():
				if c is CPUParticles3D:
					c.visible = false
		for i in int(float(args.get("bekle", "3")) * 60):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(dir.path_join("menu.png"))
		print("[sanat] menu")
		quit()
		return
	main._start_solo()
	main.apply_settings()
	main.solo_ring_wait = 999.0
	main.hud.visible = false
	main.game_ui.visible = false
	var c0: Node3D = main.cells[0]
	var lob: Node3D = main.lobby
	# ad: [konum, yaw, bakış eğimi (derece)]
	var views := {
		"hucre": [c0.to_global(Vector3(1.2, 0, 2.4)), deg_to_rad(28), -6.0],
		"hucre_kapi": [c0.to_global(Vector3(-1.2, 0, -1.6)), deg_to_rad(-130), -4.0],
		"koridor": [Vector3(3.6, 0, -8.0), 0.0, 0.0],
		"koridor_ters": [Vector3(4.4, 0, 8.0), PI, 0.0],
		"kulube": [Vector3(4.3, 0, 21.5), PI, -4.0],
		"lobi": [lob.to_global(Vector3(-0.5, 0, 5.2)), 0.0, -3.0],
		"lobi_tv": [lob.to_global(Vector3(4.2, 0, -1.5)), -PI / 2, 8.0],
		"lobi_arka": [lob.to_global(Vector3(2.0, 0, -4.5)), PI + 0.5, 4.0],
	}
	var only: Array = str(args.get("bak", "")).split(",", false)
	for name in views:
		if only.size() > 0 and not only.has(name):
			continue
		var v: Array = views[name]
		if name.begins_with("koridor") or name == "kulube":
			c0.set_door(true, true)
		main.player.global_position = v[0]
		main.player.rotation.y = float(v[1])
		main.player.head.rotation.x = deg_to_rad(float(v[2]))
		for i in 40:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
		print("[sanat] ", name)
	quit()
