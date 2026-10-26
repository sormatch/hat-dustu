// Mağaza görsel iş listesini (isler.json) üretir; sonra afis.gd ile çizilir.
// Kullanım: node magaza/araclar/isler_yap.mjs && Godot --path . -s D:/HatDustu/magaza/araclar/afis.gd -- is=D:/HatDustu/magaza/araclar/isler.json
import fs from "node:fs";

const M = "D:/HatDustu/magaza";
// [sıra_ad, ham görüntü, TR başlık, TR vurgu, EN başlık, EN vurgu, Play'de de var mı]
const EKRANLAR = [
  ["01_telefon", "altyazi", "Hücrendeki telefonu kap!", "telefonu", "Grab the phone in your cell!", "phone", true],
  ["02_yalanci", "yalanci", "Kimseye güvenme!", "güvenme!", "Trust no one!", "no one!", true],
  ["03_kara_tahta", "tahta", "7 çılgın mini oyun", "7 çılgın", "7 wild mini games", "7 wild", true],
  ["04_rulet", "rulet_hedef", "Tetiği kim çekecek?", "Tetiği", "Who pulls the trigger?", "trigger?", true],
  ["05_c4", "c4_ekran", "Bomba sende, hemen devret!", "Bomba", "Pass the bomb before it blows!", "bomb", true],
  ["06_menu", "menu", "Arkadaşlarınla sesli parti", "sesli parti", "Voice chat party with friends", "Voice chat", true],
  ["07_kasa", "kasa_efsane2", "Efsane eşyaları kap!", "Efsane", "Unlock legendary items!", "legendary", true],
  ["08_mac_sonu", "macsonu2", "Kazanan son anda belli olur", "son anda", "The winner is revealed at the end", "at the end", true],
  ["09_magaza", "karakter_kiyafet", "Mahkûmunu tarz yap", "tarz", "Style your inmate", "Style", false],
];
const BOYUTLAR = [
  ["play", 1920, 1080, ""],
  ["appstore_iphone_6.9", 2796, 1290, ""],
  ["appstore_ipad_13", 2732, 2048, "_ipad"],
];
const isler = [];
for (const dil of ["tr", "en"]) {
  for (const [klasor, w, h, ek] of BOYUTLAR) {
    fs.mkdirSync(`${M}/ekranlar/${dil}/${klasor}`, { recursive: true });
    for (const [ad, ham, trB, trV, enB, enV, play] of EKRANLAR) {
      if (klasor === "play" && !play) continue;
      isler.push({ tur: "ekran", girdi: `${M}/ham/${ham}${ek}.png`, cikti: `${M}/ekranlar/${dil}/${klasor}/${ad}.png`, w, h,
        baslik: dil === "tr" ? trB : enB, vurgu: dil === "tr" ? trV : enV });
    }
  }
}
fs.mkdirSync(`${M}/play`, { recursive: true });
for (const [dil, b, v] of [["tr", "Telefonu kap, kimseye güvenme!", "kimseye güvenme!"], ["en", "Grab the phone. Trust no one!", "Trust no one!"]]) {
  isler.push({ tur: "one_cikan", girdi: `${M}/ham/one_cikan_ham.png`, cikti: `${M}/play/one_cikan_gorsel_${dil}_1024x500.png`, w: 1024, h: 500,
    logo: "D:/HatDustu/assets/ui/logo.png", baslik: b, vurgu: v });
}
fs.writeFileSync(`${M}/araclar/isler.json`, JSON.stringify(isler, null, 1));
console.log(isler.length, "iş yazıldı");
