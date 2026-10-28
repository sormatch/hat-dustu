// KISA DEVRE: ışıklar kesilir; herkesin sigorta kutusunda 4 renkli kablo ve 4 prizli uç var.
// Her prizde bir sembol ve bir numara (1-4, yukarıdan aşağı) var. Senin kutunun şeması BAŞKASININ
// tahtasında yazar; senin tahtanda da başka birinin şeması ve kimin için olduğu ("BORA İÇİN"): onu ara,
// şemayı oku. Şema bazen sembolle ("KIRMIZI >> YILDIZ") bazen numarayla ("MAVİ >> 3 NOLU") yazılır.
// 4 kablo doğru takılınca oyuncu ŞALTERİ kaldırır: kutu o an onarılır.
// 3 hakkın var: yanlış bağlantı bir cam sigortayı patlatır (kablo yerinden fırlar). 3 hata = kutu yanar.
// Puan: kutunu onarırsan +1 (ilk onaran +2), şeman sayesinde onarılırsa sana +1, kutun yanarsa -1.
// Herkes onarırsa ışıklar tamamen geri gelir: herkese +1.

import { metin } from "../metin.js";

export const title = "KISA DEVRE";
export const rule = "Kutunu onar. Şeman başkasının tahtasında; seninkinde de başkasınınki var.";
export const phases = ["anons", "calisma"];
export const durations = { anons: 8, calisma: 150 };
export const hidden = true; // puanlar maç sonuna kadar gizli (kullanıcı kuralı)
export const LIVES = 3;

// Kolay ayırt edilen renkler ve telefonda kolay söylenen semboller
export const COLORS = ["KIRMIZI", "MAVİ", "SARI", "YEŞİL", "MOR", "TURUNCU"];
export const SYMBOLS = ["YILDIZ", "ÜÇGEN", "DAİRE", "KARE"];

const shuffle = (arr) => {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
};

const up = (s) => String(s || "").replace(/i/g, "İ").replace(/ı/g, "I").toLocaleUpperCase("tr-TR");

// Kutu: soldaki 4 kablo (renk), sağdaki 4 priz (sembol, sırası = numarası). Doğru eşleşme gizli: renk -> sembol.
function makeBox() {
  const wires = shuffle(COLORS).slice(0, 4);
  const symbols = shuffle(SYMBOLS);
  const map = {};
  const targets = shuffle(SYMBOLS);
  wires.forEach((w, i) => (map[w] = targets[i]));
  // şemada her kablo için sembol mü numara mı yazılacak (en az birer tane)
  const kinds = shuffle(["S", "N", Math.random() < 0.5 ? "S" : "N", Math.random() < 0.5 ? "S" : "N"]);
  return { wires, symbols, map, kinds, done: {}, lives: LIVES, status: "acik" };
}

// Şema satırları: [renk, "S", sembol] ya da [renk, "N", numara]
export function scheme(b) {
  return b.wires.map((w, i) => (b.kinds[i] === "N" ? [w, "N", b.symbols.indexOf(b.map[w]) + 1] : [w, "S", b.map[w]]));
}

export function boardText(name, b) {
  const rows = scheme(b).map(([w, k, v]) => `${w} >> ${k === "N" ? v + " NOLU" : v}`);
  return `${up(name)} İÇİN\n` + rows.join("\n");
}

export function start(g) {
  const ids = shuffle(g.players);
  const boxes = {};
  for (const id of ids) boxes[id] = makeBox();
  // zincir: herkes bir sonrakinin şemasını tutar (kimse kendi şemasını görmez)
  const holder = {}; // kutu sahibi -> şeması tahtasında olan
  ids.forEach((id, i) => (holder[id] = ids[(i + 1) % ids.length]));
  const boardOf = {}; // tahta sahibi -> şemasını tuttuğu kutunun sahibi
  for (const [owner, h] of Object.entries(holder)) boardOf[h] = Number(owner);
  g.m = { boxes, holder, boardOf, first: 0 };
  for (const id of ids) {
    const b = boxes[id];
    const target = boardOf[id];
    g.secret[id] = {
      kablolar: b.wires,
      semboller: b.symbols,
      adim_sayisi: b.wires.length,
      hak: LIVES,
      tahta: boardText(g.names[target], boxes[target]),
      sema: scheme(boxes[target]),
      yardim: target,
      yardim_ad: g.names[target] || "?",
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
  return counts(g);
}

// Kutu onarıldı (şalter kalktı, ya da süre bitti ama kablolar doğruydu).
// İlk onaran +2, sonrakiler +1; şemayı tahtasında tutana +1.
function repaired(g, id, b, quiet = false) {
  const others = [];
  b.status = "tamir";
  const delta = g.m.first ? 1 : 2;
  if (!g.m.first) g.m.first = id;
  g.score[id] += delta;
  g.hits[id] = (g.hits[id] || 0) + 1;
  const h = g.m.holder[id];
  if (g.players.includes(h) && h !== id) {
    g.score[h] += 1;
    if (!quiet) others.push({ to: h, msg: { t: "devre", olay: "yardim", kim: g.names[id], puan: g.score[h] } });
  }
  const c = counts(g);
  return {
    reply: { t: "devre", olay: "tamir", adim: b.wires.length, adim_sayisi: b.wires.length, hak: b.lives, delta, puan: g.score[id], ilk: delta === 2 },
    others,
    broadcast: { t: "devre_durum", ...c },
    advance: c.onarilan + c.kilitli >= c.toplam,
  };
}

// Kutuya bir işlem: {islem:"bagla", renk, sembol} ya da {islem:"salter"}.
// Dönen: { reply, others: [{to, msg}], broadcast, advance } ya da null
export function answer(g, id, v) {
  if (!v || typeof v !== "object" || g.phase !== "calisma") return null;
  const b = g.m.boxes[id];
  if (!b) return null;
  if (b.status !== "acik") return { reply: { t: "devre", olay: b.status, hak: b.lives, puan: g.score[id] } };
  if (v.islem === "salter") {
    if (Object.keys(b.done).length < b.wires.length) return null; // kablolar bitmeden şalter kalkmaz
    return repaired(g, id, b);
  }
  if (v.islem !== "bagla") return null;
  const renk = String(v.renk || "");
  const sembol = String(v.sembol || "");
  if (!b.wires.includes(renk) || !SYMBOLS.includes(sembol) || b.done[renk]) return null;
  if (Object.values(b.done).includes(sembol)) return null;
  let olay;
  let delta = 0;
  if (b.map[renk] !== sembol) {
    b.lives -= 1;
    if (b.lives <= 0) {
      b.status = "kilit";
      olay = "kilit";
      delta = -1;
      g.score[id] -= 1;
    } else {
      olay = "yanlis";
    }
  } else {
    b.done[renk] = sembol;
    olay = "adim"; // 4. doğru kablodan sonra şalter beklenir (hazir)
  }
  const c = counts(g);
  const adim = Object.keys(b.done).length;
  return {
    reply: { t: "devre", olay, renk, sembol, adim, adim_sayisi: b.wires.length, hak: b.lives, delta, puan: g.score[id], hazir: adim >= b.wires.length },
    others: [],
    broadcast: { t: "devre_durum", ...c },
    advance: c.onarilan + c.kilitli >= c.toplam,
  };
}

// Süre bitti ya da herkes bitirdi. Dönen: { public, private: id -> {delta, msg} } (anlık puanlar zaten işlendi)
export function resolve(g) {
  const m = g.m;
  const priv = {};
  for (const id of g.players) priv[id] = { delta: 0, msg: [] };
  for (const [owner, b] of Object.entries(m.boxes)) {
    const o = Number(owner);
    if (b.status !== "acik" || !priv[o]) continue;
    if (Object.keys(b.done).length >= b.wires.length) {
      repaired(g, o, b, true); // kablolar doğru, şalter kaldırılmamış: yine de onarılmış sayılır (puan içeride işlendi)
    } else {
      b.status = "kilit";
      priv[o].delta -= 1;
      priv[o].msg.push("Kutun onarılmadı.");
    }
  }
  const c = counts(g);
  const all = c.onarilan === c.toplam;
  for (const id of g.players) {
    const b = m.boxes[id];
    if (b && b.status === "tamir") priv[id].msg.unshift(m.first === id ? "İlk onaran sensin." : "Kutunu onardın.");
    if (b && b.status === "kilit" && !priv[id].msg.length) priv[id].msg.push("Kutun yandı.");
    if (all) {
      priv[id].delta += 1;
      priv[id].msg.push("Işıklar tamamen geldi!");
    }
    Object.assign(priv[id], metin("msg", ...(priv[id].msg.length ? priv[id].msg : ["Süre bitti."])));
  }
  return { public: { ...c, hepsi: all, ilk: m.first, ilk_ad: m.first ? g.names[m.first] : "" }, private: priv };
}

// Oyun devam eder; ayrılanın kutusu sayılmaz (silinir). Zincir kopmasın: ayrılanın tahtasındaki şema
// (T'nin şeması) ayrılanın şemasını tutan kişiye (H) geçer; H'nin tahtası yenilenir (g.gizliYenile).
export function leave(g, id) {
  const m = g.m;
  if (!m || !m.boxes) return false;
  const T = m.boardOf[id]; // ayrılanın tahtasında şeması yazan
  const H = m.holder[id]; // ayrılanın şemasını tahtasında tutan
  delete m.boxes[id];
  delete m.holder[id];
  delete m.boardOf[id];
  if (T !== undefined && H !== undefined && T !== id && H !== id && T !== H && m.boxes[T] && g.players.includes(H)) {
    m.holder[T] = H;
    m.boardOf[H] = T;
    if (g.secret[H]) {
      g.secret[H] = {
        ...g.secret[H],
        tahta: boardText(g.names[T], m.boxes[T]),
        sema: scheme(m.boxes[T]),
        yardim: T,
        yardim_ad: g.names[T] || "?",
        yenilendi: true,
      };
      (g.gizliYenile ||= []).push(H);
    }
  }
  return false;
}

// Kalan herkes bitirdi mi (biri ayrılınca beklemeden geçilsin)
export function tamam(g) {
  if (g.phase !== "calisma" || !g.m || !g.m.boxes) return false;
  const c = counts(g);
  return c.toplam > 0 && c.onarilan + c.kilitli >= c.toplam;
}
