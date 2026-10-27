# PROJEKTÖR AVI: gece, hapishane avlusu. Kurallar sunucuda (server/src/modes/projektor.js), burada görüntü ve ses.
# anons (28 sn): gardiyan koridorda copla kapılara vurarak yürür ("Her şey bu kadar kolay mı sandınız?!", kahkaha),
#   kapılar açılır, herkes kapısının önündeki sarı çizgiye (hizaya) geçer; geçmeyene cop. Sonra sinematik: avlunun
#   paslı demir kapısı açılır, gardiyan ve köpeği kapıda bekler, mahkumlar sırayla avluya yürür.
# sayim (12 sn): herkes avlu kapısının içinde; gardiyan hoparlörden ona kadar sayar, ışıklar kapalı: siperlere saklan.
# av: kulelerdeki projektörler avluyu tarar (yollar tohumdan, sunucuyla aynı formül). Siperin arkası güvende.
#   Işık yaklaşınca uyarı (yön oku + bip), ışığın içinde kısa bir kaçma payı var, sonra yakalanılır.
#   Gardiyan arada siperleri aratır: köpek dolu sipere koşup koklar, orada kalanı ısırır; gardiyan feneriyle bakar.
# Yakalanan konuşamaz, izleyici olur: hayattakileri onların gözünden izler (alttaki oklarla oyuncu değiştirir).
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
	Vector2(29.5, -9.5), Vector2(36, -9.5), Vector2(42.5, -9.5), Vector2(49, -9.5),
	Vector2(32.5, -4), Vector2(39.5, -4.5), Vector2(46, -4), Vector2(52.5, -3.5),
	Vector2(35.5, 1.5), Vector2(42.5, 1), Vector2(49.5, 1.5),
	Vector2(30, 6.5), Vector2(38.5, 6.5), Vector2(45.5, 6), Vector2(53, 5.5),
	Vector2(34.5, 10), Vector2(41.5, 10), Vector2(48.5, 10),
]
const SIPER_R := 1.1
const ISIK_R := 2.4
const KULELER := 4
const SURE_ANONS := 28.0
const UYARI_R := ISIK_R + 3.4  # ışık bu kadar yaklaşınca "IŞIK YAKLAŞIYOR"

const DUVAR_H := 5.4
const KULE_H := 7.4  # projektörün yüksekliği
const KULE_YER := [Vector2(24.4, -11.6), Vector2(55.6, -11.6), Vector2(55.6, 11.6), Vector2(24.4, 11.6)]
const NOBET := Vector3(27.6, 0, -6.4)  # gardiyanın avludaki nöbet yeri (köpek yanında)
const KORIDOR_X := 4.4  # gardiyanın koridorda yürüdüğü çizgi
const HIZA_X := 3.15  # sarı çizgi (kapıların önü)
const KOPEK_ANIM := {"kos": "Gallop", "yuru": "Walk", "dur": "Idle", "kokla": "Idle_2_HeadLow", "isir": "Attack"}

var _avlu: Node3D
var _gardiyan: Node3D  # koridordaki / avludaki gardiyan (model_body)
var _jop: Node3D
var _fener: SpotLight3D  # avludaki gardiyanın el feneri
var _gardiyan_hedef := Vector3.INF  # avluda yürüdüğü yer
var _gecici: Array = []  # sinematikteki geçici gövdeler
var _sine_kam: Camera3D
var _izle_kam: Camera3D
var _izlenen := 0  # izleyici: kimin gözünden bakılıyor
var _izle_bar: Control
var _izle_ad: Label
var _isik: Array = []  # her kule: {spot, havuz (ışık izi), huzme, lamba, yer}
var _parametre: Array = []  # [fx, fz, px, pz]
var _gecen_ms := 0  # av başından geçen (sunucunun saydığı) + yerel sayaç
var _gecen_yerel := 0
var _aktif_n := 0
var _aramalar := {}  # siper -> {isik, yazi}
var _hizalar: Array = []  # sarı çizgi + işaret
var _ben_yakalandim := false
var _yakalanan := {}  # id -> true
var _bot_yol := {}  # id -> {a, b, s, d} (yerel ms)
var _isikta := false
var _vinyet: ColorRect
var _durum: Label  # SAKLANDIN / IŞIKTASIN / IŞIK YAKLAŞIYOR
var _sayac: Label  # sayımda büyük sayı
var _ortam: AudioStreamPlayer
var _env_eski := {}
var _ay: DirectionalLight3D
var _kapi_kanat: Array = []
var _intro_on := false
var _intro_kalan := 0.0
var _sayim_t := -1.0
var _sayim_son := -1
var _kilit_spot: SpotLight3D
var _kilit_t := 0.0
var _seslerim: Array = []
var _gizlenen: Array = []  # sinematikte gizlenen arayüz katmanları (sonra yalnız bunlar geri açılır)
var _supur: Tween
var _uyari_t := 0.0  # ışık yaklaşıyor bip aralığı
var _onceki_d := INF
var _vurulan := {}
var _vur_t := 0.0
var _gardiyan_hiz := 4.4
# köpek (Quaternius "Husky", CC0; Alman kurdu renkleri): avluda gardiyanın yanında
var _kopek: Node3D
var _kopek_ap: AnimationPlayer
var _kopek_hedef := Vector3.INF
var _kopek_anim := ""
var _kopek_is := ""  # "", "kokla", "isir"
var _kopek_is_t := 0.0
var _kopek_hav_t := 0.0


func _ready() -> void:
	_vinyet = ColorRect.new()
	_vinyet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vinyet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float k = 0.0;
uniform vec3 renk = vec3(0.95, 0.04, 0.02);
void fragment() {
	float d = distance(UV, vec2(0.5));
	COLOR = vec4(renk, smoothstep(0.3, 0.75, d) * k);
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_vinyet.material = mat
	_vinyet.visible = false
	root().add_child(_vinyet)
	root().move_child(_vinyet, 0)
	_durum = UI.title("", UI.FS_ORTA + 4, GREEN)
	_durum.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_durum.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_durum.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_durum.offset_top = -190
	_durum.offset_bottom = -140
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
	role_card("SAKLAN!", GOLD, "Gece avlusu. Gardiyan ona kadar sayınca projektörler yanar. Siperlerin arkasına saklan: ışığa yakalanan elenir. Işık yaklaşınca kaç! Köpek aramaya gelirse yer değiştir!")


func banner() -> Array:
	var n := (state.get("hayatta", state.get("players", [])) as Array).size()
	return [str(state.get("title", "")), tr("Hayatta: %d") % n]


func help_rows() -> Array:
	return [["egil", "Siperin arkasında saklan"], ["engelle", "Işığa yakalanan elenir"], ["kapi", "Köpek gelince yer değiştir"]]


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
	_izlemeyi_kapat()
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
	if is_instance_valid(_jop):
		_jop.queue_free()
	if is_instance_valid(_avlu):
		_avlu.queue_free()
	_avlu = null
	_kopek = null
	_isik.clear()
	_aramalar.clear()
	if is_instance_valid(_ortam):
		_ortam.queue_free()
	for s in _seslerim:
		if is_instance_valid(s):
			s.queue_free()
	_seslerim.clear()
	_ortam_geri()
	if is_instance_valid(_sine_kam):
		_sine_kam.queue_free()
	if w and w.player:
		w.player.camera.make_current()
		w.player.busy = false
		w.voice.muted = false
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


func _gecen() -> float:
	return float(_gecen_ms + (Time.get_ticks_msec() - _gecen_yerel))


# ---------- her kare ----------

func process(delta: float) -> void:
	if not is_instance_valid(_avlu):
		return
	var ph := phase()
	if ph == "av":
		var gecen := _gecen()
		var n := aktif_isik(gecen, (state.get("players", []) as Array).size())
		if n > _aktif_n and _aktif_n > 0:
			_ses3d("projektor/projektor_ac", _kule_lamba(n - 1), 4.0)
			_ses_gardiyan("bir_projektor", 0.0)
		_aktif_n = n
		for i in _isik.size():
			var c := isik_merkez(_parametre[i], gecen) if i < _parametre.size() else Vector2((X0 + X1) / 2.0, 0)
			_isik_yerlestir(i, Vector3(c.x, 0, c.y), i < n)
	if (ph == "sayim" or ph == "av") and not _ben_yakalandim and not _intro_on:
		_durum_guncelle(delta, ph)
	# sayım sayacı
	if ph == "sayim" and _sayim_t >= 0.0:
		_sayim_t += delta
		var k := clampi(int(_sayim_t - 1.6) + 1, 0, 10)
		if k != _sayim_son and k >= 1:
			_sayim_son = k
			_ses_gardiyan("s%d" % k, 0.0)
			_sayac.text = str(k)
			_sayac.visible = true
			_sayac.pivot_offset = _sayac.size / 2.0
			_sayac.scale = Vector2(1.4, 1.4)
			_sayac.create_tween().tween_property(_sayac, "scale", Vector2.ONE, 0.25)
	_botlar_kare()
	_kopek_kare(delta)
	_gardiyan_kare(delta)
	if is_instance_valid(_kilit_spot):
		_kilit_t -= delta
		if _kilit_t <= 0.0:
			_kilit_spot.queue_free()
	if _intro_on:
		_giris_kare(delta)
	if _ben_yakalandim:
		_izle_kare()


# Alttaki durum yazısı: saklandın / ışık yaklaşıyor (yönüyle) / ışıktasın
func _durum_guncelle(delta: float, ph: String) -> void:
	var pp: Vector3 = w.player.global_position
	var p2 := Vector2(pp.x, pp.z)
	var s := siperde(p2)
	_uyari_t -= delta
	if _isikta:
		_yazi(tr("IŞIKTASIN! KAÇ!"), RED)
		return
	if ph == "av" and s < 0:
		# en yakın ışık (şimdi ve yarım saniye sonra): yaklaşıyorsa uyar, hangi yandan geldiğini göster
		var gecen := _gecen()
		var en_d := INF
		var en_c := Vector2.ZERO
		for i in mini(_aktif_n, _parametre.size()):
			var c := isik_merkez(_parametre[i], gecen)
			var c2 := isik_merkez(_parametre[i], gecen + 500.0)
			var dd := minf(p2.distance_to(c), p2.distance_to(c2) + 0.4)
			if dd < en_d:
				en_d = dd
				en_c = c
		var yaklasiyor := en_d < _onceki_d + 0.02
		_onceki_d = en_d
		if en_d < UYARI_R and yaklasiyor:
			var ok := _yon_oku(en_c)
			_yazi(ok[0] + tr("IŞIK YAKLAŞIYOR!") + ok[1], UI.AMBER)
			if _uyari_t <= 0.0:
				_uyari_t = clampf((en_d - ISIK_R) / 3.0, 0.25, 0.9)
				play("projektor/isik_yaklasiyor", -4.0 if en_d > ISIK_R + 1.5 else 0.0)
			return
	if s >= 0:
		_yazi(tr("SAKLANDIN"), GREEN)
	else:
		_durum.visible = false


# Işığın oyuncuya göre yönü: ["◀ ", ""] / ["", " ▶"] / ["▲ ", ""] / ["▼ ", ""]
func _yon_oku(c: Vector2) -> Array:
	var p: CharacterBody3D = w.player
	var ileri := -p.global_transform.basis.z
	var sag := p.global_transform.basis.x
	var d := Vector3(c.x - p.global_position.x, 0, c.y - p.global_position.z)
	var f := d.dot(ileri)
	var r := d.dot(sag)
	if absf(r) > absf(f):
		return ["", "  ▶"] if r > 0 else ["◀  ", ""]
	return ["▲  ", ""] if f > 0 else ["▼  ", ""]


func _yazi(t: String, c: Color) -> void:
	_durum.text = t
	_durum.add_theme_color_override("font_color", c)
	_durum.visible = true


# ---------- avlu ----------

func _kalite() -> int:
	return int(w.profile.settings.get("kalite", 1)) if w.profile else 1


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
	# zemin: yıpranmış asfalt-beton, kati
	var zemin := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(lx + 14.0, lz + 14.0)
	zemin.mesh = pm
	zemin.material_override = w._pbr("worn_concrete_floor", 0.2, 1.0, Color(0.5, 0.5, 0.52))
	zemin.position = Vector3(cx, 0, cz)
	_avlu.add_child(zemin)
	w.solid(Vector3(lx + 14.0, 1.0, lz + 14.0), Vector3(cx, -0.5, cz), 0.0, _avlu)
	for i in 22:
		var p := Vector3(randf_range(X0 + 1, X1 - 1), 0.02, randf_range(Z0 + 1, Z1 - 1))
		Dunya.leke_zemin(_avlu, ["kir", "catlak", "kir", "pas"].pick_random(), p, Vector2(randf_range(1.5, 4.5), randf_range(1.5, 4.5)), randf() * TAU)
	_saha_cizgileri()
	_duvarlar()
	_dikenli_tel()
	_kapi()
	for i in KULELER:
		_kule(i)
	# lambalar: sokak lambası (kapı ve doğu), duvarlarda kafesli amber lambalar
	for p in [Vector3(X0 + 1.4, 0, -3.8), Vector3(X1 - 1.4, 0, 4.2)]:
		w.model("street_lamp_01", p, PI / 2.0 if p.x < cx else -PI / 2.0, 1.0, NAN, _avlu)
		var l := OmniLight3D.new()
		l.position = p + Vector3(0, 3.7, 0)
		l.light_color = Color(1.0, 0.7, 0.4)
		l.light_energy = 1.5
		l.omni_range = 9.5
		_avlu.add_child(l)
	for x in [X0 + 8.0, cx, X1 - 8.0]:
		Dunya.duvar_lambasi(w, _avlu, Vector3(x, 3.4, Z0 + 0.02), Vector3(0, 0, 1), true, 1.1, 6.5)
		Dunya.duvar_lambasi(w, _avlu, Vector3(x, 3.4, Z1 - 0.02), Vector3(0, 0, -1), true, 1.1, 6.5)
	Dunya.duvar_lambasi(w, _avlu, Vector3(X1 - 0.02, 3.4, 0.0), Vector3(-1, 0, 0), true, 1.1, 6.5)
	for i in SIPERLER.size():
		_siper(i)
	_suslemeler()
	# ay: soğuk; yüksek kalitede gölgeli
	_ay = DirectionalLight3D.new()
	_ay.light_color = Color(0.55, 0.66, 0.95)
	_ay.light_energy = 0.7
	_ay.rotation = Vector3(deg_to_rad(-48), deg_to_rad(28), 0)
	_ay.shadow_enabled = _kalite() >= 2
	_ay.directional_shadow_max_distance = 40.0
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
	_gardiyan_avluda()
	_kopek_kur()


func _kutu(parent: Node3D, size: Vector3, pos: Vector3, m: Material, kati := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	if kati:
		w.solid(size, pos, 0.0, parent)
	return mi


func _boru(parent: Node3D, a: Vector3, b: Vector3, r: float, m: Material) -> void:
	Dunya.boru(parent, a, b, r, m, 8)


# Basketbol sahası çizgileri (doğu yarı) ve pota
func _saha_cizgileri() -> void:
	var boya := StandardMaterial3D.new()
	boya.albedo_color = Color(0.82, 0.8, 0.72)
	boya.roughness = 0.9
	var x0 := 40.5
	var x1 := 56.4
	var z0 := -7.5
	var z1 := 7.5
	var ince := 0.09
	for c in [[Vector3(x0, 0, z0), Vector3(x1, 0, z0)], [Vector3(x0, 0, z1), Vector3(x1, 0, z1)], [Vector3(x0, 0, z0), Vector3(x0, 0, z1)]]:
		var a: Vector3 = c[0]
		var b: Vector3 = c[1]
		var orta := (a + b) / 2.0 + Vector3(0, 0.006, 0)
		var boy := a.distance_to(b)
		_kutu(_avlu, Vector3(boy if absf(a.z - b.z) < 0.01 else ince, 0.004, boy if absf(a.x - b.x) < 0.01 else ince), orta, boya)
	# orta çember ve serbest atış alanı (ince halkalar)
	for h in [[Vector3(x0, 0.006, 0), 1.8], [Vector3(x1 - 5.8, 0.006, 0), 1.8]]:
		var tm := TorusMesh.new()
		tm.inner_radius = float(h[1]) - ince
		tm.outer_radius = float(h[1])
		tm.rings = 48
		tm.ring_segments = 3
		var mi := MeshInstance3D.new()
		mi.mesh = tm
		mi.material_override = boya
		mi.scale = Vector3(1, 0.02, 1)
		mi.position = h[0]
		_avlu.add_child(mi)
	_kutu(_avlu, Vector3(5.8, 0.004, ince), Vector3(x1 - 2.9, 0.006, -1.8), boya)
	_kutu(_avlu, Vector3(5.8, 0.004, ince), Vector3(x1 - 2.9, 0.006, 1.8), boya)
	# pota: direk, pano, çember (doğu duvarının önünde)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.25, 0.27, 0.3)
	metal.metallic = 0.7
	metal.roughness = 0.45
	_boru(_avlu, Vector3(X1 - 0.5, 0, 0), Vector3(X1 - 0.5, 3.3, 0), 0.07, metal)
	_boru(_avlu, Vector3(X1 - 0.5, 3.2, 0), Vector3(X1 - 1.2, 3.2, 0), 0.05, metal)
	var pano := StandardMaterial3D.new()
	pano.albedo_color = Color(0.85, 0.85, 0.82)
	pano.roughness = 0.6
	_kutu(_avlu, Vector3(0.05, 1.05, 1.8), Vector3(X1 - 1.25, 3.35, 0), pano)
	var cember := MeshInstance3D.new()
	var ct := TorusMesh.new()
	ct.inner_radius = 0.21
	ct.outer_radius = 0.235
	ct.rings = 24
	ct.ring_segments = 6
	cember.mesh = ct
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.85, 0.3, 0.08)
	cm.metallic = 0.6
	cember.material_override = cm
	cember.position = Vector3(X1 - 1.52, 3.05, 0)
	_avlu.add_child(cember)
	w.solid(Vector3(0.3, 3.3, 0.3), Vector3(X1 - 0.5, 1.65, 0), 0.0, _avlu)


# Yüksek beton duvarlar: payandalar, üst başlık, kir lekeleri. Kapı batıda, ortada 4 m.
func _duvarlar() -> void:
	var cx := (X0 + X1) / 2.0
	var lx := X1 - X0
	var lz := Z1 - Z0
	var m: StandardMaterial3D = w._pbr("concrete_wall_008", 0.33, 1.0, Color(0.5, 0.5, 0.53))
	var bas: StandardMaterial3D = w._pbr("rough_concrete", 0.5, 1.0, Color(0.42, 0.42, 0.45))
	var t := 0.7
	var kb := 2.0
	var parca := [
		[Vector3(cx, DUVAR_H / 2, Z0 - t / 2), Vector3(lx + 2 * t, DUVAR_H, t)],
		[Vector3(cx, DUVAR_H / 2, Z1 + t / 2), Vector3(lx + 2 * t, DUVAR_H, t)],
		[Vector3(X1 + t / 2, DUVAR_H / 2, 0), Vector3(t, DUVAR_H, lz)],
		[Vector3(X0 - t / 2, DUVAR_H / 2, (Z0 - kb) / 2.0), Vector3(t, DUVAR_H, -Z0 - kb)],
		[Vector3(X0 - t / 2, DUVAR_H / 2, (Z1 + kb) / 2.0), Vector3(t, DUVAR_H, Z1 - kb)],
	]
	for p in parca:
		_kutu(_avlu, p[1], p[0], m, true)
		# üst başlık: biraz taşan beton kuşak
		var b: Vector3 = p[1]
		_kutu(_avlu, Vector3(b.x + 0.25, 0.3, b.z + 0.25), (p[0] as Vector3) + Vector3(0, DUVAR_H / 2 + 0.15, 0), bas)
	_kutu(_avlu, Vector3(t, 1.3, 2 * kb), Vector3(X0 - t / 2, DUVAR_H - 0.65, 0), m)  # kapının üstü
	# payandalar: içeriye taşan dikey beton kolonlar (4 m arayla)
	var x := X0 + 3.0
	while x < X1 - 1.0:
		for zz in [Z0 + 0.18, Z1 - 0.18]:
			_kutu(_avlu, Vector3(0.55, DUVAR_H, 0.36), Vector3(x, DUVAR_H / 2, zz), bas, true)
		x += 4.0
	var z := Z0 + 3.0
	while z < Z1 - 1.0:
		_kutu(_avlu, Vector3(0.36, DUVAR_H, 0.55), Vector3(X1 - 0.18, DUVAR_H / 2, z), bas, true)
		z += 4.0
	# duvar diplerinde kir ve pas akıntısı
	for i in 16:
		var kenar := randi() % 3
		var pos: Vector3
		var nrm: Vector3
		if kenar == 0:
			pos = Vector3(randf_range(X0 + 1, X1 - 1), randf_range(0.8, 3.5), Z0 + 0.02)
			nrm = Vector3(0, 0, 1)
		elif kenar == 1:
			pos = Vector3(randf_range(X0 + 1, X1 - 1), randf_range(0.8, 3.5), Z1 - 0.02)
			nrm = Vector3(0, 0, -1)
		else:
			pos = Vector3(X1 - 0.02, randf_range(0.8, 3.5), randf_range(Z0 + 1, Z1 - 1))
			nrm = Vector3(-1, 0, 0)
		Dunya.leke_duvar(_avlu, ["kir", "pas"].pick_random(), pos, nrm, Vector2(randf_range(1.5, 3.5), randf_range(1.5, 3.0)))


# Duvar üstünde dikenli tel bobini (çoklu örnek: tek çizim), iki sıra
func _dikenli_tel() -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = 0.24
	tm.outer_radius = 0.265
	tm.rings = 12
	tm.ring_segments = 4
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.36, 0.35, 0.34)
	m.metallic = 0.85
	m.roughness = 0.4
	var xf := []
	var kenar := [[Vector3(X0 - 0.35, 0, Z0 - 0.35), Vector3(X1 + 0.35, 0, Z0 - 0.35)], [Vector3(X0 - 0.35, 0, Z1 + 0.35), Vector3(X1 + 0.35, 0, Z1 + 0.35)],
		[Vector3(X1 + 0.35, 0, Z0), Vector3(X1 + 0.35, 0, Z1)], [Vector3(X0 - 0.35, 0, Z0), Vector3(X0 - 0.35, 0, Z1)]]
	for k in kenar:
		var a: Vector3 = k[0]
		var b: Vector3 = k[1]
		var n := int(a.distance_to(b) / 0.22)
		var dir := (b - a).normalized()
		for i in n:
			var p := a + dir * (i * 0.22) + Vector3(0, DUVAR_H + 0.55, 0)
			var bas := Basis(Vector3.UP, atan2(dir.x, dir.z)) * Basis(Vector3.RIGHT, PI / 2.0 + 0.35 * sin(i * 1.7))
			xf.append(Transform3D(bas, p))
	Dunya.coklu(_avlu, tm, m, xf)
	# bobini taşıyan direkler
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.2, 0.2, 0.22)
	dm.metallic = 0.6
	for k in kenar:
		var a: Vector3 = k[0]
		var b: Vector3 = k[1]
		var n := int(a.distance_to(b) / 3.0)
		var dir := (b - a).normalized()
		for i in n + 1:
			var p := a + dir * (i * 3.0)
			_boru(_avlu, p + Vector3(0, DUVAR_H + 0.3, 0), p + Vector3(0, DUVAR_H + 0.95, 0), 0.025, dm)


# Avlu kapısı: paslı demir, iki kanat (sinematikte açılır)
func _kapi() -> void:
	var kb := 2.0
	_kapi_kanat.clear()
	for s in [-1.0, 1.0]:
		var piv := Node3D.new()
		piv.position = Vector3(X0 - 0.2, 0, s * kb)
		_avlu.add_child(piv)
		var k: Node3D = w.model("large_iron_gate", Vector3(0, 0, -s * kb / 2.0), PI / 2.0, 1.0, NAN, piv)
		var bb: AABB = w._bounds(k, piv)
		if bb.size.z > 0.1:
			k.scale = Vector3(1.0, minf(1.4, (DUVAR_H - 1.3) / maxf(0.1, bb.size.y)), kb / bb.size.z)
		_kapi_kanat.append(piv)
	# kapının üstünde soğuk güvenlik lambası
	var kl := SpotLight3D.new()
	kl.light_color = Color(0.85, 0.92, 1.0)
	kl.light_energy = 5.0
	kl.spot_range = 12.0
	kl.spot_angle = 55.0
	_avlu.add_child(kl)
	kl.global_position = Vector3(X0 + 0.6, DUVAR_H - 0.4, 0)
	kl.look_at(Vector3(X0 + 4.0, 0, 0), Vector3.UP)


# Gözcü kulesi: çelik kafes gövde (dört ayak, çapraz kuşaklar), merdiven, korkuluklu platform, camlı kabin, saçak
# çatı, kabinde amber lamba; köşede dönen projektör.
func _kule(i: int) -> void:
	var kp: Vector2 = KULE_YER[i]
	var k := Node3D.new()
	k.position = Vector3(kp.x, 0, kp.y)
	_avlu.add_child(k)
	var celik := StandardMaterial3D.new()
	celik.albedo_color = Color(0.22, 0.23, 0.24)
	celik.metallic = 0.75
	celik.roughness = 0.5
	var pas: StandardMaterial3D = w._pbr("rusty_metal_02", 0.7, 0.75, Color(0.62, 0.55, 0.5), "diff.jpg", 0.4)
	var beton: StandardMaterial3D = w._pbr("rough_concrete", 0.5, 1.0, Color(0.45, 0.45, 0.47))
	var h := 6.3
	var a := 1.05
	# beton kaideler + ayaklar
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_kutu(k, Vector3(0.5, 0.35, 0.5), Vector3(sx * a, 0.17, sz * a), beton)
			_boru(k, Vector3(sx * a, 0.3, sz * a), Vector3(sx * a * 0.92, h, sz * a * 0.92), 0.075, celik)
	# çapraz kuşaklar (her yüzde, üç kat)
	var katlar := [0.4, 2.3, 4.3, h]
	for kat in 3:
		var y0: float = katlar[kat]
		var y1: float = katlar[kat + 1]
		for yuz in 4:
			var c := [Vector3(-a, 0, -a), Vector3(a, 0, -a), Vector3(a, 0, a), Vector3(-a, 0, a)]
			var p0: Vector3 = c[yuz] * 0.96
			var p1: Vector3 = c[(yuz + 1) % 4] * 0.96
			_boru(k, p0 + Vector3(0, y0, 0), p1 + Vector3(0, y1, 0), 0.03, celik)
			_boru(k, p1 + Vector3(0, y0, 0), p0 + Vector3(0, y1, 0), 0.03, celik)
			_boru(k, p0 + Vector3(0, y1, 0), p1 + Vector3(0, y1, 0), 0.04, celik)
	w.solid(Vector3(2.3, h, 2.3), Vector3(0, h / 2, 0), 0.0, k)
	# merdiven (avlunun dışına bakan yüzde)
	var dis := Vector3(signf(kp.x - (X0 + X1) / 2.0), 0, 0)
	var mz := 0.0
	for s in [-0.25, 0.25]:
		_boru(k, Vector3(dis.x * (a + 0.12), 0, mz + s), Vector3(dis.x * (a + 0.12), h + 1.0, mz + s), 0.025, celik)
	var y := 0.3
	while y < h:
		_boru(k, Vector3(dis.x * (a + 0.12), y, mz - 0.25), Vector3(dis.x * (a + 0.12), y, mz + 0.25), 0.018, celik)
		y += 0.32
	# platform + korkuluk
	_kutu(k, Vector3(3.0, 0.22, 3.0), Vector3(0, h + 0.11, 0), pas)
	var r := 1.45
	var kc := [Vector3(-r, 0, -r), Vector3(r, 0, -r), Vector3(r, 0, r), Vector3(-r, 0, r)]
	for j in 4:
		var p0: Vector3 = kc[j]
		var p1: Vector3 = kc[(j + 1) % 4]
		_boru(k, p0 + Vector3(0, h + 0.2, 0), p0 + Vector3(0, h + 1.15, 0), 0.03, celik)
		_boru(k, p0 + Vector3(0, h + 1.12, 0), p1 + Vector3(0, h + 1.12, 0), 0.03, celik)
		_boru(k, p0 + Vector3(0, h + 0.66, 0), p1 + Vector3(0, h + 0.66, 0), 0.02, celik)
	# kabin: alt sac duvar, camlar (içi amber, hafif parlar), köşe dikmeleri, saçaklı çatı
	_kutu(k, Vector3(2.2, 0.95, 2.2), Vector3(0, h + 0.7, 0), pas)
	var cam := StandardMaterial3D.new()
	cam.albedo_color = Color(0.09, 0.1, 0.11, 0.6)
	cam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cam.roughness = 0.05
	cam.metallic = 0.5
	cam.emission_enabled = true
	cam.emission = Color(1.0, 0.55, 0.2)
	cam.emission_energy_multiplier = 0.25
	_kutu(k, Vector3(2.12, 1.0, 2.12), Vector3(0, h + 1.68, 0), cam)
	for j in 4:
		var p0: Vector3 = (kc[j] as Vector3) * 0.74
		_boru(k, p0 + Vector3(0, h + 1.15, 0), p0 + Vector3(0, h + 2.25, 0), 0.04, celik)
	_kutu(k, Vector3(2.9, 0.14, 2.9), Vector3(0, h + 2.28, 0), pas)
	_kutu(k, Vector3(2.4, 0.3, 2.4), Vector3(0, h + 2.48, 0), pas)
	var ic := OmniLight3D.new()
	ic.light_color = Color(1.0, 0.55, 0.2)
	ic.light_energy = 0.8
	ic.omni_range = 3.0
	ic.position = Vector3(0, h + 1.8, 0)
	k.add_child(ic)
	var uyari := OmniLight3D.new()
	uyari.light_color = Color(1.0, 0.12, 0.05)
	uyari.light_energy = 0.9
	uyari.omni_range = 2.2
	uyari.position = Vector3(0, h + 2.75, 0)
	k.add_child(uyari)
	var tep := uyari.create_tween().set_loops()
	tep.tween_property(uyari, "light_energy", 0.1, 0.7)
	tep.tween_property(uyari, "light_energy", 0.9, 0.7)
	# projektör: avluya dönük köşede, kaidesiyle
	var icy := Vector3((X0 + X1) / 2.0, 0, 0) - k.position
	icy.y = 0
	icy = icy.normalized()
	var lamba_yer := k.position + Vector3(icy.x * 1.5, KULE_H, icy.z * 1.5)
	var lamba := Node3D.new()
	_avlu.add_child(lamba)
	lamba.global_position = lamba_yer
	var model: Node3D = w.model("portable_searchlight", Vector3.ZERO, 0.0, 1.0, NAN, lamba)
	var mb: AABB = w._bounds(model, lamba)
	if mb.size.y > 0.05:
		model.scale = Vector3.ONE * (1.15 / mb.size.y)
	var spot := SpotLight3D.new()
	spot.light_color = Color(1.0, 0.96, 0.86)
	spot.light_energy = 11.0
	spot.spot_range = 28.0
	spot.spot_attenuation = 0.5
	spot.shadow_enabled = _kalite() >= 2
	spot.shadow_blur = 1.5
	spot.visible = false
	_avlu.add_child(spot)
	spot.global_position = lamba_yer + Vector3(0, 0.35, 0)
	# yerdeki ışık izi: yansıtılan parlak leke (zemine ve siperlere oturur; düz bir daire değil)
	var havuz := Decal.new()
	havuz.size = Vector3(ISIK_R * 2.3, 0.8, ISIK_R * 2.3)  # yalnız zemine (sandıkları beyaza boyamasın)
	havuz.texture_emission = _isik_doku()
	havuz.texture_albedo = _isik_doku()
	havuz.albedo_mix = 0.0
	havuz.emission_energy = 1.4
	havuz.modulate = Color(1.0, 0.95, 0.82)
	havuz.upper_fade = 0.3
	havuz.lower_fade = 0.3
	havuz.normal_fade = 0.55
	havuz.cull_mask = 1
	havuz.visible = false
	_avlu.add_child(havuz)
	var huz: MeshInstance3D = Dunya.huzme(_avlu, Vector3.ZERO, 10.0, 0.25, ISIK_R * 0.85, Color(1.0, 0.95, 0.82), 0.2)
	huz.visible = false
	_isik.append({"spot": spot, "havuz": havuz, "huzme": huz, "lamba": lamba, "yer": lamba_yer})


# Işık izi dokusu: ortası beyaz, kenara doğru yumuşakça kararan daire (ışıma rengi kanallarda, saydamlıkta değil)
static var _isik_doku_on: GradientTexture2D
static func _isik_doku() -> GradientTexture2D:
	if _isik_doku_on:
		return _isik_doku_on
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.55, 0.85, 1.0])
	gr.colors = PackedColorArray([Color(1, 1, 1, 1), Color(0.85, 0.85, 0.85, 1), Color(0.25, 0.25, 0.25, 0.6), Color(0, 0, 0, 0)])
	var t := GradientTexture2D.new()
	t.gradient = gr
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	_isik_doku_on = t
	return t


func _kule_lamba(i: int) -> Vector3:
	return _isik[i].yer if i >= 0 and i < _isik.size() else Vector3((X0 + X1) / 2.0, KULE_H, 0)


func _isik_yerlestir(i: int, hedef: Vector3, on: bool) -> void:
	var l: Dictionary = _isik[i]
	var spot: SpotLight3D = l.spot
	var havuz: Decal = l.havuz
	var huz: MeshInstance3D = l.huzme
	spot.visible = on
	havuz.visible = on
	huz.visible = on
	(l.lamba as Node3D).look_at(hedef + Vector3(0, 0.5, 0), Vector3.UP)
	if not on:
		return
	var top: Vector3 = l.yer
	var uz := top.distance_to(hedef)
	spot.look_at(hedef, Vector3.UP)
	spot.spot_angle = rad_to_deg(atan(ISIK_R * 1.15 / uz))
	spot.spot_range = uz + 4.0
	havuz.global_position = hedef + Vector3(0, 0.15, 0)
	var y := (top - hedef).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	huz.global_transform = Transform3D(Basis(x, y * (uz / 10.0), x.cross(y)), (top + hedef) / 2.0)


# Siper: avlunun ortasına doğru duran örtü (sandık yığını, varil, bariyer, tank, çöp...). Arkasındaki koyu,
# yere yansıtılmış gölge saklanma yerini belli eder.
func _siper(i: int) -> void:
	var s: Vector2 = SIPERLER[i]
	var p := Vector3(s.x, 0, s.y)
	var merkez := Vector3((X0 + X1) / 2.0, 0, 0)
	var ic := (merkez - p)
	ic.y = 0
	if ic.length() < 0.5:
		ic = Vector3(1, 0, 0)
	ic = ic.normalized()
	var yaw := atan2(ic.x, ic.z)
	var node := Node3D.new()
	node.position = p + ic * 1.15
	node.rotation.y = yaw
	_avlu.add_child(node)
	match i % 9:
		0:
			_ortu(node, "wooden_crate_01", Vector3(-0.48, 0, 0), 0.92)
			_ortu(node, "wooden_crate_01", Vector3(0.48, 0, 0.05), 0.92)
			_ortu(node, "wooden_crate_01", Vector3(0.0, 0.92, 0.0), 0.86)
		1:
			_ortu(node, "Barrel_01", Vector3(-0.58, 0, 0), 1.12)
			_ortu(node, "Barrel_01", Vector3(0.08, 0, 0.12), 1.12)
			_ortu(node, "barrel_03", Vector3(0.72, 0, -0.05), 1.02)
		2:
			_ortu(node, "concrete_road_barrier", Vector3(-0.78, 0, 0), 1.12)
			_ortu(node, "concrete_road_barrier", Vector3(0.78, 0, 0), 1.12)
		3:
			_ortu(node, "industrial_pastic_container", Vector3(0, 0, 0), 1.32)
			_ortu(node, "trashbag", Vector3(0.95, 0, -0.35), 0.55)
		4:
			_ortu(node, "old_military_crate", Vector3(-0.52, 0, 0), 0.72)
			_ortu(node, "old_military_crate", Vector3(0.52, 0, 0), 0.72)
			_ortu(node, "old_military_crate", Vector3(0.0, 0.72, 0), 0.66)
		5:
			_ortu(node, "metal_trash_can", Vector3(-0.62, 0, 0), 1.16)
			_ortu(node, "metal_trash_can", Vector3(0.2, 0, 0.05), 1.16)
			_ortu(node, "trashbag", Vector3(0.86, 0, -0.12), 0.62)
			_ortu(node, "trashbag", Vector3(-0.22, 0, -0.48), 0.56)
		6:
			_ortu(node, "wooden_crate_02", Vector3(-0.5, 0, 0), 0.96)
			_ortu(node, "wooden_crate_02", Vector3(-0.5, 0.96, 0.02), 0.5)
			_ortu(node, "old_tyre", Vector3(0.58, 0, 0), 0.25, 4)
		7:
			_ortu(node, "wooden_crate_02", Vector3(-0.46, 0, 0), 0.92)
			_ortu(node, "wooden_crate_02", Vector3(0.46, 0, 0), 0.92)
			_ortu(node, "Barrel_01", Vector3(0.0, 0, -0.78), 1.1)
		8:
			_ortu(node, "industrial_pastic_container", Vector3(-0.35, 0, 0), 1.32)
			_ortu(node, "wooden_crate_01", Vector3(0.95, 0, -0.1), 0.86)
	# saklanma gölgesi: yansıtılmış koyu leke (zemine oturur)
	var gd := Decal.new()
	gd.size = Vector3(SIPER_R * 2.5, 2.0, SIPER_R * 2.5)
	gd.texture_albedo = Dunya._radial_tex()
	gd.modulate = Color(0.0, 0.0, 0.0, 0.7)
	gd.upper_fade = 0.4
	gd.lower_fade = 0.4
	gd.cull_mask = 1
	_avlu.add_child(gd)
	gd.global_position = p + Vector3(0, 0.6, 0)


# Örtü nesnesi: modelin boyu `boy` metreye ölçeklenir; adet > 1 ise üst üste yığılır (lastik). Katı kutu eklenir.
func _ortu(parent: Node3D, id: String, yer: Vector3, boy: float, adet := 1) -> void:
	var y := yer.y
	for k in adet:
		var m: Node3D = w.model(id, Vector3(yer.x, y, yer.z), randf_range(-0.25, 0.25), 1.0, NAN, parent)
		var bb: AABB = w._bounds(m, parent)
		if bb.size.y > 0.02:
			m.scale = Vector3.ONE * (boy / bb.size.y)
			bb = w._bounds(m, parent)
		y += bb.size.y
		var gx := Vector3(maxf(0.3, bb.size.x), maxf(0.3, bb.size.y), maxf(0.3, bb.size.z))
		w.solid(gx, parent.to_global(bb.get_center()), parent.global_rotation.y, _avlu)


# Siper olmayan süsler: duvar dibinde banklar, lastik yığını, çöp torbaları, barfiks demiri
func _suslemeler() -> void:
	var yerler := [
		["painted_wooden_bench", Vector3(X0 + 6.0, 0, Z1 - 0.9), PI, 0.85],
		["painted_wooden_bench", Vector3(X0 + 14.0, 0, Z0 + 0.9), 0.0, 0.85],
		["old_tyre", Vector3(X1 - 1.0, 0, Z0 + 1.2), 0.3, 0.25],
		["trashbag", Vector3(X0 + 1.0, 0, Z1 - 1.0), 0.0, 0.6],
		["trashbag", Vector3(X0 + 1.6, 0, Z1 - 0.8), 1.0, 0.5],
		["metal_trash_can", Vector3(X0 + 2.2, 0, Z1 - 0.7), 0.0, 1.0],
	]
	for y in yerler:
		var m: Node3D = w.model(str(y[0]), y[1], float(y[2]), 1.0, NAN, _avlu)
		var bb: AABB = w._bounds(m, _avlu)
		if bb.size.y > 0.02:
			m.scale = Vector3.ONE * (float(y[3]) / bb.size.y)
	# barfiks: iki direk, üstte boru
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.3, 0.32, 0.34)
	metal.metallic = 0.8
	metal.roughness = 0.4
	var bx := X0 + 20.0
	var bz := Z1 - 1.2
	_boru(_avlu, Vector3(bx - 0.9, 0, bz), Vector3(bx - 0.9, 2.3, bz), 0.05, metal)
	_boru(_avlu, Vector3(bx + 0.9, 0, bz), Vector3(bx + 0.9, 2.3, bz), 0.05, metal)
	_boru(_avlu, Vector3(bx - 0.95, 2.25, bz), Vector3(bx + 0.95, 2.25, bz), 0.025, metal)


# ---------- gardiyan ve köpek (avluda) ----------

func _gardiyan_govde() -> Node3D:
	var b: Node3D = BodyScript.new()
	b.look = Catalog.sanitize({"govde": "erkek", "kiyafet": "gardiyan", "sapka": "kep", "sakal": "biyik", "sac": "kisa", "ten": 2})
	return b


# Avludaki gardiyan: nöbet yerinde, elinde fener; aramalarda sipere yürür, sonra döner.
func _gardiyan_avluda() -> void:
	var b := _gardiyan_govde()
	b.name = "AvluGardiyani"
	_avlu.add_child(b)
	b.global_position = NOBET
	b.rotation.y = _yuz_yaw(NOBET, Vector3((X0 + X1) / 2.0, 0, 0))
	b.set_meta("avlu", true)
	_fener = SpotLight3D.new()
	_fener.light_color = Color(0.95, 0.97, 1.0)
	_fener.light_energy = 5.0
	_fener.spot_angle = 18.0
	_fener.spot_range = 14.0
	_fener.visible = false
	_avlu.add_child(_fener)


func _avlu_gardiyani() -> Node3D:
	return _avlu.get_node_or_null("AvluGardiyani") if is_instance_valid(_avlu) else null


# yaw: gövdenin `from`dan `to`ya bakması için (gövdeler -z'ye bakar)
static func _yuz_yaw(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return atan2(-d.x, -d.z)


func _gardiyan_kare(delta: float) -> void:
	var b := _avlu_gardiyani()
	if not b:
		return
	var hedef := _gardiyan_hedef if _gardiyan_hedef != Vector3.INF else NOBET
	var p := b.global_position
	var d := Vector3(hedef.x - p.x, 0, hedef.z - p.z)
	if d.length() > 0.3:
		var adim := minf(d.length(), 2.4 * delta)
		b.global_position = p + d.normalized() * adim
		b.rotation.y = lerp_angle(b.rotation.y, atan2(-d.x, -d.z), minf(1.0, delta * 8.0))
		b.set("walk", 0.9)
	else:
		b.set("walk", 0.0)
	# fener: göğüs hizasından baktığı yöne (arama sırasında yanar)
	if is_instance_valid(_fener) and _fener.visible:
		var ileri := -b.global_transform.basis.z
		_fener.global_position = b.global_position + Vector3(0, 1.25, 0) + ileri * 0.35
		var bak := b.global_position + ileri * 5.0
		_fener.look_at(Vector3(bak.x, 0.0, bak.z), Vector3.UP)


func _kopek_kur() -> void:
	var sahne: PackedScene = load("res://assets/models/kopek/husky.glb")
	if not sahne:
		return
	_kopek = Node3D.new()
	_kopek.name = "Kopek"
	_avlu.add_child(_kopek)
	var m: Node3D = sahne.instantiate()
	_kopek.add_child(m)
	var bb: AABB = w._bounds(m, _kopek)
	if bb.size.y > 0.01:
		var sc := 0.78 / bb.size.y  # Alman kurdu boyu (~78 cm kulak ucuna)
		m.scale = Vector3.ONE * sc
		bb = w._bounds(m, _kopek)
		m.position = Vector3(-bb.get_center().x, -bb.position.y, -bb.get_center().z)
	# modelin burnu +z'de: gövdeler gibi -z'ye baksın
	m.rotation.y = PI
	_kopek_boya(m)
	var aps := m.find_children("*", "AnimationPlayer", true, false)
	_kopek_ap = aps[0] if not aps.is_empty() else null
	_kopek.global_position = NOBET + Vector3(0.9, 0, 0.7)
	_kopek.rotation.y = _yuz_yaw(_kopek.global_position, Vector3((X0 + X1) / 2.0, 0, 0))
	_kopek_oynat("dur")
	# gözler: karanlıkta hafif parlayan iki nokta (fener / projektör vurunca)
	for s in [-1.0, 1.0]:
		var goz := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.012
		sm.height = 0.024
		goz.mesh = sm
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.9, 0.75, 0.3)
		gm.emission_enabled = true
		gm.emission = Color(1.0, 0.75, 0.3)
		gm.emission_energy_multiplier = 0.8
		goz.material_override = gm
		goz.position = Vector3(s * 0.045, 0.66, -0.36)
		_kopek.add_child(goz)


# Husky renkleri -> Alman kurdu: koyu eyer, kızıl-kahve gövde ve bacaklar, açık kahve göğüs; yüzeyler pürüzsüz
func _kopek_boya(m: Node3D) -> void:
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if not mesh:
			continue
		var yumusak := _yumusat(mesh)
		if yumusak:
			(mi as MeshInstance3D).mesh = yumusak
			mesh = yumusak
		for s in mesh.get_surface_count():
			var eski: Material = mesh.surface_get_material(s)
			var renk := Color(0.3, 0.3, 0.3)
			if eski is BaseMaterial3D:
				renk = (eski as BaseMaterial3D).albedo_color
			var l := renk.get_luminance()
			var yeni := StandardMaterial3D.new()
			yeni.roughness = 0.85
			if l < 0.02:
				yeni.albedo_color = Color(0.02, 0.018, 0.016)  # burun, göz
				yeni.roughness = 0.3
			elif l < 0.1:
				yeni.albedo_color = Color(0.06, 0.05, 0.045)  # siyah eyer
			elif l < 0.45:
				yeni.albedo_color = Color(0.42, 0.24, 0.1)  # kızıl kahve
			else:
				yeni.albedo_color = Color(0.62, 0.43, 0.24)  # açık kahve
			yeni.rim_enabled = true
			yeni.rim = 0.35
			yeni.rim_tint = 0.6
			(mi as MeshInstance3D).set_surface_override_material(s, yeni)


# Düşük poligonlu modelin keskin yüzeylerini yumuşat (normaller yeniden hesaplanır, kemik ağırlıkları korunur)
static func _yumusat(mesh: Mesh) -> ArrayMesh:
	if not (mesh is ArrayMesh):
		return null
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		arr[Mesh.ARRAY_NORMAL] = null
		arr[Mesh.ARRAY_TANGENT] = null
		var st := SurfaceTool.new()
		st.create_from_arrays(arr, Mesh.PRIMITIVE_TRIANGLES)
		st.index()
		st.generate_normals()
		var yeni := st.commit_to_arrays()
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, yeni, [], {}, mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		out.surface_set_material(s, mesh.surface_get_material(s))
	return out


func _kopek_oynat(ad: String, hiz := 1.0) -> void:
	if not _kopek_ap:
		return
	var anim: String = KOPEK_ANIM.get(ad, "Idle")
	if not _kopek_ap.has_animation(anim):
		for a in _kopek_ap.get_animation_list():
			if a.ends_with(anim):
				anim = a
				break
	if _kopek_anim == anim:
		_kopek_ap.speed_scale = hiz
		return
	_kopek_anim = anim
	var a2: Animation = _kopek_ap.get_animation(anim)
	if a2 and ad != "isir":
		a2.loop_mode = Animation.LOOP_LINEAR
	_kopek_ap.play(anim, 0.2, hiz)


func _kopek_git(hedef: Vector3, is_ := "") -> void:
	_kopek_hedef = hedef
	_kopek_is = is_
	_kopek_is_t = 0.0


func _kopek_kare(delta: float) -> void:
	if not is_instance_valid(_kopek):
		return
	_kopek_hav_t -= delta
	var hedef := _kopek_hedef if _kopek_hedef != Vector3.INF else NOBET + Vector3(0.9, 0, 0.7)
	var p := _kopek.global_position
	var d := Vector3(hedef.x - p.x, 0, hedef.z - p.z)
	if d.length() > 0.45:
		var kos := d.length() > 2.0
		var hiz := 7.5 if kos else 2.0
		_kopek.global_position = p + d.normalized() * minf(d.length(), hiz * delta)
		_kopek.rotation.y = lerp_angle(_kopek.rotation.y, atan2(-d.x, -d.z), minf(1.0, delta * 9.0))
		_kopek_oynat("kos" if kos else "yuru", 1.2 if kos else 1.0)
		if kos and _kopek_hav_t <= 0.0:
			_kopek_hav_t = randf_range(1.2, 2.2)
			_ses3d("projektor/kopek_%d" % randi_range(1, 3), _kopek.global_position + Vector3(0, 0.5, 0), -2.0, 5.0)
		return
	# vardı: işi ne?
	_kopek_is_t += delta
	match _kopek_is:
		"kokla":
			_kopek_oynat("kokla")
			if _kopek_hav_t <= 0.0:
				_kopek_hav_t = randf_range(0.9, 1.6)
				_ses3d("projektor/kopek_%d" % randi_range(1, 3), _kopek.global_position + Vector3(0, 0.5, 0), 0.0, 6.0)
		"isir":
			_kopek_oynat("isir")
			if _kopek_is_t > 1.6:
				_kopek_is = ""
				_kopek_hedef = Vector3.INF
		_:
			_kopek_oynat("dur")


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
		env.fog_density = 0.012
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
	var p := "res://assets/ses/%s/%s.ogg" % ["gardiyan" if Dil.tr_mi() else "gardiyan_en", ad]
	return p if ResourceLoader.exists(p) else "res://assets/ses/gardiyan/%s.ogg" % ad


# Gardiyanın sesi: konum verilirse 3D (koridorda yanından geçerken), yoksa her yerden (hoparlör)
func _ses_gardiyan(ad: String, db: float, at = null) -> void:
	_ses_dosya(_gardiyan_yol(ad), db, at)


func _ses_dosya(path: String, db: float, at = null) -> void:
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
			p.position = Vector3(0, 1.6, 0)
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
	_vurulan = {}
	var p: CharacterBody3D = w.player
	_gardiyan = _gardiyan_govde()
	w.add_child(_gardiyan)
	_gardiyan.global_position = Vector3(KORIDOR_X, 0, 27.0)
	_gardiyan.rotation.y = 0.0  # -z yönüne yürür (yüzü yürüdüğü yöne)
	g.get_tree().create_timer(0.4).timeout.connect(_jop_ver)
	_ses3d("projektor/siren", Vector3(KORIDOR_X, 3.0, 0), -10.0, 30.0)
	g.get_tree().create_timer(0.7).timeout.connect(func() -> void: _ses_gardiyan("uyanin", 2.0, _gardiyan))
	g.get_tree().create_timer(4.4).timeout.connect(func() -> void:
		if is_instance_valid(_gardiyan):
			_ses_dosya("res://assets/ses/projektor/gulus.ogg", 2.0, _gardiyan)
			_gardiyan.play_emote("gul"))
	p.busy = false
	# hücrede kapının önünde, koridora bakarak başlar
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


# Gardiyanı oyuncuya çevir (konuşurken yüzü görünsün)
func _bana_don() -> void:
	if not is_instance_valid(_gardiyan):
		return
	var tw := _gardiyan.create_tween()
	tw.tween_property(_gardiyan, "rotation:y", _yuz_yaw(_gardiyan.global_position, w.player.global_position), 0.35)


func _giris_kare(delta: float) -> void:
	_intro_kalan += delta
	var t := _intro_kalan
	if not is_instance_valid(_gardiyan):
		return
	var gp := _gardiyan.global_position
	# 0.8 - 12.8 sn: koridor boyunca yürür (yüzü yürüdüğü yöne), her kapıda bir an kapıya döner ve vurur
	if t > 0.8 and t < 12.6 and gp.z > -27.0:
		gp.z -= _gardiyan_hiz * delta
		_gardiyan.global_position = gp
		_gardiyan.walk = 1.0
		var kapida := false
		for i in w.cells.size():
			var c: Node3D = w.cells[i]
			var dz: float = c.door_world().z
			if absf(gp.z - dz) < 1.0:
				kapida = true
			if not _vurulan.has(i) and absf(gp.z - dz) < 0.6:
				_vurulan[i] = true
				_kapiya_vur(c)
		# kapı önünde kapıya (-x), arada yürüdüğü yöne (-z) bakar
		_gardiyan.rotation.y = lerp_angle(_gardiyan.rotation.y, PI / 2.0 if kapida else 0.0, minf(1.0, delta * 10.0))
	elif t < 14.0:
		_gardiyan.walk = 0.0
	if _vur_t > 0.0:
		_vur_t -= delta
		var mod: Node = AimModScript.of_body(_gardiyan)
		if mod:
			mod.aim = clampf(sin((0.32 - _vur_t) / 0.32 * PI), 0.0, 1.0) * 0.9
	# 12.8: kapılar açılır (gardiyan bana döner)
	if t >= 12.8 and not _vurulan.has("kapi"):
		_vurulan["kapi"] = true
		_bana_don()
		_ses_gardiyan("kapilar", 2.0, _gardiyan)
		play("buzzer", -2.0)
		for c in w.cells:
			if not c.locked:
				c.set_door(true)
	# 14.0: hizaya! (sarı çizgi ve işaret); gardiyan koridorun ortasına yürür, sonra bize döner
	if t >= 14.0 and not _vurulan.has("hiza"):
		_vurulan["hiza"] = true
		_ses_gardiyan("hizaya", 2.0, _gardiyan)
		_hiza_ciz()
		flash("HİZAYA GEÇ!", "Kapının önündeki sarı çizgiye geç", UI.AMBER, 2.2)
		_botlar_hizaya()
	if t > 14.0 and t < 19.5:
		var hedef_z := clampf(w.player.global_position.z + 2.5, -22.0, 22.0)
		if absf(gp.z - hedef_z) > 0.15:
			gp.z = move_toward(gp.z, hedef_z, 3.2 * delta)
			_gardiyan.global_position = gp
			_gardiyan.rotation.y = lerp_angle(_gardiyan.rotation.y, 0.0 if hedef_z < gp.z else PI, minf(1.0, delta * 8.0))
			_gardiyan.walk = 0.8
		else:
			_gardiyan.walk = 0.0
			_gardiyan.rotation.y = lerp_angle(_gardiyan.rotation.y, _yuz_yaw(gp, w.player.global_position), minf(1.0, delta * 6.0))
	# 20.0: hizaya girmeyene cop
	if t >= 20.0 and not _vurulan.has("kontrol"):
		_vurulan["kontrol"] = true
		_hiza_denetle()
	# 22.0: yürüyün! karartma ve sinematik
	if t >= 22.0 and not _vurulan.has("yuru"):
		_vurulan["yuru"] = true
		_bana_don()
		_ses_gardiyan("yuru", 2.0, _gardiyan)
		_karart(0.5, _sinematik)


func _kapiya_vur(c: Node3D) -> void:
	var dw: Vector3 = c.door_world()
	_ses3d("projektor/parmaklik_%d" % randi_range(1, 3), dw + Vector3(0, 1.2, 0), 2.0, 5.0)
	_vur_t = 0.32
	var mod: Node = AimModScript.of_body(_gardiyan)
	if mod:
		mod.hand_target = dw + Vector3(0.1, 1.15, 0)
	if c == w.cells[w.my_cell]:
		w._shake(0.25, 0.03)


func _hiza_yeri(cell: int) -> Vector3:
	if cell < 0 or cell >= w.cells.size():
		return Vector3(HIZA_X, 0, 0)
	return Vector3(HIZA_X, 0, (w.cells[cell] as Node3D).door_world().z)


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
		var yer := _hiza_yeri(int(w._player_entry(int(id)).get("cell", -1)))
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
	# hizaya girmedi: gardiyan yanına gelir, yüzü sana dönük copla vurur, çizgiye itilirsin
	if is_instance_valid(_gardiyan):
		# koridorda, çizginin hemen yanında durur (oyuncu çizgiye itilince yüz yüze gelirler)
		_gardiyan.global_position = yer + Vector3(1.1, 0, 0.7)
		_gardiyan.rotation.y = _yuz_yaw(_gardiyan.global_position, yer)
		var mod: Node = AimModScript.of_body(_gardiyan)
		if mod:
			mod.hand_target = yer + Vector3(0, 1.4, 0)
		_vur_t = 0.32
	play("projektor/jop", 2.0)
	_ses_gardiyan("hizaya_dedim", 3.0)
	screen_flash(Color(0.9, 0.05, 0.02), 0.75, 0.03, 0.5)
	w._shake(0.5, 0.08)
	Titresim.vur("guclu")
	# oyuncu çizgiye itilir, gardiyana bakar
	var tw := p.create_tween()
	tw.tween_property(p, "global_position", yer, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	p.velocity = Vector3.ZERO
	p.rotation.y = _yuz_yaw(yer, _gardiyan.global_position) if is_instance_valid(_gardiyan) else -PI / 2.0


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


# Sinematik: avlunun içinden kapıya bakan kamera; kapı açılır, gardiyan ve köpek kapıda karşılar,
# mahkumlar sırayla içeri yürür, projektörler kapının önünü süpürür.
func _sinematik() -> void:
	if phase() != "anons":
		return
	_ortam_gece(true)
	for id in w.remotes:
		(w.remotes[id].root as Node3D).visible = false
	if is_instance_valid(_gardiyan):
		_gardiyan.visible = false
	_sine_kam = Camera3D.new()
	_sine_kam.fov = 50.0
	w.add_child(_sine_kam)
	_sine_kam.global_position = Vector3(X0 + 6.0, 1.55, 3.4)
	_sine_kam.look_at(Vector3(X0 - 1.5, 1.35, -0.4), Vector3.UP)
	_sine_kam.make_current()
	w.player.busy = true
	_gizlenen = get_tree_canvas()
	for c in _gizlenen:
		(c as CanvasLayer).visible = false
	# avludaki gardiyan ve köpek kapının iç yanında bekler
	var ag := _avlu_gardiyani()
	if ag:
		ag.global_position = Vector3(X0 + 2.6, 0, -2.6)
		ag.rotation.y = _yuz_yaw(ag.global_position, Vector3(X0, 0, 0))
		_gardiyan_hedef = ag.global_position
	if is_instance_valid(_kopek):
		_kopek.global_position = Vector3(X0 + 2.3, 0, -1.7)
		_kopek.rotation.y = _yuz_yaw(_kopek.global_position, Vector3(X0, 0, 0.5))
		_kopek_git(_kopek.global_position, "kokla")
	_ses3d("projektor/avlu_kapi", Vector3(X0, 2.0, 0), 4.0, 12.0)
	g.get_tree().create_timer(1.2).timeout.connect(func() -> void:
		if phase() == "anons":
			_ses_dosya("res://assets/ses/projektor/gulus_megafon.ogg", -2.0))
	for i in _kapi_kanat.size():
		var piv: Node3D = _kapi_kanat[i]
		var s := -1.0 if i == 0 else 1.0
		piv.create_tween().tween_property(piv, "rotation:y", s * deg_to_rad(-100), 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_supur = create_tween().set_parallel()
	for i in mini(2, _isik.size()):
		var k := i
		_supur.tween_method(func(v: float) -> void: _isik_yerlestir(k, Vector3(X0 + 2.0 + v * 4.0, 0, (-4.0 + v * 8.0) if k == 0 else (4.0 - v * 8.0)), true), 0.0, 1.0, 5.5)
	var sira: Array = state.get("players", [])
	for n in sira.size():
		var id := int(sira[n])
		var b: Node3D = BodyScript.new()
		b.look = Catalog.sanitize(w._player_entry(id).get("g", {}))
		w.add_child(b)
		var bas := Vector3(X0 - 3.0 - n * 1.3, 0, 0.45 * (1 if n % 2 == 0 else -1))
		b.global_position = bas
		b.rotation.y = -PI / 2.0
		_gecici.append(b)
		var son := Vector3(X0 + 3.5 + (sira.size() - n) * 0.6, 0, bas.z)
		var tw := b.create_tween()
		tw.tween_interval(0.9)
		tw.tween_property(b, "global_position", son, son.distance_to(bas) / 1.5)
		b.set("walk", 0.6)
	var kt := _sine_kam.create_tween()
	kt.tween_property(_sine_kam, "global_position", Vector3(X0 + 8.5, 2.3, 5.0), 5.5).set_trans(Tween.TRANS_SINE)


func get_tree_canvas() -> Array:
	var out := []
	for n in g.get_tree().root.find_children("*", "CanvasLayer", true, false):
		if (n as CanvasLayer).visible:
			out.append(n)
	return out


func _giris_bitir() -> void:
	if not _intro_on and _gecici.is_empty() and not is_instance_valid(_sine_kam) and _gizlenen.is_empty():
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
	_gardiyan_hedef = Vector3.INF
	_kopek_hedef = Vector3.INF
	_kopek_is = ""
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
	p.global_position = _giris_yeri(me())
	p.velocity = Vector3.ZERO
	p.rotation.y = -PI / 2.0
	p.head.rotation.x = 0.0
	p.camera.make_current()
	_adlar(false)
	for id in state.get("players", []):
		var pid := int(id)
		if pid == me() or not w.remotes.has(pid) or not w.is_bot(pid):
			continue
		var r: Dictionary = w.remotes[pid]
		if _bot_yol.has(pid) and (_bot_yol[pid].b as Vector3).x > X0:
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


func _av_baslat() -> void:
	_sayim_t = -1.0
	_sayac.visible = false
	close_card()
	_aktif_n = 0
	_onceki_d = INF
	play("projektor/projektor_ac", 4.0)
	g.get_tree().create_timer(0.2).timeout.connect(func() -> void: play("projektor/projektor_ac", 2.0))
	_ses_gardiyan("geliyorum", 0.0)
	g.get_tree().create_timer(3.4).timeout.connect(func() -> void:
		if phase() == "av":
			_ses_dosya("res://assets/ses/projektor/gulus_megafon.ogg", -2.0))
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
			_bot_kos(id, b.get("a", [0, 0]), bv, 0, kalan)


func _bot_kos(id: int, _a, b, gecikme: int, d: int) -> void:
	if not w.remotes.has(id):
		return
	var r: Dictionary = w.remotes[id]
	r.body.crouched = false
	_bot_yol[id] = {"a": r.root.position, "b": Vector3(float(b[0]), 0, float(b[1])), "s": Time.get_ticks_msec() + gecikme, "d": d}


func _botlar_kare() -> void:
	var now := Time.get_ticks_msec()
	for id in _bot_yol.keys():
		if not w.remotes.has(id):
			continue
		var y: Dictionary = _bot_yol[id]
		if now < int(y.s):
			continue
		var k := clampf(float(now - int(y.s)) / maxf(1.0, float(y.d)), 0.0, 1.0)
		var a: Vector3 = y.a
		var b: Vector3 = y.b
		var r: Dictionary = w.remotes[id]
		r.target = a.lerp(b, k)
		if k < 1.0:
			var dir := b - a
			r.yaw = atan2(-dir.x, -dir.z)
		else:
			_bot_yol.erase(id)
			r.body.crouched = phase() in ["sayim", "av"]


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
		_vinyet.create_tween().tween_method(func(v: float) -> void: mat.set_shader_parameter("k", v), 0.0, 1.0, 0.15)
		play("c4_bip", 0.0)
		play("alarm", -10.0)
		Titresim.vur("hafif")


# Arama uyarısı: köpek ilk (dolu) sipere koşup koklar, gardiyan feneriyle bir sonrakine yürür; aranan siperlerde
# kırmızı ışık yanıp söner, üstünde geri sayım.
func _arama_uyar(siperler: Array, ms: int) -> void:
	if siperler.is_empty():
		return
	_ses_gardiyan("arama_%d" % randi_range(1, 3), 0.0)
	var pp: Vector3 = w.player.global_position
	var benim := siperde(Vector2(pp.x, pp.z))
	var ben_orada := false
	for j in siperler.size():
		var si := int(siperler[j])
		if si < 0 or si >= SIPERLER.size():
			continue
		if si == benim and not _ben_yakalandim:
			ben_orada = true
		var sp: Vector2 = SIPERLER[si]
		var yer := Vector3(sp.x, 0, sp.y)
		if j == 0:
			_kopek_git(yer + Vector3(0.6, 0, 0.6), "kokla")
		elif j == 1:
			_gardiyan_hedef = yer + Vector3(-1.4, 0, 1.0)
			if is_instance_valid(_fener):
				_fener.visible = true
		var isik := OmniLight3D.new()
		isik.light_color = Color(1.0, 0.12, 0.06)
		isik.light_energy = 3.0
		isik.omni_range = 3.2
		_avlu.add_child(isik)
		isik.global_position = yer + Vector3(0, 1.8, 0)
		var tw := isik.create_tween().set_loops()
		tw.tween_property(isik, "light_energy", 0.3, 0.3)
		tw.tween_property(isik, "light_energy", 3.0, 0.3)
		var lb := Label3D.new()
		lb.text = tr("ARAMA")
		lb.font_size = 72
		lb.outline_size = 14
		lb.modulate = Color(1.0, 0.25, 0.15)
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_avlu.add_child(lb)
		lb.global_position = yer + Vector3(0, 2.5, 0)
		_aramalar[si] = {"isik": isik, "yazi": lb}
		_geri_say(lb, Time.get_ticks_msec() + ms)
	if ben_orada:
		flash("KÖPEK GELİYOR!", "Bu siperi bırak, başka yere saklan!", RED, 2.0)
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
		if _aramalar.has(si):
			for n in (_aramalar[si] as Dictionary).values():
				if is_instance_valid(n):
					(n as Node).queue_free()
		_aramalar.erase(si)
		if si < 0 or si >= SIPERLER.size():
			continue
		var sp: Vector2 = SIPERLER[si]
		var yer := Vector3(sp.x, 0, sp.y)
		var f := SpotLight3D.new()
		f.light_color = Color(0.92, 0.96, 1.0)
		f.light_energy = 12.0
		f.spot_angle = 22.0
		f.spot_range = 10.0
		_avlu.add_child(f)
		f.global_position = yer + Vector3(0.5, 5.0, 0.5)
		f.look_at(yer, Vector3.UP)
		_ses3d("projektor/fener", yer + Vector3(0, 1, 0), 2.0, 5.0)
		g.get_tree().create_timer(1.4).timeout.connect(f.queue_free)
	for id in yakalanan:
		_yakalandi(int(id), "arama")
	# gardiyan ve köpek nöbete döner (birini yakalamadıysa)
	g.get_tree().create_timer(2.2).timeout.connect(func() -> void:
		_gardiyan_hedef = Vector3.INF
		if is_instance_valid(_fener):
			_fener.visible = false
		if _kopek_is != "isir":
			_kopek_git(Vector3.INF))


func _yakalandi(id: int, _neden: String) -> void:
	if _yakalanan.has(id) and id != me():
		return
	_yakalanan[id] = true
	play("projektor/siren_kisa", -4.0)
	_ses_gardiyan("yakaladim_%d" % randi_range(1, 3), 0.0)
	var pos := Vector3.INF
	if id == me():
		pos = w.player.global_position
	elif w.remotes.has(id):
		pos = (w.remotes[id].root as Node3D).global_position
	# köpek yakalanana koşup ısırır
	if pos != Vector3.INF:
		_kopek_git(pos + (Vector3(-0.5, 0, 0.5)), "isir")
		_ses3d("projektor/kopek_3", pos + Vector3(0, 0.5, 0), 3.0, 6.0)
		_kilit(pos)
	if id == me():
		_beni_yakaladilar(true)
		return
	flash(tr("%s YAKALANDI!") % up(pname(id)), "", UI.AMBER, 1.4)
	if _izlenen == id:
		g.get_tree().create_timer(1.6).timeout.connect(func() -> void: _izle_degistir(1))
	if not w.remotes.has(id):
		return
	_bot_yol.erase(id)
	var root_n: Node3D = w.remotes[id].root
	g.get_tree().create_timer(2.4).timeout.connect(func() -> void:
		if is_instance_valid(root_n) and _yakalanan.has(id):
			root_n.visible = false)


func _kilit(pos: Vector3) -> void:
	if is_instance_valid(_kilit_spot):
		_kilit_spot.queue_free()
	if _isik.is_empty():
		return
	var en := 0
	var en_d := INF
	for i in _isik.size():
		var dd: float = (_isik[i].yer as Vector3).distance_to(pos)
		if dd < en_d:
			en_d = dd
			en = i
	_kilit_spot = SpotLight3D.new()
	_kilit_spot.light_color = Color(1.0, 0.45, 0.35)
	_kilit_spot.light_energy = 14.0
	_kilit_spot.spot_angle = rad_to_deg(atan(1.2 / maxf(1.0, en_d)))
	_kilit_spot.spot_range = en_d + 4.0
	_avlu.add_child(_kilit_spot)
	_kilit_spot.global_position = _isik[en].yer
	_kilit_spot.look_at(pos + Vector3(0, 0.8, 0), Vector3.UP)
	_kilit_t = 2.0


# ---------- yakalanınca: izleyici ----------

func _beni_yakaladilar(efekt: bool) -> void:
	if _ben_yakalandim:
		return
	_ben_yakalandim = true
	_isik_uyari(false)
	_durum.visible = false
	var p: CharacterBody3D = w.player
	p.busy = true
	w.voice.muted = true  # yakalanan konuşamaz (sunucu da sesini kimseye iletmez)
	if efekt:
		screen_flash(Color(1, 0.95, 0.85), 1.0, 0.03, 0.6)
		w._shake(0.6, 0.06)
		flash("YAKALANDIN!", "Konuşamazsın. Diğerlerini onların gözünden izle.", RED, 2.4)
		Titresim.vur("guclu")
	g.get_tree().create_timer(2.4 if efekt else 0.05).timeout.connect(func() -> void:
		if is_instance_valid(_avlu) and _ben_yakalandim:
			_izle_baslat())


func _izlenebilir() -> Array:
	var out := []
	for id in state.get("players", []):
		var pid := int(id)
		if pid != me() and not _yakalanan.has(pid) and w.remotes.has(pid):
			out.append(pid)
	return out


func _izle_baslat() -> void:
	if not is_instance_valid(_izle_kam):
		_izle_kam = Camera3D.new()
		_izle_kam.fov = 70.0
		_izle_kam.near = 0.08
		w.add_child(_izle_kam)
	_izle_kam.make_current()
	if not is_instance_valid(_izle_bar):
		_izle_bar = HBoxContainer.new()
		_izle_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_izle_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_izle_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_izle_bar.offset_top = -120
		_izle_bar.offset_bottom = -24
		_izle_bar.alignment = BoxContainer.ALIGNMENT_CENTER
		_izle_bar.add_theme_constant_override("separation", 18)
		var sol := UI.icon_button("geri", "ikincil", 80)
		sol.pressed.connect(func() -> void: _izle_degistir(-1))
		_izle_bar.add_child(sol)
		var kutu := VBoxContainer.new()
		kutu.alignment = BoxContainer.ALIGNMENT_CENTER
		var ust := UI.title(tr("İZLİYORSUN"), 22, Color(1, 0.82, 0.8))
		ust.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		kutu.add_child(ust)
		_izle_ad = UI.title("", UI.FS_ORTA + 4, GOLD)
		_izle_ad.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_izle_ad.custom_minimum_size = Vector2(380, 0)
		kutu.add_child(_izle_ad)
		_izle_bar.add_child(kutu)
		var sag := UI.icon_button("oyna", "ikincil", 80)
		sag.pressed.connect(func() -> void: _izle_degistir(1))
		_izle_bar.add_child(sag)
		root().add_child(_izle_bar)
	_izle_bar.visible = true
	_izlenen = 0
	_izle_degistir(1)


func _izle_degistir(yon: int) -> void:
	var liste := _izlenebilir()
	if _izlenen != 0 and w.remotes.has(_izlenen):
		(w.remotes[_izlenen].body as Node3D).visible = true
	if liste.is_empty():
		_izlenen = 0
		if is_instance_valid(_izle_ad):
			_izle_ad.text = tr("KULEDEN")
		return
	var i := liste.find(_izlenen)
	i = 0 if i < 0 else posmod(i + yon, liste.size())
	_izlenen = int(liste[i])
	if is_instance_valid(_izle_ad):
		_izle_ad.text = up(pname(_izlenen))
	# izlenenin kendi gövdesi kameranın önünü kapatmasın
	(w.remotes[_izlenen].body as Node3D).visible = false
	play("tik_ui", -6.0)


# İzlenen oyuncunun gözü: başının hizasında, onun baktığı yöne; yoksa kuleden kuş bakışı
func _izle_kare() -> void:
	if not is_instance_valid(_izle_kam):
		return
	_kontroller(false)
	if _izlenen != 0 and (not w.remotes.has(_izlenen) or _yakalanan.has(_izlenen)):
		_izle_degistir(1)
	if _izlenen == 0 or not w.remotes.has(_izlenen):
		_izle_kam.global_position = Vector3(X0 + 2.0, 13.0, Z0 - 2.0)
		_izle_kam.look_at(Vector3((X0 + X1) / 2.0, 0, 0), Vector3.UP)
		return
	var r: Dictionary = w.remotes[_izlenen]
	var root_n: Node3D = r.root
	var comel := bool(r.body.get("crouched"))
	var goz := root_n.global_position + Vector3(0, 1.05 if comel else 1.6, 0)
	var ileri := -root_n.global_transform.basis.z
	var hedef := goz + ileri * 2.0 + Vector3(0, -0.12, 0)
	_izle_kam.global_position = _izle_kam.global_position.lerp(goz, 0.35) if _izle_kam.global_position.distance_to(goz) < 3.0 else goz
	_izle_kam.look_at(hedef, Vector3.UP)


# İzlerken yürüme kolu, eğil / hareket / eylem düğmeleri ve nişan noktası gizli
func _kontroller(on: bool) -> void:
	var h = w.hud if w else null
	if not h:
		return
	h.set("izleyici", not on)
	for ad in ["joy", "action_btn", "dot"]:
		var n = h.get(ad)
		if n is CanvasItem and (n as CanvasItem).visible != on:
			(n as CanvasItem).visible = on


func _izlemeyi_kapat() -> void:
	if _izlenen != 0 or is_instance_valid(_izle_kam):
		_kontroller(true)
	if _izlenen != 0 and w and w.remotes.has(_izlenen):
		(w.remotes[_izlenen].body as Node3D).visible = true
	_izlenen = 0
	if is_instance_valid(_izle_bar):
		_izle_bar.queue_free()
	_izle_bar = null
	if is_instance_valid(_izle_kam):
		_izle_kam.queue_free()
	_izle_kam = null


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
	_izlemeyi_kapat()
	_ortam_geri()
	var p: CharacterBody3D = w.player
	p.busy = false
	w.voice.muted = false
	p.camera.make_current()
	p.global_position = w.cells[w.my_cell].spawn_world()
	p.velocity = Vector3.ZERO
	p.rotation.y = 0.0
	if is_instance_valid(_avlu):
		_avlu.queue_free()
	_avlu = null
	_kopek = null
	_isik.clear()
	_aramalar.clear()
	if is_instance_valid(_ortam):
		_ortam.queue_free()
	for id in w.remotes:
		(w.remotes[id].root as Node3D).visible = true
		(w.remotes[id].body as Node3D).visible = true
	_adlar(true)
	w.place_bots()


# ---------- test (sunucusuz) ----------
# main.gd: pose=oyunici oyun=projektor ekran=giris|sayim|av|arama|yakalandi|izle|kopek [t=<av sn>] [yer=<siper>] [ust=1] [tohum=<n>]
#   giris: gardiyan, kapılar, hiza, sinematik (gerçek sürede; --write-movie ile kaydedilir)
#   av: ışıklar t. saniyedeki yerlerinde, botlar siperlerde; yer=<siper> oyuncuyu o sipere koyar; ust=1 kuş bakışı
#   izle: ben yakalandım, bir botun gözünden izliyorum; kopek: köpek ve gardiyan yakın plan
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
				var s: Vector2 = SIPERLER[(id * 5) % SIPERLER.size()]
				liste.append({"tur": "bot_kos", "id": id, "a": [GIRIS.x, 0], "b": [s.x, s.y], "gecikme": 500 * id, "d": 2600})
			on_event({"tur": "coklu", "liste": liste})
		_:
			state["phase"] = "av"
			state["gecen"] = int(float(args.get("t", "20")) * 1000.0)
			var botlar := {}
			for id in [2, 3, 4]:
				var si: int = (int(id) * 5) % SIPERLER.size()
				var s: Vector2 = SIPERLER[si]
				botlar[str(id)] = {"siper": si, "a": [s.x, s.y], "b": [s.x, s.y], "kalan": 0, "d": 0}
			state["botlar"] = botlar
			on_state(state, true)
			if args.has("yer"):
				var s: Vector2 = SIPERLER[int(args.yer)]
				w.player.global_position = Vector3(s.x, 0, s.y)
				w.player.rotation.y = _yuz_yaw(Vector3(s.x, 0, s.y), Vector3((X0 + X1) / 2.0, 0, 0))
			match ek:
				"arama":
					on_event({"tur": "arama_uyari", "siper": [10, 4, 0], "ms": 5000})
				"yakalandi":
					on_event({"tur": "yakalandi", "id": 3, "neden": "isik"})
				"izle":
					on_event({"tur": "yakalandi", "id": me(), "neden": "isik"})
				"kopek":
					var ag := _avlu_gardiyani()
					w.player.global_position = NOBET + Vector3(3.2, 0, 1.4)
					w.player.rotation.y = _yuz_yaw(w.player.global_position, NOBET + Vector3(0.5, 0, 0.4))
					w.player.head.rotation.x = deg_to_rad(-12)
					if ag:
						ag.rotation.y = _yuz_yaw(ag.global_position, w.player.global_position)
	if args.get("ust", "0") == "1":
		await g.get_tree().create_timer(0.3).timeout
		var cam := Camera3D.new()
		cam.fov = 60.0
		w.add_child(cam)
		cam.global_position = Vector3((X0 + X1) / 2.0, 30.0, 18.0)
		cam.look_at(Vector3((X0 + X1) / 2.0, 0, 0), Vector3.UP)
		cam.make_current()
