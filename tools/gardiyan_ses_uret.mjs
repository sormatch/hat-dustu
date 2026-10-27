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

// Üslup: oyundaki anonslarla AYNI gardiyan (tools/ses_uret.mjs STYLE_TR/EN). İlk denemedeki "gerçekten bağıran, abartılı"
// yönergeler yapay ve çocukça duyuldu (kullanıcı, 28 Ekim); anons sesi doğal bulundu.
const BAGIR_TR = "Sert, otoriter, yorgun bir hapishane gardiyanı; koridorda mahkumlara sesleniyor. Türkçe, doğal vurgu, net telaffuz, biraz alaycı ve dramatik. Acele etme.";
const MEGAFON_TR = "Sert, otoriter, yorgun bir hapishane gardiyanı; avludaki kuleden hoparlörle anons yapıyor. Türkçe, doğal vurgu, net telaffuz, biraz alaycı ve dramatik. Acele etme.";
const BAGIR_EN = "A stern, authoritative, tired prison guard calling out to the inmates in the corridor. American English, natural emphasis, clear diction, a little sarcastic and dramatic. Don't rush.";
const MEGAFON_EN = "A stern, authoritative, tired prison guard making an announcement over the yard loudspeaker from the watchtower. American English, natural emphasis, clear diction, a little sarcastic and dramatic. Don't rush.";

// [ad, tür, metin, (isteğe bağlı yönerge)]
const TR = [
  ["uyanin", "koridor", "Uyanın bakalım! Her şey bu kadar kolay mı sandınız?!"],
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
  ["yakaladim_2", "megafon", "Bir tane daha!"],
  ["yakaladim_3", "megafon", "Kaçamazsın benden!"],
  ["bir_projektor", "megafon", "Bir projektör daha yakın!"],
  ["son", "megafon", "Bu sefer kaçtın... Bir dahaki sefere bakarız."],
  // Büyük Kaçış
  ["kacis_basla", "megafon", "Işıklar sönüyor. Herkes yatağına. Uslu durun... yoksa görürsünüz."],
  ["sayim_geliyor", "megafon", "Sayım! Herkes hücresine! On beş saniye!"],
  ["sayim_tamam", "megafon", "Sayım tamam. Herkes yerinde."],
  ["sayim_yakaladim", "megafon", "Yatağında değilsin! Hücre araması!"],
  ["kacak_var", "megafon", "Alarm! Bir kaçak var! Bütün kapıları kilitleyin!"],
];
const ENL = [
  ["uyanin", "koridor", "Wake up! You thought it'd be that easy?!"],
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
  ["yakaladim_2", "megafon", "Another one!"],
  ["yakaladim_3", "megafon", "You can't escape me!"],
  ["bir_projektor", "megafon", "Turn on another searchlight!"],
  ["son", "megafon", "You got away this time... We'll see next time."],
  ["kacis_basla", "megafon", "Lights out. Everybody in bed. Behave yourselves... or else."],
  ["sayim_geliyor", "megafon", "Head count! Everyone back to your cells! Fifteen seconds!"],
  ["sayim_tamam", "megafon", "Head count's done. Everyone's accounted for."],
  ["sayim_yakaladim", "megafon", "You're not in your bunk! Cell search!"],
  ["kacak_var", "megafon", "Alarm! We have an escapee! Lock down every door!"],
];

const SUZGEC = {
  // yakında bağıran: hafif sıkıştırma, koridorun beton yankısı
  koridor: "highpass=f=200,lowpass=f=5200,acompressor=threshold=0.2:ratio=4:attack=5:release=120,volume=2.0,alimiter=limit=0.8,aecho=0.8:0.5:60|120:0.22|0.1",
  // megafon: dar bant, doygunluk, açık havada uzak duvardan dönen yankı
  megafon: "highpass=f=280,lowpass=f=3600,acompressor=threshold=0.2:ratio=4:attack=5:release=120,volume=2.2,alimiter=limit=0.8,aecho=0.8:0.55:70|140:0.28|0.14",
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
