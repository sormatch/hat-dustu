# Dünya süsleri (3D sanat yardımcıları): duvar lambaları, hale, sahte ışık huzmesi, lekeler (decal),
# sahte ortam gölgesi (AO şeritleri), borular, parmaklıklar, levhalar ve kalite ayarı.
# main.gd (koridor, ortam, menü), cell.gd ve lobby3d.gd kullanır.
# Telefonda ucuz kalsın diye: huzme ve hale tek dörtgen/silindir (ışık hesabı yok), AO şeritleri tek ağda birleşir,
# tekrarlayan parmaklıklar MultiMesh ile tek çizim çağrısıdır. Kaliteye bağlı düğümler gruplarla açılıp kapanır.
extends RefCounted

const YUKSEK := "kalite_yuksek"  # kalite >= 1 iken görünür (huzme, leke)
const ULTRA := "kalite_ultra"  # kalite >= 2 iken görünür
const GOLGE := "golge_isik"  # kalite >= 1 iken gölge açar
const AMBER := Color("#ffae55")
const LEKE := "res://assets/textures/leke/"
const STENCIL_FONT := preload("res://assets/fonts/RussoOne-Regular.ttf")

const KIR_DOKU := "res://assets/textures/kir/kir_detay.png"

static var _cache := {}
static var seviye := 1  # geçerli grafik kalitesi (efekt.gd parçacık sayılarını buna göre seçer)


# ---------- kalite ----------

# 0 = pil dostu (gölge/parlama/huzme/leke/ortam parçacıkları/kir katmanı kapalı, 3D çözünürlük düşük),
# 1 = yüksek, 2 = ultra (+MSAA 2x, biraz daha geniş parlama).
static func apply_quality(w: Node, level: int) -> void:
	var hi := level >= 1
	seviye = clampi(level, 0, 2)
	var tree := w.get_tree()
	for n in tree.get_nodes_in_group(YUKSEK):
		(n as Node3D).visible = hi
		# gizli parçacık da işlemciyi yorar: ortam parçacıkları (buhar, toz zerreleri) dursun
		var ps: Array = [n] if n is CPUParticles3D else n.find_children("*", "CPUParticles3D", true, false)
		for p in ps:
			(p as CPUParticles3D).emitting = hi
	for n in tree.get_nodes_in_group(ULTRA):
		(n as Node3D).visible = level >= 2
	for n in tree.get_nodes_in_group(GOLGE):
		(n as Light3D).shadow_enabled = hi
	_malzeme_kalitesi(w, level)
	var env: Environment = w.get("env")
	if env:
		env.glow_enabled = hi
		env.glow_bloom = 0.07 if level >= 2 else 0.04
	var probe: ReflectionProbe = w.get("probe")
	if probe:
		probe.visible = hi
	var vp := w.get_viewport()
	vp.use_occlusion_culling = true
	# telefonda ekran çok yoğun (ör. 2532x1170): 3D tam çözünürlükte çizilince hem GPU hem video belleği (çizim
	# hedefleri) ağırlaşıyor; arayüz her zaman tam çözünürlükte kalır
	if OS.has_feature("mobile"):
		vp.scaling_3d_scale = [0.65, 0.8, 1.0][clampi(level, 0, 2)]
	else:
		vp.scaling_3d_scale = 1.0 if hi else 0.8
	vp.msaa_3d = Viewport.MSAA_2X if level >= 2 else Viewport.MSAA_DISABLED
	vp.positional_shadow_atlas_size = 4096 if level >= 2 else 2048


# ---------- malzeme kalitesi: kir / leke katmanı ----------
# Duvar, zemin, tavan ve metal malzemelerinin iki hali var: sade (kalite 0) ve kir katmanlı (kalite >= 1). Kir katmanı
# dünya koordinatlı ikinci doku (UV2, ~7 m'de bir tekrar): ana dokunun kısa tekrarını büyük lekelerle kırar,
# yan yana duvarlar aynı görünmez. Kalite değişince sahnedeki bütün yüzeylerde malzeme takas edilir.

const KIRLI := ["wall", "paint", "paint_b", "paint_c", "floor", "ceiling", "corridor_floor", "corridor_wall",
	"door", "green_metal", "metal_plate", "pipe", "metal"]
static var _ciftler := {}  # anahtar -> [sade, kirli]
static var _kir_acik := -1


# main.gd _make_materials sonunda çağırır: kirli kopyalar üretilir, mats geçerli kaliteye göre seçilir.
static func malzeme_ciftleri(w: Node, level: int) -> void:
	var mats: Dictionary = w.get("mats")
	_ciftler.clear()
	var kir: Texture2D = load(KIR_DOKU)
	var ac := 1 if level >= 1 else 0
	for k in KIRLI:
		var sade := mats.get(k) as StandardMaterial3D
		if sade == null:
			continue
		var d := sade.duplicate() as StandardMaterial3D
		d.detail_enabled = true
		d.detail_albedo = kir
		d.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
		d.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
		d.uv2_triplanar = true
		d.uv2_world_triplanar = true
		# metallerde lekeler daha sık (küçük parçalar), yapıda büyük
		d.uv2_scale = Vector3.ONE * (0.45 if k in ["door", "green_metal", "metal_plate", "pipe", "metal"] else 0.14)
		if k == "corridor_floor" or k == "floor":
			d.roughness = sade.roughness * 0.82  # yüksek kalitede zemin biraz daha ıslak/parlak (yansıma sondası açık)
		_ciftler[k] = [sade, d]
		mats[k] = _ciftler[k][ac]
	_kir_acik = ac


# Açılış ısıtması için: o an sahnede olmayan (öbür kalitenin) malzemeler.
static func diger_kalite_malzemeleri() -> Array:
	var out: Array = []
	for k in _ciftler:
		out.append(_ciftler[k][1 - maxi(_kir_acik, 0)])
	return out


static func _malzeme_kalitesi(w: Node, level: int) -> void:
	var ac := 1 if level >= 1 else 0
	if _ciftler.is_empty() or ac == _kir_acik:
		return
	_kir_acik = ac
	var esle := {}
	var mats = w.get("mats")
	for k in _ciftler:
		var c: Array = _ciftler[k]
		esle[c[1 - ac]] = c[ac]
		if mats is Dictionary:
			mats[k] = c[ac]
	for n in w.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if g.material_override and esle.has(g.material_override):
			g.material_override = esle[g.material_override]
		if g is MeshInstance3D:
			var mi := g as MeshInstance3D
			for s in mi.get_surface_override_material_count():
				var m := mi.get_surface_override_material(s)
				if m and esle.has(m):
					mi.set_surface_override_material(s, esle[m])


static func _grp(n: Node3D, group: String) -> Node3D:
	if group != "":
		n.add_to_group(group)
	return n


# ---------- ışık süsleri ----------

static func _radial_tex() -> GradientTexture2D:
	if _cache.has("radial"):
		return _cache.radial
	var t := GradientTexture2D.new()
	t.width = 128
	t.height = 128
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.18, Color(1, 1, 1, 0.55))
	g.add_point(0.5, Color(1, 1, 1, 0.12))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	t.gradient = g
	_cache.radial = t
	return t


# Ampulün etrafında yumuşak parıltı (glow kapalıyken de lamba "yanıyor" görünür). Toplamalı, tek dörtgen.
# light verilirse parıltı o ışıkla birlikte söner/titrer.
static func halo(parent: Node3D, pos: Vector3, color: Color, size: float, strength := 0.6, light: Light3D = null) -> MeshInstance3D:
	var key := "halo_%s_%.2f" % [color.to_html(), strength]
	var m: StandardMaterial3D = _cache.get(key)
	if not m:
		m = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.no_depth_test = false
		m.disable_fog = true
		m.albedo_texture = _radial_tex()
		m.albedo_color = Color(color.r, color.g, color.b, strength)
		_cache[key] = m
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mi: MeshInstance3D = Takip.new() if light else MeshInstance3D.new()
	if light:
		(mi as Takip).light = light
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	parent.add_child(mi)
	return mi


const HUZME_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 renk : source_color = vec4(1.0, 0.7, 0.35, 1.0);
instance uniform float guc = 0.18;
uniform float boy = 2.0;
varying float yuk;
void vertex() {
	yuk = clamp(VERTEX.y / boy + 0.5, 0.0, 1.0);
}
void fragment() {
	float kenar = abs(dot(normalize(NORMAL), normalize(VIEW)));
	kenar = kenar * kenar;
	float yakin = smoothstep(0.25, 1.6, -VERTEX.z);
	ALBEDO = renk.rgb;
	ALPHA = clamp(kenar * yuk * yuk * guc * yakin, 0.0, 1.0);
}
"""


# Lambanın altında sahte hacimsel ışık konisi (havadaki toz). top: koninin tepesi.
# light verilirse koni o ışığın parlaklığını izler (titreme, elektrik kesintisi).
# dir: koninin ışık yönü (varsayılan aşağı).
static func huzme(parent: Node3D, top: Vector3, length: float, r_top: float, r_bottom: float, color: Color, strength := 0.16, light: Light3D = null, dir := Vector3.DOWN) -> MeshInstance3D:
	var key := "huzme_%s_%.2f" % [color.to_html(), length]
	var mat: ShaderMaterial = _cache.get(key)
	if not mat:
		var sh: Shader = _cache.get("huzme_shader")
		if not sh:
			sh = Shader.new()
			sh.code = HUZME_SHADER
			_cache.huzme_shader = sh
		mat = ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("renk", color)
		mat.set_shader_parameter("boy", length)
		_cache[key] = mat
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bottom
	c.height = length
	c.radial_segments = 16
	c.rings = 1
	c.cap_top = false
	c.cap_bottom = false
	var mi: MeshInstance3D = Takip.new() if light else MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var y := -dir.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(x, y, x.cross(y)), top - y * (length / 2.0))
	mi.set_instance_shader_parameter("guc", strength)
	if light:
		(mi as Takip).light = light
		(mi as Takip).base = strength
	parent.add_child(mi)
	_grp(mi, YUKSEK)
	return mi


# Işığın parlaklığını izleyen huzme: lamba titreyince ya da elektrik gidince koni de söner.
class Takip extends MeshInstance3D:
	var light: Light3D
	var base := 0.16
	var ref := -1.0
	var _last := -1.0

	func _process(_d: float) -> void:
		if not is_instance_valid(light):
			return
		if light.light_energy > ref:
			ref = maxf(light.light_energy, 0.001)
		var k := (light.light_energy / ref) if light.is_visible_in_tree() else 0.0
		if absf(k - _last) > 0.01:
			_last = k
			if material_override is ShaderMaterial:
				set_instance_shader_parameter("guc", base * k)
			else:
				transparency = 1.0 - clampf(k, 0.0, 1.0)


# ---------- duvar lambası (Poly Haven "Industrial Wall Lamp", CC0) ----------

# Kafesli bodrum lambası: duvara monte, sıcak amber. Işık verilirse OmniLight döner.
# normal: duvardan odaya doğru yön (lambanın baktığı yer).
static func duvar_lambasi(w: Node3D, parent: Node3D, pos: Vector3, normal: Vector3, with_light := true, energy := 1.6, rng_ := 5.0, color := AMBER) -> OmniLight3D:
	var yaw := atan2(normal.x, normal.z)
	var lamp: Node3D = w.model("industrial_wall_lamp", pos, yaw, 1.0, NAN, parent)
	# modelin tabanı değil arkası duvara yaslanmalı: modeli ortala, arkasını duvara dayat
	var bb: AABB = w._bounds(lamp, lamp)
	var inst: Node3D = lamp.get_child(0)
	inst.position.y -= bb.size.y / 2.0
	inst.position.z -= bb.position.z
	var yuzeyler: Array = []  # titreme için: [MeshInstance3D, yüzey, parlak malzeme]
	for mi in lamp.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_boost_emission(mi as MeshInstance3D, color)
		for s in (mi as MeshInstance3D).get_surface_override_material_count():
			var om := (mi as MeshInstance3D).get_surface_override_material(s)
			if om is StandardMaterial3D and (om as StandardMaterial3D).emission_enabled:
				yuzeyler.append([mi, s, om])
	var front := pos + normal * (bb.size.z * 0.6 + 0.04)
	if not with_light:
		halo(parent, front, color, 0.9, 0.5)
		return null
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng_
	l.omni_attenuation = 1.0
	l.light_specular = 0.7
	l.position = pos + normal * 0.35
	l.set_meta("yuzeyler", yuzeyler)
	l.set_meta("taban", energy)
	parent.add_child(l)
	halo(parent, front, color, 0.9, 0.5, l)  # lamba titreyince hâle de titrer
	return l


# Lambanın ampul malzemesinin sönük hali (titreme anı): bir kez üretilir.
static func sonuk(m: StandardMaterial3D) -> StandardMaterial3D:
	var key := "sonuk_%d" % m.get_instance_id()
	var s: StandardMaterial3D = _cache.get(key)
	if not s:
		s = m.duplicate()
		s.emission_energy_multiplier = 0.15
		_cache[key] = s
	return s


# Lamba ışığını k (0..1) oranında söndürür/yakar: ışık, ampul ve hâle birlikte (hâle ışığı izler).
static func lamba_parlakligi(l: OmniLight3D, k: float) -> void:
	l.light_energy = float(l.get_meta("taban", 1.0)) * k
	var acik := k > 0.5
	if l.get_meta("acik", true) == acik:
		return
	l.set_meta("acik", acik)
	for y in l.get_meta("yuzeyler", []):
		var mi := y[0] as MeshInstance3D
		if is_instance_valid(mi):
			mi.set_surface_override_material(int(y[1]), y[2] if acik else sonuk(y[2]))


static func _boost_emission(mi: MeshInstance3D, color: Color) -> void:
	if not mi.mesh:
		return
	for s in mi.mesh.get_surface_count():
		var m := mi.get_active_material(s) as StandardMaterial3D
		if not m:
			continue
		if m.emission_enabled or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			# anahtar kaynak yolu: sahne her yüklenişinde model yeniden yüklenir, nesne kimliği değişir
			# (kimlikle anahtarlanınca önbellek her maçtan dönüşte büyüyordu)
			var key := "lamba_" + (m.resource_path if m.resource_path != "" else str(m.get_instance_id()))
			var nm: StandardMaterial3D = _cache.get(key)
			if not nm:
				nm = m.duplicate()
				nm.emission_enabled = true
				nm.emission = color
				nm.emission_energy_multiplier = 3.0
				_cache[key] = nm
			mi.set_surface_override_material(s, nm)


# ---------- lekeler (decal) ----------

static func _tex(name: String) -> Texture2D:
	var key := "tex_" + name
	if not _cache.has(key):
		_cache[key] = load(LEKE + name + ".png")
	return _cache[key]


# Zemine leke: kir, su (ıslak, parlak), catlak. size: (en, boy) metre.
static func leke_zemin(parent: Node3D, kind: String, pos: Vector3, size: Vector2, yaw := 0.0, mod := Color.WHITE) -> Decal:
	var d := _decal(kind, Vector3(size.x, 0.4, size.y), mod)
	d.position = pos + Vector3(0, 0.1, 0)
	d.rotation.y = yaw
	parent.add_child(d)
	return d


# Duvara leke: normal = duvardan odaya doğru. pas akıntısı ve çatlak için.
static func leke_duvar(parent: Node3D, kind: String, pos: Vector3, normal: Vector3, size: Vector2, mod := Color.WHITE) -> Decal:
	var d := _decal(kind, Vector3(size.x, 0.3, size.y), mod)
	var y := normal.normalized()
	var z := Vector3.DOWN
	var x := y.cross(z).normalized()
	d.transform = Transform3D(Basis(x, y, z), pos)
	parent.add_child(d)
	return d


static func _decal(kind: String, size: Vector3, mod: Color) -> Decal:
	var d := Decal.new()
	d.size = size
	d.texture_albedo = _tex(kind)
	d.modulate = mod
	d.cull_mask = 1
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	d.normal_fade = 0.4
	d.distance_fade_enabled = true
	d.distance_fade_begin = 14.0
	d.distance_fade_length = 4.0
	if kind == "su":
		d.texture_orm = _tex("islak_orm")
		d.albedo_mix = 0.3
		d.modulate = Color(mod.r, mod.g, mod.b, mod.a * 0.8)
	_grp(d, YUKSEK)
	return d


# ---------- sahte ortam gölgesi (AO) ----------

# Köşelerde ve duvar diplerinde koyulaşma. Kenar listesi tek ağa birleşir (tek çizim çağrısı).
# Her kenar: [a, b, iç_yön, genişlik] -> a-b çizgisinden iç_yön boyunca genişlik kadar koyudan açığa geçen şerit.
# bloblar: eşyaların altındaki temas gölgesi (gölgeler kapalıyken de eşyalar yere otursun), aynı ağa eklenir:
# her biri [merkez (zeminde), yarıçap_x, yarıçap_z, dönüş, merkez koyuluğu 0..1 (0 = en koyu)].
static func ao_ag(parent: Node3D, edges: Array, darkness := 0.5, bloblar: Array = []) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for bl in bloblar:
		var c: Vector3 = bl[0] + Vector3(0, 0.005, 0)
		var rx: float = bl[1]
		var rz: float = bl[2]
		var bs := Basis(Vector3.UP, float(bl[3]))
		var v0: float = bl[4] if bl.size() > 4 else 0.3
		var seg := 14
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			# yuvarlatılmış dikdörtgen gibi: köşelerde biraz dışarı taşan elips
			var p0 := c + bs * Vector3(cos(a0) * rx, 0, sin(a0) * rz)
			var p1 := c + bs * Vector3(cos(a1) * rx, 0, sin(a1) * rz)
			for v in [[c, v0], [p1, 1.0], [p0, 1.0]]:
				st.set_uv(Vector2(0, v[1]))
				st.add_vertex(v[0])
	for e in edges:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var dir: Vector3 = (e[2] as Vector3).normalized()
		var wd: float = e[3]
		var lift := dir.cross(b - a).normalized() * 0.0
		var a2 := a + dir * wd
		var b2 := b + dir * wd
		for v in [[a, 0.0], [b, 0.0], [b2, 1.0], [a, 0.0], [b2, 1.0], [a2, 1.0]]:
			st.set_uv(Vector2(0, v[1]))
			st.add_vertex((v[0] as Vector3) + lift)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var key := "ao_%.2f" % darkness
	var m: StandardMaterial3D = _cache.get(key)
	if not m:
		var t := GradientTexture2D.new()
		t.width = 4
		t.height = 64
		t.fill_from = Vector2(0, 0)
		t.fill_to = Vector2(0, 1)
		var g := Gradient.new()
		g.set_color(0, Color(1.0 - darkness, 1.0 - darkness, 1.0 - darkness))
		g.add_point(0.35, Color(1.0 - darkness * 0.45, 1.0 - darkness * 0.45, 1.0 - darkness * 0.42))
		g.set_color(g.get_point_count() - 1, Color(1, 1, 1))
		t.gradient = g
		m = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.disable_fog = true
		m.albedo_texture = t
		m.texture_repeat = false
		_cache[key] = m
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


# Dikdörtgen odanın iç kenarları için AO kenarları (zemin-duvar, tavan-duvar, dikey köşeler).
# lo/hi: odanın iç köşeleri. skip_x1: sağ (+x) duvarda kapı boşlukları [z0, z1] listesi.
static func oda_ao_kenarlari(lo: Vector3, hi: Vector3, floor_w := 0.35, ceil_w := 0.45, gaps_x1: Array = []) -> Array:
	var e: Array = []
	var o := 0.004
	var y0 := lo.y + o
	var y1 := hi.y - o
	# zemin ve tavan boyunca dört duvar
	var walls := [
		[Vector3(lo.x + o, 0, lo.z), Vector3(lo.x + o, 0, hi.z), Vector3.RIGHT],
		[Vector3(hi.x - o, 0, lo.z), Vector3(hi.x - o, 0, hi.z), Vector3.LEFT],
		[Vector3(lo.x, 0, lo.z + o), Vector3(hi.x, 0, lo.z + o), Vector3.BACK],
		[Vector3(lo.x, 0, hi.z - o), Vector3(hi.x, 0, hi.z - o), Vector3.FORWARD],
	]
	for i in walls.size():
		var wl: Array = walls[i]
		var segs: Array = [[wl[0], wl[1]]]
		if i == 1 and gaps_x1.size() > 0:
			segs = []
			var z := lo.z
			for g in gaps_x1:
				segs.append([Vector3(hi.x - o, 0, z), Vector3(hi.x - o, 0, float(g[0]))])
				z = float(g[1])
			segs.append([Vector3(hi.x - o, 0, z), Vector3(hi.x - o, 0, hi.z)])
		for s in segs:
			var a: Vector3 = s[0]
			var b: Vector3 = s[1]
			var inward: Vector3 = wl[2]
			e.append([Vector3(a.x, y0, a.z), Vector3(b.x, y0, b.z), inward, floor_w])  # zemin
			e.append([Vector3(a.x, y0, a.z), Vector3(b.x, y0, b.z), Vector3.UP, floor_w * 0.8])  # duvar dibi
			e.append([Vector3(a.x, y1, a.z), Vector3(b.x, y1, b.z), Vector3.DOWN, ceil_w])  # tavan köşesi
			e.append([Vector3(a.x, y1, a.z), Vector3(b.x, y1, b.z), inward, ceil_w * 0.8])
	# dikey köşeler
	for c in [[lo.x, lo.z, 1.0, 1.0], [hi.x, lo.z, -1.0, 1.0], [lo.x, hi.z, 1.0, -1.0], [hi.x, hi.z, -1.0, -1.0]]:
		var px: float = c[0] + o * c[2]
		var pz: float = c[1] + o * c[3]
		e.append([Vector3(px, lo.y, pz), Vector3(px, hi.y, pz), Vector3(c[2], 0, 0), 0.3])
		e.append([Vector3(px, lo.y, pz), Vector3(px, hi.y, pz), Vector3(0, 0, c[3]), 0.3])
	return e


# ---------- borular, parmaklıklar, levhalar ----------

# a'dan b'ye boru (silindir). Telefonda ucuz: 10 kenarlı.
static func boru(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material, segs := 10) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = a.distance_to(b)
	c.radial_segments = segs
	c.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = mat
	var y := (b - a).normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	mi.transform = Transform3D(Basis(x, y, z), (a + b) / 2.0)
	parent.add_child(mi)
	return mi


# Aynı parçadan çok sayıda (parmaklık, kelepçe): tek MultiMesh = tek çizim çağrısı.
static func coklu(parent: Node3D, mesh: Mesh, mat: Material, xforms: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	parent.add_child(mmi)
	return mmi


# Dikey demir parmaklıklar: start'tan along yönünde count adet, aralık spacing.
static func parmaklik(parent: Node3D, start: Vector3, along: Vector3, count: int, spacing: float, height: float, r: float, mat: Material, cross_bars := 2) -> void:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = height
	c.radial_segments = 8
	c.rings = 1
	var xf: Array = []
	var dir := along.normalized()
	for i in count:
		xf.append(Transform3D(Basis(), start + dir * (i * spacing) + Vector3(0, height / 2.0, 0)))
	coklu(parent, c, mat, xf)
	var length := spacing * (count - 1) + r * 4.0
	for k in cross_bars:
		var y := height * (0.12 + 0.76 * (float(k) / maxf(1.0, cross_bars - 1)))
		var mid := start + dir * (spacing * (count - 1) / 2.0) + Vector3(0, y, 0)
		var bar := BoxMesh.new()
		bar.size = Vector3(0.05, 0.05, length) if absf(dir.z) > 0.5 else Vector3(length, 0.05, 0.05)
		var mi := MeshInstance3D.new()
		mi.mesh = bar
		mi.material_override = mat
		mi.position = mid
		parent.add_child(mi)


# Duvar levhası: zemin plakası + şablon yazı. yaw: levhanın baktığı yön (+z'den).
static func levha(parent: Node3D, text: String, pos: Vector3, yaw: float, size: Vector2, bg: Material, fg: Color, font_size := 64, stripes := false) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)
	var plate := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, size.y, 0.02)
	plate.mesh = bm
	plate.material_override = bg
	root.add_child(plate)
	if stripes:
		var sm := MeshInstance3D.new()
		var sq := QuadMesh.new()
		sq.size = Vector2(size.x, size.y * 0.18)
		sm.mesh = sq
		sm.material_override = hazard_mat()
		sm.position = Vector3(0, -size.y * 0.41, 0.0115)
		root.add_child(sm)
		var sm2 := sm.duplicate() as MeshInstance3D
		sm2.position.y = size.y * 0.41
		root.add_child(sm2)
	var l := Label3D.new()
	l.text = text
	l.font = STENCIL_FONT
	l.font_size = font_size
	l.pixel_size = 0.0018
	l.modulate = fg
	l.outline_size = 0
	l.width = size.x / 0.0018 * 0.92
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector3(0, 0, 0.012)
	root.add_child(l)
	return root


static func hazard_mat() -> StandardMaterial3D:
	if _cache.has("hazard"):
		return _cache.hazard
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex("tehlike")
	m.roughness = 0.75
	m.uv1_scale = Vector3(2, 1, 1)
	_cache.hazard = m
	return m


# root altındaki, root'a göre sabit duran (arada yalnız düz Node3D olan), aynı malzeme/gölge/katmanlı tek yüzeyli
# meshleri birleştirir: dönüşümler köşelere işlenir, görüntü aynı kalır, çizim çağrısı parça sayısından bire iner.
# skip: altındakiler birleştirilmeyecek düğümler (ör. elde taşınan ahize).
static func birlestir(root: Node3D, skip: Array = []) -> void:
	var groups := {}
	# betiğin değişkenlerinde tutulan düğümler (sonradan gizlenen/değişen parçalar) birleştirilmez
	var held := {}
	for s in skip:
		held[s] = true
	for pr in root.get_property_list():
		if pr.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var v = root.get(pr.name)
			if v is Node:
				held[v] = true
			elif v is Array:
				for x in v:
					if x is Node:
						held[x] = true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if m.mesh == null or m.skin != null or m.material_override == null or not m.visible or m.get_script() != null \
				or m.get_child_count() > 0 or held.has(m) or not m.get_groups().is_empty() or _transparent(m.material_override) \
				or m.mesh.get_surface_count() != 1 or (m.mesh is ArrayMesh and ((m.mesh as ArrayMesh).surface_get_primitive_type(0) \
				!= Mesh.PRIMITIVE_TRIANGLES or (m.mesh as ArrayMesh).get_blend_shape_count() > 0)):
			continue
		var xf := m.transform
		var p := m.get_parent()
		while p != root and p != null:
			if p.get_class() != "Node3D" or p.get_script() != null or not (p as Node3D).visible or held.has(p) \
					or not p.get_groups().is_empty():
				p = null
				break
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		if p != root:
			continue
		var arr0 := m.mesh.surface_get_arrays(0)
		var fmt := ""
		for ai in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_INDEX]:
			fmt += "1" if arr0[ai] != null else "0"
		var key := "%d/%d/%d/%s/%.2f" % [m.material_override.get_instance_id(), m.cast_shadow, m.layers, fmt, m.visibility_range_end]
		if not groups.has(key):
			groups[key] = []
		groups[key].append([m, xf, arr0])
	for key in groups:
		var list: Array = groups[key]
		if list.size() < 2:
			continue
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var tans := PackedFloat32Array()
		var cols := PackedColorArray()
		var uvs := PackedVector2Array()
		var uv2s := PackedVector2Array()
		var idx := PackedInt32Array()
		for e in list:
			var arr: Array = e[2]
			var xf: Transform3D = e[1]
			var nb := xf.basis.inverse().transposed()
			var base := verts.size()
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for v in vs:
				verts.append(xf * v)
			if arr[Mesh.ARRAY_NORMAL] != null:
				for nn in (arr[Mesh.ARRAY_NORMAL] as PackedVector3Array):
					norms.append((nb * nn).normalized())
			if arr[Mesh.ARRAY_TANGENT] != null:
				var ta: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
				for i in range(0, ta.size() - 3, 4):
					var t := (xf.basis * Vector3(ta[i], ta[i + 1], ta[i + 2])).normalized()
					tans.append_array([t.x, t.y, t.z, ta[i + 3]])
			if arr[Mesh.ARRAY_COLOR] != null:
				cols.append_array(arr[Mesh.ARRAY_COLOR])
			if arr[Mesh.ARRAY_TEX_UV] != null:
				uvs.append_array(arr[Mesh.ARRAY_TEX_UV])
			if arr[Mesh.ARRAY_TEX_UV2] != null:
				uv2s.append_array(arr[Mesh.ARRAY_TEX_UV2])
			var flip := xf.basis.determinant() < 0.0  # aynalanmış parça: üçgen yönü korunsun
			var src: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vs.size()))
			for t in range(0, src.size() - 2, 3):
				idx.append_array([base + src[t], base + src[t + (2 if flip else 1)], base + src[t + (1 if flip else 2)]])
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = verts
		out[Mesh.ARRAY_INDEX] = idx
		if norms.size() == verts.size():
			out[Mesh.ARRAY_NORMAL] = norms
		if tans.size() == verts.size() * 4:
			out[Mesh.ARRAY_TANGENT] = tans
		if cols.size() == verts.size():
			out[Mesh.ARRAY_COLOR] = cols
		if uvs.size() == verts.size():
			out[Mesh.ARRAY_TEX_UV] = uvs
		if uv2s.size() == verts.size():
			out[Mesh.ARRAY_TEX_UV2] = uv2s
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
		var first: MeshInstance3D = list[0][0]
		var mi := MeshInstance3D.new()
		mi.name = "Birlesik"
		mi.mesh = am
		mi.material_override = first.material_override
		mi.cast_shadow = first.cast_shadow
		mi.layers = first.layers
		mi.visibility_range_end = first.visibility_range_end
		mi.visibility_range_end_margin = first.visibility_range_end_margin
		root.add_child(mi)
		for e in list:
			var old: MeshInstance3D = e[0]
			old.get_parent().remove_child(old)
			old.queue_free()


static func _transparent(m: Material) -> bool:
	if m is BaseMaterial3D:
		return (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	return m is ShaderMaterial  # özel gölgelendiricide sıralama bilinmez: dokunma


# Uzaktayken görünmesin (çizim çağrısı azalır): küçük eşyaların hepsine görüş mesafesi koyar.
static func uzakta_gizle(root: Node, dist: float) -> void:
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if g.visibility_range_end == 0.0:
			g.visibility_range_end = dist
			g.visibility_range_end_margin = 1.0


# ---------- koridor parçaları (main.gd _build_corridor kullanır) ----------

# Gardiyan kulübesi (koridorun +z ucunda, karşı duvara yaslı).
static func kulube(w: Node3D, root: Node3D, x1: float, zmax: float) -> Dictionary:
	var bx := 3.8
	var bz := zmax - 2.3
	var mx := (bx + x1) / 2.0
	var mz := (bz + zmax) / 2.0
	var wx := x1 - bx
	var wz := zmax - bz
	w.box(Vector3(wx, 1.05, 0.08), Vector3(mx, 0.525, bz), w.mats.metal_plate, false, root)
	w.box(Vector3(0.08, 1.05, wz), Vector3(bx, 0.525, mz), w.mats.metal_plate, false, root)
	w.box(Vector3(wx, 0.06, 0.12), Vector3(mx, 1.08, bz), w.mats.metal_dark, false, root)
	w.box(Vector3(0.12, 0.06, wz), Vector3(bx, 1.08, mz), w.mats.metal_dark, false, root)
	w.box(Vector3(wx, 1.2, 0.02), Vector3(mx, 1.7, bz), w.mats.glass, false, root)
	w.box(Vector3(0.02, 1.2, wz - 0.9), Vector3(bx, 1.7, mz + 0.45), w.mats.glass, false, root)
	for p in [Vector3(bx, 0, bz), Vector3(x1 - 0.03, 0, bz), Vector3(bx, 0, zmax - 0.9), Vector3(bx, 0, zmax - 0.03)]:
		w.box(Vector3(0.07, 2.35, 0.07), p + Vector3(0, 1.175, 0), w.mats.metal_dark, false, root)
	w.box(Vector3(wx + 0.1, 0.12, wz + 0.1), Vector3(mx, 2.38, mz), w.mats.metal_dark, false, root)
	# kapı (yan duvarda, cam yok): koyu metal
	w.box(Vector3(0.05, 2.25, 0.86), Vector3(bx, 1.125, zmax - 0.47), w.mats.door, false, root)
	w.solid(Vector3(wx, 2.4, 0.1), Vector3(mx, 1.2, bz), 0.0, root)
	w.solid(Vector3(0.1, 2.4, wz), Vector3(bx, 1.2, mz), 0.0, root)
	# içi: masa, monitör, tabure, kağıtlar
	w.box(Vector3(wx - 0.15, 0.05, 0.62), Vector3(mx, 0.82, zmax - 0.36), w.mats.metal_plate, false, root)
	w.box(Vector3(wx - 0.15, 0.78, 0.04), Vector3(mx, 0.4, zmax - 0.66), w.mats.metal_dark, false, root)
	var tv: Node3D = w.model("television_02", Vector3(mx + 0.2, 0.845, zmax - 0.32), PI, 0.55, NAN, root)
	w.model("metal_stool_01", Vector3(mx, 0, zmax - 1.05), 0.0, 1.0, NAN, root)
	# monitörün ekranı: kamera görüntüsü gibi soğuk, karıncalı; Canlilik titretir
	var tb: AABB = w._bounds(tv, root)
	var ekran_mat: StandardMaterial3D = w._glow(Color("#9fc4ff"), 1.1)
	ekran_mat.albedo_color = Color(0.02, 0.02, 0.03)
	ekran_mat.emission_texture = w._noise_tex(Color(0.45, 0.5, 0.5), Color(1, 1, 1), 0.25, 9)
	var ekran := MeshInstance3D.new()
	var eq := QuadMesh.new()
	eq.size = Vector2(tb.size.x * 0.74, tb.size.y * 0.55)
	ekran.mesh = eq
	ekran.material_override = ekran_mat
	ekran.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ekran.position = Vector3(tb.get_center().x, tb.get_center().y + tb.size.y * 0.08, tb.position.z - 0.004)
	ekran.rotation.y = PI
	root.add_child(ekran)
	var paper: StandardMaterial3D = w._flat(Color("#d8d0bc"), 0.9)
	for i in 3:
		var pp: MeshInstance3D = w.box(Vector3(0.21, 0.004, 0.29), Vector3(mx - 0.45 + i * 0.07, 0.848 + i * 0.002, zmax - 0.4), paper, false, root)
		pp.rotation.y = 0.2 * i - 0.2
	var l := OmniLight3D.new()
	l.light_color = Color("#ffb867")
	l.light_energy = 1.4
	l.omni_range = 3.2
	l.position = Vector3(mx, 2.1, mz)
	root.add_child(l)
	var scr := OmniLight3D.new()
	scr.light_color = Color("#8fb6ff")
	scr.light_energy = 0.5
	scr.omni_range = 1.6
	scr.position = Vector3(mx + 0.2, 1.15, zmax - 0.75)
	root.add_child(scr)
	var bulb := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.05
	bs.height = 0.1
	bulb.mesh = bs
	bulb.material_override = w._glow(Color("#ffd08a"), 5.0)
	bulb.position = Vector3(mx, 2.26, mz)
	root.add_child(bulb)
	halo(root, Vector3(mx, 2.22, mz), Color("#ffb867"), 0.7, 0.45)
	levha(root, "GARDİYAN", Vector3(mx, 2.62, bz - 0.01), PI, Vector2(1.2, 0.26), w.mats.stripe, Color("#e9d9b0"), 100)
	levha(root, "YAKLAŞMA", Vector3(mx, 0.6, bz - 0.05), PI, Vector2(1.0, 0.4), w._flat(Color("#c9a227"), 0.6, 0.2), Color("#141414"), 80, true)
	l.set_meta("taban", l.light_energy)
	return {"ekran": ekran_mat, "isik": scr, "lamba": l}


# Açılmayan kapıları topluca kurar: aynı parçalar MultiMesh ile tek çizim çağrısında çizilir (telefonda hızlı).
# Her kapı: [duvar_x, z, yön, numara, ışık_sızıyor_mu]
static func sahte_kapilar(w: Node3D, list: Array, parent: Node3D) -> void:
	var dim: StandardMaterial3D = w._glow(Color("#ffb45a"), 0.35)
	var lit: StandardMaterial3D = w._glow(Color("#ffb45a"), 1.6)
	var crack: StandardMaterial3D = w._glow(Color("#ffb45a"), 3.0)
	# parça: [boyut, yerel konum (x = duvardan dışarı), malzeme anahtarı]
	var parts: Array = [
		[Vector3(0.14, 2.32, 0.1), Vector3(0.07, 1.16, -0.56), "frame"],
		[Vector3(0.14, 2.32, 0.1), Vector3(0.07, 1.16, 0.56), "frame"],
		[Vector3(0.14, 0.1, 1.22), Vector3(0.07, 2.32, 0.0), "frame"],
		[Vector3(0.08, 2.2, 1.0), Vector3(0.05, 1.1, 0.0), "door"],
		[Vector3(0.1, 0.05, 1.0), Vector3(0.06, 0.25, 0.0), "dark"],
		[Vector3(0.1, 0.05, 1.0), Vector3(0.06, 1.25, 0.0), "dark"],
		[Vector3(0.1, 0.32, 0.03), Vector3(0.06, 1.66, -0.22), "dark"],
		[Vector3(0.1, 0.32, 0.03), Vector3(0.06, 1.66, 0.22), "dark"],
		[Vector3(0.1, 0.03, 0.47), Vector3(0.06, 1.835, 0.0), "dark"],
		[Vector3(0.1, 0.03, 0.47), Vector3(0.06, 1.485, 0.0), "dark"],
		[Vector3(0.12, 0.32, 0.022), Vector3(0.07, 1.66, -0.1), "dark"],
		[Vector3(0.12, 0.32, 0.022), Vector3(0.07, 1.66, 0.0), "dark"],
		[Vector3(0.12, 0.32, 0.022), Vector3(0.07, 1.66, 0.1), "dark"],
		[Vector3(0.04, 0.09, 0.36), Vector3(0.1, 1.0, 0.0), "dark"],
		[Vector3(0.06, 0.05, 0.14), Vector3(0.12, 1.1, 0.38), "dark"],
		[Vector3(0.05, 0.16, 0.05), Vector3(0.09, 0.45, -0.48), "dark"],
		[Vector3(0.05, 0.16, 0.05), Vector3(0.09, 1.8, -0.48), "dark"],
		[Vector3(0.02, 0.22, 0.4), Vector3(0.012, 2.66, 0.0), "plate"],
	]
	var groups := {}
	for d in list:
		var basis := Basis(Vector3.UP, 0.0 if float(d[2]) > 0.0 else PI)
		var origin := Vector3(float(d[0]), 0, float(d[1]))
		for p in parts:
			var key := "%s|%s" % [p[2], p[0]]
			if not groups.has(key):
				var bm := BoxMesh.new()
				bm.size = p[0]
				groups[key] = [bm, p[2], []]
			(groups[key][2] as Array).append(Transform3D(basis, origin + basis * (p[1] as Vector3)))
		# pencere camı (içeride ışık var mı?) ve kapı aralığından sızan ışık
		var win := "lit" if d[4] else "dim"
		var wkey := "%s|win" % win
		if not groups.has(wkey):
			var wm := BoxMesh.new()
			wm.size = Vector3(0.02, 0.32, 0.42)
			groups[wkey] = [wm, win, []]
		(groups[wkey][2] as Array).append(Transform3D(basis, origin + basis * Vector3(0.03, 1.66, 0.0)))
		if d[4]:
			if not groups.has("crack"):
				var cm := BoxMesh.new()
				cm.size = Vector3(0.02, 2.1, 0.025)
				groups.crack = [cm, "crack", []]
			(groups.crack[2] as Array).append(Transform3D(basis, origin + basis * Vector3(0.05, 1.05, 0.5)))
		var l := Label3D.new()
		l.text = str(d[3])
		l.font = STENCIL_FONT
		l.font_size = 96
		l.pixel_size = 0.0016
		l.modulate = Color("#e6d8b4")
		l.outline_size = 0
		l.position = origin + basis * Vector3(0.025, 2.66, 0.0)
		l.rotation.y = PI / 2 * float(d[2])
		parent.add_child(l)
	var mat_of := {"frame": w.mats.metal_dark, "door": w.mats.door, "dark": w.mats.metal_dark, "plate": w.mats.stripe, "lit": lit, "dim": dim, "crack": crack}
	for key in groups:
		var g: Array = groups[key]
		coklu(parent, g[0], mat_of[g[1]], g[2])


# ---------- koridorun canlılığı ----------

# Koridora ek ayrıntılar: tavanda parmaklıklı ay ışığı pencereleri (soğuk ışık + huzme), havalandırma ızgaraları
# (buhar), güvenlik kameralarında yanıp sönen kırmızı ışık, kopuk kablo kutusu (ara sıra kıvılcım). Koyu metal
# parçaların hepsi tek MultiMesh (tek çizim çağrısı). Dönen Canlilik düğümü titreme, damla, nefes vb. sürer.
# lambalar: titreyebilecek OmniLight3D'ler (duvar_lambasi dönüşü). kul: kulube() dönüşü. kameralar: model düğümleri.
# birikintiler: su birikintilerinin zemin noktaları (tavandan damla düşer).
static func koridor_ekleri(w: Node3D, root: Node3D, x0: float, x1: float, h: float, lambalar: Array, kul: Dictionary,
		kameralar: Array, birikintiler: Array) -> Node3D:
	var Efekt: GDScript = load("res://scripts/efekt.gd")
	var cx := (x0 + x1) / 2.0
	var koyu: Array = []  # birim kutu dönüşümleri (koyu metal)
	# tavan pencereleri: soğuk ay ışığı (sıcak lambaların arasında renk dengesi)
	var cam_xf: Array = []
	var ay := Color("#7d9cd4")
	for z in [-16.6, -3.3, 9.9]:
		var y := h - 0.012
		cam_xf.append(Transform3D(Basis().scaled(Vector3(1.0, 0.02, 0.62)), Vector3(cx, y, z)))
		koyu.append(_birim(Vector3(1.16, 0.06, 0.08), Vector3(cx, y - 0.02, z - 0.35)))
		koyu.append(_birim(Vector3(1.16, 0.06, 0.08), Vector3(cx, y - 0.02, z + 0.35)))
		koyu.append(_birim(Vector3(0.08, 0.06, 0.78), Vector3(cx - 0.54, y - 0.02, z)))
		koyu.append(_birim(Vector3(0.08, 0.06, 0.78), Vector3(cx + 0.54, y - 0.02, z)))
		for i in 6:
			koyu.append(_birim(Vector3(0.025, 0.035, 0.66), Vector3(cx - 0.4 + i * 0.16, y - 0.035, z)))
		huzme(root, Vector3(cx, h - 0.05, z), 3.4, 0.42, 0.95, Color("#6f8fc4"), 0.12, null, Vector3(0.22, -1.0, 0.12))
		var al := OmniLight3D.new()
		al.light_color = ay
		al.light_energy = 0.9
		al.omni_range = 3.6
		al.omni_attenuation = 1.4
		al.light_specular = 0.25
		al.position = Vector3(cx + 0.2, h - 0.7, z + 0.1)
		root.add_child(al)
		_grp(al, YUKSEK)
	var cm := BoxMesh.new()
	cm.size = Vector3.ONE
	coklu(root, cm, w._glow(Color("#4a6c9e"), 1.8), cam_xf)
	# havalandırma ızgaraları (tavan, hücre tarafı) ve buhar
	for z in [-11.2, 17.6]:
		var p := Vector3(x0 + 0.75, h - 0.01, z)
		koyu.append(_birim(Vector3(0.56, 0.03, 0.4), p))
		for i in 5:
			koyu.append(_birim(Vector3(0.5, 0.05, 0.03), p + Vector3(0, -0.03, -0.14 + i * 0.07)))
		Efekt.buhar(root, p + Vector3(0, -0.06, 0), Vector3.DOWN, 0.22)
	# kopuk kablo kutusu (hücre tarafı duvar, kablo kanalının altında)
	var kz := -5.2
	koyu.append(_birim(Vector3(0.12, 0.3, 0.26), Vector3(x0 + 0.06, h - 0.42, kz)))
	koyu.append(_birim(Vector3(0.02, 0.06, 0.2), Vector3(x0 + 0.125, h - 0.3, kz)))
	var kablo_uc := Vector3(x0 + 0.32, h - 1.02, kz + 0.16)
	boru(root, Vector3(x0 + 0.1, h - 0.56, kz + 0.05), Vector3(x0 + 0.24, h - 0.82, kz + 0.12), 0.012, w.mats.metal_dark, 6)
	boru(root, Vector3(x0 + 0.24, h - 0.82, kz + 0.12), kablo_uc, 0.012, w.mats.metal_dark, 6)
	coklu(root, cm, w.mats.metal_dark, koyu)
	# güvenlik kamerası ışıkları (altlarında kırmızı nokta + hâle)
	var led_mat: StandardMaterial3D = w._glow(Color("#ff2a1a"), 6.0)
	var ledler: Array = []
	var nokta := SphereMesh.new()
	nokta.radius = 0.012
	nokta.height = 0.024
	nokta.radial_segments = 6
	nokta.rings = 3
	for k in kameralar:
		var bb: AABB = w._bounds(k, root)
		var lp := Vector3(bb.get_center().x, bb.position.y + 0.02, bb.get_center().z)
		var mi := MeshInstance3D.new()
		mi.mesh = nokta
		mi.material_override = led_mat
		mi.position = lp
		root.add_child(mi)
		ledler.append(halo(root, lp + Vector3(0, -0.01, 0), Color("#ff3020"), 0.22, 0.7))
	var c := Canlilik.new()
	c.name = "KoridorCanliligi"
	c.w = w
	c.x0 = x0
	c.x1 = x1
	c.h = h
	c.lambalar = lambalar.filter(func(l) -> bool: return l is OmniLight3D)
	if kul.has("lamba"):
		c.lambalar.append(kul.lamba)
	c.ekran_mat = kul.get("ekran")
	c.ekran_isik = kul.get("isik")
	c.led_mat = led_mat
	c.ledler = ledler
	c.kablo_ucu = kablo_uc
	for b in birikintiler:
		c.damlalar.append(Vector3((b as Vector3).x, h - 0.02, (b as Vector3).z))
	root.add_child(c)
	# lamba ışığında uçuşan toz zerreleri (kameranın çevresinde)
	var tz: CPUParticles3D = Efekt.zerreler(root, AABB(Vector3(x0, 0, -29.0), Vector3(x1 - x0, h, 58.0)))
	(tz.get_parent() as Node3D).set("ust_y", h)
	return c


static func _birim(boyut: Vector3, p: Vector3) -> Transform3D:
	return Transform3D(Basis().scaled(boyut), p)


class Canlilik extends Node3D:
	var Efekt: GDScript = load("res://scripts/efekt.gd")
	var D: GDScript = load("res://scripts/dunya.gd")
	var w: Node3D
	var x0 := 2.2
	var x1 := 5.6
	var h := 3.2
	var lambalar: Array = []
	var ekran_mat: StandardMaterial3D
	var ekran_isik: OmniLight3D
	var led_mat: StandardMaterial3D
	var ledler: Array = []
	var kablo_ucu := Vector3.ZERO
	var damlalar: Array = []
	var _t := 0.0
	var _led := true
	var _titre_t := 9.0  # sıradaki titremeye kalan
	var _titre: OmniLight3D
	var _adimlar: Array = []  # [süre, parlaklık]
	var _adim_t := 0.0
	var _damla_t := 2.0
	var _kiv_t := 7.0
	var _nefes_t := 0.0
	var _nefes := {}  # gövde kimliği -> sıradaki nefes zamanı
	var _ekran_t := 0.0
	var _ses: AudioStreamPlayer3D

	func _ready() -> void:
		_ses = AudioStreamPlayer3D.new()
		_ses.unit_size = 2.0
		_ses.volume_db = -14.0
		_ses.max_distance = 14.0
		add_child(_ses)

	func _process(d: float) -> void:
		_t += d
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var cp := cam.global_position
		# güvenlik kamerası: 1,4 sn'de bir kısa kırmızı yanıp sönme
		var on := fmod(_t, 1.4) < 0.18
		if on != _led:
			_led = on
			led_mat.emission_energy_multiplier = 6.0 if on else 0.4
			for l in ledler:
				if is_instance_valid(l):
					(l as Node3D).visible = on
		# gardiyan monitörü: hafif titreme, ara sıra parlaklık atlaması, karınca kayar
		_ekran_t -= d
		if _ekran_t <= 0.0 and ekran_mat:
			_ekran_t = randf_range(0.05, 0.14)
			var k := randf_range(0.82, 1.0) if randf() > 0.06 else randf_range(0.25, 0.5)
			ekran_mat.emission_energy_multiplier = 1.1 * k
			ekran_mat.uv1_offset = Vector3(randf(), randf(), 0)
			if ekran_isik:
				ekran_isik.light_energy = 0.5 * k
		# lamba titremesi: nadiren, rastgele bir lambada
		if _titre:
			_adim_t -= d
			while _adim_t <= 0.0 and _titre:
				if _adimlar.is_empty():
					D.lamba_parlakligi(_titre, 1.0)
					_titre = null
					_ses.stop()
					break
				var a: Array = _adimlar.pop_front()
				_adim_t += float(a[0])
				D.lamba_parlakligi(_titre, float(a[1]))
		else:
			_titre_t -= d
			if _titre_t <= 0.0:
				_titre_t = randf_range(14.0, 34.0)
				_titre_baslat(cp, 1.0)
		var koridorda := cp.x > x0 - 1.0 and cp.x < x1 + 1.0
		# kopuk kablodan kıvılcım
		_kiv_t -= d
		if _kiv_t <= 0.0:
			_kiv_t = randf_range(6.0, 16.0)
			if koridorda and cp.distance_to(kablo_ucu) < 16.0:
				Efekt.kivilcim(self, kablo_ucu, Vector3(0.3, -0.6, 0.2))
				if randf() < 0.5:
					get_tree().create_timer(0.16).timeout.connect(Efekt.kivilcim.bind(self, kablo_ucu, Vector3(-0.2, -0.5, 0.3)))
				_titre_baslat(kablo_ucu, 0.35)  # en yakın lamba bir an göz kırpar
		if D.seviye < 1 or not koridorda:
			return
		# tavandan damlayan su (birikintilere)
		_damla_t -= d
		if _damla_t <= 0.0:
			_damla_t = randf_range(1.2, 3.5)
			var aday: Array = damlalar.filter(func(p: Vector3) -> bool: return p.distance_to(cp) < 13.0)
			if not aday.is_empty():
				var p: Vector3 = aday.pick_random()
				Efekt.damla(self, p + Vector3(randf_range(-0.25, 0.25), 0, randf_range(-0.25, 0.25)), 0.0)
		# soğuk koridorda nefes buharı (yakındaki karakterler)
		_nefes_t -= d
		if _nefes_t <= 0.0:
			_nefes_t = 0.3
			_nefesler(cp)

	# rastgele (siddet 1) ya da en yakın (siddet < 1: kısa göz kırpma) lambada titreme başlatır
	func _titre_baslat(yakin: Vector3, siddet: float) -> void:
		if _titre or lambalar.is_empty():
			return
		var menzil := 9.0 if siddet < 1.0 else 18.0
		var adaylar: Array = lambalar.filter(func(l) -> bool:
			return is_instance_valid(l) and (l as OmniLight3D).is_visible_in_tree() and (l as Node3D).global_position.distance_to(yakin) < menzil)
		if adaylar.is_empty():
			return
		if siddet < 1.0:
			adaylar.sort_custom(func(a, b) -> bool: return (a as Node3D).global_position.distance_to(yakin) < (b as Node3D).global_position.distance_to(yakin))
			_titre = adaylar[0]
			_adimlar = [[0.05, 0.25], [0.04, 1.0], [0.06, 0.4]]
		else:
			_titre = adaylar.pick_random()
			_adimlar = []
			for i in randi_range(4, 9):
				_adimlar.append([randf_range(0.03, 0.12), randf_range(0.0, 0.25)])
				_adimlar.append([randf_range(0.03, 0.2), randf_range(0.7, 1.0)])
			if randf() < 0.35:  # bazen bir an tamamen söner
				_adimlar.append([randf_range(0.4, 0.9), 0.0])
			_ses.stream = load("res://assets/ses/cizirti.ogg")
			_ses.global_position = _titre.global_position
			_ses.play()
		_adim_t = 0.0

	func _nefesler(cp: Vector3) -> void:
		var govdeler: Array = []
		var wb = w.get("walker_body")
		if wb is Node3D and (wb as Node3D).is_visible_in_tree():
			govdeler.append(wb)
		var rem = w.get("remotes")
		if rem is Dictionary:
			for r in (rem as Dictionary).values():
				var b = (r as Dictionary).get("body")
				if b is Node3D and (b as Node3D).is_visible_in_tree():
					govdeler.append(b)
		for b in govdeler:
			var g := b as Node3D
			var p := g.global_position
			if p.x < x0 or p.x > x1 or p.distance_to(cp) > 9.0:
				continue
			var id := g.get_instance_id()
			if _t < float(_nefes.get(id, 0.0)):
				continue
			_nefes[id] = _t + randf_range(3.2, 4.8)
			var ileri := g.global_basis.z.normalized()
			var agiz := p + Vector3(0, 1.58, 0) + ileri * 0.14
			var sk = g.get("_skel")
			var hb = g.get("_head_bone")
			if sk is Skeleton3D and hb is int and int(hb) >= 0:
				var hx: Transform3D = (sk as Skeleton3D).global_transform * (sk as Skeleton3D).get_bone_global_pose(int(hb))
				agiz = hx.origin + Vector3(0, 0.05, 0) + ileri * 0.12
			Efekt.nefes(self, agiz, ileri + Vector3(0, -0.25, 0))
