// KİM KİM?: arkadaşlarla oynanır. Rehberde isim ve hücre numarası yok, sadece "Hat 1, Hat 2..."
// (odada kaç kişi varsa). Herkesin sesi robot sesine döner. Telefonla konuşup hangi hattın kim
// olduğunu bulmaya çalışırsın; yeşil tahtada her hattın yanına bir arkadaşının adını seçersin.
// En çok doğru eşleştiren 1. +2, 2. +1 (eşitlikte aynı sırayı paylaşırlar). Yalan serbest!

import { metin } from "../metin.js";

export const title = "KİM KİM?";
export const rule = "Rehberde isim yok, sesler robot. Hangi hat kim? Tahtada eşleştir.";
export const phases = ["anons", "telefon"];
export const durations = { anons: 10, telefon: 180 };
export const hidden = true; // puanlar maç sonuna kadar gizli (kullanıcı kuralı)
export const min = 3;
// sadece arkadaşlarını davet edenlerin odasında (birbirini tanıyanlar)
export const requires = (players) => players.some((p) => p.inv);

const shuffle = (arr) => {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
};

export function start(g) {
  const order = shuffle(g.players);
  const line = {}; // oyuncu -> hat numarası (1..N)
  order.forEach((id, i) => (line[id] = i + 1));
  g.m = { line, guesses: {} };
  for (const id of g.players) {
    g.secret[id] = {
      hat: line[id],
      toplam: g.players.length,
      adaylar: g.players.filter((x) => x !== id).map((x) => ({ id: x, ad: g.names[x] })),
    };
  }
}

// Arananın telefonunda arayan bu numarayla görünür ("****"): ne adı ne de hattı belli olur
export const GIZLI = 99;

// Takma kimlik: Kim Kim? sürerken telefonlar oyuncuları 100+hat olarak bilir (gerçek kimlik gizli)
export function alias(g, id) {
  return g.m && g.m.line[id] ? 100 + g.m.line[id] : id;
}

export function unalias(g, x) {
  if (!g.m || x < 100) return x;
  for (const [id, n] of Object.entries(g.m.line)) if (100 + n === x) return Number(id);
  return 0;
}

export function stateExtra(g) {
  return { toplam: Object.keys(g.m.line).length, kaydeden: Object.keys(g.m.guesses).length };
}

// v: { eslesme: { "hat numarası": oyuncu id } }
export function answer(g, id, v) {
  if ((g.phase !== "telefon" && g.phase !== "anons") || !v || typeof v.eslesme !== "object" || !v.eslesme) return null;
  const mine = g.m.line[id];
  const clean = {};
  const used = new Set();
  for (const [k, val] of Object.entries(v.eslesme)) {
    const n = Number(k);
    const who = Number(val);
    if (!Number.isInteger(n) || n === mine || !Object.values(g.m.line).includes(n)) continue;
    if (who === id || !(who in g.m.line) || used.has(who)) continue;
    used.add(who);
    clean[n] = who;
  }
  g.m.guesses[id] = clean;
  const need = Object.keys(g.m.line).length - 1;
  // herkes tüm hatları eşleştirip kaydettiyse beklemeden biter
  const allDone = g.players.every((p) => g.m.guesses[p] && Object.keys(g.m.guesses[p]).length >= need);
  return {
    reply: { t: "karar_alindi", ne: "eslesme" },
    broadcast: { t: "olay", task: "kimkim", tur: "kaydetti", kaydeden: Object.keys(g.m.guesses).length },
    advance: allDone,
  };
}

export function resolve(g) {
  const m = g.m;
  const byLine = {};
  for (const [id, n] of Object.entries(m.line)) byLine[n] = Number(id);
  const correct = {};
  for (const id of g.players) {
    let c = 0;
    for (const [n, who] of Object.entries(m.guesses[id] || {})) if (byLine[n] === who) c++;
    correct[id] = c;
    g.hits[id] = (g.hits[id] || 0) + c;
  }
  // sıralama: en çok doğru 1. (+2), sonraki 2. (+1); 0 doğru puan almaz
  const levels = [...new Set(Object.values(correct).filter((c) => c > 0))].sort((a, b) => b - a);
  const need = Object.keys(m.line).length - 1;
  const priv = {};
  for (const id of g.players) {
    const c = correct[id];
    const place = levels.indexOf(c);
    const delta = c > 0 && place === 0 ? 2 : c > 0 && place === 1 ? 1 : 0;
    const msg = !m.guesses[id]
      ? metin("msg", "Tahtaya eşleştirme kaydetmedin.")
      : metin("msg", ["{0} hattın {1} tanesini doğru bildin.", [need, c]], delta === 2 ? "En iyi tahmin!" : delta === 1 ? "İkinci en iyi tahmin!" : "");
    priv[id] = { delta, ...msg, dogru: c, tahmin: m.guesses[id] || {} };
  }
  const hatlar = Object.keys(byLine).map(Number).sort((a, b) => a - b).map((n) => ({ hat: n, id: byLine[n], ad: g.names[byLine[n]] || "?" }));
  return { public: { hatlar, dogru: correct }, private: priv };
}

export function leave(g, id) {
  delete g.m.guesses[id];
  return g.players.length < 2;
}
