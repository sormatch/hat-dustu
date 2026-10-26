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
