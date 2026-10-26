# Hesap ekranı: Kayıt ol (kullanıcı adı + şifre) / Giriş yap / Misafir devam et.
# Solda logo ve hesabın faydaları, sağda form paneli. Hesaplı oyuncunun görünüşü, elmasları ve aldıkları
# sunucuda saklanır; başka telefondan giriş yapınca geri gelir.
extends CanvasLayer

signal closed

const UI := preload("res://scripts/ui.gd")
const E := preload("res://scripts/ekran.gd")
const Account := preload("res://scripts/account.gd")
const Dil := preload("res://scripts/dil.gd")

var account: Node
var profile: Node
var _signup := true
var _kok: Control
var _body: VBoxContainer
var _msg: Label
var _don: Control  # bekleme göstergesi (durum satırında)
var _tabs: HBoxContainer
var _user: LineEdit
var _pass: LineEdit
var _pass2: LineEdit
var _go: Button
var _cols: HBoxContainer
var _kaydir := 0.0  # klavye açıkken form yukarı kayar (px)
var _klavye_test := 0.0  # test: -- klavye=<px> klavye açıkmış gibi davranır (ekran görüntüsü için)
var _bekliyor := 0  # cevap beklenen gönderimin sırası (zaman aşımı için)


func _ready() -> void:
	layer = 18
	_kok = Control.new()
	_kok.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_kok)
	_kok.add_child(UI.background("bg_menu", 0.55))
	_kok.add_child(E.vignette(0.2, 0.92))
	var cols := HBoxContainer.new()
	_cols = cols
	cols.set_anchors_preset(Control.PRESET_FULL_RECT)
	cols.offset_left = 40
	cols.offset_right = -40
	cols.offset_top = 24
	cols.offset_bottom = -24
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.add_theme_constant_override("separation", 48)
	_kok.add_child(cols)
	UI.guvenli(cols)  # çentikli telefonda form kenara girmesin
	UI.geri_tusu(_kok, _close)  # Android geri tuşu / Esc: misafir olarak devam
	# sol: logo + faydalar
	var sol := VBoxContainer.new()
	sol.alignment = BoxContainer.ALIGNMENT_CENTER
	sol.custom_minimum_size.x = 520
	sol.add_theme_constant_override("separation", UI.B_M)
	cols.add_child(sol)
	var logo := TextureRect.new()
	logo.texture = UI.texture("logo", 440)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(520, 250)
	sol.add_child(logo)
	for f in [["envanter", "Karakterin ve eşyaların kaybolmaz"], ["elmas", "Elmasların ve ilerlemen saklanır"], ["telefon", "Başka telefondan da girersin"]]:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", UI.B_M)
		var ik := PanelContainer.new()
		var ist := StyleBoxFlat.new()
		ist.bg_color = Color(0, 0, 0, 0.55)
		ist.border_color = Color(UI.AMBER, 0.55)
		ist.set_border_width_all(2)
		ist.set_corner_radius_all(UI.R_ORTA)
		ist.content_margin_left = 6
		ist.content_margin_right = 6
		ist.content_margin_top = 6
		ist.content_margin_bottom = 6
		ik.add_theme_stylebox_override("panel", ist)
		ik.add_child(UI.icon(f[0], 44))
		r.add_child(ik)
		var l := UI.title(f[1], 22, UI.METIN)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		r.add_child(l)
		sol.add_child(r)
	# sağ: form
	var cc := CenterContainer.new()
	cols.add_child(cc)
	var panel := UI.panel(Vector2(580, 0), 30)
	cc.add_child(panel)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", UI.B_S)
	panel.add_child(_body)
	account.me_changed.connect(_on_me)
	account.message.connect(_on_message)
	_build()
	E.intro(_kok, null)
	E.stagger(sol, 0.08)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("klavye="):
			_klavye_test = float(a.substr(7))
			(func() -> void:
				if is_instance_valid(_pass2):
					_pass2.grab_focus()
				elif is_instance_valid(_pass):
					_pass.grab_focus()).call_deferred()


# Telefonda klavye açılınca odaktaki alan ve altındaki düğme klavyenin üstünde kalsın: form yukarı kayar.
func _process(delta: float) -> void:
	if not is_instance_valid(_cols):
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
		var alt := r.end.y + _kaydir + UI.B_S
		if is_instance_valid(_go) and _go.visible:
			alt = maxf(alt, _go.get_global_rect().end.y + _kaydir)  # mümkünse ana düğme de görünsün
		hedef = maxf(0.0, alt - (vis.y - kh - UI.B_S))
		hedef = minf(hedef, maxf(0.0, ust - UI.B_S))  # odaktaki alan ekranın üstünden taşmasın
	_kaydir = lerpf(_kaydir, hedef, minf(1.0, delta * 14.0)) if absf(_kaydir - hedef) > 0.5 else hedef
	_cols.offset_top = 24 - _kaydir
	_cols.offset_bottom = -24 - _kaydir


func _build() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	if account.has_account:
		_build_signed_in()
		return
	_body.add_child(UI.header("HESABIN", 30))
	_tabs = HBoxContainer.new()
	_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	_tabs.add_theme_constant_override("separation", UI.B_S)
	for i in 2:
		var on := (i == 0) == _signup
		var t := UI.tab("KAYIT OL" if i == 0 else "GİRİŞ YAP", on, "arkadas" if i == 0 else "oyna")
		t.custom_minimum_size.x = 250
		t.pressed.connect(func() -> void:
			if _signup != (i == 0):
				_signup = i == 0
				_build())
		_tabs.add_child(t)
	_body.add_child(_tabs)
	_user = _edit("Kullanıcı adı (ör. ali_34)", false)
	if account.handle != "":
		_user.text = account.handle
	_body.add_child(_user)
	_pass = _edit("Şifre (en az 6 karakter)" if _signup else "Şifre", true)
	_body.add_child(_pass)
	_user.text_submitted.connect(func(_t: String) -> void: _pass.grab_focus())
	if _signup:
		_pass2 = _edit("Şifre tekrar", true)
		_body.add_child(_pass2)
		_pass.text_submitted.connect(func(_t: String) -> void: _pass2.grab_focus())
		_pass2.text_submitted.connect(func(_t: String) -> void: _submit())
		# yazarken kural hatası hemen söylenir (Türkçe harf, boşluk, geçersiz işaret)
		_user.text_changed.connect(func(t: String) -> void:
			var he := Account.handle_error(Account.clean_handle(t))
			if he != "" and not he.contains("en az") and not he.contains("yaz."):
				_hata(he, false)
			elif is_instance_valid(_msg) and _msg.text.begins_with("Kullanıcı adında"):
				_msg.text = "")
	else:
		_pass2 = null
		_pass.text_submitted.connect(func(_t: String) -> void: _submit())
	if not _signup:
		# misafirken başka hesaba girilirse bu telefondaki misafir ilerlemesi o hesaba geçmez
		var uyari := HBoxContainer.new()
		uyari.add_theme_constant_override("separation", UI.B_XS)
		var ui_ik := UI.icon("kilit", 26)
		ui_ik.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		uyari.add_child(ui_ik)
		var ul := UI.label("Misafir ilerlemen bu hesaba taşınmaz.", UI.FS_KUCUK + 1, UI.AMBER, false)
		ul.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ul.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		uyari.add_child(ul)
		_body.add_child(uyari)
	# durum satırı: beklerken dönen gösterge + amber yazı, hatada kırmızı yazı
	var mr := HBoxContainer.new()
	mr.alignment = BoxContainer.ALIGNMENT_CENTER
	mr.add_theme_constant_override("separation", UI.B_XS)
	_don = E.spinner(22)
	_don.visible = false
	mr.add_child(_don)
	_msg = UI.label("", UI.FS_KUCUK + 1, UI.KIRMIZI.lightened(0.35), true)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.custom_minimum_size.y = 24
	_msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mr.add_child(_msg)
	_body.add_child(mr)
	if not account.connected:
		_bekle_yaz("Sunucuya bağlanılıyor…")
	_go = UI.button("HESAP AÇ" if _signup else "GİRİŞ YAP", "ana", UI.BTN_H, UI.FS_BUYUK - 4, "oyna")
	_go.pressed.connect(_submit)
	_body.add_child(_go)
	var guest := UI.button("MİSAFİR OLARAK DEVAM ET", "ikincil", UI.DOKUNMA, 20)
	guest.pressed.connect(_close)
	_body.add_child(guest)


func _build_signed_in() -> void:
	_body.add_child(UI.header("HESABIN", 30))
	var r := HBoxContainer.new()
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	r.add_theme_constant_override("separation", UI.B_M)
	var av := E.avatar(profile.player_name if profile.player_name != "" else account.handle, account.handle, 88, "acik")
	r.add_child(av)
	var tv := VBoxContainer.new()
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_theme_constant_override("separation", 0)
	tv.add_child(UI.title(profile.player_name if profile.player_name != "" else account.handle, UI.FS_BUYUK, UI.METIN))
	tv.add_child(UI.title("@" + account.handle, UI.FS_METIN, UI.AMBER))
	r.add_child(tv)
	_body.add_child(r)
	var info := E.row_box(UI.YESIL, Vector4(16, 10, 16, 10))
	var il := UI.label("Karakterin, elmasların ve aldıkların bu hesapta güvende.", UI.FS_METIN - 2, UI.METIN, true)
	il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(il)
	_body.add_child(info)
	_msg = UI.label("", UI.FS_KUCUK + 1, UI.YESIL, true)
	_body.add_child(_msg)
	var ok := UI.button("TAMAM", "ana", UI.BTN_H, UI.FS_BUYUK - 4)
	ok.pressed.connect(_close)
	_body.add_child(ok)
	var out := UI.button("ÇIKIŞ YAP", "ikincil", UI.DOKUNMA, 20, "geri")
	out.pressed.connect(func() -> void: cikis_onayi(_kok, account, _build))
	_body.add_child(out)
	if OS.get_cmdline_user_args().has("cikis_onay=1"):
		out.pressed.emit.call_deferred()  # test pozu


# Çıkış onayı (hesap ekranı ve ayarlar): hesap sunucuda kalır, tekrar giriş yapılabilir.
static func cikis_onayi(host: Node, acc: Node, bitti := Callable()) -> Control:
	var m := UI.modal("ÇIKIŞ YAP", 600)
	var l := UI.label(Dil.t("@%s hesabından çıkılsın mı?") % str(acc.handle), UI.FS_ORTA, UI.METIN, true)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m.body.add_child(l)
	var l2 := UI.label("Karakterin ve elmasların hesapta kalır. İstediğin zaman tekrar giriş yapabilirsin.", UI.FS_METIN, UI.METIN_SOLUK, true)
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
		["engelle", "Taciz, tehdit ve kötü davranış yasak; kuralı bozan hesap kapatılabilir."],
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


func _edit(placeholder: String, secret: bool) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.secret = secret
	e.max_length = 17 if not secret else 64
	e.custom_minimum_size = Vector2(0, UI.DOKUNMA)
	e.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD if secret else LineEdit.KEYBOARD_TYPE_DEFAULT
	UI.style_edit(e, 24)
	return e


func _submit() -> void:
	if _go.disabled:
		return  # cevap bekleniyor
	var h := Account.clean_handle(_user.text)
	if _signup:
		var he := Account.handle_error(h)
		if he != "":
			_hata(he)
			_user.grab_focus()
			return
	elif h == "":
		_hata("Kullanıcı adını yaz.")
		_user.grab_focus()
		return
	if _pass.text == "":
		_hata("Şifreni yaz.")
		_pass.grab_focus()
		return
	if _signup and _pass.text.length() < 6:
		_hata("Şifre en az 6 karakter olmalı.")
		_pass.grab_focus()
		return
	if _signup and _pass.text != _pass2.text:
		_hata("Şifreler aynı değil.")
		_pass2.grab_focus()
		return
	if not account.connected:
		_hata("Sunucuya bağlanılamadı. İnternetini kontrol et.")
		return
	_bekle_yaz("Bekle…")
	_go.disabled = true
	_bekliyor += 1
	var sira := _bekliyor
	get_viewport().gui_release_focus()  # klavye kapansın
	get_tree().create_timer(8.0).timeout.connect(func() -> void:
		if sira == _bekliyor and is_instance_valid(_go) and _go.disabled:
			_go.disabled = false
			_hata("Cevap gelmedi. İnternetini kontrol edip tekrar dene."))
	if _signup:
		account.sign_up(h, _pass.text, profile.player_name)
	else:
		account.sign_in(h, _pass.text)


# Bekleme yazısı: amber, yanında dönen gösterge
func _bekle_yaz(m: String) -> void:
	if not is_instance_valid(_msg):
		return
	_msg.add_theme_color_override("font_color", UI.AMBER)
	_msg.text = m
	if is_instance_valid(_don):
		# kısa bekleme yazısı göstergeyle birlikte ortada durur
		_don.visible = true
		_msg.autowrap_mode = TextServer.AUTOWRAP_OFF
		_msg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _don_kapat() -> void:
	if is_instance_valid(_don):
		_don.visible = false
	if is_instance_valid(_msg):
		_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL


# Hata yazısı + panel hafifçe sallanır
func _hata(m: String, salla := true) -> void:
	if not is_instance_valid(_msg):
		return
	_don_kapat()
	_msg.add_theme_color_override("font_color", UI.KIRMIZI.lightened(0.35))
	_msg.text = m
	if not salla:
		return
	var p := _body.get_parent() as Control
	var x0 := p.position.x
	var tw := p.create_tween()
	for k in [10.0, -8.0, 5.0, 0.0]:
		tw.tween_property(p, "position:x", x0 + k, 0.05)


func _on_me() -> void:
	if not account.has_account and is_instance_valid(_msg) and _msg.text.begins_with("Sunucuya"):
		_msg.text = ""
		_don_kapat()
	if account.has_account:
		_bekliyor += 1  # bekleyen zaman aşımı iptal
		_build()
		_msg.text = tr("Hoş geldin, @%s!") % account.handle


# Sunucudan gelen yazı: hata kırmızı ve sallanır, bilgi (ör. "Hesabın açıldı") yeşil.
func _on_message(m: String) -> void:
	if not is_instance_valid(_msg):
		return
	_don_kapat()
	if not bool(account.get("son_hata")):
		_msg.add_theme_color_override("font_color", UI.YESIL)
		_msg.text = m
		return
	_bekliyor += 1
	if is_instance_valid(_go):
		_go.disabled = false
	_hata(m)


func _close() -> void:
	profile.settings.giris_soruldu = true
	profile.save()
	E.outro(_kok, func() -> void:
		closed.emit()
		queue_free())
