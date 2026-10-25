// Hat Düştü oda sunucusu (Cloudflare Worker + Durable Object).
// Her oda kodu bir "Room" nesnesidir. Oyuncular WebSocket ile bağlanır:
//   wss://<sunucu>/oda/ABCD?ad=Mustafa&kur=1
// Metin mesajları JSON'dur; ikili (binary) mesajlar ses parçasıdır ve
// sadece o an telefonla konuşulan kişiye iletilir.

import { Accounts } from "./accounts.js";
import * as Game from "./game.js";
import * as Bots from "./bots.js";
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
    this.bots = []; // lobiden eklenen bot oyuncular: [{id, name, cell}]
    state.blockConcurrencyWhile(async () => {
      this.bots = (await state.storage.get("bots")) || [];
    });
  }

  async saveBots() {
    await this.state.storage.put("bots", this.bots);
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
    await this.rearm();
  }

  // Alarm: aşama sonu ya da oyunun kendi zamanlayıcısı (ör. ruletin sıra süresi, bombanın patlaması), hangisi önceyse.
  async rearm() {
    const g = this.g;
    if (!g || g.phase === "bitti") return;
    const wake = g.m && g.m.wake && g.phase !== "sonuc" && g.phase !== "baslangic" ? g.m.wake : Infinity;
    const botAt = Bots.plan(g, Date.now()); // botların sıradaki kararı
    await this.state.storage.setAlarm(Math.min(g.ends || Date.now(), wake, botAt));
  }

  // Bir oyunun döndürdüğü mesajları dağıtır: reply (yapana), others, privates (id -> mesaj), broadcast.
  // finish: oyun hemen biter; advance: sıradaki aşamaya geçilir.
  async deliver(r, ws) {
    if (!r) return;
    if (r.reply && ws) this.send(ws, r.reply);
    for (const o of r.others || []) {
      const w2 = this.byId(o.to);
      if (w2) this.send(w2, o.msg);
    }
    for (const [id, msg] of Object.entries(r.privates || {})) {
      const w2 = this.byId(Number(id));
      if (w2) this.send(w2, msg);
    }
    if (r.broadcast) this.broadcast(r.broadcast);
    if (r.finish) await this.finishRound();
    else if (r.advance) await this.advance();
    else await this.rearm();
  }

  gameState() {
    const g = this.g;
    const m = Game.mode(g);
    return {
      t: "oyun", phase: g.phase, round: g.round, rounds: g.rounds, task: g.task, title: m ? m.title : "", rule: m ? m.rule : "",
      kalan: Math.max(0, Math.round(((g.ends || Date.now()) - Date.now()) / 1000)), kalan_ms: Math.max(0, (g.ends || Date.now()) - Date.now()), players: g.players,
      gizli_puan: m ? !!m.hidden : true, ...(m && g.m ? m.stateExtra(g) : {}),
    };
  }

  // Her oyuncuya kendi gizli bilgisi (rolü, kutusu, tahtası...).
  sendSecrets() {
    const g = this.g;
    for (const ws of this.sockets()) {
      const id = this.info(ws).id;
      const sec = g.secret[id];
      if (sec) this.send(ws, { t: "gizli", task: g.task, round: g.round, puan: g.score[id], ...sec });
    }
  }

  // Mini oyun bitti: herkes kendi sonucunu alır; sonra sıradaki oyun ya da maç sonu.
  async finishRound() {
    const g = this.g;
    const res = Game.resolve(g);
    for (const ws of this.sockets()) {
      const id = this.info(ws).id;
      this.send(ws, { t: "sonuc", round: g.round, rounds: g.rounds, task: g.task, title: Game.mode(g).title, ...res.public, ben: res.private[id] || null });
    }
    if (Game.checkEnd(g)) {
      await this.state.storage.deleteAlarm();
      this.broadcast({ t: "bitti", winner: g.winner, table: Game.table(g), rounds: g.round });
    } else {
      await this.schedule("sonuc");
      const next = Game.MODES[g.games[g.gi + 1]];
      this.broadcast({ ...this.gameState(), sonraki: next ? next.title : "" });
    }
  }

  async setPhase(phase) {
    this.g.phase = phase;
    await this.schedule(phase);
    const hook = Game.onPhase(this.g, phase);
    this.broadcast(this.gameState());
    if (hook) await this.deliver(hook, null);
  }

  // Sıradaki aşamaya geç; aşama kalmadıysa oyunu bitir.
  async advance() {
    const next = Game.nextPhase(this.g);
    if (next) await this.setPhase(next);
    else await this.finishRound();
  }

  async alarm() {
    try {
      await this.alarmStep();
    } catch (e) {
      console.log("alarm hatası", e && e.stack ? e.stack : e);
      await this.state.storage.setAlarm(Date.now() + 2000);
    }
  }

  async alarmStep() {
    const g = await this.loadGame();
    if (!g || g.phase === "bitti") return;
    const now = Date.now();
    if (g.phase === "baslangic" || g.phase === "sonuc") {
      Game.startNext(g);
      await this.schedule(g.phase);
      const hook = Game.onPhase(g, g.phase);
      this.broadcast(this.gameState());
      this.sendSecrets();
      if (hook) await this.deliver(hook, null);
    } else if (g.m && g.m.wake && now >= g.m.wake - 50) {
      g.m.wake = 0;
      await this.deliver(Game.onWake(g), null);
    } else {
      const acts = Bots.due(g, now);
      if (acts.length) await this.botActs(acts);
      else if (now >= (g.ends || 0) - 50) await this.advance();
      else await this.rearm();
    }
    await this.saveGame();
  }

  // Botların kararları: bir insanın "karar" mesajı gibi işlenir.
  async botActs(acts) {
    const g = this.g;
    const round = g.round;
    for (const [id, v] of acts) {
      if (g.round !== round || g.phase === "sonuc" || g.phase === "bitti" || g.phase === "baslangic") break;
      const r = Game.answer(g, id, v);
      if (r) await this.deliver(r, null);
    }
    await this.rearm();
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
    const list = this.sockets(except).map((ws) => {
      const { id, name, cell, host, look, ready, inv } = this.info(ws);
      return { id, name, cell, host, g: look || {}, r: !!ready, inv: !!inv };
    });
    for (const b of this.bots) list.push({ id: b.id, name: b.name, cell: b.cell, host: false, g: b.look || {}, r: true, inv: true, bot: true });
    return list;
  }

  isBot(id) {
    return this.bots.some((b) => b.id === id);
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
    const invited = url.searchParams.get("davet") === "1";
    let existing = this.players();
    // bağlı insan kalmadıysa eski botlar da gitmiş sayılır
    if (this.sockets().length === 0 && this.bots.length) {
      this.bots = [];
      await this.saveBots();
      existing = this.players();
    }

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
      this.bots = [];
      await this.saveBots();
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
    const info = { id, name, cell, host: existing.length === 0, call: 0, calling: 0, ringFrom: 0, inv: invited };
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
      // Rus Ruleti: herkes koridorda aynı masada; sesler masadaki herkese gider, ölüler konuşamaz
      const g = await this.loadGame();
      if (g && g.task === "rulet" && (g.phase === "anons" || g.phase === "oyun") && g.m) {
        if (g.m.dead && g.m.dead.includes(me.id)) return;
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
        this.g = Game.newGame(list, speed, d.oyunlar);
        this.g.bots = list.filter((p) => p.bot).map((p) => p.id);
        this.g.ends = Date.now() + 4000;
        await this.state.storage.setAlarm(this.g.ends); // hücrelere yerleşmeleri için kısa bekleme
        await this.saveGame();
        this.broadcast({ t: "basladi" });
        break;
      }

      case "karar": {
        const g = await this.loadGame();
        if (!g || g.phase === "bitti" || g.phase === "sonuc" || g.phase === "baslangic") break;
        const r = Game.answer(g, me.id, d.v);
        if (!r) break;
        await this.deliver(r, ws);
        await this.saveGame();
        break;
      }

      case "durum": {
        // yeniden bağlanan ya da sonradan gelen için güncel oyun durumu
        const g = await this.loadGame();
        if (g && g.phase === "bitti") {
          this.send(ws, { t: "bitti", winner: g.winner, table: Game.table(g), rounds: g.round });
        } else if (g && g.phase !== "baslangic") {
          this.send(ws, this.gameState());
          const sec = g.secret[me.id];
          if (sec && g.phase !== "sonuc" && g.phase !== "bitti") this.send(ws, { t: "gizli", task: g.task, round: g.round, puan: g.score[me.id], ...sec });
        }
        break;
      }

      case "bot_ekle":
      case "bot_cikar": {
        // kurucu bekleme salonunda bot ekler/çıkarır (test ve az kişiyle oynamak için)
        if (!me.host || (await this.state.storage.get("started")) === true) break;
        if (d.t === "bot_cikar") {
          this.bots.pop();
        } else {
          const all = this.players();
          if (all.length >= MAX_PLAYERS) {
            this.send(ws, { t: "bilgi", m: "Oda dolu (en fazla 8 kişi)." });
            break;
          }
          const usedIds = new Set(all.map((p) => p.id));
          const usedCells = new Set(all.map((p) => p.cell));
          let id = 1;
          while (usedIds.has(id)) id++;
          let cell = 0;
          while (usedCells.has(cell)) cell++;
          const names = new Set(all.map((p) => p.name));
          const name = Bots.NAMES.find((n) => !names.has(n)) || "Bot " + id;
          const outfits = ["turuncu", "beyaz", "gri", "mavi", "cizgili", "kamuflaj"];
          this.bots.push({ id, name, cell, look: { kiyafet: outfits[id % outfits.length] } });
        }
        await this.saveBots();
        this.broadcast({ t: "oyuncular", players: this.players() });
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
        if (this.isBot(d.to)) {
          this.send(ws, { t: "bilgi", m: "Botlar telefonu açamaz." });
          this.send(ws, { t: "mesgul", to: d.to });
          break;
        }
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
      const cancel = Game.removePlayer(g, me.id);
      this.broadcast({ t: "bilgi", m: `${me.name} oyundan ayrıldı.` }, ws);
      if (cancel && g.phase !== "sonuc" && g.phase !== "baslangic") {
        g.phase = "sonuc"; // bu mini oyun iptal, sıradakine geç
        await this.schedule("sonuc");
      } else {
        await this.rearm(); // oyun kendi zamanlayıcısını kurmuş olabilir (ör. rulette sıra)
        // silah/bomba ayrılandaysa yeni sahibi herkes görsün
        if (g.phase !== "sonuc" && g.phase !== "baslangic" && g.players.length >= 2) this.broadcast(this.gameState(), ws);
      }
      if (g.players.length < 2 && Game.checkEnd(g)) {
        await this.state.storage.deleteAlarm();
        this.broadcast({ t: "bitti", winner: g.winner, table: Game.table(g), rounds: g.round }, ws);
      }
      await this.saveGame();
    }
    if (rest.length === 0 && this.bots.length) {
      this.bots = [];
      await this.saveBots();
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
