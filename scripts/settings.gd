# Oyun içi ayarlar: bölümlere ayrılmış kartlar (Oyuncu, Kontroller, Ses, Grafik), renkli kaydırıcılar.
extends CanvasLayer

signal closed
signal open_character
signal leave_room

const CharacterScript := preload("res://scripts/character.gd")
const UI := preload("res://scripts/ui.gd")
const ACCENT := Color("#ff7a1a")

var profile: Node
var _name: LineEdit


func _label(text: String, size := 21, color := Color(0.93, 0.93, 0.96)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _slider_style(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color("#2d3248")
	track.set_corner_radius_all(6)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	var fill := track.duplicate()
	fill.bg_color = ACCENT
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)


func _slider(min_v: float, max_v: float, value: float, key: String, fmt: String) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(240, 40)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider_style(s)
	var val := _label(fmt % (value * 100), 18, ACCENT.lightened(0.3))
	val.custom_minimum_size.x = 60
	s.value_changed.connect(func(v: float) -> void:
		val.text = fmt % (v * 100)
		profile.settings[key] = v
		profile.save())
	row.add_child(s)
	row.add_child(val)
	return row


func _section(parent: Control, title: String, color: Color) -> VBoxContainer:
	var card := PanelContainer.new()
	var cst := UI.flat(Color(0.05, 0.05, 0.07, 0.55), Color(color, 0.5), 12)
	cst.border_width_top = 2
	cst.border_width_left = 5
	card.add_theme_stylebox_override("panel", cst)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(UI.icon({"Oyuncu": "profile", "Kontroller": "controls", "Ses": "sound", "Grafik": "graphics"}.get(title, "settings"), 40))
	h.add_child(UI.title(title, 22, color))
	v.add_child(h)
	card.add_child(v)
	parent.add_child(card)
	return v

func _row(parent: Control, title: String, control: Control) -> void:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 12)
	var l := _label(title, 19, Color(0.8, 0.82, 0.9))
	l.custom_minimum_size.x = 190
	r.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(control)
	parent.add_child(r)


func _choice(options: Array, current: int, on_pick: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	for i in options.size():
		var b := CharacterScript.styled_button(options[i], i == current, 18, 46)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			on_pick.call(i)
			for j in h.get_child_count():
				var nb := CharacterScript.styled_button("", j == i, 18, 46)
				for k in ["normal", "hover", "pressed", "focus"]:
					h.get_child(j).add_theme_stylebox_override(k, nb.get_theme_stylebox(k))
				nb.free())
		h.add_child(b)
	return h


func _ready() -> void:
	layer = 15
	add_child(UI.background("bg_settings", 0.55))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UI.panel(Vector2.ZERO, 34)
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#141626")
	st.border_color = Color("#2d3248")
	st.set_border_width_all(2)
	st.border_width_top = 6
	st.border_color = ACCENT
	st.set_corner_radius_all(24)
	st.content_margin_left = 22
	st.content_margin_right = 22
	st.content_margin_top = 16
	st.content_margin_bottom = 18
	st.shadow_color = Color(0, 0, 0, 0.5)
	st.shadow_size = 20
	center.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	panel.add_child(outer)

	var head := HBoxContainer.new()
	var title := UI.title("AYARLAR", 34, ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_x := CharacterScript.styled_button("Kapat", true, 20, 46)
	close_x.custom_minimum_size.x = 120
	close_x.pressed.connect(_close)
	head.add_child(close_x)
	outer.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 12)
	scroll.add_child(col)

	var s: Dictionary = profile.settings
	var p := _section(col, "Oyuncu", Color("#ffb020"))
	_name = LineEdit.new()
	_name.text = profile.player_name
	_name.max_length = 16
	_name.placeholder_text = "Adını yaz"
	_name.custom_minimum_size = Vector2(0, 48)
	_name.add_theme_font_size_override("font_size", 21)
	_row(p, "Adın", _name)
	var chr := CharacterScript.styled_button("Karakter & Mağaza", true, 20, 52)
	chr.pressed.connect(func() -> void:
		_save_name()
		open_character.emit())
	p.add_child(chr)

	var c := _section(col, "Kontroller", Color("#3b9cff"))
	_row(c, "Bakış hassasiyeti", _slider(0.4, 2.0, s.hassasiyet, "hassasiyet", "%d%%"))
	_row(c, "Joystick", _choice(["Parmağın değdiği yer", "Sabit"], 0 if s.yuzen_joy else 1, func(i: int) -> void:
		profile.settings.yuzen_joy = i == 0
		profile.save()))

	var a := _section(col, "Ses", Color("#5be37d"))
	_row(a, "Oyun sesi", _slider(0.0, 1.0, s.oyun_ses, "oyun_ses", "%d%%"))
	_row(a, "Konuşma sesi", _slider(0.0, 1.5, s.konusma_ses, "konusma_ses", "%d%%"))

	var g := _section(col, "Grafik", Color("#b05cff"))
	_row(g, "Kalite", _choice(["Pil dostu", "Yüksek"], int(s.kalite), func(i: int) -> void:
		profile.settings.kalite = i
		profile.save()))

	var leave := CharacterScript.styled_button("Ana menüye dön", false, 20, 52)
	leave.pressed.connect(func() -> void: leave_room.emit())
	col.add_child(leave)
	col.add_child(_label("Dokular: Poly Haven (CC0) · Animasyonlar: Mixamo · Hat Düştü © 2026", 14, Color(0.5, 0.52, 0.6)))


func _close() -> void:
	_save_name()
	closed.emit()
	queue_free()


func _save_name() -> void:
	var n := _name.text.strip_edges()
	if n != "" and n != profile.player_name:
		profile.player_name = n
		profile.save()
