# Elmas mağazası: 6 elmas paketi (Türk lirası), satın alma onayı, başarıda elmaslar karttan sayaca uçar.
# Açmak: get_tree().current_scene.open_gem_store()  (main.gd; menüdeki ve mağazadaki "+" düğmeleri)
# Paketler sunucudan gelir (account.eco.paketler); bağlantı yoksa YEDEK_PAKETLER gösterilir.
# Satın alma tek yerden geçer: _buy_pack(pack). Gerçek ödeme (App Store / Google Play) oraya eklenecek.
extends CanvasLayer

signal closed

const UI := preload("res://scripts/ui.gd")
const E := preload("res://scripts/ekran.gd")
const SES := "res://assets/ses/"
const PAKET_GORSEL := "kit/elmas_paket_%d"  # assets/ui/kit/elmas_paket_1..6.png (tools/elmas_paket_uret.mjs)

# Sunucudaki PAKETLER ile aynı (server/src/ekonomi.js) — yalnızca bağlantı yokken vitrin boş kalmasın diye.
# elmas: hesaba geçen toplam (bonus dahil), bonus: bunun hediye kısmı, tek_sefer: hesap başına bir kez,
# hediye_kasa: pakete eklenen ücretsiz nadir kasa, alindi: tek seferlik paket bu hesapta alınmış mı
const YEDEK_PAKETLER := [
	{"kimlik": "baslangic", "elmas": 300, "bonus": 0, "fiyat_tl": 49.99, "etiket": "BAŞLANGIÇ PAKETİ", "tek_sefer": true, "hediye_kasa": 1},
	{"kimlik": "elmas_100", "elmas": 100, "bonus": 0, "fiyat_tl": 29.99, "etiket": ""},
	{"kimlik": "elmas_550", "elmas": 550, "bonus": 50, "fiyat_tl": 149.99, "etiket": ""},
	{"kimlik": "elmas_1200", "elmas": 1200, "bonus": 0, "fiyat_tl": 299.99, "etiket": "EN POPÜLER"},
	{"kimlik": "elmas_2500", "elmas": 2500, "bonus": 0, "fiyat_tl": 599.99, "etiket": ""},
	{"kimlik": "elmas_6500", "elmas": 6500, "bonus": 0, "fiyat_tl": 1499.99, "etiket": "EN İYİ DEĞER"},
]
# kademe (paketin elmas miktarına göre sırası, 0 = en küçük) -> kart çerçevesi (nadirlik), görsel büyüklüğü
const KADEME_CERCEVE := ["siradan", "siradan", "nadir", "nadir", "epik", "efsane"]
const KADEME_OLCEK := [0.74, 0.8, 0.88, 0.94, 1.0, 1.08]
const BEKLEME_SURESI := 12.0  # sunucu cevabı gelmezse satın alma bekleyişi biter

var account: Node
var profile: Node = null

var _kok: Control
var _ucus: Control  # uçan elmasların katmanı (en üstte, dokunmayı engellemez)
var _izgara: GridContainer
var _sayac: PanelContainer
var _sayac_ikon: Control
var _sayac_label: Label
var _test_label: Label
var _kartlar: Array = []  # [{pack, kart (Button), resim (Control), sira}]
var _paketler: Array = []
var _sunucu_paketi := false  # vitrin sunucunun listesiyle mi kuruldu
var _gosterilen := 0  # sayaçta görünen elmas
var _sayac_tw: Tween
var _kutlama := false
var _modal: Control = null
var _modal_btn: Button = null
var _bekleyen: Dictionary = {}  # sunucu cevabı beklenen paket
var _bekle_t := 0.0
var _sesler := {}
var _para_i := 0


func _ready() -> void:
	layer = 25
	for ad in ["para", "para2", "parilti", "odul", "hata"]:
		var p := AudioStreamPlayer.new()
		p.stream = load(SES + ad + ".ogg")
		p.max_polyphony = 6
		p.volume_db = -4.0
		add_child(p)
		_sesler[ad] = p

	var ekran: Dictionary = E.screen("ELMAS", "elmas", "bg_store", 0.74)
	_kok = ekran.kok
	add_child(_kok)
	(ekran.geri as Button).pressed.connect(_kapat)
	_sayac = _sayac_yap()
	(ekran.bar_sag as HBoxContainer).add_child(_sayac)
	var govde: Control = ekran.govde

	# arkadaki mavi ışık: vitrin elmas renginde parlasın
	var hale := E.glow(UI.ELMAS, 0.16)
	hale.set_anchors_preset(Control.PRESET_FULL_RECT)
	hale.offset_left = -200
	hale.offset_right = 200
	hale.offset_top = -60
	govde.add_child(hale)

	var marj := MarginContainer.new()
	marj.set_anchors_preset(Control.PRESET_FULL_RECT)
	marj.add_theme_constant_override("margin_left", UI.B_L)
	marj.add_theme_constant_override("margin_right", UI.B_L)
	marj.add_theme_constant_override("margin_top", UI.B_XS)
	marj.add_theme_constant_override("margin_bottom", UI.B_XS)
	marj.mouse_filter = Control.MOUSE_FILTER_IGNORE
	govde.add_child(marj)
	var kol := VBoxContainer.new()
	kol.add_theme_constant_override("separation", UI.B_XS)
	marj.add_child(kol)

	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.touch_scroll(sc)
	kol.add_child(sc)
	_izgara = GridContainer.new()
	_izgara.columns = 3
	_izgara.add_theme_constant_override("h_separation", UI.B_M)
	_izgara.add_theme_constant_override("v_separation", UI.B_M)
	_izgara.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_izgara.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.add_child(_izgara)

	# alt satır: güven notu (sağda) ve test modu ibaresi (solda, soluk)
	var alt := HBoxContainer.new()
	alt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kol.add_child(alt)
	_test_label = UI.label("TEST MODU · gerçek ödeme alınmaz", UI.FS_KUCUK, Color(UI.METIN_SOLUK, 0.55))
	_test_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alt.add_child(_test_label)
	var guven := UI.label("Satın aldığın elmaslar hesabına anında eklenir.", UI.FS_KUCUK, Color(UI.METIN_SOLUK, 0.8))
	alt.add_child(guven)

	_ucus = Control.new()
	_ucus.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ucus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kok.add_child(_ucus)

	if account:
		account.economy_changed.connect(_on_economy)
		account.gem_purchased.connect(_on_gem_purchased)
		account.message.connect(_on_message)
	_gosterilen = _elmas_simdi()
	_sayac_label.text = E.sayi(_gosterilen)
	_vitrin_kur()
	E.intro(_kok, govde)


func _process(delta: float) -> void:
	if _bekleyen.is_empty():
		return
	_bekle_t += delta
	if _bekle_t > BEKLEME_SURESI:
		_satin_alma_bitti(false, "Sunucu cevap vermedi. Elmasların düşmedi, tekrar dene.")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _modal and is_instance_valid(_modal):
			_modal.call("close")
		else:
			_kapat()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_inside_tree() and not (_modal and is_instance_valid(_modal)):
		_kapat()


func _kapat() -> void:
	if not _bekleyen.is_empty():
		return  # ödeme sürerken ekran kapanmasın
	E.outro(_kok, func() -> void:
		closed.emit()
		queue_free())


# ---------------------------------------------------------------------
# Veriler
# ---------------------------------------------------------------------

func _eco() -> Dictionary:
	if account and typeof(account.eco) == TYPE_DICTIONARY:
		return account.eco
	return {}


func _elmas_simdi() -> int:
	var eco := _eco()
	if eco.has("elmas"):
		return int(eco.elmas)
	return int(profile.gems) if profile else 0


func _test_modu() -> bool:
	var eco := _eco()
	return bool(eco.get("odeme_test", eco.get("test_odeme", false)))


static func kimlik(pack: Dictionary) -> String:
	return str(pack.get("kimlik", pack.get("id", "")))


static func fiyat(pack: Dictionary) -> float:
	return float(pack.get("fiyat_tl", pack.get("fiyat", 0.0)))


# Hesaba geçecek toplam elmas. Sunucunun biçimi (kimlik alanlı): elmas bonus dahil; eski biçim: elmas + bonus.
static func toplam(pack: Dictionary) -> int:
	if pack.has("kimlik"):
		return int(pack.get("elmas", 0))
	return int(pack.get("elmas", 0)) + int(pack.get("bonus", 0))


static func alindi(pack: Dictionary) -> bool:
	return bool(pack.get("alindi", false))


# Türk lirası: 199.99 -> "₺199,99", 1799.99 -> "₺1.799,99"
static func tl(fiyat: float) -> String:
	var kurus := int(roundf(fiyat * 100.0))
	return "₺%s,%02d" % [E.sayi(floori(kurus / 100.0)), kurus % 100]


func _on_economy() -> void:
	_test_label.visible = _test_modu()
	var liste: Variant = _eco().get("paketler", null)
	if _kutlama:
		return  # kutlama bitince yeniden çağrılır
	if liste is Array and not (liste as Array).is_empty() and (not _sunucu_paketi or _alindi_degisti(liste as Array)):
		_vitrin_kur()
	if not _kutlama:
		_sayac_yaz(_elmas_simdi(), 0.4)


# ---------------------------------------------------------------------
# Vitrin
# ---------------------------------------------------------------------

func _vitrin_kur() -> void:
	var liste: Variant = _eco().get("paketler", null)
	_sunucu_paketi = liste is Array and not (liste as Array).is_empty()
	_paketler = (liste as Array).duplicate() if _sunucu_paketi else YEDEK_PAKETLER.duplicate(true)
	_test_label.visible = _test_modu()
	for c in _izgara.get_children():
		_izgara.remove_child(c)
		c.queue_free()
	_kartlar.clear()
	# kademe: paketin elmas miktarına göre sırası (görsel ve çerçeve küçükten büyüğe), vitrin sırası sunucununki
	var miktarlar: Array = []
	for p in _paketler:
		miktarlar.append(toplam(p as Dictionary))
	miktarlar.sort()
	for i in _paketler.size():
		var pack: Dictionary = _paketler[i]
		var kad := mini(miktarlar.find(toplam(pack)), KADEME_CERCEVE.size() - 1)
		var k := _kart(pack, i, kad)
		_izgara.add_child(k)
	E.stagger(_izgara, 0.06)


# Tek seferlik bir paket bu arada alındı mı (kart "ALINDI" olsun)
func _alindi_degisti(liste: Array) -> bool:
	if liste.size() != _kartlar.size():
		return true
	for i in liste.size():
		if alindi(liste[i] as Dictionary) != alindi(_kartlar[i].pack as Dictionary):
			return true
	return false


func _kart(pack: Dictionary, sira: int, kad: int) -> Button:
	var nadir: String = KADEME_CERCEVE[kad]
	var renk: Color = UI.NADIRLIK.get(nadir, UI.ELMAS)
	var etiket := str(pack.get("etiket", ""))

	var kart := Button.new()
	kart.focus_mode = Control.FOCUS_NONE
	kart.custom_minimum_size = Vector2(360, 236)
	kart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bos := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		kart.add_theme_stylebox_override(s, bos)

	# çerçeve (nadirlik rengi pakete göre yükselir); üstte şerit için yer
	var cer := PanelContainer.new()
	cer.set_anchors_preset(Control.PRESET_FULL_RECT)
	cer.offset_top = 14
	cer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st: StyleBox = UI.kit_sbox("uretim/kart_" + nadir, 250, UI.KESIM.kart_nadirlik, Vector4(22, 18, 24, 20))
	if st == null:
		st = UI.flat(UI.YUZEY_2, renk, UI.R_ORTA, Color(renk, 0.3))
	cer.add_theme_stylebox_override("panel", st)
	kart.add_child(cer)

	var satir := HBoxContainer.new()
	satir.add_theme_constant_override("separation", UI.B_S)
	satir.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cer.add_child(satir)

	# sol: elmas yığını, arkasında hale (büyük paketlerde dönen ışınlar) ve parıltılar
	var sahne := Control.new()
	sahne.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sahne.size_flags_stretch_ratio = 1.05
	sahne.mouse_filter = Control.MOUSE_FILTER_IGNORE
	satir.add_child(sahne)
	var hale_renk := UI.ELMAS if kad < 5 else Color("#ffd36b")
	var hale := E.glow(hale_renk, 0.32 + 0.06 * kad)
	hale.set_anchors_preset(Control.PRESET_FULL_RECT)
	hale.offset_left = -18
	hale.offset_right = 18
	hale.offset_top = -10
	hale.offset_bottom = 10
	sahne.add_child(hale)
	if kad >= 3:
		var isin := Isinlar.new()
		isin.renk = Color(hale_renk, 0.1 + 0.03 * (kad - 3))
		isin.adet = 10 + 2 * (kad - 3)
		isin.set_anchors_preset(Control.PRESET_FULL_RECT)
		isin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sahne.add_child(isin)
	var resim := TextureRect.new()
	resim.texture = UI.texture(PAKET_GORSEL % (kad + 1), 420)
	if resim.texture == null:
		resim.texture = UI.icon_texture("elmas", 200)
	resim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	resim.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	resim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var olc: float = KADEME_OLCEK[kad]
	var pay := (1.0 - olc) * 0.5
	resim.anchor_left = pay
	resim.anchor_right = 1.0 - pay
	resim.anchor_top = pay + 0.02
	resim.anchor_bottom = 1.0 - pay + 0.02
	sahne.add_child(resim)
	_suzul(resim, sira)
	var par := Parilti.new()
	par.set_anchors_preset(Control.PRESET_FULL_RECT)
	par.mouse_filter = Control.MOUSE_FILTER_IGNORE
	par.siklik = 1.2 + 0.5 * kad
	sahne.add_child(par)

	# sağ: miktar, hediye rozeti, fiyat düğmesi
	var bilgi := VBoxContainer.new()
	bilgi.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bilgi.alignment = BoxContainer.ALIGNMENT_CENTER
	bilgi.add_theme_constant_override("separation", UI.B_XS)
	bilgi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	satir.add_child(bilgi)
	var ust_bos := Control.new()
	ust_bos.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ust_bos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bilgi.add_child(ust_bos)
	var miktar := HBoxContainer.new()
	miktar.alignment = BoxContainer.ALIGNMENT_CENTER
	miktar.add_theme_constant_override("separation", 6)
	miktar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mi := UI.icon("elmas", 38)
	mi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	miktar.add_child(mi)
	var ml := UI.title(E.sayi(toplam(pack)), 42, UI.ELMAS)
	ml.add_theme_color_override("font_outline_color", Color("#06222a"))
	ml.add_theme_constant_override("outline_size", 9)
	miktar.add_child(ml)
	bilgi.add_child(miktar)
	# rozetler: hediye elmas ve hediye kasa (yoksa hizayı bozmamak için görünmez yer tutucu)
	var bonus := int(pack.get("bonus", 0))
	var kasa := int(pack.get("hediye_kasa", 0))
	var rozetler := HBoxContainer.new()
	rozetler.alignment = BoxContainer.ALIGNMENT_CENTER
	rozetler.add_theme_constant_override("separation", 6)
	rozetler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bilgi.add_child(rozetler)
	if bonus > 0:
		rozetler.add_child(_rozet("+%s HEDİYE" % E.sayi(bonus), UI.YESIL))
	if kasa > 0:
		rozetler.add_child(_rozet("+%d NADİR KASA" % kasa, UI.NADIRLIK.get("nadir", UI.MAVI), "kasa"))
	if bonus <= 0 and kasa <= 0:
		var yer := _rozet("+0", UI.YESIL)
		yer.modulate.a = 0.0
		rozetler.add_child(yer)
	var alt_bos := Control.new()
	alt_bos.size_flags_vertical = Control.SIZE_EXPAND_FILL
	alt_bos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bilgi.add_child(alt_bos)
	var fiyat_btn := UI.button(tl(fiyat(pack)), "yesil", UI.BTN_H_KUCUK, 27)
	fiyat_btn.set_meta("sessiz", true)
	fiyat_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	fiyat_btn.pressed.connect(_kart_secildi.bind(sira))
	bilgi.add_child(fiyat_btn)
	if alindi(pack):
		# tek seferlik paket bu hesapta alınmış
		fiyat_btn.disabled = true
		UI.set_button_text(fiyat_btn, "ALINDI")
		sahne.modulate = Color(0.62, 0.62, 0.62, 0.85)

	# üst şerit (EN POPÜLER / EN İYİ DEĞER / MAHKUM KRALI)
	if etiket != "":
		var serit := _serit(etiket)
		kart.add_child(serit)

	kart.pressed.connect(_kart_secildi.bind(sira))
	kart.button_down.connect(func() -> void:
		UI.tik()
		kart.pivot_offset = kart.size / 2.0
		kart.create_tween().tween_property(kart, "scale", Vector2.ONE * 0.96, 0.06))
	kart.button_up.connect(func() -> void:
		kart.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(kart, "scale", Vector2.ONE, 0.18))
	_kartlar.append({"pack": pack, "kart": kart, "resim": resim, "sira": sira, "kad": kad})
	return kart


# Elmas yığını hafifçe süzülür (her kart farklı evrede)
func _suzul(c: Control, sira: int) -> void:
	var tw := c.create_tween().set_loops()
	tw.tween_interval(0.13 * sira)
	tw.tween_property(c, "position:y", -5.0, 1.4).as_relative().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(c, "position:y", 5.0, 1.4).as_relative().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# Küçük hap: "+50 HEDİYE", "+1 NADİR KASA" (isteğe bağlı ikonla)
func _rozet(text: String, renk: Color, ikon := "") -> PanelContainer:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(renk.darkened(0.6), 0.95)
	st.border_color = renk.lightened(0.15)
	st.set_border_width_all(2)
	st.set_corner_radius_all(40)
	st.content_margin_left = 6 if ikon != "" else 12
	st.content_margin_right = 14
	st.content_margin_top = 1
	st.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	if ikon != "":
		var ic := UI.icon(ikon, 26)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
	var l := UI.title(text, 18, renk.lightened(0.6))
	l.add_theme_color_override("font_outline_color", renk.darkened(0.75))
	l.add_theme_constant_override("outline_size", 4)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	return p


func _serit_renk(etiket: String) -> Color:
	match etiket:
		"EN POPÜLER":
			return UI.KIRMIZI
		"EN İYİ DEĞER":
			return UI.NADIRLIK.get("epik", UI.MAVI)
		"MAHKUM KRALI":
			return UI.NADIRLIK.get("efsane", UI.TEHLIKE_SARI)
	return UI.MAVI


func _serit(etiket: String) -> PanelContainer:
	var renk := _serit_renk(etiket)
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = renk.darkened(0.08)
	st.border_color = renk.lightened(0.45)
	st.set_border_width_all(2)
	st.border_width_bottom = 4
	st.border_color = renk.lightened(0.4)
	st.set_corner_radius_all(UI.R_KUCUK)
	st.shadow_color = Color(renk, 0.45)
	st.shadow_size = 10
	st.content_margin_left = UI.B_M
	st.content_margin_right = UI.B_M
	st.content_margin_top = 1
	st.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.set_anchors_preset(Control.PRESET_CENTER_TOP)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.offset_top = 0
	var koyu := renk.darkened(0.7)
	var l := UI.title(etiket, 18, Color.WHITE if etiket != "MAHKUM KRALI" else Color("#2a1600"), true)
	l.add_theme_color_override("font_outline_color", koyu if etiket != "MAHKUM KRALI" else Color("#fff1c0"))
	l.add_theme_constant_override("outline_size", 4 if etiket != "MAHKUM KRALI" else 2)
	if etiket == "MAHKUM KRALI":
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tac := UI.icon("tac", 22)
		tac.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(tac)
		h.add_child(l)
		p.add_child(h)
	else:
		p.add_child(l)
	if etiket == "EN POPÜLER":
		p.resized.connect(func() -> void: p.pivot_offset = p.size / 2.0)
		var tw := p.create_tween().set_loops()
		tw.tween_property(p, "scale", Vector2.ONE * 1.06, 0.6).set_trans(Tween.TRANS_SINE)
		tw.tween_property(p, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)
	return p


func _sayac_yap() -> PanelContainer:
	var hap := PanelContainer.new()
	var st := UI.flat(Color(0, 0, 0, 0.55), Color(UI.ELMAS, 0.35), UI.R_BUYUK)
	st.shadow_size = 0
	st.content_margin_left = 4
	st.content_margin_right = UI.B_L
	st.content_margin_top = 0
	st.content_margin_bottom = 0
	hap.add_theme_stylebox_override("panel", st)
	hap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hap.custom_minimum_size.y = 52
	hap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hap.add_child(row)
	_sayac_ikon = UI.icon("elmas", 46)
	_sayac_ikon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_sayac_ikon)
	_sayac_label = UI.title("0", UI.FS_ORTA + 4, UI.ELMAS)
	_sayac_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sayac_label.custom_minimum_size.x = 92
	row.add_child(_sayac_label)
	return hap


func _sayac_yaz(n: int, sure := 0.0) -> void:
	if _sayac_tw and _sayac_tw.is_valid():
		_sayac_tw.kill()
	if sure <= 0.0 or n == _gosterilen:
		_gosterilen = n
		_sayac_label.text = E.sayi(n)
		return
	_sayac_tw = create_tween()
	_sayac_tw.tween_method(func(v: float) -> void:
		_gosterilen = int(v)
		_sayac_label.text = E.sayi(_gosterilen), float(_gosterilen), float(n), sure).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------------
# Satın alma
# ---------------------------------------------------------------------

func _kart_secildi(sira: int) -> void:
	if not _bekleyen.is_empty() or _kutlama or (_modal and is_instance_valid(_modal)):
		return
	var k: Dictionary = _kartlar[sira]
	if alindi(k.pack as Dictionary):
		_hata("Bu paketi zaten aldın.")
		return
	var kart: Button = k.kart
	kart.pivot_offset = kart.size / 2.0
	var tw := kart.create_tween()
	tw.tween_property(kart, "scale", Vector2.ONE * 1.05, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(kart, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_onay_ac(sira)


# Onay penceresi: "1.400 elmas · ₺199,99" ve SATIN AL
func _onay_ac(sira: int) -> void:
	var pack: Dictionary = _kartlar[sira].pack
	var kad := int(_kartlar[sira].kad)
	var m := UI.modal("SATIN AL", 600)
	_modal = m
	m.closed.connect(func() -> void:
		_modal = null
		_modal_btn = null)

	var ust := HBoxContainer.new()
	ust.add_theme_constant_override("separation", UI.B_L)
	m.body.add_child(ust)
	var sahne := Control.new()
	sahne.custom_minimum_size = Vector2(190, 170)
	ust.add_child(sahne)
	var hale := E.glow(UI.ELMAS if kad < 5 else Color("#ffd36b"), 0.5)
	hale.set_anchors_preset(Control.PRESET_FULL_RECT)
	hale.offset_left = -30
	hale.offset_right = 30
	hale.offset_top = -24
	hale.offset_bottom = 24
	sahne.add_child(hale)
	var resim := TextureRect.new()
	resim.texture = UI.texture(PAKET_GORSEL % (kad + 1), 420)
	resim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	resim.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	resim.set_anchors_preset(Control.PRESET_FULL_RECT)
	resim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sahne.add_child(resim)
	var par := Parilti.new()
	par.set_anchors_preset(Control.PRESET_FULL_RECT)
	par.mouse_filter = Control.MOUSE_FILTER_IGNORE
	par.siklik = 3.0
	sahne.add_child(par)

	var sag := VBoxContainer.new()
	sag.alignment = BoxContainer.ALIGNMENT_CENTER
	sag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sag.add_theme_constant_override("separation", UI.B_XS)
	ust.add_child(sag)
	var miktar := HBoxContainer.new()
	miktar.add_theme_constant_override("separation", UI.B_XS)
	var mi := UI.icon("elmas", 50)
	mi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	miktar.add_child(mi)
	var ml := UI.title(E.sayi(toplam(pack)), 54, UI.ELMAS)
	ml.add_theme_color_override("font_outline_color", Color("#06222a"))
	ml.add_theme_constant_override("outline_size", 10)
	miktar.add_child(ml)
	var me := UI.title("elmas", UI.FS_ORTA, UI.METIN)
	me.size_flags_vertical = Control.SIZE_SHRINK_END
	miktar.add_child(me)
	sag.add_child(miktar)
	var bonus := int(pack.get("bonus", 0))
	if bonus > 0:
		var dok := UI.label("%s elmas  +  %s hediye" % [E.sayi(toplam(pack) - bonus), E.sayi(bonus)], UI.FS_METIN, UI.METIN_SOLUK)
		sag.add_child(dok)
	var kasa := int(pack.get("hediye_kasa", 0))
	if kasa > 0:
		var kr := _rozet("+%d NADİR KASA HEDİYE" % kasa, UI.NADIRLIK.get("nadir", UI.MAVI), "kasa")
		kr.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		sag.add_child(kr)
	if bool(pack.get("tek_sefer", false)):
		sag.add_child(UI.label("Hesap başına bir kez alınabilir.", UI.FS_KUCUK, UI.METIN_SOLUK))
	var fy := UI.title(tl(fiyat(pack)), UI.FS_BUYUK, UI.METIN)
	sag.add_child(fy)
	var not_yazi := "Test modu: gerçek ödeme alınmaz." if _test_modu() else "Ödeme %s ile alınır." % ("App Store" if OS.get_name() == "iOS" else "Google Play")
	sag.add_child(UI.label(not_yazi, UI.FS_KUCUK, Color(UI.METIN_SOLUK, 0.7)))

	var tus := HBoxContainer.new()
	tus.add_theme_constant_override("separation", UI.B_S)
	m.body.add_child(tus)
	var vaz := UI.button("VAZGEÇ", "ikincil", UI.BTN_H, UI.FS_ORTA, "", 170)
	vaz.pressed.connect(m.close)
	tus.add_child(vaz)
	var al := UI.button("SATIN AL  ·  %s" % tl(fiyat(pack)), "yesil", UI.BTN_H, UI.FS_ORTA + 2)
	al.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	al.pressed.connect(func() -> void: _buy_pack(pack, sira))
	tus.add_child(al)
	_modal_btn = al
	_kok.add_child(m)
	_ucus.move_to_front()


# Satın almanın tek giriş noktası.
# GERÇEK ÖDEME: burada önce mağaza eklentisi (iOS: StoreKit / Android: Google Play Billing) ödemeyi açacak,
# ödeme tamamlanınca makbuz {"t":"elmas_al","paket":id,"platform":..,"makbuz":..} ile sunucuya gidecek;
# sunucu makbuzu doğrulayıp elması ekler ve "elmas_alindi" yollar (account.gem_purchased).
# Şimdilik (sunucuda ODEME_TEST=1) doğrudan sunucuya gider.
func _buy_pack(pack: Dictionary, sira := -1) -> void:
	if not _bekleyen.is_empty():
		return
	if account == null:
		_hata("Sunucuya bağlanılamadı. İnternetini kontrol et.")
		return
	_bekleyen = pack.duplicate()
	_bekleyen["sira"] = sira
	_bekle_t = 0.0
	var btn := _modal_btn
	if btn and is_instance_valid(btn):
		btn.disabled = true
		UI.set_button_text(btn, "BAĞLANIYOR…" if not account.connected else "İŞLENİYOR…")
	# bağlantı yeni kuruluyorsa birkaç saniye bekle
	var t := 0.0
	while not account.connected and t < 6.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	if not account.connected:
		_bekleyen = {}
		if btn and is_instance_valid(btn):
			btn.disabled = false
			UI.set_button_text(btn, "TEKRAR DENE")
		_hata("Sunucuya bağlanılamadı. İnternetini kontrol et.")
		return
	_bekle_t = 0.0
	if btn and is_instance_valid(btn):
		UI.set_button_text(btn, "İŞLENİYOR…")
	account.send({"t": "elmas_al", "paket": kimlik(pack), "platform": OS.get_name()})


func _on_gem_purchased(d: Dictionary) -> void:
	var pack := _bekleyen
	var sira := int(pack.get("sira", -1))
	if pack.is_empty():
		# başka yerden gelen satın alma: paketi id'den bul
		for k in _kartlar:
			if kimlik(k.pack as Dictionary) == str(d.get("paket", "")):
				sira = int(k.sira)
	_satin_alma_bitti(true, "")
	_kutla(sira, int(d.get("elmas", 0)), int(d.get("toplam", _gosterilen + int(d.get("elmas", 0)))), int(d.get("hediye_kasa", 0)))


func _on_message(m: String) -> void:
	if not _bekleyen.is_empty():
		_satin_alma_bitti(false, m)


func _satin_alma_bitti(ok: bool, hata: String) -> void:
	_bekleyen = {}
	_bekle_t = 0.0
	if ok:
		if _modal and is_instance_valid(_modal):
			_modal.call("close")
		return
	if _modal_btn and is_instance_valid(_modal_btn):
		_modal_btn.disabled = false
		UI.set_button_text(_modal_btn, "TEKRAR DENE")
	_hata(hata)


func _hata(m: String) -> void:
	(_sesler.hata as AudioStreamPlayer).play()
	UI.toast(m, null, 2.6, "hata")


# ---------------------------------------------------------------------
# Kutlama: elmaslar karttan sayaca uçar, sayaç sayarak artar
# ---------------------------------------------------------------------

func _kutla(sira: int, eklenen: int, yeni: int, kasa := 0) -> void:
	_kutlama = true
	(_sesler.odul as AudioStreamPlayer).play()
	var hedef := _sayac_ikon.get_global_rect().get_center()
	var kaynak := get_viewport().get_visible_rect().size / 2.0
	var kart: Control = null
	if sira >= 0 and sira < _kartlar.size():
		var k: Dictionary = _kartlar[sira]
		kart = k.kart
		kaynak = (k.resim as Control).get_global_rect().get_center()
	# kartta parlama
	var flas := E.glow(Color("#bff8ff"), 0.95)
	flas.size = Vector2(320, 320)
	flas.position = kaynak - flas.size / 2.0
	flas.pivot_offset = flas.size / 2.0
	_ucus.add_child(flas)
	flas.scale = Vector2.ONE * 0.3
	var ft := flas.create_tween().set_parallel(true)
	ft.tween_property(flas, "scale", Vector2.ONE * 1.6, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	ft.tween_property(flas, "modulate:a", 0.0, 0.55).set_delay(0.1)
	ft.chain().tween_callback(flas.queue_free)
	_patlama(kaynak, UI.ELMAS, 1.4)
	if kart:
		kart.pivot_offset = kart.size / 2.0
		var kt := kart.create_tween()
		kt.tween_property(kart, "scale", Vector2.ONE * 1.08, 0.1)
		kt.tween_property(kart, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	# büyük "+1.400" yazısı
	var yazi := UI.title("+" + E.sayi(eklenen), 72, UI.ELMAS, true)
	yazi.add_theme_color_override("font_outline_color", Color("#06222a"))
	yazi.add_theme_constant_override("outline_size", 14)
	_ucus.add_child(yazi)
	yazi.size = yazi.get_combined_minimum_size()
	# ekranın ortasında belirir, sonra küçülerek sayaca uçar
	var ekran := get_viewport().get_visible_rect().size
	var orta := Vector2(ekran.x / 2.0, ekran.y * 0.44)
	yazi.position = orta - yazi.size / 2.0
	yazi.pivot_offset = yazi.size / 2.0
	yazi.scale = Vector2.ONE * 0.2
	yazi.z_index = 2
	# arkada: ekran hafifçe kararır, yazının arkasında mavi hale
	var perde := ColorRect.new()
	perde.color = Color(0, 0, 0, 0.42)
	perde.set_anchors_preset(Control.PRESET_FULL_RECT)
	perde.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ucus.add_child(perde)
	_ucus.move_child(perde, 0)
	var arka := E.glow(UI.ELMAS, 0.38)
	arka.size = Vector2(yazi.size.x + 320.0, yazi.size.y + 200.0)
	arka.position = orta - arka.size / 2.0
	arka.z_index = 1
	_ucus.add_child(arka)
	for c: CanvasItem in [perde, arka]:
		c.modulate.a = 0.0
		var at := c.create_tween()
		at.tween_property(c, "modulate:a", 1.0, 0.18)
		at.tween_interval(0.8)
		at.tween_property(c, "modulate:a", 0.0, 0.35)
		at.tween_callback(c.queue_free)
	var yt := yazi.create_tween()
	yt.tween_property(yazi, "scale", Vector2.ONE * 1.18, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	yt.tween_property(yazi, "scale", Vector2.ONE, 0.12)
	yt.tween_interval(0.6)
	yt.tween_property(yazi, "position", hedef - yazi.size / 2.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	yt.parallel().tween_property(yazi, "scale", Vector2.ONE * 0.3, 0.45).set_ease(Tween.EASE_IN)
	yt.parallel().tween_property(yazi, "modulate:a", 0.0, 0.45).set_ease(Tween.EASE_IN)
	yt.tween_callback(yazi.queue_free)

	# uçan elmaslar
	var kad := int(_kartlar[sira].kad) if sira >= 0 and sira < _kartlar.size() else 2
	var adet := 10 + kad * 3
	var tex := UI.icon_texture("elmas", 40)
	var ilk := 0.55  # ilk elmasın sayaca varışı
	var son := 0.0
	for i in adet:
		var g := TextureRect.new()
		g.texture = tex
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var boy := randf_range(34.0, 54.0)
		g.size = Vector2(boy, boy)
		g.pivot_offset = g.size / 2.0
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.position = kaynak - g.size / 2.0
		g.scale = Vector2.ZERO
		g.rotation = randf_range(-0.5, 0.5)
		_ucus.add_child(g)
		var dagil := kaynak + Vector2.from_angle(randf() * TAU) * randf_range(50.0, 140.0) + Vector2(0, -30)
		var bekle := 0.04 * i
		var ucus := randf_range(0.5, 0.7)
		var tepe := (dagil + hedef) / 2.0 + Vector2(randf_range(-160.0, 160.0), randf_range(-140.0, 40.0))
		var tw := g.create_tween()
		tw.tween_interval(bekle * 0.5)
		tw.tween_property(g, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(g, "position", dagil - g.size / 2.0, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.06 + bekle * 0.5)
		var p0 := dagil
		tw.tween_method(func(t: float) -> void:
			var a := p0.lerp(tepe, t)
			var b := tepe.lerp(hedef, t)
			g.position = a.lerp(b, t) - g.size / 2.0
			g.scale = Vector2.ONE * lerpf(1.0, 0.55, t)
			g.rotation += 0.12, 0.0, 1.0, ucus).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			g.queue_free()
			_elmas_vardi())
		var varis := bekle * 0.5 + 0.24 + 0.06 + bekle * 0.5 + ucus
		ilk = minf(ilk, varis)
		son = maxf(son, varis)

	# sayaç: ilk elmas varınca saymaya başlar, son elmasla biter
	var eski := _gosterilen
	var st := create_tween()
	st.tween_interval(ilk)
	st.tween_callback(func() -> void:
		_gosterilen = eski
		_sayac_yaz(yeni, maxf(0.4, son - ilk + 0.25)))
	st.tween_interval(son - ilk + 0.3)
	st.tween_callback(func() -> void:
		(_sesler.parilti as AudioStreamPlayer).play()
		_patlama(hedef, UI.ELMAS, 1.0)
		var tost := "%s elmas hesabına eklendi!" % E.sayi(eklenen)
		if kasa > 0:
			tost += "  +%d nadir kasa hediye!" % kasa
		UI.toast(tost, null, 2.6, "basari")
		_kutlama = false
		_sayac_yaz(maxi(yeni, _elmas_simdi()), 0.2)
		_on_economy())


# Bir elmas sayaca vardı: tık sesi + sayaç zıplar
func _elmas_vardi() -> void:
	_para_i += 1
	if _para_i % 2 == 0:
		var p: AudioStreamPlayer = _sesler.para if ((_para_i >> 1) & 1) == 0 else _sesler.para2
		p.pitch_scale = randf_range(0.95, 1.12)
		p.play()
	_sayac.pivot_offset = _sayac.size / 2.0
	var tw := _sayac.create_tween()
	tw.tween_property(_sayac, "scale", Vector2.ONE * 1.12, 0.05)
	tw.tween_property(_sayac, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_sayac_label.add_theme_color_override("font_color", Color.WHITE)
	var ct := _sayac_label.create_tween()
	ct.tween_interval(0.06)
	ct.tween_callback(func() -> void: _sayac_label.add_theme_color_override("font_color", UI.ELMAS))


func _patlama(nokta: Vector2, renk: Color, olcek := 1.0) -> void:
	var p := Patlama.new()
	p.renk = renk
	p.olcek = olcek
	p.position = nokta
	_ucus.add_child(p)


# ---------------------------------------------------------------------
# Test (main.gd pose=elmas): paket kartını seçer; onay=1 satın almayı da başlatır
# ---------------------------------------------------------------------

func test_sec(paket_id: String, satin_al: bool) -> void:
	for k in _kartlar:
		if kimlik(k.pack as Dictionary) == paket_id:
			_kart_secildi(int(k.sira))
			if satin_al:
				await get_tree().create_timer(0.5).timeout
				_buy_pack(k.pack, int(k.sira))
			return


# ---------------------------------------------------------------------
# Çizim parçaları
# ---------------------------------------------------------------------

# Dört köşeli parıltı yıldızı çizebilen taban
class Yildizli extends Control:
	func yildiz(p: Vector2, s: float, c: Color) -> void:
		if s < 1.0 or c.a <= 0.01:
			return
		var i := s * 0.2
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(i, -i), p + Vector2(s, 0), p + Vector2(i, i),
			p + Vector2(0, s), p + Vector2(-i, i), p + Vector2(-s, 0), p + Vector2(-i, -i)]), c)
		draw_circle(p, s * 0.22, Color(1, 1, 1, c.a))


# Görselin üstünde rastgele yanıp sönen parıltılar
class Parilti extends Yildizli:
	var siklik := 2.0  # saniyede ortalama yeni yıldız
	var renk := Color("#e8feff")
	var _y: Array = []  # [konum (0..1), yaş, ömür, boy]

	func _process(delta: float) -> void:
		if randf() < delta * siklik:
			_y.append([Vector2(randf_range(0.18, 0.82), randf_range(0.15, 0.75)), 0.0, randf_range(0.45, 0.85), randf_range(6.0, 13.0)])
		for y in _y:
			y[1] += delta
		_y = _y.filter(func(y: Array) -> bool: return y[1] < y[2])
		queue_redraw()

	func _draw() -> void:
		for y in _y:
			var k := sin(PI * float(y[1]) / float(y[2]))
			yildiz((y[0] as Vector2) * size, float(y[3]) * k, Color(renk, k))


# Arkada yavaşça dönen ışık huzmeleri (büyük paketler)
class Isinlar extends Control:
	var renk := Color(1, 1, 1, 0.12)
	var adet := 12
	var _a := 0.0

	func _process(delta: float) -> void:
		_a += delta * 0.25
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := maxf(size.x, size.y) * 0.62
		var bos := Color(renk, 0.0)
		for i in adet:
			var a0 := _a + TAU * i / adet
			var w := TAU / adet * 0.26
			draw_polygon(PackedVector2Array([c, c + Vector2.from_angle(a0 - w) * r, c + Vector2.from_angle(a0 + w) * r]),
				PackedColorArray([renk, bos, bos]))


# Halka + saçılan yıldızlar (elmas kartta patlar, sayaçta biter)
class Patlama extends Yildizli:
	var renk := Color("#5ff0ff")
	var olcek := 1.0
	var _t := 0.0
	var _sure := 0.75
	var _p: Array = []  # [yön, uzaklık, boy]

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		for i in 16:
			_p.append([Vector2.from_angle(randf() * TAU), randf_range(50.0, 140.0) * olcek, randf_range(6.0, 12.0) * olcek])

	func _process(delta: float) -> void:
		_t += delta
		if _t >= _sure:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := _t / _sure
		var e := 1.0 - pow(1.0 - k, 3.0)
		draw_arc(Vector2.ZERO, (16.0 + 80.0 * e) * olcek, 0.0, TAU, 48, Color(renk, (1.0 - k) * 0.85), 7.0 * (1.0 - k) + 1.0, true)
		for p in _p:
			yildiz((p[0] as Vector2) * float(p[1]) * e, float(p[2]) * (1.0 - k * 0.8), Color(Color.WHITE.lerp(renk, k), 1.0 - k))
