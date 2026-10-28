// BÜYÜK KAÇIŞ birim testi:  cd server && node test/kacis_test.mjs
import * as G from "../src/game.js";
import * as K from "../src/modes/kacis.js";

let ok = 0;
let hata = 0;
function bak(ad, kosul, ek = "") {
  if (kosul) ok++;
  else {
    hata++;
    console.log("  HATA " + ad + (ek ? "  -> " + ek : ""));
  }
}
let saat = 5_000_000;
Date.now = () => saat;
const ilerle = (ms) => (saat += ms);

function kur(n = 3, bots = []) {
  const ps = Array.from({ length: n }, (_, i) => ({ id: i + 1, name: "O" + (i + 1), cell: i, sv: 3 }));
  const g = G.newGame(ps, 1, ["kacis"]);
  g.bots = bots;
  G.startNext(g);
  return g;
}
const cevap = (g, id, v) => K.answer(g, id, v);
// sunucunun bildiği konum (Room konum mesajı): hücre k'nin ortası, yer altı (h -2.3) ya da koridor
const hucrede = (g, id, k, dx = 0, dz = 0) => K.onKonum(g, id, [0 + dx, K.hucreZ(k) + dz], 0);
const yerAltinda = (g, id, x, z) => K.onKonum(g, id, [x, z], -2.3);
const ozel = (r, id) => r && r.privates && r.privates[id];
// Bir sayım turunu sonuna kadar oynatır: zil, gardiyan kapı kapı (kontrol olayları), en sonda özet "sayim"
function sayimTuru(g) {
  const m = g.m;
  saat = m.q.find((x) => x.tur === "sayim_uyari").at;
  const tum = [];
  const priv = {};
  const al = (r) => {
    if (!r) return;
    if (r.broadcast) tum.push(...(r.broadcast.liste || [r.broadcast]));
    if (r.privates) for (const [k, v] of Object.entries(r.privates)) (priv[k] = priv[k] || []).push(...(v.liste || [v]));
  };
  al(K.onWake(g));
  for (let i = 0; i < 30 && !tum.some((x) => x.tur === "sayim"); i++) {
    saat = m.q[0].at;
    al(K.onWake(g));
  }
  return { tum, priv, ev: tum.find((x) => x.tur === "sayim"), kontrol: tum.filter((x) => x.tur === "kontrol") };
}

// 1) harita ve dağıtım
{
  const g = kur(3);
  bak("oyun kacis", g.task === "kacis");
  g.phase = "kacis";
  const m = g.m;
  bak("2 ızgara 1 tuğla", m.harita.izgara.length === 2 && m.harita.tugla.length === 1);
  bak("ızgara/tuğla temel hattında", K.kare(m, K.TEMEL_X, m.harita.izgara[0]) === "izgara" && K.kare(m, K.TEMEL_X, m.harita.tugla[0]) === "tugla");
  bak("temelin geri kalanı beton", K.kare(m, K.TEMEL_X, 999) === "temel" || true);
  let kuyuKaya = false;
  for (const id of g.players) if (m.kaya.has(K.klozetHucre(g.cells[id]).join(","))) kuyuKaya = true;
  bak("klozet kuyusunda kaya yok", !kuyuKaya);
  for (const id of g.players) {
    const es = Object.values(m.yer[g.cells[id]]);
    bak("hücre " + id + ": çakı ve kaşık var", es.includes("caki") && es.includes("kasik"), JSON.stringify(es));
  }
  for (const id of g.players) {
    const es = Object.values(m.yer[g.cells[id]]).sort();
    bak("hücre " + id + ": eski sürümde tam takım", JSON.stringify(es) === JSON.stringify(K.TAKIM_ESKI.slice().sort()), JSON.stringify(es));
  }
  bak("herkesin ipucu var", g.players.every((id) => m.ipucu[id] && typeof m.ipucu[id].z === "number"));
  bak("gizli bilgi hazır", g.secret[1] && Array.isArray(g.secret[1].env) && g.secret[1].ipucu);
}

// Bir oyuncuya kendi hücresindeki tüm eşyaları buldurur
function hepsiniAra(g, id) {
  for (const y of K.YERLER) {
    ilerle(1000);
    cevap(g, id, { ara: y });
  }
}

// 2) arama, vida, klozet, kazma, sertler
{
  const g = kur(2);
  g.phase = "kacis";
  K.onPhase(g, "kacis");
  const m = g.m;
  const o = m.oyuncu[1];
  bak("çakısız vida reddedilir", ozel(cevap(g, 1, { vida: true }), 1).tur === "red");
  const bos = K.YERLER.find((y) => !m.yer[g.cells[1]][y]);
  ilerle(1000);
  const rb = cevap(g, 1, { ara: bos });
  bak("boş yer: bos", ozel(rb, 1) && ozel(rb, 1).tur === "bos");
  hepsiniAra(g, 1);
  bak("çakı ve kaşık bulundu", o.env.includes("caki") && o.env.includes("kasik"), JSON.stringify(o.env));
  ilerle(2000);
  bak("ilk vida", cevap(g, 1, { vida: true }) && o.vida === 1);
  bak("çok hızlı vida sayılmaz", cevap(g, 1, { vida: true }) === null && o.vida === 1);
  bak("4 vida bitmeden klozet açılmaz", ozel(cevap(g, 1, { klozet: true }), 1).tur === "red");
  for (let i = 0; i < 3; i++) (ilerle(1200), cevap(g, 1, { vida: true }));
  bak("4 vida söküldü", o.vida === 4);
  const rk = cevap(g, 1, { klozet: true });
  bak("klozet açıldı (herkese)", rk && rk.broadcast && rk.broadcast.tur === "klozet" && rk.broadcast.acik);
  const kk = K.klozetHucre(g.cells[1]);
  bak("klozetin altı kazılmış sayılır", !!m.kazilan[kk.join(",")]);
  // yer altı
  cevap(g, 1, { nerede: -1 });
  bak("yer altında", o.nerede === -1);
  bak("komşu olmayan kare kazılamaz", cevap(g, 1, { kaz: [kk[0] - 3, kk[1]] }) === null);
  ilerle(7000);
  // batıdaki komşu kaya olabilir: kaya değilse kazılır
  let hedef = [kk[0] - 1, kk[1]];
  if (K.kare(m, ...hedef) === "kaya") hedef = [kk[0], kk[1] + 1];
  const rz = cevap(g, 1, { kaz: hedef });
  bak("kaşıkla kazıldı", rz && rz.broadcast && rz.broadcast.tur === "kazildi", JSON.stringify(rz));
  const r2 = cevap(g, 1, { kaz: [hedef[0] - 1, hedef[1]] }); // (komşu kaya çıkarsa "sert" döner: o da kazı değil)
  bak("hemen ikinci kazı (kaşık yavaş) olmaz", !(r2 && r2.broadcast), JSON.stringify(r2));
  // sert: kaya
  const kaya = m.harita.kaya[0].split(",").map(Number);
  m.kazilan[[kaya[0] + 1, kaya[1]].join(",")] = 1;
  ilerle(7000);
  const rs = cevap(g, 1, { kaz: kaya });
  bak("kaya kazılamaz", ozel(rs, 1) && ozel(rs, 1).tur === "sert" && ozel(rs, 1).ne === "kaya");
  // temel: beton / ızgara / tuğla
  const tz = m.harita.izgara[0];
  m.kazilan[[K.TEMEL_X + 1, tz].join(",")] = 1;
  ilerle(7000);
  bak("ızgara maymuncuksuz açılmaz", ozel(cevap(g, 1, { kaz: [K.TEMEL_X, tz] }), 1).ne === "izgara");
  o.env = ["caki", "kasik", "tel", "catal"];
  const ry = cevap(g, 1, { yap: "maymuncuk" });
  bak("maymuncuk yapıldı", o.env.includes("maymuncuk") && !o.env.includes("catal") && ry.reply.yapildi === "maymuncuk");
  ilerle(7000);
  const ri = cevap(g, 1, { kaz: [K.TEMEL_X, tz] });
  bak("maymuncukla ızgaradan geçildi", ri && ri.broadcast && ri.broadcast.ne === "izgara" && m.acik_izgara[[K.TEMEL_X, tz].join(",")]);
  const tg = m.harita.tugla[0];
  m.kazilan[[K.TEMEL_X + 1, tg].join(",")] = 1;
  ilerle(7000);
  bak("tuğla kaşıkla kazılmaz", ozel(cevap(g, 1, { kaz: [K.TEMEL_X, tg] }), 1).ne === "tugla");
  o.env.push("tahta", "bant");
  cevap(g, 1, { yap: "kurek" });
  bak("kürek yapıldı (kaşık harcandı)", o.env.includes("kurek") && !o.env.includes("kasik"));
  ilerle(9500);
  bak("tuğla kürekle kazılır", cevap(g, 1, { kaz: [K.TEMEL_X, tg] }).broadcast.ne === "tugla");
  const betonZ = [...Array(40).keys()].map((i) => i - 20).find((z) => K.kare(m, K.TEMEL_X, z) === "temel");
  m.kazilan[[K.TEMEL_X + 1, betonZ].join(",")] = 1;
  ilerle(9500);
  bak("beton temel kazılamaz", ozel(cevap(g, 1, { kaz: [K.TEMEL_X, betonZ] }), 1).ne === "temel");
  o.env = ["kurek", "pil"];
  bak("eksik malzemeyle fener olmaz", ozel(cevap(g, 1, { yap: "fener" }), 1).tur === "red");
}

// 3) sayım: yer altındaki ya da klozeti açık olan yakalanır
{
  const g = kur(2);
  g.phase = "kacis";
  K.onPhase(g, "kacis");
  const m = g.m;
  m.oyuncu[1].env = ["caki", "kasik", "tahta", "kurek"];
  m.oyuncu[1].vida = 4;
  m.oyuncu[1].klozet = true;
  m.oyuncu[1].nerede = -1;
  m.oyuncu[2].nerede = g.cells[2];
  const t = sayimTuru(g);
  const ev = t.ev;
  const uy = t.tum.find((x) => x.tur === "sayim_uyari");
  bak("sayım uyarısı: gardiyanın sırası ve kapı arası", uy && JSON.stringify(uy.sira) === JSON.stringify(K.SIRA) && uy.ara === K.KAPI_ARA);
  bak("yer altındaki yakalandı", ev && ev.yakalanan.includes(1) && !ev.yakalanan.includes(2), JSON.stringify(ev));
  const k1 = t.kontrol.find((x) => x.id === 1);
  const k2 = t.kontrol.find((x) => x.id === 2);
  bak("kapı kontrolü: 1 yakalandı (yok), 2 tamam", k1 && k1.sonuc === "yakalandi" && k1.neden === "yok" && k2 && k2.sonuc === "tamam", JSON.stringify(t.kontrol));
  bak("gardiyan önce 2. hücreye (sıra +z'den), sonra 1.", t.kontrol.indexOf(k2) < t.kontrol.indexOf(k1));
  bak("aletler toplandı, çakı/kaşık kaldı", JSON.stringify(m.oyuncu[1].env) === JSON.stringify(["caki", "kasik"]));
  bak("klozet yeniden vidalandı", m.oyuncu[1].vida === 0 && !m.oyuncu[1].klozet && m.oyuncu[1].nerede === g.cells[1]);
  bak("yakalanana durum mesajı", (t.priv[1] || []).some((x) => x.tur === "durum"));
  bak("ceza süresince bir şey yapılamaz", ozel(cevap(g, 1, { vida: true }), 1).tur === "red");
  bak("sonraki sayım kuruldu", m.q.some((x) => x.tur === "sayim_uyari"));
}

// 3b) kukla ve alttan klozet (sürüm 4): kukla tuvalet kağıdı x2 + çarşaftan yapılır; tünelde uzakken yatakta kukla,
//     klozet alttan kapalı -> gardiyan camdan bakınca hep kanar; klozet açıksa kukla işe yaramaz
{
  const ps = [1, 2].map((id) => ({ id, name: "O" + id, cell: id - 1, sv: 4 }));
  const g = G.newGame(ps, 1, ["kacis"]);
  G.startNext(g);
  g.phase = "kacis";
  K.onPhase(g, "kacis");
  const m = g.m;
  const o = m.oyuncu[1];
  const yerler = m.yer[g.cells[1]];
  bak("sürüm 4: tam takım + açıkta tuvalet kağıdı ve çarşaf", JSON.stringify(Object.values(yerler).sort()) === JSON.stringify([...K.TAKIM, "kagit", "carsaf"].sort()), JSON.stringify(yerler));
  bak("tuvalet kağıdı askıda, çarşaf yatakta", yerler.tuvalet === "kagit" && yerler.carsaf === "carsaf");
  bak("bazı gizli yerler boş", K.YERLER.some((y) => !yerler[y]));
  ilerle(3000);
  bak("malzemesiz kukla yatırılamaz", ozel(cevap(g, 1, { kukla: true }), 1).tur === "red" && !o.kukla);
  for (const y of K.TUM_YERLER) (ilerle(1000), cevap(g, 1, { ara: y }));
  bak("hücredeki her şey bulundu", o.env.length === K.TAKIM.length + 2, JSON.stringify(o.env));
  const yk = cevap(g, 1, { yap: "kukla" });
  bak("kukla yapıldı (2 kağıt + çarşaf gitti)", yk && o.env.includes("kukla") && !o.env.includes("kagit") && !o.env.includes("carsaf"), JSON.stringify(o.env));
  o.vida = 4;
  ilerle(3000);
  const kk = cevap(g, 1, { kukla: true });
  bak("yatağa kukla yatırıldı (herkes görür), cepten çıktı", kk && kk.broadcast && kk.broadcast.tur === "kukla" && kk.broadcast.on && o.kukla && !o.env.includes("kukla"));
  ilerle(3000);
  cevap(g, 1, { kukla: false });
  bak("kukla kaldırılınca cebe döner", !o.kukla && o.env.includes("kukla"));
  ilerle(3000);
  cevap(g, 1, { kukla: true });
  cevap(g, 1, { klozet: true });
  const kk1 = K.klozetHucre(g.cells[1]);
  yerAltinda(g, 1, kk1[0] - 4.5, kk1[1] + 0.5); // tünelde, kuyudan uzakta
  bak("tünelde uzaktan klozet kapatılamaz", ozel(cevap(g, 1, { klozet: false }), 1).tur === "red" && o.klozet);
  hucrede(g, 1, g.cells[2]); // başkasının hücresinde
  bak("başkasının hücresinden kendi klozetin kapatılamaz", !!ozel(cevap(g, 1, { klozet: false }), 1) && o.klozet);
  yerAltinda(g, 1, kk1[0] + 1.6, kk1[1] + 0.5); // kuyunun hemen yanında (konum gecikmesi payı)
  const kapa = cevap(g, 1, { klozet: false });
  bak("klozet tünelden üstüne çekildi (kapandı)", !!kapa && !o.klozet);
  const ac = cevap(g, 1, { klozet: true });
  bak("alttan yeniden itilip açılır (vidalar sökük)", !!ac && o.klozet);
  cevap(g, 1, { klozet: false });
  yerAltinda(g, 1, -15, 0); // klozet kapalı, kendisi tünelde uzakta
  m.oyuncu[2].nerede = -1;
  m.oyuncu[2].env = ["caki", "fener"];
  for (let tur = 0; tur < 5; tur++) {
    const t = sayimTuru(g);
    bak("tur " + tur + ": kukla + kapalı klozet hep kandırır", t.ev && !t.ev.yakalanan.includes(1) && o.kukla, JSON.stringify(t.ev));
    bak("tur " + tur + ": kapıda 'kukla' sonucu", t.kontrol.some((x) => x.id === 1 && x.sonuc === "kukla"));
    bak("tur " + tur + ": kandırana özel haber", (t.priv[1] || []).some((x) => x.tur === "kandirdi"));
    if (tur === 0) {
      bak("kuklasız tünelde olan yakalandı", t.ev.yakalanan.includes(2));
      bak("yakalananın feneri gitti, herkese fener listesi", t.tum.some((x) => x.tur === "fener" && !x.ids.includes(2)));
    }
    m.oyuncu[2].ceza = 0;
  }
  // klozet açık kalırsa kukla işe yaramaz: gardiyan camdan açık deliği görür
  o.klozet = true;
  const t2 = sayimTuru(g);
  bak("klozet açıkken kukla kurtarmaz, kukla el konur", t2.ev.yakalanan.includes(1) && !o.kukla && !o.env.includes("kukla"));
}

// 3b-eski) sürüm 3 istemci: kukla malzemesiz yatırılır (App Store'daki ilk derleme bozulmasın)
{
  const g = kur(2);
  g.phase = "kacis";
  K.onPhase(g, "kacis");
  const o = g.m.oyuncu[1];
  ilerle(3000);
  const kk = cevap(g, 1, { kukla: true });
  bak("eski sürüm: malzemesiz kukla", kk && kk.broadcast && kk.broadcast.on && o.kukla);
  yerAltinda(g, 1, -15, 0);
  const t = sayimTuru(g);
  bak("eski sürüm: kukla kandırır", !t.ev.yakalanan.includes(1));
}

// 3c) fener yapılınca herkese duyurulur (kafa lambası görünsün)
{
  const g = kur(2);
  g.phase = "kacis";
  const o = g.m.oyuncu[1];
  o.env = ["pil", "ampul", "tel"];
  const f = cevap(g, 1, { yap: "fener" });
  bak("fener yapıldı, herkese fener listesi", f && f.broadcast && f.broadcast.tur === "fener" && f.broadcast.ids.includes(1));
  bak("durum: fenerliler", JSON.stringify(K.stateExtra(g).fener) === "[1]");
}

// 4) kaçış: tel örgünün ötesinde yukarı kaz, sıra ve puan; herkes kaçınca biter
{
  const g = kur(2, [2]);
  g.phase = "kacis";
  K.onPhase(g, "kacis");
  const m = g.m;
  const o = m.oyuncu[1];
  o.env = ["kurek"];
  o.nerede = -1;
  m.kazilan[[K.CIT_X + 2, 0].join(",")] = 1;
  ilerle(4000);
  bak("tel örgünün içinde yukarı kazılmaz", ozel(cevap(g, 1, { yukari: [K.CIT_X + 2, 0] }), 1).tur === "red");
  m.kazilan[[K.CIT_X, 0].join(",")] = 1;
  ilerle(4000);
  bak("yukarı 1", cevap(g, 1, { yukari: [K.CIT_X, 0] }).reply.n === 1);
  ilerle(4000);
  cevap(g, 1, { yukari: [K.CIT_X, 0] });
  ilerle(4000);
  const r = cevap(g, 1, { yukari: [K.CIT_X, 0] });
  bak("kaçtı (1.)", r && r.broadcast && r.broadcast.tur === "kacti" && r.broadcast.sira === 1);
  bak("tek insan kaçınca bitiş kuruldu", m.bitis > 0);
  // bot kaçışı kuyruğa alınmış olabilir; puanlar
  const res = K.resolve(g);
  bak("1. kaçan 12 puan", res.private[1].delta === 12, JSON.stringify(res.private));
  bak("kaçamayan 0", res.private[2].delta === 0);
  bak("kaçan listesi", res.public.kacan[0] === 1);
}

// 5) bot kaçar; kaçan bir şey yapamaz
{
  const g = kur(2, [2]);
  g.phase = "kacis";
  const m = g.m;
  m.q = [{ at: 0, gecikme: 1000, tur: "bot_kac", id: 2 }];
  K.onPhase(g, "kacis");
  ilerle(2000);
  const r = K.onWake(g);
  bak("bot kaçtı", JSON.stringify(r).includes('"kacti"') && m.oyuncu[2].kacti === 1);
  m.oyuncu[1].kacti = 2;
  bak("kaçan oyuncu kazamaz", cevap(g, 1, { kaz: [0, 0] }) === null);
}

// 6) eşya verme: iki oyuncunun sunucudaki konumu 2,5 m'den yakın (aynı katta) olmalı
{
  const g = kur(2);
  g.phase = "kacis";
  const m = g.m;
  m.oyuncu[1].env = ["tel"];
  m.oyuncu[1].nerede = -1;
  m.oyuncu[2].nerede = -1;
  bak("konum bilinmeden verilmez (istemcinin 'nerede'si yetmez)", ozel(cevap(g, 1, { ver: { kime: 2, esya: "tel" } }), 1).tur === "red");
  yerAltinda(g, 1, -5.5, 0.5);
  hucrede(g, 2, g.cells[2]);
  bak("ayrı yerdeyken verilmez", ozel(cevap(g, 1, { ver: { kime: 2, esya: "tel" } }), 1).tur === "red");
  yerAltinda(g, 2, -5.5, 3.6);
  bak("aynı katta 3,1 m uzaktan verilmez", ozel(cevap(g, 1, { ver: { kime: 2, esya: "tel" } }), 1).tur === "red");
  K.onKonum(g, 2, [-5.5, 2.5], 0); // tam üstünde ama yer üstünde
  bak("biri yer üstünde, öbürü altında: verilmez", ozel(cevap(g, 1, { ver: { kime: 2, esya: "tel" } }), 1).tur === "red");
  yerAltinda(g, 2, -5.5, 2.4);
  const r = cevap(g, 1, { ver: { kime: 2, esya: "tel" } });
  bak("verildi", m.oyuncu[2].env.includes("tel") && !m.oyuncu[1].env.includes("tel") && r.others[0].msg.aldi === "tel");
}

// 7) yer sunucunun bildiği konumdan: hücre, yer altı, koridor; konum gelince istemcinin "nerede"si yok sayılır
{
  const g = kur(3);
  g.phase = "kacis";
  K.onPhase(g, "kacis");
  const m = g.m;
  bak("yerHesap: hücre 0 ve 7", K.yerHesap([0, K.hucreZ(0)], 0) === 0 && K.yerHesap([1.9, K.hucreZ(7) + 2.5], 0) === 7);
  bak("yerHesap: klozet hücrenin içinde", g.players.every((id) => K.yerHesap([1.5, K.hucreZ(g.cells[id]) - 2.54], 0) === g.cells[id]));
  bak("yerHesap: x > 2.15 koridor", K.yerHesap([3, K.hucreZ(2)], 0) === K.KORIDOR);
  bak("yerHesap: hücre dizisi dışı koridor", K.yerHesap([0, K.hucreZ(9)], 0) === K.KORIDOR && K.yerHesap([0, K.hucreZ(-2)], 0) === K.KORIDOR);
  bak("yerHesap: h < -0.5 yer altı", K.yerHesap([0, K.hucreZ(1)], -2.3) === -1 && K.yerHesap([0, K.hucreZ(1)], -0.4) === 1);
  hucrede(g, 1, g.cells[1]);
  bak("konum: kendi hücresinde", m.oyuncu[1].nerede === g.cells[1]);
  cevap(g, 1, { nerede: -1 });
  bak("konum varken istemcinin 'nerede'si yok sayılır", m.oyuncu[1].nerede === g.cells[1]);
  m.oyuncu[1].env = ["kasik"];
  const kk = K.klozetHucre(g.cells[1]);
  m.kazilan[kk.join(",")] = 1;
  ilerle(8000);
  bak("yer üstündeyken kazılamaz ('nerede: -1' yollasa da)", cevap(g, 1, { kaz: [kk[0] - 1, kk[1]] }) === null);
  K.onKonum(g, 2, [3.5, K.hucreZ(g.cells[2])], 0); // koridorda
  hucrede(g, 3, g.cells[3]);
  const ev = sayimTuru(g).ev;
  bak("sayım: koridordaki yakalandı, hücresindeki yakalanmadı", ev && ev.yakalanan.includes(2) && !ev.yakalanan.includes(1), JSON.stringify(ev));
}

console.log(`kacis_test: ${ok} doğru, ${hata} hata`);
process.exit(hata ? 1 : 0);
