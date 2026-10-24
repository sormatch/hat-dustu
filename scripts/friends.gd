# Arkadaşlarım ekranı: kullanıcı adını seç, @kullanıcıadı ile istek gönder, gelenleri kabul et, lobiye davet et.
extends CanvasLayer

const CharacterScript := preload("res://scripts/character.gd")
const UI := preload("res://scripts/ui.gd")

var account: Node
var profile: Node
var net: Node
var _body: VBoxContainer
var _msg: Label


func _label(text: String, size := 20, color := Color(0.93, 0.93, 0.96)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.clip_text = true
	return l


func _edit(placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.max_length = 17
	e.custom_minimum_size = Vector2(0, 50)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_size_override("font_size", 21)
	return e


func _btn(text: String, primary: bool, on: Callable, w := 120.0) -> Button:
	var b := CharacterScript.styled_button(text, primary, 18, 44)
	b.custom_minimum_size.x = w
	b.pressed.connect(on)
	return b


func _ready() -> void:
	layer = 16
	add_child(UI.background("bg_lobby", 0.55))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UI.panel(Vector2.ZERO, 34)
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#141626")
	st.border_color = Color("#ffcf8a")
	st.set_border_width_all(2)
	st.border_width_top = 6
	st.set_corner_radius_all(24)
	st.content_margin_left = 22
	st.content_margin_right = 22
	st.content_margin_top = 16
	st.content_margin_bottom = 18
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var head := HBoxContainer.new()
	var t := UI.title("ARKADAŞLARIM", 34, Color("#ffcf8a"))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(_btn("Kapat", true, queue_free))
	col.add_child(head)
	_msg = _label("", 18, Color("#5be37d"))
	col.add_child(_msg)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(700, 460)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(sc)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	sc.add_child(_body)
	account.list_changed.connect(_refresh)
	account.me_changed.connect(_refresh)
	account.message.connect(func(m: String) -> void: _msg.text = m)
	account.send({"t": "liste"})
	_refresh()


func _section(title: String, color: Color) -> VBoxContainer:
	var card := PanelContainer.new()
	var cst := UI.flat(Color(0.05, 0.05, 0.07, 0.55), Color(color, 0.5), 12)
	cst.border_width_top = 2
	cst.border_width_left = 5
	card.add_theme_stylebox_override("panel", cst)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(UI.icon({"Gelen": "invite", "Arka": "friends", "Gönd": "invite"}.get(title.substr(0, 5), "profile"), 40))
	h.add_child(UI.title(title, 22, color))
	v.add_child(h)
	card.add_child(v)
	_body.add_child(card)
	return v

func _person(parent: Control, f: Dictionary, sub: String, buttons: Array) -> void:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 10)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(14, 14)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color("#5be37d") if f.get("online", false) else Color("#59606e")
	ds.set_corner_radius_all(7)
	dot.add_theme_stylebox_override("panel", ds)
	r.add_child(dot)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", -2)
	tv.add_child(_label(str(f.get("name", f.handle)), 20))
	tv.add_child(_label("@%s%s" % [f.handle, sub], 15, Color(0.7, 0.72, 0.8)))
	r.add_child(tv)
	for b in buttons:
		r.add_child(b)
	parent.add_child(r)


func _refresh() -> void:
	for ch in _body.get_children():
		ch.queue_free()
	if account.handle == "":
		var s := _section("Kullanıcı adını seç", Color("#ffb020"))
		s.add_child(_label("Arkadaşların seni bu adla bulur: küçük harf, rakam, _ ve . (3-16 karakter)", 15, Color(0.75, 0.77, 0.85)))
		var row := HBoxContainer.new()
		var e := _edit("@kullanıcıadı")
		row.add_child(e)
		row.add_child(_btn("Kaydet", true, func() -> void: account.register(e.text, profile.player_name)))
		s.add_child(row)
		if not account.connected:
			s.add_child(_label("Sunucuya bağlanılıyor…", 15, Color("#ff9a8a")))
		return
	var me := _section("Senin kullanıcı adın:  @" + account.handle, Color("#ffb020"))
	var add := HBoxContainer.new()
	var e2 := _edit("Arkadaşının @kullanıcıadı")
	add.add_child(e2)
	add.add_child(_btn("İstek gönder", true, func() -> void:
		if e2.text.strip_edges() != "":
			account.send({"t": "istek", "handle": e2.text})
			e2.text = "", 160))
	me.add_child(add)

	if account.incoming.size() > 0:
		var inc := _section("Gelen istekler (%d)" % account.incoming.size(), Color("#5be37d"))
		for f in account.incoming:
			var h: String = f.handle
			_person(inc, f, " seninle arkadaş olmak istiyor", [
				_btn("Kabul", true, func() -> void: account.send({"t": "kabul", "handle": h}), 100),
				_btn("Reddet", false, func() -> void: account.send({"t": "reddet", "handle": h}), 100),
			])

	var fr := _section("Arkadaşlar  ·  %d çevrimiçi" % account.online_count(), Color("#3b9cff"))
	if account.friends.is_empty():
		fr.add_child(_label("Henüz arkadaşın yok. Yukarıdan @kullanıcıadı yazıp istek gönder.", 16, Color(1, 1, 1, 0.5)))
	var in_room: bool = net.connected
	for f in account.friends:
		var h: String = f.handle
		var sub: String = (" · lobide" if str(f.room) != "" else " · çevrimiçi") if f.online else " · çevrimdışı"
		var btns := []
		if in_room and f.online:
			btns.append(_btn("Lobiye davet", true, func() -> void: account.send({"t": "davet", "handle": h, "oda": net.room_code}), 150))
		btns.append(_btn("Sil", false, func() -> void: account.send({"t": "sil", "handle": h}), 70))
		_person(fr, f, sub, btns)

	if account.outgoing.size() > 0:
		var out := _section("Gönderilen istekler", Color("#b05cff"))
		for f in account.outgoing:
			var h: String = f.handle
			_person(out, f, " · yanıt bekleniyor", [_btn("İptal", false, func() -> void: account.send({"t": "reddet", "handle": h}), 90)])
