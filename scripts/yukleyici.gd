# Oyunun ilk sahnesi (project.godot run/main_scene). Çok küçüktür: yalnız açılış perdesini (acilis.gd) kurar, ana
# sahneyi (main.tscn ve bütün kod/varlık bağımlılıkları) ARKA PLANDA yükler. Önceden main.tscn doğrudan açılırken
# yüklenme süresince (masaüstünde ~3,5 sn, telefonda daha uzun) ekranda hareketsiz açılış resmi duruyordu: oyun
# donmuş sanılıyordu. Şimdi bu sürede amblem animasyonu oynar, yükleme çubuğu dolar.
# Yükleme bitince ana sahne kurulur ve perde ona devredilir (main.gd _ready: "perde" meta'sı); dünya kademeli
# kurulurken aynı perde akmaya devam eder.
extends Node

const AcilisScript := preload("res://scripts/acilis.gd")
const ANA := "res://main.tscn"

var perde: CanvasLayer
var _bitti := false


var _olc := OS.get_cmdline_user_args().has("acilis_olc=1")


func _ready() -> void:
	if _olc:
		print("[acilis] yukleyici hazir: motor acilisindan %d ms" % Time.get_ticks_msec())
	perde = AcilisScript.new()
	add_child(perde)
	# karakter animasyonları ve gövde parçaları yan iş parçacığında hazırlanır (ilk karakter kurulurken donmasın)
	var gorev := WorkerThreadPool.add_task(func() -> void: load("res://scripts/model_body.gd").onbellek_hazirla(), false, "govde_onbellek")
	perde.set_meta("govde_gorev", gorev)
	if ResourceLoader.load_threaded_request(ANA, "", true) != OK:
		_kur(load(ANA))  # iş parçacığı açılamadıysa eski yol (bekler ama açılır)


func _process(_delta: float) -> void:
	if _bitti:
		return
	var ilerleme := []
	match ResourceLoader.load_threaded_get_status(ANA, ilerleme):
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if not ilerleme.is_empty():
				perde.call("ilerle", 0.07 * float(ilerleme[0]))
		ResourceLoader.THREAD_LOAD_LOADED:
			if _olc:
				print("[acilis] ana sahne arka planda yuklendi: %d ms" % Time.get_ticks_msec())
			_kur(ResourceLoader.load_threaded_get(ANA))
		_:
			_kur(load(ANA))


func _kur(sahne: PackedScene) -> void:
	_bitti = true
	set_process(false)
	var t0 := Time.get_ticks_msec()
	var ana := sahne.instantiate()
	if _olc:
		print("[acilis] ana sahne kopyasi: %d ms" % (Time.get_ticks_msec() - t0))
	ana.set_meta("perde", perde)  # main.gd perdeyi kendine alır (yeniden kurmaz, animasyon kesilmez)
	get_tree().root.add_child(ana)
	get_tree().current_scene = ana  # menüye dönüşteki reload_current_scene main.tscn'i yeniden kursun
	queue_free()
