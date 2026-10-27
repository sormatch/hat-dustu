// Gerçek uygulama içi satın almanın SUNUCU doğrulaması (App Store + Google Play). Gizli anahtar GEREKMEZ:
//
// iOS (StoreKit 2): telefon, satın almanın imzalı işlem kaydını (JWS "signedTransaction", jwsRepresentation) yollar.
//   JWS başlığındaki x5c zinciri [yaprak, ara, kök] burada doğrulanır: kök, aşağıya gömülü "Apple Root CA - G3" ile
//   bayt bayt aynı olmalı; ara sertifika kökün, yaprak aranın anahtarıyla imzalı olmalı (ECDSA P-384/SHA-384); Apple'ın
//   amaç işaretleri (OID) bulunmalı; sertifikalar işlemin imza anında geçerli olmalı; JWS imzası yaprağın anahtarıyla
//   (ES256) tutmalı. Sonra içerik: bundleId, ürün, tür (Consumable), ortam (Sandbox ya da Production), iade yok.
// Android (Google Play Billing): telefon originalJson + signature yollar. İmza, uygulamanın Play Console'daki
//   "Lisans anahtarı" (RSA açık anahtarı, GOOGLE_LISANS_ANAHTARI) ile RSASSA-PKCS1-v1_5 / SHA-1 doğrulanır;
//   sonra packageName, ürün, purchaseState = 0 (satın alındı).
// Aynı işlemin iki kez elmas vermemesi accounts.js'te: purchases.islem tekil ("ios:<transactionId>" / "android:<purchaseToken>").
// Test: cd server && node test/odeme_test.mjs (testte kök sertifika ve anahtar seçenekle değiştirilir; canlıda değişmez).

export const BUNDLE_ID = "com.sormatch.hatdustu"; // App Store paket kimliği (export_presets.cfg iOS)
export const PAKET_ADI = "com.sormatch.hatdustu"; // Google Play paket adı (export_presets.cfg Android)

// Google Play Console > uygulama > Para kazanma (Monetize) > Para kazanma kurulumu (Monetization setup) >
// "Lisanslama" bölümündeki base64 RSA açık anahtarı (MIIBIjANBgkqh... ile başlar, tek satır). AÇIK anahtardır, gizli değil.
// BOŞKEN Android satın alma kapalı kalır: mağazada paketler "YAKINDA" görünür.
export const GOOGLE_LISANS_ANAHTARI = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEApxsJp63fdkyQwCudWZzIafr9Gx4a0255HSr1lu7KEqvKoo8X6D8H9erKVmJXYJQnHaHrMN4TFM3QuWk284Li6LfvOqD+RS88ewg5Jb6k3Em+3CVpW1e3bIiSxwCd1mn9pc0jrhJv6Yf0QBiSP3zKX18VaUVlBqmpOIKcwqtAOGoHqYFPM6PWZdtkI0COdX7jJsnrJIfHASfed9a5aUDg9xWDRwTOYEC/cuZ6LtWoWKO1Vp300srqRy+8lwi131AOgU43kdWz9Z3XQAxdgD8Nh6+LM3ifaWz8YpSlAxa8wbwI1lR3caQZ0VgFCI23dxryW5IrszwYif8rRncFkD69kQIDAQAB";

// Apple Root CA - G3 (https://www.apple.com/certificateauthority/AppleRootCA-G3.cer)
// SHA-256 parmak izi 63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79, 2039'a kadar geçerli.
export const APPLE_KOK_G3 =
  "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==";

// Apple'ın sertifika amaç işaretleri (Apple'ın kendi doğrulama kitaplığıyla aynı denetim)
export const OID_APPLE_YAPRAK = "1.2.840.113635.100.6.11.1"; // App Store makbuz imzalama
export const OID_APPLE_ARA = "1.2.840.113635.100.6.2.1"; // Apple WWDR ara sertifikası

const OID_EC_ANAHTAR = "1.2.840.10045.2.1";
const EGRI = { "1.2.840.10045.3.1.7": ["P-256", 32], "1.3.132.0.34": ["P-384", 48] };
const OZET = { "1.2.840.10045.4.3.2": "SHA-256", "1.2.840.10045.4.3.3": "SHA-384" };
const ORTAMLAR = new Set(["Production", "Sandbox"]);

// Telefonun hangi mağazada gerçek satın alma yapabileceği (ekonomi özetinde "odeme")
export function acikPlatformlar() {
  return { ios: true, android: GOOGLE_LISANS_ANAHTARI !== "" };
}

// ---------- yardımcılar ----------
export function b64(s) {
  const t = String(s || "").replace(/-/g, "+").replace(/_/g, "/").replace(/\s+/g, "");
  const bin = atob(t + "===".slice((t.length + 3) % 4));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function esit(a, b) {
  if (a.length !== b.length) return false;
  let f = 0;
  for (let i = 0; i < a.length; i++) f |= a[i] ^ b[i];
  return f === 0;
}

const red = (neden) => ({ ok: false, neden });

// ---------- DER (X.509) okuma: yalnız sertifikada geçen tek baytlık etiketler ----------
function tlv(b, i) {
  if (i + 2 > b.length) throw new Error("der");
  const tag = b[i];
  let len = b[i + 1];
  let p = i + 2;
  if (len & 0x80) {
    const n = len & 0x7f;
    if (n < 1 || n > 3) throw new Error("der");
    len = 0;
    for (let k = 0; k < n; k++) len = len * 256 + b[p++];
  }
  const son = p + len;
  if (son > b.length) throw new Error("der");
  return { tag, bas: i, ic: p, son };
}

function cocuklar(b, t) {
  const out = [];
  let i = t.ic;
  while (i < t.son) {
    const c = tlv(b, i);
    out.push(c);
    i = c.son;
  }
  if (i !== t.son) throw new Error("der");
  return out;
}

function oidOku(b, t) {
  if (t.tag !== 0x06) throw new Error("oid");
  const v = b.subarray(t.ic, t.son);
  const parca = [];
  let n = 0;
  for (let i = 0; i < v.length; i++) {
    n = n * 128 + (v[i] & 0x7f);
    if (!(v[i] & 0x80)) {
      if (parca.length === 0) parca.push(n < 80 ? Math.floor(n / 40) : 2, n < 80 ? n % 40 : n - 80);
      else parca.push(n);
      n = 0;
    }
  }
  return parca.join(".");
}

function zamanOku(b, t) {
  const s = new TextDecoder().decode(b.subarray(t.ic, t.son));
  let y, r;
  if (t.tag === 0x17) {
    const yy = Number(s.slice(0, 2));
    y = yy < 50 ? 2000 + yy : 1900 + yy;
    r = s.slice(2);
  } else if (t.tag === 0x18) {
    y = Number(s.slice(0, 4));
    r = s.slice(4);
  } else throw new Error("zaman");
  const ms = Date.UTC(y, Number(r.slice(0, 2)) - 1, Number(r.slice(2, 4)), Number(r.slice(4, 6)), Number(r.slice(6, 8)), Number(r.slice(8, 10)) || 0);
  if (!Number.isFinite(ms)) throw new Error("zaman");
  return ms;
}

// Sertifikanın doğrulamada gereken parçaları
export function sertifika(der) {
  const kok = tlv(der, 0);
  if (kok.tag !== 0x30 || kok.son !== der.length) throw new Error("sertifika");
  const [tbsT, algT, imzaT] = cocuklar(der, kok);
  if (!tbsT || !algT || !imzaT || imzaT.tag !== 0x03 || der[imzaT.ic] !== 0) throw new Error("sertifika");
  const f = cocuklar(der, tbsT);
  const k = f[0].tag === 0xa0 ? 1 : 0;
  const [, icAlg, issuer, gecerlik, subject, spki] = f.slice(k, k + 6);
  const alg = oidOku(der, cocuklar(der, algT)[0]);
  if (oidOku(der, cocuklar(der, icAlg)[0]) !== alg) throw new Error("sertifika");
  const [nb, na] = cocuklar(der, gecerlik);
  const anAlg = cocuklar(der, cocuklar(der, spki)[0]);
  const uzanti = new Set();
  const ext = f.slice(k + 6).find((x) => x.tag === 0xa3);
  if (ext) {
    for (const e of cocuklar(der, cocuklar(der, ext)[0])) uzanti.add(oidOku(der, cocuklar(der, e)[0]));
  }
  return {
    tbs: der.subarray(tbsT.bas, tbsT.son),
    alg,
    imza: der.subarray(imzaT.ic + 1, imzaT.son),
    issuer: der.subarray(issuer.bas, issuer.son),
    subject: der.subarray(subject.bas, subject.son),
    bas: zamanOku(der, nb),
    bit: zamanOku(der, na),
    spki: der.subarray(spki.bas, spki.son),
    anahtarTuru: oidOku(der, anAlg[0]),
    egri: anAlg[1] && anAlg[1].tag === 0x06 ? oidOku(der, anAlg[1]) : "",
    uzanti,
  };
}

// X.509 ECDSA imzası DER (SEQUENCE{r, s}) -> WebCrypto'nun beklediği ham r||s
export function ecdsaHam(der, n) {
  const s = tlv(der, 0);
  const [r, ss] = cocuklar(der, s);
  const out = new Uint8Array(2 * n);
  for (const [j, t] of [r, ss].entries()) {
    let v = der.subarray(t.ic, t.son);
    while (v.length > n && v[0] === 0) v = v.subarray(1);
    if (v.length > n) throw new Error("imza");
    out.set(v, j * n + (n - v.length));
  }
  return out;
}

async function ecAnahtar(c) {
  const e = EGRI[c.egri];
  if (c.anahtarTuru !== OID_EC_ANAHTAR || !e) throw new Error("anahtar");
  return [await crypto.subtle.importKey("spki", c.spki, { name: "ECDSA", namedCurve: e[0] }, false, ["verify"]), e[1]];
}

// alt sertifika üst sertifikanın anahtarıyla imzalı mı
async function imzaliMi(alt, ust) {
  const ozet = OZET[alt.alg];
  if (!ozet || !esit(alt.issuer, ust.subject)) return false;
  const [anahtar, n] = await ecAnahtar(ust);
  return crypto.subtle.verify({ name: "ECDSA", hash: ozet }, anahtar, ecdsaHam(alt.imza, n), alt.tbs);
}

// ---------- iOS: StoreKit 2 imzalı işlem (JWS) ----------
// Dönen: {ok:true, islem, urun, adet, ortam, transactionId, ...} ya da {ok:false, neden}
// sec.kok yalnız testte değişir (kendi test kökü); canlı kod her zaman APPLE_KOK_G3 kullanır.
export async function dogrulaApple(jws, sec = {}) {
  const kokDer = b64(sec.kok || APPLE_KOK_G3);
  const bundle = sec.bundle || BUNDLE_ID;
  try {
    const parca = String(jws || "").split(".");
    if (parca.length !== 3 || parca[0].length > 12000 || parca[1].length > 12000) return red("bicim");
    const bas = JSON.parse(new TextDecoder().decode(b64(parca[0])));
    const yuk = JSON.parse(new TextDecoder().decode(b64(parca[1])));
    if (!bas || bas.alg !== "ES256" || !Array.isArray(bas.x5c) || bas.x5c.length !== 3) return red("baslik");
    const zincir = bas.x5c.map((x) => b64(x));
    if (!esit(zincir[2], kokDer)) return red("kok");
    const [yaprak, ara, kok] = zincir.map(sertifika);
    if (!ara.uzanti.has(OID_APPLE_ARA) || !yaprak.uzanti.has(OID_APPLE_YAPRAK)) return red("oid");
    // sertifikalar işlemin imzalandığı anda geçerli olmalı (Apple'ın kitaplığı da imza tarihine bakar)
    const an = Number(yuk.signedDate) || Date.now();
    for (const c of [yaprak, ara, kok]) if (an < c.bas || an > c.bit) return red("sure");
    if (!(await imzaliMi(ara, kok)) || !(await imzaliMi(yaprak, ara))) return red("zincir");
    if (EGRI[yaprak.egri]?.[0] !== "P-256") return red("anahtar");
    const [anahtar] = await ecAnahtar(yaprak);
    const imza = b64(parca[2]);
    if (imza.length !== 64) return red("imza");
    const veri = new TextEncoder().encode(parca[0] + "." + parca[1]);
    if (!(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, anahtar, imza, veri))) return red("imza");
    // içerik
    if (yuk.bundleId !== bundle) return red("bundle");
    if (!ORTAMLAR.has(yuk.environment)) return red("ortam");
    if (yuk.type !== "Consumable") return red("tur");
    if (yuk.revocationDate) return red("iade");
    const tid = String(yuk.transactionId || "");
    if (!/^[0-9]{1,30}$/.test(tid)) return red("islem");
    return {
      ok: true,
      platform: "ios",
      islem: "ios:" + tid,
      urun: String(yuk.productId || ""),
      adet: Math.max(1, Math.min(10, Number(yuk.quantity) || 1)),
      ortam: yuk.environment,
      ozet: { transactionId: tid, originalTransactionId: String(yuk.originalTransactionId || ""), ortam: yuk.environment,
        tarih: Number(yuk.purchaseDate) || 0, ulke: String(yuk.storefront || ""), fiyat: Number(yuk.price) || 0, para: String(yuk.currency || "") },
    };
  } catch (e) {
    return red("bozuk");
  }
}

// ---------- Android: Google Play Billing originalJson + signature ----------
// sec.anahtar yalnız testte değişir; canlıda GOOGLE_LISANS_ANAHTARI.
export async function dogrulaGoogle(json, imza, sec = {}) {
  const anahtar = sec.anahtar !== undefined ? sec.anahtar : GOOGLE_LISANS_ANAHTARI;
  const paket = sec.paket || PAKET_ADI;
  if (!anahtar) return red("anahtar_yok");
  try {
    const metin = String(json || "");
    if (!metin || metin.length > 8000) return red("bicim");
    const k = await crypto.subtle.importKey("spki", b64(anahtar), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-1" }, false, ["verify"]);
    if (!(await crypto.subtle.verify("RSASSA-PKCS1-v1_5", k, b64(imza), new TextEncoder().encode(metin)))) return red("imza");
    const j = JSON.parse(metin);
    if (j.packageName !== paket) return red("paket");
    if ((j.purchaseState ?? 0) !== 0) return red("durum"); // 0 satın alındı (bekleyen ödeme 4: gönderilmez)
    const tok = String(j.purchaseToken || "");
    if (tok.length < 10 || tok.length > 1000) return red("islem");
    const urun = String(j.productId || (Array.isArray(j.productIds) ? j.productIds[0] : "") || "");
    return {
      ok: true,
      platform: "android",
      islem: "android:" + tok,
      urun,
      adet: Math.max(1, Math.min(10, Number(j.quantity) || 1)),
      ortam: j.purchaseType === 0 ? "Test" : "Production", // purchaseType 0: lisans test hesabıyla yapılan test satın alması
      ozet: { siparis: String(j.orderId || ""), tarih: Number(j.purchaseTime) || 0, test: j.purchaseType === 0 },
    };
  } catch (e) {
    return red("bozuk");
  }
}
