# Hücredeki duvar telefonu: kalıp gövde, çevirmeli kadran, ahize çatalı, ahize ve kıvırcık spiral kablo.
# Ahize modeli hem duvarda hem oyuncunun elinde aynıdır (handset()).
# Kablo (Cord) her karede iki uç arasında yeniden örülür: uçlar yakınken sarkan bir halka olur,
# uzaklaştıkça sarmal açılır, incelir ve gerilir.
extends RefCounted

const SCALE := 1.15  # telefonun duvardaki ölçeği (ahize elde de aynı boyda)
const CORD_MAX := 2.6  # kablonun gerilip açılabildiği en uzun mesafe (m)

static var _mats := {}


static func mat(id: String) -> StandardMaterial3D:
	if _mats.has(id):
		return _mats[id]
	var m := StandardMaterial3D.new()
	match id:
		"govde":  # parlak kırmızı bakalit
			m.albedo_color = Color("#a80f16")
			m.roughness = 0.22
			m.clearcoat_enabled = true
			m.clearcoat = 0.6
			m.clearcoat_roughness = 0.15
		"koyu":
			m.albedo_color = Color("#6e0a0f")
			m.roughness = 0.4
		"krom":
			m.albedo_color = Color("#c9ccd1")
			m.metallic = 1.0
			m.roughness = 0.18
		"kadran":  # numara plakası: fildişi
			m.albedo_color = Color("#ece4cf")
			m.roughness = 0.45
		"siyah":
			m.albedo_color = Color("#141414")
			m.roughness = 0.55
		"izgara":  # ahize ağzındaki delikli kapak
			m.albedo_color = Color("#2a0607")
			m.roughness = 0.6
		"kablo":
			m.albedo_color = Color("#b3121a")
			m.roughness = 0.3
			m.clearcoat_enabled = true
			m.clearcoat = 0.4
	_mats[id] = m
	return m


static func _mi(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func _cyl(r1: float, r2: float, h: float, segs := 28) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r1
	c.bottom_radius = r2
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


static func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


# Ahize: sap Y ekseninde (kulaklık +Y'de), kulaklık ve ağızlık +Z'ye (yüze) bakar.
# "kablo_ucu" adlı çocuk düğüm kablonun ahizeye girdiği nokta.
static func handset(parent: Node3D) -> Node3D:
	var h := Node3D.new()
	h.name = "Ahize"
	parent.add_child(h)
	var body := mat("govde")
	var cap := CapsuleMesh.new()
	cap.radius = 0.017
	cap.height = 0.2
	cap.radial_segments = 20
	_mi(h, cap, body, Vector3(0, 0, -0.004), Vector3.ZERO, Vector3(1.2, 1.0, 0.85))
	# sapın ortası hafif kemerli: iki ucu yüze doğru eğik kulaklık ve ağızlık
	for s in [1.0, -1.0]:
		var cup := Node3D.new()
		cup.position = Vector3(0, s * 0.088, 0.012)
		cup.rotation.x = -s * 0.32
		h.add_child(cup)
		_mi(cup, _cyl(0.031, 0.024, 0.04), body, Vector3(0, 0, 0.012), Vector3(PI / 2, 0, 0))
		_mi(cup, _cyl(0.033, 0.033, 0.006), body, Vector3(0, 0, 0.033), Vector3(PI / 2, 0, 0))
		_mi(cup, _cyl(0.024, 0.024, 0.004), mat("izgara"), Vector3(0, 0, 0.0365), Vector3(PI / 2, 0, 0))
		# delik halkası
		for i in 6:
			var a := i * TAU / 6.0
			_mi(cup, _cyl(0.003, 0.003, 0.002, 8), mat("siyah"), Vector3(cos(a) * 0.012, sin(a) * 0.012, 0.0388), Vector3(PI / 2, 0, 0))
	var end := Node3D.new()
	end.name = "kablo_ucu"
	end.position = Vector3(0, -0.118, -0.006)
	h.add_child(end)
	_mi(h, _cyl(0.006, 0.008, 0.016, 10), mat("koyu"), Vector3(0, -0.11, -0.006))
	for mi in h.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# aynı malzemeli parçalar tek meshte (ahize ~20 parçaydı, her biri bir çizim çağrısı)
	preload("res://scripts/dunya.gd").birlestir(h)
	return h


# Duvar telefonu (yerel: +Z odaya, Y yukarı). Dönen sözlük: kök, çataldaki ahize, kablonun gövdeden çıktığı nokta.
static func build(parent: Node3D) -> Dictionary:
	var root := Node3D.new()
	root.name = "Telefon"
	root.scale = Vector3.ONE * SCALE
	parent.add_child(root)
	var body := mat("govde")
	# duvar plakası
	_mi(root, _box(Vector3(0.2, 0.3, 0.012)), mat("koyu"), Vector3(0.0, -0.005, 0.006))
	for p in [Vector3(-0.085, 0.13, 0.013), Vector3(0.085, 0.13, 0.013), Vector3(-0.085, -0.14, 0.013), Vector3(0.085, -0.14, 0.013)]:
		_mi(root, _cyl(0.005, 0.005, 0.004, 10), mat("krom"), p, Vector3(PI / 2, 0, 0))
	# kalıp gövde: kutunun üstü ve altı yuvarlak (yatay silindirlerle)
	_mi(root, _box(Vector3(0.16, 0.16, 0.075)), body, Vector3(0.012, -0.01, 0.05))
	for y in [0.07, -0.09]:
		_mi(root, _cyl(0.0375, 0.0375, 0.16, 32), body, Vector3(0.012, y, 0.05), Vector3(0, 0, PI / 2))
	# önde hafif çıkıntılı kapak çizgisi
	_mi(root, _box(Vector3(0.164, 0.004, 0.077)), mat("koyu"), Vector3(0.012, 0.035, 0.05))
	# çevirmeli kadran: fildişi numara plakası, krom parmak çarkı, on delik, ortada etiket, parmak durdurucu
	var dial := Node3D.new()
	dial.position = Vector3(0.012, -0.03, 0.0885)
	root.add_child(dial)
	_mi(dial, _cyl(0.054, 0.056, 0.006, 40), mat("krom"), Vector3.ZERO, Vector3(PI / 2, 0, 0))
	_mi(dial, _cyl(0.05, 0.05, 0.004, 40), mat("kadran"), Vector3(0, 0, 0.004), Vector3(PI / 2, 0, 0))
	var holes := TorusMesh.new()
	holes.inner_radius = 0.0075
	holes.outer_radius = 0.0105
	holes.rings = 14
	holes.ring_segments = 6
	for i in 10:
		var a := deg_to_rad(60.0 + i * 28.0)
		var p := Vector3(cos(a) * 0.036, sin(a) * 0.036, 0.0075)
		_mi(dial, holes, mat("krom"), p, Vector3(PI / 2, 0, 0))
		_mi(dial, _cyl(0.0075, 0.0075, 0.002, 12), mat("siyah"), p - Vector3(0, 0, 0.0015), Vector3(PI / 2, 0, 0))
		var l := Label3D.new()
		l.text = str((i + 1) % 10)
		l.font_size = 36
		l.pixel_size = 0.00028
		l.modulate = Color("#1a1a1a")
		l.outline_size = 0
		l.position = Vector3(cos(a) * 0.036, sin(a) * 0.036, 0.0072)
		l.visibility_range_end = 4.0  # 1 cm'lik rakamlar uzaktan zaten seçilmez
		dial.add_child(l)
	_mi(dial, _cyl(0.018, 0.018, 0.006, 24), mat("krom"), Vector3(0, 0, 0.008), Vector3(PI / 2, 0, 0))
	_mi(dial, _cyl(0.013, 0.013, 0.002, 20), mat("kadran"), Vector3(0, 0, 0.0115), Vector3(PI / 2, 0, 0))
	_mi(dial, _box(Vector3(0.006, 0.016, 0.01)), mat("krom"), Vector3(0.046, -0.03, 0.01), Vector3(0, 0, 0.75))
	# alt kısımda küçük marka plakası
	var tag := Label3D.new()
	tag.text = "PTT"
	tag.font_size = 40
	tag.pixel_size = 0.0004
	tag.modulate = Color("#e2c27a")
	tag.outline_size = 0
	tag.position = Vector3(0.012, -0.1, 0.0885)
	tag.rotation.x = -0.5
	root.add_child(tag)
	# ahize çatalı: gövdenin sol üstünde krom kanca (kulaklık üstüne oturur)
	_mi(root, _box(Vector3(0.034, 0.02, 0.03)), body, Vector3(-0.078, 0.085, 0.05))
	var fork := Node3D.new()
	fork.position = Vector3(-0.098, 0.082, 0.05)
	root.add_child(fork)
	for z in [-0.012, 0.012]:
		_mi(fork, _cyl(0.0035, 0.0035, 0.03, 10), mat("krom"), Vector3(-0.012, 0, z), Vector3(0, 0, PI / 2))
	# kablo girişi: gövdenin altında solda
	_mi(root, _cyl(0.007, 0.006, 0.014, 12), mat("siyah"), Vector3(-0.045, -0.13, 0.05))
	var jack := Node3D.new()
	jack.name = "kablo_girisi"
	jack.position = Vector3(-0.045, -0.138, 0.05)
	root.add_child(jack)
	# çataldaki ahize: gövdenin solunda dikey, kulaklık çatalın üstünde, ağızları odaya bakar
	var hook := Node3D.new()
	hook.name = "catal"
	hook.position = Vector3(-0.125, -0.005, 0.05)
	hook.rotation.y = PI  # kapaklar duvara, sapın sırtı odaya: el ahizeyi sırtından kavrar
	root.add_child(hook)
	var hs := handset(hook)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# gövde, kadran ve çatal sabit: aynı malzemeli parçalar tek meshte (telefon başına ~70 çizim çağrısıydı);
	# ahize (elde taşınır) ayrı kalır
	preload("res://scripts/dunya.gd").birlestir(root, [hook])
	return {"root": root, "handset": hs, "jack": jack}


# Kıvırcık spiral kablo: iki dünya noktası arasında sarkan bir eğri boyunca sarmal tüp.
class Cord extends MeshInstance3D:
	const COILS := 64
	const SEG := 8  # sarmal turu başına örnek
	const SIDES := 4  # tüp kesiti
	const TUBE := 0.0033
	var _mesh := ArrayMesh.new()
	var _idx := PackedInt32Array()
	var _la := Vector3(INF, 0, 0)
	var _lb := Vector3(INF, 0, 0)
	var floor_y := 0.02  # kablo yere girmesin (yerel y)
	var length := 0.0  # uçlar arası son mesafe

	func _init() -> void:
		mesh = _mesh
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		material_override = load("res://scripts/telefon.gd").mat("kablo")
		var n := COILS * SEG + 1
		for i in n - 1:
			for k in SIDES:
				var a := i * SIDES + k
				var b := i * SIDES + (k + 1) % SIDES
				var c := a + SIDES
				var d := b + SIDES
				_idx.append_array([a, c, b, b, c, d])

	func update(a_w: Vector3, b_w: Vector3) -> void:
		if a_w.distance_squared_to(_la) < 0.000004 and b_w.distance_squared_to(_lb) < 0.000004:
			return
		_la = a_w
		_lb = b_w
		var a := to_local(a_w)
		var b := to_local(b_w)
		length = a.distance_to(b)
		var t := clampf(length / CORD_MAX, 0.0, 1.0)
		# gevşekken sarkık halka, gerildikçe dümdüz
		var sag := 0.17 * pow(1.0 - t, 1.8) + 0.012
		var ctrl := (a + b) * 0.5 + Vector3.DOWN * sag * 2.0
		var r := lerpf(0.0115, 0.0055, t)  # sarmal açıldıkça incelir
		var n := COILS * SEG + 1
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		verts.resize(n * SIDES)
		norms.resize(n * SIDES)
		var nrm := Vector3.ZERO
		var prev_c := Vector3.ZERO
		var centers := PackedVector3Array()
		centers.resize(n)
		var radial := PackedVector3Array()
		radial.resize(n)
		for i in n:
			var s := float(i) / (n - 1)
			var p := a * (1.0 - s) * (1.0 - s) + ctrl * 2.0 * s * (1.0 - s) + b * s * s
			var tan := (2.0 * (1.0 - s) * (ctrl - a) + 2.0 * s * (b - ctrl))
			if tan.length() < 1e-5:
				tan = b - a if (b - a).length() > 1e-5 else Vector3.DOWN
			tan = tan.normalized()
			if i == 0:
				nrm = tan.cross(Vector3.UP if absf(tan.y) < 0.95 else Vector3.RIGHT).normalized()
			else:
				nrm = (nrm - tan * nrm.dot(tan)).normalized()  # paralel taşıma: sarmal burulmasın
			var bin := tan.cross(nrm)
			var th := s * COILS * TAU
			var rd := nrm * cos(th) + bin * sin(th)
			var c := p + rd * r
			c.y = maxf(c.y, floor_y)
			centers[i] = c
			radial[i] = rd
		for i in n:
			var ht := centers[mini(i + 1, n - 1)] - centers[maxi(i - 1, 0)]
			if ht.length() < 1e-6:
				ht = Vector3.UP
			ht = ht.normalized()
			var u := (radial[i] - ht * radial[i].dot(ht)).normalized()
			var v := ht.cross(u)
			for k in SIDES:
				var ang := k * TAU / SIDES
				var dn := u * cos(ang) + v * sin(ang)
				verts[i * SIDES + k] = centers[i] + dn * TUBE
				norms[i * SIDES + k] = dn
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_INDEX] = _idx
		_mesh.clear_surfaces()
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)


# ---------- sesler (koddan üretilir) ----------
const Sfx := preload("res://scripts/sfx.gd")
static var _snd := {}


static func sound(id: String) -> AudioStreamWAV:
	if _snd.has(id):
		return _snd[id]
	var r := Sfx.RATE
	var s := PackedFloat32Array()
	var loop := false
	match id:
		"catal":  # ahize kalkınca çatal yayının çift tıkı
			s.resize(int(r * 0.16))
			for i in s.size():
				var t := float(i) / r
				var a := exp(-t * 90.0) * 0.8 + (exp(-(t - 0.045) * 110.0) * 0.55 if t > 0.045 else 0.0)
				s[i] = (randf() * 2.0 - 1.0) * a * 0.6 + sin(TAU * 2300.0 * t) * a * 0.35
		"klak":  # ahize çatala oturur: tok bakalit vuruşu + zil kabının hafif çınlaması
			s.resize(int(r * 0.5))
			for i in s.size():
				var t := float(i) / r
				var thud := sin(TAU * 105.0 * t) * exp(-t * 28.0) * 0.9
				var plastic := (randf() * 2.0 - 1.0) * exp(-t * 70.0) * 0.55 + sin(TAU * 820.0 * t) * exp(-t * 45.0) * 0.25
				var bell := sin(TAU * 1240.0 * t) * exp(-t * 9.0) * 0.06
				s[i] = thud + plastic + bell
		"cevir_sesi":  # hat (çevir) sesi: sürekli 450 Hz
			s.resize(r)
			for i in s.size():
				s[i] = sin(TAU * 450.0 * float(i) / r) * 0.22
			loop = true
		"calma_sesi":  # karşı taraf çalıyor: 450 Hz, 1 sn açık 3 sn kapalı
			s.resize(r * 4)
			for i in s.size():
				var t := float(i) / r
				s[i] = sin(TAU * 450.0 * t) * 0.22 if t < 1.0 else 0.0
			loop = true
		"mesgul":  # kesildi / meşgul: 450 Hz yarım saniye aralı
			s.resize(r * 3)
			for i in s.size():
				var t := float(i) / r
				s[i] = sin(TAU * 450.0 * t) * 0.2 if fmod(t, 1.0) < 0.5 else 0.0
		"gerilme":  # spiral kablo gerilir: lastik gıcırtısı
			s.resize(int(r * 0.45))
			var ph := 0.0
			for i in s.size():
				var t := float(i) / r
				var f := 260.0 + 180.0 * t / 0.45 + sin(t * 70.0) * 25.0
				ph += TAU * f / r
				var env := sin(PI * t / 0.45)
				s[i] = (sin(ph) * 0.4 + sin(ph * 2.03) * 0.25 + (randf() * 2.0 - 1.0) * 0.15) * env * 0.35
	var w := Sfx._wav(s, loop)
	_snd[id] = w
	return w
