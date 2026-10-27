// Hazır sistemi + mikrofon durumu testi:  cd server && node test/hazir_test.mjs   (uçtan uca kısım yerel sunucu 8794 açıkken koşar)
// Birim (sahte Durable Object): özel odada HAZIR olmayan varken BAŞLAT reddedilir ("Herkes hazır değil"), kurucunun
// BAŞLAT'ı kendi hazırı sayılır, herkes hazır olunca başlar; Hızlı Oyun'da geri sayım yalnız herkes hazırken işler,
// HAZIR demeyen OTO_HAZIR sonra kendiliğinden hazır sayılır, sonra botla dolup başlar; Tekrar Oyna sonrası hazırlar
// sıfırlanır; {t:"mik"} herkese gider ve oyuncu listesinde "mk" görünür.
// Uçtan uca: gerçek sunucuda aynı akış (özel oda + Hızlı Oyun salonu + mikrofon mesajı).
import crypto from "node:crypto";

import { hesapAc } from "./_hesap.mjs";
const URL0 = process.env.SRV || "ws://127.0.0.1:8794";

// misafir odaya giremez: her oyuncu adı için bir test hesabı açılır (aynı ad = aynı hesap; geri dönen oyuncu da)
const _hesaplar = {};
const hesabi = async (ad) => (_hesaplar[ad] ||= await hesapAc(URL0, "t" + ad));
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
const kod = () => {
  const c = "ABCDEFGHJKLMNPRSTUVYZ23456789";
  let s = "";
  for (let i = 0; i < 4; i++) s += c[Math.floor(Math.random() * c.length)];
  return s;
};

// ---------------------------------------------------------------- birim (sahte Durable Object)
async function yeniOda(acik) {
  globalThis.WebSocketRequestResponsePair ||= class {
    constructor(a, b) {
      this.a = a;
      this.b = b;
    }
  };
  const { Room } = await import("../src/index.js");
  const depo = new Map();
  const t = { alarm: 0, soketler: [] };
  const state = {
    setWebSocketAutoResponse() {},
    blockConcurrencyWhile: async (f) => f(),
    getWebSockets: () => t.soketler,
    storage: {
      get: async (k) => depo.get(k),
      put: async (k, v) => (typeof k === "object" ? Object.entries(k).forEach(([a, b]) => depo.set(a, b)) : depo.set(k, v)),
      delete: async (k) => (Array.isArray(k) ? k.forEach((x) => depo.delete(x)) : depo.delete(k)),
      deleteAll: async () => depo.clear(),
      setAlarm: async (x) => (t.alarm = x),
      getAlarm: async () => t.alarm || null,
      deleteAlarm: async () => (t.alarm = 0),
    },
  };
  const env = {
    ESLESTIRME: { idFromName: () => 1, get: () => ({ fetch: async () => new Response("ok") }) },
    ACCOUNTS: { idFromName: () => 1, get: () => ({ fetch: async () => Response.json({}) }) },
  };
  const room = new Room(state, env);
  await sleep(5);
  room.code = "HAZR";
  room.acik = acik;
  t.room = room;
  t.depo = depo;
  t.sok = (info) => {
    const s = { info, giden: [], serializeAttachment(x) { this.info = x; }, deserializeAttachment() { return this.info; }, send(m) { this.giden.push(JSON.parse(m)); }, close() {} };
    t.soketler.push(s);
    return s;
  };
  t.msg = (s, d) => room.webSocketMessage(s, JSON.stringify(d));
  return t;
}
const son = (s, f) => [...s.giden].reverse().find(f);
const liste = (s) => (son(s, (m) => m.t === "oyuncular") || {}).players || [];

async function birimOzel() {
  console.log("— birim: özel oda —");
  const t = await yeniOda(false);
  const a = t.sok({ id: 1, name: "Ali", cell: 0, host: true, tekrar: "a", yerel: true });
  const b = t.sok({ id: 2, name: "Bea", cell: 1, host: false, tekrar: "b", yerel: true });
  const c = t.sok({ id: 3, name: "Cem", cell: 2, host: false, tekrar: "c", yerel: true });
  t.room.bots = [{ id: 4, name: "Bot", cell: 3, look: {} }];
  bak("bot listede hep hazır", t.room.players().find((p) => p.bot).r === true);
  await t.msg(b, { t: "hazir", on: true });
  // C hazır değil: BAŞLAT reddedilir
  await t.msg(a, { t: "basla", oyunlar: ["ortalama"], hiz: 0.05 });
  const red = son(a, (m) => m.t === "bilgi");
  bak("hazır olmayan varken başlatma reddedildi", !t.room.g && !a.giden.some((m) => m.t === "basladi"));
  bak("'Herkes hazır değil' bilgisi döndü (ad ve numarayla)", red && /Herkes hazır değil/.test(red.m) && /Cem/.test(red.m) && JSON.stringify(red.hazir_degil) === "[3]", JSON.stringify(red));
  bak("bilgi iki dilde çevrilebilir (m_k şablonu)", red && Array.isArray(red.m_k) && red.m_k[0][0] === "Herkes hazır değil: {0}");
  bak("kurucunun BAŞLAT'ı kendi hazırı sayıldı", a.info.ready === true && liste(b).find((p) => p.id === 1).r === true);
  // C de hazır: başlar
  await t.msg(c, { t: "hazir", on: true });
  await t.msg(a, { t: "basla", oyunlar: ["ortalama"], hiz: 0.05 });
  bak("herkes hazır olunca başladı", !!t.room.g && c.giden.some((m) => m.t === "basladi"));
  // hazır olmayan kurucu (yalnız botlarla): BAŞLAT = hazır, başlar
  const t2 = await yeniOda(false);
  const h = t2.sok({ id: 1, name: "Tek", cell: 0, host: true, tekrar: "t", yerel: true });
  t2.room.bots = [{ id: 2, name: "Bot", cell: 1, look: {} }];
  await t2.msg(h, { t: "basla", oyunlar: ["ortalama"], hiz: 0.05 });
  bak("kurucu + botlar: HAZIR'a basmadan BAŞLAT çalışır", !!t2.room.g);
  // misafir başlatamaz
  const t3 = await yeniOda(false);
  t3.sok({ id: 1, name: "K", cell: 0, host: true, tekrar: "k", yerel: true, ready: true });
  const m3 = t3.sok({ id: 2, name: "M", cell: 1, host: false, tekrar: "m", yerel: true, ready: true });
  await t3.msg(m3, { t: "basla" });
  bak("misafir BAŞLAT gönderemez", !t3.room.g);

  // Tekrar Oyna: maç biter -> hazırlar sıfır, dönen oyuncu hazır değil
  t.room.g.phase = "bitti";
  await t.room.macBitti(t.room.g, null);
  bak("maç bitince herkesin hazırı sıfırlandı", [a, b, c].every((s) => s.info.ready === false));
  await t.msg(b, { t: "tekrar" });
  const lb = son(b, (m) => m.t === "lobi");
  bak("Tekrar Oyna sonrası lobide kimse hazır değil", lb && lb.players.filter((p) => !p.bot).every((p) => !p.r), JSON.stringify(lb && lb.players.map((p) => [p.name, p.r])));
  await t.msg(a, { t: "tekrar" });
  await t.msg(c, { t: "tekrar" });
  a.giden.length = 0;
  await t.msg(a, { t: "basla", oyunlar: ["ortalama"], hiz: 0.05 });
  bak("Tekrar Oyna sonrası hazır olmadan 2. maç başlamaz", !t.room.g && /Herkes hazır değil/.test((son(a, (m) => m.t === "bilgi") || {}).m || ""));
  await t.msg(b, { t: "hazir", on: true });
  await t.msg(c, { t: "hazir", on: true });
  await t.msg(a, { t: "basla", oyunlar: ["ortalama"], hiz: 0.05 });
  bak("herkes yeniden hazır: 2. maç başladı", !!t.room.g && t.room.g.phase !== "bitti");

  // mikrofon durumu
  const t4 = await yeniOda(false);
  const x = t4.sok({ id: 1, name: "X", cell: 0, host: true, tekrar: "x" });
  const y = t4.sok({ id: 2, name: "Y", cell: 1, host: false, tekrar: "y" });
  await t4.msg(x, { t: "mik", kapali: true });
  bak("mik: diğerlerine {t:'mik', id, kapali:true} gitti", y.giden.some((m) => m.t === "mik" && m.id === 1 && m.kapali === true));
  bak("mik: kendine geri gelmez", !x.giden.some((m) => m.t === "mik"));
  bak("mik: oyuncu listesinde mk", t4.room.players().find((p) => p.id === 1).mk === true && !t4.room.players().find((p) => p.id === 2).mk);
  const n0 = y.giden.length;
  await t4.msg(x, { t: "mik", kapali: true });
  bak("mik: aynı durum yeniden yollanmaz", y.giden.length === n0);
  await t4.msg(x, { t: "mik", kapali: false });
  bak("mik: açınca kapali:false gider, mk kalkar", y.giden.some((m) => m.t === "mik" && m.kapali === false) && !t4.room.players().find((p) => p.id === 1).mk);
}

async function birimHizli() {
  console.log("— birim: Hızlı Oyun —");
  const t = await yeniOda(true);
  const now = Date.now();
  const a = t.sok({ id: 1, name: "Ali", cell: 0, host: true, tekrar: "a", hazirSon: now + 35000 });
  const b = t.sok({ id: 2, name: "Bea", cell: 1, host: false, tekrar: "b", hazirSon: now + 35000 });
  await t.room.publicLobby();
  const sayim = (s) => son(s, (m) => m.t === "acik_oda");
  bak("kimse hazır değil: geri sayım yok (baslama -1)", sayim(a) && sayim(a).baslama === -1 && sayim(a).eksik === 2, JSON.stringify(sayim(a)));
  bak("bekleme: en geç ~35 sn sonra kendiliğinden hazır", sayim(a).bekle >= 33 && sayim(a).bekle <= 35, String(sayim(a).bekle));
  bak("alarm başlama zamanına değil kendiliğinden hazır anına kurulu", t.alarm >= now + 34000, String(t.alarm - now));
  await t.msg(a, { t: "hazir", on: true });
  bak("biri hazır: geri sayım hâlâ yok", sayim(b).baslama === -1 && sayim(b).eksik === 1);
  await t.msg(b, { t: "hazir", on: true });
  const s1 = sayim(b);
  bak("herkes hazır: geri sayım başladı", s1.baslama >= 5 && s1.baslama <= 26, JSON.stringify(s1));
  bak("alarm başlama zamanına kurulu", t.alarm === t.room.lobbyAt);
  // yeni gelen (hazır değil): geri sayım durur
  const c = t.sok({ id: 3, name: "Cem", cell: 2, host: false, tekrar: "c", hazirSon: Date.now() + 35000 });
  await t.room.publicLobby();
  bak("yeni gelen hazır değil: geri sayım durdu", sayim(a).baslama === -1 && sayim(a).eksik === 1);
  // başlama zamanı geçse de hazır olmayan varken başlamaz
  t.room.lobbyAt = Date.now() - 1;
  await t.room.alarm();
  bak("süre dolsa da HAZIR demeyen varken başlamadı", !t.room.g && !a.giden.some((m) => m.t === "basladi"));
  bak("alarm geçmiş başlama anına kurulmadı (döngü yok)", t.alarm > Date.now() + 1000, String(t.alarm - Date.now()));
  // C'nin süresi doldu: kendiliğinden hazır, geri sayım (en az 5 sn) başlar
  c.info.hazirSon = Date.now() - 1;
  await t.room.alarm();
  bak("süresi dolan kendiliğinden hazır sayıldı", c.info.ready === true && liste(a).find((p) => p.id === 3).r === true);
  const s2 = sayim(a);
  bak("herkes hazır: geri sayım en az 5 sn", s2.baslama >= 4 && s2.baslama <= 5, JSON.stringify(s2));
  bak("henüz başlamadı (geri sayım sürüyor)", !t.room.g);
  t.room.lobbyAt = Date.now() - 1;
  await t.room.alarm();
  bak("geri sayım bitince botla 4'e dolup başladı", !!t.room.g && t.room.players().length === 4 && t.room.players().filter((p) => p.bot).length === 1);
  // dolu oda (6 insan) herkes hazırsa 3 sn
  const t2 = await yeniOda(true);
  const ss = [];
  for (let i = 1; i <= 6; i++) ss.push(t2.sok({ id: i, name: "P" + i, cell: i - 1, host: i === 1, tekrar: "p" + i, ready: true, hazirSon: Date.now() + 35000 }));
  await t2.room.publicLobby();
  const s3 = son(ss[0], (m) => m.t === "acik_oda");
  bak("dolu oda, herkes hazır: 3 sn sonra başlar", s3 && s3.baslama >= 2 && s3.baslama <= 3, JSON.stringify(s3));
  // Tekrar Oyna (Hızlı Oyun): dönen oyuncunun hazırı sıfır, yeni süre
  t.room.g.phase = "bitti";
  await t.room.macBitti(t.room.g, null);
  await t.msg(a, { t: "tekrar" });
  bak("Hızlı Oyun Tekrar Oyna: dönen hazır değil, yeni otomatik hazır süresi", a.info.ready === false && a.info.hazirSon > Date.now() + 30000);
  bak("maç sonundakiler hazır sayılmaz (geri sayım yok)", sayim(a).baslama === -1);
}

// Bağlantı bildirimleri: koptu / ayrıldı (süre doldu) / odadan çıktı / oda sahibi; Kim Kim?'de ad yerine "****"
async function birimBildirim() {
  console.log("— birim: bağlantı bildirimleri —");
  const t = await yeniOda(false);
  const a = t.sok({ id: 1, name: "Ali", cell: 0, host: true, tekrar: "a", yerel: true, ready: true });
  const b = t.sok({ id: 2, name: "Bea", cell: 1, host: false, tekrar: "b", yerel: true, ready: true });
  const c = t.sok({ id: 3, name: "Cem", cell: 2, host: false, tekrar: "c", yerel: true, ready: true });
  await t.msg(a, { t: "basla", oyunlar: ["ortalama"], hiz: 0.05 });
  bak("bildirim: maç başladı", !!t.room.g);
  await t.room.drop(b);
  const k = son(a, (m) => m.t === "bilgi" && m.bag === "koptu");
  bak("bildirim: bağlantısı kopan herkese 'koptu' (ad + numara)", k && k.id === 2 && /Bea/.test(k.m) && k.m_k[0][0] === "{0} bağlantısı koptu, bekleniyor…", JSON.stringify(k));
  bak("bildirim: kopan listede 'kopuk' (baş üstü simgesi)", t.room.players().find((p) => p.id === 2).kopuk === true);
  // Kim Kim? sürerken ad sızmaz
  t.room.anon = () => ({});
  await t.room.drop(c);
  const k2 = son(a, (m) => m.t === "bilgi" && m.bag === "koptu" && m.id === 3);
  bak("bildirim: Kim Kim?'de gerçek ad yerine ****", k2 && !/Cem/.test(k2.m) && k2.m.includes("****"), JSON.stringify(k2));
  delete t.room.anon;
  // geri dönme süresi doldu: oyundan ayrıldı
  for (const x of Object.values(t.room.kopuk)) x.until = Date.now() - 1;
  t.room.g.ends = Date.now() + 60000;
  await t.room.alarm();
  const ay = a.giden.filter((m) => m.t === "bilgi" && m.bag === "ayrildi");
  bak("bildirim: süre dolunca 'oyundan ayrıldı'", ay.length >= 1 && ay.some((m) => m.id === 2 && /Bea/.test(m.m)), JSON.stringify(ay));
  // salonda: kurucu çıkınca 'odadan çıktı' + 'Oda sahibi artık ...'
  const t2 = await yeniOda(false);
  const h = t2.sok({ id: 1, name: "Han", cell: 0, host: true, tekrar: "h" });
  const z = t2.sok({ id: 2, name: "Zey", cell: 1, host: false, tekrar: "z" });
  await t2.msg(h, { t: "cik" });
  bak("bildirim: salonda çıkan 'odadan çıktı'", z.giden.some((m) => m.t === "bilgi" && m.bag === "cikti" && m.id === 1));
  const sh = son(z, (m) => m.t === "bilgi" && m.bag === "sahip");
  bak("bildirim: 'Oda sahibi artık Zey'", sh && sh.id === 2 && /Zey/.test(sh.m) && sh.m_k[0][0] === "Oda sahibi artık {0}.", JSON.stringify(sh));
}

// ---------------------------------------------------------------- uçtan uca (yerel sunucu)
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
    const eski = this.msgs.find(f);
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
      void eski;
    });
  }
  close() {
    try {
      this.send({ t: "cik" });
      this.ws.close();
    } catch {}
  }
}

async function oda(code, ad, kur, ek = "") {
  const h = await hesabi(ad);
  const w = new W(`${URL0}/oda/${code}?ad=${encodeURIComponent(ad)}&kur=${kur ? 1 : 0}&davet=${kur ? 0 : 1}&dil=tr&hesap=${h.token}${ek}`, ad);
  const p = w.wait("hosgeldin");
  await w.open();
  w.hos = await p;
  return w;
}

async function uctanUca() {
  try {
    const r = await fetch(URL0.replace("ws://", "http://") + "/");
    if (!r.ok) throw 0;
  } catch {
    console.log("  (yerel sunucu 8794 kapalı: uçtan uca kısım atlandı)");
    return;
  }
  console.log("— uçtan uca (8794) —");
  const code = kod();
  const A = await oda(code, "Ayse", true);
  const B = await oda(code, "Burak", false);
  let p = A.wait((d) => d.t === "oyuncular" && d.players.some((x) => x.bot));
  A.send({ t: "bot_ekle" });
  await p;
  // mikrofon
  p = A.wait((d) => d.t === "mik");
  B.send({ t: "mik", kapali: true });
  const mk = await p;
  bak("uçtan uca: mik mesajı diğer oyuncuya ulaştı", mk && mk.id === B.hos.id && mk.kapali === true, JSON.stringify(mk));
  // B hazır değil: BAŞLAT reddedilir
  p = A.wait((d) => d.t === "bilgi" && Array.isArray(d.hazir_degil));
  A.send({ t: "basla", oyunlar: ["ortalama"], hiz: 0.05 });
  const red = await p;
  bak("uçtan uca: hazır olmayan varken 'Herkes hazır değil'", red && red.hazir_degil.includes(B.hos.id) && /burak/i.test(red.m), JSON.stringify(red));
  await sleep(300);
  bak("uçtan uca: maç başlamadı", !B.msgs.some((m) => m.t === "basladi"));
  const l = [...B.msgs].reverse().find((m) => m.t === "oyuncular");
  bak("uçtan uca: listede B'nin mikrofonu kapalı (mk)", l && l.players.find((x) => x.id === B.hos.id).mk === true);
  bak("uçtan uca: kurucu BAŞLAT ile hazır sayıldı", l && l.players.find((x) => x.id === A.hos.id).r === true);
  B.send({ t: "hazir", on: true });
  await A.wait((d) => d.t === "oyuncular" && d.players.some((x) => x.id === B.hos.id && x.r));
  p = B.wait("basladi");
  A.send({ t: "basla", oyunlar: ["ortalama"], hiz: 0.05 });
  bak("uçtan uca: herkes hazır, maç başladı", !!(await p));
  // bağlantı kopması ve geri bağlanma (telefon gibi: aynı geri dönme anahtarıyla)
  p = A.wait((d) => d.t === "bilgi" && d.bag === "koptu");
  B.ws.close();
  const kop = await p;
  bak("uçtan uca: 'bağlantısı koptu' bildirimi", kop && kop.id === B.hos.id && /burak/i.test(kop.m), JSON.stringify(kop));
  await sleep(500);
  p = A.wait((d) => d.t === "bilgi" && d.bag === "geri");
  const B2 = await oda(code, "Burak", false, "&tekrar=" + B.hos.tekrar);
  const geri = await p;
  bak("uçtan uca: aynı oyuncu maça döndü", B2.hos && B2.hos.geri === true && B2.hos.id === B.hos.id);
  bak("uçtan uca: 'geri bağlandı' bildirimi", geri && geri.id === B.hos.id && /geri bağlandı/.test(geri.m), JSON.stringify(geri));
  A.close();
  B2.close();
  // salon: katılan / çıkan bildirimi
  const code2 = kod();
  const C = await oda(code2, "Cem", true);
  p = C.wait((d) => d.t === "bilgi" && d.bag === "katildi");
  const D = await oda(code2, "Deniz", false);
  const kat = await p;
  bak("uçtan uca: 'odaya katıldı' bildirimi", kat && kat.id === D.hos.id && /deniz/i.test(kat.m), JSON.stringify(kat));
  p = D.wait((d) => d.t === "bilgi" && d.bag === "sahip");
  C.close();
  const sah = await p;
  bak("uçtan uca: kurucu çıkınca 'Oda sahibi artık Deniz'", sah && sah.id === D.hos.id, JSON.stringify(sah));
  D.close();

  // Hızlı Oyun salonu: hazır değilken geri sayım yok, HAZIR deyince başlar
  let hk = "";
  try {
    hk = (await (await fetch(URL0.replace("ws://", "http://") + "/hizli", { headers: { "x-hesap": (await hesabi("Hizli")).token } })).json()).kod;
  } catch {}
  if (!/^[A-Z0-9]{4}$/.test(hk)) {
    bak("uçtan uca: Hızlı Oyun oda kodu alındı", false, hk);
    return;
  }
  const H = new W(`${URL0}/oda/${hk}?ad=Hizli&kur=0&davet=0&acik=1&dil=tr&hesap=${(await hesabi("Hizli")).token}`, "H");
  const ph = H.wait((d) => d.t === "acik_oda");
  await H.open();
  const s0 = await ph;
  bak("uçtan uca: Hızlı Oyun, HAZIR demeden geri sayım yok", s0 && s0.baslama === -1 && s0.bekle > 0, JSON.stringify(s0));
  const ps = H.wait((d) => d.t === "acik_oda" && d.baslama >= 0, 3000);
  H.send({ t: "hazir", on: true });
  const s1 = await ps;
  // (aynı odaya başka bir test istemcisi düştüyse onun hazırı beklenir: o zaman yalnız eksik sayısı azalır)
  const s1b = [...H.msgs].reverse().find((m) => m.t === "acik_oda");
  bak("uçtan uca: HAZIR deyince geri sayım başladı", (s1 && s1.baslama >= 5) || (s1b && s1b.eksik < s0.eksik), JSON.stringify(s1 || s1b));
  H.close();
}

await birimOzel();
await birimHizli();
await birimBildirim();
await uctanUca();
console.log(`\n${ok} geçti, ${hata} hatalı`);
process.exit(hata ? 1 : 0);
