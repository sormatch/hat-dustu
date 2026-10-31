# Sesli konuşma zincirinin uçtan uca testi (telefonsuz): kaynak ses Mikrofon bus'ından girer, voice.gd kodlar,
# taklit ağdan (gecikme dalgalanması) geçer, voice.gd açıp çalar; "Ses" bus'ı WAV'a kaydedilir. Hoparlör kullanılmaz.
# Kullanım: Godot --headless --path . --script res://tools/ses_test.gd -- surum=yeni|eski kaynak=ton440|ton11k|konusma
#           ag=sabit|dalgali kare=60|yavas sure=8 yanki=0 kazanc=1 boguk=0 cikti=build/ses/x.wav
# Sonuçlar tools/ses_olc.mjs ile ölçülür.
extends SceneTree

var args := {}
var voice: Node
var kuyruk := []  # [çıkış zamanı ms, paket]
var kayit: AudioEffectRecord
var islem_us := 0
var islem_kare := 0
var islem_t := 0.0
var bitis_ms := 0
var rng := RandomNumberGenerator.new()
var hazir := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var p := String(a).split("=", true, 1)
		if p.size() == 2:
			args[p[0]] = p[1]
	rng.seed = 12345
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
	voice.packet_ready.connect(_paket)


# Düğümün _ready'si ilk karede çalışır: kurulum ondan sonra.
func _kur() -> void:
	voice._mic_player.stream = _kaynak(str(args.get("kaynak", "ton440")))
	voice.start()
	var yanki := float(args.get("yanki", "0"))
	var kaz := float(args.get("kazanc", "1"))
	var bog := float(args.get("boguk", "0"))
	if str(args.get("surum", "yeni")) == "eski":
		voice.set_spatial(1, kaz, 0.0, bog, false)
	else:
		voice.set_spatial(1, kaz, 0.0, bog, false, yanki)
	var ses := AudioServer.get_bus_index("Ses")
	kayit = AudioEffectRecord.new()
	AudioServer.add_bus_effect(ses, kayit)
	kayit.set_recording_active(true)
	bitis_ms = Time.get_ticks_msec() + int(float(args.get("sure", "8")) * 1000.0)
	hazir = true


func _kaynak(ad: String) -> AudioStream:
	if ad == "konusma":
		var en := ""
		var en_b := 0
		var d := DirAccess.open("res://assets/ses/gardiyan")
		for f in d.get_files():
			if f.ends_with(".ogg"):
				var boy := FileAccess.get_file_as_bytes("res://assets/ses/gardiyan/" + f).size()
				if boy > en_b:
					en_b = boy
					en = f
		var s: AudioStreamOggVorbis = load("res://assets/ses/gardiyan/" + en)
		s.loop = true
		return s
	var hz := 11000.0 if ad == "ton11k" else 440.0
	var oran := int(AudioServer.get_mix_rate())
	var n := oran * 2
	var v := PackedByteArray()
	v.resize(n * 2)
	# tam sayıda dönem: döngü noktasında kırılma olmasın
	var donem := roundf(hz * n / oran)
	for i in n:
		v.encode_s16(i * 2, int(sin(TAU * donem * i / n) * 0.12 * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = oran
	w.stereo = false
	w.data = v
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


func _paket(data: PackedByteArray) -> void:
	var gecik := 15.0
	if str(args.get("ag", "sabit")) == "dalgali":
		gecik = rng.randf_range(10.0, 170.0)
		if rng.randf() < 0.02:
			gecik += 300.0  # ara sıra TCP yeniden iletimi gibi
	var p := PackedByteArray([1])
	p.append_array(data)
	kuyruk.append([Time.get_ticks_msec() + int(gecik), p])


func _process(delta: float) -> bool:
	if not hazir:
		if voice._mic_player != null:
			_kur()
		return false
	if str(args.get("kare", "60")) == "yavas":
		# yavaş telefon: ~25 fps ve ara sıra uzun kare
		OS.delay_msec(rng.randi_range(25, 45))
		if rng.randf() < 0.03:
			OS.delay_msec(120)
	var simdi := Time.get_ticks_msec()
	# TCP sırayı korur: öndeki gecikince arkası da bekler
	while not kuyruk.is_empty() and int(kuyruk[0][0]) <= simdi:
		var a := Time.get_ticks_usec()
		voice.receive(kuyruk.pop_front()[1])
		islem_us += Time.get_ticks_usec() - a
	var t0 := Time.get_ticks_usec()
	voice._process(delta)
	islem_us += Time.get_ticks_usec() - t0
	islem_kare += 1
	islem_t += delta
	if simdi >= bitis_ms:
		kayit.set_recording_active(false)
		var r := kayit.get_recording()
		var yol := ProjectSettings.globalize_path("res://" + str(args.get("cikti", "build/ses/cikti.wav")))
		r.save_to_wav(yol)
		print("SONUC surum=%s kaynak=%s ag=%s kare=%s yollanan=%d gelen=%d islem_ms_sn=%.2f" % [args.get("surum", "yeni"), args.get("kaynak", "ton440"), args.get("ag", "sabit"), args.get("kare", "60"), voice.sent_packets, voice.received_packets, islem_us / 1000.0 / maxf(islem_t, 0.001)])
		return true
	return false
