# Bir hapishane hücresi: duvarlar, koltuk, ranza, raf, pencere, kırmızı telefon, lamba ve kapı.
# Hücrenin içi yerel koordinatlarda kurulur; hücre koridor boyunca z ekseninde dizilir.
extends Node3D

const Sfx := preload("res://scripts/sfx.gd")

const H := 3.2
const CHAIR_POS := Vector3(0.0, 0.0, -1.5)
const CHAIR_YAW := 0.8  # koltuk kapıya doğru dönük
const PHONE_POS := Vector3(1.98, 1.45, -2.25)
const DOOR_CENTER := Vector3(2.1, 1.1, 0.5)
const BED_TOP := 0.5
const LAMP_SCALE := 0.75

var w: Node3D  # main.gd: malzemeler ve yardımcılar
var index := 0
var number := 14
var detailed := false  # sadece oyuncunun kendi hücresinde gölge ve toz

var door_pivot: AnimatableBody3D
var door_open := false
var door_busy := false
var door_sfx: AudioStreamPlayer3D
var door_sfx2: AudioStreamPlayer3D
var handset: Node3D
var phone_light: OmniLight3D
var ring_player: AudioStreamPlayer3D
var ringing := false
var ring_t := 0.0
var lamp_light: SpotLight3D
var lamp_fill: OmniLight3D
var bulb_mat: StandardMaterial3D
var flicker_left := 0.0
var locked := false
var moon: OmniLight3D
var dust: CPUParticles3D


# Oyuncunun kendi hücresi: gölgeler, ay ışığı ve toz açılır (telefonu yormamak için diğerlerinde kapalı).
# Kimsenin olmadığı hücre: ışık kapalı, kapı kilitli.
func lock_empty() -> void:
	locked = true
	lamp_light.visible = false
	lamp_fill.visible = false
	bulb_mat.emission_energy_multiplier = 0.0
	set_process(false)


func set_detailed(on: bool) -> void:
	detailed = on
	lamp_light.shadow_enabled = on
	moon.visible = on
	dust.visible = on
	dust.emitting = on


func build() -> void:
	_build_room()
	w.model("modern_arm_chair_01", CHAIR_POS, CHAIR_YAW, 1.0, NAN, self)
	w.solid(Vector3(0.8, 0.9, 0.9), CHAIR_POS + Vector3(0, 0.45, 0), CHAIR_YAW, self)
	_build_bed_and_shelf()
	_build_window()
	_build_phone()
	_build_lamp()
	_build_door()
	_decorate()


# Her hücreye farklı birkaç eşya: kova, kitaplar, masa ve teneke bardak, poster, tuvalet, kağıtlar.
func _decorate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + index
	var m: Dictionary = w.mats
	var tin: StandardMaterial3D = w._flat(Color("#8c8f93"), 0.45, 0.8)
	var white: StandardMaterial3D = w._flat(Color("#d9d6cf"), 0.35)
	var wood: StandardMaterial3D = w._flat(Color("#5b4630"), 0.8)
	var kinds := ["kova", "kitap", "masa", "tuvalet", "kagit", "kutu"]
	_posters(rng)
	for i in kinds.size():
		var j := rng.randi_range(i, kinds.size() - 1)
		var tmp = kinds[i]
		kinds[i] = kinds[j]
		kinds[j] = tmp
	for kind in kinds.slice(0, 4):
		match kind:
			"kova":
				var b: MeshInstance3D = w._disc(self, Vector3(-1.65, 0.16, -0.55), 0.15, 0.32, tin)
				b.rotation.x = 0.0
			"kitap":
				for k in 4:
					var bk: MeshInstance3D = w.box(Vector3(0.22, 0.04, 0.16), Vector3(-0.6, 0.02 + k * 0.042, 2.55), w._flat(Color.from_hsv(rng.randf(), 0.5, 0.45), 0.8), false, self)
					bk.rotation.y = rng.randf_range(-0.3, 0.3)
			"masa":
				w.box(Vector3(0.7, 0.04, 0.45), Vector3(1.55, 0.72, 2.6), wood, true, self)
				for x in [-0.3, 0.3]:
					for z in [-0.18, 0.18]:
						w.box(Vector3(0.04, 0.7, 0.04), Vector3(1.55 + x, 0.35, 2.6 + z), wood, false, self)
				var cup: MeshInstance3D = w._disc(self, Vector3(1.45, 0.79, 2.55), 0.04, 0.1, tin)
				cup.rotation.x = 0.0
			"tuvalet":
				w.box(Vector3(0.4, 0.4, 0.5), Vector3(1.65, 0.2, 2.75), white, true, self)
				w.box(Vector3(0.42, 0.05, 0.52), Vector3(1.65, 0.42, 2.73), white, false, self)
			"kagit":
				for k in 5:
					var pp: MeshInstance3D = w.box(Vector3(0.18, 0.004, 0.25), Vector3(rng.randf_range(-0.8, 1.2), 0.003, rng.randf_range(0.3, 2.4)), white, false, self)
					pp.rotation.y = rng.randf() * TAU
			"kutu":
				w.box(Vector3(0.45, 0.35, 0.35), Vector3(-0.9, 0.175, 2.75), w._flat(Color("#9a7a4f"), 0.95), true, self)


const POSTERS := ["sahil", "araba", "boks", "aranan", "takvim", "harita", "uzay", "kedi"]


# Duvara bantlanmış 1-2 poster (her hücrede farklı), hafif yamuk.
func _posters(rng: RandomNumberGenerator) -> void:
	var spots := [Vector3(-0.9, 1.75, -2.985), Vector3(0.35, 1.85, -2.985)]
	var first := (index * 3) % POSTERS.size()
	for k in (1 if rng.randf() < 0.4 else 2):
		var tex: Texture2D = load("res://assets/poster/poster_%s.png" % POSTERS[(first + k * 5) % POSTERS.size()])
		if not tex:
			continue
		var q := QuadMesh.new()
		q.size = Vector2(0.5, 0.5 * tex.get_height() / tex.get_width())
		var mi := MeshInstance3D.new()
		mi.mesh = q
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.roughness = 0.9
		mi.material_override = mat
		mi.position = spots[k] + Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.08, 0.08), 0)
		mi.rotation.z = rng.randf_range(-0.06, 0.06)
		add_child(mi)


func chair_world() -> Vector3:
	return to_global(CHAIR_POS)


func phone_world() -> Vector3:
	return to_global(PHONE_POS)


func door_world() -> Vector3:
	return to_global(DOOR_CENTER)


func spawn_world() -> Vector3:
	return to_global(Vector3(0.0, 0.0, 1.9))


func _build_room() -> void:
	var t := 0.2
	var m: Dictionary = w.mats
	w.box(Vector3(4.4, t, 6.4), Vector3(0, -t / 2, 0), m.floor, true, self)
	w.box(Vector3(4.4, t, 6.4), Vector3(0, H + t / 2, 0), m.ceiling, true, self)
	w.box(Vector3(4.4, H, t), Vector3(0, H / 2, -3.1), m.wall, true, self)
	w.box(Vector3(4.4, H, t), Vector3(0, H / 2, 3.1), m.wall, true, self)
	w.box(Vector3(t, H, 6.4), Vector3(-2.1, H / 2, 0), m.wall, true, self)
	# sağ duvar: z 0..1 arası kapı boşluğu
	w.box(Vector3(t, H, 3.2), Vector3(2.1, H / 2, -1.6), m.wall, true, self)
	w.box(Vector3(t, H, 2.2), Vector3(2.1, H / 2, 2.1), m.wall, true, self)
	w.box(Vector3(t, H - 2.2, 1.0), Vector3(2.1, 2.2 + (H - 2.2) / 2, 0.5), m.wall, true, self)
	# alt yarısı yeşil boyalı
	var b := 1.25
	w.box(Vector3(4.0, b, 0.02), Vector3(0, b / 2, -2.99), m.paint, false, self)
	w.box(Vector3(4.0, b, 0.02), Vector3(0, b / 2, 2.99), m.paint, false, self)
	w.box(Vector3(0.02, b, 6.0), Vector3(-1.99, b / 2, 0), m.paint, false, self)
	w.box(Vector3(0.02, b, 3.0), Vector3(1.99, b / 2, -1.5), m.paint, false, self)
	w.box(Vector3(0.02, b, 2.0), Vector3(1.99, b / 2, 2.0), m.paint, false, self)
	# kapı kasası
	for z in [0.0, 1.0]:
		w.box(Vector3(0.24, 2.25, 0.07), Vector3(2.1, 1.12, z), m.metal_dark, false, self)
	w.box(Vector3(0.24, 0.07, 1.07), Vector3(2.1, 2.22, 0.5), m.metal_dark, false, self)
	# koridordan görünen hücre numarası
	var l := Label3D.new()
	l.text = str(number)
	l.font_size = 72
	l.pixel_size = 0.004
	l.modulate = Color(0.85, 0.85, 0.82)
	l.position = Vector3(2.21, 2.6, 0.5)
	l.rotation.y = PI / 2
	add_child(l)


func _build_bed_and_shelf() -> void:
	var m: Dictionary = w.mats
	w.model("old_bed_frame", Vector3(-1.5, 0, -1.95), 0.0, 1.0, NAN, self)
	w.solid(Vector3(0.9, 0.55, 2.0), Vector3(-1.5, 0.27, -1.95), 0.0, self)
	w.box(Vector3(0.8, 0.12, 1.85), Vector3(-1.5, BED_TOP, -1.95), m.mattress, false, self)
	w.box(Vector3(0.84, 0.05, 1.2), Vector3(-1.5, BED_TOP + 0.075, -1.55), m.blanket, false, self)
	var pillow: MeshInstance3D = w.box(Vector3(0.55, 0.1, 0.35), Vector3(-1.5, BED_TOP + 0.1, -2.6), m.mattress, false, self)
	pillow.rotation.y = deg_to_rad(4)
	w.model("Shelf_01", Vector3(-1.35, 0, 2.85), PI, 0.85, NAN, self)
	w.solid(Vector3(0.9, 1.8, 0.25), Vector3(-1.35, 0.9, 2.85), 0.0, self)


func _build_window() -> void:
	var p := Vector3(-1.99, 2.45, 0.9)
	w.box(Vector3(0.03, 0.55, 0.8), p, w.glow_window, false, self)
	for i in 5:
		w.box(Vector3(0.05, 0.6, 0.03), p + Vector3(0.03, 0, -0.32 + i * 0.16), w.mats.metal_dark, false, self)
	moon = OmniLight3D.new()
	moon.light_color = Color("#7f9fd0")
	moon.light_energy = 0.5
	moon.omni_range = 3.0
	moon.position = p + Vector3(0.4, -0.2, 0)
	moon.visible = detailed
	add_child(moon)


func _build_phone() -> void:
	var root := Node3D.new()
	root.position = PHONE_POS + Vector3(-0.08, 0, 0)
	root.rotation.y = -PI / 2
	root.scale = Vector3.ONE * 1.35
	add_child(root)
	var red: StandardMaterial3D = w.mats.red
	var dark: StandardMaterial3D = w.mats.phone_dark
	w.box(Vector3(0.24, 0.34, 0.03), Vector3(0, 0, -0.04), red, true, root)
	w.box(Vector3(0.21, 0.3, 0.07), Vector3(0, -0.01, 0.01), red, false, root)
	w.box(Vector3(0.17, 0.05, 0.05), Vector3(0, 0.15, 0.03), red, false, root)
	# çevirmeli kadran: gümüş halka, on parmak deliği, ortada beyaz etiket
	w._disc(root, Vector3(0.0, -0.03, 0.05), 0.072, 0.012, w.mats.dial)
	for i in 10:
		var a := -PI * 0.15 + i * (PI * 1.6 / 9.0)
		w._disc(root, Vector3(cos(a) * 0.05, -0.03 + sin(a) * 0.05, 0.058), 0.011, 0.006, dark)
	w._disc(root, Vector3(0.0, -0.03, 0.058), 0.026, 0.008, w.mats.dial_label)
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
		var cup: MeshInstance3D = w._disc(handset, Vector3(0, y, 0.02), 0.042, 0.05, red)
		cup.rotation.x = PI / 2 + (0.25 if y > 0 else -0.25)
	# kıvrımlı kablo
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
	ring_player.stream = w.ring_stream
	ring_player.position = PHONE_POS
	ring_player.unit_size = 4.0
	add_child(ring_player)


func _build_lamp() -> void:
	var p := Vector3(0, H, CHAIR_POS.z + 0.2)
	var lamp: Node3D = w.model("hanging_industrial_lamp", Vector3(p.x, 0, p.z), 0.0, LAMP_SCALE, H, self)
	var lamp_bottom: float = H - w._bounds(lamp, lamp).size.y
	bulb_mat = w._glow(Color("#ffd27a"), 6.0)
	var bulb := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.06
	bs.height = 0.12
	bulb.mesh = bs
	bulb.material_override = bulb_mat
	bulb.position = Vector3(p.x, lamp_bottom + 0.1, p.z)
	add_child(bulb)
	p.y = lamp_bottom - 0.04

	lamp_light = SpotLight3D.new()
	lamp_light.light_color = Color("#ffc46b")
	lamp_light.light_energy = 5.5
	lamp_light.spot_range = 7.0
	lamp_light.spot_angle = 62.0
	lamp_light.spot_attenuation = 0.8
	lamp_light.shadow_enabled = detailed
	lamp_light.position = p
	lamp_light.rotation.x = -PI / 2
	add_child(lamp_light)
	lamp_fill = OmniLight3D.new()
	lamp_fill.light_color = Color("#ffb860")
	lamp_fill.light_energy = 0.45
	lamp_fill.omni_range = 6.0
	lamp_fill.position = p - Vector3(0, 0.24, 0)
	add_child(lamp_fill)

	if true:
		# ışıkta uçuşan toz (sadece oyuncunun kendi hücresinde açık)
		dust = CPUParticles3D.new()
		dust.visible = detailed
		dust.emitting = detailed
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
	var m: Dictionary = w.mats
	# menteşe noktasının kendisi hareketli gövde; döndükçe çarpışması da döner
	door_pivot = AnimatableBody3D.new()
	door_pivot.sync_to_physics = false
	door_pivot.position = Vector3(2.1, 0, 0.0)
	add_child(door_pivot)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.08, 2.2, 0.98)
	cs.shape = sh
	cs.position = Vector3(0, 1.1, 0.5)
	door_pivot.add_child(cs)
	w.box(Vector3(0.08, 2.18, 0.98), Vector3(0, 1.1, 0.5), m.metal, false, door_pivot)
	for y in [0.25, 1.1, 1.95]:
		w.box(Vector3(0.1, 0.05, 0.98), Vector3(0, y, 0.5), m.metal_dark, false, door_pivot)
	w.box(Vector3(0.1, 0.36, 0.42), Vector3(0, 1.62, 0.5), m.door_window, false, door_pivot)
	for i in 4:
		w.box(Vector3(0.12, 0.36, 0.025), Vector3(0, 1.62, 0.34 + i * 0.105), m.metal_dark, false, door_pivot)
	w.box(Vector3(0.1, 0.07, 0.36), Vector3(0, 1.0, 0.5), m.metal_dark, false, door_pivot)
	w.box(Vector3(0.14, 0.05, 0.12), Vector3(0, 1.1, 0.9), m.dial, false, door_pivot)
	door_sfx = AudioStreamPlayer3D.new()
	door_sfx.position = DOOR_CENTER
	door_sfx.unit_size = 4.0
	add_child(door_sfx)
	door_sfx2 = AudioStreamPlayer3D.new()
	door_sfx2.position = DOOR_CENTER
	door_sfx2.unit_size = 4.0
	add_child(door_sfx2)


func set_door(open: bool, instant := false) -> void:
	if open == door_open:
		return
	door_open = open
	if instant:
		door_pivot.rotation.y = deg_to_rad(100.0) if open else 0.0
		return
	door_busy = true
	# gerçek kayıtlar: açarken kilit sonra gıcırtı, kapatırken ağır metal çarpma sonra kilit tıkı
	door_sfx.stream = w.snd_latch if open else w.snd_slam
	door_sfx.play()
	door_sfx2.stream = w.snd_creak if open else w.snd_click
	get_tree().create_timer(0.18 if open else 0.12).timeout.connect(door_sfx2.play)
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(door_pivot, "rotation:y", deg_to_rad(100.0) if open else 0.0, 0.8)
	tw.tween_callback(func() -> void: door_busy = false)


func set_ringing(on: bool) -> void:
	if on == ringing:
		return
	ringing = on
	ring_t = 0.0
	if on:
		ring_player.play()
	else:
		ring_player.stop()
		handset.rotation.z = 0.0
		phone_light.light_energy = 0.0


func set_handset_lifted(lifted: bool) -> void:
	handset.visible = not lifted


func _process(delta: float) -> void:
	if ringing:
		ring_t += delta
		var on := fmod(ring_t, 3.0) < 1.05
		handset.rotation.z = sin(ring_t * 70.0) * 0.07 if on else 0.0
		phone_light.light_energy = (0.7 + sin(ring_t * 40.0) * 0.25) if on else 0.12
	# lamba ara sıra titrer
	if flicker_left <= 0.0 and randf() < delta * 0.12:
		flicker_left = randf_range(0.2, 0.5)
	var k := 1.0
	if flicker_left > 0.0:
		flicker_left -= delta
		k = 0.15 if randf() < 0.5 else 1.0
	lamp_light.light_energy = 5.5 * k
	lamp_fill.light_energy = 0.45 * k
	bulb_mat.emission_energy_multiplier = 6.0 * k
