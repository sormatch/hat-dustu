// PROJEKTÖR AVI birim testi:  cd server && node test/projektor_test.mjs
// Işık yolları avluda mı, ışıkta kalan yakalanıyor mu (önce uyarı, ISIK_SURE sonra), siper koruyor mu, arama
// uyarısı ve araması, botların kaçışı, bitiş ve puanlar, eski sürümlü oyuncu varken oyunun seçilmemesi.
import * as G from "../src/game.js";
import * as P from "../src/modes/projektor.js";

let ok = 0;
let hata = 0;
function bak(ad, kosul, ek = "") {
  if (kosul) ok++;
  else {
    hata++;
    console.log("  HATA " + ad + (ek ? "  -> " + ek : ""));
  }
}

// Zamanı elle sürmek için Date.now yerine sahte saat
let saat = 1_000_000;
Date.now = () => saat;
const ilerle = (ms) => (saat += ms);

// 1) Işıklar hep avlunun içinde, hız artıyor
{
  const p = P.isiklar(12345);
  bak("4 ışık parametresi", p.length === 4);
  bak("aynı tohum aynı yol", JSON.stringify(P.isiklar(12345)) === JSON.stringify(p));
  let icinde = true;
  for (let t = 0; t <= 120000; t += 250) {
    for (const q of p) {
      const [x, z] = P.isikMerkez(q, t);
      if (x < P.AVLU.x0 || x > P.AVLU.x1 || z < P.AVLU.z0 || z > P.AVLU.z1) icinde = false;
    }
  }
  bak("ışık merkezleri avlunun içinde", icinde);
  bak("zaman hızlanıyor", P.tau(110000) - P.tau(100000) > 1.5 * (P.tau(10000) - P.tau(0)));
  bak("ışık sayısı artıyor", P.aktifIsik(0, 6) === 2 && P.aktifIsik(40000, 6) === 3 && P.aktifIsik(80000, 6) === 4);
  bak("az oyuncuda bir eksik", P.aktifIsik(80000, 3) === 3);
}

// Oyun kurar: 1, 2 insan; 3 bot
function kur() {
  const g = G.newGame([{ id: 1, name: "A", cell: 0, sv: 2 }, { id: 2, name: "B", cell: 1, sv: 2 }, { id: 3, name: "Bot", cell: 2, sv: 99 }], 1, ["projektor"]);
  g.bots = [3];
  G.startNext(g);
  bak("oyun projektor", g.task === "projektor", g.task);
  return g;
}

// İlk ışığın merkezini bulana kadar ilerler ve (siper dışında) o noktayı döndürür
function isikNoktasi(g) {
  for (let i = 0; i < 400; i++) {
    const c = P.isikMerkez(g.m.isik[0], Date.now() - g.m.t0);
    const siperde = P.SIPERLER.some((s) => Math.hypot(c[0] - s[0], c[1] - s[1]) <= P.SIPER_R + 2.5);
    if (!siperde) return c;
    ilerle(100);
  }
  return null;
}

// 2) Sayım: bot koşar; av: ışıkta kalan yakalanır, siper korur
{
  const g = kur();
  g.phase = "sayim";
  const r = P.onPhase(g, "sayim");
  bak("sayımda bot siperine koşar", r && JSON.stringify(r).includes("bot_kos"));
  bak("botun siperi var", g.m.bot[3] && g.m.bot[3].siper >= 0);
  bak("sayımda ışık yok", P.onKonum(g, 1, [40, 0]) === null);
  g.phase = "av";
  P.onPhase(g, "av");
  bak("av başlayınca arama zamanlandı", g.m.wake > Date.now());
  ilerle(2000);
  const c = isikNoktasi(g);
  bak("ışık noktası bulundu", !!c);
  delete g.m.pos[1]; // (oyuncu ışığa yürüyerek geldi sayılır: ışınlanma sınırı bu bölümde denenmiyor)
  const u = P.onKonum(g, 1, c);
  bak("ışıkta ilk görülüş uyarı", u && u.privates && u.privates[1] && u.privates[1].tur === "isikta", JSON.stringify(u));
  ilerle(100);
  bak("hemen yakalanmaz", P.onKonum(g, 1, P.isikMerkez(g.m.isik[0], Date.now() - g.m.t0)) === null);
  ilerle(300);
  bak("400 ms sonra henüz yakalanmaz (kaçma payı)", P.onKonum(g, 1, P.isikMerkez(g.m.isik[0], Date.now() - g.m.t0)) === null);
  ilerle(350);
  const y = P.onKonum(g, 1, P.isikMerkez(g.m.isik[0], Date.now() - g.m.t0));
  bak("700 ms sonra hâlâ ışıktaysa yakalanır", y && y.broadcast && y.broadcast.tur === "yakalandi" && y.broadcast.id === 1, JSON.stringify(y));
  bak("yakalanan hayattakilerden çıktı", !g.m.alive.includes(1) && g.m.dead.includes(1));
  // siper korur: 2 siperde dururken üstüne ışık gelse de yakalanmaz
  const s = P.SIPERLER[0];
  let korundu = true;
  for (let i = 0; i < 300; i++) {
    ilerle(100);
    const e = P.onKonum(g, 2, s);
    if (e) korundu = false;
  }
  bak("siperdeki ışıktan korunur", korundu && g.m.alive.includes(2));
}

// 3) Arama: uyarı, botun kaçışı, aranan siperdeki insan yakalanır
{
  const g = kur();
  g.phase = "av";
  P.onPhase(g, "av");
  // bot 0. siperde, insan 2 de 0. siperde, insan 1 başka siperde
  g.m.bot[3] = { siper: 0, a: P.SIPERLER[0], b: P.SIPERLER[0], s: 0, d: 0 };
  P.onKonum(g, 2, P.SIPERLER[0]);
  P.onKonum(g, 1, P.SIPERLER[5]);
  // aramayı 0. siper için zorla
  // (av başında 14. sn için arama uyarısı kuyrukta)
  saat = g.m.t0 + 14000;
  const r = P.onWake(g);
  const uy = r && (r.broadcast.tur === "arama_uyari" ? r.broadcast : (r.broadcast.liste || []).find((x) => x.tur === "arama_uyari"));
  bak("arama uyarısı", !!uy, JSON.stringify(r));
  bak("arama dolu siperi içeriyor", uy && uy.siper.includes(0));
  g.m.arama.siper = [0];
  // bot kaçtıysa kaçış yolu var; kaçmadıysa (%15) yakalanacak
  ilerle(5100);
  const a = P.onWake(g);
  const ar = a && (a.broadcast.tur === "arama" ? a.broadcast : (a.broadcast.liste || []).find((x) => x.tur === "arama"));
  bak("arama yapıldı", !!ar, JSON.stringify(a));
  bak("aranan siperdeki insan yakalandı", ar && ar.yakalanan.includes(2) && !g.m.alive.includes(2));
  bak("başka siperdeki kurtuldu", g.m.alive.includes(1));
}

// 3b) Konum göndermeyen kaçamaz: av sırasında düzenli denetim; eski konum ışıkta sayılır; ışınlanma yok sayılır
{
  const g = kur();
  g.phase = "av";
  P.onPhase(g, "av");
  // 1 siperde ve konum yollamaya devam ediyor; 2 hiç konum yollamıyor
  P.onKonum(g, 1, P.SIPERLER[2]);
  let isiktaUyari = false;
  let yakalanan2 = false;
  for (let i = 0; i < 20 && !yakalanan2; i++) {
    ilerle(150);
    P.onKonum(g, 1, P.SIPERLER[2]);
    if (g.m.wake && Date.now() >= g.m.wake) {
      const r = P.onWake(g);
      const lst = r && r.broadcast ? r.broadcast.liste || [r.broadcast] : [];
      if (r && r.privates && r.privates[2] && r.privates[2].tur === "isikta") isiktaUyari = true;
      if (lst.some((x) => x.tur === "yakalandi" && x.id === 2)) yakalanan2 = true;
    }
  }
  bak("konum göndermeyene önce uyarı", isiktaUyari);
  bak("konum göndermeyen düzenli denetimde yakalandı", yakalanan2 && !g.m.alive.includes(2));
  bak("konum yollayan siperdeki yakalanmadı", g.m.alive.includes(1));
  bak("denetim av boyunca kurulu", g.m.q.some((x) => x.tur === "tara"));
  // 1 konum yollamayı keser (siperde dursa da): 1,5 sn sonra ışıkta sayılır, yakalanır
  let yakalanan1 = false;
  for (let i = 0; i < 30 && !yakalanan1; i++) {
    ilerle(150);
    if (g.m.wake && Date.now() >= g.m.wake) {
      const r = P.onWake(g);
      const lst = r && r.broadcast ? r.broadcast.liste || [r.broadcast] : [];
      if (lst.some((x) => x.tur === "yakalandi" && x.id === 1)) yakalanan1 = true;
      if (r && r.finish) break;
    }
  }
  bak("konumu eskiyen (1,5 sn) yakalandı", yakalanan1 || !g.m.alive.includes(1));
}
{
  const g = kur();
  g.phase = "av";
  P.onPhase(g, "av");
  P.onKonum(g, 1, P.SIPERLER[0]);
  ilerle(200);
  P.onKonum(g, 1, P.SIPERLER[17]); // 200 ms'de ~20 m: ışınlanma
  bak("ışınlanma yok sayıldı", JSON.stringify(g.m.pos[1]) === JSON.stringify(P.SIPERLER[0]));
  ilerle(200);
  const yakin = [P.SIPERLER[0][0] + 1, P.SIPERLER[0][1]];
  P.onKonum(g, 1, yakin); // yürüme hızı
  bak("yürüme hızında konum alındı", JSON.stringify(g.m.pos[1]) === JSON.stringify(yakin));
}

// 4) Bitiş ve puan: tek kalan +3, yakalanan -1
{
  const g = kur();
  g.phase = "av";
  P.onPhase(g, "av");
  const e1 = P.onKonum(g, 1, [0, 0]); // avlu dışı nokta: ışık yok, sorun yok
  bak("ışıksız nokta sessiz", e1 === null);
  g.m.alive = [1, 2];
  g.m.dead = [3];
  g.m.pts = { 3: -1 };
  // 2 ışıkta yakalansın
  ilerle(1000);
  const c = isikNoktasi(g);
  P.onKonum(g, 2, c);
  ilerle(750);
  P.onKonum(g, 2, P.isikMerkez(g.m.isik[0], Date.now() - g.m.t0));
  bak("tek kişi kaldı", g.m.alive.length === 1 && g.m.alive[0] === 1);
  bak("bitiş zamanlandı", g.m.bitis > 0);
  ilerle(3300);
  const f = P.onWake(g);
  bak("süre sonunda oyun biter", f && f.finish === true);
  const res = P.resolve(g);
  bak("tek kalan +3", res.private[1].delta === 3, JSON.stringify(res.private));
  bak("yakalanan -1", res.private[2].delta === -1 && res.private[3].delta === -1);
  bak("kazanan 1", res.public.kazanan === 1);
}

// 5) Süre bitince hayatta kalanlar +2
{
  const g = kur();
  g.phase = "av";
  P.onPhase(g, "av");
  const res = P.resolve(g);
  bak("süre bitti: herkes +2", [1, 2, 3].every((id) => res.private[id].delta === 2), JSON.stringify(res.private));
}

// 6) Ayrılan oyuncu
{
  const g = kur();
  g.phase = "av";
  P.onPhase(g, "av");
  P.leave(g, 2);
  bak("ayrılan hayattakilerden çıkar", !g.m.alive.includes(2));
}

// 7) Eski sürüm (sv 1) olan bir oyuncu varsa seçilmez, herkes 2 ise seçilebilir
{
  const eski = [{ id: 1, name: "A", cell: 0, sv: 1 }, { id: 2, name: "B", cell: 1, sv: 2 }];
  const yeni = [{ id: 1, name: "A", cell: 0, sv: 2 }, { id: 2, name: "B", cell: 1, sv: 2 }];
  const zorla = G.newGame(eski, 1, ["projektor"]);
  bak("eski sürümle zorla seçilse de oynanmaz", !zorla.games.includes("projektor"), JSON.stringify(zorla.games));
  let gordu = false;
  for (let i = 0; i < 300; i++) if (G.macListesi(eski).includes("projektor")) gordu = true;
  bak("eski sürümle rastgele listeye girmez", !gordu);
  let yeniGordu = false;
  for (let i = 0; i < 300; i++) if (G.macListesi(yeni).includes("projektor")) yeniGordu = true;
  bak("yeni sürümle listeye girer", yeniGordu);
  bak("sv yoksa eski sayılır", !G.newGame([{ id: 1, name: "A", cell: 0 }, { id: 2, name: "B", cell: 1 }], 1, ["projektor"]).games.includes("projektor"));
}

console.log(`projektor_test: ${ok} doğru, ${hata} hata`);
process.exit(hata ? 1 : 0);
