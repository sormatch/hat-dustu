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

static var _cache := {}


# ---------- kalite ----------

# 0 = pil dostu (gölge/parlama/huzme/leke kapalı, 3D çözünürlük %80), 1 = yüksek, 2 = ultra (+MSAA 2x).
static func apply_quality(w: Node, level: int) -> void:
	var hi := level >= 1
	var tree := w.get_tree()
	for n in tree.get_nodes_in_group(YUKSEK):
		(n as Node3D).visible = hi
	for n in tree.get_nodes_in_group(ULTRA):
		(n as Node3D).visible = level >= 2
	for n in tree.get_nodes_in_group(GOLGE):
		(n as Light3D).shadow_enabled = hi
	var env: Environment = w.get("env")
	if env:
		env.glow_enabled = hi
	var probe: ReflectionProbe = w.get("probe")
	if probe:
		probe.visible = hi
	var vp := w.get_viewport()
	vp.use_occlusion_culling = true
	vp.scaling_3d_scale = 1.0 if hi else 0.8
	vp.msaa_3d = Viewport.MSAA_2X if level >= 2 else Viewport.MSAA_DISABLED
	vp.positional_shadow_atlas_size = 4096 if level >= 2 else 2048


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
	for mi in lamp.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_boost_emission(mi as MeshInstance3D, color)
	var front := pos + normal * (bb.size.z * 0.6 + 0.04)
	halo(parent, front, color, 0.9, 0.5)
	if not with_light:
		return null
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng_
	l.omni_attenuation = 1.0
	l.light_specular = 0.7
	l.position = pos + normal * 0.35
	parent.add_child(l)
	return l


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
static func ao_ag(parent: Node3D, edges: Array, darkness := 0.5) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
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
static func kulube(w: Node3D, root: Node3D, x1: float, zmax: float) -> void:
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
	w.model("television_02", Vector3(mx + 0.2, 0.845, zmax - 0.32), PI, 0.55, NAN, root)
	w.model("metal_stool_01", Vector3(mx, 0, zmax - 1.05), 0.0, 1.0, NAN, root)
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
