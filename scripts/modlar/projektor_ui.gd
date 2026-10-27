# PROJEKTÖR AVI: gece, hapishane avlusu. Kurallar sunucuda (server/src/modes/projektor.js), burada görüntü ve ses.
# anons (28 sn): gardiyan koridorda copla kapılara vurarak yürür ("Her şey bu kadar kolay mı sandınız?!", kahkaha),
#   kapılar açılır, herkes kapısının önündeki sarı çizgiye (hizaya) geçer; geçmeyene cop. Sonra sinematik: avlunun
#   paslı demir kapısı açılır, mahkumlar sırayla avluya yürür, kulelerdeki projektörler üstlerinden geçer.
# sayim (12 sn): herkes avlu kapısının içinde; gardiyan megafonla ona kadar sayar, ışıklar kapalı: siperlere saklan.
# av: projektörler avluyu tarar (yollar tohumdan, sunucuyla aynı formül). Siperin gölgesindeki (koyu daire) güvende.
#   Işığa yakalanan elenir; gardiyan arada siperleri aratır (önce kırmızı halka + köpek + 5 sn): kaçmayan yakalanır.
# Yakalanan izleyici olur: kuleden avluya bakar.
extends "res://scripts/modlar/mod_ui.gd"

const Dunya := preload("res://scripts/dunya.gd")
const BodyScript := preload("res://scripts/model_body.gd")
const Catalog := preload("res://scripts/catalog.gd")
const AimModScript := preload("res://scripts/modlar/aim_mod.gd")
const Titresim := preload("res://scripts/titresim.gd")

# --- sunucuyla (projektor.js) aynı değerler: değiştirirsen ikisini birlikte değiştir ---
const X0 := 23.0
const X1 := 57.0
const Z0 := -13.0
const Z1 := 13.0
const GIRIS := Vector2(25.2, 0.0)
const SIPERLER := [
	Vector2(29, -9.5), Vector2(29, 9), Vector2(34.5, -2.5), Vector2(35, 6.5), Vector2(40.5, -9.5),
	Vector2(40.5, 9.5), Vector2(45.5, 1.5), Vector2(47, -8), Vector2(51.5, 7), Vector2(53, -3.5),
]
const SIPER_R := 1.1
const ISIK_R := 2.4
const KULELER := 4
const SURE_ANONS := 28.0

const DUVAR_H := 5.2
const KULE_H := 7.2  # projektörün yüksekliği
# kuleler avlunun köşelerinde (duvarın içine taşan beton ayaklar)
const KULE_YER := [Vector2(24.2, -11.8), Vector2(55.8, -11.8), Vector2(55.8, 11.8), Vector2(24.2, 11.8)]
const KORIDOR_X := 4.4  # gardiyanın koridorda yürüdüğü çizgi
const HIZA_X := 3.15  # sarı çizgi (kapıların önü)

var _avlu: Node3D
var _gardiyan: Node3D  # koridordaki / avludaki gardiyan (model_body)
var _jop: Node3D
var _gecici: Array = []  # sinematikteki geçici gövdeler
var _sine_kam: Camera3D
var _izle_kam: Camera3D
var _isik: Array = []  # her kule: {spot, disk, huzme, lamba, aktif}
var _parametre: Array = []  # [fx, fz, px, pz]
var _gecen_ms := 0  # av başından geçen (sunucunun saydığı) + yerel sayaç
var _gecen_yerel := 0
var _aktif_n := 0
var _halkalar := {}  # siper -> halka düğümü (arama uyarısı)
var _golgeler: Array = []
var _hizalar: Array = []  # sarı çizgi + numaralar
var _ben_yakalandim := false
var _yakalanan := {}  # id -> true
var _bot_yol := {}  # id -> {a, b, s, d} (yerel ms)
var _isikta := false
var _vinyet: ColorRect
var _durum: Label  # SAKLANDIN / IŞIKTASIN
var _sayac: Label  # sayımda büyük sayı
var _ortam: AudioStreamPlayer
var _env_eski := {}
var _ay: DirectionalLight3D
var _kapi_kanat: Array = []
var _intro_on := false
var _intro_kalan := 0.0
var _hiza_kontrol := false
var _sayim_t := -1.0
var _sayim_son := -1
var _kilit_spot: SpotLight3D
var _kilit_t := 0.0
var _seslerim: Array = []
var _gizlenen: Array = []  # sinematikte gizlenen arayüz katmanları (sonra yalnız bunlar geri açılır)
var _supur: Tween  # sinematikte projektörlerin kapı önünü süpürmesi


func _ready() -> void:
	_vinyet = ColorRect.new()
	_vinyet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vinyet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float k = 0.0;
void fragment() {
	float d = distance(UV, vec2(0.5));
	COLOR = vec4(0.95, 0.04, 0.02, smoothstep(0.3, 0.75, d) * k);
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_vinyet.material = mat
	_vinyet.visible = false
	root().add_child(_vinyet)
	root().move_child(_vinyet, 0)
	_durum = UI.title("", UI.FS_ORTA, GREEN)
	_durum.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_durum.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_durum.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_durum.offset_top = -170
	_durum.offset_bottom = -130
	_durum.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_durum.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_durum.visible = false
	root().add_child(_durum)
	_sayac = UI.title("", 150, GOLD)
	_sayac.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_sayac.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_sayac.offset_top = 90
	_sayac.offset_bottom = 260
	_sayac.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sayac.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sayac.visible = false
	root().add_child(_sayac)


# ---------- sunucudan gelenler ----------

func on_state(d: Dictionary, entered: bool) -> void:
	state = d
	_parametre = isiklar(int(d.get("tohum", 1)))
	for id in d.get("yakalanan", []):
		_yakalanan[int(id)] = true
	if int(me()) in _yakalanan and not _ben_yakalandim and phase() == "av":
		_beni_yakaladilar(false)
	if phase() == "av":
		_gecen_ms = int(d.get("gecen", 0))
		_gecen_yerel = Time.get_ticks_msec()
	if not entered:
		return
	match phase():
		"anons":
			_avlu_kur()
			var kalan := float(d.get("kalan_ms", SURE_ANONS * 1000.0)) / 1000.0
			if kalan > SURE_ANONS - 3.0:
				_giris_sahnesi()
			else:
				g.get_tree().create_timer(0.5).timeout.connect(show_card)
		"sayim":
			_avlu_kur()
			_giris_bitir()
			_avluya_cik()
			_sayim_baslat()
		"av":
			_avlu_kur()
			_giris_bitir()
			if w.player.global_position.x < X0 - 1.0 and not _ben_yakalandim:
				_avluya_cik()  # geri dönen / geç gelen
			_sayac.visible = false
			_av_baslat()
			_botlari_yerlestir(d.get("botlar", {}))
			var ar = d.get("arama")
			if ar is Dictionary:
				_arama_uyar(ar.get("siper", []), int(ar.get("kalan", 0)))


func on_event(d: Dictionary) -> void:
	match str(d.get("tur", "")):
		"coklu":
			for e in d.get("liste", []):
				on_event(e)
		"bot_kos":
			_bot_kos(int(d.id), d.get("a", [0, 0]), d.get("b", [0, 0]), int(d.get("gecikme", 0)), int(d.get("d", 1000)))
		"isikta":
			_isik_uyari(true)
		"karanlik":
			_isik_uyari(false)
		"arama_uyari":
			_arama_uyar(d.get("siper", []), int(d.get("ms", 5000)))
		"arama":
			_arama(d.get("siper", []), d.get("yakalanan", []))
		"yakalandi":
			_yakalandi(int(d.id), str(d.get("neden", "isik")))


func show_card() -> void:
	if not (phase() in ["anons", "sayim"]):
		return
	role_card("SAKLAN!", GOLD, "Gece avlusu. Gardiyan ona kadar sayınca projektörler yanar. Siperlerin arkasındaki koyu gölgede saklan: ışığa yakalanan elenir. Gardiyan arama yaparsa yer değiştir!")


func banner() -> Array:
	var n := (state.get("hayatta", state.get("players", [])) as Array).size()
	return [str(state.get("title", "")), tr("Hayatta: %d") % n]


func help_rows() -> Array:
	return [["egil", "Siperin koyu gölgesinde saklan"], ["engelle", "Işığa yakalanan elenir"], ["kapi", "Arama gelince yer değiştir"]]


func on_result(d: Dictionary) -> void:
	_isik_uyari(false)
	_sayac.visible = false
	_durum.visible = false
	var kazanan := int(d.get("kazanan", 0))
	var sag: Array = d.get("hayatta", [])
	var head := ""
	if kazanan == me():
		head = tr("SON KALAN SENSİN!")
	elif kazanan != 0:
		head = tr("SON KALAN: %s") % up(str(d.get("kazanan_ad", "?")))
	else:
		head = tr("%d KİŞİ YAKALANMADI") % sag.size()
	var ben_sag := int(me()) in sag.map(func(x) -> int: return int(x))
	if ben_sag:
		_ses_gardiyan("son", 0.0)
	result_modal(head, GREEN if ben_sag else RED, [tr("%d kişi yakalandı") % (d.get("yakalanan", []) as Array).size()], d, [], 1 if ben_sag else -1)
	g.get_tree().create_timer(1.8).timeout.connect(_eve_don)


func cleanup() -> void:
	_isik_uyari(false)
	_giris_bitir()
	for b in _gecici:
		if is_instance_valid(b):
			b.queue_free()
	_gecici.clear()
	for n in _hizalar:
		if is_instance_valid(n):
			n.queue_free()
	_hizalar.clear()
	if is_instance_valid(_gardiyan):
		_gardiyan.queue_free()
	if is_instance_valid(_avlu):
		_avlu.queue_free()
	_avlu = null
	_isik.clear()
	_halkalar.clear()
	if is_instance_valid(_ortam):
		_ortam.queue_free()
	for s in _seslerim:
		if is_instance_valid(s):
			s.queue_free()
	_seslerim.clear()
	_ortam_geri()
	if is_instance_valid(_sine_kam):
		_sine_kam.queue_free()
	if is_instance_valid(_izle_kam):
		_izle_kam.queue_free()
	if w and w.player:
		w.player.camera.make_current()
		w.player.busy = false
	_adlar(true)
	for id in w.remotes:
		(w.remotes[id].root as Node3D).visible = true
	if is_instance_valid(_vinyet):
		_vinyet.visible = false
	if is_instance_valid(_durum):
		_durum.visible = false
	if is_instance_valid(_sayac):
		_sayac.visible = false


func doors_open() -> bool:
	return phase() == "anons"


# ---------- ışık yolları (sunucudaki isiklar / isikMerkez / tau / aktifIsik ile aynı) ----------

static func isiklar(tohum: int) -> Array:
	var s := tohum & 0xFFFFFFFF
	if s == 0:
		s = 1
	var out := []
	for i in KULELER:
		var v := []
		for k in 4:
			s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
			v.append(float(s) / 4294967296.0)
		out.append([0.13 + v[0] * 0.07, 0.17 + v[1] * 0.08, v[2] * 6.283, v[3] * 6.283])
	return out


static func tau(gecen_ms: float) -> float:
	var t := gecen_ms / 1000.0
	return t + (t * t) / 220.0


static func isik_merkez(p: Array, gecen_ms: float) -> Vector2:
	var t := tau(gecen_ms)
	var cx := (X0 + X1) / 2.0
	var cz := (Z0 + Z1) / 2.0
	var ax := (X1 - X0) / 2.0 - 1.5
	var az := (Z1 - Z0) / 2.0 - 1.5
	return Vector2(cx + ax * sin(float(p[0]) * t + float(p[2])), cz + az * sin(float(p[1]) * t + float(p[3])))


static func aktif_isik(gecen_ms: float, n: int) -> int:
	var k := 2 if gecen_ms < 35000 else (3 if gecen_ms < 70000 else 4)
	return clampi(k - 1 if n <= 3 else k, 1, KULELER)


static func siperde(p: Vector2) -> int:
	for i in SIPERLER.size():
		if p.distance_to(SIPERLER[i]) <= SIPER_R:
			return i
	return -1


# ---------- her kare ----------

func process(delta: float) -> void:
	if not is_instance_valid(_avlu):
		return
	var ph := phase()
	if ph == "av":
		var gecen := float(_gecen_ms + (Time.get_ticks_msec() - _gecen_yerel))
		var n := aktif_isik(gecen, (state.get("players", []) as Array).size())
		if n > _aktif_n and _aktif_n > 0:
			_ses3d("projektor/projektor_ac", _kule_lamba(n - 1), 4.0)
			_ses_gardiyan("bir_projektor", 0.0)
		_aktif_n = n
		for i in _isik.size():
			var c := isik_merkez(_parametre[i], gecen) if i < _parametre.size() else Vector2((X0 + X1) / 2.0, 0)
			_isik_yerlestir(i, Vector3(c.x, 0, c.y), i < n)
	# siper durumu (ben)
	if (ph == "sayim" or ph == "av") and not _ben_yakalandim and not _intro_on:
		var pp: Vector3 = w.player.global_position
		var s := siperde(Vector2(pp.x, pp.z))
		if _isikta:
			_durum.text = tr("IŞIKTASIN! KAÇ!")
			_durum.add_theme_color_override("font_color", RED)
			_durum.visible = true
		elif s >= 0:
			_durum.text = tr("SAKLANDIN")
			_durum.add_theme_color_override("font_color", GREEN)
			_durum.visible = true
		else:
			_durum.visible = false
	# sayım sayacı
	if ph == "sayim" and _sayim_t >= 0.0:
		_sayim_t += delta
		var k := clampi(int(_sayim_t - 1.6) + 1, 0, 10)
		if k != _sayim_son and k >= 1:
			_sayim_son = k
			_ses_gardiyan("s%d" % k, 0.0)
			_sayac.text = str(k)
			_sayac.visible = true
			var tw := _sayac.create_tween()
			_sayac.scale = Vector2(1.4, 1.4)
			_sayac.pivot_offset = _sayac.size / 2.0
			tw.tween_property(_sayac, "scale", Vector2.ONE, 0.25)
	# botların koşusu
	var now := Time.get_ticks_msec()
	for id in _bot_yol.keys():
		if not w.remotes.has(id):
			continue
		var y: Dictionary = _bot_yol[id]
		var k2 := clampf(float(now - int(y.s)) / maxf(1.0, float(y.d)), 0.0, 1.0)
		if now < int(y.s):
			continue
		var a: Vector3 = y.a
		var b: Vector3 = y.b
		var r: Dictionary = w.remotes[id]
		r.target = a.lerp(b, k2)
		if k2 < 1.0:
			var dir := b - a
			r.yaw = atan2(-dir.x, -dir.z)
		else:
			_bot_yol.erase(id)
			r.body.crouched = phase() in ["sayim", "av"]
	# kilitlenen spot (yakalanana dönen kırmızımsı ışık)
	if is_instance_valid(_kilit_spot):
		_kilit_t -= delta
		if _kilit_t <= 0.0:
			_kilit_spot.queue_free()
	# giriş sahnesi
	if _intro_on:
		_giris_kare(delta)


# ---------- avlu ----------

func _avlu_kur() -> void:
	if is_instance_valid(_avlu):
		return
	_avlu = Node3D.new()
	_avlu.name = "Avlu"
	w.add_child(_avlu)
	var cx := (X0 + X1) / 2.0
	var cz := (Z0 + Z1) / 2.0
	var lx := X1 - X0
	var lz := Z1 - Z0
	# zemin: yıpranmış beton, katı
	var zemin := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(lx + 12.0, lz + 12.0)
	zemin.mesh = pm
	zemin.material_override = w._pbr("worn_concrete_floor", 0.22, 1.0, Color(0.62, 0.62, 0.64))
	zemin.position = Vector3(cx, 0, cz)
	_avlu.add_child(zemin)
	w.solid(Vector3(lx + 12.0, 1.0, lz + 12.0), Vector3(cx, -0.5, cz), 0.0, _avlu)
	for i in 14:
		var p := Vector3(randf_range(X0 + 1, X1 - 1), 0.02, randf_range(Z0 + 1, Z1 - 1))
		Dunya.leke_zemin(_avlu, ["kir", "catlak", "kir", "pas"].pick_random(), p, Vector2(randf_range(1.5, 4.0), randf_range(1.5, 4.0)), randf() * TAU)
	# duvarlar (kapı batıda, ortada 4 m boşluk)
	var duvar_m: StandardMaterial3D = w._pbr("concrete_wall_008", 0.35, 1.0, Color(0.55, 0.55, 0.58))
	var t := 0.6
	_duvar(Vector3(cx, DUVAR_H / 2, Z0 - t / 2), Vector3(lx + 2 * t, DUVAR_H, t), duvar_m)
	_duvar(Vector3(cx, DUVAR_H / 2, Z1 + t / 2), Vector3(lx + 2 * t, DUVAR_H, t), duvar_m)
	_duvar(Vector3(X1 + t / 2, DUVAR_H / 2, cz), Vector3(t, DUVAR_H, lz), duvar_m)
	var kb := 2.0  # kapı yarı genişliği
	_duvar(Vector3(X0 - t / 2, DUVAR_H / 2, (Z0 - kb) / 2.0), Vector3(t, DUVAR_H, -Z0 - kb), duvar_m)
	_duvar(Vector3(X0 - t / 2, DUVAR_H / 2, (Z1 + kb) / 2.0), Vector3(t, DUVAR_H, Z1 - kb), duvar_m)
	_duvar(Vector3(X0 - t / 2, DUVAR_H - 0.6, 0), Vector3(t, 1.2, 2 * kb), duvar_m)  # kapının üstü
	_dikenli_tel()
	# kapı: paslı demir, iki kanat (sinematikte açılır), kapalıyken katı
	_kapi_kanat.clear()
	for s in [-1.0, 1.0]:
		var piv := Node3D.new()
		piv.position = Vector3(X0 - 0.2, 0, s * kb)
		_avlu.add_child(piv)
		var k: Node3D = w.model("large_iron_gate", Vector3(0, 0, -s * kb / 2.0), PI / 2.0, 1.0, NAN, piv)
		var bb: AABB = w._bounds(k, piv)
		if bb.size.z > 0.1:
			var sc := kb / bb.size.z
			k.scale = Vector3(1.0, minf(1.4, (DUVAR_H - 1.2) / maxf(0.1, bb.size.y)), sc)
		_kapi_kanat.append(piv)
	# kapının üstünde soğuk beyaz güvenlik lambası (girişte sıraya giren mahkumlar seçilsin)
	var kl := SpotLight3D.new()
	kl.light_color = Color(0.85, 0.92, 1.0)
	kl.light_energy = 5.0
	kl.spot_range = 12.0
	kl.spot_angle = 55.0
	_avlu.add_child(kl)
	kl.global_position = Vector3(X0 + 0.6, DUVAR_H - 0.4, 0)
	kl.look_at(Vector3(X0 + 4.0, 0, 0), Vector3.UP)
	# kuleler
	for i in KULELER:
		_kule(i)
	# lambalar: kapı yanında ve doğuda, loş amber (sayımda bir şey görülsün)
	for p in [Vector3(X0 + 1.2, 0, -3.6), Vector3(X1 - 1.2, 0, 4.0)]:
		w.model("street_lamp_01", p, PI / 2.0 if p.x < cx else -PI / 2.0, 1.0, NAN, _avlu)
		var l := OmniLight3D.new()
		l.position = p + Vector3(0, 3.6, 0)
		l.light_color = Color(1.0, 0.72, 0.42)
		l.light_energy = 1.4
		l.omni_range = 9.0
		_avlu.add_child(l)
	# duvarlarda kafesli amber lambalar (koridordakilerle aynı model): duvar dipleri seçilsin
	for x in [X0 + 8.0, (X0 + X1) / 2.0, X1 - 8.0]:
		Dunya.duvar_lambasi(w, _avlu, Vector3(x, 3.2, Z0 + 0.02), Vector3(0, 0, 1), true, 1.1, 6.5)
		Dunya.duvar_lambasi(w, _avlu, Vector3(x, 3.2, Z1 - 0.02), Vector3(0, 0, -1), true, 1.1, 6.5)
	Dunya.duvar_lambasi(w, _avlu, Vector3(X1 - 0.02, 3.2, 0.0), Vector3(-1, 0, 0), true, 1.1, 6.5)
	# siperler
	for i in SIPERLER.size():
		_siper(i)
	# ay: soğuk, gölgesiz; gökte soluk disk
	_ay = DirectionalLight3D.new()
	_ay.light_color = Color(0.55, 0.66, 0.95)
	_ay.light_energy = 0.7
	_ay.rotation = Vector3(deg_to_rad(-48), deg_to_rad(28), 0)
	_ay.shadow_enabled = false
	_ay.visible = false
	_avlu.add_child(_ay)
	var disk := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(9, 9)
	disk.mesh = q
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.albedo_texture = Dunya._radial_tex()
	dm.albedo_color = Color(0.75, 0.82, 1.0)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.disable_fog = true
	disk.material_override = dm
	disk.position = Vector3(cx + 30, 70, cz - 110)
	disk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_avlu.add_child(disk)


func _duvar(pos: Vector3, size: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	_avlu.add_child(mi)
	w.solid(size, pos, 0.0, _avlu)


# Duvar üstünde dikenli tel bobini (tek çizim: çoklu örnek)
func _dikenli_tel() -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = 0.2
	tm.outer_radius = 0.225
	tm.rings = 10
	tm.ring_segments = 4
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.32, 0.31, 0.3)
	m.metallic = 0.8
	m.roughness = 0.45
	var xf := []
	var kenar := [[Vector3(X0, 0, Z0 - 0.3), Vector3(X1, 0, Z0 - 0.3)], [Vector3(X0, 0, Z1 + 0.3), Vector3(X1, 0, Z1 + 0.3)],
		[Vector3(X1 + 0.3, 0, Z0), Vector3(X1 + 0.3, 0, Z1)], [Vector3(X0 - 0.3, 0, Z0), Vector3(X0 - 0.3, 0, Z1)]]
	for k in kenar:
		var a: Vector3 = k[0]
		var b: Vector3 = k[1]
		var n := int(a.distance_to(b) / 0.32)
		var dir := (b - a).normalized()
		for i in n:
			var p := a + dir * (i * 0.32) + Vector3(0, DUVAR_H + 0.22, 0)
			var bas := Basis(Vector3.UP, atan2(dir.x, dir.z)) * Basis(Vector3.RIGHT, PI / 2.0 + randf_range(-0.25, 0.25))
			xf.append(Transform3D(bas, p))
	Dunya.coklu(_avlu, tm, m, xf)


# Gözcü kulesi: dört beton ayak, kabin, korkuluk, çatı, öne bakan projektör (her kare hedefine döner).
func _kule(i: int) -> void:
	var kp: Vector2 = KULE_YER[i]
	var k := Node3D.new()
	k.position = Vector3(kp.x, 0, kp.y)
	_avlu.add_child(k)
	var beton: StandardMaterial3D = w._pbr("rough_concrete", 0.5, 1.0, Color(0.5, 0.5, 0.52))
	var metal: StandardMaterial3D = w._pbr("rusty_metal_02", 0.6, 0.8, Color(0.6, 0.55, 0.5), "diff.jpg", 0.4)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var ayak := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.28, 6.2, 0.28)
			ayak.mesh = bm
			ayak.material_override = beton
			ayak.position = Vector3(sx * 1.0, 3.1, sz * 1.0)
			k.add_child(ayak)
	w.solid(Vector3(2.3, 6.2, 2.3), Vector3(0, 3.1, 0), 0.0, k)
	var taban := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(2.8, 0.25, 2.8)
	taban.mesh = tb
	taban.material_override = beton
	taban.position = Vector3(0, 6.3, 0)
	k.add_child(taban)
	# kabin: alt duvar + camlı üst (koyu) + çatı
	var alt := MeshInstance3D.new()
	var ab := BoxMesh.new()
	ab.size = Vector3(2.5, 1.0, 2.5)
	alt.mesh = ab
	alt.material_override = metal
	alt.position = Vector3(0, 6.95, 0)
	k.add_child(alt)
	var cam := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(2.35, 0.9, 2.35)
	cam.mesh = cb
	var camm := StandardMaterial3D.new()
	camm.albedo_color = Color(0.05, 0.07, 0.09)
	camm.roughness = 0.1
	camm.metallic = 0.6
	cam.material_override = camm
	cam.position = Vector3(0, 7.9, 0)
	k.add_child(cam)
	var cati := MeshInstance3D.new()
	var ct := BoxMesh.new()
	ct.size = Vector3(3.0, 0.18, 3.0)
	cati.mesh = ct
	cati.material_override = metal
	cati.position = Vector3(0, 8.45, 0)
	k.add_child(cati)
	# içeride kırmızı uyarı lambası (uzaktan kule seçilsin)
	var kl := OmniLight3D.new()
	kl.light_color = Color(1.0, 0.2, 0.1)
	kl.light_energy = 0.5
	kl.omni_range = 2.2
	kl.position = Vector3(0, 8.0, 0)
	k.add_child(kl)
	# projektör (avluya dönük köşede)
	var ic := Vector3((X0 + X1) / 2.0, 0, 0) - k.position
	ic.y = 0
	ic = ic.normalized()
	var lamba_yer := k.position + Vector3(ic.x * 1.35, KULE_H, ic.z * 1.35)
	var lamba := Node3D.new()
	_avlu.add_child(lamba)
	lamba.global_position = lamba_yer
	var model: Node3D = w.model("portable_searchlight", Vector3.ZERO, 0.0, 1.0, NAN, lamba)
	var mb: AABB = w._bounds(model, lamba)
	if mb.size.y > 0.05:
		model.scale = Vector3.ONE * (0.9 / mb.size.y)
	var spot := SpotLight3D.new()
	spot.light_color = Color(1.0, 0.96, 0.86)
	spot.light_energy = 9.0
	spot.spot_range = 26.0
	spot.spot_attenuation = 0.6
	spot.shadow_enabled = false
	spot.visible = false
	_avlu.add_child(spot)
	spot.global_position = lamba_yer + Vector3(0, 0.3, 0)
	# yerdeki parlak daire (oynanışta ışığın tam sınırı bu: sunucudakinden biraz geniş)
	var disk := MeshInstance3D.new()
	var dq := PlaneMesh.new()
	dq.size = Vector2(ISIK_R * 2.3, ISIK_R * 2.3)
	disk.mesh = dq
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.albedo_texture = Dunya._radial_tex()
	dm.albedo_color = Color(1.0, 0.95, 0.8, 0.85)
	dm.disable_fog = true
	disk.material_override = dm
	disk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disk.visible = false
	_avlu.add_child(disk)
	var huz: MeshInstance3D = Dunya.huzme(_avlu, Vector3.ZERO, 10.0, 0.22, ISIK_R * 0.9, Color(1.0, 0.95, 0.82), 0.22)
	huz.visible = false
	_isik.append({"spot": spot, "disk": disk, "huzme": huz, "lamba": lamba, "yer": lamba_yer})


func _kule_lamba(i: int) -> Vector3:
	return _isik[i].yer if i >= 0 and i < _isik.size() else Vector3((X0 + X1) / 2.0, KULE_H, 0)


func _isik_yerlestir(i: int, hedef: Vector3, on: bool) -> void:
	var l: Dictionary = _isik[i]
	var spot: SpotLight3D = l.spot
	var disk: MeshInstance3D = l.disk
	var huz: MeshInstance3D = l.huzme
	spot.visible = on
	disk.visible = on
	huz.visible = on
	(l.lamba as Node3D).look_at(hedef + Vector3(0, 0.5, 0), Vector3.UP)
	if not on:
		return
	var top: Vector3 = l.yer
	var uz := top.distance_to(hedef)
	spot.look_at(hedef, Vector3.UP)
	spot.spot_angle = rad_to_deg(atan(ISIK_R * 1.15 / uz))
	spot.spot_range = uz + 4.0
	disk.global_position = hedef + Vector3(0, 0.035, 0)
	# huzme: lambadan yere uzanan koni (boyu değiştikçe ölçeklenir)
	var y := (top - hedef).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	huz.global_transform = Transform3D(Basis(x, y * (uz / 10.0), x.cross(y)), (top + hedef) / 2.0)


# Siper: koyu gölge dairesi (güvenli bölge) + avlunun ortasına doğru duran örtü (sandık, varil, bariyer...).
func _siper(i: int) -> void:
	var s: Vector2 = SIPERLER[i]
	var p := Vector3(s.x, 0, s.y)
	var merkez := Vector3((X0 + X1) / 2.0, 0, 0)
	var ic := (merkez - p)
	ic.y = 0
	ic = ic.normalized()
	var yaw := atan2(ic.x, ic.z)
	var ort := p + ic * 1.15  # örtünün yeri
	var node := Node3D.new()
	node.position = ort
	node.rotation.y = yaw
	_avlu.add_child(node)
	match i % 10:
		0:
			_ortu(node, "wooden_crate_01", Vector3(-0.45, 0, 0), 0.9)
			_ortu(node, "wooden_crate_01", Vector3(0.45, 0, 0.05), 0.9)
			_ortu(node, "wooden_crate_01", Vector3(0.0, 0.9, 0.0), 0.85)
		1:
			_ortu(node, "Barrel_01", Vector3(-0.55, 0, 0), 1.1)
			_ortu(node, "Barrel_01", Vector3(0.1, 0, 0.1), 1.1)
			_ortu(node, "barrel_03", Vector3(0.7, 0, -0.05), 1.0)
		2:
			_ortu(node, "concrete_road_barrier", Vector3(-0.75, 0, 0), 1.1)
			_ortu(node, "concrete_road_barrier", Vector3(0.75, 0, 0), 1.1)
		3:
			_ortu(node, "industrial_pastic_container", Vector3(0, 0, 0), 1.3)
		4:
			_ortu(node, "old_military_crate", Vector3(-0.5, 0, 0), 0.7)
			_ortu(node, "old_military_crate", Vector3(0.5, 0, 0), 0.7)
			_ortu(node, "old_military_crate", Vector3(0.0, 0.7, 0), 0.65)
		5:
			_ortu(node, "metal_trash_can", Vector3(-0.6, 0, 0), 1.15)
			_ortu(node, "metal_trash_can", Vector3(0.2, 0, 0.05), 1.15)
			_ortu(node, "trashbag", Vector3(0.85, 0, -0.1), 0.6)
			_ortu(node, "trashbag", Vector3(-0.2, 0, -0.45), 0.55)
		6:
			_ortu(node, "wooden_crate_02", Vector3(-0.5, 0, 0), 0.95)
			_ortu(node, "old_tyre", Vector3(0.55, 0, 0), 0.25, 3)
		7:
			_ortu(node, "wooden_crate_02", Vector3(-0.45, 0, 0), 0.9)
			_ortu(node, "wooden_crate_02", Vector3(0.45, 0, 0), 0.9)
			_ortu(node, "Barrel_01", Vector3(0.0, 0, -0.75), 1.1)
		8:
			_ortu(node, "concrete_road_barrier", Vector3(0, 0, 0), 1.1)
			_ortu(node, "barrel_03", Vector3(1.0, 0, -0.2), 1.0)
		9:
			_ortu(node, "industrial_pastic_container", Vector3(-0.3, 0, 0), 1.3)
			_ortu(node, "wooden_crate_01", Vector3(0.95, 0, -0.1), 0.85)
	# gölge dairesi: siperin arkası (oyuncunun saklanacağı yer)
	var gd := MeshInstance3D.new()
	var gp := PlaneMesh.new()
	gp.size = Vector2(SIPER_R * 2.4, SIPER_R * 2.4)
	gd.mesh = gp
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_texture = Dunya._radial_tex()
	gm.albedo_color = Color(0.0, 0.0, 0.0, 0.8)
	gd.material_override = gm
	gd.position = p + Vector3(0, 0.025, 0)
	gd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_avlu.add_child(gd)
	_golgeler.append(gd)


# Örtü nesnesi: modelin boyu `boy` metreye ölçeklenir; adet > 1 ise üst üste yığılır (lastik). Katı kutu eklenir.
func _ortu(parent: Node3D, id: String, yer: Vector3, boy: float, adet := 1) -> void:
	var y := yer.y
	for k in adet:
		var m: Node3D = w.model(id, Vector3(yer.x, y, yer.z), randf_range(-0.25, 0.25), 1.0, NAN, parent)
		var bb: AABB = w._bounds(m, parent)
		if bb.size.y > 0.02:
			var sc := boy / bb.size.y
			m.scale = Vector3.ONE * sc
			bb = w._bounds(m, parent)
		y += bb.size.y
		var gx := Vector3(maxf(0.3, bb.size.x), maxf(0.3, bb.size.y), maxf(0.3, bb.size.z))
		var c := parent.to_global(bb.get_center())
		w.solid(gx, c, parent.global_rotation.y, _avlu)


# ---------- gece ortamı ----------

func _ortam_gece(on: bool) -> void:
	var env: Environment = w.env
	if on:
		if _env_eski.is_empty():
			_env_eski = {"bg": env.background_color, "amb": env.ambient_light_color, "amb_e": env.ambient_light_energy,
				"fog": env.fog_light_color, "fog_d": env.fog_density}
		env.background_color = Color(0.012, 0.018, 0.04)
		env.ambient_light_color = Color(0.36, 0.44, 0.62)
		env.ambient_light_energy = 0.62
		env.fog_light_color = Color(0.05, 0.065, 0.1)
		env.fog_density = 0.011
		if is_instance_valid(_ay):
			_ay.visible = true
		if not is_instance_valid(_ortam):
			_ortam = AudioStreamPlayer.new()
			_ortam.stream = load("res://assets/ses/projektor/gece_ortam.ogg")
			_ortam.volume_db = -4.0
			_ortam.bus = &"Efekt"
			add_child(_ortam)
			_ortam.finished.connect(_ortam.play)
			_ortam.play()
	else:
		_ortam_geri()


func _ortam_geri() -> void:
	if _env_eski.is_empty() or not w:
		return
	var env: Environment = w.env
	env.background_color = _env_eski.bg
	env.ambient_light_color = _env_eski.amb
	env.ambient_light_energy = _env_eski.amb_e
	env.fog_light_color = _env_eski.fog
	env.fog_density = _env_eski.fog_d
	_env_eski = {}


# ---------- sesler ----------

func _gardiyan_yol(ad: String) -> String:
	var tr_ses := Dil.tr_mi()
	var p := "res://assets/ses/%s/%s.ogg" % ["gardiyan" if tr_ses else "gardiyan_en", ad]
	return p if ResourceLoader.exists(p) else "res://assets/ses/gardiyan/%s.ogg" % ad


# Gardiyanın sesi: konum verilirse 3D (koridorda yanından geçerken), yoksa her yerden (megafon)
func _ses_gardiyan(ad: String, db: float, at = null) -> void:
	var path := _gardiyan_yol(ad)
	if not ResourceLoader.exists(path):
		return
	if at is Vector3 or at is Node3D:
		var p := AudioStreamPlayer3D.new()
		p.stream = load(path)
		p.volume_db = db + 4.0
		p.unit_size = 6.0
		p.max_distance = 60.0
		p.bus = &"Efekt"
		if at is Node3D:
			(at as Node3D).add_child(p)
		else:
			w.add_child(p)
			p.global_position = at
		p.finished.connect(p.queue_free)
		p.play()
		_seslerim.append(p)
		return
	var a := AudioStreamPlayer.new()
	a.stream = load(path)
	a.volume_db = db
	a.bus = &"Efekt"
	add_child(a)
	a.finished.connect(a.queue_free)
	a.play()
	_seslerim.append(a)


func _ses3d(ad: String, pos: Vector3, db: float, unit := 4.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = load("res://assets/ses/%s.ogg" % ad)
	p.volume_db = db
	p.unit_size = unit
	p.max_distance = 70.0
	p.bus = &"Efekt"
	w.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
	_seslerim.append(p)


# ---------- giriş sahnesi (anons) ----------

func _giris_sahnesi() -> void:
	_intro_on = true
	_intro_kalan = 0.0
	_hiza_kontrol = false
	var p: CharacterBody3D = w.player
	# gardiyan: koridorun kuzey ucunda belirir, güneye doğru copla kapılara vurarak yürür
	_gardiyan = BodyScript.new()
	_gardiyan.look = Catalog.sanitize({"govde": "erkek", "kiyafet": "gardiyan", "sapka": "kep", "sakal": "biyik", "sac": "kisa", "ten": 2})
	w.add_child(_gardiyan)
	_gardiyan.global_position = Vector3(KORIDOR_X, 0, 27.0)
	_gardiyan.rotation.y = 0.0  # -z yönüne yürür
	g.get_tree().create_timer(0.4).timeout.connect(_jop_ver)
	_ses3d("projektor/siren", Vector3(KORIDOR_X, 3.0, 0), -10.0, 30.0)
	g.get_tree().create_timer(0.7).timeout.connect(func() -> void: _ses_gardiyan("uyanin", 2.0, _gardiyan))
	g.get_tree().create_timer(4.6).timeout.connect(func() -> void:
		if is_instance_valid(_gardiyan):
			_ses_gardiyan("gulus", 2.0, _gardiyan)
			_gardiyan.play_emote("gul"))
	p.busy = false
	# hücrede kapının önünde, koridora bakarak başlar: gardiyan parmaklıkların önünden geçerken görünsün
	if w.my_cell >= 0 and w.my_cell < w.cells.size():
		var kapi: Vector3 = w.cells[w.my_cell].door_world()
		if p.seated:
			p.seated = false
			p.col.disabled = false
			p.head.position.y = p.EYE_STAND
		p.global_position = Vector3(kapi.x - 1.25, 0, kapi.z)
		p.velocity = Vector3.ZERO
		p.rotation.y = -PI / 2.0
		p.head.rotation.x = 0.0


# Gardiyanın sağ elinde cop (siyah, kısa silindir)
func _jop_ver() -> void:
	if not is_instance_valid(_gardiyan):
		return
	var mod: Node = AimModScript.of_body(_gardiyan)
	if not mod:
		g.get_tree().create_timer(0.3).timeout.connect(_jop_ver)
		return
	_jop = Node3D.new()
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.018
	cm.bottom_radius = 0.022
	cm.height = 0.6
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.04, 0.04, 0.045)
	m.roughness = 0.5
	mi.material_override = m
	mi.rotation.x = PI / 2.0
	mi.position = Vector3(0, 0, -0.18)
	_jop.add_child(mi)
	w.add_child(_jop)
	mod.hold(1, _jop, Transform3D.IDENTITY)


var _gardiyan_hiz := 4.4
var _vurulan := {}
var _vur_t := 0.0


func _giris_kare(delta: float) -> void:
	_intro_kalan += delta
	var t := _intro_kalan
	if not is_instance_valid(_gardiyan):
		return
	var gp := _gardiyan.global_position
	# 0.8 - 12.8 sn: koridor boyunca yürür, geçtiği her dolu hücrenin kapısına vurur
	if t > 0.8 and t < 13.0 and gp.z > -27.0:
		gp.z -= _gardiyan_hiz * delta
		_gardiyan.global_position = gp
		_gardiyan.rotation.y = 0.0
		_gardiyan.walk = 1.0
		for i in w.cells.size():
			var c: Node3D = w.cells[i]
			var dz: float = c.door_world().z
			if not _vurulan.has(i) and absf(gp.z - dz) < 0.6:
				_vurulan[i] = true
				_kapiya_vur(c)
	else:
		_gardiyan.walk = 0.0
	# kolun inişi (vuruş)
	if _vur_t > 0.0:
		_vur_t -= delta
		var mod: Node = AimModScript.of_body(_gardiyan)
		if mod:
			mod.aim = clampf(sin((0.32 - _vur_t) / 0.32 * PI), 0.0, 1.0) * 0.9
	# 12.8: kapılar açılır
	if t >= 12.8 and not _vurulan.has("kapi"):
		_vurulan["kapi"] = true
		_ses_gardiyan("kapilar", 2.0, _gardiyan)
		play("buzzer", -2.0)
		for c in w.cells:
			if not c.locked:
				c.set_door(true)
	# 14.0: hizaya! (sarı çizgi ve numaralar)
	if t >= 14.0 and not _vurulan.has("hiza"):
		_vurulan["hiza"] = true
		_ses_gardiyan("hizaya", 2.0, _gardiyan)
		_hiza_ciz()
		flash("HİZAYA GEÇ!", "Kapının önündeki sarı çizgiye geç", UI.AMBER, 2.2)
		_botlar_hizaya()
		_gardiyan.rotation.y = PI  # geri döner, koridorun ortasına yürür
	if t > 14.0 and t < 19.0:
		gp.z = move_toward(gp.z, 0.0, 3.0 * delta)
		_gardiyan.global_position = gp
		_gardiyan.rotation.y = PI
		_gardiyan.walk = 0.8 if absf(gp.z) > 0.1 else 0.0
	# 20.0: hizaya girmeyene cop
	if t >= 20.0 and not _vurulan.has("kontrol"):
		_vurulan["kontrol"] = true
		_hiza_denetle()
	# 22.0: yürüyün! karartma ve sinematik
	if t >= 22.0 and not _vurulan.has("yuru"):
		_vurulan["yuru"] = true
		_ses_gardiyan("yuru", 2.0, _gardiyan)
		_karart(0.5, _sinematik)


func _kapiya_vur(c: Node3D) -> void:
	var dw: Vector3 = c.door_world()
	_ses3d("projektor/parmaklik_%d" % randi_range(1, 3), dw + Vector3(0, 1.2, 0), 2.0, 5.0)
	_vur_t = 0.32
	var mod: Node = AimModScript.of_body(_gardiyan)
	if mod:
		mod.hand_target = dw + Vector3(0.1, 1.15, 0)
	# kapı sarsılır (hücredeki için ekran da)
	if c == w.cells[w.my_cell]:
		w._shake(0.25, 0.03)


func _hiza_yeri(cell: int) -> Vector3:
	if cell < 0 or cell >= w.cells.size():
		return Vector3(HIZA_X, 0, 0)
	var dz: float = (w.cells[cell] as Node3D).door_world().z
	return Vector3(HIZA_X, 0, dz)


func _hiza_ciz() -> void:
	var sari := StandardMaterial3D.new()
	sari.albedo_color = Color(1.0, 0.82, 0.1)
	sari.emission_enabled = true
	sari.emission = Color(1.0, 0.7, 0.05)
	sari.emission_energy_multiplier = 0.6
	var cizgi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.01, 52.0)
	cizgi.mesh = bm
	cizgi.material_override = sari
	w.add_child(cizgi)
	cizgi.global_position = Vector3(HIZA_X, 0.012, 0)
	_hizalar.append(cizgi)
	for id in state.get("players", []):
		var e: Dictionary = w._player_entry(int(id))
		var cell := int(e.get("cell", -1))
		var yer := _hiza_yeri(cell)
		var ayak := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.6, 0.012, 0.6)
		ayak.mesh = am
		ayak.material_override = sari
		w.add_child(ayak)
		ayak.global_position = yer + Vector3(0, 0.013, 0)
		_hizalar.append(ayak)
		if int(id) == me():
			var ok := Label3D.new()
			ok.text = "▼"
			ok.font_size = 96
			ok.modulate = Color(1.0, 0.85, 0.2)
			ok.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			ok.no_depth_test = true
			w.add_child(ok)
			ok.global_position = yer + Vector3(0, 1.0, 0)
			_hizalar.append(ok)


func _botlar_hizaya() -> void:
	for id in state.get("players", []):
		var pid := int(id)
		if pid == me() or not w.remotes.has(pid) or not w.is_bot(pid):
			continue
		var r: Dictionary = w.remotes[pid]
		var yer := _hiza_yeri(int(w._player_entry(pid).get("cell", -1)))
		var a: Vector3 = r.root.position
		_bot_yol[pid] = {"a": a, "b": yer, "s": Time.get_ticks_msec() + randi_range(300, 2400), "d": int(a.distance_to(yer) / 2.0 * 1000.0) + 300}


func _hiza_denetle() -> void:
	var p: CharacterBody3D = w.player
	var yer := _hiza_yeri(w.my_cell)
	if Vector2(p.global_position.x, p.global_position.z).distance_to(Vector2(yer.x, yer.z)) <= 1.1:
		return
	# hizaya girmedi: gardiyan copla vurur, oyuncu çizgiye itilir
	if is_instance_valid(_gardiyan):
		_gardiyan.global_position = yer + Vector3(1.0, 0, 0.6)
		_gardiyan.look_at(Vector3(yer.x, 0, yer.z), Vector3.UP)
		_gardiyan.rotation.y += PI
		var mod: Node = AimModScript.of_body(_gardiyan)
		if mod:
			mod.hand_target = yer + Vector3(0, 1.4, 0)
		_vur_t = 0.32
	play("projektor/jop", 2.0)
	_ses_gardiyan("hizaya_dedim", 3.0)
	screen_flash(Color(0.9, 0.05, 0.02), 0.75, 0.03, 0.5)
	w._shake(0.5, 0.08)
	Titresim.vur("guclu")
	p.global_position = yer
	p.velocity = Vector3.ZERO
	p.rotation.y = -PI / 2.0


func _karart(t: float, sonra: Callable) -> void:
	var f := ColorRect.new()
	f.color = Color(0, 0, 0, 0)
	f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root().add_child(f)
	var tw := f.create_tween()
	tw.tween_property(f, "color", Color(0, 0, 0, 1), t)
	tw.tween_callback(sonra)
	tw.tween_interval(0.25)
	tw.tween_property(f, "color", Color(0, 0, 0, 0), t)
	tw.tween_callback(f.queue_free)


# Sinematik: avlunun içinden kapıya bakan kamera; kapı açılır, mahkumlar sırayla içeri yürür, projektörler yanar.
func _sinematik() -> void:
	if phase() != "anons":
		return
	_ortam_gece(true)
	for id in w.remotes:
		(w.remotes[id].root as Node3D).visible = false
	_sine_kam = Camera3D.new()
	_sine_kam.fov = 52.0
	w.add_child(_sine_kam)
	_sine_kam.global_position = Vector3(X0 + 6.0, 1.55, 3.4)
	_sine_kam.look_at(Vector3(X0 - 1.5, 1.35, -0.4), Vector3.UP)
	_sine_kam.make_current()
	w.player.busy = true
	_gizlenen = get_tree_canvas()
	for c in _gizlenen:
		(c as CanvasLayer).visible = false
	# kapı açılır
	_ses3d("projektor/avlu_kapi", Vector3(X0, 2.0, 0), 4.0, 12.0)
	for i in _kapi_kanat.size():
		var piv: Node3D = _kapi_kanat[i]
		var s := -1.0 if i == 0 else 1.0
		piv.create_tween().tween_property(piv, "rotation:y", s * deg_to_rad(-100), 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# projektörler kapının önünü süpürür
	_supur = create_tween().set_parallel()
	for i in mini(2, _isik.size()):
		var k := i
		_supur.tween_method(func(v: float) -> void: _isik_yerlestir(k, Vector3(X0 + 2.0 + v * 4.0, 0, (-4.0 + v * 8.0) if k == 0 else (4.0 - v * 8.0)), true), 0.0, 1.0, 5.5)
	# mahkumlar sırayla yürür (ben dahil, gerçek görünüşlerle)
	var sira: Array = state.get("players", [])
	for n in sira.size():
		var id := int(sira[n])
		var b: Node3D = BodyScript.new()
		b.look = Catalog.sanitize(w._player_entry(id).get("g", {}))
		w.add_child(b)
		var bas := Vector3(X0 - 3.0 - n * 1.3, 0, 0.35 * (1 if n % 2 == 0 else -1))
		b.global_position = bas
		b.rotation.y = -PI / 2.0
		_gecici.append(b)
		var son := Vector3(X0 + 3.5 + (sira.size() - n) * 0.6, 0, bas.z)
		var tw := b.create_tween()
		tw.tween_interval(0.9)
		tw.tween_property(b, "global_position", son, son.distance_to(bas) / 1.5)
		b.set("walk", 0.6)
	# kamera yavaşça geri çekilir
	var kt := _sine_kam.create_tween()
	kt.tween_property(_sine_kam, "global_position", Vector3(X0 + 8.5, 2.3, 5.0), 5.5).set_trans(Tween.TRANS_SINE)


func get_tree_canvas() -> Array:
	var out := []
	for n in g.get_tree().root.find_children("*", "CanvasLayer", true, false):
		if (n as CanvasLayer).visible:
			out.append(n)
	return out


func _giris_bitir() -> void:
	if not _intro_on and _gecici.is_empty() and not is_instance_valid(_sine_kam):
		return
	_intro_on = false
	for b in _gecici:
		if is_instance_valid(b):
			b.queue_free()
	_gecici.clear()
	for n in _hizalar:
		if is_instance_valid(n):
			n.queue_free()
	_hizalar.clear()
	if is_instance_valid(_sine_kam):
		_sine_kam.queue_free()
	_sine_kam = null
	if is_instance_valid(_jop):
		_jop.queue_free()
	if is_instance_valid(_gardiyan):
		_gardiyan.queue_free()
	_gardiyan = null
	for n in _gizlenen:
		if is_instance_valid(n):
			(n as CanvasLayer).visible = true
	_gizlenen.clear()
	if _supur and _supur.is_valid():
		_supur.kill()
	for i in _isik.size():
		_isik_yerlestir(i, Vector3((X0 + X1) / 2.0, 0, 0), false)
	for id in w.remotes:
		(w.remotes[id].root as Node3D).visible = not _yakalanan.has(int(id))
	if w.player:
		w.player.camera.make_current()


# ---------- sayım ve av ----------

# Herkes avlu kapısının içine: oyuncu listesindeki sırayla 2 x 4 ızgara (sunucudaki GIRIS çevresi)
func _giris_yeri(id: int) -> Vector3:
	var sira: Array = state.get("players", [])
	var n := maxi(0, sira.find(id))
	return Vector3(GIRIS.x + (n / 4) * 1.3, 0, -2.25 + (n % 4) * 1.5)


func _avluya_cik() -> void:
	if _ben_yakalandim:
		return
	_ortam_gece(true)
	for c in w.cells:
		if not c.locked and c.door_open:
			c.set_door(false, true)
	for i in _kapi_kanat.size():
		(_kapi_kanat[i] as Node3D).rotation.y = 0.0
	var p: CharacterBody3D = w.player
	if p.seated:
		p.seated = false
		p.col.disabled = false
		p.head.position.y = p.EYE_STAND
	p.busy = false
	# hücrede kapının önünde, koridora bakarak başlar: gardiyan parmaklıkların önünden geçerken görünsün
	if w.my_cell >= 0 and w.my_cell < w.cells.size():
		var kapi: Vector3 = w.cells[w.my_cell].door_world()
		if p.seated:
			p.seated = false
			p.col.disabled = false
			p.head.position.y = p.EYE_STAND
		p.global_position = Vector3(kapi.x - 1.25, 0, kapi.z)
		p.velocity = Vector3.ZERO
		p.rotation.y = -PI / 2.0
		p.head.rotation.x = 0.0
	p.global_position = _giris_yeri(me())
	p.velocity = Vector3.ZERO
	p.rotation.y = -PI / 2.0
	p.head.rotation.x = 0.0
	p.camera.make_current()
	_adlar(false)
	# botlar da kapının içinde başlar
	for id in state.get("players", []):
		var pid := int(id)
		if pid == me() or not w.remotes.has(pid) or not w.is_bot(pid):
			continue
		var r: Dictionary = w.remotes[pid]
		if _bot_yol.has(pid) and int(_bot_yol[pid].s) > Time.get_ticks_msec() - 100000 and (_bot_yol[pid].b as Vector3).x > X0:
			continue  # sayım olayı geldi, koşuyor
		var y := _giris_yeri(pid)
		r.target = y
		r.root.position = y
		r.yaw = -PI / 2.0
		r.seated = false


func _sayim_baslat() -> void:
	_sayim_t = 0.0
	_sayim_son = -1
	_ses_gardiyan("sayiyorum", 0.0)
	_ses3d("projektor/kopek_uzak", Vector3(X1, 1.0, -8.0), 0.0, 10.0)
	g.get_tree().create_timer(0.6).timeout.connect(show_card)
	for gd in _golgeler:
		if is_instance_valid(gd):
			var tw := (gd as Node3D).create_tween().set_loops(3)
			tw.tween_property(gd, "scale", Vector3.ONE * 1.15, 0.4)
			tw.tween_property(gd, "scale", Vector3.ONE, 0.4)


func _av_baslat() -> void:
	_sayim_t = -1.0
	_sayac.visible = false
	close_card()
	_aktif_n = 0
	play("projektor/projektor_ac", 4.0)
	g.get_tree().create_timer(0.2).timeout.connect(func() -> void: play("projektor/projektor_ac", 2.0))
	_ses_gardiyan("geliyorum", 0.0)
	g.get_tree().create_timer(3.2).timeout.connect(func() -> void:
		if phase() == "av":
			_ses_gardiyan("isiklar", 0.0))
	w._shake(0.3, 0.02)


func _botlari_yerlestir(botlar) -> void:
	if not (botlar is Dictionary):
		return
	for k in botlar:
		var id := int(k)
		var b: Dictionary = botlar[k]
		if not w.remotes.has(id) or _yakalanan.has(id):
			continue
		var bv: Array = b.get("b", [0, 0])
		var son := Vector3(float(bv[0]), 0, float(bv[1]))
		var kalan := int(b.get("kalan", 0))
		if kalan <= 0:
			var r: Dictionary = w.remotes[id]
			r.target = son
			r.root.position = son
			r.body.crouched = true
		else:
			var av: Array = b.get("a", [0, 0])
			_bot_kos(id, av, bv, 0, kalan)


func _bot_kos(id: int, a, b, gecikme: int, d: int) -> void:
	if not w.remotes.has(id):
		return
	var r: Dictionary = w.remotes[id]
	r.body.crouched = false
	var bas: Vector3 = r.root.position
	var son := Vector3(float(b[0]), 0, float(b[1]))
	_bot_yol[id] = {"a": bas, "b": son, "s": Time.get_ticks_msec() + gecikme, "d": d}


func _isik_uyari(on: bool) -> void:
	if on == _isikta:
		return
	_isikta = on
	if not is_instance_valid(_vinyet):
		return
	_vinyet.visible = on
	var mat: ShaderMaterial = _vinyet.material
	if on:
		mat.set_shader_parameter("k", 0.0)
		var tw := _vinyet.create_tween()
		tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("k", v), 0.0, 1.0, 0.15)
		play("c4_bip", 0.0)
		play("alarm", -10.0)
		Titresim.vur("hafif")


func _arama_uyar(siperler: Array, ms: int) -> void:
	var i := randi_range(1, 3)
	_ses_gardiyan("arama_%d" % i, 0.0)
	var ben_orada := false
	var pp: Vector3 = w.player.global_position
	var benim := siperde(Vector2(pp.x, pp.z))
	for s in siperler:
		var si := int(s)
		if si < 0 or si >= SIPERLER.size():
			continue
		if si == benim and not _ben_yakalandim:
			ben_orada = true
		var sp: Vector2 = SIPERLER[si]
		var yer := Vector3(sp.x, 0, sp.y)
		_ses3d("projektor/kopek_%d" % randi_range(1, 3), yer + Vector3(0, 0.6, 0), 2.0, 6.0)
		# kırmızı nabız halkası + geri sayım
		var h := Node3D.new()
		_avlu.add_child(h)
		h.global_position = yer + Vector3(0, 0.05, 0)
		var halka := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = SIPER_R * 1.05
		tm.outer_radius = SIPER_R * 1.3
		tm.rings = 32
		tm.ring_segments = 4
		halka.mesh = tm
		var hm := StandardMaterial3D.new()
		hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hm.albedo_color = Color(1.0, 0.1, 0.05)
		hm.disable_fog = true
		halka.material_override = hm
		halka.scale = Vector3(1, 0.05, 1)
		h.add_child(halka)
		var tw := halka.create_tween().set_loops()
		tw.tween_property(halka, "scale", Vector3(1.15, 0.05, 1.15), 0.3)
		tw.tween_property(halka, "scale", Vector3(1, 0.05, 1), 0.3)
		var lb := Label3D.new()
		lb.text = tr("ARAMA")
		lb.font_size = 72
		lb.outline_size = 14
		lb.modulate = Color(1.0, 0.25, 0.15)
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.position = Vector3(0, 2.4, 0)
		h.add_child(lb)
		_halkalar[si] = h
		_geri_say(lb, Time.get_ticks_msec() + ms)
	if ben_orada:
		flash("ARAMA GELİYOR!", "Bu siperi bırak, başka yere saklan!", RED, 2.0)
		play("projektor/duduk", -2.0)


func _geri_say(lb: Label3D, son: int) -> void:
	while is_instance_valid(lb):
		var k := ceili(float(son - Time.get_ticks_msec()) / 1000.0)
		if k <= 0:
			return
		lb.text = tr("ARAMA %d") % k
		await g.get_tree().create_timer(0.2).timeout


func _arama(siperler: Array, yakalanan: Array) -> void:
	for s in siperler:
		var si := int(s)
		if _halkalar.has(si) and is_instance_valid(_halkalar[si]):
			(_halkalar[si] as Node3D).queue_free()
		_halkalar.erase(si)
		if si < 0 or si >= SIPERLER.size():
			continue
		var sp: Vector2 = SIPERLER[si]
		var yer := Vector3(sp.x, 0, sp.y)
		# el feneri gibi beyaz ışık siperin üstünde birden yanar
		var f := SpotLight3D.new()
		f.light_color = Color(0.92, 0.96, 1.0)
		f.light_energy = 12.0
		f.spot_angle = 22.0
		f.spot_range = 10.0
		_avlu.add_child(f)
		f.global_position = yer + Vector3(0.5, 5.0, 0.5)
		f.look_at(yer, Vector3.UP)
		_ses3d("projektor/fener", yer + Vector3(0, 1, 0), 2.0, 5.0)
		_ses3d("projektor/kopek_%d" % randi_range(1, 3), yer + Vector3(0, 0.6, 0), 4.0, 7.0)
		g.get_tree().create_timer(1.4).timeout.connect(f.queue_free)
	for id in yakalanan:
		_yakalandi(int(id), "arama")


func _yakalandi(id: int, _neden: String) -> void:
	if _yakalanan.has(id) and id != me():
		return
	_yakalanan[id] = true
	play("projektor/siren_kisa", -4.0)
	_ses_gardiyan("yakaladim_%d" % randi_range(1, 3), 0.0)
	if id == me():
		_beni_yakaladilar(true)
		return
	var ad := pname(id)
	flash(tr("%s YAKALANDI!") % up(ad), "", UI.AMBER, 1.4)
	if not w.remotes.has(id):
		return
	var r: Dictionary = w.remotes[id]
	var pos: Vector3 = r.root.global_position
	# en yakın kuleden kırmızımsı bir ışık ona kilitlenir, sonra gövde götürülür (gizlenir)
	_kilit(pos)
	_bot_yol.erase(id)
	var root_n: Node3D = r.root
	g.get_tree().create_timer(1.6).timeout.connect(func() -> void:
		if is_instance_valid(root_n) and _yakalanan.has(id):
			root_n.visible = false)


func _kilit(pos: Vector3) -> void:
	if is_instance_valid(_kilit_spot):
		_kilit_spot.queue_free()
	var en := 0
	var en_d := INF
	for i in _isik.size():
		var dd: float = (_isik[i].yer as Vector3).distance_to(pos)
		if dd < en_d:
			en_d = dd
			en = i
	if _isik.is_empty():
		return
	_kilit_spot = SpotLight3D.new()
	_kilit_spot.light_color = Color(1.0, 0.45, 0.35)
	_kilit_spot.light_energy = 14.0
	_kilit_spot.spot_angle = rad_to_deg(atan(1.2 / maxf(1.0, en_d)))
	_kilit_spot.spot_range = en_d + 4.0
	_avlu.add_child(_kilit_spot)
	_kilit_spot.global_position = _isik[en].yer
	_kilit_spot.look_at(pos + Vector3(0, 0.8, 0), Vector3.UP)
	_kilit_t = 1.8


func _beni_yakaladilar(efekt: bool) -> void:
	if _ben_yakalandim:
		return
	_ben_yakalandim = true
	_isik_uyari(false)
	_durum.visible = false
	var p: CharacterBody3D = w.player
	p.busy = true
	w.voice.muted = true
	if efekt:
		_kilit(p.global_position)
		screen_flash(Color(1, 0.95, 0.85), 1.0, 0.03, 0.6)
		w._shake(0.6, 0.06)
		flash("YAKALANDIN!", "Artık izleyicisin", RED, 2.2)
		Titresim.vur("guclu")
	# izleyici: kulelerden birinin tepesinden avluya bakar
	var gec := 2.0 if efekt else 0.0
	g.get_tree().create_timer(gec + 0.01).timeout.connect(func() -> void:
		if not is_instance_valid(_avlu) or not _ben_yakalandim:
			return
		_izle_kam = Camera3D.new()
		_izle_kam.fov = 62.0
		w.add_child(_izle_kam)
		_izle_kam.global_position = Vector3(X0 + 2.0, 13.0, Z0 - 2.0)
		_izle_kam.look_at(Vector3((X0 + X1) / 2.0, 0, 0), Vector3.UP)
		_izle_kam.make_current())


# Maç sırasında baş üstü adlar: saklambaçta adlar duvar arkasından kimin nerede olduğunu ele vermesin
func _adlar(on: bool) -> void:
	for id in w.remotes:
		var lb = w.remotes[id].get("label")
		if lb is Label3D:
			(lb as Label3D).visible = on


func _eve_don() -> void:
	if not w:
		return
	_isik_uyari(false)
	if is_instance_valid(_izle_kam):
		_izle_kam.queue_free()
	_ortam_geri()
	var p: CharacterBody3D = w.player
	p.busy = false
	# hücrede kapının önünde, koridora bakarak başlar: gardiyan parmaklıkların önünden geçerken görünsün
	if w.my_cell >= 0 and w.my_cell < w.cells.size():
		var kapi: Vector3 = w.cells[w.my_cell].door_world()
		if p.seated:
			p.seated = false
			p.col.disabled = false
			p.head.position.y = p.EYE_STAND
		p.global_position = Vector3(kapi.x - 1.25, 0, kapi.z)
		p.velocity = Vector3.ZERO
		p.rotation.y = -PI / 2.0
		p.head.rotation.x = 0.0
	w.voice.muted = false
	p.camera.make_current()
	p.global_position = w.cells[w.my_cell].spawn_world()
	p.velocity = Vector3.ZERO
	p.rotation.y = 0.0
	if is_instance_valid(_avlu):
		_avlu.queue_free()
	_avlu = null
	_isik.clear()
	_halkalar.clear()
	_golgeler.clear()
	if is_instance_valid(_ortam):
		_ortam.queue_free()
	for id in w.remotes:
		(w.remotes[id].root as Node3D).visible = true
	_adlar(true)
	w.place_bots()


# ---------- test (sunucusuz) ----------
# main.gd: pose=oyunici oyun=projektor ekran=giris|sayim|av|arama|yakalandi [t=<av sn>] [yer=<siper>] [ust=1] [tohum=<n>]
#   giris: gardiyan, kapılar, hiza, sinematik (gerçek sürede; --write-movie ile kaydedilir)
#   av: ışıklar t. saniyedeki yerlerinde, botlar siperlerde; yer=<siper> oyuncuyu o sipere koyar; ust=1 kuş bakışı kamera
func test_ekran(ek: String, args: Dictionary) -> void:
	for p in g.net.players:
		if int(p.id) != me():
			p["bot"] = true
			w._on_remote_state(int(p.id), {"p": [0.0, 0.0], "y": 0.0, "o": false})
	w.game_on = true
	state["tohum"] = int(args.get("tohum", "4242"))
	state["hayatta"] = [1, 2, 3, 4]
	match ek:
		"giris":
			state["phase"] = "anons"
			state["kalan_ms"] = int(SURE_ANONS * 1000)
			on_state(state, true)
		"sayim":
			state["phase"] = "sayim"
			on_state(state, true)
			var liste := []
			for id in [2, 3, 4]:
				var s: Vector2 = SIPERLER[(id * 3) % SIPERLER.size()]
				liste.append({"tur": "bot_kos", "id": id, "a": [GIRIS.x, 0], "b": [s.x, s.y], "gecikme": 500 * id, "d": 2600})
			on_event({"tur": "coklu", "liste": liste})
		_:
			state["phase"] = "av"
			state["gecen"] = int(float(args.get("t", "20")) * 1000.0)
			var botlar := {}
			for id in [2, 3, 4]:
				var s: Vector2 = SIPERLER[(id * 3) % SIPERLER.size()]
				botlar[str(id)] = {"siper": (id * 3) % SIPERLER.size(), "a": [s.x, s.y], "b": [s.x, s.y], "kalan": 0, "d": 0}
			state["botlar"] = botlar
			on_state(state, true)
			if args.has("yer"):
				var s: Vector2 = SIPERLER[int(args.yer)]
				w.player.global_position = Vector3(s.x, 0, s.y)
				w.player.rotation.y = atan2(-(((X0 + X1) / 2.0) - s.x), -(0.0 - s.y))
			if ek == "arama":
				on_event({"tur": "arama_uyari", "siper": [6, 0], "ms": 5000})
			elif ek == "yakalandi":
				on_event({"tur": "yakalandi", "id": 3, "neden": "isik"})
	if args.get("ust", "0") == "1":
		await g.get_tree().create_timer(0.3).timeout
		var cam := Camera3D.new()
		cam.fov = 60.0
		w.add_child(cam)
		cam.global_position = Vector3((X0 + X1) / 2.0, 30.0, 18.0)
		cam.look_at(Vector3((X0 + X1) / 2.0, 0, 0), Vector3.UP)
		cam.make_current()
