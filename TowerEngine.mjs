// Battle Tower battles, on top of the Pokémon Showdown simulator. Runs in the
// TowerWorker thread (and in Node for the tests).
//
// A battle is rebuilt from what the save keeps: its seed, both teams and the
// list of choices made so far ("input"), so it can resume after a restart and
// always plays out the same way.

import { Showdown } from "Showdown.mjs";
import { Narrator } from "BattleText.mjs";
import * as AI from "TowerAI.mjs";

const battles = {};
const LEVEL = 50;
const FORMATS = { singles: "gen9towersingles", doubles: "gen9towerdoubles" };

function seedOf(n) {
  // Four 16-bit numbers, the format of Showdown's Gen 5 PRNG.
  let x = Math.floor(Math.abs(Number(n) || 1)) % 4294967296;
  const out = [];
  for (let i = 0; i < 4; i++) {
    x = (Math.imul(x ^ (x >>> 15), 2246822507) + 0x9e3779b9 + i) >>> 0;
    out.push(x & 0xffff);
  }
  return out.join(",");
}

// Log lines seen by player 1: exact HP for your Pokémon, percentages for the foe's.
function viewOf(lines) {
  const ch = Showdown.extractChannelMessages(lines.join("\n"), [1]);
  return ch[1] || [];
}

// Every Pokémon fights at Lv. 50, whatever its level outside the Tower.
function atLevel(packed) {
  const team = Showdown.Teams.unpack(packed) || [];
  team.forEach(function (set) { set.level = LEVEL; });
  return Showdown.Teams.pack(team);
}

function create(opts) {
  const errors = [];
  // Requests go through battle.p1.activeRequest; only the errors are needed from here.
  const send = function (type, data) {
    if (type !== "sideupdate") return;
    const lines = String(data).split("\n");
    if (lines[0] === "p1") lines.forEach(function (l) { if (/^\|error\|/.test(l)) errors.push(l.slice(7)); });
  };
  const battle = new Showdown.Battle({ formatid: FORMATS[opts.format] || FORMATS.singles, seed: seedOf(opts.seed), send: send });
  battle.setPlayer("p1", { name: "p1", team: atLevel(opts.p1.team) });
  battle.setPlayer("p2", { name: "p2", team: atLevel(opts.p2.team) });
  return {
    battle: battle,
    errors: errors,
    opts: opts,
    input: [],
    read: 0,
    ai: opts.p2.ai || 1,
    rand: AI.rng(opts.seed + ":ai"),
    memory: {},
    narrator: new Narrator([opts.p1.name, opts.p2.name]),
  };
}

function apply(b, who, choice) {
  if (who === "forfeit") {
    if (!b.battle.ended) b.battle.forceWin("p2");
    b.input.push("forfeit");
    return true;
  }
  const ok = b.battle.choose(who, choice);
  if (ok) b.input.push(who + " " + choice);
  return ok;
}

// Lets the trainer answer every request it has, until it is your turn or the battle is over.
function aiTurns(b) {
  for (let guard = 0; guard < 8; guard++) {
    const side = b.battle.p2;
    if (b.battle.ended || !side.activeRequest || side.activeRequest.wait || side.isChoiceDone()) return;
    let choice = AI.choose(b.battle, side, b.ai, b.rand, b.memory);
    if (!choice || !apply(b, "p2", choice)) {
      side.clearChoice && side.clearChoice();
      if (!apply(b, "p2", "default")) return;
    }
  }
}

// New log lines since last time, as steps for the window.
function news(b) {
  const lines = b.battle.log.slice(b.read);
  b.read = b.battle.log.length;
  return b.narrator.lines(viewOf(lines).join("\n"));
}

function monState(p, exact) {
  const species = p.species;
  return {
    species: species.name,
    base: Showdown.toID(species.baseSpecies),
    name: p.name,
    level: p.level,
    gender: p.gender,
    shiny: !!p.set.shiny,
    hp: exact ? p.hp : Math.ceil(100 * p.hp / Math.max(1, p.maxhp)),
    maxhp: exact ? p.maxhp : 100,
    status: p.status || "",
    fainted: !!p.fainted || p.hp <= 0,
    active: p.isActive,
    position: p.position,
    item: exact ? (p.getItem().name || "") : "",
    ability: exact ? (p.getAbility().name || "") : "",
    types: p.getTypes(),
    boosts: Object.assign({}, p.boosts),
    moves: exact ? p.moveSlots.map(function (m) {
      const d = Showdown.Dex.moves.get(m.id);
      return { id: m.id, name: m.move, pp: m.pp, maxpp: m.maxpp, type: d.type, category: d.category, power: d.basePower, accuracy: d.accuracy === true ? 0 : d.accuracy, target: d.target };
    }) : [],
    stats: exact ? { hp: p.maxhp, atk: p.getStat("atk", true, true), def: p.getStat("def", true, true), spa: p.getStat("spa", true, true), spd: p.getStat("spd", true, true), spe: p.getStat("spe", true, true) } : null,
  };
}

function state(b) {
  const battle = b.battle;
  const sides = [battle.p1, battle.p2].map(function (side, i) {
    const exact = i === 0;
    return {
      active: side.active.map(function (p) { return p && !p.fainted ? monState(p, exact) : null; }),
      party: side.pokemon.map(function (p) { return monState(p, exact); }),
      left: side.pokemonLeft,
      conditions: Object.keys(side.sideConditions),
    };
  });
  // Team Preview: the foe's whole team, as you see it before choosing.
  const preview = battle.p2.pokemon.map(function (p) {
    return { species: p.species.name, base: Showdown.toID(p.species.baseSpecies), level: p.level, gender: p.gender, shiny: !!p.set.shiny, item: "" };
  });
  return {
    turn: battle.turn,
    gameType: battle.gameType,
    weather: battle.field.effectiveWeather() || "",
    terrain: battle.field.terrain || "",
    sides: sides,
    preview: preview,
    ended: !!battle.ended,
    winner: battle.ended ? (battle.winner === "p1" ? 0 : battle.winner === "p2" ? 1 : -1) : null,
  };
}

// Type, category and power of your Pokémon's moves, for the FIGHT menu.
function moveInfo(b) {
  const out = {};
  for (const p of b.battle.p1.pokemon) {
    for (const m of p.moveSlots) {
      const d = Showdown.Dex.moves.get(m.id);
      out[m.id] = { type: d.type, category: d.category, power: d.basePower, accuracy: d.accuracy === true ? 0 : d.accuracy };
    }
  }
  return out;
}

function reply(b, steps, error) {
  const req = b.battle.p1.activeRequest;
  return {
    key: b.opts.key,
    steps: steps || [],
    moveInfo: moveInfo(b),
    request: req && !req.wait && !b.battle.p1.isChoiceDone() ? req : null,
    state: state(b),
    input: b.input.slice(),
    error: error || "",
  };
}

// opts: { key, format, seed, p1: { name, team }, p2: { name, team, ai }, input: [] }
export function start(opts) {
  const b = create(opts);
  battles[opts.key] = b;
  // Replay what already happened, then show the battle as it is now.
  for (const line of opts.input || []) {
    const i = line.indexOf(" ");
    if (!apply(b, i < 0 ? line : line.slice(0, i), i < 0 ? "" : line.slice(i + 1))) break;
  }
  aiTurns(b);
  const steps = news(b);
  return reply(b, (opts.input || []).length ? [] : steps);
}

export function choose(key, choice) {
  const b = battles[key];
  if (!b) return { key: key, error: "lost", steps: [] };
  if (b.battle.ended) return reply(b, []);
  b.errors.length = 0;
  if (!apply(b, "p1", choice)) {
    b.battle.p1.clearChoice && b.battle.p1.clearChoice();
    return reply(b, [], (b.errors.pop() || "That choice isn't possible.").replace(/^\[[^\]]*\]\s*/, ""));
  }
  aiTurns(b);
  return reply(b, news(b));
}

export function forfeit(key) {
  const b = battles[key];
  if (!b) return { key: key, error: "lost", steps: [] };
  apply(b, "forfeit", "");
  return reply(b, [{ t: "text", text: "You forfeited the battle." }, { t: "win", winner: 1, text: "" }]);
}

export function close(key) { delete battles[key]; return { key: key, closed: true, steps: [] }; }

export function version() { return Showdown.version; }

// Showdown export text -> packed team, with the problems found ("" when fine).
export function pack(text) {
  const team = Showdown.Teams.import(text);
  return team ? Showdown.Teams.pack(team) : "";
}
