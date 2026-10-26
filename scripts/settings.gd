# Ayarlar ekranı: solda sekmeler (PROFİL / SES / GÖRÜNTÜ / KONTROLLER / HESAP), sağda o sekmenin ayarları.
# Her değişiklik anında kaydedilir. HESAP: giriş/çıkış, engellenen oyuncular, gizlilik politikası, kullanım
# koşulları, hesabı silme (onaylı) ve sürüm numarası. Oyun sırasında açılırsa üstte ANA MENÜ düğmesi çıkar.
extends CanvasLayer

signal closed
signal open_character
signal leave_room

const UI := preload("res://scripts/ui.gd")
const E := preload("res://scripts/ekran.gd")
const Sfx := preload("res://scripts/sfx.gd")
const ThumbsScript := preload("res://scripts/thumbs.gd")
const RINGS := ["Klasik çan", "Eski telefon", "Modern"]
const SURUM := "0.1"  # export_presets.cfg -> version/name ile aynı tut
const SEKMELER := [["PROFİL", "profile"], ["SES", "ses"], ["GÖRÜNTÜ", "graphics"], ["KONTROLLER", "controls"], ["HESAP", "kilit"]]

var profile: Node
var account: Node
var voice: Node
var sekme := 0

var _kok: Control
var _tab_btns: Array = []
var _icerik: VBoxContainer
var _scroll: ScrollContainer
var _name: LineEdit
var _mic_bar: Control
var _mic_btn: Button
var _preview: AudioStreamPlayer
var _thumbs: Node
var _engel_kutu: VBoxContainer


func _ready() -> void:
	layer = 15
	_thumbs = ThumbsScript.new()
	add_child(_thumbs)
	_preview = AudioStreamPlayer.new()
	add_child(_preview)
	var s := E.screen("AYARLAR", "ayarlar", "bg_settings", 0.62)
	_kok = s.kok
	add_child(_kok)
	(s.geri as Button).pressed.connect(_close)
	# oyun/oda içindeyken ana menüye dönüş
	var m = get_tree().current_scene
	if m and bool(m.get("playing")):
		var leave := UI.button("ANA MENÜ", "tehlike", UI.DOKUNMA, 22, "geri", 230)
		leave.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		leave.pressed.connect(func() -> void: leave_room.emit())
		(s.bar_sag as HBoxContainer).add_child(leave)
	var govde: Control = s.govde
	var cols := HBoxContainer.new()
	cols.set_anchors_preset(Control.PRESET_FULL_RECT)
	cols.offset_left = 16
	cols.offset_right = -16
	cols.offset_bottom = -12
	cols.add_theme_constant_override("separation", UI.B_M)
	govde.add_child(cols)
	# sol: sekmeler
	var rail := UI.panel(Vector2(300, 0), 26)
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
	var ver := UI.label("Hat Düştü  ·  sürüm %s" % _surum(), UI.FS_KUCUK, UI.METIN_SOLUK, true)
	rv.add_child(ver)
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
	_build()
	E.intro(_kok, govde)


func _surum() -> String:
	var v := str(ProjectSettings.get_setting("application/config/version", ""))
	return v if v != "" else SURUM


func _sec(i: int) -> void:
	if i < 0 or i == sekme:
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
# Sekmeler
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
	v.add_child(UI.label("Oyunda görünen adın", UI.FS_KUCUK, UI.METIN_SOLUK))
	_name = LineEdit.new()
	_name.text = profile.player_name
	_name.max_length = 16
	_name.placeholder_text = "Adını yaz"
	_name.custom_minimum_size = Vector2(0, UI.DOKUNMA)
	UI.style_edit(_name, 24)
	_name.text_submitted.connect(func(_t: String) -> void: _save_name())
	_name.focus_exited.connect(_save_name)
	v.add_child(_name)
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", UI.B_S)
	var sv := int(account.eco.get("seviye", 1)) if account else 1
	var lv := E.level_shield(sv, 52)
	lv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_child(lv)
	var iv := VBoxContainer.new()
	iv.alignment = BoxContainer.ALIGNMENT_CENTER
	iv.add_theme_constant_override("separation", -2)
	iv.add_child(UI.title("SEVİYE %d" % sv, 20, UI.METIN))
	var handle: String = account.handle if account and account.handle != "" else ""
	iv.add_child(UI.label("@" + handle if handle != "" else "Misafir oyuncu", UI.FS_KUCUK, UI.AMBER if handle != "" else UI.METIN_SOLUK))
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
	if not (account and account.has_account):
		var not_l := UI.label("Hesap açarsan karakterin, elmasların ve aldıkların kaybolmaz.", UI.FS_KUCUK, UI.METIN_SOLUK, true)
		not_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_icerik.add_child(not_l)


# Profil istatistikleri: maç, galibiyet, kazanma oranı, açılan kasa (sunucudaki ekonomi.istatistik)
func _istatistik() -> Control:
	var st: Dictionary = account.eco.get("istatistik", {}) if account else {}
	var mac := int(st.get("mac", 0))
	var gal := int(st.get("galibiyet", 0))
	var g := HBoxContainer.new()
	g.add_theme_constant_override("separation", UI.B_S)
	var kartlar := [["oyna", "MAÇ", E.sayi(mac)], ["tac", "GALİBİYET", E.sayi(gal)],
		["liderlik", "KAZANMA", ("%%%d" % roundi(100.0 * gal / mac)) if mac > 0 else "—"], ["kasa", "KASA", E.sayi(int(st.get("kasa", 0)))]]
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
	_baslik("SES SEVİYELERİ")
	_row("Oyun sesi", "Adımlar, kapılar, zil", _slider(0.0, 1.0, "oyun_ses", "%d%%"))
	if not profile.settings.has("muzik_ses"):
		profile.settings["muzik_ses"] = 0.7
	_row("Müzik", "Menü ve oyun müzikleri", _slider(0.0, 1.0, "muzik_ses", "%d%%", 100.0, 0.05, func(v: float) -> void:
		var m = get_tree().current_scene.get("muzik")
		if m:
			m.set_volume(v)))
	_row("Konuşma sesi", "Karşı tarafın sesi", _slider(0.0, 1.5, "konusma_ses", "%d%%"))
	_baslik("TELEFON VE MİKROFON")
	_row("Zil sesi", "Dokun, dinle ve seç", _choice(RINGS, int(profile.settings.zil), func(i: int) -> void:
		profile.settings.zil = i
		profile.save()
		_play_ring(i)))
	var mic := HBoxContainer.new()
	mic.add_theme_constant_override("separation", UI.B_S)
	_mic_btn = UI.button("TEST ET", "ikincil", UI.DOKUNMA, 20, "mikrofon", 170)
	_mic_btn.pressed.connect(_toggle_mic)
	mic.add_child(_mic_btn)
	_mic_bar = UI.progress(0.0, 160, 30)
	_mic_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mic_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mic.add_child(_mic_bar)
	_row("Mikrofon testi", "Konuş: çubuk doluyorsa mikrofon çalışıyor", mic)
	_row("Bas-konuş", "Açıksa sesin sadece KONUŞ düğmesine basarken gider", _switch("bas_konus"))


func _build_goruntu() -> void:
	_baslik("GÖRÜNTÜ")
	_row("Grafik kalitesi", "Pil dostu: gölge ve parlama kapalı", _choice(["Pil dostu", "Yüksek", "Ultra"], int(profile.settings.kalite), func(i: int) -> void:
		profile.settings.kalite = i
		profile.save()))
	_row("Görüş açısı", "Geniş açı daha çok görür", _slider(60.0, 95.0, "fov", "%d°", 1.0, 1.0))
	_row("FPS göster", "Köşede saniyedeki kare sayısı", _switch("fps"))


func _build_kontroller() -> void:
	_baslik("KONTROLLER")
	_row("Bakış hassasiyeti", "Ekranı sürükleyince ne kadar hızlı dönersin", _slider(0.4, 2.0, "hassasiyet", "%d%%"))
	_row("Joystick", "Parmağın değdiği yerde mi açılsın?", _choice(["Değdiği yerde", "Sabit"], 0 if profile.settings.yuzen_joy else 1, func(i: int) -> void:
		profile.settings.yuzen_joy = i == 0
		profile.save()))
	_row("Titreşim", "Telefon çalınca titresin", _switch("titresim"))
	_row("Kafa sallanması", "Yürürken kamera hafifçe sallansın", _switch("bob"))


func _build_hesap() -> void:
	_baslik("HESAP")
	var has: bool = account != null and account.has_account
	var durum := HBoxContainer.new()
	durum.add_theme_constant_override("separation", UI.B_S)
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
		var gir := UI.button("GİRİŞ / KAYIT", "ikincil", UI.DOKUNMA, 20, "arkadas", 230)
		gir.pressed.connect(_open_login)
		durum.add_child(gir)
	_row("@" + account.handle if has else "Misafir", "Hesabın sunucuda saklanıyor" if has else "İlerlemen sadece bu telefonda", durum)

	_baslik("ENGELLENEN OYUNCULAR")
	_engel_kutu = VBoxContainer.new()
	_engel_kutu.add_theme_constant_override("separation", UI.B_XS)
	_icerik.add_child(_engel_kutu)
	_fill_blocks()
	if account:
		account.send({"t": "engeller"})

	_baslik("YASAL")
	_row("Gizlilik politikası", "Hangi verileri neden sakladığımız", _link_btn("/gizlilik"))
	_row("Kullanım koşulları", "Oyun kuralları ve davranış", _link_btn("/kosullar"))

	_baslik("TEHLİKELİ BÖLGE")
	var sil := UI.button("HESABI SİL", "tehlike", UI.DOKUNMA, 20, "kapat", 230)
	sil.pressed.connect(_confirm_delete)
	var sh := HBoxContainer.new()
	sh.alignment = BoxContainer.ALIGNMENT_END
	sh.add_child(sil)
	_row("Hesabı sil", "İlerlemen ve arkadaşların kalıcı olarak silinir", sh)
	var foot := UI.label("Hat Düştü  ·  sürüm %s\nSaç modelleri: MakeHuman (CC0) · Dokular: Poly Haven (CC0) · Animasyonlar: Mixamo · Yazı tipleri: Russo One, Rubik (OFL)" % _surum(), UI.FS_KUCUK, Color(UI.METIN_SOLUK, 0.8), true)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_icerik.add_child(foot)


func _fill_blocks() -> void:
	if _engel_kutu == null or not is_instance_valid(_engel_kutu):
		return
	for c in _engel_kutu.get_children():
		c.queue_free()
	var list: Array = account.engeller if account else []
	if list.is_empty():
		var bos := E.row_box(Color(0, 0, 0, 0), Vector4(16, 14, 16, 14))
		var bl := UI.label("Kimseyi engellemedin. Maçta rahatsız eden oyuncuyu oyuncu listesinden engelleyebilirsin.", UI.FS_KUCUK, UI.METIN_SOLUK)
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bos.add_child(bl)
		_engel_kutu.add_child(bos)
		return
	for hnd in list:
		var h := str(hnd)
		var box := E.row_box(Color(0, 0, 0, 0), Vector4(12, 6, 10, 6))
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", UI.B_S)
		box.add_child(r)
		var av := E.avatar(h, h, 46)
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(av)
		var n := UI.title("@" + h, 20, UI.METIN)
		n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(n)
		var kaldir := UI.button("KALDIR", "ikincil", UI.DOKUNMA, 18, "", 140)
		kaldir.pressed.connect(func() -> void:
			kaldir.disabled = true
			account.send({"t": "engel_kaldir", "handle": h}))
		r.add_child(kaldir)
		_engel_kutu.add_child(box)


func _link_btn(path: String) -> Button:
	var b := UI.button("AÇ", "ikincil", UI.DOKUNMA, 20, "", 130)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.pressed.connect(func() -> void: OS.shell_open(_web_base() + path))
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

# Bir ayar satırı: solda başlık + açıklama, sağda denetim
func _row(title: String, hint: String, control: Control) -> void:
	var box := E.row_box(Color(0, 0, 0, 0), Vector4(18, 10, 14, 10))
	box.custom_minimum_size.y = 84
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


# Kaydırıcı + yanında değer; fmt'deki %d değeri (v * mult) ile yazılır.
func _slider(min_v: float, max_v: float, key: String, fmt: String, mult := 100.0, step := 0.05, on_change := Callable()) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UI.B_S)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = float(profile.settings.get(key, min_v))
	s.custom_minimum_size = Vector2(240, UI.DOKUNMA)
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


func _switch(key: String, on_change := Callable()) -> Control:
	return E.switch(bool(profile.settings.get(key, false)), func(on: bool) -> void:
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


func _open_login() -> void:
	_save_name()
	var g: CanvasLayer = load("res://scripts/giris.gd").new()
	g.account = account
	g.profile = profile
	g.closed.connect(_build)
	add_child(g)


func _close() -> void:
	if voice and voice.testing:
		voice.stop_test()
	_save_name()
	E.outro(_kok, func() -> void:
		closed.emit()
		queue_free())


func _save_name() -> void:
	if _name == null or not is_instance_valid(_name):
		return
	var n := _name.text.strip_edges()
	if n != "" and n != profile.player_name:
		profile.player_name = n
		profile.save()
