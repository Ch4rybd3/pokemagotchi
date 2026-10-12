.pragma library
.import "Pet.js" as Pet
.import "Combat.js" as Combat
.import "Battle.js" as Battle
.import "Dex.js" as Dex
.import "Info.js" as Info
.import "Items.js" as Items

// Expeditions, in the spirit of Pokémon Mystery Dungeon: a team of up to three
// explores a biome floor by floor, fights wild Pokémon with its real stats and
// moves, runs into events, and lives off the provisions you packed.
//
// Nothing is decided by you once it has left (like Fallout Shelter's
// wasteland). Each floor is simulated when its time is up, with an RNG seeded
// on the expedition and the floor, so every bar instance and every refresh
// computes exactly the same story.

// ---- Tuning ----

var TEAM_SIZE = 3
var HUNGER_PER_FLOOR = 4            // fullness lost per floor (biomes and weather can raise it)
var REGEN_PER_FLOOR = 0.08          // HP recovered while walking, as a share of max HP
var STARVING_DAMAGE = 0.10          // HP lost per floor on an empty stomach
var EAT_BELOW = 40                  // fullness under which a Pokémon eats
var POTION_IN_BATTLE = 0.30         // HP share under which a Pokémon drinks a potion mid-battle
var POTION_AFTER_BATTLE = 0.50
var RECRUIT_ODDS = 0.10             // × (catch rate / 255)^0.75 for a defeated wild Pokémon
var LEGEND_JOIN = 0.12              // a legendary met at least twice in a biome may join after a win
var MYTHICAL_JOIN = 0.06
var BOSS_POWER = 0.1                // bosses are this much stronger than the floor's wild Pokémon
var LEGEND_POWER = 0.95             // legendaries are (almost) at full strength
var RETURN_CAP = 30 * 60000         // a recalled team needs half the time spent, at most 30 min
var HISTORY_SIZE = 10
// Poké Dollars: per wild Pokémon defeated, per floor explored and per boss, × the
// difficulty's `coins`. A cleared expedition pays 25% more, a defeated team half.
var COINS_PER_KO = 6
var COINS_PER_FLOOR = 12
var COINS_PER_BOSS = 80
var COINS_PER_LEGEND = 150
var LOG_DETAIL = 80                 // lines kept per battle

var RANKS = [
  { name: "Normal", points: 0, slots: 1, provisions: 8 },
  { name: "Bronze", points: 60, slots: 1, provisions: 10 },
  { name: "Silver", points: 250, slots: 2, provisions: 12 },
  { name: "Gold", points: 700, slots: 2, provisions: 14 },
  { name: "Platinum", points: 1500, slots: 3, provisions: 16 },
  { name: "Diamond", points: 3000, slots: 3, provisions: 18 },
  { name: "Master", points: 6000, slots: 3, provisions: 20 }
]

// pack: odds of meeting 1, 2 or 3 wild Pokémon at once; steps: things that happen per floor; boss: boss floors;
// legend: chance that a legendary shows up; tier: which legendaries can (1 young ones,
// 2 + the others, 3 + box legendaries and mythicals); power: wild Pokémon's stats (×), like
// Mystery Dungeon's wild Pokémon they are weaker than a team that sticks together;
// ivMin / evs: how well trained they are.
var DIFFICULTIES = {
  easy:   { id: "easy", name: "Easy", floors: 5, minutes: 30, pack: [1, 0, 0], steps: [2, 2], boss: [], rank: 0,
            coins: 1, xp: 1, loot: 1, points: 1, check: 1.25, power: 0.6, ivMin: 0, evs: 0, legend: 0, tier: 0, recruits: 1, bossHp: 2 },
  normal: { id: "normal", name: "Normal", floors: 10, minutes: 60, pack: [0.7, 0.3, 0], steps: [2, 3], boss: [10], rank: 0,
            coins: 1.5, xp: 1.2, loot: 1.5, points: 2, check: 1.1, power: 0.66, ivMin: 0, evs: 0, legend: 0.04, tier: 1, recruits: 2, bossHp: 2.5 },
  hard:   { id: "hard", name: "Hard", floors: 15, minutes: 120, pack: [0.5, 0.35, 0.15], steps: [2, 3], boss: [8, 15], rank: 1,
            coins: 2.2, xp: 1.5, loot: 2.5, points: 3, check: 0.95, power: 0.68, ivMin: 5, evs: 0, legend: 0.10, tier: 2, recruits: 3, bossHp: 3 },
  expert: { id: "expert", name: "Expert", floors: 20, minutes: 240, pack: [0.3, 0.45, 0.25], steps: [2, 3], boss: [5, 10, 15, 20], rank: 3,
            coins: 3, xp: 2, loot: 4, points: 5, check: 0.85, power: 0.72, ivMin: 15, evs: 0, legend: 0.18, tier: 3, recruits: 4, bossHp: 3 }
}
var DIFFICULTY_ORDER = ["easy", "normal", "hard", "expert"]

// Legendaries that show up from Normal (young ones) or Hard (the others) on;
// everything else, mythicals included, waits for Expert.
var YOUNG_LEGENDS = ["cosmog", "cosmoem", "kubfu", "type-null", "meltan", "phione"]
var BOX_LEGENDS = ["mewtwo", "lugia", "ho-oh", "kyogre", "groudon", "rayquaza", "dialga", "palkia", "giratina",
                   "reshiram", "zekrom", "kyurem", "xerneas", "yveltal", "zygarde", "solgaleo", "lunala", "necrozma",
                   "zacian", "zamazenta", "eternatus", "calyrex", "regigigas", "arceus"]

function legendTier(slug) {
  if (YOUNG_LEGENDS.indexOf(slug) >= 0) return 1
  if (Battle.legendary[slug] === 2 || BOX_LEGENDS.indexOf(slug) >= 0) return 3
  return 2
}

// types: wild Pokémon types and their weight. weather: what the sky does there.
// hunger: fullness lost per floor (×). loot: items found there on top of the common ones.
var BIOMES = {
  forest: { id: "forest", name: "Misty Forest", rank: 0, hunger: 1,
            text: "A damp, green maze where Bug and Grass Pokémon thrive.",
            types: { grass: 3, bug: 3, normal: 2, fairy: 1.5, poison: 0.6, flying: 0.6 },
            weather: { fog: 2, rain: 1 }, colors: ["#1f3a24", "#3f6b3a", "#6aa060"],
            loot: ["leaf-stone", "sweet-apple", "tart-apple", "razz-berry", "nanab-berry", "big-apple", "lum-berry"],
            legends: ["celebi", "shaymin", "virizion", "zarude", "xerneas", "tapu-bulu", "zacian", "zamazenta", "calyrex"] },
  cave:   { id: "cave", name: "Crystal Cave", rank: 0, hunger: 1,
            text: "Glittering tunnels full of Rock, Ground and Steel Pokémon.",
            types: { rock: 3, ground: 3, steel: 2, fighting: 1, dark: 0.6 },
            weather: { sand: 1 }, colors: ["#262330", "#4d4560", "#8d80a8"],
            loot: ["moon-stone", "dusk-stone", "oval-stone", "metal-coat", "dawn-stone", "bottle-cap", "max-ether"],
            legends: ["regirock", "registeel", "regigigas", "terrakion", "cobalion", "diancie", "landorus", "zygarde", "mewtwo"] },
  reef:   { id: "reef", name: "Coral Reef", rank: 0, hunger: 1,
            text: "Warm currents, coral arches and lots of Water Pokémon.",
            types: { water: 4, ice: 1.2, poison: 0.6, flying: 0.6, rock: 0.5 },
            weather: { rain: 2 }, colors: ["#132c40", "#235a7a", "#5fa8c8"],
            loot: ["water-stone", "deep-sea-tooth", "deep-sea-scale", "prism-scale", "kings-rock", "moomoo-milk", "max-elixir"],
            legends: ["kyogre", "lugia", "suicune", "manaphy", "phione", "keldeo", "tapu-fini", "palkia"] },
  volcano: { id: "volcano", name: "Mt. Blaze", rank: 1, hunger: 1.5,
            text: "Scorching slopes: Fire Pokémon everywhere, and you get hungry fast.",
            types: { fire: 4, rock: 2, ground: 1.5, dragon: 0.8, steel: 0.5 },
            weather: { sun: 3 }, colors: ["#3a1712", "#7a2e1c", "#e0703a"],
            loot: ["fire-stone", "magmarizer", "rare-candy", "big-malasada", "hyper-potion", "gold-bottle-cap"],
            legends: ["moltres", "entei", "heatran", "groudon", "reshiram", "victini", "volcanion"] },
  plant:  { id: "plant", name: "Old Power Plant", rank: 1, hunger: 1,
            text: "Humming machinery haunted by Electric and Steel Pokémon.",
            types: { electric: 4, steel: 2.5, poison: 1.5, normal: 0.6 },
            weather: { rain: 1 }, colors: ["#20242c", "#3c4658", "#e8c840"],
            loot: ["thunder-stone", "electirizer", "up-grade", "dubious-disc", "metal-coat", "elixir", "ultra-ball"],
            legends: ["zapdos", "raikou", "zekrom", "thundurus", "tapu-koko", "regieleki", "magearna", "zeraora",
                      "genesect", "meltan", "melmetal", "type-null", "silvally"] },
  marsh:  { id: "marsh", name: "Toxic Marsh", rank: 2, hunger: 1.2,
            text: "A foul bog of Poison, Ghost and Dark Pokémon. Watch your step.",
            types: { poison: 3.5, ghost: 2, dark: 2, bug: 1, water: 0.6 },
            weather: { fog: 2, rain: 1 }, colors: ["#1e1a2a", "#3e2f4f", "#8a5aa8"],
            loot: ["dusk-stone", "reaper-cloth", "razor-fang", "black-augurite", "peat-block", "full-heal", "lum-berry"],
            legends: ["yveltal", "eternatus", "darkrai", "marshadow", "giratina"] },
  peak:   { id: "peak", name: "Frozen Peak", rank: 2, hunger: 1.3,
            text: "Icy cliffs where Ice, Flying and Fighting Pokémon train in the blizzard.",
            types: { ice: 3.5, flying: 2, fighting: 2, rock: 0.6, normal: 0.5 },
            weather: { hail: 3 }, colors: ["#1c2a38", "#4a6a88", "#d8eef8"],
            loot: ["ice-stone", "razor-claw", "protector", "dragon-scale", "rare-candy", "max-potion"],
            legends: ["articuno", "regice", "kyurem", "glastrier", "kubfu", "urshifu"] },
  ruins:  { id: "ruins", name: "Forgotten Ruins", rank: 3, hunger: 1,
            text: "Ancient halls where Psychic and Ghost Pokémon guard old secrets.",
            types: { psychic: 3, ghost: 3, dark: 1, steel: 0.6, fairy: 0.6 },
            weather: { fog: 2, sand: 1 }, colors: ["#2a2418", "#5a4c30", "#c8a860"],
            loot: ["shiny-stone", "dawn-stone", "dusk-stone", "sachet", "whipped-dream", "linking-cord", "gold-bottle-cap"],
            legends: ["mew", "uxie", "mesprit", "azelf", "cresselia", "jirachi", "meloetta", "spectrier", "tapu-lele",
                      "dialga", "hoopa", "arceus"] },
  sky:    { id: "sky", name: "Sky Tower", rank: 5, hunger: 1.2,
            text: "A tower above the clouds, home of Dragon and Flying Pokémon.",
            types: { dragon: 3, flying: 3, fairy: 1.5, psychic: 0.6, steel: 0.5 },
            weather: { sun: 1, rain: 1 }, colors: ["#18203a", "#36508a", "#a8c8f8"],
            loot: ["dragon-scale", "shiny-stone", "sun-stone", "rare-candy", "master-ball", "max-revive", "big-apple"],
            legends: ["rayquaza", "latias", "latios", "regidrago", "tornadus", "enamorus", "ho-oh", "deoxys",
                      "solgaleo", "lunala", "necrozma", "cosmog", "cosmoem"] }
}
var BIOME_ORDER = ["forest", "cave", "reef", "volcano", "plant", "marsh", "peak", "ruins", "sky"]

// Found in every biome, weighted.
var COMMON_LOOT = {
  "potion": 6, "super-potion": 3, "hyper-potion": 1, "max-potion": 0.3, "full-restore": 0.15,
  "ether": 3, "leppa-berry": 2, "elixir": 1, "max-ether": 0.5, "max-elixir": 0.2,
  "apple": 6, "big-apple": 1.2, "golden-apple": 0.15, "razz-berry": 1.5, "nanab-berry": 1.5, "moomoo-milk": 1,
  "full-heal": 2, "lum-berry": 0.8, "revive": 1, "max-revive": 0.2, "escape-rope": 0.8,
  "poke-ball": 4, "great-ball": 2, "ultra-ball": 0.6,
  "oran-berry": 2, "sitrus-berry": 1, "exp-candy-xs": 3, "exp-candy-s": 2, "exp-candy-m": 1, "exp-candy-l": 0.4,
  "rare-candy": 0.3, "bottle-cap": 0.1
}
var BIOME_LOOT_WEIGHT = 2.5         // each biome item, next to the common ones

var WEATHER_NAMES = { "": "Clear", rain: "Rain", sun: "Harsh sunlight", sand: "Sandstorm", hail: "Hail", fog: "Fog" }
var WEATHER_ICONS = { "": "☀", rain: "🌧", sun: "🔥", sand: "🌪", hail: "❄", fog: "🌫" }
var WEATHER_START = { rain: "It started to rain.", sun: "The sunlight turned harsh.", sand: "A sandstorm kicked up.",
                      hail: "It started to hail.", fog: "A thick fog rolled in." }

// ---- Small helpers ----

function rint(rand, a, b) { return a + Math.floor(rand() * (b - a + 1)) }
function pickR(rand, list, weightOf) {
  var total = 0
  for (var i = 0; i < list.length; i++) total += weightOf(list[i])
  if (total <= 0) return list[Math.floor(rand() * list.length)]
  var r = rand() * total
  for (var j = 0; j < list.length; j++) {
    r -= weightOf(list[j])
    if (r <= 0) return list[j]
  }
  return list[list.length - 1]
}
function pickObj(rand, obj) { return pickR(rand, Object.keys(obj), function(k) { return obj[k] }) }
function pct(v) { return Math.round(v * 100) + "%" }
function itemName(id) { return Pet.itemName(id) }
function article(word) { return /^[AEIOU]/i.test(word) ? "an " + word : "a " + word }

// ---- Rank ----

function record(save) { return save.expedition || Pet.freshRecord() }
function rankIndex(save) {
  var pts = record(save).points, i = 0
  while (i + 1 < RANKS.length && pts >= RANKS[i + 1].points) i++
  return i
}
function rank(save) { return RANKS[rankIndex(save)] }
function nextRank(save) { return RANKS[rankIndex(save) + 1] || null }
function slots(save) { return rank(save).slots }
function capacity(save) { return rank(save).provisions }
function active(save) { return (save.expeditions || []).filter(Pet.expeditionActive) }
function freeSlots(save) { return Math.max(0, slots(save) - active(save).length) }
function biomeOpen(save, id) { return rankIndex(save) >= BIOMES[id].rank }
function difficultyOpen(save, id) { return rankIndex(save) >= DIFFICULTIES[id].rank }

// ---- Wild Pokémon ----

var _pools = {}
// Every non-legendary species of the National Dex that fits the biome, weighted
// by how well its types match and how common it is.
function pool(biome) {
  if (_pools[biome]) return _pools[biome]
  var b = BIOMES[biome], out = []
  for (var s in Info.species) {
    if (Battle.legendary[s] || !Dex.species[s]) continue
    var types = Info.species[s][5], w = 0
    for (var i = 0; i < types.length; i++) w = Math.max(w, (b.types[types[i]] || 0) * (i === 0 ? 1 : 0.7))
    if (w > 0) out.push({ slug: s, w: w * Math.sqrt(Pet.captureRate(s)) })
  }
  _pools[biome] = out
  return out
}

// The family member that makes sense at this level: younger forms below their
// evolution level, evolved ones (usually) above it.
function stageFor(slug, level, rand) {
  while (Dex.species[slug][1] && Pet.evoLevel(slug) > level) slug = Dex.species[slug][1]
  for (var guard = 0; guard < 3; guard++) {
    var kids = Pet.children(slug).filter(function(k) { return Pet.evoLevel(k) <= level && !Battle.legendary[k] })
    if (!kids.length || rand() > 0.75) break
    slug = kids[Math.floor(rand() * kids.length)]
  }
  return slug
}

function movesAt(slug, level) {
  var set = Pet.learnset(slug), known = []
  for (var i = 0; i < set.length; i += 2) {
    if (set[i] > level) continue
    var m = set[i + 1], at = known.indexOf(m)
    if (at >= 0) known.splice(at, 1)
    known.push(m)
  }
  return known.slice(-Pet.MAX_MOVES)
}

function baseTotal(slug) { return Info.species[slug][6].reduce(function(a, b) { return a + b }, 0) }

// A combatant from one of your Pokémon (its current, real stats and moves).
function fromPet(p, ref) {
  var stats = Pet.stats(p).map(function(s) { return s.value })
  var e = Info.species[p.species]
  return {
    ref: ref, name: Pet.name(p.species), species: p.species, shiny: !!p.shiny, level: Pet.level(p),
    types: e[5].slice(), ability: Pet.abilityOf(p.species, p.ability), weight: e[4],
    stats: stats, hp: stats[0], maxhp: stats[0], status: "", sleep: 0, toxic: 0,
    moves: (p.moves || []).map(function(id) { var pp = Pet.move(id).pp || 5; return { id: id, pp: pp, max: pp } }),
    happiness: p.happiness, satiety: p.satiety, boosts: [0, 0, 0, 0, 0, 0, 0, 0],
    xp: 0, evs: [0, 0, 0, 0, 0, 0], happy: 0, kos: 0, fainted: 0
  }
}

// A wild combatant. opts: { shiny, boss, hpMult, strong }
function wild(slug, level, rand, d, opts) {
  opts = opts || {}
  var det = Pet.rollDetails(rand)
  var ivMin = opts.strong ? 25 : d.ivMin
  det.ivs = det.ivs.map(function(v) { return Math.max(v, ivMin) })
  var base = Info.species[slug][6]
  var evs = [0, 0, 0, 0, 0, 0]
  if (d.evs === 1 || opts.strong) evs = [84, 84, 84, 84, 84, 84]
  if (opts.boss && d.evs) {
    // A sensible spread: its best attacking stat and Speed (or HP)
    var atk = base[1] >= base[3] ? 1 : 3
    evs = [0, 0, 0, 0, 0, 0]; evs[atk] = 252; evs[base[5] >= 80 ? 5 : 0] = 252; evs[base[5] >= 80 ? 0 : 2] = 6
  }
  var pseudo = { species: slug, xp: Pet.xpForLevel(level), ivs: det.ivs, nature: det.nature, ability: det.ability, evs: evs }
  var power = opts.power || d.power
  var stats = Pet.stats(pseudo).map(function(s) { return Math.max(1, Math.floor(s.value * power)) })
  var hp = Math.floor(stats[0] * (opts.hpMult || 1))
  var e = Info.species[slug]
  return {
    name: Pet.name(slug), species: slug, shiny: !!opts.shiny, level: Pet.level(pseudo),
    types: e[5].slice(), ability: Pet.abilityOf(slug, det.ability), weight: e[4],
    stats: stats, hp: hp, maxhp: hp, status: "", sleep: 0, toxic: 0, happiness: 50,
    moves: movesAt(slug, level).map(function(id) { var pp = Pet.move(id).pp || 5; return { id: id, pp: pp, max: pp } }),
    boosts: [0, 0, 0, 0, 0, 0, 0, 0], details: det, boss: !!opts.boss
  }
}

function teamLevel(x) {
  var lv = x.team.map(function(m) { return m.level })
  return Math.round(lv.reduce(function(a, b) { return a + b }, 0) / Math.max(1, lv.length))
}

// Wild Pokémon are 0 to 5 levels under your team.
function wildLevel(X, under) { return Math.max(1, teamLevel(X.x) - rint(X.rand, 0, under === undefined ? 5 : under)) }

function pickWild(X, level) {
  var s = pickR(X.rand, pool(X.x.biome), function(o) { return o.w }).slug
  return stageFor(s, level, X.rand)
}

function shinyRoll(X) { return X.rand() < X.shinyOdds }

// ---- The expedition context passed to events ----

function alive(x) { return x.team.filter(function(m) { return m.hp > 0 }) }
function leader(x) { return alive(x)[0] || x.team[0] }
function bestAt(x, stat) {
  var list = alive(x)
  if (!list.length) return null
  return list.reduce(function(a, b) { return b.stats[stat] > a.stats[stat] ? b : a })
}
function refStat(level) { return Math.floor((2 * 80 + 15) * level / 100) + 5 }

// A stat check against an average Pokémon of the same level.
function check(X, m, stat, bias) {
  if (!m) return false
  var p = 0.5 * m.stats[stat] / refStat(m.level) * X.d.check * (bias || 1)
  return X.rand() < Math.max(0.12, Math.min(0.95, p))
}

function hasAbility(x, list) {
  return alive(x).filter(function(m) { return list.indexOf(m.ability) >= 0 })[0] || null
}

function snapshot(x) {
  return x.team.map(function(m) { return [m.hp, m.maxhp, m.status, Math.round(m.satiety)] })
}

function log(X, kind, text, detail) {
  var e = { t: X.at, f: X.f, k: kind, s: text, hp: snapshot(X.x) }
  if (detail && detail.length) e.d = detail
  X.x.log.push(e)
  return e
}

function loot(X, id, n) {
  if (!Items.items[id] && !Dex.items[id]) return
  X.x.loot[id] = (X.x.loot[id] || 0) + (n || 1)
}

function lootRoll(X, biomeShare) {
  var b = BIOMES[X.x.biome]
  if (X.rand() < (biomeShare === undefined ? 0.3 : biomeShare)) return b.loot[Math.floor(X.rand() * b.loot.length)]
  return pickObj(X.rand, COMMON_LOOT)
}

function provision(x, kind) {
  return Object.keys(x.prov).filter(function(id) { return x.prov[id] > 0 && Pet.itemKind(id) === kind })
}
function useProv(x, id) {
  x.prov[id] -= 1
  if (x.prov[id] <= 0) delete x.prov[id]
  x.used[id] = (x.used[id] || 0) + 1
}
function param(id) { return Items.items[id][4] }

// ---- Automatic care ----

function heal(m, share) {
  var before = m.hp
  m.hp = Math.min(m.maxhp, m.hp + Math.max(1, Math.floor(m.maxhp * share)))
  return m.hp - before
}

// Drinks the smallest potion that gets it back over 60%, or the biggest one it has.
function autoPotion(x, m, lines, below) {
  if (m.hp <= 0 || m.hp > m.maxhp * below) return false
  var meds = provision(x, "medicine").sort(function(a, b) { return param(a).hp - param(b).hp })
  if (!meds.length) return false
  var need = (m.maxhp * 0.6 - m.hp) / m.maxhp * 100
  var id = meds.filter(function(i) { return param(i).hp >= need })[0] || meds[meds.length - 1]
  useProv(x, id)
  heal(m, param(id).hp / 100)
  if (param(id).status) { m.status = ""; m.toxic = 0 }
  lines.push(m.name + " used " + article(itemName(id)) + "! (" + pct(m.hp / m.maxhp) + " HP)")
  return true
}

function autoCure(x, m, lines) {
  if (m.hp <= 0 || !m.status || m.status === "slp") return false
  var cures = provision(x, "status")
  if (!cures.length) return false
  useProv(x, cures[0])
  lines.push(m.name + " used " + article(itemName(cures[0])) + " and is cured.")
  m.status = ""; m.toxic = 0
  return true
}

// Restores PP when its best damaging move ran dry or most of its PP is gone.
function autoPP(x, m, lines) {
  if (m.hp <= 0) return false
  var dmg = m.moves.filter(function(mv) { return Pet.move(mv.id).power > 0 || Pet.move(mv.id).category !== "Status" })
  if (!dmg.length) return false
  var left = dmg.reduce(function(a, mv) { return a + mv.pp }, 0), max = dmg.reduce(function(a, mv) { return a + mv.max }, 0)
  var empty = dmg.filter(function(mv) { return mv.pp === 0 })
  if (!empty.length && left > max * 0.25) return false
  var items = provision(x, "pp")
  if (!items.length) return false
  var all = items.filter(function(i) { return param(i).all })
  var one = items.filter(function(i) { return !param(i).all })
  var id = empty.length <= 1 && one.length ? one.sort(function(a, b) { return param(a).pp - param(b).pp })[0] : (all[0] || one[0])
  useProv(x, id)
  var targets = param(id).all ? m.moves : [empty[0] || dmg.reduce(function(a, b) { return b.pp / b.max < a.pp / a.max ? b : a })]
  targets.forEach(function(mv) { mv.pp = Math.min(mv.max, mv.pp + param(id).pp) })
  lines.push(m.name + " used " + article(itemName(id)) + " and got its PP back.")
  return true
}

function autoFood(X, m, lines) {
  if (m.hp <= 0 || m.satiety >= EAT_BELOW) return false
  var food = provision(X.x, "food").sort(function(a, b) { return param(a).food - param(b).food })
  if (!food.length) return false
  var need = 75 - m.satiety
  var id = food.filter(function(i) { return param(i).food >= need })[0] || food[food.length - 1]
  useProv(X.x, id)
  var p = param(id)
  m.satiety = Math.min(100, m.satiety + p.food)
  if (p.happy) m.happy += p.happy
  if (p.hp) heal(m, p.hp / 100)
  lines.push(m.name + " ate " + article(itemName(id)) + ". Fullness " + Math.round(m.satiety) + ".")
  return true
}

// After a battle or an event: everybody patches up.
function care(X, lines) {
  X.x.team.forEach(function(m) {
    autoCure(X.x, m, lines)
    autoPotion(X.x, m, lines, POTION_AFTER_BATTLE)
    autoPP(X.x, m, lines)
  })
}

// A fainting team member: a Revive brings it back on the spot.
function onFaint(X, m, lines) {
  var rev = provision(X.x, "revive").sort(function(a, b) { return param(a).hp - param(b).hp })
  if (rev.length) {
    useProv(X.x, rev[0])
    m.hp = Math.max(1, Math.floor(m.maxhp * param(rev[0]).hp / 100))
    m.status = ""; m.toxic = 0
    lines.push("✚ " + article(itemName(rev[0])).replace(/^./, function(c) { return c.toUpperCase() }) + " brought " + m.name + " back!")
    return
  }
  m.fainted += 1
  m.happy -= 10
}

// Friendship and your partner can keep a team member standing.
function endure(X, m, lines) {
  var x = X.x
  if (x.guard && m.ref !== x.partner) {
    var partner = x.team.filter(function(p) { return p.ref === x.partner && p.hp > 0 })[0]
    if (partner) {
      x.guard = false
      lines.push("★ " + partner.name + " jumped in front of " + m.name + "! It hung on with 1 HP.")
      return true
    }
  }
  if (m.happiness >= 90 && X.rand() < 0.1) {
    lines.push("♥ " + m.name + " toughed it out so you wouldn't feel sad!")
    return true
  }
  return false
}

// ---- Battles ----

function describeFoes(foes) {
  var names = {}
  foes.forEach(function(f) { names[f.name] = (names[f.name] || 0) + 1 })
  return Object.keys(names).map(function(n) {
    var lv = foes.filter(function(f) { return f.name === n }).map(function(f) { return f.level })
    return (names[n] > 1 ? names[n] + " " : "") + (foes.some(function(f) { return f.name === n && f.shiny }) ? "✦ " : "") + n
           + " (Lv. " + Math.min.apply(null, lv) + (Math.max.apply(null, lv) !== Math.min.apply(null, lv) ? "–" + Math.max.apply(null, lv) : "") + ")"
  }).join(", ")
}

// Runs a battle and logs it. opts: { kind, intro, firstStrike, recruit, legend, mult }
function fight(X, foes, opts) {
  opts = opts || {}
  var x = X.x
  var lines = []
  var bench = x.flags.warped !== undefined ? x.team[x.flags.warped] : null
  if (bench) delete x.flags.warped
  var team = x.team.filter(function(m) { return m.hp > 0 && m !== bench })
  var boostNext = x.flags.boost
  delete x.flags.boost
  var ctx = {
    rand: X.rand, weather: ["rain", "sun", "sand", "hail"].indexOf(x.weather) >= 0 ? x.weather : "", fog: x.weather === "fog",
    happyCrit: true, firstStrike: opts.firstStrike,
    say: function(p, text) { if (lines.length < LOG_DETAIL) lines.push(text) },
    onFaint: function(p) { if (p.side === 0) onFaint(X, p, lines) },
    endure: function(p) { return p.side === 0 && endure(X, p, lines) },
    afterTurn: function() { team.forEach(function(m) { autoPotion(x, m, lines, POTION_IN_BATTLE) }) },
    teamBoost: function(p) {
      if (!boostNext) return
      boostNext.forEach(function(b) { if (b[0] === "all" || b[0] === p.ref) Combat.boost(p, b[1], b[2], ctx) })
    }
  }
  if (bench) lines.push(bench.name + " got separated from the team and missed the fight.")
  var hpBefore = team.map(function(m) { return m.hp })
  var result = Combat.battle(team, foes, ctx)
  team.concat(foes).forEach(Combat.afterBattle)

  // Rewards for every wild Pokémon that went down
  var downed = foes.filter(function(f) { return f.hp <= 0 })
  downed.forEach(function(f) { reward(X, f, opts.mult || (f.boss ? 3 : 1)) })

  var who = describeFoes(foes)
  var hurt = team.map(function(m, i) { return m.hp < hpBefore[i] ? m.name + " " + pct(m.hp / m.maxhp) : "" }).filter(String)
  var summary = result === "won" ? "Defeated " + who + "." + (hurt.length ? " (" + hurt.join(", ") + ")" : "")
              : result === "fled" ? who + " ran off after a long fight."
              : "The team was beaten by " + who + "…"
  log(X, opts.kind || "battle", (opts.intro ? opts.intro + " " : "") + summary, lines)

  if (result === "won") {
    if (opts.legend) legendJoin(X, foes[0])
    else if (opts.recruit !== false) downed.forEach(function(f) { recruitRoll(X, f, opts.recruitMult || 1) })
    if (hasAbility(x, ["pickup"]) && X.rand() < 0.15) {
      var m = hasAbility(x, ["pickup"]), id = lootRoll(X, 0.2)
      loot(X, id, 1)
      log(X, "item", m.name + " picked up " + article(itemName(id)) + " after the battle.")
    }
  }
  var careLines = []
  care(X, careLines)
  if (careLines.length) log(X, "care", careLines.join(" "))
  return result
}

function reward(X, f, mult) {
  var x = X.x
  var xp = (3 + baseTotal(f.species) / 120) * X.d.xp * mult
  var yieldEv = (Battle.evs[f.species] || "000000").split("").map(Number)
  x.kos += 1
  x.money += COINS_PER_KO * X.d.coins * Math.min(mult, 3)
  x.team.forEach(function(m) {
    if (m.hp > 0) {
      m.xp += xp
      m.kos += 1
      for (var i = 0; i < 6; i++) m.evs[i] += yieldEv[i] * Math.min(2, mult)
    } else {
      m.xp += xp / 2
    }
  })
}

function recruitRoll(X, f, mult) {
  var x = X.x
  if (x.recruits.length >= X.d.recruits || f.boss) return
  var lead = leader(x)
  var chance = RECRUIT_ODDS * Math.pow(Pet.captureRate(f.species) / 255, 0.75) * (0.75 + (lead ? lead.happiness : 50) / 200)
  if (f.shiny) chance *= 3
  if (X.rand() >= chance * mult) return
  x.recruits.push({ species: f.species, level: f.level, shiny: f.shiny, ivs: f.details.ivs, ability: f.details.ability, nature: f.details.nature })
  log(X, "recruit", "★ The " + (f.shiny ? "shiny " : "") + f.name + " got up and wants to join your team!")
}

function legendJoin(X, f) {
  var x = X.x
  var seen = ((record(X.save).legends[x.biome] || {})[f.species]) || 0
  if (seen < 2) {
    log(X, "legend", "✦ " + f.name + " looked at your team for a long moment… then vanished. Maybe it will come back.")
    return
  }
  var odds = Battle.legendary[f.species] === 2 ? MYTHICAL_JOIN : LEGEND_JOIN
  if (X.rand() < odds) {
    x.recruits.push({ species: f.species, level: f.level, shiny: f.shiny, ivs: f.details.ivs, ability: f.details.ability,
                      nature: f.details.nature, legend: true })
    log(X, "recruit", "✦ " + f.name + " recognized your team from before. It wants to come with you!")
  } else {
    log(X, "legend", "✦ " + f.name + " nodded at your team, then disappeared again.")
  }
}

function wildBattle(X, opts) {
  opts = opts || {}
  var n = opts.count || 1 + pickR(X.rand, [0, 1, 2], function(i) { return X.d.pack[i] })
  var lv = wildLevel(X)
  var first = pickWild(X, lv)
  var foes = []
  for (var i = 0; i < n; i++) {
    var l = i === 0 ? lv : wildLevel(X)
    // Packs are usually the same species
    var s = i > 0 && X.rand() < 0.6 ? stageFor(first, l, X.rand) : pickWild(X, l)
    foes.push(wild(s, l, X.rand, X.d, { shiny: shinyRoll(X) || (opts.shiny && i === 0) }))
  }
  var intro = (n > 1 ? "A group of wild Pokémon jumped out!" : "A wild " + (foes[0].shiny ? "shiny " : "") + foes[0].name + " appeared!")
  // Ambush: they strike first unless your fastest Pokémon saw them coming
  var firstStrike = ""
  if (opts.ambush) {
    var fast = bestAt(X.x, 5)
    if (fast && fast.stats[5] >= Math.max.apply(null, foes.map(function(f) { return f.stats[5] }))) intro = "An ambush! But " + fast.name + " saw it coming."
    else { intro = "Ambush! The wild Pokémon attacked first!"; firstStrike = "foes" }
  }
  return fight(X, foes, { intro: intro, firstStrike: firstStrike, kind: opts.kind })
}

function bossBattle(X) {
  var lv = wildLevel(X, 2)
  // The strongest of a few candidates, fully grown
  var best = null
  for (var i = 0; i < 6; i++) {
    var s = pickWild(X, lv)
    while (Pet.children(s).filter(function(k) { return Pet.evoLevel(k) <= lv && !Battle.legendary[k] }).length)
      s = Pet.children(s).filter(function(k) { return Pet.evoLevel(k) <= lv && !Battle.legendary[k] })[0]
    if (!best || baseTotal(s) > baseTotal(best)) best = s
  }
  var boss = wild(best, lv, X.rand, X.d, { boss: true, hpMult: X.d.bossHp, power: X.d.power + BOSS_POWER, shiny: shinyRoll(X) })
  var r = fight(X, [boss], { kind: "boss", intro: "☠ The floor's boss, a mighty " + boss.name + " (Lv. " + boss.level + "), blocks the stairs!", recruit: false })
  if (r === "won") {
    X.x.bosses += 1
    X.x.money += COINS_PER_BOSS * X.d.coins
    var items = []
    for (var k = 0; k < 2 + Math.floor(X.rand() * 2); k++) { var id = lootRoll(X, 0.55); loot(X, id, 1); items.push(itemName(id)) }
    log(X, "item", "The boss left a treasure chest: " + items.join(", ") + ".")
  }
  return r
}

function legendCandidates(X) {
  return BIOMES[X.x.biome].legends.filter(function(s) {
    return Info.species[s] && Battle.legendary[s] && legendTier(s) <= X.d.tier
  })
}

function legendBattle(X) {
  var list = legendCandidates(X)
  if (!list.length) return bossBattle(X)
  var slug = pickR(X.rand, list, function(s) { return Battle.legendary[s] === 2 ? 0.4 : 1 })
  var rec = record(X.save)
  if (!rec.legends[X.x.biome]) rec.legends[X.x.biome] = {}
  rec.legends[X.x.biome][slug] = (rec.legends[X.x.biome][slug] || 0) + 1
  Pet.markSeen(X.save, slug)
  var lv = wildLevel(X, 2)
  var foe = wild(slug, lv, X.rand, X.d, { boss: true, strong: true, hpMult: 3, power: LEGEND_POWER, shiny: shinyRoll(X) })
  X.x.legend = slug
  var r = fight(X, [foe], { kind: "legend", legend: true, mult: 5,
                            intro: "✦ The air trembles… The legendary " + (foe.shiny ? "shiny " : "") + foe.name + " (Lv. " + foe.level + ") appeared!" })
  if (r === "won") {
    X.x.money += COINS_PER_LEGEND * X.d.coins
    var id = lootRoll(X, 0.8)
    loot(X, id, 2)
    log(X, "item", foe.name + " left something shiny behind: 2 × " + itemName(id) + ".")
  }
  return r
}

// ---- Event catalog ----
// w: weight, min: lowest difficulty index, biomes: where (all if absent),
// when(X): extra condition, run(X): what happens (it logs on its own).

function randomMember(X) { var a = alive(X.x); return a[Math.floor(X.rand() * a.length)] }
function natureOf(m) { return m.nature !== undefined ? Pet.natureName(m.nature) : "" }
function natureIn(m, list) { return list.indexOf(natureOf(m)) >= 0 }

var EVENTS = [
  // -- Exploration
  { id: "locked-chest", w: 4, run: function(X) {
      var m = hasAbility(X.x, ["pickpocket", "pickup", "technician"]) || bestAt(X.x, 1)
      if (m.ability === "pickpocket" || m.ability === "pickup" || check(X, m, 1)) {
        var id = lootRoll(X, 0.5); loot(X, id, 1)
        log(X, "item", m.name + " forced open a locked chest: " + article(itemName(id)) + "!")
      } else log(X, "event", "A locked chest… " + m.name + " pushed and pulled, but it wouldn't budge.")
  } },
  { id: "trapped-chest", w: 3, run: function(X) {
      var m = bestAt(X.x, 3)
      if (check(X, m, 3)) {
        var id = lootRoll(X, 0.6); loot(X, id, 1)
        log(X, "item", m.name + " noticed the wire on a chest and disarmed it. Inside: " + article(itemName(id)) + ".")
      } else {
        alive(X.x).forEach(function(t) { t.hp = Math.max(1, t.hp - Math.floor(t.maxhp * 0.15)) })
        log(X, "trap", "The chest exploded! Everyone took some damage, and the loot is gone.")
      }
  } },
  { id: "spring", w: 3, run: function(X) {
      alive(X.x).forEach(function(m) { heal(m, m.types.indexOf("water") >= 0 ? 0.4 : 0.3) })
      log(X, "event", "A clear spring. The team drank and felt refreshed.")
  } },
  { id: "berry-patch", w: 3, biomes: ["forest", "reef", "marsh", "sky", "plant", "cave", "volcano", "peak", "ruins"], run: function(X) {
      alive(X.x).forEach(function(m) { m.satiety = Math.min(100, m.satiety + (m.types.indexOf("grass") >= 0 ? 40 : 20)) })
      var id = X.rand() < 0.5 ? "razz-berry" : "nanab-berry"
      loot(X, id, 1)
      log(X, "event", "A patch of wild berries! The team snacked and kept " + article(itemName(id)) + " for later.")
  } },
  { id: "hidden-stairs", w: 2, when: function(X) { return X.f < X.x.floors - 1 && !hasBoss(X.x, X.f + 1) }, run: function(X) {
      var m = hasAbility(X.x, ["keen-eye", "illuminate", "frisk", "compound-eyes", "forewarn", "anticipation"])
      if (m || check(X, bestAt(X.x, 3), 3, 0.5)) {
        X.x.flags.skip = true
        log(X, "event", (m ? m.name + " spotted" : "The team stumbled on") + " a hidden staircase and skipped ahead a floor!")
      } else log(X, "event", "The team walked right past something odd on the wall. Probably nothing.")
  } },
  { id: "mural", w: 2, biomes: ["ruins", "cave", "sky", "marsh"], run: function(X) {
      var m = bestAt(X.x, 3)
      if (check(X, m, 3)) {
        alive(X.x).forEach(function(t) { t.xp += 4 * X.d.xp })
        log(X, "event", m.name + " studied an ancient mural and shared what it learned. Everyone gained some XP.")
      } else log(X, "event", "An ancient mural. Nobody could make sense of it, but it looked nice.")
  } },
  { id: "evolution-stone", w: 2, run: function(X) {
      var b = BIOMES[X.x.biome]
      var stones = b.loot.filter(function(i) { return Pet.itemKind(i) === "evolution" })
      if (!stones.length) return
      var id = stones[Math.floor(X.rand() * stones.length)]
      loot(X, id, 1)
      log(X, "item", "Something glimmered between the rocks: " + article(itemName(id)) + "!")
  } },
  { id: "egg", w: 0.25, run: function(X) {
      var s = pickWild(X, 1)
      while (Dex.species[s][1]) s = Dex.species[s][1]
      var det = Pet.rollDetails(X.rand)
      det.ivs = det.ivs.map(function(v) { return Math.max(v, 20) })
      if (X.x.recruits.length >= X.d.recruits + 1) return
      X.x.recruits.push({ species: s, level: 1, shiny: shinyRoll(X), ivs: det.ivs, ability: det.ability, nature: det.nature, egg: true })
      log(X, "recruit", "★ An abandoned Egg! The team carefully carried it along. It hatched into " + Pet.name(s) + "!")
  } },
  { id: "pitfall", w: 2, when: function(X) { return X.f < X.x.floors - 1 && !hasBoss(X.x, X.f + 1) }, run: function(X) {
      var m = bestAt(X.x, 5)
      if (hasAbility(X.x, ["levitate"]) || check(X, m, 5)) log(X, "event", "The floor gave way, but the team jumped back just in time.")
      else {
        alive(X.x).forEach(function(t) { t.hp = Math.max(1, t.hp - Math.floor(t.maxhp * 0.1)) })
        X.x.flags.skip = true
        log(X, "trap", "A pitfall! The team tumbled down to the next floor. Ouch, but at least it was a shortcut.")
      }
  } },
  { id: "lost-bag", w: 3, run: function(X) {
      var kinds = ["medicine", "food", "pp", "status"]
      var pickKind = kinds[Math.floor(X.rand() * kinds.length)]
      var ids = Object.keys(COMMON_LOOT).filter(function(i) { return Pet.itemKind(i) === pickKind })
      var id = pickR(X.rand, ids, function(i) { return COMMON_LOOT[i] })
      loot(X, id, 1)
      log(X, "item", "Someone dropped their bag here. The team found " + article(itemName(id)) + ".")
  } },
  { id: "ball-cache", w: 2, run: function(X) {
      var id = X.rand() < 0.25 ? "great-ball" : "poke-ball", n = rint(X.rand, 1, 3)
      loot(X, id, n)
      log(X, "item", "An old explorer's stash: " + n + " × " + itemName(id) + ".")
  } },
  // -- Traps
  { id: "sleep-trap", w: 2, trap: true, run: function(X) {
      var m = randomMember(X)
      if (["insomnia", "vital-spirit", "sweet-veil", "levitate"].indexOf(m.ability) >= 0) {
        log(X, "trap", "A Sleep Trap went off under " + m.name + ", who didn't even yawn.")
        return
      }
      m.status = "slp"; m.sleep = 2
      log(X, "trap", "A Sleep Trap! " + m.name + " dozed off and will sleep through the start of the next fight.")
  } },
  { id: "poison-trap", w: 2, trap: true, run: function(X) {
      var m = randomMember(X)
      if (m.types.indexOf("poison") >= 0 || m.types.indexOf("steel") >= 0 || m.ability === "immunity" || m.ability === "levitate" || m.status) {
        log(X, "trap", "A Poison Trap sprayed " + m.name + ", who shook it off.")
        return
      }
      m.status = "psn"
      log(X, "trap", "A Poison Trap! " + m.name + " was poisoned.")
      var lines = []; autoCure(X.x, m, lines); if (lines.length) log(X, "care", lines.join(" "))
  } },
  { id: "sticky-trap", w: 1.5, trap: true, when: function(X) { return Object.keys(X.x.prov).length > 0 }, run: function(X) {
      var ids = Object.keys(X.x.prov)
      var id = ids[Math.floor(X.rand() * ids.length)]
      X.x.prov[id] -= 1
      if (X.x.prov[id] <= 0) delete X.x.prov[id]
      X.x.lost[id] = (X.x.lost[id] || 0) + 1
      log(X, "trap", "A Sticky Trap! " + article(itemName(id)).replace(/^./, function(c) { return c.toUpperCase() }) + " got stuck to the floor and had to be left behind.")
  } },
  { id: "warp-trap", w: 1.5, trap: true, when: function(X) { return alive(X.x).length > 1 }, run: function(X) {
      var m = randomMember(X)
      X.x.flags.warped = X.x.team.indexOf(m)
      log(X, "trap", "A Warp Trap! " + m.name + " was whisked away and will be busy finding its way back.")
  } },
  { id: "hunger-trap", w: 1.5, trap: true, run: function(X) {
      alive(X.x).forEach(function(m) { m.satiety = Math.max(0, m.satiety - 25) })
      log(X, "trap", "A Hunger Trap! Everyone's stomach growled at once.")
  } },
  { id: "rock-trap", w: 2, trap: true, run: function(X) {
      var m = randomMember(X)
      if (m.types.indexOf("rock") >= 0 || m.types.indexOf("steel") >= 0 || check(X, m, 2)) {
        log(X, "trap", "Rocks fell from the ceiling! " + m.name + " took them without flinching.")
        return
      }
      var d = Math.floor(m.maxhp * 0.2)
      m.hp = Math.max(1, m.hp - d)
      log(X, "trap", "Rocks fell on " + m.name + "! (" + pct(m.hp / m.maxhp) + " HP)")
  } },
  { id: "pp-trap", w: 1, trap: true, run: function(X) {
      var m = randomMember(X)
      m.moves.forEach(function(mv) { mv.pp = Math.max(0, mv.pp - 3) })
      log(X, "trap", "A PP-Zero Trap drained " + m.name + "'s moves a little.")
  } },
  { id: "spin-trap", w: 1, trap: true, run: function(X) {
      X.x.flags.boost = [["all", 6, -1]]
      log(X, "trap", "A Spin Trap! The whole team is dizzy: their accuracy will drop in the next fight.")
  } },
  // -- People and Pokémon you meet
  { id: "kecleon", w: 1.5, min: 1, run: function(X) {
      var x = X.x, items = Object.keys(x.loot).filter(function(i) { return x.loot[i] > 0 && Pet.itemKind(i) !== "evolution" })
      var lead = leader(x)
      if (natureIn(lead, ["Naughty", "Rash", "Hasty", "Naive"]) && X.rand() < 0.5) {
        if (check(X, bestAt(x, 5), 5, 0.8)) {
          var id = lootRoll(X, 0.6); loot(X, id, 1)
          log(X, "event", "A Kecleon shop! " + lead.name + " grabbed " + article(itemName(id)) + " and ran for it… and got away with it!")
        } else {
          var lv = teamLevel(x)
          var shop = wild("kecleon", lv, X.rand, X.d, { boss: true, strong: true, hpMult: 2, power: LEGEND_POWER })
          fight(X, [shop], { kind: "boss", intro: "A Kecleon shop! " + lead.name + " tried to steal… Kecleon is furious!", recruit: false })
        }
        return
      }
      if (!items.length) { log(X, "event", "A Kecleon shop! The team had nothing to trade, so they just waved."); return }
      var give = items[Math.floor(X.rand() * items.length)]
      x.loot[give] -= 1
      if (x.loot[give] <= 0) delete x.loot[give]
      var get = lootRoll(X, 0.7)
      loot(X, get, 1)
      log(X, "event", "A Kecleon shop! The team traded " + article(itemName(give)) + " for " + article(itemName(get)) + ".")
  } },
  { id: "kangaskhan", w: 1, min: 1, run: function(X) {
      X.x.safe = JSON.parse(JSON.stringify(X.x.loot))
      log(X, "event", "A Kangaskhan Storage! The team stored everything it found so far, safe whatever happens.")
  } },
  { id: "chansey", w: 1.2, run: function(X) {
      X.x.team.forEach(function(m) { m.hp = m.maxhp; m.status = ""; m.toxic = 0 })
      log(X, "event", "A wandering Chansey healed the whole team, even the ones who had fainted. ♥")
  } },
  { id: "slowpoke", w: 1, when: function(X) { return X.f < X.x.floors - 2 && !X.x.flags.escort }, run: function(X) {
      X.x.flags.escort = X.f + 2
      log(X, "event", "A lost Slowpoke… it has been here a while. The team offered to take it to the next floors.")
  } },
  { id: "explorer", w: 1.2, run: function(X) {
      var x = X.x, food = provision(x, "food")
      var lead = leader(x)
      if (food.length && lead.happiness >= 50) {
        useProv(x, food[0])
        alive(x).forEach(function(m) { m.happy += 8 })
        var id = lootRoll(X, 0.7); loot(X, id, 1)
        log(X, "team", "An injured explorer! " + lead.name + " shared " + article(itemName(food[0])) + ". As thanks, they gave " + article(itemName(id)) + ".")
      } else log(X, "event", "An injured explorer asked for food, but the team had none to spare. They wished the team luck.")
  } },
  { id: "smeargle", w: 0.8, run: function(X) {
      alive(X.x).forEach(function(m) { m.happy += 5 })
      log(X, "team", "A Smeargle painted the team's portrait. They look so heroic! Everyone's happier.")
  } },
  { id: "wobbuffet", w: 0.8, run: function(X) {
      var m = bestAt(X.x, 3)
      if (check(X, m, 3)) log(X, "event", "A Wobbuffet blocked the way. " + m.name + " outsmarted it with a special attack.")
      else {
        var p = bestAt(X.x, 1)
        p.hp = Math.max(1, p.hp - Math.floor(p.maxhp * 0.15))
        log(X, "event", "A Wobbuffet blocked the way. " + p.name + " punched it… and the hit came right back! (" + pct(p.hp / p.maxhp) + " HP)")
      }
  } },
  // -- Team life (natures)
  { id: "quarrel", w: 1.2, when: function(X) { return alive(X.x).length > 1 }, run: function(X) {
      var a = alive(X.x)
      var m1 = a[0], m2 = a[1 + Math.floor(X.rand() * (a.length - 1))]
      var lead = leader(X.x)
      if (lead.happiness >= 80) { log(X, "team", m1.name + " and " + m2.name + " started bickering, but " + lead.name + " calmed them down."); return }
      m1.happy -= 5; m2.happy -= 5
      log(X, "team", m1.name + " and " + m2.name + " had a quarrel about which way to go. Nobody was right.")
  } },
  { id: "buddies", w: 1.2, when: function(X) { return alive(X.x).length > 1 }, run: function(X) {
      var a = alive(X.x), pair = null
      for (var i = 0; i < a.length && !pair; i++)
        for (var j = i + 1; j < a.length && !pair; j++)
          if (a[i].types.some(function(t) { return a[j].types.indexOf(t) >= 0 })) pair = [a[i], a[j]]
      if (!pair) pair = [a[0], a[1]]
      X.x.flags.boost = [[pair[0].ref, 1, 1], [pair[1].ref, 1, 1], [pair[0].ref, 3, 1], [pair[1].ref, 3, 1]]
      pair[0].happy += 3; pair[1].happy += 3
      log(X, "team", pair[0].name + " and " + pair[1].name + " are getting along great. They'll fight side by side next time!")
  } },
  { id: "glutton", w: 1, when: function(X) { return provision(X.x, "food").length > 0 }, run: function(X) {
      var m = alive(X.x).filter(function(t) { return natureIn(t, ["Naughty", "Naive", "Lax", "Hasty", "Impish"]) })[0]
      if (!m) return
      var id = provision(X.x, "food")[0]
      useProv(X.x, id)
      m.satiety = Math.min(100, m.satiety + param(id).food)
      log(X, "team", m.name + " sneaked into the bag and ate " + article(itemName(id)) + " when nobody was looking.")
  } },
  { id: "brave", w: 1, run: function(X) {
      var m = alive(X.x).filter(function(t) { return natureIn(t, ["Brave", "Adamant", "Lonely", "Naughty"]) })[0]
      if (!m) return
      X.x.flags.boost = [[m.ref, 1, 1]]
      log(X, "team", m.name + " marched ahead, fired up. It'll hit harder in the next fight.")
  } },
  { id: "timid", w: 1, run: function(X) {
      var m = alive(X.x).filter(function(t) { return natureIn(t, ["Timid", "Modest", "Calm", "Gentle"]) })[0]
      if (!m) return
      X.x.flags.boost = [["all", 7, 1]]
      log(X, "team", m.name + " is a bit nervous and keeps a lookout. The team will be harder to hit next fight.")
  } },
  { id: "campfire", w: 1.5, run: function(X) {
      var a = alive(X.x)
      a.forEach(function(m) { heal(m, 0.1); m.happy += 5 })
      var stories = [
        " told a scary story. Nobody slept.",
        " fell asleep first and snored all night.",
        " insisted on keeping watch, then dozed off.",
        " roasted berries a bit too long. Crunchy!"
      ]
      log(X, "team", "Campfire time. " + a[Math.floor(X.rand() * a.length)].name + stories[Math.floor(X.rand() * stories.length)])
  } },
  // -- Odd things
  { id: "old-rod", w: 0.6, run: function(X) {
      loot(X, "poke-ball", 1)
      log(X, "event", randomMember(X).name + " found an Old Rod. Nobody knows why it's here. There was a Poké Ball tied to the line.")
  } },
  { id: "magikarp", w: 0.6, run: function(X) {
      log(X, "event", "A Magikarp out of water flopped around. " + randomMember(X).name + " stared at it. It stared back. Nothing happened.")
  } },
  { id: "psyduck", w: 0.6, run: function(X) {
      X.x.flags.boost = [["all", 6, -1]]
      log(X, "event", "A Psyduck has a headache. Now the whole team has a headache too.")
  } },
  { id: "snorlax", w: 0.8, run: function(X) {
      var m = bestAt(X.x, 1)
      if (check(X, m, 1, 0.8)) log(X, "event", "A Snorlax was blocking the corridor. " + m.name + " pushed it out of the way!")
      else {
        alive(X.x).forEach(function(t) { t.satiety = Math.max(0, t.satiety - 15) })
        log(X, "event", "A Snorlax was blocking the corridor. The team had to take the long way around.")
      }
  } },
  { id: "sudowoodo", w: 0.8, run: function(X) {
      var water = alive(X.x).filter(function(m) { return m.moves.some(function(mv) { return Pet.move(mv.id).type === "water" }) })[0]
      if (!water) { log(X, "event", "A tree stood in the middle of the corridor. A very suspicious tree. The team walked around it."); return }
      var foe = wild("sudowoodo", wildLevel(X), X.rand, X.d, { shiny: shinyRoll(X) })
      fight(X, [foe], { intro: water.name + " watered a strange tree… It was a Sudowoodo!" })
  } },
  { id: "ditto-chest", w: 0.8, run: function(X) {
      var foe = wild("ditto", wildLevel(X), X.rand, X.d, { shiny: shinyRoll(X) })
      if (fight(X, [foe], { intro: "That treasure chest has a face… It's a Ditto!" }) === "won") {
        var id = lootRoll(X, 0.5); loot(X, id, 1)
        log(X, "item", "The real chest was right behind it: " + article(itemName(id)) + ".")
      }
  } },
  { id: "diglett", w: 0.6, run: function(X) {
      if (X.rand() < 0.5) { loot(X, "exp-candy-s", 1); log(X, "item", "A Diglett popped out, dropped an Exp. Candy S and vanished. The rest of its body remains a mystery.") }
      else log(X, "event", "A Diglett popped out of the ground. The rest of its body remains a mystery.")
  } },
  // -- Rare
  { id: "mew", w: 0.05, min: 3, run: function(X) {
      loot(X, "rare-candy", 3)
      alive(X.x).forEach(function(m) { m.happy += 10 })
      Pet.markSeen(X.save, "mew")
      log(X, "legend", "✦ A pink glow… Mew played with the team for a while, then left 3 Rare Candies behind!")
  } },
  { id: "jirachi", w: 0.04, min: 3, run: function(X) {
      var gifts = [["rare-candy", 5], ["gold-bottle-cap", 1], ["master-ball", 1]]
      var g = gifts[Math.floor(X.rand() * gifts.length)]
      loot(X, g[0], g[1])
      Pet.markSeen(X.save, "jirachi")
      log(X, "legend", "✦ Jirachi woke up for a moment and granted the team a wish: " + g[1] + " × " + itemName(g[0]) + "!")
  } },
  { id: "distortion", w: 0.2, min: 2, run: function(X) {
      var other = BIOME_ORDER.filter(function(b) { return b !== X.x.biome })
      var to = other[Math.floor(X.rand() * other.length)]
      X.x.biome = to
      X.x.weather = ""
      log(X, "danger", "The world twisted… The team came out in " + BIOMES[to].name + "!")
  } }
]

// Combat events, picked like the others
var BATTLE_EVENTS = [
  { id: "wild", w: 10, run: function(X) { return wildBattle(X) } },
  { id: "ambush", w: 1.2, run: function(X) { return wildBattle(X, { ambush: true }) } },
  { id: "monster-house", w: 0.35, min: 2, run: function(X) {
      var runner = hasAbility(X.x, ["run-away"])
      if (runner) { log(X, "danger", "A Monster House! " + runner.name + " led the team out before anyone noticed."); return "won" }
      var r = wildBattle(X, { count: rint(X.rand, 4, 6), kind: "danger" })
      if (r === "won") {
        var items = []
        for (var i = 0; i < 3; i++) { var id = lootRoll(X, 0.4); loot(X, id, 1); items.push(itemName(id)) }
        log(X, "item", "The Monster House was full of items: " + items.join(", ") + ".")
      }
      return r
  } },
  { id: "rival", w: 0.4, min: 2, run: function(X) {
      var foes = []
      for (var i = 0; i < 3; i++) { var lv = wildLevel(X, 2); foes.push(wild(pickWild(X, lv), lv, X.rand, X.d, { strong: true })) }
      var r = fight(X, foes, { kind: "boss", intro: "A rival exploration team challenged yours!", recruit: false, mult: 2 })
      if (r === "won") { var id = lootRoll(X, 0.5); loot(X, id, 2); log(X, "item", "The rivals handed over their prize: 2 × " + itemName(id) + ".") }
      return r
  } },
  { id: "shiny", w: 0.06, run: function(X) { return wildBattle(X, { count: 1, shiny: true }) } },
  { id: "scared", w: 1, run: function(X) {
      var lv = wildLevel(X), s = pickWild(X, lv)
      var foe = wild(s, lv, X.rand, X.d)
      var fast = bestAt(X.x, 5)
      if (fast.stats[5] > foe.stats[5]) {
        var id = lootRoll(X, 0.2); loot(X, id, 1)
        log(X, "event", "A wild " + foe.name + " panicked at the sight of " + fast.name + " and ran, dropping " + article(itemName(id)) + ".")
        return "won"
      }
      return fight(X, [foe], { intro: "A wild " + foe.name + " was startled and attacked!" })
  } }
]

function eligible(list, X) {
  var di = DIFFICULTY_ORDER.indexOf(X.x.diff)
  return list.filter(function(e) {
    return (e.min || 0) <= di && (!e.biomes || e.biomes.indexOf(X.x.biome) >= 0) && (!e.when || e.when(X))
  })
}

// ---- Floors ----

function stepsOf(x, f) {
  var d = DIFFICULTIES[x.diff]
  return rint(Pet.seeded(x.seed + ":steps:" + f), d.steps[0], d.steps[1])
}

function floorStart(x, f) { return x.start + (f - 1) * x.floorMs }

function hasBoss(x, f) { return DIFFICULTIES[x.diff].boss.indexOf(f) >= 0 || x.legendFloor === f }

function simulateFloor(save, x, f, shinyOdds) {
  var X = { save: save, x: x, d: DIFFICULTIES[x.diff], f: f, rand: Pet.seeded(x.seed + ":floor:" + f), shinyOdds: shinyOdds }
  var t0 = floorStart(x, f), steps = stepsOf(x, f)
  X.at = t0

  // Weather
  if (x.weatherLeft > 0) {
    x.weatherLeft -= 1
    if (x.weatherLeft === 0 && x.weather) { log(X, "weather", WEATHER_ICONS[""] + " The weather cleared up."); x.weather = "" }
  } else if (X.rand() < 0.18) {
    var w = pickObj(X.rand, BIOMES[x.biome].weather)
    if (w !== x.weather) {
      x.weather = w; x.weatherLeft = 3
      log(X, "weather", WEATHER_ICONS[w] + " " + WEATHER_START[w])
    }
  }

  for (var s = 0; s < steps && x.status === "running"; s++) {
    X.at = t0 + Math.round(x.floorMs * (s + 1) / (steps + 1))
    if (x.flags.skip) break
    var last = s === steps - 1
    if (last && x.legendFloor === f) legendBattle(X)
    else if (last && X.d.boss.indexOf(f) >= 0) bossBattle(X)
    else {
      var r = X.rand()
      var e
      if (r < 0.48) e = pickR(X.rand, eligible(BATTLE_EVENTS, X), function(v) { return v.w })
      else if (r < 0.62) {
        var id = lootRoll(X, 0.3), n = Pet.itemKind(id) === "ball" ? rint(X.rand, 1, 2) : 1
        if (hasAbility(x, ["pickup", "honey-gather"]) && X.rand() < 0.4) n += 1
        loot(X, id, n)
        log(X, "item", "Found " + (n > 1 ? n + " × " + itemName(id) : article(itemName(id))) + ".")
        continue
      } else {
        var pool = eligible(EVENTS, X)
        var traps = r < 0.72
        var list = pool.filter(function(v) { return !!v.trap === traps })
        e = pickR(X.rand, list.length ? list : pool, function(v) { return v.w })
      }
      if (e) e.run(X)
    }
    if (checkEnd(X)) return
  }

  // Walking on: hunger, a bit of HP back, the Slowpoke escort
  X.at = t0 + x.floorMs
  var weatherHunger = x.weather === "sun" ? 1.4 : 1
  var lines = []
  alive(x).forEach(function(m) {
    m.satiety = Math.max(0, m.satiety - HUNGER_PER_FLOOR * BIOMES[x.biome].hunger * weatherHunger)
    autoFood(X, m, lines)
    if (m.satiety <= 0) {
      m.hp = Math.max(0, m.hp - Math.floor(m.maxhp * STARVING_DAMAGE))
      m.happy -= 2
      lines.push(m.name + " is starving! (" + pct(m.hp / m.maxhp) + " HP)")
      if (m.hp <= 0) { onFaint(X, m, lines); if (m.hp <= 0) lines.push(m.name + " collapsed from hunger…") }
    } else heal(m, REGEN_PER_FLOOR)
    if (m.status === "psn" || m.status === "tox") {
      m.hp = Math.max(1, m.hp - Math.floor(m.maxhp / 16))
    }
  })
  if (lines.length) log(X, "care", lines.join(" "))
  if (x.flags.escort === f) {
    var id = X.rand() < 0.3 ? "rare-candy" : "exp-candy-m"
    loot(X, id, 1)
    log(X, "event", "The Slowpoke found its family! It slowly handed over " + article(itemName(id)) + ". Very slowly.")
    delete x.flags.escort
  }
  x.floor = f
  x.money += COINS_PER_FLOOR * X.d.coins
  if (checkEnd(X)) return
  if (x.flags.skip && f < x.floors) {
    delete x.flags.skip
    x.floor = f + 1
    log(X, "info", "B" + (f + 1) + "F skipped.")
  }
  delete x.flags.skip
}

// Wipe-out or an Escape Rope: returns true when the expedition is over.
function checkEnd(X) {
  var x = X.x
  var up = alive(x)
  if (!up.length) {
    log(X, "danger", "The whole team fainted… A rescue team brought them home, but half of the items were lost.")
    finish(X.save, x, X.at, "failed")
    return true
  }
  var ropes = provision(x, "escape")
  if (ropes.length && x.team.length > 1 && up.length === 1 && up[0].hp < up[0].maxhp / 2 && !provision(x, "revive").length) {
    useProv(x, ropes[0])
    log(X, "info", up[0].name + " used an Escape Rope and got everybody out safely, with all the loot.")
    finish(X.save, x, X.at, "escaped")
    return true
  }
  return false
}

// ---- Life cycle ----

// Launch a new expedition. opts: { biome, diff, team: [roots], provisions: { id: n } }
// Returns "" on success, or why it can't go.
function launch(save, opts, now) {
  var b = BIOMES[opts.biome], d = DIFFICULTIES[opts.diff]
  if (!b || !d) return "Pick a destination and a difficulty."
  if (!biomeOpen(save, b.id)) return b.name + " opens at the " + RANKS[b.rank].name + " rank."
  if (!difficultyOpen(save, d.id)) return d.name + " expeditions open at the " + RANKS[d.rank].name + " rank."
  if (freeSlots(save) <= 0) return "Your rank allows " + slots(save) + " expedition" + (slots(save) > 1 ? "s" : "") + " at a time."
  var team = (opts.team || []).filter(function(r, i, a) { return save.pets[r] && a.indexOf(r) === i })
  if (!team.length) return "Choose up to " + TEAM_SIZE + " Pokémon."
  if (team.length > TEAM_SIZE) return "A team has " + TEAM_SIZE + " Pokémon at most."
  for (var i = 0; i < team.length; i++) if (Pet.isAway(save, team[i])) return Pet.name(save.pets[team[i]].species) + " is already away."
  var prov = {}, count = 0
  for (var id in opts.provisions || {}) {
    var n = Math.floor(opts.provisions[id] || 0)
    if (n <= 0) continue
    if (!Pet.isProvision(id) || (save.bag[id] || 0) < n) return "You don't have that many " + itemName(id) + "."
    prov[id] = n; count += n
  }
  if (count > capacity(save)) return "The bag holds " + capacity(save) + " provisions at your rank."

  for (var p in prov) { save.bag[p] -= prov[p]; if (save.bag[p] <= 0) delete save.bag[p] }
  team.forEach(function(r) { if (save.pets[r].training) Pet.stopTraining(save, r) })

  var seed = String(now) + ":" + team.join(",") + ":" + b.id
  var rand = Pet.seeded(seed + ":launch")
  var members = team.map(function(r) {
    var m = fromPet(save.pets[r], r)
    m.nature = save.pets[r].nature
    return m
  })
  var x = {
    id: "x" + now, biome: b.id, home: b.id, diff: d.id, seed: seed, start: now, floors: d.floors,
    floorMs: Math.round(d.minutes * 60000 / d.floors), floor: 0, status: "running",
    team: members, partner: save.current, guard: team.indexOf(save.current) >= 0 && team.length > 1,
    prov: prov, packed: JSON.parse(JSON.stringify(prov)), used: {}, lost: {}, loot: {}, safe: null, recruits: [],
    log: [], flags: {}, weather: "", weatherLeft: 0, kos: 0, bosses: 0, legend: "", money: 0,
    legendFloor: rand() < d.legend && legendPossible(b.id, d) ? Math.max(1, d.floors - Math.floor(rand() * Math.ceil(d.floors / 2))) : 0,
    seen: false
  }
  x.log.push({ t: now, f: 0, k: "info", s: "The team set off for " + b.name + " (" + d.name + ", " + d.floors + " floors).", hp: snapshot(x) })
  save.expeditions.push(x)
  return ""
}

function legendPossible(biome, d) {
  return BIOMES[biome].legends.some(function(s) { return Info.species[s] && Battle.legendary[s] && legendTier(s) <= d.tier })
}

// Calls the team back: it stops exploring and walks home.
function recall(save, id, now) {
  var x = find(save, id)
  if (!x || x.status !== "running") return false
  advance(save, x, now, Pet.shinyOdds(save))
  if (x.status !== "running") return true
  x.status = "returning"
  x.recalledAt = now
  x.returnAt = now + Math.min(RETURN_CAP, Math.round((now - x.start) / 2))
  x.log.push({ t: now, f: x.floor, k: "info", s: "You called the team back. They're heading home.", hp: snapshot(x) })
  return true
}

function find(save, id) { return (save.expeditions || []).filter(function(x) { return x.id === id })[0] || null }

function advance(save, x, now, shinyOdds) {
  while (x.status === "running" && x.floor < x.floors && floorStart(x, x.floor + 1) + x.floorMs <= now)
    simulateFloor(save, x, x.floor + 1, shinyOdds)
  if (x.status === "running" && x.floor >= x.floors) {
    var X = { save: save, x: x, f: x.floors, at: x.start + x.floors * x.floorMs }
    log(X, "info", "The team cleared all " + x.floors + " floors and came home!")
    finish(save, x, X.at, "cleared")
  }
  if (x.status === "returning" && now >= x.returnAt) finish(save, x, x.returnAt, "recalled")
}

// Runs every expedition up to `now`. Safe to call on any copy of the save.
function tick(save, now) {
  var odds = Pet.shinyOdds(save)
  ;(save.expeditions || []).forEach(function(x) { advance(save, x, now, odds) })
  return save
}

function points(x, outcome) {
  var d = DIFFICULTIES[x.diff]
  var p = x.floor * d.points + x.bosses * 5 + (x.legend ? 10 : 0)
  return Math.round(p * (outcome === "cleared" ? 1.5 : outcome === "failed" ? 0.5 : 1))
}

// Back home: XP, EVs, fullness and happiness go to your Pokémon, loot and
// leftovers to the bag, recruits to their boxes.
function finish(save, x, at, outcome) {
  if (outcome === "failed") {
    // Every item not stored at a Kangaskhan has one chance in two to be lost
    var keep = x.safe || {}, rand = Pet.seeded(x.seed + ":lost")
    for (var id in x.loot) {
      var safe = Math.min(x.loot[id], keep[id] || 0), kept = safe
      for (var n = safe; n < x.loot[id]; n++) if (rand() < 0.5) kept++
      x.lost[id] = (x.lost[id] || 0) + x.loot[id] - kept
      x.loot[id] = kept
      if (x.loot[id] <= 0) delete x.loot[id]
    }
  }
  var coins = Math.round((x.money || 0) * (outcome === "cleared" ? 1.25 : outcome === "failed" ? 0.5 : 1))
  var report = { outcome: outcome, floor: x.floor, kos: x.kos, members: [], recruits: [], points: points(x, outcome), money: coins }
  save.money = (save.money || 0) + coins
  x.team.forEach(function(m) {
    var p = save.pets[m.ref]
    if (!p) return
    var before = Pet.level(p)
    if (before < Pet.MAX_LEVEL) p.xp += m.xp
    if (!p.evs) p.evs = [0, 0, 0, 0, 0, 0]
    var gained = [0, 0, 0, 0, 0, 0]
    for (var i = 0; i < 6; i++) {
      var room = Pet.evCeiling(p, i) - p.evs[i]
      var add = Math.max(0, Math.min(room, Math.floor(m.evs[i])))
      p.evs[i] += add
      gained[i] = add
    }
    p.satiety = Pet.clamp(m.satiety)
    p.happiness = Pet.clamp(p.happiness + m.happy + (outcome === "cleared" ? 5 : 0))
    p.last = at
    Pet.syncMoves(p)
    report.members.push({ ref: m.ref, species: p.species, shiny: p.shiny, from: before, to: Pet.level(p),
                          xp: Math.round(m.xp), evs: gained, kos: m.kos, fainted: m.fainted })
  })
  x.recruits.forEach(function(r) {
    var caught = Pet.freshPet(r.species, at, r.shiny, Pet.xpForLevel(r.level), r)
    var ref = Pet.addCaught(save, caught)
    report.recruits.push({ species: r.species, shiny: r.shiny, level: r.level, ref: ref, legend: !!r.legend })
  })
  for (var l in x.loot) save.bag[l] = (save.bag[l] || 0) + x.loot[l]
  for (var q in x.prov) save.bag[q] = (save.bag[q] || 0) + x.prov[q]
  var rec = record(save)
  rec.points += report.points
  rec.total += 1
  save.expedition = rec
  if (!save.charm && Pet.ownedCount(save) >= Pet.familyTotal()) save.charm = true
  x.status = "done"
  x.end = at
  x.report = report
}

// Clears a finished expedition, keeping a short summary.
function dismiss(save, id) {
  var x = find(save, id)
  if (!x || x.status !== "done") return
  var rec = record(save)
  rec.history.unshift({ id: x.id, biome: x.home, diff: x.diff, start: x.start, end: x.end, outcome: x.report.outcome,
                        floor: x.report.floor, floors: x.floors, kos: x.kos, points: x.report.points, money: x.report.money || 0,
                        team: x.team.map(function(m) { return m.species }),
                        recruits: x.report.recruits.map(function(r) { return r.species }) })
  rec.history = rec.history.slice(0, HISTORY_SIZE)
  save.expedition = rec
  save.expeditions = save.expeditions.filter(function(e) { return e.id !== id })
}

// ---- For the window ----

var OUTCOMES = { cleared: "Cleared", escaped: "Escaped", recalled: "Called back", failed: "Defeated" }

function title(x) { return (BIOMES[x.biome] || BIOMES[x.home]).name }

// Where the team is: { floor, fraction of the floor walked, ms left }.
function progress(x, now) {
  if (x.status === "done") return { floor: x.floor, frac: 1, left: 0 }
  if (x.status === "returning") return { floor: x.floor, frac: 1, left: Math.max(0, x.returnAt - now) }
  var f = Math.min(x.floors, Math.floor((now - x.start) / x.floorMs) + 1)
  f = Math.max(f, x.floor + 1)
  return { floor: Math.min(x.floors, f), frac: Math.max(0, Math.min(1, (now - floorStart(x, f)) / x.floorMs)),
           left: Math.max(0, x.start + x.floors * x.floorMs - now) }
}

function timeText(ms) {
  var m = Math.ceil(ms / 60000)
  return m >= 60 ? Math.floor(m / 60) + "h" + ("0" + m % 60).slice(-2) : Math.max(0, m) + " min"
}

// Where the events of a floor wait along the corridor, as fractions of the floor.
function marks(x, f) {
  var steps = stepsOf(x, f), out = []
  for (var m = 0; m < steps; m++) out.push((m + 1) / (steps + 1))
  return out
}

// Team state as shown: the latest snapshot.
function teamState(x) {
  return x.team.map(function(m) {
    var pp = m.moves.reduce(function(a, mv) { return a + mv.pp }, 0), max = m.moves.reduce(function(a, mv) { return a + mv.max }, 0)
    return { ref: m.ref, name: m.name, species: m.species, shiny: m.shiny, level: m.level, hp: m.hp, maxhp: m.maxhp,
             status: m.status, satiety: m.satiety, pp: pp, ppMax: max, types: m.types, ability: m.ability,
             moves: m.moves.map(function(mv) { return { name: Pet.moveName(mv.id), type: Pet.move(mv.id).type, pp: mv.pp, max: mv.max } }) }
  })
}

// Type matchups and abilities worth knowing before leaving.
function hints(save, biome, team) {
  var b = BIOMES[biome]
  if (!b) return []
  var out = []
  var attack = Object.keys(b.types).sort(function(a, c) { return b.types[c] - b.types[a] }).slice(0, 3)
  team.forEach(function(r) {
    var p = save.pets[r]
    if (!p) return
    var n = Pet.name(p.species), defender = { types: Info.species[p.species][5], ability: Pet.abilityOf(p.species, p.ability) }
    var weak = attack.filter(function(t) { return Combat.effectiveness(t, defender) > 1 })
    var resist = attack.filter(function(t) { return Combat.effectiveness(t, defender) < 1 })
    if (weak.length) out.push({ bad: true, text: n + " is weak to " + weak.map(cap).join(", ") + " here." })
    if (resist.length) out.push({ bad: false, text: n + " resists " + resist.map(cap).join(", ") + "." })
    var ab = defender.ability
    var notes = { "pickup": "finds extra items", "honey-gather": "finds extra items", "levitate": "floats over pitfalls and traps",
                  "keen-eye": "spots hidden stairs", "illuminate": "spots hidden stairs", "frisk": "spots hidden stairs",
                  "compound-eyes": "spots hidden stairs", "run-away": "can lead the team out of a Monster House",
                  "intimidate": "weakens wild Pokémon at the start of fights", "insomnia": "can't be put to sleep by traps",
                  "vital-spirit": "can't be put to sleep by traps", "pickpocket": "opens locked chests" }
    if (notes[ab]) out.push({ bad: false, text: n + "'s " + Pet.abilityName(ab) + ": " + notes[ab] + "." })
    if (Pet.level(p) < 15) out.push({ bad: true, text: n + " is still young (Lv. " + Pet.level(p) + ")." })
  })
  if (team.indexOf(save.current) >= 0 && team.length > 1) out.push({ bad: false, text: "Your partner will protect a teammate once." })
  return out
}

function cap(t) { return t.charAt(0).toUpperCase() + t.slice(1) }

// Roots that can go: at the Day Care (or your partner) and not already away.
function available(save) {
  return Pet.ownedRoots(save).filter(function(r) { return !Pet.isAway(save, r) })
}

// A sensible bag for this trip: food for the floors, potions, some PP,
// a Revive and, for the long ones, a cure and an Escape Rope.
function autoPack(save, diff, teamSize) {
  var d = DIFFICULTIES[diff]
  if (!d) return {}
  var cap = capacity(save), left = cap, out = {}
  var bag = save.bag || {}
  function take(kind, n, prefer) {
    var ids = Object.keys(bag).filter(function(i) { return bag[i] > 0 && Pet.itemKind(i) === kind })
    ids.sort(prefer)
    for (var k = 0; k < ids.length && n > 0 && left > 0; k++) {
      var id = ids[k], free = bag[id] - (out[id] || 0), c = Math.min(free, n, left)
      if (c <= 0) continue
      out[id] = (out[id] || 0) + c
      n -= c; left -= c
    }
  }
  var big = function(a, b) { return (param(b).hp || param(b).food || param(b).pp || 0) - (param(a).hp || param(a).food || param(a).pp || 0) }
  var small = function(a, b) { return -big(a, b) }
  take("revive", d.floors >= 10 ? 2 : 1, small)
  take("medicine", Math.ceil(d.floors / 2.5), small)
  take("food", Math.ceil(d.floors * teamSize / 12), big)
  take("pp", Math.ceil(d.floors / 8), small)
  if (d.floors >= 10) take("status", 1, small)
  if (d.floors >= 15) take("escape", 1, small)
  take("medicine", left, small)
  return out
}

function provisionCount(prov) {
  var n = 0
  for (var id in prov) n += prov[id] || 0
  return n
}

// Legendaries sighted in a biome: [{ slug, count }]
function sightings(save, biome) {
  var seen = record(save).legends[biome] || {}
  return Object.keys(seen).map(function(s) { return { slug: s, count: seen[s] } })
}
