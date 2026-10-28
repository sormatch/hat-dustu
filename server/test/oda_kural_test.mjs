// Oda kuralları birim testi (sahte Durable Object; sunucu gerekmez):  cd server && node test/oda_kural_test.mjs
// - maç sürerken gelen yeni oyuncu ayrılanın numarasını / hücresini almaz; askıya alınan oyuncu geri dönemez
// - paralı görünüş yalnız sahibine (sahip listesi Accounts /ic/sahip; ulaşılamazsa görünüş olduğu gibi)
// - Kim Kim?: zil yalnız aranana, konumdaki telefon bayrağı (c) gönderilmez
// - C4: konumu bilinmeyen bomba veremez / konumu bilinmeyen insana verilemez (bota verilir); patlayan çıkarsa -2 kalır
// - ödül: 2'den az insanla maç ödül vermez; Hızlı Oyun odasında elle bot / başlatma yok; canlıda aynı oyun bir kez
// - hesap sunucusu: yeni anahtarla /hesap bağlantısına IP başına kova
globalThis.WebSocketRequestResponsePair = class {
  constructor(a, b) {
    this.a = a;
    this.b = b;
  }
};
class SahteWS {
  constructor(info = null) {
    this.info = info;
    this.giden = [];
  }
  serializeAttachment(x) {
    this.info = x;
  }
  deserializeAttachment() {
    return this.info;
  }
  send(m) {
    if (typeof m === "string") this.giden.push(JSON.parse(m));
  }
  close(c) {
    this.kapandi = c || 1000;
  }
}
globalThis.WebSocketPair = class {
  constructor() {
    this[0] = new SahteWS();
    this[1] = new SahteWS();
  }
};
// Node'un Response'u 101 durumunu kabul etmez: WebSocket cevabı için küçük sarmalayıcı
const GercekResponse = Response;
globalThis.Response = class extends GercekResponse {
  constructor(b, o = {}) {
    super(b, o.status === 101 ? {} : o);
    if (o.status === 101) {
      Object.defineProperty(this, "status", { value: 101 });
      this.webSocket = o.webSocket;
    }
  }
};
const { Room } = await import("../src/index.js");
const G = await import("../src/game.js");

let ok = 0;
let hata = 0;
function bak(ad, kosul, ek = "") {
  if (kosul) ok++;
  else {
    hata++;
    console.log("  HATA " + ad + (ek ? "  -> " + ek : ""));
  }
}
const uyu = (ms) => new Promise((r) => setTimeout(r, ms));
const sessiz = console.log;

function kur() {
  const depo = new Map();
  let alarm = null;
  const soketler = [];
  const hesaplar = {}; // anahtar -> { ad, yasak, sahip, ulasilamaz }
  const mac = [];
  const state = {
    setWebSocketAutoResponse() {},
    blockConcurrencyWhile: async (f) => f(),
    acceptWebSocket: (s) => soketler.push(s),
    getWebSockets: () => soketler.filter((s) => !s.kapandi),
    storage: {
      get: async (k) => depo.get(k),
      put: async (k, v) => (typeof k === "object" ? Object.entries(k).forEach(([a, b]) => depo.set(a, b)) : depo.set(k, v)),
      delete: async (k) => (Array.isArray(k) ? k.forEach((x) => depo.delete(x)) : depo.delete(k)),
      deleteAll: async () => depo.clear(),
      setAlarm: async (t) => (alarm = t),
      getAlarm: async () => alarm,
      deleteAlarm: async () => (alarm = null),
    },
  };
  const env = {
    ACCOUNTS: {
      idFromName: () => 1,
      get: () => ({
        fetch: async (req) => {
          const u = new URL(req.url);
          let b = {};
          try {
            b = await req.json();
          } catch {}
          const h = hesaplar[b.token];
          if (u.pathname === "/ic/oda-giris") return Response.json({ hesap: !!h, ad: (h && h.ad) || "", yasak: (h && h.yasak) || null, engel: [] });
          if (u.pathname === "/ic/sahip") {
            if (h && h.ulasilamaz) throw new Error("ulaşılamadı");
            return Response.json({ sahip: (h && h.sahip) || [] });
          }
          if (u.pathname === "/mac") mac.push(b);
          return Response.json({});
        },
      }),
    },
  };
  const room = new Room(state, env);
  room.code = "TEST";
  const t = { room, soketler, hesaplar, mac, depo };
  // fetch ile giriş (telefon gibi); dönen: yeni bağlantı
  t.gir = async (ad, ek = "", kur = false) => {
    const tok = "anahtar_" + ad + "_0000000000";
    hesaplar[tok] ||= { ad: ad.toLowerCase() };
    await room.fetch(new Request(`https://127.0.0.1/oda/TEST?ad=${ad}&hesap=${tok}&sv=3${kur ? "&kur=1" : "&davet=1"}${ek}`));
    const s = soketler[soketler.length - 1];
    s.tok = tok;
    return s;
  };
  // doğrudan bağlı oyuncu
  t.sok = (info) => {
    const s = new SahteWS(info);
    soketler.push(s);
    return s;
  };
  t.msg = (s, d) => room.webSocketMessage(s, JSON.stringify(d));
  return t;
}
const son = (s, f) => [...s.giden].reverse().find(f);

// ---- 1) maç sürerken gelen yeni oyuncu; askıya alınan oyuncu geri dönemez ----
{
  const t = kur();
  await uyu(5); // (oda kurucusu depoyu yükleyip bitirsin)
  const A = await t.gir("Ali", "", true);
  const B = await t.gir("Bea");
  const C = await t.gir("Cem");
  bak("üç oyuncu girdi", [A, B, C].every((s) => s.info && s.info.id), JSON.stringify([A, B, C].map((s) => s.info)));
  await t.msg(B, { t: "hazir", on: true });
  await t.msg(C, { t: "hazir", on: true });
  await t.msg(A, { t: "basla", oyunlar: ["ortalama", "c4"], hiz: 0.05 });
  bak("maç başladı", !!t.room.g && t.room.g.games.length === 2, JSON.stringify(t.room.g && t.room.g.games));
  t.room.g.ends = Date.now() - 10;
  await t.room.alarm();
  bak("ilk oyun ortalama", t.room.g.task === "ortalama", t.room.g.task);
  const bId = B.info.id;
  const bCell = B.info.cell;
  await t.msg(B, { t: "cik" });
  const D = await t.gir("Dua");
  bak("yeni gelen ayrılanın numarasını almadı", D.info.id && D.info.id !== bId && !Object.keys(t.room.g.score).map(Number).includes(D.info.id), JSON.stringify(D.info));
  bak("yeni gelen ayrılanın hücresini almadı", D.info.cell !== bCell && !Object.values(t.room.g.cells).includes(D.info.cell), String(D.info.cell));
  // C'nin bağlantısı koptu (geri dönebilir), sonra hesabı askıya alındı
  const cTekrar = C.info.tekrar;
  await t.room.webSocketClose(C);
  bak("C kopuk sayıldı", Object.keys(t.room.kopuk).includes(cTekrar));
  t.hesaplar[C.tok].yasak = { m: "Hesabın askıya alındı.", m_k: [["Hesabın askıya alındı.", []]] };
  console.log = () => {};
  const C2 = await t.room.fetch(new Request(`https://127.0.0.1/oda/TEST?ad=Cem&hesap=${C.tok}&sv=3&tekrar=${cTekrar}`)).then(() => t.soketler[t.soketler.length - 1]);
  console.log = sessiz;
  bak("askıdaki oyuncu geri dönme anahtarıyla maça dönemedi", !C2.info || !C2.info.id, JSON.stringify(C2.info));
  bak("askıdaki oyuncuya yasak mesajı gitti", C2.giden.some((m) => m.t === "hata" && /askıya/.test(m.m)), JSON.stringify(C2.giden));
}

// ---- 2) paralı görünüş yalnız sahibine ----
{
  const t = kur();
  await uyu(5); // (oda kurucusu depoyu yükleyip bitirsin)
  const A = await t.gir("Ali", "", true);
  const B = await t.gir("Bea");
  t.hesaplar[A.tok].sahip = ["sac:topuz"];
  await t.msg(A, { t: "profil", g: { govde: "kadin", sac: "topuz", kiyafet: "altin", sapka: "yok", ten: 2 } });
  let g = A.info.look;
  bak("sahip olunan paralı saç kaldı", g.sac === "topuz", JSON.stringify(g));
  bak("sahip olunmayan paralı kıyafet varsayılana döndü", g.kiyafet === "turuncu", JSON.stringify(g));
  bak("bedava parçalar olduğu gibi", g.govde === "kadin" && g.ten === 2 && g.sapka === "yok");
  const lb = son(B, (m) => m.t === "oyuncular");
  bak("diğerleri varsayılanı görür", lb && lb.players.find((p) => p.id === A.info.id).g.kiyafet === "turuncu");
  // A az önce kıyafeti satın aldı: önbellekte yok -> liste yeniden çekilir
  t.hesaplar[A.tok].sahip = ["sac:topuz", "kiyafet:altin"];
  await uyu(1100);
  await t.msg(A, { t: "profil", g: { govde: "kadin", sac: "topuz", kiyafet: "altin", ten: 2 } });
  bak("yeni alınan eşya yeniden çekilen listeyle giyildi", A.info.look.kiyafet === "altin", JSON.stringify(A.info.look));
  // hesap sunucusuna ulaşılamıyor: görünüş olduğu gibi (oyun bozulmaz)
  t.hesaplar[B.tok].ulasilamaz = true;
  console.log = () => {};
  await t.msg(B, { t: "profil", g: { govde: "erkek", kiyafet: "kamuflaj", sapka: "tac" } });
  console.log = sessiz;
  bak("hesap sunucusu yoksa görünüş olduğu gibi", B.info.look.kiyafet === "kamuflaj" && B.info.look.sapka === "tac", JSON.stringify(B.info.look));
}

// ---- 3) Kim Kim?: zil yalnız aranana, telefon bayrağı gönderilmez ----
{
  const t = kur();
  await uyu(5); // (oda kurucusu depoyu yükleyip bitirsin)
  const s = [1, 2, 3].map((i) => t.sok({ id: i, name: "O" + i, cell: i - 1, host: i === 1, tekrar: "t" + i, call: 0, calling: 0, ringFrom: 0 }));
  t.room.g = G.newGame(s.map((x) => x.info), 1, ["kimkim"]);
  G.startNext(t.room.g);
  t.room.g.phase = "telefon";
  const hat2 = G.MODES.kimkim.alias(t.room.g, 2);
  await t.msg(s[0], { t: "ara", to: hat2 });
  bak("aranana zil gitti", s[1].giden.some((m) => m.t === "zil" && m.on === true && m.cell === 1));
  bak("üçüncü kişiye zil gitmedi (aranan hat belli olmasın)", !s[2].giden.some((m) => m.t === "zil"), JSON.stringify(s[2].giden));
  await t.msg(s[1], { t: "cevap" });
  bak("cevapta zil kapanışı da yalnız arananın", !s[2].giden.some((m) => m.t === "zil") && s[1].giden.some((m) => m.t === "zil" && m.on === false));
  await t.msg(s[0], { t: "konum", p: [1, 2], y: 0, o: false, c: true });
  const k = son(s[2], (m) => m.t === "konum");
  bak("Kim Kim?'de konumda telefon bayrağı yok", k && k.c === undefined, JSON.stringify(k));
  // oyun dışı: zil herkese, bayrak var
  t.room.g.phase = "sonuc";
  await t.msg(s[0], { t: "kapat" });
  await t.msg(s[0], { t: "konum", p: [1, 3], y: 0, o: false, c: true });
  bak("Kim Kim? dışında telefon bayrağı gider", son(s[2], (m) => m.t === "konum").c === true);
}

// ---- 4) C4: konum şartı, bota verme, patlayanın cezası ----
{
  const t = kur();
  await uyu(5); // (oda kurucusu depoyu yükleyip bitirsin)
  const s = [1, 2].map((i) => t.sok({ id: i, name: "O" + i, cell: i - 1, host: i === 1, tekrar: "t" + i }));
  t.room.bots = [{ id: 3, name: "Bot", cell: 2, look: {} }];
  t.room.g = G.newGame([...s.map((x) => x.info), { id: 3, name: "Bot", cell: 2 }], 1, ["c4"]);
  t.room.g.bots = [3];
  G.startNext(t.room.g);
  t.room.g.phase = "bomba";
  t.room.g.m.holder = 1;
  await t.msg(s[0], { t: "karar", v: { ver: 2 } });
  bak("konumu bilinmeyen bombayı veremez", t.room.g.m.holder === 1 && /Yanına git/.test((son(s[0], (m) => m.t === "bilgi") || {}).m || ""));
  await t.msg(s[0], { t: "konum", p: [0, 0], y: 0, o: false });
  await t.msg(s[0], { t: "karar", v: { ver: 2 } });
  bak("konumu bilinmeyen insana verilemez", t.room.g.m.holder === 1);
  await t.msg(s[1], { t: "konum", p: [5, 0], y: 0, o: false });
  await t.msg(s[0], { t: "karar", v: { ver: 2 } });
  bak("uzaktaki insana verilemez", t.room.g.m.holder === 1);
  await t.msg(s[1], { t: "konum", p: [1.5, 0], y: 0, o: false });
  await t.msg(s[0], { t: "karar", v: { ver: 2 } });
  bak("yanındaki insana verildi", t.room.g.m.holder === 2);
  await t.msg(s[1], { t: "karar", v: { ver: 3 } });
  bak("bota (konumu yok) verildi", t.room.g.m.holder === 3);
  // bomba 2'nin elinde patladı, 2 sonuçtan önce çıktı: -2 puanında kalır
  t.room.g.m.holder = 2;
  G.onWake(t.room.g);
  bak("patladı", t.room.g.m.boom === 2);
  await t.room.leave(s[1]);
  bak("patlayan çıkınca -2 puanına yazıldı", t.room.g.score[2] === -2, JSON.stringify(t.room.g.score));
  const res = G.resolve(t.room.g);
  bak("oyunun puan değişiminde de -2", t.room.g.log[0].d[2] === -2 && res, JSON.stringify(t.room.g.log));
}

// ---- 5) ödül, Hızlı Oyun kısıtları, aynı oyun bir kez ----
{
  const t = kur();
  await uyu(5); // (oda kurucusu depoyu yükleyip bitirsin)
  const s = [1, 2].map((i) => t.sok({ id: i, name: "O" + i, cell: i - 1, host: i === 1, tekrar: "t" + i, hesap: "hesap_" + i }));
  const g1 = G.newGame([s[0].info, { id: 3, name: "Bot", cell: 2 }], 1, ["c4"]);
  g1.bots = [3];
  g1.log = [{ task: "c4", title: "C4", d: { 1: 1, 3: -2 } }];
  t.soketler.splice(1, 1); // yalnız 1 insan bağlı
  await t.room.reportMatch(g1);
  bak("1 insan + bot: maç ödülü yok", t.mac.length === 0, JSON.stringify(t.mac));
  t.soketler.push(s[1]);
  const g2 = G.newGame([s[0].info, s[1].info, { id: 3, name: "Bot", cell: 2 }], 1, ["c4"]);
  g2.bots = [3];
  g2.log = [{ task: "c4", title: "C4", d: { 1: 1, 2: 1, 3: -2 } }];
  await t.room.reportMatch(g2);
  bak("2 insan: maç ödülü bildirildi", t.mac.length === 1 && t.mac[0].oyuncular.length === 2, JSON.stringify(t.mac));
  // Hızlı Oyun odası: elle bot ekleme ve başlatma yok
  t.room.acik = true;
  s[1].info.ready = true;
  await t.msg(s[0], { t: "bot_ekle" });
  bak("Hızlı Oyun: elle bot eklenmez", t.room.bots.length === 0);
  await t.msg(s[0], { t: "basla", oyunlar: ["ortalama"] });
  bak("Hızlı Oyun: elle başlatılmaz", !t.room.g);
  // özel oda, canlı (yerel değil): aynı oyun listede bir kez
  t.room.acik = false;
  await t.msg(s[0], { t: "basla", oyunlar: ["ortalama", "ortalama", "c4", "ortalama"] });
  bak("canlıda aynı oyun bir kez", t.room.g && JSON.stringify(t.room.g.games) === '["ortalama","c4"]', JSON.stringify(t.room.g && t.room.g.games));
  // yerel test sunucusunda tekrar serbest
  const t2 = kur();
  await uyu(5);
  const y = [1, 2].map((i) => t2.sok({ id: i, name: "O" + i, cell: i - 1, host: i === 1, tekrar: "t" + i, yerel: true, ready: i === 2 }));
  await t2.msg(y[0], { t: "basla", oyunlar: ["ortalama", "ortalama"], hiz: 0.05 });
  bak("yerelde aynı oyun iki kez olabilir", t2.room.g && t2.room.g.games.length === 2, JSON.stringify(t2.room.g && t2.room.g.games));
}

// ---- 6) hesap sunucusu: yeni anahtarla bağlantıya IP başına kova (hesap tablosu şişmesin) ----
{
  const { DatabaseSync } = await import("node:sqlite");
  const { Accounts } = await import("../src/accounts.js");
  const db = new DatabaseSync(":memory:");
  const sql = {
    exec(q, ...a) {
      const st = db.prepare(q);
      const rows = /^\s*(SELECT|WITH)/i.test(q) || /RETURNING/i.test(q) ? st.all(...a) : (st.run(...a), []);
      return { toArray: () => rows };
    },
  };
  const acs = [];
  const acc = new Accounts({ storage: { sql }, setWebSocketAutoResponse() {}, acceptWebSocket: (s) => acs.push(s), getWebSockets: () => acs.filter((s) => !s.kapandi) }, {});
  const baglan = async (tok, ip) => {
    await acc.fetch(new Request("https://hatdustu.app/hesap?token=" + tok, { headers: { "cf-connecting-ip": ip, upgrade: "websocket" } }));
    return acs[acs.length - 1];
  };
  const satir = () => acc.rows(`SELECT COUNT(*) AS n FROM users`)[0].n;
  const ilk = await baglan("eski_anahtar_000000000001", "9.9.9.9");
  bak("ilk bağlantı kabul", !ilk.giden.some((m) => m.t === "hata"));
  let red = 0;
  for (let i = 0; i < 100; i++) {
    const w = await baglan("rastgele_anahtar_" + String(i).padStart(8, "0"), "9.9.9.9");
    if (w.giden.some((m) => m.t === "hata" && /Çok fazla/.test(m.m))) red++;
  }
  bak("aynı IP'den 100 yeni anahtar: çoğu reddedildi, tablo şişmedi", red >= 30 && satir() <= 62, red + " red, " + satir() + " satır");
  const eski = await baglan("eski_anahtar_000000000001", "9.9.9.9");
  bak("var olan anahtar aynı IP'den yine bağlanır", !eski.giden.some((m) => m.t === "hata"));
  const baska = await baglan("baska_ip_anahtari_0000001", "8.8.4.4");
  bak("başka IP'den yeni anahtar bağlanır", !baska.giden.some((m) => m.t === "hata"));
}

console.log(`oda_kural_test: ${ok} doğru, ${hata} hata`);
process.exit(hata ? 1 : 0);
