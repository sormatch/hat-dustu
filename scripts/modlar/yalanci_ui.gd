# YALANCI: dolabında bir eşya var; herkeste aynısı, birinde farklısı. Telefonla konuş, sonra yeşil
# tahtada yalancıyı oyla. Yalancı farklı olduğunu bilir ama diğerlerinin eşyasını bilmez.
extends "res://scripts/modlar/mod_ui.gd"

var voted := 0
var seen := false  # dolabı açıp eşyaya baktı mı
var worn := false  # eşyayı kafasına taktı mı


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
			flash("OYLAMA!", "Yalancı kim? Tahtada seç.", GOLD, 1.0)
			g.get_tree().create_timer(1.5).timeout.connect(func() -> void:
				if phase() == "oylama" and voted == 0:
					open_board())
	show_main_button("TAHTA: OYLA", phase() == "oylama")


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
		role_card("SEN YALANCISIN!", Color("#ff3b3b"), "Dolabındaki eşya diğerlerinden FARKLI. Ama onlarınkinin ne olduğunu bilmiyorsun!\nTelefonda çaktırmadan öğren, yalan söyle, kendini gizle.",
			"Kimse bulamazsa +3 · yakalanırsan -1")
	else:
		role_card("DOLABINA BAK", Color("#7dff9f"), "Dolabında bir eşya var. Herkeste aynısı var, sadece BİR kişide farklı.\nTelefonla konuş, sor, yalancıyı bul!",
			"Yalancıyı doğru oylarsan +1")


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


func _item_card() -> void:
	if not (phase() in ["anons", "telefon"]):
		return
	close_card()
	var m: Array = g._clean_modal(640)
	card = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UI.label("Dolabında:", 22, Color(0.8, 0.82, 0.9), true))
	v.add_child(UI.title(item(), 46, Color("#ffcf8a"), true))
	if liar():
		v.add_child(UI.title("BU EŞYA FARKLI! Sen yalancısın.", 24, RED, true))
	else:
		v.add_child(UI.label("Herkeste aynısı var... biri hariç.", 22, Color.WHITE, true))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	var wear := UI.button("ÇIKAR" if worn else "KAFANA TAK", "orange", 60, 22, "", 240)
	wear.pressed.connect(func() -> void:
		_wear(not worn)
		close_card())
	row.add_child(wear)
	var ok := UI.button("TAMAM", "primary", 60, 22, "", 200)
	ok.pressed.connect(close_card)
	row.add_child(ok)
	v.add_child(row)
	play("parilti", -6.0)


# Eşyayı kafana tak (aynada görürsün, diğerleri de üstünde görür) ya da dolaba geri koy.
func _wear(on: bool) -> void:
	worn = on
	var look: Dictionary = w.profile.look.duplicate()
	if on:
		look["sapka"] = str(secret.get("esya", ""))
		_cell().set_locker_item("")
		w.hud.show_toast("Aynaya bak: sol duvar, masanın üstünde!")
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
	var pn: String = {"anons": "EŞYALAR DOLAPTA", "telefon": "KONUŞ", "oylama": "OYLAMA"}.get(phase(), "")
	var info := ""
	match phase():
		"oylama":
			info = ("Oyun: %s · " % pname(voted) if voted else "Yalancıyı tahtada seç! · ") + "oy veren %d/%d" % [int(state.get("oy_veren", 0)), state.get("players", []).size()]
		_:
			if not seen:
				info = "Dolabını aç, eşyana bak! (sol duvar)"
			elif liar():
				info = "YALANCISIN · eşyan: %s · çaktırma!" % item()
			else:
				info = "Eşyan: %s · farklı olanı bul" % item()
	return ["YALANCI  ·  " + pn, info]


func help_rows() -> Array:
	return [
		["lock", "Dolabını aç: içinde bir eşya var. Herkeste aynısı, birinde farklısı."],
		["phone", "Telefonla konuş. Yalancı farklı olduğunu bilir ama sizinkini bilmez: yalan söyler."],
		["deal", "Süre bitince yeşil tahtada yalancıyı oyla."],
		["trophy", "Doğru oy +1. Yalancı yakalanırsa -1, kaçarsa +3."],
	]


func open_board() -> void:
	if phase() != "oylama" or secret.is_empty():
		return
	var m := chalk_modal("Yalancı kim?", "Dolabında farklı eşya olan kişiyi seç. Değiştirebilirsin.", 980.0)
	var v: VBoxContainer = m[1]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(grid)
	for id in state.get("players", []):
		if int(id) == me():
			continue
		var pid := int(id)
		var b := chalk_button(pname(pid), "carpi" if voted == pid else "", voted == pid, 330)
		b.pressed.connect(func() -> void:
			voted = pid
			g.decided.emit({"oy": pid})
			chalk_sfx()
			play("sec", -4.0)
			g._update_banner()
			close_panel()
			flash("OYUN: " + pname(pid), "", GOLD, 0.9))
		grid.add_child(b)


func on_result(d: Dictionary) -> void:
	show_main_button("", false)
	var rows := []
	rows.append(UI.title("Yalancı: %s" % str(d.get("yalanci_ad", "?")), 34, RED, true))
	rows.append(UI.label("Herkeste: %s   ·   Onda: %s" % [str(d.get("cogunluk", "")), str(d.get("farkli", ""))], 21, Color.WHITE, true))
	var caught := bool(d.get("yakalandi", false))
	rows.append(UI.title("YAKALANDI!" if caught else "KAÇTI!", 40, GREEN if caught else GOLD, true))
	var tally = d.get("oylar", {})
	if typeof(tally) == TYPE_DICTIONARY and not tally.is_empty():
		var parts := []
		for k in tally:
			parts.append("%s: %d" % [pname(int(k)), int(tally[k])])
		rows.append(UI.label("Oylar  ·  " + "   ".join(parts), 19, Color(0.8, 0.82, 0.9), true))
	result_modal("YALANCI", rows, d)
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
