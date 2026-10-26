# Aksesuarlar: gözlükler, küpeler, hızma, kolyeler, yara bandı, göz bandı, maske, fiyonk, kürdan...
# Yüz aksesuarları Quaternius erkek kafasının model uzayında (metre, yüz +z) kurulur; kökleri o anki kafaya
# (kadın) Hair'in kafa eşlemesiyle taşınır. Yama türleri (bant, göz bandı, maske) ölçülen kafa
# yüzeyine oturur. Kolyeler ve boyun kulaklığı göğüs kemiğine (mixamorig_Spine2) bağlanır.
extends RefCounted

const Hair := preload("res://scripts/hair.gd")

# Yüzdeki önemli noktalar (erkek kafası model uzayı)
const EYE := Vector3(0.0338, 1.6985, 0.0806)  # sağ göz merkezi (ön yüzey)
const NOSE := Vector3(0.0, 1.646, 0.103)  # burun altı (septum)
const MOUTH := Vector3(0.0, 1.62, 0.092)
const LOBE := Vector3(0.086, 1.664, -0.03)  # kulak memesi

static var _mats := {}


static func _mat(key: String, c: Color, rough := 0.5, metal := 0.0, alpha := 1.0) -> StandardMaterial3D:
	var k := "%s/%s/%.2f/%.2f/%.2f" % [key, c.to_html(), rough, metal, alpha]
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.roughness = rough
	m.metallic = metal
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.metallic_specular = 0.9
	_mats[k] = m
	return m


static func build(head: Node3D, skel: Skeleton3D, id: String, info: Dictionary) -> void:
	if id == "yok" or id == "":
		return
	var face := _face_root(head)
	match id:
		"gozluk":
			_glasses(face, "yuvarlak", _mat("cerceve", Color("#2b2b2e"), 0.35, 0.6), _mat("cam", Color("#dfe9f0"), 0.05, 0.0, 0.18))
		"gunes":
			_glasses(face, "yuvarlak_kalin", _mat("cerceve", Color("#111113"), 0.3), _mat("cam", Color("#0b0d10"), 0.05, 0.2, 0.92))
		"pilot":
			_glasses(face, "pilot", _mat("altin", Color("#d9b25a"), 0.25, 0.95), _mat("cam", Color("#3a2a14"), 0.05, 0.2, 0.75))
		"kalp":
			_glasses(face, "kalp", _mat("pembe", Color("#ff3d8b"), 0.35), _mat("cam", Color("#ff6fae"), 0.05, 0.1, 0.6))
		"nerd":
			_glasses(face, "kare", _mat("kalin", Color("#151515"), 0.4), _mat("cam", Color("#e8f0f4"), 0.05, 0.0, 0.15))
		"monokl":
			_glasses(face, "monokl", _mat("altin", Color("#d9b25a"), 0.25, 0.95), _mat("cam", Color("#e8f0f4"), 0.05, 0.0, 0.2))
		"bant":
			var c := _yaw_pitch(_land(head, Vector3(-0.047, 1.67, 0.085)))
			_patch(head, c, 0.32, 0.09, 0.6, _plaster_mat(), 0.003)
			_patch(head, c, 0.32, 0.09, -0.6, _plaster_mat(), 0.0042)
		"goz_bandi":
			_eye_patch(head)
		"maske":
			_mask(head)
		"kupe":
			for s in [-1.0, 1.0]:
				_hoop(face, s)
		"kupe_elmas":
			for s in [-1.0, 1.0]:
				_stud(face, s)
		"burun":
			_nose_ring(face)
		"fiyonk":
			_bow(head)
		"kurdan":
			_toothpick(face)
		"zincir", "inci", "kunye", "kulaklik_boyun":
			_neck_item(skel, id, info)


# ---------- yardımcılar ----------

static func _add(parent: Node3D, mesh: Mesh, mat: Material, xf := Transform3D.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


# Erkek kafası model uzayından o anki kafa çerçevesine taşıyan dönüşüm.
static func _to_frame() -> Transform3D:
	if not Hair._profiles.has("erkek"):
		return Transform3D.IDENTITY
	var a: Dictionary = Hair._profiles["erkek"]
	return Hair._box_map(a.min, a.max) * (a.frame as Transform3D).affine_inverse()


# Yüz aksesuarlarının kökü: içindeki her şey erkek kafası model uzayında yazılır.
static func _face_root(head: Node3D) -> Node3D:
	var root := Node3D.new()
	root.transform = _to_frame()
	head.add_child(root)
	return root


# Erkek modelindeki bir noktanın kafa çerçevesindeki yeri.
static func _land(_head: Node3D, p: Vector3) -> Vector3:
	return _to_frame() * p


static func _yaw_pitch(p: Vector3) -> Vector2:
	return Vector2(atan2(p.x, -p.z), asin(clampf(p.y / maxf(p.length(), 0.0001), -1.0, 1.0)))


static func _tube_mesh(paths: Array, radius: float, sides := 8, closed := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for path in paths:
		var p: PackedVector3Array = path
		if closed:
			p = p.duplicate()
			p.append(p[0])
			p.append(p[1])
		var radii := PackedFloat32Array()
		radii.resize(p.size())
		radii.fill(radius)
		Hair._tube(st, p, radii, sides)
	return st.commit()


# Kafa yüzeyine oturan ince yama: merkez (yaw, pitch radyan), genişlik/yükseklik (radyan), dönüş.
static func _patch(head: Node3D, center: Vector2, w: float, h: float, rot: float, mat: Material, off := 0.0025) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 12
	var nv := 6
	var pts := []
	for j in nv + 1:
		var row := []
		for i in nu + 1:
			var u := (float(i) / nu - 0.5) * w
			var v := (float(j) / nv - 0.5) * h
			var ru := u * cos(rot) - v * sin(rot)
			var rv := u * sin(rot) + v * cos(rot)
			row.append([Hair.scalp(center.x + ru, center.y + rv, off), Vector2(float(i) / nu, float(j) / nv)])
		pts.append(row)
	for j in nv:
		for i in nu:
			var q: Array = [pts[j][i], pts[j][i + 1], pts[j + 1][i + 1], pts[j + 1][i]]
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_normal((q[k][0] as Vector3).normalized())
				st.set_uv(q[k][1])
				st.add_vertex(q[k][0])
	_add(head, st.commit(), mat)


static func _plaster_mat() -> StandardMaterial3D:
	if _mats.has("bant"):
		return _mats["bant"]
	var img := Image.create(64, 16, false, Image.FORMAT_RGB8)
	for y in 16:
		for x in 64:
			var pad := x > 22 and x < 42 and y > 2 and y < 13
			var c := Color("#f2ead9") if pad else Color("#e3c9a6")
			if not pad and (x + y * 3) % 7 == 0:
				c = c.darkened(0.08)  # delikler
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.85
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["bant"] = m
	return m


# ---------- gözlükler (erkek kafası model uzayında) ----------

# Cam çerçevesinin şekli (cam merkezine göre, metre): kapalı nokta listesi.
static func _outline(shape: String) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 36
	for i in n:
		var a := TAU * i / n
		var c := cos(a)
		var s := sin(a)
		var p := Vector2.ZERO
		match shape:
			"yuvarlak", "monokl":
				p = Vector2(c, s) * 0.021
			"yuvarlak_kalin":
				p = Vector2(c * 0.025, s * 0.021)
			"kare":
				p = Vector2(signf(c) * pow(absf(c), 0.45) * 0.026, signf(s) * pow(absf(s), 0.45) * 0.018)
			"pilot":
				var low := maxf(0.0, -s)
				p = Vector2(c * (0.025 + low * 0.003) + low * 0.005, s * 0.019 - low * 0.008)
			"kalp":
				var hx := 16.0 * pow(sin(a), 3.0)
				var hy := 13.0 * cos(a) - 5.0 * cos(2.0 * a) - 2.0 * cos(3.0 * a) - cos(4.0 * a)
				p = Vector2(hx, hy + 3.0) * 0.0014
		pts.append(p)
	return pts


static func _glasses(root: Node3D, shape: String, frame_mat: Material, lens_mat: Material) -> void:
	var zf := EYE.z + 0.017  # camlar gözün önünde
	var ey := EYE.y
	var sides: Array = [1.0] if shape == "monokl" else [-1.0, 1.0]
	var thick := 0.0024 if shape in ["yuvarlak", "pilot", "monokl"] else 0.0038
	var spread := 0.003 if shape in ["kare", "yuvarlak_kalin", "kalp"] else 0.0
	var ol := _outline(shape)
	var half := 0.0
	for p in ol:
		half = maxf(half, absf(p.x))
	for s in sides:
		var cx: float = s * (EYE.x + spread)
		var ring := PackedVector3Array()
		for p in ol:
			var x: float = cx + p.x * (-s if shape == "pilot" else s)
			ring.append(Vector3(x, ey + p.y, zf - x * x * 2.0))
		_add(root, _tube_mesh([ring], thick, 6, true), frame_mat)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var c := Vector3(cx, ey, zf - cx * cx * 2.0 + 0.001)
		for i in ring.size():
			for v in [c, ring[i], ring[(i + 1) % ring.size()]]:
				st.set_normal(Vector3(0, 0, 1))
				st.add_vertex(v)
		_add(root, st.commit(), lens_mat)
		if shape == "monokl":
			var chain := PackedVector3Array()
			for i in 12:
				var f := i / 11.0
				chain.append(Vector3(cx + s * (0.02 + f * 0.025), ey - 0.018 - sin(f * PI) * 0.025 - f * 0.05, zf - f * 0.04))
			_add(root, _tube_mesh([chain], 0.0009, 4), frame_mat)
			return
		# sap: camın dış kenarından kafanın yanına, kulağın üstüne
		var hinge := Vector3(cx + s * half, ey + 0.004, zf - (cx + s * half) * (cx + s * half) * 2.0)
		var arm := PackedVector3Array([hinge, Vector3(s * 0.072, ey + 0.006, 0.072), Vector3(s * 0.08, ey + 0.004, 0.03),
			Vector3(s * 0.083, ey, -0.01), Vector3(s * 0.082, ey - 0.012, -0.04)])
		_add(root, _tube_mesh([arm], thick * 0.75, 5), frame_mat)
	if shape != "monokl":
		var br := PackedVector3Array()
		var x0 := EYE.x + spread - half
		for i in 9:
			var f := i / 8.0
			var x := lerpf(-x0, x0, f)
			br.append(Vector3(x, ey + 0.004 + sin(f * PI) * 0.004, zf + 0.002 - x * x * 2.0))
		_add(root, _tube_mesh([br], thick, 6), frame_mat)


# ---------- yüz ----------

static func _eye_patch(head: Node3D) -> void:
	var black := _mat("bant_siyah", Color("#141416"), 0.6)
	var c := _yaw_pitch(_land(head, Vector3(-EYE.x, EYE.y, EYE.z)))
	_patch(head, c, 0.46, 0.36, 0.1, black, 0.008)
	var strap := PackedVector3Array()
	for i in 41:
		var yaw := lerpf(c.x + 0.2, c.x + TAU - 0.2, i / 40.0)
		var pitch := lerpf(c.y + 0.14, c.y + 0.32, sin(i / 40.0 * PI))
		strap.append(Hair.scalp(yaw, pitch, 0.006))
	_add(head, _tube_mesh([strap], 0.0022, 5), black)


static func _mask(head: Node3D) -> void:
	var blue := _mat("maske", Color("#9fd2e6"), 0.9)
	var c := _yaw_pitch(_land(head, Vector3(0, (NOSE.y + MOUTH.y) * 0.5 - 0.008, 0.09)))
	_patch(head, c, 1.3, 0.62, 0.0, blue, 0.009)
	for s in [-1.0, 1.0]:
		var strap := PackedVector3Array()
		for i in 13:
			var f := i / 12.0
			strap.append(Hair.scalp(c.x + s * lerpf(0.64, 1.6, f), c.y + 0.08 + sin(f * PI) * 0.1 + f * 0.12, 0.004))
		_add(head, _tube_mesh([strap], 0.0016, 4), _mat("maske_ip", Color("#e9eef0"), 0.9))


static func _hoop(root: Node3D, s: float) -> void:
	var r := 0.017
	var t := TorusMesh.new()
	t.inner_radius = r - 0.0015
	t.outer_radius = r
	t.rings = 24
	t.ring_segments = 8
	var p := Vector3(s * (LOBE.x + 0.008), LOBE.y - r * 0.95, LOBE.z + 0.004)
	# halka yan düzlemde (kulağa paralel) sarkar
	_add(root, t, _mat("altin", Color("#e2b84f"), 0.2, 1.0), Transform3D(Basis(Vector3.FORWARD, PI / 2).rotated(Vector3.UP, s * 0.3), p))


static func _stud(root: Node3D, s: float) -> void:
	var gem := SphereMesh.new()
	gem.radius = 0.004
	gem.height = 0.008
	gem.radial_segments = 8
	gem.rings = 4
	var m := _mat("elmas", Color("#e8f4ff"), 0.02, 0.6)
	m.emission_enabled = true
	m.emission = Color("#bfe6ff")
	m.emission_energy_multiplier = 0.8
	_add(root, gem, m, Transform3D(Basis(), Vector3(s * (LOBE.x + 0.007), LOBE.y + 0.002, LOBE.z + 0.006)))


static func _nose_ring(root: Node3D) -> void:
	var t := TorusMesh.new()
	t.inner_radius = 0.0062
	t.outer_radius = 0.0076
	t.rings = 20
	t.ring_segments = 6
	_add(root, t, _mat("gumus", Color("#d6d8dc"), 0.2, 1.0), Transform3D(Basis(Vector3.RIGHT, PI / 2 + 0.5), NOSE + Vector3(0, -0.006, -0.002)))


static func _toothpick(root: Node3D) -> void:
	var a := MOUTH + Vector3(-0.018, -0.002, -0.004)
	var dir := Vector3(-0.5, -0.18, 0.85).normalized()
	var c := CylinderMesh.new()
	c.top_radius = 0.0011
	c.bottom_radius = 0.0017
	c.height = 0.065
	c.radial_segments = 6
	var y := dir
	var x := y.cross(Vector3.UP).normalized()
	_add(root, c, _mat("tahta", Color("#d8b98a"), 0.8), Transform3D(Basis(x, y, x.cross(y)), a + dir * 0.026))


static func _bow(head: Node3D) -> void:
	var red := _mat("fiyonk", Color("#e0244f"), 0.55)
	var base := Hair.scalp(0.55, 0.95, 0.0)
	var p := base.normalized() * (base.length() + 0.006)
	var n := p.normalized()
	var x := n.cross(Vector3.FORWARD).normalized()
	var z := x.cross(n).normalized()
	var root := Node3D.new()
	root.transform = Transform3D(Basis(x, n, z), p)
	head.add_child(root)
	for s in [-1.0, 1.0]:
		var lobe := SphereMesh.new()
		lobe.radius = 0.022
		lobe.height = 0.044
		_add(root, lobe, red, Transform3D(Basis().scaled(Vector3(1.25, 0.5, 0.85)).rotated(Vector3.UP, s * 0.2), Vector3(s * 0.026, 0.004, 0)))
		var tail := BoxMesh.new()
		tail.size = Vector3(0.011, 0.003, 0.034)
		_add(root, tail, red, Transform3D(Basis(Vector3.UP, s * 0.5), Vector3(s * 0.011, -0.002, 0.024)))
	var knot := SphereMesh.new()
	knot.radius = 0.009
	knot.height = 0.018
	_add(root, knot, _mat("fiyonk2", Color("#b0163a"), 0.5), Transform3D(Basis().scaled(Vector3(1, 0.75, 1.1)), Vector3(0, 0.003, 0)))


# ---------- boyun (göğüs kemiğine bağlı, model uzayında yazılır) ----------

static func _neck_item(skel: Skeleton3D, id: String, info: Dictionary) -> void:
	var chest := skel.find_bone("mixamorig_Spine2")
	if chest < 0 or not info.has("chest_bind"):
		return
	var ba := BoneAttachment3D.new()
	ba.bone_idx = chest
	skel.add_child(ba)
	var holder := Node3D.new()
	holder.transform = info.chest_bind
	ba.add_child(holder)
	var np: Vector3 = info.neck
	# kolye yakanın üstünde boynun dibini dolaşır, önde göğse sarkar
	# boyun kemiği boynun arkasına yakındır: halka öne alınır
	var rx := 0.08
	var rz := 0.085
	var center := np + Vector3(0, -0.045, 0.06)
	var curve := PackedVector3Array()
	var n := 48
	for i in n:
		var a := TAU * i / n
		var front := maxf(0.0, cos(a))  # a = 0 önde (+z)
		curve.append(center + Vector3(sin(a) * rx, -front * front * 0.065, cos(a) * rz + front * front * 0.03))
	match id:
		"zincir":
			var gold := _mat("altin", Color("#e2b84f"), 0.2, 1.0)
			var link := TorusMesh.new()
			link.inner_radius = 0.0026
			link.outer_radius = 0.0046
			link.rings = 10
			link.ring_segments = 5
			var m2 := n * 2
			for i in m2:
				var f := float(i) / m2
				var p := _curve_at(curve, f)
				var t := (_curve_at(curve, f + 0.003) - p).normalized()
				var side := Vector3.UP.cross(t).normalized()
				var b := Basis(side, t, side.cross(t))
				if i % 2 == 1:
					b = b * Basis(Vector3.UP, PI / 2)
				_add(holder, link, gold, Transform3D(b, p))
			var med := CylinderMesh.new()
			med.top_radius = 0.015
			med.bottom_radius = 0.015
			med.height = 0.004
			_add(holder, med, gold, Transform3D(Basis(Vector3.RIGHT, PI / 2), curve[0] + Vector3(0, -0.02, 0.004)))
		"inci":
			var pearl := SphereMesh.new()
			pearl.radius = 0.0055
			pearl.height = 0.011
			pearl.radial_segments = 10
			pearl.rings = 5
			var pm := _mat("inci", Color("#f4efe6"), 0.18, 0.15)
			for i in 44:
				_add(holder, pearl, pm, Transform3D(Basis(), _curve_at(curve, i / 44.0)))
		"kunye":
			var steel := _mat("celik", Color("#c9ccd1"), 0.3, 1.0)
			_add(holder, _tube_mesh([curve], 0.0012, 4, true), steel)
			for k in 2:
				var tag := BoxMesh.new()
				tag.size = Vector3(0.022, 0.034, 0.0018)
				_add(holder, tag, steel, Transform3D(Basis(Vector3.UP, k * 0.3 - 0.15), curve[0] + Vector3(k * 0.006 - 0.003, -0.022 - k * 0.005, 0.004 + k * 0.002)))
		"kulaklik_boyun":
			var black := _mat("kulaklik", Color("#16171b"), 0.4, 0.2)
			var band := PackedVector3Array()
			for i in 25:
				var a := lerpf(PI * 0.5, PI * 1.5, i / 24.0)
				band.append(center + Vector3(sin(a) * (rx + 0.02), 0.02, cos(a) * (rz + 0.02)))
			_add(holder, _tube_mesh([band], 0.006, 6), black)
			for s in [-1.0, 1.0]:
				var cup := CylinderMesh.new()
				cup.top_radius = 0.034
				cup.bottom_radius = 0.038
				cup.height = 0.024
				var p := center + Vector3(s * (rx + 0.02), 0.0, 0.035)
				var b := Basis(Vector3.RIGHT, PI / 2 - 0.5).rotated(Vector3.UP, s * 0.75)
				_add(holder, cup, black, Transform3D(b, p))
				var pad := TorusMesh.new()
				pad.inner_radius = 0.02
				pad.outer_radius = 0.034
				_add(holder, pad, _mat("kulaklik_ped", Color("#d0263a"), 0.5), Transform3D(b, p + b.y * -0.012))


static func _curve_at(curve: PackedVector3Array, f: float) -> Vector3:
	var n := curve.size()
	var x := fposmod(f, 1.0) * n
	var i := int(x)
	return curve[i % n].lerp(curve[(i + 1) % n], x - i)
