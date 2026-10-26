# Ekran görüntüsü testi (main.gd pose=dizi): koridorda yan yana karakterler, her birine ayrı görünüş.
# Listeler virgülle; her karakter listelerin sırasıyla bir öğesini alır (kısa liste döner):
#   govde=erkek,iri,yasli  kiyafet=..  sapka=..  aksesuar=..  sac=..  sakal=..  ten=0,3,5  sac_renk=..
#   n=<adet> (varsayılan en uzun liste)  ara=<metre>  yon=on|arka|yan|ceyrek  yakin=kafa|govde|el|boy (kamera)
#   hareket=<kimlik> t=<sn> (hareket başladıktan sonra çekim)  isik=1 (öne ek dolgu ışığı)
# Örnek: pose=dizi govde=erkek,iri,yasli,ince kiyafet=no1337,kirli,gardiyan yon=arka
extends RefCounted

const BodyScript := preload("res://scripts/model_body.gd")
const Catalog := preload("res://scripts/catalog.gd")


static func _list(args: Dictionary, k: String) -> Array:
	return str(args.get(k, "")).split(",", false) if args.has(k) else []


static func run(w: Node3D, args: Dictionary) -> void:
	w.hud.visible = false
	if args.has("hucre"):
		await _cell_view(w, args)
		return
	w.solo_ring_wait = 100.0
	w.cells[0].set_door(true, true)
	var keys := ["govde", "kiyafet", "sapka", "aksesuar", "sac", "sakal", "ten", "sac_renk", "dovme", "goz"]
	var lists := {}
	var n := 1
	for k in keys:
		lists[k] = _list(args, k)
		n = maxi(n, (lists[k] as Array).size())
	n = int(args.get("n", n))
	var gap := float(args.get("ara", "0.62"))
	var base := Transform3D(Basis(), Vector3(3.9, 0, w.cells[0].position.z + 3.0))
	var yaw: float = {"on": 0.0, "arka": PI, "yan": PI / 2, "ceyrek": 0.6}.get(str(args.get("yon", "on")), 0.0)
	var bodies := []
	for i in n:
		var look := {"govde": "erkek", "sac": "kisa", "kiyafet": "turuncu", "ten": 1}
		for k in keys:
			var l: Array = lists[k]
			if not l.is_empty():
				var v: String = l[i % l.size()]
				look[k] = int(v) if k in ["ten", "sac_renk", "goz"] else v
		var b: Node3D = BodyScript.new()
		b.look = Catalog.sanitize(look)
		w.add_child(b)
		# karakterler -z'ye bakar; dizi kameraya (+z yönünde, karşıda) dönük
		b.global_position = base * Vector3((i - (n - 1) / 2.0) * gap, 0, -2.0)
		b.rotation.y = PI + yaw
		bodies.append(b)
	var cam := Camera3D.new()
	w.add_child(cam)
	var mode := str(args.get("yakin", "boy"))
	var width := (n - 1) * gap + 0.8
	var target := base * Vector3(0, 0.95, -2.0)
	match mode:
		"kafa":
			target = base * Vector3(0, 1.6, -2.0)
			cam.fov = 30
		"govde":
			target = base * Vector3(0, 1.25, -2.0)
			cam.fov = 34
		"el":
			target = base * Vector3(0, 0.88, -2.0)
			cam.fov = 30
		_:
			cam.fov = 40
	var h := {"kafa": 0.45, "govde": 0.8, "el": 0.5, "boy": 2.0}.get(mode, 2.0) as float
	var dist := maxf(width * 0.5 / tan(deg_to_rad(cam.fov) * 0.5 * 16.0 / 9.0), h * 0.55 / tan(deg_to_rad(cam.fov) * 0.5))
	cam.look_at_from_position(target + Vector3(0, 0.05, dist), target)
	cam.current = true
	if args.has("isik"):
		var l := OmniLight3D.new()
		l.omni_range = 6.0
		l.light_energy = 1.2
		w.add_child(l)
		l.global_position = target + Vector3(0, 0.6, 1.6)
	await w.get_tree().process_frame
	await w.get_tree().process_frame
	if args.has("hareket"):
		for b in bodies:
			b.play_emote(str(args.hareket))
		await w.get_tree().create_timer(float(args.get("t", "1.0"))).timeout
		args["wait"] = "0"  # çekim hemen (main.gd çekimden önce wait kadar daha bekler)


# hucre=<numara> aci=1..3: hücrenin içi geniş açıyla (rastgele eşyalar: kitaplık, radyo, tuvalet-lavabo, ağırlık, saksı,
# saat, posterler). Işıklar açık; oyuncu dışarıda.
static func _cell_view(w: Node3D, args: Dictionary) -> void:
	w.solo_ring_wait = 100.0
	var i := clampi(int(args.hucre), 0, w.cells.size() - 1)
	var c: Node3D = w.cells[i]
	if c.get("locked"):
		c.lamp_light.visible = true
		c.lamp_fill.visible = true
	w.player.global_position = Vector3(0, -50, 0)
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.fov = 78
	var views := {
		"1": [Vector3(-1.3, 1.65, 2.4), Vector3(1.2, 0.8, -1.6)],  # sağ duvar ve arka köşe (kitaplık, lavabo, saat)
		"2": [Vector3(1.2, 1.65, -2.2), Vector3(-0.6, 0.7, 2.6)],  # ön duvar (ağırlık, masa, poster)
		"3": [Vector3(1.5, 1.7, 2.5), Vector3(-1.2, 0.9, -2.0)],  # arka-sol (yatak, poster, kova)
		"raf": [Vector3(0.0, 1.45, -0.2), Vector3(1.78, 0.75, -1.0)],
		"lavabo": [Vector3(0.2, 1.55, -1.2), Vector3(1.5, 0.6, -2.74)],
		"agirlik": [Vector3(0.3, 1.45, 1.0), Vector3(0.35, 0.25, 2.5)],
		"saat": [Vector3(0.2, 1.75, -0.6), Vector3(1.96, 2.25, -1.05)],
		"masa": [Vector3(0.6, 1.45, 1.4), Vector3(1.5, 0.8, 2.65)],
		"poster": [Vector3(0.3, 1.65, 0.6), Vector3(0.3, 1.8, 3.0)],
	}
	if views.has(str(args.get("aci", ""))) and str(args.aci).length() > 1:
		cam.fov = 55
		var fill := OmniLight3D.new()
		fill.omni_range = 4.0
		fill.light_energy = 0.8
		c.add_child(fill)
		fill.position = (views[str(args.aci)][0] as Vector3) + Vector3(0, 0.3, 0)
	var v: Array = views.get(str(args.get("aci", "1")), views["1"])
	cam.look_at_from_position(c.to_global(v[0]), c.to_global(v[1]))
	cam.current = true
	await w.get_tree().process_frame
