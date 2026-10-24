# Birinci şahıs oyuncu: yürür, etrafa bakar, koltuğa oturup kalkar.
# Aşağı bakınca kendi gövdesini ve bacaklarını, ekranın altında da ellerini görür.
extends CharacterBody3D

const BodyScript := preload("res://scripts/body.gd")
const ModelScript := preload("res://scripts/model_body.gd")
const Sfx := preload("res://scripts/sfx.gd")

const SPEED := 2.4
const EYE_STAND := 1.6
const EYE_SEAT := 1.05
const RUN_MULT := 1.9
const EYE_CROUCH := 1.05
const ARM_BASE := [Vector3(-0.23, -0.34, -0.24), Vector3(0.23, -0.34, -0.24)]

var head: Node3D
var camera: Camera3D
var col: CollisionShape3D
var body: Node3D

var arms: Array[Node3D] = []  # 0 = sol, 1 = sağ
var held_handset: Node3D
var move_input := Vector2.ZERO  # ekrandaki joystick'ten gelir
var seated := false
var busy := false
var on_call := false
var bob_t := 0.0
var _arm_tween: Tween
var emote_active := false
var sensitivity := 1.0  # ayarlardan
var sprint := false
var crouched := false
var head_bob := true  # ayarlardan
signal emote_stopped
var _eye := 1.6
var _steps: AudioStreamPlayer
var _step_t := 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	col = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	col.shape = cap
	col.position.y = 0.85
	add_child(col)
	head = Node3D.new()
	head.position = Vector3(0, EYE_STAND, -0.16)
	add_child(head)
	camera = Camera3D.new()
	camera.fov = 72.0
	camera.near = 0.03
	head.add_child(camera)
	camera.current = true

	# kendi gövden gerçek karakter modeli: aşağı bakınca gerçek bacak ve eller, kafa gizli
	body = ModelScript.new()
	body.hide_head = true
	body.position.z = 0.03
	add_child(body)
	_build_arms()
	for a in arms:
		a.visible = false
	_steps = AudioStreamPlayer.new()
	# gerçek beton ayak sesi kayıtları, her adımda rastgele biri
	var steps := AudioStreamRandomizer.new()
	for i in 5:
		steps.add_stream(-1, load("res://assets/ses/adim_%d.ogg" % i))
	steps.random_pitch = 1.08
	_steps.stream = steps
	_steps.volume_db = -2.0
	add_child(_steps)


# Eğil / kalk: göz hizası ve çarpışma boyu küçülür, karakter çömelir.
func toggle_crouch() -> void:
	if seated or busy:
		return
	crouched = not crouched
	body.crouched = crouched
	_eye = EYE_CROUCH if crouched else EYE_STAND
	var cap: CapsuleShape3D = col.shape
	cap.height = 1.15 if crouched else 1.7
	col.position.y = cap.height / 2.0


func stop_emote() -> void:
	emote_active = false
	body.stop_emote()
	emote_stopped.emit()


func set_look(look: Dictionary) -> void:
	body.set_look(look)


# Hareket (emote): kamera yerinde kalır; kendi ellerini hareket yaparken görürsün, diğerleri tüm hareketi görür.
func play_emote(id: String) -> void:
	if emote_active or seated or busy or on_call:
		return
	emote_active = true
	body.play_emote(id)
	var tw := create_tween()
	tw.tween_interval(4.0 if id == "dans" else 2.6)
	tw.tween_callback(func() -> void: emote_active = false)


func _mat(c: Color, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, rot: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


# Kameraya bağlı iki kol: turuncu kol, ten rengi el ve parmaklar.
func _build_arms() -> void:
	var cloth := _mat(Color("#B4501A"), 0.9)
	var skin := _mat(Color("#b07d62"), 0.65)
	var sleeve := CapsuleMesh.new()
	sleeve.radius = 0.052
	sleeve.height = 0.42
	var cuff := CylinderMesh.new()
	cuff.top_radius = 0.047
	cuff.bottom_radius = 0.047
	cuff.height = 0.05
	var palm := BoxMesh.new()
	palm.size = Vector3(0.082, 0.032, 0.095)
	var finger := CapsuleMesh.new()
	finger.radius = 0.0105
	finger.height = 0.075
	var thumb := CapsuleMesh.new()
	thumb.radius = 0.012
	thumb.height = 0.065
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var arm := Node3D.new()
		arm.position = ARM_BASE[i]
		arm.rotation.y = side * 0.18
		camera.add_child(arm)
		_part(arm, sleeve, Vector3(0, -0.02, 0.06), Vector3(deg_to_rad(-78), 0, 0), cloth)
		_part(arm, cuff, Vector3(0, 0.025, -0.135), Vector3(deg_to_rad(-78), 0, 0), skin)
		_part(arm, palm, Vector3(0, 0.035, -0.2), Vector3(deg_to_rad(8), 0, 0), skin)
		for f in 4:
			var fx := (f - 1.5) * 0.02
			_part(arm, finger, Vector3(fx, 0.012, -0.258), Vector3(deg_to_rad(-118), 0, 0), skin)
		_part(arm, thumb, Vector3(-side * 0.048, 0.04, -0.2), Vector3(deg_to_rad(-70), 0, side * 0.6), skin)
		arms.append(arm)

	# sağ elde tutulan ahize (sadece konuşurken görünür)
	var red := _mat(Color("#C4121A"), 0.25)
	held_handset = Node3D.new()
	held_handset.position = Vector3(0, 0.07, -0.22)
	held_handset.rotation = Vector3(-PI / 2, 0, 0)
	arms[1].add_child(held_handset)
	var grip := CapsuleMesh.new()
	grip.radius = 0.026
	grip.height = 0.27
	_part(held_handset, grip, Vector3.ZERO, Vector3.ZERO, red)
	var cup := CylinderMesh.new()
	cup.top_radius = 0.045
	cup.bottom_radius = 0.035
	cup.height = 0.05
	_part(held_handset, cup, Vector3(0, 0.12, 0.02), Vector3(deg_to_rad(90), 0, 0), red)
	_part(held_handset, cup, Vector3(0, -0.12, 0.02), Vector3(deg_to_rad(90), 0, 0), red)
	held_handset.visible = false


func look(delta_px: Vector2, sens := 0.005) -> void:
	if busy or emote_active:
		return
	sens *= sensitivity
	rotate_y(-delta_px.x * sens)
	head.rotation.x = clampf(head.rotation.x - delta_px.y * sens, deg_to_rad(-80.0), deg_to_rad(75.0))


func _physics_process(delta: float) -> void:
	body.seated = seated
	if emote_active and (move_input.length() > 0.15 or Input.get_vector("sol", "sag", "ileri", "geri").length() > 0.1):
		stop_emote()
	if seated or busy or emote_active:
		velocity = Vector3.ZERO
		body.walk = 0.0
		_sway(delta, 0.0)
		return
	var dir2 := move_input
	var keys := Input.get_vector("sol", "sag", "ileri", "geri")
	if keys.length() > 0.0:
		dir2 = keys
	# KOŞ halkası (ya da Shift) hızlı koşturur, eğilince yavaşlar
	var run := RUN_MULT if (sprint or Input.is_action_pressed("kos")) and not crouched else 1.0
	if crouched:
		run = 0.5
	var dir := transform.basis * Vector3(dir2.x, 0.0, dir2.y)
	velocity.x = dir.x * SPEED * run
	velocity.z = dir.z * SPEED * run
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
	move_and_slide()
	var speed := Vector2(velocity.x, velocity.z).length() / SPEED
	body.walk = speed
	# yürürken hafif kafa sallanması
	if speed > 0.1:
		# ayak sesi: koşarken daha sık
		_step_t -= delta * speed
		if _step_t <= 0.0 and is_on_floor():
			_step_t = 0.52
			_steps.play()
		bob_t += delta * 9.0
		head.position.y = _eye + sin(bob_t) * (0.025 if head_bob else 0.0)
	else:
		head.position.y = lerpf(head.position.y, _eye, delta * 8.0)
	_sway(delta, speed)


# Eller yürürken hafifçe sallanır; konuşurken sağ el kulakta kalır.
func _sway(delta: float, speed: float) -> void:
	if _arm_tween and _arm_tween.is_running():
		return
	var low := Vector3(0, -0.07, 0.04) if seated else Vector3.ZERO
	for i in 2:
		if i == 1 and on_call:
			continue
		var s := 1.0 if i == 0 else -1.0
		var target: Vector3 = ARM_BASE[i] + low + Vector3(sin(bob_t * 0.5) * 0.012 * s, absf(cos(bob_t * 0.5)) * 0.014, 0) * speed
		arms[i].position = arms[i].position.lerp(target, minf(1.0, delta * 10.0))


func set_call(active: bool) -> void:
	on_call = active
	var arm := arms[1]
	if _arm_tween:
		_arm_tween.kill()
	_arm_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# ahize kulakta: birinci şahısta görünmez, sağ el ekranın dışına (kulağa) kalkar
	if active:
		held_handset.visible = true
		_arm_tween.tween_property(arm, "position", Vector3(0.34, -0.05, -0.12), 0.35)
		_arm_tween.tween_property(arm, "rotation", Vector3(deg_to_rad(75), 0.6, 0), 0.35)
		_arm_tween.chain().tween_callback(func() -> void: arm.visible = false)
	else:
		arm.visible = false
		_arm_tween.tween_property(arm, "position", ARM_BASE[1], 0.4)
		_arm_tween.tween_property(arm, "rotation", Vector3(0, 0.18, 0), 0.4)
		_arm_tween.chain().tween_callback(func() -> void: held_handset.visible = false)


# Kapıyı iterken sağ el ileri uzanır.
func push() -> void:
	if on_call:
		return
	var arm := arms[1]
	if _arm_tween:
		_arm_tween.kill()
	_arm_tween = create_tween().set_trans(Tween.TRANS_SINE)
	_arm_tween.tween_property(arm, "position", ARM_BASE[1] + Vector3(-0.04, 0.08, -0.16), 0.22)
	_arm_tween.tween_property(arm, "position", ARM_BASE[1], 0.35)


func _turn_to(yaw: float) -> float:
	return rotation.y + wrapf(yaw - rotation.y, -PI, PI)


func sit(seat: Vector3, yaw: float) -> void:
	seated = true
	busy = true
	col.disabled = true
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "global_position", seat, 0.7)
	tw.tween_property(self, "rotation:y", _turn_to(yaw), 0.7)
	tw.tween_property(head, "position:y", EYE_SEAT, 0.7)
	tw.tween_property(head, "rotation:x", deg_to_rad(-4.0), 0.7)
	tw.chain().tween_callback(func() -> void: busy = false)


func stand(to: Vector3) -> void:
	busy = true
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "global_position", to, 0.6)
	tw.tween_property(head, "position:y", EYE_STAND, 0.6)
	tw.chain().tween_callback(func() -> void:
		col.disabled = false
		seated = false
		busy = false)
