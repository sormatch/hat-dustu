# Ayarlar. Nereden açıldığına göre iki görünüm:
#  - ANA MENÜDEN ("menu"): tam ekran ayarlar; solda sekmeler (PROFİL / SES / GÖRÜNTÜ / KONTROLLER / HESAP).
#    Profil, dil, hesap, giriş/çıkış, engellenenler, yasal sayfalar ve hesap silme yalnız burada.
#  - ODADA ("lobi") ve MAÇTA ("mac"): sağda kısa panel (dışı hafif karartılır); oyun arkada sürer (çok oyunculu oyun
#    durmaz). Yalnız oyunla ilgili ayarlar: müzik / efekt / sesli sohbet, mikrofon aç-kapa, grafik kalitesi,
#    bakış hassasiyeti ve onaylı ODADAN ÇIK / MAÇTAN ÇIK. Hesap, profil, yasal, hesap silme YOK.
# Her değişiklik anında kaydedilir ve oyuna hemen uygulanır.
extends CanvasLayer

signal closed
signal open_character
signal leave_room

const UI := preload("res://scripts/ui.gd")
const E := preload("res://scripts/ekran.gd")
const Sfx := preload("res://scripts/sfx.gd")
const ThumbsScript := preload("res://scripts/thumbs.gd")
const Dil := preload("res://scripts/dil.gd")
const RINGS := ["Klasik çan", "Eski telefon", "Modern"]
const KALITE := ["Pil dostu", "Yüksek", "Ultra"]
const SEKMELER := [["PROFİL", "profile"], ["SES", "ses"], ["GÖRÜNTÜ", "graphics"], ["KONTROLLER", "controls"], ["HESAP", "kilit"]]
const PANEL_W := 580.0  # oyun içi panelin genişliği (1280 tabanda ekranın yarısından az: oyun görünür kalır)

var profile: Node
var account: Node
var voice: Node
var sekme := 0
# "menu" = tam ayarlar, "lobi" = odadaki kısa panel, "mac" = maçtaki kısa panel.
# Boş bırakılırsa sahneden anlaşılır (main.gd: playing / in_lobby). Test: komut satırında baglam=menu|lobi|mac
var baglam := ""

var _kok: Control
var _panel: PanelContainer
var _tab_btns: Array = []
var _icerik: VBoxContainer
var _scroll: ScrollContainer
var _name: LineEdit
var _mic_bar: Control
var _mic_btn: Button
var _preview: AudioStreamPlayer
var _thumbs: Node
var _engel_kutu: VBoxContainer
var _ver: Label
var _kapaniyor := false


func _ready() -> void:
	layer = 15
	_thumbs = ThumbsScript.new()
	add_child(_thumbs)
	_preview = AudioStreamPlayer.new()
	add_child(_preview)
	if baglam == "":
		baglam = _baglam_bul()
	if oyun_ici():
		_kur_panel()
	else:
		_kur_tam()


func oyun_ici() -> bool:
	return baglam == "lobi" or baglam == "mac"


func _baglam_bul() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("baglam="):
			return a.substr(7)
	var m = get_tree().current_scene
	if m and bool(m.get("playing")):
		return "lobi" if bool(m.get("in_lobby")) else "mac"
	return "menu"


# Ana menüden açılan tam ekran ayarlar
func _kur_tam() -> void:
	var s := E.screen("AYARLAR", "ayarlar", "bg_settings", 0.62)
	_kok = s.kok
	add_child(_kok)
	(s.geri as Button).pressed.connect(_close)
	var govde: Control = s.govde
	var cols := HBoxContainer.new()
	cols.set_anchors_preset(Control.PRESET_FULL_RECT)
	cols.offset_left = 16
	cols.offset_right = -16
	cols.offset_bottom = -12
	cols.add_theme_constant_override("separation", UI.B_M)
	govde.add_child(cols)
	# sol: sekmeler
	var rail := UI.panel(Vector2(290, 0), 26)
	cols.add_child(rail)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", UI.B_S)
	rail.add_child(rv)
	for i in SEKMELER.size():
		var b := UI.button(SEKMELER[i][0], "ana" if i == sekme else "ikincil", 70, 20, SEKMELER[i][1])
		b.pressed.connect(func() -> void: _sec(i))
		rv.add_child(b)
		_tab_btns.append(b)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(sp)
	_ver = UI.label(tr("Hat Düştü  ·  sürüm %s") % _surum(), UI.FS_KUCUK, UI.METIN_SOLUK, true)
	rv.add_child(_ver)
	# sağ: içerik
	var p := UI.panel(Vector2.ZERO, 34)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(p)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.touch_scroll(_scroll)
	p.add_child(_scroll)
	_icerik = VBoxContainer.new()
	_icerik.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_icerik.add_theme_constant_override("separation", UI.B_S)
	_scroll.add_child(_icerik)
	if account:
		account.me_changed.connect(func() -> void:
			if sekme == 0 or sekme == 4:
				_build())
		account.blocks_changed.connect(_fill_blocks)
		# seviye, elmas ve istatistikler sunucudan sonra gelir: profil sekmesi açıkken yenilensin
		# (ad yazılırken yenilenmez, klavye kapanmasın)
		account.economy_changed.connect(func() -> void:
			if sekme == 0 and not (is_instance_valid(_name) and _name.has_focus()):
				_build())
	_build()
	E.intro(_kok, govde)


# Odada / maçta: sağda kısa panel. Panelin dışına dokununca (ya da geri tuşuyla) kapanır.
func _kur_panel() -> void:
	_kok = Control.new()
	_kok.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_kok)
	# panel dışı: hafif karartma (oyun görünür kalır); dokununca kapanır
	var perde := ColorRect.new()
	perde.set_anchors_preset(Control.PRESET_FULL_RECT)
	perde.color = Color(0, 0, 0, 0.3)
	perde.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_close())
	_kok.add_child(perde)
	var kap := Control.new()
	kap.set_anchors_preset(Control.PRESET_FULL_RECT)
	kap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kok.add_child(kap)
	UI.guvenli(kap, UI.KENAR_PAYI - 16.0)  # çentik / yuvarlak köşe payı
	_panel = UI.panel(Vector2(PANEL_W, 0), 18)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -PANEL_W
	_panel.offset_right = 0.0
	_panel.offset_top = 6.0
	_panel.offset_bottom = -6.0
	kap.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UI.B_S)
	_panel.add_child(v)
	# üst: ikon + AYARLAR + kapat
	var ust := HBoxContainer.new()
	ust.add_theme_constant_override("separation", UI.B_S)
	v.add_child(ust)
	var ic := UI.icon("ayarlar", 44)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ust.add_child(ic)
	var t := UI.title("AYARLAR", 28, UI.METIN)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ust.add_child(t)
	var kapat := UI.icon_button("kapat", "ikincil", UI.DOKUNMA)
	kapat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kapat.pressed.connect(_close)
	ust.add_child(kapat)
	# orta: ayarlar (sığmazsa kayar)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UI.touch_scroll(_scroll)
	v.add_child(_scroll)
	_icerik = VBoxContainer.new()
	_icerik.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_icerik.add_theme_constant_override("separation", 5)
	_scroll.add_child(_icerik)
	# alt: odadan / maçtan çık (onaylı)
	var cik := UI.button("ODADAN ÇIK" if baglam == "lobi" else "MAÇTAN ÇIK", "tehlike", UI.BTN_H_KUCUK, 22, "geri")
	cik.pressed.connect(_cikis_onayi)
	v.add_child(cik)
	UI.geri_tusu(_kok, _close)  # Android geri tuşu / Esc
	_build()
	# açılış: sağdan kayarak gelir
	_kok.modulate.a = 0.0
	_panel.offset_left = -PANEL_W + 70.0
	_panel.offset_right = 70.0
	var tw := _kok.create_tween().set_parallel(true)
	tw.tween_property(_kok, "modulate:a", 1.0, 0.16)
	tw.tween_property(_panel, "offset_left", -PANEL_W, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "offset_right", 0.0, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if OS.get_cmdline_user_args().has("cik_onay=1"):
		_cikis_onayi.call_deferred()  # test pozu


func _build_panel() -> void:
	if not profile.settings.has("muzik_ses"):
		profile.settings["muzik_ses"] = 0.7
	_pbaslik("ses", "SES")
	_prow("Müzik", _slider(0.0, 1.0, "muzik_ses", "%d%%"))
	_prow("Efektler", _slider(0.0, 1.0, "oyun_ses", "%d%%"))
	_prow("Sesli sohbet", _slider(0.0, 1.5, "konusma_ses", "%d%%"))
	_prow("Mikrofon", _mic_anahtar())
	_pbaslik("controls", "OYUN")
	_prow("Grafik", _choice(KALITE, int(profile.settings.kalite), func(i: int) -> void:
		profile.settings.kalite = i
		profile.save()
		_uygula("kalite", i)))
	_prow("Hassasiyet", _slider(0.5, 2.0, "hassasiyet", "%d%%"))


# Paneldeki küçük bölüm başlığı: ikon + amber yazı
func _pbaslik(icon_name: String, text: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.B_XS)
	var ic := UI.icon(icon_name, 28)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var t := UI.title(text, 18, UI.AMBER)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(t)
	_icerik.add_child(h)


# Paneldeki tek satır: solda kısa ad, sağda denetim (en az 64 px yükseklik)
func _prow(title: String, control: Control) -> void:
	var box := E.row_box(Color(0, 0, 0, 0), Vector4(14, 2, 10, 2))
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", UI.B_S)
	r.custom_minimum_size.y = UI.DOKUNMA
	box.add_child(r)
	var t := UI.title(title, 20, UI.METIN)
	t.custom_minimum_size.x = 150
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	r.add_child(t)
	UI.sigdir(t, 150)
	if control is ESwitch:
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(sp)
	else:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(control)
	_icerik.add_child(box)


# Mikrofon aç/kapa (yalnız bu oturum: odadan çıkınca / oyun yeniden açılınca mikrofon yine açık).
# HUD'daki mikrofon göstergesiyle (hud.gd mik_kapat / mik_kapali) aynı durumu kullanır: biri değişince öbürü de.
func _mic_anahtar() -> Control:
	var hud = _hud()
	var acik: bool = not bool(hud.get("mik_kapali")) if hud else mikrofon_acik(voice)
	return E.switch(acik, func(on: bool) -> void:
		var h = _hud()
		if h:
			h.mik_kapat(not on)  # HUD kendi bildirimini gösterir
		else:
			mikrofon_ayarla(voice, on)
			UI.toast("Mikrofon açık" if on else "Mikrofon kapalı", null, 1.6, "bilgi"))


func _hud() -> Node:
	var m = get_tree().current_scene
	var h = m.get("hud") if m else null
	if h and h.has_method("mik_kapat") and "mik_kapali" in h:
		return h
	return null


static func mikrofon_acik(v: Node) -> bool:
	if v == null or v.get("_mic_player") == null:
		return true
	return (v.get("_mic_player") as AudioStreamPlayer).volume_db > -60.0


# voice.gd mikrofonu kendi oynatıcısından (Mikrofon bus'ı) yakalar: oynatıcı sessize alınınca yakalanan ses
# sıfıra iner, ses kapısı hiç açılmaz ve kimseye bir şey gitmez.
static func mikrofon_ayarla(v: Node, on: bool) -> void:
	if v == null or v.get("_mic_player") == null:
		return
	(v.get("_mic_player") as AudioStreamPlayer).volume_db = 0.0 if on else -80.0


# Değişiklik oyuna hemen uygulansın (kapanınca main.gd apply_settings zaten hepsini yeniden uygular)
func _uygula(key: String, v: Variant) -> void:
	var m = get_tree().current_scene
	if m == null:
		return
	match key:
		"muzik_ses":
			var mz = m.get("muzik")
			if mz and mz.has_method("set_volume"):
				mz.set_volume(float(v))
		"oyun_ses":
			var mz = m.get("muzik")
			if mz and mz.has_method("set_efekt"):
				mz.set_efekt(float(v))
		"konusma_ses":
			if voice and voice.has_method("set_volume"):
				voice.set_volume(float(v))
		"hassasiyet":
			var pl = m.get("player")
			if pl and "sensitivity" in pl:
				pl.sensitivity = float(v)
		"kalite":
			if m.has_method("apply_settings") and m.get("player") != null:
				m.apply_settings()


# Odadan / maçtan çık: onay penceresi
func _cikis_onayi() -> void:
	var lobi := baglam == "lobi"
	var m := UI.modal("ODADAN ÇIK" if lobi else "MAÇTAN ÇIK", 600)
	var ic := UI.icon("kapi", 72)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	m.body.add_child(ic)
	var l := UI.label("Ana menüye dönersin." if lobi else "Maçtan çıkarsın.", UI.FS_METIN, UI.METIN, true)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m.body.add_child(l)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.B_S)
	var vaz := UI.button("VAZGEÇ", "ikincil", UI.BTN_H, UI.FS_ORTA, "")
	vaz.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vaz.pressed.connect(m.close)
	h.add_child(vaz)
	var cik := UI.button("ÇIK", "tehlike", UI.BTN_H, UI.FS_ORTA, "kapi")
	cik.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cik.pressed.connect(func() -> void:
		cik.disabled = true
		vaz.disabled = true
		leave_room.emit())
	h.add_child(cik)
	m.body.add_child(h)
	_kok.add_child(m)


func _surum() -> String:
	# tek kaynak: project.godot application/config/version (export_presets.cfg sürümleriyle aynı)
	return str(ProjectSettings.get_setting("application/config/version", "?"))


func _sec(i: int) -> void:
	if i < 0 or i == sekme or oyun_ici():
		return
	_save_name()
	if voice and voice.testing:
		voice.stop_test()
	sekme = i
	for k in _tab_btns.size():
		UI.set_button_kind(_tab_btns[k], "ana" if k == sekme else "ikincil")
	_build()
	E.stagger(_icerik, 0.04)


func _build() -> void:
	for c in _icerik.get_children():
		_icerik.remove_child(c)
		c.queue_free()
	_name = null
	_mic_bar = null
	_engel_kutu = null
	_scroll.scroll_vertical = 0
	if oyun_ici():
		_build_panel()
		return
	match sekme:
		0:
			_build_profil()
		1:
			_build_ses()
		2:
			_build_goruntu()
		3:
			_build_kontroller()
		4:
			_build_hesap()


func _baslik(text: String) -> void:
	var t := UI.title(text, UI.FS_ORTA, UI.AMBER)
	_icerik.add_child(t)


# ---------------------------------------------------------------------
# Sekmeler (ana menüdeki tam ayarlar)
# ---------------------------------------------------------------------
func _build_profil() -> void:
	var card := E.row_box(UI.AMBER, Vector4(20, 16, 20, 16))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.B_L)
	card.add_child(h)
	var pk := Control.new()
	pk.custom_minimum_size = Vector2(150, 170)
	h.add_child(pk)
	var hale := E.glow(UI.AMBER, 0.35)
	hale.set_anchors_preset(Control.PRESET_FULL_RECT)
	pk.add_child(hale)
	var pic := TextureRect.new()
	pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pk.add_child(pic)
	_thumbs.request(profile.look, "aksesuar", str(profile.look.aksesuar), pic)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", UI.B_S)
	h.add_child(v)
	v.add_child(UI.label("Oyundaki adın (kullanıcı adın)", UI.FS_KUCUK, UI.METIN_SOLUK))
	var ad_l := UI.title(profile.player_name, UI.FS_BUYUK, UI.METIN)
	ad_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	ad_l.clip_text = true
	ad_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(ad_l)
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", UI.B_S)
	var sv := int(account.eco.get("seviye", 1)) if account else 1
	var lv := E.level_shield(sv, 52)
	lv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_child(lv)
	var iv := VBoxContainer.new()
	iv.alignment = BoxContainer.ALIGNMENT_CENTER
	iv.add_theme_constant_override("separation", -2)
	iv.add_child(UI.title(tr("SEVİYE %d") % sv, 20, UI.METIN))
	var handle: String = account.handle if account and account.handle != "" else ""
	iv.add_child(UI.label("@" + handle if handle != "" else tr("Giriş yapılmadı"), UI.FS_KUCUK, UI.AMBER if handle != "" else UI.METIN_SOLUK))
	iv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(iv)
	var gem := UI.counter("elmas", E.sayi(int(account.eco.get("elmas", profile.gems)) if account else profile.gems), 36)
	gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	(gem.get_meta("label") as Label).add_theme_color_override("font_color", UI.ELMAS)
	info.add_child(gem)
	v.add_child(info)
	_icerik.add_child(card)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", UI.B_S)
	var edit := UI.button("KARAKTERİ DÜZENLE", "ikincil", UI.DOKUNMA, 22, "magaza")
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.pressed.connect(func() -> void:
		_save_name()
		open_character.emit())
	btns.add_child(edit)
	var acc := UI.button("HESABIM" if account and account.has_account else "GİRİŞ / KAYIT", "ikincil", UI.DOKUNMA, 22, "arkadas")
	acc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acc.pressed.connect(_open_login)
	btns.add_child(acc)
	_icerik.add_child(btns)
	_icerik.add_child(_istatistik())
	# Dil / Language: iki dilde de aynı yazılır (yanlış dilde kalan oyuncu da bulsun); seçince anında uygulanır
	var diller: Array = Dil.DILLER
	_row("Dil / Language", "", _choice(diller.map(func(k: String) -> String: return Dil.ADLAR[k]), diller.find(Dil.kod()), func(i: int) -> void:
		Dil.ayarla(profile, diller[i])
		_dil_degisti.call_deferred()))
	_eposta_uyarisi()


# Profil: e-posta doğrulanmadıysa uyarı ve kod girme yeri (doğrulama oynamayı engellemez)
func _eposta_uyarisi() -> void:
	if not (account and account.has_account) or account.eposta_ok:
		return
	var kutu := E.row_box(UI.AMBER, Vector4(14, 8, 14, 8))
	var kh := HBoxContainer.new()
	kh.add_theme_constant_override("separation", UI.B_S)
	var ik := UI.icon("kilit", 34)
	ik.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kh.add_child(ik)
	var kv := VBoxContainer.new()
	kv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kv.add_theme_constant_override("separation", 0)
	kv.add_child(UI.title("E-posta doğrulanmadı" if account.eposta_var else "E-posta eklenmedi", UI.FS_ORTA - 2, UI.AMBER))
	var al := UI.label(tr("%s adresine gelen 6 haneli kodu gir; şifreni unutursan hesabını kurtarabilirsin.") % account.eposta if account.eposta_var else tr("Şifreni unutursan hesabını kurtarmak için e-posta adresini ekle."), UI.FS_KUCUK, UI.METIN_SOLUK)
	al.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	al.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	kv.add_child(al)
	kh.add_child(kv)
	var kb := UI.button("KODU GİR" if account.eposta_var else "E-POSTA EKLE", "ana", 60, 18, "", 190)
	kb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kb.pressed.connect(func() -> void: _open_login("dogrula" if account.eposta_var else "eposta"))
	kh.add_child(kb)
	kutu.add_child(kh)
	_icerik.add_child(kutu)


# Profil istatistikleri: maç, galibiyet, kazanma oranı, açılan kasa (sunucudaki ekonomi.istatistik)
func _istatistik() -> Control:
	var st: Dictionary = account.eco.get("istatistik", {}) if account else {}
	var mac := int(st.get("mac", 0))
	var gal := int(st.get("galibiyet", 0))
	var g := HBoxContainer.new()
	g.add_theme_constant_override("separation", UI.B_S)
	var kartlar := [["oyna", "MAÇ", E.sayi(mac)], ["tac", "GALİBİYET", E.sayi(gal)],
		["liderlik", "KAZANMA", (tr("%%%d") % roundi(100.0 * gal / mac)) if mac > 0 else "—"], ["kasa", "KASA", E.sayi(int(st.get("kasa", 0)))]]
	for k in kartlar:
		var box := E.row_box(Color(0, 0, 0, 0), Vector4(12, 12, 12, 12))
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", 2)
		box.add_child(v)
		var ic := UI.icon(k[0], 48)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		v.add_child(UI.title(k[2], UI.FS_BUYUK - 4, UI.METIN, true))
		v.add_child(UI.label(k[1], UI.FS_KUCUK, UI.METIN_SOLUK, true))
		g.add_child(box)
	return g


func _build_ses() -> void:
	if not profile.settings.has("muzik_ses"):
		profile.settings["muzik_ses"] = 0.7
	_baslik("SES")
	_row("Müzik", "", _slider(0.0, 1.0, "muzik_ses", "%d%%"))
	_row("Efektler", "Adımlar, kapılar, zil", _slider(0.0, 1.0, "oyun_ses", "%d%%"))
	_row("Sesli sohbet", "", _slider(0.0, 1.5, "konusma_ses", "%d%%"))
	_row("Zil sesi", "", _choice(RINGS, int(profile.settings.zil), func(i: int) -> void:
		profile.settings.zil = i
		profile.save()
		_play_ring(i)))
	_baslik("MİKROFON")
	var mic := HBoxContainer.new()
	mic.add_theme_constant_override("separation", UI.B_S)
	_mic_btn = UI.button("TEST ET", "ikincil", UI.DOKUNMA, 20, "mikrofon", 170)
	_mic_btn.pressed.connect(_toggle_mic)
	mic.add_child(_mic_btn)
	_mic_bar = UI.progress(0.0, 160, 30)
	_mic_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mic_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mic.add_child(_mic_bar)
	_row("Mikrofon testi", "Konuş: çubuk dolmalı", mic)
	_row("Bas-konuş", "Sadece basılıyken konuşursun", _switch("bas_konus"))


func _build_goruntu() -> void:
	_baslik("GÖRÜNTÜ")
	_row("Grafik kalitesi", "Pil dostu: telefon daha az ısınır", _choice(KALITE, int(profile.settings.kalite), func(i: int) -> void:
		profile.settings.kalite = i
		profile.save()))
	_row("Görüş açısı", "", _slider(60.0, 95.0, "fov", "%d°", 1.0, 1.0))
	_row("FPS göster", "", _switch("fps"))


func _build_kontroller() -> void:
	_baslik("KONTROLLER")
	_row("Bakış hassasiyeti", "", _slider(0.5, 2.0, "hassasiyet", "%d%%"))
	_row("Joystick", "", _choice(["Değdiği yerde", "Sabit"], 0 if profile.settings.yuzen_joy else 1, func(i: int) -> void:
		profile.settings.yuzen_joy = i == 0
		profile.save()))
	_row("Titreşim", "", _switch("titresim", true))
	_row("Kafa sallanması", "", _switch("bob", true))


func _build_hesap() -> void:
	_baslik("HESAP")
	var has: bool = account != null and account.has_account
	var durum := HBoxContainer.new()
	durum.add_theme_constant_override("separation", UI.B_S)
	durum.alignment = BoxContainer.ALIGNMENT_END  # düğme diğer satırlardaki gibi sağa yaslı
	if has:
		var out := UI.button("ÇIKIŞ YAP", "ikincil", UI.DOKUNMA, 20, "geri", 190)
		# onay penceresi (scripts/giris.gd); çıkınca bu sekme misafir olarak yeniden kurulur
		out.pressed.connect(func() -> void:
			preload("res://scripts/giris.gd").cikis_onayi(_kok, account, func() -> void:
				UI.toast("Çıkış yapıldı", null, 2.0, "bilgi")
				_build()))
		durum.add_child(out)
		if OS.get_cmdline_user_args().has("cikis_onay=1"):
			out.pressed.emit.call_deferred()  # test pozu
	else:
		var gir := UI.button("GİRİŞ / KAYIT", "ikincil", UI.DOKUNMA, 20, "arkadas", 270)
		gir.pressed.connect(_open_login)
		durum.add_child(gir)
	_row("@" + account.handle if has else tr("Giriş yapılmadı"), (account.eposta if account.eposta != "" else tr("E-posta yok")) if has else "Oynamak için hesap aç ya da giriş yap.", durum)

	_baslik("ENGELLENENLER")
	_engel_kutu = VBoxContainer.new()
	_engel_kutu.add_theme_constant_override("separation", UI.B_XS)
	_icerik.add_child(_engel_kutu)
	_fill_blocks()
	if account:
		account.send({"t": "engeller"})

	_baslik("YASAL")
	_row("Gizlilik politikası", "", _link_btn("/gizlilik"))
	_row("Kullanım koşulları", "", _link_btn("/kosullar"))
	_row("Hesap silme sayfası", "", _link_btn("/hesap-sil"))

	var sil := UI.button("HESABI SİL", "tehlike", UI.DOKUNMA, 20, "kapat", 230)
	sil.pressed.connect(_confirm_delete)
	var sh := HBoxContainer.new()
	sh.alignment = BoxContainer.ALIGNMENT_END
	sh.add_child(sil)
	_row("Hesabı sil", "Geri alınamaz", sh)
	var foot := UI.label(tr("Hat Düştü  ·  sürüm %s\nSaç modelleri: MakeHuman (CC0) · Dokular: Poly Haven (CC0) · Animasyonlar: Mixamo · Yazı tipleri: Russo One, Rubik (OFL)") % _surum(), UI.FS_KUCUK, Color(UI.METIN_SOLUK, 0.8), true)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_icerik.add_child(foot)


# Dil değişti: biçimli yazılar (sürüm, seviye...) yeni dilde yeniden kurulsun.
func _dil_degisti() -> void:
	if is_instance_valid(_ver):
		_ver.text = tr("Hat Düştü  ·  sürüm %s") % _surum()
	_build()


func _fill_blocks() -> void:
	if _engel_kutu == null or not is_instance_valid(_engel_kutu):
		return
	for c in _engel_kutu.get_children():
		c.queue_free()
	# kullanıcı adıyla engellenenler + maçta engellenen (kullanıcı adı olmayan) oyuncular
	var list: Array = []
	if account:
		for hnd in account.engeller:
			list.append({"ad": "@" + str(hnd), "anahtar": str(hnd), "kaldir": {"t": "engel_kaldir", "handle": str(hnd)}})
		for mi in account.engeller_misafir:
			list.append({"ad": str(mi.get("ad", "?")), "anahtar": str(mi.get("ad", "?")), "kaldir": {"t": "engel_kaldir", "k": int(mi.get("k", 0))}})
	if list.is_empty():
		var bos := E.row_box(Color(0, 0, 0, 0), Vector4(16, 14, 16, 14))
		var bl := UI.label("Kimseyi engellemedin.", UI.FS_KUCUK, UI.METIN_SOLUK)
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bos.add_child(bl)
		_engel_kutu.add_child(bos)
		return
	for it in list:
		var h := str(it.anahtar)
		var kaldir_msg: Dictionary = it.kaldir
		var box := E.row_box(Color(0, 0, 0, 0), Vector4(12, 6, 10, 6))
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", UI.B_S)
		box.add_child(r)
		var av := E.avatar(h, h, 46)
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(av)
		var n := UI.title(str(it.ad), 20, UI.METIN)
		n.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(n)
		var kaldir := UI.button("KALDIR", "ikincil", UI.DOKUNMA, 18, "", 140)
		kaldir.pressed.connect(func() -> void:
			kaldir.disabled = true
			account.send(kaldir_msg))
		r.add_child(kaldir)
		_engel_kutu.add_child(box)


func _link_btn(path: String) -> Button:
	var b := UI.button("AÇ", "ikincil", UI.DOKUNMA, 20, "", 130)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	# sayfada önce Türkçe, sonra İngilizce bölüm (#en) var: oyunun diline göre açılır
	b.pressed.connect(func() -> void: OS.shell_open(_web_base() + path + Dil.yasal_ek()))
	return b


# Sunucunun web adresi: wss://alan -> https://alan
func _web_base() -> String:
	var u: String = account.server_url if account else ""
	return u.replace("wss://", "https://").replace("ws://", "http://").trim_suffix("/")


func _confirm_delete() -> void:
	var m := UI.modal("HESABI SİL", 640)
	var ic := UI.icon("kapat", 72)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	m.body.add_child(ic)
	var l := UI.label("Kullanıcı adın, şifren, karakterin, elmasların, eşyaların, ilerlemen ve arkadaşlıkların kalıcı olarak silinir.", UI.FS_METIN, UI.METIN, true)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m.body.add_child(l)
	m.body.add_child(UI.title("Bu işlem geri alınamaz.", UI.FS_ORTA, UI.KIRMIZI.lightened(0.25), true))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.B_S)
	var vaz := UI.button("VAZGEÇ", "ikincil", UI.BTN_H, UI.FS_ORTA, "")
	vaz.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vaz.pressed.connect(m.close)
	h.add_child(vaz)
	var sil := UI.button("SİL", "tehlike", UI.BTN_H, UI.FS_ORTA, "kapat")
	sil.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sil.pressed.connect(func() -> void:
		if not account or not account.connected:
			UI.toast("Sunucuya bağlı değilsin, internetini kontrol et.", null, 2.4, "hata")
			return
		sil.disabled = true
		vaz.disabled = true
		m.perde_kapatir = false
		UI.set_button_text(sil, "SİLİNİYOR…")
		account.account_deleted.connect(_after_delete, CONNECT_ONE_SHOT)
		account.send({"t": "hesap_sil"})
		# cevap gelmezse de 4 sn sonra yerel kayıt sıfırlanır
		get_tree().create_timer(4.0).timeout.connect(_after_delete))
	h.add_child(sil)
	m.body.add_child(h)
	_kok.add_child(m)


var _silindi := false


# Hesap silindi: cihazın anahtarı yenilenir, yerel profil sıfırlanır ve oyun baştan açılır.
func _after_delete() -> void:
	if _silindi:
		return
	_silindi = true
	profile.token = Crypto.new().generate_random_bytes(16).hex_encode()
	profile.player_name = ""
	profile.hesap_adi = ""  # hesap yok: açılışta kayıt ekranı
	profile.owned = []
	profile.last_daily = ""
	profile.look = preload("res://scripts/catalog.gd").random_look()
	profile.settings.giris_soruldu = false
	profile.save()
	UI.toast("Hesabın silindi", null, 2.0, "basari")
	get_tree().reload_current_scene()


# ---------------------------------------------------------------------
# Denetimler
# ---------------------------------------------------------------------

# Bir ayar satırı (tam ayarlar): solda başlık + (varsa) kısa açıklama, sağda denetim
func _row(title: String, hint: String, control: Control) -> void:
	var box := E.row_box(Color(0, 0, 0, 0), Vector4(18, 8, 14, 8))
	box.custom_minimum_size.y = 80 if hint != "" else 76
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", UI.B_M)
	box.add_child(r)
	var tv := VBoxContainer.new()
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_stretch_ratio = 0.9
	tv.add_theme_constant_override("separation", 0)
	tv.add_child(UI.title(title, 21, UI.METIN))
	if hint != "":
		var hl := UI.label(hint, UI.FS_KUCUK, UI.METIN_SOLUK)
		hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(hl)
	r.add_child(tv)
	if control is Button:
		control.size_flags_horizontal = Control.SIZE_SHRINK_END
	elif not (control is ESwitch):
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(control)
	_icerik.add_child(box)


const ESwitch := preload("res://scripts/ekran.gd").Anahtar


# Kaydırıcı + yanında değer; fmt'deki %d değeri (v * mult) ile yazılır. Değer anında kaydedilir ve uygulanır.
func _slider(min_v: float, max_v: float, key: String, fmt: String, mult := 100.0, step := 0.05, on_change := Callable()) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UI.B_S)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = float(profile.settings.get(key, min_v))
	s.custom_minimum_size = Vector2(200, UI.DOKUNMA)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	E.style_slider(s)
	var val := UI.title(fmt % (s.value * mult), 22, UI.AMBER)
	val.custom_minimum_size.x = 76
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	s.value_changed.connect(func(v: float) -> void:
		val.text = fmt % (v * mult)
		profile.settings[key] = v
		profile.save()
		_uygula(key, v)
		if on_change.is_valid():
			on_change.call(v))
	row.add_child(s)
	row.add_child(val)
	return row


# Yan yana seçenek düğmeleri; seçili olan amber.
func _choice(options: Array, current: int, on_pick: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.B_XS)
	var btns: Array = []
	for i in options.size():
		var b := UI.button(options[i], "ana" if i == current else "ikincil", UI.DOKUNMA, 18)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(b.get_meta("row") as Control).offset_left = 12
		(b.get_meta("row") as Control).offset_right = -12
		btns.append(b)
		h.add_child(b)
	for i in btns.size():
		(btns[i] as Button).pressed.connect(func() -> void:
			for k in btns.size():
				UI.set_button_kind(btns[k], "ana" if k == i else "ikincil")
			on_pick.call(i))
	return h


# Aç/kapa anahtarı; varsayilan: kayıtta anahtar yoksa ne gösterilsin
func _switch(key: String, varsayilan := false, on_change := Callable()) -> Control:
	return E.switch(bool(profile.settings.get(key, varsayilan)), func(on: bool) -> void:
		profile.settings[key] = on
		profile.save()
		if on_change.is_valid():
			on_change.call(on))


func _process(_delta: float) -> void:
	if _mic_bar and is_instance_valid(_mic_bar) and voice and voice.testing:
		_mic_bar.value = voice.level


func _play_ring(kind: int) -> void:
	_preview.stream = Sfx.ring(kind)
	_preview.play()
	get_tree().create_timer(1.6).timeout.connect(func() -> void:
		if is_instance_valid(_preview):
			_preview.stop())


func _toggle_mic() -> void:
	if not voice:
		return
	if voice.testing:
		voice.stop_test()
		UI.set_button_text(_mic_btn, "TEST ET")
		_mic_bar.value = 0.0
	else:
		voice.start_test()
		UI.set_button_text(_mic_btn, "DURDUR")


func _open_login(ekran := "") -> void:
	var g: CanvasLayer = load("res://scripts/giris.gd").new()
	g.account = account
	g.profile = profile
	g.ilk_ekran = ekran
	g.closed.connect(_build)
	add_child(g)


func _close() -> void:
	if _kapaniyor:
		return
	_kapaniyor = true
	if voice and voice.testing:
		voice.stop_test()
	_save_name()
	if oyun_ici() and _panel:
		# panel sağa kayarak çekilir
		var tw := _kok.create_tween().set_parallel(true)
		tw.tween_property(_panel, "offset_left", -PANEL_W + 70.0, 0.16)
		tw.tween_property(_panel, "offset_right", 70.0, 0.16)
	E.outro(_kok, func() -> void:
		closed.emit()
		queue_free())


# Oyundaki ad kullanıcı adıdır: ayarlardan ad değiştirilmez (eski çağrılar için boş bırakıldı).
func _save_name() -> void:
	pass


# Statik: ekran kapansa da cevap gelince ad kaydedilsin (örnek yöntemine bağlı lambda ekranla birlikte geçersiz olur)
static func _ad_sonucu(prof: Node, alan: LineEdit, n: String) -> Callable:
	return func(uygun: bool) -> void:
		if not uygun:
			UI.toast("Bu ad kullanılamaz", null, 2.4, "hata")
			if is_instance_valid(alan) and alan.text.strip_edges() == n:
				alan.text = prof.player_name
			return
		if is_instance_valid(prof) and prof.player_name != n:
			prof.player_name = n
			prof.save()
