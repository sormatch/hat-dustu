// Kötü söz süzgeci birim testleri:  cd server && node test/suzgec_test.mjs
// Olumlu (engellenmesi gereken) örnekler suzgec_liste.js'den gelir ve her kökten harf oyunlarıyla türetilir;
// bu dosyada kaba ifade yazılı değildir. Olumsuz örnekler (engellenmemesi gerekenler) aşağıda.
import { uygunsuz, adUygun, tahtaKelimesi } from "../src/suzgec.js";
import { KOKLER, OLUMLU_ORNEKLER } from "../src/suzgec_liste.js";
import { WORDS, ADLAR } from "../src/bots.js";

let ok = 0;
let hata = 0;
const yanlis = [];
function bak(ad, kosul) {
  if (kosul) ok++;
  else {
    hata++;
    yanlis.push(ad);
  }
}

// ---- olumlu: listedeki elle yazılmış örnekler (leet, nokta, boşluk, tekrar, Kiril, tam genişlik, görünmez karakter)
for (const [m, dil] of OLUMLU_ORNEKLER) bak(`olumlu örnek #${OLUMLU_ORNEKLER.findIndex((x) => x[0] === m)} (${dil})`, uygunsuz(m, dil));

// ---- olumlu: her kökten türetilen biçimler
const LEET = { o: "0", i: "1", a: "@", e: "3", s: "$", t: "7" };
const leet = (s) => s.replace(/[oiaest]/, (c) => LEET[c]);
const turet = (kok, tur) => {
  const out = [kok, kok.toLocaleUpperCase("tr-TR"), leet(kok), [...kok].join("."), [...kok].join(" ")];
  const unlu = kok.search(/[aeıioöuü]/);
  if (unlu >= 0) out.push(kok.slice(0, unlu) + kok[unlu].repeat(3) + kok.slice(unlu + 1)); // harf tekrarı
  if (tur === "onek") out.push(kok + "ler", kok + "_34");
  if (tur === "icerir") out.push("xx" + kok + "xx", "kral" + kok);
  return out;
};
let turetilen = 0;
KOKLER.forEach(([kok, tur, o = {}], i) => {
  const dil = o.dil || "tum";
  for (const m of turet(kok, tur)) {
    turetilen++;
    bak(`kök #${i} biçim "${m.length} harf" (${dil})`, uygunsuz(m, dil));
  }
});

// ---- olumsuz: engellenmemesi gereken adlar ve kelimeler
const MASUM_ADLAR = [
  "Ahmet Sikke", "amcam", "Amcam Geldi", "I am Bob", "Kara Murat", "Çağrı Şeker", "Zeynep", "Hücre Bekçisi",
  "sıkıntı", "SIKINTI", "Sık Sık", "sıkıcı adam", "şikayet", "sikayetci", "götür", "götürmek", "Picasso", "pic",
  "picture", "got", "I got it", "stamina", "lamina", "Amina", "Scunthorpe", "class", "assassin", "bass", "as",
  "pass", "cockpit", "peacock", "penisilin", "saksofon", "Nazif", "Nazife", "shiitake", "Ashitaka", "yaram",
  "yara", "Nigar", "Pop Ornek", "ali_34", "mert_1907", "kasap", "ibrahim", "tasarım", "amaç", "Amasya", "Amerika",
  "Samsun", "Sikkim", "Hitchcock", "therapist", "grape", "document", "Dick Grayson", "Cumhur", "Cuma", "cumartesi",
  "Analiz", "Nazım", "Gökhan", "Hüsnü", "Rıza", "Sedat", "Vedat", "Necmi", "Fadime", "Gülsüm", "Sevim", "Melek",
  "Mahkum42", "Oyuncu", "sakız", "kaşık", "Çakal", "Topal", "Kel", "Sinsi", "Pusula",
];
const masum = MASUM_ADLAR;
for (const ad of masum) bak(`masum ad "${ad}"`, adUygun(ad));
// bot adları (Türkçe + İngilizce, kadın + erkek): süzgeçten geçmeli, en çok 16 harf
const BOT_ADLARI = Object.values(ADLAR).flatMap((d) => [...d.erkek, ...d.kadin]);
for (const ad of BOT_ADLARI) bak(`bot adı "${ad}"`, adUygun(ad) && ad.length <= 16);
for (const dil of ["tr", "en"]) for (const w of WORDS[dil]) bak(`bot kelimesi ${w} (${dil})`, tahtaKelimesi(w.toLowerCase(), dil) === w.toLowerCase());
const MASUM_KELIMELER_TR = ["elma", "sıkı", "sıkıntı", "amca", "götür", "yara", "kasa", "piknik", "aslan", "sakız", "şık", "masa", "ambar", "amaç", "kum", "sikke"];
for (const w of MASUM_KELIMELER_TR) bak(`masum tahta kelimesi ${w} (tr)`, tahtaKelimesi(w, "tr") === w);
const MASUM_KELIMELER_EN = ["apple", "am", "got", "class", "bass", "glass", "cucumber", "assassin", "shiitake", "grape", "picture"];
for (const w of MASUM_KELIMELER_EN) bak(`masum tahta kelimesi ${w} (en)`, tahtaKelimesi(w, "en") === w);

// ---- Kara Tahta: uygunsuz kelime "***" olur, oda diline özgü kökler
bak("tahta: tr odasında dile özgü kök ***", tahtaKelimesi(OLUMLU_ORNEKLER.find((x) => x[1] === "tr")[0], "tr") === "***");
bak("tahta: aynı kelime en odasında serbest", tahtaKelimesi(OLUMLU_ORNEKLER.find((x) => x[1] === "tr")[0], "en") !== "***");
bak("tahta: en odasında dile özgü kök ***", tahtaKelimesi(OLUMLU_ORNEKLER.find((x) => x[1] === "en")[0], "en") === "***");
bak("tahta: genel kök iki dilde de ***", tahtaKelimesi(OLUMLU_ORNEKLER[0][0], "tr") === "***" && tahtaKelimesi(OLUMLU_ORNEKLER[0][0], "en") === "***");
bak("boş metin uygun", adUygun("") && adUygun("   ") && adUygun(null));

console.log(`Süzgeç testi: ${ok} geçti, ${hata} hatalı (elle örnek ${OLUMLU_ORNEKLER.length}, türetilen ${turetilen}, masum ${masum.length + BOT_ADLARI.length + 16 + MASUM_KELIMELER_TR.length + MASUM_KELIMELER_EN.length})`);
if (yanlis.length) {
  console.log("Hatalı:");
  for (const y of yanlis) console.log("  - " + y);
}
process.exit(hata ? 1 : 0);
