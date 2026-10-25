// Hat Düştü oyun kuralları (saf mantık; Room ağ işini yapar).
//
// KARA TAHTA: Her tur sırayla biri "yazan" olur ve hücresindeki yeşil tahtaya gizli bir kelime yazar.
// Diğerleri kelimeyi telefonla öğrenmeye çalışır ve kendi tahtalarına tahminlerini yazar.
// Tek tur, tek uzun süre (240 sn): herkes tahtasına istediği kadar yazıp silebilir; süre bitince tahtada ne varsa o sayılır.
// Yazanın hedefi: kelimeyi TAM olarak belli sayıda kişinin bilmesi (oyuncu sayısıyla orantılı).
//   Bilen +1, bilemeyen -1. Yazan: tam hedef kadar kişi bildiyse +2, değilse -1.
// Puanlar oyun bitene kadar gizli: herkes sadece kendi sonucunu görür. Sonda en çok puanı olan kazanır.

export const ROUNDS = 1; // bir oyun = tek tur (240 sn)
export const DURATIONS = { anons: 8, telefon: 240, sonuc: 10 };

export const TASKS = {
  tahta: {
    title: "KARA TAHTA",
    rule: "Bu tur bir kişi hücresindeki tahtaya gizli bir kelime yazar. Diğerleri telefonla kelimeyi öğrenip kendi tahtasına yazar. Bilen +1, bilemeyen -1 puan. Yazan, kelimeyi TAM hedef sayıdaki kişiye bildirtmeli: tutarsa +2, tutmazsa -1. Puanlar oyun sonuna kadar gizli!",
  },
};

const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
const shuffle = (arr) => {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
};

// Türkçe küçük harf, harf dışı atılır: "Elma " = "ELMA" = "elma"
export function norm(s) {
  return String(s || "")
    .replace(/İ/g, "i").replace(/I/g, "ı")
    .toLocaleLowerCase("tr-TR")
    .replace(/[^a-zçğıöşü]/g, "");
}

// Kaç kişi bilmeli: tahmin edenlerin ~%40'ı (en az 1). 5 oyuncu → 2, 6 → 2, 8 → 3.
export function target(n) {
  return Math.max(1, Math.round((n - 1) * 0.4));
}

// players: [{id, name, cell}]
export function newGame(players, speed = 1) {
  const ids = players.map((p) => p.id);
  const order = shuffle(ids);
  const rounds = ROUNDS;
  const g = {
    round: 0, rounds, phase: "baslangic", task: "tahta", speed,
    players: ids.slice(), names: {}, cells: {}, score: {}, hits: {},
    writers: Array.from({ length: rounds }, (_, i) => order[i % order.length]),
    writer: 0, word: "", guesses: {}, secret: {}, winner: 0,
  };
  for (const p of players) {
    g.names[p.id] = p.name;
    g.cells[p.id] = p.cell;
    g.score[p.id] = 0;
    g.hits[p.id] = 0;
  }
  return g;
}

export function duration(g, phase) {
  return Math.max(2, Math.round(DURATIONS[phase] * g.speed));
}

export function startRound(g) {
  g.round += 1;
  g.phase = "anons";
  g.word = "";
  g.guesses = {};
  g.secret = {};
  let w = g.writers[g.round - 1];
  if (!g.players.includes(w)) w = pick(g.players); // yazacak kişi oyundan çıkmışsa
  g.writer = w;
  const t = target(g.players.length);
  for (const id of g.players) {
    g.secret[id] = id === w
      ? { yazan: true, hedef: t, tahminci: g.players.length - 1 }
      : { yazan: false, yazan_id: w, yazan_ad: g.names[w], hedef: t, tahminci: g.players.length - 1 };
  }
}

// Kelime ya da tahmin. Dönen: "kelime" (yazan yazdı), "tahmin", ya da "" (geçersiz).
export function answer(g, id, v) {
  if (!g.players.includes(id)) return "";
  const w = norm(v);
  if (w.length < 2 || w.length > 16) return "";
  if (g.phase !== "anons" && g.phase !== "telefon") return "";
  if (id === g.writer) {
    g.word = w;
    return "kelime";
  }
  g.guesses[id] = w;
  return "tahmin";
}

export function allGuessed(g) {
  return g.players.every((id) => id === g.writer || id in g.guesses);
}

// Turu bitirir. Dönen: { public: herkese gidecek (puan yok), private: id -> sadece o kişiye }
export function resolve(g) {
  g.phase = "sonuc";
  const t = target(g.players.length);
  const priv = {};
  const wname = g.names[g.writer] || "?";
  if (!g.word) {
    // yazan süresinde yazmadı: sadece o -1, tur sayılmaz
    for (const id of g.players) {
      if (id === g.writer) {
        g.score[id] -= 1;
        priv[id] = { delta: -1, score: g.score[id], msg: "Süren doldu, tahtaya kelime yazmadın." };
      } else {
        priv[id] = { delta: 0, score: g.score[id], msg: `${wname} kelime yazmadı, bu tur sayılmadı.` };
      }
    }
    return { public: { word: "", writer: g.writer, writer_name: wname }, private: priv };
  }
  let hits = 0;
  for (const id of g.players) {
    if (id === g.writer) continue;
    const ok = g.guesses[id] === g.word;
    if (ok) {
      hits += 1;
      g.hits[id] += 1;
    }
    g.score[id] += ok ? 1 : -1;
    const guess = g.guesses[id] ? g.guesses[id].toLocaleUpperCase("tr-TR") : "(boş)";
    priv[id] = { delta: ok ? 1 : -1, score: g.score[id], guess, msg: ok ? "Doğru bildin!" : "Bilemedin." };
  }
  const exact = hits === t;
  g.score[g.writer] += exact ? 2 : -1;
  priv[g.writer] = {
    delta: exact ? 2 : -1, score: g.score[g.writer],
    msg: exact ? `Tam ${t} kişi bildi, hedef tuttu!` : `${hits} kişi bildi, hedef ${t} idi.`,
  };
  return { public: { word: g.word.toLocaleUpperCase("tr-TR"), writer: g.writer, writer_name: wname }, private: priv };
}

// Oyun bitti mi (tur sayısı doldu ya da 2'den az kişi kaldı)? Bittiyse kazananı seçer.
export function checkEnd(g) {
  if (g.round < g.rounds && g.players.length >= 2) return false;
  const pool = g.players.length ? g.players : Object.keys(g.score).map(Number);
  const top = Math.max(...pool.map((id) => g.score[id]));
  let best = pool.filter((id) => g.score[id] === top);
  if (best.length > 1) {
    const h = Math.max(...best.map((id) => g.hits[id]));
    best = best.filter((id) => g.hits[id] === h); // eşitlikte en çok bilen
  }
  g.winner = pick(best);
  g.phase = "bitti";
  return true;
}

// Bitiş tablosu: [{id, name, score}] kazanan en üstte, sonra puana göre.
export function table(g) {
  const ids = Object.keys(g.score).map(Number);
  ids.sort((a, b) => (b === g.winner) - (a === g.winner) || g.score[b] - g.score[a] || g.hits[b] - g.hits[a]);
  return ids.map((id) => ({ id, name: g.names[id], score: g.score[id], left: !g.players.includes(id) }));
}

export function removePlayer(g, id) {
  g.players = g.players.filter((x) => x !== id);
}
