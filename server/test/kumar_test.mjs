// Kumarbaz birim testleri:  cd server && node test/kumar_test.mjs
// Puanlama (yakalanan yalan, haksız meydan okuma, en yüksek iddia), varsayılan iddia, akış, ayrılma, botlar.
import * as G from "../src/game.js";
import * as K from "../src/modes/kumar.js";
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

// ---- olasılık
bak("2'den küçük olasılığı 0", K.yalanOlasiligi(2) === 0);
bak("13'ten küçük olasılığı 1", K.yalanOlasiligi(13) === 1);
bak("7'den küçük 15/36", Math.abs(K.yalanOlasiligi(7) - 15 / 36) < 1e-9);

// ---- hesap
{
  // 1: 12 dedi (gerçek 5) -> 2 ve 3 "yalan" dedi: yakalandı. 2: 8 dedi (gerçek 8) -> 4 "yalan" dedi: haklı çıktı.
  // 3: 10 dedi (gerçek 4, kimse demedi) -> yakalanmayan en yüksek: kazanır. 4: 6 dedi (gerçek 6)
  const ids = [1, 2, 3, 4];
  const r = K.hesapla(ids, { 1: 12, 2: 8, 3: 10, 4: 6 }, { 1: 5, 2: 8, 3: 4, 4: 6 }, { 1: 0, 2: 1, 3: 1, 4: 2 });
  bak("yalanı yakalanan -2", r.puan[1] === -2);
  bak("doğru söyleyen meydan okununca +1", r.puan[2] === 1 + 1); // +1 (2'ye yalan dendi, doğru) + 1 (1'e yalan dedi, haklı)
  bak("yakalanmayan blöf kazanır", r.kazananlar.length === 1 && r.kazananlar[0] === 3);
  bak("kazanan +2, doğru meydan +1", r.puan[3] === 2 + 1);
  bak("haksız meydan -1", r.puan[4] === -1);
  bak("satır: yakalandı bilgisi", r.satirlar.find((s) => s.id === 1).yakalandi === true && r.satirlar.find((s) => s.id === 3).yakalandi === false);
}
{
  // eşitlik: iki kişi 9, ikisi de kazanır; kendine meydan sayılmaz
  const r = K.hesapla([1, 2, 3], { 1: 9, 2: 9, 3: 7 }, { 1: 9, 2: 10, 3: 7 }, { 1: 1, 2: 0, 3: 0 });
  bak("eşitlikte ikisi de kazanır", r.kazananlar.length === 2 && r.puan[1] === 2 && r.puan[2] === 2);
  bak("kendine 'yalan' sayılmaz", r.satirlar.find((s) => s.id === 1).meydan.length === 0);
}
{
  // düşük iddia yalan sayılmaz
  const r = K.hesapla([1, 2], { 1: 4, 2: 5 }, { 1: 11, 2: 5 }, { 1: 0, 2: 1 });
  bak("eksik iddia yalan değil", r.puan[1] === 1 && r.puan[2] === -1 + 2);
}

// ---- akış
function oyun(n, bots = []) {
  const players = Array.from({ length: n }, (_, i) => ({ id: i + 1, name: "P" + (i + 1), cell: i }));
  const g = G.newGame(players, 1, ["kumar"]);
  g.bots = bots;
  G.startNext(g);
  return g;
}
{
  const g = oyun(4);
  bak("aşamalar", G.MODES.kumar.phases.length === 10 && g.phase === "anons");
  bak("herkesin iki zarı var", g.players.every((id) => g.secret[id].zar.length === 2 && g.secret[id].zar.every((z) => z >= 1 && z <= 6)));
  g.phase = "zar1";
  bak("geçersiz iddia", G.answer(g, 1, { iddia: 13 }).reply.t === "bilgi");
  bak("iddia kabul", G.answer(g, 1, { iddia: 12 }).reply.ne === "iddia");
  G.answer(g, 2, { iddia: 3 });
  G.answer(g, 3, { iddia: 7 });
  // 4 iddia yazmadı
  g.phase = "meydan1";
  const r = G.onPhase(g, "meydan1");
  const z4 = g.m.dice[0][4];
  bak("yazmayanın iddiası zarı", g.m.claims[0][4] === z4[0] + z4[1]);
  bak("iddialar herkese, büyükten küçüğe", r.broadcast.iddialar[0].iddia >= r.broadcast.iddialar[3].iddia);
  bak("iddialarda zar yok", r.broadcast.iddialar.every((x) => !("zar" in x)));
  bak("kendine meydan okunamaz", G.answer(g, 2, { meydan: 2 }) === null);
  G.answer(g, 2, { meydan: 1 });
  G.answer(g, 3, { meydan: 0 });
  G.answer(g, 4, { meydan: 1 });
  const son = G.answer(g, 1, { meydan: 0 });
  bak("herkes karar verince ilerler", son.advance === true);
  g.phase = "acilis1";
  const a = G.onPhase(g, "acilis1");
  bak("açılışta tüm zarlar", a.broadcast.satirlar.length === 4 && a.broadcast.satirlar.every((s) => Array.isArray(s.zar)));
  const s1 = a.broadcast.satirlar.find((s) => s.id === 1);
  bak("12 iddiası: meydan okuyan 2 kişi", s1.meydan.length === 2);
  // 2. el: yeni zar, özel mesaj
  g.phase = "zar2";
  const z = G.onPhase(g, "zar2");
  bak("yeni elde herkese yeni zar", Object.keys(z.privates).length === 4 && z.privates[1].el === 2);
  g.phase = "meydan2";
  G.onPhase(g, "meydan2");
  g.phase = "acilis2";
  G.onPhase(g, "acilis2");
  g.phase = "zar3";
  G.onPhase(g, "zar3");
  g.phase = "meydan3";
  G.onPhase(g, "meydan3");
  g.phase = "acilis3";
  G.onPhase(g, "acilis3");
  const res = G.resolve(g);
  bak("3 el sonucu", res.public.sonuclar.length === 3);
  bak("herkese mesaj", g.players.every((id) => typeof res.private[id].msg === "string"));
}
{
  // ayrılma: ayrılanın zarı silinir, ona "yalan" diyenin kararı boşa düşer
  const g = oyun(4);
  g.phase = "zar1";
  for (const id of g.players) G.answer(g, id, { iddia: 7 });
  g.phase = "meydan1";
  G.onPhase(g, "meydan1");
  G.answer(g, 2, { meydan: 1 });
  bak("ayrılma iptal etmez", G.removePlayer(g, 1) === false);
  bak("ayrılanın zarı yok", !g.m.dice[0][1]);
  bak("ona meydan boşa düştü", g.m.chal[0][2] === 0);
  g.phase = "acilis1";
  const a = G.onPhase(g, "acilis1");
  bak("açılışta ayrılan yok", !a.broadcast.satirlar.some((s) => s.id === 1));
  bak("ayrılan karar veremez", G.answer(g, 1, { meydan: 2 }) === null);
  G.removePlayer(g, 2);
  bak("tek kişi kalınca iptal", G.removePlayer(g, 3) === true);
}
{
  // botlar
  const g = oyun(5, [2, 3, 4, 5]);
  bak("botların kişiliği", [2, 3, 4, 5].every((id) => g.m.pers[id]));
  g.phase = "zar1";
  const t0 = Date.now();
  Bots.plan(g, t0);
  let acts = Bots.due(g, t0 + 60000);
  bak("4 bot iddia etti", acts.length === 4 && acts.every(([, v]) => v.iddia >= 2 && v.iddia <= 12));
  for (const [id, v] of acts) G.answer(g, id, v);
  bak("bot iddiası zarından küçük değil", [2, 3, 4, 5].every((id) => g.m.claims[0][id] >= g.m.dice[0][id][0] + g.m.dice[0][id][1]));
  G.answer(g, 1, { iddia: 12 });
  g.phase = "meydan1";
  G.onPhase(g, "meydan1");
  Bots.plan(g, t0);
  acts = Bots.due(g, t0 + 60000);
  bak("4 bot meydan kararı", acts.length === 4 && acts.every(([id, v]) => v.meydan !== id));
  // 12 iddiası çoğunlukla sorgulanır
  let sor = 0;
  for (let i = 0; i < 200; i++) if (K.botMeydan("durust", 2, { 1: 12, 2: 6, 3: 7 }) === 1) sor++;
  bak(`12 iddiası sorgulanır (${sor}/200)`, sor > 170);
  let blof = 0;
  for (let i = 0; i < 300; i++) if (K.botIddia("blofcu", 5) > 5) blof++;
  bak(`blöfçü sık blöf yapar (${blof}/300)`, blof > 150);
  let durust = 0;
  for (let i = 0; i < 300; i++) if (K.botIddia("durust", 5) === 5) durust++;
  bak(`dürüst çoğunlukla zarını söyler (${durust}/300)`, durust > 220);
}

console.log(`kumar: ${ok} doğru, ${hata} hata`);
process.exit(hata ? 1 : 0);
