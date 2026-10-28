# Sinematik fragman çekimleri (2. kuşak: yazısız, anlatıcısız; oyunun kendi sahneleri). fragman_cek.gd çağırır:
#   tools/fragman2.sh <yatay|dikey> <ad> <sure> sahne=<ad>   -> build/fragman2/cek/<yon>/<ad>.avi
# sahne:
#   f2_c4ver   birinci şahıs: hücresindeki mahkum bombayı eline tutuşturur, kapıyı yüzüne çarpar; koşarsın,
#              koridordaki başka birine bombayı verip geri kaçarsın, onun elinde patlar
#   f2_vida    klozetin dibinde çakıyla vida sökülür (yakın çekim), vida döne döne çıkıp yere düşer
#   f2_klozet  yerden alçak açı: klozet kenara çekilir, altında kapkara çukur
#   f2_kazi    tünelde birinci şahıs: kürekle kazı, çakmak titrer, kafa feneri; kayaya vurur
#   f2_kukla   karanlık hücre: yatakta kukla; sayım zili, gardiyanın feneri kapıdan girip kuklada durur, geçer
#   f2_cikis   tel örgünün ötesinde yerden çıkış: projektör, siren, ormana koşu (oyunun kaçış sahnesi)
# Her sahne 1.5 sn hazırlık bekler (kurguda baştan kesilir).
extends RefCounted

const FC := preload("res://tools/fragman_cek.gd")
const TT := preload("res://tools/tiktok_cek.gd")
const Props := preload("res://scripts/modlar/props.gd")
const AimMod := preload("res://scripts/modlar/aim_mod.gd")
const HAZIRLIK := 1.5


static func run(w: Node3D, args: Dictionary, sahne: String) -> void:
	if w.walker:
		w.walker.visible = false
		w.walker.global_position = Vector3(3.9, -20, 0)
	match sahne:
		"f2_c4ver":
			await _c4ver(w)
		"f2_vida":
			await _vida(w)
		"f2_klozet":
			await _klozet(w)
		"f2_kazi":
			await _kazi(w)
		"f2_kukla":
			await _kukla(w)
		"f2_tunel":
			await _tunel(w)
		"f2_cikis":
			await _cikis(w)


static func _kacis_kur(w: Node3D, ekran: String) -> Object:
	var OT = load("res://scripts/modlar/oyunici_test.gd")
	await OT.run(w, {"ekran": ekran, "oyun": "kacis", "bekle": "0.05"})
	return w.game_ui.mod


# --- C4: elden ele ---
# Zaman (hazırlıktan sonra, sn): 0-1.1 uzatır | 1.1 bomba elimde | 1.7 kapı yüzüme çarpar | 2.5-5.0 koşu |
# 5.0 ona veririm | 5.4-6.6 geri kaçarım | 6.9 patlama | 8.5 son
static func _c4ver(w: Node3D) -> void:
	FC._arayuz_gizle(w, 30.0)
	var k := 3
	var c: Node3D = w.cells[k]
	var cz: float = c.global_position.z
	for cc in w.cells:
		cc.set_door(false, true)
	c.set_door(true, true)
	var cam := FC._kamera(w)
	var p: CharacterBody3D = w.player
	p.global_position = Vector3(3.15, 0, cz + 0.5)
	p.rotation.y = PI / 2.0
	# veren: kapının iç ağzında, bana dönük
	var a: Node3D = FC._mahkum(w, TT.LOOKS[2], Vector3(1.75, 0, cz + 0.5), -PI / 2.0)
	# alan: koridorun ilerisinde, sırtı dönük durur
	var bz := cz + 9.0
	var b: Node3D = FC._mahkum(w, TT.LOOKS[3], Vector3(3.7, 0, bz), PI)
	await w.get_tree().process_frame
	var pa: Node = AimMod.of_body(a)
	var bomba := Node3D.new()
	w.add_child(bomba)
	Props.c4(bomba)
	if pa:
		pa.mode = "c4"
		pa.aim_l = 1.0
		pa.hold(0, bomba, AimMod.item_offset("c4", 0))
	var bip := AudioStreamPlayer3D.new()
	bip.stream = load("res://assets/ses/c4_bip.ogg")
	bip.unit_size = 4.0
	bip.volume_db = 1.0
	bomba.add_child(bip)
	var goz := Vector3(3.15, 1.6, cz + 0.5)
	cam.global_transform = TT._bak_xf(goz, a.global_position + Vector3(0, 1.45, 0))
	cam.fov = FC._fv(56.0)
	await FC._bekle(w, HAZIRLIK)

	var T_EL := 1.1
	var T_KAPI := 1.7
	var T_KOS := 2.5
	var T_VER := 5.0
	var T_BUM := 6.9
	var t := 0.0
	var blink_t := 0.0
	var adim_t := 0.0
	var elde := false
	var bde := false
	var patladi := false
	var bomba2: Node3D = null
	var bomba3: Node3D = null
	var pb: Node = AimMod.of_body(b)
	var ben_z := cz + 0.5
	var ben_x := 3.15
	while t < 8.6:
		var d := w.get_process_delta_time()
		a.set("talk", (0.5 + 0.5 * sin(t * 14.0)) if t < T_KAPI else 0.0)
		a.set("bakis", cam.global_position)
		if t < T_EL:
			var base := TT._bak_xf(goz, a.global_position + Vector3(0, 1.4 - t * 0.25, 0))
			TT._el_kamera(cam, base, t, 0.0, 0.006)
			cam.fov = FC._fv(lerpf(56.0, 50.0, t / T_EL))
		elif t < T_KOS:
			if not elde:
				elde = true
				if pa:
					pa.hold(0, null)
					pa.aim_l = 0.0
					pa.mode = ""
				bip.get_parent().remove_child(bip)
				bomba.queue_free()
				bomba2 = Node3D.new()
				Props.c4(bomba2)
				p.body.visible = true
				p.hold_item(0, bomba2, AimMod.item_offset("c4", 0))
				p.set_hand_pose(0, "c4")
				bomba2.add_child(bip)
				TT._ses(w, "kumas", -2.0)
			var u := t - T_EL
			# önce eldeki bombaya bakış, sonra kapı yüzüme kapanır
			var hedef: Vector3 = (bomba2.global_position if u < 0.55 else a.global_position + Vector3(0, 1.5, 0))
			if t >= T_KAPI and c.door_open:
				c.set_door(false)
				var geri := a.create_tween()
				geri.tween_property(a, "global_position", a.global_position + Vector3(-0.9, 0, 0), 0.5)
			var base := TT._bak_xf(goz, hedef)
			TT._el_kamera(cam, base, t, 0.0, 0.01 + (0.03 if t > T_KAPI + 0.7 and t < T_KAPI + 1.0 else 0.0))
			cam.fov = FC._fv(lerpf(50.0, 46.0, clampf(u, 0.0, 1.0)))
		elif t < T_VER:
			# dönüp koridor boyunca koşarım
			var u := t - T_KOS
			var don := FC._yumusak(u / 0.35)
			ben_x = lerpf(3.15, 3.75, don)
			ben_z = minf(ben_z + lerpf(0.0, 5.4, clampf(u * 3.0, 0.0, 1.0)) * d, bz - 1.15)
			adim_t += d
			if adim_t > 0.28 and u > 0.3:
				adim_t = 0.0
				TT._ses(w, "kos_%d" % (randi() % 6), -4.0, randf_range(0.95, 1.05))
			var pos := Vector3(ben_x, 1.6, ben_z)
			var ileri := Vector3(-1, 0, 0).slerp(Vector3(0, 0, 1), don)
			var base := TT._bak_xf(pos, pos + ileri * 5.0 + Vector3(0, -0.2, 0))
			TT._el_kamera(cam, base, t, 1.0 if u > 0.3 else 0.3, 0.012)
			cam.fov = FC._fv(lerpf(46.0, 66.0, don))
			p.global_position = Vector3(pos.x, 0, pos.z - 0.16)
			p.rotation.y = lerpf(PI / 2.0, PI, don)
			# önümdeki duyup döner
			if u > 1.4:
				b.rotation.y = lerp_angle(b.rotation.y, 0.0, d * 6.0)
				b.set("bakis", cam.global_position)
		else:
			var u := t - T_VER
			if not bde:
				bde = true
				p.hold_item(0, null)
				p.set_hand_pose(0, "")
				p.body.visible = false  # kamera geri çekilirken kendi sırtım kadraja girmesin
				bip.get_parent().remove_child(bip)
				bomba2.queue_free()
				bomba3 = Node3D.new()
				w.add_child(bomba3)
				Props.c4(bomba3)
				bomba3.add_child(bip)
				if pb:
					pb.mode = "c4"
					pb.aim_l = 1.0
					pb.hold(0, bomba3, AimMod.item_offset("c4", 0))
				TT._ses(w, "kumas", -2.0)
			b.set("talk", (0.6 + 0.4 * sin(t * 18.0)) if not patladi else 0.0)
			b.set("bakis", cam.global_position)
			# geri geri kaçarım, ona bakarak
			var geri := FC._yumusak(clampf((u - 0.3) / 1.4, 0.0, 1.0)) * 3.2
			var pos := Vector3(3.75, 1.6, bz - 1.15 - geri)
			var base := TT._bak_xf(pos, b.global_position + Vector3(0, 1.35, 0))
			TT._el_kamera(cam, base, t, 0.5 if u > 0.3 else 0.0, 0.01)
			cam.fov = FC._fv(lerpf(66.0, 54.0, FC._yumusak(u / 0.6)))
			if t >= T_BUM and not patladi:
				patladi = true
				if pb:
					pb.hold(0, null)
				bomba3.visible = false
				Props.explosion(w, b.global_position + Vector3(0, 1.0, 0), 0.0)
				b.visible = false
				w._shake(1.4, 0.2)
		# bomba ışığı ve bip: hızlanır
		var hiz := lerpf(1.8, 9.0, clampf(t / T_BUM, 0.0, 1.0))
		var once := blink_t
		blink_t = fmod(blink_t + d * hiz, 1.0)
		var on := blink_t < 0.18
		if not patladi:
			var nd: Node3D = bomba3 if bde else (bomba2 if elde else bomba)
			TT._blink(nd, on, "00:0%d" % maxi(0, 6 - int(t)))
			if blink_t < once and is_instance_valid(bip):
				bip.play()
		await w.get_tree().process_frame
		t += d


# --- Kaçış: vida yakın çekim ---
static func _vida(w: Node3D) -> void:
	FC._arayuz_gizle(w, 20.0)
	var mod = await _kacis_kur(w, "hucre")
	var c: Node3D = w.cells[w.my_cell]
	c.klozet_vida(0)
	var cam := FC._kamera(w)
	var vida: Vector3 = c.klozet_vida_yeri(1)
	var vida2: Vector3 = c.klozet_vida_yeri(3)
	var cak: Node3D = mod._esya_mesh("caki")
	w.add_child(cak)
	cak.global_position = vida + Vector3(-0.05, 0.13, 0.05)
	cak.look_at(vida, Vector3.UP)
	var bas := vida + Vector3(-0.34, 0.13, 0.24)  # klozetin dışından, vidanın yanından
	var bas2 := vida2 + Vector3(0.3, 0.13, 0.24)
	cam.global_transform = TT._bak_xf(bas, vida + Vector3(0, 0.01, 0))
	cam.fov = FC._fv(34.0)
	var dolgu := OmniLight3D.new()  # yakın çekimde vida ve çakı seçilsin
	dolgu.light_color = Color(1.0, 0.86, 0.66)
	dolgu.light_energy = 0.9
	dolgu.omni_range = 1.2
	w.add_child(dolgu)
	dolgu.global_position = vida + Vector3(-0.15, 0.35, 0.3)
	await FC._bekle(w, HAZIRLIK)
	var t := 0.0
	var soktu := false
	var ikinci := false
	while t < 5.2:
		var d := w.get_process_delta_time()
		if t > 0.3 and not soktu:
			soktu = true
			c.klozet_vida_sok(1, 1.6)
			TT._ses(w, "kacis/vida", -1.0)
		if t > 3.0 and not ikinci:
			ikinci = true
			c.klozet_vida_sok(3, 1.4)
			TT._ses(w, "kacis/vida", -2.0)
		var hedef := vida if t < 2.6 else vida2
		var yan := Vector3(-0.05, 0.12, 0.05) if t < 2.6 else Vector3(0.05, 0.12, 0.05)
		cak.global_position = cak.global_position.lerp(hedef + yan + Vector3(0, 0.04 if t > 1.9 and t < 2.6 else 0.0, 0), d * 6.0)
		cak.look_at(hedef, Vector3.UP)
		cak.rotate_object_local(Vector3.FORWARD, t * 9.0)
		var odak := vida.lerp(vida2, FC._yumusak((t - 2.4) / 0.7))
		var pos := bas.lerp(bas2, FC._yumusak((t - 2.4) / 0.7))
		dolgu.global_position = odak + Vector3(0, 0.35, 0.3)
		TT._el_kamera(cam, TT._bak_xf(pos, odak + Vector3(0, 0.01, 0)), t, 0.0, 0.004)
		await w.get_tree().process_frame
		t += d


# --- Kaçış: klozet çekilir, çukur ---
static func _klozet(w: Node3D) -> void:
	FC._arayuz_gizle(w, 20.0)
	await _kacis_kur(w, "hucre")
	var c: Node3D = w.cells[w.my_cell]
	c.klozet_vida(4)
	var cam := FC._kamera(w)
	var kl: Vector3 = c.klozet_world()
	var bas := kl + Vector3(0.3, -0.12, 1.0)  # duvarın iç yüzü x≈1.95: kamera içeride kalsın
	cam.global_transform = TT._bak_xf(bas, kl + Vector3(0, -0.15, 0))
	cam.fov = FC._fv(48.0)
	await FC._bekle(w, HAZIRLIK)
	var t := 0.0
	var acti := false
	while t < 4.2:
		var d := w.get_process_delta_time()
		if t > 0.5 and not acti:
			acti = true
			c.klozet_ac(true)
			TT._ses(w, "kacis/klozet_cek", 0.0)
			w._shake(0.5, 0.02)
		var delik: Vector3 = c.klozet_delik.global_position
		var k := FC._yumusak((t - 1.4) / 2.4)
		var pos := bas.lerp(delik + Vector3(0.12, 0.6, 0.55), k)
		TT._el_kamera(cam, TT._bak_xf(pos, kl.lerp(delik, FC._yumusak((t - 0.6) / 1.2)) + Vector3(0, -0.2, 0)), t, 0.0, 0.006)
		cam.fov = FC._fv(lerpf(48.0, 40.0, k))
		await w.get_tree().process_frame
		t += d


# --- Kaçış: tünelde kazı ---
static func _kazi(w: Node3D) -> void:
	FC._arayuz_gizle(w, 20.0)
	var mod = await _kacis_kur(w, "tunel")
	await FC._bekle(w, 0.9)
	var p: CharacterBody3D = w.player
	var kz: Vector2i = mod.klozet_kare(w.my_cell)
	p.global_position = Vector3(-4.5, mod.TY + 0.05, kz.y + 3.5)  # yan dalın ucu: önü kazılmamış toprak
	p.rotation.y = PI
	p.head.rotation.x = deg_to_rad(-6.0)
	await FC._bekle(w, HAZIRLIK - 0.9)
	var t := 0.0
	var vur := 0.0
	var kaya := false
	mod._eylem("kaz", 2.6, {"kare": [0, 0]}, "")
	while t < 4.6:
		var d := w.get_process_delta_time()
		if t > 2.7 and not kaya:
			kaya = true
			mod._eylem("kaz", 2.0, {"kare": [0, 0]}, "")
			mod._yorgunluk = 0.25
		if t > 3.4 and t - d <= 3.4:
			mod.on_event({"tur": "sert", "ne": "kaya"})
		vur += d
		p.head.rotation.x = deg_to_rad(-6.0 + sin(t * 5.5) * 2.0)
		if is_instance_valid(mod._eldeki):
			mod._eldeki.position.x = 0.07  # dikey kadrajda alet görünsün
		await w.get_tree().process_frame
		t += d


# --- Kaçış: elde kürek, tünelde batıya ilerleyiş (ahşap destekler, çakmak ve fener ışığı) ---
static func _tunel(w: Node3D) -> void:
	FC._arayuz_gizle(w, 20.0)
	var mod = await _kacis_kur(w, "tunel")
	await FC._bekle(w, 0.9)
	var p: CharacterBody3D = w.player
	var kz: Vector2i = mod.klozet_kare(w.my_cell)
	var bas := Vector3(-0.6, mod.TY + 0.05, kz.y + 0.5)
	var son := Vector3(-6.2, mod.TY + 0.05, kz.y + 0.5)
	p.global_position = bas
	p.rotation.y = PI / 2.0
	p.head.rotation.x = deg_to_rad(-4.0)
	mod._ele_al("kurek")
	await FC._bekle(w, HAZIRLIK - 0.9)
	var t := 0.0
	var adim := 0.0
	while t < 4.4:
		var d := w.get_process_delta_time()
		p.global_position = bas.lerp(son, FC._yumusak(t / 4.4))
		p.velocity = Vector3.ZERO
		p.head.rotation.x = deg_to_rad(-4.0 + sin(t * 4.2) * 1.2)
		p.head.rotation.z = sin(t * 2.1) * 0.012
		if is_instance_valid(mod._eldeki):
			mod._eldeki.position = mod.ELDE + Vector3(-0.08, sin(t * 4.2) * 0.008, 0)
		adim += d
		if adim > 0.55:
			adim = 0.0
			TT._ses(w, "adim_%d" % (randi() % 6), -12.0, 0.9)
		await w.get_tree().process_frame
		t += d


# --- Kaçış: sayımda gardiyanın feneri kuklada ---
static func _kukla(w: Node3D) -> void:
	FC._arayuz_gizle(w, 20.0)
	var mod = await _kacis_kur(w, "hucre")
	var c: Node3D = w.cells[w.my_cell]
	mod._kukla_goster(w.my_cell, true)
	# hücre karanlık: yalnız koridorun soluk ışığı

	for l in c.find_children("*", "Light3D", true, false):
		(l as Light3D).visible = false
	var cam := FC._kamera(w)
	var yatak: Vector3 = c.to_global(Vector3(-1.5, 0.7, -1.8))
	var bas: Vector3 = c.to_global(Vector3(-0.2, 1.25, 1.6))
	cam.global_transform = TT._bak_xf(bas, yatak)
	cam.fov = FC._fv(52.0)
	var fener := SpotLight3D.new()
	fener.light_color = Color(0.92, 0.96, 1.0)
	fener.light_energy = 7.0
	fener.spot_angle = 13.0
	fener.spot_range = 9.0
	fener.shadow_enabled = true
	w.add_child(fener)
	fener.global_position = c.to_global(Vector3(1.85, 1.8, 0.55))  # kapının gözetleme deliğinden giren ışık
	var ay := OmniLight3D.new()  # pencereden soluk ay ışığı: kukla karanlıkta seçilsin
	ay.light_color = Color(0.55, 0.65, 0.95)
	ay.light_energy = 0.5
	ay.omni_range = 4.5
	c.add_child(ay)
	ay.position = Vector3(-1.6, 2.3, 0.9)
	fener.look_at(c.to_global(Vector3(0.5, 0.0, 2.6)), Vector3.UP)
	await FC._bekle(w, HAZIRLIK)
	TT._ses(w, "kacis/sayim_zili", -6.0)
	var t := 0.0
	var dedi := false
	while t < 6.0:
		var d := w.get_process_delta_time()
		if t > 0.8 and not dedi:
			dedi = true
			mod._gardiyan_sesi("sayim_geliyor")
		# fener odayı tarar, yatakta durur, sonra çekilir
		var a := c.to_global(Vector3(0.5, 0.0, 2.6))
		var hedef: Vector3
		if t < 2.4:
			hedef = a.lerp(yatak, FC._yumusak((t - 0.6) / 1.8))
		elif t < 4.2:
			hedef = yatak + Vector3(sin(t * 3.0) * 0.04, 0, 0)
		else:
			hedef = yatak.lerp(c.to_global(Vector3(1.2, 0.0, -2.6)), FC._yumusak((t - 4.2) / 1.0))
		fener.look_at(hedef, Vector3.UP)
		fener.visible = t < 5.3
		var k := FC._yumusak((t - 1.5) / 3.0)
		TT._el_kamera(cam, TT._bak_xf(bas.lerp(c.to_global(Vector3(-0.6, 1.1, 0.4)), k), yatak), t, 0.0, 0.004)
		cam.fov = FC._fv(lerpf(52.0, 40.0, k))
		await w.get_tree().process_frame
		t += d


# --- Kaçış: dışarı ---
static func _cikis(w: Node3D) -> void:
	FC._arayuz_gizle(w, 20.0)
	await FC._bekle(w, HAZIRLIK - 0.4)
	var mod = await _kacis_kur(w, "kacis")
	await w.get_tree().process_frame
	w.env.ambient_light_energy = 0.7
	if is_instance_valid(mod._dis):
		for l in mod._dis.find_children("*", "DirectionalLight3D", true, false):
			(l as DirectionalLight3D).light_energy = 2.4
	await FC._bekle(w, 7.5)
