// KISA DEVRE: ışıklar kesilir, herkesin hücresindeki sigorta kutusu bozulur. Kutunun ekranında bir kod
// yazar (ör. "K7"). Onarma adımları KENDİ tahtanda değil, başka birinin tahtasında yazar; sen de
// başkasının talimatını tutarsın (zincir). Telefonla kimin kodunun kimde olduğunu bul, talimatı söyle.
//   Kendi kutunu doğru onarırsan +1; tahtandaki talimatla başkası onarırsa sana da +1 (yardım).
//   Yanlış adım: kutu kilitlenir (tek hak), -1. Süre bitince onarılmamış kutu -1.
// SABOTAJCI (gizli, 3+ kişide 1 kişi): tahtasındaki talimatın sahibi başarısız olursa +2 (sonda görünür).
// Süre bitince oylama: sabotajcıyı doğru tahmin eden +1; çoğunluk onu bulursa sabotajcı -2.

export const title = "KISA DEVRE";
export const rule = "Kutunu onarmanın adımları başka birinin tahtasında. Telefonla bul, birbirinize yardım edin.";
export const durations = { anons: 10, calisma: 180, oylama: 25 };
export const hidden = false; // puanlar anında görünür

export const COLORS = ["KIRMIZI", "TURUNCU", "SARI", "YEŞİL", "AÇIK MAVİ", "KOYU MAVİ", "MOR", "BEYAZ", "SİYAH", "GRİ"];
const LETTERS = "BKPRSTVZ";
const SOCKETS = ["A", "B", "C", "D"];

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

function makeBox(code) {
  const wires = shuffle(COLORS).slice(0, 5);
  const plugs = shuffle(COLORS).slice(0, 3);
  const types = shuffle(["kes", "tak", "salter", "kod"]).slice(0, 2 + (Math.random() < 0.5 ? 1 : 0));
  const steps = types.map((t) => {
    if (t === "kes") return { t, renk: pick(wires) };
    if (t === "tak") return { t, renk: pick(plugs), soket: pick(SOCKETS) };
    if (t === "salter") return { t, sira: shuffle([1, 2, 3, 4]).slice(0, 2 + Math.floor(Math.random() * 2)) };
    return { t, kod: String(1000 + Math.floor(Math.random() * 9000)) };
  });
  return { code, wires, plugs, steps, step: 0, sub: 0, status: "acik", cut: [], plugged: {}, switches: [] };
}

export function stepText(s) {
  if (s.t === "kes") return `${s.renk} kabloyu kes`;
  if (s.t === "tak") return `${s.renk} fişi ${s.soket} soketine tak`;
  if (s.t === "salter") return `Şalterleri sırayla aç: ${s.sira.join(" → ")}`;
  return `Tuş takımına gir: ${s.kod}`;
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
      fisler: b.plugs,
      adim_sayisi: b.steps.length,
      moduller: ["kes", "tak", "salter", "kod"].filter((k) => b.steps.some((s) => s.t === k)), // panelde sadece gerekenler
      tahta: `${target.code} KODLU KUTU\n` + target.steps.map((s, i) => `${i + 1}) ${stepText(s)}`).join("\n"),
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
  const s = b.steps[b.step];
  let ok = false;
  let stepDone = false;
  if (v.islem === "kes") {
    const renk = String(v.renk || "");
    if (!b.wires.includes(renk) || b.cut.includes(renk)) return null;
    b.cut.push(renk);
    ok = s.t === "kes" && s.renk === renk;
    stepDone = ok;
  } else if (v.islem === "tak") {
    const renk = String(v.renk || "");
    const soket = String(v.soket || "");
    if (!b.plugs.includes(renk) || !SOCKETS.includes(soket)) return null;
    b.plugged[renk] = soket;
    ok = s.t === "tak" && s.renk === renk && s.soket === soket;
    stepDone = ok;
  } else if (v.islem === "salter") {
    const no = Number(v.no);
    if (![1, 2, 3, 4].includes(no) || b.switches.includes(no)) return null;
    b.switches.push(no);
    ok = s.t === "salter" && s.sira[b.sub] === no;
    if (ok) {
      b.sub += 1;
      stepDone = b.sub >= s.sira.length;
    }
  } else if (v.islem === "kod") {
    ok = s.t === "kod" && String(v.kod || "") === s.kod;
    stepDone = ok;
  } else {
    return null;
  }
  const others = [];
  let olay;
  if (!ok) {
    fail(g, id, "yanlis");
    olay = "yanlis";
  } else if (stepDone) {
    b.step += 1;
    b.sub = 0;
    if (b.step >= b.steps.length) {
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
  } else {
    olay = "ilerle"; // şalter sırasında doğru ama adım bitmedi
  }
  const delta = olay === "tamir" ? 1 : olay === "yanlis" ? -1 : 0;
  const c = counts(g);
  const allDone = c.onarilan + c.kilitli >= c.toplam;
  return {
    reply: { t: "devre", olay, adim: b.step, adim_sayisi: b.steps.length, delta, puan: g.score[id] },
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
