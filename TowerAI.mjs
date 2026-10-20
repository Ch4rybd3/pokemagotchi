// Battle Tower trainers' AI. It reads the simulator's battle state (like the
// main-series AI, it knows your Pokémon's stats, but not what you will choose)
// and returns a Showdown choice such as "move 2", "move 1 2, switch 4" or "team 3124".
//
// Levels:
//   1  Novice: often picks a move at random, never switches on purpose.
//   2  Trained: usually picks its strongest move, sometimes a status move.
//   3  Expert: estimates damage, goes for KOs, uses status and setup moves when
//      it makes sense and switches out of bad matchups.
//   4  Master: like Expert, plus it switches out when it is about to be KO'd
//      by a faster foe, focuses one target in Doubles and keeps its allies safe.

const PHYSICAL_STATUS = { brn: 1 };
const SETUP_BOOSTS = ["atk", "def", "spa", "spd", "spe"];
const ABILITY_IMMUNE = {
  levitate: "Ground", flashfire: "Fire", wellbakedbody: "Fire", waterabsorb: "Water", stormdrain: "Water",
  dryskin: "Water", voltabsorb: "Electric", lightningrod: "Electric", motordrive: "Electric",
  sapsipper: "Grass", eartheater: "Ground",
};

// Small seeded RNG so a replay makes the same choices.
export function rng(seed) {
  let h = 2166136261;
  const text = String(seed);
  for (let i = 0; i < text.length; i++) { h ^= text.charCodeAt(i); h = Math.imul(h, 16777619); }
  return function () {
    h ^= h << 13; h ^= h >>> 17; h ^= h << 5;
    return (h >>> 0) / 4294967296;
  };
}

function hpShare(p) { return p.maxhp ? p.hp / p.maxhp : 0; }

// Stat with its boosts, without running ability/item events (those expect a move in progress).
function stat(p, name) { return p.getStat(name, false, true) * (name === "spe" && p.status === "par" ? 0.5 : 1); }

// Whether `a` moves before `b` (Trick Room turns it around).
function faster(battle, a, b) {
  const tr = !!battle.field.pseudoWeather["trickroom"];
  return tr ? stat(a, "spe") < stat(b, "spe") : stat(a, "spe") > stat(b, "spe");
}

function effectiveness(battle, moveType, target) {
  const dex = battle.dex;
  if (!dex.getImmunity(moveType, target)) return 0;
  const ability = target.getAbility().id;
  if (ABILITY_IMMUNE[ability] === moveType && !target.volatiles["gastroacid"]) return 0;
  if (moveType === "Ground" && target.hasItem && target.hasItem("airballoon")) return 0;
  const e = dex.getEffectiveness(moveType, target);
  let m = Math.pow(2, e);
  if (ability === "wonderguard" && m <= 1) return 0;
  return m;
}

// Rough damage (share of the target's current HP, 0..∞) of `move` from `user` on `target`.
export function estimate(battle, user, target, moveId) {
  const move = battle.dex.moves.get(moveId);
  if (!move.exists || move.category === "Status") return 0;
  if (move.ohko) return effectiveness(battle, move.type, target) && target.level <= user.level ? 0.3 : 0;
  let power = move.basePower || 0;
  if (move.damage === "level") return effectiveness(battle, move.type, target) ? user.level / Math.max(1, target.hp) : 0;
  if (typeof move.damage === "number") return move.damage / Math.max(1, target.hp);
  if (move.id === "superfang" || move.id === "ruination" || move.id === "naturesmadness") return 0.5;
  if (!power) power = 60;
  if (move.multihit) power *= Array.isArray(move.multihit) ? 3 : move.multihit;
  const type = move.type;
  const eff = effectiveness(battle, type, target);
  if (!eff) return 0;
  const physical = move.category === "Physical";
  const atk = stat(user, physical ? "atk" : "spa") * (physical && user.status === "brn" && user.getAbility().id !== "guts" ? 0.5 : 1);
  const def = stat(target, physical ? "def" : "spd");
  let dmg = Math.floor(Math.floor(Math.floor(2 * user.level / 5 + 2) * power * atk / Math.max(1, def)) / 50) + 2;
  if (user.hasType(type)) dmg *= user.getAbility().id === "adaptability" ? 2 : 1.5;
  dmg *= eff;
  const item = user.getItem().id;
  if (item === "choiceband" && physical) dmg *= 1.5;
  if (item === "choicespecs" && !physical) dmg *= 1.5;
  if (item === "lifeorb") dmg *= 1.3;
  if (item === "expertbelt" && eff > 1) dmg *= 1.2;
  const w = battle.field.effectiveWeather();
  if ((w === "sunnyday" || w === "desolateland") && type === "Fire") dmg *= 1.5;
  if ((w === "sunnyday" || w === "desolateland") && type === "Water") dmg *= 0.5;
  if ((w === "raindance" || w === "primordialsea") && type === "Water") dmg *= 1.5;
  if ((w === "raindance" || w === "primordialsea") && type === "Fire") dmg *= 0.5;
  const acc = move.accuracy === true ? 1 : (move.accuracy || 100) / 100;
  dmg *= 0.925 * acc;
  return dmg / Math.max(1, target.hp);
}

function foesOf(side) { return side.foe.active.filter(function (p) { return p && !p.fainted && p.hp > 0; }); }

// How much damage this Pokémon's best move does to `target`.
function bestHit(battle, user, target) {
  let best = 0;
  for (const slot of user.moveSlots) best = Math.max(best, estimate(battle, user, target, slot.id));
  return best;
}

// A matchup score for `mon` against the foes in front of it (higher is better).
function matchup(battle, mon, foes) {
  if (!foes.length) return 0;
  let s = 0;
  for (const f of foes) {
    const mine = Math.min(1.5, bestHit(battle, mon, f) * f.hp / Math.max(1, f.maxhp));
    const theirs = Math.min(1.5, bestHit(battle, f, mon) * mon.hp / Math.max(1, mon.maxhp));
    s += mine - theirs + (faster(battle, mon, f) ? 0.15 : 0);
  }
  return s / foes.length;
}

// Value of a status move used by `user` on `target`, about on the same scale as damage (1 = a KO).
function statusValue(battle, user, target, move, level, opts) {
  const id = move.id;
  const share = hpShare(user);
  const threatened = opts.threat >= 0.9;
  if (level <= 1) return 0.2;
  // Healing
  if (move.heal || ["recover", "roost", "softboiled", "slackoff", "moonlight", "morningsun", "synthesis",
                     "milkdrink", "shoreup", "rest", "wish"].includes(id)) {
    if (share > 0.6) return 0.02;
    return share < 0.35 ? 0.8 : 0.45;
  }
  if (id === "protect" || id === "detect" || id === "spikyshield" || id === "kingsshield" || id === "banefulbunker" || id === "silktrap") {
    if (opts.lastMove === id) return 0;
    // Masters stall a turn when they would go down, so their partner can act.
    if (level >= 4 && opts.doomed && battle.gameType === "doubles") return 0.6;
    return battle.gameType === "doubles" ? (level >= 3 ? 0.25 : 0.12) : (user.status === "tox" || opts.foeHurt ? 0.2 : 0.05);
  }
  // Setting up
  if (move.target === "self" && move.boosts) {
    const boosts = Object.keys(move.boosts).filter(function (k) { return move.boosts[k] > 0 && SETUP_BOOSTS.includes(k); });
    if (!boosts.length) return 0.05;
    const current = boosts.reduce(function (a, k) { return Math.max(a, user.boosts[k] || 0); }, 0);
    // Experts only set up when the foe needs three hits or more to KO them.
    if (current >= 2 || share < 0.55 || opts.threat >= (level >= 3 ? 0.45 : 0.9)) return 0.03;
    return level >= 3 ? 0.55 - current * 0.15 : 0.3;
  }
  if (!target) return 0.05;
  // Status conditions
  if (move.status) {
    if (target.status || !battle.dex.getImmunity(move.status, target)) return 0;
    if (move.status === "par" && target.hasType("Electric")) return 0;
    if ((move.status === "psn" || move.status === "tox") && (target.hasType("Poison") || target.hasType("Steel"))) return 0;
    if (move.status === "brn" && target.hasType("Fire")) return 0;
    if (move.type === "Electric" && !battle.dex.getImmunity("Electric", target)) return 0;
    if (move.flags && move.flags.powder && target.hasType("Grass")) return 0;
    if (move.status === "slp" && target.side.pokemon.some(function (p) { return p.status === "slp" && p !== target; })) return 0;
    let v = move.status === "slp" ? 0.55 : move.status === "tox" ? 0.4 : 0.35;
    if (move.status === "brn" && stat(target, "atk") > stat(target, "spa")) v += 0.2;
    if (move.status === "par" && stat(target, "spe") > stat(user, "spe")) v += 0.2;
    if (move.status === "brn" && stat(target, "atk") <= stat(target, "spa")) v -= 0.15;
    const acc = move.accuracy === true ? 1 : (move.accuracy || 100) / 100;
    // No time for that when the foe is about to KO us.
    if (level >= 3 && threatened) v *= 0.3;
    return (level >= 3 ? v : v * 0.7) * acc;
  }
  // Hazards and screens
  if (move.sideCondition && move.target === "foeSide") {
    if (target.side.sideConditions[move.sideCondition]) return 0;
    return target.side.pokemonLeft >= 2 ? 0.35 : 0.05;
  }
  if (move.sideCondition && move.target === "allySide") {
    if (user.side.sideConditions[move.sideCondition]) return 0;
    return 0.3;
  }
  if (move.volatileStatus === "confusion" && !target.volatiles["confusion"]) return 0.25;
  if (move.volatileStatus === "leechseed") return target.hasType("Grass") || target.volatiles["leechseed"] ? 0 : 0.3;
  if (move.volatileStatus === "taunt") return target.volatiles["taunt"] ? 0 : 0.15;
  if (move.boosts && move.target !== "self") return 0.15;
  if (move.weather) return battle.field.isWeather(move.weather) ? 0 : 0.3;
  if (move.pseudoWeather) return battle.field.pseudoWeather[move.pseudoWeather] ? 0 : 0.25;
  return 0.08;
}

function targetsFor(battle, side, slot, move) {
  // Which target numbers this move takes in Doubles: foes 1..n, allies -1..-n.
  const t = move.target;
  if (battle.gameType !== "doubles") return [0];
  if (t === "normal" || t === "any" || t === "adjacentFoe") {
    const out = [];
    side.foe.active.forEach(function (p, i) { if (p && !p.fainted) out.push(i + 1); });
    return out.length ? out : [1];
  }
  if (t === "adjacentAlly") return [-(slot === 0 ? 2 : 1)];
  if (t === "adjacentAllyOrSelf") return [-(slot + 1)];
  return [0];
}

const FIRST_TURN = { fakeout: 1, firstimpression: 1, matblock: 1 };

function scoreMove(battle, side, slot, user, slotData, target, level, rand, opts) {
  const move = battle.dex.moves.get(slotData.id);
  const foes = foesOf(side);
  let value = 0;
  // These fail after the Pokémon's first turn out (everybody knows that much).
  if (FIRST_TURN[move.id] && user.activeMoveActions > 0) return level === 1 ? rand() * 0.2 : 0;
  if (move.category === "Status") {
    const foe = target > 0 ? side.foe.active[target - 1] : foes[0];
    value = statusValue(battle, user, foe, move, level, opts);
  } else {
    const spread = battle.gameType === "doubles" && (move.target === "allAdjacentFoes" || move.target === "allAdjacent");
    const hits = target > 0 ? [side.foe.active[target - 1]] : spread ? foes : [foes[0]];
    for (const f of hits) {
      if (!f) continue;
      let d = estimate(battle, user, f, move.id) * (spread && hits.length > 1 ? 0.75 : 1);
      if (level >= 3 && d >= 1) {
        d = 1.2;
        if (move.priority > 0 && stat(f, "spe") > stat(user, "spe")) d += 0.4;
        if (opts.focus && opts.focus === f) d += 0.2;
      } else d = Math.min(d, 1.2);
      value += d;
    }
    if (spread && move.target === "allAdjacent") {
      const ally = side.active[1 - slot];
      if (ally && !ally.fainted) {
        const hurt = estimate(battle, user, ally, move.id) * 0.75;
        value -= level >= 3 ? hurt * 1.5 : hurt * 0.5;
      }
    }
    // Recharge, recoil and self-KO moves are worth less unless they finish the job.
    if (move.self && move.self.volatileStatus === "mustrecharge") value *= 0.7;
    if (move.selfdestruct) value *= hpShare(user) < 0.3 ? 0.9 : 0.4;
    if (move.recoil || move.mindBlownRecoil) value *= 0.92;
  }
  // Fake Out's flinch is worth a lot on the first turn, more in Doubles.
  if (move.id === "fakeout" && level >= 2) value += battle.gameType === "doubles" ? 0.35 : 0.15;
  // A faster foe that can KO us first: only priority moves are sure to happen.
  if (level >= 3 && opts.doomed && !(move.priority > 0)) value *= move.category === "Status" ? 0.2 : 0.45;
  if (level === 1) value = value * (0.5 + rand()) + rand() * 0.3;
  else if (level === 2) value *= 0.75 + rand() * 0.5;
  else value *= 0.9 + rand() * 0.2;
  return value;
}

// The best teammate to bring in, or 0 when none can come.
function bestSwitch(battle, side, level, rand, exclude) {
  const foes = foesOf(side);
  let best = 0, bestScore = -Infinity;
  side.pokemon.forEach(function (p, i) {
    if (i < side.active.length || p.fainted || p.hp <= 0 || (exclude && exclude.includes(i + 1))) return;
    const s = level <= 1 ? rand() : matchup(battle, p, foes) + rand() * 0.1;
    if (s > bestScore) { bestScore = s; best = i + 1; }
  });
  return { slot: best, score: bestScore };
}

function teamOrder(battle, side, level, rand, size) {
  const n = side.pokemon.length;
  let idx = [];
  for (let i = 0; i < n; i++) idx.push(i);
  if (level >= 2) {
    const foes = side.foe.pokemon;
    const score = idx.map(function (i) {
      const p = side.pokemon[i];
      let s = 0;
      for (const f of foes) s += Math.min(1.5, bestHit(battle, p, f)) - Math.min(1.5, bestHit(battle, f, p));
      return s / Math.max(1, foes.length) + (level === 2 ? rand() * 0.6 : rand() * 0.15);
    });
    idx.sort(function (a, b) { return score[b] - score[a]; });
  } else {
    // Novices bring their first Pokémon, the others in a random order.
    const rest = idx.slice(1);
    for (let i = rest.length - 1; i > 0; i--) { const j = Math.floor(rand() * (i + 1)); const t = rest[i]; rest[i] = rest[j]; rest[j] = t; }
    idx = [0].concat(rest);
  }
  return "team " + idx.slice(0, Math.max(size, 1)).map(function (i) { return i + 1; }).join("");
}

// The choice for `side` (a Side of the battle), given its current request.
export function choose(battle, side, level, rand, memory) {
  const req = side.activeRequest;
  if (!req || req.wait) return "";
  memory = memory || {};
  if (req.teamPreview) return teamOrder(battle, side, level, rand, req.maxChosenTeamSize || side.pokemon.length);

  if (req.forceSwitch) {
    const taken = [];
    const parts = req.forceSwitch.map(function (must) {
      if (!must) return "pass";
      const s = bestSwitch(battle, side, level, rand, taken);
      if (!s.slot) return "pass";
      taken.push(s.slot);
      return "switch " + s.slot;
    });
    return parts.join(", ");
  }

  const foes = foesOf(side);
  const focus = level >= 4 && battle.gameType === "doubles"
    ? foes.slice().sort(function (a, b) { return hpShare(a) - hpShare(b); })[0] : null;
  const taken = [];
  const parts = req.active.map(function (act, slot) {
    const user = side.active[slot];
    if (!user || user.fainted || (req.side && req.side.pokemon[slot] && /fnt/.test(req.side.pokemon[slot].condition))) return "pass";
    const threat = foes.reduce(function (a, f) { return Math.max(a, bestHit(battle, f, user)); }, 0);
    const foeHurt = foes.some(function (f) { return f.status === "tox" || f.status === "brn" || f.volatiles["leechseed"]; });
    const doomed = foes.some(function (f) { return faster(battle, f, user) && bestHit(battle, f, user) >= 1; });
    const opts = { threat: threat, focus: focus, lastMove: (memory.last || {})[user.name], foeHurt: foeHurt, doomed: doomed };
    const options = [];
    act.moves.forEach(function (m, i) {
      if (m.disabled || (m.pp !== undefined && m.pp <= 0 && !act.trapped)) return;
      const move = battle.dex.moves.get(m.id);
      for (const target of targetsFor(battle, side, slot, move)) {
        const v = scoreMove(battle, side, slot, user, { id: m.id }, target, level, rand, opts);
        options.push({ value: v, choice: "move " + (i + 1) + (target ? " " + target : ""), id: m.id });
      }
    });
    options.sort(function (a, b) { return b.value - a.value; });
    // Trained trainers don't always find the best move.
    let best = options[0] || null;
    if (level === 2 && options.length > 1 && options[1].value > 0 && rand() < 0.3) best = options[1];
    // Level 1 sometimes just picks any move.
    if (level === 1 && rand() < 0.35) {
      const usable = act.moves.map(function (m, i) { return m.disabled ? -1 : i; }).filter(function (i) { return i >= 0; });
      if (usable.length) {
        const i = usable[Math.floor(rand() * usable.length)];
        const move = battle.dex.moves.get(act.moves[i].id);
        const t = targetsFor(battle, side, slot, move);
        best = { value: 0, choice: "move " + (i + 1) + (t[0] ? " " + t[0] : ""), id: act.moves[i].id };
      }
    }
    // Switching out of a bad spot, to a teammate that takes the hit well.
    const canSwitch = !act.trapped && !act.maybeTrapped && level >= 3;
    if (canSwitch) {
      const sw = bestSwitch(battle, side, level, rand, taken);
      if (sw.slot) {
        const mon = side.pokemon[sw.slot - 1];
        const incoming = foes.reduce(function (a, f) { return Math.max(a, bestHit(battle, f, mon)); }, 0);
        const here = matchup(battle, user, foes);
        const hopeless = (!best || best.value < 0.15) && here < -0.5;
        const bad = level >= 4 && doomed && (!best || best.value < 0.9) && hpShare(user) > 0.25;
        const safe = incoming < (level >= 4 ? 0.5 : 0.6);
        if (safe && sw.score > here + 0.4 && (hopeless || bad) && rand() < (level >= 4 ? 0.85 : 0.5)) {
          taken.push(sw.slot);
          return "switch " + sw.slot;
        }
      }
    }
    if (!best) return "move 1";
    if (!memory.last) memory.last = {};
    memory.last[user.name] = best.id;
    return best.choice;
  });
  return parts.join(", ");
}
