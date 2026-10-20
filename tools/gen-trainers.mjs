#!/usr/bin/env node
// Builds Trainers.js: the Battle Tower's towers and the trainers you meet there.
//
// Usage: tools/gen-trainers.mjs [pokemon-showdown checkout]
// Needs Node.js, and a built Pokémon Showdown checkout (tools/gen-showdown.mjs
// leaves one in the temporary directory). Writes ../Trainers.js.
//
// Three kinds of trainers:
// - Gym Leaders, Elite Four and Champions of every region, written by hand in
//   tools/trainers/<region>.txt ("in the spirit" of their teams in the games).
// - Pokémon Radical Red's bosses and Ace Trainers, from a public dump of the
//   game's trainer data (Radical Red 4.1, Normal mode).
// - Generic trainers (Youngster, Ace Trainer…), made here with Showdown's Random
//   Battle sets, from the region's Pokémon.
// Every trainer gets a fixed difficulty rating (1 to 10) and an AI level (1 to 4).

import fs from 'fs';
import os from 'os';
import path from 'path';
import { createRequire } from 'module';

const ROOT = path.dirname(path.dirname(new URL(import.meta.url).pathname));
const OUT = path.join(ROOT, 'Trainers.js');
const RR_URL = 'https://gist.githubusercontent.com/Rudo2204/7f9e4a3ceaf077d623d3c37b1f921601/raw/e6c75faf6396f2562e1a6d7e6ca6ccf1805e180d/all_radical_red_trainer_sets_4_1_normal_mode_no_mingrind.txt';

const ps = path.resolve(process.argv[2] || path.join(os.tmpdir(), 'pokemagotchi-showdown'));
const req = createRequire(path.join(ps, 'package.json'));
const { Dex, toID } = req('./dist/sim/dex.js');
const { Teams } = req('./dist/sim/teams.js');

// Species the plugin can draw (pokemon-colorscripts sprites, Gen 1 to 8).
const plugin = fs.readFileSync(path.join(ROOT, 'Dex.js'), 'utf8');
const SLUGS = new Set(Object.keys(JSON.parse(/^var species = (\{.*\})$/m.exec(plugin)[1])).map(s => toID(s)));
function drawable(species) { return SLUGS.has(toID(species.baseSpecies)); }

const warnings = [];

// How well trained the trainers' Pokémon are, by tier: IVs in every stat, and the
// EVs of sets that don't give their own. This is what makes the tiers climb:
// the same species is a lot tougher with 31 IVs and EVs than without.
// `scale` shrinks the EVs a set gives itself (the Elite Four's and Champions' 252s).
// Tuned with tools/ simulations so that a sensible team of yours wins about 90%,
// 80%, 70% and 60% of its battles in the four tiers, and less at Radical Red.
const TRAINING = {
  generic: { 1: { iv: 20, ev: 0 }, 2: { iv: 12, ev: 0 }, 3: { iv: 10, ev: 0 }, 4: { iv: 16, ev: 0 } },
  named: { 1: { iv: 16, ev: 0 }, 2: { iv: 16, ev: 0 }, 3: { iv: 12, ev: 0, scale: 0.2 }, 4: { iv: 16, ev: 0, scale: 0.35 } },
  rr: { 1: { iv: 28, scale: 0.6 }, 2: { iv: 8, scale: 0.1 }, 3: { iv: 12, scale: 0.15 } },
};
function train(set, t, own) {
  set.ivs = { hp: t.iv, atk: t.iv, def: t.iv, spa: t.iv, spd: t.iv, spe: t.iv };
  if (own && t.scale !== undefined) {
    for (const k in set.evs) set.evs[k] = Math.floor((set.evs[k] || 0) * t.scale / 4) * 4;
  } else if (!own && t.ev !== undefined) {
    set.evs = { hp: t.ev, atk: t.ev, def: t.ev, spa: t.ev, spd: t.ev, spe: t.ev };
  }
  return set;
}
function warn(msg) { warnings.push(msg); }

// ---- Towers ----

const REGIONS = [
  { id: 'kanto', name: 'Kanto', dex: [1, 151] },
  { id: 'johto', name: 'Johto', dex: [152, 251] },
  { id: 'hoenn', name: 'Hoenn', dex: [252, 386] },
  { id: 'sinnoh', name: 'Sinnoh', dex: [387, 493] },
  { id: 'unova', name: 'Unova', dex: [494, 649] },
  { id: 'kalos', name: 'Kalos', dex: [650, 721] },
  { id: 'alola', name: 'Alola', dex: [722, 809] },
  { id: 'galar', name: 'Galar', dex: [810, 905] },
];
const TIERS = [
  { name: 'Novice', stars: 1 }, { name: 'Ace', stars: 2 }, { name: 'Elite', stars: 3 }, { name: 'Master', stars: 4 },
];
const towers = REGIONS.map(r => ({ id: r.id, name: r.name + ' Tower', region: r.name, tiers: TIERS, unlock: '' }));
towers.push({ id: 'radical-red', name: 'Radical Red Tower', region: 'Radical Red',
              tiers: [{ name: 'Kanto League', stars: 4 }, { name: 'Johto Leaders', stars: 5 }, { name: 'Rematch', stars: 5 }],
              unlock: 'master' });

// ---- Sets ----

const trainers = {};
function add(id, t) {
  if (trainers[id]) throw new Error('duplicate trainer ' + id);
  trainers[id] = t;
}

// Checks a set against Showdown's data; drops what doesn't exist.
function clean(set, where) {
  const species = Dex.species.get(set.species);
  if (!species.exists) { warn(`${where}: unknown species ${set.species}`); return null; }
  if (!drawable(species)) { warn(`${where}: no sprite for ${species.name}, left out`); return null; }
  set.species = species.name;
  set.name = set.name || species.baseSpecies;
  set.moves = (set.moves || []).filter(m => {
    const mv = Dex.moves.get(m);
    if (!mv.exists) warn(`${where}: ${species.name}: unknown move ${m}`);
    return mv.exists;
  }).map(m => Dex.moves.get(m).name);
  if (!set.moves.length) { warn(`${where}: ${species.name} has no moves`); return null; }
  if (set.ability && !Dex.abilities.get(set.ability).exists) { warn(`${where}: ${species.name}: unknown ability ${set.ability}`); set.ability = ''; }
  if (!set.ability) set.ability = species.abilities[0];
  if (set.item && !Dex.items.get(set.item).exists) { warn(`${where}: ${species.name}: unknown item ${set.item}`); set.item = ''; }
  if (set.item && /Z$|ium Z$/.test(Dex.items.get(set.item).name) && Dex.items.get(set.item).zMove) set.item = '';
  set.level = 50;
  delete set.teraType;
  delete set.role;
  delete set.speciesId;
  delete set.gigantamax;
  return set;
}

// Learnable in any generation (a gentle check for the hand-written teams).
function learnable(species, moveId) {
  let s = Dex.species.get(species);
  const seen = new Set();
  while (s && s.exists && !seen.has(s.id)) {
    seen.add(s.id);
    const ls = Dex.species.getLearnsetData(s.id);
    if (ls && ls.learnset && ls.learnset[moveId]) return true;
    const base = s.changesFrom || s.baseSpecies;
    if (base && base !== s.name && Dex.species.get(base).id !== s.id) { s = Dex.species.get(base); continue; }
    s = s.prevo ? Dex.species.get(s.prevo) : null;
  }
  return false;
}

function packTeam(sets) { return Teams.pack(sets); }

// ---- Hand-written teams ----
// tools/trainers/<region>.txt:
//   == Class / Name | tier 1 | rating 2 | ai 1 [| boss] [| singles|doubles]
//   Species @ Item | Ability | Nature | EVs | Move, Move, Move, Move
// Empty fields are fine; "#" starts a comment.

function parseLine(line, where) {
  const f = line.split('|').map(s => s.trim());
  const [speciesItem, ability, nature, evs, moves] = f;
  const [species, item] = speciesItem.split('@').map(s => s.trim());
  const set = { species, item: item || '', ability: ability || '', nature: nature || '', moves: (moves || '').split(',').map(s => s.trim()).filter(Boolean),
                evs: { hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0 }, ivs: { hp: 31, atk: 31, def: 31, spa: 31, spd: 31, spe: 31 }, ownEvs: !!evs };
  if (evs) {
    for (const part of evs.split('/')) {
      const m = /^\s*(\d+)\s+(HP|Atk|Def|SpA|SpD|Spe)\s*$/i.exec(part);
      if (!m) { warn(`${where}: bad EVs "${evs}"`); continue; }
      set.evs[{ hp: 'hp', atk: 'atk', def: 'def', spa: 'spa', spd: 'spd', spe: 'spe' }[m[2].toLowerCase()]] = Number(m[1]);
    }
  }
  if (set.nature && !Dex.natures.get(set.nature).exists) { warn(`${where}: bad nature ${set.nature}`); set.nature = ''; }
  return set;
}

function readHandWritten(region) {
  const file = path.join(ROOT, 'tools/trainers', region.id + '.txt');
  if (!fs.existsSync(file)) { warn(`missing ${file}`); return; }
  let current = null;
  const flush = () => {
    if (!current) return;
    const t = TRAINING.named[current.tier];
    const sets = current.sets.map(s => {
      const own = s.ownEvs;
      delete s.ownEvs;
      return clean(train(s, t, own), current.id);
    }).filter(Boolean);
    sets.forEach(s => {
      // (Smeargle can Sketch anything.)
      if (toID(s.species) !== 'smeargle') s.moves.forEach(m => { if (!learnable(s.species, toID(m))) warn(`${current.id}: ${s.species} can't learn ${m}`); });
      const sp = Dex.species.get(s.species);
      const abilities = Object.values(sp.abilities);
      if (s.ability && !abilities.includes(Dex.abilities.get(s.ability).name)) warn(`${current.id}: ${s.species} doesn't have ${s.ability}`);
    });
    if (sets.length < 3) warn(`${current.id}: only ${sets.length} Pokémon`);
    add(current.id, [current.name, current.cls, region.id, current.tier, current.rating, current.ai, current.boss ? 1 : 0,
                     packTeam(sets), current.format]);
    current = null;
  };
  fs.readFileSync(file, 'utf8').split('\n').forEach((raw, n) => {
    const line = raw.replace(/#.*$/, '').trim();
    if (!line) return;
    const where = `${region.id}.txt:${n + 1}`;
    if (line.startsWith('==')) {
      flush();
      const f = line.slice(2).split('|').map(s => s.trim());
      // "Gym Leader / Lt. Surge": class, then name.
      const [cls, name] = f[0].split('/').map(s => s.trim());
      const opts = {};
      f.slice(1).forEach(x => { const m = /^(\w+)\s*(\d*)$/.exec(x); if (m) opts[m[1]] = m[2] ? Number(m[2]) : true; });
      current = { id: region.id + '-' + toID(name), cls: cls, name: name, tier: opts.tier || 1, rating: opts.rating || 1,
                  ai: opts.ai || 1, boss: !!opts.boss, format: opts.singles ? 's' : opts.doubles ? 'd' : '', sets: [] };
      if (!opts.tier || !opts.rating || !opts.ai) warn(`${where}: tier, rating and ai are required`);
      return;
    }
    if (!current) { warn(`${where}: set outside of a trainer`); return; }
    current.sets.push(parseLine(line, where));
  });
  flush();
}

// ---- Radical Red ----
// Which trainers of the dump become Tower trainers: id -> [tier, rating, ai, boss].
const RR_PICKS = {
  // Kanto's last Gym Leaders, the Elite Four and the Champion, first time around
  '0x1a2': [1, 8, 4, 0], '0x1a4': [1, 8, 4, 0], '0x1a3': [1, 8, 4, 0], '0x15e': [1, 8, 4, 1], '0x15d': [1, 8, 4, 0],
  '0x19a': [1, 8, 4, 0], '0x19b': [1, 8, 4, 0], '0x19c': [1, 8, 4, 0], '0x19d': [1, 8, 4, 1],
  '0x2e4': [1, 8, 4, 1], '0x1b0': [1, 8, 4, 0],
  // Post-game: Johto Gym Leaders and the Champion at full strength
  '0x2b': [2, 9, 4, 0], '0x4b': [2, 9, 4, 0], '0x4c': [2, 9, 4, 0], '0x1c': [2, 9, 4, 0],
  '0x13d': [2, 9, 4, 0], '0x40': [2, 9, 4, 0], '0x4f': [2, 9, 4, 0], '0x26': [2, 9, 4, 1],
  '0x1b6': [2, 9, 4, 1],
  // The Elite Four rematches and Professor Oak
  '0x4d': [3, 10, 4, 0], '0x50': [3, 10, 4, 0], '0x53': [3, 10, 4, 0], '0x56': [3, 10, 4, 1],
  '0xc8': [3, 10, 4, 1], '0x27': [3, 10, 4, 0],
};

// Radical Red adds its own moves, Mega Stones and Sevii forms that Showdown
// doesn't know: use the closest official ones (unknown Mega Stones are dropped).
const RR_FIXES = [
  [/ \((?:Gender unknown|Genderless)\)/g, ''], [/ @ None$/gm, ''],
  [/^(\S+?)-Sevii\b/gm, '$1'], [/Kangaskanite/g, 'Kangaskhanite'], [/Blastoisnite/g, 'Blastoisinite'],
  [/^- Drain Kiss$/gm, '- Draining Kiss'], [/^- Aqua Fang$/gm, '- Liquidation'],
  [/^- Dark Hole$/gm, '- Dark Pulse'], [/^- Draco Barrage$/gm, '- Draco Meteor'],
  [/^Ability: Quill Rush$/gm, 'Ability: Overgrow'], [/^Ability: As One\n/gm, ''], [/Rusty Sword/g, 'Rusted Sword'], [/Charzardite/g, 'Charizardite'],
  [/ @ (X Attack|Hyper Potion|Ability Pill|Green Shard|Full Restore|Potion|Super Potion)$/gm, ''],
];

async function radicalRed() {
  const cache = path.join(os.tmpdir(), 'pokemagotchi-rr41.txt');
  if (!fs.existsSync(cache)) {
    console.error('downloading the Radical Red trainer dump');
    const res = await fetch(RR_URL);
    if (!res.ok) throw new Error('download failed: ' + res.status);
    fs.writeFileSync(cache, await res.text());
  }
  let text = fs.readFileSync(cache, 'utf8');
  for (const [re, by] of RR_FIXES) text = text.replace(re, by);
  const blocks = text.split(/\n(?=[^\n]+\(id: 0x[0-9a-f]+\)\n)/);
  const aces = [];
  const seen = {};
  for (const block of blocks) {
    const head = /^(.+?)\s*\(id: (0x[0-9a-f]+)\)\n([\s\S]*)$/.exec(block);
    if (!head) continue;
    const [, title, hex, body] = head;
    const pick = RR_PICKS[hex];
    const isAce = /^Ace Trainer/.test(title);
    if (!pick && !isAce) continue;
    // Showdown's importer doesn't know "Level: Max Level" or the "Type:" lines.
    const sets = Teams.import(body.replace(/^={3,}.*\n?/gm, '').replace(/^(Level|Type):.*\n/gm, '').trim()) || [];
    const levels = (body.match(/^Level: (\d+)/gm) || []).map(l => Number(l.slice(7)));
    const team = sets.map(s => s).filter(Boolean);
    const words = title.trim().split(/\s+/);
    const name = words.pop();
    const cls = words.join(' ');
    const trained = tier => team.map(s => clean(train(JSON.parse(JSON.stringify(s)), TRAINING.rr[tier], true), 'RR ' + title)).filter(Boolean);
    if (pick) {
      const sets = trained(pick[0]);
      if (sets.length < 3) continue;
      let id = 'rr-' + toID(name);
      seen[id] = (seen[id] || 0) + 1;
      if (seen[id] > 1) id += seen[id];
      add(id, [name, cls, 'radical-red', pick[0], pick[1], pick[2], pick[3], packTeam(sets), '']);
    } else {
      const lv = levels.length ? levels.reduce((a, b) => a + b, 0) / levels.length : 100;
      aces.push({ name, cls, lv, trained });
    }
  }
  // Ace Trainers fill the tiers between the bosses, by how far into the game they are.
  aces.sort((a, b) => a.lv - b.lv);
  aces.forEach((a, i) => {
    if (a.lv < 55) return;                       // early-game Ace Trainers are too easy for this tower
    const tier = a.lv < 75 ? 1 : a.lv < 84 ? 2 : 3;
    const rating = tier === 1 ? 8 : tier === 2 ? 9 : 10;
    const sets = a.trained(tier);
    if (sets.length < 3) return;
    add('rr-ace-' + (i + 1), [a.name, a.cls, 'radical-red', tier, rating, 4, 0, packTeam(sets), '']);
  });
}

// ---- Generic trainers ----

// Generic classes by tier, and the classes that go with a type (picked when
// at least two of the team's Pokémon have it).
const CLASSES = {
  1: ['Youngster', 'Lass', 'Picnicker', 'Camper', 'School Kid'],
  2: ['Beauty', 'Gentleman', 'Pokéfan', 'Rich Boy', 'Lady'],
  3: ['Ace Trainer', 'Veteran', 'Expert', 'Pokémon Ranger'],
  4: ['Ace Trainer', 'Veteran', 'Expert', 'Battle Master'],
};
const TYPE_CLASSES = {
  Bug: ['Bug Catcher', 'Bug Maniac'], Water: ['Fisherman', 'Swimmer'], Rock: ['Hiker'], Ground: ['Hiker', 'Ruin Maniac'],
  Fighting: ['Black Belt', 'Battle Girl'], Psychic: ['Psychic'], Flying: ['Bird Keeper'], Ghost: ['Hex Maniac', 'Channeler'],
  Dark: ['Punk', 'Hex Maniac'], Dragon: ['Dragon Tamer'], Electric: ['Rocker', 'Guitarist'], Fire: ['Kindler', 'Fire Breather'],
  Grass: ['Aroma Lady', 'Gardener'], Ice: ['Skier', 'Boarder'], Poison: ['Biker', 'Scientist'], Steel: ['Worker', 'Scientist'],
  Fairy: ['Fairy Tale Girl', 'Furisode Girl'], Normal: [],
};
const NAMES = {
  f: ['Cindy', 'Dana', 'Emma', 'Gwen', 'Mia', 'Olga', 'Rosa', 'Tara', 'Vera', 'Xena', 'Zoe', 'Bea', 'Dina', 'Faye', 'Hana',
      'Jade', 'Lila', 'Nora', 'Pia', 'Uma', 'Yara', 'Alba', 'Cleo', 'Elsa', 'Gaia', 'Kira', 'Lena', 'Maya', 'Sofia', 'Ines'],
  m: ['Joey', 'Ben', 'Tim', 'Leo', 'Nico', 'Pete', 'Ugo', 'Wes', 'Yuri', 'Abel', 'Cole', 'Eli', 'Gus', 'Ivan', 'Kai',
      'Milo', 'Owen', 'Ravi', 'Theo', 'Vito', 'Zack', 'Bram', 'Dex', 'Finn', 'Hugo', 'Jon', 'Marco', 'Paul', 'Rémi', 'Sven'],
};
NAMES.n = NAMES.f.concat(NAMES.m);
const FEMALE = new Set(['Lass', 'Picnicker', 'Battle Girl', 'Beauty', 'Hex Maniac', 'Lady', 'Aroma Lady', 'Fairy Tale Girl', 'Furisode Girl', 'Swimmer', 'Skier']);
const MALE = new Set(['Youngster', 'Bug Catcher', 'Camper', 'Fisherman', 'Hiker', 'Black Belt', 'Gentleman', 'Bird Keeper', 'Rocker',
  'Rich Boy', 'Punk', 'Biker', 'Worker', 'Guitarist', 'Kindler', 'Fire Breather', 'Boarder', 'Bug Maniac', 'Ruin Maniac', 'Channeler']);
// How many generic trainers per region and tier.
const GENERIC = { singles: 12, doubles: 8 };
const TEAM_SIZE = { 1: [3, 4], 2: [4, 4], 3: [4, 5], 4: [5, 6] };
const RESTRICTED = new Set();
for (const s of Dex.species.all()) if (s.tags.includes('Restricted Legendary') || s.tags.includes('Mythical')) RESTRICTED.add(s.id);

function seeded(seed) {
  let h = 2166136261;
  for (const c of String(seed)) { h ^= c.charCodeAt(0); h = Math.imul(h, 16777619); }
  return () => { h ^= h << 13; h ^= h >>> 17; h ^= h << 5; return (h >>> 0) / 4294967296; };
}

// One set per species and format, from the newest Random Battle that has it.
const generators = [
  ['gen9randombattle', false], ['gen9randomdoublesbattle', true], ['gen9babyrandombattle', false],
  ['gen8randombattle', false], ['gen7randombattle', false],
].map(([id, doubles]) => ({ id, doubles, gen: Teams.getGenerator(id, [7, 7, 7, 7]) }));

function poolFor(g) { return Object.keys((g.doubles ? g.gen.randomDoublesSets : g.gen.randomSets) || g.gen.randomData || {}); }

const singlesPool = {}, doublesPool = {}, babyPool = {};
for (const g of generators) {
  for (const id of poolFor(g)) {
    const species = Dex.species.get(id);
    if (!species.exists || !drawable(species) || RESTRICTED.has(species.id)) continue;
    if (species.isNonstandard === 'CAP') continue;
    let set;
    try {
      set = g.gen.randomSet(g.gen.dex.species.get(id), {}, false, g.doubles);
    } catch (e) { continue; }
    if (!set) continue;
    const strength = set.level || 90;
    const item = Dex.items.get(set.item || '');
    if (item.megaStone || item.zMove || item.onPrimal) set.item = 'Leftovers';
    const entry = { set, strength, num: species.num };
    if (g.id === 'gen9babyrandombattle') { if (!babyPool[species.id]) babyPool[species.id] = entry; }
    else if (g.doubles) { if (!doublesPool[species.id]) doublesPool[species.id] = entry; }
    else if (!singlesPool[species.id]) singlesPool[species.id] = entry;
  }
}

function tierOf(entry, baby) {
  if (baby) return 1;
  const l = entry.strength;
  return l >= 92 ? 1 : l >= 87 ? 2 : l >= 82 ? 3 : 4;
}

function genericTrainers(region, format) {
  const rand = seeded(region.id + ':' + format);
  const inRegion = e => e.num >= region.dex[0] && e.num <= region.dex[1];
  const main = format === 'doubles' ? Object.assign({}, singlesPool, doublesPool) : singlesPool;
  const byTier = { 1: [], 2: [], 3: [], 4: [] };
  for (const id in babyPool) byTier[1].push(babyPool[id]);
  for (const id in main) byTier[tierOf(main[id], false)].push(main[id]);
  for (let tier = 1; tier <= 4; tier++) {
    // The region's own Pokémon, plus some from elsewhere when it has too few.
    let pool = byTier[tier].filter(inRegion);
    const others = byTier[tier].filter(e => !inRegion(e));
    if (tier === 4) pool = pool.concat(byTier[3].filter(inRegion).filter(e => e.strength <= 84));
    if (pool.length < 12) pool = pool.concat(others.sort(() => rand() - 0.5).slice(0, 12 - pool.length));
    const count = GENERIC[format];
    for (let i = 0; i < count; i++) {
      const [lo, hi] = TEAM_SIZE[tier];
      const size = Math.max(format === 'doubles' ? 4 : 3, lo + Math.floor(rand() * (hi - lo + 1)));
      const picks = [];
      const used = new Set(), items = new Set();
      let guard = 0;
      while (picks.length < size && guard++ < 200) {
        const e = pool[Math.floor(rand() * pool.length)];
        const sp = Dex.species.get(e.set.species);
        if (used.has(sp.baseSpecies)) continue;
        used.add(sp.baseSpecies);
        const set = JSON.parse(JSON.stringify(e.set));
        // Item Clause: one of each item per team.
        if (set.item && items.has(set.item)) set.item = ['Sitrus Berry', 'Leftovers', 'Lum Berry', 'Focus Sash', 'Shell Bell'].find(x => !items.has(x)) || '';
        if (set.item) items.add(set.item);
        const c = clean(train(set, TRAINING.generic[tier], false), `${region.id} generic`);
        if (c) picks.push({ set: c, strength: e.strength });
      }
      const avg = picks.reduce((a, p) => a + p.strength, 0) / picks.length;
      // Rating: two steps per tier, the stronger half of the tier gets the upper one.
      const strong = tier === 1 ? picks.filter(p => !babyPool[toID(p.set.species)]).length > picks.length / 2
        : avg < { 2: 89.5, 3: 84.5, 4: 79 }[tier];
      const rating = tier * 2 - 1 + (strong ? 1 : 0);
      const ai = tier === 1 ? 1 : tier === 2 ? 2 : 3;
      const typeCount = {};
      picks.forEach(p => Dex.species.get(p.set.species).types.forEach(t => { typeCount[t] = (typeCount[t] || 0) + 1; }));
      const themed = Object.keys(typeCount).filter(t => typeCount[t] >= 2 && (TYPE_CLASSES[t] || []).length)
        .sort((a, b) => typeCount[b] - typeCount[a]);
      const choices = themed.length && tier <= 3 ? TYPE_CLASSES[themed[0]] : CLASSES[tier];
      const cls = choices[Math.floor(rand() * choices.length)];
      const names = NAMES[FEMALE.has(cls) ? 'f' : MALE.has(cls) ? 'm' : 'n'];
      const name = names[Math.floor(rand() * names.length)];
      add(`${region.id}-${format[0]}${tier}-${i + 1}`,
          [name, cls, region.id, tier, rating, ai, 0, packTeam(picks.map(p => p.set)), format === 'doubles' ? 'd' : 's']);
    }
  }
}

// ---- Build ----

for (const r of REGIONS) {
  readHandWritten(r);
  genericTrainers(r, 'singles');
  genericTrainers(r, 'doubles');
}
await radicalRed();

const lines = [];
lines.push('.pragma library', '');
lines.push('// Generated by tools/gen-trainers.mjs: the Battle Tower\'s towers and trainers.');
lines.push('// Gym Leaders, Elite Four and Champions are written by hand in tools/trainers/;');
lines.push('// Radical Red trainers come from a dump of Pokémon Radical Red 4.1 (see');
lines.push('// THIRD_PARTY_NOTICES.md); generic trainers use Pokémon Showdown\'s Random Battle sets.');
lines.push('');
lines.push('// { id, name, region, tiers: [{ name, stars }], unlock ("" = open, "master" = after any Master tier) }');
lines.push('var towers = ' + JSON.stringify(towers));
lines.push('');
lines.push('// id: [name, class, tower, tier (1..), rating (1..10), AI level (1..4), boss (1),');
lines.push('//      team (Showdown packed format), format ("" both, "s" Singles only, "d" Doubles only)]');
lines.push('var trainers = {');
const ids = Object.keys(trainers);
ids.forEach((id, i) => lines.push(JSON.stringify(id) + ':' + JSON.stringify(trainers[id]) + (i < ids.length - 1 ? ',' : '')));
lines.push('}');
fs.writeFileSync(OUT, lines.join('\n') + '\n');

const count = {};
for (const id of ids) { const t = trainers[id]; const k = t[2] + ' T' + t[3]; count[k] = (count[k] || 0) + 1; }
console.error(Object.entries(count).map(([k, v]) => k + ': ' + v).join(', '));
if (warnings.length) console.error(warnings.length + ' warnings:\n  ' + warnings.join('\n  '));
console.error(`wrote ${OUT} (${(fs.statSync(OUT).size / 1024).toFixed(0)} KB, ${ids.length} trainers)`);
