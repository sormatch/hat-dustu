# Mağaza efektleri: dönen ışık huzmeleri, konfeti, çizimle sandık ve "kazandın / satın aldın" penceresi.
extends RefCounted

const UI := preload("res://scripts/ui.gd")


# Arkada yavaşça dönen ışık huzmeleri.
class Rays extends Control:
	var color := Color("#ffcf8a")
	var spin := 0.0

	func _process(delta: float) -> void:
		spin += delta * 0.6
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := maxf(size.x, size.y)
		for i in 14:
			var a := spin + TAU * i / 14.0
			var pts := PackedVector2Array([c, c + Vector2.from_angle(a - 0.09) * r, c + Vector2.from_angle(a + 0.09) * r])
			draw_colored_polygon(pts, Color(color, 0.16))
		for k in 6:
			draw_circle(c, r * 0.05 * (6 - k), Color(color, 0.07))


# Çizimle hapishane sandığı: gövde, metal şeritler, kilit; kapak açılınca içinden ışık taşar.
class Chest extends Control:
	var lid := 0.0  # 0 kapalı, 1 açık
	var glow := 0.0
	var gold := false

	# assets/ui/chest_wood.png, chest_wood_open.png, chest_gold.png, chest_gold_open.png varsa resim kullanılır
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var base := "chest_gold" if gold else "chest_wood"
		var closed_tex := UI.texture(base, int(h * 2))
		if closed_tex:
			var open_tex := UI.texture(base + "_open", int(h * 2))
			if glow > 0.0:
				for k in 8:
					draw_circle(Vector2(w / 2, h * 0.45), w * 0.09 * (8 - k) * glow, Color(1.0, 0.85, 0.45, 0.07 * glow))
			var t: Texture2D = open_tex if lid > 0.5 and open_tex else closed_tex
			var ts := t.get_size()
			var sc := minf(w / ts.x, h / ts.y)
			draw_texture_rect(t, Rect2(Vector2(w, h) / 2.0 - ts * sc / 2.0, ts * sc), false)
			return
		var wood := Color("#c9a227") if gold else Color("#7a4a26")
		var dark := wood.darkened(0.45)
		var band := Color("#e8d27a") if gold else Color("#8b929e")
		var body := Rect2(w * 0.08, h * 0.45, w * 0.84, h * 0.5)
		# içten taşan ışık
		if glow > 0.0:
			for k in 8:
				draw_circle(Vector2(w / 2, h * 0.45), w * 0.08 * (8 - k) * glow, Color(1.0, 0.85, 0.45, 0.06 * glow))
		draw_rect(body, wood)
		for i in 4:
			draw_line(Vector2(body.position.x, body.position.y + body.size.y * (i + 1) / 5.0), Vector2(body.end.x, body.position.y + body.size.y * (i + 1) / 5.0), dark, 2.0)
		for x in [0.18, 0.82]:
			draw_rect(Rect2(w * x - w * 0.04, body.position.y, w * 0.08, body.size.y), band)
		draw_rect(body, dark, false, 4.0)
		# kapak: menteşeden yukarı kalkar
		var lift := lid * h * 0.32
		var lid_rect := Rect2(w * 0.06, h * 0.24 - lift, w * 0.88, h * 0.22)
		draw_rect(lid_rect, wood.lightened(0.08))
		for x in [0.18, 0.82]:
			draw_rect(Rect2(w * x - w * 0.04, lid_rect.position.y, w * 0.08, lid_rect.size.y), band)
		draw_rect(lid_rect, dark, false, 4.0)
		# kilit
		if lid < 0.3:
			var lk := Rect2(w * 0.44, h * 0.4, w * 0.12, h * 0.14)
			draw_rect(lk, band)
			draw_circle(lk.get_center(), w * 0.02, dark)


static func confetti(parent: Control, at: Vector2, colors: Array) -> void:
	for c in colors:
		var p := CPUParticles2D.new()
		p.position = at
		p.amount = 40
		p.one_shot = true
		p.explosiveness = 0.95
		p.lifetime = 1.8
		p.direction = Vector2.UP
		p.spread = 75.0
		p.initial_velocity_min = 380.0
		p.initial_velocity_max = 760.0
		p.gravity = Vector2(0, 900)
		p.angular_velocity_min = -400.0
		p.angular_velocity_max = 400.0
		p.scale_amount_min = 5.0
		p.scale_amount_max = 10.0
		p.color = Color(c)
		parent.add_child(p)
		p.emitting = true
		p.finished.connect(p.queue_free)


# Tam ekran ödül penceresi: huzmeler, konfeti, ortada resim, nadirlik ve ad. Dokununca kapanır.
static func reward_popup(layer: CanvasLayer, title: String, name: String, tier_name: String, tier_color: Color, pic: Control) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.01, 0.03, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var rays := Rays.new()
	rays.color = tier_color
	rays.set_anchors_preset(Control.PRESET_FULL_RECT)
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(rays)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(v)
	v.add_child(UI.title(title, 46, Color.WHITE, true))
	pic.custom_minimum_size = Vector2(260, 260)
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(pic)
	v.add_child(UI.title(tier_name, 24, tier_color.lightened(0.3), true))
	v.add_child(UI.title(name, 38, Color("#ffcf8a"), true))
	v.add_child(UI.label("Devam etmek için dokun", 18, Color(0.7, 0.72, 0.8), true))
	layer.add_child(root)
	root.pivot_offset = root.get_viewport_rect().size / 2.0
	root.scale = Vector2.ONE * 0.6
	root.modulate.a = 0.0
	var tw := root.create_tween().set_parallel()
	tw.tween_property(root, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "modulate:a", 1.0, 0.2)
	confetti(root, root.get_viewport_rect().size * Vector2(0.5, 0.62), [tier_color, "#ffcf8a", "#5be37d", "#ffffff"])
	root.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			var out := root.create_tween()
			out.tween_property(root, "modulate:a", 0.0, 0.15)
			out.tween_callback(root.queue_free))
	return root
