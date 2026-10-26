// Alarm bekçisi ve sunucu sağlamlığı birim testi (sahte Durable Object; sunucu gerekmez):  cd server && node test/bekci_test.mjs
// - alarm üst üste hata verirse: önce yeniden dener, 3. hatada mini oyunu atlar, sürerse 6. hatada maçı bitirir
// - boş alarm sonucu (onWake null) alarm zincirini koparmaz
// - erken uyanış sonuç ekranını kısaltmaz
// - oda boşalınca depo silinir
// - bozuk konum / görünüş / kapı mesajları süzülür, spam sınırı ve bağlantı kesme
// - Kısa Devre'de ayrılanın şeması başka tahtaya geçer; ödül: aynı hesap bir kez, oyun sayısıyla orantılı
globalThis.WebSocketRequestResponsePair = class {
  constructor(a, b) {
    this.a = a;
    this.b = b;
  }
};
globalThis.WebSocketPair = class {
  constructor() {
    this[0] = {};
    this[1] = {};
  }
};
const { Room } = await import("../src/index.js");
const devre = await import("../src/modes/devre.js");
const E = await import("../src/ekonomi.js");

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

function kur() {
  const depo = new Map();
  let alarm = null;
  const soketler = [];
  const sok = (info) => {
    const s = {
      info, giden: [], kapandi: 0,
      serializeAttachment(x) { this.info = x; },
      deserializeAttachment() { return this.info; },
      send(m) { if (typeof m === "string") this.giden.push(JSON.parse(m)); },
      close(c) { this.kapandi = c || 1000; },
    };
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
      setAlarm: async (t) => {
        if (!Number.isFinite(t)) throw new Error("alarm sayı değil");
        alarm = t;
      },
      getAlarm: async () => alarm,
      deleteAlarm: async () => (alarm = null),
    },
  };
  const env = {
    ESLESTIRME: { idFromName: () => 1, get: () => ({ fetch: async () => new Response("ok") }) },
    ACCOUNTS: { idFromName: () => 1, get: () => ({ fetch: async (r) => (env.mac.push(await r.text()), Response.json({})) }) },
    mac: [],
  };
  const room = new Room(state, env);
  return { room, depo, sok, soketler, env, alarm: () => alarm, setAlarmVal: (v) => (alarm = v) };
}
const sessiz = console.log;
const sus = () => (console.log = () => {});
const ac = () => (console.log = sessiz);

// ---- 1) bekçi: bozuk mini oyun önce atlanır ----
{
  const t = kur();
  await new Promise((r) => setTimeout(r, 5));
  const a = t.sok({ id: 1, name: "A", cell: 0, host: true, tekrar: "a" });
  t.sok({ id: 2, name: "B", cell: 1, tekrar: "b" });
  t.room.code = "TEST";
  // ortalama "yaz1" aşamasında oyun durumu bozuk (g.m yok): sıradaki aşamaya geçerken hata verir
  t.room.g = { games: ["ortalama", "c4"], gi: 0, round: 1, rounds: 2, task: "ortalama", phase: "yaz1", speed: 1, players: [1, 2], names: { 1: "A", 2: "B" }, cells: {}, score: { 1: 0, 2: 0 }, hits: {}, secret: {}, m: null, log: [], ends: Date.now() - 10 };
  // (hata aşamanın yarısında olabilir: her denemede süre dolmuş sayılır)
  sus();
  t.room.g.ends = Date.now() - 10;
  await t.room.alarm();
  t.room.g.ends = Date.now() - 10;
  await t.room.alarm();
  ac();
  bak("1-2. hata: yeniden denenir, alarm kurulu", t.alarm() !== null && t.room.g.phase !== "sonuc" && t.depo.get("alarmHata") === 2, t.room.g.phase + " " + t.depo.get("alarmHata"));
  sus();
  t.room.g.ends = Date.now() - 10;
  await t.room.alarm();
  ac();
  bak("3. hata: mini oyun atlandı (sonuç ekranı)", t.room.g.phase === "sonuc", t.room.g.phase);
  bak("kalanlar 'sıradaki oyun' ekranını aldı", a.giden.some((m) => m.t === "oyun" && m.phase === "sonuc" && m.sonraki === "C4"));
  t.room.g.ends = Date.now() - 10;
  await t.room.alarm();
  bak("sonra maç sıradaki oyunla sürer (C4)", t.room.g.task === "c4" && t.room.g.phase === "anons", t.room.g.task + " " + t.room.g.phase);
  bak("hata sayacı sıfırlandı", !t.depo.get("alarmHata"));
}

// ---- 2) bekçi: düzelmezse maç bitirilir ----
{
  const t = kur();
  await new Promise((r) => setTimeout(r, 5));
  const a = t.sok({ id: 1, name: "A", cell: 0, host: true, tekrar: "a", hesap: "h1" });
  t.sok({ id: 2, name: "B", cell: 1, tekrar: "b", hesap: "h2" });
  t.room.code = "TEST";
  // sonuç ekranında sıradaki oyun bilinmeyen bir oyun: her alarmda hata
  t.room.g = { games: ["c4", "yok_boyle"], gi: 0, round: 1, rounds: 2, task: "c4", phase: "sonuc", speed: 1, players: [1, 2], names: { 1: "A", 2: "B" }, cells: {}, score: { 1: 3, 2: 1 }, hits: {}, secret: {}, m: { wake: 0 }, log: [{ task: "c4", title: "C4", d: { 1: 3, 2: 1 } }], ends: Date.now() - 10 };
  sus();
  for (let i = 0; i < 6; i++) await t.room.alarm();
  ac();
  bak("6. hatada maç bitirildi", t.room.g.phase === "bitti", t.room.g.phase);
  const b = a.giden.find((m) => m.t === "bitti");
  bak("herkes maç sonu tablosunu aldı (kazanan en yüksek puanlı)", b && b.winner === 1 && b.table.length === 2);
  bak("maç sonu süresi alarmı kurulu (oda lobiye dönecek)", t.alarm() !== null && t.room.msBitis > 0);
  bak("ödül bir kez bildirildi", t.env.mac.length === 1);
}

// ---- 3) onWake boş dönerse alarm zinciri kopmaz; erken uyanış sonuç ekranını kısaltmaz ----
{
  const t = kur();
  await new Promise((r) => setTimeout(r, 5));
  t.sok({ id: 1, name: "A", cell: 0, host: true, tekrar: "a" });
  t.sok({ id: 2, name: "B", cell: 1, tekrar: "b" });
  t.room.code = "TEST";
  // ruletin sırası oyunda olmayan birinde (onWake null döner)
  t.room.g = { games: ["rulet"], gi: 0, round: 1, rounds: 1, task: "rulet", phase: "oyun", speed: 1, players: [1, 2], names: { 1: "A", 2: "B" }, cells: {}, score: { 1: 0, 2: 0 }, hits: {}, secret: {}, log: [], ends: Date.now() + 100000, m: { alive: [1, 2], holder: 9, stage: 0, pts: {}, kills: {}, dead: [], ready: 0, wake: Date.now() - 10, last: null } };
  t.setAlarmVal(null);
  await t.room.alarm();
  bak("onWake boş: alarm yeniden kuruldu", t.alarm() !== null, String(t.alarm()));
  t.room.g.phase = "sonuc";
  t.room.g.ends = Date.now() + 8000;
  await t.room.alarm();
  bak("sonuç ekranında erken uyanış: sıradaki oyuna atlanmaz", t.room.g.phase === "sonuc" && t.alarm() >= t.room.g.ends - 5);
}

// ---- 4) mesaj süzgeci, spam sınırı, oda boşalınca temizlik ----
{
  const t = kur();
  await new Promise((r) => setTimeout(r, 5));
  const a = t.sok({ id: 1, name: "A", cell: 0, host: true, tekrar: "a" });
  const b = t.sok({ id: 2, name: "B", cell: 1, tekrar: "b" });
  t.room.code = "TEST";
  await t.room.webSocketMessage(a, JSON.stringify({ t: "konum", p: [1.23456, 2], y: 0.5, o: false, c: false, k: false, kotu: "<x>" }));
  const k = b.giden.find((m) => m.t === "konum");
  bak("konum süzüldü (yalnız bilinen alanlar, yuvarlanmış)", k && JSON.stringify(k) === JSON.stringify({ t: "konum", id: 1, p: [1.23, 2], y: 0.5, o: false }), JSON.stringify(k));
  const n0 = b.giden.length;
  await t.room.webSocketMessage(a, JSON.stringify({ t: "konum", p: "abc" }));
  await t.room.webSocketMessage(a, JSON.stringify({ t: "konum", p: [NaN, 1] }));
  await t.room.webSocketMessage(a, JSON.stringify({ t: "kapi", cell: "__proto__", open: true }));
  await t.room.webSocketMessage(a, JSON.stringify({ t: "emote", e: { a: 1 } }));
  await t.room.webSocketMessage(a, "x".repeat(5000));
  bak("bozuk konum/kapı/hareket ve dev mesaj kimseye gitmedi", b.giden.length === n0, JSON.stringify(b.giden.slice(n0)));
  await t.room.webSocketMessage(a, JSON.stringify({ t: "profil", ad: "‮Ali\u0000", g: { govde: "kadin", sac: { x: 1 }, ten: 2, uzun: "y".repeat(100) } }));
  const pl = b.giden.filter((m) => m.t === "oyuncular").pop();
  const pa = pl && pl.players.find((p) => p.id === 1);
  bak("profil: ad ve görünüş temizlendi", pa && pa.name === "Ali" && pa.g.govde === "kadin" && pa.g.sac === undefined && pa.g.uzun.length === 32, JSON.stringify(pa));
  const n1 = b.giden.length;
  await t.room.webSocketMessage(a, JSON.stringify({ t: "profil", ad: "Ali", g: { govde: "kadin", ten: 2, uzun: "y".repeat(100) } }));
  bak("değişmeyen profil listeyi yeniden yollatmaz", b.giden.length === n1);
  // spam: 30 birikmiş + saniyede 15 konum; 600 konum peş peşe -> çoğu atılır, 400 atılınca bağlantı kesilir
  sus();
  for (let i = 0; i < 600; i++) await t.room.webSocketMessage(a, JSON.stringify({ t: "konum", p: [1, i % 10], y: 0, o: false }));
  ac();
  const gecen = b.giden.filter((m) => m.t === "konum").length - 1;
  bak("spam: konum yağmurunun çoğu atıldı", gecen <= 40, String(gecen));
  bak("spam: bağlantı kesildi ve uyarı gitti", a.kapandi === 4008 && a.giden.some((m) => m.t === "hata" && /Çok hızlı/.test(m.m)));
  // ses: dev parça atılır
  const ses0 = b.giden.length;
  t.room.started = false;
  const sesWs = t.sok({ id: 3, name: "C", cell: 2, tekrar: "c" });
  const binler = [];
  b.send = function (m) {
    if (typeof m === "string") this.giden.push(JSON.parse(m));
    else binler.push(m.length);
  };
  await t.room.webSocketMessage(sesWs, new Uint8Array(100000).buffer);
  await t.room.webSocketMessage(sesWs, new Uint8Array(640).buffer);
  bak("ses: dev parça atıldı, normal parça iletildi", binler.length === 1 && binler[0] === 641, JSON.stringify(binler));
  // oda boşalır
  for (const w of [...t.soketler]) await t.room.leave(w);
  bak("oda boşalınca depo ve alarm silindi", t.depo.size === 0 && t.alarm() === null, [...t.depo.keys()].join(","));
}

// ---- 5) Kısa Devre: ayrılanın şeması zincirde başka tahtaya geçer ----
{
  const g = { players: [1, 2, 3], names: { 1: "A", 2: "B", 3: "C" }, secret: {}, score: { 1: 0, 2: 0, 3: 0 }, hits: {}, phase: "calisma" };
  devre.start(g);
  const ayrilan = 2;
  const T = g.m.boardOf[ayrilan];
  const H = g.m.holder[ayrilan];
  g.players = g.players.filter((x) => x !== ayrilan);
  devre.leave(g, ayrilan);
  bak("ayrılanın kutusu sayılmaz", !g.m.boxes[ayrilan] && devre.counts(g).toplam === 2);
  bak("T'nin şeması artık H'nin tahtasında", g.m.holder[T] === H && g.m.boardOf[H] === T && g.secret[H].yardim === T && g.gizliYenile.includes(H), JSON.stringify({ T, H, holder: g.m.holder }));
  bak("kimse kendi şemasını görmüyor", Object.entries(g.m.boardOf).every(([h, t]) => Number(h) !== t));
}

// ---- 6) ödül: oyun sayısıyla orantılı ----
{
  const tam = E.matchReward({ sira: 1, oyuncu_sayisi: 4, puan: 5, oyun_sayisi: 6 });
  const bir = E.matchReward({ sira: 1, oyuncu_sayisi: 4, puan: 5, oyun_sayisi: 1 });
  bak("6 oyunlu maç tam ödül, tek oyunluk 1/3", bir.gems === Math.round(tam.gems / 3) && tam.gems === 40, JSON.stringify({ tam, bir }));
}

console.log(`\nbekçi testi: ${ok} geçti, ${hata} hatalı`);
process.exit(hata ? 1 : 0);
