// Maç yöneticisi: bir oda = sırayla oynanan mini oyunlar. Puanlar oyunlar boyunca toplanır;
// maç sonunda puan tablosu açılır. Her oyunun kuralları modes/ altında.
//
// Bir oyun modülü şunları verir: title, rule, phases (dizi ya da fonksiyon), durations, hidden,
// start(g), stateExtra(g), answer(g, id, v), resolve(g), leave(g, id) ve isteğe bağlı:
//   min (en az oyuncu), requires(players) (ör. davetli oda), onPhase(g, phase), onWake(g)
//   g.m.wake: oyunun kendi zamanlayıcısı (ms); dolunca onWake çağrılır.
// answer/onPhase/onWake dönüşü: { reply, others: [{to,msg}], privates: {id: msg}, broadcast, advance, finish }

import * as tahta from "./modes/tahta.js";
import * as devre from "./modes/devre.js";
import * as kimkim from "./modes/kimkim.js";
import * as yalanci from "./modes/yalanci.js";
import * as rulet from "./modes/rulet.js";
import * as c4 from "./modes/c4.js";
import * as ortalama from "./modes/ortalama.js";
import * as projektor from "./modes/projektor.js";
import * as kacis from "./modes/kacis.js";

export const MODES = { tahta, devre, kimkim, yalanci, rulet, c4, ortalama, projektor, kacis };
// Maçta oynanma sırası. Yeni oyunlar kendi satırında: beğenilmezse o satırı silmek yeter.
export const PLAYLIST = [
  "kimkim", "tahta", "devre",
  "yalanci", "rulet",
  "c4", "ortalama",
  "projektor",
  "kacis",
];
// Oyun türleri (istatistik/etiket için)
export const TUR = { kimkim: "telefon", tahta: "telefon", yalanci: "telefon", devre: "beceri", rulet: "olum", c4: "olum", ortalama: "secim", projektor: "olum", kacis: "kacis" };
export const RESULT_TIME = 10; // her oyundan sonra sonuç ekranı (sn)
// Maç sonu tablosunda sütun başlığı olarak kısa oyun adları
export const SHORT = { tahta: "TAHTA", devre: "DEVRE", kimkim: "KİM KİM", yalanci: "YALANCI", rulet: "RULET", c4: "C4", ortalama: "ORTALAMA", projektor: "PROJEKTÖR", kacis: "KAÇIŞ" };

const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];

export function mode(g) {
  return MODES[g.task];
}

function phaseList(g) {
  const p = mode(g).phases;
  return typeof p === "function" ? p(g) : p;
}

// Bu oyuncularla oynanabilir mi? (en az kişi, davetli oda gibi koşullar)
function playable(name, players, forced) {
  // yalnız bilinen oyun adları ("constructor", "__proto__" gibi adlar oyunu bozmasın)
  if (typeof name !== "string" || !PLAYLIST.includes(name)) return false;
  const m = MODES[name];
  if (!m) return false;
  if (players.length < (m.min || 2)) return false;
  // yeni oyun eski sürümlü bir oyuncuya gelmesin (istemci bilmediği oyunu açamaz): seçilse bile atlanır
  if ((m.surum || 1) > 1 && players.some((p) => (p.sv || 1) < m.surum)) return false;
  if (!forced && m.requires && !m.requires(players)) return false;
  return true;
}

// "Tüm oyunlar" listesi: oynanabilen her oyun, PLAYLIST sırasıyla baştan sona (Kim Kim? ilk, Büyük Kaçış en sonda).
// Karışık sıra istenmedi: oyuncular oyunları hep aynı sırayla, en baştan oynamak istiyor.
export function macListesi(players) {
  const ok = PLAYLIST.filter((x) => playable(x, players, false));
  const son = ok.filter((x) => MODES[x].final);
  return ok.filter((x) => !MODES[x].final).concat(son);
}

// players: [{id, name, cell, inv}]; games: lobide seçilen oyun(lar) (ör. ["rulet"]); verilirse yalnız onlar,
// verilen sırayla oynanır ve "davetli oda" gibi koşullar aranmaz, sadece en az oyuncu sayısı.
// Verilmezse ("Tüm oyunlar") macListesi: oynanabilen bütün oyunlar sırayla.
export function newGame(players, speed = 1, games = null) {
  // lobiden gelen liste: yalnız bilinen oyunlar, en çok 12 oyun (test için aynı oyun iki kez olabilir)
  if (Array.isArray(games)) games = games.filter((x) => typeof x === "string" && PLAYLIST.includes(x)).slice(0, 12);
  const forced = Array.isArray(games) && games.length > 0;
  let list = forced ? games.filter((x) => playable(x, players, true)) : macListesi(players);
  if (!list.length) list = ["tahta"];
  const g = {
    games: list, gi: -1, round: 0, rounds: list.length, task: "", phase: "baslangic", speed,
    players: players.map((p) => p.id), names: {}, cells: {}, sv: {}, score: {}, hits: {}, secret: {}, m: null, winner: 0,
    log: [], // oynanan her mini oyunun puan değişimleri: [{task, title, d: {id: delta}}]
  };
  for (const p of players) {
    g.names[p.id] = p.name;
    g.cells[p.id] = p.cell;
    g.sv[p.id] = p.sv || 1; // istemci sürümü (oyun içi kurallar eski sürüme uyumlu kalsın diye)
    g.score[p.id] = 0;
    g.hits[p.id] = 0;
  }
  return g;
}

export function duration(g, phase) {
  const d = phase === "sonuc" ? RESULT_TIME : mode(g).durations[phase];
  return Math.max(2, Math.round(d * g.speed));
}

// Kalan oyuncularla bu oyun hâlâ oynanabilir mi (bilinen oyun, en az kişi tutuyor)
function kalanOynanir(g, name) {
  if (typeof name !== "string" || !PLAYLIST.includes(name) || !MODES[name]) return false;
  return g.players.length >= (MODES[name].min || 2);
}

// Sıradaki oynanabilir oyunun listedeki yeri (-1: kalmadı). Oyuncu azaldıysa en az kişisi tutmayanlar atlanır.
function siraIndex(g) {
  for (let i = g.gi + 1; i < g.games.length; i++) if (kalanOynanir(g, g.games[i])) return i;
  return -1;
}

// Sıradaki oyunun modülü (tur sonu ekranındaki "sıradaki oyun" için); yoksa null.
export function siradaki(g) {
  const i = siraIndex(g);
  return i >= 0 ? MODES[g.games[i]] : null;
}

// Sıradaki mini oyuna geç (ilk aşama: anons). Oyuncu azaldıysa oynanamayan oyunlar atlanır.
// Oynanacak oyun kalmadıysa hiçbir şey değişmez, false döner (çağıran maçı bitirir).
export function startNext(g) {
  const i = siraIndex(g);
  if (i < 0) return false;
  g.gi = i;
  g.round = g.gi + 1;
  g.task = g.games[g.gi];
  g.secret = {};
  g.m = null;
  g.base = { ...g.score }; // oyun başındaki puanlar: oyun içinde anlık verilen puanlar da tura sayılsın
  mode(g).start(g);
  g.phase = phaseList(g)[0];
  return true;
}

export function nextPhase(g) {
  const list = phaseList(g);
  const i = list.indexOf(g.phase);
  return i >= 0 && i + 1 < list.length ? list[i + 1] : null;
}

export function onPhase(g, phase) {
  const m = mode(g);
  return m && m.onPhase ? m.onPhase(g, phase) : null;
}

export function onWake(g) {
  const m = mode(g);
  return m && m.onWake ? m.onWake(g) : null;
}

export function answer(g, id, v) {
  if (!g.players.includes(id) || !mode(g)) return null;
  return mode(g).answer(g, id, v);
}

// Oyunu bitirir, puanları işler. Dönen: { public, private }
export function resolve(g) {
  const res = mode(g).resolve(g);
  const d = {};
  for (const [id, p] of Object.entries(res.private)) {
    if (g.score[id] !== undefined) {
      g.score[id] += p.delta || 0;
      p.score = g.score[id];
      d[id] = p.delta || 0;
    }
  }
  // bu oyunun gerçek puan değişimi (anlık puanlar dahil): şimdiki puan - oyun başındaki puan
  if (g.base) for (const id of Object.keys(g.score)) if (g.base[id] !== undefined) d[id] = g.score[id] - g.base[id];
  if (!g.log) g.log = [];
  g.log.push({ task: g.task, title: SHORT[g.task] || mode(g).title, d });
  g.phase = "sonuc";
  if (g.m) g.m.wake = 0;
  return res;
}

export function isHidden(g) {
  return !!mode(g).hidden;
}

// Maç bitti mi (tüm oyunlar oynandı ya da 2'den az kişi kaldı)? Bittiyse kazananı seçer.
export function checkEnd(g) {
  if (siraIndex(g) >= 0 && g.players.length >= 2) return false;
  const pool = g.players.length ? g.players : Object.keys(g.score).map(Number);
  const top = Math.max(...pool.map((id) => g.score[id]));
  let best = pool.filter((id) => g.score[id] === top);
  if (best.length > 1) {
    const h = Math.max(...best.map((id) => g.hits[id] || 0));
    best = best.filter((id) => (g.hits[id] || 0) === h);
  }
  g.winner = pick(best);
  g.phase = "bitti";
  return true;
}

export function table(g) {
  const ids = Object.keys(g.score).map(Number);
  ids.sort((a, b) => (b === g.winner) - (a === g.winner) || g.score[b] - g.score[a] || (g.hits[b] || 0) - (g.hits[a] || 0));
  return ids.map((id) => ({ id, name: g.names[id], score: g.score[id], left: !g.players.includes(id) }));
}

// Maç sonu mesajı: kazanan, sıralı tablo (her satırda oyun oyun puanlar "p") ve oyun listesi.
export function overMsg(g) {
  const log = g.log || [];
  const rows = table(g).map((r) => ({ ...r, p: log.map((e) => e.d[r.id] || 0) }));
  return { t: "bitti", winner: g.winner, table: rows, rounds: log.length, oyunlar: log.map((e) => ({ task: e.task, ad: e.title })) };
}

// Oyuncu ayrıldı. Dönen: true ise şu anki mini oyun iptal (sıradakine geçilir).
export function removePlayer(g, id) {
  g.players = g.players.filter((x) => x !== id);
  return mode(g) ? mode(g).leave(g, id) : false;
}

// Mini oyunun kalan oyuncuları bitirdi mi (biri ayrıldıktan sonra beklemeden geçmek için; isteğe bağlı mode.tamam)
export function tamam(g) {
  const m = mode(g);
  return !!(m && m.tamam && m.tamam(g));
}
