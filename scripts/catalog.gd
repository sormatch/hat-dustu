# Karakter seçenekleri, mağaza fiyatları (elmas) ve hareketler (emote).
extends RefCounted

const SKIN := ["#f1c9a5", "#e0ac83", "#c68a62", "#a8704d", "#7d4f32", "#5a3622"]
const HAIR_COLORS := ["#1c1a18", "#4a3020", "#8a5a32", "#d4a85a", "#b8b4ac", "#a3341f", "#2f4fa8", "#d84a8a"]
const EYE_COLORS := ["#4a2e1a", "#1a1a1a", "#3a7bd5", "#3f8f4a", "#8a6a2a", "#7a8a96"]

# Her kategori: [kimlik, görünen ad, fiyat]. Fiyatı 0 olanlar herkese açık.
const ITEMS := {
	"sac": [
		["kisa", "Kısa", 0], ["asker", "Asker tıraşı", 0], ["kel", "Kel", 0],
		["uzun", "Uzun", 60], ["atkuyrugu", "At kuyruğu", 60], ["mohawk", "Mohawk", 80],
		["kivircik", "Kıvırcık", 80], ["bere", "Bere", 120],
	],
	"kas": [
		["duz", "Düz", 0], ["kalin", "Kalın", 0], ["kizgin", "Kızgın", 0], ["uzgun", "Üzgün", 0],
	],
	"sakal": [
		["yok", "Yok", 0], ["biyik", "Bıyık", 0], ["keci", "Keçi sakal", 40], ["sakal", "Gür sakal", 60],
	],
	"kiyafet": [
		["turuncu", "Turuncu tulum", 0], ["gri", "Gri tulum", 0], ["mavi", "Mavi tulum", 100],
		["beyaz", "Beyaz tulum", 100], ["kirmizi", "Kırmızı tulum", 120], ["cizgili", "Çizgili", 150],
		["kamuflaj", "Kamuflaj", 250], ["altin", "Altın tulum", 500],
	],
	"aksesuar": [
		["yok", "Yok", 0], ["bant", "Yara bandı", 30], ["gozluk", "Gözlük", 70],
		["gunes", "Güneş gözlüğü", 120], ["zincir", "Altın zincir", 300],
	],
	"hareket": [
		["selam", "El salla", 0], ["super", "Süper", 0], ["isaret", "Şuraya bak", 40],
		["omuz", "Bilmem", 50], ["alkis", "Alkış", 50], ["off", "Off...", 60],
		["selamla", "Asker selamı", 80], ["dans", "Dans", 150],
	],
}

# Hareket yaparken kafanın üstünde çıkan yazı
const EMOTE_TEXT := {
	"selam": "Selam!", "super": "Süper!", "isaret": "Şuraya bak!", "omuz": "Bilmem...",
	"alkis": "Bravo!", "off": "Off...", "selamla": "Emredersin!", "dans": "Dans!",
}

const CATEGORY_NAMES := {
	"ten": "Ten", "sac": "Saç", "sac_renk": "Saç rengi", "goz": "Göz", "kas": "Kaş",
	"sakal": "Sakal", "kiyafet": "Kıyafet", "aksesuar": "Aksesuar", "hareket": "Hareketler",
}

const OUTFIT_COLORS := {
	"turuncu": "#B4501A", "gri": "#6b6e72", "mavi": "#2f4f86", "beyaz": "#d9d6cf",
	"kirmizi": "#8f1d1d", "cizgili": "#d9d6cf", "kamuflaj": "#4f5a3a", "altin": "#c9a227",
}

const DEFAULT_LOOK := {
	"ten": 1, "sac": "kisa", "sac_renk": 0, "goz": 0, "kas": "duz",
	"sakal": "yok", "kiyafet": "turuncu", "aksesuar": "yok",
}


static func price(category: String, id: String) -> int:
	for it in ITEMS.get(category, []):
		if it[0] == id:
			return it[2]
	return 0


static func item_name(category: String, id: String) -> String:
	for it in ITEMS.get(category, []):
		if it[0] == id:
			return it[1]
	return id


# Rastgele ama herkese açık parçalardan bir görünüş (karşı tarafın verisi bozuksa da kullanılır).
static func random_look() -> Dictionary:
	var free := func(cat: String) -> String:
		var opts := []
		for it in ITEMS[cat]:
			if it[2] == 0:
				opts.append(it[0])
		return opts[randi() % opts.size()]
	return {
		"ten": randi() % SKIN.size(), "sac": free.call("sac"), "sac_renk": randi() % HAIR_COLORS.size(),
		"goz": randi() % EYE_COLORS.size(), "kas": free.call("kas"), "sakal": free.call("sakal"),
		"kiyafet": free.call("kiyafet"), "aksesuar": "yok",
	}


# Ağdan gelen görünüşü güvenli hale getirir: bilinmeyen değerler varsayılana döner.
static func sanitize(look) -> Dictionary:
	var out := DEFAULT_LOOK.duplicate()
	if typeof(look) != TYPE_DICTIONARY:
		return out
	out.ten = clampi(int(look.get("ten", 1)), 0, SKIN.size() - 1)
	out.sac_renk = clampi(int(look.get("sac_renk", 0)), 0, HAIR_COLORS.size() - 1)
	out.goz = clampi(int(look.get("goz", 0)), 0, EYE_COLORS.size() - 1)
	for cat in ["sac", "kas", "sakal", "kiyafet", "aksesuar"]:
		var v := str(look.get(cat, out[cat]))
		for it in ITEMS[cat]:
			if it[0] == v:
				out[cat] = v
	return out
