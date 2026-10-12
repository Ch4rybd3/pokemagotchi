.pragma library
.import "Battle.js" as Battle
.import "Info.js" as Info
.import "Moves.js" as Moves

// Battle engine for expeditions. Damage follows the Pokémon Showdown damage
// calculator (Gen 9 order of operations, 4096-based modifiers and rounding);
// the turn loop is a simplified version of the main-series one: everybody on
// the field acts each turn, by priority then Speed.
//
// Everything random goes through `rand`, a seeded RNG, so a battle replays
// the same way every time it is simulated.

// ---- Combatants ----
// { name, species, shiny, level, types, ability, weight, stats [HP..Spe], hp, maxhp,
//   moves [{ id, pp, max }], status "", sleep, toxic, boosts [_, Atk, Def, SpA, SpD, Spe, Acc, Eva],
//   confused, flinch, charging, recharge, seeded, flashFire, side, ... }

var STRUGGLE = 165
var TURN_LIMIT = 30
var BOOST_NAMES = ["", "Attack", "Defense", "Sp. Atk", "Sp. Def", "Speed", "accuracy", "evasiveness"]
var STATUS_NAMES = { par: "paralyzed", slp: "asleep", psn: "poisoned", tox: "badly poisoned", brn: "burned", frz: "frozen" }

// Moves whose power depends on the battle (power is empty in the data).
var FIXED = { 69: "level", 101: "level", 82: 40, 49: 20, 162: "half", 717: "half", 283: "endeavor", 149: "psywave" }
var OHKO = { 12: 1, 32: 1, 90: 1, 329: 1 }
var SELF_TARGETS = { 3: 1, 4: 1, 5: 1, 7: 1, 13: 1, 15: 1 }
var SPREAD_TARGETS = { 9: 1, 11: 1, 14: 1 }
var WEATHER_MOVES = { 240: "rain", 241: "sun", 201: "sand", 258: "hail", 883: "hail" }
var WEATHER_ABILITIES = { drizzle: "rain", drought: "sun", "sand-stream": "sand", "snow-warning": "hail" }
var EXPLODE = { 120: 1, 153: 1 }
var TEAM_CURE = { 215: 1, 312: 1 }
var TRANSFORM = 144
var LEECH_SEED = 73
var REST = 156
var FAKE_OUT = 252
var DREAM_EATER = 138
var SNORE = 173
var WEATHER_HEAL = { 234: 1, 235: 1, 236: 1 }   // Morning Sun, Synthesis, Moonlight

function moveData(id) {
  var m = Moves.moves[id]
  if (id === STRUGGLE || !m) return { id: STRUGGLE, name: "Struggle", type: "typeless", cat: 1, power: 50, acc: 0, pp: 1 }
  return { id: id, name: m[0], type: m[1], cat: m[2], power: m[3], acc: m[4], pp: m[5] }
}

function meta(id) {
  return Battle.moves[id] || [0, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, [], 0, 0]
}

function hasFlag(id, bit) { return (meta(id)[13] & bit) !== 0 }
var F_CONTACT = 1, F_CHARGE = 2, F_RECHARGE = 4, F_PUNCH = 8, F_SOUND = 16, F_BITE = 32
var F_PULSE = 64, F_BALLISTICS = 128, F_POWDER = 256

// ---- Showdown helpers ----

function pokeRound(n) { return n % 1 > 0.5 ? Math.ceil(n) : Math.floor(n) }
function OF32(n) { return n > 4294967295 ? n % 4294967296 : n }
function chainMods(mods) {
  var m = 4096
  for (var i = 0; i < mods.length; i++)
    if (mods[i] !== 4096) m = (m * mods[i] + 2048) >> 12
  return m
}
function applyMod(value, mod) { return pokeRound(OF32(value * mod) / 4096) }

function stageMult(stage) { return stage >= 0 ? (2 + stage) / 2 : 2 / (2 - stage) }
function accMult(stage) { return stage >= 0 ? (3 + stage) / 3 : 3 / (3 - stage) }

// ---- Types ----

function effectiveness(type, defender, moveId) {
  if (type === "typeless") return 1
  var row = Battle.types[type] || {}
  var mult = 1
  for (var i = 0; i < defender.types.length; i++) {
    var t = defender.types[i]
    var f = row[t] === undefined ? 1 : row[t]
    if (f === 0 && t === "ghost" && (type === "normal" || type === "fighting") && defender.foeScrappy) f = 1
    if (moveId === 573 && t === "water") f = 2      // Freeze-Dry
    mult *= f
  }
  return mult
}

function isGrounded(p) { return p.types.indexOf("flying") < 0 && p.ability !== "levitate" }

// ---- Stats ----

function speed(p, weather) {
  var s = Math.floor(p.stats[5] * stageMult(p.boosts[5]))
  if (p.status === "par" && p.ability !== "quick-feet") s = Math.floor(s / 2)
  if (p.status && p.ability === "quick-feet") s = Math.floor(s * 1.5)
  if ((weather === "rain" && p.ability === "swift-swim") || (weather === "sun" && p.ability === "chlorophyll")
      || (weather === "sand" && p.ability === "sand-rush") || (weather === "hail" && p.ability === "slush-rush")) s *= 2
  if (p.ability === "unburden" && p.unburden) s *= 2
  return s
}

// ---- Base power ----

function weightBp(hg) { return hg >= 2000 ? 120 : hg >= 1000 ? 100 : hg >= 500 ? 80 : hg >= 250 ? 60 : hg >= 100 ? 40 : 20 }

function basePower(move, user, target, ctx) {
  var id = move.id, bp = move.power || 0
  switch (id) {
  case 360: return Math.min(150, Math.floor(25 * speed(target, ctx.weather) / Math.max(1, speed(user, ctx.weather))) + 1) // Gyro Ball
  case 486: {                                                                                                        // Electro Ball
    var r = speed(user, ctx.weather) / Math.max(1, speed(target, ctx.weather))
    return r >= 4 ? 150 : r >= 3 ? 120 : r >= 2 ? 80 : r >= 1 ? 60 : 40
  }
  case 67: case 447: return weightBp(target.weight)                                                                  // Low Kick, Grass Knot
  case 484: case 535: {                                                                                              // Heavy Slam, Heat Crash
    var w = user.weight / Math.max(1, target.weight)
    return w >= 5 ? 120 : w >= 4 ? 100 : w >= 3 ? 80 : w >= 2 ? 60 : 40
  }
  case 284: case 323: case 820: return Math.max(1, Math.floor(150 * user.hp / user.maxhp))                            // Eruption, Water Spout, Dragon Energy
  case 175: case 179: {                                                                                              // Flail, Reversal
    var p = Math.floor(48 * user.hp / user.maxhp)
    return p <= 1 ? 200 : p <= 4 ? 150 : p <= 9 ? 100 : p <= 16 ? 80 : p <= 32 ? 40 : 20
  }
  case 216: return Math.max(1, Math.floor(user.happiness * 2.55 * 10 / 25))                                         // Return
  case 218: return Math.max(1, Math.floor((255 - user.happiness * 2.55) * 10 / 25))                                // Frustration
  case 462: case 378: return Math.max(1, Math.floor(120 * target.hp / target.maxhp))                                // Crush Grip, Wring Out
  case 500: case 681: return 20 + 20 * user.boosts.slice(1).reduce(function(a, b) { return a + Math.max(0, b) }, 0) // Stored Power, Power Trip
  case 222: return [10, 30, 50, 70, 90, 110, 150][Math.min(6, Math.floor(ctx.rand() * 7))]                          // Magnitude
  case 263: return user.status && user.status !== "slp" ? 140 : 70                                                 // Facade
  case 506: return target.status ? 130 : 65                                                                          // Hex
  case 474: return target.status === "psn" || target.status === "tox" ? 130 : 65                                  // Venoshock
  case 362: return target.hp * 2 <= target.maxhp ? 130 : 65                                                        // Brine
  case 512: return 110                                                                                               // Acrobatics: nobody holds an item
  case 358: return target.status === "slp" ? 140 : 70                                                              // Wake-Up Slap
  case 265: return target.status === "par" ? 140 : 70                                                              // Smelling Salts
  }
  return bp || 60
}

// ---- Damage (Showdown calc, Gen 9) ----
// Returns { min, max, avg, rolls(rand) } for one hit, or null when the move can't hit.

function isPhysical(move) { return move.cat === 1 }

function moveType(move, user) {
  var t = move.type
  if (user.ability === "normalize") return "normal"
  if (t === "normal" && move.id !== STRUGGLE) {
    if (user.ability === "aerilate") return "flying"
    if (user.ability === "pixilate") return "fairy"
    if (user.ability === "refrigerate") return "ice"
    if (user.ability === "galvanize") return "electric"
  }
  return t
}

function immune(move, type, user, target) {
  var a = target.ability
  if (user.ability === "mold-breaker" || user.ability === "teravolt" || user.ability === "turboblaze") a = ""
  if (type === "ground" && !isGrounded(target) && move.id !== 614) return "levitate"
  if (type === "fire" && a === "flash-fire") return "flash-fire"
  if (type === "water" && (a === "water-absorb" || a === "dry-skin" || a === "storm-drain")) return a
  if (type === "electric" && (a === "volt-absorb" || a === "lightning-rod" || a === "motor-drive")) return a
  if (type === "grass" && a === "sap-sipper") return a
  if (type === "ground" && a === "earth-eater") return a
  if (a === "soundproof" && hasFlag(move.id, F_SOUND)) return a
  if (a === "bulletproof" && hasFlag(move.id, F_BALLISTICS)) return a
  if (hasFlag(move.id, F_POWDER) && (target.types.indexOf("grass") >= 0 || a === "overcoat")) return "powder"
  return ""
}

function damage(move, user, target, ctx, opts) {
  opts = opts || {}
  var crit = !!opts.crit, spread = !!opts.spread
  var type = moveType(move, user)
  if (move.id !== STRUGGLE && immune(move, type, user, target)) return null
  target.foeScrappy = user.ability === "scrappy"
  var eff = move.id === STRUGGLE ? 1 : effectiveness(type, target, move.id)
  target.foeScrappy = false
  if (eff === 0) return null
  var ta = user.ability === "mold-breaker" ? "" : target.ability
  if (ta === "wonder-guard" && eff <= 1 && move.id !== STRUGGLE) return null

  // Fixed damage
  var fixed = FIXED[move.id]
  if (fixed !== undefined) {
    var d = fixed === "level" ? user.level : fixed === "half" ? Math.max(1, Math.floor(target.hp / 2))
          : fixed === "endeavor" ? Math.max(0, target.hp - user.hp)
          : fixed === "psywave" ? Math.max(1, Math.floor(user.level * 1)) : fixed
    return { min: d, max: d, avg: d, eff: eff, roll: function() { return d } }
  }

  // Base power, with ability boosts (chained like Showdown's bpMods)
  var bp = basePower(move, user, target, ctx)
  var bpMods = []
  if (user.ability === "technician" && bp <= 60) bpMods.push(6144)
  if (["aerilate", "pixilate", "refrigerate", "galvanize"].indexOf(user.ability) >= 0 && move.type === "normal" && type !== "normal") bpMods.push(4915)
  if (user.ability === "normalize") bpMods.push(4915)
  if (user.ability === "iron-fist" && hasFlag(move.id, F_PUNCH)) bpMods.push(4915)
  if (user.ability === "strong-jaw" && hasFlag(move.id, F_BITE)) bpMods.push(6144)
  if (user.ability === "mega-launcher" && hasFlag(move.id, F_PULSE)) bpMods.push(6144)
  if (user.ability === "tough-claws" && hasFlag(move.id, F_CONTACT)) bpMods.push(5325)
  if (user.ability === "punk-rock" && hasFlag(move.id, F_SOUND)) bpMods.push(5325)
  if (user.ability === "sheer-force" && hasSecondary(move.id)) bpMods.push(5325)
  if (user.ability === "reckless" && meta(move.id)[7] < 0) bpMods.push(4915)
  if (user.ability === "sand-force" && ctx.weather === "sand" && ["rock", "ground", "steel"].indexOf(type) >= 0) bpMods.push(5325)
  if (ta === "dry-skin" && type === "fire") bpMods.push(5120)
  if (ta === "heatproof" && type === "fire") bpMods.push(2048)
  bp = Math.max(1, pokeRound(bp * chainMods(bpMods) / 4096))

  // Attack and Defense, with stat stages (a crit ignores the bad ones)
  var phys = isPhysical(move)
  var ai = phys ? 1 : 3, di = phys ? 2 : 4
  if (move.id === 492) ai = 2                      // Body Press uses Defense
  var atkSource = move.id === 492 ? user : move.id === 251 ? target : user   // Foul Play uses the target's Attack
  var aStage = atkSource.boosts[ai], dStage = target.boosts[di]
  if (ta === "unaware") aStage = 0
  if (user.ability === "unaware") dStage = 0
  if (crit) { aStage = Math.max(0, aStage); dStage = Math.min(0, dStage) }
  var attack = Math.floor(atkSource.stats[ai] * stageMult(aStage))
  var defense = Math.floor(target.stats[di] * stageMult(dStage))
  if ([492, 251].indexOf(move.id) < 0) {
    var atMods = []
    if (phys && (user.ability === "huge-power" || user.ability === "pure-power")) atMods.push(8192)
    if (phys && user.ability === "guts" && user.status) atMods.push(6144)
    if (phys && user.ability === "hustle") atMods.push(6144)
    if (phys && user.ability === "gorilla-tactics") atMods.push(6144)
    if (!phys && user.ability === "solar-power" && ctx.weather === "sun") atMods.push(6144)
    if (user.hp * 3 <= user.maxhp && ((user.ability === "blaze" && type === "fire") || (user.ability === "torrent" && type === "water")
        || (user.ability === "overgrow" && type === "grass") || (user.ability === "swarm" && type === "bug"))) atMods.push(6144)
    if (user.flashFire && type === "fire") atMods.push(6144)
    if ((user.ability === "transistor" && type === "electric") || (user.ability === "dragons-maw" && type === "dragon")) atMods.push(5325)
    if (user.ability === "steelworker" && type === "steel") atMods.push(6144)
    if (user.ability === "water-bubble" && type === "water") atMods.push(8192)
    if (ta === "thick-fat" && (type === "fire" || type === "ice")) atMods.push(2048)
    if (ta === "water-bubble" && type === "fire") atMods.push(2048)
    attack = Math.max(1, pokeRound(attack * chainMods(atMods) / 4096))
  }
  var dfMods = []
  if (phys && ta === "fur-coat") dfMods.push(8192)
  if (phys && ta === "marvel-scale" && target.status) dfMods.push(6144)
  if (!phys && ctx.weather === "sand" && target.types.indexOf("rock") >= 0) dfMods.push(6144)
  if (phys && ctx.weather === "hail" && target.types.indexOf("ice") >= 0) dfMods.push(6144)
  defense = Math.max(1, pokeRound(defense * chainMods(dfMods) / 4096))

  var base = Math.floor(Math.floor(Math.floor(2 * user.level / 5 + 2) * bp * attack / defense) / 50 + 2)
  if (spread) base = pokeRound(OF32(base * 3072) / 4096)
  if (ctx.weather === "sun" && type === "fire" || ctx.weather === "rain" && type === "water") base = pokeRound(OF32(base * 6144) / 4096)
  else if (ctx.weather === "sun" && type === "water" || ctx.weather === "rain" && type === "fire") base = pokeRound(OF32(base * 2048) / 4096)
  if (crit) base = Math.floor(OF32(base * 1.5))

  var stab = user.types.indexOf(type) >= 0 && type !== "typeless" ? (user.ability === "adaptability" ? 8192 : 6144) : 4096
  var finalMods = []
  if (ta === "multiscale" || ta === "shadow-shield") { if (target.hp === target.maxhp) finalMods.push(2048) }
  if ((ta === "filter" || ta === "solid-rock" || ta === "prism-armor") && eff > 1) finalMods.push(3072)
  if (user.ability === "tinted-lens" && eff < 1) finalMods.push(8192)
  if (user.ability === "sniper" && crit) finalMods.push(6144)
  if (ta === "fluffy" && hasFlag(move.id, F_CONTACT) && type !== "fire") finalMods.push(2048)
  if (ta === "fluffy" && type === "fire") finalMods.push(8192)
  if (ta === "ice-scales" && !phys) finalMods.push(2048)
  if (ta === "punk-rock" && hasFlag(move.id, F_SOUND)) finalMods.push(2048)
  if (ctx.screens && ctx.screens[target.side] && !crit) finalMods.push(2732)
  var finalMod = chainMods(finalMods)
  var burned = phys && user.status === "brn" && user.ability !== "guts" && move.id !== 263

  function roll(r) {
    var d = Math.floor(OF32(base * r) / 100)
    d = applyMod(d, stab)
    d = Math.floor(OF32(d * eff))
    if (burned) d = Math.floor(d / 2)
    d = applyMod(d, finalMod)
    return Math.max(1, d % 65536)
  }
  var lo = roll(85), hi = roll(100)
  return { min: lo, max: hi, avg: (lo + hi) / 2, eff: eff, roll: function(rand) { return roll(85 + Math.floor(rand() * 16)) } }
}

function hasSecondary(id) {
  var m = meta(id)
  return (m[3] > 0 && m[4] > 0) || m[10] > 0 || (m[2] === 6 && m[11] > 0) || (m[2] === 7 && m[11] > 0 && m[12].some(function(c) { return c[1] > 0 }))
}

// ---- Status ----

function canStatus(p, status, ctx) {
  if (p.hp <= 0 || p.status) return false
  var a = p.ability
  if (a === "comatose" || a === "purifying-salt") return false
  if (status === "par") return p.types.indexOf("electric") < 0 && a !== "limber"
  if (status === "slp") return a !== "insomnia" && a !== "vital-spirit" && a !== "sweet-veil"
  if (status === "brn") return p.types.indexOf("fire") < 0 && a !== "water-veil" && a !== "water-bubble"
  if (status === "frz") return p.types.indexOf("ice") < 0 && a !== "magma-armor" && ctx.weather !== "sun"
  if (status === "psn" || status === "tox") return p.types.indexOf("poison") < 0 && p.types.indexOf("steel") < 0 && a !== "immunity"
  return true
}

function setStatus(p, status, ctx, from) {
  if (!canStatus(p, status, ctx)) return false
  p.status = status
  if (status === "slp") p.sleep = 1 + Math.floor(ctx.rand() * 3)
  if (status === "tox") p.toxic = 1
  ctx.say(p, p.name + " is " + STATUS_NAMES[status] + "!")
  if (from && p.ability === "synchronize" && ["par", "brn", "psn", "tox"].indexOf(status) >= 0 && from.side !== p.side)
    setStatus(from, status === "tox" ? "psn" : status, ctx)
  return true
}

var AILMENTS = { 1: "par", 2: "slp", 3: "frz", 4: "brn", 5: "psn", 99: "tox" }

// ---- Stat stages ----

function boost(p, stat, change, ctx, byFoe) {
  if (p.hp <= 0 || !change) return false
  var a = p.ability
  if (a === "contrary") change = -change
  if (a === "simple") change *= 2
  if (change < 0 && byFoe) {
    if (a === "clear-body" || a === "white-smoke" || a === "full-metal-body") return false
    if (a === "hyper-cutter" && stat === 1) return false
    if (a === "big-pecks" && stat === 2) return false
    if (a === "keen-eye" && stat === 6) return false
  }
  var before = p.boosts[stat]
  p.boosts[stat] = Math.max(-6, Math.min(6, before + change))
  var diff = p.boosts[stat] - before
  if (!diff) return false
  var words = Math.abs(diff) >= 3 ? " drastically" : Math.abs(diff) === 2 ? " sharply" : ""
  ctx.say(p, p.name + "'s " + BOOST_NAMES[stat] + (diff > 0 ? words + " rose!" : words + " fell!"), true)
  if (diff < 0 && byFoe) {
    if (a === "defiant") boost(p, 1, 2, ctx)
    if (a === "competitive") boost(p, 3, 2, ctx)
  }
  return true
}

// ---- HP ----

function heal(p, amount, ctx, why) {
  if (p.hp <= 0 || p.hp >= p.maxhp) return 0
  var h = Math.min(p.maxhp - p.hp, Math.max(1, Math.floor(amount)))
  p.hp += h
  if (why) ctx.say(p, why, true)
  return h
}

function hurt(p, amount, ctx) {
  if (p.hp <= 0) return 0
  var d = Math.min(p.hp, Math.max(1, Math.floor(amount)))
  p.hp -= d
  if (p.hp <= 0) faint(p, ctx)
  return d
}

function faint(p, ctx) {
  p.hp = 0
  ctx.say(p, (p.side === 1 ? "The wild " : "") + p.name + " fainted!")
  if (ctx.onFaint) ctx.onFaint(p)
}

// ---- Move choice (AI) ----

function usableMoves(p) {
  var out = p.moves.filter(function(m) { return m.pp > 0 })
  if (p.lastTurn && p.lastTurn > 1) out = out.filter(function(m) { return m.id !== FAKE_OUT })
  return out
}

function hitChance(move, user, target, ctx) {
  if (!move.acc) return 1
  if (OHKO[move.id]) return target.level > user.level ? 0 : Math.min(1, (30 + user.level - target.level) / 100)
  var acc = move.acc
  if ((move.id === 87 || move.id === 542) && ctx.weather === "rain") return 1   // Thunder, Hurricane
  if ((move.id === 87 || move.id === 542) && ctx.weather === "sun") acc = 50
  if (move.id === 59 && ctx.weather === "hail") return 1                        // Blizzard
  var stage = Math.max(-6, Math.min(6, user.boosts[6] - (user.ability === "unaware" ? 0 : target.boosts[7])))
  acc = acc * accMult(stage)
  if (user.ability === "compound-eyes") acc *= 1.3
  if (user.ability === "hustle" && isPhysical(move)) acc *= 0.8
  if (ctx.fog) acc *= 0.9
  if (target.ability === "sand-veil" && ctx.weather === "sand" || target.ability === "snow-cloak" && ctx.weather === "hail") acc *= 0.8
  if (user.ability === "no-guard" || target.ability === "no-guard") return 1
  return Math.max(0, Math.min(1, acc / 100))
}

// How much this move is worth right now, roughly in "foe HP fractions".
function moveValue(move, user, target, allies, foes, ctx) {
  var m = meta(move.id), cat = m[2]
  var hit = hitChance(move, user, target, ctx)
  if (move.id === TRANSFORM) return user.transformed ? 0 : 1.2
  if (move.id === FAKE_OUT) return (user.lastTurn || 0) <= 1 && target.ability !== "inner-focus" ? 0.6 * hit : 0
  if (move.id === DREAM_EATER && target.status !== "slp") return 0
  if (move.id === SNORE && user.status !== "slp") return 0
  if (EXPLODE[move.id] && user.hp * 4 > user.maxhp) return 0.02
  if (OHKO[move.id]) return target.ability === "sturdy" ? 0 : hit * 0.9
  if (move.cat > 0) {
    var spread = SPREAD_TARGETS[m[1]] && foes.length > 1
    var targets = spread ? foes : [target]
    var total = 0
    for (var i = 0; i < targets.length; i++) {
      var t = targets[i]
      var d = damage(move, user, t, ctx, { spread: spread })
      if (!d) continue
      var hits = m[6] > 1 ? (user.ability === "skill-link" ? m[6] : (m[5] + m[6]) / 2) : 1
      var dealt = Math.min(t.hp, d.avg * hits)
      var v = dealt / t.maxhp
      if (d.min * hits >= t.hp) v += 0.6           // a sure KO is worth a lot
      else if (d.max * hits >= t.hp) v += 0.25
      total += v * hitChance(move, user, t, ctx)
    }
    if (hasFlag(move.id, F_CHARGE) && !(move.id === 76 && ctx.weather === "sun") && !(move.id === 669 && ctx.weather === "sun")) total *= 0.55
    if (hasFlag(move.id, F_RECHARGE)) total *= 0.6
    if (m[7] < 0 && user.ability !== "rock-head") total -= (-m[7] / 100) * total * 0.4
    if (m[7] > 0 && user.hp < user.maxhp) total *= 1.15
    if (EXPLODE[move.id]) total *= 0.7
    if (cat === 9) total = 0
    // Keep a little PP for the boss: last PP of a move is slightly less attractive
    if (move.pp !== undefined && move.max && move.pp <= 1 && move.max > 5) total *= 0.9
    return total
  }
  // Status moves
  if (WEATHER_MOVES[move.id]) {
    var w = WEATHER_MOVES[move.id]
    if (ctx.weather === w) return 0
    var helps = user.moves.some(function(x) {
      var t = moveData(x.id).type
      return (w === "rain" && t === "water") || (w === "sun" && t === "fire")
    }) || (w === "rain" && user.ability === "swift-swim") || (w === "sun" && user.ability === "chlorophyll")
    return helps ? 0.18 : 0
  }
  if (TEAM_CURE[move.id]) return allies.some(function(a) { return a.hp > 0 && a.status }) ? 0.3 : 0
  if (move.id === LEECH_SEED) return target.seeded || target.types.indexOf("grass") >= 0 ? 0 : 0.22 * hit
  if (move.id === REST) return user.hp * 3 < user.maxhp && user.ability !== "insomnia" ? 0.5 : 0
  if (cat === 3) {   // heal
    if (user.hp * 2 > user.maxhp) return 0
    var pct = WEATHER_HEAL[move.id] ? (ctx.weather === "sun" ? 66 : ctx.weather ? 25 : 50) : (m[8] || 50)
    return Math.min(user.maxhp - user.hp, user.maxhp * pct / 100) / user.maxhp
  }
  var value = 0
  var long = target.hp / Math.max(1, target.maxhp) > 0.5 && foes.length > 0
  if (cat === 1 || cat === 5) {   // inflict a status
    var st = AILMENTS[m[3]]
    if (st && canStatus(target, st, ctx)) value += { slp: 0.4, par: 0.25, brn: 0.25, psn: 0.18, tox: 0.28, frz: 0.4 }[st] * (long ? 1 : 0.4)
    if (m[3] === 6 && !target.confused && target.ability !== "own-tempo") value += 0.15
    if (move.id === 92 && target.types.indexOf("poison") >= 0) value = 0
  }
  if (cat === 2 || cat === 5) {   // stat changes
    var self = SELF_TARGETS[m[1]]
    m[12].forEach(function(c) {
      var stat = c[0], change = c[1]
      if (self) {
        if (change <= 0 || user.boosts[stat] >= 2) return
        var useful = stat === 1 ? user.moves.some(function(x) { return moveData(x.id).cat === 1 })
                   : stat === 3 ? user.moves.some(function(x) { return moveData(x.id).cat === 2 })
                   : true
        if (useful && user.hp * 3 > user.maxhp * 2 && long) value += 0.12 * change
      } else if (change < 0 && target.boosts[stat] > -2 && long) {
        value += 0.05 * -change
      }
    })
  }
  return value * hit
}

function chooseAction(user, allies, foes, ctx, careful) {
  var moves = usableMoves(user)
  var aliveFoes = foes.filter(function(f) { return f.hp > 0 })
  if (!aliveFoes.length) return null
  if (!moves.length) return { move: moveData(STRUGGLE), slot: -1, target: aliveFoes[Math.floor(ctx.rand() * aliveFoes.length)] }
  var best = null, options = []
  for (var i = 0; i < moves.length; i++) {
    var mv = moveData(moves[i].id)
    mv.pp = moves[i].pp; mv.max = moves[i].max
    for (var j = 0; j < aliveFoes.length; j++) {
      var v = moveValue(mv, user, aliveFoes[j], allies, aliveFoes, ctx)
      options.push({ move: mv, slot: user.moves.indexOf(moves[i]), target: aliveFoes[j], value: v })
    }
  }
  if (careful) {
    // Your team: the best option, with a pinch of noise
    for (var k = 0; k < options.length; k++) {
      var o = options[k], score = o.value * (0.93 + ctx.rand() * 0.14)
      if (!best || score > best.score) { best = o; best.score = score }
    }
  } else {
    // Wild Pokémon: weighted by value, so they make the odd questionable choice
    var total = options.reduce(function(a, o) { return a + o.value + 0.08 }, 0)
    var r = ctx.rand() * total
    for (var n = 0; n < options.length; n++) {
      r -= options[n].value + 0.08
      if (r <= 0) { best = options[n]; break }
    }
    best = best || options[options.length - 1]
  }
  return best
}

// ---- Using a move ----

function critStage(move, user) {
  var s = meta(move.id)[9] || 0
  if (user.ability === "super-luck") s += 1
  if (user.focus) s += 2
  return s
}

function rollCrit(move, user, target, ctx) {
  if (target.ability === "battle-armor" || target.ability === "shell-armor") return false
  var s = critStage(move, user)
  var chance = s <= 0 ? 1 / 24 : s === 1 ? 1 / 8 : s === 2 ? 1 / 2 : 1
  if (ctx.happyCrit && user.side === 0 && user.happiness >= 90) chance = Math.min(1, chance * 2)
  return ctx.rand() < chance
}

function absorb(move, type, user, target, ctx) {
  var a = immune(move, type, user, target)
  if (!a) return false
  var n = target.name
  if (a === "flash-fire") { target.flashFire = true; ctx.say(target, n + "'s Flash Fire powered up its Fire moves!", true) }
  else if (a === "water-absorb" || a === "dry-skin" || a === "volt-absorb" || a === "earth-eater")
    heal(target, target.maxhp / 4, ctx, n + " absorbed the attack!") || ctx.say(target, "It doesn't affect " + n + "…", true)
  else if (a === "storm-drain" || a === "lightning-rod") boost(target, 3, 1, ctx)
  else if (a === "motor-drive") boost(target, 5, 1, ctx)
  else if (a === "sap-sipper") boost(target, 1, 1, ctx)
  else ctx.say(target, "It doesn't affect " + n + "…", true)
  return true
}

function useMove(user, action, allies, foes, ctx) {
  var move = action.move
  var m = meta(move.id)
  var who = (user.side === 1 ? "The wild " : "") + user.name
  // PP
  if (action.slot >= 0 && user.moves[action.slot]) user.moves[action.slot].pp = Math.max(0, user.moves[action.slot].pp - 1)
  // Two-turn moves
  if (hasFlag(move.id, F_CHARGE) && !user.charging && !((move.id === 76 || move.id === 669) && ctx.weather === "sun")) {
    user.charging = action
    ctx.say(user, who + " is charging up " + move.name + "!", true)
    return
  }
  user.charging = null
  var aimed = move.cat > 0 && !SPREAD_TARGETS[m[1]] && action.target && action.target.hp > 0
  ctx.say(user, who + " used " + move.name + (aimed ? " on " + (action.target.side === 1 ? "the wild " : "") + action.target.name : "") + "!", true)

  if (move.id === TRANSFORM) { transform(user, action.target, ctx); return }

  var aliveFoes = foes.filter(function(f) { return f.hp > 0 })
  if (SELF_TARGETS[m[1]] && !move.cat) {
    selfEffects(move, user, allies, ctx)
    return
  }
  if (WEATHER_MOVES[move.id]) { setWeather(WEATHER_MOVES[move.id], 5, ctx, user); return }
  if (TEAM_CURE[move.id]) {
    allies.forEach(function(a) { if (a.hp > 0 && a.status) { a.status = ""; a.toxic = 0 } })
    ctx.say(user, "A soothing sound cured the team's status problems!", true)
    return
  }
  if (move.id === REST) {
    if (user.hp >= user.maxhp || !canStatus({ hp: 1, status: "", types: user.types, ability: user.ability }, "slp", ctx)) { ctx.say(user, "But it failed!", true); return }
    user.status = "slp"; user.sleep = 2; user.toxic = 0
    heal(user, user.maxhp, ctx, who + " slept and became healthy!")
    return
  }
  if (m[2] === 3 && !move.cat) {
    var pct = WEATHER_HEAL[move.id] ? (ctx.weather === "sun" ? 66 : ctx.weather ? 25 : 50) : (m[8] || 50)
    if (!heal(user, user.maxhp * pct / 100, ctx, who + " restored its HP.")) ctx.say(user, "But it failed!", true)
    return
  }

  var spread = SPREAD_TARGETS[m[1]] && aliveFoes.length > 1
  var targets = SPREAD_TARGETS[m[1]] ? aliveFoes : [action.target && action.target.hp > 0 ? action.target : aliveFoes[0]]
  targets = targets.filter(function(t) { return !!t })
  var type = moveType(move, user)
  var dealtTotal = 0

  for (var i = 0; i < targets.length; i++) {
    var target = targets[i]
    if (target.hp <= 0) continue
    // Accuracy
    if (ctx.rand() >= hitChance(move, user, target, ctx)) {
      ctx.say(user, (target.side === 1 ? "The wild " : "") + target.name + " avoided the attack!", true)
      if ([26, 136].indexOf(move.id) >= 0) hurt(user, user.maxhp / 2, ctx)   // crash damage
      continue
    }
    if (OHKO[move.id]) {
      if (target.ability === "sturdy") { ctx.say(target, target.name + " held on thanks to Sturdy!", true); continue }
      hurt(target, target.hp, ctx); ctx.say(user, "It's a one-hit KO!")
      continue
    }
    if (move.cat > 0 || move.id === STRUGGLE) {
      if (move.id !== STRUGGLE && absorb(move, type, user, target, ctx)) continue
      var hits = 1
      if (m[6] > 1) hits = user.ability === "skill-link" ? m[6] : m[5] === m[6] ? m[5] : rollHits(m[5], m[6], ctx.rand)
      var landed = 0, eff = 1
      for (var h = 0; h < hits && target.hp > 0 && user.hp > 0; h++) {
        var crit = rollCrit(move, user, target, ctx)
        var d = damage(move, user, target, ctx, { crit: crit, spread: spread })
        if (!d) { ctx.say(target, "It doesn't affect " + target.name + "…", true); break }
        eff = d.eff
        var amount = d.roll(ctx.rand)
        if (move.id === DREAM_EATER && target.status !== "slp") { ctx.say(user, "But it failed!", true); break }
        // Sturdy and friendship endure
        if (amount >= target.hp && target.hp === target.maxhp && target.ability === "sturdy" && user.ability !== "mold-breaker") {
          amount = target.hp - 1
          ctx.say(target, target.name + " endured the hit thanks to Sturdy!", true)
        } else if (amount >= target.hp && ctx.endure && ctx.endure(target)) {
          amount = target.hp - 1
        }
        if (crit) ctx.say(user, "A critical hit!", true)
        if (h === 0 && eff > 1) ctx.say(user, "It's super effective!", true)
        else if (h === 0 && eff < 1) ctx.say(user, "It's not very effective…", true)
        dealtTotal += Math.min(target.hp, amount)
        landed++
        if (hits === 1 && amount < target.hp) ctx.say(target, (target.side === 1 ? "The wild " : "") + target.name + " lost " + Math.round(amount / target.maxhp * 100) + "% of its HP.", true)
        hurt(target, amount, ctx)
        if (target.hp > 0) contactEffects(move, user, target, ctx)
        else if (user.ability === "moxie" || user.ability === "chilling-neigh") boost(user, 1, 1, ctx)
        else if (user.ability === "grim-neigh") boost(user, 3, 1, ctx)
      }
      if (hits > 1 && landed > 1) ctx.say(user, "Hit " + landed + " times!", true)
      if (landed && target.hp > 0) secondary(move, user, target, ctx)
    } else {
      // Status move aimed at a foe
      statusMove(move, user, target, ctx)
    }
  }
  // After-effects on the user
  if (dealtTotal > 0) {
    if (m[7] > 0) heal(user, dealtTotal * m[7] / 100, ctx, who + " drained some energy.")
    if (m[7] < 0 && user.ability !== "rock-head" && user.ability !== "magic-guard") { hurt(user, Math.max(1, dealtTotal * -m[7] / 100), ctx); ctx.say(user, who + " was hurt by the recoil!", true) }
    if (m[2] === 7 && user.hp > 0 && (!m[11] || ctx.rand() * 100 < m[11] * (user.ability === "serene-grace" ? 2 : 1)))
      m[12].forEach(function(c) { boost(user, c[0], c[1], ctx) })
  }
  if (move.id === STRUGGLE && user.hp > 0) hurt(user, user.maxhp / 4, ctx)
  if (EXPLODE[move.id] && user.hp > 0) hurt(user, user.hp, ctx)
  if (hasFlag(move.id, F_RECHARGE) && dealtTotal > 0) user.recharge = true
}

function rollHits(min, max, rand) {
  if (min === 2 && max === 5) {
    var r = rand()
    return r < 0.35 ? 2 : r < 0.70 ? 3 : r < 0.85 ? 4 : 5
  }
  return min + Math.floor(rand() * (max - min + 1))
}

function secondary(move, user, target, ctx) {
  var m = meta(move.id)
  if (target.ability === "shield-dust" || user.ability === "sheer-force") return
  var mult = user.ability === "serene-grace" ? 2 : 1
  if (m[3] > 0 && m[4] > 0 && ctx.rand() * 100 < m[4] * mult) applyAilment(m[3], user, target, ctx)
  if (m[10] > 0 && !target.moved && target.ability !== "inner-focus" && ctx.rand() * 100 < m[10] * mult) target.flinch = true
  if (m[2] === 6 && m[11] > 0 && ctx.rand() * 100 < m[11] * mult) m[12].forEach(function(c) { boost(target, c[0], c[1], ctx, true) })
  if (move.id === FAKE_OUT && target.ability !== "inner-focus") target.flinch = true
}

function applyAilment(id, user, target, ctx) {
  if (id === 6) {
    if (!target.confused && target.ability !== "own-tempo") {
      target.confused = 2 + Math.floor(ctx.rand() * 4)
      ctx.say(target, target.name + " became confused!", true)
    }
    return
  }
  if (id === 18) {
    if (!target.seeded && target.types.indexOf("grass") < 0) { target.seeded = user; ctx.say(target, target.name + " was seeded!", true) }
    return
  }
  var st = AILMENTS[id]
  if (st) setStatus(target, st, ctx, user)
}

function statusMove(move, user, target, ctx) {
  var m = meta(move.id)
  var n = (target.side === 1 ? "The wild " : "") + target.name
  if (target.ability === "magic-bounce" || (m[13] & F_POWDER) && target.types.indexOf("grass") >= 0) { ctx.say(target, "It doesn't affect " + n + "…", true); return }
  if (ctx.rand() >= hitChance(move, user, target, ctx)) { ctx.say(target, n + " avoided the attack!", true); return }
  var did = false
  if (move.id === LEECH_SEED) { applyAilment(18, user, target, ctx); return }
  if (m[3] > 0) {
    var before = target.status + "|" + target.confused + "|" + !!target.seeded
    applyAilment(m[3], user, target, ctx)
    did = before !== target.status + "|" + target.confused + "|" + !!target.seeded
  }
  if (m[2] === 2 || m[2] === 5) m[12].forEach(function(c) { did = boost(target, c[0], c[1], ctx, true) || did })
  if (!did) ctx.say(user, "But it failed!", true)
}

function selfEffects(move, user, allies, ctx) {
  var m = meta(move.id)
  var did = false
  var targets = m[1] === 13 || m[1] === 15 ? allies.filter(function(a) { return a.hp > 0 }) : [user]
  targets.forEach(function(t) {
    m[12].forEach(function(c) { did = boost(t, c[0], c[1], ctx) || did })
  })
  if (m[2] === 3 || m[8] > 0) did = heal(user, user.maxhp * (m[8] || 50) / 100, ctx, user.name + " restored its HP.") > 0 || did
  if (move.id === 116) { user.focus = true; did = true; ctx.say(user, user.name + " is getting pumped!", true) }   // Focus Energy
  if (!did) ctx.say(user, "But nothing happened.", true)
}

function contactEffects(move, user, target, ctx) {
  if (!hasFlag(move.id, F_CONTACT) || user.hp <= 0) return
  var a = target.ability
  if ((a === "rough-skin" || a === "iron-barbs") && user.ability !== "magic-guard") {
    hurt(user, user.maxhp / 8, ctx); ctx.say(user, user.name + " was hurt by " + target.name + "'s " + (a === "rough-skin" ? "Rough Skin" : "Iron Barbs") + "!", true)
  }
  if (ctx.rand() < 0.3) {
    if (a === "static") setStatus(user, "par", ctx)
    else if (a === "flame-body") setStatus(user, "brn", ctx)
    else if (a === "poison-point") setStatus(user, "psn", ctx)
    else if (a === "effect-spore" && user.types.indexOf("grass") < 0 && user.ability !== "overcoat") {
      var r = ctx.rand()
      setStatus(user, r < 0.33 ? "slp" : r < 0.66 ? "par" : "psn", ctx)
    }
  }
}

function transform(user, target, ctx) {
  if (!target || target.hp <= 0) return
  if (!user.original) user.original = { species: user.species, types: user.types, ability: user.ability, weight: user.weight,
                                        stats: user.stats, moves: user.moves }
  user.transformed = true
  user.species = target.species
  user.types = target.types.slice()
  user.ability = target.ability
  user.weight = target.weight
  user.stats = [user.stats[0]].concat(target.stats.slice(1))
  user.boosts = target.boosts.slice()
  user.moves = target.moves.map(function(m) { return { id: m.id, pp: 5, max: 5 } })
  ctx.say(user, user.name + " transformed into " + target.name + "!")
}

// ---- Weather ----

function setWeather(w, turns, ctx, by) {
  if (ctx.weather === w) { if (by) ctx.say(by, "But it failed!", true); return }
  ctx.weather = w
  ctx.weatherTurns = turns
  ctx.say(by || null, { rain: "It started to rain!", sun: "The sunlight turned harsh!", sand: "A sandstorm kicked up!", hail: "It started to hail!" }[w])
}

// ---- One turn ----

function canAct(p, ctx) {
  var who = (p.side === 1 ? "The wild " : "") + p.name
  if (p.recharge) { p.recharge = false; ctx.say(p, who + " must recharge!", true); return false }
  if (p.status === "slp") {
    p.sleep -= p.ability === "early-bird" ? 2 : 1
    if (p.sleep > 0) { ctx.say(p, who + " is fast asleep.", true); return false }
    p.status = ""
    ctx.say(p, who + " woke up!", true)
  }
  if (p.status === "frz") {
    if (ctx.rand() < 0.2) { p.status = ""; ctx.say(p, who + " thawed out!", true) }
    else { ctx.say(p, who + " is frozen solid!", true); return false }
  }
  if (p.flinch) { p.flinch = false; ctx.say(p, who + " flinched!", true); return false }
  if (p.confused) {
    p.confused -= 1
    if (p.confused <= 0) { p.confused = 0; ctx.say(p, who + " snapped out of its confusion!", true) }
    else if (ctx.rand() < 1 / 3) {
      var d = Math.floor(Math.floor(Math.floor(2 * p.level / 5 + 2) * 40 * p.stats[1] / p.stats[2]) / 50 + 2)
      ctx.say(p, who + " hurt itself in its confusion!", true)
      hurt(p, d, ctx)
      return false
    }
  }
  if (p.status === "par" && ctx.rand() < 0.25) { ctx.say(p, who + " is paralyzed! It can't move!", true); return false }
  return true
}

function endOfTurn(all, ctx) {
  if (ctx.weather && ctx.weatherTurns > 0) {
    ctx.weatherTurns -= 1
    if (ctx.weatherTurns === 0 && ctx.weather !== ctx.baseWeather) {
      ctx.say(null, { rain: "The rain stopped.", sun: "The sunlight faded.", sand: "The sandstorm subsided.", hail: "The hail stopped." }[ctx.weather], true)
      ctx.weather = ctx.baseWeather || ""
    }
  }
  all.forEach(function(p) {
    if (p.hp <= 0) return
    var a = p.ability
    if (ctx.weather === "sand" && ["rock", "ground", "steel"].every(function(t) { return p.types.indexOf(t) < 0 })
        && ["sand-veil", "sand-rush", "sand-force", "overcoat", "magic-guard"].indexOf(a) < 0) hurt(p, p.maxhp / 16, ctx)
    if (ctx.weather === "hail" && p.types.indexOf("ice") < 0 && ["ice-body", "snow-cloak", "overcoat", "magic-guard", "slush-rush"].indexOf(a) < 0) hurt(p, p.maxhp / 16, ctx)
    if (p.hp <= 0) return
    if (ctx.weather === "rain" && (a === "rain-dish" || a === "dry-skin")) heal(p, p.maxhp / (a === "dry-skin" ? 8 : 16), ctx)
    if (ctx.weather === "hail" && a === "ice-body") heal(p, p.maxhp / 16, ctx)
    if (ctx.weather === "sun" && (a === "dry-skin" || a === "solar-power")) hurt(p, p.maxhp / 8, ctx)
    if (p.hp <= 0) return
    if (p.seeded && p.seeded.hp > 0 && a !== "magic-guard") {
      var drained = hurt(p, p.maxhp / 8, ctx)
      heal(p.seeded, drained, ctx)
    }
    if (p.hp <= 0) return
    if ((p.status === "psn" || p.status === "tox") && a === "poison-heal") heal(p, p.maxhp / 8, ctx)
    else if (p.status === "psn" && a !== "magic-guard") { hurt(p, p.maxhp / 8, ctx); ctx.say(p, p.name + " is hurt by poison.", true) }
    else if (p.status === "tox" && a !== "magic-guard") { hurt(p, p.maxhp * Math.min(15, p.toxic) / 16, ctx); p.toxic += 1; ctx.say(p, p.name + " is hurt by poison.", true) }
    else if (p.status === "brn" && a !== "magic-guard") { hurt(p, p.maxhp / 16, ctx); ctx.say(p, p.name + " is hurt by its burn.", true) }
    if (p.hp <= 0) return
    if (a === "speed-boost" && p.lastTurn) boost(p, 5, 1, ctx)
    if (a === "shed-skin" && p.status && ctx.rand() < 0.3) { p.status = ""; p.toxic = 0 }
    if (a === "hydration" && p.status && ctx.weather === "rain") { p.status = ""; p.toxic = 0 }
    p.flinch = false
  })
}

// ---- A whole battle ----
// team, foes: arrays of combatants (their hp / pp / status are updated in place).
// ctx: { rand, weather, say(p, text, minor), onFaint(p), endure(p), afterTurn(turn), firstStrike: "team" | "foes" }
// Returns "won" | "lost" | "fled".

function freshBattleState(p, side) {
  p.side = side
  p.boosts = [0, 0, 0, 0, 0, 0, 0, 0]
  p.confused = 0; p.flinch = false; p.charging = null; p.recharge = false
  p.seeded = null; p.flashFire = false; p.focus = false; p.lastTurn = 0; p.moved = false
  if (p.status === "slp" && !p.sleep) p.sleep = 1
}

function battle(team, foes, ctx) {
  team.forEach(function(p) { freshBattleState(p, 0) })
  foes.forEach(function(p) { freshBattleState(p, 1) })
  ctx.baseWeather = ctx.weather || ""
  ctx.weatherTurns = 0

  // Switch-in abilities
  var everyone = team.concat(foes)
  everyone.forEach(function(p) {
    if (p.hp <= 0) return
    if (WEATHER_ABILITIES[p.ability] && ctx.weather !== WEATHER_ABILITIES[p.ability]) setWeather(WEATHER_ABILITIES[p.ability], 5, ctx, null)
    if (p.ability === "intimidate") {
      var other = p.side === 0 ? foes : team
      other.forEach(function(o) {
        if (o.hp <= 0) return
        if (["inner-focus", "oblivious", "own-tempo", "scrappy"].indexOf(o.ability) >= 0) return
        boost(o, 1, -1, ctx, true)
      })
    }
    if (p.ability === "imposter" && p.side === 1) {
      var t = team.filter(function(x) { return x.hp > 0 })[0]
      if (t) transform(p, t, ctx)
    }
  })
  if (ctx.teamBoost) team.forEach(function(p) { ctx.teamBoost(p) })

  for (var turn = 1; turn <= TURN_LIMIT; turn++) {
    var aliveTeam = team.filter(function(p) { return p.hp > 0 })
    var aliveFoes = foes.filter(function(p) { return p.hp > 0 })
    if (!aliveFoes.length) return "won"
    if (!aliveTeam.length) return "lost"

    var actions = []
    aliveTeam.forEach(function(p) {
      if (ctx.benched && ctx.benched(p)) return
      var a = p.charging || chooseAction(p, team, aliveFoes, ctx, true)
      if (a) actions.push({ who: p, act: a })
    })
    aliveFoes.forEach(function(p) {
      var a = p.charging || chooseAction(p, foes, aliveTeam, ctx, false)
      if (a) actions.push({ who: p, act: a })
    })
    // Priority, then Speed (random tie-break); an ambush lets one side go first on turn 1
    var keys = actions.map(function() { return ctx.rand() })
    actions.forEach(function(a, i) { a.tie = keys[i] })
    actions.sort(function(x, y) {
      if (turn === 1 && ctx.firstStrike && x.who.side !== y.who.side)
        return (ctx.firstStrike === "foes" ? (x.who.side === 1 ? -1 : 1) : (x.who.side === 0 ? -1 : 1))
      var px = meta(x.act.move.id)[0], py = meta(y.act.move.id)[0]
      if (px !== py) return py - px
      var sx = speed(x.who, ctx.weather), sy = speed(y.who, ctx.weather)
      if (sx !== sy) return sy - sx
      return x.tie - y.tie
    })
    everyone.forEach(function(p) { p.moved = false })
    for (var i = 0; i < actions.length; i++) {
      var p = actions[i].who
      if (p.hp <= 0) continue
      p.lastTurn = turn
      var allies = p.side === 0 ? team : foes
      var opponents = (p.side === 0 ? foes : team).filter(function(o) { return o.hp > 0 })
      if (!opponents.length) break
      var act = actions[i].act
      if (act.target && act.target.hp <= 0) {
        // Its target fell: pick again against whoever is left
        act = p.charging || chooseAction(p, allies, opponents, ctx, p.side === 0) || act
      }
      if (canAct(p, ctx)) useMove(p, act, allies, opponents, ctx)
      else if (p.charging) p.charging = null
      p.moved = true
    }
    endOfTurn(everyone, ctx)
    if (ctx.afterTurn) ctx.afterTurn(turn)
  }
  return foes.some(function(p) { return p.hp > 0 }) && team.some(function(p) { return p.hp > 0 }) ? "fled"
       : foes.some(function(p) { return p.hp > 0 }) ? "lost" : "won"
}

// Clears what only lasts for one battle; status conditions stay (sleep wears off).
function afterBattle(p) {
  if (p.status === "slp") { p.status = ""; p.sleep = 0 }
  if (p.original) {
    var o = p.original
    p.species = o.species; p.types = o.types; p.ability = o.ability; p.weight = o.weight; p.stats = o.stats; p.moves = o.moves
    delete p.original
  }
  delete p.transformed
  delete p.foeScrappy
  p.boosts = [0, 0, 0, 0, 0, 0, 0, 0]
  p.confused = 0; p.flinch = false; p.charging = null; p.recharge = false; p.seeded = null; p.flashFire = false; p.focus = false
}
