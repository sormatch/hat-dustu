// Maç yöneticisi: bir oda = sırayla oynanan mini oyunlar (şimdilik Kara Tahta → Kısa Devre).
// Puanlar oyunlar boyunca toplanır; maç sonunda puan tablosu açılır. Kurallar modes/ altında.

import * as tahta from "./modes/tahta.js";
import * as devre from "./modes/devre.js";

export const MODES = { tahta, devre };
export const PLAYLIST = ["tahta", "devre"];
export const RESULT_TIME = 10; // her oyundan sonra sonuç ekranı (sn)

const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];

export function mode(g) {
  return MODES[g.task];
}

function phaseList(g) {
  const p = mode(g).phases;
  return typeof p === "function" ? p(g) : p;
}

// players: [{id, name, cell}]; games: test için oyun listesi (ör. ["devre"])
export function newGame(players, speed = 1, games = null) {
  const list = Array.isArray(games) && games.length ? games.filter((x) => MODES[x]) : PLAYLIST;
  const g = {
    games: list.length ? list : PLAYLIST, gi: -1, round: 0, rounds: 0, task: "", phase: "baslangic", speed,
    players: players.map((p) => p.id), names: {}, cells: {}, score: {}, hits: {}, secret: {}, m: null, winner: 0,
  };
  g.rounds = g.games.length;
  for (const p of players) {
    g.names[p.id] = p.name;
    g.cells[p.id] = p.cell;
    g.score[p.id] = 0;
    g.hits[p.id] = 0;
  }
  return g;
}

export function duration(g, phase) {
  const d = phase === "sonuc" ? RESULT_TIME : mode(g).durations[phase];
  return Math.max(2, Math.round(d * g.speed));
}

// Sıradaki mini oyuna geç (ilk aşama: anons).
export function startNext(g) {
  g.gi += 1;
  g.round = g.gi + 1;
  g.task = g.games[g.gi];
  g.secret = {};
  mode(g).start(g);
  g.phase = phaseList(g)[0];
}

// Şu anki aşamadan sonraki aşama; yoksa null (oyun sonucu hesaplanır).
export function nextPhase(g) {
  const list = phaseList(g);
  const i = list.indexOf(g.phase);
  return i >= 0 && i + 1 < list.length ? list[i + 1] : null;
}

export function answer(g, id, v) {
  if (!g.players.includes(id) || !mode(g)) return null;
  return mode(g).answer(g, id, v);
}

// Oyunu bitirir, puanları işler. Dönen: { public, private }
export function resolve(g) {
  const res = mode(g).resolve(g);
  for (const [id, p] of Object.entries(res.private)) {
    if (g.score[id] !== undefined) {
      g.score[id] += p.delta || 0;
      p.score = g.score[id];
    }
  }
  g.phase = "sonuc";
  return res;
}

export function isHidden(g) {
  return !!mode(g).hidden;
}

// Maç bitti mi (tüm oyunlar oynandı ya da 2'den az kişi kaldı)? Bittiyse kazananı seçer.
export function checkEnd(g) {
  if (g.gi + 1 < g.games.length && g.players.length >= 2) return false;
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

// Oyuncu ayrıldı. Dönen: true ise şu anki mini oyun iptal (sıradakine geçilir).
export function removePlayer(g, id) {
  g.players = g.players.filter((x) => x !== id);
  return mode(g) ? mode(g).leave(g, id) : false;
}
