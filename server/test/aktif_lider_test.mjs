// Sıralama ekranındaki "AKTİF" listesi (liderlik cevabında aktif, aktif_sayi) ve günlük ödülün yeni değeri, yerel sunucuda.
//   cd server && npx wrangler dev --port 8794 --local   (ayrı pencerede)  ->  node test/aktif_lider_test.mjs
import { hesapAc, bagla as hesapBagla } from "./_hesap.mjs";
const URL0 = process.env.SRV || "ws://127.0.0.1:8794";
let ok = 0, hata = 0;
const bak = (ad, k, ek = "") => (k ? ok++ : (hata++, console.log("  HATA " + ad, ek)));
const a = await hesapAc(URL0, "aktifa");
const b = await hesapAc(URL0, "aktifb");
const ca = await hesapBagla(URL0, a.token);
const cb = await hesapBagla(URL0, b.token);
ca.ws.send(JSON.stringify({ t: "liderlik" }));
const l = await ca.bekle((d) => d.t === "liderlik");
bak("liderlik cevabı geldi", !!l);
bak("aktif listesi var", Array.isArray(l?.aktif), JSON.stringify(l).slice(0, 200));
bak("iki hesap da aktifte", l?.aktif?.some((x) => x.handle === a.handle && x.ben) && l?.aktif?.some((x) => x.handle === b.handle && !x.ben), JSON.stringify(l?.aktif));
bak("aktif_sayi en az 2", (l?.aktif_sayi || 0) >= 2);
cb.ws.close();
await new Promise((r) => setTimeout(r, 1500));
ca.ws.send(JSON.stringify({ t: "liderlik" }));
const l2 = await ca.bekle((d) => d.t === "liderlik" && d !== l);
bak("çıkan hesap aktiften düştü", l2 && !l2.aktif.some((x) => x.handle === b.handle), JSON.stringify(l2?.aktif));
ca.ws.send(JSON.stringify({ t: "gunluk_al" }));
const o = await ca.bekle((d) => d.t === "odul");
bak("günlük ödül 3 elmas (1. gün)", o && o.elmas === 3, JSON.stringify(o));
ca.ws.close();
console.log(`aktif liderlik testi: ${ok} geçti, ${hata} hata`);
process.exit(hata ? 1 : 0);
