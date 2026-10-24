# Gerçekçi saç ve sakal: oyunlarda kullanılan "saç kartı" yöntemi.
# Kafanın çevresine, tel tel saç dokulu yüzlerce ince şerit dizilir. Doku koddan üretilir (tel çizgileri,
# kökte koyu uçta açık ve saydam). Kafa çerçevesi body.gd ile aynı: yarıçap ~0.115, yüz -z yönüne bakar.
extends RefCounted

const R := 0.118  # kafa yüzeyi (saç kökleri bunun biraz dışında)

static var _strands: ImageTexture
static var _rmap: PackedFloat32Array = PackedFloat32Array()  # gerçek kafa şekli: yön -> yarıçap
const YB := 48
const PB := 24
static var _mats := {}


# Tel dokusu: 256x512, her sütunda farklı kalınlık/parlaklıkta teller, uca doğru incelir ve saydamlaşır.
static func strand_texture() -> ImageTexture:
	if _strands:
		return _strands
	var w := 256
	var h := 512
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 1500:
		var x0 := rng.randf() * w
		var bright := rng.randf_range(0.55, 1.0)
		var len_f := rng.randf_range(0.6, 1.0)
		var wave := rng.randf_range(0.0, 3.0)
		var thick := rng.randf_range(0.9, 2.2)
		for y in int(h * len_f):
			var t := float(y) / (h * len_f)
			var x := x0 + sin(t * 6.0 + wave) * 2.0
			var a := (1.0 - pow(t, 3.0)) * (0.75 + 0.25 * rng.randf())
			var shade := bright * lerpf(0.75, 1.15, t)  # kök koyu, uç açık
			for dx in range(-1, 2):
				var px := int(x) + dx
				if px < 0 or px >= w:
					continue
				var cov := clampf(thick - absf(x - px), 0.0, 1.0) * a
				if cov <= 0.01:
					continue
				var old := img.get_pixel(px, y)
				img.set_pixel(px, y, Color(maxf(old.r, shade), maxf(old.g, shade), maxf(old.b, shade), minf(1.0, old.a + cov)))
	img.generate_mipmaps()
	_strands = ImageTexture.create_from_image(img)
	return _strands


static func material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = strand_texture()
	m.albedo_color = color.lightened(0.08)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.3
	m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.55
	m.metallic_specular = 0.6
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_mats[key] = m
	return m


# Modelin gerçek kafa şeklini ölçer: kafa çerçevesindeki (frame) mesh noktalarını yön kutularına ayırıp
# her yön için en dıştaki noktanın uzaklığını saklar. Bir kez yapılır (tüm karakterler aynı model).
static func fit_head(meshes: Array, frame: Transform3D) -> void:
	if not _rmap.is_empty():
		return
	_rmap.resize(YB * PB)
	_rmap.fill(0.0)
	var inv := frame.affine_inverse()
	for mi in meshes:
		var m: Mesh = (mi as MeshInstance3D).mesh
		var xf := inv * (mi as MeshInstance3D).global_transform
		for si in m.get_surface_count():
			var verts: PackedVector3Array = m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var q := xf * v
				if q.y < -0.16 or q.length() > 0.22:
					continue
				var i := _bin(q)
				_rmap[i] = maxf(_rmap[i], q.length())
	# boş kutuları komşulardan doldur
	for pass_i in 4:
		for pi_ in PB:
			for yi in YB:
				var i := pi_ * YB + yi
				if _rmap[i] > 0.0:
					continue
				var sum := 0.0
				var n := 0
				for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
					var yy: int = (yi + int(d[0]) + YB) % YB
					var pp: int = clampi(pi_ + int(d[1]), 0, PB - 1)
					var vv := _rmap[pp * YB + yy]
					if vv > 0.0:
						sum += vv
						n += 1
				if n > 0:
					_rmap[i] = sum / n


static func _bin(q: Vector3) -> int:
	var yaw := atan2(q.x, -q.z)
	var pitch := asin(clampf(q.y / maxf(q.length(), 0.0001), -1.0, 1.0))
	var yi := clampi(int((yaw + PI) / TAU * YB), 0, YB - 1)
	var pi_ := clampi(int((pitch + PI / 2) / PI * PB), 0, PB - 1)
	return pi_ * YB + yi


# O yöndeki gerçek kafa yüzeyinin uzaklığı (ölçülmediyse küre varsayılır).
static func radius_at(dir: Vector3) -> float:
	if _rmap.is_empty():
		return R
	var v := _rmap[_bin(dir)]
	return v if v > 0.0 else R


# Kafa yüzeyinde bir nokta: yaw (yatay açı, 0 = ön/-z), pitch (0 = ekvator, 90 = tepe); off = deriden uzaklık.
static func scalp(yaw: float, pitch: float, off := 0.004) -> Vector3:
	var d := Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	return d * (radius_at(d) + off)


# Bir saç tutamı: kökten başlayıp yolu izleyen ince şerit (tutam), dışa bakan yüzlü.
static func _strip(st: SurfaceTool, path: PackedVector3Array, width: float, rng: RandomNumberGenerator) -> void:
	var u0 := rng.randf() * 0.7
	var u1 := u0 + 0.3
	var n := path.size()
	for i in n - 1:
		var a := path[i]
		var b := path[i + 1]
		var along := (b - a).normalized()
		var out := ((a + b) * 0.5).normalized()
		var side := along.cross(out).normalized()
		var wa := width * (1.0 - 0.6 * float(i) / (n - 1))
		var wb := width * (1.0 - 0.6 * float(i + 1) / (n - 1))
		var va := float(i) / (n - 1)
		var vb := float(i + 1) / (n - 1)
		var p := [a - side * wa, a + side * wa, b + side * wb, b - side * wb]
		var uv := [Vector2(u0, va), Vector2(u1, va), Vector2(u1, vb), Vector2(u0, vb)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(out)
			st.set_uv(uv[idx])
			st.add_vertex(p[idx])


# Saçın kafa yüzeyini takip ederek, sonra yerçekimiyle aşağı sarkarak uzaması.
static func _grow(root: Vector3, dir: Vector3, length: float, steps: int, droop: float, min_r: float, hug := 0.0) -> PackedVector3Array:
	var pts := PackedVector3Array([root])
	var p := root
	var d := dir.normalized()
	var seg := length / steps
	for i in steps:
		d = (d + Vector3.DOWN * droop).normalized()
		p += d * seg
		# kafayı sarar (hug > 0 ise kafa yüzeyinde kalır), en azından içine girmez
		if hug > 0.0 and p.y > -0.03:
			p = p.normalized() * (radius_at(p) + hug)
			var n := p.normalized()
			d = (d - n * d.dot(n)).normalized()
		elif min_r > 0.0 and p.length() < radius_at(p) + min_r and p.y > -0.12:
			p = p.normalized() * (radius_at(p) + min_r)
		pts.append(p)
	return pts


static func _mesh(parent: Node3D, st: SurfaceTool, color: Color) -> MeshInstance3D:
	st.set_material(material(color))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	parent.add_child(mi)
	return mi


# Saç stili. "kisa": kısa, geriye yatırılmış; "uzun": omuza kadar; "atkuyrugu": arkada toplanmış;
# "mohawk": ortada dik şerit; "kivircik": kısa, dalgalı, hacimli.
static func build_hair(parent: Node3D, style: String, color: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(style)
	var layers: int = {"kisa": 3, "uzun": 3, "atkuyrugu": 3, "mohawk": 2, "kivircik": 4}.get(style, 2)
	for layer in layers:
		var r: float = 0.004 + layer * 0.005  # deriden uzaklık
		var count := 300 if style != "mohawk" else 120
		for k in count:
			var yaw := rng.randf_range(-PI, PI)
			var pitch := rng.randf_range(0.15, 1.45)
			# saç çizgisi: önde kaşların üstünden, yanlarda kulak üstünden başlar
			var front := cos(yaw)  # 1 = ön
			var min_pitch := lerpf(0.1, 0.62, clampf(front, 0.0, 1.0))
			if absf(sin(yaw)) > 0.8:
				min_pitch = maxf(min_pitch, 0.32)
			if pitch < min_pitch:
				continue
			if style == "mohawk" and absf(sin(yaw) * cos(pitch)) > 0.035:
				continue
			var root := scalp(yaw, pitch, r)
			var up := Vector3.UP
			var back := Vector3(0, 0, 1)
			var tangent_back := (back - root.normalized() * root.normalized().dot(back)).normalized()
			var path: PackedVector3Array
			match style:
				"kisa":
					var d := (tangent_back * 0.8 + Vector3.DOWN * 0.3 + Vector3(sin(yaw), 0, 0) * 0.2).normalized()
					path = _grow(root, d, rng.randf_range(0.05, 0.08), 4, 0.05, r, r)
				"uzun":
					var d := (tangent_back * 0.6 + Vector3(sin(yaw), 0, 0) * 0.5 + Vector3.DOWN * 0.3).normalized()
					path = _grow(root, d, rng.randf_range(0.2, 0.3), 8, 0.25, r + 0.006, r)
				"atkuyrugu":
					var knot := Vector3(0, 0.02, R * 1.05)
					var d := (knot - root).normalized()
					path = _grow(root, d, root.distance_to(knot), 5, 0.0, r, r)
				"mohawk":
					path = _grow(root, (root.normalized() + up * 0.3).normalized(), rng.randf_range(0.06, 0.1), 3, -0.05, r)
				"kivircik":
					var d := (root.normalized() * 0.6 + tangent_back * 0.4).normalized()
					var pts := PackedVector3Array([root])
					var p := root
					for i in 5:
						p += d * 0.016 + Vector3(sin(i * 2.1 + k), cos(i * 1.7 + k), 0) * 0.007
						pts.append(p)
					path = pts
				_:
					continue
			_strip(st, path, rng.randf_range(0.018, 0.028) if style != "kivircik" else 0.016, rng)
	if style == "atkuyrugu":
		# arkadan sarkan kuyruk
		for k in 40:
			var start := Vector3(rng.randf_range(-0.015, 0.015), 0.02 + rng.randf_range(-0.01, 0.01), R * 1.05)
			var d := Vector3(rng.randf_range(-0.1, 0.1), -1.0, rng.randf_range(0.2, 0.5)).normalized()
			_strip(st, _grow(start, d, rng.randf_range(0.16, 0.22), 6, 0.2, 0.0), 0.016, rng)
	st.generate_tangents()
	_mesh(parent, st, color)


# Yüzün önünde (x, y) hizasındaki deri noktası.
static func _on_face(x: float, y: float) -> Vector3:
	var d := Vector3(x, y, -0.1).normalized()
	return d * (radius_at(d) + 0.002)


# Sakal: "sakal" = gür sakal, "keci" = keçi sakal, "biyik" = sadece bıyık.
static func build_beard(parent: Node3D, style: String, color: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(style) + 3
	# bıyık: üst dudağın üstü, aşağı ve yanlara
	if style in ["biyik", "keci", "sakal"]:
		for k in 60:
			var x := rng.randf_range(-0.032, 0.032)
			var root := _on_face(x, -0.03 + rng.randf_range(-0.004, 0.004))
			var d := Vector3(x * 6.0, -1.0, -0.15).normalized()
			_strip(st, _grow(root, d, rng.randf_range(0.016, 0.024), 2, 0.0, 0.0), 0.006, rng)
	# keçi: çenenin ortası
	if style in ["keci", "sakal"]:
		for k in 70 if style == "keci" else 30:
			var x := rng.randf_range(-0.022, 0.022)
			var y := rng.randf_range(-0.095, -0.06)
			var root := _on_face(x, y)
			_strip(st, _grow(root, Vector3(x * 4.0, -1.0, -0.3).normalized(), rng.randf_range(0.02, 0.035), 3, 0.0, 0.0), 0.008, rng)
	# gür sakal: yanaklardan çeneye kadar
	if style == "sakal":
		for layer in 2:
			for k in 260:
				var yaw := rng.randf_range(-0.85, 0.85)
				var pitch := rng.randf_range(-0.85, -0.2)
				# ağız açıklığını boş bırak
				if absf(yaw) < 0.32 and pitch > -0.5:
					continue
				var r := 0.002 + layer * 0.004
				var root := scalp(yaw, pitch, r)
				var d := (Vector3.DOWN * 0.9 + root.normalized() * 0.25).normalized()
				_strip(st, _grow(root, d, rng.randf_range(0.009, 0.016), 2, 0.1, 0.0), 0.007, rng)
	st.generate_tangents()
	_mesh(parent, st, color)
