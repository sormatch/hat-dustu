# Hücre, koridor, ışıklar ve etkileşimler (koltuk, telefon, kapı).
extends Node3D

const Sfx := preload("res://scripts/sfx.gd")
const PlayerScript := preload("res://scripts/player.gd")
const HudScript := preload("res://scripts/hud.gd")

const H := 3.2  # tavan yüksekliği
const CHAIR_POS := Vector3(0.0, 0.0, -1.5)
const CHAIR_YAW := 0.8  # koltuk kapıya doğru dönük
const PHONE_POS := Vector3(1.98, 1.45, -2.25)
const DOOR_CENTER := Vector3(2.1, 1.1, 0.5)
const ROUND_TIME := 90.0
const BED_TOP := 0.5  # şiltenin oturduğu yükseklik
const LAMP_SCALE := 0.75

const CALL_LINES := [
	[0.6, "Alo? Duyuyor musun beni?"],
	[3.5, "Bu tur ortağız. Ben paylaşacağım, söz veriyorum."],
	[8.0, "Ama Elif'e güvenme. Koridorda duydum, seni satacakmış."],
	[13.0, "Karar senin. Süre dolmadan bir daha ararım."],
]

enum Phone { IDLE, RINGING, CALL }

var player: CharacterBody3D
var hud: CanvasLayer
var mats := {}

var door_pivot: Node3D
var door_open := false
var door_busy := false
var door_sfx: AudioStreamPlayer3D

var handset: Node3D
var phone_light: OmniLight3D
var ring_player: AudioStreamPlayer3D
var click_player: AudioStreamPlayer
var phone_state := Phone.IDLE
var ring_wait := 5.0
var ring_t := 0.0
var call_t := 0.0

var lamp_light: SpotLight3D
var lamp_fill: OmniLight3D
var bulb_mat: StandardMaterial3D
var flicker_left := 0.0
var round_left := ROUND_TIME

var current_target := ""

const BodyScript := preload("res://scripts/body.gd")
const WALK_ENDS := [-18.0, 18.0]
const WALK_SPEED := 1.1
var walker: AnimatableBody3D
var walker_body: Node3D
var walker_leg := 1  # hangi uca gidiyor
var walker_wait := 0.0
var test_move := Vector2.ZERO  # sadece ekran görüntüsü testleri için


func _ready() -> void:
	_setup_input()
	_make_materials()
	_build_environment()
	_build_cell()
	_build_chair()
	_build_bed_and_shelf()
	_build_window()
	_build_phone()
	_build_lamp()
	_build_door()
	_build_corridor()

	player = PlayerScript.new()
	add_child(player)
	player.global_position = Vector3(0.0, 0.0, 1.9)

	hud = HudScript.new()
	add_child(hud)
	hud.player = player
	hud.action_pressed.connect(_do_action)

	_handle_cmdline()


func _setup_input() -> void:
	var keys := {"ileri": KEY_W, "geri": KEY_S, "sol": KEY_A, "sag": KEY_D, "etkilesim": KEY_E}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = keys[action]
		InputMap.action_add_event(action, ev)


# ---------- malzemeler ----------

func _noise_tex(c1: Color, c2: Color, freq: float, sd: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = sd
	n.frequency = freq
	n.fractal_octaves = 5
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = n
	var g := Gradient.new()
	g.set_color(0, c1)
	g.set_color(1, c2)
	tex.color_ramp = g
	return tex


func _bump_tex(freq: float, sd: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = sd
	n.frequency = freq
	n.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 6.0
	tex.noise = n
	return tex


func _surface(c: Color, rough: float, scale: float, sd: int, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _noise_tex(c.darkened(0.22), c.lightened(0.05), 0.02, sd)
	m.normal_enabled = true
	m.normal_texture = _bump_tex(0.03, sd + 7)
	m.normal_scale = 0.35
	m.roughness = rough
	m.metallic = metal
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	return m


# Poly Haven'dan indirilen gerçek doku (renk + yüzey kabartısı + pürüzlülük).
func _pbr(id: String, scale: float, rough := 1.0, tint := Color.WHITE, diff := "diff.jpg", metal := 0.0) -> StandardMaterial3D:
	var dir := "res://assets/textures/%s/" % id
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(dir + diff)
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(dir + "nor.jpg")
	m.roughness_texture = load(dir + "rough.jpg")
	m.roughness = rough
	m.metallic = metal
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	return m


# Hazır 3D modeli yükler; tabanı (ya da top_y verilirse tepesi) o yüksekliğe, ortası pos'a gelir.
func model(id: String, pos: Vector3, yaw := 0.0, scale := 1.0, top_y := NAN) -> Node3D:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = yaw
	add_child(holder)
	var inst: Node3D = load("res://assets/models/%s/%s.gltf" % [id, id]).instantiate()
	inst.scale = Vector3.ONE * scale
	holder.add_child(inst)
	var bb := _bounds(inst, holder)
	var c := bb.get_center()
	inst.position = Vector3(-c.x, -bb.position.y if is_nan(top_y) else -(bb.end.y), -c.z)
	if not is_nan(top_y):
		holder.position.y = top_y
	return holder


func _bounds(n: Node, rel: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var box_ := (mi as MeshInstance3D).get_aabb()
		var xf := rel.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform
		box_ = xf * box_
		out = box_ if first else out.merge(box_)
		first = false
	return out


# Görünmez çarpışma kutusu (modellerin içinden geçilmesin diye).
func solid(size: Vector3, pos: Vector3, yaw := 0.0) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	sb.position = pos
	sb.rotation.y = yaw
	add_child(sb)


# Yüzü +z'ye bakan ince silindir (kadran, delik, ahize kulaklığı).
func _disc(parent: Node3D, pos: Vector3, radius: float, depth: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = depth
	c.radial_segments = 24
	mi.mesh = c
	mi.material_override = mat
	mi.rotation.x = PI / 2
	mi.position = pos
	parent.add_child(mi)
	return mi


func _flat(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _make_materials() -> void:
	mats.wall = _pbr("concrete_wall_008", 0.5, 1.0, Color(0.85, 0.82, 0.78))
	mats.paint = _pbr("peeling_painted_wall", 0.6, 0.8, Color(0.72, 0.78, 0.72), "diff_green.jpg")
	mats.floor = _pbr("worn_concrete_floor", 0.5, 1.0, Color(0.42, 0.42, 0.42))
	mats.ceiling = _pbr("rough_concrete", 0.5, 1.0, Color(0.45, 0.45, 0.45))
	mats.corridor_floor = _pbr("smooth_concrete_floor", 0.4, 0.3, Color(0.6, 0.65, 0.7))
	mats.corridor_wall = _pbr("concrete_wall_006", 0.45, 1.0, Color(0.7, 0.75, 0.8))
	mats.metal = _pbr("rusty_metal_02", 0.9, 1.0, Color(0.8, 0.8, 0.8), "diff.jpg", 0.5)
	mats.metal_dark = _flat(Color("#1d1f22"), 0.5, 0.7)
	mats.leather = _surface(Color("#3a2c20"), 0.45, 0.8, 9)
	mats.red = _flat(Color("#C4121A"), 0.3)
	mats.dial = _flat(Color("#B9B5AC"), 0.4, 0.3)
	mats.blanket = _surface(Color("#4a5560"), 1.0, 1.5, 10)
	mats.mattress = _flat(Color("#8a8475"), 1.0)
	mats.wood = _surface(Color("#5b4630"), 0.8, 1.0, 11)
	mats.orange = _flat(Color("#D5661E"), 0.9)


func box(size: Vector3, pos: Vector3, mat: Material, collide := true, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	(parent if parent else self).add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		sb.add_child(cs)
		mi.add_child(sb)
	return mi


# ---------- ortam ----------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.012, 0.016)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.36, 0.4)
	env.ambient_light_energy = 0.22
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.06
	env.fog_enabled = true
	env.fog_light_color = Color(0.1, 0.12, 0.15)
	env.fog_density = 0.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_cell() -> void:
	var t := 0.2
	box(Vector3(4.4, t, 6.4), Vector3(0, -t / 2, 0), mats.floor)
	box(Vector3(4.4, t, 6.4), Vector3(0, H + t / 2, 0), mats.ceiling)
	box(Vector3(4.4, H, t), Vector3(0, H / 2, -3.1), mats.wall)
	box(Vector3(4.4, H, t), Vector3(0, H / 2, 3.1), mats.wall)
	box(Vector3(t, H, 6.4), Vector3(-2.1, H / 2, 0), mats.wall)
	# sağ duvar: z 0..1 arası kapı boşluğu
	box(Vector3(t, H, 3.2), Vector3(2.1, H / 2, -1.6), mats.wall)
	box(Vector3(t, H, 2.2), Vector3(2.1, H / 2, 2.1), mats.wall)
	box(Vector3(t, H - 2.2, 1.0), Vector3(2.1, 2.2 + (H - 2.2) / 2, 0.5), mats.wall)
	# alt yarısı yeşil boyalı
	var b := 1.25
	box(Vector3(4.0, b, 0.02), Vector3(0, b / 2, -2.99), mats.paint, false)
	box(Vector3(4.0, b, 0.02), Vector3(0, b / 2, 2.99), mats.paint, false)
	box(Vector3(0.02, b, 6.0), Vector3(-1.99, b / 2, 0), mats.paint, false)
	box(Vector3(0.02, b, 3.0), Vector3(1.99, b / 2, -1.5), mats.paint, false)
	box(Vector3(0.02, b, 2.0), Vector3(1.99, b / 2, 2.0), mats.paint, false)
	# kapı kasası
	for z in [0.0, 1.0]:
		box(Vector3(0.24, 2.25, 0.07), Vector3(2.1, 1.12, z), mats.metal_dark, false)
	box(Vector3(0.24, 0.07, 1.07), Vector3(2.1, 2.22, 0.5), mats.metal_dark, false)


func _build_chair() -> void:
	model("modern_arm_chair_01", CHAIR_POS, CHAIR_YAW)
	solid(Vector3(0.8, 0.9, 0.9), CHAIR_POS + Vector3(0, 0.45, 0), CHAIR_YAW)


func _build_bed_and_shelf() -> void:
	model("old_bed_frame", Vector3(-1.5, 0, -1.95))
	solid(Vector3(0.9, 0.55, 2.0), Vector3(-1.5, 0.27, -1.95))
	box(Vector3(0.8, 0.12, 1.85), Vector3(-1.5, BED_TOP, -1.95), mats.mattress, false)
	box(Vector3(0.84, 0.05, 1.2), Vector3(-1.5, BED_TOP + 0.075, -1.55), mats.blanket, false)
	var pillow := box(Vector3(0.55, 0.1, 0.35), Vector3(-1.5, BED_TOP + 0.1, -2.6), mats.mattress, false)
	pillow.rotation.y = deg_to_rad(4)
	# karşı duvarda eski raf
	model("Shelf_01", Vector3(-1.35, 0, 2.85), PI, 0.85)
	solid(Vector3(0.9, 1.8, 0.25), Vector3(-1.35, 0.9, 2.85))


func _build_window() -> void:
	var p := Vector3(-1.99, 2.45, 0.9)
	box(Vector3(0.03, 0.55, 0.8), p, _glow(Color("#5d7fa8"), 1.4), false)
	for i in 5:
		box(Vector3(0.05, 0.6, 0.03), p + Vector3(0.03, 0, -0.32 + i * 0.16), mats.metal_dark, false)
	var moon := OmniLight3D.new()
	moon.light_color = Color("#7f9fd0")
	moon.light_energy = 0.5
	moon.omni_range = 3.0
	moon.position = p + Vector3(0.4, -0.2, 0)
	add_child(moon)


func _build_phone() -> void:
	var root := Node3D.new()
	root.position = PHONE_POS + Vector3(-0.08, 0, 0)
	root.rotation.y = -PI / 2
	root.scale = Vector3.ONE * 1.35
	add_child(root)
	var red: StandardMaterial3D = mats.red
	red.roughness = 0.22
	red.clearcoat_enabled = true
	red.clearcoat = 0.6
	var dark := _flat(Color("#141414"), 0.6)
	# gövde: arkada ince duvar plakası, önde öne doğru incelen kasa
	box(Vector3(0.24, 0.34, 0.03), Vector3(0, 0, -0.04), red, true, root)
	box(Vector3(0.21, 0.3, 0.07), Vector3(0, -0.01, 0.01), red, false, root)
	box(Vector3(0.17, 0.05, 0.05), Vector3(0, 0.15, 0.03), red, false, root)
	# çevirmeli kadran: gümüş halka, on parmak deliği, ortada beyaz etiket
	_disc(root, Vector3(0.0, -0.03, 0.05), 0.072, 0.012, mats.dial)
	for i in 10:
		var a := -PI * 0.15 + i * (PI * 1.6 / 9.0)
		_disc(root, Vector3(cos(a) * 0.05, -0.03 + sin(a) * 0.05, 0.058), 0.011, 0.006, dark)
	_disc(root, Vector3(0.0, -0.03, 0.058), 0.026, 0.008, _flat(Color("#e8e2d2"), 0.5))
	# ahize: kasanın solunda dikey asılı
	handset = Node3D.new()
	handset.position = Vector3(-0.15, 0.02, 0.04)
	root.add_child(handset)
	var grip := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.024
	cap.height = 0.26
	grip.mesh = cap
	grip.material_override = red
	handset.add_child(grip)
	for y in [0.12, -0.12]:
		var cup := _disc(handset, Vector3(0, y, 0.02), 0.042, 0.05, red)
		cup.rotation.x = PI / 2 + (0.25 if y > 0 else -0.25)
	# kıvrımlı kablo: ahizenin altından kasaya sarkan halkalar
	var ring := TorusMesh.new()
	ring.inner_radius = 0.009
	ring.outer_radius = 0.019
	ring.rings = 8
	ring.ring_segments = 6
	var n := 26
	for i in n:
		var k := float(i) / (n - 1)
		var r := MeshInstance3D.new()
		r.mesh = ring
		r.material_override = red
		r.position = Vector3(-0.15 + k * 0.13, -0.15 - sin(k * PI) * 0.2, 0.04)
		r.rotation.z = (k - 0.5) * 1.6
		root.add_child(r)

	phone_light = OmniLight3D.new()
	phone_light.light_color = Color("#ff5a2a")
	phone_light.light_energy = 0.0
	phone_light.omni_range = 2.2
	phone_light.position = PHONE_POS + Vector3(-0.6, 0.15, 0)
	add_child(phone_light)

	ring_player = AudioStreamPlayer3D.new()
	ring_player.stream = Sfx.ring()
	ring_player.position = PHONE_POS
	ring_player.unit_size = 4.0
	add_child(ring_player)
	click_player = AudioStreamPlayer.new()
	click_player.stream = Sfx.click()
	add_child(click_player)


func _build_lamp() -> void:
	var p := Vector3(0, H, CHAIR_POS.z + 0.2)
	var lamp := model("hanging_industrial_lamp", Vector3(p.x, 0, p.z), 0.0, LAMP_SCALE, H)
	var lamp_bottom := H - _bounds(lamp, lamp).size.y
	bulb_mat = _glow(Color("#ffd27a"), 6.0)
	var bulb := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.06
	bs.height = 0.12
	bulb.mesh = bs
	bulb.material_override = bulb_mat
	bulb.position = Vector3(p.x, lamp_bottom + 0.1, p.z)
	add_child(bulb)
	p.y = lamp_bottom + 0.62

	lamp_light = SpotLight3D.new()
	lamp_light.light_color = Color("#ffc46b")
	lamp_light.light_energy = 5.5
	lamp_light.spot_range = 7.0
	lamp_light.spot_angle = 62.0
	lamp_light.spot_attenuation = 0.8
	lamp_light.shadow_enabled = true
	lamp_light.position = p - Vector3(0, 0.66, 0)
	lamp_light.rotation.x = -PI / 2
	add_child(lamp_light)
	lamp_fill = OmniLight3D.new()
	lamp_fill.light_color = Color("#ffb860")
	lamp_fill.light_energy = 0.45
	lamp_fill.omni_range = 6.0
	lamp_fill.position = p - Vector3(0, 0.9, 0)
	add_child(lamp_fill)

	# ışıkta uçuşan toz
	var dust := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.012)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(1.0, 0.86, 0.6, 0.55)
	q.material = dm
	dust.mesh = q
	dust.amount = 90
	dust.lifetime = 10.0
	dust.preprocess = 10.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(1.1, 1.2, 1.1)
	dust.gravity = Vector3(0, -0.01, 0)
	dust.initial_velocity_min = 0.01
	dust.initial_velocity_max = 0.05
	dust.direction = Vector3(0, 1, 0)
	dust.spread = 180.0
	dust.position = Vector3(0, 1.4, CHAIR_POS.z + 0.2)
	add_child(dust)


func _build_door() -> void:
	# menteşe noktasının kendisi hareketli gövde; döndükçe çarpışması da döner
	var body := AnimatableBody3D.new()
	body.sync_to_physics = false
	body.position = Vector3(2.1, 0, 0.0)
	add_child(body)
	door_pivot = body
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.08, 2.2, 0.98)
	cs.shape = sh
	cs.position = Vector3(0, 1.1, 0.5)
	body.add_child(cs)
	box(Vector3(0.08, 2.18, 0.98), Vector3(0, 1.1, 0.5), mats.metal, false, door_pivot)
	# perçin şeritleri
	for y in [0.25, 1.1, 1.95]:
		box(Vector3(0.1, 0.05, 0.98), Vector3(0, y, 0.5), mats.metal_dark, false, door_pivot)
	# parmaklıklı küçük pencere ve yemek deliği
	box(Vector3(0.1, 0.36, 0.42), Vector3(0, 1.62, 0.5), _flat(Color("#0b0c0d"), 1.0), false, door_pivot)
	for i in 4:
		box(Vector3(0.12, 0.36, 0.025), Vector3(0, 1.62, 0.34 + i * 0.105), mats.metal_dark, false, door_pivot)
	box(Vector3(0.1, 0.07, 0.36), Vector3(0, 1.0, 0.5), mats.metal_dark, false, door_pivot)
	box(Vector3(0.14, 0.05, 0.12), Vector3(0, 1.1, 0.9), mats.dial, false, door_pivot)
	door_sfx = AudioStreamPlayer3D.new()
	door_sfx.position = DOOR_CENTER
	add_child(door_sfx)


func _build_corridor() -> void:
	var x0 := 2.2
	var x1 := 5.6
	var cx := (x0 + x1) / 2.0
	var w := x1 - x0
	var zmin := -24
	var zmax := 24
	for z in range(zmin, zmax, 4):
		box(Vector3(w, 0.2, 4.0), Vector3(cx, -0.1, z + 2.0), mats.corridor_floor)
		box(Vector3(w, 0.2, 4.0), Vector3(cx, H + 0.1, z + 2.0), mats.ceiling, false)
		box(Vector3(0.2, H, 4.0), Vector3(x1 + 0.1, H / 2, z + 2.0), mats.corridor_wall)
	for z in range(zmin, -4, 4):
		box(Vector3(0.2, H, 4.0), Vector3(2.1, H / 2, z + 2.0), mats.corridor_wall)
	for z in range(4, zmax, 4):
		box(Vector3(0.2, H, 4.0), Vector3(2.1, H / 2, z + 2.0), mats.corridor_wall)
	box(Vector3(0.2, H, 0.8), Vector3(2.1, H / 2, -3.6), mats.corridor_wall)
	box(Vector3(0.2, H, 0.8), Vector3(2.1, H / 2, 3.6), mats.corridor_wall)
	box(Vector3(w, H, 0.2), Vector3(cx, H / 2, zmin - 0.1), mats.corridor_wall)
	box(Vector3(w, H, 0.2), Vector3(cx, H / 2, zmax + 0.1), mats.corridor_wall)

	# karşılıklı hücre kapıları ve numaraları
	var num := 14
	for k in range(-7, 8):
		var z := 0.5 + k * 3.0
		if z < zmin + 1 or z > zmax - 1:
			continue
		_fake_door(x1, z, -1.0, 30 + k, k % 3 == 1)
		if k != 0:
			_fake_door(2.2, z, 1.0, num + k, k % 4 == 2)
	_door_label(Vector3(2.21, 2.6, 0.5), str(num), 1.0)

	# floresan lambalar
	for z in range(-21, 22, 6):
		model("mounted_fluorescent_lights", Vector3(cx, 0, z), PI / 2, 1.0, H)
		var l := OmniLight3D.new()
		l.light_color = Color("#cfe2ff")
		l.light_energy = 1.3
		l.omni_range = 5.5
		l.position = Vector3(cx, H - 0.3, z)
		add_child(l)

	# koridorda bir uçtan öbür uca yürüyen mahkum
	walker = AnimatableBody3D.new()
	walker.sync_to_physics = false
	walker.position = Vector3(cx + 0.5, 0, -16.0)
	add_child(walker)
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = 0.3
	sh.height = 1.75
	cs.shape = sh
	cs.position.y = 0.88
	walker.add_child(cs)
	walker_body = BodyScript.new()
	walker.add_child(walker_body)

	var probe := ReflectionProbe.new()
	probe.size = Vector3(w, H, 48.0)
	probe.position = Vector3(cx, H / 2, 0)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(probe)


# Koridor duvarındaki açılmayan hücre kapısı. side: +1 = +x'e bakar, -1 = -x'e bakar.
func _fake_door(x: float, z: float, side: float, number: int, leak: bool) -> void:
	var fx := x + side * 0.05
	box(Vector3(0.1, 2.2, 1.0), Vector3(fx, 1.1, z), mats.metal, false)
	for y in [0.25, 1.1, 1.95]:
		box(Vector3(0.12, 0.05, 1.0), Vector3(fx, y, z), mats.metal_dark, false)
	box(Vector3(0.12, 0.34, 0.4), Vector3(fx, 1.62, z), _glow(Color("#ffb45a"), 0.9 if leak else 0.25), false)
	for i in 4:
		box(Vector3(0.14, 0.34, 0.025), Vector3(fx, 1.62, z - 0.16 + i * 0.105), mats.metal_dark, false)
	if leak:
		box(Vector3(0.12, 2.1, 0.03), Vector3(fx, 1.05, z + 0.5), _glow(Color("#ffb45a"), 2.5), false)
	_door_label(Vector3(x + side * 0.11, 2.6, z), str(number), side)


func _door_label(pos: Vector3, text: String, side: float) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 72
	l.pixel_size = 0.004
	l.modulate = Color(0.85, 0.85, 0.82)
	l.position = pos
	l.rotation.y = PI / 2 * side
	add_child(l)


# ---------- oyun döngüsü ----------

func _process(delta: float) -> void:
	player.move_input = test_move if test_move != Vector2.ZERO else hud.move
	_update_walker(delta)
	_update_phone(delta)
	_update_lamp(delta)
	_update_target()
	round_left -= delta
	if round_left <= 0.0:
		round_left = ROUND_TIME
	hud.set_timer(round_left)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("etkilesim"):
		_do_action()


func _update_target() -> void:
	var cam: Camera3D = player.camera
	var fwd := -cam.global_transform.basis.z
	var best := ""
	var best_score := -INF
	var targets := [["chair", CHAIR_POS + Vector3(0, 0.5, 0), 2.0], ["door", DOOR_CENTER, 2.2]]
	if phone_state == Phone.RINGING:
		targets.append(["phone", PHONE_POS, 2.4])
	for t in targets:
		var to: Vector3 = t[1] - cam.global_position
		var d := to.length()
		if d > t[2]:
			continue
		var facing := fwd.dot(to.normalized())
		if facing < 0.5 and not (t[0] == "phone" and player.seated):
			continue
		var score := facing - d * 0.15 + (2.0 if t[0] == "phone" else 0.0)
		if score > best_score:
			best_score = score
			best = t[0]
	if player.seated and best != "phone":
		best = "chair"
	if phone_state == Phone.CALL:
		best = "hangup"
	current_target = best
	match best:
		"chair":
			hud.set_action("Kalk" if player.seated else "Otur")
		"door":
			hud.set_action("Kapıyı kapat" if door_open else "Kapıyı aç")
		"phone":
			hud.set_action("Cevapla", true)
		"hangup":
			hud.set_action("Kapat", true)
		_:
			hud.set_action("")


func _do_action() -> void:
	if player.busy:
		return
	match current_target:
		"chair":
			if player.seated:
				player.stand(CHAIR_POS + Vector3(sin(CHAIR_YAW), 0, cos(CHAIR_YAW)) * 0.95)
			else:
				player.sit(CHAIR_POS, PI + CHAIR_YAW)
		"door":
			_toggle_door()
		"phone":
			_answer()
		"hangup":
			_hang_up()


func _toggle_door() -> void:
	if door_busy:
		return
	door_busy = true
	door_open = not door_open
	player.push()
	door_sfx.stream = Sfx.door(door_open)
	door_sfx.play()
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(door_pivot, "rotation:y", deg_to_rad(100.0) if door_open else 0.0, 0.8)
	tw.tween_callback(func() -> void: door_busy = false)


func _update_phone(delta: float) -> void:
	match phone_state:
		Phone.IDLE:
			ring_wait -= delta
			if ring_wait <= 0.0:
				phone_state = Phone.RINGING
				ring_t = 0.0
				ring_player.play()
				hud.ring_label.visible = true
		Phone.RINGING:
			ring_t += delta
			var cyc := fmod(ring_t, 3.0)
			var on := cyc < 1.05
			handset.rotation.z = sin(ring_t * 70.0) * 0.07 if on else 0.0
			phone_light.light_energy = (0.7 + sin(ring_t * 40.0) * 0.25) if on else 0.12
			hud.ring_label.modulate.a = 0.6 + 0.4 * sin(ring_t * 6.0)
			if ring_t > 24.0:
				_stop_ring()
				phone_state = Phone.IDLE
				ring_wait = 12.0
		Phone.CALL:
			call_t += delta
			var line := ""
			for l in CALL_LINES:
				if call_t >= l[0]:
					line = l[1]
			hud.show_call("Deniz", line if line != "" else "…")
			if call_t > 22.0:
				_hang_up()


func _stop_ring() -> void:
	ring_player.stop()
	handset.rotation.z = 0.0
	phone_light.light_energy = 0.0
	hud.ring_label.visible = false


func _answer() -> void:
	_stop_ring()
	phone_state = Phone.CALL
	call_t = 0.0
	handset.visible = false
	click_player.play()
	player.set_call(true)


func _hang_up() -> void:
	phone_state = Phone.IDLE
	ring_wait = 20.0
	handset.visible = true
	hud.hide_call()
	click_player.play()
	player.set_call(false)


# Mahkum koridorun iki ucu arasında yürür, uçlarda biraz bekleyip geri döner.
# Oyuncu tam önüne çıkarsa durur.
func _update_walker(delta: float) -> void:
	if walker_wait > 0.0:
		walker_wait -= delta
		walker_body.walk = 0.0
		return
	var target_z: float = WALK_ENDS[walker_leg]
	var dz := target_z - walker.position.z
	var dir := signf(dz)
	var ahead := walker.position + Vector3(0, 0, dir * 0.9)
	var blocked := ahead.distance_to(player.global_position * Vector3(1, 0, 1)) < 0.75
	walker.rotation.y = lerp_angle(walker.rotation.y, 0.0 if dir < 0.0 else PI, minf(1.0, delta * 5.0))
	if blocked:
		walker_body.walk = 0.0
		return
	var step := dir * WALK_SPEED * delta
	if absf(step) >= absf(dz):
		walker.position.z = target_z
		walker_leg = 1 - walker_leg
		walker_wait = randf_range(1.5, 4.0)
	else:
		walker.position.z += step
	walker_body.walk = WALK_SPEED / 1.4


func _update_lamp(delta: float) -> void:
	if flicker_left <= 0.0 and randf() < delta * 0.12:
		flicker_left = randf_range(0.2, 0.5)
	var k := 1.0
	if flicker_left > 0.0:
		flicker_left -= delta
		k = 0.15 if randf() < 0.5 else 1.0
	lamp_light.light_energy = 5.5 * k
	lamp_fill.light_energy = 0.45 * k
	bulb_mat.emission_energy_multiplier = 6.0 * k


# ---------- ekran görüntüsü (test için) ----------
# Kullanım: Godot --path . -- shot=dosya.png pose=cell|phone|corridor|seated

func _handle_cmdline() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	if not args.has("shot"):
		return
	var pose: String = args.get("pose", "cell")
	match pose:
		"phone":
			ring_wait = 0.0
			player.global_position = Vector3(1.05, 0, -2.25)
			player.rotation.y = -PI / 2
			player.head.rotation.x = deg_to_rad(-9)
		"corridor":
			door_open = true
			door_pivot.rotation.y = deg_to_rad(100)
			player.global_position = Vector3(3.9, 0, 3.0)
		"seated":
			ring_wait = 0.0
			player.seated = true
			player.col.disabled = true
			player.global_position = CHAIR_POS
			player.rotation.y = PI + CHAIR_YAW
			player.head.position.y = player.EYE_SEAT
			player.head.rotation.x = deg_to_rad(-55)
		"call":
			ring_wait = 0.0
			player.global_position = Vector3(1.05, 0, -2.25)
			player.rotation.y = -PI / 2
			await get_tree().create_timer(0.5).timeout
			current_target = "phone"
			_do_action()
		"lookdown":
			player.head.rotation.x = deg_to_rad(-70)
			test_move = Vector2(0, -1)
		"walkout":
			# kapıyı açıp hücreden koridora yürür; görüntü koridordan alınır
			door_open = true
			door_pivot.rotation.y = deg_to_rad(100)
			player.global_position = Vector3(1.0, 0, 0.5)
			player.rotation.y = -PI / 2
			test_move = Vector2(0, -1)
			await get_tree().create_timer(1.2).timeout
			for ci in player.get_slide_collision_count():
				var cc := player.get_slide_collision(ci)
				print("çarpışma: ", cc.get_collider(), " ", cc.get_collider().global_position, " normal ", cc.get_normal())
			test_move = Vector2.ZERO
			player.rotation.y = 0.0
			player.head.rotation.x = deg_to_rad(-5)
			walker.position.z = -6.0
			walker_wait = 0.0
			walker_leg = 1
	await get_tree().create_timer(float(args.get("wait", "2.5"))).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args["shot"])
	print("oyuncu konumu: ", player.global_position)
	get_tree().quit()
