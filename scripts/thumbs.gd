# Mağaza küçük resimleri: oyuncunun karakterine o parça giydirilip ekran dışında çekilir.
# Sırayla tek tek üretilir (telefonu yormamak için) ve bellekte saklanır.
extends Node

const BodyScript := preload("res://scripts/model_body.gd")
const SIZE := 256

static var _cache := {}

var _queue: Array = []  # [anahtar, görünüş, kategori, kimlik, TextureRect]
var _busy := false


static func key(look: Dictionary, cat: String, id: String) -> String:
	var l := look.duplicate()
	if cat != "hareket":
		l[cat] = id
	return "%s|%s|%s" % [cat, id, JSON.stringify(l)]


# Resim hazırsa hemen koyar, değilse sıraya ekler (öncelikliyse sıranın başına).
func request(look: Dictionary, cat: String, id: String, target: TextureRect, first := false) -> void:
	var k := key(look, cat, id)
	if _cache.has(k):
		target.texture = _cache[k]
		return
	if first:
		_queue.push_front([k, look.duplicate(), cat, id, target])
	else:
		_queue.append([k, look.duplicate(), cat, id, target])
	if not _busy:
		_run()


func _run() -> void:
	_busy = true
	while not _queue.is_empty():
		var job: Array = _queue.pop_front()
		if _cache.has(job[0]):
			if is_instance_valid(job[4]):
				job[4].texture = _cache[job[0]]
			continue
		var tex := await _render(job[1], job[2], job[3])
		_cache[job[0]] = tex
		if is_instance_valid(job[4]):
			job[4].texture = tex
	_busy = false


func _render(look: Dictionary, cat: String, id: String) -> Texture2D:
	var sv := SubViewport.new()
	sv.size = Vector2i(SIZE, SIZE)
	sv.own_world_3d = true
	sv.transparent_bg = true
	sv.msaa_3d = Viewport.MSAA_4X
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.62, 0.64, 0.72)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	sv.add_child(env)
	var key_l := DirectionalLight3D.new()
	key_l.rotation = Vector3(-0.45, 2.75, 0)
	key_l.light_energy = 1.5
	sv.add_child(key_l)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(-0.3, 0.4, 0)
	rim.light_energy = 0.7
	rim.light_color = Color("#9fc4ff")
	sv.add_child(rim)
	var body: Node3D = BodyScript.new()
	var l := look.duplicate()
	if cat != "hareket":
		l[cat] = id
	body.look = l
	body.rotation.y = 0.35
	sv.add_child(body)
	var cam := Camera3D.new()
	sv.add_child(cam)
	match cat:
		"kiyafet", "hareket", "govde":
			cam.fov = 34
			cam.look_at_from_position(Vector3(0, 1.05, -3.3), Vector3(0, 0.95, 0))
		"sapka" when id in ["asci", "parti", "hale", "kovboy", "korsan", "tilki"]:
			# uzun / geniş şapkalar: biraz geriden, tepesi kesilmesin
			cam.fov = 30
			cam.look_at_from_position(Vector3(0, 1.86, -1.5), Vector3(0, 1.72, 0))
		"sapka":
			cam.fov = 28
			cam.look_at_from_position(Vector3(0, 1.72, -1.1), Vector3(0, 1.6, 0))
		"aksesuar" when id in ["canta", "gitar"]:
			# sırt eşyaları arkadan (omuz üstünden çapraz)
			body.rotation.y = PI + 0.5
			cam.fov = 34
			cam.look_at_from_position(Vector3(0, 1.35, -2.1), Vector3(0, 1.15, 0))
		"aksesuar" when id in ["saat", "kelepce"]:
			# bilek eşyaları: o elin yakını (kameraya dönük karakterin solu ekranın sağında, dünyada -x)
			var hx := -0.24 if id == "saat" else 0.2
			cam.fov = 26
			cam.look_at_from_position(Vector3(hx * 0.6, 1.05, -0.95), Vector3(hx, 0.86, 0))
		"aksesuar" when id == "anahtar":
			cam.fov = 28
			cam.look_at_from_position(Vector3(0.05, 1.1, -1.05), Vector3(0.08, 0.92, 0))
		"aksesuar" when not (id in ["zincir", "inci", "kunye", "kulaklik_boyun"]):
			# yüz aksesuarları (gözlük, küpe, hızma, bant...) yakından
			cam.fov = 26
			cam.look_at_from_position(Vector3(0, 1.66, -0.9), Vector3(0, 1.6, 0))
		"aksesuar":
			cam.fov = 30
			cam.look_at_from_position(Vector3(0, 1.55, -1.25), Vector3(0, 1.48, 0))
		_:
			cam.fov = 24
			cam.look_at_from_position(Vector3(0, 1.67, -0.82), Vector3(0, 1.6, 0))
	cam.current = true
	# saç/sakal kafa kemiğine bir kare sonra takılır; hareket için animasyonun ortası
	for i in 3:
		await get_tree().process_frame
	if cat == "hareket":
		body.play_emote(id)
		var ap: AnimationPlayer = body._player
		if ap and ap.has_animation("hd/" + id):
			ap.play("hd/" + id, 0.0)  # geçişsiz: karede hareketin kendisi görünsün
			ap.seek(minf(1.2, ap.get_animation("hd/" + id).length * 0.45), true)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := sv.get_texture().get_image()
	sv.queue_free()
	return ImageTexture.create_from_image(img)
