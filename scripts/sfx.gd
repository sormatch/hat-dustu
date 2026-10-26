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
static func ring(kind := 0) -> AudioStreamWAV:
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
# SES DÜZENİ (default_bus_layout.tres)
# Master (tepe sınırlayıcı) <- Muzik, Efekt, Ses (sesli sohbet); Ortam -> Efekt.
# Ayarlardaki "Oyun sesi" Efekt'i kısar (ortam da onunla kısılır); müzik ve konuşma ayrı.
# =====================================================================

const BUS_EFEKT := &"Efekt"
const BUS_ORTAM := &"Ortam"
const SES := "res://assets/ses/"


# Sahneye eklenen her ses çalar bus seçmemişse (Master) Efekt'e gider: yeni eklenen sesler de
# ayarlardaki efekt sesiyle kısılır. main.gd: get_tree().node_added.connect(Sfx.yonlendir)
static func yonlendir(n: Node) -> void:
	if n is AudioStreamPlayer or n is AudioStreamPlayer3D or n is AudioStreamPlayer2D:
		if n.bus == &"Master":
			n.bus = BUS_EFEKT


# Tek seferlik ses (konumsuz): çalar, bitince kendini siler.
static func tek(parent: Node, ad: String, db := 0.0, pitch := 1.0) -> void:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.stream = load(SES + ad + ".ogg")
	p.volume_db = db
	p.pitch_scale = pitch
	p.bus = BUS_EFEKT
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
	p.bus = BUS_EFEKT
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# =====================================================================
# AYAK SESLERİ (beton): 6 yürüme + 6 koşma kaydı, her adımda rastgele biri, perde ±%5
# =====================================================================

const ADIM_ARALIK := 0.52  # hız 1'de (yürüme) iki adım arası saniye; koşarken hızla kısalır
# Yürüme ya da koşma kayıtlarından rastgele seçen akış (oynatıcı başına bir kez kurulur, meta'da saklanır).
static func adim_sesi(kos: bool) -> AudioStreamRandomizer:
	var r := AudioStreamRandomizer.new()
	for i in 6:
		r.add_stream(-1, load(SES + ("kos_%d.ogg" if kos else "adim_%d.ogg") % i))
	r.random_pitch = 1.05
	r.random_volume_offset_db = 1.5
	return r


# Bir adım çal. hiz: 1 = yürüme, ~1.9 = koşma, 0.5 = çömelerek. Çömelince çok daha sessiz.
static func adim_cal(p: Node, hiz: float, comel: bool) -> void:
	var kos := hiz > 1.35 and not comel
	var anahtar := "kos" if kos else "adim"
	if not p.has_meta(anahtar):
		p.set_meta(anahtar, adim_sesi(kos))
	var s: AudioStream = p.get_meta(anahtar)
	if p.stream != s:
		p.stream = s  # akış değişince çalan adım kesilir: yalnız yürüme <-> koşma geçişinde
	p.volume_db = (-5.0 if kos else -8.0) - (10.0 if comel else 0.0)
	p.play()


# Uzak oyuncunun ayak sesi ve koltuk sesi (main.gd _update_remotes'tan her kare).
# r: uzak oyuncu sözlüğü (çalar ve zamanlayıcı burada tutulur), hiz: yürüme hızına oranla hız.
static func uzak_adim(r: Dictionary, root: Node3D, hiz: float, comel: bool, oturuyor: bool, delta: float) -> void:
	var p: AudioStreamPlayer3D = r.get("_adim")
	if p == null:
		p = AudioStreamPlayer3D.new()
		p.unit_size = 2.5
		p.max_polyphony = 2
		p.max_distance = 24.0
		p.position.y = 0.1
		p.bus = BUS_EFEKT
		root.add_child(p)
		r["_adim"] = p
		r["_adim_t"] = 0.25
		r["_otur"] = oturuyor
	if bool(r["_otur"]) != oturuyor:
		r["_otur"] = oturuyor
		tek3d(root, Vector3(0, 0.5, 0), "koltuk_otur" if oturuyor else "koltuk_kalk", -6.0, 2.5)
	# ışınlanma (doğma, koltuğa geçiş) adım sayılmasın
	if oturuyor or hiz < 0.15 or hiz > 3.0:
		r["_adim_t"] = minf(float(r["_adim_t"]), 0.2)
		return
	var t: float = float(r["_adim_t"]) - delta * minf(hiz, 2.0)
	if t <= 0.0:
		t = ADIM_ARALIK
		adim_cal(p, hiz, comel)
	r["_adim_t"] = t
