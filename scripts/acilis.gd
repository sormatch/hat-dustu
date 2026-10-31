# Açılış perdesi ve yükleme ekranı. yukleyici.gd (ilk sahne) açılışta bunu kurar; main.gd _ready perdeyi devralır.
#
# AKIŞ (telefonda takılmasın diye): animasyon CANLI HESAPLANMAZ; tools/acilis_gif_pisir.gd onu önceden çizilmiş
# kare dizisine pişirmiştir (assets/ui/uretim/acilis_kareler.res: ~2,3 sn, 30 fps, kayıplı WebP, tek dosya;
# sesler acilis_ses.ogg). Katman, parlama gölgelendiricisi, parçacık ve zil üretimi yok.
#  1) GIF: ilk kare sistem açılış görseliyle (acilis_splash.png) aynı yerde, aynı boyda, aynı zeminde başlar.
#     Kareler YAN İŞ PARÇACIĞINDA çözülür; ana iş parçacığı yalnız tek dokuyu günceller (ImageTexture.update).
#     Kare gerçek saate göre seçilir: ana iş parçacığı geç kalırsa kareler ATLANIR, animasyon yavaşlamaz.
#     Bu sürede ana iş parçacığında ağır iş YOKTUR (yukleyici.gd ana sahneyi yan iş parçacığında yükler,
#     GIF bitmeden main.tscn kurulmaz). Ses tek dosya, ses motorunda zamanlı çalar.
#  2) GIF bitince son karede sabit durur, altta ince amber ilerleme çizgisi belirir; ağır kurulum (main.gd _ready,
#     kademeli) ve gölgelendirici ısıtma (_isit) bu sabit ekranın altında koşar: takılma gözle görülmez.
#  3) Hazır olunca perde yumuşakça kalkar, menü görünür.
#  - Menüye dönüşte (sahne yeniden kurulur): son kare sabit + çubuk, kısa.
#  - Test / araç çalıştırmaları (--script, shot=, auto=): görünmez; dünya eskisi gibi tek seferde kurulur.
# Ölçüm: `acilis_olc=1`; yavaş telefon taklidi (yalnız ölçümde): yavas=<ms> (ana iş parçacığına kare başı bekleme),
# yavas_dec=<ms> (çözücüye), yuk=<n> (n boşta dönen iş parçacığı).
extends CanvasLayer

const ZEMIN := Color("#0b0e0f")  # acilis_splash.png zemini ve project.godot boot_splash/bg_color ile aynı
const AMBER := Color("#ffb020")
const SPLASH := Vector2(1920, 1080)
const TUVAL := Vector2(2400, 1080)  # pişirilen kare tuvali (tasarım birimi; tools/acilis_gif_pisir.gd TUVAL ile aynı)
const KARELER := "res://assets/ui/uretim/acilis_kareler.res"
const SES := "res://assets/ui/uretim/acilis_ses.ogg"
const T_HAT := 1.05  # titreşim anları (pişirilen animasyondaki vuruşlar)
const T_DUSTU := 1.45
const SURE_DONUS := 0.35
const ISIT_KARE := 4  # ısıtmada bir karede çizilen yeni malzeme sayısı
const ONBELLEK := 6  # çözülmüş, gösterilmeyi bekleyen en çok kare (RGB8 ~2,8 MB)

static var _ilk := true  # bu süreçte ilk açılış mı
static var _isitildi := false

var kademeli := true  # false: araç/test (dünya tek seferde kurulur, perde görünmez)
var tur := "ilk"  # ilk | donus | test
var gif_bitti := false  # GIF son karesine ulaştı (yukleyici.gd ana sahneyi bundan sonra kurar)
var saat := 0.0  # GIF saati (sn, gerçek saat; ölçüm/araçlar)
var gosterilen := -1  # ekrandaki kare numarası
var _host: Node
var _kok: Control
var _gorsel: TextureRect
var _tex: ImageTexture
var _bar_kutu: Control
var _bar: ColorRect
var _yazi: Label
var _oran := 0.0
var _hedef := 0.0
var _gecildi := false  # dokununca GIF atlanır
var _kalkiyor := false
var _bas_ms := 0
var _olc := OS.get_cmdline_user_args().has("acilis_olc=1")  # ölçüm: adım süreleri yazılır
var _adim_us := Time.get_ticks_usec()
var _kareler: Array = []  # kare paketi (PackedByteArray listesi)
var _n := 0
var _fps := 30
var _bas_us := -1  # GIF saatinin başladığı an (ilk çizim karesi)
var _titre_oldu := {}
var _is: Thread
var _mx := Mutex.new()
var _hazir := {}  # kare no -> çözülmüş Image (çözücü iş parçacığı yazar)
var _iste := 0  # ana iş parçacığının şu an istediği kare
var _dur := false
var _yavas_ms := 0
var _yavas_dec := 0
var _yuk: Array[Thread] = []
var _tum_ms: Array = []  # ölçüm: bütün karelerin süreleri
var _gif_ms: Array = []  # ölçüm: GIF sırasındaki kare süreleri
var _gosterim_sayisi := 0
var _kare_us := 0
var _gif_son_ms := 0


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
		gif_bitti = true
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
	# kare dizisi: sistem açılış görseliyle aynı ölçek (Keep: tasarım 1920x1080 ekrana sığar, ortalanır)
	var paket: Resource = load(KARELER) if ResourceLoader.exists(KARELER) else null
	if paket != null and paket.has_meta("kareler"):
		_kareler = paket.get_meta("kareler")
		_fps = int(paket.get_meta("fps", 30))
		_n = _kareler.size()
	if _n == 0:
		gif_bitti = true  # paket yok: yalnız zemin + çubuk (kurulum yine çalışır)
	else:
		var ilk_kare := 0 if tur == "ilk" else _n - 1
		_tex = ImageTexture.create_from_image(_coz(ilk_kare))
		_gorsel = TextureRect.new()
		_gorsel.texture = _tex
		_gorsel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_gorsel.stretch_mode = TextureRect.STRETCH_SCALE
		_gorsel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_gorsel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var olcek := minf(vs.x / SPLASH.x, vs.y / SPLASH.y)
		_gorsel.size = TUVAL * olcek
		_gorsel.position = (vs - _gorsel.size) / 2.0
		_kok.add_child(_gorsel)
		gosterilen = ilk_kare
		if tur == "ilk":
			_olc_ayar()
			_is = Thread.new()
			_is.start(_coz_gorev, Thread.PRIORITY_HIGH)
		else:
			gif_bitti = true
	# altta ince amber yükleme çubuğu ve "YÜKLENİYOR" (GIF bitince belirir)
	_bar_kutu = Control.new()
	_bar_kutu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bw := minf(vs.x * 0.36, 520.0)
	_bar_kutu.size = Vector2(bw, 34)
	_bar_kutu.position = Vector2(vs.x / 2.0 - bw / 2.0, vs.y - 64.0)
	_bar_kutu.modulate.a = 1.0 if gif_bitti else 0.0
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


# Ölçümde yavaş telefon taklidi (yalnız acilis_olc=1)
func _olc_ayar() -> void:
	if not _olc:
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("yavas="):
			_yavas_ms = int(a.trim_prefix("yavas="))
		elif a.begins_with("yavas_dec="):
			_yavas_dec = int(a.trim_prefix("yavas_dec="))
		elif a.begins_with("yuk="):
			for i in int(a.trim_prefix("yuk=")):
				var t := Thread.new()
				t.start(func() -> void:
					var x := 0.0
					while not _dur:
						x += sqrt(float(Time.get_ticks_usec() % 977)))
				_yuk.append(t)


func _coz(k: int) -> Image:
	var im := Image.new()
	im.load_webp_from_buffer(_kareler[k])
	return im


# Yan iş parçacığı: ana iş parçacığının istediği kareden başlayarak çözer (geride kalırsa kareleri atlar).
func _coz_gorev() -> void:
	var sonraki := 1
	while not _dur and sonraki < _n:
		_mx.lock()
		var ist := _iste
		var bekleyen := _hazir.size()
		_mx.unlock()
		if bekleyen >= ONBELLEK:
			OS.delay_msec(2)
			continue
		sonraki = clampi(maxi(sonraki, ist), 1, _n - 1)
		var im := _coz(sonraki)
		if _yavas_dec > 0:
			OS.delay_msec(_yavas_dec)
		_mx.lock()
		_hazir[sonraki] = im
		_mx.unlock()
		if sonraki >= _n - 1:
			break
		sonraki += 1


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
	var bas := Time.get_ticks_msec()
	while not gif_bitti and Time.get_ticks_msec() - bas < 5000:  # yalnız araçlar main.tscn'i doğrudan açınca
		await get_tree().process_frame
	if tur == "ilk" and not _isitildi and not OS.get_cmdline_user_args().has("isitma=0"):
		_isitildi = true
		await _isit()
	_hedef = 1.0
	_ilk = false
	bas = Time.get_ticks_msec()
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


func _input(e: InputEvent) -> void:
	if tur == "test" or _kalkiyor or gif_bitti:
		return
	if (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed):
		_gecildi = true  # dokununca GIF son kareye atlar
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var simdi := Time.get_ticks_usec()
	if _olc and _kare_us > 0:
		var ms := (simdi - _kare_us) / 1000.0
		_tum_ms.append(ms)
		if not gif_bitti:
			_gif_ms.append(ms)
		if ms > 100.0 or (not gif_bitti and ms > 25.0):
			print("[acilis] uzun kare %.0f ms (hedef %.2f, %d ms, gif %s)" % [ms, _hedef, Time.get_ticks_msec(), str(not gif_bitti)])
	_kare_us = simdi
	if tur == "test" or _kok == null:
		return
	if not gif_bitti:
		_gif_adim()
	elif _bar_kutu.modulate.a < 1.0:
		_bar_kutu.modulate.a = minf(1.0, _bar_kutu.modulate.a + delta * 4.0)  # çizgi hafifçe belirir
	_oran = move_toward(_oran, _hedef, delta * (2.2 if _hedef >= 1.0 else 0.9))
	_bar.size.x = _bar_kutu.size.x * _oran


# GIF: kare gerçek saate göre seçilir (geç kalınırsa atlanır); ağır iş yok.
func _gif_adim() -> void:
	if _yavas_ms > 0:
		OS.delay_msec(_yavas_ms)  # yalnız ölçüm: yavaş telefon
	var simdi := Time.get_ticks_usec()
	if _bas_us < 0:
		_bas_us = simdi
		_ses_baslat()
	if _gecildi:
		_bas_us = mini(_bas_us, simdi - int(float(_n) / float(_fps) * 1.0e6))
	saat = float(simdi - _bas_us) / 1.0e6
	var k := mini(int(saat * float(_fps)), _n - 1)
	var im: Image = null
	var en := -1
	_mx.lock()
	_iste = k
	for key: int in _hazir:
		if key <= k and key > en:
			en = key
	if en >= 0:
		im = _hazir[en]
		for key: int in _hazir.keys():
			if key <= en:
				_hazir.erase(key)
	_mx.unlock()
	if im != null:
		_tex.update(im)
		gosterilen = en
		_gosterim_sayisi += 1
	elif k >= _n - 1 and gosterilen < _n - 1 and saat > float(_n) / float(_fps) + 0.6:
		_tex.update(_coz(_n - 1))  # çözücü yetişemedi: son kare
		gosterilen = _n - 1
	if saat >= T_HAT:
		_titre("h", 25)
	if saat >= T_DUSTU:
		_titre("d", 40)
	if gosterilen >= _n - 1:
		gif_bitti = true
		_gif_son_ms = Time.get_ticks_msec()
		_dur = true
		if _olc:
			var sirali := _gif_ms.duplicate()
			sirali.sort()
			var uzun := sirali.filter(func(x: float) -> bool: return x > 25.0)
			var kare_sayisi := _gosterim_sayisi + 1
			print("[acilis] GIF bitti: gercek sure %.0f ms (animasyon %.0f ms), gosterilen %d/%d kare (atlanan %d), ana is parcacigi en uzun kare %.1f ms, 25 ms ustu %d kare, ort %.1f ms" % [
				saat * 1000.0, float(_n) / float(_fps) * 1000.0, kare_sayisi, _n, _n - kare_sayisi, sirali[-1] if not sirali.is_empty() else 0.0, uzun.size(),
				(sirali.reduce(func(a: float, b: float) -> float: return a + b, 0.0) / maxf(1.0, sirali.size())) if not sirali.is_empty() else 0.0])


# Vuruş titreşimi (ayarlardan kapatılabilir; yukleyici aşamasında profil henüz yoktur: titreşim yok)
func _titre(ad: String, ms: int) -> void:
	if _titre_oldu.has(ad):
		return
	_titre_oldu[ad] = true
	var pr: Variant = _host.get("profile") if _host else null
	if pr and bool(pr.settings.get("titresim", true)):
		Input.vibrate_handheld(ms)


# Zil + vuruş sesleri tek dosyada (tools/acilis_gif_pisir.gd karıştırır); ses motorunda zamanlı çalar,
# kare takılmasından etkilenmez.
func _ses_baslat() -> void:
	if not ResourceLoader.exists(SES):
		return
	var a := AudioStreamPlayer.new()
	a.stream = load(SES)
	if AudioServer.get_bus_index("Efekt") >= 0:
		a.bus = "Efekt"
	add_child(a)
	a.play()
	a.finished.connect(a.queue_free)


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


func _exit_tree() -> void:
	_dur = true
	if _is and _is.is_started():
		_is.wait_to_finish()
	for t in _yuk:
		t.wait_to_finish()
	_yuk.clear()
