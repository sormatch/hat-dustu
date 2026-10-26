# Mağaza küçük resimleri.
# 1) Pakette hazır resim (assets/kucuk/, tools/kucuk_resim_pisir.gd ile derlemeden önce üretilir): arka planda
#    iş parçacığıyla yüklenir, ana döngü donmaz. Erkek ve kadın gövdesi için ayrı set (diğer gövdeler en yakınını kullanır).
# 2) Pakette yoksa (sonradan eklenmiş eşya): karakter ekran dışında çekilir, user://thumbs/ altına .webp olarak
#    yazılır; bir dahaki açılışta diskten okunur. Üretim tek tek, aralarında bir kare nefes.
# Bellekte en çok LRU_MAX resim tutulur (görünmeyen kartların dokusu boşalır); OS bellek uyarısında bosalt().
extends Node

const BodyScript := preload("res://scripts/model_body.gd")
const Catalog := preload("res://scripts/catalog.gd")
const SIZE := 256
const PAKET := "res://assets/kucuk/"
const DISK := "user://thumbs/"
const LRU_MAX := 72
const BUTCE_USEC := 4000  # kare başına yüklenen resimleri karta koyma süresi
# Saç rengine bağlı kartlar: her saç rengi için ayrı resim (<kat>_<kimlik>_<renk>.webp). Saç stili ve sakal kartları
# oyuncunun seçtiği saç rengiyle görünür; "sac_renk" kartları oyuncunun saç stilini o renkte gösterir (aynı dosyalar).
const RENKLI := ["sac", "sakal"]

static var _cache := {}  # yol/anahtar -> Texture2D
static var _order: Array = []  # LRU sırası (en yeni sonda)

var _queue: Array = []  # üretilecekler: [anahtar, görünüş, kategori, kimlik, TextureRect]
var _busy := false
var _loading := {}  # paket yolu -> [TextureRect, ...] (iş parçacığında yükleniyor)


# Paketteki resmin gövde seti: kadın gövdeleri "kadin", diğerleri "erkek".
static func variant(look: Dictionary) -> String:
	return "kadin" if BodyScript.base_of(str(look.get("govde", "erkek"))) == "kadin" else "erkek"


static func paket_yolu(look: Dictionary, cat: String, id: String) -> String:
	if cat == "govde":
		return PAKET + "govde_%s.webp" % id
	if cat == "sac_renk":
		return PAKET + "%s/sac_%s_%d.webp" % [variant(look), renk_stili(look), _renk(id)]
	if cat in RENKLI:
		return PAKET + "%s/%s_%s_%d.webp" % [variant(look), cat, id, _renk(look.get("sac_renk", 0))]
	return PAKET + "%s/%s_%s.webp" % [variant(look), cat, id]


static func _renk(v: Variant) -> int:
	return clampi(int(v), 0, Catalog.HAIR_COLORS.size() - 1)


# Saç rengi kartında gösterilen stil: oyuncunun saçı; kel ya da bilinmiyorsa gövde setinin temel saçı.
static func renk_stili(look: Dictionary) -> String:
	var s := str(look.get("sac", ""))
	if s == "kel" or Catalog.item_name("sac", s) == s:
		return str(temel_gorunus(variant(look)).sac)
	return s


# Kartın çekileceği görünüş: temel görünüş + kartın saç rengi (ve saç rengi kartında oyuncunun saç stili).
static func cekim_gorunusu(look: Dictionary, cat: String, id: String) -> Dictionary:
	var base := temel_gorunus(variant(look))
	if cat == "sac_renk":
		base.sac = renk_stili(look)
		base.sac_renk = _renk(id)
	elif cat in RENKLI:
		base.sac_renk = _renk(look.get("sac_renk", 0))
	return base


# Pişirme aracı ve yedek üretim için sabit temel görünüş (herkes aynı resmi görür; telefonda çekim yok).
static func temel_gorunus(v: String) -> Dictionary:
	if v == "kadin":
		return {"govde": "kadin", "ten": 1, "sac": "uzun_duz", "sac_renk": 1, "goz": 0, "kas": "duz", "sakal": "yok", "kiyafet": "turuncu", "aksesuar": "yok", "sapka": "yok", "dovme": "yok"}
	return {"govde": "erkek", "ten": 1, "sac": "kisa", "sac_renk": 0, "goz": 0, "kas": "duz", "sakal": "yok", "kiyafet": "turuncu", "aksesuar": "yok", "sapka": "yok", "dovme": "yok"}


static func key(look: Dictionary, cat: String, id: String) -> String:
	var l := look.duplicate()
	if cat == "sac_renk":
		l[cat] = _renk(id)
	elif cat != "hareket":
		l[cat] = id
	return "%s|%s|%s" % [cat, id, JSON.stringify(l)]


static func _remember(k: String, tex: Texture2D) -> void:
	_cache[k] = tex
	_order.erase(k)
	_order.append(k)
	while _order.size() > LRU_MAX:
		_cache.erase(_order.pop_front())


# Bellek uyarısı: önbellekteki resimler bırakılır (kartlardaki resimler kart silinince boşalır).
static func bosalt() -> void:
	_cache.clear()
	_order.clear()


# Resim hazırsa hemen koyar, değilse arka planda yükler / sıraya ekler (öncelikliyse sıranın başına).
func request(look: Dictionary, cat: String, id: String, target: TextureRect, first := false) -> void:
	var path := paket_yolu(look, cat, id)
	if _cache.has(path):
		target.texture = _cache[path]
		_order.erase(path)
		_order.append(path)
		return
	if ResourceLoader.exists(path):
		if _loading.has(path):
			(_loading[path] as Array).append(target)
			return
		if ResourceLoader.load_threaded_request(path, "Texture2D", false) == OK:
			_loading[path] = [target]
			set_process(true)
			return
		target.texture = load(path)
		_remember(path, target.texture)
		return
	# yedek: ekran dışında çek (diskte varsa oradan)
	var base := cekim_gorunusu(look, cat, id)
	var k := key(base, cat, id)
	if _cache.has(k):
		target.texture = _cache[k]
		return
	var dp := _disk_yolu(k)
	if FileAccess.file_exists(dp):
		var img := Image.load_from_file(dp)
		if img and not img.is_empty():
			var tex := ImageTexture.create_from_image(img)
			_remember(k, tex)
			target.texture = tex
			return
	if first:
		_queue.push_front([k, base, cat, id, target])
	else:
		_queue.append([k, base, cat, id, target])
	if not _busy:
		_run()


func _ready() -> void:
	set_process(not _loading.is_empty())


func _exit_tree() -> void:
	# yarım kalan yüklemelerin sonucu alınsın (yükleyicide asılı kalmasın)
	for path in _loading.keys():
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(path)
	_loading.clear()


func _process(_delta: float) -> void:
	if _loading.is_empty():
		set_process(false)
		return
	var t0 := Time.get_ticks_usec()
	for path in _loading.keys():
		var st := ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		var targets: Array = _loading[path]
		_loading.erase(path)
		var tex: Texture2D = ResourceLoader.load_threaded_get(path) if st == ResourceLoader.THREAD_LOAD_LOADED else null
		if tex:
			_remember(path, tex)
			for t in targets:
				if is_instance_valid(t):
					(t as TextureRect).texture = tex
		if Time.get_ticks_usec() - t0 > BUTCE_USEC:
			break


# İş var mı (ölçüm araçları bekler)
func mesgul() -> bool:
	return _busy or not _queue.is_empty() or not _loading.is_empty()


static func _disk_yolu(k: String) -> String:
	return DISK + k.md5_text() + ".webp"


func _run() -> void:
	_busy = true
	while not _queue.is_empty():
		var job: Array = _queue.pop_front()
		if not is_instance_valid(job[4]):
			continue  # kart artık yok (sekme değişti): üretme
		if _cache.has(job[0]):
			job[4].texture = _cache[job[0]]
			continue
		var tex := await _render(job[1], job[2], job[3])
		if not is_inside_tree():
			break
		_remember(job[0], tex)
		DirAccess.make_dir_recursive_absolute(DISK)
		tex.get_image().save_webp(_disk_yolu(job[0]), true, 0.85)
		if is_instance_valid(job[4]):
			job[4].texture = tex
		await get_tree().process_frame  # bir sonraki üretimden önce bir kare nefes
	_busy = false


func _render(look: Dictionary, cat: String, id: String, msaa := Viewport.MSAA_4X) -> Texture2D:
	var sv := SubViewport.new()
	sv.size = Vector2i(SIZE, SIZE)
	sv.own_world_3d = true
	sv.transparent_bg = true
	sv.msaa_3d = msaa
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
	if cat == "sac_renk":
		l[cat] = _renk(id)
	elif cat != "hareket":
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
