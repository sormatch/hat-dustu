// Oyunun ekonomisi SUNUCUDA: elmas, eşyalar, kasa, günün fırsatları, maç ödülleri, seviye (XP),
// günlük görevler, başarımlar ve haftalık liderlik. Telefon sadece gösterir; hile ile elmas/eşya üretilemez.
// Eşya listesi ve fiyatlar scripts/catalog.gd ile AYNI olmalı (değişince ikisini birlikte güncelle).

export const START_GEMS = 1000;

// [kimlik, fiyat] — fiyatı 0 olanlar herkese açık
export const ITEMS = {
  govde: [["erkek", 0], ["kadin", 0], ["iri", 0], ["yasli", 0], ["kadin_iri", 0], ["ince", 0]],
  sac: [["kisa", 0], ["asker", 0], ["kel", 0], ["kazi", 0], ["uzun_duz", 0], ["kazi_k", 30], ["topuz", 40], ["ayrik", 40], ["uzun", 60], ["atkuyrugu", 60], ["mohawk", 80], ["kivircik", 80], ["dalgali", 40], ["yandan", 40], ["kut", 90], ["orgu", 150], ["yuksek_kuyruk", 90], ["yan_orgu", 100], ["cift_topuz", 110], ["ikiz_orgu", 120], ["rasta", 180]],
  kas: [["duz", 0], ["kalin", 0], ["kizgin", 0], ["uzgun", 0]],
  sakal: [["yok", 0], ["biyik", 0], ["kirli", 0], ["keci", 40], ["sakal", 60], ["ince", 30], ["favori", 40], ["zincir", 50], ["pala", 90], ["dolgun", 120], ["uzun", 150]],
  kiyafet: [["turuncu", 0], ["gri", 0], ["mavi", 100], ["beyaz", 100], ["kirmizi", 120], ["cizgili", 150], ["kamuflaj", 250], ["altin", 500], ["siyah", 100], ["yesil", 100], ["sari", 100], ["pembe", 120], ["mor", 120], ["kot", 150], ["puantiye", 160], ["ekose", 180], ["neon", 200], ["leopar", 300], ["no1337", 60], ["kirli", 40], ["revir", 50], ["esofman", 90], ["yirtik", 110], ["hirka", 120], ["firari", 220], ["gardiyan", 450]],
  sapka: [["yok", 0], ["bere", 40], ["ponpon", 60], ["kep", 60], ["ters_kep", 80], ["bandana", 70], ["baret", 90], ["kulaklik", 120], ["fotr", 150], ["tac", 600], ["asci", 50], ["parti", 40], ["tilki", 90], ["kapuson", 100], ["kask", 120], ["kovboy", 140], ["korsan", 160], ["hale", 400]],
  dovme: [["yok", 0], ["gozyasi", 40], ["kalp", 60], ["gul", 80], ["orumcek", 80], ["kafatasi", 100], ["kartal", 150], ["ejderha", 200], ["kaplan", 250]],
  aksesuar: [["yok", 0], ["bant", 30], ["gozluk", 70], ["gunes", 120], ["zincir", 300], ["kurdan", 30], ["maske", 40], ["fiyonk", 50], ["nerd", 60], ["burun", 80], ["kupe", 90], ["kunye", 100], ["goz_bandi", 110], ["kalp", 130], ["kulaklik_boyun", 140], ["pilot", 150], ["monokl", 200], ["kupe_elmas", 220], ["inci", 260], ["saat", 60], ["anahtar", 50], ["yuz_bandana", 70], ["kelepce", 90], ["canta", 110], ["gitar", 240]],
  hareket: [["selam", 0], ["super", 0], ["evet", 0], ["hayir", 0], ["isaret", 40], ["omuz", 50], ["alkis", 50], ["off", 60], ["selamla", 80], ["dans", 150], ["konus", 30], ["comel", 30], ["gul", 40], ["dusun", 40], ["kollar", 40], ["gozcu", 50], ["tuh", 50], ["telefon", 60], ["agla", 60], ["kiz", 60], ["ic", 70], ["firlat", 80], ["yumruk", 90], ["zombi", 140], ["buyu", 150], ["takla", 160], ["bayil", 180], ["dans2", 200], ["kasin", 40], ["sula", 50], ["odun", 60], ["it", 70], ["sandik", 80], ["tamir", 90], ["kalk", 100], ["boks", 120], ["ninja", 200]],
};

// nadirlik fiyattan: 0 sıradan (≤60), 1 nadir (≤120), 2 epik (≤250), 3 efsane
// (catalog.gd RARITY ile aynı sınırlar olmalı)
export function rarity(price) {
  if (price <= 60) return 0;
  if (price <= 120) return 1;
  if (price <= 250) return 2;
  return 3;
}

export function price(cat, id) {
  const it = (ITEMS[cat] || []).find((x) => x[0] === id);
  return it ? it[1] : -1;
}

export function shopItems() {
  const out = [];
  for (const cat of ["sac", "sakal", "kiyafet", "aksesuar", "sapka", "dovme", "hareket"]) {
    for (const [id, p] of ITEMS[cat]) if (p > 0) out.push([cat, id, p]);
  }
  return out;
}

// ---------- ELMAS PAKETLERİ (Türk lirası) ----------
// !!! TEST MODU !!! TEST_ODEME = true iken ÖDEME ALINMAZ: telefon {"t":"elmas_paketi","paket":kimlik} yollar,
// sunucu elmasları doğrudan hesaba ekler. Gerçek mağaza ödemesi (App Store / Google Play makbuz doğrulaması)
// bağlanınca TEST_ODEME = false yapılacak; o zaman bu doğrudan ekleme KAPANIR, yalnızca doğrulanmış makbuz elmas verir.
// (Ortam değişkeni ODEME_TEST=1 de test modunu açar.)
export const TEST_ODEME = false; // test modu yalnızca ortam değişkeniyle açılır: wrangler.toml ODEME_TEST = "1" (YAYINDA "0")

// kimlik: mağaza ürün kimliğiyle aynı olacak (id aynı değerin eski adı). elmas: hesaba geçen toplam (bonus dahil);
// bonus: bunun hediye kısmı. etiket: kartın üstündeki şerit. tek_sefer: hesap başına bir kez.
// hediye_kasa: pakete eklenen ücretsiz nadir kasa sayısı (CHESTS.nadir).
function pk(kimlik, elmas, bonus, fiyat_tl, etiket, ek = {}) {
  return { kimlik, id: kimlik, elmas, bonus, fiyat_tl, fiyat: fiyat_tl, etiket, tek_sefer: false, hediye_kasa: 0, ...ek };
}
export const PAKETLER = [
  pk("baslangic", 300, 0, 49.99, "BAŞLANGIÇ PAKETİ", { tek_sefer: true, hediye_kasa: 1 }),
  pk("elmas_100", 100, 0, 29.99, ""),
  pk("elmas_550", 550, 50, 149.99, ""),
  pk("elmas_1200", 1200, 0, 299.99, "EN POPÜLER"),
  pk("elmas_2500", 2500, 0, 599.99, ""),
  pk("elmas_6500", 6500, 0, 1499.99, "EN İYİ DEĞER"),
];
export const GEM_PACKS = PAKETLER; // eski ad

export function paket(kimlik) {
  return PAKETLER.find((x) => x.kimlik === String(kimlik || "")) || null;
}

// Kasalar: fiyat ve nadirlik ağırlıkları [sıradan, nadir, epik, efsane]
// nadir: satılmaz; Başlangıç Paketi ile gelen hediye kasa (en az NADİR çıkar), yalnızca hediye hakkıyla açılır.
export const CHESTS = {
  tahta: { price: 100, weights: [55, 35, 9, 1] },
  altin: { price: 400, weights: [0, 35, 45, 20] },
  nadir: { price: 0, weights: [0, 70, 25, 5], gift: true },
};

// Tarihten tohumlanan basit rastgele sayı (herkes aynı günün fırsatını görür)
function seeded(seedStr) {
  let h = 1779033703 ^ seedStr.length;
  for (let i = 0; i < seedStr.length; i++) {
    h = Math.imul(h ^ seedStr.charCodeAt(i), 3432918353);
    h = (h << 13) | (h >>> 19);
  }
  return () => {
    h = Math.imul(h ^ (h >>> 16), 2246822507);
    h = Math.imul(h ^ (h >>> 13), 3266489909);
    h ^= h >>> 16;
    return (h >>> 0) / 4294967296;
  };
}

// Gün Türkiye saatine göre döner (UTC+3)
export function today() {
  return new Date(Date.now() + 3 * 3600 * 1000).toISOString().slice(0, 10);
}

// ISO hafta kimliği (liderlik her pazartesi sıfırlanır), ör. "2026-W43"
export function weekId(d = new Date()) {
  const t = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const day = t.getUTCDay() || 7;
  t.setUTCDate(t.getUTCDate() + 4 - day);
  const y0 = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
  const w = Math.ceil(((t - y0) / 86400000 + 1) / 7);
  return `${t.getUTCFullYear()}-W${String(w).padStart(2, "0")}`;
}

// Günün 4 fırsatı: [kategori, kimlik, eski fiyat, indirim %, yeni fiyat]
export function dailyDeals(date = today()) {
  const r = seeded("vitrin" + date);
  const pool = shopItems();
  const out = [];
  for (let i = 0; i < 4 && pool.length; i++) {
    const [cat, id, p] = pool.splice(Math.floor(r() * pool.length), 1)[0];
    const off = [30, 40, 50][Math.floor(r() * 3)];
    out.push([cat, id, p, off, Math.round((p * (100 - off)) / 100 / 5) * 5]);
  }
  return out;
}

// Kasa: nadirlik ağırlığa göre seçilir; o nadirlikte sahip olunmayan bir eşya verilir.
// Hepsine sahipse aynı nadirlikten bir eşya "kopya" olarak gelir ve fiyatının yarısı elmas iade edilir.
export function rollChest(kind, owned) {
  const ch = CHESTS[kind];
  const w = ch.weights;
  let x = Math.random() * w.reduce((a, b) => a + b, 0);
  let rar = 0;
  for (; rar < w.length; rar++) {
    if (x < w[rar]) break;
    x -= w[rar];
  }
  rar = Math.min(rar, 3);
  const all = shopItems().filter(([cat, id, p]) => rarity(p) === rar);
  const fresh = all.filter(([cat, id]) => !owned.includes(cat + ":" + id));
  const pool = fresh.length ? fresh : all;
  const [cat, id, p] = pool[Math.floor(Math.random() * pool.length)];
  return { cat, id, rarity: rar, dup: !fresh.length, refund: fresh.length ? 0 : Math.floor(p / 2) };
}

// ---------- seviye ----------
// Seviye n'den n+1'e geçmek için 100 + 50*(n-1) XP
export function levelOf(xp) {
  let lv = 1;
  let need = 100;
  let rest = xp;
  while (rest >= need) {
    rest -= need;
    lv++;
    need = 100 + 50 * (lv - 1);
  }
  return { seviye: lv, xp_ic: rest, xp_gerek: need };
}

// ---------- maç ödülleri ----------
// sonuc: { sira (1 = birinci), oyuncu_sayisi, puan, oyunlar: {task: delta} }
export const ODUL_TAM_OYUN = 3;
export function matchReward(r) {
  const n = Math.max(2, r.oyuncu_sayisi || 2);
  const top = r.sira <= Math.ceil(n / 3);
  const xp = 40 + (r.sira === 1 ? 40 : top ? 20 : 0) + Math.max(0, r.puan) * 3;
  const gems = 10 + (r.sira === 1 ? 30 : top ? 10 : 0);
  // kısa maç (tek oyun seçilen oda) daha az verir: tam ödül en az ODUL_TAM_OYUN oyunlu maçta (botla tek oyunluk
  // hızlı maçlarla elmas biriktirilmesin). oyun_sayisi gelmezse (eski çağrı) tam ödül.
  const oran = r.oyun_sayisi === undefined ? 1 : Math.min(1, Math.max(0, Number(r.oyun_sayisi) || 0) / ODUL_TAM_OYUN);
  return { xp: Math.round(xp * oran), gems: Math.round(gems * oran) };
}

// ---------- günlük görevler ----------
const MISSIONS = [
  { k: "mac_oyna", ad: "3 maç oyna", hedef: 3, odul: 60 },
  { k: "mac_kazan", ad: "1 maç kazan", hedef: 1, odul: 100 },
  { k: "ilk3", ad: "2 maçta ilk 3'e gir", hedef: 2, odul: 70 },
  { k: "rulet", ad: "Rus Ruleti'nden artı puanla çık", hedef: 1, odul: 50 },
  { k: "tahta", ad: "Kara Tahta'da kelimeyi bil", hedef: 1, odul: 50 },
  { k: "devre", ad: "Kısa Devre'de kutunu onar", hedef: 1, odul: 50 },
  { k: "c4", ad: "C4'ten sağ çık", hedef: 2, odul: 50 },
  { k: "yalanci", ad: "Yalancı'da artı puan al", hedef: 1, odul: 50 },
  { k: "ortalama", ad: "Ortalama Sayı'yı kazan", hedef: 1, odul: 60 },
  { k: "kimkim", ad: "Kim Kim?'de artı puan al", hedef: 1, odul: 50 },
];

// Her oyuncuya her gün 3 görev (oyuncuya ve güne göre karışık)
export function dailyMissions(seedKey, date = today()) {
  const r = seeded("gorev" + seedKey + date);
  const pool = MISSIONS.slice();
  const out = [];
  out.push({ ...pool.shift(), ilerleme: 0, alindi: false }); // "3 maç oyna" her gün var
  for (let i = 0; i < 2; i++) out.push({ ...pool.splice(Math.floor(r() * pool.length), 1)[0], ilerleme: 0, alindi: false });
  return { tarih: date, liste: out };
}

// Maç sonucunu görev ilerlemesine işler
export function applyMissions(g, r) {
  for (const m of g.liste) {
    if (m.ilerleme >= m.hedef) continue;
    let inc = 0;
    if (m.k === "mac_oyna") inc = 1;
    else if (m.k === "mac_kazan") inc = r.sira === 1 ? 1 : 0;
    else if (m.k === "ilk3") inc = r.sira <= 3 ? 1 : 0;
    else if (r.oyunlar && m.k in r.oyunlar) inc = r.oyunlar[m.k] > 0 ? 1 : 0;
    m.ilerleme = Math.min(m.hedef, m.ilerleme + inc);
  }
}

// ---------- başarımlar ----------
export const ACHIEVEMENTS = [
  { k: "mac1", ad: "İlk gün", aciklama: "İlk maçını oyna", stat: "mac", hedef: 1, odul: 50 },
  { k: "mac10", ad: "Koğuşun eskisi", aciklama: "10 maç oyna", stat: "mac", hedef: 10, odul: 150 },
  { k: "mac50", ad: "Müebbet", aciklama: "50 maç oyna", stat: "mac", hedef: 50, odul: 500 },
  { k: "kaz1", ad: "İlk zafer", aciklama: "Bir maç kazan", stat: "galibiyet", hedef: 1, odul: 100 },
  { k: "kaz10", ad: "Koğuş ağası", aciklama: "10 maç kazan", stat: "galibiyet", hedef: 10, odul: 400 },
  { k: "kaz50", ad: "Hapishanenin kralı", aciklama: "50 maç kazan", stat: "galibiyet", hedef: 50, odul: 1500 },
  { k: "sv5", ad: "Tecrübeli", aciklama: "5. seviyeye ulaş", stat: "seviye", hedef: 5, odul: 200 },
  { k: "sv20", ad: "Efsane mahkum", aciklama: "20. seviyeye ulaş", stat: "seviye", hedef: 20, odul: 1000 },
  { k: "kasa10", ad: "Kasa avcısı", aciklama: "10 kasa aç", stat: "kasa", hedef: 10, odul: 200 },
];
