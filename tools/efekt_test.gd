# Efekt denetimi (scripts/efekt.gd): her efektin İLK kullanımındaki en uzun kare süresi + ekran görüntüleri.
# Kullanım: Godot --path . --resolution 1280x720 --script res://tools/efekt_test.gd -- server=ws://127.0.0.1:8794 profil=efekt_test kalite=1 klasor=build/dunya2/efekt
# Önce efektsiz 40 karenin en uzunu (taban), sonra her efekt ilk kez tetiklenip sonraki 40 karenin en uzunu ölçülür.
# Ardından her efekt yeniden tetiklenir ve ekran görüntüsü alınır (kivilcim, namlu, toz, damla, nefes, patlama, kisa_devre).
extends SceneTree

const Efekt := preload("res://scripts/efekt.gd")

var args := {}
var main: Node
var dir := ""


func _init() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	dir = str(args.get("klasor", "build/dunya2/efekt"))
	DirAccess.make_dir_recursive_absolute(dir)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	if not main.hazir_mi:
		await main.hazir
	while main.get_children().any(func(c: Node) -> bool: return c.get_script() == preload("res://scripts/acilis.gd")):
		await process_frame
	main.profile.settings.kalite = int(args.get("kalite", "1"))
	main.apply_settings()
	main._start_solo()
	main.apply_settings()
	main.solo_ring_wait = 9999.0
	main.hud.visible = false
	if main.game_ui:
		main.game_ui.visible = false
	var c0: Node3D = main.cells[0]
	c0.set_door(true, true)
	_place(Vector3(3.9, 0, c0.position.z + 3.2), 0.0, -4.0)
	await _wait(60)
	var cam: Camera3D = main.player.camera
	var ileri := -cam.global_basis.z
	ileri.y = 0.0
	ileri = ileri.normalized()
	var on := cam.global_position + ileri * 2.2
	var zemin := Vector3(on.x, 0.0, on.z)
	var tetik := {
		"kivilcim": func() -> void: Efekt.kivilcim(main, on + Vector3(0, 0.4, 0), Vector3(-ileri.x, 0.5, -ileri.z)),
		"namlu": func() -> void: Efekt.namlu(main, Transform3D(Basis.looking_at(Vector3(1, 0, 0) * 0.6 + ileri * 0.4, Vector3.UP), on + Vector3(-0.3, 0.2, 0))),
		"toz": func() -> void: Efekt.toz(main, zemin, 2.2),
		"damla": func() -> void: Efekt.damla(main, Vector3(zemin.x, 3.18, zemin.z - 0.6), 0.0),
		"nefes": func() -> void: Efekt.nefes(main, on + Vector3(0, 0.1, 0), Vector3(1, -0.2, 0)),
		"patlama": func() -> void: preload("res://scripts/modlar/props.gd").explosion(main, zemin + ileri * 1.2 + Vector3(0, 1.0, 0), 0.0),
	}
	# 1) ilk kullanım kare süreleri
	print("[efekt] kalite=%s" % args.get("kalite", "1"))
	print("[efekt] taban (efektsiz) en uzun kare: %.1f ms" % await _worst(40))
	for ad in tetik:
		(tetik[ad] as Callable).call()
		print("[efekt] %-9s ilk kullanim en uzun kare: %.1f ms" % [ad, await _worst(40)])
		await _wait(30)
	# kısa devre: sigorta bozulur (kıvılcımlar cell.gd _efektler)
	main.my_cell = 0
	c0.set_detailed(true)
	c0.set_fuse("bozuk")
	print("[efekt] kisa_devre ilk kullanim en uzun kare: %.1f ms" % await _worst(60))
	c0.set_fuse("normal")
	await _wait(240)
	# 2) görüntüler
	var anlar := {"kivilcim": 4, "namlu": 1, "toz": 30, "damla": 34, "nefes": 40, "patlama": 1}
	for ad in tetik:
		(tetik[ad] as Callable).call()
		await _wait(int(anlar[ad]))
		await _shot(ad)
		if ad == "patlama":
			await _wait(6)
			await _shot("patlama_1")
			await _wait(24)
			await _shot("patlama_2")
			await _wait(150)
			await _shot("patlama_3")
		await _wait(200)
	# kısa devre: sigorta kutusuna bak
	var fp: Vector3 = c0.fuse_world()
	_place(c0.to_global(Vector3(0.2, 0, 1.6)), 0.0, 0.0)
	_bak(fp)
	c0.set_power(false)
	c0.set_fuse("bozuk")
	for i in 6:
		await _wait(12)
		await _shot("kisa_devre_%d" % i)
	c0.set_fuse("kilit")
	await _wait(3)
	await _shot("kisa_devre_kilit")
	quit()


func _bak(p: Vector3) -> void:
	var pl: Node3D = main.player
	var d := p - pl.global_position
	pl.rotation.y = atan2(-d.x, -d.z)
	var cam: Camera3D = main.player.camera
	var dc := p - cam.global_position
	main.player.head.rotation.x = atan2(dc.y, Vector2(dc.x, dc.z).length())


func _place(pos: Vector3, yaw: float, pitch: float) -> void:
	main.player.global_position = pos
	main.player.rotation.y = yaw
	main.player.head.rotation.x = deg_to_rad(pitch)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _worst(frames: int) -> float:
	var last := Time.get_ticks_usec()
	var w := 0.0
	for i in frames:
		await process_frame
		var now := Time.get_ticks_usec()
		w = maxf(w, (now - last) / 1000.0)
		last = now
	return w


func _shot(ad: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(dir.path_join("%s_k%s.png" % [ad, args.get("kalite", "1")]))
	print("[efekt] goruntu ", ad)
