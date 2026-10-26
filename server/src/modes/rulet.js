// RUS RULETİ: silah bir kişide. Patlama şansı %15 ile başlar.
//   Kendine sıkıp patlamazsa silah sende kalır, şans artar: %15 → %35 → %50 → %100.
//   %100'de kendine sıkamazsın: istediğin kişiyi vurursun.
//   Başkasına doğrultursan aynı şansla sıkılır; patlamazsa silah o kişiye AYNI şansla geçer,
//   patlarsa (vurduysan) silah sende kalır ve şans %15'e döner.
//   Ölen -1, vuran +1. Son kalan +3. Sırası gelen 15 sn içinde karar vermezse tetik kendine çekilir.

export const title = "RUS RULETİ";
export const rule = "Tetiği kendine çek ya da birine doğrult. Son kalan kazanır!";
export const phases = ["anons", "oyun"];
export const durations = { anons: 10, oyun: 420 };
export const hidden = true; // puanlar maç sonuna kadar gizli (kullanıcı kuralı)
export const min = 2;
export const CHANCES = [15, 35, 50, 100];
const TURN = 15; // sn
const ANIM = 2600; // ms: istemcide tambur dönüp tetik çekilirken bekleme

const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];

function turnMs(g) {
  return Math.max(3, Math.round(TURN * g.speed)) * 1000;
}

export function start(g) {
  g.m = { alive: g.players.slice(), holder: pick(g.players), stage: 0, pts: {}, kills: {}, dead: [], ready: 0, wake: 0, last: null };
}

function add(m, id, d) {
  m.pts[id] = (m.pts[id] || 0) + d;
}

export function stateExtra(g) {
  const m = g.m;
  return { sira: m.holder, sans: CHANCES[m.stage], asama: m.stage, hayatta: m.alive, olenler: m.dead, son: m.last, sure: m.wake ? Math.max(0, Math.round((m.wake - Date.now()) / 1000)) : 0 };
}

export function onPhase(g, phase) {
  if (phase !== "oyun") return null;
  g.m.wake = Date.now() + turnMs(g);
  return { broadcast: { t: "olay", task: "rulet", tur: "sira", sira: g.m.holder, sans: CHANCES[g.m.stage], sure: Math.round(turnMs(g) / 1000) } };
}

function passRandom(m, except) {
  const pool = m.alive.filter((x) => x !== except);
  return pool.length ? pick(pool) : m.alive[0];
}

function shoot(g, shooter, target, timeout) {
  const m = g.m;
  const chance = CHANCES[m.stage];
  const fired = chance >= 100 || Math.random() * 100 < chance;
  let dead = 0;
  if (target === shooter) {
    if (fired) {
      dead = shooter;
    } else {
      m.stage = Math.min(CHANCES.length - 1, m.stage + 1);
    }
  } else if (fired) {
    dead = target;
    add(m, shooter, 1);
    m.kills[shooter] = (m.kills[shooter] || 0) + 1;
  } else {
    m.holder = target; // patlamadı: silah ona aynı şansla geçer
  }
  if (dead) {
    add(m, dead, -1);
    m.alive = m.alive.filter((x) => x !== dead);
    m.dead.push(dead);
    m.stage = 0;
    // kendini vurduysa silah rastgele birine geçer; birini vurduysa silah atanda kalır
    m.holder = dead === shooter ? passRandom(m, 0) : shooter;
  }
  const over = m.alive.length <= 1;
  m.ready = Date.now() + ANIM;
  m.wake = over ? 0 : Date.now() + ANIM + turnMs(g);
  m.last = { atan: shooter, hedef: target, patladi: fired, olen: dead, sans: chance, zaman: !!timeout };
  const ev = {
    t: "olay", task: "rulet", tur: "atis", atan: shooter, hedef: target, patladi: fired, olen: dead, sans: chance, zaman: !!timeout,
    sira: m.holder, yeni_sans: CHANCES[m.stage], hayatta: m.alive, sure: Math.round(turnMs(g) / 1000),
  };
  if (over) {
    if (m.alive.length === 1) add(m, m.alive[0], 3);
    // son atışın canlandırması bitsin, sonra sonuç
    m.endAt = Date.now() + ANIM + 1500;
    m.wake = m.endAt;
  }
  return { broadcast: ev };
}

// v: { atis: "kendi" | oyuncu id }
export function answer(g, id, v) {
  const m = g.m;
  if (g.phase !== "oyun" || !v || v.atis === undefined || m.endAt) return null;
  if (id !== m.holder) return { reply: { t: "bilgi", m: "Silah sende değil." } };
  if (Date.now() < m.ready) return null;
  const target = v.atis === "kendi" ? id : Number(v.atis);
  if (target === id && CHANCES[m.stage] >= 100) return { reply: { t: "bilgi", m: "Şans %100: birini seçmek zorundasın!" } };
  if (target !== id && !m.alive.includes(target)) return null;
  return shoot(g, id, target, false);
}

// sıra süresi doldu (tetik kendine çekilir; %100'de rastgele birine) ya da oyun bitti
export function onWake(g) {
  const m = g.m;
  if (m.endAt) return { finish: true };
  if (g.phase !== "oyun" || !m.alive.includes(m.holder)) return null;
  const target = CHANCES[m.stage] >= 100 ? passRandom(m, m.holder) : m.holder;
  return shoot(g, m.holder, target, true);
}

export function resolve(g) {
  const m = g.m;
  const priv = {};
  const survivors = m.alive.filter((x) => g.players.includes(x));
  // süre bittiyse hayatta kalanlar +1
  if (survivors.length > 1) for (const id of survivors) add(m, id, 1);
  for (const id of g.players) {
    const kills = m.kills[id] || 0;
    g.hits[id] = (g.hits[id] || 0) + kills;
    const alive = m.alive.includes(id);
    let msg = alive ? (survivors.length === 1 ? "Son kalan sensin!" : "Hayatta kaldın.") : "Vuruldun.";
    if (kills) msg += ` ${kills} kişiyi vurdun.`;
    priv[id] = { delta: m.pts[id] || 0, msg };
  }
  return {
    public: { kazanan: survivors.length === 1 ? survivors[0] : 0, kazanan_ad: survivors.length === 1 ? g.names[survivors[0]] : "", hayatta: survivors, olenler: m.dead },
    private: priv,
  };
}

export function leave(g, id) {
  const m = g.m;
  m.alive = m.alive.filter((x) => x !== id);
  if (m.holder === id && m.alive.length) {
    m.holder = pick(m.alive);
    m.stage = 0;
    m.ready = Date.now() + 500;
    m.wake = Date.now() + turnMs(g);
  }
  if (m.alive.length <= 1 && !m.endAt) {
    if (m.alive.length === 1) add(m, m.alive[0], 3);
    m.endAt = Date.now() + 1500;
    m.wake = m.endAt;
  }
  return false;
}
