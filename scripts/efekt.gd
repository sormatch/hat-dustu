# Efektler: kıvılcım, namlu alevi + duman, toz bulutu, su damlası, nefes buharı, patlama; ortam için sürekli buhar ve
# havada uçuşan toz zerreleri. Her yerden çağrılır:
#   const Efekt := preload("res://scripts/efekt.gd")
#   Efekt.kivilcim(self, konum, normal)        Efekt.namlu(silah_ucu, silah_ucu.global_transform)
#   Efekt.toz(self, zemindeki_nokta)           Efekt.damla(self, tavan_noktasi, zemin_y)
#   Efekt.nefes(self, agiz, bakis_yonu)        var h := Efekt.patlama(dunya, konum, zemin_y)  (h: yanık izi + ses için düğüm)
# Telefonda donma/takılma olmasın diye:
# - HAVUZ: her efekt türünün birkaç hazır kopyası sahnede gizli bekler; çağrılınca boştaki kopya yeniden başlatılır
#   (yeni düğüm, yeni malzeme, yeni gölgelendirici üretilmez). Kopyalar görünüm (viewport) başına bir "EfektHavuzu"nda.
# - Malzeme ve gölgelendiriciler statik önbellekte bir kez üretilir. isitma_listesi() bunların hepsini verir: açılıştaki
#   gölgelendirici ısıtması (acilis.gd) bunları çizer; hazirla() ayrıca her türden bir kopyayı sahneye koyar.
# - Parçacıklar CPUParticles3D (GPU parçacık işleme gölgelendiricisi derlenmez), az sayıda ve yumuşak kenarlı dörtgen.
# - Kalite 0 (pil dostu): parçacık sayıları yarıya iner, ışık parlaması ve enkaz azalır, ortam efektleri kapanır.
extends RefCounted

const Dunya := preload("res://scripts/dunya.gd")
const DUMAN_DOKU := "res://assets/textures/efekt/duman.png"

static var _r := {}  # paylaşılan kaynaklar (malzeme, ağ, eğri, renk geçişi)
static var _havuzlar := {}  # viewport kimliği -> Havuz


# ---------- gölgelendiriciler ----------

# Yumuşak kenarlı, gürültüyle bozulmuş kameraya dönük bulut (duman, toz, ateş topu, buhar). Parçacığın açısı
# (INSTANCE_CUSTOM.x) ve yaşı (INSTANCE_CUSTOM.y) CPUParticles3D'den gelir: yaşlandıkça kenarları aşınıp dağılır.
const PUF_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled, %s;
uniform sampler2D gurultu : repeat_enable, filter_linear_mipmap;
uniform float parlak = 1.0;
uniform float dagilma = 0.6;
uniform float sicak = 0.0;
uniform float puruz = 0.6;  // kenar düzensizliği (ateş topunda yüksek)
uniform float desen = 0.0;  // iç dalgalanma: koyu-açık lekeler (ateş topu)
varying float tohum;
varying float yas;
void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	float a = INSTANCE_CUSTOM.x;
	mat4 don = mat4(vec4(cos(a), sin(a), 0.0, 0.0), vec4(-sin(a), cos(a), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * don * mat4(vec4(s, 0.0, 0.0, 0.0), vec4(0.0, s, 0.0, 0.0), vec4(0.0, 0.0, s, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	tohum = fract(float(INSTANCE_ID) * 0.61803);
	yas = INSTANCE_CUSTOM.y;
}
void fragment() {
	vec2 o = vec2(tohum * 7.31, tohum * 3.17);
	float r = length(UV - 0.5) * 2.0;
	float n = texture(gurultu, UV * 0.75 + o + vec2(0.0, yas * 0.2)).r;
	float n2 = texture(gurultu, UV * 1.7 - o * 1.3 - vec2(yas * 0.12, 0.0)).r;
	float sekil = r + (n - 0.5) * puruz + (n2 - 0.5) * puruz * 0.45;
	float a = smoothstep(1.0, 0.15, sekil) * smoothstep(1.0, 0.62, r);
	a *= clamp(1.0 - yas * dagilma * (1.25 - (n * 0.7 + n2 * 0.3) * 1.5), 0.0, 1.0);
	vec3 c = COLOR.rgb * parlak * (0.78 + n * 0.44);
	c *= mix(1.0, 1.0 + (1.0 - r) * 1.2, sicak);
	c *= mix(1.0, 0.35 + smoothstep(0.25, 0.8, n2 * 0.6 + n * 0.4) * 1.1, desen);
	ALBEDO = c;
	ALPHA = clamp(a * COLOR.a, 0.0, 1.0);
}
"""

# Hız yönünde uzayan ince parlak çizgi (kıvılcım, su damlası): parçacığın Y ekseni hız yönüne hizalıdır
# (particle_flag_align_y); dörtgen o eksen boyunca uzar, yanı kameraya döner.
const IZ_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, world_vertex_coords;
uniform float en = 0.16;
uniform float parlak = 3.0;
void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	vec3 ax = MODEL_MATRIX[1].xyz;
	vec3 kam = normalize(CAMERA_POSITION_WORLD - c);
	vec3 yan = cross(ax, kam);
	float l = length(yan);
	yan = l > 0.00001 ? yan / l : vec3(1.0, 0.0, 0.0);
	float s = length(ax);
	VERTEX = c + yan * (UV.x - 0.5) * s * en + ax * (0.5 - UV.y);
}
void fragment() {
	float x = abs(UV.x - 0.5) * 2.0;
	float a = (1.0 - x * x) * smoothstep(0.0, 0.35, 1.0 - UV.y) * smoothstep(0.0, 0.15, UV.y);
	ALBEDO = COLOR.rgb * parlak;
	ALPHA = clamp(a * COLOR.a, 0.0, 1.0);
}
"""

# Yerde genişleyen halka (şok dalgası, su halkası): düz dörtgen, kalınlık ve renk COLOR'dan.
const HALKA_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform float kalin = 0.16;
uniform float parlak = 2.0;
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float band = smoothstep(1.0 - kalin, 1.0 - kalin * 0.35, r) * smoothstep(1.0, 1.0 - kalin * 0.35, r);
	ALBEDO = COLOR.rgb * parlak * band;
	ALPHA = clamp(band * COLOR.a, 0.0, 1.0);
}
"""


static func _shader(ad: String, kod: String) -> Shader:
	if not _r.has(ad):
		var s := Shader.new()
		s.code = kod
		_r[ad] = s
	return _r[ad]


static func _gurultu() -> Texture2D:
	if not _r.has("gurultu"):
		_r.gurultu = load(DUMAN_DOKU)
	return _r.gurultu


# Bulut malzemesi. toplamali: ateş/parıltı (ışık ekler), değilse duman/toz (örter).
static func _puf(toplamali: bool, parlak := 1.0, dagilma := 0.6, sicak := 0.0, puruz := 0.6, desen := 0.0) -> ShaderMaterial:
	var k := "puf_%s_%.2f_%.2f_%.2f_%.2f_%.2f" % [toplamali, parlak, dagilma, sicak, puruz, desen]
	if _r.has(k):
		return _r[k]
	var m := ShaderMaterial.new()
	m.shader = _shader("puf_add" if toplamali else "puf_mix", PUF_SHADER % ("blend_add, fog_disabled" if toplamali else "blend_mix"))
	m.set_shader_parameter("gurultu", _gurultu())
	m.set_shader_parameter("parlak", parlak)
	m.set_shader_parameter("dagilma", dagilma)
	m.set_shader_parameter("sicak", sicak)
	m.set_shader_parameter("puruz", puruz)
	m.set_shader_parameter("desen", desen)
	_r[k] = m
	return m


static func _iz(parlak: float, en := 0.16) -> ShaderMaterial:
	var k := "iz_%.2f_%.2f" % [parlak, en]
	if _r.has(k):
		return _r[k]
	var m := ShaderMaterial.new()
	m.shader = _shader("iz", IZ_SHADER)
	m.set_shader_parameter("parlak", parlak)
	m.set_shader_parameter("en", en)
	_r[k] = m
	return m


static func _halka(kalin: float, parlak: float) -> ShaderMaterial:
	var k := "halka_%.2f_%.2f" % [kalin, parlak]
	if _r.has(k):
		return _r[k]
	var m := ShaderMaterial.new()
	m.shader = _shader("halka", HALKA_SHADER)
	m.set_shader_parameter("kalin", kalin)
	m.set_shader_parameter("parlak", parlak)
	_r[k] = m
	return m


# Küçük parlak nokta (havadaki toz zerreleri): hazır StandardMaterial, yumuşak yuvarlak doku.
static func _zerre_mat() -> StandardMaterial3D:
	if not _r.has("zerre"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = Dunya._radial_tex()
		m.texture_repeat = false
		m.disable_fog = true
		_r.zerre = m
	return _r.zerre


static func _enkaz_mat(sicak: bool) -> StandardMaterial3D:
	var k := "enkaz_%s" % sicak
	if not _r.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#3a1a0a") if sicak else Color("#2a2622")
		m.roughness = 0.9
		if sicak:
			m.emission_enabled = true
			m.emission = Color("#ff5a10")
			m.emission_energy_multiplier = 2.5
		_r[k] = m
	return _r[k]


# Açılıştaki gölgelendirici ısıtması için: efektlerin kullandığı bütün malzemeler (acilis.gd bunları ekran dışında bir kez
# çizer, ilk patlamada / ilk kıvılcımda derleme donması olmaz).
static func isitma_listesi() -> Array:
	var out: Array = []
	for t in TURLER:
		_tur_malzemeleri(t, out)
	out.append(_zerre_mat())
	out.append(_puf(false, 1.0, 0.35))  # ortam buharı
	out.append(_enkaz_mat(false))
	out.append(_enkaz_mat(true))
	var tek := {}
	var sonuc: Array = []
	for m in out:
		if not tek.has(m):
			tek[m] = true
			sonuc.append(m)
	return sonuc


static func _tur_malzemeleri(tur: String, out: Array) -> void:
	var s := _yeni_set(tur, 1)
	for c in s.get_children():
		if c is CPUParticles3D and (c as CPUParticles3D).mesh:
			out.append((c as CPUParticles3D).mesh.surface_get_material(0))
	s.free()


# ---------- yardımcılar ----------

static func _renk(cols: Array, ofs: Array = []) -> Gradient:
	var g := Gradient.new()
	var o := PackedFloat32Array()
	for i in cols.size():
		o.append(float(ofs[i]) if ofs.size() == cols.size() else float(i) / (cols.size() - 1))
	g.offsets = o
	g.colors = PackedColorArray(cols)
	return g


static func _egri(noktalar: Array, ust := 4.0) -> Curve:
	var c := Curve.new()
	c.max_value = ust
	for p in noktalar:
		c.add_point(p)
	return c


static func _ortak(k: String, yap: Callable) -> Variant:
	if not _r.has(k):
		_r[k] = yap.call()
	return _r[k]


# Tek parçacık yayıcısı. boyut: dörtgenin kenarı (m). duz: yere yatık dörtgen (halka).
static func _yayici(s: Node3D, ad: String, sayi: int, omur: float, mat: Material, boyut: float, duz := false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = ad
	p.emitting = false
	p.one_shot = true
	p.amount = maxi(1, sayi)
	p.lifetime = omur
	p.explosiveness = 0.9
	p.randomness = 0.4
	p.local_coords = false
	p.fixed_fps = 0
	p.draw_order = CPUParticles3D.DRAW_ORDER_INDEX
	var k := "q_%.3f_%s_%d" % [boyut, duz, mat.get_instance_id()]
	var q: QuadMesh = _r.get(k)
	if not q:
		q = QuadMesh.new()
		q.size = Vector2(boyut, boyut)
		if duz:
			q.orientation = PlaneMesh.FACE_Y
		q.material = mat
		_r[k] = q
	p.mesh = q
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3.ZERO
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.add_child(p)
	return p


static func _carpan() -> float:
	return 0.5 if Dunya.seviye <= 0 else 1.0


static func _n(sayi: int) -> int:
	return maxi(1, int(round(sayi * _carpan())))


# Kısa ışık parlaması: eğri = [[sn, enerji], ...]. Kalite 0'da yalnız güçlü parlamalar (patlama) ışık verir.
static func _isik(s: Node3D, renk: Color, menzil: float, egri: Array) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = "Isik"
	l.light_color = renk
	l.omni_range = menzil
	l.omni_attenuation = 1.2
	l.shadow_enabled = false
	l.light_energy = 0.0
	l.visible = false
	l.set_meta("egri", egri)
	s.add_child(l)
	return l


# ---------- efekt türleri (her biri bir "set": aynı anda başlayan yayıcılar + isteğe bağlı ışık) ----------

const TURLER := ["kivilcim", "namlu", "toz", "toz_dokul", "damla", "nefes", "patlama"]
const SINIR := {"kivilcim": 4, "namlu": 3, "toz": 4, "toz_dokul": 3, "damla": 5, "nefes": 8, "patlama": 2}


static func _yeni_set(tur: String, seviye: int) -> Node3D:
	var s := Node3D.new()
	s.name = tur
	s.set_meta("tur", tur)
	s.visible = false
	var ince := seviye <= 0
	match tur:
		"kivilcim":
			# elektrik kıvılcımı: mavi-beyaz çakma, yerçekimiyle düşen turuncu çizgiler, ince duman
			var c := _yayici(s, "parlama", 1, 0.09, _puf(true, 2.2, 0.0, 1.0), 0.32)
			c.explosiveness = 1.0
			c.color_ramp = _ortak("r_kiv_par", func() -> Gradient: return _renk([Color(0.75, 0.88, 1.0, 1.0), Color(0.5, 0.7, 1.0, 0.0)]))
			c.scale_amount_curve = _ortak("e_kiv_par", func() -> Curve: return _egri([Vector2(0, 0.6), Vector2(1, 1.3)]))
			var k := _yayici(s, "kivilcim", 22 if not ince else 12, 0.65, _iz(4.0, 0.14), 1.0)
			k.explosiveness = 0.95
			k.spread = 60.0
			k.initial_velocity_min = 1.4
			k.initial_velocity_max = 4.2
			k.gravity = Vector3(0, -9.8, 0)
			k.damping_min = 0.3
			k.damping_max = 1.0
			k.particle_flag_align_y = true
			k.scale_amount_min = 0.03
			k.scale_amount_max = 0.08
			k.lifetime_randomness = 0.5
			k.color_ramp = _ortak("r_kiv", func() -> Gradient: return _renk([Color(1, 1, 0.9, 1), Color(1, 0.72, 0.25, 1), Color(1, 0.35, 0.05, 0.0)], [0.0, 0.35, 1.0]))
			var d := _yayici(s, "duman", 3, 1.3, _puf(false, 1.0, 0.8), 0.22)
			d.set_meta("gecikme", 0.05)
			d.explosiveness = 0.7
			d.initial_velocity_min = 0.15
			d.initial_velocity_max = 0.35
			d.gravity = Vector3(0, 0.25, 0)
			d.color_ramp = _ortak("r_kiv_d", func() -> Gradient: return _renk([Color(0.5, 0.5, 0.52, 0.0), Color(0.45, 0.45, 0.46, 0.28), Color(0.4, 0.4, 0.4, 0.0)]))
			d.scale_amount_curve = _ortak("e_buyu", func() -> Curve: return _egri([Vector2(0, 0.5), Vector2(1, 2.0)]))
			d.angle_min = -180.0
			d.angle_max = 180.0
			if not ince:
				_isik(s, Color(0.7, 0.85, 1.0), 2.6, [[0.0, 2.6], [0.05, 1.0], [0.1, 2.0], [0.18, 0.0]])
		"namlu":
			# namlu alevi (ileri doğru kısa çizgiler + parıltı), barut dumanı, birkaç kıvılcım. Yön: düğümün -Z'si.
			var f := _yayici(s, "alev", 5, 0.06, _iz(5.0, 0.42), 1.0)
			f.explosiveness = 1.0
			f.direction = Vector3.FORWARD
			f.spread = 14.0
			f.initial_velocity_min = 1.5
			f.initial_velocity_max = 3.0
			f.particle_flag_align_y = true
			f.scale_amount_min = 0.1
			f.scale_amount_max = 0.2
			f.color_ramp = _ortak("r_alev", func() -> Gradient: return _renk([Color(1, 0.95, 0.75, 1), Color(1, 0.55, 0.15, 0.0)]))
			var p := _yayici(s, "parilti", 2, 0.07, _puf(true, 2.4, 0.0, 1.0), 0.2)
			p.explosiveness = 1.0
			p.direction = Vector3.FORWARD
			p.spread = 0.0
			p.initial_velocity_min = 0.3
			p.initial_velocity_max = 0.9
			p.color_ramp = _ortak("r_alev_p", func() -> Gradient: return _renk([Color(1, 0.85, 0.5, 1), Color(1, 0.5, 0.1, 0.0)]))
			var d := _yayici(s, "duman", 8 if not ince else 5, 1.9, _puf(false, 1.0, 0.75), 0.24)
			d.explosiveness = 0.85
			d.direction = Vector3.FORWARD
			d.spread = 24.0
			d.initial_velocity_min = 0.35
			d.initial_velocity_max = 1.3
			d.damping_min = 1.5
			d.damping_max = 2.5
			d.gravity = Vector3(0, 0.22, 0)
			d.angle_min = -180.0
			d.angle_max = 180.0
			d.lifetime_randomness = 0.35
			d.color_ramp = _ortak("r_barut", func() -> Gradient: return _renk([Color(0.6, 0.58, 0.55, 0.0), Color(0.55, 0.54, 0.52, 0.32), Color(0.5, 0.5, 0.5, 0.0)], [0.0, 0.15, 1.0]))
			d.scale_amount_curve = _ortak("e_barut", func() -> Curve: return _egri([Vector2(0, 0.35), Vector2(1, 2.2)]))
			var k := _yayici(s, "kivilcim", 5, 0.25, _iz(4.0, 0.12), 1.0)
			k.explosiveness = 1.0
			k.direction = Vector3.FORWARD
			k.spread = 16.0
			k.initial_velocity_min = 4.0
			k.initial_velocity_max = 8.0
			k.gravity = Vector3(0, -6.0, 0)
			k.particle_flag_align_y = true
			k.scale_amount_min = 0.03
			k.scale_amount_max = 0.06
			k.color_ramp = _ortak("r_kiv", func() -> Gradient: return _renk([Color(1, 1, 0.9, 1), Color(1, 0.72, 0.25, 1), Color(1, 0.35, 0.05, 0.0)], [0.0, 0.35, 1.0]))
			_isik(s, Color(1.0, 0.72, 0.38), 4.0, [[0.0, 7.0], [0.06, 2.0], [0.16, 0.0]])
		"toz":
			# yerde halka gibi açılan toz bulutu (kapı çarpması, oturma): düğümün olduğu yer zemindir
			var t := _yayici(s, "toz", 12 if not ince else 7, 2.4, _puf(false, 1.0, 0.7), 0.5)
			t.explosiveness = 0.9
			t.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
			t.emission_ring_axis = Vector3.UP
			t.emission_ring_radius = 0.28
			t.emission_ring_inner_radius = 0.1
			t.emission_ring_height = 0.06
			t.direction = Vector3.RIGHT
			t.spread = 180.0
			t.flatness = 0.85
			t.initial_velocity_min = 0.35
			t.initial_velocity_max = 0.95
			t.damping_min = 0.9
			t.damping_max = 1.4
			t.gravity = Vector3(0, 0.07, 0)
			t.angle_min = -180.0
			t.angle_max = 180.0
			t.lifetime_randomness = 0.3
			t.position = Vector3(0, 0.12, 0)
			t.color_ramp = _ortak("r_toz", func() -> Gradient: return _renk([Color(0.42, 0.39, 0.34, 0.0), Color(0.42, 0.39, 0.34, 0.36), Color(0.4, 0.38, 0.34, 0.0)], [0.0, 0.18, 1.0]))
			t.scale_amount_curve = _ortak("e_toz", func() -> Curve: return _egri([Vector2(0, 0.45), Vector2(1, 1.9)]))
		"toz_dokul":
			# yukarıdan (kapı kasası, tavan) dökülen ince toz: düğüm dökülen yerin tepesi
			var t := _yayici(s, "dokul", 7 if not ince else 4, 2.2, _puf(false, 1.0, 0.8), 0.28)
			t.explosiveness = 0.6
			t.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			t.emission_box_extents = Vector3(0.45, 0.02, 0.45)
			t.direction = Vector3.DOWN
			t.spread = 12.0
			t.initial_velocity_min = 0.2
			t.initial_velocity_max = 0.5
			t.gravity = Vector3(0, -0.5, 0)
			t.angle_min = -180.0
			t.angle_max = 180.0
			t.color_ramp = _ortak("r_dokul", func() -> Gradient: return _renk([Color(0.5, 0.47, 0.42, 0.0), Color(0.5, 0.47, 0.42, 0.3), Color(0.5, 0.47, 0.42, 0.0)]))
			t.scale_amount_curve = _ortak("e_buyu", func() -> Curve: return _egri([Vector2(0, 0.5), Vector2(1, 2.0)]))
		"damla":
			# tavandan düşen damla, yerde sıçrama ve genişleyen halka. "sicrama"/"halka" konumu çağrıda zemine taşınır.
			var d := _yayici(s, "damla", 1, 0.6, _iz(1.2, 0.35), 1.0)
			d.explosiveness = 1.0
			d.spread = 0.0
			d.direction = Vector3.DOWN
			d.initial_velocity_min = 0.2
			d.initial_velocity_max = 0.2
			d.gravity = Vector3(0, -9.8, 0)
			d.particle_flag_align_y = true
			d.scale_amount_min = 0.05
			d.scale_amount_max = 0.05
			d.color_ramp = _ortak("r_damla", func() -> Gradient: return _renk([Color(0.75, 0.85, 0.95, 0.75), Color(0.75, 0.85, 0.95, 0.75)]))
			var sc := _yayici(s, "sicrama", 5 if not ince else 3, 0.32, _iz(1.4, 0.3), 1.0)
			sc.explosiveness = 1.0
			sc.spread = 55.0
			sc.initial_velocity_min = 0.5
			sc.initial_velocity_max = 1.1
			sc.gravity = Vector3(0, -9.8, 0)
			sc.particle_flag_align_y = true
			sc.scale_amount_min = 0.012
			sc.scale_amount_max = 0.024
			sc.color_ramp = _ortak("r_sicrama", func() -> Gradient: return _renk([Color(0.8, 0.88, 0.95, 0.7), Color(0.8, 0.88, 0.95, 0.0)]))
			var h := _yayici(s, "halka", 2, 0.9, _halka(0.22, 0.9), 1.0, true)
			h.explosiveness = 0.55
			h.spread = 0.0
			h.initial_velocity_min = 0.0
			h.initial_velocity_max = 0.0
			h.scale_amount_min = 1.0
			h.scale_amount_max = 1.0
			h.scale_amount_curve = _ortak("e_halka", func() -> Curve: return _egri([Vector2(0, 0.03), Vector2(1, 0.42)], 1.0))
			h.color_ramp = _ortak("r_halka", func() -> Gradient: return _renk([Color(0.7, 0.8, 0.9, 0.55), Color(0.7, 0.8, 0.9, 0.0)]))
		"nefes":
			# soğuk koridorda nefes buharı: ağızdan ileri, çok soluk. Yön: düğümün -Z'si.
			var b := _yayici(s, "buhar", 4, 1.7, _puf(false, 1.0, 0.9), 0.26)
			b.explosiveness = 0.55
			b.direction = Vector3.FORWARD
			b.spread = 16.0
			b.initial_velocity_min = 0.22
			b.initial_velocity_max = 0.42
			b.damping_min = 0.5
			b.damping_max = 0.9
			b.gravity = Vector3(0, 0.05, 0)
			b.angle_min = -180.0
			b.angle_max = 180.0
			b.color_ramp = _ortak("r_nefes", func() -> Gradient: return _renk([Color(0.86, 0.9, 0.95, 0.0), Color(0.86, 0.9, 0.95, 0.1), Color(0.86, 0.9, 0.95, 0.0)], [0.0, 0.2, 1.0]))
			b.scale_amount_curve = _ortak("e_nefes", func() -> Curve: return _egri([Vector2(0, 0.25), Vector2(1, 1.4)]))
		"patlama":
			_patlama_seti(s, ince)
	var sure := 0.0
	for c in s.get_children():
		if c is CPUParticles3D:
			sure = maxf(sure, float(c.get_meta("gecikme", 0.0)) + (c as CPUParticles3D).lifetime)
		elif c is OmniLight3D:
			var e: Array = c.get_meta("egri")
			sure = maxf(sure, float(e[e.size() - 1][0]))
	s.set_meta("sure", sure + 0.1)
	return s


# Gerçekçi patlama: göz alan parlama, turuncu ateş topu, ağır kara duman sütunu, yavaş çöken kalıcı duman,
# yerçekimiyle düşen kıvılcım çizgileri, yükselen korlar, yerde şok halkası, tavandan dökülen toz.
# Enkaz (fiziksel parçalar) ve yanık izi havuzda değil: patlama() ekler.
static func _patlama_seti(s: Node3D, ince: bool) -> void:
	# ilk parlama: yalnız 1-2 kare, sıcak beyaz-sarı, hemen turuncuya döner (düz beyaz top kalmasın)
	var cek := _yayici(s, "cekirdek", 2, 0.07, _puf(true, 1.0, 0.0, 0.5, 1.1, 0.5), 1.4)
	cek.explosiveness = 1.0
	cek.initial_velocity_max = 0.4
	cek.color_ramp = _ortak("r_cek", func() -> Gradient: return _renk([Color(1, 0.74, 0.38, 1), Color(1, 0.42, 0.1, 0.0)]))
	cek.scale_amount_curve = _ortak("e_cek", func() -> Curve: return _egri([Vector2(0, 0.6), Vector2(1, 1.3)]))
	cek.angle_min = -180.0
	cek.angle_max = 180.0
	# ateş topu: çok sayıda küçük, kenarı düzensiz, içi koyu-açık dalgalı turuncu-kırmızı bulut (pürüzsüz küre değil)
	var ates := _yayici(s, "ates", 22 if not ince else 12, 0.95, _puf(true, 0.6, 1.0, 0.1, 1.35, 0.9), 0.95)
	ates.explosiveness = 0.9
	ates.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	ates.emission_sphere_radius = 0.45
	ates.initial_velocity_min = 1.2
	ates.initial_velocity_max = 4.8
	ates.damping_min = 3.0
	ates.damping_max = 5.0
	ates.gravity = Vector3(0, 1.6, 0)
	ates.angle_min = -180.0
	ates.angle_max = 180.0
	ates.lifetime_randomness = 0.35
	ates.scale_amount_min = 0.5
	ates.scale_amount_max = 1.25
	ates.color_ramp = _ortak("r_ates", func() -> Gradient: return _renk([Color(1, 0.5, 0.15, 0.9), Color(0.9, 0.28, 0.05, 0.75), Color(0.45, 0.08, 0.02, 0.35), Color(0.1, 0.03, 0.01, 0.0)], [0.0, 0.22, 0.6, 1.0]))
	ates.scale_amount_curve = _ortak("e_ates", func() -> Curve: return _egri([Vector2(0, 0.35), Vector2(0.3, 1.4), Vector2(1, 1.9)]))
	var dum := _yayici(s, "duman", 22 if not ince else 12, 4.8, _puf(false, 1.0, 0.85), 1.1)
	dum.set_meta("gecikme", 0.08)
	dum.explosiveness = 0.65
	dum.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dum.emission_sphere_radius = 0.45
	dum.spread = 75.0
	dum.initial_velocity_min = 0.6
	dum.initial_velocity_max = 2.2
	dum.damping_min = 0.8
	dum.damping_max = 1.4
	dum.gravity = Vector3(0, 0.6, 0)
	dum.angle_min = -180.0
	dum.angle_max = 180.0
	dum.lifetime_randomness = 0.3
	dum.color_ramp = _ortak("r_dum", func() -> Gradient: return _renk([Color(0.07, 0.06, 0.05, 0.0), Color(0.09, 0.08, 0.07, 0.72), Color(0.2, 0.19, 0.18, 0.4), Color(0.28, 0.28, 0.28, 0.0)], [0.0, 0.08, 0.55, 1.0]))
	dum.scale_amount_curve = _ortak("e_dum", func() -> Curve: return _egri([Vector2(0, 0.55), Vector2(1, 2.0)]))
	var kal := _yayici(s, "kalici", 6 if not ince else 3, 9.0, _puf(false, 1.0, 0.5), 1.5)
	kal.set_meta("gecikme", 0.7)
	kal.explosiveness = 0.35
	kal.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	kal.emission_box_extents = Vector3(0.6, 0.25, 0.6)
	kal.spread = 180.0
	kal.flatness = 0.7
	kal.initial_velocity_min = 0.05
	kal.initial_velocity_max = 0.25
	kal.gravity = Vector3(0, 0.03, 0)
	kal.angle_min = -180.0
	kal.angle_max = 180.0
	kal.color_ramp = _ortak("r_kal", func() -> Gradient: return _renk([Color(0.17, 0.16, 0.15, 0.0), Color(0.17, 0.16, 0.15, 0.18), Color(0.2, 0.2, 0.2, 0.1), Color(0.22, 0.22, 0.22, 0.0)], [0.0, 0.15, 0.6, 1.0]))
	kal.scale_amount_curve = _ortak("e_kal", func() -> Curve: return _egri([Vector2(0, 0.7), Vector2(1, 1.6)]))
	# kıvılcımlar: turuncu-sarı, kısa, sönerek kısalan izler (beyaz çizgi değil)
	var kiv := _yayici(s, "kivilcim", 40 if not ince else 20, 0.9, _iz(1.4, 0.16), 1.0)
	kiv.explosiveness = 1.0
	kiv.initial_velocity_min = 4.0
	kiv.initial_velocity_max = 11.0
	kiv.damping_min = 1.5
	kiv.damping_max = 3.0
	kiv.gravity = Vector3(0, -9.8, 0)
	kiv.particle_flag_align_y = true
	kiv.scale_amount_min = 0.05
	kiv.scale_amount_max = 0.11
	kiv.lifetime_randomness = 0.6
	kiv.scale_amount_curve = _ortak("e_kiv_pat", func() -> Curve: return _egri([Vector2(0, 1.0), Vector2(1, 0.3)], 1.0))
	kiv.color_ramp = _ortak("r_kiv_pat", func() -> Gradient: return _renk([Color(1, 0.62, 0.22, 1), Color(1, 0.4, 0.06, 0.85), Color(0.7, 0.14, 0.01, 0.0)], [0.0, 0.4, 1.0]))
	if not ince:
		var kor := _yayici(s, "kor", 14, 3.2, _zerre_mat(), 0.05)
		kor.set_meta("gecikme", 0.25)
		kor.explosiveness = 0.5
		kor.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		kor.emission_sphere_radius = 0.6
		kor.spread = 60.0
		kor.initial_velocity_min = 0.3
		kor.initial_velocity_max = 1.2
		kor.damping_min = 0.4
		kor.damping_max = 0.8
		kor.gravity = Vector3(0, 0.35, 0)
		kor.color_ramp = _ortak("r_kor", func() -> Gradient: return _renk([Color(1, 0.7, 0.3, 1), Color(1, 0.35, 0.05, 0.8), Color(0.6, 0.1, 0.0, 0.0)]))
	var toz := _yayici(s, "tavan_tozu", 26 if not ince else 12, 3.0, _puf(false, 1.0, 0.7), 0.5)
	toz.set_meta("gecikme", 0.25)
	toz.explosiveness = 0.3
	toz.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	toz.emission_box_extents = Vector3(2.6, 0.08, 2.6)
	toz.direction = Vector3.DOWN
	toz.spread = 15.0
	toz.initial_velocity_min = 0.2
	toz.initial_velocity_max = 0.8
	toz.gravity = Vector3(0, -1.2, 0)
	toz.angle_min = -180.0
	toz.angle_max = 180.0
	toz.color_ramp = _ortak("r_ttoz", func() -> Gradient: return _renk([Color(0.5, 0.47, 0.43, 0.0), Color(0.5, 0.47, 0.43, 0.42), Color(0.5, 0.47, 0.43, 0.0)]))
	toz.scale_amount_curve = _ortak("e_ttoz", func() -> Curve: return _egri([Vector2(0, 0.6), Vector2(1, 1.8)]))
	# şok dalgası: düz ışık halkası yerine yerde dışa savrulan toz halkası
	var yt := _yayici(s, "yer_tozu", 14 if not ince else 8, 1.8, _puf(false, 1.0, 0.8), 0.7)
	yt.explosiveness = 1.0
	yt.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	yt.emission_ring_axis = Vector3.UP
	yt.emission_ring_radius = 0.4
	yt.emission_ring_inner_radius = 0.2
	yt.emission_ring_height = 0.05
	yt.direction = Vector3.RIGHT
	yt.spread = 180.0
	yt.flatness = 0.9
	yt.initial_velocity_min = 2.5
	yt.initial_velocity_max = 4.5
	yt.damping_min = 3.0
	yt.damping_max = 4.0
	yt.gravity = Vector3(0, 0.15, 0)
	yt.angle_min = -180.0
	yt.angle_max = 180.0
	yt.color_ramp = _ortak("r_yt", func() -> Gradient: return _renk([Color(0.38, 0.34, 0.3, 0.0), Color(0.36, 0.33, 0.29, 0.32), Color(0.36, 0.33, 0.3, 0.0)], [0.0, 0.12, 1.0]))
	yt.scale_amount_curve = _ortak("e_yt", func() -> Curve: return _egri([Vector2(0, 0.5), Vector2(1, 2.2)]))
	_isik(s, Color(1.0, 0.62, 0.3), 9.0 if ince else 15.0, [[0.0, 0.0], [0.016, 20.0], [0.08, 9.0], [0.5, 3.5], [1.5, 0.0]])


# ---------- havuz ----------

class Havuz extends Node3D:
	var E: GDScript = load("res://scripts/efekt.gd")
	var setler := {}  # tur -> Array[Node3D]
	var aktif := {}  # set -> bitiş (ms)
	var gecikenler: Array = []  # [başlama ms, CPUParticles3D]
	var isiklar := {}  # OmniLight3D -> başlama ms
	var enkaz: Array = []  # [RigidBody3D, bitiş ms]
	var seviye := 1

	func _ready() -> void:
		top_level = true
		set_process(false)

	func al(tur: String) -> Node3D:
		if seviye != E.Dunya.seviye:
			_yenile()
		var liste: Array = setler.get(tur, [])
		setler[tur] = liste
		var now := Time.get_ticks_msec()
		var en_eski: Node3D = null
		var en_eski_t := INF
		for s in liste:
			var b: float = aktif.get(s, 0.0)
			if b <= now:
				return s
			if b < en_eski_t:
				en_eski_t = b
				en_eski = s
		if liste.size() < int(E.SINIR.get(tur, 3)) or en_eski == null:
			var s: Node3D = E._yeni_set(tur, seviye)
			add_child(s)
			liste.append(s)
			return s
		return en_eski

	func _yenile() -> void:
		seviye = E.Dunya.seviye
		for tur in setler:
			for s in setler[tur]:
				(s as Node).queue_free()
		setler.clear()
		aktif.clear()
		gecikenler.clear()
		isiklar.clear()

	func baslat(s: Node3D) -> void:
		var now := Time.get_ticks_msec()
		s.visible = true
		aktif[s] = now + float(s.get_meta("sure", 1.0)) * 1000.0
		for c in s.get_children():
			if c is CPUParticles3D:
				var p := c as CPUParticles3D
				var g := float(p.get_meta("gecikme", 0.0))
				if g <= 0.0:
					p.restart()
				else:
					p.emitting = false
					gecikenler.append([now + g * 1000.0, p])
			elif c is OmniLight3D:
				isiklar[c] = now
				(c as OmniLight3D).light_energy = 0.0
				(c as OmniLight3D).visible = true
		set_process(true)

	func enkaz_al() -> RigidBody3D:
		var now := Time.get_ticks_msec()
		for e in enkaz:
			if float(e[1]) <= now:
				return e[0]
		if enkaz.size() >= 16:
			return null
		var rb := RigidBody3D.new()
		rb.collision_layer = 0  # oyuncuya çarpmaz, yalnız dünyaya
		rb.collision_mask = 1
		rb.mass = 0.2
		rb.freeze = true
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		rb.visible = false
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.06, 0.04, 0.06)
		cs.shape = bs
		rb.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm: BoxMesh = E._r.get("enkaz_kutu")
		if not bm:
			bm = BoxMesh.new()
			bm.size = Vector3(0.06, 0.04, 0.06)
			E._r.enkaz_kutu = bm
		mi.mesh = bm
		mi.material_override = E._enkaz_mat(enkaz.size() % 3 == 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rb.add_child(mi)
		add_child(rb)
		rb.global_position = Vector3(0, -200, 0)
		enkaz.append([rb, 0.0])
		return rb

	func enkaz_firlat(rb: RigidBody3D, merkez: Vector3, hiz: Vector3, sure: float) -> void:
		for e in enkaz:
			if e[0] == rb:
				e[1] = Time.get_ticks_msec() + sure * 1000.0
		var olcek := randf_range(0.6, 1.5)
		rb.get_child(1).scale = Vector3(olcek, randf_range(0.7, 1.3) * olcek, olcek)
		rb.global_position = merkez
		rb.rotation = Vector3(randf() * TAU, randf() * TAU, 0.0)
		rb.visible = true
		rb.freeze = false
		rb.sleeping = false
		rb.linear_velocity = hiz
		rb.angular_velocity = Vector3(randf_range(-18, 18), randf_range(-18, 18), randf_range(-18, 18))
		set_process(true)

	func _process(_d: float) -> void:
		var now := Time.get_ticks_msec()
		var is_var := false
		for i in range(gecikenler.size() - 1, -1, -1):
			var g: Array = gecikenler[i]
			if float(g[0]) <= now:
				if is_instance_valid(g[1]):
					(g[1] as CPUParticles3D).restart()
				gecikenler.remove_at(i)
		for l in isiklar.keys():
			var li := l as OmniLight3D
			var t := (now - float(isiklar[l])) / 1000.0
			var egri: Array = li.get_meta("egri")
			var e := 0.0
			var bitti := true
			for k in range(1, egri.size()):
				if t <= float(egri[k][0]):
					var a: Array = egri[k - 1]
					var b: Array = egri[k]
					e = lerpf(float(a[1]), float(b[1]), clampf((t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001), 0.0, 1.0))
					bitti = false
					break
			if bitti:
				li.visible = false
				isiklar.erase(l)
			else:
				li.light_energy = e
		for s in aktif.keys():
			if float(aktif[s]) <= now:
				(s as Node3D).visible = false
				aktif.erase(s)
		for e in enkaz:
			if float(e[1]) > 0.0 and float(e[1]) <= now:
				var rb := e[0] as RigidBody3D
				rb.freeze = true
				rb.visible = false
				rb.global_position = Vector3(0, -200, 0)
				e[1] = 0.0
			elif float(e[1]) > now:
				is_var = true
		if gecikenler.is_empty() and isiklar.is_empty() and aktif.is_empty() and not is_var:
			set_process(false)


# Çağıranın bulunduğu görünümün havuzu (yoksa kurulur). Havuz o görünümdeki en üst 3D düğümün altına eklenir.
static func _havuz(ctx: Node) -> Havuz:
	if not is_instance_valid(ctx) or not ctx.is_inside_tree():
		return null
	var vp := ctx.get_viewport()
	var key := vp.get_instance_id()
	var v: Variant = _havuzlar.get(key)
	if v != null and is_instance_valid(v) and (v as Node).is_inside_tree():
		return v as Havuz
	var ust: Node3D = null
	var p: Node = ctx
	while p != null and p != vp:
		if p is Node3D:
			ust = p
		p = p.get_parent()
	if ust == null:
		return null
	var h := Havuz.new()
	h.name = "EfektHavuzu"
	h.seviye = Dunya.seviye
	ust.add_child(h)
	_havuzlar[key] = h
	return h


static func _calistir(ctx: Node, tur: String, xf: Transform3D) -> Node3D:
	var h := _havuz(ctx)
	if h == null:
		return null
	var s := h.al(tur)
	s.global_transform = xf
	h.baslat(s)
	return s


# Y ekseni normal yönünde dönüşüm (kıvılcım, toz).
static func _yukari(pos: Vector3, normal: Vector3) -> Transform3D:
	var y := normal.normalized() if normal.length() > 0.01 else Vector3.UP
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	return Transform3D(Basis(x, y, x.cross(y)), pos)


# -Z ekseni yon doğrultusunda dönüşüm (namlu, nefes).
static func _ileri(pos: Vector3, yon: Vector3) -> Transform3D:
	var f := yon.normalized() if yon.length() > 0.01 else Vector3.FORWARD
	var up := Vector3.UP if absf(f.y) < 0.95 else Vector3.RIGHT
	return Transform3D(Basis.looking_at(f, up), pos)


# ---------- dışarıya açık efektler ----------

# Her türden bir kopya şimdiden kurulur (gizli): ilk kullanımda düğüm üretimi olmaz, malzemeleri açılıştaki ısıtmaya girer.
static func hazirla(ctx: Node) -> void:
	var h := _havuz(ctx)
	if h == null:
		return
	for t in TURLER:
		if (h.setler.get(t, []) as Array).is_empty():
			var s := _yeni_set(t, h.seviye)
			h.add_child(s)
			h.setler[t] = [s]
	for i in 4:
		h.enkaz_al()


# Elektrik kıvılcımı. normal: kıvılcımların fışkırdığı yön.
static func kivilcim(ctx: Node, pos: Vector3, normal := Vector3.UP) -> void:
	_calistir(ctx, "kivilcim", _yukari(pos, normal))


# Namlu alevi ve barut dumanı. ucu: namlunun ucu, -Z ileri. isik: kısa ışık parlaması.
static func namlu(ctx: Node, ucu: Transform3D, isik := true) -> void:
	var s := _calistir(ctx, "namlu", Transform3D(ucu.basis.orthonormalized(), ucu.origin))
	if s:
		# namlu kameranın dibindeyse (şakağa sıkma) duman ve alev ekranı kaplamasın: yalnız kıvılcım ve ışık
		var cam := ctx.get_viewport().get_camera_3d()
		var uzak := cam == null or cam.global_position.distance_to(ucu.origin) > 0.7
		for ad in ["duman", "alev", "parilti"]:
			(s.get_node(ad) as Node3D).visible = uzak
	if s and not isik:
		var l := s.get_node_or_null("Isik") as OmniLight3D
		if l:
			l.visible = false
			var h := _havuz(ctx)
			if h:
				h.isiklar.erase(l)


# Yerde açılan toz bulutu (zemindeki nokta). dokul: üstten de toz dökülür (kapı kasası, tavan) — yükseklik (m).
static func toz(ctx: Node, zemin: Vector3, dokul := 0.0) -> void:
	_calistir(ctx, "toz", Transform3D(Basis(Vector3.UP, randf() * TAU), zemin))
	if dokul > 0.0:
		_calistir(ctx, "toz_dokul", Transform3D(Basis(), zemin + Vector3(0, dokul, 0)))


# Tavandan düşen su damlası; zemin_y'de sıçrar ve halka açar.
static func damla(ctx: Node, ust: Vector3, zemin_y: float) -> void:
	var h := _havuz(ctx)
	if h == null:
		return
	var s := h.al("damla")
	var yuk := maxf(ust.y - zemin_y, 0.1)
	var t := sqrt(2.0 * yuk / 9.8)
	var d := s.get_node("damla") as CPUParticles3D
	d.lifetime = maxf(t - 0.02, 0.05)
	var zem := Vector3(0, zemin_y - ust.y + 0.01, 0)
	for ad in ["sicrama", "halka"]:
		var p := s.get_node(ad) as CPUParticles3D
		p.position = zem
		p.set_meta("gecikme", t)
	s.set_meta("sure", t + 1.0)
	s.global_transform = Transform3D(Basis(), ust)
	h.baslat(s)


# Nefes buharı: agiz noktasından yon doğrultusunda.
static func nefes(ctx: Node, agiz: Vector3, yon: Vector3) -> void:
	_calistir(ctx, "nefes", _ileri(agiz, yon))


# Patlama. Dönen düğüm dünyada patlama noktasında durur: yanık izini taşır (silinince iz de gider), çağıran ona
# ses vb. ekleyebilir. Parçacıklar ve ışık havuzdadır (düğüm silinse de sürer).
static func patlama(world: Node3D, pos: Vector3, floor_y := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Patlama"
	world.add_child(root)
	root.global_position = pos
	var h := _havuz(world)
	if h == null:
		return root
	var s := h.al("patlama")
	var yer := floor_y - pos.y
	(s.get_node("kalici") as Node3D).position = Vector3(0, yer + 0.55, 0)
	(s.get_node("tavan_tozu") as Node3D).position = Vector3(0, yer + 3.0, 0)
	(s.get_node("yer_tozu") as Node3D).position = Vector3(0, yer + 0.08, 0)
	s.global_transform = Transform3D(Basis(), pos)
	h.baslat(s)
	# enkaz: yere sekip yuvarlanan parçalar (havuzdan; 4,5 sn sonra gizlenir)
	for i in (12 if Dunya.seviye >= 1 else 6):
		var rb := h.enkaz_al()
		if rb == null:
			break
		var yon := Vector3(randf_range(-1, 1), randf_range(0.3, 1.2), randf_range(-1, 1)).normalized()
		h.enkaz_firlat(rb, pos + Vector3(randf_range(-0.15, 0.15), randf_range(0.0, 0.2), randf_range(-0.15, 0.15)), yon * randf_range(4.0, 9.0), 4.5)
	# kalıcı yanık izi
	var dec := Decal.new()
	dec.texture_albedo = (load("res://scripts/modlar/props.gd") as GDScript).call("scorch_texture")
	dec.size = Vector3(2.8, 0.6, 2.8)
	dec.position = Vector3(0, yer, 0)
	dec.rotation.y = randf() * TAU
	dec.cull_mask = 1
	root.add_child(dec)
	return root


# Ekran sarsıntısı (o görünümün kamerası): guc metre cinsinden en büyük kayma.
static func sarsinti(ctx: Node, sure: float, guc: float) -> void:
	if not is_instance_valid(ctx) or not ctx.is_inside_tree():
		return
	var cam := ctx.get_viewport().get_camera_3d()
	if cam == null:
		return
	var tw := cam.create_tween()
	var adim := maxi(1, int(sure / 0.04))
	for i in adim:
		var k := 1.0 - float(i) / adim
		tw.tween_property(cam, "h_offset", randf_range(-guc, guc) * k, 0.02)
		tw.parallel().tween_property(cam, "v_offset", randf_range(-guc, guc) * k, 0.02)
		tw.tween_interval(0.02)
	tw.tween_property(cam, "h_offset", 0.0, 0.05)
	tw.parallel().tween_property(cam, "v_offset", 0.0, 0.05)


# ---------- sürekli ortam efektleri (havuzsuz; kalite >= 1, dunya.gd YUKSEK grubu) ----------

# Havalandırmadan ya da borudan yavaşça çıkan buhar. yon: çıkış yönü.
static func buhar(parent: Node3D, pos: Vector3, yon := Vector3.DOWN, genislik := 0.35) -> CPUParticles3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.transform = _yukari(pos, yon)
	var p := _yayici(holder, "buhar", 9, 4.0, _puf(false, 1.0, 0.35), 0.7)
	p.one_shot = false
	p.explosiveness = 0.0
	p.randomness = 0.6
	p.preprocess = 4.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(genislik, 0.02, genislik * 0.6)
	p.spread = 22.0
	p.initial_velocity_min = 0.12
	p.initial_velocity_max = 0.3
	p.damping_min = 0.05
	p.damping_max = 0.1
	p.gravity = Vector3(0, 0.05, 0)
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.color_ramp = _ortak("r_buhar", func() -> Gradient: return _renk([Color(0.75, 0.76, 0.78, 0.0), Color(0.72, 0.73, 0.75, 0.13), Color(0.7, 0.7, 0.72, 0.0)], [0.0, 0.3, 1.0]))
	p.scale_amount_curve = _ortak("e_buhar", func() -> Curve: return _egri([Vector2(0, 0.4), Vector2(1, 2.2)]))
	p.visibility_range_end = 16.0
	p.emitting = true
	holder.add_to_group(Dunya.YUKSEK)
	return p


# Kameranın çevresinde havada asılı duran ışıklı toz zerreleri (lamba ışığında parlayan). Kamera ile yer değiştirir,
# zerreler dünyada kalır. Kalite >= 1.
static func zerreler(parent: Node3D, bolge: AABB, alan := Vector3(2.4, 1.3, 2.4), renk := Color(1.0, 0.86, 0.6, 0.3)) -> CPUParticles3D:
	var t := Takipci.new()
	t.name = "TozZerreleri"
	t.bolge = bolge
	parent.add_child(t)
	var p := _yayici(t, "zerre", 50, 9.0, _zerre_mat(), 0.012)
	p.one_shot = false
	p.explosiveness = 0.0
	p.randomness = 0.5
	p.preprocess = 9.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = alan
	p.spread = 180.0
	p.initial_velocity_min = 0.01
	p.initial_velocity_max = 0.05
	p.gravity = Vector3(0, -0.008, 0)
	p.color_ramp = _renk([Color(renk.r, renk.g, renk.b, 0.0), renk, Color(renk.r, renk.g, renk.b, 0.0)])
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.emitting = true
	t.add_to_group(Dunya.YUKSEK)
	return p


# Etkin kameranın önünde durur (zerreler kameranın çevresinde doğsun).
class Takipci extends Node3D:
	var alt_y := 0.0
	var ust_y := 3.2
	var bolge := AABB()  # ebeveynin yerel koordinatlarında; kamera bunun dışındaysa zerreler gizlenir
	var _ebeveyn: Node3D

	func _ready() -> void:
		_ebeveyn = get_parent() as Node3D
		top_level = true

	func _process(_d: float) -> void:
		if not is_visible_in_tree():
			return
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var ic := true
		if bolge.size != Vector3.ZERO and _ebeveyn:
			ic = bolge.has_point(_ebeveyn.to_local(cam.global_position))
		for c in get_children():
			(c as Node3D).visible = ic
		if ic:
			var p := cam.global_position - cam.global_basis.z * 1.6
			p.y = clampf(p.y, alt_y + 1.0, ust_y - 1.0)
			global_position = p
