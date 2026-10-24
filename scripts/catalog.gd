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
		["dalgali", "Dalgalı kısa", 40], ["yandan", "Yandan ayrık", 40], ["kut", "Küt kesim", 90], ["orgu", "Örgü", 150],
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
	"vitrin": "Vitrin", "sandik": "Sandık",
}

# Kıyafet tarifi: üst (gövde) rengi, alt (bacak) rengi, kol (0 = kollu, 1 = çıplak kol, 2 = kısa kol),
# desenler (0 düz, 1 çizgili, 2 kamuflaj, 3 altın, 4 kot)
const OUTFITS := {
	"turuncu": {"ust": "#B4501A", "alt": "#B4501A"},
	"gri": {"ust": "#6b6e72", "alt": "#6b6e72"},
	"mavi": {"ust": "#2f4f86", "alt": "#2f4f86"},
	"beyaz": {"ust": "#d9d6cf", "alt": "#d9d6cf"},
	"kirmizi": {"ust": "#8f1d1d", "alt": "#8f1d1d"},
	"cizgili": {"ust": "#d9d6cf", "alt": "#d9d6cf", "ud": 1, "ad": 1},
	"kamuflaj": {"ust": "#4f5a3a", "alt": "#4f5a3a", "ud": 2, "ad": 2},
	"altin": {"ust": "#c9a227", "alt": "#c9a227", "ud": 3, "ad": 3},
	"atlet": {"ust": "#ece8de", "alt": "#B4501A", "kol": 1},
	"tisort": {"ust": "#f0efe9", "alt": "#3b5a8a", "kol": 2, "ad": 4},
	"esofman": {"ust": "#1c1e23", "alt": "#24272d"},
	"gardiyan": {"ust": "#26344f", "alt": "#14171c"},
	"revir": {"ust": "#9cc7b6", "alt": "#9cc7b6"},
	"askeri": {"ust": "#56603f", "alt": "#4f5a3a", "kol": 2, "ad": 2},
}

const OUTFIT_COLORS := {
	"turuncu": "#B4501A", "gri": "#6b6e72", "mavi": "#2f4f86", "beyaz": "#d9d6cf",
	"kirmizi": "#8f1d1d", "cizgili": "#d9d6cf", "kamuflaj": "#4f5a3a", "altin": "#c9a227",
	"atlet": "#ece8de", "tisort": "#f0efe9", "esofman": "#1c1e23", "gardiyan": "#26344f", "revir": "#9cc7b6", "askeri": "#56603f",
}

const DEFAULT_LOOK := {
	"ten": 1, "sac": "kisa", "sac_renk": 0, "goz": 0, "kas": "duz",
	"sakal": "yok", "kiyafet": "turuncu", "aksesuar": "yok",
}


# Satın alınabilen her şey: [kategori, kimlik, ad, fiyat]
static func shop_items() -> Array:
	var out := []
	for cat in ["sac", "sakal", "kiyafet", "aksesuar", "hareket"]:
		for it in ITEMS[cat]:
			if it[2] > 0:
				out.append([cat, it[0], it[1], it[2]])
	return out


# Günün fırsatları: her gün aynı 4 ürün, %30-50 indirimli (tarihten türetilir, herkes aynısını görür).
# Dönen öğe: [kategori, kimlik, ad, eski fiyat, indirim yüzdesi, yeni fiyat]
static func daily_deals(date: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("vitrin" + date)
	var pool := shop_items()
	var out := []
	for i in 4:
		var it: Array = pool.pop_at(rng.randi() % pool.size())
		var off: int = [30, 40, 50][rng.randi() % 3]
		out.append(it + [off, int(round(it[3] * (100 - off) / 100.0 / 5.0) * 5)])
	return out


# Nadirlik fiyattan gelir: [üst sınır, ad, renk]
const RARITY := [
	[0, "SIRADAN", "#8b93a7"], [80, "NADİR", "#3b9cff"], [150, "EPİK", "#b05cff"], [100000, "EFSANE", "#ffb020"],
]


static func rarity(p: int) -> Array:
	for r in RARITY:
		if p <= r[0]:
			return r
	return RARITY[0]


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
