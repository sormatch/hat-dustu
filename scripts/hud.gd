# Ekran arayüzü: joystick, bakma, tur/süre, oyuncular, etkileşim düğmesi, arama kutusu.
extends CanvasLayer

signal action_pressed
signal contact_chosen(id: int)
signal settings_pressed
signal emote_chosen(id: String)
signal crouch_pressed
signal ptt_changed(down: bool)
signal lobby_ready(on: bool)
signal lobby_start
signal lobby_invite
signal lobby_leave

const UI := preload("res://scripts/ui.gd")

const CharacterScript := preload("res://scripts/character.gd")
const Catalog := preload("res://scripts/catalog.gd")
const JOY_R := 85.0
const JOY_HOME := Vector2(50, -280)

var floating_joy := true
var sprint := false  # joystick yukarıdaki KOŞ halkasında  # joystick parmağın değdiği yerde açılır
var gems_label: Label
var emote_btn: Button
var crouch_btn: Button
var ptt_btn: Button
var fps_label: Label
var lobby_panel: PanelContainer
var lobby_info: Label
var lobby_players: HBoxContainer
var lobby_buttons: HBoxContainer
var _ready_on := false
var _game_pills: Array[Control] = []
var emote_panel: PanelContainer
var emote_grid: GridContainer
var _tap_blockers: Array[Control] = []

var player: Node  # main.gd bağlar
var move := Vector2.ZERO

var joy: Joy
var joy_index := -1
var look_index := -1

var action_btn: Button
var prompt_label: Label
var timer_label: Label
var timer_pill: PanelContainer
var _last_sec := -1
var _tick: AudioStreamPlayer
var ring_label: Label
var call_panel: PanelContainer
var call_title: Label
var call_text: Label
var hint: Label
var _style_phone: StyleBoxFlat
var _style_normal: StyleBoxFlat
var avatars: HBoxContainer
var round_pill: PanelContainer
var contacts: PanelContainer
var contact_list: VBoxContainer
var toast: Label
var _toast_tween: Tween


class Joy extends Control:
	var knob := Vector2.ZERO
	var sprint := false
	var active := false

	func _draw() -> void:
		var c := size / 2.0
		draw_circle(c, 85.0, Color(0, 0, 0, 0.35))
		draw_arc(c, 85.0, 0.0, TAU, 64, Color(1, 1, 1, 0.55), 3.0, true)
		for a in [0.0, PI / 2.0, PI, PI * 1.5]:
			var d := Vector2.from_angle(a)
			var p := c + d * 66.0
			var side := d.orthogonal() * 7.0
			draw_colored_polygon(PackedVector2Array([p + d * 8.0, p + side, p - side]), Color(1, 1, 1, 0.6))
		if active:
			# yukarıdaki halkaya itince hızlı koşma
			var sc := c + Vector2(0, -225)
			draw_circle(sc, 38.0, Color(1, 0.48, 0.1, 0.55 if sprint else 0.22))
			draw_arc(sc, 38.0, 0.0, TAU, 48, Color(1, 0.7, 0.4, 0.9), 3.0, true)
			draw_string(get_theme_default_font(), sc + Vector2(-24, 8), "KOŞ", HORIZONTAL_ALIGNMENT_CENTER, 48, 20, Color.WHITE)
		draw_circle(c + knob, 36.0, Color(1, 0.6, 0.25, 0.95) if sprint else Color(0.86, 0.87, 0.9, 0.92))


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


func _round_button(text: String, w: float, h: float, font: int, icon_name := "") -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(w, h)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font)
	var tex := UI.sbox("btn_round", int(minf(w, h)), 0.0, Vector4.ZERO)
	if tex:
		for k in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(k, tex)
		var v := VBoxContainer.new()
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", -2)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if icon_name != "":
			var ic := UI.icon(icon_name, minf(w, h) * (0.5 if text != "" else 0.62))
			ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			v.add_child(ic)
		if text != "":
			v.add_child(UI.title(text, font if icon_name == "" else int(font * 0.7), Color.WHITE, true))
		b.add_child(v)
		b.button_down.connect(func() -> void:
			b.pivot_offset = b.size / 2.0
			b.create_tween().tween_property(b, "scale", Vector2.ONE * 0.92, 0.06))
		b.button_up.connect(func() -> void: b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.1))
		return b
	b.text = text
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.05, 0.06, 0.6)
	st.border_color = Color(1, 1, 1, 0.6)
	st.set_border_width_all(3)
	st.set_corner_radius_all(int(minf(w, h) / 2.0))
	for k in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(k, st)
	return b


# Bekleme salonu paneli: oda kodu, oyuncular (hazır olanlar işaretli), Hazırım / Başlat / Davet / Çık.
func _build_lobby_panel() -> void:
	lobby_panel = UI.panel(Vector2(0, 0), 22)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	lobby_info = UI.title("", 22, Color("#ffcf8a"), true)
	v.add_child(lobby_info)
	lobby_players = HBoxContainer.new()
	lobby_players.alignment = BoxContainer.ALIGNMENT_CENTER
	lobby_players.add_theme_constant_override("separation", 6)
	v.add_child(lobby_players)
	lobby_buttons = HBoxContainer.new()
	lobby_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	lobby_buttons.add_theme_constant_override("separation", 8)
	v.add_child(lobby_buttons)
	lobby_panel.add_child(v)
	lobby_panel.visible = false
	add_child(lobby_panel)
	_place(lobby_panel, Control.PRESET_CENTER_TOP, Vector2(0, 12), Vector2.ZERO)
	lobby_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tap_blockers.append(lobby_panel)


func show_lobby(on: bool) -> void:
	if not lobby_panel:
		_build_lobby_panel()
	lobby_panel.visible = on
	for p in _game_pills:
		p.visible = not on


func update_lobby(code: String, players: Array, my_id: int, is_host: bool) -> void:
	if not lobby_panel:
		_build_lobby_panel()
	var ready_n := 0
	for p in players:
		if bool(p.get("r", false)):
			ready_n += 1
	lobby_info.text = "BEKLEME SALONU  ·  KOD %s  ·  %d/%d hazır" % [code, ready_n, players.size()]
	for ch in lobby_players.get_children():
		ch.queue_free()
	for p in players:
		var chip := PanelContainer.new()
		var st := UI.flat(Color(0.1, 0.12, 0.1, 0.85) if bool(p.get("r", false)) else Color(0.08, 0.08, 0.1, 0.85), Color("#5be37d") if bool(p.get("r", false)) else Color("#59606e"), 12)
		st.content_margin_top = 4
		st.content_margin_bottom = 4
		st.content_margin_left = 10
		st.content_margin_right = 10
		chip.add_theme_stylebox_override("panel", st)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		if bool(p.get("host", false)):
			row.add_child(UI.icon("crown", 22))
		var t := str(p.name) + ("  ✓" if bool(p.get("r", false)) else "")
		row.add_child(UI.label(t, 16, Color("#5be37d") if bool(p.get("r", false)) else Color(0.85, 0.86, 0.9)))
		chip.add_child(row)
		lobby_players.add_child(chip)
	for ch in lobby_buttons.get_children():
		ch.queue_free()
	var rb := UI.button("HAZIRIM ✓" if _ready_on else "HAZIRIM", "primary" if _ready_on else "orange", 50, 18, "", 150)
	rb.pressed.connect(func() -> void:
		_ready_on = not _ready_on
		lobby_ready.emit(_ready_on))
	lobby_buttons.add_child(rb)
	if is_host:
		var sb := UI.button("OYUNU BAŞLAT", "primary", 50, 18, "play", 210)
		sb.pressed.connect(func() -> void: lobby_start.emit())
		lobby_buttons.add_child(sb)
	var ib := UI.button("DAVET", "normal", 50, 18, "friends", 140)
	ib.pressed.connect(func() -> void: lobby_invite.emit())
	lobby_buttons.add_child(ib)
	var lb := UI.button("ÇIK", "red", 50, 18, "", 90)
	lb.pressed.connect(func() -> void: lobby_leave.emit())
	lobby_buttons.add_child(lb)


func set_fps_visible(on: bool) -> void:
	fps_label.visible = on


func set_ptt(on: bool) -> void:
	ptt_btn.visible = on


func _process(_delta: float) -> void:
	if fps_label and fps_label.visible:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()


func refresh_gems(n: int) -> void:
	gems_label.text = str(n)


# Hareket menüsü: sadece sahip olunan hareketler.
func set_emotes(owned_ids: Array) -> void:
	for ch in emote_grid.get_children():
		ch.queue_free()
	for it in Catalog.ITEMS.hareket:
		if not owned_ids.has(it[0]):
			continue
		var b := _button(it[1], false)
		b.custom_minimum_size = Vector2(140, 56)
		var id: String = it[0]
		b.pressed.connect(func() -> void:
			emote_panel.visible = false
			emote_chosen.emit(id))
		emote_grid.add_child(b)


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
	round_pill = PanelContainer.new()
	round_pill.add_theme_stylebox_override("panel", _pill())
	var rb := HBoxContainer.new()
	rb.add_theme_constant_override("separation", 14)
	rb.add_child(_label("Tur", 24, Color(0.8, 0.8, 0.82)))
	rb.add_child(_label("2/5", 26))
	round_pill.add_child(rb)
	root.add_child(round_pill)
	_place(round_pill, Control.PRESET_TOP_LEFT, Vector2(108, 22), Vector2.ZERO)
	_game_pills.append(round_pill)

	# Sol üst: ayarlar
	var gear := _round_button("", 64, 64, 18, "settings")
	gear.pressed.connect(func() -> void: settings_pressed.emit())
	root.add_child(gear)
	_place(gear, Control.PRESET_TOP_LEFT, Vector2(28, 14), Vector2(64, 64))
	_tap_blockers.append(gear)

	# Sağ üst, oyuncuların altında: elmas
	var gem_row := HBoxContainer.new()
	gem_row.add_theme_constant_override("separation", 6)
	gem_row.add_child(UI.gem(32))
	gems_label = _label("0", 24, Color("#a8f2ff"))
	gems_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	gems_label.add_theme_constant_override("outline_size", 6)
	gem_row.add_child(gems_label)
	root.add_child(gem_row)
	_place(gem_row, Control.PRESET_TOP_RIGHT, Vector2(-28, 84), Vector2.ZERO)
	gem_row.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	# Sağda: hareket (emote) düğmesi ve menüsü
	emote_btn = _round_button("Hareket", 116, 116, 22, "emote")
	emote_btn.pressed.connect(func() -> void:
		emote_panel.visible = not emote_panel.visible
		contacts.visible = false)
	root.add_child(emote_btn)
	_place(emote_btn, Control.PRESET_BOTTOM_RIGHT, Vector2(-190, -370), Vector2(110, 110))
	_tap_blockers.append(emote_btn)
	crouch_btn = _round_button("EĞİL", 100, 100, 20)
	crouch_btn.pressed.connect(func() -> void: crouch_pressed.emit())
	root.add_child(crouch_btn)
	_place(crouch_btn, Control.PRESET_BOTTOM_RIGHT, Vector2(-340, -150), Vector2(100, 100))
	_tap_blockers.append(crouch_btn)
	# bas-konuş: telefondayken basılı tutunca ses gider
	ptt_btn = _round_button("KONUŞ", 150, 150, 26, "mic")
	ptt_btn.button_down.connect(func() -> void:
		ptt_changed.emit(true)
		ptt_btn.modulate = Color(0.6, 1.4, 0.7))
	ptt_btn.button_up.connect(func() -> void:
		ptt_changed.emit(false)
		ptt_btn.modulate = Color.WHITE)
	ptt_btn.visible = false
	root.add_child(ptt_btn)
	_place(ptt_btn, Control.PRESET_CENTER_RIGHT, Vector2(-200, -75), Vector2(150, 150))
	_tap_blockers.append(ptt_btn)
	fps_label = _label("", 18, Color("#5be37d"))
	fps_label.visible = false
	root.add_child(fps_label)
	_place(fps_label, Control.PRESET_TOP_LEFT, Vector2(30, 84), Vector2(120, 26))
	emote_panel = PanelContainer.new()
	var eps := _pill()
	eps.set_corner_radius_all(18)
	eps.bg_color = Color(0.05, 0.05, 0.06, 0.9)
	eps.content_margin_left = 14
	eps.content_margin_right = 14
	eps.content_margin_top = 12
	eps.content_margin_bottom = 12
	emote_panel.add_theme_stylebox_override("panel", eps)
	emote_grid = GridContainer.new()
	emote_grid.columns = 2
	emote_grid.add_theme_constant_override("h_separation", 8)
	emote_grid.add_theme_constant_override("v_separation", 8)
	emote_panel.add_child(emote_grid)
	emote_panel.visible = false
	root.add_child(emote_panel)
	_place(emote_panel, Control.PRESET_CENTER_RIGHT, Vector2(-520, -170), Vector2(310, 0))
	_tap_blockers.append(emote_panel)

	# Üst orta: süre
	timer_pill = PanelContainer.new()
	timer_pill.add_theme_stylebox_override("panel", _pill())
	timer_label = _label("1:30", 30)
	timer_pill.add_child(timer_label)
	root.add_child(timer_pill)
	_place(timer_pill, Control.PRESET_CENTER_TOP, Vector2(0, 22), Vector2.ZERO)
	timer_pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_game_pills.append(timer_pill)

	# Sağ üst: oyuncular
	avatars = HBoxContainer.new()
	avatars.add_theme_constant_override("separation", 8)
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
	_place(joy, Control.PRESET_BOTTOM_LEFT, JOY_HOME, Vector2(240, 240))

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
	tw.tween_interval(6.0)
	tw.tween_property(hint, "modulate:a", 0.0, 1.0)

	# ekranın üstünde kısa bilgi mesajı
	toast = _label("", 24)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	toast.add_theme_constant_override("outline_size", 8)
	toast.modulate.a = 0.0
	root.add_child(toast)
	_place(toast, Control.PRESET_CENTER_TOP, Vector2(-400, 140), Vector2(800, 40))

	# telefon rehberi: kimi arayacağını seç
	contacts = PanelContainer.new()
	var ps := _pill()
	ps.set_corner_radius_all(20)
	ps.bg_color = Color(0.05, 0.05, 0.06, 0.92)
	ps.content_margin_left = 24
	ps.content_margin_right = 24
	ps.content_margin_top = 18
	ps.content_margin_bottom = 18
	contacts.add_theme_stylebox_override("panel", ps)
	var cvb := VBoxContainer.new()
	cvb.add_theme_constant_override("separation", 10)
	cvb.add_child(_label("Kimi arayacaksın?", 26, Color("#FF6B57")))
	contact_list = VBoxContainer.new()
	contact_list.add_theme_constant_override("separation", 8)
	cvb.add_child(contact_list)
	var cancel := _button("Vazgeç", false)
	cancel.pressed.connect(func() -> void: contacts.visible = false)
	cvb.add_child(cancel)
	contacts.add_child(cvb)
	contacts.visible = false
	root.add_child(contacts)
	_place(contacts, Control.PRESET_CENTER, Vector2(-230, -200), Vector2(460, 0))


func _button(text: String, phone: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 60)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 24)
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#B3141B") if phone else Color(1, 1, 1, 0.08)
	st.border_color = Color("#FF5A52") if phone else Color(1, 1, 1, 0.3)
	st.set_border_width_all(2)
	st.set_corner_radius_all(14)
	for k in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(k, st)
	return b


func show_contacts(list: Array) -> void:
	for ch in contact_list.get_children():
		ch.queue_free()
	for c in list:
		var b := _button("Ara:  " + str(c.name), true)
		var id: int = c.id
		b.pressed.connect(func() -> void:
			contacts.visible = false
			contact_chosen.emit(id))
		contact_list.add_child(b)
	contacts.visible = true


func show_toast(text: String) -> void:
	toast.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(toast, "modulate:a", 1.0, 0.2)
	_toast_tween.tween_interval(3.0)
	_toast_tween.tween_property(toast, "modulate:a", 0.0, 0.6)


const AVATAR_COLORS := ["#F5C542", "#C8A6FF", "#FFB86B", "#7FB2FF", "#6FD3B5", "#FF8FA3", "#B8E986", "#F4A6D7"]


# Sağ üstteki oyuncu yuvarlakları: baş harf, hücre rengine göre renk, kendin mavi çerçeveli.
func set_players(list: Array, my_id: int) -> void:
	for ch in avatars.get_children():
		ch.queue_free()
	for pl in list:
		var p := Panel.new()
		p.custom_minimum_size = Vector2(52, 52)
		var st := StyleBoxFlat.new()
		st.bg_color = Color(AVATAR_COLORS[int(pl.cell) % AVATAR_COLORS.size()])
		st.set_corner_radius_all(26)
		var me := int(pl.id) == my_id
		st.border_color = Color("#4C8DFF") if me else Color(0, 0, 0, 0.5)
		st.set_border_width_all(4 if me else 2)
		p.add_theme_stylebox_override("panel", st)
		var nm := str(pl.name)
		var l := _label(nm.substr(0, 1).to_upper() if nm != "" else "?", 22, Color("#14161B"))
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		p.add_child(l)
		p.tooltip_text = nm
		p.set_meta("id", int(pl.id))
		avatars.add_child(p)


# Oyunda hattı düşenlerin yuvarlağı solar.
func set_alive(alive: Array) -> void:
	for p in avatars.get_children():
		var out := not (int(p.get_meta("id", 0)) in alive)
		p.modulate = Color(0.35, 0.35, 0.38, 0.6) if out else Color.WHITE


func set_action(text: String, phone := false) -> void:
	if text == "":
		action_btn.visible = false
		return
	action_btn.visible = true
	action_btn.text = text
	var ph := UI.texture("icon_phone", 120)
	action_btn.icon = ph if phone else null
	action_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	action_btn.expand_icon = true
	action_btn.add_theme_constant_override("icon_max_width", 72)
	var st := _style_phone if phone else _style_normal
	for k in ["normal", "hover", "pressed", "focus"]:
		action_btn.add_theme_stylebox_override(k, st)


func set_timer(seconds: float) -> void:
	var s := int(ceil(seconds))
	timer_label.text = "%d:%02d" % [s / 60, s % 60]


# Oyun sayacı: son 15 saniyede kırmızı, her saniye nabız gibi atar ve tik sesi gelir.
func set_game_timer(seconds: float) -> void:
	set_timer(seconds)
	var s := int(ceil(seconds))
	var urgent := s <= 15 and s > 0
	timer_label.add_theme_color_override("font_color", Color("#ff3b3b") if urgent else Color.WHITE)
	if not urgent or s == _last_sec:
		if not urgent:
			timer_pill.scale = Vector2.ONE
			_last_sec = -1
		return
	_last_sec = s
	timer_pill.pivot_offset = timer_pill.size / 2.0
	var tw := timer_pill.create_tween()
	tw.tween_property(timer_pill, "scale", Vector2.ONE * (1.35 if s <= 5 else 1.18), 0.08)
	tw.tween_property(timer_pill, "scale", Vector2.ONE, 0.25)
	if not _tick:
		_tick = AudioStreamPlayer.new()
		_tick.stream = load("res://assets/ses/tik_ui.ogg")
		add_child(_tick)
	_tick.volume_db = 0.0 if s <= 5 else -8.0
	_tick.pitch_scale = 1.25 if s <= 5 else 1.0
	_tick.play()


func show_call(who: String, text: String) -> void:
	call_panel.visible = true
	call_title.text = "● Hatta: " + who
	call_text.text = text


func hide_call() -> void:
	call_panel.visible = false


# Ortadaki küçük ölü bölge titremeyi keser; kenara yakın itince tam hız (koşma).
func _update_joy(pos: Vector2) -> void:
	var c := joy.get_global_rect().get_center()
	var raw := pos - c
	joy.active = true
	sprint = raw.y < -JOY_R * 1.95 and absf(raw.x) < 80.0
	joy.sprint = sprint
	var v := raw.limit_length(JOY_R)
	joy.knob = v
	if sprint:
		move = Vector2(0, -1)
		joy.queue_redraw()
		return
	var m := v.length() / JOY_R
	m = 0.0 if m < 0.12 else minf(1.0, (m - 0.12) / 0.8)
	move = v.normalized() * m if v.length() > 0.0 else Vector2.ZERO
	joy.queue_redraw()


func _over_button(pos: Vector2) -> bool:
	if contacts.visible and contacts.get_global_rect().grow(10).has_point(pos):
		return true
	for c in _tap_blockers:
		if c.is_visible_in_tree() and c.get_global_rect().grow(10).has_point(pos):
			return true
	return action_btn.visible and action_btn.get_global_rect().grow(10).has_point(pos)


# Joystick: ekranın sol yarısında parmağın değdiği yerde açılır (ayarlardan sabit yapılabilir).
func _joy_zone(pos: Vector2) -> bool:
	var vs := get_viewport().get_visible_rect().size
	if floating_joy:
		return pos.x < vs.x * 0.42 and pos.y > vs.y * 0.3 and not _over_button(pos)
	return joy.get_global_rect().grow(60).has_point(pos)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var vw := get_viewport().get_visible_rect().size.x
		if event.pressed:
			if joy_index == -1 and _joy_zone(event.position):
				joy_index = event.index
				if floating_joy:
					joy.global_position = event.position - joy.size / 2.0
				_update_joy(event.position)
			elif look_index == -1 and not _over_button(event.position) and event.position.x > vw * 0.3:
				look_index = event.index
		else:
			if event.index == joy_index:
				joy_index = -1
				joy.knob = Vector2.ZERO
				joy.active = false
				joy.sprint = false
				sprint = false
				move = Vector2.ZERO
				_place(joy, Control.PRESET_BOTTOM_LEFT, JOY_HOME, Vector2(240, 240))
				joy.queue_redraw()
			if event.index == look_index:
				look_index = -1
	elif event is InputEventScreenDrag:
		if event.index == joy_index:
			_update_joy(event.position)
		elif event.index == look_index and player:
			player.look(event.relative)
