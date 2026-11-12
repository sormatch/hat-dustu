# 30 sn'lik reklam için yeni sinematik sahneler (tools/tanitim_cek.sh ile, sinema modunda çekilir):
#   r_kam      kim=1..4: güvenlik kamerası (tavan köşesi) hücresindeki mahkûma bakar; mahkûm tedirgin bakınır, sonda
#              kameraya döner. Şapkalar: 1, 2, 4 mavi kep; 3 sarı baret (farklı olan: "kim yalan söylüyor").
#   r_c4kos    koridor, dışarıdan: C4'lü mahkûm koşarak gelir; biri hücresine dalıp kapıyı kapatır, biri kaçar;
#              bombacı kapıya vurur, sonra kameraya koşar.
#   r_gardiyan karanlık koridor: gardiyan fenerle yürüyerek gelir, bir hücrenin camından bakar, devam eder.
# Her sahne 1.5 sn hazırlık bekler (kurguda baştan kesilir).
extends RefCounted

const FC := preload("res://tools/fragman_cek.gd")
const TT := preload("res://tools/tiktok_cek.gd")
const AimMod := preload("res://scripts/modlar/aim_mod.gd")
const Props := preload("res://scripts/modlar/props.gd")
const BodyScript := preload("res://scripts/model_body.gd")
const Catalog := preload("res://scripts/catalog.gd")
const HAZIRLIK := 1.5
const KAPI_CAMI := Vector3(2.75, 0, 0.5)  # kacis_ui.gd ile aynı: hücre kapısı camının önü (koridor)


static func run(w: Node3D, args: Dictionary, sahne: String) -> void:
	if w.walker:
		w.walker.visible = false
		w.walker.global_position = Vector3(3.9, -20, 0)
	FC._arayuz_gizle(w, 30.0)
	match sahne:
		"r_kam":
			await _kam(w, int(args.get("kim", "1")))
		"r_c4kos":
			await _c4kos(w)
		"r_gardiyan":
			await _gardiyan(w)


static func _yaw_bak(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return atan2(-d.x, -d.z)


# --- 1) güvenlik kamerası ---
static func _kam(w: Node3D, kim: int) -> void:
	var c: Node3D = w.cells[clampi(kim + 1, 0, w.cells.size() - 1)]
	for cc in w.cells:
		cc.set_door(false, true)
	w.player.global_position = Vector3(3.9, 0, 30.0)
	var look: Dictionary = TT.LOOKS[clampi(kim, 1, 4)].duplicate()
	look["sapka"] = "baret" if kim == 3 else "kep"
	var yer: Vector3 = c.to_global(Vector3(0.35, 0, 0.55))
	var kam_yer: Vector3 = c.to_global(Vector3(1.55, 2.45, 2.25))
	var m: Node3D = FC._mahkum(w, look, yer, _yaw_bak(yer, c.to_global(Vector3(0.6, 0, 1.6))))
	var cam := FC._kamera(w)
	var bas := yer + Vector3(0, 1.55, 0)
	cam.global_transform = TT._bak_xf(kam_yer, bas + Vector3(0, -0.15, 0))
	cam.fov = FC._fv(40.0)
	await FC._bekle(w, HAZIRLIK)
	var t := 0.0
	# bakınma noktaları: kapı, yatak, tavan, sonra kameraya
	var noktalar := [c.to_global(Vector3(2.2, 1.5, 1.0)), c.to_global(Vector3(-1.5, 0.9, -1.8)), c.to_global(Vector3(1.5, 1.7, -1.5)), kam_yer]
	while t < 5.0:
		var d := w.get_process_delta_time()
		var i := clampi(int(t / 1.1), 0, 3)
		var hedef: Vector3 = noktalar[i]
		m.set("bakis", hedef)
		# son bölümde gövde de kameraya döner
		m.rotation.y = lerp_angle(m.rotation.y, _yaw_bak(yer, hedef), clampf(d * (4.0 if i == 3 else 2.2), 0.0, 1.0))
		m.set("talk", 0.0)
		var k := FC._yumusak(t / 5.0)
		cam.global_transform = TT._bak_xf(kam_yer.lerp(kam_yer + (bas - kam_yer) * 0.12, k), bas + Vector3(0, -0.15, 0))
		await w.get_tree().process_frame
		t += d


# --- 2) C4 kovalamaca (dışarıdan) ---
static func _c4kos(w: Node3D) -> void:
	for cc in w.cells:
		cc.set_door(false, true)
	var c5: Node3D = w.cells[5]
	c5.set_door(true, true)
	w.player.global_position = Vector3(3.9, 0, -30.0)
	var kapi: Vector3 = c5.to_global(KAPI_CAMI)
	var z0 := kapi.z
	var ic: Vector3 = c5.to_global(Vector3(0.4, 0, 0.5))
	var a: Node3D = FC._mahkum(w, TT.LOOKS[1], Vector3(3.8, 0, z0 + 10.0), PI)
	var b: Node3D = FC._mahkum(w, TT.LOOKS[4], Vector3(3.6, 0, z0 + 1.8), 0.0)
	var cc2: Node3D = FC._mahkum(w, TT.LOOKS[2], Vector3(4.15, 0, z0 - 0.6), 0.0)
	await w.get_tree().process_frame
	var pose: Node = AimMod.of_body(a)
	var bomba := Node3D.new()
	w.add_child(bomba)
	Props.c4(bomba)
	if pose:
		pose.mode = "c4"
		pose.aim_l = 1.0
		pose.hold(0, bomba, AimMod.item_offset("c4", 0))
	var bip := AudioStreamPlayer3D.new()
	bip.stream = load("res://assets/ses/c4_bip.ogg")
	bip.unit_size = 5.0
	bip.max_distance = 40.0
	bomba.add_child(bip)
	var cam := FC._kamera(w)
	var kam0 := Vector3(4.65, 1.0, z0 - 3.6)
	cam.global_transform = TT._bak_xf(kam0, Vector3(3.7, 1.25, z0 + 3.0))
	cam.fov = FC._fv(58.0)
	await FC._bekle(w, HAZIRLIK)
	var t := 0.0
	var bip_t := 0.0
	var adim_t := 0.0
	var kapandi := false
	var a_pos: Vector3 = a.global_position
	var b_pos: Vector3 = b.global_position
	var c_pos: Vector3 = cc2.global_position
	while t < 6.2:
		var d := w.get_process_delta_time()
		# bombacı A: koşar, kapıya varır, vurur, döner ve kameraya koşar
		var a_hiz := 0.0
		if t < 1.75:
			var hedef := Vector3(3.3, 0, z0 + 0.6)
			var yon := (hedef - a_pos)
			var adim := minf(yon.length(), 5.4 * d)
			a_pos += yon.normalized() * adim
			a_hiz = adim / maxf(d, 0.001)
			a.rotation.y = _yaw_bak(a_pos, a_pos + yon)
		elif t < 2.9:
			a.rotation.y = lerp_angle(a.rotation.y, PI / 2.0, clampf(d * 8.0, 0.0, 1.0))  # kapıya döner
			a.set("talk", 0.6 + 0.4 * sin(t * 16.0))
			a_pos.x = 3.3 + sin(t * 18.0) * 0.03  # kapıya vurur
			if fmod(t, 0.35) < d:
				TT._ses3d(w, "carpma", kapi, 2.0)
		else:
			a.set("talk", 0.0)
			var hedef2 := Vector3(4.15, 0, kam0.z + 1.5)
			var yon2 := (hedef2 - a_pos)
			var adim2 := minf(yon2.length(), 5.0 * d)
			a_pos += yon2.normalized() * adim2
			a_hiz = adim2 / maxf(d, 0.001)
			a.rotation.y = lerp_angle(a.rotation.y, _yaw_bak(a_pos, kam0), clampf(d * 6.0, 0.0, 1.0))
			a.set("bakis", cam.global_position)
		a.global_position = a_pos
		a.set("walk", clampf(a_hiz / 2.9, 0.0, 1.95))
		# B: döner, hücresine dalar, kapı kapanır
		var b_hiz := 0.0
		if t > 0.35 and t < 2.0:
			var hedef_b: Vector3 = kapi if b_pos.distance_to(kapi) > 0.4 and t < 1.0 else ic
			var yb := hedef_b - b_pos
			var ab := minf(yb.length(), 5.0 * d)
			b_pos += yb.normalized() * ab
			b_hiz = ab / maxf(d, 0.001)
			if yb.length() > 0.05:
				b.rotation.y = _yaw_bak(b_pos, hedef_b)
		elif t <= 0.35:
			b.rotation.y = PI  # bombacıya bakar
			b.set("talk", 0.8)
		b.global_position = b_pos
		b.set("walk", clampf(b_hiz / 2.9, 0.0, 1.95))
		if t > 1.95 and not kapandi:
			kapandi = true
			b.set("talk", 0.0)
			c5.set_door(false)
		# C: döner, kameranın yanından kaçar
		var c_hiz := 0.0
		if t > 0.6:
			var hedef_c := Vector3(4.9, 0, kam0.z - 4.0)
			var yc := hedef_c - c_pos
			var ac := minf(yc.length(), 5.6 * d)
			c_pos += yc.normalized() * ac
			c_hiz = ac / maxf(d, 0.001)
			cc2.rotation.y = _yaw_bak(c_pos, hedef_c)
		else:
			cc2.rotation.y = PI
		cc2.global_position = c_pos
		cc2.set("walk", clampf(c_hiz / 2.9, 0.0, 1.95))
		# ayak sesleri, bip (sona doğru hızlanır)
		adim_t += d
		if adim_t > 0.28 and (a_hiz > 2.0 or b_hiz > 2.0 or c_hiz > 2.0):
			adim_t = 0.0
			TT._ses3d(w, "kos_%d" % (randi() % 6), a_pos if a_hiz > 2.0 else c_pos, -4.0)
		bip_t += d
		if bip_t > lerpf(0.5, 0.14, clampf(t / 6.0, 0.0, 1.0)):
			bip_t = 0.0
			bip.play()
		# kamera: alçak açı, yavaşça geri çekilir; sonda bombacıya
		var k := FC._yumusak(t / 6.2)
		var kp := kam0 + Vector3(0.05, 0.0, -0.6) * k
		var bakis := Vector3(3.7, 1.25, z0 + 3.0).lerp(a_pos + Vector3(0, 1.3, 0), FC._yumusak((t - 2.6) / 1.2))
		TT._el_kamera(cam, TT._bak_xf(kp, bakis), t, 0.5 if t > 2.9 else 0.2, 0.006)
		await w.get_tree().process_frame
		t += d


# --- 3) gardiyan fenerle gelir ---
static func _gardiyan(w: Node3D) -> void:
	for cc in w.cells:
		cc.set_door(false, true)
	w.player.global_position = Vector3(3.9, 0, -30.0)
	# gece: koridor ışıkları kısık
	for it in FC._isiklar(w):
		(it[0] as Light3D).light_energy = float(it[1]) * 0.6
	var g: Node3D = BodyScript.new()
	g.look = Catalog.sanitize({"govde": "erkek", "kiyafet": "gardiyan", "sapka": "kep", "sakal": "biyik", "sac": "kisa", "ten": 2})
	w.add_child(g)
	var fener := SpotLight3D.new()
	fener.light_color = Color(0.95, 0.97, 1.0)
	fener.light_energy = 4.0
	fener.spot_angle = 17.0
	fener.spot_range = 11.0
	fener.shadow_enabled = true
	w.add_child(fener)
	var yuz := OmniLight3D.new()
	yuz.light_color = Color(1.0, 0.9, 0.78)
	yuz.light_energy = 1.6
	yuz.omni_range = 1.8
	g.add_child(yuz)
	yuz.position = Vector3(0, 1.62, -0.35)
	var c4: Node3D = w.cells[4]
	var kapi: Vector3 = c4.to_global(KAPI_CAMI)
	var bas_z := kapi.z + 8.5
	var g_pos := Vector3(3.75, 0, bas_z)
	g.global_position = g_pos
	g.rotation.y = 0.0
	var cam := FC._kamera(w)
	var kp := Vector3(4.55, 1.0, kapi.z - 3.8)
	cam.global_transform = TT._bak_xf(kp, Vector3(3.7, 1.4, kapi.z + 4.0))
	cam.fov = FC._fv(46.0)
	await FC._bekle(w, HAZIRLIK)
	var t := 0.0
	var adim_t := 0.0
	var durak := Vector3(3.15, 0, kapi.z)
	while t < 7.5:
		var d := w.get_process_delta_time()
		var hiz := 0.0
		var hedef_bak: Vector3
		if t < 3.6:
			var yon := durak - g_pos
			var adim := minf(yon.length(), 1.6 * d)
			g_pos += yon.normalized() * adim
			hiz = adim / maxf(d, 0.001)
			g.rotation.y = _yaw_bak(g_pos, g_pos + Vector3(0, 0, -1))
			# fener yürürken kapıları ve yeri tarar
			hedef_bak = g_pos + Vector3(-1.6 + sin(t * 1.7) * 1.2, -0.2, -3.0)
		elif t < 5.6:
			g.rotation.y = lerp_angle(g.rotation.y, PI / 2.0, clampf(d * 5.0, 0.0, 1.0))  # cama döner
			hedef_bak = c4.to_global(Vector3(-0.5, 0.8, -1.0))
		else:
			var yon2 := Vector3(3.75, 0, kp.z - 3.0) - g_pos
			var adim2 := minf(yon2.length(), 1.4 * d)
			g_pos += yon2.normalized() * adim2
			hiz = adim2 / maxf(d, 0.001)
			g.rotation.y = lerp_angle(g.rotation.y, 0.0, clampf(d * 4.0, 0.0, 1.0))
			hedef_bak = g_pos + Vector3(0.3, -0.4, -3.0)
		g.global_position = g_pos
		g.set("walk", clampf(hiz / 2.9, 0.0, 1.0))
		g.set("bakis", hedef_bak)
		fener.global_position = g_pos + Vector3(0, 1.35, 0) + Vector3(0, 0, -0.25).rotated(Vector3.UP, g.rotation.y)
		if not fener.global_position.is_equal_approx(hedef_bak):
			fener.look_at(hedef_bak, Vector3.UP)
		adim_t += d
		if hiz > 0.5 and adim_t > 0.55:
			adim_t = 0.0
			TT._ses3d(w, "adim_%d" % (randi() % 6), g_pos, -2.0)
		# kamera: alçak, kapı hizasına doğru çok yavaş itme
		var k := FC._yumusak(t / 7.5)
		TT._el_kamera(cam, TT._bak_xf(kp + Vector3(0, 0, 0.8) * k, g_pos + Vector3(0, 1.35, 0)), t, 0.0, 0.004)
		await w.get_tree().process_frame
		t += d
