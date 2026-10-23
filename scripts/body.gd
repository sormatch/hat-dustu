# Turuncu tulumlu mahkum gövdesi: bacaklar, gövde, (isteğe bağlı) kafa ve kollar.
# Yürürken bacaklar ve kollar sallanır, oturunca bacaklar kırılır. Yüzü -z yönüne bakar.
extends Node3D

var show_head := true
var show_arms := true
var show_torso := true
var suit := Color("#B4501A")

var walk := 0.0      # 0 = duruyor, 1 = tam hızda yürüyor
var seated := false
var _phase := 0.0
var _sit := 0.0      # 0 ayakta, 1 oturuyor (yumuşak geçiş)
var _hip_root: Node3D
var _upper: Node3D
var _hips: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _shoulders: Array[Node3D] = []
var _elbows: Array[Node3D] = []


func _mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _capsule(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 4
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _ready() -> void:
	var cloth := _mat(suit)
	var dark := _mat(Color("#1b1b1d"), 0.6)
	var skin := _mat(Color("#b07d62"), 0.7)

	_hip_root = Node3D.new()
	_hip_root.position.y = 0.92
	add_child(_hip_root)
	if show_torso:
		_capsule(_hip_root, 0.17, 0.4, Vector3(0, 0.05, 0.04), cloth).scale = Vector3(1.15, 1, 0.8)
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
	add_child(_upper)
	if show_torso:
		_capsule(_upper, 0.19, 0.62, Vector3(0, 0.3, 0.08), cloth).scale = Vector3(1.2, 1, 0.75)
	if show_head:
		var head := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.11
		s.height = 0.25
		head.mesh = s
		head.material_override = skin
		head.position = Vector3(0, 0.74, 0.04)
		_upper.add_child(head)
		_capsule(_upper, 0.05, 0.12, Vector3(0, 0.62, 0.05), skin)
	if show_arms:
		for side in [-1.0, 1.0]:
			var sh := Node3D.new()
			sh.position = Vector3(side * 0.24, 0.55, 0.06)
			_upper.add_child(sh)
			_capsule(sh, 0.058, 0.32, Vector3(0, -0.14, 0), cloth)
			var el := Node3D.new()
			el.position.y = -0.29
			sh.add_child(el)
			_capsule(el, 0.05, 0.28, Vector3(0, -0.12, 0), cloth)
			_box(el, Vector3(0.07, 0.11, 0.04), Vector3(0, -0.3, 0), skin)
			_shoulders.append(sh)
			_elbows.append(el)


func _process(delta: float) -> void:
	_sit = move_toward(_sit, 1.0 if seated else 0.0, delta * 2.5)
	if walk > 0.05:
		_phase += delta * 7.5 * clampf(walk, 0.4, 1.2)
	else:
		_phase = lerpf(_phase, roundf(_phase / PI) * PI, delta * 6.0)
	var a := sin(_phase) * 0.55 * clampf(walk, 0.0, 1.0)
	var b := absf(sin(_phase)) * 0.25 * clampf(walk, 0.0, 1.0)
	# oturunca kalça 0.92'den 0.5'e iner, uyluk öne döner, diz kırılır
	_hip_root.position.y = lerpf(0.92, 0.5, _sit) + b * 0.05
	_upper.position.y = lerpf(0.95, 0.53, _sit) + b * 0.05
	for i in 2:
		var sgn := 1.0 if i == 0 else -1.0
		_hips[i].rotation.x = lerpf(a * sgn, deg_to_rad(88), _sit)
		var knee_walk := maxf(0.0, -sin(_phase + (0.0 if i == 0 else PI))) * 0.7 * clampf(walk, 0.0, 1.0)
		_knees[i].rotation.x = lerpf(-knee_walk, -deg_to_rad(85), _sit)
	for i in _shoulders.size():
		var sgn := -1.0 if i == 0 else 1.0
		_shoulders[i].rotation.x = lerpf(a * sgn * 0.8, deg_to_rad(35), _sit)
		_elbows[i].rotation.x = lerpf(0.25 + b, deg_to_rad(45), _sit)
