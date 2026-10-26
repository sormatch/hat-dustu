// Hesaplar ve arkadaşlık: tek bir "Accounts" nesnesi (SQLite).
// Oyun açılınca  wss://<sunucu>/hesap?token=...  ile bağlanır; token cihazda üretilen gizli anahtardır.
// Kullanıcı adı (@ad) bir kez seçilir. Şifre konursa hesap başka cihazdan "giriş" ile açılır (sunucu o hesabın anahtarını verir).
// Şifreler PBKDF2-SHA256 ile tuzlanıp saklanır; profil (görünüş, elmas, eşyalar) JSON olarak hesapta durur. İstek → kabul → arkadaş; arkadaşlar birbirini lobiye davet edebilir.

import * as E from "./ekonomi.js";

const HANDLE_RE = /^[a-z0-9_.]{3,16}$/;
const ODA_RE = /^[A-Z0-9]{4}$/;
const LOGIN_MAX = 8; // bir kullanıcı adına bu kadar yanlış şifreden sonra...
const LOGIN_WINDOW = 15 * 60000; // ...15 dakika giriş kapalı (bağlantı yenilense de)
const MAX_PENDING = 50; // bekleyen giden istek sınırı

// Kullanıcı adı kuralı: kısa ve anlaşılır Türkçe hata ("" = uygun)
function handleError(h) {
  if (!h) return "Kullanıcı adını yaz.";
  if (/[çğıöşüâîû̇]/.test(h)) return "Kullanıcı adında Türkçe harf olamaz (ç, ğ, ı, ö, ş, ü).";
  if (/\s/.test(h)) return "Kullanıcı adında boşluk olamaz.";
  if (h.length < 3) return "Kullanıcı adı en az 3 karakter olmalı.";
  if (h.length > 16) return "Kullanıcı adı en fazla 16 karakter olabilir.";
  if (!HANDLE_RE.test(h)) return "Kullanıcı adında sadece harf, rakam, _ ve . olabilir.";
  if (!/[a-z0-9]/.test(h)) return "Kullanıcı adında en az bir harf ya da rakam olmalı.";
  return "";
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
    // çökme raporları ve analitik olaylar (30 gün saklanır)
    this.sql.exec(`CREATE TABLE IF NOT EXISTS events (ts INTEGER, kind TEXT, surum TEXT, platform TEXT, data TEXT)`);
    // ekonomi ve ilerleme sunucuda: elmas, eşyalar, XP, istatistik, günlük görev, başarım, haftalık puan
    for (const col of ["pass TEXT", "profil TEXT", "gems INTEGER", "items TEXT", "xp INTEGER DEFAULT 0", "stats TEXT", "gorev TEXT", "basarim TEXT", "hafta TEXT", "hafta_xp INTEGER DEFAULT 0"]) {
      try {
        this.sql.exec(`ALTER TABLE users ADD COLUMN ${col}`);
      } catch {}
    }
    this.state.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
    this.loginFails = new Map(); // kullanıcı adı -> {n, ts}: yanlış şifre sayacı
    this.lastInvite = new Map(); // "a>b" -> zaman: davet yağmuruna karşı
  }

  // a anahtarlı oyuncu b kullanıcı adını engellemiş mi
  blocked(aToken, bHandle) {
    return !!aToken && !!bHandle && this.rows(`SELECT 1 FROM blocks WHERE a = ? AND b = ?`, aToken, bHandle).length > 0;
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

  me(token) {
    const u = this.rows(`SELECT handle, name, pass, profil FROM users WHERE token = ?`, token)[0];
    let profil = null;
    try {
      profil = u && u.profil ? JSON.parse(u.profil) : null;
    } catch {}
    return { t: "ben", handle: (u && u.handle) || "", name: (u && u.name) || "", hesap: !!(u && u.pass), profil };
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
      hediye_kasa: e.stats.hediye_kasa || 0, // Başlangıç Paketi'nden gelen, açılmamış ücretsiz nadir kasa
      kasalar: Object.fromEntries(Object.entries(E.CHESTS).map(([k, c]) => [k, c.price])),
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
      for (const ws of this.state.getWebSockets()) {
        if (this.info(ws).token === r.token) {
          this.send(ws, { t: "mac_odul", xp: rw.xp, elmas: rw.gems, seviye_atladi: after > before ? after : 0 });
          this.send(ws, this.economy(r.token));
        }
      }
    }
  }

  // Ekonomi mesajları (misafir de kullanabilir). Dönen: true ise mesaj işlendi.
  ecoMessage(ws, me, d) {
    const err = (m) => this.send(ws, { t: "hata", m });
    switch (d.t) {
      case "ekonomi":
        this.send(ws, this.economy(me.token));
        return true;
      case "satin_al": {
        const cat = String(d.kat || "");
        const id = String(d.id || "");
        let cost = E.price(cat, id);
        if (cost <= 0) return err("Bu eşya satılmıyor."), true;
        const deal = E.dailyDeals().find((x) => x[0] === cat && x[1] === id);
        if (d.firsat && deal) cost = deal[4];
        const e = this.eco(me.token);
        if (e.items.includes(cat + ":" + id)) return err("Bu eşya zaten sende."), true;
        if (e.gems < cost) return err("Elmas yetmiyor."), true;
        e.gems -= cost;
        e.items.push(cat + ":" + id);
        this.saveEco(me.token, e);
        this.send(ws, { t: "satin_alindi", kat: cat, id, elmas: e.gems });
        this.send(ws, this.economy(me.token));
        return true;
      }
      case "kasa_ac": {
        const kind = String(d.kasa || "");
        const ch = E.CHESTS[kind];
        if (!ch) return err("Böyle bir kasa yok."), true;
        const e = this.eco(me.token);
        // hediye kasa (Başlangıç Paketi): elmasla alınmaz, hediye hakkı düşer
        if (ch.gift) {
          if ((e.stats.hediye_kasa || 0) <= 0) return err("Hediye kasan yok."), true;
          e.stats.hediye_kasa -= 1;
        } else if (e.gems < ch.price) return err("Elmas yetmiyor."), true;
        const r = E.rollChest(kind, e.items);
        e.gems -= ch.price;
        if (r.dup) e.gems += r.refund;
        else e.items.push(r.cat + ":" + r.id);
        e.stats.kasa = (e.stats.kasa || 0) + 1;
        this.saveEco(me.token, e);
        this.send(ws, { t: "kasa_sonuc", kasa: kind, kat: r.cat, id: r.id, nadirlik: r.rarity, kopya: r.dup, iade: r.refund, elmas: e.gems });
        this.send(ws, this.economy(me.token));
        return true;
      }
      case "elmas_paketi":
      case "elmas_al": {
        // ELMAS PAKETİ. !!! TEST MODU (E.TEST_ODEME = true) !!!: ödeme alınmaz, makbuz aranmaz, elmas doğrudan hesaba geçer.
        // Gerçek ödeme bağlanınca: telefon App Store / Google Play'den makbuz alır, sunucu makbuzu doğrular
        // (TODO), E.TEST_ODEME = false yapılır ve bu doğrudan ekleme kapanır.
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
        this.send(ws, { t: "odul", elmas: odul, neden: "Günlük ödül (" + e.stats.seri + ". gün)" });
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
        const reasons = ["kufur", "taciz", "hile", "uygunsuz_ad", "diger"];
        const reason = reasons.includes(String(d.neden)) ? String(d.neden) : "diger";
        const recent = this.rows(`SELECT COUNT(*) AS n FROM reports WHERE from_token = ? AND ts > ?`, me.token, Date.now() - 3600 * 1000)[0].n;
        if (recent >= 20) return err("Çok fazla şikayet gönderdin, biraz sonra tekrar dene."), true;
        this.sql.exec(`INSERT INTO reports (from_token, target, room, reason, note, ts) VALUES (?, ?, ?, ?, ?, ?)`,
          me.token, String(d.hedef || "").slice(0, 40), String(d.oda || "").slice(0, 8), reason, String(d.not || "").slice(0, 300), Date.now());
        this.send(ws, { t: "bilgi", m: "Şikayetin alındı. Teşekkürler." });
        return true;
      }
      case "engelle":
      case "engel_kaldir": {
        const h = String(d.handle || "").trim().replace(/^@/, "").toLowerCase().slice(0, 16);
        if (!h || h === me.handle) return true;
        if (d.t === "engelle") {
          this.sql.exec(`INSERT OR IGNORE INTO blocks (a, b) VALUES (?, ?)`, me.token, h);
          // engellenenle arkadaşlık ve bekleyen istekler (iki yönde) kalkar
          if (me.handle) this.unlink(me.handle, h);
        } else this.sql.exec(`DELETE FROM blocks WHERE a = ? AND b = ?`, me.token, h);
        this.send(ws, { t: "engeller", liste: this.rows(`SELECT b FROM blocks WHERE a = ?`, me.token).map((r) => r.b) });
        return true;
      }
      case "engeller":
        this.send(ws, { t: "engeller", liste: this.rows(`SELECT b FROM blocks WHERE a = ?`, me.token).map((r) => r.b) });
        return true;
      case "hesap_sil": {
        // Mağaza kuralı: hesap uygulamanın içinden silinebilmeli. Kullanıcı adı, şifre, profil, arkadaşlıklar, ilerleme silinir.
        const u = this.rows(`SELECT handle FROM users WHERE token = ?`, me.token)[0];
        if (u && u.handle) {
          // önce ilgili herkesi (arkadaşlar + istek gönderilen/gelen) bul, sonra sil, sonra listelerini tazele
          const others = this.rows(`SELECT b AS h FROM friends WHERE a = ? UNION SELECT a AS h FROM friends WHERE b = ?`, u.handle, u.handle).map((r) => r.h);
          this.sql.exec(`DELETE FROM friends WHERE a = ? OR b = ?`, u.handle, u.handle);
          this.loginFails.delete(u.handle);
          for (const h of others) this.refresh(h);
        }
        this.sql.exec(`DELETE FROM blocks WHERE a = ?`, me.token);
        this.sql.exec(`DELETE FROM users WHERE token = ?`, me.token);
        this.send(ws, { t: "hesap_silindi" });
        try {
          ws.close(1000, "silindi");
        } catch {}
        return true;
      }
      case "liderlik": {
        const wk = E.weekId();
        const top = this.rows(`SELECT handle, name, hafta_xp, xp FROM users WHERE hafta = ? AND hafta_xp > 0 ORDER BY hafta_xp DESC LIMIT 50`, wk)
          .map((r, i) => ({ sira: i + 1, ad: r.name || r.handle || "Mahkum", handle: r.handle || "", puan: r.hafta_xp, seviye: E.levelOf(r.xp || 0).seviye }));
        const mine = this.eco(me.token);
        const rank = mine && mine.hafta_xp > 0 ? this.rows(`SELECT COUNT(*) AS n FROM users WHERE hafta = ? AND hafta_xp > ?`, wk, mine.hafta_xp)[0].n + 1 : 0;
        this.send(ws, { t: "liderlik", hafta: wk, liste: top, benim_sira: rank, benim_puan: mine ? mine.hafta_xp : 0 });
        return true;
      }
    }
    return false;
  }

  info(ws) {
    return ws.deserializeAttachment() || {};
  }

  socketsOf(handle) {
    return this.state.getWebSockets().filter((ws) => this.info(ws).handle === handle);
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
    const name = (h) => (this.rows(`SELECT name FROM users WHERE handle = ?`, h)[0] || {}).name || h;
    const friends = this.rows(`SELECT b FROM friends WHERE a = ? AND status = 'arkadas'`, handle).map((r) => ({
      handle: r.b,
      name: name(r.b),
      ...presence(r.b),
    }));
    friends.sort((x, y) => Number(y.online) - Number(x.online) || x.handle.localeCompare(y.handle));
    const incoming = this.rows(`SELECT a FROM friends WHERE b = ? AND status = 'istek'`, handle).map((r) => ({ handle: r.a, name: name(r.a) }));
    const outgoing = this.rows(`SELECT b FROM friends WHERE a = ? AND status = 'istek'`, handle).map((r) => ({ handle: r.b, name: name(r.b) }));
    return { t: "liste", friends, incoming, outgoing };
  }

  refresh(handle) {
    if (handle) this.sendTo(handle, this.list(handle));
  }

  // Arkadaşlarına "çevrimiçi/çevrimdışı/odada" değişikliğini bildir
  refreshFriendsOf(handle) {
    for (const r of this.rows(`SELECT b FROM friends WHERE a = ? AND status = 'arkadas'`, handle)) this.refresh(r.b);
  }

  async fetch(req) {
    const url = new URL(req.url);
    if (url.pathname === "/telemetri" && req.method === "POST") {
      try {
        const body = await req.json();
        const list = Array.isArray(body.olaylar) ? body.olaylar.slice(0, 50) : [];
        const now = Date.now();
        for (const e of list) {
          const data = JSON.stringify(e.k === "hata" ? { m: String(e.m || "").slice(0, 400), tur: e.tur } : e.d || {}).slice(0, 600);
          this.sql.exec(`INSERT INTO events (ts, kind, surum, platform, data) VALUES (?, ?, ?, ?, ?)`, now, String(e.k || "").slice(0, 32), String(e.s || "").slice(0, 12), String(e.p || "").slice(0, 16), data);
        }
        if (Math.random() < 0.02) this.sql.exec(`DELETE FROM events WHERE ts < ?`, now - 30 * 86400000);
      } catch {}
      return new Response("ok");
    }
    if (url.pathname === "/mac" && req.method === "POST") {
      // sadece aynı Worker içindeki oda sunucusu çağırır (dışarıdan /hesap yolu WebSocket ister)
      try {
        const body = await req.json();
        this.matchResult(Array.isArray(body.oyuncular) ? body.oyuncular : []);
      } catch {}
      return new Response("ok");
    }
    const token = url.searchParams.get("token") || "";
    const [client, server] = Object.values(new WebSocketPair());
    this.state.acceptWebSocket(server);
    if (token.length < 16) {
      this.send(server, { t: "hata", m: "Geçersiz hesap anahtarı." });
      server.close(4000, "hata");
      return new Response(null, { status: 101, webSocket: client });
    }
    this.sql.exec(`INSERT OR IGNORE INTO users (token) VALUES (?)`, token);
    const user = this.rows(`SELECT handle, name FROM users WHERE token = ?`, token)[0];
    server.serializeAttachment({ token, handle: (user && user.handle) || "", room: "", tries: 0 });
    this.send(server, this.me(token));
    this.send(server, this.economy(token));
    if (user && user.handle) {
      this.send(server, this.list(user.handle));
      this.refreshFriendsOf(user.handle);
    }
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws, msg) {
    if (typeof msg !== "string") return;
    let d;
    try {
      d = JSON.parse(msg);
    } catch {
      return;
    }
    const me = this.info(ws);
    const err = (m) => this.send(ws, { t: "hata", m });
    const target = String(d.handle || "").replace(/^@/, "").trim().toLowerCase();

    if (this.ecoMessage(ws, me, d)) return;
    if (d.t === "uye_ol") {
      const pass = String(d.sifre || "");
      const name = cleanName(d.ad);
      const row = me.handle ? this.rows(`SELECT pass FROM users WHERE token = ?`, me.token)[0] : null;
      if (row && row.pass) return err("Bu cihaz zaten @" + me.handle + " hesabında. Önce çıkış yap.");
      if (!me.handle || target !== me.handle) {
        const he = handleError(target);
        if (he) return err(he);
      }
      if (pass.length < 6) return err("Şifre en az 6 karakter olmalı.");
      if (pass.length > 64) return err("Şifre en fazla 64 karakter olabilir.");
      if (!me.handle || target !== me.handle) {
        if (this.rows(`SELECT 1 FROM users WHERE handle = ?`, target).length) return err("@" + target + " alınmış, başka bir ad dene.");
        if (me.handle) {
          // eski kullanıcı adını yenisiyle değiştir (arkadaşlıklar ve engeller taşınır)
          this.sql.exec(`UPDATE friends SET a = ? WHERE a = ?`, target, me.handle);
          this.sql.exec(`UPDATE friends SET b = ? WHERE b = ?`, target, me.handle);
          this.sql.exec(`UPDATE blocks SET b = ? WHERE b = ?`, target, me.handle);
          this.sql.exec(`UPDATE users SET handle = ? WHERE token = ?`, target, me.token);
        } else {
          this.sql.exec(`UPDATE users SET handle = ?, name = ? WHERE token = ?`, target, name || target, me.token); // satırı silmeden (ekonomi kaybolmasın)
        }
        me.handle = target;
        ws.serializeAttachment(me);
      }
      this.sql.exec(`UPDATE users SET pass = ?, name = COALESCE(NULLIF(?, ''), name) WHERE token = ?`, await this.makePass(pass), name, me.token);
      this.send(ws, this.me(me.token));
      this.send(ws, this.list(me.handle));
      this.send(ws, { t: "bilgi", m: "Hesabın açıldı: @" + me.handle });
      return;
    }
    if (d.t === "giris") {
      me.tries = (me.tries || 0) + 1;
      ws.serializeAttachment(me);
      if (me.tries > 20) return err("Çok fazla deneme. Oyunu kapatıp yeniden aç.");
      const pass = String(d.sifre || "");
      if (!target || !pass) return err("Kullanıcı adını ve şifreni yaz.");
      const now = Date.now();
      let f = this.loginFails.get(target);
      if (f && now - f.ts > LOGIN_WINDOW) f = null;
      if (f && f.n >= LOGIN_MAX) return err("Çok fazla yanlış deneme. 15 dakika sonra tekrar dene.");
      const u = this.rows(`SELECT token, pass FROM users WHERE handle = ?`, target)[0];
      if (!u || !u.pass || !(await this.checkPass(u.pass, pass))) {
        if (!f) f = { n: 0, ts: now };
        f.n += 1;
        this.loginFails.set(target, f);
        if (this.loginFails.size > 5000) this.loginFails.clear();
        return err("Kullanıcı adı ya da şifre yanlış.");
      }
      this.loginFails.delete(target);
      this.send(ws, { t: "giris_ok", token: u.token });
      return;
    }
    if (d.t === "profil_kaydet") {
      if (!me.handle) return;
      const p = JSON.stringify(d.p || {});
      if (p.length < 16000) this.sql.exec(`UPDATE users SET profil = ? WHERE token = ?`, p, me.token);
      // profildeki görünen ad değiştiyse arkadaşlar da yeni adı görsün
      const name = cleanName(d.p && d.p.ad);
      const old = (this.rows(`SELECT name FROM users WHERE token = ?`, me.token)[0] || {}).name;
      if (name && name !== old) {
        this.sql.exec(`UPDATE users SET name = ? WHERE token = ?`, name, me.token);
        this.refreshFriendsOf(me.handle);
      }
      return;
    }
    if (d.t === "kayit") {
      const name = cleanName(d.ad);
      if (me.handle) return err("Kullanıcı adın zaten @" + me.handle);
      const he = handleError(target);
      if (he) return err(he);
      if (this.rows(`SELECT 1 FROM users WHERE handle = ?`, target).length) return err("@" + target + " alınmış, başka bir ad dene.");
      this.sql.exec(`UPDATE users SET handle = ?, name = ? WHERE token = ?`, target, name || target, me.token); // satırı silmeden (ekonomi kaybolmasın)
      me.handle = target;
      ws.serializeAttachment(me);
      this.send(ws, this.me(me.token));
      this.send(ws, this.list(target));
      return;
    }
    if (!me.handle) {
      if (d.t === "durum") return this.setRoom(ws, me, d); // misafir: sonra hesap açarsa odası bilinsin
      if (d.t === "liste") return; // misafirin arka plan mesajları sessizce geçer
      return err("Önce hesap aç ya da giriş yap.");
    }

    switch (d.t) {
      case "ad": {
        const name = cleanName(d.ad);
        if (!name) return err("Ad boş olamaz.");
        this.sql.exec(`UPDATE users SET name = ? WHERE token = ?`, name, me.token);
        this.send(ws, this.me(me.token));
        this.refreshFriendsOf(me.handle);
        break;
      }
      case "durum": {
        this.setRoom(ws, me, d);
        this.refreshFriendsOf(me.handle);
        break;
      }
      case "liste":
        this.refresh(me.handle);
        break;
      case "istek": {
        if (!target) return err("Arkadaşının kullanıcı adını yaz.");
        if (target === me.handle) return err("Kendine istek gönderemezsin.");
        const ttok = this.tokenOf(target);
        if (!ttok) return err("@" + target + " diye biri yok.");
        if (this.blocked(me.token, target)) return err("@" + target + " kişisini engelledin. Önce engeli kaldır.");
        if (this.blocked(ttok, me.handle)) return err("@" + target + " kişisine istek gönderilemiyor.");
        if (this.rows(`SELECT 1 FROM friends WHERE a = ? AND b = ? AND status = 'arkadas'`, me.handle, target).length) return err("@" + target + " zaten arkadaşın.");
        if (this.rows(`SELECT 1 FROM friends WHERE a = ? AND b = ? AND status = 'istek'`, me.handle, target).length)
          return err("@" + target + " kişisine zaten istek gönderdin. Cevap bekleniyor.");
        if (this.rows(`SELECT 1 FROM friends WHERE a = ? AND b = ? AND status = 'istek'`, target, me.handle).length) {
          // karşı taraf da istek göndermişse doğrudan arkadaş olun
          this.makeFriends(me.handle, target);
          this.send(ws, { t: "bilgi", m: "@" + target + " ile artık arkadaşsınız." });
          this.sendTo(target, { t: "bilgi", m: "@" + me.handle + " ile artık arkadaşsınız." });
        } else {
          if (this.rows(`SELECT COUNT(*) AS n FROM friends WHERE a = ? AND status = 'istek'`, me.handle)[0].n >= MAX_PENDING)
            return err("Çok fazla bekleyen isteğin var. Önce birkaçını iptal et.");
          this.sql.exec(`INSERT OR REPLACE INTO friends (a, b, status) VALUES (?, ?, 'istek')`, me.handle, target);
          this.sendTo(target, { t: "istek_geldi", handle: me.handle });
          this.send(ws, { t: "bilgi", m: "@" + target + " kişisine istek gönderildi." });
        }
        this.refresh(me.handle);
        this.refresh(target);
        break;
      }
      case "kabul":
        if (this.rows(`SELECT 1 FROM friends WHERE a = ? AND b = ? AND status = 'istek'`, target, me.handle).length) {
          this.makeFriends(me.handle, target);
          this.send(ws, { t: "bilgi", m: "@" + target + " ile artık arkadaşsınız." });
          this.sendTo(target, { t: "bilgi", m: "@" + me.handle + " isteğini kabul etti." });
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
        if (!socks.length) return err("@" + target + " şu an çevrimdışı.");
        if (socks.some((s) => this.info(s).room === code)) return err("@" + target + " zaten bu odada.");
        if (socks.every((s) => this.info(s).oyun)) return err("@" + target + " şu an maçta. Maç bitince davet et.");
        if (this.blocked(this.tokenOf(target), me.handle)) return err("@" + target + " şu an davet alamıyor.");
        const key = me.handle + ">" + target;
        const now = Date.now();
        if (now - (this.lastInvite.get(key) || 0) < 5000) return err("Az önce davet ettin, biraz bekle.");
        this.lastInvite.set(key, now);
        if (this.lastInvite.size > 5000) this.lastInvite.clear();
        const name = (this.rows(`SELECT name FROM users WHERE handle = ?`, me.handle)[0] || {}).name || me.handle;
        this.sendTo(target, { t: "davet_geldi", handle: me.handle, name, oda: code });
        this.send(ws, { t: "bilgi", m: "@" + target + " davet edildi." });
        break;
      }
    }
  }

  // Oyuncunun bulunduğu oda (4 harf ya da "") ve o odada maçın başlayıp başlamadığı
  setRoom(ws, me, d) {
    const code = String(d.oda || "").toUpperCase();
    me.room = ODA_RE.test(code) ? code : "";
    me.oyun = !!(me.room && d.oyun);
    ws.serializeAttachment(me);
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
    if (me.handle) this.refreshFriendsOf(me.handle);
  }

  async webSocketError(ws) {
    await this.webSocketClose(ws);
  }
}
