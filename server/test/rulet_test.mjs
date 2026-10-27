// Rus Ruleti "masada dönen silah" birim testi:  cd server && node test/rulet_test.mjs   (sunucu gerekmez)
// Silahın rastgele birine geçtiği iki an (oyunun başı, biri kendini vurunca) masada dönen silahla gösterilir:
// olayda cevir: true; dönüş sürerken karar reddedilir, sıra süresi işlemez; dönüş bitince sahip karar verebilir.
// Başkasına sıkıp patlamazsa (silah ona geçer) dönüş yok. Botlar da dönüş bitene kadar bekler.
import * as R from "../src/modes/rulet.js";
import * as Bots from "../src/bots.js";

let ok = 0;
let hata = 0;
function bak(ad, kosul, ek = "") {
  if (kosul) ok++;
  else {
    hata++;
    console.log("HATA:", ad, ek);
  }
}

// sahte saat ve zar
let T = 1_700_000_000_000;
Date.now = () => T;
let zar = null; // null: gerçek Math.random
const gercek = Math.random;
Math.random = () => (zar === null ? gercek() : zar);

function yeni(speed = 1, n = 4) {
  const players = Array.from({ length: n }, (_, i) => i + 1);
  const g = { task: "rulet", round: 1, phase: "anons", speed, players, names: {}, hits: {}, bots: [] };
  R.start(g);
  return g;
}

// ---- oyunun başı: silah masada döner
{
  const g = yeni(1);
  g.phase = "oyun";
  const r = R.onPhase(g, "oyun");
  const ev = r.broadcast;
  const m = g.m;
  bak("başta cevir: true", ev.cevir === true && ev.tur === "sira");
  bak("dönüş süresi 4,5 sn", ev.cevir_ms === 4500 && ev.cevir_bas === 0, JSON.stringify(ev));
  bak("sahip sunucuda seçili", g.players.includes(ev.sira) && ev.sira === m.holder);
  bak("karar dönüş bitince açılır", m.ready === T + 4500);
  bak("sıra süresi dönüşten sonra işler", m.wake === T + 4500 + 15000);
  const st = R.stateExtra(g);
  bak("durumda dönüş bilgisi", st.cevir && st.cevir.kalan === 4500 && st.cevir.bas === 0 && st.cevir.tohum === ev.tohum);
  // dönerken sahip karar veremez
  T += 2000;
  bak("dönüş anında karar reddedilir", R.answer(g, m.holder, { atis: "kendi" }) === null && m.last === null);
  // bot da dönüş bitene kadar beklemeli
  g.bots = [m.holder];
  const at = Bots.plan(g, T);
  bak("bot dönüş bitince düşünmeye başlar", at >= m.ready + 1000 && at <= m.ready + 3900, at - m.ready);
  bak("bot erken karar vermez", Bots.due(g, T + 2400).length === 0);
  g.bots = [];
  // dönüş bitti: sahip karar verebilir (boş çıksın)
  T += 2500;
  bak("dönüş bitince durumda cevir yok", !R.stateExtra(g).cevir);
  zar = 0.99;
  const h = m.holder;
  const r2 = R.answer(g, h, { atis: "kendi" });
  bak("dönüş bitince sahip karar verebilir", r2 && r2.broadcast && r2.broadcast.tur === "atis" && r2.broadcast.patladi === false);
  bak("kendine boş: dönüş yok, silah sende", !r2.broadcast.cevir && m.holder === h && m.stage === 1);
  bak("normal atışta bekleme 2,6 sn", m.ready === T + 2600);
}

// ---- biri kendini vurdu: atış canlandırmasından sonra silah masada döner
{
  const g = yeni(1);
  g.phase = "oyun";
  R.onPhase(g, "oyun");
  T += 4500;
  const m = g.m;
  const olen = m.holder;
  zar = 0; // patlar; passRandom ilk kişiyi seçer
  const r = R.answer(g, olen, { atis: "kendi" });
  const ev = r.broadcast;
  bak("kendini vurdu: öldü", ev.patladi === true && ev.olen === olen && !m.alive.includes(olen));
  bak("kendini vurdu: cevir", ev.cevir === true && ev.cevir_bas === 2600 && ev.cevir_ms === 4500, JSON.stringify(ev));
  bak("yeni sahip yaşayan biri", m.alive.includes(m.holder) && ev.sira === m.holder && m.holder !== olen);
  bak("karar atış + dönüş bitince", m.ready === T + 2600 + 4500 && m.wake === T + 2600 + 4500 + 15000);
  const st = R.stateExtra(g);
  bak("durumda: dönüş 2,6 sn sonra başlar", st.cevir && st.cevir.bas === 2600 && st.cevir.ms === 4500 && st.cevir.kalan === 7100);
  T += 5000;
  bak("dönerken yeni sahip karar veremez", R.answer(g, m.holder, { atis: "kendi" }) === null);
  bak("dönerken sıra süresi dolmaz", T < m.wake);
  T += 2100;
  zar = 0.99;
  const r2 = R.answer(g, m.holder, { atis: "kendi" });
  bak("dönüş bitince yeni sahip sıkar", r2 && r2.broadcast.tur === "atis");
}

// ---- başkasına sıktı, patlamadı: silah ona geçer, dönüş yok; vurdu: silah atanda kalır, dönüş yok
{
  const g = yeni(1);
  g.phase = "oyun";
  R.onPhase(g, "oyun");
  T += 4500;
  const m = g.m;
  const a = m.holder;
  const b = m.alive.find((x) => x !== a);
  zar = 0.99;
  const r = R.answer(g, a, { atis: b });
  bak("başkasına boş: silah ona geçer, dönüş yok", r.broadcast.patladi === false && m.holder === b && !r.broadcast.cevir);
  T += 2600;
  zar = 0;
  const c = m.alive.find((x) => x !== b);
  const r2 = R.answer(g, b, { atis: c });
  bak("birini vurdu: silah atanda, dönüş yok", r2.broadcast.olen === c && m.holder === b && !r2.broadcast.cevir);
}

// ---- son iki kişi: kendini vuran ölünce oyun biter, dönüş yok
{
  const g = yeni(1, 2);
  g.phase = "oyun";
  R.onPhase(g, "oyun");
  T += 4500;
  zar = 0;
  const r = R.answer(g, g.m.holder, { atis: "kendi" });
  bak("son atış: dönüş yok, oyun biter", !r.broadcast.cevir && g.m.endAt > 0);
}

// ---- hız: test hızında dönüş kısalır (en az 0,5 sn)
{
  const g = yeni(0.5);
  g.phase = "oyun";
  const ev = R.onPhase(g, "oyun").broadcast;
  bak("hız 0,5: dönüş 2,25 sn", ev.cevir_ms === 2250);
  const g2 = yeni(0.05);
  g2.phase = "oyun";
  bak("çok hızlı: en az 0,5 sn", R.onPhase(g2, "oyun").broadcast.cevir_ms === 500);
}

// ---- dönerken sahip çıkarsa: yeni sahip hemen, dönüş bilgisi silinir
{
  const g = yeni(1);
  g.phase = "oyun";
  R.onPhase(g, "oyun");
  const h = g.m.holder;
  R.leave(g, h);
  bak("sahip çıktı: dönüş iptal", !g.m.cevir && !R.stateExtra(g).cevir && g.m.holder !== h);
}

// ---- onWake (süre doldu): dönüşten önce çağrılmaz; dönüş bitip süre dolunca tetik kendine çekilir
{
  const g = yeni(1);
  g.phase = "oyun";
  R.onPhase(g, "oyun");
  T = g.m.wake;
  zar = 0.99;
  const r = R.onWake(g);
  bak("süre doldu: kendine çekildi", r && r.broadcast.zaman === true);
}

Math.random = gercek;
console.log(`rulet_test: ${ok} doğru, ${hata} hata`);
process.exit(hata ? 1 : 0);
