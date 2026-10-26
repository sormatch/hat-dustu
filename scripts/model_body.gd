# Oyuncu karakteri: gerçek iskeletli insan modelleri + animasyonlar. body.gd ile aynı arayüzü kullanır.
# Gövdeler (look.govde):
#   "erkek" / "kadin": Quaternius Universal Base Characters (CC0) kafası + Modular Character Outfits (CC0)
#                      kıyafeti (gömlek, pantolon, çizme); kıyafet rengi/deseni gölgelendiriciyle boyanır.
#   Bilinmeyen/eski değerler (ör. eski "mahkum" modeli kaldırıldı) erkek gövdesine düşer.
# Bütün modeller ve animasyonlar içe aktarılırken aynı insansı profile (assets/karakter/mixamo_profil.tres)
# yeniden hedeflenir: kemik adları her gövdede "mixamorig_*" olur, animasyonlar (Mixamo + Quaternius UAL +
# koddan üretilenler) her gövdede oynar. Saç, sakal, şapka, aksesuar ve dövme kafa/el kemiklerine takılır.
extends "res://scripts/body.gd"

const ANIMS := ["durma", "yurume", "kosma", "oturma", "selam", "super", "isaret", "omuz", "alkis", "off", "selamla", "dans"]
const LOOPS := ["durma", "yurume", "kosma", "oturma"]
# Quaternius Universal Animation Library (CC0) animasyonları: oyundaki ad -> dosya (assets/karakter/anim_ual)
const UAL := {
	"dans2": "Dance", "konus": "Idle_Talking", "comel": "Crouch_Idle", "comel_yuru": "Crouch_Fwd",
	"bayil": "Death01", "yumruk": "Punch_Cross", "buyu": "Spell_Simple_Shoot", "takla": "Roll",
	"evet": "Yes", "hayir": "Idle_No", "kollar": "Idle_FoldArms", "telefon": "Idle_TalkingPhone",
	"ic": "Consume", "zombi": "Zombie_Idle", "gozcu": "Idle_Rail_Call", "firlat": "OverhandThrow",
	"sula": "Farm_Watering", "odun": "TreeChopping", "it": "Push", "sandik": "Chest_Open", "tamir": "Fixing_Kneeling",
	"kalk": "LayToIdle", "ninja": "NinjaJump_Start",
}
# Döngülü hareketler bu kadar saniye sürer (döngüsüzler animasyon bitince biter)
const EMOTE_LEN := {"dans2": 5.0, "konus": 4.0, "hayir": 2.5, "kollar": 4.0, "telefon": 4.5, "zombi": 4.0, "comel": 4.0,
	"odun": 3.9, "it": 4.0}
# Birkaç UAL animasyonu art arda: tek hareket (boks: sol direkt, sol direkt, sağ direkt, kroşe)
const COMBOS := {
	"boks": ["Punch_Jab", "Punch_Jab", "Punch_Cross", "Melee_Hook"],
	"kasin": ["Zombie_Scratch", "Zombie_Scratch"],
}
const Hair := preload("res://scripts/hair.gd")
const CARD_STYLES := ["kisa", "uzun", "atkuyrugu", "mohawk", "kivircik"]  # tel tel saç kartlarıyla
const Hats := preload("res://scripts/hats.gd")
const Acc := preload("res://scripts/aksesuar.gd")
const Emotes := preload("res://scripts/hareketler.gd")
const Dunya := preload("res://scripts/dunya.gd")
const GovdeDuzen := preload("res://scripts/govde_duzen.gd")
# Dövme yeri ve boyu (metre): yuz = göz altı, kafa = kafanın yanı (şakak/kulak üstü), el = sağ elin üstü
const TATTOO_PLACE := {
	"gozyasi": ["yuz", 0.026], "kalp": ["el", 0.07], "kafatasi": ["el", 0.07], "gul": ["kafa", 0.075],
	"orumcek": ["kafa", 0.08], "kartal": ["kafa", 0.095], "ejderha": ["kafa", 0.095], "kaplan": ["kafa", 0.09],
}
const TATTOO_FILE := {"orumcek": "orumcek_agi"}
const DECAL_LAYER := 1 << 10  # dövme sadece vücut modeline yapışsın (saç/şapka değil)
# Karakterler dünya katmanında (1) değil kendi katmanlarında çizilir: duvar lekeleri (Decal, cull_mask = 1)
# ve sadece dünyayı aydınlatması gereken ışıklar (light_cull_mask = 1, ör. bilgisayar ekranının yeşil ışığı)
# karaktere vurmasın. Kameralar ve diğer ışıklar bütün katmanları gördüğü için başka bir şey değişmez.
const CHAR_LAYER := 1 << 11
static var _ink := {}

const G := "res://assets/govde/"
# CC0 gövdeler: giysi = iskelet + kıyafet parçaları (kafa yok), bas = kafası alınan tam gövde modeli.
const BODIES := {
	"erkek": {
		"giysi": G + "kiyafet/Male_Peasant.gltf", "bas": G + "Superhero_Male_FullBody.gltf",
		"ten": [G + "T_Superhero_Male_Ligh.png", G + "T_Superhero_Male_Dark.png"],
		"ten_n": G + "T_Superhero_Male_Normal.png", "ten_r": G + "T_Superhero_Male_Roughness.png",
		"el": G + "kiyafet/T_Regular_Male_Dark_BaseColor.png", "el_n": G + "kiyafet/T_Regular_Male_Normal.png",
		"kas": G + "T_Hair_1_BaseColor.png", "olcek": 0.955,
		"ranger": G + "kiyafet/Male_Ranger.gltf",
	},
	"kadin": {
		"giysi": G + "kiyafet/Female_Peasant.gltf", "bas": G + "Superhero_Female_FullBody.gltf",
		"ten": [G + "T_Superhero_Female_Light_BaseColor.png", G + "T_Superhero_Female_Dark_BaseColor.png"],
		"ten_n": G + "T_Superhero_Female_Normal.png", "ten_r": G + "T_Superhero_Female_Roughness.png",
		"el": G + "kiyafet/T_Regular_Female_Dark_BaseColor.png", "el_n": G + "kiyafet/T_Regular_Female_Normal.png",
		"kas": G + "T_Hair_2_BaseColor.png", "olcek": 0.97,
		"ranger": G + "kiyafet/Female_Ranger.gltf",
	},
}
# Gövde tipleri: bir tabanın (erkek/kadin) kafası ve kıyafeti kullanılır; kıyafet meshi bağlama pozunda
# şekillendirilir (metre: gövde/kol/bacak şişirme, göbek öne), boy (olcek) ve duruş (kambur) değişir.
# Kafa aynı kaldığı için saç, şapka, sakal ve yüz aksesuarları tabanınkiyle aynı oturur.
# yas: yüzde kırışıklık + kır kaş (yalnız erkek yüz dokusunun UV yerleri ölçüldü).
const TYPES := {
	"iri": {"taban": "erkek", "olcek": 0.975, "sekil": {"govde": 0.042, "gobek": 0.06, "kol": 0.024, "bacak": 0.024}},
	"yasli": {"taban": "erkek", "olcek": 0.94, "sekil": {"govde": 0.006, "gobek": 0.034, "kol": -0.004, "bacak": -0.004}, "kambur": 1.0, "yas": 1.0},
	"kadin_iri": {"taban": "kadin", "olcek": 0.98, "sekil": {"govde": 0.032, "gobek": 0.04, "kol": 0.02, "bacak": 0.026}},
	"ince": {"taban": "erkek", "olcek": 0.99, "sekil": {"govde": -0.011, "gobek": -0.012, "kol": -0.006, "bacak": -0.006}},
}
const CLOTH_TEX := G + "kiyafet/T_Peasant_BaseColor.png"
const CLOTH_N := G + "kiyafet/T_Peasant_Normal.png"
const CLOTH_ORM := G + "kiyafet/T_Peasant_ORM.png"
# Ranger kıyafeti (gardiyan üniforması, firari ceketi, kapüşon): yeşil kumaş boyanır, deri koyu kalır
const RANGER_TEX := G + "kiyafet/T_Ranger_BaseColor.png"
const RANGER_N := G + "kiyafet/T_Ranger_Normal.png"
const RANGER_ORM := G + "kiyafet/T_Ranger_ORM.png"
# Kıyafet baskıları (mahkum numarası, gardiyan yazısı): tools/baski_uret.gd üretir
const PRINT_TEX := "res://assets/govde/kiyafet/baski.png"
const EYE_TEX := G + "T_Eye_Brown.png"

# CC0 gövdelerin teni: doku, seçilen ten rengine göre boyanır (dokunun ortalama ten rengine oranla).
# Yüz dokusundaki boyalı saç gölgesi ve kirli sakal seçime göre tene karışır.
const SKIN_SHADER := """
shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform sampler2D nrm : hint_normal, filter_linear_mipmap;
uniform sampler2D rgh : hint_default_white, filter_linear_mipmap;
uniform vec3 tint = vec3(1.0);
uniform vec3 base_avg = vec3(0.7, 0.5, 0.4);
uniform float stubble = 1.0;  // yüzdeki boyalı kirli sakal (0 = temiz yüz)
uniform float scalp = 1.0;  // kafa derisindeki boyalı saç gölgesi (0 = ten)
uniform vec4 face_box = vec4(0.0, 0.0, 0.36, 0.38);  // dokuda yüz bölgesi (x0, y0, x1, y1)
uniform vec3 hair_col = vec3(0.1);
uniform float age = 0.0;  // yaşlı yüz: kırışıklıklar (erkek yüz dokusunun UV yerleri)

float seg_d(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

float wrinkles(vec2 uv) {
	float w = 0.0;
	// alın çizgileri (ortada yukarı kavisli)
	for (int i = 0; i < 3; i++) {
		float dx = uv.x - 0.183;
		float vy = 0.101 + float(i) * 0.0135 + dx * dx * 2.2 + sin(uv.x * 140.0 + float(i)) * 0.0012;
		float span = 1.0 - smoothstep(0.045, 0.072, abs(dx));
		w += (1.0 - smoothstep(0.0009, 0.0028, abs(uv.y - vy))) * span * (0.9 - float(i) * 0.2);
	}
	// kaz ayakları: gözlerin dış köşeleri
	for (int s = 0; s < 2; s++) {
		float sx = s == 0 ? -1.0 : 1.0;
		vec2 c = s == 0 ? vec2(0.106, 0.176) : vec2(0.261, 0.176);
		for (int k = 0; k < 3; k++) {
			vec2 d = vec2(sx, (float(k) - 1.0) * 0.55) * 0.02;
			w += (1.0 - smoothstep(0.0007, 0.002, seg_d(uv, c, c + d))) * 0.7;
		}
		// burun kenarından ağız köşesine (nazolabial çizgi)
		vec2 a = s == 0 ? vec2(0.161, 0.232) : vec2(0.206, 0.232);
		vec2 b = s == 0 ? vec2(0.147, 0.276) : vec2(0.220, 0.276);
		w += (1.0 - smoothstep(0.001, 0.0045, seg_d(uv, a, b))) * 0.85;
		// göz altı torbası
		vec2 e = s == 0 ? vec2(0.132, 0.176) : vec2(0.2355, 0.176);
		vec2 q = (uv - e) * vec2(1.0, 1.7);
		w += (1.0 - smoothstep(0.0008, 0.003, abs(length(q) - 0.03))) * step(e.y + 0.004, uv.y) * 0.55;
	}
	return clamp(w, 0.0, 1.0);
}

void fragment() {
	vec3 c = texture(tex, UV).rgb;
	vec3 o = c * tint;
	if (UV.x > face_box.x && UV.x < face_box.z && UV.y > face_box.y && UV.y < face_box.w) {
		// dokuya boyanmış saç gölgesi ve kirli sakal gri/düşük doygunluktadır: önce tene çevrilir,
		// sonra seçime göre saç renginde yeniden boyanır
		float lum = dot(c, vec3(0.3, 0.59, 0.11));
		float blum = dot(base_avg, vec3(0.3, 0.59, 0.11));
		float mx = max(c.r, max(c.g, c.b));
		float sat = (mx - min(c.r, min(c.g, c.b))) / max(mx, 0.001);
		float bmx = max(base_avg.r, max(base_avg.g, base_avg.b));
		float bsat = (bmx - min(base_avg.r, min(base_avg.g, base_avg.b))) / max(bmx, 0.001);
		float gray = clamp((bsat - sat) / (bsat * 0.55), 0.0, 1.0);
		float fy = (UV.y - face_box.y) / (face_box.w - face_box.y);
		float is_scalp = smoothstep(0.34, 0.2, fy);
		float is_jaw = smoothstep(0.56, 0.72, fy);
		vec3 clean = base_avg * tint * clamp(lum / blum, 0.6, 1.15);
		vec3 painted = mix(clean, hair_col * (0.35 + lum * 0.8), 0.7);
		float a_s = is_scalp * gray;
		float a_j = is_jaw * gray;
		o = mix(o, clean, clamp(a_s + a_j, 0.0, 1.0));
		o = mix(o, painted, clamp(a_s * scalp + a_j * stubble, 0.0, 1.0));
	}
	if (age > 0.0) {
		o *= 1.0 - wrinkles(UV) * 0.38 * age;
		o = mix(o, vec3(dot(o, vec3(0.3, 0.59, 0.11))), 0.12 * age);  // biraz solgun
	}
	ALBEDO = o;
	NORMAL_MAP = texture(nrm, UV).rgb;
	ROUGHNESS = texture(rgh, UV).r * 0.9 + 0.08;
	SPECULAR = 0.35;
}
"""

# Kıyafet: kumaş dokusu gri tonlara çevrilip seçilen renge boyanır; deri (kemer, çizme) kahverengi kalır.
# pattern: 0 düz, 1 çizgili, 2 kamuflaj, 3 altın, 4 kot, 5 ekose, 6 leopar, 7 puantiye, 8 eşofman (yan şerit),
#   9 hırka (örgü + önde düğmeli açıklık), 99 dokunun kendi renkleri
# Ekler (desenle birlikte): kir (lekeler), yirtik (ten görünen yırtıklar), baski (1 mahkum numarası, 2 gardiyan rozeti)
# mode: 0 köylü kıyafeti (açık renkli gömlek kumaşı boyanır), 1 ranger (yeşil kumaş boyanır, deri koyu, metal kalır)
# Desenler bağlama pozundaki köşe yerine (CUSTOM0) göre çizilir: kol/bacak oynarken desen kumaşın üstünde kaymaz.
const CLOTH_SHADER := """
shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform sampler2D nrm : hint_normal, filter_linear_mipmap;
uniform sampler2D orm : hint_default_white, filter_linear_mipmap;
uniform sampler2D prints : source_color, filter_linear_mipmap;
uniform vec3 color : source_color = vec3(0.7, 0.31, 0.1);
uniform vec3 accent : source_color = vec3(0.92, 0.92, 0.9);  // şerit / baskı rengi
uniform vec3 skin : source_color = vec3(0.8, 0.6, 0.45);
uniform int pattern = 0;
uniform int part = 0;  // 0 üst (gömlek, kollar), 1 pantolon, 2 ayakkabı
uniform int mode = 0;
uniform float kir = 0.0;
uniform float yirtik = 0.0;
uniform int baski = 0;
uniform float back_y = 1.3;  // sırt baskısının yüksekliği (model uzayı)
uniform float chest_y = 1.36;
varying vec3 lpos;
varying vec3 lnrm;
varying float glove;  // eldiven (köşe rengi siyah işaretli)

void vertex() {
	lpos = CUSTOM0.xyz;
	lnrm = CUSTOM1.xyz;
	glove = 1.0 - COLOR.r;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) { return noise(p) * 0.6 + noise(p * 2.3) * 0.3 + noise(p * 5.1) * 0.1; }

// baskı dokusundan bir bölge: r = bölge (x0, y0, x1, y1; 0..1), q = bölge içi 0..1
vec4 print_a(vec4 r, vec2 q) {
	if (q.x < 0.0 || q.x > 1.0 || q.y < 0.0 || q.y > 1.0) { return vec4(0.0); }
	return texture(prints, mix(r.xy, r.zw, q));
}

void fragment() {
	vec3 c = texture(tex, UV).rgb;
	vec3 m = texture(orm, UV).rgb;
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	// kumaş kıvrımları korunsun diye parlaklık, dokunun bulanık (yakın çevre ortalaması) haline oranlanır
	vec3 cb = textureLod(tex, UV, 5.0).rgb;
	float lb = max(dot(cb, vec3(0.3, 0.59, 0.11)), 0.015);
	float shade = clamp(lum / lb, 0.45, 1.6);
	float mx = max(cb.r, max(cb.g, cb.b));
	float sat = (mx - min(cb.r, min(cb.g, cb.b))) / max(mx, 0.001);
	float metal_part = 0.0;
	// boyanacak kısım: üstte açık renkli gömlek kumaşı, altta pantolon; deri (kemer, yelek, bilek, çizme) kalır
	float k = 1.0;
	if (mode == 1) {
		// ranger: yeşil baskın yerler kumaş; gri-beyaz (doygunluğu düşük, açık) yerler metal toka
		float mx2 = max(c.r, max(c.g, c.b));
		float sat2 = (mx2 - min(c.r, min(c.g, c.b))) / max(mx2, 0.001);
		k = smoothstep(0.0, 0.05, cb.g - max(cb.r, cb.b));
		metal_part = smoothstep(0.35, 0.5, lum) * (1.0 - smoothstep(0.12, 0.25, sat2)) * (1.0 - k);
		if (part == 2) { k = 0.0; }
	} else if (part == 0) {
		k = smoothstep(0.07, 0.13, lb) * (1.0 - smoothstep(0.65, 0.85, sat));
	} else if (part == 2) {
		k = 0.0;
	}
	vec3 base = color;
	float rough = 0.88;
	float metal = 0.0;
	if (pattern == 1) {
		base = mix(vec3(0.07), color, step(0.5, fract(lpos.y * 9.0)));
	} else if (pattern == 2) {
		float n = noise(lpos.xy * 9.0 + lpos.z * 3.0) + 0.5 * noise(lpos.zy * 17.0);
		// renkler sRGB yazıldı; ALBEDO doğrusal ister (yoksa kamuflaj solgun, beyaza yakın görünüyordu)
		vec3 camo = n > 0.95 ? vec3(0.17, 0.2, 0.13) : (n < 0.55 ? vec3(0.42, 0.36, 0.24) : vec3(0.31, 0.35, 0.23));
		base = pow(camo, vec3(2.2));
	} else if (pattern == 3) {
		rough = 0.28;
		metal = 0.9;
	} else if (pattern == 4) {
		base = color * (0.86 + 0.14 * sin((lpos.x + lpos.y + lpos.z) * 420.0));
	} else if (pattern == 5) {
		vec2 g = fract(vec2(lpos.x + lpos.z, lpos.y) * 7.0);
		float a = step(0.7, g.x) * 0.5 + step(0.7, g.y) * 0.5;
		base = mix(color, color * 0.35, a) + vec3(0.06) * step(0.93, max(g.x, g.y));
	} else if (pattern == 6) {
		vec2 q = vec2(lpos.x + lpos.z * 0.7, lpos.y) * 22.0;
		float n = noise(q);
		float spot = smoothstep(0.62, 0.66, n);
		float core = smoothstep(0.7, 0.74, n);
		base = mix(color, vec3(0.08, 0.06, 0.04), spot - core * 0.8);
	} else if (pattern == 7) {
		vec2 g = fract(vec2(lpos.x + lpos.z, lpos.y) * 16.0) - 0.5;
		base = mix(color, vec3(0.95, 0.93, 0.88), step(length(g), 0.18));
	} else if (pattern == 8) {
		// eşofman: kolların üstünden ve bacakların dış yanından inen şerit (bağlama pozu: kollar yanlara açık)
		float side = 0.0;
		if (part == 1) {
			side = smoothstep(0.93, 0.965, abs(lnrm.x)) * step(0.0, lpos.x * lnrm.x);
		} else if (abs(lpos.x) > 0.24) {
			side = smoothstep(0.94, 0.975, lnrm.y);
		} else {
			side = smoothstep(0.93, 0.97, abs(lnrm.x));
		}
		base = mix(color, accent, side);
		rough = 0.6;
	} else if (pattern == 9) {
		// hırka: dikey örgü kaburgası + önde koyu düğmeli açıklık
		float rib = 0.8 + 0.2 * smoothstep(0.2, 0.8, abs(sin((lpos.x + lpos.z * 0.4) * 260.0)));
		float row = 0.94 + 0.06 * sin(lpos.y * 520.0);
		base = color * rib * row;
		if (part == 0 && lnrm.z > 0.3 && abs(lpos.x) < 0.03) {
			float placket = 1.0 - smoothstep(0.012, 0.018, abs(lpos.x));
			base = mix(base, color * 0.55, placket);
			vec2 bq = vec2(lpos.x * 60.0, fract(lpos.y * 11.0) - 0.5);
			base = mix(base, vec3(0.86, 0.8, 0.66), (1.0 - smoothstep(0.12, 0.17, length(bq))) * placket);
		}
		rough = 0.97;
	}
	if (baski > 0 && part == 0) {
		// sırt: büyük numara (yalnız mahkum); göğüs solu: numara etiketi ya da rozet
		vec4 a = vec4(0.0);
		if (baski == 1 && lnrm.z < -0.3) {
			// sırttan bakınca x ters: yazı okunur olsun diye çevrilir
			a = print_a(vec4(0.24, 0.07, 0.76, 0.45), vec2(-lpos.x / 0.24 + 0.5, (back_y - lpos.y) / 0.085 + 0.5));
		}
		if (lnrm.z > 0.25) {
			if (baski == 1) {
				vec2 q = vec2((lpos.x - 0.085) / 0.095 + 0.5, (chest_y - lpos.y) / 0.05 + 0.5);
				float patch = step(0.0, q.x) * step(q.x, 1.0) * step(-0.12, q.y) * step(q.y, 1.12);
				base = mix(base, vec3(0.9, 0.88, 0.82), patch);
				k = max(k, patch);
				vec4 t = print_a(vec4(0.03, 0.62, 0.48, 0.88), q);
				a = t.a > a.a ? t : a;
			} else {
				vec2 qb = vec2((lpos.x - 0.085) / 0.075 + 0.5, (chest_y - lpos.y) / 0.088 + 0.5);
				vec4 t = print_a(vec4(0.65, 0.53, 0.85, 0.99), qb);
				a = t.a > a.a ? t : a;
			}
		}
		// baskı rengi = vurgu rengi x dokudaki ton (rozetin yıldızı koyu)
		base = mix(base, accent * a.rgb, a.a);
		metal = mix(metal, baski == 2 ? 0.85 : 0.0, a.a);
		rough = mix(rough, baski == 2 ? 0.3 : rough, a.a);
		k = max(k, a.a);
	}
	// deri kısımlar (kemer, yelek/korse, kol bantları) kıyafetin koyu tonuna, eldiven ve ayakkabılar siyah iş
	// botu tonuna boyanır: herkes tek parça mahkum kıyafetli görünsün
	vec3 dark = base * 0.68;  // desen de devam etsin: korse/yelek kıyafetin bir parçası gibi
	if (glove > 0.5 || part == 2) {
		dark = vec3(0.02, 0.02, 0.023);
	}
	if (mode == 1) {
		dark = vec3(0.035, 0.032, 0.03);  // ranger: deri kemer, bot ve kol koruması siyah
	}
	vec3 o = mix(dark * clamp(lum / lb, 0.55, 1.5), base * shade, k);
	rough = mix(0.55, rough, k);
	metal *= k;
	if (mode == 1 && metal_part > 0.0) {
		o = mix(o, c * vec3(0.95, 0.92, 0.85), metal_part);
		metal = mix(metal, 0.8, metal_part);
		rough = mix(rough, 0.35, metal_part);
	}
	// kir: büyük lekeler + paçalarda koyulaşma
	if (kir > 0.0) {
		float n = fbm(vec2(lpos.x * 5.0 + lpos.z * 3.1, lpos.y * 4.3)) * 0.5
			+ fbm(vec2(lpos.z * 4.7 - lpos.x * 2.3, lpos.y * 5.1 + 7.0)) * 0.5;
		float stain = smoothstep(0.5, 0.66, n);
		float low = part == 1 ? 1.0 - smoothstep(0.42, 0.8, lpos.y) : 0.0;  // dizler ve paçalar
		float grime = clamp(stain * 0.85 + low * 0.6, 0.0, 1.0) * kir;
		o = mix(o, o * vec3(0.42, 0.36, 0.27), grime);
		rough = mix(rough, 0.97, grime);
	}
	// yırtık: kumaşta düzensiz delikler, içinde ten, kenarları yıpranmış koyu iplik
	if (yirtik > 0.0 && k > 0.5 && glove < 0.5) {
		float n = fbm(vec2(lpos.x * 11.0 + lpos.z * 9.0, lpos.y * 9.0) + vec2(3.7, 1.3));
		float hole = smoothstep(0.735, 0.75, n) * yirtik;
		float edge = smoothstep(0.69, 0.725, n) * (1.0 - hole) * yirtik;
		o = mix(o, o * 0.45, edge);
		o = mix(o, skin * (0.7 + 0.3 * shade), hole);
		rough = mix(rough, 0.6, hole);
	}
	if (pattern == 99) { o = c; metal = 0.0; rough = 0.85; }
	ALBEDO = o;
	NORMAL_MAP = texture(nrm, UV).rgb;
	ROUGHNESS = rough * m.g + 0.05;
	METALLIC = metal;
	AO = m.r;
}
"""

# Göz: dokudaki kahverengi iris seçilen göz rengine boyanır.
const EYE_SHADER := """
shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec3 iris : source_color = vec3(0.3, 0.2, 0.1);
void fragment() {
	vec3 c = texture(tex, UV).rgb;
	float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	float d = length(UV - vec2(0.5, 0.5));
	float k = smoothstep(0.17, 0.13, d) * step(0.18, sat) * step(lum, 0.5);
	ALBEDO = mix(c, iris * (0.35 + lum * 1.6), k);
	ROUGHNESS = 0.08;
	SPECULAR = 0.7;
}
"""

static var _library: AnimationLibrary
static var _skin_shader: Shader
static var _cloth_shader: Shader
static var _eye_shader: Shader
static var _parts := {}  # govde -> kafa/göz/kaş parçaları (bir kez çıkarılır)
static var _avg := {}  # doku yolu -> ortalama ten rengi

var hide_head := false
var head_peek := false  # birinci şahıs gövdesinde kafa geçici görünür (hareket sırasında üçüncü şahıs kamera)
var crouched := false  # çömelme
var _head_bone := -1
var _player: AnimationPlayer
var _skel: Skeleton3D
var _current := ""
var _govde := "erkek"
var _taban := "erkek"  # gövde tipinin kafası/kıyafeti alınan taban (erkek/kadin)
var _ranger := false  # kıyafet ranger modelinden (gardiyan üniforması, firari ceketi)
var _spine2_y := 1.31  # göğüs kemiği yüksekliği (baskı yerleri)
var _cloth_mats: Array = []  # [malzeme, bölüm (0 üst, 1 pantolon, 2 ayakkabı)]


static func _get_library() -> AnimationLibrary:
	if _library:
		return _library
	_library = AnimationLibrary.new()
	for n in ANIMS:
		var path := "res://assets/karakter/anim/%s.fbx" % n
		if not ResourceLoader.exists(path):
			continue
		var inst: Node = load(path).instantiate()
		var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
		var anim: Animation = ap.get_animation(ap.get_animation_list()[0]).duplicate()
		anim.loop_mode = Animation.LOOP_LINEAR if n in LOOPS else Animation.LOOP_NONE
		_add_pinky(anim)
		_library.add_animation(n, anim)
		inst.free()
	for id in UAL:
		var path := "res://assets/karakter/anim_ual/%s.res" % UAL[id]
		if ResourceLoader.exists(path):
			var anim: Animation = (load(path) as Animation).duplicate()
			anim.loop_mode = Animation.LOOP_LINEAR if EMOTE_LEN.has(id) or id == "comel_yuru" else Animation.LOOP_NONE
			_library.add_animation(id, anim)
	for id in COMBOS:
		var combo := _concat(COMBOS[id])
		if combo:
			_library.add_animation(id, combo)
	# koddan üretilen hareketler (gülme, ağlama, kızma...) duruş animasyonunun üstüne kurulur
	if _library.has_animation("durma"):
		for id in Emotes.IDS:
			_library.add_animation(id, Emotes.make(id, _library.get_animation("durma")))
	return _library


# UAL animasyonlarını art arda ekler (aynı iskelet izleri; her parça bir öncekinin bittiği yerden başlar).
static func _concat(names: Array) -> Animation:
	var out := Animation.new()
	var t0 := 0.0
	for n in names:
		var path := "res://assets/karakter/anim_ual/%s.res" % n
		if not ResourceLoader.exists(path):
			return null
		var a: Animation = load(path)
		for ti in a.get_track_count():
			var p := a.track_get_path(ti)
			var ty := a.track_get_type(ti)
			var oi := out.find_track(p, ty)
			if oi < 0:
				oi = out.add_track(ty)
				out.track_set_path(oi, p)
				out.track_set_interpolation_type(oi, a.track_get_interpolation_type(ti))
			for k in a.track_get_key_count(ti):
				out.track_insert_key(oi, t0 + a.track_get_key_time(ti, k) + (0.0001 if k == 0 and t0 > 0.0 else 0.0), a.track_get_key_value(ti, k))
		t0 += a.length
	out.length = t0
	out.loop_mode = Animation.LOOP_NONE
	return out


# Mixamo animasyonlarında serçe parmak yok (4 parmaklı iskeletle indirildi): yüzük parmağının hareketi kopyalanır.
static func _add_pinky(anim: Animation) -> void:
	for side in ["Left", "Right"]:
		for j in [1, 2, 3]:
			var ring := NodePath("%%GeneralSkeleton:mixamorig_%sHandRing%d" % [side, j])
			var pinky := NodePath("%%GeneralSkeleton:mixamorig_%sHandPinky%d" % [side, j])
			var t := anim.find_track(ring, Animation.TYPE_ROTATION_3D)
			if t < 0 or anim.find_track(pinky, Animation.TYPE_ROTATION_3D) >= 0:
				continue
			var nt := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(nt, pinky)
			for k in anim.track_get_key_count(t):
				anim.rotation_track_insert_key(nt, anim.track_get_key_time(t, k), anim.track_get_key_value(t, k))


func _build() -> void:
	if _rig:
		_rig.queue_free()
	_rig = Node3D.new()
	add_child(_rig)
	_cloth_mats.clear()
	_govde = str(look.get("govde", "erkek"))
	if not BODIES.has(_govde) and not TYPES.has(_govde):
		_govde = "erkek"
	_taban = base_of(_govde)
	var model := _build_cc0(_govde)
	model.rotation.y = PI  # modeller +z'ye bakıyor, oyunda karakterler -z'ye bakar
	# boy ~1,75 m kalsın: kamera, oturma ve kol hizaları buna göre ayarlı (gövde tipleri birkaç yüzde farklı)
	model.scale = Vector3.ONE * float(body_def(_govde).olcek)
	_rig.add_child(model)
	if not _player.has_animation_library("hd"):
		_player.add_animation_library("hd", _get_library())
	_apply_colors()
	_head_bone = _skel.find_bone("mixamorig_Head")
	if hide_head:
		_player.mixer_applied.connect(func() -> void:
			_skel.set_bone_pose_scale(_head_bone, Vector3.ONE if head_peek else Vector3.ONE * 0.001))
		if not head_peek:
			for mi in model.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_current = ""
	_play("durma")
	if not hide_head:
		# ekranda (ya da hemen kenarında) olmayan karakterin animasyonu durur: iskelet güncellemesi ve deri
		# (skinning) hesabı yapılmaz. Başka hücredeki oyuncular çoğu zaman görünmez; görününce kaldığı yerden sürer.
		# Kutu gövdeden geniş: kadrajın hemen dışındaki karakterin gölgesi donmasın.
		var vis := VisibleOnScreenNotifier3D.new()
		vis.aabb = AABB(Vector3(-1.5, -0.5, -1.5), Vector3(3.0, 3.2, 3.0))
		vis.screen_exited.connect(func() -> void:
			if is_instance_valid(_player):
				_player.active = false)
		vis.screen_entered.connect(func() -> void:
			if is_instance_valid(_player):
				_player.active = true)
		_rig.add_child(vis)
	_char_layers(_rig)
	_attach_head_props.call_deferred()


# CC0 gövde: kıyafet modelinin iskeletine (gövde ölçüleri) aynı setin kafası, gözleri ve kaşları takılır.
func _build_cc0(id: String) -> Node3D:
	var def := body_def(id)
	var outfit: Dictionary = Catalog.OUTFITS.get(look.get("kiyafet", "turuncu"), Catalog.OUTFITS.turuncu)
	_ranger = str(outfit.get("model", "")) == "ranger"
	var path: String = def.ranger if _ranger else def.giysi
	var model: Node3D = load(path).instantiate()
	_skel = model.find_children("*", "Skeleton3D", true, false)[0]
	var parts := _head_info(_taban)
	# kafa tepesi kemiği (Mixamo iskeletlerindeki gibi): taç ve maç sonu ekranı bunu kullanır
	if _skel.find_bone("mixamorig_HeadTop_End") < 0:
		var head := _skel.find_bone("mixamorig_Head")
		_skel.add_bone("mixamorig_HeadTop_End")
		var top := _skel.get_bone_count() - 1
		_skel.set_bone_parent(top, head)
		var tp: Vector3 = parts.head
		_skel.set_bone_rest(top, Transform3D(Basis(), (parts.bind as Transform3D) * Vector3(tp.x, float(parts.top), tp.z)))
		_skel.reset_bone_pose(top)
	# kıyafet meshlerine eldiven işareti (köşe rengi) + bağlama pozu bilgisi eklenmiş, gövde tipine göre
	# şekillendirilmiş kopyaları takılır. Ranger kıyafetinin omuz zırhı hiç, kapüşonu yalnız şapka seçilince görünür.
	var shape: Dictionary = def.get("sekil", {})
	var hood := str(look.get("sapka", "yok")) == "kapuson"
	var body_mi: MeshInstance3D = null
	for mi in _skel.get_children():
		if not mi is MeshInstance3D:
			continue
		var m := mi as MeshInstance3D
		var n := String(m.name)
		if n.contains("Pauldron") or (n.contains("Hood") and not hood):
			_skel.remove_child(m)
			m.free()
			continue
		m.mesh = _prepared(m.mesh, m.skin, shape, path + "|" + id)
		if n.ends_with("_Body"):
			body_mi = m
			var sb: Variant = _bind_of(m.skin, "mixamorig_Spine2")
			if sb != null:
				_spine2_y = (sb as Transform3D).affine_inverse().origin.y
	if _ranger and body_mi:
		# ranger kıyafetinin kemerleri ve kol korumaları gövde meshine katılır (aynı malzeme, aynı kemik listesi):
		# karakter başına 3 çizim çağrısı az
		var extra := []
		for mi in _skel.get_children():
			if mi is MeshInstance3D and (String(mi.name).contains("Belt") or String(mi.name).contains("Bracer")):
				extra.append(mi)
		var merged := _merged_skinned(body_mi, extra, path + "|" + id)
		if merged:
			body_mi.mesh = merged
			for e in extra:
				_skel.remove_child(e)
				e.free()
	if hood and not _ranger:
		var hp := _ranger_part(_taban, "Hood")
		if not hp.is_empty():
			var hm := MeshInstance3D.new()
			hm.name = "Kapuson"
			hm.mesh = _prepared(hp[0], hp[1], {}, "kapuson|" + _taban)
			hm.skin = hp[1]
			_skel.add_child(hm)
			hm.skeleton = NodePath("..")
	if def.has("kambur"):
		# yaşlı duruşu: animasyonun üstüne hafif kamburluk (el IK'sı bundan sonra çalışır)
		var dz := GovdeDuzen.new()
		dz.kambur = float(def.kambur)
		_skel.add_child(dz)
		_skel.move_child(dz, 0)
	for key in ["bas", "goz", "kas"]:
		if not parts.has(key):
			continue
		var p: Array = parts[key]
		var mi := MeshInstance3D.new()
		mi.name = {"bas": "Bas", "goz": "Goz", "kas": "Kas"}[key]
		mi.mesh = p[0]
		mi.skin = p[1]
		_skel.add_child(mi)
		mi.skeleton = NodePath("..")
	var band := _collar_band(path + "|" + id, parts, body_mi)
	if not band.is_empty():
		var bm := MeshInstance3D.new()
		bm.name = "Yaka"
		bm.mesh = band[0]
		bm.skin = band[1]
		_skel.add_child(bm)
		bm.skeleton = NodePath("..")
	_player = AnimationPlayer.new()
	model.add_child(_player)
	return model


static var _band_cache := {}

# Yaka bandı: kıyafetin yaka ağzı ile boyun arasındaki boşluğu (arkada ve yanlarda gövde ile kıyafet
# farklı modellerden geldiği için açılan aralık) kapatan ince, deri renkli bir halka. İç kenarı boyun
# kemiğine, dış kenarı göğüs kemiğine bağlı (deri gibi esner). Gövde başına bir kez kurulur.
static func _collar_band(id: String, parts: Dictionary, body: MeshInstance3D) -> Array:
	if _band_cache.has(id):
		return _band_cache[id]
	_band_cache[id] = []
	if not parts.has("neck_bind") or body == null or body.skin == null:
		return []
	var ob_neck: Variant = _bind_of(body.skin, "mixamorig_Neck")
	var ob_chest: Variant = _bind_of(body.skin, "mixamorig_Spine2")
	var verts: PackedVector3Array = body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	if ob_neck == null or ob_chest == null:
		return []
	# gövde (kafa) modelinin uzayından kıyafet modelinin uzayına: aynı boyun kemiği üzerinden
	var to_outfit: Transform3D = (ob_neck as Transform3D).affine_inverse() * (parts.neck_bind as Transform3D)
	var neck: Vector3 = to_outfit * (parts.neck_pos as Vector3)
	const N := 32
	# yaka ağzı: her yön diliminde kıyafetin en üst noktası
	var collar: Array = []
	collar.resize(N)
	for v in verts:
		var d := Vector2(v.x - neck.x, v.z - neck.z)
		if d.length() > 0.16 or v.y < neck.y - 0.12:
			continue
		var bi := int(fposmod(atan2(d.y, d.x) / TAU, 1.0) * N) % N
		if collar[bi] == null or v.y > (collar[bi] as Vector3).y:
			collar[bi] = v
	# boş dilimleri komşulardan doldur
	for pass_i in 3:
		for i in N:
			if collar[i] == null:
				collar[i] = collar[(i + 1) % N] if collar[(i + 1) % N] != null else collar[(i + N - 1) % N]
	for c in collar:
		if c == null:
			return []
	# boyun yüzeyi: kafa meshinde boyun kemiği hizasındaki halka (her dilimde en dıştaki nokta)
	var hv: PackedVector3Array = (parts.bas[0] as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var neck_r := PackedFloat32Array()
	neck_r.resize(N)
	for v0 in hv:
		var v := to_outfit * v0
		if absf(v.y - neck.y) > 0.02:
			continue
		var d := Vector2(v.x - neck.x, v.z - neck.z)
		if d.length() > 0.085:
			continue  # dizide kesilmiş omuz/gövde köşeleri de duruyor
		var bi := int(fposmod(atan2(d.y, d.x) / TAU, 1.0) * N) % N
		neck_r[bi] = maxf(neck_r[bi], d.length())
	for pass_i in 3:
		for i in N:
			if neck_r[i] <= 0.0:
				neck_r[i] = maxf(neck_r[(i + 1) % N], neck_r[(i + N - 1) % N])
	# İç kenarın ağırlıkları: boynun o noktadaki köşesininki (boyun kökü göğüs ve boyun kemiği arasında
	# karışık bağlı; iç kenar yalnız boyna bağlıyken baş yana dönünce bant boyundan ayrılıp aralık açıyordu).
	var bas_skin: Skin = parts.bas[1]
	var harr: Array = (parts.bas[0] as Mesh).surface_get_arrays(0)
	var hb: PackedInt32Array = harr[Mesh.ARRAY_BONES]
	var hw: PackedFloat32Array = harr[Mesh.ARRAY_WEIGHTS]
	var hper := hb.size() / maxi(1, hv.size())
	var adlar := ["mixamorig_Neck", "mixamorig_Spine2", "mixamorig_Head"]
	var bas_bind: Variant = _bind_of(body.skin, "mixamorig_Head")
	var ob_head: Variant = bas_bind if bas_bind != null else _bind_of(bas_skin, "mixamorig_Head")
	var esle := {}  # kafa skin'indeki kemik sırası -> bant skin'indeki sıra
	for bi in bas_skin.get_bind_count():
		var k := adlar.find(String(bas_skin.get_bind_name(bi)))
		if k >= 0:
			esle[bi] = k
	var huv: PackedVector2Array = harr[Mesh.ARRAY_TEX_UV]
	var hq := PackedVector3Array()  # kafa köşeleri kıyafet uzayında
	hq.resize(hv.size())
	for vi in hv.size():
		hq[vi] = to_outfit * hv[vi]
	# p'ye en yakın boyun köşesi (aynı yükseklik bandında); ağırlığı ve doku yeri banda kopyalanır
	var yakin := func(p: Vector3) -> int:
		var en := -1
		var ed := 1e9
		for vi in hq.size():
			if absf(hq[vi].y - p.y) > 0.035:
				continue
			var dd := hq[vi].distance_squared_to(p)
			if dd < ed:
				ed = dd
				en = vi
		return en
	var agirlik := func(en: int) -> Array:
		var w := [0.0, 0.0, 0.0]
		if en >= 0 and hper > 0:
			for k in hper:
				var bi: int = hb[en * hper + k]
				if esle.has(bi):
					w[esle[bi]] += hw[en * hper + k]
		var top: float = w[0] + w[1] + w[2]
		if top < 0.3:
			return [1.0, 0.0, 0.0]
		return [w[0] / top, w[1] / top, w[2] / top]
	var ring_up := []
	var ring_in := []
	var ring_out := []
	var ring_low := []
	var bilgi := [[], [], []]  # satır başına köşe: [ağırlık, uv]
	# doku yeri: ensedeki düz deri (her köşeye aynı; boyun dokusunun dikiş yerlerinde başka adaya atlamasın)
	var e_ense: int = yakin.call(neck + Vector3(0, -0.005, -maxf(neck_r[N * 3 / 4], 0.03)))
	var uv_ense: Vector2 = huv[e_ense] if e_ense >= 0 and e_ense < huv.size() else Vector2(0.5, 0.9)
	for i in N + 1:
		var a := TAU * (i % N + 0.5) / N
		var dir := Vector3(cos(a), 0, sin(a))
		var c: Vector3 = collar[i % N]
		var rc := Vector2(c.x - neck.x, c.z - neck.z).length()
		var rn := maxf(neck_r[i % N] * 0.97, 0.03)
		# iç kenarın üstünde boynun içinde gizli bir halka daha: baş dönünce boyun kökü kayar, bant yine kapatır
		ring_up.append(neck + dir * rn * 0.84 + Vector3(0, 0.03, 0))
		ring_in.append(neck + dir * rn * 0.92 + Vector3(0, -0.005, 0))
		# önde (yüz +z) yaka ağzı açık, göğüs derisi görünür: bant orada boynun içinde iner, göğsü delmez
		var on := clampf((dir.z - 0.2) / 0.5, 0.0, 1.0)
		ring_out.append(neck + dir * lerpf(maxf(rc * 0.86, rn), rn * 0.9, on) + Vector3(0, minf(c.y - neck.y, 0.03) - 0.03, 0))
		ring_low.append(neck + dir * lerpf(maxf(rc * 0.7, rn), rn * 0.85, on) + Vector3(0, minf(c.y - neck.y, 0.03) - 0.06, 0))
		var e_up: int = yakin.call(neck + dir * rn + Vector3(0, 0.03, 0))
		var e_in: int = yakin.call(neck + dir * rn + Vector3(0, -0.005, 0))
		var e_out: int = yakin.call(neck + dir * rn + Vector3(0, -0.02, 0))
		for r in 3:
			var en: int = [e_up, e_in, e_out][r]
			bilgi[r].append([agirlik.call(en) if r < 2 else [0.35, 0.65, 0.0], uv_ense])
	# 0. yüzey (deri, kafanın deri malzemesi ve dokusuyla): boyuna değen üst kısım, kesişim çizgisi görünmez.
	# 1. yüzey (koyu): yaka ağzından içeri inen kısım; arkada gölge gibi koyu, önde deri tonunda.
	var rows := [ring_up, ring_in, ring_out, ring_low]
	var am := ArrayMesh.new()
	for yuzey in 2:
		var st := SurfaceTool.new()
		st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for r in ([0, 1] if yuzey == 0 else [2]):
			for i in N:
				var q := [[r, i], [r, i + 1], [r + 1, i + 1], [r + 1, i]]
				var pts := []
				for e in q:
					pts.append(rows[e[0]][e[1]])
				var nrm := ((pts[1] - pts[0]) as Vector3).cross((pts[3] - pts[0]) as Vector3).normalized()
				for k in [0, 1, 2, 0, 2, 3]:
					var rr: int = q[k][0]
					var p: Vector3 = pts[k]
					var yan := Vector3(p.x - neck.x, 0.0, p.z - neck.z).normalized()
					var ww: Array = bilgi[rr][q[k][1]][0] if rr < 3 else [0.0, 1.0, 0.0]
					if yuzey == 0:
						# boyun gibi dışa bakan normal: ışıkta boyundan ayrı parlamaz
						st.set_normal((yan * 0.85 + Vector3.UP * 0.15).normalized())
						st.set_uv(bilgi[rr][q[k][1]][1])
					else:
						# yarı dışa bakan normal: yukarıdan gelen ışıkta parlayıp beyaz görünmesin
						st.set_normal((yan * 0.7 + Vector3.UP * 0.3).normalized())
						var ton: float = lerpf(0.88 if rr == 2 else 0.4, 0.9, clampf((yan.z + 0.1) / 0.5, 0.0, 1.0))
						st.set_color(Color(ton, ton, ton))
					st.set_bones(PackedInt32Array([0, 1, 2, 0]))
					st.set_weights(PackedFloat32Array([ww[0], ww[1], ww[2], 0.0]))
					st.add_vertex(p)
		st.commit(am)
	var skin := Skin.new()
	skin.add_named_bind("mixamorig_Neck", ob_neck)
	skin.add_named_bind("mixamorig_Spine2", ob_chest)
	skin.add_named_bind("mixamorig_Head", ob_head if ob_head != null else ob_neck)
	_band_cache[id] = [am, skin]
	return _band_cache[id]


static var _mask_cache := {}
const SHAPE_GROUPS := {
	"Hips": 1, "Spine": 1, "Spine1": 1, "Spine2": 1, "LeftShoulder": 1, "RightShoulder": 1,
	"LeftArm": 2, "RightArm": 2, "LeftForeArm": 2, "RightForeArm": 2,
	"LeftUpLeg": 3, "RightUpLeg": 3, "LeftLeg": 3, "RightLeg": 3,
}

# Kıyafet meshinin hazır kopyası (mesh + gövde tipi başına bir kez):
#  - köşe rengine işaret: beyaz = kumaş/deri, siyah = eldiven (bilekten sonrası, |x| > 0,56 m; T duruşu),
#  - CUSTOM0/CUSTOM1: bağlama pozundaki köşe yeri ve normali (desenler animasyonda kumaşın üstünde kaymasın),
#  - gövde tipi şekli (shape): köşeler kemik ağırlığına göre gövde/kol/bacak ekseninden dışarı itilir, göbek öne.
#    İtme yönü normalden değil yerden hesaplanır: üst üste binen parçalar (kemer, yaka, kol koruması) birlikte kayar.
static func _prepared(mesh: Mesh, skin: Skin, shape: Dictionary, key: String) -> Mesh:
	var ck := "%d|%s|%s" % [mesh.get_instance_id(), key, JSON.stringify(shape)]
	if _mask_cache.has(ck):
		return _mask_cache[ck]
	var groups := PackedByteArray()
	var ax := {}
	if not shape.is_empty() and skin:
		groups.resize(skin.get_bind_count())
		for i in skin.get_bind_count():
			var bn := String(skin.get_bind_name(i)).trim_prefix("mixamorig_")
			groups[i] = SHAPE_GROUPS.get(bn, 0)
			ax[bn] = skin.get_bind_pose(i).affine_inverse().origin
	var am := ArrayMesh.new()
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var cols := PackedColorArray()
		cols.resize(verts.size())
		var c0 := PackedFloat32Array()
		c0.resize(verts.size() * 3)
		var c1 := PackedFloat32Array()
		c1.resize(verts.size() * 3)
		for i in verts.size():
			cols[i] = Color.BLACK if absf(verts[i].x) > 0.56 else Color.WHITE
			c0[i * 3] = verts[i].x
			c0[i * 3 + 1] = verts[i].y
			c0[i * 3 + 2] = verts[i].z
			c1[i * 3] = norms[i].x
			c1[i * 3 + 1] = norms[i].y
			c1[i * 3 + 2] = norms[i].z
		if not groups.is_empty() and ax.has("Spine1") and ax.has("Neck") and ax.has("LeftArm") and ax.has("LeftUpLeg"):
			arr[Mesh.ARRAY_VERTEX] = _shape_verts(verts, arr[Mesh.ARRAY_BONES], arr[Mesh.ARRAY_WEIGHTS], groups, ax, shape)
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_CUSTOM0] = c0
		arr[Mesh.ARRAY_CUSTOM1] = c1
		arr[Mesh.ARRAY_CUSTOM2] = null
		arr[Mesh.ARRAY_CUSTOM3] = null
		var flags: int = mesh.surface_get_format(si) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		flags |= Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		flags |= Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT
		# içe aktarırken üretilen ayrıntı seviyeleri (LOD) korunur: uzaktaki karakter daha az üçgenle çizilir
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], _lods_of(mesh, si), flags)
		am.surface_set_material(si, mesh.surface_get_material(si))
	am.resource_name = mesh.resource_name
	_mask_cache[ck] = am
	return am


# Gövde tipi şekli: her köşe, ağırlıklı olduğu bölgenin (gövde/kol/bacak) ekseninden dışarı (eksi değerde içeri)
# itilir; göbek gövdenin önünde, bel hizasında yumuşak bir tümsek. Yaka (boyun kökü) ve eller/ayaklar oynamaz.
static func _shape_verts(verts: PackedVector3Array, bones: PackedInt32Array, weights: PackedFloat32Array, groups: PackedByteArray, ax: Dictionary, shape: Dictionary) -> PackedVector3Array:
	var out := verts.duplicate()
	var per := bones.size() / maxi(verts.size(), 1)
	var cz: float = (ax.Spine1 as Vector3).z
	var neck_y: float = (ax.Neck as Vector3).y
	var low_y: float = (ax.Spine as Vector3).y if ax.has("Spine") else (ax.Spine1 as Vector3).y - 0.1
	var belly_y := lerpf(low_y, (ax.Spine1 as Vector3).y, 0.5)
	var arm: Vector3 = ax.LeftArm
	var leg: Vector3 = ax.LeftUpLeg
	var g_t: float = shape.get("govde", 0.0)
	var g_b: float = shape.get("gobek", 0.0)
	var g_a: float = shape.get("kol", 0.0)
	var g_l: float = shape.get("bacak", 0.0)
	var belly_dir := Vector3(0.0, -0.12, 1.0).normalized()
	for i in verts.size():
		var w := [0.0, 0.0, 0.0, 0.0]
		for k in per:
			var b := bones[i * per + k]
			if b < groups.size():
				w[groups[b]] += weights[i * per + k]
		var p := verts[i]
		var d := Vector3.ZERO
		if w[1] > 0.0:
			var r := Vector3(p.x, 0.0, p.z - cz)
			r = r.normalized() if r.length() > 0.001 else Vector3.BACK
			var fall := smoothstep(0.0, 1.0, clampf((neck_y - 0.07 - p.y) / 0.14, 0.0, 1.0))
			d += r * g_t * w[1] * fall
			var gb := exp(-pow((p.y - belly_y) / 0.13, 2.0)) * exp(-pow(p.x / 0.17, 2.0)) * clampf((p.z - cz) / 0.08 + 0.4, 0.0, 1.0)
			d += belly_dir * g_b * gb * w[1]
		if w[2] > 0.0:
			var r := Vector3(0.0, p.y - arm.y, p.z - arm.z)
			if r.length() > 0.001:
				d += r.normalized() * g_a * w[2]
		if w[3] > 0.0:
			var r := Vector3(p.x - absf(leg.x) * signf(p.x), 0.0, p.z - leg.z)
			if r.length() > 0.001:
				d += r.normalized() * g_l * w[3]
		out[i] = p + d
	return out


static var _merge_cache := {}

# Aynı kemik listesine (skin) bağlı tek yüzeyli meshleri hedefin tek yüzeyine ekler (köşe dizileri art arda,
# sıra numaraları kaydırılır). Kemik listesi farklıysa ya da biçim uyuşmazsa null döner (birleştirme yapılmaz).
static func _merged_skinned(target: MeshInstance3D, extra: Array, key: String) -> Mesh:
	if extra.is_empty():
		return null
	if _merge_cache.has(key):
		return _merge_cache[key]
	_merge_cache[key] = null
	var parts := [target] + extra
	var names := []
	for i in target.skin.get_bind_count():
		names.append(target.skin.get_bind_name(i))
	for p in parts:
		var m := p as MeshInstance3D
		if m.mesh.get_surface_count() != 1 or m.skin == null or m.skin.get_bind_count() != names.size():
			return null
		for i in names.size():
			if m.skin.get_bind_name(i) != names[i]:
				return null
	var keys := [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV,
		Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var idx := PackedInt32Array()
	var base := 0
	for p in parts:
		var arr := (p as MeshInstance3D).mesh.surface_get_arrays(0)
		var n: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		for k in keys:
			if arr[k] == null:
				return null
			if out[k] == null:
				out[k] = arr[k].duplicate()
			else:
				out[k].append_array(arr[k])
		var src: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for t in src:
			idx.append(t + base)
		base += n
	out[Mesh.ARRAY_INDEX] = idx
	var tm := target.mesh
	var flags: int = tm.surface_get_format(0) & (Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS | (Mesh.ARRAY_FORMAT_CUSTOM_MASK << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_FORMAT_CUSTOM_MASK << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out, [], {}, flags)
	am.surface_set_material(0, tm.surface_get_material(0))
	am.resource_name = tm.resource_name
	_merge_cache[key] = am
	return am


static var _ranger_cache := {}

# Ranger kıyafetinden tek parça (ör. kapüşon): [mesh, skin]. Adlandırılmış bağlamalar (mixamorig_*) her
# iskelette aynı kemiklere oturur, bu yüzden köylü kıyafetinin iskeletine de takılabilir.
static func _ranger_part(taban: String, part: String) -> Array:
	var k := taban + "/" + part
	if _ranger_cache.has(k):
		return _ranger_cache[k]
	var out := []
	var sc: Node = load(BODIES[taban].ranger).instantiate()
	for mi in sc.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).contains(part) and (mi as MeshInstance3D).skin:
			out = [(mi as MeshInstance3D).mesh, (mi as MeshInstance3D).skin]
	sc.free()
	_ranger_cache[k] = out
	return out


# Gövde tipinin tarifi: taban gövdenin tarifi + tipin farkları.
static func body_def(id: String) -> Dictionary:
	if BODIES.has(id):
		return BODIES[id]
	if not TYPES.has(id):
		return BODIES.erkek
	var t: Dictionary = TYPES[id]
	var d: Dictionary = (BODIES[t.taban] as Dictionary).duplicate()
	d.merge(t, true)
	return d


static func base_of(id: String) -> String:
	if TYPES.has(id):
		return TYPES[id].taban
	return id if BODIES.has(id) else "erkek"


# Bir yüzeyin içe aktarmada üretilmiş LOD üçgen dizileri: {kenar uzunluğu: köşe sırası}. Köşeler aynı
# kaldığı sürece yeni meshe aynen verilebilir (köşe rengi eklemek, köşeleri içeri çekmek). keep verilirse
# yalnız üç köşesi de tutulan üçgenler kalır (kafa kesme).
static func _lods_of(mesh: Mesh, si: int, keep := PackedByteArray()) -> Dictionary:
	var out := {}
	if not mesh is ArrayMesh:
		return out
	var sd: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), si)
	var lods: Array = sd.get("lods", [])
	var n_idx := (mesh as ArrayMesh).surface_get_array_index_len(si)
	var main_idx: PackedByteArray = sd.get("index_data", PackedByteArray())
	if lods.is_empty() or n_idx <= 0 or main_idx.is_empty():
		return out
	var wide := main_idx.size() / n_idx >= 4  # 32 bit sıra (çok köşeli mesh) ya da 16 bit
	for lod in lods:
		var data: PackedByteArray = lod.get("index_data", PackedByteArray())
		var idx := PackedInt32Array()
		if wide:
			idx = data.to_int32_array()
		else:
			idx.resize(data.size() / 2)
			for i in idx.size():
				idx[i] = data.decode_u16(i * 2)
		if not keep.is_empty():
			var kept := PackedInt32Array()
			for t in range(0, idx.size() - 2, 3):
				if keep[idx[t]] and keep[idx[t + 1]] and keep[idx[t + 2]]:
					kept.append_array([idx[t], idx[t + 1], idx[t + 2]])
			idx = kept
		if idx.size() >= 3:
			out[float(lod.get("edge_length", 0.0))] = idx
	return out


# Görünen parçaları dünya katmanından karakter katmanına taşır (başka katman bitleri korunur).
static func _char_layers(n: Node) -> void:
	if n is VisualInstance3D and not n is Decal:
		var v := n as VisualInstance3D
		if v.layers & 1:
			v.layers = (v.layers & ~1) | CHAR_LAYER
	for c in n.get_children():
		_char_layers(c)


static func _bind_of(skin: Skin, bone: String) -> Variant:
	for i in skin.get_bind_count():
		if String(skin.get_bind_name(i)) == bone:
			return skin.get_bind_pose(i)
	return null


# Gövdenin kafa bilgisi (modelin kendi çizildiği uzayda = bağlama/bind uzayı, yüz +z):
#   bind: model uzayından kafa kemiği uzayına dönüşüm (kafaya takılan her şey bununla kemiğe bağlanır),
#   head: kafa kemiğinin yeri, top: kafa tepesinin yüksekliği, mesh: kafayı içeren mesh.
# CC0 gövdelerde ayrıca tam gövde modelinden ayrılan kafa+boyun, göz ve kaş meshleri (bas/goz/kas).
static func _head_info(id: String) -> Dictionary:
	if _parts.has(id):
		return _parts[id]
	var path: String = BODIES[id].bas
	var sc: Node = load(path).instantiate()
	var out := {}
	for mi in sc.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var n := String(m.name).to_lower()
		if m.skin == null:
			continue
		if n.contains("eyebrow"):
			out.kas = [m.mesh, m.skin]
		elif n.contains("eye"):
			out.goz = [m.mesh, m.skin]
		elif _bind_of(m.skin, "mixamorig_Head") != null and not out.has("bind"):
			out.bind = _bind_of(m.skin, "mixamorig_Head")
			out.head = (out.bind as Transform3D).affine_inverse().origin
			var nb: Variant = _bind_of(m.skin, "mixamorig_Neck")
			var neck: Vector3 = (nb as Transform3D).affine_inverse().origin if nb != null else (out.head as Vector3) + Vector3(0, -0.08, 0)
			var cb: Variant = _bind_of(m.skin, "mixamorig_Spine2")
			if cb != null and nb != null:
				out.chest_bind = cb
				out.neck = (nb as Transform3D).affine_inverse().origin
			if nb != null:
				out.neck_bind = nb
				out.neck_pos = neck
			var r := _cut_head(m.mesh, m.skin, neck)
			out.top = r[1]
			out.mesh = r[0]
			out.bas = [r[0], m.skin]
	sc.free()
	_parts[id] = out
	return out


# Kafa çerçevesi model uzayında: dik, kafa ortasında; yüz -z'ye bakar (model +z'ye baktığı için y ekseninde
# 180° dönük), ölçek kafa yarıçapı ~0.115 olacak şekilde (saç/şapka/sakal kodu bu çerçevede çalışır).
static func _frame_model(info: Dictionary) -> Transform3D:
	var head: Vector3 = info.head
	var top := Vector3(head.x, float(info.top), head.z)
	var r := head.distance_to(top) * 0.5
	return Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * (r / 0.115)), head.lerp(top, 0.45))


# Kafa ve boyun (ağırlığı kafa/boyun kemiğinde olan üçgenler) + gömleğin altına çekilmiş boyun/omuz kökü.
static func _cut_head(mesh: Mesh, skin: Skin, neck: Vector3) -> Array:
	var keep := {}
	for i in skin.get_bind_count():
		var bn := String(skin.get_bind_name(i))
		if bn == "mixamorig_Head" or bn == "mixamorig_Neck":
			keep[i] = true
	var arr := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / verts.size()
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var nverts := verts.duplicate()
	var ok := PackedByteArray()
	ok.resize(verts.size())
	var top := -1e9
	for v in verts.size():
		var w := 0.0
		for k in per:
			if keep.has(bones[v * per + k]):
				w += weights[v * per + k]
		# boyun altı, omuz üstü ve göğsün üstü de alınır ama içeri (normalin tersine) çekilir: yaka
		# açıklıklarını doldurur, kollar kalkınca bile gömleğin altında kalır, kesik kenarı görünmez
		var p := verts[v]
		var dz := p.z - neck.z
		var hd := Vector2(p.x - neck.x, dz * (0.6 if dz > 0.0 else 1.0)).length()
		var in_neck := hd < 0.075 and p.y > neck.y - 0.06
		ok[v] = 1 if (w >= 0.5 and (p.y > neck.y + 0.03 or hd < 0.075)) or in_neck else 0
		if p.y < neck.y + 0.05:
			# boyun kökü yakanın altına doğru içeri çekilir
			var sink := clampf((neck.y + 0.05 - p.y) / 0.08, 0.0, 1.0) * 0.014
			nverts[v] = p - norms[v] * sink
		if w >= 0.5:
			top = maxf(top, verts[v].y)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var nidx := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		if ok[idx[t]] and ok[idx[t + 1]] and ok[idx[t + 2]]:
			nidx.append_array([idx[t], idx[t + 1], idx[t + 2]])
	arr[Mesh.ARRAY_INDEX] = nidx
	arr[Mesh.ARRAY_VERTEX] = nverts
	for ci in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		arr[ci] = null
	var am := ArrayMesh.new()
	var flags: int = mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], _lods_of(mesh, 0, ok), flags)
	return [am, top]


# Bir gövdenin kafa şeklini (model uzayında) ölçüp saklar; saçlar hangi kafaya göre yapıldıysa ona göre taşınır.
static func _ensure_profile(id: String) -> void:
	if Hair.has_profile(id):
		return
	var info := _head_info(id)
	var frame := _frame_model(info)
	Hair.fit_head([[info.mesh, frame.affine_inverse()]], id, frame, false)


# Dokudaki ortalama ten rengi (ten pikselleri): boyama oranı buna göre hesaplanır.
static func _avg_skin(path: String) -> Color:
	if _avg.has(path):
		return _avg[path]
	var img := (load(path) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.resize(64, 64, Image.INTERPOLATE_BILINEAR)
	var sum := Vector3.ZERO
	var n := 0
	for y in 64:
		for x in 64:
			var c := img.get_pixel(x, y)
			if c.r > c.b * 1.12 and c.r > 0.25:  # ten pikseli (gri iç çamaşırı / koyu saç değil)
				sum += Vector3(c.r, c.g, c.b)
				n += 1
	var avg := Color(sum.x / n, sum.y / n, sum.z / n) if n > 0 else Color(0.7, 0.5, 0.4)
	_avg[path] = avg
	return avg


static func _shaders() -> void:
	if _skin_shader:
		return
	_skin_shader = Shader.new()
	_skin_shader.code = SKIN_SHADER
	_cloth_shader = Shader.new()
	_cloth_shader.code = CLOTH_SHADER
	_eye_shader = Shader.new()
	_eye_shader.code = EYE_SHADER


func _skin_mat(tex: String, nrm: String, rgh: String, face: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _skin_shader
	m.set_shader_parameter("tex", load(tex))
	m.set_shader_parameter("nrm", load(nrm))
	if rgh != "":
		m.set_shader_parameter("rgh", load(rgh))
	var avg := _avg_skin(tex)
	var sk := Color(Catalog.SKIN[look.ten])
	m.set_shader_parameter("base_avg", Vector3(avg.r, avg.g, avg.b))
	m.set_shader_parameter("tint", Vector3(sk.r / avg.r, sk.g / avg.g, sk.b / avg.b))
	m.set_shader_parameter("hair_col", Color(Catalog.HAIR_COLORS[look.sac_renk]))
	if not face:
		m.set_shader_parameter("face_box", Vector4(-1, -1, -1, -1))
	else:
		# boyalı saç gölgesi kel seçilince silinir; kirli sakal sakallı seçimlerde kalır
		var sac := str(look.sac)
		m.set_shader_parameter("scalp", 0.0 if sac == "kel" else (1.0 if sac in ["asker", "kazi"] else 0.35))
		m.set_shader_parameter("stubble", 1.0 if look.sakal in ["kirli", "sakal", "keci", "hipster"] else (0.0 if _taban == "kadin" else 0.25))
		var def := body_def(_govde)
		if def.has("yas"):
			m.set_shader_parameter("age", float(def.yas))
			m.set_shader_parameter("hair_col", _aged(Color(Catalog.HAIR_COLORS[look.sac_renk])))
	return m


# Yaşlı gövdede kaş ve boyalı kirli sakal kırlaşır (saçın kendisi oyuncunun seçtiği renkte kalır).
func _aged(c: Color) -> Color:
	return c.lerp(Color("#b9b6ae"), 0.6) if body_def(_govde).has("yas") else c


func _cloth_mat(part: int, ranger := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _cloth_shader
	m.set_shader_parameter("tex", load(RANGER_TEX if ranger else CLOTH_TEX))
	m.set_shader_parameter("nrm", load(RANGER_N if ranger else CLOTH_N))
	m.set_shader_parameter("orm", load(RANGER_ORM if ranger else CLOTH_ORM))
	m.set_shader_parameter("prints", load(PRINT_TEX))
	m.set_shader_parameter("mode", 1 if ranger else 0)
	m.set_shader_parameter("part", part)
	m.set_shader_parameter("back_y", _spine2_y - 0.01)
	m.set_shader_parameter("chest_y", _spine2_y + 0.05)
	m.set_shader_parameter("skin", Color(Catalog.SKIN[look.ten]))
	return m


func _apply_colors() -> void:
	_shaders()
	var def := body_def(_govde)
	var dark := int(look.ten) >= 3
	var o: Dictionary = Catalog.OUTFITS.get(look.kiyafet, Catalog.OUTFITS.turuncu)
	var hair_col := Color(Catalog.HAIR_COLORS[look.sac_renk])
	for mi in _skel.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var n := String(m.name)
		if n == "Bas":
			m.material_override = _skin_mat(def.ten[1 if dark else 0], def.ten_n, def.ten_r, true)
		elif n == "Goz":
			var e := ShaderMaterial.new()
			e.shader = _eye_shader
			e.set_shader_parameter("tex", load(EYE_TEX))
			e.set_shader_parameter("iris", Color(Catalog.EYE_COLORS[look.goz]))
			m.material_override = e
		elif n == "Yaka":
			# 0. yüzey: boyunla aynı deri malzemesi (doku yerleri boyundan kopyalandı)
			m.set_surface_override_material(0, _skin_mat(def.ten[1 if dark else 0], def.ten_n, def.ten_r, true))
			# yaka içi: dışarıdan görünmez, yaka aralığından bakınca gölge gibi koyu (iki yüzlü); boyuna değen
			# kenarı deri rengi (köşe rengiyle koyulaşır), kesişim çizgisi alacalı görünmez
			var ym := StandardMaterial3D.new()
			ym.albedo_color = Color(Catalog.SKIN[look.ten])
			ym.vertex_color_use_as_albedo = true
			ym.roughness = 0.9
			ym.metallic_specular = 0.1
			ym.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.set_surface_override_material(1, ym)
		elif n == "Kas":
			m.material_override = Hair.brow_material(def.kas, _aged(hair_col))
		elif n == "Kapuson" or n.contains("Hood"):
			# kapüşon (şapka): kıyafetten bağımsız koyu kumaş; firari ceketinde ceketle aynı
			var hm := _cloth_mat(0, true)
			hm.set_shader_parameter("color", Color("#2c2f36"))
			hm.set_shader_parameter("pattern", 99 if int(o.get("ud", 0)) == 99 else 0)
			m.material_override = hm
		else:
			for s in m.mesh.get_surface_count():
				var src := m.mesh.surface_get_material(s)
				var sname := src.resource_name if src else ""
				var mat: Material
				if sname.contains("Regular"):
					mat = _skin_mat(def.el, def.el_n, "", false)
				else:
					var part := 1 if n.contains("Legs") else (2 if n.contains("Feet") else 0)
					mat = _cloth_mat(part, _ranger)
					_cloth_mats.append([mat, part])
				m.set_surface_override_material(s, mat)
	for c in _cloth_mats:
		var cm: ShaderMaterial = c[0]
		var leg: bool = c[1] == 1
		cm.set_shader_parameter("color", Color(o.alt if leg else o.ust))
		cm.set_shader_parameter("pattern", int(o.get("ad" if leg else "ud", 0)))
		cm.set_shader_parameter("accent", Color(o.get("vurgu", "#ebe9e2")))
		cm.set_shader_parameter("kir", float(o.get("kir", 0.0)))
		cm.set_shader_parameter("yirtik", float(o.get("yirtik", 0.0)))
		cm.set_shader_parameter("baski", int(o.get("baski", 0)))


# Kafa kemiğine bir düğüm takar; saç/sakal/gözlük kafa ölçüsüne göre kurulur, modele göre ölçeklenir.
func _attach_head_props() -> void:
	if not is_instance_valid(_skel):
		return
	var head_i := _skel.find_bone("mixamorig_Head")
	if head_i < 0:
		return
	var ba := BoneAttachment3D.new()
	ba.bone_idx = head_i
	_skel.add_child(ba)
	# kafa çerçevesi model uzayında kurulur, kafa kemiğine bağlama (bind) dönüşümüyle takılır:
	# gövdenin dünyadaki dönüşünden ve yeniden hedeflemenin dinlenme pozundan bağımsız
	var info := _head_info(_taban).duplicate()
	info.sis = float((body_def(_govde).get("sekil", {}) as Dictionary).get("govde", 0.0))  # göğüs kalınlığı farkı (kolye, çanta)
	var frame := _frame_model(info)
	_head = Node3D.new()
	_head.transform = (info.bind as Transform3D) * frame
	ba.add_child(_head)
	var hair_col := Color(Catalog.HAIR_COLORS[look.sac_renk])
	# saç/sakal kökleri gerçek kafa yüzeyine otursun diye kafa şekilleri ölçülür (gövde başına bir kez);
	# Quaternius saçları kadın/erkek kafasına göre yapıldığından iki kafa da ölçülür.
	for id in BODIES:
		_ensure_profile(id)
	Hair.use(_taban)
	var hat := str(look.get("sapka", "yok"))
	var hair_box := AABB()
	if hat == "kapuson" or (hat != "yok" and not hat in Hats.OPEN and look.sac in Hats.HIDDEN_HAIR):
		pass  # kısa saç şapkanın altında kalır; kapüşon bütün saçı örter
	else:
		var before := _head.get_child_count()
		if Hair.build_real(_head, look.sac, hair_col):
			pass  # gerçek saç modeli
		elif look.sac in CARD_STYLES:
			Hair.build_hair(_head, look.sac, hair_col)
		# şapka, saçın ilk (taban) parçasını örter; örgü/kuyruk gibi sarkan ekler kutuya katılmaz
		for i in range(before, _head.get_child_count()):
			var mi := _head.get_child(i) as MeshInstance3D
			if mi:
				hair_box = mi.transform * mi.get_aabb()
				break
	Hats.build(_head, hat, hair_box)
	_apply_tattoo()
	if look.sakal != "yok":
		Hair.build_beard_any(_head, str(look.sakal), _aged(hair_col), true)
	Acc.build(_head, _skel, str(look.get("aksesuar", "yok")), info)
	# aynı malzemeli küçük parçalar tek meshte (her mesh ayrı çizim çağrısı): zincir halkaları, inci taneleri,
	# gözlük çerçevesi, küpe çifti...
	_merge_rigid(_head)
	for bag in _skel.get_children():
		if bag is BoneAttachment3D:
			for h in bag.get_children():
				if h.get_class() == "Node3D":
					_merge_rigid(h)
	_head.visible = not hide_head or head_peek
	_char_layers(self)


# Aynı malzemeli sabit parçaları tek meshte birleştirir (dunya.gd birlestir).
static func _merge_rigid(root: Node3D) -> void:
	Dunya.birlestir(root)


# Dövme resmini mürekkebe çevirir: beyaz/açık kısımlar şeffaf, koyu çizgiler lacivert-siyah mürekkep.
static func ink_texture(id: String) -> Texture2D:
	if _ink.has(id):
		return _ink[id]
	var path := "res://assets/dovme/dovme_%s.png" % TATTOO_FILE.get(id, id)
	var src: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if src == null:
		return null
	var img := src.get_image()
	img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var lum := (c.r + c.g + c.b) / 3.0
			var a := c.a * clampf((0.82 - lum) / 0.62, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.07, 0.09, 0.13, a * 0.92))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_ink[id] = t
	return t


# Dövmeyi gerçek dövme gibi vücut yüzeyine yansıtır (Decal); kafa ya da el kemiğiyle birlikte hareket eder.
func _apply_tattoo() -> void:
	var id := str(look.get("dovme", "yok"))
	if id == "yok" or not TATTOO_PLACE.has(id):
		return
	var tex := ink_texture(id)
	if tex == null:
		return
	for mi in _rig.find_children("*", "MeshInstance3D", true, false):
		if not (mi as MeshInstance3D).get_parent() is BoneAttachment3D and _head and not _head.is_ancestor_of(mi) \
				and not String(mi.name) in ["Goz", "Kas"]:
			(mi as MeshInstance3D).layers |= DECAL_LAYER
	var place: String = TATTOO_PLACE[id][0]
	var size: float = TATTOO_PLACE[id][1]
	var d := Decal.new()
	d.texture_albedo = tex
	d.cull_mask = DECAL_LAYER
	d.normal_fade = 0.35
	d.upper_fade = 0.05
	d.lower_fade = 0.05
	var aspect := float(tex.get_height()) / tex.get_width()
	# kafa çerçevesi metre değil: ölçülen kafa genişliğine (gerçekte ~15,5 cm) göre ölçekle
	var k := (Hair._head_max.x - Hair._head_min.x) / 0.155
	match place:
		"yuz":
			var dir := Vector3(0.3, 0.1, -1.0).normalized()
			var p := dir * Hair.radius_at(dir)
			size *= k
			d.size = Vector3(size / aspect, 0.05 * k, size)
			d.transform = Transform3D(_decal_basis(dir, Vector3.UP), p)
			_head.add_child(d)
		"kafa":
			var dir := Vector3(1.0, 0.12, 0.15).normalized()
			size *= k
			d.size = Vector3(size / aspect, 0.06 * k, size)
			d.transform = Transform3D(_decal_basis(dir, Vector3.UP), dir * Hair.radius_at(dir))
			_head.add_child(d)
		"el":
			var hand := _skel.find_bone("mixamorig_RightHand")
			var finger := _skel.find_bone("mixamorig_RightHandMiddle1")
			if hand < 0 or finger < 0:
				return
			var hr := _skel.global_transform * _skel.get_bone_global_rest(hand)
			var fr := _skel.global_transform * _skel.get_bone_global_rest(finger)
			var along := (fr.origin - hr.origin).normalized()
			var ba := BoneAttachment3D.new()
			ba.bone_idx = hand
			_skel.add_child(ba)
			d.size = Vector3(size, 0.08, size * aspect)
			var want := Transform3D(_decal_basis(Vector3.UP, along), hr.origin.lerp(fr.origin, 0.55))
			d.transform = hr.affine_inverse() * want
			ba.add_child(d)


# Decal tabanı: Y ekseni yüzeyden dışarı (yansıtma yönünün tersi), resmin üstü "up" yönünde.
static func _decal_basis(normal: Vector3, up: Vector3) -> Basis:
	var y := normal.normalized()
	var z := -(up - y * up.dot(y)).normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


# Birinci şahıs gövdesinde (hide_head) kafa, saç, şapka, aksesuar ve gövde gölgesi geçici açılır / geri kapanır.
func set_head_peek(on: bool) -> void:
	head_peek = on
	if not hide_head or not is_instance_valid(_rig):
		return
	if is_instance_valid(_head):
		_head.visible = on
	if _skel and _head_bone >= 0 and not on:
		_skel.set_bone_pose_scale(_head_bone, Vector3.ONE * 0.001)
	var sh := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for mi in _rig.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = sh


func set_first_person(on: bool) -> void:
	show_head = not on
	_rig.visible = not on


func _apply_visibility() -> void:
	pass


func play_emote(id: String) -> void:
	if _player and _player.has_animation("hd/" + id):
		emote = id
		emote_t = 0.0
		_current = ""
		_play(id, 0.2)


func stop_emote() -> void:
	emote = ""
	_current = ""


func _play(n: String, blend := 0.25) -> void:
	var full := "hd/" + n
	if _current == n or not _player.has_animation(full):
		return
	_current = n
	_player.play(full, blend)


func _process(delta: float) -> void:
	if not _player:
		return
	if emote != "":
		emote_t += delta
		var max_t: float = EMOTE_LEN.get(emote, Emotes.LEN.get(emote, 999.0))
		if emote_t > max_t or not _player.is_playing() or _player.current_animation != "hd/" + emote:
			emote = ""
		else:
			return
	if seated:
		_play("oturma", 0.4)
		_player.speed_scale = 1.0
	elif crouched:
		_play("comel_yuru" if walk > 0.08 else "comel", 0.3)
		_player.speed_scale = clampf(walk * 1.2, 0.6, 1.3) if walk > 0.08 else 1.0
	elif walk > 1.15:
		_play("kosma")
		_player.speed_scale = clampf(walk / 1.5, 0.7, 1.3)
	elif walk > 0.08:
		_play("yurume")
		_player.speed_scale = clampf(walk * 1.1, 0.6, 1.4)
	else:
		_play("durma")
		_player.speed_scale = 1.0
