# RUS RULETİ: herkes koridordaki yuvarlak masanın etrafına ışınlanır, tek lamba altında oynanır.
# Silah kimdeyse elinde altıpatar durur. Sıra sendeyken yazılı düğme yok: ekranı kaydırıp masada kime
# bakarsan silah ona doğrulur (başının çevresinde ince kırmızı halka), sağ alttaki tetiğe basınca ona
# sıkarsın; şakak düğmesi namluyu kendi şakağına çevirir. Her atışta herkes aynı gerilimi yaşar: horoz
# sesi, tambur döner, kalp atar... BAM ya da TIK (uzaktakilerin atışı 3B konumlu, izleyiciler de duyar).
# Ölen yere düşer, cesedi orada kalır, konuşamaz (sesi kimseye gitmez), izleyici olur.
extends "res://scripts/modlar/mod_ui.gd"

const Props := preload("res://scripts/modlar/props.gd")
const AimMod := preload("res://scripts/modlar/aim_mod.gd")
const CENTER := Vector3(3.9, 0.0, 0.0)  # koridorun ortası (iki hücre kapısının arası)
const RADIUS := 1.0  # sandalyelerin masaya uzaklığı
const SEAT_TOP := 0.44  # tabure oturağının yerden yüksekliği (oturma pozunda kalça eklemi ~0,49 m)
const TABLE_TOP := 0.76  # masa üstünün yerden yüksekliği

const AIM_CONE := 0.26  # bakış bu açıdan (rad, ~15°) yakınsa o kişi hedef olur
const AIM_KEEP := 0.36  # kilitli hedef biraz daha geniş açıda tutulur (titreşmesin)
const AIM_HOLD := 0.2  # yeni hedef bu kadar sn bakışta kalınca kilitlenir (kazara geçişe karşı)
const AIM_LOSE := 0.25  # kimseye bakmıyorsan hedef bu kadar sn sonra bırakılır
const CHANCES := [15, 35, 50, 100]
const LOADED := [1, 2, 3, 6]  # altı yuvadan kaçı dolu (≈ şans)

var holder := 0
var stage := 0
var alive: Array = []
var dead: Array = []
var turn_left := 0.0
var busy := false  # atış canlandırması sürüyor
var _istek := 0  # yanıt bekleyen atış isteğinin numarası (sunucu yanıt vermezse kilit açılır; atış gelince 0)
var _istek_sayac := 0  # her istek yeni numara alır (eski zamanlayıcı yeni isteği açmasın)
var _hud: Control
var _drum: Control
var _who: Label
var _pct: Label
var _timer: Label
var _bar: Control  # silah sendeyken: nişangah, tetik ve şakak düğmeleri
var _aim_ov: AimOverlay
var _trig: Button  # tetik (sağ alt, yazısız)
var _temple: Button  # namluyu şakağa çevir (yazısız)
var _aim_id := 0  # silahın kilitlendiği oyuncu (0: kimse)
var _aim_cand := 0  # bakışın şu an gösterdiği aday
var _aim_cand_t := 0.0  # aday ne kadar süredir aynı (kazara geçişe karşı)
var _self_mode := false  # namlu şakakta
var _auto_n := 0  # otomatik test: kaçıncı sıra
static var _ipucu_goruldu := false  # kaydırma ipucu uygulama açıkken bir kez
var _gun: Node3D
var _dead_ov: Control
var _beat: AudioStreamPlayer
var _arena: Node3D  # masa, lamba
var _remote_gun: Node3D  # başkasının elindeki altıpatar
var _remote_gun_id := 0
var _remote_mode := "silah"  # uzaktaki silahlının pozu: silah (boşta), sakak, hedef
var _remote_target := 0
var _remote_w := 0.0  # uzaktaki elin poza geçiş ağırlığı
var _fp_aim_target := 0
var _sus: Control  # atış gerilimi karartması
var _corpses := {}  # ölen id -> kan izi
var _i_died := false


# Tambur göstergesi: dolu yuvalar pirinç fişek; dışındaki halka karar süresi (son 5 sn kırmızı, nabız gibi atar).
class Drum extends Control:
	var loaded := 1
	var spin := 0.0
	var hot := 0.0  # atış parlaması
	var left := 0.0  # karar süresi (0: halka gizli)
	var total := 15.0

	func _process(_delta: float) -> void:
		if hot > 0.0 or (left > 0.0 and left <= 5.0):
			queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var R := minf(size.x, size.y) * 0.5
		var r := R * 0.8
		# süre halkası
		draw_arc(c, R - 4.0, 0, TAU, 64, Color(1, 1, 1, 0.1), 6.0, true)
		if left > 0.0:
			var k := clampf(left / maxf(total, 0.1), 0.0, 1.0)
			var urgent := left <= 5.0
			var col := Color("#e0322a") if urgent else Color("#ffb020")
			if urgent:
				col.a = 0.65 + 0.35 * sin(Time.get_ticks_msec() / 90.0)
			draw_arc(c, R - 4.0, -PI / 2, -PI / 2 + TAU * k, 64, col, 6.0, true)
		# metal tambur
		draw_circle(c, r, Color("#24272c"))
		draw_circle(c + Vector2(-r * 0.12, -r * 0.14), r * 0.8, Color("#33373e"))
		draw_arc(c, r, 0, TAU, 48, Color("#9aa1aa"), 3.0, true)
		draw_arc(c, r * 0.93, 0, TAU, 48, Color("#111316"), 2.0, true)
		for i in 6:
			var a := spin + i * TAU / 6.0 - PI / 2
			var p := c + Vector2(cos(a), sin(a)) * r * 0.58
			draw_circle(p, r * 0.25, Color("#0a0b0d"))
			if i < loaded:
				draw_circle(p, r * 0.2, Color("#c9962e"))
				draw_circle(p + Vector2(-r * 0.05, -r * 0.05), r * 0.1, Color("#f2cf6e"))
				draw_circle(p, r * 0.06, Color("#7a4e14"))
			draw_arc(p, r * 0.25, 0, TAU, 20, Color("#5a5f68"), 2.0, true)
		draw_circle(c, r * 0.13, Color("#7b818a"))
		if hot > 0.0:
			draw_circle(c, R * 1.05, Color(1.0, 0.55, 0.2, hot * 0.5))


# Silah sendeyken: ortada küçük nişangah (hedefe kilitlenince kırmızı); doğrultulan kişinin başının
# çevresinde ince kırmızı halka (yavaşça döner, kilitlenince bir an büyüyüp oturur). Yazı yok.
class AimOverlay extends Control:
	var ring_pos := Vector2.ZERO
	var ring_r := 40.0
	var ring_a := 0.0  # halkanın görünürlüğü 0-1
	var pop := 0.0  # kilitlenme anında 1, hızla söner
	var locked := false
	var self_mode := false

	func _process(delta: float) -> void:
		pop = maxf(0.0, pop - delta * 4.0)
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		if not self_mode:
			var col := Color(1.0, 0.3, 0.24, 0.95) if locked else Color(1, 1, 1, 0.8)
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				draw_line(c + d * 7.0, c + d * 17.0, Color(0, 0, 0, 0.45), 4.5, true)
				draw_line(c + d * 7.0, c + d * 17.0, col, 2.0, true)
			draw_circle(c, 2.5, col)
		if ring_a > 0.01:
			var t := Time.get_ticks_msec() / 1000.0
			var r := ring_r * (1.0 + 0.35 * pop + 0.03 * sin(t * 5.0))
			var rc := Color(1.0, 0.16, 0.12, 0.9 * ring_a)
			draw_arc(ring_pos, r, 0, TAU, 72, Color(0, 0, 0, 0.35 * ring_a), 5.0, true)
			draw_arc(ring_pos, r, 0, TAU, 72, rc, 2.0, true)
			for i in 4:
				var a := t * 0.8 + i * PI / 2.0
				var d := Vector2(cos(a), sin(a))
				draw_line(ring_pos + d * (r - 7.0), ring_pos + d * (r + 9.0), rc, 3.0, true)


# Yazısız düğme ikonları (elle çizilir): "tetik" yandan altıpatar, "sakak" baş profili ve şakağa dayalı namlu.
class GunIcon extends Control:
	var kind := "tetik"
	var col := Color("#fff4e2")
	var cut := Color("#7a1410")  # tamburdaki oluklar (disk rengi)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	# birim karede (0-1) yandan altıpatar, namlu sağa
	func _revolver() -> void:
		draw_colored_polygon(PackedVector2Array([Vector2(0.45, 0.3), Vector2(0.92, 0.3), Vector2(0.92, 0.4), Vector2(0.45, 0.4)]), col)
		draw_colored_polygon(PackedVector2Array([Vector2(0.86, 0.25), Vector2(0.9, 0.25), Vector2(0.9, 0.3), Vector2(0.86, 0.3)]), col)
		draw_colored_polygon(PackedVector2Array([Vector2(0.3, 0.26), Vector2(0.58, 0.26), Vector2(0.6, 0.5), Vector2(0.3, 0.5)]), col)
		draw_colored_polygon(PackedVector2Array([Vector2(0.3, 0.27), Vector2(0.21, 0.17), Vector2(0.26, 0.15), Vector2(0.35, 0.26)]), col)
		draw_colored_polygon(PackedVector2Array([Vector2(0.3, 0.48), Vector2(0.45, 0.48), Vector2(0.38, 0.86), Vector2(0.3, 0.89), Vector2(0.18, 0.85), Vector2(0.22, 0.62)]), col)
		draw_arc(Vector2(0.48, 0.52), 0.085, 0.0, PI, 16, col, 0.035, true)
		draw_line(Vector2(0.47, 0.49), Vector2(0.445, 0.585), col, 0.035, true)
		for y in [0.335, 0.425]:
			draw_line(Vector2(0.36, y), Vector2(0.54, y), cut, 0.022, true)

	func _draw() -> void:
		var k := minf(size.x, size.y)
		var o := (size - Vector2(k, k)) / 2.0
		if kind == "tetik":
			draw_set_transform(o + Vector2(-0.05, -0.02) * k, 0.0, Vector2(k, k))
			_revolver()
		else:
			# baş (yan profil) ve omuz; sağdan namlusu şakağa dayalı küçük altıpatar
			draw_set_transform(o, 0.0, Vector2(k, k))
			draw_circle(Vector2(0.34, 0.4), 0.19, col)
			draw_colored_polygon(PackedVector2Array([Vector2(0.26, 0.54), Vector2(0.42, 0.54), Vector2(0.5, 0.7), Vector2(0.6, 0.9), Vector2(0.06, 0.9), Vector2(0.16, 0.7)]), col)
			draw_set_transform(o + Vector2(1.04, 0.17) * k, 0.0, Vector2(-k * 0.56, k * 0.56))
			_revolver()
		draw_set_transform_matrix(Transform2D.IDENTITY)


func _ready() -> void:
	_hud = PanelContainer.new()
	var st := UI.flat(Color(0.03, 0.035, 0.035, 0.86), Color(UI.KIRMIZI, 0.9), UI.R_BUYUK)
	st.set_border_width_all(0)
	st.border_width_left = 5
	st.shadow_size = 10
	st.shadow_color = Color(0, 0, 0, 0.45)
	st.content_margin_left = UI.B_S
	st.content_margin_right = UI.B_L
	st.content_margin_top = UI.B_XS
	st.content_margin_bottom = UI.B_XS
	_hud.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UI.B_M)
	_drum = Drum.new()
	_drum.custom_minimum_size = Vector2(112, 112)
	row.add_child(_drum)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -4)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_who = UI.title("", 22, UI.METIN)
	col.add_child(_who)
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", UI.B_M)
	_pct = UI.title("", 52, Color("#ff5a4a"))
	r2.add_child(_pct)
	# hayatta kalan sayısı: ikon + sayı
	var alive_chip := HBoxContainer.new()
	alive_chip.add_theme_constant_override("separation", 4)
	alive_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	alive_chip.add_child(UI.icon("arkadas", 34))
	_timer = UI.title("", UI.FS_ORTA, UI.METIN_SOLUK)
	alive_chip.add_child(_timer)
	r2.add_child(alive_chip)
	col.add_child(r2)
	row.add_child(col)
	_hud.add_child(row)
	_hud.position = Vector2(20 + maxf(UI.guvenli_pay().x, 20.0), 82)  # kenardan güvenli alan payı kadar içeride
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
	role_card("RUS RULETİ", UI.KIRMIZI, "Kendine sık ya da birine doğrult. Son kalan kazanır!")


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
	_istek = 0  # yanıt geldi: önceki isteğin kilit açma zamanlayıcısı canlandırmayı bölmesin
	close_card()
	_refresh()
	var shooter := int(d.atan)
	var target := int(d.hedef)
	var fired := bool(d.patladi)
	var self_shot := shooter == target
	# yazı yok: kim kime doğrulttu masada zaten görünüyor
	var involved := target == me() or shooter == me()
	if is_instance_valid(_sus):
		_sus.queue_free()
	_sus = _suspense(involved)
	_gun_sfx("horoz", shooter, 0.0)
	if shooter == me() and is_instance_valid(_gun):
		_aim_gun(self_shot, target, fired)
	elif shooter != me():
		_aim_remote(shooter, target)
	for gun in [_gun, _remote_gun, _sakak_gun]:
		if is_instance_valid(gun):
			var drum3d: Node3D = gun.find_child("tambur", true, false)
			if drum3d:
				drum3d.create_tween().tween_property(drum3d, "rotation:z", drum3d.rotation.z + TAU * 3.0 + randf() * TAU, 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# geri çağrılar bu düğümün yöntemleri: yakalanan düğüm serbest kalınca "Lambda capture ... was freed" olmaz
	var tw := create_tween()
	tw.tween_interval(0.35)
	tw.tween_callback(_gun_sfx.bind("tambur", shooter, -2.0))
	tw.tween_method(_spin_drum, 0.0, TAU * 2.0 + randf() * TAU, 1.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.25)
	tw.tween_callback(_shot_fire.bind(d))
	tw.tween_interval(0.9)
	tw.tween_callback(_shot_end.bind(d))
	if involved:
		_beat.pitch_scale = 1.25
		_beat.play()


func _spin_drum(x: float) -> void:
	if is_instance_valid(_drum):
		_drum.spin = x
		_drum.queue_redraw()


func _shot_fire(d: Dictionary) -> void:
	if is_instance_valid(_sus):
		_sus.queue_free()
	_sus = null
	if bool(d.patladi):
		_bang(d)
	else:
		_click(d)


func _shot_end(d: Dictionary) -> void:
	_apply(d)
	busy = false
	_refresh()


# Kenarlardan kararan kırmızı vinyet (kalp atışıyla nabız gibi daralır); ortası, yani masa, görünür kalır.
func _vignette(col: Color, strength: float, pulse: bool) -> ColorRect:
	var v := ColorRect.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.2, 0.0, 0.0, 1.0);
uniform float k = 0.0;
uniform float pulse = 0.0;
void fragment() {
	vec2 q = (UV - 0.5) * vec2(1.25, 1.0);
	float d = length(q);
	float beat = pulse * (0.5 + 0.5 * sin(TIME * 7.5));
	float a = smoothstep(0.28 - 0.06 * beat, 0.78, d);
	COLOR = vec4(tint.rgb, clamp(a * k + 0.12 * k, 0.0, 1.0));
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tint", col)
	mat.set_shader_parameter("pulse", 1.0 if pulse else 0.0)
	mat.set_shader_parameter("k", 0.0)
	v.material = mat
	v.create_tween().tween_method(func(x: float) -> void: mat.set_shader_parameter("k", x), 0.0, strength, 0.4)
	return v


func _suspense(involved: bool) -> Control:
	var holder_ctl := Control.new()
	holder_ctl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder_ctl.add_child(_vignette(Color(0.22, 0.0, 0.0), 0.95 if involved else 0.6, involved))
	root().add_child(holder_ctl)
	root().move_child(holder_ctl, 0)
	return holder_ctl


func _bang(d: Dictionary) -> void:
	var victim := int(d.olen)
	_gun_sfx("tabanca", int(d.atan), 1.0)
	_drum.hot = 1.0
	create_tween().tween_property(_drum, "hot", 0.0, 0.6)
	_muzzle(int(d.atan))
	if victim == me():
		screen_flash(Color(1, 1, 1), 1.0, 0.03, 0.15)
		_die_local()
		w._shake(0.8, 0.12)
		flash("VURULDUN!", "Artık izleyicisin", UI.KIRMIZI, 2.0)
	else:
		screen_flash(Color(1, 0.9, 0.7), 0.7 if int(d.atan) == me() else 0.35, 0.03, 0.3)
		w._shake(0.4, 0.05 if int(d.atan) == me() else 0.025)
		_corpse(victim, int(d.atan))
	if int(d.atan) == me() and victim != me():
		play("odul", -6.0)


func _click(d: Dictionary) -> void:
	_gun_sfx("bos_tetik", int(d.atan), 4.0)
	_refresh()


# Silah sesleri: kendi atışın kulağının dibinde (konumsuz); başkasınınki silahın olduğu yerden 3B çalar:
# yakında patlama baskın, uzaklaştıkça (izleyici yukarıdan, ya da başka yerde olan) boğuk ve yankılı
# uzak kayıt öne çıkar. Ölüler (izleyiciler) de duyar: sesli sohbet susturulsa da efektler çalar.
func _gun_sfx(ad: String, shooter: int, db := 0.0) -> void:
	if shooter == me() and not (me() in dead):
		play(ad, db)
		return
	var pos := _gun_pos(shooter)
	if pos == Vector3.INF or not is_instance_valid(w):
		play(ad, db - 3.0)
		return
	_sfx3d(ad, pos, db + 4.0, 2.2, 6.0)
	if ad == "tabanca":
		_sfx3d("tabanca_uzak", pos, db - 8.0, 14.0, 0.0)


func _sfx3d(ad: String, pos: Vector3, db: float, unit: float, max_db: float) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = load("res://assets/ses/%s.ogg" % ad)
	p.volume_db = db
	p.unit_size = unit
	p.max_db = max_db
	p.max_distance = 60.0
	p.bus = &"Efekt"
	w.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


# Atıcının silahının dünyadaki yeri (yoksa elinin, o da yoksa oturduğu yerin göğüs hizası).
func _gun_pos(shooter: int) -> Vector3:
	if shooter == _remote_gun_id and is_instance_valid(_remote_gun) and _remote_gun.is_inside_tree():
		return _remote_gun.global_position
	if shooter == me() and is_instance_valid(w.player):
		return w.player.camera.global_position
	if w.remotes.has(shooter):
		var hand := _bone_world(shooter, "RightHand")
		return hand if hand != Vector3.ZERO else (w.remotes[shooter].root as Node3D).global_position + Vector3(0, 1.0, 0)
	if (state.get("players", []) as Array).has(shooter):
		return _seat_of(shooter) + Vector3(0, 1.0, 0)
	return Vector3.INF

func _show_dead() -> void:
	if is_instance_valid(_dead_ov):
		return
	_dead_ov = Control.new()
	_dead_ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dead_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dead_ov.add_child(_vignette(Color(0.28, 0.0, 0.0), 0.85, false))
	# altta küçük hap: izleyicisin (sesin kimseye gitmez)
	var chip := PanelContainer.new()
	var st := UI.flat(Color(0.05, 0.02, 0.02, 0.85), Color(UI.KIRMIZI, 0.8), UI.R_BUYUK)
	st.set_border_width_all(2)
	st.shadow_size = 0
	st.content_margin_left = UI.B_M
	st.content_margin_right = UI.B_L
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", st)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UI.B_S)
	row.add_child(UI.icon("engelle", 36))
	var l := UI.title("İZLEYİCİSİN", UI.FS_ORTA, Color(1, 0.82, 0.8))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	chip.add_child(row)
	chip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	chip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	chip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	chip.offset_left = 0
	chip.offset_right = 0
	chip.offset_top = -40
	chip.offset_bottom = -40
	_dead_ov.add_child(chip)
	root().add_child(_dead_ov)
	root().move_child(_dead_ov, 0)


func _refresh() -> void:
	if not is_instance_valid(_hud):
		return
	var playing := phase() == "oyun"
	var i := clampi(stage, 0, 3)
	(_drum as Drum).loaded = LOADED[i]
	_drum.queue_redraw()
	_who.text = ("SİLAH SENDE" if holder == me() else up(pname(holder))) if holder else "SİLAH MASADA"
	_who.add_theme_color_override("font_color", UI.AMBER if holder == me() else UI.METIN)
	_pct.text = tr("%%%d") % CHANCES[i]
	_timer.text = str(alive.size())
	(_drum as Drum).left = turn_left if playing and not busy else 0.0
	var mine := playing and holder == me() and not busy and me() in alive and alive.size() > 1  # tek kalan: sonuç gelir, düğme çıkmasın
	_set_gun(holder == me() and me() in alive and phase() in ["anons", "oyun"])
	_set_remote_gun(holder if holder != me() and phase() in ["anons", "oyun"] else 0)
	for id in dead:
		if id != me() and not _corpses.has(id):
			_corpse(id)
	if mine and not is_instance_valid(_bar):
		_build_bar()
	elif not mine and is_instance_valid(_bar):
		_free_bar()
	if me() in dead:
		_show_dead()
	g._update_banner()


func _build_bar() -> void:
	# Yazı yok: ortada nişangah, sağ altta büyük tetik, onun sol üstünde şakak düğmesi. Kime bakarsan silah
	# ona doğrulur (process -> _update_aim); hedef yokken tetik pasif.
	_bar = Control.new()
	_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim_id = 0
	_aim_cand = 0
	_aim_cand_t = 0.0
	_self_mode = false
	_aim_ov = AimOverlay.new()
	_aim_ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_aim_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_aim_ov)
	var hud: Node = w.hud
	# tetik: eylem düğmesinin yeri (sağ alt), kırmızı disk, altıpatar ikonu. Basınca (bırakınca değil) sıkar:
	# parmak basılıyken kayarsa hedef değişmesin
	_trig = hud._yuvarlak(146, "", "", Color("#c42a20"))
	_trig.set_meta("sessiz", true)
	var ic := GunIcon.new()
	ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = 38
	ic.offset_top = 38
	ic.offset_right = -38
	ic.offset_bottom = -38
	_trig.add_child(ic)
	_trig.button_down.connect(_tetik)
	_bar.add_child(_trig)
	hud._place_kenar(_trig, Control.PRESET_BOTTOM_RIGHT, Vector2(-200, -214), Vector2(146, 146))
	# şakak: namluyu kendine çevirir / geri alır (%100'de kendine sıkılamaz: gizli)
	_temple = hud._yuvarlak(96, "", "")
	var ti := GunIcon.new()
	ti.kind = "sakak"
	ti.cut = Color(0.1, 0.1, 0.1)
	ti.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ti.offset_left = 22
	ti.offset_top = 20
	ti.offset_right = -22
	ti.offset_bottom = -24
	_temple.add_child(ti)
	_temple.pressed.connect(func() -> void: _sakak_sec(not _self_mode))
	_temple.visible = CHANCES[clampi(stage, 0, 3)] < 100
	_bar.add_child(_temple)
	hud._place_kenar(_temple, Control.PRESET_BOTTOM_RIGHT, Vector2(-330, -262), Vector2(96, 96))
	# dokunuşları bakışa çevirmesin (hud: düğmenin üstünden başlayan sürükleme kamerayı döndürmez)
	hud._tap_blockers.append(_trig)
	hud._tap_blockers.append(_temple)
	root().add_child(_bar)
	_trig_durum()
	# düğmeler büyüyerek gelir
	for b in [_trig, _temple]:
		b.pivot_offset = b.custom_minimum_size / 2.0
		b.scale = Vector2.ONE * 0.6
		b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not _ipucu_goruldu:
		_ipucu_goruldu = true
		_kaydir_ipucu()
	play("horoz", -6.0)


# İlk sırada bir kez: el ikonu ekranın ortasında sağa sola kayar (ekranı kaydırarak nişan al). Yazı yok.
func _kaydir_ipucu() -> void:
	var el := UI.icon("el", 78)
	el.mouse_filter = Control.MOUSE_FILTER_IGNORE
	el.set_anchors_preset(Control.PRESET_CENTER)
	el.size = Vector2(78, 78)
	var c := Vector2(-39, 34)  # nişangahın hemen altında
	el.position = Vector2.ZERO
	el.offset_left = c.x
	el.offset_top = c.y
	el.offset_right = c.x + 78
	el.offset_bottom = c.y + 78
	el.modulate.a = 0.0
	_bar.add_child(el)
	var tw := el.create_tween()
	tw.tween_property(el, "modulate:a", 0.9, 0.25)
	for k in 2:
		tw.tween_property(el, "offset_left", c.x + 110.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_property(el, "offset_right", c.x + 188.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(el, "offset_left", c.x - 110.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_property(el, "offset_right", c.x - 32.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(el, "offset_left", c.x, 0.4)
	tw.parallel().tween_property(el, "offset_right", c.x + 78.0, 0.4)
	tw.tween_property(el, "modulate:a", 0.0, 0.3)
	tw.tween_callback(el.queue_free)


func _free_bar() -> void:
	_aim_vurgu(_aim_id, false)
	if w and w.hud:
		for b in [_trig, _temple]:
			if b:
				w.hud._tap_blockers.erase(b)
	if is_instance_valid(_bar):
		_bar.queue_free()
	_bar = null
	_trig = null
	_temple = null
	_aim_ov = null
	_aim_id = 0
	_self_mode = false


# Bakıştan hedef: masada hayatta olan (ölmemiş, masadaki) başkaları.
func _aim_ids() -> Array:
	var out := []
	for id in alive:
		var pid := int(id)
		if pid != me() and not (pid in dead) and not _corpses.has(pid) and w.remotes.has(pid):
			out.append(pid)
	return out


func _aim_point(id: int) -> Vector3:
	var hp := _bone_world(id, "Head")
	if hp == Vector3.ZERO and w.remotes.has(id):
		hp = (w.remotes[id].root as Node3D).global_position + Vector3(0, 1.15, 0)
	return hp + Vector3(0, 0.05, 0)


# Kameranın baktığı yöne en yakın kişi (baş ya da göğüs açısı, koni içinde); yoksa 0.
func _aim_candidate() -> int:
	var cam: Camera3D = w.player.camera
	var from := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var best := 0
	var best_a := INF
	for pid in _aim_ids():
		var hp := _aim_point(pid)
		var a := minf(fwd.angle_to(hp - from), fwd.angle_to(hp - Vector3(0, 0.3, 0) - from))
		var cone := AIM_KEEP if pid == _aim_id else AIM_CONE
		if a < cone and a < best_a:
			best_a = a
			best = pid
	return best


func _update_aim(delta: float) -> void:
	if not is_instance_valid(_bar) or not is_instance_valid(w.player):
		return
	if not _self_mode:
		var c := _aim_candidate()
		if c != _aim_cand:
			_aim_cand = c
			_aim_cand_t = 0.0
		else:
			_aim_cand_t += delta
		if c != _aim_id and _aim_cand_t >= (AIM_HOLD if c != 0 else AIM_LOSE):
			_set_aim(c)
	# silah eli: hedefin başına doğrulur (oyuncu etrafa bakarken de takip eder)
	if _self_mode:
		pass
	elif _aim_id != 0:
		w.player.set_hand_pose(1, {"obj": "silah", "aim_at": _aim_point(_aim_id), "u": Vector3.UP, "e": Vector3(0.5, -1.0, 0.1), "c": [0.6, 0.45, 1.0, 1.0, 1.0], "r": 9.0})
	# halka: hedefin başının ekrandaki yeri
	var ov := _aim_ov
	ov.locked = _aim_id != 0 and not _self_mode
	ov.self_mode = _self_mode
	var want_a := 0.0
	if ov.locked:
		var cam: Camera3D = w.player.camera
		var hp := _aim_point(_aim_id)
		if not cam.is_position_behind(hp):
			var right := cam.global_transform.basis.x
			ov.ring_pos = cam.unproject_position(hp)
			ov.ring_r = clampf(cam.unproject_position(hp + right * 0.16).distance_to(ov.ring_pos), 22.0, 110.0)
			want_a = 1.0
	ov.ring_a = move_toward(ov.ring_a, want_a, delta * 6.0)


func _set_aim(id: int) -> void:
	_aim_vurgu(_aim_id, false)
	_aim_id = id
	_aim_vurgu(id, true)
	if id != 0:
		if is_instance_valid(_aim_ov):
			_aim_ov.pop = 1.0
		UI.tik(-16.0)
		if OS.has_feature("mobile"):
			Input.vibrate_handheld(12)
	else:
		w.player.set_hand_pose(1, "silah")
	_trig_durum()


# Hedeflenenin baş üstündeki adı hafifçe kızarır.
func _aim_vurgu(id: int, on: bool) -> void:
	if id == 0 or id == me() or not w or not w.remotes.has(id):
		return
	(w.remotes[id].label as Label3D).modulate = Color(1.0, 0.42, 0.36) if on else Color.WHITE


# Şakak düğmesi: namlu kendi şakağına döner (tetik kendine sıkar) ya da geri bakışa döner.
func _sakak_sec(on: bool) -> void:
	if not is_instance_valid(_bar) or busy:
		return
	if on and CHANCES[clampi(stage, 0, 3)] >= 100:
		return
	_self_mode = on
	_aim_vurgu(_aim_id, false)
	_aim_id = 0
	_aim_cand = 0
	_aim_cand_t = 0.0
	w.player.set_hand_pose(1, "sakak" if on else "silah")
	_sakak_gorunum(on)
	if is_instance_valid(_temple):
		w.hud._disk_renk(_temple, Color(UI.AMBER, 0.85) if on else Color(0, 0, 0, 0))
	if on:
		play("horoz", -10.0)
	_trig_durum()


func _trig_durum() -> void:
	if not is_instance_valid(_trig):
		return
	var ok := (_self_mode or _aim_id != 0) and not busy
	_trig.disabled = not ok
	_trig.modulate = Color.WHITE if ok else Color(0.62, 0.6, 0.6, 0.55)


func _tetik() -> void:
	if busy or not is_instance_valid(_bar):
		return
	if _self_mode:
		_fire("kendi")
	elif _aim_id != 0 and _aim_id in alive and not (_aim_id in dead):
		_fire(_aim_id)
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(30)


func _fire(v) -> void:
	if busy:
		return
	busy = true  # sunucudan atış gelene kadar düğmeler kapalı
	g.decided.emit({"atis": v})
	_free_bar()
	# sunucu reddederse (ör. süre) kilitli kalmasın. Yalnız bu istek hâlâ yanıtsızsa açılır: eskiden önceki
	# atışın zamanlayıcısı sonraki atışın canlandırması sırasında busy'yi açıyor, tetik düğmesi
	# vurulduktan sonra bile yeniden beliriyordu.
	_istek_sayac += 1
	_istek = _istek_sayac
	var no := _istek
	g.get_tree().create_timer(4.0).timeout.connect(_istek_zaman_asimi.bind(no))


# Bakışı bir oyuncunun başına çevirir (test ve otomatik maç; oyuncu kendisi ekranı kaydırarak yapar).
func _look_at(id: int) -> void:
	var p: CharacterBody3D = w.player
	for k in 2:
		var to: Vector3 = _aim_point(id) - p.camera.global_position
		p.rotation.y = atan2(-to.x, -to.z)
		p.head.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
		p.camera.force_update_transform()


# Otomatik botlu maç: sıra bendeyken bir başkasına (bakışla), bir kendime (şakak) sıkarım. Aynı sıra için
# iki olay ("atis" ve "sira") ikişer çağrı yapabilir: biri sürerken ikincisi beklemeden döner.
var _auto_mesgul := false


func auto_sira(shot: Callable) -> void:
	if _auto_mesgul:
		return
	_auto_mesgul = true
	await _auto_sira(shot)
	_auto_mesgul = false


func _auto_sira(shot: Callable) -> void:
	if not is_instance_valid(_bar):
		await g.get_tree().create_timer(0.3).timeout
		if not is_instance_valid(_bar):
			return
	_auto_n += 1
	var kendine: bool = CHANCES[clampi(stage, 0, 3)] < 100 and _auto_n % 2 == 0
	if kendine:
		_sakak_sec(true)
	else:
		var ids := _aim_ids()
		if ids.is_empty():
			return
		_look_at(ids[randi() % ids.size()])
	await g.get_tree().create_timer(0.8).timeout
	if not is_instance_valid(_bar) or busy:
		return
	await shot.call("rulet_sakak" if kendine else "rulet_sira_sende")
	if is_instance_valid(_bar) and not busy:
		_tetik()


# Test pozu (oyunici_test ekran=rulet_hedef): masada 3 bot, silah bende; hedef=<id>|kendi|0 bakışı ayarlar.
func test_hedef(args: Dictionary) -> void:
	for p in g.net.players:
		if int(p.id) != me():
			p["bot"] = true
			w._on_remote_state(int(p.id), {"p": [0.0, 0.0], "y": 0.0, "o": false})
	w.game_on = true  # mod.process çalışsın, masadan "kalk" düğmesi çıkmasın (gerçek maçtaki gibi)
	state["phase"] = "oyun"
	stage = int(args.get("asama", "1"))
	holder = me()
	alive = [1, 2, 3, 4]
	dead = []
	if args.has("olu"):
		dead = [int(args.olu)]
		alive.erase(int(args.olu))
	turn_left = 9.0
	on_state(state, false)
	await g.get_tree().create_timer(1.2).timeout  # oturma
	_refresh()
	var h := str(args.get("hedef", "2"))
	if h == "kendi":
		_sakak_sec(true)
	elif h != "0":
		_look_at(int(h))
	else:
		# masadakilerin arasından boşluğa bakar: hedef yok, tetik pasif
		w.player.rotation.y += deg_to_rad(float(args.get("don", "150")))
		w.player.head.rotation.x = 0.0
	if args.has("bak"):
		# test: yukarı/aşağı bakış (derece); oturma geçişi yavaş biterse ezmesin diye biraz sonra yeniden
		w.player.head.rotation.x = deg_to_rad(float(args.bak))
		await g.get_tree().create_timer(0.6).timeout
		w.player.head.rotation.x = deg_to_rad(float(args.bak))
	if args.has("yakin"):
		# test: hedeflenen botun boynuna/yakasına yakından bakan kamera
		var id := int(args.yakin)
		var cam := Camera3D.new()
		w.add_child(cam)
		var hp := _bone_world(id, "Neck")
		var to_me: Vector3 = w.player.global_position - hp
		to_me.y = 0.0
		cam.global_position = hp + to_me.normalized() * 0.55 + Vector3(0, 0.08, 0)
		cam.look_at(hp, Vector3.UP)
		cam.fov = 40.0
		cam.current = true
	if args.has("atis"):
		# test: o an doğrultulan kişiye (ya da kendine) atış canlandırması, boş tetik (sunucusuz); çekim wait= ile
		var hd: int = me() if _self_mode else (_aim_id if _aim_id != 0 else 2)
		_free_bar()
		on_event({"tur": "atis", "atan": me(), "hedef": hd, "patladi": false, "olen": 0, "sira": me(), "hayatta": alive, "sure": 9})
		return
	if args.has("ipucu"):
		# kaydırma ipucu baştan (çekim anı: wait= ile, ~1 sn)
		if is_instance_valid(_bar):
			_kaydir_ipucu()
		return
	await g.get_tree().create_timer(float(args.get("bekle", "3.2"))).timeout


func _istek_zaman_asimi(no: int) -> void:
	if busy and _istek == no:
		_istek = 0
		busy = false
		_refresh()


# Birinci şahıs altıpatar (silah sendeyken): karakterin gerçek sağ elinde, kabza avuçta, parmaklar kavrar.
func _set_gun(on: bool) -> void:
	var p: CharacterBody3D = w.player
	if on and not is_instance_valid(_gun):
		_gun = Node3D.new()
		Props.revolver(_gun)
		p.hold_item(1, _gun, AimMod.item_offset("silah", 1))
		p.set_hand_pose(1, "silah")
	elif not on and is_instance_valid(_gun):
		_sakak_gorunum(false)
		p.hold_item(1, null)
		_gun.queue_free()
		_gun = null
		p.set_hand_pose(1, "")


# Kendine doğrultma görünümü (birinci şahıs): kol ve el gizlenir, yalnız altıpatar kameraya bağlı olarak
# ekranın sağında yandan (profilden) görünür; namlu sağa ve geriye, şakağa doğru döner, hafif eğik.
# Gerçekte şakağa dayalı bir silah görüş alanının dışında kalır (ya da yalnız tamburun arkası, delikli bej
# bir şekil olarak görünür): FPS oyunlarındaki gibi silah biraz öne alınıp tanınır hâlde gösterilir.
# Kamera 3,5° sağa yatar ve hafifçe yakınlaşır (gerilim). Eldeki gerçek silah bu sırada gizli.
var _sakak_gun: Node3D
var _sakak_fov := 0.0
const SAKAK_ARKA := Vector3(0.2, -0.05, -0.4)  # silahın kökü (horoz/kabza üstü), kamera uzayı
const SAKAK_YON := Vector3(0.75, 0.5, 0.6)  # namlunun gösterdiği yön: sağa, biraz yukarı ve geriye (şakağa)


func _sakak_xf() -> Transform3D:
	var b := Basis.looking_at(SAKAK_YON.normalized(), Vector3.UP)
	b = b * Basis(Vector3.BACK, deg_to_rad(-12.0))  # hafif eğik
	return Transform3D(b, SAKAK_ARKA)


func _sakak_gorunum(on: bool) -> void:
	var p: CharacterBody3D = w.player if w else null
	if not p:
		return
	if on == is_instance_valid(_sakak_gun):
		return
	var cam: Camera3D = p.camera
	if on:
		_sakak_gun = Node3D.new()
		Props.revolver(_sakak_gun)
		cam.add_child(_sakak_gun)
		p._fp_layers(_sakak_gun, false)
		var xf := _sakak_xf()
		# sağ kenardan kayarak gelir
		_sakak_gun.transform = Transform3D(xf.basis, xf.origin + Vector3(0.12, -0.08, 0.02))
		_sakak_gun.create_tween().tween_property(_sakak_gun, "transform", xf, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		# silahı aydınlatan küçük dolgu ışığı (yalnız birinci şahıs katmanında): doku ve metal net görünsün
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.85, 0.65)
		l.light_energy = 0.3
		l.omni_range = 0.8
		l.light_cull_mask = p.FP_LAYER
		l.position = Vector3(-0.05, 0.12, 0.05)
		_sakak_gun.add_child(l)
		if is_instance_valid(_gun):
			_gun.visible = false
		if p.body.has_method("set_fp_hide"):
			p.body.call("set_fp_hide", true)
		_sakak_fov = cam.fov
		var tw := p.create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(p.head, "rotation:z", deg_to_rad(-3.5), 0.35)
		tw.tween_property(cam, "fov", _sakak_fov - 6.0, 0.35)
	else:
		_sakak_gun.queue_free()
		_sakak_gun = null
		if is_instance_valid(_gun):
			_gun.visible = true
		if p.body.has_method("set_fp_hide"):
			p.body.call("set_fp_hide", false)
		if not _i_died:
			var tw := p.create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw.tween_property(p.head, "rotation:z", 0.0, 0.3)
			tw.tween_property(cam, "fov", _sakak_fov, 0.3)
		else:
			cam.fov = _sakak_fov


# Şakaktaki silahın geri tepmesi: namlu bir anlığına yukarı-dışarı sıçrar, yerine döner.
func _sakak_tepme() -> void:
	if not is_instance_valid(_sakak_gun):
		return
	var xf := _sakak_xf()
	var kick := Transform3D(xf.basis.rotated(Vector3.BACK, deg_to_rad(-9.0)), xf.origin + Vector3(0.03, 0.025, 0.01))
	var tw := _sakak_gun.create_tween()
	tw.tween_property(_sakak_gun, "transform", kick, 0.04)
	tw.tween_property(_sakak_gun, "transform", xf, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# Kendi atışım: namlu şakağa döner ya da kol hedefe uzanır; patlarsa geri teper, sonra silah dinlenir.
func _aim_gun(at_self: bool, target := 0, fired := false) -> void:
	_fp_aim_target = target
	_fp_aim(at_self)
	var tw := create_tween()
	tw.tween_interval(1.9)  # tetik anı (_shot ile aynı)
	if at_self:
		tw.tween_callback(_sakak_tepme)  # boş çıksa da tetik ve horoz silahı sarsar
	if fired and not at_self:
		tw.tween_callback(_fp_recoil)
		tw.tween_interval(0.12)
		tw.tween_callback(_fp_aim.bind(false))
	tw.tween_interval(0.55)
	tw.tween_callback(_fp_rest)


func _fp_target_point() -> Vector3:
	if w.remotes.has(_fp_aim_target):
		return _bone_world(_fp_aim_target, "Head")
	return w.player.camera.global_position - w.player.global_transform.basis.z * 2.0


func _fp_aim(at_self: bool) -> void:
	if not is_instance_valid(_gun):
		return
	_sakak_gorunum(at_self)
	if at_self:
		w.player.set_hand_pose(1, "sakak")
	else:
		w.player.set_hand_pose(1, {"obj": "silah", "aim_at": _fp_target_point(), "u": Vector3.UP, "e": Vector3(0.5, -1.0, 0.1), "c": [0.6, 0.45, 1.0, 1.0, 1.0], "r": 9.0})


# Geri tepme: namlu bir anlığına yukarı kalkar.
func _fp_recoil() -> void:
	if not is_instance_valid(_gun):
		return
	var cam: Transform3D = w.player.camera.global_transform
	var t := _fp_target_point()
	var up := cam.basis.y * cam.origin.distance_to(t) * 0.35
	w.player.set_hand_pose(1, {"obj": "silah", "aim_at": t + up, "u": Vector3.UP, "e": Vector3(0.5, -1.0, 0.1), "c": [0.6, 0.45, 1.0, 1.0, 1.0], "r": 45.0, "reach": 0.36})


func _fp_rest() -> void:
	_sakak_gorunum(false)
	if is_instance_valid(_gun):
		w.player.set_hand_pose(1, "silah")


# Başkasının elindeki altıpatar (masadakiler görür): o oyuncunun gerçek sağ elinde, iskelet her karede pozlar.
func _set_remote_gun(id: int) -> void:
	if id == _remote_gun_id and is_instance_valid(_remote_gun):
		return
	var old := _pose(_remote_gun_id)
	if old:
		old.mode = ""
		old.aim = 0.0
		old.hold(1, null)
	if is_instance_valid(_remote_gun):
		_remote_gun.queue_free()
	_remote_gun = null
	_remote_gun_id = id
	_remote_mode = "silah"
	_remote_w = 0.0
	if id == 0 or not w.remotes.has(id) or not (id in alive):
		return
	_remote_gun = Node3D.new()
	w.add_child(_remote_gun)
	Props.revolver(_remote_gun)
	_remote_gun.visible = false  # el ilk kez pozlanınca görünür
	_update_remote_gun(0.0)


# Uzaktaki oyuncunun iskeleti ve kol/gövde pozlayıcısı.
func _skel(id: int) -> Skeleton3D:
	if not w.remotes.has(id):
		return null
	var sks: Array = (w.remotes[id].body as Node).find_children("*", "Skeleton3D", true, false)
	return sks[0] if not sks.is_empty() else null


func _pose(id: int) -> Node:
	if id == 0 or not w.remotes.has(id):
		return null
	return AimMod.of_body(w.remotes[id].body)


func _bone_world(id: int, bone: String) -> Vector3:
	var sk := _skel(id)
	if not sk:
		return Vector3.ZERO
	var b := sk.find_bone("mixamorig_" + bone)
	if b < 0:
		return sk.global_position
	return sk.global_transform * sk.get_bone_global_pose(b).origin


# Uzaktaki silah her karede: pozlayıcıya o anki poz (boşta / şakakta / hedefte) ve avuçtaki silah verilir.
func _update_remote_gun(delta: float) -> void:
	if not is_instance_valid(_remote_gun) or not w.remotes.has(_remote_gun_id):
		return
	var pose := _pose(_remote_gun_id)
	if not pose:
		return
	if _corpses.has(_remote_gun_id):
		# vurulan atıcı: silah ölü elinde kalır, kol gevşer
		pose.mode = ""
		pose.aim = 0.0
		pose.hold(1, _remote_gun, AimMod.item_offset("silah", 1))
		return
	_remote_w = minf(1.0, _remote_w + delta * 3.0)
	pose.mode = _remote_mode
	if _remote_mode == "hedef":
		pose.mode_target = _remote_target_point()
	pose.aim = smoothstep(0.0, 1.0, _remote_w)
	pose.hold(1, _remote_gun, AimMod.item_offset("silah", 1))
	if _remote_w > 0.0:
		_remote_gun.visible = true


func _remote_target_point() -> Vector3:
	if _remote_target == me():
		return w.player.camera.global_position
	if w.remotes.has(_remote_target):
		return _bone_world(_remote_target, "Head")
	return Vector3.ZERO


# Uzaktaki atıcı: kendine sıkıyorsa namluyu sağ şakağına dayar, değilse kolunu hedefe uzatır; sonra dinlenir.
func _aim_remote(shooter: int, target: int) -> void:
	if shooter != _remote_gun_id or not is_instance_valid(_remote_gun):
		_set_remote_gun(shooter)
	_remote_target = target
	_remote_mode = "sakak" if target == shooter else "hedef"
	var tw := create_tween()
	tw.tween_interval(2.45)
	tw.tween_callback(_remote_rest.bind(shooter))


func _remote_rest(shooter: int) -> void:
	if shooter == _remote_gun_id:
		_remote_mode = "silah"


# Namlu alevi: atışta silahın ucunda kısa bir parlama.
func _muzzle(shooter: int) -> void:
	var gun: Node3D = null
	if shooter == me():
		gun = _sakak_gun if is_instance_valid(_sakak_gun) else _gun
	elif _remote_gun_id == shooter:
		gun = _remote_gun
	if not is_instance_valid(gun):
		return
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.7, 0.35)
	l.light_energy = 8.0
	l.omni_range = 4.0
	var tip: Node3D = gun.find_child("namlu_agzi", true, false)
	if tip:
		tip.add_child(l)
	else:
		l.position = Vector3(0, 0.03, -0.22)
		gun.add_child(l)
	preload("res://scripts/efekt.gd").namlu(gun, l.global_transform, false)  # namlu alevi, barut dumanı, kıvılcım (scripts/efekt.gd)
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
		var s := 1.2 / maxf(tb.size.x, tb.size.z)  # 1.2 m çaplı masa
		# boyu oturan birine göre: üstü ~76 cm (düz ölçekte 86 cm, oturanın göğsüne geliyordu)
		table.scale = Vector3(s, TABLE_TOP / tb.size.y, s)
	# koridorda yürüyen mahkum masanın içinden geçmesin
	if w.walker:
		w.walker.visible = false
		w.walker.global_position = Vector3(3.9, -20, 0)
	# her oyuncuya bir metal tabure. Model 88 cm'lik bar taburesi; oturma pozunda kalça ~49 cm'de olduğu
	# için düz ölçekte oturak göğüs/kafa hizasında kalıyordu (yukarıdan bakınca kafaların içinde görünüyordu).
	# Boyu oturma yüksekliğine indirilir: oturak kalçanın hemen altında, bacaklar aşağıda.
	for id in state.get("players", []):
		var cp := _seat_of(int(id))
		var stool: Node3D = w.model("metal_stool_01", cp - CENTER, _chair_yaw(cp), 1.0, NAN, _arena)
		var sb: AABB = w._bounds(stool, stool)
		if sb.size.y > 0.1:
			stool.scale = Vector3(1.0, SEAT_TOP / sb.size.y, 1.0)
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
	_labels(0.0011)
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


# Masada adlar küçük ve sade: uzaklıktan bağımsız sabit ekran boyu (yakından dev görünüyordu), oturan
# başın hemen üstünde (ayakta boyuna göre 2 m'de havada kalıyordu). px = 0: masadan kalkınca eski hâli.
func _labels(px: float) -> void:
	for id in w.remotes:
		var l := w.remotes[id].label as Label3D
		if px > 0.0:
			l.fixed_size = true
			l.pixel_size = px
			l.font_size = 40
			l.outline_size = 6
			l.position.y = 1.4
		else:
			l.fixed_size = false
			l.pixel_size = 0.004
			l.font_size = 48
			l.outline_size = 8
			l.position.y = 2.05


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
	p.set_hand_pose(0, "")
	p.set_hand_pose(1, "")
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# oturduğu yerde yığılır: baş yana ve öne düşer (yere düşmez)
	tw.tween_property(p.head, "position:y", p.head.position.y - 0.32, 0.45)
	tw.parallel().tween_property(p.head, "rotation:z", 0.75, 0.45)
	tw.parallel().tween_property(p.head, "rotation:x", deg_to_rad(-55), 0.45)
	tw.tween_callback(_show_dead)
	tw.tween_interval(2.6)
	# izleyici: masanın üstünden bakar
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(p.head, "position:y", 2.5, 1.2)
	tw.parallel().tween_property(p.head, "rotation:z", 0.0, 1.2)
	tw.parallel().tween_property(p.head, "rotation:x", deg_to_rad(-40), 1.2)
	# yukarıdan bakarken baş üstündeki adlar kameraya çok yakın kalıp dev ve yarım görünüyordu (kimin sırası
	# olduğu sol üstte yazıyor): izlerken adlar gizlenir, oyun bitince geri gelir
	tw.parallel().tween_callback(_adlar_gizle).set_delay(0.4)


func _adlar_gizle() -> void:
	for id in w.remotes:
		(w.remotes[id].label as Label3D).visible = false


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
	_update_remote_gun(delta)
	_update_aim(delta)
	if phase() == "oyun" and not busy and turn_left > 0.0:
		var before := ceili(turn_left)
		turn_left = maxf(0.0, turn_left - delta)
		if is_instance_valid(_drum):
			(_drum as Drum).left = turn_left
			_drum.queue_redraw()
		if ceili(turn_left) != before:
			if holder == me() and turn_left <= 5.0 and turn_left > 0.0:
				play("tik", -4.0)


# Bant sadece gerektiğinde: kim/şans/süre sol üstteki tambur göstergesinde.
func banner() -> Array:
	if me() in dead:
		return ["İZLEYİCİSİN", ""]
	if phase() == "anons":
		return ["SİLAH DOLDURULUYOR", ""]
	if phase() == "oyun" and holder == me():
		return ["SIRA SENDE", ""]  # nasıl oynanacağı yazıyla değil: nişangah, halka ve tetik
	return ["", ""]


func help_rows() -> Array:
	return [
		["oyna", "Kendine sık ya da birine"],
		["kilit", "Boş çıkarsa şans artar"],
		["tac", "Son kalan kazanır"],
	]


func on_result(d: Dictionary) -> void:
	_set_gun(false)
	_hud.visible = false
	var win := int(d.get("kazanan", 0))
	var dead: Array = d.get("olenler", []).map(func(x) -> int: return int(x))
	var mood := 1 if win == me() else (-1 if me() in dead else 0)
	if win:
		result_modal(tr("SON KALAN: %s") % (tr("SEN") if win == me() else up(str(d.get("kazanan_ad", "?")))), GREEN, [], d, [], mood)
	else:
		var names := []
		for id in d.get("hayatta", []):
			names.append(pname(int(id)))
		result_modal("SÜRE BİTTİ", GOLD, [tr("Hayatta kalanlar: %s") % ", ".join(names)], d, [], mood)


func cleanup() -> void:
	_sakak_gorunum(false)
	_set_gun(false)
	_set_remote_gun(0)
	_revive_all()
	if is_instance_valid(_arena):
		_arena.queue_free()
	if w:
		if w.walker:
			w.walker.visible = true
			w.walker.position = Vector3(4.4, 0, -16.0)
		w.place_bots()
		_labels(0.0)
		for id in w.remotes:
			(w.remotes[id].label as Label3D).visible = true  # izlerken gizlenen adlar
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
	_free_bar()
	for n in [_hud, _dead_ov]:
		if is_instance_valid(n):
			n.queue_free()
	if w and w.player:
		w.player.set_hand_pose(0, "")
		w.player.set_hand_pose(1, "")
	close_panel()
	close_card()
