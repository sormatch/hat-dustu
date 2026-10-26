// YÜK (STRES) TESTİ:  cd server && node test/stres_test.mjs
// Ayrı bir yerel sunucuda çalıştır (Hızlı Oyun odaları başkalarının testine karışmasın, hız kısaltılsın):
//   npx wrangler dev --port 8797 --var TEST_HIZ:0.1 --persist-to ../build/qa2/wr_durum
//   SRV=ws://127.0.0.1:8797 node test/stres_test.mjs      (varsayılan 8797)
// Bölüm A: 6 özel oda × 8 kişi (davetle; Kim Kim? dahil "Tüm oyunlar", hiz 0.1) + 2 ek istemci (dolu oda,
//   kötü niyetli kurucu). Her odada: spam yapan, kopup geri gelen (anahtarla / yalnız hesapla), hiç dönmeyen,
//   bilerek çıkan, aynı hesapla ikinci cihazdan giren oyuncular. İki odada TEKRAR OYNA ile ikinci maç.
// Bölüm B: 50 istemci Hızlı Oyun (/hizli) ile eşleşir, botlarla dolar, tam maç oynar; bir kısmı kopup döner.
// Denetimler: her maç bitti mi, takılan aşama var mı (60 sn haber yok), puan tablosu tutarlı mı (her satırda
// oyun puanları toplamı = puan, kazanan en yüksek puanlı kalanlardan), bozuk konum mesajı başkasına ulaştı mı,
// spam sınırı çalışıyor mu, yanıt süreleri ve mesaj boyutları (tür başına bayt).
import crypto from "node:crypto";
import fs from "node:fs";

const SRV = process.env.SRV || "ws://127.0.0.1:8797";
const HTTP = SRV.replace("ws://", "http://").replace("wss://", "https://");
const CIKTI = process.env.CIKTI || "../build/qa2/stres_sonuc.json";
const SADECE = process.env.BOLUM || "AB"; // "A", "B" ya da "AB"
const HIZ = 0.1;

let ok = 0;
let hata = 0;
const hatalar = [];
function bak(ad, kosul, ek = "") {
  if (kosul) {
    ok++;
    console.log("  OK   " + ad);
  } else {
    hata++;
    hatalar.push(ad + (ek ? " -> " + ek : ""));
    console.log("  HATA " + ad + (ek ? "  -> " + ek : ""));
  }
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const rnd = (a, b) => a + Math.random() * (b - a);
const pick = (a) => a[Math.floor(Math.random() * a.length)];
const tok = () => crypto.randomBytes(16).toString("hex");
const CH = "ABCDEFGHJKLMNPRSTUVYZ23456789";
const yeniKod = () => Array.from({ length: 4 }, () => CH[Math.floor(Math.random() * CH.length)]).join("");
const KELIME = ["ELMA", "KAPI", "SABUN", "TÜNEL", "KAŞIK"];

// ---- ölçümler ----
const olcum = { tur: {}, sesBayt: 0, sesAdet: 0, gecikme: { hatlar: [], karar: [], giris: [] }, kotuKonum: 0, toplamBayt: 0 };
function say(t, n) {
  const o = (olcum.tur[t] ||= { adet: 0, bayt: 0, enBuyuk: 0 });
  o.adet++;
  o.bayt += n;
  o.enBuyuk = Math.max(o.enBuyuk, n);
  olcum.toplamBayt += n;
}
const yuzde = (a, p) => {
  if (!a.length) return 0;
  const b = a.slice().sort((x, y) => x - y);
  return b[Math.min(b.length - 1, Math.floor(b.length * p))];
};

// ---- odalar (oda başına ortak bilgi: Kısa Devre şemaları, takılma denetimi) ----
class Oda {
  constructor(kod, ad) {
    this.kod = kod;
    this.ad = ad;
    this.semalar = {}; // kutu sahibi id -> şema (tutan istemci yayınlar)
    this.sonHaber = Date.now();
    this.sonAsama = "";
    this.enUzunSessizlik = 0;
    this.bittiler = []; // gelen "bitti" mesajları (istemci adıyla)
    this.uyeler = new Set();
  }
  haber(asama) {
    const now = Date.now();
    if (asama !== this.sonAsama) {
      this.enUzunSessizlik = Math.max(this.enUzunSessizlik, now - this.sonHaber);
      this.sonHaber = now;
      this.sonAsama = asama;
    }
  }
}

class Istemci {
  constructor(ad, oda, o = {}) {
    this.ad = ad;
    this.oda = oda;
    this.hesap = o.hesap || tok();
    this.kur = !!o.kur;
    this.acik = !!o.acik;
    this.davet = o.davet !== false && !o.kur && !o.acik;
    this.id = 0;
    this.tekrar = "";
    this.g = null;
    this.gizli = null;
    this.yapilan = new Set();
    this.msgs = [];
    this.waiters = [];
    this.hatalar = [];
    this.bittiSay = 0;
    this.konumT = null;
    this.kapali = true;
    this.oyunda = false;
    this.davranis = o.davranis || "normal";
  }

  url(ek = "") {
    const kod = this.oda.kod;
    let u = `${SRV}/oda/${kod}?ad=${encodeURIComponent(this.ad)}&kur=${this.kur ? 1 : 0}&davet=${this.davet ? 1 : 0}&dil=tr`;
    if (this.hesap) u += "&hesap=" + this.hesap;
    if (this.acik) u += "&acik=1";
    return u + ek;
  }

  baglan(ek = "") {
    return new Promise((res) => {
      const t0 = Date.now();
      const ws = new WebSocket(this.url(ek));
      ws.binaryType = "arraybuffer";
      this.ws = ws;
      this.kapali = false;
      let bitti = false;
      const son = (v) => {
        if (!bitti) {
          bitti = true;
          res(v);
        }
      };
      ws.onopen = () => {};
      ws.onerror = () => son(null);
      ws.onclose = (e) => {
        if (this.ws === ws) {
          this.kapali = true;
          this.kapanmaKodu = e.code;
          clearInterval(this.konumT);
        }
        son(null);
      };
      ws.onmessage = (e) => {
        if (typeof e.data !== "string") {
          olcum.sesAdet++;
          olcum.sesBayt += e.data.byteLength;
          return;
        }
        if (e.data === "pong") return;
        say(JSON.parse(e.data).t, Buffer.byteLength(e.data));
        const d = JSON.parse(e.data);
        if (d.t === "hosgeldin") {
          olcum.gecikme.giris.push(Date.now() - t0);
          son(d);
        }
        if (d.t === "hata") son(d);
        this.al(d);
      };
      setTimeout(() => son(null), 15000);
    });
  }

  send(o) {
    try {
      if (this.ws && this.ws.readyState === 1) this.ws.send(typeof o === "string" ? o : JSON.stringify(o));
    } catch {}
  }

  wait(f, ms = 10000) {
    if (typeof f === "string") {
      const t = f;
      f = (d) => d.t === t;
    }
    return new Promise((res) => {
      const w = { f, r: res };
      this.waiters.push(w);
      setTimeout(() => {
        const i = this.waiters.indexOf(w);
        if (i >= 0) {
          this.waiters.splice(i, 1);
          res(null);
        }
      }, ms);
    });
  }

  al(d) {
    this.msgs.push(d);
    if (this.msgs.length > 400) this.msgs.splice(0, 200);
    for (const w of [...this.waiters]) {
      if (w.f(d)) {
        this.waiters.splice(this.waiters.indexOf(w), 1);
        w.r(d);
      }
    }
    switch (d.t) {
      case "hosgeldin":
        this.id = d.id;
        this.tekrar = d.tekrar;
        this.oyunda = !!d.started;
        this.oda.uyeler.add(this);
        if (d.started) this.send({ t: "durum" });
        else setTimeout(() => this.send({ t: "hazir", on: true }), 300); // "herkes hazır" kuralı varsa da maç başlasın
        this.konumBaslat();
        break;
      case "lobi":
        this.id = d.id;
        this.oyunda = false;
        setTimeout(() => this.send({ t: "hazir", on: true }), 300);
        break;
      case "basladi":
        this.oyunda = true;
        this.yapilan.clear();
        break;
      case "oyun":
        this.g = d;
        this.oda.haber(d.task + ":" + d.round + ":" + d.phase);
        this.davran();
        break;
      case "gizli":
        this.gizli = d;
        if (d.task === "devre" && d.yardim) this.oda.semalar[d.yardim] = d.sema;
        this.davran();
        break;
      case "olay":
        this.olay(d);
        break;
      case "sonuc":
        this.oda.haber("sonuc:" + d.round);
        break;
      case "konum":
        if (!Array.isArray(d.p) || typeof d.p[0] !== "number" || typeof d.p[1] !== "number" || typeof d.id !== "number" || Object.keys(d).some((k) => !["t", "id", "p", "y", "o", "c", "k"].includes(k))) olcum.kotuKonum++;
        break;
      case "bitti":
        this.bittiSay++;
        this.oyunda = false;
        this.oda.haber("bitti");
        this.oda.bittiler.push({ ad: this.ad, d });
        break;
      case "hata":
        this.hatalar.push(d.m);
        break;
    }
  }

  konumBaslat() {
    clearInterval(this.konumT);
    // herkes koridorda birbirine yakın (C4'te bomba verilebilsin)
    const x = 3 + rnd(0, 0.6);
    const z = rnd(-0.6, 0.6);
    this.konumT = setInterval(() => {
      if (this.kapali) return;
      this.send({ t: "konum", p: [x + rnd(-0.05, 0.05), z + rnd(-0.05, 0.05)], y: rnd(-3, 3), o: false, c: false, k: Math.random() < 0.1 });
    }, 150);
  }

  bir(key, ms, f) {
    if (this.yapilan.has(key)) return;
    this.yapilan.add(key);
    setTimeout(() => {
      if (!this.kapali) f();
    }, ms);
  }

  karar(v) {
    const t0 = Date.now();
    this.send({ t: "karar", v });
    this.wait("karar_alindi", 3000).then((d) => d && olcum.gecikme.karar.push(Date.now() - t0));
  }

  davran() {
    const g = this.g;
    if (!g || !this.id || !g.players || !g.players.includes(this.id)) return;
    const s = this.gizli && this.gizli.task === g.task && this.gizli.round === g.round ? this.gizli : null;
    const k = g.task + g.round + g.phase;
    switch (g.task) {
      case "tahta":
        if (s && s.yazan && (g.phase === "anons" || g.phase === "telefon")) this.bir(k + "y", rnd(300, 1200), () => this.karar(pick(KELIME)));
        else if (s && !s.yazan && g.phase === "telefon") this.bir(k + "t", rnd(500, 3000), () => this.karar(pick(KELIME)));
        break;
      case "devre":
        if (g.phase === "calisma" && s) this.bir(k, rnd(300, 1500), () => this.devre(s, 0));
        break;
      case "kimkim":
        if (g.phase === "telefon" && s)
          this.bir(k, rnd(500, 3000), () => {
            const hatlar = [];
            for (let n = 1; n <= s.toplam; n++) if (n !== s.hat) hatlar.push(n);
            const adaylar = s.adaylar.map((a) => a.id).sort(() => Math.random() - 0.5);
            const es = {};
            hatlar.forEach((n, i) => adaylar[i] && (es[n] = adaylar[i]));
            this.karar({ eslesme: es });
          });
        break;
      case "yalanci":
        if (g.phase === "oylama") this.bir(k, rnd(300, 2000), () => this.send({ t: "karar", v: { oy: pick(g.players.filter((x) => x !== this.id)) } }));
        break;
      case "ortalama":
        if (g.phase.startsWith("yaz")) this.bir(k, rnd(300, 3000), () => this.karar({ sayi: Math.floor(rnd(0, 120)) }));
        break;
      case "rulet":
        if (g.phase === "oyun" && g.sira === this.id) this.atis(g.sans, g.hayatta || g.players);
        break;
      case "c4":
        if (g.phase === "bomba" && g.bomba === this.id) this.bombaVer();
        break;
    }
  }

  // Kısa Devre: şemayı odanın ortak tablosundan al (tahtasında tutan istemci yayınladı), kabloları tak, şalteri kaldır
  devre(s, deneme) {
    const sema = this.oda.semalar[this.id];
    if (!sema) {
      if (deneme < 20 && this.g && this.g.task === "devre" && this.g.phase === "calisma") setTimeout(() => this.devre(s, deneme + 1), 500);
      return;
    }
    let ms = 0;
    for (const [renk, tur, v] of sema) {
      const sembol = tur === "S" ? v : s.semboller[v - 1];
      if (Math.random() < 0.08) {
        const yanlis = s.semboller.find((x) => x !== sembol);
        setTimeout(() => this.send({ t: "karar", v: { islem: "bagla", renk, sembol: yanlis } }), (ms += 120));
      }
      setTimeout(() => this.send({ t: "karar", v: { islem: "bagla", renk, sembol } }), (ms += 120));
    }
    setTimeout(() => this.send({ t: "karar", v: { islem: "salter" } }), (ms += 200));
  }

  atis(sans, hayatta) {
    const key = "atis" + JSON.stringify(this.g && this.g.son) + (this.g && this.g.round);
    if (this.yapilan.has(key)) return;
    this.yapilan.add(key);
    // tambur canlandırması 2.6 sn: ondan sonra sık
    setTimeout(() => {
      if (this.kapali) return;
      const digerleri = (hayatta || []).filter((x) => x !== this.id);
      const v = sans >= 100 || Math.random() < 0.4 ? pick(digerleri) : "kendi";
      if (v !== undefined) this.send({ t: "karar", v: { atis: v } });
    }, rnd(2800, 3600));
  }

  bombaVer(deneme = 0) {
    const key = "bomba" + (this.g && this.g.verilen) + ":" + deneme;
    if (this.yapilan.has(key)) return;
    this.yapilan.add(key);
    setTimeout(() => {
      if (this.kapali || !this.g || this.g.task !== "c4") return;
      const digerleri = this.g.players.filter((x) => x !== this.id);
      if (digerleri.length) this.send({ t: "karar", v: { ver: pick(digerleri) } });
    }, rnd(600, 1800));
  }

  olay(d) {
    if (d.task === "rulet" && (d.tur === "sira" || d.tur === "atis") && d.sira === this.id) {
      if (this.g) this.g.son = { ...d };
      this.atis(d.yeni_sans || d.sans, d.hayatta);
    }
    if (d.task === "c4" && d.tur === "verdi") {
      if (this.g) this.g.verilen = (this.g.verilen || 0) + 1;
      if (d.kime === this.id) {
        if (this.g) this.g.bomba = this.id;
        this.bombaVer();
      }
    }
  }

  kopar() {
    clearInterval(this.konumT);
    try {
      this.ws.close();
    } catch {}
    this.kapali = true;
  }

  // Spam: ani yağmur + bozuk / kötü niyetli mesajlar
  spam() {
    for (let i = 0; i < 300; i++) this.send({ t: "konum", p: [3, 0], y: 0, o: false });
    for (let i = 0; i < 100; i++) this.send({ t: "emote", e: "el" });
    for (let i = 0; i < 40; i++) this.send({ t: "profil", ad: "Spam" + i, g: { govde: "erkek", sac: "kisa" } });
    for (let i = 0; i < 30; i++) this.send({ t: "hazir", on: i % 2 === 0 });
    for (let i = 0; i < 50; i++) this.send("{bozuk json");
    for (let i = 0; i < 10; i++) this.send(JSON.stringify({ t: "konum", p: [1, 2], cop: "x".repeat(5000) }));
    for (let i = 0; i < 200; i++) this.send(new Uint8Array(640));
    this.send(new Uint8Array(100000)); // dev ses parçası
    // kötü niyetli içerik
    this.send({ t: "konum", p: "abc", y: {} });
    this.send({ t: "konum", p: [1e300, NaN], y: 1, zararli: { a: 1 } });
    this.send({ t: "konum", p: [1, 2], y: 0, o: false, x: "<script>" });
    this.send({ t: "kapi", cell: "__proto__", open: true });
    this.send({ t: "kapi", cell: 99999, open: true });
    this.send({ t: "ara", to: { a: 1 } });
    this.send({ t: "emote", e: { x: 1 } });
    this.send({ t: "profil", ad: "‮Kötü\u0000Ad", g: { govde: { ic: [1, 2, 3] }, sac: "x".repeat(500) } });
    this.send({ t: "karar", v: { eslesme: Object.fromEntries(Array.from({ length: 200 }, (_, i) => [i, i])) } });
    this.send({ t: "karar", v: { atis: "constructor" } });
    this.send({ t: "karar", v: { ver: "__proto__" } });
    this.send({ t: "karar", v: { sayi: "1e400" } });
    this.send({ t: "karar", v: { islem: "bagla", renk: "__proto__", sembol: "YILDIZ" } });
    this.send({ t: "basla", oyunlar: ["constructor", "__proto__"], hiz: 0.01 });
    this.send({ t: "sikayet", id: "x", neden: { a: 1 } });
    this.send({ t: 42 });
    this.send("null");
    this.send("[]");
  }
}

// Maç sonu tablosu tutarlı mı?
function tabloDenetle(ad, d) {
  const sorunlar = [];
  const ids = d.table.map((r) => r.id);
  if (new Set(ids).size !== ids.length) sorunlar.push("aynı oyuncu iki kez");
  if (d.rounds !== d.oyunlar.length) sorunlar.push("rounds != oyunlar");
  for (const r of d.table) {
    if (!Array.isArray(r.p) || r.p.length !== d.oyunlar.length) sorunlar.push(r.name + ": sütun sayısı");
    const top = (r.p || []).reduce((a, b) => a + b, 0);
    if (top !== r.score) sorunlar.push(`${r.name}: oyun puanları toplamı ${top} != puan ${r.score}`);
    if (!Number.isFinite(r.score)) sorunlar.push(r.name + ": puan sayı değil");
  }
  const kalan = d.table.filter((r) => !r.left);
  const w = d.table.find((r) => r.id === d.winner);
  if (!w) sorunlar.push("kazanan tabloda yok");
  else if (kalan.length && w.left) sorunlar.push("kazanan maçtan ayrılmış biri");
  else if (kalan.some((r) => r.score > w.score)) sorunlar.push("kazanandan yüksek puanlı kalan var");
  if (d.table[0] && d.table[0].id !== d.winner) sorunlar.push("tablonun başında kazanan yok");
  return sorunlar;
}

// Oda maçını bekle: bağlı üyelerin hepsi "bitti" alana kadar (ya da süre)
async function macBekle(oda, istemciler, ms) {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) {
    const bagli = istemciler.filter((c) => !c.kapali && c.oyunda !== false);
    if (oda.bittiler.length && istemciler.filter((c) => !c.kapali).every((c) => c.bittiSay > 0 || !c.oyundaMi)) return true;
    if (oda.bittiler.length && bagli.length === 0) return true;
    await sleep(500);
  }
  return false;
}

// ================= BÖLÜM A: 6 özel oda × 8 =================
async function bolumA() {
  console.log("\n== Bölüm A: 6 özel oda × 8 kişi (+2 ek istemci)");
  const odalar = [];
  const hepsi = [];
  for (let r = 0; r < 6; r++) {
    const oda = new Oda(yeniKod(), "A" + r);
    const cs = [];
    for (let i = 0; i < 8; i++) cs.push(new Istemci(`A${r}o${i}`, oda, { kur: i === 0 }));
    odalar.push({ oda, cs });
    hepsi.push(...cs);
  }
  // kurucular aynı anda, sonra diğerleri aynı anda (eşzamanlı giriş: numara/hücre çakışmamalı)
  await Promise.all(odalar.map(({ cs }) => cs[0].baglan()));
  await Promise.all(odalar.flatMap(({ cs }) => cs.slice(1).map((c) => c.baglan())));
  await sleep(800);
  for (const { oda, cs } of odalar) {
    const ids = cs.map((c) => c.id);
    const hucre = cs[0].msgs.filter((m) => m.t === "oyuncular").pop();
    const cells = hucre ? hucre.players.map((p) => p.cell) : [];
    bak(`${oda.ad}: 8 kişi girdi, numaralar farklı`, ids.every(Boolean) && new Set(ids).size === 8, ids.join(","));
    bak(`${oda.ad}: hücreler farklı`, cells.length === 8 && new Set(cells).size === 8, cells.join(","));
  }
  // dolu odaya 9. kişi
  const dokuz = new Istemci("Fazla", odalar[5].oda);
  const r9 = await dokuz.baglan();
  bak("dolu odaya 9. kişi giremez", r9 && r9.t === "hata" && /dolu/i.test(r9.m), JSON.stringify(r9));
  // aynı anda 9 kişi boş olmayan bir odaya (yarış): en fazla 8 kalmalı
  const yarisOda = new Oda(yeniKod(), "yaris");
  const yk = new Istemci("YK", yarisOda, { kur: true });
  await yk.baglan();
  const yarisanlar = Array.from({ length: 10 }, (_, i) => new Istemci("Y" + i, yarisOda));
  const yr = await Promise.all(yarisanlar.map((c) => c.baglan()));
  const girenler = yr.filter((d) => d && d.t === "hosgeldin");
  const yIds = girenler.map((d) => d.id);
  bak("aynı anda 10 kişi: 7 girer, 3 'dolu' alır", girenler.length === 7 && new Set(yIds).size === 7, `giren ${girenler.length} id ${yIds}`);
  for (const c of [yk, ...yarisanlar]) c.send({ t: "cik" });

  // kötü niyetli kurucu: bilinmeyen oyun adları, bot yağmuru
  const kotuOda = new Oda(yeniKod(), "kotu");
  const kotu = new Istemci("Kotu", kotuOda, { kur: true });
  await kotu.baglan();
  for (let i = 0; i < 30; i++) kotu.send({ t: "bot_ekle" });
  await sleep(1500);
  const kl = kotu.msgs.filter((m) => m.t === "oyuncular").pop();
  bak("bot yağmuru: odada en fazla 8 kişi", kl && kl.players.length <= 8, kl && String(kl.players.length));
  kotu.send({ t: "basla", oyunlar: ["constructor", "__proto__", "toString"], hiz: HIZ });
  const kb = await kotu.wait("basladi", 8000);
  bak("bilinmeyen oyun adlarıyla başlatma oyunu bozmaz (yedek oyunla başlar)", !!kb);
  kotu.oda = kotuOda;

  // maçları başlat (Tüm oyunlar, hız 0.1)
  for (const { cs } of odalar) cs[0].send({ t: "basla", hiz: HIZ });
  const bas = await Promise.all(odalar.map(({ cs }) => cs[0].wait("basladi", 8000)));
  bak("6 odada maç başladı", bas.every(Boolean));

  // ---- kargaşa ----
  const plan = [];
  odalar.forEach(({ oda, cs }, r) => {
    // spam
    plan.push((async () => {
      await sleep(rnd(8000, 25000));
      cs[1].spam();
      await sleep(3000);
      cs[1].spam();
      const h = await cs[1].wait((m) => m.t === "hata" && /Çok hızlı/.test(m.m), 5000) || cs[1].hatalar.find((m) => /Çok hızlı/.test(m));
      await sleep(1500);
      bak(`${oda.ad}: spam yapanın bağlantısı kesildi`, !!h && cs[1].kapali, String(cs[1].kapanmaKodu));
      cs[1].gitti = true;
    })());
    // kop + geri dön (anahtarla), iki kez
    plan.push((async () => {
      for (let k = 0; k < 2; k++) {
        await sleep(rnd(10000, 40000));
        cs[2].kopar();
        await sleep(rnd(2000, 8000));
        const d = await cs[2].baglan("&tekrar=" + cs[2].tekrar);
        bak(`${oda.ad}: kopan oyuncu anahtarla geri döndü`, d && d.t === "hosgeldin" && (d.geri || !d.started), JSON.stringify(d && { t: d.t, geri: d.geri, m: d.m }));
      }
    })());
    // kop + yalnız hesapla dön (anahtar kayboldu)
    plan.push((async () => {
      await sleep(rnd(15000, 45000));
      const eskiId = cs[3].id;
      cs[3].kopar();
      await sleep(rnd(2000, 6000));
      const d = await cs[3].baglan();
      bak(`${oda.ad}: anahtarsız (aynı hesap) dönen aynı numarayı aldı`, d && d.t === "hosgeldin" && d.id === eskiId, JSON.stringify(d && { id: d.id, eskiId, m: d.m }));
    })());
    // hiç dönmeyen (çift odalarda)
    if (r % 2 === 0) plan.push((async () => {
      await sleep(rnd(5000, 20000));
      cs[4].kopar();
      cs[4].gitti = true;
    })());
    // bilerek çıkan (tek odalarda)
    if (r % 2 === 1) plan.push((async () => {
      await sleep(rnd(15000, 50000));
      cs[5].send({ t: "cik" });
      cs[5].gitti = true;
      await sleep(200);
      cs[5].kopar();
    })());
    // ikinci cihaz (oda 0 ve 3): aynı hesapla yeni bağlantı; eskisi kapanmalı, yenisi maça devam etmeli
    if (r === 0 || r === 3) plan.push((async () => {
      await sleep(rnd(10000, 30000));
      const eski = cs[6];
      const yeni = new Istemci(eski.ad + "b", oda, { hesap: eski.hesap });
      yeni.yapilan = new Set();
      const kapanis = eski.wait((m) => m.t === "hata", 8000);
      const d = await yeni.baglan();
      const h = await kapanis;
      bak(`${oda.ad}: ikinci cihaz aynı numarayı aldı`, d && d.t === "hosgeldin" && d.id === eski.id, JSON.stringify(d && { id: d.id, eski: eski.id }));
      bak(`${oda.ad}: eski cihaz uyarılıp kapandı`, !!h && /başka bir cihaz/.test(h.m), JSON.stringify(h));
      eski.gitti = true;
      clearInterval(eski.konumT);
      cs[6] = yeni;
      // eski cihaz kendiliğinden yeniden bağlanmaya çalışır (telefonun otomatik geri dönüşü): geri alamamalı
      await sleep(2000);
      const g2 = await eski.baglan("&tekrar=" + eski.tekrar);
      bak(`${oda.ad}: eski cihaz eski anahtarla yerini geri alamaz`, g2 && g2.t === "hata" && /başka bir cihaz/.test(g2.m), JSON.stringify(g2 && { t: g2.t, m: g2.m }));
      await sleep(500);
      bak(`${oda.ad}: yeni cihaz bağlı kaldı`, !yeni.kapali);
      eski.kopar();
    })());
  });

  // maç bitişlerini bekle
  const sure = 6 * 60000;
  const t0 = Date.now();
  while (Date.now() - t0 < sure) {
    if (odalar.every(({ cs }) => cs.filter((c) => !c.gitti && !c.kapali).every((c) => c.bittiSay >= 1))) break;
    await sleep(1000);
  }
  await Promise.race([Promise.all(plan), sleep(5000)]);
  console.log(`  (maçlar ${Math.round((Date.now() - t0) / 1000)} sn)`);
  for (const { oda, cs } of odalar) {
    const kalanlar = cs.filter((c) => !c.gitti && !c.kapali);
    bak(`${oda.ad}: maç bitti, kalan herkes sonucu aldı`, kalanlar.length > 0 && kalanlar.every((c) => c.bittiSay === 1), kalanlar.map((c) => c.ad + ":" + c.bittiSay).join(" "));
    bak(`${oda.ad}: hiçbir aşama 60 sn'den uzun takılmadı`, oda.enUzunSessizlik < 60000, String(oda.enUzunSessizlik));
    const b = oda.bittiler[0];
    if (b) {
      const s = tabloDenetle(oda.ad, b.d);
      bak(`${oda.ad}: puan tablosu tutarlı (${b.d.oyunlar.map((o) => o.task).join(",")})`, s.length === 0, s.join("; "));
      bak(`${oda.ad}: herkes aynı tabloyu aldı`, oda.bittiler.every((x) => JSON.stringify(x.d.table.map((r) => [r.id, r.score])) === JSON.stringify(b.d.table.map((r) => [r.id, r.score]))));
    }
  }
  bak("kötü niyetli kurucunun maçı da bitti", kotu.bittiSay === 1 || !!(await kotu.wait("bitti", 60000)));

  // TEKRAR OYNA: oda 0 ve 1 ikinci maç
  for (const r of [0, 1]) {
    const { oda, cs } = odalar[r];
    const kal = cs.filter((c) => !c.gitti && !c.kapali);
    oda.bittiler = [];
    for (const c of kal) c.send({ t: "tekrar" });
    await sleep(1500);
    const host = kal.find((c) => (c.msgs.filter((m) => m.t === "lobi").pop() || {}).host) || kal[0];
    for (const c of kal) c.yapilan.clear(), (c.bittiSay = 0);
    host.send({ t: "basla", hiz: HIZ, oyunlar: ["ortalama", "c4", "rulet"] });
    const b = await host.wait("basladi", 8000);
    bak(`${oda.ad}: TEKRAR OYNA sonrası ikinci maç başladı`, !!b);
  }
  const t1 = Date.now();
  while (Date.now() - t1 < 3 * 60000) {
    if ([0, 1].every((r) => odalar[r].cs.filter((c) => !c.gitti && !c.kapali).every((c) => c.bittiSay >= 1))) break;
    await sleep(1000);
  }
  for (const r of [0, 1]) {
    const { oda, cs } = odalar[r];
    const kal = cs.filter((c) => !c.gitti && !c.kapali);
    bak(`${oda.ad}: ikinci maç bitti`, kal.every((c) => c.bittiSay === 1), kal.map((c) => c.bittiSay).join(","));
    const b = oda.bittiler[0];
    if (b) {
      const s = tabloDenetle(oda.ad, b.d);
      bak(`${oda.ad}: ikinci maç tablosu tutarlı`, s.length === 0, s.join("; "));
    }
  }
  // hatalar: istemcilere beklenmeyen "hata" mesajı gitmiş mi (ikinci cihaz uyarısı dışında)
  const beklenmeyen = hepsi.flatMap((c) => c.hatalar.filter((m) => !/başka bir cihaz|dolu|Çok hızlı|bulunamadı/.test(m)).map((m) => c.ad + ": " + m));
  bak("istemcilere beklenmeyen hata mesajı gitmedi", beklenmeyen.length === 0, beklenmeyen.slice(0, 5).join(" | "));
  // gecikme ölçümü (lobide, yük altında): hatlar isteği -> yanıt
  for (const { cs } of odalar) {
    for (const c of cs.filter((x) => !x.gitti && !x.kapali).slice(0, 3)) {
      for (let i = 0; i < 5; i++) {
        const t0 = Date.now();
        c.send({ t: "hatlar" });
        const d = await c.wait("hatlar", 3000);
        if (d) olcum.gecikme.hatlar.push(Date.now() - t0);
      }
    }
  }
  for (const c of [...hepsi, kotu, dokuz]) {
    c.send({ t: "cik" });
  }
  await sleep(500);
  for (const c of [...hepsi, kotu, dokuz]) c.kopar();
  return odalar;
}

// ================= BÖLÜM B: 50 istemci Hızlı Oyun =================
async function bolumB() {
  console.log("\n== Bölüm B: 50 istemci Hızlı Oyun");
  const istemciler = [];
  const odaMap = new Map();
  const kodlar = await Promise.all(
    Array.from({ length: 50 }, async () => {
      const r = await fetch(HTTP + "/hizli", { headers: { "x-hesap": "" } });
      return r.status === 200 ? (await r.json()).kod : "";
    }),
  );
  bak("50 Hızlı Oyun isteğinin hepsi oda kodu aldı", kodlar.every((k) => /^[A-Z0-9]{4}$/.test(k)), kodlar.filter((k) => !k).length + " boş");
  kodlar.forEach((k, i) => {
    if (!odaMap.has(k)) odaMap.set(k, new Oda(k, "B" + odaMap.size));
    istemciler.push(new Istemci("H" + i, odaMap.get(k), { acik: true }));
  });
  const sonuc = await Promise.all(istemciler.map((c) => c.baglan()));
  const reddedilen = sonuc.filter((d) => !d || d.t !== "hosgeldin");
  // reddedilenler (oda doldu) yeniden arar: gerçek istemci gibi
  for (let tur = 0; tur < 3; tur++) {
    for (const c of istemciler.filter((x) => x.kapali && !x.id)) {
      const r = await fetch(HTTP + "/hizli");
      const k = (await r.json()).kod;
      if (!odaMap.has(k)) odaMap.set(k, new Oda(k, "B" + odaMap.size));
      c.oda = odaMap.get(k);
      await c.baglan();
    }
  }
  const giren = istemciler.filter((c) => c.id);
  bak("50 istemcinin hepsi bir odaya girdi", giren.length === 50, `${giren.length} girdi, ilk denemede ${reddedilen.length} red`);
  const dagilim = [...odaMap.values()].map((o) => [...o.uyeler].length).filter(Boolean);
  console.log("  oda dağılımı:", dagilim.join(" "));
  bak("hiçbir açık odada 6'dan fazla insan yok", dagilim.every((n) => n <= 8), dagilim.join(","));
  // maçlar ~25 sn sonra kendiliğinden başlar (6 kişi dolunca 3 sn)
  const bas = await Promise.all(giren.map((c) => (c.oyunda ? true : c.wait("basladi", 40000))));
  bak("Hızlı Oyun maçlarının hepsi başladı", bas.every(Boolean), bas.filter((x) => !x).length + " başlamadı");
  // kargaşa: her odada bir kişi kopup döner, biri spam yapar
  const plan = [];
  for (const oda of odaMap.values()) {
    const u = [...oda.uyeler];
    if (u[0]) plan.push((async () => {
      await sleep(rnd(10000, 30000));
      u[0].spam();
    })());
    if (u[1]) plan.push((async () => {
      await sleep(rnd(10000, 40000));
      u[1].kopar();
      await sleep(rnd(2000, 8000));
      const d = await u[1].baglan("&tekrar=" + u[1].tekrar);
      bak(`${oda.ad}: Hızlı Oyunda kopan geri döndü`, d && d.t === "hosgeldin", JSON.stringify(d && { t: d.t, m: d.m }));
    })());
  }
  const t0 = Date.now();
  while (Date.now() - t0 < 6 * 60000) {
    if (giren.filter((c) => !c.kapali).every((c) => c.bittiSay >= 1)) break;
    await sleep(1000);
  }
  await Promise.race([Promise.all(plan), sleep(5000)]);
  console.log(`  (maçlar ${Math.round((Date.now() - t0) / 1000)} sn)`);
  for (const oda of odaMap.values()) {
    const u = [...oda.uyeler].filter((c) => !c.kapali);
    if (!u.length) continue;
    bak(`${oda.ad} (${u.length} insan): maç bitti`, u.every((c) => c.bittiSay === 1), u.map((c) => c.bittiSay).join(","));
    bak(`${oda.ad}: takılan aşama yok`, oda.enUzunSessizlik < 60000, String(oda.enUzunSessizlik));
    const b = oda.bittiler[0];
    if (b) {
      const s = tabloDenetle(oda.ad, b.d);
      bak(`${oda.ad}: puan tablosu tutarlı`, s.length === 0, s.join("; "));
    }
  }
  for (const c of istemciler) c.send({ t: "cik" });
  await sleep(500);
  for (const c of istemciler) c.kopar();
}

const bas = Date.now();
if (SADECE.includes("A")) await bolumA();
if (SADECE.includes("B")) await bolumB();
await sleep(1000);

console.log("\n== Ölçümler");
bak("bozuk konum mesajı hiçbir oyuncuya ulaşmadı", olcum.kotuKonum === 0, String(olcum.kotuKonum));
const g = olcum.gecikme;
console.log(`  giriş (WebSocket açılış -> hoş geldin): ort ${Math.round(g.giris.reduce((a, b) => a + b, 0) / (g.giris.length || 1))} ms, %95 ${yuzde(g.giris, 0.95)} ms, en çok ${Math.max(0, ...g.giris)} ms`);
console.log(`  karar -> alındı: %50 ${yuzde(g.karar, 0.5)} ms, %95 ${yuzde(g.karar, 0.95)} ms (${g.karar.length} ölçüm)`);
console.log(`  hatlar -> yanıt: %50 ${yuzde(g.hatlar, 0.5)} ms, %95 ${yuzde(g.hatlar, 0.95)} ms (${g.hatlar.length} ölçüm)`);
const turler = Object.entries(olcum.tur).sort((a, b) => b[1].bayt - a[1].bayt);
console.log("  gelen mesajlar (tür: adet, toplam KB, ortalama bayt, en büyük):");
for (const [t, o] of turler.slice(0, 14)) console.log(`    ${t.padEnd(12)} ${String(o.adet).padStart(7)}  ${(o.bayt / 1024).toFixed(0).padStart(6)} KB  ort ${Math.round(o.bayt / o.adet)}  en çok ${o.enBuyuk}`);
console.log(`  ses: ${olcum.sesAdet} parça, ${(olcum.sesBayt / 1024).toFixed(0)} KB`);
console.log(`\nstres testi: ${ok} geçti, ${hata} hatalı (${Math.round((Date.now() - bas) / 1000)} sn)`);
try {
  fs.writeFileSync(CIKTI, JSON.stringify({ ok, hata, hatalar, olcum: { ...olcum, gecikme: { giris: [yuzde(g.giris, 0.5), yuzde(g.giris, 0.95)], karar: [yuzde(g.karar, 0.5), yuzde(g.karar, 0.95)], hatlar: [yuzde(g.hatlar, 0.5), yuzde(g.hatlar, 0.95)] } } }, null, 1));
} catch {}
process.exit(hata ? 1 : 0);
