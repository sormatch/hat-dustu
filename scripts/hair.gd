# Gerçekçi saç ve sakal: oyunlarda kullanılan "saç kartı" yöntemi.
# Kafanın çevresine, tel tel saç dokulu yüzlerce ince şerit dizilir. Doku koddan üretilir (tel çizgileri,
# kökte koyu uçta açık ve saydam). Kafa çerçevesi body.gd ile aynı: yarıçap ~0.115, yüz -z yönüne bakar.
extends RefCounted

const R := 0.118  # kafa yüzeyi (saç kökleri bunun biraz dışında)

static var _strands: Texture2D
static var _rmap: PackedFloat32Array = PackedFloat32Array()  # gerçek kafa şekli: yön -> yarıçap
const YB := 48
const PB := 24
static var _mats := {}
static var _head_min := Vector3(-0.1, -0.03, -0.12)  # kafa derisi kutusu (kafa çerçevesinde), fit_head ölçer
static var _head_max := Vector3(0.1, 0.13, 0.1)
static var _real_mats := {}
static var _gray_cache := {}
# Saç dokularının ortak ortalama parlaklığı (sRGB, Quaternius T_Hair_1/2 ortalaması ~0,54) ve saç rengi çarpanı:
# MakeHuman (gri/), Quaternius ve tutam malzemeleri aynı ortalama tona çıksın (aynı renk her stilde aynı görünsün).
const GRI_HEDEF := 0.54
const IKI_YUZLU := ["afro01"]  # arka yüzü de çizilen MakeHuman saçları (real_material)
static var _face_tris: PackedVector3Array = PackedVector3Array()  # kafa çerçevesinde: köşe, normal, köşe, normal...
# MakeHuman temel modelinin kafa derisi kutusu (metre, yüz +z): genişlik, tepe, ön-arka
const MH_HEAD_MIN := Vector3(-0.088, 0.648, -0.039)
const MH_HEAD_MAX := Vector3(0.080, 0.849, 0.153)
# oyundaki saç stili -> MakeHuman (CC0) saç modeli
const REAL_STYLES := {"kisa": "short02", "asker": "short04", "uzun": "long01", "atkuyrugu": "ponytail01", "kivircik": "afro01", "dalgali": "short01", "yandan": "short03", "kut": "bob02", "orgu": "braid01"}
# Quaternius Universal Base Characters (CC0) saçları: stil -> [dosya, hangi kafaya göre yapıldığı]
const UBC_DIR := "res://assets/govde/sac/"
const UBC_STYLES := {
	"uzun_duz": ["Hair_Long", "kadin"], "topuz": ["Hair_Buns", "kadin"], "ayrik": ["Hair_SimpleParted", "erkek"],
	"kazi": ["Hair_Buzzed", "erkek"], "kazi_k": ["Hair_BuzzedFemale", "kadin"],
}
# Gerçek saç modelinin üstüne koddan eklenen parçalar (örgü, kuyruk, rasta): stil -> [taban saç, ek]
const COMBO_STYLES := {
	"ikiz_orgu": ["kazi_k", "ikiz_orgu"], "yuksek_kuyruk": ["kazi_k", "yuksek_kuyruk"], "rasta": ["kazi", "rasta"],
	"cift_topuz": ["kazi_k", "cift_topuz"], "yan_orgu": ["kazi_k", "yan_orgu"], "mohawk": ["kazi", "mohawk"], "orgu": ["kazi_k", "orgu_tek"],
}
# Gövde başına ölçülen kafa şekilleri (gövde kimliği -> rmap, kutu, yüz üçgenleri, kafa çerçevesi)
static var _profiles := {}
static var _frame_model := Transform3D()  # seçili gövdenin kafa çerçevesi (model uzayında)


# Tel dokusu: 256x512, her sütunda farklı kalınlık/parlaklıkta teller, uca doğru incelir ve saydamlaşır.
# Pakette pişirilmiş hali var (tools/doku_pisir.gd): GDScript ile üretmek telefonda saniyeler sürüyordu.
static func strand_texture() -> Texture2D:
	if _strands:
		return _strands
	const PISMIS := "res://assets/pisir/sac_tel.png"
	if ResourceLoader.exists(PISMIS):
		_strands = load(PISMIS)
	else:
		_strands = ImageTexture.create_from_image(strand_uret())
	return _strands


static func strand_uret() -> Image:
	var w := 256
	var h := 512
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	# siyah-saydam zemin: teller max() ile üst üste biner (eskiden beyaz zemin yüzünden max hep 1 çıkıyor,
	# kök-uç gölgesi ve tel parlaklığı kayboluyor, doku düz beyaz kalıyordu)
	img.fill(Color(0, 0, 0, 0))
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
	return img


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


# Modelin gerçek kafa şeklini ölçer: kafa çerçevesindeki mesh noktalarını yön kutularına ayırıp her yön için
# en dıştaki noktanın uzaklığını saklar. Gövde başına bir kez yapılır (key = gövde kimliği), sonra seçilir.
# items: [[Mesh, Transform3D (mesh uzayı -> kafa çerçevesi)], ...]; frame_model: kafa çerçevesi model uzayında.
static func fit_head(items: Array, key: String, frame_model := Transform3D(), select := true) -> void:
	if _profiles.has(key):
		if select:
			use(key)
		return
	var rmap := PackedFloat32Array()
	rmap.resize(YB * PB)
	rmap.fill(0.0)
	var hmin := Vector3(-0.1, -0.03, -0.12)
	var hmax := Vector3(0.1, 0.13, 0.1)
	var face := PackedVector3Array()
	var found := false
	for it in items:
		var m: Mesh = it[0]
		var xf: Transform3D = it[1]
		var nb := xf.basis.inverse().transposed()
		for si in m.get_surface_count():
			var arr := m.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			for t in range(0, idx.size(), 3):
				var a := xf * verts[idx[t]]
				var c := (a + xf * verts[idx[t + 1]] + xf * verts[idx[t + 2]]) / 3.0
				if c.y > -0.15 and c.y < 0.0 and c.z < 0.02 and c.length() < 0.2:
					for k in 3:
						face.append(xf * verts[idx[t + k]])
						face.append((nb * norms[idx[t + k]]).normalized())
			for v in verts:
				var q := xf * v
				if q.y < -0.16 or q.length() > 0.22:
					continue
				var i := _bin(q)
				rmap[i] = maxf(rmap[i], q.length())
				if q.y > -0.03:
					hmin = hmin.min(q) if found else q
					hmax = hmax.max(q) if found else q
					found = true
	# boş kutuları komşulardan doldur
	for pass_i in 4:
		for pi_ in PB:
			for yi in YB:
				var i := pi_ * YB + yi
				if rmap[i] > 0.0:
					continue
				var sum := 0.0
				var n := 0
				for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
					var yy: int = (yi + int(d[0]) + YB) % YB
					var pp: int = clampi(pi_ + int(d[1]), 0, PB - 1)
					var vv := rmap[pp * YB + yy]
					if vv > 0.0:
						sum += vv
						n += 1
				if n > 0:
					rmap[i] = sum / n
	_profiles[key] = {"rmap": rmap, "min": hmin, "max": hmax, "face": face, "frame": frame_model}
	if select:
		use(key)


# Ölçülmüş bir gövdenin kafa şeklini seçer (saç/şapka/sakal bununla kurulur).
static func use(key: String) -> bool:
	if not _profiles.has(key):
		return false
	var p: Dictionary = _profiles[key]
	_rmap = p.rmap
	_head_min = p.min
	_head_max = p.max
	_face_tris = p.face
	_frame_model = p.frame
	return true


static func has_profile(key: String) -> bool:
	return _profiles.has(key)


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


# Gerçek saç modeli (MakeHuman CC0): kafa derisi kutusu bizim karakterin kafasına hizalanır.
# Model yüzü +z'ye bakar, bizde yüz -z: y ekseninde 180° çevrilir. Tepe tepeye, orta ortaya oturur.
static func _build_mh(parent: Node3D, style: String, color: Color) -> bool:
	if not REAL_STYLES.has(style):
		return false
	var file: String = REAL_STYLES[style]
	var mesh_path := "res://assets/sac/%s.obj" % file
	if not ResourceLoader.exists(mesh_path):
		return false
	var mi := MeshInstance3D.new()
	mi.mesh = load(mesh_path)
	mi.material_override = real_material(file, color)
	var mh_size := MH_HEAD_MAX - MH_HEAD_MIN
	var our_size := _head_max - _head_min
	# genişlik ve derinlik kafaya göre; yükseklik kafa boyuna göre (çerçeve kafa boyuyla ölçekli olduğundan
	# geniş kafalarda saç aşağı uzayıp gözleri kapatmasın)
	var basis := Basis(Vector3.UP, PI) * Basis.from_scale(Vector3(our_size.x / mh_size.x * 1.04, 1.12 * our_size.y / 0.156, our_size.z / mh_size.z * 1.04))
	var mh_anchor := Vector3((MH_HEAD_MIN.x + MH_HEAD_MAX.x) * 0.5, MH_HEAD_MAX.y, (MH_HEAD_MIN.z + MH_HEAD_MAX.z) * 0.5)
	var our_anchor := Vector3((_head_min.x + _head_max.x) * 0.5, _head_max.y + 0.004, (_head_min.z + _head_max.z) * 0.5)
	mi.transform = Transform3D(basis, our_anchor - basis * mh_anchor)
	parent.add_child(mi)
	return true


static func real_material(file: String, color: Color) -> StandardMaterial3D:
	var key := file + color.to_html()
	if _real_mats.has(key):
		return _real_mats[key]
	var m := StandardMaterial3D.new()
	# önceden griye çevrilmiş, sıkıştırılmış doku (tools/sac_gri.gd); yoksa eski yol: çalışırken çevir
	var baked := "res://assets/sac/gri/%s.png" % file
	m.albedo_texture = load(baked) if ResourceLoader.exists(baked) else _gray("res://assets/sac/%s.webp" % file)
	# gri dokular Quaternius saç dokularıyla aynı ortalama parlaklıkta (gri_veri): çarpan da ubc_material ile aynı
	m.albedo_color = Color(color.r * 1.5 + 0.02, color.g * 1.5 + 0.02, color.b * 1.5 + 0.02)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	# arka yüzler çizilmez: saç kabuğunun iç yüzü (kendi gölgesinde, koyu) yarı saydam kenarlardan görünüp açık
	# renklerde (sarı, gri, pembe) tepede koyu lekeler yapıyordu. Kıvırcık (afro01) iç içe ince kabuklardan oluşuyor,
	# iç yüzler olmadan aralarından kafa görünür: onda iki yüzlü kalır.
	m.cull_mode = BaseMaterial3D.CULL_DISABLED if file in IKI_YUZLU else BaseMaterial3D.CULL_BACK
	m.roughness = 0.6
	m.metallic_specular = 0.55
	_real_mats[key] = m
	return m



static func _gray(path: String) -> Texture2D:
	if _gray_cache.has(path):
		return _gray_cache[path]
	var img: Image = (load(path) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img = Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, gri_veri(img.get_data()))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_gray_cache[path] = t
	return t


# Saç dokusunun gri tonlu hali (RGBA8 verisi): parlaklık, saydamlık ağırlıklı ortalaması GRI_HEDEF olacak şekilde
# üs (gamma) ile çekilir; açık-koyu sırası ve 0..1 aralığı korunur, kırpma olmaz. Kaynak dokular çok farklı
# (afro01 ortalama ~0,06 neredeyse siyah, long01 ~0,2, short02 ~0,39): eskiden sabit x1,6 ile çevrildiği için
# aynı saç rengi stile göre başka tonda görünüyor, kıvırcık her renkte siyah kalıyordu. tools/sac_gri.gd de bunu kullanır.
static func gri_veri(data: PackedByteArray) -> PackedByteArray:
	var hist := PackedFloat64Array()
	hist.resize(256)
	var out := data.duplicate()
	for i in range(0, data.size(), 4):
		var l := clampi(int(data[i] * 0.3 + data[i + 1] * 0.59 + data[i + 2] * 0.11), 0, 255)
		out[i] = l
		if data[i + 3] > 76:
			hist[l] += data[i + 3]
	var g := _gri_us(hist)
	var lut := PackedByteArray()
	lut.resize(256)
	for v in 256:
		lut[v] = clampi(int(round(pow(v / 255.0, g) * 255.0)), 0, 255)
	for i in range(0, out.size(), 4):
		var l := lut[out[i]]
		out[i] = l
		out[i + 1] = l
		out[i + 2] = l
	return out


# Ortalaması GRI_HEDEF olan üs (ikiye bölme): ort(x^g) g büyüdükçe küçülür.
static func _gri_us(hist: PackedFloat64Array) -> float:
	var total := 0.0
	for v in 256:
		total += hist[v]
	if total <= 0.0:
		return 1.0
	var lo := 0.02
	var hi := 4.0
	for it in 40:
		var g := (lo + hi) * 0.5
		var m := 0.0
		for v in 256:
			m += hist[v] * pow(v / 255.0, g)
		if m / total > GRI_HEDEF:
			lo = g
		else:
			hi = g
	return (lo + hi) * 0.5


# ---------- saç: gerçek modeller + koddan eklenen parçalar ----------

# Saç stilini kurar: koddan eklemeli stiller (örgü, kuyruk...), Quaternius saçları ya da MakeHuman saçları.
static func build_real(parent: Node3D, style: String, color: Color) -> bool:
	if COMBO_STYLES.has(style):
		var c: Array = COMBO_STYLES[style]
		build_real(parent, c[0], color)
		build_extra(parent, c[1], color)
		return true
	if UBC_STYLES.has(style):
		var u: Array = UBC_STYLES[style]
		return build_ubc(parent, u[0], u[1], color)
	return _build_mh(parent, style, color)


# Quaternius saçı (CC0): yapıldığı kafanın (author) çerçevesinden bizim kafaya taşınır; kafa farklıysa
# kafa derisi kutusuna göre ölçeklenir (tepe tepeye, orta ortaya).
static func build_ubc(parent: Node3D, file: String, author: String, color: Color) -> bool:
	var path := UBC_DIR + file + ".gltf"
	if not ResourceLoader.exists(path) or not _profiles.has(author):
		return false
	var a: Dictionary = _profiles[author]
	var sc: Node = load(path).instantiate()
	var src: MeshInstance3D = sc.find_children("*", "MeshInstance3D", true, false)[0]
	var model_xf := Transform3D.IDENTITY
	var n: Node = src
	while n and n != sc:
		if n is Node3D:
			model_xf = (n as Node3D).transform * model_xf
		n = n.get_parent()
	var in_author: Transform3D = (a.frame as Transform3D).affine_inverse() * model_xf
	var mi := MeshInstance3D.new()
	mi.mesh = src.mesh
	mi.material_override = ubc_material(file, color)
	mi.transform = _box_map(a.min, a.max) * in_author
	sc.free()
	parent.add_child(mi)
	return true


# Başka bir kafanın kutusundan (amin, amax) seçili kafanın kutusuna taşıyan dönüşüm.
static func _box_map(amin: Vector3, amax: Vector3) -> Transform3D:
	var asz := amax - amin
	var osz := _head_max - _head_min
	var s := (osz.x / asz.x + osz.z / asz.z) * 0.5
	var aa := Vector3((amin.x + amax.x) * 0.5, amax.y, (amin.z + amax.z) * 0.5)
	var oa := Vector3((_head_min.x + _head_max.x) * 0.5, _head_max.y, (_head_min.z + _head_max.z) * 0.5)
	return Transform3D(Basis().scaled(Vector3.ONE * s), oa - aa * s)


const UBC_TEX := {"Hair_Long": "T_Hair_2", "Hair_Buns": "T_Hair_2", "Eyebrows_Female": "T_Hair_2"}


static func ubc_material(file: String, color: Color) -> StandardMaterial3D:
	var t: String = UBC_TEX.get(file, "T_Hair_1")
	var key := "ubc/" + t + color.to_html()
	if _real_mats.has(key):
		return _real_mats[key]
	var m := StandardMaterial3D.new()
	# doku zaten gri tonlu: telefonda piksel piksel çevirmeye gerek yok, doğrudan saç rengiyle çarpılır
	m.albedo_texture = load(UBC_DIR + t + "_BaseColor.png")
	m.albedo_color = Color(color.r * 1.5 + 0.02, color.g * 1.5 + 0.02, color.b * 1.5 + 0.02)
	m.normal_enabled = true
	m.normal_texture = load(UBC_DIR + t + "_Normal.png")
	m.roughness = 0.5
	m.metallic_specular = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_real_mats[key] = m
	return m


# Kaş malzemesi (gövde modelindeki kaş meshi için): saç rengine boyanır.
static func brow_material(tex_path: String, color: Color) -> StandardMaterial3D:
	var key := "kas/" + tex_path + color.to_html()
	if _real_mats.has(key):
		return _real_mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(tex_path)
	m.albedo_color = Color(color.r * 1.4 + 0.03, color.g * 1.4 + 0.03, color.b * 1.4 + 0.03)
	m.roughness = 0.7
	_real_mats[key] = m
	return m


static var _lock_tex: ImageTexture

# Tutam dokusu: dolu (saydamlıksız), boyuna ince tel çizgileri; örgü ve rasta tüpleri için.
static func lock_texture() -> ImageTexture:
	if _lock_tex:
		return _lock_tex
	var w := 64
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var cols := PackedFloat32Array()
	cols.resize(w)
	for x in w:
		cols[x] = rng.randf_range(0.55, 1.0)
	for i in 3:  # yumuşat
		var nc := cols.duplicate()
		for x in w:
			nc[x] = (cols[(x + w - 1) % w] + cols[x] * 2.0 + cols[(x + 1) % w]) / 4.0
		cols = nc
	for y in h:
		for x in w:
			var v := cols[(x + int(sin(y * 0.09 + x) * 1.5) + w) % w] * (0.9 + 0.1 * sin(y * 0.6 + x * 3.0))
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	_lock_tex = ImageTexture.create_from_image(img)
	return _lock_tex


static func lock_material(color: Color) -> StandardMaterial3D:
	var key := "tutam/" + color.to_html()
	if _real_mats.has(key):
		return _real_mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = lock_texture()
	m.albedo_color = Color(color.r * 1.15 + 0.02, color.g * 1.15 + 0.02, color.b * 1.15 + 0.02)
	m.roughness = 0.55
	m.metallic_specular = 0.6
	_real_mats[key] = m
	return m


# Bir yol boyunca tüp (tutam/örgü teli); radii her noktadaki yarıçap.
static func _tube(st: SurfaceTool, path: PackedVector3Array, radii: PackedFloat32Array, sides := 8, twist := 0.0) -> void:
	var n := path.size()
	if n < 2:
		return
	var rings: Array = []
	var prev_side := Vector3.ZERO
	var vlen := 0.0
	for i in n:
		var t := (path[mini(i + 1, n - 1)] - path[maxi(i - 1, 0)]).normalized()
		var side := prev_side
		if side == Vector3.ZERO or absf(side.dot(t)) > 0.95:
			side = t.cross(Vector3.UP if absf(t.y) < 0.9 else Vector3.RIGHT).normalized()
		side = (side - t * side.dot(t)).normalized()
		prev_side = side
		var up := t.cross(side).normalized()
		if i > 0:
			vlen += path[i].distance_to(path[i - 1])
		var ring := []
		for k in sides + 1:
			var a := TAU * k / sides + twist * i
			var d := side * cos(a) + up * sin(a)
			ring.append([path[i] + d * radii[i], d, Vector2(float(k) / sides * 2.0, vlen * 14.0)])
		rings.append(ring)
	for i in n - 1:
		for k in sides:
			# Godot'da ön yüz saat yönünde sarılır: ters sarılırsa arka yüz silinir, tüpün İÇ duvarı görünür
			# (saç rengi koyu ve ters ışıklı, karakter dönünce "kayan" lekeler: örgü, rasta, mohawk, pala uçları)
			var q: Array = [rings[i][k], rings[i][k + 1], rings[i + 1][k + 1], rings[i + 1][k]]
			for j in [0, 2, 1, 0, 3, 2]:
				st.set_normal(q[j][1])
				st.set_uv(q[j][2])
				st.add_vertex(q[j][0])


# Kafa yüzeyinden başlayıp aşağı sarkan yol: kafanın içine girmez, yerçekimiyle düşer.
static func _hang(root: Vector3, dir: Vector3, length: float, steps: int, off: float) -> PackedVector3Array:
	var pts := PackedVector3Array([root])
	var p := root
	var d := dir.normalized()
	var seg := length / steps
	for i in steps:
		d = (d + Vector3.DOWN * 0.35).normalized()
		p += d * seg
		if p.y > -0.2:
			var r := radius_at(p) + off
			if p.length() < r:
				p = p.normalized() * r
		pts.append(p)
	return pts


# Üç telli örgü: merkez yolu boyunca birbirinin üstünden geçen üç tüp. Ucun konumunu döndürür.
static func _braid(st: SurfaceTool, center: PackedVector3Array, width: float) -> Vector3:
	var n := center.size()
	var dense := PackedVector3Array()
	for i in n - 1:
		for s in 4:
			dense.append(center[i].lerp(center[i + 1], s / 4.0))
	dense.append(center[n - 1])
	var m := dense.size()
	for k in 3:
		var path := PackedVector3Array()
		var radii := PackedFloat32Array()
		var prev := Vector3.ZERO
		for i in m:
			var t := (dense[mini(i + 1, m - 1)] - dense[maxi(i - 1, 0)]).normalized()
			var side := t.cross(Vector3.BACK if absf(t.z) < 0.9 else Vector3.RIGHT).normalized()
			if prev != Vector3.ZERO and side.dot(prev) < 0.0:
				side = -side
			prev = side
			var nrm := t.cross(side).normalized()
			var f := float(i) / (m - 1)
			var taper := lerpf(1.0, 0.55, f)
			var ph := i * 0.55 + TAU * k / 3.0
			path.append(dense[i] + side * sin(ph) * width * 0.55 * taper + nrm * sin(ph * 2.0) * width * 0.18 * taper)
			radii.append(width * 0.42 * taper)
		_tube(st, path, radii, 7)
	return dense[m - 1]


# Koddan eklenen saç parçaları; taban saç modelinin üstüne kurulur.
static var _extra_cache := {}


# Koddan üretilen yoğun saç ağlarına (rasta ~11 bin üçgen) ayrıntı seviyeleri: uzaktan daha az üçgen,
# yakından aynı ağ. Üretilemezse (LOD aracı yoksa) ağ olduğu gibi kalır.
static func _with_lods(mesh: ArrayMesh) -> ArrayMesh:
	if mesh == null or mesh.get_surface_count() != 1 or mesh.surface_get_array_index_len(0) < 3000 * 3:
		return mesh
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(0))
	im.generate_lods(25.0, 60.0, [])
	if im.get_surface_lod_count(0) == 0:
		return mesh
	return im.get_mesh()


static func build_extra(parent: Node3D, kind: String, color: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var used := false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var ties: Array = []  # [konum, yön, yarıçap]
	# aynı stil + aynı kafa şekli: ağ bir kez üretilir (rasta ~95 tüp, her karakterde yeniden kurulmasın)
	var key := "%s|%s|%s" % [kind, _head_min, _head_max]
	var mesh: Mesh = null
	if _extra_cache.has(key):
		mesh = _extra_cache[key][0]
		ties = _extra_cache[key][1]
		used = mesh != null
	else:
		match kind:
			"ikiz_orgu", "yan_orgu", "orgu_tek":
				var sides: Array = [-1.0, 1.0] if kind == "ikiz_orgu" else [1.0]
				for s in sides:
					var yaw: float = PI if kind == "orgu_tek" else s * deg_to_rad(108.0)
					var root := scalp(yaw, deg_to_rad(-8.0), 0.012)
					var c := PackedVector3Array([root])
					var p := root
					var out := Vector3(s * 0.25, 0, 0.35 if kind == "ikiz_orgu" else -0.25)
					if kind == "orgu_tek":
						out = Vector3(0, 0, 0.5)
					for i in 9:
						p += (Vector3.DOWN + out * (0.6 if i < 3 else 0.15)).normalized() * 0.034
						var r := radius_at(p) + 0.016
						if p.y > -0.25 and p.length() < r:
							p = p.normalized() * r
						c.append(p)
					var end := _braid(st, c, 0.034)
					ties.append([end, Vector3.DOWN, 0.012])
					for k in 7:  # uçtaki püskül
						var a := TAU * k / 7.0
						var off := Vector3(cos(a), 0, sin(a)) * 0.006
						_tube(st, PackedVector3Array([end + off, end + off * 2.2 + Vector3.DOWN * 0.035]), PackedFloat32Array([0.005, 0.0015]), 5)
				used = true
			"yuksek_kuyruk":
				# tepede toplanan kalın kuyruk: ortada kalın bir tutam, çevresinde ince tutamlar; önce yukarı-geri, sonra sırta düşer
				var knot := scalp(PI, deg_to_rad(48.0), 0.012)
				var out := knot.normalized()
				ties.append([knot + out * 0.006, out, 0.024])
				var center := PackedVector3Array([knot])
				var p := knot
				var d := (out + Vector3.UP * 0.5).normalized()
				for i in 12:
					d = (d + Vector3.DOWN * 0.28 + Vector3.BACK * 0.04).normalized()
					p += d * 0.03
					var r := radius_at(p) + 0.03
					if p.y > -0.3 and p.length() < r:
						p = p.normalized() * r
					center.append(p)
				for k in 26:
					var a := TAU * k / 26.0
					var ring := 0.0 if k == 0 else (0.008 if k < 9 else 0.016)
					var off := Vector3(cos(a), sin(a) * 0.7, 0) * ring
					var path := PackedVector3Array()
					var radii := PackedFloat32Array()
					var cut := rng.randi_range(9, 12)
					for i in cut + 1:
						var f := float(i) / cut
						path.append(center[i] + off * (1.0 + f * 0.8) + Vector3(sin(i * 0.9 + k) * 0.004, 0, cos(i * 0.7 + k) * 0.004))
						radii.append(lerpf(0.022 if k == 0 else 0.012, 0.002, pow(f, 1.4)))
					_tube(st, path, radii, 7, 0.2)
				used = true
			"cift_topuz":
				for s in [-1.0, 1.0]:
					var base := scalp(s * deg_to_rad(118.0), deg_to_rad(56.0), 0.0)
					var axis := base.normalized()
					var side := axis.cross(Vector3.FORWARD).normalized()
					var up := axis.cross(side).normalized()
					var coil := PackedVector3Array()
					var radii := PackedFloat32Array()
					for i in 60:
						var f := float(i) / 59.0
						var a := f * TAU * 3.6
						var rr := 0.046 * sin(f * PI * 0.94 + 0.1)
						coil.append(base + axis * (0.008 + f * 0.07) + (side * cos(a) + up * sin(a)) * rr)
						radii.append(lerpf(0.022, 0.012, f))
					_tube(st, coil, radii, 8, 0.3)
					ties.append([base + axis * 0.01, axis, 0.034])
				used = true
			"rasta":
				for k in 95:
					var yaw := rng.randf_range(-PI, PI)
					var pitch := rng.randf_range(0.0, 1.45)
					if cos(yaw) > 0.5 and pitch < 0.8:
						continue  # yüzün önüne düşmesin
					var root := scalp(yaw, pitch, 0.01)
					var tb := (Vector3(0, 0, 1) - root.normalized() * root.normalized().z).normalized()
					var d := (tb * 0.45 + Vector3(sin(yaw), 0, 0) * 0.5 + Vector3.DOWN * 0.2).normalized()
					var path := _hang(root, d, rng.randf_range(0.22, 0.34), 11, 0.02)
					var radii := PackedFloat32Array()
					for i in path.size():
						var f := float(i) / (path.size() - 1)
						radii.append(0.0125 * (1.0 - f * 0.3) * (0.85 + 0.25 * sin(i * 2.3 + k)))
					_tube(st, path, radii, 6, 0.5)
				used = true
			"mohawk":
				# ortada sıra sıra dik, sivri tutamlar (kazıma tabanın üstünde)
				for row in [-1.0, 1.0]:
					for k in 13:
						var f := k / 12.0
						var yaw := 0.0 if f < 0.5 else PI
						var pitch := lerpf(0.75, PI / 2, f * 2.0) if f < 0.5 else lerpf(PI / 2, 0.35, (f - 0.5) * 2.0)
						var root := scalp(yaw, pitch, 0.004) + Vector3(row * 0.008, 0, 0)
						var n := root.normalized()
						var tilt := Vector3.BACK * 0.35 + Vector3(row * 0.12, 0, 0)
						var len := 0.07 + 0.03 * sin(f * PI)
						var path := PackedVector3Array()
						var radii := PackedFloat32Array()
						for i in 6:
							var t := i / 5.0
							path.append(root + (n + tilt * t).normalized() * len * t)
							radii.append(lerpf(0.016, 0.0015, t))
						_tube(st, path, radii, 6)
				used = true
		if used:
			st.index()  # aynı köşeler birleşir (görüntü aynı), LOD üretimi sıralı ağ ister
			mesh = _with_lods(st.commit())
		_extra_cache[key] = [mesh, ties]
	if used:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = lock_material(color)
		parent.add_child(mi)
	for t in ties:
		var ring := TorusMesh.new()
		ring.inner_radius = float(t[2]) * 0.7
		ring.outer_radius = float(t[2])
		ring.rings = 12
		ring.ring_segments = 8
		var tm := MeshInstance3D.new()
		tm.mesh = ring
		tm.material_override = _tie_material()
		var y: Vector3 = (t[1] as Vector3).normalized()
		var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
		tm.transform = Transform3D(Basis(x, y, x.cross(y)), t[0])
		parent.add_child(tm)


static func _tie_material() -> StandardMaterial3D:
	if _real_mats.has("lastik"):
		return _real_mats["lastik"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#c2185b")
	m.roughness = 0.45
	_real_mats["lastik"] = m
	return m


# ---------- sakal ----------

# Kabuk sakallar: [katman, uzunluk, en dış katmanın saydamlık eşiği] — eşik büyüdükçe seyrek (kirli sakal)
const BEARD_SHELL := {
	"biyik": [4, 0.005, 0.75], "keci": [4, 0.005, 0.75], "sakal": [6, 0.009, 0.75], "kirli": [2, 0.0018, 0.9],
	"ince": [3, 0.003, 0.7], "pala": [5, 0.007, 0.72], "zincir": [4, 0.005, 0.75], "favori": [4, 0.005, 0.75],
	"uzun": [6, 0.01, 0.72],
}


# Sakal stilleri: Quaternius sakal modelinden (CC0) bölge bölge kesilir (bıyık, keçi, çene, favori...);
# uzun/dolgun sakalda çene kısmı aşağı uzatılır. Kirli sakal: CC0 kafalarda yüz dokusundaki boyalı sakal,
# başka kafalarda seyrek kürk katmanları.
static func build_beard_any(parent: Node3D, style: String, color: Color, painted_stubble := false) -> void:
	if style == "kirli":
		if not painted_stubble:
			build_beard_shells(parent, "kirli", color)
		return
	if not _build_beard_cut(parent, style, color):
		build_beard_shells(parent, style, color)
	if style == "pala":
		# pala bıyık: bıyığın uçlarından çene hizasına inen kalın, kıvrık uçlar
		var ends: Array = _beard_cache.get("pala_uc", [])
		if ends.is_empty():
			return
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for e in ends:
			var p0: Vector3 = e
			var s := signf(p0.x)
			var path := PackedVector3Array()
			var radii := PackedFloat32Array()
			for i in 8:
				var f := i / 7.0
				path.append(p0 + Vector3(s * f * 0.012, -f * 0.045, -f * 0.004 + sin(f * PI) * -0.004))
				radii.append(lerpf(0.0075, 0.0025, f))
			_tube(st, path, radii, 7)
		_beard_mesh(parent, st, color)


static var _beard_cache := {}
# Sakal modelinin bölgeleri (erkek modelinin uzayında, metre; yüz +z): ağız hizası ve sakal sınırları
const BEARD_MOUTH_Y := 1.62
const BEARD_TOP_Y := 1.689
const BEARD_BOTTOM_Y := 1.5495


static func _beard_keep(style: String, c: Vector3) -> bool:
	var ax := absf(c.x)
	var moust := c.y > BEARD_MOUTH_Y + 0.003 and c.y < BEARD_MOUTH_Y + 0.04 and ax < 0.042 and c.z > 0.055
	match style:
		"biyik", "pala":
			return moust
		"ince":
			return moust and c.y < BEARD_MOUTH_Y + 0.022 and ax < 0.034
		"keci":
			return moust or (ax < 0.03 and c.y < BEARD_MOUTH_Y - 0.004 and c.z > 0.03)
		"zincir":
			return not moust and (ax > 0.045 or c.y < BEARD_BOTTOM_Y + 0.035) and c.y < BEARD_TOP_Y - 0.01
		"favori":
			return ax > 0.058 and c.y > BEARD_MOUTH_Y + 0.008
		"sakal", "dolgun", "uzun":
			return true
	return false


# Sakal modelini stile göre keser ve kafaya takar; gerçek model bulunamazsa false.
static func _build_beard_cut(parent: Node3D, style: String, color: Color) -> bool:
	var path := UBC_DIR + "Hair_Beard.gltf"
	if not ResourceLoader.exists(path) or not _profiles.has("erkek"):
		return false
	if not _beard_cache.has("arr"):
		var sc: Node = load(path).instantiate()
		var src: MeshInstance3D = sc.find_children("*", "MeshInstance3D", true, false)[0]
		_beard_cache.arr = src.mesh.surface_get_arrays(0)
		_beard_cache.xf = src.transform
		sc.free()
	var arr: Array = (_beard_cache.arr as Array).duplicate()
	var xf: Transform3D = _beard_cache.xf
	var verts: PackedVector3Array = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	for i in verts.size():
		verts[i] = xf * verts[i]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var nidx := PackedInt32Array()
	var ends := [Vector3(0, 0, 0), Vector3(0, 0, 0)]
	for t in range(0, idx.size(), 3):
		var c := (verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0
		if _beard_keep(style, c):
			nidx.append_array([idx[t], idx[t + 1], idx[t + 2]])
			if style == "pala":
				for k in 3:
					var v := verts[idx[t + k]]
					if v.x < ends[0].x:
						ends[0] = v
					if v.x > ends[1].x:
						ends[1] = v
	if nidx.is_empty():
		return false
	# uzun / dolgun: çene altı aşağı ve öne doğru uzar
	var stretch: float = {"uzun": 1.6, "dolgun": 0.45}.get(style, 0.0)
	var puff: float = {"dolgun": 1.08, "uzun": 1.04}.get(style, 1.0)
	var mid := Vector3(0, BEARD_MOUTH_Y + 0.02, -0.02)
	for i in verts.size():
		var v := verts[i]
		if stretch > 0.0 and v.y < BEARD_MOUTH_Y - 0.005:
			var d := BEARD_MOUTH_Y - 0.005 - v.y
			v.y -= d * stretch * clampf(1.0 - absf(v.x) / 0.08, 0.2, 1.0)
			v.z += d * stretch * 0.25
		if puff != 1.0:
			v = mid + (v - mid) * puff
		verts[i] = v
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = nidx
	if arr[Mesh.ARRAY_NORMAL] != null:
		var nb := xf.basis.inverse().transposed()
		var ns: PackedVector3Array = (arr[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate()
		for i in ns.size():
			ns[i] = (nb * ns[i]).normalized()
		arr[Mesh.ARRAY_NORMAL] = ns
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var a: Dictionary = _profiles["erkek"]
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = ubc_material("Hair_Beard", color.darkened(0.05))
	mi.transform = _box_map(a.min, a.max) * (a.frame as Transform3D).affine_inverse()
	parent.add_child(mi)
	if style == "pala":
		var to_head := mi.transform
		_beard_cache.pala_uc = [to_head * ends[0], to_head * ends[1]]
	return true


static func _beard_mesh(parent: Node3D, st: SurfaceTool, color: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = lock_material(color.darkened(0.12))
	parent.add_child(mi)


# Sakal: yüz yüzeyinin kopyası, milimetrik aralıklarla dışa açılmış kürk katmanları (tel dokulu).
# Bölge stile göre seçilir; dudaklar boş kalır.
static func build_beard_shells(parent: Node3D, style: String, color: Color) -> void:
	if _face_tris.is_empty():
		return
	var spec: Array = BEARD_SHELL.get(style, [4, 0.005, 0.75])
	var layers: int = spec[0]
	var reach: float = spec[1]
	for L in layers:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var off := 0.0012 + reach * float(L) / layers
		var any := false
		for t in range(0, _face_tris.size(), 6):
			var c := (_face_tris[t] + _face_tris[t + 2] + _face_tris[t + 4]) / 3.0
			if not _in_beard(style, c):
				continue
			any = true
			for k in 3:
				var p := _face_tris[t + k * 2]
				var n := _face_tris[t + k * 2 + 1]
				st.set_normal(n)
				st.set_uv(Vector2(p.x * 9.0 + 0.5, -p.y * 6.0 + p.z * 2.0))
				st.add_vertex(p + n * off + Vector3.DOWN * off * 0.6)
		if not any:
			return
		var m := StandardMaterial3D.new()
		m.albedo_texture = strand_texture()
		m.albedo_color = color.darkened(0.15)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = lerpf(0.25, float(spec[2]), float(L) / maxf(1.0, layers - 1))
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.7
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = m
		parent.add_child(mi)


# Kafa çerçevesinde yüz bölgeleri: x yanlara, y yukarı (ağız ~ -0.05), -z ön.
static func _in_beard(style: String, c: Vector3) -> bool:
	var lips := absf(c.x) < 0.026 and c.y > -0.062 and c.y < -0.04
	if lips:
		return false
	var moust := absf(c.x) < 0.034 and c.y > -0.042 and c.y < -0.026 and c.z < -0.06
	var full := c.y < -0.03 and c.y > -0.13 and c.z < 0.0
	var jaw := full and (c.y < -0.095 or absf(c.x) > 0.052)
	var burns := absf(c.x) > 0.058 and c.y > -0.07 and c.y < 0.02 and c.z < 0.025 and c.z > -0.05
	match style:
		"biyik":
			return moust
		"ince":
			return absf(c.x) < 0.03 and c.y > -0.038 and c.y < -0.03 and c.z < -0.06
		"pala":
			return absf(c.x) < 0.04 and c.y > -0.044 and c.y < -0.024 and c.z < -0.055
		"keci":
			return moust or (absf(c.x) < 0.03 and c.y < -0.062 and c.y > -0.12 and c.z < -0.05)
		"sakal", "kirli", "uzun":
			return moust or full
		"zincir":
			return jaw or burns
		"favori":
			return burns
	return false
