# Ana menü, oyun seçimi ve bekleme salonu (lobi).
# Ortada logo ve büyük düğmeler, solda dönen karakterin, sağda arkadaşlarım paneli, sağ üstte elmas ve ayarlar.
extends CanvasLayer

signal solo
signal open_character
signal open_settings
signal open_friends

const CharacterScript := preload("res://scripts/character.gd")
const UI := preload("res://scripts/ui.gd")
const ModelScript := preload("res://scripts/model_body.gd")
const SLOT_COLORS := ["#F5C542", "#C8A6FF", "#FFB86B", "#7FB2FF", "#6FD3B5", "#FF8FA3", "#B8E986", "#F4A6D7"]

var net: Node
var profile: Node
var account: Node
var main_box: VBoxContainer
var play_box: VBoxContainer
var lobby_box: VBoxContainer
var code_edit: LineEdit
var status: Label
var code_label: Label
var lobby_title: Label
var player_list: GridContainer
var start_btn: Button
var wait_label: Label
var gems_label: Label
var daily_btn: Button
var friends_list: VBoxContainer
var friends_title: Label
var char_name: Label
var _preview: Node3D
var _turn: Node3D
var _toast: PanelContainer


# Düğme ikonları: basit çizimler (oynat, elmas, kişiler, dişli, kapı).
class Icon extends Control:
	var kind := ""
	var color := Color.WHITE

	func _draw() -> void:
		var s := size
		var c := s / 2.0
		match kind:
			"oyna":
				draw_colored_polygon(PackedVector2Array([Vector2(s.x * 0.3, s.y * 0.2), Vector2(s.x * 0.8, c.y), Vector2(s.x * 0.3, s.y * 0.8)]), color)
			"elmas":
				var p := PackedVector2Array([Vector2(c.x, s.y * 0.1), Vector2(s.x * 0.9, s.y * 0.4), Vector2(c.x, s.y * 0.92), Vector2(s.x * 0.1, s.y * 0.4)])
				draw_colored_polygon(p, Color("#3fd6f0"))
				draw_colored_polygon(PackedVector2Array([p[0], p[1], Vector2(c.x, s.y * 0.4), p[3]]), Color("#a8f2ff"))
			"kisiler":
				for k in 2:
					var x := s.x * (0.36 + k * 0.3)
					var col := color if k == 0 else color.darkened(0.25)
					draw_circle(Vector2(x, s.y * 0.32), s.x * 0.13, col)
					draw_circle(Vector2(x, s.y * 0.82), s.x * 0.22, col)
			"disli":
				for k in 8:
					var a := k * TAU / 8.0
					draw_line(c + Vector2.from_angle(a) * s.x * 0.22, c + Vector2.from_angle(a) * s.x * 0.44, color, s.x * 0.14)
				draw_circle(c, s.x * 0.3, color)
				draw_circle(c, s.x * 0.13, Color(0.15, 0.16, 0.2))
			"kapi":
				draw_rect(Rect2(s.x * 0.45, s.y * 0.12, s.x * 0.42, s.y * 0.76), Color("#b06a2c"))
				draw_circle(Vector2(s.x * 0.53, c.y), s.x * 0.04, Color("#ffd27a"))
				draw_line(Vector2(s.x * 0.08, c.y), Vector2(s.x * 0.4, c.y), Color("#5be37d"), s.x * 0.1)
				draw_colored_polygon(PackedVector2Array([Vector2(s.x * 0.42, c.y), Vector2(s.x * 0.28, s.y * 0.34), Vector2(s.x * 0.28, s.y * 0.66)]), Color("#5be37d"))


static func icon(kind: String, px: float, color := Color.WHITE) -> Icon:
	var i := Icon.new()
	i.kind = kind
	i.color = color
	i.custom_minimum_size = Vector2(px, px)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


func _label(text: String, size: int, color := Color(0.95, 0.94, 0.92)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _style(bg: Color, border: Color, glow := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = border
	st.set_border_width_all(2)
	st.border_width_top = 3
	st.set_corner_radius_all(16)
	st.shadow_color = glow if glow.a > 0.0 else Color(0, 0, 0, 0.45)
	st.shadow_size = 16 if glow.a > 0.0 else 6
	st.shadow_offset = Vector2.ZERO if glow.a > 0.0 else Vector2(0, 4)
	return st


# Büyük menü düğmesi: solda ikon, ortada yazı. tür: "ana" (parlayan), "kirmizi", "" (metal).
func _big(text: String, icon_kind: String, kind := "", h := 76.0) -> Button:
	var kinds := {"ana": "primary", "kirmizi": "red", "": "normal"}
	var icons := {"oyna": "play", "elmas": "store", "kisiler": "friends", "disli": "settings", "kapi": "exit"}
	return UI.button(text, kinds.get(kind, "normal"), int(h), 30 if h >= 70 else 24, icons.get(icon_kind, ""), 430.0 if h >= 60 else 0.0)


func _big_old(text: String, icon_kind: String, kind := "", h := 76.0) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(430, h)
	b.focus_mode = Control.FOCUS_NONE
	var st: StyleBoxFlat
	match kind:
		"ana":
			st = _style(Color("#1d3a42"), Color("#5ff0ff"), Color(0.37, 0.94, 1, 0.45))
		"kirmizi":
			st = _style(Color("#5a1616"), Color("#d0463a"))
		_:
			st = _style(Color("#2b2f38"), Color("#7b8494"))
	var hover := st.duplicate()
	hover.bg_color = st.bg_color.lightened(0.12)
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", st)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 22
	row.offset_right = -22
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	var ic := icon(icon_kind, h * 0.55, Color("#ffcf8a") if kind == "" else Color.WHITE)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var l := _label(text, 30 if h >= 70 else 24)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 6)
	row.add_child(l)
	var pad := Control.new()
	pad.custom_minimum_size.x = h * 0.55
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pad)
	b.add_child(row)
	return b


func _edit(placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(0, 62)
	e.add_theme_font_size_override("font_size", 26)
	e.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var st := _style(Color(0.08, 0.09, 0.12, 0.95), Color("#5a6273"))
	e.add_theme_stylebox_override("normal", st)
	e.add_theme_stylebox_override("focus", st)
	return e


func _card(w: float, h: float) -> PanelContainer:
	return UI.panel(Vector2(w, h), 26)


func _card_old(w: float, h: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(w, h)
	var st := _style(Color(0.09, 0.1, 0.13, 0.86), Color("#6b7383"))
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 12
	st.content_margin_bottom = 12
	p.add_theme_stylebox_override("panel", st)
	return p


func _place(c: Control, preset: int, ofs: Vector2, sz: Vector2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = ofs.x
	c.offset_top = ofs.y
	c.offset_right = ofs.x + sz.x
	c.offset_bottom = ofs.y + sz.y


func _ready() -> void:
	layer = 10
	# kenarları karartan sinematik gölge (arkada 3D koridor var)
	var vig := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.45)
	gt.fill_to = Vector2(1.05, 1.05)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.15))
	g.set_color(1, Color(0, 0, 0, 0.85))
	gt.gradient = g
	vig.texture = gt
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vig)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# sağ üst: elmas ve ayarlar
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var gem_pill := PanelContainer.new()
	var gps := _style(Color(0.06, 0.07, 0.1, 0.85), Color("#5a6273"))
	gps.set_corner_radius_all(30)
	gps.content_margin_left = 16
	gps.content_margin_right = 20
	gem_pill.add_theme_stylebox_override("panel", gps)
	var gr := HBoxContainer.new()
	gr.add_theme_constant_override("separation", 8)
	gr.add_child(UI.gem(40))
	gems_label = UI.title("0", 30, Color("#a8f2ff"))
	gr.add_child(gems_label)
	gem_pill.add_child(gr)
	top.add_child(gem_pill)
	var gear := Button.new()
	gear.custom_minimum_size = Vector2(64, 64)
	gear.focus_mode = Control.FOCUS_NONE
	var gst := _style(Color(0.06, 0.07, 0.1, 0.85), Color("#8a93a3"))
	gst.set_corner_radius_all(32)
	for k in ["normal", "hover", "pressed", "focus"]:
		gear.add_theme_stylebox_override(k, gst)
	var rb := UI.sbox("btn_round", 64, 0.3, Vector4.ZERO)
	if rb:
		for k in ["normal", "hover", "pressed", "focus"]:
			gear.add_theme_stylebox_override(k, rb)
	var gi := UI.icon("settings", 44)
	gi.position = Vector2(10, 10)
	gear.add_child(gi)
	gear.pressed.connect(func() -> void: open_settings.emit())
	top.add_child(gear)
	root.add_child(top)
	_place(top, Control.PRESET_TOP_RIGHT, Vector2(-24, 18), Vector2.ZERO)
	top.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	# orta sütun: logo + düğmeler / oyun seçimi / lobi
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	root.add_child(col)
	_place(col, Control.PRESET_CENTER_TOP, Vector2(-235, 14), Vector2(470, 0))
	col.add_child(_logo())

	main_box = VBoxContainer.new()
	main_box.add_theme_constant_override("separation", 12)
	col.add_child(main_box)
	var play := _big("OYUNA BAŞLA", "oyna", "ana")
	play.pressed.connect(func() -> void: _show(play_box))
	main_box.add_child(play)
	var shop := _big("KARAKTER & MAĞAZA", "elmas")
	shop.pressed.connect(func() -> void: open_character.emit())
	main_box.add_child(shop)
	var fr := _big("ARKADAŞLARIM", "kisiler")
	fr.pressed.connect(func() -> void: open_friends.emit())
	main_box.add_child(fr)
	var st_btn := _big("AYARLAR", "disli")
	st_btn.pressed.connect(func() -> void: open_settings.emit())
	main_box.add_child(st_btn)
	var quit := _big("ÇIKIŞ", "kapi", "kirmizi")
	quit.pressed.connect(func() -> void: get_tree().quit())
	main_box.add_child(quit)

	# oyun seçimi
	play_box = VBoxContainer.new()
	play_box.add_theme_constant_override("separation", 12)
	play_box.visible = false
	col.add_child(play_box)
	var create := _big("ODA KUR", "oyna", "ana")
	create.pressed.connect(_on_create)
	play_box.add_child(create)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	code_edit = _edit("Oda kodu")
	code_edit.max_length = 4
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_edit.text_changed.connect(func(t: String) -> void:
		var up := t.to_upper()
		if up != t:
			code_edit.text = up
			code_edit.caret_column = up.length())
	row.add_child(code_edit)
	var join := _big("KATIL", "kisiler", "", 62)
	join.custom_minimum_size.x = 180
	join.pressed.connect(func() -> void: _on_join(code_edit.text))
	row.add_child(join)
	play_box.add_child(row)
	var alone := _big("TEK BAŞINA DENE", "kapi", "", 64)
	alone.pressed.connect(func() -> void: solo.emit())
	play_box.add_child(alone)
	daily_btn = _big("GÜNLÜK ÖDÜL  +%d" % profile.DAILY_GEMS, "elmas", "", 60)
	daily_btn.pressed.connect(func() -> void:
		profile.claim_daily()
		refresh_profile())
	play_box.add_child(daily_btn)
	var back := _big("GERİ", "kapi", "kirmizi", 60)
	back.pressed.connect(func() -> void: _show(main_box))
	play_box.add_child(back)

	_build_lobby(col)

	status = _label("", 20, Color("#ff9a8a"))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(status)

	_build_char_card(root)
	_build_friends_card(root)

	net.welcomed.connect(_show_lobby)
	net.players_changed.connect(_refresh_players)
	account.list_changed.connect(_refresh_friends)
	account.me_changed.connect(refresh_profile)
	account.invited.connect(_on_invited)
	refresh_profile()
	_refresh_friends()


func _logo() -> Control:
	var tex := UI.texture("logo", 420)
	if tex:
		var r := TextureRect.new()
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.custom_minimum_size = Vector2(470, 230)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return r
	var badge := PanelContainer.new()
	var st := _style(Color(0.1, 0.11, 0.13, 0.75), Color("#9aa3b2"))
	st.set_border_width_all(4)
	st.set_corner_radius_all(26)
	st.content_margin_top = 2
	st.content_margin_bottom = 8
	badge.add_theme_stylebox_override("panel", st)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -26)
	for line in [["HAT", 84], ["DÜŞTÜ", 96]]:
		var l := _label(line[0], line[1], Color("#dfe3e8"))
		l.add_theme_color_override("font_outline_color", Color("#3a2a1c"))
		l.add_theme_constant_override("outline_size", 18)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
		l.add_theme_constant_override("shadow_offset_x", 4)
		l.add_theme_constant_override("shadow_offset_y", 6)
		v.add_child(l)
	badge.add_child(v)
	return badge


# Sol: karakterin dönerek duruyor, altında adın ve @kullanıcı adın.
func _build_char_card(root: Control) -> void:
	var card := _card(250, 380)
	root.add_child(card)
	_place(card, Control.PRESET_CENTER_LEFT, Vector2(18, -170), Vector2(250, 380))
	var v := VBoxContainer.new()
	card.add_child(v)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(220, 300)
	v.add_child(svc)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.transparent_bg = true
	svc.add_child(sv)
	var w := Node3D.new()
	sv.add_child(w)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.62, 0.7)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	w.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.5, 2.8, 0)
	key.light_energy = 1.4
	w.add_child(key)
	_turn = Node3D.new()
	w.add_child(_turn)
	_preview = ModelScript.new()
	_preview.look = profile.look.duplicate()
	_turn.add_child(_preview)
	var cam := Camera3D.new()
	cam.fov = 32
	w.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.35, -2.6), Vector3(0, 1.2, 0))
	char_name = UI.title("", 22, UI.CREAM, true)
	v.add_child(char_name)


# Sağ: arkadaşlarım paneli (çevrimiçi olanlar üstte, lobideyken "Davet" düğmesi).
func _build_friends_card(root: Control) -> void:
	var card := _card(280, 380)
	root.add_child(card)
	_place(card, Control.PRESET_CENTER_RIGHT, Vector2(-298, -170), Vector2(280, 380))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	friends_title = UI.title("ARKADAŞLARIM", 22, Color("#ffcf8a"), true)
	v.add_child(friends_title)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	friends_list = VBoxContainer.new()
	friends_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	friends_list.add_theme_constant_override("separation", 6)
	sc.add_child(friends_list)
	var all := UI.button("ARKADAŞ EKLE", "orange", 52, 19)
	all.pressed.connect(func() -> void: open_friends.emit())
	v.add_child(all)


func _refresh_friends() -> void:
	if not friends_list:
		return
	for ch in friends_list.get_children():
		ch.queue_free()
	friends_title.text = "ARKADAŞLARIM  %d/%d" % [account.online_count(), account.friends.size()]
	if account.incoming.size() > 0:
		friends_list.add_child(_label("%d yeni arkadaşlık isteği" % account.incoming.size(), 17, Color("#5be37d")))
	if account.friends.is_empty():
		var e := _label("Henüz arkadaşın yok.\n\"Arkadaş ekle\" ile @kullanıcıadı yazarak ekle.", 16, Color(1, 1, 1, 0.5))
		e.autowrap_mode = TextServer.AUTOWRAP_WORD
		friends_list.add_child(e)
	var in_lobby: bool = net.connected and lobby_box.visible
	for f in account.friends:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var ds := StyleBoxFlat.new()
		ds.bg_color = Color("#5be37d") if f.online else Color("#59606e")
		ds.set_corner_radius_all(6)
		dot.add_theme_stylebox_override("panel", ds)
		r.add_child(dot)
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_theme_constant_override("separation", -4)
		var n := _label(str(f.name), 18)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		n.clip_text = true
		tv.add_child(n)
		var where: String = ("lobide" if str(f.room) != "" else "çevrimiçi") if f.online else "çevrimdışı"
		var h := _label("@%s · %s" % [f.handle, where], 14, Color(0.7, 0.72, 0.8))
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		h.clip_text = true
		tv.add_child(h)
		r.add_child(tv)
		if in_lobby and f.online:
			var inv := CharacterScript.styled_button("Davet", true, 15, 36)
			inv.custom_minimum_size.x = 74
			var fh: String = f.handle
			inv.pressed.connect(func() -> void: account.send({"t": "davet", "handle": fh, "oda": net.room_code}))
			r.add_child(inv)
		friends_list.add_child(r)


func _on_invited(handle: String, name: String, code: String) -> void:
	if _toast:
		_toast.queue_free()
	_toast = _card(560, 0)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var l := _label("%s (@%s) seni odasına çağırıyor!" % [name, handle], 20, Color("#ffcf8a"))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	h.add_child(l)
	var ok := CharacterScript.styled_button("Katıl", true, 20, 48)
	ok.custom_minimum_size.x = 100
	ok.pressed.connect(func() -> void:
		_toast.queue_free()
		if not net.connected:
			_on_join(code))
	h.add_child(ok)
	var no := CharacterScript.styled_button("X", false, 20, 48)
	no.custom_minimum_size.x = 50
	no.pressed.connect(func() -> void: _toast.queue_free())
	h.add_child(no)
	_toast.add_child(h)
	add_child(_toast)
	_place(_toast, Control.PRESET_CENTER_BOTTOM, Vector2(-280, -110), Vector2(560, 0))


func _process(delta: float) -> void:
	if _turn and visible:
		_turn.rotation.y += delta * 0.4


func _build_lobby(col: VBoxContainer) -> void:
	lobby_box = VBoxContainer.new()
	lobby_box.add_theme_constant_override("separation", 10)
	lobby_box.visible = false
	col.add_child(lobby_box)
	lobby_title = UI.title("BEKLEME SALONU", 30, Color("#ffcf8a"), true)
	lobby_box.add_child(lobby_title)
	# yeşil tebeşir tahtası
	var board := PanelContainer.new()
	var bst := StyleBoxFlat.new()
	bst.bg_color = Color("#2e5a3c")
	bst.border_color = Color("#7a4f2a")
	bst.set_border_width_all(12)
	bst.set_corner_radius_all(8)
	bst.content_margin_top = 6
	bst.content_margin_bottom = 10
	bst.shadow_color = Color(0, 0, 0, 0.5)
	bst.shadow_size = 12
	board.add_theme_stylebox_override("panel", bst)
	var bv := VBoxContainer.new()
	bv.add_child(_label("oda kodu", 18, Color(0.92, 0.95, 0.9, 0.7)))
	code_label = _label("----", 72, Color(0.97, 0.97, 0.93))
	bv.add_child(code_label)
	bv.add_child(_label("Mikrofon açık: salondaki herkes birbirini duyar", 16, Color("#c8f0c8")))
	board.add_child(bv)
	lobby_box.add_child(board)
	player_list = GridContainer.new()
	player_list.columns = 4
	player_list.add_theme_constant_override("h_separation", 8)
	player_list.add_theme_constant_override("v_separation", 8)
	lobby_box.add_child(player_list)
	var share := HBoxContainer.new()
	share.add_theme_constant_override("separation", 8)
	var wa := CharacterScript.styled_button("WhatsApp ile davet", false, 18, 48)
	wa.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wa.pressed.connect(_on_invite)
	share.add_child(wa)
	var copy := CharacterScript.styled_button("Kodu kopyala", false, 18, 48)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(net.room_code)
		status.text = "Kod kopyalandı: " + net.room_code)
	share.add_child(copy)
	lobby_box.add_child(share)
	start_btn = _big("OYUNU BAŞLAT", "oyna", "ana", 64)
	start_btn.pressed.connect(func() -> void: net.send({"t": "basla"}))
	lobby_box.add_child(start_btn)
	wait_label = _label("Odayı kuranın oyunu başlatması bekleniyor…", 18, Color(0.75, 0.75, 0.78))
	lobby_box.add_child(wait_label)
	var leave := _big("ODADAN ÇIK", "kapi", "kirmizi", 56)
	leave.pressed.connect(func() -> void:
		net.leave()
		account.set_room("")
		_show(main_box)
		_refresh_friends())
	lobby_box.add_child(leave)


func _show(box: Control) -> void:
	for b in [main_box, play_box, lobby_box]:
		b.visible = b == box
	status.text = ""


func _player_name() -> String:
	var n: String = profile.player_name
	if n == "":
		n = account.handle if account.handle != "" else "Mahkum%d" % (randi() % 90 + 10)
		profile.player_name = n
		profile.save()
	return n


func refresh_profile() -> void:
	gems_label.text = str(profile.gems)
	daily_btn.visible = profile.daily_available()
	char_name.text = _player_name() + ("\n@" + account.handle if account.handle != "" else "")
	if _preview:
		_preview.set_look(profile.look)


func _on_create() -> void:
	status.text = "Oda kuruluyor…"
	net.join(net.new_code(), _player_name(), true)


func _on_join(raw: String) -> void:
	var code := raw.strip_edges().to_upper()
	if code.length() != 4:
		status.text = "Oda kodu 4 harf olmalı."
		return
	status.text = "Bağlanılıyor…"
	net.join(code, _player_name(), false)


func _on_invite() -> void:
	var text := "Hat Düştü'de seni bekliyorum! Uygulamayı aç, \"Katıl\" kısmına şu kodu yaz: %s" % net.room_code
	OS.shell_open("https://wa.me/?text=" + text.uri_encode())


func _show_lobby() -> void:
	_show(lobby_box)
	code_label.text = net.room_code
	account.set_room(net.room_code)
	_refresh_players()
	_refresh_friends()


func _refresh_players() -> void:
	for ch in player_list.get_children():
		ch.queue_free()
	lobby_title.text = "BEKLEME SALONU  ·  %d/8" % net.players.size()
	var by_cell := {}
	for p in net.players:
		by_cell[int(p.cell)] = p
	for cell in 8:
		player_list.add_child(_slot(by_cell.get(cell, {}), cell))
	start_btn.visible = net.is_host
	wait_label.visible = not net.is_host


# Lobideki bir yer: dolu ise baş harf yuvarlağı, ad ve rozet; boşsa soluk "boş yer".
func _slot(p: Dictionary, cell: int) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(108, 104)
	var filled := not p.is_empty()
	var me: bool = filled and int(p.id) == net.my_id
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#262a3a") if filled else Color(1, 1, 1, 0.03)
	st.border_color = Color("#ffb020") if me else (Color("#3d4460") if filled else Color(1, 1, 1, 0.1))
	st.set_border_width_all(3 if me else 2)
	st.set_corner_radius_all(16)
	card.add_theme_stylebox_override("panel", st)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	card.add_child(v)
	if not filled:
		v.add_child(_label("Boş yer", 15, Color(1, 1, 1, 0.3)))
		return card
	var av := Panel.new()
	av.custom_minimum_size = Vector2(44, 44)
	av.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var ast := StyleBoxFlat.new()
	ast.bg_color = Color(SLOT_COLORS[cell % SLOT_COLORS.size()])
	ast.set_corner_radius_all(22)
	av.add_theme_stylebox_override("panel", ast)
	var ini := _label(str(p.name).substr(0, 1).to_upper(), 22, Color("#14161b"))
	ini.set_anchors_preset(Control.PRESET_FULL_RECT)
	ini.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	av.add_child(ini)
	v.add_child(av)
	var nm := _label(str(p.name), 16)
	nm.clip_text = true
	v.add_child(nm)
	var badge := "KURUCU" if bool(p.host) else ("SEN" if me else "hücre %d" % (11 + cell))
	v.add_child(_label(badge, 12, Color("#ffb020") if bool(p.host) else Color(0.7, 0.72, 0.8)))
	return card


func show_error(msg: String) -> void:
	_show(play_box)
	status.text = msg
