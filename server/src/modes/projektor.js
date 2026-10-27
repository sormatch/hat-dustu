// PROJEKTÖR AVI: gece, avlu. Gardiyan herkesi hizaya sokup avluya çıkarır (anons: sinematik açılış), sonra
// ona kadar sayar (sayim: ışıklar kapalı, herkes bir siperin arkasına saklanır). Av başlayınca kulelerdeki
// projektörler avluyu tarar: siper dışında ışığa yakalanan elenir. Işıklar zamanla çoğalır ve hızlanır.
// Gardiyan arada bazı siperleri aratır (önce uyarır): aranan siperdekiler kaçmazsa yakalanır; kaçarken ışığa
// yakalanabilirler. Son kalan kazanır. Puan: yakalanan -1, süre bitince hayatta kalan +2, tek kalan +3.
//
// Yakalanma sunucuda: insanların konumu (Room "konum" mesajı -> onKonum) ışık yollarıyla karşılaştırılır.
// Işık yolları tohumdan hesaplanır, istemci aynı formülle çizer (isikMerkez). Gecikmeye pay: ışıkta ilk görülüşte
// uyarı ("isikta"), ISIK_SURE ms sonra hâlâ ışıktaysa yakalanır; sunucu yarıçapı çizilenden biraz küçük.
// Botların konumu yok: sunucuda siperden sipere koşarlar (olay "bot_kos"), yolda ışığa denk gelirlerse yakalanırlar.

import { metin } from "../metin.js";

export const title = "PROJEKTÖR AVI";
export const rule = "Siperlere saklan! Işığa yakalanan elenir. Gardiyan aramaya gelince yer değiştir.";
export const phases = ["anons", "sayim", "av"];
export const durations = { anons: 28, sayim: 12, av: 110 };
export const hidden = true; // puanlar maç sonuna kadar gizli (kullanıcı kuralı)
export const min = 2;
export const surum = 2; // istemci sürümü 2 ve üstü (sv) olmayan oyuncu varsa bu oyun seçilmez

// Avlu (dünya koordinatı, x-z düzlemi). Hücre koridorunun uzağında ayrı bir alan; istemci projektor_ui.gd aynı
// değerleri kullanır (değiştirirsen ikisini birlikte değiştir).
export const AVLU = { x0: 23, x1: 57, z0: -13, z1: 13 };
export const GIRIS = [25.2, 0]; // avlu kapısının içi: herkes burada başlar
// Siperler: arkasına saklanılan noktalar (siperin gölgesi). Yarıçap içinde duran ışıktan korunur.
export const SIPERLER = [
  [29, -9.5], [29, 9], [34.5, -2.5], [35, 6.5], [40.5, -9.5],
  [40.5, 9.5], [45.5, 1.5], [47, -8], [51.5, 7], [53, -3.5],
];
export const SIPER_R = 1.1;
export const ISIK_R = 2.4; // çizilen ışık dairesi
const ISIK_R_SUNUCU = 2.1; // yakalama yarıçapı (gecikme payı)
const ISIK_SURE = 350; // ms: ışıkta bu kadar kalan yakalanır
const KULELER = 4;

// Işık sayısı ve hızı: başta 2, 35. sn'de 3, 70. sn'de 4 (az oyuncuda bir eksik); zaman hızlanır.
export function aktifIsik(gecen, n) {
  const k = gecen < 35000 ? 2 : gecen < 70000 ? 3 : 4;
  return Math.max(1, Math.min(KULELER, n <= 3 ? k - 1 : k));
}

// Hızlanan zaman (sn): ışıkların yolu bu zamana göre ilerler (başta ~1x, 110. sn'de ~2x)
export function tau(gecenMs) {
  const t = gecenMs / 1000;
  return t + (t * t) / 220;
}

// Tohumdan ışık parametreleri: [fx, fz, px, pz] (frekans ve faz). Lissajous yolu avluyu dolaşır.
export function isiklar(tohum) {
  let s = tohum >>> 0 || 1;
  const r = () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
  const out = [];
  for (let i = 0; i < KULELER; i++) out.push([0.13 + r() * 0.07, 0.17 + r() * 0.08, r() * 6.283, r() * 6.283]);
  return out;
}

// i. ışığın yerdeki merkezi (istemci isik_merkez ile aynı)
export function isikMerkez(p, gecenMs) {
  const t = tau(gecenMs);
  const cx = (AVLU.x0 + AVLU.x1) / 2;
  const cz = (AVLU.z0 + AVLU.z1) / 2;
  const ax = (AVLU.x1 - AVLU.x0) / 2 - 1.5;
  const az = (AVLU.z1 - AVLU.z0) / 2 - 1.5;
  return [cx + ax * Math.sin(p[0] * t + p[2]), cz + az * Math.sin(p[1] * t + p[3])];
}

function siperde(p) {
  for (let i = 0; i < SIPERLER.length; i++) if (Math.hypot(p[0] - SIPERLER[i][0], p[1] - SIPERLER[i][1]) <= SIPER_R) return i;
  return -1;
}

// Bu noktaya şu an (av başından gecen ms) bir ışık vuruyor mu?
function isikta(m, p, gecen, n) {
  const k = aktifIsik(gecen, n);
  for (let i = 0; i < k; i++) {
    const c = isikMerkez(m.isik[i], gecen);
    if (Math.hypot(p[0] - c[0], p[1] - c[1]) <= ISIK_R_SUNUCU) return true;
  }
  return false;
}

const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
const karistir = (a) => {
  const b = a.slice();
  for (let i = b.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [b[i], b[j]] = [b[j], b[i]];
  }
  return b;
};

export function start(g) {
  const tohum = Math.floor(Math.random() * 2 ** 31);
  g.m = {
    alive: g.players.slice(), dead: [], pts: {}, tohum, isik: isiklar(tohum), t0: 0, uyari: {}, pos: {},
    bot: {}, // botId -> { siper, a: [x,z], b: [x,z], s, d } (s..s+d arası koşuyor)
    q: [], // zamanlanmış işler: { at, tur, ... }
    arama: null, // { siper: [i], at }: uyarısı yapılmış arama
    wake: 0, bitis: 0,
  };
}

function bots(g) {
  return (g.bots || []).filter((id) => g.m.alive.includes(id));
}

function gecen(g, now = Date.now()) {
  return g.m.t0 ? now - g.m.t0 : 0;
}

export function stateExtra(g) {
  const m = g.m;
  const now = Date.now();
  const kos = {};
  for (const [id, b] of Object.entries(m.bot)) kos[id] = { siper: b.siper, a: b.a, b: b.b, kalan: Math.max(0, b.s + b.d - now), d: b.d };
  return {
    hayatta: m.alive, yakalanan: m.dead, tohum: m.tohum, gecen: g.phase === "av" ? gecen(g, now) : 0,
    arama: m.arama ? { siper: m.arama.siper, kalan: Math.max(0, m.arama.at - now) } : null, botlar: kos,
  };
}

function kuyruk(m, is) {
  m.q.push(is);
  m.q.sort((a, b) => a.at - b.at);
  m.wake = m.q.length ? m.q[0].at : 0;
}

// Botu bir siperden ötekine koşturur; yolda ışığa denk gelirse o an yakalanır (kuyruğa yazılır).
function botKos(g, id, hedef, gecikme, out) {
  const m = g.m;
  const now = Date.now() + gecikme;
  const b = m.bot[id] || { siper: -1, a: GIRIS, b: GIRIS, s: 0, d: 0 };
  const a = b.siper >= 0 ? SIPERLER[b.siper] : b.b;
  const h = SIPERLER[hedef];
  const d = Math.max(900, Math.round((Math.hypot(h[0] - a[0], h[1] - a[1]) / 4.2) * 1000));
  m.bot[id] = { siper: hedef, a: [a[0], a[1]], b: [h[0], h[1]], s: now, d };
  out.push({ t: "olay", task: "projektor", tur: "bot_kos", id, a: m.bot[id].a, b: m.bot[id].b, gecikme, d });
  if (g.phase !== "av") return;
  // yolda ışık: 150 ms aralıkla bakılır (siperin içi güvenli)
  for (let t = 0; t <= d; t += 150) {
    const k = t / d;
    const p = [a[0] + (h[0] - a[0]) * k, a[1] + (h[1] - a[1]) * k];
    if (siperde(p) >= 0) continue;
    if (isikta(m, p, gecen(g, now + t), g.players.length)) {
      kuyruk(m, { at: now + t + ISIK_SURE, tur: "bot_isik", id, s: now });
      return;
    }
  }
}

function botSiperSec(g, haric = []) {
  const m = g.m;
  const dolu = new Set(Object.values(m.bot).map((b) => b.siper));
  const bos = SIPERLER.map((_, i) => i).filter((i) => !dolu.has(i) && !haric.includes(i));
  return bos.length ? pick(bos) : pick(SIPERLER.map((_, i) => i).filter((i) => !haric.includes(i)));
}

function yakala(g, id, neden) {
  const m = g.m;
  if (!m.alive.includes(id)) return null;
  m.alive = m.alive.filter((x) => x !== id);
  m.dead.push(id);
  m.pts[id] = (m.pts[id] || 0) - 1;
  delete m.uyari[id];
  delete m.bot[id];
  return { t: "olay", task: "projektor", tur: "yakalandi", id, neden, hayatta: m.alive };
}

// Biri yakalandıktan sonra: tek kişi (ya da kimse) kaldıysa oyun 3 sn sonra biter
function bitisKontrol(g) {
  const m = g.m;
  if (m.alive.length <= 1 && !m.bitis) {
    if (m.alive.length === 1) m.pts[m.alive[0]] = (m.pts[m.alive[0]] || 0) + 3;
    m.bitis = Date.now() + 3200;
    m.q = [];
    m.arama = null;
    kuyruk(m, { at: m.bitis, tur: "bitir" });
  }
}

export function onPhase(g, phase) {
  const m = g.m;
  const out = [];
  if (phase === "sayim") {
    // botlar kapıdan farklı siperlere koşar (biraz düşünüp)
    for (const id of bots(g)) botKos(g, id, botSiperSec(g), 800 + Math.floor(Math.random() * 2500), out);
  } else if (phase === "av") {
    m.t0 = Date.now();
    kuyruk(m, { at: m.t0 + 14000, tur: "arama_uyari" });
  }
  return out.length ? { broadcast: out.length === 1 ? out[0] : { t: "olay", task: "projektor", tur: "coklu", liste: out } } : null;
}

// Arama: önce uyarı (hangi siperler, 5 sn), sonra o siperlerdekiler yakalanır.
function aramaUyari(g, out) {
  const m = g.m;
  const now = Date.now();
  const dolu = new Set();
  for (const id of m.alive) {
    if (m.bot[id]) dolu.add(m.bot[id].siper);
    else if (m.pos[id]) {
      const s = siperde(m.pos[id]);
      if (s >= 0) dolu.add(s);
    }
  }
  const k = m.alive.length > 4 ? 3 : 2;
  const dolular = karistir([...dolu]).slice(0, Math.ceil(k / 2));
  const kalan = karistir(SIPERLER.map((_, i) => i).filter((i) => !dolular.includes(i))).slice(0, k - dolular.length);
  const siper = [...dolular, ...kalan];
  m.arama = { siper, at: now + 5000 };
  out.push({ t: "olay", task: "projektor", tur: "arama_uyari", siper, ms: 5000 });
  kuyruk(m, { at: m.arama.at, tur: "arama" });
  // aranan siperdeki botlar kaçar (insan gibi biraz geç fark eder; bazen hiç fark etmez)
  for (const id of bots(g)) {
    const b = m.bot[id];
    if (b && siper.includes(b.siper) && Math.random() < 0.85) botKos(g, id, botSiperSec(g, siper), 600 + Math.floor(Math.random() * 2800), out);
  }
}

function arama(g, out) {
  const m = g.m;
  const now = Date.now();
  const siper = m.arama ? m.arama.siper : [];
  m.arama = null;
  const yakalanan = [];
  for (const id of m.alive.slice()) {
    let s = -1;
    const b = m.bot[id];
    if (b) s = now >= b.s + b.d ? b.siper : -1; // koşan bot siperde sayılmaz
    else if (m.pos[id]) s = siperde(m.pos[id]);
    if (s >= 0 && siper.includes(s)) {
      const e = yakala(g, id, "arama");
      if (e) yakalanan.push(id);
    }
  }
  out.push({ t: "olay", task: "projektor", tur: "arama", siper, yakalanan, hayatta: m.alive });
  bitisKontrol(g);
  if (!m.bitis) {
    // sonraki arama: zamanla sıklaşır (14 sn -> 8 sn)
    const ara = Math.max(8000, 14000 - gecen(g, now) / 20);
    kuyruk(m, { at: now + ara, tur: "arama_uyari" });
  }
}

export function onWake(g) {
  const m = g.m;
  if (g.phase !== "av" && g.phase !== "sayim") return null;
  const now = Date.now();
  const out = [];
  let bitir = false;
  while (m.q.length && m.q[0].at <= now + 30) {
    const is = m.q.shift();
    if (is.tur === "bitir") bitir = true;
    else if (is.tur === "arama_uyari" && g.phase === "av") aramaUyari(g, out);
    else if (is.tur === "arama" && g.phase === "av") arama(g, out);
    else if (is.tur === "bot_isik") {
      const b = m.bot[is.id];
      if (b && b.s === is.s) {
        const e = yakala(g, is.id, "isik");
        if (e) out.push(e);
        bitisKontrol(g);
      }
    }
  }
  m.wake = m.q.length ? m.q[0].at : 0;
  if (bitir) return { finish: true };
  if (!out.length) return null;
  return { broadcast: out.length === 1 ? out[0] : { t: "olay", task: "projektor", tur: "coklu", liste: out } };
}

// Room her konum mesajında çağırır (yalnız insanlar). Dönen: deliver sonucu ya da null.
export function onKonum(g, id, p) {
  const m = g.m;
  if (!m || !m.alive.includes(id)) return null;
  m.pos[id] = p;
  if (g.phase !== "av" || m.bitis) return null;
  const now = Date.now();
  if (siperde(p) >= 0 || !isikta(m, p, gecen(g, now), g.players.length)) {
    if (m.uyari[id]) {
      delete m.uyari[id];
      return { privates: { [id]: { t: "olay", task: "projektor", tur: "karanlik" } } };
    }
    return null;
  }
  const u = m.uyari[id];
  if (u && now - u >= ISIK_SURE && now - u < 2500) {
    const e = yakala(g, id, "isik");
    bitisKontrol(g);
    return e ? { broadcast: e } : null;
  }
  if (!u || now - u >= 2500) {
    m.uyari[id] = now;
    return { privates: { [id]: { t: "olay", task: "projektor", tur: "isikta" } } };
  }
  return null;
}

// Projektör Avı'nda oyuncunun seçeceği bir şey yok (saklanmak yürüyerek)
export function answer() {
  return null;
}

export function resolve(g) {
  const m = g.m;
  const sag = m.alive.filter((x) => g.players.includes(x));
  // süre bittiyse hayatta kalanlar +2 (tek kalanın +3'ü bitisKontrol'de verildi)
  if (sag.length > 1) for (const id of sag) m.pts[id] = (m.pts[id] || 0) + 2;
  const priv = {};
  for (const id of g.players) {
    const yasiyor = sag.includes(id);
    priv[id] = { delta: m.pts[id] || 0, ...metin("msg", yasiyor ? (sag.length === 1 ? "Son kalan sensin!" : "Yakalanmadın!") : "Gardiyana yakalandın.") };
  }
  return {
    public: { kazanan: sag.length === 1 ? sag[0] : 0, kazanan_ad: sag.length === 1 ? g.names[sag[0]] : "", hayatta: sag, yakalanan: m.dead },
    private: priv,
  };
}

export function leave(g, id) {
  const m = g.m;
  m.alive = m.alive.filter((x) => x !== id);
  delete m.bot[id];
  delete m.pos[id];
  delete m.uyari[id];
  if (g.phase === "av") bitisKontrol(g);
  return g.players.length < 2;
}
