// Hat Düştü — OpenAI görsel üretim betiği
// Kullanım (Git Bash, D:/HatDustu içinde):
//   node tools/gorsel_uret.mjs                 -> listedeki eksik görselleri üretir (var olanı atlar)
//   node tools/gorsel_uret.mjs logo oyun_c4    -> yalnızca adı verilenleri üretir
//   node tools/gorsel_uret.mjs --force logo    -> var olsa da yeniden üretir
//   node tools/gorsel_uret.mjs --test          -> küçük/ucuz deneme (model hangisi çalışıyor?)
//   --model=gpt-image-1   --quality=medium   --list (yalnızca listeyi yazdır)
// Anahtar: .gizli/openai.txt (asla yazdırılmaz / loglanmaz).
// Çıktı: assets/ui/uretim/<ad>.png ya da (klasor verilmişse) assets/ui/uretim/<klasor>/<ad>.png
//   (+ uretim/_kayit.json: hangi model/prompt/ne zaman)

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const KOK = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const CIKTI = path.join(KOK, "assets", "ui", "uretim");
const KAYIT = path.join(CIKTI, "_kayit.json");
const MODELLER = ["gpt-image-2", "gpt-image-1.5", "gpt-image-1"]; // en kaliteliden geriye

// Ortak stil cümlesi
const STIL =
  "Dark cinematic prison atmosphere, realistic-stylized 3D game art, rusty metal, green-painted concrete, warm yellow tungsten lamp light, deep shadows, high detail, crisp edges, mobile game asset quality.";
const SAYDAM =
  "Single object centered with generous empty margin on all sides, nothing cropped, fully transparent background, no floor, no backdrop, no shadow plate.";
const YAZISIZ = "Absolutely no text, no letters, no numbers, no watermark, no logo.";

// --- GÖRSEL LİSTESİ (ad -> ayarlar) ---
export const GORSELLER = [
  {
    ad: "uygulama_ikonu",
    size: "1024x1024",
    transparent: false,
    prompt: `Mobile app icon, full-bleed square artwork filling every corner (no rounded corners, no border). A glossy red rotary prison wall payphone handset falling and snapping off its coiled cord, frozen mid-air, small sparks where the cord broke, behind it dark rusty iron prison bars against green-painted concrete, one warm yellow lamp light from above, strong bold silhouette, high contrast, readable at very small size, simple composition. ${STIL} ${YAZISIZ}`,
  },
  {
    ad: "acilis",
    size: "1536x1024",
    transparent: false,
    prompt: `Wide horizontal loading screen / splash art for a mobile game. Long dark prison cell block corridor in one-point perspective, rows of rusty steel cell doors with small barred windows on both sides, green-painted concrete walls with peeling paint, a red rotary payphone mounted on the wall, warm yellow caged ceiling lamps creating pools of light, light haze and dust in the air, cinematic moody lighting. The central upper area is calm, darker and empty (negative space reserved for a game logo). ${STIL} ${YAZISIZ} No people.`,
  },
  {
    ad: "logo",
    size: "1536x1024",
    transparent: true,
    prompt: `Video game title logo, horizontal, two words on one line: "HAT DÜŞTÜ". Spelling, letter by letter: first word H, A, T (3 letters); second word D, Ü, Ş, T, Ü (5 letters: D, then U-umlaut, then S-cedilla, then the letter T, then U-umlaut). The second word must contain the letter T between Ş and the final Ü. All capitals, large and highly legible. Heavy bold blocky letters made of scratched rusty riveted steel plates with glowing red neon tube outlines, subtle warm yellow rim light, a few small sparks. Nothing else written. Logo only, centered, generous margin, transparent background, no backdrop, nothing cropped.`,
  },
  // Açılış amblemi (yazısız taban): "HAT" (üst yay) ve "DÜŞTÜ" (alt yay) tools/amblem_uret.gd ile logo.png'den
  // kavis boyunca bükülerek eklenir (model Türkçe harfleri bozabildiği için yazıyı model yazmaz).
  {
    ad: "amblem_taban",
    klasor: "kaynak", // assets/ui/uretim/kaynak/ (.gdignore: pakete girmez, yalnız araçlar okur)
    size: "1024x1024",
    transparent: true,
    prompt: `Circular game emblem badge, perfectly round, flat front view, perfectly centered, filling about 94% of the canvas. Structure from outside to inside: (1) a thin outer rim of heavy rusty riveted steel with a glowing orange-red neon tube edge; (2) a WIDE plain ring band (about one quarter of the radius wide) of dark scratched rusty gunmetal steel, completely blank and uncluttered all the way around (it is reserved for curved lettering that will be added later at the top and at the bottom), only a few small rivets at the far left and far right (3 o'clock and 9 o'clock positions); (3) a thin inner riveted steel rim with a faint orange glow; (4) the inner round disc: a dark prison background with silhouetted rusty iron bars and a warm red-orange glow, and in the exact center a glossy red retro rotary telephone handset tilted diagonally with its coiled spiral cord curling below it, a few small sparks. Strong bold silhouette, high contrast, readable at small size. Realistic-stylized 3D game art, rusty metal, warm orange-red rim light, deep shadows, high detail, crisp edges, mobile game asset quality. Outside the circle: 100% transparent background, no backdrop, no shadow plate, nothing cropped. ${YAZISIZ}`,
  },
  // Mini oyun rozetleri
  {
    ad: "oyun_tahta",
    size: "1024x1024",
    transparent: true,
    prompt: `Game mode badge icon: a small green school chalkboard in a worn wooden frame, with abstract chalk scribbles and a chalk-drawn question mark shape, a piece of white chalk on the ledge, chalk dust. Bold silhouette, cinematic warm rim light. ${SAYDAM} ${STIL} ${YAZISIZ}`,
  },
  {
    ad: "oyun_devre",
    size: "1024x1024",
    transparent: true,
    prompt: `Game mode badge icon: an open rusty metal electrical fuse box with old ceramic fuses and tangled colorful wires (red, blue, yellow, green), bright electric sparks and a short-circuit flash bursting out. Bold silhouette, cinematic lighting. ${SAYDAM} ${STIL} ${YAZISIZ}`,
  },
  {
    ad: "oyun_kimkim",
    size: "1024x1024",
    transparent: true,
    prompt: `Game mode badge icon: a red rotary telephone handset with a glowing anonymous hooded silhouette mask / question shape made of sound waves coming out of the earpiece, robotic voice wave lines, mysterious. Bold silhouette, cinematic lighting. ${SAYDAM} ${STIL} ${YAZISIZ}`,
  },
  {
    ad: "oyun_yalanci",
    size: "1024x1024",
    transparent: true,
    prompt: `Game mode badge icon: a dented grey-green metal prison locker with its door half open, a warm light glowing from inside revealing a hidden object, suspicious mood. Bold silhouette, cinematic lighting. ${SAYDAM} ${STIL} ${YAZISIZ}`,
  },
  {
    ad: "oyun_rulet",
    size: "1024x1024",
    transparent: true,
    prompt: `Game mode badge icon for a tabletop luck game: an old worn six-shot revolver lying on its side, its cylinder swung open showing six empty chambers, one single brass cartridge standing upright next to it, dramatic warm overhead spotlight (no lamp visible in frame), tense mood. Bold silhouette. ${SAYDAM} ${STIL} ${YAZISIZ}`,
  },
  {
    ad: "oyun_c4",
    size: "1024x1024",
    transparent: true,
    prompt: `Stylized game prop icon for a party mini-game called "hot potato bomb": a harmless prop, three beige putty bricks bundled together with grey duct tape, a few red, blue and yellow wires, and a small digital countdown clock strapped on top with a glowing red LED display (only abstract glowing red bars, no readable digits). Video game collectible, cartoon-realistic, non-violent. Bold silhouette, cinematic lighting. ${SAYDAM} ${STIL} ${YAZISIZ}`,
  },
  {
    ad: "oyun_ortalama",
    size: "1024x1024",
    transparent: true,
    prompt: `Game mode badge icon: a balance scale made of rusty metal with chalk-dusted weights on both sides and a small piece of chalk, symbolizing averaging numbers, chalk dust in the air. Bold silhouette, cinematic lighting. ${SAYDAM} ${STIL} ${YAZISIZ}`,
  },
  {
    ad: "oyun_projektor",
    size: "1024x1024",
    transparent: true,
    prompt: `Game mode badge icon: a prison watchtower searchlight on a rusty metal mount, its powerful cold-white beam cutting diagonally downward through night fog, a bright light circle on the ground, a small piece of barbed wire in the foreground, tense hide-and-seek night mood. Bold silhouette, cinematic lighting. ${SAYDAM} ${STIL} ${YAZISIZ}`,
  },
  // Kasa kartı çerçeveleri
  ...[
    ["kart_siradan", "cool grey / gunmetal silver", "subtle grey"],
    ["kart_nadir", "electric blue", "bright blue"],
    ["kart_epik", "royal purple / violet", "intense purple"],
    ["kart_efsane", "rich gold", "radiant golden"],
  ].map(([ad, renk, parilti]) => ({
    ad,
    size: "1024x1536",
    transparent: true,
    prompt: `Vertical collectible loot card frame for a mobile game case-opening screen, front view, perfectly flat and symmetric, filling most of the canvas. Ornate riveted industrial metal border in ${renk} with ${parilti} glowing edges and a soft outer glow, small corner rivets and prison-bar motifs. The inner panel is a plain very dark charcoal empty area with a faint ${renk} vignette, completely empty (an item picture will be placed on top later). Outside the card: fully transparent background. ${YAZISIZ} No item, no character inside.`,
  })),
  {
    ad: "kasa_kapali",
    size: "1024x1024",
    transparent: true,
    prompt: `Game loot crate: a heavy closed prison-themed steel strongbox chest, olive-green painted riveted metal with rust and scratches, yellow-black hazard stripes, a big padlock and chains locking it shut, three-quarter view. ${SAYDAM} ${STIL} ${YAZISIZ}`,
  },
  {
    ad: "kasa_acik",
    size: "1024x1024",
    transparent: true,
    prompt: `Game loot crate opened: the same heavy prison-themed steel strongbox chest, olive-green painted riveted metal with rust and yellow-black hazard stripes, lid flung open, broken padlock and loose chains, bright warm golden light rays and sparkles bursting out of the inside, three-quarter view. ${SAYDAM} ${STIL} ${YAZISIZ}`,
  },
  {
    ad: "kasa_altin_kapali",
    size: "1024x1024",
    transparent: true,
    prompt: `Premium game loot crate: the same heavy prison-themed riveted steel strongbox chest shape (three-quarter view), but a luxury golden edition: polished gold-plated riveted metal panels with dark gunmetal corner guards, black-and-gold hazard stripes, heavy golden chains locking it shut, a big ornate golden padlock with a glowing amber gem, faint warm golden glow and a few tiny sparkles around the edges. Isolated game asset render: ONLY the chest itself, no wall, no floor, no ground, no room, no environment, no backdrop, no vignette, no shadow plate; everything around the chest is 100% transparent alpha. Realistic-stylized 3D game art, warm golden rim light, high detail, crisp edges, mobile game asset quality. ${YAZISIZ}`,
  },
  {
    ad: "kasa_altin_acik",
    size: "1024x1024",
    transparent: true,
    prompt: `Premium game loot crate opened: the same luxury golden-edition prison steel strongbox chest (polished gold-plated riveted metal panels, dark gunmetal corner guards, black-and-gold hazard stripes), lid flung open, broken golden padlock and loose golden chains, intense bright golden-white light beams and sparkles bursting out of the inside, three-quarter view. Isolated game asset render: ONLY the chest itself, no wall, no floor, no ground, no room, no environment, no backdrop, no vignette, no shadow plate; everything around the chest is 100% transparent alpha. Realistic-stylized 3D game art, warm golden rim light, high detail, crisp edges, mobile game asset quality. ${YAZISIZ}`,
  },
  {
    ad: "tac",
    size: "1024x1024",
    transparent: true,
    prompt: `A shiny golden king's crown with red and purple gemstones, slightly worn, polished metal with warm highlights, front three-quarter view, victory trophy icon for match results screen. ${SAYDAM} Realistic-stylized 3D game art, high detail, crisp edges. ${YAZISIZ}`,
  },
  // Elmas mağazası paket görselleri (küçükten büyüğe). Elmas: parlak camgöbeği (#5ff0ff) kesme taş.
  ...[
    ["elmas_paket_1", "a small neat handful of 3 to 4 brilliant cut cyan diamonds lying together"],
    ["elmas_paket_2", "a small pile of about 10 brilliant cut cyan diamonds"],
    ["elmas_paket_3", "a medium heap of about 30 brilliant cut cyan diamonds overflowing from a small worn leather pouch"],
    ["elmas_paket_4", "a big heap of brilliant cut cyan diamonds spilling out of an open rusty olive-green metal ammo box"],
    ["elmas_paket_5", "a huge mountain of brilliant cut cyan diamonds overflowing from a large open riveted steel prison strongbox, diamonds spilling all around"],
  ].map(([ad, ne]) => ({
    ad,
    size: "1024x1024",
    transparent: true,
    prompt: `Mobile game shop item icon (premium currency pack): ${ne}. Diamonds are glossy bright cyan-turquoise (#5ff0ff) faceted gems with white specular highlights, a soft cyan glow and tiny sparkles. Three-quarter view, bold readable silhouette, stylized 3D render, top mobile game store quality. Isolated game asset: everything around the object is 100% transparent alpha, no floor, no backdrop, no vignette, no shadow plate, nothing cropped, generous margin. ${YAZISIZ}`,
  })),
  {
    ad: "elmas_baslangic",
    size: "1024x1024",
    transparent: true,
    prompt: `Mobile game shop item icon (starter bundle): a small closed olive-green riveted steel prison loot crate with yellow-black hazard stripes and a padlock, a pile of glossy bright cyan-turquoise (#5ff0ff) faceted diamonds spilling in front of it, a few sparkles, warm amber rim light. Three-quarter view, bold readable silhouette, stylized 3D render, top mobile game store quality. Isolated game asset: everything around the object is 100% transparent alpha, no floor, no backdrop, no vignette, no shadow plate, nothing cropped, generous margin. ${YAZISIZ}`,
  },
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
function kayitYaz(k) { fs.writeFileSync(KAYIT, JSON.stringify(k, null, 2)); }

async function istek(key, govde) {
  const r = await fetch("https://api.openai.com/v1/images/generations", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify(govde),
  });
  const metin = await r.text();
  let j;
  try { j = JSON.parse(metin); } catch { j = null; }
  if (!r.ok) {
    const msg = j?.error?.message || metin.slice(0, 300);
    const e = new Error(`HTTP ${r.status}: ${temizle(msg)}`);
    e.status = r.status;
    e.param = j?.error?.param;
    throw e;
  }
  return j;
}

async function uret(key, g, { model, quality, dosya }) {
  const govde = {
    model,
    prompt: g.prompt,
    size: g.size,
    quality,
    n: 1,
    output_format: "png",
  };
  if (g.transparent) govde.background = "transparent";
  else govde.background = "opaque";
  // Saydamlık vb. desteklenmezse sıradaki (daha eski) modele düş: gpt-image-2 -> 1.5 -> 1
  const zincir = [model, ...MODELLER.slice(MODELLER.indexOf(model) + 1)];
  let kullanilan, j, sonHata;
  for (const m of zincir) {
    govde.model = m;
    try { j = await istek(key, govde); kullanilan = m; break; }
    catch (e) {
      sonHata = e;
      if (e.status !== 400 && e.status !== 404) throw e;
      console.log(`
  ${m} reddetti (${e.message}); sıradaki model denenecek`);
    }
  }
  if (!j) throw sonHata;
  const b64 = j?.data?.[0]?.b64_json;
  if (!b64) throw new Error("Yanıtta b64_json yok");
  fs.writeFileSync(dosya, Buffer.from(b64, "base64"));
  return { model: kullanilan, usage: j.usage || null };
}

// ---------------- ana ----------------
async function main() {
  const args = process.argv.slice(2);
  const bayrak = (n) => args.includes(`--${n}`);
  const deger = (n, v) => (args.find((a) => a.startsWith(`--${n}=`)) || `=${v}`).split("=")[1];
  const adlar = args.filter((a) => !a.startsWith("--"));
  const model = deger("model", MODELLER[0]);
  const quality = deger("quality", "high");
  const ek = deger("ek", ""); // ör. --ek=_v2 -> logo_v2.png
  fs.mkdirSync(CIKTI, { recursive: true });

  if (bayrak("list")) {
    for (const g of GORSELLER) console.log(`${g.ad}\t${g.size}\t${g.transparent ? "saydam" : "opak"}`);
    return;
  }
  const key = anahtar();

  if (bayrak("test")) {
    // Hangi modeller çalışıyor? Ucuz deneme (low kalite, saydam)
    const dir = path.join(CIKTI, "_deneme");
    fs.mkdirSync(dir, { recursive: true });
    for (const m of (adlar.length ? adlar : MODELLER)) {
      try {
        const sonuc = await uret(key, { prompt: "A small red rotary telephone, centered, transparent background.", size: "1024x1024", transparent: true },
          { model: m, quality: "low", dosya: path.join(dir, `${m}.png`) });
        console.log(`TEST ${m}: OK (kullanılan ${sonuc.model}) usage=${JSON.stringify(sonuc.usage)}`);
      } catch (e) {
        console.log(`TEST ${m}: HATA ${e.message}`);
      }
    }
    return;
  }

  const kayit = kayitOku();
  const liste = GORSELLER.filter((g) => !adlar.length || adlar.includes(g.ad));
  if (adlar.length && liste.length !== adlar.length) console.log("Uyarı: bazı adlar listede yok:", adlar.filter((a) => !GORSELLER.some((g) => g.ad === a)));
  for (const g of liste) {
    if (g.klasor) fs.mkdirSync(path.join(CIKTI, g.klasor), { recursive: true });
    const dosya = path.join(CIKTI, g.klasor || "", `${g.ad}${ek}.png`);
    if (fs.existsSync(dosya) && !bayrak("force")) { console.log(`atla  ${path.basename(dosya)} (var)`); continue; }
    const t0 = Date.now();
    process.stdout.write(`üret  ${path.basename(dosya)} [${model}, ${quality}, ${g.size}${g.transparent ? ", saydam" : ""}] ... `);
    try {
      const s = await uret(key, g, { model, quality, dosya });
      console.log(`tamam ${((Date.now() - t0) / 1000).toFixed(0)} sn (${s.model}) usage=${JSON.stringify(s.usage)}`);
      kayit[path.basename(dosya)] = { model: s.model, quality, size: g.size, transparent: g.transparent, prompt: g.prompt, usage: s.usage, tarih: new Date().toISOString() };
      kayitYaz(kayit);
    } catch (e) {
      console.log(`HATA ${e.message}`);
    }
  }
}

// Yalnızca doğrudan çalıştırılınca üret (import edilince değil)
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  main().catch((e) => { console.error("Hata:", temizle(e.message)); process.exit(1); });
