# Oyunlarda kullanılan 3D nesneler (koddan): altıpatar tabanca, askeri C4 kalıbı ve katmanlı patlama efekti.
extends RefCounted


static func _mat(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mesh(parent, b, mat, pos, rot)


static func _cyl(parent: Node3D, r: float, h: float, mat: Material, pos: Vector3, rot := Vector3.ZERO, segs := 20) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return _mesh(parent, c, mat, pos, rot)


# ---------- altıpatar ----------
# Gerçek altıpatar modeli (CC0, loafbrr_1 "Revolver Game Asset", assets/models/altipatar).
# Kök düğümün ekseni: namlu -z yönünde, üstü +y, kök kabzanın tepesinde (gövdeye birleştiği yer).
# "tambur" adlı düğümün rotation.z'si tamburu döndürür (iskeletteki tambur kemiğine aktarılır);
# "namlu_agzi" namlunun ucu (atış alevi buraya).
const REVOLVER_MODEL := "res://assets/models/altipatar/altipatar.gltf"
const REVOLVER_SCALE := 0.86  # .357 Magnum boyu; elde doğal dursun
const REVOLVER_GIZLI := ["357BulletCylinders", "357Bullet", "357AmmunitionBox", "357BulletFired"]


# Tambur kemiğini "tambur" düğümünün dönüşüne bağlar (rulet tamburu çevirince model de döner).
class DrumSpin extends SkeletonModifier3D:
	var drum: Node3D
	var _bone := -2

	func _process_modification() -> void:
		var sk := get_skeleton()
		if not sk or not is_instance_valid(drum):
			return
		if _bone == -2:
			_bone = sk.find_bone("DEF_Cylinder")
		if _bone < 0:
			return
		# kemiğin Y ekseni namlu boyunca: kendi ekseni etrafında çevir
		var rest := sk.get_bone_rest(_bone).basis.get_rotation_quaternion()
		sk.set_bone_pose_rotation(_bone, rest * Quaternion(Vector3.UP, drum.rotation.z))


static func revolver(parent: Node3D) -> Node3D:
	if not ResourceLoader.exists(REVOLVER_MODEL):
		return _revolver_kutu(parent)
	var root := Node3D.new()
	root.name = "Altipatar"
	parent.add_child(root)
	var m: Node3D = load(REVOLVER_MODEL).instantiate()
	m.rotation.y = PI / 2  # modelde namlu +x yönünde
	m.scale = Vector3.ONE * REVOLVER_SCALE
	root.add_child(m)
	for n in m.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		# masadaki mermi kutusu ve boş kovanlar gizli; tamburdaki dolu mermiler kalır
		if String(mi.name) in REVOLVER_GIZLI or String(mi.name).begins_with("357BulletFired"):
			mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in m.get_children():
		if String(c.name) in REVOLVER_GIZLI:
			(c as Node3D).visible = false
	var drum := Node3D.new()
	drum.name = "tambur"
	root.add_child(drum)
	var sks: Array = m.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty():
		var spin := DrumSpin.new()
		spin.drum = drum
		(sks[0] as Skeleton3D).add_child(spin)
	var tip := Marker3D.new()
	tip.name = "namlu_agzi"
	tip.position = Vector3(0, 0.084, -0.305) * REVOLVER_SCALE
	root.add_child(tip)
	return root


# Eski kutulardan altıpatar (model bulunamazsa yedek).
static func _revolver_kutu(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Altipatar"
	parent.add_child(root)
	var steel := _mat(Color("#2b2e34"), 0.28, 0.92)
	var steel_dark := _mat(Color("#17191c"), 0.35, 0.85)
	var bright := _mat(Color("#8d939c"), 0.2, 1.0)
	var wood := _mat(Color("#5a2f1a"), 0.55)
	var brass := _mat(Color("#c9a24a"), 0.3, 1.0)
	# gövde (çerçeve)
	_box(root, Vector3(0.03, 0.05, 0.075), steel, Vector3(0, 0.012, 0.0))
	_box(root, Vector3(0.03, 0.016, 0.06), steel, Vector3(0, 0.044, -0.005))  # tambur üstü köprü
	_box(root, Vector3(0.026, 0.03, 0.03), steel, Vector3(0, 0.02, 0.05), Vector3(-0.2, 0, 0))  # arka
	# namlu ve altındaki kılıf
	_cyl(root, 0.0085, 0.15, steel, Vector3(0, 0.03, -0.11), Vector3(PI / 2, 0, 0))
	_box(root, Vector3(0.016, 0.014, 0.14), steel, Vector3(0, 0.017, -0.105))
	_cyl(root, 0.0045, 0.006, steel_dark, Vector3(0, 0.03, -0.186), Vector3(PI / 2, 0, 0))  # namlu ağzı
	_box(root, Vector3(0.004, 0.009, 0.012), steel, Vector3(0, 0.042, -0.175))  # arpacık
	_box(root, Vector3(0.012, 0.004, 0.02), steel_dark, Vector3(0, 0.05, 0.03))  # gez
	# tambur (6 yuva + mermi dipleri)
	var drum := Node3D.new()
	drum.name = "tambur"
	drum.position = Vector3(0, 0.018, -0.008)
	root.add_child(drum)
	_cyl(drum, 0.022, 0.044, steel, Vector3.ZERO, Vector3(PI / 2, 0, 0), 24)
	for i in 6:
		var a := i * TAU / 6.0
		var p := Vector3(cos(a) * 0.013, sin(a) * 0.013, 0)
		_cyl(drum, 0.0055, 0.046, steel_dark, p, Vector3(PI / 2, 0, 0), 10)
		_cyl(drum, 0.0045, 0.002, brass, p + Vector3(0, 0, 0.023), Vector3(PI / 2, 0, 0), 10)
		# yivler
		var ga := a + TAU / 12.0
		_box(drum, Vector3(0.004, 0.004, 0.03), steel_dark, Vector3(cos(ga) * 0.021, sin(ga) * 0.021, 0), Vector3(0, 0, ga))
	_cyl(root, 0.004, 0.06, bright, Vector3(0, 0.018, -0.01), Vector3(PI / 2, 0, 0), 8)  # mil
	# horoz
	var hammer := Node3D.new()
	hammer.name = "horoz"
	hammer.position = Vector3(0, 0.04, 0.045)
	root.add_child(hammer)
	_box(hammer, Vector3(0.008, 0.026, 0.01), steel, Vector3(0, 0.008, 0), Vector3(-0.5, 0, 0))
	_box(hammer, Vector3(0.012, 0.006, 0.012), steel_dark, Vector3(0, 0.02, 0.008), Vector3(-0.5, 0, 0))
	# tetik korkuluğu ve tetik
	var guard := TorusMesh.new()
	guard.inner_radius = 0.013
	guard.outer_radius = 0.0165
	guard.rings = 16
	guard.ring_segments = 6
	var gm := _mesh(root, guard, steel, Vector3(0, -0.022, 0.006), Vector3(0, 0, PI / 2))
	gm.scale = Vector3(1, 1, 1.15)
	_box(root, Vector3(0.005, 0.02, 0.006), bright, Vector3(0, -0.018, 0.004), Vector3(0.35, 0, 0))
	# kabza: ahşap, alt ucu arkaya eğik, perçinli
	var grip := Node3D.new()
	grip.position = Vector3(0, -0.012, 0.058)
	grip.rotation.x = -0.42  # alt ucu arkaya (tutan elin bileğine doğru)
	root.add_child(grip)
	_box(grip, Vector3(0.029, 0.072, 0.034), wood, Vector3(0, -0.034, 0))
	_box(grip, Vector3(0.024, 0.01, 0.03), steel, Vector3(0, -0.074, 0))
	for s in [-1.0, 1.0]:
		_cyl(grip, 0.004, 0.002, brass, Vector3(s * 0.0151, -0.035, 0), Vector3(0, 0, PI / 2), 8)
	return root


# ---------- C4 ----------
# İki M112 kalıbı bantla sarılı, üstünde dijital sayaç (rakamları bozuk: ne zaman patlayacağı belli değil),
# fünyeler ve renkli kablolar. Meta: led (malzeme), light (ışık), ekran (Label3D).
static func c4(parent: Node3D) -> Node3D:
	var n := Node3D.new()
	n.name = "C4"
	parent.add_child(n)
	var olive := _mat(Color("#5d5f3c"), 0.85)
	var clay := _mat(Color("#d9d2b8"), 0.95)
	var tape := _mat(Color("#121212"), 0.45)
	var plastic := _mat(Color("#1d1f22"), 0.4, 0.1)
	var silver := _mat(Color("#b8bcc2"), 0.25, 1.0)
	for i in 2:
		var z := (i - 0.5) * 0.058
		_box(n, Vector3(0.2, 0.05, 0.055), olive, Vector3(0, 0, z))
		_box(n, Vector3(0.19, 0.002, 0.045), clay, Vector3(0, 0.026, z))  # kalıbın açık ucu gibi açık renk şerit
		var lbl := Label3D.new()
		lbl.text = "CHARGE DEMOLITION M112\nC-4  1-1/4 LB"
		lbl.font_size = 22
		lbl.pixel_size = 0.0004
		lbl.modulate = Color(0.95, 0.9, 0.6)
		lbl.outline_size = 0
		lbl.position = Vector3(0.02, 0.0, z + (0.0281 if i == 1 else -0.0281))
		lbl.rotation.y = 0.0 if i == 1 else PI
		n.add_child(lbl)
	for x in [-0.07, 0.07]:
		_box(n, Vector3(0.022, 0.056, 0.122), tape, Vector3(x, 0, 0))
	# sayaç kutusu
	_box(n, Vector3(0.075, 0.022, 0.06), plastic, Vector3(-0.01, 0.036, 0))
	_box(n, Vector3(0.05, 0.002, 0.026), _mat(Color("#160404"), 0.2), Vector3(-0.016, 0.0475, -0.006))
	var scr := Label3D.new()
	scr.name = "ekran"
	scr.text = "88:88"
	scr.font_size = 64
	scr.pixel_size = 0.00028
	scr.modulate = Color(1.0, 0.18, 0.1)
	scr.outline_size = 0
	scr.position = Vector3(-0.016, 0.049, -0.006)
	scr.rotation.x = -PI / 2
	n.add_child(scr)
	for k in 3:
		_cyl(n, 0.0035, 0.004, _mat(Color("#303030"), 0.5), Vector3(0.012 + k * 0.009, 0.049, 0.016), Vector3.ZERO, 8)
	# LED
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color("#ff2010")
	lmat.emission_enabled = true
	lmat.emission = Color("#ff2010")
	lmat.emission_energy_multiplier = 0.2
	var led := SphereMesh.new()
	led.radius = 0.0045
	led.height = 0.009
	_mesh(n, led, lmat, Vector3(0.018, 0.049, -0.014))
	# fünyeler (gümüş tüpler) ve kablolar
	for i in 2:
		var z := (i - 0.5) * 0.058
		_cyl(n, 0.0035, 0.035, silver, Vector3(0.11, 0.0, z), Vector3(0, 0, PI / 2), 10)
	var cols := [Color("#c81e1e"), Color("#1e4ec8"), Color("#e0c020"), Color("#20a040")]
	for i in cols.size():
		var wm := _mat(cols[i], 0.5)
		var from := Vector3(0.02, 0.04, -0.02 + i * 0.012)
		var to := Vector3(0.125, 0.0, (-0.03 if i % 2 == 0 else 0.03))
		_wire(n, from, to, 0.025 + i * 0.006, wm)
	var light := OmniLight3D.new()
	light.light_color = Color("#ff2a10")
	light.omni_range = 1.0
	light.light_energy = 0.0
	light.position = Vector3(0.02, 0.07, 0)
	n.add_child(light)
	n.set_meta("led", lmat)
	n.set_meta("light", light)
	n.set_meta("ekran", scr)
	return n


# İki nokta arasında yukarı kavisli kablo (küçük silindir parçaları).
static func _wire(parent: Node3D, a: Vector3, b: Vector3, lift: float, mat: Material) -> void:
	var prev := a
	var steps := 7
	for s in range(1, steps + 1):
		var t := float(s) / steps
		var p := a.lerp(b, t) + Vector3(0, sin(t * PI) * lift, 0)
		var mid := (prev + p) / 2.0
		var d := p - prev
		var seg := _cyl(parent, 0.0016, d.length() + 0.001, mat, mid, Vector3.ZERO, 6)
		seg.look_at_from_position(mid, mid + d, Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT)
		seg.rotate_object_local(Vector3.RIGHT, PI / 2)
		prev = p


# ---------- patlama ----------

const PUFF_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, %s;
uniform sampler2D noise : repeat_enable, filter_linear;
uniform float boost = 1.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, length(MODEL_MATRIX[2].xyz), 0), vec4(0, 0, 0, 1));
}
void fragment() {
	vec2 uv = UV - 0.5;
	float r = length(uv) * 2.0;
	float n = texture(noise, UV * 0.7 + COLOR.rg * 0.13 + TIME * 0.05).r;
	float n2 = texture(noise, UV * 1.6 - TIME * 0.08).r;
	float a = smoothstep(1.0, 0.25, r + (n - 0.5) * 0.9 + (n2 - 0.5) * 0.3) * smoothstep(1.0, 0.7, r);  // kenarlar her zaman yumuşak
	ALBEDO = COLOR.rgb * boost * (0.75 + n * 0.5);
	ALPHA = clamp(a * COLOR.a, 0.0, 1.0);
}
"""


static func _noise() -> NoiseTexture2D:
	var nt := NoiseTexture2D.new()
	nt.width = 128
	nt.height = 128
	nt.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.035
	fn.fractal_octaves = 4
	nt.noise = fn
	return nt


static func _puff_mat(additive: bool, boost: float, noise: Texture2D) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = PUFF_SHADER % ("blend_add" if additive else "blend_mix")
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("noise", noise)
	m.set_shader_parameter("boost", boost)
	return m


static func _particles(parent: Node3D, amount: int, life: float, mat: Material, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.92
	p.randomness = 0.5
	p.lifetime_randomness = 0.4
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = mat
	p.mesh = q
	p.direction = Vector3.UP
	p.spread = 180.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25
	parent.add_child(p)
	return p


static func _ramp(cols: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(range(cols.size()).map(func(i) -> float: return float(i) / (cols.size() - 1)))
	g.colors = PackedColorArray(cols)
	return g


static func _curve(points: Array) -> Curve:
	var c := Curve.new()
	c.max_value = 4.0
	for pt in points:
		c.add_point(pt)
	return c


# Katmanlı patlama: göz alan parlama, ateş topu, kara duman, kıvılcım yağmuru, fiziksel enkaz,
# yerde genişleyen şok halkası, kalıcı yanık izi ve tavandan dökülen toz. floor_y: zeminin yüksekliği.
static func explosion(world: Node3D, pos: Vector3, floor_y := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Patlama"
	world.add_child(root)
	root.global_position = pos
	var noise := _noise()
	# 1) parlama
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.4)
	light.omni_range = 16.0
	light.light_energy = 40.0
	light.shadow_enabled = true
	root.add_child(light)
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 9.0, 0.12)
	lt.tween_property(light, "light_color", Color(1.0, 0.4, 0.12), 0.3)
	lt.tween_property(light, "light_energy", 0.0, 1.4).set_ease(Tween.EASE_OUT)
	var core := _particles(root, 1, 0.22, _puff_mat(true, 2.2, noise), 2.0)
	core.explosiveness = 1.0
	core.spread = 0.0
	core.initial_velocity_max = 0.0
	core.color_ramp = _ramp([Color(1, 1, 0.9, 1), Color(1, 0.8, 0.4, 0.0)])
	core.scale_amount_curve = _curve([Vector2(0, 0.4), Vector2(1, 1.6)])
	core.gravity = Vector3.ZERO
	# 2) ateş topu
	var fire := _particles(root, 30, 1.0, _puff_mat(true, 1.8, noise), 1.0)
	fire.initial_velocity_min = 1.5
	fire.initial_velocity_max = 5.5
	fire.damping_min = 4.0
	fire.damping_max = 7.0
	fire.gravity = Vector3(0, 1.2, 0)
	fire.color_ramp = _ramp([Color(1, 0.95, 0.75, 1), Color(1, 0.62, 0.15, 1), Color(0.85, 0.22, 0.04, 0.8), Color(0.2, 0.06, 0.02, 0.0)])
	fire.scale_amount_min = 0.6
	fire.scale_amount_max = 1.3
	fire.scale_amount_curve = _curve([Vector2(0, 0.5), Vector2(0.35, 1.6), Vector2(1, 2.2)])
	fire.angle_min = -180.0
	fire.angle_max = 180.0
	# 3) kara duman (uzun süre yükselir)
	var smoke := _particles(root, 28, 4.5, _puff_mat(false, 1.0, noise), 0.9)
	smoke.explosiveness = 0.7
	smoke.initial_velocity_min = 0.6
	smoke.initial_velocity_max = 2.4
	smoke.damping_min = 0.8
	smoke.damping_max = 1.6
	smoke.gravity = Vector3(0, 0.55, 0)
	smoke.color_ramp = _ramp([Color(0.12, 0.1, 0.09, 0.0), Color(0.13, 0.11, 0.1, 0.9), Color(0.28, 0.27, 0.26, 0.6), Color(0.4, 0.4, 0.4, 0.0)])
	smoke.scale_amount_curve = _curve([Vector2(0, 0.6), Vector2(1, 2.4)])
	smoke.emission_sphere_radius = 0.4
	# 4) kıvılcımlar
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.vertex_color_use_as_albedo = true
	spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var sparks := _particles(root, 90, 1.6, spark_mat, 0.05)
	sparks.initial_velocity_min = 6.0
	sparks.initial_velocity_max = 15.0
	sparks.damping_min = 1.0
	sparks.damping_max = 2.0
	sparks.gravity = Vector3(0, -9.8, 0)
	sparks.color_ramp = _ramp([Color(1, 0.95, 0.7, 1), Color(1, 0.55, 0.1, 1), Color(0.6, 0.1, 0.0, 0)])
	sparks.scale_amount_min = 0.5
	sparks.scale_amount_max = 1.6
	# 5) tavandan dökülen toz
	var dust_mat := _puff_mat(false, 1.0, noise)
	var dust := _particles(root, 50, 3.0, dust_mat, 0.5)
	dust.explosiveness = 0.3
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(3.0, 0.1, 3.0)
	dust.position = Vector3(0, 3.0 - (pos.y - floor_y), 0)
	dust.direction = Vector3.DOWN
	dust.spread = 15.0
	dust.initial_velocity_min = 0.2
	dust.initial_velocity_max = 0.8
	dust.gravity = Vector3(0, -1.2, 0)
	dust.color_ramp = _ramp([Color(0.55, 0.52, 0.48, 0.0), Color(0.55, 0.52, 0.48, 0.5), Color(0.55, 0.52, 0.48, 0.0)])
	dust.scale_amount_curve = _curve([Vector2(0, 0.6), Vector2(1, 1.8)])
	for p in [core, fire, smoke, sparks]:
		(p as CPUParticles3D).emitting = true
	# toz biraz sonra dökülsün
	# düğümün kendi yöntemine bağlı: patlama erken silinirse bağlantı da düşer (yakalanan düğüm hatası olmaz)
	world.get_tree().create_timer(0.25).timeout.connect(dust.set_emitting.bind(true))
	# 6) enkaz: fiziksel parçalar yere sekip yuvarlanır
	var chunk_mat := _mat(Color("#2a2622"), 0.9)
	var hot_mat := StandardMaterial3D.new()
	hot_mat.albedo_color = Color("#3a1a0a")
	hot_mat.emission_enabled = true
	hot_mat.emission = Color("#ff5a10")
	hot_mat.emission_energy_multiplier = 2.5
	for i in 14:
		var rb := RigidBody3D.new()
		var sz := Vector3(randf_range(0.03, 0.09), randf_range(0.02, 0.06), randf_range(0.03, 0.08))
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = sz
		cs.shape = bs
		rb.add_child(cs)
		_box(rb, sz, hot_mat if i % 3 == 0 else chunk_mat, Vector3.ZERO)
		rb.mass = 0.2
		root.add_child(rb)
		rb.position = Vector3(randf_range(-0.15, 0.15), randf_range(0.0, 0.2), randf_range(-0.15, 0.15))
		var dir := Vector3(randf_range(-1, 1), randf_range(0.3, 1.2), randf_range(-1, 1)).normalized()
		rb.linear_velocity = dir * randf_range(4.0, 9.0)
		rb.angular_velocity = Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
	# 7) yerde genişleyen şok halkası
	var ring := MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(1, 1)
	rq.orientation = PlaneMesh.FACE_Y
	ring.mesh = rq
	var rs := Shader.new()
	rs.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform float k = 0.0;
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float band = smoothstep(0.75, 0.92, r) * smoothstep(1.0, 0.93, r);
	ALBEDO = vec3(1.0, 0.75, 0.45) * band * 2.0;
	ALPHA = band * (1.0 - k);
}"""
	var rm := ShaderMaterial.new()
	rm.shader = rs
	ring.material_override = rm
	root.add_child(ring)
	ring.position = Vector3(0, floor_y - pos.y + 0.03, 0)
	var rt := ring.create_tween().set_parallel()
	rt.tween_property(ring, "scale", Vector3.ONE * 9.0, 0.55).from(Vector3.ONE * 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	rt.tween_method(func(v: float) -> void: rm.set_shader_parameter("k", v), 0.0, 1.0, 0.55)
	# 8) kalıcı yanık izi (yerde)
	var dec := Decal.new()
	dec.texture_albedo = scorch_texture()
	dec.size = Vector3(2.6, 0.6, 2.6)
	dec.position = Vector3(0, floor_y - pos.y, 0)
	root.add_child(dec)
	return root


# Yanık izi dokusu: ortası kömür siyahı, kenarlara doğru düzensiz biçimde kaybolur.
static func scorch_texture() -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var fn := FastNoiseLite.new()
	fn.frequency = 0.08
	for y in n:
		for x in n:
			var d := Vector2(x - n / 2.0, y - n / 2.0).length() / (n / 2.0)
			var e := d + fn.get_noise_2d(x, y) * 0.35
			var a := clampf(1.0 - smoothstep(0.35, 0.95, e), 0.0, 1.0) * 0.92
			img.set_pixel(x, y, Color(0.03, 0.025, 0.02, a))
	return ImageTexture.create_from_image(img)
