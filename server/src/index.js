// Hat Düştü oda sunucusu (Cloudflare Worker + Durable Object).
// Her oda kodu bir "Room" nesnesidir. Oyuncular WebSocket ile bağlanır:
//   wss://<sunucu>/oda/ABCD?ad=Mustafa&kur=1
// Metin mesajları JSON'dur; ikili (binary) mesajlar ses parçasıdır ve
// sadece o an telefonla konuşulan kişiye iletilir.

import { Accounts } from "./accounts.js";
import * as Game from "./game.js";
export { Accounts };

const MAX_PLAYERS = 8;

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    if (url.pathname === "/hesap" && req.headers.get("Upgrade") === "websocket") {
      return env.ACCOUNTS.get(env.ACCOUNTS.idFromName("hepsi")).fetch(req);
    }
    const m = url.pathname.match(/^\/oda\/([A-Z0-9]{4})$/);
    if (!m) return new Response("Hat Düştü sunucusu çalışıyor\n");
    if (req.headers.get("Upgrade") !== "websocket") {
      return new Response("WebSocket gerekli", { status: 426 });
    }
    const room = env.ROOMS.get(env.ROOMS.idFromName(m[1]));
    return room.fetch(req);
  },
};

export class Room {
  constructor(state) {
    this.state = state;
    // bağlantıyı canlı tutmak için oyun her 20 sn'de "ping" yollar
    this.state.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
    this.g = undefined; // oyun durumu (depoda da saklanır; nesne uyuyup uyanınca oradan yüklenir)
  }

  async loadGame() {
    if (this.g === undefined) this.g = (await this.state.storage.get("game")) || null;
    return this.g;
  }

  async saveGame() {
    await this.state.storage.put("game", this.g);
  }

  // Bir sonraki aşamaya geçiş zamanını kurar.
  async schedule(phase) {
    const g = this.g;
    g.ends = Date.now() + Game.duration(g, phase) * 1000;
    await this.state.storage.setAlarm(g.ends);
  }

  gameState() {
    const g = this.g;
    const t = Game.TASKS[g.task] || {};
    return {
      t: "oyun", phase: g.phase, round: g.round, rounds: g.rounds, task: g.task, title: t.title || "", rule: t.rule || "",
      kalan: Math.max(0, Math.round(((g.ends || Date.now()) - Date.now()) / 1000)),
      writer: g.writer, writer_name: g.names[g.writer] || "", players: g.players,
    };
  }

  // Her oyuncuya kendi gizli bilgisi (rolü, hedef sayı).
  sendSecrets() {
    const g = this.g;
    for (const ws of this.sockets()) {
      const id = this.info(ws).id;
      const sec = g.secret[id];
      if (sec) this.send(ws, { t: "gizli", task: g.task, round: g.round, ...sec });
    }
  }

  // Tur sonu: kelime herkese açıklanır ama puanlar gizli; herkes sadece kendi sonucunu alır.
  async finishRound() {
    const g = this.g;
    const res = Game.resolve(g);
    for (const ws of this.sockets()) {
      const id = this.info(ws).id;
      this.send(ws, { t: "sonuc", round: g.round, rounds: g.rounds, title: Game.TASKS[g.task].title, ...res.public, ben: res.private[id] || null });
    }
    if (Game.checkEnd(g)) {
      await this.state.storage.deleteAlarm();
      this.broadcast({ t: "bitti", winner: g.winner, table: Game.table(g), rounds: g.round });
    } else {
      await this.schedule("sonuc");
    }
  }

  async setPhase(phase) {
    this.g.phase = phase;
    await this.schedule(phase);
    this.broadcast(this.gameState());
  }

  async alarm() {
    const g = await this.loadGame();
    if (!g || g.phase === "bitti") return;
    if (g.phase === "baslangic" || g.phase === "sonuc") {
      Game.startRound(g);
      await this.schedule("anons");
      this.broadcast(this.gameState());
      this.sendSecrets();
    } else if (g.phase === "anons") {
      await this.setPhase("telefon");
    } else if (g.phase === "telefon") {
      await this.finishRound();
    }
    await this.saveGame();
  }

  info(ws) {
    return ws.deserializeAttachment() || {};
  }

  setInfo(ws, info) {
    ws.serializeAttachment(info);
  }

  sockets(except) {
    return this.state.getWebSockets().filter((ws) => ws !== except && this.info(ws).id);
  }

  players(except) {
    return this.sockets(except).map((ws) => {
      const { id, name, cell, host, look, ready } = this.info(ws);
      return { id, name, cell, host, g: look || {}, r: !!ready };
    });
  }

  byId(id) {
    return this.sockets().find((ws) => this.info(ws).id === id);
  }

  send(ws, obj) {
    try {
      ws.send(JSON.stringify(obj));
    } catch {}
  }

  broadcast(obj, except) {
    const s = JSON.stringify(obj);
    for (const ws of this.sockets(except)) {
      try {
        ws.send(s);
      } catch {}
    }
  }

  async fetch(req) {
    const url = new URL(req.url);
    const code = url.pathname.slice(-4);
    const name = (url.searchParams.get("ad") || "Oyuncu").trim().slice(0, 16) || "Oyuncu";
    const create = url.searchParams.get("kur") === "1";
    const existing = this.players();

    const [client, server] = Object.values(new WebSocketPair());
    this.state.acceptWebSocket(server);

    let error = "";
    if (create && existing.length > 0) error = "Bu oda kodu kullanımda, tekrar dene.";
    else if (!create && existing.length === 0) error = "Bu kodla bir oda bulunamadı.";
    else if (existing.length >= MAX_PLAYERS) error = "Oda dolu (en fazla 8 kişi).";
    if (error) {
      server.send(JSON.stringify({ t: "hata", m: error }));
      server.close(4000, "hata");
      return new Response(null, { status: 101, webSocket: client });
    }

    if (create) {
      await this.state.storage.put("started", false);
      this.started = false;
      this.g = null;
      await this.state.storage.delete("game");
      await this.state.storage.deleteAlarm();
    }
    const usedCells = new Set(existing.map((p) => p.cell));
    let cell = 0;
    while (usedCells.has(cell)) cell++;
    const usedIds = new Set(existing.map((p) => p.id));
    let id = 1;
    while (usedIds.has(id)) id++;
    const info = { id, name, cell, host: existing.length === 0, call: 0, calling: 0, ringFrom: 0 };
    this.setInfo(server, info);

    const started = (await this.state.storage.get("started")) === true;
    this.send(server, { t: "hosgeldin", id, cell, host: info.host, code, started, players: this.players() });
    this.broadcast({ t: "oyuncular", players: this.players() }, server);
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws, msg) {
    const me = this.info(ws);
    if (!me.id) return;

    // ses: oyun başlamadıysa bekleme salonundaki herkese, başladıysa sadece telefonla konuşulan kişiye
    if (typeof msg !== "string") {
      const bytes = new Uint8Array(msg);
      const tagged = new Uint8Array(bytes.length + 1);
      tagged[0] = me.id;
      tagged.set(bytes, 1);
      msg = tagged;
      if (this.started === undefined) this.started = (await this.state.storage.get("started")) === true;
      if (!this.started) {
        for (const p of this.sockets(ws)) {
          try {
            p.send(msg);
          } catch {}
        }
        return;
      }
      if (me.call) {
        const p = this.byId(me.call);
        if (p) {
          try {
            p.send(msg);
          } catch {}
        }
      }
      return;
    }

    let d;
    try {
      d = JSON.parse(msg);
    } catch {
      return;
    }

    switch (d.t) {
      case "basla": {
        if (!me.host) break;
        const list = this.players();
        if (list.length < 2) {
          this.send(ws, { t: "bilgi", m: "Oyunu başlatmak için en az 2 kişi gerekli." });
          break;
        }
        await this.state.storage.put("started", true);
        this.started = true;
        // hiz: test için süreleri kısaltır (0.05-1)
        const speed = Math.min(1, Math.max(0.05, Number(d.hiz) || 1));
        this.g = Game.newGame(list, speed);
        this.g.ends = Date.now() + 4000;
        await this.state.storage.setAlarm(this.g.ends); // hücrelere yerleşmeleri için kısa bekleme
        await this.saveGame();
        this.broadcast({ t: "basladi" });
        break;
      }

      case "karar": {
        const g = await this.loadGame();
        if (!g || g.phase === "bitti") break;
        const r = Game.answer(g, me.id, d.v);
        if (!r) {
          this.send(ws, { t: "bilgi", m: "Bu kelime yazılamaz (2-16 harf, sadece harf)." });
          break;
        }
        // süre bitene kadar istediği kadar değiştirebilir; sonuç süre bitince
        this.send(ws, { t: "karar_alindi", ne: r });
        await this.saveGame();
        break;
      }

      case "durum": {
        // yeniden bağlanan ya da sonradan gelen için güncel oyun durumu
        const g = await this.loadGame();
        if (g) {
          this.send(ws, this.gameState());
          const sec = g.secret[me.id];
          if (sec && g.phase !== "sonuc" && g.phase !== "bitti") this.send(ws, { t: "gizli", task: g.task, round: g.round, ...sec });
        }
        break;
      }

      case "konum":
        d.id = me.id;
        this.broadcast(d, ws);
        break;

      case "profil": {
        // ad ve karakter görünüşü (küçük bir sözlük); herkese yeni liste gider
        const name = String(d.ad || "").trim().slice(0, 16);
        if (name) me.name = name;
        if (d.g && typeof d.g === "object") {
          const look = JSON.stringify(d.g);
          if (look.length <= 600) me.look = d.g;
        }
        this.setInfo(ws, me);
        this.broadcast({ t: "oyuncular", players: this.players() });
        break;
      }

      case "hazir":
        me.ready = !!d.on;
        this.setInfo(ws, me);
        this.broadcast({ t: "oyuncular", players: this.players() });
        break;

      case "emote":
        this.broadcast({ t: "emote", id: me.id, e: String(d.e || "").slice(0, 16) }, ws);
        break;

      case "kapi":
        this.broadcast({ t: "kapi", cell: d.cell, open: !!d.open }, ws);
        break;

      case "ara": {
        const p = this.byId(d.to);
        const pi = p ? this.info(p) : null;
        const g = await this.loadGame();
        const dead = g && g.phase !== "bitti" && (!g.players.includes(me.id) || (pi && !g.players.includes(pi.id)));
        if (!p || p === ws || dead || me.call || me.calling || pi.call || pi.calling || pi.ringFrom) {
          this.send(ws, { t: "mesgul", to: d.to });
          break;
        }
        pi.ringFrom = me.id;
        me.calling = pi.id;
        this.setInfo(p, pi);
        this.setInfo(ws, me);
        this.send(p, { t: "caliyor", from: me.id });
        this.broadcast({ t: "zil", cell: pi.cell, on: true });
        break;
      }

      case "cevap": {
        const p = this.byId(me.ringFrom);
        if (!p) {
          me.ringFrom = 0;
          this.setInfo(ws, me);
          this.send(ws, { t: "kapandi" });
          break;
        }
        const pi = this.info(p);
        me.call = pi.id;
        me.ringFrom = 0;
        pi.call = me.id;
        pi.calling = 0;
        this.setInfo(ws, me);
        this.setInfo(p, pi);
        this.send(ws, { t: "baglandi", with: pi.id });
        this.send(p, { t: "baglandi", with: me.id });
        this.broadcast({ t: "zil", cell: me.cell, on: false });
        break;
      }

      case "kapat":
        this.endCall(ws);
        break;
    }
  }

  // Konuşmayı, çalan aramayı ya da bekleyen aramayı bitirir; karşı tarafa haber verir.
  endCall(ws) {
    const me = this.info(ws);
    const partnerId = me.call || me.calling || me.ringFrom;
    let ringingCell = -1;
    if (me.ringFrom) ringingCell = me.cell;
    me.call = me.calling = me.ringFrom = 0;
    this.setInfo(ws, me);
    if (!partnerId) return;
    const p = this.byId(partnerId);
    if (p) {
      const pi = this.info(p);
      if (pi.ringFrom === me.id) ringingCell = pi.cell;
      if (pi.call === me.id) pi.call = 0;
      if (pi.calling === me.id) pi.calling = 0;
      if (pi.ringFrom === me.id) pi.ringFrom = 0;
      this.setInfo(p, pi);
      this.send(p, { t: "kapandi" });
    }
    if (ringingCell >= 0) this.broadcast({ t: "zil", cell: ringingCell, on: false });
  }

  async leave(ws) {
    const me = this.info(ws);
    if (!me.id) return;
    this.endCall(ws);
    try {
      this.setInfo(ws, {});
    } catch {}
    const rest = this.sockets(ws);
    if (me.host && rest.length > 0) {
      // kurucu çıkarsa en eski oyuncu kurucu olur
      rest.sort((a, b) => this.info(a).id - this.info(b).id);
      const h = this.info(rest[0]);
      h.host = true;
      this.setInfo(rest[0], h);
    }
    const g = await this.loadGame();
    if (g && g.phase !== "bitti" && g.players.includes(me.id)) {
      Game.removePlayer(g, me.id);
      this.broadcast({ t: "bilgi", m: `${me.name} oyundan ayrıldı.` }, ws);
      if (me.id === g.writer && ["anons", "telefon"].includes(g.phase)) {
        // yazan çıktı: tur iptal, sıradaki tura geç
        g.phase = "sonuc";
        await this.schedule("sonuc");
      }
      if (Game.checkEnd(g)) {
        await this.state.storage.deleteAlarm();
        this.broadcast({ t: "bitti", winner: g.winner, table: Game.table(g), rounds: g.round }, ws);
      }
      await this.saveGame();
    }
    this.broadcast({ t: "ayrildi", id: me.id }, ws);
    this.broadcast({ t: "oyuncular", players: this.players(ws) }, ws);
  }

  async webSocketClose(ws) {
    await this.leave(ws);
  }

  async webSocketError(ws) {
    await this.leave(ws);
  }
}
