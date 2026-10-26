# C4: bir hücrede aniden bomba belirir. Kapılar açılır; bomba sendeyse birine yaklaş, "Bombayı ver":
# bomba ona geçer, sen kendi hücrene ışınlanırsın. Bomba elindeyken kırmızı ışığı yanıp söner, bipler.
# Ne zaman patlayacağını kimse bilmez; patlayınca elinde olan -2, diğerleri +1.
extends "res://scripts/modlar/mod_ui.gd"

const Props := preload("res://scripts/modlar/props.gd")
const AimMod := preload("res://scripts/modlar/aim_mod.gd")

var holder := 0
var _pending := false  # "ver" yollandı, cevap bekleniyor
var _fp: Node3D  # birinci şahısta elimdeki bomba
var _on_remote: Node3D  # başkasının elindeki bomba
var _remote_id := 0
var _remote_w := 0.0  # uzaktaki elin poza geçiş ağırlığı
var _blink_t := 0.0
var _bip: AudioStreamPlayer
var _bip3d: AudioStreamPlayer3D
var _vignette: ColorRect
var _boomed := false
var _boom_node: Node3D  # patlama (yanık izi oyun bitene kadar kalır)
var _scr_t := 0.0
var _muffle: AudioEffectLowPassFilter


func _ready() -> void:
	_bip = AudioStreamPlayer.new()
	_bip.stream = load("res://assets/ses/c4_bip.ogg")
	_bip.volume_db = -6.0
	add_child(_bip)
	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float k = 0.0;
void fragment() {
	float d = distance(UV, vec2(0.5));
	COLOR = vec4(0.9, 0.05, 0.02, smoothstep(0.35, 0.75, d) * k);
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_vignette.material = mat
	_vignette.visible = false
	root().add_child(_vignette)
	root().move_child(_vignette, 0)


func on_state(d: Dictionary, entered: bool) -> void:
	state = d
	var h := int(d.get("bomba", holder))
	if h != holder or entered:
		_set_holder(h)
	if not entered:
		return
	match phase():
		"anons":
			_boomed = false
			_pending = false
			_intro()
		"bomba":
			close_card()
			play("buzzer", 0.0)
			for c in w.cells:
				if not c.locked:
					c.set_door(true)
			if holder == me():
				flash("KAPILAR AÇILDI!", "Bombayı birine ver!", UI.KIRMIZI, 1.4)
			else:
				flash("KAPILAR AÇILDI!", tr("%s kaç!") % abl(pname(holder)), UI.AMBER, 1.4)


func _intro() -> void:
	play("alarm", 0.0)
	play("c4_kur", -2.0)
	for i in 3:
		g.get_tree().create_timer(i * 0.55).timeout.connect(func() -> void: screen_flash(Color(1, 0.1, 0.05), 0.45, 0.08, 0.35))
	g.get_tree().create_timer(1.4).timeout.connect(show_card)
	w._shake(0.4, 0.03)


func show_card() -> void:
	if not (phase() in ["anons", "bomba"]):
		return
	if holder == me():
		role_card("BOMBA SENDE!", UI.KIRMIZI, "Birine yaklaş ve ver. Ne zaman patlayacağı belli değil!")
	else:
		role_card("UZAK DUR!", UI.AMBER, tr("Bomba %s. Patladığında yanında olma!") % loc(pname(holder)))


func _set_holder(h: int) -> void:
	holder = h
	_fp_bomb(holder == me() and phase() in ["anons", "bomba"])
	_remote_bomb(holder if holder != me() and phase() in ["anons", "bomba"] else 0)
	g._update_banner()


# Elimdeki bomba: karakterin gerçek sol avucunda, ekranı bana dönük.
func _fp_bomb(on: bool) -> void:
	var p: CharacterBody3D = w.player
	if on and not is_instance_valid(_fp):
		_fp = Node3D.new()
		Props.c4(_fp)
		p.hold_item(0, _fp, AimMod.item_offset("c4", 0))
		p.set_hand_pose(0, "c4")
	elif not on and is_instance_valid(_fp):
		p.hold_item(0, null)
		_fp.queue_free()
		_fp = null
		p.set_hand_pose(0, "")
	_vignette.visible = on


# Başkasının elindeki bomba: o oyuncunun gerçek sol avucunda, göğsünün önünde.
func _remote_bomb(id: int) -> void:
	if id == _remote_id and is_instance_valid(_on_remote):
		return
	_release_remote_pose()
	if is_instance_valid(_on_remote):
		_on_remote.queue_free()
	_on_remote = null
	_remote_id = id
	if id == 0 or not w.remotes.has(id):
		return
	var n := Node3D.new()
	w.add_child(n)
	Props.c4(n)
	_bip3d = AudioStreamPlayer3D.new()
	_bip3d.stream = load("res://assets/ses/c4_bip.ogg")
	_bip3d.unit_size = 2.5
	_bip3d.max_distance = 16.0
	n.add_child(_bip3d)
	_on_remote = n
	_remote_w = 0.0
	_hold_remote(0.0)


func _release_remote_pose() -> void:
	if _remote_id == 0 or not w.remotes.has(_remote_id):
		return
	var pose: Node = AimMod.of_body(w.remotes[_remote_id].body)
	if pose:
		pose.mode = ""
		pose.aim_l = 0.0
		pose.hold(0, null)


# Her karede: bomba uzaktakinin sol avucunda (gövdesi yeniden kurulsa da).
func _hold_remote(delta: float) -> void:
	if not is_instance_valid(_on_remote) or not w.remotes.has(_remote_id):
		return
	var pose: Node = AimMod.of_body(w.remotes[_remote_id].body)
	if not pose:
		return
	_remote_w = minf(1.0, _remote_w + delta * 3.0)
	pose.mode = "c4"
	pose.aim_l = smoothstep(0.0, 1.0, _remote_w)
	pose.hold(0, _on_remote, AimMod.item_offset("c4", 0))


func _blink(node: Node3D, on: bool, scramble: bool) -> void:
	if not is_instance_valid(node):
		return
	for b in node.find_children("*", "Node3D", true, false):
		if b.has_meta("led"):
			(b.get_meta("led") as StandardMaterial3D).emission_energy_multiplier = 9.0 if on else 0.2
			(b.get_meta("light") as OmniLight3D).light_energy = 1.4 if on else 0.0
			if scramble:
				# sayaç bozuk: rastgele rakamlar, ara sıra "--:--" (ne zaman patlayacağı belli değil)
				var scr: Label3D = b.get_meta("ekran")
				scr.text = "--:--" if randf() < 0.15 else "%02d:%02d" % [randi() % 100, randi() % 60]


func process(delta: float) -> void:
	if not (phase() in ["anons", "bomba"]) or _boomed:
		return
	# uzaktaki oyuncunun gövdesi sonradan gelmiş olabilir
	if holder != me() and holder != 0 and not is_instance_valid(_on_remote) and w.remotes.has(holder):
		_remote_bomb(holder)
	_hold_remote(delta)
	var before := _blink_t
	_blink_t = fmod(_blink_t + delta, 1.0)
	var on := _blink_t < 0.14
	_scr_t += delta
	var scramble := _scr_t > 0.09
	if scramble:
		_scr_t = 0.0
	_blink(_fp, on, scramble)
	_blink(_on_remote, on, scramble)
	if _blink_t < before:
		if holder == me():
			_bip.play()
		elif is_instance_valid(_bip3d):
			_bip3d.play()
	if holder == me():
		(_vignette.material as ShaderMaterial).set_shader_parameter("k", 0.55 + 0.35 * sin(Time.get_ticks_msec() / 160.0))


func doors_open() -> bool:
	return phase() == "bomba"


func targets(_cell: int) -> Array:
	if holder != me() or phase() != "bomba" or _pending:
		return []
	var out := []
	var alive: Array = state.get("players", [])
	for id in w.remotes:
		if not (int(id) in alive):
			continue
		var p: Vector3 = w.remotes[id].root.global_position + Vector3(0, 1.2, 0)
		out.append(["ver:%d" % int(id), p, 2.1, tr("Bombayı ver: %s") % pname(int(id))])
	return out


func do_action(n: String) -> void:
	if not n.begins_with("ver:") or _pending or holder != me():
		return
	_pending = true
	g.decided.emit({"ver": int(n.substr(4))})
	g.get_tree().create_timer(2.0).timeout.connect(func() -> void: _pending = false)


func on_event(d: Dictionary) -> void:
	match str(d.get("tur", "")):
		"verdin":
			_pending = false
			play("odul", -4.0)
			_teleport_home(true)
		"verdi":
			var to := int(d.kime)
			var from := int(d.kimden)
			_set_holder(to)
			if to == me():
				play("alarm", -2.0)
				screen_flash(Color(1, 0.1, 0.05), 0.5, 0.05, 0.4)
				flash("BOMBA SENDE!", tr("%s verdi!") % pname(from), UI.KIRMIZI, 1.4)
			elif from != me():
				w.hud.show_toast(tr("Bomba artık %s!") % loc(pname(to)))
		"patlama":
			_explode(int(d.kim))
			g._update_banner()


func _teleport_home(fade: bool) -> void:
	var p: CharacterBody3D = w.player
	var home: Vector3 = w.cells[w.my_cell].spawn_world()
	var go := func() -> void:
		if p.seated:
			p.seated = false
			p.col.disabled = false
			p.head.position.y = p.EYE_STAND
		p.busy = false
		p.global_position = home
		p.velocity = Vector3.ZERO
		p.rotation.y = 0.0
	if not fade:
		if p.global_position.distance_to(home) > 1.0:
			go.call()
		return
	play("isinlan", 0.0)
	var f := ColorRect.new()
	f.color = Color(0.4, 0.9, 1.0, 0.0)
	f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root().add_child(f)
	var tw := f.create_tween()
	tw.tween_property(f, "color", Color(0.85, 0.97, 1.0, 1.0), 0.22)
	tw.tween_callback(go)
	tw.tween_interval(0.12)
	tw.tween_property(f, "color", Color(0.4, 0.9, 1.0, 0.0), 0.4)
	tw.tween_callback(f.queue_free)
	flash("IŞINLANDIN!", "", UI.MAVI, 1.0)


func _explode(who: int) -> void:
	_boomed = true
	var pos: Vector3
	if who == me():
		# elimde: patlama hemen önümde (kameranın içinde değil)
		var fwd: Vector3 = -w.player.camera.global_transform.basis.z
		pos = w.player.global_position + Vector3(0, 1.0, 0) + Vector3(fwd.x, 0, fwd.z).normalized() * 1.2
	elif w.remotes.has(who):
		pos = w.remotes[who].root.global_position + Vector3(0, 1.0, 0)
	else:
		pos = w.cells[0].global_position + Vector3(0, 1.0, 0)
	_fp_bomb(false)
	_remote_bomb(0)
	_vignette.visible = false
	if is_instance_valid(_boom_node):
		_boom_node.queue_free()
	_boom_node = Props.explosion(w, pos, 0.0)
	var dist: float = w.player.global_position.distance_to(pos)
	if who == me():
		_sound("c4_patlama", 6.0)
		screen_flash(Color(1, 1, 1), 1.0, 0.02, 0.35)
		g.get_tree().create_timer(0.3).timeout.connect(func() -> void: screen_flash(Color(1, 0.42, 0.1), 0.8, 0.05, 1.6))
		g.get_tree().create_timer(0.2).timeout.connect(func() -> void: play("cinlama", -2.0))
		w._shake(1.6, 0.22)
		_deafen(1.0)
		flash("BOOM!", "Bomba elinde patladı!", RED, 2.2)
	else:
		var k := clampf(1.0 - dist / 22.0, 0.1, 1.0)
		if dist < 12.0:
			var snd := AudioStreamPlayer3D.new()
			snd.stream = load("res://assets/ses/c4_patlama.ogg")
			snd.unit_size = 9.0
			snd.max_db = 6.0
			snd.max_distance = 60.0
			_boom_node.add_child(snd)
			snd.play()
		else:
			_sound("c4_uzak", linear_to_db(k) + 2.0)
		screen_flash(Color(1, 0.7, 0.3), 0.65 * k, 0.03, 0.6)
		w._shake(0.9, 0.12 * k)
		if dist < 7.0:
			_deafen(k)
		flash("BOOM!", tr("%s elinde patladı!") % gen(pname(who)), Color("#ff8a3a"), 2.0)


func _sound(n: String, vol: float) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = load("res://assets/ses/%s.ogg" % n)
	p.volume_db = vol
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


# Sağırlaşma: patlamadan sonra tüm sesler boğuklaşır, yavaşça geri gelir.
func _deafen(k: float) -> void:
	var bus := AudioServer.get_bus_index("Master")
	if _muffle == null:
		_muffle = AudioEffectLowPassFilter.new()
		AudioServer.add_bus_effect(bus, _muffle)
	_muffle.cutoff_hz = lerpf(4000.0, 350.0, k)
	var tw := create_tween()
	tw.tween_interval(0.8)
	tw.tween_method(func(v: float) -> void:
		if _muffle:
			_muffle.cutoff_hz = v, _muffle.cutoff_hz, 20000.0, 3.5).set_ease(Tween.EASE_IN)
	tw.tween_callback(_undeafen)


func _undeafen() -> void:
	if _muffle == null:
		return
	var bus := AudioServer.get_bus_index("Master")
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) == _muffle:
			AudioServer.remove_bus_effect(bus, i)
			break
	_muffle = null


func banner() -> Array:
	if _boomed or not (phase() in ["anons", "bomba"]):
		return ["", ""]
	if holder == me():
		return ["BOMBA SENDE", "Birine yaklaş, ver!"]
	if holder == 0:
		return ["", ""]
	return [tr("BOMBA: %s") % up(pname(holder)), "Ondan uzak dur!"]


func help_rows() -> Array:
	return [
		["kasa", "Bir hücrede C4 belirir"],
		["kapi", "Kapılar açılır: koş!"],
		["el", "Bomba sendeyse birine ver"],
	]


func on_result(d: Dictionary) -> void:
	_fp_bomb(false)
	_remote_bomb(0)
	_vignette.visible = false
	var who := int(d.get("patlayan", 0))
	var head := tr("BOOM! SENİN ELİNDE PATLADI") if who == me() else tr("BOOM! %s ELİNDE PATLADI") % up(gen(str(d.get("patlayan_ad", "?"))))
	result_modal(head, RED, [tr("Bomba %d kez el değiştirdi") % int(d.get("verilen", 0))], d, [], -1 if who == me() else 1)
	g.get_tree().create_timer(1.6).timeout.connect(_restore)


# Herkes kendi hücresine döner, kapılar kapanır (sıradaki oyun hücrelerde oynanır).
func _restore() -> void:
	if not w:
		return
	var away: bool = w.player.global_position.distance_to(w.cells[w.my_cell].spawn_world()) > 2.6
	_teleport_home(away)
	for c in w.cells:
		if not c.locked and c.door_open:
			c.set_door(false)


func cleanup() -> void:
	_undeafen()
	if is_instance_valid(_boom_node):
		_boom_node.queue_free()
	_fp_bomb(false)
	_remote_bomb(0)
	if is_instance_valid(_vignette):
		_vignette.queue_free()
	close_panel()
	close_card()
	if w and phase() in ["anons", "bomba"]:
		_restore()
