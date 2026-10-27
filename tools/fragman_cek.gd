# Tanıtım fragmanı çekimleri (sinematik kamera, arayüzsüz). Movie Maker ile kaydedilir:
#   Godot --path . --write-movie build/fragman/<ad>.avi --fixed-fps 30 -- shot=build/fragman/x.png pose=fragman sahne=<ad> wait=0.1
# sahne: koridor | hucre | telefon | ahize | c4 | patlama | silah | karakter | tahta | sigorta | dolap | kadro | rulet
# yon=dikey: 1080x1920 dikey çekim (kamera görüş açısı genişliğe göre; reklamın 9:16 sürümü). Reklam: build/reklam/cek.sh
# Her sahne 1.5 sn hazırlık bekler, sonra hareket başlar (kurguda baştan 1.5 sn kesilir).
extends RefCounted

const Props := preload("res://scripts/modlar/props.gd")
const AimMod := preload("res://scripts/modlar/aim_mod.gd")
const ModelScript := preload("res://scripts/model_body.gd")
const Catalog := preload("res://scripts/catalog.gd")
const HAZIRLIK := 1.5

static var dikey := false  # yon=dikey: dikey kadraj (görüş açısı yatay eksende)


static func run(w: Node3D, args: Dictionary) -> void:
	w.solo_ring_wait = 1000.0
	w.hud.visible = false
	if w.game_ui:
		w.game_ui.visible = false
	dikey = str(args.get("yon", "")) == "dikey"
	if dikey:
		w.player.camera.keep_aspect = Camera3D.KEEP_WIDTH
		w.player.camera.fov = 58.0
	var sahne := str(args.get("sahne", "koridor"))
	match sahne:
		"koridor":
			await _koridor(w)
		"hucre":
			await _hucre(w)
		"telefon":
			await _telefon(w)
		"ahize":
			await _ahize(w)
		"c4":
			await _c4(w)
		"patlama":
			await _patlama(w)
		"silah":
			await _silah(w)
		"karakter":
			await _karakter(w)
		"tahta":
			await _tahta(w, str(args.get("kelime", "TÜNEL")))
		"sigorta":
			await _sigorta(w)
		"dolap":
			await _dolap(w)
		"kadro":
			await _kadro(w)
		"rulet":
			await _rulet(w, args)
	args["wait"] = "0.05"


# --- yardımcılar ---

static func _kamera(w: Node3D) -> Camera3D:
	var cam := Camera3D.new()
	cam.near = 0.03
	if dikey:
		cam.keep_aspect = Camera3D.KEEP_WIDTH
	w.add_child(cam)
	cam.current = true
	var kulak := AudioListener3D.new()
	cam.add_child(kulak)
	kulak.make_current()
	w.player.body.visible = false
	return cam


# Dikey kadrajda görüş açısı genişliğe göre verilir: yataydaki dikey açının biraz darı (konu kadrajı doldursun).
static func _fv(f: float) -> float:
	return f * 0.9 if dikey else f


static func _bekle(w: Node3D, t: float) -> void:
	await w.get_tree().create_timer(t).timeout


static func _yumusak(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


# Kamerayı a -> b noktasına kaydırır, bakış noktası la -> lb; görüş açısı fa -> fb. Hafif el titremesi.
static func _kaydir(w: Node3D, cam: Camera3D, a: Vector3, b: Vector3, la: Vector3, lb: Vector3, sure: float, fa := 60.0, fb := 60.0, titre := 0.006, egri := true) -> void:
	var t := 0.0
	while t <= sure:
		var k := t / sure
		var e := _yumusak(k) if egri else k
		var sway := Vector3(sin(t * 1.3) * titre, sin(t * 1.9 + 1.0) * titre * 0.7, 0)
		cam.global_position = a.lerp(b, e) + sway
		var hedef := la.lerp(lb, e)
		if not cam.global_position.is_equal_approx(hedef):
			cam.look_at(hedef, Vector3.UP)
		cam.fov = _fv(lerpf(fa, fb, e))
		await w.get_tree().process_frame
		t += w.get_process_delta_time()


static func _isiklar(w: Node3D) -> Array:
	var out := []
	for l in w.find_children("*", "Light3D", true, false):
		if l is DirectionalLight3D:
			continue
		out.append([l, (l as Light3D).light_energy])
	return out


# Elektrik kesintisi gibi titreme: ışıklar yanıp söner, sonra loş kalır (kalan oranında).
static func _titret(w: Node3D, isiklar: Array, sure: float, kalan: float) -> void:
	var t := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	while t < sure:
		var k := t / sure
		var on := rng.randf() > 0.45 * (1.0 - k * 0.5)
		var oran := (1.0 if on else 0.05) * lerpf(1.0, kalan, k)
		for it in isiklar:
			if is_instance_valid(it[0]):
				(it[0] as Light3D).light_energy = float(it[1]) * oran
		await w.get_tree().process_frame
		t += w.get_process_delta_time()
	for it in isiklar:
		if is_instance_valid(it[0]):
			(it[0] as Light3D).light_energy = float(it[1]) * kalan


static func _mahkum(w: Node3D, look: Dictionary, pos: Vector3, yaw: float) -> Node3D:
	var b: Node3D = ModelScript.new()
	b.look = Catalog.sanitize(look)
	w.add_child(b)
	b.global_position = pos
	b.rotation.y = yaw
	return b


# --- sahneler ---

# 1) Karanlık koridor: ışıklar titreyip söner, kamera koridorda yavaşça süzülür.
static func _koridor(w: Node3D) -> void:
	for c in w.cells:
		c.set_door(false, true)
	var cam := _kamera(w)
	var a := Vector3(3.75, 1.75, 21.0)
	cam.global_position = a
	cam.look_at(a + Vector3(-0.12, -0.05, -1), Vector3.UP)
	cam.fov = _fv(62.0)
	w.player.global_position = w.cells[0].spawn_world()
	var isik := _isiklar(w)
	await _bekle(w, HAZIRLIK)
	_titret(w, isik, 2.2, 0.35)
	await _kaydir(w, cam, a, Vector3(3.95, 1.62, 8.0), a + Vector3(-0.12, -0.05, -10), Vector3(3.6, 1.45, -6.0), 7.0, 62.0, 56.0, 0.01, false)


# 2) Koridordan hücreye: kapı açık, duvarda çalan kırmızı telefon, içeride bir mahkum telefona bakıyor.
static func _hucre(w: Node3D) -> void:
	var c: Node3D = w.cells[0]
	var cam := _kamera(w)
	w.player.global_position = w.cells[6].spawn_world()
	var mp: Vector3 = c.to_global(Vector3(-0.65, 0, -0.95))
	var d: Vector3 = c.phone_world() - mp
	_mahkum(w, {"govde": "erkek", "sac": "ayrik", "sakal": "dolgun", "sac_renk": 1, "kiyafet": "turuncu", "ten": 2}, mp, atan2(-d.x, -d.z))
	var a: Vector3 = c.to_global(Vector3(-1.6, 1.75, 2.3))
	var b: Vector3 = c.to_global(Vector3(-0.55, 1.62, 0.55))
	cam.global_position = a
	cam.look_at(c.phone_world(), Vector3.UP)
	cam.fov = _fv(58.0)
	await _bekle(w, HAZIRLIK - 0.6)
	c.set_ringing(true)
	await _bekle(w, 0.6)
	if dikey:
		# dar kadraj: mahkum ile telefon birlikte görünsün (bakış ikisinin arası, daha kısa yaklaşma)
		var bas: Vector3 = mp + Vector3(0, 1.55, 0)
		await _kaydir(w, cam, a, a.lerp(b, 0.45), c.phone_world().lerp(bas, 0.5), c.phone_world().lerp(bas, 0.42), 5.0, 64.0, 58.0)
	else:
		await _kaydir(w, cam, a, b, c.phone_world() + Vector3(-0.6, -0.3, 0.4), c.phone_world() + Vector3(-0.2, -0.1, 0.0), 5.0, 58.0, 46.0)


# 3) Çalan telefona yakın plan (kamera yavaşça yaklaşır).
static func _telefon(w: Node3D) -> void:
	var c: Node3D = w.cells[0]
	var cam := _kamera(w)
	w.player.global_position = c.to_global(Vector3(-1.2, 0, 1.5))
	var p: Vector3 = c.phone_world()
	var a: Vector3 = p + Vector3(-0.95, 0.12, 0.42)
	var b: Vector3 = p + Vector3(-0.62, 0.05, 0.24)
	cam.global_position = a
	cam.look_at(p, Vector3.UP)
	cam.fov = _fv(42.0)
	await _bekle(w, HAZIRLIK - 0.5)
	c.set_ringing(true)
	await _bekle(w, 0.5)
	await _kaydir(w, cam, a, b, p + Vector3(0, -0.02, 0), p + Vector3(0, 0.0, 0), 4.5, 42.0, 38.0, 0.003)


# 4) Birinci şahıs: el ahizeyi kaldırır, oyuncu geri çekilince spiral kablo gerilir.
static func _ahize(w: Node3D) -> void:
	var p: CharacterBody3D = w.player
	var c: Node3D = w.cells[0]
	p.global_position = c.to_global(Vector3(1.05, 0, -2.15))
	var dir: Vector3 = c.phone_world() - p.global_position
	p.rotation.y = atan2(-dir.x, -dir.z)
	p.head.rotation.x = deg_to_rad(-8.0)
	await _bekle(w, HAZIRLIK - 1.0)
	c.set_ringing(true)
	await _bekle(w, 1.0)
	c.set_ringing(false)
	p.lift_handset(c)
	await _bekle(w, 1.6)
	# geri geri yürü: kablo gerilir
	var from: Vector3 = p.global_position
	var to: Vector3 = c.to_global(Vector3(-0.35, 0, -0.75))
	var t := 0.0
	var dur := 1.8
	var y0: float = p.rotation.y
	while t < dur:
		var e := _yumusak(t / dur)
		p.global_position = from.lerp(to, e)
		var d2: Vector3 = c.phone_world() - p.global_position
		p.rotation.y = lerp_angle(y0, atan2(-d2.x, -d2.z) + (0.06 if dikey else 0.25), e)
		p.head.rotation.x = lerpf(deg_to_rad(-12.0), deg_to_rad(-16.0), e)
		await w.get_tree().process_frame
		t += w.get_process_delta_time()
	await _bekle(w, 1.5)


# 5) C4 elde, koridorda; ekran geri sayıyor.
static func _c4(w: Node3D) -> void:
	var p: CharacterBody3D = w.player
	w.cells[0].set_door(true, true)
	p.global_position = Vector3(3.9, 0, w.cells[0].position.z + 2.5)
	p.rotation.y = 0.0
	p.head.rotation.x = deg_to_rad(-14.0)
	var bomb := Node3D.new()
	Props.c4(bomb)
	p.hold_item(0, bomb, AimMod.item_offset("c4", 0))
	p.set_hand_pose(0, "c4")
	await _bekle(w, HAZIRLIK)
	var t := 0.0
	while t < 3.5:
		p.head.rotation.x = deg_to_rad((-24.0 if dikey else -14.0) - 4.0 * _yumusak(t / 3.5))
		p.rotation.y = sin(t * 0.8) * 0.06 + (0.22 if dikey else 0.0)
		await w.get_tree().process_frame
		t += w.get_process_delta_time()


# 6) Patlama: hücre kapısında C4 patlar (dışarıdan, koridordan).
static func _patlama(w: Node3D) -> void:
	var c: Node3D = w.cells[2]
	c.set_detailed(true)
	c.set_door(true, true)
	var cam := _kamera(w)
	w.player.global_position = w.cells[6].spawn_world()
	var a := Vector3(4.6, 1.5, c.position.z + 5.5)
	cam.global_position = a
	cam.look_at(c.door_world(), Vector3.UP)
	cam.fov = _fv(55.0)
	await _bekle(w, HAZIRLIK)
	var b := Vector3(4.4, 1.45, c.position.z + 4.6)
	_kaydir(w, cam, a, b, c.door_world(), c.door_world() + Vector3(-0.5, 0, 0), 3.0, 55.0, 50.0)
	await _bekle(w, 0.7)
	Props.explosion(w, c.to_global(Vector3(1.4, 1.0, 0.5)), 0.0)
	w._shake(0.5, 0.06)
	await _bekle(w, 2.6)


# 7) Rus ruleti, dışarıdan: masada bir mahkum altıpatarı şakağına dayar.
static func _silah(w: Node3D) -> void:
	var c: Node3D = w.cells[0]
	var cam := _kamera(w)
	w.player.global_position = w.cells[6].spawn_world()
	var merkez: Vector3 = c.to_global(Vector3(0.0, 0, -0.7))
	var b: Node3D = ModelScript.new()
	b.look = Catalog.sanitize({"govde": "erkek", "sac": "ayrik", "sakal": "kirli", "sac_renk": 1, "ten": 2, "kiyafet": "turuncu"})
	b.seated = true
	w.add_child(b)
	b.global_position = merkez
	b.rotation.y = PI
	await w.get_tree().process_frame
	var sk: Skeleton3D = b.find_children("*", "Skeleton3D", true, false)[0]
	var m: Node = AimMod.new()
	sk.add_child(m)
	var item := Node3D.new()
	w.add_child(item)
	var inner := Node3D.new()
	item.add_child(inner)
	Props.revolver(inner)
	m.mode = "sakak"
	m.mode_target = merkez + Vector3(0, 1.5, 1.3)
	m.aim = 1.0
	m.hold(1, item, AimMod.item_offset("silah", 1))
	var hedef := merkez + Vector3(0.05, 1.12, 0)
	var a := merkez + Vector3(0.35, 1.3, 1.45)
	var bb := merkez + Vector3(0.12, 1.22, 0.85)
	if dikey:
		# dar kadraj: silahlı el de görünsün
		a = merkez + Vector3(0.3, 1.32, 2.0)
		bb = merkez + Vector3(0.12, 1.27, 1.45)
		hedef += Vector3(0.0, 0.12, 0)
	cam.global_position = a
	cam.look_at(hedef, Vector3.UP)
	cam.fov = _fv(45.0)
	await _bekle(w, HAZIRLIK)
	await _kaydir(w, cam, a, bb, hedef, hedef + Vector3(0.05, 0.02, 0), 3.5, 45.0, 40.0, 0.004)


# 8) Karakter özelleştirme: saç, şapka, kıyafet hızla değişir.
static func _karakter(w: Node3D) -> void:
	var ch: CanvasLayer = w.open_character()
	await w.get_tree().process_frame
	await _bekle(w, HAZIRLIK)
	var seq := [["sac", "mohawk"], ["sapka", "ters_kep"], ["kiyafet", "altin"], ["aksesuar", "gunes"], ["sac", "rasta"], ["sapka", "tac"], ["kiyafet", "leopar"], ["aksesuar", "zincir"]]
	for s in seq:
		if ch._cat != s[0]:
			ch._cat = s[0]
			ch._refresh()
		ch._pick(s[1])
		await _bekle(w, 0.55)
	await _bekle(w, 1.0)


# --- reklam (build/reklam) için ek sahneler ---

# 9) Kara Tahta: tahtaya tebeşirle gizli kelime yazılır, kamera tahtaya yaklaşır.
static func _tahta(w: Node3D, kelime: String) -> void:
	var c: Node3D = w.cells[0]
	var cam := _kamera(w)
	w.player.global_position = w.cells[6].spawn_world()
	var bp: Vector3 = c.board_world()
	var a: Vector3 = c.to_global(Vector3(-0.45, 1.45, -0.55))
	var b: Vector3 = c.to_global(Vector3(0.2, 1.62, -1.55))
	cam.global_position = a
	cam.look_at(bp, Vector3.UP)
	cam.fov = _fv(54.0)
	await _bekle(w, HAZIRLIK - 0.4)
	c.set_board_text(kelime)
	await _bekle(w, 0.4)
	await _kaydir(w, cam, a, b, bp + Vector3(0, -0.08, 0), bp, 4.5, 54.0, 44.0, 0.004)



# 10) Kısa Devre: ışıklar söner, sigorta kutusunun kapağı fırlar, kıvılcımlar saçılır; kamera kutuya yaklaşır.
static func _sigorta(w: Node3D) -> void:
	var c: Node3D = w.cells[0]
	var cam := _kamera(w)
	w.player.global_position = w.cells[6].spawn_world()
	var fp: Vector3 = c.fuse_world()
	var a: Vector3 = c.to_global(Vector3(0.05, 1.75, 0.75))
	var b: Vector3 = c.to_global(Vector3(1.0, 1.55, 1.4))
	cam.global_position = a
	cam.look_at(fp, Vector3.UP)
	cam.fov = _fv(56.0)
	await _bekle(w, HAZIRLIK - 0.5)
	c.set_power(false)
	await _bekle(w, 0.5)
	c.set_fuse("bozuk")
	await _kaydir(w, cam, a, b, fp + Vector3(0, -0.1, 0), fp, 4.0, 56.0, 46.0, 0.008)


# 11) Yalancı: dolap açılır, rafta eşya; kamera dolaba süzülür.
static func _dolap(w: Node3D) -> void:
	var c: Node3D = w.cells[0]
	c.set_locker_item("ponpon")
	var cam := _kamera(w)
	w.player.global_position = w.cells[6].spawn_world()
	var lp: Vector3 = c.locker_world()
	var a: Vector3 = c.to_global(Vector3(0.6, 1.55, 0.9))
	var b: Vector3 = c.to_global(Vector3(-0.35, 1.38, 0.35))
	cam.global_position = a
	cam.look_at(lp, Vector3.UP)
	cam.fov = _fv(56.0)
	await _bekle(w, HAZIRLIK - 0.3)
	c.set_locker(true)
	await _bekle(w, 0.3)
	await _kaydir(w, cam, a, b, lp + Vector3(0, -0.1, 0), lp, 4.0, 56.0, 46.0, 0.005)


# 12) Koğuş: beş mahkum karanlık koridorda kameraya doğru yürür (alçak açı), ışıklar titrer.
static func _kadro(w: Node3D) -> void:
	for c in w.cells:
		c.set_door(false, true)
	var cam := _kamera(w)
	w.player.global_position = w.cells[0].spawn_world()
	var looks := [
		{"govde": "erkek", "sac": "mohawk", "sakal": "pala", "sac_renk": 2, "kiyafet": "turuncu", "ten": 1},
		{"govde": "kadin", "sac": "ikiz_orgu", "sac_renk": 5, "aksesuar": "kupe", "kiyafet": "turuncu", "ten": 0},
		{"govde": "erkek", "sac": "ayrik", "sakal": "dolgun", "sac_renk": 1, "aksesuar": "gunes", "kiyafet": "turuncu", "ten": 2},
		{"govde": "kadin", "sac": "uzun_duz", "sac_renk": 3, "kiyafet": "cizgili", "ten": 2},
		{"govde": "erkek", "sac": "rasta", "sakal": "keci", "ten": 4, "aksesuar": "zincir", "kiyafet": "turuncu"},
	]
	var z0 := -8.0
	var ofs := [Vector3(0, 0, 0), Vector3(-0.85, 0, -0.9), Vector3(0.85, 0, -0.9), Vector3(-1.2, 0, -1.9), Vector3(1.2, 0, -1.9)]
	var bodies := []
	for i in looks.size():
		var b: Node3D = ModelScript.new()
		b.look = Catalog.sanitize(looks[i])
		w.add_child(b)
		b.global_position = Vector3(3.9, 0, z0) + ofs[i]
		b.rotation.y = PI  # +z yönüne (kameraya) yürür
		bodies.append(b)
	var a := Vector3(3.9, 0.55, z0 + 5.2)
	cam.global_position = a
	cam.look_at(Vector3(3.9, 1.35, z0), Vector3.UP)
	cam.fov = _fv(50.0)
	var isik := _isiklar(w)
	await _bekle(w, HAZIRLIK)
	_titret(w, isik, 1.2, 0.6)
	var t := 0.0
	var hiz := 1.0
	while t < 5.0:
		var d := w.get_process_delta_time()
		for i in bodies.size():
			var b: Node3D = bodies[i]
			b.global_position.z += hiz * d
			b.set("walk", hiz / 1.4)
		var hz: float = bodies[0].global_position.z
		cam.global_position = Vector3(3.9 + sin(t * 0.7) * 0.04, 0.55 + t * 0.04, a.z + t * 0.55)
		cam.look_at(Vector3(3.9, 1.3 + t * 0.03, hz - 0.5), Vector3.UP)
		await w.get_tree().process_frame
		t += d


# 13) Rus ruleti birinci şahıs: masada üç mahkum, silah sende; birine doğrultup tetiği çekersin (boş).
#   arayuz=1: oyunun arayüzü görünür (yatay arayüz çekimi)
static func _rulet(w: Node3D, args: Dictionary) -> void:
	var gizle := str(args.get("arayuz", "0")) != "1"
	if gizle:
		_arayuz_gizle(w, 30.0)
	var OT = load("res://scripts/modlar/oyunici_test.gd")
	await OT.run(w, {"ekran": "rulet_hedef", "oyun": "rulet", "hedef": str(args.get("hedef", "2")), "bekle": "0.05"})
	if not gizle:
		w.hud.visible = true
	await _bekle(w, 1.4)
	var mod = w.game_ui.mod
	if mod:
		mod.on_event({"tur": "atis", "atan": 1, "hedef": int(args.get("hedef", "2")), "patladi": false, "olen": 0, "sira": 1, "hayatta": [1, 2, 3, 4], "sure": 9})
	await _bekle(w, 3.0)


static func _arayuz_gizle(w: Node3D, sure: float) -> void:
	var t := 0.0
	while t < sure and is_instance_valid(w):
		for n in w.get_tree().root.find_children("*", "CanvasLayer", true, false):
			(n as CanvasLayer).visible = false
		await w.get_tree().process_frame
		t += w.get_process_delta_time()
