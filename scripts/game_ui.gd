# Oyun ekranları (Kara Tahta): rol kartı, üstte görev bandı, tahtaya tebeşirle yazma paneli,
# kişisel tur sonucu (puanlar gizli) ve oyun sonu puan tablosu. Kurallar sunucuda; burası gösterir ve yollar.
extends CanvasLayer

signal decided(value)
signal board_written(text: String)
signal leave_game

const UI := preload("res://scripts/ui.gd")
const Fx := preload("res://scripts/store_fx.gd")
const CHALK_FONT := preload("res://assets/fonts/CabinSketch-Bold.ttf")
const CHALK := Color(0.95, 0.96, 0.9)

var net: Node
var my_id := 0
var state := {}  # son "oyun" mesajı
var secret := {}  # son "gizli" mesajı (rolün)
var my_score := 0
var written := ""  # bu tur tahtana yazdığın
var _last_result := {}

var _root: Control
var _banner: PanelContainer
var _banner_title: Label
var _banner_info: Label
var _card: Control
var _write_btn: Button
var _panel: Control
var _overlay: Control
var _round_label: Label
var _score_label: Label
var _pill: PanelContainer


func _ready() -> void:
	layer = 12
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	# sol üst: tur ve SADECE kendi puanın
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", UI.flat(Color(0.05, 0.05, 0.08, 0.75), Color(1, 1, 1, 0.12), 22))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_round_label = UI.title("TUR 1", 22, Color("#ffcf8a"))
	row.add_child(_round_label)
	_score_label = UI.title("PUANIN 0", 22, Color("#a8f2ff"))
	row.add_child(_score_label)
	_score_label.visible = false  # tek tur: puan süre bitince belli olur
	pill.add_child(row)
	pill.position = Vector2(108, 18)
	_root.add_child(pill)
	_pill = pill
	# sayacın altında görev bandı; dokununca rol kartı yeniden açılır
	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", UI.flat(Color(0.08, 0.06, 0.04, 0.88), Color("#ffb020"), 14))
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 0)
	_banner_title = UI.title("", 18, Color("#ffcf8a"), true)
	_banner_info = UI.label("", 16, Color.WHITE, true)
	bv.add_child(_banner_title)
	bv.add_child(_banner_info)
	_banner.add_child(bv)
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.position = Vector2(-250, 78)
	_banner.custom_minimum_size = Vector2(500, 0)
	_banner.gui_input.connect(func(e: InputEvent) -> void:
		if _pressed(e):
			_show_card())
	_banner.visible = false
	_root.add_child(_banner)
	# alt orta: tahtaya yaz (telefonda tahtaya yürümeden de yazılabilsin)
	_write_btn = UI.button("TAHTAYA YAZ", "orange", 64, 22, "deal", 270)
	_write_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_write_btn.position = Vector2(-135, -100)
	_write_btn.pressed.connect(open_board)
	_write_btn.visible = false
	_root.add_child(_write_btn)
	visible = false


static func _pressed(e: InputEvent) -> bool:
	return (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed)


func _play(n: String, vol := 0.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = load("res://assets/ses/%s.ogg" % n)
	p.volume_db = vol
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _clear(c) -> void:
	if is_instance_valid(c):
		c.queue_free()


func _is_writer() -> bool:
	return bool(secret.get("yazan", false))


# Karartılmış katman + ortada metal panel. Dönen: [katman, içerik kutusu]
func _modal(min_w: float, dim := 0.6) -> Array:
	var ov := Control.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	var d := ColorRect.new()
	d.color = Color(0.01, 0.01, 0.03, dim)
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(d)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(center)
	var p := UI.panel(Vector2(min_w, 0), 30)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	_root.add_child(ov)
	p.pivot_offset = Vector2(min_w / 2, 120)
	p.scale = Vector2.ONE * 0.85
	p.create_tween().tween_property(p, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return [ov, v]


# ---------- sunucudan gelenler ----------

func on_state(d: Dictionary) -> void:
	visible = true
	_pill.visible = true
	state = d
	var phase := str(d.phase)
	_round_label.text = "KARA TAHTA"
	match phase:
		"anons":
			written = ""
			board_written.emit("")
			_clear(_panel)
			_clear(_overlay)
			_play("anons")
		"telefon":
			_clear(_card)
			_play("sec", -6.0)
			if _is_writer() and written == "":
				open_board()
	_update_banner()


func on_secret(d: Dictionary) -> void:
	secret = d
	_update_banner()
	_show_card()


func on_written(kind: String) -> void:
	_play("sec")
	if kind == "kelime":
		_banner_info.text = "Kelimen tahtada: %s · şimdi telefonla seçtiklerine söyle" % written


# Kişisel tur sonucu: kelime herkese açık, puanın sadece sana.
func on_result(d: Dictionary) -> void:
	_last_result = d
	if int(d.round) >= int(d.get("rounds", 1)):
		return  # son tur: sonucu bitiş ekranı gösterir
	_clear(_card)
	_clear(_panel)
	_write_btn.visible = false
	_banner.visible = false
	var ben = d.get("ben")
	var m := _modal(620, 0.55)
	_clear(_overlay)
	_overlay = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UI.header("SÜRE BİTTİ", 28))
	if str(d.get("word", "")) != "":
		v.add_child(UI.label("%s tahtaya şunu yazmıştı:" % str(d.writer_name), 18, Color(0.8, 0.82, 0.9), true))
		v.add_child(_chalk_label(str(d.word), 64))
	if typeof(ben) == TYPE_DICTIONARY:
		var delta := int(ben.delta)
		my_score = int(ben.score)
		_score_label.text = "PUANIN %d" % my_score
		v.add_child(UI.label(str(ben.msg), 20, Color.WHITE, true))
		if ben.has("guess"):
			v.add_child(UI.label("Senin tahminin: %s" % str(ben.guess), 17, Color(0.75, 0.77, 0.85), true))
		var col := Color("#5be37d") if delta > 0 else (Color("#ff5a5a") if delta < 0 else Color(0.8, 0.8, 0.85))
		v.add_child(UI.title("%s%d PUAN" % ["+" if delta > 0 else "", delta], 34, col, true))
		_play("odul" if delta > 0 else "hata", -2.0)

	var ok := UI.button("TAMAM", "normal", 54, 20)
	ok.pressed.connect(func() -> void: _clear(_overlay))
	v.add_child(ok)


func on_over(d: Dictionary) -> void:
	_clear(_card)
	_clear(_panel)
	_clear(_overlay)
	_write_btn.visible = false
	_banner.visible = false
	var winner := int(d.winner)
	var ov := Control.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.01, 0.03, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.add_child(dim)
	var rays := Fx.Rays.new()
	rays.color = Color("#ffb020")
	rays.set_anchors_preset(Control.PRESET_FULL_RECT)
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(rays)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 6)
	ov.add_child(v)
	var crown := UI.icon("crown", 84)
	crown.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(crown)
	var rows: Array = d.get("table", [])
	var wname := "?"
	for r in rows:
		if int(r.id) == winner:
			wname = str(r.name)
	v.add_child(UI.title("KAZANDIN!" if winner == my_id else "KAZANAN", 48, Color.WHITE, true))
	v.add_child(UI.title(wname, 42, Color("#ffcf8a"), true))
	v.add_child(UI.label("Puanlar artık açık:", 18, Color(0.8, 0.82, 0.9), true))
	# puan tablosu
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for i in rows.size():
		var r: Dictionary = rows[i]
		var me := int(r.id) == my_id
		var col := Color("#5be37d") if me else Color(0.92, 0.92, 0.95)
		grid.add_child(UI.title("%d." % (i + 1), 22, col))
		grid.add_child(UI.title(str(r.name) + ("  (sen)" if me else "") + ("  · ayrıldı" if bool(r.get("left", false)) else ""), 22, col))
		var sc := int(r.score)
		grid.add_child(UI.title("%s%d" % ["+" if sc > 0 else "", sc], 24, Color("#a8f2ff") if sc >= 0 else Color("#ff8a8a")))
	v.add_child(grid)
	if not _last_result.is_empty() and str(_last_result.get("word", "")) != "":
		var wl := HBoxContainer.new()
		wl.alignment = BoxContainer.ALIGNMENT_CENTER
		wl.add_theme_constant_override("separation", 14)
		wl.add_child(UI.label("%s tahtaya şunu yazmıştı:" % str(_last_result.writer_name), 18, Color(0.85, 0.86, 0.9)))
		wl.add_child(_chalk_label(str(_last_result.word), 44))
		v.add_child(wl)
	var ben = _last_result.get("ben")
	if typeof(ben) == TYPE_DICTIONARY:
		v.add_child(UI.label("Sen: %s  (%s%d)" % [str(ben.msg), "+" if int(ben.delta) > 0 else "", int(ben.delta)], 18, Color("#a8f2ff"), true))
	var back := UI.button("ANA MENÜYE DÖN", "primary", 64, 22, "play", 340)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void: leave_game.emit())
	v.add_child(back)
	_root.add_child(ov)
	_overlay = ov
	_play("odul" if winner == my_id else "parilti")
	if winner == my_id:
		Fx.confetti(ov, ov.get_viewport_rect().size * Vector2(0.5, 0.4), ["#ffb020", "#5be37d", "#3fd6f0", "#ffffff"])


# ---------- rol kartı ve bant ----------

func _role_text() -> String:
	if _is_writer():
		return "Tahtana gizli bir kelime yaz. Tam %d kişi bilsin." % int(secret.get("hedef", 1))
	return "Kelimeyi telefonla öğren, tahtana yaz."


func _update_banner() -> void:
	var phase := str(state.get("phase", ""))
	var live := phase in ["anons", "telefon"] and not secret.is_empty()
	_banner.visible = live
	var phase_name: String = {"anons": "ANONS", "telefon": "SÜRE İŞLİYOR"}.get(phase, "")
	_banner_title.text = "%s  ·  %s" % [str(state.get("title", "KARA TAHTA")), phase_name]
	if _is_writer():
		_banner_info.text = ("Tahtanda: %s · tam %d kişi bilsin" % [written, int(secret.hedef)]) if written != "" else "Tahtana gizli bir kelime yaz!"
	elif written != "":
		_banner_info.text = "Tahtanda: %s · süre bitene kadar değiştirebilirsin" % written
	else:
		_banner_info.text = "Yazan: %s · kelimeyi telefonla öğren, tahtana yaz" % str(secret.get("yazan_ad", "?"))
	var can_write := phase == "telefon" or (_is_writer() and phase == "anons")
	_write_btn.visible = false  # tahtaya yaklaşınca panel kendiliğinden açılır
	UI.set_button_text(_write_btn, "TAHTAYA YAZ" if written == "" else "DEĞİŞTİR")


func _show_card() -> void:
	if secret.is_empty():
		return
	_clear(_card)
	var writer := _is_writer()
	var m := _clean_modal(640)
	_card = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UI.title("SEN YAZIYORSUN" if writer else "YAZAN: %s" % str(secret.get("yazan_ad", "?")).to_upper(), 40, Color("#ffcf8a") if writer else Color("#7fe3ff"), true))
	var t := UI.label(_role_text(), 26, Color.WHITE, true)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 560
	v.add_child(t)
	v.add_child(UI.title("Tutarsa +2 · tutmazsa -1" if writer else "Bilirsen +1 · bilemezsen -1", 24, Color("#5be37d"), true))
	var ok := UI.button("TAMAM", "primary", 64, 24)
	ok.pressed.connect(func() -> void: _clear(_card))
	v.add_child(ok)


# Sade, okunaklı pencere: düz koyu zemin, ince çerçeve (dokulu panel göz yoruyordu).
func _clean_modal(min_w: float) -> Array:
	var ov := Control.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	var d := ColorRect.new()
	d.color = Color(0.0, 0.0, 0.02, 0.7)
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(d)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(center)
	var p := PanelContainer.new()
	var st := UI.flat(Color("#12141a"), Color("#3a3f4c"), 22)
	st.set_border_width_all(2)
	st.content_margin_left = 40
	st.content_margin_right = 40
	st.content_margin_top = 30
	st.content_margin_bottom = 30
	p.add_theme_stylebox_override("panel", st)
	p.custom_minimum_size.x = min_w
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	p.add_child(v)
	_root.add_child(ov)
	p.pivot_offset = Vector2(min_w / 2, 120)
	p.scale = Vector2.ONE * 0.9
	p.create_tween().tween_property(p, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return [ov, v]


# ---------- bilgisayar: oyunun amacı ----------

func show_help() -> void:
	visible = true
	_pill.visible = not state.is_empty()  # oyun dışında (tek başına) üst yazı görünmesin
	_clear(_overlay)
	var m := _clean_modal(720)
	_overlay = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UI.title("KARA TAHTA", 44, Color("#7dff9f"), true))
	var rows := [
		["trophy", "En çok puanı topla."],
		["crown", "Yazan: tahtaya gizli kelime yazar. Tam hedef kadar kişi bilirse +2."],
		["phone", "Diğerleri: telefonla öğrenir, tahtasına yazar. Bilen +1, bilemeyen -1."],
		["lock", "240 saniye. Puanlar sonda açılır. Herkes yalan söyleyebilir!"],
	]
	for r in rows:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 18)
		h.add_child(UI.icon(r[0], 54))
		var l := UI.label(r[1], 24, Color(0.95, 0.96, 0.98))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 560
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(l)
		v.add_child(h)
	var ok := UI.button("ANLADIM", "primary", 64, 24)
	ok.pressed.connect(func() -> void:
		_clear(_overlay)
		if state.is_empty():
			visible = false)
	v.add_child(ok)
	_play("sec")


# ---------- tahtaya yazma ----------

func _chalk_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", CHALK_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", CHALK)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


# Yeşil tahta görünümlü panel: tebeşir yazılı kutu, YAZ düğmesi.
func open_board() -> void:
	var phase := str(state.get("phase", ""))
	var can_write := phase == "telefon" or (_is_writer() and phase == "anons")
	if not can_write:
		return
	_clear(_panel)
	var ov := Control.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	var d := ColorRect.new()
	d.color = Color(0.01, 0.01, 0.03, 0.6)
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.add_child(d)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.add_child(center)
	var board := PanelContainer.new()
	var bst := UI.flat(Color("#2c4a35"), Color("#6b4a2b"), 10)
	bst.set_border_width_all(18)
	bst.content_margin_left = 40
	bst.content_margin_right = 40
	bst.content_margin_top = 26
	bst.content_margin_bottom = 26
	bst.shadow_color = Color(0, 0, 0, 0.6)
	bst.shadow_size = 18
	board.add_theme_stylebox_override("panel", bst)
	board.custom_minimum_size = Vector2(760, 0)
	center.add_child(board)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	board.add_child(v)
	v.add_child(_chalk_label("Gizli kelimeni yaz" if _is_writer() else "Tahminini yaz", 40))
	var e := LineEdit.new()
	e.text = written
	e.max_length = 16
	e.placeholder_text = "örn. elma"
	e.alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.add_theme_font_override("font", CHALK_FONT)
	e.add_theme_font_size_override("font_size", 72)
	e.add_theme_color_override("font_color", CHALK)
	e.add_theme_color_override("font_placeholder_color", Color(CHALK, 0.3))
	e.add_theme_color_override("caret_color", CHALK)
	var est := StyleBoxFlat.new()
	est.bg_color = Color(0, 0, 0, 0.12)
	est.border_color = Color(CHALK, 0.35)
	est.border_width_bottom = 3
	est.content_margin_top = 8
	est.content_margin_bottom = 8
	e.add_theme_stylebox_override("normal", est)
	e.add_theme_stylebox_override("focus", est)
	e.custom_minimum_size = Vector2(0, 110)
	v.add_child(e)
	var hint := _chalk_label("İstediğin kadar yazıp silebilirsin.", 26)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate.a = 0.7
	v.add_child(hint)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	var ok := UI.button("KAYDET", "primary", 62, 24, "", 220)
	var erase := UI.button("SİL", "red", 62, 20, "", 140)
	var cancel := UI.button("KAPAT", "normal", 62, 20, "", 160)
	row.add_child(ok)
	row.add_child(erase)
	row.add_child(cancel)
	erase.pressed.connect(func() -> void:
		e.text = ""
		e.grab_focus())
	v.add_child(row)
	var submit := func() -> void:
		var t := e.text.strip_edges()
		if t.length() < 2:
			hint.text = "En az 2 harf yaz."
			hint.modulate.a = 1.0
			return
		written = t.to_upper()
		board_written.emit(written)
		decided.emit(t)
		_clear(_panel)
		_update_banner()
	ok.pressed.connect(submit)
	e.text_submitted.connect(func(_t: String) -> void: submit.call())
	# yazarken tebeşir sesi
	var chalk := AudioStreamPlayer.new()
	var rnd := AudioStreamRandomizer.new()
	for i in 3:
		rnd.add_stream(-1, load("res://assets/ses/tebesir_%d.ogg" % (i + 1)))
	rnd.random_pitch = 1.15
	chalk.stream = rnd
	chalk.volume_db = -6.0
	ov.add_child(chalk)
	e.text_changed.connect(func(_t: String) -> void: chalk.play())
	cancel.pressed.connect(func() -> void: _clear(_panel))
	_root.add_child(ov)
	_panel = ov
	e.grab_focus.call_deferred()
