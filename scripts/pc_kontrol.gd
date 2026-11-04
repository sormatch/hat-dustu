# Bilgisayar kontrolleri (yalnız masaüstünde eklenir; telefonda yok). main.gd _setup_input ekler.
#   Sağ tık: fareyle bakışı aç / kapat (imleç kilitlenir)   Esc: imleci bırak
#   Sol tık (bakış açıkken): eylem (kapı, telefon, eşya — ekrandaki EYLEM düğmesi)
#   W A S D yürü · Shift koş · E etkileşim · C eğil (main.gd tuş eylemleri)
#   G hareket menüsü · M mikrofon aç/kapa · V bas-konuş · Q telefonu kapat · Tab ayarlar
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
		UI.toast("Sağ tık: fareyle bak · E: etkileşim · Shift: koş · C: eğil · G: hareket · M: mikrofon · V: bas-konuş · Q: telefonu kapat", null, 7.0, "bilgi")


func _input(e: InputEvent) -> void:
	if not is_instance_valid(main) or not bool(main.get("playing")):
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
		KEY_ESCAPE:
			if _kilit:
				_birak()
				get_viewport().set_input_as_handled()
		KEY_M:
			hud.mik_kapat(not bool(hud.get("mik_kapali")))
		KEY_G:
			var b: Button = hud.get("emote_btn")
			if b and b.is_visible_in_tree():
				b.pressed.emit()
		KEY_Q:
			if int(main.get("phone_state")) != 0 and main.has_method("_hang_up"):
				main._hang_up()
		KEY_TAB:
			_birak()
			hud.settings_pressed.emit()
			get_viewport().set_input_as_handled()


func _kilitle() -> void:
	_kilit = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _birak() -> void:
	_kilit = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
