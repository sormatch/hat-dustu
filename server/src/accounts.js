// Hesaplar ve arkadaşlık: tek bir "Accounts" nesnesi (SQLite).
// Oyun açılınca  wss://<sunucu>/hesap?token=...  ile bağlanır; token cihazda üretilen gizli anahtardır.
// Kullanıcı adı (@ad) bir kez seçilir. Şifre konursa hesap başka cihazdan "giriş" ile açılır (sunucu o hesabın anahtarını verir).
// Şifreler PBKDF2-SHA256 ile tuzlanıp saklanır; profil (görünüş, elmas, eşyalar) JSON olarak hesapta durur. İstek → kabul → arkadaş; arkadaşlar birbirini lobiye davet edebilir.

const HANDLE_RE = /^[a-z0-9_.]{3,16}$/;

export class Accounts {
  constructor(state) {
    this.state = state;
    this.sql = state.storage.sql;
    this.sql.exec(`CREATE TABLE IF NOT EXISTS users (token TEXT PRIMARY KEY, handle TEXT UNIQUE, name TEXT)`);
    this.sql.exec(`CREATE TABLE IF NOT EXISTS friends (a TEXT, b TEXT, status TEXT, PRIMARY KEY (a, b))`);
    for (const col of ["pass TEXT", "profil TEXT"]) {
      try {
        this.sql.exec(`ALTER TABLE users ADD COLUMN ${col}`);
      } catch {}
    }
    this.state.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
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
    return { t: "ben", handle: u ? u.handle : "", name: u ? u.name : "", hesap: !!(u && u.pass), profil };
  }

  rows(q, ...args) {
    return this.sql.exec(q, ...args).toArray();
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
      if (s.length === 0) return { online: false, room: "" };
      return { online: true, room: this.info(s[0]).room || "" };
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
    const token = url.searchParams.get("token") || "";
    const [client, server] = Object.values(new WebSocketPair());
    this.state.acceptWebSocket(server);
    if (token.length < 16) {
      this.send(server, { t: "hata", m: "Geçersiz hesap anahtarı." });
      server.close(4000, "hata");
      return new Response(null, { status: 101, webSocket: client });
    }
    const user = this.rows(`SELECT handle, name FROM users WHERE token = ?`, token)[0];
    server.serializeAttachment({ token, handle: user ? user.handle : "", room: "", tries: 0 });
    this.send(server, this.me(token));
    if (user) {
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

    if (d.t === "uye_ol") {
      const pass = String(d.sifre || "");
      const name = String(d.ad || "").trim().slice(0, 16);
      if (pass.length < 6 || pass.length > 64) return err("Şifre en az 6 karakter olmalı.");
      const row = me.handle ? this.rows(`SELECT pass FROM users WHERE token = ?`, me.token)[0] : null;
      if (row && row.pass) return err("Bu cihaz zaten @" + me.handle + " hesabında. Önce çıkış yap.");
      if (!me.handle || target !== me.handle) {
        if (!HANDLE_RE.test(target)) return err("Kullanıcı adı 3-16 karakter olmalı: küçük harf, rakam, _ ve . kullanılabilir.");
        if (this.rows(`SELECT 1 FROM users WHERE handle = ?`, target).length) return err("@" + target + " alınmış, başka bir ad dene.");
        if (me.handle) {
          // eski kullanıcı adını yenisiyle değiştir (arkadaşlıklar taşınır)
          this.sql.exec(`UPDATE friends SET a = ? WHERE a = ?`, target, me.handle);
          this.sql.exec(`UPDATE friends SET b = ? WHERE b = ?`, target, me.handle);
          this.sql.exec(`UPDATE users SET handle = ? WHERE token = ?`, target, me.token);
        } else {
          this.sql.exec(`INSERT OR REPLACE INTO users (token, handle, name) VALUES (?, ?, ?)`, me.token, target, name || target);
        }
        me.handle = target;
        ws.serializeAttachment(me);
      }
      this.sql.exec(`UPDATE users SET pass = ?, name = COALESCE(NULLIF(?, ''), name) WHERE token = ?`, await this.makePass(pass), name, me.token);
      this.send(ws, this.me(me.token));
      this.send(ws, this.list(me.handle));
      this.send(ws, { t: "bilgi", m: "Hesabın oluşturuldu: @" + me.handle });
      return;
    }
    if (d.t === "giris") {
      me.tries = (me.tries || 0) + 1;
      ws.serializeAttachment(me);
      if (me.tries > 8) return err("Çok fazla deneme. Oyunu yeniden açıp tekrar dene.");
      const u = this.rows(`SELECT token, pass FROM users WHERE handle = ?`, target)[0];
      if (!u || !u.pass || !(await this.checkPass(u.pass, String(d.sifre || "")))) return err("Kullanıcı adı ya da şifre yanlış.");
      this.send(ws, { t: "giris_ok", token: u.token });
      return;
    }
    if (d.t === "profil_kaydet") {
      if (!me.handle) return;
      const p = JSON.stringify(d.p || {});
      if (p.length < 16000) this.sql.exec(`UPDATE users SET profil = ? WHERE token = ?`, p, me.token);
      return;
    }
    if (d.t === "kayit") {
      const name = String(d.ad || "").trim().slice(0, 16);
      if (me.handle) return err("Kullanıcı adın zaten @" + me.handle);
      if (!HANDLE_RE.test(target)) return err("Kullanıcı adı 3-16 karakter olmalı: küçük harf, rakam, _ ve . kullanılabilir.");
      if (this.rows(`SELECT 1 FROM users WHERE handle = ?`, target).length) return err("@" + target + " alınmış, başka bir ad dene.");
      this.sql.exec(`INSERT OR REPLACE INTO users (token, handle, name) VALUES (?, ?, ?)`, me.token, target, name || target);
      me.handle = target;
      ws.serializeAttachment(me);
      this.send(ws, { t: "ben", handle: target, name: name || target });
      this.send(ws, this.list(target));
      return;
    }
    if (!me.handle) return err("Önce bir kullanıcı adı seç.");

    switch (d.t) {
      case "ad": {
        const name = String(d.ad || "").trim().slice(0, 16);
        if (name) this.sql.exec(`UPDATE users SET name = ? WHERE handle = ?`, name, me.handle);
        this.refreshFriendsOf(me.handle);
        break;
      }
      case "durum":
        me.room = String(d.oda || "").slice(0, 4);
        ws.serializeAttachment(me);
        this.refreshFriendsOf(me.handle);
        break;
      case "liste":
        this.refresh(me.handle);
        break;
      case "istek": {
        if (target === me.handle) return err("Kendine istek gönderemezsin.");
        if (!this.rows(`SELECT 1 FROM users WHERE handle = ?`, target).length) return err("@" + target + " diye biri yok.");
        if (this.rows(`SELECT 1 FROM friends WHERE a = ? AND b = ? AND status = 'arkadas'`, me.handle, target).length) return err("@" + target + " zaten arkadaşın.");
        if (this.rows(`SELECT 1 FROM friends WHERE a = ? AND b = ? AND status = 'istek'`, target, me.handle).length) {
          // karşı taraf da istek göndermişse doğrudan arkadaş olun
          this.makeFriends(me.handle, target);
        } else {
          this.sql.exec(`INSERT OR REPLACE INTO friends (a, b, status) VALUES (?, ?, 'istek')`, me.handle, target);
          this.sendTo(target, { t: "istek_geldi", handle: me.handle });
        }
        this.send(ws, { t: "bilgi", m: "@" + target + " kişisine istek gönderildi." });
        this.refresh(me.handle);
        this.refresh(target);
        break;
      }
      case "kabul":
        if (this.rows(`SELECT 1 FROM friends WHERE a = ? AND b = ? AND status = 'istek'`, target, me.handle).length) {
          this.makeFriends(me.handle, target);
          this.refresh(me.handle);
          this.refresh(target);
        }
        break;
      case "reddet":
        this.sql.exec(`DELETE FROM friends WHERE a = ? AND b = ? AND status = 'istek'`, target, me.handle);
        this.sql.exec(`DELETE FROM friends WHERE a = ? AND b = ? AND status = 'istek'`, me.handle, target);
        this.refresh(me.handle);
        this.refresh(target);
        break;
      case "sil":
        this.sql.exec(`DELETE FROM friends WHERE (a = ? AND b = ?) OR (a = ? AND b = ?)`, me.handle, target, target, me.handle);
        this.refresh(me.handle);
        this.refresh(target);
        break;
      case "davet": {
        if (!this.rows(`SELECT 1 FROM friends WHERE a = ? AND b = ? AND status = 'arkadas'`, me.handle, target).length) return err("Sadece arkadaşlarını davet edebilirsin.");
        const code = String(d.oda || "").slice(0, 4);
        if (!this.socketsOf(target).length) return err("@" + target + " şu an çevrimdışı.");
        const name = (this.rows(`SELECT name FROM users WHERE handle = ?`, me.handle)[0] || {}).name || me.handle;
        this.sendTo(target, { t: "davet_geldi", handle: me.handle, name, oda: code });
        this.send(ws, { t: "bilgi", m: "@" + target + " davet edildi." });
        break;
      }
    }
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
