# Mağaza dikey görselleri, 2-8. sahneler (dikey_cek.gd çağırır). Yalnız çekim: oyunun davranışını değiştirmez.
extends RefCounted

const D := preload("res://tools/dikey_cek.gd")
const FC := preload("res://tools/fragman_cek.gd")
const TT := preload("res://tools/tiktok_cek.gd")
const Props := preload("res://scripts/modlar/props.gd")
const AimMod := preload("res://scripts/modlar/aim_mod.gd")
const MacSonu := preload("res://scripts/mac_sonu.gd")


static func sahne(w: Node3D, args: Dictionary, ad: String) -> void:
	match ad:
		"d_yalanci":
			await _yalanci(w, args)
		"d_c4":
			await _c4(w, args)
		"d_kacis":
			await _kacis(w, args)
		"d_projektor":
			await _projektor(w, args)
		"d_rulet":
			await _rulet(w, args)
		"d_kasa":
			await _kasa(w, args)
		"d_macsonu":
			await _macsonu(w, args)
		"d_klozet":
			await _klozet(w, args)
		"d_tunel":
			await _tunel(w, args)


static func _pozla(w: Node3D, pozlama: float, beyaz := 5.0) -> void:
	var env: Environment = w.get("env")
	env.tonemap_exposure = pozlama
	env.tonemap_white = beyaz


static func _koridor_hazir(w: Node3D) -> void:
	for cc in w.cells:
		cc.set_door(false, true)


# --- 2) YALANCI: yan yana mahkûmlar, herkeste aynı ponponlu bere, birinde lastik ördek ---
static func _yalanci(w: Node3D, args: Dictionary) -> void:
	_koridor_hazir(w)
	var cam := D._kamera(w)
	var zc := 6.0
	w.player.global_position = Vector3(3.9, 0, zc + 8.0)
	var liste := [
		{"govde": "kadin", "sac": "ikiz_orgu", "sac_renk": 5, "kiyafet": "turuncu", "ten": 0, "sapka": "ponpon"},
		{"govde": "erkek", "sac": "kisa", "sakal": "dolgun", "sac_renk": 1, "kiyafet": "turuncu", "ten": 2, "sapka": "ponpon"},
		{"govde": "erkek", "sac": "ayrik", "sakal": "keci", "sac_renk": 2, "kiyafet": "turuncu", "ten": 1, "sapka": "ordek"},
		{"govde": "erkek", "sac": "kisa", "sakal": "pala", "ten": 4, "kiyafet": "turuncu", "sapka": "ponpon"},
	]
	var bas := []
	var n := liste.size()
	for i in n:
		var k: float = i - (n - 1) / 2.0
		var yer := Vector3(3.9 + k * 0.5 + 0.06 + (-0.1 if i == 0 else 0.0), 0, zc - absf(k - 0.5) * 0.32 + (0.12 if i == 2 else 0.0))
		var b: Node3D = FC._mahkum(w, liste[i], yer, PI + (-k * 0.08))
		bas.append(b)
	await w.get_tree().process_frame
	await w.get_tree().process_frame
	var yalanci: Node3D = bas[2]
	var kam_yer := Vector3(3.95, 1.28, zc + D._sec(2.75, 2.45, 2.6))
	var hedef := Vector3(3.95, D._sec(1.12, 1.33, 1.2), zc)
	D._kam(cam, kam_yer, hedef, D._sec(38.0, 53.0, 43.0))
	for i in n:
		var b: Node3D = bas[i]
		if b == yalanci:
			b.set("bakis", kam_yer + Vector3(0, 0.4, 0))
			b.play_emote("omuz")
		else:
			b.set("bakis", yalanci.global_position + Vector3(0, 1.65, 0))
			b.play_emote("kollar")
	D._spot(w, Vector3(3.9, 3.05, zc + 1.6), Vector3(3.9, 1.3, zc), Color(1.0, 0.86, 0.68), 2.4, 46.0, 6.0)
	D._spot(w, Vector3(4.2, 3.0, zc + 0.7), yalanci.global_position + Vector3(0, 1.7, 0), Color(1.0, 0.78, 0.4), 2.6, 15.0, 5.0)
	_pozla(w, 0.75)
	await FC._bekle(w, float(args.get("an", "1.1")))


# --- 3) C4: elinde bomba, koridorda koşarak kaçış, arkada patlama ---
static func _c4(w: Node3D, args: Dictionary) -> void:
	_koridor_hazir(w)
	var cam := D._kamera(w)
	var z := 6.5
	w.player.global_position = Vector3(3.9, 0, z + 9.0)
	var b: Node3D = FC._mahkum(w, TT.LOOKS[1], Vector3(3.85, 0, z), PI)
	await w.get_tree().process_frame
	var pose: Node = AimMod.of_body(b)
	var bomba := Node3D.new()
	w.add_child(bomba)
	Props.c4(bomba)
	if pose:
		pose.mode = "c4"
		pose.aim_l = 1.0
		pose.hold(0, bomba, AimMod.item_offset("c4", 0))
	b.set("walk", 1.95)
	var kam_yer := Vector3(3.5, 0.85, z + 2.15)
	D._kam(cam, kam_yer, Vector3(3.85, D._sec(1.18, 1.22, 1.18), z), D._sec(56.0, 70.0, 60.0))
	b.set("bakis", kam_yer + Vector3(0, 0.7, 0.0))
	b.set("talk", 0.8)
	TT._blink(bomba, true, "00:03")
	D._spot(w, Vector3(3.4, 2.4, z + 2.2), Vector3(3.85, 1.3, z), Color(1.0, 0.86, 0.72), 1.0, 28.0, 5.0)
	_pozla(w, 0.5)
	await FC._bekle(w, 1.2)
	var uzak := float(args.get("uzak", "1.8"))
	for a in [[3.9, 1.55, 3.4, 0.0, 3.5], [3.3, 1.2, 2.6, 2.4, 2.6], [4.5, 1.25, 2.4, 1.4, 2.6], [3.85, 1.35, 1.6, 4.0, 3.2]]:
		var pn := D._pano(w, "ates", Vector3(a[0], a[1], z - uzak - a[2]), Vector2(a[4], a[4]), kam_yer, true, Color(1.0, 0.88, 0.75))
		pn.rotate_object_local(Vector3.BACK, a[3])
	D._omni(w, Vector3(3.9, 1.5, z - 0.9), Color(1.0, 0.45, 0.12), 2.2, 4.0)
	Props.explosion(w, Vector3(3.9, 1.0, z - uzak - 2.6), 0.0)
	await FC._bekle(w, 0.07)
	Props.explosion(w, Vector3(3.7, 1.15, z - uzak - 1.2), 0.0)
	await FC._bekle(w, 0.07)
	Props.explosion(w, Vector3(4.1, 1.25, z - uzak), 0.0)
	TT._blink(bomba, true, "00:03")
	await FC._bekle(w, float(args.get("an", "0.14")))
	for rb in w.get_tree().root.find_children("*", "RigidBody3D", true, false):
		(rb as Node3D).visible = false  # uçuşan küp enkaz durağan karede kare leke gibi duruyor
	TT._blink(bomba, true, "00:03")


# --- 4) BÜYÜK KAÇIŞ: tel örgünün dışı, ormandan bakış; arkada duvar, kule ışığı, ormana koşan mahkûmlar ---
static func _kacis(w: Node3D, _args: Dictionary) -> void:
	var OT = load("res://scripts/modlar/oyunici_test.gd")
	await OT.run(w, {"ekran": "hucre", "oyun": "kacis", "bekle": "0.05"})
	var mod = w.game_ui.mod
	var kx := -19.5
	var kz := 0.5
	mod._dis_kur(Vector3(kx, 0, kz))
	w.player.global_position = Vector3(kx + 6.0, 0, kz + 30.0)
	var cam := D._kamera(w)
	var b: Node3D = FC._mahkum(w, TT.LOOKS[3], Vector3(kx - 7.2, 0, kz + 1.0), PI / 2.0 - 0.12)
	var b2: Node3D = FC._mahkum(w, TT.LOOKS[2], Vector3(kx - 3.6, 0, kz - 0.4), PI / 2.0 + 0.12)
	await w.get_tree().process_frame
	b.set("walk", 1.95)
	b2.set("walk", 1.95)
	var kam_yer := Vector3(kx - 10.4, 0.95, kz + 1.5)
	D._kam(cam, kam_yer, Vector3(kx - 4.0, D._sec(3.55, 2.75, 3.1), kz + 0.6), D._sec(58.0, 72.0, 62.0))
	D._pano(w, "gokyuzu", Vector3(45.0, D._sec(34.0, 20.0, 24.0), kz + 1.5), Vector2(120.0, 180.0) if D.oran == "iphone" else Vector2(150.0, 225.0), kam_yer).scale.x = -1.0
	for a in [[6.2, 3.3, 7.5], [6.6, -5.0, 8.0], [8.4, 3.6, 7.0], [8.8, -5.8, 6.5]]:
		_agac(w, Vector3(kam_yer.x + a[0], 0, kam_yer.z + a[1]), a[2])
	for fz in [-6.0, 2.0, 10.0]:
		D._omni(w, Vector3(float(mod.CIT_X) + 1.0, 3.0, kz + fz), Color(0.7, 0.8, 1.0), 3.5, 9.0)
	b.set("bakis", kam_yer + Vector3(0, 1.0, 0))
	b2.set("bakis", kam_yer + Vector3(0, 1.0, 0))
	D._omni(w, Vector3(kx - 8.8, 1.7, kz + 2.2), Color(0.8, 0.86, 1.0), 2.6, 5.0)
	# gece seçilsin: ay ve ortam biraz güçlü, gökyüzü koyu lacivert
	var env: Environment = w.env
	env.background_color = Color(0.02, 0.04, 0.09)
	env.ambient_light_energy = 1.3
	env.ambient_light_color = Color(0.42, 0.52, 0.74)
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.09, 0.16)
	env.fog_density = 0.012
	if is_instance_valid(mod._dis):
		for l in mod._dis.find_children("*", "DirectionalLight3D", true, false):
			(l as DirectionalLight3D).light_energy = 2.6
		# kuleden inen sabit huzme (oyunun projektör efekti): koşanların yanına düşer
		var top := Vector3(float(mod.TEMEL_X), 10.0, kz + 6.0)
		var yer := Vector3(kx - 1.0, 0, kz - 2.6)
		var spot := D._spot(w, top, yer, Color(1.0, 0.95, 0.85), 30.0, 9.0, 40.0)
		spot.spot_attenuation = 0.4
		D._huzme(w, top, yer, 0.2, 1.2, Color(1.0, 0.95, 0.82), 0.5)
	_pozla(w, 1.1)
	await FC._bekle(w, 1.3)


# --- 5) PROJEKTÖR AVI: gece avlusu, kuleden inen huzme mahkûmun üstünde; yanında gardiyan fenerle arıyor ---
static func _projektor(w: Node3D, args: Dictionary) -> void:
	var OT = load("res://scripts/modlar/oyunici_test.gd")
	await OT.run(w, {"ekran": "av", "oyun": "projektor", "t": "20", "bekle": "0.05"})
	var mod = w.game_ui.mod
	await FC._bekle(w, 2.5)
	var cam := D._kamera(w)
	var kule := Vector3(24.4, 0, -11.6)
	var p := Vector3(float(args.get("px", "29.0")), 0, float(args.get("pz", "-1.5")))
	var yon: Vector3 = (p - kule).normalized()
	var yan := yon.cross(Vector3.UP)
	w.player.global_position = Vector3(26, 0, 11)
	var kam_yon_b: Vector3 = yon.rotated(Vector3.UP, float(args.get("don", "0.5")))
	var b: Node3D = FC._mahkum(w, {"govde": "kadin", "sac": "ikiz_orgu", "sac_renk": 5, "kiyafet": "turuncu", "ten": 2}, p, 0.0)
	await w.get_tree().process_frame
	b.rotation.y = atan2(-kam_yon_b.x, -kam_yon_b.z) - 0.8
	b.set("crouched", bool(args.get("comel", "1") == "1"))
	var kam_yon: Vector3 = yon.rotated(Vector3.UP, float(args.get("don", "0.5")))
	var kam_yer: Vector3 = p + kam_yon * 2.7 + Vector3(0, 0.62, 0)
	D._pano(w, "gokyuzu", kule - yon * 60.0 + Vector3(0, 40.0, 0), Vector2(170.0, 255.0), kam_yer)
	var hedef: Vector3 = p + Vector3(0, D._sec(2.05, 1.75, 1.9), 0)
	D._kam(cam, kam_yer, hedef, D._sec(62.0, 76.0, 66.0))
	b.set("bakis", kam_yer + Vector3(0, 0.9, 0))
	var eski_g: Node3D = mod._avlu_gardiyani()
	if eski_g:
		eski_g.visible = false
	var g_b: Node3D = mod._gardiyan_govde()
	w.add_child(g_b)
	var g_yer: Vector3 = p - kam_yon * 1.0 + kam_yon.cross(Vector3.UP) * float(args.get("gy", "-1.25"))
	var env: Environment = w.env
	env.background_color = Color(0.02, 0.035, 0.08)
	env.fog_light_color = Color(0.07, 0.1, 0.17)
	env.fog_density = 0.016
	D._omni(w, kam_yer + Vector3(0.0, 0.6, 0), Color(0.7, 0.8, 1.0), 0.9, 4.0)
	_pozla(w, 1.05)
	var hangi := 0
	for i in mod._isik.size():
		var y0: Vector3 = mod._isik[i].yer
		print("bilgi isik ", i, " ", y0)
		if Vector2(y0.x, y0.z).distance_to(Vector2(kule.x, kule.z)) < 3.0:
			hangi = i
	var l0: Dictionary = mod._isik[hangi]
	(l0.spot as SpotLight3D).light_energy = 1.0
	(l0.havuz as Decal).emission_energy = 0.22
	D._huzme(w, (l0.yer as Vector3) + Vector3(0, 0.3, 0), p, 0.2, 1.25, Color(1.0, 0.95, 0.82), 0.75)
	(l0.huzme as MeshInstance3D).visible = false
	var isikla := func() -> void:
		for i in mod._isik.size():
			mod._isik_yerlestir(i, p, i == hangi)
		(l0.huzme as MeshInstance3D).visible = false
		if g_b:
			g_b.global_position = g_yer
			g_b.rotation.y = atan2(-(p - g_yer).x, -(p - g_yer).z)
			g_b.set("walk", 0.0)
			g_b.set("bakis", p + Vector3(0, 1.0, 0))
		if is_instance_valid(mod._fener):
			mod._fener.visible = true
			mod._fener.global_position = g_yer + Vector3(0, 1.25, 0) + (p - g_yer).normalized() * 0.35
			mod._fener.look_at(p + Vector3(0, 0.6, 0), Vector3.UP)
	mod.state["phase"] = "cekim"  # oyunun ışık döngüsü artık dokunmasın
	isikla.call()
	await FC._bekle(w, 0.2)
	isikla.call()
	await FC._bekle(w, 1.0)


# --- 6) RUS RULETİ: masada dönen altıpatar, karşıda bekleyen mahkûmlar ---
static func _rulet(w: Node3D, args: Dictionary) -> void:
	var OT = load("res://scripts/modlar/oyunici_test.gd")
	await OT.run(w, {"ekran": "rulet_hedef", "oyun": "rulet", "hedef": "2", "asama": "2", "bekle": "0.05"})
	var mod = w.game_ui.mod
	var cam := D._kamera(w)
	var merkez := Vector3(3.9, 0.0, 0.0)
	var benim: Vector3 = mod._seat_of(1)
	var yon := (benim - merkez).normalized()
	var yan := yon.cross(Vector3.UP)
	var tt: float = mod._table_top
	var kim := {2: {"govde": "erkek", "sac": "mohawk", "sakal": "pala", "sac_renk": 2, "kiyafet": "turuncu", "ten": 1}, 3: {"govde": "kadin", "sac": "ikiz_orgu", "sac_renk": 5, "aksesuar": "kupe", "kiyafet": "turuncu", "ten": 0}, 4: {"govde": "erkek", "sac": "ayrik", "sakal": "dolgun", "sac_renk": 1, "aksesuar": "gunes", "kiyafet": "turuncu", "ten": 2}}
	for id in kim:
		w._player_entry(id)["g"] = kim[id]
		if w.remotes.has(id):
			w._apply_remote_profile(id)
	mod.on_event({"tur": "sira", "cevir": true, "sira": 1, "cevir_bas": 0, "cevir_ms": 5200, "tohum": int(args.get("tohum", "4242"))})
	var capraz := (yon + yan * float(args.get("yan", "-1.0"))).normalized()
	var kam_yer: Vector3 = merkez + capraz * 0.5 + Vector3(0, tt + 0.16, 0)
	var hedef: Vector3 = merkez - capraz * 0.25 + Vector3(0, tt + D._sec(-0.1, -0.06, -0.08), 0)
	D._kam(cam, kam_yer, hedef, D._sec(74.0, 84.0, 78.0))
	_pozla(w, 0.7)
	await FC._bekle(w, 1.0)
	for id in kim:
		if w.remotes.has(id):
			w.remotes[id].body.set("bakis", merkez + Vector3(0, tt, 0))
			(w.remotes[id].label as Label3D).visible = false
	await FC._bekle(w, float(args.get("an", "4.1")) - 1.0)


# Kürsü (maç sonu ekranındaki gibi: koyu çelik, altın kenar)
static func _kursu(w: Node3D, yer: Vector3, k := 1.0, rakam := true) -> void:
	var ped := CylinderMesh.new()
	ped.top_radius = 0.62 * k
	ped.bottom_radius = 0.7 * k
	ped.height = 0.5
	ped.radial_segments = 48
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color("#1c201d")
	pm.metallic = 0.6
	pm.roughness = 0.4
	var pmi := MeshInstance3D.new()
	pmi.mesh = ped
	pmi.material_override = pm
	w.add_child(pmi)
	pmi.global_position = yer + Vector3(0, 0.25, 0)
	var halka := TorusMesh.new()
	halka.inner_radius = 0.6 * k
	halka.outer_radius = 0.65 * k
	halka.rings = 48
	var rmi := MeshInstance3D.new()
	rmi.mesh = halka
	rmi.material_override = MacSonu._gold_mat()
	w.add_child(rmi)
	rmi.global_position = yer + Vector3(0, 0.5, 0)
	var kapak := CylinderMesh.new()
	kapak.top_radius = 0.6 * k
	kapak.bottom_radius = 0.6 * k
	kapak.height = 0.02
	kapak.radial_segments = 48
	var km := StandardMaterial3D.new()
	km.albedo_color = Color("#4a4f4a")
	km.metallic = 0.5
	km.roughness = 0.45
	var kmi := MeshInstance3D.new()
	kmi.mesh = kapak
	kmi.material_override = km
	w.add_child(kmi)
	kmi.global_position = yer + Vector3(0, 0.505, 0)
	if not rakam:
		return
	var bir := Label3D.new()
	bir.text = "1"
	bir.font = load("res://assets/fonts/RussoOne-Regular.ttf")
	bir.font_size = 160
	bir.pixel_size = 0.0022
	bir.modulate = Color("#ffc23a")
	bir.outline_size = 0
	w.add_child(bir)
	bir.global_position = yer + Vector3(0, 0.25, 0.69 * k)


# --- 7) KARAKTER / KASA: altın tulum + taç, iki yanında başka tarzlar ---
static func _kasa(w: Node3D, args: Dictionary) -> void:
	_koridor_hazir(w)
	var cam := D._kamera(w)
	var zc := 6.0
	w.player.global_position = Vector3(3.9, 0, zc + 8.0)
	_kursu(w, Vector3(3.9, 0, zc), 1.0, false)  # kasa görselinde "1" logoyla çakışıyordu
	var ana: Node3D = FC._mahkum(w, {"govde": "erkek", "sac": "kisa", "sac_renk": 1, "sakal": "dolgun", "kiyafet": "altin", "aksesuar": "zincir", "sapka": "tac", "ten": 1}, Vector3(3.9, 0.5, zc), PI)
	var sol: Node3D = FC._mahkum(w, {"govde": "kadin", "sac": "uzun_duz", "sac_renk": 3, "kiyafet": "leopar", "aksesuar": "kalp", "sapka": "yok", "ten": 0}, Vector3(3.22, 0, zc - 0.55), PI - 0.28)
	var sag: Node3D = FC._mahkum(w, {"govde": "erkek", "sac": "rasta", "sakal": "keci", "ten": 4, "kiyafet": "kamuflaj", "aksesuar": "gunes", "sapka": "viking"}, Vector3(4.6, 0, zc - 0.5), PI + 0.28)
	await w.get_tree().process_frame
	await w.get_tree().process_frame
	var kam_yer := Vector3(3.9, 1.3, zc + 2.7)
	D._kam(cam, kam_yer, Vector3(3.9, D._sec(1.32, 1.62, 1.5), zc), D._sec(40.0, 60.0, 47.0))
	for b in [ana, sol, sag]:
		b.set("bakis", kam_yer + Vector3(0, 0.6, 0))
	(w.get("env") as Environment).glow_enabled = false
	ana.play_emote("kollar")
	sol.play_emote("selam")
	sag.play_emote("kollar")
	D._spot(w, Vector3(3.9, 3.1, zc + 1.2), Vector3(3.9, 1.5, zc), Color(1.0, 0.9, 0.72), 1.1, 30.0, 6.0)
	D._spot(w, Vector3(3.9, 3.1, zc + 2.2), Vector3(3.9, 1.0, zc - 0.5), Color(1.0, 0.94, 0.86), 1.0, 58.0, 7.0)
	D._omni(w, Vector3(3.9, 1.8, zc - 1.8), Color(1.0, 0.62, 0.2), 3.0, 4.0)
	_pozla(w, 0.8)
	await FC._bekle(w, float(args.get("an", "1.1")))


# --- 8) MAÇ SONU: kürsüde taçlı kazanan dans eder, arkadaşları alkışlar ---
static func _macsonu(w: Node3D, args: Dictionary) -> void:
	_koridor_hazir(w)
	var cam := D._kamera(w)
	var zc := 6.0
	w.player.global_position = Vector3(3.9, 0, zc + 8.0)
	_kursu(w, Vector3(3.9, 0, zc), 0.8)
	var ana: Node3D = FC._mahkum(w, {"govde": "kadin", "sac": "ikiz_orgu", "sac_renk": 5, "aksesuar": "kalp", "kiyafet": "pembe", "sapka": "tac", "ten": 0}, Vector3(3.9, 0.5, zc), PI)
	var dost := [
		[{"govde": "erkek", "sac": "ayrik", "sakal": "dolgun", "sac_renk": 1, "kiyafet": "turuncu", "ten": 2, "aksesuar": "gunes"}, Vector3(3.05, 0, zc + 0.0), PI + 0.3, "alkis"],
		[{"govde": "erkek", "sac": "rasta", "ten": 4, "kiyafet": "cizgili"}, Vector3(4.75, 0, zc + 0.0), PI - 0.3, "alkis"],
		[{"govde": "kadin", "sac": "uzun_duz", "sac_renk": 3, "kiyafet": "turuncu", "ten": 2}, Vector3(3.5, 0, zc - 0.85), PI + 0.15, "alkis"],
		[{"govde": "erkek", "sac": "mohawk", "sakal": "pala", "sac_renk": 2, "kiyafet": "kot", "ten": 1}, Vector3(4.35, 0, zc - 0.85), PI - 0.15, "selam"],
	]
	var govdeler := []
	for d in dost:
		govdeler.append(FC._mahkum(w, d[0], d[1], d[2]))
	await w.get_tree().process_frame
	await w.get_tree().process_frame
	var kam_yer := Vector3(3.9, 1.35, zc + 3.1)
	D._kam(cam, kam_yer, Vector3(3.9, D._sec(1.4, 1.62, 1.48), zc), D._sec(42.0, 62.0, 47.0))
	ana.set("bakis", kam_yer + Vector3(0, 0.8, 0))
	ana.play_emote(str(args.get("hareket", "dans")))
	for i in dost.size():
		govdeler[i].set("bakis", ana.global_position + Vector3(0, 1.6, 0))
		govdeler[i].play_emote(dost[i][3])
		govdeler[i].set("talk", 0.7)
	ana.set("talk", 0.7)
	D._spot(w, Vector3(3.9, 3.1, zc + 1.3), Vector3(3.9, 1.5, zc), Color(1.0, 0.82, 0.55), 1.6, 30.0, 6.0)
	D._spot(w, Vector3(3.9, 3.1, zc + 2.6), Vector3(3.9, 1.0, zc), Color(1.0, 0.9, 0.75), 1.3, 62.0, 7.0)
	D._omni(w, Vector3(3.9, 2.0, zc - 2.0), Color(1.0, 0.6, 0.18), 3.0, 4.5)
	_pozla(w, 0.8)
	await FC._bekle(w, float(args.get("an", "0.8")))


# Oyunun kaçış sahnesindeki iğne yapraklı ağaç: gece silueti olarak (ışık almaz, kadrajı çerçeveler)
static func _agac(w: Node3D, p: Vector3, h: float) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.008, 0.016, 0.022)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var gv := MeshInstance3D.new()
	var gc := CylinderMesh.new()
	gc.top_radius = 0.1
	gc.bottom_radius = 0.2
	gc.height = h * 0.45
	gv.mesh = gc
	gv.material_override = m
	w.add_child(gv)
	gv.global_position = p + Vector3(0, h * 0.225, 0)
	for k in 6:
		var kon := MeshInstance3D.new()
		var cc := CylinderMesh.new()
		cc.top_radius = 0.0
		cc.bottom_radius = h * (0.22 - k * 0.028)
		cc.height = h * 0.26
		kon.mesh = cc
		kon.material_override = m
		w.add_child(kon)
		kon.global_position = p + Vector3(0, h * (0.3 + k * 0.125), 0)


# --- Kaçış eki: hücrede kenara çekilmiş klozet ve altındaki çukur (küçük kare) ---
static func _klozet(w: Node3D, _args: Dictionary) -> void:
	var OT = load("res://scripts/modlar/oyunici_test.gd")
	await OT.run(w, {"ekran": "klozet", "oyun": "kacis", "bekle": "0.05"})
	var c: Node3D = w.cells[w.my_cell]
	c.set_detailed(true)
	c.dust.visible = false
	c.dust.emitting = false
	var cam := D._kamera(w)
	var delik: Vector3 = c.klozet_delik.global_position
	var kl: Vector3 = c.klozet_world()
	var yer: Vector3 = delik + Vector3(-0.95, 0.85, 1.05)
	D._kam(cam, yer, delik.lerp(kl, 0.25) + Vector3(0, 0.05, 0), 52.0)
	D._omni(w, delik + Vector3(-0.3, 0.7, 0.5), Color(1.0, 0.86, 0.66), 0.8, 2.5)
	_pozla(w, 0.8)
	await FC._bekle(w, 1.0)


# --- Kaçış eki: hücrenin altındaki tünelde çömelmiş mahkûm (ahşap destekler, çakmak ışığı) ---
static func _tunel(w: Node3D, _args: Dictionary) -> void:
	var OT = load("res://scripts/modlar/oyunici_test.gd")
	await OT.run(w, {"ekran": "tunel", "oyun": "kacis", "bekle": "0.05"})
	var mod = w.game_ui.mod
	await FC._bekle(w, 1.0)
	var kz: Vector2i = mod.klozet_kare(w.my_cell)
	var cam := D._kamera(w)
	var ty: float = mod.TY
	var zo := float(kz.y) + 0.5
	var bx := -4.0
	var b: Node3D = FC._mahkum(w, TT.LOOKS[1], Vector3(bx, ty + 0.02, zo), -PI / 2.0 + 0.3)
	await w.get_tree().process_frame
	b.set("crouched", true)
	var yer := Vector3(bx + 1.75, ty + 0.72, zo + 0.18)
	D._kam(cam, yer, Vector3(bx, ty + 0.55, zo), 58.0)
	b.set("bakis", yer)
	w.player.global_position = Vector3(bx + 6.0, ty + 0.05, zo)
	D._omni(w, Vector3(bx + 0.6, ty + 0.75, zo + 0.25), Color(1.0, 0.68, 0.32), 1.6, 4.0)
	_pozla(w, 1.0)
	await FC._bekle(w, 1.0)
