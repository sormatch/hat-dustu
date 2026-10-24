# Ana menü ve lobi: adını yaz, oda kur ya da kodla katıl, arkadaşını WhatsApp'tan davet et.
extends CanvasLayer

signal solo
signal open_character

const CharacterScript := preload("res://scripts/character.gd")

const SETTINGS := "user://ayar.cfg"

var net: Node
var profile: Node
var gems_label: Label
var daily_btn: Button
var main_box: VBoxContainer
var lobby_box: VBoxContainer
var name_edit: LineEdit
var code_edit: LineEdit
var status: Label
var code_label: Label
var player_list: GridContainer
var lobby_title: Label
var start_btn: Button
var wait_label: Label


func _label(text: String, size: int, color := Color(0.95, 0.94, 0.92)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 64)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 26)
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#ff6a1a") if primary else Color("#262a3a")
	st.border_color = Color("#ffb46b") if primary else Color("#3d4460")
	st.set_border_width_all(2)
	st.border_width_bottom = 5
	st.set_corner_radius_all(16)
	for k in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(k, st)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.4))
	return b


func _edit(placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(0, 60)
	e.add_theme_font_size_override("font_size", 26)
	e.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	st.border_color = Color(1, 1, 1, 0.3)
	st.set_border_width_all(2)
	st.set_corner_radius_all(14)
	e.add_theme_stylebox_override("normal", st)
	e.add_theme_stylebox_override("focus", st)
	return e


func _ready() -> void:
	layer = 10
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.12, 0.84)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(520, 0)
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)

	var title := _label("HAT DÜŞTÜ", 68, Color("#ff7a1a"))
	col.add_child(title)
	col.add_child(_label("Herkes kendi hücresinde. Tek bağlantı: kırmızı telefon.", 20, Color(0.75, 0.75, 0.78)))

	# --- ana ekran ---
	main_box = VBoxContainer.new()
	main_box.add_theme_constant_override("separation", 12)
	col.add_child(main_box)
	name_edit = _edit("Adın")
	name_edit.max_length = 16
	name_edit.text = _load_name()
	main_box.add_child(name_edit)
	var create := _button("Oda kur", true)
	create.pressed.connect(_on_create)
	main_box.add_child(create)
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
	var join := _button("Katıl", false)
	join.custom_minimum_size.x = 160
	join.pressed.connect(_on_join)
	row.add_child(join)
	main_box.add_child(row)
	var alone := _button("Tek başına dene", false)
	alone.pressed.connect(func() -> void: solo.emit())
	main_box.add_child(alone)
	var chr_row := HBoxContainer.new()
	chr_row.add_theme_constant_override("separation", 10)
	var chr := _button("Karakterim & Mağaza", false)
	chr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chr.pressed.connect(func() -> void:
		_player_name()
		open_character.emit())
	chr_row.add_child(chr)
	var gem_box := HBoxContainer.new()
	gem_box.add_theme_constant_override("separation", 6)
	gem_box.alignment = BoxContainer.ALIGNMENT_CENTER
	gem_box.custom_minimum_size.x = 110
	gem_box.add_child(CharacterScript.gem_icon(28))
	gems_label = _label(str(profile.gems), 28, Color("#a8f2ff"))
	gem_box.add_child(gems_label)
	chr_row.add_child(gem_box)
	main_box.add_child(chr_row)
	daily_btn = _button("Günlük ödülünü al  (+%d elmas)" % profile.DAILY_GEMS, true)
	daily_btn.visible = profile.daily_available()
	daily_btn.pressed.connect(func() -> void:
		profile.claim_daily()
		refresh_profile()
		status.text = "+%d elmas! Mağazada harcayabilirsin." % profile.DAILY_GEMS)
	main_box.add_child(daily_btn)

	# --- lobi ---
	lobby_box = VBoxContainer.new()
	lobby_box.add_theme_constant_override("separation", 12)
	lobby_box.visible = false
	col.add_child(lobby_box)
	lobby_title = _label("LOBİ", 40, Color("#ffb020"))
	lobby_box.add_child(lobby_title)
	lobby_box.add_child(_label("ODA KODU", 20, Color(0.7, 0.7, 0.74)))
	code_label = _label("----", 72, Color("#F5C542"))
	lobby_box.add_child(code_label)
	var invite := _button("WhatsApp ile davet et", true)
	invite.pressed.connect(_on_invite)
	lobby_box.add_child(invite)
	var copy := _button("Kodu kopyala", false)
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(net.room_code)
		status.text = "Kod kopyalandı: " + net.room_code)
	lobby_box.add_child(copy)
	player_list = GridContainer.new()
	player_list.columns = 4
	player_list.add_theme_constant_override("h_separation", 10)
	player_list.add_theme_constant_override("v_separation", 10)
	lobby_box.add_child(player_list)
	start_btn = _button("Oyunu başlat", true)
	start_btn.pressed.connect(func() -> void: net.send({"t": "basla"}))
	lobby_box.add_child(start_btn)
	wait_label = _label("Odayı kuranın oyunu başlatması bekleniyor…", 20, Color(0.75, 0.75, 0.78))
	lobby_box.add_child(wait_label)
	var quit := _button("Odadan çık", false)
	quit.pressed.connect(func() -> void:
		net.leave()
		_show_main())
	lobby_box.add_child(quit)

	status = _label("", 20, Color("#FF8A7A"))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(status)

	net.welcomed.connect(_show_lobby)
	net.players_changed.connect(_refresh_players)


func _load_name() -> String:
	return profile.player_name


func _player_name() -> String:
	var n := name_edit.text.strip_edges()
	if n == "":
		n = "Mahkum%d" % (randi() % 90 + 10)
		name_edit.text = n
	if n != profile.player_name:
		profile.player_name = n
		profile.save()
	return n


# Karakter ekranından dönünce ad ve elmas güncellenir.
func refresh_profile() -> void:
	name_edit.text = profile.player_name
	gems_label.text = str(profile.gems)
	daily_btn.visible = profile.daily_available()


func _on_create() -> void:
	status.text = "Oda kuruluyor…"
	net.join(net.new_code(), _player_name(), true)


func _on_join() -> void:
	var code := code_edit.text.strip_edges().to_upper()
	if code.length() != 4:
		status.text = "Oda kodu 4 harf olmalı."
		return
	status.text = "Bağlanılıyor…"
	net.join(code, _player_name(), false)


func _on_invite() -> void:
	var text := "Hat Düştü'de seni bekliyorum! Uygulamayı aç, \"Katıl\" kısmına şu kodu yaz: %s" % net.room_code
	OS.shell_open("https://wa.me/?text=" + text.uri_encode())


func _show_main() -> void:
	main_box.visible = true
	lobby_box.visible = false


func _show_lobby() -> void:
	main_box.visible = false
	lobby_box.visible = true
	status.text = ""
	code_label.text = net.room_code
	_refresh_players()


func _refresh_players() -> void:
	for ch in player_list.get_children():
		ch.queue_free()
	lobby_title.text = "LOBİ  ·  %d/8 oyuncu" % net.players.size()
	var by_cell := {}
	for p in net.players:
		by_cell[int(p.cell)] = p
	for cell in 8:
		player_list.add_child(_slot(by_cell.get(cell, {}), cell))
	start_btn.visible = net.is_host
	wait_label.visible = not net.is_host


const SLOT_COLORS := ["#F5C542", "#C8A6FF", "#FFB86B", "#7FB2FF", "#6FD3B5", "#FF8FA3", "#B8E986", "#F4A6D7"]


# Lobideki bir yer: dolu ise baş harf yuvarlağı, ad, hücre ve rozet; boşsa soluk "boş yer".
func _slot(p: Dictionary, cell: int) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(122, 128)
	var st := StyleBoxFlat.new()
	var filled := not p.is_empty()
	var me: bool = filled and int(p.id) == net.my_id
	st.bg_color = Color("#262a3a") if filled else Color(1, 1, 1, 0.03)
	st.border_color = Color("#ffb020") if me else (Color("#3d4460") if filled else Color(1, 1, 1, 0.1))
	st.set_border_width_all(3 if me else 2)
	st.set_corner_radius_all(18)
	card.add_theme_stylebox_override("panel", st)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	if not filled:
		v.add_child(_label("Boş yer", 16, Color(1, 1, 1, 0.3)))
		v.add_child(_label("hücre %d" % (11 + cell), 14, Color(1, 1, 1, 0.2)))
		return card
	var av := Panel.new()
	av.custom_minimum_size = Vector2(52, 52)
	av.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var ast := StyleBoxFlat.new()
	ast.bg_color = Color(SLOT_COLORS[cell % SLOT_COLORS.size()])
	ast.set_corner_radius_all(26)
	av.add_theme_stylebox_override("panel", ast)
	var ini := _label(str(p.name).substr(0, 1).to_upper(), 24, Color("#14161b"))
	ini.set_anchors_preset(Control.PRESET_FULL_RECT)
	ini.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	av.add_child(ini)
	v.add_child(av)
	var nm := _label(str(p.name), 17)
	nm.clip_text = true
	v.add_child(nm)
	var badge := "KURUCU" if bool(p.host) else ("SEN" if me else "hücre %d" % (11 + cell))
	v.add_child(_label(badge, 13, Color("#ffb020") if bool(p.host) else Color(0.7, 0.72, 0.8)))
	return card


func show_error(msg: String) -> void:
	_show_main()
	status.text = msg
