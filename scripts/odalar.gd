# ODALAR: oyuncuların kurduğu odalar.
#  - kur_penceresi(): ODA KUR penceresi (Arkadaşlarım / Herkes, 4-8 kişi, isteğe bağlı oda adı, botla doldur).
#    Lobide oda sahibi aynı pencereyi KAYDET ile açar (oda ayarını değiştirir).
#  - Ekran (bu betik bir CanvasLayer): "Herkes" odalarının listesi; arkadaşların odaları üstte, 5 sn'de bir yenilenir.
#    Sunucu: POST /odalar {ark: [arkadaşların oda kodları]} -> {o: [{k, a, h, n, x, m?, b?, f?}], toplam}
#    (server/src/odalar.js). Yalnız lobidekilere katılınır; maçtakiler gri, dolu odaya KATIL kapalı.
#  - lobi_bilgi(): bekleme salonundaki oda kartında oda adı + görünürlük + kişi sayısı şeridi.
# Test: menüde -- odalar=1 [odalar_demo=dolu|bos], -- oda_kur=1 [oda_kur_gor=herkes]; lobide -- oda_demo=herkes:6:1:Ad
extends CanvasLayer

signal closed
signal katil(code: String, liste: bool)  # menü odaya bağlanır (liste: ODALAR listesinden, değilse arkadaşın kodu)
signal kur_iste  # ODA KUR penceresi açılsın

const UI := preload("res://scripts/ui.gd")
const E := preload("res://scripts/ekran.gd")
const Dil := preload("res://scripts/dil.gd")

const KISI_MIN := 4
const KISI_MAX := 8
const AD_MAX := 22
const YENILE_SN := 5.0

var net: Node
var account: Node
var demo := ""  # test: "dolu" | "bos" (sunucuya sorulmaz)

var _kok: Control
var _liste: VBoxContainer
var _sayi: Label
var _kur_btn: Button
var _yenile_btn: Button
var _http: HTTPRequest
var _t := 0.0
var _istekte := false
var _son := ""  # son çizilen listenin özeti (aynıysa yeniden çizilmez, titremez)
var _ilk := true
var _katiliyor := ""  # bağlanılan oda kodu (bu sırada KATIL düğmeleri kapalı)


func _ready() -> void:
	layer = 16
	var s := E.screen("ODALAR", "kapi")
	_kok = s.kok
	add_child(_kok)
	(s.geri as Button).pressed.connect(_kapat)
	var sag: HBoxContainer = s.bar_sag
	_sayi = UI.title("", UI.FS_METIN, UI.METIN_SOLUK)
	_sayi.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sag.add_child(_sayi)
	_yenile_btn = UI.button("YENİLE", "ikincil", UI.BTN_H_KUCUK, UI.FS_METIN, "", 150)
	_yenile_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_yenile_btn.pressed.connect(func() -> void:
		_son = ""
		_yenile())
	sag.add_child(_yenile_btn)
	_kur_btn = UI.button("ODA KUR", "ana", UI.BTN_H_KUCUK, UI.FS_METIN + 2, "", 220)
	_kur_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_kur_btn.pressed.connect(func() -> void: kur_iste.emit())
	sag.add_child(_kur_btn)
	var govde: Control = s.govde
	var p := UI.panel(Vector2.ZERO, 22)
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.offset_left = 16
	p.offset_right = -16
	p.offset_bottom = -12
	govde.add_child(p)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.touch_scroll(sc)
	p.add_child(sc)
	_liste = VBoxContainer.new()
	_liste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_liste.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_liste.add_theme_constant_override("separation", UI.B_XS)
	sc.add_child(_liste)
	_http = HTTPRequest.new()
	_http.timeout = 8.0
	add_child(_http)
	if net:
		net.failed.connect(_katilamadi)
		net.welcomed.connect(_kapat)
	if account and account.has_signal("list_changed"):
		account.list_changed.connect(func() -> void: _t = YENILE_SN)  # arkadaşların odası değişti
	_doldur_bos(E.durum("kapi", "Odalar yükleniyor…", "", true))
	E.intro(_kok, govde)
	_yenile()


func _process(delta: float) -> void:
	_t += delta
	if _t >= YENILE_SN and not _istekte:
		_yenile()


func _kapat() -> void:
	if not is_instance_valid(_kok) or is_queued_for_deletion():
		return
	set_process(false)
	E.outro(_kok, func() -> void:
		closed.emit()
		queue_free())


# ---------------------------------------------------------------- liste
func _arkadas_odalari() -> Dictionary:
	# oda kodu -> [arkadaşın adı, maçta mı] (çevrimiçi ve bir odada olanlar)
	var out := {}
	if not account:
		return out
	for f in account.get("friends"):
		var oda := str(f.get("room", ""))
		if oda != "" and bool(f.get("online", false)) and not out.has(oda):
			var ad := str(f.get("name", ""))
			out[oda] = [ad if ad != "" else str(f.get("handle", "")), bool(f.get("oyun", false))]
	return out


func _yenile() -> void:
	_t = 0.0
	if demo != "":
		_ciz(_demo_liste())
		return
	if not net or _istekte:
		return
	_istekte = true
	var base := str(net.get("server_url")).replace("wss://", "https://").replace("ws://", "http://")
	var govde := JSON.stringify({"ark": _arkadas_odalari().keys()})
	var err := _http.request(base + "/odalar", ["Content-Type: application/json"], HTTPClient.METHOD_POST, govde)
	if err != OK:
		_istekte = false
		_baglanti_yok()
		return
	var res: Array = await _http.request_completed
	_istekte = false
	if not is_instance_valid(_liste):
		return
	var d = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8()) if int(res[0]) == HTTPRequest.RESULT_SUCCESS else null
	if typeof(d) != TYPE_DICTIONARY or not (d.get("o") is Array):
		if int(res[1]) == 429:
			return  # çok sık: bir sonraki yenilemede
		_baglanti_yok()
		return
	_ciz(d)


func _baglanti_yok() -> void:
	_son = ""
	_sayi.text = ""
	_kur_btn.visible = true
	_doldur_bos(E.durum("kapi", "Sunucuya ulaşılamadı", "İnternetini kontrol et.", false, "TEKRAR DENE", func() -> void: _yenile()))


func _doldur_bos(c: Control) -> void:
	for ch in _liste.get_children():
		_liste.remove_child(ch)
		ch.queue_free()
	_liste.add_child(c)


func _ciz(d: Dictionary) -> void:
	_son_veri = d
	var odalar: Array = d.get("o", [])
	var ark := _arkadas_odalari()
	# listede olmayan arkadaş odaları ("Arkadaşlarım" odası: arkadaşlar zaten görür) en üstte
	var kodlar := {}
	for r in odalar:
		kodlar[str(r.get("k", ""))] = true
	var ozel: Array = []
	for k in ark.keys():
		if not kodlar.has(k):
			ozel.append({"k": k, "ozel": true, "fa": ark[k][0], "m": 1 if ark[k][1] else 0})
	var hepsi: Array = ozel + odalar
	var ozet := JSON.stringify([hepsi, _katiliyor])
	if ozet == _son:
		return
	_son = ozet
	_sayi.text = tr("%d oda") % odalar.size() if not odalar.is_empty() else ""
	if hepsi.is_empty():
		# boş durum: tek büyük ODA KUR (üst çubuktaki gizlenir; ekranda tek ana düğme)
		_kur_btn.visible = false
		var v := E.durum("kapi", "Açık oda yok", "Kendi odanı kur.", false)
		var cc := CenterContainer.new()
		var b := UI.button("ODA KUR", "ana", UI.BTN_H_BUYUK, UI.FS_BUYUK, "arkadas", 380)
		b.pressed.connect(func() -> void: kur_iste.emit())
		cc.add_child(b)
		v.add_child(cc)
		_doldur_bos(v)
		return
	_kur_btn.visible = true
	for ch in _liste.get_children():
		_liste.remove_child(ch)
		ch.queue_free()
	for r in hepsi:
		var k := str(r.get("k", ""))
		var fa := ""
		if ark.has(k):
			fa = str(ark[k][0])
		_liste.add_child(_satir(r, fa))
	if _ilk:
		_ilk = false
		E.stagger(_liste, 0.03)
		for a in OS.get_cmdline_user_args():
			if a.begins_with("odalar_katil="):
				# test: listedeki bu odaya KATIL (dolu odada reddedilip bildirim çıkmalı)
				var hedef := a.substr(13)
				get_tree().create_timer(0.5).timeout.connect(func() -> void: katil.emit(hedef, true))


# Bir oda satırı: kurucu avatarı | oda adı + kurucu | kişi | durum | KATIL
func _satir(r: Dictionary, arkadas_adi: String) -> Control:
	var kod := str(r.get("k", ""))
	var ozel := bool(r.get("ozel", false))
	var macta := int(r.get("m", 0)) == 1
	var n := int(r.get("n", 0))
	var x := int(r.get("x", KISI_MAX))
	var dolu := not ozel and n >= x
	var kurucu := str(r.get("h", ""))
	var arkadas := arkadas_adi != "" or int(r.get("f", 0)) == 1  # sunucu da işaretler (f:1)
	var box := E.row_box(UI.AMBER if arkadas else Color(0, 0, 0, 0), Vector4(12, 8, 10, 8))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.B_S)
	box.add_child(h)
	var av_ad := arkadas_adi if ozel else kurucu
	var av := E.avatar(av_ad if av_ad != "" else "?", av_ad, 56)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(av)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_theme_constant_override("separation", 0)
	h.add_child(tv)
	var ust := HBoxContainer.new()
	ust.add_theme_constant_override("separation", UI.B_XS)
	tv.add_child(ust)
	var baslik := ""
	if ozel:
		baslik = tr("%s burada") % arkadas_adi
	else:
		baslik = str(r.get("a", ""))
		if baslik == "":
			baslik = varsayilan_ad(kurucu)
	var bl := UI.title(baslik, UI.FS_ORTA - 2, UI.METIN)
	bl.clip_text = true
	bl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bl.custom_minimum_size.x = 120
	ust.add_child(bl)
	if arkadas:
		var ap := E.pill("ARKADAŞIN", UI.AMBER, 14)
		ap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ust.add_child(ap)
	var alt := HBoxContainer.new()
	alt.add_theme_constant_override("separation", 6)
	tv.add_child(alt)
	if ozel:
		alt.add_child(UI.label("Arkadaşlarına özel oda", UI.FS_KUCUK, UI.METIN_SOLUK))
	else:
		var ti := UI.icon("tac", 20)
		ti.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		alt.add_child(ti)
		var kl := UI.label(kurucu, UI.FS_KUCUK, UI.METIN_SOLUK)
		kl.clip_text = true
		kl.custom_minimum_size.x = 60
		alt.add_child(kl)
		if int(r.get("b", 0)) == 1:
			var bi := UI.icon("bot", 22)
			bi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bi.modulate = Color(1, 1, 1, 0.75)
			alt.add_child(bi)
	# kişi sayısı
	if not ozel:
		var kh := HBoxContainer.new()
		kh.add_theme_constant_override("separation", 6)
		kh.custom_minimum_size.x = 96
		kh.alignment = BoxContainer.ALIGNMENT_END
		var ki := UI.icon("arkadas", 30)
		ki.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		kh.add_child(ki)
		var kl2 := UI.title("%d/%d" % [n, x], UI.FS_ORTA + 2, UI.KIRMIZI.lightened(0.3) if dolu else UI.METIN)
		kl2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		kh.add_child(kl2)
		kh.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(kh)
	# durum
	var dp := E.pill("MAÇTA" if macta else "LOBİDE", UI.KIRMIZI if macta else UI.YESIL, 15)
	dp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dp.custom_minimum_size.x = 118
	(dp.get_meta("label") as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.sigdir(dp.get_meta("label"), 98.0)
	h.add_child(dp)
	# KATIL (dolu ya da maçta: kapalı)
	var yazi := "KATIL"
	if dolu:
		yazi = "DOLU"
	if _katiliyor == kod:
		yazi = "…"
	var b := UI.button(yazi, "yesil" if not (dolu or macta) else "ikincil", UI.BTN_H_KUCUK, UI.FS_METIN + 2, "", 150)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.disabled = dolu or macta or _katiliyor != ""
	b.pressed.connect(func() -> void: katil.emit(kod, not ozel))
	h.add_child(b)
	if macta:
		box.modulate = Color(0.62, 0.62, 0.62, 0.9)
	return box


var _son_veri := {}


# Menü odaya bağlanmaya başladı (kurallar onaylandıktan sonra): KATIL düğmeleri kapanır, basılanda "…"
func baglaniyor(kod: String) -> void:
	_katiliyor = kod
	_son = ""
	_ciz_tekrar()


func _ciz_tekrar() -> void:
	# katılırken düğmeler kapansın (aynı veriyle yeniden çiz)
	_t = 0.0
	if not _son_veri.is_empty():
		_ciz(_son_veri)


# Katılma reddedildi (Oda dolu, maç başladı...): bildirim + liste yenilenir
func _katilamadi(m: String) -> void:
	if _katiliyor == "":
		return
	_katiliyor = ""
	UI.toast(m, null, 2.6, "hata")
	_son = ""
	_yenile()


func _demo_liste() -> Dictionary:
	if demo == "bos":
		return {"o": [], "toplam": 0}
	return {"o": [
		{"k": "K7QX", "a": "Gece Kulübü", "h": "Zeynep", "n": 3, "x": 6, "f": 1},
		{"k": "M2PA", "a": "", "h": "Kerem", "n": 5, "x": 8, "b": 1},
		{"k": "T9RB", "a": "Sadece eğlence", "h": "Deniz", "n": 2, "x": 4},
		{"k": "H4LL", "a": "Kara Tahta ustaları", "h": "Burak", "n": 6, "x": 6},
		{"k": "Z8YU", "a": "", "h": "Elif", "n": 7, "x": 8, "m": 1},
		{"k": "C3PO", "a": "Yeni başlayanlar", "h": "Mert", "n": 4, "x": 5, "m": 1},
	], "toplam": 6}


# ---------------------------------------------------------------- ortak yardımcılar

# Varsayılan oda adı: "Ali'nin odası" / "Mustafa'nın odası" (Türkçe ses uyumu) — İngilizcede "Ali's room"
static func varsayilan_ad(isim: String) -> String:
	var ad := isim.strip_edges()
	if ad == "":
		return Dil.t("Oda")
	if not Dil.tr_mi():
		return ad + "'s room"
	var kucuk := ad.replace("I", "ı").replace("İ", "i").to_lower()
	var unlu := ""
	for i in range(kucuk.length() - 1, -1, -1):
		var c := kucuk[i]
		if "aeıioöuü".contains(c):
			unlu = c
			break
	var son := kucuk[kucuk.length() - 1]
	var ek := "in"
	match unlu:
		"a", "ı":
			ek = "ın"
		"o", "u":
			ek = "un"
		"ö", "ü":
			ek = "ün"
	if "aeıioöuü".contains(son):
		ek = "n" + ek
	return ad + "'" + ek + " odası"


static func _secim_dugmesi(b: Button, secili: bool) -> void:
	UI.set_button_kind(b, "ana" if secili else "ikincil")


# ODA KUR penceresi. ayar: {gor, max, oda_ad, botla} (son kullanılan ya da odanın şimdiki ayarı).
# duzenle: lobide oda sahibi (düğme KAYDET). tamam.call(yeni_ayar) — oda_ad "" ise varsayılan ad.
# account verilirse ad küfür süzgecine önceden sorulur (sunucu yine süzer).
static func kur_penceresi(ayar: Dictionary, duzenle: bool, oyuncu: String, tamam: Callable, account: Node = null) -> Control:
	var m := UI.modal("ODA AYARI" if duzenle else "ODA KUR", 700)
	var sec := {"gor": "herkes" if str(ayar.get("gor", "")) == "herkes" else "arkadas", "max": clampi(int(ayar.get("max", KISI_MAX)), KISI_MIN, KISI_MAX), "botla": bool(ayar.get("botla", false))}
	# görünürlük: iki büyük seçenek
	var gh := HBoxContainer.new()
	gh.add_theme_constant_override("separation", UI.B_S)
	m.body.add_child(gh)
	var gw := (700.0 - UI.B_L * 2.0 - UI.B_S) / 2.0
	var b_ark := UI.button("ARKADAŞLARIM", "ikincil", UI.BTN_H, UI.FS_ORTA, "arkadas", gw)
	var b_her := UI.button("HERKES", "ikincil", UI.BTN_H, UI.FS_ORTA, "kapi", gw)
	gh.add_child(b_ark)
	gh.add_child(b_her)
	var ipucu := UI.label("", UI.FS_KUCUK + 1, UI.METIN_SOLUK, true)
	m.body.add_child(ipucu)
	var gor_ciz := func() -> void:
		_secim_dugmesi(b_ark, sec.gor == "arkadas")
		_secim_dugmesi(b_her, sec.gor == "herkes")
		ipucu.text = Dil.t("Herkes görür, katılır") if sec.gor == "herkes" else Dil.t("Sadece davet ve kodla")
	b_ark.pressed.connect(func() -> void:
		sec.gor = "arkadas"
		gor_ciz.call())
	b_her.pressed.connect(func() -> void:
		sec.gor = "herkes"
		gor_ciz.call())
	gor_ciz.call()
	# kişi sayısı: 4 5 6 7 8 (tek dokunuş)
	var kh := HBoxContainer.new()
	kh.add_theme_constant_override("separation", UI.B_S)
	m.body.add_child(kh)
	var kl := UI.title("KİŞİ", UI.FS_ORTA, UI.METIN)
	kl.custom_minimum_size.x = 170
	kl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.sigdir(kl, 170.0)
	kh.add_child(kl)
	var sayilar: Array = []
	for i in range(KISI_MIN, KISI_MAX + 1):
		var nb := UI.button(str(i), "ikincil", UI.BTN_H_KUCUK, UI.FS_BUYUK - 4, "", 84)
		var k := i
		nb.pressed.connect(func() -> void:
			sec.max = k
			for j in sayilar.size():
				_secim_dugmesi(sayilar[j], KISI_MIN + j == sec.max))
		sayilar.append(nb)
		kh.add_child(nb)
		_secim_dugmesi(nb, i == sec.max)
	# oda adı (isteğe bağlı)
	var ah := HBoxContainer.new()
	ah.add_theme_constant_override("separation", UI.B_S)
	m.body.add_child(ah)
	var al := UI.title("ODA ADI", UI.FS_ORTA, UI.METIN)
	al.custom_minimum_size.x = 170
	al.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.sigdir(al, 170.0)
	ah.add_child(al)
	var e := LineEdit.new()
	var vars := varsayilan_ad(oyuncu)
	e.placeholder_text = vars
	e.text = str(ayar.get("oda_ad", ayar.get("ad", "")))
	e.max_length = AD_MAX
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.custom_minimum_size = Vector2(0, UI.BTN_H_KUCUK)
	UI.style_edit(e, 24)
	ah.add_child(e)
	var red := UI.label("", UI.FS_METIN, UI.KIRMIZI.lightened(0.35), true)
	red.visible = false
	m.body.add_child(red)
	e.text_changed.connect(func(_t: String) -> void: red.visible = false)
	# botla doldur
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", UI.B_S)
	m.body.add_child(bh)
	var bi := UI.icon("bot", 44)
	bi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bh.add_child(bi)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", -2)
	bv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	bh.add_child(bv)
	bv.add_child(UI.title("BOTLA DOLDUR", UI.FS_ORTA, UI.METIN))
	bv.add_child(UI.label("Boş yerlere bot gelir", UI.FS_KUCUK, UI.METIN_SOLUK))
	var sw := E.switch(sec.botla, func(on: bool) -> void: sec.botla = on)
	bh.add_child(sw)
	# büyük ODA KUR / KAYDET
	var ok := UI.button("KAYDET" if duzenle else "ODA KUR", "yesil", UI.BTN_H_BUYUK - 8, UI.FS_BUYUK, "onay" if duzenle else "oyna")
	m.body.add_child(ok)
	var bitir := func() -> void:
		var ad := e.text.strip_edges()
		if ad == vars:
			ad = ""  # varsayılan ad: herkes kendi dilinde görsün
		var sonuc := {"gor": sec.gor, "max": sec.max, "oda_ad": ad, "botla": sec.botla}
		if ad == "" or account == null:
			m.close()
			tamam.call(sonuc)
			return
		ok.disabled = true
		account.ad_dene(ad, func(uygun: bool) -> void:
			if not is_instance_valid(m) or not is_instance_valid(ok):
				return
			ok.disabled = false
			if not uygun:
				red.text = Dil.t("Bu oda adı kullanılamaz.")
				red.visible = true
				UI.tik()
				var tw := m.box.create_tween()
				for kx in [10.0, -8.0, 5.0, 0.0]:
					tw.tween_property(m.box, "position:x", m.box.position.x + kx, 0.05)
				return
			m.close()
			tamam.call(sonuc))
	ok.pressed.connect(bitir)
	e.text_submitted.connect(func(_t: String) -> void: bitir.call())
	_klavye(m, e, ok)
	return m


# Telefonda klavye açılınca pencere yukarı kayar (oda adı ve düğme klavyenin üstünde kalır). Test: -- klavye=<px>
static func _klavye(m: Control, e: LineEdit, alt_dugme: Control) -> void:
	var test := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("klavye="):
			test = float(a.substr(7))
	var tree := Engine.get_main_loop() as SceneTree
	var kutu: Control = m.get("box")
	var kaydir := [0.0]
	var adim := func() -> void:
		if not is_instance_valid(m) or not is_instance_valid(kutu) or not m.is_inside_tree():
			return
		var vis := m.get_viewport().get_visible_rect().size
		var kh := test
		if kh <= 0.0 and DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
			kh = float(DisplayServer.virtual_keyboard_get_height()) * vis.y / maxf(1.0, float(DisplayServer.window_get_size().y))
		var hedef := 0.0
		if kh > 0.0 and e.has_focus():
			var ust: float = e.get_global_rect().position.y + kaydir[0]
			var alt: float = maxf(e.get_global_rect().end.y, alt_dugme.get_global_rect().end.y) + kaydir[0] + UI.B_S
			hedef = clampf(alt - (vis.y - kh), 0.0, maxf(0.0, ust - UI.B_S))
		var yeni := lerpf(kaydir[0], hedef, 0.25) if absf(kaydir[0] - hedef) > 0.5 else hedef
		if yeni == kaydir[0] and yeni == 0.0:
			return
		kaydir[0] = yeni
		var orta := ((kutu.get_parent() as Control).size.y - kutu.size.y) / 2.0
		kutu.position.y = orta - yeni
	tree.process_frame.connect(adim)
	m.tree_exiting.connect(func() -> void:
		if tree.process_frame.is_connected(adim):
			tree.process_frame.disconnect(adim))


# ---------------------------------------------------------------- lobideki oda bilgisi

# Oda kartında (hud.gd) ODA KODU'nun altında: görünürlük ikonu + oda adı + "HERKES · 3/6" (+ bot).
# Oda sahibi dokununca ODA AYARI penceresi açılır. hud: HUD düğümü (net'e ebeveyninden ulaşılır).
static func lobi_bilgi(hud: Node) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, UI.DOKUNMA)
	var st := UI.flat(Color(0, 0, 0, 0.32), Color(UI.CIZGI, 0.9), UI.R_ORTA)
	st.set_border_width_all(2)
	for k in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(k, st)
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10
	h.offset_right = -8
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var ic := UI.icon("kapi", 38)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", -3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var ad := UI.title("", UI.FS_METIN, UI.METIN)
	ad.clip_text = true
	ad.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ad.custom_minimum_size.x = 120
	v.add_child(ad)
	var alt := UI.title("", UI.FS_KUCUK, UI.AMBER)
	v.add_child(alt)
	var bot := UI.icon("bot", 30)
	bot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bot)
	var ay := UI.icon("ayarlar", 34)
	ay.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ay)
	b.set_meta("ikon_kok", h)
	b.set_meta("ad", ad)
	b.set_meta("alt", alt)
	b.set_meta("bot", bot)
	b.set_meta("ayar_ikon", ay)
	b.set_meta("hud", hud)
	b.set_meta("oyuncular", [])
	b.visible = false
	UI._basma_hissi(b, h)
	b.pressed.connect(func() -> void:
		var n := _net(hud)
		if n == null or not bool(n.get("is_host")) or (n.get("oda_ayar") as Dictionary).is_empty():
			return
		var a: Dictionary = n.get("oda_ayar")
		var kurucu := _kurucu_adi(b.get_meta("oyuncular"))
		var acc: Node = hud.get_parent().get("account") if hud.get_parent() else null
		var m := kur_penceresi(a, true, kurucu, func(y: Dictionary) -> void:
			n.send({"t": "oda_ayar", "gor": y.gor, "max": y.max, "ad": y.oda_ad, "botla": y.botla}), acc)
		var ust: Node = hud.get("_ust") if hud.get("_ust") is Node else hud
		ust.add_child(m))
	var n0 := _net(hud)
	if n0 and n0.has_signal("room_settings_changed"):
		n0.room_settings_changed.connect(func() -> void:
			if is_instance_valid(b):
				lobi_bilgi_guncelle(b, b.get_meta("oyuncular"), bool(n0.get("is_host"))))
	return b


static func _net(hud: Node) -> Node:
	var p := hud.get_parent() if hud else null
	var n = p.get("net") if p else null
	return n as Node if n is Node else null


static func _kurucu_adi(players: Array) -> String:
	for p in players:
		if bool(p.get("host", false)) and not bool(p.get("bot", false)):
			return str(p.get("name", ""))
	return ""


# Oda kişi sınırı (ayar yoksa 8): lobide "+ BOT" bunun üstüne çıkmaz
static func sinir(hud: Node) -> int:
	var n := _net(hud)
	if n == null:
		return KISI_MAX
	var a: Dictionary = n.get("oda_ayar")
	return int(a.get("max", KISI_MAX)) if not a.is_empty() else KISI_MAX


static func lobi_bilgi_guncelle(b: Button, players: Array, is_host: bool) -> void:
	if b == null:
		return
	b.set_meta("oyuncular", players)
	var n := _net(b.get_meta("hud"))
	var a: Dictionary = n.get("oda_ayar") if n else {}
	b.visible = not a.is_empty()
	if a.is_empty():
		return
	var herkes := str(a.get("gor", "")) == "herkes"
	var h: HBoxContainer = b.get_meta("ikon_kok")
	var eski: Control = h.get_child(0)
	var yeni := UI.icon("kapi" if herkes else "arkadas", 38)
	yeni.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.remove_child(eski)
	eski.queue_free()
	h.add_child(yeni)
	h.move_child(yeni, 0)
	var ad := str(a.get("ad", ""))
	(b.get_meta("ad") as Label).text = ad if ad != "" else varsayilan_ad(_kurucu_adi(players))
	(b.get_meta("alt") as Label).text = "%s · %d/%d" % [Dil.buyuk(Dil.t("Herkes") if herkes else Dil.t("Arkadaşlarım")), players.size(), int(a.get("max", KISI_MAX))]
	(b.get_meta("alt") as Label).add_theme_color_override("font_color", UI.AMBER if herkes else UI.METIN_SOLUK)
	(b.get_meta("bot") as Control).visible = bool(a.get("botla", false))
	(b.get_meta("ayar_ikon") as Control).visible = is_host
	b.mouse_filter = Control.MOUSE_FILTER_STOP if is_host else Control.MOUSE_FILTER_IGNORE
