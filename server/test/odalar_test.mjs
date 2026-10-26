// ODALAR testi:  cd server && node test/odalar_test.mjs   (uçtan uca kısım yerel sunucu 8794 açıkken koşar)
// Birim: oda ayarı (görünürlük, kişi sınırı 4-8, ad süzgeci, botla), Odalar listesi (sıra, arkadaş üstte, en çok 50,
// mesaj boyutu, süre aşımı, depodan geri yükleme), Room -> liste bildirimi (Arkadaşlarım odası hiç yazılmaz).
// Uçtan uca: Herkes / Arkadaşlarım görünürlüğü, listeden katılma, kişi sınırı ve "Oda dolu", oda sahibinin ayar
// değiştirmesi, bot ekleme sayısı, maçtaki odaya listeden girilmemesi, botla doldurma, son kişi çıkınca listeden düşme.
import { Odalar, odaAyari, odaBildir, temizOdaAdi, ODA_TTL, LISTE_MAX } from "../src/odalar.js";
import { adUygun } from "../src/suzgec.js";
import { OLUMLU_ORNEKLER } from "../src/suzgec_liste.js";

const URL0 = process.env.SRV || "ws://127.0.0.1:8794";
const HTTP0 = URL0.replace("ws://", "http://").replace("wss://", "https://");
let ok = 0;
let hata = 0;
function bak(ad, kosul, ek = "") {
  if (kosul) {
    ok++;
    console.log("  OK   " + ad);
  } else {
    hata++;
    console.log("  HATA " + ad + (ek ? "  -> " + ek : ""));
  }
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const kod = () => {
  const c = "ABCDEFGHJKLMNPRSTUVYZ23456789";
  let s = "";
  for (let i = 0; i < 4; i++) s += c[Math.floor(Math.random() * c.length)];
  return s;
};
// süzgeçten geçmeyen bir ad (kaba kelime bu dosyada yazılı değil; liste dosyasından gelir)
const KOTU = (OLUMLU_ORNEKLER.find(([m]) => !adUygun(m)) || ["?"])[0];

// sahte Durable Object deposu (list dahil)
function depo() {
  const m = new Map();
  return {
    m,
    get: async (k) => m.get(k),
    put: async (k, v) => (typeof k === "object" ? Object.entries(k).forEach(([a, b]) => m.set(a, b)) : m.set(k, v)),
    delete: async (k) => (Array.isArray(k) ? k.forEach((x) => m.delete(x)) : m.delete(k)),
    list: async ({ prefix }) => new Map([...m].filter(([k]) => k.startsWith(prefix))),
  };
}
const istek = (o, yol, veri) => o.fetch(new Request("https://ic" + yol, { method: "POST", body: JSON.stringify(veri) }));
const liste = async (o, ark = []) => (await istek(o, "/liste", { ark })).json();

// ---------------------------------------------------------------- birim
async function birim() {
  // oda ayarı
  const v = odaAyari(new URLSearchParams(""));
  bak("birim: varsayılan ayar Arkadaşlarım, 8 kişi, adsız, botsuz", v.ayar.gor === "arkadas" && v.ayar.max === 8 && v.ayar.ad === "" && v.ayar.botla === false);
  const h = odaAyari(new URLSearchParams("gor=herkes&max=6&oda_ad=Gece%20Kul%C3%BCb%C3%BC&botla=1"));
  bak("birim: Herkes, 6 kişi, ad ve botla doldur okunur", h.ayar.gor === "herkes" && h.ayar.max === 6 && h.ayar.ad === "Gece Kulübü" && h.ayar.botla === true);
  bak("birim: kişi sınırı 4-8 arasına sıkışır", odaAyari({ max: 2 }).ayar.max === 4 && odaAyari({ max: 99 }).ayar.max === 8 && odaAyari({ max: "abc" }).ayar.max === 8);
  bak("birim: bilinmeyen görünürlük Arkadaşlarım sayılır", odaAyari({ gor: "gizli" }).ayar.gor === "arkadas");
  bak("birim: oda adı en çok 22 harf, görünmez karakter atılır", temizOdaAdi("  a​b  " + "x".repeat(40)).length === 22 && temizOdaAdi("a​b") === "ab");
  const k = odaAyari({ ad: KOTU, gor: "herkes" });
  bak("birim: küfürlü oda adı reddedilir, varsayılan ada döner", k.adRed === true && k.ayar.ad === "", KOTU === "?" ? "örnek bulunamadı" : "");
  bak("birim: adresteki oyuncu adı (ad=) oda adı sayılmaz", odaAyari(new URLSearchParams("ad=Kaan&kur=1&gor=herkes")).ayar.ad === "" && odaAyari(new URLSearchParams("ad=Kaan&oda_ad=Salon")).ayar.ad === "Salon");
  bak("birim: düzgün ad süzgeçten geçer", odaAyari({ ad: "Ali'nin odası" }).adRed === false);

  // Odalar listesi
  const st = { storage: depo() };
  const o = new Odalar(st, {});
  await istek(o, "/kayit", { kod: "AAAA", a: "Bir", h: "Ali", n: 3, x: 6 });
  await istek(o, "/kayit", { kod: "BBBB", a: "", h: "Bea", n: 2, x: 4, m: 1 });
  await istek(o, "/kayit", { kod: "CCCC", a: "Dolu", h: "Can", n: 4, x: 4 });
  await istek(o, "/kayit", { kod: "DDDD", a: "", h: "Dan", n: 1, x: 8 });
  await istek(o, "/kayit", { kod: "kötü", a: "x", h: "x", n: 1, x: 8 });
  let l = await liste(o);
  bak("birim: geçersiz kodlu kayıt alınmaz", l.toplam === 4, JSON.stringify(l));
  bak("birim: sıra lobide yeri olanlar (kalabalık önce) > dolu > maçta", l.o.map((r) => r.k).join(",") === "AAAA,DDDD,CCCC,BBBB", l.o.map((r) => r.k).join(","));
  bak("birim: kısa alanlar (k a h n x, maçta m:1)", l.o[0].k === "AAAA" && l.o[0].a === "Bir" && l.o[0].h === "Ali" && l.o[0].n === 3 && l.o[0].x === 6 && !("m" in l.o[0]) && l.o[3].m === 1);
  l = await liste(o, ["BBBB", "CCCC"]);
  bak("birim: arkadaşların odaları üstte (f:1)", l.o[0].k === "CCCC" && l.o[1].k === "BBBB" && l.o[0].f === 1 && !("f" in l.o[2]), l.o.map((r) => r.k).join(","));
  // kayıt güncelleme
  await istek(o, "/kayit", { kod: "DDDD", a: "", h: "Dan", n: 5, x: 8 });
  l = await liste(o);
  bak("birim: kayıt güncellenir (oyuncu sayısı)", l.o.find((r) => r.k === "DDDD").n === 5 && l.toplam === 4);
  await istek(o, "/sil", { kod: "AAAA" });
  l = await liste(o);
  bak("birim: silinen oda listeden çıkar", !l.o.some((r) => r.k === "AAAA") && l.toplam === 3);
  // depodan geri yükleme (nesne uyuyup uyandı)
  const o2 = new Odalar(st, {});
  bak("birim: kayıtlar depodan geri yüklenir", (await liste(o2)).toplam === 3);
  // süre aşımı
  const now0 = Date.now;
  Date.now = () => now0() + ODA_TTL - 2000;
  await istek(o2, "/kayit", { kod: "EEEE", a: "", h: "Eda", n: 1, x: 8 }); // bu taze
  Date.now = () => now0() + ODA_TTL + 1000;
  l = await liste(o2);
  Date.now = now0;
  bak("birim: 60 sn güncellenmeyen odalar düşer, taze olan kalır", l.toplam === 1 && l.o[0].k === "EEEE", JSON.stringify(l));
  bak("birim: düşen kayıtlar depodan da silinir", ![...st.storage.m.keys()].some((x) => x === "o:BBBB"));
  // en çok 50 oda, mesaj küçük
  const o3 = new Odalar({ storage: depo() }, {});
  for (let i = 0; i < 70; i++) {
    const kk = "K" + String(i).padStart(3, "0");
    await istek(o3, "/kayit", { kod: kk, a: "Ç".repeat(30), h: "Ğ".repeat(20), n: 1 + (i % 7), x: 8, b: 1 });
  }
  l = await liste(o3);
  const boy = new TextEncoder().encode(JSON.stringify(l)).length;
  bak("birim: listede en çok 50 oda (toplam ayrıca)", l.o.length === LISTE_MAX && l.toplam === 70);
  bak("birim: 50 odalık liste mesajı küçük (< 6 KB)", boy < 6144, boy + " bayt");
  bak("birim: ad/kurucu sınırları kayıtta da uygulanır", Array.from(l.o[0].a).length === 22 && Array.from(l.o[0].h).length === 16);

  // Room -> liste bildirimi (sahte oda)
  const kayitlar = [];
  const o4 = new Odalar({ storage: depo() }, {});
  const env = { ODALAR: { idFromName: () => 1, get: () => ({ fetch: async (r) => (kayitlar.push(new URL(r.url).pathname), o4.fetch(r)) }) } };
  const insan = [{}, {}];
  const oda = {
    env,
    code: "ROOM",
    acik: false,
    g: null,
    ayar: { gor: "arkadas", max: 6, ad: "", botla: false },
    sockets: (ex) => insan.filter((s) => s !== ex),
    players: (ex) => insan.filter((s) => s !== ex).map((s, i) => ({ id: i + 1, name: i ? "Bea" : "Ali", host: i === 0 })),
    loadGame: async () => null,
  };
  await odaBildir(oda);
  bak("birim: Arkadaşlarım odası listeye hiç yazılmaz", kayitlar.length === 0 && (await liste(o4)).toplam === 0);
  oda.ayar = { gor: "herkes", max: 6, ad: "Salon", botla: true };
  await odaBildir(oda, null, true);
  l = await liste(o4);
  bak("birim: Herkes odası listede (kurucu, sayı, sınır, botla)", l.toplam === 1 && l.o[0].h === "Ali" && l.o[0].n === 2 && l.o[0].x === 6 && l.o[0].a === "Salon" && l.o[0].b === 1, JSON.stringify(l));
  const n0 = kayitlar.length;
  await odaBildir(oda);
  bak("birim: değişiklik yoksa yeniden yollanmaz", kayitlar.length === n0);
  oda.g = { phase: "oyun" };
  await odaBildir(oda);
  l = await liste(o4);
  bak("birim: maç başlayınca durum Maçta", l.o[0].m === 1 && kayitlar.length === n0 + 1);
  oda.g = { phase: "bitti" };
  await odaBildir(oda);
  bak("birim: maç sonu ekranındaki oda yine Lobide sayılır", !("m" in (await liste(o4)).o[0]));
  oda.ayar = { ...oda.ayar, gor: "arkadas" };
  await odaBildir(oda, null, true);
  bak("birim: Arkadaşlarım'a çevrilen oda listeden silinir", (await liste(o4)).toplam === 0);
  oda.ayar = { ...oda.ayar, gor: "herkes" };
  await odaBildir(oda, null, true);
  await odaBildir(oda, insan[1]);
  bak("birim: biri çıkınca sayı düşer", (await liste(o4)).o[0].n === 1);
  insan.pop();
  await odaBildir(oda, insan[0]);
  bak("birim: son kişi çıkınca oda listeden silinir", (await liste(o4)).toplam === 0);
  const acikOda = { ...oda, acik: true, sockets: () => [{}], players: () => [{ id: 1, name: "X", host: true }] };
  const n1 = kayitlar.length;
  await odaBildir(acikOda);
  bak("birim: Hızlı Oyun odası bu listeye girmez", (await liste(o4)).toplam === 0 && kayitlar.slice(n1).every((p) => p === "/sil"));
}

// ---------------------------------------------------------------- uçtan uca (yerel sunucu)
class W {
  constructor(url, ad) {
    this.url = url;
    this.ad = ad;
    this.msgs = [];
    this.waiters = [];
  }
  open() {
    return new Promise((res, rej) => {
      this.ws = new WebSocket(this.url);
      this.ws.onopen = () => res(this);
      this.ws.onerror = (e) => rej(e);
      this.ws.onclose = () => (this.closed = true);
      this.ws.onmessage = (e) => {
        if (typeof e.data !== "string" || e.data === "pong") return;
        const d = JSON.parse(e.data);
        this.msgs.push(d);
        if (process.env.V) console.log(`  [${this.ad}] <-`, JSON.stringify(d).slice(0, 160));
        for (const w of [...this.waiters])
          if (w.f(d)) {
            this.waiters.splice(this.waiters.indexOf(w), 1);
            w.r(d);
          }
      };
    });
  }
  send(o) {
    this.ws.send(JSON.stringify(o));
  }
  wait(f, ms = 5000) {
    if (typeof f === "string") {
      const t = f;
      f = (d) => d.t === t;
    }
    const eski = this.msgs.find(f);
    if (eski) return Promise.resolve(eski);
    return new Promise((r) => {
      const w = { f, r };
      this.waiters.push(w);
      setTimeout(() => {
        const i = this.waiters.indexOf(w);
        if (i >= 0) {
          this.waiters.splice(i, 1);
          r(null);
        }
      }, ms);
    });
  }
  cik() {
    try {
      this.send({ t: "cik" });
      this.ws.close();
    } catch {}
  }
}

// kur: {gor, max, oda_ad, botla} ya da null (katıl); liste: ODALAR listesinden katılma
async function gir(code, ad, kur, liste = false) {
  let q = `ad=${encodeURIComponent(ad)}&kur=${kur ? 1 : 0}&davet=${kur || liste ? 0 : 1}&dil=tr`;
  if (kur) for (const [a, b] of Object.entries(kur)) q += `&${a}=${encodeURIComponent(b)}`;
  if (liste) q += "&liste=1";
  const w = new W(`${URL0}/oda/${code}?${q}`, ad);
  const p = w.wait((d) => d.t === "hosgeldin" || d.t === "hata");
  await w.open();
  const d = await p;
  if (d && d.t === "hosgeldin") w.hos = d;
  else w.hata = d;
  if (w.hos) await sleep(60); // oda_ayar ve liste kaydı
  return w;
}

async function odalar(ark = []) {
  const r = await fetch(HTTP0 + "/odalar", { method: "POST", body: JSON.stringify({ ark }) });
  return await r.json();
}
const bul = async (k, ark) => (await odalar(ark)).o.find((r) => r.k === k);

async function uctanUca() {
  try {
    const r = await fetch(HTTP0 + "/");
    if (!r.ok) throw 0;
  } catch {
    console.log("  (yerel sunucu 8794 kapalı: uçtan uca kısım atlandı)");
    return;
  }
  const acik = [];
  try {
    const R1 = kod();
    const A = await gir(R1, "Ayse", { gor: "herkes", max: 5, oda_ad: "Gece Kulübü" });
    acik.push(A);
    const ay = await A.wait("oda_ayar");
    bak("Herkes odası kuruldu, ayar geldi", A.hos && A.hos.host && ay && ay.gor === "herkes" && ay.max === 5 && ay.ad === "Gece Kulübü", JSON.stringify(ay));
    let r1 = await bul(R1);
    bak("Herkes odası ODALAR listesinde (ad, kurucu, 1/5, lobide)", r1 && r1.a === "Gece Kulübü" && r1.h === "Ayse" && r1.n === 1 && r1.x === 5 && !r1.m, JSON.stringify(r1));

    const R2 = kod();
    const B = await gir(R2, "Burak", { gor: "arkadas", max: 6 });
    acik.push(B);
    bak("Arkadaşlarım odası kuruldu (ayar arkadas)", B.hos && (await B.wait("oda_ayar")).gor === "arkadas");
    bak("Arkadaşlarım odası listede hiç görünmez", !(await bul(R2)));
    const B2 = await gir(R2, "Bora", null, true);
    bak("Arkadaşlarım odasına listeden girilemez", !B2.hos && B2.hata && /listede değil/.test(B2.hata.m), JSON.stringify(B2.hata));
    const B3 = await gir(R2, "Bilge", null, false);
    acik.push(B3);
    bak("Arkadaşlarım odasına kodla girilir", !!B3.hos);
    bak("kodla katılana da oda ayarı gelir", !!(await B3.wait("oda_ayar")));

    // listeden katılma ve kişi sınırı
    const misafir = [];
    for (let i = 0; i < 4; i++) {
      const w = await gir(R1, "Misafir" + i, null, true);
      acik.push(w);
      misafir.push(w);
    }
    bak("listeden 4 kişi katıldı", misafir.every((w) => !!w.hos), misafir.map((w) => JSON.stringify(w.hata)).join(" "));
    r1 = await bul(R1);
    bak("liste kaydı güncellendi: 5/5", r1 && r1.n === 5 && r1.x === 5, JSON.stringify(r1));
    const fazla = await gir(R1, "Fazla", null, true);
    bak("dolu odaya katılma reddedilir: Oda dolu (en fazla 5 kişi)", !fazla.hos && fazla.hata && fazla.hata.m === "Oda dolu (en fazla 5 kişi)." && Array.isArray(fazla.hata.m_k), JSON.stringify(fazla.hata));
    const fazla2 = await gir(R1, "Fazla2", null, false);
    bak("kodla da sınır aşılamaz", !fazla2.hos && /Oda dolu/.test((fazla2.hata || {}).m || ""));
    A.send({ t: "oda_ayar", gor: "herkes", max: 4, ad: "Gece Kulübü" });
    const sayi = await A.wait((d) => d.t === "bilgi" && /kişi var/.test(d.m || ""));
    await sleep(150);
    r1 = await bul(R1);
    bak("sınır odadaki kişiden aşağı inemez (5 kişi var: 4 istenince 5 kalır)", !!sayi && r1 && r1.x === 5, JSON.stringify(r1));
    const ark = await odalar([R1]);
    bak("arkadaşın odası listenin en üstünde (f:1)", ark.o[0] && ark.o[0].k === R1 && ark.o[0].f === 1);
    misafir[3].cik();
    await sleep(250);
    r1 = await bul(R1);
    bak("biri çıkınca kayıt 4/5", r1 && r1.n === 4, JSON.stringify(r1));

    // oda sahibi ayarı değiştirir
    A.send({ t: "oda_ayar", gor: "arkadas", max: 5, ad: "Gece Kulübü" });
    const ay2 = await A.wait((d) => d.t === "oda_ayar" && d.gor === "arkadas");
    await sleep(150);
    bak("sahip Arkadaşlarım'a çevirdi: herkese yeni ayar gider, listeden düşer", ay2 && !!(await misafir[0].wait((d) => d.t === "oda_ayar" && d.gor === "arkadas")) && !(await bul(R1)));
    const engel = await gir(R1, "Gec", null, true);
    bak("listeden kalkmış odaya listeden girilemez", !engel.hos && /listede değil/.test((engel.hata || {}).m || ""));
    misafir[0].send({ t: "oda_ayar", gor: "herkes", max: 8 });
    await sleep(200);
    bak("sahip olmayan oda ayarını değiştiremez", !(await bul(R1)));
    A.send({ t: "oda_ayar", gor: "herkes", max: 4, ad: KOTU });
    const red = await A.wait((d) => d.t === "bilgi" && /oda adı/.test(d.m || ""));
    await sleep(150);
    r1 = await bul(R1);
    bak("ayar değişiminde küfürlü ad reddedilir, eski ad kalır; sınır 4 oldu", !!red && r1 && r1.a === "Gece Kulübü" && r1.x === 4, JSON.stringify(r1));
    A.send({ t: "bot_ekle" });
    const dolu = await A.wait((d) => d.t === "bilgi" && /Oda dolu \(en fazla 4/.test(d.m || ""));
    bak("sınır doluyken bot eklenemez", !!dolu);

    // ad süzgeci, bot sayısı, maçta durumu
    const R3 = kod();
    const C = await gir(R3, "Cem", { gor: "herkes", max: 4, oda_ad: KOTU });
    acik.push(C);
    const cb = await C.wait((d) => d.t === "bilgi" && /oda adı/.test(d.m || ""));
    let r3 = await bul(R3);
    bak("kurarken küfürlü oda adı: bilgi + listede varsayılan ad (boş)", !!cb && r3 && r3.a === "" && r3.h === "Cem", JSON.stringify(r3));
    C.send({ t: "bot_ekle" });
    await C.wait((d) => d.t === "oyuncular" && d.players.length === 2);
    await sleep(150);
    r3 = await bul(R3);
    bak("bot eklenince listedeki sayı artar (2/4)", r3 && r3.n === 2, JSON.stringify(r3));
    C.send({ t: "basla", oyunlar: ["ortalama"], hiz: 0.05 });
    await C.wait("basladi");
    await sleep(200);
    r3 = await bul(R3);
    bak("maç başlayınca listede Maçta (m:1)", r3 && r3.m === 1, JSON.stringify(r3));
    const gec = await gir(R3, "Geç", null, true);
    bak("maçtaki odaya listeden girilmez", !gec.hos && /maç başladı/.test((gec.hata || {}).m || ""), JSON.stringify(gec.hata));

    // botla doldur
    const R4 = kod();
    const D = await gir(R4, "Deniz", { gor: "arkadas", max: 4, botla: 1 });
    acik.push(D);
    D.send({ t: "basla", oyunlar: ["ortalama"], hiz: 0.05 });
    const dol = await D.wait((d) => d.t === "oyuncular" && d.players.length === 4);
    bak("botla doldur: tek kişi BAŞLAT deyince 3 bot eklenip 4/4 başlar", !!dol && !!(await D.wait("basladi")));

    // son kişi çıkınca listeden düşer
    A.cik();
    for (const w of misafir) w.cik();
    await sleep(400);
    bak("herkes çıkınca Herkes odası listeden silinir", !(await bul(R1)));
    C.cik();
    await sleep(300);
    bak("maçtaki oda da son kişi çıkınca silinir", !(await bul(R3)));
  } finally {
    for (const w of acik) w.cik();
  }
}

console.log("— birim —");
await birim();
console.log("— uçtan uca (8794) —");
await uctanUca();
console.log(`\n${ok} geçti, ${hata} hatalı`);
process.exit(hata ? 1 : 0);
