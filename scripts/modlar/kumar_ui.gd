# KUMARBAZ: 3 el. Her elde iki gizli zarın var. Telefonda konuş, blöf yap; tahtana bir İDDİA yaz.
# İddialar açılınca birine "YALAN!" diyebilirsin; sonra tüm zarlar açılır. Yalanı yakalanmayanlar arasında
# en yüksek iddia kazanır. Puan yazmaz (maç sonuna kadar gizli). Sunucu: server/src/modes/kumar.js
extends "res://scripts/modlar/mod_ui.gd"

var dice: Array = []  # [a, b]
var el := 0
var claim := -1  # bu elde tahtaya yazılan iddia
var pick_n := 7  # tuşlarla seçilen
var target := -1  # meydan: -1 karar yok, 0 inandım, id: "yalan" dediğin
var claims: Array = []  # [{id, ad, iddia}]


func _sum() -> int:
	return int(dice[0]) + int(dice[1]) if dice.size() == 2 else 0


func _set_dice(d: Dictionary) -> void:
	var e := int(d.get("el", el))
	if e != el:
		claim = -1
		target = -1
		claims = []
	el = e
	dice = d.get("zar", dice)
	pick_n = claim if claim >= 2 else maxi(2, _sum())
	if w and w.cells.size() > w.my_cell and dice.size() == 2:
		w.cells[w.my_cell].set_board_text("%d + %d" % [int(dice[0]), int(dice[1])])


func on_state(d: Dictionary, entered: bool) -> void:
	state = d
	if d.has("iddialar"):
		claims = d.get("iddialar", [])
	if not entered:
		return
	var ph := phase()
	if ph == "anons":
		play("anons")
	elif ph.begins_with("zar"):
		close_panel()
		play("sec", -6.0)
	elif ph.begins_with("meydan"):
		close_card()
		close_panel()
		play("alarm", -10.0)
		flash("YALAN MI?", "", UI.KIRMIZI, 0.9)
		g.get_tree().create_timer(1.1).timeout.connect(func() -> void:
			if phase().begins_with("meydan") and target < 0 and not is_instance_valid(panel):
				open_board())
	elif ph.begins_with("acilis"):
		close_card()
		if is_instance_valid(panel) and not panel.has_meta("acilis"):
			close_panel()
	_main_btn()


func _main_btn() -> void:
	var ph := phase()
	if ph.begins_with("zar"):
		show_main_button("DEĞİŞTİR" if claim >= 2 else "İDDİA ET", true)
	elif ph.begins_with("meydan"):
		show_main_button("YALAN!", true)
	else:
		show_main_button("", false)


func on_secret(d: Dictionary) -> void:
	secret = d
	_set_dice(d)
	show_card()


func on_event(d: Dictionary) -> void:
	match str(d.get("tur", "")):
		"zar":
			_set_dice(d)
			g.get_tree().create_timer(0.3).timeout.connect(show_card)
			g._update_banner()
		"iddia":
			state["iddia_veren"] = int(d.get("iddia_veren", 0))
			g._update_banner()
		"meydan":
			state["karar_veren"] = int(d.get("karar_veren", 0))
			g._update_banner()
		"iddialar":
			claims = d.get("iddialar", [])
		"acilis":
			_reveal(d)


# Rol kartı: iki zarın kocaman (tebeşir), tek cümle.
func show_card() -> void:
	if dice.size() != 2 or not (phase() == "anons" or phase().begins_with("zar") or phase() == ""):
		return
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", UI.B_M)
	for z in dice:
		var zd := Zar.new()
		zd.deger = int(z)
		zd.custom_minimum_size = Vector2(104, 104)
		h.add_child(zd)
	var eq := UI.title("= %d" % _sum(), 56, UI.AMBER)
	eq.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(eq)
	var t := tr("ZARIN  ·  EL %d") % el if el > 0 else "ZARIN"
	role_card(t, UI.AMBER, "Kimse bilmiyor. Telefonda blöf yap, iddianı yaz.", "", h)


func open_board() -> void:
	var ph := phase()
	if ph.begins_with("zar"):
		_claim_board()
	elif ph.begins_with("meydan"):
		_challenge_board()


# İddia tahtası: solda zarların, sağda kocaman iddia sayısı ve - / + ; altta "İDDİA ET".
func _claim_board() -> void:
	if dice.size() != 2:
		return
	var m := chalk_modal("İddian", "", 1000.0)
	var v: VBoxContainer = m[1]
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 64)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	var left := VBoxContainer.new()
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 6)
	var dl := chalk("Zarın", 30)
	dl.modulate.a = 0.7
	left.add_child(dl)
	var dr := HBoxContainer.new()
	dr.alignment = BoxContainer.ALIGNMENT_CENTER
	dr.add_theme_constant_override("separation", 14)
	for z in dice:
		var zd := Zar.new()
		zd.deger = int(z)
		zd.custom_minimum_size = Vector2(96, 96)
		dr.add_child(zd)
	left.add_child(dr)
	left.add_child(chalk("= %d" % _sum(), 52))
	row.add_child(left)
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 4)
	var il := chalk("İddian", 30, OI.CHALK_SARI)
	il.modulate.a = 0.85
	right.add_child(il)
	var nr := HBoxContainer.new()
	nr.alignment = BoxContainer.ALIGNMENT_CENTER
	nr.add_theme_constant_override("separation", 14)
	var minus := chalk_button("-", "", false, 96, 96)
	var num := chalk(str(pick_n), 130, OI.CHALK_SARI)
	num.custom_minimum_size = Vector2(170, 150)
	var plus := chalk_button("+", "", false, 96, 96)
	for b in [minus, plus]:
		(b as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		((b as Control).get_meta("label") as Label).add_theme_font_size_override("font_size", 76)
	nr.add_child(minus)
	nr.add_child(num)
	nr.add_child(plus)
	right.add_child(nr)
	var hint := chalk("", 26, OI.CHALK_KIRMIZI)
	hint.custom_minimum_size.y = 36
	right.add_child(hint)
	row.add_child(right)
	var refresh := func() -> void:
		num.text = str(pick_n)
		hint.text = "Blöf!" if pick_n > _sum() else ""
		num.pivot_offset = num.size / 2.0
		var tw := num.create_tween()
		tw.tween_property(num, "scale", Vector2.ONE * 1.1, 0.05)
		tw.tween_property(num, "scale", Vector2.ONE, 0.12)
	refresh.call()
	minus.pressed.connect(func() -> void:
		pick_n = maxi(2, pick_n - 1)
		chalk_sfx()
		refresh.call())
	plus.pressed.connect(func() -> void:
		pick_n = mini(12, pick_n + 1)
		chalk_sfx()
		refresh.call())
	var ok := chalk_button("İddia et", "tebesir", true, 340, 80, OI.CHALK_YESIL)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(func() -> void:
		claim = pick_n
		g.decided.emit({"iddia": claim})
		play("sec", -4.0)
		chalk_sfx()
		w.cells[w.my_cell].set_board_text(tr("İDDİA %d") % claim)
		_main_btn()
		g._update_banner()
		flash(tr("İDDİA: %d") % claim, "", UI.AMBER, 0.7)
		_close_later(0.35))
	v.add_child(ok)


# Meydan okuma: herkesin iddiası tebeşir kart; birine dokun = "YALAN!", ya da "İnandım".
func _challenge_board() -> void:
	var m := chalk_modal("Kim yalan söylüyor?", "", 1000.0)
	var v: VBoxContainer = m[1]
	var list: Array = claims.duplicate()
	if list.is_empty():
		for id in state.get("players", []):
			list.append({"id": int(id), "ad": pname(id), "iddia": 0})
	var n := list.size()
	var grid := GridContainer.new()
	grid.columns = n if n <= 4 else ceili(n / 2.0)
	grid.add_theme_constant_override("h_separation", UI.B_M)
	grid.add_theme_constant_override("v_separation", UI.B_S)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(grid)
	var cw := clampf(760.0 / grid.columns - UI.B_M, 150.0, 200.0)
	var ch := 190.0 if n <= 4 else 132.0
	for c in list:
		var id := int(c.id)
		var mine := id == me()
		var on := target == id
		var col := OI.CHALK_KIRMIZI if on else CHALK
		var b := chalk_button("", "", on, cw, ch, col)
		var kv := VBoxContainer.new()
		kv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		kv.alignment = BoxContainer.ALIGNMENT_CENTER
		kv.add_theme_constant_override("separation", -6)
		kv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var nm := chalk("SEN" if mine else str(c.ad), 28 if str(c.ad).length() < 11 else 22, OI.CHALK_SARI if mine else col)
		nm.clip_text = true
		nm.custom_minimum_size.x = cw - 16
		kv.add_child(nm)
		kv.add_child(chalk(str(int(c.iddia)) if int(c.iddia) > 0 else "?", 80 if n <= 4 else 60, col))
		if on and n <= 4:
			kv.add_child(chalk("YALAN!", 26, OI.CHALK_KIRMIZI))
		b.add_child(kv)
		if mine:
			b.disabled = true
			b.modulate.a = 0.5
		else:
			b.pressed.connect(func() -> void: _challenge(id))
		grid.add_child(b)
	var pass_b := chalk_button("İnandım", "onay", target == 0, 300, 72, OI.CHALK_YESIL)
	pass_b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pass_b.pressed.connect(func() -> void: _challenge(0))
	v.add_child(pass_b)


func _challenge(id: int) -> void:
	target = id
	g.decided.emit({"meydan": id})
	chalk_sfx()
	if id > 0:
		play("buzzer", -8.0)
		flash("YALAN!", up(pname(id)), UI.KIRMIZI, 0.8)
	else:
		play("sec", -4.0)
	g._update_banner()
	_close_later(0.35)


# El sonu: satırlar büyükten küçüğe; zarlar tek tek açılır, yakalanan yalan kırmızı çarpı, doğru çıkan yeşil onay,
# kazanan(lar) taç. Puan yazmaz.
func _reveal(d: Dictionary) -> void:
	g.clear_flashes()
	close_card()
	close_panel()
	show_main_button("", false)
	var m := chalk_modal(tr("Zarlar açıldı · El %d") % int(d.get("el", el)), "", 1000.0)
	panel.set_meta("acilis", true)
	var v: VBoxContainer = m[1]
	var rows: Array = d.get("satirlar", [])
	var winners: Array = (d.get("kazananlar", []) as Array).map(func(x) -> int: return int(x))
	var two := rows.size() > 4
	var grid := GridContainer.new()
	grid.columns = 2 if two else 1
	grid.add_theme_constant_override("h_separation", 24 if two else 40)
	grid.add_theme_constant_override("v_separation", 2 if two else 6)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(grid)
	var rh := 56.0 if two else 74.0
	var zs := 40.0 if two else 56.0
	var nw := 140.0 if two else 260.0
	var steps: Array = []
	for s in rows:
		var id := int(s.id)
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 6 if two else 10)
		r.custom_minimum_size.y = rh
		var nm := chalk("SEN" if id == me() else str(s.ad), 24 if two else 32, OI.CHALK_SARI if id == me() else CHALK)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		nm.custom_minimum_size.x = nw
		nm.clip_text = true
		r.add_child(nm)
		var cl := chalk(str(int(s.iddia)), 40 if two else 52)
		cl.custom_minimum_size.x = 52 if two else 64
		r.add_child(cl)
		var zr := HBoxContainer.new()
		zr.add_theme_constant_override("separation", 6)
		var zz: Array = s.get("zar", [1, 1])
		var zds: Array = []
		for z in zz:
			var zd := Zar.new()
			zd.deger = 0  # kapalı
			zd.custom_minimum_size = Vector2(zs, zs)
			zd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			zr.add_child(zd)
			zds.append([zd, int(z)])
		r.add_child(zr)
		var mark := Control.new()
		mark.custom_minimum_size = Vector2(rh, rh)
		var caught := bool(s.get("yakalandi", false))
		var chal := (s.get("meydan", []) as Array).size() > 0
		var won := id in winners
		var kind := "carpi" if caught else ("tac" if won else ("onay" if chal else ""))
		var mcol := OI.CHALK_KIRMIZI if caught else (OI.CHALK_SARI if won else OI.CHALK_YESIL)
		if kind != "":
			var md := chalk_draw(kind, Vector2(rh, rh * (0.75 if kind == "tac" else 1.0)), mcol)
			md.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			md.visible = false
			mark.add_child(md)
			steps.append([zds, md, caught, won, cl])
		else:
			steps.append([zds, null, false, false, cl])
		r.add_child(mark)
		grid.add_child(r)
	var tw := v.create_tween()
	tw.tween_interval(0.35)
	for st in steps:
		tw.tween_callback(func() -> void:
			for p in st[0]:
				(p[0] as Zar).deger = int(p[1])
				(p[0] as Zar).queue_redraw()
			chalk_sfx())
		tw.tween_interval(0.12 if two else 0.18)
	tw.tween_interval(0.3)
	tw.tween_callback(func() -> void:
		var any_caught := false
		for st in steps:
			if st[1]:
				(st[1] as Control).visible = true
			if st[2]:
				any_caught = true
				(st[4] as Label).add_theme_color_override("font_color", OI.CHALK_KIRMIZI)
			elif st[3]:
				(st[4] as Label).add_theme_color_override("font_color", OI.CHALK_SARI)
		if me() in winners:
			play("odul", -2.0)
		elif any_caught:
			play("buzzer", -6.0)
		else:
			play("tik", -2.0))
	w.cells[w.my_cell].set_board_text("")


# Seçimden kısa süre sonra tahtayı kapatır; bu arada başka pencere (ör. açılış) açıldıysa ona dokunmaz.
func _close_later(t: float) -> void:
	var p := panel
	g.get_tree().create_timer(t).timeout.connect(func() -> void:
		if is_instance_valid(p) and panel == p:
			close_panel())


func banner() -> Array:
	var ph := phase()
	if ph == "anons":
		return ["ZARLARINA BAK", tr("Zarın: %d") % _sum() if dice.size() == 2 else ""]
	if ph.begins_with("zar"):
		var z := (tr("Zarın: %d + %d") % [int(dice[0]), int(dice[1])]) if dice.size() == 2 else ""
		return [(tr("İDDİAN: %d") % claim) if claim >= 2 else "İDDİANI YAZ", z]
	if ph.begins_with("meydan"):
		var n := tr("%d/%d karar") % [int(state.get("karar_veren", 0)), state.get("players", []).size()]
		var t := "YALAN MI?"
		if target == 0:
			t = "İNANDIN"
		elif target > 0:
			t = tr("YALAN: %s") % up(pname(target))
		return [t, n]
	if ph.begins_with("acilis"):
		return ["ZARLAR AÇILDI", ""]
	return ["", ""]


func help_rows() -> Array:
	return [
		["tahta", "Zarın gizli: iddianı yaz"],
		["telefon", "Telefonda blöf yap"],
		["tac", "Yalanı yakala, en yüksek kazanır"],
	]


func on_result(d: Dictionary) -> void:
	show_main_button("", false)
	var items := []
	var wins := 0
	var caught := 0
	for r in d.get("sonuclar", []):
		var mine: Dictionary = {}
		for s in r.get("satirlar", []):
			if int(s.id) == me():
				mine = s
		if mine.is_empty():
			continue
		var won: bool = me() in (r.get("kazananlar", []) as Array).map(func(x) -> int: return int(x))
		var yak := bool(mine.get("yakalandi", false))
		if won:
			wins += 1
		if yak:
			caught += 1
		var c := "KAZANDIN" if won else ("YAKALANDIN" if yak else "-")
		var col := GREEN if won else (RED if yak else Color(0.8, 0.82, 0.9))
		items.append({"a": tr("EL %d") % int(r.get("el", 0)), "b": tr("İddia %d · Zar %d") % [int(mine.get("iddia", 0)), int(mine.get("zar_toplam", 0))], "c": c, "col": col})
	var head := ("BİR ELİ KAZANDIN" if wins == 1 else tr("%d ELDE KAZANDIN") % wins) if wins > 0 else ("BLÖFÜN YAKALANDI" if caught > 0 else "ELİ BOŞ KALKTIN")
	result_modal(head, GREEN if wins > 0 else RED, [], d, items, 1 if wins > caught else (-1 if caught > wins or wins == 0 else 0))


func cleanup() -> void:
	close_panel()
	close_card()
	show_main_button("", false)
	if w and w.cells.size() > w.my_cell:
		w.cells[w.my_cell].set_board_text("")


# ---------- test (main.gd otomatik maç ve oyunici_test.gd) ----------

# Otomatik maçta "Sen" oynar: zarı +2 blöfle iddia eder, en yüksek iddiaya "yalan" der.
func auto_test(ph: String, shot: Callable) -> void:
	if ph.begins_with("zar"):
		await g.get_tree().create_timer(0.9).timeout
		close_card()
		open_board()
		await g.get_tree().create_timer(0.4).timeout
		if ph == "zar1":
			await shot.call("kumar_iddia")
		claim = mini(12, _sum() + 2)
		g.decided.emit({"iddia": claim})
		w.cells[w.my_cell].set_board_text(tr("İDDİA %d") % claim)
		close_panel()
		_main_btn()
		g._update_banner()
	elif ph.begins_with("meydan"):
		await g.get_tree().create_timer(1.5).timeout
		if not is_instance_valid(panel):
			open_board()
		await g.get_tree().create_timer(0.4).timeout
		if ph == "meydan1":
			await shot.call("kumar_meydan")
		var best := 0
		var top := -1
		for c in claims:
			if int(c.id) != me() and int(c.iddia) > top:
				top = int(c.iddia)
				best = int(c.id)
		_challenge(best if top >= 9 else 0)


func auto_event(d: Dictionary, shot: Callable) -> void:
	if str(d.get("tur", "")) == "acilis":
		await g.get_tree().create_timer(1.5).timeout
		await shot.call("kumar_acilis_%d" % int(d.get("el", 0)))


# Tek ekran testi: ekran = kart | iddia | meydan | acilis | sonuc
func test_ekran(ek: String, args: Dictionary) -> void:
	el = 1
	dice = [4, 3]
	claims = [{"id": 2, "ad": "Kara Ali", "iddia": 11}, {"id": 1, "ad": "Sen", "iddia": 9}, {"id": 3, "ad": "Sinsi Necmi", "iddia": 8}, {"id": 4, "ad": "Deli Rıza", "iddia": 5}]
	var cok: bool = str(args.get("n", "4")) == "8"
	if cok:
		var adlar := ["Çakal Sedat", "Kel Hüsnü", "Sessiz Kemal", "Topal Vedat"]
		for i in 4:
			claims.append({"id": 5 + i, "ad": adlar[i], "iddia": 4 + i})
	match ek:
		"kart":
			state["phase"] = "zar1"
			show_card()
		"iddia":
			state["phase"] = "zar1"
			pick_n = int(args.get("iddia", "9"))
			g._update_banner()
			_claim_board()
		"meydan":
			state["phase"] = "meydan1"
			target = int(args.get("hedef", "2"))
			g._update_banner()
			_challenge_board()
		"acilis":
			state["phase"] = "acilis1"
			var rows := [
				{"id": 2, "ad": "Kara Ali", "iddia": 11, "zar": [2, 3], "meydan": [1, 3], "yakalandi": true},
				{"id": 1, "ad": "Sen", "iddia": 9, "zar": [4, 3], "meydan": [], "yakalandi": false},
				{"id": 3, "ad": "Sinsi Necmi", "iddia": 8, "zar": [6, 2], "meydan": [4], "yakalandi": false},
				{"id": 4, "ad": "Deli Rıza", "iddia": 5, "zar": [1, 4], "meydan": [], "yakalandi": false}]
			if cok:
				var adlar2 := ["Çakal Sedat", "Kel Hüsnü", "Sessiz Kemal", "Topal Vedat"]
				for i in 4:
					rows.append({"id": 5 + i, "ad": adlar2[i], "iddia": 4 + i, "zar": [1 + i, 2], "meydan": [], "yakalandi": false})
			_reveal({"el": 1, "satirlar": rows, "kazananlar": [1]})
		"sonuc":
			on_result({"title": "KUMARBAZ", "task": "kumar", "round": 6, "rounds": 9, "sonraki": "C4", "sonuc_sure": 10,
				"ben": {"msg": "Kazandın ama yalanın da yakalandı."},
				"sonuclar": [
					{"el": 1, "kazananlar": [1], "satirlar": [{"id": 1, "iddia": 9, "zar_toplam": 7, "yakalandi": false}]},
					{"el": 2, "kazananlar": [3], "satirlar": [{"id": 1, "iddia": 12, "zar_toplam": 6, "yakalandi": true}]},
					{"el": 3, "kazananlar": [2], "satirlar": [{"id": 1, "iddia": 6, "zar_toplam": 6, "yakalandi": false}]}]})


# Tebeşirle çizilmiş zar: yuvarlak köşeli kare ve noktalar. deger 0: kapalı (soru işareti yerine boş, taralı).
class Zar extends Control:
	var deger := 1
	var col := Color(0.95, 0.96, 0.9)
	var _rng := RandomNumberGenerator.new()

	func _cizgi(a: Vector2, b: Vector2, wd: float) -> void:
		var L := a.distance_to(b)
		var n := maxi(1, int(L / 12.0))
		var dir := (b - a) / maxf(L, 0.001)
		var nor := Vector2(-dir.y, dir.x)
		var prev := a
		for i in range(1, n + 1):
			var p := a.lerp(b, float(i) / n) + nor * _rng.randf_range(-0.9, 0.9)
			draw_line(prev, p, Color(col, _rng.randf_range(0.7, 0.95)), wd)
			prev = p

	func _draw() -> void:
		_rng.seed = 3 + deger
		var s := minf(size.x, size.y)
		var o := (size - Vector2(s, s)) / 2.0
		var wd := maxf(2.5, s * 0.045)
		var m := s * 0.08
		var a := o + Vector2(m, m)
		var b := o + Vector2(s - m, s - m)
		_cizgi(a + Vector2(-2, 0), Vector2(b.x + 2, a.y), wd)
		_cizgi(Vector2(b.x, a.y - 2), b + Vector2(0, 2), wd)
		_cizgi(b + Vector2(2, 0), Vector2(a.x - 2, b.y), wd)
		_cizgi(Vector2(a.x, b.y + 2), a - Vector2(0, 2), wd)
		if deger <= 0:
			# kapalı zar: tebeşir tarama
			var x := a.x + 6.0
			while x < b.x - 4.0:
				draw_line(Vector2(x, b.y - 4), Vector2(minf(x + (b.y - a.y) * 0.5, b.x - 4), a.y + 4), Color(col, 0.18), 2.0)
				x += 9.0
			return
		var c := o + Vector2(s, s) / 2.0
		var q := (s - m * 2) * 0.27
		var pips: Array = {1: [Vector2.ZERO], 2: [Vector2(-1, -1), Vector2(1, 1)], 3: [Vector2(-1, -1), Vector2.ZERO, Vector2(1, 1)],
			4: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)],
			5: [Vector2(-1, -1), Vector2(1, -1), Vector2.ZERO, Vector2(-1, 1), Vector2(1, 1)],
			6: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)]}.get(clampi(deger, 1, 6), [])
		for p in pips:
			draw_circle(c + (p as Vector2) * q, s * 0.075, Color(col, 0.92))
