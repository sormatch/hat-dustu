# Bir kerelik araç: tüm karakterleri durma animasyonuyla yan yana çekip resim kaydeder.
# Çalıştırma: Godot --path . --script res://tools/kadro.gd -- cikti=C:/.../a.png [adlar=a,b,c] [yakin=1]
extends SceneTree

func _init() -> void:
	var args := {"adlar": "mahkum_b,remy,james,brian,big_vegas,kate,megan,sophie,jennifer,claire"}
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
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.5, 0.4, 0)
	w.add_child(sun)
	var inst: Node = load("res://assets/karakter/anim/durma.fbx").instantiate()
	var ap0: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
	var idle: Animation = ap0.get_animation(ap0.get_animation_list()[0])
	var lib := AnimationLibrary.new()
	lib.add_animation("durma", idle)
	var names: PackedStringArray = str(args.adlar).split(",")
	var n := names.size()
	for i in n:
		var m: Node3D = load("res://assets/karakterler/%s.fbx" % names[i]).instantiate()
		m.position.x = (i - (n - 1) / 2.0) * 0.85
		w.add_child(m)
		var aps := m.find_children("*", "AnimationPlayer", true, false)
		var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
		var ab := Vector3.ZERO
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			ab = ab.max((mi as MeshInstance3D).get_aabb().size)
		print(names[i], " bones=", sk.get_bone_count(), " skel=", m.get_path_to(sk), " aabb=", ab, " anims=", aps.size())
		if aps.size() > 0:
			var ap: AnimationPlayer = aps[0]
			ap.add_animation_library("hd", lib)
			ap.play("hd/durma")
		var l := Label3D.new()
		l.text = names[i]
		l.position = Vector3(0, 2.05, 0)
		l.pixel_size = 0.003
		m.add_child(l)
	var cam := Camera3D.new()
	if args.has("yakin"):
		cam.position = Vector3(0, 1.6, 2.2)
		cam.fov = 40
		w.add_child(cam)
		cam.look_at_from_position(cam.position, Vector3(0, 1.55, 0))
	else:
		cam.position = Vector3(0, 1.0, n * 0.62 + 1.0)
		w.add_child(cam)
		cam.look_at_from_position(cam.position, Vector3(0, 0.95, 0))
	for i in 20:
		await process_frame
	if not cam.is_inside_tree(): print("cam yok")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args.cikti)
	quit()
