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
	role_card("ORTALAMA SAYI", Color("#7fe3ff"), "Herkes gizlice 0 ile 100 arası bir TAM sayı yazar.\nYazılan sayıların ORTALAMASININ YARISINA en yakın olan kazanır. Diğerlerinin ne yazacağını tahmin et!",
		"Kazanan +2 · sayı yazmayan -1")


func open_board() -> void:
	if not phase().begins_with("yaz"):
		return
	var m := chalk_modal("Sayını yaz", "0-100 arası. Ortalamanın yarısına en yakın kazanır. Süre bitene kadar değiştirebilirsin.", 960.0)
	var v: VBoxContainer = m[1]
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	var left := VBoxContainer.new()
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.custom_minimum_size.x = 300
	var disp := chalk(number if number != "" else "_", 130)
	left.add_child(disp)
	var line = g.ChalkDraw.new()
	line.custom_minimum_size = Vector2(260, 10)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(line)
	var hint := chalk(("Tahtada: %d" % saved) if saved >= 0 else "", 26, Color(0.75, 1.0, 0.8))
	left.add_child(hint)
	row.add_child(left)
	var pad := GridContainer.new()
	pad.columns = 3
	pad.add_theme_constant_override("h_separation", 10)
	pad.add_theme_constant_override("v_separation", 8)
	row.add_child(pad)
	var refresh := func() -> void:
		disp.text = number if number != "" else "_"
	for k in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "sil", "0", "ok"]:
		var key: String = k
		var b: Button
		if key == "sil":
			b = chalk_button("", "silgi", false, 96)
		elif key == "ok":
			b = chalk_button("Yaz", "", true, 96)
		else:
			b = chalk_button(key, "", false, 96)
		b.custom_minimum_size.y = 70
		b.pressed.connect(func() -> void:
			if key == "sil":
				number = number.substr(0, maxi(0, number.length() - 1))
			elif key == "ok":
				if number == "" or int(number) > 100:
					hint.text = "0-100 arası yaz!"
					hint.add_theme_color_override("font_color", Color(1, 0.7, 0.65))
					return
				saved = int(number)
				g.decided.emit({"sayi": saved})
				hint.text = "Tahtada: %d" % saved
				hint.add_theme_color_override("font_color", Color(0.75, 1.0, 0.8))
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


# El sonucu: sayılar tebeşirle tek tek yazılır, sonra ortalama, yarısı ve kazanan.
func _reveal(d: Dictionary) -> void:
	close_panel()
	var m := chalk_modal("Sonuç", "", 1000.0)
	var v: VBoxContainer = m[1]
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 34)
	grid.add_theme_constant_override("v_separation", 0)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(grid)
	var winners: Array = d.get("kazananlar", []).map(func(x) -> int: return int(x))
	var cells := []
	for s in d.get("sayilar", []):
		var id := int(s.id)
		var nm := chalk(("SEN" if id == me() else str(s.ad)), 30)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var num := chalk("-" if s.sayi == null else str(int(s.sayi)), 40)
		nm.modulate.a = 0.0
		num.modulate.a = 0.0
		grid.add_child(nm)
		grid.add_child(num)
		cells.append([nm, num, id in winners])
	var sum := chalk("", 40, GOLD)
	var res := chalk("", 30, Color(0.75, 1.0, 0.8))
	v.add_child(sum)
	v.add_child(res)
	var tw := v.create_tween()
	for c in cells:
		tw.tween_interval(0.28)
		tw.tween_callback(func() -> void:
			c[0].modulate.a = 1.0
			c[1].modulate.a = 1.0
			chalk_sfx())
	tw.tween_interval(0.5)
	tw.tween_callback(func() -> void:
		sum.text = "Ortalama %s  ·  yarısı %s" % [_fmt(d.get("ortalama", 0)), _fmt(d.get("hedef", 0))]
		play("tik", -2.0))
	tw.tween_interval(0.6)
	tw.tween_callback(func() -> void:
		var names := []
		for c in cells:
			if c[2]:
				(c[1] as Label).add_theme_color_override("font_color", GREEN)
				(c[0] as Label).add_theme_color_override("font_color", GREEN)
		for id in winners:
			names.append("SEN" if id == me() else pname(id))
		res.text = ("En yakın: " + ", ".join(names) + "  (+2)") if not names.is_empty() else "Kimse yazmadı."
		if me() in winners:
			play("odul", -2.0)
		else:
			play("sec", -6.0))
	# 3D tahtaya da yazılsın
	w.cells[w.my_cell].set_board_text("ORT %s / 2 = %s" % [_fmt(d.get("ortalama", 0)), _fmt(d.get("hedef", 0))])


func _fmt(x) -> String:
	var f := float(x)
	return str(int(f)) if is_equal_approx(f, roundf(f)) else str(snappedf(f, 0.1))


func banner() -> Array:
	var ph := phase()
	var pn := ""
	var info := ""
	if ph == "anons":
		pn = "HAZIRLAN"
		info = "0-100 arası sayı · ortalamanın yarısına en yakın kazanır"
	elif ph.begins_with("yaz"):
		pn = "SAYINI YAZ"
		info = ("Tahtanda: %d · " % saved if saved >= 0 else "Sayını yaz! · ") + "yazan %d/%d" % [int(state.get("yazan", 0)), state.get("players", []).size()]
	elif ph.begins_with("goster"):
		pn = "SONUÇ"
		info = "Ortalamanın yarısına en yakın kazandı"
	return ["ORTALAMA SAYI  ·  " + pn, info]


func help_rows() -> Array:
	return [
		["deal", "Herkes gizlice 0 ile 100 arası bir sayı yazar."],
		["crown", "Yazılan sayıların ortalaması alınır; o ortalamanın YARISINA en yakın olan kazanır."],
		["chat", "Tek el: sonunda tüm sayılar tek tek açılır. Diğerlerinin aklını oku!"],
		["trophy", "Kazanan +2, sayı yazmayan -1. Küsurat yok: ortalama ve yarısı tam sayıya yuvarlanır."],
	]


func on_result(d: Dictionary) -> void:
	show_main_button("", false)
	var rows := []
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 22)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for r in d.get("sonuclar", []):
		var mine := "-"
		for s in r.sayilar:
			if int(s.id) == me() and s.sayi != null:
				mine = str(int(s.sayi))
		var won: bool = me() in r.kazananlar.map(func(x) -> int: return int(x))
		grid.add_child(UI.title("El %d" % int(r.el), 20, GOLD))
		grid.add_child(UI.label("yarısı %s" % _fmt(r.hedef), 20, Color.WHITE))
		grid.add_child(UI.label("sen: %s" % mine, 20, Color("#a8f2ff")))
		grid.add_child(UI.title("KAZANDIN" if won else "", 20, GREEN))
	rows.append(grid)
	result_modal("ORTALAMA SAYI", rows, d)


func cleanup() -> void:
	close_panel()
	close_card()
	show_main_button("", false)
