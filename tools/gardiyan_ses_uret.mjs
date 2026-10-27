// Projektör Avı gardiyan sesleri: OpenAI konuşma modeliyle (gpt-4o-mini-tts, kullanıcının hesabı) Türkçe ve
// İngilizce replikler. İki tür: "koridor" (yakında bağıran gerçek insan: tam ses aralığı, hafif koridor yankısı)
// ve "megafon" (avlunun kulesinden: bant geçiren süzgeç, doygunluk, açık hava yankısı).
// Kullanım: node tools/gardiyan_ses_uret.mjs [en] [ad1 ad2 ...]   -> assets/ses/gardiyan/ (en: gardiyan_en/)
// Ham konuşma build/ses_ham/gardiyan/ altında saklanır (yeniden işlemek için yeni istek gerekmez).
// Anahtar .gizli/openai.txt; var olan .ogg atlanır (yeniden üretmek için dosyayı sil).
import fs from "fs";
import { execFileSync, spawnSync } from "child_process";

const KEY = fs.readFileSync(new URL("../.gizli/openai.txt", import.meta.url), "utf8").trim();
const EN = process.argv[2] === "en";
const SADECE = process.argv.slice(2).filter((a) => a !== "en");
const OUT = new URL(EN ? "../assets/ses/gardiyan_en/" : "../assets/ses/gardiyan/", import.meta.url);
const HAM = new URL("../build/ses_ham/gardiyan/", import.meta.url);
const FFMPEG = "C:/ffmpeg/bin/ffmpeg.exe";
fs.mkdirSync(OUT, { recursive: true });
fs.mkdirSync(HAM, { recursive: true });
const yol = (u) => decodeURIComponent(u.pathname.slice(1));

const BAGIR_TR = "Gece vardiyasındaki sert, zalim bir hapishane gardiyanı; koridorda mahkumlara yüz yüze, gerçekten bağırıyor. Doğal, nefesli, öfkeli ve alaycı; spiker gibi değil, gerçek bir insan gibi. Türkçe, net telaffuz.";
const MEGAFON_TR = "Kuleden megafonla konuşan, işinden zevk alan zalim bir hapishane gardiyanı. Yüksek sesle, alaycı ve tehditkâr; gerçek bir insan gibi, spiker gibi değil. Türkçe, net telaffuz.";
const BAGIR_EN = "A harsh, cruel night-shift prison guard really yelling at inmates face to face in the corridor. Natural, breathy, angry and mocking; like a real person, not an announcer. American English.";
const MEGAFON_EN = "A cruel prison guard on a watchtower speaking through a megaphone, enjoying every second. Loud, mocking and threatening; like a real person, not an announcer. American English.";
const GULUS_TR = "Uzun, gerçekçi, kötü niyetli ve keyifli bir kahkaha at; boğazdan gelen, nefes alarak, gerçek bir insan gibi. Kelime söyleme, sadece gül.";
const GULUS_EN = "Let out a long, realistic, menacing and gleeful laugh from the throat, breathing between, like a real person. No words, just laughter.";

// [ad, tür, metin, (isteğe bağlı yönerge)]
const TR = [
  ["uyanin", "koridor", "Uyanın bakalım! Her şey bu kadar kolay mı sandınız?!"],
  ["gulus", "koridor", "Hı hı hı... Ha ha ha ha... HAHAHAHAHAHA!", GULUS_TR],
  ["kapilar", "koridor", "Kapılar açılıyor! Herkes dışarı!"],
  ["hizaya", "koridor", "Hizaya geçin! Çabuk!"],
  ["hizaya_dedim", "koridor", "Hizaya geç dedim sana!"],
  ["yuru", "koridor", "Yürüyün! Avluya!"],
  ["sayiyorum", "megafon", "Ona kadar sayıyorum! Saklanın!"],
  ["s1", "megafon", "Bir!"], ["s2", "megafon", "İki!"], ["s3", "megafon", "Üç!"], ["s4", "megafon", "Dört!"], ["s5", "megafon", "Beş!"],
  ["s6", "megafon", "Altı!"], ["s7", "megafon", "Yedi!"], ["s8", "megafon", "Sekiz!"], ["s9", "megafon", "Dokuz!"], ["s10", "megafon", "On!"],
  ["geliyorum", "megafon", "Hazır olsanız da olmasanız da... geliyorum!"],
  ["isiklar", "megafon", "Işıkları yakın! Av başladı!"],
  ["arama_1", "megafon", "Şu sandıkların arkasına bir bakalım..."],
  ["arama_2", "megafon", "Köpekleri salın! Şuraya bakın!"],
  ["arama_3", "megafon", "Orada biri var gibi..."],
  ["yakaladim_1", "megafon", "Yakaladım seni!"],
  ["yakaladim_2", "megafon", "Bir tane daha! Hahaha!"],
  ["yakaladim_3", "megafon", "Kaçamazsın benden!"],
  ["bir_projektor", "megafon", "Bir projektör daha yakın!"],
  ["son", "megafon", "Bu sefer kaçtın... Bir dahaki sefere bakarız."],
  ["gulus_megafon", "megafon", "Hahahahaha!", GULUS_TR],
];
const ENL = [
  ["uyanin", "koridor", "Wake up! You thought it'd be that easy?!"],
  ["gulus", "koridor", "Heh heh heh... Ha ha ha ha... HAHAHAHAHAHA!", GULUS_EN],
  ["kapilar", "koridor", "Doors opening! Everybody out!"],
  ["hizaya", "koridor", "Line up! Move it!"],
  ["hizaya_dedim", "koridor", "I said get in line!"],
  ["yuru", "koridor", "Walk! Out to the yard!"],
  ["sayiyorum", "megafon", "I'm counting to ten! Hide!"],
  ["s1", "megafon", "One!"], ["s2", "megafon", "Two!"], ["s3", "megafon", "Three!"], ["s4", "megafon", "Four!"], ["s5", "megafon", "Five!"],
  ["s6", "megafon", "Six!"], ["s7", "megafon", "Seven!"], ["s8", "megafon", "Eight!"], ["s9", "megafon", "Nine!"], ["s10", "megafon", "Ten!"],
  ["geliyorum", "megafon", "Ready or not... here I come!"],
  ["isiklar", "megafon", "Lights on! The hunt begins!"],
  ["arama_1", "megafon", "Let's take a look behind those crates..."],
  ["arama_2", "megafon", "Release the dogs! Check over there!"],
  ["arama_3", "megafon", "Looks like someone's over there..."],
  ["yakaladim_1", "megafon", "Gotcha!"],
  ["yakaladim_2", "megafon", "Another one! Hahaha!"],
  ["yakaladim_3", "megafon", "You can't escape me!"],
  ["bir_projektor", "megafon", "Turn on another searchlight!"],
  ["son", "megafon", "You got away this time... We'll see next time."],
  ["gulus_megafon", "megafon", "Hahahahaha!", GULUS_EN],
];

const SUZGEC = {
  // yakında bağıran: hafif sıkıştırma, koridorun beton yankısı
  koridor: "highpass=f=90,acompressor=threshold=0.25:ratio=3:attack=4:release=150,aecho=0.85:0.5:45|95:0.22|0.12",
  // megafon: dar bant, doygunluk, açık havada uzak duvardan dönen yankı
  megafon: "highpass=f=420,lowpass=f=3300,acompressor=threshold=0.18:ratio=5:attack=3:release=100,volume=2.6,aeval='val(0)*1.3/(1+abs(val(0)*1.3)*0.6)',aecho=0.8:0.6:180|360:0.3|0.15",
};

const liste = EN ? ENL : TR;
for (const [ad, tur, metin, yonerge] of liste) {
  if (SADECE.length && !SADECE.includes(ad)) continue;
  const ogg = new URL(ad + ".ogg", OUT);
  if (fs.existsSync(ogg)) continue;
  const ham = new URL((EN ? "en_" : "tr_") + ad + ".wav", HAM);
  if (!fs.existsSync(ham)) {
    const stil = yonerge || (tur === "koridor" ? (EN ? BAGIR_EN : BAGIR_TR) : (EN ? MEGAFON_EN : MEGAFON_TR));
    const res = await fetch("https://api.openai.com/v1/audio/speech", {
      method: "POST",
      headers: { Authorization: `Bearer ${KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({ model: "gpt-4o-mini-tts", voice: "onyx", input: metin, instructions: stil, response_format: "wav" }),
    });
    if (!res.ok) {
      console.log("HATA", ad, res.status, (await res.text()).slice(0, 200));
      continue;
    }
    fs.writeFileSync(ham, Buffer.from(await res.arrayBuffer()));
  }
  const ara = new URL((EN ? "en_" : "tr_") + ad + "_ara.wav", HAM);
  execFileSync(FFMPEG, ["-y", "-loglevel", "error", "-i", yol(ham), "-af",
    "silenceremove=start_periods=1:start_threshold=-45dB:detection=peak,areverse,silenceremove=start_periods=1:start_threshold=-45dB:detection=peak,areverse,aformat=sample_fmts=flt:channel_layouts=mono," + SUZGEC[tur] + ",apad=pad_dur=0.25",
    "-ar", "44100", "-c:a", "pcm_f32le", yol(ara)]);
  // ses düzeyi: ölç, -14 LUFS (bağırış) / -15 (megafon) için kazanç + tepe sınırlayıcı
  const olc = spawnSync(FFMPEG, ["-hide_banner", "-nostats", "-i", yol(ara), "-af", "apad=pad_dur=0.5,ebur128=framelog=quiet", "-f", "null", "-"], { encoding: "utf8" });
  const lufs = Number([...olc.stderr.matchAll(/I:\s+(-?[\d.]+) LUFS/g)].pop()[1]);
  const kazanc = ((tur === "koridor" ? -14 : -15) - lufs + 0.7).toFixed(2);
  execFileSync(FFMPEG, ["-y", "-loglevel", "error", "-i", yol(ara), "-af", `volume=${kazanc}dB,alimiter=limit=0.84:attack=2:release=40:level=disabled`,
    "-ar", "44100", "-ac", "1", "-c:a", "libvorbis", "-q:a", "5", yol(ogg)]);
  fs.unlinkSync(ara);
  console.log("tamam", ad);
}
