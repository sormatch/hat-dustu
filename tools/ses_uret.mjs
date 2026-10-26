// Anons sesleri: OpenAI konuşma modeliyle Türkçe gardiyan anonsları üretir, ffmpeg ile hapishane
// hoparlörü efekti verir (bant geçiren süzgeç, hafif bozulma, koridor yankısı) ve assets/ses/anons/ altına .ogg yazar.
// Kullanım: node tools/ses_uret.mjs        (Türkçe -> assets/ses/anons/)
//           node tools/ses_uret.mjs en     (İngilizce -> assets/ses/anons_en/)
// Anahtar .gizli/openai.txt; var olan dosyalar atlanır.
import fs from "fs";
import { execFileSync, spawnSync } from "child_process";

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

// Kim Kim? açılış sesi: `node tools/ses_uret.mjs kimkim` -> assets/ses/kimkim_kimim.ogg (+ _en).
// Aranan kişi ahizeyi kaldırınca kısa hat cızırtısı + robot sesi "Acaba ben kimim?" duyar.
// Ham konuşma build/ses_ham/ altında saklanır (yeniden işlemek için yeni istek gerekmez); robot efekti
// voice.gd _robotize + _telephone ile aynı: 16 kHz, 64 Hz halka modülasyonu (0.3..1), 5.5 ms geri beslemeli
// tarak yankı, 6 bit kırpma, 300-3400 Hz hat süzgeci ve yumuşak doyma.
if (process.argv[2] === "kimkim") {
  const HAM = new URL("../build/ses_ham/", import.meta.url);
  fs.mkdirSync(HAM, { recursive: true });
  const SATIRLAR = [
    ["kimkim_kimim", 1.3, "Acaba ben kimim?", "Tek nefeste, akıcı ve orta hızda, kelimeler arasında hiç duraksamadan; gizemli, alaycı, tekdüze bir makine sesi gibi. Türkçe, net telaffuz."],
    ["kimkim_kimim_en", 1.1, "Guess who I am?", "In one quick fluid breath with no pauses between words; mysterious, teasing, flat and monotone like a machine. Clear diction."],
  ];
  const yol = (u) => decodeURIComponent(u.pathname.slice(1));
  for (const [ad, hiz, metin, stil] of SATIRLAR) {
    const ham = new URL(ad + ".wav", HAM);
    if (!fs.existsSync(ham)) {
      const res = await fetch("https://api.openai.com/v1/audio/speech", {
        method: "POST",
        headers: { Authorization: `Bearer ${KEY}`, "Content-Type": "application/json" },
        body: JSON.stringify({ model: "gpt-4o-mini-tts", voice: "ash", input: metin, instructions: stil, response_format: "wav" }),
      });
      if (!res.ok) {
        console.log("HATA", ad, res.status, (await res.text()).slice(0, 200));
        process.exit(1);
      }
      fs.writeFileSync(ham, Buffer.from(await res.arrayBuffer()));
    }
    const robot = [
      "silenceremove=start_periods=1:start_threshold=-45dB:stop_periods=-1:stop_threshold=-30dB:stop_duration=0.08:stop_silence=0.05:detection=peak",
      "aresample=16000", "aformat=sample_fmts=flt:channel_layouts=mono", `atempo=${hiz}`,
      "dynaudnorm=f=150:g=7:p=0.7",
      "aeval='val(0)*(0.3+0.7*sin(2*PI*64*t))'",
      "aecho=1:1:5.5|11|16.5|22|27.5:0.5|0.25|0.125|0.0625|0.03125",
      "aeval='floor(val(0)*0.9*64+0.5)/64'",
      "highpass=f=300:poles=1", "lowpass=f=3400:poles=1", "lowpass=f=3400:poles=1",
      "aeval='val(0)*1.5/(1+abs(val(0)*1.5)*0.35)'",
    ].join(",");
    // hat cızırtısı: pembe gürültü + seyrek çıtırtılar, telefon bandında; ~0.25 sn, sese doğru söner
    const cizirti = "anoisesrc=d=0.25:c=pink:r=16000:a=0.22,aeval='val(0)*(0.35+1.6*gt(random(0),0.93))',highpass=f=300,lowpass=f=3400,afade=t=in:d=0.03,afade=t=out:st=0.15:d=0.1,aformat=sample_fmts=flt:sample_rates=16000:channel_layouts=mono";
    const ogg = new URL("../assets/ses/" + ad + ".ogg", import.meta.url);
    const ara = new URL(ad + "_ara.wav", HAM);
    execFileSync(FFMPEG, ["-y", "-loglevel", "error", "-i", yol(ham), "-filter_complex",
      `${cizirti}[c];[0:a]${robot},apad=pad_dur=0.06,aformat=sample_fmts=flt:sample_rates=16000:channel_layouts=mono[r];[c][r]concat=n=2:v=0:a=1,aresample=44100[o]`,
      "-map", "[o]", "-c:a", "pcm_f32le", yol(ara)]);
    // ses düzeyi: kısa klipte loudnorm tutmuyor; önce ölç (EBU R128), sonra -16 LUFS için kazanç + tepe sınırlayıcı (-1.5 dBFS)
    const olc = spawnSync(FFMPEG, ["-hide_banner", "-nostats", "-i", yol(ara), "-af", "ebur128=framelog=quiet", "-f", "null", "-"], { encoding: "utf8" });
    const lufs = Number([...olc.stderr.matchAll(/I:\s+(-?[\d.]+) LUFS/g)].pop()[1]);
    const kazanc = (-16 - lufs + 0.7).toFixed(2); // +0.7: sınırlayıcının yediği düzey
    execFileSync(FFMPEG, ["-y", "-loglevel", "error", "-i", yol(ara), "-af", `volume=${kazanc}dB,alimiter=limit=0.84:attack=2:release=40:level=disabled`,
      "-ar", "44100", "-ac", "1", "-c:a", "libvorbis", "-q:a", "5", yol(ogg)]);
    fs.unlinkSync(ara);
    console.log("tamam", ad);
  }
  process.exit(0);
}

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
