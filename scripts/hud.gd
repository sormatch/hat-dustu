# Oyun içi ekran: joystick, eylem düğmesi, EĞİL / HAREKET, nişan noktası, süre, bildirimler,
# bekleme salonu (oda kodu, oyuncu kartları, HAZIRIM / BAŞLAT), telefon rehberi ve arama şeridi.
# Tasarım takımı: scripts/ui.gd (docs/TASARIM.md). Oyuncu avatarı / şikayet: scripts/oyuncu_ui.gd
extends CanvasLayer

signal action_pressed
signal contact_chosen(id: int)
signal settings_pressed
signal emote_chosen(id: String)
signal crouch_pressed
signal ptt_changed(down: bool)
signal lobby_ready(on: bool)
signal lobby_start
signal lobby_invite
signal lobby_leave
signal lobby_bot(add: bool)  # kurucu: bot ekle / çıkar
signal hangup_pressed  # arama şeridindeki kapat düğmesi

const UI := preload("res://scripts/ui.gd")
const OU := preload("res://scripts/oyuncu_ui.gd")
const Catalog := preload("res://scripts/catalog.gd")
const Dil := preload("res://scripts/dil.gd")
const JOY_R := 85.0
const JOY_HOME := Vector2(50, -280)
const MAX_OYUNCU := 8

var floating_joy := true  # joystick parmağın değdiği yerde açılır
var sprint := false  # joystick yukarıdaki KOŞ halkasında
var gems_label: Label
var emote_btn: Button
var crouch_btn: Button
var ptt_btn: Button
var fps_label: Label
# kurucunun seçtiği oyun ("" = hepsi sırayla)
const GAME_CHOICES := [["", "TÜM OYUNLAR"], ["tahta", "KARA TAHTA"], ["devre", "KISA DEVRE"], ["kimkim", "KİM KİM?"], ["yalanci", "YALANCI"], ["rulet", "RUS RULETİ"], ["c4", "C4"], ["ortalama", "ORTALAMA SAYI"]]
var game_pick := 0
var _ready_on := false
var _game_pills: Array[Control] = []
var emote_panel: PanelContainer
var emote_grid: GridContainer
var _tap_blockers: Array[Control] = []

var player: Node  # main.gd bağlar
var move := Vector2.ZERO

var joy: Joy
var joy_index := -1
var look_index := -1

var action_btn: Button
var prompt_label: Label
var timer_label: Label
var timer_pill: PanelContainer
var _last_sec := -1
var _tick: AudioStreamPlayer
var ring_label: Label  # main.gd yazar ("Telefon çalıyor: Ali" + visible); arama şeridi bunu izler
var call_panel: PanelContainer  # altyazı balonu (çevrimdışı konuşmada karşı tarafın sözleri)
var call_title: Label
var call_text: Label
var hint: Label
var avatars: HBoxContainer
var round_pill: PanelContainer
var contacts: Control
var contact_list: GridContainer

var _root: Control
var _ust: Control  # modal ve menüler (açıkken joystick / bakış çalışmaz)
var _toast_host: Control
var _toast: Control
var _t := 0.0

# eylem düğmesi
var _action_text := ""
var _action_label: Label
var _action_icon: TextureRect
var _action_halo: Panel
var _action_shake: Tween

# telefon şeridi (sağ üst, oyun panellerinin de üstünde)
var _tel: CanvasLayer
var _tel_kok: Control
var _pill: PanelContainer
var _pill_style: StyleBoxFlat
var _pill_avatar_kutu: Control
var _pill_dalga: Dalga
var _pill_ad: Label
var _pill_durum: Label
var _pill_kapat: Button
var _pill_sikayet: Button
var _call_state := ""  # "" / caliyor / ariyor / baglaniyor / hatta
var _call_who := ""
var _call_t := 0.0
var _call_time_text := ""

# bekleme salonu
var lobby_panel: Control  # bekleme salonu katmanı (oda kartı + oyuncu kartları + alt düğmeler)
var _lobby_card: PanelContainer
var _lobby_code: Label
var _lobby_code_text := ""
var _lobby_ready_lbl: Label
var _lobby_count_row: Control
var _lobby_count_num: Label
var _lobby_count_bar: UI.Cubuk
var _lobby_host_box: VBoxContainer
var _lobby_game_btn: Button
var _lobby_bot_num: Label
var _lobby_bot_minus: Button
var _lobby_bot_plus: Button
var _lobby_strip: HBoxContainer
var _lobby_bar: HBoxContainer
var _lobby_ready_btn: Button
var _lobby_start_btn: Button
var _lobby_invite_btn: Button
var _lobby_ids: Array = []
var _lobby_host := false
var _public_left := -1.0
var _public_total := 30.0


# ---------------------------------------------------------------- joystick

class Joy extends Control:
	var knob := Vector2.ZERO
	var sprint := false
	var active := false

	func _draw() -> void:
		var c := size / 2.0
		# taban: koyu disk + krem halka + amber yön okları
		draw_circle(c, 92.0, Color(0, 0, 0, 0.16))
		draw_circle(c, 86.0, Color(0.03, 0.04, 0.04, 0.42))
		draw_arc(c, 86.0, 0.0, TAU, 72, Color(0.95, 0.92, 0.85, 0.45), 4.0, true)
		draw_arc(c, 62.0, 0.0, TAU, 64, Color(1, 1, 1, 0.08), 2.0, true)
		for a in [0.0, PI / 2.0, PI, PI * 1.5]:
			var d := Vector2.from_angle(a)
			var p := c + d * 72.0
			var side := d.orthogonal() * 8.0
			draw_colored_polygon(PackedVector2Array([p + d * 9.0, p + side, p - side]), Color(1, 0.69, 0.13, 0.8 if active else 0.5))
		if active:
			# yukarıdaki halkaya itince hızlı koşma
			var sc := c + Vector2(0, -225)
			draw_circle(sc, 42.0, Color(1, 0.69, 0.13, 0.9 if sprint else 0.2))
			draw_arc(sc, 42.0, 0.0, TAU, 48, Color(1, 0.82, 0.4, 0.95), 3.0, true)
			var f: Font = UI.TITLE_FONT
			if not sprint:
				draw_string_outline(f, sc + Vector2(-42, 8), tr("KOŞ"), HORIZONTAL_ALIGNMENT_CENTER, 84, 22, 5, Color(0, 0, 0, 0.7))
			draw_string(f, sc + Vector2(-42, 8), tr("KOŞ"), HORIZONTAL_ALIGNMENT_CENTER, 84, 22, Color("#1a1206") if sprint else Color.WHITE)
			for i in 2:
				var y := sc.y - 52.0 - i * 12.0
				draw_polyline(PackedVector2Array([Vector2(sc.x - 10, y + 6), Vector2(sc.x, y - 2), Vector2(sc.x + 10, y + 6)]), Color(1, 0.82, 0.4, 0.8 - i * 0.3), 3.0, true)
		# topuz: gölge + açık çelik + amber göbek
		var k := c + knob
		draw_circle(k + Vector2(0, 4), 38.0, Color(0, 0, 0, 0.35))
		draw_circle(k, 38.0, Color("#ffb020") if sprint else Color(0.74, 0.75, 0.72, 0.95))
		draw_circle(k + Vector2(0, -4), 31.0, Color("#ffd36b") if sprint else Color(0.9, 0.9, 0.87, 0.95))
		draw_arc(k, 38.0, 0.0, TAU, 48, Color(0, 0, 0, 0.45), 2.0, true)
		draw_circle(k, 9.0, Color("#b86f00") if sprint else Color(1, 0.69, 0.13, 0.9 if active else 0.6))


# Arama şeridindeki avatarın arkasında yayılan halkalar (arıyor / çalıyor).
class Dalga extends Control:
	var renk := Color.WHITE
	var acik := false
	var _t := 0.0

	func _process(delta: float) -> void:
		if acik:
			_t += delta
			queue_redraw()

	func _draw() -> void:
		if not acik:
			return
		var c := size / 2.0
		for i in 3:
			var f := fmod(_t * 0.9 + i / 3.0, 1.0)
			draw_arc(c, 26.0 + f * 28.0, 0.0, TAU, 48, Color(renk, (1.0 - f) * 0.8), 3.0, true)


# ---------------------------------------------------------------- yardımcılar

# Bir arayüz parçasını ekranın bir köşesine/kenarına göre yerleştirir.
func _place(c: Control, preset: int, ofs: Vector2, sz: Vector2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = ofs.x
	c.offset_top = ofs.y
	c.offset_right = ofs.x + sz.x
	c.offset_bottom = ofs.y + sz.y


# Ekranın sol/sağ kenarına yaslı dokunmatik öğeler: telefonun yuvarlak köşesi, çentiği ya da kamera deliği
# altında kalmasın diye en az HUD_KENAR (ya da güvenli alan payı) kadar içeri alınır.
const HUD_KENAR := 20.0
const _SOL := [Control.PRESET_TOP_LEFT, Control.PRESET_BOTTOM_LEFT, Control.PRESET_CENTER_LEFT, Control.PRESET_LEFT_WIDE]
const _SAG := [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_RIGHT, Control.PRESET_RIGHT_WIDE]

func _place_kenar(c: Control, preset: int, ofs: Vector2, sz: Vector2) -> void:
	var g := UI.guvenli_pay()
	if preset in _SOL:
		ofs.x += maxf(g.x, HUD_KENAR)
	elif preset in _SAG:
		ofs.x -= maxf(g.z, HUD_KENAR)
	_place(c, preset, ofs, sz)


# Önce oyunun diline çevir, sonra büyük harf (Türkçede i -> İ, ı -> I)
static func _buyuk(s: String) -> String:
	return Dil.buyuk(Dil.t(s))


func _daire(c: Color, kenar: Color, px: float, glow := 0.0, kenar_px := 0) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = c
	st.border_color = kenar
	st.set_border_width_all(kenar_px if kenar_px > 0 else maxi(2, int(px * 0.03)))
	st.set_corner_radius_all(int(px))
	st.anti_aliasing = true
	if glow > 0.0:
		st.shadow_color = Color(c, glow)
		st.shadow_size = int(maxf(6.0, px * 0.12))
	return st


func _ana_bool(ad: String) -> bool:
	var p := get_parent()
	if p == null:
		return false
	var v = p.get(ad)
	return v is bool and v


# Koyu ad plakası (yuvarlak düğmelerin altında).
func _plaka(text: String, size := UI.FS_KUCUK) -> PanelContainer:
	var p := PanelContainer.new()
	var st := UI.flat(Color(0.04, 0.045, 0.045, 0.94), Color(1, 1, 1, 0.18), UI.R_KUCUK + 2)
	st.set_border_width_all(1)
	st.shadow_size = 3
	st.content_margin_left = 10
	st.content_margin_right = 10
	st.content_margin_top = 1
	st.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.title(text, size, UI.METIN, true)
	p.add_child(l)
	p.set_meta("label", l)
	return p


# Yuvarlak oyun düğmesi: perçinli çelik halka (btn_round) + isteğe bağlı renkli disk + ikon + altta ad plakası.
func _yuvarlak(px: float, icon_name: String, yazi: String, disk := Color(0, 0, 0, 0)) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(px, px)
	var bos := StyleBoxEmpty.new()
	for k in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(k, bos)
	var halo := Panel.new()
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(halo, Control.PRESET_FULL_RECT, Vector2(-px * 0.07, -px * 0.07), Vector2.ZERO)
	halo.offset_right = px * 0.07
	halo.offset_bottom = px * 0.07
	halo.visible = false
	b.add_child(halo)
	b.set_meta("halo", halo)
	var t := UI.texture("btn_round", int(px * 2))
	if t:
		var cer := TextureRect.new()
		cer.texture = t
		cer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cer.set_anchors_preset(Control.PRESET_FULL_RECT)
		cer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(cer)
	else:
		var yedek := Panel.new()
		yedek.add_theme_stylebox_override("panel", _daire(Color(0.06, 0.07, 0.07, 0.8), Color(1, 1, 1, 0.5), px / 2.0))
		yedek.set_anchors_preset(Control.PRESET_FULL_RECT)
		yedek.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(yedek)
	var d := Panel.new()
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ins := px * 0.17
	_place(d, Control.PRESET_FULL_RECT, Vector2(ins, ins), Vector2.ZERO)
	d.offset_right = -ins
	d.offset_bottom = -ins
	b.add_child(d)
	b.set_meta("disk", d)
	# disk üstünde ışık
	var parla := Panel.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(1, 1, 1, 0.16)
	ps.set_corner_radius_all(int(px))
	parla.add_theme_stylebox_override("panel", ps)
	parla.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(parla, Control.PRESET_FULL_RECT, Vector2(px * 0.28, px * 0.21), Vector2.ZERO)
	parla.offset_right = -px * 0.28
	parla.offset_bottom = -px * 0.53
	b.add_child(parla)
	b.set_meta("parla", parla)
	_disk_renk(b, disk)
	var ic := TextureRect.new()
	ic.texture = UI.icon_texture(icon_name, int(px * 0.5))
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ip := px * (0.28 if yazi == "" else 0.25)
	var dy := px * 0.05 if yazi != "" else 0.0
	_place(ic, Control.PRESET_CENTER, Vector2(-ip, -ip - dy), Vector2(ip * 2.0, ip * 2.0))
	b.add_child(ic)
	b.set_meta("ikon", ic)
	if yazi != "":
		var pl := _plaka(yazi, UI.FS_KUCUK if px < 130 else UI.FS_METIN)
		_place(pl, Control.PRESET_CENTER_BOTTOM, Vector2(0, -px * 0.17), Vector2.ZERO)
		pl.grow_horizontal = Control.GROW_DIRECTION_BOTH
		b.add_child(pl)
		b.set_meta("plaka", pl)
	b.button_down.connect(func() -> void:
		b.pivot_offset = b.size / 2.0
		b.create_tween().tween_property(b, "scale", Vector2.ONE * 0.9, 0.06)
		# oyun içi yuvarlak düğmeler: hafif dokunma sesi (BAS KONUŞ gibi basılı tutulanlarda "sessiz")
		if not b.get_meta("sessiz", false):
			UI.tik(-13.0))
	b.button_up.connect(func() -> void:
		b.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(b, "scale", Vector2.ONE, 0.16))
	return b


func _disk_renk(b: Button, c: Color, glow := 0.0) -> void:
	var d: Panel = b.get_meta("disk")
	d.visible = c.a > 0.0
	(b.get_meta("parla") as Control).visible = d.visible
	if d.visible:
		d.add_theme_stylebox_override("panel", _daire(c, c.lightened(0.45), b.custom_minimum_size.x / 2.0, glow, 3))


# Bir öğeyi (dx, dy) uzaktan yerine kaydırarak getirir.
func _kay(c: Control, dx: float, dy: float, sure := 0.38) -> void:
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, 0.22)
	for pr in [["offset_left", dx], ["offset_right", dx], ["offset_top", dy], ["offset_bottom", dy]]:
		var ad: String = pr[0]
		var d: float = pr[1]
		if d == 0.0:
			continue
		var goal: float = c.get(ad)
		tw.tween_property(c, ad, goal, sure).from(goal + d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _pop(c: Control) -> void:
	c.pivot_offset = c.custom_minimum_size / 2.0
	c.scale = Vector2.ONE * 0.6
	c.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(c, "scale", Vector2.ONE, 0.28)


# ---------------------------------------------------------------- kurulum

func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var root := _root

	# eski tur göstergesi (oyunda gösterilmiyor; main.gd gizler)
	round_pill = _plaka("TUR")
	round_pill.visible = false
	root.add_child(round_pill)
	_place(round_pill, Control.PRESET_TOP_LEFT, Vector2(104, 26), Vector2.ZERO)

	# Sol üst: ayarlar
	var gear := _yuvarlak(68, "ayarlar", "")
	gear.pressed.connect(func() -> void: settings_pressed.emit())
	root.add_child(gear)
	_place_kenar(gear, Control.PRESET_TOP_LEFT, Vector2(20, 10), Vector2(68, 68))
	_tap_blockers.append(gear)

	fps_label = UI.title("", UI.FS_KUCUK, UI.YESIL)
	fps_label.visible = false
	root.add_child(fps_label)
	_place_kenar(fps_label, Control.PRESET_TOP_LEFT, Vector2(22, 82), Vector2(120, 24))

	# elmas sayacı (oyunda gizli: elmas mağazada/menüde görünür)
	var gem_row := UI.counter("elmas", "0", 34)
	gems_label = gem_row.get_meta("label")
	gem_row.visible = false
	root.add_child(gem_row)
	_place_kenar(gem_row, Control.PRESET_TOP_RIGHT, Vector2(-28, 84), Vector2.ZERO)
	gem_row.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	# oyuncu yuvarlakları (oyunda gizli)
	avatars = HBoxContainer.new()
	avatars.add_theme_constant_override("separation", 8)
	avatars.visible = false
	root.add_child(avatars)
	_place_kenar(avatars, Control.PRESET_TOP_RIGHT, Vector2(-28, 20), Vector2.ZERO)
	avatars.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	# Üst orta: süre
	timer_pill = PanelContainer.new()
	timer_pill.add_theme_stylebox_override("panel", _timer_style(false))
	timer_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_label = UI.title("1:30", 32, UI.METIN, true)
	timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	timer_pill.add_child(timer_label)
	root.add_child(timer_pill)
	_place(timer_pill, Control.PRESET_CENTER_TOP, Vector2(-68, 12), Vector2(136, 58))
	timer_pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_game_pills.append(timer_pill)

	# Ekran ortası: nişan noktası (koyu kenarlı, her zeminde görünür)
	var dot := Panel.new()
	dot.add_theme_stylebox_override("panel", _daire(Color(1, 1, 1, 0.8), Color(0, 0, 0, 0.5), 5, 0.0, 2))
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dot)
	_place(dot, Control.PRESET_CENTER, Vector2(-5, -5), Vector2(10, 10))

	prompt_label = UI.title("", UI.FS_METIN, UI.METIN, true)
	root.add_child(prompt_label)
	_place(prompt_label, Control.PRESET_CENTER, Vector2(-200, 26), Vector2(400, 40))

	# Sol alt: joystick
	joy = Joy.new()
	joy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(joy)
	_place_kenar(joy, Control.PRESET_BOTTOM_LEFT, JOY_HOME, Vector2(240, 240))

	# Sağ alt: eylem düğmesi (büyük, ikonlu; altında ne yapacağı yazar)
	action_btn = _yuvarlak(158, "el", "EYLEM", UI.AMBER)
	_action_label = (action_btn.get_meta("plaka") as Control).get_meta("label")
	_action_icon = action_btn.get_meta("ikon")
	_action_halo = action_btn.get_meta("halo")
	_action_halo.visible = true
	action_btn.pressed.connect(func() -> void: action_pressed.emit())
	action_btn.visible = false
	root.add_child(action_btn)
	_place_kenar(action_btn, Control.PRESET_BOTTOM_RIGHT, Vector2(-206, -222), Vector2(158, 158))

	# EĞİL (eylemin solunda) ve HAREKET (eylemin üstünde)
	crouch_btn = _yuvarlak(96, "egil", "EĞİL")
	crouch_btn.pressed.connect(func() -> void: crouch_pressed.emit())
	root.add_child(crouch_btn)
	_place_kenar(crouch_btn, Control.PRESET_BOTTOM_RIGHT, Vector2(-322, -122), Vector2(96, 96))
	_tap_blockers.append(crouch_btn)
	emote_btn = _yuvarlak(96, "emote", "HAREKET")
	emote_btn.pressed.connect(func() -> void:
		_emote_ac(not emote_panel.visible)
		contacts.visible = false)
	root.add_child(emote_btn)
	_place_kenar(emote_btn, Control.PRESET_BOTTOM_RIGHT, Vector2(-175, -352), Vector2(96, 96))
	_tap_blockers.append(emote_btn)

	# bas-konuş: telefondayken basılı tutunca ses gider (HAREKET'in yerinde görünür)
	ptt_btn = _yuvarlak(132, "mikrofon", "BAS KONUŞ", UI.ZEYTIN)
	ptt_btn.set_meta("sessiz", true)  # basılı tutulur; tık sesi rahatsız etmesin / mikrofona girmesin
	ptt_btn.button_down.connect(func() -> void:
		ptt_changed.emit(true)
		_disk_renk(ptt_btn, UI.YESIL, 0.7))
	ptt_btn.button_up.connect(func() -> void:
		ptt_changed.emit(false)
		_disk_renk(ptt_btn, UI.ZEYTIN))
	ptt_btn.visible = false
	root.add_child(ptt_btn)
	_place_kenar(ptt_btn, Control.PRESET_BOTTOM_RIGHT, Vector2(-193, -392), Vector2(132, 132))
	_tap_blockers.append(ptt_btn)

	# hareket menüsü (HAREKET düğmesinin solunda açılır)
	emote_panel = PanelContainer.new()
	var eps := UI.flat(Color(UI.YUZEY, 0.95), Color(UI.AMBER, 0.55), UI.R_ORTA)
	eps.set_border_width_all(2)
	eps.content_margin_left = UI.B_S
	eps.content_margin_right = UI.B_S
	eps.content_margin_top = UI.B_S
	eps.content_margin_bottom = UI.B_S
	eps.shadow_size = 16
	emote_panel.add_theme_stylebox_override("panel", eps)
	emote_grid = GridContainer.new()
	emote_grid.columns = 2
	emote_grid.add_theme_constant_override("h_separation", UI.B_XS)
	emote_grid.add_theme_constant_override("v_separation", UI.B_XS)
	emote_panel.add_child(emote_grid)
	emote_panel.visible = false
	root.add_child(emote_panel)
	_place_kenar(emote_panel, Control.PRESET_BOTTOM_RIGHT, Vector2(-196, -470), Vector2.ZERO)
	emote_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	emote_panel.grow_vertical = Control.GROW_DIRECTION_END
	_tap_blockers.append(emote_panel)

	# Alt orta: çevrimdışı konuşmanın altyazısı
	_build_subtitle()

	_toast_host = Control.new()
	_toast_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_toast_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast_host)

	# telefon rehberi ve arama şeridi
	_build_contacts()
	_build_phone_strip()

	_ust = Control.new()
	_ust.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ust.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_ust)

	# Android geri tuşu / Esc (oyunda / lobide): önce açık menü ya da tahta kapanır, yoksa ayarlar açılır
	UI.geri_tusu(root, func() -> void:
		if emote_panel.visible:
			_emote_ac(false)
			return
		if contacts.visible:
			contacts.visible = false
			return
		var gu = get_parent().get("game_ui") if get_parent() else null
		if gu and is_instance_valid(gu) and gu.has_method("geri_kapat") and gu.geri_kapat():
			return
		settings_pressed.emit())


func _timer_style(urgent: bool) -> StyleBoxFlat:
	var st: StyleBoxFlat
	if urgent:
		st = UI.flat(Color(0.34, 0.04, 0.03, 0.94), UI.KIRMIZI, UI.R_ORTA, Color(UI.KIRMIZI, 0.6))
	else:
		st = UI.flat(Color(0.035, 0.045, 0.045, 0.86), Color(1, 1, 1, 0.18), UI.R_ORTA)
	st.set_border_width_all(2)
	st.border_width_bottom = 4
	st.content_margin_left = UI.B_M
	st.content_margin_right = UI.B_M
	st.content_margin_top = 2
	st.content_margin_bottom = 4
	return st


# ---------------------------------------------------------------- genel

func set_fps_visible(on: bool) -> void:
	fps_label.visible = on


func set_ptt(on: bool) -> void:
	ptt_btn.visible = on
	emote_btn.visible = not on
	if on:
		_emote_ac(false)
		_pop(ptt_btn)


func _emote_ac(on: bool) -> void:
	if on == emote_panel.visible:
		return
	emote_panel.visible = on
	if on:
		emote_panel.pivot_offset = Vector2(emote_panel.size.x, emote_panel.size.y * 0.5)
		emote_panel.scale = Vector2.ONE * 0.85
		emote_panel.modulate.a = 0.0
		var tw := emote_panel.create_tween().set_parallel(true)
		tw.tween_property(emote_panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(emote_panel, "modulate:a", 1.0, 0.14)


func _process(delta: float) -> void:
	_t += delta
	if _tel:
		_tel.visible = visible
	if _public_left >= 0.0 and lobby_panel and lobby_panel.visible:
		_public_left = maxf(0.0, _public_left - delta)
		_lobby_count_num.text = str(ceili(_public_left))
		_lobby_count_bar.value = _public_left / maxf(1.0, _public_total)
	if fps_label and fps_label.visible:
		fps_label.text = tr("%d FPS") % Engine.get_frames_per_second()
	if action_btn.visible:
		_action_halo.modulate.a = 0.35 + 0.35 * sin(_t * 4.0)
	_update_ring()
	if _call_state == "hatta" and _call_time_text == "":
		_call_t += delta
		_pill_durum.text = tr("● HATTA  %s") % ("%d:%02d" % [int(_call_t) / 60, int(_call_t) % 60])
	elif _call_state == "ariyor" or _call_state == "baglaniyor":
		var n := int(_t * 2.5) % 4
		_pill_durum.text = tr("ARANIYOR" if _call_state == "ariyor" else "BAĞLANIYOR") + ".".repeat(n)
	elif _call_state == "caliyor":
		_pill_style.shadow_size = int(10 + 10 * (0.5 + 0.5 * sin(_t * 9.0)))


func refresh_gems(n: int) -> void:
	gems_label.text = str(n)


# Hareket menüsü: sadece sahip olunan hareketler.
func set_emotes(owned_ids: Array) -> void:
	for ch in emote_grid.get_children():
		ch.queue_free()
	for it in Catalog.ITEMS.hareket:
		if not owned_ids.has(it[0]):
			continue
		var b := UI.button(_buyuk(str(it[1])), "ikincil", UI.BTN_H_KUCUK, UI.FS_METIN, "", 176)
		# yazı zaten çevrilip büyütüldü: ikinci kez çevrilmesin ("Hayır" -> "NO" -> kablo şemasındaki "NO" = "SOCKET" oluyordu)
		(b.get_meta("label") as Label).auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var id: String = it[0]
		b.pressed.connect(func() -> void:
			_emote_ac(false)
			emote_chosen.emit(id))
		emote_grid.add_child(b)


# Kısa bildirim (tasarım takımı UI.toast). Tür metinden anlaşılır: olumsuzlar kırmızı, ödüller yeşil.
# (metin Türkçe ya da çevrilmiş İngilizce gelebilir: iki dilin anahtar kelimeleri de bakılır)
func show_toast(text: String) -> void:
	var kind := "bilgi"
	var k := text.to_lower()
	for w in ["açmadı", "meşgul", "kilitli", "yapamazsın", "izleyici", "kimse yok", "hata", "koptu", "önce ",
			"didn't answer", "busy", "locked", "can't", "spectator", "no one", "error", "disconnected", "lost connection", "first"]:
		if k.contains(w):
			kind = "hata"
	if k.begins_with("+") or k.contains("kazandın") or k.contains("geri döndün") or k.contains("you won") or k.contains("you're back"):
		kind = "basari"
	_toast_ver(text, kind)


func _toast_ver(text: String, kind: String) -> void:
	if is_instance_valid(_toast):
		_toast.queue_free()
	var y := 150.0 if (lobby_panel and lobby_panel.visible) else 84.0
	_toast = UI.toast(text, _toast_host, 2.8, kind, y)


# Oyuncu yuvarlakları (oyunda gizli; liste yine de tutulur).
func set_players(list: Array, my_id: int) -> void:
	for ch in avatars.get_children():
		ch.queue_free()
	for pl in list:
		var me := int(pl.id) == my_id
		var p := OU.avatar(str(pl.name), 52, UI.AMBER if me else Color(0, 0, 0, 0))
		p.tooltip_text = str(pl.name)
		p.set_meta("id", int(pl.id))
		avatars.add_child(p)


# Oyunda hattı düşenlerin yuvarlağı solar.
func set_alive(alive: Array) -> void:
	for p in avatars.get_children():
		var out := not (int(p.get_meta("id", 0)) in alive)
		p.modulate = Color(0.35, 0.35, 0.38, 0.6) if out else Color.WHITE


# ---------------------------------------------------------------- eylem düğmesi

# eylem metni -> ikon (kit/ikon_*)
func _action_icon_name(text: String, phone: bool) -> String:
	var k := text.to_lower()
	if phone:
		return "telefon"
	if k.contains("tahtayı oku") or k.contains("sigorta"):
		return "sigorta"
	if k.contains("tahta"):
		return "tahta"
	if k.contains("bilgisayar"):
		return "bilgisayar"
	if k.contains("otur") or k.contains("kalk"):
		return "sandalye"
	if k.contains("kapı"):
		return "kapi"
	return "el"


# Eylem düğmesi: "" gizler. phone: telefon eylemi (Ara / Cevapla yeşil, Kapat kırmızı). Her karede çağrılabilir.
func set_action(text: String, phone := false) -> void:
	if text == "":
		if action_btn.visible:
			action_btn.visible = false
			_action_text = ""
			if _action_shake:
				_action_shake.kill()
			action_btn.rotation = 0.0
		return
	var key := text + ("#tel" if phone else "")
	if key == _action_text and action_btn.visible:
		return
	var yeni := not action_btn.visible
	_action_text = key
	action_btn.visible = true
	_action_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # _buyuk zaten çevirdi
	_action_label.text = _buyuk(text)
	_action_icon.texture = UI.icon_texture(_action_icon_name(text, phone), 80)
	var renk := UI.AMBER
	if phone:
		renk = UI.KIRMIZI if text.to_lower().begins_with("kapat") else UI.YESIL
	_disk_renk(action_btn, renk)
	_action_halo.add_theme_stylebox_override("panel", _daire(Color(renk, 0.0), Color(renk, 0.95), 90.0, 0.0, 5))
	if _action_shake:
		_action_shake.kill()
	action_btn.pivot_offset = Vector2(79, 79)
	action_btn.rotation = 0.0
	if yeni:
		_pop(action_btn)
	if phone and text.to_lower().begins_with("cevap"):
		# çalan telefon: düğme titrer
		_action_shake = action_btn.create_tween().set_loops()
		for a in [0.1, -0.1, 0.08, -0.08, 0.05, 0.0]:
			_action_shake.tween_property(action_btn, "rotation", a, 0.05)
		_action_shake.tween_interval(0.5)


func set_timer(seconds: float) -> void:
	var s := int(ceil(seconds))
	timer_label.text = "%d:%02d" % [s / 60, s % 60]


# Oyun sayacı: son 15 saniyede kırmızı, her saniye nabız gibi atar ve tik sesi gelir.
func set_game_timer(seconds: float) -> void:
	set_timer(seconds)
	var s := int(ceil(seconds))
	var urgent := s <= 15 and s > 0
	if bool(timer_pill.get_meta("acil", false)) != urgent:
		timer_pill.set_meta("acil", urgent)
		timer_pill.add_theme_stylebox_override("panel", _timer_style(urgent))
		timer_label.add_theme_color_override("font_color", Color("#ffe0d8") if urgent else UI.METIN)
	if not urgent or s == _last_sec:
		if not urgent:
			timer_pill.scale = Vector2.ONE
			_last_sec = -1
		return
	_last_sec = s
	timer_pill.pivot_offset = timer_pill.size / 2.0
	var tw := timer_pill.create_tween()
	tw.tween_property(timer_pill, "scale", Vector2.ONE * (1.32 if s <= 5 else 1.16), 0.08)
	tw.tween_property(timer_pill, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not _tick:
		_tick = AudioStreamPlayer.new()
		_tick.stream = load("res://assets/ses/tik_ui.ogg")
		add_child(_tick)
	_tick.volume_db = 0.0 if s <= 5 else -8.0
	_tick.pitch_scale = 1.25 if s <= 5 else 1.0
	_tick.play()


# ---------------------------------------------------------------- telefon: rehber

func _build_contacts() -> void:
	contacts = Control.new()
	contacts.set_anchors_preset(Control.PRESET_FULL_RECT)
	contacts.mouse_filter = Control.MOUSE_FILTER_STOP
	contacts.visible = false
	var perde := ColorRect.new()
	perde.color = UI.PERDE
	perde.set_anchors_preset(Control.PRESET_FULL_RECT)
	perde.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_contacts_kapat())
	contacts.add_child(perde)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contacts.add_child(cc)
	var box := UI.panel(Vector2(900, 0), UI.B_L)
	box.name = "Kutu"
	cc.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UI.B_M)
	box.add_child(v)
	var ust := HBoxContainer.new()
	ust.add_theme_constant_override("separation", UI.B_S)
	v.add_child(ust)
	var h := UI.header("KİMİ ARAYACAKSIN?", UI.FS_ORTA + 2)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ust.add_child(h)
	var kapat := UI.icon_button("kapat", "ikincil", UI.DOKUNMA)
	kapat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kapat.pressed.connect(_contacts_kapat)
	ust.add_child(kapat)
	var govde := HBoxContainer.new()
	govde.add_theme_constant_override("separation", UI.B_L)
	v.add_child(govde)
	# sol: eski tip çevirmeli telefon, arkasında sıcak lamba ışığı
	var sol := Control.new()
	sol.custom_minimum_size = Vector2(220, 320)
	govde.add_child(sol)
	var isik := Panel.new()
	var ist := _daire(Color(UI.AMBER, 0.06), Color(UI.AMBER, 0.0), 100, 0.0)
	ist.shadow_color = Color(UI.AMBER, 0.14)
	ist.shadow_size = 60
	isik.add_theme_stylebox_override("panel", ist)
	isik.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(isik, Control.PRESET_TOP_LEFT, Vector2(20, 60), Vector2(180, 180))
	sol.add_child(isik)
	var tel := UI.icon("ahize", 210)
	tel.name = "Ahize"
	_place(tel, Control.PRESET_TOP_LEFT, Vector2(5, 40), Vector2(210, 210))
	sol.add_child(tel)
	# sağ: kişi kartları
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(610, 336)
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.touch_scroll(sc)
	govde.add_child(sc)
	var mc := MarginContainer.new()
	mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mc.add_theme_constant_override("margin_right", 6)
	mc.add_theme_constant_override("margin_top", 6)
	mc.add_theme_constant_override("margin_bottom", 6)
	sc.add_child(mc)
	contact_list = GridContainer.new()
	contact_list.columns = 2
	contact_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contact_list.add_theme_constant_override("h_separation", UI.B_S)
	contact_list.add_theme_constant_override("v_separation", UI.B_S)
	mc.add_child(contact_list)
	box.resized.connect(func() -> void: box.pivot_offset = box.size / 2.0)
	_root.add_child(contacts)


func _contacts_kapat() -> void:
	if not contacts.visible or contacts.has_meta("kapaniyor"):
		return
	contacts.set_meta("kapaniyor", true)
	var box: Control = contacts.find_child("Kutu", true, false)
	var tw := contacts.create_tween().set_parallel(true)
	tw.tween_property(contacts, "modulate:a", 0.0, 0.16)
	tw.tween_property(box, "scale", Vector2.ONE * 0.9, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func() -> void:
		contacts.visible = false
		contacts.remove_meta("kapaniyor"))


# "Deniz  (hücre 12)" -> ["Deniz", "HÜCRE 12"]
static func _kisi_ad(s: String) -> Array:
	var re := RegEx.create_from_string("^(.*?)\\s*\\(hücre (\\d+)\\)\\s*$")
	var m := re.search(s)
	if m:
		return [m.get_string(1), Dil.t("HÜCRE %s") % m.get_string(2)]
	return [s, ""]


func _contact_card(c: Dictionary) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(290, 100)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := UI.flat(Color(UI.YUZEY_2, 0.97), UI.CIZGI, UI.R_ORTA)
	st.set_border_width_all(2)
	st.border_width_bottom = 4
	st.shadow_size = 5
	var bas := st.duplicate() as StyleBoxFlat
	bas.border_color = UI.YESIL
	bas.bg_color = UI.YUZEY_2.lightened(0.07)
	for k in ["normal", "hover", "focus"]:
		b.add_theme_stylebox_override(k, st)
	b.add_theme_stylebox_override("pressed", bas)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = UI.B_M
	row.offset_right = -UI.B_M
	row.add_theme_constant_override("separation", UI.B_M)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var ad: Array = _kisi_ad(str(c.name))
	var av := OU.avatar(str(ad[0]), 64)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(av)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_theme_constant_override("separation", 0)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := UI.title(str(ad[0]), UI.FS_ORTA + 2, UI.METIN)
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(nm)
	var alt := HBoxContainer.new()
	alt.add_theme_constant_override("separation", UI.B_S)
	alt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if str(ad[1]) != "":
		alt.add_child(UI.label(str(ad[1]), UI.FS_KUCUK, UI.METIN_SOLUK))
	# telefonda olan kişi: küçük kırmızı "MEŞGUL" etiketi (mark_busy açar/kapatır)
	var ms := UI.title("MEŞGUL", UI.FS_KUCUK, UI.KIRMIZI)
	ms.name = "Mesgul"
	ms.visible = bool(c.get("mesgul", false))
	alt.add_child(ms)
	tv.add_child(alt)
	row.add_child(tv)
	# yeşil ahize düğmesi
	var ara := Panel.new()
	ara.custom_minimum_size = Vector2(66, 66)
	ara.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ara.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ara.add_theme_stylebox_override("panel", _daire(UI.YESIL.darkened(0.08), UI.YESIL.lightened(0.5), 33, 0.45, 3))
	var ic := UI.icon("telefon", 42)
	_place(ic, Control.PRESET_CENTER, Vector2(-21, -21), Vector2(42, 42))
	ara.add_child(ic)
	row.add_child(ara)
	b.button_down.connect(func() -> void:
		b.pivot_offset = b.size / 2.0
		b.create_tween().tween_property(b, "scale", Vector2.ONE * 0.96, 0.05)
		UI.tik())
	b.button_up.connect(func() -> void: b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.12))
	return b


func show_contacts(list: Array) -> void:
	_emote_ac(false)
	for ch in contact_list.get_children():
		ch.queue_free()
	contact_list.columns = 1 if list.size() <= 1 else 2
	var i := 0
	for c in list:
		var b := _contact_card(c)
		var id: int = c.id
		b.set_meta("id", id)
		b.pressed.connect(func() -> void:
			_contacts_kapat()
			contact_chosen.emit(id))
		contact_list.add_child(b)
		# kartlar sırayla belirir
		b.modulate.a = 0.0
		var tw := b.create_tween()
		tw.tween_interval(0.08 + i * 0.05)
		tw.tween_property(b, "modulate:a", 1.0, 0.18)
		i += 1
	contacts.visible = true
	contacts.remove_meta("kapaniyor")
	contacts.modulate.a = 0.0
	var box: Control = contacts.find_child("Kutu", true, false)
	box.scale = Vector2.ONE * 0.86
	var tw := contacts.create_tween().set_parallel(true)
	tw.tween_property(contacts, "modulate:a", 1.0, 0.16)
	tw.tween_property(box, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# ahize hafifçe sallanır
	var tel: Control = contacts.find_child("Ahize", true, false)
	if tel:
		tel.pivot_offset = Vector2(105, 170)
		var sw := tel.create_tween()
		for a in [0.07, -0.06, 0.04, -0.02, 0.0]:
			sw.tween_property(tel, "rotation", a, 0.07)


# ---------------------------------------------------------------- telefon: arama şeridi ve altyazı

func _build_phone_strip() -> void:
	# main.gd ring_label'ı yazar; görünmez bir kaynak olarak tutulur, şerit ondan okur
	var kaynak := Control.new()
	kaynak.visible = false
	add_child(kaynak)
	ring_label = Label.new()
	ring_label.visible = false
	kaynak.add_child(ring_label)

	_tel = CanvasLayer.new()
	_tel.layer = 30  # oyun panellerinin (tahta, sigorta kutusu) de üstünde
	add_child(_tel)
	_tel_kok = Control.new()
	_tel_kok.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tel_kok.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tel.add_child(_tel_kok)

	_pill = PanelContainer.new()
	_pill_style = UI.flat(Color(0.035, 0.045, 0.045, 0.96), UI.AMBER, 36, Color(UI.AMBER, 0.3))
	_pill_style.set_border_width_all(3)
	_pill_style.content_margin_left = 6
	_pill_style.content_margin_right = 4
	_pill_style.content_margin_top = 2
	_pill_style.content_margin_bottom = 2
	_pill.add_theme_stylebox_override("panel", _pill_style)
	_pill.visible = false
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UI.B_S)
	_pill.add_child(row)
	_pill_avatar_kutu = Control.new()
	_pill_avatar_kutu.custom_minimum_size = Vector2(58, 58)
	_pill_avatar_kutu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_pill_avatar_kutu)
	_pill_dalga = Dalga.new()
	_pill_dalga.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_pill_dalga, Control.PRESET_TOP_LEFT, Vector2(-31, -31), Vector2(120, 120))
	_pill_avatar_kutu.add_child(_pill_dalga)
	var tv := VBoxContainer.new()
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_theme_constant_override("separation", -2)
	row.add_child(tv)
	_pill_ad = UI.title("", 22, UI.METIN)
	_pill_ad.clip_text = true
	_pill_ad.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_pill_ad.custom_minimum_size.x = 150
	tv.add_child(_pill_ad)
	_pill_durum = UI.title("", UI.FS_KUCUK, UI.AMBER)
	tv.add_child(_pill_durum)
	_pill_sikayet = UI.icon_button("sikayet", "ikincil", UI.DOKUNMA)
	_pill_sikayet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pill_sikayet.pressed.connect(func() -> void:
		var n = get_parent().get("net") if get_parent() else null
		var oda := ""
		if n is Node:
			oda = str((n as Node).get("room_code"))
		var peer = get_parent().get("phone_peer") if get_parent() else 0
		open_report(_call_who, "", oda, _tel_kok, int(peer) if peer != null else 0))
	row.add_child(_pill_sikayet)
	_pill_kapat = UI.icon_button("telefon", "ikincil", UI.DOKUNMA)
	_pill_kapat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pill_kapat.pressed.connect(_kapat_basildi)
	row.add_child(_pill_kapat)
	_tel_kok.add_child(_pill)
	_place_kenar(_pill, Control.PRESET_TOP_RIGHT, Vector2(-14, 6), Vector2.ZERO)
	_pill.grow_horizontal = Control.GROW_DIRECTION_BEGIN


func _kapat_basildi() -> void:
	if hangup_pressed.get_connections().is_empty() and get_parent() and get_parent().has_method("_hang_up"):
		get_parent().call("_hang_up")
	else:
		hangup_pressed.emit()


func _build_subtitle() -> void:
	call_panel = PanelContainer.new()
	var st := UI.flat(Color(0.035, 0.045, 0.045, 0.92), Color(UI.AMBER, 0.9), UI.R_ORTA)
	st.set_border_width_all(1)
	st.border_width_left = 6
	st.content_margin_left = UI.B_M
	st.content_margin_right = UI.B_L
	st.content_margin_top = UI.B_S
	st.content_margin_bottom = UI.B_S
	call_panel.add_theme_stylebox_override("panel", st)
	call_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UI.B_M)
	call_panel.add_child(row)
	var av := Control.new()
	av.custom_minimum_size = Vector2(52, 52)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	av.name = "Av"
	row.add_child(av)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 0)
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	call_title = UI.title("", UI.FS_KUCUK, UI.AMBER)
	call_text = UI.label("", 22, UI.METIN)
	call_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	call_text.custom_minimum_size = Vector2(540, 0)
	cv.add_child(call_title)
	cv.add_child(call_text)
	row.add_child(cv)
	call_panel.visible = false
	_root.add_child(call_panel)
	_place(call_panel, Control.PRESET_CENTER_BOTTOM, Vector2(-330, -150), Vector2(660, 0))
	call_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _pill_kur(state: String, who: String) -> void:
	var degisti := state != _call_state or who != _call_who
	if who != _call_who:
		for ch in _pill_avatar_kutu.get_children():
			if ch != _pill_dalga:
				ch.queue_free()
		_pill_avatar_kutu.add_child(OU.avatar(who, 58))
	if state == "hatta" and _call_state != "hatta":
		_call_t = 0.0
	_call_state = state
	_call_who = who
	_pill_ad.text = who
	var renk := UI.YESIL if state == "hatta" else (UI.KIRMIZI if state == "mesgul" else UI.AMBER)
	_pill_style.border_color = renk
	_pill_style.shadow_color = Color(renk, 0.32)
	_pill_style.shadow_size = 18 if state == "mesgul" else 12
	_pill_dalga.renk = renk
	_pill_dalga.acik = state != "hatta" and state != "mesgul"
	_pill_dalga.queue_redraw()
	_pill_durum.add_theme_color_override("font_color", renk)
	# meşgulken durum yazısı büyük ve kırmızı ("MEŞGUL"), diğer durumlarda küçük
	_pill_durum.add_theme_font_size_override("font_size", 34 if state == "mesgul" else UI.FS_KUCUK)
	_pill_style.content_margin_right = 22 if state == "mesgul" else 4  # kapat düğmesi yok: yazı kenara yapışmasın
	_pill_kapat.visible = state != "caliyor" and state != "mesgul"
	_pill_sikayet.visible = state == "hatta" and _ana_bool("online")
	if state == "caliyor":
		_pill_durum.text = "SENİ ARIYOR"
	elif state == "mesgul":
		_pill_durum.text = "MEŞGUL"
	if not _pill.visible or _pill.has_meta("gizleniyor"):
		_pill.remove_meta("gizleniyor")
		_pill.visible = true
		_pill.modulate.a = 0.0
		var tw := _pill.create_tween().set_parallel(true)
		tw.tween_property(_pill, "modulate:a", 1.0, 0.18)
		tw.tween_property(_pill, "offset_top", 6.0, 0.32).from(-50.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_pill, "offset_bottom", 6.0, 0.32).from(-50.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif degisti:
		_pill.pivot_offset = _pill.size / 2.0
		var tw2 := _pill.create_tween()
		tw2.tween_property(_pill, "scale", Vector2.ONE * 1.06, 0.08)
		tw2.tween_property(_pill, "scale", Vector2.ONE, 0.18)


# Aranan kişi meşgul: şerit kırmızıya döner, büyük "MEŞGUL" yazısı görünür ve şerit sallanır.
# main.gd ~2 sn sonra hattı kapatır (hide_call), şerit de kapanır.
func show_busy(who: String) -> void:
	call_panel.visible = false
	_pill_kur("mesgul", who)
	_pill.pivot_offset = _pill.size / 2.0
	var tw := _pill.create_tween()
	for a in [-0.035, 0.03, -0.022, 0.014, -0.006, 0.0]:
		tw.tween_property(_pill, "rotation", a, 0.05)


# Rehberde telefonda olan kişilerin kartına küçük kırmızı "MEŞGUL" etiketi (sunucunun "hatlar" bilgisi).
func mark_busy(ids: Array) -> void:
	if not contact_list:
		return
	for b in contact_list.get_children():
		var etiket: Control = b.find_child("Mesgul", true, false)
		if etiket:
			etiket.visible = ids.has(int(b.get_meta("id", -1)))


func _pill_gizle() -> void:
	_call_state = ""
	_call_who = ""
	_call_time_text = ""
	_pill_dalga.acik = false
	for ch in _pill_avatar_kutu.get_children():
		if ch != _pill_dalga:
			ch.queue_free()
	if _pill.visible:
		_pill.set_meta("gizleniyor", true)
		var tw := _pill.create_tween()
		tw.tween_property(_pill, "modulate:a", 0.0, 0.18)
		tw.tween_callback(func() -> void:
			if _pill.has_meta("gizleniyor"):
				_pill.remove_meta("gizleniyor")
				_pill.visible = false
				# geniş "MEŞGUL" yazısından sonra şerit eski genişliğine dönsün (sağa yaslı, sola doğru büyür)
				_pill.offset_left = _pill.offset_right)


# Gelen arama: main.gd ring_label'ı yazar ("Telefon çalıyor: Ali") ve görünür yapar; şerit bunu izler.
func _update_ring() -> void:
	var caliyor := ring_label.visible
	if caliyor and (_call_state == "" or _call_state == "caliyor"):
		var t := ring_label.text
		var who := t.get_slice(": ", 1) if t.contains(": ") else t
		if _call_state != "caliyor" or who != _call_who:
			_pill_kur("caliyor", who)
	elif not caliyor and _call_state == "caliyor":
		_pill_gizle()


# Arama ekranı. text: "Çalıyor…" (sen arıyorsun), "Bağlanıyor…", "Konuşuyorsunuz 0:23"
# ya da çevrimdışı konuşmada karşı tarafın söylediği cümle (altta altyazı olarak çıkar).
func show_call(who: String, text: String) -> void:
	var k := text.to_lower()
	if k.begins_with("çalıyor"):
		_pill_kur("ariyor", who)
		call_panel.visible = false
	elif k.begins_with("bağlanıyor"):
		_pill_kur("baglaniyor", who)
		call_panel.visible = false
	else:
		if _call_state != "hatta" or who != _call_who:
			_pill_kur("hatta", who)
		var m: RegExMatch = null
		if k.begins_with("konuşuyor"):
			m = RegEx.create_from_string("(\\d+:\\d\\d)").search(text)
		if m:
			_call_time_text = m.get_string(1)
			_pill_durum.text = tr("● HATTA  %s") % _call_time_text
			call_panel.visible = false
		else:
			_call_time_text = ""
			_subtitle(who, text)


func _subtitle(who: String, text: String) -> void:
	var s := text.strip_edges()
	if s == "" or s == "…":
		call_panel.visible = false
		return
	if call_text.text == text and call_panel.visible:
		return
	call_title.text = Dil.buyuk(who)
	call_text.text = text
	var av: Control = call_panel.find_child("Av", true, false)
	if str(av.get_meta("ad", "")) != who:
		for ch in av.get_children():
			ch.queue_free()
		av.add_child(OU.avatar(who, 52))
		av.set_meta("ad", who)
	call_panel.visible = true
	call_panel.modulate.a = 0.0
	call_panel.create_tween().tween_property(call_panel, "modulate:a", 1.0, 0.2)


func hide_call() -> void:
	call_panel.visible = false
	_pill_gizle()


# main.gd _set_call_bar buraya bağlanır: "" = şerit kapanır; "● Ali aranıyor…" / "● Hatta: Ali   0:23".
func set_call_bar(text: String) -> void:
	if text == "":
		hide_call()
		return
	var t := text.trim_prefix("●").strip_edges()
	if t.begins_with("Hatta:"):
		var rest := t.trim_prefix("Hatta:").strip_edges()
		var m := RegEx.create_from_string("^(.*?)\\s+(\\d+:\\d\\d)$").search(rest)
		if m:
			if _call_state != "hatta" or m.get_string(1) != _call_who:
				_pill_kur("hatta", m.get_string(1))
			_call_time_text = m.get_string(2)
			_pill_durum.text = tr("● HATTA  %s") % _call_time_text
		elif _call_state != "hatta":
			_pill_kur("hatta", rest)
	elif t.ends_with("aranıyor…") and _call_state == "":
		_pill_kur("ariyor", t.trim_suffix("aranıyor…").strip_edges())


# ---------------------------------------------------------------- şikayet

func _account() -> Node:
	var p := get_parent()
	if p == null:
		return null
	var a = p.get("account")
	return a if a is Node else null


# Oyuncuyu şikayet et penceresi (neden seçtirir). oyuncu_id > 0: maçtaki oyuncu, oda sunucusuna
# {"t":"sikayet","id":..} gider ve sunucu oda içi numarayı hesaba çevirir; değilse hesap sunucusuna.
func open_report(ad: String, handle := "", oda := "", host: Node = null, oyuncu_id := 0) -> void:
	OU.sikayet(host if host else _ust, _account(), ad, handle, oda, _oda_gonder(oyuncu_id))


# Oda bağlantısı üzerinden oyuncu numarasıyla gönderen işlev (numara yoksa boş Callable)
func _oda_gonder(oyuncu_id: int) -> Callable:
	if oyuncu_id <= 0:
		return Callable()
	var p := get_parent()
	var n = p.get("net") if p else null
	if not (n is Node):
		return Callable()
	var ag: Node = n
	return func(d: Dictionary) -> void:
		d["id"] = oyuncu_id
		ag.call("send", d)


# ---------------------------------------------------------------- bekleme salonu

func _build_lobby() -> void:
	lobby_panel = Control.new()
	lobby_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	lobby_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lobby_panel.visible = false
	_root.add_child(lobby_panel)
	_root.move_child(lobby_panel, _toast_host.get_index())

	# --- sol üst: oda kartı (kod, kopyala, çık, hazır sayısı, kurucu ayarları)
	_lobby_card = UI.panel(Vector2(380, 0), 34)
	lobby_panel.add_child(_lobby_card)
	_place_kenar(_lobby_card, Control.PRESET_TOP_LEFT, Vector2(96, 6), Vector2.ZERO)
	_tap_blockers.append(_lobby_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UI.B_S)
	_lobby_card.add_child(v)
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", UI.B_S)
	v.add_child(r1)
	var kv := VBoxContainer.new()
	kv.add_theme_constant_override("separation", -2)
	kv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r1.add_child(kv)
	kv.add_child(UI.label("ODA KODU", UI.FS_KUCUK, UI.METIN_SOLUK))
	_lobby_code = UI.title("----", 40, UI.AMBER)
	kv.add_child(_lobby_code)
	var kop := UI.icon_button("kopyala", "ikincil", UI.DOKUNMA)
	kop.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kop.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(_lobby_code_text)
		_toast_ver(tr("Oda kodu kopyalandı: %s") % _lobby_code_text, "basari"))
	r1.add_child(kop)
	var cik := UI.button("ÇIK", "tehlike", UI.BTN_H_KUCUK, UI.FS_ORTA, "", 92)
	cik.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cik.pressed.connect(func() -> void: lobby_leave.emit())
	r1.add_child(cik)
	# hazır sayısı
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", UI.B_XS)
	v.add_child(r2)
	var oi := UI.icon("onay", 30)
	oi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r2.add_child(oi)
	_lobby_ready_lbl = UI.title("", UI.FS_METIN, UI.METIN)
	_lobby_ready_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r2.add_child(_lobby_ready_lbl)
	# Hızlı Oyun geri sayımı
	var cd := VBoxContainer.new()
	cd.add_theme_constant_override("separation", 4)
	cd.visible = false
	v.add_child(cd)
	_lobby_count_row = cd
	var cr := HBoxContainer.new()
	cr.add_theme_constant_override("separation", UI.B_XS)
	cd.add_child(cr)
	_lobby_count_num = UI.title("25", UI.FS_BUYUK, UI.AMBER)
	cr.add_child(_lobby_count_num)
	var cl := UI.label("sn içinde başlıyor", UI.FS_METIN, UI.METIN)
	cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cr.add_child(cl)
	_lobby_count_bar = UI.progress(1.0, 320, 24)
	cd.add_child(_lobby_count_bar)
	# kurucu: oyun seçici + bot
	_lobby_host_box = VBoxContainer.new()
	_lobby_host_box.add_theme_constant_override("separation", UI.B_S)
	v.add_child(_lobby_host_box)
	_lobby_game_btn = UI.button(str(GAME_CHOICES[game_pick][1]), "ikincil", UI.BTN_H_KUCUK, UI.FS_METIN, "oyna")
	_lobby_game_btn.pressed.connect(_oyun_sec)
	_lobby_host_box.add_child(_lobby_game_btn)
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", UI.B_S)
	_lobby_host_box.add_child(br)
	var bi := UI.icon("bot", 46)
	bi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	br.add_child(bi)
	var bl := UI.title("BOT", UI.FS_ORTA, UI.METIN)
	bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	br.add_child(bl)
	_lobby_bot_minus = UI.button("-", "ikincil", UI.BTN_H_KUCUK, UI.FS_BUYUK, "", 64)
	_lobby_bot_minus.pressed.connect(func() -> void: lobby_bot.emit(false))
	br.add_child(_lobby_bot_minus)
	_lobby_bot_num = UI.title("0", UI.FS_BUYUK, UI.METIN, true)
	_lobby_bot_num.custom_minimum_size.x = 40
	_lobby_bot_num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	br.add_child(_lobby_bot_num)
	_lobby_bot_plus = UI.button("+", "ikincil", UI.BTN_H_KUCUK, UI.FS_BUYUK, "", 64)
	_lobby_bot_plus.pressed.connect(func() -> void: lobby_bot.emit(true))
	br.add_child(_lobby_bot_plus)

	# --- sağ üst: oyuncu kartları
	_lobby_strip = HBoxContainer.new()
	_lobby_strip.add_theme_constant_override("separation", 6)
	_lobby_strip.alignment = BoxContainer.ALIGNMENT_END
	lobby_panel.add_child(_lobby_strip)
	_place_kenar(_lobby_strip, Control.PRESET_TOP_RIGHT, Vector2(-14, 10), Vector2.ZERO)
	_lobby_strip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_tap_blockers.append(_lobby_strip)

	# --- alt orta: DAVET · HAZIRIM · BAŞLAT
	_lobby_bar = HBoxContainer.new()
	_lobby_bar.add_theme_constant_override("separation", UI.B_S)
	_lobby_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	lobby_panel.add_child(_lobby_bar)
	_place(_lobby_bar, Control.PRESET_CENTER_BOTTOM, Vector2(-14, -90), Vector2.ZERO)
	_lobby_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tap_blockers.append(_lobby_bar)
	_lobby_invite_btn = UI.button("DAVET", "ikincil", UI.BTN_H, UI.FS_ORTA, "davet", 166)
	_lobby_invite_btn.pressed.connect(func() -> void: lobby_invite.emit())
	_lobby_bar.add_child(_lobby_invite_btn)
	_lobby_ready_btn = UI.button("HAZIRIM", "ana", UI.BTN_H, UI.FS_ORTA, "onay", 200)
	_lobby_ready_btn.pressed.connect(func() -> void:
		_ready_on = not _ready_on
		_hazir_gorunum()
		lobby_ready.emit(_ready_on))
	_lobby_bar.add_child(_lobby_ready_btn)
	_lobby_start_btn = UI.button("BAŞLAT", "ana", UI.BTN_H, UI.FS_ORTA, "oyna", 206)
	_lobby_start_btn.pressed.connect(func() -> void: lobby_start.emit())
	_lobby_bar.add_child(_lobby_start_btn)


func _hazir_gorunum() -> void:
	if not _lobby_ready_btn:
		return
	UI.set_button_text(_lobby_ready_btn, "HAZIRSIN" if _ready_on else "HAZIRIM")
	# ekranda tek amber ana eylem: kurucuda BAŞLAT, misafirde HAZIRIM
	UI.set_button_kind(_lobby_ready_btn, "yesil" if _ready_on else ("ikincil" if _lobby_host else "ana"))


func _oyun_sec() -> void:
	var m := UI.modal("OYUN SEÇ", 720)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", UI.B_S)
	g.add_theme_constant_override("v_separation", UI.B_S)
	m.body.add_child(g)
	for i in GAME_CHOICES.size():
		var b := UI.button(str(GAME_CHOICES[i][1]), "ana" if i == game_pick else "ikincil", UI.BTN_H_KUCUK, UI.FS_METIN, "", 318)
		var k := i
		b.pressed.connect(func() -> void:
			game_pick = k
			UI.set_button_text(_lobby_game_btn, str(GAME_CHOICES[k][1]))
			m.close())
		g.add_child(b)
	_ust.add_child(m)


func show_lobby(on: bool) -> void:
	if not lobby_panel:
		_build_lobby()
	var acildi := on and not lobby_panel.visible
	lobby_panel.visible = on
	for p in _game_pills:
		p.visible = not on
	if on:
		if hint:
			hint.visible = false
	if acildi:
		# giriş: oda kartı soldan, oyuncular üstten, düğmeler alttan kayar
		_kay(_lobby_card, -440.0, 0.0)
		_kay(_lobby_strip, 0.0, -170.0)
		_kay(_lobby_bar, 0.0, 140.0)


# Hızlı Oyun odasında geri sayım: "25 sn içinde başlıyor"
func set_public_countdown(seconds: int) -> void:
	if float(seconds) > _public_left + 1.5:
		_public_total = maxf(1.0, float(seconds))
	_public_left = float(seconds)
	if not lobby_panel:
		_build_lobby()
	_lobby_count_row.visible = seconds >= 0
	_lobby_count_num.text = str(seconds)


func _player_card(p: Dictionary, me: bool, yeni: bool) -> Button:
	var hazir := bool(p.get("r", false))
	var bot := bool(p.get("bot", false))
	var ad := str(p.get("name", "?"))
	var handle := str(p.get("handle", ""))
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(88, 122)
	var st := UI.flat(Color(UI.YUZEY, 0.92), Color(UI.YESIL, 0.9) if hazir else UI.CIZGI, UI.R_ORTA)
	st.set_border_width_all(2)
	st.border_width_bottom = 5
	st.shadow_size = 6
	st.content_margin_left = 4
	st.content_margin_right = 4
	if me:
		st.border_color = UI.AMBER
		st.bg_color = Color(UI.YUZEY_2, 0.96)
	for k in ["normal", "hover", "focus", "pressed", "disabled"]:
		b.add_theme_stylebox_override(k, st)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_top = 12
	v.offset_bottom = -6
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var ak := Control.new()
	ak.custom_minimum_size = Vector2(62, 62)
	ak.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ak.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ak)
	var av := OU.avatar(ad, 62, UI.YESIL if hazir else Color(0, 0, 0, 0))
	if not hazir:
		av.modulate = Color(0.78, 0.78, 0.78)
	ak.add_child(av)
	if bool(p.get("host", false)):
		var cr := UI.icon("tac", 32)
		_place(cr, Control.PRESET_TOP_LEFT, Vector2(-14, -18), Vector2(32, 32))
		cr.pivot_offset = Vector2(16, 16)
		cr.rotation = -0.35
		ak.add_child(cr)
	if bot:
		var bi := UI.icon("bot", 30)
		_place(bi, Control.PRESET_TOP_LEFT, Vector2(42, -14), Vector2(30, 30))
		ak.add_child(bi)
	if hazir:
		var ok := UI.icon("onay", 32)
		_place(ok, Control.PRESET_TOP_LEFT, Vector2(40, 36), Vector2(32, 32))
		ak.add_child(ok)
	var nm := UI.title(ad, UI.FS_KUCUK, UI.METIN if hazir or me else UI.METIN_SOLUK, true)
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.custom_minimum_size.x = 80
	v.add_child(nm)
	if not me and not bot:
		# kart menüsü: dokun ya da uzun bas -> ŞİKAYET ET (/ ENGELLE)
		var menu := func() -> void:
			var pid := int(p.get("id", 0))
			var items := [["ŞİKAYET ET", "sikayet", "tehlike", func() -> void: open_report(ad, handle, _lobby_code_text, null, pid)]]
			# maçtaki oyuncu oda içi numarasıyla engellenir (misafir de olsa; sunucu hesaba çevirir)
			items.append(["ENGELLE", "engelle", "ikincil", func() -> void: OU.engelle(_ust, _account(), ad, handle, Callable(), _oda_gonder(pid))])
			OU.menu(_ust, b, items, 262)
		OU.uzun_bas(b, menu)
		b.pressed.connect(func() -> void:
			if not bool(b.get_meta("uzun", false)):
				menu.call())
	b.button_down.connect(func() -> void:
		b.pivot_offset = b.size / 2.0
		b.create_tween().tween_property(b, "scale", Vector2.ONE * 0.95, 0.05)
		UI.tik())
	b.button_up.connect(func() -> void: b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.12))
	if yeni:
		b.modulate.a = 0.0
		b.scale = Vector2.ONE * 0.7
		b.pivot_offset = Vector2(44, 61)
		var tw := b.create_tween().set_parallel(true)
		tw.tween_property(b, "modulate:a", 1.0, 0.2)
		tw.tween_property(b, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return b


func update_lobby(code: String, players: Array, my_id: int, is_host: bool) -> void:
	if not lobby_panel:
		_build_lobby()
	_lobby_host = is_host
	_lobby_code_text = code
	_lobby_code.text = code
	var ready_n := 0
	var bots := 0
	for p in players:
		if bool(p.get("r", false)):
			ready_n += 1
		if bool(p.get("bot", false)):
			bots += 1
		if int(p.get("id", 0)) == my_id:
			_ready_on = bool(p.get("r", false))
	_lobby_ready_lbl.text = tr("%d/%d HAZIR") % [ready_n, players.size()]
	_lobby_host_box.visible = is_host
	_lobby_bot_num.text = str(bots)
	_lobby_bot_minus.disabled = bots == 0
	_lobby_bot_plus.disabled = players.size() >= MAX_OYUNCU
	_lobby_start_btn.visible = is_host
	_hazir_gorunum()
	# oyuncu kartları (sen en solda); yeni gelen kart büyüyerek belirir
	for ch in _lobby_strip.get_children():
		_lobby_strip.remove_child(ch)
		ch.queue_free()
	var sirali := players.duplicate()
	sirali.sort_custom(func(a, b) -> bool:
		var am := int(a.get("id", 0)) == my_id
		var bm := int(b.get("id", 0)) == my_id
		if am != bm:
			return am
		return int(a.get("cell", 0)) < int(b.get("cell", 0)))
	var ids := []
	for p in sirali:
		var id := int(p.get("id", 0))
		ids.append(id)
		_lobby_strip.add_child(_player_card(p, id == my_id, not _lobby_ids.is_empty() and not (id in _lobby_ids)))
	_lobby_ids = ids


# ---------------------------------------------------------------- dokunma (joystick / bakış)

# Ortadaki küçük ölü bölge titremeyi keser; kenara yakın itince tam hız (koşma).
func _update_joy(pos: Vector2) -> void:
	var c := joy.get_global_rect().get_center()
	var raw := pos - c
	joy.active = true
	sprint = raw.y < -JOY_R * 1.95 and absf(raw.x) < 80.0
	joy.sprint = sprint
	var v := raw.limit_length(JOY_R)
	joy.knob = v
	if sprint:
		move = Vector2(0, -1)
		joy.queue_redraw()
		return
	var m := v.length() / JOY_R
	m = 0.0 if m < 0.12 else minf(1.0, (m - 0.12) / 0.8)
	move = v.normalized() * m if v.length() > 0.0 else Vector2.ZERO
	joy.queue_redraw()


func _over_button(pos: Vector2) -> bool:
	# açık pencere, menü ya da rehber varken joystick / bakış çalışmaz
	if contacts.visible or _ust.get_child_count() > 0 or _tel_kok.get_child_count() > 1:
		return true
	if _pill.visible and _pill.get_global_rect().grow(10).has_point(pos):
		return true
	for c in _tap_blockers:
		if c.is_visible_in_tree() and c.get_global_rect().grow(10).has_point(pos):
			return true
	return action_btn.visible and action_btn.get_global_rect().grow(10).has_point(pos)


# Joystick: ekranın sol yarısında parmağın değdiği yerde açılır (ayarlardan sabit yapılabilir).
func _joy_zone(pos: Vector2) -> bool:
	var vs := get_viewport().get_visible_rect().size
	if floating_joy:
		return pos.x < vs.x * 0.42 and pos.y > vs.y * 0.3 and not _over_button(pos)
	return joy.get_global_rect().grow(60).has_point(pos)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var vw := get_viewport().get_visible_rect().size.x
		if event.pressed:
			if joy_index == -1 and _joy_zone(event.position):
				joy_index = event.index
				if floating_joy:
					joy.global_position = event.position - joy.size / 2.0
				_update_joy(event.position)
			elif look_index == -1 and not _over_button(event.position) and event.position.x > vw * 0.3:
				look_index = event.index
		else:
			if event.index == joy_index:
				joy_index = -1
				joy.knob = Vector2.ZERO
				joy.active = false
				joy.sprint = false
				sprint = false
				move = Vector2.ZERO
				_place_kenar(joy, Control.PRESET_BOTTOM_LEFT, JOY_HOME, Vector2(240, 240))
				joy.queue_redraw()
			if event.index == look_index:
				look_index = -1
	elif event is InputEventScreenDrag:
		if event.index == joy_index:
			_update_joy(event.position)
		elif event.index == look_index and player:
			player.look(event.relative)
