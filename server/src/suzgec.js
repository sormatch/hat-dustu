// Kötü söz süzgeci (Türkçe + İngilizce): kullanıcı adı, görünen ad ve Kara Tahta kelimeleri için.
// Sunucuda uygulanır (istemci atlatamaz). Kelime listesi: suzgec_liste.js.
//
// Dayanıklılık:
//   - büyük/küçük harf (Türkçe I/ı, İ/i dahil; iki küçültme de denenir)
//   - leet: 0→o 1→i 3→e 4→a 5→s 7→t @→a $→s !→i |→i €→e
//   - tekrarlanan harfler (siiiik → sik), tam genişlik harfler (NFKC), Kiril benzerleri (ѕ, о, а...),
//     görünmez karakterler (sıfır genişlikli boşluk vb.), aksanlar (é → e)
//   - araya nokta/boşluk/alt çizgi koyma: "s.i.k", "s i k", "or.os.pu"
//   - Türkçe karakter eşlemesi: ç→c ğ→g ı→i ö→o ş→s ü→u (kökün "ascii: false" seçeneği yoksa)
// Yanlış pozitiflere karşı: kelime sınırı (tam / önek / içerir türleri) ve istisna listesi
// ("Ahmet Sikke", "amcam", "sıkıntı", "Scunthorpe" engellenmez).
//
// Kullanım:
//   uygunsuz(metin, "tum")  -> kullanıcı/görünen ad için (dile özgü belirsiz kökler atlanır)
//   uygunsuz(kelime, "tr")  -> Türkçe Kara Tahta odası; "en" İngilizce oda
//   tahtaKelimesi(kelime, dil) -> uygunsuzsa "***", değilse kelimenin kendisi

import { KOKLER, ISTISNALAR, ISTISNA_ONEKLER } from "./suzgec_liste.js";

const LEET = { "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s", "!": "i", "|": "i", "€": "e" };
const KIRIL = { "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "х": "x", "у": "y", "і": "i", "ј": "j", "ѕ": "s", "к": "k", "м": "m", "т": "t", "н": "h", "в": "b", "ԁ": "d", "ɡ": "g" };
const TR_HARF = "çğıöşü";
const ASCII = { "ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u" };
const GORUNMEZ = /[\u0000-\u001f\u007f­͏؜ᅟᅠ឴឵᠎​-‏‪-‮⁠-⁯ㅤ︀-️﻿]/g;
const UNLU = /[aeıioöuü]/;

// Türkçe harfleri koruyup diğer aksanlı harfleri sadeleştirir (é → e, â → a)
function sadelestir(s) {
  let out = "";
  for (const ch of s) {
    if (TR_HARF.includes(ch)) out += ch;
    else out += ch.normalize("NFD").replace(/[̀-ͯ]/g, "");
  }
  return out;
}

// Harf dizisi: leet + Kiril eşlemesi; harf olmayan her şey ayraç (boşluk) olur
function harflestir(s) {
  let out = "";
  for (const ch of s) {
    const c = KIRIL[ch] || LEET[ch] || ch;
    out += /\p{L}/u.test(c) ? c : /\s/u.test(c) ? " " : "\u0001"; // \u0001: kelime içi ayraç (nokta, alt çizgi...)
  }
  return out;
}

const tekHarf = (s) => s.replace(/(.)\1+/gu, "$1"); // siiiik -> sik, yarrak -> yarak
// çift harfi koruyan biçim: ünlü tekrarları teke, ünsüz tekrarları en fazla ikiye iner (yaaarrrrak -> yarrak)
const ciftHarf = (s) => s.replace(/(.)\1+/gu, (m, c) => (UNLU.test(c) ? c : m.length >= 2 ? c + c : c));
const asciiYap = (s) => s.replace(/[çğıöşü]/g, (c) => ASCII[c]);

// Kökler bir kez hazırlanır: her kök için Türkçe ve ASCII biçimleri, tek/çift harf hâlleriyle
const HAZIR = KOKLER.map(([kok, tur, o = {}]) => {
  const k = kok.toLocaleLowerCase("tr-TR");
  const bicim = (s) => (o.cift ? ciftHarf(s) : tekHarf(s));
  return { tur, dil: o.dil || "", cift: !!o.cift, tr: bicim(k), ascii: o.ascii === false ? "" : bicim(asciiYap(k)) };
});
const ISTISNA = new Set();
for (const w of ISTISNALAR) {
  const k = w.toLocaleLowerCase("tr-TR");
  for (const x of [k, asciiYap(k), tekHarf(k), tekHarf(asciiYap(k))]) ISTISNA.add(x);
}

// Metinden denenecek kelimeleri çıkarır: boşlukla ayrılan parçalar, parça içindeki alt kelimeler,
// tek harflerin birleşimi ("s i k"), ayraçla bölünmüş kısa parçaların birleşimi ("or.os.pu")
function kelimeler(metin) {
  const out = new Set();
  const parcalar = metin.split(/\s+/).filter(Boolean);
  let tekler = "";
  const tekleriBitir = () => {
    if (tekler.length >= 2) out.add(tekler);
    tekler = "";
  };
  for (const p of parcalar) {
    const alt = p.split("\u0001").filter(Boolean);
    for (const a of alt) out.add(a);
    if (alt.length > 1 && alt.some((a) => a.length <= 2)) out.add(alt.join(""));
    // tek harfli parçalar (boşlukla ya da ayraçla) art arda geliyorsa birleşir
    for (const a of alt) {
      if (a.length === 1) tekler += a;
      else tekleriBitir();
    }
    if (alt.length === 0) tekleriBitir();
  }
  tekleriBitir();
  return [...out];
}

function eslesir(kelime, kok, alan) {
  if (!kok) return false;
  if (alan.tur === "tam") return kelime === kok;
  if (alan.tur === "onek") return kelime.startsWith(kok);
  return kelime.includes(kok);
}

// Bir kelime herhangi bir kökle eşleşiyor mu
function kelimeKotu(w, dil) {
  if (ISTISNA.has(w) || ISTISNA.has(ciftHarf(w)) || ISTISNA.has(tekHarf(w))) return false;
  const aw = asciiYap(w);
  if (ISTISNA.has(aw) || ISTISNA.has(tekHarf(aw))) return false;
  if (ISTISNA_ONEKLER.some((o) => aw.startsWith(o) || tekHarf(aw).startsWith(o))) return false;
  const bicimler = { tek: tekHarf(w), cift: ciftHarf(w), aTek: tekHarf(aw), aCift: ciftHarf(aw) };
  for (const k of HAZIR) {
    if (k.dil && k.dil !== dil) continue;
    const trB = k.cift ? bicimler.cift : bicimler.tek;
    const asB = k.cift ? bicimler.aCift : bicimler.aTek;
    if (eslesir(trB, k.tr, k)) return true;
    if (k.ascii && eslesir(asB, k.ascii, k)) return true;
  }
  return false;
}

// Ana işlev: metinde uygunsuz bir kelime var mı. dil: "tum" (adlar), "tr" ya da "en" (Kara Tahta odası)
export function uygunsuz(metin, dil = "tum") {
  const ham = String(metin || "").normalize("NFKC").replace(GORUNMEZ, "");
  if (!ham.trim()) return false;
  // iki küçültme: Türkçe (I→ı) ve İngilizce (I→i). İ her ikisinde de i olur.
  const trKucuk = ham.replace(/İ/g, "i").replace(/I/g, "ı").toLocaleLowerCase("tr-TR");
  const enKucuk = ham.replace(/İ/g, "i").toLowerCase();
  const denenecek = new Set([trKucuk, enKucuk]);
  for (const v of denenecek) {
    const temiz = harflestir(sadelestir(v.normalize("NFC")));
    for (const w of kelimeler(temiz)) if (kelimeKotu(w, dil)) return true;
  }
  return false;
}

// Ad (kullanıcı adı / görünen ad) kullanılabilir mi
export function adUygun(ad) {
  return !uygunsuz(ad, "tum");
}

// Kara Tahta: diğer oyunculara gidecek kelime (uygunsuzsa "***")
export function tahtaKelimesi(kelime, dil = "tr") {
  return uygunsuz(kelime, dil === "en" ? "en" : "tr") ? "***" : kelime;
}
