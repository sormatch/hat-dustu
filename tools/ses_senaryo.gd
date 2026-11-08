# Sesli konuşma senaryo testi (telefonsuz, hoparlörsüz). A kişisinin sesi mikrofon gibi Mikrofon bus'ına verilir,
# voice.gd kodlar, taklit ağdan geçip yine voice.gd ile çalınır; aynı anda B kişisinin önceden kodlanmış paketleri
# de gelebilir (iki kişi). Yankı: B'nin sesi hoparlörden mikrofona kaçmış gibi kısık olarak mikrofona da verilir.
# Çıkış ("Ses" bus'ı) WAV'a yazılır; tools/ses_rapor.mjs ölçer.
# Kullanım: Godot --headless --path . --script res://tools/ses_senaryo.gd -- surum=yeni|eski a=erkek a_db=0 b=kadin
#   b_db=0 gurultu_db=-99 yanki_db=-99 telefon=0 ag=sabit|dalgali|kotu kare=60|yavas sure=18 cikti=build/ses/s/x.wav
extends SceneTree

const K := "D:/HatDustu/build/ses/kaynak/"
var args := {}
var voice: Node  # konuşan (mikrofon)
var dinleyen: Node  # dinleyen (çıkış kaydı bundan)
var kuyruk := []  # [çıkış ms, paket]
var b_paket := []  # B'nin 40 ms'lik mu-law parçaları
var b_i := 0
var b_bas := 0
var kayit: AudioEffectRecord
var t0 := 0
var bitis := 0
var hazir := false
var rng := RandomNumberGenerator.new()
var stall_bitis := 0  # kötü ağ: bu ana kadar hiçbir paket gelmez (TCP yeniden iletim takılması)
var islem_us := 0
var islem_t := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var p := String(a).split("=", true, 1)
		if p.size() == 2:
			args[p[0]] = p[1]
	rng.seed = int(args.get("tohum", "7"))
	Engine.max_fps = 60
	var bet: Script
	if str(args.get("surum", "yeni")) == "eski":
		var g := GDScript.new()
		g.source_code = FileAccess.get_file_as_string("res://build/ses/voice_eski.gd.txt")
		g.reload()
		bet = g
	else:
		bet = load("res://scripts/voice.gd")
	voice = Node.new()
	voice.set_script(bet)
	root.add_child(voice)
	voice.set_process(false)
	voice.packet_ready.connect(func(data: PackedByteArray) -> void: _ag(1, data))
	dinleyen = Node.new()
	dinleyen.set_script(bet)
	root.add_child(dinleyen)
	dinleyen.set_process(false)
	dinleyen.test_tone = true  # mikrofon yakalamasını konuşandan çalmasın; yolladığı paketler kullanılmaz


func _wav(ad: String, db: float, gecikme := 0.0) -> AudioStreamPlayer:
	var s := AudioStreamWAV.load_from_file(K + ad)
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = &"Mikrofon"
	p.volume_db = db
	root.add_child(p)
	if gecikme > 0.0:
		create_timer(gecikme).timeout.connect(p.play)
	else:
		p.play()
	return p


# B'nin 16 kHz kaydını 40 ms'lik parçalara böl, voice.gd ile aynı mu-law ile kodla
func _b_hazirla(ad: String, db: float) -> void:
	var f := FileAccess.open(K + ad + ".wav", FileAccess.READ)
	var veri := f.get_buffer(f.get_length())
	var i := 12
	var bas := -1
	var boy := 0
	while i + 8 <= veri.size():
		var ck := veri.slice(i, i + 4).get_string_from_ascii()
		var n := veri.decode_u32(i + 4)
		if ck == "data":
			bas = i + 8
			boy = n
			break
		i += 8 + n + (n & 1)
	var kat := db_to_linear(db)
	var parca := PackedByteArray()
	var j := bas
	while j + 1 < bas + boy:
		var x := float(veri.decode_s16(j)) / 32768.0 * kat
		parca.append(voice._enc(x))
		if parca.size() == 640:
			b_paket.append(parca)
			parca = PackedByteArray()
		j += 2


func _ag(id: int, data: PackedByteArray) -> void:
	var simdi := Time.get_ticks_msec()
	var gecik := 20.0
	match str(args.get("ag", "sabit")):
		"dalgali":
			gecik = rng.randf_range(20.0, 180.0)
			if rng.randf() < 0.02:
				gecik += 300.0
		"kotu":
			gecik = rng.randf_range(40.0, 260.0)
			if rng.randf() < 0.01:
				stall_bitis = maxi(stall_bitis, simdi + rng.randi_range(400, 900))
	var p := PackedByteArray([id])
	p.append_array(data)
	var cikis := maxi(simdi + int(gecik), stall_bitis)
	# TCP sırayı korur: öndeki gecikirse arkası da bekler
	if not kuyruk.is_empty():
		cikis = maxi(cikis, int(kuyruk[-1][0]))
	kuyruk.append([cikis, p])


func _kur() -> void:
	var tel := str(args.get("telefon", "0")) == "1"
	voice.phone_line = tel
	if "test_giden" in voice:
		voice.test_giden = true
	voice.start()
	voice._out_player.volume_db = -80.0  # konuşanın hoparlörü kayda girmesin (yankı bastırması yine ölçer)
	dinleyen.phone_line = tel
	dinleyen.robot = str(args.get("robot", "0")) == "1"
	if "test_olay_ac" in dinleyen:
		dinleyen.test_olay_ac = true
	dinleyen.start()
	var a := str(args.get("a", "erkek"))
	if a != "":
		_wav(a + "_44k.wav", float(args.get("a_db", "0")), 0.3)
	var gdb := float(args.get("gurultu_db", "-99"))
	if gdb > -90.0:
		_wav("gurultu_44k.wav", gdb)
	var b := str(args.get("b", ""))
	if b != "":
		_b_hazirla(b, float(args.get("b_db", "0")))
		var ydb := float(args.get("yanki_db", "-99"))
		if ydb > -90.0:
			_wav(b + "_44k.wav", ydb, float(args.get("b_bas", "0.3")) + 0.25)  # hoparlörden mikrofona kaçan B
	for id in [1, 2]:
		if str(args.get("surum", "yeni")) == "eski":
			dinleyen.set_spatial(id, 1.0, -0.3 if id == 1 else 0.3, 0.0, tel)
			voice.set_spatial(id, 1.0, 0.0, 0.0, tel)
		else:
			dinleyen.set_spatial(id, 1.0, -0.3 if id == 1 else 0.3, 0.0, tel, 0.0)
			voice.set_spatial(id, 1.0, 0.0, 0.0, tel, 0.0)
	var ses := AudioServer.get_bus_index("Ses")
	kayit = AudioEffectRecord.new()
	AudioServer.add_bus_effect(ses, kayit)
	kayit.set_recording_active(true)
	t0 = Time.get_ticks_msec()
	b_bas = t0 + int(float(args.get("b_bas", "0.3")) * 1000.0)
	bitis = t0 + int(float(args.get("sure", "18")) * 1000.0)
	hazir = true


func _process(delta: float) -> bool:
	if not hazir:
		if voice._mic_player != null:
			_kur()
		return false
	if str(args.get("kare", "60")) == "yavas":
		OS.delay_msec(rng.randi_range(25, 45))
		if rng.randf() < 0.03:
			OS.delay_msec(120)
	var simdi := Time.get_ticks_msec()
	while b_i < b_paket.size() and simdi >= b_bas + b_i * 40:
		_ag(2, b_paket[b_i])
		var bp := PackedByteArray([2])
		bp.append_array(b_paket[b_i])
		voice.receive(bp)  # konuşan da B'yi duyar (yankı bastırması bunu bilir)
		b_i += 1
	var u0 := Time.get_ticks_usec()
	while not kuyruk.is_empty() and int(kuyruk[0][0]) <= simdi:
		dinleyen.receive(kuyruk.pop_front()[1])
	voice._process(delta)
	dinleyen._process(delta)
	islem_us += Time.get_ticks_usec() - u0
	islem_t += delta
	if simdi >= bitis:
		kayit.set_recording_active(false)
		var yol := ProjectSettings.globalize_path("res://" + str(args.get("cikti", "build/ses/s/x.wav")))
		DirAccess.make_dir_recursive_absolute(yol.get_base_dir())
		kayit.get_recording().save_to_wav(yol)
		var gk: PackedFloat32Array = voice.test_kayit if "test_kayit" in voice else PackedFloat32Array()
		var v := PackedByteArray()
		v.resize(gk.size() * 2)
		for k in gk.size():
			v.encode_s16(k * 2, int(clampf(gk[k], -1.0, 1.0) * 32767.0))
		var w := AudioStreamWAV.new()
		w.data = v
		w.mix_rate = int(voice.get_script().get_script_constant_map().get("RATE", 16000))
		w.format = AudioStreamWAV.FORMAT_16_BITS
		w.save_to_wav(yol.replace(".wav", "_giden.wav"))
		for o in (dinleyen.test_olaylar if "test_olaylar" in dinleyen else []):
			print("OLAY %.2f %s id=%d kuyruk=%d hoparlor=%d hedef=%d" % [(int(o[0]) - t0) / 1000.0, o[1], o[2], o[3], o[4], o[5]])
		print("SONUC yollanan=%d gelen=%d islem_ms_sn=%.1f" % [voice.sent_packets, voice.received_packets, islem_us / 1000.0 / maxf(islem_t, 0.001)])
		return true
	return false
