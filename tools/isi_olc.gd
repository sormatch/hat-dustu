# Isınma ölçümü: gerçek kare sınırı + dikey eşzamanlama açıkken saniyedeki kare, çizilen kare, GPU/CPU süresi.
# Kullanım: Godot --path . --resolution 1280x720 --script res://tools/isi_olc.gd -- sahne=menu_bosta [onceki=1] [sure=4]
#   onceki=1: eski davranış (Isi kapalı, kare sınırı yok: yalnız ekran yenileme hızı sınırlar)  -> komut satırına ayrıca isi=0 ver
# Sahneler: menu_bosta (dokunulmuyor), menu_dokun (her 0,3 sn dokunma), hucre, koridor, salon (in_lobby), rulet,
#   arka (arka plana alınmış: arka_plan(true))
# Çıktı: "[isi] sahne | fps | cizilen/sn | gpu ms | cpu ms | GPU-ms/sn | cizim | ucgen(k)"
# GPU-ms/sn = kare başına GPU süresi x çizilen kare/sn: ısınmanın masaüstündeki en iyi göstergesi (telefona taşınmaz, yönü taşınır).
extends SceneTree

var args := {}
var main: Node


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	if args.has("onceki"):
		Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	if not main.hazir_mi:
		await main.hazir
	while main.get_children().any(func(c: Node) -> bool: return c.get_script() == preload("res://scripts/acilis.gd")):
		await process_frame
	main.profile.settings.kalite = int(args.get("kalite", "1"))
	main.profile.settings.kalite_oto = false
	main.apply_settings()
	var sahne := str(args.get("sahne", "menu_bosta"))
	var sure := float(args.get("sure", "4"))
	if args.has("onceki"):
		Engine.max_fps = 0  # Isi _ready'de sınır koymuş olabilir (isi=0 verilmediyse)
	var isi: Node = main.get_node_or_null("Isi")
	for c in main.get_children():
		if c.get_script() == preload("res://scripts/isi.gd"):
			isi = c
	match sahne:
		"menu_bosta", "menu_dokun":
			pass
		_:
			main._start_solo()
			main.apply_settings()
			main.solo_ring_wait = 9999.0
			main.hud.visible = false
			var c0: Node3D = main.cells[0]
			match sahne:
				"hucre", "arka":
					_place(c0.to_global(Vector3(1.2, 0, 2.4)), c0.global_rotation.y + deg_to_rad(28), -6.0)
				"koridor":
					c0.set_door(true, true)
					_place(Vector3(3.6, 0, -8.0), 0.0, 0.0)
				"salon":
					_place(main.lobby.to_global(Vector3(-0.5, 0, 5.2)), 0.0, -3.0)
					main.in_lobby = true
				"rulet":
					await load("res://scripts/modlar/oyunici_test.gd").run(main, {"ekran": "rulet", "oyun": "rulet"})
	if sahne == "arka" and isi and not args.has("onceki"):  # önceki sürümde arka plan davranışı yoktu
		isi.arka_plan(true)
	for i in 90:
		await process_frame
	await _olc(sahne, sure, isi)
	if sahne == "arka" and isi:
		isi.arka_plan(false)
	quit()


func _place(pos: Vector3, yaw: float, pitch: float) -> void:
	main.player.global_position = pos
	main.player.rotation.y = yaw
	main.player.head.rotation.x = deg_to_rad(pitch)


func _olc(sahne: String, sure: float, isi: Node) -> void:
	var vp := root.get_viewport_rid()
	var t0 := Time.get_ticks_usec()
	var sayac := [0]
	var baglan := func() -> void: sayac[0] += 1
	RenderingServer.frame_post_draw.connect(baglan)
	var cizilen0 := 0
	var fd0 := Engine.get_frames_drawn()
	var kare := 0
	var gpu := 0.0
	var cpu := 0.0
	var dc := 0
	var prim := 0
	var son_dokun := 0.0
	var degerler := {}  # çizim gerçekten sürüyorsa GPU ölçümü kareden kareye değişir; durduysa tek değer kalır
	while Time.get_ticks_usec() - t0 < int(sure * 1000000.0):
		await process_frame
		kare += 1
		if sahne == "menu_dokun" and Time.get_ticks_usec() / 1000000.0 - son_dokun > 0.3:
			son_dokun = Time.get_ticks_usec() / 1000000.0
			var ev := InputEventScreenTouch.new()
			ev.pressed = true
			Input.parse_input_event(ev)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		degerler[snappedf(RenderingServer.viewport_get_measured_render_time_gpu(vp), 0.0001)] = 1
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		dc += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		prim += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var el := (Time.get_ticks_usec() - t0) / 1000000.0
	RenderingServer.frame_post_draw.disconnect(baglan)
	var cizilen: int = sayac[0] - cizilen0  # gerçekten çizilen kare (render_loop_enabled=false iken frame_post_draw gelmez)
	var f := float(maxi(kare, 1))
	var cf := float(maxi(cizilen, 1))
	var fps := kare / el
	var cfps := cizilen / el
	# GPU/CPU süreleri yalnız çizilen karelerde ölçülür; çizilmeyen karelerde son değer kalır, bu yüzden çizilen kareye bölünür
	var gpu_kare := gpu / f
	print("[isi] %-11s | %s | max_fps=%d yenileme=%.0f | fps %5.1f | cizilen/sn %5.1f | gpu %.2f ms | cpu %.2f ms | GPU-ms/sn %6.1f | gpu-degisim %2d | cizim %4d | ucgen %6.1fk" % [
		sahne, "ONCEKI" if args.has("onceki") else "SONRA ", Engine.max_fps, DisplayServer.screen_get_refresh_rate(), fps, cfps, gpu_kare, cpu / f, gpu_kare * cfps, degerler.size(), dc / f, prim / f / 1000.0])
