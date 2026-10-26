// Sunucu maç ortasında yeniden başlarsa (güncelleme/taşınma: bağlantılar "kapandı" haberi olmadan düşer)
// oyuncular aynı yere geri dönebilmeli ve maç bitmeli.
// Yalnız AYRI bir sunucu kopyasıyla çalıştır (yeniden başlatmak için kopyanın bir dosyasına dokunulur):
//   KOPYA=../build/qa2/kopya  (içinde src/ ve wrangler.toml)
//   npx wrangler dev -c $KOPYA/wrangler.toml --port 8797 --persist-to ../build/qa2/wr_durum
//   SRV=ws://127.0.0.1:8797 KOPYA=../build/qa2/kopya node test/yeniden_baslama_test.mjs
import fs from "node:fs";
import crypto from "node:crypto";

const SRV = process.env.SRV || "ws://127.0.0.1:8797";
const KOPYA = process.env.KOPYA;
if (!KOPYA) {
  console.log("KOPYA verilmedi (sunucu kopyası olmadan bu test koşmaz)");
  process.exit(0);
}
let ok = 0;
let hata = 0;
function bak(ad, kosul, ek = "") {
  if (kosul) ok++, console.log("  OK   " + ad);
  else hata++, console.log("  HATA " + ad + (ek ? "  -> " + ek : ""));
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const CH = "ABCDEFGHJKLMNPRSTUVYZ23456789";
const kod = Array.from({ length: 4 }, () => CH[Math.floor(Math.random() * CH.length)]).join("");

// Telefon gibi davranan istemci: oyun sürerken bağlantı koparsa 2 sn arayla 45 sn boyunca aynı anahtarla yeniden dener
class C {
  constructor(ad, kur) {
    this.ad = ad;
    this.kur = kur;
    this.hesap = crypto.randomBytes(16).toString("hex");
    this.msgs = [];
    this.geriSay = 0;
    this.bitti = null;
  }
  ac(tekrar = "") {
    return new Promise((res) => {
      const ws = new WebSocket(`${SRV}/oda/${kod}?ad=${this.ad}&kur=${this.kur && !tekrar ? 1 : 0}&davet=1&hesap=${this.hesap}&dil=tr${tekrar ? "&tekrar=" + tekrar : ""}`);
      this.ws = ws;
      ws.onmessage = (e) => {
        if (typeof e.data !== "string" || e.data === "pong") return;
        const d = JSON.parse(e.data);
        this.msgs.push(d);
        if (d.t === "hosgeldin") {
          this.id = d.id;
          this.tekrar = d.tekrar;
          if (d.geri) this.geriSay++, ws.send(JSON.stringify({ t: "durum" }));
          else ws.send(JSON.stringify({ t: "hazir", on: true }));
          res(d);
        }
        if (d.t === "hata") res(d);
        if (d.t === "basladi") this.oyunda = true;
        if (d.t === "bitti") (this.bitti = d), (this.oyunda = false);
        if (d.t === "oyun" && d.task === "ortalama" && d.phase === "yaz1") ws.send(JSON.stringify({ t: "karar", v: { sayi: Math.floor(Math.random() * 50) } }));
      };
      ws.onclose = () => {
        if (this.ws !== ws) return;
        res(null);
        if (this.oyunda && !this.yenilen) this.yenile();
      };
    });
  }
  async yenile() {
    this.yenilen = true;
    const t0 = Date.now();
    while (Date.now() - t0 < 45000) {
      await sleep(2000);
      const d = await this.ac(this.tekrar);
      if (d && d.t === "hosgeldin") break;
    }
    this.yenilen = false;
  }
}

const cs = [new C("A", true), new C("B"), new C("C"), new C("D")];
await cs[0].ac();
for (const c of cs.slice(1)) await c.ac();
cs[0].ws.send(JSON.stringify({ t: "bot_ekle" }));
await sleep(500);
cs[0].ws.send(JSON.stringify({ t: "basla", hiz: 0.3, oyunlar: ["ortalama", "c4", "ortalama"] }));
await sleep(9000);
bak("maç başladı", cs.every((c) => c.oyunda));
// sunucuyu yeniden başlat: kopyanın bir dosyasına dokun (wrangler yeniden yükler, bütün bağlantılar düşer)
const dosya = KOPYA + "/src/metin.js";
fs.appendFileSync(dosya, "\n// yeniden başlatma testi " + Date.now() + "\n");
console.log("  (sunucu yeniden başlatıldı)");
const t0 = Date.now();
while (Date.now() - t0 < 150000 && !cs.every((c) => c.bitti)) await sleep(1000);
bak("dört oyuncu da aynı numarayla geri döndü", cs.every((c) => c.geriSay >= 1), cs.map((c) => c.ad + ":" + c.geriSay).join(" "));
bak("maç bitti, herkes sonucu aldı", cs.every((c) => c.bitti), cs.map((c) => c.ad + ":" + !!c.bitti).join(" "));
const b = cs[0].bitti;
if (b) {
  bak("tabloda 5 oyuncu (4 insan + bot), kimse ayrılmış sayılmadı", b.table.length === 5 && b.table.every((r) => !r.left), JSON.stringify(b.table.map((r) => [r.name, r.score, r.left])));
  bak("oyun puanları toplamı = puan", b.table.every((r) => r.p.reduce((x, y) => x + y, 0) === r.score));
}
// dosyayı eski haline getir
fs.writeFileSync(dosya, fs.readFileSync(dosya, "utf8").replace(/\n\/\/ yeniden başlatma testi \d+\n/g, ""));
for (const c of cs) c.ws.send(JSON.stringify({ t: "cik" })), (c.oyunda = false);
await sleep(300);
console.log(`\nyeniden başlama testi: ${ok} geçti, ${hata} hatalı`);
process.exit(hata ? 1 : 0);
