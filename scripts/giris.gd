# Hesap ekranı: "Mahkum Kayıt Formu". Misafir oyun yok: hesabı olmayan herkes açılışta buraya gelir (main.gd
# _hesap_kapisi, zorunlu = true: kapatılamaz, geri tuşu ve dışarı dokunma kapatmaz).
# Sekmeler: KAYIT OL (kullanıcı adı + e-posta + şifre) / GİRİŞ YAP (kullanıcı adı ya da e-posta + şifre).
# Diğer adımlar: şifremi unuttum (kod iste -> kod + yeni şifre), e-posta ekle (e-postasız eski hesap, zorunlu),
# e-posta doğrula (6 haneli kod; oynamayı engellemez, "ŞİMDİLİK GEÇ"), hesabım (girişliyken ayarlardan).
# Solda sicil fotoğrafı panosu: boy cetveli, kelepçe ve yazdıkça değişen sicil tabelası (oyundaki adın = kullanıcı adın).
# Kayıt / giriş onaylanınca kartın üstüne "KABUL EDİLDİ" damgası vurulur.
# Test: -- pose=giris ekran=kayit|giris|unuttum|sifirla|eposta|dogrula|hesap|kabul  doldur=1  hatali=1  klavye=<px> odak=<alan>
extends CanvasLayer

signal closed

const UI := preload("res://scripts/ui.gd")
const E := preload("res://scripts/ekran.gd")
const Account := preload("res://scripts/account.gd")
const Dil := preload("res://scripts/dil.gd")
const Sfx := preload("res://scripts/sfx.gd")

const KART_W := 600.0
const SOL_W := 420.0

var account: Node
var profile: Node
var zorunlu := false  # açılış kapısı: hesap (ve e-posta) olmadan kapanmaz
var ilk_ekran := ""  # açılırken gösterilecek adım (ör. ayarlardan "dogrula")

var _mod := "kayit"  # kayit | giris | unuttum | sifirla | eposta | dogrula | hesap
var _kim := ""  # şifre sıfırlamada yazılan kullanıcı adı / e-posta
var _kok: Control
var _sahne: Control  # klavye açılınca yukarı kayan kısım
var _kart: PanelContainer
var _form: VBoxContainer
var _plaka_ad: Label
var _pano: Control  # sicil panosu (baş harf rozeti burada yenilenir)
var _av: Control
var _av_ad := ""
var _msg: Label
var _don: Control
var _go: Button
var _alanlar := {}  # ad -> LineEdit
var _ipuclari := {}  # ad -> {kutu, ik, l, metin}
var _kaydir := 0.0
var _klavye_test := 0.0
var _bekliyor := 0  # cevap beklenen gönderimin sırası (zaman aşımı için)
var _bekleyen := ""  # cevabı beklenen işlem: kayit, giris, unuttum, sifirla, eposta, dogrula, tekrar
var _kapaniyor := false
var _sicil_no := 0
var _args := {}


func _ready() -> void:
	layer = 18
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			_args[kv[0]] = kv[1]
	_klavye_test = float(_args.get("klavye", "0"))
	if _args.has("demo"):
		# ekran görüntüsü: sunucusuz örnek hesap (ekran=eposta|dogrula|hesap için)
		var ek := str(_args.get("ekran", ""))
		if ek in ["eposta", "dogrula", "hesap"]:
			account.handle = "ali_34"
			account.has_account = true
			account.eposta_var = ek != "eposta"
			account.eposta_ok = false
			account.eposta = "al***@g***.com"
		_kim = "ali_34"
	_sicil_no = 10000 + absi(hash(str(account.token))) % 89999
	_kok = Control.new()
	_kok.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_kok)
	_kok.add_child(UI.background("bg_menu", 0.62))
	var bars := Parmaklik.new()
	bars.set_anchors_preset(Control.PRESET_FULL_RECT)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kok.add_child(bars)
	_kok.add_child(E.vignette(0.2, 0.92))
	_sahne = Control.new()
	_sahne.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sahne.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kok.add_child(_sahne)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.offset_top = 12
	cc.offset_bottom = -12
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sahne.add_child(cc)
	UI.guvenli(cc)  # çentikli telefonda form kenara girmesin
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	cc.add_child(cols)
	cols.add_child(_sol_pano())
	_kart = UI.panel(Vector2(KART_W, 0), 26)
	_kart.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cols.add_child(_kart)
	_form = VBoxContainer.new()
	_form.add_theme_constant_override("separation", 8)
	_kart.add_child(_form)
	UI.geri_tusu(_kok, _geri)  # Android geri tuşu / Esc: zorunluyken kapatmaz
	account.me_changed.connect(_on_me)
	account.message.connect(_on_message)
	account.hesap_olay.connect(_on_olay)
	if ilk_ekran != "":
		_mod = ilk_ekran
	elif account.has_account:
		_mod = "eposta" if not account.eposta_var else "hesap"
	if _args.has("ekran"):
		_mod = "kayit" if str(_args.ekran) == "kabul" else str(_args.ekran)
	_build()
	E.intro(_kok, null)
	if _args.get("ekran", "") == "kabul":
		get_tree().create_timer(0.8).timeout.connect(func() -> void: _damga("KABUL EDİLDİ", UI.YESIL))
	if _klavye_test > 0.0:
		# test: ekranın altında klavyenin kaplayacağı alan (ekran görüntüsünde görünsün)
		var kl := ColorRect.new()
		kl.color = Color(0.22, 0.24, 0.26, 0.96)
		kl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		kl.offset_top = -_klavye_test
		kl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_kok.add_child(kl)
		var kt := UI.title("KLAVYE (TEST)", 22, Color(1, 1, 1, 0.35), true)
		kt.set_anchors_preset(Control.PRESET_FULL_RECT)
		kt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		kl.add_child(kt)
		(func() -> void:
			var son: LineEdit = null
			for k in _alanlar:
				son = _alanlar[k]
			if _args.has("odak") and _alanlar.has(_args.odak):
				son = _alanlar[_args.odak]
			if son:
				son.grab_focus()).call_deferred()


# ---------------------------------------------------------------------
# Sol: sicil fotoğrafı panosu
# ---------------------------------------------------------------------
func _sol_pano() -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size.x = SOL_W
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", UI.B_S)
	var logo := TextureRect.new()
	logo.texture = UI.texture("logo", 300)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(SOL_W, 118)
	v.add_child(logo)
	var pano := Control.new()
	pano.custom_minimum_size = Vector2(SOL_W, 400)
	v.add_child(pano)
	var boy := Boy.new()
	boy.set_anchors_preset(Control.PRESET_FULL_RECT)
	pano.add_child(boy)
	# kelepçe: panonun sağ üstünde, hafif eğik asılı
	var kel := Kelepce.new()
	kel.position = Vector2(SOL_W - 156, 16)
	kel.size = Vector2(132, 74)
	kel.rotation = deg_to_rad(-8)
	pano.add_child(kel)
	# oyuncunun baş harfi (sicil fotoğrafı yerine): yazdıkça değişir
	_pano = pano
	_avatar(account.handle)
	# sicil tabelası: yazdıkça kullanıcı adı burada görünür
	var tabela := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#0c0d0d")
	st.border_color = Color(UI.METIN, 0.85)
	st.set_border_width_all(3)
	st.set_corner_radius_all(6)
	st.content_margin_left = 18
	st.content_margin_right = 18
	st.content_margin_top = 8
	st.content_margin_bottom = 10
	st.shadow_color = Color(0, 0, 0, 0.6)
	st.shadow_size = 10
	tabela.add_theme_stylebox_override("panel", st)
	tabela.position = Vector2(30, 232)
	tabela.custom_minimum_size = Vector2(SOL_W - 60, 0)
	tabela.size = Vector2(SOL_W - 60, 0)
	tabela.pivot_offset = Vector2((SOL_W - 60) / 2.0, 50)
	tabela.rotation = deg_to_rad(-1.5)
	pano.add_child(tabela)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tabela.add_child(tv)
	tv.add_child(UI.title("HAT DÜŞTÜ CEZAEVİ", 15, Color(UI.METIN, 0.7), true))
	_plaka_ad = UI.title(_plaka_metni(), 34, Color.WHITE, true)
	_plaka_ad.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_plaka_ad.clip_text = true
	_plaka_ad.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(_plaka_ad)
	var gun := Time.get_date_dict_from_system()
	var alt := UI.label(tr("SİCİL NO %05d  ·  %s") % [_sicil_no, "%02d.%02d.%d" % [gun.day, gun.month, gun.year]], 15, Color(UI.AMBER, 0.95), true)
	alt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	tv.add_child(alt)
	var ipucu := UI.label("Oyundaki adın kullanıcı adındır.", UI.FS_KUCUK, UI.METIN_SOLUK, true)
	ipucu.position = Vector2(0, 368)
	ipucu.size = Vector2(SOL_W, 24)
	pano.add_child(ipucu)
	return v


func _plaka_metni() -> String:
	if account.has_account and account.handle != "":
		return "@" + account.handle
	return "@_ _ _ _ _"


func _plaka(h: String) -> void:
	if is_instance_valid(_plaka_ad):
		_plaka_ad.text = ("@" + h) if h != "" else _plaka_metni()
	_avatar(h)


func _avatar(h: String) -> void:
	var ad := h if h != "" else "?"
	if not is_instance_valid(_pano) or (ad == _av_ad and is_instance_valid(_av)):
		return
	_av_ad = ad
	if is_instance_valid(_av):
		_av.queue_free()
	_av = E.avatar(ad, ad if h != "" else str(account.token), 132)
	_av.position = Vector2((SOL_W - 132) / 2.0, 74)
	_pano.add_child(_av)
	_pano.move_child(_av, 2)  # tabelanın arkasında kalsın


# ---------------------------------------------------------------------
# Kart (form)
# ---------------------------------------------------------------------
func _build() -> void:
	for c in _form.get_children():
		_form.remove_child(c)
		c.queue_free()
	_alanlar.clear()
	_ipuclari.clear()
	_go = null
	_msg = null
	_don = null
	if _mod in ["kayit", "giris"]:
		_sekmeler()
	match _mod:
		"kayit":
			_baslik("MAHKUM KAYIT FORMU", "FORM 27-B")
			var u := _alan("kullanici", "KULLANICI ADI", "3-16 karakter: a-z, 0-9, _ ve . (Türkçe harf, boşluk yok)", "ad")
			var e := _alan("eposta", "E-POSTA", "Şifreni unutursan hesabını bununla kurtarırsın.", "eposta")
			var s := _alan("sifre", "ŞİFRE", "En az 6 karakter.", "sifre")
			u.text_changed.connect(_kullanici_degisti)
			e.text_changed.connect(_eposta_degisti)
			e.focus_exited.connect(func() -> void: _eposta_kontrol(true))
			s.text_changed.connect(_sifre_degisti)
			_zincir([u, e, s])
			if account.handle != "":
				u.text = account.handle
				_kullanici_degisti(u.text)
			_durum_satiri()
			_ana_dugme("KAYDI TAMAMLA", "onay")
			var not_l := UI.label("Bu telefondaki eşyaların hesabına geçer.", UI.FS_KUCUK, UI.METIN_SOLUK, true)
			not_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_form.add_child(not_l)
		"giris":
			_baslik("SİCİL SORGULAMA", "GİRİŞ")
			var k := _alan("kim", "KULLANICI ADI YA DA E-POSTA", "", "kim")
			var s := _alan("sifre", "ŞİFRE", "", "sifre")
			k.text_changed.connect(func(t: String) -> void:
				var tt := t.strip_edges()
				_plaka(Account.clean_handle(tt) if not tt.contains("@") or tt.begins_with("@") else ""))
			_zincir([k, s])
			if account.handle != "":
				k.text = account.handle
			_durum_satiri()
			_ana_dugme("GİRİŞ YAP", "oyna")
			var alt := _baglanti_satiri()
			_baglanti(alt, "Şifremi unuttum", func() -> void:
				_kim = _metin("kim").strip_edges()
				_git("unuttum"))
			var uy := UI.label("Hesapsız kazandıkların taşınmaz.", UI.FS_KUCUK, UI.METIN_SOLUK, true)
			uy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_form.add_child(uy)
		"unuttum":
			_baslik("KAYIP ANAHTAR BAŞVURUSU", "ŞİFRE")
			_aciklama(tr("Kullanıcı adı ya da e-posta yaz. Kod göndereceğiz."))
			var k := _alan("kim", "KULLANICI ADI YA DA E-POSTA", "", "kim")
			k.text = _kim
			_zincir([k])
			_durum_satiri()
			_ana_dugme("KOD GÖNDER", "telefon")
			var alt := _baglanti_satiri()
			_baglanti(alt, "Geri dön", func() -> void: _git("giris"))
			_baglanti(alt, "Kodum var", func() -> void:
				_kim = _metin("kim").strip_edges()
				if _kim == "":
					_alan_hata("kim", "Kullanıcı adını ya da e-postanı yaz.")
					return
				_git("sifirla"))
		"sifirla":
			_baslik("YENİ ANAHTAR", "ŞİFRE")
			if _kim.contains("@") and not _kim.begins_with("@"):
				_aciklama(tr("%s adresine gelen kodu ve yeni şifreni yaz. Kod 15 dakika geçerli.") % _kim)
			else:
				_aciklama(tr("@%s için e-postana gelen kodu ve yeni şifreni yaz. Kod 15 dakika geçerli.") % Account.clean_handle(_kim))
			var kd := _alan("kod", "6 HANELİ KOD", "", "kod")
			var s := _alan("sifre", "YENİ ŞİFRE", "En az 6 karakter.", "sifre")
			s.text_changed.connect(_sifre_degisti)
			_zincir([kd, s])
			_durum_satiri()
			_ana_dugme("ŞİFREYİ DEĞİŞTİR", "kilit")
			var alt := _baglanti_satiri()
			_baglanti(alt, "Geri dön", func() -> void: _git("unuttum"))
			_baglanti(alt, "Kodu tekrar gönder", func() -> void:
				if _kim != "":
					_gonder("unuttum", func() -> void: account.sifre_unuttum(_kim)))
		"eposta":
			_baslik("SİCİL GÜNCELLEME", "E-POSTA")
			_aciklama(tr("@%s, hesabını korumak için e-posta adresini ekle. Şifreni unutursan hesabını bununla kurtarırsın.") % account.handle)
			var e := _alan("eposta", "E-POSTA", "Kimse adresini görmez.", "eposta")
			e.text_changed.connect(_eposta_degisti)
			_zincir([e])
			_durum_satiri()
			_ana_dugme("E-POSTAYI KAYDET", "onay")
			var alt := _baglanti_satiri()
			if account.eposta_var:
				_baglanti(alt, "Vazgeç", func() -> void: _git("dogrula" if not account.eposta_ok else "hesap"))
			_baglanti(alt, "Çıkış yap", _cikis)
		"dogrula":
			_baslik("E-POSTA DOĞRULAMA", "KOD")
			var adres: String = account.eposta if account.eposta != "" else "—"
			_aciklama(tr("%s adresine 6 haneli bir kod gönderdik. Kodu yaz, hesabın güvende olsun. Doğrulamadan da oynayabilirsin.") % adres)
			var kd := _alan("kod", "6 HANELİ KOD", "", "kod")
			_zincir([kd])
			_durum_satiri()
			_ana_dugme("DOĞRULA", "onay")
			var alt := _baglanti_satiri()
			_baglanti(alt, "Kodu tekrar gönder", func() -> void: _gonder("tekrar", func() -> void: account.dogrulama_tekrar()))
			_baglanti(alt, "Adresi düzelt", func() -> void: _git("eposta"))
			var gec := UI.button("ŞİMDİLİK GEÇ", "ikincil", UI.DOKUNMA, 20, "")
			gec.pressed.connect(_kapat_izinliyse)
			_form.add_child(gec)
		"hesap":
			_hesap_karti()
	if _args.has("doldur"):
		_test_doldur()
	if _mod in ["unuttum", "sifirla"] and _kim != "" and not (_kim.contains("@") and not _kim.begins_with("@")):
		_plaka(Account.clean_handle(_kim))
	E.stagger(_form, 0.03)


func _sekmeler() -> void:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", UI.B_S)
	for i in 2:
		var kayit := i == 0
		var on := (_mod == "kayit") == kayit
		var t := UI.tab("KAYIT OL" if kayit else "GİRİŞ YAP", on, "arkadas" if kayit else "oyna")
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.pressed.connect(func() -> void:
			var hedef := "kayit" if kayit else "giris"
			if _mod != hedef:
				_git(hedef))
		tabs.add_child(t)
	_form.add_child(tabs)


func _baslik(metin: String, etiket: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.B_S)
	var t := UI.title(metin, UI.FS_ORTA + 2, UI.AMBER)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(t)
	# köşede soluk form etiketi (kağıt formlardaki gibi)
	var et := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0)
	st.border_color = Color(UI.METIN_SOLUK, 0.6)
	st.set_border_width_all(2)
	st.set_corner_radius_all(4)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 1
	st.content_margin_bottom = 1
	et.add_theme_stylebox_override("panel", st)
	et.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	et.add_child(UI.title(etiket, 13, UI.METIN_SOLUK))
	h.add_child(et)
	_form.add_child(h)
	var cizgi := ColorRect.new()
	cizgi.color = Color(UI.AMBER, 0.35)
	cizgi.custom_minimum_size.y = 2
	_form.add_child(cizgi)


func _aciklama(metin: String) -> void:
	var l := UI.label(metin, UI.FS_METIN - 2, UI.METIN)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # çağıran tr() ile çevirdi
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = KART_W - 60
	_form.add_child(l)


# Etiketli yazı alanı + altında ipucu satırı. tur: ad | eposta | sifre | kim | kod
func _alan(ad: String, baslik: String, ipucu: String, tur: String) -> LineEdit:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.add_child(UI.title(baslik, 14, Color(UI.AMBER, 0.9)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UI.B_XS)
	var e := LineEdit.new()
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.style_edit(e, 24)
	e.custom_minimum_size.y = 60
	match tur:
		"ad":
			e.max_length = 17
			e.placeholder_text = "ör. ali_34"
		"eposta":
			e.max_length = 120
			e.placeholder_text = "ör. ali@gmail.com"
			e.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
		"kim":
			e.max_length = 120
			e.placeholder_text = "ör. ali_34"
			e.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
		"kod":
			e.max_length = 6
			e.placeholder_text = "000000"
			e.alignment = HORIZONTAL_ALIGNMENT_CENTER
			e.add_theme_font_override("font", UI.TITLE_FONT)
			e.add_theme_font_size_override("font_size", 30)
			e.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
			e.text_changed.connect(func(t: String) -> void:
				var sade := ""
				for ch in t:
					if ch >= "0" and ch <= "9":
						sade += ch
				if sade != t:
					e.text = sade
					e.caret_column = sade.length()
				if sade.length() == 6 and e.has_focus():
					_submit.call_deferred())
		"sifre":
			e.max_length = 64
			e.secret = true
			e.placeholder_text = "••••••"
			e.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
	row.add_child(e)
	if tur == "sifre":
		var goz := UI.button("GÖSTER", "ikincil", 60, 17, "", 128)
		goz.pressed.connect(func() -> void:
			e.secret = not e.secret
			UI.set_button_text(goz, "GÖSTER" if e.secret else "GİZLE"))
		row.add_child(goz)
	v.add_child(row)
	var ih := HBoxContainer.new()
	ih.add_theme_constant_override("separation", 6)
	var ik := UI.icon("onay", 18)
	ik.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ik.visible = false
	ih.add_child(ik)
	var il := UI.label(ipucu, 15, UI.METIN_SOLUK)
	il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	il.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ih.add_child(il)
	ih.visible = ipucu != ""
	v.add_child(ih)
	_form.add_child(v)
	_alanlar[ad] = e
	_ipuclari[ad] = {"kutu": ih, "ik": ik, "l": il, "metin": ipucu}
	e.text_changed.connect(func(_t: String) -> void:
		if is_instance_valid(_msg) and bool(_msg.get_meta("kirmizi", false)):
			_msg.text = "")
	return e


# Enter / İleri: sıradaki alana geç, sonuncusunda gönder
func _zincir(l: Array) -> void:
	for i in l.size():
		var e: LineEdit = l[i]
		if i < l.size() - 1:
			var sonraki: LineEdit = l[i + 1]
			e.text_submitted.connect(func(_t: String) -> void: sonraki.grab_focus())
		else:
			e.text_submitted.connect(func(_t: String) -> void: _submit())


# İpucu satırı: durum "" (soluk, varsayılan metin), "iyi" (yeşil + onay), "kotu" (kırmızı)
func _ipucu(ad: String, durum: String, metin := "") -> void:
	if not _ipuclari.has(ad):
		return
	var d: Dictionary = _ipuclari[ad]
	var l: Label = d.l
	var m := metin if metin != "" else str(d.metin)
	l.text = m
	l.add_theme_color_override("font_color", UI.YESIL.lightened(0.25) if durum == "iyi" else (UI.KIRMIZI.lightened(0.35) if durum == "kotu" else UI.METIN_SOLUK))
	(d.ik as Control).visible = durum == "iyi"
	(d.kutu as Control).visible = m != ""


func _alan_hata(ad: String, metin: String) -> void:
	_ipucu(ad, "kotu", metin)
	if _alanlar.has(ad):
		(_alanlar[ad] as LineEdit).grab_focus()
	_salla()


func _kullanici_degisti(t: String) -> void:
	var h := Account.clean_handle(t)
	_plaka(h)
	if h == "":
		_ipucu("kullanici", "")
		return
	var he := Account.handle_error(h)
	if he == "":
		_ipucu("kullanici", "iyi", tr("Oyundaki adın: @%s") % h)
	elif he.contains("en az"):
		_ipucu("kullanici", "", "En az 3 karakter.")
	else:
		_ipucu("kullanici", "kotu", he)


func _eposta_degisti(_t := "") -> void:
	_eposta_kontrol(false)


# yazarken yalnızca geçerliyse yeşil olur; alandan çıkınca (ya da gönderirken) hatası söylenir
func _eposta_kontrol(sert: bool) -> void:
	if not _alanlar.has("eposta"):
		return
	var e := Account.clean_email(_metin("eposta"))
	if e == "":
		_ipucu("eposta", "")
		return
	var he := Account.eposta_hatasi(e)
	if he == "":
		_ipucu("eposta", "iyi", "E-posta adresi uygun.")
	elif sert or e.contains(" "):
		_ipucu("eposta", "kotu", he)
	else:
		_ipucu("eposta", "")


func _sifre_degisti(t: String) -> void:
	if t == "":
		_ipucu("sifre", "")
	elif t.length() < 6:
		_ipucu("sifre", "", tr("En az 6 karakter (%d/6).") % t.length())
	else:
		_ipucu("sifre", "iyi", "Şifre uygun.")


func _durum_satiri() -> void:
	var mr := HBoxContainer.new()
	mr.alignment = BoxContainer.ALIGNMENT_CENTER
	mr.add_theme_constant_override("separation", UI.B_XS)
	_don = E.spinner(22)
	_don.visible = false
	mr.add_child(_don)
	_msg = UI.label("", UI.FS_KUCUK + 1, UI.KIRMIZI.lightened(0.35), true)
	_msg.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # gelen metin zaten çevrildi
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.custom_minimum_size = Vector2(KART_W - 90, 22)
	mr.add_child(_msg)
	_form.add_child(mr)
	if not account.connected and not _args.has("demo"):
		_bekle_yaz(tr("Sunucuya bağlanılıyor…"))


func _ana_dugme(metin: String, ikon: String) -> void:
	_go = UI.button(metin, "ana", UI.BTN_H, UI.FS_BUYUK - 6, ikon)
	_go.pressed.connect(_submit)
	_form.add_child(_go)


func _baglanti_satiri() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", UI.B_L)
	_form.add_child(h)
	return h


# Altı çizili yazı düğmesi (parmakla rahat basılacak yükseklikte)
func _baglanti(h: HBoxContainer, metin: String, f: Callable) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.text = metin
	b.custom_minimum_size.y = 48
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_color_override("font_color", Color(UI.AMBER, 0.95))
	b.add_theme_color_override("font_hover_color", UI.AMBER.lightened(0.3))
	b.add_theme_color_override("font_pressed_color", UI.AMBER.darkened(0.2))
	b.add_theme_color_override("font_focus_color", Color(UI.AMBER, 0.95))
	var alt := ColorRect.new()
	alt.color = Color(UI.AMBER, 0.6)
	alt.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	alt.offset_top = -10
	alt.offset_bottom = -8
	alt.offset_left = 6
	alt.offset_right = -6
	alt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(alt)
	b.pressed.connect(func() -> void:
		UI.tik()
		f.call())
	h.add_child(b)
	return b


func _hesap_karti() -> void:
	_baslik("SİCİL KARTIN", "HESAP")
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", UI.B_M)
	r.add_child(E.avatar(account.handle, account.handle, 84, "acik"))
	var tv := VBoxContainer.new()
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_theme_constant_override("separation", 0)
	var hl := UI.title("@" + account.handle, UI.FS_BUYUK, UI.METIN)
	hl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	tv.add_child(hl)
	tv.add_child(UI.label("Oyundaki adın kullanıcı adındır.", UI.FS_KUCUK, UI.METIN_SOLUK))
	r.add_child(tv)
	_form.add_child(r)
	# e-posta durumu
	var kutu := E.row_box(UI.YESIL if account.eposta_ok else UI.AMBER, Vector4(14, 8, 14, 8))
	var kh := HBoxContainer.new()
	kh.add_theme_constant_override("separation", UI.B_S)
	var ik := UI.icon("onay" if account.eposta_ok else "kilit", 34)
	ik.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kh.add_child(ik)
	var kv := VBoxContainer.new()
	kv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kv.add_theme_constant_override("separation", 0)
	var el := UI.label(account.eposta if account.eposta != "" else tr("E-posta yok"), UI.FS_METIN, UI.METIN)
	el.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	kv.add_child(el)
	kv.add_child(UI.label("E-posta doğrulandı" if account.eposta_ok else "E-posta doğrulanmadı", UI.FS_KUCUK, UI.YESIL.lightened(0.2) if account.eposta_ok else UI.AMBER))
	kh.add_child(kv)
	if not account.eposta_ok:
		var kb := UI.button("KODU GİR", "ana", 56, 18, "", 150)
		kb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		kb.pressed.connect(func() -> void: _git("dogrula" if account.eposta_var else "eposta"))
		kh.add_child(kb)
	kutu.add_child(kh)
	_form.add_child(kutu)
	_durum_satiri()
	var ok := UI.button("TAMAM", "ana", UI.BTN_H, UI.FS_BUYUK - 6)
	ok.pressed.connect(_kapat_izinliyse)
	_form.add_child(ok)
	var out := UI.button("ÇIKIŞ YAP", "ikincil", UI.DOKUNMA, 20, "geri")
	out.pressed.connect(_cikis)
	_form.add_child(out)
	if OS.get_cmdline_user_args().has("cikis_onay=1"):
		out.pressed.emit.call_deferred()  # test pozu


func _cikis() -> void:
	cikis_onayi(_kok, account, func() -> void: _git("giris"))


func _git(mod: String) -> void:
	_mod = mod
	_bekliyor += 1  # bekleyen zaman aşımı iptal
	_bekleyen = ""
	_build()


# ---------------------------------------------------------------------
# Gönderme
# ---------------------------------------------------------------------
func _metin(ad: String) -> String:
	return (_alanlar[ad] as LineEdit).text if _alanlar.has(ad) else ""


func _submit() -> void:
	if not is_instance_valid(_go) or _go.disabled:
		return  # cevap bekleniyor
	match _mod:
		"kayit":
			var h := Account.clean_handle(_metin("kullanici"))
			var he := Account.handle_error(h)
			if he != "":
				_alan_hata("kullanici", he)
				return
			var e := Account.clean_email(_metin("eposta"))
			var ee := Account.eposta_hatasi(e)
			if ee != "":
				_alan_hata("eposta", ee)
				return
			if _metin("sifre").length() < 6:
				_alan_hata("sifre", "Şifre en az 6 karakter olmalı.")
				return
			var sifre := _metin("sifre")
			_gonder("kayit", func() -> void: account.sign_up(h, e, sifre))
		"giris":
			var k := _metin("kim").strip_edges()
			if k == "":
				_alan_hata("kim", "Kullanıcı adını ya da e-postanı yaz.")
				return
			var sifre := _metin("sifre")
			if sifre == "":
				_alan_hata("sifre", "Şifreni yaz.")
				return
			_gonder("giris", func() -> void: account.sign_in(k, sifre))
		"unuttum":
			_kim = _metin("kim").strip_edges()
			if _kim == "":
				_alan_hata("kim", "Kullanıcı adını ya da e-postanı yaz.")
				return
			_gonder("unuttum", func() -> void: account.sifre_unuttum(_kim))
		"sifirla":
			var kod := _metin("kod")
			if kod.length() != 6:
				_alan_hata("kod", "Kod 6 haneli olmalı.")
				return
			var sifre := _metin("sifre")
			if sifre.length() < 6:
				_alan_hata("sifre", "Şifre en az 6 karakter olmalı.")
				return
			_gonder("sifirla", func() -> void: account.sifre_sifirla(_kim, kod, sifre))
		"eposta":
			var e := Account.clean_email(_metin("eposta"))
			var ee := Account.eposta_hatasi(e)
			if ee != "":
				_alan_hata("eposta", ee)
				return
			_gonder("eposta", func() -> void: account.eposta_ekle(e))
		"dogrula":
			var kod := _metin("kod")
			if kod.length() != 6:
				_alan_hata("kod", "Kod 6 haneli olmalı.")
				return
			_gonder("dogrula", func() -> void: account.eposta_dogrula(kod))


func _gonder(tur: String, f: Callable) -> void:
	if not account.connected:
		_hata(tr("Bağlantı yok. İnternetini kontrol et."))
		return
	_bekle_yaz(tr("Bekle…"))
	if is_instance_valid(_go):
		_go.disabled = true
	_bekleyen = tur
	_bekliyor += 1
	var sira := _bekliyor
	get_viewport().gui_release_focus()  # klavye kapansın
	get_tree().create_timer(9.0).timeout.connect(func() -> void:
		if sira == _bekliyor and _bekleyen != "":
			_bekleyen = ""
			if is_instance_valid(_go):
				_go.disabled = false
			_hata(tr("Cevap yok. Tekrar dene.")))
	f.call()


func _cevap_bitti() -> void:
	_bekliyor += 1
	_bekleyen = ""
	if is_instance_valid(_go):
		_go.disabled = false
	_don_kapat()


# Bekleme yazısı: amber, yanında dönen gösterge
func _bekle_yaz(m: String) -> void:
	if not is_instance_valid(_msg):
		return
	_msg.add_theme_color_override("font_color", UI.AMBER)
	_msg.set_meta("kirmizi", false)
	_msg.text = m
	if is_instance_valid(_don):
		_don.visible = true


func _don_kapat() -> void:
	if is_instance_valid(_don):
		_don.visible = false


func _bilgi(m: String) -> void:
	if not is_instance_valid(_msg):
		return
	_don_kapat()
	_msg.add_theme_color_override("font_color", UI.YESIL.lightened(0.2))
	_msg.set_meta("kirmizi", false)
	_msg.text = m


# Hata yazısı + kart hafifçe sallanır
func _hata(m: String, salla := true) -> void:
	if not is_instance_valid(_msg):
		return
	_don_kapat()
	_msg.add_theme_color_override("font_color", UI.KIRMIZI.lightened(0.35))
	_msg.set_meta("kirmizi", true)
	_msg.text = m
	if salla:
		_salla()


func _salla() -> void:
	if not is_instance_valid(_kart):
		return
	UI.tik()
	var x0 := _kart.position.x
	var tw := _kart.create_tween()
	for k in [12.0, -9.0, 6.0, -3.0, 0.0]:
		tw.tween_property(_kart, "position:x", x0 + k, 0.045)


# ---------------------------------------------------------------------
# Sunucu cevapları
# ---------------------------------------------------------------------
func _on_me() -> void:
	if _args.has("demo"):
		return
	if _kapaniyor or not account.ben_geldi:
		return  # hesap değişiyor (giriş / çıkış): yeni "ben" beklenir
	if is_instance_valid(_msg) and _msg.text == tr("Sunucuya bağlanılıyor…"):
		_msg.text = ""
		_don_kapat()
	if account.has_account:
		_plaka(account.handle)
		var b := _bekleyen
		if b in ["kayit", "giris", "sifirla"]:
			_cevap_bitti()
			_basari(b)
		elif _mod in ["kayit", "giris", "unuttum", "sifirla"] and b == "":
			# ekran açıkken hesap bilgisi geldi (ör. açılışta sunucu cevabı perdeden sonra geldi)
			if account.eposta_var and zorunlu:
				_kapat()
			elif not account.eposta_var:
				_git("eposta")
	elif _mod in ["eposta", "dogrula", "hesap"]:
		_git("giris")  # çıkış yapıldı / oturum kapandı


func _on_olay(t: String, d: Dictionary) -> void:
	if _kapaniyor:
		return
	match t:
		"sifirla_gitti":
			if _bekleyen == "unuttum":
				_cevap_bitti()
				if _mod == "unuttum":
					_git("sifirla")
				_bilgi(Dil.sunucu(d))
		"eposta_tamam":
			if _bekleyen == "eposta":
				_cevap_bitti()
				_damga("SİCİLE İŞLENDİ", UI.AMBER, func() -> void: _git("dogrula"))
		"dogrulandi":
			if _bekleyen == "dogrula":
				_cevap_bitti()
				_damga("DOĞRULANDI", UI.YESIL, _kapat_izinliyse)
		"oturum_kapandi":
			_git("giris")
			_hata(Dil.sunucu(d), false)


# Sunucudan gelen yazı: hata kırmızı ve sallanır, bilgi (ör. "Yeni kod gönderildi") yeşil.
func _on_message(m: String) -> void:
	if _kapaniyor or not is_instance_valid(_msg):
		return
	if not bool(account.get("son_hata")):
		if _bekleyen == "tekrar":
			_cevap_bitti()
		_bilgi(m)
		return
	_cevap_bitti()
	_hata(m)


# Kayıt / giriş / yeni şifre onaylandı: damga, sonra sıradaki adım
func _basari(tur: String) -> void:
	var sonra := func() -> void:
		if not account.eposta_var:
			_git("eposta")
		elif tur == "kayit" and not account.eposta_ok:
			_git("dogrula")
		else:
			_kapat()
	match tur:
		"kayit":
			_damga("KABUL EDİLDİ", UI.YESIL, sonra)
		"sifirla":
			_damga("ŞİFRE YENİLENDİ", UI.YESIL, sonra)
		_:
			_damga("GİRİŞ ONAYLANDI", UI.YESIL, sonra)


# Kartın üstüne damga vurulur: büyükten küçülerek iner, kart sarsılır, tok bir ses.
func _damga(metin: String, renk: Color, sonra := Callable()) -> void:
	if not is_instance_valid(_kart):
		return
	var d := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(renk.darkened(0.85), 0.55)
	st.border_color = renk
	st.set_border_width_all(6)
	st.set_corner_radius_all(10)
	st.content_margin_left = 26
	st.content_margin_right = 26
	st.content_margin_top = 6
	st.content_margin_bottom = 10
	d.add_theme_stylebox_override("panel", st)
	var l := UI.title(metin, 50, renk.lightened(0.15), true)
	l.add_theme_color_override("font_outline_color", renk.darkened(0.6))
	l.add_theme_constant_override("outline_size", 6)
	d.add_child(l)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.modulate.a = 0.0
	_sahne.add_child(d)
	await get_tree().process_frame
	if not is_instance_valid(d) or not is_instance_valid(_kart):
		return
	var r := _kart.get_global_rect()
	d.size = d.get_combined_minimum_size()
	d.pivot_offset = d.size / 2.0
	d.global_position = r.get_center() - d.size / 2.0
	d.rotation = deg_to_rad(-11)
	d.scale = Vector2.ONE * 2.6
	var tw := d.create_tween()
	tw.tween_property(d, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(d, "modulate:a", 1.0, 0.1)
	tw.tween_callback(func() -> void:
		Sfx.tek(_kok, "kapi_kilit", -3.0, 0.9)
		Sfx.arayuz("odul")
		preload("res://scripts/titresim.gd").vur("orta")
		var k0 := _kart.position
		var sar := _kart.create_tween()
		for o in [Vector2(0, 7), Vector2(-4, -3), Vector2(2, 1), Vector2.ZERO]:
			sar.tween_property(_kart, "position", k0 + o, 0.05))
	tw.tween_property(d, "scale", Vector2.ONE * 1.04, 0.08)
	tw.tween_property(d, "scale", Vector2.ONE, 0.1)
	tw.tween_interval(1.1)
	if _args.get("ekran", "") == "kabul":
		return  # test pozu: damga ekranda kalsın
	tw.tween_property(d, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func() -> void:
		d.queue_free()
		if sonra.is_valid():
			sonra.call())


# ---------------------------------------------------------------------
# Kapanma
# ---------------------------------------------------------------------
# Zorunluyken yalnızca hesap (ve e-posta) varsa kapanır.
func _kapat_izinliyse() -> void:
	if zorunlu and not (account.has_account and account.eposta_var):
		_git("eposta" if account.has_account else "kayit")
		return
	_kapat()


func _geri() -> void:
	if _mod in ["unuttum", "sifirla"]:
		_git("giris")
		return
	if zorunlu and not (account.has_account and account.eposta_var):
		_hata(tr("Oynamak için hesap aç ya da giriş yap."))
		return
	_kapat()


func _kapat() -> void:
	if _kapaniyor:
		return
	_kapaniyor = true
	profile.settings.giris_soruldu = true
	profile.save()
	E.outro(_kok, func() -> void:
		closed.emit()
		queue_free())


# Telefonda klavye açılınca odaktaki alan ve altındaki düğme klavyenin üstünde kalsın: sahne yukarı kayar.
func _process(delta: float) -> void:
	if not is_instance_valid(_sahne):
		return
	var vis := get_viewport().get_visible_rect().size
	var kh := _klavye_test
	if kh <= 0.0 and DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		var win := DisplayServer.window_get_size()
		kh = float(DisplayServer.virtual_keyboard_get_height()) * vis.y / maxf(1.0, float(win.y))
	var hedef := 0.0
	var f := get_viewport().gui_get_focus_owner()
	if kh > 0.0 and f is LineEdit and _kok.is_ancestor_of(f):
		var r := (f as Control).get_global_rect()
		var ust := r.position.y + _kaydir  # kaymasız konum
		var alt := r.end.y + _kaydir + 26.0  # altındaki ipucu satırı da görünsün
		if is_instance_valid(_go) and _go.visible:
			alt = maxf(alt, _go.get_global_rect().end.y + _kaydir)  # mümkünse ana düğme de görünsün
		hedef = maxf(0.0, alt - (vis.y - kh - UI.B_S))
		hedef = minf(hedef, maxf(0.0, ust - 26.0 - UI.B_S))  # odaktaki alan (ve başlığı) ekranın üstünden taşmasın
	_kaydir = lerpf(_kaydir, hedef, minf(1.0, delta * 14.0)) if absf(_kaydir - hedef) > 0.5 else hedef
	_sahne.offset_top = -_kaydir
	_sahne.offset_bottom = -_kaydir


# Test: alanlara örnek değer (ekran görüntüsü)
func _test_doldur() -> void:
	var hatali := _args.has("hatali")
	var ornek := {"kullanici": "ali_34" if not hatali else "çağrı 34", "eposta": "ali.veli@gmail.com" if not hatali else "ali@gmail",
		"sifre": "gizli123" if not hatali else "123", "kim": "ali_34", "kod": "48"}
	for k in _alanlar:
		var e: LineEdit = _alanlar[k]
		if ornek.has(k):
			e.text = ornek[k]
			e.text_changed.emit(e.text)
	if hatali and _alanlar.has("eposta"):
		_eposta_kontrol(true)
	if hatali and _alanlar.has("sifre"):
		_ipucu("sifre", "kotu", "Şifre en az 6 karakter olmalı.")
	if hatali and is_instance_valid(_msg):
		_hata(tr("@%s alınmış, başka bir ad dene.") % "ali_34", false)


# ---------------------------------------------------------------------
# Çıkış onayı (hesap ekranı ve ayarlar): hesap sunucuda kalır, tekrar giriş yapılabilir.
# ---------------------------------------------------------------------
static func cikis_onayi(host: Node, acc: Node, bitti := Callable()) -> Control:
	var m := UI.modal("ÇIKIŞ YAP", 600)
	var l := UI.label(Dil.t("@%s hesabından çıkılsın mı?") % str(acc.handle), UI.FS_ORTA, UI.METIN, true)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m.body.add_child(l)
	var l2 := UI.label("Karakterin ve elmasların hesapta kalır.", UI.FS_METIN, UI.METIN_SOLUK, true)
	l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m.body.add_child(l2)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.B_S)
	var vaz := UI.button("VAZGEÇ", "ikincil", UI.BTN_H, UI.FS_ORTA, "")
	vaz.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vaz.pressed.connect(m.close)
	h.add_child(vaz)
	var cik := UI.button("ÇIKIŞ YAP", "tehlike", UI.BTN_H, UI.FS_ORTA, "geri")
	cik.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cik.pressed.connect(func() -> void:
		acc.sign_out()
		m.close()
		if bitti.is_valid():
			bitti.call())
	h.add_child(cik)
	m.body.add_child(h)
	host.add_child(m)
	return m


# ---------------------------------------------------------------------
# Topluluk kuralları (Apple 1.2): ilk açılışta bir kez gösterilir; kabul edilmeden çevrimiçi oynanmaz.
# Kabul profile yazılır (profile.settings.kurallar). Çevrimiçi oyuna giden her düğme kurallar_sonra() ile geçer.
# ---------------------------------------------------------------------

static func kurallar_kabul(profile: Node) -> bool:
	return profile != null and bool(profile.settings.get("kurallar", false))


# Kurallar kabul edildiyse sonra'yı hemen çağırır, değilse önce onay penceresini açar.
static func kurallar_sonra(host: Node, profile: Node, sonra: Callable) -> void:
	if kurallar_kabul(profile):
		sonra.call()
		return
	kurallar_onayi(host, profile, sonra)


static func kurallar_onayi(host: Node, profile: Node, kabul := Callable()) -> Control:
	var m := UI.modal("TOPLULUK KURALLARI", 720)
	m.perde_kapatir = false
	m.close_button.visible = false
	var maddeler := [
		["kapat", "Küfür, hakaret ve nefret söylemi yasak."],
		["engelle", "Taciz ve tehdit yasak. Hesap kapatılabilir."],
		["sikayet", "Rahatsız eden oyuncuyu oyuncu menüsünden şikayet et ya da engelle."],
	]
	for md in maddeler:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", UI.B_M)
		var ik := UI.icon(str(md[0]), 48)
		ik.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(ik)
		var l := UI.label(str(md[1]), UI.FS_METIN, UI.METIN)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		r.add_child(l)
		m.body.add_child(r)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.B_S)
	var vaz := UI.button("SONRA", "ikincil", UI.BTN_H, UI.FS_ORTA, "", 200)
	vaz.pressed.connect(m.close)
	h.add_child(vaz)
	var ok := UI.button("KABUL EDİYORUM", "ana", UI.BTN_H, UI.FS_ORTA, "onay")
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.pressed.connect(func() -> void:
		profile.settings.kurallar = true
		profile.settings.kurallar_tarih = Time.get_datetime_string_from_system(true)
		profile.save()
		m.close()
		if kabul.is_valid():
			kabul.call())
	h.add_child(ok)
	m.body.add_child(h)
	host.add_child(m)
	return m


# ---------------------------------------------------------------------
# Çizimler: hücre parmaklıkları, boy cetveli, kelepçe
# ---------------------------------------------------------------------
class Parmaklik extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var x := 46.0
		while x < w:
			draw_rect(Rect2(x, 0, 16, h), Color(0.02, 0.02, 0.02, 0.5))
			draw_rect(Rect2(x + 3, 0, 3, h), Color(1, 1, 1, 0.05))
			x += 118.0
		for y in [54.0, h - 70.0]:
			draw_rect(Rect2(0, y, w, 14), Color(0.02, 0.02, 0.02, 0.45))
			draw_rect(Rect2(0, y + 2, w, 2), Color(1, 1, 1, 0.04))


class Boy extends Control:
	const U := preload("res://scripts/ui.gd")

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var st := StyleBoxFlat.new()
		st.bg_color = Color("#1a1e1d")
		st.border_color = Color("#3a4240")
		st.set_border_width_all(2)
		st.set_corner_radius_all(14)
		draw_style_box(st, Rect2(Vector2.ZERO, size))
		var y := 18.0
		var cm := 200
		var font: Font = U.TITLE_FONT
		while y < h - 12.0:
			var kalin := cm % 10 == 0
			draw_line(Vector2(14, y), Vector2(w - 14, y), Color(U.METIN, 0.16 if kalin else 0.07), 2.0 if kalin else 1.0)
			if kalin:
				draw_string(font, Vector2(18, y - 4), str(cm), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(U.METIN, 0.35))
				draw_string(font, Vector2(w - 50, y - 4), str(cm), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(U.METIN, 0.35))
			y += 24.0
			cm -= 5


class Kelepce extends Control:
	func _draw() -> void:
		var celik := Color("#9aa3a6")
		var koyu := Color("#4b5254")
		var parla := Color(1, 1, 1, 0.55)
		var r := 26.0
		var a := Vector2(r + 4, size.y / 2.0 + 6)
		var b := Vector2(size.x - r - 4, size.y / 2.0 + 6)
		for m in [a, b]:
			draw_arc(m, r, 0, TAU, 40, koyu, 9.0)
			draw_arc(m, r, 0, TAU, 40, celik, 6.0)
			draw_arc(m, r - 1, deg_to_rad(200), deg_to_rad(290), 12, parla, 2.0)
			draw_rect(Rect2(m + Vector2(-9, -r - 10), Vector2(18, 14)), celik)
			draw_rect(Rect2(m + Vector2(-9, -r - 10), Vector2(18, 14)), koyu, false, 2.0)
		# zincir halkaları
		var n := 4
		for i in n:
			var t := (i + 0.5) / float(n)
			var p := a.lerp(b, t) + Vector2(0, -r - 4 + sin(t * PI) * 10.0)
			draw_arc(p, 6.0, 0, TAU, 16, koyu, 4.0)
			draw_arc(p, 6.0, 0, TAU, 16, celik, 2.5)
