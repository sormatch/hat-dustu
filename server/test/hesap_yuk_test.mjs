// HESAP SUNUCUSU YÜK TESTİ:  cd server && node test/hesap_yuk_test.mjs
// Ayrı, boş bir yerel sunucuda çalıştır (hesaplar gerçekten açılır):
//   npx wrangler dev --port 8798 --persist-to ../build/qa2/yuk_durum
//   SRV=ws://127.0.0.1:8798 N=400 F=15 node test/hesap_yuk_test.mjs
// N hesap açılır, her biri F komşusuyla arkadaş olur. Sonra:
//   1) Bağlanma fırtınası: hepsi aynı anda yeniden bağlanır (her bağlantı arkadaşlarına "çevrimiçi" yollar)
//   2) Durum yağmuru: herkes 2 sn'de bir oda durumunu değiştirir (her biri arkadaşlarının listesini yeniler)
// Her aşamada ayrı bir yoklama istemcisi "liste" ister; yanıt süresi sunucunun ne kadar meşgul olduğunu gösterir.
// Çıktı: aşama başına yoklama gecikmesi (ortanca / %95 / en çok) ve bağlanma süreleri.
import { bagla, hesapAc } from "./_hesap.mjs";

const SRV = process.env.SRV || "ws://127.0.0.1:8798";
const N = Number(process.env.N || 400);
const F = Number(process.env.F || 15);
const SURE = Number(process.env.SURE || 20000); // durum yağmuru süresi (ms)
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function ozet(dizi) {
  if (!dizi.length) return "veri yok";
  const s = [...dizi].sort((a, b) => a - b);
  const q = (p) => s[Math.min(s.length - 1, Math.floor(p * s.length))];
  return `ortanca ${q(0.5)} ms, %95 ${q(0.95)} ms, en çok ${s[s.length - 1]} ms (${s.length} ölçüm)`;
}

// sınırlı eşzamanlılıkla işler
async function sirayla(liste, es, f) {
  const sonuc = new Array(liste.length);
  let i = 0;
  await Promise.all(Array.from({ length: es }, async () => {
    while (i < liste.length) {
      const k = i++;
      sonuc[k] = await f(liste[k], k);
    }
  }));
  return sonuc;
}

// Yoklama: arka arkaya "liste" ister, her yanıtın süresini kaydeder
function yoklama(c) {
  const olcum = [];
  let dur = false;
  const dongu = (async () => {
    while (!dur) {
      const t0 = Date.now();
      const n0 = c.msgs.length;
      c.gonder({ t: "liste" });
      await c.bekle((d) => d.t === "liste" && c.msgs.indexOf(d) >= n0, 30000);
      c.msgs.length = 0;
      olcum.push(Date.now() - t0);
      await sleep(200);
    }
  })();
  return { olcum, async bitir() { dur = true; await dongu; } };
}

console.log(`Sunucu ${SRV}, ${N} hesap, her biri ${F} arkadaş`);
let t = Date.now();
const hesaplar = await sirayla(Array.from({ length: N }), 8, (_, i) => hesapAc(SRV, "y" + i));
console.log(`Hesaplar açıldı: ${((Date.now() - t) / 1000).toFixed(1)} sn`);

// Arkadaşlık: i, i+1..i+F ile karşılıklı istek (iki taraf da isteyince doğrudan arkadaş olur)
t = Date.now();
const baglar = await sirayla(hesaplar, 50, (h) => bagla(SRV, h.token));
await Promise.all(baglar.map((c) => c.bekle((d) => d.t === "ben")));
for (let i = 0; i < N; i++) for (let k = 1; k <= F; k++) baglar[i].gonder({ t: "istek", handle: hesaplar[(i + k) % N].handle });
await sleep(3000);
for (let i = 0; i < N; i++) for (let k = 1; k <= F; k++) baglar[(i + k) % N].gonder({ t: "istek", handle: hesaplar[i].handle });
// son istekler işlenene kadar bekle: son hesabın listesinde 2F arkadaş görünmeli
const son = baglar[N - 1];
for (let i = 0; i < 120; i++) {
  son.msgs.length = 0;
  son.gonder({ t: "liste" });
  const l = await son.bekle((d) => d.t === "liste", 30000);
  if (l && l.friends.length >= Math.min(2 * F, N - 1)) break;
  await sleep(1000);
}
console.log(`Arkadaşlıklar kuruldu: ${((Date.now() - t) / 1000).toFixed(1)} sn`);
for (const c of baglar) c.ws.close();
await sleep(3000);

// Yoklama istemcisi ayrı bir hesap (arkadaşı yok; ölçüm kendi yükünü katmasın)
const yok = await hesapAc(SRV, "yoklama");
const yc = await bagla(SRV, yok.token);
await yc.bekle((d) => d.t === "ben");

// Sakin ölçüm
let y = yoklama(yc);
await sleep(4000);
await y.bitir();
console.log("Boşta yoklama:            " + ozet(y.olcum));

// 1) Bağlanma fırtınası
y = yoklama(yc);
t = Date.now();
const bagSure = [];
const yeni = await Promise.all(hesaplar.map(async (h) => {
  const t0 = Date.now();
  const c = await bagla(SRV, h.token);
  await c.bekle((d) => d.t === "liste", 60000);
  bagSure.push(Date.now() - t0);
  return c;
}));
const firtina = Date.now() - t;
await sleep(2000);
await y.bitir();
console.log(`Bağlanma fırtınası:       hepsi ${(firtina / 1000).toFixed(1)} sn'de bağlandı`);
console.log("  bağlantı başına:        " + ozet(bagSure));
console.log("  yoklama:                " + ozet(y.olcum));

// 2) Durum yağmuru: herkes 2 sn'de bir oda durumunu değiştirir
y = yoklama(yc);
const KOD = "ABCDEFGHJKLMNPRSTUVYZ23456789";
let durumSay = 0;
const bitis = Date.now() + SURE;
await Promise.all(yeni.map(async (c, i) => {
  await sleep((i * 2000) / N);
  while (Date.now() < bitis) {
    const oda = Math.random() < 0.5 ? "" : Array.from({ length: 4 }, () => KOD[Math.floor(Math.random() * KOD.length)]).join("");
    c.gonder({ t: "durum", oda, oyun: false });
    c.msgs.length = 0;
    durumSay++;
    await sleep(2000);
  }
}));
await y.bitir();
console.log(`Durum yağmuru:            ${durumSay} durum mesajı, ${(durumSay / (SURE / 1000)).toFixed(0)}/sn`);
console.log("  yoklama:                " + ozet(y.olcum));

for (const c of yeni) c.ws.close();
yc.ws.close();
process.exit(0);
