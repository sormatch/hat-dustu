# HatSes modülü denemesi: sınıflar yüklü mü, Opus 40 ms'lik konuşma parçasını sıkıştırıp açabiliyor mu, kayıp gizleme.
# Godot --headless --path . --script res://tools/opus_dene.gd
extends SceneTree


func _initialize() -> void:
	print("HatSes: ", ClassDB.class_exists("HatSes"), " Kodlayici: ", ClassDB.class_exists("HatOpusKodlayici"), " Cozucu: ", ClassDB.class_exists("HatOpusCozucu"))
	if not ClassDB.class_exists("HatOpusKodlayici"):
		quit(1)
		return
	var k: RefCounted = ClassDB.instantiate("HatOpusKodlayici")
	var c: RefCounted = ClassDB.instantiate("HatOpusCozucu")
	print("kur: ", k.call("kur", 24000, 32000), " ", c.call("kur", 24000))
	var toplam := 0
	var hata := 0.0
	var guc := 0.0
	var gecikme := 312  # Opus'un kendi gecikmesi (örnek), karşılaştırmada kaydırılır
	var giris := PackedFloat32Array()
	var cikis := PackedFloat32Array()
	for p in 50:
		var pcm := PackedFloat32Array()
		pcm.resize(960)
		for i in 960:
			var t := float(p * 960 + i) / 24000.0
			pcm[i] = 0.2 * sin(TAU * 220.0 * t) + 0.08 * sin(TAU * 1300.0 * t)
		giris.append_array(pcm)
		var paket: PackedByteArray = k.call("kodla", pcm)
		toplam += paket.size()
		var o: PackedFloat32Array = c.call("coz", paket)
		cikis.append_array(o)
	for i in range(4000, giris.size() - 1000):
		var e := cikis[i] - giris[i - gecikme] if i >= gecikme else 0.0
		hata += e * e
		guc += giris[i - gecikme] * giris[i - gecikme]
	var plc: PackedFloat32Array = c.call("kayip", 960)
	print("paket ortalama %d bayt (%.1f kbps), cozulen %d ornek, SNR %.1f dB, kayip gizleme %d ornek" % [toplam / 50, toplam * 8.0 / 2.0 / 1000.0, cikis.size(), 10.0 * log(guc / maxf(hata, 1e-12)) / log(10.0), plc.size()])
	var h: RefCounted = ClassDB.instantiate("HatSes")
	print("HatSes masaustu: baslat=", h.call("baslat", 24000), " durum=", h.call("durum"))
	quit()
