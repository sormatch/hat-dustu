// Mahkum İkilemi birim testleri:  cd server && node test/ikilem_test.mjs
// Puanlama, eşleştirme (tekrar etmeyen eş, tek sayı -> üçlü, insan-bot karışımı), seçim/açılış akışı,
// oyuncu ayrılması ve botların kararları.
import * as G from "../src/game.js";
import * as I from "../src/modes/ikilem.js";
import * as Bots from "../src/bots.js";

let ok = 0;
let hata = 0;
function bak(ad, kosul) {
  if (kosul) ok++;
  else {
    hata++;
    console.log("HATA:", ad);
  }
}
const esit = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// ---- puanlama (klasik tablo + üçlü)
{
  const p = (c) => Object.fromEntries(Object.entries(I.puanla(c)).map(([k, v]) => [k, v.delta]));
  bak("ikisi sus +2/+2", esit(p({ 1: "sus", 2: "sus" }), { 1: 2, 2: 2 }));
  bak("biri öt +3/-1", esit(p({ 1: "ot", 2: "sus" }), { 1: 3, 2: -1 }));
  bak("ikisi öt 0/0", esit(p({ 1: "ot", 2: "ot" }), { 1: 0, 2: 0 }));
  bak("üçlü hepsi sus", esit(p({ 1: "sus", 2: "sus", 3: "sus" }), { 1: 2, 2: 2, 3: 2 }));
  bak("üçlü tek öten", esit(p({ 1: "ot", 2: "sus", 3: "sus" }), { 1: 3, 2: -1, 3: -1 }));
  bak("üçlü iki öten", esit(p({ 1: "ot", 2: "ot", 3: "sus" }), { 1: 0, 2: 0, 3: -1 }));
  bak("yalnız kalan 0", esit(p({ 1: "ot" }), { 1: 0 }));
  const s = I.puanla({ 1: "ot", 2: "sus" });
  bak("sonuç adları", s[1].sonuc === "sattin" && s[2].sonuc === "satildin");
}

// ---- eşleştirme
for (const n of [2, 3, 4, 5, 6, 7, 8]) {
  const ids = Array.from({ length: n }, (_, i) => i + 1);
  for (let r = 0; r < 30; r++) {
    const gr = I.eslestir(ids, new Set(), []);
    const hepsi = gr.flat().sort((a, b) => a - b);
    bak(`n=${n}: herkes tam bir grupta`, esit(hepsi, ids));
    bak(`n=${n}: gruplar 2 ya da 3 kişi`, gr.every((g) => g.length === 2 || g.length === 3));
    bak(`n=${n}: en fazla bir üçlü (tekse)`, gr.filter((g) => g.length === 3).length === n % 2);
  }
}
// her turda farklı eş: 4, 6, 8 kişide 3 tur boyunca hiç tekrar yok
for (const n of [4, 6, 8]) {
  const ids = Array.from({ length: n }, (_, i) => i + 1);
  for (let r = 0; r < 20; r++) {
    const past = new Set();
    let tekrar = 0;
    for (let t = 0; t < 3; t++) {
      for (const gr of I.eslestir(ids, past, [])) {
        const k = gr[0] < gr[1] ? gr[0] + "-" + gr[1] : gr[1] + "-" + gr[0];
        if (past.has(k)) tekrar++;
        past.add(k);
      }
    }
    bak(`n=${n}: 3 turda eş tekrarı yok`, tekrar === 0);
  }
}
// 2 insan + 2 bot: insanlar birbiriyle eşleşir (ilk tur)
{
  let iyi = 0;
  for (let r = 0; r < 30; r++) {
    const gr = I.eslestir([1, 2, 3, 4], new Set(), [3, 4]);
    if (gr.some((g) => g.includes(1) && g.includes(2))) iyi++;
  }
  bak("iki insan birbiriyle eşleşir", iyi === 30);
}

// ---- tam akış: game.js üzerinden
function oyun(n, bots = []) {
  const players = Array.from({ length: n }, (_, i) => ({ id: i + 1, name: "P" + (i + 1), cell: i }));
  const g = G.newGame(players, 1, ["ikilem"]);
  g.bots = bots;
  G.startNext(g);
  return g;
}
function asamaya(g, ph) {
  while (g.phase !== ph) {
    const nx = G.nextPhase(g);
    if (!nx) throw new Error("aşama yok: " + ph);
    g.phase = nx;
    const r = G.onPhase(g, nx);
    if (r && r.advance && g.phase === nx) continue;
  }
}
{
  const g = oyun(4);
  bak("4 kişi: 3 tur", g.m.turlar === 3 && G.MODES.ikilem.phases(g).length === 10);
  bak("ilk aşama anons", g.phase === "anons");
  bak("herkesin gizli eşi var", g.players.every((id) => g.secret[id] && g.secret[id].es.length === 1));
  // tur 1: seçimler
  asamaya(g, "pazarlik1");
  const gr = g.m.groups[0];
  const [a, b] = gr[0];
  const [c, d] = gr[1];
  bak("pazarlıkta seçim kabul", G.answer(g, a, { secim: "ot" }) !== null);
  bak("geçersiz seçim reddedilir", G.answer(g, b, { secim: "belki" }) === null);
  G.answer(g, b, { secim: "sus" });
  G.answer(g, c, { secim: "sus" });
  const son = G.answer(g, d, { secim: "sus" });
  bak("herkes seçince ilerler", son.advance === true);
  asamaya(g, "acilis1");
  bak("açılışta puanlar işlendi", g.m.pts[a] === 3 && g.m.pts[b] === -1 && g.m.pts[c] === 2 && g.m.pts[d] === 2);
  bak("tur sonucu kaydedildi", g.m.results.length === 1);
}
{
  // açılış puanları: ilk tur
  const g = oyun(4);
  g.phase = "pazarlik1";
  const [[a, b], [c, d]] = g.m.groups[0];
  G.answer(g, a, { secim: "ot" });
  G.answer(g, b, { secim: "sus" });
  G.answer(g, c, { secim: "ot" });
  // d seçmedi: susmuş sayılır
  g.phase = "acilis1";
  const r = G.onPhase(g, "acilis1");
  bak("öten +3", g.m.pts[a] === 3 && g.m.pts[c] === 3);
  bak("susan -1", g.m.pts[b] === -1 && g.m.pts[d] === -1);
  bak("seçmeyen 'sus' görünür", r.privates[d].grup.find((s) => s.id === d).secim === "sus");
  bak("öten 'sattin'", r.privates[a].sonuc === "sattin" && r.privates[b].sonuc === "satildin");
  bak("açılış sadece kendi grubunu gösterir", r.privates[a].grup.length === 2 && r.privates[a].grup.every((s) => s.id === a || s.id === b));
  // tur 2: yeni eşler, öncekiyle aynı değil
  g.phase = "pazarlik2";
  const r2 = G.onPhase(g, "pazarlik2");
  const ayni = g.m.groups[1].some((gr) => (gr.includes(a) && gr.includes(b)) || (gr.includes(c) && gr.includes(d)));
  bak("2. turda farklı eş", !ayni);
  bak("eşleşme olayı herkese", Object.keys(r2.privates).length === 4 && r2.privates[a].tur === "eslesme");
  // tur 2-3 boş geç (herkes susar)
  g.phase = "acilis2";
  G.onPhase(g, "acilis2");
  g.phase = "pazarlik3";
  G.onPhase(g, "pazarlik3");
  g.phase = "acilis3";
  G.onPhase(g, "acilis3");
  const res = G.resolve(g);
  bak("sonuç: herkes için özel", g.players.every((id) => res.private[id] && Array.isArray(res.private[id].turlar) && res.private[id].turlar.length === 3));
  bak("toplam puan: öten a = 3+2+2", res.private[a].delta === 7);
  bak("puan sonuç mesajında yok", !("delta" in (res.public || {})));
}
{
  // tek sayı: 5 kişi -> bir üçlü
  const g = oyun(5);
  bak("5 kişi: bir üçlü", g.m.groups[0].some((gr) => gr.length === 3));
  bak("üçlüdekinin iki eşi var", g.players.some((id) => g.secret[id].es.length === 2));
}
{
  // 3 kişi: 2 tur, hep üçlü
  const g = oyun(3);
  bak("3 kişi: 2 tur", g.m.turlar === 2 && G.MODES.ikilem.phases(g).length === 7);
}
{
  // oyuncu ayrılması: eşi yalnız kalır (0, "yalniz"); 2'den az kalınca iptal
  const g = oyun(4);
  g.phase = "pazarlik1";
  const [[a, b]] = g.m.groups[0];
  G.answer(g, a, { secim: "ot" });
  const iptal = G.removePlayer(g, a);
  bak("ayrılma oyunu iptal etmez (3 kişi kaldı)", iptal === false);
  bak("ayrılanın seçimi silinir", !(a in g.m.picks[0]));
  g.phase = "acilis1";
  const r = G.onPhase(g, "acilis1");
  bak("eşi yalnız: 0 ve 'yalniz'", r.privates[b].sonuc === "yalniz" && (g.m.pts[b] || 0) === 0);
  bak("ayrılana mesaj gitmez", !(a in r.privates));
  // sonraki turda ayrılan eşleşmez
  g.phase = "pazarlik2";
  G.onPhase(g, "pazarlik2");
  bak("ayrılan yeni turda yok", !g.m.groups[1].flat().includes(a));
  G.removePlayer(g, b);
  bak("2'den az kalınca iptal", G.removePlayer(g, g.players[0]) === true);
}
{
  // botlar: plan + not, bot kararları, insan-bot eşinde not gider
  const g = oyun(4, [3, 4]);
  bak("botların kişiliği var", g.m.pers[3] && g.m.pers[4]);
  bak("botların planı var", g.m.plan[0][3] && ["sus", "ot"].includes(g.m.plan[0][3].secim));
  // 1 insan + 3 bot: insanın eşi bot, notu var
  const h = oyun(4, [2, 3, 4]);
  const es = h.secret[1].es[0];
  bak("bot eşin notu", es.bot === true && ["sus", "ot"].includes(es.not));
  // bot kararları zamanı gelince
  h.phase = "pazarlik1";
  const t0 = Date.now();
  Bots.plan(h, t0);
  const acts = Bots.due(h, t0 + 60000);
  bak("3 bot seçti", acts.length === 3 && acts.every(([, v]) => v.secim === "sus" || v.secim === "ot"));
  for (const [id, v] of acts) G.answer(h, id, v);
  bak("bot kararı plana uygun", acts.every(([id, v]) => h.m.plan[0][id].secim === v.secim));
  // kişilik istatistiği: sadık çoğunlukla susar, hain çoğunlukla öter
  let sadikSus = 0;
  let hainSus = 0;
  for (let i = 0; i < 400; i++) {
    const x = oyun(4, [2, 3, 4]);
    x.m.pers = { 2: "sadik", 3: "hain", 4: "sadik" };
    x.phase = "pazarlik2";
    G.onPhase(x, "pazarlik2");
    if (x.m.plan[1][2].secim === "sus") sadikSus++;
    if (x.m.plan[1][3].secim === "sus") hainSus++;
  }
  bak(`sadık çoğunlukla susar (${sadikSus}/400)`, sadikSus > 280);
  bak(`hain çoğunlukla öter (${hainSus}/400 sus)`, hainSus < 160);
}
{
  // seçim aşamasına girerken herkes seçmişse doğrudan açılış
  const g = oyun(4);
  g.phase = "pazarlik1";
  for (const id of g.players) G.answer(g, id, { secim: "sus" });
  g.phase = "secim1";
  const r = G.onPhase(g, "secim1");
  bak("herkes seçmişse seçim atlanır", r && r.advance === true);
  bak("açılışta seçim kabul edilmez", (g.phase = "acilis1") && G.answer(g, 1, { secim: "ot" }) === null);
}

console.log(`ikilem: ${ok} doğru, ${hata} hata`);
process.exit(hata ? 1 : 0);
