# Ana menü. Üstte seviye/XP, elmas (+ elmas mağazası) ve ayarlar; solda giydirilmiş karakterin (envanter kartı),
# sağda arkadaşların, ortada logo, büyük OYNA ve MAĞAZA / GÖREVLER / BAŞARIMLAR / LİDERLİK kutucukları.
# OYNA -> "Oyuna başla" alt ekranı: HIZLI OYUN / ARKADAŞLARINLA ODA KUR / KOD İLE KATIL / TEK BAŞINA DENE.
extends CanvasLayer

signal solo
signal open_character
signal open_settings
signal open_friends
signal open_inventory

const UI := preload("res://scripts/ui.gd")
const E := preload("res://scripts/ekran.gd")
const ModelScript := preload("res://scripts/model_body.gd")
const Catalog := preload("res://scripts/catalog.gd")
const GorevlerScript := preload("res://scripts/gorevler.gd")
const LiderlikScript := preload("res://scripts/liderlik.gd")
const Dil := preload("res://scripts/dil.gd")
const Giris := preload("res://scripts/giris.gd")  # topluluk kuralları onayı

const BAR_H := 80        # üst çubuk (içindeki düğmeler 64 px dokunma alanı)
const ORTA_W := 560.0    # orta sütun genişliği
const SOL_W := 290.0     # envanter kartı
const SAG_W := 312.0     # arkadaşlar paneli
const KENAR := 16.0

var net: Node
var profile: Node
var account: Node

var root: Control
var col: VBoxContainer
var logo: TextureRect
var main_box: VBoxContainer
var play_box: VBoxContainer
var code_edit: LineEdit
var status: Label
var quick_btn: Button
var daily_btn: Button
var gorev_tile: Button
var basarim_tile: Button
var _gorev_rozet: PanelContainer
var _basarim_rozet: PanelContainer
# üst çubuk
var gems_label: Label
var _lvl_shield: Control
var _lvl_label: Label
var _xp_bar: Control
# envanter kartı
var _name_label: Label
var _handle_label: Label
var _rarity_pill: PanelContainer
var _preview: Node3D
var _turn: Node3D
# arkadaşlar
var friends_list: VBoxContainer
var _online_label: Label
var _req_box: Control
var _req_badge: PanelContainer
var _toast: Control
var _box_now: Control
var _sol_kart: Control
var _sag_kart: Control


func _ready() -> void:
	layer = 10
	# arka plan: sisli koridor görseli, çok yavaş yaklaşır (sinematik)
	var bg := UI.background("bg_menu", 0.18)
	add_child(bg)
	if bg.get_child_count() > 1:
		var pic: Control = bg.get_child(0)
		pic.resized.connect(func() -> void: pic.pivot_offset = pic.size / 2.0)
		var zoom := pic.create_tween().set_loops()
		zoom.tween_property(pic, "scale", Vector2.ONE * 1.07, 18.0).set_trans(Tween.TRANS_SINE)
		zoom.tween_property(pic, "scale", Vector2.ONE, 18.0).set_trans(Tween.TRANS_SINE)
	add_child(E.vignette(0.1, 0.88))
	# arka plan opak: menü açıkken arkadaki 3D dünyayı çizme (telefonda pil ve ısı)
	visibility_changed.connect(_dunya_ciz)
	_dunya_ciz.call_deferred()

	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_center()
	_build_char_card()
	_build_friends_card()
	_build_top_bar()
	root.resized.connect(_yerlesim)
	_yerlesim()

	account.list_changed.connect(_refresh_friends)
	account.me_changed.connect(refresh_profile)
	account.economy_changed.connect(refresh_profile)
	account.invited.connect(_on_invited)
	account.reward.connect(_on_reward)
	net.welcomed.connect(func() -> void: account.set_room(net.room_code, net.in_game))
	# maç başladı: arkadaşlar "MAÇTA" görsün (davet gelmez, KATIL yerine İZLE)
	net.started.connect(func() -> void: account.set_room(net.room_code, true))
	# maç bitti (maç sonu ekranı): bu odada artık oynanmaz, "ANA MENÜYE DÖN" odadan çıkarır.
	# Arkadaşlar MAÇTA görmesin; katılabilecekleri bir oda da yok, durum "çevrimiçi"ye döner.
	net.game_over.connect(func(_d: Dictionary) -> void: account.set_room(""))
	# odaya bağlanılamadı ya da bağlantı koptu: arkadaşlar artık "odada" görmesin
	net.failed.connect(func(_m: String) -> void:
		if not net.connected:
			account.set_room(""))
	profile.changed.connect(refresh_profile)
	refresh_profile()
	_refresh_friends()
	_intro()
	if OS.get_cmdline_user_args().has("ad_duzenle=1"):
		get_tree().create_timer(1.0).timeout.connect(_edit_name)  # test pozu: ad penceresi
	for a in OS.get_cmdline_user_args():
		if a.begins_with("ad_dene="):
			# test pozu: ad penceresine yazıp KAYDET'e basar (sunucu reddederse "Bu ad kullanılamaz")
			var deneme := a.substr(8).uri_decode()
			get_tree().create_timer(2.5).timeout.connect(func() -> void:
				var m := _edit_name()
				var e: LineEdit = m.find_children("*", "LineEdit", true, false)[0]
				e.text = deneme
				e.text_submitted.emit(deneme))
		elif a == "kurallar=1":
			get_tree().create_timer(1.0).timeout.connect(func() -> void: Giris.kurallar_onayi(self, profile))  # test pozu


# ---------------------------------------------------------------------
# ÜST ÇUBUK: seviye + XP (solda), elmas + "+" (elmas mağazası) + ayarlar (sağda)
# ---------------------------------------------------------------------
func _build_top_bar() -> void:
	var bar := UI.top_bar(BAR_H)
	root.add_child(bar)
	var row: HBoxContainer = bar.get_meta("row")
	# seviye plakası (dokununca başarımlar)
	var lvl := Button.new()
	lvl.focus_mode = Control.FOCUS_NONE
	lvl.custom_minimum_size = Vector2(300, UI.DOKUNMA)
	lvl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bos := StyleBoxEmpty.new()
	for k in ["normal", "hover", "pressed", "focus"]:
		lvl.add_theme_stylebox_override(k, bos)
	var lh := HBoxContainer.new()
	lh.set_anchors_preset(Control.PRESET_FULL_RECT)
	lh.add_theme_constant_override("separation", 10)
	lh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lvl_shield = E.level_shield(1, 64)
	_lvl_shield.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lh.add_child(_lvl_shield)
	var lv := VBoxContainer.new()
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	lv.add_theme_constant_override("separation", 2)
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lvl_label = UI.title("SEVİYE 1", 20, UI.METIN)
	lv.add_child(_lvl_label)
	_xp_bar = UI.progress(0.0, 214, 26, "0/100")
	lv.add_child(_xp_bar)
	lh.add_child(lv)
	lvl.add_child(lh)
	lvl.pressed.connect(func() -> void: _open_gorevler(1))
	UI._basma_hissi(lvl, null)
	row.add_child(lvl)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp)
	# elmas sayacı + yanında yeşil "+" (elmas mağazası); sayaca dokunmak da mağazayı açar
	var gem_row := HBoxContainer.new()
	gem_row.add_theme_constant_override("separation", -10)
	gem_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(gem_row)
	var gem_btn := Button.new()
	gem_btn.focus_mode = Control.FOCUS_NONE
	gem_btn.custom_minimum_size = Vector2(180, UI.DOKUNMA)
	for k in ["normal", "hover", "pressed", "focus"]:
		gem_btn.add_theme_stylebox_override(k, bos)
	var gem := UI.counter("elmas", "0", 46)
	gem.set_anchors_preset(Control.PRESET_FULL_RECT)
	gem.offset_top = 6
	gem.offset_bottom = -6
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(gem.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_right = 22
	gems_label = gem.get_meta("label")
	gems_label.add_theme_color_override("font_color", UI.ELMAS)
	gems_label.add_theme_font_size_override("font_size", 26)
	gems_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gems_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gem_btn.add_child(gem)
	gem_btn.pressed.connect(_open_gem_store)
	UI._basma_hissi(gem_btn, null)
	gem_row.add_child(gem_btn)
	var plus := UI.button("+", "yesil", UI.DOKUNMA, 40, "", UI.DOKUNMA)
	plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	(plus.get_meta("row") as Control).offset_left = 0
	(plus.get_meta("row") as Control).offset_right = 0
	plus.pressed.connect(_open_gem_store)
	gem_row.add_child(plus)
	var gear := UI.icon_button("ayarlar", "ikincil", UI.DOKUNMA)
	gear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gear.pressed.connect(func() -> void: open_settings.emit())
	row.add_child(gear)


func _open_gem_store() -> void:
	var m = get_tree().current_scene
	if m and m.has_method("open_gem_store"):
		m.open_gem_store()
	else:
		open_character.emit()


# ---------------------------------------------------------------------
# ORTA SÜTUN: logo, OYNA, kutucuklar, günlük ödül  |  oyuna başla alt ekranı
# ---------------------------------------------------------------------
func _build_center() -> void:
	col = VBoxContainer.new()
	col.add_theme_constant_override("separation", UI.B_M)
	root.add_child(col)
	UI.place(col, Control.PRESET_CENTER_TOP, Vector2(-ORTA_W / 2.0, BAR_H - 2), Vector2(ORTA_W, 0))
	logo = TextureRect.new()
	logo.texture = UI.texture("logo", 460)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(ORTA_W, 226)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(logo)

	# --- ana kutu ---
	main_box = VBoxContainer.new()
	main_box.add_theme_constant_override("separation", UI.B_M)
	col.add_child(main_box)
	var oyna_kap := Control.new()
	oyna_kap.custom_minimum_size = Vector2(ORTA_W, 104)
	main_box.add_child(oyna_kap)
	var hale := E.glow(UI.AMBER, 0.42)
	hale.set_anchors_preset(Control.PRESET_FULL_RECT)
	hale.offset_left = -60
	hale.offset_right = 60
	hale.offset_top = -40
	hale.offset_bottom = 40
	oyna_kap.add_child(hale)
	var ht := hale.create_tween().set_loops()
	ht.tween_property(hale, "modulate:a", 0.45, 1.1).set_trans(Tween.TRANS_SINE)
	ht.tween_property(hale, "modulate:a", 1.0, 1.1).set_trans(Tween.TRANS_SINE)
	var play := UI.button("OYNA", "ana", 104, 50, "oyna", ORTA_W)
	play.set_anchors_preset(Control.PRESET_FULL_RECT)
	play.pressed.connect(func() -> void: _show(play_box))
	oyna_kap.add_child(play)

	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", UI.B_S)
	main_box.add_child(tiles)
	var tw := (ORTA_W - UI.B_S * 3) / 4.0
	var shop := E.tile("MAĞAZA", "magaza", tw, 118)
	shop.pressed.connect(func() -> void: open_character.emit())
	tiles.add_child(shop)
	gorev_tile = E.tile("GÖREVLER", "gorev", tw, 118)
	gorev_tile.pressed.connect(func() -> void: _open_gorevler(0))
	tiles.add_child(gorev_tile)
	_gorev_rozet = UI.badge_on(gorev_tile, 0, 30)
	basarim_tile = E.tile("BAŞARIMLAR", "basarim", tw, 118)
	basarim_tile.pressed.connect(func() -> void: _open_gorevler(1))
	tiles.add_child(basarim_tile)
	_basarim_rozet = UI.badge_on(basarim_tile, 0, 30)
	var lb := E.tile("LİDERLİK", "liderlik", tw, 118)
	lb.pressed.connect(_open_liderlik)
	tiles.add_child(lb)

	var dr := CenterContainer.new()
	main_box.add_child(dr)
	daily_btn = UI.button("GÜNLÜK ÖDÜL", "yesil", UI.BTN_H_KUCUK + 4, UI.FS_ORTA, "gift", 330)
	daily_btn.pressed.connect(_claim_daily)
	dr.add_child(daily_btn)
	UI.badge_on(daily_btn, 1, 30)
	E.pulse(daily_btn, 1.04, 0.6)

	# --- oyuna başla ---
	play_box = VBoxContainer.new()
	play_box.add_theme_constant_override("separation", UI.B_S)
	play_box.visible = false
	col.add_child(play_box)
	quick_btn = UI.button("HIZLI OYUN", "ana", UI.BTN_H_BUYUK, 40, "oyna", ORTA_W)
	quick_btn.pressed.connect(func() -> void:
		Giris.kurallar_sonra(self, profile, func() -> void:
			_set_status("Oyuncu aranıyor…", false)
			net.quick_match(_player_name())))
	play_box.add_child(quick_btn)
	var create := UI.button("ARKADAŞLARINLA ODA KUR", "ikincil", UI.BTN_H, 26, "arkadas", ORTA_W)
	create.pressed.connect(_on_create)
	play_box.add_child(create)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UI.B_S)
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "ODA KODU"
	code_edit.max_length = 4
	code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_edit.custom_minimum_size = Vector2(0, UI.BTN_H)
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.style_edit(code_edit, 30)
	code_edit.add_theme_font_override("font", UI.TITLE_FONT)
	code_edit.text_changed.connect(func(t: String) -> void:
		var up := t.to_upper()
		if up != t:
			code_edit.text = up
			code_edit.caret_column = up.length())
	code_edit.text_submitted.connect(func(t: String) -> void: _on_join(t))
	row.add_child(code_edit)
	var join := UI.button("KATIL", "ikincil", UI.BTN_H, 26, "davet", 200)
	join.pressed.connect(func() -> void: _on_join(code_edit.text))
	row.add_child(join)
	play_box.add_child(row)
	var alone := UI.button("TEK BAŞINA DENE", "ikincil", UI.BTN_H, 26, "telefon", ORTA_W)
	alone.pressed.connect(func() -> void: solo.emit())
	play_box.add_child(alone)
	var gr := CenterContainer.new()
	play_box.add_child(gr)
	var back := UI.button("GERİ", "ikincil", UI.BTN_H_KUCUK, UI.FS_ORTA, "geri", 230)
	back.pressed.connect(func() -> void: _show(main_box))
	gr.add_child(back)

	status = UI.title("", UI.FS_METIN, UI.METIN, true)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD
	status.add_theme_constant_override("outline_size", 5)
	col.add_child(status)
	_box_now = main_box


# ---------------------------------------------------------------------
# SOL: envanter kartı — isim plakası, büyük ışıklı dönen karakter, nadirlik rozeti, ENVANTER düğmesi
# ---------------------------------------------------------------------
func _build_char_card() -> void:
	var card := UI.panel(Vector2(SOL_W, 0), 22)
	_sol_kart = card
	root.add_child(card)
	card.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	card.offset_left = KENAR
	card.offset_right = KENAR + SOL_W
	card.offset_top = BAR_H + 10
	card.offset_bottom = -KENAR
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UI.B_S)
	card.add_child(v)
	# isim plakası: ad + @kullanıcı adı; dokununca ad değiştirilir
	var plate := Button.new()
	plate.focus_mode = Control.FOCUS_NONE
	plate.custom_minimum_size = Vector2(0, 66)
	var pst := StyleBoxFlat.new()
	pst.bg_color = Color(0.02, 0.025, 0.025, 0.82)
	pst.border_color = Color(UI.AMBER, 0.55)
	pst.set_border_width_all(2)
	pst.border_width_bottom = 4
	pst.set_corner_radius_all(UI.R_ORTA)
	for k in ["normal", "hover", "pressed", "focus"]:
		plate.add_theme_stylebox_override(k, pst)
	var ph := HBoxContainer.new()
	ph.set_anchors_preset(Control.PRESET_FULL_RECT)
	ph.offset_left = 14
	ph.offset_right = -10
	ph.add_theme_constant_override("separation", 8)
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pv := VBoxContainer.new()
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pv.add_theme_constant_override("separation", -2)
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label = UI.title("", UI.FS_ORTA, UI.METIN)
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pv.add_child(_name_label)
	_handle_label = UI.label("", UI.FS_KUCUK, UI.METIN_SOLUK)
	_handle_label.clip_text = true
	pv.add_child(_handle_label)
	ph.add_child(pv)
	var kalem := UI.label("✎", 26, Color(UI.AMBER, 0.85))
	kalem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.add_child(kalem)
	plate.add_child(ph)
	plate.pressed.connect(_edit_name)
	UI._basma_hissi(plate, null)
	v.add_child(plate)

	# sahne: arkada amber hale, dönen karakter, sağ üstte nadirlik
	var stage := Button.new()
	stage.focus_mode = Control.FOCUS_NONE
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var empty := StyleBoxEmpty.new()
	for k in ["normal", "hover", "pressed", "focus"]:
		stage.add_theme_stylebox_override(k, empty)
	stage.pressed.connect(func() -> void: open_inventory.emit())
	v.add_child(stage)
	var hale := E.glow(UI.AMBER, 0.55)
	hale.set_anchors_preset(Control.PRESET_FULL_RECT)
	hale.offset_left = -40
	hale.offset_right = 40
	stage.add_child(hale)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(svc)
	_build_preview(svc)
	_rarity_pill = E.pill("", UI.AMBER, 15)
	_rarity_pill.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_rarity_pill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_rarity_pill.offset_top = 4
	_rarity_pill.offset_right = -2
	stage.add_child(_rarity_pill)

	var inv := UI.button("ENVANTER", "ikincil", UI.BTN_H_KUCUK + 4, UI.FS_ORTA, "envanter")
	inv.pressed.connect(func() -> void: open_inventory.emit())
	v.add_child(inv)


func _build_preview(svc: SubViewportContainer) -> void:
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.transparent_bg = true
	sv.msaa_3d = Viewport.MSAA_4X
	svc.add_child(sv)
	var w := Node3D.new()
	sv.add_child(w)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	w.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.55, 2.7, 0)
	key.light_energy = 1.3
	key.light_color = Color("#fff1d8")
	w.add_child(key)
	# sıcak tepe ışığı (lamba altında duruyormuş gibi)
	var spot := SpotLight3D.new()
	spot.position = Vector3(0, 3.2, -0.6)
	spot.rotation = Vector3(-PI / 2 + 0.2, 0, 0)
	spot.light_color = Color("#ffb64a")
	spot.light_energy = 3.0
	spot.spot_range = 5.0
	spot.spot_angle = 38.0
	w.add_child(spot)
	var rim := OmniLight3D.new()
	rim.position = Vector3(0.9, 1.9, 1.2)
	rim.light_color = Color("#7fa8ff")
	rim.light_energy = 1.6
	rim.omni_range = 4.5
	w.add_child(rim)
	# ayak altı: koyu gölge diski + ince amber halka
	var sh := MeshInstance3D.new()
	var disk := CylinderMesh.new()
	disk.top_radius = 0.5
	disk.bottom_radius = 0.5
	disk.height = 0.01
	sh.mesh = disk
	var shm := StandardMaterial3D.new()
	shm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shm.albedo_color = Color(0, 0, 0, 0.35)
	sh.material_override = shm
	w.add_child(sh)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.44
	ring.outer_radius = 0.47
	var rg := MeshInstance3D.new()
	rg.mesh = ring
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color("#ffb020")
	rg.material_override = rm
	rg.scale = Vector3(1, 0.3, 1)
	w.add_child(rg)
	_turn = Node3D.new()
	w.add_child(_turn)
	_preview = ModelScript.new()
	_preview.look = profile.look.duplicate()
	_turn.add_child(_preview)
	var cam := Camera3D.new()
	cam.fov = 26
	w.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.1, -4.1), Vector3(0, 0.9, 0))


# ---------------------------------------------------------------------
# SAĞ: arkadaşlar paneli
# ---------------------------------------------------------------------
func _build_friends_card() -> void:
	var card := UI.panel(Vector2(SAG_W, 0), 20)
	_sag_kart = card
	root.add_child(card)
	card.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	card.offset_left = -KENAR - SAG_W
	card.offset_right = -KENAR
	card.offset_top = BAR_H + 10
	card.offset_bottom = -KENAR
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UI.B_S)
	card.add_child(v)
	# başlık: ikon + ARKADAŞLAR + çevrimiçi sayısı
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var hi := UI.icon("arkadas", 40)
	hi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hi)
	var ht := UI.title("ARKADAŞLAR", 22, UI.METIN)
	ht.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ht.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(ht)
	var on := PanelContainer.new()
	var ost := StyleBoxFlat.new()
	ost.bg_color = Color(0, 0, 0, 0.5)
	ost.border_color = Color(UI.YESIL, 0.6)
	ost.set_border_width_all(2)
	ost.set_corner_radius_all(20)
	ost.content_margin_left = 10
	ost.content_margin_right = 12
	on.add_theme_stylebox_override("panel", ost)
	on.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var oh := HBoxContainer.new()
	oh.add_theme_constant_override("separation", 6)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var dst := StyleBoxFlat.new()
	dst.bg_color = UI.YESIL
	dst.set_corner_radius_all(6)
	dst.shadow_color = Color(UI.YESIL, 0.6)
	dst.shadow_size = 4
	dot.add_theme_stylebox_override("panel", dst)
	oh.add_child(dot)
	_online_label = UI.title("0", 20, UI.YESIL)
	oh.add_child(_online_label)
	on.add_child(oh)
	head.add_child(on)
	v.add_child(head)
	# gelen istek bildirimi
	var req := Button.new()
	req.focus_mode = Control.FOCUS_NONE
	req.custom_minimum_size = Vector2(0, UI.DOKUNMA)
	var rst := StyleBoxFlat.new()
	rst.bg_color = Color(UI.AMBER, 0.14)
	rst.border_color = Color(UI.AMBER, 0.8)
	rst.set_border_width_all(2)
	rst.border_width_left = 6
	rst.set_corner_radius_all(UI.R_ORTA)
	for k in ["normal", "hover", "pressed", "focus"]:
		req.add_theme_stylebox_override(k, rst)
	var rh := HBoxContainer.new()
	rh.set_anchors_preset(Control.PRESET_FULL_RECT)
	rh.offset_left = 12
	rh.offset_right = -12
	rh.add_theme_constant_override("separation", 10)
	rh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ri := UI.icon("davet", 38)
	ri.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rh.add_child(ri)
	var rl := UI.title("YENİ İSTEK", 19, UI.AMBER)
	rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rh.add_child(rl)
	_req_badge = UI.badge(1, 30)
	_req_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rh.add_child(_req_badge)
	req.add_child(rh)
	req.pressed.connect(func() -> void: open_friends.emit())
	UI._basma_hissi(req, rh)
	_req_box = req
	v.add_child(req)
	# liste
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.touch_scroll(sc)
	v.add_child(sc)
	friends_list = VBoxContainer.new()
	friends_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	friends_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	friends_list.add_theme_constant_override("separation", UI.B_XS)
	sc.add_child(friends_list)
	var add := UI.button("ARKADAŞ EKLE", "ikincil", UI.BTN_H_KUCUK + 4, 22, "davet")
	add.pressed.connect(func() -> void: open_friends.emit())
	v.add_child(add)


func _refresh_friends() -> void:
	if not friends_list:
		return
	for ch in friends_list.get_children():
		ch.queue_free()
	_online_label.text = str(account.online_count())
	_req_box.visible = account.incoming.size() > 0
	UI.set_badge(_req_badge, account.incoming.size())
	if account.friends.is_empty():
		friends_list.add_child(_empty_friends())
		return
	var list: Array = account.friends.duplicate()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := (2 if str(a.get("room", "")) != "" else 0) + (1 if a.get("online", false) else 0)
		var rb := (2 if str(b.get("room", "")) != "" else 0) + (1 if b.get("online", false) else 0)
		if ra != rb:
			return ra > rb
		return str(a.get("name", "")) < str(b.get("name", "")))
	for f in list:
		friends_list.add_child(_friend_row(f))
	E.stagger(friends_list, 0.04)


func _friend_row(f: Dictionary) -> Control:
	var online: bool = f.get("online", false)
	var room := str(f.get("room", ""))
	var box := E.row_box(Color(0, 0, 0, 0), Vector4(10, 8, 8, 8))
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 10)
	box.add_child(r)
	var nm := str(f.get("name", ""))
	var hd := str(f.get("handle", ""))
	var durum := "kapali"
	if online:
		durum = "oda" if room != "" else "acik"
	var av := E.avatar(nm if nm != "" else hd, hd, 50, durum)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not online:
		av.modulate = Color(0.6, 0.6, 0.6, 0.9)
	r.add_child(av)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_theme_constant_override("separation", 0)
	var n := UI.title(nm if nm != "" else hd, 20, UI.METIN if online else UI.METIN_SOLUK)
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(n)
	var macta: bool = online and room != "" and bool(f.get("oyun", false))
	var sub := "Çevrimdışı"
	var sub_c := UI.METIN_SOLUK
	if macta:
		sub = "Maçta"
		sub_c = UI.KIRMIZI.lightened(0.3)
	elif online and room != "":
		sub = "Odada"
		sub_c = UI.AMBER
	elif online:
		sub = "Çevrimiçi"
		sub_c = UI.YESIL
	var s := UI.label(sub, UI.FS_KUCUK, sub_c)
	s.clip_text = true
	tv.add_child(s)
	r.add_child(tv)
	if online and room != "":
		# maçtaki arkadaşın odasına izleyici olarak girilir (maç bitince birlikte oynanır)
		var join := UI.button("İZLE" if macta else "KATIL", "ikincil" if macta else "yesil", UI.DOKUNMA, 18, "", 100)
		join.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		(join.get_meta("row") as Control).offset_left = 10
		(join.get_meta("row") as Control).offset_right = -10
		join.pressed.connect(func() -> void: _on_join(room))
		r.add_child(join)
	else:
		r.add_child(_spacer(0, UI.DOKUNMA))
	return box


func _empty_friends() -> Control:
	var v := VBoxContainer.new()
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", UI.B_S)
	var kap := Control.new()
	kap.custom_minimum_size = Vector2(0, 150)
	kap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(kap)
	var hale := E.glow(UI.AMBER, 0.32)
	UI.place(hale, Control.PRESET_CENTER, Vector2(-110, -95), Vector2(220, 190))
	kap.add_child(hale)
	var ic := UI.icon("arkadas", UI.IKON_DEV)
	UI.place(ic, Control.PRESET_CENTER, Vector2(-60, -66), Vector2(120, 120))
	kap.add_child(ic)
	var t := UI.title("BİRLİKTE OYNA", UI.FS_ORTA, UI.METIN, true)
	v.add_child(t)
	var l := UI.label("Arkadaşlarını ekle, birlikte oynayın.", UI.FS_METIN - 2, UI.METIN_SOLUK, true)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	return v


func _spacer(w: float, h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


# Arkadaş daveti: üstten kayan kart (KATIL / kapat), 15 sn sonra kendiliğinden kapanır.
func _on_invited(handle: String, name: String, code: String) -> void:
	if not visible:
		# menü kapalı: maçtaysa rahatsız etme; bekleme salonundaysa kısa bilgi ver
		if net.connected and not net.in_game and code != net.room_code:
			UI.toast(tr("%s seni odasına çağırıyor (%s)") % [name, code], null, 3.0, "bilgi")
		return
	if _toast and is_instance_valid(_toast):
		_toast.queue_free()
	var kok := Control.new()
	kok.set_anchors_preset(Control.PRESET_CENTER_TOP)
	kok.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(kok)
	_toast = kok
	var card := E.row_box(UI.AMBER, Vector4(18, 12, 12, 12))
	var cst := card.get_theme_stylebox("panel") as StyleBoxFlat
	cst.bg_color = Color(0.04, 0.05, 0.05, 0.97)
	cst.shadow_size = 18
	cst.shadow_color = Color(0, 0, 0, 0.7)
	card.custom_minimum_size = Vector2(620, 0)
	card.position = Vector2(-310, BAR_H + 10)
	kok.add_child(card)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.B_S)
	card.add_child(h)
	var av := E.avatar(name, handle, 60, "oda")
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(av)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_theme_constant_override("separation", 0)
	tv.add_child(UI.title("ODA DAVETİ", 18, UI.AMBER))
	var l := UI.label(tr("%s seni odasına çağırıyor") % name, UI.FS_METIN, UI.METIN)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(l)
	h.add_child(tv)
	var ok := UI.button("KATIL", "yesil", UI.DOKUNMA, 22, "", 130)
	ok.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(func() -> void:
		_close_toast(kok)
		if not net.connected:
			_on_join(code))
	h.add_child(ok)
	var no := UI.icon_button("kapat", "ikincil", UI.DOKUNMA)
	no.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	no.pressed.connect(func() -> void: _close_toast(kok))
	h.add_child(no)
	card.modulate.a = 0.0
	var tw := card.create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(card, "position:y", card.position.y, 0.35).from(card.position.y - 40.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(15.0).timeout.connect(func() -> void: _close_toast(kok))


func _close_toast(kok: Control) -> void:
	if not is_instance_valid(kok) or kok.has_meta("kapaniyor"):
		return
	kok.set_meta("kapaniyor", true)
	var tw := kok.create_tween()
	tw.tween_property(kok, "modulate:a", 0.0, 0.18)
	tw.tween_callback(kok.queue_free)


func _dunya_ciz() -> void:
	if is_inside_tree():
		get_viewport().disable_3d = visible


func _exit_tree() -> void:
	get_viewport().disable_3d = false


func _process(delta: float) -> void:
	if _turn and visible:
		_turn.rotation.y += delta * 0.45


# Geniş telefonlarda (ör. 2400x1080 -> 1600x720) yan paneller biraz genişler, kenarlardan içeri alınır;
# orta sütun hep ortada kalır.
func _yerlesim() -> void:
	var fazla := maxf(0.0, root.size.x - 1280.0)
	var ek := minf(fazla * 0.2, 70.0)
	var kenar := KENAR + minf(fazla * 0.12, 40.0)
	_sol_kart.offset_left = kenar
	_sol_kart.offset_right = kenar + SOL_W + ek
	_sag_kart.offset_left = -kenar - SAG_W - ek
	_sag_kart.offset_right = -kenar


# ---------------------------------------------------------------------
# Geçişler
# ---------------------------------------------------------------------
func _intro() -> void:
	# yan paneller yandan, orta sütun ve üst çubuk soluklaşarak gelir
	var parcalar := root.get_children()
	for c in parcalar:
		(c as Control).modulate.a = 0.0
	await get_tree().process_frame
	for i in parcalar.size():
		var c: Control = parcalar[i]
		var tw := c.create_tween()
		tw.tween_interval(0.05 * i)
		tw.tween_property(c, "modulate:a", 1.0, 0.3)
		var dx := 0.0
		if c.anchor_left == 0.0 and c.anchor_right == 0.0:
			dx = -40.0
		elif c.anchor_left == 1.0:
			dx = 40.0
		if dx != 0.0:
			var x0 := c.position.x
			tw.parallel().tween_property(c, "position:x", x0, 0.4).from(x0 + dx).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	E.stagger(main_box, 0.07)


func _show(box: Control) -> void:
	status.text = ""
	if box == _box_now:
		return
	var eski := _box_now
	_box_now = box
	var kucuk := box == play_box
	eski.visible = false
	box.visible = true
	E.stagger(box, 0.05)
	var lt := logo.create_tween()
	lt.tween_property(logo, "custom_minimum_size:y", 150.0 if kucuk else 226.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------------
# Veri
# ---------------------------------------------------------------------
func _player_name() -> String:
	var n: String = profile.player_name
	if n == "":
		n = account.handle if account.handle != "" else tr("Mahkum%d") % (randi() % 90 + 10)
		profile.player_name = n
		profile.save()
	return n


func refresh_profile() -> void:
	if not gems_label:
		return
	var eco: Dictionary = account.eco
	gems_label.text = E.sayi(int(eco.get("elmas", profile.gems)))
	var sv := int(eco.get("seviye", 1))
	var ic := int(eco.get("xp_ic", 0))
	var ger := maxi(1, int(eco.get("xp_gerek", 100)))
	_lvl_label.text = tr("SEVİYE %d") % sv
	(_lvl_shield.get_meta("label") as Label).text = str(sv)
	_xp_bar.value = float(ic) / float(ger)
	_xp_bar.text = tr("%d / %d XP") % [ic, ger]
	var hazir: bool = bool(eco.get("gunluk_hazir", false)) and profile.daily_available()
	daily_btn.get_parent().visible = hazir
	# alınabilir görev / başarım sayıları
	var g := 0
	for m in eco.get("gorevler", []):
		if not bool(m.get("alindi", false)) and int(m.get("ilerleme", 0)) >= int(m.get("hedef", 1)):
			g += 1
	var b := 0
	for a in eco.get("basarimlar", []):
		if not bool(a.get("alindi", false)) and int(a.get("ilerleme", 0)) >= int(a.get("hedef", 1)):
			b += 1
	UI.set_badge(_gorev_rozet, g)
	UI.set_badge(_basarim_rozet, b)
	# isim plakası
	_name_label.text = _player_name()
	_handle_label.text = ("@" + account.handle) if account.handle != "" else "Misafir oyuncu"
	# giyili en nadir parça
	var en := -1
	for cat in ["sac", "sakal", "sapka", "dovme", "kiyafet", "aksesuar"]:
		var p := Catalog.price(cat, str(profile.look.get(cat, "")))
		if p > 0:
			en = maxi(en, _rarity_index(p))
	_rarity_pill.visible = en >= 1
	if en >= 1:
		var key: String = ["siradan", "nadir", "epik", "efsane"][en]
		var c := UI.rarity_color(key)
		var lab: Label = _rarity_pill.get_meta("label")
		lab.text = ["", "NADİR", "EPİK", "EFSANE"][en]
		lab.add_theme_color_override("font_color", c.lightened(0.15))
		var st := _rarity_pill.get_theme_stylebox("panel") as StyleBoxFlat
		st.border_color = c
		st.bg_color = Color(c.darkened(0.75), 0.92)
	if _preview:
		_preview.set_look(profile.look)


func _rarity_index(p: int) -> int:
	for i in Catalog.RARITY.size():
		if p <= int(Catalog.RARITY[i][0]):
			return i
	return 0


# Sunucudan ödül geldi (günlük ödül, görev, başarım): menüdeyken üstte yeşil bildirim
func _on_reward(d: Dictionary) -> void:
	if not visible or str(d.get("t", "")) == "mac_odul":
		return
	UI.toast(tr("+%d elmas  ·  %s") % [int(d.get("elmas", 0)), Dil.sunucu(d, "neden")], null, 2.4, "basari", BAR_H + 12.0)


func _claim_daily() -> void:
	if not profile.claim_daily():
		UI.toast("Bugünün ödülünü aldın, yarın gel!", null, 2.0, "bilgi")
		return
	var dr := daily_btn.get_parent() as Control
	var tw := dr.create_tween()
	tw.tween_property(dr, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func() -> void:
		dr.visible = false
		dr.modulate.a = 1.0)


func _edit_name() -> Control:
	var m := UI.modal("OYUNCU ADI", 560)
	var e := LineEdit.new()
	e.text = profile.player_name
	e.max_length = 16
	e.placeholder_text = "Adını yaz"
	e.alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.custom_minimum_size = Vector2(0, UI.BTN_H)
	UI.style_edit(e, 28)
	m.body.add_child(e)
	# sunucunun küfür süzgecinden dönerse: "Bu ad kullanılamaz" (server/src/suzgec.js)
	var red := UI.label("", UI.FS_METIN, UI.KIRMIZI.lightened(0.35), true)
	red.visible = false
	m.body.add_child(red)
	e.text_changed.connect(func(_t: String) -> void: red.visible = false)
	var ok := UI.button("KAYDET", "ana", UI.BTN_H, UI.FS_BUYUK - 4, "")
	var kaydet := func() -> void:
		var n := e.text.strip_edges()
		if n == "" or n == profile.player_name:
			m.close()
			return
		if ok.disabled:
			return
		ok.disabled = true
		account.ad_dene(n, func(uygun: bool) -> void:
			if not is_instance_valid(m) or not is_instance_valid(ok):
				return
			ok.disabled = false
			if not uygun:
				red.text = "Bu ad kullanılamaz"
				red.visible = true
				UI.tik()
				var tw := m.box.create_tween()
				for k in [10.0, -8.0, 5.0, 0.0]:
					tw.tween_property(m.box, "position:x", m.box.position.x + k, 0.05)
				return
			profile.player_name = n
			profile.save()
			account.change_name(n)  # arkadaşların da yeni adı görsün
			if _name_label:
				_name_label.text = n
			m.close())
	ok.pressed.connect(kaydet)
	e.text_submitted.connect(func(_t: String) -> void: kaydet.call())
	m.body.add_child(ok)
	add_child(m)
	_klavye_kaydir(m, e, ok)
	return m


# Telefonda klavye açılınca pencere yukarı kayar: yazı alanı ve KAYDET düğmesi klavyenin üstünde kalır.
# Test: -- klavye=<px> klavye açıkmış gibi davranır.
func _klavye_kaydir(m: Control, e: LineEdit, alt_dugme: Control) -> void:
	var test := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("klavye="):
			test = float(a.substr(7))
	if test > 0.0:
		e.grab_focus.call_deferred()
	var kutu: Control = m.get("box")
	var kaydir := [0.0]
	var adim := func() -> void:
		if not is_instance_valid(m) or not is_instance_valid(kutu) or not m.is_inside_tree():
			return
		var vis := m.get_viewport().get_visible_rect().size
		var kh := test
		if kh <= 0.0 and DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
			kh = float(DisplayServer.virtual_keyboard_get_height()) * vis.y / maxf(1.0, float(DisplayServer.window_get_size().y))
		var hedef := 0.0
		if kh > 0.0 and e.has_focus():
			var ust: float = e.get_global_rect().position.y + kaydir[0]
			var alt: float = maxf(e.get_global_rect().end.y, alt_dugme.get_global_rect().end.y) + kaydir[0] + UI.B_S
			hedef = clampf(alt - (vis.y - kh), 0.0, maxf(0.0, ust - UI.B_S))
		var yeni := lerpf(kaydir[0], hedef, 0.25) if absf(kaydir[0] - hedef) > 0.5 else hedef
		kaydir[0] = yeni
		# CenterContainer'ın ortaladığı yerden yukarı kaydır
		var orta := ((kutu.get_parent() as Control).size.y - kutu.size.y) / 2.0
		kutu.position.y = orta - yeni
	get_tree().process_frame.connect(adim)
	m.tree_exiting.connect(func() -> void:
		if get_tree().process_frame.is_connected(adim):
			get_tree().process_frame.disconnect(adim))


func _open_gorevler(tab: int) -> void:
	var g: CanvasLayer = GorevlerScript.new()
	g.account = account
	g.profile = profile
	g.tab = tab
	get_parent().add_child(g)


func _open_liderlik() -> void:
	var l: CanvasLayer = LiderlikScript.new()
	l.account = account
	l.profile = profile
	get_parent().add_child(l)


func _set_status(text: String, hata := true) -> void:
	status.text = text
	status.add_theme_color_override("font_color", UI.KIRMIZI.lightened(0.35) if hata else UI.METIN)


func _on_create() -> void:
	Giris.kurallar_sonra(self, profile, func() -> void:
		_set_status("Oda kuruluyor…", false)
		net.join(net.new_code(), _player_name(), true))


func _on_join(raw: String) -> void:
	var code := raw.strip_edges().to_upper()
	if code.length() != 4:
		if not play_box.visible:
			_show(play_box)
		_set_status("Oda kodu 4 harf olmalı.")
		return
	Giris.kurallar_sonra(self, profile, func() -> void:
		_set_status("Bağlanılıyor…", false)
		net.join(code, _player_name(), false))


func show_error(msg: String) -> void:
	if not play_box.visible:
		_show(play_box)
	_set_status(msg)
