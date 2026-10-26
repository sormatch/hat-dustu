// Mağaza (market.js) testleri:  cd server && node test/market_test.mjs
// 1) Birim: market.js saf işlevleri (vitrin, set fiyatı, kasa güvencesi, seviye yolu).
// 2) Hesap nesnesi (accounts.js) sahte Durable Object ile (node:sqlite): satın alma, set, kasa, istek listesi,
//    seviye yolu, hediye sınırları, yetersiz elmas, eşzamanlı istekler. Gerçek SQL ve gerçek mesaj işleyici çalışır.
// 3) Yerel sunucu açıksa (ws://127.0.0.1:8794, SRV ile değişir) uçtan uca kısa deneme. Kapalıysa atlanır.
import { DatabaseSync } from "node:sqlite";
import * as E from "../src/ekonomi.js";
import * as M from "../src/market.js";

let ok = 0;
let hata = 0;
function bak(ad, kosul, ek = "") {
  if (kosul) {
    ok++;
    if (process.env.V) console.log("  OK   " + ad);
  } else {
    hata++;
    console.log("  HATA " + ad + (ek ? "  -> " + ek : ""));
  }
}

// ---------------- 1) birim ----------------
{
  const v1 = M.gunluk("2026-10-26");
  const v2 = M.gunluk("2026-10-26");
  const v3 = M.gunluk("2026-10-27");
  bak("vitrin 6 eşya", v1.length === M.VITRIN_ADET);
  bak("vitrin herkese aynı (tarih tohumlu)", JSON.stringify(v1) === JSON.stringify(v2));
  bak("vitrin ertesi gün değişir", JSON.stringify(v1) !== JSON.stringify(v3));
  bak("vitrinde tekrar yok", new Set(v1.map((x) => x[0] + ":" + x[1])).size === v1.length);
  bak("vitrinin ilki epik/efsane", E.rarity(v1[0][2]) >= 2);
  bak("vitrin fiyatları indirimli ve 5'in katı", v1.every((x) => x[4] < x[2] && x[4] % 5 === 0 && x[4] >= 5));
  bak("fiyatSimdi vitrindeki eşyada indirimli", M.fiyatSimdi(v1[1][0], v1[1][1], "2026-10-26") === v1[1][4]);
  const h = M.hafta(Date.UTC(2026, 9, 26, 0, 0, 0)); // pazartesi 03:00 TR
  const h2 = M.hafta(Date.UTC(2026, 10, 1, 20, 59, 0)); // pazar 23:59 TR
  const h3 = M.hafta(Date.UTC(2026, 10, 1, 21, 0, 1)); // pazartesi 00:00 TR
  bak("hafta pazartesi başlar", h.no === h2.no && h3.no === h.no + 7, JSON.stringify([h, h2, h3]));
  bak("hafta kalan süre", h2.kalan === 60 && h3.kalan > 7 * 86400 - 5, JSON.stringify([h2.kalan, h3.kalan]));
  bak("gün kalan süre (TR)", M.gunKalan(Date.UTC(2026, 9, 26, 20, 59, 0)) === 60);
  bak("geçerli setler", M.gecerliSetler().length >= 6 && M.gecerliSetler().every((s) => M.setParcalari(s).length >= 2));

  // her set: tek kimlik, bütün parçalar mağazada (ücretli), aynı kategoriden iki parça yok (biri ötekini çıkarırdı)
  bak("set kimlikleri tekil", new Set(M.SETLER.map((s) => s.k)).size === M.SETLER.length);
  for (const s of M.SETLER) {
    bak("set parçaları geçerli: " + s.k, M.setParcalari(s).length === s.parcalar.length, JSON.stringify(s.parcalar));
    bak("set kategorileri tekil: " + s.k, new Set(s.parcalar.map((p) => p[0])).size === s.parcalar.length);
  }
  for (const k of ["gardiyan", "kovboy", "firar"]) bak("yeni set var: " + k, M.gecerliSetler().some((s) => s.k === k));

  // set fiyatı: sahip olunan parçalar düşülür
  const kacak = M.SETLER.find((s) => s.k === "kacak");
  const tam = M.setParcalari(kacak).reduce((a, x) => a + x[2], 0);
  const f0 = M.setFiyat(kacak, []);
  bak("set fiyatı = toplam - %30 (5'e yuvarlı)", f0.fiyat === Math.round((tam * 0.7) / 5) * 5 && f0.fiyat < tam, `${f0.fiyat} / ${tam}`);
  const f1 = M.setFiyat(kacak, ["kiyafet:cizgili"]);
  const kalanTop = tam - E.price("kiyafet", "cizgili");
  bak("sahip olunan parça fiyattan düşer", f1.fiyat === Math.round((kalanTop * 0.7) / 5) * 5 && f1.kalan.length === 3, `${f1.fiyat}`);
  const fHepsi = M.setFiyat(kacak, M.setParcalari(kacak).map(([c, i]) => c + ":" + i));
  bak("hepsi sendeyse fiyat 0", fHepsi.fiyat === 0 && fHepsi.kalan.length === 0);
  const fOne = M.setFiyat(kacak, [], true);
  bak("haftanın seti ek indirimli", fOne.fiyat < f0.fiyat && fOne.indirim === kacak.indirim + M.ONE_CIKAN_EK);
  bak("haftanın seti herkese aynı", M.haftaninSeti(Date.UTC(2026, 9, 27)).k === M.haftaninSeti(Date.UTC(2026, 9, 29)).k);

  // kasa güvencesi: 9 kasa boyunca hep sıradan gelse bile 10. kasa en az epik
  const hepSiradan = () => 0.0; // ağırlıkta hep ilk kademe
  let sayac = 0;
  let r;
  for (let i = 0; i < 9; i++) {
    r = M.kasaCek("tahta", [], sayac, hepSiradan);
    sayac = r.sayac;
  }
  bak("9 kasa sıradan, sayaç 9", r.rarity === 0 && sayac === 9, JSON.stringify(r));
  r = M.kasaCek("tahta", [], sayac, hepSiradan);
  bak("10. kasa en az EPİK (güvence)", r.rarity >= 2 && r.garanti && r.sayac === 0, JSON.stringify(r));
  // doğal epik sayacı sıfırlar
  const r2 = M.kasaCek("tahta", [], 5, () => 0.995); // ağırlığın sonu: efsane
  bak("doğal efsane sayacı sıfırlar", r2.rarity === 3 && r2.sayac === 0 && !r2.garanti);
  // altın kasa güvencesi efsane
  let sa = 0;
  let ra;
  for (let i = 0; i < 10; i++) {
    ra = M.kasaCek("altin", [], sa, hepSiradan);
    sa = ra.sayac;
  }
  bak("altın kasada 10. kasa EFSANE", ra.rarity === 3 && ra.garanti, JSON.stringify(ra));
  // rastgele 2000 kasada güvence hiç aşılmaz
  let maxSeri = 0;
  let seri = 0;
  sayac = 0;
  for (let i = 0; i < 2000; i++) {
    const x = M.kasaCek("tahta", [], sayac);
    sayac = x.sayac;
    seri = x.rarity >= 2 ? 0 : seri + 1;
    maxSeri = Math.max(maxSeri, seri);
  }
  bak("2000 kasada epiksiz seri en fazla 9", maxSeri <= 9, String(maxSeri));
  const ol = M.olasiliklar();
  bak("olasılıklar yüzde toplamı 100", Math.abs(ol.tahta.yuzde.reduce((a, b) => a + b, 0) - 100) < 0.2 && ol.tahta.guvence.n === 10);
  // seviye yolu
  bak("seviye 1 ödülsüz", M.yolOdul(1) === null);
  bak("seviye 10 altın kasa", M.yolOdul(10).tur === "kasa" && M.yolOdul(10).kasa === "altin");
  bak("seviye 5 eşya", M.yolOdul(5).tur === "esya" && E.price(M.yolOdul(5).kat, M.yolOdul(5).id) > 0);
  bak("seviye 3 tahta kasa", M.yolOdul(3).kasa === "tahta");
  bak("seviye 2 elmas", M.yolOdul(2).tur === "elmas" && M.yolOdul(2).n > 0);
  bak("yüksek seviyelerde de ödül var", [99, 100, 101, 205].every((s) => M.yolOdul(s)));
}

// ---------------- 2) hesap nesnesi (sahte Durable Object) ----------------
globalThis.WebSocketRequestResponsePair = class {
  constructor(a, b) {
    this.a = a;
    this.b = b;
  }
};
const { Accounts } = await import("../src/accounts.js");

function sahteDO() {
  const db = new DatabaseSync(":memory:");
  const sql = {
    exec(q, ...args) {
      const st = db.prepare(q);
      const okur = /^\s*(SELECT|WITH)/i.test(q) || /RETURNING/i.test(q);
      const rows = okur ? st.all(...args) : (st.run(...args), []);
      return { toArray: () => rows };
    },
  };
  const socks = [];
  return { storage: { sql }, setWebSocketAutoResponse() {}, getWebSockets: () => socks, socks };
}

class SahteWS {
  constructor(st, token, handle) {
    this.att = { token, handle: handle || "", room: "" };
    this.msgs = [];
    st.socks.push(this);
  }
  send(s) {
    this.msgs.push(JSON.parse(s));
  }
  deserializeAttachment() {
    return this.att;
  }
  serializeAttachment(a) {
    this.att = a;
  }
  close() {}
  son(t) {
    for (let i = this.msgs.length - 1; i >= 0; i--) if (this.msgs[i].t === t) return this.msgs[i];
    return null;
  }
  temizle() {
    this.msgs = [];
  }
}

const st = sahteDO();
const acc = new Accounts(st, { ODEME_TEST: "0", SPAM_SINIRI: "0" }); // test art arda çok mesaj yollar
let n = 0;
function oyuncu(handle, { gems = 1000, xp = 0 } = {}) {
  const token = "tok" + String(++n).padStart(20, "0");
  acc.sql.exec(`INSERT INTO users (token, handle, name) VALUES (?, ?, ?)`, token, handle || null, handle || null);
  const e = acc.eco(token);
  e.gems = gems;
  e.xp = xp;
  acc.saveEco(token, e);
  const ws = new SahteWS(st, token, handle);
  return { token, ws, gonder: (d) => (ws.temizle(), acc.webSocketMessage(ws, JSON.stringify(d))), eco: () => acc.eco(token) };
}
const sonHata = (p) => p.ws.son("hata");

{
  // ---- ekonomi özeti
  const a = oyuncu("ali");
  await a.gonder({ t: "ekonomi" });
  const ek = a.ws.son("ekonomi");
  bak("özet: vitrin 6 + firsatlar", ek && ek.vitrin.gunluk.length === 6 && ek.firsatlar.length === 6);
  bak("özet: setler, pity, olasılık, yol", ek.setler.length >= 6 && ek.pity.tahta.kalan === 10 && ek.olasilik.altin && ek.yol.length >= 29);
  bak("özet: geri sayımlar", ek.vitrin.gun_kalan > 0 && ek.vitrin.hafta_kalan >= ek.vitrin.gun_kalan);
  bak("özet: haftanın seti işaretli", ek.setler.filter((s) => s.one_cikan).length === 1);

  // ---- satın alma: vitrin fiyatı, yetersiz elmas, fiyat değişti
  const v = M.gunluk()[1];
  const b = oyuncu("bulut", { gems: v[4] });
  await b.gonder({ t: "satin_al", kat: v[0], id: v[1], fiyat: v[2] });
  bak("vitrin eşyası indirimli fiyattan alınır", b.ws.son("satin_alindi") && b.eco().gems === 0, JSON.stringify(b.ws.msgs.slice(0, 1)));
  await b.gonder({ t: "satin_al", kat: v[0], id: v[1] });
  bak("aynı eşya iki kez alınmaz", sonHata(b) && sonHata(b).m.includes("zaten"));
  const fakir = oyuncu("fakir", { gems: 10 });
  await fakir.gonder({ t: "satin_al", kat: "sapka", id: "tac" });
  bak("yetersiz elmas: satın alma reddedilir", sonHata(fakir) && sonHata(fakir).m === "Elmas yetmiyor." && fakir.eco().gems === 10);
  const tacFiyat = M.fiyatSimdi("sapka", "tac");
  const c = oyuncu("cem", { gems: 5000 });
  await c.gonder({ t: "satin_al", kat: "sapka", id: "tac", fiyat: tacFiyat - 5 });
  bak("telefonun gördüğünden pahalıysa reddedilir", sonHata(c) && sonHata(c).m.includes("Fiyat değişti") && c.eco().gems === 5000);
  await c.gonder({ t: "satin_al", kat: "sapka", id: "yok" });
  bak("bedava eşya satılmaz", sonHata(c) && sonHata(c).m.includes("satılmıyor"));
  await c.gonder({ t: "satin_al", kat: "sapka", id: "uydurma" });
  bak("olmayan eşya satılmaz", sonHata(c) && sonHata(c).m.includes("satılmıyor"));

  // ---- eşzamanlı satın alma: 1 eşyalık elmasla 5 istek aynı anda
  const p = E.price("kiyafet", "leopar");
  const es = oyuncu("esz", { gems: M.fiyatSimdi("kiyafet", "leopar") + 1 });
  es.ws.temizle();
  await Promise.all([0, 1, 2, 3, 4].map(() => acc.webSocketMessage(es.ws, JSON.stringify({ t: "satin_al", kat: "kiyafet", id: "leopar" }))));
  const alinan = es.ws.msgs.filter((m) => m.t === "satin_alindi").length;
  bak("eşzamanlı 5 istekte tek satın alma", alinan === 1 && es.eco().gems === 1 && es.eco().items.filter((k) => k === "kiyafet:leopar").length === 1, `${alinan} ${es.eco().gems} ${p}`);

  // ---- set
  const set = M.gecerliSetler().find((s) => s.k !== (M.haftaninSeti() || {}).k);
  const parca = M.setParcalari(set);
  const s1 = oyuncu("setci", { gems: 5000 });
  const e1 = s1.eco();
  e1.items.push(parca[0][0] + ":" + parca[0][1]);
  acc.saveEco(s1.token, e1);
  const beklenen = M.setFiyat(set, e1.items).fiyat;
  await s1.gonder({ t: "set_al", k: set.k, fiyat: beklenen });
  const sa = s1.ws.son("set_alindi");
  bak("set alınır, sahip olunan parça fiyattan düşer", sa && sa.fiyat === beklenen && s1.eco().gems === 5000 - beklenen && sa.parcalar.length === parca.length - 1, JSON.stringify(sa));
  bak("setin tüm parçaları hesapta", parca.every(([c2, i]) => s1.eco().items.includes(c2 + ":" + i)));
  bak("parçalar çift eklenmez", s1.eco().items.filter((k) => k === parca[0][0] + ":" + parca[0][1]).length === 1);
  await s1.gonder({ t: "set_al", k: set.k });
  bak("hepsi sendeyse set alınmaz", sonHata(s1) && sonHata(s1).m.includes("hepsi sende"));
  const s2 = oyuncu("setfakir", { gems: 20 });
  await s2.gonder({ t: "set_al", k: set.k });
  bak("set: yetersiz elmas", sonHata(s2) && sonHata(s2).m === "Elmas yetmiyor." && s2.eco().items.length === 0);
  await s2.gonder({ t: "set_al", k: "yok_boyle" });
  bak("olmayan set", sonHata(s2) && sonHata(s2).m.includes("set yok"));
  const s3 = oyuncu("setesz", { gems: M.setFiyat(set, []).fiyat });
  s3.ws.temizle();
  await Promise.all([1, 2, 3].map(() => acc.webSocketMessage(s3.ws, JSON.stringify({ t: "set_al", k: set.k }))));
  bak("eşzamanlı set alımı tek sefer", s3.ws.msgs.filter((m) => m.t === "set_alindi").length === 1 && s3.eco().gems === 0);
  const hs = M.haftaninSeti();
  const s4 = oyuncu("haftaset", { gems: 5000 });
  await s4.gonder({ t: "set_al", k: hs.k });
  bak("haftanın seti ek indirimle satılır", s4.ws.son("set_alindi").fiyat === M.setFiyat(hs, [], true).fiyat);

  // ---- kasa: güvence sayacı sunucuda tutulur
  const k = oyuncu("kasaci", { gems: 100000 });
  let epikVar = false;
  let enUzun = 0;
  let seri = 0;
  for (let i = 0; i < 60; i++) {
    await k.gonder({ t: "kasa_ac", kasa: "tahta" });
    const r = k.ws.son("kasa_sonuc");
    if (!r) break;
    seri = r.nadirlik >= 2 ? 0 : seri + 1;
    enUzun = Math.max(enUzun, seri);
    if (r.garanti) epikVar = true;
  }
  const ke = k.ws.son("ekonomi");
  bak("kasa: 60 açılışta epiksiz seri ≤ 9", enUzun <= 9, String(enUzun));
  bak("kasa: sayaç özette", ke && ke.pity.tahta.sayac === seri && ke.pity.tahta.kalan === 10 - seri, JSON.stringify(ke && ke.pity));
  bak("kasa: elmas düşer", k.eco().gems <= 100000 - 60 * 100 + 60 * 300);
  const kf = oyuncu("kasafakir", { gems: 99 });
  await kf.gonder({ t: "kasa_ac", kasa: "tahta" });
  bak("kasa: yetersiz elmas", sonHata(kf) && kf.eco().gems === 99 && kf.eco().items.length === 0);
  await kf.gonder({ t: "kasa_ac", kasa: "tahta", hak: true });
  bak("kasa: ücretsiz hak yoksa açılmaz", sonHata(kf) && sonHata(kf).m.includes("Ücretsiz"));
  await kf.gonder({ t: "kasa_ac", kasa: "nadir" });
  bak("kasa: hediye kasa hakkı yoksa açılmaz", sonHata(kf) && sonHata(kf).m.includes("Hediye kasan"));
  const ke2 = oyuncu("kasaesz", { gems: 100 });
  ke2.ws.temizle();
  await Promise.all([1, 2, 3, 4].map(() => acc.webSocketMessage(ke2.ws, JSON.stringify({ t: "kasa_ac", kasa: "tahta" }))));
  bak("eşzamanlı kasa: 100 elmasla tek kasa", ke2.ws.msgs.filter((m) => m.t === "kasa_sonuc").length === 1 && ke2.eco().gems >= 0);

  // ---- seviye yolu
  const y = oyuncu("yolcu", { gems: 0, xp: 0 });
  await y.gonder({ t: "yol_al", s: 2 });
  bak("yol: seviye yetmezse alınmaz", sonHata(y) && y.eco().gems === 0);
  const ey = y.eco();
  ey.xp = 2000; // seviye 6 civarı
  acc.saveEco(y.token, ey);
  const lv = E.levelOf(2000).seviye;
  await y.gonder({ t: "ekonomi" });
  bak("yol: alınabilir sayısı", y.ws.son("ekonomi").yol_hazir === lv - 1, `${y.ws.son("ekonomi").yol_hazir} ${lv}`);
  await y.gonder({ t: "yol_al", s: 2 });
  bak("yol: elmas ödülü", y.ws.son("yol_alindi") && y.eco().gems === M.yolOdul(2).n);
  await y.gonder({ t: "yol_al", s: 2 });
  bak("yol: aynı ödül iki kez alınmaz", sonHata(y) && y.eco().gems === M.yolOdul(2).n);
  await y.gonder({ t: "yol_al", s: 3 });
  bak("yol: kasa hakkı verilir", y.eco().stats.kasa_hak.tahta === 1);
  await y.gonder({ t: "kasa_ac", kasa: "tahta", hak: true });
  const yk = y.ws.son("kasa_sonuc");
  bak("yol: ücretsiz kasa elmas harcamadan açılır", yk && yk.bedava && y.eco().stats.kasa_hak.tahta === 0 && y.eco().gems >= M.yolOdul(2).n);
  const o5 = M.yolOdul(5);
  await y.gonder({ t: "yol_al", s: 5 });
  bak("yol: eşya ödülü", y.eco().items.includes(o5.kat + ":" + o5.id) || y.ws.son("yol_alindi").odul.kopya);
  await y.gonder({ t: "yol_al", s: 999 });
  bak("yol: ileri seviye alınmaz", !!sonHata(y));
  await y.gonder({ t: "yol_al", s: "abc" });
  bak("yol: bozuk seviye", !!sonHata(y));
  // eşya zaten sendeyse elmas
  const y2 = oyuncu("yolcu2", { gems: 0, xp: 2000 });
  const ey2 = y2.eco();
  ey2.items.push(o5.kat + ":" + o5.id);
  acc.saveEco(y2.token, ey2);
  await y2.gonder({ t: "yol_al", s: 5 });
  bak("yol: sahip olunan eşya yerine elmas", y2.ws.son("yol_alindi").odul.kopya && y2.eco().gems > 0);
  // eşzamanlı yol
  const y3 = oyuncu("yolcu3", { gems: 0, xp: 2000 });
  y3.ws.temizle();
  await Promise.all([1, 2, 3].map(() => acc.webSocketMessage(y3.ws, JSON.stringify({ t: "yol_al", s: 2 }))));
  bak("yol: eşzamanlı alımda tek ödül", y3.eco().gems === M.yolOdul(2).n);

  // ---- istek listesi
  const w = oyuncu("istekli");
  const vit = M.gunluk();
  await w.gonder({ t: "istek_listesi", kat: vit[2][0], id: vit[2][1], ekle: true });
  await w.gonder({ t: "istek_listesi", kat: "sapka", id: "yok", ekle: true });
  bak("istek: bedava eşya eklenmez", !!sonHata(w));
  await w.gonder({ t: "ekonomi" });
  let we = w.ws.son("ekonomi");
  bak("istek: listede ve vitrinde", we.istek.includes(vit[2][0] + ":" + vit[2][1]) && we.istek_vitrinde.length === 1 && we.istek_yeni === 1);
  await w.gonder({ t: "vitrin_bakti" });
  we = w.ws.son("ekonomi");
  bak("istek: vitrine bakınca rozet söner", we.istek_yeni === 0 && we.istek_vitrinde.length === 1);
  await w.gonder({ t: "istek_listesi", kat: vit[2][0], id: vit[2][1], ekle: false });
  bak("istek: çıkarılır", w.ws.son("ekonomi").istek.length === 0);
  for (let i = 0; i < 45; i++) {
    const it = E.shopItems()[i];
    await w.gonder({ t: "istek_listesi", kat: it[0], id: it[1], ekle: true });
  }
  bak("istek: en fazla 40", w.eco().stats.istek.length === M.ISTEK_MAX);

  // ---- hediye
  const g1 = oyuncu("gonderen", { gems: 3000, xp: 2000 });
  const g2 = oyuncu("alan", { gems: 0 });
  const yabanci = oyuncu("yabanci", { gems: 0 });
  acc.makeFriends("gonderen", "alan");
  await g1.gonder({ t: "hediye", handle: "yabanci", kat: "sapka", id: "bere" });
  bak("hediye: arkadaş olmayana gitmez", sonHata(g1) && sonHata(g1).m.includes("arkadaş") && g1.eco().gems === 3000);
  const dusuk = oyuncu("dusuk", { gems: 3000, xp: 0 });
  acc.makeFriends("dusuk", "alan");
  await dusuk.gonder({ t: "hediye", handle: "alan", kat: "sapka", id: "bere" });
  bak("hediye: düşük seviye gönderemez", sonHata(dusuk) && sonHata(dusuk).m.includes("seviye") && dusuk.eco().gems === 3000);
  const misafir = oyuncu(null, { gems: 3000, xp: 5000 });
  await misafir.gonder({ t: "hediye", handle: "alan", kat: "sapka", id: "bere" });
  bak("hediye: misafir gönderemez", sonHata(misafir) && misafir.eco().gems === 3000);
  await g1.gonder({ t: "hediye", handle: "gonderen", kat: "sapka", id: "bere" });
  bak("hediye: kendine gönderemez", !!sonHata(g1));
  const bereF = M.fiyatSimdi("sapka", "bere");
  g2.ws.temizle();
  await g1.gonder({ t: "hediye", handle: "@Alan", kat: "sapka", id: "bere" });
  bak("hediye: gider, elmas gönderenden düşer", g1.ws.son("hediye_gitti") && g1.eco().gems === 3000 - bereF && g2.eco().items.includes("sapka:bere"), JSON.stringify(g1.ws.msgs[0]));
  bak("hediye: alan oyuncu bildirim alır", g2.ws.son("hediye_geldi") && g2.ws.son("hediye_geldi").handle === "gonderen" && g2.eco().gems === 0);
  bak("hediye: alıcının elması değişmez", g2.eco().gems === 0);
  await g1.gonder({ t: "hediye", handle: "alan", kat: "sapka", id: "bere" });
  bak("hediye: alıcıda zaten varsa gitmez", sonHata(g1) && sonHata(g1).m.includes("zaten sahip") && g1.eco().gems === 3000 - bereF);
  await g1.gonder({ t: "hediye", handle: "alan", kat: "sapka", id: "yok" });
  bak("hediye: bedava eşya hediye edilmez", !!sonHata(g1));
  await g1.gonder({ t: "hediye", handle: "alan", kat: "aksesuar", id: "bant" });
  await g1.gonder({ t: "hediye", handle: "alan", kat: "aksesuar", id: "kurdan" });
  const gun = g1.eco().gems;
  await g1.gonder({ t: "hediye", handle: "alan", kat: "aksesuar", id: "maske" });
  bak("hediye: günlük sınır (3)", sonHata(g1) && sonHata(g1).m.includes("en fazla") && g1.eco().gems === gun && !g2.eco().items.includes("aksesuar:maske"));
  await g1.gonder({ t: "ekonomi" });
  bak("hediye: özet kalan 0", g1.ws.son("ekonomi").hediye.kalan === 0);
  // alıcı sınırı: 3 ayrı gönderen + 3 = 6 > 5
  const alici = oyuncu("alici2", { gems: 0 });
  const gonderenler = [];
  for (let i = 0; i < 2; i++) {
    const gg = oyuncu("gg" + i, { gems: 5000, xp: 2000 });
    acc.makeFriends("gg" + i, "alici2");
    gonderenler.push(gg);
  }
  const hedefler = E.shopItems().filter(([, , pr]) => pr <= 60).slice(0, 6);
  let gitti = 0;
  for (let i = 0; i < 6; i++) {
    const gg = gonderenler[Math.floor(i / 3)];
    await gg.gonder({ t: "hediye", handle: "alici2", kat: hedefler[i][0], id: hedefler[i][1] });
    if (gg.ws.son("hediye_gitti")) gitti++;
  }
  bak("hediye: alıcı günde en fazla 5", gitti === M.HEDIYE.alici_gunluk && alici.eco().items.length === 5, String(gitti));
  // yetersiz elmas
  const gz = oyuncu("gzfakir", { gems: 5, xp: 2000 });
  acc.makeFriends("gzfakir", "alan");
  await gz.gonder({ t: "hediye", handle: "alan", kat: "sapka", id: "tac" });
  bak("hediye: yetersiz elmas", sonHata(gz) && sonHata(gz).m === "Elmas yetmiyor." && !g2.eco().items.includes("sapka:tac"));
  // engel
  const ge = oyuncu("engelli", { gems: 3000, xp: 2000 });
  acc.makeFriends("engelli", "alan");
  acc.sql.exec(`INSERT INTO blocks (a, b) VALUES (?, ?)`, g2.token, "engelli");
  await ge.gonder({ t: "hediye", handle: "alan", kat: "sapka", id: "kep" });
  bak("hediye: engelleyene gitmez", !!sonHata(ge) && ge.eco().gems === 3000);
  // eşzamanlı: günlük sınırı aşamaz
  const ges = oyuncu("gesz", { gems: 9000, xp: 2000 });
  const alici3 = oyuncu("alici3", { gems: 0 });
  acc.makeFriends("gesz", "alici3");
  ges.ws.temizle();
  await Promise.all(hedefler.map(([kk, ii]) => acc.webSocketMessage(ges.ws, JSON.stringify({ t: "hediye", handle: "alici3", kat: kk, id: ii }))));
  bak("hediye: eşzamanlı isteklerde günlük sınır korunur", ges.ws.msgs.filter((m2) => m2.t === "hediye_gitti").length === 3 && alici3.eco().items.length === 3);
  // çevrimdışı alıcı: bağlanınca bildirilir
  const cev = oyuncu("cevrimdisi", { gems: 0 });
  st.socks.splice(st.socks.indexOf(cev.ws), 1);
  const gc = oyuncu("gc", { gems: 3000, xp: 2000 });
  acc.makeFriends("gc", "cevrimdisi");
  await gc.gonder({ t: "hediye", handle: "cevrimdisi", kat: "sapka", id: "kep" });
  const bekleyen = acc.rows(`SELECT goruldu FROM gifts WHERE to_token = ?`, cev.token);
  bak("hediye: çevrimdışı alıcıya kayıt", bekleyen.length === 1 && bekleyen[0].goruldu === 0);
  const yeniWs = new SahteWS(st, cev.token, "cevrimdisi");
  M.bekleyenHediyeler(acc, yeniWs, cev.token);
  bak("hediye: bağlanınca bildirilir (bir kez)", yeniWs.son("hediye_geldi") && acc.rows(`SELECT goruldu FROM gifts WHERE to_token = ?`, cev.token)[0].goruldu === 1);
  // hesap silinince alıcı kayıtları silinir
  acc.deleteAccount(cev.token);
  bak("hesap silme: gelen hediye kayıtları silinir", acc.rows(`SELECT 1 FROM gifts WHERE to_token = ?`, cev.token).length === 0);

  // ---- arkadaşlık isteği ("istek") mağazanın istek listesine ("istek_listesi") karışmaz
  const f1 = oyuncu("arkadas1");
  const f2 = oyuncu("arkadas2");
  await f1.gonder({ t: "istek", handle: "arkadas2" });
  const arkSor = (durum) => acc.rows(`SELECT 1 FROM friends WHERE a = 'arkadas1' AND b = 'arkadas2' AND status = ?`, durum).length;
  bak("arkadaşlık isteği hâlâ çalışır", arkSor("istek") === 1, JSON.stringify(f1.ws.msgs.slice(-2)));
  await f2.gonder({ t: "kabul", handle: "arkadas1" });
  bak("arkadaşlık kabulü çalışır", arkSor("arkadas") === 1);

  // ---- ödeme kapalıyken elmas paketi verilmez (eski davranış bozulmadı)
  const od = oyuncu("odeme", { gems: 100 });
  await od.gonder({ t: "elmas_paketi", paket: "elmas_6500" });
  bak("ödeme kapalı: elmas paketi verilmez", sonHata(od) && od.eco().gems === 100);
  await od.gonder({ t: "ekonomi" });
  bak("ödeme kapalı: özet odeme_test false", od.ws.son("ekonomi").odeme_test === false);
}

// ---------------- 3) yerel sunucu (uçtan uca) ----------------
const SRV = process.env.SRV || "ws://127.0.0.1:8794";
async function baglan(token) {
  return new Promise((res) => {
    const ws = new WebSocket(`${SRV}/hesap?token=${token}`);
    const c = { ws, msgs: [], bekle: [] };
    const zaman = setTimeout(() => res(null), 4000);
    ws.onerror = () => {
      clearTimeout(zaman);
      res(null);
    };
    ws.onmessage = (e) => {
      if (e.data === "pong") return;
      const d = JSON.parse(e.data);
      c.msgs.push(d);
      for (const w of [...c.bekle]) if (w.f(d)) (c.bekle.splice(c.bekle.indexOf(w), 1), w.r(d));
      if (d.t === "ekonomi" && !c.hazir) {
        c.hazir = true;
        clearTimeout(zaman);
        res(c);
      }
    };
    c.sor = (o, f, ms = 3000) =>
      new Promise((r) => {
        const w = { f: typeof f === "string" ? (d) => d.t === f || d.t === "hata" : f, r };
        c.bekle.push(w);
        setTimeout(() => {
          const i = c.bekle.indexOf(w);
          if (i >= 0) (c.bekle.splice(i, 1), r(null));
        }, ms);
        ws.send(JSON.stringify(o));
      });
  });
}
{
  const { randomBytes } = await import("node:crypto");
  const c = await baglan(randomBytes(16).toString("hex"));
  if (!c) console.log("  (yerel sunucu kapalı: uçtan uca bölüm atlandı)");
  else {
    const e0 = c.msgs.find((m) => m.t === "ekonomi");
    bak("e2e: özet vitrin/set/pity/yol", e0.vitrin && e0.vitrin.gunluk.length === 6 && e0.setler.length >= 6 && e0.pity && e0.yol, Object.keys(e0).join(","));
    const r = await c.sor({ t: "kasa_ac", kasa: "tahta" }, "kasa_sonuc");
    bak("e2e: kasa açılır", r && r.t === "kasa_sonuc");
    const e1 = await c.sor({ t: "ekonomi" }, "ekonomi");
    bak("e2e: güvence sayacı", e1 && e1.pity.tahta.sayac === (r.nadirlik >= 2 ? 0 : 1));
    const set = e1.setler.find((s) => s.fiyat <= e1.elmas) || e1.setler[0];
    const sr = await c.sor({ t: "set_al", k: set.k, fiyat: set.fiyat }, "set_alindi");
    bak("e2e: set alınır ya da elmas yetmez", sr && (sr.t === "set_alindi" || sr.m === "Elmas yetmiyor."), JSON.stringify(sr));
    const sahip = new Set((await c.sor({ t: "ekonomi" }, "ekonomi")).sahip);
    const v = e1.vitrin.gunluk.find((x) => !sahip.has(x[0] + ":" + x[1]));
    const ir = await c.sor({ t: "istek_listesi", kat: v[0], id: v[1], ekle: true }, (d) => d.t === "istek_tamam" || d.t === "hata");
    bak("e2e: istek listesine eklenir", ir && ir.t === "istek_tamam" && ir.ekli, JSON.stringify(ir));
    const hr = await c.sor({ t: "hediye", handle: "kimse_yok", kat: "sapka", id: "bere" }, "hediye_gitti");
    bak("e2e: misafir hediye gönderemez", hr && hr.t === "hata");
    const yr = await c.sor({ t: "yol_al", s: 2 }, "yol_alindi");
    bak("e2e: seviye 1'de yol ödülü yok", yr && yr.t === "hata");
    c.ws.close();
  }
}

console.log(`market testi: ${ok} geçti, ${hata} hata`);
process.exit(hata ? 1 : 0);
