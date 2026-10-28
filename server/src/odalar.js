// ODALAR: oyuncuların kurduğu odaların ayarları ve "Herkes" odalarının ortak listesi.
//
// Oda kurulurken (kur=1) ayarlar ws adresinde gelir: gor=herkes|arkadas, max=4..8, oda_ad=..., botla=1.
//   - "arkadas" (varsayılan): yalnız davet ve kodla girilir, listede HİÇ görünmez.
//   - "herkes": tek "Odalar" nesnesindeki listeye yazılır, ODALAR ekranında herkes görür ve katılabilir.
// Room kurulunca, kişi sayısı ya da durumu (lobide / maçta) değişince ve kapanınca kaydı günceller (odaBildir);
// ayrıca en geç ODA_NABIZ'da bir tazeler. ODA_TTL boyunca haber gelmeyen kayıt listeden düşer (oda çöktü, sunucu
// yeniden başladı...). Hızlı Oyun (eslestirme.js) bu sistemden tamamen ayrıdır.

import { adUygun } from "./suzgec.js";

export const KISI_MIN = 4;
export const KISI_MAX = 8;
export const ODA_TTL = 60000; // bu kadar güncellenmeyen oda listeden düşer
export const ODA_NABIZ = 25000; // oda kaydını en geç bu aralıkla tazeler
export const LISTE_MAX = 50; // listede en fazla bu kadar oda (mesaj küçük kalsın)
const ODA_MAX = 600; // aynı anda tutulan kayıt (istek yağmurunda depo şişmesin)
const AD_MAX = 22; // oda adı (harf)
// liste isteği: bir IP adresinden saniyede 2, en çok 12 birikmiş (ekran 5 sn'de bir yeniler; yerel test sınırsız)
const IP_ORAN = [2, 12];
const YEREL_IP = new Set(["", "127.0.0.1", "::1", "::ffff:127.0.0.1"]);
const KOD = /^[A-Z0-9]{4}$/;

// Oda adı: kontrol / görünmez yön karakterleri atılır, boşluk sadeleşir, en çok AD_MAX harf (emoji bölünmez)
export function temizOdaAdi(s) {
  const t = String(s || "").replace(/[\u0000-\u001f\u007f​-‏‪-‮⁦-⁩﻿]/g, "").replace(/\s+/g, " ").trim();
  return Array.from(t).slice(0, AD_MAX).join("").trim();
}

// Oda ayarı (kur=1 adresindeki parametreler ya da lobide oda sahibinin {t:"oda_ayar"} mesajı).
// Dönen: { ayar: {gor, max, ad, botla}, adRed } — uygunsuz ad boş (varsayılan "X'in odası") olur.
export function odaAyari(p) {
  const al = (k) => (p && typeof p.get === "function" ? p.get(k) : p ? p[k] : undefined);
  const gor = al("gor") === "herkes" ? "herkes" : "arkadas";
  let max = Math.round(Number(al("max")));
  if (!Number.isFinite(max) || max === 0) max = KISI_MAX;
  max = Math.min(KISI_MAX, Math.max(KISI_MIN, max));
  // adres parametresinde "ad" oyuncunun adıdır (oda adı "oda_ad"); lobideki {t:"oda_ayar"} mesajında "ad" oda adıdır
  const url = p && typeof p.get === "function";
  let ad = temizOdaAdi(url ? al("oda_ad") : al("ad") ?? al("oda_ad"));
  let adRed = false;
  if (ad && !adUygun(ad)) {
    ad = "";
    adRed = true;
  }
  const botla = false; // "Botla doldur" kaldırıldı (28 Ekim 2026): kurulan oda yalnız gerçek oyuncularla; eski istemcinin isteği yok sayılır
  return { ayar: { gor, max, ad, botla }, adRed };
}

// Odanın kişi sınırı (Hızlı Oyun ve eski odalar: 8)
export function kisiSiniri(room) {
  return room.ayar && room.ayar.max ? room.ayar.max : KISI_MAX;
}

// Odaya istemci için ayar mesajı
export function ayarMsg(room) {
  const a = room.ayar;
  if (!a) return null;
  return { t: "oda_ayar", gor: a.gor, max: a.max, ad: a.ad, botla: !!a.botla };
}

function odalarNesnesi(env) {
  if (!env || !env.ODALAR) return null;
  return env.ODALAR.get(env.ODALAR.idFromName("hepsi"));
}

// Room -> Odalar: "Herkes" odasının güncel kaydı (ya da silinmesi). except: ayrılmakta olan bağlantı.
// Değişiklik yoksa ODA_NABIZ dolmadan yeniden yollanmaz. Hata olursa oyun etkilenmez.
export async function odaBildir(room, except = null, zorla = false) {
  const o = odalarNesnesi(room.env);
  if (!o || !room.code) return;
  const a = room.ayar;
  const insan = room.sockets(except).length;
  let govde;
  if (!a || room.acik || a.gor !== "herkes" || insan === 0) {
    // listede hiç yoktu (nesne uykudan uyandıysa bayrak kaybolur: "Herkes" odası yine de siler)
    if (!room._odaKayitli && !zorla && !(a && a.gor === "herkes" && !room.acik)) return;
    govde = { yol: "/sil", veri: { kod: room.code } };
  } else {
    const g = room.g === undefined ? await room.loadGame() : room.g;
    const liste = room.players(except);
    const sahip = liste.find((p) => p.host && !p.bot);
    const veri = { kod: room.code, a: a.ad || "", h: (sahip && sahip.name) || "", n: liste.length, x: a.max, m: g && g.phase !== "bitti" ? 1 : 0, b: a.botla ? 1 : 0 };
    govde = { yol: "/kayit", veri };
  }
  const anahtar = JSON.stringify(govde);
  if (!zorla && anahtar === room._odaAnahtar && Date.now() - (room._odaT || 0) < ODA_NABIZ) return;
  try {
    await o.fetch(new Request("https://ic" + govde.yol, { method: "POST", body: JSON.stringify(govde.veri) }));
    room._odaAnahtar = anahtar;
    room._odaT = Date.now();
    room._odaKayitli = govde.yol === "/kayit";
  } catch (e) {
    room._odaT = Date.now(); // nabız alarmı boşuna dönüp durmasın (değişiklik olursa yine hemen denenir)
    console.log("oda listesi güncellenemedi", e && e.message);
  }
}

// Nabız: "Herkes" odası kaydını süresi dolmadan tazeler (mesaj ve alarm geldikçe çağrılır, kendisi seyreltir)
export async function odaNabiz(room) {
  if (!room.ayar || room.ayar.gor !== "herkes" || room.acik) return;
  if (Date.now() - (room._odaT || 0) < ODA_NABIZ) return;
  await odaBildir(room, null, true);
}

// Lobide alarm kurulurken: "Herkes" odası kaydının bir sonraki tazelenme anı (yoksa 0)
export function nabizZamani(room) {
  if (!room.ayar || room.ayar.gor !== "herkes" || room.acik || room.sockets().length === 0) return 0;
  return (room._odaT || Date.now()) + ODA_NABIZ;
}

// ---------------------------------------------------------------- tek liste nesnesi
export class Odalar {
  constructor(state, env) {
    this.state = state;
    this.env = env || {};
    this.odalar = null; // kod -> { a, h, n, x, m, b, ts }
    this.ipler = new Map(); // IP -> {j, t} jeton kovası
  }

  ipIzin(ip) {
    if (YEREL_IP.has(ip)) return true;
    const now = Date.now();
    let o = this.ipler.get(ip);
    if (!o) o = { j: IP_ORAN[1], t: now };
    o.j = Math.min(IP_ORAN[1], o.j + ((now - o.t) / 1000) * IP_ORAN[0]);
    o.t = now;
    this.ipler.set(ip, o);
    if (this.ipler.size > 20000) this.ipler.clear();
    if (o.j < 1) return false;
    o.j -= 1;
    return true;
  }

  async load() {
    if (!this.odalar) {
      this.odalar = new Map();
      const l = await this.state.storage.list({ prefix: "o:" });
      for (const [k, v] of l) this.odalar.set(k.slice(2), v);
    }
    // süresi dolanlar düşer
    const now = Date.now();
    const sil = [];
    for (const [k, r] of this.odalar) {
      if (now - r.ts > ODA_TTL) {
        this.odalar.delete(k);
        sil.push("o:" + k);
      }
    }
    for (let i = 0; i < sil.length; i += 128) await this.state.storage.delete(sil.slice(i, i + 128));
  }

  async fetch(req) {
    const url = new URL(req.url);
    let d = {};
    if (req.method === "POST") {
      try {
        d = (await req.json()) || {};
      } catch {}
    }
    await this.load();
    if (url.pathname === "/kayit") {
      const k = String(d.kod || "");
      if (!KOD.test(k)) return new Response("?", { status: 400 });
      const sayi = (v, a, b) => Math.min(b, Math.max(a, Math.round(Number(v)) || 0));
      const rec = {
        a: temizOdaAdi(d.a),
        h: Array.from(String(d.h || "")).slice(0, 16).join(""),
        n: sayi(d.n, 0, KISI_MAX),
        x: sayi(d.x, KISI_MIN, KISI_MAX),
        m: d.m ? 1 : 0,
        b: d.b ? 1 : 0,
        ts: Date.now(),
      };
      if (!this.odalar.has(k) && this.odalar.size >= ODA_MAX) {
        // en eski kayıt yer açar
        let eski = "";
        for (const [kk, r] of this.odalar) if (!eski || r.ts < this.odalar.get(eski).ts) eski = kk;
        this.odalar.delete(eski);
        await this.state.storage.delete("o:" + eski);
      }
      this.odalar.set(k, rec);
      await this.state.storage.put("o:" + k, rec);
      return new Response("ok");
    }
    if (url.pathname === "/sil") {
      const k = String(d.kod || "");
      if (this.odalar.delete(k)) await this.state.storage.delete("o:" + k);
      return new Response("ok");
    }
    if (url.pathname === "/liste") {
      if (!this.ipIzin(String(d.ip || "").slice(0, 64))) return Response.json({ o: [], m: "Çok hızlı denedin, biraz bekle." }, { status: 429 });
      return Response.json(this.liste(d.ark));
    }
    return new Response("?", { status: 404 });
  }

  // Liste: arkadaşların odaları üstte, sonra lobide olup yeri olanlar (kalabalık önce), dolu odalar, maçtakiler.
  // Kısa alanlar: k kod, a oda adı ("" = "<h>'nin odası"), h kurucu, n oyuncu (botlar dahil), x sınır, m maçta, b botla dolar, f arkadaşın
  liste(ark) {
    const arkSet = new Set(Array.isArray(ark) ? ark.slice(0, 50).map((x) => String(x).slice(0, 4)) : []);
    const sira = (r) => (r.f ? 0 : 4) + (r.m ? 2 : 0) + (r.n >= r.x ? 1 : 0);
    const hepsi = [];
    for (const [k, r] of this.odalar) hepsi.push({ k, a: r.a, h: r.h, n: r.n, x: r.x, m: r.m, b: r.b, f: arkSet.has(k) ? 1 : 0, ts: r.ts });
    hepsi.sort((p, q) => sira(p) - sira(q) || q.n - p.n || q.ts - p.ts);
    const o = hepsi.slice(0, LISTE_MAX).map(({ ts, f, m, b, ...r }) => ({ ...r, ...(m ? { m: 1 } : {}), ...(b ? { b: 1 } : {}), ...(f ? { f: 1 } : {}) }));
    return { o, toplam: hepsi.length };
  }
}
