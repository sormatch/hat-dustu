// KARA TAHTA: rastgele bir "yazan" hücresindeki yeşil tahtaya gizli bir kelime yazar.
// Diğerleri kelimeyi telefonla öğrenip kendi tahtasına yazar. 240 sn boyunca yazıp silebilirler;
// süre bitince tahtada ne varsa o sayılır. Bilen +1, bilemeyen -1. Yazan: TAM hedef sayıda kişi
// bildiyse +2, değilse -1 (hedef oyuncu sayısıyla orantılı). Bu oyunun puanları maç sonuna kadar gizli.

export const title = "KARA TAHTA";
export const rule = "Yazan tahtaya gizli bir kelime yazar; diğerleri telefonla öğrenip kendi tahtasına yazar.";
export const phases = ["anons", "telefon"];
export const durations = { anons: 8, telefon: 240 };
export const hidden = true; // puanlar maç sonuna kadar gizli

const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];

export function norm(s) {
  return String(s || "")
    .replace(/İ/g, "i").replace(/I/g, "ı")
    .toLocaleLowerCase("tr-TR")
    .replace(/[^a-zçğıöşü]/g, "");
}

// Kaç kişi bilmeli: tahmin edenlerin ~%40'ı (en az 1). 5 oyuncu → 2, 8 → 3.
export function target(n) {
  return Math.max(1, Math.round((n - 1) * 0.4));
}

export function start(g) {
  const m = { writer: pick(g.players), word: "", guesses: {} };
  g.m = m;
  const t = target(g.players.length);
  for (const id of g.players) {
    g.secret[id] = id === m.writer
      ? { yazan: true, hedef: t, tahminci: g.players.length - 1 }
      : { yazan: false, yazan_id: m.writer, yazan_ad: g.names[m.writer], hedef: t, tahminci: g.players.length - 1 };
  }
}

export function stateExtra(g) {
  return { writer: g.m.writer, writer_name: g.names[g.m.writer] || "" };
}

// v: yazılan kelime. Dönen: { reply } (sadece yazana) ya da null (geçersiz)
export function answer(g, id, v) {
  if (g.phase !== "anons" && g.phase !== "telefon") return null;
  const w = norm(v);
  if (w.length < 2 || w.length > 16) return { reply: { t: "bilgi", m: "Bu kelime yazılamaz (2-16 harf, sadece harf)." } };
  if (id === g.m.writer) g.m.word = w;
  else if (g.phase === "telefon") g.m.guesses[id] = w;
  else return null;
  return { reply: { t: "karar_alindi", ne: id === g.m.writer ? "kelime" : "tahmin" } };
}

// Oyun sonu: { public, private: id -> {delta, msg, ...} }
export function resolve(g) {
  const m = g.m;
  const t = target(g.players.length);
  const priv = {};
  const wname = g.names[m.writer] || "?";
  if (!m.word) {
    for (const id of g.players) {
      priv[id] = id === m.writer
        ? { delta: -1, msg: "Süren doldu, tahtaya kelime yazmadın." }
        : { delta: 0, msg: `${wname} kelime yazmadı, bu oyun sayılmadı.` };
    }
    return { public: { word: "", writer: m.writer, writer_name: wname }, private: priv };
  }
  let hits = 0;
  for (const id of g.players) {
    if (id === m.writer) continue;
    const ok = m.guesses[id] === m.word;
    if (ok) {
      hits += 1;
      g.hits[id] = (g.hits[id] || 0) + 1;
    }
    const guess = m.guesses[id] ? m.guesses[id].toLocaleUpperCase("tr-TR") : "(boş)";
    priv[id] = { delta: ok ? 1 : -1, guess, msg: ok ? "Doğru bildin!" : "Bilemedin." };
  }
  const exact = hits === t;
  priv[m.writer] = { delta: exact ? 2 : -1, msg: exact ? `Tam ${t} kişi bildi, hedef tuttu!` : `${hits} kişi bildi, hedef ${t} idi.` };
  return { public: { word: m.word.toLocaleUpperCase("tr-TR"), writer: m.writer, writer_name: wname }, private: priv };
}

export function leave(g, id) {
  return id === g.m.writer; // yazan çıktıysa oyun iptal
}
