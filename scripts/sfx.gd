# Oyundaki sesleri dosya kullanmadan, koddan üretir.
extends RefCounted

const RATE := 22050


static func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


# Zil sesleri: 0 = klasik çan, 1 = eski çevirmeli (kalın, yavaş), 2 = modern (iki tonlu bip).
static var _ring_c := {}  # üretilen ziller (her çalışta yeniden hesaplanmasın: tur sonunda takılıyordu)
static var _bell_c: AudioStreamWAV


static func ring(kind := 0) -> AudioStreamWAV:
	if _ring_c.has(kind):
		return _ring_c[kind]
	_ring_c[kind] = _ring_uret(kind)
	return _ring_c[kind]


static func _ring_uret(kind: int) -> AudioStreamWAV:
	var n := int(RATE * 3.0)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var on := (t < 0.45) or (t > 0.6 and t < 1.05)
		if not on:
			s[i] = 0.0
			continue
		match kind:
			1:
				var since := fmod(t, 1.0 / 13.0)
				s[i] = (sin(TAU * 640.0 * t) * 0.6 + sin(TAU * 1010.0 * t) * 0.3) * exp(-since * 22.0) * 0.85
			2:
				var f := 1320.0 if fmod(t, 0.24) < 0.12 else 880.0
				s[i] = (sin(TAU * f * t) * 0.5 + sin(TAU * f * 2.0 * t) * 0.12) * 0.7
			_:
				var since := fmod(t, 1.0 / 22.0)
				s[i] = (sin(TAU * 920.0 * t) * 0.55 + sin(TAU * 1380.0 * t) * 0.35) * exp(-since * 35.0) * 0.8
	return _wav(s, true)


static func click() -> AudioStreamWAV:
	var n := int(RATE * 0.12)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = (randf() * 2.0 - 1.0) * exp(-t * 60.0) * 0.7 + sin(TAU * 180.0 * t) * exp(-t * 40.0) * 0.5
	return _wav(s)


# Metal çınlaması: birkaç harmonik, her biri kendi hızında söner.
static func _ring(t: float, freqs: Array, decay: float) -> float:
	var v := 0.0
	for k in freqs.size():
		v += sin(TAU * freqs[k] * t) * exp(-t * decay * (1.0 + k * 0.6)) / (1.0 + k)
	return v


# Ağır çelik hücre kapısı.
# Açılış: kilit "klak" + menteşenin takılarak gıcırdaması (sürtünme darbeleri bir rezonatörü titretir).
# Kapanış: kısa gıcırtı + tok çarpma + metal çınlaması + kilit tıkı.
static func door(opening: bool) -> AudioStreamWAV:
	var dur := 1.6 if opening else 1.3
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var creak_start := 0.18 if opening else 0.0
	var creak_len := 1.0 if opening else 0.35
	var y1 := 0.0
	var y2 := 0.0
	var pulse_ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		# menteşe gıcırtısı
		var ct := t - creak_start
		var x := 0.0
		if ct > 0.0 and ct < creak_len:
			var k := ct / creak_len
			var rate := lerpf(38.0, 70.0, k) + sin(ct * 23.0) * 8.0
			pulse_ph += rate / RATE
			if pulse_ph >= 1.0:
				pulse_ph -= 1.0
				x = (0.6 + randf() * 0.4) * sin(PI * k)
		var f := lerpf(520.0, 760.0, ct / creak_len) if ct > 0.0 else 520.0
		var w := TAU * f / RATE
		var r := 0.985
		var y := 2.0 * r * cos(w) * y1 - r * r * y2 + x
		y2 = y1
		y1 = y
		v += y * 0.09
		if opening:
			# kilidin açılması
			if t < 0.25:
				v += _ring(t, [1450.0, 2310.0, 3120.0], 28.0) * 0.35 + (randf() * 2.0 - 1.0) * exp(-t * 90.0) * 0.4
		else:
			# çarpma: tok gümbürtü + uzun metal çınlaması + kilit tıkı
			var ht := t - 0.32
			if ht > 0.0:
				v += sin(TAU * 52.0 * ht) * exp(-ht * 7.0) * 0.9
				v += (randf() * 2.0 - 1.0) * exp(-ht * 40.0) * 0.5
				v += _ring(ht, [182.0, 413.0, 871.0, 1530.0], 3.2) * 0.35
			var lt := t - 0.42
			if lt > 0.0:
				v += _ring(lt, [1800.0, 2900.0], 45.0) * 0.25
		s[i] = clampf(v, -1.0, 1.0)
	return _wav(s)


# Beton zeminde ayak sesi: kısa, boğuk vuruş.
static func step() -> AudioStreamWAV:
	var n := int(RATE * 0.16)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp = lerpf(lp, randf() * 2.0 - 1.0, 0.18)
		s[i] = (lp * 0.9 + sin(TAU * 90.0 * t) * 0.5) * exp(-t * 38.0)
	return _wav(s)


# Tavandan damlayan su: tiz "plink" ve küçük şıpırtı.
# Okul/hapishane zili: tokmak hızla vurur (titreşimli), madeni çınlama; ~2 sn.
static func bell() -> AudioStreamWAV:
	if _bell_c:
		return _bell_c
	_bell_c = _bell_uret()
	return _bell_c


static func _bell_uret() -> AudioStreamWAV:
	var n := int(RATE * 2.2)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := minf(1.0, t * 40.0) * (1.0 if t < 1.6 else exp(-(t - 1.6) * 6.0))
		var hit := 0.55 + 0.45 * absf(sin(TAU * 11.0 * t))  # tokmak
		var v := sin(TAU * 1180.0 * t) * 0.5 + sin(TAU * 2950.0 * t) * 0.25 + sin(TAU * 4130.0 * t) * 0.12 + sin(TAU * 590.0 * t) * 0.2
		s[i] = v * env * hit * 0.55
	return _wav(s)


static func drip() -> AudioStreamWAV:
	var n := int(RATE * 0.5)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * (1900.0 - 900.0 * minf(t * 12.0, 1.0)) / RATE
		s[i] = sin(ph) * exp(-t * 22.0) * 0.5 + (randf() * 2.0 - 1.0) * exp(-t * 60.0) * 0.12
	return _wav(s)


# =====================================================================
# SES DÜZENİ (default_bus_layout.tres + çalışırken eklenen Dunya bus'ı)
# Master (tepe sınırlayıcı) <- Muzik, Efekt, Ses (sesli sohbet); Ortam -> Efekt; Dunya (3B dünya sesleri,
# yankı) -> Efekt. Ayarlardaki "Oyun sesi" Efekt'i kısar (ortam ve dünya da onunla kısılır); müzik ve konuşma ayrı.
# =====================================================================

const BUS_EFEKT := &"Efekt"
const BUS_ORTAM := &"Ortam"
const BUS_DUNYA := &"Dunya"
const SES := "res://assets/ses/"


# Sahneye eklenen her ses çalar bus seçmemişse (Master) Efekt'e gider: yeni eklenen sesler de
# ayarlardaki efekt sesiyle kısılır. 3B sesler (dünyadakiler) Dunya bus'ına gider: hücrede küçük oda tınısı,
# koridorda hafif yankı alırlar. main.gd: get_tree().node_added.connect(Sfx.yonlendir)
static func yonlendir(n: Node) -> void:
	if n is AudioStreamPlayer or n is AudioStreamPlayer3D or n is AudioStreamPlayer2D:
		if n.bus == &"Master":
			n.bus = BUS_DUNYA if (n is AudioStreamPlayer3D and _dunya_var()) else BUS_EFEKT


static func _dunya_var() -> bool:
	return AudioServer.get_bus_index(BUS_DUNYA) >= 0


# Tek seferlik ses (konumsuz): çalar, bitince kendini siler. Dünyadaki bir düğüme eklenirse (oyuncunun kendi
# oturma/kalkma sesi gibi) yankı bus'ına gider.
static func tek(parent: Node, ad: String, db := 0.0, pitch := 1.0) -> void:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.stream = load(SES + ad + ".ogg")
	p.volume_db = db
	p.pitch_scale = pitch
	p.bus = BUS_DUNYA if (parent is Node3D and _dunya_var()) else BUS_EFEKT
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# Tek seferlik 3B ses: parent'a göre yerel konumda çalar, bitince kendini siler.
static func tek3d(parent: Node3D, pos: Vector3, ad: String, db := 0.0, unit := 3.0) -> void:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = load(SES + ad + ".ogg")
	p.volume_db = db
	p.unit_size = unit
	p.max_distance = 30.0
	p.position = pos
	p.bus = BUS_DUNYA if _dunya_var() else BUS_EFEKT
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# =====================================================================
# YANKI (mobilde ucuz: tek reverb efekti, Dunya bus'ında). muzik.gd _ready kurar; ayarlar dinleyicinin
# bulunduğu yere göre yumuşakça değişir: hücre = küçük beton oda tınısı, koridor = uzun çıplak koridor (biraz
# daha uzun kuyruk), yemekhane = büyük salon. Kuru ses hep tam (dry 1), yankı az.
# =====================================================================

const YANKI := {
	# oda boyu, sönüm, ıslak, ön gecikme (ms)
	"hucre": [0.22, 0.62, 0.10, 6.0],
	"koridor": [0.62, 0.42, 0.17, 22.0],
	"lobi": [0.55, 0.55, 0.13, 16.0],
}
static var _reverb: AudioEffectReverb
static var _sagir: AudioEffectLowPassFilter
static var _sagir_tw: Tween


static func ses_duzeni_kur() -> void:
	if not _dunya_var():
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, BUS_DUNYA)
		AudioServer.set_bus_send(i, BUS_EFEKT)
		_reverb = AudioEffectReverb.new()
		_reverb.dry = 1.0
		_reverb.spread = 0.6
		_reverb.hipass = 0.25  # alttaki gümbürtü yankılanıp çamurlaşmasın
		_reverb.predelay_feedback = 0.2
		_reverb.room_size = 0.22
		_reverb.damping = 0.62
		_reverb.wet = 0.10
		AudioServer.add_bus_effect(i, _reverb)
	# kulak boğulması (patlama): müzik, sesli sohbet ve ortamda bekleyen, kapalı alçak geçiren süzgeç
	if _sagir == null:
		_sagir = AudioEffectLowPassFilter.new()
		_sagir.cutoff_hz = 20000.0
		_sagir.resonance = 0.5
		for b in [&"Muzik", &"Ses", BUS_ORTAM]:
			var bi := AudioServer.get_bus_index(b)
			if bi >= 0:
				AudioServer.add_bus_effect(bi, _sagir)
				AudioServer.set_bus_effect_enabled(bi, AudioServer.get_bus_effect_count(bi) - 1, false)


# Yankıyı yere göre ayarla. k: geçiş oranı (her karede küçük k ile çağrılır, yumuşak geçer).
static func yanki_ayarla(yer: String, k: float) -> void:
	if _reverb == null or not YANKI.has(yer):
		return
	var h: Array = YANKI[yer]
	_reverb.room_size = lerpf(_reverb.room_size, h[0], k)
	_reverb.damping = lerpf(_reverb.damping, h[1], k)
	_reverb.wet = lerpf(_reverb.wet, h[2], k)
	_reverb.predelay_msec = lerpf(_reverb.predelay_msec, h[3], k)


# Patlamadan sonra kulak boğulur: müzik, sesli sohbet ve ortam 1-2 sn boğuk duyulur, sonra açılır.
# k: 0-1 (yakınlık). Efekt bus'ı (patlamanın kendisi ve kulak çınlaması) boğulmaz.
static func sagirlas(k: float) -> void:
	if _sagir == null:
		ses_duzeni_kur()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or _sagir == null:
		return
	_sagir_ac(true)
	_sagir.cutoff_hz = lerpf(2500.0, 280.0, clampf(k, 0.0, 1.0))
	if _sagir_tw and _sagir_tw.is_valid():
		_sagir_tw.kill()
	_sagir_tw = tree.create_tween()
	_sagir_tw.tween_interval(0.35 + 0.35 * k)
	_sagir_tw.tween_method(func(v: float) -> void: _sagir_kesim(v), _sagir.cutoff_hz, 20000.0, 1.1).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_EXPO)
	_sagir_tw.tween_callback(func() -> void: _sagir_ac(false))


static func _sagir_kesim(v: float) -> void:
	if _sagir:
		_sagir.cutoff_hz = v


static func _sagir_ac(on: bool) -> void:
	for b in [&"Muzik", &"Ses", BUS_ORTAM]:
		var bi := AudioServer.get_bus_index(b)
		if bi < 0:
			continue
		for e in AudioServer.get_bus_effect_count(bi):
			if AudioServer.get_bus_effect(bi, e) == _sagir:
				AudioServer.set_bus_effect_enabled(bi, e, on)


# =====================================================================
# C4: patlama (3B, yakın + uzak katman), geri sayım bipi hızlanır
# =====================================================================

# Patlama sesi: dünyada pos'ta çalar. Yakın katman (keskin patlama, gövde, alt bas, enkaz yağmuru) uzaklaştıkça
# kısılır; uzak katman (boğuk gümbürtü + koridor yankısı) uzakta öne çıkar. Yakındaysa (dist < 7 ya da elde)
# kulak çınlar ve müzik/sohbet kısa süre boğulur.
static func patlama(world: Node3D, pos: Vector3, dist: float, elimde := false) -> void:
	if not is_instance_valid(world) or not world.is_inside_tree():
		return
	var uzak := clampf((dist - 5.0) / 12.0, 0.0, 1.0)
	_patlama_katman(world, pos, "c4_patlama", 9.0, (6.0 if elimde else 3.0) - uzak * 14.0)
	_patlama_katman(world, pos, "c4_uzak", 30.0, lerpf(-12.0, 2.0, uzak))
	var yakin := 1.0 if elimde else clampf(1.0 - dist / 7.0, 0.0, 1.0)
	if yakin > 0.05:
		# kulak çınlaması doğrudan Master'a: boğulmaz
		var c := AudioStreamPlayer.new()
		c.stream = load(SES + "cinlama.ogg")
		c.volume_db = -4.0 + linear_to_db(yakin)
		world.add_child(c)
		c.bus = &"Master"
		c.finished.connect(c.queue_free)
		world.get_tree().create_timer(0.18).timeout.connect(func() -> void:
			if is_instance_valid(c):
				c.play())
		sagirlas(yakin)


static func _patlama_katman(world: Node3D, pos: Vector3, ad: String, unit: float, db: float) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = load(SES + ad + ".ogg")
	p.unit_size = unit
	p.max_db = 6.0
	p.max_distance = 90.0
	p.volume_db = db
	p.bus = BUS_DUNYA if _dunya_var() else BUS_EFEKT
	world.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


# C4 bipi hızlanır: bomba aynı kişide kaldıkça bipler sıklaşır (1 sn -> 0.3 sn, ~35 sn'de).
# Patlama anı kimseye söylenmez; hız yalnızca bombanın o kişide ne kadar kaldığına bağlı.
# Dönüş: bip döngüsünün (0-1) saniyedeki ilerlemesi. c4_ui.gd: _blink_t + delta * Sfx.c4_hiz(self, holder, delta)
static func c4_hiz(n: Object, holder: int, delta: float) -> float:
	if int(n.get_meta("_c4_h", -1)) != holder:
		n.set_meta("_c4_h", holder)
		n.set_meta("_c4_t", 0.0)
	var t: float = float(n.get_meta("_c4_t", 0.0)) + delta
	n.set_meta("_c4_t", t)
	var k := clampf(t / 35.0, 0.0, 1.0)
	return 1.0 / lerpf(1.0, 0.3, k * k * (3.0 - 2.0 * k))


# =====================================================================
# KISA DEVRE: elektrik kesilince şalter "kılık" + trafo sönmesi; geri gelince floresan tıkları ve vızıltı.
# cell.gd set_power'dan, yalnızca durum değişince çağrılır. power_on_sequence ışığı birkaç kez yakıp söndürür:
# ilk değişiklik sesi çalar (dosyadaki tıklar bu titremeye denk gelir), 1.5 sn içindeki diğerleri sessiz.
# =====================================================================

static func elektrik(cell: Node3D, on: bool) -> void:
	if not is_instance_valid(cell) or not cell.is_inside_tree():
		return
	var now := Time.get_ticks_msec()
	var son := int(cell.get_meta("_elk_t", -100000))
	cell.set_meta("_elk_t", now)
	if now - son < 1500:
		return
	tek3d(cell, Vector3(0.0, 2.6, 0.0), "floresan_yan" if on else "elektrik_kes", -2.0 if on else 0.0, 3.0)


# =====================================================================
# ARAYÜZ: dokunma (ui.gd tik_ui), pencere açılış/kapanış, ödül, seviye atlama — aynı ses ailesi
# (yumuşak tık + La majör notalar, marimba gibi çabuk söner). Sfx.arayuz("ui_ac" | "ui_kapa" | "odul" | "seviye")
# =====================================================================

const ARAYUZ_DB := {"ui_ac": -9.0, "ui_kapa": -10.0, "odul": -4.0, "seviye": -2.0}
static var _arayuz: AudioStreamPlayer
static var _arayuz_son := {}


static func arayuz(ad: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var ui = load("res://scripts/ui.gd")
	if ui and not ui.ses_acik:
		return  # ayarlardan arayüz sesleri kapatıldı
	# aynı ses art arda yığılmasın (ör. iç içe açılan pencereler)
	var now := Time.get_ticks_msec()
	if now - int(_arayuz_son.get(ad, -1000)) < 120:
		return
	_arayuz_son[ad] = now
	if not is_instance_valid(_arayuz):
		_arayuz = AudioStreamPlayer.new()
		_arayuz.max_polyphony = 3
		_arayuz.bus = BUS_EFEKT
		tree.root.add_child.call_deferred(_arayuz)
	_arayuz.stream = load(SES + ad + ".ogg")
	_arayuz.volume_db = float(ARAYUZ_DB.get(ad, -6.0))
	if _arayuz.is_inside_tree():
		_arayuz.play()
	elif not _arayuz.ready.is_connected(_arayuz.play):
		_arayuz.ready.connect(_arayuz.play, CONNECT_ONE_SHOT)


# =====================================================================
# AYAK SESLERİ: yüzeye göre (beton / metal / ahşap) 6 yürüme + 6 koşma kaydı, her adımda rastgele biri, perde ±%5.
# Yüzey konumdan basit bir kuralla: hücre ve koridor beton; hücre kapısının çelik eşiği (ray) metal;
# yemekhane (main.gd LOBBY_POS = (-40, 0, 0), 14 x 12 m) ahşap.
# =====================================================================

const ADIM_ARALIK := 0.52  # hız 1'de (yürüme) iki adım arası saniye; koşarken hızla kısalır
const ZEMIN_SES := {
	"beton": ["adim_%d", "kos_%d", 0.0],
	"metal": ["adim_metal_%d", "adim_metal_%d", 1.0],
	"ahsap": ["adim_ahsap_%d", "kos_ahsap_%d", 0.0],
}


# Yürüme ya da koşma kayıtlarından rastgele seçen akış (oynatıcı başına bir kez kurulur, meta'da saklanır).
static func adim_sesi(kos: bool, zemin_adi := "beton") -> AudioStreamRandomizer:
	var z: Array = ZEMIN_SES.get(zemin_adi, ZEMIN_SES["beton"])
	var r := AudioStreamRandomizer.new()
	for i in 6:
		r.add_stream(-1, load(SES + (str(z[1]) if kos else str(z[0])) % i + ".ogg"))
	r.random_pitch = 1.05
	r.random_volume_offset_db = 1.5
	return r


# Ayağın bastığı yüzey (n: ses çalar ya da onun dünyadaki ebeveyni).
static func zemin(n: Node) -> String:
	var n3: Node3D = n as Node3D
	if n3 == null:
		n3 = n.get_parent() as Node3D
	if n3 == null or not n3.is_inside_tree():
		return "beton"
	var pos := n3.global_position
	if pos.x < -28.0:
		return "ahsap"
	var w := n3.get_tree().current_scene
	var cells = w.get("cells") if w else null
	if cells is Array:
		for c in cells:
			if c is Node3D and c.has_method("door_world"):
				var d: Vector3 = c.door_world()
				if absf(pos.x - d.x) < 0.4 and absf(pos.z - d.z) < 0.62:
					return "metal"
	return "beton"


# Bir adım çal. hiz: 1 = yürüme, ~1.9 = koşma, 0.5 = çömelerek. Çömelince çok daha sessiz.
static func adim_cal(p: Node, hiz: float, comel: bool) -> void:
	var kos := hiz > 1.35 and not comel
	var z := zemin(p)
	var anahtar := ("kos_" if kos else "adim_") + z
	if not p.has_meta(anahtar):
		p.set_meta(anahtar, adim_sesi(kos, z))
	var s: AudioStream = p.get_meta(anahtar)
	if p.stream != s:
		p.stream = s  # akış değişince çalan adım kesilir: yalnız yürüme <-> koşma ya da yüzey geçişinde
	p.volume_db = (-5.0 if kos else -8.0) - (10.0 if comel else 0.0) + float(ZEMIN_SES[z][2])
	if p is AudioStreamPlayer and p.bus == BUS_EFEKT and _dunya_var():
		p.bus = BUS_DUNYA  # oyuncunun kendi adımları da oda/koridor yankısını alsın
	p.play()


# Giysi hışırtısı (eğilme, kalkma). parent Node3D ise 3B, değilse konumsuz.
static func kumas(parent: Node, db := -6.0) -> void:
	var ad := "kumas_%d" % (randi() % 3 + 1)
	if parent is Node3D and not (parent is CharacterBody3D):
		tek3d(parent, Vector3(0, 0.9, 0), ad, db, 2.0)
	else:
		tek(parent, ad, db, randf_range(0.95, 1.05))


# Uzak oyuncunun ayak sesi, koltuk ve eğilme sesi (main.gd _update_remotes'tan her kare).
# r: uzak oyuncu sözlüğü (çalar ve zamanlayıcı burada tutulur), hiz: yürüme hızına oranla hız.
static func uzak_adim(r: Dictionary, root: Node3D, hiz: float, comel: bool, oturuyor: bool, delta: float) -> void:
	var p: AudioStreamPlayer3D = r.get("_adim")
	if p == null:
		p = AudioStreamPlayer3D.new()
		p.unit_size = 2.5
		p.max_polyphony = 2
		p.max_distance = 24.0
		p.position.y = 0.1
		p.bus = BUS_DUNYA if _dunya_var() else BUS_EFEKT
		root.add_child(p)
		r["_adim"] = p
		r["_adim_t"] = 0.25
		r["_otur"] = oturuyor
		r["_comel"] = comel
	if bool(r["_otur"]) != oturuyor:
		r["_otur"] = oturuyor
		tek3d(root, Vector3(0, 0.5, 0), "koltuk_otur" if oturuyor else "koltuk_kalk", -6.0, 2.5)
	if bool(r.get("_comel", comel)) != comel:
		r["_comel"] = comel
		if not oturuyor:
			tek3d(root, Vector3(0, 0.9, 0), "kumas_%d" % (randi() % 3 + 1), -8.0, 2.0)
	# ışınlanma (doğma, koltuğa geçiş) adım sayılmasın
	if oturuyor or hiz < 0.15 or hiz > 3.0:
		r["_adim_t"] = minf(float(r["_adim_t"]), 0.2)
		return
	var t: float = float(r["_adim_t"]) - delta * minf(hiz, 2.0)
	if t <= 0.0:
		t = ADIM_ARALIK
		adim_cal(p, hiz, comel)
	r["_adim_t"] = t
