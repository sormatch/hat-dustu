// Hesaplar ve arkadaşlık: tek bir "Accounts" nesnesi (SQLite).
// Oyun açılınca  wss://<sunucu>/hesap?token=...  ile bağlanır; token cihazda üretilen gizli anahtardır.
// Kullanıcı adı (@ad) bir kez seçilir. Şifre konursa hesap başka cihazdan "giriş" ile açılır (sunucu o hesabın anahtarını verir).
// Şifreler PBKDF2-SHA256 ile tuzlanıp saklanır; profil (görünüş, elmas, eşyalar) JSON olarak hesapta durur. İstek → kabul → arkadaş; arkadaşlar birbirini lobiye davet edebilir.

import * as E from "./ekonomi.js";
import * as M from "./market.js";
import * as O from "./odeme.js";
import { tx, metin } from "./metin.js";
import { adUygun } from "./suzgec.js";
import { yonetim } from "./yonetim.js";
import { postaGonder, postaAcik, epostaTemiz, epostaMaske } from "./posta_gonder.js";

export const AD_RED = "Bu ad kullanılamaz"; // küfür / uygunsuz ad (suzgec.js)

const HANDLE_RE = /^[a-z0-9_.]{3,16}$/;
const ODA_RE = /^[A-Z0-9]{4}$/;
const LOGIN_MAX = 8; // bir kullanıcı adına bu kadar yanlış şifreden sonra...
const LOGIN_WINDOW = 15 * 60000; // ...15 dakika giriş kapalı (bağlantı yenilense de)
const MAX_PENDING = 50; // bekleyen giden istek sınırı
const WEB_MAX = 10; // web'den hesap silme: bir IP adresinden 15 dakikada en fazla bu kadar deneme
const GUN = 86400000;
// Spam sınırı: hesap bağlantısı başına saniyede 10 mesaj (en çok 30 birikmiş); telemetri IP başına dakikada ~30 paket
const MESAJ_ORAN = [10, 30];
const TELEMETRI_ORAN = [0.5, 20];
const MESAJ_MAX = 20000; // hesap mesajı (profil kaydı 16000 karaktere kadar)
// E-posta kodları (doğrulama, şifre sıfırlama): sunucuda yalnızca tuzlu özet (SHA-256) saklanır
const DAKIKA = 60000;
const KOD_SURE = { dogrula: 30 * DAKIKA, sifirla: 15 * DAKIKA };
const KOD_DENEME = 5; // bu kadar yanlış denemede kod iptal olur
const KOD_GONDERIM = { dogrula: [5, 60 * DAKIKA], sifirla: [3, 15 * DAKIKA] }; // hesap başına: [en çok, süre]
const KOD_ARA = 45000; // aynı hesaba iki kod arasında en az bu kadar
const SIFIRLA_IP_ORAN = [1 / 90, 10]; // şifre sıfırlama isteği: IP başına 10 birikmiş, 90 sn'de bir yenilenir
const KAYIT_IP_ORAN = [1 / 360, 10]; // hesap açma: IP başına saatte ~10 (yerel testte yok)
const YEREL = new Set(["127.0.0.1", "localhost", "[::1]", "::1"]);
const SITE = "https://hatdustu.app";
const DESTEK = "destek@hatdustu.app";

// jeton kovası: kova = {j, t}; dönen true ise geçebilir
function kovaIzin(map, key, [hiz, kap]) {
  const now = Date.now();
  let o = map.get(key);
  if (!o) o = { j: kap, t: now };
  o.j = Math.min(kap, o.j + ((now - o.t) / 1000) * hiz);
  o.t = now;
  map.set(key, o);
  if (o.j < 1) return false;
  o.j -= 1;
  return true;
}
// Saklama süreleri (gizlilik ve hesap silme sayfalarında yazanla aynı tut: gizlilik.js, hesap_sil.js)
export const KALICI = 8.64e15; // süresiz yasak (yasak_bitis)
export const UYARI_METNI = "Topluluk kurallarını ihlal ettiğin için uyarıldın. Tekrarlanırsa hesabın askıya alınabilir.";
// Türkiye saatiyle "27.10.2026 14:30"
export function tarihTR(ms) {
  const d = new Date(Number(ms) + 3 * 3600000);
  const p = (n) => String(n).padStart(2, "0");
  return `${p(d.getUTCDate())}.${p(d.getUTCMonth() + 1)}.${d.getUTCFullYear()} ${p(d.getUTCHours())}:${p(d.getUTCMinutes())}`;
}
export const KAYIT_SURE ={ telemetri: 30 * GUN, sikayet: 365 * GUN, satin_alma: 5 * 365 * GUN };

// Kullanıcı adı kuralı: kısa ve anlaşılır Türkçe hata ("" = uygun)
function handleError(h) {
  if (!h) return "Kullanıcı adını yaz.";
  if (/[çğıöşüâîû̇]/.test(h)) return "Kullanıcı adında Türkçe harf olamaz (ç, ğ, ı, ö, ş, ü).";
  if (/\s/.test(h)) return "Kullanıcı adında boşluk olamaz.";
  if (h.length < 3) return "Kullanıcı adı en az 3 karakter olmalı.";
  if (h.length > 16) return "Kullanıcı adı en fazla 16 karakter olabilir.";
  if (!HANDLE_RE.test(h)) return "Kullanıcı adında sadece harf, rakam, _ ve . olabilir.";
  if (!/[a-z0-9]/.test(h)) return "Kullanıcı adında en az bir harf ya da rakam olmalı.";
  if (!adUygun(h)) return AD_RED;
  return "";
}


// Başkalarına gösterilen ad: kayıtta kalmış uygunsuz bir ad varsa kullanıcı adı gösterilir
// Hesabı olan oyuncunun adı her yerde kullanıcı adıdır (ayrı görünen ad yok).
function shownName(name, handle) {
  if (handle) return handle;
  return name && adUygun(name) ? name : "Mahkum";
}

// Görünen ad: görünmez/kontrol karakterleri atılır, boşluklar sadeleşir, en fazla 16 harf (emoji bölünmez)
function cleanName(s) {
  const t = String(s || "").replace(/[\u0000-\u001f\u007f​-‏‪-‮⁦-⁩﻿]/g, "").replace(/\s+/g, " ").trim();
  return Array.from(t).slice(0, 16).join("").trim();
}

export class Accounts {
  constructor(state, env) {
    this.state = state;
    this.env = env || {};
    this.sql = state.storage.sql;
    this.sql.exec(`CREATE TABLE IF NOT EXISTS users (token TEXT PRIMARY KEY, handle TEXT UNIQUE, name TEXT)`);
    this.sql.exec(`CREATE TABLE IF NOT EXISTS friends (a TEXT, b TEXT, status TEXT, PRIMARY KEY (a, b))`);
    // şikayetler (moderasyon için saklanır) ve engellemeler (engellenenin sesi duyulmaz, daveti gelmez)
    this.sql.exec(`CREATE TABLE IF NOT EXISTS reports (id INTEGER PRIMARY KEY AUTOINCREMENT, from_token TEXT, target TEXT, room TEXT, reason TEXT, note TEXT, ts INTEGER)`);
    this.sql.exec(`CREATE TABLE IF NOT EXISTS blocks (a TEXT, b TEXT, PRIMARY KEY (a, b))`);
    // elmas satın almaları (mağaza makbuzu ile; test modunda makbuzsuz)
    this.sql.exec(`CREATE TABLE IF NOT EXISTS purchases (token TEXT, paket TEXT, elmas INTEGER, fiyat REAL, platform TEXT, makbuz TEXT, test INTEGER, ts INTEGER)`);
    // islem: mağaza işlem kimliği ("ios:<transactionId>" / "android:<purchaseToken>"), TEKİL: aynı makbuz iki kez elmas vermez.
    // makbuz: doğrulanmış işlemin kısa özeti (işlem/sipariş no, ortam, tarih, ülke, para birimi); ödeme bilgisi yoktur.
    try {
      this.sql.exec(`ALTER TABLE purchases ADD COLUMN islem TEXT`);
    } catch {}
    this.sql.exec(`CREATE UNIQUE INDEX IF NOT EXISTS purchases_islem ON purchases(islem) WHERE islem IS NOT NULL AND islem != ''`);
    // çökme raporları ve analitik olaylar (30 gün saklanır)
    this.sql.exec(`CREATE TABLE IF NOT EXISTS events (ts INTEGER, kind TEXT, surum TEXT, platform TEXT, data TEXT)`);
    // ekonomi ve ilerleme sunucuda: elmas, eşyalar, XP, istatistik, günlük görev, başarım, haftalık puan
    for (const col of ["pass TEXT", "profil TEXT", "gems INTEGER", "items TEXT", "xp INTEGER DEFAULT 0", "stats TEXT", "gorev TEXT", "basarim TEXT", "hafta TEXT", "hafta_xp INTEGER DEFAULT 0"]) {
      try {
        this.sql.exec(`ALTER TABLE users ADD COLUMN ${col}`);
      } catch {}
    }
    // moderasyon: yasak (bitiş zamanı; KALICI = süresiz), bekleyen uyarı; şikayette şikayet edilenin hesabı ve durumu
    for (const col of ["yasak_bitis INTEGER DEFAULT 0", "yasak_neden TEXT", "uyari INTEGER DEFAULT 0"]) {
      try {
        this.sql.exec(`ALTER TABLE users ADD COLUMN ${col}`);
      } catch {}
    }
    for (const col of ["target_token TEXT", "target_ad TEXT", "durum TEXT DEFAULT 'acik'", "islem TEXT"]) {
      try {
        this.sql.exec(`ALTER TABLE reports ADD COLUMN ${col}`);
      } catch {}
    }
    // hesap anahtarıyla engelleme (maçtaki oyuncu, misafir dahil): a engelleyen, bt engellenenin anahtarı, ad o anki adı
    this.sql.exec(`CREATE TABLE IF NOT EXISTS blocks_t (a TEXT, bt TEXT, ad TEXT, ts INTEGER, PRIMARY KEY (a, bt))`);
    // arkadaşa hediye kayıtları (market.js): goruldu 0 = alıcı çevrimdışıydı, bağlanınca bildirilir
    // e-posta (zorunlu; küçük harf, tek hesap), doğrulandı mı, e-postaların dili
    for (const col of ["email TEXT", "email_ok INTEGER DEFAULT 0", "dil TEXT"]) {
      try {
        this.sql.exec(`ALTER TABLE users ADD COLUMN ${col}`);
      } catch {}
    }
    this.sql.exec(`CREATE UNIQUE INDEX IF NOT EXISTS users_email ON users(email) WHERE email IS NOT NULL AND email != ''`);
    // e-posta kodları: tuzlu özet, bitiş, yanlış deneme sayısı; gönderim kayıtları (hesap başına hız sınırı)
    this.sql.exec(`CREATE TABLE IF NOT EXISTS kodlar (token TEXT, tur TEXT, ozet TEXT, bitis INTEGER, deneme INTEGER DEFAULT 0, PRIMARY KEY (token, tur))`);
    this.sql.exec(`CREATE TABLE IF NOT EXISTS kod_gonderim (token TEXT, tur TEXT, ts INTEGER)`);
    this.sql.exec(`CREATE TABLE IF NOT EXISTS gifts (from_token TEXT, to_token TEXT, from_handle TEXT, kat TEXT, item TEXT, elmas INTEGER, ts INTEGER, goruldu INTEGER DEFAULT 0)`);
    // Arama dizinleri: gelen istekler (friends.b), beni engelleyenler, bekleyen hediyeler, kod sınırları, eski kayıt
    // temizliği. Dizinsiz her arkadaş listesi bütün tabloyu tarıyordu (27 Ekim yük testi).
    for (const [ad, tablo] of [["friends_b", "friends(b, status)"], ["blocks_b", "blocks(b)"], ["blocks_t_bt", "blocks_t(bt)"],
      ["gifts_to", "gifts(to_token)"], ["kod_gonderim_token", "kod_gonderim(token)"], ["events_ts", "events(ts)"],
      ["reports_hedef", "reports(target_token)"]]) {
      try {
        this.sql.exec(`CREATE INDEX IF NOT EXISTS ${ad} ON ${tablo}`);
      } catch {}
    }
    this.state.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
    this.loginFails = new Map(); // kullanıcı adı -> {n, ts}: yanlış şifre sayacı
    this.webFails = new Map(); // IP -> {n, ts}: web'den hesap silme denemeleri
    this.lastInvite = new Map(); // "a>b" -> zaman: davet yağmuruna karşı
    this.yonetimOturum = new Map(); // yönetim sayfası oturumu -> bitiş zamanı (yonetim.js)
    this.yonetimHata = new Map(); // yanlış yönetici anahtarı sayacı (IP -> {n, ts}; "*" = toplam)
    this.kovalar = new WeakMap(); // bağlantı -> mesaj jeton kovası
    this.telemetriIp = new Map(); // IP -> jeton kovası
    this.sifirlaIp = new Map(); // IP -> jeton kovası (şifre sıfırlama isteği)
    this.kayitIp = new Map(); // IP -> jeton kovası (hesap açma)
  }

  // a anahtarlı oyuncu b kullanıcı adını engellemiş mi (kullanıcı adıyla ya da maçta hesap anahtarıyla)
  blocked(aToken, bHandle) {
    if (!aToken || !bHandle) return false;
    if (this.rows(`SELECT 1 FROM blocks WHERE a = ? AND b = ?`, aToken, bHandle).length > 0) return true;
    const bt = this.tokenOf(bHandle);
    return !!bt && this.rows(`SELECT 1 FROM blocks_t WHERE a = ? AND bt = ?`, aToken, bt).length > 0;
  }

  // Bu anahtarın engellediği hesapların anahtarları (oda sesi ve Hızlı Oyun için; istemciye gönderilmez)
  engelTokenleri(token) {
    if (!token) return [];
    return this.rows(
      `SELECT bt AS t FROM blocks_t WHERE a = ? UNION SELECT u.token AS t FROM blocks b JOIN users u ON u.handle = b.b WHERE b.a = ?`,
      token, token,
    ).map((r) => r.t).filter(Boolean).slice(0, 300);
  }

  // İki yönde engel ilişkisi olan anahtarlar (benim engellediklerim + beni engelleyenler)
  engelIliskili(token) {
    if (!token) return [];
    const h = (this.rows(`SELECT handle FROM users WHERE token = ?`, token)[0] || {}).handle || "";
    const beniEngelleyen = this.rows(`SELECT a AS t FROM blocks_t WHERE bt = ? UNION SELECT a AS t FROM blocks WHERE b = ?`, token, h || "\u0000").map((r) => r.t);
    return [...new Set([...this.engelTokenleri(token), ...beniEngelleyen])].slice(0, 600);
  }

  // Hesap engelle (a -> b anahtarı). Engellenenin kullanıcı adı varsa arkadaşlık/istekler de kalkar.
  engelEkle(aToken, bToken, ad) {
    if (!aToken || !bToken || aToken === bToken) return false;
    this.sql.exec(`INSERT OR REPLACE INTO blocks_t (a, bt, ad, ts) VALUES (?, ?, ?, ?)`, aToken, bToken, String(ad || "").slice(0, 40), Date.now());
    const bh = (this.rows(`SELECT handle FROM users WHERE token = ?`, bToken)[0] || {}).handle || "";
    const ah = (this.rows(`SELECT handle FROM users WHERE token = ?`, aToken)[0] || {}).handle || "";
    if (bh) {
      this.sql.exec(`INSERT OR IGNORE INTO blocks (a, b) VALUES (?, ?)`, aToken, bh);
      if (ah) this.unlink(ah, bh);
    }
    this.engelListesiGonder(aToken);
    return true;
  }

  // Engellenenler listesi (ayarlar ekranı): kullanıcı adları + kullanıcı adı olmayan (misafir) engeller
  engelListesi(token) {
    const liste = this.rows(`SELECT b FROM blocks WHERE a = ?`, token).map((r) => r.b);
    const misafir = this.rows(
      `SELECT rowid AS k, ad FROM blocks_t t WHERE a = ? AND NOT EXISTS (SELECT 1 FROM users u WHERE u.token = t.bt AND u.handle IS NOT NULL AND u.handle != '') ORDER BY ts DESC LIMIT 100`,
      token,
    ).map((r) => ({ k: r.k, ad: r.ad || "?" }));
    return { t: "engeller", liste, misafir };
  }

  engelListesiGonder(token) {
    for (const ws of this.socketsOfToken(token)) this.send(ws, this.engelListesi(token));
  }

  // Yasak: { bitis, kalici } ya da null (süresi dolmuşsa null)
  yasak(token) {
    const u = token ? this.rows(`SELECT yasak_bitis FROM users WHERE token = ?`, token)[0] : null;
    const b = u ? Number(u.yasak_bitis) || 0 : 0;
    return b > Date.now() ? { bitis: b, kalici: b >= KALICI } : null;
  }

  // Oyuncuya gösterilen yasak mesajı (tarih Türkiye saatiyle)
  static yasakMetni(y) {
    if (y.kalici) return tx("Hesabın kalıcı olarak askıya alındı.");
    return tx("Hesabın {0} tarihine kadar askıya alındı.", tarihTR(y.bitis));
  }

  // Başkalarına gösterilen ad (kullanıcı adından)
  gorunenAd(handle) {
    if (!handle) return "";
    return shownName((this.rows(`SELECT name FROM users WHERE handle = ?`, handle)[0] || {}).name, handle);
  }

  tokenOf(handle) {
    return (this.rows(`SELECT token FROM users WHERE handle = ?`, handle)[0] || {}).token || "";
  }

  // İki kişi arasındaki tüm arkadaşlık ve istek satırlarını siler, iki tarafın listesini tazeler
  unlink(x, y) {
    this.sql.exec(`DELETE FROM friends WHERE (a = ? AND b = ?) OR (a = ? AND b = ?)`, x, y, y, x);
    this.refresh(x);
    this.refresh(y);
  }

  static hex(buf) {
    return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
  }

  async hash(password, saltHex) {
    const salt = new Uint8Array(saltHex.match(/../g).map((h) => parseInt(h, 16)));
    const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(password), "PBKDF2", false, ["deriveBits"]);
    const bits = await crypto.subtle.deriveBits({ name: "PBKDF2", hash: "SHA-256", salt, iterations: 100000 }, key, 256);
    return Accounts.hex(bits);
  }

  async makePass(password) {
    const salt = Accounts.hex(crypto.getRandomValues(new Uint8Array(16)));
    return salt + ":" + (await this.hash(password, salt));
  }

  async checkPass(stored, password) {
    if (!stored) return false;
    const [salt, h] = stored.split(":");
    return (await this.hash(password, salt)) === h;
  }

  // Sahibine giden hesap özeti. E-posta yalnızca gizlenmiş biçimde ("al***@g***.com") ve yalnızca sahibine gider.
  me(token) {
    const u = this.rows(`SELECT handle, name, pass, profil, email, email_ok FROM users WHERE token = ?`, token)[0];
    let profil = null;
    try {
      profil = u && u.profil ? JSON.parse(u.profil) : null;
    } catch {}
    const handle = (u && u.handle) || "";
    return {
      t: "ben", handle, name: handle || (u && u.name) || "", hesap: !!(u && u.pass), profil,
      eposta_var: !!(u && u.email), eposta_ok: !!(u && u.email && u.email_ok), eposta: u && u.email ? epostaMaske(u.email) : "",
    };
  }

  // ---------- e-posta kodları ----------

  static async ozet(metin) {
    return Accounts.hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(metin)));
  }

  // 6 haneli yeni kod üretir (eskisi geçersiz olur); sunucuda yalnızca tuzlu özeti kalır
  async kodUret(token, tur) {
    const r = crypto.getRandomValues(new Uint32Array(1))[0] % 1000000;
    const kod = String(r).padStart(6, "0");
    const tuz = Accounts.hex(crypto.getRandomValues(new Uint8Array(8)));
    const ozet = tuz + ":" + (await Accounts.ozet(`${tuz}:${tur}:${token}:${kod}`));
    this.sql.exec(`INSERT OR REPLACE INTO kodlar (token, tur, ozet, bitis, deneme) VALUES (?, ?, ?, ?, 0)`, token, tur, ozet, Date.now() + KOD_SURE[tur]);
    this.sql.exec(`INSERT INTO kod_gonderim (token, tur, ts) VALUES (?, ?, ?)`, token, tur, Date.now());
    return kod;
  }

  // Bu hesaba şimdi yeni kod gönderilebilir mi (hesap başına sınır + iki kod arası bekleme)
  kodGonderilebilir(token, tur, aralikAtla = false) {
    const [max, sure] = KOD_GONDERIM[tur];
    const now = Date.now();
    const l = this.rows(`SELECT ts FROM kod_gonderim WHERE token = ? AND tur = ? AND ts > ? ORDER BY ts DESC`, token, tur, now - sure);
    if (l.length >= max) return false;
    return aralikAtla || !(l.length && now - Number(l[0].ts) < KOD_ARA);
  }

  // Kodu dener: "ok" | "yok" (kod istenmemiş / iptal) | "suresi" | "yanlis" | "iptal" (son yanlış deneme). Doğruysa kod silinir.
  async kodDene(token, tur, kod) {
    const r = this.rows(`SELECT ozet, bitis, deneme FROM kodlar WHERE token = ? AND tur = ?`, token, tur)[0];
    if (!r) return "yok";
    if (Number(r.bitis) < Date.now()) {
      this.sql.exec(`DELETE FROM kodlar WHERE token = ? AND tur = ?`, token, tur);
      return "suresi";
    }
    const k = String(kod || "").replace(/\D/g, "").slice(0, 6);
    const [tuz, h] = String(r.ozet).split(":");
    if (k.length === 6 && (await Accounts.ozet(`${tuz}:${tur}:${token}:${k}`)) === h) {
      this.sql.exec(`DELETE FROM kodlar WHERE token = ? AND tur = ?`, token, tur);
      return "ok";
    }
    const n = (Number(r.deneme) || 0) + 1;
    if (n >= KOD_DENEME) {
      this.sql.exec(`DELETE FROM kodlar WHERE token = ? AND tur = ?`, token, tur);
      return "iptal";
    }
    this.sql.exec(`UPDATE kodlar SET deneme = ? WHERE token = ? AND tur = ?`, n, token, tur);
    return "yanlis";
  }

  static kodHatasi(sonuc) {
    if (sonuc === "suresi") return "Kodun süresi doldu. Yeni kod iste.";
    if (sonuc === "iptal") return "Çok fazla yanlış deneme. Kod iptal edildi, yeni kod iste.";
    if (sonuc === "yok") return "Geçerli bir kod yok. Yeni kod iste.";
    return "Kod yanlış. Tekrar dene.";
  }

  // ---------- e-posta gönderimi (posta_gonder.js; hata fırlatmaz, akışı beklemez) ----------

  // Arka planda bitecek iş: cevap beklemeden sürer (Durable Object açık kalır)
  arka(p) {
    const q = Promise.resolve(p).catch(() => {});
    try {
      if (this.state && typeof this.state.waitUntil === "function") this.state.waitUntil(q);
    } catch {}
    return q;
  }

  // E-posta gönder. ws: yerel test bağlantısı (bağlama yokken kod {t:"test_posta"} ile yalnız ona gider)
  postala(tur, alici, dil, veri, ws) {
    if (ws && !postaAcik(this.env) && this.info(ws).yerel) this.send(ws, { t: "test_posta", tur, ...(veri && veri.kod ? { kod: veri.kod } : {}) });
    if (typeof this.postaKanca === "function") this.postaKanca(tur, alici, veri); // birim testte gönderilenleri yakalamak için
    return this.arka(postaGonder(this.env, tur, dil, alici, veri));
  }

  static zaman(dil) {
    return tarihTR(Date.now()) + (dil === "en" ? " (GMT+3)" : " (TSİ)");
  }

  // Kod e-postasındaki bağlantı (sunucunun web sayfası: kod zaten dolu gelir)
  static kodBaglantisi(koken, yol, handle, kod) {
    const o = String(koken || "").replace(/^ws(s?):/, "http$1:");
    const k = /^https?:\/\//.test(o) ? o : SITE;
    return `${k}${yol}?h=${encodeURIComponent(handle)}&k=${kod}`;
  }

  // Doğrulama kodu üret ve gönder (kayıt, e-posta ekleme, yeniden gönder). Dönen: gönderildi mi (hız sınırı)
  // yeniAdres: adres yeni değişti (iki kod arası bekleme yok; saatlik sınır yine geçerli)
  async dogrulamaGonder(token, ws, yeniAdres = false) {
    const u = this.rows(`SELECT handle, email, email_ok, dil FROM users WHERE token = ?`, token)[0];
    if (!u || !u.email || u.email_ok) return false;
    if (!this.kodGonderilebilir(token, "dogrula", yeniAdres)) return false;
    const kod = await this.kodUret(token, "dogrula");
    const me = ws ? this.info(ws) : {};
    this.postala("dogrula", u.email, u.dil, { ad: u.handle, kullanici: u.handle, kod, url: Accounts.kodBaglantisi(me.koken, "/eposta-dogrula", u.handle, kod) }, ws);
    return true;
  }

  // Hesabın anahtarını yeniler (şifre sıfırlanınca: eski anahtarla açık oturumlar kapanır). Dönen: yeni anahtar
  tokenYenile(eski) {
    const yeni = Accounts.hex(crypto.getRandomValues(new Uint8Array(16)));
    this.sql.exec(`UPDATE users SET token = ? WHERE token = ?`, yeni, eski);
    this.sql.exec(`UPDATE blocks SET a = ? WHERE a = ?`, yeni, eski);
    this.sql.exec(`UPDATE OR IGNORE blocks_t SET a = ? WHERE a = ?`, yeni, eski);
    this.sql.exec(`UPDATE OR IGNORE blocks_t SET bt = ? WHERE bt = ?`, yeni, eski);
    this.sql.exec(`UPDATE purchases SET token = ? WHERE token = ?`, yeni, eski);
    this.sql.exec(`UPDATE reports SET from_token = ? WHERE from_token = ?`, yeni, eski);
    this.sql.exec(`UPDATE reports SET target_token = ? WHERE target_token = ?`, yeni, eski);
    this.sql.exec(`UPDATE gifts SET from_token = ? WHERE from_token = ?`, yeni, eski);
    this.sql.exec(`UPDATE gifts SET to_token = ? WHERE to_token = ?`, yeni, eski);
    this.sql.exec(`DELETE FROM kodlar WHERE token = ?`, eski);
    this.sql.exec(`UPDATE kod_gonderim SET token = ? WHERE token = ?`, yeni, eski);
    for (const ws of this.socketsOfToken(eski)) {
      this.send(ws, { t: "oturum_kapandi", ...tx("Şifren değişti. Tekrar giriş yap.") });
      try {
        this.setInfo(ws, {});
        ws.close(4004, "sifre");
      } catch {}
    }
    return yeni;
  }

  // Kullanıcı adı ya da e-postadan hesap satırı
  hesapBul(kim) {
    const s = String(kim || "").trim().toLowerCase().slice(0, 120);
    if (!s) return null;
    if (s.includes("@") && !s.startsWith("@")) return this.rows(`SELECT token, handle, pass, email, email_ok, dil FROM users WHERE email = ?`, s)[0] || null;
    return this.rows(`SELECT token, handle, pass, email, email_ok, dil FROM users WHERE handle = ?`, s.replace(/^@/, ""))[0] || null;
  }

  rows(q, ...args) {
    return this.sql.exec(q, ...args).toArray();
  }

  // ---------- ekonomi ----------

  // Oyuncunun ekonomi kaydı (yoksa başlatır). Eski sürümden kalan profildeki elmas/eşyalar bir kez taşınır.
  eco(token) {
    const u = this.rows(`SELECT gems, items, xp, stats, gorev, basarim, hafta, hafta_xp, profil FROM users WHERE token = ?`, token)[0];
    if (!u) return null;
    const j = (v, d) => {
      try {
        return v ? JSON.parse(v) : d;
      } catch {
        return d;
      }
    };
    const e = {
      gems: u.gems,
      items: j(u.items, null),
      xp: u.xp || 0,
      stats: j(u.stats, {}),
      gorev: j(u.gorev, null),
      basarim: j(u.basarim, {}),
      hafta: u.hafta || "",
      hafta_xp: u.hafta_xp || 0,
    };
    if (e.gems === null || e.gems === undefined || e.items === null) {
      const old = j(u.profil, {});
      e.gems = Math.min(10000, Math.max(E.START_GEMS, Number(old.elmas) || 0));
      e.items = Array.isArray(old.sahip) ? old.sahip.filter((x) => typeof x === "string").slice(0, 500) : [];
    }
    if (!e.gorev || e.gorev.tarih !== E.today()) e.gorev = E.dailyMissions(token.slice(0, 12));
    if (e.hafta !== E.weekId()) {
      e.hafta = E.weekId();
      e.hafta_xp = 0;
    }
    return e;
  }

  saveEco(token, e) {
    this.sql.exec(
      `UPDATE users SET gems = ?, items = ?, xp = ?, stats = ?, gorev = ?, basarim = ?, hafta = ?, hafta_xp = ? WHERE token = ?`,
      e.gems, JSON.stringify(e.items), e.xp, JSON.stringify(e.stats), JSON.stringify(e.gorev), JSON.stringify(e.basarim), e.hafta, e.hafta_xp, token,
    );
  }

  // !!! TEST MODU: ödeme doğrulaması yokken elmas paketleri doğrudan eklenir (ekonomi.js TEST_ODEME) !!!
  testOdeme() {
    return E.TEST_ODEME || this.env.ODEME_TEST === "1";
  }

  // GERÇEK ÖDEME: telefon mağazadan aldığı imzalı makbuzu yollar:
  //   iOS     {t:"elmas_paketi", platform:"ios", paket, islem, makbuz:"<StoreKit 2 JWS>"}
  //   Android {t:"elmas_paketi", platform:"android", paket, islem, makbuz:{json:"<originalJson>", imza:"<signature>"}}
  // islem: telefonun kendi işlem anahtarı (cevapta "istemci" olarak geri gelir, telefon hangi işlemi bitireceğini bilir).
  // Cevaplar: yeni işlem -> "elmas_alindi" (+islem, istemci); daha önce işlenmiş -> "odeme_tamam" (zaten:true);
  // doğrulanamadı -> "odeme_red" (m). Telefon işlemi (iOS finish / Android consume) YALNIZ ilk ikisinde bitirir;
  // reddedilen işlem bitirilmez (sunucu tarafı bir hata düzelince bir sonraki açılışta yeniden denenir).
  // sec: yalnız testte (odeme_test.mjs) kök sertifika / lisans anahtarı değiştirmek için.
  async odemeIsle(ws, me, d, sec = this.odemeSec || {}) {
    const istemci = String(d.islem || "").slice(0, 300);
    const platform = String(d.platform || "").toLowerCase();
    const reddet = (neden, m = "Satın alma doğrulanamadı. Elmasların için tekrar denenecek.") => {
      console.log("odeme_red", platform, neden);
      this.send(ws, { t: "odeme_red", istemci, neden, ...tx(m) });
      return true;
    };
    let s;
    if (platform === "ios") s = await O.dogrulaApple(String(d.makbuz), sec.apple);
    else if (platform === "android") {
      const mk = d.makbuz && typeof d.makbuz === "object" ? d.makbuz : {};
      s = await O.dogrulaGoogle(String(mk.json || ""), String(mk.imza || ""), sec.google);
    } else return reddet("platform");
    if (!s.ok) return reddet(s.neden);
    const pack = E.paket(s.urun);
    if (!pack) return reddet("urun");
    // Buradan sonra BEKLEME (await) YOK: tekillik denetimi, kayıt ve elmas tek parça işlenir (Durable Object tek iş parçacıklı)
    if (!this.info(ws).token || this.info(ws).token !== me.token) return reddet("oturum", "Bağlantı değişti, satın alma birazdan yeniden denenecek.");
    if (this.rows(`SELECT 1 AS v FROM purchases WHERE islem = ?`, s.islem).length) {
      this.send(ws, { t: "odeme_tamam", istemci, islem: s.islem, paket: pack.kimlik, zaten: true });
      return true;
    }
    const e = this.eco(me.token);
    if (!e) return reddet("hesap", "Hesap bulunamadı.");
    e.stats.paketler = e.stats.paketler || {};
    // tek seferlik paket (Başlangıç) ikinci kez ödenmişse (iki cihazdan aynı anda): para alındığı için elmas verilir,
    // hediye kasa verilmez (hesap başına bir kez kuralı)
    const tekrar = pack.tek_sefer && !!e.stats.paketler[pack.kimlik];
    const elmas = pack.elmas * s.adet;
    const kasa = tekrar ? 0 : pack.hediye_kasa;
    try {
      this.sql.exec(`INSERT INTO purchases (token, paket, elmas, fiyat, platform, makbuz, test, ts, islem) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        me.token, pack.kimlik, elmas, pack.fiyat_tl * s.adet, s.platform, JSON.stringify(s.ozet).slice(0, 1000), s.ortam === "Production" ? 0 : 1, Date.now(), s.islem);
    } catch {
      this.send(ws, { t: "odeme_tamam", istemci, islem: s.islem, paket: pack.kimlik, zaten: true });
      return true;
    }
    e.gems += elmas;
    e.stats.paketler[pack.kimlik] = (e.stats.paketler[pack.kimlik] || 0) + s.adet;
    if (kasa) e.stats.hediye_kasa = (e.stats.hediye_kasa || 0) + kasa;
    e.stats.satin_alma = (e.stats.satin_alma || 0) + 1;
    this.saveEco(me.token, e);
    this.send(ws, { t: "elmas_alindi", paket: pack.kimlik, elmas, toplam: e.gems, hediye_kasa: kasa, istemci, islem: s.islem, ortam: s.ortam });
    this.send(ws, this.economy(me.token));
    return true;
  }

  // Telefona gönderilen ekonomi özeti
  economy(token) {
    const e = this.eco(token);
    if (!e) return { t: "ekonomi" };
    this.saveEco(token, e);
    const lv = E.levelOf(e.xp);
    const stats = { ...e.stats, seviye: lv.seviye };
    const basarimlar = E.ACHIEVEMENTS.map((a) => ({
      k: a.k, ad: a.ad, aciklama: a.aciklama, hedef: a.hedef, odul: a.odul,
      ilerleme: Math.min(a.hedef, stats[a.stat] || 0), alindi: !!e.basarim[a.k],
    }));
    return {
      t: "ekonomi", elmas: e.gems, sahip: e.items, xp: e.xp, ...lv, istatistik: e.stats,
      gorevler: e.gorev.liste, basarimlar, firsatlar: E.dailyDeals(), hafta_xp: e.hafta_xp,
      gunluk_hazir: e.stats.gunluk !== E.today(), seri: e.stats.seri || 0,
      // elmas paketleri; alındı: tek seferlik paket bu hesapta alınmış mı
      paketler: E.PAKETLER.map((p) => ({ ...p, alindi: p.tek_sefer && !!(e.stats.paketler || {})[p.kimlik] })),
      odeme_test: this.testOdeme(), test_odeme: this.testOdeme(),
      odeme: O.acikPlatformlar(), // gerçek satın alma hangi mağazada açık: {ios, android} (Android lisans anahtarı girilince)
      hediye_kasa: e.stats.hediye_kasa || 0, // Başlangıç Paketi'nden gelen, açılmamış ücretsiz nadir kasa
      kasalar: Object.fromEntries(Object.entries(E.CHESTS).map(([k, c]) => [k, c.price])),
      // mağaza: günlük/haftalık vitrin, setler, kasa güvencesi, olasılıklar, seviye yolu, istek listesi, hediye (market.js)
      ...M.ozet(e),
    };
  }

  // Bir maçın sonucu (oda sunucusundan): her oyuncuya XP, elmas, istatistik, görev ilerlemesi
  matchResult(list) {
    for (const r of list) {
      if (!r.token) continue;
      this.sql.exec(`INSERT OR IGNORE INTO users (token) VALUES (?)`, r.token);
      const e = this.eco(r.token);
      if (!e) continue;
      const rw = E.matchReward(r);
      const before = E.levelOf(e.xp).seviye;
      e.xp += rw.xp;
      e.hafta_xp += rw.xp;
      e.gems += rw.gems;
      e.stats.mac = (e.stats.mac || 0) + 1;
      if (r.sira === 1) e.stats.galibiyet = (e.stats.galibiyet || 0) + 1;
      E.applyMissions(e.gorev, r);
      this.saveEco(r.token, e);
      const after = E.levelOf(e.xp).seviye;
      for (const ws of this.socketsOfToken(r.token)) {
        this.send(ws, { t: "mac_odul", xp: rw.xp, elmas: rw.gems, seviye_atladi: after > before ? after : 0 });
        this.send(ws, this.economy(r.token));
      }
    }
  }

  // Ekonomi mesajları (misafir de kullanabilir). Dönen: true ise mesaj işlendi.
  ecoMessage(ws, me, d) {
    const err = (m, ...a) => this.send(ws, { t: "hata", ...tx(m, ...a) });
    // satın alma, set, kasa, istek listesi, seviye yolu, hediye: market.js
    if (M.mesaj(this, ws, me, d)) return true;
    switch (d.t) {
      case "ekonomi":
        this.send(ws, this.economy(me.token));
        return true;
      case "elmas_paketi":
      case "elmas_al": {
        // ELMAS PAKETİ. Makbuzlu istek (gerçek ödeme): odemeIsle doğrular (odeme.js) ve elmas verir; dönen Promise
        // webSocketMessage'da beklenir. Makbuzsuz istek yalnız TEST MODUNDA (ODEME_TEST=1) elmas verir, ödeme alınmaz.
        if (d.makbuz) return this.odemeIsle(ws, me, d);
        const pack = E.paket(d.paket);
        if (!pack) return err("Böyle bir paket yok."), true;
        if (!this.testOdeme()) return err("Ödeme sistemi henüz açılmadı."), true;
        const e = this.eco(me.token);
        e.stats.paketler = e.stats.paketler || {};
        if (pack.tek_sefer && e.stats.paketler[pack.kimlik]) return err("Bu paketi zaten aldın."), true;
        e.gems += pack.elmas;
        e.stats.paketler[pack.kimlik] = (e.stats.paketler[pack.kimlik] || 0) + 1;
        if (pack.hediye_kasa) e.stats.hediye_kasa = (e.stats.hediye_kasa || 0) + pack.hediye_kasa;
        e.stats.satin_alma = (e.stats.satin_alma || 0) + 1;
        this.saveEco(me.token, e);
        this.sql.exec(`INSERT INTO purchases (token, paket, elmas, fiyat, platform, makbuz, test, ts) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
          me.token, pack.kimlik, pack.elmas, pack.fiyat_tl, String(d.platform || "").slice(0, 12), "", 1, Date.now());
        this.send(ws, { t: "elmas_alindi", paket: pack.kimlik, elmas: pack.elmas, toplam: e.gems, hediye_kasa: pack.hediye_kasa, test: true });
        this.send(ws, this.economy(me.token));
        return true;
      }
      case "gunluk_al": {
        // günlük giriş ödülü: her gün bir kez, art arda gelinen gün sayısına göre artar (en fazla 7. gün)
        const e = this.eco(me.token);
        if (e.stats.gunluk === E.today()) return err("Bugünün ödülünü aldın."), true;
        const dun = new Date(Date.now() + 3 * 3600 * 1000 - 86400000).toISOString().slice(0, 10);
        e.stats.seri = e.stats.gunluk === dun ? Math.min(7, (e.stats.seri || 0) + 1) : 1;
        e.stats.gunluk = E.today();
        const odul = 30 + e.stats.seri * 10;
        e.gems += odul;
        this.saveEco(me.token, e);
        this.send(ws, { t: "odul", elmas: odul, ...metin("neden", ["Günlük ödül ({0}. gün)", [e.stats.seri]]) });
        this.send(ws, this.economy(me.token));
        return true;
      }
      case "gorev_al": {
        const e = this.eco(me.token);
        const m = e.gorev.liste[Number(d.i)];
        if (!m || m.alindi || m.ilerleme < m.hedef) return err("Görev henüz tamamlanmadı."), true;
        m.alindi = true;
        e.gems += m.odul;
        this.saveEco(me.token, e);
        this.send(ws, { t: "odul", elmas: m.odul, neden: m.ad });
        this.send(ws, this.economy(me.token));
        return true;
      }
      case "basarim_al": {
        const e = this.eco(me.token);
        const a = E.ACHIEVEMENTS.find((x) => x.k === String(d.k || ""));
        const stats = { ...e.stats, seviye: E.levelOf(e.xp).seviye };
        if (!a || e.basarim[a.k] || (stats[a.stat] || 0) < a.hedef) return err("Başarım henüz açılmadı."), true;
        e.basarim[a.k] = Date.now();
        e.gems += a.odul;
        this.saveEco(me.token, e);
        this.send(ws, { t: "odul", elmas: a.odul, neden: a.ad });
        this.send(ws, this.economy(me.token));
        return true;
      }
      case "sikayet": {
        // oyuncu şikayeti: hedef (kullanıcı adı ya da oyundaki adı), oda, neden (küfür, taciz, hile, uygunsuz ad, diğer)
        // (maçtaki oyuncu şikayeti oda sunucusundan gelir: sikayetEkle, /oda-sikayet)
        const hedef = String(d.hedef || "").trim().replace(/^@/, "").slice(0, 40);
        const r = this.sikayetEkle(me.token, this.tokenOf(hedef.toLowerCase()), hedef, d.oda, d.neden, d.not);
        this.send(ws, r.ok ? { t: "bilgi", m: "Şikayetin alındı. Teşekkürler." } : { t: "hata", ...tx(r.m) });
        return true;
      }
      case "engelle":
      case "engel_kaldir": {
        if (d.t === "engel_kaldir" && d.k !== undefined) {
          // kullanıcı adı olmayan (maçta engellenmiş misafir) engel: satır numarasıyla kalkar
          this.sql.exec(`DELETE FROM blocks_t WHERE a = ? AND rowid = ?`, me.token, Number(d.k) || 0);
          this.send(ws, this.engelListesi(me.token));
          return true;
        }
        const h = String(d.handle || "").trim().replace(/^@/, "").toLowerCase().slice(0, 16);
        if (!h || h === me.handle) return true;
        const ht = this.tokenOf(h);
        if (d.t === "engelle") {
          this.sql.exec(`INSERT OR IGNORE INTO blocks (a, b) VALUES (?, ?)`, me.token, h);
          if (ht) this.sql.exec(`INSERT OR REPLACE INTO blocks_t (a, bt, ad, ts) VALUES (?, ?, ?, ?)`, me.token, ht, h, Date.now());
          // engellenenle arkadaşlık ve bekleyen istekler (iki yönde) kalkar
          if (me.handle) this.unlink(me.handle, h);
        } else {
          this.sql.exec(`DELETE FROM blocks WHERE a = ? AND b = ?`, me.token, h);
          if (ht) this.sql.exec(`DELETE FROM blocks_t WHERE a = ? AND bt = ?`, me.token, ht);
        }
        this.send(ws, this.engelListesi(me.token));
        return true;
      }
      case "engeller":
        this.send(ws, this.engelListesi(me.token));
        return true;
      case "hesap_sil": {
        // Mağaza kuralı: hesap uygulamanın içinden silinebilmeli (web'den: /hesap-sil, deleteAccount ortak)
        this.deleteAccount(me.token, ws);
        return true;
      }
      case "liderlik": {
        const wk = E.weekId();
        const top = this.rows(`SELECT handle, name, hafta_xp, xp FROM users WHERE hafta = ? AND hafta_xp > 0 ORDER BY hafta_xp DESC LIMIT 50`, wk)
          .map((r, i) => ({ sira: i + 1, ad: shownName(r.name, r.handle), handle: r.handle || "", puan: r.hafta_xp, seviye: E.levelOf(r.xp || 0).seviye }));
        const mine = this.eco(me.token);
        const rank = mine && mine.hafta_xp > 0 ? this.rows(`SELECT COUNT(*) AS n FROM users WHERE hafta = ? AND hafta_xp > ?`, wk, mine.hafta_xp)[0].n + 1 : 0;
        this.send(ws, { t: "liderlik", hafta: wk, liste: top, benim_sira: rank, benim_puan: mine ? mine.hafta_xp : 0 });
        return true;
      }
    }
    return false;
  }

  // Şikayet kaydı (arkadaş listesinden ya da maçtan). Dönen: { ok } ya da { ok: false, m }
  sikayetEkle(fromToken, targetToken, targetAd, oda, neden, not) {
    const reasons = ["kufur", "taciz", "hile", "uygunsuz_ad", "diger"];
    const reason = reasons.includes(String(neden)) ? String(neden) : "diger";
    const recent = this.rows(`SELECT COUNT(*) AS n FROM reports WHERE from_token = ? AND ts > ?`, fromToken, Date.now() - 3600 * 1000)[0].n;
    if (recent >= 20) return { ok: false, m: "Çok fazla şikayet gönderdin, biraz sonra tekrar dene." };
    if (targetToken && targetToken === fromToken) return { ok: false, m: "Kendini şikayet edemezsin." };
    const ad = String(targetAd || "").slice(0, 40);
    this.sql.exec(`INSERT INTO reports (from_token, target, room, reason, note, ts, target_token, target_ad, durum) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'acik')`,
      fromToken, ad, String(oda || "").slice(0, 8), reason, String(not || "").slice(0, 300), Date.now(), targetToken || "", ad);
    return { ok: true };
  }

  // ---------- hesap silme (oyun içi "hesap_sil" ve web sayfası /hesap-sil aynı işi yapar) ----------
  // Hemen silinir: kullanıcı adı, görünen ad, şifre özeti, profil/görünüş, elmas, eşyalar, XP/seviye, görev,
  // başarım, istatistik, haftalık puan, arkadaşlıklar ve istekler, engellediğin ve seni engelleyen kayıtlar.
  // Hesaptan koparılıp saklanır: satın alma kayıtları (KAYIT_SURE.satin_alma) ve şikayetler (KAYIT_SURE.sikayet).
  // E-posta adresi de silinir; silmeden önce o adrese "silindi" e-postası gider (ws: yerel testte bildirim için).
  deleteAccount(token, ws) {
    const u = this.rows(`SELECT handle, email, dil FROM users WHERE token = ?`, token)[0];
    const handle = (u && u.handle) || "";
    if (u && u.email && handle) this.postala("silindi", u.email, u.dil, { kullanici: handle, zaman: Accounts.zaman(u.dil) }, ws);
    this.sql.exec(`DELETE FROM kodlar WHERE token = ?`, token);
    this.sql.exec(`DELETE FROM kod_gonderim WHERE token = ?`, token);
    if (handle) {
      // önce ilgili herkesi (arkadaşlar + istek gönderilen/gelen) bul, sonra sil, sonra listelerini tazele
      const others = this.rows(`SELECT b AS h FROM friends WHERE a = ? UNION SELECT a AS h FROM friends WHERE b = ?`, handle, handle).map((r) => r.h);
      this.sql.exec(`DELETE FROM friends WHERE a = ? OR b = ?`, handle, handle);
      this.sql.exec(`DELETE FROM blocks WHERE b = ?`, handle); // kullanıcı adı boşa çıkar; yeni sahibi engelli başlamasın
      this.loginFails.delete(handle);
      for (const h of others) this.refresh(h);
    }
    this.sql.exec(`DELETE FROM blocks WHERE a = ?`, token);
    this.sql.exec(`DELETE FROM blocks_t WHERE a = ? OR bt = ?`, token, token);
    this.sql.exec(`UPDATE reports SET target_token = '' WHERE target_token = ?`, token);
    // satın alma ve şikayet kayıtları hesaptan koparılır (anahtar silinir), süreleri dolunca temizlik() siler
    this.sql.exec(`UPDATE purchases SET token = '' WHERE token = ?`, token);
    this.sql.exec(`UPDATE reports SET from_token = '' WHERE from_token = ?`, token);
    // hediyeler: gelenler silinir, gönderilenler hesaptan koparılır (elmas harcaması kaydı gibi saklanır)
    this.sql.exec(`DELETE FROM gifts WHERE to_token = ?`, token);
    this.sql.exec(`UPDATE gifts SET from_token = '', from_handle = '' WHERE from_token = ?`, token);
    this.sql.exec(`DELETE FROM users WHERE token = ?`, token);
    // bu hesaba bağlı açık oturumlar kapanır (telefon yeni bir misafir olarak açılır)
    for (const ws of this.socketsOfToken(token)) {
      this.send(ws, { t: "hesap_silindi" });
      try {
        this.setInfo(ws, {});
        ws.close(1000, "silindi");
      } catch {}
    }
    return handle;
  }

  // Süresi dolan kayıtları siler (ara sıra çağrılır)
  temizlik() {
    const now = Date.now();
    this.sql.exec(`DELETE FROM events WHERE ts < ?`, now - KAYIT_SURE.telemetri);
    this.sql.exec(`DELETE FROM reports WHERE ts < ?`, now - KAYIT_SURE.sikayet);
    this.sql.exec(`DELETE FROM purchases WHERE ts < ?`, now - KAYIT_SURE.satin_alma);
    this.sql.exec(`DELETE FROM gifts WHERE ts < ?`, now - KAYIT_SURE.sikayet);
    this.sql.exec(`DELETE FROM kodlar WHERE bitis < ?`, now);
    this.sql.exec(`DELETE FROM kod_gonderim WHERE ts < ?`, now - 2 * 3600000);
  }

  // Web'den hesap silme: kullanıcı adı + şifre. Yanlış şifre sayacı oyundaki girişle ortak (LOGIN_MAX / 15 dk);
  // ayrıca aynı IP adresinden 15 dakikada en fazla WEB_MAX deneme. Dönen: { kod } (hesap_sil.js sayfası yazar)
  async webDelete(req) {
    let form;
    try {
      form = await req.formData();
    } catch {
      return { kod: "eksik" };
    }
    const girilen = String(form.get("kullanici") || "").trim().toLowerCase().slice(0, 120);
    const pass = String(form.get("sifre") || "").slice(0, 64);
    if (!girilen || !pass) return { kod: "eksik" };
    // kullanıcı adı ya da e-posta (yanlış sayacı hesabın kullanıcı adına işler)
    const bulunan = this.hesapBul(girilen);
    const handle = (bulunan && bulunan.handle) || girilen.replace(/^@/, "").slice(0, 32);
    if (!form.get("onay")) return { kod: "onay" };
    const now = Date.now();
    const ip = (req.headers.get("cf-connecting-ip") || req.headers.get("x-forwarded-for") || "?").split(",")[0].trim().slice(0, 64);
    let w = this.webFails.get(ip);
    if (w && now - w.ts > LOGIN_WINDOW) w = null;
    if (!w) w = { n: 0, ts: now };
    if (w.n >= WEB_MAX) return { kod: "cok_deneme" };
    w.n += 1;
    this.webFails.set(ip, w);
    if (this.webFails.size > 5000) this.webFails.clear();
    let f = this.loginFails.get(handle);
    if (f && now - f.ts > LOGIN_WINDOW) f = null;
    if (f && f.n >= LOGIN_MAX) return { kod: "cok_deneme" };
    const u = this.rows(`SELECT token, pass FROM users WHERE handle = ?`, handle)[0];
    if (!u || !u.pass || !(await this.checkPass(u.pass, pass))) {
      if (!f) f = { n: 0, ts: now };
      f.n += 1;
      this.loginFails.set(handle, f);
      if (this.loginFails.size > 5000) this.loginFails.clear();
      return { kod: "yanlis" };
    }
    this.deleteAccount(u.token);
    this.temizlik();
    return { kod: "silindi" };
  }

  // Şifreyi yeniler (sıfırlama kodu doğrulandıktan sonra): anahtar yenilenir (eski oturumlar kapanır), "degisti" e-postası gider.
  // Dönen: yeni hesap anahtarı
  async sifreYenile(u, sifre, cihaz, konum, ws) {
    const pass = await this.makePass(sifre);
    this.sql.exec(`UPDATE users SET pass = ? WHERE token = ?`, pass, u.token);
    if (u.email) this.sql.exec(`UPDATE users SET email_ok = 1 WHERE token = ?`, u.token); // kod e-postaya gitti: adres doğru
    this.loginFails.delete(u.handle);
    const yeni = this.tokenYenile(u.token);
    if (u.email) {
      this.postala("degisti", u.email, u.dil, {
        kullanici: u.handle, zaman: Accounts.zaman(u.dil), cihaz: cihaz || "—", konum: konum || "—",
        url: `mailto:${DESTEK}?subject=${encodeURIComponent("Şifre değişikliği: @" + u.handle)}`,
      }, ws);
    }
    return yeni;
  }

  // E-postadaki bağlantıdan gelen web formu: e-posta doğrulama ya da yeni şifre. Dönen: { kod } (eposta_web.js sayfası yazar)
  async webKod(req, tur) {
    let form;
    try {
      form = await req.formData();
    } catch {
      return { kod: "eksik" };
    }
    const handle = String(form.get("h") || "").trim().replace(/^@/, "").toLowerCase().slice(0, 32);
    const kod = String(form.get("k") || "").replace(/\D/g, "").slice(0, 6);
    if (!handle || kod.length !== 6) return { kod: "eksik" };
    const now = Date.now();
    const ip = (req.headers.get("cf-connecting-ip") || req.headers.get("x-forwarded-for") || "?").split(",")[0].trim().slice(0, 64);
    let w = this.webFails.get(ip);
    if (w && now - w.ts > LOGIN_WINDOW) w = null;
    if (!w) w = { n: 0, ts: now };
    if (w.n >= WEB_MAX) return { kod: "cok_deneme" };
    w.n += 1;
    this.webFails.set(ip, w);
    if (this.webFails.size > 5000) this.webFails.clear();
    const u = this.rows(`SELECT token, handle, pass, email, email_ok, dil FROM users WHERE handle = ?`, handle)[0];
    if (!u || !u.pass) return { kod: "yok" };
    if (tur === "dogrula") {
      if (!u.email) return { kod: "yok" };
      if (u.email_ok) return { kod: "zaten" };
      const r = await this.kodDene(u.token, "dogrula", kod);
      if (r !== "ok") return { kod: r };
      this.sql.exec(`UPDATE users SET email_ok = 1 WHERE token = ?`, u.token);
      for (const s of this.socketsOfToken(u.token)) this.send(s, this.me(u.token));
      return { kod: "tamam" };
    }
    const sifre = String(form.get("sifre") || "");
    if (sifre.length < 6) return { kod: "kisa" };
    if (sifre.length > 64) return { kod: "uzun" };
    if (sifre !== String(form.get("sifre2") || "")) return { kod: "ayni_degil" };
    const r = await this.kodDene(u.token, "sifirla", kod);
    if (r !== "ok") return { kod: r };
    await this.sifreYenile(u, sifre, "Web", (req.headers.get("x-konum") || "").slice(0, 60));
    return { kod: "tamam" };
  }

  // Bağlantı dizini: her bağlantının eki (attachment) bellekte tutulur, kullanıcı adı ve anahtardan bağlantıya
  // doğrudan gidilir. Eskiden her arama bütün bağlantıları tarayıp eklerini çözüyordu: biri bağlanınca arkadaşlarının
  // listesi yenilenirken iş (arkadaş² × çevrimiçi) kadar büyüyordu, kalabalıkta sunucu kilitleniyordu.
  // Nesne uykuya geçince (hibernation) bellek boşalır; ilk kullanımda getWebSockets()'tan yeniden kurulur.
  // Kaçak kalan kayıt olmasın diye 5 dakikada bir baştan kurulur.
  dizin() {
    const now = Date.now();
    if (this._dz && now - this._dz.kurulus < 5 * DAKIKA) return this._dz;
    this._dz = { kurulus: now, ek: new Map(), h: new Map(), t: new Map() };
    for (const ws of this.state.getWebSockets()) this.dizinle(ws, ws.deserializeAttachment() || {});
    return this._dz;
  }

  dizinle(ws, ek) {
    const dz = this._dz;
    const eski = dz.ek.get(ws);
    const cikar = (m, k) => {
      const s = k && m.get(k);
      if (s && s.delete(ws) && !s.size) m.delete(k);
    };
    const ekle = (m, k) => {
      if (!k) return;
      if (!m.has(k)) m.set(k, new Set());
      m.get(k).add(ws);
    };
    if (eski) (cikar(dz.h, eski.handle), cikar(dz.t, eski.token));
    dz.ek.set(ws, ek);
    ekle(dz.h, ek.handle);
    ekle(dz.t, ek.token);
  }

  dizindenCikar(ws) {
    if (!this._dz) return;
    this.dizinle(ws, {});
    this._dz.ek.delete(ws);
  }

  // Bağlantının ekinin kopyası (değiştirilirse setInfo ile yazılmalı)
  info(ws) {
    const dz = this.dizin();
    let ek = dz.ek.get(ws);
    if (!ek) this.dizinle(ws, (ek = ws.deserializeAttachment() || {}));
    return { ...ek };
  }

  setInfo(ws, ek) {
    try {
      ws.serializeAttachment(ek);
    } catch {}
    this.dizin();
    this.dizinle(ws, { ...ek });
  }

  socketsOf(handle) {
    return handle ? [...(this.dizin().h.get(handle) || [])] : [];
  }

  socketsOfToken(token) {
    return token ? [...(this.dizin().t.get(token) || [])] : [];
  }

  send(ws, obj) {
    try {
      ws.send(JSON.stringify(obj));
    } catch {}
  }

  sendTo(handle, obj) {
    for (const ws of this.socketsOf(handle)) this.send(ws, obj);
  }

  // Bir oyuncunun arkadaş listesi, gelen ve gönderilen istekler
  list(handle) {
    const presence = (h) => {
      const s = this.socketsOf(h);
      if (s.length === 0) return { online: false, room: "", oyun: false };
      // birden çok cihaz bağlıysa odada olanı göster; oyun: odadaki maç başlamış mı (MAÇTA / ODADA)
      const i = this.info(s.find((w) => this.info(w).room) || s[0]);
      return { online: true, room: i.room || "", oyun: !!(i.room && i.oyun) };
    };
    // adlar aynı sorguda gelir (eskiden her kişi için ayrı sorgu)
    const kisiler = (q) => this.rows(q, handle).map((r) => ({ handle: r.h, name: shownName(r.name, r.h) }));
    const friends = kisiler(`SELECT f.b AS h, u.name FROM friends f LEFT JOIN users u ON u.handle = f.b WHERE f.a = ? AND f.status = 'arkadas'`)
      .map((k) => ({ ...k, ...presence(k.handle) }));
    friends.sort((x, y) => Number(y.online) - Number(x.online) || x.handle.localeCompare(y.handle));
    const incoming = kisiler(`SELECT f.a AS h, u.name FROM friends f LEFT JOIN users u ON u.handle = f.a WHERE f.b = ? AND f.status = 'istek'`);
    const outgoing = kisiler(`SELECT f.b AS h, u.name FROM friends f LEFT JOIN users u ON u.handle = f.b WHERE f.a = ? AND f.status = 'istek'`);
    return { t: "liste", friends, incoming, outgoing };
  }

  // Listeyi yenile: yalnız bağlı olana, kısa aralıktaki yenilemeler birleştirilerek (biri odaya girip çıkınca
  // arkadaşlarının listesi her değişiklikte baştan hesaplanmasın). Hemen gereken yanıtlar list() ile doğrudan gider.
  refresh(handle) {
    if (!handle || !this.socketsOf(handle).length) return;
    if (!this._yenile) this._yenile = new Set();
    this._yenile.add(handle);
    if (this._yenileZaman) return;
    this._yenileZaman = setTimeout(() => {
      const liste = [...this._yenile];
      this._yenile.clear();
      this._yenileZaman = null;
      for (const h of liste) {
        const socks = this.socketsOf(h);
        if (socks.length) {
          const l = this.list(h);
          for (const ws of socks) this.send(ws, l);
        }
      }
    }, 250);
  }

  // Arkadaşlarına "çevrimiçi/çevrimdışı/odada" değişikliğini bildir
  refreshFriendsOf(handle) {
    for (const r of this.rows(`SELECT b FROM friends WHERE a = ? AND status = 'arkadas'`, handle)) this.refresh(r.b);
  }

  async fetch(req) {
    const url = new URL(req.url);
    if (url.pathname === "/telemetri" && req.method === "POST") {
      const ip = (req.headers.get("cf-connecting-ip") || "").slice(0, 64);
      if (ip) {
        if (this.telemetriIp.size > 20000) this.telemetriIp.clear();
        if (!kovaIzin(this.telemetriIp, ip, TELEMETRI_ORAN)) return new Response("cok", { status: 429 });
      }
      try {
        const body = await req.json();
        const list = Array.isArray(body.olaylar) ? body.olaylar.slice(0, 50) : [];
        const now = Date.now();
        for (const e of list) {
          const data = JSON.stringify(e.k === "hata" ? { m: String(e.m || "").slice(0, 400), tur: e.tur } : e.d || {}).slice(0, 600);
          this.sql.exec(`INSERT INTO events (ts, kind, surum, platform, data) VALUES (?, ?, ?, ?, ?)`, now, String(e.k || "").slice(0, 32), String(e.s || "").slice(0, 12), String(e.p || "").slice(0, 16), data);
        }
        if (Math.random() < 0.02) this.temizlik();
      } catch {}
      return new Response("ok");
    }
    if (url.pathname === "/hesap-sil" && req.method === "POST") {
      // web'den hesap silme (index.js yönlendirir, sayfayı hesap_sil.js yazar)
      return Response.json(await this.webDelete(req));
    }
    if ((url.pathname === "/eposta-dogrula" || url.pathname === "/sifre-sifirla") && req.method === "POST") {
      // e-postadaki bağlantının web sayfası (index.js yönlendirir, sayfayı eposta_web.js yazar)
      return Response.json(await this.webKod(req, url.pathname === "/eposta-dogrula" ? "dogrula" : "sifirla"));
    }
    // yönetim sayfası (index.js yalnızca /yonetim yollarını buraya yollar; yonetim.js)
    if (url.pathname === "/yonetim" || url.pathname.startsWith("/yonetim/")) return yonetim(this, req);
    if (url.pathname === "/mac" && req.method === "POST") {
      // sadece aynı Worker içindeki oda sunucusu çağırır (dışarıdan /hesap yolu WebSocket ister)
      try {
        const body = await req.json();
        this.matchResult(Array.isArray(body.oyuncular) ? body.oyuncular : []);
      } catch {}
      return new Response("ok");
    }
    // ---- oda sunucusunun iç istekleri (dışarıdan ulaşılamaz: index.js bu yolları yönlendirmez) ----
    if (url.pathname.startsWith("/ic/") && req.method === "POST") {
      let b = {};
      try {
        b = await req.json();
      } catch {}
      const tok = String(b.token || "");
      if (url.pathname === "/ic/oda-giris") {
        // odaya giren oyuncu: yasaklı mı, kimleri engellemiş
        // hesap: şifreli hesap mı (misafir odaya giremez), ad: oyundaki adı = kullanıcı adı (istemcinin yolladığı ada güvenilmez)
        const y = this.yasak(tok);
        const u = tok ? this.rows(`SELECT handle, pass FROM users WHERE token = ?`, tok)[0] : null;
        const hesap = !!(u && u.pass && u.handle);
        return Response.json({ yasak: y ? { bitis: y.bitis, kalici: y.kalici, ...Accounts.yasakMetni(y) } : null, engel: this.engelTokenleri(tok), hesap, ad: hesap ? u.handle : "" });
      }
      if (url.pathname === "/ic/oda-sikayet") {
        const r = this.sikayetEkle(tok, String(b.hedef || ""), b.ad, b.oda, b.neden, b.not);
        return Response.json(r.ok ? { ok: true } : { ok: false, ...tx(r.m) });
      }
      if (url.pathname === "/ic/oda-engel") {
        const ok = this.engelEkle(tok, String(b.hedef || ""), b.ad);
        return Response.json({ ok, engel: this.engelTokenleri(tok) });
      }
      if (url.pathname === "/ic/engelliler") return Response.json({ liste: this.engelIliskili(tok) });
      return new Response("?", { status: 404 });
    }
    const token = url.searchParams.get("token") || "";
    const [client, server] = Object.values(new WebSocketPair());
    this.state.acceptWebSocket(server);
    if (token.length < 16) {
      this.send(server, { t: "hata", m: "Geçersiz hesap anahtarı." });
      server.close(4000, "hata");
      return new Response(null, { status: 101, webSocket: client });
    }
    // askıya alınmış hesap (ya da misafirse cihaz anahtarı): kısa mesaj, bağlantı kapanır
    const ban = this.yasak(token);
    if (ban) {
      this.send(server, { t: "yasak", bitis: ban.kalici ? 0 : ban.bitis, kalici: ban.kalici, ...Accounts.yasakMetni(ban) });
      server.close(4003, "yasak");
      return new Response(null, { status: 101, webSocket: client });
    }
    this.sql.exec(`INSERT OR IGNORE INTO users (token) VALUES (?)`, token);
    const user = this.rows(`SELECT handle, name, uyari FROM users WHERE token = ?`, token)[0];
    if (user && user.uyari) {
      // yönetici uyarısı: bağlanınca bir kez gösterilir
      this.send(server, { t: "uyari", ...tx(UYARI_METNI) });
      this.sql.exec(`UPDATE users SET uyari = 0 WHERE token = ?`, token);
    }
    // yerel: test sunucusu (e-posta bağlaması yokken kodlar test için bu bağlantıya da gider); koken: e-posta bağlantıları için
    // ip / konum: hız sınırı ve güvenlik e-postasındaki yaklaşık konum (saklanmaz, yalnız bu bağlantının ekinde)
    const ip = (req.headers.get("cf-connecting-ip") || "").slice(0, 64);
    const konum = (req.headers.get("x-konum") || "").slice(0, 60);
    this.setInfo(server, { token, handle: (user && user.handle) || "", room: "", tries: 0, yerel: YEREL.has(url.hostname), koken: url.origin.slice(0, 80), ip, konum });
    this.send(server, this.me(token));
    this.send(server, this.economy(token));
    M.bekleyenHediyeler(this, server, token);
    if (user && user.handle) {
      this.send(server, this.list(user.handle));
      this.refreshFriendsOf(user.handle);
    }
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws, msg) {
    if (typeof msg !== "string" || msg.length > MESAJ_MAX) return;
    let kova = this.kovalar.get(ws);
    if (!kova) this.kovalar.set(ws, (kova = new Map()));
    if (this.env.SPAM_SINIRI !== "0" && !kovaIzin(kova, "m", MESAJ_ORAN)) return; // çok hızlı mesaj: atılır (SPAM_SINIRI=0 yalnız birim testte)
    let d;
    try {
      d = JSON.parse(msg);
    } catch {
      return;
    }
    if (!d || typeof d !== "object" || typeof d.t !== "string") return;
    const me = this.info(ws);
    if (!me.token) return; // kapanmakta olan / silinmiş hesabın bağlantısı
    const err = (m, ...a) => this.send(ws, { t: "hata", ...tx(m, ...a) });
    const target = String(d.handle || "").replace(/^@/, "").trim().toLowerCase();

    const eko = this.ecoMessage(ws, me, d);
    if (eko) return void (await eko); // gerçek ödeme doğrulaması Promise döner (odemeIsle)
    if (d.t === "ad_kontrol") {
      // görünen ad kaydedilmeden önce sorulur (misafir de sorabilir): {t:"ad_kontrol", ad, ok}
      const ad = cleanName(d.ad);
      this.send(ws, { t: "ad_kontrol", ad: String(d.ad || "").slice(0, 40), ok: !!ad && adUygun(ad), ...(ad && !adUygun(ad) ? { m: AD_RED } : {}) });
      return;
    }
    const dilOf = (x) => (x === "en" ? "en" : "tr");
    if (d.t === "uye_ol") {
      // Kayıt: kullanıcı adı + e-posta (zorunlu, tek hesap) + şifre. Oyundaki ad = kullanıcı adı.
      // Misafirken kayıt olunca bu cihazın anahtarı hesaba dönüşür: misafir ilerlemesi (elmas, eşya, XP) hesapta kalır.
      const pass = String(d.sifre || "");
      const row = me.handle ? this.rows(`SELECT pass FROM users WHERE token = ?`, me.token)[0] : null;
      if (row && row.pass) return err("Bu cihaz zaten @{0} hesabında. Önce çıkış yap.", me.handle);
      if (!me.handle || target !== me.handle) {
        const he = handleError(target);
        if (he) return err(he);
      }
      const email = epostaTemiz(d.eposta);
      if (!email) return err(String(d.eposta || "").trim() ? "E-posta adresi geçerli değil." : "E-posta adresini yaz.");
      if (pass.length < 6) return err("Şifre en az 6 karakter olmalı.");
      if (pass.length > 64) return err("Şifre en fazla 64 karakter olabilir.");
      if (!me.handle || target !== me.handle) {
        if (this.rows(`SELECT 1 FROM users WHERE handle = ?`, target).length) return err("@{0} alınmış, başka bir ad dene.", target);
      }
      if (this.rows(`SELECT 1 FROM users WHERE email = ? AND token != ?`, email, me.token).length)
        return err("Bu e-posta adresiyle zaten bir hesap var. Giriş yap ya da şifreni sıfırla.");
      if (!me.yerel && me.ip) {
        if (this.kayitIp.size > 20000) this.kayitIp.clear();
        if (!kovaIzin(this.kayitIp, me.ip, KAYIT_IP_ORAN)) return err("Bu bağlantıdan çok fazla hesap açıldı. Biraz sonra tekrar dene.");
      }
      const passHash = await this.makePass(pass);
      // (şifre özeti hesaplanırken başka bağlantı aynı adı / e-postayı almış olabilir: yeniden bakılır)
      if (this.rows(`SELECT 1 FROM users WHERE handle = ? AND token != ?`, target, me.token).length) return err("@{0} alınmış, başka bir ad dene.", target);
      if (this.rows(`SELECT 1 FROM users WHERE email = ? AND token != ?`, email, me.token).length)
        return err("Bu e-posta adresiyle zaten bir hesap var. Giriş yap ya da şifreni sıfırla.");
      if (me.handle && target !== me.handle) {
        // eski (şifresiz) kullanıcı adını yenisiyle değiştir (arkadaşlıklar ve engeller taşınır)
        this.sql.exec(`UPDATE friends SET a = ? WHERE a = ?`, target, me.handle);
        this.sql.exec(`UPDATE friends SET b = ? WHERE b = ?`, target, me.handle);
        this.sql.exec(`UPDATE blocks SET b = ? WHERE b = ?`, target, me.handle);
      }
      // satır silinmeden güncellenir (misafirin ekonomisi kaybolmasın)
      this.sql.exec(`UPDATE users SET handle = ?, name = ?, pass = ?, email = ?, email_ok = 0, dil = ? WHERE token = ?`,
        target, target, passHash, email, dilOf(d.dil), me.token);
      me.handle = target;
      this.setInfo(ws, me);
      this.send(ws, this.me(me.token));
      this.send(ws, this.list(me.handle));
      this.send(ws, { t: "bilgi", ...tx("Hesabın açıldı: @{0}", me.handle) });
      // e-postalar cevabı geciktirmez; gönderilemese de kayıt geçerli (posta_gonder.js hata fırlatmaz)
      this.postala("hosgeldin", email, dilOf(d.dil), { ad: target, kullanici: target, url: SITE + (dilOf(d.dil) === "en" ? "/en/" : "/") }, ws);
      this.arka(this.dogrulamaGonder(me.token, ws, true));
      return;
    }
    if (d.t === "giris") {
      me.tries = (me.tries || 0) + 1;
      this.setInfo(ws, me);
      if (me.tries > 20) return err("Çok fazla deneme. Oyunu kapatıp yeniden aç.");
      const pass = String(d.sifre || "");
      if (!target || !pass) return err("Kullanıcı adını ve şifreni yaz.");
      // kullanıcı adı ya da e-posta ile giriş (yanlış sayacı hesabın kullanıcı adına işler)
      const bulunan = this.hesapBul(String(d.handle || ""));
      const anahtar = (bulunan && bulunan.handle) || target;
      const now = Date.now();
      let f = this.loginFails.get(anahtar);
      if (f && now - f.ts > LOGIN_WINDOW) f = null;
      if (f && f.n >= LOGIN_MAX) return err("Çok fazla yanlış deneme. 15 dakika sonra tekrar dene.");
      const u = bulunan;
      if (!u || !u.pass || !(await this.checkPass(u.pass, pass))) {
        if (!f) f = { n: 0, ts: now };
        f.n += 1;
        this.loginFails.set(anahtar, f);
        if (this.loginFails.size > 5000) this.loginFails.clear();
        return err("Kullanıcı adı ya da şifre yanlış.");
      }
      this.loginFails.delete(anahtar);
      const yas = this.yasak(u.token);
      if (yas) return this.send(ws, { t: "hata", ...Accounts.yasakMetni(yas) }); // askıdaki hesaba giriş yok
      this.send(ws, { t: "giris_ok", token: u.token });
      return;
    }
    if (d.t === "sifre_unuttum") {
      // Şifremi unuttum: kullanıcı adı ya da e-posta. Kod yalnızca DOĞRULANMIŞ e-postaya gider. Cevap her durumda aynıdır
      // (kimin hesabı olduğu buradan öğrenilemesin). Hız sınırı: IP başına + hesap başına (KOD_GONDERIM.sifirla).
      if (me.ip && !me.yerel) {
        if (this.sifirlaIp.size > 20000) this.sifirlaIp.clear();
        if (!kovaIzin(this.sifirlaIp, me.ip, SIFIRLA_IP_ORAN)) return err("Çok fazla istek. Biraz sonra tekrar dene.");
      }
      me.sifirla = (me.sifirla || 0) + 1;
      this.setInfo(ws, me);
      if (me.sifirla > 10) return err("Çok fazla istek. Biraz sonra tekrar dene.");
      const kim = String(d.kim || "").trim();
      if (!kim) return err("Kullanıcı adını ya da e-postanı yaz.");
      const u = this.hesapBul(kim);
      if (u && u.pass && u.email && u.email_ok && this.kodGonderilebilir(u.token, "sifirla")) {
        const kod = await this.kodUret(u.token, "sifirla");
        this.postala("sifirla", u.email, u.dil, {
          kullanici: u.handle, kod, url: Accounts.kodBaglantisi(me.koken, "/sifre-sifirla", u.handle, kod),
          zaman: Accounts.zaman(u.dil), cihaz: String(d.cihaz || "").replace(/[\u0000-\u001f<>]/g, "").slice(0, 60) || "—", konum: me.konum || "—",
        }, ws);
      }
      this.send(ws, { t: "sifirla_gitti", ...tx("Hesap bulunduysa ve e-postası doğrulandıysa 6 haneli bir kod gönderdik. Gelen kutunu (ve spam klasörünü) kontrol et.") });
      return;
    }
    if (d.t === "sifre_sifirla") {
      // Kod + yeni şifre: doğruysa şifre değişir, anahtar yenilenir (eski oturumlar kapanır) ve bu cihaz yeni anahtarla girer
      me.tries = (me.tries || 0) + 1;
      this.setInfo(ws, me);
      if (me.tries > 20) return err("Çok fazla deneme. Oyunu kapatıp yeniden aç.");
      const sifre = String(d.sifre || "");
      if (sifre.length < 6) return err("Şifre en az 6 karakter olmalı.");
      if (sifre.length > 64) return err("Şifre en fazla 64 karakter olabilir.");
      const u = this.hesapBul(String(d.kim || ""));
      if (!u || !u.pass) return err(Accounts.kodHatasi("yanlis"));
      const r = await this.kodDene(u.token, "sifirla", d.kod);
      if (r !== "ok") return err(Accounts.kodHatasi(r));
      const yas = this.yasak(u.token);
      const yeni = await this.sifreYenile(u, sifre, String(d.cihaz || "").replace(/[\u0000-\u001f<>]/g, "").slice(0, 60), me.konum, ws);
      this.send(ws, { t: "sifre_yenilendi", ...tx("Şifren değişti. Hoş geldin, @{0}!", u.handle) });
      if (yas) return this.send(ws, { t: "hata", ...Accounts.yasakMetni(yas) });
      this.send(ws, { t: "giris_ok", token: yeni });
      return;
    }
    if (d.t === "profil_kaydet") {
      if (!me.handle) return;
      const p = JSON.stringify(d.p || {});
      if (p.length < 16000) this.sql.exec(`UPDATE users SET profil = ? WHERE token = ?`, p, me.token);
      return; // oyundaki ad kullanıcı adıdır: profildeki "ad" hesaba yazılmaz
    }
    if (d.t === "kayit") return err("Hesap açmak için e-posta ve şifre gerekli. Oyunu güncelle.");
    if (!me.handle) {
      if (d.t === "durum") return this.setRoom(ws, me, d); // misafir: sonra hesap açarsa odası bilinsin
      if (d.t === "liste") return; // misafirin arka plan mesajları sessizce geçer
      return err("Önce hesap aç ya da giriş yap.");
    }
    if (d.t === "eposta_ekle") {
      // E-postasız eski hesap e-posta ekler (ya da doğrulanmamış adresini düzeltir). Doğrulanmış adres yalnızca şifreyle değişir.
      const u = this.rows(`SELECT pass, email, email_ok FROM users WHERE token = ?`, me.token)[0];
      if (!u || !u.pass) return err("Önce hesap aç ya da giriş yap.");
      const email = epostaTemiz(d.eposta);
      if (!email) return err(String(d.eposta || "").trim() ? "E-posta adresi geçerli değil." : "E-posta adresini yaz.");
      if (u.email === email) {
        this.send(ws, { t: "eposta_tamam" });
        if (!u.email_ok) await this.dogrulamaGonder(me.token, ws);
        return;
      }
      if (u.email && u.email_ok && !(await this.checkPass(u.pass, String(d.sifre || "")))) return err("E-postanı değiştirmek için şifreni doğru yaz.");
      if (this.rows(`SELECT 1 FROM users WHERE email = ? AND token != ?`, email, me.token).length)
        return err("Bu e-posta adresiyle zaten bir hesap var.");
      this.sql.exec(`UPDATE users SET email = ?, email_ok = 0, dil = COALESCE(?, dil) WHERE token = ?`, email, d.dil ? dilOf(d.dil) : null, me.token);
      this.sql.exec(`DELETE FROM kodlar WHERE token = ? AND tur = 'dogrula'`, me.token);
      this.send(ws, this.me(me.token));
      this.send(ws, { t: "eposta_tamam" });
      this.arka(this.dogrulamaGonder(me.token, ws, true));
      return;
    }
    if (d.t === "dogrulama_tekrar") {
      const u = this.rows(`SELECT email, email_ok FROM users WHERE token = ?`, me.token)[0];
      if (!u || !u.email) return err("Önce e-posta adresini ekle.");
      if (u.email_ok) return this.send(ws, { t: "bilgi", ...tx("E-postan zaten doğrulandı.") });
      if (!(await this.dogrulamaGonder(me.token, ws))) return err("Biraz bekle, sonra yeni kod iste.");
      return this.send(ws, { t: "bilgi", ...tx("Yeni kod gönderildi.") });
    }
    if (d.t === "eposta_dogrula") {
      const u = this.rows(`SELECT email, email_ok FROM users WHERE token = ?`, me.token)[0];
      if (!u || !u.email) return err("Önce e-posta adresini ekle.");
      if (u.email_ok) {
        this.send(ws, this.me(me.token));
        return this.send(ws, { t: "dogrulandi" });
      }
      const r = await this.kodDene(me.token, "dogrula", d.kod);
      if (r !== "ok") return err(Accounts.kodHatasi(r));
      this.sql.exec(`UPDATE users SET email_ok = 1 WHERE token = ?`, me.token);
      for (const s of this.socketsOfToken(me.token)) this.send(s, this.me(me.token));
      this.send(ws, { t: "dogrulandi", ...tx("E-postan doğrulandı.") });
      return;
    }

    switch (d.t) {
      case "ad": {
        // oyundaki ad kullanıcı adıdır; ayrı görünen ad yok (eski sürümler için sessizce yok sayılır)
        this.send(ws, this.me(me.token));
        break;
      }
      case "durum": {
        this.setRoom(ws, me, d);
        this.refreshFriendsOf(me.handle);
        break;
      }
      case "liste":
        this.send(ws, this.list(me.handle));
        break;
      case "istek": {
        if (!target) return err("Arkadaşının kullanıcı adını yaz.");
        if (target === me.handle) return err("Kendine istek gönderemezsin.");
        const ttok = this.tokenOf(target);
        if (!ttok) return err("@{0} diye biri yok.", target);
        if (this.blocked(me.token, target)) return err("@{0} kişisini engelledin. Önce engeli kaldır.", target);
        if (this.blocked(ttok, me.handle)) return err("@{0} kişisine istek gönderilemiyor.", target);
        if (this.rows(`SELECT 1 FROM friends WHERE a = ? AND b = ? AND status = 'arkadas'`, me.handle, target).length) return err("@{0} zaten arkadaşın.", target);
        if (this.rows(`SELECT 1 FROM friends WHERE a = ? AND b = ? AND status = 'istek'`, me.handle, target).length)
          return err("@{0} kişisine zaten istek gönderdin. Cevap bekleniyor.", target);
        if (this.rows(`SELECT 1 FROM friends WHERE a = ? AND b = ? AND status = 'istek'`, target, me.handle).length) {
          // karşı taraf da istek göndermişse doğrudan arkadaş olun
          this.makeFriends(me.handle, target);
          this.send(ws, { t: "bilgi", ...tx("@{0} ile artık arkadaşsınız.", target) });
          this.sendTo(target, { t: "bilgi", ...tx("@{0} ile artık arkadaşsınız.", me.handle) });
        } else {
          if (this.rows(`SELECT COUNT(*) AS n FROM friends WHERE a = ? AND status = 'istek'`, me.handle)[0].n >= MAX_PENDING)
            return err("Çok fazla bekleyen isteğin var. Önce birkaçını iptal et.");
          this.sql.exec(`INSERT OR REPLACE INTO friends (a, b, status) VALUES (?, ?, 'istek')`, me.handle, target);
          this.sendTo(target, { t: "istek_geldi", handle: me.handle });
          this.send(ws, { t: "bilgi", ...tx("@{0} kişisine istek gönderildi.", target) });
        }
        this.refresh(me.handle);
        this.refresh(target);
        break;
      }
      case "kabul":
        if (this.rows(`SELECT 1 FROM friends WHERE a = ? AND b = ? AND status = 'istek'`, target, me.handle).length) {
          this.makeFriends(me.handle, target);
          this.send(ws, { t: "bilgi", ...tx("@{0} ile artık arkadaşsınız.", target) });
          this.sendTo(target, { t: "bilgi", ...tx("@{0} isteğini kabul etti.", me.handle) });
          this.refresh(target);
        } else this.send(ws, { t: "hata", m: "Bu istek artık geçerli değil." });
        this.refresh(me.handle);
        break;
      case "reddet":
        // gelen isteği reddet ya da gönderdiğin isteği iptal et
        this.sql.exec(`DELETE FROM friends WHERE a = ? AND b = ? AND status = 'istek'`, target, me.handle);
        this.sql.exec(`DELETE FROM friends WHERE a = ? AND b = ? AND status = 'istek'`, me.handle, target);
        this.refresh(me.handle);
        this.refresh(target);
        break;
      case "sil":
        this.unlink(me.handle, target);
        break;
      case "davet": {
        if (!this.rows(`SELECT 1 FROM friends WHERE a = ? AND b = ? AND status = 'arkadas'`, me.handle, target).length) return err("Sadece arkadaşlarını davet edebilirsin.");
        const code = String(d.oda || "").toUpperCase();
        if (!ODA_RE.test(code)) return err("Davet için önce bir odaya gir.");
        const socks = this.socketsOf(target);
        if (!socks.length) return err("@{0} şu an çevrimdışı.", target);
        if (socks.some((s) => this.info(s).room === code)) return err("@{0} zaten bu odada.", target);
        if (socks.every((s) => this.info(s).oyun)) return err("@{0} şu an maçta. Maç bitince davet et.", target);
        if (this.blocked(this.tokenOf(target), me.handle)) return err("@{0} şu an davet alamıyor.", target);
        const key = me.handle + ">" + target;
        const now = Date.now();
        if (now - (this.lastInvite.get(key) || 0) < 5000) return err("Az önce davet ettin, biraz bekle.");
        this.lastInvite.set(key, now);
        if (this.lastInvite.size > 5000) this.lastInvite.clear();
        const name = shownName((this.rows(`SELECT name FROM users WHERE handle = ?`, me.handle)[0] || {}).name, me.handle);
        this.sendTo(target, { t: "davet_geldi", handle: me.handle, name, oda: code });
        this.send(ws, { t: "bilgi", ...tx("@{0} davet edildi.", target) });
        break;
      }
    }
  }

  // Oyuncunun bulunduğu oda (4 harf ya da "") ve o odada maçın başlayıp başlamadığı
  setRoom(ws, me, d) {
    const code = String(d.oda || "").toUpperCase();
    me.room = ODA_RE.test(code) ? code : "";
    me.oyun = !!(me.room && d.oyun);
    this.setInfo(ws, me);
  }

  makeFriends(x, y) {
    this.sql.exec(`DELETE FROM friends WHERE (a = ? AND b = ?) OR (a = ? AND b = ?)`, x, y, y, x);
    this.sql.exec(`INSERT INTO friends (a, b, status) VALUES (?, ?, 'arkadas'), (?, ?, 'arkadas')`, x, y, y, x);
  }

  async webSocketClose(ws) {
    const me = this.info(ws);
    try {
      ws.serializeAttachment({});
    } catch {}
    this.dizindenCikar(ws);
    if (me.handle) this.refreshFriendsOf(me.handle);
  }

  async webSocketError(ws) {
    await this.webSocketClose(ws);
  }
}
