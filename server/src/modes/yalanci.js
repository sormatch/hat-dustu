// YALANCI: herkesin dolabında aynı eşya var (ör. kırmızı bandana), sadece birinin dolabında
// benzer ama FARKLI bir eşya var (ör. kırmızı bere). O kişi yalancıdır: farklı olduğunu bilir ama
// diğerlerinin eşyasının ne olduğunu bilmez; telefonda çaktırmadan öğrenip yalan söyler.
// Süre bitince yeşil tahtada yalancı oylanır. Doğru oy +1. Yalancı yakalanırsa -1, kaçarsa +3.

export const title = "YALANCI";
export const rule = "Dolabına bak. Herkeste aynı eşya var, birinde farklı. Yalancıyı bul!";
export const phases = ["anons", "telefon", "oylama"];
export const durations = { anons: 10, telefon: 120, oylama: 30 };
export const hidden = true; // puanlar maç sonuna kadar gizli (kullanıcı kuralı)
export const min = 3;

// [stil, ad] çiftleri: birbirine benzer, telefonda karıştırılabilir (stiller hats.gd'de çizilir)
export const PAIRS = [
  [["bandana", "KIRMIZI BANDANA"], ["ponpon", "KIRMIZI PONPONLU BERE"]],
  [["bere", "SİYAH BERE"], ["fotr", "SİYAH FÖTR ŞAPKA"]],
  [["kep", "MAVİ KEP"], ["baret", "SARI BARET"]],
  [["tac", "ALTIN TAÇ"], ["kulaklik", "KIRMIZI KULAKLIK"]],
];

const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];

export function start(g) {
  const pair = pick(PAIRS);
  const flip = Math.random() < 0.5;
  const common = flip ? pair[1] : pair[0];
  const odd = flip ? pair[0] : pair[1];
  const liar = pick(g.players);
  g.m = { liar, common, odd, votes: {} };
  for (const id of g.players) {
    const it = id === liar ? odd : common;
    g.secret[id] = { esya: it[0], esya_ad: it[1], yalanci: id === liar };
  }
}

export function stateExtra(g) {
  return { oy_veren: Object.keys(g.m.votes).length };
}

export function answer(g, id, v) {
  if (g.phase !== "oylama" || !v || v.oy === undefined) return null;
  const t = Number(v.oy);
  if (!g.players.includes(t) || t === id) return null;
  g.m.votes[id] = t;
  const advance = g.players.every((p) => p in g.m.votes);
  return { reply: { t: "karar_alindi", ne: "oy" }, broadcast: { t: "olay", task: "yalanci", tur: "oy", oy_veren: Object.keys(g.m.votes).length }, advance };
}

export function resolve(g) {
  const m = g.m;
  const tally = {};
  for (const t of Object.values(m.votes)) tally[t] = (tally[t] || 0) + 1;
  let top = 0;
  let best = [];
  for (const [k, c] of Object.entries(tally)) {
    if (c > top) {
      top = c;
      best = [Number(k)];
    } else if (c === top) best.push(Number(k));
  }
  const caught = best.length === 1 && best[0] === m.liar;
  const priv = {};
  for (const id of g.players) {
    if (id === m.liar) {
      priv[id] = caught ? { delta: -1, msg: "Yakalandın!" } : { delta: 3, msg: "Kimse seni bulamadı!" };
      continue;
    }
    const ok = m.votes[id] === m.liar;
    if (ok) g.hits[id] = (g.hits[id] || 0) + 1;
    priv[id] = {
      delta: ok ? 1 : 0,
      msg: ok ? "Yalancıyı doğru bildin!" : m.votes[id] ? "Yanlış kişiyi seçtin." : "Oy vermedin.",
    };
  }
  return {
    public: { yalanci: m.liar, yalanci_ad: g.names[m.liar] || "?", cogunluk: m.common[1], cogunluk_stil: m.common[0], farkli: m.odd[1], farkli_stil: m.odd[0], oylar: tally, yakalandi: caught },
    private: priv,
  };
}

export function leave(g, id) {
  delete g.m.votes[id];
  return id === g.m.liar || g.players.length < 2; // yalancı çıktıysa oyun iptal
}
