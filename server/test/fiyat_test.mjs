// Fiyat sürümleri testi:  cd server && node test/fiyat_test.mjs
// 1) Sunucunun iki fiyat tablosu (ekonomi.js ITEMS = güncel, ITEMS_V1 = 1.0.0/1.0.1 istemcilerinin gösterdiği, DONMUŞ)
//    tutarlı mı: aynı eşyalar aynı sırada, eski tablo değişmemiş, nadirlik kademesi iki tabloda da aynı, artış ölçülü.
// 2) İstemci (scripts/catalog.gd, account.gd, character.gd) sunucunun GÜNCEL tablosuyla birebir aynı mı.
// 3) Hesap nesnesi: eski istemci (fs yok) eski fiyattan, yeni istemci (fs=2) yeni fiyattan ücretlendirilir
//    (tek eşya, vitrin, set, kasa, hediye; özetteki fiyatlar da bağlantının sürümünde).
// 4) Yerel sunucu açıksa (ws://127.0.0.1:8794) aynısı gerçek bağlantı adresiyle (&fs=2 / yok).
import fs from "node:fs";
import { createHash } from "node:crypto";
import { DatabaseSync } from "node:sqlite";
import * as E from "../src/ekonomi.js";
import * as M from "../src/market.js";

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
const kok = new URL("../../", import.meta.url);
const oku = (yol) => fs.readFileSync(new URL(yol, kok), "utf8");

// ---------------- 1) sunucu tabloları ----------------
{
  const kat = Object.keys(E.ITEMS);
  bak("iki tabloda aynı kategoriler", JSON.stringify(kat) === JSON.stringify(Object.keys(E.ITEMS_V1)));
  for (const c of kat) {
    const a = E.ITEMS[c].map((x) => x[0]);
    const b = E.ITEMS_V1[c].map((x) => x[0]);
    bak("aynı eşyalar aynı sırada: " + c, JSON.stringify(a) === JSON.stringify(b));
  }
  // Eski tablo DONMUŞ: yayındaki telefonlar bu fiyatları gösteriyor. Bu özet değişirse eski oyuncular ekranda
  // gördüğünden farklı fiyat öder. (Bilerek değiştirildiyse yeni bir fiyat sürümü açılmalıydı.)
  const ozetV1 = createHash("sha256").update(JSON.stringify(E.ITEMS_V1)).digest("hex").slice(0, 16);
  bak("ITEMS_V1 donmuş (1.0.0/1.0.1 fiyatları)", ozetV1 === "c23e23738b463824", ozetV1);
  bak("eski sınırlar 60/120/250", JSON.stringify(E.NADIRLIK_SINIR_V1) === "[60,120,250]");
  let kayan = [];
  let oranlar = [];
  for (const c of kat) {
    for (let i = 0; i < E.ITEMS[c].length; i++) {
      const [id, yeni] = E.ITEMS[c][i];
      const eski = E.ITEMS_V1[c][i][1];
      if ((eski === 0) !== (yeni === 0)) kayan.push(c + ":" + id + " bedava/ücretli değişti");
      if (eski === 0) continue;
      if (E.rarity(eski, E.NADIRLIK_SINIR_V1) !== E.rarity(yeni)) kayan.push(`${c}:${id} ${eski}->${yeni}`);
      if (yeni % 5) kayan.push(`${c}:${id} 5'in katı değil`);
      oranlar.push([c + ":" + id, yeni / eski]);
    }
  }
  bak("hiçbir eşyanın nadirliği kaymadı", kayan.length === 0, kayan.join(", "));
  const disari = oranlar.filter(([, r]) => r < 1.2 || r > 1.45);
  bak("artış ölçülü (%20-%45 arası)", disari.length === 0, disari.map((x) => x[0] + " x" + x[1].toFixed(2)).join(", "));
  bak("fiyatlar artmış (hiçbiri ucuzlamamış)", oranlar.every(([, r]) => r > 1));
  bak("fsOf: yok/bozuk -> 1", E.fsOf(null) === 1 && E.fsOf("") === 1 && E.fsOf("abc") === 1 && E.fsOf("0") === 1 && E.fsOf("-3") === 1);
  bak("fsOf: 1, 2 geçerli; büyük -> en yeni", E.fsOf("1") === 1 && E.fsOf("2") === 2 && E.fsOf("99") === E.FIYAT_SON);
  bak("price(fs): eski / yeni", E.price("sapka", "tac", 1) === 600 && E.price("sapka", "tac", 2) === E.price("sapka", "tac"));
  bak("kasa fiyatı: eski 100/400, yeni daha pahalı", E.kasaFiyat("tahta", 1) === 100 && E.kasaFiyat("altin", 1) === 400 &&
    E.kasaFiyat("tahta") > 100 && E.kasaFiyat("altin") > 400);
  // vitrin iki sürümde aynı eşyaları seçer, fiyatlar sürümünden, indirim % gerçek
  for (const gun of ["2026-11-04", "2026-11-05", "2026-12-31"]) {
    const v1 = M.gunluk(gun, 1);
    const v2 = M.gunluk(gun, 2);
    bak("vitrin iki sürümde aynı eşyalar: " + gun, JSON.stringify(v1.map((x) => x[0] + x[1])) === JSON.stringify(v2.map((x) => x[0] + x[1])));
    bak("vitrin eski fiyatlar eski tablodan: " + gun, v1.every((x) => x[2] === E.price(x[0], x[1], 1)));
    bak("vitrin indirim yüzdesi gerçek: " + gun, [...v1, ...v2].every((x) => x[3] === Math.round(((x[2] - x[4]) * 100) / x[2]) && x[4] < x[2]));
  }
  // set: tasarruf gerçek hesaptan
  for (const s of M.gecerliSetler()) {
    for (const fs2 of [1, 2]) {
      const f = M.setFiyat(s, [], false, fs2);
      const top = M.setParcalari(s, fs2).reduce((a, x) => a + x[2], 0);
      if (f.toplam !== top || f.tasarruf !== Math.round(((top - f.fiyat) * 100) / top) || f.fiyat >= top) {
        bak("set tasarrufu gerçek: " + s.k + " fs" + fs2, false, JSON.stringify(f));
      }
    }
  }
  bak("set tasarrufları denetlendi", true);
  bak("en az 15 set", M.gecerliSetler().length >= 15, String(M.gecerliSetler().length));
  const ucuz = M.gecerliSetler().filter((s) => M.setFiyat(s, []).fiyat <= 400);
  bak("ücretsiz oynayanın alabileceği ucuz set var (≤400)", ucuz.length >= 2, ucuz.map((s) => s.k).join(","));
}

// ---------------- 2) istemci = sunucunun güncel tablosu ----------------
{
  const cat = oku("scripts/catalog.gd");
  const a = cat.indexOf("const ITEMS := {");
  const blok = cat.slice(a, cat.indexOf("\n}\n", a));
  let k = null;
  const istemci = {};
  for (const line of blok.split("\n")) {
    const m = line.match(/^\t"([a-z_]+)": \[/);
    if (m) k = m[1];
    for (const x of line.matchAll(/\["([a-z_0-9]+)", "[^"]*", (\d+)\]/g)) (istemci[k] ||= []).push([x[1], Number(x[2])]);
  }
  for (const c of Object.keys(E.ITEMS)) {
    if (c === "govde") continue; // istemci yalnız erkek/kadın gösterir (hepsi bedava)
    bak("catalog.gd = sunucu güncel fiyatları: " + c, JSON.stringify(istemci[c]) === JSON.stringify(E.ITEMS[c]),
      JSON.stringify((istemci[c] || []).filter((x, i) => JSON.stringify(x) !== JSON.stringify(E.ITEMS[c][i])).slice(0, 4)));
  }
  bak("catalog.gd gövdeler bedava", (istemci.govde || []).every(([id, p]) => p === 0 && E.price("govde", id) === 0));
  const r = cat.match(/const RARITY := \[\s*\[(\d+), "SIRADAN"[^\]]*\], \[(\d+), "NADİR"[^\]]*\], \[(\d+), "EPİK"/);
  bak("catalog.gd RARITY sınırları = sunucu", r && [r[1], r[2], r[3]].map(Number).join() === E.NADIRLIK_SINIR.join(), r ? r.slice(1).join() : "yok");
  const acc = oku("scripts/account.gd");
  const fsm = acc.match(/const FIYAT_SURUMU := (\d+)/);
  bak("account.gd FIYAT_SURUMU = sunucu FIYAT_SON", fsm && Number(fsm[1]) === E.FIYAT_SON);
  bak("account.gd bağlantı adresinde fs", /hesap\?token=%s&fs=%d/.test(acc));
  const ch = oku("scripts/character.gd");
  const km = ch.match(/const CHESTS := \[\["Tahta kasa", (\d+),.*\["Altın kasa", (\d+),/);
  bak("character.gd kasa fiyatları = sunucu güncel", km && Number(km[1]) === E.kasaFiyat("tahta") && Number(km[2]) === E.kasaFiyat("altin"), km ? km.slice(1).join() : "yok");
}

// ---------------- 3) hesap nesnesi: eski / yeni istemci ----------------
globalThis.WebSocketRequestResponsePair = class {
  constructor(a, b) {
    this.a = a;
    this.b = b;
  }
};
const { Accounts } = await import("../src/accounts.js");
const db = new DatabaseSync(":memory:");
const socks = [];
const st = {
  storage: { sql: { exec(q, ...args) {
    const s = db.prepare(q);
    const rows = /^\s*(SELECT|WITH)/i.test(q) || /RETURNING/i.test(q) ? s.all(...args) : (s.run(...args), []);
    return { toArray: () => rows };
  } } },
  setWebSocketAutoResponse() {},
  getWebSockets: () => socks,
};
class SahteWS {
  constructor(token, handle, fs) {
    this.att = { token, handle: handle || "", room: "" };
    if (fs !== undefined) this.att.fs = fs; // eski istemci: alan hiç yok
    this.msgs = [];
    socks.push(this);
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
const acc = new Accounts(st, { ODEME_TEST: "0", SPAM_SINIRI: "0" });
let n = 0;
function oyuncu(handle, fs, { gems = 20000, xp = 0 } = {}) {
  const token = "fyt" + String(++n).padStart(20, "0");
  acc.sql.exec(`INSERT INTO users (token, handle, name) VALUES (?, ?, ?)`, token, handle, handle);
  const e = acc.eco(token);
  e.gems = gems;
  e.xp = xp;
  acc.saveEco(token, e);
  const ws = new SahteWS(token, handle, fs);
  return { token, ws, gonder: (d) => ((ws.msgs = []), acc.webSocketMessage(ws, JSON.stringify(d))), eco: () => acc.eco(token) };
}
{
  const vit1 = M.gunluk(M.bugun(), 1);
  const vitrinde = new Set(vit1.map((x) => x[0] + ":" + x[1]));
  // vitrinde olmayan, iki sürümde fiyatı farklı bir eşya
  const [kc, ki] = E.shopItems().find(([c, i]) => !vitrinde.has(c + ":" + i) && E.price(c, i, 1) !== E.price(c, i, 2));
  const eskiF = E.price(kc, ki, 1);
  const yeniF = E.price(kc, ki, 2);

  const eski = oyuncu("eski1", undefined);
  await eski.gonder({ t: "ekonomi" });
  const oz1 = eski.ws.son("ekonomi");
  bak("eski istemci: özet fiyat_surumu 1", oz1.fiyat_surumu === 1);
  bak("eski istemci: vitrin eski fiyatlarla", JSON.stringify(oz1.firsatlar) === JSON.stringify(vit1));
  bak("eski istemci: kasa fiyatları eski", oz1.kasalar.tahta === 100 && oz1.kasalar.altin === 400);
  const s0 = M.gecerliSetler().find((s) => s.k !== (M.haftaninSeti() || {}).k);
  const os1 = oz1.setler.find((s) => s.k === s0.k);
  bak("eski istemci: set fiyatı eski tablodan", os1.fiyat === M.setFiyat(s0, [], false, 1).fiyat && os1.toplam === M.setFiyat(s0, [], false, 1).toplam);
  bak("eski istemci: şeritteki yüzde gerçek tasarruf", os1.indirim === os1.tasarruf && os1.tasarruf === Math.round(((os1.toplam - os1.fiyat) * 100) / os1.toplam));
  await eski.gonder({ t: "satin_al", kat: kc, id: ki, fiyat: eskiF });
  bak("eski istemci: eski fiyattan alır (gördüğünü öder)", eski.ws.son("satin_alindi") && eski.ws.son("satin_alindi").fiyat === eskiF && eski.eco().gems === 20000 - eskiF,
    JSON.stringify(eski.ws.msgs[0]));

  const yeni = oyuncu("yeni1", 2);
  await yeni.gonder({ t: "ekonomi" });
  const oz2 = yeni.ws.son("ekonomi");
  bak("yeni istemci: özet fiyat_surumu 2", oz2.fiyat_surumu === 2);
  bak("yeni istemci: vitrin yeni fiyatlarla", JSON.stringify(oz2.firsatlar) === JSON.stringify(M.gunluk(M.bugun(), 2)));
  bak("yeni istemci: kasa fiyatları yeni", oz2.kasalar.tahta === E.kasaFiyat("tahta") && oz2.kasalar.altin === E.kasaFiyat("altin"));
  await yeni.gonder({ t: "satin_al", kat: kc, id: ki, fiyat: eskiF });
  bak("yeni istemci: eski fiyatı yollarsa reddedilir (fiyat değişti)", yeni.ws.son("hata") && yeni.eco().gems === 20000);
  await yeni.gonder({ t: "satin_al", kat: kc, id: ki, fiyat: yeniF });
  bak("yeni istemci: yeni fiyattan alır", yeni.ws.son("satin_alindi") && yeni.ws.son("satin_alindi").fiyat === yeniF && yeni.eco().gems === 20000 - yeniF);

  // vitrin eşyası: iki sürüm kendi indirimli fiyatından
  const v = vit1[1];
  const ev = oyuncu("eskiv", undefined);
  await ev.gonder({ t: "satin_al", kat: v[0], id: v[1], fiyat: v[4] });
  bak("eski istemci: vitrin eşyası eski indirimli fiyattan", ev.ws.son("satin_alindi") && ev.ws.son("satin_alindi").fiyat === v[4]);
  const yv = oyuncu("yeniv", 2);
  const v2 = M.gunluk(M.bugun(), 2)[1];
  await yv.gonder({ t: "satin_al", kat: v2[0], id: v2[1], fiyat: v2[4] });
  bak("yeni istemci: vitrin eşyası yeni indirimli fiyattan", yv.ws.son("satin_alindi") && yv.ws.son("satin_alindi").fiyat === v2[4]);

  // set
  const es = oyuncu("eskiset", undefined);
  await es.gonder({ t: "set_al", k: s0.k, fiyat: os1.fiyat });
  bak("eski istemci: set eski fiyattan", es.ws.son("set_alindi") && es.ws.son("set_alindi").fiyat === os1.fiyat && es.eco().gems === 20000 - os1.fiyat);
  const ys = oyuncu("yeniset", 2);
  const yf = M.setFiyat(s0, [], false, 2).fiyat;
  await ys.gonder({ t: "set_al", k: s0.k, fiyat: yf });
  bak("yeni istemci: set yeni fiyattan", ys.ws.son("set_alindi") && ys.ws.son("set_alindi").fiyat === yf && yf > os1.fiyat);

  // kasa
  const ek = oyuncu("eskikasa", undefined, { gems: 100 });
  await ek.gonder({ t: "kasa_ac", kasa: "tahta" });
  const r1 = ek.ws.son("kasa_sonuc");
  bak("eski istemci: tahta kasa 100 elmas", r1 && ek.eco().gems === 0 + (r1.kopya ? r1.iade : 0));
  const yk = oyuncu("yenikasa", 2, { gems: 100 });
  await yk.gonder({ t: "kasa_ac", kasa: "tahta" });
  bak("yeni istemci: 100 elmas yeni kasaya yetmez", yk.ws.son("hata") && yk.eco().gems === 100);

  // hediye: gönderenin sürümü
  const g1 = oyuncu("eskigonderen", undefined, { gems: 5000, xp: 3000 });
  const g2 = oyuncu("yenigonderen", 2, { gems: 5000, xp: 3000 });
  const al = oyuncu("hediyealan", 2, { gems: 0 });
  acc.makeFriends("eskigonderen", "hediyealan");
  acc.makeFriends("yenigonderen", "hediyealan");
  await g1.gonder({ t: "hediye", handle: "hediyealan", kat: kc, id: ki, fiyat: eskiF });
  bak("eski istemci: hediye eski fiyattan", g1.ws.son("hediye_gitti") && g1.eco().gems === 5000 - eskiF);
  const [hc, hi] = E.shopItems().find(([c, i]) => !vitrinde.has(c + ":" + i) && c + i !== kc + ki && E.price(c, i, 1) !== E.price(c, i, 2));
  await g2.gonder({ t: "hediye", handle: "hediyealan", kat: hc, id: hi, fiyat: E.price(hc, hi, 2) });
  bak("yeni istemci: hediye yeni fiyattan", g2.ws.son("hediye_gitti") && g2.eco().gems === 5000 - E.price(hc, hi, 2));
  bak("alıcının özeti kendi sürümünde", al.ws.son("ekonomi") && al.ws.son("ekonomi").fiyat_surumu === 2);
}

// ---------------- 4) yerel sunucu (uçtan uca) ----------------
const SRV = process.env.SRV || "ws://127.0.0.1:8794";
function baglan(adres) {
  return new Promise((res) => {
    const ws = new WebSocket(adres);
    const zaman = setTimeout(() => res(null), 4000);
    ws.onerror = () => (clearTimeout(zaman), res(null));
    ws.onmessage = (e) => {
      if (e.data === "pong") return;
      const d = JSON.parse(e.data);
      if (d.t === "ekonomi") {
        clearTimeout(zaman);
        ws.close();
        res(d);
      }
    };
  });
}
{
  const { randomBytes } = await import("node:crypto");
  const tok = randomBytes(16).toString("hex");
  const eskiOz = await baglan(`${SRV}/hesap?token=${tok}`);
  if (!eskiOz) console.log("  (yerel sunucu kapalı: uçtan uca bölüm atlandı)");
  else {
    const yeniOz = await baglan(`${SRV}/hesap?token=${tok}&fs=2`);
    bak("e2e: fs yok -> eski fiyatlar", eskiOz.fiyat_surumu === 1 && eskiOz.kasalar.tahta === 100 && eskiOz.firsatlar.every((x) => x[2] === E.price(x[0], x[1], 1)));
    bak("e2e: fs=2 -> yeni fiyatlar", yeniOz && yeniOz.fiyat_surumu === 2 && yeniOz.kasalar.tahta === E.kasaFiyat("tahta") && yeniOz.firsatlar.every((x) => x[2] === E.price(x[0], x[1], 2)));
    bak("e2e: setler iki sürümde aynı liste", yeniOz && JSON.stringify(eskiOz.setler.map((s) => s.k)) === JSON.stringify(yeniOz.setler.map((s) => s.k)));
  }
}

console.log(`fiyat testi: ${ok} geçti, ${hata} hata`);
process.exit(hata ? 1 : 0);
