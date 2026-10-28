// C4: bir hücrede aniden C4 belirir; ne zaman patlayacağı belli değil. Hücre kapıları açılır,
// koridorda dolaşılabilir. Bomba sendeyse birine yaklaş, "Bombayı ver": bomba ona geçer, sen kendi
// hücrene ışınlanırsın. Bomba rastgele bir anda patlar: elinde patlayan -2, diğer herkes +1.

export const title = "C4";
export const rule = "Bomba sendeyse birine yaklaş ve ver. Ne zaman patlayacağı belli değil.";
export const phases = ["anons", "bomba"];
export const durations = { anons: 8, bomba: 150 };
export const hidden = true; // puanlar maç sonuna kadar gizli (kullanıcı kuralı)
export const min = 2;
const GIVE_BACK_MS = 4000; // aynı kişiye hemen geri verilemez

const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];

export function start(g) {
  g.m = { holder: pick(g.players), from: 0, at: 0, gives: 0, wake: 0, boom: 0 };
}

export function stateExtra(g) {
  return { bomba: g.m.holder, verilen: g.m.gives, patlayan: g.m.boom };
}

export function onPhase(g, phase) {
  if (phase !== "bomba") return null;
  // fitil: 50-110 sn arası, hiç kimse bilmez (test hızında kısalır)
  const sec = (50 + Math.random() * 60) * g.speed;
  g.m.wake = Date.now() + Math.max(4, sec) * 1000;
  return null;
}

// v: { ver: oyuncu id }
export function answer(g, id, v) {
  const m = g.m;
  if (g.phase !== "bomba" || !v || v.ver === undefined || m.boom) return null;
  if (id !== m.holder) return { reply: { t: "bilgi", m: "Bomba sende değil." } };
  const to = Number(v.ver);
  if (!g.players.includes(to) || to === id) return null;
  if (to === m.from && Date.now() - m.at < GIVE_BACK_MS) {
    return { reply: { t: "bilgi", m: "Hemen geri veremezsin." } };
  }
  m.holder = to;
  m.from = id;
  m.at = Date.now();
  m.gives += 1;
  return {
    reply: { t: "olay", task: "c4", tur: "verdin", kime: to },
    broadcast: { t: "olay", task: "c4", tur: "verdi", kimden: id, kime: to },
  };
}

export function onWake(g) {
  const m = g.m;
  if (g.phase !== "bomba") return null;
  if (m.boom) return { finish: true }; // patlama görüldü, şimdi sonuç
  m.boom = m.holder;
  m.wake = Date.now() + 3200; // herkes patlamayı görsün, sonra sonuç
  return { broadcast: { t: "olay", task: "c4", tur: "patlama", kim: m.holder } };
}

export function resolve(g) {
  const m = g.m;
  if (!m.boom) m.boom = m.holder; // süre bittiyse yine de patlar
  const priv = {};
  for (const id of g.players) {
    priv[id] = id === m.boom
      ? { delta: -2, msg: "Bomba elinde patladı!" }
      : { delta: 1, msg: "Patlamadan kurtuldun!" };
  }
  return { public: { patlayan: m.boom, patlayan_ad: g.names[m.boom] || "?", verilen: m.gives }, private: priv };
}

export function leave(g, id) {
  const m = g.m;
  // elinde patlamıştı (patlama ile sonuç arasındaki 3,2 sn'de çıktı): cezası kaybolmasın, puanına yazılır
  // (resolve yalnız kalanlara puan verir; oyun sürüyorsa tura da sayılır: game.js base farkı)
  if (m.boom === id && !m.cezaYazildi && g.score[id] !== undefined) {
    g.score[id] -= 2;
    m.cezaYazildi = true;
  }
  if (m.holder === id && !m.boom && g.players.length) {
    m.holder = pick(g.players);
    m.from = 0;
  }
  return g.players.length < 2;
}
