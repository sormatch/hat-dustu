// E-posta şablonlarını önizler (build/eposta/*.html) ve istenirse test olarak posta worker'ına gönderir.
//   node tools/eposta_test.mjs            → yalnız önizleme dosyaları
//   node tools/eposta_test.mjs gonder [tr|en] [tür...]  → doğrulanmış tek adrese (posta/wrangler.toml) gönderir
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { eposta, EPOSTA_TURLERI } from "../server/src/eposta.js";

const ORNEK = {
  ad: "Emin",
  kullanici: "emin_66",
  kod: "482913",
  url: "https://hatdustu.app/",
  zaman: "26 Ekim 2026, 23:41 (TSİ)",
  cihaz: "iPhone 15 Pro · iOS 26",
  konum: "İstanbul, Türkiye",
  paket: "Başlangıç Paketi",
  etiket: "Tek seferlik",
  elmas: "300 elmas",
  ek: "1 hediye nadir kasa",
  siparis: "HD-7Q4K-2291",
  magaza: "App Store",
  tutar: "49,99 ₺",
  no: "HD-24817",
  baslik: "Kasa açarken oyun kapandı",
  mesaj: "Merhaba, altın kasayı açarken oyun birden kapandı.\nElmaslarım düştü ama eşya gelmedi. Yardımcı olur musunuz?",
};
const ORNEK_EN = { ...ORNEK, zaman: "Oct 26, 2026, 23:41 (GMT+3)", konum: "Istanbul, Türkiye", paket: "Starter Pack", etiket: "One-time", elmas: "300 gems", ek: "1 free rare crate", tutar: "$1.99", baslik: "Game closed while opening a crate", mesaj: "Hi, the game closed while I was opening a gold crate.\nMy gems were spent but I got no item. Can you help?" };

const arg = process.argv.slice(2);
const gonder = arg[0] === "gonder";
const dil = gonder && (arg[1] === "en" || arg[1] === "tr") ? arg[1] : null;
const secili = arg.slice(dil ? 2 : 1).filter((x) => EPOSTA_TURLERI.includes(x));
const turler = secili.length ? secili : EPOSTA_TURLERI;

mkdirSync("build/eposta", { recursive: true });
const liste = [];
for (const d of dil ? [dil] : ["tr", "en"]) {
  for (const tur of turler) {
    const e = eposta(tur, d, d === "en" ? ORNEK_EN : ORNEK);
    writeFileSync(`build/eposta/${d}_${tur}.html`, e.html);
    writeFileSync(`build/eposta/${d}_${tur}.txt`, e.metin);
    liste.push({ d, tur, ...e });
    console.log(`${d}_${tur}: ${e.html.length} karakter html, ${e.metin.length} metin  | ${e.konu}`);
  }
}
writeFileSync(
  "build/eposta/index.html",
  `<!doctype html><meta charset="utf-8"><body style="background:#333;font-family:sans-serif">${liste.map((x) => `<h3 style="color:#fff">${x.d}_${x.tur}: ${x.konu}</h3><iframe src="${x.d}_${x.tur}.html" style="width:640px;height:1500px;border:0;background:#000"></iframe>`).join("")}`,
);

if (gonder) {
  const anahtar = readFileSync(".gizli/posta.txt", "utf8").trim(); // asla yazdırılmaz
  for (const x of liste) {
    if (x.html.length > 50000 || x.metin.length > 20000) throw new Error(`${x.d}_${x.tur} worker sınırını aşıyor`);
    const r = await fetch("https://hatdustu-posta.hatdustu.workers.dev/gonder", {
      method: "POST",
      headers: { Authorization: "Bearer " + anahtar, "Content-Type": "application/json" },
      body: JSON.stringify({ konu: x.konu, metin: x.metin, html: x.html }),
    });
    console.log(`gönder ${x.d}_${x.tur}: ${r.status} ${await r.text()}`);
    await new Promise((s) => setTimeout(s, 1500));
  }
}
