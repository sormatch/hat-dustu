# MAHKUM İKİLEMİ: her turda bir eşin var (tek sayıda kalan üçlüye girer). Telefonla pazarlık edersin; süre bitince
# tahtada gizlice SUS ya da ÖT seçersin. Tur sonunda kartlar aynı anda döner (SUS mavi, ÖT kırmızı). Puan yazmaz.
# Bot eş telefonu açamaz: tahtana bir not bırakır ("Susacağım." / "Öteceğim."), doğru da olabilir yalan da.
# Sunucu: server/src/modes/ikilem.js
extends "res://scripts/modlar/mod_ui.gd"

const MAVI_T := Color(0.56, 0.8, 1.0)  # tebeşir mavisi (SUS)
const KIRMIZI_T := Color(1.0, 0.5, 0.45)  # tebeşir kırmızısı (ÖT)
const SUS_RENK := Color("#3fa8ff")
const OT_RENK := Color("#e0322a")
const MUTED_RENK := Color(0.78, 0.8, 0.88)

var choice := ""  # bu turdaki seçimin: "sus" | "ot" | ""
var tur := 0
var partners: Array = []  # [{id, ad, bot, not}]


static func kelime(secim: String) -> String:
	return "ÖT" if secim == "ot" else "SUS"


static func renk(secim: String) -> Color:
	return OT_RENK if secim == "ot" else SUS_RENK


func _names() -> String:
	var out := PackedStringArray()
	for p in partners:
		out.append(str(p.get("ad", "?")))
	return " + ".join(out)


func _bot_partner() -> bool:
	return not partners.is_empty() and partners.all(func(p) -> bool: return bool(p.get("bot", false)))


func _set_pair(d: Dictionary) -> void:
	var t := int(d.get("tur_no", tur))
	if t != tur:
		choice = ""
		if w and w.cells.size() > w.my_cell:
			w.cells[w.my_cell].set_board_text("")
	tur = t
	partners = d.get("es", [])


func on_state(d: Dictionary, entered: bool) -> void:
	state = d
	if not entered:
		return
	var ph := phase()
	if ph == "anons":
		choice = ""
		play("anons")
	elif ph.begins_with("pazarlik"):
		close_panel()
		play("sec", -6.0)
	elif ph.begins_with("secim"):
		close_card()
		play("alarm", -10.0)
		flash("SUS mu, ÖT mü?", "", UI.AMBER, 0.9)
		g.get_tree().create_timer(1.1).timeout.connect(func() -> void:
			if phase().begins_with("secim") and choice == "" and not is_instance_valid(panel):
				open_board())
	elif ph.begins_with("acilis"):
		close_card()
		if is_instance_valid(panel) and not panel.has_meta("acilis"):
			close_panel()
	show_main_button("DEĞİŞTİR" if choice != "" else "SEÇ", ph.begins_with("pazarlik") or ph.begins_with("secim"))


func on_secret(d: Dictionary) -> void:
	secret = d
	_set_pair(d)
	if phase() == "anons" or phase() == "":
		show_card()
	else:
		_pair_card()


func on_event(d: Dictionary) -> void:
	match str(d.get("tur", "")):
		"eslesme":
			_set_pair(d)
			g.get_tree().create_timer(0.3).timeout.connect(_pair_card)
			g._update_banner()
		"secti":
			state["secen"] = int(d.get("secen", 0))
			g._update_banner()
		"acilis":
			_reveal(d)


# Oyunun tanıtımı (anons): kısa kural.
func show_card() -> void:
	if phase().begins_with("pazarlik") or phase().begins_with("secim"):
		_pair_card()
		return
	var ex := HBoxContainer.new()
	ex.alignment = BoxContainer.ALIGNMENT_CENTER
	ex.add_theme_constant_override("separation", UI.B_XL)
	for s in ["sus", "ot"]:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		var f := Surat.new()
		f.acik = s == "ot"
		f.col = MAVI_T if s == "sus" else KIRMIZI_T
		f.custom_minimum_size = Vector2(96, 96)
		f.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(f)
		v.add_child(UI.title(kelime(s), 40, renk(s), true))
		ex.add_child(v)
	role_card("MAHKUM İKİLEMİ", UI.AMBER, "Eşinle telefonda konuş. Sonra gizlice SUS ya da ÖT.", "", ex)


# Bu turun eşi: kocaman ad, telefon ikonu; bot eşse tebeşirle notu.
func _pair_card() -> void:
	if partners.is_empty() or not (phase().begins_with("pazarlik") or phase() == "anons"):
		return
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UI.B_XS)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", UI.B_S)
	var ic := UI.icon("bot" if _bot_partner() else "telefon", 64)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var ad := UI.title(up(_names()), 44 if _names().length() < 16 else 32, UI.AMBER)
	h.add_child(ad)
	v.add_child(h)
	var line := "Ara, pazarlık yap. Sonra SUS ya da ÖT."
	if _bot_partner():
		line = "Bot telefonu açamaz. Notuna güvenecek misin?"
		v.add_child(_note_label(36))
	elif partners.size() > 1:
		line = "Üçlüsünüz. İkisini de ara, pazarlık yap."
	var t := tr("TUR %d") % tur if tur > 0 else ""
	role_card(tr("EŞİN") + ("  ·  " + t if t != "" else ""), MAVI_T, line, "", v)


func _note_label(size: int) -> Label:
	var nt := ""
	for p in partners:
		if bool(p.get("bot", false)):
			nt = str(p.get("not", ""))
	var l := chalk("“" + tr("Öteceğim." if nt == "ot" else "Susacağım.") + "”", size, OI.CHALK_SARI)
	l.rotation = deg_to_rad(-2.0)
	return l


# Seçim tahtası: iki kocaman tebeşir kartı (SUS mavi, ÖT kırmızı); seçili olan taralı ve renkli.
func open_board() -> void:
	var ph := phase()
	if not (ph.begins_with("pazarlik") or ph.begins_with("secim")) or partners.is_empty():
		return
	var m := chalk_modal("SUS mu, ÖT mü?", "", 1000.0)
	var v: VBoxContainer = m[1]
	var who := chalk(tr("Eşin: %s") % _names(), 30, OI.CHALK_SARI)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	who.clip_text = true
	v.add_child(who)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 56)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	var bh := clampf(root().get_viewport_rect().size.y * 0.42, 220.0, 320.0)
	for s in ["sus", "ot"]:
		var sec: String = s
		var on := choice == sec
		var col := MAVI_T if sec == "sus" else KIRMIZI_T
		var b := chalk_button("", "", on, 300, bh, col)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var kv := VBoxContainer.new()
		kv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		kv.alignment = BoxContainer.ALIGNMENT_CENTER
		kv.add_theme_constant_override("separation", 0)
		kv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var f := Surat.new()
		f.acik = sec == "ot"
		f.col = col
		f.custom_minimum_size = Vector2(bh * 0.5, bh * 0.5)
		f.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		kv.add_child(f)
		kv.add_child(chalk(kelime(sec), 72, col))
		b.add_child(kv)
		b.pressed.connect(func() -> void: _choose(sec))
		row.add_child(b)
	if _bot_partner():
		var nr := HBoxContainer.new()
		nr.alignment = BoxContainer.ALIGNMENT_CENTER
		nr.add_theme_constant_override("separation", 12)
		var ic := UI.icon("bot", 40)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nr.add_child(ic)
		nr.add_child(_note_label(34))
		v.add_child(nr)


func _choose(sec: String) -> void:
	choice = sec
	g.decided.emit({"secim": sec})
	chalk_sfx()
	play("sec", -4.0)
	w.cells[w.my_cell].set_board_text(tr(kelime(sec)))  # hücredeki tahtada da yazsın
	show_main_button("DEĞİŞTİR", true)
	g._update_banner()
	flash(tr(kelime(sec)), "", renk(sec), 0.7)
	_close_later(0.35)


# Seçimden kısa süre sonra tahtayı kapatır; bu arada başka pencere (ör. açılış) açıldıysa ona dokunmaz.
func _close_later(t: float) -> void:
	var p := panel
	g.get_tree().create_timer(t).timeout.connect(func() -> void:
		if is_instance_valid(p) and panel == p:
			close_panel())


func banner() -> Array:
	var ph := phase()
	if ph == "anons":
		return ["HAZIRLAN", "Eşin geliyor"]
	if ph.begins_with("pazarlik"):
		var info := "Bot: telefonu açamaz" if _bot_partner() else "Ara, pazarlık yap"
		if choice != "":
			info = tr("Seçimin: %s") % tr(kelime(choice))
		return [tr("EŞİN: %s") % up(_names()), info]
	if ph.begins_with("secim"):
		var n := tr("%d/%d seçti") % [int(state.get("secen", 0)), state.get("players", []).size()]
		return [(tr("SEÇİMİN: %s") % tr(kelime(choice))) if choice != "" else "SUS mu, ÖT mü?", n]
	return ["", ""]  # açılışta bant gizli (kartlar ekranı kaplar)


func help_rows() -> Array:
	return [
		["telefon", "Eşini ara, pazarlık yap"],
		["kilit", "İkiniz susarsanız ikiniz kazanır"],
		["sikayet", "Öten kazanır, susan yanar"],
	]


func contact_name(id: int) -> String:
	if partners.is_empty() or not (phase().begins_with("pazarlik") or phase().begins_with("secim")):
		return ""
	for p in partners:
		if int(p.get("id", 0)) == id:
			return tr("%s (EŞİN)") % str(p.get("ad", "?"))
	return ""


# Tur sonu: eşlerin kartları yüzü kapalı gelir, kısa gerilimden sonra AYNI ANDA döner.
func _reveal(d: Dictionary) -> void:
	g.clear_flashes()
	close_card()
	close_panel()
	show_main_button("", false)
	var grup: Array = (d.get("grup", []) as Array).duplicate()
	grup.sort_custom(func(a, b) -> bool: return int(a.id) == me() and int(b.id) != me())
	var ov := Control.new()
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	ov.set_meta("acilis", true)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.012, 0.02, 0.88)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", UI.B_L)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(v)
	v.add_child(UI.title(tr("TUR %d") % int(d.get("tur_no", tur)), UI.FS_ORTA, UI.METIN_SOLUK, true))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", UI.B_XL if grup.size() < 3 else UI.B_L)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	var vh := root().get_viewport_rect().size.y
	var ch := clampf(vh * 0.46, 240.0, 340.0)
	var cw := ch * 0.72
	var cards: Array = []
	for s in grup:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", UI.B_XS)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var k := _flip_card(str(s.secim), Vector2(cw, ch))
		col.add_child(k)
		var nm := UI.title("SEN" if int(s.id) == me() else str(s.ad), UI.FS_ORTA, UI.AMBER if int(s.id) == me() else UI.METIN, true)
		nm.custom_minimum_size.x = cw
		nm.clip_text = true
		col.add_child(nm)
		row.add_child(col)
		cards.append(k)
	var sonuc := str(d.get("sonuc", ""))
	var head := UI.title("", UI.FS_DEV, UI.METIN, true)
	head.modulate.a = 0.0
	v.add_child(head)
	root().add_child(ov)
	panel = ov
	ov.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			if head.modulate.a > 0.5:
				close_panel())
	# gerilim: kalp atışı, kartlar hafifçe titrer; sonra aynı anda dönerler
	play("kalp", -4.0)
	var tw := ov.create_tween()
	tw.tween_interval(1.3)
	tw.tween_callback(func() -> void:
		for k in cards:
			((k as Control).get_meta("cevir") as Callable).call()
		play("tik", -2.0))
	tw.tween_interval(0.45)
	tw.tween_callback(func() -> void:
		var t := _outcome_text(sonuc, grup.size())
		head.text = t[0]
		head.add_theme_color_override("font_color", t[1])
		head.pivot_offset = Vector2(head.size.x / 2.0, head.size.y / 2.0)
		head.scale = Vector2.ONE * 1.4
		head.modulate.a = 1.0
		head.create_tween().tween_property(head, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_outcome_sfx(sonuc))
	w.cells[w.my_cell].set_board_text("")


func _outcome_sfx(sonuc: String) -> void:
	match sonuc:
		"ikisus":
			play("odul", -2.0)
		"sattin":
			play("para", -2.0)
		"satildin":
			play("kapi_carp", -2.0)
			screen_flash(OT_RENK, 0.35, 0.05, 0.5)
		"ikiot":
			play("kilit", -2.0)
		_:
			play("sec", -4.0)


static func _outcome_text(sonuc: String, n: int) -> Array:
	match sonuc:
		"ikisus":
			return ["HEPİNİZ SUSTUNUZ" if n > 2 else "İKİNİZ DE SUSTUNUZ", SUS_RENK]
		"satildin":
			return ["SATILDIN!", OT_RENK]
		"sattin":
			return ["ÖTTÜN, KURTULDUN!", UI.AMBER]
		"ikiot":
			return ["İKİNİZ DE ÖTTÜNÜZ" if n == 2 else "ÖTENLER YANDI", Color("#ff8a7a")]
		"yalniz":
			return ["EŞİN KAÇTI", UI.METIN_SOLUK]
	return ["", UI.METIN]


# Dönen kart: arkası nötr (soru işareti), önü renkli (yüz + SUS/ÖT). cevir() çağrılınca döner.
func _flip_card(secim: String, sz: Vector2) -> Control:
	var k := Control.new()
	k.custom_minimum_size = sz
	k.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := UI.card_frame("", sz)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var q := chalk("?", int(sz.y * 0.42), CHALK)
	back.add_child(q)
	k.add_child(back)
	var front := PanelContainer.new()
	var st := UI.flat(Color(renk(secim), 0.92).darkened(0.35), renk(secim).lightened(0.25), UI.R_BUYUK)
	st.set_border_width_all(5)
	st.shadow_size = 24
	st.shadow_color = Color(renk(secim), 0.55)
	front.add_theme_stylebox_override("panel", st)
	front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.visible = false
	var fv := VBoxContainer.new()
	fv.alignment = BoxContainer.ALIGNMENT_CENTER
	fv.add_theme_constant_override("separation", 0)
	fv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f := Surat.new()
	f.acik = secim == "ot"
	f.col = Color.WHITE
	f.custom_minimum_size = Vector2(sz.x * 0.62, sz.x * 0.62)
	f.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fv.add_child(f)
	var word := UI.title(kelime(secim), int(sz.y * 0.2), Color.WHITE, true)
	var fs := int(sz.y * 0.2)
	var fnt := word.get_theme_font("font")
	while fs > 20 and fnt.get_string_size(tr(kelime(secim)), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > sz.x - 44.0:
		fs -= 2
	word.add_theme_font_size_override("font_size", fs)
	fv.add_child(word)
	front.add_child(fv)
	k.add_child(front)
	k.resized.connect(func() -> void: k.pivot_offset = k.size / 2.0)
	# bekleme: hafif sallanma
	var wob := k.create_tween().set_loops(3)
	wob.tween_property(k, "rotation", deg_to_rad(1.6), 0.11)
	wob.tween_property(k, "rotation", deg_to_rad(-1.6), 0.11)
	wob.tween_property(k, "rotation", 0.0, 0.11)
	var flip := func() -> void:
		k.rotation = 0.0
		k.pivot_offset = k.size / 2.0
		var tw := k.create_tween()
		tw.tween_property(k, "scale:x", 0.0, 0.14).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			back.visible = false
			front.visible = true)
		tw.tween_property(k, "scale", Vector2(1.08, 1.08), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(k, "scale", Vector2.ONE, 0.12)
	k.set_meta("cevir", flip)
	return k


func on_result(d: Dictionary) -> void:
	show_main_button("", false)
	var ben = d.get("ben")
	var turlar: Array = ben.get("turlar", []) if typeof(ben) == TYPE_DICTIONARY else []
	var items := []
	var sus := 0
	var iyi := 0
	var kotu := 0
	for t in turlar:
		var es: Array = t.get("es", [])
		var ad := PackedStringArray()
		for e in es:
			ad.append(str(e.get("ad", "?")))
		var mine := str(t.get("secim", "sus"))
		if mine == "sus":
			sus += 1
		var so := str(t.get("sonuc", ""))
		if so in ["ikisus", "sattin"]:
			iyi += 1
		elif so == "satildin":
			kotu += 1
		var col: Color = {"ikisus": SUS_RENK, "sattin": UI.AMBER, "satildin": OT_RENK, "ikiot": Color("#ff8a7a")}.get(so, MUTED_RENK)
		# sağ sütun kısa sonuç (İngilizcede uzun "SILENT / SNITCH" sığmıyor); renk de sonucu söyler
		var kisa: String = {"ikisus": "SUSTUNUZ", "satildin": "SATILDIN", "sattin": "ÖTTÜN", "ikiot": "İKİ ÖTEN"}.get(so, "EŞ KAÇTI")
		items.append({"a": tr("TUR %d") % int(t.get("tur", 0)), "b": " + ".join(ad) if not ad.is_empty() else "-", "c": tr(kisa), "col": col})
	var head := "İKİ YÜZLÜ"
	var hc := UI.AMBER
	if not turlar.is_empty() and sus == turlar.size():
		head = "SADIK MAHKUM"
		hc = SUS_RENK
	elif not turlar.is_empty() and sus == 0:
		head = "MUHBİR"
		hc = OT_RENK
	result_modal(head, hc, [], d, items, 1 if iyi > kotu else (-1 if kotu > iyi else 0))


func cleanup() -> void:
	close_panel()
	close_card()
	show_main_button("", false)
	if w and w.cells.size() > w.my_cell:
		w.cells[w.my_cell].set_board_text("")


# ---------- test (main.gd otomatik maç ve oyunici_test.gd) ----------

# Otomatik maçta "Sen" oynar: pazarlıkta eş kartı, seçimde tahta; dönüşümlü SUS/ÖT seçer.
func auto_test(ph: String, shot: Callable) -> void:
	if ph.begins_with("pazarlik"):
		await g.get_tree().create_timer(0.9).timeout
		await shot.call("ikilem_es_" + ph.right(1))
		close_card()
	elif ph.begins_with("secim"):
		await g.get_tree().create_timer(1.4).timeout
		if not is_instance_valid(panel):
			open_board()
		await g.get_tree().create_timer(0.5).timeout
		await shot.call("ikilem_tahta_" + ph.right(1))
		_choose("ot" if int(ph.right(1)) % 2 == 0 else "sus")


func auto_event(d: Dictionary, shot: Callable) -> void:
	if str(d.get("tur", "")) == "acilis":
		await g.get_tree().create_timer(0.6).timeout
		await shot.call("ikilem_kapali_%d" % int(d.get("tur_no", 0)))
		await g.get_tree().create_timer(1.1).timeout
		await shot.call("ikilem_acilis_%d" % int(d.get("tur_no", 0)))


# Tek ekran testi: ekran = kart | es | es_bot | tahta | acilis | sonuc
func test_ekran(ek: String, args: Dictionary) -> void:
	tur = 2
	partners = [{"id": 2, "ad": "Kara Ali", "bot": ek == "es_bot", "not": "sus"}]
	match ek:
		"kart":
			state["phase"] = "anons"
			show_card()
		"es", "es_bot":
			state["phase"] = "pazarlik2"
			g._update_banner()
			_pair_card()
		"tahta":
			state["phase"] = "secim2"
			choice = str(args.get("secim", ""))
			partners[0]["bot"] = args.get("bot", "0") == "1"
			g._update_banner()
			open_board()
		"acilis":
			state["phase"] = "acilis2"
			var es: String = str(args.get("es_secim", "ot"))
			var benim: String = str(args.get("secim", "sus"))
			var so := "ikisus" if benim == "sus" and es == "sus" else ("satildin" if benim == "sus" else ("sattin" if es == "sus" else "ikiot"))
			var grup := [{"id": 1, "ad": "Sen", "secim": benim}, {"id": 2, "ad": "Kara Ali", "secim": es}]
			if args.get("uclu", "0") == "1":
				grup.append({"id": 3, "ad": "Sinsi Necmi", "secim": "sus"})
			_reveal({"tur_no": 2, "grup": grup, "sonuc": so})
		"sonuc":
			on_result({"title": "MAHKUM İKİLEMİ", "task": "ikilem", "round": 3, "rounds": 9, "sonraki": "YALANCI", "sonuc_sure": 10,
				"ben": {"msg": "Bir kez satıldın.", "turlar": [
					{"tur": 1, "secim": "sus", "sonuc": "ikisus", "es": [{"id": 2, "ad": "Kara Ali", "secim": "sus"}]},
					{"tur": 2, "secim": "sus", "sonuc": "satildin", "es": [{"id": 3, "ad": "Sinsi Necmi", "secim": "ot"}]},
					{"tur": 3, "secim": "ot", "sonuc": "sattin", "es": [{"id": 4, "ad": "Deli Rıza", "secim": "sus"}, {"id": 2, "ad": "Kara Ali", "secim": "sus"}]}]}})


# Tebeşirle çizilmiş yüz: kapalı ağız (fermuarlı, SUS) ya da açık ağız ve ses dalgaları (ÖT).
class Surat extends Control:
	var acik := false
	var col := Color(0.95, 0.96, 0.9)
	var _rng := RandomNumberGenerator.new()

	func _cizgi(a: Vector2, b: Vector2, wd: float) -> void:
		var L := a.distance_to(b)
		var n := maxi(1, int(L / 12.0))
		var dir := (b - a) / maxf(L, 0.001)
		var nor := Vector2(-dir.y, dir.x)
		var prev := a
		for i in range(1, n + 1):
			var p := a.lerp(b, float(i) / n) + nor * _rng.randf_range(-1.0, 1.0)
			draw_line(prev, p, Color(col, _rng.randf_range(0.7, 0.95)), wd)
			prev = p

	func _yay(c: Vector2, r: Vector2, a0: float, a1: float, wd: float) -> void:
		var n := maxi(10, int(absf(a1 - a0) * maxf(r.x, r.y) / 9.0))
		var prev := c + Vector2(cos(a0) * r.x, sin(a0) * r.y)
		for i in range(1, n + 1):
			var a := lerpf(a0, a1, float(i) / n)
			var j := _rng.randf_range(-0.8, 0.8)
			var p := c + Vector2(cos(a) * (r.x + j), sin(a) * (r.y + j))
			draw_line(prev, p, Color(col, _rng.randf_range(0.7, 0.95)), wd)
			prev = p

	func _draw() -> void:
		_rng.seed = 11 if acik else 5
		var s := minf(size.x, size.y)
		var c := size / 2.0
		var wd := maxf(3.0, s * 0.035)
		var r := s * 0.36
		var fc := c - Vector2(s * (0.06 if acik else 0.0), 0)
		_yay(fc, Vector2(r, r * 1.05), 0, TAU, wd)
		# gözler
		for dx in [-0.38, 0.38]:
			var e := fc + Vector2(r * dx, -r * 0.28)
			if acik:
				_yay(e, Vector2(r * 0.1, r * 0.13), 0, TAU, wd * 0.8)
			else:
				_cizgi(e - Vector2(r * 0.14, 0), e + Vector2(r * 0.14, 0), wd * 0.8)  # gözler kısık
		var my := fc.y + r * 0.42
		if acik:
			# kocaman açık ağız + ses dalgaları
			_yay(Vector2(fc.x, my), Vector2(r * 0.3, r * 0.22), 0, TAU, wd)
			for i in 3:
				var rr := r * (0.32 + 0.2 * i)
				_yay(Vector2(fc.x + r * 0.95, my - r * 0.05), Vector2(rr * 0.55, rr), -0.7, 0.7, wd * 0.8)
		else:
			# fermuarlı ağız
			var a := Vector2(fc.x - r * 0.42, my)
			var b := Vector2(fc.x + r * 0.42, my)
			_cizgi(a, b, wd)
			for i in 6:
				var x := lerpf(a.x + r * 0.06, b.x - r * 0.06, i / 5.0)
				_cizgi(Vector2(x, my - r * 0.09), Vector2(x, my + r * 0.09), wd * 0.6)
