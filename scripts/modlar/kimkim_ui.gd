# KİM KİM?: rehberde sadece "Hat 1, Hat 2..." görünür, herkesin sesi robot. Yeşil tahtada her hattın
# yanına arkadaşının adını seçip kaydedersin. Sonda hatların kim olduğu açılır.
extends "res://scripts/modlar/mod_ui.gd"

var picks := {}  # hat numarası -> oyuncu id
var saved := false
var _chooser: Control


func _lines() -> Dictionary:
	var out := {}
	var h = secret.get("hatlar", {})
	if typeof(h) == TYPE_DICTIONARY:
		for k in h:
			out[int(k)] = int(h[k])
	return out


func my_line() -> int:
	return int(secret.get("hat", 0))


func total() -> int:
	return int(secret.get("toplam", state.get("toplam", 0)))


func contact_name(id: int) -> String:
	var l := _lines()
	return "Hat %d" % l[id] if l.has(id) else ""


func on_state(d: Dictionary, entered: bool) -> void:
	state = d
	w.voice.robot = phase() in ["anons", "telefon"]
	if not entered:
		return
	match phase():
		"anons":
			picks = {}
			saved = false
			play("anons")
		"telefon":
			close_card()
			play("sec", -6.0)
	show_main_button("TAHTA: KİM KİM?", phase() in ["anons", "telefon"])


func on_secret(d: Dictionary) -> void:
	secret = d
	w.voice.robot = true
	var big := VBoxContainer.new()
	big.add_child(chalk_line("SENİN HATTIN", 26, GOLD))
	big.add_child(chalk_line(str(my_line()), 110, Color.WHITE))
	role_card("KİM KİM?", Color("#7fe3ff"), "Rehberde isim yok, herkesin sesi ROBOT!\nTelefonla ara, konuş: hangi hat kim? Tahtada her hatta arkadaşının adını seç.",
		"En iyi tahmin +2 · ikinci en iyi +1", big)


func chalk_line(t: String, size: int, col: Color) -> Label:
	var l := UI.title(t, size, col, true)
	return l


func show_card() -> void:
	if not secret.is_empty():
		on_secret(secret)


func on_event(d: Dictionary) -> void:
	if str(d.get("tur", "")) == "kaydetti":
		state["kaydeden"] = int(d.get("kaydeden", 0))
		g._update_banner()


func banner() -> Array:
	var pn: String = {"anons": "HATLAR DAĞITILDI", "telefon": "KONUŞ VE EŞLEŞTİR"}.get(phase(), "")
	var info := "Senin hattın: %d · tahtaya kaydeden: %d/%d" % [my_line(), int(state.get("kaydeden", 0)), total()]
	if saved:
		info = "Kaydedildi! · " + info
	return ["KİM KİM?  ·  " + pn, info]


func help_rows() -> Array:
	return [
		["phone", "Rehberde isim yok: Hat 1, Hat 2... Herkesin sesi robot sesine döner."],
		["chat", "Ara, konuş, soru sor. Karşındaki yalan da söyleyebilir!"],
		["deal", "Yeşil tahtada her hattın yanına kim olduğunu seç ve kaydet."],
		["trophy", "En çok doğru bilen +2, ikinci +1."],
	]


# Tahta: her hat için bir satır; satıra dokununca isim seçici açılır.
func open_board() -> void:
	if secret.is_empty() or not (phase() in ["anons", "telefon"]):
		return
	var m := chalk_modal("Hangi hat kim?", "Satıra dokun, arkadaşının adını seç. İstediğin kadar değiştirip kaydedebilirsin.", 1040.0)
	var v: VBoxContainer = m[1]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(grid)
	var n := total()
	var rows := {}
	for i in range(1, n + 1):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var hl := chalk("Hat %d" % i, 34)
		hl.custom_minimum_size.x = 120
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(hl)
		var b := chalk_button("SEN" if i == my_line() else _pick_name(i), "", i == my_line(), 260)
		b.custom_minimum_size.y = 58 if n > 6 else 66
		if i == my_line():
			b.disabled = true
			b.modulate = Color(0.75, 1.0, 0.8)
		else:
			var line := i
			b.pressed.connect(func() -> void: _open_chooser(line, rows))
		row.add_child(b)
		rows[i] = b
		grid.add_child(row)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 22)
	var hint := chalk("Kaydedildi!" if saved else "", 26, Color(0.75, 1.0, 0.8))
	var ok := chalk_button("Kaydet", "tebesir", true, 300)
	ok.pressed.connect(func() -> void:
		var out := {}
		for k in picks:
			out[str(k)] = int(picks[k])
		g.decided.emit({"eslesme": out})
		saved = true
		hint.text = "Kaydedildi!  (%d/%d hat)" % [picks.size(), n - 1]
		chalk_sfx()
		play("sec", -4.0)
		g._update_banner())
	foot.add_child(ok)
	foot.add_child(hint)
	v.add_child(foot)


func _pick_name(line: int) -> String:
	return pname(picks[line]) if picks.has(line) else "?"


# Küçük isim seçici: adaylar + "Boş". Başka hatta seçili ad seçilirse oradan kalkar.
func _open_chooser(line: int, rows: Dictionary) -> void:
	if is_instance_valid(_chooser):
		_chooser.queue_free()
	var ov := Control.new()
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	var d := ColorRect.new()
	d.color = Color(0, 0, 0, 0.45)
	d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	d.gui_input.connect(func(e: InputEvent) -> void:
		if g._pressed(e):
			ov.queue_free())
	ov.add_child(d)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(center)
	var p := PanelContainer.new()
	var st := UI.flat(Color("#23392b"), Color(CHALK, 0.7), 18)
	st.set_border_width_all(3)
	st.content_margin_left = 26
	st.content_margin_right = 26
	st.content_margin_top = 18
	st.content_margin_bottom = 18
	p.add_theme_stylebox_override("panel", st)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(chalk("Hat %d kim?" % line, 38))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	var cands: Array = secret.get("adaylar", [])
	for c in cands:
		var id := int(c.id)
		var used_by := 0
		for k in picks:
			if int(picks[k]) == id and k != line:
				used_by = k
		var b := chalk_button(str(c.ad), "", picks.get(line, -1) == id, 260)
		if used_by:
			b.modulate = Color(1, 1, 1, 0.55)
		b.pressed.connect(func() -> void:
			for k in picks.keys():
				if int(picks[k]) == id:
					picks.erase(k)
					if rows.has(k):
						_set_chalk_text(rows[k], "?")
			picks[line] = id
			_set_chalk_text(rows[line], str(c.ad))
			saved = false
			chalk_sfx()
			ov.queue_free())
		grid.add_child(b)
	var clr := chalk_button("Boş bırak", "silgi", false, 260)
	clr.pressed.connect(func() -> void:
		picks.erase(line)
		_set_chalk_text(rows[line], "?")
		saved = false
		ov.queue_free())
	v.add_child(clr)
	panel.add_child(ov)
	_chooser = ov


# Tebeşir düğmesinin içindeki yazıyı değiştirir.
func _set_chalk_text(b: Button, t: String) -> void:
	for l in b.find_children("*", "Label", true, false):
		(l as Label).text = t


func on_result(d: Dictionary) -> void:
	w.voice.robot = false
	show_main_button("", false)
	var rows := []
	rows.append(UI.label("Hatlar açıldı:", 20, Color(0.8, 0.82, 0.9), true))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 2)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var ben = d.get("ben", {})
	var guess = ben.get("tahmin", {}) if typeof(ben) == TYPE_DICTIONARY else {}
	for h in d.get("hatlar", []):
		var n := int(h.hat)
		var me_row := int(h.id) == me()
		grid.add_child(UI.title("Hat %d" % n, 22, GOLD))
		grid.add_child(UI.title(str(h.ad) + ("  (sen)" if me_row else ""), 22, Color.WHITE))
		if me_row:
			grid.add_child(UI.label("", 20))
		else:
			var gid := int(guess.get(str(n), 0)) if typeof(guess) == TYPE_DICTIONARY else 0
			var ok := gid == int(h.id)
			grid.add_child(UI.title(("DOĞRU" if ok else ("YANLIŞ (%s)" % pname(gid) if gid else "BOŞ")), 20, GREEN if ok else RED))
	rows.append(grid)
	result_modal("KİM KİM?", rows, d)


func cleanup() -> void:
	w.voice.robot = false
	close_panel()
	close_card()
	show_main_button("", false)
