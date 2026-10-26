# Bekleme salonu: hapishane ortak alanı (yemekhane). Duvarda yeşil tebeşir tahtasında oda kodu, çelik masalar ve banklar,
# masaların üstünde sarkan lambalardan tozlu ışık konileri, duvarda televizyon, içecek makinesi, parmaklıklı yüksek
# pencerelerden ay ışığı, demir parmaklıklı çıkış kapısı. Oyuncular oyun başlayana kadar burada.
# Sanat yönü ve telefon bütçesi için yardımcılar: scripts/dunya.gd
extends Node3D

const UI := preload("res://scripts/ui.gd")
const Dunya := preload("res://scripts/dunya.gd")
const W := 14.0
const D := 12.0
const H := 3.6

var w: Node3D  # main.gd: malzemeler ve yardımcılar
var _code: Label3D
var _count: Label3D
var _tv_mat: StandardMaterial3D
var _tv_light: OmniLight3D
var _tv_t := 0.0


func build() -> void:
	var m: Dictionary = w.mats
	var t := 0.2
	# zemin (ıslak boyalı beton), tavan, duvarlar (altı yeşil boyalı, üstünde koyu şerit)
	w.box(Vector3(W + 0.4, t, D + 0.4), Vector3(0, -t / 2, 0), m.corridor_floor, true, self)
	w.box(Vector3(W + 0.4, t, D + 0.4), Vector3(0, H + t / 2, 0), m.ceiling, true, self)
	for side in [-1.0, 1.0]:
		w.box(Vector3(W + 0.4, H, t), Vector3(0, H / 2, side * (D / 2 + 0.1)), m.wall, true, self)
		w.box(Vector3(t, H, D + 0.4), Vector3(side * (W / 2 + 0.1), H / 2, 0), m.wall, true, self)
		w.box(Vector3(W, 1.3, 0.02), Vector3(0, 0.65, side * (D / 2 - 0.01)), m.paint, false, self)
		w.box(Vector3(0.02, 1.3, D), Vector3(side * (W / 2 - 0.01), 0.65, 0), m.paint, false, self)
		w.box(Vector3(W, 0.06, 0.01), Vector3(0, 1.3, side * (D / 2 - 0.02)), m.stripe, false, self)
		w.box(Vector3(0.01, 0.06, D), Vector3(side * (W / 2 - 0.02), 1.3, 0), m.stripe, false, self)
	# tavan kirişleri ve iki kolon (derinlik hissi)
	for x in [-4.6, -1.55, 1.55, 4.6]:
		w.box(Vector3(0.35, 0.32, D), Vector3(x, H - 0.16, 0), m.wall, false, self)
	for p in [Vector3(-4.6, 0, -2.6), Vector3(4.6, 0, -2.6)]:
		w.box(Vector3(0.45, H, 0.45), p + Vector3(0, H / 2, 0), m.wall, true, self)
		w.box(Vector3(0.47, 1.3, 0.47), p + Vector3(0, 0.65, 0), m.paint, false, self)
		w.box(Vector3(0.48, 0.06, 0.48), p + Vector3(0, 1.3, 0), m.stripe, false, self)
	# zeminde sarı yürüme şeridi
	for z in [-3.9, 5.2]:
		w.box(Vector3(W - 1.4, 0.004, 0.07), Vector3(0, 0.002, z), m.yellow_line, false, self)
	for x in [-6.3, 6.3]:
		w.box(Vector3(0.07, 0.004, 9.1), Vector3(x, 0.002, 0.65), m.yellow_line, false, self)

	_build_board()
	for x in [-3.6, 0.0, 3.6]:
		_table(Vector3(x, 0, 1.2))
	for x in [-3.6, 3.6]:
		_table(Vector3(x, 0, 4.0))
	_build_lights()
	_build_tv()
	_build_vending()
	_build_windows()
	_build_gate()
	_build_details()

	# ıslak zemin yansımaları (yüksek kalitede)
	var probe := ReflectionProbe.new()
	probe.size = Vector3(W, H, D)
	probe.position = Vector3(0, H / 2, 0)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.box_projection = true
	probe.interior = true
	probe.intensity = 0.85
	add_child(probe)
	probe.add_to_group(Dunya.YUKSEK)


# Masaların üstünde sarkan lambalar: aşağı bakan spot ışıklar (ışık havuzları), tozlu koniler ve parıltı.
# Tahtayı ayrı bir spot aydınlatır; yan duvarlarda kafesli amber lambalar.
func _build_lights() -> void:
	var spots := [Vector3(-3.6, 0, 1.2), Vector3(0, 0, 1.2), Vector3(3.6, 0, 1.2), Vector3(-3.6, 0, 4.0), Vector3(3.6, 0, 4.0)]
	for i in spots.size():
		var p: Vector3 = spots[i]
		var lamp: Node3D = w.model("hanging_industrial_lamp", p, 0.0, 0.7, H, self)
		var bottom: float = H - w._bounds(lamp, lamp).size.y
		var bulb := MeshInstance3D.new()
		var bs := SphereMesh.new()
		bs.radius = 0.055
		bs.height = 0.11
		bulb.mesh = bs
		bulb.material_override = w._glow(Color("#ffd27a"), 6.0)
		bulb.position = Vector3(p.x, bottom + 0.09, p.z)
		add_child(bulb)
		Dunya.halo(self, Vector3(p.x, bottom + 0.05, p.z), Color("#ffc070"), 0.8, 0.4)
		Dunya.huzme(self, Vector3(p.x, bottom, p.z), H - 0.8, 0.14, 1.4, Color("#ffb45c"), 0.1)
		# her lamba aşağıya ışık havuzu düşürür (spot: ucuz, gölgesiz); sadece ortadaki gölge düşürür
		var l := SpotLight3D.new()
		l.light_color = Color("#ffbd6a")
		l.light_energy = 6.5 if i < 3 else 5.0
		l.spot_range = 6.5
		l.spot_angle = 64.0
		l.spot_attenuation = 0.8
		l.position = Vector3(p.x, bottom - 0.05, p.z)
		l.rotation.x = -PI / 2
		add_child(l)
		if i == 1:
			l.add_to_group(Dunya.GOLGE)
	# tahta ışığı
	var bl := SpotLight3D.new()
	bl.light_color = Color("#ffcf8a")
	bl.light_energy = 7.0
	bl.spot_range = 8.0
	bl.spot_angle = 30.0
	bl.spot_attenuation = 0.7
	bl.position = Vector3(0, H - 0.3, -2.6)
	bl.rotation.x = -deg_to_rad(24)
	add_child(bl)
	# tahtanın iki yanında kafesli lambalar (arka duvarı ve tahtanın kenarlarını aydınlatır)
	for x in [-3.4, 3.4]:
		Dunya.duvar_lambasi(w, self, Vector3(x, 2.7, -D / 2), Vector3.BACK, true, 2.0, 5.0)
	# yan duvar lambaları (her duvarda biri ışık verir)
	for z in [-3.5, 2.6]:
		Dunya.duvar_lambasi(w, self, Vector3(-W / 2, 2.6, z), Vector3.RIGHT, z > 0.0, 1.6, 5.5)
		Dunya.duvar_lambasi(w, self, Vector3(W / 2, 2.6, z), Vector3.LEFT, z < 0.0, 1.4, 5.0)


# Yeşil tebeşir tahtası (yapay zekâ görseli varsa o), üstünde tebeşirle oda kodu.
func _build_board() -> void:
	var z := -D / 2 + 0.06
	var tex := UI.texture("chalkboard")
	if tex:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(5.2, 5.2 * tex.get_height() / float(tex.get_width()))
		q.mesh = qm
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.roughness = 0.9
		q.material_override = mat
		q.position = Vector3(0, 1.95, z)
		add_child(q)
	else:
		w.box(Vector3(4.8, 2.5, 0.06), Vector3(0, 1.95, z), w._flat(Color("#5a3a20"), 0.8), false, self)
		w.box(Vector3(4.4, 2.1, 0.07), Vector3(0, 1.95, z + 0.01), w._flat(Color("#2e5a3c"), 0.95), false, self)
	var chalk := Color(0.96, 0.96, 0.9)
	var head := _chalk_text("BEKLEME SALONU", 70, Vector3(0, 2.65, z + 0.06), chalk.darkened(0.15))
	head.modulate.a = 0.8
	_code = _chalk_text("----", 260, Vector3(0, 1.95, z + 0.06), chalk)
	_count = _chalk_text("0/8 oyuncu", 70, Vector3(0, 1.2, z + 0.06), chalk.darkened(0.1))


func _chalk_text(text: String, size: int, pos: Vector3, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UI.TITLE_FONT
	l.font_size = size
	l.pixel_size = 0.0035
	l.modulate = color
	l.outline_size = 0
	l.position = pos
	l.shaded = false
	add_child(l)
	return l


func set_code(code: String) -> void:
	_code.text = code


func set_count(n: int) -> void:
	_count.text = tr("%d/8 oyuncu") % n


# Çelik yemekhane masası ve iki yanında bank (yere sabit, hapishane tipi).
func _table(p: Vector3) -> void:
	var top: StandardMaterial3D = w.mats.metal_plate
	var metal: StandardMaterial3D = w.mats.metal_dark
	var bench: StandardMaterial3D = w.mats.green_metal
	w.box(Vector3(2.6, 0.06, 0.95), p + Vector3(0, 0.76, 0), top, true, self)
	w.box(Vector3(2.62, 0.04, 0.97), p + Vector3(0, 0.72, 0), metal, false, self)
	for x in [-1.0, 1.0]:
		w.box(Vector3(0.1, 0.72, 0.1), p + Vector3(x, 0.36, 0), metal, false, self)
		w.box(Vector3(0.08, 0.04, 1.9), p + Vector3(x, 0.06, 0), metal, false, self)
	for side in [-1.0, 1.0]:
		w.box(Vector3(2.6, 0.06, 0.34), p + Vector3(0, 0.45, side * 0.78), bench, true, self)
		for x in [-1.0, 1.0]:
			w.box(Vector3(0.06, 0.42, 0.06), p + Vector3(x, 0.21, side * 0.78), metal, false, self)
	# masada teneke bardak ve tepsi (her masada farklı)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p.x * 10.0 + p.z * 100.0)
	var tin: StandardMaterial3D = w._flat(Color("#8c8f93"), 0.4, 0.8)
	for i in rng.randi_range(1, 3):
		var cup: MeshInstance3D = w._disc(self, p + Vector3(rng.randf_range(-1.0, 1.0), 0.84, rng.randf_range(-0.3, 0.3)), 0.04, 0.1, tin)
		cup.rotation.x = 0.0
	if rng.randf() < 0.6:
		var tray: MeshInstance3D = w.box(Vector3(0.45, 0.02, 0.32), p + Vector3(rng.randf_range(-0.8, 0.8), 0.8, rng.randf_range(-0.2, 0.2)), tin, false, self)
		tray.rotation.y = rng.randf_range(-0.4, 0.4)


# Duvarda eski tüplü televizyon (Poly Haven "Television 02", CC0): ekranı yavaşça renk değiştirir, odaya ışık saçar.
func _build_tv() -> void:
	var p := Vector3(W / 2 - 0.05, 2.3, -1.5)
	var tv: Node3D = w.model("television_02", Vector3(p.x - 0.35, 0, p.z), -PI / 2, 2.3, NAN, self)
	var bb: AABB = w._bounds(tv, self)
	tv.position.y = p.y - bb.size.y / 2.0
	tv.position.x += (W / 2 - 0.12) - bb.end.x
	bb = w._bounds(tv, self)
	# duvar rafı
	w.box(Vector3(bb.size.x + 0.15, 0.05, bb.size.z + 0.15), Vector3(bb.get_center().x, bb.position.y - 0.025, bb.get_center().z), w.mats.metal_dark, false, self)
	w.box(Vector3(0.05, 0.4, 0.05), Vector3(W / 2 - 0.05, bb.position.y - 0.2, bb.get_center().z), w.mats.metal_dark, false, self)
	_tv_mat = w._glow(Color("#4a7fc0"), 0.7)
	_tv_mat.albedo_color = Color(0.02, 0.02, 0.03)  # ekran sadece kendi ışığıyla görünsün
	_tv_mat.emission_texture = w._noise_tex(Color(0.55, 0.55, 0.55), Color(1, 1, 1), 0.2, 5)  # eski tüplü ekran karıncası
	var scr := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(bb.size.z * 0.78, bb.size.y * 0.56)
	scr.mesh = q
	scr.material_override = _tv_mat
	scr.position = Vector3(bb.position.x - 0.004, bb.get_center().y + bb.size.y * 0.1, bb.get_center().z)
	scr.rotation.y = -PI / 2
	add_child(scr)
	var l := Label3D.new()
	l.text = "HAT DÜŞTÜ TV"
	l.font = UI.TITLE_FONT
	l.font_size = 32
	l.pixel_size = 0.0022
	l.modulate = Color(1, 1, 1, 0.85)
	l.position = scr.position + Vector3(-0.006, -q.size.y * 0.36, 0)  # ekranın altında kanal yazısı
	l.rotation.y = -PI / 2
	add_child(l)
	_tv_light = OmniLight3D.new()
	_tv_light.light_energy = 0.8
	_tv_light.omni_range = 3.5
	_tv_light.position = scr.position + Vector3(-0.8, 0, 0)
	add_child(_tv_light)


# İçecek makinesi: kırmızı gövde, ışıklı ön panel.
func _build_vending() -> void:
	var p := Vector3(-W / 2 + 0.5, 1.0, -3.8)
	w.box(Vector3(0.9, 2.0, 1.1), p, w._flat(Color("#7d1a1a"), 0.35, 0.3), true, self)
	w.box(Vector3(0.02, 1.2, 0.8), p + Vector3(0.46, 0.25, 0), w._glow(Color("#ffd98a"), 1.4), false, self)
	w.box(Vector3(0.04, 0.5, 0.16), p + Vector3(0.47, -0.25, 0.3), w.mats.metal_dark, false, self)
	w.box(Vector3(0.05, 0.12, 0.6), p + Vector3(0.47, -0.8, -0.1), w.mats.metal_dark, false, self)
	var l := Label3D.new()
	l.text = "SODA"
	l.font = UI.TITLE_FONT
	l.font_size = 90
	l.pixel_size = 0.004
	l.modulate = Color("#ffffff")
	l.position = p + Vector3(0.48, 0.85, 0)
	l.rotation.y = PI / 2
	add_child(l)
	var g := OmniLight3D.new()
	g.light_color = Color("#ffd9a0")
	g.light_energy = 0.7
	g.omni_range = 2.4
	g.position = p + Vector3(0.9, 0.2, 0)
	add_child(g)
	Dunya.leke_zemin(self, "su", Vector3(p.x + 0.8, 0, p.z + 0.2), Vector2(1.0, 0.8), 0.6)


# Arka duvarda (oyuncuların arkasında) parmaklıklı yüksek pencereler, aşağı süzülen ay ışığı.
func _build_windows() -> void:
	for x in [-4.5, 4.5]:
		var p := Vector3(x, 2.65, D / 2 - 0.02)
		w.box(Vector3(1.4, 0.8, 0.03), p, w._glow(Color("#5d7fa8"), 1.3), false, self)
		w.box(Vector3(1.5, 0.06, 0.12), p + Vector3(0, -0.43, -0.05), w.mats.wall, false, self)
		Dunya.parmaklik(self, p + Vector3(-0.6, -0.42, -0.04), Vector3.RIGHT, 7, 0.2, 0.85, 0.018, w.mats.metal_dark, 1)
		Dunya.huzme(self, p + Vector3(0, 0, -0.05), 4.2, 0.55, 1.2, Color("#6f8fc4"), 0.13, null, Vector3(0, -0.65, -1.0))


# Sol duvarda demir parmaklıklı çıkış kapısı; arkasında aydınlık koridor.
func _build_gate() -> void:
	var x := -W / 2 + 0.02
	var z0 := 1.6
	var gw := 1.8
	w.box(Vector3(0.04, 2.5, gw), Vector3(x - 0.02, 1.25, z0 + gw / 2), w._glow(Color("#ffcf8a"), 0.6), false, self)
	Dunya.parmaklik(self, Vector3(x + 0.06, 0, z0 + 0.06), Vector3.BACK, 12, 0.153, 2.45, 0.02, w.mats.door, 3)
	w.box(Vector3(0.16, 0.14, gw + 0.2), Vector3(x + 0.06, 2.5, z0 + gw / 2), w.mats.door, false, self)
	for z in [z0 - 0.04, z0 + gw + 0.04]:
		w.box(Vector3(0.16, 2.55, 0.1), Vector3(x + 0.06, 1.27, z), w.mats.door, false, self)
	Dunya.levha(self, "ÇIKIŞ", Vector3(x + 0.03, 2.85, z0 + gw / 2), PI / 2, Vector2(0.8, 0.26), w.mats.stripe, Color("#e9d9b0"), 100)
	var hz := MeshInstance3D.new()
	var hq := QuadMesh.new()
	hq.size = Vector2(gw, 0.3)
	hz.mesh = hq
	hz.material_override = Dunya.hazard_mat()
	hz.rotation = Vector3(-PI / 2, PI / 2, 0)
	hz.position = Vector3(x + 0.35, 0.004, z0 + gw / 2)
	add_child(hz)


# Borular, levhalar, güvenlik kamerası, lekeler, sahte AO.
func _build_details() -> void:
	var m: Dictionary = w.mats
	Dunya.boru(self, Vector3(-W / 2, H - 0.25, -D / 2 + 0.18), Vector3(W / 2, H - 0.25, -D / 2 + 0.18), 0.08, m.pipe)
	Dunya.boru(self, Vector3(-W / 2, H - 0.12, -D / 2 + 0.38), Vector3(W / 2, H - 0.12, -D / 2 + 0.38), 0.05, m.pipe)
	Dunya.boru(self, Vector3(W / 2 - 0.15, 0, D / 2 - 0.2), Vector3(W / 2 - 0.15, H, D / 2 - 0.2), 0.06, m.pipe)
	var plate: StandardMaterial3D = w._flat(Color("#c9a227"), 0.6, 0.2)
	Dunya.levha(self, "SIRA\nBEKLE", Vector3(-W / 2 + 0.015, 1.9, -1.0), PI / 2, Vector2(0.55, 0.42), plate, Color("#141414"), 70)
	Dunya.levha(self, "B BLOK\nORTAK ALAN", Vector3(3.6, 2.3, -D / 2 + 0.015), 0.0, Vector2(0.9, 0.42), m.stripe, Color("#e9d9b0"), 60)
	Dunya.levha(self, "SİGARA\nİÇİLMEZ", Vector3(W / 2 - 0.015, 1.9, 2.4), -PI / 2, Vector2(0.55, 0.42), plate, Color("#141414"), 60)
	w.model("security_camera_02", Vector3(-W / 2 + 0.4, H - 0.5, -D / 2 + 0.4), PI * 0.75, 0.75, NAN, self)
	var rng := RandomNumberGenerator.new()
	rng.seed = 919
	for i in 10:
		Dunya.leke_zemin(self, "kir", Vector3(rng.randf_range(-6.0, 6.0), 0, rng.randf_range(-5.0, 5.0)), Vector2(1.6, 1.2) * rng.randf_range(0.8, 1.4), rng.randf() * TAU, Color(1, 1, 1, 0.7))
	for p in [Vector3(-1.8, 0, -2.4), Vector3(2.4, 0, 2.7), Vector3(5.6, 0, -4.6)]:
		Dunya.leke_zemin(self, "su", p, Vector2(1.6, 1.1), rng.randf() * TAU)
	for i in 4:
		Dunya.leke_zemin(self, "catlak", Vector3(rng.randf_range(-5.0, 5.0), 0, rng.randf_range(-4.0, 4.5)), Vector2(1.4, 1.4), rng.randf() * TAU)
	for x in [-5.6, -0.6, 4.8]:
		Dunya.leke_duvar(self, "pas", Vector3(x, H - 0.35, -D / 2 + 0.015), Vector3.BACK, Vector2(0.7, 2.0))
	Dunya.ao_ag(self, Dunya.oda_ao_kenarlari(Vector3(-W / 2 + 0.024, 0, -D / 2 + 0.024), Vector3(W / 2 - 0.024, H, D / 2 - 0.024), 0.45, 0.6), 0.55)


func spawn_point(i: int) -> Vector3:
	return to_global(Vector3(-2.0 + (i % 4) * 1.3, 0, 3.0 + (i / 4) * 1.0))


func _process(delta: float) -> void:
	_tv_t += delta
	var c := Color.from_hsv(fmod(_tv_t * 0.05, 1.0), 0.5, 0.6)
	_tv_mat.emission = c
	# ekran titreşimi gibi hafif parlaklık oynaması
	_tv_light.light_color = c
	_tv_light.light_energy = 0.7 + sin(_tv_t * 7.0) * 0.06 + sin(_tv_t * 2.3) * 0.08
