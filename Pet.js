.pragma library
.import "Dex.js" as Dex
.import "Info.js" as Info
.import "Items.js" as Items
.import "Moves.js" as Moves
.import "Battle.js" as Battle

// Rates per hour. Tweak here to speed the game up or slow it down.
var SATIETY_DECAY = 6
var HAPPINESS_DECAY = 5
var PASSIVE_XP = 36                 // earned per hour while fed and happy
var DAYCARE_XP = 12                 // earned per hour by the Pokémon at the Day Care
var DAYCARE_SIZE = 10               // Pokémon the Day Care looks after; the others rest
var ACTION_XP = { feed: 12, pet: 9, play: 18 }
var ACTION_COOLDOWN = 10 * 60000    // an action only grants XP once every 10 min
var START_LEVEL = 5                 // level at 0 XP; wild catches below it start with negative XP
var MIN_LEVEL = 1
var MAX_LEVEL = 100
var WILD_MAX_LEVEL = 40

// Evolution conditions.
var HAPPY_THRESHOLD = 80            // "friendship" evolutions
var BOND_PETS = 15                  // rewarded pets needed for the fairy path
var DAY_START = 8
var DAY_END = 20

// Exploring: per half-hour window (aligned on :00 and :30).
var WINDOW = 30 * 60000
var ENCOUNTERS_PER_WINDOW = 3
var SEARCHES_PER_WINDOW = 5         // items found by the one search of each half hour
var SHINY_ODDS = 1 / 64
var CHARM_SHINY_ODDS = 1 / 32       // with the Shiny Charm, earned by catching every family
var HIDDEN_ABILITY_ODDS = 1 / 20
var EVOLUTION_WEIGHT = 6            // share of searches that turn up an evolution item

// Poké Balls found by every search, on top of the items.
var BALLS_FOUND = [1, 5]
var GREAT_BALL_ODDS = 0.3           // 1 or 2 Great Balls
var ULTRA_BALL_ODDS = 0.08
var MASTER_BALL_ODDS = 0.003
var STARTER_BALLS = 10
var APPLES_FOUND = [1, 3]           // apples in every search, each one rolled for its quality
var APPLE_QUALITY = { "apple": 70, "big-apple": 25, "golden-apple": 5 }
var TMS_FOUND = [1, 3]              // TMs in every search, on top of the items
var STARTER_MONEY = 300             // Poké Dollars given once, to try the shop
var SELL_RATE = 0.5                 // the shop buys items back at half price

// Catching: the main-series formula, (a / 255)^0.75 per throw with
// a = catch rate × Ball × HP factor. Safari Pokémon can't be weakened, so they
// are treated as if they were at a third of their HP, with a Safari bonus.
var SAFARI_HP_FACTOR = 7 / 9
var SAFARI_BONUS = 1.5
var MAX_CATCH = 0.95
var LEGEND_FLEE = 0.6               // legendaries stick around a little longer

// Wild encounter weights: catch rate, ×0.25 for evolved forms, and rarer still for these.
var RARE_RATE = 45                  // catch rate at or under which a Pokémon counts as rare
var RARE_WEIGHT = 0.6
var LEGENDARY_WEIGHT = 0.12
var MYTHICAL_WEIGHT = 0.05

// EV training against the Substitute doll.
var EV_MAX_TOTAL = 510
var EV_MAX_STAT = 252
var TRAIN_EV_PER_HOUR = 60
var TRAIN_XP_PER_HOUR = 40          // XP training: about 4 levels an hour
var TRAIN_SLOTS = 5                 // Pokémon that can train at the same time

// Boxes: every family keeps one Pokémon at the Day Care and the rest in its box.
var BOX_SIZE = 32                   // Pokémon per family, the Day Care one included
var MAX_MOVES = 4

// ---- Pokédex helpers ----

function name(slug) { return Dex.species[slug] ? Dex.species[slug][0] : slug }
function evoLevel(slug) { return Dex.species[slug][2] }
function captureRate(slug) { return Dex.species[slug][3] }
function legendKind(slug) { return Battle.legendary[slug] || 0 }   // 0, 1 legendary, 2 mythical
function condition(slug) { return Dex.species[slug][4] || {} }
function itemName(id) { return Items.items[id] ? Items.items[id][0] : (Dex.items[id] || id) }
function itemKind(id) { return Items.items[id] ? Items.items[id][1] : "evolution" }
function itemText(id) { return Items.items[id] ? Items.items[id][3] : "" }
// Sprite file of an item: TMs share one disc per type.
function itemSprite(id) { return itemKind(id) === "tm" ? "tm-" + Items.items[id][4].type : id }

var _children = null
function children(slug) {
  if (!_children) {
    _children = {}
    for (var s in Dex.species) {
      var from = Dex.species[s][1]
      if (from) (_children[from] = _children[from] || []).push(s)
    }
  }
  return _children[slug] || []
}

function family(slug) {
  while (Dex.species[slug] && Dex.species[slug][1]) slug = Dex.species[slug][1]
  return slug
}

// Lowest level at which this species can evolve, 0 when fully evolved.
function nextLevel(slug) {
  var c = children(slug), best = 0
  for (var i = 0; i < c.length; i++) {
    var l = evoLevel(c[i])
    if (!best || l < best) best = l
  }
  return best
}

var _search = null
function searchFamilies(query) {
  if (!_search) {
    _search = {}
    for (var s in Dex.species) {
      var root = family(s)
      _search[root] = (_search[root] || "") + " " + name(s).toLowerCase()
    }
  }
  var q = String(query || "").trim().toLowerCase()
  if (!q) return Dex.families
  return Dex.families.filter(function(root) { return _search[root].indexOf(q) >= 0 })
}

function pick(list, weightOf) {
  var total = 0
  for (var i = 0; i < list.length; i++) total += weightOf(list[i])
  var r = Math.random() * total
  for (var j = 0; j < list.length; j++) {
    r -= weightOf(list[j])
    if (r <= 0) return list[j]
  }
  return list[list.length - 1]
}

function randInt(min, max) { return min + Math.floor(Math.random() * (max - min + 1)) }

// ---- Save ----

function clamp(v) { return Math.max(0, Math.min(100, v)) }
function copy(o) { return JSON.parse(JSON.stringify(o)) }

function freshPet(species, now, shiny, xp, details) {
  var d = details || rollDetails(Math.random)
  var p = { species: species, xp: xp || 0, satiety: 80, happiness: 80, last: now,
            shiny: !!shiny, cooldowns: {}, bond: 0, postponed: 0,
            ivs: d.ivs, ability: d.ability, nature: d.nature }
  syncMoves(p)
  return p
}

function freshSave() {
  return { version: 4, current: "", pets: {}, bag: { "poke-ball": STARTER_BALLS }, explore: { window: 0, encounters: 0, searches: 0 },
           encounter: null, box: {}, seen: {}, navdex: "", incense: 0, charm: false, balls: true,
           expeditions: [], expedition: freshRecord(), daycare: [], money: STARTER_MONEY }
}

// Rank points, legendary sightings per biome and past reports.
function freshRecord() { return { points: 0, legends: {}, history: [], total: 0 } }

// Fields added after v4 shipped; older v4 saves get them on load.
function upgrade(v) {
  if (!v.box) v.box = {}
  if (!v.seen) {
    v.seen = {}
    for (var root in v.pets) markLineSeen(v, v.pets[root].species)
  }
  if (typeof v.navdex !== "string") v.navdex = ""
  if (!v.incense) v.incense = 0
  if (!v.charm) v.charm = ownedCount(v) >= familyTotal()
  // Poké Balls became an item: everybody starts with a few.
  if (!v.balls) {
    v.bag["poke-ball"] = (v.bag["poke-ball"] || 0) + STARTER_BALLS
    v.balls = true
  }
  if (!Array.isArray(v.expeditions)) v.expeditions = []
  if (!v.expedition) v.expedition = freshRecord()
  // The Day Care became a place for DAYCARE_SIZE Pokémon: keep the most advanced ones.
  if (!Array.isArray(v.daycare)) {
    v.daycare = Object.keys(v.pets).filter(function(r) { return r !== v.current })
      .sort(function(a, b) { return v.pets[b].xp - v.pets[a].xp }).slice(0, DAYCARE_SIZE)
  }
  if (typeof v.money !== "number") v.money = STARTER_MONEY
  return v
}

// Stage indexes used by the v1/v2 saves, which only knew twelve families.
var LEGACY = {
  "bagon": ["bagon", "shelgon", "salamence"], "bulbasaur": ["bulbasaur", "ivysaur", "venusaur"],
  "charmander": ["charmander", "charmeleon", "charizard"], "squirtle": ["squirtle", "wartortle", "blastoise"],
  "dratini": ["dratini", "dragonair", "dragonite"], "larvitar": ["larvitar", "pupitar", "tyranitar"],
  "beldum": ["beldum", "metang", "metagross"], "gible": ["gible", "gabite", "garchomp"],
  "deino": ["deino", "zweilous", "hydreigon"], "goomy": ["goomy", "sliggoo", "goodra"],
  "jangmo-o": ["jangmo-o", "hakamo-o", "kommo-o"], "dreepy": ["dreepy", "drakloak", "dragapult"]
}

// Returns a v4 save, migrating older formats; null when unreadable.
function parse(raw) {
  try {
    var v = JSON.parse(raw)
    if (v && typeof v.stage === "number") v = { version: 2, current: "bagon", pets: { bagon: v } }
    if (v && v.version === 2 && v.pets) {
      for (var id in v.pets) {
        var p = v.pets[id]
        p.species = (LEGACY[id] || [id])[p.stage || 0] || id
        delete p.stage
      }
      v.version = 3
    }
    if (v && v.version === 3 && v.pets) {
      var fresh = freshSave()
      v.bag = fresh.bag; v.explore = fresh.explore; v.encounter = null
      v.version = 4
    }
    if (v && v.version === 4 && v.pets) {
      // Pokémon caught before IVs existed get a stable, seeded individual.
      for (var root in v.pets) {
        if (!v.pets[root].ivs) {
          var d = rollDetails(seeded(root))
          v.pets[root].ivs = d.ivs; v.pets[root].ability = d.ability; v.pets[root].nature = d.nature
        }
      }
      return upgrade(v)
    }
  } catch (e) {}
  return null
}

function current(save) { return save.pets[save.current] || null }
function peek(save, root) { return save.pets[root] || null }
function ownedCount(save) { return Object.keys(save.pets).length }
function familyTotal() { return Dex.families.length }

// ---- Boxes ----
// A Pokémon is addressed by a ref: "root" for the family's Day Care Pokémon,
// "root/N" for the N-th one in its box. Boxed Pokémon rest: no XP, no training.

function refRoot(ref) { return String(ref).split("/")[0] }
function refIndex(ref) {
  var i = String(ref).indexOf("/")
  return i < 0 ? -1 : parseInt(String(ref).slice(i + 1))
}
function isBoxed(ref) { return refIndex(ref) >= 0 }
function boxOf(save, root) { return (save.box && save.box[root]) || [] }

function specimen(save, ref) {
  if (!ref) return null
  var i = refIndex(ref), root = refRoot(ref)
  return i < 0 ? save.pets[root] || null : boxOf(save, root)[i] || null
}

function familyCount(save, root) { return (save.pets[root] ? 1 : 0) + boxOf(save, root).length }
function boxFull(save, root) { return familyCount(save, root) >= BOX_SIZE }

// Every Pokémon of a family: the Day Care one first, then the box.
function familyRefs(save, root) {
  if (!save.pets[root]) return []
  return [root].concat(boxOf(save, root).map(function(_, i) { return root + "/" + i }))
}

function storedTotal(save) {
  var n = ownedCount(save)
  for (var root in save.box || {}) n += save.box[root].length
  return n
}

// Swaps a boxed Pokémon with the family's Day Care one (your partner, if it was).
function makeLead(save, ref, now) {
  var i = refIndex(ref), root = refRoot(ref), box = boxOf(save, root)
  if (i < 0 || !box[i] || !save.pets[root] || isAway(save, root)) return false
  if (save.pets[root].training) stopTraining(save, root)
  var p = box[i]
  p.last = now
  box[i] = save.pets[root]
  save.pets[root] = p
  return true
}

// Only boxed Pokémon can be released: every family keeps its Day Care one.
function release(save, ref) {
  var i = refIndex(ref), root = refRoot(ref), box = boxOf(save, root)
  if (i < 0 || !box[i]) return false
  box.splice(i, 1)
  if (!box.length) delete save.box[root]
  return true
}

// ---- Expeditions ----
// Expedition.js runs them; here we only need to know who is away.

function expeditionActive(x) { return x.status === "running" || x.status === "returning" }

function awayRoots(save) {
  var out = {}
  ;(save.expeditions || []).forEach(function(x) {
    if (expeditionActive(x)) x.team.forEach(function(m) { out[m.ref] = true })
  })
  return out
}

function isAway(save, root) { return !!awayRoots(save)[root] }

// ---- Seen Pokémon and the Nav-Dex ----

function familyMembers(root) {
  var out = [], stack = [root]
  while (stack.length) {
    var s = stack.shift()
    out.push(s)
    stack = stack.concat(children(s))
  }
  return out
}

function markSeen(save, slug) {
  if (!save.seen) save.seen = {}
  save.seen[slug] = 1
}

// A Pokémon you own has also shown you its earlier forms.
function markLineSeen(save, slug) {
  while (slug && Dex.species[slug]) { markSeen(save, slug); slug = Dex.species[slug][1] }
}

function isSeen(save, slug) { return !!(save.seen && save.seen[slug]) || !!save.pets[slug] }
function seenMembers(save, root) { return familyMembers(root).filter(function(s) { return isSeen(save, s) }) }
function familySeen(save, root) { return !!save.pets[root] || seenMembers(save, root).length > 0 }

// The Nav-Dex locks every wild encounter on one species you've seen.
function setNavdex(save, slug) {
  save.navdex = slug && Dex.species[slug] && isSeen(save, slug) ? slug : ""
  return save.navdex
}

function hasCharm(save) { return !!save.charm || ownedCount(save) >= familyTotal() }
function shinyOdds(save) { return hasCharm(save) ? CHARM_SHINY_ODDS : SHINY_ODDS }
function oddsText(save) { return "1/" + Math.round(1 / shinyOdds(save)) }

function level(p) { return Math.max(MIN_LEVEL, Math.min(MAX_LEVEL, START_LEVEL + Math.floor(p.xp / 10))) }

// Progress 0..1 towards the next evolution.
function evoProgress(p) {
  var end = nextLevel(p.species)
  if (!end) return 1
  var start = evoLevel(p.species) || START_LEVEL
  var lv = START_LEVEL + p.xp / 10
  return Math.max(0, Math.min(1, (lv - start) / Math.max(1, end - start)))
}

// Passive XP between two instants, with a berry boost on the part it covers.
function boostedXp(p, rate, from, to) {
  var xp = rate * Math.max(0, (to - from) / 3600000)
  if (p.boost) {
    var covered = Math.max(0, Math.min(to, p.boost.until) - from) / 3600000
    xp += rate * (p.boost.mult - 1) * covered
  }
  return xp
}

function dropExpiredBoost(p, now) { if (p.boost && now >= p.boost.until) delete p.boost }

// Your partner lives with you; up to DAYCARE_SIZE others play at the Day Care,
// where they don't get hungry or bored and slowly earn XP. The rest just rest.
// Anyone can be training against the Substitute doll.
function tick(save, now) {
  var away = awayRoots(save)
  var care = {}
  ;(save.daycare || []).forEach(function(r) { care[r] = true })
  for (var root in save.pets) {
    var q = save.pets[root]
    var from = q.last || now
    // Pokémon on an expedition don't train, play or get hungry here.
    if (away[root]) { q.last = now; dropExpiredBoost(q, now); continue }
    train(q, from, now)
    if (root === save.current) continue
    if (care[root]) q.xp += boostedXp(q, DAYCARE_XP, from, now)
    dropExpiredBoost(q, now)
    q.last = now
    syncMoves(q)
  }
  var p = current(save)
  if (!p || away[save.current]) return save
  var hours = Math.max(0, (now - (p.last || now)) / 3600000)
  var wasWell = p.satiety >= 50 && p.happiness >= 50
  p.satiety = clamp(p.satiety - SATIETY_DECAY * hours)
  p.happiness = clamp(p.happiness - HAPPINESS_DECAY * hours)
  if (wasWell && p.satiety >= 50 && p.happiness >= 50) p.xp += boostedXp(p, PASSIVE_XP, p.last || now, now)
  dropExpiredBoost(p, now)
  p.last = now
  syncMoves(p)
  return save
}

function gain(p, action, now) {
  if (!p.cooldowns) p.cooldowns = {}
  if (now - (p.cooldowns[action] || 0) < ACTION_COOLDOWN) return
  p.cooldowns[action] = now
  p.xp += ACTION_XP[action]
  if (action === "pet") p.bond = (p.bond || 0) + 1
}

function act(save, action, now) {
  var p = current(save)
  if (!p) return ""
  var n = name(p.species)
  if (isAway(save, save.current)) return n + " is away on an expedition."
  if (action === "feed") {
    if (p.satiety >= 95) return n + " isn't hungry."
    p.satiety = clamp(p.satiety + 25); gain(p, action, now)
    return n + " munches on a Berry!"
  }
  if (action === "pet") {
    if (p.happiness >= 95) return n + " is already overjoyed."
    p.happiness = clamp(p.happiness + 15); gain(p, action, now)
    return n + " closes its eyes happily."
  }
  if (action === "play") {
    if (p.satiety < 20) return n + " is too hungry to play."
    p.happiness = clamp(p.happiness + 25); p.satiety = clamp(p.satiety - 10); gain(p, action, now)
    return n + " plays around with you!"
  }
  return ""
}

function switchTo(save, root, now) {
  if (!save.pets[root]) return save
  tick(save, now)
  // The old partner takes the new one's spot at the Day Care, if it had one
  var spot = (save.daycare || []).indexOf(root)
  if (spot >= 0) {
    if (save.current && save.pets[save.current]) save.daycare[spot] = save.current
    else save.daycare.splice(spot, 1)
  }
  save.current = root
  current(save).last = now
  return save
}

// ---- Day Care ----

function inDaycare(save, root) { return (save.daycare || []).indexOf(root) >= 0 }
function daycareFull(save) { return (save.daycare || []).length >= DAYCARE_SIZE }

// Sends a Pokémon to the Day Care or takes it back. Returns the message to show.
function toggleDaycare(save, root) {
  var p = save.pets[root]
  if (!p) return ""
  if (!save.daycare) save.daycare = []
  var n = name(p.species), i = save.daycare.indexOf(root)
  if (i >= 0) {
    save.daycare.splice(i, 1)
    return n + " left the Day Care. It will rest without gaining XP."
  }
  if (root === save.current) return n + " is your partner: it already earns XP with you."
  if (daycareFull(save)) return "The Day Care is full (" + DAYCARE_SIZE + "). Take a Pokémon back first."
  save.daycare.push(root)
  return n + " joined the Day Care! +" + DAYCARE_XP + " XP per hour."
}

// Back to the first stage of the family, keeping the shiny choice.
function reset(save, now) {
  var p = current(save)
  if (p) save.pets[save.current] = freshPet(save.current, now, p.shiny, 0, p)
  return save
}

function mood(save) {
  var p = current(save)
  if (!p) return "You don't have any Pokémon yet. Go explore the tall grass!"
  if (p.satiety < 25) return "It looks hungry…"
  if (p.happiness < 25) return "It looks bored…"
  if (p.satiety >= 70 && p.happiness >= 70) return "It's full of energy!"
  return "It seems fine."
}

// ---- Evolution ----

function isDay(now) {
  var h = new Date(now).getHours()
  return h >= DAY_START && h < DAY_END
}

function hasConditions(slug) { return Object.keys(condition(slug)).length > 0 }

// A lone, plain level-up evolution happens on its own, like Bagon -> Shelgon.
function isAuto(p) {
  var c = children(p.species)
  return c.length === 1 && !hasConditions(c[0])
}

function conditionText(slug) {
  var c = condition(slug), parts = []
  if (c.i) parts.push(itemName(c.i))
  if (c.b) parts.push("Strong bond (" + BOND_PETS + " pets) · Fairy path")
  else if (c.h) parts.push("Happiness " + HAPPY_THRESHOLD + "+")
  if (c.d === "day") parts.push("Daytime (" + DAY_START + "h–" + DAY_END + "h)")
  if (c.d === "night") parts.push("Night (" + DAY_END + "h–" + DAY_START + "h)")
  return parts.length ? parts.join(" · ") : "Level up"
}

function conditionMet(save, p, slug, now) {
  var c = condition(slug)
  if (c.i && !(save.bag[c.i] > 0)) return false
  if (c.h && p.happiness < HAPPY_THRESHOLD) return false
  if (c.b && (p.bond || 0) < BOND_PETS) return false
  if (c.d === "day" && !isDay(now)) return false
  if (c.d === "night" && isDay(now)) return false
  return true
}

function petOf(save, ref) { return ref ? specimen(save, ref) : current(save) }

function evolutionOptions(save, now, root) {
  var p = petOf(save, root)
  var ref = root || save.current
  if (!p || (!isBoxed(ref) && isAway(save, refRoot(ref)))) return []
  var lv = level(p)
  return children(p.species).filter(function(k) { return lv >= evoLevel(k) }).map(function(k) {
    return { slug: k, name: name(k), text: conditionText(k), met: conditionMet(save, p, k, now) }
  })
}

function evolutionReady(save, now) {
  var p = current(save)
  return !!p && !isAuto(p) && evolutionOptions(save, now).length > 0
}

// Any Pokémon past its evolution level, including ones that lagged behind at
// the Day Care: the Summary page offers an Evolve button for it.
function canEvolve(save, now, root) { return evolutionOptions(save, now, root).length > 0 }

// Ready and not postponed at this level: the popup offers it on its own.
function evolutionPending(save, now) {
  var p = current(save)
  return evolutionReady(save, now) && level(p) > (p.postponed || 0)
}

function evolveTo(save, slug, now, root) {
  var p = petOf(save, root)
  var c = condition(slug)
  if (c.i) {
    save.bag[c.i] -= 1
    if (save.bag[c.i] <= 0) delete save.bag[c.i]
  }
  var from = name(p.species)
  p.species = slug
  p.postponed = 0
  markSeen(save, slug)
  var learned = syncMoves(p)
  return { from: from, to: name(slug), learned: learned.map(moveName) }
}

function postpone(save, root) {
  var p = petOf(save, root)
  if (p) p.postponed = level(p)
}

function maybeEvolve(save, now) {
  var p = current(save)
  if (!p || !isAuto(p) || isAway(save, save.current)) return null
  var kid = children(p.species)[0]
  return level(p) >= evoLevel(kid) ? evolveTo(save, kid, now) : null
}

// ---- Exploring ----

function windowOf(now) { return Math.floor(now / WINDOW) }

function refreshWindow(save, now) {
  if (!save.explore || save.explore.window !== windowOf(now))
    save.explore = { window: windowOf(now), encounters: 0, searches: 0 }
}

function incenseActive(save, now) { return (save.incense || 0) > now }

function incenseLeft(save, now) {
  if (!incenseActive(save, now)) return ""
  var m = Math.ceil((save.incense - now) / 60000)
  return m >= 60 ? Math.floor(m / 60) + "h" + ("0" + m % 60).slice(-2) : m + " min"
}

function encountersPerWindow(save, now) {
  return incenseActive(save, now) ? Items.items["incense"][4].encounters : ENCOUNTERS_PER_WINDOW
}

function encountersLeft(save, now) {
  var e = save.explore
  return Math.max(0, encountersPerWindow(save, now) - (e && e.window === windowOf(now) ? e.encounters : 0))
}

function searchesLeft(save, now) {
  var e = save.explore
  return Math.max(0, SEARCHES_PER_WINDOW - (e && e.window === windowOf(now) ? e.searches : 0))
}

function minutesToRefill(now) { return Math.ceil(((windowOf(now) + 1) * WINDOW - now) / 60000) }

// How often a species shows up in the tall grass: its catch rate, less for
// evolved forms, much less for rare Pokémon and less still for legendaries.
function encounterWeight(s) {
  var w = captureRate(s) * (Dex.species[s][1] ? 0.25 : 1)
  var k = legendKind(s)
  if (k === 2) return w * MYTHICAL_WEIGHT
  if (k === 1) return w * LEGENDARY_WEIGHT
  return captureRate(s) <= RARE_RATE ? w * RARE_WEIGHT : w
}

// A wild Pokémon from a family you don't own yet; rarer ones show up less.
// With the Nav-Dex on, it is always the chosen species. Once every family is
// caught, any species whose box still has room can show up.
// Returns the encounter, { error: "full" | "done" }, or null when out of encounters.
function startEncounter(save, now) {
  refreshWindow(save, now)
  if (encountersLeft(save, now) <= 0) return null
  var slug = ""
  if (save.navdex && Dex.species[save.navdex]) {
    if (boxFull(save, family(save.navdex))) return { error: "full" }
    slug = save.navdex
  } else {
    var wild = Object.keys(Dex.species).filter(function(s) { return !save.pets[family(s)] })
    if (!wild.length) wild = Object.keys(Dex.species).filter(function(s) { return !boxFull(save, family(s)) })
    if (!wild.length) return { error: "done" }
    slug = pick(wild, encounterWeight)
  }
  save.explore.encounters += 1
  markSeen(save, slug)
  // Lv. 1 to 40; an evolved form is at least at its evolution level (capped at 40).
  var lv = randInt(Math.max(MIN_LEVEL, Math.min(WILD_MAX_LEVEL, evoLevel(slug))), WILD_MAX_LEVEL)
  var d = rollDetails(Math.random)
  save.encounter = { species: slug, level: lv, shiny: Math.random() < shinyOdds(save), angry: 0, eating: 0,
                     ivs: d.ivs, ability: d.ability, nature: d.nature }
  return save.encounter
}

function ballMult(ball) { return Items.items[ball] && itemKind(ball) === "ball" ? Items.items[ball][4].mult : 1 }

// Chance that one throw catches it. A rock makes it easier to catch (×2), bait harder (×0.5).
function catchChance(e, ball) {
  if (ball === "master-ball") return 1
  var mood = e.angry > 0 ? 2 : e.eating > 0 ? 0.5 : 1
  var a = captureRate(e.species) * ballMult(ball || "poke-ball") * SAFARI_HP_FACTOR * SAFARI_BONUS * mood
  return Math.min(MAX_CATCH, Math.pow(Math.min(255, a) / 255, 0.75))
}

function fleeChance(e) {
  var base = captureRate(e.species) / 255
  var mod = e.angry > 0 ? 2 : e.eating > 0 ? 0.35 : 1
  var legend = legendKind(e.species) ? LEGEND_FLEE : 1
  return Math.max(0.02, Math.min(0.7, (0.06 + 0.22 * (1 - base)) * mod * legend))
}

// End of a Safari turn: the wild Pokémon may run, then its mood wears off.
function endTurn(save) {
  var e = save.encounter
  var fled = Math.random() < fleeChance(e)
  if (e.angry > 0) e.angry -= 1
  if (e.eating > 0) e.eating -= 1
  if (fled) save.encounter = null
  return fled
}

function ballsLeft(save) {
  return ["poke-ball", "great-ball", "ultra-ball", "master-ball"].reduce(function(a, b) { return a + (save.bag[b] || 0) }, 0)
}

// Puts a newly caught Pokémon at the Day Care, or in its family's box.
// Returns its ref, or "" when the box is full.
function addCaught(save, caught) {
  var root = family(caught.species)
  if (boxFull(save, root)) return ""
  var ref = root
  if (!save.pets[root]) {
    save.pets[root] = caught
  } else {
    if (!save.box) save.box = {}
    save.box[root] = boxOf(save, root).concat([caught])
    ref = root + "/" + (save.box[root].length - 1)
  }
  markLineSeen(save, caught.species)
  if (!save.current || !save.pets[save.current]) save.current = root
  else if (ref === root && !daycareFull(save) && !inDaycare(save, root)) {
    if (!save.daycare) save.daycare = []
    save.daycare.push(root)
  }
  return ref
}

function throwBall(save, now, ball) {
  var e = save.encounter
  ball = ball || "poke-ball"
  if (!e) return null
  if (!(save.bag[ball] > 0)) return { result: "noball", shakes: 0 }
  var root = family(e.species)
  if (boxFull(save, root)) return { result: "full", shakes: 0 }
  consume(save, ball)
  var chance = catchChance(e, ball)
  if (Math.random() < chance) {
    var ref = addCaught(save, freshPet(e.species, now, e.shiny, xpForLevel(e.level), e))
    save.encounter = null
    var charm = !save.charm && ownedCount(save) >= familyTotal()
    if (charm) save.charm = true
    return { result: "caught", shakes: 3, ref: ref, boxed: ref !== root, charm: charm }
  }
  // The closer it was, the more the ball shakes before it breaks free
  return { result: endTurn(save) ? "fled" : "broke", shakes: Math.min(2, Math.floor(Math.random() * 3 * (0.5 + chance))) }
}

function throwRock(save) {
  var e = save.encounter
  if (!e) return null
  e.angry = randInt(1, 5); e.eating = 0
  return { result: endTurn(save) ? "fled" : "angry" }
}

function throwBait(save) {
  var e = save.encounter
  if (!e) return null
  e.eating = randInt(1, 5); e.angry = 0
  return { result: endTurn(save) ? "fled" : "eating" }
}

function run(save) { save.encounter = null }

// Items that would let one of your Pokémon evolve someday.
function usefulItems(save) {
  var useful = {}
  for (var root in save.pets) {
    var stack = [root]
    while (stack.length) {
      var s = stack.pop()
      var c = condition(s)
      if (c.i) useful[c.i] = true
      stack = stack.concat(children(s))
    }
  }
  return useful
}

// One item from the search pool: mostly berries, then candies, provisions,
// mints and bottle caps. Evolution items come up when missing from the bag,
// favouring the ones your Pokémon need. Balls have their own roll.
function rollItem(save, useful, taken) {
  var ids = Object.keys(Items.items).filter(function(i) { return itemKind(i) !== "ball" })
  var missingEvo = ids.filter(function(i) { return itemKind(i) === "evolution" && !(save.bag[i] > 0) && !taken[i] })
  var evoTotal = missingEvo.reduce(function(a, i) { return a + (useful[i] ? 4 : 1) }, 0)
  var pool = ids.filter(function(i) { return itemKind(i) !== "evolution" || missingEvo.indexOf(i) >= 0 })
  return pick(pool, function(i) {
    return itemKind(i) === "evolution" ? EVOLUTION_WEIGHT * (useful[i] ? 4 : 1) / evoTotal : Items.items[i][2]
  })
}

// The search of this half hour: a handful of Poké Balls (sometimes better
// ones), 1 to 3 apples (sometimes Big or even Golden), SEARCHES_PER_WINDOW items
// and 1 to 3 TMs. Returns [{ id, count }], or null when you already searched.
function search(save, now) {
  refreshWindow(save, now)
  if (searchesLeft(save, now) <= 0) return null
  save.explore.searches = SEARCHES_PER_WINDOW
  var found = {}, order = []
  function add(id, n) {
    if (!found[id]) order.push(id)
    found[id] = (found[id] || 0) + n
    save.bag[id] = (save.bag[id] || 0) + n
  }
  add("poke-ball", randInt(BALLS_FOUND[0], BALLS_FOUND[1]))
  if (Math.random() < GREAT_BALL_ODDS) add("great-ball", randInt(1, 2))
  if (Math.random() < ULTRA_BALL_ODDS) add("ultra-ball", 1)
  if (Math.random() < MASTER_BALL_ODDS) add("master-ball", 1)
  for (var a = randInt(APPLES_FOUND[0], APPLES_FOUND[1]); a > 0; a--)
    add(pick(Object.keys(APPLE_QUALITY), function(k) { return APPLE_QUALITY[k] }), 1)
  var useful = usefulItems(save)
  for (var i = 0; i < SEARCHES_PER_WINDOW; i++) add(rollItem(save, useful, found), 1)
  for (var t = randInt(TMS_FOUND[0], TMS_FOUND[1]); t > 0; t--) add(rollTm(Math.random), 1)
  return order.map(function(id) { return { id: id, count: found[id] } })
}

var KIND_ORDER = ["ball", "incense", "berry", "candy", "mint", "cap", "ability", "food", "medicine", "pp", "status", "revive", "escape",
                  "evolution", "held", "tm"]
var PROVISION_KINDS = ["food", "medicine", "pp", "status", "revive", "escape"]
function isProvision(id) { return PROVISION_KINDS.indexOf(itemKind(id)) >= 0 }

function bagItems(save) {
  return Object.keys(save.bag).filter(function(i) { return save.bag[i] > 0 }).sort(function(a, b) {
    return KIND_ORDER.indexOf(itemKind(a)) - KIND_ORDER.indexOf(itemKind(b))
        || (Object.keys(Items.items).indexOf(a) - Object.keys(Items.items).indexOf(b))
  })
}

function natureIndex(nameText) {
  for (var i = 0; i < Info.natures.length; i++) if (Info.natures[i][0] === nameText) return i
  return 0
}

// Uses an item on your partner; returns the message to show.
function useItem(save, id, now, stat) {
  var p = current(save)
  var it = Items.items[id]
  if (!it || !(save.bag[id] > 0)) return ""
  var kind = it[1], param = it[4], msg = ""
  if (kind === "incense") {
    save.incense = Math.max(now, save.incense || 0) + param.hours * 3600000
    consume(save, id)
    return "You lit the Incense! " + param.encounters + " wild encounters per half-hour for " + incenseLeft(save, now) + "."
  }
  if (kind === "ball") return "Throw it at a wild Pokémon."
  if (kind === "tm") return "Teach it from a Pokémon's Moves page."
  if (kind === "held") return "Give it to a Pokémon in a Battle Tower team."
  if (PROVISION_KINDS.indexOf(kind) >= 0) return "Pack it for an expedition: the team uses it on its own."
  if (!p) return "You need a partner Pokémon first."
  var n = name(p.species)
  if (kind === "evolution") return "It's used up when a Pokémon that needs it evolves."
  if (isAway(save, save.current)) return n + " is away on an expedition."
  if (kind === "candy") {
    if (level(p) >= MAX_LEVEL) return n + " is already at level " + MAX_LEVEL + "."
    if (param.level) p.xp = (Math.floor(p.xp / 10) + 1) * 10
    else p.xp += param.xp
    msg = n + " ate the " + it[0] + " and reached Lv. " + level(p) + "!"
    var learned = syncMoves(p)
    if (learned.length) msg += " It learned " + learned.map(moveName).join(", ") + "!"
  } else if (kind === "berry") {
    var stacked = p.boost && p.boost.mult === param.mult ? p.boost.until : now
    p.boost = { mult: param.mult, until: Math.max(now, stacked) + param.hours * 3600000 }
    msg = n + " ate the " + it[0] + "! Passive XP ×" + param.mult + " for " + boostLeft(p, now) + "."
  } else if (kind === "mint") {
    var idx = natureIndex(param.nature)
    if (p.nature === idx) return n + " already has a " + param.nature + " nature."
    p.nature = idx
    msg = n + "'s nature became " + param.nature + "!"
  } else if (kind === "ability") {
    var e = Info.species[p.species], ab = p.ability || { slot: 0, hidden: false }
    if (param.hidden) {
      if (!e[8]) return n + " has no Hidden Ability."
      p.ability = { slot: ab.slot, hidden: !ab.hidden }
    } else {
      if (ab.hidden) return n + " has its Hidden Ability: use an Ability Patch instead."
      if (e[7].length < 2) return n + " has only one regular Ability."
      p.ability = { slot: ab.slot ? 0 : 1, hidden: false }
    }
    msg = n + "'s Ability became " + abilityName(abilityOf(p.species, p.ability)) + "!"
  } else if (kind === "cap") {
    if (param.all) {
      if (p.ivs.every(function(v) { return v === 31 })) return n + "'s IVs are already perfect."
      p.ivs = [31, 31, 31, 31, 31, 31]
      msg = "Hyper Training! All of " + n + "'s IVs are now 31."
    } else {
      if (stat === undefined || stat === null) return "Choose a stat to train."
      if (p.ivs[stat] === 31) return n + "'s " + STAT_LABELS[stat] + " IV is already 31."
      p.ivs[stat] = 31
      msg = "Hyper Training! " + n + "'s " + STAT_LABELS[stat] + " IV is now 31."
    }
  }
  consume(save, id)
  return msg
}

function consume(save, id) {
  save.bag[id] -= 1
  if (save.bag[id] <= 0) delete save.bag[id]
}

function boostLeft(p, now) {
  if (!p || !p.boost || now >= p.boost.until) return ""
  var m = Math.ceil((p.boost.until - now) / 60000)
  return m >= 60 ? Math.floor(m / 60) + "h" + ("0" + m % 60).slice(-2) : m + " min"
}

function needsAttention(save, now) {
  var p = current(save)
  if (!p || isAway(save, save.current)) return false
  return p.satiety < 30 || p.happiness < 30 || evolutionPending(save, now)
}

// ---- Summary: IVs, abilities, natures and stats ----

var STAT_LABELS = ["HP", "Attack", "Defense", "Sp. Atk", "Sp. Def", "Speed"]

// Small deterministic RNG (FNV-1a seed + xorshift) for migrated Pokémon.
function seeded(text) {
  var h = 2166136261
  for (var i = 0; i < text.length; i++) { h ^= text.charCodeAt(i); h = Math.imul(h, 16777619) }
  return function() {
    h ^= h << 13; h ^= h >>> 17; h ^= h << 5
    return (h >>> 0) / 4294967296
  }
}

function rollDetails(rand) {
  var ivs = []
  for (var i = 0; i < 6; i++) ivs.push(Math.floor(rand() * 32))
  return { ivs: ivs, ability: { slot: rand() < 0.5 ? 0 : 1, hidden: rand() < HIDDEN_ABILITY_ODDS },
           nature: Math.floor(rand() * Info.natures.length) }
}

// The ability slot survives evolution, like in the games.
function abilityOf(slug, ab) {
  var e = Info.species[slug]
  if (ab && ab.hidden && e[8]) return e[8]
  return e[7][Math.min(ab ? ab.slot : 0, e[7].length - 1)]
}
function abilityName(id) { return Info.abilities[id] ? Info.abilities[id][0] : id }
function abilityText(id) { return Info.abilities[id] ? Info.abilities[id][1] : "" }
function natureName(n) { return Info.natures[n][0] }

function entry(slug) {
  var e = Info.species[slug]
  return { number: ("000" + e[0]).slice(-4), genus: e[1], text: e[2],
           height: (e[3] / 10).toFixed(1) + " m", weight: (e[4] / 10).toFixed(1) + " kg",
           types: e[5], baseTotal: e[6].reduce(function(a, b) { return a + b }, 0) }
}

// Actual stats with the main-series formula.
function stats(p) {
  var base = Info.species[p.species][6]
  var nat = Info.natures[p.nature || 0]
  var lv = level(p)
  var e = evs(p)
  return base.map(function(b, i) {
    var iv = p.ivs ? p.ivs[i] : 0
    var core = Math.floor((2 * b + iv + Math.floor(e[i] / 4)) * lv / 100)
    var up = i > 0 && nat[1] !== nat[2] && nat[1] === i
    var down = i > 0 && nat[1] !== nat[2] && nat[2] === i
    var value = i === 0 ? core + lv + 10 : Math.floor((core + 5) * (up ? 1.1 : down ? 0.9 : 1))
    return { label: STAT_LABELS[i], base: b, iv: iv, ev: Math.floor(e[i]), value: value, up: up, down: down }
  })
}

function ivTotal(p) { return (p.ivs || []).reduce(function(a, b) { return a + b }, 0) }

// ---- EV training ----

function evs(p) { return p.evs || [0, 0, 0, 0, 0, 0] }
function evTotal(p) { return evs(p).reduce(function(a, b) { return a + b }, 0) }

// Highest value this stat's EVs can reach, given both caps.
function evCeiling(p, stat) {
  var e = evs(p)
  return Math.floor(e[stat] + Math.max(0, Math.min(EV_MAX_STAT - e[stat], EV_MAX_TOTAL - evTotal(p))))
}

function trainKind(t) { return t && t.kind === "xp" ? "xp" : "ev" }

function xpForLevel(lv) { return (lv - START_LEVEL) * 10 }

function train(p, from, to) {
  var t = p.training
  if (!t) return
  var hours = Math.max(0, (to - from) / 3600000)
  if (trainKind(t) === "xp") {
    var goal = xpForLevel(Math.min(MAX_LEVEL, t.target))
    var add = Math.min(Math.max(0, goal - p.xp), TRAIN_XP_PER_HOUR * hours)
    p.xp += add
    if (p.xp >= goal - 0.0001) p.training = null
    return
  }
  if (!p.evs) p.evs = [0, 0, 0, 0, 0, 0]
  var room = Math.min(t.target, evCeiling(p, t.stat)) - p.evs[t.stat]
  var gain = Math.min(Math.max(0, room), TRAIN_EV_PER_HOUR * hours)
  p.evs[t.stat] += gain
  if (room - gain <= 0.0001) {
    p.evs[t.stat] = Math.round(p.evs[t.stat])
    p.training = null
  }
}

function trainees(save) { return ownedRoots(save).filter(function(r) { return !!save.pets[r].training }) }

function canTrain(save, root) {
  var p = save.pets[root]
  return !!p && !isAway(save, root) && (!!p.training || trainees(save).length < TRAIN_SLOTS)
}

// kind "ev": target is the stat's EV goal; kind "xp": target is a level.
function startTraining(save, root, kind, stat, target) {
  var p = save.pets[root]
  if (!p || !canTrain(save, root)) return false
  if (kind === "xp") {
    if (target <= level(p)) return false
    p.training = { kind: "xp", stat: 0, target: Math.min(MAX_LEVEL, target) }
  } else {
    if (!p.evs) p.evs = [0, 0, 0, 0, 0, 0]
    p.training = { kind: "ev", stat: stat, target: Math.min(target, evCeiling(p, stat)) }
  }
  return true
}

function stopTraining(save, root) {
  var p = save.pets[root]
  if (!p || !p.training) return
  if (p.evs) p.evs = p.evs.map(function(v) { return Math.floor(v) })
  p.training = null
}

function trainingText(p) {
  var t = p && p.training
  if (!t) return ""
  if (trainKind(t) === "xp") return "Training to Lv. " + t.target
  return "Training " + STAT_LABELS[t.stat] + " (" + Math.floor(evs(p)[t.stat]) + " / " + t.target + " EVs)"
}

function trainingLeft(p) {
  var t = p && p.training
  if (!t) return ""
  var m = trainKind(t) === "xp"
    ? Math.ceil((xpForLevel(Math.min(MAX_LEVEL, t.target)) - p.xp) / TRAIN_XP_PER_HOUR * 60)
    : Math.ceil((Math.min(t.target, evCeiling(p, t.stat)) - evs(p)[t.stat]) / TRAIN_EV_PER_HOUR * 60)
  return m >= 60 ? Math.floor(m / 60) + "h" + ("0" + m % 60).slice(-2) : Math.max(1, m) + " min"
}

// Owned family roots in National Dex order (the Day Care boxes use it).
function ownedRoots(save) { return Dex.families.filter(function(r) { return !!save.pets[r] }) }

// ---- Moves ----
// Pokémon learn their level-up moves as they grow (the oldest is forgotten
// past four) and can relearn any move they know at the Move Reminder.

function learnset(slug) { return Moves.learnsets[slug] || [] }
function moveName(id) { return Moves.moves[id] ? Moves.moves[id][0] : "???" }
var CATEGORIES = ["Status", "Physical", "Special"]

function move(id) {
  var m = Moves.moves[id]
  if (!m) return { id: id, name: "???", type: "normal", category: "Status", power: 0, accuracy: 0, pp: 0, text: "" }
  return { id: id, name: m[0], type: m[1], category: CATEGORIES[m[2]], power: m[3], accuracy: m[4], pp: m[5], text: m[6] }
}

// Learns the moves reached since the last call; returns their ids. A Pokémon
// that never had moves starts with the last four it could have learned.
function syncMoves(p) {
  var lv = level(p), set = learnset(p.species), learned = []
  if (!p.moves) {
    var known = []
    for (var i = 0; i < set.length; i += 2)
      if (set[i] <= lv && known.indexOf(set[i + 1]) < 0) known.push(set[i + 1])
    p.known = known
    p.moves = known.slice(-MAX_MOVES)
    p.movesAt = { species: p.species, level: lv }
    return learned
  }
  var at = p.movesAt || { species: p.species, level: lv }
  var evolved = at.species !== p.species
  if (!p.known) p.known = p.moves.slice()
  for (var j = 0; j < set.length; j += 2) {
    var l = set[j], m = set[j + 1]
    if (!((l > at.level && l <= lv) || (evolved && l === 0))) continue
    if (p.known.indexOf(m) < 0) p.known.push(m)
    if (p.moves.indexOf(m) >= 0) continue
    if (p.moves.length >= MAX_MOVES) p.moves.shift()
    p.moves.push(m)
    learned.push(m)
  }
  p.movesAt = { species: p.species, level: lv }
  return learned
}

function moves(p) { return (p && p.moves || []).map(move) }

// Moves the Move Reminder offers: everything this species learns up to its
// level, plus anything it learned before, minus what it knows right now.
function relearnable(p) {
  if (!p) return []
  var lv = level(p), set = learnset(p.species), out = []
  for (var i = 0; i < set.length; i += 2)
    if (set[i] <= lv && out.indexOf(set[i + 1]) < 0) out.push(set[i + 1])
  ;(p.known || []).forEach(function(m) { if (out.indexOf(m) < 0) out.push(m) })
  return out.filter(function(m) { return (p.moves || []).indexOf(m) < 0 }).map(move)
}

// Teaches a relearnable move, replacing the one in `slot` (or filling a free slot).
function relearn(save, ref, id, slot) {
  var p = specimen(save, ref)
  if (!p) return ""
  if (!isBoxed(ref) && isAway(save, refRoot(ref))) return name(p.species) + " is away on an expedition."
  if (!relearnable(p).some(function(m) { return m.id === id })) return ""
  var n = name(p.species)
  if (!p.moves) p.moves = []
  if (p.moves.length < MAX_MOVES) {
    p.moves.push(id)
    return n + " learned " + moveName(id) + "!"
  }
  if (slot === undefined || slot === null || slot < 0 || slot >= p.moves.length) return ""
  var old = p.moves[slot]
  p.moves[slot] = id
  return "1, 2 and… Poof! " + n + " forgot " + moveName(old) + " and learned " + moveName(id) + "!"
}

// ---- TMs ----
// A TM teaches its move to any Pokémon that could learn it from a TM or TR in
// some main-series game. It is used up, but the move stays at the Move Reminder.

function tmMove(id) { return Items.items[id] && itemKind(id) === "tm" ? Items.items[id][4].move : 0 }

function canLearnTm(p, id) {
  var t = Items.items[id]
  if (!p || !t || t[1] !== "tm") return false
  var nums = Moves.machines[p.species] || ""
  var hex = ("0" + parseInt(id.slice(2), 10).toString(16)).slice(-2)
  for (var i = 0; i < nums.length; i += 2) if (nums.substr(i, 2) === hex) return true
  return false
}

// TMs in the bag that this Pokémon can use and doesn't know right now.
function tmsFor(save, p) {
  if (!p) return []
  return bagItems(save).filter(function(id) {
    return itemKind(id) === "tm" && canLearnTm(p, id) && (p.moves || []).indexOf(tmMove(id)) < 0
  })
}

// One TM, rarer ones less often.
function rollTm(rand) {
  var list = Moves.tms.map(function(t) { return Items.tmId(t[0]) })
  var r = rand() * list.reduce(function(a, id) { return a + Items.TM_WEIGHTS[Items.items[id][4].rarity] }, 0)
  for (var i = 0; i < list.length; i++) {
    r -= Items.TM_WEIGHTS[Items.items[list[i]][4].rarity]
    if (r <= 0) return list[i]
  }
  return list[list.length - 1]
}

// Teaches a TM, replacing the move in `slot` (or filling a free slot).
function teachTm(save, ref, id, slot) {
  var p = specimen(save, ref)
  if (!p || !(save.bag[id] > 0)) return ""
  if (!isBoxed(ref) && isAway(save, refRoot(ref))) return name(p.species) + " is away on an expedition."
  if (!canLearnTm(p, id)) return name(p.species) + " can't learn " + moveName(tmMove(id)) + "."
  var n = name(p.species), m = tmMove(id)
  if (!p.moves) p.moves = []
  if (p.moves.indexOf(m) >= 0) return n + " already knows " + moveName(m) + "."
  if (!p.known) p.known = p.moves.slice()
  var msg = ""
  if (p.moves.length < MAX_MOVES) {
    p.moves.push(m)
    msg = n + " learned " + moveName(m) + "!"
  } else {
    if (slot === undefined || slot === null || slot < 0 || slot >= p.moves.length) return ""
    var old = p.moves[slot]
    p.moves[slot] = m
    msg = "1, 2 and… Poof! " + n + " forgot " + moveName(old) + " and learned " + moveName(m) + "!"
  }
  if (p.known.indexOf(m) < 0) p.known.push(m)
  consume(save, id)
  return msg
}

// ---- Shop ----
// Poké Dollars come from expeditions and from selling items. Most things are
// always in stock; mints and the rarer evolution items change every day.

var DAILY_MINTS = 3
var DAILY_EVOLUTION = 4
var DAILY_TMS = 10                  // TMs on sale each day, at most one very rare

function price(id) { return Items.prices[id] || 0 }
function sellPrice(id) { return Items.sellOnly[id] || Math.floor(price(id) * SELL_RATE) }
function money(save) { return save.money || 0 }

function day(now) { var d = new Date(now); return d.getFullYear() * 1000 + Math.floor((d - new Date(d.getFullYear(), 0, 1)) / 86400000) }

// Items for sale today, by shelf.
function shopStock(now) {
  var rand = seeded("shop:" + day(now))
  var ids = Object.keys(Items.prices).filter(function(i) { return price(i) > 0 })
  function shelf(kinds) { return ids.filter(function(i) { return kinds.indexOf(itemKind(i)) >= 0 }) }
  function some(list, n) {
    list = list.slice()
    var out = []
    while (list.length && out.length < n) out.push(list.splice(Math.floor(rand() * list.length), 1)[0])
    return out
  }
  var stones = shelf(["evolution"]).filter(function(i) { return /-stone$/.test(i) })
  var rare = shelf(["evolution"]).filter(function(i) { return !/-stone$/.test(i) })
  return [
    { name: "Balls", items: shelf(["ball"]) },
    { name: "Provisions", items: shelf(["food", "medicine", "pp", "status", "revive", "escape"]) },
    { name: "Partner", items: shelf(["berry", "candy", "incense", "cap"]).concat(some(shelf(["mint"]), DAILY_MINTS)) },
    { name: "Evolution", items: stones.concat(some(rare, DAILY_EVOLUTION)) },
    { name: "TMs", items: dailyTms(rand) }
  ]
}

function dailyTms(rand) {
  var out = [], guard = 0, veryRare = 0
  while (out.length < DAILY_TMS && guard++ < 200) {
    var id = rollTm(rand)
    var rarity = Items.items[id][4].rarity
    if (out.indexOf(id) >= 0 || (rarity === 4 && veryRare)) continue
    if (rarity === 4) veryRare = 1
    out.push(id)
  }
  return out.sort()
}

function inStock(id, now) { return shopStock(now).some(function(s) { return s.items.indexOf(id) >= 0 }) }

// Returns "" when done, or why not.
function buy(save, id, count, now) {
  count = Math.max(1, Math.floor(count || 1))
  if (!inStock(id, now)) return "That isn't for sale today."
  var cost = price(id) * count
  if (money(save) < cost) return "Not enough money: " + count + " × " + itemName(id) + " costs ₽" + cost + "."
  save.money = money(save) - cost
  save.bag[id] = (save.bag[id] || 0) + count
  return ""
}

function sell(save, id, count) {
  count = Math.max(1, Math.floor(count || 1))
  var each = sellPrice(id)
  if (!each) return "The shop doesn't buy that."
  if ((save.bag[id] || 0) < count) return "You don't have that many."
  save.bag[id] -= count
  if (save.bag[id] <= 0) delete save.bag[id]
  save.money = money(save) + each * count
  return ""
}

function sellable(save) { return bagItems(save).filter(function(i) { return sellPrice(i) > 0 }) }

