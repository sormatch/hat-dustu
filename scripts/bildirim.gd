# Oyun kapalıyken hatırlatma bildirimleri (yerel; sunucu yok): günde 2 (13:00 ve 20:30), önümüzdeki 3 gün.
# Uygulama açılınca hepsi iptal edilir, arka plana geçince / kapanınca yeniden kurulur: oynayan kişiye bildirim
# gitmez, 3 gün hiç açmayan kişiye de bildirim yağmaz. Yakın zamanda oynadıysa (2 saatten yakın) o saat atlanır.
# Eklenti: addons/NotificationSchedulerPlugin (godot-notification-scheduler v6.0, MIT). Eklenti yoksa (bilgisayar,
# eklentisiz Android paketi) hiçbir şey yapmaz.
# İzin: ilk maç bittikten sonra sorulur (iOS sistem penceresi; Android 13+ izni).
extends Node

const KANAL := "hatirlatma"
const ID_BAS := 700
const GUN := 3
const SAATLER := [[13, 0], [20, 30]]
const METINLER := [
	["Hat seni bekliyor ☎️", "Arkadaşlarını topla, Kim Kim'de karşındakinin kim olduğunu bul!"],
	["Gardiyan devriyede 🔦", "Bu akşam kaçış planı kurmaya ne dersin? Bir oda kur, ekibini çağır."],
	["Aranızda bir yalancı var 🎩", "Oda kur, kodu arkadaşlarına at, kimin yalan söylediğini bul."],
	["Günlük görevlerin yenilendi 💎", "Gel, görevleri bitir, elmasları topla."],
	["Işıklar sönmeden bir maç daha? 🌙", "Arkadaşlarınla sesli konuş, telefonu kap, oyunu kazan."],
	["Ekibini topla 👥", "Hat Düştü arkadaşlarla daha eğlenceli: oda kur ve davet et."],
	["Rulet masası hazır 🎲", "Şansına güveniyor musun? Gel bir el oyna."],
	["Kim aradı? 📞", "Sesini tanıyan kazanır. Kim Kim'de bugün kaç kişiyi bilirsin?"],
]

var _ns: Node = null
var _hazir := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not (OS.get_name() in ["iOS", "Android"]) or not Engine.has_singleton("NotificationSchedulerPlugin"):
		return
	var betik: Script = load("res://addons/NotificationSchedulerPlugin/NotificationScheduler.gd")
	if betik == null:
		return
	_ns = betik.new()
	add_child(_ns)
	_ns.initialization_completed.connect(_ilk)
	_ns.initialize()


func _ilk() -> void:
	_hazir = true
	if OS.get_name() == "Android":
		var kanal_b: Script = load("res://addons/NotificationSchedulerPlugin/model/NotificationChannel.gd")
		var k = kanal_b.new()
		k.set_id(KANAL).set_name("Hatırlatmalar").set_description("Oyuna dönmen için günde en çok 2 hatırlatma")
		_ns.create_notification_channel(k)
	_iptal()  # oyun açık: bekleyen hatırlatmalar silinir


# İlk maç bittikten sonra bir kez: bildirim izni (iOS: sistem penceresi).
func izin_iste(profile: Node) -> void:
	if not _hazir or bool(profile.settings.get("bildirim_soruldu", false)):
		return
	profile.settings["bildirim_soruldu"] = true
	profile.save()
	if not _ns.has_post_notifications_permission():
		_ns.request_post_notifications_permission()


func _notification(what: int) -> void:
	if not _hazir:
		return
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			_kur()
		NOTIFICATION_APPLICATION_RESUMED:
			_iptal()


func _iptal() -> void:
	for i in GUN * SAATLER.size():
		_ns.cancel(ID_BAS + i)
	_ns.set_badge_count(0)


func _kur() -> void:
	if not _ns.has_post_notifications_permission():
		return
	_iptal()
	var veri_b: Script = load("res://addons/NotificationSchedulerPlugin/model/NotificationData.gd")
	var simdi := int(Time.get_unix_time_from_system())
	# yerel saat: sistem saat dilimi farkı (dakika)
	var fark := int(Time.get_time_zone_from_system().get("bias", 180)) * 60
	var yerel := simdi + fark
	var gun_bas := yerel - (yerel % 86400)
	var sira := int(simdi / 86400) % METINLER.size()  # her gün farklı metinlerle başla
	var n := 0
	for g in GUN:
		for s in SAATLER:
			var an := gun_bas + g * 86400 + int(s[0]) * 3600 + int(s[1]) * 60
			var gecikme := an - yerel
			if gecikme < 2 * 3600:
				continue  # geçmiş saat ya da az önce oynadı
			var m: Array = METINLER[(sira + n) % METINLER.size()]
			var d = veri_b.new()
			d.set_id(ID_BAS + n).set_channel_id(KANAL).set_title(str(m[0])).set_content(str(m[1])) \
				.set_small_icon_name("ic_stat_notification").set_delay(gecikme)
			_ns.schedule(d)
			n += 1
