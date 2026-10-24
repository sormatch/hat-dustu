# Ayarlar: profil kartı (karakter resmi, ad, @kullanıcı adı, elmas), Kontroller, Ses (zil sesi seçip dinleme,
# canlı mikrofon testi, bas-konuş), Görüntü (görüş açısı, kalite, FPS). Her değişiklik anında kaydedilir.
extends CanvasLayer

signal closed
signal open_character
signal leave_room

const CharacterScript := preload("res://scripts/character.gd")
const UI := preload("res://scripts/ui.gd")
const Sfx := preload("res://scripts/sfx.gd")
const ThumbsScript := preload("res://scripts/thumbs.gd")
const ACCENT := Color("#ff7a1a")
const RINGS := ["Klasik çan", "Eski telefon", "Modern"]

var profile: Node
var account: Node
var voice: Node
var _name: LineEdit
var _mic_bar: ProgressBar
var _mic_btn: Button
var _preview: AudioStreamPlayer
var _thumbs: Node


func _slider_style(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color("#2d3248")
	track.set_corner_radius_all(6)
	track.content_margin_top = 7
	track.content_margin_bottom = 7
	var fill := track.duplicate()
	fill.bg_color = ACCENT
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)


# Kaydırıcı + yanında değer; fmt'deki %d değeri (v * mult) ile yazılır.
func _slider(min_v: float, max_v: float, key: String, fmt: String, mult := 100.0, step := 0.05, on_change := Callable()) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = float(profile.settings[key])
	s.custom_minimum_size = Vector2(220, 40)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider_style(s)
	var val := UI.title(fmt % (s.value * mult), 18, ACCENT.lightened(0.3))
	val.custom_minimum_size.x = 64
	s.value_changed.connect(func(v: float) -> void:
		val.text = fmt % (v * mult)
		profile.settings[key] = v
		profile.save()
		if on_change.is_valid():
			on_change.call(v))
	row.add_child(s)
	row.add_child(val)
	return row


# Yan yana seçenek butonları; seçili olan turuncu. Basınca yeniden boyanır.
func _choice(options: Array, current: int, on_pick: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	_fill_choice(h, options, current, on_pick)
	return h


func _fill_choice(h: HBoxContainer, options: Array, sel: int, on_pick: Callable) -> void:
	for ch in h.get_children():
		ch.queue_free()
	for i in options.size():
		var b := UI.button(options[i], "orange" if i == sel else "normal", 46, 16)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			on_pick.call(i)
			_fill_choice(h, options, i, on_pick))
		h.add_child(b)


func _toggle(key: String, on_change := Callable()) -> HBoxContainer:
	var h := _choice(["Açık", "Kapalı"], 0 if profile.settings[key] else 1, func(i: int) -> void:
		profile.settings[key] = i == 0
		profile.save()
		if on_change.is_valid():
			on_change.call(i == 0))
	return h


func _process(_delta: float) -> void:
	if _mic_bar and voice and voice.testing:
		_mic_bar.value = voice.level * 100.0


func _section(parent: Control, title: String, color: Color, icon: String) -> VBoxContainer:
	var card := PanelContainer.new()
	var cst := UI.flat(Color(0.05, 0.05, 0.07, 0.55), Color(color, 0.55), 14)
	cst.border_width_left = 6
	card.add_theme_stylebox_override("panel", cst)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(UI.icon(icon, 40))
	h.add_child(UI.title(title, 23, color))
	v.add_child(h)
	card.add_child(v)
	parent.add_child(card)
	return v


func _row(parent: Control, title: String, hint: String, control: Control) -> void:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 12)
	var tv := VBoxContainer.new()
	tv.custom_minimum_size.x = 210
	tv.add_theme_constant_override("separation", -2)
	tv.add_child(UI.label(title, 19, Color(0.9, 0.91, 0.95)))
	if hint != "":
		var hl := UI.label(hint, 13, Color(0.6, 0.62, 0.7))
		hl.autowrap_mode = TextServer.AUTOWRAP_WORD
		tv.add_child(hl)
	r.add_child(tv)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(control)
	parent.add_child(r)


func _ready() -> void:
	layer = 15
	_thumbs = ThumbsScript.new()
	add_child(_thumbs)
	_preview = AudioStreamPlayer.new()
	add_child(_preview)
	add_child(UI.background("bg_settings", 0.55))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UI.panel(Vector2.ZERO, 34)
	center.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	panel.add_child(outer)

	var head := HBoxContainer.new()
	var title := UI.title("AYARLAR", 34, ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_x := UI.button("KAPAT", "orange", 48, 18, "", 130)
	close_x.pressed.connect(_close)
	head.add_child(close_x)
	outer.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(760, 500)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 14)
	scroll.add_child(col)

	_profile_card(col)

	var c := _section(col, "Kontroller", Color("#3b9cff"), "controls")
	_row(c, "Bakış hassasiyeti", "Ekranı sürükleyince ne kadar hızlı dönersin", _slider(0.4, 2.0, "hassasiyet", "%d%%"))
	_row(c, "Joystick", "Parmağın değdiği yerde mi açılsın?", _choice(["Değdiği yerde", "Sabit"], 0 if profile.settings.yuzen_joy else 1, func(i: int) -> void:
		profile.settings.yuzen_joy = i == 0
		profile.save()))
	_row(c, "Titreşim", "Telefon çalınca titresin", _toggle("titresim"))
	_row(c, "Kafa sallanması", "Yürürken kamera hafifçe sallansın", _toggle("bob"))

	var a := _section(col, "Ses ve konuşma", Color("#5be37d"), "sound")
	_row(a, "Oyun sesi", "", _slider(0.0, 1.0, "oyun_ses", "%d%%"))
	_row(a, "Konuşma sesi", "Karşı tarafın sesi", _slider(0.0, 1.5, "konusma_ses", "%d%%"))
	var ring_row := HBoxContainer.new()
	ring_row.add_theme_constant_override("separation", 8)
	var rc := _choice(RINGS, int(profile.settings.zil), func(i: int) -> void:
		profile.settings.zil = i
		profile.save()
		_play_ring(i))
	rc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ring_row.add_child(rc)
	_row(a, "Zil sesi", "Dokun, dinle ve seç", ring_row)
	var mic := HBoxContainer.new()
	mic.add_theme_constant_override("separation", 10)
	_mic_btn = UI.button("TEST ET", "normal", 46, 16, "mic", 150)
	_mic_btn.pressed.connect(_toggle_mic)
	mic.add_child(_mic_btn)
	_mic_bar = ProgressBar.new()
	_mic_bar.show_percentage = false
	_mic_bar.custom_minimum_size = Vector2(160, 22)
	_mic_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mic_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#2d3248")
	bg.set_corner_radius_all(8)
	var fg := bg.duplicate()
	fg.bg_color = Color("#5be37d")
	_mic_bar.add_theme_stylebox_override("background", bg)
	_mic_bar.add_theme_stylebox_override("fill", fg)
	mic.add_child(_mic_bar)
	_row(a, "Mikrofon testi", "Konuş, çubuk doluyorsa mikrofon çalışıyor", mic)
	_row(a, "Bas-konuş", "Açıksa sadece KONUŞ düğmesine basarken sesin gider", _toggle("bas_konus"))

	var g := _section(col, "Görüntü", Color("#b05cff"), "graphics")
	_row(g, "Görüş açısı", "Geniş açı daha çok görür", _slider(60.0, 95.0, "fov", "%d°", 1.0, 1.0))
	_row(g, "Kalite", "Pil dostu: gölge ve parlama kapalı", _choice(["Pil dostu", "Yüksek"], int(profile.settings.kalite), func(i: int) -> void:
		profile.settings.kalite = i
		profile.save()))
	_row(g, "FPS göster", "Köşede saniyedeki kare sayısı", _toggle("fps"))

	var leave := UI.button("ANA MENÜYE DÖN", "red", 52, 20, "exit")
	leave.pressed.connect(func() -> void: leave_room.emit())
	col.add_child(leave)
	col.add_child(UI.label("Saç modelleri: MakeHuman (CC0) · Dokular: Poly Haven (CC0) · Animasyonlar: Mixamo · Yazı tipleri: Russo One, Rubik (OFL)", 13, Color(0.5, 0.52, 0.6)))


# Profil kartı: karakterin küçük resmi, adın, @kullanıcı adın, elmasların, karakteri düzenle.
func _profile_card(col: Control) -> void:
	var card := PanelContainer.new()
	var cst := UI.flat(Color(0.12, 0.08, 0.04, 0.7), Color("#ffb020"), 16)
	card.add_theme_stylebox_override("panel", cst)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	card.add_child(h)
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(120, 120)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(pic)
	_thumbs.request(profile.look, "aksesuar", str(profile.look.aksesuar), pic)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	_name = LineEdit.new()
	_name.text = profile.player_name
	_name.max_length = 16
	_name.placeholder_text = "Adını yaz"
	_name.custom_minimum_size = Vector2(0, 48)
	_name.add_theme_font_size_override("font_size", 22)
	v.add_child(_name)
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 8)
	var handle: String = account.handle if account and account.handle != "" else ""
	info.add_child(UI.title("@" + handle if handle != "" else "kullanıcı adı yok", 18, Color("#ffcf8a") if handle != "" else Color(0.6, 0.6, 0.65)))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(sp)
	info.add_child(UI.gem(26))
	info.add_child(UI.title(str(profile.gems), 20, Color("#a8f2ff")))
	v.add_child(info)
	var edit := UI.button("KARAKTERİ DÜZENLE", "orange", 50, 18, "store")
	edit.pressed.connect(func() -> void:
		_save_name()
		open_character.emit())
	v.add_child(edit)
	h.add_child(v)
	col.add_child(card)


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
		_mic_bar.value = 0
	else:
		voice.start_test()
		UI.set_button_text(_mic_btn, "DURDUR")


func _close() -> void:
	if voice and voice.testing:
		voice.stop_test()
	_save_name()
	closed.emit()
	queue_free()


func _save_name() -> void:
	var n := _name.text.strip_edges()
	if n != "" and n != profile.player_name:
		profile.player_name = n
		profile.save()
