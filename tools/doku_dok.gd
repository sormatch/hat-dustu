# Sahnedeki dokuların dökümü: hangi doku ne kadar video belleği tutuyor (malzemeler, arayüz, önbellekler)?
# Kullanım: Godot --path . --resolution 1280x720 --script res://tools/doku_dok.gd -- server=ws://127.0.0.1:8794 profil=dokutest [adim=menu|magaza|magaza_kapali|mac] [n=40]
extends SceneTree

var seen := {}


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
	for i in 120:
		await process_frame
	var adim := str(args.get("adim", "menu"))
	if adim == "magaza" or adim == "magaza_kapali":
		var ch: CanvasLayer = main.open_character()
		for i in 60:
			await process_frame
		for c in ch.CATS:
			ch._select_cat(c)
			for i in 20:
				await process_frame
		if adim == "magaza_kapali":
			ch._close(false)
			for i in 60:
				await process_frame
	elif adim == "mac":
		main._start_solo()
		for i in 120:
			await process_frame
	for n in [root] + root.find_children("*", "", true, false):
		_node(n)
	var ui: GDScript = load("res://scripts/ui.gd")
	for t in (ui.get("_tex") as Dictionary).values():
		_add(t, "UI._tex")
	_print(int(args.get("n", "40")))
	print("[dok] vram %.1f MB, doku %.1f MB" % [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0])
	quit()


func _node(n: Node) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		_mat(g.material_override, n)
		_mat(g.material_overlay, n)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var m := (n as MeshInstance3D).mesh
			for s in m.get_surface_count():
				_mat((n as MeshInstance3D).get_surface_override_material(s), n)
				_mat(m.surface_get_material(s), n)
		if n is CPUParticles3D and (n as CPUParticles3D).mesh:
			var pm := (n as CPUParticles3D).mesh
			for s in pm.get_surface_count():
				_mat(pm.surface_get_material(s), n)
		if n is SpriteBase3D and n.get("texture"):
			_add(n.texture, n)
	if n is Decal:
		_add((n as Decal).texture_albedo, n)
	if n is TextureRect:
		_add((n as TextureRect).texture, n)
	if n is NinePatchRect:
		_add((n as NinePatchRect).texture, n)
	if n is Control:
		for p in n.get_property_list():
			var nm: String = p.name
			if nm.begins_with("theme_override_styles/"):
				var sb = n.get(nm)
				if sb is StyleBoxTexture:
					_add((sb as StyleBoxTexture).texture, n)
	if n is WorldEnvironment and (n as WorldEnvironment).environment:
		var e := (n as WorldEnvironment).environment
		if e.sky and e.sky.sky_material:
			_mat(e.sky.sky_material, n)


func _mat(m: Material, n: Node) -> void:
	if m == null:
		return
	if m is BaseMaterial3D:
		for p in ["albedo_texture", "normal_texture", "roughness_texture", "orm_texture", "metallic_texture", "emission_texture", "ao_texture", "detail_albedo", "detail_normal"]:
			_add(m.get(p), n)
	elif m is ShaderMaterial and (m as ShaderMaterial).shader:
		for p in (m as ShaderMaterial).shader.get_shader_uniform_list():
			_add((m as ShaderMaterial).get_shader_parameter(p.name), n)
	if m.next_pass:
		_mat(m.next_pass, n)


func _add(t, n) -> void:
	if not (t is Texture2D) or seen.has(t):
		return
	var tx := t as Texture2D
	var bytes := 0.0
	var fmt := ""
	if tx is CompressedTexture2D or tx is ImageTexture:
		var img := tx.get_image()
		if img:
			bytes = img.get_data_size()
			fmt = str(img.get_format())
			if not img.has_mipmaps() and tx is CompressedTexture2D and (tx as CompressedTexture2D).has_mipmaps():
				bytes *= 1.33
	else:
		bytes = tx.get_width() * tx.get_height() * 4.0
		fmt = tx.get_class()
	var where := str(n) if n is String else String((n as Node).get_path()).right(48)
	seen[t] = [bytes, tx.get_width(), tx.get_height(), fmt, tx.resource_path if tx.resource_path != "" else tx.get_class(), where]


func _print(n: int) -> void:
	var list := seen.values()
	list.sort_custom(func(a, b) -> bool: return a[0] > b[0])
	var tot := 0.0
	var by_dir := {}
	for d in list:
		tot += d[0]
		var k: String = str(d[4]).get_base_dir() if str(d[4]).begins_with("res://") else str(d[4])
		by_dir[k] = float(by_dir.get(k, 0.0)) + d[0]
	print("[dok] %d doku, ~%.1f MB" % [list.size(), tot / 1048576.0])
	for i in mini(n, list.size()):
		var d: Array = list[i]
		print("[dok] %6.2f MB %5dx%-5d f%-3s %s  <- %s" % [d[0] / 1048576.0, d[1], d[2], d[3], d[4], d[5]])
	var keys := by_dir.keys()
	keys.sort_custom(func(a, b) -> bool: return by_dir[a] > by_dir[b])
	for k in keys.slice(0, 25):
		print("[dok] klasor %7.1f MB  %s" % [by_dir[k] / 1048576.0, k])
