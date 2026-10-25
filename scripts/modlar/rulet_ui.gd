# RUS RULETİ: herkes koridordaki yuvarlak masanın etrafına ışınlanır, tek lamba altında oynanır.
# Silah kimdeyse elinde altıpatar durur; "Kendine sık" ya da birini seç. Her atışta herkes aynı gerilimi
# yaşar: horoz sesi, tambur döner, kalp atar... BAM ya da TIK. Ölen yere düşer, cesedi orada kalır,
# konuşamaz (sesi kimseye gitmez), izleyici olur.
extends "res://scripts/modlar/mod_ui.gd"

const Props := preload("res://scripts/modlar/props.gd")
const AimMod := preload("res://scripts/modlar/aim_mod.gd")
const CENTER := Vector3(3.9, 0.0, 0.0)  # koridorun ortası (iki hücre kapısının arası)
const RADIUS := 1.0  # sandalyelerin masaya uzaklığı

const CHANCES := [15, 35, 50, 100]
const LOADED := [1, 2, 3, 6]  # altı yuvadan kaçı dolu (≈ şans)

var holder := 0
var stage := 0
var alive: Array = []
var dead: Array = []
var turn_left := 0.0
var busy := false  # atış canlandırması sürüyor
var _hud: Control
var _drum: Control
var _who: Label
var _pct: Label
var _timer: Label
var _bar: Control  # silah sendeyken: düğmeler
var _gun: Node3D
var _dead_ov: Control
var _beat: AudioStreamPlayer
var _arena: Node3D  # masa, lamba
var _remote_gun: Node3D  # başkasının elindeki altıpatar
var _remote_gun_id := 0
var _gun_aim_at := Vector3.ZERO  # uzaktaki silahın baktığı nokta (boşta: ZERO)
var _corpses := {}  # ölen id -> kan izi
var _i_died := false


class Drum extends Control:
	var loaded := 1
	var spin := 0.0
	var hot := 0.0  # atış parlaması

	func _process(_delta: float) -> void:
		if hot > 0.0:
			queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.46
		draw_circle(c, r, Color("#2a2d33"))
		draw_arc(c, r, 0, TAU, 48, Color("#8d939c"), 4.0)
		draw_arc(c, r * 0.94, 0, TAU, 48, Color("#15171a"), 2.0)
		for i in 6:
			var a := spin + i * TAU / 6.0 - PI / 2
			var p := c + Vector2(cos(a), sin(a)) * r * 0.58
			var full := i < loaded
			draw_circle(p, r * 0.25, Color("#0c0d0f"))
			if full:
				draw_circle(p, r * 0.2, Color("#d8a63a"))
				draw_circle(p, r * 0.11, Color("#8a5a1a"))
			draw_arc(p, r * 0.25, 0, TAU, 20, Color("#5a5f68"), 2.0)
		draw_circle(c, r * 0.14, Color("#6b7079"))
		if hot > 0.0:
			draw_circle(c, r * 1.1, Color(1.0, 0.55, 0.2, hot * 0.5))


func _ready() -> void:
	_hud = PanelContainer.new()
	var st := UI.flat(Color(0.06, 0.03, 0.03, 0.88), Color("#c43a2a"), 18)
	st.set_border_width_all(2)
	st.content_margin_left = 14
	st.content_margin_right = 22
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	_hud.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_drum = Drum.new()
	_drum.custom_minimum_size = Vector2(96, 96)
	row.add_child(_drum)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_who = UI.title("", 24, Color.WHITE)
	_pct = UI.title("", 40, Color("#ff5a4a"))
	_timer = UI.label("", 18, Color(0.85, 0.85, 0.9))
	col.add_child(_who)
	col.add_child(_pct)
	col.add_child(_timer)
	row.add_child(col)
	_hud.add_child(row)
	_hud.position = Vector2(20, 84)
	_hud.custom_minimum_size = Vector2(380, 0)
	_hud.visible = false
	root().add_child(_hud)
	_beat = AudioStreamPlayer.new()
	_beat.stream = load("res://assets/ses/kalp.ogg")
	_beat.volume_db = 2.0
	add_child(_beat)


func _apply(d: Dictionary) -> void:
	if d.has("sira"):
		holder = int(d.sira)
	if d.has("asama"):
		stage = int(d.asama)
	elif d.has("yeni_sans"):
		stage = maxi(0, CHANCES.find(int(d.yeni_sans)))
	if d.has("hayatta"):
		alive = d.hayatta.map(func(x) -> int: return int(x))
	if d.has("olenler"):
		dead = d.olenler.map(func(x) -> int: return int(x))
	if d.has("sure") and int(d.sure) > 0:
		turn_left = float(d.sure)


func on_state(d: Dictionary, entered: bool) -> void:
	state = d
	_apply(d)
	if phase() in ["anons", "oyun"] and not is_instance_valid(_arena):
		_build_arena()
		_seat_me()
		w.voice.start()  # masadaki herkes birbirini duyar
	if entered and phase() == "anons":
		busy = false
		play("horoz", 2.0)
		flash("RUS RULETİ", "Son kalan kazanır!", Color("#ff4a3a"), 1.6)
		g.get_tree().create_timer(1.8).timeout.connect(show_card)
	_hud.visible = phase() in ["anons", "oyun"]
	_refresh()


func show_card() -> void:
	if not (phase() in ["anons", "oyun"]):
		return
	role_card("RUS RULETİ", Color("#ff5a4a"), "Silah kimdeyse karar onun: tetiği KENDİNE çek ya da birine doğrult.\nKendine sıkıp patlamazsa şans artar: %15 → %35 → %50 → %100. %100'de birini vurmak zorundasın.\nBaşkasına sıkıp patlamazsa silah ona AYNI şansla geçer.",
		"Vurursan +1 · ölürsen -1 · son kalan +3")


func on_event(d: Dictionary) -> void:
	match str(d.get("tur", "")):
		"sira":
			_apply(d)
			_refresh()
		"atis":
			_shot(d)


# Atış canlandırması (~2.6 sn, sunucu da bu kadar bekler).
func _shot(d: Dictionary) -> void:
	busy = true
	close_card()
	_refresh()
	var shooter := int(d.atan)
	var target := int(d.hedef)
	var fired := bool(d.patladi)
	var self_shot := shooter == target
	# yazı yok: kim kime doğrulttu masada zaten görünüyor
	var involved := target == me() or shooter == me()
	var sus := _suspense(involved)
	play("horoz", 0.0)
	if shooter == me() and is_instance_valid(_gun):
		_aim_gun(self_shot)
	elif shooter != me():
		_aim_remote(shooter, target)
	for gun in [_gun, _remote_gun]:
		if is_instance_valid(gun):
			var drum3d: Node3D = gun.find_child("tambur", true, false)
			if drum3d:
				drum3d.create_tween().tween_property(drum3d, "rotation:z", drum3d.rotation.z + TAU * 3.0 + randf() * TAU, 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var tw := create_tween()
	tw.tween_interval(0.35)
	tw.tween_callback(func() -> void: play("tambur", -2.0))
	tw.tween_method(func(x: float) -> void:
		_drum.spin = x
		_drum.queue_redraw(), 0.0, TAU * 2.0 + randf() * TAU, 1.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.25)
	tw.tween_callback(func() -> void:
		if is_instance_valid(sus):
			sus.queue_free()
		if fired:
			_bang(d)
		else:
			_click(d))
	tw.tween_interval(0.9)
	tw.tween_callback(func() -> void:
		_apply(d)
		busy = false
		_refresh())
	if involved:
		_beat.pitch_scale = 1.25
		_beat.play()


func _suspense(involved: bool) -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0.15, 0.0, 0.0, 0.45 if involved else 0.25)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var holder_ctl := Control.new()
	holder_ctl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder_ctl.add_child(dim)
	root().add_child(holder_ctl)
	root().move_child(holder_ctl, 0)
	dim.color.a = 0.0
	dim.create_tween().tween_property(dim, "color:a", 0.45 if involved else 0.22, 0.4)
	return holder_ctl


func _bang(d: Dictionary) -> void:
	var victim := int(d.olen)
	play("tabanca", 3.0)
	_drum.hot = 1.0
	create_tween().tween_property(_drum, "hot", 0.0, 0.6)
	_muzzle(int(d.atan))
	if victim == me():
		screen_flash(Color(1, 1, 1), 1.0, 0.03, 0.15)
		_die_local()
		w._shake(0.8, 0.12)
		flash("VURULDUN!", "Artık konuşamazsın, izleyicisin", RED, 2.0)
	else:
		screen_flash(Color(1, 0.9, 0.7), 0.7 if int(d.atan) == me() else 0.35, 0.03, 0.3)
		w._shake(0.4, 0.05 if int(d.atan) == me() else 0.025)
		_corpse(victim, int(d.atan))
	if int(d.atan) == me() and victim != me():
		play("odul", -6.0)


func _click(d: Dictionary) -> void:
	play("bos_tetik", 4.0)
	_refresh()

func _show_dead() -> void:
	if is_instance_valid(_dead_ov):
		return
	_dead_ov = Control.new()
	_dead_ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dead_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var red := ColorRect.new()
	red.color = Color(0.35, 0.0, 0.0, 0.0)
	red.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	red.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dead_ov.add_child(red)
	red.create_tween().tween_property(red, "color:a", 0.38, 0.8)
	var l := UI.title("İZLEYİCİSİN", 26, Color(1, 0.8, 0.8))
	l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	l.position = Vector2(-90, -160)
	_dead_ov.add_child(l)
	root().add_child(_dead_ov)
	root().move_child(_dead_ov, 0)


func _refresh() -> void:
	if not is_instance_valid(_hud):
		return
	var playing := phase() == "oyun"
	var i := clampi(stage, 0, 3)
	(_drum as Drum).loaded = LOADED[i]
	_drum.queue_redraw()
	_who.text = ("SİLAH SENDE!" if holder == me() else "Silah: %s" % pname(holder)) if holder else "Silah masada"
	_who.add_theme_color_override("font_color", Color("#ffcf8a") if holder == me() else Color.WHITE)
	_pct.text = "%%%d" % CHANCES[i]
	_timer.text = ("Hayatta: %d kişi" % alive.size()) if not playing else ("Karar: %d sn · hayatta %d" % [ceili(turn_left), alive.size()])
	var mine := playing and holder == me() and not busy and me() in alive
	_set_gun(holder == me() and me() in alive and phase() in ["anons", "oyun"])
	_set_remote_gun(holder if holder != me() and phase() in ["anons", "oyun"] else 0)
	for id in dead:
		if id != me() and not _corpses.has(id):
			_corpse(id)
	if mine and not is_instance_valid(_bar):
		_build_bar()
	elif not mine and is_instance_valid(_bar):
		_bar.queue_free()
		_bar = null
	if me() in dead:
		_show_dead()
	g._update_banner()


func _build_bar() -> void:
	_bar = PanelContainer.new()
	var st := UI.flat(Color(0.05, 0.02, 0.02, 0.9), Color("#ff5a4a"), 20)
	st.set_border_width_all(2)
	st.content_margin_left = 18
	st.content_margin_right = 18
	st.content_margin_top = 12
	st.content_margin_bottom = 12
	_bar.add_theme_stylebox_override("panel", st)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_bar.add_child(v)
	var i := clampi(stage, 0, 3)
	var selfb := UI.button("KENDİNE SIK  %%%d" % CHANCES[i], "red", 68, 26, "", 420)
	selfb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if CHANCES[i] >= 100:
		selfb.disabled = true
		UI.set_button_text(selfb, "%100: BİRİNİ SEÇ!")
	selfb.pressed.connect(func() -> void: _fire("kendi"))
	v.add_child(selfb)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for id in alive:
		if int(id) == me():
			continue
		var pid := int(id)
		var b := UI.button(up(dat(pname(pid))) + " SIK", "orange", 56, 20, "", 240)
		b.pressed.connect(func() -> void: _fire(pid))
		grid.add_child(b)
	v.add_child(grid)
	_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	root().add_child(_bar)
	await g.get_tree().process_frame
	if is_instance_valid(_bar):
		_bar.position = Vector2(-_bar.size.x / 2.0, -_bar.size.y - 26)
	play("horoz", -6.0)


func _fire(v) -> void:
	if busy:
		return
	busy = true  # sunucudan atış gelene kadar düğmeler kapalı
	g.decided.emit({"atis": v})
	if is_instance_valid(_bar):
		_bar.queue_free()
		_bar = null
	# sunucu reddederse (ör. süre) kilitli kalmasın
	g.get_tree().create_timer(4.0).timeout.connect(func() -> void:
		if busy:
			busy = false
			_refresh())


# Birinci şahıs altıpatar (silah sendeyken).
const HOLD_POS := Vector3(0.2, -0.27, -0.2)  # silahlı sağ kol: biraz kalkık
const HOLD_ROT := Vector3(0.06, 0.16, 0)


func _set_gun(on: bool) -> void:
	var arm: Node3D = w.player.arms[1]
	if on and not is_instance_valid(_gun):
		# kabza sağ avucun içinde, namlu ileri
		_gun = Node3D.new()
		arm.add_child(_gun)
		_gun.position = Vector3(0, 0.085, -0.255)
		Props.revolver(_gun)
		w.player.arms[0].visible = false
		arm.visible = true
		arm.position = HOLD_POS
		arm.rotation = HOLD_ROT
	elif not on and is_instance_valid(_gun):
		_gun.queue_free()
		_gun = null
		arm.position = w.player.ARM_BASE[1]
		arm.rotation = Vector3(0, 0.18, 0)
		arm.visible = false


# Kendi atışım: kol silahla birlikte şakağa gider (namlu başa döner) ya da hedefe uzanır; geri tepme.
func _aim_gun(at_self: bool) -> void:
	var arm: Node3D = w.player.arms[1]
	var tw := arm.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if at_self:
		tw.tween_property(arm, "position", Vector3(0.44, -0.04, -0.04), 0.5)
		tw.parallel().tween_property(arm, "rotation", Vector3(0.05, PI / 2 + 0.1, 0), 0.5)
	else:
		tw.tween_property(arm, "position", Vector3(0.12, -0.2, -0.3), 0.4)
		tw.parallel().tween_property(arm, "rotation", Vector3(0.02, 0.05, 0), 0.4)
	tw.tween_interval(1.25)
	tw.tween_property(arm, "rotation:x", arm.rotation.x + 0.25, 0.04)
	tw.tween_property(arm, "position", HOLD_POS, 0.45)
	tw.parallel().tween_property(arm, "rotation", HOLD_ROT, 0.45)


# Başkasının elindeki altıpatar (masadakiler görür).
func _set_remote_gun(id: int) -> void:
	if id == _remote_gun_id and is_instance_valid(_remote_gun):
		return
	if is_instance_valid(_remote_gun):
		_remote_gun.queue_free()
	_remote_gun = null
	_remote_gun_id = id
	_gun_aim_at = Vector3.ZERO
	if id == 0 or not w.remotes.has(id) or not (id in alive):
		return
	_remote_gun = Node3D.new()
	w.add_child(_remote_gun)
	var inner := Node3D.new()
	inner.position = Vector3(0, 0.0575, -0.0805)  # kabzanın ortası tam avuçta
	_remote_gun.add_child(inner)
	inner.scale = Vector3.ONE * 1.15
	Props.revolver(inner)
	_update_remote_gun()


# Uzaktaki oyuncunun iskeleti ve kol/gövde pozlayıcısı.
func _skel(id: int) -> Skeleton3D:
	if not w.remotes.has(id):
		return null
	var sks: Array = (w.remotes[id].body as Node).find_children("*", "Skeleton3D", true, false)
	return sks[0] if not sks.is_empty() else null


func _pose(id: int) -> Node:
	var sk := _skel(id)
	if not sk:
		return null
	for c in sk.get_children():
		if c is AimMod:
			return c
	var m: Node = AimMod.new()
	sk.add_child(m)
	return m


func _bone_world(id: int, bone: String) -> Vector3:
	var sk := _skel(id)
	if not sk:
		return Vector3.ZERO
	var b := sk.find_bone("mixamorig_" + bone)
	if b < 0:
		return sk.global_position
	return sk.global_transform * sk.get_bone_global_pose(b).origin


# Silah her karede sağ elin içinde: nişan alırken hedefe, boştayken öne-aşağı bakar.
func _update_remote_gun() -> void:
	if not is_instance_valid(_remote_gun) or not w.remotes.has(_remote_gun_id):
		return
	var pose := _pose(_remote_gun_id)
	var palm: Vector3 = pose.palm if pose and pose.palm != Vector3.ZERO else _bone_world(_remote_gun_id, "RightHand")
	var r: Node3D = w.remotes[_remote_gun_id].root
	var look: Vector3
	if _gun_aim_at != Vector3.ZERO:
		look = _gun_aim_at
	elif pose and pose.fingers != Vector3.ZERO:
		look = palm + pose.fingers  # namlu parmaklarla aynı yöne
	else:
		look = palm - r.global_transform.basis.z
	_remote_gun.global_position = palm
	if palm.distance_to(look) > 0.01:
		_remote_gun.look_at(look, Vector3.UP)


# Uzaktaki atıcı: sağ kolunu kaldırır; kendine sıkıyorsa namluyu şakağına dayar, değilse hedefe uzatır.
func _aim_remote(shooter: int, target: int) -> void:
	if not w.remotes.has(shooter):
		return
	var pose := _pose(shooter)
	if not pose:
		return
	var head := _bone_world(shooter, "Head") + Vector3(0, 0.07, 0)
	var shoulder := _bone_world(shooter, "RightArm")
	var left := _bone_world(shooter, "LeftArm")
	var right := (shoulder - left).normalized()
	if target == shooter:
		pose.hand_target = head + right * 0.16 + Vector3(0, -0.02, 0)
		_gun_aim_at = head - right * 0.3
	else:
		var tp: Vector3
		if target == me():
			tp = w.player.camera.global_position
		elif w.remotes.has(target):
			tp = _bone_world(target, "Head")
		else:
			tp = shoulder - w.remotes[shooter].root.global_transform.basis.z
		pose.hand_target = shoulder + (tp - shoulder).normalized() * 0.62
		_gun_aim_at = tp
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(pose, "aim", 1.0, 0.45)
	tw.tween_interval(1.55)
	tw.tween_callback(func() -> void: _gun_aim_at = Vector3.ZERO)
	tw.tween_property(pose, "aim", 0.0, 0.45)


# Namlu alevi: atışta silahın ucunda kısa bir parlama.
func _muzzle(shooter: int) -> void:
	var gun: Node3D = null
	if shooter == me():
		gun = _gun
	elif _remote_gun_id == shooter:
		gun = _remote_gun
	if not is_instance_valid(gun):
		return
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.7, 0.35)
	l.light_energy = 8.0
	l.omni_range = 4.0
	l.position = Vector3(0, 0.03, -0.22)
	gun.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.18)
	tw.tween_callback(l.queue_free)


# ---------- koridordaki masa ----------

func _build_arena() -> void:
	_arena = Node3D.new()
	w.add_child(_arena)
	_arena.global_position = CENTER
	var table: Node3D = w.model("round_wooden_table_01", Vector3.ZERO, 0.0, 1.0, NAN, _arena)
	var tb: AABB = w._bounds(table, _arena)
	if tb.size.x > 0.1:
		table.scale = Vector3.ONE * (1.2 / maxf(tb.size.x, tb.size.z))  # 1.2 m çaplı masa
	# koridorda yürüyen mahkum masanın içinden geçmesin
	w.walker.visible = false
	w.walker.global_position = Vector3(3.9, -20, 0)
	# her oyuncuya bir metal tabure
	for id in state.get("players", []):
		var cp := _seat_of(int(id))
		w.model("metal_stool_01", cp - CENTER, _chair_yaw(cp), 1.0, NAN, _arena)
	# masanın üstünde tek sarkık lamba: dramatik koni ışık
	w.model("hanging_industrial_lamp", Vector3(0, 2.25, 0), 0.0, 1.0, NAN, _arena)
	var cord := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.006
	cm.bottom_radius = 0.006
	cm.height = 0.6
	cord.mesh = cm
	cord.position = Vector3(0, 2.95, 0)
	_arena.add_child(cord)
	var spot := SpotLight3D.new()
	spot.position = Vector3(0, 2.3, 0)
	spot.rotation.x = -PI / 2
	spot.light_color = Color(1.0, 0.82, 0.55)
	spot.light_energy = 6.0
	spot.spot_range = 5.0
	spot.spot_angle = 52.0
	spot.shadow_enabled = true
	_arena.add_child(spot)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 1.6, 0)
	fill.light_color = Color(1.0, 0.7, 0.45)
	fill.light_energy = 0.6
	fill.omni_range = 3.2
	_arena.add_child(fill)
	# masada boş kovanlar
	var top := 0.75
	var aabb: AABB = w._bounds(table, _arena)
	_seat_bots()
	_labels(0.0022)
	if aabb.size.y > 0.1:
		top = aabb.end.y
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color("#c9a24a")
	brass.metallic = 1.0
	brass.roughness = 0.3
	for i in 5:
		var b := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.0045
		bm.bottom_radius = 0.0045
		bm.height = 0.03
		b.mesh = bm
		b.material_override = brass
		var a := randf() * TAU
		var rr := randf_range(0.05, 0.3)
		b.position = Vector3(cos(a) * rr, top + 0.005, sin(a) * rr)
		b.rotation = Vector3(PI / 2, randf() * TAU, 0)
		_arena.add_child(b)


# Masadaki yer: oyuncu sırasına göre çember üstünde bir sandalye (masaya dönük).
func _seat_of(id: int) -> Vector3:
	var ids: Array = state.get("players", [])
	var i := maxi(0, ids.find(id))
	var a := TAU * i / maxf(1.0, ids.size()) + 0.35
	return CENTER + Vector3(cos(a), 0, sin(a)) * RADIUS


# Sandalyenin yönü: önü masaya bakar (oturan da masaya bakar).
func _chair_yaw(pos: Vector3) -> float:
	var to := CENTER - pos
	return atan2(to.x, to.z)


func _seat_me() -> void:
	var p: CharacterBody3D = w.player
	var pos := _seat_of(me())
	p.seated = false
	p.velocity = Vector3.ZERO
	p.global_position = pos + (CENTER - pos).normalized() * 0.4
	p.set_physics_process(false)  # yerinden kalkamaz, sadece etrafa bakar
	p.sit(pos, PI + _chair_yaw(pos))
	play("isinlan", -6.0)


# Masada isimler küçük yazılsın (yakından dev görünüyordu).
func _labels(px: float) -> void:
	for id in w.remotes:
		(w.remotes[id].label as Label3D).pixel_size = px


# Botların bilgisayarı yok: gövdelerini masadaki sandalyelerine bu istemci oturtur.
func _seat_bots() -> void:
	for id in state.get("players", []):
		var pid := int(id)
		if pid == me() or not w.remotes.has(pid) or not w.is_bot(pid):
			continue
		var pos := _seat_of(pid)
		var r: Dictionary = w.remotes[pid]
		r.target = pos
		r.root.position = pos
		r.yaw = PI + _chair_yaw(pos)
		r.root.rotation.y = r.yaw
		r.seated = true


# ---------- ölüm ----------

func _die_local() -> void:
	if _i_died:
		return
	_i_died = true
	w.voice.muted = true
	_set_gun(false)
	var p: CharacterBody3D = w.player
	for a in p.arms:
		a.visible = false
	var tw := p.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# oturduğu yerde yığılır: baş yana ve öne düşer (yere düşmez)
	tw.tween_property(p.head, "position:y", p.head.position.y - 0.32, 0.45)
	tw.parallel().tween_property(p.head, "rotation:z", 0.75, 0.45)
	tw.parallel().tween_property(p.head, "rotation:x", deg_to_rad(-55), 0.45)
	tw.tween_callback(func() -> void: _show_dead())
	tw.tween_interval(2.6)
	# izleyici: masanın üstünden bakar
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(p.head, "position:y", 2.5, 1.2)
	tw.parallel().tween_property(p.head, "rotation:z", 0.0, 1.2)
	tw.parallel().tween_property(p.head, "rotation:x", deg_to_rad(-40), 1.2)


# Uzaktaki ölü: sandalyeden kalkmaz; vurulduğu yöne doğru oturduğu yerde yığılır (baş düşer, kollar sarkar),
# animasyonu durur, taburenin dibinde kan göleti büyür.
func _corpse(id: int, shooter := 0) -> void:
	if _corpses.has(id) or not w.remotes.has(id):
		return
	var r: Dictionary = w.remotes[id]
	var body: Node3D = r.body
	r.label.visible = false
	var root_node: Node3D = r.root
	# vuruş yönü (ölünün kendi yönlerine göre): kendine sıktıysa sağ şakaktan sola, değilse atıcıdan uzağa
	var dir_local := Vector3(-1.0, 0, 0.25)
	if shooter != 0 and shooter != id:
		var from: Vector3 = w.player.global_position if shooter == me() else (w.remotes[shooter].root.global_position if w.remotes.has(shooter) else root_node.global_position)
		var push := (root_node.global_position - from)
		push.y = 0
		var loc := root_node.global_transform.basis.inverse() * push.normalized()
		dir_local = Vector3(loc.x, 0, loc.z)
	var pose := _pose(id)
	# animasyon o anki oturuş pozunda donar
	body.set_process(false)
	var ap := body.find_children("*", "AnimationPlayer", true, false)
	if not ap.is_empty():
		(ap[0] as AnimationPlayer).pause()
	if pose:
		pose.aim = 0.0
		pose.slump_dir = root_node.global_transform.basis * dir_local
		var tw := create_tween().set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_property(pose, "slump", 1.0, 0.45)
	# baş tarafına doğru taburenin dibinde kan
	var dec := Decal.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	gr.colors = PackedColorArray([Color(0.32, 0.0, 0.0, 0.95), Color(0.25, 0.0, 0.0, 0.85), Color(0.2, 0, 0, 0)])
	gt.gradient = gr
	dec.texture_albedo = gt
	dec.size = Vector3(0.1, 0.6, 0.1)
	w.add_child(dec)
	var lean := root_node.global_transform.basis * dir_local
	dec.global_position = root_node.global_position + lean.normalized() * 0.35
	dec.create_tween().tween_property(dec, "size", Vector3(0.9, 0.6, 0.9), 7.0).set_ease(Tween.EASE_OUT)
	play("carpma", -10.0)
	_corpses[id] = dec


func _revive_all() -> void:
	for id in _corpses:
		var dec: Node3D = _corpses[id]
		if is_instance_valid(dec):
			dec.queue_free()
		if not w.remotes.has(id):
			continue
		var r: Dictionary = w.remotes[id]
		var pose := _pose(id)
		if pose:
			pose.slump = 0.0
			pose.aim = 0.0
		r.body.set_process(true)
		r.label.visible = true
		r.seated = false
		var ap: Array = r.body.find_children("*", "AnimationPlayer", true, false)
		if not ap.is_empty():
			(ap[0] as AnimationPlayer).play()
	_corpses.clear()


func locks_seat() -> bool:
	return phase() in ["anons", "oyun", "sonuc"]


func process(delta: float) -> void:
	_update_remote_gun()
	if phase() == "oyun" and not busy and turn_left > 0.0:
		var before := ceili(turn_left)
		turn_left = maxf(0.0, turn_left - delta)
		if ceili(turn_left) != before:
			_timer.text = "Karar: %d sn · hayatta %d" % [ceili(turn_left), alive.size()]
			if holder == me() and turn_left <= 5.0 and turn_left > 0.0:
				play("tik", -4.0)


func banner() -> Array:
	var pn: String = {"anons": "SİLAH DOLDURULUYOR", "oyun": "SIRA: " + (("SENDE" if holder == me() else up(pname(holder))))}.get(phase(), "")
	var info := "Hayatta: %d · şans %%%d" % [alive.size(), CHANCES[clampi(stage, 0, 3)]]
	if me() in dead:
		info = "Vuruldun · izliyorsun · " + info
	elif holder == me() and phase() == "oyun":
		info = "Kararını ver! " + info
	return ["RUS RULETİ  ·  " + pn, info]


func help_rows() -> Array:
	return [
		["lock", "Silah kimdeyse o karar verir: kendine sık ya da birine doğrult."],
		["crown", "Kendine sıkıp patlamazsa şans artar: %15, %35, %50, %100. %100'de birini vurursun."],
		["deal", "Başkasına sıkıp patlamazsa silah ona aynı şansla geçer."],
		["trophy", "Vuran +1, ölen -1, son kalan +3. 15 saniyede karar vermezsen tetik kendine çekilir!"],
	]


func on_result(d: Dictionary) -> void:
	_set_gun(false)
	_hud.visible = false
	var rows := []
	var win := int(d.get("kazanan", 0))
	if win:
		rows.append(UI.title("SON KALAN: %s" % ("SEN" if win == me() else str(d.get("kazanan_ad", "?"))), 36, GREEN, true))
	else:
		var names := []
		for id in d.get("hayatta", []):
			names.append(pname(int(id)))
		rows.append(UI.label("Süre bitti. Hayatta kalanlar: " + ", ".join(names), 22, Color.WHITE, true))
	result_modal("RUS RULETİ", rows, d)


func cleanup() -> void:
	_set_gun(false)
	_set_remote_gun(0)
	_revive_all()
	if is_instance_valid(_arena):
		_arena.queue_free()
	if w and w.walker:
		w.walker.visible = true
		w.walker.position = Vector3(4.4, 0, -16.0)
		w.place_bots()
		_labels(0.004)
	if w and w.player:
		var p: CharacterBody3D = w.player
		p.seated = false
		p.busy = false
		p.col.disabled = false
		p.head.position.y = p.EYE_STAND
		p.head.rotation = Vector3.ZERO
		p.global_position = w.cells[w.my_cell].spawn_world()
		p.rotation.y = 0.0
		p.set_physics_process(true)
		w.voice.muted = false
		if w.phone_state == 0:
			w.voice.stop()
	for n in [_hud, _bar, _dead_ov]:
		if is_instance_valid(n):
			n.queue_free()
	if w and w.player:
		w.player.arms[0].visible = true
		w.player.arms[1].visible = true
	close_panel()
	close_card()
