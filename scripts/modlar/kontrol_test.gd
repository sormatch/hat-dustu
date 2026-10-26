# Kontrol hissi testi (main.gd pose=kontrol): ekrana gerçek dokunma olayları (InputEventScreenTouch/Drag)
# gönderilir; joystick, bakış, iki parmak, düğme üstündeki parmak, duvar kayması, kapıdan geçiş, eğilme,
# sarsıntı ve kare başı maliyet ölçülür. Sonuçlar "[kontrol]" önekiyle yazılır.
#   adim=hepsi|ivme|bakis|iki|dugme|titreme|egim|duvar|kapi|egil|sars|olcum  (virgülle birden çok)
#   shot=<png> (sonunda aşağı bakış sınırında çekim)
extends RefCounted

static var _w: Node3D
static var _p: CharacterBody3D


static func run(w: Node3D, args: Dictionary) -> void:
	_w = w
	_p = w.player
	w.solo_ring_wait = 1000.0
	w.hud.visible = true
	var adim := str(args.get("adim", "hepsi"))
	var hepsi := adim == "hepsi"
	var c0: Node3D = w.cells[0]
	c0.set_door(true, true)
	await _bekle(0.8)
	if args.has("eski"):
		# karşılaştırma: eski çarpışma ayarları (Godot varsayılanları)
		_p.wall_min_slide_angle = deg_to_rad(15.0)
		_p.safe_margin = 0.001
		_p.floor_snap_length = 0.1
	print("[kontrol] surum: ", "eski carpisma ayari" if args.has("eski") else "yeni")
	if hepsi or "ivme" in adim:
		await _ivme(c0)
	if hepsi or "bakis" in adim:
		await _bakis(c0)
	if hepsi or "iki" in adim:
		await _iki_parmak(c0)
	if hepsi or "dugme" in adim:
		await _dugme(c0)
	if hepsi or "titreme" in adim:
		await _titreme(c0)
	if hepsi or "duvar" in adim:
		await _duvar(c0)
	if hepsi or "kapi" in adim:
		await _kapi(c0)
	if hepsi or "egil" in adim:
		await _egil(c0)
	if hepsi or "sars" in adim:
		await _sars()
	if hepsi or "olcum" in adim:
		await _olcum(c0)
	if hepsi or "egim" in adim:
		await _egim(c0)


# ---------------------------------------------------------------- yardımcılar

static func _bekle(s: float) -> void:
	await _w.get_tree().create_timer(s).timeout


static func _vs() -> Vector2:
	return _w.hud.get_viewport().get_visible_rect().size


static func _dokun(i: int, pos: Vector2, basili: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = pos
	e.pressed = basili
	Input.parse_input_event(e)


static func _surukle(i: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = pos
	e.relative = rel
	e.screen_relative = rel
	Input.parse_input_event(e)


static func _yer(c0: Node3D, lp: Vector3, yon_derece: float) -> void:
	# lp hücre içinde; yon_derece: 0 = hücrenin -z yönüne (tahtaya) bakış, 90 = +x (kapıya)
	_p.velocity = Vector3.ZERO
	if "_yatay" in _p:
		_p.set("_yatay", Vector3.ZERO)
	_p.global_position = c0.to_global(lp)
	_p.rotation.y = c0.global_rotation.y - deg_to_rad(yon_derece)
	_p.head.rotation.x = 0.0


static func _joy_merkez() -> Vector2:
	var vs := _vs()
	return Vector2(vs.x * 0.17, vs.y * 0.72)


static func _hiz() -> float:
	return Vector2(_p.velocity.x, _p.velocity.z).length()


# ---------------------------------------------------------------- testler

# Joystick: dokunduğun yerde açılır mı, hızlanma/yavaşlama süresi, yavaş ve tam yürüme.
static func _ivme(c0: Node3D) -> void:
	_yer(c0, Vector3(0.0, 0, 2.4), 0.0)
	await _bekle(0.3)
	var c := _joy_merkez()
	_dokun(0, c, true)
	await _w.get_tree().process_frame
	var joy: Control = _w.hud.joy
	print("[kontrol] joystick merkezi=", joy.get_global_rect().get_center().round(), " dokunus=", c.round(), " (dinamik: ayni olmali)")
	# yavaş itiş (%40)
	_surukle(0, c + Vector2(0, -34), Vector2(0, -34))
	var once := _p.global_position
	await _bekle(0.8)
	var yavas := (_p.global_position - once).length() / 0.8
	# tam itiş
	_surukle(0, c + Vector2(0, -85), Vector2(0, -51))
	await _bekle(0.8)
	_dokun(0, c + Vector2(0, -85), false)
	print("[kontrol] yavas itis hizi=%.2f m/sn" % yavas)
	# baştan: hızlanma eğrisi
	await _bekle(0.6)
	_yer(c0, Vector3(0.0, 0, 2.4), 0.0)
	await _bekle(0.2)
	_dokun(0, c, true)
	_surukle(0, c + Vector2(0, -85), Vector2(0, -85))
	var t := 0.0
	var t90 := -1.0
	var prev := _p.global_position
	while t < 1.0:
		await _w.get_tree().physics_frame
		var dt := 1.0 / Engine.physics_ticks_per_second
		t += dt
		var v := (_p.global_position - prev).length() / dt
		prev = _p.global_position
		if t90 < 0.0 and v >= 0.9 * 2.4:
			t90 = t
	var tam := _hiz()
	_dokun(0, c + Vector2(0, -85), false)
	var dur_t := 0.0
	var kayma := 0.0
	prev = _p.global_position
	while dur_t < 1.0:
		await _w.get_tree().physics_frame
		var dt := 1.0 / Engine.physics_ticks_per_second
		dur_t += dt
		var d := (_p.global_position - prev).length()
		prev = _p.global_position
		kayma += d
		if d / dt < 0.05:
			break
	print("[kontrol] tam itis hizi=%.2f m/sn  %%90 hiza=%.3f sn  birakinca durma=%.3f sn kayma=%.3f m" % [tam, t90, dur_t, kayma])


# Bakış: sağ yarıda sürükleme dönüşü, hassasiyet çarpanı.
static func _bakis(c0: Node3D) -> void:
	_yer(c0, Vector3(0.0, 0, 1.0), 0.0)
	await _bekle(0.3)
	var vs := _vs()
	var s := Vector2(vs.x * 0.72, vs.y * 0.45)
	for sens in [1.0, 2.0]:
		_p.sensitivity = sens
		var y0 := _p.rotation.y
		_dokun(1, s, true)
		await _w.get_tree().process_frame
		var pos := s
		for i in 10:
			pos += Vector2(20, 0)
			_surukle(1, pos, Vector2(20, 0))
			await _w.get_tree().process_frame
		_dokun(1, pos, false)
		await _bekle(0.3)
		print("[kontrol] bakis hassasiyet=%.1f 200px -> %.1f derece" % [sens, rad_to_deg(y0 - _p.rotation.y)])
	_p.sensitivity = 1.0


# İki parmak: joystick ileri tutulurken diğer parmak bakar.
static func _iki_parmak(c0: Node3D) -> void:
	_yer(c0, Vector3(0.0, 0, 2.4), 0.0)
	await _bekle(0.3)
	var c := _joy_merkez()
	_dokun(0, c, true)
	_surukle(0, c + Vector2(0, -85), Vector2(0, -85))
	await _bekle(0.5)
	var vs := _vs()
	var s := Vector2(vs.x * 0.75, vs.y * 0.4)
	var y0 := _p.rotation.y
	_dokun(1, s, true)
	var en_az := 99.0
	var pos := s
	for i in 12:
		pos += Vector2(-10, 0)
		_surukle(1, pos, Vector2(-10, 0))
		await _w.get_tree().physics_frame
		en_az = minf(en_az, _hiz())
	_dokun(1, pos, false)
	await _bekle(0.2)
	var hareket := _w.hud.move as Vector2
	_dokun(0, c + Vector2(0, -85), false)
	print("[kontrol] iki parmak: donus=%.1f derece  yururken en dusuk hiz=%.2f  joystick hala=%s" % [rad_to_deg(_p.rotation.y - y0), en_az, str(hareket.length() > 0.5)])
	await _bekle(0.5)


# Düğmeye basan parmak bakışı döndürmemeli.
static func _dugme(c0: Node3D) -> void:
	_yer(c0, Vector3(0.0, 0, 1.0), 0.0)
	await _bekle(0.3)
	var hud = _w.hud
	for ad in ["crouch_btn", "emote_btn", "action_btn"]:
		var b: Control = hud.get(ad)
		if b == null or not b.is_visible_in_tree():
			print("[kontrol] dugme %s gorunmuyor" % ad)
			continue
		var s: Vector2 = b.get_global_rect().get_center()
		var y0 := _p.rotation.y
		var x0: float = _p.head.rotation.x
		_dokun(1, s, true)
		await _w.get_tree().process_frame
		var pos := s
		for i in 8:
			pos += Vector2(-15, 6)
			_surukle(1, pos, Vector2(-15, 6))
			await _w.get_tree().process_frame
		await _bekle(0.15)
		print("[kontrol] dugme %s ustunde surukleme: donus=%.2f derece egim=%.2f derece" % [ad, rad_to_deg(_p.rotation.y - y0), rad_to_deg(_p.head.rotation.x - x0)])
		# basılı parmağı düğmenin dışında bırak (düğmeye tıklanmasın)
		_dokun(1, pos, false)
		await _bekle(0.2)
		if _p.crouched:
			_p.toggle_crouch()
		if hud.emote_panel.visible:
			hud.emote_panel.visible = false
		await _bekle(0.3)


# Düzensiz gelen dokunma olayları (bazı karelerde iki olay, bazısında hiç): kare kare dönüş ne kadar titrek.
static func _titreme(c0: Node3D) -> void:
	_yer(c0, Vector3(0.0, 0, 1.0), 0.0)
	await _bekle(0.3)
	var vs := _vs()
	var s := Vector2(vs.x * 0.7, vs.y * 0.45)
	_dokun(1, s, true)
	await _w.get_tree().process_frame
	var desen := [14.0, 0.0, 22.0, 6.0, 0.0, 18.0, 10.0, 0.0, 24.0, 4.0]
	var adimlar: Array[float] = []
	var pos := s
	var prev := _p.rotation.y
	for r in 3:
		for d in desen:
			if d > 0.0:
				pos += Vector2(d, 0)
				_surukle(1, pos, Vector2(d, 0))
			await _w.get_tree().process_frame
			adimlar.append(rad_to_deg(prev - _p.rotation.y))
			prev = _p.rotation.y
	_dokun(1, pos, false)
	for i in 10:
		await _w.get_tree().process_frame
		adimlar.append(rad_to_deg(prev - _p.rotation.y))
		prev = _p.rotation.y
	var ort := 0.0
	for a in adimlar.slice(0, 30):
		ort += a
	ort /= 30.0
	var sap := 0.0
	var dur := 0
	for a in adimlar.slice(0, 30):
		sap += (a - ort) * (a - ort)
		if a < 0.05:
			dur += 1
	sap = sqrt(sap / 30.0)
	print("[kontrol] duzensiz dokunma: kare basi donus ort=%.2f sapma=%.2f derece  donmeyen kare=%d/30  (sapma/ort=%.2f)" % [ort, sap, dur, sap / maxf(ort, 0.001)])
	await _bekle(0.3)


# Duvara sürtünerek yürüme: hücre ortasına geçici bir duvar kurulur (oyundaki gibi yan yana üç kutu: birleşim
# yerlerine takılma da ölçülür); duvara 10/30/60 derece açıyla itince duvar boyunca kayma hızı.
static func _duvar(c0: Node3D) -> void:
	var c := _joy_merkez()
	var duvar := Node3D.new()
	c0.add_child(duvar)
	for i in 3:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(0.1, 2.0, 0.8)
		cs.shape = sh
		sb.add_child(cs)
		sb.position = Vector3(0.35, 1.0, 2.2 - i * 0.8)
		duvar.add_child(sb)
	for aci in [30.0, 10.0, 60.0]:
		# geçici duvar (x = 0,3 yüzü) boyunca -z yönüne, duvara doğru "aci" derece
		_yer(c0, Vector3(-0.05, 0, 2.4), aci)
		await _bekle(0.2)
		_dokun(0, c, true)
		_surukle(0, c + Vector2(0, -85), Vector2(0, -85))
		var z0: float = c0.to_local(_p.global_position).z
		var tak := 0
		var prev := _p.global_position
		for i in 60:
			await _w.get_tree().physics_frame
			var v := (_p.global_position - prev).length() * Engine.physics_ticks_per_second
			prev = _p.global_position
			if i > 15 and v < 0.25:
				tak += 1
		var lp: Vector3 = c0.to_local(_p.global_position)
		_dokun(0, c + Vector2(0, -85), false)
		var beklenen := 2.4 * cos(deg_to_rad(aci))
		print("[kontrol] duvar %d derece: 1 sn'de duvar boyunca %.2f m (ideal ~%.2f), takilan kare=%d, x=%.2f" % [int(aci), z0 - lp.z, beklenen, tak, lp.x])
		await _bekle(0.4)
	duvar.queue_free()
	await _w.get_tree().physics_frame


# Kapıdan geçiş: açık kapıya (aralık z 0..1, gövde çapı 0,6) hücre içinden yürü. Başlangıç yanlara kaymış
# (kasaya sürtecek) ve hafif açılı: kasanın köşesine takılmadan kayıp geçmeli.
static func _kapi(c0: Node3D) -> void:
	var c := _joy_merkez()
	var gecen := 0
	var toplam := 0
	var sureler := 0.0
	for z in [0.12, 0.25, 0.5, 0.75, 0.88]:
		for aci in [78.0, 90.0, 102.0]:
			toplam += 1
			# 1,1 m geriden; yürüyüş çizgisi kapı düzlemini (x = 2,1) z noktasında keser (açı 90 = dümdüz +x)
			var a := deg_to_rad(aci)
			_yer(c0, Vector3(1.0, 0, z + 1.1 * cos(a) / sin(a)), aci)
			await _w.get_tree().physics_frame
			_dokun(0, c, true)
			_surukle(0, c + Vector2(0, -85), Vector2(0, -85))
			var t := 0.0
			var ok := false
			while t < 2.5:
				await _w.get_tree().physics_frame
				t += 1.0 / Engine.physics_ticks_per_second
				if c0.to_local(_p.global_position).x > 2.7:
					ok = true
					break
			_dokun(0, c + Vector2(0, -85), false)
			if ok:
				gecen += 1
				sureler += t
			else:
				var lp: Vector3 = c0.to_local(_p.global_position)
				print("[kontrol] kapi takildi: z=%.2f aci=%d -> (%.2f, %.2f)" % [z, int(aci), lp.x, lp.z])
	print("[kontrol] kapi: %d/%d gecis, ort sure=%.2f sn" % [gecen, toplam, sureler / maxf(gecen, 1)])


# Eğilme: göz yüksekliği kare kare (yürürken) sıçrıyor mu.
static func _egil(c0: Node3D) -> void:
	_yer(c0, Vector3(0.0, 0, 2.4), 0.0)
	await _bekle(0.3)
	var c := _joy_merkez()
	_dokun(0, c, true)
	_surukle(0, c + Vector2(0, -85), Vector2(0, -85))
	await _bekle(0.4)
	var y0: float = _p.head.position.y + _p.camera.position.y
	_p.toggle_crouch()
	var en_buyuk := 0.0
	var prev := y0
	var sure := -1.0
	for i in 40:
		await _w.get_tree().process_frame
		var y: float = _p.head.position.y + _p.camera.position.y
		en_buyuk = maxf(en_buyuk, absf(y - prev))
		prev = y
		if sure < 0.0 and absf(y - (y0 - 0.5)) < 0.06:
			sure = i / 60.0
	_dokun(0, c + Vector2(0, -85), false)
	print("[kontrol] egilme (yururken): goz %.2f -> %.2f, kare basi en buyuk sicrama=%.3f m" % [y0, prev, en_buyuk])
	_p.toggle_crouch()
	await _bekle(0.6)


static func _sars() -> void:
	if not _p.has_method("sars"):
		print("[kontrol] sars yok (eski)")
		return
	_p.sars(0.12, 0.6)
	var en := 0.0
	for i in 50:
		await _w.get_tree().process_frame
		en = maxf(en, absf(_p.camera.h_offset) + absf(_p.camera.v_offset))
	print("[kontrol] sars(0.12, 0.6): en buyuk kayma=%.3f, sonra h=%.4f v=%.4f" % [en, _p.camera.h_offset, _p.camera.v_offset])


# Kare başı maliyet: oyuncunun _process ve _physics_process'i (mikrosaniye).
static func _olcum(c0: Node3D) -> void:
	_yer(c0, Vector3(0.0, 0, 1.0), 0.0)
	await _bekle(0.3)
	var n := 3000
	_p.move_input = Vector2.ZERO
	var t0 := Time.get_ticks_usec()
	for i in n:
		_p._process(1.0 / 60.0)
	var proc := float(Time.get_ticks_usec() - t0) / n
	var mem0 := OS.get_static_memory_usage()
	var obj0 := Performance.get_monitor(Performance.OBJECT_COUNT)
	t0 = Time.get_ticks_usec()
	for i in n:
		_p.look(Vector2(0.3, 0.0))
		_p._process(1.0 / 60.0)
	var bak := float(Time.get_ticks_usec() - t0) / n
	_p.set_physics_process(false)
	t0 = Time.get_ticks_usec()
	for i in 600:
		_p.move_input = Vector2(0.3 * sin(i * 0.05), -0.5)
		_p._physics_process(1.0 / 60.0)
	var fiz := float(Time.get_ticks_usec() - t0) / 600.0
	_p.set_physics_process(true)
	_p.move_input = Vector2.ZERO
	print("[kontrol] maliyet: _process=%.1f us, bakisla=%.1f us, _physics_process=%.1f us; nesne farki=%d bellek farki=%d bayt" % [proc, bak, fiz, Performance.get_monitor(Performance.OBJECT_COUNT) - obj0, OS.get_static_memory_usage() - mem0])
	await _bekle(0.3)


# Aşağı bakış sınırı (en sonda; ekran görüntüsü bu duruşta alınır).
static func _egim(c0: Node3D) -> void:
	_yer(c0, Vector3(0.0, 0, 0.6), 0.0)
	await _bekle(0.3)
	var vs := _vs()
	var s := Vector2(vs.x * 0.7, vs.y * 0.2)
	_dokun(1, s, true)
	var pos := s
	for i in 20:
		pos += Vector2(0, 30)
		_surukle(1, pos, Vector2(0, 30))
		await _w.get_tree().process_frame
	_dokun(1, pos, false)
	await _bekle(0.5)
	print("[kontrol] asagi bakis siniri=%.1f derece" % rad_to_deg(_p.head.rotation.x))
