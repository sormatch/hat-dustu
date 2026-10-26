// Hat Düştü oda sunucusu (Cloudflare Worker + Durable Object).
// Her oda kodu bir "Room" nesnesidir. Oyuncular WebSocket ile bağlanır:
//   wss://<sunucu>/oda/ABCD?ad=Mustafa&kur=1
// Metin mesajları JSON'dur; ikili (binary) mesajlar ses parçasıdır ve
// sadece o an telefonla konuşulan kişiye iletilir.

import { Accounts } from "./accounts.js";
import * as Game from "./game.js";
import * as Bots from "./bots.js";
import { privacyHtml, termsHtml } from "./gizlilik.js";
import { hesapSilHtml, hesapSilSonucHtml } from "./hesap_sil.js";
import { adUygun } from "./suzgec.js";
import { AD_RED } from "./accounts.js";
import { Eslestirme, PUBLIC_MAX } from "./eslestirme.js";
import { tx, odaDili } from "./metin.js";
export { Accounts, Eslestirme };

const PUBLIC_WAIT = 25000; // açık odada en fazla bu kadar beklenir, sonra eksikler botla dolar
const PUBLIC_MIN = 4; // açık oda en az bu kadar oyuncuyla (botlar dahil) başlar

const MAX_PLAYERS = 8;

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    if (url.pathname === "/hesap" && req.headers.get("Upgrade") === "websocket") {
      return env.ACCOUNTS.get(env.ACCOUNTS.idFromName("hepsi")).fetch(req);
    }
    // Hızlı Oyun: açık bir oda kodu al
    if (url.pathname === "/hizli") {
      // hesap anahtarı başlıkta gelir (adres çubuğunda değil): engel ilişkisi olan oyuncularla aynı odaya düşmesin
      const hesap = (req.headers.get("x-hesap") || "").slice(0, 80);
      return env.ESLESTIRME.get(env.ESLESTIRME.idFromName("hepsi")).fetch(new Request("https://ic/hizli", { method: "POST", body: JSON.stringify({ hesap }) }));
    }
    // yönetim sayfası (şikayetler, yasaklar): Accounts içinde çalışır, giriş anahtarı env.YONETICI_ANAHTARI
    if (url.pathname === "/yonetim" || url.pathname.startsWith("/yonetim/")) {
      return env.ACCOUNTS.get(env.ACCOUNTS.idFromName("hepsi")).fetch(req);
    }
    // çökme raporu ve analitik olaylar (oyundan küçük paketler)
    if (url.pathname === "/telemetri" && req.method === "POST") {
      return env.ACCOUNTS.get(env.ACCOUNTS.idFromName("hepsi")).fetch(req);
    }
    // mağaza sayfalarının istediği gizlilik politikası ve kullanım koşulları
    if (url.pathname === "/gizlilik" || url.pathname === "/privacy") {
      return new Response(privacyHtml(), { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    if (url.pathname === "/kosullar" || url.pathname === "/terms") {
      return new Response(termsHtml(), { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    // web'den hesap silme (Google Play): GET form, POST kullanıcı adı + şifre ile siler
    if (url.pathname === "/hesap-sil" || url.pathname === "/delete-account") {
      const html = { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "x-frame-options": "DENY" };
      if (req.method !== "POST") return new Response(hesapSilHtml(), { headers: html });
      let dil = "tr";
      let kod = "hata";
      try {
        const body = await req.clone().formData();
        dil = body.get("dil") === "en" ? "en" : "tr";
        const r = await env.ACCOUNTS.get(env.ACCOUNTS.idFromName("hepsi")).fetch(new Request("https://ic/hesap-sil", { method: "POST", headers: req.headers, body: await req.arrayBuffer() }));
        kod = (await r.json()).kod || "hata";
      } catch (e) {
        console.log("hesap silme hatası", e && e.message);
      }
      return new Response(hesapSilSonucHtml(kod, dil), { status: kod === "silindi" ? 200 : kod === "cok_deneme" ? 429 : 400, headers: html });
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
  constructor(state, env) {
    this.state = state;
    this.env = env;
    // bağlantıyı canlı tutmak için oyun her 20 sn'de "ping" yollar
    this.state.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
    this.g = undefined; // oyun durumu (depoda da saklanır; nesne uyuyup uyanınca oradan yüklenir)
    this.bots = []; // lobiden eklenen bot oyuncular: [{id, name, cell}]
    this.kopuk = {}; // oyun sırasında bağlantısı kopanlar: geri dönüş anahtarı -> { info, until }
    state.blockConcurrencyWhile(async () => {
      this.bots = (await state.storage.get("bots")) || [];
      this.kopuk = (await state.storage.get("kopuk")) || {};
      this.acik = (await state.storage.get("acik")) === true;
      this.lobbyAt = (await state.storage.get("lobbyAt")) || 0;
      this.code = (await state.storage.get("code")) || "";
      this.engeller = (await state.storage.get("engeller")) || {}; // hesap anahtarı -> engellediği anahtarlar (WebSocket ekine sığmaz)
    });
  }

  async saveKopuk() {
    await this.state.storage.put("kopuk", this.kopuk);
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
    let dropAt = Infinity; // kopanın geri dönme süresi dolunca oyundan çıkarılır
    for (const k of Object.values(this.kopuk)) dropAt = Math.min(dropAt, k.until);
    await this.state.storage.setAlarm(Math.min(g.ends || Date.now(), wake, botAt, dropAt));
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
      if (sec) this.send(ws, { t: "gizli", task: g.task, round: g.round, ...sec });
    }
  }

  // Mini oyun bitti: herkes kendi sonucunu alır; sonra sıradaki oyun ya da maç sonu.
  async finishRound() {
    const g = this.g;
    const res = Game.resolve(g);
    // tur sonu ekranı için: sıradaki oyun ve ekranın süresi. Puanlar maç sonuna kadar gizli:
    // kimsenin puanı (kendininki dahil) gönderilmez, sadece ne olduğu (ben.msg vb.)
    const nx = g.gi + 1 < g.games.length ? Game.MODES[g.games[g.gi + 1]] : null;
    const extra = { sonraki: nx ? nx.title : "", sonuc_sure: Game.duration(g, "sonuc") };
    for (const ws of this.sockets()) {
      const id = this.info(ws).id;
      let ben = res.private[id] || null;
      if (ben) {
        ben = { ...ben };
        delete ben.delta;
        delete ben.score;
      }
      this.send(ws, { t: "sonuc", round: g.round, rounds: g.rounds, task: g.task, title: Game.mode(g).title, ...res.public, ben, ...extra });
    }
    if (Game.checkEnd(g)) {
      await this.state.storage.deleteAlarm();
      this.broadcast(this.overMsg(g));
      await this.reportMatch(g);
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
    if (!g && this.acik && this.lobbyAt && Date.now() >= this.lobbyAt - 50) return this.publicStart();
    if (!g || g.phase === "bitti") return;
    const now = Date.now();
    // geri dönme süresi dolan kopuk oyuncular artık gerçekten ayrılmış sayılır
    let expired = false;
    for (const [tok, k] of Object.entries(this.kopuk)) {
      if (k.until <= now) {
        delete this.kopuk[tok];
        expired = true;
        await this.leaveInfo(k.info, null);
      }
    }
    if (expired) {
      await this.saveKopuk();
      if (!this.g || this.g.phase === "bitti") return;
    }
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
    // bağlantısı kopmuş ama geri dönebilecek oyuncular listede kalır (yerleri ayrılmış)
    for (const k of Object.values(this.kopuk)) {
      const i = k.info;
      list.push({ id: i.id, name: i.name, cell: i.cell, host: !!i.host, g: i.look || {}, r: true, inv: !!i.inv, kopuk: true });
    }
    return list;
  }

  // Maç sonu mesajı + her oyuncunun görünüşü (kazananın karakteri giydirilsin diye)
  overMsg(g) {
    const msg = Game.overMsg(g);
    const looks = {};
    for (const p of this.players()) looks[p.id] = p.g;
    for (const r of msg.table) r.g = looks[r.id] || {};
    return msg;
  }

  // Maç sonucu hesaplara işlensin (sadece maçı bitiren, hesabı bilinen gerçek oyuncular)
  async reportMatch(g) {
    if (!this.env || !this.env.ACCOUNTS || g.reported) return;
    g.reported = true;
    const tokens = {};
    for (const ws of this.sockets()) {
      const i = this.info(ws);
      if (i.hesap) tokens[i.id] = i.hesap;
    }
    for (const k of Object.values(this.kopuk)) if (k.info.hesap) tokens[k.info.id] = k.info.hesap;
    const table = Game.table(g).filter((r) => !r.left);
    const log = g.log || [];
    const oyuncular = [];
    table.forEach((r, i) => {
      if (!tokens[r.id]) return;
      const oyunlar = {};
      for (const e of log) oyunlar[e.task] = (oyunlar[e.task] || 0) + (e.d[r.id] || 0);
      oyuncular.push({ token: tokens[r.id], sira: i + 1, oyuncu_sayisi: table.length, puan: r.score, oyunlar });
    });
    if (!oyuncular.length) return;
    try {
      await this.env.ACCOUNTS.get(this.env.ACCOUNTS.idFromName("hepsi")).fetch(new Request("https://ic/mac", { method: "POST", body: JSON.stringify({ oyuncular }) }));
    } catch (e) {
      console.log("maç sonucu bildirilemedi", e && e.message);
    }
  }

  // Kim Kim? sürerken telefon/ses için takma kimlik (100+hat); diğer zamanlarda gerçek kimlik
  anon() {
    const g = this.g;
    return g && g.task === "kimkim" && (g.phase === "anons" || g.phase === "telefon") && g.m && g.m.line ? g : null;
  }

  alias(id) {
    const g = this.anon();
    return g ? Game.MODES.kimkim.alias(g, id) : id;
  }

  unalias(x) {
    const g = this.anon();
    return g ? Game.MODES.kimkim.unalias(g, Number(x)) : Number(x);
  }

  // Konuma göre bölge: koridor "K" ya da hücre numarası (hücreler z boyunca 6.6 m arayla, x < 2.15)
  static zone(pos) {
    return pos[0] > 2.15 ? "K" : Math.round(pos[1] / 6.6 + 3.5);
  }

  // a'nın sesi b'ye fiziksel olarak ulaşır mı? (14 m içinde; aynı bölge ya da aradaki kapılar açık)
  audible(a, b) {
    const g = this.g;
    // Kim Kim?'de kimlik gizli: yakın ses yok, sadece telefon (robot sesi)
    if (g && g.task === "kimkim" && (g.phase === "anons" || g.phase === "telefon")) return false;
    const pa = this.pos && this.pos[a];
    const pb = this.pos && this.pos[b];
    if (!pa || !pb || Math.hypot(pa[0] - pb[0], pa[1] - pb[1]) > 14) return false;
    const za = Room.zone(pa);
    const zb = Room.zone(pb);
    if (za === zb) return true;
    const allOpen = g && g.task === "c4" && g.phase === "bomba"; // C4'te tüm kapılar açık
    const open = (z) => z === "K" || allOpen || !!(this.doors && this.doors[z]);
    return open(za) && open(zb);
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
    this.code = code;
    await this.state.storage.put("code", code);
    let name = (url.searchParams.get("ad") || "Oyuncu").trim().slice(0, 16) || "Oyuncu";
    const adRed = !adUygun(name); // uygunsuz ad odada "Oyuncu N" olur, oyuncuya kısa bilgi gider
    if (adRed) name = "Oyuncu";
    const create = url.searchParams.get("kur") === "1";
    const invited = url.searchParams.get("davet") === "1";
    const rejoin = url.searchParams.get("tekrar") || "";
    const hesap = (url.searchParams.get("hesap") || "").slice(0, 80); // hesap anahtarı: maç ödülü için (kimseye gösterilmez)
    const publicJoin = url.searchParams.get("acik") === "1"; // Hızlı Oyun ile gelen
    const dil = odaDili(url.searchParams.get("dil")); // oyuncunun dili; odanın dili = kurucunun dili (kelime havuzları)
    // kopan oyuncu geri dönüyor: aynı kimlik, hücre ve oyun durumu
    const slot = rejoin ? this.kopuk[rejoin] : null;
    if (slot && slot.until > Date.now()) {
      const [client, server] = Object.values(new WebSocketPair());
      this.state.acceptWebSocket(server);
      const info = { ...slot.info, call: 0, calling: 0, ringFrom: 0 };
      delete this.kopuk[rejoin];
      await this.saveKopuk();
      this.setInfo(server, info);
      this.send(server, { t: "hosgeldin", id: info.id, cell: info.cell, host: !!info.host, code, started: true, players: this.players(), tekrar: rejoin, geri: true });
      this.broadcast({ t: "oyuncular", players: this.players() }, server);
      this.broadcast({ t: "bilgi", ...tx("{0} geri döndü.", info.name) }, server);
      return new Response(null, { status: 101, webSocket: client });
    }
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
    const started0 = (await this.state.storage.get("started")) === true;
    // açık odaya ilk gelen odayı kurar; başlamış açık odaya girilmez
    const createNow = create || (publicJoin && existing.length === 0);
    if (publicJoin && existing.length > 0 && (!this.acik || started0)) error = "Bu oda doldu, yeniden aranıyor…";
    else if (create && existing.length > 0) error = "Bu oda kodu kullanımda, tekrar dene.";
    else if (!createNow && existing.length === 0) error = "Bu kodla bir oda bulunamadı.";
    else if (existing.length >= MAX_PLAYERS) error = "Oda dolu (en fazla 8 kişi).";
    // hesap durumu: askıdaki hesap odaya giremez; engellediği oyuncuların anahtarları (ses onlara/onlardan gitmez)
    const durum = await this.hesapDurumu(hesap);
    let hataK = null;
    if (!error && durum.yasak) {
      error = durum.yasak.m;
      hataK = durum.yasak.m_k;
    }
    if (error) {
      server.send(JSON.stringify({ t: "hata", m: error, ...(hataK ? { m_k: hataK } : {}) }));
      server.close(4000, "hata");
      return new Response(null, { status: 101, webSocket: client });
    }

    if (createNow) {
      this.acik = publicJoin;
      this.lobbyAt = 0;
      await this.state.storage.put("acik", this.acik);
      await this.state.storage.put("lobbyAt", 0);
      this.bots = [];
      await this.saveBots();
      this.kopuk = {};
      await this.saveKopuk();
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
    const tekrar = crypto.randomUUID(); // bağlantı koparsa aynı oyuncu olarak geri dönme anahtarı
    if (adRed) name = "Oyuncu " + id;
    const info = { id, name, cell, host: existing.length === 0, call: 0, calling: 0, ringFrom: 0, inv: invited, tekrar, hesap, dil };
    this.setInfo(server, info);
    await this.engelYaz(hesap, durum.engel);

    const started = (await this.state.storage.get("started")) === true;
    this.send(server, { t: "hosgeldin", id, cell, host: info.host, code, started, players: this.players(), tekrar });
    if (adRed) this.send(server, { t: "bilgi", m: AD_RED, ad_red: true });
    this.broadcast({ t: "oyuncular", players: this.players() }, server);
    if (this.acik && !started) await this.publicLobby();
    return new Response(null, { status: 101, webSocket: client });
  }

  // Accounts'tan oyuncunun durumu: { yasak: {m, m_k} | null, engel: [anahtar] }. Ulaşılamazsa engelsiz devam.
  async hesapDurumu(hesap) {
    if (!hesap || !this.env || !this.env.ACCOUNTS) return { yasak: null, engel: [] };
    try {
      const r = await this.env.ACCOUNTS.get(this.env.ACCOUNTS.idFromName("hepsi")).fetch(new Request("https://ic/ic/oda-giris", { method: "POST", body: JSON.stringify({ token: hesap }) }));
      const d = await r.json();
      return { yasak: d.yasak || null, engel: Array.isArray(d.engel) ? d.engel : [] };
    } catch (e) {
      console.log("hesap durumu alınamadı", e && e.message);
      return { yasak: null, engel: [] };
    }
  }

  // İki oyuncu arasında engel var mı (iki yönde): varsa ses birbirine hiç iletilmez
  engelli(a, b) {
    if (!a || !b || !a.hesap || !b.hesap) return false;
    return (this.engeller[a.hesap] || []).includes(b.hesap) || (this.engeller[b.hesap] || []).includes(a.hesap);
  }

  async engelYaz(hesap, liste) {
    if (!hesap) return;
    this.engeller[hesap] = Array.isArray(liste) ? liste.slice(0, 300) : [];
    // odada olmayanların kaydı atılır (oda uzun yaşarsa şişmesin)
    const burada = new Set([...this.sockets().map((w) => this.info(w).hesap), ...Object.values(this.kopuk).map((k) => k.info.hesap), hesap]);
    for (const k of Object.keys(this.engeller)) if (!burada.has(k)) delete this.engeller[k];
    await this.state.storage.put("engeller", this.engeller);
  }

  // Maçtaki bir oyuncuyu (oda içi numarasıyla) bul: bağlı ya da geri dönmesi beklenen
  odadakiBilgi(id) {
    const w = this.byId(id);
    if (w) return this.info(w);
    for (const k of Object.values(this.kopuk)) if (k.info.id === id) return k.info;
    return null;
  }

  // Oda içi şikayet / engelleme: istemci yalnızca oyuncu numarasını yollar, sunucu hesaba çevirir
  async odaIslem(ws, me, d) {
    await this.loadGame();
    const hedefId = this.unalias(d.id); // Kim Kim?'de telefondaki takma numara
    const hedef = this.odadakiBilgi(hedefId);
    if (!hedef || hedefId === me.id) return this.send(ws, { t: "hata", m: "Bu oyuncu bulunamadı." });
    if (!me.hesap || !this.env || !this.env.ACCOUNTS) return this.send(ws, { t: "hata", m: "Sunucuya bağlı değilsin. İnternetini kontrol et." });
    const yol = d.t === "engelle" ? "/ic/oda-engel" : "/ic/oda-sikayet";
    let r = {};
    try {
      const res = await this.env.ACCOUNTS.get(this.env.ACCOUNTS.idFromName("hepsi")).fetch(new Request("https://ic" + yol, {
        method: "POST",
        body: JSON.stringify({ token: me.hesap, hedef: hedef.hesap || "", ad: hedef.name, oda: this.code, neden: d.neden, not: String(d.not || "").slice(0, 300) }),
      }));
      r = await res.json();
    } catch {
      return this.send(ws, { t: "hata", m: "Sunucuya bağlı değilsin. İnternetini kontrol et." });
    }
    if (d.t === "engelle") {
      if (!r.ok) return this.send(ws, { t: "hata", m: "Bu oyuncu engellenemedi." });
      const cur = this.info(ws);
      await this.engelYaz(me.hesap, Array.isArray(r.engel) ? r.engel : [...(this.engeller[me.hesap] || []), hedef.hesap]);
      // telefonda bu kişiyle konuşuyorsa hat kapanır
      if ([cur.call, cur.calling, cur.ringFrom].includes(hedef.id)) this.endCall(ws);
      return this.send(ws, { t: "bilgi", ...tx("{0} engellendi. Sesini artık duymazsın.", hedef.name), engellendi: d.id });
    }
    return this.send(ws, r.ok ? { t: "bilgi", m: "Şikayetin alındı. Teşekkürler." } : { t: "hata", m: r.m || "Şikayet gönderilemedi.", ...(r.m_k ? { m_k: r.m_k } : {}) });
  }

  // Açık oda bekleme salonu: kişi sayısını eşleştiriciye bildir, otomatik başlama zamanını kur.
  async publicLobby() {
    const humans = this.sockets().length;
    try {
      await this.env.ESLESTIRME.get(this.env.ESLESTIRME.idFromName("hepsi")).fetch(new Request("https://ic/durum", { method: "POST", body: JSON.stringify({ kod: this.code, n: humans, started: false, hesaplar: this.sockets().map((w) => this.info(w).hesap).filter(Boolean) }) }));
    } catch {}
    if (humans === 0) return;
    const now = Date.now();
    let at = this.lobbyAt || now + PUBLIC_WAIT;
    if (humans >= PUBLIC_MAX) at = Math.min(at, now + 3000);
    this.lobbyAt = at;
    await this.state.storage.put("lobbyAt", at);
    await this.state.storage.setAlarm(at);
    this.broadcast({ t: "acik_oda", baslama: Math.max(0, Math.round((at - now) / 1000)) });
  }

  // Maçı başlatır (kurucunun "basla"sı ya da açık odada süre dolunca).
  async startGame(list, speed, games) {
    await this.state.storage.put("started", true);
    this.started = true;
    this.g = Game.newGame(list, speed, games);
    const kurucu = this.sockets().map((ws) => this.info(ws)).find((i) => i && i.host);
    this.g.dil = odaDili(kurucu && kurucu.dil);
    this.g.bots = list.filter((p) => p.bot).map((p) => p.id);
    this.g.ends = Date.now() + 4000;
    await this.state.storage.setAlarm(this.g.ends); // hücrelere yerleşmeleri için kısa bekleme
    await this.saveGame();
    this.broadcast({ t: "basladi" });
    if (this.acik) {
      try {
        await this.env.ESLESTIRME.get(this.env.ESLESTIRME.idFromName("hepsi")).fetch(new Request("https://ic/durum", { method: "POST", body: JSON.stringify({ kod: this.code, n: 0, started: true }) }));
      } catch {}
    }
  }

  // Açık odada bekleme süresi doldu: en az 4 kişiye tamamlanacak kadar bot ekle ve başlat.
  async publicStart() {
    if (!this.acik || this.sockets().length === 0) return;
    if ((await this.state.storage.get("started")) === true) return;
    while (this.players().length < PUBLIC_MIN) this.addBot();
    await this.saveBots();
    this.broadcast({ t: "oyuncular", players: this.players() });
    await this.startGame(this.players(), 1, null);
  }

  // Bir bot ekler (lobideki "+ BOT" ve açık oda doldurma)
  addBot() {
    const all = this.players();
    const usedIds = new Set(all.map((p) => p.id));
    const usedCells = new Set(all.map((p) => p.cell));
    let id = 1;
    while (usedIds.has(id)) id++;
    let cell = 0;
    while (usedCells.has(cell)) cell++;
    const names = new Set(all.map((p) => p.name));
    // bot görünüşü: rastgele kadın/erkek gövde, gövdeye uygun saç ve sakal (kimlikler catalog.gd ile aynı)
    const pick = (a) => a[Math.floor(Math.random() * a.length)];
    const kadin = Math.random() < 0.4;
    const kadinAdlari = ["Cingöz Nazlı", "Deli Fadime", "Sinsi Sevim", "Kara Zehra", "Çakal Melek", "Sessiz Gülsüm"];
    const name = (kadin ? kadinAdlari : Bots.NAMES).find((n) => !names.has(n)) || "Bot " + id;
    const outfits = ["turuncu", "beyaz", "gri", "mavi", "cizgili", "kamuflaj"];
    const look = {
      govde: kadin ? "kadin" : "erkek",
      kiyafet: outfits[id % outfits.length],
      ten: Math.floor(Math.random() * 6),
      sac_renk: pick([0, 0, 1, 1, 2, 3, 4, 5]),
      goz: Math.floor(Math.random() * 6),
      sac: kadin
        ? pick(["uzun_duz", "topuz", "kazi_k", "ikiz_orgu", "yuksek_kuyruk", "cift_topuz", "yan_orgu", "kut"])
        : pick(["kisa", "asker", "kazi", "ayrik", "dalgali", "yandan", "mohawk", "kel"]),
      sakal: kadin ? "yok" : pick(["yok", "yok", "biyik", "kirli", "keci", "sakal", "dolgun", "pala"]),
      aksesuar: Math.random() < 0.35 ? pick(kadin ? ["kupe", "inci", "gozluk", "fiyonk"] : ["gozluk", "gunes", "zincir", "bant", "kurdan"]) : "yok",
    };
    this.bots.push({ id, name, cell, look });
  }

  async webSocketMessage(ws, msg) {
    const me = this.info(ws);
    if (!me.id) return;

    // ses: oyun başlamadıysa bekleme salonundaki herkese, başladıysa sadece telefonla konuşulan kişiye
    if (typeof msg !== "string") {
      const bytes = new Uint8Array(msg);
      const tagged = new Uint8Array(bytes.length + 1);
      tagged[0] = this.alias(me.id); // Kim Kim?'de ses takma kimlikle gelir
      tagged.set(bytes, 1);
      msg = tagged;
      if (this.started === undefined) this.started = (await this.state.storage.get("started")) === true;
      if (!this.started) {
        for (const p of this.sockets(ws)) {
          if (this.engelli(me, this.info(p))) continue; // engellenen oyuncunun sesi iletilmez
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
          if (this.engelli(me, this.info(p))) continue;
          try {
            p.send(msg);
          } catch {}
        }
        return;
      }
      // telefondaki kişi + yanında olup sesi duyabilecekler (aynı hücre ya da açık kapıdan koridor)
      for (const p of this.sockets(ws)) {
        const pi = this.info(p);
        if (this.engelli(me, pi)) continue;
        const pid = pi.id;
        if (pid === me.call || this.audible(me.id, pid)) {
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
        // hiz: test için süreleri kısaltır (0.05-1)
        const speed = Math.min(1, Math.max(0.05, Number(d.hiz) || 1));
        await this.startGame(list, speed, d.oyunlar);
        break;
      }

      case "karar": {
        const g = await this.loadGame();
        if (!g || g.phase === "bitti" || g.phase === "sonuc" || g.phase === "baslangic") break;
        // C4: bomba sadece yakındaki oyuncuya verilebilir (botların konumu bilinmez, onlarda bakılmaz)
        if (g.task === "c4" && d.v && d.v.ver !== undefined && this.pos) {
          const a = this.pos[me.id];
          const b = this.pos[Number(d.v.ver)];
          if (a && b && Math.hypot(a[0] - b[0], a[1] - b[1]) > 3.5) {
            this.send(ws, { t: "bilgi", m: "Bombayı vermek için yanına git!" });
            break;
          }
        }
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
          this.send(ws, this.overMsg(g));
        } else if (g && g.phase !== "baslangic") {
          this.send(ws, this.gameState());
          const sec = g.secret[me.id];
          if (sec && g.phase !== "sonuc" && g.phase !== "bitti") this.send(ws, { t: "gizli", task: g.task, round: g.round, ...sec });
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
          this.addBot();
        }
        await this.saveBots();
        this.broadcast({ t: "oyuncular", players: this.players() });
        break;
      }

      case "konum":
        d.id = me.id;
        if (Array.isArray(d.p)) (this.pos ||= {})[me.id] = d.p; // son konum (C4 hile kontrolü için)
        this.broadcast(d, ws);
        break;

      case "profil": {
        // ad ve karakter görünüşü (küçük bir sözlük); herkese yeni liste gider
        const name = String(d.ad || "").trim().slice(0, 16);
        if (name && adUygun(name)) me.name = name;
        else if (name && me.adRed !== name) {
          me.adRed = name; // aynı ad için bir kez söylenir
          this.send(ws, { t: "bilgi", m: AD_RED, ad_red: true });
        }
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

      case "sikayet":
      case "engelle":
        // maçtaki oyuncu: { id: oda içi numara, neden, not } (hesap anahtarı istemciye hiç gitmez)
        await this.odaIslem(ws, me, d);
        break;

      case "emote":
        this.broadcast({ t: "emote", id: me.id, e: String(d.e || "").slice(0, 16) }, ws);
        break;

      case "kapi":
        (this.doors ||= {})[Number(d.cell)] = !!d.open; // yakındaki ses kapı kapalıysa geçmez
        this.broadcast({ t: "kapi", cell: d.cell, open: !!d.open }, ws);
        break;

      case "ara": {
        await this.loadGame();
        d.to = this.unalias(d.to);
        if (this.isBot(d.to)) {
          this.send(ws, { t: "bilgi", m: "Botlar telefonu açamaz." });
          this.send(ws, { t: "mesgul", to: d.to });
          break;
        }
        const p = this.byId(d.to);
        const pi = p ? this.info(p) : null;
        const g = await this.loadGame();
        const dead = g && g.phase !== "bitti" && (!g.players.includes(me.id) || (pi && !g.players.includes(pi.id)));
        if (!p || p === ws || dead || me.call || me.calling || pi.call || pi.calling || pi.ringFrom || this.engelli(me, pi)) {
          this.send(ws, { t: "mesgul", to: d.to });
          break;
        }
        pi.ringFrom = me.id;
        me.calling = pi.id;
        this.setInfo(p, pi);
        this.setInfo(ws, me);
        this.send(p, { t: "caliyor", from: this.alias(me.id) });
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
        await this.loadGame();
        this.send(ws, { t: "baglandi", with: this.alias(pi.id) });
        this.send(p, { t: "baglandi", with: this.alias(me.id) });
        this.broadcast({ t: "zil", cell: me.cell, on: false });
        break;
      }

      case "kapat":
        this.endCall(ws);
        break;

      case "cik":
        // oyuncu bilerek çıkıyor: geri dönme hakkı tutulmaz
        await this.leave(ws);
        try {
          ws.close(1000, "cikti");
        } catch {}
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
    await this.leaveInfo(me, ws);
  }

  // Bağlantı koptu: oyun sürüyorsa 45 sn geri dönme hakkı tanınır, değilse normal ayrılış.
  async drop(ws) {
    const me = this.info(ws);
    if (!me.id) return;
    const g = await this.loadGame();
    const playing = g && g.phase !== "bitti" && g.players.includes(me.id) && me.tekrar;
    if (!playing) return this.leave(ws);
    this.endCall(ws);
    const info = this.info(ws);
    try {
      this.setInfo(ws, {});
    } catch {}
    this.kopuk[me.tekrar] = { info, until: Date.now() + 45000 };
    await this.saveKopuk();
    this.broadcast({ t: "bilgi", ...tx("{0} bağlantısı koptu, bekleniyor…", me.name) }, ws);
    this.broadcast({ t: "oyuncular", players: this.players(ws) }, ws);
    await this.rearm();
  }

  // Bir oyuncunun gerçekten ayrılması (ws: kendi bağlantısı ya da null: süresi dolmuş kopuk oyuncu)
  async leaveInfo(me, ws) {
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
      this.broadcast({ t: "bilgi", ...tx("{0} oyundan ayrıldı.", me.name) }, ws);
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
        await this.reportMatch(g);
        this.broadcast(this.overMsg(g), ws);
      }
      await this.saveGame();
    }
    if (rest.length === 0 && this.bots.length) {
      this.bots = [];
      await this.saveBots();
    }
    if (this.acik && !(await this.state.storage.get("started"))) await this.publicLobby();
    this.broadcast({ t: "ayrildi", id: me.id }, ws);
    this.broadcast({ t: "oyuncular", players: this.players(ws) }, ws);
  }

  async webSocketClose(ws) {
    await this.drop(ws);
  }

  async webSocketError(ws) {
    await this.drop(ws);
  }
}
