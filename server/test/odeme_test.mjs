// Gerçek ödeme doğrulaması (odeme.js + accounts.js odemeIsle) testleri:  cd server && node test/odeme_test.mjs
// 1) Gerçek Apple sertifikası: koda gömülü Apple Root CA - G3 ile Apple WWDR G6 ara sertifikası doğrulanır
//    (DER okuyucu ve ECDSA P-384 imza dönüşümü gerçek Apple verisiyle denenir).
// 2) iOS JWS: bu testte üretilen kendi test kökü (P-384) -> ara (P-384, Apple OID'li) -> yaprak (P-256, Apple OID'li)
//    zinciriyle imzalı StoreKit 2 işlemleri. Doğru olan kabul, sahte imza / değiştirilmiş içerik / yanlış zincir /
//    yanlış bundle / yanlış tür / süresi geçmiş sertifika / iade edilmiş işlem reddedilir. Gerçek kökle (testte
//    değiştirilmemiş) test zinciri reddedilir.
// 3) Android: test RSA anahtar çiftiyle imzalı originalJson; yanlış imza / paket / durum reddedilir, anahtar boşken kapalı.
// 4) Hesap nesnesi (sahte Durable Object): elmas verilir, aynı işlem iki kez elmas vermez (aynı ya da başka hesap,
//    eşzamanlı istek dahil), Başlangıç Paketi'nin hediye kasası bir kez, makbuzsuz istek test modu dışında reddedilir.
// 5) Yerel sunucu açıksa (ws://127.0.0.1:8794): uçtan uca fiyatlar, sahte makbuz reddi.
import { DatabaseSync } from "node:sqlite";
import * as E from "../src/ekonomi.js";
import * as O from "../src/odeme.js";

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

const S = crypto.subtle;
const enc = new TextEncoder();
const b64 = (u) => Buffer.from(u).toString("base64");
const b64u = (u) => Buffer.from(u).toString("base64url");

// ---------------- DER yazıcı (test sertifikaları için) ----------------
function uzunluk(n) {
  if (n < 128) return [n];
  const b = [];
  while (n > 0) (b.unshift(n & 0xff), (n = Math.floor(n / 256)));
  return [0x80 | b.length, ...b];
}
const tlv = (tag, ...icler) => {
  const ic = Buffer.concat(icler.map((x) => Buffer.from(x)));
  return Buffer.concat([Buffer.from([tag, ...uzunluk(ic.length)]), ic]);
};
const seq = (...x) => tlv(0x30, ...x);
function tamsayi(u) {
  let b = Buffer.from(u);
  while (b.length > 1 && b[0] === 0 && !(b[1] & 0x80)) b = b.subarray(1);
  if (b[0] & 0x80) b = Buffer.concat([Buffer.from([0]), b]);
  return tlv(0x02, b);
}
function oid(s) {
  const p = s.split(".").map(Number);
  const out = [40 * p[0] + p[1]];
  for (const n of p.slice(2)) {
    const b = [n & 0x7f];
    let v = Math.floor(n / 128);
    while (v > 0) (b.unshift(0x80 | (v & 0x7f)), (v = Math.floor(v / 128)));
    out.push(...b);
  }
  return tlv(0x06, out);
}
const ad = (cn) => seq(tlv(0x31, seq(oid("2.5.4.3"), tlv(0x0c, enc.encode(cn)))));
function utc(ms) {
  const d = new Date(ms).toISOString(); // 2026-10-27T03:04:05.000Z
  return tlv(0x17, enc.encode(d.slice(2, 4) + d.slice(5, 7) + d.slice(8, 10) + d.slice(11, 13) + d.slice(14, 16) + d.slice(17, 19) + "Z"));
}
const hamDer = (raw) => seq(tamsayi(raw.subarray(0, raw.length / 2)), tamsayi(raw.subarray(raw.length / 2)));

const ALG = { "SHA-256": "1.2.840.10045.4.3.2", "SHA-384": "1.2.840.10045.4.3.3" };
// sertifika: konu, veren (ad + özel anahtar), konu açık anahtarı, geçerlilik, uzantı OID'leri
async function sertifika({ konu, veren, verenAnahtar, acik, bas, bit, oidler = [], ozet = "SHA-384", seri = 1 }) {
  const spki = Buffer.from(await S.exportKey("spki", acik));
  const alg = seq(oid(ALG[ozet]));
  const uz = oidler.length ? [tlv(0xa3, seq(...oidler.map((o) => seq(oid(o), tlv(0x04, [0x05, 0x00])))))] : [];
  const tbs = seq(tlv(0xa0, tamsayi([2])), tamsayi([seri]), alg, ad(veren), seq(utc(bas), utc(bit)), ad(konu), spki, ...uz);
  const imza = new Uint8Array(await S.sign({ name: "ECDSA", hash: ozet }, verenAnahtar, tbs));
  return seq(tbs, alg, tlv(0x03, Buffer.concat([Buffer.from([0]), hamDer(imza)])));
}

const anahtar = (egri) => S.generateKey({ name: "ECDSA", namedCurve: egri }, true, ["sign", "verify"]);
const SIMDI = Date.now();
const YIL = 365 * 86400000;
const kokA = await anahtar("P-384");
const araA = await anahtar("P-384");
const yaprakA = await anahtar("P-256");
const kokS = await sertifika({ konu: "Test Kok", veren: "Test Kok", verenAnahtar: kokA.privateKey, acik: kokA.publicKey, bas: SIMDI - YIL, bit: SIMDI + 10 * YIL });
const araS = await sertifika({ konu: "Test Ara", veren: "Test Kok", verenAnahtar: kokA.privateKey, acik: araA.publicKey, bas: SIMDI - YIL, bit: SIMDI + 5 * YIL, oidler: ["2.5.29.19", O.OID_APPLE_ARA], seri: 2 });
const yaprakS = await sertifika({ konu: "Test Yaprak", veren: "Test Ara", verenAnahtar: araA.privateKey, acik: yaprakA.publicKey, bas: SIMDI - YIL, bit: SIMDI + 2 * YIL, oidler: [O.OID_APPLE_YAPRAK], seri: 3 });
const KOK = b64(kokS);
const secA = { kok: KOK };

let tid = 2000000700000000;
function yukle(ek = {}) {
  return {
    transactionId: String(++tid), originalTransactionId: String(tid), bundleId: O.BUNDLE_ID, productId: "elmas_550",
    purchaseDate: SIMDI - 5000, signedDate: SIMDI - 1000, quantity: 1, type: "Consumable", inAppOwnershipType: "PURCHASED",
    environment: "Sandbox", storefront: "TUR", price: 179990, currency: "TRY", ...ek,
  };
}
async function jws(yuk, { zincir = [yaprakS, araS, kokS], imzaci = yaprakA.privateKey, alg = "ES256" } = {}) {
  const h = b64u(enc.encode(JSON.stringify({ alg, x5c: zincir.map(b64) })));
  const p = b64u(enc.encode(JSON.stringify(yuk)));
  const imza = new Uint8Array(await S.sign({ name: "ECDSA", hash: "SHA-256" }, imzaci, enc.encode(h + "." + p)));
  return h + "." + p + "." + b64u(imza);
}

// ---------------- 1) gerçek Apple sertifikası ----------------
{
  const G6 =
    "MIIDFjCCApygAwIBAgIUIsGhRwp0c2nvU4YSycafPTjzbNcwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMjEwMzE3MjAzNzEwWhcNMzYwMzE5MDAwMDAwWjB1MUQwQgYDVQQDDDtBcHBsZSBXb3JsZHdpZGUgRGV2ZWxvcGVyIFJlbGF0aW9ucyBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTELMAkGA1UECwwCRzYxEzARBgNVBAoMCkFwcGxlIEluYy4xCzAJBgNVBAYTAlVTMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAEbsQKC94PrlWmZXnXgtxzdVJL8T0SGYngDRGpngn3N6PT8JMEb7FDi4bBmPhCnZ3/sq6PF/cGcKXWsL5vOteRhyJ45x3ASP7cOB+aao90fcpxSv/EZFbniAbNgZGhIhpIo4H6MIH3MBIGA1UdEwEB/wQIMAYBAf8CAQAwHwYDVR0jBBgwFoAUu7DeoVgziJqkipnevr3rr9rLJKswRgYIKwYBBQUHAQEEOjA4MDYGCCsGAQUFBzABhipodHRwOi8vb2NzcC5hcHBsZS5jb20vb2NzcDAzLWFwcGxlcm9vdGNhZzMwNwYDVR0fBDAwLjAsoCqgKIYmaHR0cDovL2NybC5hcHBsZS5jb20vYXBwbGVyb290Y2FnMy5jcmwwHQYDVR0OBBYEFD8vlCNR01DJmig97bB85c+lkGKZMA4GA1UdDwEB/wQEAwIBBjAQBgoqhkiG92NkBgIBBAIFADAKBggqhkjOPQQDAwNoADBlAjBAXhSq5IyKogMCPtw490BaB677CaEGJXufQB/EqZGd6CSjiCtOnuMTbXVXmxxcxfkCMQDTSPxarZXvNrkxU3TkUMI33yzvFVVRT4wxWJC994OsdcZ4+RGNsYDyR5gmdr0nDGg=";
  const kok = O.sertifika(O.b64(O.APPLE_KOK_G3));
  const ara = O.sertifika(O.b64(G6));
  bak("gerçek: Apple kökü P-384, 2039'a kadar", kok.egri === "1.3.132.0.34" && new Date(kok.bit).getUTCFullYear() === 2039);
  bak("gerçek: WWDR G6 Apple ara OID'li", ara.uzanti.has(O.OID_APPLE_ARA));
  const k = await S.importKey("spki", kok.spki, { name: "ECDSA", namedCurve: "P-384" }, false, ["verify"]);
  bak("gerçek: WWDR G6 Apple köküyle imzalı", await S.verify({ name: "ECDSA", hash: "SHA-384" }, k, O.ecdsaHam(ara.imza, 48), ara.tbs));
  const bozuk = new Uint8Array(ara.tbs);
  bozuk[40] ^= 1;
  bak("gerçek: bozulmuş ara sertifika tutmaz", !(await S.verify({ name: "ECDSA", hash: "SHA-384" }, k, O.ecdsaHam(ara.imza, 48), bozuk)));
}

// ---------------- 2) iOS JWS ----------------
{
  const y = yukle();
  const s = await O.dogrulaApple(await jws(y), secA);
  bak("ios: doğru zincirli JWS kabul", s.ok && s.islem === "ios:" + y.transactionId && s.urun === "elmas_550" && s.ortam === "Sandbox", JSON.stringify(s));
  bak("ios: özet (ülke, para birimi)", s.ok && s.ozet.ulke === "TUR" && s.ozet.para === "TRY");
  bak("ios: Production da kabul", (await O.dogrulaApple(await jws(yukle({ environment: "Production" })), secA)).ok);
  const r = async (j, neden, ad2) => {
    const x = await O.dogrulaApple(j, secA);
    bak("ios: " + ad2, !x.ok && (!neden || x.neden === neden), JSON.stringify(x));
  };
  // gerçek Apple köküyle (test kökü verilmeden) test zinciri reddedilir
  const g = await O.dogrulaApple(await jws(yukle()));
  bak("ios: gerçek kök beklenirken test zinciri red", !g.ok && g.neden === "kok", JSON.stringify(g));
  // sahte imza: zincirdeki yaprak değil başka anahtar imzalar
  const baska = await anahtar("P-256");
  await r(await jws(yukle(), { imzaci: baska.privateKey }), "imza", "sahte imzalı JWS red");
  // içerik değiştirilmiş (imza eski içeriğe)
  const asil = await jws(yukle({ productId: "elmas_100" }));
  const [h, , i] = asil.split(".");
  await r(h + "." + b64u(enc.encode(JSON.stringify(yukle({ productId: "elmas_6500" })))) + "." + i, "imza", "değiştirilmiş içerik red");
  // ara sertifika kökün değil sahtecinin anahtarıyla imzalı (kök baytları aynı)
  const sahteKok = await anahtar("P-384");
  const sahteAra = await sertifika({ konu: "Test Ara", veren: "Test Kok", verenAnahtar: sahteKok.privateKey, acik: araA.publicKey, bas: SIMDI - YIL, bit: SIMDI + YIL, oidler: [O.OID_APPLE_ARA] });
  await r(await jws(yukle(), { zincir: [yaprakS, sahteAra, kokS] }), "zincir", "kökün imzalamadığı ara red");
  // yaprak Apple OID'siz
  const oidsiz = await sertifika({ konu: "Test Yaprak", veren: "Test Ara", verenAnahtar: araA.privateKey, acik: yaprakA.publicKey, bas: SIMDI - YIL, bit: SIMDI + YIL });
  await r(await jws(yukle(), { zincir: [oidsiz, araS, kokS] }), "oid", "OID'siz yaprak red");
  // süresi geçmiş yaprak
  const eski = await sertifika({ konu: "Test Yaprak", veren: "Test Ara", verenAnahtar: araA.privateKey, acik: yaprakA.publicKey, bas: SIMDI - 3 * YIL, bit: SIMDI - YIL, oidler: [O.OID_APPLE_YAPRAK] });
  await r(await jws(yukle(), { zincir: [eski, araS, kokS] }), "sure", "süresi geçmiş sertifika red");
  await r(await jws(yukle(), { zincir: [yaprakS, araS] }), "baslik", "eksik zincir red");
  await r(await jws(yukle(), { alg: "none" }), "baslik", "alg none red");
  await r(await jws(yukle({ bundleId: "com.baska.oyun" })), "bundle", "yanlış bundle red");
  await r(await jws(yukle({ environment: "Xcode" })), "ortam", "Xcode ortamı red");
  await r(await jws(yukle({ type: "Non-Consumable" })), "tur", "tüketilemez ürün red");
  await r(await jws(yukle({ revocationDate: SIMDI })), "iade", "iade edilmiş işlem red");
  await r("abc.def", "bicim", "bozuk metin red");
  await r("", "bicim", "boş makbuz red");
}

// ---------------- 3) Android ----------------
const rsa = await S.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-1" }, true, ["sign", "verify"]);
const LISANS = b64(new Uint8Array(await S.exportKey("spki", rsa.publicKey)));
const secG = { anahtar: LISANS };
let tokNo = 0;
function satin(ek = {}) {
  const tok = "tok" + ++tokNo + "abcdefghij.AO-J1Oz" + "x".repeat(40);
  return JSON.stringify({ orderId: "GPA.3300-0000-0000-" + tokNo, packageName: O.PAKET_ADI, productId: "elmas_1200", purchaseTime: SIMDI, purchaseState: 0, purchaseToken: tok, quantity: 1, acknowledged: false, ...ek });
}
const imzala = async (json, k = rsa.privateKey) => b64(new Uint8Array(await S.sign("RSASSA-PKCS1-v1_5", k, enc.encode(json))));
{
  const j = satin();
  const s = await O.dogrulaGoogle(j, await imzala(j), secG);
  bak("android: doğru imzalı satın alma kabul", s.ok && s.urun === "elmas_1200" && s.islem === "android:" + JSON.parse(j).purchaseToken, JSON.stringify(s));
  const r = async (json, imza, neden, ad2, sec = secG) => {
    const x = await O.dogrulaGoogle(json, imza, sec);
    bak("android: " + ad2, !x.ok && x.neden === neden, JSON.stringify(x));
  };
  const baska = await S.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-1" }, true, ["sign"]);
  const j2 = satin();
  await r(j2, await imzala(j2, baska.privateKey), "imza", "başka anahtarla imza red");
  await r(j2.replace("elmas_1200", "elmas_6500"), await imzala(j2), "imza", "değiştirilmiş json red");
  const j3 = satin({ packageName: "com.baska.oyun" });
  await r(j3, await imzala(j3), "paket", "yanlış paket red");
  const j4 = satin({ purchaseState: 4 });
  await r(j4, await imzala(j4), "durum", "bekleyen ödeme red");
  await r(j2, await imzala(j2), "anahtar_yok", "lisans anahtarı boşken kapalı", { anahtar: "" });
  bak("android: koddaki anahtar şimdilik boş -> Android satışı kapalı", O.GOOGLE_LISANS_ANAHTARI === "" ? !O.acikPlatformlar().android : O.acikPlatformlar().android);
  const p = await O.dogrulaGoogle(satin({ productIds: ["elmas_100"], productId: undefined }), "", secG);
  bak("android: imzasız red", !p.ok);
}

// ---------------- 4) hesap nesnesi ----------------
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
  constructor(st, token) {
    this.att = { token, handle: "", room: "" };
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
}
function hesapKur(env) {
  const st = sahteDO();
  const acc = new Accounts(st, { SPAM_SINIRI: "0", ...env });
  acc.odemeSec = { apple: secA, google: secG }; // yalnız testte: test kökü ve test lisans anahtarı
  let n = 0;
  const oyuncu = () => {
    const token = "tok" + String(++n).padStart(20, "0") + Math.random().toString(36).slice(2, 8);
    acc.sql.exec(`INSERT INTO users (token) VALUES (?)`, token);
    const e = acc.eco(token);
    e.gems = 1000;
    acc.saveEco(token, e);
    const ws = new SahteWS(st, token);
    return { token, ws, gonder: (d) => ((ws.msgs = []), acc.webSocketMessage(ws, JSON.stringify(d))), eco: () => acc.eco(token) };
  };
  return { acc, oyuncu };
}
{
  const { acc, oyuncu } = hesapKur({ ODEME_TEST: "0" });
  const a = oyuncu();
  await a.gonder({ t: "ekonomi" });
  const ek = a.ws.son("ekonomi");
  bak("özet: gerçek ödeme platformları", ek.odeme && ek.odeme.ios === true && typeof ek.odeme.android === "boolean");
  const fiy = Object.fromEntries(ek.paketler.map((p) => [p.kimlik, p.fiyat_tl]));
  bak("özet: yeni fiyatlar", fiy.baslangic === 59.99 && fiy.elmas_100 === 39.99 && fiy.elmas_550 === 179.99 && fiy.elmas_1200 === 349.99 && fiy.elmas_2500 === 699.99 && fiy.elmas_6500 === 1749.99, JSON.stringify(fiy));
  bak("özet: test modu kapalı", ek.odeme_test === false);

  await a.gonder({ t: "elmas_paketi", paket: "elmas_550" });
  bak("makbuzsuz istek test modu dışında red", a.ws.son("hata") && a.ws.son("hata").m === "Ödeme sistemi henüz açılmadı." && a.eco().gems === 1000);

  // iOS: ilk gönderim elmas verir
  const y = yukle({ productId: "elmas_550" });
  const j = await jws(y);
  await a.gonder({ t: "elmas_paketi", platform: "ios", paket: "elmas_550", islem: "ios:" + y.transactionId, makbuz: j });
  const al = a.ws.son("elmas_alindi");
  bak("ios hesap: doğrulanan makbuz elmas verir", al && al.elmas === 550 && a.eco().gems === 1550 && al.istemci === "ios:" + y.transactionId && al.islem === "ios:" + y.transactionId, JSON.stringify(a.ws.msgs));
  const kayit = acc.rows(`SELECT * FROM purchases WHERE islem = ?`, "ios:" + y.transactionId);
  bak("ios hesap: satın alma kaydı (özet, kart bilgisi yok)", kayit.length === 1 && kayit[0].platform === "ios" && kayit[0].test === 1 && JSON.parse(kayit[0].makbuz).transactionId === y.transactionId);
  // aynı makbuz ikinci kez
  await a.gonder({ t: "elmas_paketi", platform: "ios", paket: "elmas_550", islem: "ios:" + y.transactionId, makbuz: j });
  bak("ios hesap: aynı işlem ikinci kez elmas vermez", a.ws.son("odeme_tamam") && a.ws.son("odeme_tamam").zaten && !a.ws.son("elmas_alindi") && a.eco().gems === 1550);
  // başka hesap aynı makbuzla
  const b = oyuncu();
  await b.gonder({ t: "elmas_paketi", platform: "ios", paket: "elmas_550", makbuz: j });
  bak("ios hesap: başka hesap aynı makbuzla elmas alamaz", b.ws.son("odeme_tamam") && b.eco().gems === 1000);
  // sahte makbuz
  const sahte = await jws(yukle(), { imzaci: (await anahtar("P-256")).privateKey });
  await b.gonder({ t: "elmas_paketi", platform: "ios", paket: "elmas_550", islem: "x", makbuz: sahte });
  bak("ios hesap: sahte imzalı makbuz red, elmas yok", b.ws.son("odeme_red") && b.ws.son("odeme_red").istemci === "x" && b.eco().gems === 1000);
  // yanlış bundle
  await b.gonder({ t: "elmas_paketi", platform: "ios", paket: "elmas_550", makbuz: await jws(yukle({ bundleId: "com.baska" })) });
  bak("ios hesap: yanlış bundle red", b.ws.son("odeme_red") && b.eco().gems === 1000);
  // bilinmeyen ürün
  await b.gonder({ t: "elmas_paketi", platform: "ios", paket: "x", makbuz: await jws(yukle({ productId: "elmas_9999" })) });
  bak("ios hesap: bilinmeyen ürün red", b.ws.son("odeme_red") && b.ws.son("odeme_red").neden === "urun");
  // makbuzdaki ürün esas alınır (istekteki paket adı değil)
  await b.gonder({ t: "elmas_paketi", platform: "ios", paket: "elmas_6500", makbuz: await jws(yukle({ productId: "elmas_100" })) });
  bak("ios hesap: makbuzdaki ürün esas", b.ws.son("elmas_alindi") && b.ws.son("elmas_alindi").paket === "elmas_100" && b.eco().gems === 1100);
  // eşzamanlı: aynı makbuz 5 kez aynı anda
  const c = oyuncu();
  const jc = await jws(yukle({ productId: "elmas_2500" }));
  await Promise.all([1, 2, 3, 4, 5].map(() => acc.webSocketMessage(c.ws, JSON.stringify({ t: "elmas_paketi", platform: "ios", makbuz: jc }))));
  bak("ios hesap: eşzamanlı 5 istek -> bir kez elmas", c.eco().gems === 3500 && c.ws.msgs.filter((m) => m.t === "elmas_alindi").length === 1 && c.ws.msgs.filter((m) => m.t === "odeme_tamam").length === 4, String(c.eco().gems));
  // Başlangıç Paketi: hediye kasa bir kez
  const d = oyuncu();
  await d.gonder({ t: "elmas_paketi", platform: "ios", makbuz: await jws(yukle({ productId: "baslangic" })) });
  const d1 = d.ws.son("elmas_alindi");
  bak("başlangıç: 300 elmas + 1 nadir kasa", d1 && d1.elmas === 300 && d1.hediye_kasa === 1 && d.eco().stats.hediye_kasa === 1 && d.eco().gems === 1300);
  await d.gonder({ t: "ekonomi" });
  bak("başlangıç: vitrinde ALINDI", d.ws.son("ekonomi").paketler.find((p) => p.kimlik === "baslangic").alindi === true);
  await d.gonder({ t: "elmas_paketi", platform: "ios", makbuz: await jws(yukle({ productId: "baslangic" })) });
  const d2 = d.ws.son("elmas_alindi");
  bak("başlangıç: ikinci ödemede elmas var, hediye kasa yok", d2 && d2.hediye_kasa === 0 && d.eco().stats.hediye_kasa === 1 && d.eco().gems === 1600);
  // Android
  const g = oyuncu();
  const ja = satin({ productId: "elmas_100" });
  const ia = await imzala(ja);
  await g.gonder({ t: "elmas_paketi", platform: "android", paket: "elmas_100", islem: "android:" + JSON.parse(ja).purchaseToken, makbuz: { json: ja, imza: ia } });
  bak("android hesap: doğrulanan satın alma elmas verir", g.ws.son("elmas_alindi") && g.eco().gems === 1100 && g.ws.son("elmas_alindi").istemci === "android:" + JSON.parse(ja).purchaseToken, JSON.stringify(g.ws.msgs));
  await g.gonder({ t: "elmas_paketi", platform: "android", paket: "elmas_100", makbuz: { json: ja, imza: ia } });
  bak("android hesap: aynı purchaseToken ikinci kez elmas vermez", g.ws.son("odeme_tamam") && g.eco().gems === 1100);
  const jy = satin({ packageName: "com.baska" });
  await g.gonder({ t: "elmas_paketi", platform: "android", makbuz: { json: jy, imza: await imzala(jy) } });
  bak("android hesap: yanlış paket red", g.ws.son("odeme_red") && g.eco().gems === 1100);
  await g.gonder({ t: "elmas_paketi", platform: "android", makbuz: { json: ja.replace("elmas_100", "elmas_6500"), imza: ia } });
  bak("android hesap: değiştirilmiş json red", g.ws.son("odeme_red") && g.eco().gems === 1100);
  await g.gonder({ t: "elmas_paketi", platform: "windows", makbuz: "x" });
  bak("bilinmeyen platform red", g.ws.son("odeme_red") && g.ws.son("odeme_red").neden === "platform");
  // hesap silinince kayıt kalır, aynı makbuz yeni hesapta yine çalışmaz
  acc.deleteAccount(a.token, a.ws);
  const yeni = oyuncu();
  await yeni.gonder({ t: "elmas_paketi", platform: "ios", makbuz: j });
  bak("silinen hesabın makbuzu yeniden kullanılamaz", yeni.ws.son("odeme_tamam") && yeni.eco().gems === 1000);
}
{
  // test modu (yalnız yerel, ODEME_TEST=1) eskisi gibi
  const { oyuncu } = hesapKur({ ODEME_TEST: "1" });
  const t = oyuncu();
  await t.gonder({ t: "elmas_paketi", paket: "baslangic", platform: "Windows" });
  bak("test modu: makbuzsuz elmas", t.ws.son("elmas_alindi") && t.ws.son("elmas_alindi").test && t.eco().gems === 1300);
  await t.gonder({ t: "elmas_paketi", paket: "baslangic" });
  bak("test modu: başlangıç bir kez", t.ws.son("hata") && t.ws.son("hata").m === "Bu paketi zaten aldın." && t.eco().gems === 1300);
  await t.gonder({ t: "elmas_paketi", platform: "ios", makbuz: "sahte.jws.metni" });
  bak("test modu: makbuz varsa yine doğrulanır", t.ws.son("odeme_red") && t.eco().gems === 1300);
}

// ---------------- 5) yerel sunucu (uçtan uca) ----------------
const SRV = process.env.SRV || "ws://127.0.0.1:8794";
async function baglan(token) {
  return new Promise((res) => {
    let ws;
    try {
      ws = new WebSocket(`${SRV}/hesap?token=${token}`);
    } catch {
      return res(null);
    }
    const c = { ws, msgs: [], bekle: [] };
    const zaman = setTimeout(() => res(null), 4000);
    ws.onerror = () => (clearTimeout(zaman), res(null));
    ws.onmessage = (e) => {
      if (e.data === "pong") return;
      const d = JSON.parse(e.data);
      c.msgs.push(d);
      for (const w of [...c.bekle]) if (w.f(d)) (c.bekle.splice(c.bekle.indexOf(w), 1), w.r(d));
      if (d.t === "ekonomi" && !c.hazir) (c.hazir = true, clearTimeout(zaman), res(c));
    };
    c.sor = (o, f, ms = 4000) =>
      new Promise((r) => {
        const w = { f: (d) => f.includes(d.t), r };
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
    bak("e2e: özet fiyatlar ve odeme", e0.paketler.find((p) => p.kimlik === "elmas_6500").fiyat_tl === 1749.99 && e0.odeme && e0.odeme.ios === true, JSON.stringify(e0.odeme));
    const r1 = await c.sor({ t: "elmas_paketi", platform: "ios", paket: "elmas_550", islem: "ios:1", makbuz: await jws(yukle()) }, ["odeme_red", "elmas_alindi", "odeme_tamam", "hata"]);
    bak("e2e: test köklü makbuz gerçek sunucuda red", r1 && r1.t === "odeme_red" && r1.istemci === "ios:1", JSON.stringify(r1));
    if (!e0.odeme_test) {
      const r2 = await c.sor({ t: "elmas_paketi", paket: "elmas_550" }, ["hata", "elmas_alindi"]);
      bak("e2e: makbuzsuz istek red (ODEME_TEST=0)", r2 && r2.t === "hata", JSON.stringify(r2));
    }
    const e1 = await c.sor({ t: "ekonomi" }, ["ekonomi"]);
    bak("e2e: elmas değişmedi", e1 && e1.elmas === e0.elmas);
    c.ws.close();
  }
}

console.log(`ödeme testi: ${ok} geçti, ${hata} hata`);
process.exit(hata ? 1 : 0);
