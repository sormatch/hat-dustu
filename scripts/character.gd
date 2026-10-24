# Karakter ve mağaza ekranı: solda dönen 3D önizleme, sağda kategoriler ve seçenekler.
# Kilitli parçalar önizlenebilir, elmasla satın alınır; kaydederken sadece sahip olunanlar kalır.
extends CanvasLayer

signal closed(saved: bool)

const Catalog := preload("res://scripts/catalog.gd")
const BodyScript := preload("res://scripts/model_body.gd")
const UI := preload("res://scripts/ui.gd")
const ThumbsScript := preload("res://scripts/thumbs.gd")
const Fx := preload("res://scripts/store_fx.gd")
const CAT_ICONS := {"vitrin": "deal", "sandik": "chest", "ten": "skin", "sac": "hair", "sac_renk": "hair", "sakal": "beard", "kiyafet": "outfit", "aksesuar": "accessory", "sapka": "hat", "dovme": "tattoo", "hareket": "emote"}
const COLOR_CATS := ["ten", "sac_renk", "goz"]
const CATS := ["vitrin", "sandik", "ten", "sac", "sac_renk", "sakal", "sapka", "dovme", "kiyafet", "aksesuar", "hareket"]
# Sandıklar: [ad, fiyat, altın mı, nadirlik ağırlıkları SIRADAN/NADİR/EPİK/EFSANE]
const CHESTS := [["Tahta sandık", 100, false, [55, 35, 9, 1]], ["Altın sandık", 400, true, [0, 35, 45, 20]]]

var profile: Node
var _look: Dictionary
var _cat := "vitrin"
var _gems_shown := -1.0
var _countdown: Label
var _deal_price := -1  # vitrinden seçilen ürünün indirimli fiyatı
var _preview_item := ""  # hareket kategorisinde önizlenen
var _body: Node3D
var _turntable: Node3D
var _cam: Camera3D
var _close_up := true
var _name_edit: LineEdit
var _gems_label: Label
var _cat_row: HBoxContainer
var _grid: GridContainer
var _info: Label
var _buy_btn: Button
var _daily_btn: Button
var _pending := ["", ""]
var _thumbs: Node  # satın alınacak [kategori, kimlik]


class Gem extends Control:
	func _draw() -> void:
		var s := size
		var pts := PackedVector2Array([Vector2(s.x * 0.5, 0), Vector2(s.x, s.y * 0.38), Vector2(s.x * 0.5, s.y), Vector2(0, s.y * 0.38)])
		draw_colored_polygon(pts, Color("#3fd6f0"))
		draw_colored_polygon(PackedVector2Array([pts[0], pts[1], Vector2(s.x * 0.5, s.y * 0.38), pts[3]]), Color("#a8f2ff"))


static func gem_icon(px: float) -> Control:
	var g := Gem.new()
	g.custom_minimum_size = Vector2(px, px)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


static func styled_button(text: String, primary: bool, font := 22, h := 56.0) -> Button:
	return UI.button(text, "orange" if primary else "normal", int(h), font)


func _label(text: String, size: int, color := Color(0.95, 0.94, 0.92)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _ready() -> void:
	layer = 20
	_thumbs = ThumbsScript.new()
	add_child(_thumbs)
	_look = profile.look.duplicate()
	add_child(UI.background("bg_store", 0.5))

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	add_child(row)

	# --- 3D önizleme ---
	var stage := Control.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_stretch_ratio = 0.85
	row.add_child(stage)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(svc)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.msaa_3d = Viewport.MSAA_4X
	sv.transparent_bg = true
	svc.add_child(sv)
	_build_stage(sv)
	svc.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventScreenDrag:
			_turntable.rotation.y += e.relative.x * 0.012
		elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_turntable.rotation.y += e.relative.x * 0.012)
	var zoom := styled_button("Tüm boy", false, 20, 48)
	zoom.position = Vector2(16, 16)
	zoom.custom_minimum_size.x = 130
	zoom.pressed.connect(func() -> void:
		_close_up = not _close_up
		UI.set_button_text(zoom, "Tüm boy" if _close_up else "Yüz")
		_place_camera())
	stage.add_child(zoom)

	# --- sağ panel ---
	var side := MarginContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in ["left", "right", "top", "bottom"]:
		side.add_theme_constant_override("margin_" + m, 18)
	row.add_child(side)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	side.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	var title := UI.title("KARAKTER & MAĞAZA", 30, Color("#ffcf8a"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(UI.gem(38))
	_gems_label = UI.title("", 28, Color("#a8f2ff"))
	top.add_child(_gems_label)
	col.add_child(top)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_row.add_child(_label("Adın", 20, Color(0.7, 0.7, 0.74)))
	_name_edit = LineEdit.new()
	_name_edit.text = profile.player_name
	_name_edit.max_length = 16
	_name_edit.placeholder_text = "Adını yaz"
	_name_edit.custom_minimum_size = Vector2(0, 48)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.style_edit(_name_edit, 22)
	name_row.add_child(_name_edit)
	col.add_child(name_row)

	# sekmeler tek satırda, parmakla yana kaydırılır
	var tab_scroll := ScrollContainer.new()
	tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	tab_scroll.scroll_deadzone = 14
	tab_scroll.custom_minimum_size.y = 62
	col.add_child(tab_scroll)
	_cat_row = HBoxContainer.new()
	_cat_row.add_theme_constant_override("separation", 6)
	tab_scroll.add_child(_cat_row)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.touch_scroll(scroll)
	col.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_grid)

	var info_row := HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 8)
	_info = _label("", 20, Color(0.8, 0.8, 0.84))
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	info_row.add_child(_info)
	_buy_btn = styled_button("Satın al", true, 20, 48)
	_buy_btn.custom_minimum_size.x = 170
	_buy_btn.pressed.connect(_buy)
	info_row.add_child(_buy_btn)
	col.add_child(info_row)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	_daily_btn = UI.button("Günlük ödül  +%d" % profile.DAILY_GEMS, "normal", 56, 20, "gift")
	_daily_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_daily_btn.pressed.connect(func() -> void:
		if profile.claim_daily():
			_info.text = "Günlük ödül alındı: +%d elmas. Yarın yine gel!" % profile.DAILY_GEMS
		_refresh())
	bottom.add_child(_daily_btn)
	var cancel := styled_button("Vazgeç", false, 20)
	cancel.custom_minimum_size.x = 130
	cancel.pressed.connect(func() -> void:
		closed.emit(false)
		queue_free())
	bottom.add_child(cancel)
	var save := styled_button("Kaydet", true, 22)
	save.custom_minimum_size.x = 150
	save.pressed.connect(_save)
	bottom.add_child(save)
	col.add_child(bottom)

	_build_tabs()
	_refresh()


func _play(n: String, vol := 0.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = load("res://assets/ses/%s.ogg" % n)
	p.volume_db = vol
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _process(delta: float) -> void:
	# elmas sayacı yeni değere doğru sayarak gider
	var target := float(profile.gems)
	if _gems_shown < 0.0:
		_gems_shown = target
	if absf(_gems_shown - target) > 0.5:
		_gems_shown = move_toward(_gems_shown, target, maxf(absf(target - _gems_shown) * delta * 4.0, 60.0 * delta))
		_gems_label.text = str(int(round(_gems_shown)))
	if is_instance_valid(_countdown):
		var now := Time.get_time_dict_from_system()
		var left := 86400 - (int(now.hour) * 3600 + int(now.minute) * 60 + int(now.second))
		_countdown.text = "Yenilenmesine  %02d:%02d:%02d" % [left / 3600, (left / 60) % 60, left % 60]


func _build_tabs() -> void:
	for ch in _cat_row.get_children():
		ch.queue_free()
	for c in CATS:
		var b := UI.tab(Catalog.CATEGORY_NAMES[c], c == _cat, CAT_ICONS.get(c, ""))
		b.pressed.connect(func() -> void:
			_play("tik_ui", -6.0)
			_cat = c
			_preview_item = ""
			_info.text = ""
			_refresh())
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		_cat_row.add_child(b)


func _build_stage(sv: SubViewport) -> void:
	var root := Node3D.new()
	sv.add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.7)
	env.ambient_light_energy = 0.5
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
	rim.light_color = Color("#7fa8ff")
	rim.light_energy = 1.5
	rim.omni_range = 5.0
	root.add_child(rim)
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 0.9
	floor_mesh.bottom_radius = 0.9
	floor_mesh.height = 0.04
	var fl := MeshInstance3D.new()
	fl.mesh = floor_mesh
	fl.position.y = -0.02
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("#2a2d36")
	fl.material_override = fm
	root.add_child(fl)
	_turntable = Node3D.new()
	_turntable.rotation.y = 0.35
	root.add_child(_turntable)
	_body = BodyScript.new()
	_body.look = _look.duplicate()
	_turntable.add_child(_body)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	root.add_child(_cam)
	_place_camera()


# Dövme elde ise kamerayı ele, yüz/boyunda ise yüze çevirir (karakter de o yana döner).
func _focus_tattoo(id: String) -> void:
	var place := str(BodyScript.TATTOO_PLACE.get(id, ["yuz"])[0])
	if place == "el":
		_turntable.rotation.y = 0.9
		_cam.position = Vector3(-0.35, 1.25, -1.6)
		_cam.look_at_from_position(_cam.position, Vector3(-0.15, 0.95, 0))
	elif place == "kafa":
		_turntable.rotation.y = 1.15
		_place_camera()
	else:
		_turntable.rotation.y = 0.2
		_place_camera()


func _place_camera() -> void:
	if _close_up:
		_cam.position = Vector3(0, 1.58, -1.7)
		_cam.look_at_from_position(_cam.position, Vector3(0, 1.5, 0))
	else:
		_cam.position = Vector3(0, 1.1, -3.4)
		_cam.look_at_from_position(_cam.position, Vector3(0, 0.92, 0))


func _refresh() -> void:
	if _gems_shown < 0.0:
		_gems_label.text = str(profile.gems)
	_daily_btn.disabled = not profile.daily_available()
	UI.set_button_text(_daily_btn, ("Günlük ödül  +%d" % profile.DAILY_GEMS) if profile.daily_available() else "Ödül alındı (yarın gel)")
	_build_tabs()
	for ch in _grid.get_children():
		ch.queue_free()
	_buy_btn.visible = false
	if is_instance_valid(_countdown) and _cat != "vitrin":
		_countdown.queue_free()
		_countdown = null
	if _cat == "vitrin":
		_fill_vitrin()
	elif _cat == "sandik":
		_fill_chests()
	elif _cat in COLOR_CATS:
		_fill_colors()
	else:
		_fill_items()
	if _info.text == "":
		_info.text = "Parçaya dokun, önizle. Kilitli olanları elmasla satın alabilirsin."


func _fill_colors() -> void:
	var colors: Array = {"ten": Catalog.SKIN, "sac_renk": Catalog.HAIR_COLORS, "goz": Catalog.EYE_COLORS}[_cat]
	_grid.columns = 4
	for i in colors.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 64)
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var st := StyleBoxFlat.new()
		st.bg_color = Color(colors[i])
		st.set_corner_radius_all(14)
		var sel := int(_look[_cat]) == i
		st.border_color = Color.WHITE if sel else Color(0, 0, 0, 0.4)
		st.set_border_width_all(4 if sel else 2)
		for k in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(k, st)
		b.pressed.connect(func() -> void:
			_look[_cat] = i
			_info.text = ""
			_apply())
		_grid.add_child(b)
	_close_up = true
	_place_camera()


func _fill_items() -> void:
	_grid.columns = 3
	for it in Catalog.ITEMS[_cat]:
		var id: String = it[0]
		var owned: bool = profile.owns(_cat, id)
		var selected: bool = (_preview_item == id) if _cat == "hareket" else (_look[_cat] == id)
		_grid.add_child(_item_card(it[1], it[2], owned, selected, _pick.bind(id), id))
	_close_up = _cat in ["sac", "kas", "sakal", "aksesuar", "sapka", "dovme"]
	_place_camera()
	if _cat == "dovme":
		_focus_tattoo(str(_look.dovme))


const RARITY := Catalog.RARITY

# Vitrin: günün 4 fırsatı (eski fiyat üstü çizili, indirim rozeti) ve gece yarısına geri sayım.
func _fill_vitrin() -> void:
	_grid.columns = 2
	var date := Time.get_date_string_from_system()
	for d in Catalog.daily_deals(date):
		var cat: String = d[0]
		var id: String = d[1]
		var owned: bool = profile.owns(cat, id)
		var card := _item_card(d[2], d[5], owned, _pending == [cat, id], _pick_deal.bind(d), id, cat)
		card.custom_minimum_size.y = 236
		var badge := PanelContainer.new()
		badge.add_theme_stylebox_override("panel", UI.flat(Color("#d0263a"), Color("#ffd0a0"), 10))
		badge.add_child(UI.title("-%%%d" % d[4], 18, Color.WHITE, true))
		badge.position = Vector2(14, 34)
		badge.rotation = -0.12
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(badge)
		if not owned:
			var old := UI.title(str(d[3]), 15, Color(0.75, 0.75, 0.8))
			var strike := ColorRect.new()
			strike.color = Color("#ff5a5a")
			strike.mouse_filter = Control.MOUSE_FILTER_IGNORE
			old.add_child(strike)
			old.resized.connect(func() -> void:
				strike.position = Vector2(-2, old.size.y / 2.0)
				strike.size = Vector2(old.size.x + 4, 2))
			old.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			old.position = Vector2(-62, 36)
			old.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(old)
		_grid.add_child(card)
	if not is_instance_valid(_countdown):
		_countdown = UI.title("", 18, Color("#ffcf8a"))
		_info.get_parent().add_child(_countdown)
		_info.get_parent().move_child(_countdown, 0)
	if _info.text == "":
		_info.text = "Günün fırsatları her gece yenilenir. Dokun, önizle, indirimli al!"
	_close_up = true
	_place_camera()


func _pick_deal(d: Array) -> void:
	var cat: String = d[0]
	var id: String = d[1]
	_play("kumas", -4.0)
	if cat == "hareket":
		_body.play_emote(id)
	else:
		_look[cat] = id
		_body.set_look(_look)
	_pending = [cat, id]
	_deal_price = d[5]
	var nm: String = d[2]
	if profile.owns(cat, id):
		_info.text = nm + " — sende var."
		_buy_btn.visible = false
	elif profile.gems >= d[5]:
		_info.text = "%s: %d yerine %d elmas!" % [nm, d[3], d[5]]
		UI.set_button_text(_buy_btn, "Satın al (%d)" % d[5])
		_buy_btn.disabled = false
		_buy_btn.visible = true
	else:
		_info.text = "%s: %d elmas gerekiyor." % [nm, d[5]]
		UI.set_button_text(_buy_btn, "Elmas yetmiyor")
		_buy_btn.disabled = true
		_buy_btn.visible = true


# Sandık sekmesi: iki sandık, içinden ne çıkabileceği oranlarıyla.
func _fill_chests() -> void:
	_grid.columns = 2
	for ch in CHESTS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 330)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		var st := UI.sbox("card_legend" if ch[2] else "card_rare", 190, 0.2, Vector4(12, 12, 12, 12))
		if st == null:
			st = UI.flat(Color("#1d1a14"), Color("#ffb020"), 16)
		for k in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(k, st)
		var v := VBoxContainer.new()
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.offset_top = 18
		v.offset_bottom = -14
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(UI.title(str(ch[0]).to_upper(), 20, Color("#ffcf8a") if ch[2] else Color.WHITE, true))
		var chest := Fx.Chest.new()
		chest.gold = ch[2]
		chest.custom_minimum_size = Vector2(150, 120)
		chest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		chest.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(chest)
		# hafif sallanma: "aç beni"
		var tw := chest.create_tween().set_loops()
		tw.tween_property(chest, "rotation", 0.05, 0.9).set_trans(Tween.TRANS_SINE)
		tw.tween_property(chest, "rotation", -0.05, 0.9).set_trans(Tween.TRANS_SINE)
		chest.resized.connect(func() -> void: chest.pivot_offset = chest.size * Vector2(0.5, 1.0))
		var odds := HBoxContainer.new()
		odds.alignment = BoxContainer.ALIGNMENT_CENTER
		odds.add_theme_constant_override("separation", 10)
		odds.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for i in 4:
			if ch[3][i] > 0:
				var o := VBoxContainer.new()
				o.add_theme_constant_override("separation", -4)
				o.add_child(UI.title("%%%d" % ch[3][i], 16, Color(RARITY[i][2]).lightened(0.3), true))
				o.add_child(UI.label(str(RARITY[i][1]).capitalize(), 11, Color(0.8, 0.82, 0.9), true))
				odds.add_child(o)
		v.add_child(odds)
		var foot := HBoxContainer.new()
		foot.alignment = BoxContainer.ALIGNMENT_CENTER
		foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		foot.add_child(UI.gem(26))
		foot.add_child(UI.title(" %d" % ch[1], 22, Color("#a8f2ff")))
		v.add_child(foot)
		b.add_child(v)
		b.pressed.connect(_open_chest.bind(ch))
		_grid.add_child(b)
	if _info.text == "":
		_info.text = "Sandıktan rastgele bir parça çıkar. Hepsine sahipsen elmasının yarısı geri gelir."
	_close_up = false
	_place_camera()


# Ödül seçimi: önce nadirlik zarı, sonra o nadirlikte sahip olunmayan bir parça (yoksa en yakın nadirlik).
func _roll_chest(weights: Array) -> Array:
	var pool := []
	for it in Catalog.shop_items():
		if not profile.owns(it[0], it[1]):
			pool.append(it)
	if pool.is_empty():
		return []
	var roll := randi() % 100
	var tier := 0
	var acc := 0
	for i in 4:
		acc += int(weights[i])
		if roll < acc:
			tier = i
			break
	for step in [0, 1, -1, 2, -2, 3, -3]:
		var t := clampi(tier + step, 0, 3)
		var opts := pool.filter(func(it: Array) -> bool: return Catalog.rarity(it[3])[1] == RARITY[t][1])
		if not opts.is_empty():
			return opts[randi() % opts.size()]
	return pool[0]


func _open_chest(ch: Array) -> void:
	if profile.gems < ch[1]:
		_play("hata", -4.0)
		_info.text = "%s için %d elmas gerekiyor." % [ch[0], ch[1]]
		return
	profile.add_gems(-int(ch[1]))
	var won := _roll_chest(ch[3])
	# açılış sahnesi: sandık sallanır, kilit açılır, kapak kalkar, ışık taşar
	var ov := Control.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.01, 0.03, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.add_child(dim)
	var chest := Fx.Chest.new()
	chest.gold = ch[2]
	chest.size = Vector2(340, 280)
	ov.add_child(chest)
	add_child(ov)
	var vs := ov.get_viewport_rect().size
	chest.position = vs / 2.0 - chest.size / 2.0
	chest.pivot_offset = chest.size * Vector2(0.5, 1.0)
	_play("sandik_kilit")
	var tw := create_tween()
	for i in 6:
		tw.tween_property(chest, "rotation", 0.08 * (1 if i % 2 == 0 else -1) * (1.0 + i * 0.3), 0.07)
	tw.tween_property(chest, "rotation", 0.0, 0.06)
	tw.tween_callback(func() -> void: _play("sandik_gicirti"))
	tw.tween_method(func(t: float) -> void:
		chest.lid = t
		chest.glow = t
		chest.queue_redraw(), 0.0, 1.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.25)
	tw.tween_callback(func() -> void:
		ov.queue_free()
		_chest_reward(ch, won))


func _chest_reward(ch: Array, won: Array) -> void:
	if won.is_empty():
		profile.add_gems(int(ch[1]) / 2)
		_play("para")
		var gp := TextureRect.new()
		gp.texture = UI.texture("gem_pile", 512)
		gp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gp.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		Fx.reward_popup(self, "HEPSİ SENDE!", "+%d elmas geri" % (int(ch[1]) / 2), "", Color("#3fd6f0"), gp)
		return
	profile.grant(won[0], won[1])
	_play("odul")
	_play("parilti", -6.0)
	var tier: Array = Catalog.rarity(won[3])
	var pic := TextureRect.new()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_thumbs.request(profile.look, won[0], won[1], pic)
	Fx.reward_popup(self, "SANDIKTAN ÇIKTI!", won[2], tier[1], Color(tier[2]), pic)
	if won[0] == "hareket":
		_body.play_emote(won[1])
	else:
		_look[won[0]] = won[1]
		_body.set_look(_look)
	_info.text = "%s artık senin! Kaydet'e basınca üstünde kalır." % won[2]
	_refresh_selection()



# Mağaza kartı: nadirliğe göre renkli çerçeve ve şerit, fiyat ya da "SENDE" rozeti.
func _item_card(title: String, price: int, owned: bool, selected: bool, on_press: Callable, id := "", cat := "") -> Button:
	if cat == "":
		cat = _cat
	var tier: Array = Catalog.rarity(Catalog.price(cat, id) if id != "" else price)
	var card_tex: String = {"SIRADAN": "card_common", "NADİR": "card_rare", "EPİK": "card_epic", "EFSANE": "card_legend"}[tier[1]]
	var accent := Color(tier[2])
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 214)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	var st := UI.sbox(card_tex, 190, 0.2, Vector4(12, 12, 12, 12))
	if st == null:
		st = UI.flat(accent.darkened(0.78), accent, 16)
	for k in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(k, st)
	if selected:
		b.modulate = Color(1.25, 1.2, 1.1)
	b.pressed.connect(on_press)
	b.button_down.connect(func() -> void:
		b.pivot_offset = b.size / 2.0
		b.create_tween().tween_property(b, "scale", Vector2.ONE * 0.95, 0.06))
	b.button_up.connect(func() -> void: b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.1))
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_top = 14
	v.offset_bottom = -12
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.add_child(UI.title(tier[1], 13, accent.lightened(0.35), true))
	# o parçayı giymiş karakterin küçük resmi (3D modelden çekilir)
	var ic := TextureRect.new()
	ic.custom_minimum_size = Vector2(112, 112)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cat == "dovme" and id != "yok":
		# dövme resmi ten renginde yuvarlak bir zeminin üstünde
		var skin_bg := PanelContainer.new()
		skin_bg.add_theme_stylebox_override("panel", UI.flat(Color(Catalog.SKIN[int(_look.ten)]), Color(Catalog.SKIN[int(_look.ten)]).darkened(0.3), 56))
		skin_bg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		skin_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.custom_minimum_size = Vector2(104, 104)
		skin_bg.add_child(ic)
		v.add_child(skin_bg)
	else:
		v.add_child(ic)
	if id != "":
		if cat == "dovme" and id != "yok":
			ic.texture = BodyScript.ink_texture(id)
		else:
			_thumbs.request(profile.look, cat, id, ic)
	var nm := UI.title(title, 17, Color.WHITE, true)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(nm)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if selected:
		foot.add_child(UI.title("SEÇİLİ", 15, Color("#ffcf8a")))
	elif owned:
		foot.add_child(UI.title("SENDE ✓" if price > 0 else "ÜCRETSİZ", 15, Color("#5be37d")))
	else:
		foot.add_child(UI.gem(22))
		foot.add_child(UI.title(" %d" % price, 18, Color("#a8f2ff")))
	v.add_child(foot)
	b.add_child(v)
	return b


func _pick(id: String) -> void:
	_deal_price = -1
	_play("kumas", -4.0)
	if _cat == "hareket":
		_preview_item = id
		_body.play_emote(id)
	else:
		_look[_cat] = id
	_apply()
	if _cat == "dovme":
		_focus_tattoo(id)
	var owned: bool = profile.owns(_cat, id)
	var price := Catalog.price(_cat, id)
	var nm := Catalog.item_name(_cat, id)
	_pending = [_cat, id]
	if owned:
		_info.text = nm + (" — sende var, oyunda hareket menüsünde." if _cat == "hareket" else " — seçildi.")
	elif profile.gems >= price:
		_info.text = "%s kilitli: %d elmas." % [nm, price]
		UI.set_button_text(_buy_btn, "Satın al (%d)" % price)
		_buy_btn.disabled = false
		_buy_btn.visible = true
	else:
		_info.text = "%s: %d elmas gerekiyor, sende %d var. Oynadıkça ve günlük ödülle elmas kazanırsın." % [nm, price, profile.gems]
		UI.set_button_text(_buy_btn, "Elmas yetmiyor")
		_buy_btn.disabled = true
		_buy_btn.visible = true


func _buy() -> void:
	var cat: String = _pending[0]
	var id: String = _pending[1]
	if profile.buy(cat, id, _deal_price):
		_info.text = "%s satın alındı!" % Catalog.item_name(cat, id)
		_play("para")
		_play("odul", -4.0)
		var pic := TextureRect.new()
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_thumbs.request(profile.look, cat, id, pic)
		var tier: Array = Catalog.rarity(Catalog.price(cat, id))
		Fx.reward_popup(self, "SATIN ALINDI!", Catalog.item_name(cat, id), tier[1], Color(tier[2]), pic)
	else:
		_play("hata", -4.0)
	_refresh()


func _apply() -> void:
	if _cat != "hareket":
		_body.set_look(_look)
	_refresh_selection()


func _refresh_selection() -> void:
	var keep := _info.text
	_refresh()
	_info.text = keep


func _save() -> void:
	var reverted := []
	for c in ["sac", "kas", "sakal", "kiyafet", "aksesuar", "sapka", "dovme"]:
		if not profile.owns(c, _look[c]):
			reverted.append(Catalog.item_name(c, _look[c]))
			_look[c] = profile.look[c]
	var n := _name_edit.text.strip_edges()
	if n != "":
		profile.player_name = n
	profile.look = _look.duplicate()
	profile.save()
	if not reverted.is_empty():
		_info.text = "Satın alınmamış parçalar çıkarıldı: " + ", ".join(reverted)
		_body.set_look(_look)
		_refresh_selection()
		await get_tree().create_timer(1.6).timeout
	closed.emit(true)
	queue_free()
