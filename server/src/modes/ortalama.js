// ORTALAMA SAYI: tek el. Herkes gizlice 0-100 arası bir sayı yazar. Yazılan sayıların
// ortalamasının YARISINA en yakın olan +2 (eşitlikte hepsi). Sayı yazmayan -1.
// Ortalama ve yarısı tam sayıya yuvarlanır (küsurat yok).
// Sonda tüm sayılar, ortalama ve hedef tahtada tek tek açılır.

export const title = "ORTALAMA SAYI";
export const rule = "0-100 arası bir sayı yaz. Ortalamanın yarısına en yakın kazanır.";
export const phases = ["anons", "yaz1", "goster1"];
export const durations = { anons: 10, yaz1: 40, goster1: 10 };
export const hidden = true; // puanlar maç sonuna kadar gizli (kullanıcı kuralı)
export const min = 2;
const ELLER = 1;

export function start(g) {
  g.m = { picks: [{}], pts: {}, wins: {}, results: [] };
}

const handOf = (phase) => Number(String(phase).slice(-1)) - 1;

export function stateExtra(g) {
  const k = g.phase.startsWith("yaz") || g.phase.startsWith("goster") ? handOf(g.phase) : -1;
  return { el: k + 1, eller: ELLER, yazan: k >= 0 ? Object.keys(g.m.picks[k]).length : 0, sonuclar: g.m.results };
}

// v: { sayi: 0-100 }
export function answer(g, id, v) {
  if (!g.phase.startsWith("yaz") || !v || v.sayi === undefined) return null;
  const n = Math.round(Number(v.sayi));
  if (!Number.isFinite(n) || n < 0 || n > 100) return { reply: { t: "bilgi", m: "0 ile 100 arası bir sayı yaz." } };
  const k = handOf(g.phase);
  g.m.picks[k][id] = n;
  const advance = g.players.every((p) => p in g.m.picks[k]);
  return {
    reply: { t: "karar_alindi", ne: "sayi" },
    broadcast: { t: "olay", task: "ortalama", tur: "yazdi", yazan: Object.keys(g.m.picks[k]).length },
    advance,
  };
}

function add(m, id, d) {
  m.pts[id] = (m.pts[id] || 0) + d;
}

// elin sonucu: herkesin sayısı, ortalama, hedef (yarısı), kazananlar
export function onPhase(g, phase) {
  if (!phase.startsWith("goster")) return null;
  const k = handOf(phase);
  const m = g.m;
  const picks = m.picks[k];
  const ids = g.players.filter((id) => id in picks);
  const sayilar = g.players.map((id) => ({ id, ad: g.names[id], sayi: id in picks ? picks[id] : null }));
  let ort = 0;
  let hedef = 0;
  let kazananlar = [];
  if (ids.length) {
    // küsurat yok: ortalama tam sayıya yuvarlanır, hedef onun yarısı (yine tam sayı)
    ort = Math.round(ids.reduce((s, id) => s + picks[id], 0) / ids.length);
    hedef = Math.round(ort / 2);
    const best = Math.min(...ids.map((id) => Math.abs(picks[id] - hedef)));
    kazananlar = ids.filter((id) => Math.abs(Math.abs(picks[id] - hedef) - best) < 1e-9);
  }
  for (const id of kazananlar) {
    add(m, id, 2);
    m.wins[id] = (m.wins[id] || 0) + 1;
  }
  for (const id of g.players) if (!(id in picks)) add(m, id, -1);
  const res = { el: k + 1, sayilar, ortalama: ort, hedef, kazananlar };
  m.results.push(res);
  return { broadcast: { t: "olay", task: "ortalama", tur: "goster", ...res, eller: ELLER } };
}

export function resolve(g) {
  const m = g.m;
  const priv = {};
  for (const id of g.players) {
    const w = m.wins[id] || 0;
    g.hits[id] = (g.hits[id] || 0) + w;
    priv[id] = { delta: m.pts[id] || 0, msg: w ? "Yarısına en yakın sendin!" : "Bu sefer olmadı." };
  }
  return { public: { sonuclar: m.results }, private: priv };
}

export function leave(g, id) {
  return g.players.length < 2;
}
