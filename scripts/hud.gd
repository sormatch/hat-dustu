# Ekran arayüzü: joystick, bakma, tur/süre, oyuncular, etkileşim düğmesi, arama kutusu.
extends CanvasLayer

signal action_pressed

const JOY_R := 85.0

var player: Node  # main.gd bağlar
var move := Vector2.ZERO

var joy: Joy
var joy_index := -1
var look_index := -1

var action_btn: Button
var prompt_label: Label
var timer_label: Label
var ring_label: Label
var call_panel: PanelContainer
var call_title: Label
var call_text: Label
var hint: Label
var _style_phone: StyleBoxFlat
var _style_normal: StyleBoxFlat


class Joy extends Control:
	var knob := Vector2.ZERO

	func _draw() -> void:
		var c := size / 2.0
		draw_circle(c, 85.0, Color(0, 0, 0, 0.35))
		draw_arc(c, 85.0, 0.0, TAU, 64, Color(1, 1, 1, 0.55), 3.0, true)
		for a in [0.0, PI / 2.0, PI, PI * 1.5]:
			var d := Vector2.from_angle(a)
			var p := c + d * 66.0
			var side := d.orthogonal() * 7.0
			draw_colored_polygon(PackedVector2Array([p + d * 8.0, p + side, p - side]), Color(1, 1, 1, 0.6))
		draw_circle(c + knob, 36.0, Color(0.86, 0.87, 0.9, 0.92))


func _pill() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.03, 0.03, 0.04, 0.6)
	s.border_color = Color(1, 1, 1, 0.22)
	s.set_border_width_all(1)
	s.set_corner_radius_all(24)
	s.content_margin_left = 20
	s.content_margin_right = 20
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


# Bir arayüz parçasını ekranın bir köşesine/kenarına göre yerleştirir.
func _place(c: Control, preset: int, ofs: Vector2, sz: Vector2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = ofs.x
	c.offset_top = ofs.y
	c.offset_right = ofs.x + sz.x
	c.offset_bottom = ofs.y + sz.y


func _label(text: String, size: int, color := Color(0.95, 0.94, 0.92)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Sol üst: tur
	var round_pill := PanelContainer.new()
	round_pill.add_theme_stylebox_override("panel", _pill())
	var rb := HBoxContainer.new()
	rb.add_theme_constant_override("separation", 14)
	rb.add_child(_label("Tur", 24, Color(0.8, 0.8, 0.82)))
	rb.add_child(_label("2/5", 26))
	round_pill.add_child(rb)
	root.add_child(round_pill)
	_place(round_pill, Control.PRESET_TOP_LEFT, Vector2(28, 22), Vector2.ZERO)

	# Üst orta: süre
	var timer_pill := PanelContainer.new()
	timer_pill.add_theme_stylebox_override("panel", _pill())
	timer_label = _label("1:30", 30)
	timer_pill.add_child(timer_label)
	root.add_child(timer_pill)
	_place(timer_pill, Control.PRESET_CENTER_TOP, Vector2(0, 22), Vector2.ZERO)
	timer_pill.grow_horizontal = Control.GROW_DIRECTION_BOTH

	# Sağ üst: oyuncular
	var avatars := HBoxContainer.new()
	avatars.add_theme_constant_override("separation", 8)
	var people := [["M", Color("#F5C542")], ["D", Color("#C8A6FF")], ["A", Color("#FFB86B")],
		["M", Color("#7FB2FF")], ["C", Color("#6FD3B5")], ["E", Color("#FF8FA3")]]
	for i in people.size():
		var p := Panel.new()
		p.custom_minimum_size = Vector2(52, 52)
		var st := StyleBoxFlat.new()
		st.bg_color = people[i][1]
		st.set_corner_radius_all(26)
		st.border_color = Color("#4C8DFF") if i == 0 else Color(0, 0, 0, 0.5)
		st.set_border_width_all(4 if i == 0 else 2)
		p.add_theme_stylebox_override("panel", st)
		var l := _label(people[i][0], 22, Color("#14161B"))
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		p.add_child(l)
		avatars.add_child(p)
	root.add_child(avatars)
	_place(avatars, Control.PRESET_TOP_RIGHT, Vector2(-28, 20), Vector2.ZERO)
	avatars.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	# Ekran ortası: nişan noktası
	var dot := Panel.new()
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(1, 1, 1, 0.6)
	ds.set_corner_radius_all(4)
	dot.add_theme_stylebox_override("panel", ds)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dot)
	_place(dot, Control.PRESET_CENTER, Vector2(-3.5, -3.5), Vector2(7, 7))

	prompt_label = _label("", 22)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	prompt_label.add_theme_constant_override("outline_size", 6)
	root.add_child(prompt_label)
	_place(prompt_label, Control.PRESET_CENTER, Vector2(-200, 26), Vector2(400, 40))

	ring_label = _label("Telefon çalıyor…", 26, Color("#FF6B57"))
	ring_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ring_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	ring_label.add_theme_constant_override("outline_size", 8)
	ring_label.visible = false
	root.add_child(ring_label)
	_place(ring_label, Control.PRESET_CENTER_TOP, Vector2(-200, 92), Vector2(400, 40))

	# Sol alt: joystick
	joy = Joy.new()
	joy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(joy)
	_place(joy, Control.PRESET_BOTTOM_LEFT, Vector2(50, -280), Vector2(240, 240))

	# Sağ alt: etkileşim düğmesi
	_style_phone = StyleBoxFlat.new()
	_style_phone.bg_color = Color("#B3141B")
	_style_phone.border_color = Color("#FF5A52")
	_style_phone.set_border_width_all(5)
	_style_phone.set_corner_radius_all(85)
	_style_phone.shadow_color = Color(1, 0.15, 0.1, 0.45)
	_style_phone.shadow_size = 18
	_style_normal = StyleBoxFlat.new()
	_style_normal.bg_color = Color(0.05, 0.05, 0.06, 0.6)
	_style_normal.border_color = Color(1, 1, 1, 0.75)
	_style_normal.set_border_width_all(4)
	_style_normal.set_corner_radius_all(85)
	action_btn = Button.new()
	action_btn.add_theme_font_size_override("font_size", 24)
	action_btn.focus_mode = Control.FOCUS_NONE
	action_btn.autowrap_mode = TextServer.AUTOWRAP_WORD
	action_btn.pressed.connect(func() -> void: action_pressed.emit())
	action_btn.visible = false
	root.add_child(action_btn)
	_place(action_btn, Control.PRESET_BOTTOM_RIGHT, Vector2(-220, -230), Vector2(170, 170))

	# Alt orta: telefon konuşması
	call_panel = PanelContainer.new()
	var cs := _pill()
	cs.set_corner_radius_all(18)
	cs.content_margin_left = 24
	cs.content_margin_right = 24
	cs.content_margin_top = 14
	cs.content_margin_bottom = 16
	cs.bg_color = Color(0.03, 0.03, 0.04, 0.78)
	call_panel.add_theme_stylebox_override("panel", cs)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	call_title = _label("", 20, Color("#FF6B57"))
	call_text = _label("", 24)
	call_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	call_text.custom_minimum_size = Vector2(570, 0)
	cv.add_child(call_title)
	cv.add_child(call_text)
	call_panel.add_child(cv)
	call_panel.visible = false
	root.add_child(call_panel)
	_place(call_panel, Control.PRESET_CENTER_BOTTOM, Vector2(-310, -200), Vector2(620, 0))

	hint = _label("Yürü: joystick / WASD   ·   Etrafa bak: ekranı sürükle   ·   Etkileşim: düğme / E", 18, Color(0.85, 0.85, 0.87))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hint.add_theme_constant_override("outline_size", 5)
	root.add_child(hint)
	_place(hint, Control.PRESET_CENTER_BOTTOM, Vector2(-450, -50), Vector2(900, 30))
	var tw := create_tween()
	tw.tween_interval(10.0)
	tw.tween_property(hint, "modulate:a", 0.0, 1.5)


func set_action(text: String, phone := false) -> void:
	if text == "":
		action_btn.visible = false
		return
	action_btn.visible = true
	action_btn.text = text
	var st := _style_phone if phone else _style_normal
	for k in ["normal", "hover", "pressed", "focus"]:
		action_btn.add_theme_stylebox_override(k, st)


func set_timer(seconds: float) -> void:
	var s := int(ceil(seconds))
	timer_label.text = "%d:%02d" % [s / 60, s % 60]


func show_call(who: String, text: String) -> void:
	call_panel.visible = true
	call_title.text = "● Hatta: " + who
	call_text.text = text


func hide_call() -> void:
	call_panel.visible = false


func _update_joy(pos: Vector2) -> void:
	var c := joy.get_global_rect().get_center()
	var v := (pos - c).limit_length(JOY_R)
	joy.knob = v
	move = v / JOY_R
	joy.queue_redraw()


func _over_button(pos: Vector2) -> bool:
	return action_btn.visible and action_btn.get_global_rect().grow(10).has_point(pos)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var vw := get_viewport().get_visible_rect().size.x
		if event.pressed:
			if joy_index == -1 and joy.get_global_rect().grow(60).has_point(event.position):
				joy_index = event.index
				_update_joy(event.position)
			elif look_index == -1 and not _over_button(event.position) and event.position.x > vw * 0.3:
				look_index = event.index
		else:
			if event.index == joy_index:
				joy_index = -1
				joy.knob = Vector2.ZERO
				move = Vector2.ZERO
				joy.queue_redraw()
			if event.index == look_index:
				look_index = -1
	elif event is InputEventScreenDrag:
		if event.index == joy_index:
			_update_joy(event.position)
		elif event.index == look_index and player:
			player.look(event.relative)
