# Yeni mini oyunların ekranları için ortak taban. Her oyun (Kim Kim?, Yalancı, Rus Ruleti, C4, Ortalama)
# bundan türer; game_ui.gd sunucudan geleni buraya iletir, main.gd 3D etkileşimleri (hedefler, kapılar) sorar.
extends Node

const UI := preload("res://scripts/ui.gd")
const CHALK_FONT := preload("res://assets/fonts/CabinSketch-Bold.ttf")
const CHALK := Color(0.95, 0.96, 0.9)
const GREEN := Color("#5be37d")
const RED := Color("#ff5a5a")
const GOLD := Color("#ffcf8a")

var g: CanvasLayer  # game_ui.gd
var w: Node3D  # main.gd
var task := ""
var state := {}
var secret := {}
var panel: Control  # açık tahta / pencere
var card: Control  # rol kartı


# ---------- türeyenlerin dolduracağı ----------

func on_state(_d: Dictionary, _entered: bool) -> void:
	pass


func on_secret(_d: Dictionary) -> void:
	pass


func on_event(_d: Dictionary) -> void:
	pass


func on_result(d: Dictionary) -> void:
	result_modal(str(d.get("title", "")), [], d)


func open_board() -> void:
	pass


func banner() -> Array:
	return [str(state.get("title", "")), ""]


func help_rows() -> Array:
	return []


func show_card() -> void:
	pass


# main.gd etkileşim hedefleri: [ad, dünya konumu, en uzak mesafe, düğme yazısı]
func targets(_cell: int) -> Array:
	return []


func do_action(_name: String) -> void:
	pass


func doors_open() -> bool:
	return false


# true: oyuncu oturduğu yerden kalkamaz (rulette masa)
func locks_seat() -> bool:
	return false


# Rehberde ve aramada görünen ad ("" ise gerçek ad)
func contact_name(_id: int) -> String:
	return ""


func process(_delta: float) -> void:
	pass


# oyun bitti ya da sıradakine geçildi: 3D eklentileri, sesleri temizle
func cleanup() -> void:
	pass


# ---------- yardımcılar ----------

func me() -> int:
	return int(g.my_id)


func phase() -> String:
	return str(state.get("phase", ""))


func pname(id) -> String:
	return g.net.player_name(int(id)) if g.net else "Oyuncu %d" % int(id)


func play(n: String, vol := 0.0) -> void:
	g._play(n, vol)


func flash(title: String, sub: String, col: Color, t := 1.6) -> void:
	g._flash(title, sub, col, t)


func root() -> Control:
	return g._root


func close_panel() -> void:
	if is_instance_valid(panel):
		panel.queue_free()
	panel = null


func close_card() -> void:
	if is_instance_valid(card):
		card.queue_free()
	card = null


func chalk(text: String, size: int, col := CHALK) -> Label:
	var l: Label = g._chalk_label(text, size)
	l.add_theme_color_override("font_color", col)
	return l


func chalk_button(text: String, icon_kind: String, filled: bool, wd: float) -> Button:
	return g._chalk_button(text, icon_kind, filled, wd)


# Rol kartı: başlık, açıklama, puan satırı, TAMAM.
func role_card(title: String, col: Color, body: String, points: String, extra: Control = null) -> void:
	close_card()
	var m: Array = g._clean_modal(700)
	card = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UI.title(title, 42, col, true))
	if extra:
		extra.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(extra)
	var t := UI.label(body, 24, Color.WHITE, true)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 620
	v.add_child(t)
	if points != "":
		v.add_child(UI.title(points, 22, GREEN, true))
	var ok := UI.button("TAMAM", "primary", 64, 24)
	ok.pressed.connect(close_card)
	v.add_child(ok)


# Ahşap çerçeveli kara tahta penceresi. Dönen: [katman, içerik kutusu]
func chalk_modal(title: String, sub := "", bw := 1000.0) -> Array:
	close_panel()
	var ov := Control.new()
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	var d := ColorRect.new()
	d.color = Color(0.01, 0.01, 0.03, 0.65)
	d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ov.add_child(d)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ov.add_child(center)
	var bh := bw * 905.0 / 1476.0
	var board := Control.new()
	board.custom_minimum_size = Vector2(bw, bh)
	center.add_child(board)
	var src: Texture2D = load("res://assets/ui/chalkboard.png")
	var at := AtlasTexture.new()
	at.atlas = src
	at.region = Rect2(30, 50, 1476, 905)
	var tr := TextureRect.new()
	tr.texture = at
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.add_child(tr)
	var inner := MarginContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.add_theme_constant_override("margin_left", int(bw * 0.08))
	inner.add_theme_constant_override("margin_right", int(bw * 0.08))
	inner.add_theme_constant_override("margin_top", int(bh * 0.1))
	inner.add_theme_constant_override("margin_bottom", int(bh * 0.1))
	board.add_child(inner)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	inner.add_child(v)
	var head := HBoxContainer.new()
	var tl := chalk(title, 44)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	var close := Button.new()
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(54, 54)
	var cx = g.ChalkDraw.new()
	cx.kind = "carpi"
	cx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	close.add_child(cx)
	close.pressed.connect(close_panel)
	head.add_child(close)
	v.add_child(head)
	if sub != "":
		var sl := chalk(sub, 23)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		sl.modulate.a = 0.75
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(sl)
	root().add_child(ov)
	panel = ov
	board.pivot_offset = Vector2(bw, bh) / 2.0
	board.scale = Vector2.ONE * 0.92
	board.modulate.a = 0.0
	var tin := board.create_tween().set_parallel()
	tin.tween_property(board, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tin.tween_property(board, "modulate:a", 1.0, 0.15)
	return [ov, v]


func chalk_sfx() -> void:
	play("tebesir_%d" % (randi() % 3 + 1), -6.0)


# Oyun sonu penceresi: başlık, oyuna özel satırlar, kendi sonucun ve puanın.
func result_modal(title: String, rows: Array, d: Dictionary) -> VBoxContainer:
	g.clear_flashes()
	close_panel()
	close_card()
	var m: Array = g._clean_modal(720)
	g._clear(g._overlay)
	g._overlay = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UI.title(title, 44, GOLD, true))
	for r in rows:
		v.add_child(r)
	var ben = d.get("ben")
	if typeof(ben) == TYPE_DICTIONARY:
		var delta := int(ben.get("delta", 0))
		g.my_score = int(ben.get("score", g.my_score))
		g._score_label.text = "PUANIN %d" % g.my_score
		var ml := UI.label(str(ben.get("msg", "")), 22, Color("#a8f2ff"), true)
		ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ml.custom_minimum_size.x = 640
		v.add_child(ml)
		var col := GREEN if delta > 0 else (RED if delta < 0 else Color(0.8, 0.8, 0.85))
		v.add_child(UI.title("%s%d PUAN" % ["+" if delta > 0 else "", delta], 34, col, true))
		play("odul" if delta > 0 else "hata", -2.0)
	var ok := UI.button("TAMAM", "primary", 60, 22)
	ok.pressed.connect(func() -> void: g._clear(g._overlay))
	v.add_child(ok)
	return v


func label(text: String, size := 22, col := Color.WHITE) -> Label:
	var l := UI.label(text, size, col, true)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 620
	return l


# Ekranı bir an bir renge boyar (patlama, vuruş).
func screen_flash(col: Color, peak: float, t_in: float, t_out: float) -> ColorRect:
	var f := ColorRect.new()
	f.color = Color(col, 0.0)
	f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root().add_child(f)
	var tw := f.create_tween()
	tw.tween_property(f, "color:a", peak, t_in)
	tw.tween_property(f, "color:a", 0.0, t_out)
	tw.tween_callback(f.queue_free)
	return f


# Alt ortadaki büyük düğme (TAHTA, SAYI YAZ...): game_ui'nin düğmesi kullanılır.
func show_main_button(text: String, on: bool) -> void:
	g._write_btn.visible = on
	if on:
		UI.set_button_text(g._write_btn, text)


# Türkçe büyük harf (i → İ, ı → I).
static func up(s: String) -> String:
	return s.replace("i", "İ").replace("ı", "I").to_upper()


# Türkçe ekler (ünlü uyumu): Ali'ye, Bora'da, Cem'in, Fatih'ten...
static func _last_vowel(s: String) -> String:
	var low := s.replace("I", "ı").replace("İ", "i").to_lower()
	for i in range(low.length() - 1, -1, -1):
		if low[i] in "aeıioöuü":
			return low[i]
	return "e"


static func _ends_vowel(s: String) -> bool:
	return s != "" and s.replace("I", "ı").replace("İ", "i").to_lower()[s.length() - 1] in "aeıioöuü"


static func _hard(s: String) -> bool:
	return s != "" and s.to_lower()[s.length() - 1] in "fstkçşhp"


static func dat(s: String) -> String:  # yönelme: Ali'ye
	var v := "a" if _last_vowel(s) in "aıou" else "e"
	return s + "'" + ("y" if _ends_vowel(s) else "") + v


static func loc(s: String) -> String:  # bulunma: Ali'de
	var v := "a" if _last_vowel(s) in "aıou" else "e"
	return s + "'" + ("t" if _hard(s) else "d") + v


static func abl(s: String) -> String:  # ayrılma: Ali'den
	return loc(s) + "n"


static func gen(s: String) -> String:  # ilgi: Ali'nin
	var lv := _last_vowel(s)
	var v: String = {"a": "ı", "ı": "ı", "o": "u", "u": "u", "e": "i", "i": "i", "ö": "ü", "ü": "ü"}.get(lv, "i")
	return s + "'" + ("n" if _ends_vowel(s) else "") + v + "n"
