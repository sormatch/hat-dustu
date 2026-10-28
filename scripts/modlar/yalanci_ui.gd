# YALANCI: dolabında bir eşya var; herkeste aynısı, birinde farklısı. Telefonla konuş, sonra yeşil
# tahtada yalancıyı oyla. Yalancı farklı olduğunu bilir ama diğerlerinin eşyasını bilmez.
extends "res://scripts/modlar/mod_ui.gd"

var voted := 0
var seen := false  # dolabı açıp eşyaya baktı mı
var worn := false  # eşyayı kafasına taktı mı
var _thumbs: Node  # eşya kartındaki küçük resim (karakterin eşyayı takmış hâli)


func liar() -> bool:
	return bool(secret.get("yalanci", false))


func item() -> String:
	return str(secret.get("esya_ad", "?"))


func on_state(d: Dictionary, entered: bool) -> void:
	state = d
	if not entered:
		return
	match phase():
		"anons":
			voted = 0
			seen = false
			play("anons")
		"telefon":
			close_card()
			play("sec", -6.0)
		"oylama":
			close_card()
			_cell().set_locker(false)
			play("anons", -4.0)
			flash("OYLAMA", "Yalancı kim?", UI.AMBER, 1.0)
			g.get_tree().create_timer(1.5).timeout.connect(func() -> void:
				if phase() == "oylama" and voted == 0:
					open_board())
	show_main_button("OYLA", phase() == "oylama")


func _cell() -> Node3D:
	return w.cells[w.my_cell]


func on_secret(d: Dictionary) -> void:
	secret = d
	_cell().set_locker_item(str(d.get("esya", "")))
	_cell().set_locker(false)
	show_card()


func show_card() -> void:
	if secret.is_empty():
		return
	if liar():
		role_card("SEN YALANCISIN!", UI.KIRMIZI, "Eşyan farklı. Çaktırma.")
	else:
		role_card("DOLABINA BAK", UI.YESIL, "Birinin eşyası farklı. Onu bul.")


func targets(cell: int) -> Array:
	if cell != w.my_cell or secret.is_empty() or not (phase() in ["anons", "telefon"]):
		return []
	return [["dolap", _cell().locker_world(), 2.3, "Dolabı kapat" if _cell().locker_open else "Dolabı aç"]]


func do_action(n: String) -> void:
	if n != "dolap":
		return
	var c := _cell()
	c.set_locker(not c.locker_open)
	if c.locker_open:
		seen = true
		g.get_tree().create_timer(0.55).timeout.connect(_item_card)
	g._update_banner()


func tahta_var() -> bool:
	return phase() == "oylama" and not secret.is_empty()


func tahta_yazisi() -> String:
	return "Oyla"


# HUD işareti: eşyana bakana kadar dolabın yeri
func hedef(_aradi: bool) -> Array:
	if secret.is_empty() or seen or not (phase() in ["anons", "telefon"]):
		return []
	return ["dolap", "DOLABINA BAK", "envanter", UI.AMBER]


func _item_card() -> void:
	if not (phase() in ["anons", "telefon"]):
		return
	close_card()
	var m: Array = g._clean_modal(560)
	card = m[0]
	var v: VBoxContainer = m[1]
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	# eşya kartı: senin karakterin o eşyayı takmış hâli (mağaza küçük resmi), nadirlik çerçevesinde
	var col := UI.KIRMIZI if liar() else UI.AMBER
	var fr := UI.card_frame("epik" if liar() else "efsane", Vector2(230, 250))
	fr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var pic := TextureRect.new()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(190, 210)
	pic.texture = OI.rozet_tex("yalanci", 200)  # küçük resim gelene kadar
	fr.add_child(pic)
	v.add_child(fr)
	if not is_instance_valid(_thumbs):
		_thumbs = load("res://scripts/thumbs.gd").new()
		add_child(_thumbs)
	if w and w.profile:
		_thumbs.request(w.profile.look, "sapka", str(secret.get("esya", "")), pic, true)
	v.add_child(UI.title(item(), 40 if item().length() < 18 else 32, col, true))
	if liar():
		v.add_child(UI.title("FARKLI OLAN SENSİN!", UI.FS_ORTA, UI.KIRMIZI, true))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", UI.B_M)
	var wear := UI.button("ÇIKAR" if worn else "KAFANA TAK", "ana", UI.BTN_H, 26, "", 260)
	wear.pressed.connect(func() -> void:
		_wear(not worn)
		close_card())
	row.add_child(wear)
	var ok := UI.button("TAMAM", "ikincil", UI.BTN_H, 26, "", 200)
	ok.pressed.connect(close_card)
	row.add_child(ok)
	v.add_child(row)
	# kart dönerek açılır
	fr.pivot_offset = Vector2(115, 125)
	fr.scale = Vector2(0.05, 1.0)
	fr.create_tween().tween_property(fr, "scale", Vector2.ONE, 0.35).set_delay(0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	play("parilti", -6.0)


# Eşyayı kafana tak (aynada görürsün, diğerleri de üstünde görür) ya da dolaba geri koy.
func _wear(on: bool) -> void:
	worn = on
	var look: Dictionary = w.profile.look.duplicate()
	if on:
		look["sapka"] = str(secret.get("esya", ""))
		_cell().set_locker_item("")
		w.hud.show_toast("Ayna sol duvarda.")
		play("kumas", -2.0)
	else:
		_cell().set_locker_item(str(secret.get("esya", "")))
	w.player.set_look(look)
	w.net.send({"t": "profil", "ad": w.profile.player_name, "g": look})


func on_event(d: Dictionary) -> void:
	if str(d.get("tur", "")) == "oy":
		state["oy_veren"] = int(d.get("oy_veren", 0))
		g._update_banner()


func banner() -> Array:
	match phase():
		"oylama":
			var n := tr("%d/%d oy") % [int(state.get("oy_veren", 0)), state.get("players", []).size()]
			return [tr("OYUN: %s") % up(pname(voted)) if voted else "YALANCIYI SEÇ", n]
		_:
			if not seen:
				return ["DOLABINA BAK", "Sol duvar"]
			if liar():
				return ["YALANCISIN", item()]
			return ["EŞYAN", item()]


func help_rows() -> Array:
	return [
		["envanter", "Dolabındaki eşyaya bak"],
		["telefon", "Biri farklı: konuş, onu bul"],
		["engelle", "Süre bitince yalancıyı oyla"],
	]


# Oylama tahtası: her oyuncu tebeşirle çizilmiş bir "kişi" kartı; seçtiğin sarı ve taramalı.
func open_board() -> void:
	if phase() != "oylama" or secret.is_empty():
		return
	var m := chalk_modal("Yalancı kim?", "", 1000.0)
	var v: VBoxContainer = m[1]
	var sp0 := Control.new()
	sp0.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp0)
	var others: Array = []
	for id in state.get("players", []):
		if int(id) != me():
			others.append(int(id))
	var grid := GridContainer.new()
	grid.columns = mini(4, maxi(1, others.size())) if others.size() <= 4 else ceili(others.size() / 2.0)
	grid.add_theme_constant_override("h_separation", UI.B_L)
	grid.add_theme_constant_override("v_separation", UI.B_M)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(grid)
	var cw := clampf(760.0 / grid.columns - UI.B_L, 160.0, 220.0)
	var ch := 200.0 if others.size() <= 4 else 150.0
	for pid in others:
		var on: bool = voted == pid
		var col := OI.CHALK_SARI if on else CHALK
		var b := chalk_button("", "", on, cw, ch, col)
		var kv := VBoxContainer.new()
		kv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		kv.alignment = BoxContainer.ALIGNMENT_CENTER
		kv.add_theme_constant_override("separation", 0)
		kv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var kisi := chalk_draw("kisi", Vector2(ch * 0.5, ch * 0.5), col)
		kisi.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		kv.add_child(kisi)
		var nl := chalk(pname(pid), 32 if pname(pid).length() < 11 else 26, col)
		nl.clip_text = true
		nl.custom_minimum_size.x = cw - 20
		kv.add_child(nl)
		b.add_child(kv)
		b.pressed.connect(func() -> void:
			voted = pid
			g.decided.emit({"oy": pid})
			chalk_sfx()
			play("sec", -4.0)
			g._update_banner()
			close_panel()
			flash(tr("OYUN: %s") % up(pname(pid)), "", UI.AMBER, 0.9))
		grid.add_child(b)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)


func on_result(d: Dictionary) -> void:
	show_main_button("", false)
	var caught := bool(d.get("yakalandi", false))
	var liar := up(str(d.get("yalanci_ad", "?")))
	var head := tr("YALANCI %s YAKALANDI!" if caught else "YALANCI %s KAÇTI!") % liar
	# oylar: kim kaç oy aldı (yalancı kırmızı)
	var liar_id := int(d.get("yalanci", 0))
	var items := []
	var tally = d.get("oylar", {})
	if typeof(tally) == TYPE_DICTIONARY:
		var keys: Array = tally.keys()
		keys.sort_custom(func(x, y) -> bool: return int(tally[x]) > int(tally[y]))
		for k in keys:
			var id := int(k)
			items.append({"a": (tr("%d OY") % int(tally[k])) if int(tally[k]) != 1 else tr("1 OY"), "b": pname(id), "c": "YALANCI" if id == liar_id else "", "col": RED, "me": id == me()})
	var mood := (-1 if caught else 1) if liar_id == me() else 0
	result_modal(head, GREEN if caught else RED, [tr("Herkeste: %s   ·   Onda: %s") % [tr(str(d.get("cogunluk", ""))), tr(str(d.get("farkli", "")))]], d, items, mood)
	if caught:
		play("kilit", -2.0)


func cleanup() -> void:
	if worn and w:
		worn = false
		w.player.set_look(w.profile.look)
		w._send_profile()
	close_panel()
	close_card()
	show_main_button("", false)
	if w and w.cells.size() > w.my_cell:
		_cell().set_locker(false)
		_cell().set_locker_item("")
