# Şapkalar: kafanın ölçülen şekline (Hair._head_min/_head_max) oturan, koddan kurulan modeller.
# Saç bırakılırsa (uzun saçlar) şapka saçın kutusunu da kapsayacak kadar büyür.
extends RefCounted

const Hair := preload("res://scripts/hair.gd")
# Bu saçlar şapkanın altında kalır (gizlenir); diğerleri şapkayla birlikte görünür.
const HIDDEN_HAIR := ["kisa", "asker", "dalgali", "yandan", "mohawk", "kivircik", "kel"]


static func _mat(c: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func _add(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func _dome(parent: Node3D, mat: Material, at: Vector3, rx: float, h: float, rz: float) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 1.0  # yarıçap = yükseklik: düzgün yarım küre, y 0..1
	s.is_hemisphere = true
	s.radial_segments = 32
	s.rings = 12
	return _add(parent, s, mat, at, Vector3.ZERO, Vector3(rx, h, rz))


static func _ring(parent: Node3D, mat: Material, at: Vector3, rx: float, rz: float, height: float, top_k := 1.0) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = top_k
	c.bottom_radius = 1.0
	c.height = 1.0
	c.radial_segments = 32
	return _add(parent, c, mat, at, Vector3.ZERO, Vector3(rx, height, rz))


# style: şapka kimliği; hair_box: bırakılan saçın kutusu (kafa çerçevesinde) ya da boş.
static func build(parent: Node3D, style: String, hair_box: AABB) -> void:
	if style == "yok" or style == "":
		return
	var hmin: Vector3 = Hair._head_min
	var hmax: Vector3 = Hair._head_max
	var root := Node3D.new()
	root.rotation.x = 0.2  # arkası biraz aşağıda, alnı açık
	parent.add_child(root)
	var cx := (hmin.x + hmax.x) * 0.5
	var cz := (hmin.z + hmax.z) * 0.5 + 0.006
	var rx := (hmax.x - hmin.x) * 0.5 * 1.07
	var rz := (hmax.z - hmin.z) * 0.5 * 1.07
	var top := hmax.y + 0.012
	if hair_box.size != Vector3.ZERO:
		rx = maxf(rx, hair_box.size.x * 0.5 * 1.04)
		rz = maxf(rz, hair_box.size.z * 0.5 * 1.02)
		top = maxf(top, hair_box.end.y + 0.008)
	var rim := lerpf(hmin.y, hmax.y, 0.42)
	var h := top - rim
	var at := Vector3(cx, rim, cz)
	match style:
		"bere", "ponpon":
			var knit := _mat(Color("#1d1f24") if style == "bere" else Color("#a8262a"), 0.98)
			_dome(root, knit, at, rx * 1.02, h * 1.12, rz * 1.02)
			_ring(root, _mat(knit.albedo_color.darkened(0.15), 1.0), at + Vector3(0, 0.012, 0), rx * 1.07, rz * 1.07, 0.04)
			if style == "ponpon":
				var p := SphereMesh.new()
				p.radius = 0.035
				p.height = 0.07
				_add(root, p, _mat(Color("#f2efe6"), 1.0), Vector3(cx, top + h * 0.12 + 0.02, cz))
		"kep", "ters_kep":
			var cloth := _mat(Color("#1f3e78"), 0.9)
			_dome(root, cloth, at, rx * 1.01, h * 0.98, rz * 1.01)
			var visor := CylinderMesh.new()
			visor.top_radius = 1.0
			visor.bottom_radius = 1.0
			visor.height = 1.0
			visor.radial_segments = 24
			var dir := -1.0 if style == "kep" else 1.0
			_add(root, visor, _mat(Color("#14294f"), 0.85), Vector3(cx, rim + 0.008, cz + dir * rz * 0.92), Vector3(dir * -0.12, 0, 0), Vector3(rx * 0.8, 0.008, rz * 0.62))
			var b := SphereMesh.new()
			b.radius = 0.012
			b.height = 0.012
			_add(root, b, cloth, Vector3(cx, top - 0.002, cz))
		"bandana":
			var red := _mat(Color("#b3202a"), 0.95)
			_dome(root, red, at + Vector3(0, -0.004, 0), rx * 1.0, h * 0.97, rz * 1.0)
			_ring(root, _mat(Color("#8f1820"), 0.95), at + Vector3(0, 0.006, 0), rx * 1.02, rz * 1.02, 0.03)
			for s in [-1.0, 1.0]:
				_add(root, BoxMesh.new(), red, Vector3(cx + s * 0.018, rim - 0.035, cz + rz * 1.0), Vector3(0.35, 0, s * 0.25), Vector3(0.025, 0.08, 0.006))
		"fotr":
			var felt := _mat(Color("#2a2622"), 0.9)
			_ring(root, felt, at + Vector3(0, 0.05, 0), rx * 0.98, rz * 0.98, 0.1 + maxf(0.0, h - 0.09), 0.86)
			_ring(root, _mat(Color("#121212"), 0.7), at + Vector3(0, 0.022, 0), rx * 1.0, rz * 1.0, 0.024)
			_ring(root, felt, at + Vector3(0, 0.004, 0), rx * 1.7, rz * 1.6, 0.008)
		"baret":
			var yellow := _mat(Color("#f2b81c"), 0.35)
			_dome(root, yellow, at + Vector3(0, -0.004, 0), rx * 1.08, h * 1.15, rz * 1.08)
			_ring(root, yellow, at + Vector3(0, -0.002, -0.012), rx * 1.32, rz * 1.32, 0.008)
		"kulaklik":
			var black := _mat(Color("#141418"), 0.4, 0.2)
			# kafa bandı: elips yay boyunca birbirine değen ince parçalar
			var seg := BoxMesh.new()
			var ax := rx + 0.014
			var ay := top - rim + 0.08
			for i in 24:
				var a := PI * (i + 0.5) / 24.0
				var p := Vector3(cx + cos(a) * ax, rim - 0.07 + sin(a) * ay, cz)
				var tan := Vector2(-sin(a) * ax, cos(a) * ay)
				_add(root, seg, black, p, Vector3(0, 0, tan.angle() - PI / 2), Vector3(0.012, tan.length() * PI / 24.0 * 1.15, 0.03))
			for s in [-1.0, 1.0]:
				var cup := CylinderMesh.new()
				cup.top_radius = 0.042
				cup.bottom_radius = 0.046
				cup.height = 0.03
				_add(root, cup, _mat(Color("#d0263a"), 0.4), Vector3(cx + s * (rx + 0.012), rim - 0.07, cz), Vector3(0, 0, PI / 2))
		"tac":
			var gold := _mat(Color("#e8b33a"), 0.25, 0.9)
			var y := top - 0.02
			_ring(root, gold, Vector3(cx, y, cz), rx * 0.78, rz * 0.78, 0.04)
			for i in 8:
				var a := TAU * i / 8.0
				var spike := CylinderMesh.new()
				spike.top_radius = 0.0
				spike.bottom_radius = 0.016
				spike.height = 0.045
				_add(root, spike, gold, Vector3(cx + cos(a) * rx * 0.76, y + 0.04, cz + sin(a) * rz * 0.76))
				var gem := SphereMesh.new()
				gem.radius = 0.008
				gem.height = 0.016
				_add(root, gem, _mat(Color("#c0182a") if i % 2 == 0 else Color("#1e5ad8"), 0.1, 0.3), Vector3(cx + cos(a) * rx * 0.79, y, cz + sin(a) * rz * 0.79))
