# Envanter: oyuncunun sahip olduğu her şey (kasadan, mağazadan ya da baştan açık olanlar).
# Mağaza ekranıyla aynı düzen: solda çelik çerçeveli 3D vitrin, sağda kategori sekmeleri, nadirlik çerçeveli
# kartlar ve alt bilgi çubuğu. Karta dokununca parça hemen giyilir ve kaydedilir (profile.look);
# hareketler önizlemede oynatılır.
extends CanvasLayer

signal closed(changed: bool)
signal open_store

const Catalog := preload("res://scripts/catalog.gd")
const BodyScript := preload("res://scripts/model_body.gd")
const UI := preload("res://scripts/ui.gd")
const E := preload("res://scripts/ekran.gd")
const ThumbsScript := preload("res://scripts/thumbs.gd")
const CharacterScript := preload("res://scripts/character.gd")
const TABS := ["tumu", "govde", "sac", "sakal", "sapka", "dovme", "kiyafet", "aksesuar", "hareket"]
const ITEM_CATS := ["govde", "sac", "sakal", "sapka", "dovme", "kiyafet", "aksesuar", "hareket"]
const SLOTS := ["sac", "sapka", "sakal", "aksesuar", "dovme", "kiyafet"]
const HEAD_CATS := ["sac", "sakal", "sapka", "aksesuar", "dovme"]
const TAB_NAMES := {"tumu": "TÜMÜ", "govde": "KARAKTER", "sac": "SAÇ", "sakal": "SAKAL", "sapka": "ŞAPKA", "dovme": "DÖVME",
	"kiyafet": "KIYAFET", "aksesuar": "AKSESUAR", "hareket": "HAREKET"}

var profile: Node
var _look: Dictionary
var _thumb_look: Dictionary  # küçük resimler açılıştaki görünüşle çekilir (her giyişte yeniden çizilmesin)
var _cat := "tumu"
var _changed := false
var _thumbs: Node
var _body: Node3D
var _turntable: Node3D
var _cam: Camera3D
var _cam_pos := Vector3(0, 1.02, -3.6)
var _cam_aim := Vector3(0, 0.9, 0)
var _aim := Vector3(0, 0.9, 0)
var _idle_t := 10.0  # son sürükleme/odaklamadan beri geçen süre (uzunsa kendiliğinden döner)
var _kok: Control
var _tab_scroll: ScrollContainer
var _cat_row: HBoxContainer
var _scroll: ScrollContainer
var _grid: GridContainer
var _info_name: Label
var _info_sub: Label
var _coll: Control  # koleksiyon ilerlemesi (UI.progress)
var _gem_label: Label
var _gems_shown := -1.0
var _cards: Array = []  # [kategori, kimlik, kart düğmesi]


func _ready() -> void:
	layer = 20
	preload("res://scripts/telemetri.gd").ekran("envanter")
	_thumbs = ThumbsScript.new()
	add_child(_thumbs)
	_look = profile.look.duplicate()
	_thumb_look = _look.duplicate()
	var s := E.screen("ENVANTER", "envanter", "bg_store", 0.6)
	_kok = s.kok
	add_child(_kok)
	(s.geri as Button).pressed.connect(_close)
	var sag: HBoxContainer = s.bar_sag
	# koleksiyon: kaç parçanın sende olduğu
	var coll := HBoxContainer.new()
	coll.add_theme_constant_override("separation", UI.B_XS)
	coll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ci := UI.icon("basarim", 40)
	ci.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coll.add_child(ci)
	_coll = UI.progress(0.0, 210, 32, "")
	_coll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coll.add_child(_coll)
	sag.add_child(coll)
	var gw := CharacterScript.gem_widget(func() -> void: CharacterScript.open_gem_store(self))
	_gem_label = gw.get_meta("label")
	sag.add_child(gw)

	var govde: Control = s.govde
	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	mc.add_theme_constant_override("margin_left", UI.B_M)
	mc.add_theme_constant_override("margin_right", UI.B_M)
	mc.add_theme_constant_override("margin_top", UI.B_XS)
	mc.add_theme_constant_override("margin_bottom", UI.B_M)
	govde.add_child(mc)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UI.B_M)
	mc.add_child(row)
	row.add_child(_build_stage_panel())

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", UI.B_S)
	row.add_child(right)
	_tab_scroll = ScrollContainer.new()
	_tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_tab_scroll.scroll_deadzone = 14
	_tab_scroll.custom_minimum_size.y = UI.DOKUNMA + 4
	right.add_child(_tab_scroll)
	_cat_row = HBoxContainer.new()
	_cat_row.add_theme_constant_override("separation", 4)
	_tab_scroll.add_child(_cat_row)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.touch_scroll(_scroll)
	right.add_child(_scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + m, 6)
	_scroll.add_child(pad)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", UI.B_S)
	_grid.add_theme_constant_override("v_separation", UI.B_S)
	pad.add_child(_grid)
	_scroll.resized.connect(_layout_grid)
	right.add_child(_build_info_bar())

	_refresh()
	_set_info_default()
	E.intro(_kok, govde)


# Sol: çelik çerçeveli 3D vitrin (parmakla çevrilir, boşta kendiliğinden döner).
func _build_stage_panel() -> Control:
	var panel := UI.panel(Vector2.ZERO, 10)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = CharacterScript.STAGE_RATIO
	var st := Control.new()
	st.clip_contents = true
	panel.add_child(st)
	var gl := E.glow(UI.AMBER, 0.22)
	gl.set_anchors_preset(Control.PRESET_FULL_RECT)
	gl.offset_top = 40
	gl.offset_bottom = 60
	st.add_child(gl)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	st.add_child(svc)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.msaa_3d = Viewport.MSAA_4X if int(profile.settings.get("kalite", 1)) >= 1 else Viewport.MSAA_2X
	sv.transparent_bg = true
	svc.add_child(sv)
	_build_stage(sv)
	svc.gui_input.connect(func(e: InputEvent) -> void:
		var dx := 0.0
		if e is InputEventScreenDrag:
			dx = (e as InputEventScreenDrag).relative.x
		elif e is InputEventMouseMotion and ((e as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT):
			dx = (e as InputEventMouseMotion).relative.x
		if dx != 0.0:
			_turntable.rotation.y += dx * 0.012
			_idle_t = 0.0)
	return panel


# Alt bilgi çubuğu: seçilen parçanın adı ve durumu, mağaza düğmesi.
func _build_info_bar() -> Control:
	var bar := E.row_box(Color(0, 0, 0, 0), Vector4(UI.B_M, UI.B_XS, UI.B_XS, UI.B_XS))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.B_S)
	bar.add_child(h)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.add_theme_constant_override("separation", -2)
	_info_name = UI.title("", UI.FS_ORTA, UI.METIN)
	_info_name.clip_text = true
	_info_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(_info_name)
	_info_sub = UI.label("", UI.FS_KUCUK, UI.METIN_SOLUK)
	_info_sub.clip_text = true
	_info_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(_info_sub)
	h.add_child(tv)
	var shop := UI.button("MAĞAZA", "ikincil", UI.DOKUNMA, UI.FS_ORTA, "magaza", 220)
	shop.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	shop.pressed.connect(_go_store)
	h.add_child(shop)
	return bar


func _build_stage(sv: SubViewport) -> void:
	var root := Node3D.new()
	sv.add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.7)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-35), deg_to_rad(200), 0)
	key.light_energy = 1.3
	key.light_color = Color("#ffe2c0")
	root.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(1.2, 2.0, 1.5)
	rim.light_color = Color("#ffb34a")
	rim.light_energy = 1.4
	rim.omni_range = 5.0
	root.add_child(rim)
	# kaide: koyu metal disk ve amber halka (mağazayla aynı)
	var disk := CylinderMesh.new()
	disk.top_radius = 0.5
	disk.bottom_radius = 0.54
	disk.height = 0.06
	var fl := MeshInstance3D.new()
	fl.mesh = disk
	fl.position.y = -0.03
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("#22262a")
	fm.metallic = 0.5
	fm.roughness = 0.45
	fl.material_override = fm
	root.add_child(fl)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.495
	ring.outer_radius = 0.515
	var rg := MeshInstance3D.new()
	rg.mesh = ring
	rg.position.y = 0.005
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(UI.AMBER, 0.85)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rg.material_override = rm
	root.add_child(rg)
	_turntable = Node3D.new()
	_turntable.rotation.y = 0.35
	root.add_child(_turntable)
	_body = BodyScript.new()
	_body.look = _look.duplicate()
	_turntable.add_child(_body)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	root.add_child(_cam)
	_cam.position = _cam_pos
	_cam.look_at_from_position(_cam_pos, _aim)


func _process(delta: float) -> void:
	# elmas sayacı (sunucudan gelen yeni değere sayarak gider)
	var target := float(profile.gems)
	if _gems_shown < 0.0:
		_gems_shown = target
		_gem_label.text = E.sayi(int(target))
	if absf(_gems_shown - target) > 0.5:
		_gems_shown = move_toward(_gems_shown, target, maxf(absf(target - _gems_shown) * delta * 4.0, 60.0 * delta))
		_gem_label.text = E.sayi(int(round(_gems_shown)))
	if not _cam:
		return
	_idle_t += delta
	if _idle_t > 3.0:
		_turntable.rotation.y += delta * 0.35
	var k := minf(1.0, delta * 6.0)
	_cam.position = _cam.position.lerp(_cam_pos, k)
	_aim = _aim.lerp(_cam_aim, k)
	_cam.look_at(_aim)


# Kamera: kafa parçalarında yüze yakın, kıyafet ve hareketlerde tüm boy.
func _focus(cat: String) -> void:
	if cat in HEAD_CATS:
		_cam_pos = Vector3(0, 1.56, -1.75)
		_cam_aim = Vector3(0, 1.5, 0)
	else:
		_cam_pos = Vector3(0, 1.02, -3.6)
		_cam_aim = Vector3(0, 0.9, 0)


func _turn_to(angle: float, dur := 0.5) -> void:
	_idle_t = 0.0
	var from := _turntable.rotation.y
	var to := from + wrapf(angle - from, -PI, PI)
	create_tween().tween_property(_turntable, "rotation:y", to, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# Sahip olunanlar: [kategori, kimlik, ad, fiyat]. "Tümü" sadece kazanılan/satın alınanları gösterir.
func _owned(cat: String) -> Array:
	var out := []
	var cats: Array = ITEM_CATS if cat == "tumu" else [cat]
	for c in cats:
		for it in Catalog.ITEMS[c]:
			if cat == "tumu" and int(it[2]) == 0:
				continue
			if profile.owns(c, it[0]):
				out.append([c, it[0], it[1], it[2]])
	# önce "Yok", sonra en nadirden sıradana
	out.sort_custom(func(a: Array, b: Array) -> bool:
		if (a[1] == "yok") != (b[1] == "yok"):
			return a[1] == "yok"
		return int(a[3]) > int(b[3]))
	return out


func _paid_total() -> int:
	var n := 0
	for c in ITEM_CATS:
		for it in Catalog.ITEMS[c]:
			if int(it[2]) > 0:
				n += 1
	return n


func _refresh() -> void:
	var have := _owned("tumu").size()
	var total := _paid_total()
	_coll.set("text", "%d / %d" % [have, total])
	_coll.set("value", float(have) / maxf(1.0, float(total)))
	_build_tabs()
	_fill_grid()


# Sekmeler (mağazadakiyle aynı); adın yanında o kategorideki parça sayısı.
func _build_tabs() -> void:
	for ch in _cat_row.get_children():
		ch.queue_free()
	for c in TABS:
		var on: bool = c == _cat
		var b := UI.tab(str(TAB_NAMES[c]), on, "chest" if c == "tumu" else str(CharacterScript.CAT_ICONS.get(c, "")))
		b.custom_minimum_size.x += 22
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.pressed.connect(_select_tab.bind(c))
		_cat_row.add_child(b)
		var cnt := UI.title(str(_owned(c).size()), UI.FS_KUCUK, UI.AMBER if on else UI.METIN_SOLUK)
		cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if on:
			cnt.add_theme_color_override("font_color", Color.WHITE)
		(b.get_meta("label") as Label).get_parent().add_child(cnt)
		if on:
			_scroll_tab_into_view.call_deferred(b)


func _scroll_tab_into_view(b: Button) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(b) or not b.is_inside_tree():
		return
	var w := _tab_scroll.size.x
	var x0 := float(_tab_scroll.scroll_horizontal)
	if b.position.x < x0 or b.position.x + b.size.x > x0 + w:
		_tab_scroll.scroll_horizontal = int(maxf(0.0, b.position.x - (w - b.size.x) / 2.0))


func _select_tab(c: String) -> void:
	if c == _cat:
		return
	_cat = c
	_build_tabs()
	_fill_grid()
	_scroll.scroll_vertical = 0
	if c != "tumu":
		_focus(c)
	_set_info_default()


func _layout_grid() -> void:
	var w := _scroll.size.x - 12.0
	if w <= 0.0 or _cards.is_empty():
		return
	_grid.columns = clampi(int((w + UI.B_S) / (168.0 + UI.B_S)), 2, 8)


func _fill_grid() -> void:
	for ch in _grid.get_children():
		ch.queue_free()
	_cards.clear()
	var items := _owned(_cat)
	if items.is_empty():
		_grid.columns = 1
		_grid.add_child(_empty_state())
		return
	for it in items:
		_grid.add_child(_card(it))
	_layout_grid()
	_update_marks()
	E.stagger(_grid, 0.02)


func _empty_state() -> Control:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", UI.B_M)
	v.custom_minimum_size.y = maxf(360.0, _scroll.size.y - 20.0)
	var ic := UI.icon("kasa", UI.IKON_DEV)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	v.add_child(UI.title("BURASI BOŞ", UI.FS_BUYUK, UI.METIN, true))
	var go := UI.button("KASA AÇ", "ana", UI.BTN_H, UI.FS_ORTA + 2, "kasa", 280)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(_go_store)
	v.add_child(go)
	return v


# Envanter kartı (mağazayla aynı kart): giyiliyse amber ışık ve "GİYİLİ"; hareketlerde "OYNAT".
func _card(it: Array) -> Button:
	var tier: Array = Catalog.rarity(int(it[3]))
	var b := CharacterScript.item_card(str(it[0]), str(it[1]), str(it[2]), UI.rarity_key(str(tier[1])), _thumbs, _thumb_look, 224.0)
	var foot: HBoxContainer = b.get_meta("foot")
	var chip: Control
	if it[0] == "hareket":
		chip = E.pill("OYNAT", UI.MAVI, UI.FS_KUCUK)
	else:
		chip = E.pill("GİYİLİ", UI.AMBER, UI.FS_KUCUK)
	foot.add_child(chip)
	b.set_meta("chip", chip)
	b.pressed.connect(_equip.bind(it, b))
	_cards.append([it[0], it[1], b])
	return b


func _update_marks() -> void:
	for c in _cards:
		var cat: String = c[0]
		var on: bool = cat != "hareket" and str(_look.get(cat, "")) == str(c[1])
		var b: Button = c[2]
		CharacterScript.set_card_selected(b, on)
		(b.get_meta("chip") as Control).visible = (on and str(c[1]) != "yok") or cat == "hareket"


# Dokunulan parçayı giyer (giyiliyse ve "Yok" seçeneği varsa çıkarır) ve hemen kaydeder.
func _equip(it: Array, b: Button) -> void:
	var cat: String = it[0]
	var id: String = it[1]
	var tier: Array = Catalog.rarity(int(it[3]))
	b.pivot_offset = b.size / 2.0
	var pop := b.create_tween()
	pop.tween_property(b, "scale", Vector2.ONE * 1.05, 0.08)
	pop.tween_property(b, "scale", Vector2.ONE, 0.12)
	if cat == "hareket":
		_focus("hareket")
		_turn_to(0.0)
		_body.play_emote(id)
		_show_info(str(it[2]), tier, "Hareket")
		return
	var took_off := false
	if str(_look.get(cat, "")) == id and id != "yok" and Catalog.price(cat, "yok") == 0 and _has_none(cat):
		id = "yok"
		took_off = true
	_look[cat] = id
	profile.look = _look.duplicate()
	profile.save()
	_changed = true
	_body.set_look(_look)
	_play("kumas", -4.0)
	_focus(cat)
	if cat == "kiyafet":
		# kıyafette karakter kendi etrafında bir tur döner
		_idle_t = 0.0
		var r := _turntable.rotation.y
		create_tween().tween_property(_turntable, "rotation:y", r + TAU, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	elif cat == "dovme" and id != "yok":
		var place := str(BodyScript.TATTOO_PLACE.get(id, ["yuz"])[0])
		_turn_to(0.9 if place == "el" else (1.15 if place == "kafa" else 0.2))
	else:
		_turn_to(0.35)
	var cn := tr(str(Catalog.CATEGORY_NAMES[cat]))
	_show_info(str(it[2]), tier, cn + (tr("  ·  çıkarıldı") if took_off else ""))
	_update_marks()


func _has_none(cat: String) -> bool:
	for it in Catalog.ITEMS[cat]:
		if it[0] == "yok":
			return true
	return false


func _show_info(nm: String, tier: Array, sub: String) -> void:
	var rk := UI.rarity_key(str(tier[1]))
	_info_name.text = nm
	_info_name.add_theme_color_override("font_color", UI.rarity_color(rk).lightened(0.2))
	_info_sub.text = "%s  ·  %s" % [tr(str(tier[1])), sub]


func _set_info_default() -> void:
	_info_name.text = str(TAB_NAMES[_cat])
	_info_name.add_theme_color_override("font_color", UI.METIN)
	_info_sub.text = tr("%d parça") % _owned(_cat).size()


func _play(n: String, vol := 0.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = load("res://assets/ses/%s.ogg" % n)
	p.volume_db = vol
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _go_store() -> void:
	_close()
	open_store.emit()


func _close() -> void:
	if not is_instance_valid(_kok):
		return
	var k := _kok
	_kok = null
	closed.emit(_changed)
	E.outro(k, queue_free)
