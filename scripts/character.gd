# Karakter ve mağaza ekranı: solda dönen 3D önizleme, sağda kategoriler ve seçenekler.
# Kilitli parçalar önizlenebilir, elmasla satın alınır; kaydederken sadece sahip olunanlar kalır.
extends CanvasLayer

signal closed(saved: bool)

const Catalog := preload("res://scripts/catalog.gd")
const BodyScript := preload("res://scripts/model_body.gd")
const COLOR_CATS := ["ten", "sac_renk", "goz"]
const CATS := ["ten", "sac", "sac_renk", "goz", "kas", "sakal", "kiyafet", "aksesuar", "hareket"]

var profile: Node
var _look: Dictionary
var _cat := "sac"
var _preview_item := ""  # hareket kategorisinde önizlenen
var _body: Node3D
var _turntable: Node3D
var _cam: Camera3D
var _close_up := true
var _name_edit: LineEdit
var _gems_label: Label
var _cat_row: HFlowContainer
var _grid: GridContainer
var _info: Label
var _buy_btn: Button
var _daily_btn: Button
var _pending := ["", ""]  # satın alınacak [kategori, kimlik]


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
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, h)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font)
	b.clip_text = true
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#B3141B") if primary else Color(1, 1, 1, 0.07)
	st.border_color = Color("#FF5A52") if primary else Color(1, 1, 1, 0.3)
	st.set_border_width_all(2)
	st.set_corner_radius_all(14)
	st.content_margin_left = 10
	st.content_margin_right = 10
	for k in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(k, st)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.4))
	return b


func _label(text: String, size: int, color := Color(0.95, 0.94, 0.92)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _ready() -> void:
	layer = 20
	_look = profile.look.duplicate()
	var bg := ColorRect.new()
	bg.color = Color("#101115")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

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
		zoom.text = "Tüm boy" if _close_up else "Yüz"
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
	var title := _label("Karakterim & Mağaza", 28, Color("#FF4B3E"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(gem_icon(26))
	_gems_label = _label("", 26, Color("#a8f2ff"))
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
	_name_edit.add_theme_font_size_override("font_size", 22)
	name_row.add_child(_name_edit)
	col.add_child(name_row)

	_cat_row = HFlowContainer.new()
	_cat_row.add_theme_constant_override("h_separation", 6)
	_cat_row.add_theme_constant_override("v_separation", 6)
	col.add_child(_cat_row)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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
	_daily_btn = styled_button("Günlük ödül  +%d" % profile.DAILY_GEMS, false, 20)
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

	for c in CATS:
		var b := styled_button(Catalog.CATEGORY_NAMES[c], false, 19, 44)
		b.clip_text = false
		b.toggle_mode = true
		b.set_meta("cat", c)
		b.pressed.connect(func() -> void:
			_cat = c
			_preview_item = ""
			_refresh())
		_cat_row.add_child(b)
	_refresh()


func _build_stage(sv: SubViewport) -> void:
	var root := Node3D.new()
	sv.add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#1b1d24")
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


func _place_camera() -> void:
	if _close_up:
		_cam.position = Vector3(0, 1.58, -1.7)
		_cam.look_at_from_position(_cam.position, Vector3(0, 1.5, 0))
	else:
		_cam.position = Vector3(0, 1.1, -3.4)
		_cam.look_at_from_position(_cam.position, Vector3(0, 0.92, 0))


func _refresh() -> void:
	_gems_label.text = str(profile.gems)
	_daily_btn.disabled = not profile.daily_available()
	_daily_btn.text = ("Günlük ödül  +%d" % profile.DAILY_GEMS) if profile.daily_available() else "Ödül alındı (yarın gel)"
	for b in _cat_row.get_children():
		b.button_pressed = b.get_meta("cat") == _cat
	for ch in _grid.get_children():
		ch.queue_free()
	_buy_btn.visible = false
	if _cat in COLOR_CATS:
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
		var text: String = it[1]
		if not owned:
			text += "\n%d elmas" % it[2]
		var b := styled_button(text, selected, 18, 72)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = false
		b.autowrap_mode = TextServer.AUTOWRAP_WORD
		if not owned:
			b.add_theme_color_override("font_color", Color("#a8f2ff"))
		b.pressed.connect(_pick.bind(id))
		_grid.add_child(b)
	_close_up = _cat in ["sac", "kas", "sakal", "aksesuar"]
	_place_camera()


func _pick(id: String) -> void:
	if _cat == "hareket":
		_preview_item = id
		_body.play_emote(id)
	else:
		_look[_cat] = id
	_apply()
	var owned: bool = profile.owns(_cat, id)
	var price := Catalog.price(_cat, id)
	var nm := Catalog.item_name(_cat, id)
	_pending = [_cat, id]
	if owned:
		_info.text = nm + (" — sende var, oyunda hareket menüsünde." if _cat == "hareket" else " — seçildi.")
	elif profile.gems >= price:
		_info.text = "%s kilitli: %d elmas." % [nm, price]
		_buy_btn.text = "Satın al (%d)" % price
		_buy_btn.disabled = false
		_buy_btn.visible = true
	else:
		_info.text = "%s: %d elmas gerekiyor, sende %d var. Oynadıkça ve günlük ödülle elmas kazanırsın." % [nm, price, profile.gems]
		_buy_btn.text = "Elmas yetmiyor"
		_buy_btn.disabled = true
		_buy_btn.visible = true


func _buy() -> void:
	if profile.buy(_pending[0], _pending[1]):
		_info.text = "%s satın alındı!" % Catalog.item_name(_pending[0], _pending[1])
	_refresh()


func _apply() -> void:
	_body.set_look(_look)
	_refresh_selection()


func _refresh_selection() -> void:
	var keep := _info.text
	_refresh()
	_info.text = keep


func _save() -> void:
	var reverted := []
	for c in ["sac", "kas", "sakal", "kiyafet", "aksesuar"]:
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
