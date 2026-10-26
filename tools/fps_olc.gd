# Performans ölçümü: her sahne için çizim çağrısı, üçgen, nesne, video belleği, bellek ve kare süresi.
# Kullanım: Godot --path . --resolution 1280x720 --script res://tools/fps_olc.gd -- kalite=1 [sahne=hucre,koridor] [klasor=build/perf/once] [sure=3]
# Sahneler (her biri ayrı süreçte ölçülür): menu, kasa, hucre, ayna, telefon, koridor, kalabalik (koridorda 8 karakter),
#   kalabalik_arka (aynı 7 karakter arkada, koridorun öbür ucuna bakış), lobi, c4 (patlama anı), macsonu.
# kalabalik_arka ekleri: okluzyonsuz=1 (gölgeleyicisiz karşılaştırma), hucresiz=1 (diğer hücreler gizli), dok=1 (görüş konisindekiler).
# kapat=<betik adları> o betiklerin _process'ini kapatır (sıcak nokta arama). Önce/sonra tablosu: build/perf/once.txt, sonra.txt
# govde=1: tek karakterin parça dökümü (yüzey, üçgen, kemik, doku) ve 8 karakterin toplamı.
# Masaüstünde ölçüldüğü için fps değil; çizim çağrısı / üçgen / bellek sayıları telefona taşınır.
extends SceneTree

const BodyScript := preload("res://scripts/model_body.gd")
const Catalog := preload("res://scripts/catalog.gd")
const LOOKS := [
	{"govde": "erkek", "sac": "ayrik", "sakal": "dolgun", "sac_renk": 1, "aksesuar": "gunes", "kiyafet": "turuncu"},
	{"govde": "kadin", "sac": "ikiz_orgu", "sac_renk": 5, "aksesuar": "kupe", "kiyafet": "pembe", "ten": 0},
	{"govde": "erkek", "sac": "rasta", "sakal": "keci", "ten": 4, "aksesuar": "zincir", "kiyafet": "cizgili"},
	{"govde": "kadin", "sac": "uzun_duz", "sac_renk": 3, "aksesuar": "kalp", "kiyafet": "leopar", "ten": 2},
	{"govde": "erkek", "sac": "mohawk", "sakal": "pala", "sac_renk": 2, "sapka": "yok", "kiyafet": "kot", "ten": 1},
	{"govde": "kadin", "sac": "atkuyrugu", "sac_renk": 0, "sapka": "bere", "kiyafet": "kamuflaj", "ten": 3},
	{"govde": "erkek", "sac": "kisa", "sakal": "biyik", "sapka": "ters_kep", "aksesuar": "kulaklik", "kiyafet": "ekose"},
	{"govde": "kadin", "sac": "kivircik", "sac_renk": 4, "aksesuar": "gozluk", "kiyafet": "altin", "ten": 1},
]

var args := {}
var main: Node
var dir := ""
var rows := []


func _init() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	dir = str(args.get("klasor", ""))
	if dir != "":
		DirAccess.make_dir_recursive_absolute(dir)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.profile.settings.kalite = int(args.get("kalite", "1"))
	main.apply_settings()
	if args.get("govde", "") == "1":
		await _body_report()
		quit()
		return
	# her sahne kendi sürecinde ölçülmeli (öncekinin kalıntısı karışmasın): sahne=<tek ad>
	var only: Array = str(args.get("sahne", "hucre")).split(",", false)
	if only.has("menu"):
		await _wait(60)
		await _measure("menu")
	if only.has("kasa"):
		# menüden açılan mağazada kasa açılışı (3D dünya menüdeyken çizilmez)
		var ch: CanvasLayer = main.open_character()
		await process_frame
		var won: Array = []
		for it in Catalog.shop_items():
			if it[1] == "tac":
				won = it
		if won.is_empty():
			won = Catalog.shop_items()[0]
		ch.spin(ch.CHESTS[1], won)
		await _measure("kasa", 2.5, 30)
	if only.has("menu") or only.has("kasa"):
		_print_rows()
		quit()
		return
	main._start_solo()
	main.apply_settings()
	main.solo_ring_wait = 9999.0
	main.hud.visible = false
	var c0: Node3D = main.cells[0]
	if args.has("kapat"):
		# deney: adı verilen betiklerin _process'i kapatılır (sıcak nokta arama)
		var names: Array = str(args.kapat).split(",", false)
		for n in main.find_children("*", "", true, false) + [main]:
			var sc: Script = n.get_script()
			if sc and names.has(sc.resource_path.get_file().get_basename()):
				n.set_process(false)
	for name in only:
		match name:
			"ayna":
				_place(c0.to_global(Vector3(-0.85, 0, 1.05)), c0.global_rotation.y + PI / 2, 8.0)
				await _measure(name)
			"telefon":
				# hücredeki duvar telefonu yakından (ahize çatalda)
				_place(c0.to_global(Vector3(1.05, 0, -2.25)), c0.global_rotation.y - PI / 2, -8.0)
				await _measure(name)
			"hucre":
				_place(c0.to_global(Vector3(1.2, 0, 2.4)), c0.global_rotation.y + deg_to_rad(28), -6.0)
				await _measure(name)
			"koridor":
				c0.set_door(true, true)
				_place(Vector3(3.6, 0, -8.0), 0.0, 0.0)
				await _measure(name)
			"lobi":
				_place(main.lobby.to_global(Vector3(-0.5, 0, 5.2)), 0.0, -3.0)
				await _measure(name)
			"kalabalik":
				c0.set_door(true, true)
				_place(Vector3(3.9, 0, c0.position.z + 3.0), 0.0, -4.0)
				_spawn_crowd(7)
				await _measure(name)
			"kalabalik_arka":
				# aynı 7 karakter arkada kalır (ekranda değil): animasyonları durmalı
				c0.set_door(true, true)
				_place(Vector3(3.9, 0, c0.position.z + 3.0), 0.0, -4.0)
				_spawn_crowd(7)
				await _wait(20)
				main.player.rotation.y = PI
				await _measure(name)
				print("[olc] oklüzyon ayari=", ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling"), " vp=", root.get_viewport().use_occlusion_culling)
				if args.has("okluzyonsuz"):
					root.get_viewport().use_occlusion_culling = false
					await _measure(name + "_o")
				if args.has("hucresiz"):
					for i in range(1, main.cells.size()):
						main.cells[i].visible = false
					await _measure(name + "_h")
				if args.has("dok"):
					_dump_visible()
			"c4":
				c0.set_door(true, true)
				_place(Vector3(3.9, 0, c0.position.z + 3.0), 0.0, -2.0)
				await _wait(20)
				preload("res://scripts/modlar/props.gd").explosion(main, main.player.global_transform * Vector3(0, 1.0, -3.0), 0.0)
				await _measure(name, 1.5, 0)
			"macsonu":
				var tbl := []
				var pl := []
				for i in 4:
					tbl.append({"id": i + 1, "name": ["Zeynep", "Kerem", "Ali", "Deniz"][i], "score": 40 - i * 10, "p": [10 - i * 3, 12 - i * 4, 8 - i * 3], "g": LOOKS[i]})
					pl.append({"id": i + 1, "g": LOOKS[i]})
				var ms = load("res://scripts/mac_sonu.gd").new()
				ms.setup({"table": tbl, "oyunlar": [{"ad": "Kara Tahta"}, {"ad": "Kısa Devre"}, {"ad": "Rulet"}], "winner": 1}, 1, pl)
				var katman := CanvasLayer.new()
				katman.layer = 100
				main.add_child(katman)
				katman.add_child(ms)
				await _wait(int(60 * 9))  # açılış animasyonu bitsin (birinci tacıyla sahnede)
				await _measure(name)
				katman.queue_free()
	_print_rows()
	quit()


func _print_rows() -> void:
	print("[olc] kalite=%s" % args.get("kalite", "1"))
	print("[olc] sahne        | cizim | ucgen(k) | nesne | vram MB | doku MB | bellek MB | cpu ms | gpu ms | kare ms (en kotu) | betik ms | fizik ms")
	for r in rows:
		print("[olc] %-12s | %5d | %8.1f | %5d | %7.0f | %7.0f | %9.0f | %6.2f | %6.2f | %6.2f (%5.1f) | %5.2f | %5.2f" % r)


func _place(pos: Vector3, yaw: float, pitch: float) -> void:
	main.player.global_position = pos
	main.player.rotation.y = yaw
	main.player.head.rotation.x = deg_to_rad(pitch)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


# Koridorda gerçek uzak oyuncu yoluyla (çarpışma gövdesi + ad etiketi) karakterler: yakından uzağa.
func _spawn_crowd(n: int) -> void:
	main.playing = true
	var base: Vector3 = main.player.global_position
	for i in n:
		var id := 50 + i
		main.net.players.append({"id": id, "name": "Bot %d" % i, "cell": i % 8, "g": LOOKS[(i + 1) % LOOKS.size()]})
		var p := base + Vector3((i % 2) * 1.1 - 0.55, 0, -2.0 - i * 1.6)
		main._on_remote_state(id, {"p": [p.x, p.z], "y": PI if i % 3 else 0.0, "o": false})


func _measure(name: String, secs := -1.0, warm := 40) -> void:
	if secs < 0.0:
		secs = float(args.get("sure", "3"))
	await _wait(warm)
	var vp := root.get_viewport_rid()
	var t0 := Time.get_ticks_usec()
	var last := t0
	var frames := 0
	var dc := 0
	var prim := 0
	var obj := 0
	var cpu := 0.0
	var gpu := 0.0
	var worst := 0.0
	var shot_done := false
	var proc := 0.0
	var phys := 0.0
	while Time.get_ticks_usec() - t0 < int(secs * 1000000.0):
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		frames += 1
		dc += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		prim += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		obj += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		if dir != "" and not shot_done and frames == 10:
			shot_done = true
			await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_png(dir.path_join("%s_k%s.png" % [name, args.get("kalite", "1")]))
			last = Time.get_ticks_usec()
	var f := float(maxi(frames, 1))
	var el := (Time.get_ticks_usec() - t0) / 1000.0
	rows.append([name, int(dc / f), prim / f / 1000.0, int(obj / f),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		cpu / f, gpu / f, el / f, worst, proc / f, phys / f])


# ---------- tek karakterin dökümü ----------

func _body_report() -> void:
	var bodies := []
	for i in LOOKS.size():
		var b: Node3D = BodyScript.new()
		b.look = Catalog.sanitize(LOOKS[i])
		main.add_child(b)
		b.position = Vector3(100 + i, 0, 100)
		bodies.append(b)
	await _wait(5)
	var tot := {"yuzey": 0, "ucgen": 0, "golge": 0}
	var all_tex := {}
	for i in bodies.size():
		var b: Node3D = bodies[i]
		var surf := 0
		var tris := 0
		var shadow := 0
		var parts := []
		var bones := 0
		for sk in b.find_children("*", "Skeleton3D", true, false):
			bones += (sk as Skeleton3D).get_bone_count()
		for mi in b.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null or not m.is_visible_in_tree():
				continue
			var t := 0
			for s in m.mesh.get_surface_count():
				t += _surf_tris(m.mesh, s)
				for tex in _mat_textures(_mat_of(m, s)):
					all_tex[tex] = true
			surf += m.mesh.get_surface_count()
			tris += t
			if m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				shadow += m.mesh.get_surface_count()
			parts.append("%s:%dx%d" % [m.name, m.mesh.get_surface_count(), t])
		for sk in b.find_children("*", "SkeletonModifier3D", true, false):
			parts.append("[mod %s]" % sk.get_class())
		print("[govde] %d %s/%s: %d yuzey, %d ucgen, %d golge yuzeyi, %d kemik | %s" % [i, b.look.govde, b.look.sac, surf, tris, shadow, bones, ", ".join(parts)])
		tot.yuzey += surf
		tot.ucgen += tris
		tot.golge += shadow
	print("[govde] 8 karakter toplam: %d yuzey (her biri bir cizim), %d ucgen, %d golge yuzeyi" % [tot.yuzey, tot.ucgen, tot.golge])
	var tex_mb := 0.0
	for tex in all_tex:
		var t := tex as Texture2D
		var img := t.get_image() if t is CompressedTexture2D else null
		var fmt: String = str(img.get_format()) if img else t.get_class()
		var mb := (img.get_data_size() / 1048576.0) if img else 0.0
		tex_mb += mb
		print("[doku] %s %dx%d %s %.2f MB" % [t.resource_path.get_file() if t.resource_path != "" else t.get_class(), t.get_width(), t.get_height(), fmt, mb])
	print("[doku] karakter dokulari toplam %.1f MB (%d doku)" % [tex_mb, all_tex.size()])


func _surf_tris(mesh: Mesh, s: int) -> int:
	if mesh is ArrayMesh:
		var am := mesh as ArrayMesh
		var ic := am.surface_get_array_index_len(s)
		return (ic if ic > 0 else am.surface_get_array_len(s)) / 3
	var arr := mesh.surface_get_arrays(s)
	var idx = arr[Mesh.ARRAY_INDEX]
	return (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3


func _mat_of(m: MeshInstance3D, s: int) -> Material:
	if m.material_override:
		return m.material_override
	if m.get_surface_override_material(s):
		return m.get_surface_override_material(s)
	return m.mesh.surface_get_material(s)


func _mat_textures(mat: Material) -> Array:
	var out := []
	if mat is BaseMaterial3D:
		for p in ["albedo_texture", "normal_texture", "roughness_texture", "orm_texture", "metallic_texture", "emission_texture"]:
			var t = mat.get(p)
			if t is Texture2D:
				out.append(t)
	elif mat is ShaderMaterial:
		for p in (mat as ShaderMaterial).shader.get_shader_uniform_list():
			var t = (mat as ShaderMaterial).get_shader_parameter(p.name)
			if t is Texture2D:
				out.append(t)
	return out


# Kameranın görüş konisindeki çizilen nesneler: türe / ağ adına göre sayım (çizim çağrısı nereden geliyor).
func _dump_visible() -> void:
	var cam := root.get_viewport().get_camera_3d()
	var counts := {}
	for n in main.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var bb := g.global_transform * g.get_aabb()
		if not cam.is_position_in_frustum(bb.get_center()) and bb.size.length() < 6.0:
			continue
		var d := cam.global_position.distance_to(bb.get_center())
		if g.visibility_range_end > 0.0 and d > g.visibility_range_end + g.visibility_range_end_margin:
			continue
		var nm := g.get_class()
		if g is MeshInstance3D and (g as MeshInstance3D).mesh:
			nm += ":" + ((g as MeshInstance3D).mesh.resource_name if (g as MeshInstance3D).mesh.resource_name != "" else (g as MeshInstance3D).mesh.get_class())
		var key := "%s @%s" % [nm, String(g.get_parent().name).left(18)]
		var surf := (g as MeshInstance3D).mesh.get_surface_count() if g is MeshInstance3D and (g as MeshInstance3D).mesh else 1
		if not counts.has(key):
			counts[key] = [0, 0, 999.0]
		counts[key][0] += 1
		counts[key][1] += surf
		counts[key][2] = minf(counts[key][2], d)
	var keys := counts.keys()
	keys.sort_custom(func(a, b) -> bool: return counts[a][1] > counts[b][1])
	for k in keys.slice(0, 40):
		print("[dok] %4d adet %4d yuzey en yakin %5.1f m  %s" % [counts[k][0], counts[k][1], counts[k][2], k])
