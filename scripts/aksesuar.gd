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
		"yuz_bandana":
			_face_bandana(head)
		"saat", "kelepce":
			_wrist_item(skel, id)
		"canta", "gitar":
			_back_item(skel, id)
		"anahtar":
			_keys(skel)
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
		"palyaco":
			var burun := SphereMesh.new()
			burun.radius = 0.019
			burun.height = 0.038
			_add(face, burun, _mat("palyaco", Color("#e01b1b"), 0.18), Transform3D(Basis(), NOSE + Vector3(0, 0.008, 0.016)))
		"lolipop":
			_lolipop(face)
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


# Ağızda lolipop: beyaz çubuk ve ucunda pembe-beyaz sarmal şeker
static func _lolipop(root: Node3D) -> void:
	var a := MOUTH + Vector3(0.012, -0.004, -0.004)
	var dir := Vector3(0.55, -0.2, 0.8).normalized()
	var c := CylinderMesh.new()
	c.top_radius = 0.0022
	c.bottom_radius = 0.0022
	c.height = 0.075
	c.radial_segments = 6
	var y := dir
	var x := y.cross(Vector3.UP).normalized()
	_add(root, c, _mat("cubuk", Color("#f4f1ea"), 0.5), Transform3D(Basis(x, y, x.cross(y)), a + dir * 0.03))
	var uc := a + dir * 0.072
	var seker := CylinderMesh.new()
	seker.top_radius = 0.024
	seker.bottom_radius = 0.024
	seker.height = 0.009
	seker.radial_segments = 20
	var n := Vector3(0, 0, 1)
	var xx := Vector3.RIGHT
	_add(root, seker, _mat("seker", Color("#ff4f9a"), 0.25), Transform3D(Basis(xx, n, xx.cross(n)), uc))
	for i in 2:
		var hal := TorusMesh.new()
		hal.inner_radius = 0.006 + i * 0.008
		hal.outer_radius = 0.0095 + i * 0.008
		hal.rings = 18
		hal.ring_segments = 4
		_add(root, hal, _mat("seker_beyaz", Color("#fff6fa"), 0.3), Transform3D(Basis(xx, n, xx.cross(n)), uc + Vector3(0, 0, 0.0046)))


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
		# iri gövdede göğüs önde biraz daha dolgun (model_body TYPES sekil.govde): kolye göğsün üstünde kalsın
		var sis := maxf(0.0, float(info.get("sis", 0.0))) * 0.35 * front * front
		curve.append(center + Vector3(sin(a) * rx, -front * front * 0.065, cos(a) * rz + front * front * 0.03 + sis))
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


# ---------- gövdeye takılanlar (kıyafet modelinin bağlama uzayında: yüz +z, karakterin solu +x, T duruşu) ----------

# Kıyafet meshlerinden bir kemiğin bağlama (bind) dönüşümü: model uzayı -> kemik uzayı.
static func _obind(skel: Skeleton3D, bone: String) -> Variant:
	for mi in skel.get_children():
		if mi is MeshInstance3D and (mi as MeshInstance3D).skin:
			var sk := (mi as MeshInstance3D).skin
			for i in sk.get_bind_count():
				if String(sk.get_bind_name(i)) == bone:
					return sk.get_bind_pose(i)
	return null


static var _vcache := {}

# Kıyafet parçalarının (gövde tipine göre şekillenmiş) köşeleri: takılan eşyalar gerçek yüzeye göre yerleşir.
static func _cloth_verts(skel: Skeleton3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for mi in skel.get_children():
		if not mi is MeshInstance3D or String(mi.name) in ["Bas", "Goz", "Kas", "Yaka", "Kapuson"]:
			continue
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		var k := m.get_instance_id()
		if not _vcache.has(k):
			_vcache[k] = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		out.append_array(_vcache[k])
	return out


# (x, y) çevresindeki (r yarıçap) köşelerin en öndeki (front) ya da en arkadaki z değeri.
static func _surface_z(verts: PackedVector3Array, x: float, y: float, r: float, front: bool, fallback: float) -> float:
	var best := -INF if front else INF
	for v in verts:
		if absf(v.x - x) < r and absf(v.y - y) < r:
			best = maxf(best, v.z) if front else minf(best, v.z)
	return best if is_finite(best) else fallback


# Bir kemiğe bağlı tutucu: içindekiler kıyafet modelinin uzayında yazılır.
static func _holder(skel: Skeleton3D, bone: String) -> Node3D:
	var bi := skel.find_bone(bone)
	var bind: Variant = _obind(skel, bone)
	if bi < 0 or bind == null:
		return null
	var ba := BoneAttachment3D.new()
	ba.bone_idx = bi
	skel.add_child(ba)
	var holder := Node3D.new()
	holder.transform = bind
	ba.add_child(holder)
	return holder


# Kol saati (sol bilek) ya da kelepçe (sağ bilekte kilitli, zincirle sarkan açık halka).
static func _wrist_item(skel: Skeleton3D, id: String) -> void:
	var bone := "mixamorig_LeftHand" if id == "saat" else "mixamorig_RightHand"
	var holder := _holder(skel, bone)
	if holder == null:
		return
	var hb: Variant = _obind(skel, bone)
	var wrist: Vector3 = (hb as Transform3D).affine_inverse().origin
	var s := signf(wrist.x)
	# bilek kalınlığı: bilek hizasındaki el/eldiven köşelerinin bilek eksenine uzaklığı (kolun bütün yüzeyleri)
	var c := wrist + Vector3(s * 0.012, 0, 0)  # bileğin hemen el tarafı (kol manşetinin önünde)
	var ds: Array[float] = []
	for mi in skel.get_children():
		if not mi is MeshInstance3D or not String(mi.name).contains("Arms"):
			continue
		var m := (mi as MeshInstance3D).mesh
		for si in m.get_surface_count():
			for v in (m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				if absf(v.x - c.x) < 0.006:
					var d := Vector2(v.y - c.y, v.z - c.z).length()
					if d < 0.06:
						ds.append(d)
	ds.sort()
	# başparmak ve manşet uçları ölçüyü büyütmesin: ortanca uzaklık
	var r := clampf(ds[ds.size() / 2] * 1.12, 0.022, 0.038) if not ds.is_empty() else 0.03
	var ring_basis := Basis(Vector3.FORWARD, PI / 2)  # halka ekseni kol boyunca (x)
	if id == "saat":
		var strap := TorusMesh.new()
		strap.inner_radius = r + 0.001
		strap.outer_radius = r + 0.007
		strap.rings = 28
		strap.ring_segments = 6
		_add(holder, strap, _mat("saat_kayis", Color("#2a2420"), 0.7), Transform3D(ring_basis * Basis.from_scale(Vector3(1, 2.2, 1)), c))
		var face := CylinderMesh.new()
		face.top_radius = 0.017
		face.bottom_radius = 0.018
		face.height = 0.007
		face.radial_segments = 20
		# kadran elin üstünde (T duruşunda +y)
		_add(holder, face, _mat("celik", Color("#c9ccd1"), 0.3, 1.0), Transform3D(Basis(), c + Vector3(0, r + 0.006, 0)))
		var glass := CylinderMesh.new()
		glass.top_radius = 0.0145
		glass.bottom_radius = 0.0145
		glass.height = 0.002
		glass.radial_segments = 20
		_add(holder, glass, _mat("kadran", Color("#10161f"), 0.15), Transform3D(Basis(), c + Vector3(0, r + 0.0098, 0)))
		for k in 2:
			var hand := BoxMesh.new()
			hand.size = Vector3(0.0016, 0.001, 0.011 - k * 0.003)
			_add(holder, hand, _mat("ibre", Color("#e8e4d8"), 0.4), Transform3D(Basis(Vector3.UP, 0.9 + k * 2.0), c + Vector3(0, r + 0.0112, 0) + Basis(Vector3.UP, 0.9 + k * 2.0) * Vector3(0, 0, -(0.011 - k * 0.003) * 0.5)))
	else:
		var steel := _mat("celik", Color("#c9ccd1"), 0.3, 1.0)
		var cuff := TorusMesh.new()
		cuff.inner_radius = r + 0.001
		cuff.outer_radius = r + 0.006
		cuff.rings = 24
		cuff.ring_segments = 5
		_add(holder, cuff, steel, Transform3D(ring_basis * Basis.from_scale(Vector3(1, 1.6, 1)), c))
		# kilit elin üstünde (T duruşunda +y: kol sarkınca dışa bakar); zincir parmaklara doğru uzanır, açık halka
		# elin dış yanında sarkar (kol aşağıdayken aşağı)
		var box := BoxMesh.new()
		box.size = Vector3(0.02, 0.012, 0.016)
		var lock_p := c + Vector3(0, r + 0.007, 0)
		_add(holder, box, steel, Transform3D(Basis(), lock_p))
		var link := TorusMesh.new()
		link.inner_radius = 0.0035
		link.outer_radius = 0.0062
		link.rings = 12
		link.ring_segments = 5
		var p := lock_p + Vector3(s * 0.016, 0.004, 0)
		for k in 3:
			var lb := Basis(Vector3.BACK, PI / 2) if k % 2 == 0 else Basis(Vector3.BACK, PI / 2) * Basis(Vector3.UP, PI / 2)
			_add(holder, link, steel, Transform3D(lb, p))
			p += Vector3(s * 0.0105, 0.003, 0)
		var open := TorusMesh.new()
		open.inner_radius = 0.028
		open.outer_radius = 0.034
		open.rings = 24
		open.ring_segments = 5
		_add(holder, open, steel, Transform3D(Basis(Vector3.RIGHT, PI / 2) * Basis.from_scale(Vector3(1, 1, 1.3)), p + Vector3(s * 0.031, 0.012, 0)))


# Sırt çantası ya da sırtta gitar: göğüs kemiğine bağlı, sırt yüzeyine dayalı, askıları omuzlardan geçer.
static func _back_item(skel: Skeleton3D, id: String) -> void:
	var holder := _holder(skel, "mixamorig_Spine2")
	if holder == null:
		return
	var verts := _cloth_verts(skel)
	var cb: Variant = _obind(skel, "mixamorig_Spine2")
	var nb: Variant = _obind(skel, "mixamorig_Neck")
	var chest: Vector3 = (cb as Transform3D).affine_inverse().origin
	var neck: Vector3 = (nb as Transform3D).affine_inverse().origin if nb != null else chest + Vector3(0, 0.2, 0)
	var y0 := chest.y - 0.05
	var back_z := _surface_z(verts, 0.0, y0, 0.05, false, chest.z - 0.13)
	var sh_y := neck.y - 0.035  # omuz üstü
	var strap_m := _mat("canta_kayis", Color("#1f2226"), 0.75)
	if id == "canta":
		var cloth := _mat("canta", Color("#3d5a3a"), 0.9)
		var dark := _mat("canta_koyu", Color("#2b3f29"), 0.9)
		var depth := 0.12
		var pc := Vector3(0, y0 - 0.02, back_z - depth * 0.5 - 0.005)
		var body := BoxMesh.new()
		body.size = Vector3(0.28, 0.36, depth)
		_add(holder, body, cloth, Transform3D(Basis(), pc))
		var lid := SphereMesh.new()
		lid.radius = 1.0
		lid.height = 1.0
		lid.is_hemisphere = true
		lid.radial_segments = 16
		lid.rings = 6
		_add(holder, lid, cloth, Transform3D(Basis().scaled(Vector3(0.14, 0.05, depth * 0.5)), pc + Vector3(0, 0.18, 0)))
		var pocket := BoxMesh.new()
		pocket.size = Vector3(0.2, 0.14, 0.05)
		_add(holder, pocket, dark, Transform3D(Basis(), pc + Vector3(0, -0.08, -depth * 0.5 - 0.022)))
		var flap := BoxMesh.new()
		flap.size = Vector3(0.21, 0.05, 0.056)
		_add(holder, flap, cloth, Transform3D(Basis(Vector3.RIGHT, -0.15), pc + Vector3(0, -0.02, -depth * 0.5 - 0.024)))
		var handle := PackedVector3Array()
		for i in 9:
			var a := PI * i / 8.0
			handle.append(pc + Vector3(cos(a) * 0.04, 0.2 + sin(a) * 0.03, 0.01))
		_add(holder, _tube_mesh([handle], 0.006, 5), strap_m)
		# askılar: çantanın üst köşesinden omuzun üstünden göğsün önüne, oradan koltuk altına
		for s in [-1.0, 1.0]:
			var x: float = s * 0.085
			var fz := _surface_z(verts, x, sh_y - 0.12, 0.035, true, chest.z + 0.1)
			var bz := _surface_z(verts, x, sh_y - 0.02, 0.03, false, back_z)
			var tz := _surface_z(verts, x, sh_y + 0.0, 0.04, true, chest.z)
			var top_y := _top_y(verts, x, (bz + fz) * 0.5)
			var path := PackedVector3Array([
				Vector3(x, pc.y + 0.15, back_z - 0.01), Vector3(x, sh_y - 0.03, bz - 0.012),
				Vector3(x, top_y + 0.01, (bz + tz) * 0.5), Vector3(x, sh_y - 0.05, fz + 0.012),
				Vector3(x, sh_y - 0.14, _surface_z(verts, x, sh_y - 0.14, 0.035, true, fz) + 0.012),
				Vector3(s * 0.15, sh_y - 0.25, _surface_z(verts, s * 0.15, sh_y - 0.25, 0.035, true, fz - 0.03) + 0.008)])
			_add(holder, _ribbon(_smooth(path, 4), 0.034, chest.z), strap_m)
	else:
		# gitar: gövde sol alt (karakterin solu +x), sap sağ omuzun arkasından yukarı çıkar
		var wood := _mat("gitar", Color("#b0702e"), 0.45)
		var dark := _mat("gitar_koyu", Color("#3a2414"), 0.55)
		var g := Node3D.new()
		var tilt := 0.62
		g.transform = Transform3D(Basis(Vector3.BACK, tilt), Vector3(0.06, y0 - 0.16, back_z - 0.05))
		holder.add_child(g)
		var bowl := CylinderMesh.new()
		bowl.top_radius = 1.0
		bowl.bottom_radius = 1.0
		bowl.height = 1.0
		bowl.radial_segments = 28
		var flat := Basis(Vector3.RIGHT, PI / 2)
		# gövde: iki yassı silindir (alt geniş, üst dar) + ses deliği; silindir ekseni sırttan dışarı (z)
		_add(g, bowl, wood, Transform3D(flat * Basis.from_scale(Vector3(0.16, 0.075, 0.16)), Vector3(0, -0.1, 0)))
		_add(g, bowl, wood, Transform3D(flat * Basis.from_scale(Vector3(0.125, 0.075, 0.125)), Vector3(0, 0.05, 0)))
		_add(g, bowl, dark, Transform3D(flat * Basis.from_scale(Vector3(0.038, 0.077, 0.038)), Vector3(0, -0.02, 0)))
		var neck_m := BoxMesh.new()
		neck_m.size = Vector3(0.045, 0.4, 0.028)
		_add(g, neck_m, dark, Transform3D(Basis(), Vector3(0, 0.36, 0.0)))
		var head_m := BoxMesh.new()
		head_m.size = Vector3(0.062, 0.11, 0.022)
		_add(g, head_m, dark, Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0, 0.6, -0.01)))
		var bridge := BoxMesh.new()
		bridge.size = Vector3(0.07, 0.012, 0.01)
		_add(g, bridge, dark, Transform3D(Basis(), Vector3(0, -0.15, -0.042)))
		# askı: gitarın altından sol yandan geçip göğüste çapraz, sağ omuzun üstünden sapa
		var fz := _surface_z(verts, 0.0, chest.y - 0.02, 0.05, true, chest.z + 0.1)
		var rs := -0.09
		var sbz := _surface_z(verts, rs, sh_y - 0.02, 0.03, false, back_z)
		var stz := _surface_z(verts, rs, sh_y, 0.04, true, chest.z)
		var low := g.transform * Vector3(0, -0.28, 0.0)
		var path := PackedVector3Array([
			low, Vector3(0.2, y0 - 0.2, (back_z + fz) * 0.5),
			Vector3(0.13, y0 - 0.16, _surface_z(verts, 0.13, y0 - 0.16, 0.04, true, fz) + 0.012),
			Vector3(0.0, chest.y - 0.02, fz + 0.014),
			Vector3(rs, sh_y - 0.06, _surface_z(verts, rs, sh_y - 0.06, 0.035, true, fz) + 0.012),
			Vector3(rs, _top_y(verts, rs, (sbz + stz) * 0.5) + 0.01, (sbz + stz) * 0.5),
			Vector3(rs, sh_y - 0.03, sbz - 0.015), g.transform * Vector3(0, 0.3, -0.02)])
		_add(holder, _ribbon(_smooth(path, 4), 0.03, chest.z), strap_m)


# Yassı kayış: yol boyunca gövdeye teğet (omurga ekseninden dışarı bakan yüzle) şerit, iki yüzlü.
static func _ribbon(path: PackedVector3Array, width: float, axis_z: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lefts := []
	var rights := []
	var outs := []
	for i in path.size():
		var t := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var o := Vector3(path[i].x, 0.0, path[i].z - axis_z)
		if absf(t.y) < 0.5:
			o = Vector3.UP  # omuzun üstünde yatay giden kısım: yüz yukarı
		o = (o - t * o.dot(t)).normalized()
		var side := t.cross(o).normalized() * width * 0.5
		lefts.append(path[i] - side)
		rights.append(path[i] + side)
		outs.append(o)
	for i in path.size() - 1:
		var q := [lefts[i], rights[i], rights[i + 1], lefts[i + 1]]
		var n: Vector3 = (outs[i] + outs[i + 1]).normalized()
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(n)
			st.add_vertex(q[k])
	return st.commit()


# (x, z) dikeyinde kıyafetin en üst noktası (omuz üstü).
static func _top_y(verts: PackedVector3Array, x: float, z: float) -> float:
	var best := -INF
	for v in verts:
		if absf(v.x - x) < 0.025 and absf(v.z - z) < 0.04 and v.y < 1.7:
			best = maxf(best, v.y)
	return best if is_finite(best) else 1.45


# Kırık çizgiyi yumuşatır (Catmull-Rom): askılar köşeli görünmesin.
static func _smooth(p: PackedVector3Array, sub: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in p.size() - 1:
		var p0 := p[maxi(i - 1, 0)]
		var p1 := p[i]
		var p2 := p[i + 1]
		var p3 := p[mini(i + 2, p.size() - 1)]
		for k in sub:
			var t := float(k) / sub
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(p[p.size() - 1])
	return out


# Anahtarlık: sağ kalçanın önünde kemerden sarkan halka ve üç anahtar (gardiyandan aşırılmış); önden düz görünür.
static func _keys(skel: Skeleton3D) -> void:
	var holder := _holder(skel, "mixamorig_Hips")
	if holder == null:
		return
	var hb: Variant = _obind(skel, "mixamorig_Hips")
	var hips: Vector3 = (hb as Transform3D).affine_inverse().origin
	var verts := _cloth_verts(skel)
	var x := -0.105
	var y := hips.y + 0.06
	var z := _surface_z(verts, x, y, 0.025, true, hips.z + 0.1) + 0.006
	var steel := _mat("celik", Color("#c9ccd1"), 0.3, 1.0)
	var brass := _mat("pirinc", Color("#c9a24a"), 0.3, 0.9)
	var face := Basis(Vector3.RIGHT, PI / 2)  # halka düzlemi önden görünür (eksen z)
	var clip := BoxMesh.new()
	clip.size = Vector3(0.014, 0.04, 0.006)
	_add(holder, clip, steel, Transform3D(Basis(), Vector3(x, y + 0.004, z)))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.016
	ring.outer_radius = 0.02
	ring.rings = 20
	ring.ring_segments = 5
	var rc := Vector3(x, y - 0.03, z + 0.004)
	_add(holder, ring, steel, Transform3D(face, rc))
	var bow := TorusMesh.new()
	bow.inner_radius = 0.005
	bow.outer_radius = 0.0095
	bow.rings = 12
	bow.ring_segments = 4
	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.006, 0.045, 0.003)
	var tooth := BoxMesh.new()
	tooth.size = Vector3(0.008, 0.006, 0.003)
	for k in 3:
		var key := Node3D.new()
		key.transform = Transform3D(Basis(Vector3.BACK, (k - 1) * 0.35), rc + Vector3(0, -0.016, 0.002 + k * 0.002))
		holder.add_child(key)
		var m := brass if k != 1 else steel
		_add(key, bow, m, Transform3D(face, Vector3(0, -0.01, 0)))
		_add(key, shaft, m, Transform3D(Basis(), Vector3(0, -0.042, 0)))
		for t in 2:
			_add(key, tooth, m, Transform3D(Basis(), Vector3(0.006, -0.05 - t * 0.01, 0)))


# Yüz bandanası (kovboy/kaçak): burnun üstünden çeneye kırmızı puantiyeli bez, çenenin altında üçgen sarkar.
static func _face_bandana(head: Node3D) -> void:
	var m := _bandana_mat()
	var c := _yaw_pitch(_land(head, Vector3(0, (NOSE.y + MOUTH.y) * 0.5 - 0.012, 0.09)))
	_patch(head, c, 1.75, 0.8, 0.0, m, 0.012)
	# çene altı üçgen: patch'in alt kenarından aşağı
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var l := Hair.scalp(c.x - 0.45, c.y - 0.42, 0.014)
	var r := Hair.scalp(c.x + 0.45, c.y - 0.42, 0.014)
	var mid := Hair.scalp(c.x, c.y - 0.42, 0.016)
	var tip := mid + Vector3(0, -0.07, -0.02)
	for tri in [[l, mid, tip], [mid, r, tip]]:
		var nrm := ((tri[1] - tri[0]) as Vector3).cross((tri[2] - tri[0]) as Vector3).normalized()
		for v in tri:
			st.set_normal(-nrm if nrm.z > 0.0 else nrm)
			st.set_uv(Vector2((v as Vector3).x * 8.0, (v as Vector3).y * 8.0))
			st.add_vertex(v)
	_add(head, st.commit(), m)
	# arkada düğüm
	var knot := SphereMesh.new()
	knot.radius = 0.014
	knot.height = 0.024
	_add(head, knot, m, Transform3D(Basis(), Hair.scalp(c.x + PI, c.y + 0.12, 0.012)))


static func _bandana_mat() -> StandardMaterial3D:
	if _mats.has("yuz_bandana"):
		return _mats["yuz_bandana"]
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	img.fill(Color("#a61e24"))
	for y in 32:
		for x in 32:
			var gx := (x + (8 if (y / 8) % 2 == 1 else 0)) % 16 - 8
			var gy := y % 8 - 4
			if gx * gx + gy * gy * 4 < 7:
				img.set_pixel(x, y, Color("#f1e6d6"))
	img.generate_mipmaps()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.uv1_scale = Vector3(3, 3, 1)
	_mats["yuz_bandana"] = mat
	return mat
