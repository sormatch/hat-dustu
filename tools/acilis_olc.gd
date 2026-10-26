# Açılış adımlarının süresi: main.gd _ready'deki büyük işler tek tek ölçülür (hangi adım donduruyor?).
# Kullanım: Godot --path . --resolution 1280x720 --script res://tools/acilis_olc.gd -- server=ws://127.0.0.1:8794 profil=acilistest
extends SceneTree


func _init() -> void:
	_run.call_deferred()


func _t(name: String, f: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	f.call()
	print("[acilis] %-22s %7.1f ms" % [name, (Time.get_ticks_usec() - t0) / 1000.0])


func _run() -> void:
	print("[acilis] motor -> betik: %d ms" % Time.get_ticks_msec())
	if OS.get_cmdline_user_args().has("onyukle=1"):
		var keep := []
		var t0 := Time.get_ticks_usec()
		for d in ResourceLoader.list_directory("res://assets/models/"):
			var p := "res://assets/models/%s%s.gltf" % [d, d.trim_suffix("/")]
			if ResourceLoader.exists(p):
				keep.append(load(p))
		for d in ResourceLoader.list_directory("res://assets/textures/"):
			for f in ResourceLoader.list_directory("res://assets/textures/" + d):
				if f.ends_with(".jpg") or f.ends_with(".png"):
					keep.append(load("res://assets/textures/" + d + f))
		print("[acilis] onyukleme %d kaynak %.1f ms" % [keep.size(), (Time.get_ticks_usec() - t0) / 1000.0])
		set_meta("keep", keep)
	var m := Node3D.new()
	root.add_child(m)
	m.set_script(load("res://scripts/main.gd"))
	var w: Node3D = m
	_t("profil+muzik", func() -> void:
		w.profile = w.ProfileScript.new()
		w.add_child(w.profile)
		w.muzik = w.MuzikScript.new()
		w.add_child(w.muzik))
	_t("input", w._setup_input)
	_t("malzemeler", w._make_materials)
	_t("ortam", w._build_environment)
	_t("koridor", w._build_corridor)
	_t("lobi", func() -> void:
		w.lobby = w.LobbyScript.new()
		w.lobby.w = w
		w.lobby.position = w.LOBBY_POS
		w.add_child(w.lobby)
		w.lobby.build())
	for k in 8:
		_t("hucre %d" % k, func() -> void:
			var c: Node3D = w.CellScript.new()
			c.w = w
			c.index = k
			c.number = 11 + k
			c.position = Vector3(0, 0, (k - 3.5) * 6.6)
			w.add_child(c)
			c.build()
			w.cells.append(c))
	_t("oyuncu", func() -> void:
		w.player = w.PlayerScript.new()
		w.add_child(w.player))
	_t("hud", func() -> void:
		w.hud = w.HudScript.new()
		w.add_child(w.hud))
	_t("player.set_look", func() -> void: w.player.set_look(w.profile.look))
	var st := {"pre": 0}
	RenderingServer.frame_pre_draw.connect(func() -> void: st.pre = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func() -> void: print("[acilis]   cizim: %.1f ms" % ((Time.get_ticks_usec() - int(st.pre)) / 1000.0)))
	var t0 := Time.get_ticks_usec()
	for i in 5:
		await process_frame
		print("[acilis] kare %d: %.1f ms (islem %.1f ms)" % [i, (Time.get_ticks_usec() - t0) / 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
		t0 = Time.get_ticks_usec()
	quit()
