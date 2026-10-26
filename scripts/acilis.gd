# Açılış perdesi ve yükleme ekranı. main.gd _ready'nin İLK işi olarak eklenir; dünya (koridor, salon, 8 hücre,
# arayüz) kademeli kurulurken (her adımdan sonra bir kare: main.gd "await perde.adim(oran)") bu perde oynar.
# Böylece telefon donmuş bir ekran değil animasyon gösterir.
#  - İlk açılış (2-3 sn, dokununca geçilir): sistem açılış ekranındaki (assets/ui/uretim/acilis_splash.png) yuvarlak
#    "HAT DÜŞTÜ" amblemi aynı yerde, aynı boyda durur (katmanları: amblem_zemin/tel/hat/dustu, tools/amblem_uret.gd).
#    Ahize iki kez titreyerek çalar (zil), amblemin üstünden bir ışık geçer, karanlık koridor (acilis.png) belirir,
#    "HAT" sonra "DÜŞTÜ" metal vuruşla çakılıp parlar (sarsıntı, kıvılcım, flaş); altta ince amber yükleme çubuğu.
#    Dünya kurulunca gölgelendiriciler ekran dışında ısıtılır (_isit: ilk maçta / ilk patlamada derleme donması
#    olmasın), sonra perde yumuşakça kalkar ve menü görünür.
#  - Menüye dönüşte (sahne yeniden kurulur): yalnız koridor + amblem + çubuk, kısa.
#  - Test / araç çalıştırmaları (--script, shot=, auto=): görünmez; dünya eskisi gibi tek seferde kurulur.
extends CanvasLayer

const ZEMIN := Color("#0b0e0f")  # acilis_splash.png zemini ve project.godot boot_splash/bg_color ile aynı
const AMBER := Color("#ffb020")
const SPLASH := Vector2(1920, 1080)
# amblem: 1024'lük tuval, splash'ta 820 px (tools/acilis_splash_uret.gd AMBLEM), ekranın ortasında
const AMBLEM_ORAN := 820.0 / 1080.0
const AMBLEM_MERKEZ := Vector2(511.5, 501.5)  # tuvalde dairenin merkezi
# kırpık katmanların tuvaldeki yeri: tools/amblem_uret.gd çıktısıyla AYNI olmalı
const KATMAN := {"tel": Rect2(373, 295, 288, 350), "hat": Rect2(290, 38, 442, 231), "dustu": Rect2(227, 690, 563, 272)}
# yazıların yayı (kıvılcımlar uçlarından saçılır): [yarıçap, orta açı, yarım açı]
const YAY := {"hat": [360.0, -PI / 2.0, 0.49], "dustu": [354.0, PI / 2.0, 0.70]}
# arkadaki kırmızı ışıma: splash'takiyle aynı eğri (tools/acilis_splash_uret.gd ISIK_*)
const ISIK_RENK := Color(0.55, 0.06, 0.04)
const ISIK_R := 0.5
const ISIK_GUC := 0.42
const ISIK_US := 2.0
const T_HAT := 1.05  # "HAT" vuruşu (animasyon saati)
const T_DUSTU := 1.45  # "DÜŞTÜ" vuruşu
const T_VURUS := T_DUSTU  # son vuruş (bitir() bunu görmeden perdeyi kaldırmaz)
const PARILTI := """shader_type canvas_item;
// amblemin üstünden geçen ışık bandı; ofs/boy: katmanın 1024'lük tuvaldeki yeri (bant bütün katmanlarda aynı yerde)
uniform vec2 ofs = vec2(0.0);
uniform vec2 boy = vec2(1024.0);
uniform float konum = -1.0;
uniform float guc = 0.0;
void fragment() {
	vec2 p = (ofs + UV * boy) / 1024.0;
	float d = p.x * 0.75 + p.y * 0.55 - konum;
	COLOR.rgb += vec3(1.0, 0.74, 0.45) * exp(-d * d * 260.0) * guc * COLOR.a;
}
"""
const Sfx := preload("res://scripts/sfx.gd")
const SURE_ILK := 2.5  # ilk açılışta en kısa süre (dokununca geçilir)
const SURE_DONUS := 0.35
const ISIT_KARE := 10  # ısıtmada bir karede çizilen yeni malzeme sayısı

static var _ilk := true  # bu süreçte ilk açılış mı
static var _isitildi := false

var kademeli := true  # false: araç/test (dünya tek seferde kurulur, perde görünmez)
var tur := "ilk"  # ilk | donus | test
var _host: Node
var _kok: Control
var _koridor: TextureRect
var _isik: TextureRect
var _amb: Control  # amblem (1024'lük tuval, ölçekli)
var _amb_yer := Vector2.ZERO
var _tel: TextureRect
var _hat: TextureRect
var _dustu: TextureRect
var _parilti: Array[ShaderMaterial] = []
var _flas: ColorRect
var _bar_kutu: Control
var _bar: ColorRect
var _yazi: Label
var _t := 0.0
var _oran := 0.0
var _hedef := 0.0
var _gecildi := false
var _kalkiyor := false
var _olay := {}
var _sarsinti := 0.0
var _bas_ms := 0
var _olc := OS.get_cmdline_user_args().has("acilis_olc=1")  # ölçüm: adım süreleri yazılır
var _adim_us := Time.get_ticks_usec()


func _init() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	var user := OS.get_cmdline_user_args()
	var test := false
	for a in user:
		if a.begins_with("shot=") or a.begins_with("auto=") or a.begins_with("pose="):
			test = true
	kademeli = not OS.get_cmdline_args().has("--script") or user.has("kademeli=1")
	if test or not kademeli:
		tur = "test"
	elif not _ilk:
		tur = "donus"


func _ready() -> void:
	_host = get_parent()
	_bas_ms = Time.get_ticks_msec()
	if kademeli and OS.get_cmdline_user_args().has("onyukle=1"):
		_onyukle()  # deneme: masaüstünde süre kazancı ölçülemedi, video belleği +50 MB; kapalı
	if tur == "test":
		if kademeli:
			# test görüntülerinde perde olmasın ama kurulum sırasında yarım dünya da görünmesin: düz zemin
			var z := ColorRect.new()
			z.color = ZEMIN
			z.set_anchors_preset(Control.PRESET_FULL_RECT)
			add_child(z)
		return
	_kur()


func _kur() -> void:
	var vs := get_viewport().get_visible_rect().size
	_kok = Control.new()
	_kok.set_anchors_preset(Control.PRESET_FULL_RECT)
	_kok.mouse_filter = Control.MOUSE_FILTER_STOP  # alttaki menüye dokunulmasın
	add_child(_kok)
	var zemin := ColorRect.new()
	zemin.color = ZEMIN
	zemin.set_anchors_preset(Control.PRESET_FULL_RECT)
	zemin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kok.add_child(zemin)
	# karanlık koridor: ekranı kaplar (oran korunur, taşan kenar kırpılır), yavaşça belirir
	_koridor = TextureRect.new()
	_koridor.texture = load("res://assets/ui/uretim/acilis.png")
	_koridor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_koridor.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_koridor.set_anchors_preset(Control.PRESET_FULL_RECT)
	_koridor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_koridor.modulate = Color(0.55, 0.55, 0.55, 0.0)
	_koridor.pivot_offset = vs / 2.0
	_kok.add_child(_koridor)
	var vig := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.1, 1.1)
	var g := Gradient.new()
	g.set_color(0, Color(ZEMIN, 0.1))
	g.set_color(1, Color(ZEMIN, 0.95))
	gt.gradient = g
	vig.texture = gt
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kok.add_child(vig)
	# kırmızı ışıma + amblem: sistem açılış ekranındakiyle aynı yer ve boy (Keep: görsel ekrana sığdırılır, ortalanır)
	var olcek := minf(vs.x / SPLASH.x, vs.y / SPLASH.y)
	_isik = TextureRect.new()
	var it := GradientTexture2D.new()
	it.width = 256
	it.height = 256
	it.fill = GradientTexture2D.FILL_RADIAL
	it.fill_from = Vector2(0.5, 0.5)
	it.fill_to = Vector2(1.0, 0.5)
	var ig := Gradient.new()
	var ofs := PackedFloat32Array()
	var renk := PackedColorArray()
	for i in 13:
		var o := float(i) / 12.0
		ofs.append(o)
		renk.append(Color(ISIK_RENK, pow(1.0 - o, ISIK_US) * ISIK_GUC))
	ig.offsets = ofs
	ig.colors = renk
	it.gradient = ig
	_isik.texture = it
	_isik.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_isik.stretch_mode = TextureRect.STRETCH_SCALE
	_isik.size = Vector2.ONE * 2.0 * ISIK_R * SPLASH.y * olcek
	_isik.position = vs / 2.0 - _isik.size / 2.0
	_isik.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kok.add_child(_isik)
	_amb = Control.new()
	_amb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_amb.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_amb.size = Vector2(1024, 1024)
	_amb.pivot_offset = AMBLEM_MERKEZ
	_amb.scale = Vector2.ONE * AMBLEM_ORAN * SPLASH.y * olcek / 1024.0
	# tuvalin ortası ekranın ortasına (pivot ölçekte sabit kalır: ekran = konum + pivot + (yer - pivot) * ölçek)
	_amb_yer = vs / 2.0 - AMBLEM_MERKEZ - (_amb.size / 2.0 - AMBLEM_MERKEZ) * _amb.scale
	_amb.position = _amb_yer
	_kok.add_child(_amb)
	var sh := Shader.new()
	sh.code = PARILTI
	_katman(sh, "res://assets/ui/uretim/amblem_zemin.png", Rect2(0, 0, 1024, 1024))
	_tel = _katman(sh, "res://assets/ui/uretim/amblem_tel.png", KATMAN.tel)
	_hat = _katman(sh, "res://assets/ui/uretim/amblem_hat.png", KATMAN.hat)
	_dustu = _katman(sh, "res://assets/ui/uretim/amblem_dustu.png", KATMAN.dustu)
	_flas = ColorRect.new()
	_flas.color = Color(1.0, 0.85, 0.6, 0.0)
	_flas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kok.add_child(_flas)
	# altta ince amber yükleme çubuğu ve "YÜKLENİYOR"
	_bar_kutu = Control.new()
	_bar_kutu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bw := minf(vs.x * 0.36, 520.0)
	_bar_kutu.size = Vector2(bw, 34)
	_bar_kutu.position = Vector2(vs.x / 2.0 - bw / 2.0, vs.y - 64.0)
	_bar_kutu.modulate.a = 0.0
	_kok.add_child(_bar_kutu)
	_yazi = Label.new()
	_yazi.text = tr("YÜKLENİYOR")
	_yazi.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_yazi.add_theme_font_size_override("font_size", 15)
	_yazi.add_theme_color_override("font_color", Color(AMBER, 0.7))
	_yazi.add_theme_constant_override("outline_size", 0)
	_yazi.size = Vector2(bw, 20)
	_yazi.position = Vector2(0, 0)
	_yazi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_kutu.add_child(_yazi)
	var iz := ColorRect.new()
	iz.color = Color(1, 1, 1, 0.1)
	iz.size = Vector2(bw, 3)
	iz.position = Vector2(0, 26)
	iz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_kutu.add_child(iz)
	_bar = ColorRect.new()
	_bar.color = AMBER
	_bar.size = Vector2(0, 3)
	_bar.position = Vector2(0, 26)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_kutu.add_child(_bar)
	if tur == "donus":
		# menüye dönüş: koridor ve logo hazır, yalnız çubuk ilerler
		_t = 3.0
		_koridor.modulate.a = 1.0
		_koridor.scale = Vector2.ONE
		_bar_kutu.modulate.a = 1.0
	_ciz(0.0)


func _katman(sh: Shader, yol: String, r: Rect2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(yol)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.position = r.position
	t.size = r.size
	t.pivot_offset = r.size / 2.0
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("ofs", r.position)
	m.set_shader_parameter("boy", r.size)
	t.material = m
	_parilti.append(m)
	_amb.add_child(t)
	return t


# Kurulum adımı bitti: çubuk ilerler, bir kare çizilir (animasyon akar). Araç çalıştırmalarında beklemez.
func adim(oran: float) -> void:
	_hedef = maxf(_hedef, oran)
	if _olc:
		var simdi := Time.get_ticks_usec()
		print("[acilis] adim %.2f: %.1f ms" % [oran, (simdi - _adim_us) / 1000.0])
		_adim_us = simdi
	if kademeli:
		await get_tree().process_frame


# Dünya hazır: (ilk açılışta) gölgelendiriciler ısıtılır, animasyon en kısa süresini doldurur, perde kalkar.
func bitir() -> void:
	if not kademeli or tur == "test":
		queue_free()
		return
	_hedef = maxf(_hedef, 0.92)
	if tur == "ilk" and not _isitildi and not OS.get_cmdline_user_args().has("isitma=0"):
		_isitildi = true
		await _isit()
	_onyukleme_bitir()
	_hedef = 1.0
	_ilk = false
	# en kısa süre gerçek saatle (ağır karelerde animasyon saati geride kalır); logonun vuruşu da görülmüş olsun
	var en_az := int((SURE_ILK if tur == "ilk" else SURE_DONUS) * 1000.0)
	var bas := Time.get_ticks_msec()
	while ((not _gecildi and (Time.get_ticks_msec() - _bas_ms < en_az or (tur == "ilk" and _t < T_VURUS + 0.45))) or _oran < 0.995) \
			and Time.get_ticks_msec() - bas < 4000:
		await get_tree().process_frame
	print("[acilis] perde kalkiyor: %d ms (motor acilisindan %d ms)" % [Time.get_ticks_msec() - _bas_ms, Time.get_ticks_msec()])
	_kalkiyor = true
	_kok.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(_kok, "modulate:a", 0.0, 0.45 if tur == "ilk" else 0.25).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(queue_free)


func _input(e: InputEvent) -> void:
	if tur == "test" or _kalkiyor:
		return
	if (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed):
		_gecildi = true  # dokununca animasyon beklenmez (yükleme bitince perde hemen kalkar)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if tur == "test" or _kok == null:
		return
	# ağır kurulum karelerinde animasyon atlamasın: kare süresi sınırlanır (yavaşlar ama akar)
	var dt := minf(delta, 1.0 / 30.0)
	_t += dt
	_oran = move_toward(_oran, _hedef, dt * (2.2 if _hedef >= 1.0 else 0.9))
	_ciz(dt)


func _ciz(dt: float) -> void:
	var t := _t
	# koridor: 0,25 sn'den itibaren belirir, hafifçe yaklaşır
	var k := clampf((t - 0.25) / 1.2, 0.0, 1.0)
	_koridor.modulate.a = k * k * (3.0 - 2.0 * k)
	_koridor.scale = Vector2.ONE * lerpf(1.1, 1.0, k)
	var titre := Vector2.ZERO
	if tur == "ilk":
		# ahize iki kez titreyerek çalar (zil); amblem de hafifçe sarsılır, ışıma zille parlar
		var z := t - 0.15
		var cal := z > 0.0 and z < 0.9 and fmod(z, 0.45) < 0.3
		_tel.rotation = sin(t * 95.0) * 0.07 if cal else 0.0
		_tel.scale = Vector2.ONE * (1.035 if cal else 1.0)
		if cal:
			titre = Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
		_bir("zil1", z >= 0.0, func() -> void: _ses_akis(_zil(), -9.0))
		_bir("zil2", z >= 0.45, func() -> void: _ses_akis(_zil(), -9.0))
		_bir("cizirti", t >= 0.05, func() -> void: _ses("res://assets/ses/cizirti.ogg", -10.0))
		var parla := (1.25 if cal else 1.0) + 0.08 * sin(t * 3.0)
		_isik.self_modulate = Color(parla, parla, parla)
		# ışık bandı sol üstten sağ alta geçer
		var g := clampf((t - 0.3) / 0.75, 0.0, 1.0)
		for m in _parilti:
			m.set_shader_parameter("konum", lerpf(-0.25, 1.6, g))
			m.set_shader_parameter("guc", sin(g * PI) * 0.6)
		# "HAT", sonra "DÜŞTÜ" metal vuruşla çakılır ve parlar
		_kelime(_hat, t, T_HAT)
		_kelime(_dustu, t, T_DUSTU)
		_bir("vurus_hat", t >= T_HAT, func() -> void: _vurus("hat", 1.0))
		_bir("vurus_dustu", t >= T_DUSTU, func() -> void: _vurus("dustu", 0.8))
	_amb.position = _amb_yer + titre
	_flas.color.a = maxf(0.0, _flas.color.a - dt * 3.0)
	# sarsıntı
	if _sarsinti > 0.0:
		_sarsinti = maxf(0.0, _sarsinti - dt)
		var a := 16.0 * (_sarsinti / 0.32)
		_kok.position = Vector2(randf_range(-a, a), randf_range(-a, a))
	else:
		_kok.position = Vector2.ZERO
	# çubuk
	var b := clampf((t - 1.6) / 0.3, 0.0, 1.0) if tur == "ilk" else 1.0
	_bar_kutu.modulate.a = b
	_bar.size.x = _bar_kutu.size.x * _oran


# Kelime vuruşu: vuruştan 0,14 sn önce biraz kalkar (büyür, kararır), vuruşta yerine çakılır, beyaz-turuncu parlar,
# küçük bir sekmeyle durulur.
func _kelime(n: TextureRect, t: float, tv: float) -> void:
	if t < tv:
		var o := clampf((t - (tv - 0.14)) / 0.14, 0.0, 1.0)
		n.scale = Vector2.ONE * (1.0 + 0.1 * sin(o * PI * 0.5))
		n.modulate = Color(1.0 - 0.3 * o, 1.0 - 0.3 * o, 1.0 - 0.3 * o)
		return
	var s := clampf((t - tv) / 0.5, 0.0, 1.0)
	n.scale = Vector2.ONE * (1.0 - sin(s * PI * 2.0) * 0.03 * (1.0 - s))
	var p := (1.0 - s) * (1.0 - s)
	n.modulate = Color(1, 1, 1).lerp(Color(2.3, 1.75, 1.3), p)


func _bir(ad: String, kosul: bool, f: Callable) -> void:
	if kosul and not _olay.has(ad):
		_olay[ad] = true
		f.call()


func _vurus(ad: String, pitch: float) -> void:
	var son := ad == "dustu"
	_ses("res://assets/ses/kapi_carp.ogg", -2.0 if son else -4.0, 0.9 * pitch)
	_ses("res://assets/ses/kivilcim.ogg", -6.0, 1.05 * pitch)
	_sarsinti = 0.32 if son else 0.22
	_flas.color.a = 0.3 if son else 0.18
	var pr: Node = _host.get("profile")
	if pr and bool(pr.settings.get("titresim", true)):
		Input.vibrate_handheld(40 if son else 25)
	# kelimenin iki ucundan, yay boyunca dışa doğru saçılan kıvılcımlar
	var y: Array = YAY[ad]
	var tuval := _kok.get_global_transform().affine_inverse() * _amb.get_global_transform()
	for i in 2:
		var yon := -1.0 if i == 0 else 1.0  # sol uç / sağ uç
		var aci: float = float(y[1]) + yon * float(y[2]) * (1.0 if ad == "hat" else -1.0)
		var dis := Vector2(cos(aci), sin(aci))
		var p := CPUParticles2D.new()
		p.position = tuval * (AMBLEM_MERKEZ + dis * float(y[0]))
		p.amount = 32
		p.one_shot = true
		p.explosiveness = 1.0
		p.lifetime = 0.8
		p.spread = 55.0
		p.direction = (Vector2(yon, 0.0) + dis * 0.6 + Vector2(0, -0.6)).normalized()
		p.initial_velocity_min = 180.0
		p.initial_velocity_max = 520.0
		p.gravity = Vector2(0, 1100)
		p.scale_amount_min = 1.5
		p.scale_amount_max = 3.5
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 0.95, 0.7))
		g.set_color(1, Color(1.0, 0.45, 0.1, 0.0))
		p.color_ramp = g
		_kok.add_child(p)
		p.emitting = true
		p.finished.connect(p.queue_free)


# Eski duvar telefonu zili: iki çan tonu, tokmak ~24 Hz vurur (koddan, bir kez üretilir).
static var _zil_ses: AudioStreamWAV


static func _zil() -> AudioStream:
	if _zil_ses:
		return _zil_ses
	var r := Sfx.RATE
	var s := PackedFloat32Array()
	s.resize(int(r * 0.34))
	for i in s.size():
		var t := float(i) / r
		var tokmak := 0.55 + 0.45 * signf(sin(TAU * 24.0 * t))
		var zarf := minf(1.0, t * 80.0) * exp(-maxf(0.0, t - 0.26) * 40.0)
		var ton := sin(TAU * 1180.0 * t) * 0.5 + sin(TAU * 1630.0 * t) * 0.3 + sin(TAU * 2390.0 * t) * 0.12
		s[i] = ton * tokmak * zarf * 0.4
	_zil_ses = Sfx._wav(s)
	return _zil_ses


func _ses_akis(st: AudioStream, db := 0.0) -> void:
	var a := AudioStreamPlayer.new()
	a.stream = st
	a.volume_db = db
	add_child(a)
	a.play()
	a.finished.connect(a.queue_free)


func _ses(yol: String, db := 0.0, pitch := 1.0) -> void:
	if not ResourceLoader.exists(yol):
		return
	var a := AudioStreamPlayer.new()
	a.stream = load(yol)
	a.volume_db = db
	a.pitch_scale = pitch
	add_child(a)
	a.play()
	a.finished.connect(a.queue_free)


# ---------- gölgelendirici ısıtma ----------
# Sahnedeki bütün malzemeler (koridor, hücreler, salon, karakter) ve sonradan çıkan efektler (patlama, altıpatar,
# C4, başka giyimli karakterler) ekran dışındaki küçük bir görünümde birer kez çizilir: gölgelendiriciler şimdi
# derlenir, maçta ilk görüldükleri karede değil. Her karede ISIT_KARE yeni malzeme (kareler uzun donmasın).
func _isit() -> void:
	var t0 := Time.get_ticks_msec()
	var sv := SubViewport.new()
	sv.size = Vector2i(192, 108)
	sv.own_world_3d = true
	sv.msaa_3d = get_viewport().msaa_3d
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var root := Node3D.new()
	sv.add_child(root)
	var env: Environment = _host.get("env")
	if env:
		var we := WorldEnvironment.new()
		we.environment = env
		root.add_child(we)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.0, 3.0)
	cam.fov = 60.0
	root.add_child(cam)
	cam.current = true
	# gölgeli ışıklar: gölge geçişinin gölgelendiricileri de derlensin
	var omni := OmniLight3D.new()
	omni.position = Vector3(0.6, 2.0, 1.5)
	omni.shadow_enabled = true
	omni.omni_range = 8.0
	root.add_child(omni)
	var spot := SpotLight3D.new()
	spot.position = Vector3(-0.8, 2.5, 2.0)
	spot.rotation = Vector3(-1.0, 0, 0)
	spot.shadow_enabled = true
	spot.spot_range = 8.0
	root.add_child(spot)
	var mats := _malzemeler(_host)
	mats.append_array(preload("res://scripts/efekt.gd").isitma_listesi() + preload("res://scripts/dunya.gd").diger_kalite_malzemeleri())  # efektler + öbür kalitenin kirli/sade malzemeleri (E ajanı)
	var kutu := BoxMesh.new()
	kutu.size = Vector3(0.4, 0.4, 0.4)
	var i := 0
	var parti: Array = []
	for m in mats:
		var mi := MeshInstance3D.new()
		mi.mesh = kutu
		mi.material_override = m
		mi.position = Vector3((i % 6) * 0.45 - 1.1, 0.4 + ((i / 6) % 4) * 0.45, 0)
		root.add_child(mi)
		parti.append(mi)
		i += 1
		if parti.size() >= ISIT_KARE:
			_hedef = maxf(_hedef, 0.92 + 0.05 * float(i) / mats.size())
			await get_tree().process_frame
			for n in parti:
				n.queue_free()
			parti.clear()
	await get_tree().process_frame
	for n in parti:
		n.queue_free()
	# sonradan çıkan efektler ve eşyalar
	var Props := preload("res://scripts/modlar/props.gd")
	Props.hazirla()
	var efekt := Node3D.new()
	root.add_child(efekt)
	Props.explosion(efekt, Vector3(0, 1.0, -1.0), 0.0)
	var gun := Node3D.new()
	gun.position = Vector3(-0.6, 1.0, 1.5)
	root.add_child(gun)
	Props.revolver(gun)
	var c4 := Node3D.new()
	c4.position = Vector3(0.6, 1.0, 1.5)
	root.add_child(c4)
	Props.c4(c4)
	await get_tree().process_frame
	_hedef = maxf(_hedef, 0.98)
	# farklı giyimli karakterler (saç kartı, şeffaf aksesuar, dövme, ranger kıyafeti...)
	var Body := preload("res://scripts/model_body.gd")
	for look in [{"govde": "kadin", "sac": "ikiz_orgu", "sac_renk": 5, "sapka": "bere", "aksesuar": "gunes", "kiyafet": "leopar", "dovme": "gul"},
			{"govde": "iri", "sac": "rasta", "sakal": "dolgun", "sapka": "kapuson", "aksesuar": "zincir", "kiyafet": "firari", "dovme": "ejderha"}]:
		var b: Node3D = Body.new()
		b.look = preload("res://scripts/catalog.gd").sanitize(look)
		b.position = Vector3(0, 0, 0.5)
		root.add_child(b)
		await get_tree().process_frame  # saç / şapka kafa kemiğine bu karede takılır, sonraki karede çizilir
		await get_tree().process_frame
		b.queue_free()
	await get_tree().process_frame
	efekt.queue_free()  # patlamanın gecikmeli tozu dumanla aynı malzeme (zaten çizildi)
	await get_tree().process_frame
	sv.queue_free()
	print("[acilis] isitma: %d malzeme, %d ms" % [mats.size(), Time.get_ticks_msec() - t0])


# Ağaçtaki bütün 3D malzemeler (tekrarsız; aynı gölgelendiricili ShaderMaterial'lerden biri yeter).
static func _malzemeler(host: Node) -> Array:
	var seen := {}
	var shaders := {}
	var out: Array = []
	var ekle := func(m: Material) -> void:
		while m:
			if not seen.has(m):
				seen[m] = true
				if m is ShaderMaterial:
					var sh: Shader = (m as ShaderMaterial).shader
					if sh and not shaders.has(sh):
						shaders[sh] = true
						out.append(m)
				elif m is BaseMaterial3D:
					out.append(m)
			m = m.next_pass
	for n in host.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		ekle.call(g.material_override)
		ekle.call(g.material_overlay)
		var mesh: Mesh = null
		if g is MeshInstance3D:
			mesh = (g as MeshInstance3D).mesh
			for s in (mesh.get_surface_count() if mesh else 0):
				ekle.call((g as MeshInstance3D).get_surface_override_material(s))
		elif g is CPUParticles3D:
			mesh = (g as CPUParticles3D).mesh
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
			mesh = (g as MultiMeshInstance3D).multimesh.mesh
		if mesh:
			for s in mesh.get_surface_count():
				ekle.call(mesh.surface_get_material(s))
	return out


# ---------- arka planda ön yükleme ----------
# Dünyanın modelleri ve dokuları iş parçacığında okunmaya başlar; kurulum adımları (ana iş parçacığı) onları
# istediğinde çoğu hazırdır (masaüstünde ~0,5 sn kazanç; telefonda dosya okuma daha yavaş olduğundan daha çok).
var _yuklenen: Array = []


func _onyukle() -> void:
	var yollar: Array = []
	for d in ResourceLoader.list_directory("res://assets/models/"):
		if d.ends_with("/"):
			yollar.append("res://assets/models/%s%s.gltf" % [d, d.trim_suffix("/")])
	for d in ResourceLoader.list_directory("res://assets/textures/"):
		if d.ends_with("/"):
			for f in ResourceLoader.list_directory("res://assets/textures/" + d):
				if f.ends_with(".jpg") or f.ends_with(".png"):
					yollar.append("res://assets/textures/" + d + f)
	for p in yollar:
		if ResourceLoader.exists(p) and ResourceLoader.load_threaded_request(p, "", true) == OK:
			_yuklenen.append(p)


func _onyukleme_bitir() -> void:
	for p in _yuklenen:
		if ResourceLoader.load_threaded_get_status(p) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_get(p)  # yükleyicinin tuttuğu başvuru bırakılır (dünyadakiler kalır)
	_yuklenen.clear()


func _exit_tree() -> void:
	_onyukleme_bitir()
