// "Tekrar Oyna" testi:  cd server && node test/tekrar_test.mjs   (uçtan uca kısım yerel sunucu 8794 açıkken koşar)
// İki gerçek istemci + botlarla maç -> bitti -> ikisi de TEKRAR -> aynı oda lobide (kod, sahip, botlar aynı) -> yeni maç.
// Maç ödülü her maçta bir kez. Sahip çıkınca sahiplik devri, kalan lobide. Süre dolunca otomatik lobiye dönüş,
// maç bitmiş odaya yeni gelenin lobiye düşmesi. Birim kısmı: Hızlı Oyun odasının lobiye dönüşü (sahte Durable Object).
import crypto from "node:crypto";

const URL0 = process.env.SRV || "ws://127.0.0.1:8794";
let ok = 0;
let hata = 0;
function bak(ad, kosul, ek = "") {
  if (kosul) {
    ok++;
    console.log("  OK   " + ad);
  } else {
    hata++;
    console.log("  HATA " + ad + (ek ? "  -> " + ek : ""));
  }
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const tok = () => crypto.randomBytes(16).toString("hex");
const kod = () => {
  const c = "ABCDEFGHJKLMNPRSTUVYZ23456789";
  let s = "";
  for (let i = 0; i < 4; i++) s += c[Math.floor(Math.random() * c.length)];
  return s;
};

// WebSocket istemcisi: gelen mesajları biriktirir, koşullu bekler
class W {
  constructor(url, ad) {
    this.url = url;
    this.ad = ad;
    this.msgs = [];
    this.waiters = [];
  }
  open() {
    return new Promise((res, rej) => {
      this.ws = new WebSocket(this.url);
      this.ws.onopen = () => res(this);
      this.ws.onerror = (e) => rej(e);
      this.ws.onclose = () => (this.closed = true);
      this.ws.onmessage = (e) => {
        if (typeof e.data !== "string" || e.data === "pong") return;
        const d = JSON.parse(e.data);
        this.msgs.push(d);
        if (process.env.V) console.log(`  [${this.ad}] <-`, JSON.stringify(d).slice(0, 160));
        for (const w of [...this.waiters]) if (w.f(d)) {
          this.waiters.splice(this.waiters.indexOf(w), 1);
          w.r(d);
        }
      };
    });
  }
  send(o) {
    this.ws.send(JSON.stringify(o));
  }
  wait(f, ms = 5000) {
    if (typeof f === "string") {
      const t = f;
      f = (d) => d.t === t;
    }
    return new Promise((r) => {
      const w = { f, r };
      this.waiters.push(w);
      setTimeout(() => {
        const i = this.waiters.indexOf(w);
        if (i >= 0) {
          this.waiters.splice(i, 1);
          r(null);
        }
      }, ms);
    });
  }
  say(t) {
    return this.msgs.filter((d) => d.t === t).length;
  }
  close() {
    try {
      this.ws.close();
    } catch {}
  }
}

async function oda(code, ad, hesap, kur) {
  const w = new W(`${URL0}/oda/${code}?ad=${encodeURIComponent(ad)}&kur=${kur ? 1 : 0}&davet=${kur ? 0 : 1}&hesap=${hesap}&dil=tr`, ad);
  const p = w.wait("hosgeldin");
  await w.open();
  w.hos = await p;
  return w;
}

async function hesap(token, ad) {
  const w = new W(`${URL0}/hesap?token=${token}`, "hesap-" + ad);
  const p = w.wait("ben");
  await w.open();
  await p;
  return w;
}

async function ekonomi(h) {
  const p = h.wait("ekonomi");
  h.send({ t: "ekonomi" });
  return await p;
}

const benim = (w, list) => (list || []).find((p) => p.id === w.hos.id) || {};

// ---------------------------------------------------------------- birim: Hızlı Oyun odası lobiye döner
async function birim() {
  globalThis.WebSocketRequestResponsePair ||= class {
    constructor(a, b) {
      this.a = a;
      this.b = b;
    }
  };
  const { Room } = await import("../src/index.js");
  const depo = new Map();
  let alarm = 0;
  const soketler = [];
  const sok = (info) => {
    const s = { info, giden: [], serializeAttachment(x) { this.info = x; }, deserializeAttachment() { return this.info; }, send(m) { this.giden.push(JSON.parse(m)); } };
    soketler.push(s);
    return s;
  };
  const state = {
    setWebSocketAutoResponse() {},
    blockConcurrencyWhile: async (f) => f(),
    getWebSockets: () => soketler,
    storage: {
      get: async (k) => depo.get(k),
      put: async (k, v) => (typeof k === "object" ? Object.entries(k).forEach(([a, b]) => depo.set(a, b)) : depo.set(k, v)),
      delete: async (k) => (Array.isArray(k) ? k.forEach((x) => depo.delete(x)) : depo.delete(k)),
      deleteAll: async () => depo.clear(),
      setAlarm: async (t) => (alarm = t),
      getAlarm: async () => alarm || null,
      deleteAlarm: async () => (alarm = 0),
    },
  };
  const eslesme = [];
  const env = {
    ESLESTIRME: { idFromName: () => 1, get: () => ({ fetch: async (r) => (eslesme.push(await r.json()), new Response("ok")) }) },
    ACCOUNTS: { idFromName: () => 1, get: () => ({ fetch: async () => Response.json({}) }) },
  };
  const room = new Room(state, env);
  await sleep(10);
  room.code = "TEST";
  room.acik = true;
  const a = sok({ id: 1, name: "Ali", cell: 0, host: true, tekrar: "x" });
  const b = sok({ id: 2, name: "Bea", cell: 1, host: false, tekrar: "y" });
  room.bots = [{ id: 3, name: "Bot", cell: 2, look: {} }];
  room.g = { phase: "bitti", players: [1, 2, 3], speed: 1, score: { 1: 3, 2: 1, 3: 0 }, hits: {}, names: { 1: "Ali", 2: "Bea", 3: "Bot" }, winner: 1, log: [], games: ["c4"], gi: 0 };
  await room.macBitti(room.g, null);
  bak("birim: maç bitince ikisi de maç sonu ekranında (ms)", room.players().filter((p) => p.ms).length === 2);
  bak("birim: maç sonu süresi alarmı kurulu", alarm === room.msBitis && room.msBitis > Date.now() + 25000);
  bak("birim: bitti mesajında dönüş süresi", a.giden.some((m) => m.t === "bitti" && m.donus === 30));
  // Bea TEKRAR OYNA
  await room.webSocketMessage(b, JSON.stringify({ t: "tekrar" }));
  bak("birim: oda lobiye döndü (oyun silindi, başlamadı)", room.g === null && depo.get("started") === false);
  bak("birim: Hızlı Oyun botları bıraktı (yeniden eşleştirme)", room.bots.length === 0);
  bak("birim: eşleştiriciye yeniden açık bildirildi", eslesme.some((e) => e.kod === "TEST" && e.started === false && e.n === 2));
  bak("birim: başlama zamanı maç sonu süresinden sonra", room.lobbyAt >= room.msBitis + 2000 || room.msBitis === 0);
  bak("birim: Bea lobide, Ali hâlâ maç sonunda", !b.info.ms && a.info.ms && b.giden.some((m) => m.t === "lobi" && m.code === "TEST"));
  bak("birim: alarm maç sonu süresine kurulu", alarm === room.msBitis);
  // Hızlı Oyun süresi doldu: Ali lobiye alınır, botla 4'e tamamlanıp başlar
  a.giden.length = 0;
  room.msBitis = Date.now() - 1;
  await room.alarm();
  bak("birim: süre dolunca Ali de lobiye alındı", !a.info.ms && a.giden.some((m) => m.t === "lobi"));
  // (hazır sistemi: HAZIR demeyenler OTO_HAZIR sonra kendiliğinden hazır sayılır, geri sayım ondan sonra işler)
  room.lobbyAt = Date.now() - 1;
  await room.alarm();
  bak("birim: HAZIR demeyen varken Hızlı Oyun başlamadı", !room.g);
  a.info.hazirSon = b.info.hazirSon = Date.now() - 1;
  await room.alarm();
  room.lobbyAt = Date.now() - 1;
  await room.alarm();
  bak("birim: Hızlı Oyun süresi dolunca botla dolup başladı", room.g && room.players().length === 4 && a.giden.some((m) => m.t === "basladi"));
  bak("birim: yeni maçta eski hazır/ms bayrağı yok", room.players().every((p) => !p.ms));
}

// ---------------------------------------------------------------- uçtan uca (yerel sunucu)
async function maciBekle(ws, ms = 90000) {
  return await ws.wait("bitti", ms);
}

async function uctanUca() {
  try {
    const r = await fetch(URL0.replace("ws://", "http://") + "/");
    if (!r.ok) throw 0;
  } catch {
    console.log("  (yerel sunucu 8794 kapalı: uçtan uca kısım atlandı)");
    return;
  }
  const ta = tok();
  const tb = tok();
  const ha = await hesap(ta, "A");
  const hb = await hesap(tb, "B");
  const e0a = await ekonomi(ha);
  const e0b = await ekonomi(hb);
  const mac0a = (e0a && e0a.istatistik && e0a.istatistik.mac) || 0;
  const mac0b = (e0b && e0b.istatistik && e0b.istatistik.mac) || 0;
  const code = kod();
  const A = await oda(code, "Ayse", ta, true);
  const B = await oda(code, "Burak", tb, false);
  bak("A kurucu, B katıldı", A.hos.host && !B.hos.host && !B.hos.started);
  for (let i = 0; i < 2; i++) {
    const p = A.wait((d) => d.t === "oyuncular" && d.players.filter((x) => x.bot).length === i + 1);
    A.send({ t: "bot_ekle" });
    await p;
  }
  B.send({ t: "hazir", on: true });
  await A.wait((d) => d.t === "oyuncular" && d.players.some((x) => x.id === B.hos.id && x.r));

  // ---- 1. maç
  let pa = maciBekle(A);
  let pb = maciBekle(B);
  A.send({ t: "basla", oyunlar: ["ortalama"], hiz: 0.05 });
  bak("1. maç başladı", !!(await B.wait("basladi")));
  const [b1a, b1b] = await Promise.all([pa, pb]);
  bak("1. maç bitti (iki istemciye de)", !!b1a && !!b1b);
  bak("bitti mesajında lobiye dönüş süresi", b1a && b1a.donus >= 20, JSON.stringify(b1a && b1a.donus));
  const l1 = A.msgs.filter((d) => d.t === "oyuncular").pop();
  bak("maç sonunda ikisi de 'maç sonu ekranında'", l1 && l1.players.filter((p) => p.ms).length === 2, JSON.stringify(l1 && l1.players));
  await sleep(1500);
  bak("1. maç ödülü A'ya bir kez", ha.say("mac_odul") === 1, String(ha.say("mac_odul")));
  bak("1. maç ödülü B'ye bir kez", hb.say("mac_odul") === 1, String(hb.say("mac_odul")));

  // ---- B TEKRAR OYNA: lobiye döner; A hâlâ maç sonunda
  let p = B.wait("lobi");
  let pA = A.wait((d) => d.t === "oyuncular" && d.players.some((x) => x.id === B.hos.id && !x.ms));
  B.send({ t: "tekrar" });
  const lb = await p;
  bak("B lobiye döndü (aynı kod, aynı hücre)", lb && lb.code === code && lb.cell === B.hos.cell && lb.id === B.hos.id, JSON.stringify(lb));
  const la = await pA;
  bak("A, B'yi lobide görür; kendisi maç sonunda", la && benim(A, la.players).ms === true && !benim(B, la.players).ms);
  bak("botlar korundu (2)", la && la.players.filter((x) => x.bot).length === 2);
  bak("hazır bayrakları temizlendi", la && la.players.filter((x) => !x.bot).every((x) => !x.r));
  // maç sonundaki varken başlatılamaz
  p = A.wait((d) => d.t === "bilgi");
  A.send({ t: "basla", oyunlar: ["ortalama"], hiz: 0.05 });
  const bil = await p;
  bak("maç sonu ekranında kalan varken BAŞLAT olmaz", bil && /maç sonu/.test(bil.m), JSON.stringify(bil));
  // A da döner
  p = A.wait("lobi");
  A.send({ t: "tekrar" });
  const la2 = await p;
  bak("A lobiye döndü, hâlâ kurucu", la2 && la2.host === true && la2.code === code);
  bak("lobide kimse maç sonunda değil", la2 && la2.players.every((x) => !x.ms));

  // ---- 2. maç (Tekrar Oyna sonrası hazırlar sıfırlandı: B yeniden HAZIR der)
  B.send({ t: "hazir", on: true });
  await A.wait((d) => d.t === "oyuncular" && d.players.some((x) => x.id === B.hos.id && x.r));
  pa = maciBekle(A);
  pb = maciBekle(B);
  p = B.wait("basladi");
  A.send({ t: "basla", oyunlar: ["ortalama"], hiz: 0.05 });
  bak("2. maç aynı odada başladı", !!(await p));
  const st = await B.wait("oyun", 8000);
  bak("2. maç yeni oyun durumu (tur 1, 4 oyuncu)", st && st.round === 1 && st.players.length === 4, JSON.stringify(st && { r: st.round, p: st.players }));
  const [b2a, b2b] = await Promise.all([pa, pb]);
  bak("2. maç bitti", !!b2a && !!b2b);
  await sleep(1500);
  bak("ödül her maçta bir kez: A 2", ha.say("mac_odul") === 2, String(ha.say("mac_odul")));
  bak("ödül her maçta bir kez: B 2", hb.say("mac_odul") === 2, String(hb.say("mac_odul")));
  const e2a = await ekonomi(ha);
  const e2b = await ekonomi(hb);
  bak("hesapta maç sayısı +2 (A)", e2a && e2a.istatistik.mac === mac0a + 2, JSON.stringify(e2a && e2a.istatistik.mac));
  bak("hesapta maç sayısı +2 (B)", e2b && e2b.istatistik.mac === mac0b + 2);

  // ---- kurucu A maç sonunda odadan çıkar: sahiplik B'ye, B lobide kalır
  p = B.wait((d) => d.t === "bilgi" && d.cikti === A.hos.id);
  pA = B.wait((d) => d.t === "oyuncular" && benim(B, d.players).host === true && !d.players.some((x) => x.id === A.hos.id));
  A.send({ t: "cik" });
  A.close();
  bak("B, A'nın çıktığını görür", !!(await p));
  bak("sahiplik B'ye geçti", !!(await pA));
  p = B.wait("lobi");
  B.send({ t: "tekrar" });
  const lb3 = await p;
  bak("B lobide, kurucu, botlar duruyor", lb3 && lb3.host === true && lb3.players.length === 3 && lb3.players.filter((x) => x.bot).length === 2, JSON.stringify(lb3 && lb3.players));
  p = B.wait("basladi");
  B.send({ t: "basla", oyunlar: ["c4"], hiz: 0.05 });
  bak("yeni kurucu B maçı başlatabilir", !!(await p));
  B.send({ t: "cik" });
  B.close();

  // ---- süre dolunca otomatik lobiye dönüş + maç bitmiş odaya yeni gelen
  const code2 = kod();
  const C = await oda(code2, "Cem", tok(), true);
  const pc = C.wait((d) => d.t === "oyuncular" && d.players.some((x) => x.bot));
  C.send({ t: "bot_ekle" });
  await pc;
  const pbit = maciBekle(C);
  C.send({ t: "basla", oyunlar: ["ortalama"], hiz: 0.05 });
  const b3 = await pbit;
  bak("tek kişi + bot maçı bitti", !!b3);
  const t0 = Date.now();
  const D = await oda(code2, "Deniz", tok(), false);
  bak("maç bitmiş odaya yeni gelen lobiye düşer (izleyici değil)", D.hos && D.hos.started === false, JSON.stringify(D.hos && D.hos.started));
  bak("yeni gelen, C'yi maç sonunda görür", benim(C, D.hos.players).ms === true);
  const otomatik = await C.wait("lobi", 26000);
  const gecen = (Date.now() - t0) / 1000;
  bak("süre dolunca C kendiliğinden lobiye döndü", !!otomatik, "");
  bak("dönüş süresi bitti mesajındaki kadar", b3 && gecen <= b3.donus + 2, gecen.toFixed(1) + " sn");
  bak("otomatik dönüşte kurucu ve bot aynı", otomatik && otomatik.host === true && otomatik.players.length === 3);
  C.send({ t: "cik" });
  D.send({ t: "cik" });
  C.close();
  D.close();
  ha.send({ t: "hesap_sil" });
  hb.send({ t: "hesap_sil" });
  await sleep(400);
  ha.close();
  hb.close();
}

console.log("— birim (Hızlı Oyun) —");
await birim();
console.log("— uçtan uca (8794) —");
await uctanUca();
console.log(`\n${ok} geçti, ${hata} hatalı`);
process.exit(hata ? 1 : 0);
