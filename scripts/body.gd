# Mahkum karakteri: tulum, yüz (göz, kaş, burun, ağız), saç, sakal, aksesuar.
# Yürürken bacaklar ve kollar sallanır, oturunca bacaklar kırılır, hareketleri (emote) oynar.
# Yüzü -z yönüne bakar. Görünüş catalog.gd'deki seçeneklerden gelir.
extends Node3D

const Catalog := preload("res://scripts/catalog.gd")

var show_head := true
var show_arms := true
var show_torso := true
var look: Dictionary = Catalog.DEFAULT_LOOK.duplicate()

var walk := 0.0      # 0 = duruyor, 1 = tam hızda yürüyor
var seated := false
var emote := ""
var emote_t := 0.0
var _phase := 0.0
var _sit := 0.0      # 0 ayakta, 1 oturuyor (yumuşak geçiş)
var _rig: Node3D
var _hip_root: Node3D
var _upper: Node3D
var _head: Node3D
var _torso_parts: Array[Node3D] = []
var _arm_parts: Array[Node3D] = []
var _hips: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _shoulders: Array[Node3D] = []
var _elbows: Array[Node3D] = []

static var _mat_cache := {}


static func _mat(c: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var key := "%s/%.2f/%.2f" % [c.to_html(), rough, metal]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	_mat_cache[key] = m
	return m


# Kıyafet malzemesi: düz renk, çizgili, kamuflaj ya da altın.
static func outfit_material(id: String) -> StandardMaterial3D:
	var key := "kiyafet/" + id
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(Catalog.OUTFIT_COLORS.get(id, "#B4501A"))
	m.roughness = 0.9
	match id:
		"cizgili":
			var img := Image.create(1, 2, false, Image.FORMAT_RGB8)
			img.set_pixel(0, 0, Color("#1b1b1d"))
			img.set_pixel(0, 1, Color("#e4e0d8"))
			m.albedo_texture = ImageTexture.create_from_image(img)
			m.albedo_color = Color.WHITE
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			m.uv1_triplanar = true
			m.uv1_scale = Vector3.ONE * 7.0
		"kamuflaj":
			var n := FastNoiseLite.new()
			n.frequency = 0.03
			var t := NoiseTexture2D.new()
			t.width = 128
			t.height = 128
			t.seamless = true
			t.noise = n
			var g := Gradient.new()
			g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
			g.set_color(0, Color("#2e3524"))
			g.set_color(1, Color("#8a8058"))
			g.add_point(0.45, Color("#4f5a3a"))
			g.add_point(0.62, Color("#6b5a3c"))
			t.color_ramp = g
			m.albedo_texture = t
			m.albedo_color = Color.WHITE
			m.uv1_triplanar = true
			m.uv1_scale = Vector3.ONE * 2.0
		"altin":
			m.metallic = 0.85
			m.roughness = 0.3
	_mat_cache[key] = m
	return m


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _capsule(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 4
	return _mesh(parent, c, pos, mat)


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mesh(parent, b, pos, mat, rot)


func _sphere(parent: Node3D, r: float, pos: Vector3, mat: Material, hemi := false, scl := Vector3.ONE) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r if hemi else r * 2.0
	s.is_hemisphere = hemi
	s.radial_segments = 16
	s.rings = 8
	return _mesh(parent, s, pos, mat, Vector3.ZERO, scl)


func _ready() -> void:
	_build()


func set_look(l) -> void:
	look = Catalog.sanitize(l)
	if is_inside_tree():
		_build()


# Birinci şahısta kafa, kollar ve gövde gizlenir (kamera içinden görünmesin diye).
func set_first_person(on: bool) -> void:
	show_head = not on
	show_arms = not on
	show_torso = not on
	_apply_visibility()


func play_emote(id: String) -> void:
	emote = id
	emote_t = 0.0


func _apply_visibility() -> void:
	if _head:
		_head.visible = show_head
	for p in _torso_parts:
		p.visible = show_torso
	for p in _arm_parts:
		p.visible = show_arms


func _build() -> void:
	if _rig:
		_rig.queue_free()
	_hips.clear()
	_knees.clear()
	_shoulders.clear()
	_elbows.clear()
	_torso_parts.clear()
	_arm_parts.clear()
	_rig = Node3D.new()
	add_child(_rig)

	var cloth := outfit_material(look.kiyafet)
	var dark := _mat(Color("#1b1b1d"), 0.6)
	var skin := _mat(Color(Catalog.SKIN[look.ten]), 0.7)

	_hip_root = Node3D.new()
	_hip_root.position.y = 0.92
	_rig.add_child(_hip_root)
	var pelvis := _capsule(_hip_root, 0.17, 0.4, Vector3(0, 0.05, 0.04), cloth)
	pelvis.scale = Vector3(1.15, 1, 0.8)
	_torso_parts.append(pelvis)
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.1, 0, 0.04)
		_hip_root.add_child(hip)
		_capsule(hip, 0.075, 0.5, Vector3(0, -0.23, 0), cloth)
		var knee := Node3D.new()
		knee.position.y = -0.45
		hip.add_child(knee)
		_capsule(knee, 0.066, 0.46, Vector3(0, -0.21, 0), cloth)
		_box(knee, Vector3(0.11, 0.08, 0.27), Vector3(0, -0.43, -0.05), dark)
		_hips.append(hip)
		_knees.append(knee)

	_upper = Node3D.new()
	_upper.position.y = 0.95
	_rig.add_child(_upper)
	var chest := _capsule(_upper, 0.19, 0.62, Vector3(0, 0.3, 0.08), cloth)
	chest.scale = Vector3(1.2, 1, 0.75)
	_torso_parts.append(chest)
	# göğüste mahkum numarası etiketi
	_torso_parts.append(_box(_upper, Vector3(0.1, 0.05, 0.01), Vector3(0.09, 0.42, -0.065), _mat(Color("#e8e4da"), 0.9)))
	if look.aksesuar == "zincir":
		var chain := TorusMesh.new()
		chain.inner_radius = 0.095
		chain.outer_radius = 0.108
		_torso_parts.append(_mesh(_upper, chain, Vector3(0, 0.56, 0.03), _mat(Color("#d4af37"), 0.25, 0.9), Vector3(deg_to_rad(-20), 0, 0)))

	_build_head(skin)

	for side in [-1.0, 1.0]:
		var sh := Node3D.new()
		sh.position = Vector3(side * 0.24, 0.55, 0.06)
		_upper.add_child(sh)
		_arm_parts.append(_capsule(sh, 0.058, 0.32, Vector3(0, -0.14, 0), cloth))
		var el := Node3D.new()
		el.position.y = -0.29
		sh.add_child(el)
		_arm_parts.append(_capsule(el, 0.05, 0.28, Vector3(0, -0.12, 0), cloth))
		_arm_parts.append(_box(el, Vector3(0.07, 0.11, 0.045), Vector3(0, -0.3, 0), skin))
		_shoulders.append(sh)
		_elbows.append(el)
	_apply_visibility()


func _build_head(skin: StandardMaterial3D) -> void:
	_head = Node3D.new()
	_head.position = Vector3(0, 0.74, 0.04)
	_upper.add_child(_head)
	_capsule(_head, 0.05, 0.14, Vector3(0, -0.11, 0.01), skin)
	_sphere(_head, 0.115, Vector3.ZERO, skin, false, Vector3(0.92, 1.08, 0.98))
	for side in [-1.0, 1.0]:
		_sphere(_head, 0.026, Vector3(side * 0.106, -0.005, 0.0), skin)

	var hair := _mat(Color(Catalog.HAIR_COLORS[look.sac_renk]), 0.8)
	var white := _mat(Color("#f2f0ea"), 0.4)
	var iris := _mat(Color(Catalog.EYE_COLORS[look.goz]), 0.3)
	var black := _mat(Color("#0c0c0c"), 0.3)
	# gözler
	for side in [-1.0, 1.0]:
		_sphere(_head, 0.016, Vector3(side * 0.04, 0.015, -0.092), white)
		_sphere(_head, 0.0095, Vector3(side * 0.04, 0.015, -0.103), iris)
		_sphere(_head, 0.0045, Vector3(side * 0.04, 0.015, -0.11), black)
	# kaşlar
	var brow_h := 0.02 if look.kas == "kalin" else 0.012
	var tilt: float = {"kizgin": 0.35, "uzgun": -0.3}.get(look.kas, 0.0)
	for side in [-1.0, 1.0]:
		_box(_head, Vector3(0.05, brow_h, 0.015), Vector3(side * 0.041, 0.05, -0.103), hair, Vector3(0, 0, tilt * side))
	# burun ve ağız
	_box(_head, Vector3(0.022, 0.036, 0.024), Vector3(0, -0.012, -0.108), _mat(Color(Catalog.SKIN[look.ten]).darkened(0.08), 0.7))
	_box(_head, Vector3(0.042, 0.008, 0.01), Vector3(0, -0.052, -0.1), _mat(Color("#7a3030"), 0.6))
	_build_hair(hair, skin)
	_build_extras(hair)


# Sakal ve yüz aksesuarları (gerçek karakter modelinde de kafaya takılır).
func _build_extras(hair: StandardMaterial3D) -> void:
	# sakal
	match look.sakal:
		"biyik":
			_box(_head, Vector3(0.07, 0.016, 0.02), Vector3(0, -0.035, -0.112), hair)
		"keci":
			_box(_head, Vector3(0.036, 0.045, 0.03), Vector3(0, -0.088, -0.098), hair)
			_box(_head, Vector3(0.06, 0.014, 0.02), Vector3(0, -0.035, -0.112), hair)
		"sakal":
			_sphere(_head, 0.1, Vector3(0, -0.07, -0.03), hair, false, Vector3(1.05, 0.72, 0.85))
			_box(_head, Vector3(0.075, 0.016, 0.02), Vector3(0, -0.035, -0.112), hair)
	# yüz aksesuarları
	match look.aksesuar:
		"gozluk", "gunes":
			var frame := _mat(Color("#141414"), 0.4, 0.3)
			for side in [-1.0, 1.0]:
				if look.aksesuar == "gunes":
					var lens := CylinderMesh.new()
					lens.top_radius = 0.026
					lens.bottom_radius = 0.026
					lens.height = 0.006
					_mesh(_head, lens, Vector3(side * 0.04, 0.015, -0.122), _mat(Color("#101010"), 0.1, 0.5), Vector3(PI / 2, 0, 0))
				else:
					var ring := TorusMesh.new()
					ring.inner_radius = 0.02
					ring.outer_radius = 0.026
					_mesh(_head, ring, Vector3(side * 0.04, 0.015, -0.12), frame, Vector3(PI / 2, 0, 0))
			_box(_head, Vector3(0.03, 0.006, 0.006), Vector3(0, 0.02, -0.122), frame)
		"bant":
			var tape := _mat(Color("#e8dcc6"), 0.9)
			_box(_head, Vector3(0.05, 0.014, 0.008), Vector3(0.06, -0.02, -0.088), tape, Vector3(0, -0.5, 0.6))
			_box(_head, Vector3(0.05, 0.014, 0.008), Vector3(0.06, -0.02, -0.088), tape, Vector3(0, -0.5, -0.6))


# Saç başın üstüne geriye eğik bir kubbe olarak oturur; ön kenarı kaşların üstünde kalır.
func _build_hair(hair: StandardMaterial3D, skin: StandardMaterial3D) -> void:
	var tilt := Vector3(0.45, 0, 0)
	var dome := func(r: float, mat: Material) -> MeshInstance3D:
		var m := _sphere(_head, r, Vector3(0, 0.012, 0.004), mat, true, Vector3(0.95, 1.0, 1.02))
		m.rotation = tilt
		return m
	match look.sac:
		"kisa":
			dome.call(0.122, hair)
		"asker":
			var buzz := _mat(Color(Catalog.HAIR_COLORS[look.sac_renk]).lerp(Color(Catalog.SKIN[look.ten]), 0.45), 0.9)
			dome.call(0.118, buzz)
		"uzun":
			dome.call(0.124, hair)
			_box(_head, Vector3(0.22, 0.27, 0.07), Vector3(0, -0.09, 0.085), hair)
			for side in [-1.0, 1.0]:
				_box(_head, Vector3(0.03, 0.2, 0.12), Vector3(side * 0.105, -0.06, 0.02), hair)
		"atkuyrugu":
			dome.call(0.122, hair)
			var tail := _capsule(_head, 0.032, 0.17, Vector3(0, -0.05, 0.15), hair)
			tail.rotation.x = 0.6
		"mohawk":
			dome.call(0.117, _mat(Color(Catalog.HAIR_COLORS[look.sac_renk]).lerp(Color(Catalog.SKIN[look.ten]), 0.6), 0.9))
			_box(_head, Vector3(0.035, 0.08, 0.22), Vector3(0, 0.125, 0.01), hair)
		"kivircik":
			_sphere(_head, 0.15, Vector3(0, 0.07, 0.045), hair)
		"bere":
			var cap := _mat(Color(Catalog.HAIR_COLORS[look.sac_renk]).lightened(0.1), 0.95)
			var top := dome.call(0.13, cap) as MeshInstance3D
			top.scale = Vector3(0.97, 1.15, 1.04)
			var rim := CylinderMesh.new()
			rim.top_radius = 0.126
			rim.bottom_radius = 0.128
			rim.height = 0.035
			_mesh(_head, rim, Vector3(0, 0.03, 0.01), cap, tilt)


func _process(delta: float) -> void:
	_sit = move_toward(_sit, 1.0 if seated else 0.0, delta * 2.5)
	if walk > 0.05:
		_phase += delta * 7.5 * clampf(walk, 0.4, 1.4)
	else:
		_phase = lerpf(_phase, roundf(_phase / PI) * PI, delta * 6.0)
	var wk := clampf(walk, 0.0, 1.0)
	var a := sin(_phase) * 0.55 * wk
	var b := absf(sin(_phase)) * 0.25 * wk
	# oturunca kalça 0.92'den 0.5'e iner, uyluk öne döner, diz kırılır
	_hip_root.position.y = lerpf(0.92, 0.5, _sit) + b * 0.05
	_upper.position.y = lerpf(0.95, 0.53, _sit) + b * 0.05
	_upper.rotation = Vector3.ZERO
	_head.rotation = Vector3.ZERO
	for i in 2:
		var sgn := 1.0 if i == 0 else -1.0
		_hips[i].rotation.x = lerpf(a * sgn, deg_to_rad(88), _sit)
		var knee_walk := maxf(0.0, -sin(_phase + (0.0 if i == 0 else PI))) * 0.7 * wk
		_knees[i].rotation.x = lerpf(-knee_walk, -deg_to_rad(85), _sit)
	for i in 2:
		var sgn := -1.0 if i == 0 else 1.0
		_shoulders[i].rotation = Vector3(lerpf(a * sgn * 0.8, deg_to_rad(35), _sit), 0, 0)
		_elbows[i].rotation = Vector3(lerpf(0.25 + b, deg_to_rad(45), _sit), 0, 0)
	if emote != "":
		emote_t += delta
		var dur := 4.0 if emote == "dans" else 2.6
		if emote_t > dur:
			emote = ""
		else:
			_emote_pose(emote_t, minf(1.0, minf(emote_t, dur - emote_t) * 5.0))


# Kol pozu: i 0 = sol, 1 = sağ. side_out: kolu yana açma (iki tarafta da dışa doğru pozitif).
func _arm(i: int, fwd: float, side_out: float, elbow: float, k: float, elbow_twist := 0.0) -> void:
	var s := -1.0 if i == 0 else 1.0
	var sh := _shoulders[i]
	sh.rotation = sh.rotation.lerp(Vector3(fwd, 0, side_out * s), k)
	_elbows[i].rotation = _elbows[i].rotation.lerp(Vector3(elbow, 0, elbow_twist * s), k)


func _emote_pose(t: float, k: float) -> void:
	match emote:
		"selam":
			_arm(1, 0.15, 2.6, 0.0, k, sin(t * 12.0) * 0.5)
		"super":
			_arm(1, 1.25, 0.15, 0.9, k)
		"isaret":
			_arm(1, 1.55, 0.05, 0.0, k)
		"omuz":
			for i in 2:
				_arm(i, 0.35, 0.3, 1.4, k)
			_upper.position.y += absf(sin(t * 3.0)) * 0.03 * k
			_head.rotation.z = sin(t * 2.0) * 0.12 * k
		"alkis":
			for i in 2:
				_arm(i, 1.2, -0.3 - sin(t * 16.0) * 0.12, 0.5, k)
		"off":
			_arm(1, 1.0, -0.4, 2.1, k)
			_head.rotation.x = 0.35 * k
		"selamla":
			_arm(1, 0.25, 1.35, 2.0, k, 0.4)
		"dans":
			_upper.rotation.z = sin(t * 6.0) * 0.15 * k
			_hip_root.position.y += absf(sin(t * 6.0)) * 0.05 * k
			for i in 2:
				var ph := t * 6.0 + (0.0 if i == 0 else PI)
				_arm(i, 0.3, 1.9 + sin(ph) * 0.6, 0.4, k)
				_hips[i].rotation.x = sin(ph) * 0.35 * k
