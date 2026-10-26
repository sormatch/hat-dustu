// Mağaza (market): setler (indirimli paketler), günlük + haftalık vitrin, kasa şans güvencesi (pity),
// istek listesi, seviye yolu (ücretsiz ödül şeridi) ve arkadaşa hediye.
// Hepsi SUNUCUDA hesaplanır; telefon yalnızca gösterir ve istek yollar. Eşyalar ekonomi.js ITEMS'tan kimlikle gelir
// (bu dosya ITEMS'ı değiştirmez; listede olmayan / fiyatı 0 olan parça yok sayılır).
// Her şey kozmetik: parayla güç satılmaz.

import * as E from "./ekonomi.js";
import { tx } from "./metin.js";

const GUN = 86400000;
const TR_SAAT = 3 * 3600 * 1000; // gün ve hafta Türkiye saatine göre döner

// ---------- zaman ----------
// Türkiye saatiyle bugünün bitimine kalan saniye
export function gunKalan(now = Date.now()) {
  const t = now + TR_SAAT;
  return Math.ceil((GUN - (t % GUN)) / 1000);
}

// Türkiye saatiyle bu haftanın (pazartesi 00:00) numarası ve haftanın bitimine kalan saniye
export function hafta(now = Date.now()) {
  const t = now + TR_SAAT;
  const gun = Math.floor(t / GUN); // 1970-01-01 perşembe
  const pzt = gun - ((gun + 3) % 7);
  return { no: pzt, kalan: Math.ceil(((pzt + 7) * GUN - t) / 1000) };
}

export function bugun(now = Date.now()) {
  return new Date(now + TR_SAAT).toISOString().slice(0, 10);
}

// Tarihten tohumlanan rastgele sayı (herkes aynı vitrini görür)
function tohum(s) {
  let h = 1779033703 ^ s.length;
  for (let i = 0; i < s.length; i++) {
    h = Math.imul(h ^ s.charCodeAt(i), 3432918353);
    h = (h << 13) | (h >>> 19);
  }
  return () => {
    h = Math.imul(h ^ (h >>> 16), 2246822507);
    h = Math.imul(h ^ (h >>> 13), 3266489909);
    h ^= h >>> 16;
    return (h >>> 0) / 4294967296;
  };
}

const bes = (x) => Math.max(5, Math.round(x / 5) * 5);

// ---------- günlük vitrin ----------
export const VITRIN_ADET = 6;

// Günün 6 fırsatı: [kategori, kimlik, eski fiyat, indirim %, yeni fiyat]. İlki "öne çıkan": epik ya da efsane.
export function gunluk(date = bugun()) {
  const r = tohum("vitrin2" + date);
  const pool = E.shopItems();
  const out = [];
  const pick = (arr) => arr.splice(Math.floor(r() * arr.length), 1)[0];
  const buyuk = pool.filter(([, , p]) => E.rarity(p) >= 2);
  if (buyuk.length) {
    const it = pick(buyuk);
    pool.splice(pool.findIndex((x) => x[0] === it[0] && x[1] === it[1]), 1);
    out.push(it);
  }
  while (out.length < VITRIN_ADET && pool.length) out.push(pick(pool));
  return out.map(([cat, id, p]) => {
    const off = [20, 30, 40, 50][Math.floor(r() * 4)];
    return [cat, id, p, off, bes((p * (100 - off)) / 100)];
  });
}

// Bir eşyanın bugünkü fiyatı (vitrindeyse indirimli)
export function fiyatSimdi(cat, id, date = bugun()) {
  const p = E.price(cat, id);
  if (p <= 0) return p;
  const d = gunluk(date).find((x) => x[0] === cat && x[1] === id);
  return d ? d[4] : p;
}

// ---------- setler ----------
// Tematik setler: parçalar ITEMS kimlikleriyle. Fiyat = sahip olunmayan parçaların toplamı - indirim.
export const SETLER = [
  { k: "kacak", ad: "Kaçak Paketi", indirim: 30, parcalar: [["sapka", "bandana"], ["kiyafet", "cizgili"], ["aksesuar", "goz_bandi"], ["hareket", "gozcu"]] },
  { k: "patron", ad: "Patron Paketi", indirim: 30, parcalar: [["sapka", "fotr"], ["kiyafet", "siyah"], ["aksesuar", "zincir"], ["hareket", "ic"]] },
  { k: "rapci", ad: "Koğuş Rapçisi", indirim: 30, parcalar: [["sapka", "ters_kep"], ["kiyafet", "neon"], ["aksesuar", "kulaklik_boyun"], ["hareket", "dans2"]] },
  { k: "asker", ad: "Asker Paketi", indirim: 30, parcalar: [["kiyafet", "kamuflaj"], ["sakal", "pala"], ["aksesuar", "kunye"], ["hareket", "selamla"]] },
  { k: "murekkep", ad: "Mürekkep Paketi", indirim: 30, parcalar: [["dovme", "ejderha"], ["sapka", "bere"], ["aksesuar", "gunes"], ["hareket", "firlat"]] },
  { k: "atolye", ad: "Atölye Paketi", indirim: 30, parcalar: [["sapka", "baret"], ["kiyafet", "kot"], ["aksesuar", "kurdan"], ["hareket", "yumruk"]] },
  { k: "sik", ad: "Şık Paketi", indirim: 30, parcalar: [["sac", "yuksek_kuyruk"], ["kiyafet", "pembe"], ["aksesuar", "inci"], ["hareket", "alkis"]] },
  { k: "kral", ad: "Kral Paketi", indirim: 30, parcalar: [["sapka", "tac"], ["kiyafet", "altin"], ["aksesuar", "kupe_elmas"], ["hareket", "dans"]] },
  { k: "gardiyan", ad: "Gardiyan Paketi", indirim: 30, parcalar: [["kiyafet", "gardiyan"], ["sapka", "kask"], ["aksesuar", "anahtar"], ["hareket", "it"]] },
  { k: "kovboy", ad: "Kovboy Paketi", indirim: 30, parcalar: [["sapka", "kovboy"], ["kiyafet", "ekose"], ["aksesuar", "gitar"], ["hareket", "ic"]] },
  { k: "firar", ad: "Firar Paketi", indirim: 30, parcalar: [["kiyafet", "firari"], ["sapka", "kapuson"], ["aksesuar", "canta"], ["hareket", "ninja"]] },
];
export const ONE_CIKAN_EK = 10; // haftanın setine ek indirim (%)

// Setin geçerli parçaları: [kategori, kimlik, fiyat] (ITEMS'ta olmayan ya da bedava parça atlanır)
export function setParcalari(set) {
  return set.parcalar.map(([c, i]) => [c, i, E.price(c, i)]).filter(([, , p]) => p > 0);
}

export function gecerliSetler() {
  return SETLER.filter((s) => setParcalari(s).length >= 2);
}

// Haftanın öne çıkan seti (herkese aynı)
export function haftaninSeti(now = Date.now()) {
  const l = gecerliSetler();
  if (!l.length) return null;
  const r = tohum("set" + hafta(now).no);
  return l[Math.floor(r() * l.length)];
}

// Set fiyatı: sahip olunan parçalar düşülür, kalanlara indirim uygulanır.
export function setFiyat(set, owned, oneCikan = false) {
  const parts = setParcalari(set);
  const kalan = parts.filter(([c, i]) => !owned.includes(c + ":" + i));
  const toplam = kalan.reduce((a, x) => a + x[2], 0);
  const tam = parts.reduce((a, x) => a + x[2], 0);
  const indirim = set.indirim + (oneCikan ? ONE_CIKAN_EK : 0);
  const fiyat = kalan.length ? bes((toplam * (100 - indirim)) / 100) : 0;
  return { parts, kalan, toplam, tam, indirim, fiyat };
}

// ---------- kasa güvencesi ----------
// Her n kasada en az "min" nadirlik (0 sıradan, 1 nadir, 2 epik, 3 efsane). Sayaç: son güvenceden beri açılan kasa.
export const GUVENCE = { tahta: { n: 10, min: 2 }, altin: { n: 10, min: 3 } };

function agirliktan(w, rnd) {
  let x = rnd() * w.reduce((a, b) => a + b, 0);
  let rar = 0;
  for (; rar < w.length; rar++) {
    if (x < w[rar]) break;
    x -= w[rar];
  }
  return Math.min(rar, 3);
}

// Kasa çekilişi (güvenceli). sayac: bu kasa türünde son güvenceden beri açılan kasa sayısı.
// Dönen: { cat, id, rarity, dup, refund, garanti, sayac (yeni) }
export function kasaCek(kind, owned, sayac = 0, rnd = Math.random) {
  const ch = E.CHESTS[kind];
  const g = GUVENCE[kind];
  let w = ch.weights.slice();
  let garanti = false;
  if (g && sayac + 1 >= g.n) {
    // güvence: bu kasada en az g.min çıkar (o kademe ve üstünün kendi oranlarıyla)
    w = w.map((x, i) => (i >= g.min ? x : 0));
    if (w.every((x) => x <= 0)) w = ch.weights.map((_, i) => (i >= g.min ? 1 : 0));
    garanti = true;
  }
  let rar = agirliktan(w, rnd);
  const items = E.shopItems();
  // bu nadirlikte eşya yoksa en yakın kademeye bakılır
  let all = [];
  for (const step of [0, 1, -1, 2, -2, 3, -3]) {
    const t = rar + step;
    if (t < 0 || t > 3) continue;
    all = items.filter(([, , p]) => E.rarity(p) === t);
    if (all.length) {
      rar = t;
      break;
    }
  }
  const fresh = all.filter(([c, i]) => !owned.includes(c + ":" + i));
  const pool = fresh.length ? fresh : all;
  const [cat, id, p] = pool[Math.floor(rnd() * pool.length)];
  const yeni = g ? (rar >= g.min ? 0 : sayac + 1) : sayac;
  return { cat, id, rarity: rar, dup: !fresh.length, refund: fresh.length ? 0 : Math.floor(p / 2), garanti, sayac: yeni };
}

// Kasa olasılıkları (mağaza kuralı: şeffaf gösterilir). havuz: o nadirlikteki eşya sayısı
export function olasiliklar() {
  const items = E.shopItems();
  const havuz = [0, 1, 2, 3].map((r) => items.filter(([, , p]) => E.rarity(p) === r).length);
  const out = {};
  for (const [k, c] of Object.entries(E.CHESTS)) {
    const top = c.weights.reduce((a, b) => a + b, 0) || 1;
    out[k] = { yuzde: c.weights.map((x) => Math.round((x * 1000) / top) / 10), havuz, guvence: GUVENCE[k] || null };
  }
  return out;
}

// ---------- seviye yolu ----------
// Her seviyede bir ödül: elmas, kasa ya da eşya. 10'un katı altın kasa, 5'in katı eşya, 3/8 ile bitenler tahta kasa.
const YOL_ESYA = [["hareket", "alkis"], ["aksesuar", "kupe"], ["kiyafet", "kamuflaj"], ["sapka", "fotr"], ["dovme", "ejderha"], ["aksesuar", "monokl"], ["hareket", "takla"], ["sapka", "tac"]];

export function yolOdul(s) {
  if (!Number.isInteger(s) || s < 2) return null;
  if (s % 10 === 0) return { tur: "kasa", kasa: "altin" };
  if (s % 5 === 0) {
    const it = YOL_ESYA[(s - 5) / 10];
    if (it && E.price(it[0], it[1]) > 0) return { tur: "esya", kat: it[0], id: it[1] };
    return { tur: "elmas", n: 200 };
  }
  if (s % 5 === 3) return { tur: "kasa", kasa: "tahta" };
  return { tur: "elmas", n: Math.min(150, 40 + 10 * Math.floor(s / 5)) };
}

// Ödülü hesaba işler (e: accounts.eco kaydı). Eşya zaten sendeyse yarı fiyatı elmas olur.
function odulVer(e, o) {
  if (o.tur === "elmas") {
    e.gems += o.n;
    return { ...o };
  }
  if (o.tur === "kasa") {
    e.stats.kasa_hak = e.stats.kasa_hak || {};
    e.stats.kasa_hak[o.kasa] = (e.stats.kasa_hak[o.kasa] || 0) + 1;
    return { ...o };
  }
  const key = o.kat + ":" + o.id;
  if (e.items.includes(key)) {
    const n = Math.max(25, Math.floor(E.price(o.kat, o.id) / 2));
    e.gems += n;
    return { ...o, kopya: true, n };
  }
  e.items.push(key);
  return { ...o };
}

function alinanlar(e) {
  return Array.isArray(e.stats.yol) ? e.stats.yol : [];
}

// ---------- hediye ----------
export const HEDIYE = { gunluk: 3, alici_gunluk: 5, min_seviye: 5 };
export const ISTEK_MAX = 40;

function gunSayac(obj, gun) {
  return obj && obj.gun === gun ? obj.n || 0 : 0;
}

// ---------- telefona giden özet (accounts.economy içine katılır) ----------
export function ozet(e, now = Date.now()) {
  const gun = bugun(now);
  const owned = e.items;
  const vit = gunluk(gun);
  const hs = haftaninSeti(now);
  const lv = E.levelOf(e.xp).seviye;
  const yolAl = alinanlar(e);
  const ust = Math.max(30, lv + 10);
  const yol = [];
  let yolHazir = 0;
  for (let s = 2; s <= ust; s++) {
    const al = yolAl.includes(s);
    if (!al && s <= lv) yolHazir++;
    yol.push({ s, ...yolOdul(s), alindi: al });
  }
  const setler = gecerliSetler().map((s) => {
    const f = setFiyat(s, owned, hs && s.k === hs.k);
    return {
      k: s.k, ad: s.ad, indirim: f.indirim, fiyat: f.fiyat, toplam: f.toplam, tam: f.tam, one_cikan: !!(hs && s.k === hs.k),
      parcalar: f.parts.map(([c, i, p]) => [c, i, p, owned.includes(c + ":" + i)]),
      hepsi_sende: f.kalan.length === 0,
    };
  });
  const istek = (Array.isArray(e.stats.istek) ? e.stats.istek : []).filter((k) => !owned.includes(k));
  const vitrinde = new Set(vit.map((x) => x[0] + ":" + x[1]));
  if (hs) for (const [c, i] of setParcalari(hs)) vitrinde.add(c + ":" + i);
  const istekVitrinde = istek.filter((k) => vitrinde.has(k));
  const pity = {};
  for (const [k, g] of Object.entries(GUVENCE)) {
    const sayac = (e.stats.pity || {})[k] || 0;
    pity[k] = { n: g.n, min: g.min, sayac, kalan: Math.max(1, g.n - sayac) };
  }
  const hd = e.stats.hediye_gun;
  return {
    firsatlar: vit,
    vitrin: { gunluk: vit, gun_kalan: gunKalan(now), hafta_kalan: hafta(now).kalan, haftanin_seti: hs ? hs.k : "" },
    setler,
    pity,
    olasilik: olasiliklar(),
    kasa_hak: { tahta: 0, altin: 0, ...(e.stats.kasa_hak || {}) },
    yol,
    yol_hazir: yolHazir,
    istek,
    istek_vitrinde: istekVitrinde,
    istek_yeni: e.stats.istek_gor === gun ? 0 : istekVitrinde.length,
    hediye: { kalan: Math.max(0, HEDIYE.gunluk - gunSayac(hd, gun)), sinir: HEDIYE.gunluk, min_seviye: HEDIYE.min_seviye },
  };
}

// ---------- mesajlar ----------
// acc: Accounts nesnesi. Dönen true: mesaj işlendi. Hepsi eşzamanlı (await yok): Durable Object aynı anda
// tek mesaj işler, iki istek aynı elması iki kez harcayamaz.
export function mesaj(acc, ws, me, d) {
  const err = (m, ...a) => (acc.send(ws, { t: "hata", ...tx(m, ...a) }), true);
  const bitti = (cevap) => {
    acc.send(ws, cevap);
    acc.send(ws, acc.economy(me.token));
    return true;
  };
  switch (d.t) {
    case "satin_al": {
      const cat = String(d.kat || "");
      const id = String(d.id || "");
      if (E.price(cat, id) <= 0) return err("Bu eşya satılmıyor.");
      const cost = fiyatSimdi(cat, id);
      const e = acc.eco(me.token);
      if (e.items.includes(cat + ":" + id)) return err("Bu eşya zaten sende.");
      // telefonun gördüğü fiyattan pahalıysa (vitrin yenilendi) sormadan almaz
      if (d.fiyat !== undefined && cost > Number(d.fiyat)) return err("Fiyat değişti, vitrin yenilendi.");
      if (e.gems < cost) return err("Elmas yetmiyor.");
      e.gems -= cost;
      e.items.push(cat + ":" + id);
      acc.saveEco(me.token, e);
      return bitti({ t: "satin_alindi", kat: cat, id, elmas: e.gems, fiyat: cost });
    }
    case "set_al": {
      const set = gecerliSetler().find((s) => s.k === String(d.k || ""));
      if (!set) return err("Böyle bir set yok.");
      const e = acc.eco(me.token);
      const hs = haftaninSeti();
      const f = setFiyat(set, e.items, !!(hs && hs.k === set.k));
      if (!f.kalan.length) return err("Bu setin hepsi sende.");
      if (d.fiyat !== undefined && f.fiyat > Number(d.fiyat)) return err("Fiyat değişti, vitrin yenilendi.");
      if (e.gems < f.fiyat) return err("Elmas yetmiyor.");
      e.gems -= f.fiyat;
      for (const [c, i] of f.kalan) e.items.push(c + ":" + i);
      e.stats.set = (e.stats.set || 0) + 1;
      acc.saveEco(me.token, e);
      return bitti({ t: "set_alindi", k: set.k, parcalar: f.kalan.map(([c, i]) => [c, i]), fiyat: f.fiyat, elmas: e.gems });
    }
    case "kasa_ac": {
      const kind = String(d.kasa || "");
      const ch = E.CHESTS[kind];
      if (!ch) return err("Böyle bir kasa yok.");
      const e = acc.eco(me.token);
      let bedava = false;
      if (ch.gift) {
        // hediye kasa (Başlangıç Paketi): elmasla alınmaz, hediye hakkı düşer
        if ((e.stats.hediye_kasa || 0) <= 0) return err("Hediye kasan yok.");
        e.stats.hediye_kasa -= 1;
        bedava = true;
      } else if (d.hak) {
        // seviye yolundan gelen ücretsiz kasa hakkı
        const hak = (e.stats.kasa_hak || {})[kind] || 0;
        if (hak <= 0) return err("Ücretsiz kasan yok.");
        e.stats.kasa_hak[kind] = hak - 1;
        bedava = true;
      } else if (e.gems < ch.price) return err("Elmas yetmiyor.");
      e.stats.pity = e.stats.pity || {};
      const r = kasaCek(kind, e.items, e.stats.pity[kind] || 0);
      if (GUVENCE[kind]) e.stats.pity[kind] = r.sayac;
      if (!bedava) e.gems -= ch.price;
      if (r.dup) e.gems += r.refund;
      else e.items.push(r.cat + ":" + r.id);
      e.stats.kasa = (e.stats.kasa || 0) + 1;
      acc.saveEco(me.token, e);
      return bitti({ t: "kasa_sonuc", kasa: kind, kat: r.cat, id: r.id, nadirlik: r.rarity, kopya: r.dup, iade: r.refund, garanti: r.garanti, bedava, elmas: e.gems });
    }
    case "istek_listesi": {
      // istek listesi: eşya vitrine girince menüde rozet çıkar
      const cat = String(d.kat || "");
      const id = String(d.id || "");
      const key = cat + ":" + id;
      const e = acc.eco(me.token);
      let l = (Array.isArray(e.stats.istek) ? e.stats.istek : []).filter((k) => typeof k === "string" && !e.items.includes(k));
      if (d.ekle) {
        if (E.price(cat, id) <= 0) return err("Bu eşya satılmıyor.");
        if (e.items.includes(key)) return err("Bu eşya zaten sende.");
        if (!l.includes(key)) {
          if (l.length >= ISTEK_MAX) return err("İstek listen dolu.");
          l.push(key);
        }
      } else l = l.filter((k) => k !== key);
      e.stats.istek = l;
      acc.saveEco(me.token, e);
      return bitti({ t: "istek_tamam", kat: cat, id, ekli: l.includes(key) });
    }
    case "vitrin_bakti": {
      // vitrin açıldı: istek listesi rozeti bugün için söner
      const e = acc.eco(me.token);
      if (e.stats.istek_gor === bugun()) return true;
      e.stats.istek_gor = bugun();
      acc.saveEco(me.token, e);
      acc.send(ws, acc.economy(me.token));
      return true;
    }
    case "yol_al": {
      const s = Math.floor(Number(d.s));
      const e = acc.eco(me.token);
      const lv = E.levelOf(e.xp).seviye;
      const o = yolOdul(s);
      if (!Number.isInteger(s) || !o || s > lv) return err("Bu ödül henüz açılmadı.");
      const al = alinanlar(e);
      if (al.includes(s)) return err("Bu ödülü aldın.");
      e.stats.yol = [...al, s];
      const verilen = odulVer(e, o);
      acc.saveEco(me.token, e);
      return bitti({ t: "yol_alindi", s, odul: verilen, elmas: e.gems });
    }
    case "hediye": {
      // arkadaşa eşya hediye et: elmas gönderenden düşer, eşya alıcıya gider. Günlük sınır, seviye şartı.
      if (!me.handle) return err("Hediye göndermek için hesap aç.");
      const to = String(d.handle || "").replace(/^@/, "").trim().toLowerCase().slice(0, 16);
      const cat = String(d.kat || "");
      const id = String(d.id || "");
      if (!to || to === me.handle) return err("Kendine hediye gönderemezsin.");
      if (!acc.rows(`SELECT 1 FROM friends WHERE a = ? AND b = ? AND status = 'arkadas'`, me.handle, to).length) return err("Sadece arkadaşlarına hediye gönderebilirsin.");
      const toTok = acc.tokenOf(to);
      if (!toTok) return err("@{0} diye biri yok.", to);
      if (acc.blocked(me.token, to) || acc.blocked(toTok, me.handle)) return err("@{0} şu an hediye alamıyor.", to);
      if (E.price(cat, id) <= 0) return err("Bu eşya satılmıyor.");
      const gun = bugun();
      const e = acc.eco(me.token);
      if (E.levelOf(e.xp).seviye < HEDIYE.min_seviye) return err("Hediye için en az {0}. seviye olmalısın.", HEDIYE.min_seviye);
      const gonderilen = gunSayac(e.stats.hediye_gun, gun);
      if (gonderilen >= HEDIYE.gunluk) return err("Bugün en fazla {0} hediye gönderebilirsin.", HEDIYE.gunluk);
      const cost = fiyatSimdi(cat, id, gun);
      if (d.fiyat !== undefined && cost > Number(d.fiyat)) return err("Fiyat değişti, vitrin yenilendi.");
      if (e.gems < cost) return err("Elmas yetmiyor.");
      const r = acc.eco(toTok);
      if (!r) return err("@{0} diye biri yok.", to);
      if (r.items.includes(cat + ":" + id)) return err("@{0} bu eşyaya zaten sahip.", to);
      if (gunSayac(r.stats.hediye_al, gun) >= HEDIYE.alici_gunluk) return err("@{0} bugün çok hediye aldı, yarın dene.", to);
      e.gems -= cost;
      e.stats.hediye_gun = { gun, n: gonderilen + 1 };
      e.stats.hediye_giden = (e.stats.hediye_giden || 0) + 1;
      r.items.push(cat + ":" + id);
      r.stats.hediye_al = { gun, n: gunSayac(r.stats.hediye_al, gun) + 1 };
      // önce alıcı, sonra gönderen kaydedilir (ikisi de aynı eşzamanlı adımda: arada başka mesaj işlenmez)
      acc.saveEco(toTok, r);
      acc.saveEco(me.token, e);
      const online = acc.state.getWebSockets().filter((w) => acc.info(w).token === toTok);
      acc.sql.exec(`INSERT INTO gifts (from_token, to_token, from_handle, kat, item, elmas, ts, goruldu) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        me.token, toTok, me.handle, cat, id, cost, Date.now(), online.length ? 1 : 0);
      const ad = acc.gorunenAd(me.handle);
      for (const w of online) {
        acc.send(w, { t: "hediye_geldi", handle: me.handle, ad, kat: cat, id });
        acc.send(w, acc.economy(toTok));
      }
      return bitti({ t: "hediye_gitti", handle: to, kat: cat, id, fiyat: cost, elmas: e.gems });
    }
  }
  return false;
}

// Bağlanınca: çevrimdışıyken gelen hediyeler bildirilir (bir kez)
export function bekleyenHediyeler(acc, ws, token) {
  const l = acc.rows(`SELECT rowid AS r, from_handle, kat, item FROM gifts WHERE to_token = ? AND goruldu = 0 ORDER BY ts LIMIT 20`, token);
  for (const g of l) {
    acc.send(ws, { t: "hediye_geldi", handle: g.from_handle || "", ad: acc.gorunenAd(g.from_handle || ""), kat: g.kat, id: g.item });
    acc.sql.exec(`UPDATE gifts SET goruldu = 1 WHERE rowid = ?`, g.r);
  }
}
