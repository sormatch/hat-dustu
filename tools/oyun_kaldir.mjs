// Kullanıcının beğenmediği iki mini oyunu (ikilem, kumar) oyundan tamamen çıkarır.
import fs from 'fs';
const kok = 'D:/HatDustu/';
const duzenle = (yol, isler) => {
  let s = fs.readFileSync(kok + yol, 'utf8');
  for (const [a, b] of isler) {
    if (a instanceof RegExp ? !a.test(s) : !s.includes(a)) throw new Error(yol + ' içinde bulunamadı: ' + String(a).slice(0, 80));
    s = s.replace(a, b);
  }
  fs.writeFileSync(kok + yol, s);
  console.log('düzenlendi', yol);
};
duzenle('server/src/bots.js', [
  ['import { turOf } from "./modes/ikilem.js";\n', ''],
  ['import { elOf, botIddia, botMeydan } from "./modes/kumar.js";\n', ''],
  [/    case "ikilem": \{[\s\S]*?\n    \}\n    case "kumar": \{[\s\S]*?\n    \}\n  \}\n  return null;/, '  }\n  return null;'],
]);
duzenle('server/src/ekonomi.js', [
  [/  \{ k: "ikilem",[^\n]*\n/, ''],
  [/  \{ k: "kumar",[^\n]*\n/, ''],
]);
duzenle('server/src/game.js', [
  ['import * as ikilem from "./modes/ikilem.js";\n', ''],
  ['import * as kumar from "./modes/kumar.js";\n', ''],
  ['c4, ortalama, ikilem, kumar };', 'c4, ortalama };'],
  [/\n[ \t]*"ikilem",[^\n]*/, ''],
  [/\n[ \t]*"kumar",[^\n]*/, ''],
  [', ikilem: "secim", kumar: "blof" };', ' };'],
  [', ikilem: "İKİLEM", kumar: "KUMAR" };', ' };'],
]);
duzenle('scripts/game_ui.gd', [
  [/\n\t"ikilem": preload\("res:\/\/scripts\/modlar\/ikilem_ui\.gd"\),/, ''],
  [/\n\t"kumar": preload\("res:\/\/scripts\/modlar\/kumar_ui\.gd"\),/, ''],
]);
duzenle('scripts/hud.gd', [[', ["ikilem", "MAHKUM İKİLEMİ"], ["kumar", "KUMARBAZ"]]', ']']]);
duzenle('scripts/modlar/oyunici_test.gd', [[', "ikilem": "MAHKUM İKİLEMİ", "kumar": "KUMARBAZ"}', '}']]);
duzenle('scripts/muzik.gd', [[/\n\t"ikilem": "hava", "kumar": "gerilim",/, '']]);
duzenle('scripts/oyun_ici.gd', [[', "MAHKUM İKİLEMİ": "ikilem", "KUMARBAZ": "kumar"}', '}']]);
duzenle('scripts/main.gd', [['# yeni oyunlar (ikilem, kumar) kendi test adımlarını kendi dosyasında taşır', '# bir oyun kendi test adımlarını kendi dosyasında taşıyabilir']]);
for (const f of [
  'server/src/modes/ikilem.js', 'server/src/modes/kumar.js', 'server/test/ikilem_test.mjs', 'server/test/kumar_test.mjs',
  'scripts/modlar/ikilem_ui.gd', 'scripts/modlar/ikilem_ui.gd.uid', 'scripts/modlar/kumar_ui.gd', 'scripts/modlar/kumar_ui.gd.uid',
  'assets/ui/uretim/oyun_ikilem.png', 'assets/ui/uretim/oyun_ikilem.png.import', 'assets/ui/uretim/oyun_kumar.png', 'assets/ui/uretim/oyun_kumar.png.import',
  'assets/ses/anons/ikilem.ogg', 'assets/ses/anons/ikilem.ogg.import', 'assets/ses/anons/kumar.ogg', 'assets/ses/anons/kumar.ogg.import',
  'assets/ses/anons_en/ikilem.ogg', 'assets/ses/anons_en/ikilem.ogg.import', 'assets/ses/anons_en/kumar.ogg', 'assets/ses/anons_en/kumar.ogg.import',
]) {
  if (fs.existsSync(kok + f)) { fs.unlinkSync(kok + f); console.log('silindi', f); }
}
