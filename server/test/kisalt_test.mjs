// Herkes seçimini yapınca süre 15 sn'ye iner: Kim Kim? (eşleştirme) ve Yalancı (oy).
//   cd server && node test/kisalt_test.mjs      (yerel sunucu 8794 açıkken; SRV ile değiştirilebilir)
// 3 gerçek istemci oda kurar, HAZIR der; Kim Kim? telefon aşamasında (180 sn) üçü de kaydeder -> kalan <= 15 sn
// ve "bilgi" (kisaldi) gelir. Sonra Yalancı oylamada (hiz=1: 30 sn) üçü de oy verir -> kalan <= 15 sn.
import { hesapAc } from "./_hesap.mjs";
const URL0 = process.env.SRV || "ws://127.0.0.1:8794";

// misafir odaya giremez: her oyuncu adı için bir test hesabı açılır (aynı ad = aynı hesap; geri dönen oyuncu da)
const _hesaplar = {};
const hesabi = async (ad) => (_hesaplar[ad] ||= await hesapAc(URL0, "t" + ad));
const KOD = "KS" + Math.floor(Math.random() * 90 + 10);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let gecti = 0;
let kaldi = 0;
const bak = (ad, ok) => {
  console.log((ok ? "  OK   " : "  HATA ") + ad);
  ok ? gecti++ : kaldi++;
};

async function istemci(ad, kur) {
  const h = await hesabi(ad);
  return new Promise((res) => {
    const ws = new WebSocket(`${URL0}/oda/${KOD}?ad=${ad}&kur=${kur ? 1 : 0}&davet=1&dil=tr&hesap=${h.token}`);
    const c = { ws, ad, id: 0, gizli: null, durum: null, olaylar: [], bilgi: [] };
    c.send = (o) => ws.send(JSON.stringify(o));
    ws.onmessage = (e) => {
      if (typeof e.data !== "string" || e.data === "pong") return;
      const d = JSON.parse(e.data);
      if (d.t === "hosgeldin") {
        c.id = d.id;
        c.send({ t: "hazir", on: true });
        res(c);
      }
      if (d.t === "gizli") c.gizli = d;
      if (d.t === "oyun") c.olaylar.push({ ...d, an: Date.now() });
      if (d.t === "bilgi" && d.kisaldi) c.bilgi.push(d);
    };
  });
}

async function bekle(c, f, sn) {
  for (let i = 0; i < sn * 10; i++) {
    const x = c.olaylar.find(f);
    if (x) return x;
    await sleep(100);
  }
  return null;
}

const a = await istemci("Ali", true);
await sleep(500);
const b = await istemci("Bea", false);
const c = await istemci("Can", false);
await sleep(800);
a.send({ t: "basla", hiz: 1, oyunlar: ["kimkim", "yalanci"] });

// --- Kim Kim? ---
const tel = await bekle(a, (d) => d.task === "kimkim" && d.phase === "telefon", 40);
bak("Kim Kim? telefon aşaması başladı (" + (tel ? tel.kalan : "-") + " sn)", tel && tel.kalan > 100);
for (const k of [a, b, c]) {
  const s = k.gizli;
  const hatlar = [];
  for (let n = 1; n <= s.toplam; n++) if (n !== s.hat) hatlar.push(n);
  const es = {};
  hatlar.forEach((n, i) => (es[n] = s.adaylar[i].id));
  k.olaylar.length = 0;
  k.send({ t: "karar", v: { eslesme: es } });
  await sleep(300);
}
const kis = await bekle(a, (d) => d.task === "kimkim" && d.phase === "telefon", 5);
bak("herkes kaydedince kalan " + (kis ? kis.kalan : "-") + " sn (≤ 15)", kis && kis.kalan <= 15 && kis.kalan >= 13);
bak("herkese 'son 15 saniye' bildirimi", [a, b, c].every((k) => k.bilgi.length === 1));
const t0 = Date.now();
const sonuc = await bekle(a, (d) => d.task === "kimkim" && d.phase === "sonuc", 25);
bak("Kim Kim? ~15 sn sonra bitti (" + ((Date.now() - t0) / 1000).toFixed(1) + " sn)", sonuc && Date.now() - t0 < 17500);

// --- Yalancı ---
const oy = await bekle(a, (d) => d.task === "yalanci" && d.phase === "oylama", 170);
bak("Yalancı oylama başladı (" + (oy ? oy.kalan : "-") + " sn)", oy && oy.kalan > 20);
for (const k of [a, b, c]) {
  k.olaylar.length = 0;
  k.bilgi.length = 0;
  k.send({ t: "karar", v: { oy: [a, b, c].find((x) => x !== k).id } });
  await sleep(300);
}
const kis2 = await bekle(a, (d) => d.task === "yalanci" && d.phase === "oylama", 5);
bak("herkes oy verince kalan " + (kis2 ? kis2.kalan : "-") + " sn (≤ 15)", kis2 && kis2.kalan <= 15 && kis2.kalan >= 13);
// fikrini değiştirmek: oy yeniden verilebilir, süre yeniden kısalmaz/uzamaz
a.send({ t: "karar", v: { oy: c.id } });
await sleep(500);
bak("oy değiştirince ikinci bildirim gelmedi", a.bilgi.length === 1);

for (const k of [a, b, c]) k.ws.close();
console.log(`\n${gecti} geçti, ${kaldi} hatalı`);
process.exit(kaldi ? 1 : 0);
