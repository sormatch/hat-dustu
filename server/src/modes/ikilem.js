// MAHKUM İKİLEMİ: her turda oyuncular rastgele ikili eşleşir (tek sayıda kalan, bir ikiliye üçüncü olur).
// Eşler telefonla pazarlık eder; süre bitince herkes gizlice seçer: SUS (iş birliği) ya da ÖT (ihanet).
//   İkisi SUS: ikisi +2 · Biri ÖT, diğeri SUS: öten +3, susan -1 · İkisi ÖT: ikisi 0
// Üçlüde aynı kural: herkes susarsa herkes +2; tek öten +3, susanlar -1; birden çok öten varsa ötenler 0, susanlar -1.
// Seçmeyen susmuş sayılır. 2-3 tur, her turda (olabildiğince) farklı eş. Seçimler tur sonunda eşlere açılır.
// Botlar telefonu açamaz: bot eşin tahtana kısa bir not bırakır ("Susacağım." ya da "Öteceğim."), doğru ya da yalan.
// Oyundan kaldırmak için: game.js PLAYLIST'ten "ikilem" satırını sil.

export const title = "MAHKUM İKİLEMİ";
export const rule = "Eşinle telefonda pazarlık et. Sonra gizlice seç: SUS ya da ÖT.";
export const hidden = true; // puanlar maç sonuna kadar gizli (kullanıcı kuralı)
export const min = 3;
export const MAX_TUR = 3;

// her tur: pazarlık (telefon) -> seçim -> açılış
export const durations = { anons: 8 };
for (let t = 1; t <= MAX_TUR; t++) {
  durations["pazarlik" + t] = 50;
  durations["secim" + t] = 15;
  durations["acilis" + t] = 8;
}

export function phases(g) {
  const n = (g.m && g.m.turlar) || turSayisi(g.players.length);
  const out = ["anons"];
  for (let t = 1; t <= n; t++) out.push("pazarlik" + t, "secim" + t, "acilis" + t);
  return out;
}

// 3 kişiyle hep aynı üçlü olur: 2 tur yeter. 4+ kişide 3 tur (her turda farklı eş).
export function turSayisi(n) {
  return n <= 3 ? 2 : MAX_TUR;
}

const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
const shuffle = (arr) => {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
};
const key = (a, b) => (a < b ? a + "-" + b : b + "-" + a);

// Aşamanın tur numarası (pazarlik2 -> 2), tur aşaması değilse 0
export function turOf(phase) {
  const m = /^(pazarlik|secim|acilis)(\d)$/.exec(String(phase || ""));
  return m ? Number(m[2]) : 0;
}

// Oyuncuları ikili gruplara ayırır (tek sayıdaysa son grup üçlü). past: önceki eşleşmeler ("a-b" kümesi),
// bots: bot kimlikleri. Önce tekrar eden eşi, sonra insan-bot karışımını en aza indirir (insanlar birbiriyle konuşsun).
export function eslestir(players, past = new Set(), bots = []) {
  const ids = players.slice();
  if (ids.length < 2) return ids.length ? [ids] : [];
  const isBot = new Set(bots);
  const humans = ids.filter((x) => !isBot.has(x)).length;
  let best = null;
  let bestScore = Infinity;
  for (let i = 0; i < 400; i++) {
    const order = shuffle(ids);
    const groups = [];
    for (let k = 0; k + 1 < order.length; k += 2) groups.push([order[k], order[k + 1]]);
    if (order.length % 2) groups[groups.length - 1].push(order[order.length - 1]);
    let score = 0;
    let mixed = 0;
    for (const gr of groups) {
      for (let a = 0; a < gr.length; a++) for (let b = a + 1; b < gr.length; b++) if (past.has(key(gr[a], gr[b]))) score += 10;
      const h = gr.filter((x) => !isBot.has(x)).length;
      if (h > 0 && h < gr.length) mixed += 1;
      if (h === 1 && gr.length === 3) score += 1; // tek insanı iki botla bırakma
    }
    // insanlar çift sayıdaysa hiç karışık grup gerekmez; tekse en az bir tane
    score += Math.max(0, mixed - (humans % 2)) * 3;
    if (score < bestScore) {
      bestScore = score;
      best = groups;
      if (score === 0) break;
    }
  }
  return best;
}

// Grup puanı: choices {id: "sus"|"ot"}. Dönen {id: {delta, sonuc}}
//   sonuc: "ikisus" (hepiniz sustunuz), "satildin" (sen sustun, biri öttü), "sattin" (tek öten sendin),
//          "ikiot" (birden çok öten), "yalniz" (eşin oyundan ayrıldı)
export function puanla(choices) {
  const ids = Object.keys(choices);
  const out = {};
  if (ids.length < 2) {
    for (const id of ids) out[id] = { delta: 0, sonuc: "yalniz" };
    return out;
  }
  const ot = ids.filter((id) => choices[id] === "ot").length;
  for (const id of ids) {
    if (choices[id] === "ot") out[id] = ot === 1 ? { delta: 3, sonuc: "sattin" } : { delta: 0, sonuc: "ikiot" };
    else out[id] = ot === 0 ? { delta: 2, sonuc: "ikisus" } : { delta: -1, sonuc: "satildin" };
  }
  return out;
}

// ---------- botların kişiliği ----------
// sadik: çoğunlukla susar, notu doğru; hain: çoğunlukla öter, notunda "susacağım" der;
// kurnaz: geçen tur eşi öttüyse öter, yoksa susar; kararsiz: yazı tura.
export const KISILIK = {
  sadik: { sus: 0.85, durust: 0.9 },
  hain: { sus: 0.25, durust: 0.25 },
  kurnaz: { sus: 0.75, durust: 0.65 },
  kararsiz: { sus: 0.5, durust: 0.5 },
};

function botPlan(m, id) {
  const k = KISILIK[m.pers[id]] || KISILIK.kararsiz;
  let sus = k.sus;
  if (m.pers[id] === "kurnaz") {
    const last = m.hist[id] && m.hist[id][m.hist[id].length - 1];
    if (last && last.ihanet) sus = 0.15; // geçen tur satıldı: kısasa kısas
  }
  const secim = Math.random() < sus ? "sus" : "ot";
  const durust = Math.random() < k.durust;
  return { secim, not: durust ? secim : secim === "sus" ? "ot" : "sus" };
}

// t. turun eşleşmesini kurar; her oyuncunun gizli bilgisini (eşleri, bot eşin notu) günceller.
function kurTur(g, t) {
  const m = g.m;
  const groups = eslestir(g.players, new Set(Object.keys(m.past)), g.bots || []);
  m.groups[t - 1] = groups;
  m.picks[t - 1] = {};
  m.plan[t - 1] = {};
  for (const gr of groups) {
    for (let a = 0; a < gr.length; a++) for (let b = a + 1; b < gr.length; b++) m.past[key(gr[a], gr[b])] = true;
  }
  const isBot = new Set(g.bots || []);
  for (const id of g.players) if (isBot.has(id)) m.plan[t - 1][id] = botPlan(m, id);
  for (const gr of groups) {
    for (const id of gr) {
      const es = gr.filter((x) => x !== id).map((x) => {
        const e = { id: x, ad: g.names[x] || "?", bot: isBot.has(x) };
        if (e.bot) e.not = m.plan[t - 1][x].not;
        return e;
      });
      g.secret[id] = { tur_no: t, turlar: m.turlar, es };
    }
  }
}

export function start(g) {
  const m = { turlar: turSayisi(g.players.length), groups: [], picks: [], plan: [], past: {}, pers: {}, hist: {}, pts: {}, results: [] };
  g.m = m;
  const kisilikler = Object.keys(KISILIK);
  for (const id of g.bots || []) m.pers[id] = pick(kisilikler);
  kurTur(g, 1);
}

function grupOf(m, t, id) {
  return (m.groups[t - 1] || []).find((gr) => gr.includes(id)) || null;
}

export function stateExtra(g) {
  const t = turOf(g.phase);
  const picks = t ? g.m.picks[t - 1] || {} : {};
  return { tur: t, turlar: g.m.turlar, secen: Object.keys(picks).length };
}

function allPicked(g, t) {
  const picks = g.m.picks[t - 1] || {};
  return g.players.every((id) => id in picks || !grupOf(g.m, t, id));
}

// v: { secim: "sus" | "ot" } — pazarlık ve seçim aşamalarında; süre bitene kadar değiştirilebilir
export function answer(g, id, v) {
  const t = turOf(g.phase);
  if (!t || g.phase.startsWith("acilis") || !v || (v.secim !== "sus" && v.secim !== "ot")) return null;
  if (!grupOf(g.m, t, id)) return null;
  g.m.picks[t - 1][id] = v.secim;
  // herkes seçtiyse beklemeden açılır
  return {
    reply: { t: "karar_alindi", ne: "secim" },
    broadcast: { t: "olay", task: "ikilem", tur: "secti", secen: Object.keys(g.m.picks[t - 1]).length },
    advance: allPicked(g, t),
  };
}

export function onPhase(g, phase) {
  const m = g.m;
  const t = turOf(phase);
  if (!t) return null;
  if (phase.startsWith("pazarlik")) {
    if (t > 1) kurTur(g, t);
    // her oyuncuya yeni eşi (rol kartı yeniden açılır)
    const privates = {};
    for (const id of g.players) if (g.secret[id]) privates[id] = { t: "olay", task: "ikilem", tur: "eslesme", ...g.secret[id] };
    return { privates };
  }
  if (phase.startsWith("secim")) {
    if (allPicked(g, t)) return { advance: true }; // herkes pazarlıkta seçmişti
    return null;
  }
  // açılış: seçmeyen susmuş sayılır; her grup kendi seçimlerini görür
  const picks = m.picks[t - 1];
  const privates = {};
  const tur = { tur: t, gruplar: [] };
  for (const gr of m.groups[t - 1]) {
    const live = gr.filter((id) => g.players.includes(id));
    const ch = {};
    for (const id of live) ch[id] = picks[id] || "sus";
    const res = puanla(ch);
    const satirlar = live.map((id) => ({ id, ad: g.names[id] || "?", secim: ch[id], sonuc: res[id].sonuc }));
    tur.gruplar.push(satirlar);
    for (const id of live) {
      m.pts[id] = (m.pts[id] || 0) + res[id].delta;
      if (res[id].delta > 0) g.hits[id] = (g.hits[id] || 0) + 1;
      // kurnaz botlar için: bu tur eşlerinden biri öttü mü?
      (m.hist[id] ||= []).push({ secim: ch[id], ihanet: live.some((x) => x !== id && ch[x] === "ot") });
      privates[id] = { t: "olay", task: "ikilem", tur: "acilis", tur_no: t, turlar: m.turlar, grup: satirlar, sonuc: res[id].sonuc };
    }
  }
  m.results.push(tur);
  return { privates };
}

export function resolve(g) {
  const m = g.m;
  const priv = {};
  for (const id of g.players) {
    const mine = m.results.map((r) => {
      const gr = r.gruplar.find((x) => x.some((s) => s.id === id));
      const ben = gr ? gr.find((s) => s.id === id) : null;
      return ben ? { tur: r.tur, secim: ben.secim, sonuc: ben.sonuc, es: gr.filter((s) => s.id !== id).map((s) => ({ id: s.id, ad: s.ad, secim: s.secim })) } : null;
    }).filter(Boolean);
    const sus = mine.filter((x) => x.secim === "sus").length;
    const satildi = mine.filter((x) => x.sonuc === "satildin").length;
    const msg = !mine.length ? "Bu oyunda turun olmadı." : satildi ? (satildi === 1 ? "Bir kez satıldın." : "Birden çok kez satıldın.") : sus === mine.length ? "Hiç satılmadın, hep sustun." : "Hiç satılmadın.";
    priv[id] = { delta: m.pts[id] || 0, msg, turlar: mine };
  }
  return { public: { tur_sayisi: m.results.length }, private: priv };
}

export function leave(g, id) {
  const m = g.m;
  const t = turOf(g.phase);
  if (t) {
    const picks = m.picks[t - 1];
    if (picks) delete picks[id];
  }
  return g.players.length < 2;
}
