# Karakter görüntü testi: model_body.gd ile bir ya da birkaç karakter kurar, poz/hareket oynatır, fotoğraf çeker.
# Çalıştırma: Godot --path . --script res://tools/karakter_cek.gd -- cikti=C:/.../a.png
#   look={"govde":"kadin","sac":"topuz"}  (JSON; birden çok karakter için | ile ayır)
#   hareket=dans  zaman=1.2  kamera=yakin|tam|bel  aci=0 (derece, karakter dönüşü)
extends SceneTree

const BodyScript := preload("res://scripts/model_body.gd")


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var w := Node3D.new()
	root.add_child(w)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#2a2d35")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.57, 0.62)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.5, 0.45, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	w.add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.5, 1.8, 2.0)
	fill.light_energy = 0.8
	fill.omni_range = 6.0
	w.add_child(fill)
	var looks: Array = []
	for s in str(args.get("look", "{}")).split("|"):
		looks.append(JSON.parse_string(s))
	var n := looks.size()
	var bodies := []
	for i in n:
		var b: Node3D = BodyScript.new()
		b.look = b.Catalog.sanitize(looks[i])
		w.add_child(b)
		b.position.x = (i - (n - 1) * 0.5) * float(args.get("aralik", "0.42" if args.get("kamera", "tam") == "yakin" else "0.75"))
		b.rotation.y = PI + deg_to_rad(float(args.get("aci", "0")))
		bodies.append(b)
	await process_frame
	await process_frame
	if args.has("ham"):
		for b in bodies:
			for c in b._cloth_mats:
				(c[0] as ShaderMaterial).set_shader_parameter("pattern", 99)
	var t := float(args.get("zaman", "0.6"))
	if args.has("hareket"):
		for b in bodies:
			b.play_emote(args.hareket)
	var el := 0.0
	while el < t:
		await process_frame
		el += 1.0 / 60.0
	if args.has("profil"):
		var H = load("res://scripts/hair.gd")
		for k in H._profiles:
			print("profil ", k, " min=", H._profiles[k].min, " max=", H._profiles[k].max, " boyut=", H._profiles[k].max - H._profiles[k].min)
	if args.has("hata"):
		for b in bodies:
			var sk: Skeleton3D = b._skel
			var hi := sk.find_bone("mixamorig_Head")
			print("kafa kemiği dünya: ", sk.global_transform * sk.get_bone_global_pose(hi))
			print("_head dünya: ", b._head.global_transform)
			for c in b._head.get_children():
				if c is MeshInstance3D:
					print("  parça ", c.name, " dünya kutu: ", c.global_transform * (c as MeshInstance3D).get_aabb())
			for ba in sk.get_children():
				if ba is BoneAttachment3D:
					for q in ba.find_children("*", "MeshInstance3D", true, false):
						print("  bağlı ", ba.bone_name, " ", q.name, " kutu: ", (q as MeshInstance3D).global_transform * (q as MeshInstance3D).get_aabb())
						break
			for mi in sk.get_children():
				if mi is MeshInstance3D:
					print("  model ", mi.name, " kutu: ", (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb())
	var cam := Camera3D.new()
	w.add_child(cam)
	var kind: String = args.get("kamera", "tam")
	var width := maxf(1.0, n * float(args.get("aralik", "0.42" if args.get("kamera", "tam") == "yakin" else "0.75")))
	match kind:
		"yakin":
			cam.fov = 30.0
			cam.position = Vector3(0, 1.62, maxf(0.75, width * 1.75 if n > 1 else 0.75))
			cam.look_at(Vector3(0, 1.58, 0))
		"bel":
			cam.fov = 35.0
			cam.position = Vector3(0, 1.35, 1.6 + 0.6 * width)
			cam.look_at(Vector3(0, 1.25, 0))
		_:
			cam.fov = 40.0
			cam.position = Vector3(0, 1.0, 2.6 + 0.9 * width)
			cam.look_at(Vector3(0, 0.9, 0))
	cam.current = true
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args.get("cikti", "user://karakter.png"))
	quit()
