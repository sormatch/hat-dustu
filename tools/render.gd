# Bir kerelik araç: 3D dosyayı önden ve yandan çekip resim kaydeder.
# Çalıştırma: Godot --path . --script res://tools/render.gd -- dosya=res://... cikti=C:/.../a.png
extends SceneTree

func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1]
	var w := Node3D.new()
	root.add_child(w)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#30333b")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.6, 0.5, 0)
	w.add_child(sun)
	for i in 2:
		var m: Node3D = load(args.dosya).instantiate()
		m.position.x = -0.9 + i * 1.8
		m.rotation.y = 0.0 if i == 0 else PI / 2
		w.add_child(m)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.95, 4.2)
	w.add_child(cam)
	cam.look_at(Vector3(0, 0.9, 0))
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args.cikti)
	quit()
