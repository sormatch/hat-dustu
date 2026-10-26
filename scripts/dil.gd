# Dil desteği (Türkçe / English). Kaynak dil Türkçe: çeviri anahtarı Türkçe metnin kendisidir
# (translations/en.po, msgid = Türkçe). Label/Button gibi düğümler .text'i kendiliğinden çevirir;
# biçimli metinlerde çeviri biçimlemeden ÖNCE yapılır: tr("%d/%d yazdı") % [a, b]
# Statik betiklerde tr() yok: Dil.t("...") kullan.
#
# Sunucu mesajları: sabit metinler istemcide çevrilir. Değişkenli metinlerde sunucu "<alan>_k" ile
# şablon parçaları gönderir: [[şablon, [değerler]], ...] (ör. m_k: [["{0} geri döndü.", ["Ali"]]]).
# Dil.sunucu(d, "m") bunları çevirip birleştirir; _k yoksa d.m'yi çevirir (eski sunucuyla da çalışır).
extends RefCounted

const DILLER := ["tr", "en"]
const ADLAR := {"tr": "Türkçe", "en": "English"}


# Oyunun şu anki dili: "tr" ya da "en"
static func kod() -> String:
	var l := TranslationServer.get_locale().substr(0, 2)
	return l if l in DILLER else "en"


static func tr_mi() -> bool:
	return kod() == "tr"


static func t(s: String) -> String:
	return TranslationServer.translate(s)


# Açılışta dili seç: test parametresi (dil=en) > ayarlarda seçilen > cihaz dili (Türkçe değilse İngilizce).
static func baslat(profile: Node) -> void:
	var d := str(profile.settings.get("dil", ""))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("dil="):
			d = a.substr(4)
	if not d in DILLER:
		d = "tr" if OS.get_locale_language() == "tr" else "en"
	TranslationServer.set_locale(d)


# Ayarlardan dil değişti: kaydet ve anında uygula.
static func ayarla(profile: Node, d: String) -> void:
	if not d in DILLER:
		return
	profile.settings["dil"] = d
	profile.save()
	TranslationServer.set_locale(d)
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		preload("res://scripts/ui.gd").sigdir_hepsi(tree.root)


# Büyük harf: Türkçede i -> İ, ı -> I; İngilizcede düz.
static func buyuk(s: String) -> String:
	if tr_mi():
		return s.replace("i", "İ").replace("ı", "I").to_upper()
	return s.to_upper()


# Sunucudan gelen metni bu dile çevirir (bkz. dosya başı).
static func sunucu(d: Dictionary, alan := "m") -> String:
	var parcalar = d.get(alan + "_k")
	if parcalar is Array and not (parcalar as Array).is_empty():
		var out := PackedStringArray()
		for p in parcalar:
			if p is Array and not (p as Array).is_empty():
				var args: Array = []
				if (p as Array).size() > 1 and p[1] is Array:
					for x in p[1]:
						# değerler (ad, kullanıcı adı, sayı) çevrilmez
						args.append(str(int(x)) if (x is float and x == floorf(x)) else str(x))
				out.append(t(str(p[0])).format(args))
			elif p is String:
				out.append(t(p))
		return " ".join(out)
	return t(str(d.get(alan, "")))


# Gizlilik / koşullar sayfasının bu dildeki bölümü (sayfada TR üstte, EN altta #en çapasında).
static func yasal_ek() -> String:
	return "" if tr_mi() else "#en"
