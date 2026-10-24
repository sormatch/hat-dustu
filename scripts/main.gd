# Hapishane koridoru, hücreler, oyuncu, ekran, menü ve çok oyunculu bağlantı.
extends Node3D

const Sfx := preload("res://scripts/sfx.gd")
const PlayerScript := preload("res://scripts/player.gd")
const HudScript := preload("res://scripts/hud.gd")
const MenuScript := preload("res://scripts/menu.gd")
const CellScript := preload("res://scripts/cell.gd")
const BodyScript := preload("res://scripts/model_body.gd")
const NetScript := preload("res://scripts/net.gd")
const AccountScript := preload("res://scripts/account.gd")
const FriendsScript := preload("res://scripts/friends.gd")
const VoiceScript := preload("res://scripts/voice.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const CharacterScript := preload("res://scripts/character.gd")
const SettingsScript := preload("res://scripts/settings.gd")
const Catalog := preload("res://scripts/catalog.gd")

const H := 3.2
const CELL_COUNT := 8
const CELL_SPACING := 6.6
const CORRIDOR_X0 := 2.2
const CORRIDOR_X1 := 5.6
const CORRIDOR_HALF := 28
const ROUND_TIME := 90.0
const WALK_ENDS := [-25.0, 25.0]
const WALK_SPEED := 1.1
const DIAL_TIMEOUT := 30.0
const CALL_REWARD := 10

# tek başına modda arayan hayali oyuncu
const CALL_LINES := [
	[0.6, "Alo? Duyuyor musun beni?"],
	[3.5, "Bu tur ortağız. Ben paylaşacağım, söz veriyorum."],
	[8.0, "Ama Elif'e güvenme. Koridorda duydum, seni satacakmış."],
	[13.0, "Karar senin. Süre dolmadan bir daha ararım."],
]

enum Phone { IDLE, RINGING, DIALING, CALL }

var player: CharacterBody3D
var hud: CanvasLayer
var menu: CanvasLayer
var net: Node
var voice: Node
var profile: Node
var account: Node
var menu_cam: Camera3D
var _menu_t := 0.0
var env: Environment
var probe: ReflectionProbe
var mats := {}
var ring_stream: AudioStreamWAV
var door_open_stream: AudioStreamWAV
var door_close_stream: AudioStreamWAV
var glow_window: StandardMaterial3D
var click_player: AudioStreamPlayer

var cells: Array = []
var my_cell := 0
var online := false
var playing := false

var phone_state := Phone.IDLE
var phone_peer := 0  # arayan / aranan / konuşulan oyuncu
var phone_t := 0.0
var solo_ring_wait := 5.0

var remotes := {}  # id -> {root, body, label, target, yaw, seated}
var _send_t := 0.0
var _last_sent := ""

var walker: AnimatableBody3D
var walker_body: Node3D
var walker_leg := 1
var walker_wait := 0.0

var round_left := ROUND_TIME
var current_target := ""
var current_cell := -1
var test_move := Vector2.ZERO
var _auto := ""
var _drip_t := 3.0
var _drip: AudioStreamPlayer3D


func _ready() -> void:
	randomize()
	profile = ProfileScript.new()
	add_child(profile)
	_setup_input()
	_make_materials()
	_build_environment()
	_build_corridor()
	for k in CELL_COUNT:
		var c: Node3D = CellScript.new()
		c.w = self
		c.index = k
		c.number = 11 + k
		c.position = Vector3(0, 0, (k - (CELL_COUNT - 1) / 2.0) * CELL_SPACING)
		add_child(c)
		c.build()
		cells.append(c)

	player = PlayerScript.new()
	add_child(player)
	player.global_position = cells[0].spawn_world()
	player.set_physics_process(false)  # menüdeyken yürümesin

	click_player = AudioStreamPlayer.new()
	click_player.stream = Sfx.click()
	add_child(click_player)

	net = NetScript.new()
	add_child(net)
	account = AccountScript.new()
	add_child(account)
	account.start(net.server_url, profile.token)
	voice = VoiceScript.new()
	add_child(voice)
	voice.packet_ready.connect(net.send_voice)
	net.voice.connect(voice.receive)
	net.started.connect(_on_started)
	net.players_changed.connect(_on_players_changed)
	net.remote_state.connect(_on_remote_state)
	net.player_left.connect(_remove_remote)
	net.door.connect(func(cell: int, open: bool) -> void: cells[cell].set_door(open))
	net.ringing.connect(_on_ringing)
	net.ring_cell.connect(func(cell: int, on: bool) -> void: cells[cell].set_ringing(on))
	net.call_connected.connect(_on_call_connected)
	net.call_ended.connect(_on_call_ended)
	net.busy.connect(_on_busy)
	net.failed.connect(_on_net_failed)

	net.welcomed.connect(_send_profile)
	net.welcomed.connect(func() -> void: voice.start())
	net.emote.connect(_on_remote_emote)

	hud = HudScript.new()
	add_child(hud)
	hud.player = player
	hud.action_pressed.connect(_do_action)
	hud.contact_chosen.connect(_dial)
	hud.settings_pressed.connect(open_settings)
	hud.emote_chosen.connect(_do_emote)
	hud.crouch_pressed.connect(player.toggle_crouch)
	hud.ptt_changed.connect(func(down: bool) -> void: voice.ptt_down = down)
	hud.visible = false

	menu = MenuScript.new()
	menu.net = net
	menu.account = account
	menu.profile = profile
	add_child(menu)
	menu.solo.connect(_start_solo)
	menu.open_character.connect(open_character)
	menu.open_settings.connect(open_settings)
	menu.open_friends.connect(open_friends)
	_build_menu_scene()

	player.set_look(profile.look)
	profile.changed.connect(_on_profile_changed)
	_on_profile_changed()
	apply_settings()
	_handle_cmdline()


func _on_profile_changed() -> void:
	hud.refresh_gems(profile.gems)
	var em := []
	for it in Catalog.ITEMS.hareket:
		if profile.owns("hareket", it[0]):
			em.append(it[0])
	hud.set_emotes(em)


func _send_profile() -> void:
	net.send({"t": "profil", "ad": profile.player_name, "g": profile.look})


# Ayarları oyuna uygular: hassasiyet, ses, joystick, grafik kalitesi.
func apply_settings() -> void:
	var s: Dictionary = profile.settings
	player.sensitivity = float(s.hassasiyet)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(s.oyun_ses), 0.001)))
	voice.set_volume(float(s.konusma_ses))
	hud.floating_joy = bool(s.yuzen_joy)
	var high := int(s.kalite) == 1
	env.glow_enabled = high
	env.fog_density = 0.04
	probe.visible = high
	if playing:
		cells[my_cell].set_detailed(high)
	player.camera.fov = float(s.get("fov", 72.0))
	player.head_bob = bool(s.get("bob", true))
	hud.set_fps_visible(bool(s.get("fps", false)))
	voice.ptt_enabled = bool(s.get("bas_konus", false))
	ring_stream = Sfx.ring(int(s.get("zil", 0)))
	for c in cells:
		c.ring_player.stream = ring_stream


func open_settings() -> void:
	var st: CanvasLayer = SettingsScript.new()
	st.profile = profile
	st.account = account
	st.voice = voice
	st.closed.connect(func() -> void:
		apply_settings()
		_send_profile())
	st.open_character.connect(func() -> void:
		st.queue_free()
		apply_settings()
		open_character())
	st.leave_room.connect(func() -> void:
		net.leave()
		get_tree().reload_current_scene())
	add_child(st)


# Ara sıra yakında bir yerde tavandan su damlar.
func _update_drip(delta: float) -> void:
	_drip_t -= delta
	if _drip_t > 0.0:
		return
	_drip_t = randf_range(3.0, 9.0)
	if not _drip:
		_drip = AudioStreamPlayer3D.new()
		_drip.stream = Sfx.drip()
		_drip.unit_size = 3.0
		add_child(_drip)
	var a := randf() * TAU
	_drip.global_position = player.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(1.0, 4.0) + Vector3(0, H - 0.2, 0)
	_drip.pitch_scale = randf_range(0.8, 1.25)
	_drip.play()


func _do_emote(id: String) -> void:
	if phone_state == Phone.CALL or phone_state == Phone.DIALING:
		hud.show_toast("Telefondayken hareket yapamazsın.")
		return
	if player.seated:
		hud.show_toast("Önce koltuktan kalk.")
		return
	player.play_emote(id)
	if online:
		net.send({"t": "emote", "e": id})


func _on_remote_emote(id: int, e: String) -> void:
	if _auto != "":
		print("[test] hareket geldi: ", e, " oyuncu ", id)
	if not remotes.has(id) or not Catalog.EMOTE_TEXT.has(e):
		return
	var r: Dictionary = remotes[id]
	r.body.play_emote(e)
	var bubble := Label3D.new()
	bubble.text = Catalog.EMOTE_TEXT[e]
	bubble.font_size = 56
	bubble.pixel_size = 0.004
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.outline_size = 10
	bubble.modulate = Color("#F5C542")
	bubble.position.y = 2.3
	r.root.add_child(bubble)
	var tw := bubble.create_tween()
	tw.tween_property(bubble, "position:y", 2.6, 2.4)
	tw.parallel().tween_property(bubble, "modulate:a", 0.0, 2.4).set_delay(1.2)
	tw.tween_callback(bubble.queue_free)


func _setup_input() -> void:
	var keys := {"ileri": KEY_W, "geri": KEY_S, "sol": KEY_A, "sag": KEY_D, "etkilesim": KEY_E, "kos": KEY_SHIFT, "egil": KEY_C}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = keys[action]
		InputMap.action_add_event(action, ev)


# ---------- malzemeler ve yardımcılar ----------

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


func _noise_tex(c1: Color, c2: Color, freq: float, sd: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = sd
	n.frequency = freq
	n.fractal_octaves = 5
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = n
	var g := Gradient.new()
	g.set_color(0, c1)
	g.set_color(1, c2)
	tex.color_ramp = g
	return tex


func _surface(c: Color, rough: float, scale: float, sd: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _noise_tex(c.darkened(0.22), c.lightened(0.05), 0.02, sd)
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	return m


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
	var red := _flat(Color("#C4121A"), 0.22)
	red.clearcoat_enabled = true
	red.clearcoat = 0.6
	mats.red = red
	mats.dial = _flat(Color("#B9B5AC"), 0.4, 0.3)
	mats.dial_label = _flat(Color("#e8e2d2"), 0.5)
	mats.phone_dark = _flat(Color("#141414"), 0.6)
	mats.door_window = _flat(Color("#0b0c0d"), 1.0)
	mats.blanket = _surface(Color("#4a5560"), 1.0, 1.5, 10)
	mats.mattress = _flat(Color("#8a8475"), 1.0)
	glow_window = _glow(Color("#5d7fa8"), 1.4)
	ring_stream = Sfx.ring()
	door_open_stream = Sfx.door(true)
	door_close_stream = Sfx.door(false)


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


# Hazır 3D modeli yükler; tabanı (ya da top_y verilirse tepesi) o yüksekliğe, ortası pos'a gelir.
func model(id: String, pos: Vector3, yaw := 0.0, scale := 1.0, top_y := NAN, parent: Node = null) -> Node3D:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = yaw
	(parent if parent else self).add_child(holder)
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
func solid(size: Vector3, pos: Vector3, yaw := 0.0, parent: Node = null) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	sb.position = pos
	sb.rotation.y = yaw
	(parent if parent else self).add_child(sb)


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


# ---------- ortam ----------

func _build_environment() -> void:
	env = Environment.new()
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


func _build_corridor() -> void:
	var x0 := CORRIDOR_X0
	var x1 := CORRIDOR_X1
	var cx := (x0 + x1) / 2.0
	var w := x1 - x0
	var zmin := -CORRIDOR_HALF
	var zmax := CORRIDOR_HALF
	for z in range(zmin, zmax, 4):
		box(Vector3(w, 0.2, 4.0), Vector3(cx, -0.1, z + 2.0), mats.corridor_floor)
		box(Vector3(w, 0.2, 4.0), Vector3(cx, H + 0.1, z + 2.0), mats.ceiling, false)
		box(Vector3(0.2, H, 4.0), Vector3(x1 + 0.1, H / 2, z + 2.0), mats.corridor_wall)
	# hücre duvarlarının arasındaki boşlukları ve uçları kapat
	var first := -(CELL_COUNT - 1) / 2.0 * CELL_SPACING
	var last := -first
	for k in CELL_COUNT - 1:
		box(Vector3(0.2, H, 0.2), Vector3(2.1, H / 2, first + (k + 0.5) * CELL_SPACING), mats.corridor_wall)
	var end_len := zmax - (last + 3.2)
	box(Vector3(0.2, H, end_len), Vector3(2.1, H / 2, zmin + end_len / 2), mats.corridor_wall)
	box(Vector3(0.2, H, end_len), Vector3(2.1, H / 2, zmax - end_len / 2), mats.corridor_wall)
	box(Vector3(w, H, 0.2), Vector3(cx, H / 2, zmin - 0.1), mats.corridor_wall)
	box(Vector3(w, H, 0.2), Vector3(cx, H / 2, zmax + 0.1), mats.corridor_wall)

	# karşı duvarda açılmayan hücre kapıları
	var k := 0
	for zf in range(zmin + 2, zmax - 1, 3):
		_fake_door(x1, float(zf) + 0.5, -1.0, 40 + k, k % 3 == 1)
		k += 1

	# floresan lambalar
	for z in range(zmin + 3, zmax, 6):
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

	probe = ReflectionProbe.new()
	probe.size = Vector3(w, H, zmax - zmin)
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
	var l := Label3D.new()
	l.text = str(number)
	l.font_size = 72
	l.pixel_size = 0.004
	l.modulate = Color(0.85, 0.85, 0.82)
	l.position = Vector3(x + side * 0.11, 2.6, z)
	l.rotation.y = PI / 2 * side
	add_child(l)


# ---------- ana menü arka planı ----------

# Menünün arkasında: sisli koridorda yavaşça ilerleyen kamera ve yerden yükselen buhar.
func _build_menu_scene() -> void:
	menu_cam = Camera3D.new()
	menu_cam.fov = 62.0
	add_child(menu_cam)
	menu_cam.position = Vector3(3.9, 1.75, 20.0)
	menu_cam.rotation = Vector3(deg_to_rad(-4), 0, 0)
	menu_cam.current = true
	var puff := GradientTexture2D.new()
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(0.8, 0.82, 0.86, 0.35))
	g.set_color(1, Color(0.8, 0.82, 0.86, 0.0))
	puff.gradient = g
	var m := StandardMaterial3D.new()
	m.albedo_texture = puff
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 1.6)
	q.material = m
	for z in [14.0, 6.0, -2.0]:
		var steam := CPUParticles3D.new()
		steam.mesh = q
		steam.amount = 14
		steam.lifetime = 6.0
		steam.preprocess = 6.0
		steam.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		steam.emission_box_extents = Vector3(1.2, 0.05, 0.6)
		steam.direction = Vector3(0, 1, 0)
		steam.spread = 25.0
		steam.initial_velocity_min = 0.15
		steam.initial_velocity_max = 0.35
		steam.gravity = Vector3.ZERO
		steam.scale_amount_min = 0.8
		steam.scale_amount_max = 1.8
		var fade := Gradient.new()
		fade.set_color(0, Color(1, 1, 1, 0))
		fade.add_point(0.3, Color(1, 1, 1, 1))
		fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
		steam.color_ramp = fade
		steam.position = Vector3(3.9 + (0.6 if z < 10.0 else -0.5), 0.05, z)
		add_child(steam)


func open_friends() -> void:
	var f: CanvasLayer = FriendsScript.new()
	f.account = account
	f.profile = profile
	f.net = net
	add_child(f)


# ---------- karakter ve mağaza ----------

func open_character() -> CanvasLayer:
	var ch: CanvasLayer = CharacterScript.new()
	ch.profile = profile
	ch.closed.connect(_on_character_closed)
	add_child(ch)
	return ch


func _on_character_closed(saved: bool) -> void:
	if not saved:
		return
	player.set_look(profile.look)
	menu.refresh_profile()
	hud.refresh_gems(profile.gems)
	if online:
		net.send({"t": "profil", "ad": profile.player_name, "g": profile.look})


# ---------- oyunun başlaması ----------

func _start_solo() -> void:
	online = false
	_begin(0)
	hud.set_players([{"id": 1, "name": "Sen", "cell": 0}, {"id": 2, "name": "Deniz", "cell": 1}], 1)


func _on_started() -> void:
	voice.stop()
	online = true
	_begin(net.my_cell)
	_on_players_changed()


func _begin(cell: int) -> void:
	my_cell = cell
	player.camera.current = true
	if menu_cam:
		menu_cam.queue_free()
		menu_cam = null
	var used := maxi(cell + 1, 2)
	if online:
		for p in net.players:
			used = maxi(used, int(p.cell) + 1)
	for k in range(used, CELL_COUNT):
		cells[k].lock_empty()
	cells[cell].set_detailed(true)
	player.global_position = cells[cell].spawn_world()
	player.rotation.y = 0.0
	menu.visible = false
	hud.visible = true
	playing = true
	player.set_physics_process(true)
	hud.show_toast("Hücre %d · telefonun sağ duvarda" % cells[cell].number)


func _on_net_failed(msg: String) -> void:
	if playing and online:
		_end_call_local()
		hud.show_toast(msg)
	else:
		menu.show_error(msg)


# ---------- diğer oyuncular ----------

func _on_players_changed() -> void:
	if not playing:
		return
	hud.set_players(net.players, net.my_id)
	var ids := {}
	for p in net.players:
		var id := int(p.id)
		ids[id] = true
		if remotes.has(id):
			_apply_remote_profile(id)
	for id in remotes.keys():
		if not ids.has(id):
			_remove_remote(id)


func _player_entry(id: int) -> Dictionary:
	for p in net.players:
		if int(p.id) == id:
			return p
	return {}


# Diğer oyuncunun adı ve görünüşü değiştiyse karakterini yeniden giydirir.
func _apply_remote_profile(id: int) -> void:
	var r: Dictionary = remotes[id]
	var p := _player_entry(id)
	var look_json := JSON.stringify(p.get("g", {}))
	if look_json != r.get("look", ""):
		r.look = look_json
		r.body.set_look(p.get("g", {}))
	r.label.text = str(p.get("name", "?"))


func _on_remote_state(id: int, d: Dictionary) -> void:
	if not playing or id == net.my_id:
		return
	if not remotes.has(id):
		# diğer oyuncular katı: içinden geçilmez
		var root := AnimatableBody3D.new()
		root.sync_to_physics = false
		var rc := CollisionShape3D.new()
		var rs := CapsuleShape3D.new()
		rs.radius = 0.3
		rs.height = 1.7
		rc.shape = rs
		rc.position.y = 0.85
		root.add_child(rc)
		add_child(root)
		var body: Node3D = BodyScript.new()
		root.add_child(body)
		var label := Label3D.new()
		label.text = net.player_name(id)
		label.font_size = 48
		label.pixel_size = 0.004
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position.y = 2.05
		label.outline_size = 8
		root.add_child(label)
		var p0: Array = d.p
		root.position = Vector3(p0[0], 0, p0[1])
		remotes[id] = {"root": root, "body": body, "label": label, "target": root.position, "yaw": 0.0, "seated": false}
		_apply_remote_profile(id)
	var r: Dictionary = remotes[id]
	var p: Array = d.p
	r.target = Vector3(float(p[0]), 0, float(p[1]))
	r.yaw = float(d.y)
	r.seated = bool(d.o)
	r.body.crouched = bool(d.get("k", false))
	r.label.text = net.player_name(id) + ("  (telefonda)" if bool(d.get("c", false)) else "")


func _remove_remote(id: int) -> void:
	if remotes.has(id):
		remotes[id].root.queue_free()
		remotes.erase(id)


func _update_remotes(delta: float) -> void:
	for id in remotes:
		var r: Dictionary = remotes[id]
		var root: Node3D = r.root
		var before := root.position
		root.position = root.position.lerp(r.target, minf(1.0, delta * 10.0))
		root.rotation.y = lerp_angle(root.rotation.y, r.yaw, minf(1.0, delta * 10.0))
		var speed := Vector2(root.position.x - before.x, root.position.z - before.z).length() / maxf(delta, 0.001)
		r.body.walk = clampf(speed / 2.4, 0.0, 1.0)
		r.body.seated = r.seated


func _send_state(delta: float) -> void:
	_send_t += delta
	if _send_t < 0.12:
		return
	_send_t = 0.0
	var gp := player.global_position
	var d := {"t": "konum", "p": [snappedf(gp.x, 0.01), snappedf(gp.z, 0.01)], "y": snappedf(player.rotation.y, 0.01),
		"o": player.seated, "c": phone_state == Phone.CALL, "k": player.crouched}
	var s := JSON.stringify(d)
	if s != _last_sent:
		_last_sent = s
		net.send(d)


# ---------- oyun döngüsü ----------

func _process(delta: float) -> void:
	player.move_input = test_move if test_move != Vector2.ZERO else hud.move
	player.sprint = hud.sprint
	_update_walker(delta)
	if not playing:
		if menu_cam:
			_menu_t += delta
			menu_cam.position.z = 20.0 - fmod(_menu_t * 0.35, 14.0)
			menu_cam.rotation.y = sin(_menu_t * 0.15) * 0.08
		return
	profile.tick_play(delta)
	_update_drip(delta)
	_update_phone(delta)
	_update_target()
	_update_remotes(delta)
	if online:
		_send_state(delta)
	round_left -= delta
	if round_left <= 0.0:
		round_left = ROUND_TIME
	hud.set_timer(round_left)


func _unhandled_input(event: InputEvent) -> void:
	if playing and event.is_action_pressed("etkilesim"):
		_do_action()
	if playing and event.is_action_pressed("egil"):
		player.toggle_crouch()


func _nearest_cell() -> int:
	var z := player.global_position.z
	return clampi(roundi(z / CELL_SPACING + (CELL_COUNT - 1) / 2.0), 0, CELL_COUNT - 1)


func _update_target() -> void:
	var cam: Camera3D = player.camera
	var fwd := -cam.global_transform.basis.z
	var best := ""
	var best_score := -INF
	var ci := _nearest_cell()
	var c: Node3D = cells[ci]
	var mine: Node3D = cells[my_cell]
	var targets := [["chair", c.chair_world() + Vector3(0, 0.5, 0), 2.0], ["door", c.door_world(), 2.2]]
	if phone_state == Phone.RINGING or phone_state == Phone.IDLE:
		targets.append(["phone", mine.phone_world(), 2.4])
	for t in targets:
		var to: Vector3 = t[1] - cam.global_position
		var d := to.length()
		if d > t[2]:
			continue
		var facing := fwd.dot(to.normalized())
		if facing < 0.5 and not (t[0] == "phone" and player.seated):
			continue
		var score := facing - d * 0.15 + (2.0 if t[0] == "phone" and phone_state == Phone.RINGING else 0.0)
		if score > best_score:
			best_score = score
			best = t[0]
	if player.seated and best != "phone":
		best = "chair"
	if phone_state == Phone.CALL or phone_state == Phone.DIALING:
		best = "hangup"
	current_target = best
	current_cell = ci
	match best:
		"chair":
			hud.set_action("Kalk" if player.seated else "Otur")
		"door":
			hud.set_action("Kapıyı kapat" if c.door_open else "Kapıyı aç")
		"phone":
			if phone_state == Phone.RINGING:
				hud.set_action("Cevapla", true)
			else:
				hud.set_action("Ara", true)
		"hangup":
			hud.set_action("Kapat", true)
		_:
			hud.set_action("")


func _do_action() -> void:
	if player.busy or not playing:
		return
	var c: Node3D = cells[current_cell] if current_cell >= 0 else cells[my_cell]
	match current_target:
		"chair":
			if player.seated:
				player.stand(c.to_global(c.CHAIR_POS + Vector3(sin(c.CHAIR_YAW), 0, cos(c.CHAIR_YAW)) * 0.95))
			else:
				player.sit(c.chair_world(), PI + c.CHAIR_YAW)
		"door":
			if c.door_busy or c.locked:
				return
			c.set_door(not c.door_open)
			player.push()
			if online:
				net.send({"t": "kapi", "cell": c.index, "open": c.door_open})
		"phone":
			if phone_state == Phone.RINGING:
				_answer()
			else:
				_open_contacts()
		"hangup":
			_hang_up()


# ---------- telefon ----------

func _open_contacts() -> void:
	var list := []
	if online:
		for p in net.players:
			if int(p.id) != net.my_id:
				list.append({"id": int(p.id), "name": "%s  (hücre %d)" % [p.name, 11 + int(p.cell)]})
	else:
		list.append({"id": 2, "name": "Deniz  (hücre 12)"})
	if list.is_empty():
		hud.show_toast("Arayacak kimse yok. Arkadaşını odaya davet et!")
		return
	hud.show_contacts(list)


func _dial(id: int) -> void:
	if phone_state != Phone.IDLE:
		return
	phone_state = Phone.DIALING
	phone_peer = id
	phone_t = 0.0
	click_player.play()
	cells[my_cell].set_handset_lifted(true)
	player.set_call(true)
	hud.show_call(_peer_name(), "Çalıyor…")
	if online:
		net.send({"t": "ara", "to": id})


func _on_ringing(from_id: int) -> void:
	if bool(profile.settings.get("titresim", true)):
		Input.vibrate_handheld(500)
	phone_state = Phone.RINGING
	phone_peer = from_id
	phone_t = 0.0
	hud.ring_label.text = "Telefon çalıyor: " + net.player_name(from_id)
	hud.ring_label.visible = true


func _answer() -> void:
	click_player.play()
	cells[my_cell].set_ringing(false)
	cells[my_cell].set_handset_lifted(true)
	player.set_call(true)
	hud.ring_label.visible = false
	if online:
		hud.show_call(_peer_name(), "Bağlanıyor…")
		net.send({"t": "cevap"})
	else:
		phone_state = Phone.CALL
		phone_t = 0.0


func _on_call_connected(with_id: int) -> void:
	hud.set_ptt(voice.ptt_enabled)
	phone_state = Phone.CALL
	phone_peer = with_id
	phone_t = 0.0
	voice.start()


func _on_call_ended() -> void:
	if phone_state == Phone.DIALING and phone_t < DIAL_TIMEOUT:
		hud.show_toast(_peer_name() + " açmadı.")
	_end_call_local()


func _on_busy() -> void:
	hud.show_toast(_peer_name() + " şu an meşgul.")
	_end_call_local()


func _hang_up() -> void:
	if online:
		net.send({"t": "kapat"})
	_end_call_local()


func _end_call_local() -> void:
	if phone_state == Phone.IDLE:
		return
	if phone_state != Phone.RINGING:
		click_player.play()
	# 10 saniyeden uzun gerçek konuşma elmas kazandırır
	if phone_state == Phone.CALL and online and phone_t > 10.0:
		profile.add_gems(CALL_REWARD)
		hud.show_toast("Konuşma bitti: +%d elmas" % CALL_REWARD)
	phone_state = Phone.IDLE
	solo_ring_wait = 20.0
	voice.stop()
	hud.set_ptt(false)
	cells[my_cell].set_ringing(false)
	cells[my_cell].set_handset_lifted(false)
	player.set_call(false)
	hud.hide_call()
	hud.ring_label.visible = false


func _peer_name() -> String:
	return net.player_name(phone_peer) if online else "Deniz"


func _update_phone(delta: float) -> void:
	phone_t += delta
	match phone_state:
		Phone.IDLE:
			if not online:
				solo_ring_wait -= delta
				if solo_ring_wait <= 0.0:
					phone_state = Phone.RINGING
					phone_peer = 2
					phone_t = 0.0
					cells[my_cell].set_ringing(true)
					hud.ring_label.text = "Telefon çalıyor: Deniz"
					hud.ring_label.visible = true
		Phone.RINGING:
			hud.ring_label.modulate.a = 0.6 + 0.4 * sin(phone_t * 6.0)
			if not online and phone_t > 24.0:
				_end_call_local()
		Phone.DIALING:
			if not online and phone_t > 2.5:
				phone_state = Phone.CALL
				phone_t = 0.0
			elif online and phone_t > DIAL_TIMEOUT:
				hud.show_toast(_peer_name() + " açmadı.")
				_hang_up()
		Phone.CALL:
			if online:
				var s := int(phone_t)
				hud.show_call(_peer_name(), "Konuşuyorsunuz  %d:%02d" % [s / 60, s % 60])
			else:
				var line := ""
				for l in CALL_LINES:
					if phone_t >= l[0]:
						line = l[1]
				hud.show_call("Deniz", line if line != "" else "…")
				if phone_t > 22.0:
					_hang_up()


# Mahkum koridorun iki ucu arasında yürür, uçlarda biraz bekleyip geri döner.
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
	for id in remotes:
		blocked = blocked or ahead.distance_to(remotes[id].root.position) < 0.75
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


# ---------- testler ----------
# Ekran görüntüsü:  Godot --path . -- shot=dosya.png pose=cell|corridor|icon|menu
# İki oyunculu test: -- server=ws://127.0.0.1:8787 auto=host|join code=TEST tone=1

func _handle_cmdline() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	if args.has("auto"):
		_run_auto(args)
		return
	if not args.has("shot"):
		return
	var pose: String = args.get("pose", "cell")
	if pose == "arkadas":
		open_friends()
	elif pose == "karakter":
		var ch: CanvasLayer = open_character()
		await get_tree().process_frame
		ch._cat = args.get("cat", "sac")
		ch._refresh()
		if args.has("item"):
			ch._pick(args.item)
	elif pose != "menu":
		_start_solo()
		if args.has("pitch"):
			player.head.rotation.x = deg_to_rad(float(args.pitch))
	match pose:
		"corridor":
			cells[0].set_door(true, true)
			player.global_position = Vector3(3.9, 0, cells[0].position.z + 3.0)
		"icon":
			hud.visible = false
			solo_ring_wait = 0.0
			player.global_position = cells[0].to_global(Vector3(0.75, 0, -2.25))
			player.rotation.y = -PI / 2
			player.head.rotation.x = deg_to_rad(-10)
			player.camera.fov = 42.0
			for a in player.arms:
				a.visible = false
		"ayarlar":
			open_settings()
		"emote":
			await get_tree().create_timer(0.3).timeout
			hud.emote_panel.visible = true
			if args.has("e"):
				hud.emote_panel.visible = false
				player.global_position = cells[0].to_global(Vector3(0.6, 0, 1.2))
				_do_emote(args.e)
		"contacts":
			player.global_position = cells[0].to_global(Vector3(1.05, 0, -2.25))
			player.rotation.y = -PI / 2
			solo_ring_wait = 100.0
			await get_tree().create_timer(0.5).timeout
			_do_action()
	await get_tree().create_timer(float(args.get("wait", "2.5"))).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args["shot"])
	get_tree().quit()


func _run_auto(args: Dictionary) -> void:
	_auto = args.auto
	var code: String = args.get("code", "TEST")
	print("[test] ", _auto, " başlıyor")
	net.failed.connect(func(m: String) -> void:
		print("[test] hata: ", m)
		get_tree().quit())
	if _auto == "host":
		net.join(code, "Kurucu", true)
		await net.welcomed
		print("[test] oda kuruldu, kod ", net.room_code, " hücre ", net.my_cell)
		while net.players.size() < 2:
			await get_tree().process_frame
		print("[test] oyuncular: ", net.players)
		net.send({"t": "basla"})
		await net.ringing
		print("[test] telefon çalıyor, arayan ", net.player_name(phone_peer))
		await get_tree().create_timer(1.0).timeout
		_answer()
	else:
		await get_tree().create_timer(2.0).timeout
		net.join(code, "Arkadaş", false)
		await net.welcomed
		print("[test] odaya katıldı, hücre ", net.my_cell)
		await net.started
		await get_tree().create_timer(1.5).timeout
		print("[test] uzaktaki oyuncular: ", remotes.keys())
		_do_emote("selam")
		await get_tree().create_timer(3.0).timeout
		print("[test] karşıdakinin görünüşü: ", _player_entry(_other_id()).get("g", {}))
		_dial(_other_id())
	await net.call_connected
	print("[test] arama bağlandı")
	await get_tree().create_timer(4.0).timeout
	print("[test] ses: yollanan %d, gelen %d paket" % [voice.sent_packets, voice.received_packets])
	if args.has("shot"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args.shot)
	if _auto == "join":
		_hang_up()
	else:
		await net.call_ended
		print("[test] karşı taraf kapattı")
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()


func _other_id() -> int:
	for p in net.players:
		if int(p.id) != net.my_id:
			return int(p.id)
	return 0
