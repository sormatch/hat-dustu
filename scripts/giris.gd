# Hesap ekranı: Kayıt ol (kullanıcı adı + şifre) / Giriş yap / Misafir devam et.
# Hesaplı oyuncunun görünüşü, elmasları ve aldıkları sunucuda saklanır; başka telefondan giriş yapınca geri gelir.
extends CanvasLayer

signal closed

const UI := preload("res://scripts/ui.gd")

var account: Node
var profile: Node
var _signup := true
var _body: VBoxContainer
var _msg: Label
var _tabs: HBoxContainer
var _user: LineEdit
var _pass: LineEdit
var _pass2: LineEdit
var _go: Button


func _ready() -> void:
	layer = 18
	add_child(UI.background("bg_menu", 0.6))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UI.panel(Vector2(620, 0), 34)
	center.add_child(panel)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 12)
	panel.add_child(_body)
	account.me_changed.connect(_on_me)
	account.message.connect(_on_message)
	_build()


func _build() -> void:
	for c in _body.get_children():
		c.queue_free()
	if account.has_account:
		_build_signed_in()
		return
	_body.add_child(UI.header("HESABIN", 30))
	_tabs = HBoxContainer.new()
	_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	_tabs.add_theme_constant_override("separation", 10)
	for i in 2:
		var on := (i == 0) == _signup
		var t := UI.tab("KAYIT OL" if i == 0 else "GİRİŞ YAP", on, "friends" if i == 0 else "play")
		t.custom_minimum_size.x = 250
		t.pressed.connect(func() -> void:
			_signup = i == 0
			_build())
		_tabs.add_child(t)
	_body.add_child(_tabs)
	_body.add_child(UI.label("Hesabın olursa karakterin, elmasların ve aldıkların kaybolmaz; başka telefondan da girersin." if _signup
		else "Daha önce açtığın hesabın kullanıcı adı ve şifresi.", 16, Color(0.78, 0.8, 0.88), true))
	_user = _edit("@kullanıcıadı", false)
	if account.handle != "":
		_user.text = account.handle
	_body.add_child(_user)
	_pass = _edit("Şifre (en az 6 karakter)" if _signup else "Şifre", true)
	_body.add_child(_pass)
	if _signup:
		_pass2 = _edit("Şifre tekrar", true)
		_body.add_child(_pass2)
		_pass2.text_submitted.connect(func(_t: String) -> void: _submit())
	else:
		_pass.text_submitted.connect(func(_t: String) -> void: _submit())
	_msg = UI.label("", 17, Color("#ff9a8a"), true)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_msg)
	if not account.connected:
		_msg.text = "Sunucuya bağlanılıyor…"
	_go = UI.button("HESAP AÇ" if _signup else "GİRİŞ YAP", "primary", 66, 24, "play")
	_go.pressed.connect(_submit)
	_body.add_child(_go)
	var guest := UI.button("MİSAFİR OLARAK DEVAM ET", "normal", 52, 18)
	guest.pressed.connect(_close)
	_body.add_child(guest)


func _build_signed_in() -> void:
	_body.add_child(UI.header("HESABIN", 30))
	_body.add_child(UI.title("@" + account.handle, 34, Color("#ffcf8a"), true))
	_body.add_child(UI.label("Karakterin, elmasların ve aldıkların bu hesapta saklanıyor.", 17, Color(0.78, 0.8, 0.88), true))
	_msg = UI.label("", 17, Color("#5be37d"), true)
	_body.add_child(_msg)
	var ok := UI.button("TAMAM", "primary", 62, 22)
	ok.pressed.connect(_close)
	_body.add_child(ok)
	var out := UI.button("ÇIKIŞ YAP", "red", 52, 18)
	out.pressed.connect(func() -> void:
		account.sign_out()
		_build())
	_body.add_child(out)


func _edit(placeholder: String, secret: bool) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.secret = secret
	e.max_length = 17 if not secret else 64
	e.custom_minimum_size = Vector2(0, 56)
	UI.style_edit(e, 22)
	return e


func _submit() -> void:
	var h := _user.text.strip_edges().trim_prefix("@").to_lower()
	if h.length() < 3:
		_msg.text = "Kullanıcı adını yaz."
		return
	if _pass.text.length() < 6:
		_msg.text = "Şifre en az 6 karakter olmalı."
		return
	if _signup and _pass.text != _pass2.text:
		_msg.text = "Şifreler aynı değil."
		return
	if not account.connected:
		_msg.text = "Sunucuya bağlanılamadı, internetini kontrol et."
		return
	_msg.add_theme_color_override("font_color", Color(0.8, 0.82, 0.9))
	_msg.text = "Bekle…"
	if _signup:
		account.sign_up(h, _pass.text, profile.player_name)
	else:
		account.sign_in(h, _pass.text)


func _on_me() -> void:
	if not account.has_account and is_instance_valid(_msg) and _msg.text.begins_with("Sunucuya"):
		_msg.text = ""
	if account.has_account:
		_build()
		_msg.text = "Hoş geldin!"


func _on_message(m: String) -> void:
	if is_instance_valid(_msg):
		_msg.add_theme_color_override("font_color", Color("#ff9a8a"))
		_msg.text = m


func _close() -> void:
	profile.settings.giris_soruldu = true
	profile.save()
	closed.emit()
	queue_free()
