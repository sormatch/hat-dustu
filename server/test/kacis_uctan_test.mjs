// BÜYÜK KAÇIŞ uçtan uca:  cd server && SRV=ws://127.0.0.1:8798 node test/kacis_uctan_test.mjs
// (yerel sunucu açıkken: npx wrangler dev --port 8798 --persist-to ../build/qa2/kacis_durum)
// İki gerçek istemci (sv=3) + bot: maç Büyük Kaçış ile başlar (hız 0.1). A gizli yer arar, 4 vidayı söker, klozeti açar,
// aşağı iner, kazar; B de iner, A ona kaşık verir. Sayımda ikisi de yer altında yakalanır (aletler gider). Oyun sonuçlanır.
// Eski sürümlü (sv=2) bir oyuncu varken Büyük Kaçış seçilse de oynanmaz.
import { hesapAc } from "./_hesap.mjs";

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
// coklu olayları da aç
const olaylar = (d) => (d.t !== "olay" ? [] : d.tur === "coklu" ? d.liste : [d]);

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
  // yalnız bundan sonra gelen olayı bekle
  sonra(f, ms = 8000) {
    const n = this.msgs.length;
    return this.wait((d) => this.msgs.indexOf(d) >= n && olaylar(d).some(f), ms);
  }
  karar(v) {
    this.send({ t: "karar", v });
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

// ---- 1) yeni sürümle akış
{
  const ta = (await hesapAc(URL0, "kca")).token;
  const tb = (await hesapAc(URL0, "kcb")).token;
  const code = kod();
  const A = await oda(code, "Ayse", ta, true, 3);
  const B = await oda(code, "Burak", tb, false, 3);
  const pb = A.wait((d) => d.t === "oyuncular" && d.players.some((x) => x.bot));
  A.send({ t: "bot_ekle" });
  await pb;
  B.send({ t: "hazir", on: true });
  await A.wait((d) => d.t === "oyuncular" && d.players.some((x) => x.id === B.hos.id && x.r));
  A.send({ t: "basla", oyunlar: ["kacis"], hiz: 0.1 });
  const anons = await A.wait((d) => d.t === "oyun" && d.task === "kacis" && d.phase === "anons", 15000);
  bak("Büyük Kaçış başladı (anons)", !!anons, JSON.stringify(A.msgs.filter((m) => m.t === "oyun").map((m) => m.task + ":" + m.phase)));
  bak("haritada ızgara/tuğla/kaya var", !!anons && anons.harita && anons.harita.izgara.length === 2 && anons.harita.tugla.length === 1 && anons.harita.kaya.length > 20);
  const gizli = await A.wait((d) => d.t === "gizli" && d.task === "kacis");
  bak("A'nın gizlisi: boş cep + ipucu (aletler hücrede saklı)", !!gizli && gizli.env.length === 0 && !!gizli.ipucu, JSON.stringify(gizli));
  const oyun = await A.wait((d) => d.t === "oyun" && d.task === "kacis" && d.phase === "kacis", 15000);
  bak("kaçış aşaması", !!oyun);
  // hücredeki 10 gizli yeri sırayla ara (bulursa "buldu", yoksa "bos"); çakı ve kaşık mutlaka kendi hücresinde
  const YERLER = ["yatak", "yastik", "kitaplik", "poster", "havalandirma", "tugla", "lavabo", "koltuk", "dolap", "bilgisayar"];
  let env = [];
  let yanit = 0;
  for (const y of YERLER) {
    const ara = A.sonra((e) => e.tur === "buldu" || e.tur === "bos", 3000);
    A.karar({ ara: y });
    const c = await ara;
    if (c) yanit++;
    const b = c && olaylar(c).find((e) => e.tur === "buldu");
    if (b) env = b.env;
    await sleep(110);
  }
  bak("10 aramanın hepsine yanıt geldi", yanit === 10, String(yanit));
  bak("hücrede çakı ve kaşık bulundu", env.includes("caki") && env.includes("kasik"), JSON.stringify(env));
  const tekrar = A.sonra((e) => e.tur === "bos", 2000);
  A.karar({ ara: "yatak" });
  bak("aranmış yer artık boş", !!(await tekrar));
  // 4 vida (hız 0.1: 110 ms arayla), B de görür
  for (let i = 0; i < 4; i++) {
    await sleep(160);
    A.karar({ vida: true });
  }
  const v4 = await B.wait((d) => olaylar(d).some((e) => e.tur === "vida" && e.id === A.hos.id && e.n === 4), 4000);
  bak("4 vida söküldü, B gördü", !!v4);
  const kl = B.sonra((e) => e.tur === "klozet" && e.id === A.hos.id && e.acik);
  A.karar({ klozet: true });
  const klo = await kl;
  const klE = klo && olaylar(klo).find((e) => e.tur === "klozet");
  bak("klozet açıldı, B gördü (kuyu karesi ile)", !!klE && Array.isArray(klE.kare), JSON.stringify(klo));
  const kuyu = klE ? klE.kare : [1, 0];
  // aşağı in ve batıya kaz (kaşık: 650 ms * 0.85)
  A.karar({ nerede: -1 });
  await sleep(800);
  const kz = A.sonra((e) => e.tur === "kazildi" || e.tur === "sert");
  A.karar({ kaz: [kuyu[0] - 1, kuyu[1]] });
  const kazi = await kz;
  bak("kazı yanıtı (kazıldı ya da sert)", !!kazi, JSON.stringify(kazi));
  bak("B kazıyı gördü", !!(await B.wait((d) => olaylar(d).some((e) => e.tur === "kazildi" && e.id === A.hos.id), 2000)) || olaylar(kazi).some((e) => e.tur === "sert"));
  // B de yer altına iner, A ona kaşık verir (others yolu)
  B.karar({ nerede: -1 });
  await sleep(150);
  const al = B.wait((d) => d.t === "olay" && d.tur === "durum" && d.aldi === "kasik", 3000);
  A.karar({ ver: { kime: B.hos.id, esya: "kasik" } });
  const alindi = await al;
  bak("B kaşığı aldı (kimden A)", !!alindi && alindi.kimden === A.hos.id && alindi.env.includes("kasik"), JSON.stringify(alindi));
  // ilk sayım: uyarı, sonra ikisi de yer altında -> yakalanır
  const uy = await A.wait((d) => olaylar(d).some((e) => e.tur === "sayim_uyari"), 15000);
  bak("sayım uyarısı geldi", !!uy);
  const sy = await A.wait((d) => olaylar(d).some((e) => e.tur === "sayim"), 8000);
  const say = sy && olaylar(sy).find((e) => e.tur === "sayim");
  bak("sayımda A ve B yakalandı", !!say && say.yakalanan.includes(A.hos.id) && say.yakalanan.includes(B.hos.id), JSON.stringify(say));
  const ceza = await B.wait((d) => d.t === "olay" && d.tur === "durum" && d.ceza > 0, 3000);
  bak("B'nin aletleri gitti (çakı + kaşık kaldı)", !!ceza && ceza.env.every((x) => x === "caki" || x === "kasik") && ceza.vida === 0, JSON.stringify(ceza));
  // oyun süre sonunda biter
  const son = await A.wait((d) => d.t === "sonuc" || (d.t === "oyun" && d.phase === "sonuc"), 60000);
  bak("oyun sonuçlandı", !!son);
  A.close();
  B.close();
}

// ---- 2) eski sürümlü oyuncu varken seçilmez
{
  const ta = (await hesapAc(URL0, "kcc")).token;
  const tb = (await hesapAc(URL0, "kcd")).token;
  const code = kod();
  const A = await oda(code, "Cem", ta, true, 3);
  const B = await oda(code, "Deniz", tb, false, 2);
  B.send({ t: "hazir", on: true });
  await A.wait((d) => d.t === "oyuncular" && d.players.some((x) => x.id === B.hos.id && x.r));
  A.send({ t: "basla", oyunlar: ["kacis"], hiz: 0.1 });
  const o = await A.wait((d) => d.t === "oyun" && d.phase === "anons", 15000);
  bak("eski sürüm varken Büyük Kaçış oynanmadı", !!o && o.task !== "kacis", o && o.task);
  A.close();
  B.close();
}

console.log(`kacis_uctan_test: ${ok} doğru, ${hata} hata`);
process.exit(hata ? 1 : 0);
