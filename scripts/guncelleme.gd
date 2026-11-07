# Güncelleme denetimi: oyun açılınca mağazadaki sürüme bakılır; daha yenisi varsa "GÜNCELLEME VAR" penceresi,
# GÜNCELLE düğmesi mağaza sayfasını açar. Oturum başına bir kez.
#   iOS: App Store'un herkese açık sürüm sorgusu (itunes.apple.com/lookup) — yeni sürüm yayınlanınca kendiliğinden.
#   Android: https://hatdustu.app/surum.json {"android": "1.0.x", "android_url": "..."} (site/surum.json; yeni
#            APK siteye konunca bu dosyadaki sürüm de artırılır).
#   Masaüstü: denetlenmez. Test: guncelleme_test=1 (bilgisayarda pencere sahte sürümle açılır).
extends Node

const UI := preload("res://scripts/ui.gd")
const IOS_SORGU := "https://itunes.apple.com/lookup?bundleId=com.sormatch.hatdustu&country=tr"
const IOS_URL := "https://apps.apple.com/tr/app/id6827360852"
const ANDROID_SORGU := "https://hatdustu.app/surum.json"
const ANDROID_URL := "https://hatdustu.app/indir/hatdustu.apk"

var _http: HTTPRequest


func _ready() -> void:
	var test := OS.get_cmdline_user_args().has("guncelleme_test=1")
	var ios := OS.get_name() == "iOS"
	if not test and not ios and OS.get_name() != "Android":
		return
	await get_tree().create_timer(4.0).timeout  # açılış ve giriş bitsin
	if test:
		_goster("9.9.9", IOS_URL)
		return
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_geldi.bind(ios))
	_http.request((IOS_SORGU if ios else ANDROID_SORGU) + ("&" if ios else "?") + "t=%d" % Time.get_unix_time_from_system())


func _geldi(sonuc: int, kod: int, _b: PackedStringArray, govde: PackedByteArray, ios: bool) -> void:
	if sonuc != HTTPRequest.RESULT_SUCCESS or kod != 200:
		return
	var d: Variant = JSON.parse_string(govde.get_string_from_utf8())
	if not (d is Dictionary):
		return
	var yeni := ""
	var url := IOS_URL if ios else ANDROID_URL
	if ios:
		var r: Array = d.get("results", []) if d.get("results") is Array else []
		if r.is_empty() or not (r[0] is Dictionary):
			return
		yeni = str(r[0].get("version", ""))
		url = str(r[0].get("trackViewUrl", IOS_URL))
	else:
		yeni = str(d.get("android", ""))
		url = str(d.get("android_url", ANDROID_URL))
	var bu := str(ProjectSettings.get_setting("application/config/version", "0"))
	if yeni != "" and daha_yeni(yeni, bu):
		_goster(yeni, url)


# "1.0.10" > "1.0.9" gibi sayı sayı karşılaştırma
static func daha_yeni(a: String, b: String) -> bool:
	var x := a.split(".")
	var y := b.split(".")
	for i in maxi(x.size(), y.size()):
		var p := int(x[i]) if i < x.size() else 0
		var q := int(y[i]) if i < y.size() else 0
		if p != q:
			return p > q
	return false


func _goster(yeni: String, url: String) -> void:
	var m := UI.modal("GÜNCELLEME VAR", 620.0)
	m.body.add_child(UI.label(tr("Hat Düştü'nün yeni sürümü (%s) hazır. Yeni özellikler ve düzeltmeler için oyunu güncelle.") % yeni, UI.FS_METIN, UI.METIN, true))
	var sat := HBoxContainer.new()
	sat.add_theme_constant_override("separation", UI.B_M)
	sat.alignment = BoxContainer.ALIGNMENT_CENTER
	m.body.add_child(sat)
	var sonra := UI.button("SONRA", "ikincil", UI.BTN_H_KUCUK, UI.FS_ORTA, "", 200)
	sonra.pressed.connect(m.close)
	sat.add_child(sonra)
	var git := UI.button("GÜNCELLE", "ana", UI.BTN_H_KUCUK, UI.FS_ORTA, "", 260)
	git.pressed.connect(func() -> void:
		OS.shell_open(url)
		m.close())
	sat.add_child(git)
	var kat := CanvasLayer.new()
	kat.layer = 60
	get_tree().root.add_child(kat)
	kat.add_child(m)
	m.closed.connect(kat.queue_free)
