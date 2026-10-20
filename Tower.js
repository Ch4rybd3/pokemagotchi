.pragma library
.import "Pet.js" as Pet
.import "Items.js" as Items
.import "Info.js" as Info
.import "Moves.js" as Moves
.import "Dex.js" as Dex
.import "Trainers.js" as Trainers

// The Battle Tower: challenges of 7 battles against trainers of one tower and
// tier, with a battle team of yours. Battles run in TowerWorker.mjs (Pokémon
// Showdown); this file keeps the teams, the challenge in progress and the rewards.
//
// Everybody fights at Lv. 50, and only Pokémon at Lv. 50 or more can enter.
// In Singles you pick 3 of your team's Pokémon after seeing the other team, in
// Doubles 4, like the VGC.

var MIN_LEVEL = 50
var RUN_LENGTH = 7                  // battles in a challenge; the 7th is a boss
var TEAMS = 6                       // battle teams you can keep
var TEAM_SIZE = 6
var PICK = { singles: 3, doubles: 4 }
var FORMATS = ["singles", "doubles"]
var FORMAT_NAMES = { singles: "Singles", doubles: "Doubles" }

// Rewards. BP per win by tier ("level": 1-4 in the regional towers, 5-7 at the
// Radical Red Tower). A cleared challenge adds 3 wins' worth of BP and some
// Poké Dollars; the first clear of a tier adds 10 wins' worth.
var SET_BONUS = 3
var FIRST_CLEAR_BONUS = 10
var MONEY_PER_SET = 100             // × level
var FIRST_WIN_BP = 2                // the first time you beat a named trainer
var STREAK_BONUS_MAX = 3            // +1 BP per win per challenge cleared in a row, up to 3
var BP_TMS_DAILY = 6                // rare TMs at the BP counter, changing every day
var TM_BP = [0, 0, 0, 32, 64]       // BP price of a TM by rarity (3 and 4 only)
var HISTORY = 20

// ---- Towers ----

function towers() { return Trainers.towers }
function tower(id) {
  var list = Trainers.towers
  for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
  return null
}
function tierCount(id) { var t = tower(id); return t ? t.tiers.length : 0 }
function tierName(id, tier) { var t = tower(id); return t && t.tiers[tier - 1] ? t.tiers[tier - 1].name : "" }
function stars(id, tier) { var t = tower(id); return t && t.tiers[tier - 1] ? t.tiers[tier - 1].stars : 0 }
function level(id, tier) { return id === "radical-red" ? 4 + tier : tier }
function bpPerWin(id, tier) { return level(id, tier) }

function key(towerId, format) { return towerId + ":" + format }

// The Tower's part of the save, created on first use.
function state(save) {
  if (!save.tower) save.tower = { bp: 0, teams: [], progress: {}, best: {}, beaten: {}, run: null, history: [], wins: 0, battles: 0 }
  var t = save.tower
  if (!Array.isArray(t.teams)) t.teams = []
  if (!t.progress) t.progress = {}
  if (!t.best) t.best = {}
  if (!t.beaten) t.beaten = {}
  if (!Array.isArray(t.history)) t.history = []
  return t
}
function peek(save) { return save.tower || { bp: 0, teams: [], progress: {}, best: {}, beaten: {}, run: null, history: [], wins: 0, battles: 0 } }
function bp(save) { return peek(save).bp || 0 }
function cleared(save, towerId, format) { return peek(save).progress[key(towerId, format)] || 0 }
function bestStreak(save, towerId, format, tier) { return peek(save).best[key(towerId, format) + ":" + tier] || 0 }

// Regional towers are open from the start, one tier at a time. The Radical Red
// Tower opens once you clear a Master tier anywhere, in that format.
function towerOpen(save, towerId, format) {
  var t = tower(towerId)
  if (!t) return false
  if (t.unlock !== "master") return true
  return Trainers.towers.some(function(o) { return o.unlock !== "master" && cleared(save, o.id, format) >= o.tiers.length })
}
function tierOpen(save, towerId, format, tier) {
  return towerOpen(save, towerId, format) && tier >= 1 && tier <= tierCount(towerId) && tier <= cleared(save, towerId, format) + 1
}

// ---- Trainers ----
// Trainers.trainers[id] = [name, class, tower, tier, rating, ai, boss, team, format]

function trainer(id) {
  var t = Trainers.trainers[id]
  if (!t) return null
  return { id: id, name: t[0], cls: t[1], tower: t[2], tier: t[3], rating: t[4], ai: t[5], boss: !!t[6], team: t[7],
           format: t[8], size: teamSize(t[7]), named: isNamed(id) }
}
function teamSize(packed) { return packed ? packed.split("]").length : 0 }
// Generic trainers are made by the generator: "kanto-s2-7", "rr-ace-12".
function isNamed(id) { return !/-[sd]\d-\d+$/.test(id) && !/^rr-ace-/.test(id) }
function title(t) { return t ? t.cls + " " + t.name : "" }

function pool(towerId, format, tier) {
  var out = []
  for (var id in Trainers.trainers) {
    var t = Trainers.trainers[id]
    if (t[2] !== towerId || t[3] !== tier) continue
    if (t[8] && t[8] !== format.charAt(0)) continue
    if (teamSize(t[7]) < PICK[format]) continue
    out.push(id)
  }
  return out
}

// The 7 trainers of a challenge: 6 of the tier, easiest first, then a boss.
function drawOpponents(towerId, format, tier, rand) {
  var ids = pool(towerId, format, tier)
  var bosses = ids.filter(function(id) { return Trainers.trainers[id][6] })
  var named = ids.filter(function(id) { return !Trainers.trainers[id][6] && isNamed(id) })
  var generic = ids.filter(function(id) { return !Trainers.trainers[id][6] && !isNamed(id) })
  function take(list, n) {
    list = list.slice()
    var out = []
    while (list.length && out.length < n) out.push(list.splice(Math.floor(rand() * list.length), 1)[0])
    return out
  }
  var picks = take(named, 3)
  picks = picks.concat(take(generic, RUN_LENGTH - 1 - picks.length))
  if (picks.length < RUN_LENGTH - 1) picks = picks.concat(take(bosses, RUN_LENGTH - 1 - picks.length))
  picks.sort(function(a, b) { return Trainers.trainers[a][4] - Trainers.trainers[b][4] || (rand() - 0.5) })
  var boss = take(bosses.filter(function(b) { return picks.indexOf(b) < 0 }), 1)
  if (!boss.length) boss = take(named.concat(generic).filter(function(b) { return picks.indexOf(b) < 0 }), 1)
  return picks.concat(boss)
}

// ---- Battle teams ----
// A team: { name, members: [{ ref: family root, item: "" }] }. Only each
// family's Day Care Pokémon (or your partner) can be in a team.

function teams(save) { return peek(save).teams || [] }

function newTeam(save) {
  var t = state(save)
  if (t.teams.length >= TEAMS) return -1
  t.teams.push({ name: "Team " + (t.teams.length + 1), members: [] })
  return t.teams.length - 1
}

function deleteTeam(save, i) {
  var t = state(save)
  if (t.run && t.run.team === i) return false
  t.teams.splice(i, 1)
  if (t.run && t.run.team > i) t.run.team -= 1
  return true
}

function renameTeam(save, i, name) {
  var t = state(save)
  if (t.teams[i]) t.teams[i].name = String(name || "").slice(0, 16) || ("Team " + (i + 1))
}

function eligible(save, root) {
  var p = save.pets[root]
  return !!p && Pet.level(p) >= MIN_LEVEL
}

// Your Pokémon that can enter, strongest first.
function candidates(save) {
  return Pet.ownedRoots(save).filter(function(r) { return eligible(save, r) })
    .sort(function(a, b) { return save.pets[b].xp - save.pets[a].xp })
}

function toggleMember(save, i, root) {
  var team = state(save).teams[i]
  if (!team) return ""
  var at = indexOf(team, root)
  if (at >= 0) { team.members.splice(at, 1); return "" }
  if (team.members.length >= TEAM_SIZE) return "A team has " + TEAM_SIZE + " Pokémon at most."
  if (!eligible(save, root)) return Pet.name(save.pets[root].species) + " must be Lv. " + MIN_LEVEL + " or more."
  team.members.push({ ref: root, item: "" })
  return ""
}

function moveMember(save, i, from, to) {
  var team = state(save).teams[i]
  if (!team || !team.members[from] || to < 0 || to >= team.members.length) return
  var m = team.members.splice(from, 1)[0]
  team.members.splice(to, 0, m)
}

function indexOf(team, root) {
  for (var k = 0; k < team.members.length; k++) if (team.members[k].ref === root) return k
  return -1
}

// Items a Pokémon can hold in the Tower: held items, and a few others from the bag.
function holdable(id) { return Pet.itemKind(id) === "held" || Items.alsoHeld.indexOf(id) >= 0 }
function holdableItems(save) { return Pet.bagItems(save).filter(holdable) }

// Item Clause: one of each item per team.
function setItem(save, i, slot, id) {
  var team = state(save).teams[i]
  if (!team || !team.members[slot]) return ""
  if (id && !holdable(id)) return "That can't be held."
  if (id && !(save.bag[id] > 0)) return "You don't have " + Pet.itemName(id) + "."
  for (var k = 0; k < team.members.length; k++)
    if (k !== slot && id && team.members[k].item === id) return "Item Clause: only one " + Pet.itemName(id) + " per team."
  team.members[slot].item = id || ""
  return ""
}

// Problems that keep a team from entering, "" when it's ready.
function teamProblem(save, i, format) {
  var team = teams(save)[i]
  if (!team) return "Choose a battle team."
  var pick = PICK[format]
  if (team.members.length < pick) return FORMAT_NAMES[format] + " needs " + pick + " Pokémon or more in the team."
  var away = Pet.awayRoots(save), seen = {}
  for (var k = 0; k < team.members.length; k++) {
    var m = team.members[k], p = save.pets[m.ref]
    if (!p) return "A Pokémon of this team is gone."
    var n = Pet.name(p.species)
    if (Pet.level(p) < MIN_LEVEL) return n + " must be Lv. " + MIN_LEVEL + " or more."
    if (away[m.ref]) return n + " is away on an expedition."
    if (!(p.moves || []).length) return n + " doesn't know any move."
    if (m.item && !(save.bag[m.item] > 0)) return "You no longer have the " + Pet.itemName(m.item) + " that " + n + " holds."
    if (m.item && seen[m.item]) return "Item Clause: only one " + Pet.itemName(m.item) + " per team."
    if (m.item) seen[m.item] = true
  }
  return ""
}

// ---- Showdown sets ----

function toID(text) { return String(text || "").toLowerCase().replace(/[^a-z0-9]+/g, "") }

// A Pokémon in Showdown's packed format, at Lv. 50.
function packed(p, item) {
  var ability = Pet.abilityOf(p.species, p.ability)
  var nature = Info.natures[p.nature || 0][0]
  var evs = Pet.evs(p).map(function(v) { return Math.floor(v) })
  var ivs = (p.ivs || [31, 31, 31, 31, 31, 31])
  var moves = (p.moves || []).map(function(id) { return toID(Pet.moveName(id)) })
  return [Pet.name(p.species).replace(/[|\]]/g, ""), toID(p.species), toID(item || ""), toID(ability), moves.join(","),
          nature, evs.map(function(v) { return v || "" }).join(","), "", ivs.map(function(v) { return v === 31 ? "" : v }).join(","),
          p.shiny ? "S" : "", MIN_LEVEL, ""].join("|")
}

function packedTeam(save, team) {
  return team.members.map(function(m) { return packed(save.pets[m.ref], m.item) }).join("]")
}

// ---- Challenges ----

function run(save) { return peek(save).run || null }
function inRun(save, root) {
  var r = run(save)
  return !!r && r.refs.indexOf(root) >= 0
}

function seed() { return Math.floor(Math.random() * 2147483647) + 1 }

// Starts a challenge. Returns "" or why not.
function start(save, towerId, format, tier, teamIndex, now) {
  var t = state(save)
  if (t.run) return "Finish your current challenge first."
  if (!tower(towerId) || PICK[format] === undefined) return "Unknown tower."
  if (!tierOpen(save, towerId, format, tier)) return "Clear the tier before it first."
  var err = teamProblem(save, teamIndex, format)
  if (err) return err
  var team = t.teams[teamIndex]
  var rand = Pet.seeded("run:" + now + ":" + Math.random())
  var opponents = drawOpponents(towerId, format, tier, rand)
  if (opponents.length < RUN_LENGTH) return "Not enough trainers here yet."
  t.run = { tower: towerId, format: format, tier: tier, team: teamIndex, name: team.name,
            refs: team.members.map(function(m) { return m.ref }), sets: packedTeam(save, team),
            opponents: opponents, wins: 0, streak: 0, started: now, earned: { bp: 0, money: 0, items: [] },
            battle: null, last: null }
  return ""
}

function opponent(save) {
  var r = run(save)
  return r ? trainer(r.opponents[r.wins % RUN_LENGTH]) : null
}

// The battle in progress, created when needed. Its seed and choices are kept
// so it can be rebuilt after a restart.
function battle(save) {
  var t = state(save), r = t.run
  if (!r) return null
  if (!r.battle) r.battle = { seed: seed(), input: [], opponent: r.opponents[r.wins % RUN_LENGTH] }
  return r.battle
}

// What TowerWorker needs to start (or rebuild) the battle.
function battleOptions(save, playerName) {
  var r = run(save)
  var b = r && r.battle
  if (!b) return null
  var o = trainer(b.opponent)
  return { key: "tower:" + r.started + ":" + r.wins + ":" + b.seed, format: r.format, seed: b.seed,
           p1: { name: playerName || "You", team: r.sets },
           p2: { name: title(o), team: o.team, ai: o.ai },
           input: b.input.slice() }
}

function saveInput(save, input) {
  var r = run(save)
  if (r && r.battle) r.battle.input = input.slice()
}

// The battle is over: rewards, and what comes next. Returns the summary to show.
function finishBattle(save, won, now) {
  var t = state(save), r = t.run
  if (!r || !r.battle) return null
  var o = trainer(r.battle.opponent)
  var out = { won: won, trainer: title(o), bp: 0, money: 0, firstWin: false, setDone: false, firstClear: false,
              unlocked: "", over: false, wins: 0 }
  t.battles = (t.battles || 0) + 1
  r.battle = null
  if (!won) {
    out.over = true
    endRun(save, "lost", now)
    out.wins = r.wins
    return out
  }
  t.wins = (t.wins || 0) + 1
  r.wins += 1
  out.wins = r.wins
  var per = bpPerWin(r.tower, r.tier) + Math.min(STREAK_BONUS_MAX, r.streak)
  out.bp += per
  if (o && o.named && !t.beaten[o.id]) { t.beaten[o.id] = 1; out.bp += FIRST_WIN_BP; out.firstWin = true }
  var k = key(r.tower, r.format)
  var bestKey = k + ":" + r.tier
  if (r.wins + r.streak * RUN_LENGTH > (t.best[bestKey] || 0)) t.best[bestKey] = r.wins + r.streak * RUN_LENGTH
  if (r.wins >= RUN_LENGTH) {
    out.setDone = true
    out.bp += bpPerWin(r.tower, r.tier) * SET_BONUS
    out.money = MONEY_PER_SET * level(r.tower, r.tier)
    if ((t.progress[k] || 0) < r.tier) {
      t.progress[k] = r.tier
      out.firstClear = true
      out.bp += bpPerWin(r.tower, r.tier) * FIRST_CLEAR_BONUS
      if (r.tier < tierCount(r.tower)) out.unlocked = tierName(r.tower, r.tier + 1)
      else if (r.tower !== "radical-red" && !wasRadicalOpen(save, r.format, k)) out.unlocked = "Radical Red Tower"
    }
  }
  t.bp = (t.bp || 0) + out.bp
  save.money = (save.money || 0) + out.money
  r.earned.bp += out.bp
  r.earned.money += out.money
  return out
}

// Whether the Radical Red Tower was already open before this clear.
function wasRadicalOpen(save, format, justCleared) {
  return Trainers.towers.some(function(o) {
    return o.unlock !== "master" && key(o.id, format) !== justCleared && cleared(save, o.id, format) >= o.tiers.length
  })
}

// After 7 wins: keep going (a new challenge, the streak goes on) or stop here.
function continueRun(save, now) {
  var r = run(save)
  if (!r || r.wins < RUN_LENGTH) return false
  var rand = Pet.seeded("run:" + now + ":" + Math.random())
  r.opponents = drawOpponents(r.tower, r.format, r.tier, rand)
  r.wins = 0
  r.streak += 1
  r.battle = null
  return true
}

function endRun(save, result, now) {
  var t = state(save), r = t.run
  if (!r) return
  t.history.unshift({ at: now, tower: r.tower, format: r.format, tier: r.tier, team: r.name,
                      wins: r.wins + r.streak * RUN_LENGTH, bp: r.earned.bp, money: r.earned.money, result: result })
  t.history = t.history.slice(0, HISTORY)
  t.run = null
}

// Gives up the challenge (a battle in progress counts as lost).
function quit(save, now) {
  var r = run(save)
  if (!r) return
  endRun(save, r.wins >= RUN_LENGTH ? "cleared" : r.battle && r.battle.input.length ? "lost" : "quit", now)
}

// ---- BP counter ----

function bpPrice(id) {
  if (Items.bp[id]) return Items.bp[id]
  if (Pet.itemKind(id) === "tm") return TM_BP[Items.items[id][4].rarity] || 0
  return 0
}

function day(now) { return Pet.day(now) }

// Shelves of the BP counter. Rare TMs and mints change every day.
function counter(now) {
  var rand = Pet.seeded("bp:" + day(now))
  var held = Object.keys(Items.held).sort(function(a, b) { return Items.held[b][1] - Items.held[a][1] || (a < b ? -1 : 1) })
  var tms = Moves.tms.filter(function(t) { return t[2] >= 3 }).map(function(t) { return Items.tmId(t[0]) })
  var daily = []
  while (tms.length && daily.length < BP_TMS_DAILY) daily.push(tms.splice(Math.floor(rand() * tms.length), 1)[0])
  var mints = Object.keys(Items.items).filter(function(i) { return Pet.itemKind(i) === "mint" })
  var someMints = []
  while (mints.length && someMints.length < 4) someMints.push(mints.splice(Math.floor(rand() * mints.length), 1)[0])
  return [
    { name: "Held items", items: held },
    { name: "Training", items: ["ability-capsule", "ability-patch", "bottle-cap", "gold-bottle-cap", "rare-candy", "exp-candy-xl"].concat(someMints) },
    { name: "TMs", items: daily.sort() },
    { name: "Rare", items: ["master-ball"] }
  ]
}

function onCounter(id, now) { return counter(now).some(function(s) { return s.items.indexOf(id) >= 0 }) }

function buy(save, id, count, now) {
  count = Math.max(1, Math.floor(count || 1))
  if (!onCounter(id, now)) return "That isn't available today."
  var cost = bpPrice(id) * count
  var t = state(save)
  if ((t.bp || 0) < cost) return "Not enough BP: " + count + " × " + Pet.itemName(id) + " costs " + cost + " BP."
  t.bp -= cost
  save.bag[id] = (save.bag[id] || 0) + count
  return ""
}

// ---- Text ----

function towerTitle(id) { var t = tower(id); return t ? t.name : "" }
function starText(n) { var s = ""; for (var i = 0; i < n; i++) s += "★"; return s }
function runTitle(r) { return r ? towerTitle(r.tower) + " · " + FORMAT_NAMES[r.format] + " · " + tierName(r.tower, r.tier) : "" }

// The species of a packed team, for previews: [{ slug, name }].
function previewOf(packedTeam) {
  if (!packedTeam) return []
  return packedTeam.split("]").map(function(p) {
    var f = p.split("|")
    var sp = f[1] || f[0]
    return { slug: slugOf(sp), name: f[0] || sp }
  })
}

// Showdown species ("Ninetales-Alola", "rotomwash") -> the plugin's sprite slug.
var _slugs = null
function slugOf(species) {
  if (!_slugs) {
    _slugs = {}
    for (var s in Dex.species) _slugs[toID(s)] = s
  }
  var id = toID(species)
  if (_slugs[id]) return _slugs[id]
  // Formes: try the longest known prefix ("ninetalesalola" -> "ninetales").
  for (var n = id.length - 1; n >= 3; n--) if (_slugs[id.slice(0, n)]) return _slugs[id.slice(0, n)]
  return ""
}
