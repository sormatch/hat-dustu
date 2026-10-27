# TikTok / Reels / Shorts reklam çekimleri (build/tiktok). tools/fragman_cek.gd bu dosyayı çağırır:
#   Godot --path . --write-movie build/tiktok/cek/<ad>.avi --fixed-fps 30 -- shot=... profil=tiktok_<x> pose=fragman yon=dikey sahne=<ad>
# sahne:
#   c4kovala   birinci şahıs: mahkum elinde yanıp sönen C4 ile koridorda üstüne koşar, kaçarsın, duvarda
#              yakalar, bombayı eline tutuşturur, sayaç biter, elinde patlar (tek çekim; kurguda bölünür)
#   rulet_don  birinci şahıs Rus ruleti: silah masada döner, namlu sende durur, şakağa (TIK), sonra birine (BAM)
#   rulet_masa masada dönen silaha alçak açıdan yakın plan; namlu kameraya (sana) dönüp durur
#   supheli    kim=1|2|3|4: hücresinde ahizeyi kulağına dayamış, konuşan bir mahkuma yakın plan
#   dolap2     esya=ponpon|bandana: dolap açılır, rafta eşya (Yalancı)
# Her sahne 1.5 sn hazırlık bekler (kurguda baştan kesilir).
extends RefCounted

const FC := preload("res://tools/fragman_cek.gd")
const Props := preload("res://scripts/modlar/props.gd")
const AimMod := preload("res://scripts/modlar/aim_mod.gd")
const ModelScript := preload("res://scripts/model_body.gd")
const Catalog := preload("res://scripts/catalog.gd")
const TelefonScript := preload("res://scripts/telefon.gd")
const HAZIRLIK := 1.5

const LOOKS := {
	1: {"govde": "erkek", "sac": "mohawk", "sakal": "pala", "sac_renk": 2, "kiyafet": "turuncu", "ten": 1},
	2: {"govde": "erkek", "sac": "ayrik", "sakal": "dolgun", "sac_renk": 1, "aksesuar": "gunes", "kiyafet": "turuncu", "ten": 2},
	3: {"govde": "erkek", "sac": "rasta", "sakal": "keci", "ten": 4, "aksesuar": "zincir", "kiyafet": "turuncu"},
	4: {"govde": "kadin", "sac": "ikiz_orgu", "sac_renk": 5, "aksesuar": "kupe", "kiyafet": "turuncu", "ten": 0},
}


static func run(w: Node3D, args: Dictionary, sahne: String) -> void:
	if w.walker:
		w.walker.visible = false
		w.walker.global_position = Vector3(3.9, -20, 0)
	match sahne:
		"c4kovala":
			await _c4kovala(w)
		"rulet_don":
			await _rulet_don(w, args, false)
		"rulet_masa":
			await _rulet_don(w, args, true)
		"supheli":
			await _supheli(w, int(args.get("kim", "1")))
		"dolap2":
			await _dolap2(w, str(args.get("esya", "ponpon")))
		"rulet_ceset":
			await _rulet_ceset(w, args)


# Denetim çekimi (reklam değil): karşıdaki (3) ve yandaki (2) vurulup yığılır; kamera masadaki yerimden
# sırayla ikisine bakar. Baş görünüyor mu (geriye yığılınca omuz arkasına kaçmasın) kontrolü için.
static func _rulet_ceset(w: Node3D, _args: Dictionary) -> void:
	var OT = load("res://scripts/modlar/oyunici_test.gd")
	await OT.run(w, {"ekran": "rulet_hedef", "oyun": "rulet", "hedef": "3", "asama": "2", "bekle": "0.05"})
	var mod = w.game_ui.mod
	FC._arayuz_gizle(w, 20.0)
	await _bakis_cevir(w, mod, 3, 0.3)
	await FC._bekle(w, 0.5)
	mod.on_event({"tur": "atis", "atan": 1, "hedef": 3, "patladi": true, "olen": 3, "sira": 1, "hayatta": [1, 2, 4], "sure": 9})
	await FC._bekle(w, 1.6)
	mod.on_event({"tur": "atis", "atan": 4, "hedef": 2, "patladi": true, "olen": 2, "sira": 4, "hayatta": [1, 4], "sure": 9})
	await FC._bekle(w, 1.0)
	await _bakis_cevir(w, mod, 2, 0.3)
	await FC._bekle(w, 1.2)


# --- yardımcılar ---

static func _ses(w: Node3D, ad: String, db: float, pitch := 1.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = load("res://assets/ses/%s.ogg" % ad)
	p.volume_db = db
	p.pitch_scale = pitch
	p.bus = &"Efekt"
	w.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


static func _ses3d(w: Node3D, ad: String, pos: Vector3, db: float) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = load("res://assets/ses/%s.ogg" % ad)
	p.volume_db = db
	p.unit_size = 3.0
	p.max_distance = 40.0
	p.bus = &"Efekt"
	w.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


# C4 ışığı ve sayaç ekranı (c4_ui._blink gibi). yazi: ekrandaki yazı
static func _blink(node: Node3D, on: bool, yazi: String) -> void:
	if not is_instance_valid(node):
		return
	for b in node.find_children("*", "Node3D", true, false):
		if b.has_meta("led"):
			(b.get_meta("led") as StandardMaterial3D).emission_energy_multiplier = 9.0 if on else 0.2
			(b.get_meta("light") as OmniLight3D).light_energy = 2.2 if on else 0.15
			var scr: Label3D = b.get_meta("ekran")
			scr.text = yazi
			scr.modulate = Color(1.0, 0.18, 0.1, 1.0 if on else 0.6)


# Kameraya el kamerası sarsıntısı + koşu sallantısı ekler (taban dönüşümünün üstüne).
static func _el_kamera(cam: Camera3D, base: Transform3D, t: float, kos: float, titre: float) -> void:
	var adim := t * TAU * 1.55  # saniyede ~3 adım
	var bob := Vector3(sin(adim) * 0.035 * kos, absf(sin(adim)) * 0.06 * kos - 0.03 * kos, 0)
	var n1 := sin(t * 7.3) * 0.6 + sin(t * 13.1 + 1.7) * 0.4
	var n2 := sin(t * 6.1 + 0.4) * 0.6 + sin(t * 11.7 + 2.9) * 0.4
	var rot := Basis.from_euler(Vector3(n1 * titre + sin(adim * 2.0) * 0.012 * kos, n2 * titre, sin(adim) * 0.025 * kos))
	cam.global_transform = Transform3D(base.basis * rot, base.origin + base.basis * bob)


static func _bak_xf(pos: Vector3, hedef: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(hedef - pos, Vector3.UP), pos)


# --- 1) C4 kovalamaca ---
# Zaman çizelgesi (hazırlıktan sonra, sn): 0-1.9 koşarak gelir | 1.9-2.4 dönüp kaçış | 2.4-5.0 koşu |
# 5.0-5.6 omuz üstünden bakış | 5.6-6.4 duvara sırt | 6.4-7.3 karşıda durur, bombayı uzatır |
# 7.3 birinci şahsa geçiş (bomba elde, 3-2-1) | 9.6 patlama | 12.0 son
static func _c4kovala(w: Node3D) -> void:
	FC._arayuz_gizle(w, 30.0)
	for c in w.cells:
		c.set_door(false, true)
	var cam := FC._kamera(w)
	var p: CharacterBody3D = w.player
	# zaman çizelgesi (hazırlıktan sonra)
	var T_DON := 1.7  # kovalayan yaklaştı: dönüp kaçarım
	var T_KAC := 2.15
	var T_BAK := 4.3  # omuz üstünden geriye bakış
	var T_DUR := 4.9  # köşe: durup ona dönerim
	var T_FP := 6.6  # bomba elimde (birinci şahıs)
	var T_BUM := T_FP + 2.4
	var son_z := 21.0
	p.global_position = Vector3(3.9, 0, son_z + 0.16)
	p.rotation.y = 0.0
	p.head.rotation.x = deg_to_rad(-12.0)
	var b: Node3D = FC._mahkum(w, LOOKS[1], Vector3(3.75, 0, 0.0), PI)
	await w.get_tree().process_frame
	var pose: Node = AimMod.of_body(b)
	var bomba := Node3D.new()
	w.add_child(bomba)
	Props.c4(bomba)
	if pose:
		pose.mode = "c4"
		pose.aim_l = 1.0
		pose.hold(0, bomba, AimMod.item_offset("c4", 0))
	var bip := AudioStreamPlayer3D.new()
	bip.stream = load("res://assets/ses/c4_bip.ogg")
	bip.unit_size = 4.0
	bip.max_distance = 40.0
	bip.volume_db = 2.0
	bomba.add_child(bip)
	var cz := 6.5
	cam.global_transform = _bak_xf(Vector3(3.9, 1.62, cz), Vector3(3.8, 1.35, 0.0))
	cam.fov = FC._fv(62.0)
	await FC._bekle(w, HAZIRLIK)

	var t := 0.0
	var blink_t := 0.0
	var adim_t := 0.0
	var ben_adim := 0.0
	var kov_z := 0.0
	var ben_hiz := 0.0
	var fp := false
	var fp_bomba: Node3D = null
	var patladi := false
	var kaz := 0.0  # kovalayanın uzaklaşma yolu
	while t < T_BUM + 2.6:
		var d := w.get_process_delta_time()
		# --- kovalayan: kameranın en fazla "ara" kadar yakınına gelir ---
		if t < T_FP:
			var ara := 2.6
			if t >= T_KAC and t < T_DUR:
				ara = lerpf(4.2, 2.4, clampf((t - T_KAC) / (T_DUR - T_KAC), 0.0, 1.0))
			elif t >= T_DUR:
				ara = lerpf(2.4, 1.3, FC._yumusak((t - T_DUR) / 0.8))
			var sinir := cz - ara
			var onceki := kov_z
			kov_z = minf(kov_z + 6.2 * d, sinir)
			var v := (kov_z - onceki) / maxf(d, 0.001)
			b.global_position = Vector3(3.8 + sin(t * 2.2) * 0.1, 0, kov_z)
			b.rotation.y = PI
			b.set("walk", clampf(v / 2.9, 0.0, 1.95))
			b.set("bakis", cam.global_position)
			b.set("talk", (0.55 + 0.45 * sin(t * 15.0)) if (t < 1.5 or (t > T_DUR + 0.5 and t < T_FP)) else 0.0)
			if v > 2.0:
				adim_t += d
				if adim_t > 0.3:
					adim_t = 0.0
					_ses3d(w, "kos_%d" % (randi() % 6), b.global_position, -2.0)
		else:
			# bombayı verdi: döner ve koşarak kaçar
			var u := t - T_FP
			b.rotation.y = lerp_angle(PI, 0.0, clampf(u / 0.3, 0.0, 1.0))
			if u > 0.2:
				kaz += 5.5 * d
				b.set("walk", 1.95)
				adim_t += d
				if adim_t > 0.3:
					adim_t = 0.0
					_ses3d(w, "kos_%d" % (randi() % 6), b.global_position, -6.0)
			b.global_position = Vector3(3.8, 0, kov_z - kaz)
			b.set("bakis", Vector3.ZERO)
			b.set("talk", 0.0)
		# --- kamera (ben) ---
		if t < T_DON:
			var base := _bak_xf(Vector3(3.9, 1.62, cz), Vector3(3.8, 1.3, kov_z))
			_el_kamera(cam, base, t, 0.0, 0.006 + t * 0.005)
			cam.fov = FC._fv(lerpf(62.0, 54.0, t / T_DON))
		elif t < T_DUR:
			ben_hiz = minf(5.6, ben_hiz + d * 16.0)
			cz = minf(cz + ben_hiz * d, son_z)
			ben_adim += d
			if ben_adim > 0.29:
				ben_adim = 0.0
				_ses(w, "kos_%d" % (randi() % 6), -4.0, randf_range(0.95, 1.05))
			var donus := FC._yumusak((t - T_DON) / 0.4)
			if t > T_BAK:
				donus = 1.0 - FC._yumusak((t - T_BAK) / 0.3) * 0.9
			var yaw := lerpf(0.0, PI, donus)
			var fwd := Vector3(sin(yaw) * 0.15, 0, -cos(yaw))
			var pos := Vector3(3.9 + sin(t * 1.3) * 0.12, 1.6, cz)
			var base := _bak_xf(pos, pos + fwd * 5.0 + Vector3(0, -0.25 * (1.0 - donus) - 0.1, 0))
			_el_kamera(cam, base, t, 1.0 if t > T_KAC else 0.4, 0.012)
			cam.fov = FC._fv(lerpf(54.0, 68.0, FC._yumusak((t - T_DON) / 0.5)))
		elif t < T_FP:
			# köşe: dönerim, soluk soluğa; o gelir, bombayı uzatır
			var u := t - T_DUR
			cz = minf(cz + maxf(0.0, 3.0 - u * 8.0) * d, son_z)
			var pos := Vector3(3.9, 1.6 - 0.03 * sin(u * 9.0), cz)
			var base := _bak_xf(pos, b.global_position + Vector3(0, 1.38 - minf(u, 1.2) * 0.05, 0))
			_el_kamera(cam, base, t, 0.0, 0.025 * exp(-u * 1.5) + 0.006)
			cam.fov = FC._fv(lerpf(68.0, 56.0, FC._yumusak(u / 0.9)))
		else:
			if not fp:
				fp = true
				if pose:
					pose.hold(0, null)
					pose.aim_l = 0.0
					pose.mode = ""
				bip.get_parent().remove_child(bip)
				bomba.queue_free()
				p.global_position = Vector3(3.9, 0, cz + 0.16)
				p.body.visible = true
				fp_bomba = Node3D.new()
				Props.c4(fp_bomba)
				p.hold_item(0, fp_bomba, AimMod.item_offset("c4", 0))
				p.set_hand_pose(0, "c4")
				fp_bomba.add_child(bip)
				_ses(w, "kumas", -2.0)
			var u := t - T_FP
			var k := FC._yumusak((u - 0.45) / 0.55)
			p.head.rotation.x = deg_to_rad(-20.0)
			p.rotation.y = 0.0
			# kamera başın yerinde: önce kaçan kovalayana, sonra eldeki bombaya bakar (dikey kadrajda bomba ortada)
			var goz: Vector3 = p.camera.global_position
			var bh: Vector3 = fp_bomba.global_position if is_instance_valid(fp_bomba) and not patladi else goz + Vector3(0, -0.5, -0.4)
			var h1: Vector3 = b.global_position + Vector3(0, 1.2, 0)
			var base := _bak_xf(goz, h1.lerp(bh + Vector3(0, 0.02, 0), k))
			_el_kamera(cam, base, t, 0.0, 0.008 + 0.01 * k)
			cam.fov = FC._fv(lerpf(60.0, 44.0, k))
			if u >= T_BUM - T_FP and not patladi:
				patladi = true
				var fwd3: Vector3 = -p.camera.global_transform.basis.z
				var pos3: Vector3 = p.global_position + Vector3(0, 1.0, 0) + Vector3(fwd3.x, 0, fwd3.z).normalized() * 1.1
				p.hold_item(0, null)
				p.set_hand_pose(0, "")
				fp_bomba.visible = false
				Props.explosion(w, pos3, 0.0)
				w._shake(1.6, 0.22)
		# --- bomba ışığı ve bip: elimde gittikçe hızlanır ---
		var hiz := 1.7 if t < T_FP else lerpf(2.6, 9.0, clampf((t - T_FP) / (T_BUM - T_FP), 0.0, 1.0))
		var once := blink_t
		blink_t = fmod(blink_t + d * hiz, 1.0)
		var on := blink_t < 0.18
		var yazi := "ARM" if t < T_FP else "00:%02d" % maxi(0, 3 - int((t - T_FP) / ((T_BUM - T_FP) / 3.0)))
		if not patladi:
			_blink(fp_bomba if fp else bomba, on, yazi)
			if blink_t < once and is_instance_valid(bip):
				bip.play()
		await w.get_tree().process_frame
		t += d


# --- 2) Rus ruleti (oyunun kendi masası ve dönen silahı) ---
static func _rulet_don(w: Node3D, args: Dictionary, sinematik: bool) -> void:
	FC._arayuz_gizle(w, 40.0)
	var OT = load("res://scripts/modlar/oyunici_test.gd")
	await OT.run(w, {"ekran": "rulet_hedef", "oyun": "rulet", "hedef": "2", "asama": "2", "bekle": "0.05"})
	var mod = w.game_ui.mod
	var p: CharacterBody3D = w.player
	var cam: Camera3D = null
	var merkez := Vector3(3.9, 0.0, 0.0)
	if sinematik:
		cam = FC._kamera(w)
		var benim: Vector3 = mod._seat_of(1)
		var yon := (benim - merkez).normalized()
		var tt: float = mod._table_top
		var a := merkez + yon * 0.62 + Vector3(0, tt + 0.16, 0)
		cam.global_transform = _bak_xf(a, merkez + Vector3(0, tt + 0.02, 0))
		cam.fov = FC._fv(46.0)
	await FC._bekle(w, maxf(0.1, HAZIRLIK - 1.25))
	# silah elimden masaya kayar, döner, namlu bende durur
	mod.on_event({"tur": "sira", "cevir": true, "sira": 1, "cevir_bas": 0, "cevir_ms": 5200, "tohum": int(args.get("tohum", "4242"))})
	if sinematik:
		var benim2: Vector3 = mod._seat_of(1)
		var yon2 := (benim2 - merkez).normalized()
		var tt2: float = mod._table_top
		var a2 := merkez + yon2 * 0.62 + Vector3(0, tt2 + 0.16, 0)
		var b2 := merkez + yon2 * 0.42 + Vector3(0, tt2 + 0.1, 0)
		await FC._kaydir(w, cam, a2, b2, merkez + Vector3(0, tt2 + 0.02, 0), merkez + Vector3(0, tt2 + 0.03, 0), 4.6, 46.0, 38.0, 0.002)
		await FC._bekle(w, 1.5)
		return
	await FC._bekle(w, 5.4)
	# masadakilerin yüzlerine sırayla bakış (gerilim)
	await _bakis_cevir(w, mod, 2, 0.7)
	await FC._bekle(w, 0.35)
	await _bakis_cevir(w, mod, 4, 0.8)
	await FC._bekle(w, 0.35)
	# namlu şakakta (dikey kadraja göre kameraya bağlı altıpatar): horoz, tambur döner, TIK
	var sk := Node3D.new()
	Props.revolver(sk)
	p.camera.add_child(sk)
	p._fp_layers(sk, false)
	var xf := Transform3D(Basis.looking_at(Vector3(0.75, 0.42, 0.62).normalized(), Vector3.UP) * Basis(Vector3.BACK, deg_to_rad(-14.0)), Vector3(0.055, -0.045, -0.36))
	sk.transform = Transform3D(xf.basis, xf.origin + Vector3(0.12, -0.1, 0.02))
	sk.create_tween().tween_property(sk, "transform", xf, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var isik := OmniLight3D.new()
	isik.light_color = Color(1.0, 0.85, 0.65)
	isik.light_energy = 0.35
	isik.omni_range = 0.8
	isik.light_cull_mask = p.FP_LAYER
	isik.position = Vector3(-0.05, 0.12, 0.05)
	sk.add_child(isik)
	if is_instance_valid(mod._gun):
		mod._gun.visible = false
	if p.body.has_method("set_fp_hide"):
		p.body.call("set_fp_hide", true)
	var fov0: float = p.camera.fov
	var tw := p.create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(p.head, "rotation:z", deg_to_rad(-4.0), 0.35)
	tw.tween_property(p.head, "rotation:x", deg_to_rad(-2.0), 0.35)
	tw.tween_property(p.camera, "fov", fov0 - 8.0, 2.4)
	_ses(w, "horoz", -2.0)
	await FC._bekle(w, 0.5)
	_ses(w, "tambur", -1.0)
	var tb: Node3D = sk.find_child("tambur", true, false)
	if tb:
		tb.create_tween().tween_property(tb, "rotation:z", tb.rotation.z + TAU * 3.0, 1.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_ses(w, "kalp", 2.0, 1.2)
	await FC._bekle(w, 1.0)
	_ses(w, "kalp", 2.0, 1.3)
	await FC._bekle(w, 0.95)
	_ses(w, "bos_tetik", 4.0)
	var kick := Transform3D(xf.basis.rotated(Vector3.BACK, deg_to_rad(-9.0)), xf.origin + Vector3(0.03, 0.025, 0.01))
	var tw2 := sk.create_tween()
	tw2.tween_property(sk, "transform", kick, 0.04)
	tw2.tween_property(sk, "transform", xf, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await FC._bekle(w, 1.2)
	sk.queue_free()
	if is_instance_valid(mod._gun):
		mod._gun.visible = true
	if p.body.has_method("set_fp_hide"):
		p.body.call("set_fp_hide", false)
	var tw3 := p.create_tween().set_parallel()
	tw3.tween_property(p.head, "rotation:z", 0.0, 0.25)
	tw3.tween_property(p.camera, "fov", fov0, 0.25)
	# başkasına doğrult: BAM
	await _bakis_cevir(w, mod, 3, 0.45)
	await FC._bekle(w, 1.4)
	mod.on_event({"tur": "atis", "atan": 1, "hedef": 3, "patladi": true, "olen": 3, "sira": 1, "hayatta": [1, 2, 4], "sure": 9})
	await FC._bekle(w, 3.5)


# Oyuncunun bakışını yumuşakça bir oyuncunun başına çevirir (silah eli de ona doğrulur).
static func _bakis_cevir(w: Node3D, mod, id: int, sure: float) -> void:
	var p: CharacterBody3D = w.player
	var y0: float = p.rotation.y
	var x0: float = p.head.rotation.x
	mod._look_at(id)  # hedef açıyı bul (iki geçiş), sonra geri al ve yumuşakça çevir
	var y1: float = p.rotation.y
	var x1: float = p.head.rotation.x
	p.rotation.y = y0
	p.head.rotation.x = x0
	var t := 0.0
	while t < sure:
		var e := FC._yumusak(t / sure)
		p.rotation.y = lerp_angle(y0, y1, e)
		p.head.rotation.x = lerpf(x0, x1, e)
		await w.get_tree().process_frame
		t += w.get_process_delta_time()
	p.rotation.y = y1
	p.head.rotation.x = x1


# --- 3) Şüpheli: hücresinde telefonla konuşan mahkum (yakın plan) ---
static func _supheli(w: Node3D, kim: int) -> void:
	var c: Node3D = w.cells[(kim + 1) % w.cells.size()]
	var cam := FC._kamera(w)
	w.player.global_position = w.cells[6].spawn_world() if kim != 3 else w.cells[5].spawn_world()
	var ph: Vector3 = c.phone_world()
	var mp: Vector3 = c.to_global(Vector3(-0.55, 0, -0.75))
	var dd: Vector3 = ph - mp
	var yaw := atan2(-dd.x, -dd.z) + 0.9  # telefona yan, kameraya yarı dönük
	var b: Node3D = FC._mahkum(w, LOOKS.get(kim, LOOKS[1]), mp, yaw)
	await w.get_tree().process_frame
	var pose: Node = AimMod.of_body(b)
	var ahize := Node3D.new()
	ahize.name = "UzakAhize"
	w.add_child(ahize)
	var h: Node3D = TelefonScript.handset(ahize)
	h.scale = Vector3.ONE * TelefonScript.SCALE
	h.get_node("kablo_ucu").reparent(ahize)
	if pose:
		pose.mode = "ahize"
		pose.aim = 1.0
		pose.hold(1, ahize, AimMod.item_offset("ahize", 1))
	c.set_handset_lifted(true, ahize)
	var bas: Vector3 = mp + Vector3(0, 1.55, 0)
	var ileri := Vector3(-sin(yaw), 0, -cos(yaw))
	var a := bas + ileri * 1.25 + Vector3(0, 0.02, 0) + ileri.cross(Vector3.UP) * 0.25
	var bb := bas + ileri * 0.8 + Vector3(0, 0.0, 0) + ileri.cross(Vector3.UP) * 0.12
	cam.global_transform = _bak_xf(a, bas)
	cam.fov = FC._fv(44.0)
	b.set("bakis", a)
	var t := 0.0
	var gor := 0.0
	await FC._bekle(w, HAZIRLIK)
	while t < 4.5:
		var d := w.get_process_delta_time()
		var e := FC._yumusak(t / 4.5)
		cam.global_transform = _bak_xf(a.lerp(bb, e) + Vector3(sin(t * 1.3) * 0.004, sin(t * 1.9) * 0.003, 0), bas + Vector3(0, -0.02, 0))
		cam.fov = FC._fv(lerpf(44.0, 38.0, e))
		gor += d
		b.set("talk", clampf(0.5 + 0.5 * sin(t * 11.0) * sin(t * 3.1 + 1.0), 0.0, 1.0))
		await w.get_tree().process_frame
		t += d


# --- 4) Dolap (Yalancı): kapak açılır, rafta eşya ---
static func _dolap2(w: Node3D, esya: String) -> void:
	var c: Node3D = w.cells[0]
	c.set_locker_item(esya)
	var cam := FC._kamera(w)
	w.player.global_position = w.cells[6].spawn_world()
	var lp: Vector3 = c.locker_world()
	var a: Vector3 = c.to_global(Vector3(0.45, 1.5, 0.75))
	var b: Vector3 = c.to_global(Vector3(-0.3, 1.36, 0.3))
	cam.global_position = a
	cam.look_at(lp, Vector3.UP)
	cam.fov = FC._fv(56.0)
	await FC._bekle(w, HAZIRLIK - 0.3)
	c.set_locker(true)
	await FC._bekle(w, 0.3)
	await FC._kaydir(w, cam, a, b, lp + Vector3(0, -0.1, 0), lp + Vector3(0, -0.02, 0), 3.5, 56.0, 42.0, 0.005)
