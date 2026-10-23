# Oyun içi ayarlar: ad, bakış hassasiyeti, ses seviyeleri, grafik kalitesi, joystick türü.
extends CanvasLayer

signal closed
signal open_character
signal leave_room

const CharacterScript := preload("res://scripts/character.gd")

var profile: Node
var _name: LineEdit


func _label(text: String, size := 22, color := Color(0.92, 0.92, 0.94)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _slider(min_v: float, max_v: float, value: float, key: String) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(260, 44)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(v: float) -> void:
		profile.settings[key] = v
		profile.save())
	return s


func _row(parent: Control, title: String, control: Control) -> void:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 12)
	var l := _label(title)
	l.custom_minimum_size.x = 210
	r.add_child(l)
	r.add_child(control)
	parent.add_child(r)


func _ready() -> void:
	layer = 15
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#15161b")
	st.border_color = Color(1, 1, 1, 0.15)
	st.set_border_width_all(2)
	st.set_corner_radius_all(20)
	st.content_margin_left = 26
	st.content_margin_right = 26
	st.content_margin_top = 20
	st.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", st)
	center.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 12)
	scroll.add_child(col)

	col.add_child(_label("Ayarlar", 32, Color("#FF4B3E")))
	_name = LineEdit.new()
	_name.text = profile.player_name
	_name.max_length = 16
	_name.placeholder_text = "Adını yaz"
	_name.custom_minimum_size = Vector2(0, 50)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.add_theme_font_size_override("font_size", 22)
	_row(col, "Adın", _name)
	_row(col, "Bakış hassasiyeti", _slider(0.4, 2.0, profile.settings.hassasiyet, "hassasiyet"))
	_row(col, "Oyun sesi", _slider(0.0, 1.0, profile.settings.oyun_ses, "oyun_ses"))
	_row(col, "Konuşma sesi", _slider(0.0, 1.5, profile.settings.konusma_ses, "konusma_ses"))

	var q := HBoxContainer.new()
	q.add_theme_constant_override("separation", 8)
	for i in 2:
		var b := CharacterScript.styled_button(["Düşük (pil dostu)", "Yüksek"][i], profile.settings.kalite == i, 20, 50)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			profile.settings.kalite = i
			profile.save()
			for j in q.get_child_count():
				var other: Button = q.get_child(j)
				var s2 := StyleBoxFlat.new()
				s2.bg_color = Color("#B3141B") if j == i else Color(1, 1, 1, 0.07)
				s2.border_color = Color("#FF5A52") if j == i else Color(1, 1, 1, 0.3)
				s2.set_border_width_all(2)
				s2.set_corner_radius_all(14)
				for k in ["normal", "hover", "pressed", "focus"]:
					other.add_theme_stylebox_override(k, s2))
		q.add_child(b)
	q.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row(col, "Grafik", q)

	var joy := CheckButton.new()
	joy.text = "Parmağın değdiği yerde aç"
	joy.button_pressed = profile.settings.yuzen_joy
	joy.add_theme_font_size_override("font_size", 20)
	joy.toggled.connect(func(on: bool) -> void:
		profile.settings.yuzen_joy = on
		profile.save())
	_row(col, "Joystick", joy)

	var chr := CharacterScript.styled_button("Karakterim & Mağaza", true, 22, 56)
	chr.pressed.connect(func() -> void:
		_save_name()
		open_character.emit())
	col.add_child(chr)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	var leave := CharacterScript.styled_button("Ana menüye dön", false, 20, 56)
	leave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leave.pressed.connect(func() -> void: leave_room.emit())
	bottom.add_child(leave)
	var close := CharacterScript.styled_button("Kapat", true, 22, 56)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(func() -> void:
		_save_name()
		closed.emit()
		queue_free())
	bottom.add_child(close)
	col.add_child(bottom)
	col.add_child(_label("Karakter modelleri ve dokular: Poly Haven (CC0). Hat Düştü © 2026", 16, Color(0.6, 0.6, 0.64)))


func _save_name() -> void:
	var n := _name.text.strip_edges()
	if n != "" and n != profile.player_name:
		profile.player_name = n
		profile.save()
