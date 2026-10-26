// Yakınlık sesi (maç sürerken): koridordaki oyuncu, kapısı açık hücredeki oyuncuyu duyar; kapı kapalıysa duymaz.
// Kapı durumu "kapi" mesajı hiç gelmese de konum nabzındaki "kp" (açık kapılar) listesinden öğrenilir
// (oda uyuyup uyanınca kapılar unutuluyordu: koridorda ses gitmiyordu).
//   cd server && node test/yakin_ses_test.mjs      (yerel sunucu 8794 açıkken; SRV ile değiştirilebilir)
const URL0 = process.env.SRV || "ws://127.0.0.1:8794";
const KOD = "YS" + Math.floor(Math.random() * 90 + 10);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let gecti = 0;
let kaldi = 0;
const bak = (ad, ok) => {
  console.log((ok ? "  OK   " : "  HATA ") + ad);
  ok ? gecti++ : kaldi++;
};

function istemci(ad, kur) {
  return new Promise((res) => {
    const ws = new WebSocket(`${URL0}/oda/${KOD}?ad=${ad}&kur=${kur ? 1 : 0}&davet=1&dil=tr`);
    ws.binaryType = "arraybuffer";
    const c = { ws, ad, id: 0, ses: 0, oyun: null };
    c.send = (o) => ws.send(JSON.stringify(o));
    ws.onmessage = (e) => {
      if (typeof e.data !== "string") return void c.ses++;
      if (e.data === "pong") return;
      const d = JSON.parse(e.data);
      if (d.t === "hosgeldin") {
        c.id = d.id;
        c.send({ t: "hazir", on: true });
        res(c);
      }
      if (d.t === "oyun") c.oyun = d;
    };
  });
}

const a = await istemci("Ali", true);
await sleep(400);
const b = await istemci("Bea", false);
const c = await istemci("Can", false);
await sleep(800);
a.send({ t: "basla", hiz: 1, oyunlar: ["tahta"] });
for (let i = 0; i < 100 && !(a.oyun && a.oyun.phase !== "baslangic"); i++) await sleep(100);
bak("maç başladı (" + (a.oyun ? a.oyun.phase : "-") + ")", a.oyun && a.oyun.phase !== "baslangic");

// Ali koridorda (x 3.9), Bea 2 numaralı hücrede (z -9.9), Can uzakta 7. hücrede
const konum = (k, x, z, kp) => k.send({ t: "konum", p: [x, z], y: 0, o: false, ...(kp ? { kp } : {}) });
const konustur = async (k) => {
  for (let i = 0; i < 10; i++) {
    k.ws.send(new Uint8Array(640).fill(128 + (i % 7)));
    await sleep(40);
  }
  await sleep(400);
};
konum(a, 3.9, -9.9);
konum(c, 0, 23.1);
konum(b, 0, -9.9, []); // kapılar kapalı
await sleep(500);
a.ses = 0;
await konustur(b);
bak("kapı kapalıyken koridordaki Ali Bea'yı duymuyor (" + a.ses + ")", a.ses === 0);

// "kapi" mesajı hiç gönderilmeden (oda uyanmış gibi) nabızdaki açık kapı listesiyle
konum(b, 0, -9.9, [2]);
await sleep(500);
a.ses = 0;
c.ses = 0;
await konustur(b);
bak("kapı açıkken (nabızdan öğrenildi) Ali Bea'yı duyuyor (" + a.ses + " parça)", a.ses >= 8);
bak("uzaktaki Can duymuyor (" + c.ses + ")", c.ses === 0);

// Ali Bea'nın hücresine girer: aynı bölge, kapı kapansa da duyar
konum(a, 0.8, -9.0);
b.send({ t: "kapi", cell: 2, open: false });
await sleep(500);
a.ses = 0;
await konustur(b);
bak("aynı hücrede kapı kapalıyken de duyuyor (" + a.ses + " parça)", a.ses >= 8);
// Ali konuşur, Bea duyar (iki yönlü)
b.ses = 0;
await konustur(a);
bak("Bea da Ali'yi duyuyor (" + b.ses + " parça)", b.ses >= 8);

for (const k of [a, b, c]) k.ws.close();
console.log(`\n${gecti} geçti, ${kaldi} hatalı`);
process.exit(kaldi ? 1 : 0);
