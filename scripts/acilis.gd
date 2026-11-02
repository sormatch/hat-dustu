# Açılış perdesi ve yükleme ekranı. yukleyici.gd (ilk sahne) açılışta bunu kurar; main.gd _ready perdeyi devralır.
#
# AKIŞ: animasyon yok. Sistem açılış görseliyle (acilis_splash.png, HAT DÜŞTÜ amblemi) aynı resim, aynı yerde, aynı
# boyda sabit durur; altta ince amber yükleme çizgisi ilerler. Ağır kurulum (main.gd _ready, kademeli) ve gölgelendirici
# ısıtma (_isit) bu sabit ekranın altında koşar: takılma gözle görülmez. Hazır olunca perde yumuşakça kalkar.
#  - Test / araç çalıştırmaları (--script, shot=, auto=): görünmez; dünya eskisi gibi tek seferde kurulur.
# Ölçüm: `acilis_olc=1`.
extends CanvasLayer

const ZEMIN := Color("#0b0e0f")  # acilis_splash.png zemini ve project.godot boot_splash/bg_color ile aynı
const AMBER := Color("#ffb020")
const SPLASH := Vector2(1920, 1080)
const RESIM := "res://assets/ui/uretim/acilis_splash.png"
const SURE_DONUS := 0.35
const ISIT_KARE := 4  # ısıtmada bir karede çizilen yeni malzeme sayısı

static var _ilk := true  # bu süreçte ilk açılış mı
static var _isitildi := false

var kademeli := true  # false: araç/test (dünya tek seferde kurulur, perde görünmez)
var tur := "ilk"  # ilk | donus | test
var _host: Node
var _kok: Control
var _gorsel: TextureRect
var _bar_kutu: Control
var _bar: ColorRect
var _yazi: Label
var _oran := 0.0
var _hedef := 0.0
var _kalkiyor := false
var _bas_ms := 0
var _olc := OS.get_cmdline_user_args().has("acilis_olc=1")  # ölçüm: adım süreleri yazılır
var _adim_us := Time.get_ticks_usec()
var _tum_ms: Array = []  # ölçüm: bütün karelerin süreleri
var _kare_us := 0


func _init() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	var user := OS.get_cmdline_user_args()
	var test := false
	for a in user:
		if a.begins_with("shot=") or a.begins_with("auto=") or a.begins_with("pose="):
			test = true
	kademeli = not OS.get_cmdline_args().has("--script") or user.has("kademeli=1")
	if test or not kademeli:
		tur = "test"
	elif not _ilk:
		tur = "donus"


func _ready() -> void:
	_host = get_parent()
	_bas_ms = Time.get_ticks_msec()
	if _olc:
		print("[acilis] perde ilk kez: motor acilisindan %d ms (bu ana kadar ekran sabit acilis resmi)" % _bas_ms)
	if tur == "test":
		if kademeli:
			# test görüntülerinde perde olmasın ama kurulum sırasında yarım dünya da görünmesin: düz zemin
			var z := ColorRect.new()
			z.color = ZEMIN
			z.set_anchors_preset(Control.PRESET_FULL_RECT)
			add_child(z)
		set_process(false)
		return
	_kur()


func _kur() -> void:
	var vs := get_viewport().get_visible_rect().size
	_kok = Control.new()
	_kok.set_anchors_preset(Control.PRESET_FULL_RECT)
	_kok.mouse_filter = Control.MOUSE_FILTER_STOP  # alttaki menüye dokunulmasın
	add_child(_kok)
	var zemin := ColorRect.new()
	zemin.color = ZEMIN
	zemin.set_anchors_preset(Control.PRESET_FULL_RECT)
	zemin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kok.add_child(zemin)
	# sistem açılış görseliyle aynı resim ve ölçek (Keep: tasarım 1920x1080 ekrana sığar, ortalanır): geçiş görünmez
	_gorsel = TextureRect.new()
	_gorsel.texture = load(RESIM)
	_gorsel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_gorsel.stretch_mode = TextureRect.STRETCH_SCALE
	_gorsel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var olcek := minf(vs.x / SPLASH.x, vs.y / SPLASH.y)
	_gorsel.size = SPLASH * olcek
	_gorsel.position = (vs - _gorsel.size) / 2.0
	_kok.add_child(_gorsel)
	# altta ince amber yükleme çubuğu ve "YÜKLENİYOR"
	_bar_kutu = Control.new()
	_bar_kutu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bw := minf(vs.x * 0.36, 520.0)
	_bar_kutu.size = Vector2(bw, 34)
	_bar_kutu.position = Vector2(vs.x / 2.0 - bw / 2.0, vs.y - 64.0)
	_kok.add_child(_bar_kutu)
	_yazi = Label.new()
	_yazi.text = tr("YÜKLENİYOR")
	_yazi.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_yazi.add_theme_font_size_override("font_size", 15)
	_yazi.add_theme_color_override("font_color", Color(AMBER, 0.7))
	_yazi.add_theme_constant_override("outline_size", 0)
	_yazi.size = Vector2(bw, 20)
	_yazi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_kutu.add_child(_yazi)
	var iz := ColorRect.new()
	iz.color = Color(1, 1, 1, 0.1)
	iz.size = Vector2(bw, 3)
	iz.position = Vector2(0, 26)
	iz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_kutu.add_child(iz)
	_bar = ColorRect.new()
	_bar.color = AMBER
	_bar.size = Vector2(0, 3)
	_bar.position = Vector2(0, 26)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_kutu.add_child(_bar)


# Ana sahne arka planda yüklenirken (yukleyici.gd) çubuk ilerler; beklemez.
func ilerle(oran: float) -> void:
	_hedef = maxf(_hedef, oran)


# Kurulum adımı bitti: çubuk ilerler, bir kare çizilir. Araç çalıştırmalarında beklemez.
func adim(oran: float) -> void:
	_hedef = maxf(_hedef, oran)
	if _olc:
		var simdi := Time.get_ticks_usec()
		print("[acilis] adim %.2f: %.1f ms" % [oran, (simdi - _adim_us) / 1000.0])
		_adim_us = simdi
	if kademeli:
		await get_tree().process_frame


# Uzun bir kurulum adımının içinde: son karenin üstünden ~25 ms geçtiyse bir kare çizdirir (çubuk akar).
# Geçmediyse hiç beklemeden döner.
func nefes() -> void:
	if kademeli and tur != "test" and Time.get_ticks_usec() - _kare_us > 25000:
		await get_tree().process_frame


# İlk açılışta gölgelendiriciler dünya ilk kez çizilmeden ÖNCE ısıtılır (main.gd 3B çizimi açmadan çağırır):
# yoksa dünyanın ilk karesi bütün malzemeleri aynı anda derler (~0,5 sn donma). Ekranda sabit son kare durur.
func on_isit() -> void:
	if kademeli and tur == "ilk" and not _isitildi and not OS.get_cmdline_user_args().has("isitma=0"):
		_isitildi = true
		await _isit()


# Dünya hazır: (ilk açılışta) gölgelendiriciler ısıtılır, perde kalkar.
func bitir() -> void:
	if not kademeli or tur == "test":
		queue_free()
		return
	_hedef = maxf(_hedef, 0.92)
	if tur == "ilk" and not _isitildi and not OS.get_cmdline_user_args().has("isitma=0"):
		_isitildi = true
		await _isit()
	_hedef = 1.0
	_ilk = false
	var bas := Time.get_ticks_msec()
	while (_oran < 0.995 or (tur == "donus" and Time.get_ticks_msec() - _bas_ms < int(SURE_DONUS * 1000.0))) \
			and Time.get_ticks_msec() - bas < 4000:
		await get_tree().process_frame
	print("[acilis] perde kalkiyor: %d ms (motor acilisindan %d ms)" % [Time.get_ticks_msec() - _bas_ms, Time.get_ticks_msec()])
	if _olc and not _tum_ms.is_empty():
		var sirali := _tum_ms.duplicate()
		sirali.sort()
		var uzun := sirali.filter(func(x: float) -> bool: return x > 50.0)
		print("[acilis] kareler: %d, en uzun %.0f ms, 50 ms ustu %d kare, en uzun 8: %s" % [sirali.size(), sirali[-1], uzun.size(), str(sirali.slice(-8).map(func(x: float) -> int: return int(x)))])
	_kalkiyor = true
	_kok.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(_kok, "modulate:a", 0.0, 0.45 if tur == "ilk" else 0.25).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(queue_free)


func _process(delta: float) -> void:
	var simdi := Time.get_ticks_usec()
	if _olc and _kare_us > 0:
		var ms := (simdi - _kare_us) / 1000.0
		_tum_ms.append(ms)
		if ms > 100.0:
			print("[acilis] uzun kare %.0f ms (hedef %.2f, %d ms)" % [ms, _hedef, Time.get_ticks_msec()])
	_kare_us = simdi
	if tur == "test" or _kok == null:
		return
	_oran = move_toward(_oran, _hedef, delta * (2.2 if _hedef >= 1.0 else 0.9))
	_bar.size.x = _bar_kutu.size.x * _oran


# ---------- gölgelendirici ısıtma ----------
# Sahnedeki bütün malzemeler (koridor, hücreler, salon, karakter) ve sonradan çıkan efektler (patlama, altıpatar,
# C4, başka giyimli karakterler) ekran dışındaki küçük bir görünümde birer kez çizilir: gölgelendiriciler şimdi
# derlenir, maçta ilk görüldükleri karede değil. Her karede ISIT_KARE yeni malzeme (kareler uzun donmasın).
func _isit() -> void:
	var t0 := Time.get_ticks_msec()
	var sv := SubViewport.new()
	sv.size = Vector2i(192, 108)
	sv.own_world_3d = true
	sv.msaa_3d = get_viewport().msaa_3d
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var root := Node3D.new()
	sv.add_child(root)
	var env: Environment = _host.get("env")
	if env:
		var we := WorldEnvironment.new()
		we.environment = env
		root.add_child(we)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.0, 3.0)
	cam.fov = 60.0
	root.add_child(cam)
	cam.current = true
	# gölgeli ışıklar: gölge geçişinin gölgelendiricileri de derlensin
	var omni := OmniLight3D.new()
	omni.position = Vector3(0.6, 2.0, 1.5)
	omni.shadow_enabled = true
	omni.omni_range = 8.0
	root.add_child(omni)
	var spot := SpotLight3D.new()
	spot.position = Vector3(-0.8, 2.5, 2.0)
	spot.rotation = Vector3(-1.0, 0, 0)
	spot.shadow_enabled = true
	spot.spot_range = 8.0
	root.add_child(spot)
	await get_tree().process_frame  # alt görüntü ve gölgeli ışıklar ayrı karede hazırlansın
	var mats := _malzemeler(_host)
	mats.append_array(preload("res://scripts/efekt.gd").isitma_listesi() + preload("res://scripts/dunya.gd").diger_kalite_malzemeleri())  # efektler + öbür kalitenin kirli/sade malzemeleri (E ajanı)
	var kutu := BoxMesh.new()
	kutu.size = Vector3(0.4, 0.4, 0.4)
	var i := 0
	var parti: Array = []
	for m in mats:
		var mi := MeshInstance3D.new()
		mi.mesh = kutu
		mi.material_override = m
		mi.position = Vector3((i % 6) * 0.45 - 1.1, 0.4 + ((i / 6) % 4) * 0.45, 0)
		root.add_child(mi)
		parti.append(mi)
		i += 1
		if parti.size() >= ISIT_KARE:
			_hedef = maxf(_hedef, 0.92 + 0.05 * float(i) / mats.size())
			await get_tree().process_frame
			for n in parti:
				n.queue_free()
			parti.clear()
	await get_tree().process_frame
	for n in parti:
		n.queue_free()
	# sonradan çıkan efektler ve eşyalar
	var Props := preload("res://scripts/modlar/props.gd")
	Props.hazirla()
	var efekt := Node3D.new()
	root.add_child(efekt)
	Props.explosion(efekt, Vector3(0, 1.0, -1.0), 0.0)
	var gun := Node3D.new()
	gun.position = Vector3(-0.6, 1.0, 1.5)
	root.add_child(gun)
	Props.revolver(gun)
	var c4 := Node3D.new()
	c4.position = Vector3(0.6, 1.0, 1.5)
	root.add_child(c4)
	Props.c4(c4)
	await get_tree().process_frame
	_hedef = maxf(_hedef, 0.98)
	# farklı giyimli karakterler (saç kartı, şeffaf aksesuar, dövme, ranger kıyafeti...)
	var Body := preload("res://scripts/model_body.gd")
	for look in [{"govde": "kadin", "sac": "ikiz_orgu", "sac_renk": 5, "sapka": "bere", "aksesuar": "gunes", "kiyafet": "leopar", "dovme": "gul"},
			{"govde": "iri", "sac": "rasta", "sakal": "dolgun", "sapka": "kapuson", "aksesuar": "zincir", "kiyafet": "firari", "dovme": "ejderha"}]:
		var b: Node3D = Body.new()
		b.look = preload("res://scripts/catalog.gd").sanitize(look)
		b.position = Vector3(0, 0, 0.5)
		root.add_child(b)
		await get_tree().process_frame  # saç / şapka kafa kemiğine bu karede takılır, sonraki karede çizilir
		await get_tree().process_frame
		b.queue_free()
	await get_tree().process_frame
	efekt.queue_free()  # patlamanın gecikmeli tozu dumanla aynı malzeme (zaten çizildi)
	await get_tree().process_frame
	sv.queue_free()
	print("[acilis] isitma: %d malzeme, %d ms" % [mats.size(), Time.get_ticks_msec() - t0])


# Ağaçtaki bütün 3D malzemeler (tekrarsız; aynı gölgelendiricili ShaderMaterial'lerden biri yeter).
static func _malzemeler(host: Node) -> Array:
	var seen := {}
	var shaders := {}
	var out: Array = []
	var ekle := func(m: Material) -> void:
		while m:
			if not seen.has(m):
				seen[m] = true
				if m is ShaderMaterial:
					var sh: Shader = (m as ShaderMaterial).shader
					if sh and not shaders.has(sh):
						shaders[sh] = true
						out.append(m)
				elif m is BaseMaterial3D:
					out.append(m)
			m = m.next_pass
	for n in host.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		ekle.call(g.material_override)
		ekle.call(g.material_overlay)
		var mesh: Mesh = null
		if g is MeshInstance3D:
			mesh = (g as MeshInstance3D).mesh
			for s in (mesh.get_surface_count() if mesh else 0):
				ekle.call((g as MeshInstance3D).get_surface_override_material(s))
		elif g is CPUParticles3D:
			mesh = (g as CPUParticles3D).mesh
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
			mesh = (g as MultiMeshInstance3D).multimesh.mesh
		if mesh:
			for s in mesh.get_surface_count():
				ekle.call(mesh.surface_get_material(s))
	return out


