// KUMARBAZ: 3 el. Her elde herkes gizlice iki zar atar (toplam 2-12). Telefonla konuşulur, blöf serbest;
// herkes tahtasına bir İDDİA yazar ("zarım 9"). Sonra iddialar açılır ve herkes bir kişiye "YALAN!" diyebilir.
//   - Meydan okunan ve iddiası zarından BÜYÜK çıkan (yalan): -2, ona "yalan" diyen her biri +1.
//   - Meydan okunan ama doğru söyleyen: +1, ona "yalan" diyen her biri -1.
//   - Yalanı yakalanmayanlar arasında EN YÜKSEK iddia eli kazanır: +2 (eşitlikte hepsi). Yakalanmayan blöf de kazanabilir!
// İddia yazmayanın iddiası zarının kendisi sayılır. El sonunda tüm zarlar açılır.
// Oyundan kaldırmak için: game.js PLAYLIST'ten "kumar" satırını sil.

export const title = "KUMARBAZ";
export const rule = "Zarını gizle, iddianı yaz. En yüksek iddia kazanır; yalanı yakalanan kaybeder.";
export const hidden = true; // puanlar maç sonuna kadar gizli (kullanıcı kuralı)
export const min = 3;
export const ELLER = 3;

export const durations = { anons: 8 };
for (let k = 1; k <= ELLER; k++) {
  durations["zar" + k] = 40; // telefon + iddia
  durations["meydan" + k] = 20; // iddialar açık: "YALAN!" de ya da inan
  durations["acilis" + k] = 8; // zarlar açılır
}
export const phases = ["anons"];
for (let k = 1; k <= ELLER; k++) phases.push("zar" + k, "meydan" + k, "acilis" + k);

const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
const zar = () => 1 + Math.floor(Math.random() * 6);

export function elOf(phase) {
  const m = /^(zar|meydan|acilis)(\d)$/.exec(String(phase || ""));
  return m ? Number(m[2]) : 0;
}

// İki zarın toplamı s'den KÜÇÜK olma olasılığı (iddia s ise yalan olma olasılığı)
export function yalanOlasiligi(s) {
  let n = 0;
  for (let a = 1; a <= 6; a++) for (let b = 1; b <= 6; b++) if (a + b < s) n++;
  return n / 36;
}

// Elin hesabı. iddia {id: n}, gercek {id: toplam}, meydan {id: hedef id | 0}. Dönen { puan: {id: delta}, satirlar, kazananlar }
export function hesapla(ids, iddia, gercek, meydan) {
  const puan = {};
  for (const id of ids) puan[id] = 0;
  const diyenler = {}; // hedef -> ona "yalan" diyenler
  for (const id of ids) {
    const h = Number(meydan[id] || 0);
    if (h && h !== id && ids.includes(h)) (diyenler[h] ||= []).push(id);
  }
  const yakalanan = new Set();
  for (const [hs, list] of Object.entries(diyenler)) {
    const h = Number(hs);
    if (iddia[h] > gercek[h]) {
      yakalanan.add(h);
      puan[h] -= 2;
      for (const d of list) puan[d] += 1;
    } else {
      puan[h] += 1;
      for (const d of list) puan[d] -= 1;
    }
  }
  const aday = ids.filter((id) => !yakalanan.has(id));
  const top = aday.length ? Math.max(...aday.map((id) => iddia[id])) : 0;
  const kazananlar = aday.filter((id) => iddia[id] === top);
  for (const id of kazananlar) puan[id] += 2;
  const satirlar = ids.map((id) => ({
    id,
    iddia: iddia[id],
    zar_toplam: gercek[id],
    meydan: diyenler[id] || [],
    yalan: iddia[id] > gercek[id],
    yakalandi: yakalanan.has(id),
    dedi: Number(meydan[id] || 0),
  }));
  return { puan, satirlar, kazananlar };
}

// ---------- botların kişiliği ----------
// durust: zarını söyler; blofcu: sık sık yüksek atar; temkinli: küçük blöf, az meydan okur; deli: her şeyi dener.
export const KISILIK = {
  durust: { blof: 0.12, esik: 0.6 },
  blofcu: { blof: 0.7, esik: 0.5 },
  temkinli: { blof: 0.3, esik: 0.72 },
  deli: { blof: 0.55, esik: 0.38 },
};

export function botIddia(pers, toplam) {
  const k = KISILIK[pers] || KISILIK.durust;
  if (toplam >= 10 || Math.random() >= k.blof) return toplam;
  const ust = pers === "temkinli" ? 2 : 4;
  return Math.min(12, Math.max(toplam + 1, 7 + Math.floor(Math.random() * 3)) + Math.floor(Math.random() * ust));
}

// Bot kime "yalan" der: en olası yalanı (kendi zarını da düşünerek yüksek iddiayı daha çok sorgular), ya da 0
export function botMeydan(pers, id, iddialar) {
  const k = KISILIK[pers] || KISILIK.durust;
  let best = 0;
  let bp = 0;
  for (const [hs, n] of Object.entries(iddialar)) {
    const h = Number(hs);
    if (h === id) continue;
    const p = yalanOlasiligi(n) + (Math.random() - 0.5) * 0.2;
    if (p > bp) {
      bp = p;
      best = h;
    }
  }
  return bp >= k.esik ? best : 0;
}

function atZar(g, k) {
  const m = g.m;
  m.dice[k - 1] = {};
  m.claims[k - 1] = {};
  m.chal[k - 1] = {};
  for (const id of g.players) {
    const z = [zar(), zar()];
    m.dice[k - 1][id] = z;
    g.secret[id] = { el: k, eller: ELLER, zar: z };
  }
}

export function start(g) {
  g.m = { dice: [], claims: [], chal: [], pts: {}, wins: {}, pers: {}, results: [] };
  const kisilikler = Object.keys(KISILIK);
  for (const id of g.bots || []) g.m.pers[id] = pick(kisilikler);
  atZar(g, 1);
}

const toplam = (z) => (z ? z[0] + z[1] : 0);

export function stateExtra(g) {
  const k = elOf(g.phase);
  const m = g.m;
  const out = { el: k, eller: ELLER };
  if (!k) return out;
  if (g.phase.startsWith("zar")) out.iddia_veren = Object.keys(m.claims[k - 1] || {}).length;
  else out.karar_veren = Object.keys(m.chal[k - 1] || {}).length;
  // iddialar açıldıktan sonra herkes görür (yeniden bağlanan da)
  if (!g.phase.startsWith("zar")) out.iddialar = iddiaListesi(g, k);
  return out;
}

function iddiaListesi(g, k) {
  const m = g.m;
  return g.players
    .filter((id) => m.dice[k - 1] && m.dice[k - 1][id])
    .map((id) => ({ id, ad: g.names[id] || "?", iddia: m.claims[k - 1][id] }))
    .sort((a, b) => b.iddia - a.iddia);
}

// v: { iddia: 2-12 } (zar aşaması) ya da { meydan: oyuncu id | 0 } (meydan aşaması)
export function answer(g, id, v) {
  const k = elOf(g.phase);
  const m = g.m;
  if (!k || !v || !m.dice[k - 1] || !m.dice[k - 1][id]) return null;
  if (g.phase.startsWith("zar") && v.iddia !== undefined) {
    const n = Math.round(Number(v.iddia));
    if (!Number.isFinite(n) || n < 2 || n > 12) return { reply: { t: "bilgi", m: "İddia 2 ile 12 arası olmalı." } };
    m.claims[k - 1][id] = n;
    const n2 = Object.keys(m.claims[k - 1]).length;
    return {
      reply: { t: "karar_alindi", ne: "iddia" },
      broadcast: { t: "olay", task: "kumar", tur: "iddia", iddia_veren: n2 },
      advance: g.players.every((p) => p in m.claims[k - 1]),
    };
  }
  if (g.phase.startsWith("meydan") && v.meydan !== undefined) {
    const h = Number(v.meydan) || 0;
    if (h === id || (h && !g.players.includes(h))) return null;
    m.chal[k - 1][id] = h;
    const n2 = Object.keys(m.chal[k - 1]).length;
    return {
      reply: { t: "karar_alindi", ne: "meydan" },
      broadcast: { t: "olay", task: "kumar", tur: "meydan", karar_veren: n2 },
      advance: g.players.every((p) => p in m.chal[k - 1]),
    };
  }
  return null;
}

export function onPhase(g, phase) {
  const k = elOf(phase);
  const m = g.m;
  if (!k) return null;
  if (phase.startsWith("zar")) {
    if (k === 1) return null; // ilk elin zarı oyun başında (gizli bilgiyle) geldi
    atZar(g, k);
    const privates = {};
    for (const id of g.players) privates[id] = { t: "olay", task: "kumar", tur: "zar", ...g.secret[id] };
    return { privates };
  }
  if (phase.startsWith("meydan")) {
    // iddia yazmayanın iddiası zarının kendisi
    for (const id of g.players) if (!(id in m.claims[k - 1]) && m.dice[k - 1][id]) m.claims[k - 1][id] = toplam(m.dice[k - 1][id]);
    return { broadcast: { t: "olay", task: "kumar", tur: "iddialar", el: k, iddialar: iddiaListesi(g, k) } };
  }
  // açılış: hesap, tüm zarlar açılır
  const ids = g.players.filter((id) => m.dice[k - 1][id]);
  const gercek = {};
  for (const id of ids) gercek[id] = toplam(m.dice[k - 1][id]);
  const r = hesapla(ids, m.claims[k - 1], gercek, m.chal[k - 1]);
  for (const id of ids) {
    m.pts[id] = (m.pts[id] || 0) + r.puan[id];
    if (r.kazananlar.includes(id)) m.wins[id] = (m.wins[id] || 0) + 1;
  }
  for (const s of r.satirlar) {
    s.ad = g.names[s.id] || "?";
    s.zar = m.dice[k - 1][s.id];
    // doğru "yalan" deyişler beraberlikte üstünlük sayılır
    if (s.dedi && r.satirlar.find((x) => x.id === s.dedi && x.yakalandi)) g.hits[s.id] = (g.hits[s.id] || 0) + 1;
  }
  for (const id of r.kazananlar) g.hits[id] = (g.hits[id] || 0) + 1;
  r.satirlar.sort((a, b) => b.iddia - a.iddia);
  const res = { el: k, satirlar: r.satirlar, kazananlar: r.kazananlar };
  m.results.push(res);
  return { broadcast: { t: "olay", task: "kumar", tur: "acilis", ...res } };
}

export function resolve(g) {
  const m = g.m;
  const priv = {};
  for (const id of g.players) {
    const w = m.wins[id] || 0;
    let yak = 0;
    for (const r of m.results) {
      const s = r.satirlar.find((x) => x.id === id);
      if (s && s.yakalandi) yak++;
    }
    const msg = w && !yak ? "Masadan kazançlı kalktın!" : w ? "Kazandın ama yalanın da yakalandı." : yak ? "Blöfün yakalandı." : "Bu sefer şans yüzüne gülmedi.";
    priv[id] = { delta: m.pts[id] || 0, msg };
  }
  return { public: { sonuclar: m.results }, private: priv };
}

export function leave(g, id) {
  const k = elOf(g.phase);
  if (k && g.m.dice[k - 1]) {
    delete g.m.dice[k - 1][id];
    delete g.m.claims[k - 1][id];
    delete g.m.chal[k - 1][id];
    // ona "yalan" diyenlerin kararı boşa düşer
    for (const [p, h] of Object.entries(g.m.chal[k - 1])) if (h === id) g.m.chal[k - 1][p] = 0;
  }
  return g.players.length < 2;
}
