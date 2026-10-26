# KİM KİM?: rehberde sadece "Hat 1, Hat 2..." görünür, herkesin sesi robot. Yeşil tahtada her hattın
# yanına arkadaşının adını seçip kaydedersin. Sonda hatların kim olduğu açılır.
extends "res://scripts/modlar/mod_ui.gd"

var picks := {}  # hat numarası -> oyuncu id
var saved := false
var _chooser: Control


# Rehber: kendi hattın dışındaki hatlar; telefon onları takma kimlikle (100 + hat) arar.
func contacts() -> Array:
	var out := []
	for n in range(1, total() + 1):
		if n != my_line():
			out.append({"id": 100 + n, "name": "Hat %d" % n})
	return out


func my_line() -> int:
	return int(secret.get("hat", 0))


func total() -> int:
	return int(secret.get("toplam", state.get("toplam", 0)))


func contact_name(id: int) -> String:
	return "Hat %d" % (id - 100) if id > 100 else ""


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
	show_main_button("EŞLEŞTİR", phase() in ["anons", "telefon"])


func on_secret(d: Dictionary) -> void:
	secret = d
	w.voice.robot = true
	role_card("KİM KİM?", UI.MAVI, "İsimler gizli, sesler robot. Ara, kim kim bul!", "", big_value("SENİN HATTIN", str(my_line()), UI.AMBER, "telefon"))


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
	var info := "Hattın: %d · %d/%d kaydetti" % [my_line(), int(state.get("kaydeden", 0)), total()]
	match phase():
		"anons":
			return ["HATLAR DAĞITILDI", "Hattın: %d" % my_line()]
		"telefon":
			return ["KAYDEDİLDİ" if saved else "ARA VE EŞLEŞTİR", info]
	return ["", ""]


func help_rows() -> Array:
	return [
		["telefon", "İsim yok: Hat 1, Hat 2..."],
		["mikrofon", "Sesler robot, yalan serbest"],
		["tahta", "Hangi hat kim: tahtada eşleştir"],
	]


# Tahta: her hat için bir satır (tebeşir ahize, "Hat N", ok, isim kutusu); kutuya dokununca isim seçici açılır.
func open_board() -> void:
	if secret.is_empty() or not (phase() in ["anons", "telefon"]):
		return
	var m := chalk_modal("Hangi hat kim?", "", 1040.0)
	var v: VBoxContainer = m[1]
	var n := total()
	var sp0 := Control.new()
	sp0.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp0)
	var grid := GridContainer.new()
	grid.columns = 2 if n > 4 else 1
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 4 if n > 6 else 10)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(grid)
	var rows := {}
	var rh := 64.0 if n > 6 else 72.0
	var bw := 250.0 if n > 4 else 320.0
	for i in range(1, n + 1):
		var mine := i == my_line()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var ic := chalk_draw("ahize", Vector2(40, 34), OI.CHALK_SARI if mine else CHALK)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
		var hl := chalk("Hat %d" % i, 36, OI.CHALK_SARI if mine else CHALK)
		hl.custom_minimum_size.x = 112
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(hl)
		var ok_ic := chalk_draw("ok", Vector2(44, 30))
		ok_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ok_ic.modulate.a = 0.6
		row.add_child(ok_ic)
		var b := chalk_button("SEN" if mine else _pick_name(i), "", picks.has(i), bw, rh, OI.CHALK_SARI if mine else CHALK)
		if mine:
			b.disabled = true
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
	foot.add_theme_constant_override("separation", UI.B_L)
	var ok := chalk_button("Kaydet", "tebesir", true, 300, 80)
	var tik := chalk_draw("onay", Vector2(56, 56), OI.CHALK_YESIL)
	tik.visible = saved
	ok.pressed.connect(func() -> void:
		var out := {}
		for k in picks:
			out[str(k)] = int(picks[k])
		g.decided.emit({"eslesme": out})
		saved = true
		tik.visible = true
		tik.pivot_offset = Vector2(28, 28)
		tik.scale = Vector2.ONE * 1.6
		tik.create_tween().tween_property(tik, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		chalk_sfx()
		play("sec", -4.0)
		g._update_banner())
	foot.add_child(ok)
	foot.add_child(tik)
	v.add_child(foot)


func _pick_name(line: int) -> String:
	return pname(picks[line]) if picks.has(line) else "?"


# İsim seçici: tahtanın üstünde küçük ikinci bir kara tahta; adaylar tebeşir kutularında + silgi ("boş").
# Başka hatta seçili ad seçilirse oradan kalkar.
func _open_chooser(line: int, rows: Dictionary) -> void:
	if is_instance_valid(_chooser):
		_chooser.queue_free()
	var ov := Control.new()
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	var d := ColorRect.new()
	d.color = Color(0, 0, 0, 0.5)
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
	var st := UI.flat(Color("#25402e"), Color("#7a5230"), 10)
	st.set_border_width_all(14)
	st.border_color = Color("#7a5230")
	st.shadow_size = 30
	st.shadow_color = Color(0, 0, 0, 0.6)
	st.content_margin_left = 40
	st.content_margin_right = 40
	st.content_margin_top = 24
	st.content_margin_bottom = 28
	p.add_theme_stylebox_override("panel", st)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UI.B_S)
	p.add_child(v)
	var hv := HBoxContainer.new()
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	hv.add_theme_constant_override("separation", 12)
	hv.add_child(chalk_draw("ahize", Vector2(48, 40)))
	hv.add_child(chalk("Hat %d kim?" % line, 44))
	v.add_child(hv)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", UI.B_S)
	grid.add_theme_constant_override("v_separation", UI.B_S)
	v.add_child(grid)
	var cands: Array = secret.get("adaylar", [])
	for c in cands:
		var id := int(c.id)
		var used_by := 0
		for k in picks:
			if int(picks[k]) == id and k != line:
				used_by = k
		var b := chalk_button(str(c.ad), "kisi", picks.get(line, -1) == id, 290, 76)
		if used_by:
			b.modulate = Color(1, 1, 1, 0.5)
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
	var clr := chalk_button("Boş", "silgi", false, 220, 70)
	clr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	clr.modulate.a = 0.85
	clr.pressed.connect(func() -> void:
		picks.erase(line)
		_set_chalk_text(rows[line], "?")
		saved = false
		ov.queue_free())
	v.add_child(clr)
	panel.add_child(ov)
	_chooser = ov
	p.pivot_offset = Vector2(320, 160)
	p.scale = Vector2.ONE * 0.85
	p.create_tween().tween_property(p, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	chalk_sfx()


# Tebeşir düğmesinin içindeki yazıyı değiştirir; seçili hat taramalı (dolu) görünür.
func _set_chalk_text(b: Button, t: String) -> void:
	OI.chalk_set_text(b, t)
	OI.chalk_set_filled(b, t != "?")


func on_result(d: Dictionary) -> void:
	w.voice.robot = false
	show_main_button("", false)
	var ben = d.get("ben", {})
	var guess = ben.get("tahmin", {}) if typeof(ben) == TYPE_DICTIONARY else {}
	var total := 0
	var right := 0
	var items := []
	for h in d.get("hatlar", []):
		var mine := int(h.id) == me()
		var it := {"a": "HAT %d" % int(h.hat), "b": str(h.ad), "c": "SEN", "col": Color("#5ff0ff"), "me": mine}
		if not mine:
			total += 1
			var gid := int(guess.get(str(int(h.hat)), 0)) if typeof(guess) == TYPE_DICTIONARY else 0
			if gid == int(h.id):
				right += 1
				it.c = "DOĞRU"
				it.col = GREEN
			else:
				it.c = "YANLIŞ" if gid else "BOŞ"
				it.col = RED
		items.append(it)
	result_modal("%d / %d HAT BİLDİN" % [right, total], GREEN if right > 0 else RED, ["Hatlar açıldı"], d, items, 1 if right > 0 else -1)


func cleanup() -> void:
	w.voice.robot = false
	close_panel()
	close_card()
	show_main_button("", false)
