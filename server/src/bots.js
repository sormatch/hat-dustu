// Bot oyuncular: kurucu lobiden ekler; sunucuda oynarlar (bağlantıları yok). Her oyunda insan gibi
// biraz bekleyip karar verirler. plan(): yeni kararları zamanlar ve en erken zamanı döndürür;
// due(): zamanı gelen kararları [botId, karar] olarak verir. Telefonla konuşamazlar.

export const NAMES = ["Kara Ali", "Sinsi Necmi", "Deli Rıza", "Topal Vedat", "Sessiz Kemal", "Kel Hüsnü", "Çakal Sedat"];
const WORDS = ["ELMA", "ÇORBA", "ANAHTAR", "TÜNEL", "KAŞIK", "KAPI", "PARMAK", "SABUN"];

const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
const rnd = (a, b) => a + Math.random() * (b - a);

// Bu bot şu an neye karar vermeli? Dönen: { key, delay: [min,max] sn, act: () => karar | [kararlar] } ya da null
function need(g, id) {
  const m = g.m;
  if (!m || !g.players.includes(id)) return null;
  const ph = g.phase;
  switch (g.task) {
    case "tahta":
      if (id === m.writer && (ph === "anons" || ph === "telefon") && !m.word)
        return { key: "yaz", delay: [2, 5], act: () => pick(WORDS) };
      if (id !== m.writer && ph === "telefon" && !m.guesses[id])
        return { key: "tahmin", delay: [8, 25], act: () => (Math.random() < 0.4 && m.word ? m.word : pick(WORDS)) };
      return null;
    case "devre": {
      if (ph === "calisma") {
        const b = m.boxes[id];
        if (!b || b.status !== "acik") return null;
        return {
          key: "kutu", delay: [10, 30],
          act: () => {
            const wrong = Math.random() < 0.25;
            return b.wires.map((w, i) => {
              let sembol = b.map[w];
              if (wrong && i === 2) sembol = b.map[b.wires[3]];
              return { islem: "bagla", renk: w, sembol };
            });
          },
        };
      }
      if (ph === "oylama" && !(id in m.votes))
        return { key: "oy", delay: [3, 8], act: () => ({ oy: pick(g.players.filter((x) => x !== id)) }) };
      return null;
    }
    case "kimkim":
      if ((ph === "telefon") && !m.guesses[id])
        return {
          key: "eslesme", delay: [10, 40],
          act: () => {
            const lines = Object.entries(m.line).filter(([pid]) => Number(pid) !== id);
            const left = g.players.filter((x) => x !== id);
            const es = {};
            for (const [pid, n] of lines) {
              const who = Math.random() < 0.4 && left.includes(Number(pid)) ? Number(pid) : pick(left);
              left.splice(left.indexOf(who), 1);
              es[n] = who;
            }
            return { eslesme: es };
          },
        };
      return null;
    case "yalanci":
      if (ph === "oylama" && !(id in m.votes))
        return { key: "oy", delay: [3, 10], act: () => ({ oy: id !== m.liar && Math.random() < 0.4 ? m.liar : pick(g.players.filter((x) => x !== id)) }) };
      return null;
    case "rulet":
      if (ph === "oyun" && m.holder === id && !m.endAt && m.alive.includes(id))
        return {
          key: "atis" + m.dead.length + ":" + JSON.stringify(m.last) + ":" + m.stage,
          delay: [3.6, 6.5],
          act: () => {
            const others = m.alive.filter((x) => x !== id);
            const chance = [15, 35, 50, 100][m.stage];
            const self = chance < 100 && Math.random() < (chance <= 35 ? 0.75 : 0.45);
            return { atis: self ? "kendi" : pick(others) };
          },
        };
      return null;
    case "c4":
      if (ph === "bomba" && m.holder === id && !m.boom)
        return {
          key: "ver" + m.gives, delay: [4, 10],
          act: () => {
            const pool = g.players.filter((x) => x !== id && x !== m.from);
            return { ver: pick(pool.length ? pool : g.players.filter((x) => x !== id)) };
          },
        };
      return null;
    case "ortalama":
      if (ph.startsWith("yaz") && !(id in m.picks[Number(ph.slice(-1)) - 1]))
        return { key: ph, delay: [3, 12], act: () => ({ sayi: Math.round(rnd(5, 45)) }) };
      return null;
  }
  return null;
}

// Yeni kararları zamanlar. Dönen: en erken karar zamanı (ms) ya da Infinity.
export function plan(g, now) {
  if (!g || !g.bots || !g.bots.length || g.phase === "bitti" || g.phase === "sonuc" || g.phase === "baslangic") return Infinity;
  g.bp = g.bp || {};
  let next = Infinity;
  for (const id of g.bots) {
    const n = need(g, id);
    if (!n) {
      delete g.bp[id];
      continue;
    }
    const key = g.task + ":" + g.round + ":" + g.phase + ":" + n.key;
    let p = g.bp[id];
    if (!p || p.key !== key) {
      p = g.bp[id] = { key, at: now + rnd(n.delay[0], n.delay[1]) * 1000 * Math.max(0.3, g.speed), done: false };
    }
    if (!p.done) next = Math.min(next, p.at);
  }
  return next;
}

// Zamanı gelen kararlar: [[botId, karar], ...]
export function due(g, now) {
  const out = [];
  if (!g || !g.bots || !g.bp) return out;
  for (const id of g.bots) {
    const p = g.bp[id];
    if (!p || p.done || now < p.at - 30) continue;
    const n = need(g, id);
    const key = n ? g.task + ":" + g.round + ":" + g.phase + ":" + n.key : "";
    p.done = true;
    if (!n || key !== p.key) continue;
    const v = n.act();
    for (const one of Array.isArray(v) ? v : [v]) out.push([id, one]);
  }
  return out;
}
