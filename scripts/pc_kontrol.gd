# Bilgisayar kontrolleri (yalnız masaüstünde eklenir; telefonda yok). main.gd _setup_input ekler.
#   Sağ tık: fareyle bakışı aç / kapat (imleç kilitlenir)   Esc: imleci bırak
#   Sol tık (bakış açıkken): eylem (kapı, telefon, eşya — ekrandaki EYLEM düğmesi)
#   W A S D yürü · Shift koş · E etkileşim · C eğil (main.gd tuş eylemleri)
#   G hareket menüsü · M mikrofon aç/kapa · V bas-konuş · Q telefonu kapat · Tab ayarlar aç/kapa · F11 tam ekran · I tuş bilgisi paneli
extends Node

const HASSAS := 0.8  # fare hassasiyeti (ayarlardaki hassasiyet player.look içinde ayrıca uygulanır)
const UI := preload("res://scripts/ui.gd")

var main: Node
var _kilit := false
var _ipucu := false


func _process(_delta: float) -> void:
	if not is_instance_valid(main):
		return
	var oyunda: bool = bool(main.get("playing"))
	# telefon ekranı (rehber, arama) ya da oyun dışı: imleç serbest olmalı
	var tel: int = int(main.get("phone_state")) if main.get("phone_state") != null else 0
	if _kilit and (not oyunda or tel == 2 or not get_window().has_focus()):
		_birak()
	if oyunda and not _ipucu:
		_ipucu = true
		UI.toast("I: tuş bilgisi", null, 4.0, "bilgi")
		if OS.get_cmdline_user_args().has("tuslar=1"):
			_panel_ac_kapa()  # test pozu: panel açık
	if not oyunda and _panel and _panel.visible:
		_panel.visible = false


# I tuşu: tuşların ne işe yaradığını alt alta gösteren panel (I ile açılır / kapanır)
const TUSLAR := [
	["W A S D", "Yürü"],
	["Shift", "Koş"],
	["E", "Etkileşim (telefon, kapı, eşya)"],
	["C", "Eğil"],
	["G", "Hareket (emote) menüsü"],
	["M", "Mikrofonu aç / kapat"],
	["V", "Bas-konuş (ayarlarda açıksa)"],
	["Q", "Telefonu kapat"],
	["Tab", "Ayarları aç / kapat"],
	["F11", "Tam ekran"],
	["Sağ tık", "Fareyle bakışı aç / kapat"],
	["Sol tık", "Eylem (bakış açıkken)"],
	["Sol tık + sürükle", "Etrafa bak"],
	["Esc", "İmleci bırak"],
	["I", "Bu paneli aç / kapat"],
]
var _panel: Control


func _panel_ac_kapa() -> void:
	if _panel == null:
		_panel_kur()
	_panel.visible = not _panel.visible


func _panel_kur() -> void:
	var katman := CanvasLayer.new()
	katman.layer = 13
	add_child(katman)
	var pc := PanelContainer.new()
	var st := UI.flat(Color(UI.YUZEY, 0.92), Color(UI.AMBER, 0.6), UI.R_ORTA)
	st.set_border_width_all(2)
	st.content_margin_left = UI.B_M
	st.content_margin_right = UI.B_M
	st.content_margin_top = UI.B_S
	st.content_margin_bottom = UI.B_S
	pc.add_theme_stylebox_override("panel", st)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.position = Vector2(24, 100)  # sol üst (ayar düğmesinin altı)
	katman.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	pc.add_child(v)
	v.add_child(UI.title("TUŞLAR", UI.FS_ORTA, UI.AMBER))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", UI.B_M)
	g.add_theme_constant_override("v_separation", 4)
	v.add_child(g)
	for t in TUSLAR:
		var k := UI.label(str(t[0]), UI.FS_KUCUK + 2, UI.AMBER)
		k.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		g.add_child(k)
		g.add_child(UI.label(str(t[1]), UI.FS_KUCUK + 2, UI.METIN))
	_panel = pc
	_panel.visible = false


func _input(e: InputEvent) -> void:
	if not is_instance_valid(main):
		return
	# her yerde (menüde de): F11 tam ekran, Tab ayarları aç / kapat
	if e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode == KEY_F11:
			_tam_ekran()
			get_viewport().set_input_as_handled()
			return
		if e.physical_keycode == KEY_TAB and bool(main.get("hazir_mi")) and not (get_viewport().gui_get_focus_owner() is LineEdit):
			_ayarlar_ac_kapa()  # yazı alanındayken Tab bir sonraki alana geçer (giriş / kayıt ekranı)
			get_viewport().set_input_as_handled()
			return
	if not bool(main.get("playing")):
		return
	var hud: Node = main.get("hud")
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_RIGHT:
			if _kilit:
				_birak()
			else:
				_kilitle()
			get_viewport().set_input_as_handled()
		elif e.button_index == MOUSE_BUTTON_LEFT and _kilit and hud:
			hud.action_pressed.emit()  # bakış açıkken sol tık = eylem düğmesi
			get_viewport().set_input_as_handled()
		return
	if e is InputEventMouseMotion and _kilit:
		var p: Node = main.get("player")
		if p:
			p.look(e.relative * HASSAS)
		get_viewport().set_input_as_handled()
		return
	if not (e is InputEventKey) or e.echo or hud == null:
		return
	var k: int = e.physical_keycode
	if k == KEY_V:
		hud.ptt_changed.emit(e.pressed)  # bas-konuş (ayarlarda açıksa)
		return
	if not e.pressed:
		return
	match k:
		KEY_I:
			_panel_ac_kapa()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if _kilit:
				_birak()
				get_viewport().set_input_as_handled()
		KEY_M:
			hud.mik_kapat(not bool(hud.get("mik_kapali")))
		KEY_G:
			if hud.has_method("emote_tusu"):
				hud.emote_tusu()
		KEY_Q:
			if int(main.get("phone_state")) != 0 and main.has_method("_hang_up"):
				main._hang_up()


func _tam_ekran() -> void:
	var tam := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if tam else DisplayServer.WINDOW_MODE_FULLSCREEN)


# Açık ayarlar penceresi (main'in çocuğu settings.gd) ya da null
func _acik_ayarlar() -> Node:
	for c in main.get_children():
		var s: Script = c.get_script()
		if s and s.resource_path == "res://scripts/settings.gd" and not c.is_queued_for_deletion():
			return c
	return null


func _ayarlar_ac_kapa() -> void:
	var st := _acik_ayarlar()
	if st:
		if st.has_method("_close"):
			st._close()  # kayarak kapanır, ayarlar uygulanır (closed sinyali)
		return
	_birak()
	var hud: Node = main.get("hud")
	if bool(main.get("playing")) and hud:
		hud.settings_pressed.emit()
	elif main.has_method("open_settings"):
		main.open_settings()


func _kilitle() -> void:
	_kilit = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _birak() -> void:
	_kilit = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
