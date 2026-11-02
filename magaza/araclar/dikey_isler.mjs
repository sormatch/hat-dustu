// Dikey mağaza görselleri: iş listesini kurar ve dikey_afis.gd ile birleştirir.
// Kullanım (Git Bash, D:/HatDustu): node magaza/araclar/dikey_isler.mjs [--dil=tr,en] [--oran=iphone,ipad,play] [--no=1,2]
// Önkoşul: build/dikey/plaka/<oran>/d_<sahne>.png (magaza/araclar/dikey_cek.sh).
// Yazılar burada; hepsi Godot ile RussoOne yazı tipinden çizilir, görsele gömülü AI yazısı yoktur.
import fs from "node:fs";
import { spawnSync } from "node:child_process";

const KOK = "D:/HatDustu";
const PLAKA = `${KOK}/build/dikey/plaka`;
const SUS = `${KOK}/magaza/araclar/sus`;
const ORANLAR = {
  iphone: { w: 1290, h: 2796, klasor: "iphone_1290x2796" },
  ipad: { w: 2048, h: 2732, klasor: "ipad_2048x2732" },
  play: { w: 1080, h: 1920, klasor: "play_1080x1920" },
};

// satır: [metin, vurgu(0/1)] parçaları
const IKON = `${KOK}/assets/ui/kit/ikon_mikrofon.png`;
const ORTAK = { ust_koyu: 0.72, ust_bit: 0.36, alt_koyu: 0.78, alt_bas: 0.76, kenar: 0.5, logo: true };
export const GORSELLER = [
  {
    no: "01", ad: "kim_kim", plaka: "d_kimkim", vurgu: "#ffb020",
    tr: { etiket: "KİM KİM?", satirlar: [[["Alo,", 0]], [["sen kimsin?", 1]]] },
    en: { etiket: "WHO'S WHO?", satirlar: [[["Hello,", 0]], [["who is this?", 1]]] },
    ayar: { ...ORTAK },
  },
  {
    no: "02", ad: "yalanci", plaka: "d_yalanci", vurgu: "#ffb020",
    tr: { etiket: "YALANCI", satirlar: [[["Aranızda bir", 0]], [["yalancı var!", 1]]] },
    en: { etiket: "LIAR", satirlar: [[["There's a ", 0], ["liar", 1]], [["among you!", 0]]] },
    ayar: { ...ORTAK, ust_koyu: 0.78 },
  },
  {
    no: "03", ad: "c4", plaka: "d_c4", vurgu: "#ff5a36",
    tr: { etiket: "C4", satirlar: [[["Bomba sende,", 1]], [["hemen devret!", 0]]] },
    en: { etiket: "C4", satirlar: [[["The bomb's on you,", 1]], [["pass it on!", 0]]] },
    ayar: { ...ORTAK, ust_koyu: 0.82 },
  },
  {
    no: "04", ad: "kacis", plaka: "d_kacis", vurgu: "#ffb020",
    tr: { etiket: "BÜYÜK KAÇIŞ", satirlar: [[["Hapishaneden", 0]], [["kaç!", 1]]] },
    en: { etiket: "THE GREAT ESCAPE", satirlar: [[["Break out", 1]], [["of prison!", 0]]] },
    ayar: { ...ORTAK, ek: [{ yol: `${KOK}/build/dikey/plaka/ek/d_tunel.png`, x: 0.585, y: 0.715, g: 0.36, u: 0.0, kare: true, aci: 3, cerceve: true }] },
    ayar_ipad: { ek: [{ yol: `${KOK}/build/dikey/plaka/ek/d_tunel.png`, x: 0.68, y: 0.60, g: 0.27, u: 0.0, kare: true, aci: 3, cerceve: true }] },
    ayar_play: { ek: [{ yol: `${KOK}/build/dikey/plaka/ek/d_tunel.png`, x: 0.62, y: 0.665, g: 0.33, u: 0.0, kare: true, aci: 3, cerceve: true }] },
  },
  {
    no: "05", ad: "projektor", plaka: "d_projektor", vurgu: "#ffb020",
    tr: { etiket: "PROJEKTÖR AVI", satirlar: [[["Gardiyan", 0]], [["seni arıyor!", 1]]] },
    en: { etiket: "SPOTLIGHT HUNT", satirlar: [[["The guard is", 0]], [["hunting you!", 1]]] },
    ayar: { ...ORTAK, ust_koyu: 0.62 },
  },
  {
    no: "06", ad: "rulet", plaka: "d_rulet", vurgu: "#ff5a36",
    tr: { etiket: "RUS RULETİ", satirlar: [[["Tetiği", 0]], [["kim çekecek?", 1]]] },
    en: { etiket: "RUSSIAN ROULETTE", satirlar: [[["Who pulls", 0]], [["the trigger?", 1]]] },
    ayar: { ...ORTAK, baslik_y: 0.665, ust_koyu: 0.3, ust_bit: 0.2, alt_koyu: 0.93, alt_bas: 0.56 },
    ayar_ipad: { baslik_y: 0.655 },
  },
  {
    no: "07", ad: "kasa", plaka: "d_kasa", vurgu: "#ffc23a",
    tr: { etiket: "KARAKTER", satirlar: [[["Kasayı aç,", 0]], [["tarzını seç!", 1]]] },
    en: { etiket: "CHARACTER", satirlar: [[["Open crates,", 0]], [["pick your style!", 1]]] },
    ayar: { ...ORTAK, alt_koyu: 0.6, ek: [{ yol: `${KOK}/assets/ui/uretim/kasa_altin_acik.png`, x: 0.14, y: 0.62, g: 0.72, u: 0.0, kare: true }] },
    ayar_ipad: { ek: [{ yol: `${KOK}/assets/ui/uretim/kasa_altin_acik.png`, x: 0.31, y: 0.615, g: 0.38, u: 0.0, kare: true }] },
    ayar_play: { ek: [{ yol: `${KOK}/assets/ui/uretim/kasa_altin_acik.png`, x: 0.2, y: 0.58, g: 0.6, u: 0.0, kare: true }] },
  },
  {
    no: "08", ad: "mac_sonu", plaka: "d_macsonu", vurgu: "#ffb020",
    tr: { etiket: "MAÇ SONU", satirlar: [[["Arkadaşlarınla", 0]], [["sesli parti!", 1]]] },
    en: { etiket: "MATCH END", satirlar: [[["Voice party", 1]], [["with friends!", 0]]] },
    ayar: { ...ORTAK, konfeti: 60, konfeti_alt: 0.62, kacin: [[0.5, 0.325, 0.11], [0.15, 0.45, 0.1], [0.82, 0.43, 0.1], [0.34, 0.45, 0.07], [0.66, 0.44, 0.07]], rozet: [{ yol: IKON, x: 0.15, y: 0.385, r: 0.04 }, { yol: IKON, x: 0.85, y: 0.37, r: 0.04 }] },
    ayar_ipad: { konfeti: 50, konfeti_alt: 0.66, kacin: [[0.5, 0.42, 0.09], [0.33, 0.52, 0.09], [0.67, 0.52, 0.09], [0.43, 0.56, 0.05], [0.58, 0.56, 0.05]], rozet: [{ yol: IKON, x: 0.2, y: 0.42, r: 0.032 }, { yol: IKON, x: 0.8, y: 0.42, r: 0.032 }] },
    ayar_play: { konfeti_alt: 0.64, kacin: [[0.5, 0.38, 0.11], [0.2, 0.48, 0.1], [0.8, 0.47, 0.1], [0.36, 0.5, 0.07], [0.65, 0.5, 0.07]], rozet: [{ yol: IKON, x: 0.14, y: 0.41, r: 0.04 }, { yol: IKON, x: 0.86, y: 0.40, r: 0.04 }] },
  },
];

const arg = (n) => (process.argv.find((a) => a.startsWith(`--${n}=`)) || "").split("=")[1];
const diller = (arg("dil") || "tr,en").split(",");
const oranlar = (arg("oran") || "iphone,ipad,play").split(",");
const nolar = arg("no") ? arg("no").split(",").map((x) => x.padStart(2, "0")) : null;

const isler = [];
for (const g of GORSELLER) {
  if (nolar && !nolar.includes(g.no)) continue;
  for (const d of diller) {
    for (const o of oranlar) {
      const O = ORANLAR[o];
      const plaka = `${PLAKA}/${o}/${g.plaka}.png`;
      if (!fs.existsSync(plaka)) { console.log("plaka yok:", plaka); continue; }
      const { logo, ...ayar } = g.ayar || {};
      const VARSAY = { ipad: { fs_h: 0.074, logo_g: 0.25, baslik_y: 0.075 }, play: { fs_h: 0.085, logo_g: 0.34 }, iphone: {} }[o];
      const is = {
        ...VARSAY, ...ayar, ...(g[`ayar_${o}`] || {}),
        w: O.w, h: O.h, plaka, vurgu: g.vurgu,
        etiket: g[d].etiket, satirlar: g[d].satirlar,
        cikti: `${KOK}/magaza/dikey/${d}/${O.klasor}/${g.no}_${g.ad}.png`,
      };
      if (logo) is.logo = `${KOK}/${d === "en" ? "assets/ui/uretim/logo_en.png" : "assets/ui/uretim/logo.png"}`;
      if (logo && !fs.existsSync(is.logo)) is.logo = `${KOK}/assets/ui/uretim/logo.png`;
      if (is.ek) is.ek = is.ek.map((e) => (e.kare ? { ...e, u: (e.g * O.w) / O.h } : e));
      if (is.sus) is.sus = is.sus.map((s) => ({ ...s, yol: `${SUS}/${s.ad}.png` }));
      isler.push(is);
    }
  }
}
fs.mkdirSync(`${KOK}/build/dikey`, { recursive: true });
const jsonYol = `${KOK}/build/dikey/isler.json`;
fs.writeFileSync(jsonYol, JSON.stringify(isler, null, 1));
const r = spawnSync("D:/Godot/Godot_v4.7.2-stable_win64_console.exe",
  ["--path", KOK, "--resolution", "270x480", "-s", `${KOK}/magaza/araclar/dikey_afis.gd`, "--", `is=${jsonYol}`],
  { encoding: "utf8", timeout: 600000, maxBuffer: 1 << 26, env: { ...process.env, TMP: "D:/tmp_gh", TEMP: "D:/tmp_gh" } });
const log = (r.stdout || "") + (r.stderr || "");
for (const s of log.split("\n")) if (/^yazildi|SCRIPT ERROR|Parse Error|^ERROR: [^B]/.test(s) && !/PagedAllocator|leaked/.test(s)) console.log(s.trim());
for (const is of isler) {
  if (!fs.existsSync(is.cikti)) { console.log("YOK", is.cikti); continue; }
  const mb = fs.statSync(is.cikti).size / 1048576;
  console.log(mb.toFixed(2), "MB", is.cikti.replace(KOK + "/magaza/dikey/", ""));
}
