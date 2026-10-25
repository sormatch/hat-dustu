// KISA DEVRE: ışıklar kesilir, herkesin hücresindeki sigorta kutusu bozulur. Kutuda 4 renkli kablo ve
// 4 sembollü uç (yıldız, üçgen, daire, kare) var; her kablo doğru sembole bağlanmalı. Hangi kablonun nereye
// gideceği KENDİ tahtanda değil, başka birinin tahtasında yazar; sen de başkasının talimatını tutarsın.
//   Kendi kutunu onarırsan +1; tahtandaki talimatla başkası onarırsa sana da +1 (yardım).
//   Yanlış bağlantı: kutu kilitlenir (tek hak), -1. Süre bitince onarılmamış kutu -1.
// SABOTAJCI (gizli, 3+ kişide 1 kişi): tahtasındaki talimatın sahibi başarısız olursa +2 (sonda görünür).
// Süre bitince oylama: sabotajcıyı doğru tahmin eden +1; çoğunluk onu bulursa sabotajcı -2.

export const title = "KISA DEVRE";
export const rule = "Kabloları doğru sembollere bağla. Hangi kablo nereye? Başka birinin tahtasında yazıyor.";
export const durations = { anons: 10, calisma: 180, oylama: 25 };
export const hidden = false; // puanlar anında görünür

// Kolay ayırt edilen renkler ve telefonda kolay söylenen semboller
export const COLORS = ["KIRMIZI", "MAVİ", "SARI", "YEŞİL", "MOR", "TURUNCU"];
export const SYMBOLS = ["YILDIZ", "ÜÇGEN", "DAİRE", "KARE"];
const LETTERS = "BKPRSTVZ";

const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
const shuffle = (arr) => {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
};

export function phases(g) {
  return g.m && g.m.saboteur ? ["anons", "calisma", "oylama"] : ["anons", "calisma"];
}

// Kutu: soldaki 4 kablo (renk), sağdaki 4 uç (sembol). Doğru eşleşme gizli: renk -> sembol.
function makeBox(code) {
  const wires = shuffle(COLORS).slice(0, 4);
  const symbols = shuffle(SYMBOLS);
  const map = {};
  const targets = shuffle(SYMBOLS);
  wires.forEach((w, i) => (map[w] = targets[i]));
  return { code, wires, symbols, map, done: {}, status: "acik" };
}

export function boardText(b) {
  return `${b.code} KUTUSU\n` + b.wires.map((w, i) => `${i + 1}) ${w} >> ${b.map[w]}`).join("\n");
}

export function start(g) {
  const ids = shuffle(g.players);
  const used = new Set();
  const boxes = {};
  for (const id of ids) {
    let code;
    do code = pick(LETTERS.split("")) + (1 + Math.floor(Math.random() * 9));
    while (used.has(code));
    used.add(code);
    boxes[id] = makeBox(code);
  }
  // zincir: herkes bir sonrakinin talimatını tutar (kimse kendi talimatını görmez)
  const holder = {}; // kutu sahibi -> talimatı tahtasında olan
  ids.forEach((id, i) => (holder[id] = ids[(i + 1) % ids.length]));
  const boardOf = {}; // tahta sahibi -> talimatını tuttuğu kutunun sahibi
  for (const [owner, h] of Object.entries(holder)) boardOf[h] = Number(owner);
  const saboteur = ids.length >= 3 ? pick(ids) : 0;
  g.m = { boxes, holder, boardOf, saboteur, votes: {}, bonus: {}, events: [] };
  for (const id of ids) {
    const b = boxes[id];
    const target = boxes[boardOf[id]];
    g.secret[id] = {
      kod: b.code,
      kablolar: b.wires,
      semboller: b.symbols,
      adim_sayisi: b.wires.length,
      tahta: boardText(target),
      sabotajci: id === saboteur,
    };
  }
}

export function counts(g) {
  let onarilan = 0;
  let kilitli = 0;
  for (const b of Object.values(g.m.boxes)) {
    if (b.status === "tamir") onarilan++;
    if (b.status === "kilit") kilitli++;
  }
  return { onarilan, kilitli, toplam: Object.keys(g.m.boxes).length };
}

export function stateExtra(g) {
  return { ...counts(g), oylama: !!g.m.saboteur };
}

function fail(g, owner, why) {
  const b = g.m.boxes[owner];
  b.status = "kilit";
  g.score[owner] -= 1;
  const h = g.m.holder[owner];
  if (h === g.m.saboteur) g.m.bonus[h] = (g.m.bonus[h] || 0) + 2;
  return why;
}

// Kutuya bir işlem ya da oy. Dönen: { reply, others: [{to, msg}], broadcast, advance } ya da null
export function answer(g, id, v) {
  if (!v || typeof v !== "object") return null;
  if (v.oy !== undefined) {
    if (g.phase !== "oylama") return null;
    const t = Number(v.oy);
    if (!g.players.includes(t) || t === id) return null;
    g.m.votes[id] = t;
    const advance = g.players.every((p) => p in g.m.votes);
    return { reply: { t: "karar_alindi", ne: "oy" }, advance };
  }
  if (g.phase !== "calisma") return null;
  const b = g.m.boxes[id];
  if (!b) return null;
  if (b.status !== "acik") return { reply: { t: "devre", olay: b.status, puan: g.score[id] } };
  if (v.islem !== "bagla") return null;
  const renk = String(v.renk || "");
  const sembol = String(v.sembol || "");
  if (!b.wires.includes(renk) || !SYMBOLS.includes(sembol) || b.done[renk]) return null;
  if (Object.values(b.done).includes(sembol)) return null;
  const ok = b.map[renk] === sembol;
  if (ok) b.done[renk] = sembol;
  const finished = ok && Object.keys(b.done).length >= b.wires.length;
  const others = [];
  let olay;
  if (!ok) {
    fail(g, id, "yanlis");
    olay = "yanlis";
  } else {
    if (finished) {
      b.status = "tamir";
      olay = "tamir";
      g.score[id] += 1;
      const h = g.m.holder[id];
      if (h !== g.m.saboteur && g.players.includes(h)) {
        g.score[h] += 1;
        others.push({ to: h, msg: { t: "devre", olay: "yardim", kod: b.code, kim: g.names[id], delta: 1, puan: g.score[h] } });
      }
    } else {
      olay = "adim";
    }
  }
  const delta = olay === "tamir" ? 1 : olay === "yanlis" ? -1 : 0;
  const c = counts(g);
  const allDone = c.onarilan + c.kilitli >= c.toplam;
  return {
    reply: { t: "devre", olay, renk, sembol, adim: Object.keys(b.done).length, adim_sayisi: b.wires.length, delta, puan: g.score[id] },
    others,
    broadcast: { t: "devre_durum", ...c },
    advance: allDone,
  };
}

// Süre ya da oylama bitti. Dönen: { public, private: id -> {delta, msg} } (anlık puanlar zaten işlendi)
export function resolve(g) {
  const m = g.m;
  const priv = {};
  for (const id of g.players) priv[id] = { delta: 0, msg: [] };
  // onarılmadan kalan kutular
  for (const [owner, b] of Object.entries(m.boxes)) {
    const o = Number(owner);
    if (b.status === "acik" && g.players.includes(o)) {
      b.status = "kilit";
      priv[o].delta -= 1;
      priv[o].msg.push("Süre bitti, kutun onarılmadı (-1).");
      const h = m.holder[o];
      if (h === m.saboteur) m.bonus[h] = (m.bonus[h] || 0) + 2;
    }
  }
  let caught = false;
  let tally = {};
  if (m.saboteur) {
    for (const [voter, t] of Object.entries(m.votes)) tally[t] = (tally[t] || 0) + 1;
    let top = 0;
    let best = [];
    for (const [k, c] of Object.entries(tally)) {
      if (c > top) {
        top = c;
        best = [Number(k)];
      } else if (c === top) best.push(Number(k));
    }
    caught = best.length === 1 && best[0] === m.saboteur;
    for (const [voter, t] of Object.entries(m.votes)) {
      const vid = Number(voter);
      if (t === m.saboteur && vid !== m.saboteur && priv[vid]) {
        priv[vid].delta += 1;
        priv[vid].msg.push("Sabotajcıyı doğru tahmin ettin (+1).");
      }
    }
    if (priv[m.saboteur]) {
      const bonus = m.bonus[m.saboteur] || 0;
      if (bonus) {
        priv[m.saboteur].delta += bonus;
        priv[m.saboteur].msg.push(`Sabotajın işe yaradı (+${bonus}).`);
      }
      if (caught) {
        priv[m.saboteur].delta -= 2;
        priv[m.saboteur].msg.push("Yakalandın (-2).");
      }
    }
  }
  for (const id of g.players) priv[id].msg = priv[id].msg.join(" ") || "Süre bitti.";
  return {
    public: {
      sabotajci: m.saboteur, sabotajci_ad: m.saboteur ? g.names[m.saboteur] : "", yakalandi: caught, oylar: tally, ...counts(g),
    },
    private: priv,
  };
}

export function leave(g, id) {
  return false; // oyun devam eder; ayrılanın kutusu sayılmaz
}
