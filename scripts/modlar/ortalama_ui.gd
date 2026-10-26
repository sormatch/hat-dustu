# ORTALAMA SAYI: 3 el. Her elde tahtaya gizlice 0-100 arası bir sayı yazılır. Elin sonunda tüm sayılar
# tebeşirle tek tek açılır, ortalama ve yarısı hesaplanır; yarısına en yakın olan eli kazanır.
extends "res://scripts/modlar/mod_ui.gd"

var number := ""  # tuş takımında yazılan
var saved := -1  # bu elde kaydedilen sayı
var hand := 0


func on_state(d: Dictionary, entered: bool) -> void:
	state = d
	hand = int(d.get("el", hand))
	if not entered:
		return
	var ph := phase()
	if ph == "anons":
		play("anons")
		g.get_tree().create_timer(0.6).timeout.connect(show_card)
	elif ph.begins_with("yaz"):
		close_card()
		g._clear(g._overlay)
		number = ""
		saved = -1
		play("sec", -4.0)
		open_board()
	elif ph.begins_with("goster"):
		close_panel()
	show_main_button("SAYI YAZ", ph.begins_with("yaz"))


func show_card() -> void:
	role_card("ORTALAMA SAYI", UI.MAVI, "0-100 arası bir sayı yaz. Ortalamanın yarısına en yakın kazanır.")


# Tuş takımı tahtası: solda kocaman tebeşir sayı, sağda elle çizilmiş tuşlar. Yazı yok denecek kadar az.
func open_board() -> void:
	if not phase().begins_with("yaz"):
		return
	var m := chalk_modal("Sayını yaz", "", 960.0)
	var v: VBoxContainer = m[1]
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 48)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	var left := VBoxContainer.new()
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 0)
	left.custom_minimum_size.x = 300
	var aralik := chalk("0 - 100", 26)
	aralik.modulate.a = 0.6
	left.add_child(aralik)
	var disp := chalk(number if number != "" else "_", 150)
	disp.custom_minimum_size.y = 170
	left.add_child(disp)
	var line := chalk_draw("cizgi", Vector2(260, 10))
	left.add_child(line)
	var hint := chalk((tr("Tahtada: %d") % saved) if saved >= 0 else "", 28, OI.CHALK_YESIL)
	hint.custom_minimum_size.y = 44
	left.add_child(hint)
	row.add_child(left)
	var pad := GridContainer.new()
	pad.columns = 3
	pad.add_theme_constant_override("h_separation", 10)
	pad.add_theme_constant_override("v_separation", 8)
	pad.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pad)
	var refresh := func() -> void:
		disp.text = number if number != "" else "_"
		disp.pivot_offset = disp.size / 2.0
		var tw := disp.create_tween()
		tw.tween_property(disp, "scale", Vector2.ONE * 1.08, 0.05)
		tw.tween_property(disp, "scale", Vector2.ONE, 0.12)
	for k in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "sil", "0", "ok"]:
		var key: String = k
		var b: Button
		if key == "sil":
			b = chalk_button("", "silgi", false, 100, 72)
		elif key == "ok":
			b = chalk_button("", "onay", true, 100, 72, OI.CHALK_YESIL)
		else:
			b = chalk_button(key, "", false, 100, 72)
		b.pressed.connect(func() -> void:
			if key == "sil":
				number = number.substr(0, maxi(0, number.length() - 1))
			elif key == "ok":
				if number == "" or int(number) > 100:
					hint.text = "0-100 arası!"
					hint.add_theme_color_override("font_color", OI.CHALK_KIRMIZI)
					play("hata", -10.0)
					return
				saved = int(number)
				g.decided.emit({"sayi": saved})
				hint.text = tr("Tahtada: %d") % saved
				hint.add_theme_color_override("font_color", OI.CHALK_YESIL)
				play("sec", -4.0)
				g._update_banner()
				g.get_tree().create_timer(0.5).timeout.connect(close_panel)
				return
			else:
				if number == "0":
					number = ""
				if number.length() < 3:
					number += key
				if int(number) > 100:
					number = "100"
			chalk_sfx()
			refresh.call())
		pad.add_child(b)


func on_event(d: Dictionary) -> void:
	match str(d.get("tur", "")):
		"yazdi":
			state["yazan"] = int(d.get("yazan", 0))
			g._update_banner()
		"goster":
			_reveal(d)


# El sonucu: sayılar tebeşirle tek tek yazılır, sonra "ortalama ÷ 2 = hedef" ve en yakın(lar) daireye alınır.
# Puan yazmaz (puanlar maç sonuna kadar gizli).
func _reveal(d: Dictionary) -> void:
	close_panel()
	var m := chalk_modal("Sonuç", "", 1000.0)
	var v: VBoxContainer = m[1]
	var grid := GridContainer.new()
	var sayilar: Array = d.get("sayilar", [])
	grid.columns = 4 if sayilar.size() > 3 else maxi(2, sayilar.size() * 2)
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 0)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(grid)
	var winners: Array = d.get("kazananlar", []).map(func(x) -> int: return int(x))
	var cells := []
	for s in sayilar:
		var id := int(s.id)
		var nm := chalk(("SEN" if id == me() else str(s.ad)), 30, OI.CHALK_SARI if id == me() else CHALK)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var num := chalk("-" if s.sayi == null else str(int(s.sayi)), 46)
		num.custom_minimum_size = Vector2(96, 60)
		var ring := chalk_draw("daire", Vector2(96, 60), OI.CHALK_YESIL)
		ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ring.visible = false
		num.add_child(ring)
		nm.modulate.a = 0.0
		num.modulate.a = 0.0
		grid.add_child(nm)
		grid.add_child(num)
		cells.append([nm, num, id in winners, ring])
	var sp := Control.new()
	sp.custom_minimum_size.y = 6
	v.add_child(sp)
	var eq := HBoxContainer.new()
	eq.alignment = BoxContainer.ALIGNMENT_CENTER
	eq.add_theme_constant_override("separation", 18)
	var ort := chalk("", 44)
	var bol := chalk("/ 2 =", 44)
	var hed := chalk("", 64, OI.CHALK_SARI)
	for c in [ort, bol, hed]:
		(c as Control).modulate.a = 0.0
		eq.add_child(c)
	v.add_child(eq)
	var res := HBoxContainer.new()
	res.alignment = BoxContainer.ALIGNMENT_CENTER
	res.add_theme_constant_override("separation", 12)
	var star := chalk_draw("tac", Vector2(54, 40), OI.CHALK_YESIL)
	star.modulate.a = 0.0
	var rl := chalk("", 34, OI.CHALK_YESIL)
	res.add_child(star)
	res.add_child(rl)
	v.add_child(res)
	var tw := v.create_tween()
	for c in cells:
		tw.tween_interval(0.28)
		tw.tween_callback(func() -> void:
			c[0].modulate.a = 1.0
			c[1].modulate.a = 1.0
			chalk_sfx())
	tw.tween_interval(0.45)
	tw.tween_callback(func() -> void:
		ort.text = _fmt(d.get("ortalama", 0))
		hed.text = _fmt(d.get("hedef", 0))
		ort.modulate.a = 1.0
		chalk_sfx())
	tw.tween_interval(0.3)
	tw.tween_callback(func() -> void:
		bol.modulate.a = 1.0
		hed.modulate.a = 1.0
		hed.pivot_offset = hed.size / 2.0
		hed.scale = Vector2.ONE * 1.5
		hed.create_tween().tween_property(hed, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		play("tik", -2.0))
	tw.tween_interval(0.6)
	tw.tween_callback(func() -> void:
		var names := []
		for c in cells:
			if c[2]:
				(c[1] as Label).add_theme_color_override("font_color", OI.CHALK_YESIL)
				(c[3] as Control).visible = true
		for id in winners:
			names.append("SEN" if id == me() else pname(id))
		rl.text = ", ".join(names) if not names.is_empty() else "Kimse yazmadı"
		star.modulate.a = 1.0 if not names.is_empty() else 0.0
		chalk_sfx()
		if me() in winners:
			play("odul", -2.0)
		else:
			play("sec", -6.0))
	# 3D tahtaya da yazılsın
	w.cells[w.my_cell].set_board_text(tr("ORT %s / 2 = %s") % [_fmt(d.get("ortalama", 0)), _fmt(d.get("hedef", 0))])


func _fmt(x) -> String:
	var f := float(x)
	return str(int(f)) if is_equal_approx(f, roundf(f)) else str(snappedf(f, 0.1))


func banner() -> Array:
	var ph := phase()
	if ph == "anons":
		return ["HAZIRLAN", "0-100 arası sayı"]
	if ph.begins_with("yaz"):
		var n := tr("%d/%d yazdı") % [int(state.get("yazan", 0)), state.get("players", []).size()]
		return [(tr("TAHTADA: %d") % saved) if saved >= 0 else "SAYINI YAZ", n]
	if ph.begins_with("goster"):
		return ["SONUÇ", ""]
	return ["", ""]


func help_rows() -> Array:
	return [
		["tahta", "Gizlice 0-100 arası yaz"],
		["liderlik", "Hedef: ortalamanın yarısı"],
		["tac", "En yakın sayı kazanır"],
	]


func on_result(d: Dictionary) -> void:
	show_main_button("", false)
	var wins := 0
	var items := []
	for r in d.get("sonuclar", []):
		var mine := "-"
		for s in r.sayilar:
			if int(s.id) == me() and s.sayi != null:
				mine = str(int(s.sayi))
		var won: bool = me() in r.kazananlar.map(func(x) -> int: return int(x))
		if won:
			wins += 1
		items.append({"a": tr("EL %d") % int(r.el), "b": tr("Hedef: %s") % _fmt(r.hedef), "c": tr("Sen: %s") % mine, "col": GREEN if won else Color(0.8, 0.82, 0.9)})
	var head := (tr("%d ELDE EN YAKIN SENDİN") % wins) if wins > 0 else "HİÇ EL KAZANAMADIN"
	result_modal(head, GREEN if wins > 0 else RED, [], d, items, 1 if wins > 0 else -1)


func cleanup() -> void:
	close_panel()
	close_card()
	show_main_button("", false)
