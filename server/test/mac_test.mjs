// Maç listesi testleri:  cd server && node test/mac_test.mjs
// "Tüm oyunlar": oynanabilen her oyun PLAYLIST sırasıyla (Kim Kim? ilk, Büyük Kaçış son), tekrar yok,
// en az oyuncu / davetli oda kuralları; lobide seçilen oyun(lar) aynen; oyuncu azalınca atlama; maç sonu tablosu.
import * as G from "../src/game.js";

let ok = 0;
let hata = 0;
function bak(ad, kosul) {
  if (kosul) ok++;
  else {
    hata++;
    console.log("HATA:", ad);
  }
}
// sv 2: yeni oyunları (Projektör Avı) destekleyen istemci sürümü
const oyuncu = (n, davetli = false) => Array.from({ length: n }, (_, i) => ({ id: i + 1, name: "O" + (i + 1), cell: i, inv: davetli && i === 1, sv: 2 }));

// ---- her oyunun bir türü var
for (const x of G.PLAYLIST) bak("tür tanımlı: " + x, !!G.TUR[x]);

// ---- davetli oda, 4 kişi (sv 2): oynanabilen her oyun PLAYLIST sırasıyla, Kim Kim ilk, tekrar yok, her seferinde aynı
{
  const beklenen = G.PLAYLIST.filter((x) => (G.MODES[x].surum || 1) <= 2 && !G.MODES[x].final);
  for (let k = 0; k < 50; k++) {
    const g = G.newGame(oyuncu(4, true));
    const l = g.games;
    if (k < 1) console.log("  örnek:", l.join(", "));
    bak("hepsi sırayla " + l.join(","), JSON.stringify(l) === JSON.stringify(beklenen));
    bak("Kim Kim ilk", l[0] === "kimkim");
    bak("tekrar yok", new Set(l).size === l.length);
    bak("rounds = oyun sayısı", g.rounds === l.length);
  }
  bak("sürüm 2'de final oyunu yok", !G.newGame(oyuncu(4, true)).games.includes("kacis"));
}

// ---- sürüm 3: 9 oyunun hepsi, Büyük Kaçış en sonda
{
  const o3 = oyuncu(4, true).map((p) => ({ ...p, sv: 3 }));
  const l = G.newGame(o3).games;
  bak("sv3: tüm oyunlar PLAYLIST sırasıyla " + l.join(","), JSON.stringify(l) === JSON.stringify(G.PLAYLIST));
  bak("Büyük Kaçış son oyun", l[l.length - 1] === "kacis");
}

// ---- davetsiz oda: Kim Kim yok, kalanlar yine sırayla
{
  const l = G.newGame(oyuncu(5)).games;
  bak("davetsiz: Kim Kim yok", !l.includes("kimkim"));
  bak("davetsiz: sırayla " + l.join(","), JSON.stringify(l) === JSON.stringify(G.PLAYLIST.filter((x) => l.includes(x))) && l.length >= 6);
}

// ---- 2 kişi: en az 3 kişilik oyunlar (yalanci, kimkim) yok
{
  const l = G.newGame(oyuncu(2, true)).games;
  bak("2 kişi: hepsi oynanabilir " + l.join(","), l.every((x) => (G.MODES[x].min || 2) <= 2));
  bak("2 kişi: tekrar yok", new Set(l).size === l.length && l.length >= 1);
}

// ---- lobide tek oyun seçildi (forced): yalnız o, davet koşulu aranmaz
{
  const g = G.newGame(oyuncu(4), 1, ["kimkim"]);
  bak("forced kimkim (davetsiz bile)", JSON.stringify(g.games) === '["kimkim"]' && g.rounds === 1);
  const g2 = G.newGame(oyuncu(4), 1, ["rulet"]);
  bak("forced rulet", JSON.stringify(g2.games) === '["rulet"]');
  // test listesi: verilen sırayla, hepsi (7 oyun)
  const g3 = G.newGame(oyuncu(4).map((p) => ({ ...p, sv: 3 })), 1, G.PLAYLIST.slice());
  bak("forced tüm oyunlar aynen", JSON.stringify(g3.games) === JSON.stringify(G.PLAYLIST));
  // forced ama en az kişi tutmuyor: atlanır
  const g4 = G.newGame(oyuncu(2), 1, ["yalanci", "c4"]);
  bak("forced: 2 kişide yalanci atlanır", JSON.stringify(g4.games) === '["c4"]');
}

// ---- maç akışı: oyuncu azalınca oynanamayan oyunlar atlanır, maç sonu tablosu oynanan oyun kadar sütun
{
  const g = G.newGame(oyuncu(3), 1, ["ortalama", "yalanci", "kimkim", "c4"]);
  G.startNext(g);
  bak("ilk oyun ortalama", g.task === "ortalama" && g.round === 1);
  g.log.push({ task: "ortalama", title: "ORTALAMA", d: { 1: 2, 2: 0, 3: 1 } });
  g.score = { 1: 2, 2: 0, 3: 1 };
  G.removePlayer(g, 3); // 2 kişi kaldı: yalanci ve kimkim (en az 3) oynanamaz
  bak("sıradaki c4", G.siradaki(g) === G.MODES.c4);
  bak("maç bitmedi", G.checkEnd(g) === false);
  G.startNext(g);
  bak("yalanci/kimkim atlandı -> c4", g.task === "c4" && g.round === 4);
  g.log.push({ task: "c4", title: "C4", d: { 1: 0, 2: 3 } });
  g.score[2] = 3;
  bak("sıradaki yok", G.siradaki(g) === null);
  bak("maç bitti", G.checkEnd(g) === true && g.winner === 2);
  const m = G.overMsg(g);
  bak("tablo 2 sütun", m.oyunlar.length === 2 && m.rounds === 2 && m.table.every((r) => r.p.length === 2));
  bak("tablo sırası", m.table[0].id === 2 && m.table[0].score === 3);
  bak("ayrılan işaretli", m.table.find((r) => r.id === 3).left === true);
}

// ---- tam maç: her oyun başlatılabiliyor, maç listedeki oyun sayısında bitiyor
{
  const g = G.newGame(oyuncu(4, true));
  let n = 0;
  while (true) {
    G.startNext(g);
    n++;
    g.log.push({ task: g.task, title: G.SHORT[g.task], d: {} });
    if (G.checkEnd(g)) break;
    if (n > 20) break;
  }
  bak("tüm oyunlarda bitti (" + n + ")", n === g.games.length && G.overMsg(g).oyunlar.length === g.games.length);
}

// ---- oyun kalmadıysa startNext false döner, durum bozulmaz (son oyun iptal / sonuçta biri çıktı)
{
  const g = G.newGame(oyuncu(3), 1, ["ortalama", "yalanci"]);
  bak("ilk oyun başladı", G.startNext(g) === true && g.task === "ortalama");
  G.removePlayer(g, 3); // yalanci 3 kişilik: artık oynanamaz
  const once = JSON.stringify([g.gi, g.task, g.round]);
  bak("kalan oyun yok: startNext false", G.startNext(g) === false);
  bak("startNext false: gi/task değişmedi", JSON.stringify([g.gi, g.task, g.round]) === once);
  bak("kalan oyun yok: checkEnd maçı bitirir", G.checkEnd(g) === true && g.phase === "bitti");
}

// ---- süre tahmini: tüm oyunlu maç (üst sınır süreleriyle kaba hesap) 35 dk'yı geçmesin
{
  const sure = (x) => {
    const m = G.MODES[x];
    const p = typeof m.phases === "function" ? m.phases({ players: [1, 2, 3, 4], m: {} }) : m.phases;
    return (Array.isArray(p) ? p : []).reduce((t, f) => t + (m.durations[f] || 0), 0) + G.RESULT_TIME;
  };
  let top = 0;
  const N = 300;
  for (let k = 0; k < N; k++) top += G.newGame(oyuncu(4, true)).games.reduce((t, x) => t + sure(x), 0);
  const dk = top / N / 60;
  console.log("  ortalama en uzun süre: " + dk.toFixed(1) + " dk");
  bak("tüm oyunlu maç (üst sınır) 35 dk altında", dk < 35);
}

console.log(`mac_test: ${ok} doğru, ${hata} hata`);
process.exit(hata ? 1 : 0);
