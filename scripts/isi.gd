# Isı / pil yöneticisi (main.gd _ready ekler). Telefonun ısınmasını azaltan üç iş:
#  1. Kare sınırı: ekran 90/120 Hz olsa da oyun 60'ın üstünde çizmez (Godot'ta varsayılan sınır yok). Dokunulmayan
#     menü / salon / telefon görüşmesinde 30'a iner, dokunur dokunmaz 60'a çıkar. Sınır, ekran hızının tam böleni
#     seçilir (90 Hz'de 60 yerine 45: dikey eşzamanlamayla 60 sınırı 45'e takılıp seğirirdi).
#  2. Arka plan: uygulama arka plana alınınca / odağı kaybedince çizim tamamen durur, mantık ve ses 15 kare/sn sürer.
#  3. Otomatik kalite: hedef kare hızı uzun süre tutulamıyorsa (ısınan telefon kısılır) 3D çözünürlüğü kademeli,
#     sonra gölgeyi düşürür. Yalnız ayarlardan "Otomatik" seçiliyken çalışır; elle seçilen kaliteyi ezmez.
# Test / ölçüm için komut satırı: isi=0 (hepsi kapalı, eski davranış).
extends Node

const Dunya := preload("res://scripts/dunya.gd")

const FPS_AKTIF := 60.0
const FPS_SAKIN := 30.0
const FPS_ARKA := 15.0
const SAKIN_BEKLEME := 1.2  # sn: son dokunmadan sonra sakin sayılmak için
const OLCEK_KADEMELERI := [1.0, 0.9, 0.8, 0.8, 0.7, 0.6]  # kademe -> 3D ölçek çarpanı
const GOLGE_KADEMESI := 3  # bu kademede gölgeler kapanır
const PENCERE := 5.0  # sn: kare hızı bu aralıklarla ölçülür
const KOTU_PENCERE_SAYISI := 2  # üst üste bu kadar kötü pencere -> bir kademe düş
const TOLERANS := 0.85  # ölçülen / hedef bunun altındaysa pencere kötü
const KARENCE := 4.0  # sn: durum değişince / geri dönünce ölçüme başlamadan bekle

var main: Node
var devre_disi := false
var arka := false
var kademe := 0
var _son_giris := -100.0
var _istenen := -1.0
var _kontrol_t := 0.0
var _pencere_t := 0.0
var _pencere_n := 0
var _kotu := 0
var _bekle := KARENCE
var _carpan_hedef := 1.0
var _olcek_t := 0.0
var _ayar_imza := ""
var log_ac := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "isi=0":
			devre_disi = true
		elif a == "isi_log=1":
			log_ac = true
	if devre_disi:
		set_process(false)
		set_process_input(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_uygula_sinir(true)


# Ekran yenileme hızının tam bölenlerinden istenene en yakın olanı.
static func sinir_sec(istenen: float, yenileme: float) -> int:
	if yenileme <= 0.0:
		yenileme = 60.0
	# yenileme/n sınırları arasından istenene oran olarak en yakın olan (90 Hz'de 60 -> 45, 120 Hz'de 60, 144 Hz'de 72)
	var en_iyi := yenileme
	for n in range(1, 9):
		var f := yenileme / float(n)
		if absf(log(f / istenen)) < absf(log(en_iyi / istenen)):
			en_iyi = f
	return roundi(en_iyi)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouseButton \
			or event is InputEventKey or (event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask != 0):
		_son_giris = Time.get_ticks_msec() / 1000.0
		if _istenen < FPS_AKTIF:
			_uygula_sinir(true)


func _notification(what: int) -> void:
	if devre_disi or not OS.has_feature("mobile"):
		return  # masaüstünde başka pencereye geçmek çizimi durdurmasın (yan yana test, ekran görüntüsü)
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			arka_plan(true)
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			arka_plan(false)


# Arka planda çizim durur (ağ, ses, sesli sohbet işlemeye devam eder: 15 kare/sn).
func arka_plan(b: bool) -> void:
	if arka == b:
		return
	arka = b
	RenderingServer.render_loop_enabled = not b
	# render_loop_enabled tek başına gerçek sahnede (alt görünümlü ana sahne) çizimi durdurmadı (ölçüldü); kök görünümü de kapat
	RenderingServer.viewport_set_update_mode(get_tree().root.get_viewport_rid(),
			RenderingServer.VIEWPORT_UPDATE_DISABLED if b else RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	_uygula_sinir(true)
	if not b:
		_bekle = KARENCE
		_pencere_t = 0.0
		_pencere_n = 0


func _simdi() -> float:
	return Time.get_ticks_msec() / 1000.0


func _hareketli() -> bool:
	if _simdi() - _son_giris < SAKIN_BEKLEME or Input.is_anything_pressed():
		return true
	var hud: Node = main.get("hud")
	return hud != null and hud.get("move") != null and (hud.get("move") as Vector2) != Vector2.ZERO


# Şu an hangi kare hızı yeter?
func istenen_fps() -> float:
	if arka:
		return FPS_ARKA
	if _hareketli():
		return FPS_AKTIF
	var oynuyor: bool = bool(main.get("playing"))
	# menü, bekleme salonu, telefon görüşmesi (phone_state 3 = CALL): dokunulmuyorsa 30 yeter
	if not oynuyor or bool(main.get("in_lobby")) or int(main.get("phone_state")) == 3:
		return FPS_SAKIN
	return FPS_AKTIF


func _uygula_sinir(zorla := false) -> void:
	var ist := istenen_fps()
	if ist == _istenen and not zorla:
		return
	_istenen = ist
	var yenileme := DisplayServer.screen_get_refresh_rate() if DisplayServer.get_name() != "headless" else 60.0
	Engine.max_fps = sinir_sec(ist, yenileme)


func _oto_acik() -> bool:
	var p: Node = main.get("profile")
	return p != null and bool(p.settings.get("kalite_oto", false)) and int(p.settings.get("kalite", 1)) <= 1


func _process(delta: float) -> void:
	_kontrol_t += delta
	if _kontrol_t >= 0.25:
		_kontrol_t = 0.0
		_uygula_sinir()
		_ayar_izle()
	_olcek_yumusat(delta)
	# Otomatik kalite örneklemesi: yalnız 3D dünya çizilirken, tam hızda (sakin/arka plan sınırı bilerek düşük)
	if arka or not bool(main.get("playing")) or _istenen < FPS_AKTIF or not _oto_acik():
		_pencere_t = 0.0
		_pencere_n = 0
		return
	ornekle(delta)


# Bir karelik süre (sn). Pencere dolunca ölçülen kare hızı hedefle karşılaştırılır.
func ornekle(delta: float) -> void:
	if _bekle > 0.0:
		_bekle -= delta
		return
	if delta > 0.5:
		return  # tek seferlik takılma (yükleme, geri dönüş) ısınma işareti değil
	_pencere_t += delta
	_pencere_n += 1
	if _pencere_t < PENCERE:
		return
	var olculen := float(_pencere_n) / _pencere_t
	var hedef := float(Engine.max_fps) if Engine.max_fps > 0 else 60.0
	_pencere_t = 0.0
	_pencere_n = 0
	if olculen < hedef * TOLERANS:
		_kotu += 1
	else:
		_kotu = 0
	if log_ac:
		print("[isi] olculen %.1f hedef %.0f kotu=%d kademe=%d" % [olculen, hedef, _kotu, kademe])
	if _kotu >= KOTU_PENCERE_SAYISI:
		_kotu = 0
		asagi()


# Bir kademe düşür (çözünürlük, sonra gölge). Geri çıkmaz: ısınan telefon soğuyana kadar kalite oynamasın;
# ayardan kalite seçilince ya da uygulama yeniden açılınca sıfırlanır.
func asagi() -> bool:
	if kademe >= OLCEK_KADEMELERI.size() - 1:
		return false
	kademe += 1
	_carpan_hedef = OLCEK_KADEMELERI[kademe]
	if kademe >= GOLGE_KADEMESI and not Dunya.golge_kapali:
		Dunya.golge_kapali = true
		Dunya.golge_kes(main)
	_bekle = KARENCE
	if log_ac:
		print("[isi] kademe %d: olcek carpani %.2f golge_kapali=%s" % [kademe, _carpan_hedef, str(Dunya.golge_kapali)])
	return true


# Ölçek ani zıplamasın: çarpan 0,05'lik adımlarla her 0,25 sn'de hedefe yaklaşır.
func _olcek_yumusat(delta: float) -> void:
	if is_equal_approx(Dunya.oto_carpan, _carpan_hedef):
		return
	_olcek_t += delta
	if _olcek_t < 0.25:
		return
	_olcek_t = 0.0
	Dunya.oto_carpan = move_toward(Dunya.oto_carpan, _carpan_hedef, 0.05)
	main.get_viewport().scaling_3d_scale = Dunya.olcek(Dunya.olcek_taban)


# Oyuncu ayarlardan kaliteyi değiştirdiyse otomatik düşüşler sıfırlanır (yeni seçim geçerli olsun).
func _ayar_izle() -> void:
	var p: Node = main.get("profile")
	if p == null:
		return
	var imza := "%s/%s" % [str(p.settings.get("kalite", 1)), str(p.settings.get("kalite_oto", false))]
	if imza == _ayar_imza:
		return
	var ilk := _ayar_imza == ""
	_ayar_imza = imza
	if ilk or (kademe == 0 and Dunya.oto_carpan >= 0.999 and not Dunya.golge_kapali):
		return
	kademe = 0
	_carpan_hedef = 1.0
	Dunya.oto_carpan = 1.0
	Dunya.golge_kapali = false
	_kotu = 0
	_bekle = KARENCE
	if main.get("player") != null and bool(main.get("hazir_mi")):
		main.apply_settings()
