// Kayıt / e-posta / şifre sıfırlama / misafir yasağı testi:  cd server && node test/kayit_test.mjs
// 1) posta_gonder.js: bağlama yokken göndermez ve hata fırlatmaz; bağlama hata verse de akış bozulmaz.
// 2) Hesap nesnesi (sahte Durable Object, node:sqlite): e-postasız kayıt reddi, aynı e-posta reddi, misafir ilerlemesi
//    hesaba geçer, oyundaki ad = kullanıcı adı, eski hesap e-posta ekler, doğrulama, şifre sıfırlama (kod özeti, yanlış
//    kod sınırı, hız sınırı), web bağlantısı, hesap silinince "silindi" e-postası; e-posta başka oyunculara sızmaz.
// 3) Yerel sunucu (ws://127.0.0.1:8794, SRV ile değişir) açıksa uçtan uca: misafir odaya / Hızlı Oyun'a giremez,
//    odadaki ad = kullanıcı adı (istemcinin yolladığı ad değil), kayıtta test kodu yakalanır. Kapalıysa atlanır.
import { DatabaseSync } from "node:sqlite";
import { hesapAc, hesapSil, bagla, rastgeleAnahtar } from "./_hesap.mjs";

let ok = 0;
let hata = 0;
function bak(ad, kosul, ek = "") {
  if (kosul) ok++;
  else {
    hata++;
    console.log("HATA:", ad, ek);
  }
}
const uyu = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------------- 1) gönderici ----------------
const { postaGonder, epostaTemiz, epostaMaske } = await import("../src/posta_gonder.js");
{
  const eskiLog = console.log;
  const loglar = [];
  console.log = (...a) => loglar.push(a.join(" "));
  const r1 = await postaGonder({}, "hosgeldin", "tr", "ali@example.com", { ad: "ali", kullanici: "ali" });
  const giden = [];
  const r2 = await postaGonder({ EMAIL: { send: async (m) => (giden.push(m), { messageId: "x" }) } }, "dogrula", "en", "ali@example.com", { ad: "ali", kod: "123456", url: "https://x" });
  const r3 = await postaGonder({ EMAIL: { send: async () => { throw new Error("hata ali@example.com"); } } }, "sifirla", "tr", "ali@example.com", { kullanici: "ali", kod: "1" });
  const r4 = await postaGonder({}, "yok_boyle", "tr", "ali@example.com", {});
  console.log = eskiLog;
  bak("bağlama yok: gönderilmez, hata yok", r1.ok === false && r1.neden === "baglanti_yok");
  bak("bağlama yok: log yazılır", loglar.some((l) => l.includes("posta: bağlantı yok, gönderilmedi (hosgeldin)")), loglar.join(" | "));
  bak("bağlama var: gönderilir", r2.ok === true && giden.length === 1);
  bak("gönderim alanları (to/from/subject/html/text)", giden[0] && giden[0].to === "ali@example.com" && /destek@hatdustu\.app/.test(giden[0].from) && /123456/.test(giden[0].subject) && giden[0].html.includes("123456") && giden[0].text.includes("123456"));
  bak("bağlama hata verirse yakalanır", r3.ok === false && r3.neden === "hata");
  bak("bilinmeyen tür hata fırlatmaz", r4.ok === false);
  bak("loglarda e-posta adresi yok", !loglar.some((l) => l.includes("ali@example.com")), loglar.join(" | "));
  bak("e-posta biçimi: büyük harf küçülür", epostaTemiz("  Ali.Veli@Example.COM ") === "ali.veli@example.com");
  for (const yanlis of ["", "ali", "ali@", "@x.com", "ali@x", "a b@x.com", "ali@@x.com", "ali..v@x.com", ".ali@x.com"]) bak("geçersiz e-posta: " + yanlis, epostaTemiz(yanlis) === "");
  bak("maske", epostaMaske("ali.veli@example.com") === "al***@e***.com", epostaMaske("ali.veli@example.com"));
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
  return { storage: { sql }, setWebSocketAutoResponse() {}, getWebSockets: () => socks.filter((s) => !s.kapali), socks };
}

class SahteWS {
  constructor(st, token, handle, ek = {}) {
    this.att = { token, handle: handle || "", room: "", tries: 0, koken: "https://sunucu.test", ip: "1.2.3.4", ...ek };
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
  close() {
    this.kapali = true;
  }
  son(t) {
    for (let i = this.msgs.length - 1; i >= 0; i--) if (this.msgs[i].t === t) return this.msgs[i];
    return null;
  }
}

const st = sahteDO();
const acc = new Accounts(st, { ODEME_TEST: "0", SPAM_SINIRI: "0" });
const giden = []; // gönderilen e-postalar (birim testte yakalanır)
const hepsiPosta = []; // hiç silinmez
acc.postaKanca = (tur, alici, veri) => (giden.push({ tur, alici, veri }), hepsiPosta.push({ tur, alici, veri }));
const sonPosta = (tur, alici) => [...giden].reverse().find((g) => g.tur === tur && (!alici || g.alici === alici));
let n = 0;
function cihaz(ek = {}) {
  const token = "tok" + String(++n).padStart(20, "0") + Math.random().toString(36).slice(2, 8);
  acc.sql.exec(`INSERT OR IGNORE INTO users (token) VALUES (?)`, token);
  const ws = new SahteWS(st, token, "", ek);
  const c = {
    token, ws,
    async gonder(d) {
      ws.msgs = [];
      await acc.webSocketMessage(ws, JSON.stringify(d));
      await uyu(30); // arka plandaki kod üretimi / e-posta
      return ws.msgs;
    },
    hata: () => ws.son("hata"),
    me: () => acc.me(ws.att.token),
  };
  return c;
}
const kayit = (c, handle, eposta, sifre = "Sifre-123", ek = {}) => c.gonder({ t: "uye_ol", handle, eposta, sifre, dil: "tr", ...ek });

// ---- e-postasız / hatalı e-postayla kayıt reddedilir
{
  const c = cihaz();
  await kayit(c, "ali", undefined);
  bak("e-postasız kayıt reddedilir", c.hata() && /E-posta adresini yaz/.test(c.hata().m), JSON.stringify(c.ws.msgs));
  await kayit(c, "ali", "ali@");
  bak("hatalı e-posta reddedilir", c.hata() && /geçerli değil/.test(c.hata().m), JSON.stringify(c.ws.msgs));
  bak("reddedilen kayıtta hesap açılmaz", !c.me().hesap && c.me().handle === "");
  bak("e-posta yokken kullanıcı adı kuralı yine önce", (await kayit(c, "çağrı", "a@b.co")) && /Türkçe harf/.test(c.hata().m));
}

// ---- kayıt: e-posta küçük harfe, ad = kullanıcı adı, misafir ilerlemesi hesapta kalır, e-postalar gider
let ali;
{
  ali = cihaz();
  const e = acc.eco(ali.token);
  e.gems = 777;
  e.items = ["sapka:bere"];
  e.xp = 350;
  acc.saveEco(ali.token, e); // misafirken kazanılanlar
  giden.length = 0;
  await kayit(ali, "Ali_34", "  Ali.Veli@Example.COM ", "Sifre-123", { ad: "Sahte Ad" });
  const me = ali.ws.son("ben");
  bak("kayıt olur", me && me.hesap && me.handle === "ali_34", JSON.stringify(ali.ws.msgs));
  bak("oyundaki ad = kullanıcı adı (istemcinin yolladığı ad değil)", me && me.name === "ali_34", JSON.stringify(me));
  const row = acc.rows(`SELECT email, email_ok, name FROM users WHERE token = ?`, ali.token)[0];
  bak("e-posta küçük harfle saklanır", row.email === "ali.veli@example.com" && row.email_ok === 0, JSON.stringify(row));
  bak("sahibine e-posta yalnız gizli biçimde gider", me.eposta === "al***@e***.com" && !JSON.stringify(ali.ws.msgs).includes("ali.veli@example.com"));
  bak("e-posta doğrulanmadı bilgisi", me.eposta_var === true && me.eposta_ok === false);
  const eco = acc.eco(ali.token);
  bak("misafir ilerlemesi hesapta (elmas, eşya, XP)", eco.gems === 777 && eco.items.includes("sapka:bere") && eco.xp === 350, JSON.stringify(eco));
  bak("hoş geldin e-postası", !!sonPosta("hosgeldin", "ali.veli@example.com"));
  const d = sonPosta("dogrula", "ali.veli@example.com");
  bak("doğrulama e-postası (6 haneli kod, bağlantı)", d && /^\d{6}$/.test(d.veri.kod) && d.veri.url.startsWith("https://sunucu.test/eposta-dogrula?h=ali_34&k="), JSON.stringify(d && d.veri));
  const kr = acc.rows(`SELECT ozet, bitis FROM kodlar WHERE token = ? AND tur = 'dogrula'`, ali.token)[0];
  bak("kod sunucuda düz yazı değil (özet)", kr && !kr.ozet.includes(d.veri.kod) && kr.ozet.length > 60);
  bak("doğrulama kodu 30 dk", kr && Math.abs(Number(kr.bitis) - Date.now() - 30 * 60000) < 5000);
  bak("bağlama yokken kayıt yine başarılı (bilgi mesajı)", ali.ws.msgs.some((m) => m.t === "bilgi" && /Hesabın açıldı/.test(m.m)));
}

// ---- aynı e-posta ikinci hesapta reddedilir (büyük/küçük harf fark etmez)
{
  const c = cihaz();
  await kayit(c, "baska1", "ALI.VELI@example.com");
  bak("aynı e-postayla ikinci hesap açılamaz", c.hata() && /zaten bir hesap var/.test(c.hata().m), JSON.stringify(c.ws.msgs));
  bak("ikinci hesap açılmadı", !c.me().hesap);
  await kayit(c, "ali_34", "yeni@example.com");
  bak("alınmış kullanıcı adı reddedilir", c.hata() && /alınmış/.test(c.hata().m));
}

// ---- e-posta doğrulama: yanlış kod, doğru kod
{
  const d = sonPosta("dogrula", "ali.veli@example.com");
  const yanlis = d.veri.kod === "000000" ? "111111" : "000000";
  await ali.gonder({ t: "eposta_dogrula", kod: yanlis });
  bak("yanlış doğrulama kodu", ali.hata() && /Kod yanlış/.test(ali.hata().m));
  await ali.gonder({ t: "eposta_dogrula", kod: d.veri.kod });
  bak("doğru kodla e-posta doğrulanır", !!ali.ws.son("dogrulandi") && ali.me().eposta_ok === true, JSON.stringify(ali.ws.msgs));
  await ali.gonder({ t: "dogrulama_tekrar" });
  bak("doğrulanmışa yeni kod gitmez", ali.ws.son("bilgi") && /zaten doğrulandı/.test(ali.ws.son("bilgi").m));
}

// ---- oyundaki ad kilitli: "ad" ve profil kaydı adı değiştirmez; oda girişi adı hesaptan alır
{
  await ali.gonder({ t: "ad", ad: "Başka Biri" });
  await ali.gonder({ t: "profil_kaydet", p: { ad: "Profil Adı", gorunum: {} } });
  bak("ad değişmez (kullanıcı adı)", ali.me().name === "ali_34" && acc.gorunenAd("ali_34") === "ali_34");
  const r = await (await acc.fetch(new Request("https://ic/ic/oda-giris", { method: "POST", body: JSON.stringify({ token: ali.token }) }))).json();
  bak("oda girişi: hesap var, ad = kullanıcı adı", r.hesap === true && r.ad === "ali_34", JSON.stringify(r));
  const g = cihaz();
  const r2 = await (await acc.fetch(new Request("https://ic/ic/oda-giris", { method: "POST", body: JSON.stringify({ token: g.token }) }))).json();
  bak("oda girişi: misafir hesap değil", r2.hesap === false && r2.ad === "", JSON.stringify(r2));
  await g.gonder({ t: "istek", handle: "ali_34" });
  bak("misafir arkadaş isteği gönderemez", g.hata() && /hesap aç/.test(g.hata().m));
  await g.gonder({ t: "eposta_ekle", eposta: "g@example.com" });
  bak("misafir e-posta ekleyemez", g.hata() && /hesap aç/.test(g.hata().m));
}

// ---- e-posta başka oyunculara sızmaz (arkadaş listesi, davet, liderlik)
{
  const b = cihaz();
  await kayit(b, "berk", "berk@example.com");
  await b.gonder({ t: "istek", handle: "ali_34" });
  await ali.gonder({ t: "kabul", handle: "berk" });
  const e = acc.eco(ali.token);
  e.hafta_xp = 50;
  acc.saveEco(ali.token, e);
  await b.gonder({ t: "liderlik" });
  const hepsi = JSON.stringify([acc.list("berk"), acc.list("ali_34"), b.ws.msgs]);
  bak("liste ve liderlikte e-posta yok", !hepsi.includes("@example.com") && hepsi.includes("ali_34"), hepsi.slice(0, 300));
  bak("liderlikte ad = kullanıcı adı", (b.ws.son("liderlik").liste || []).some((x) => x.ad === "ali_34"));
}

// ---- eski (e-postasız) hesap e-posta ekler
let eski;
{
  eski = cihaz();
  acc.sql.exec(`UPDATE users SET handle = 'eski_hesap', name = 'Eski Görünen', pass = ? WHERE token = ?`, await acc.makePass("Eski-123"), eski.token);
  eski.ws.att.handle = "eski_hesap";
  const me = eski.me();
  bak("eski hesap: e-posta yok bilgisi", me.hesap && me.eposta_var === false && me.name === "eski_hesap", JSON.stringify(me));
  await eski.gonder({ t: "eposta_ekle", eposta: "yanlis" });
  bak("eski hesap: hatalı e-posta reddedilir", eski.hata() && /geçerli değil/.test(eski.hata().m));
  await eski.gonder({ t: "eposta_ekle", eposta: "Ali.Veli@example.com" });
  bak("eski hesap: başkasının e-postası reddedilir", eski.hata() && /zaten bir hesap var/.test(eski.hata().m));
  giden.length = 0;
  await eski.gonder({ t: "eposta_ekle", eposta: "Eski@Example.com" });
  bak("eski hesap e-posta ekler", !!eski.ws.son("eposta_tamam") && eski.me().eposta_var && !eski.me().eposta_ok, JSON.stringify(eski.ws.msgs));
  bak("eski hesap: doğrulama kodu gider", !!sonPosta("dogrula", "eski@example.com"));
  await eski.gonder({ t: "dogrulama_tekrar" });
  bak("hemen yeni kod istenemez (bekleme)", eski.hata() && /bekle/.test(eski.hata().m));
  await eski.gonder({ t: "eposta_ekle", eposta: "eski2@example.com" });
  bak("doğrulanmamış adres düzeltilebilir", eski.ws.son("eposta_tamam") && acc.rows(`SELECT email FROM users WHERE token = ?`, eski.token)[0].email === "eski2@example.com");
}

// ---- şifre sıfırlama
{
  // doğrulanmamış e-posta: kod gitmez ama cevap aynıdır (kimin hesabı olduğu anlaşılmasın)
  const x = cihaz();
  giden.length = 0;
  await x.gonder({ t: "sifre_unuttum", kim: "eski_hesap" });
  const c1 = x.ws.son("sifirla_gitti");
  await x.gonder({ t: "sifre_unuttum", kim: "olmayan_biri" });
  const c2 = x.ws.son("sifirla_gitti");
  bak("doğrulanmamış / olmayan hesap: kod gitmez", !sonPosta("sifirla"));
  bak("cevap her durumda aynı", c1 && c2 && c1.m === c2.m);
  // doğrulanmış hesap (e-postayla aranır)
  await x.gonder({ t: "sifre_unuttum", kim: "ALI.VELI@example.com", cihaz: "iPhone" });
  const s1 = sonPosta("sifirla", "ali.veli@example.com");
  bak("doğrulanmış e-postaya sıfırlama kodu gider", s1 && /^\d{6}$/.test(s1.veri.kod) && s1.veri.kullanici === "ali_34" && s1.veri.cihaz === "iPhone", JSON.stringify(s1 && s1.veri));
  bak("sıfırlama bağlantısı", s1 && s1.veri.url.includes("/sifre-sifirla?h=ali_34&k=" + s1.veri.kod));
  const kr = acc.rows(`SELECT ozet, bitis FROM kodlar WHERE token = ? AND tur = 'sifirla'`, ali.token)[0];
  bak("sıfırlama kodu özet olarak, 15 dk", kr && !kr.ozet.includes(s1.veri.kod) && Math.abs(Number(kr.bitis) - Date.now() - 15 * 60000) < 5000);
  // yanlış kod sınırı: 5. yanlışta kod iptal, sonra doğru kod da geçmez
  const yanlis = s1.veri.kod === "999999" ? "888888" : "999999";
  for (let i = 0; i < 4; i++) await x.gonder({ t: "sifre_sifirla", kim: "ali_34", kod: yanlis, sifre: "Yeni-123" });
  bak("yanlış kod: hata", x.hata() && /Kod yanlış/.test(x.hata().m), JSON.stringify(x.ws.msgs));
  await x.gonder({ t: "sifre_sifirla", kim: "ali_34", kod: yanlis, sifre: "Yeni-123" });
  bak("5. yanlışta kod iptal", x.hata() && /iptal/.test(x.hata().m), JSON.stringify(x.ws.msgs));
  await x.gonder({ t: "sifre_sifirla", kim: "ali_34", kod: s1.veri.kod, sifre: "Yeni-123" });
  bak("iptal edilen kod artık geçmez", x.hata() && /Geçerli bir kod yok/.test(x.hata().m), JSON.stringify(x.ws.msgs));
  // hemen yeni kod: hesap başına bekleme (cevap yine aynı, kod gitmez)
  giden.length = 0;
  await x.gonder({ t: "sifre_unuttum", kim: "ali_34" });
  bak("iki kod arası bekleme", !sonPosta("sifirla") && x.ws.son("sifirla_gitti"));
  acc.sql.exec(`UPDATE kod_gonderim SET ts = ts - 60000`);
  await x.gonder({ t: "sifre_unuttum", kim: "ali_34" });
  const s2 = sonPosta("sifirla");
  bak("bekleme sonrası yeni kod", !!s2);
  // kısa şifre
  await x.gonder({ t: "sifre_sifirla", kim: "ali_34", kod: s2.veri.kod, sifre: "123" });
  bak("yeni şifre kısa: hata", x.hata() && /en az 6/.test(x.hata().m));
  // doğru kod + yeni şifre: anahtar yenilenir, eski oturum kapanır, "degisti" e-postası, bu cihaz girer
  const eskiToken = ali.token;
  giden.length = 0;
  await x.gonder({ t: "sifre_sifirla", kim: "ali_34", kod: s2.veri.kod, sifre: "Yeni-123", cihaz: "Pixel" });
  const gir = x.ws.son("giris_ok");
  bak("şifre sıfırlanır, yeni anahtarla giriş", gir && gir.token && gir.token !== eskiToken && !!x.ws.son("sifre_yenilendi"), JSON.stringify(x.ws.msgs));
  bak("eski anahtarla oturum kapandı", ali.ws.kapali === true && !!ali.ws.son("oturum_kapandi"));
  bak("eski anahtar artık hesap değil", acc.rows(`SELECT 1 FROM users WHERE token = ?`, eskiToken).length === 0);
  const yeniEco = acc.eco(gir.token);
  bak("ilerleme yeni anahtarda", yeniEco.gems === 777 && yeniEco.items.includes("sapka:bere"));
  bak("arkadaşlık korunur", acc.list("berk").friends.some((f) => f.handle === "ali_34"));
  const dg = sonPosta("degisti", "ali.veli@example.com");
  bak("şifre değişti e-postası", dg && dg.veri.kullanici === "ali_34" && dg.veri.cihaz === "Pixel", JSON.stringify(dg && dg.veri));
  const y = cihaz();
  await y.gonder({ t: "giris", handle: "ali_34", sifre: "Sifre-123" });
  bak("eski şifre geçmez", y.hata() && /yanlış/.test(y.hata().m));
  await y.gonder({ t: "giris", handle: "ali.veli@example.com", sifre: "Yeni-123" });
  bak("yeni şifreyle e-posta adresiyle giriş", y.ws.son("giris_ok") && y.ws.son("giris_ok").token === gir.token, JSON.stringify(y.ws.msgs));
  ali = { ...ali, token: gir.token };
  // hesap başına sınır: 15 dk'da en çok 3 kod
  acc.sql.exec(`DELETE FROM kod_gonderim`);
  let gonderilen = 0;
  for (let i = 0; i < 5; i++) {
    giden.length = 0;
    acc.sql.exec(`UPDATE kod_gonderim SET ts = ts - 50000`); // iki kod arası beklemeyi atla, 15 dk penceresi kalsın
    await cihaz({ ip: "5.5.5." + i }).gonder({ t: "sifre_unuttum", kim: "ali_34" });
    if (sonPosta("sifirla")) gonderilen++;
  }
  bak("hesap başına 15 dk'da en çok 3 kod", gonderilen === 3, String(gonderilen));
  // IP başına sınır (farklı bağlantılar, aynı IP)
  let red = 0;
  for (let i = 0; i < 12; i++) {
    const z = cihaz({ ip: "9.9.9.9" });
    await z.gonder({ t: "sifre_unuttum", kim: "kimse" + i });
    if (z.hata() && /Çok fazla/.test(z.hata().m)) red++;
  }
  bak("IP başına hız sınırı", red >= 1, String(red));
}

// ---- web bağlantısı: doğrulama ve yeni şifre
{
  const d = [...hepsiPosta].reverse().find((g) => g.tur === "dogrula" && g.alici === "eski2@example.com");
  const form = (o) => new Request("https://ic/x", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded", "cf-connecting-ip": "7.7.7.7" }, body: new URLSearchParams(o).toString() });
  let r = await acc.webKod(form({ h: "eski_hesap", k: "000001" }), "dogrula");
  bak("web: yanlış kod", r.kod === "yanlis" || (d.veri.kod === "000001" && r.kod === "tamam"), JSON.stringify(r));
  r = await acc.webKod(form({ h: "eski_hesap", k: d.veri.kod }), "dogrula");
  bak("web: e-posta doğrulanır", r.kod === "tamam" && acc.me(eski.token).eposta_ok, JSON.stringify(r));
  const x = cihaz({ ip: "8.8.8.8" });
  giden.length = 0;
  await x.gonder({ t: "sifre_unuttum", kim: "eski_hesap" });
  const s = sonPosta("sifirla", "eski2@example.com");
  r = await acc.webKod(form({ h: "eski_hesap", k: s.veri.kod, sifre: "Web-1234", sifre2: "farkli" }), "sifirla");
  bak("web: şifreler aynı değil", r.kod === "ayni_degil");
  r = await acc.webKod(form({ h: "eski_hesap", k: s.veri.kod, sifre: "Web-1234", sifre2: "Web-1234" }), "sifirla");
  bak("web: şifre değişir", r.kod === "tamam" && !!sonPosta("degisti", "eski2@example.com"), JSON.stringify(r));
}

// ---- hesap silinince "silindi" e-postası; e-posta boşa çıkar
{
  const s = cihaz();
  await kayit(s, "silinecek", "sil@example.com");
  giden.length = 0;
  await s.gonder({ t: "hesap_sil" });
  bak("hesap silinince silindi e-postası", sonPosta("silindi", "sil@example.com") && sonPosta("silindi").veri.kullanici === "silinecek");
  bak("e-posta veritabanından silindi", acc.rows(`SELECT 1 FROM users WHERE email = 'sil@example.com'`).length === 0);
  const s2 = cihaz();
  await kayit(s2, "silinecek2", "sil@example.com");
  bak("silinen hesabın e-postasıyla yeni hesap açılır", s2.me().hesap, JSON.stringify(s2.ws.msgs));
  // web'den silme (kullanıcı adı ya da e-posta + şifre)
  giden.length = 0;
  const fd = new Request("https://ic/hesap-sil", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded", "cf-connecting-ip": "6.6.6.6" }, body: new URLSearchParams({ kullanici: "SIL@example.com", sifre: "Sifre-123", onay: "1" }).toString() });
  const r = await acc.webDelete(fd);
  bak("web'den e-postayla silme + silindi e-postası", r.kod === "silindi" && !!sonPosta("silindi", "sil@example.com"), JSON.stringify(r));
}

// ---------------- 3) uçtan uca (yerel sunucu) ----------------
const URL0 = process.env.SRV || "ws://127.0.0.1:8794";
const HTTP = URL0.replace("ws://", "http://").replace("wss://", "https://");
let acik = false;
try {
  await fetch(HTTP + "/", { signal: AbortSignal.timeout(1500) });
  acik = true;
} catch {}
const CH = "ABCDEFGHJKLMNPRSTUVYZ23456789";
const kod = () => Array.from({ length: 4 }, () => CH[Math.floor(Math.random() * CH.length)]).join("");
function oda(c, q) {
  return new Promise((res) => {
    const ws = new WebSocket(`${URL0}/oda/${c}?${new URLSearchParams(q)}`);
    const o = { ws, msgs: [], ilk: null };
    ws.onmessage = (e) => {
      if (typeof e.data !== "string" || e.data === "pong") return;
      const d = JSON.parse(e.data);
      o.msgs.push(d);
      if (!o.ilk && (d.t === "hosgeldin" || d.t === "hata")) res(((o.ilk = d), o));
    };
    ws.onclose = () => !o.ilk && res(o);
    setTimeout(() => res(o), 6000);
  });
}
if (!acik) {
  console.log("  (yerel sunucu 8794 kapalı: uçtan uca kısım atlandı)");
} else {
  console.log("— uçtan uca (8794) —");
  // kayıt (yerel + bağlama yok: kod test için bu bağlantıya da gelir)
  const tok = rastgeleAnahtar();
  const c = await bagla(URL0, tok);
  await c.bekle((d) => d.t === "ben");
  const h = "kt" + Math.random().toString(36).slice(2, 8);
  c.gonder({ t: "uye_ol", handle: h, sifre: "Test-12345", dil: "tr" });
  const r0 = await c.bekle((d) => d.t === "hata");
  bak("uçtan uca: e-postasız kayıt reddedilir", r0 && /E-posta/.test(r0.m), JSON.stringify(r0));
  c.gonder({ t: "uye_ol", handle: h, eposta: h + "@test.hatdustu.app", sifre: "Test-12345", dil: "tr", ad: "Sahte" });
  const r1 = await c.bekle((d) => d.t === "ben" && d.hesap);
  bak("uçtan uca: kayıt, ad = kullanıcı adı", r1 && r1.handle === h && r1.name === h, JSON.stringify(r1));
  const tk = await c.bekle((d) => d.t === "test_posta" && d.tur === "dogrula");
  bak("uçtan uca: yerel testte doğrulama kodu yakalanır", tk && /^\d{6}$/.test(tk.kod), JSON.stringify(c.msgs.map((m) => m.t)));
  if (tk) {
    c.gonder({ t: "eposta_dogrula", kod: tk.kod });
    bak("uçtan uca: e-posta doğrulanır", !!(await c.bekle((d) => d.t === "dogrulandi")));
  }
  const c2 = await bagla(URL0, rastgeleAnahtar());
  await c2.bekle((d) => d.t === "ben");
  c2.gonder({ t: "uye_ol", handle: h + "x", eposta: (h + "@TEST.hatdustu.app").toUpperCase(), sifre: "Test-12345" });
  const r2 = await c2.bekle((d) => d.t === "hata");
  bak("uçtan uca: aynı e-posta reddedilir", r2 && /zaten bir hesap/.test(r2.m), JSON.stringify(r2));
  c2.gonder({ t: "sifre_unuttum", kim: h });
  const sk = await c2.bekle((d) => d.t === "test_posta" && d.tur === "sifirla");
  bak("uçtan uca: sıfırlama kodu yakalanır", sk && /^\d{6}$/.test(sk.kod));
  if (sk) {
    c2.msgs.length = 0;
    c2.gonder({ t: "sifre_sifirla", kim: h, kod: sk.kod, sifre: "Yeni-12345" });
    const g = await c2.bekle((d) => d.t === "giris_ok" || d.t === "hata");
    bak("uçtan uca: şifre sıfırlanır, yeni anahtar", g && g.t === "giris_ok" && g.token !== tok, JSON.stringify(g));
    const kp = await c.bekle((d) => d.t === "oturum_kapandi", 3000);
    bak("uçtan uca: eski oturum kapandı", !!kp);
    if (g && g.token) await hesapSil(URL0, g.token);
  }
  c.ws.close();
  c2.ws.close();

  // misafir odaya giremez
  const m1 = await oda(kod(), { ad: "Misafir", kur: "1", davet: "0", hesap: rastgeleAnahtar(), dil: "tr" });
  bak("misafir (kayıtsız anahtar) oda kuramaz", m1.ilk && m1.ilk.t === "hata" && m1.ilk.hesap_yok === true, JSON.stringify(m1.ilk));
  const m2 = await oda(kod(), { ad: "Anahtarsiz", kur: "1", davet: "0", dil: "tr" });
  bak("anahtarsız oda kurulamaz", m2.ilk && m2.ilk.t === "hata" && /hesap aç/.test(m2.ilk.m), JSON.stringify(m2.ilk));
  const q1 = await fetch(HTTP + "/hizli");
  bak("misafir Hızlı Oyun'a giremez (403)", q1.status === 403, String(q1.status));
  const q2 = await fetch(HTTP + "/hizli", { headers: { "x-hesap": rastgeleAnahtar() } });
  bak("kayıtsız anahtarla Hızlı Oyun yok (403)", q2.status === 403, String(q2.status));
  // hesaplı oyuncu: ad hesaptan gelir, profil mesajı adı değiştirmez
  const a = await hesapAc(URL0, "kta");
  const q3 = await fetch(HTTP + "/hizli", { headers: { "x-hesap": a.token } });
  const q3j = await q3.json();
  bak("hesaplı Hızlı Oyun alır", q3.status === 200 && String(q3j.kod).length === 4, JSON.stringify(q3j));
  const K = kod();
  const o1 = await oda(K, { ad: "SahteAd", kur: "1", davet: "0", hesap: a.token, dil: "tr" });
  bak("hesaplı oda kurar", o1.ilk && o1.ilk.t === "hosgeldin", JSON.stringify(o1.ilk));
  const ben = o1.ilk && (o1.ilk.players || []).find((p) => p.id === o1.ilk.id);
  bak("odadaki ad = kullanıcı adı", ben && ben.name === a.handle, JSON.stringify(o1.ilk && o1.ilk.players));
  o1.ws.send(JSON.stringify({ t: "profil", ad: "Degistir", g: { govde: "erkek" } }));
  await uyu(500);
  const son = [...o1.msgs].reverse().find((m) => m.t === "oyuncular");
  bak("profil mesajı adı değiştirmez", !son || son.players.find((p) => p.id === o1.ilk.id).name === a.handle, JSON.stringify(son && son.players));
  const b = await hesapAc(URL0, "ktb");
  const o2 = await oda(K, { ad: "Baska", kur: "0", davet: "1", hesap: b.token, dil: "tr" });
  bak("ikinci hesap katılır, adı kullanıcı adı", o2.ilk && o2.ilk.t === "hosgeldin" && o2.ilk.players.some((p) => p.name === b.handle), JSON.stringify(o2.ilk));
  const o3 = await oda(K, { ad: "Misafir", kur: "0", davet: "1", hesap: rastgeleAnahtar(), dil: "tr" });
  bak("misafir koda katılamaz", o3.ilk && o3.ilk.t === "hata" && o3.ilk.hesap_yok, JSON.stringify(o3.ilk));
  o1.ws.close();
  o2.ws.close();
  await hesapSil(URL0, a.token);
  await hesapSil(URL0, b.token);
}

console.log(`\nkayit_test: ${ok} geçti, ${hata} hatalı`);
process.exit(hata ? 1 : 0);
