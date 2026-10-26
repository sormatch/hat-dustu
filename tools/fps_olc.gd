# Performans ölçümü: hücre ve koridor görünümünde ortalama FPS, çizim çağrısı ve üçgen sayısı.
# Kullanım: Godot --path . --resolution 1280x720 --script res://tools/fps_olc.gd -- kalite=1
extends SceneTree


func _init() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.profile.settings.kalite = int(args.get("kalite", "1"))
	main._start_solo()
	main.apply_settings()
	main.solo_ring_wait = 999.0
	var poses := {
		"hucre": [Vector3(0.0, 0, 1.9), 0.0],
		"hucre_kapi": [Vector3(-1.0, 0, -1.0), -PI * 0.75],
		"koridor": [Vector3(3.9, 0, 3.0), 0.0],
	}
	for name in poses:
		var p: Array = poses[name]
		if name == "koridor":
			main.cells[0].set_door(true, true)
			main.player.global_position = Vector3(3.9, 0, main.cells[0].position.z + 3.0)
		else:
			main.player.global_position = main.cells[0].to_global(p[0])
		main.player.rotation.y = float(p[1])
		for i in 30:
			await process_frame
		var t0 := Time.get_ticks_usec()
		var frames := 0
		var dc := 0
		var prim := 0
		while Time.get_ticks_usec() - t0 < 3000000:
			await process_frame
			frames += 1
			dc += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
			prim += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		var secs := (Time.get_ticks_usec() - t0) / 1000000.0
		print("[fps] %s: %.0f fps, %d cizim, %dk ucgen" % [name, frames / secs, dc / frames, prim / frames / 1000])
	print("[fps] video bellegi: %d MB" % (RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576))
	quit()
