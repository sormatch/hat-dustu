# Arama başı testi: telefon çalarken hoparlörden mikrofona kaçan yüksek ton (2,5 sn), ardından kısık konuşma.
# Bağlandıktan sonraki ilk saniyede giden ses ne kadar (kazanç, giden parça sayısı)? zil=1: yeni davranış (zil
# çalarken öğrenme durur, bağlanınca hat_acildi), zil=0: eski davranış.
# Kullanım: Godot --headless --path . --script res://tools/ses_zil_test.gd -- zil=1
extends SceneTree

var v: Node
var giden: Array = []


func _initialize() -> void:
	v = load("res://scripts/voice.gd").new()
	root.add_child(v)
	v.set_process(false)
	v.packet_ready.connect(func(d: PackedByteArray) -> void: giden.append(d))


func _parca(seviye: float, hz: float, t0: float) -> PackedFloat32Array:
	var c := PackedFloat32Array()
	c.resize(640)
	for i in 640:
		var t := t0 + float(i) / 16000.0
		c[i] = sin(TAU * hz * t) * seviye * sqrt(2.0)
	return c


func _rms_dec(d: PackedByteArray) -> float:
	var s := 0.0
	for b in d:
		var x: float = v._dec(b)
		s += x * x
	return sqrt(s / d.size())


func _process(_d: float) -> bool:
	var yeni := "zil=1" in OS.get_cmdline_user_args()
	var t := 0.0
	# 1) arama öncesi kısa konuşma: kazanç konuşmaya göre öğrenilir
	for i in 50:
		v._send_chunk(_parca(0.012 * (0.6 + 0.4 * sin(i * 0.7)), 220.0, t))
		t += 0.04
	if yeni:
		v.zil = true
	# 2) zil / çalma sesi 2,5 sn (mikrofona yüksek kaçar)
	for i in 62:
		v._send_chunk(_parca(0.25 if (i / 10) % 2 == 0 else 0.0, 425.0, t))
		t += 0.04
	if yeni:
		v.hat_acildi()
	giden.clear()
	# 3) bağlandı: kısık konuşma 2 sn
	var sonuc := []
	for i in 50:
		v._send_chunk(_parca(0.012 * (0.6 + 0.4 * sin(i * 0.7)), 220.0, t))
		t += 0.04
		if i == 24:
			var r := 0.0
			for d in giden:
				r += _rms_dec(d)
			sonuc.append([giden.size(), r / maxf(1, giden.size())])
			giden.clear()
	var r2 := 0.0
	for d in giden:
		r2 += _rms_dec(d)
	sonuc.append([giden.size(), r2 / maxf(1, giden.size())])
	print("SONUC %s ilk 1 sn: %d parça, ort. seviye %.4f | 2. sn: %d parça, ort. seviye %.4f (kazanç sonda %.2f)" % [
		"YENI" if yeni else "ESKI", sonuc[0][0], sonuc[0][1], sonuc[1][0], sonuc[1][1], v._kazanc])
	return true
