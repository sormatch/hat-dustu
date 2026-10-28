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
import { kodFormHtml, kodSonucHtml, webDili } from "./eposta_web.js";
import { adUygun } from "./suzgec.js";
import { AD_RED } from "./accounts.js";
import { Eslestirme, PUBLIC_MAX } from "./eslestirme.js";
import { Odalar, odaAyari, kisiSiniri, ayarMsg, odaBildir, odaNabiz, nabizZamani } from "./odalar.js";
import { tx, odaDili } from "./metin.js";
import { price } from "./ekonomi.js";
export { Accounts, Eslestirme, Odalar };

const PUBLIC_WAIT = 25000; // açık odada en fazla bu kadar beklenir, sonra eksikler botla dolar
const PUBLIC_MIN = 4; // açık oda en az bu kadar oyuncuyla (botlar dahil) başlar
// Hazır sistemi: maç yalnız bütün insanlar HAZIR deyince başlar (botlar hep hazır). Hızlı Oyun'da HAZIR demeyen
// oyuncu salona girdikten bu kadar sonra kendiliğinden hazır sayılır (oda sonsuza dek beklemesin); herkes hazır
// olunca geri sayım en az HAZIR_SAYIM sürer (bot doldurma zamanı PUBLIC_WAIT daha önce dolmuş olsa da).
const OTO_HAZIR = 35000;
const HAZIR_SAYIM = 5000;

const MAX_PLAYERS = 8;
// Maç sonu ekranı: oyuncu "TEKRAR OYNA" demezse en geç bu kadar sonra lobiye döner (test hızında kısalır, en az 20 sn)
const MAC_SONU_SURE = 30000;
const KOPUK_SURE = 45000; // bağlantısı kopan oyuncunun maça geri dönebileceği süre
const KISALT_SN = 15; // herkes oy verince / eşleştirmeyi kaydedince aşamanın kalan süresi (oylamalı oyunlar: mode.kisalt)

// Gelen mesaj sınırları: büyük mesaj atılır; her bağlantı için saniyede en çok [hız, birikim] mesaj (jeton kovası).
// Telefon konumu ~8/sn, ses 25 parça/sn (40 ms) yollar; aşan mesajlar sessizce atılır.
const MESAJ_MAX = 4096; // JSON metin (karakter)
const SES_MAX = 4096; // ses parçası (bayt; normali 640)
const ORAN = {
  ses: [40, 80],
  konum: [15, 30],
  genel: [10, 25], // karar, kapı, arama, hareket (emote)...
  agir: [2, 6], // herkese oyuncu listesi yollatanlar (profil, hazır, bot), hesap sunucusuna gidenler (şikayet, engel)
};
const SPAM_KES = 400; // 10 sn içinde bu kadar mesaj atılırsa bağlantı kesilir
const AGIR = new Set(["profil", "hazir", "bot_ekle", "bot_cikar", "sikayet", "engelle", "basla", "tekrar", "mik", "oda_ayar"]);
// Alarm bekçisi: alarm üst üste hata verirse önce o mini oyun atlanır, sürerse maç bitirilir (maç asla takılı kalmaz)
const BEKCI_ATLA = 3;
const BEKCI_BITIR = 6;
const YEREL = new Set(["127.0.0.1", "localhost", "[::1]", "::1"]); // test hızı (hiz<1) yalnız yerel sunucuda

// Oyuncu adı: kontrol / görünmez yön karakterleri atılır, boşluk sadeleşir, en çok 16 harf (emoji bölünmez)
function temizAd(s) {
  const t = String(s || "").replace(/[\u0000-\u001f\u007f​-‏‪-‮⁦-⁩﻿]/g, "").replace(/\s+/g, " ").trim();
  return Array.from(t).slice(0, 16).join("").trim();
}

// Karakter görünüşü (lobide herkese gider): düz sözlük, kısa anahtar ve değerler (yazı, sayı, evet/hayır)
function temizGorunus(g) {
  if (!g || typeof g !== "object" || Array.isArray(g)) return null;
  const out = {};
  let n = 0;
  for (const [k, v] of Object.entries(g)) {
    if (n >= 24 || typeof k !== "string" || k.length > 16) continue;
    if (typeof v === "string") out[k] = v.slice(0, 32);
    else if (typeof v === "number" && Number.isFinite(v)) out[k] = v;
    else if (typeof v === "boolean") out[k] = v;
    else continue;
    n++;
  }
  return out;
}

// Görünüşte paralı eşya olabilen anahtarlar (ekonomi.js ITEMS kategorileri) ve sahibi değilse giydirilen varsayılan
// (catalog.gd DEFAULT_LOOK; gövde ve kaş hep bedava)
const VARSAYILAN_GORUNUS = { sac: "kisa", sakal: "yok", kiyafet: "turuncu", aksesuar: "yok", sapka: "yok", dovme: "yok" };
const SAHIP_TAZE = 1000; // sahip listesinde olmayan eşya gelince liste yeniden çekilir (en sık bu kadar ms'de bir)

// Bu anahtar şifreli bir hesabın mı (misafir oynayamaz). Hesap sunucusuna ulaşılamazsa anahtarı olan geçer.
async function hesapVarMi(env, hesap) {
  if (!hesap || hesap.length < 16) return false;
  if (!env || !env.ACCOUNTS) return true;
  try {
    const r = await env.ACCOUNTS.get(env.ACCOUNTS.idFromName("hepsi")).fetch(new Request("https://ic/ic/oda-giris", { method: "POST", body: JSON.stringify({ token: hesap }) }));
    return !!(await r.json()).hesap;
  } catch (e) {
    console.log("hesap durumu alınamadı", e && e.message);
    return true;
  }
}

const sayi = (v, lim) => typeof v === "number" && Number.isFinite(v) && Math.abs(v) <= lim;
const yuvarla = (v) => Math.round(v * 100) / 100;

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    if (url.pathname === "/hesap" && req.headers.get("Upgrade") === "websocket") {
      // yaklaşık konum (şehir, ülke): yalnızca şifre e-postalarında sahibine gösterilir, saklanmaz
      const h = new Headers(req.headers);
      const cf = req.cf || {};
      h.set("x-konum", [cf.city, cf.country].filter(Boolean).join(", ").slice(0, 60));
      return env.ACCOUNTS.get(env.ACCOUNTS.idFromName("hepsi")).fetch(new Request(req, { headers: h }));
    }
    // Hızlı Oyun: açık bir oda kodu al
    if (url.pathname === "/hizli") {
      // hesap anahtarı başlıkta gelir (adres çubuğunda değil): engel ilişkisi olan oyuncularla aynı odaya düşmesin
      const hesap = (req.headers.get("x-hesap") || "").slice(0, 80);
      const ip = (req.headers.get("cf-connecting-ip") || "").slice(0, 64); // istek yağmuruna karşı (yerelde boş)
      // misafir Hızlı Oyun'a giremez: anahtar şifreli bir hesabın olmalı
      if (!(await hesapVarMi(env, hesap))) return Response.json({ kod: "", ...tx("Oynamak için hesap aç ya da giriş yap.") }, { status: 403 });
      return env.ESLESTIRME.get(env.ESLESTIRME.idFromName("hepsi")).fetch(new Request("https://ic/hizli", { method: "POST", body: JSON.stringify({ hesap, ip }) }));
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
    // e-postadaki bağlantılar: e-posta doğrulama ve şifre sıfırlama (eposta_web.js; işi Accounts.webKod yapar)
    if (url.pathname === "/eposta-dogrula" || url.pathname === "/sifre-sifirla") {
      const tur = url.pathname === "/eposta-dogrula" ? "dogrula" : "sifirla";
      const html = { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "x-frame-options": "DENY", "referrer-policy": "no-referrer" };
      if (req.method !== "POST") return new Response(kodFormHtml(tur, url.searchParams.get("h"), url.searchParams.get("k"), webDili(req, url)), { headers: html });
      let dil = "tr";
      let kod = "hata";
      try {
        const body = await req.clone().formData();
        dil = body.get("dil") === "en" ? "en" : "tr";
        const h = new Headers(req.headers);
        const cf = req.cf || {};
        h.set("x-konum", [cf.city, cf.country].filter(Boolean).join(", ").slice(0, 60));
        const r = await env.ACCOUNTS.get(env.ACCOUNTS.idFromName("hepsi")).fetch(new Request("https://ic" + url.pathname, { method: "POST", headers: h, body: await req.arrayBuffer() }));
        kod = (await r.json()).kod || "hata";
      } catch (e) {
        console.log("e-posta bağlantısı hatası", e && e.message);
      }
      return new Response(kodSonucHtml(tur, kod, dil), { status: kod === "tamam" || kod === "zaten" ? 200 : kod === "cok_deneme" ? 429 : 400, headers: html });
    }
    // ODALAR ekranı: "Herkes" odalarının listesi (gövde: {ark: [arkadaşların oda kodları]} — onlar üstte)
    if (url.pathname === "/odalar" && env.ODALAR) {
      let ark = [];
      if (req.method === "POST") {
        try {
          const b = await req.json();
          if (Array.isArray(b && b.ark)) ark = b.ark.slice(0, 50);
        } catch {}
      }
      const ip = (req.headers.get("cf-connecting-ip") || "").slice(0, 64);
      const r = await env.ODALAR.get(env.ODALAR.idFromName("hepsi")).fetch(new Request("https://ic/liste", { method: "POST", body: JSON.stringify({ ark, ip }) }));
      return new Response(r.body, { status: r.status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
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
      this.msBitis = (await state.storage.get("msBitis")) || 0; // maç sonu ekranındakilerin en geç lobiye döneceği an (0: yok)
      this.alarmHata = (await state.storage.get("alarmHata")) || 0; // üst üste hata veren alarm sayısı (bekçi)
      this.atilan = (await state.storage.get("atilan")) || []; // başka cihaz yerini aldığı için düşürülen eski geri dönme anahtarları
      // odadaki insanların kaydı (geri dönme anahtarı -> bilgi): sunucu yeniden başlarsa (güncelleme, taşınma) bağlantılar
      // "kapandı" haberi gelmeden düşer; bu kayıtla oyuncular aynı yere geri dönebilir (yetimler)
      this.kadro = (await state.storage.get("kadro")) || {};
      this.ayar = (await state.storage.get("ayar")) || null; // kurulan odanın ayarı (odalar.js): görünürlük, kişi sınırı, ad, botla doldur
    });
    this.kovalar = new WeakMap(); // bağlantı -> mesaj jeton kovaları (spam sınırı)
    this.sahipler = new WeakMap(); // bağlantı -> { set: sahip olunan eşyalar ("kategori:kimlik"), t } (Accounts /ic/sahip)
  }

  async saveKopuk() {
    // boş oda temizlendiyse depoya yeniden yazılmaz
    if (!Object.keys(this.kopuk).length && this.sockets().length === 0) await this.state.storage.delete("kopuk");
    else await this.state.storage.put("kopuk", this.kopuk);
  }

  async kadroYaz(info) {
    if (!info || !info.tekrar) return;
    const { id, name, cell, host, inv, hesap, dil, look, tekrar, sv } = info;
    this.kadro[tekrar] = { id, name, cell, host: !!host, inv: !!inv, hesap: hesap || "", dil, look, tekrar, sv: sv || 1 };
    await this.state.storage.put("kadro", this.kadro);
  }

  async kadroSil(tekrar) {
    if (!tekrar || !this.kadro[tekrar]) return;
    delete this.kadro[tekrar];
    await this.state.storage.put("kadro", this.kadro);
  }

  // Sunucu yeniden başladıysa maçtaki insanların bağlantıları sessizce düşmüş olabilir: bağlı da değil, "kopuk" da değil.
  // Bunlar kopuk sayılır (KOPUK_SURE içinde geri dönebilirler; dönmezlerse maçtan çıkarılırlar).
  async yetimler() {
    const g = this.g;
    if (!g || g.phase === "bitti" || !this.kadro) return;
    const bagli = new Set(this.sockets().map((w) => this.info(w).id));
    const kopukId = new Set(Object.values(this.kopuk).map((k) => k.info.id));
    let n = 0;
    for (const [tok, i] of Object.entries(this.kadro)) {
      if (!g.players.includes(i.id) || bagli.has(i.id) || kopukId.has(i.id) || this.isBot(i.id)) continue;
      this.kopuk[tok] = { info: { ...i, call: 0, calling: 0, ringFrom: 0 }, until: Date.now() + KOPUK_SURE };
      kopukId.add(i.id);
      n++;
    }
    if (n) {
      console.log("bağlantısı sessizce düşen oyuncular kopuk sayıldı (sunucu yeniden başlamış):", n);
      await this.saveKopuk();
    }
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
  // finish: oyun hemen biter; advance: sıradaki aşamaya geçilir; kisalt: herkes oyunu verdi, kalan süre en çok
  // KISALT_SN'ye iner (fikrini değiştirmek isteyen için kısa bir pay).
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
    else if (r.kisalt) await this.kisalt();
    else await this.rearm();
  }

  // Herkes oy verdi / eşleştirmeyi kaydetti: aşamanın kalanı 15 sn'den uzunsa 15 sn'ye iner, herkese duyurulur.
  async kisalt() {
    const g = this.g;
    const son = Date.now() + KISALT_SN * 1000;
    if ((g.ends || 0) > son + 500) {
      g.ends = son;
      this.broadcast(this.gameState());
      this.broadcast({ t: "bilgi", ...tx("Herkes seçti. Son {0} sn.", KISALT_SN), kisaldi: true });
    }
    await this.rearm();
  }

  // Oyunun alarmı olmadan kalmasın: boş sonuç (ör. onWake null döndü) da alarmı yeniden kurar
  async deliverOrRearm(r, ws) {
    if (r) await this.deliver(r, ws);
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
    const nx = g.players.length >= 2 ? Game.siradaki(g) : null;
    const extra = { sonraki: nx ? nx.title : "", sonuc_sure: Game.duration(g, "sonuc") };
    // son oyunsa (kalan oyunlar oyuncu azaldığı için atlanacaksa da) telefon sonucu bitiş ekranına bıraksın
    const rounds = nx ? g.rounds : g.round;
    for (const ws of this.sockets()) {
      const id = this.info(ws).id;
      let ben = res.private[id] || null;
      if (ben) {
        ben = { ...ben };
        delete ben.delta;
        delete ben.score;
      }
      this.send(ws, { t: "sonuc", round: g.round, rounds, task: g.task, title: Game.mode(g).title, ...res.public, ben, ...extra });
    }
    if (Game.checkEnd(g)) {
      await this.state.storage.deleteAlarm();
      await this.macBitti(g, null);
    } else {
      await this.schedule("sonuc");
      const next = Game.siradaki(g);
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
      await odaNabiz(this); // "Herkes" odası: ODALAR listesindeki kayıt tazelenir
    } catch {}
    try {
      await this.alarmStep();
      if (this.alarmHata) {
        this.alarmHata = 0;
        await this.state.storage.delete("alarmHata");
      }
    } catch (e) {
      console.log("alarm hatası", e && e.stack ? e.stack : e);
      // BEKÇİ: hata üst üste sürerse maç takılı kalmasın (önce yeniden dene, sonra mini oyunu atla, sonra maçı bitir)
      const n = ((await this.state.storage.get("alarmHata")) || 0) + 1;
      this.alarmHata = n;
      await this.state.storage.put("alarmHata", n);
      try {
        await this.kurtar(n);
      } catch (e2) {
        console.log("bekçi kurtaramadı", e2 && e2.stack ? e2.stack : e2);
      }
      // alarm zinciri hiç kopmasın
      try {
        if ((await this.state.storage.getAlarm()) === null) await this.state.storage.setAlarm(Date.now() + 2000);
      } catch {}
    }
  }

  // Bekçi: alarm n kez üst üste hata verdi. BEKCI_ATLA: bu mini oyun iptal, sıradakine geçilir.
  // BEKCI_BITIR: maç bitirilir (puan tablosu açılır). Maç bittiyse ve sorun sürüyorsa oda lobiye döner.
  async kurtar(n) {
    if (n < BEKCI_ATLA) return;
    const g = await this.loadGame();
    if (!g || g.phase === "bitti") {
      if (n >= BEKCI_ATLA) {
        console.log("bekçi: maç sonu takıldı, oda lobiye alınıyor");
        this.g = null;
        await this.state.storage.delete("game");
        await this.state.storage.put("started", false);
        this.started = false;
        this.msBitis = 0;
        await this.state.storage.put("msBitis", 0);
        this.herkesLobiye();
        await this.state.storage.delete("alarmHata");
        this.alarmHata = 0;
      }
      return;
    }
    if (n < BEKCI_BITIR && g.phase !== "sonuc" && g.phase !== "baslangic") {
      console.log("bekçi: mini oyun atlanıyor", g.task, g.phase);
      if (g.m) g.m.wake = 0;
      g.phase = "sonuc";
      await this.schedule("sonuc");
      const next = Game.siradaki(g);
      this.broadcast({ ...this.gameState(), sonraki: next ? next.title : "" });
      await this.saveGame();
      return;
    }
    if (n >= BEKCI_BITIR) {
      console.log("bekçi: maç bitiriliyor", g.task, g.phase);
      g.gi = g.games.length; // sıradaki oyun kalmadı
      if (g.m) g.m.wake = 0;
      Game.checkEnd(g);
      await this.state.storage.deleteAlarm();
      await this.saveGame();
      await this.state.storage.delete("alarmHata");
      this.alarmHata = 0;
      await this.macBitti(g, null);
    }
  }

  // Bekçi (mesaj geldikçe en çok 5 sn'de bir): maç sürüyorsa alarmı olmalı; yoksa ya da çoktan geçmişse yeniden kurulur.
  async bekci() {
    const now = Date.now();
    if (now - (this.bekciT || 0) < 5000) return;
    this.bekciT = now;
    const g = await this.loadGame();
    const al = await this.state.storage.getAlarm();
    if (g && g.phase !== "bitti") {
      if (al === null || al < now - 15000) {
        // (alarm tam o an çalmak üzereyken de boş görünür: yeniden kurmak zararsız, her aşama zamanını kendi denetler)
        if (al !== null || now - (g.ends || now) > 5000 || (g.ends || 0) > now + 1000) console.log("bekçi: maçın alarmı yoktu, yeniden kuruldu", g.task, g.phase);
        await this.rearm();
      }
    } else if (al === null && (this.msBitis || (!g && this.acik && this.lobbyAt))) {
      await this.lobiAlarm();
    }
  }

  async alarmStep() {
    let g = await this.loadGame();
    // maç sonu ekranının süresi doldu: oda lobiye döner, ekranda kalanlar da lobiye alınır
    if (this.msBitis && Date.now() >= this.msBitis - 50) {
      await this.msZaman();
      g = this.g;
    }
    // Hızlı Oyun salonu: süresi dolan HAZIR demeyenler kendiliğinden hazır (geri sayım bundan sonra başlar)
    if (!g && this.acik && this.otoHazir()) await this.publicLobby();
    if (!g && this.acik && this.lobbyAt && Date.now() >= this.lobbyAt - 50) return this.publicStart();
    // maç yokken odada kimse kalmadıysa (bağlı da, geri dönecek de yok) depo silinir
    if ((!g || g.phase === "bitti") && this.sockets().length === 0 && Object.keys(this.kopuk).length === 0) return this.temizle();
    if (!g || g.phase === "bitti") return this.lobiAlarm();
    await this.yetimler();
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
      // leaveInfo alarmı kendisi kurdu (oyun iptal olduysa "sonuc" ekranı da gösterilmeli: hemen sıradakine atlanmasın)
      if (this.g && this.g.phase !== "bitti") await this.saveGame();
      return;
    }
    if ((g.phase === "baslangic" || g.phase === "sonuc") && now < (g.ends || 0) - 50) {
      // erken uyanış (ör. geri dönen oyuncunun eski "kopuk süresi" alarmı): sonuç ekranı kısalmasın
      await this.rearm();
    } else if (g.phase === "baslangic" || g.phase === "sonuc") {
      // oynanacak oyun kalmadıysa (son oyun iptal oldu, sonuç ekranında biri çıktı) maç burada biter
      if (Game.checkEnd(g) || !Game.startNext(g)) {
        if (g.phase !== "bitti") {
          g.gi = g.games.length;
          Game.checkEnd(g);
        }
        await this.state.storage.deleteAlarm();
        await this.macBitti(g, null);
        await this.saveGame();
        return;
      }
      await this.schedule(g.phase);
      const hook = Game.onPhase(g, g.phase);
      this.broadcast(this.gameState());
      this.sendSecrets();
      if (hook) await this.deliver(hook, null);
    } else if (g.m && g.m.wake && now >= g.m.wake - 50) {
      g.m.wake = 0;
      await this.deliverOrRearm(Game.onWake(g), null);
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
      const { id, name, cell, host, look, ready, inv, ms, mik, sv } = this.info(ws);
      // ms: maç sonu ekranında (henüz lobiye dönmedi); mk: mikrofonunu kapattı (baş üstünde çizik mikrofon); sv: oyun sürümü
      return { id, name, cell, host, g: look || {}, r: !!ready, inv: !!inv, sv: sv || 1, ...(ms ? { ms: true } : {}), ...(mik ? { mk: true } : {}) };
    });
    for (const b of this.bots) list.push({ id: b.id, name: b.name, cell: b.cell, host: false, g: b.look || {}, r: true, inv: true, bot: true, sv: 99 });
    // bağlantısı kopmuş ama geri dönebilecek oyuncular listede kalır (yerleri ayrılmış)
    for (const k of Object.values(this.kopuk)) {
      const i = k.info;
      list.push({ id: i.id, name: i.name, cell: i.cell, host: !!i.host, g: i.look || {}, r: true, inv: !!i.inv, kopuk: true, sv: i.sv || 1, ...(i.mik ? { mk: true } : {}) });
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

  // Maç bitti: bağlı herkes maç sonu ekranına geçer (ms), puan tablosu gider, ödül bir kez işlenir.
  // Oda "bitti" durumunda bekler; ilk "tekrar" diyen (ya da süre dolunca) oda lobiye döner (lobiyeDon).
  async macBitti(g, except) {
    const sure = Math.max(20000, Math.round(MAC_SONU_SURE * (g.speed || 1)));
    this.msBitis = Date.now() + sure;
    await this.state.storage.put("msBitis", this.msBitis);
    for (const ws of this.sockets(except)) {
      const i = this.info(ws);
      i.ms = true;
      i.ready = false;
      this.setInfo(ws, i);
    }
    this.broadcast({ t: "oyuncular", players: this.players(except) }, except);
    this.broadcast({ ...this.overMsg(g), donus: Math.round(sure / 1000) }, except);
    await this.reportMatch(g);
    await this.lobiAlarm();
  }

  // Oda bekleme salonuna döner: oyun durumu silinir, hazır bayrakları ve telefon hatları temizlenir,
  // kod ve oda sahibi aynı kalır; özel odada bot ayarı korunur. Hızlı Oyun odası botlarını bırakır,
  // yeniden eşleştirmeye açılır, süre dolunca eksikler yine botla dolar. Oda "bitti" değilse bir şey yapmaz.
  async lobiyeDon() {
    const g = await this.loadGame();
    if (!g || g.phase !== "bitti") return false;
    this.g = null;
    await this.state.storage.delete("game");
    await this.state.storage.put("started", false);
    this.started = false;
    this.pos = {};
    this.doors = {};
    this._hatKeys = {};
    if (this.acik) {
      this.bots = [];
      await this.saveBots();
      this.lobbyAt = Math.max(Date.now() + PUBLIC_WAIT, (this.msBitis || 0) + 2000);
      await this.state.storage.put("lobbyAt", this.lobbyAt);
    }
    // maçta bağlantısı kopup geri dönmeyenler artık odadan çıkmış sayılır
    const kopanlar = Object.values(this.kopuk);
    this.kopuk = {};
    await this.saveKopuk();
    for (const k of kopanlar) await this.leaveInfo(k.info, null);
    for (const ws of this.sockets()) {
      const i = this.info(ws);
      i.ready = false;
      if (this.acik && !i.ms) i.hazirSon = Date.now() + OTO_HAZIR; // (maç sonundakiler salona dönünce)
      i.call = i.calling = i.ringFrom = 0;
      i.gizli = i.gizliSon = 0;
      this.setInfo(ws, i);
    }
    this.broadcast({ t: "oyuncular", players: this.players() });
    if (this.acik) await this.publicLobby();
    await odaBildir(this); // ODALAR listesinde yeniden "Lobide"
    await this.lobiAlarm();
    return true;
  }

  // Lobiye dönen oyuncuya: kimliği, hücresi, oda sahipliği ve güncel liste
  lobiMsg(i) {
    return { t: "lobi", id: i.id, cell: i.cell, host: !!i.host, code: this.code, players: this.players() };
  }

  // Maç sonu ekranında kalanların hepsi lobiye alınır (süre doldu ya da yeni maç başlıyor)
  herkesLobiye() {
    const donen = [];
    for (const ws of this.sockets()) {
      const i = this.info(ws);
      if (!i.ms) continue;
      i.ms = false;
      if (this.acik) i.hazirSon = Date.now() + OTO_HAZIR;
      this.setInfo(ws, i);
      donen.push(ws);
    }
    for (const ws of donen) this.send(ws, this.lobiMsg(this.info(ws)));
    if (donen.length) this.broadcast({ t: "oyuncular", players: this.players() });
  }

  async msZaman() {
    this.msBitis = 0;
    await this.state.storage.put("msBitis", 0);
    await this.lobiyeDon();
    this.herkesLobiye();
    if (this.acik && !this.g) await this.publicLobby(); // salona alınanların hazır süresi işlesin
  }

  // Oyun yokken alarm: maç sonu süresi ve Hızlı Oyun başlama zamanı, hangisi önceyse. Hızlı Oyun'da HAZIR
  // demeyen varken başlama zamanı yerine ilk kendiliğinden hazır olma anı kurulur (başlama ondan sonra hesaplanır).
  async lobiAlarm() {
    const t = [];
    if (this.msBitis) t.push(this.msBitis);
    if (this.acik && this.lobbyAt && !this.g && (await this.state.storage.get("started")) !== true) {
      if (this.hazirOlmayanlar().length === 0) t.push(this.lobbyAt);
      else {
        const son = this.hazirSonlar();
        if (son.length) t.push(Math.min(...son));
      }
    }
    if (!this.g) {
      const nabiz = nabizZamani(this); // "Herkes" odası: liste kaydı süresi dolmadan tazelensin
      if (nabiz) t.push(nabiz);
    }
    if (t.length) await this.state.storage.setAlarm(Math.min(...t));
  }

  // Salonda HAZIR olmayan insanlar (maç sonu ekranındakiler de henüz hazır değil). Botlar hep hazır.
  hazirOlmayanlar(except) {
    return this.sockets(except).map((w) => this.info(w)).filter((i) => !i.ready || i.ms);
  }

  // Hızlı Oyun: HAZIR demeyenlerin kendiliğinden hazır sayılacağı anlar
  hazirSonlar() {
    return this.hazirOlmayanlar().filter((i) => !i.ms && i.hazirSon).map((i) => i.hazirSon);
  }

  // Hızlı Oyun salonu: süresi dolan HAZIR demeyenler hazır sayılır (oda sonsuza dek beklemesin).
  // Değişen olduysa yeni liste herkese gider ve true döner.
  otoHazir() {
    if (!this.acik || this.g) return false;
    const now = Date.now();
    let degisti = false;
    for (const ws of this.sockets()) {
      const i = this.info(ws);
      if (i.ready || i.ms || !i.hazirSon || now < i.hazirSon - 50) continue;
      i.ready = true;
      this.setInfo(ws, i);
      degisti = true;
    }
    if (degisti) this.broadcast({ t: "oyuncular", players: this.players() });
    return degisti;
  }

  // Maç sonucu hesaplara işlensin (sadece maçı bitiren, hesabı bilinen gerçek oyuncular)
  async reportMatch(g) {
    if (!this.env || !this.env.ACCOUNTS || g.reported) return;
    g.reported = true;
    const log = g.log || [];
    if (!log.length) return; // hiç oyun bitmeden biten maç ödül vermez
    const tokens = {};
    for (const ws of this.sockets()) {
      const i = this.info(ws);
      if (i.hesap) tokens[i.id] = i.hesap;
    }
    for (const k of Object.values(this.kopuk)) if (k.info.hesap) tokens[k.info.id] = k.info.hesap;
    const table = Game.table(g).filter((r) => !r.left);
    const oyuncular = [];
    const verilen = new Set(); // aynı hesap maçta iki kez görünse de (iki cihaz) ödül bir kez, en iyi sırasıyla
    table.forEach((r, i) => {
      const t = tokens[r.id];
      if (!t || verilen.has(t)) return;
      verilen.add(t);
      const oyunlar = {};
      for (const e of log) oyunlar[e.task] = (oyunlar[e.task] || 0) + (e.d[r.id] || 0);
      oyuncular.push({ token: t, sira: i + 1, oyuncu_sayisi: table.length, puan: r.score, oyunlar, oyun_sayisi: log.length });
    });
    // botlarla ödül çiftliği olmasın: maçı bitiren farklı insan hesabı 2'den azsa hiç ödül yok (XP, elmas, görev, istatistik)
    if (oyuncular.length < 2) return;
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

  // `alici`nın telefonunda `id` nasıl görünür: Kim Kim?'de seni arayan kişi "****" (GIZLI; ne adı ne hattı),
  // aradığın kişi "Hat N" (takma numara), diğer zamanlarda gerçek numara.
  gorunen(alici, id) {
    if (this.anon() && alici && alici.gizli && alici.gizli === id) return Game.MODES.kimkim.GIZLI;
    return this.alias(id);
  }

  // İstemcinin yolladığı numarayı gerçek numaraya çevirir (GIZLI: bu kişiyi son arayan)
  unaliasFor(me, x) {
    if (Number(x) === Game.MODES.kimkim.GIZLI) return Number((me && (me.gizli || me.gizliSon)) || 0);
    return this.unalias(x);
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
    // Projektör Avı'nda yakalanan konuşamaz (izleyici): sesi kimseye gitmez
    if (g && g.task === "projektor" && g.m && Array.isArray(g.m.dead) && g.m.dead.includes(a)) return false;
    const pa = this.pos && this.pos[a];
    const pb = this.pos && this.pos[b];
    if (!pa || !pb || Math.hypot(pa[0] - pb[0], pa[1] - pb[1]) > 14) return false;
    if (g && g.task === "kacis") return true; // kaçışta hücreler ve tüneller arası: yalnız mesafe
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
    if (this.code !== code) {
      this.code = code;
      await this.state.storage.put("code", code);
    }
    const yerel = YEREL.has(url.hostname); // test hızı (hiz) yalnız yerel sunucuda geçerli
    let name = temizAd(url.searchParams.get("ad")) || "Oyuncu";
    let adRed = !adUygun(name); // uygunsuz ad odada "Oyuncu N" olur, oyuncuya kısa bilgi gider
    if (adRed) name = "Oyuncu";
    const create = url.searchParams.get("kur") === "1";
    const invited = url.searchParams.get("davet") === "1";
    const rejoin = (url.searchParams.get("tekrar") || "").slice(0, 64);
    const hesap = (url.searchParams.get("hesap") || "").slice(0, 80); // hesap anahtarı: maç ödülü için (kimseye gösterilmez)
    const publicJoin = url.searchParams.get("acik") === "1"; // Hızlı Oyun ile gelen
    const listeden = url.searchParams.get("liste") === "1"; // ODALAR listesinden katılan (yalnız lobideki "Herkes" odasına)
    const dil = odaDili(url.searchParams.get("dil")); // oyuncunun dili; odanın dili = kurucunun dili (kelime havuzları)
    // istemcinin oyun sürümü (sv): yeni mini oyunlar yalnız herkesin sürümü destekliyorsa seçilir (eski sürüm "1")
    const sv = Math.max(1, Math.min(99, Math.floor(Number(url.searchParams.get("sv")) || 1)));

    // Dış istek (hesap sunucusu) EN BAŞTA: bu bekleme sırasında başka oyuncular da girebilir. Oda durumu
    // (kim var, numara, hücre) bundan SONRA, araya dış istek girmeden okunur; iki kişi aynı anda girse de
    // aynı numarayı/hücreyi alamaz, oda 8 kişiyi aşmaz.
    const durum = await this.hesapDurumu(hesap);
    // misafir (hesapsız) odaya giremez; hesaplı oyuncunun adı her zaman kullanıcı adıdır (istemcinin yolladığı ada güvenilmez)
    if (!durum.hesap) {
      const [client, server] = Object.values(new WebSocketPair());
      this.state.acceptWebSocket(server);
      server.send(JSON.stringify({ t: "hata", ...tx("Oynamak için hesap aç ya da giriş yap."), hesap_yok: true }));
      setTimeout(() => {
        try {
          server.close(4000, "hata");
        } catch {}
      }, 400);
      return new Response(null, { status: 101, webSocket: client });
    }
    if (durum.ad && temizAd(durum.ad)) {
      name = temizAd(durum.ad);
      adRed = false;
    }
    await this.loadGame();
    await this.yetimler(); // sunucu yeniden başladıysa geri dönenler yerini bulsun

    // Aynı oyuncu zaten bağlı görünüyor (aynı geri dönme anahtarı: telefonun eski bağlantısı yarım kaldı;
    // ya da aynı hesap ikinci bir cihazdan/sekmeden geldi): yeni bağlantı eskisinin yerini alır, eskisi kapanır.
    const eski = this.sockets().find((w) => {
      const i = this.info(w);
      return (rejoin && i.tekrar === rejoin) || (hesap && i.hesap === hesap);
    });
    // yeri başka cihaza geçmiş eski cihaz kendiliğinden yeniden bağlanmaya çalışıyor: geri alamaz (iki cihaz birbirini atıp durmasın)
    if (rejoin && this.atilan.includes(rejoin)) {
      const [client, server] = Object.values(new WebSocketPair());
      this.state.acceptWebSocket(server);
      server.send(JSON.stringify({ t: "hata", m: "Bu hesapla başka bir cihazdan odaya girildi." }));
      server.close(4001, "devralindi");
      return new Response(null, { status: 101, webSocket: client });
    }
    if (eski && !durum.yasak) return this.devral(eski, rejoin, yerel);

    // kopan oyuncu geri dönüyor: aynı kimlik, hücre ve oyun durumu (anahtarı kaybettiyse aynı hesapla da bulunur)
    // (askıya alınan oyuncu geri dönme anahtarıyla da maça dönemez: aşağıda normal girişte yasak mesajını alır)
    let slotKey = !durum.yasak && rejoin && this.kopuk[rejoin] ? rejoin : "";
    if (!slotKey && hesap && !durum.yasak) slotKey = Object.keys(this.kopuk).find((k) => this.kopuk[k].info.hesap === hesap) || "";
    const slot = slotKey ? this.kopuk[slotKey] : null;
    if (slot && slot.until > Date.now()) {
      const [client, server] = Object.values(new WebSocketPair());
      this.state.acceptWebSocket(server);
      const info = { ...slot.info, call: 0, calling: 0, ringFrom: 0, yerel };
      if (this.g && this.g.phase === "bitti") info.ms = true; // maç bu arada bitti: maç sonu ekranına döner
      delete this.kopuk[slotKey];
      this.setInfo(server, info);
      await this.saveKopuk();
      this.send(server, { t: "hosgeldin", id: info.id, cell: info.cell, host: !!info.host, code, started: true, players: this.players(), tekrar: info.tekrar, geri: true });
      this.broadcast({ t: "oyuncular", players: this.players() }, server);
      // bag: bağlantı bildirimi (istemci ikonlu, renkli gösterir); Kim Kim? sürerken ad yerine "****"
      this.broadcast({ t: "bilgi", ...tx("{0} geri bağlandı.", this.anon() ? "****" : info.name), bag: "geri", id: info.id }, server);
      return new Response(null, { status: 101, webSocket: client });
    }
    // maç bitmiş odaya yeni gelen: oda lobiye döner (maç sonu ekranındakiler orada kalır)
    await this.lobiyeDon();
    // (lobiyeDon dış istek yapabilir: oda durumu buradan sonra okunur)
    if (this.sockets().length === 0 && Object.keys(this.kopuk).length === 0 && this.bots.length && !(this.g && this.g.phase !== "bitti")) {
      // bağlı insan kalmadıysa eski botlar da gitmiş sayılır (maç sürüyorsa değil)
      this.bots = [];
      await this.saveBots();
    }
    const started0 = (await this.state.storage.get("started")) === true;

    // ---- buradan yeni oyuncunun kaydına kadar dış istek YOK (yalnız depo; araya başka giriş girmez) ----
    const existing = this.players();
    const [client, server] = Object.values(new WebSocketPair());
    this.state.acceptWebSocket(server);

    let error = "";
    // açık odaya ilk gelen odayı kurar; başlamış açık odaya girilmez
    const createNow = create || (publicJoin && existing.length === 0);
    if (publicJoin && existing.length > 0 && (!this.acik || started0)) error = "Bu oda doldu, yeniden aranıyor…";
    else if (create && existing.length > 0) error = "Bu oda kodu kullanımda, tekrar dene.";
    else if (!createNow && existing.length === 0) error = "Bu kodla bir oda bulunamadı.";
    else if (listeden && !createNow && (!this.ayar || this.ayar.gor !== "herkes" || this.acik)) error = "Bu oda artık listede değil.";
    else if (listeden && !createNow && started0 && this.g && this.g.phase !== "bitti") error = "Bu odada maç başladı.";
    else if (existing.length >= (createNow ? MAX_PLAYERS : kisiSiniri(this))) error = "Oda dolu.";
    // hesap durumu: askıdaki hesap odaya giremez; engellediği oyuncuların anahtarları (ses onlara/onlardan gitmez)
    let hataK = null;
    if (error === "Oda dolu.") {
      const t = tx("Oda dolu (en fazla {0} kişi).", kisiSiniri(this));
      error = t.m;
      hataK = t.m_k;
    }
    if (!error && durum.yasak) {
      error = durum.yasak.m;
      hataK = durum.yasak.m_k;
    }
    if (error) {
      server.send(JSON.stringify({ t: "hata", m: error, ...(hataK ? { m_k: hataK } : {}) }));
      // hemen kapatılırsa telefon (Godot) mesajı okuyamadan bağlantıyı kapalı görür ("Oda dolu" yerine genel hata);
      // mesaj ulaşsın diye biraz sonra kapatılır (bu bağlantının eki boş: oyuncu sayılmaz, mesajları işlenmez)
      setTimeout(() => {
        try {
          server.close(4000, "hata");
        } catch {}
      }, 400);
      return new Response(null, { status: 101, webSocket: client });
    }

    const usedCells = new Set(existing.map((p) => p.cell));
    const usedIds = new Set(existing.map((p) => p.id));
    // maç sürüyorsa maçtan ayrılmış olanların numarası ve hücresi de dolu sayılır (puan tablosu, hücre karışmasın)
    if (this.g && this.g.phase !== "bitti") {
      for (const x of Object.keys(this.g.score || {})) usedIds.add(Number(x));
      for (const c of Object.values(this.g.cells || {})) usedCells.add(c);
    }
    let cell = 0;
    while (usedCells.has(cell)) cell++;
    let id = 1;
    while (usedIds.has(id)) id++;
    const tekrar = crypto.randomUUID(); // bağlantı koparsa aynı oyuncu olarak geri dönme anahtarı
    if (adRed) name = "Oyuncu " + id;
    const info = { id, name, cell, host: existing.length === 0, call: 0, calling: 0, ringFrom: 0, inv: invited, tekrar, hesap, dil, yerel, sv, ...(durum.ad ? { hesapAd: true } : {}) };
    if (this._hatKeys) delete this._hatKeys[id]; // aynı numarayla önce çıkan birinin kaydı yeni gelene kalmasın
    if (this.pos) delete this.pos[id];
    this.setInfo(server, info); // artık sayılıyor: sonraki giriş bu numarayı/hücreyi görür
    if (createNow) this.kadro = {};

    if (createNow) {
      this.acik = publicJoin;
      this.lobbyAt = 0;
      this.msBitis = 0;
      this.bots = [];
      this.kopuk = {};
      this.started = false;
      this.g = null;
      this.alarmHata = 0;
      this.pos = {};
      this.doors = {};
      this._hatKeys = {};
      this.atilan = [];
      await this.state.storage.put({ msBitis: 0, acik: this.acik, lobbyAt: 0, bots: [], kopuk: {}, started: false });
      await this.state.storage.delete(["game", "alarmHata", "atilan"]);
      await this.state.storage.deleteAlarm();
      // oda ayarı (ODA KUR penceresi): Hızlı Oyun odasında yok
      this.ayar = null;
      this._odaKayitli = false;
      this._odaAnahtar = "";
      if (!publicJoin) {
        const { ayar, adRed: odaAdRed } = odaAyari(url.searchParams);
        this.ayar = ayar;
        if (odaAdRed) info.odaAdRed = true;
      }
      if (this.ayar) await this.state.storage.put("ayar", this.ayar);
      else await this.state.storage.delete("ayar");
    }
    if (this.acik) {
      info.hazirSon = Date.now() + OTO_HAZIR; // Hızlı Oyun: HAZIR demezse bu süre sonunda hazır sayılır
      this.setInfo(server, info);
    }
    await this.engelYaz(hesap, durum.engel);
    await this.kadroYaz(info);

    const started = (await this.state.storage.get("started")) === true;
    this.send(server, { t: "hosgeldin", id, cell, host: info.host, code, started, players: this.players(), tekrar });
    if (adRed) this.send(server, { t: "bilgi", m: AD_RED, ad_red: true });
    if (this.ayar) this.send(server, ayarMsg(this));
    if (info.odaAdRed) this.send(server, { t: "bilgi", m: "Bu oda adı kullanılamaz." });
    this.broadcast({ t: "oyuncular", players: this.players() }, server);
    if (!started) this.broadcast({ t: "bilgi", ...tx("{0} odaya katıldı.", name), bag: "katildi", id }, server);
    if (this.acik && !started) await this.publicLobby();
    await odaBildir(this); // "Herkes" odası: ODALAR listesindeki kayıt (kişi sayısı)
    return new Response(null, { status: 101, webSocket: client });
  }

  // Aynı oyuncu yeniden bağlandı (eski bağlantısı hâlâ açık görünüyor) ya da aynı hesap ikinci cihazdan geldi:
  // yeni bağlantı eskisinin numarasını, hücresini, sahipliğini ve maçtaki yerini alır; eskisine kısa bilgi gider, kapanır.
  async devral(eski, rejoin, yerel) {
    this.endCall(eski); // telefondaysa karşı taraf "kapandı" görür
    const info = { ...this.info(eski), call: 0, calling: 0, ringFrom: 0, yerel };
    if (!(rejoin && info.tekrar === rejoin)) {
      // başka cihaz: yeni geri dönme anahtarı; eskisinin anahtarı artık geçmez
      this.atilan = [...this.atilan.filter((x) => x !== info.tekrar), info.tekrar].slice(-20);
      await this.state.storage.put("atilan", this.atilan);
      delete this.kadro[info.tekrar];
      info.tekrar = crypto.randomUUID();
    }
    await this.kadroYaz(info);
    try {
      eski.serializeAttachment({}); // kapanınca "koptu" sayılmasın
    } catch {}
    this.send(eski, { t: "hata", m: "Bu hesapla başka bir cihazdan odaya girildi." });
    // mesaj ulaşsın diye biraz sonra kapatılır (bu arada gelen mesajları sayılmaz: eki boş)
    setTimeout(() => {
      try {
        eski.close(4001, "devralindi");
      } catch {}
    }, 1500);
    const [client, server] = Object.values(new WebSocketPair());
    this.state.acceptWebSocket(server);
    this.setInfo(server, info);
    const g = this.g;
    const started = (await this.state.storage.get("started")) === true;
    // aynı geri dönme anahtarıyla maç sürerken geldiyse geri dönüş (oyun ekranı kalır), değilse normal hoş geldin
    const geri = !!(rejoin && info.tekrar === rejoin && started && g && g.phase !== "bitti");
    this.send(server, { t: "hosgeldin", id: info.id, cell: info.cell, host: !!info.host, code: this.code, started, players: this.players(), tekrar: info.tekrar, ...(geri ? { geri: true } : {}) });
    if (this.ayar) this.send(server, ayarMsg(this));
    this.broadcast({ t: "oyuncular", players: this.players() }, server);
    return new Response(null, { status: 101, webSocket: client });
  }

  // Hesabın sahip olduğu eşyalar (bağlantı başına önbellek). tazele: önbellekte olmayan eşya geldi (az önce satın
  // almış olabilir), SAHIP_TAZE'den eskiyse yeniden çekilir. Dönen: Set ya da null (hesap sunucusuna ulaşılamadı).
  async sahipListesi(ws, hesap, tazele) {
    const c = this.sahipler.get(ws);
    if (c && (!tazele || Date.now() - c.t < SAHIP_TAZE)) return c.set;
    if (!this.env || !this.env.ACCOUNTS) return c ? c.set : null;
    try {
      const r = await this.env.ACCOUNTS.get(this.env.ACCOUNTS.idFromName("hepsi")).fetch(new Request("https://ic/ic/sahip", { method: "POST", body: JSON.stringify({ token: hesap }) }));
      const d = await r.json();
      if (!d || !Array.isArray(d.sahip)) return c ? c.set : null;
      const set = new Set(d.sahip.filter((x) => typeof x === "string"));
      this.sahipler.set(ws, { set, t: Date.now() });
      return set;
    } catch (e) {
      console.log("sahip listesi alınamadı", e && e.message);
      return c ? c.set : null;
    }
  }

  // Görünüşteki paralı eşyalardan hesabın sahip olmadıkları varsayılana çevrilir (istemci ne yollarsa yollasın)
  async sahipliGorunus(ws, hesap, look) {
    const ucretli = Object.keys(VARSAYILAN_GORUNUS).filter((k) => typeof look[k] === "string" && price(k, look[k]) > 0);
    if (!ucretli.length) return look;
    let set = await this.sahipListesi(ws, hesap, false);
    if (set && ucretli.some((k) => !set.has(k + ":" + look[k]))) set = await this.sahipListesi(ws, hesap, true);
    if (!set) return look;
    const out = { ...look };
    for (const k of ucretli) if (!set.has(k + ":" + look[k])) out[k] = VARSAYILAN_GORUNUS[k];
    return out;
  }

  // Accounts'tan oyuncunun durumu: { yasak: {m, m_k} | null, engel: [anahtar] }. Ulaşılamazsa engelsiz devam.
  // hesap: şifreli hesap mı (misafir giremez), ad: kullanıcı adı (oyundaki ad). Ulaşılamazsa anahtarı olan girer (ad istemciden).
  async hesapDurumu(hesap) {
    if (!hesap || hesap.length < 16) return { yasak: null, engel: [], hesap: false, ad: "" };
    if (!this.env || !this.env.ACCOUNTS) return { yasak: null, engel: [], hesap: true, ad: "" };
    try {
      const r = await this.env.ACCOUNTS.get(this.env.ACCOUNTS.idFromName("hepsi")).fetch(new Request("https://ic/ic/oda-giris", { method: "POST", body: JSON.stringify({ token: hesap }) }));
      const d = await r.json();
      return { yasak: d.yasak || null, engel: Array.isArray(d.engel) ? d.engel : [], hesap: !!d.hesap, ad: String(d.ad || "") };
    } catch (e) {
      console.log("hesap durumu alınamadı", e && e.message);
      return { yasak: null, engel: [], hesap: true, ad: "" };
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
    const hedefId = this.unaliasFor(me, d.id); // Kim Kim?'de telefondaki takma numara ya da "****" (gizli arayan)
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
      // Kim Kim? sürerken ad açılmaz (engellenen hattın / gizli arayanın kim olduğu belli olmasın)
      return this.send(ws, { t: "bilgi", ...tx("{0} engellendi. Sesini artık duymazsın.", this.anon() ? "****" : hedef.name), engellendi: d.id });
    }
    return this.send(ws, r.ok ? { t: "bilgi", m: "Şikayetin alındı. Teşekkürler." } : { t: "hata", m: r.m || "Şikayet gönderilemedi.", ...(r.m_k ? { m_k: r.m_k } : {}) });
  }

  // Açık oda bekleme salonu: kişi sayısını eşleştiriciye bildir, otomatik başlama zamanını kur.
  async publicLobby() {
    const humans = this.sockets().length;
    try {
      await this.env.ESLESTIRME.get(this.env.ESLESTIRME.idFromName("hepsi")).fetch(new Request("https://ic/durum", { method: "POST", body: JSON.stringify({ kod: this.code, n: humans, started: false, hesaplar: this.sockets().map((w) => this.info(w).hesap).filter(Boolean) }) }));
    } catch {}
    // (dış istek sırasında herkes çıkmış olabilir: boşalmış odaya yeniden zaman/alarm yazılmasın)
    if (humans === 0 || this.sockets().length === 0) return;
    const now = Date.now();
    let at = this.lobbyAt || now + PUBLIC_WAIT;
    // geri sayım yalnız bütün insanlar HAZIR iken işler; herkes yeni hazır olduysa en az HAZIR_SAYIM sürer
    const eksik = this.hazirOlmayanlar();
    if (eksik.length === 0) {
      if (!this.hazirAn) at = Math.max(at, now + HAZIR_SAYIM);
      this.hazirAn = this.hazirAn || now;
      if (humans >= PUBLIC_MAX) at = Math.min(at, now + 3000);
    } else this.hazirAn = 0;
    this.lobbyAt = at;
    await this.state.storage.put("lobbyAt", at);
    await this.lobiAlarm();
    if (eksik.length === 0) this.broadcast({ t: "acik_oda", baslama: Math.max(0, Math.round((at - now) / 1000)) });
    else {
      // baslama -1: geri sayım durdu, HAZIR demeyenler bekleniyor (bekle: en geç kaç sn sonra kendiliğinden hazır)
      const son = this.hazirSonlar();
      const bekle = son.length ? Math.max(0, Math.round((Math.max(...son) - now) / 1000)) : -1;
      this.broadcast({ t: "acik_oda", baslama: -1, bekle, eksik: eksik.length });
    }
  }

  // Maçı başlatır (kurucunun "basla"sı ya da açık odada süre dolunca).
  async startGame(list, speed, games) {
    // maç sonu ekranında kalan varsa önce lobiye alınır (Hızlı Oyun süresi doldu)
    this.herkesLobiye();
    this.msBitis = 0;
    await this.state.storage.put("msBitis", 0);
    this.lobbyAt = 0; // Hızlı Oyun bekleme süresi bu maç için kullanıldı (maç sonunda yeniden kurulur)
    await this.state.storage.put("lobbyAt", 0);
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
    await odaBildir(this); // ODALAR listesinde "Maçta"
    if (this.acik) {
      try {
        await this.env.ESLESTIRME.get(this.env.ESLESTIRME.idFromName("hepsi")).fetch(new Request("https://ic/durum", { method: "POST", body: JSON.stringify({ kod: this.code, n: 0, started: true }) }));
      } catch {}
    }
  }

  // Açık odada bekleme süresi doldu: en az 4 kişiye tamamlanacak kadar bot ekle ve başlat.
  async publicStart() {
    if (this.sockets().length === 0 && Object.keys(this.kopuk).length === 0) return this.temizle(); // kimse kalmadı
    if (!this.acik || this.sockets().length === 0) return;
    if ((await this.state.storage.get("started")) === true) return;
    if (this.hazirOlmayanlar().length) return this.lobiAlarm(); // HAZIR demeyen var: süresi dolunca hazır sayılır
    this.hazirAn = 0;
    while (this.players().length < PUBLIC_MIN) this.addBot();
    await this.saveBots();
    this.broadcast({ t: "oyuncular", players: this.players() });
    // TEST_HIZ: yalnız yerel yük testinde (wrangler dev --var TEST_HIZ:0.1); canlıda tanımlı değil
    const hiz = Math.min(1, Math.max(0.05, Number(this.env && this.env.TEST_HIZ) || 1));
    await this.startGame(this.players(), hiz, null);
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
    // ad odanın diline göre (kurucunun dili; kurucu yoksa ilk oyuncununki)
    const insanlar = this.sockets().map((ws) => this.info(ws)).filter((i) => i && i.id);
    const kurucu = insanlar.find((i) => i.host) || insanlar[0];
    const name = Bots.botAdi(odaDili(kurucu && kurucu.dil), kadin, names, id);
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

  // Bu bağlantı şu tür mesajı şimdi yollayabilir mi (jeton kovası; aşan mesaj atılır)
  izin(ws, tur) {
    let k = this.kovalar.get(ws);
    if (!k) this.kovalar.set(ws, (k = {}));
    const [hiz, kap] = ORAN[tur];
    const now = Date.now();
    let o = k[tur];
    if (!o) o = k[tur] = { j: kap, t: now };
    o.j = Math.min(kap, o.j + ((now - o.t) / 1000) * hiz);
    o.t = now;
    if (o.j < 1) {
      k.atilan = (k.atilan || 0) + 1;
      if (k.atilan === 1 || k.atilan % 500 === 0) console.log("spam sınırı:", tur, "oyuncu", this.info(ws).id, "atılan", k.atilan);
      // 10 sn içinde SPAM_KES mesaj atıldıysa bağlantı kapatılır (oda kuyruğu tıkanmasın; normal oyun buna hiç yaklaşmaz)
      if (!k.pencere || now - k.pencere > 10000) {
        k.pencere = now;
        k.penAtilan = 0;
      }
      if (++k.penAtilan === SPAM_KES) {
        console.log("spam: bağlantı kapatıldı, oyuncu", this.info(ws).id);
        this.send(ws, { t: "hata", m: "Çok hızlı mesaj gönderildi, bağlantı kesildi." });
        try {
          ws.close(4008, "spam");
        } catch {}
      }
      return false;
    }
    o.j -= 1;
    return true;
  }

  async webSocketMessage(ws, msg) {
    let me = this.info(ws);
    if (!me.id) return;

    // ses: oyun başlamadıysa bekleme salonundaki herkese, başladıysa sadece telefonla konuşulan kişiye
    if (typeof msg !== "string") {
      const bytes = new Uint8Array(msg);
      if (bytes.length === 0 || bytes.length > SES_MAX || !this.izin(ws, "ses")) return;
      if (this.started === undefined) this.started = (await this.state.storage.get("started")) === true;
      // oyun durumu önce yüklenir: Kim Kim? sürerken ilk ses parçası da takma kimlikle gitsin (nesne uykudan yeni uyandıysa)
      if (this.started) await this.loadGame();
      const tagged = new Uint8Array(bytes.length + 1);
      tagged[0] = this.alias(me.id); // Kim Kim?'de ses takma kimlikle gelir
      tagged.set(bytes, 1);
      msg = tagged;
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
          // Kim Kim?: aranan kişiye arayanın sesi "****" numarasıyla gider (hattı da belli olmasın)
          let out = msg;
          const no = this.gorunen(pi, me.id);
          if (no !== msg[0]) {
            out = msg.slice();
            out[0] = no;
          }
          try {
            p.send(out);
          } catch {}
        }
      }
      return;
    }

    if (msg.length > MESAJ_MAX) return;
    let d;
    try {
      d = JSON.parse(msg);
    } catch {
      return;
    }
    if (!d || typeof d !== "object" || typeof d.t !== "string") return;
    if (!this.izin(ws, d.t === "konum" ? "konum" : AGIR.has(d.t) ? "agir" : "genel")) return;
    // oyun durumu bellekte olsun (takma kimlikler, telefon hatları için); bekçi alarmı denetler
    await this.loadGame();
    await this.bekci();
    // "Herkes" odası: liste kaydı tazelenir (en çok ODA_NABIZ'da bir). Beklenmez: dış istek sürerken aynı bağlantının
    // başka mesajı işlenip bilgisi değişebilir, eski bilgi geri yazılmasın
    odaNabiz(this).catch(() => {});
    me = this.info(ws); // (beklerken değişmiş / bağlantı kapanmış olabilir)
    if (!me.id) return;

    switch (d.t) {
      case "basla": {
        // Hızlı Oyun odası kendiliğinden başlar (publicStart): elle başlatılamaz
        if (!me.host || this.acik) break;
        if (await this.loadGame()) break; // maç sürüyor (ya da bitti ama oda henüz lobiye dönmedi)
        const bekleyen = this.sockets().map((w) => this.info(w)).filter((i) => i.ms);
        if (bekleyen.length) {
          this.send(ws, { t: "bilgi", ...tx("{0} henüz maç sonu ekranında.", bekleyen.map((i) => i.name).join(", ")) });
          break;
        }
        const list = this.players();
        if (list.length < 2 && !(this.ayar && this.ayar.botla)) {
          this.send(ws, { t: "bilgi", m: "En az 2 kişi lazım." });
          break;
        }
        // Herkes HAZIR olmalı (botlar hep hazır). Kurucunun BAŞLAT'a basması kendi HAZIR'ı sayılır.
        if (!me.ready) {
          me.ready = true;
          this.setInfo(ws, me);
          this.broadcast({ t: "oyuncular", players: this.players() });
        }
        const eksik = this.hazirOlmayanlar();
        if (eksik.length) {
          this.send(ws, { t: "bilgi", ...tx("Herkes hazır değil: {0}", eksik.map((i) => i.name).join(", ")), hazir_degil: eksik.map((i) => i.id) });
          break;
        }
        // hiz: test için süreleri kısaltır (0.05-1)
        // (yalnız yerel test sunucusunda; canlıda hızlı maçla ödül biriktirilemesin)
        const speed = me.yerel ? Math.min(1, Math.max(0.05, Number(d.hiz) || 1)) : 1;
        // canlıda aynı oyun listede bir kez (tek oyunu tekrar tekrar seçip tam ödüllü kısa maç yapılmasın); yerel testte serbest
        const oyunlar = Array.isArray(d.oyunlar) && !me.yerel ? [...new Set(d.oyunlar)] : d.oyunlar;
        // oda ayarı "Botla doldur": boş yerler (kişi sınırına kadar) başlarken botla dolar
        let kadro = list;
        if (this.ayar && this.ayar.botla && list.length < kisiSiniri(this)) {
          while (this.players().length < kisiSiniri(this)) this.addBot();
          await this.saveBots();
          kadro = this.players();
          this.broadcast({ t: "oyuncular", players: kadro });
        }
        await this.startGame(kadro, speed, oyunlar);
        break;
      }

      case "tekrar": {
        // maç sonu ekranında TEKRAR OYNA: oda lobiye döner (ilk diyende), oyuncu bekleme salonuna geçer
        const g = await this.loadGame();
        if (g && g.phase !== "bitti") break;
        await this.lobiyeDon();
        const cur = this.info(ws);
        if (!cur.id) break;
        cur.ms = false;
        cur.ready = false;
        if (this.acik) cur.hazirSon = Date.now() + OTO_HAZIR; // Hızlı Oyun: HAZIR demezse bu süre sonunda hazır
        this.setInfo(ws, cur);
        this.send(ws, this.lobiMsg(cur));
        this.broadcast({ t: "oyuncular", players: this.players() }, ws);
        if (!this.sockets().some((w) => this.info(w).ms)) {
          this.msBitis = 0; // herkes döndü
          await this.state.storage.put("msBitis", 0);
        }
        await this.lobiAlarm();
        if (this.acik && !this.g) await this.publicLobby();
        break;
      }

      case "karar": {
        const g = await this.loadGame();
        if (!g || g.phase === "bitti" || g.phase === "sonuc" || g.phase === "baslangic") break;
        // C4: bomba sadece yakındaki oyuncuya verilebilir. Konumu bilinmeyen (konum göndermeyen) veremez; hedef insansa
        // onun konumu da bilinmeli (botların konumu yok, onlara mesafe bakılmaz)
        if (g.task === "c4" && d.v && d.v.ver !== undefined) {
          const a = this.pos && this.pos[me.id];
          const b = this.pos && this.pos[Number(d.v.ver)];
          if (!a || (!b && !this.isBot(Number(d.v.ver))) || (b && Math.hypot(a[0] - b[0], a[1] - b[1]) > 3.5)) {
            this.send(ws, { t: "bilgi", m: "Yanına git." });
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
        // kurucu bekleme salonunda bot ekler/çıkarır (test ve az kişiyle oynamak için); Hızlı Oyun'da botları oda kendisi ekler
        if (!me.host || this.acik || (await this.state.storage.get("started")) === true) break;
        if (d.t === "bot_cikar") {
          this.bots.pop();
        } else {
          const all = this.players();
          if (all.length >= kisiSiniri(this)) {
            this.send(ws, { t: "bilgi", ...tx("Oda dolu (en fazla {0} kişi).", kisiSiniri(this)) });
            break;
          }
          this.addBot();
        }
        await this.saveBots();
        this.broadcast({ t: "oyuncular", players: this.players() });
        await odaBildir(this);
        break;
      }

      case "oda_ayar": {
        // oda sahibi lobide oda ayarını değiştirir (görünürlük, kişi sınırı, ad, botla doldur); Hızlı Oyun odasında yok
        if (!me.host || this.acik || !this.ayar || (this.g && this.g.phase !== "bitti")) break;
        const { ayar, adRed: odaAdRed } = odaAyari(d);
        const n = this.players().length;
        if (ayar.max < n) {
          this.send(ws, { t: "bilgi", ...tx("Odada {0} kişi var.", n) });
          ayar.max = Math.max(ayar.max, n);
        }
        if (odaAdRed) {
          this.send(ws, { t: "bilgi", m: "Bu oda adı kullanılamaz." });
          ayar.ad = this.ayar.ad;
        }
        this.ayar = ayar;
        await this.state.storage.put("ayar", ayar);
        this.broadcast(ayarMsg(this));
        await odaBildir(this, null, true);
        break;
      }

      case "konum": {
        // yalnız bilinen alanlar, yuvarlanmış sayılarla gider (bozuk/kötü niyetli mesaj kimsenin oyununu çökertmesin;
        // false olan c/k alanları yollanmaz: istemci yoksa false sayar)
        const p = d.p;
        if (!Array.isArray(p) || p.length < 2 || !sayi(p[0], 500) || !sayi(p[1], 500)) break;
        const k = { t: "konum", id: me.id, p: [yuvarla(p[0]), yuvarla(p[1])], y: sayi(d.y, 100) ? yuvarla(d.y) : 0, o: !!d.o };
        if (d.c && !this.anon()) k.c = true; // telefonda mı: Kim Kim? sürerken gönderilmez (hattın kimliği belli olmasın)
        if (d.k) k.k = true;
        if (sayi(d.h, 20) && d.h < -0.3) k.h = yuvarla(d.h); // yükseklik: yer altı (Büyük Kaçış tünelleri)
        (this.pos ||= {})[me.id] = k.p; // son konum (C4 hile kontrolü, yakınlık sesi)
        // Projektör Avı: ışığa yakalanma sunucuda, insanın her konumunda bakılır; Büyük Kaçış: oyuncunun yeri konumdan
        const pg = this.g;
        const pm = pg && pg.m ? Game.mode(pg) : null;
        if (pm && pm.onKonum && pg.phase !== "sonuc" && pg.phase !== "baslangic") {
          const pr = pm.onKonum(pg, me.id, k.p, sayi(d.h, 20) ? d.h : 0); // (Büyük Kaçış: yükseklikten yer altı)
          if (pr) {
            await this.deliver(pr, null);
            await this.saveGame();
          }
        }
        // nabız (sn'de bir, kıpırdamasan da): açık kapı listesi. Oda uyuyup uyandıysa kapı durumu buradan geri gelir.
        // (az önce kapı açılıp kapandıysa o mesajı henüz görmemiş eski nabız onu ezmesin)
        if (Array.isArray(d.kp) && (!this.doors || Date.now() - (this._kapiAt || 0) > 2000)) {
          this.doors = {};
          for (const c of d.kp.slice(0, MAX_PLAYERS)) if (Number.isInteger(c) && c >= 0 && c < MAX_PLAYERS) this.doors[c] = true;
        }
        this.broadcast(k, ws);
        break;
      }

      case "profil": {
        // ad ve karakter görünüşü (küçük bir sözlük); herkese yeni liste gider
        let look = temizGorunus(d.g);
        if (look && JSON.stringify(look).length > 600) look = null;
        // paralı eşyalar yalnız sahibine (hesap sunucusuna ulaşılamazsa görünüş olduğu gibi kalır)
        if (look && me.hesap) {
          look = await this.sahipliGorunus(ws, me.hesap, look);
          me = this.info(ws); // (dış istek sırasında bilgi değişmiş / bağlantı kapanmış olabilir)
          if (!me.id) break;
        }
        const once = JSON.stringify([me.name, me.look || null]);
        // hesaplı oyuncunun adı kullanıcı adıdır: istemci başka ad yollasa da değişmez
        const name = me.hesapAd ? "" : temizAd(d.ad);
        if (name && adUygun(name)) me.name = name;
        else if (name && me.adRed !== name) {
          me.adRed = name; // aynı ad için bir kez söylenir
          this.send(ws, { t: "bilgi", m: AD_RED, ad_red: true });
        }
        if (look) me.look = look;
        this.setInfo(ws, me);
        // değişmediyse liste yeniden yollanmaz (8 kişilik listede ~2 KB)
        if (JSON.stringify([me.name, me.look || null]) !== once) {
          this.broadcast({ t: "oyuncular", players: this.players() });
          if (this.kadro[me.tekrar]) await this.kadroYaz(me);
        }
        break;
      }

      case "hazir":
        if (me.ready === !!d.on) break;
        me.ready = !!d.on;
        this.setInfo(ws, me);
        this.broadcast({ t: "oyuncular", players: this.players() });
        if (this.acik && !this.g) await this.publicLobby(); // Hızlı Oyun: herkes hazırsa geri sayım başlar / durur
        break;

      case "mik": {
        // oyuncu mikrofonunu kapattı / açtı: herkes baş üstünde çizik mikrofonu görsün (ses zaten gönderilmiyor)
        const kapali = !!d.kapali;
        if (!!me.mik === kapali) break;
        me.mik = kapali;
        this.setInfo(ws, me);
        this.broadcast({ t: "mik", id: me.id, kapali }, ws);
        break;
      }

      case "sikayet":
      case "engelle":
        // maçtaki oyuncu: { id: oda içi numara, neden, not } (hesap anahtarı istemciye hiç gitmez)
        await this.odaIslem(ws, me, d);
        break;

      case "emote":
        if (typeof d.e !== "string" || !d.e) break;
        this.broadcast({ t: "emote", id: me.id, e: d.e.slice(0, 16) }, ws);
        break;

      case "kapi": {
        const c = Number(d.cell);
        if (!Number.isInteger(c) || c < 0 || c >= MAX_PLAYERS) break; // hücre numarası 0-7
        (this.doors ||= {})[c] = !!d.open; // yakındaki ses kapı kapalıysa geçmez
        this._kapiAt = Date.now();
        this.broadcast({ t: "kapi", cell: c, open: !!d.open }, ws);
        break;
      }

      case "ara": {
        await this.loadGame();
        if (!Number.isFinite(Number(d.to))) break;
        const istenen = Number(d.to); // telefondaki numara (Kim Kim?'de "Hat N"): cevapta gerçek numara geri gitmesin
        d.to = this.unalias(d.to);
        if (this.isBot(d.to)) {
          this.send(ws, { t: "bilgi", m: "Botlar telefonu açamaz." });
          this.send(ws, { t: "mesgul", to: istenen });
          break;
        }
        const p = this.byId(d.to);
        const pi = p ? this.info(p) : null;
        const g = await this.loadGame();
        const dead = g && g.phase !== "bitti" && (!g.players.includes(me.id) || (pi && !g.players.includes(pi.id)));
        if (!p || p === ws || dead || me.call || me.calling || pi.call || pi.calling || pi.ringFrom || this.engelli(me, pi)) {
          this.send(ws, { t: "mesgul", to: istenen });
          break;
        }
        pi.ringFrom = me.id;
        // Kim Kim?: aranan kişi arayanı "****" görür (ne adı ne hattı); arayan karşısını "Hat N" görür
        pi.gizli = this.anon() ? me.id : 0;
        me.calling = pi.id;
        this.setInfo(p, pi);
        this.setInfo(ws, me);
        this.send(p, { t: "caliyor", from: this.gorunen(pi, me.id) });
        this.zil(pi.cell, true, p);
        this.hatlar();
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
        this.send(ws, { t: "baglandi", with: this.gorunen(me, pi.id) });
        this.send(p, { t: "baglandi", with: this.gorunen(pi, me.id) });
        this.zil(me.cell, false, ws);
        this.hatlar();
        break;
      }

      case "kapat":
        this.endCall(ws);
        break;

      case "hatlar":
        // rehber açıldı (ya da geri bağlanıldı): telefondakilerin güncel listesi hemen bu oyuncuya
        // (Kim Kim? sürüyorsa takma numaralarla; seni arayan "****" yine listede yer almaz)
        await this.loadGame();
        if (this._hatKeys) delete this._hatKeys[me.id];
        this.hatlar();
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
    let ringingWs = null; // zili çalan telefonun sahibi
    if (me.ringFrom) {
      ringingCell = me.cell;
      ringingWs = ws;
    }
    me.call = me.calling = me.ringFrom = 0;
    if (me.gizli) me.gizliSon = me.gizli; // görüşme bitse de "****" şikayet edilebilsin
    me.gizli = 0;
    this.setInfo(ws, me);
    if (!partnerId) return;
    const p = this.byId(partnerId);
    if (p) {
      const pi = this.info(p);
      if (pi.ringFrom === me.id) {
        ringingCell = pi.cell;
        ringingWs = p;
      }
      if (pi.call === me.id) pi.call = 0;
      if (pi.calling === me.id) pi.calling = 0;
      if (pi.ringFrom === me.id) pi.ringFrom = 0;
      if (pi.gizli === me.id) {
        pi.gizliSon = me.id;
        pi.gizli = 0;
      }
      this.setInfo(p, pi);
      this.send(p, { t: "kapandi" });
    }
    if (ringingCell >= 0) this.zil(ringingCell, false, ringingWs);
    this.hatlar();
  }

  // Hücredeki telefonun zili. Kim Kim? sürerken yalnız aranana gider (kimin hücresinin çaldığı, yani aranan hattın
  // kim olduğu herkese belli olmasın); diğer zamanlarda herkes duyar.
  zil(cell, on, sahip) {
    const msg = { t: "zil", cell, on };
    if (!this.anon()) return this.broadcast(msg);
    if (sahip) this.send(sahip, msg);
  }

  // Telefonda olanlar (konuşan, arayan ya da zili çalan): rehberde küçük kırmızı "MEŞGUL" etiketi için.
  // Kim Kim?'de takma numarayla gider (rehber "Hat 3" gösterir); seni arayan ("****") senin listende yer almaz,
  // yoksa meşgul hatlardan arayanın hattı çıkarılabilirdi. Kişiye göre değişmediyse tekrar yollanmaz.
  hatlar() {
    const mesgul = [];
    const socks = this.sockets();
    for (const ws of socks) {
      const i = this.info(ws);
      if (i.call || i.calling || i.ringFrom) mesgul.push(i.id);
    }
    const anon = !!this.anon();
    const keys = (this._hatKeys ||= {});
    for (const ws of socks) {
      const r = this.info(ws);
      if (!r || !r.id) continue;
      const ids = mesgul.filter((id) => !(anon && r.gizli && r.gizli === id)).map((id) => this.alias(id));
      ids.sort((a, b) => a - b);
      const key = ids.join(",");
      if (keys[r.id] === key) continue;
      keys[r.id] = key;
      this.send(ws, { t: "hatlar", ids });
    }
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
    this.kopuk[me.tekrar] = { info, until: Date.now() + KOPUK_SURE };
    await this.saveKopuk();
    this.broadcast({ t: "bilgi", ...tx("{0} bağlantısı koptu, bekleniyor…", this.anon() ? "****" : me.name), bag: "koptu", id: me.id }, ws);
    this.broadcast({ t: "oyuncular", players: this.players(ws) }, ws);
    await this.rearm();
  }

  // Bir oyuncunun gerçekten ayrılması (ws: kendi bağlantısı ya da null: süresi dolmuş kopuk oyuncu)
  async leaveInfo(me, ws) {
    await this.kadroSil(me.tekrar);
    if (this._hatKeys) delete this._hatKeys[me.id];
    if (this.pos) delete this.pos[me.id];
    const rest = this.sockets(ws);
    if (me.host && rest.length > 0) {
      // kurucu çıkarsa en eski oyuncu kurucu olur
      rest.sort((a, b) => this.info(a).id - this.info(b).id);
      const h = this.info(rest[0]);
      h.host = true;
      this.setInfo(rest[0], h);
      // salonda / maç sonunda sahiplik değişti: herkes bilsin (maç sürerken önemi yok, bildirim kalabalığı olmasın)
      if (!this.g || this.g.phase === "bitti") this.broadcast({ t: "bilgi", ...tx("Oda sahibi artık {0}.", h.name), bag: "sahip", id: h.id }, ws);
    } else if (me.host) {
      // bağlı kimse kalmadı ama geri dönmesi beklenen var: sahiplik onlardan en eskisine (dönünce oda sahipsiz kalmasın)
      const ks = Object.values(this.kopuk).filter((k) => k.info.id !== me.id).sort((a, b) => a.info.id - b.info.id);
      if (ks.length) {
        ks[0].info.host = true;
        await this.saveKopuk();
      }
    }
    const g = await this.loadGame();
    if (g && g.phase !== "bitti" && g.players.includes(me.id)) {
      const cancel = Game.removePlayer(g, me.id);
      this.broadcast({ t: "bilgi", ...tx("{0} oyundan ayrıldı.", this.anon() ? "****" : me.name), bag: "ayrildi", id: me.id }, ws);
      this.gizliYenile(g); // ayrılanın yerine bilgisi değişenler (ör. Kısa Devre şeması başka tahtaya geçti)
      if (cancel && g.phase !== "sonuc" && g.phase !== "baslangic") {
        if (g.m) g.m.wake = 0;
        g.phase = "sonuc"; // bu mini oyun iptal, sıradakine geç
        if (Game.checkEnd(g)) {
          // sıradaki oyun yok (son oyundu ya da kalanlar oynanamaz): maç burada biter
          await this.state.storage.deleteAlarm();
          await this.macBitti(g, ws);
        } else {
          await this.schedule("sonuc");
        }
        // kalanlar "sıradaki oyun" ekranını görsün (yoksa 10 sn eski oyunun ekranında beklerlerdi)
        if (g.phase !== "bitti" && g.players.length >= 2) {
          const next = Game.siradaki(g);
          this.broadcast({ ...this.gameState(), sonraki: next ? next.title : "", iptal: true }, ws);
        }
      } else if (g.phase !== "sonuc" && g.phase !== "baslangic" && g.players.length >= 2 && Game.tamam(g)) {
        // kalan herkes bitirmişti (ör. son oy vermeyen ayrıldı): oylamalı oyunlarda son 15 sn, ötekiler beklemeden geçer
        if (Game.mode(g) && Game.mode(g).kisalt) await this.kisalt();
        else await this.advance();
      } else {
        await this.rearm(); // oyun kendi zamanlayıcısını kurmuş olabilir (ör. rulette sıra)
        // silah/bomba ayrılandaysa yeni sahibi herkes görsün
        if (g.phase !== "sonuc" && g.phase !== "baslangic" && g.players.length >= 2) this.broadcast(this.gameState(), ws);
      }
      if (g.phase !== "bitti" && g.players.length < 2 && Game.checkEnd(g)) {
        await this.state.storage.deleteAlarm();
        await this.macBitti(g, ws);
      }
      await this.saveGame();
    } else if (me.name) {
      // lobide ya da maç sonunda çıktı: kalanlar görsün
      this.broadcast({ t: "bilgi", ...tx("{0} odadan çıktı.", me.name), cikti: me.id, bag: "cikti", id: me.id }, ws);
    }
    if (rest.length === 0 && this.bots.length) {
      this.bots = [];
      await this.saveBots();
    }
    if (this.acik && !(await this.state.storage.get("started"))) await this.publicLobby();
    await odaBildir(this, ws); // ODALAR listesi: kişi sayısı ya da (son kişi çıktıysa) kayıt silinir
    this.broadcast({ t: "ayrildi", id: me.id }, ws);
    this.broadcast({ t: "oyuncular", players: this.players(ws) }, ws);
    // oda tamamen boşaldı (bağlı kimse yok, geri dönmesi beklenen de yok): depo ve alarm silinir
    if (this.sockets(ws).length === 0 && Object.keys(this.kopuk).length === 0) await this.temizle();
  }

  // Ayrılan oyuncu yüzünden gizli bilgisi değişenlere yenisini yolla (g.gizliYenile: oyuncu numaraları)
  gizliYenile(g) {
    const ids = g.gizliYenile || [];
    delete g.gizliYenile;
    for (const id of ids) {
      const w = this.byId(id);
      if (w && g.secret[id]) this.send(w, { t: "gizli", task: g.task, round: g.round, ...g.secret[id] });
    }
  }

  // Boş oda: Durable Object deposu ve alarmı silinir, bellekteki durum sıfırlanır (kod bellekte kalır).
  // Aynı kodla yeniden kurulursa sıfırdan başlar; kimse yokken bot maçı boşuna sürmez.
  async temizle() {
    try {
      await this.state.storage.deleteAlarm();
      await this.state.storage.deleteAll();
    } catch (e) {
      console.log("oda temizlenemedi", e && e.message);
    }
    this.g = null;
    this.bots = [];
    this.kopuk = {};
    this.acik = false;
    this.lobbyAt = 0;
    this.msBitis = 0;
    this.engeller = {};
    this.pos = {};
    this.doors = {};
    this._hatKeys = {};
    this.started = false;
    this.alarmHata = 0;
    this.atilan = [];
    this.kadro = {};
    this.ayar = null;
    this._odaKayitli = false;
    this._odaAnahtar = "";
  }

  async webSocketClose(ws) {
    await this.drop(ws);
  }

  async webSocketError(ws) {
    await this.drop(ws);
  }
}
