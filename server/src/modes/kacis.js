// BÜYÜK KAÇIŞ: maçın son oyunu. Herkes kilitli hücresinde başlar. Hücrelerde gizli yerlerde malzemeler var;
// kaçış defterindeki tariflerle alet yapılır. Çakıyla klozetin 4 vidası sökülür, klozet çekilir, altındaki toprak
// kaşıkla (yavaş) ya da kürekle (hızlı) kazılır. Yer altı tünelleri ortak: başkasının tüneline girilir, açık
// klozetinden onun hücresine çıkılabilir. Hapishanenin beton temeli yalnız eski demir ızgaradan (maymuncukla) ya da
// gevşek tuğladan (kürekle, yavaş) geçilir; yerleri gizli, defterlerdeki ipuçlarına dağılmış. Dış tel örgünün
// ötesinde yukarı kazan kaçar. Ara ara SAYIM: 30 sn içinde kendi hücrende ve klozetin kapalı olmalı; değilse
// aletler toplanır, klozet yeniden vidalanır. Tünelde uzaktaysan: yatağına KUKLA yatır ve klozeti tünelden
// üstüne çek (kapat); gardiyan kuklayı çoğu zaman yer (%25 fark eder). Puan kaçış sırasına göre, kaçamayan 0.
//
// Izgara: 1 m'lik kareler (gx = floor(x), gz = floor(z)), dünya koordinatı. Hücreler x -2.1..2.1, z = (k-3.5)*6.6
// (main.gd); yer altı x -24..2 arası. İstemci kacis_ui.gd aynı sabitleri kullanır (değiştirirsen birlikte değiştir).

import { metin } from "../metin.js";

export const title = "BÜYÜK KAÇIŞ";
export const rule = "Alet yap, kaz, kaç. Sayımda hücrende ol.";
export const phases = ["anons", "kacis"];
export const durations = { anons: 14, kacis: 420 };
export const hidden = true;
export const min = 1;
export const surum = 3; // istemci sürümü 3 ve üstü olmayan varsa seçilmez
export const final = true; // "Tüm oyunlar" maçında hep son oyun (game.js)

export const HUCRE_ARA = 6.6;
export const hucreZ = (k) => (k - 3.5) * HUCRE_ARA;
export const KLOZET = [1.5, -2.54]; // klozet gövdesinin hücreye göre yeri (yerel x, z; cell.gd KLOZET_POS + 0.2 z)
export const SINIR = { x0: -24, x1: 1, z0: -27, z1: 26 }; // kazılabilir ızgara (gx, gz dahil)
export const TEMEL_X = -9; // hapishane temeli (beton): bu sütun kazılamaz (ızgara / tuğla hariç)
export const CIT_X = -19; // dış tel örgü: bu sütun ve batısında yukarı kazılır
export const YUKARI = 3; // yüzeye çıkmak için kaç kazı
export const SURE = { kasik: 6500, kurek: 2600, tugla: 9000, yukari_kasik: 7000, yukari_kurek: 3000, vida: 1100, ara: 900, kukla: 2500 };
export const PUAN = [12, 9, 7, 5, 4, 3, 2, 2];
// hücredeki gizli yerler (istemci kacis_ui.gd'de her birinin 3B yeri ve görünüşü)
export const YERLER = ["yatak", "yastik", "kitaplik", "poster", "havalandirma", "tugla", "lavabo", "koltuk", "dolap", "bilgisayar"];
export const ESYALAR = ["caki", "kasik", "tahta", "bant", "pil", "ampul", "tel", "catal"];
export const TARIFLER = {
  kurek: ["kasik", "tahta", "bant"],
  fener: ["pil", "ampul", "tel"],
  maymuncuk: ["tel", "catal"],
};
const ENVANTER_MAX = 8;
const SAYIM_UYARI = 30000;
export const KUKLA_FARK = 0.25; // gardiyanın kuklayı fark etme olasılığı (sen hücrende değilken)
export const sans = { r: Math.random }; // testte değiştirilir
const SAYIM_ILK = 75000;
const CEZA = 12000; // sayımda yakalanan bu kadar ms hiçbir şey yapamaz
export const KORIDOR = -2; // "nerede": hücrede de yer altında da değil (koridor; sayımda hücrede değil sayılır)
const YER_ALTI_H = -0.5; // bu yükseklikten aşağısı yer altı (tünel tabanı -2.35; main.gd de -0.5 altında "h" yollar)
const VER_MESAFE = 2.5; // eşya vermek için iki oyuncu en fazla bu kadar uzakta (m)

// Sunucunun bildiği konumdan yer: -1 yer altı, 0..7 hücre (x < 2.15, z'den), KORIDOR (geri kalan her yer)
export function yerHesap(p, h) {
  if (typeof h === "number" && h < YER_ALTI_H) return -1;
  if (p[0] < 2.15) {
    const c = Math.round(p[1] / HUCRE_ARA + 3.5);
    if (c >= 0 && c < 8) return c;
  }
  return KORIDOR;
}

const k2 = (x, z) => x + "," + z;

// tohumlu rastgele (sunucu ve testte aynı harita)
function rasgele(tohum) {
  let s = tohum >>> 0 || 1;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
}

export function klozetHucre(cell) {
  return [Math.floor(KLOZET[0]), Math.floor(hucreZ(cell) + KLOZET[1])];
}

// Harita: kayalar, temeldeki ızgaralar ve gevşek tuğla (tohumdan; istemciye "harita" olarak gider)
export function harita(tohum, kullanilan) {
  const r = rasgele(tohum);
  // ızgaralar ve tuğla, hücrelerin hizasında (ipucu "3 numaralı hücrenin hizası" diye verilebilsin)
  const hiza = [];
  for (let k = 0; k < 8; k++) hiza.push(Math.floor(hucreZ(k)));
  const sec = () => hiza.splice(Math.floor(r() * hiza.length), 1)[0];
  const izgara = [sec(), sec()];
  const tugla = [sec()];
  const kaya = new Set();
  const yasak = new Set((kullanilan || []).map((c) => k2(...klozetHucre(c))));
  for (let i = 0; i < 70; i++) {
    const x = -2 - Math.floor(r() * 16); // -2 .. -17
    const z = SINIR.z0 + Math.floor(r() * (SINIR.z1 - SINIR.z0 + 1));
    if (x === TEMEL_X) continue;
    // kaya kümeleri (1-3 kare)
    const n = 1 + Math.floor(r() * 3);
    for (let j = 0; j < n; j++) {
      const kx = x + (j === 1 ? 1 : 0);
      const kz = z + (j === 2 ? 1 : 0);
      if (kx === TEMEL_X || kx > SINIR.x1 || yasak.has(k2(kx, kz))) continue;
      kaya.add(k2(kx, kz));
    }
  }
  return { izgara, tugla, kaya: [...kaya] };
}

export function start(g) {
  const tohum = Math.floor(Math.random() * 2 ** 31);
  const insanlar = g.players.filter((id) => !(g.bots || []).includes(id));
  const kullanilan = g.players.map((id) => g.cells[id]);
  const h = harita(tohum, kullanilan);
  const r = rasgele(tohum ^ 0x5bd1e995);
  const m = {
    tohum, harita: h, kaya: new Set(h.kaya),
    kazilan: {}, // "gx,gz" -> kazan id (klozet kuyuları dahil)
    yukari: {}, // id -> kaç kez yukarı kazdı (dış alanda)
    acik_izgara: {}, // "gx,gz" -> true (maymuncukla açılan)
    oyuncu: {}, // id -> { env: [], vida: 0, klozet: false, kukla: false, nerede: hücre | -1 (yer altı) | KORIDOR, son: ms, ceza: ms,
    //              kacti: sira, yakalanma: n, pos: [x, z], h: yükseklik } (nerede ve pos sunucunun bildiği konumdan: onKonum)
    yer: {}, // hücre -> { yer: esya }
    kacan: [], // kaçış sırası
    ipucu: {}, // id -> ipucu
    sayimlar: 0, q: [], wake: 0, bitis: 0,
  };
  for (const id of g.players) m.oyuncu[id] = { env: [], vida: 0, klozet: false, kukla: false, nerede: g.cells[id], son: 0, ceza: 0, kacti: 0, yakalanma: 0 };
  // gizli yerler: her insanın hücresinde bir çakı ve bir kaşık; kalan malzemeler insan hücrelerine dağılır
  const hucreler = insanlar.map((id) => g.cells[id]);
  for (const c of hucreler) m.yer[c] = {};
  const bosYer = (c) => {
    const bos = YERLER.filter((y) => !m.yer[c][y]);
    return bos[Math.floor(r() * bos.length)];
  };
  for (const c of hucreler) {
    m.yer[c][bosYer(c)] = "caki";
    m.yer[c][bosYer(c)] = "kasik";
  }
  // her iki kişiye bir takım: tahta, bant, pil, ampul, tel x2, çatal (yalnız oynayan da tamamlayabilsin diye en az bir takım)
  const takim = Math.max(1, Math.ceil(hucreler.length / 2));
  const havuz = [];
  for (let i = 0; i < takim; i++) havuz.push("tahta", "bant", "pil", "ampul", "tel", "tel", "catal");
  for (const e of havuz) {
    // boş yeri olan rastgele bir hücre
    const adaylar = hucreler.filter((c) => YERLER.some((y) => !m.yer[c][y]));
    if (!adaylar.length) break;
    const c = adaylar[Math.floor(r() * adaylar.length)];
    m.yer[c][bosYer(c)] = e;
  }
  // defter ipuçları: herkese bir tane (ızgara / tuğla nerede), sırayla dağıtılır
  const ipuclari = [
    { tur: "izgara", z: h.izgara[0] }, { tur: "izgara", z: h.izgara[1] }, { tur: "tugla", z: h.tugla[0] },
  ];
  insanlar.forEach((id, i) => (m.ipucu[id] = ipuclari[i % ipuclari.length]));
  // bot kaçışları: rastgele bir anda (bazıları kaçamaz)
  for (const id of g.bots || []) {
    if (Math.random() < 0.7) m.q.push({ at: 0, gecikme: 150000 + Math.random() * 240000, tur: "bot_kac", id });
  }
  g.m = m;
  // başlangıçta herkese kendi defter ipucu ve (boş) envanteri: "gizli" mesajı
  for (const id of g.players) g.secret[id] = secret(g, id);
}

// hangi ızgara karesinin içeriği: "kaya" | "temel" | "izgara" | "tugla" | "" (toprak)
export function kare(m, x, z) {
  if (x === TEMEL_X) {
    if (m.harita.izgara.includes(z)) return m.acik_izgara[k2(x, z)] ? "" : "izgara";
    if (m.harita.tugla.includes(z)) return "tugla";
    return "temel";
  }
  if (m.kaya.has(k2(x, z))) return "kaya";
  return "";
}

const sinirda = (x, z) => x >= SINIR.x0 && x <= SINIR.x1 && z >= SINIR.z0 && z <= SINIR.z1;

export function stateExtra(g) {
  const m = g.m;
  return {
    tohum: m.tohum, harita: m.harita, kazilan: Object.keys(m.kazilan), acik_izgara: Object.keys(m.acik_izgara),
    kacan: m.kacan, klozet: Object.fromEntries(Object.entries(m.oyuncu).map(([id, o]) => [id, o.klozet])),
    kukla: Object.keys(m.oyuncu).filter((id) => m.oyuncu[id].kukla).map(Number), fener: fenerliler(g),
    sayim: m.sayim_at ? Math.max(0, m.sayim_at - Date.now()) : -1,
  };
}

// Herkese kendi envanteri, hücresinin durumu ve defter ipucu
export function secret(g, id) {
  const m = g.m;
  const o = m.oyuncu[id];
  if (!o) return null;
  return { env: o.env, vida: o.vida, klozet: o.klozet, ipucu: m.ipucu[id] || null, ceza: Math.max(0, o.ceza - Date.now()) };
}

// kafasında fener olanlar (herkes görür: tünelde ışık)
export function fenerliler(g) {
  return Object.keys(g.m.oyuncu).filter((id) => g.m.oyuncu[id].env.includes("fener") && !g.m.oyuncu[id].kacti).map(Number);
}

function fenerYayin(g) {
  return { t: "olay", task: "kacis", tur: "fener", ids: fenerliler(g) };
}

function kuyruk(m, is) {
  m.q.push(is);
  m.q.sort((a, b) => a.at - b.at);
  m.wake = m.q.length ? m.q[0].at : 0;
}

export function onPhase(g, phase) {
  const m = g.m;
  if (phase !== "kacis") return null;
  const now = Date.now();
  // bot kaçışlarının zamanı bu aşamaya göre
  const botlar = m.q.filter((x) => x.tur === "bot_kac");
  m.q = [];
  for (const b of botlar) kuyruk(m, { ...b, at: now + b.gecikme * g.speed });
  kuyruk(m, { at: now + Math.max(8000, (SAYIM_ILK - SAYIM_UYARI) * g.speed), tur: "sayim_uyari" });
  return null;
}

function ozel(id, msg) {
  return { privates: { [id]: msg } };
}

function envDurum(g, id) {
  return { t: "olay", task: "kacis", tur: "durum", ...secret(g, id) };
}

// v: { ara: yer, hucre } | { vida: true } | { klozet: true|false } | { in: true|false } (yer altına inip çıkma; hücre)
//    | { kaz: [gx, gz] } | { yukari: [gx, gz] } | { yap: tarif } | { ver: { kime, esya } }
export function answer(g, id, v) {
  const m = g.m;
  const o = m.oyuncu[id];
  if (!o || g.phase !== "kacis" || !v || typeof v !== "object" || o.kacti) return null;
  const now = Date.now();
  const red = (metn) => ozel(id, { t: "olay", task: "kacis", tur: "red", ...metin("m", metn) });
  if (o.ceza > now) return red("Yakalandın, bekle.");
  // yer: sunucunun bildiği konumdan çıkarılır (onKonum). İstemcinin bildirdiği yer yalnız konumu hiç gelmemişse yedek.
  if (v.nerede !== undefined) {
    if (o.pos) return null;
    const n = Number(v.nerede);
    o.nerede = Number.isInteger(n) && n >= -1 && n < 8 ? n : o.nerede;
    return null;
  }
  if (v.ara !== undefined) {
    const yer = String(v.ara);
    const c = o.nerede;
    if (!YERLER.includes(yer) || c < 0) return null;
    if (now - o.son < SURE.ara * g.speed) return null;
    o.son = now;
    const esya = m.yer[c] && m.yer[c][yer];
    if (!esya) return ozel(id, { t: "olay", task: "kacis", tur: "bos", yer, hucre: c });
    if (o.env.length >= ENVANTER_MAX) return red("Ceplerin dolu.");
    delete m.yer[c][yer];
    o.env.push(esya);
    return { privates: { [id]: { t: "olay", task: "kacis", tur: "buldu", yer, hucre: c, esya, ...secret(g, id) } } };
  }
  if (v.vida) {
    if (o.nerede !== g.cells[id]) return null;
    if (!o.env.includes("caki")) return red("Çakı lazım.");
    if (o.vida >= 4) return null;
    if (now - o.son < SURE.vida * g.speed) return null;
    o.son = now;
    o.vida += 1;
    return { reply: envDurum(g, id), broadcast: { t: "olay", task: "kacis", tur: "vida", id, n: o.vida } };
  }
  if (v.kukla !== undefined) {
    const on = !!v.kukla;
    if (o.nerede !== g.cells[id]) return null;
    if (o.kukla === on) return null;
    if (on && now - o.son < SURE.kukla * g.speed * 0.85) return null;
    o.son = now;
    o.kukla = on;
    return { reply: envDurum(g, id), broadcast: { t: "olay", task: "kacis", tur: "kukla", id, hucre: g.cells[id], on } };
  }
  if (v.klozet !== undefined) {
    const ac = !!v.klozet;
    if (ac && o.vida < 4) return red("Önce vidaları sök.");
    if (o.klozet === ac) return null;
    const kk = klozetHucre(g.cells[id]);
    // kapatmak (üstüne çekmek) yalnız kendi hücrende ya da yer altında kendi kuyunun karesinde (başkası uzaktan kapatamasın,
    // sayımdan kaçmak için tünelin öbür ucundan da kapatılamasın)
    if (!ac && o.nerede !== g.cells[id] && !(o.nerede === -1 && kuyuda(o, kk))) return null;
    o.klozet = ac;
    if (ac && !m.kazilan[k2(...kk)]) m.kazilan[k2(...kk)] = id; // klozetin altı: tünelin başı
    return { reply: envDurum(g, id), broadcast: { t: "olay", task: "kacis", tur: "klozet", id, hucre: g.cells[id], acik: ac, kare: kk } };
  }
  if (v.kaz !== undefined) {
    const x = Number(v.kaz && v.kaz[0]);
    const z = Number(v.kaz && v.kaz[1]);
    if (!Number.isInteger(x) || !Number.isInteger(z) || !sinirda(x, z) || o.nerede !== -1) return null;
    if (m.kazilan[k2(x, z)]) return null;
    // komşusu kazılmış olmalı
    if (![[1, 0], [-1, 0], [0, 1], [0, -1]].some(([dx, dz]) => m.kazilan[k2(x + dx, z + dz)])) return null;
    const ne = kare(m, x, z);
    const kurek = o.env.includes("kurek");
    if (!kurek && !o.env.includes("kasik")) return red("Kaşık ya da kürek lazım.");
    if (ne === "kaya") return ozel(id, { t: "olay", task: "kacis", tur: "sert", ne, kare: [x, z] });
    if (ne === "temel") return ozel(id, { t: "olay", task: "kacis", tur: "sert", ne, kare: [x, z] });
    if (ne === "izgara") {
      if (!o.env.includes("maymuncuk")) return ozel(id, { t: "olay", task: "kacis", tur: "sert", ne, kare: [x, z] });
      m.acik_izgara[k2(x, z)] = true;
    }
    if (ne === "tugla" && !kurek) return ozel(id, { t: "olay", task: "kacis", tur: "sert", ne, kare: [x, z] });
    const sure = (ne === "tugla" ? SURE.tugla : kurek ? SURE.kurek : SURE.kasik) * g.speed;
    if (now - o.son < sure * 0.85) return null;
    o.son = now;
    m.kazilan[k2(x, z)] = id;
    return { broadcast: { t: "olay", task: "kacis", tur: "kazildi", id, kare: [x, z], ne } };
  }
  if (v.yukari !== undefined) {
    const x = Number(v.yukari && v.yukari[0]);
    const z = Number(v.yukari && v.yukari[1]);
    if (!m.kazilan[k2(x, z)] || x > CIT_X || o.nerede !== -1) return red("Hâlâ örgünün içindesin. İlerle.");
    const kurek = o.env.includes("kurek");
    if (!kurek && !o.env.includes("kasik")) return red("Kaşık ya da kürek lazım.");
    const sure = (kurek ? SURE.yukari_kurek : SURE.yukari_kasik) * g.speed;
    if (now - o.son < sure * 0.85) return null;
    o.son = now;
    m.yukari[id] = (m.yukari[id] || 0) + 1;
    if (m.yukari[id] < YUKARI) return { reply: { t: "olay", task: "kacis", tur: "yukari", n: m.yukari[id] }, broadcast: { t: "olay", task: "kacis", tur: "toprak", kare: [x, z] } };
    return kacti(g, id, [x, z]);
  }
  if (v.yap !== undefined) {
    const t = String(v.yap);
    const tarif = TARIFLER[t];
    if (!tarif) return null;
    const env = o.env.slice();
    for (const p of tarif) {
      const i = env.indexOf(p);
      if (i < 0) return red("Malzemeler eksik.");
      env.splice(i, 1);
    }
    env.push(t);
    o.env = env;
    const r = { reply: { ...envDurum(g, id), yapildi: t } };
    if (t === "fener") r.broadcast = fenerYayin(g);
    return r;
  }
  if (v.ver !== undefined) {
    const kime = Number(v.ver && v.ver.kime);
    const esya = String(v.ver && v.ver.esya);
    const k = m.oyuncu[kime];
    if (!k || kime === id || k.kacti || !o.env.includes(esya) || k.env.length >= ENVANTER_MAX) return null;
    // ikisinin de sunucudaki konumu bilinmeli: aynı katta (ikisi de yer altında ya da üstte) ve VER_MESAFE'den yakın
    if (!yakin(o, k)) return red("Yanına git.");
    o.env.splice(o.env.indexOf(esya), 1);
    k.env.push(esya);
    const r = { reply: envDurum(g, id), others: [{ to: kime, msg: { ...envDurum(g, kime), aldi: esya, kimden: id } }] };
    if (esya === "fener") r.broadcast = fenerYayin(g);
    return r;
  }
  return null;
}

// Yer altında kendi klozet kuyusunun karesinde mi (1 m'lik kare, gecikme için her yönde yarım kare pay)
function kuyuda(o, kk) {
  return !!o.pos && Math.abs(o.pos[0] - (kk[0] + 0.5)) <= 1 && Math.abs(o.pos[1] - (kk[1] + 0.5)) <= 1;
}

// İki oyuncu eşya verebilecek kadar yakın mı (konumları bilinmeli, aynı katta)
function yakin(a, b) {
  if (!a.pos || !b.pos) return false;
  if ((a.nerede === -1) !== (b.nerede === -1)) return false;
  return Math.hypot(a.pos[0] - b.pos[0], a.pos[1] - b.pos[1]) < VER_MESAFE;
}

// Room konum mesajında çağırır (h: yükseklik, yer üstünde 0): oyuncunun yeri (hücre / yer altı / koridor) buradan
// çıkarılır; sayım, arama, vida, kazı ve eşya verme bu yere bakar (istemcinin "nerede" bildirimine güvenilmez)
export function onKonum(g, id, p, h = 0) {
  const o = g.m && g.m.oyuncu[id];
  if (!o || o.kacti) return null;
  o.pos = p;
  o.h = h;
  o.nerede = yerHesap(p, h);
  return null;
}

function kacti(g, id, kare) {
  const m = g.m;
  const o = m.oyuncu[id];
  m.kacan.push(id);
  o.kacti = m.kacan.length;
  // herkes kaçtıysa oyun birkaç saniye sonra biter (kaçış anı görülsün)
  if (bittiMi(g) && !m.bitis) {
    m.bitis = Date.now() + 4000;
    kuyruk(m, { at: m.bitis, tur: "bitir" });
  }
  return { broadcast: { t: "olay", task: "kacis", tur: "kacti", id, sira: o.kacti, kare: kare || null } };
}

// herkes kaçtı (ya da kaçabilecek insan kalmadı) mı?
function bittiMi(g) {
  const m = g.m;
  const insanlar = g.players.filter((id) => !(g.bots || []).includes(id));
  return insanlar.length > 0 && insanlar.every((id) => m.oyuncu[id] && m.oyuncu[id].kacti);
}

function sayim(g, out) {
  const m = g.m;
  const now = Date.now();
  m.sayim_at = 0;
  m.sayimlar += 1;
  const yakalanan = [];
  const kandirdi = []; // kuklası gardiyanı kandıranlar
  let fenerVardi = false;
  for (const id of g.players) {
    const o = m.oyuncu[id];
    if (!o || o.kacti || (g.bots || []).includes(id)) continue;
    let yok = o.nerede !== g.cells[id];
    if (yok && o.kukla && !o.klozet) {
      if (sans.r() >= KUKLA_FARK) {
        kandirdi.push(id);
        yok = false;
      }
    }
    if (yok || o.klozet) {
      if (o.env.includes("fener")) fenerVardi = true;
      o.kukla = false;
      yakalanan.push(id);
      o.yakalanma += 1;
      // aletler toplanır (çakı ve kaşık sende kalır ama vidalar yeniden takılır)
      o.env = o.env.filter((e) => e === "caki" || e === "kasik");
      o.vida = 0;
      o.klozet = false;
      o.nerede = g.cells[id];
      o.ceza = now + CEZA * g.speed;
    }
  }
  out.push({ t: "olay", task: "kacis", tur: "sayim", yakalanan, klozet: yakalanan.map((id) => ({ id, hucre: g.cells[id] })) });
  for (const id of kandirdi) out.push({ to: id, t: "olay", task: "kacis", tur: "kandirdi" });
  if (fenerVardi) out.push(fenerYayin(g));
  for (const id of yakalanan) out.push({ to: id, ...envDurum(g, id) });
  // sonraki sayım: 70-90 sn sonra
  kuyruk(m, { at: now + (55000 + Math.random() * 20000) * g.speed, tur: "sayim_uyari" });
}

export function onWake(g) {
  const m = g.m;
  if (g.phase !== "kacis") return null;
  const now = Date.now();
  const out = [];
  const ozelMesaj = {};
  let bitir = false;
  while (m.q.length && m.q[0].at <= now + 30) {
    const is = m.q.shift();
    if (is.tur === "bitir") bitir = true;
    else if (is.tur === "sayim_uyari") {
      m.sayim_at = now + SAYIM_UYARI * g.speed;
      out.push({ t: "olay", task: "kacis", tur: "sayim_uyari", ms: SAYIM_UYARI * g.speed });
      kuyruk(m, { at: m.sayim_at, tur: "sayim" });
    } else if (is.tur === "sayim") {
      const liste = [];
      sayim(g, liste);
      for (const x of liste) {
        if (x.to) {
          const msg = (({ to, ...rest }) => rest)(x);
          ozelMesaj[x.to] = ozelMesaj[x.to] ? { t: "olay", task: "kacis", tur: "coklu", liste: [ozelMesaj[x.to], msg] } : msg;
        }
        else out.push(x);
      }
    } else if (is.tur === "bot_kac") {
      const o = m.oyuncu[is.id];
      if (o && !o.kacti && g.players.includes(is.id)) {
        const r = kacti(g, is.id, null);
        out.push(r.broadcast);
      }
    }
  }
  if (bittiMi(g) && !m.bitis) {
    m.bitis = now + 4000;
    kuyruk(m, { at: m.bitis, tur: "bitir" });
  }
  m.wake = m.q.length ? m.q[0].at : 0;
  if (bitir) return { finish: true };
  const r = {};
  if (out.length) r.broadcast = out.length === 1 ? out[0] : { t: "olay", task: "kacis", tur: "coklu", liste: out };
  if (Object.keys(ozelMesaj).length) r.privates = ozelMesaj;
  return Object.keys(r).length ? r : null;
}

export function resolve(g) {
  const m = g.m;
  const priv = {};
  for (const id of g.players) {
    const o = m.oyuncu[id];
    const sira = o ? o.kacti : 0;
    const delta = sira ? PUAN[Math.min(sira, PUAN.length) - 1] : 0;
    priv[id] = { delta, ...metin("msg", sira ? ["{0}. kaçan sensin!", [sira]] : "Kaçamadın.") };
  }
  return { public: { kacan: m.kacan, kacan_ad: m.kacan.map((id) => g.names[id] || "?") }, private: priv };
}

export function leave(g, id) {
  const m = g.m;
  if (m && m.oyuncu[id]) m.oyuncu[id].kacti = m.oyuncu[id].kacti || 0;
  return g.players.length < 1;
}
