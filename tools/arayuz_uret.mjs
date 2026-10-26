// Hat Düştü — ARAYÜZ TAKIMI (UI kit) görsel üretimi
// Kullanım (Git Bash, D:/HatDustu içinde):
//   node tools/arayuz_uret.mjs                  -> eksik ham görselleri üretir (var olanı atlar)
//   node tools/arayuz_uret.mjs ikon_oyna dugmeler   -> yalnızca adı verilenler
//   node tools/arayuz_uret.mjs --force panel    -> var olsa da yeniden üretir
//   --quality=medium  --list  --paralel=4
//   node tools/arayuz_uret.mjs --isle           -> ham görselleri kırpıp assets/ui/kit/ son dosyalarını yazar (ffmpeg)
// Anahtar: .gizli/openai.txt (asla yazdırılmaz / loglanmaz).
// Ham çıktı: assets/ui/kit/_ham/<ad>.png  (Godot bu klasörü görmez: .gdignore)
// Ham görseller ffmpeg ile kırpılıp assets/ui/kit/ altına son hâline getirilir (bkz. docs/TASARIM.md).
// Saydam görseller gpt-image-1.5 ile (gpt-image-2 saydam arka planı reddediyor).

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const KOK = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const HAM = path.join(KOK, "assets", "ui", "kit", "_ham");
const KAYIT = path.join(HAM, "_kayit.json");
const KIT = path.join(KOK, "assets", "ui", "kit");
const FFMPEG = fs.existsSync("C:/ffmpeg/bin/ffmpeg.exe") ? "C:/ffmpeg/bin/ffmpeg.exe" : "ffmpeg";
const MODEL = "gpt-image-1.5";

// Ortak stil: oyunun sanat yönüyle uyumlu ama arayüz için sade, düz önden.
const STIL =
  "Premium mobile game UI asset (Clash Royale / Brawl Stars production quality) with an industrial prison theme. Realistic-stylized painted look: worn dark olive-green painted steel, light rust and scratches only on the outer edges, small round rivets, warm amber lamp-light accents. Orthographic straight-on front view, perfectly symmetric left-right, no perspective, flat even lighting with a soft warm highlight on the top edge, no drop shadow, no cast shadow. Clean, readable, not noisy, crisp edges.";
const SAYDAM = "Isolated on a fully transparent background, nothing cropped, small even empty margin around, no backdrop, no floor.";
const YAZISIZ = "Absolutely no text, no letters, no numbers, no symbols on the surface, no watermark, no logo.";
const ORTA_DUZ = "The central face area is plain, flat, uniform and empty, with no texture, no ornaments, no gradient, so it can be stretched as a 9-slice and have a label placed on it.";

const IKON =
  "Single game UI icon, one bold object, front view, chunky simplified shapes, thick readable silhouette that still reads at 32 pixels, realistic-stylized painted 3D look like premium mobile game icons, consistent lighting: warm amber key light from the upper left, soft rim light, a thin dark outline around the whole silhouette. Palette: worn olive-green steel, brass and warm amber, plus the one accent color named. Object centered and filling about 80% of the canvas, fully transparent background, no shadow, no backdrop, no circle behind it, no frame, no badge plate, nothing cropped.";

const ikon = (ad, konu) => ({ ad, size: "1024x1024", prompt: `${IKON} The object: ${konu}. ${YAZISIZ}` });

export const ARAYUZ = [
  {
    ad: "panel",
    size: "1024x1024",
    prompt: `Square UI window panel plate made for 9-slice scaling, filling about 94% of the canvas. A thick dark gunmetal steel frame border (about 7% of the width) with one round rivet in each of the four corners and slight rust on the frame, a thin glowing warm amber inner edge line just inside the frame. All four sides are identical and plain between the corners (no decorations in the middle of the edges). The whole inner area is a flat, uniform, very dark charcoal-green steel surface with almost no texture, no details, no objects. ${STIL} ${SAYDAM} ${YAZISIZ}`,
  },
  {
    ad: "panel_baslik",
    size: "1536x1024",
    prompt: `A wide horizontal title banner plate for the top of a UI window, very wide and short (aspect ratio about 5:1), centered. Dark olive-green steel plate with a beveled metal rim and a small rivet near each end. The left and right ends each have a short section of yellow-and-black diagonal hazard stripes; the long middle section is plain flat dark steel, empty and uniform. ${STIL} ${SAYDAM} ${YAZISIZ}`,
  },
  {
    ad: "ust_bar",
    size: "1536x1024",
    prompt: `A very wide thin horizontal top-of-screen HUD bar plate (aspect ratio about 8:1), centered. Dark gunmetal steel plate with a thin warm amber trim line along the bottom edge, a few rivets near both ends, short yellow-black hazard stripe accents only at the far left and far right ends. The long middle is plain, flat, uniform dark steel. ${STIL} ${SAYDAM} ${YAZISIZ}`,
  },
  {
    ad: "dugmeler",
    size: "1024x1536",
    prompt: `Exactly four game UI buttons stacked vertically with equal spacing, all four with exactly the same shape and size: a chunky wide horizontal rounded-rectangle button (aspect ratio about 4:1, small corner radius) with visible 3D thickness like a heavy keycap: a thin beveled dark steel rim with a small rivet at the left end and at the right end, a raised convex painted-metal face whose upper half is lighter and glossy and lower half slightly darker, and a darker thick bottom lip under the face showing its depth. Colors from top to bottom: 1) bright amber-yellow painted metal face, 2) dark gunmetal grey steel face, 3) strong red painted metal face, 4) vivid green painted metal face. Light wear and scratches only on the rims. ${ORTA_DUZ} ${STIL} ${SAYDAM} ${YAZISIZ}`,
  },
  {
    ad: "sekmeler",
    size: "1536x1024",
    prompt: `Exactly two game UI tab buttons side by side with equal spacing, both exactly the same shape and size: a wide rounded-top tab (aspect ratio about 2.5:1, rounded top corners, flat bottom edge) with a thin beveled metal rim. Left tab = unselected: dark muted gunmetal steel, dim, matte. Right tab = selected: bright warm amber-yellow painted metal with a soft warm glow along its rim. ${ORTA_DUZ} ${STIL} ${SAYDAM} ${YAZISIZ}`,
  },
  {
    ad: "cubuklar",
    size: "1536x1024",
    prompt: `Exactly two horizontal progress bar parts stacked vertically with a gap between them, both exactly the same width and height (very wide and thin, aspect ratio about 9:1). Top part: the empty track, a recessed dark steel channel with a beveled metal rim and a tiny rivet at each rounded end, the inside of the channel is plain flat near-black. Bottom part: the fill strip only, a smooth glowing amber-yellow to orange energy fill with rounded ends, glossy highlight along its top, no rim. ${STIL} ${SAYDAM} ${YAZISIZ}`,
  },
  {
    ad: "rozet",
    size: "1024x1024",
    prompt: `A very simple small round notification badge for a mobile game, like the red count bubble on an app icon: one glossy bright red circle with a thin light silver rim and a soft glossy highlight on its top half, nothing else (no plate, no screws, no outer ring, no base). Front view, the circle face is plain and empty (a number will be placed on it later). The circle fills about 80% of the canvas. ${STIL} ${SAYDAM} ${YAZISIZ}`,
  },
  {
    ad: "kart",
    size: "1024x1536",
    prompt: `A vertical item card background for an inventory grid, neutral (no rarity color), filling about 94% of the canvas: a dark gunmetal steel frame with a beveled rim and one small rivet in each corner, and an inner area that is a plain flat very dark charcoal-green surface with a faint soft lighter center, completely empty (an item picture is placed on top later). ${STIL} ${SAYDAM} ${YAZISIZ}`,
  },
  ikon("ikon_oyna", "a bold right-pointing triangular play arrow made of glowing amber-yellow beveled metal with two small rivets; accent color amber"),
  ikon("ikon_magaza", "a sturdy steel shopping basket with a handle, holding a glowing blue diamond gem and a gold coin; accent color cyan blue"),
  ikon("ikon_envanter", "a worn olive-green canvas military backpack with brass buckles and straps; accent color brass"),
  ikon("ikon_arkadas", "two simple person bust silhouettes side by side, one slightly in front, rounded heads and shoulders wearing bright orange prisoner jumpsuits; accent color orange"),
  ikon("ikon_ayarlar", "a single thick steel cog gear with eight teeth and a warm amber glowing center hub; accent color amber"),
  ikon("ikon_gorev", "a metal clipboard holding a sheet with three green check marks and short gray lines (no writing); accent color green"),
  ikon("ikon_liderlik", "a three-step winners podium made of steel, the tallest middle step topped with a small gold star, side steps marked by silver and bronze trims; accent color gold"),
  ikon("ikon_basarim", "a round gold medal with an embossed star, hanging from a short red and yellow striped ribbon; accent color gold"),
  ikon("ikon_elmas", "a brilliant cut sparkling diamond gem glowing bright cyan blue; accent color cyan"),
  ikon("ikon_xp", "a bold golden five-pointed star above two gold military rank chevrons; accent color gold"),
  ikon("ikon_kilit", "a heavy closed steel padlock with a brass keyhole plate; accent color brass"),
  ikon("ikon_telefon", "a glossy red vintage telephone handset (receiver only) tilted diagonally, with a short coiled cord end; accent color red"),
  ikon("ikon_kapat", "a bold X cross made of two thick crossed red painted metal bars with a rivet in the middle; accent color red"),
  ikon("ikon_geri", "a bold thick left-pointing arrow made of amber-yellow beveled metal; accent color amber"),
  ikon("ikon_tac", "a simple bold golden crown with three points and a red gem in the middle; accent color gold"),
  ikon("ikon_davet", "a cream paper envelope with a round green badge with a plus sign at its corner; accent color green"),
  ikon("ikon_ses", "a steel loudspeaker cone facing right with three curved amber sound wave arcs; accent color amber"),
  ikon("ikon_mikrofon", "a vintage chrome studio microphone with a grille head on a short stand; accent color amber"),
  // telefon / bekleme salonu / şikayet ekranları (hud.gd, friends.gd)
  ikon("ikon_sikayet", "a small red triangular warning flag on a short steel pole, the flag cloth slightly waving, with a white-yellow exclamation-mark-shaped stripe painted on it; accent color red"),
  ikon("ikon_engelle", "a round red prohibition sign: a thick red ring with a single diagonal red bar across it, made of painted enamel metal with a rivet; accent color red"),
  ikon("ikon_kopyala", "two overlapping cream paper cards, the front one slightly lower-right, with a brass paper clip on top; accent color brass"),
  ikon("ikon_bot", "a friendly boxy robot head made of olive-green riveted steel with two round glowing cyan eyes and a short antenna; accent color cyan"),
  ikon("ikon_onay", "a bold thick green check mark made of beveled glossy green painted metal; accent color green"),
  // oyun içi eylem düğmesi ikonları (hud.gd set_action)
  ikon("ikon_el", "an open hand reaching forward to grab, palm facing the viewer, wearing a worn orange prisoner sleeve cuff; accent color orange"),
  ikon("ikon_kapi", "a heavy prison cell door made of riveted olive-green steel with a small barred window and a brass handle, seen straight from the front; accent color brass"),
  ikon("ikon_sandalye", "a simple worn black leather armchair with thin metal legs seen from the front; accent color brass"),
  ikon("ikon_bilgisayar", "a chunky retro beige CRT computer monitor with a glowing green screen showing only a blinking cursor block, on a small keyboard; accent color green"),
  ikon("ikon_tahta", "a small green school chalkboard in a worn wooden frame with a piece of white chalk on its ledge and faint abstract chalk scribbles; accent color green"),
  ikon("ikon_sigorta", "a small open rusty fuse box with a bright yellow electric lightning spark bursting out of it; accent color yellow"),
  ikon("ikon_egil", "a side view silhouette of a person in an orange prisoner jumpsuit crouching low on one knee, simple chunky shape; accent color orange"),
  ikon("ikon_ahize", "a vintage black bakelite rotary dial desk telephone seen from the front, with a chrome rotary dial and the handset resting on top, a coiled cord; accent color red"),
  ikon("ikon_kasa","a closed olive-green riveted steel loot crate seen from the front, with yellow-black hazard stripes and a brass padlock; accent color yellow"),
];

// ---------------- yardımcılar ----------------
function anahtar() {
  const k = fs.readFileSync(path.join(KOK, ".gizli", "openai.txt"), "utf8").trim();
  if (!k) throw new Error("Anahtar dosyası boş");
  return k;
}
const temizle = (s) => String(s).replace(/sk-[A-Za-z0-9_\-*.]+/g, "sk-***");
function kayitOku() {
  try { return JSON.parse(fs.readFileSync(KAYIT, "utf8")); } catch { return {}; }
}

async function uret(key, g, quality, dosya) {
  const govde = { model: MODEL, prompt: g.prompt, size: g.size, quality, n: 1, output_format: "png", background: "transparent" };
  const r = await fetch("https://api.openai.com/v1/images/generations", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify(govde),
  });
  const metin = await r.text();
  let j = null;
  try { j = JSON.parse(metin); } catch {}
  if (!r.ok) throw new Error(`HTTP ${r.status}: ${temizle(j?.error?.message || metin.slice(0, 300))}`);
  const b64 = j?.data?.[0]?.b64_json;
  if (!b64) throw new Error("Yanıtta b64_json yok");
  fs.writeFileSync(dosya, Buffer.from(b64, "base64"));
  return j.usage || null;
}


// ---------------- işleme (--isle): ham -> assets/ui/kit ----------------
// Ham görseli ham RGBA olarak okur (ffmpeg), saydam olmayan bölgeleri bulur, kırpar.
function rgba(dosya) {
  let err = "";
  try { execFileSync(FFMPEG, ["-hide_banner", "-i", dosya], { stdio: ["ignore", "ignore", "pipe"] }); }
  catch (e) { err = String(e.stderr); }
  const m = err.match(/, (\d{2,5})x(\d{2,5})/);
  if (!m) throw new Error("boyut okunamadı: " + dosya);
  const w = +m[1], h = +m[2];
  const buf = execFileSync(FFMPEG, ["-v", "error", "-i", dosya, "-f", "rawvideo", "-pix_fmt", "rgba", "-"], { maxBuffer: 64 << 20 });
  return { w, h, buf };
}
// eksen boyunca dolu aralıklar (alfa > esik); küçük boşluklar birleştirilir
function araliklar(img, eksen, bolge, esik = 40, bosluk = 8) {
  const { w, buf } = img;
  const [x0, y0, x1, y1] = bolge;
  const dolu = [];
  const n = eksen === "y" ? y1 - y0 : x1 - x0;
  for (let i = 0; i < n; i++) {
    let say = 0;
    if (eksen === "y") { const y = y0 + i; for (let x = x0; x < x1; x++) if (buf[(y * w + x) * 4 + 3] > esik) say++; }
    else { const x = x0 + i; for (let y = y0; y < y1; y++) if (buf[(y * w + x) * 4 + 3] > esik) say++; }
    dolu.push(say > 2);
  }
  const r = [];
  let bas = -1;
  for (let i = 0; i <= n; i++) {
    if (i < n && dolu[i]) { if (bas < 0) bas = i; }
    else if (bas >= 0) { r.push([bas, i]); bas = -1; }
  }
  const birlesik = [];
  for (const a of r) {
    const son = birlesik[birlesik.length - 1];
    if (son && a[0] - son[1] < bosluk) son[1] = a[1]; else birlesik.push([...a]);
  }
  return birlesik.map(([a, b]) => (eksen === "y" ? [y0 + a, y0 + b] : [x0 + a, x0 + b]));
}
// sayi kadar parçaya böl (en büyük parçalar, konum sırasına göre) ve her birinin kutusunu ver
function parcalar(img, eksen, sayi) {
  const tum = [0, 0, img.w, img.h];
  let ana = araliklar(img, eksen, tum).sort((a, b) => (b[1] - b[0]) - (a[1] - a[0])).slice(0, sayi).sort((a, b) => a[0] - b[0]);
  return ana.map(([a, b]) => {
    const bolge = eksen === "y" ? [0, a, img.w, b] : [a, 0, b, img.h];
    const dik = araliklar(img, eksen === "y" ? "x" : "y", bolge, 40, 40);
    const c0 = Math.min(...dik.map((d) => d[0])), c1 = Math.max(...dik.map((d) => d[1]));
    return eksen === "y" ? [c0, a, c1, b] : [a, c0, b, c1];
  });
}
function kirp(giris, cikis, [x0, y0, x1, y1], ek = "", pay = 2) {
  const x = Math.max(0, x0 - pay), y = Math.max(0, y0 - pay);
  const vf = `crop=${x1 - x0 + 2 * pay}:${y1 - y0 + 2 * pay}:${x}:${y}${ek ? "," + ek : ""}`;
  execFileSync(FFMPEG, ["-v", "error", "-y", "-i", giris, "-vf", vf, "-frames:v", "1", cikis]);
  console.log("yaz ", path.basename(cikis), vf);
}

// Yeşilimsi (zeytin) pikselleri altına çevirir (ikon_tac zeytin yeşili çıktı; taç altın olmalı).
function altinla(dosya) {
  const { w, h, buf: b } = rgba(dosya);
  for (let i = 0; i < b.length; i += 4) {
    const r = b[i] / 255, g = b[i + 1] / 255, bl = b[i + 2] / 255;
    const mx = Math.max(r, g, bl), mn = Math.min(r, g, bl), d = mx - mn;
    if (d < 0.04) continue;
    let hu = mx === r ? ((g - bl) / d) % 6 : mx === g ? (bl - r) / d + 2 : (r - g) / d + 4;
    hu *= 60; if (hu < 0) hu += 360;
    if (hu < 44 || hu > 140) continue;
    const t = Math.min(1, (hu - 44) / 6);
    const nh = hu + (38 - hu) * t, ns = Math.min(1, (d / mx) * (1 + 1.1 * t)), nv = Math.min(1, mx * (1 + 0.75 * t));
    const c = nv * ns, x = c * (1 - Math.abs(((nh / 60) % 2) - 1)), m = nv - c;
    const [R, G, B] = nh < 60 ? [c, x, 0] : [x, c, 0];
    b[i] = Math.round((R + m) * 255); b[i + 1] = Math.round((G + m) * 255); b[i + 2] = Math.round((B + m) * 255);
  }
  execFileSync(FFMPEG, ["-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", `${w}x${h}`, "-i", "-", "-frames:v", "1", dosya], { input: b });
  console.log("altın", path.basename(dosya));
}
const BASILI = "vflip,colorchannelmixer=rr=0.74:gg=0.74:bb=0.74"; // ışığı ters çevirip karart = içe göçük
function isle(adlar) {
  const H = (a) => path.join(HAM, a + ".png");
  const K = (a) => path.join(KIT, a + ".png");
  const ister = (a) => !adlar.length || adlar.includes(a);
  const tek = (ham, ad, ek = "") => {
    if (!fs.existsSync(H(ham)) || !ister(ham)) return;
    const img = rgba(H(ham));
    kirp(H(ham), K(ad), parcalar(img, "y", 1)[0], ek);
  };
  tek("panel", "panel", "scale=640:-1:flags=lanczos");
  tek("panel_baslik", "panel_baslik", "scale=900:-1:flags=lanczos");
  tek("ust_bar", "ust_bar", "scale=1200:-1:flags=lanczos");
  tek("kart", "kart", "scale=480:-1:flags=lanczos");
  tek("rozet", "rozet", "scale=192:-1:flags=lanczos");
  if (fs.existsSync(H("dugmeler")) && ister("dugmeler")) {
    const img = rgba(H("dugmeler"));
    const p = parcalar(img, "y", 4);
    ["btn_ana", "btn_ikincil", "btn_tehlike", "btn_yesil"].forEach((ad, i) => {
      kirp(H("dugmeler"), K(ad), p[i]);
      kirp(H("dugmeler"), K(ad + "_basili"), p[i], BASILI);
    });
  }
  if (fs.existsSync(H("sekmeler")) && ister("sekmeler")) {
    const p = parcalar(rgba(H("sekmeler")), "x", 2);
    kirp(H("sekmeler"), K("sekme"), p[0]);
    kirp(H("sekmeler"), K("sekme_secili"), p[1]);
  }
  if (fs.existsSync(H("cubuklar")) && ister("cubuklar")) {
    const p = parcalar(rgba(H("cubuklar")), "y", 2);
    kirp(H("cubuklar"), K("cubuk_bos"), p[0]);
    kirp(H("cubuklar"), K("cubuk_dolu"), p[1]);
  }
  // ikonlar: kırp, 440x440 içine sığdır, 512x512 saydam tuvalde ortala
  const IKON_EK = "scale=440:440:force_original_aspect_ratio=decrease:flags=lanczos,format=rgba,pad=512:512:(ow-iw)/2:(oh-ih)/2:color=0x00000000";
  const kaynaklar = ARAYUZ.filter((g) => g.ad.startsWith("ikon_")).map((g) => [g.ad, H(g.ad)]);
  // kasa ikonu üretilmediyse oyunun kasa görseli kullanılır (aynı sanat yönü)
  if (!fs.existsSync(H("ikon_kasa"))) kaynaklar.push(["ikon_kasa", path.join(KOK, "assets", "ui", "uretim", "kasa_kapali.png")]);
  for (const [ad, giris] of kaynaklar) {
    if (!fs.existsSync(giris) || !ister(ad)) continue;
    kirp(giris, K(ad), parcalar(rgba(giris), "y", 1)[0], IKON_EK);
    if (ad === "ikon_tac") altinla(K(ad));
  }
}

async function main() {
  const args = process.argv.slice(2);
  const bayrak = (n) => args.includes(`--${n}`);
  const deger = (n, v) => (args.find((a) => a.startsWith(`--${n}=`)) || `=${v}`).split("=")[1];
  const adlar = args.filter((a) => !a.startsWith("--"));
  const quality = deger("quality", "high");
  const paralel = Number(deger("paralel", "4"));
  fs.mkdirSync(HAM, { recursive: true });
  if (bayrak("list")) {
    for (const g of ARAYUZ) console.log(`${g.ad}\t${g.size}`);
    return;
  }
  if (bayrak("isle")) { fs.mkdirSync(KIT, { recursive: true }); isle(adlar); return; }
  const key = anahtar();
  const kayit = kayitOku();
  const liste = ARAYUZ.filter((g) => (!adlar.length || adlar.includes(g.ad)))
    .filter((g) => bayrak("force") || !fs.existsSync(path.join(HAM, `${g.ad}.png`)));
  let i = 0;
  const isci = async () => {
    while (i < liste.length) {
      const g = liste[i++];
      const dosya = path.join(HAM, `${g.ad}.png`);
      const t0 = Date.now();
      try {
        const usage = await uret(key, g, quality, dosya);
        console.log(`tamam ${g.ad} ${((Date.now() - t0) / 1000).toFixed(0)} sn usage=${JSON.stringify(usage)}`);
        kayit[g.ad] = { model: MODEL, quality, size: g.size, prompt: g.prompt, usage, tarih: new Date().toISOString() };
        fs.writeFileSync(KAYIT, JSON.stringify(kayit, null, 2));
      } catch (e) {
        console.log(`HATA ${g.ad}: ${e.message}`);
      }
    }
  };
  await Promise.all(Array.from({ length: Math.max(1, paralel) }, isci));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  main().catch((e) => { console.error("Hata:", temizle(e.message)); process.exit(1); });
