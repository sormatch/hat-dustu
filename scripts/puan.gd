# Oyunu puanlama isteği: oyuncu oyunu gerçekten oynadıktan sonra (2 maç bitirdi ya da toplam 20 dk oynadı)
# en çok 3 kez, en az 7 gün arayla sorulur. Puan verdiyse bir daha sorulmaz.
#   iOS: Apple'ın kendi puan penceresi (StoreKit request_review; Apple yılda en çok 3 kez gösterir). Apple kuralı
#        (5.6.1): kendi yaptığımız "puan ver" penceresi kullanılamaz, bu yüzden doğrudan sistem penceresi açılır.
#   Android: kendi penceremiz: yıldızlar + PUAN VER (Play Store sayfası açılır) / SONRA.
#   Masaüstü: sorulmaz. Test: puan_test=1 (Android penceresi bilgisayarda açılır).
extends RefCounted

const UI := preload("res://scripts/ui.gd")
const MAC_ESIK := 2
const DK_ESIK := 20
const ARA_SN := 7 * 24 * 3600
const EN_COK := 3
const PLAY_URL := "market://details?id=com.sormatch.hatdustu"
const PLAY_WEB := "https://play.google.com/store/apps/details?id=com.sormatch.hatdustu"


static func mac_bitti(profile: Node) -> void:
	profile.settings["puan_mac"] = int(profile.settings.get("puan_mac", 0)) + 1
	profile.save()


static func dakika(profile: Node) -> void:
	profile.settings["puan_dk"] = int(profile.settings.get("puan_dk", 0)) + 1
	if int(profile.settings["puan_dk"]) % 5 == 0:
		profile.save()


# Koşullar tuttuysa sorar. ekran: Android penceresinin ekleneceği düğüm.
static func dene(profile: Node, ekran: Node) -> void:
	var test := OS.get_cmdline_user_args().has("puan_test=1")
	var s: Dictionary = profile.settings
	if not test:
		if bool(s.get("puan_verdi", false)) or int(s.get("puan_sor", 0)) >= EN_COK:
			return
		if Time.get_unix_time_from_system() - float(s.get("puan_son", 0)) < ARA_SN:
			return
		if int(s.get("puan_mac", 0)) < MAC_ESIK and int(s.get("puan_dk", 0)) < DK_ESIK:
			return
	var ios := OS.get_name() == "iOS"
	if not test and not ios and OS.get_name() != "Android":
		return
	s["puan_son"] = Time.get_unix_time_from_system()
	s["puan_sor"] = int(s.get("puan_sor", 0)) + 1
	profile.save()
	if ios:
		var sk = ekran.get_tree().root.get_node_or_null("Odeme")
		if sk and sk.has_method("puan_iste"):
			sk.puan_iste()
		return
	_pencere(profile, ekran)


static func _pencere(profile: Node, ekran: Node) -> void:
	var m := UI.modal("OYUNU BEĞENDİN Mİ?", 620.0)
	var yildiz := Label.new()
	yildiz.text = "★★★★★"
	yildiz.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	yildiz.add_theme_font_size_override("font_size", 64)
	yildiz.add_theme_color_override("font_color", UI.AMBER)
	m.body.add_child(yildiz)
	m.body.add_child(UI.label("Hat Düştü'ye puan verip kısa bir yorum yazarsan daha çok kişi bulur, odalar daha çabuk dolar. Yalnızca birkaç saniye sürer.", UI.FS_METIN, UI.METIN, true))
	var sat := HBoxContainer.new()
	sat.add_theme_constant_override("separation", UI.B_M)
	sat.alignment = BoxContainer.ALIGNMENT_CENTER
	m.body.add_child(sat)
	var sonra := UI.button("SONRA", "ikincil", UI.BTN_H_KUCUK, UI.FS_ORTA, "", 200)
	sonra.pressed.connect(m.close)
	sat.add_child(sonra)
	var ver := UI.button("PUAN VER", "ana", UI.BTN_H_KUCUK, UI.FS_ORTA, "", 260)
	ver.pressed.connect(func() -> void:
		profile.settings["puan_verdi"] = true
		profile.save()
		if OS.shell_open(PLAY_URL) != OK:
			OS.shell_open(PLAY_WEB)
		m.close())
	sat.add_child(ver)
	# en üst katman: maç sonu ekranının da üstünde
	var kat := CanvasLayer.new()
	kat.layer = 60
	ekran.get_tree().root.add_child(kat)
	kat.add_child(m)
	m.closed.connect(kat.queue_free)
