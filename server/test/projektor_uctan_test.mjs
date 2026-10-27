// PROJEKTÖR AVI uçtan uca:  cd server && SRV=ws://127.0.0.1:8798 node test/projektor_uctan_test.mjs
// (yerel sunucu açıkken: npx wrangler dev --port 8798 --persist-to ../build/qa2/proj_durum)
// İki gerçek istemci (sv=2) + bot: maç Projektör Avı ile başlar, aşamalar anons -> sayim -> av gelir, bot sayımda
// siperine koşar. Av'da A ışığın ortasına yürür (konum mesajı) -> önce "isikta", sonra "yakalandi". B siperde kalır.
// Eski sürümlü (sv yok) bir oyuncu varken Projektör Avı seçilse de oynanmaz.
import { hesapAc } from "./_hesap.mjs";
import * as P from "../src/modes/projektor.js";

const URL0 = process.env.SRV || "ws://127.0.0.1:8798";
let ok = 0;
let hata = 0;
function bak(ad, kosul, ek = "") {
  if (kosul) {
    ok++;
    console.log("  OK   " + ad);
  } else {
    hata++;
    console.log("  HATA " + ad + (ek ? "  -> " + ek : ""));
  }
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const CH = "ABCDEFGHJKLMNPRSTUVYZ23456789";
const kod = () => Array.from({ length: 4 }, () => CH[Math.floor(Math.random() * CH.length)]).join("");

class W {
  constructor(url, ad) {
    this.url = url;
    this.ad = ad;
    this.msgs = [];
    this.waiters = [];
  }
  open() {
    return new Promise((res, rej) => {
      this.ws = new WebSocket(this.url);
      this.ws.onopen = () => res(this);
      this.ws.onerror = (e) => rej(e);
      this.ws.onmessage = (e) => {
        if (typeof e.data !== "string" || e.data === "pong") return;
        const d = JSON.parse(e.data);
        this.msgs.push(d);
        if (process.env.V) console.log(`  [${this.ad}] <-`, JSON.stringify(d).slice(0, 180));
        for (const w of [...this.waiters]) if (w.f(d)) (this.waiters.splice(this.waiters.indexOf(w), 1), w.r(d));
      };
    });
  }
  send(o) {
    this.ws.send(JSON.stringify(o));
  }
  wait(f, ms = 8000) {
    const hazir = this.msgs.find(f);
    if (hazir) return Promise.resolve(hazir);
    return new Promise((r) => {
      const w = { f, r };
      this.waiters.push(w);
      setTimeout(() => {
        const i = this.waiters.indexOf(w);
        if (i >= 0) (this.waiters.splice(i, 1), r(null));
      }, ms);
    });
  }
  close() {
    try {
      this.ws.close();
    } catch {}
  }
}

async function oda(code, ad, hesap, kur, sv) {
  const w = new W(`${URL0}/oda/${code}?ad=${encodeURIComponent(ad)}&kur=${kur ? 1 : 0}&davet=${kur ? 0 : 1}&hesap=${hesap}&dil=tr${sv ? "&sv=" + sv : ""}`, ad);
  const p = w.wait((d) => d.t === "hosgeldin");
  await w.open();
  w.hos = await p;
  return w;
}

// ---- 1) yeni sürümle tam akış
{
  const ta = (await hesapAc(URL0, "pja")).token;
  const tb = (await hesapAc(URL0, "pjb")).token;
  const code = kod();
  const A = await oda(code, "Ayse", ta, true, 2);
  const B = await oda(code, "Burak", tb, false, 2);
  const pb = A.wait((d) => d.t === "oyuncular" && d.players.some((x) => x.bot));
  A.send({ t: "bot_ekle" });
  await pb;
  B.send({ t: "hazir", on: true });
  await A.wait((d) => d.t === "oyuncular" && d.players.some((x) => x.id === B.hos.id && x.r));
  A.send({ t: "basla", oyunlar: ["projektor"], hiz: 0.1 });
  const anons = await A.wait((d) => d.t === "oyun" && d.task === "projektor" && d.phase === "anons", 15000);
  bak("Projektör Avı başladı (anons)", !!anons, JSON.stringify(A.msgs.filter((m) => m.t === "oyun").map((m) => m.task + ":" + m.phase)));
  const sayim = await A.wait((d) => d.t === "oyun" && d.task === "projektor" && d.phase === "sayim", 15000);
  bak("sayım aşaması", !!sayim);
  const kos = await A.wait((d) => d.t === "olay" && (d.tur === "bot_kos" || (d.tur === "coklu" && d.liste.some((x) => x.tur === "bot_kos"))), 5000);
  bak("bot sayımda siperine koştu", !!kos);
  // B siperde dursun
  B.send({ t: "konum", p: P.SIPERLER[1], y: 0 });
  const av = await A.wait((d) => d.t === "oyun" && d.task === "projektor" && d.phase === "av", 15000);
  bak("av aşaması", !!av && Array.isArray(av.hayatta) && av.hayatta.length === 3, JSON.stringify(av && av.hayatta));
  const alindi = Date.now();
  // A ilk ışığın ortasına gider (siper dışı bir anı bekler), konumunu sık yollar
  let yakalandi = null;
  let uyari = null;
  for (let i = 0; i < 60 && !yakalandi; i++) {
    const gecen = av.gecen + (Date.now() - alindi) + 120;
    const c = P.isikMerkez(P.isiklar(av.tohum)[0], gecen);
    A.send({ t: "konum", p: c, y: 0 });
    B.send({ t: "konum", p: P.SIPERLER[1], y: 0 });
    await sleep(120);
    uyari = uyari || A.msgs.find((d) => d.t === "olay" && d.tur === "isikta");
    yakalandi = A.msgs.find((d) => d.t === "olay" && d.tur === "yakalandi" && d.id === A.hos.id);
  }
  bak("ışıkta önce uyarı geldi", !!uyari);
  bak("ışıkta kalan A yakalandı", !!yakalandi, JSON.stringify(A.msgs.filter((d) => d.t === "olay").map((d) => d.tur).slice(-10)));
  bak("B de yakalanmayı gördü", !!(await B.wait((d) => d.t === "olay" && d.tur === "yakalandi" && d.id === A.hos.id, 2000)));
  // oyun biter (süre ya da tek kalan), sonuç gelir
  const son = await A.wait((d) => d.t === "sonuc" || (d.t === "oyun" && d.phase === "sonuc"), 30000);
  bak("oyun sonuçlandı", !!son);
  A.close();
  B.close();
}

// ---- 2) eski sürümlü oyuncu varken seçilmez
{
  const ta = (await hesapAc(URL0, "pjc")).token;
  const tb = (await hesapAc(URL0, "pjd")).token;
  const code = kod();
  const A = await oda(code, "Cem", ta, true, 2);
  const B = await oda(code, "Deniz", tb, false, 0); // sv yok: eski sürüm
  B.send({ t: "hazir", on: true });
  await A.wait((d) => d.t === "oyuncular" && d.players.some((x) => x.id === B.hos.id && x.r));
  A.send({ t: "basla", oyunlar: ["projektor"], hiz: 0.1 });
  const o = await A.wait((d) => d.t === "oyun" && d.phase === "anons", 15000);
  bak("eski sürüm varken Projektör Avı oynanmadı", !!o && o.task !== "projektor", o && o.task);
  A.close();
  B.close();
}

console.log(`projektor_uctan_test: ${ok} doğru, ${hata} hata`);
process.exit(hata ? 1 : 0);
