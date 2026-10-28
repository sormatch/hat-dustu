// Hızlı Oyun eşleştirme birim testi (sahte Durable Object; sunucu gerekmez):  cd server && node test/eslestirme_test.mjs
// Hesap başına tek bekleyen yer ayırma: aynı hesap art arda istese de açık odanın sayısı şişmez; oda gerçek sayıyı
// bildirince ayırma biter; yeniden arayan hesap az önce ayrıldığı odaya düşmez.
import { Eslestirme, PUBLIC_MAX } from "../src/eslestirme.js";

let ok = 0;
let hata = 0;
function bak(ad, kosul, ek = "") {
  if (kosul) ok++;
  else {
    hata++;
    console.log("HATA:", ad, ek);
  }
}

const depo = new Map();
const state = { storage: { get: async (k) => depo.get(k), put: async (k, v) => depo.set(k, v) } };
const es = new Eslestirme(state, {});
const hizli = async (hesap, ip = "5.5.5.5") => (await (await es.fetch(new Request("https://ic/hizli", { method: "POST", body: JSON.stringify({ hesap, ip }) }))).json()).kod;
const durum = (kod, n, hesaplar) => es.fetch(new Request("https://ic/durum", { method: "POST", body: JSON.stringify({ kod, n, hesaplar }) }));

// aynı hesap 20 kez ister: oda en çok 1 kişilik ayırma taşır
let kod = "";
const kodlar = new Set();
for (let i = 0; i < 20; i++) {
  kod = await hizli("hesap_a");
  kodlar.add(kod);
}
const toplam = Object.values(es.rooms).reduce((a, r) => a + r.n, 0);
bak("aynı hesabın art arda istekleri: toplam ayırma 1", toplam === 1, JSON.stringify(es.rooms));
bak("art arda isteklerde odalar dolmadı", Object.values(es.rooms).every((r) => r.n < PUBLIC_MAX));

// başka hesap: mevcut (1 kişilik) odaya gelir
const kodB = await hizli("hesap_b");
bak("ikinci hesap aynı odaya", kodB === kod && es.rooms[kod].n === 2, JSON.stringify(es.rooms));

// oda gerçek sayıyı bildirdi (ikisi de girdi): ayırmalar biter, yeni istek o odayı düşürmez
await durum(kod, 2, ["hesap_a", "hesap_b"]);
bak("oda bildirince ayırmalar silindi", !es.ayirma.has("hesap_a") && !es.ayirma.has("hesap_b"));
const kodC = await hizli("hesap_c");
bak("üçüncü hesap aynı odaya", kodC === kod && es.rooms[kod].n === 3);

// C odaya giremedi, hemen yeniden arıyor: ayırması geri alınır, aynı oda seçilmez
const kodC2 = await hizli("hesap_c");
bak("yeniden arayanın eski ayırması geri alındı", es.rooms[kod].n === 2, JSON.stringify(es.rooms[kod]));
bak("yeniden arayan aynı odaya düşmedi", kodC2 !== kod);

// süresi dolan ayırma geri alınmaz (oda bu arada kendi sayısını bildirmiş sayılır)
es.ayirma.get("hesap_c").ts -= 60000;
const n0 = es.rooms[kodC2].n;
await hizli("hesap_c");
bak("eski ayırma (süresi dolmuş) sayıyı düşürmez", es.rooms[kodC2].n === n0, JSON.stringify(es.rooms[kodC2]));

console.log(`eslestirme_test: ${ok} doğru, ${hata} hata`);
process.exit(hata ? 1 : 0);
