// Anons sesleri: OpenAI konuşma modeliyle Türkçe gardiyan anonsları üretir, ffmpeg ile hapishane
// hoparlörü efekti verir (bant geçiren süzgeç, hafif bozulma, koridor yankısı) ve assets/ses/anons/ altına .ogg yazar.
// Kullanım: node tools/ses_uret.mjs        (Türkçe -> assets/ses/anons/)
//           node tools/ses_uret.mjs en     (İngilizce -> assets/ses/anons_en/)
// Anahtar .gizli/openai.txt; var olan dosyalar atlanır.
import fs from "fs";
import { execFileSync } from "child_process";

const KEY = fs.readFileSync(new URL("../.gizli/openai.txt", import.meta.url), "utf8").trim();
const EN = process.argv[2] === "en";
const OUT = new URL(EN ? "../assets/ses/anons_en/" : "../assets/ses/anons/", import.meta.url);
const FFMPEG = "C:/ffmpeg/bin/ffmpeg.exe";
fs.mkdirSync(OUT, { recursive: true });

const STYLE_TR = "Sert, otoriter, yorgun bir hapishane gardiyanı; koridordaki hoparlörden anons yapıyor. Türkçe, doğal vurgu, net telaffuz, biraz alaycı ve dramatik. Acele etme.";
const STYLE_EN = "A stern, authoritative, tired prison guard making an announcement over the corridor loudspeaker. American English, natural emphasis, clear diction, a little sarcastic and dramatic. Don't rush.";
const LINES_TR = {
  mac_basliyor: "Dikkat! Sayım başlıyor. Herkes hücresine!",
  tahta: "Kara tahta. Biriniz gizli bir kelime yazdı. Bulun bakalım.",
  devre: "Elektrikler kesildi! Sigortanızı onarın.",
  kimkim: "Hatlar karıştı. Kimin kim olduğunu bulun.",
  yalanci: "İçinizde bir yalancı var. Herkes dolabını açsın.",
  rulet: "Rus ruleti. Herkes masaya. Tek kazanan olacak.",
  c4: "Dikkat! Hücrelerden birinde bomba var. Kapılar açılıyor!",
  ortalama: "Şimdiki oyun: ortalama sayı. Aklınızdan bir sayı tutun.",
  son_15: "Son on beş saniye!",
  sure_bitti: "Süre doldu!",
  siradaki: "Sıradaki oyun geliyor.",
  mac_bitti: "Sayım bitti. Kazanan belli oldu.",
  kazandin: "Tebrikler mahkum. Bu koğuşun kralı sensin.",
};
const LINES_EN = {
  mac_basliyor: "Attention! Head count begins. Everyone to your cells!",
  tahta: "Blackboard. One of you wrote a secret word. Let's see you find it.",
  devre: "Power's out! Fix your fuse boxes.",
  kimkim: "The lines are crossed. Figure out who's who.",
  yalanci: "There's a liar among you. Everyone, open your lockers.",
  rulet: "Russian roulette. Everyone to the table. Only one walks away.",
  c4: "Attention! There's a bomb in one of the cells. Doors are opening!",
  ortalama: "Next game: average number. Think of a number.",
  son_15: "Last fifteen seconds!",
  sure_bitti: "Time's up!",
  siradaki: "Next game coming up.",
  mac_bitti: "Head count's over. We have a winner.",
  kazandin: "Congratulations, inmate. You're the king of this block.",
};
const STYLE = EN ? STYLE_EN : STYLE_TR;
const LINES = EN ? LINES_EN : LINES_TR;

for (const [name, text] of Object.entries(LINES)) {
  const ogg = new URL(name + ".ogg", OUT);
  if (fs.existsSync(ogg)) continue;
  const res = await fetch("https://api.openai.com/v1/audio/speech", {
    method: "POST",
    headers: { Authorization: `Bearer ${KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ model: "gpt-4o-mini-tts", voice: "onyx", input: text, instructions: STYLE, response_format: "wav" }),
  });
  if (!res.ok) {
    console.log("HATA", name, res.status, (await res.text()).slice(0, 200));
    continue;
  }
  const wav = new URL(name + ".wav", OUT);
  fs.writeFileSync(wav, Buffer.from(await res.arrayBuffer()));
  // hoparlör: 300-3400 Hz, hafif doygunluk, koridor yankısı, ses düzeyi dengeleme
  execFileSync(FFMPEG, ["-y", "-loglevel", "error", "-i", wav.pathname.slice(1),
    "-af", "highpass=f=280,lowpass=f=3600,acompressor=threshold=0.2:ratio=4:attack=5:release=120,volume=2.2,alimiter=limit=0.8,aecho=0.8:0.55:70|140:0.28|0.14,loudnorm=I=-14:TP=-1.5",
    "-ar", "44100", "-c:a", "libvorbis", "-q:a", "5", ogg.pathname.slice(1)]);
  fs.unlinkSync(wav);
  console.log("tamam", name);
}
