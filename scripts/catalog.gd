# Karakter seçenekleri, mağaza fiyatları (elmas) ve hareketler (emote).
extends RefCounted

const SKIN := ["#f1c9a5", "#e0ac83", "#c68a62", "#a8704d", "#7d4f32", "#5a3622"]
const HAIR_COLORS := ["#1c1a18", "#4a3020", "#8a5a32", "#d4a85a", "#b8b4ac", "#a3341f", "#2f4fa8", "#d84a8a"]
const EYE_COLORS := ["#4a2e1a", "#1a1a1a", "#3a7bd5", "#3f8f4a", "#8a6a2a", "#7a8a96"]

# Her kategori: [kimlik, görünen ad, fiyat]. Fiyatı 0 olanlar herkese açık.
# Sunucudaki server/src/ekonomi.js ITEMS listesi bununla AYNI olmalı (kimlik ve fiyat).
const ITEMS := {
	"govde": [["erkek", "Erkek", 0], ["kadin", "Kadın", 0], ["iri", "İri yarı", 0], ["yasli", "Yaşlı kurt", 0], ["kadin_iri", "Kalıplı kadın", 0], ["ince", "Sırık", 0]],
	"sac": [
		["kisa", "Kısa", 0], ["asker", "Asker tıraşı", 0], ["kel", "Kel", 0], ["kazi", "Kazıma", 0],
		["uzun_duz", "Uzun düz", 0], ["kazi_k", "Kısa kazıma", 30], ["topuz", "Topuz", 40], ["ayrik", "Yana taralı", 40],
		["uzun", "Uzun", 60], ["atkuyrugu", "At kuyruğu", 60], ["mohawk", "Mohawk", 80],
		["kivircik", "Kıvırcık", 80],
		["dalgali", "Dalgalı kısa", 40], ["yandan", "Yandan ayrık", 40], ["kut", "Küt kesim", 90], ["orgu", "Örgü", 150],
		["yuksek_kuyruk", "Yüksek at kuyruğu", 90], ["yan_orgu", "Yan örgü", 100], ["cift_topuz", "Çift topuz", 110],
		["ikiz_orgu", "İkiz örgü", 120], ["rasta", "Rasta", 180],
	],
	"kas": [
		["duz", "Düz", 0], ["kalin", "Kalın", 0], ["kizgin", "Kızgın", 0], ["uzgun", "Üzgün", 0],
	],
	"sakal": [
		["yok", "Yok", 0], ["biyik", "Bıyık", 0], ["kirli", "Kirli sakal", 0], ["keci", "Keçi sakal", 40], ["sakal", "Gür sakal", 60],
		["ince", "İnce bıyık", 30], ["favori", "Favori", 40], ["zincir", "Çene sakalı", 50], ["pala", "Pala bıyık", 90],
		["dolgun", "Dolgun sakal", 120], ["uzun", "Uzun sakal", 150],
	],
	"kiyafet": [
		["turuncu", "Turuncu tulum", 0], ["gri", "Gri tulum", 0], ["mavi", "Mavi tulum", 100],
		["beyaz", "Beyaz tulum", 100], ["kirmizi", "Kırmızı tulum", 120], ["cizgili", "Çizgili", 150],
		["kamuflaj", "Kamuflaj", 250], ["altin", "Altın tulum", 500],
		["siyah", "Siyah", 100], ["yesil", "Yeşil", 100], ["sari", "Sarı", 100], ["pembe", "Pembe", 120], ["mor", "Mor", 120],
		["kot", "Kot", 150], ["puantiye", "Puantiyeli", 160], ["ekose", "Ekose", 180], ["neon", "Neon yeşil", 200],
		["leopar", "Leopar", 300],
		["no1337", "Numaralı tulum", 60], ["kirli", "Kirli tulum", 40], ["revir", "Revir önlüğü", 50], ["esofman", "Eşofman", 90],
		["yirtik", "Yırtık tulum", 110], ["hirka", "Hırka", 120], ["firari", "Firari ceketi", 220], ["gardiyan", "Gardiyan üniforması", 450],
	],
	"sapka": [
		["yok", "Yok", 0], ["bere", "Siyah bere", 40], ["ponpon", "Ponponlu bere", 60], ["kep", "Kep", 60],
		["ters_kep", "Ters kep", 80], ["bandana", "Bandana", 70], ["baret", "Baret", 90], ["kulaklik", "Kulaklık", 120],
		["fotr", "Fötr şapka", 150], ["tac", "Kral tacı", 600],
		["asci", "Aşçı şapkası", 50], ["parti", "Parti şapkası", 40], ["tilki", "Tilki kulakları", 90], ["kapuson", "Kapüşon", 100],
		["kask", "Asker kaskı", 120], ["kovboy", "Kovboy şapkası", 140], ["korsan", "Korsan şapkası", 160], ["hale", "Melek halesi", 400],
	],
	"dovme": [
		["yok", "Yok", 0], ["gozyasi", "Gözyaşı", 40], ["kalp", "Kalp", 60], ["gul", "Gül", 80],
		["orumcek", "Örümcek ağı", 80], ["kafatasi", "Kafatası", 100], ["kartal", "Kartal", 150],
		["ejderha", "Ejderha", 200], ["kaplan", "Kaplan", 250],
	],
	"aksesuar": [
		["yok", "Yok", 0], ["bant", "Yara bandı", 30], ["gozluk", "Gözlük", 70],
		["gunes", "Güneş gözlüğü", 120], ["zincir", "Altın zincir", 300],
		["kurdan", "Kürdan", 30], ["maske", "Maske", 40], ["fiyonk", "Fiyonk", 50], ["nerd", "Kalın çerçeve", 60],
		["burun", "Hızma", 80], ["kupe", "Halka küpe", 90], ["kunye", "Künye", 100], ["goz_bandi", "Göz bandı", 110],
		["kalp", "Kalp gözlük", 130], ["kulaklik_boyun", "Boyun kulaklığı", 140], ["pilot", "Pilot gözlüğü", 150],
		["monokl", "Monokl", 200], ["kupe_elmas", "Pırlanta küpe", 220], ["inci", "İnci kolye", 260],
		["saat", "Kol saati", 60], ["anahtar", "Anahtarlık", 50], ["yuz_bandana", "Yüz bandanası", 70], ["kelepce", "Kelepçe", 90],
		["canta", "Sırt çantası", 110], ["gitar", "Sırtta gitar", 240],
	],
	"hareket": [
		["selam", "El salla", 0], ["super", "Süper", 0], ["evet", "Evet", 0], ["hayir", "Hayır", 0],
		["isaret", "Şuraya bak", 40], ["omuz", "Bilmem", 50], ["alkis", "Alkış", 50], ["off", "Off...", 60],
		["selamla", "Asker selamı", 80], ["dans", "Dans", 150],
		["konus", "Anlat", 30], ["comel", "Çömel", 30], ["gul", "Gül", 40], ["dusun", "Düşün", 40], ["kollar", "Kollar bağlı", 40],
		["gozcu", "Gözcü", 50], ["tuh", "Tüh!", 50], ["telefon", "Telefonda", 60], ["agla", "Ağla", 60], ["kiz", "Kız", 60],
		["ic", "Şerefe", 70], ["firlat", "Fırlat", 80], ["yumruk", "Yumruk", 90], ["zombi", "Zombi", 140],
		["buyu", "Büyü", 150], ["takla", "Takla", 160], ["bayil", "Bayıl", 180], ["dans2", "Çılgın dans", 200],
		["kasin", "Kaşın", 40], ["sula", "Çiçek sula", 50], ["odun", "Odun kır", 60], ["it", "İttir", 70], ["sandik", "Sandık aç", 80],
		["tamir", "Tamir et", 90], ["kalk", "Yerden kalk", 100], ["boks", "Boks", 120], ["ninja", "Ninja", 200],
	],
}

# Hareket yaparken kafanın üstünde çıkan yazı
const EMOTE_TEXT := {
	"selam": "Selam!", "super": "Süper!", "isaret": "Şuraya bak!", "omuz": "Bilmem...",
	"alkis": "Bravo!", "off": "Off...", "selamla": "Emredersin!", "dans": "Dans!",
	"evet": "Evet!", "hayir": "Hayır!", "konus": "Bak şimdi...", "comel": "Bekliyorum...", "gul": "Hahaha!",
	"dusun": "Hmm...", "kollar": "Hıh.", "gozcu": "Kim var orada?", "tuh": "Tüh!", "telefon": "Alo?",
	"agla": "Hüüü...", "kiz": "Grrr!", "ic": "Şerefe!", "firlat": "Al bakalım!", "yumruk": "Gel bakalım!",
	"zombi": "Beyiiin...", "buyu": "Abrakadabra!", "takla": "Hop!", "bayil": "Bayıldım...", "dans2": "Parti!",
	"kasin": "Of, kaşınıyor!", "sula": "Büyü güzelim...", "odun": "Hıh! Hıh!", "it": "Çekil yoldan!", "sandik": "Hazine!",
	"tamir": "Bir dakika...", "kalk": "Ben iyiyim!", "boks": "Gel bakalım!", "ninja": "Hiyaa!",
}

const CATEGORY_NAMES := {
	"ten": "Ten", "sac": "Saç", "sac_renk": "Saç rengi", "goz": "Göz", "kas": "Kaş",
	"sakal": "Sakal", "kiyafet": "Kıyafet", "aksesuar": "Aksesuar", "hareket": "Hareketler",
	"vitrin": "Vitrin", "sandik": "Sandık", "sapka": "Şapka", "dovme": "Dövme", "govde": "Karakter",
}

# Kıyafet tarifi: üst (gövde) rengi, alt (bacak) rengi, kol (0 = kollu, 1 = çıplak kol, 2 = kısa kol),
# desenler (0 düz, 1 çizgili, 2 kamuflaj, 3 altın, 4 kot, 5 ekose, 6 leopar, 7 puantiye)
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
	"esofman": {"ust": "#1f2a44", "alt": "#1f2a44", "ud": 8, "ad": 8, "vurgu": "#e8e6df"},
	"gardiyan": {"ust": "#26344f", "alt": "#14171c", "model": "ranger", "baski": 2, "vurgu": "#d9b25a"},
	"revir": {"ust": "#9cc7b6", "alt": "#9cc7b6"},
	"askeri": {"ust": "#56603f", "alt": "#4f5a3a", "kol": 2, "ad": 2},
	"siyah": {"ust": "#1d1f24", "alt": "#1d1f24"},
	"yesil": {"ust": "#2f6b3a", "alt": "#2f6b3a"},
	"sari": {"ust": "#d9a92a", "alt": "#d9a92a"},
	"pembe": {"ust": "#e06a9a", "alt": "#e06a9a"},
	"mor": {"ust": "#5b3b8c", "alt": "#5b3b8c"},
	"kot": {"ust": "#3b5a8a", "alt": "#2e4670", "ud": 4, "ad": 4},
	"puantiye": {"ust": "#2a2f6b", "alt": "#2a2f6b", "ud": 7, "ad": 7},
	"ekose": {"ust": "#a32b2b", "alt": "#3a2a2a", "ud": 5},
	"neon": {"ust": "#3cf06e", "alt": "#1d1f24"},
	"leopar": {"ust": "#d29a45", "alt": "#d29a45", "ud": 6, "ad": 6},
	# ek alanlar: kir / yirtik (0..1), baski (1 mahkum numarası, 2 gardiyan rozeti), vurgu (şerit/baskı rengi),
	# model "ranger" (Quaternius ranger kıyafeti: ceket, kemerler, bot), desen 99 = dokunun kendi renkleri, 8 eşofman, 9 hırka
	"no1337": {"ust": "#B4501A", "alt": "#B4501A", "baski": 1, "vurgu": "#16181c"},
	"kirli": {"ust": "#a9552a", "alt": "#a9552a", "kir": 1.0},
	"yirtik": {"ust": "#6b6e72", "alt": "#5d6064", "yirtik": 1.0, "kir": 0.5},
	"hirka": {"ust": "#7a5a3c", "alt": "#3a3d44", "ud": 9},
	"firari": {"ust": "#5d6b3a", "alt": "#3b3f2a", "model": "ranger", "ud": 99, "ad": 99},
}

const OUTFIT_COLORS := {
	"turuncu": "#B4501A", "gri": "#6b6e72", "mavi": "#2f4f86", "beyaz": "#d9d6cf",
	"kirmizi": "#8f1d1d", "cizgili": "#d9d6cf", "kamuflaj": "#4f5a3a", "altin": "#c9a227",
	"atlet": "#ece8de", "tisort": "#f0efe9", "esofman": "#1c1e23", "gardiyan": "#26344f", "revir": "#9cc7b6", "askeri": "#56603f",
	"siyah": "#1d1f24", "yesil": "#2f6b3a", "sari": "#d9a92a", "pembe": "#e06a9a", "mor": "#5b3b8c", "kot": "#3b5a8a",
	"puantiye": "#2a2f6b", "ekose": "#a32b2b", "neon": "#3cf06e", "leopar": "#d29a45",
	"no1337": "#B4501A", "kirli": "#a9552a", "yirtik": "#6b6e72", "hirka": "#7a5a3c", "firari": "#5d6b3a",
}

const DEFAULT_LOOK := {
	"govde": "erkek", "ten": 1, "sac": "kisa", "sac_renk": 0, "goz": 0, "kas": "duz",
	"sakal": "yok", "kiyafet": "turuncu", "aksesuar": "yok", "sapka": "yok", "dovme": "yok",
}


# Satın alınabilen her şey: [kategori, kimlik, ad, fiyat]
static func shop_items() -> Array:
	var out := []
	for cat in ["sac", "sakal", "kiyafet", "aksesuar", "sapka", "dovme", "hareket"]:
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


# Nadirlik fiyattan gelir: [üst sınır, ad, renk] (sunucudaki server/src/ekonomi.js rarity() ile aynı sınırlar)
const RARITY := [
	[60, "SIRADAN", "#8b93a7"], [120, "NADİR", "#3b9cff"], [250, "EPİK", "#b05cff"], [100000, "EFSANE", "#ffb020"],
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
		"govde": free.call("govde"), "ten": randi() % SKIN.size(), "sac": free.call("sac"), "sac_renk": randi() % HAIR_COLORS.size(),
		"goz": randi() % EYE_COLORS.size(), "kas": free.call("kas"), "sakal": free.call("sakal"),
		"kiyafet": free.call("kiyafet"), "aksesuar": "yok", "sapka": "yok", "dovme": "yok",
	}


# Ağdan gelen görünüşü güvenli hale getirir: bilinmeyen değerler varsayılana döner.
static func sanitize(look) -> Dictionary:
	var out := DEFAULT_LOOK.duplicate()
	if typeof(look) != TYPE_DICTIONARY:
		return out
	out.ten = clampi(int(look.get("ten", 1)), 0, SKIN.size() - 1)
	out.sac_renk = clampi(int(look.get("sac_renk", 0)), 0, HAIR_COLORS.size() - 1)
	out.goz = clampi(int(look.get("goz", 0)), 0, EYE_COLORS.size() - 1)
	for cat in ["govde", "sac", "kas", "sakal", "kiyafet", "aksesuar", "sapka", "dovme"]:
		var v := str(look.get(cat, out[cat]))
		for it in ITEMS[cat]:
			if it[0] == v:
				out[cat] = v
	return out
