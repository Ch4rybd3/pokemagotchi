import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Pet.js" as Pet
import "Expedition.js" as Exp
import "Tower.js" as Tower

BarWidget {
  id: root
  moduleName: "ch4rybd3.pokemagotchi"

  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/pokemagotchi.json"
  readonly property color accent: "#e23b44"
  readonly property color gold: "#f2b84b"
  readonly property color steel: "#4a86b8"
  readonly property color good: "#7fbf9a"

  // `save` mirrors the file on disk. Every bar (one per monitor) watches the
  // file and only writes on user interaction, so instances never clobber each
  // other with stale state.
  property var save: Pet.freshSave()
  property bool loaded: false
  property real now: Date.now()
  // Expeditions run first, so a team that just came home is back at the Day Care for Pet.tick.
  readonly property var view: Pet.tick(Exp.tick(Pet.copy(save), now), now)
  readonly property var pet: Pet.current(view)
  readonly property bool hasPet: pet !== null
  readonly property string speciesName: hasPet ? Pet.name(pet.species) : ""
  readonly property int nextLevel: hasPet ? Pet.nextLevel(pet.species) : 0
  readonly property int encountersLeft: Pet.encountersLeft(view, now)
  readonly property int searchesLeft: Pet.searchesLeft(view, now)
  readonly property int encountersPerWindow: Pet.encountersPerWindow(view, now)
  readonly property string incenseLeft: Pet.incenseLeft(view, now)
  readonly property int refillMinutes: Pet.minutesToRefill(now)
  readonly property bool partnerAway: hasPet && Pet.isAway(view, view.current)
  readonly property var expeditions: view.expeditions || []
  readonly property bool expeditionNews: expeditions.some(function(x) { return x.status === "done" && !x.seen })

  // "pet" | "menu" | "picker" | "box" | "confirm" | "evolve" | "encounter" | "found" | "bag"
  // | "info" | "moves" | "relearn" | "tms" | "daycare" | "train" | "expedition" | "shop"
  property string mode: "pet"
  property string message: ""
  property string query: ""
  property bool caughtOnly: false   // Pokédex filter: every family, or only the ones you own
  property bool opened: false
  property bool popoutSwitchClosing: false

  // Safari encounter shown on screen (kept after it ends, for the result).
  property string wildSlug: ""
  property bool wildShiny: false
  property int wildLevel: 0
  property bool encounterOver: false
  property bool busy: false
  property int shakeLoops: 1
  property var pendingThrow: null
  property var foundItems: []         // [{ id, count }] from the last search
  // Expedition followed in the popup, a clock for its walk, the log entry opened
  property string expId: ""
  property real expClock: Date.now()
  property var expOpenEntry: null
  readonly property var followed: expId ? Exp.find(view, expId) : null
  onFollowedChanged: if (mode === "expedition") Qt.callLater(markExpeditionSeen)
  property string ballItem: "poke-ball"

  // Summary page, boxes and Day Care. A ref is "root" (Day Care) or "root/N" (box).
  property string infoRef: ""
  property string infoBack: "pet"
  property string caughtRef: ""
  property string evolveRoot: ""      // a ref; "" = your partner
  property string boxRoot: ""
  property bool releaseArmed: false
  // Moves page: the move shown in detail, and a move waiting for a slot to replace
  property int moveSlot: -1
  property int relearnId: 0
  property string pendingTm: ""       // the TM being taught, while choosing the move it replaces
  readonly property var ownedRoots: Pet.ownedRoots(view)
  // Who plays in the Day Care field: its members, plus anyone training at the doll
  readonly property var daycareWalkers: ownedRoots.filter(function(r) {
    return !Pet.isAway(view, r) && (Pet.inDaycare(view, r) || !!view.pets[r].training)
  })
  // Shop
  property string shopTab: "buy"      // "buy" | "sell"
  property int shopShelf: 0
  property string shopItem: ""
  property int shopQty: 1
  property string selectedItem: ""
  property int trainStat: 1
  property int trainTarget: 252
  property string trainKind: "ev"     // "ev" | "xp"
  property int trainLevel: 15
  property string trainMessage: ""
  readonly property var trainees: Pet.trainees(view)
  readonly property var evolvePet: evolveRoot && Pet.specimen(view, evolveRoot) ? Pet.specimen(view, evolveRoot) : pet
  readonly property var trainPet: infoPet
  readonly property var infoPet: Pet.specimen(view, infoRef)
  readonly property bool infoBoxed: Pet.isBoxed(infoRef)
  readonly property var typeColors: ({
    normal: "#a8a77a", fire: "#ee8130", water: "#6390f0", electric: "#f7d02c", grass: "#7ac74c",
    ice: "#96d9d6", fighting: "#c22e28", poison: "#a33ea1", ground: "#e2bf65", flying: "#a98ff3",
    psychic: "#f95587", bug: "#a6b91a", rock: "#b6a136", ghost: "#735797", dragon: "#6f35fc",
    dark: "#705746", steel: "#b7b7ce", fairy: "#d685ad"
  })

  function open() { opened = true }
  function close() { opened = false }
  function toggle() { opened = !opened }
  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { popoutSwitchClosing = false })
  }

  onOpenedChanged: if (opened) {
    mutate(function() {})
    if (save.encounter) resumeEncounter()
    else home()
  }

  function home() {
    query = ""
    evolveRoot = ""
    selectedItem = ""
    // The ball stays shown after a catch; clear it when leaving the encounter.
    throwAnim.stop()
    busy = false
    ball.visible = false
    if (Pet.evolutionPending(save, Date.now())) {
      mode = "evolve"
      message = "What? " + speciesName + " is ready to evolve!"
    } else {
      mode = "pet"
      message = Pet.mood(save)
    }
  }

  // Applies a change on top of the latest saved state, then persists it.
  function mutate(fn) {
    if (!loaded) return null
    var t = Date.now()
    var before = Pet.current(save)
    var known = before && before.moves ? before.moves.slice() : null
    var s = Pet.tick(Exp.tick(Pet.copy(save), t), t)
    var after = Pet.current(s)
    var learned = known && after && s.current === save.current
      ? after.moves.filter(function(m) { return known.indexOf(m) < 0 }) : []
    var result = fn(s, t)
    var evo = Pet.maybeEvolve(s, t)
    var back = (s.expeditions || []).filter(function(x) { return x.status === "done" && !x.notified })
    back.forEach(function(x) { x.notified = true })
    save = s
    now = t
    stateFile.setText(JSON.stringify(s) + "\n")
    back.forEach(function(x) {
      notify("⛰ Your team is back from " + Exp.title(x) + "!",
             Exp.OUTCOMES[x.report.outcome] + " · B" + Math.max(1, x.report.floor) + "F · " + x.kos + " wild Pokémon defeated · ₽" + x.report.money
             + (x.report.recruits.length ? " · " + x.report.recruits.map(function(r) { return Pet.name(r.species) }).join(", ") + " joined you!" : ""))
    })
    if (evo) evolved(evo)
    if (learned.length) notify(Pet.name(after.species) + " learned " + learned.map(Pet.moveName).join(", ") + "!",
                               "Open its Moves page to see them or bring back an older move.")
    return result
  }

  function doAction(action) {
    message = mutate(function(s, t) { return Pet.act(s, action, t) })
    if (action === "pet") hearts.restart()
    else if (action === "play") jump.restart()
    else if (action === "feed") munch.restart()
  }

  // Pokédex entry: every Pokémon you own in this family, plus its Nav-Dex.
  function openBox(rootSlug) {
    if (!Pet.familySeen(view, rootSlug)) {
      message = "You haven't seen this one yet."
      return
    }
    boxRoot = rootSlug
    message = ""
    mode = "box"
  }

  function toggleNavdex(slug) {
    var target = view.navdex === slug ? "" : slug
    mutate(function(s) { Pet.setNavdex(s, target) })
    message = target ? "Nav-Dex on: every wild encounter will be " + Pet.name(target) + "." : "Nav-Dex off."
  }

  function sendToDayCare(ref) {
    var r = Pet.refRoot(ref)
    mutate(function(s, t) { Pet.makeLead(s, ref, t) })
    showInfo(r, "box")
  }

  function releaseBoxed(ref) {
    if (!releaseArmed) { releaseArmed = true; return }
    var n = Pet.name(infoPet.species)
    mutate(function(s) { Pet.release(s, ref) })
    openBox(Pet.refRoot(ref))
    message = "Bye-bye, " + n + "!"
  }

  function openMoves() {
    moveSlot = -1
    relearnId = 0
    pendingTm = ""
    message = ""
    mode = "moves"
  }

  function pickRelearn(id) {
    if ((infoPet.moves || []).length < Pet.MAX_MOVES) { teach(id, -1); return }
    relearnId = id
    moveSlot = -1
    message = ""
    mode = "moves"
  }

  function teach(id, slot) {
    var r = infoRef, tm = pendingTm
    message = mutate(function(s) { return tm ? Pet.teachTm(s, r, tm, slot) : Pet.relearn(s, r, id, slot) })
    pendingTm = ""
    relearnId = 0
    moveSlot = -1
    mode = "moves"
  }

  // A TM from the bag: taught at once if there's a free slot, else pick the move to forget.
  function pickTm(tm) {
    pendingTm = tm
    if ((infoPet.moves || []).length < Pet.MAX_MOVES) { teach(Pet.tmMove(tm), -1); return }
    relearnId = Pet.tmMove(tm)
    moveSlot = -1
    message = ""
    mode = "moves"
  }

  function openTower() {
    close()
    towerWindow.open()
  }

  function restart() {
    var oldName = speciesName
    mutate(function(s, t) { Pet.reset(s, t) })
    mode = "pet"
    message = "Bye, " + oldName + "! Say hello to " + speciesName + "."
  }

  function evolveInto(slug) {
    var target = evolveRoot
    var evo = mutate(function(s, t) { return Pet.evolveTo(s, slug, t, target || undefined) })
    if (target) showInfo(target, infoBack)
    else mode = "pet"
    if (evo) evolved(evo)
  }

  function notNow() {
    var target = evolveRoot
    mutate(function(s) { Pet.postpone(s, target || undefined) })
    if (target) { showInfo(target, infoBack); return }
    mode = "pet"
    message = "OK! " + speciesName + " will ask again at the next level. The Evolve button stays here."
  }

  function openEvolve(rootSlug) {
    evolveRoot = rootSlug && rootSlug !== save.current ? rootSlug : ""
    mode = "evolve"
    message = "Which way should " + Pet.name(evolvePet.species) + " evolve?"
  }

  function useItem(id, stat) {
    message = mutate(function(s, t) { return Pet.useItem(s, id, t, stat) })
  }

  function openTraining() {
    var p = infoPet
    if (!p) return
    var t = p.training
    trainKind = Pet.trainKind(t)
    trainStat = t && trainKind === "ev" ? t.stat : 1
    trainTarget = t && trainKind === "ev" ? t.target : Pet.evCeiling(p, trainStat)
    trainLevel = t && trainKind === "xp" ? t.target : Math.min(Pet.MAX_LEVEL, Pet.level(p) + 10)
    trainMessage = ""
    mode = "train"
  }

  function openTrainingFor(rootSlug) {
    infoRef = rootSlug
    openTraining()
  }

  function selectTrainStat(i) {
    trainStat = i
    trainTarget = Pet.evCeiling(infoPet, i)
  }

  function startTraining() {
    var r = infoRef, kind = trainKind, st = trainStat
    var tg = kind === "xp" ? trainLevel : trainTarget
    var ok = mutate(function(s) { return Pet.startTraining(s, r, kind, st, tg) })
    trainMessage = ok ? "" : "All " + Pet.TRAIN_SLOTS + " training spots are taken. Stop another training first."
  }

  function stopTraining() {
    var r = infoRef
    mutate(function(s) { Pet.stopTraining(s, r) })
  }

  // Plugins only get a narrow bar API (no shellQuote), so run notify-send
  // directly with an argument list: nothing goes through a shell.
  function notify(title, body) {
    Quickshell.execDetached(["notify-send", "-a", "Pokemagotchi", title, body])
  }

  function evolved(evo) {
    message = "Congratulations! Your " + evo.from + " evolved into " + evo.to + "!"
            + (evo.learned && evo.learned.length ? " It learned " + evo.learned.join(", ") + "!" : "")
    flash.restart()
    notify("What? " + evo.from + " is evolving!", "Congratulations! Your " + evo.from + " evolved into " + evo.to + "!")
  }

  // ---- Exploring ----

  function showWild(e) {
    wildSlug = e.species
    wildShiny = e.shiny
    wildLevel = e.level
    caughtRef = ""
    encounterOver = false
    busy = false
    ball.visible = false
    wildSprite.opacity = 1
    mode = "encounter"
    if (e.shiny) shinyBurst.restart()
  }

  function resumeEncounter() {
    showWild(save.encounter)
    message = "The wild " + Pet.name(wildSlug) + " is still here!"
  }

  function startWild() {
    if (save.encounter) { resumeEncounter(); return }
    if (encountersLeft <= 0) {
      message = "No more encounters for now. Come back in " + refillMinutes + " min."
      return
    }
    var e = mutate(function(s, t) { return Pet.startEncounter(s, t) })
    if (!e) return
    if (e.error === "full") {
      message = Pet.name(view.navdex) + "'s box is full (" + Pet.BOX_SIZE + "). Release some or turn the Nav-Dex off."
      return
    }
    if (e.error) { message = "Every box is full. What a collection!"; return }
    showWild(e)
    message = "A wild " + (e.shiny ? "shiny " : "") + Pet.name(e.species) + " appeared!"
  }

  function wildFled() {
    wildSprite.opacity = 0
    ball.visible = false
    encounterOver = true
    message = Pet.name(wildSlug) + " fled!"
  }

  function throwBall(kind) {
    if (busy || encounterOver) return
    var b = kind || "poke-ball"
    if (!(view.bag[b] > 0)) {
      message = Pet.ballsLeft(view) > 0 ? "You don't have any " + Pet.itemName(b) + "s left."
                                        : "You're out of Poké Balls! Search around to find more."
      return
    }
    var r = mutate(function(s, t) { return Pet.throwBall(s, t, b) })
    if (!r) return
    if (r.result === "full") {
      message = Pet.name(wildSlug) + "'s box is full (" + Pet.BOX_SIZE + "). Release one first."
      return
    }
    if (r.result === "noball") return
    busy = true
    pendingThrow = r
    ballItem = b
    shakeLoops = Math.max(1, r.shakes)
    message = "You threw " + (b === "ultra-ball" ? "an " : "a ") + Pet.itemName(b) + "!"
    throwAnim.restart()
  }

  function showInfo(ref, back) {
    if (!Pet.specimen(view, ref)) return
    infoRef = ref
    infoBack = back || "pet"
    releaseArmed = false
    message = ""
    mode = "info"
  }

  function leaveInfo() {
    if (infoBack === "daycare") mode = "daycare"
    else if (infoBack === "box") openBox(Pet.refRoot(infoRef))
    else home()
  }

  function makePartner(rootSlug) {
    if (rootSlug !== save.current) mutate(function(s, t) { Pet.switchTo(s, rootSlug, t) })
    home()
    message = "Go, " + speciesName + "!"
  }

  function finishThrow() {
    busy = false
    var r = pendingThrow
    if (r.result === "caught") {
      encounterOver = true
      caughtRef = r.ref
      var where = r.boxed ? "It was sent to its box (" + Pet.familyCount(view, Pet.family(wildSlug)) + " / " + Pet.BOX_SIZE + ")."
                          : "It's waiting for you in your Pokédex."
      message = "Gotcha! " + Pet.name(wildSlug) + " was caught! " + where
      sparkle.restart()
      notify("Gotcha! " + Pet.name(wildSlug) + " was caught!", where)
      if (r.charm) {
        message = "You caught them all! You received the Shiny Charm: shiny odds are now " + Pet.oddsText(view) + "."
        notify("✦ Shiny Charm obtained!", "Every family is caught. Shiny Pokémon now appear at " + Pet.oddsText(view) + ".")
      }
    } else if (r.result === "fled") {
      wildFled()
    } else {
      ball.visible = false
      wildSprite.opacity = 1
      message = r.shakes >= 2 ? "Aargh! Almost had it!" : "Oh no! The Pokémon broke free!"
    }
  }

  function throwRock() {
    if (busy || encounterOver) return
    var r = mutate(function(s) { return Pet.throwRock(s) })
    if (!r) return
    if (r.result === "fled") wildFled()
    else { message = "You threw a rock. " + Pet.name(wildSlug) + " is angry!"; wildShake.restart() }
  }

  function throwBait() {
    if (busy || encounterOver) return
    var r = mutate(function(s) { return Pet.throwBait(s) })
    if (!r) return
    if (r.result === "fled") wildFled()
    else { message = Pet.name(wildSlug) + " is eating!"; munchWild.restart() }
  }

  function runAway() {
    if (busy) return
    mutate(function(s) { Pet.run(s) })
    encounterOver = true
    wildSprite.opacity = 0
    message = "Got away safely!"
  }

  function search() {
    if (searchesLeft <= 0) {
      message = "You already searched around. Try again in " + refillMinutes + " min."
      return
    }
    var r = mutate(function(s, t) { return Pet.search(s, t) })
    if (!r) return
    foundItems = r
    mode = "found"
    var total = r.reduce(function(a, f) { return a + f.count }, 0)
    message = "You searched the area and found " + total + " items!"
    sparkle.restart()
  }

  // The window is for planning (and history); teams are followed here.
  function toggleDaycare(r) {
    message = mutate(function(s) { return Pet.toggleDaycare(s, r) })
  }

  // ---- Menu and shop ----

  function openMenuItem(id) {
    message = ""
    if (id === "partner") home()
    else if (id === "pokedex") { query = ""; mode = "picker"; searchField.forceActiveFocus() }
    else if (id === "bag") mode = "bag"
    else if (id === "shop") { shopItem = ""; shopQty = 1; mode = "shop" }
    else if (id === "daycare") mode = "daycare"
    else if (id === "training") {
      if (!hasPet) { message = "You need a partner Pokémon first."; return }
      if (partnerAway) { message = speciesName + " is away on an expedition."; return }
      openTrainingFor(view.current)
    }
    else if (id === "expeditions") openExpeditions("new")
    else if (id === "history") openExpeditions("history")
    else if (id === "tower") openTower()
    else if (id === "summary") { if (hasPet) showInfo(view.current, "pet") }
  }

  function pickShopItem(id) {
    shopItem = id
    shopQty = 1
    message = ""
  }

  function shopDeal() {
    var id = shopItem, n = shopQty, selling = shopTab === "sell"
    var err = mutate(function(s, t) { return selling ? Pet.sell(s, id, n) : Pet.buy(s, id, n, t) })
    if (err === null || err === undefined) return
    if (err) { message = err; return }
    message = (selling ? "Sold " : "Bought ") + n + " × " + Pet.itemName(id) + " for ₽" + (selling ? Pet.sellPrice(id) : Pet.price(id)) * n + "."
    if (selling && !(view.bag[id] > 0)) shopItem = ""
    shopQty = 1
  }

  function openExpeditions(which) {
    close()
    expeditionWindow.open(which || "new")
  }

  function followExpedition(id) {
    if (!opened) opened = true
    expId = id
    expOpenEntry = null
    expClock = Date.now()
    message = ""
    mode = "expedition"
    Qt.callLater(markExpeditionSeen)
  }

  function markExpeditionSeen() {
    var x = followed
    if (!x || x.status !== "done" || x.seen) return
    var id = x.id
    mutate(function(s) { var e = Exp.find(s, id); if (e) e.seen = true })
  }

  function recallExpedition() {
    var id = expId
    mutate(function(s, t) { Exp.recall(s, id, t) })
  }

  function closeReport() {
    var id = expId
    mutate(function(s) { Exp.dismiss(s, id) })
    expId = ""
    home()
  }

  implicitWidth: Math.max(barSize, (hasPet ? barSprite.width : barBall.width) + 6)
  implicitHeight: barSize

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var s = Pet.parse(text())
      if (s) root.save = s
      root.now = Date.now()
      root.loaded = true
    }
    onLoadFailed: function(error) {
      if (error === FileViewError.FileNotFound) root.loaded = true
    }
  }

  // Display refresh. It only writes when an expedition just came home, to
  // notify once (the flag is saved, so the other bars won't notify again).
  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: {
      root.now = Date.now()
      if (root.expeditions.some(function(x) { return x.status === "done" && !x.notified })) root.mutate(function() {})
    }
  }

  ExpeditionWindow {
    id: expeditionWindow
    host: root
  }

  TowerWindow {
    id: towerWindow
    host: root
  }

  // Keeps the corridor moving while you watch
  Timer {
    interval: 1000
    running: root.opened && root.mode === "expedition"
    repeat: true
    onTriggered: {
      root.expClock = Date.now()
      // Refresh the simulation now and then, so finished floors show up
      if (Math.floor(root.expClock / 1000) % 10 === 0) root.now = root.expClock
    }
  }

  component PetButton: Rectangle {
    id: btn
    property string label: ""
    property bool danger: false
    property bool highlight: false
    property bool enabledLook: true
    signal clicked()

    height: Style.space(30)
    radius: Style.cornerRadius
    opacity: root.loaded && enabledLook && !root.busy ? 1 : 0.4
    readonly property color tint: danger ? root.accent : highlight ? root.gold : root.steel
    color: area.pressed ? Qt.rgba(tint.r, tint.g, tint.b, 0.35)
         : area.containsMouse ? Qt.rgba(tint.r, tint.g, tint.b, 0.18)
         : danger || highlight ? Qt.rgba(tint.r, tint.g, tint.b, 0.12) : Qt.rgba(1, 1, 1, 0.05)
    border.width: 1
    border.color: area.containsMouse || danger || highlight ? tint : Qt.rgba(1, 1, 1, 0.12)

    Text {
      anchors.centerIn: parent
      text: btn.label
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.space(12)
    }

    MouseArea {
      id: area
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: if (root.loaded && !root.busy) btn.clicked()
    }
  }

  component Caption: Text {
    color: Color.popups.text
    opacity: 0.7
    font.family: Style.font.family
    font.pixelSize: Style.space(11)
  }

  // One move: type, name, category, power / accuracy / PP
  component MoveCard: Rectangle {
    id: card
    property var move: null
    property bool selected: false
    property bool warn: false
    signal clicked()

    height: Style.space(40)
    radius: Style.cornerRadius
    readonly property color typeColor: move ? root.typeColors[move.type] || root.steel : root.steel
    color: cardArea.containsMouse ? Qt.rgba(typeColor.r, typeColor.g, typeColor.b, 0.22)
                                  : Qt.rgba(typeColor.r, typeColor.g, typeColor.b, 0.10)
    border.width: 1
    border.color: selected ? (warn ? root.accent : root.gold) : Qt.rgba(typeColor.r, typeColor.g, typeColor.b, 0.45)

    Rectangle {
      id: typePill
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(60)
      height: Style.space(18)
      radius: height / 2
      color: card.typeColor
      Text {
        anchors.centerIn: parent
        text: card.move ? card.move.type.toUpperCase() : ""
        color: "white"
        font.family: Style.font.family
        font.pixelSize: Style.space(9)
        font.bold: true
      }
    }

    Column {
      anchors.left: typePill.right
      anchors.leftMargin: Style.space(10)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter

      Text {
        width: parent.width
        elide: Text.ElideRight
        text: card.move ? card.move.name : ""
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.space(12)
        font.bold: true
      }
      Caption {
        font.pixelSize: Style.space(10)
        text: !card.move ? ""
            : card.move.category + "  ·  Pow " + (card.move.power || "—") + "  ·  Acc " + (card.move.accuracy ? card.move.accuracy + "%" : "—")
              + "  ·  " + card.move.pp + " PP"
      }
    }

    MouseArea {
      id: cardArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: if (root.loaded) card.clicked()
    }
  }

  // ---- Bar button ----
  Item {
    id: button
    anchors.fill: parent

    PokeSprite {
      id: barSprite
      visible: root.hasPet
      anchors.centerIn: parent
      slug: root.hasPet ? root.pet.species : ""
      shiny: root.hasPet && root.pet.shiny
      fitWidth: 36
      fitHeight: root.barSize - 4
      opacity: root.partnerAway ? 0.45 : 1
    }

    ItemSprite {
      id: barBall
      visible: !root.hasPet
      anchors.centerIn: parent
      item: "poke-ball"
      scale_: (root.barSize - 6) / 30
    }

    Rectangle {
      visible: Pet.needsAttention(root.view, root.now)
      width: 5; height: 5; radius: 3
      color: root.accent
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 2
    }

    // A team is back with a report to read
    Rectangle {
      visible: root.expeditionNews
      width: 5; height: 5; radius: 3
      color: root.gold
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.margins: 2
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.toggle()
    }
  }

  // ---- Popup ----
  KeyboardPanel {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.opened
    focusTarget: root.mode === "picker" ? searchField : null
    contentWidth: popup.fittedContentWidth(Style.space(root.mode === "daycare" ? 560
                                                     : ["info", "box", "moves", "relearn", "tms", "expedition", "shop", "menu"].indexOf(root.mode) >= 0 ? 400
                                                     : root.mode === "bag" ? 340 : 300))
    contentHeight: popup.fittedContentHeight(content.implicitHeight)

    Column {
      id: content
      objectName: "pokemagotchi-popup"
      width: parent.width
      spacing: Style.space(10)

      // Header: title (opens the Pokédex), level / counters, shiny badge
      Item {
        width: parent.width
        height: Style.space(22)

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, headerInfo.x - Style.space(10))
          elide: Text.ElideRight
          text: (root.mode === "menu" ? "MENU"
               : root.mode === "shop" ? "SHOP"
               : root.mode === "picker" ? "POKÉDEX"
               : root.mode === "box" ? Pet.name(root.boxRoot).toUpperCase() + " BOX"
               : (root.mode === "moves" || root.mode === "relearn" || root.mode === "tms") && root.infoPet ? Pet.name(root.infoPet.species).toUpperCase()
               : root.mode === "bag" ? "BAG"
               : root.mode === "found" ? "EXPLORE"
               : root.mode === "encounter" ? Pet.name(root.wildSlug).toUpperCase()
               : root.mode === "daycare" ? "DAY CARE"
               : root.mode === "expedition" && root.followed ? Exp.title(root.followed).toUpperCase()
               : (root.mode === "info" || root.mode === "train") && root.infoPet ? Pet.name(root.infoPet.species).toUpperCase()
               : root.mode === "evolve" && root.evolvePet ? Pet.name(root.evolvePet.species).toUpperCase()
               : root.hasPet ? root.speciesName.toUpperCase() : "NO POKÉMON") + "  ▾"
          color: titleArea.containsMouse ? Color.popups.text : root.accent
          font.family: Style.font.family
          font.pixelSize: Style.space(15)
          font.bold: true
          font.letterSpacing: 2

          MouseArea {
            id: titleArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.busy) return
              if (root.mode === "menu") { root.home(); return }
              root.message = ""
              root.mode = "menu"
            }
          }
        }

        Text {
          id: headerInfo
          anchors.right: shinyChip.visible ? shinyChip.left : parent.right
          anchors.rightMargin: shinyChip.visible ? Style.space(10) : 0
          anchors.verticalCenter: parent.verticalCenter
          text: root.mode === "menu" || root.mode === "shop" ? "₽ " + Pet.money(root.view).toLocaleString(Qt.locale("en_US"), "f", 0)
              : root.mode === "picker" ? Pet.ownedCount(root.view) + " / " + Pet.familyTotal() + (Pet.hasCharm(root.view) ? "" : " caught")
              : root.mode === "box" ? Pet.familyCount(root.view, root.boxRoot) + " / " + Pet.BOX_SIZE
              : root.mode === "moves" ? "Moves"
              : root.mode === "relearn" ? "Move Reminder"
              : root.mode === "tms" ? "TMs"
              : root.mode === "bag" ? Pet.bagItems(root.view).length + (Pet.bagItems(root.view).length === 1 ? " item" : " items")
              : root.mode === "encounter" ? "Lv. " + root.wildLevel
              : root.mode === "found" ? ""
              : root.mode === "expedition" && root.followed ? Exp.DIFFICULTIES[root.followed.diff].name
                + (root.followed.status === "running" ? "  ·  B" + Exp.progress(root.followed, root.expClock).floor + "F / " + root.followed.floors : "")
              : root.mode === "daycare" ? (root.view.daycare || []).length + " / " + Pet.DAYCARE_SIZE + " Pokémon"
              : root.mode === "train" && root.trainPet ? (root.trainKind === "xp" ? "Lv. " + Pet.level(root.trainPet)
                                                       : "EVs " + Math.floor(Pet.evTotal(root.trainPet)) + " / " + Pet.EV_MAX_TOTAL)
              : root.mode === "evolve" && root.evolvePet ? "Lv. " + Pet.level(root.evolvePet)
              : root.mode === "info" && root.infoPet ? "No. " + Pet.entry(root.infoPet.species).number
              : root.hasPet ? "Lv. " + Pet.level(root.pet) : ""
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.space(13)
        }

        Rectangle {
          id: shinyChip
          readonly property bool shown: root.mode === "encounter" ? root.wildShiny
                                      : root.mode === "picker" ? Pet.hasCharm(root.view)
                                      : root.hasPet && root.pet.shiny && (root.mode === "pet" || root.mode === "confirm")
          visible: shown
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: shinyLabel.implicitWidth + Style.space(14)
          height: Style.space(22)
          radius: height / 2
          color: Qt.rgba(0.95, 0.72, 0.29, 0.22)
          border.width: 1
          border.color: root.gold

          Text {
            id: shinyLabel
            anchors.centerIn: parent
            text: root.mode === "picker" ? "✦ Charm" : "✦ Shiny"
            color: root.gold
            font.family: Style.font.family
            font.pixelSize: Style.space(11)
            font.bold: true
          }
        }
      }

      // ---- Menu: every place, like a phone's home screen ----
      Column {
        visible: root.mode === "menu"
        width: parent.width
        spacing: Style.space(10)

        Grid {
          id: menuGrid
          width: parent.width
          columns: 3
          spacing: Style.space(10)
          readonly property real tile: (width - spacing * 2) / 3

          Repeater {
            model: root.mode !== "menu" ? [] : [
              { id: "partner", label: root.hasPet ? root.speciesName : "Partner", pokemon: root.hasPet ? root.pet.species : "", tint: "#e23b44" },
              { id: "pokedex", label: "Pokédex", item: "poke-ball", tint: "#d0473f",
                badge: Pet.ownedCount(root.view) + "/" + Pet.familyTotal() },
              { id: "bag", label: "Bag", item: "sitrus-berry", tint: "#c8913a", badge: Pet.bagItems(root.view).length + "" },
              { id: "shop", label: "Shop", item: "nugget", tint: "#d8b13a", badge: "₽" + Pet.money(root.view) },
              { id: "daycare", label: "Day Care", pokemon: "chansey", tint: "#4f9a6a",
                badge: (root.view.daycare || []).length + "/" + Pet.DAYCARE_SIZE },
              { id: "training", label: "Training", image: "sprites/substitute.png", tint: "#8a6a4a",
                badge: root.trainees.length + "/" + Pet.TRAIN_SLOTS },
              { id: "expeditions", label: "Expeditions", item: "escape-rope", tint: "#4a86b8",
                badge: Exp.active(root.view).length + "/" + Exp.slots(root.view), news: root.expeditionNews },
              { id: "history", label: "Exp. history", glyph: "☰", tint: "#5a6aa8", badge: Exp.rank(root.view).name },
              { id: "summary", label: "Summary", glyph: "◉", tint: "#9a5aa8" },
              { id: "tower", label: "Battle Tower", item: "choice-band", tint: "#c0504d",
                badge: Tower.bp(root.view) + " BP", news: !!Tower.run(root.view) }
            ]

            delegate: Item {
              id: app
              required property var modelData
              width: menuGrid.tile
              height: menuGrid.tile * 0.86

              Rectangle {
                id: appIcon
                anchors.horizontalCenter: parent.horizontalCenter
                readonly property real side: Math.min(app.width - Style.space(16), app.height - Style.space(24))
                width: side
                height: side
                radius: width * 0.24
                readonly property color tint: app.modelData.tint
                color: appArea.pressed ? Qt.rgba(tint.r, tint.g, tint.b, 0.55)
                     : appArea.containsMouse ? Qt.rgba(tint.r, tint.g, tint.b, 0.42) : Qt.rgba(tint.r, tint.g, tint.b, 0.28)
                border.width: 1
                border.color: Qt.rgba(tint.r, tint.g, tint.b, appArea.containsMouse ? 0.9 : 0.5)
                scale: appArea.pressed ? 0.94 : 1
                Behavior on scale { NumberAnimation { duration: 90 } }

                PokeSprite {
                  visible: !!app.modelData.pokemon
                  anchors.centerIn: parent
                  slug: app.modelData.pokemon || ""
                  shiny: app.modelData.id === "partner" && root.hasPet && root.pet.shiny
                  fitWidth: parent.width - Style.space(10)
                  fitHeight: parent.height - Style.space(10)
                  maxPixel: 2
                }
                ItemSprite {
                  visible: !!app.modelData.item
                  anchors.centerIn: parent
                  item: app.modelData.item || ""
                  scale_: 2
                }
                Image {
                  visible: !!app.modelData.image
                  anchors.centerIn: parent
                  source: app.modelData.image ? Qt.resolvedUrl(app.modelData.image) : ""
                  smooth: false
                  width: implicitWidth * 1.3
                  height: implicitHeight * 1.3
                }
                Text {
                  visible: !!app.modelData.glyph
                  anchors.centerIn: parent
                  text: app.modelData.glyph || ""
                  color: "white"
                  font.pixelSize: parent.height * 0.42
                }

                // Small count in the corner, red dot for news
                Rectangle {
                  visible: !!app.modelData.badge
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  anchors.margins: -Style.space(4)
                  width: badgeText.implicitWidth + Style.space(8)
                  height: Style.space(16)
                  radius: height / 2
                  color: Qt.rgba(0, 0, 0, 0.7)
                  Text {
                    id: badgeText
                    anchors.centerIn: parent
                    text: app.modelData.badge || ""
                    color: "white"
                    font.family: Style.font.family
                    font.pixelSize: Style.space(9)
                  }
                }
                Rectangle {
                  visible: !!app.modelData.news
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: -Style.space(3)
                  width: Style.space(12); height: width; radius: width / 2
                  color: root.gold
                }
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: appIcon.bottom
                anchors.topMargin: Style.space(5)
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: app.modelData.label
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.space(11)
              }

              MouseArea {
                id: appArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openMenuItem(app.modelData.id)
              }
            }
          }
        }

        Text {
          visible: root.message !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
          text: root.message
          color: root.gold
          font.family: Style.font.family
          font.pixelSize: Style.space(11)
        }
      }

      // ---- Shop ----
      Column {
        id: shop
        visible: root.mode === "shop"
        width: parent.width
        spacing: Style.space(8)
        readonly property var shelves: root.mode === "shop" ? Pet.shopStock(root.now) : []
        readonly property bool selling: root.shopTab === "sell"
        readonly property var items: !visible ? [] : selling ? Pet.sellable(root.view)
                                   : shelves.length ? shelves[root.shopShelf].items : []
        readonly property int unit: !root.shopItem ? 0 : selling ? Pet.sellPrice(root.shopItem) : Pet.price(root.shopItem)
        readonly property int maxQty: !root.shopItem ? 1 : selling ? (root.view.bag[root.shopItem] || 0)
                                    : Math.max(1, Math.floor(Pet.money(root.view) / Math.max(1, unit)))

        Row {
          width: parent.width
          spacing: Style.space(8)
          readonly property real half: (width - spacing) / 2
          PetButton { width: parent.half; highlight: !shop.selling; label: "Buy"; onClicked: { root.shopTab = "buy"; root.shopItem = ""; root.message = "" } }
          PetButton { width: parent.half; highlight: shop.selling; label: "Sell"; onClicked: { root.shopTab = "sell"; root.shopItem = ""; root.message = "" } }
        }

        Row {
          visible: !shop.selling
          spacing: Style.space(6)
          Repeater {
            model: shop.shelves
            delegate: Rectangle {
              required property var modelData
              required property int index
              readonly property bool selected: root.shopShelf === index
              width: shelfLabel.implicitWidth + Style.space(16)
              height: Style.space(24)
              radius: height / 2
              color: selected ? Qt.rgba(0.95, 0.72, 0.29, 0.2) : shelfArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
              border.width: 1
              border.color: selected ? root.gold : Qt.rgba(1, 1, 1, 0.15)
              Text {
                id: shelfLabel
                anchors.centerIn: parent
                text: modelData.name
                color: parent.selected ? root.gold : Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.space(11)
              }
              MouseArea { id: shelfArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                          onClicked: { root.shopShelf = index; root.shopItem = "" } }
            }
          }
        }

        Caption {
          visible: shop.selling && shop.items.length === 0
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "Nothing to sell."
        }

        GridView {
          id: shopGrid
          width: parent.width
          height: count === 0 ? 0 : Math.min(Style.space(250), Math.ceil(count / 5) * cellHeight)
          clip: true
          cellWidth: width / 5
          cellHeight: Style.space(78)
          boundsBehavior: Flickable.StopAtBounds
          model: shop.items

          delegate: Item {
            required property string modelData
            width: shopGrid.cellWidth
            height: shopGrid.cellHeight
            Rectangle {
              anchors.fill: parent
              anchors.margins: Style.space(3)
              radius: Style.cornerRadius
              color: shopArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0.29, 0.53, 0.72, 0.08)
              border.width: root.shopItem === modelData ? 1 : 0
              border.color: root.gold
              ItemSprite { anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top; anchors.topMargin: Style.space(3); item: modelData; scale_: 1.3 }
              Text {
                visible: (root.view.bag[modelData] || 0) > 0
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: Style.space(3)
                text: "×" + root.view.bag[modelData]
                color: Color.popups.text
                opacity: 0.6
                font.family: Style.font.family
                font.pixelSize: Style.space(8)
              }
              Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(3)
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: shopGrid.cellWidth - Style.space(8)
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                  text: Pet.itemName(modelData)
                  color: Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.space(9)
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "₽" + (shop.selling ? Pet.sellPrice(modelData) : Pet.price(modelData))
                  color: shop.selling || Pet.money(root.view) >= Pet.price(modelData) ? root.gold : root.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.space(10)
                  font.bold: true
                }
              }
              MouseArea { id: shopArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.pickShopItem(modelData) }
            }
          }
        }

        // The selected item, how many, and the deal
        Rectangle {
          visible: root.shopItem !== ""
          width: parent.width
          height: dealColumn.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          color: Qt.rgba(1, 1, 1, 0.04)
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.10)

          Column {
            id: dealColumn
            anchors.fill: parent
            anchors.margins: Style.space(8)
            spacing: Style.space(6)
            Row {
              spacing: Style.space(8)
              ItemSprite { item: root.shopItem; scale_: 1 }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.shopItem ? Pet.itemName(root.shopItem) + "   (in bag: " + (root.view.bag[root.shopItem] || 0) + ")" : ""
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.space(12)
                font.bold: true
              }
            }
            Caption { width: parent.width; wrapMode: Text.WordWrap; text: root.shopItem ? Pet.itemText(root.shopItem) : "" }
            Row {
              spacing: Style.space(6)
              PetButton { width: Style.space(30); label: "−"; onClicked: root.shopQty = Math.max(1, root.shopQty - 1) }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(34)
                horizontalAlignment: Text.AlignHCenter
                text: "×" + root.shopQty
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.space(13)
                font.bold: true
              }
              PetButton { width: Style.space(30); label: "+"; onClicked: root.shopQty = Math.min(Math.max(1, shop.maxQty), root.shopQty + 1) }
              PetButton { width: Style.space(40); label: "×10"; onClicked: root.shopQty = Math.min(Math.max(1, shop.maxQty), root.shopQty + 10) }
              PetButton {
                width: dealColumn.width - Style.space(30 + 34 + 30 + 40 + 24)
                highlight: true
                enabledLook: shop.selling || Pet.money(root.view) >= shop.unit * root.shopQty
                label: (shop.selling ? "Sell for ₽" : "Buy for ₽") + shop.unit * root.shopQty
                onClicked: root.shopDeal()
              }
            }
          }
        }

        Text {
          visible: root.message !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
          text: root.message
          color: root.gold
          font.family: Style.font.family
          font.pixelSize: Style.space(11)
        }

        Caption {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: shop.selling ? "The shop buys items back at half price."
              : "Earn Poké Dollars on expeditions. Mints and rare evolution items change every day."
        }

        PetButton { width: parent.width; label: "Back"; onClicked: root.home() }
      }

      // ---- Pokédex ----
      Column {
        visible: root.mode === "picker"
        width: parent.width
        spacing: Style.space(8)

        Row {
          width: parent.width
          spacing: Style.space(8)

          TextField {
            id: searchField
            width: parent.width - filterToggle.width - parent.spacing
            placeholderText: "Search a Pokémon…"
            text: root.query
            font.family: Style.font.family
            onTextChanged: root.query = text
            Keys.onEscapePressed: root.home()
            Keys.onReturnPressed: if (pickerGrid.count > 0) root.openBox(pickerGrid.model[0])
          }

          // All families in Dex order, or only the caught ones (still in Dex order)
          Rectangle {
            id: filterToggle
            width: filterRow.implicitWidth
            height: searchField.height
            radius: Style.cornerRadius
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.18)
            clip: true

            Row {
              id: filterRow
              anchors.fill: parent

              Repeater {
                model: [ { label: "All", caught: false }, { label: "Caught", caught: true } ]

                delegate: Rectangle {
                  required property var modelData
                  readonly property bool selected: root.caughtOnly === modelData.caught
                  width: segLabel.implicitWidth + Style.space(16)
                  height: filterRow.height
                  color: selected ? Qt.rgba(0.89, 0.23, 0.27, 0.22)
                       : segArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                  Text {
                    id: segLabel
                    anchors.centerIn: parent
                    text: modelData.label
                    color: selected ? root.accent : Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Style.space(11)
                  }

                  MouseArea {
                    id: segArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.caughtOnly = modelData.caught
                      pickerGrid.positionViewAtBeginning()
                      searchField.forceActiveFocus()
                    }
                  }
                }
              }
            }
          }
        }

        GridView {
          id: pickerGrid
          width: parent.width
          height: Style.space(340)
          clip: true
          cellWidth: width / 3
          cellHeight: Style.space(88)
          boundsBehavior: Flickable.StopAtBounds
          model: root.mode !== "picker" ? []
               : Pet.searchFamilies(root.query).filter(function(f) { return !root.caughtOnly || !!root.view.pets[f] })

          delegate: Item {
            id: tile
            required property string modelData
            readonly property var saved: Pet.peek(root.view, modelData)
            readonly property var seen: saved ? [] : Pet.seenMembers(root.view, modelData)
            readonly property bool known: !!saved || seen.length > 0
            readonly property string slug: saved ? saved.species : seen.length ? seen[seen.length - 1] : modelData
            readonly property bool current: modelData === root.view.current
            readonly property int count: saved ? Pet.familyCount(root.view, modelData) : 0
            readonly property bool hunted: !!root.view.navdex && Pet.family(root.view.navdex) === modelData
            width: pickerGrid.cellWidth
            height: pickerGrid.cellHeight

            Rectangle {
              anchors.fill: parent
              anchors.margins: Style.space(3)
              radius: Style.cornerRadius
              color: tileArea.containsMouse && tile.known ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0.29, 0.53, 0.72, 0.08)
              border.width: tile.current || tile.hunted ? 1 : 0
              border.color: tile.current ? root.accent : root.gold

              PokeSprite {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Style.space(4) + (Style.space(50) - height) / 2
                slug: tile.slug
                shiny: tile.saved ? tile.saved.shiny : false
                silhouette: !tile.known
                opacity: tile.saved ? 1 : tile.known ? 0.45 : 0.85
                fitWidth: parent.width - 8
                fitHeight: Style.space(50)
                maxPixel: 2
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(5)
                width: parent.width - 6
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: tile.known ? Pet.name(tile.slug) : "???"
                color: tile.current ? root.accent : Color.popups.text
                opacity: tile.saved ? 1 : 0.4
                font.family: Style.font.family
                font.pixelSize: Style.space(10)
              }

              Text {
                visible: !!tile.saved
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(4)
                text: tile.saved ? "Lv." + Pet.level(tile.saved) : ""
                color: Color.popups.text
                opacity: 0.6
                font.family: Style.font.family
                font.pixelSize: Style.space(9)
              }

              Text {
                visible: tile.count > 1 || tile.hunted
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: Style.space(4)
                text: (tile.hunted ? "◎ " : "") + (tile.count > 1 ? "×" + tile.count : "")
                color: root.gold
                font.family: Style.font.family
                font.pixelSize: Style.space(9)
                font.bold: true
              }

              MouseArea {
                id: tileArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: tile.known ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: if (root.loaded && tile.known) root.openBox(tile.modelData)
              }
            }
          }
        }
      }

      // ---- Box: every Pokémon of a family, and its Nav-Dex ----
      Column {
        id: boxView
        visible: root.mode === "box"
        width: parent.width
        spacing: Style.space(8)
        readonly property var refs: root.mode === "box" ? Pet.familyRefs(root.view, root.boxRoot) : []

        Caption {
          visible: boxView.refs.length === 0
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: "You haven't caught any yet. Turn the Nav-Dex on below to go looking for one!"
        }

        GridView {
          id: boxGrid
          visible: count > 0
          width: parent.width
          height: Math.min(Style.space(282), Math.ceil(count / 5) * cellHeight)
          clip: true
          cellWidth: width / 5
          cellHeight: Style.space(94)
          boundsBehavior: Flickable.StopAtBounds
          model: boxView.refs

          delegate: Item {
            id: boxTile
            required property string modelData
            required property int index
            readonly property var saved: Pet.specimen(root.view, modelData)
            readonly property bool lead: index === 0
            readonly property bool partner: lead && Pet.refRoot(modelData) === root.view.current
            width: boxGrid.cellWidth
            height: boxGrid.cellHeight

            Rectangle {
              anchors.fill: parent
              anchors.margins: Style.space(3)
              radius: Style.cornerRadius
              color: boxTileArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08)
                   : boxTile.lead ? Qt.rgba(0.50, 0.75, 0.60, 0.12) : Qt.rgba(0.29, 0.53, 0.72, 0.08)
              border.width: boxTile.partner ? 1 : 0
              border.color: root.accent

              PokeSprite {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Style.space(8) + (Style.space(42) - height) / 2
                slug: boxTile.saved ? boxTile.saved.species : ""
                shiny: !!boxTile.saved && boxTile.saved.shiny
                fitWidth: parent.width - 8
                fitHeight: Style.space(42)
                maxPixel: 2
              }

              Text {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: Style.space(4)
                text: boxTile.partner ? "★" : boxTile.lead ? "⌂" : ""
                color: boxTile.partner ? root.accent : root.good
                font.pixelSize: Style.space(10)
              }

              Text {
                visible: !!boxTile.saved && boxTile.saved.shiny
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(4)
                text: "✦"
                color: root.gold
                font.pixelSize: Style.space(10)
              }

              Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(3)

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: boxTile.saved ? "Lv." + Pet.level(boxTile.saved) : ""
                  color: Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.space(10)
                }
                Caption {
                  anchors.horizontalCenter: parent.horizontalCenter
                  font.pixelSize: Style.space(9)
                  text: boxTile.saved ? "IV " + Pet.ivTotal(boxTile.saved) : ""
                  color: boxTile.saved && Pet.ivTotal(boxTile.saved) >= 150 ? root.good : Color.popups.text
                }
              }

              MouseArea {
                id: boxTileArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.showInfo(boxTile.modelData, "box")
              }
            }
          }
        }

        Caption {
          visible: boxView.refs.length > 0
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: "⌂ is the family's lead: it can be your partner, play at the Day Care or go on expeditions. The others rest in the box. Click one to see its summary."
        }

        // Nav-Dex: lock wild encounters on one species of this family
        Rectangle {
          width: parent.width
          height: navColumn.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          color: Qt.rgba(1, 1, 1, 0.04)
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.10)

          Column {
            id: navColumn
            anchors.fill: parent
            anchors.margins: Style.space(8)
            spacing: Style.space(6)

            Text {
              text: "◎ NAV-DEX"
              color: root.gold
              font.family: Style.font.family
              font.pixelSize: Style.space(12)
              font.bold: true
              font.letterSpacing: 1
            }

            Caption {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "Pick a species you've seen: every wild encounter will be that Pokémon, so you can hunt a better one or a shiny ("
                    + Pet.oddsText(root.view) + (Pet.hasCharm(root.view) ? " with the Shiny Charm" : "") + ")."
            }

            Flow {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.mode === "box" ? Pet.familyMembers(root.boxRoot) : []

                delegate: Rectangle {
                  id: navChip
                  required property string modelData
                  readonly property bool seen: Pet.isSeen(root.view, modelData)
                  readonly property bool active: root.view.navdex === modelData
                  width: Style.space(64)
                  height: Style.space(64)
                  radius: Style.cornerRadius
                  color: active ? Qt.rgba(0.95, 0.72, 0.29, 0.18)
                       : navArea.containsMouse && seen ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0.29, 0.53, 0.72, 0.08)
                  border.width: active ? 1 : 0
                  border.color: root.gold
                  opacity: seen ? 1 : 0.5

                  PokeSprite {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: Style.space(3)
                    slug: navChip.modelData
                    silhouette: !navChip.seen
                    fitWidth: parent.width - 8
                    fitHeight: Style.space(40)
                    maxPixel: 2
                  }

                  Caption {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Style.space(3)
                    width: parent.width - 4
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    font.pixelSize: Style.space(9)
                    text: navChip.seen ? Pet.name(navChip.modelData) : "???"
                  }

                  MouseArea {
                    id: navArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: navChip.seen ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (navChip.seen) root.toggleNavdex(navChip.modelData)
                  }
                }
              }
            }

            Caption {
              width: parent.width
              wrapMode: Text.WordWrap
              color: root.view.navdex ? root.gold : Color.popups.text
              opacity: root.view.navdex ? 1 : 0.7
              text: !root.view.navdex ? "Nav-Dex off: wild Pokémon are random."
                  : "Hunting " + Pet.name(root.view.navdex) + ". Click it again to stop."
            }
          }
        }

        Text {
          visible: root.message !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
          text: root.message
          color: root.gold
          font.family: Style.font.family
          font.pixelSize: Style.space(11)
        }

        PetButton { width: parent.width; label: "Back to the Pokédex"; onClicked: { root.message = ""; root.mode = "picker" } }
      }

      // ---- Summary (Pokédex page) ----
      Column {
        id: summary
        visible: root.mode === "info" && !!root.infoPet
        width: parent.width
        spacing: Style.space(10)

        readonly property var p: root.infoPet
        readonly property var dex: p ? Pet.entry(p.species) : null
        readonly property string ability: p ? Pet.abilityOf(p.species, p.ability) : ""

        Row {
          width: parent.width
          spacing: Style.space(12)

          Rectangle {
            width: Style.space(104)
            height: Style.space(104)
            radius: Style.cornerRadius
            color: Qt.rgba(0.29, 0.53, 0.72, 0.10)

            PokeSprite {
              anchors.centerIn: parent
              slug: summary.p ? summary.p.species : ""
              shiny: summary.p ? summary.p.shiny : false
              fitWidth: parent.width - 8
              fitHeight: parent.height - 8
              maxPixel: 3
              integerScale: true
            }

            Text {
              visible: summary.p && summary.p.shiny
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 4
              text: "✦"
              color: root.gold
              font.pixelSize: Style.space(12)
            }
          }

          Column {
            width: parent.width - Style.space(116)
            spacing: Style.space(5)

            Text {
              text: summary.dex ? summary.dex.genus : ""
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.space(12)
              font.bold: true
            }

            Row {
              spacing: Style.space(4)
              Repeater {
                model: summary.dex ? summary.dex.types : []
                delegate: Rectangle {
                  required property string modelData
                  width: typeLabel.implicitWidth + Style.space(12)
                  height: Style.space(18)
                  radius: height / 2
                  color: root.typeColors[modelData] || root.steel
                  Text {
                    id: typeLabel
                    anchors.centerIn: parent
                    text: modelData.toUpperCase()
                    color: "white"
                    font.family: Style.font.family
                    font.pixelSize: Style.space(9)
                    font.bold: true
                  }
                }
              }
            }

            Caption { text: summary.dex ? summary.dex.height + "  ·  " + summary.dex.weight : "" }
            Caption { text: summary.p ? "Lv. " + Pet.level(summary.p) + "  ·  " + Pet.natureName(summary.p.nature) + " nature" : "" }
            Caption {
              text: root.infoBoxed ? "In the box"
                  : root.infoRef === root.view.current ? "★ Your partner"
                  : Pet.isAway(root.view, root.infoRef) ? "⛰ On an expedition"
                  : Pet.inDaycare(root.view, root.infoRef) ? "⌂ At the Day Care (+" + Pet.DAYCARE_XP + " XP/h)" : "Resting (no XP)"
            }
            Text {
              width: parent.width
              elide: Text.ElideRight
              text: summary.p ? Pet.abilityName(summary.ability) + (summary.p.ability && summary.p.ability.hidden ? "  (hidden)" : "") : ""
              color: root.gold
              font.family: Style.font.family
              font.pixelSize: Style.space(11)
              font.bold: true
            }
          }
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: summary.dex ? summary.dex.text : ""
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.space(11)
          font.italic: true
        }

        Caption {
          width: parent.width
          wrapMode: Text.WordWrap
          text: summary.ability ? Pet.abilityName(summary.ability) + ": " + Pet.abilityText(summary.ability) : ""
        }

        Column {
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: summary.p ? Pet.stats(summary.p) : []

            delegate: Item {
              required property var modelData
              width: summary.width
              height: Style.space(16)

              Text {
                id: statLabel
                width: Style.space(62)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label + (modelData.up ? " ▲" : modelData.down ? " ▼" : "")
                color: modelData.up ? root.accent : modelData.down ? root.steel : Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.space(10)
              }

              Text {
                id: statValue
                anchors.left: statLabel.right
                width: Style.space(30)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: modelData.value
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.space(11)
                font.bold: true
              }

              Rectangle {
                anchors.left: statValue.right
                anchors.leftMargin: Style.space(8)
                anchors.right: ivLabel.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.08)

                Rectangle {
                  width: parent.width * Math.min(1, modelData.base / 180)
                  height: parent.height
                  radius: parent.radius
                  color: modelData.base >= 100 ? root.good : modelData.base >= 60 ? root.gold : root.accent
                }
              }

              Text {
                id: ivLabel
                anchors.right: evLabel.left
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(44)
                horizontalAlignment: Text.AlignRight
                text: "IV " + modelData.iv
                color: modelData.iv === 31 ? root.good : modelData.iv === 0 ? root.accent : Color.popups.text
                opacity: modelData.iv === 31 || modelData.iv === 0 ? 1 : 0.7
                font.family: Style.font.family
                font.pixelSize: Style.space(10)
                font.bold: modelData.iv === 31 || modelData.iv === 0
              }

              Text {
                id: evLabel
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(52)
                horizontalAlignment: Text.AlignRight
                text: "EV " + modelData.ev
                color: modelData.ev >= 252 ? root.gold : Color.popups.text
                opacity: modelData.ev > 0 ? 1 : 0.45
                font.family: Style.font.family
                font.pixelSize: Style.space(10)
              }
            }
          }
        }

        Caption {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: summary.p && summary.dex ? "Base stats " + summary.dex.baseTotal + "  ·  IVs " + Pet.ivTotal(summary.p) + " / 186"
                            + "  ·  EVs " + Math.floor(Pet.evTotal(summary.p)) + " / " + Pet.EV_MAX_TOTAL : ""
        }

        Caption {
          visible: !!summary.p && (!!summary.p.training || !!Pet.boostLeft(summary.p, root.now))
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          color: root.gold
          opacity: 1
          text: !summary.p ? "" : [
            summary.p.training ? Pet.trainingText(summary.p) + " · " + Pet.trainingLeft(summary.p) + " left" : "",
            Pet.boostLeft(summary.p, root.now) ? "XP ×" + summary.p.boost.mult + " · " + Pet.boostLeft(summary.p, root.now) + " left" : ""
          ].filter(function(x) { return x }).join("   ·   ")
        }

        Text {
          visible: root.message !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
          text: root.message
          color: root.gold
          font.family: Style.font.family
          font.pixelSize: Style.space(11)
        }

        Row {
          id: summaryTools
          width: parent.width
          spacing: Style.space(8)
          readonly property bool evolvable: !!summary.p && Pet.canEvolve(root.view, root.now, root.infoRef)
          readonly property int count: 1 + (evolvable ? 1 : 0) + (root.infoBoxed ? 0 : 1)
          readonly property real cell: (width - spacing * (count - 1)) / count

          PetButton {
            visible: summaryTools.evolvable
            width: summaryTools.cell
            highlight: true
            label: "✦ Evolve"
            onClicked: root.openEvolve(root.infoRef)
          }
          PetButton {
            visible: !root.infoBoxed
            width: summaryTools.cell
            label: summary.p && summary.p.training ? "Training…" : "Train"
            onClicked: root.openTraining()
          }
          PetButton {
            width: summaryTools.cell
            label: "Moves"
            onClicked: root.openMoves()
          }
        }

        Row {
          id: summaryButtons
          width: parent.width
          spacing: Style.space(8)
          readonly property bool partner: root.infoRef === root.view.current
          readonly property int count: root.infoBoxed ? 3 : partner ? 1 : 3
          readonly property real cell: (width - spacing * (count - 1)) / count

          PetButton {
            width: summaryButtons.cell
            label: "Back"
            onClicked: root.leaveInfo()
          }
          PetButton {
            visible: !root.infoBoxed && !summaryButtons.partner
            width: summaryButtons.cell
            highlight: true
            label: "Make partner"
            onClicked: root.makePartner(root.infoRef)
          }
          PetButton {
            visible: !root.infoBoxed && !summaryButtons.partner
            width: summaryButtons.cell
            readonly property bool inside: Pet.inDaycare(root.view, root.infoRef)
            label: inside ? "Leave Day Care" : "⌂ Day Care"
            onClicked: root.toggleDaycare(root.infoRef)
          }
          PetButton {
            visible: root.infoBoxed
            width: summaryButtons.cell
            highlight: true
            label: "Make it lead"
            onClicked: root.sendToDayCare(root.infoRef)
          }
          PetButton {
            visible: root.infoBoxed
            width: summaryButtons.cell
            danger: true
            label: root.releaseArmed ? "Sure? Release" : "Release"
            onClicked: root.releaseBoxed(root.infoRef)
          }
        }

        Caption {
          visible: root.infoBoxed
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: "Boxed Pokémon rest: no XP or training. Make it the lead to swap it with "
                + (Pet.specimen(root.view, Pet.refRoot(root.infoRef)) ? Pet.name(Pet.specimen(root.view, Pet.refRoot(root.infoRef)).species) : "the one there")
                + (Pet.refRoot(root.infoRef) === root.view.current ? ", your partner." : ".")
        }
      }

      // ---- Moves: the four it knows, and the Move Reminder ----
      Column {
        id: movesView
        visible: (root.mode === "moves" || root.mode === "relearn" || root.mode === "tms") && !!root.infoPet
        width: parent.width
        spacing: Style.space(6)
        readonly property var known: movesView.visible ? Pet.moves(root.infoPet) : []
        readonly property var others: movesView.visible ? Pet.relearnable(root.infoPet) : []
        readonly property var tms: movesView.visible ? Pet.tmsFor(root.view, root.infoPet) : []
        readonly property var detail: root.mode === "moves" && root.moveSlot >= 0 ? known[root.moveSlot] || null : null

        Caption {
          visible: root.mode === "moves" && root.relearnId > 0
          width: parent.width
          wrapMode: Text.WordWrap
          color: root.accent
          opacity: 1
          text: "Which move should " + (root.infoPet ? Pet.name(root.infoPet.species) : "") + " forget to learn "
                + Pet.moveName(root.relearnId) + "?"
        }

        Repeater {
          model: root.mode === "moves" ? movesView.known : []
          delegate: MoveCard {
            required property var modelData
            required property int index
            width: movesView.width
            move: modelData
            selected: root.relearnId > 0 || root.moveSlot === index
            warn: root.relearnId > 0
            onClicked: {
              if (root.relearnId > 0) root.teach(root.relearnId, index)
              else root.moveSlot = root.moveSlot === index ? -1 : index
            }
          }
        }

        Caption {
          visible: root.mode === "moves" && movesView.known.length === 0
          text: "It doesn't know any move yet."
        }

        Caption {
          visible: !!movesView.detail
          width: parent.width
          wrapMode: Text.WordWrap
          font.italic: true
          text: movesView.detail ? movesView.detail.text : ""
        }

        Caption {
          visible: root.mode === "relearn"
          width: parent.width
          wrapMode: Text.WordWrap
          text: movesView.others.length
            ? "Pick a move it can remember. It learns new moves by leveling up and forgets its oldest past four."
            : "There's no other move it can remember right now."
        }

        Flickable {
          visible: root.mode === "relearn"
          width: parent.width
          height: Math.min(contentHeight, Style.space(300))
          contentHeight: relearnColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: relearnColumn
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.mode === "relearn" ? movesView.others : []
              delegate: MoveCard {
                required property var modelData
                width: relearnColumn.width
                move: modelData
                onClicked: root.pickRelearn(modelData.id)
              }
            }
          }
        }

        Caption {
          visible: root.mode === "tms"
          width: parent.width
          wrapMode: Text.WordWrap
          text: movesView.tms.length
            ? "Pick a TM from your bag. It's used up, but the move stays at the Move Reminder."
            : "None of your TMs can teach it something new. TMs turn up in searches, on expeditions and at the shop."
        }

        Flickable {
          visible: root.mode === "tms"
          width: parent.width
          height: Math.min(contentHeight, Style.space(300))
          contentHeight: tmColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: tmColumn
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.mode === "tms" ? movesView.tms : []
              delegate: Item {
                required property var modelData
                width: tmColumn.width
                height: tmCard.height
                MoveCard {
                  id: tmCard
                  width: parent.width - tmTag.width - Style.space(6)
                  move: Pet.move(Pet.tmMove(modelData))
                  onClicked: root.pickTm(modelData)
                }
                Text {
                  id: tmTag
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(58)
                  horizontalAlignment: Text.AlignRight
                  text: modelData.toUpperCase() + "\n×" + (root.view.bag[modelData] || 0)
                  color: Color.popups.text
                  opacity: 0.7
                  font.family: Style.font.family
                  font.pixelSize: Style.space(10)
                }
              }
            }
          }
        }

        Text {
          visible: root.message !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
          text: root.message
          color: root.gold
          font.family: Style.font.family
          font.pixelSize: Style.space(11)
        }

        Row {
          id: movesButtons
          width: parent.width
          spacing: Style.space(8)
          readonly property real third: (width - spacing * 2) / 3
          readonly property bool picking: root.mode === "relearn" || root.mode === "tms" || root.relearnId > 0

          PetButton {
            width: movesButtons.third
            label: movesButtons.picking ? "Cancel" : "Summary"
            onClicked: {
              if (movesButtons.picking) root.openMoves()
              else root.showInfo(root.infoRef, root.infoBack)
            }
          }
          PetButton {
            width: movesButtons.third
            highlight: root.mode === "moves"
            enabledLook: root.mode === "moves" && root.relearnId === 0
            label: "Move Reminder"
            onClicked: if (root.mode === "moves" && root.relearnId === 0) { root.message = ""; root.mode = "relearn" }
          }
          PetButton {
            width: movesButtons.third
            highlight: root.mode === "moves" && movesView.tms.length > 0
            enabledLook: root.mode === "moves" && root.relearnId === 0
            label: "TMs" + (movesView.tms.length ? " (" + movesView.tms.length + ")" : "")
            onClicked: if (root.mode === "moves" && root.relearnId === 0) { root.message = ""; root.mode = "tms" }
          }
        }
      }

      // ---- Day Care: your Pokémon wander around ----
      Column {
        visible: root.mode === "daycare"
        width: parent.width
        spacing: Style.space(8)

        Rectangle {
          id: field
          width: parent.width
          height: Style.space(230)
          radius: Style.cornerRadius
          clip: true
          gradient: Gradient {
            GradientStop { position: 0.0; color: "#1d3a2a" }
            GradientStop { position: 1.0; color: "#2c5a36" }
          }

          // A few tufts of grass
          Repeater {
            model: 14
            delegate: Text {
              required property int index
              x: (index * 97 % 13) / 13 * (field.width - 20)
              y: 20 + (index * 53 % 11) / 11 * (field.height - 40)
              text: "ʷ"
              color: "#3f7a4a"
              font.pixelSize: Style.space(16)
            }
          }

          Repeater {
            model: root.mode === "daycare" ? root.daycareWalkers : []

            delegate: Item {
              id: walker
              required property string modelData
              readonly property var saved: root.view.pets[modelData]
              property bool ready: false
              property bool facingRight: false
              property bool moving: false
              property int moveDuration: 1500
              // Trainees stay put next to a Substitute doll and hit it
              readonly property bool training: !!saved && !!saved.training
              readonly property real dollRoom: Style.space(40)
              width: walkerSprite.width
              height: walkerSprite.height
              z: y + height
              // Position as a fraction of the field, so they spread out once the popup has widened
              property real fx: Math.random()
              property real fy: Math.random()
              readonly property real minX: training ? dollRoom : 0
              x: minX + fx * Math.max(0, field.width - width - minX)
              y: fy * Math.max(0, field.height - height)

              Behavior on x { enabled: walker.ready; NumberAnimation { duration: walker.moveDuration; easing.type: Easing.InOutSine } }
              Behavior on y { enabled: walker.ready; NumberAnimation { duration: walker.moveDuration; easing.type: Easing.InOutSine } }

              function wander() {
                if (training) return
                var nfx = Math.random(), nfy = Math.random()
                var dx = (nfx - fx) * field.width, dy = (nfy - fy) * field.height
                facingRight = nfx > fx
                moveDuration = Math.max(400, Math.sqrt(dx * dx + dy * dy) / 45 * 1000)
                moving = true
                stopTimer.interval = moveDuration
                stopTimer.restart()
                fx = nfx
                fy = nfy
                wanderTimer.interval = moveDuration + 800 + Math.random() * 3500
              }

              onTrainingChanged: if (training) facingRight = false

              Component.onCompleted: Qt.callLater(function() { walker.ready = true })

              Timer {
                id: wanderTimer
                running: root.mode === "daycare" && root.opened && !walker.training
                repeat: true
                interval: 500 + Math.random() * 2500
                onTriggered: walker.wander()
              }

              Timer { id: stopTimer; onTriggered: walker.moving = false }

              PokeSprite {
                id: walkerSprite
                slug: walker.saved ? walker.saved.species : ""
                shiny: walker.saved ? walker.saved.shiny : false
                fitWidth: Style.space(76)
                fitHeight: Style.space(62)
                maxPixel: 3
                x: lunge
                y: hopY
                property real hopY: 0
                property real lunge: 0
                transform: Scale { origin.x: walkerSprite.width / 2; xScale: walker.facingRight ? -1 : 1 }

                SequentialAnimation on hopY {
                  running: walker.moving
                  loops: Animation.Infinite
                  NumberAnimation { to: -3; duration: 140 }
                  NumberAnimation { to: 0; duration: 140 }
                  onRunningChanged: if (!running) walkerSprite.hopY = 0
                }
              }

              Image {
                id: walkerDoll
                visible: walker.training
                source: Qt.resolvedUrl("sprites/substitute.png")
                smooth: false
                width: implicitWidth * 1.2
                height: implicitHeight * 1.2
                x: -width + Style.space(2) + shift
                anchors.bottom: walkerSprite.bottom
                property real shift: 0
              }

              SequentialAnimation {
                running: walker.training && root.mode === "daycare" && root.opened
                loops: Animation.Infinite
                onRunningChanged: if (!running) { walkerSprite.lunge = 0; walkerDoll.shift = 0 }
                PauseAnimation { duration: 400 + Math.random() * 600 }
                NumberAnimation { target: walkerSprite; property: "lunge"; to: -Style.space(14); duration: 140; easing.type: Easing.InQuad }
                ParallelAnimation {
                  NumberAnimation { target: walkerSprite; property: "lunge"; to: 0; duration: 220; easing.type: Easing.OutQuad }
                  SequentialAnimation {
                    NumberAnimation { target: walkerDoll; property: "shift"; to: -4; duration: 60 }
                    NumberAnimation { target: walkerDoll; property: "shift"; to: 3; duration: 60 }
                    NumberAnimation { target: walkerDoll; property: "shift"; to: 0; duration: 60 }
                  }
                }
              }

              Rectangle {
                visible: walkerArea.containsMouse || walker.modelData === root.view.current
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.top
                width: walkerName.implicitWidth + 10
                height: walkerName.implicitHeight + 4
                radius: height / 2
                color: Qt.rgba(0, 0, 0, 0.55)

                Text {
                  id: walkerName
                  anchors.centerIn: parent
                  text: (walker.modelData === root.view.current ? "★ " : "")
                        + (walker.saved ? Pet.name(walker.saved.species) + " " + Pet.level(walker.saved) : "")
                  color: "white"
                  font.family: Style.font.family
                  font.pixelSize: Style.space(9)
                }
              }

              MouseArea {
                id: walkerArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.showInfo(walker.modelData, "daycare")
              }
            }
          }
        }

        Caption {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: "Up to " + Pet.DAYCARE_SIZE + " Pokémon play here and earn " + Pet.DAYCARE_XP + " XP per hour each; the others rest without XP. "
                + "Click a Pokémon below to send it or take it back."
        }

        // Everyone you can send (your partner earns XP with you)
        GridView {
          id: careGrid
          width: parent.width
          height: Style.space(196)
          clip: true
          cellWidth: width / 8
          cellHeight: Style.space(66)
          boundsBehavior: Flickable.StopAtBounds
          model: root.mode === "daycare" ? root.ownedRoots.filter(function(r) { return r !== root.view.current })
                                                .sort(function(a, b) { return Pet.inDaycare(root.view, b) - Pet.inDaycare(root.view, a) }) : []

          delegate: Item {
            id: careTile
            required property string modelData
            readonly property var saved: root.view.pets[modelData]
            readonly property bool inside: Pet.inDaycare(root.view, modelData)
            readonly property bool away: Pet.isAway(root.view, modelData)
            width: careGrid.cellWidth
            height: careGrid.cellHeight

            Rectangle {
              anchors.fill: parent
              anchors.margins: Style.space(2)
              radius: Style.cornerRadius
              color: careArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08)
                   : careTile.inside ? Qt.rgba(0.50, 0.75, 0.60, 0.16) : Qt.rgba(0.29, 0.53, 0.72, 0.06)
              border.width: careTile.inside ? 1 : 0
              border.color: root.good
              opacity: careTile.inside ? 1 : 0.6

              PokeSprite {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Style.space(3)
                slug: careTile.saved ? careTile.saved.species : ""
                shiny: !!careTile.saved && careTile.saved.shiny
                fitWidth: parent.width - 6
                fitHeight: Style.space(38)
                maxPixel: 2
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(2)
                text: careTile.away ? "⛰ away" : careTile.saved ? "Lv." + Pet.level(careTile.saved) : ""
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.space(9)
              }
              Text {
                visible: careTile.inside
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(3)
                text: "⌂"
                color: root.good
                font.pixelSize: Style.space(10)
              }
              MouseArea {
                id: careArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleDaycare(careTile.modelData)
              }
            }
          }
        }

        Text {
          visible: root.message !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
          text: root.message
          color: root.gold
          font.family: Style.font.family
          font.pixelSize: Style.space(11)
        }

        PetButton { width: parent.width; label: "Back"; onClicked: root.home() }
      }

      // ---- Training against the Substitute doll (EVs or XP) ----
      Column {
        id: training
        visible: root.mode === "train" && !!root.trainPet
        width: parent.width
        spacing: Style.space(10)
        readonly property var p: root.trainPet
        readonly property bool active: !!p && !!p.training

        Rectangle {
          width: parent.width
          height: Style.space(140)
          radius: Style.cornerRadius
          color: Qt.rgba(0.29, 0.53, 0.72, 0.10)
          clip: true

          SubstituteScene {
            anchors.fill: parent
            slug: training.p ? training.p.species : ""
            shiny: !!training.p && training.p.shiny
            hitting: training.active && root.opened && root.mode === "train"
            label: training.active && Pet.trainKind(training.p.training) === "xp" ? "+XP" : "+EV"
          }
        }

        Caption {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          opacity: 1
          color: training.active ? root.gold : root.trainMessage ? root.accent : Color.popups.text
          text: root.trainMessage ? root.trainMessage
              : !training.p ? ""
              : training.active ? Pet.trainingText(training.p) + " · " + Pet.trainingLeft(training.p) + " left"
              : root.trainKind === "xp" ? "Trains toward a level goal at " + Pet.TRAIN_XP_PER_HOUR + " XP per hour."
              : Pet.TRAIN_EV_PER_HOUR + " EVs per hour, " + Pet.EV_MAX_STAT + " max per stat, " + Pet.EV_MAX_TOTAL + " in total."
        }

        // EVs or XP
        Row {
          id: kindRow
          width: parent.width
          spacing: Style.space(8)
          readonly property real half: (width - spacing) / 2

          PetButton {
            width: kindRow.half
            highlight: root.trainKind === "ev"
            enabledLook: !training.active || root.trainKind === "ev"
            label: "EV training"
            onClicked: if (!training.active) root.trainKind = "ev"
          }
          PetButton {
            width: kindRow.half
            highlight: root.trainKind === "xp"
            enabledLook: !training.active || root.trainKind === "xp"
            label: "XP training"
            onClicked: if (!training.active) root.trainKind = "xp"
          }
        }

        Grid {
          id: statPicker
          visible: root.trainKind === "ev"
          width: parent.width
          columns: 3
          spacing: Style.space(6)

          Repeater {
            model: training.p ? 6 : 0
            delegate: PetButton {
              required property int index
              width: (statPicker.width - statPicker.spacing * 2) / 3
              highlight: root.trainStat === index
              enabledLook: !training.active || root.trainStat === index
              label: Pet.STAT_LABELS[index] + " " + Math.floor(Pet.evs(training.p)[index])
              onClicked: if (!training.active) root.selectTrainStat(index)
            }
          }
        }

        Row {
          visible: !training.active && !!training.p
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(8)
          readonly property bool xp: root.trainKind === "xp"
          readonly property int low: !training.p ? 0 : xp ? Pet.level(training.p) + 1 : Math.floor(Pet.evs(training.p)[root.trainStat])
          readonly property int high: !training.p ? 0 : xp ? Pet.MAX_LEVEL : Pet.evCeiling(training.p, root.trainStat)
          readonly property int step: xp ? 1 : 4
          readonly property int value: xp ? root.trainLevel : root.trainTarget
          function set(v) {
            v = Math.max(low, Math.min(high, v))
            if (xp) root.trainLevel = v
            else root.trainTarget = v
          }

          Caption { anchors.verticalCenter: parent.verticalCenter; text: parent.xp ? "Goal Lv." : "Goal EVs" }
          PetButton { width: Style.space(30); label: "−"; onClicked: parent.set(parent.value - parent.step) }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(40)
            horizontalAlignment: Text.AlignHCenter
            text: parent.value
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.space(13)
            font.bold: true
          }
          PetButton { width: Style.space(30); label: "+"; onClicked: parent.set(parent.value + parent.step) }
          PetButton { width: Style.space(48); label: "Max"; onClicked: parent.set(parent.high) }
        }

        Row {
          id: trainButtons
          width: parent.width
          spacing: Style.space(8)
          readonly property real third: (width - spacing * 2) / 3
          readonly property bool startable: !!training.p && (root.trainKind === "xp"
            ? root.trainLevel > Pet.level(training.p)
            : root.trainTarget > Math.floor(Pet.evs(training.p)[root.trainStat]))

          PetButton { width: trainButtons.third; label: "Summary"; onClicked: root.showInfo(root.infoRef, root.infoBack) }
          PetButton {
            width: trainButtons.third
            highlight: !training.active
            danger: training.active
            enabledLook: training.active || trainButtons.startable
            label: training.active ? "Stop" : "Start"
            onClicked: {
              if (training.active) root.stopTraining()
              else if (trainButtons.startable) root.startTraining()
            }
          }
          PetButton { width: trainButtons.third; label: "Done"; onClicked: root.home() }
        }

        // Everyone currently training: jump between them freely
        Column {
          width: parent.width
          spacing: Style.space(6)

          Caption { text: "Training spots " + root.trainees.length + " / " + Pet.TRAIN_SLOTS }

          Row {
            spacing: Style.space(6)

            Repeater {
              model: root.mode === "train" ? root.trainees : []

              delegate: Rectangle {
                id: slot
                required property string modelData
                readonly property var saved: root.view.pets[modelData]
                width: Style.space(52)
                height: Style.space(52)
                radius: Style.cornerRadius
                color: slotArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0.29, 0.53, 0.72, 0.08)
                border.width: modelData === root.infoRef ? 1 : 0
                border.color: root.gold

                PokeSprite {
                  anchors.centerIn: parent
                  slug: slot.saved ? slot.saved.species : ""
                  shiny: !!slot.saved && slot.saved.shiny
                  fitWidth: parent.width - 6
                  fitHeight: parent.height - 6
                }

                MouseArea {
                  id: slotArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openTrainingFor(slot.modelData)
                }
              }
            }

            Repeater {
              model: Math.max(0, Pet.TRAIN_SLOTS - root.trainees.length)
              delegate: Rectangle {
                width: Style.space(52)
                height: Style.space(52)
                radius: Style.cornerRadius
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.10)
              }
            }
          }
        }
      }

      // ---- Following an expedition ----
      Column {
        id: expFollow
        visible: root.mode === "expedition"
        width: parent.width
        spacing: Style.space(8)
        readonly property var exp: root.followed
        readonly property var prog: exp ? Exp.progress(exp, root.expClock) : ({ floor: 1, frac: 0, left: 0 })
        readonly property var members: exp ? Exp.teamState(exp) : []
        readonly property bool done: !!exp && exp.status === "done"
        readonly property var report: done ? exp.report : null

        Rectangle {
          width: parent.width
          height: Style.space(150)
          radius: Style.cornerRadius
          clip: true
          color: Qt.rgba(0.29, 0.53, 0.72, 0.10)

          CorridorScene {
            anchors.fill: parent
            visible: !!expFollow.exp
            team: expFollow.members
            colors: expFollow.exp ? Exp.BIOMES[expFollow.exp.biome].colors : ["#222", "#444", "#888"]
            floor: Math.max(1, expFollow.prog.floor)
            frac: expFollow.prog.frac
            floorMs: expFollow.exp ? expFollow.exp.floorMs : 360000
            marks: expFollow.exp && expFollow.exp.status === "running" ? Exp.marks(expFollow.exp, Math.max(1, expFollow.prog.floor)) : []
            status: expFollow.exp ? expFollow.exp.status : "done"
            homeward: expFollow.exp && expFollow.exp.status === "returning" ? root.expClock - (expFollow.exp.recalledAt || root.expClock) : 0
            weather: expFollow.exp && expFollow.exp.status === "running" ? expFollow.exp.weather || "" : ""
            active: root.opened && root.mode === "expedition"
          }

          // Floor and time
          Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: Style.space(8)
            width: floorChip.implicitWidth + Style.space(14)
            height: Style.space(22)
            radius: height / 2
            color: Qt.rgba(0, 0, 0, 0.5)
            Text {
              id: floorChip
              anchors.centerIn: parent
              text: !expFollow.exp ? "" : expFollow.done ? Exp.OUTCOMES[expFollow.report.outcome]
                  : expFollow.exp.status === "returning" ? "Heading home"
                  : "B" + expFollow.prog.floor + "F"
              color: "white"
              font.family: Style.font.family
              font.pixelSize: Style.space(11)
              font.bold: true
            }
          }
          Rectangle {
            visible: !!expFollow.exp && !expFollow.done
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(8)
            width: timeChip.implicitWidth + Style.space(14)
            height: Style.space(22)
            radius: height / 2
            color: Qt.rgba(0, 0, 0, 0.5)
            Text {
              id: timeChip
              anchors.centerIn: parent
              text: !expFollow.exp ? "" : (expFollow.exp.status === "running" ? Exp.WEATHER_ICONS[expFollow.exp.weather || ""] + "  " : "")
                    + Exp.timeText(expFollow.prog.left) + (expFollow.exp.status === "returning" ? "" : " left")
              color: "white"
              font.family: Style.font.family
              font.pixelSize: Style.space(11)
            }
          }
        }

        Caption {
          visible: !expFollow.exp
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "This expedition is over."
        }

        // The team
        Repeater {
          model: expFollow.members
          delegate: Item {
            id: expMember
            required property var modelData
            readonly property bool down: modelData.hp <= 0
            width: expFollow.width
            height: Style.space(30)
            opacity: down ? 0.5 : 1

            PokeSprite {
              id: expMemberSprite
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              slug: expMember.modelData.species
              shiny: expMember.modelData.shiny
              fitWidth: Style.space(32)
              fitHeight: Style.space(28)
            }
            Text {
              id: expMemberName
              anchors.left: expMemberSprite.right
              anchors.leftMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(110)
              elide: Text.ElideRight
              text: expMember.modelData.name + " " + expMember.modelData.level
                    + (expMember.down ? " · KO" : expMember.modelData.status ? " · " + expMember.modelData.status.toUpperCase() : "")
              color: expMember.down || expMember.modelData.status ? root.accent : Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.space(11)
              font.bold: true
            }
            Column {
              anchors.left: expMemberName.right
              anchors.leftMargin: Style.space(6)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)
              Repeater {
                model: [
                  { ratio: expMember.modelData.hp / expMember.modelData.maxhp, hp: true, color: root.good },
                  { ratio: expMember.modelData.ppMax ? expMember.modelData.pp / expMember.modelData.ppMax : 0, color: root.steel },
                  { ratio: expMember.modelData.satiety / 100, color: root.gold }
                ]
                delegate: Rectangle {
                  required property var modelData
                  width: parent.width
                  height: Style.space(4)
                  radius: height / 2
                  color: Qt.rgba(1, 1, 1, 0.08)
                  Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, modelData.ratio))
                    height: parent.height
                    radius: parent.radius
                    color: modelData.hp && modelData.ratio <= 0.2 ? root.accent : modelData.hp && modelData.ratio <= 0.5 ? root.gold : modelData.color
                  }
                }
              }
            }
          }
        }
        Caption {
          visible: !!expFollow.exp && !expFollow.done
          width: parent.width
          font.pixelSize: Style.space(9)
          text: "Bars: HP · PP · fullness   ·   Bag: " + (expFollow.exp ? Exp.provisionCount(expFollow.exp.prov) : 0)
                + " provisions left   ·   Found: " + (expFollow.exp ? Exp.provisionCount(expFollow.exp.loot) : 0) + " items"
        }

        // Report
        Column {
          visible: expFollow.done
          width: parent.width
          spacing: Style.space(4)

          Text {
            text: !expFollow.report ? ""
                : { cleared: "★ Expedition cleared!", escaped: "Escaped safely", recalled: "Back home", failed: "The team was defeated…" }[expFollow.report.outcome]
                  + "   +" + expFollow.report.points + " rank pts   +₽" + (expFollow.report.money || 0)
            color: expFollow.report && expFollow.report.outcome === "failed" ? root.accent : root.gold
            font.family: Style.font.family
            font.pixelSize: Style.space(13)
            font.bold: true
          }
          Repeater {
            model: expFollow.report ? expFollow.report.members : []
            delegate: Caption {
              required property var modelData
              width: expFollow.width
              opacity: 0.9
              wrapMode: Text.WordWrap
              text: Pet.name(modelData.species) + "  Lv. " + modelData.from + (modelData.to > modelData.from ? " → " + modelData.to : "")
                    + "  ·  +" + modelData.xp + " XP"
                    + (modelData.evs.some(function(v) { return v > 0 })
                       ? "  ·  EVs " + modelData.evs.map(function(v, i) { return v > 0 ? "+" + v + " " + ["HP", "Atk", "Def", "SpA", "SpD", "Spe"][i] : "" }).filter(String).join(", ")
                       : "")
            }
          }
          Flow {
            width: parent.width
            spacing: Style.space(4)
            Repeater {
              model: expFollow.report ? expFollow.report.recruits : []
              delegate: Row {
                required property var modelData
                spacing: Style.space(2)
                PokeSprite { slug: modelData.species; shiny: modelData.shiny; fitWidth: Style.space(30); fitHeight: Style.space(26) }
                Caption {
                  anchors.verticalCenter: parent.verticalCenter
                  text: (modelData.legend ? "✦ " : "★ ") + Pet.name(modelData.species) + (modelData.ref ? " joined!" : " (box full)")
                  color: modelData.ref ? root.gold : root.accent
                  opacity: 1
                }
              }
            }
          }
          Flow {
            width: parent.width
            spacing: Style.space(2)
            Repeater {
              model: expFollow.done ? Object.keys(expFollow.exp.loot) : []
              delegate: Item {
                required property string modelData
                width: Style.space(32); height: Style.space(30)
                ItemSprite { anchors.centerIn: parent; item: modelData; scale_: 1 }
                Text {
                  anchors.right: parent.right; anchors.bottom: parent.bottom
                  text: "×" + expFollow.exp.loot[modelData]
                  color: Color.popups.text; font.pixelSize: Style.space(9); font.bold: true; font.family: Style.font.family
                }
              }
            }
          }
        }

        // Log, newest first (click a fight to see it turn by turn)
        Rectangle {
          visible: !!expFollow.exp
          width: parent.width
          height: Style.space(expFollow.done ? 130 : 180)
          radius: Style.cornerRadius
          color: Qt.rgba(1, 1, 1, 0.03)
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.08)

          ListView {
            id: expLog
            anchors.fill: parent
            anchors.margins: Style.space(6)
            clip: true
            spacing: Style.space(3)
            boundsBehavior: Flickable.StopAtBounds
            model: expFollow.exp ? expFollow.exp.log.slice().reverse() : []
            readonly property var icons: ({ battle: "⚔", boss: "☠", legend: "✦", item: "◆", trap: "⚠", event: "✧",
                                            weather: "☁", team: "♥", danger: "✖", info: "·", recruit: "★", care: "✚" })
            readonly property var tints: ({ boss: root.accent, legend: root.gold, item: root.good, trap: "#e8903a", danger: root.accent,
                                            recruit: root.gold, team: "#d685ad", care: root.good, battle: root.steel })

            delegate: Column {
              id: logEntry
              required property var modelData
              readonly property bool open: root.expOpenEntry === modelData
              width: expLog.width

              Item {
                width: parent.width
                height: logText.implicitHeight
                Text {
                  id: logFloor
                  width: Style.space(30)
                  text: logEntry.modelData.f > 0 ? "B" + logEntry.modelData.f + "F" : ""
                  color: Color.popups.text
                  opacity: 0.5
                  font.family: Style.font.family
                  font.pixelSize: Style.space(9)
                }
                Text {
                  id: logIcon
                  anchors.left: logFloor.right
                  width: Style.space(14)
                  text: expLog.icons[logEntry.modelData.k] || "·"
                  color: expLog.tints[logEntry.modelData.k] || Color.popups.text
                  font.pixelSize: Style.space(11)
                }
                Text {
                  id: logText
                  anchors.left: logIcon.right
                  anchors.right: parent.right
                  wrapMode: Text.WordWrap
                  text: logEntry.modelData.s + (logEntry.modelData.d ? (logEntry.open ? "  ▴" : "  ▸") : "")
                  color: logEntry.modelData.k === "danger" ? root.accent : Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.space(10)
                  MouseArea {
                    anchors.fill: parent
                    enabled: !!logEntry.modelData.d
                    cursorShape: logEntry.modelData.d ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.expOpenEntry = logEntry.open ? null : logEntry.modelData
                  }
                }
              }
              Repeater {
                model: logEntry.open ? logEntry.modelData.d : []
                delegate: Caption {
                  required property string modelData
                  x: Style.space(44)
                  width: expLog.width - x
                  wrapMode: Text.WordWrap
                  text: modelData
                  font.pixelSize: Style.space(9)
                }
              }
            }
          }
        }

        Row {
          id: expButtons
          width: parent.width
          spacing: Style.space(8)
          readonly property bool second: !!expFollow.exp && expFollow.exp.status !== "returning"
          readonly property real cell: second ? (width - spacing) / 2 : width

          PetButton { width: expButtons.cell; label: "Back"; onClicked: root.home() }
          PetButton {
            visible: !!expFollow.exp && expFollow.exp.status === "running"
            width: expButtons.cell
            danger: true
            label: "Call the team back"
            onClicked: root.recallExpedition()
          }
          PetButton {
            visible: expFollow.done
            width: expButtons.cell
            highlight: true
            label: "Close the report"
            onClicked: root.closeReport()
          }
        }
      }

      // ---- Bag ----
      Column {
        visible: root.mode === "bag"
        width: parent.width
        spacing: Style.space(8)

        Caption {
          visible: bagGrid.count === 0
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: "Your bag is empty. Search around to find Poké Balls, berries, candies, mints, bottle caps, incense, expedition provisions and evolution items!"
        }

        GridView {
          id: bagGrid
          width: parent.width
          height: count === 0 ? 0 : Math.min(Style.space(300), Math.ceil(count / 4) * cellHeight)
          clip: true
          cellWidth: width / 4
          cellHeight: Style.space(76)
          boundsBehavior: Flickable.StopAtBounds
          model: root.mode === "bag" ? Pet.bagItems(root.view) : []

          delegate: Item {
            required property string modelData
            width: bagGrid.cellWidth
            height: bagGrid.cellHeight

            Rectangle {
              anchors.fill: parent
              anchors.margins: Style.space(3)
              radius: Style.cornerRadius
              color: bagArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0.29, 0.53, 0.72, 0.08)
              border.width: root.selectedItem === modelData ? 1 : 0
              border.color: root.gold

              Text {
                visible: (root.view.bag[modelData] || 0) > 1
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(3)
                text: "×" + root.view.bag[modelData]
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.space(9)
                font.bold: true
              }

              MouseArea {
                id: bagArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.selectedItem = modelData; root.message = "" }
              }

              ItemSprite {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Style.space(4)
                item: modelData
                scale_: 1.5
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(4)
                width: parent.width - 4
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: Pet.itemName(modelData)
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.space(9)
              }
            }
          }
        }

        // Selected item: description and how to use it
        Rectangle {
          id: itemPanel
          readonly property bool shown: root.selectedItem !== "" && (root.view.bag[root.selectedItem] || 0) > 0
          readonly property string kind: shown ? Pet.itemKind(root.selectedItem) : ""
          visible: shown
          width: parent.width
          height: itemColumn.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          color: Qt.rgba(1, 1, 1, 0.04)
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.10)

          Column {
            id: itemColumn
            anchors.fill: parent
            anchors.margins: Style.space(8)
            spacing: Style.space(8)

            Row {
              spacing: Style.space(8)
              ItemSprite { item: itemPanel.shown ? root.selectedItem : ""; scale_: 1 }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: itemPanel.shown ? Pet.itemName(root.selectedItem) + "  ×" + root.view.bag[root.selectedItem] : ""
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.space(12)
                font.bold: true
              }
            }

            Caption {
              width: parent.width
              wrapMode: Text.WordWrap
              text: itemPanel.shown ? Pet.itemText(root.selectedItem) : ""
            }

            Grid {
              id: capGrid
              visible: itemPanel.shown && root.selectedItem === "bottle-cap" && root.hasPet
              width: parent.width
              columns: 3
              spacing: Style.space(6)

              Repeater {
                model: capGrid.visible ? 6 : 0
                delegate: PetButton {
                  required property int index
                  width: (capGrid.width - capGrid.spacing * 2) / 3
                  enabledLook: root.pet.ivs[index] < 31
                  label: Pet.STAT_LABELS[index] + " " + root.pet.ivs[index]
                  onClicked: root.useItem(root.selectedItem, index)
                }
              }
            }

            PetButton {
              readonly property bool incense: itemPanel.kind === "incense"
              visible: itemPanel.shown && ["evolution", "ball"].indexOf(itemPanel.kind) < 0 && !Pet.isProvision(root.selectedItem)
                       && root.selectedItem !== "bottle-cap"
              width: parent.width
              highlight: true
              enabledLook: root.hasPet || incense
              label: incense ? (root.incenseLeft ? "Light another (+1h30)" : "Light the Incense")
                   : root.hasPet ? "Use on " + root.speciesName : "You need a partner"
              onClicked: if (root.hasPet || incense) root.useItem(root.selectedItem)
            }
          }
        }

        Text {
          visible: root.message !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
          text: root.message
          color: root.gold
          font.family: Style.font.family
          font.pixelSize: Style.space(11)
        }

        Caption {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: (root.searchesLeft > 0 ? "Your search of this half-hour is ready."
              : "Next search in " + root.refillMinutes + " min.")
              + (root.incenseLeft ? "  ·  Incense: " + root.incenseLeft : "")
        }

        PetButton { width: parent.width; label: "Back"; onClicked: root.home() }
      }

      // ---- Scene ----
      Rectangle {
        id: scene
        visible: ["picker", "box", "bag", "info", "moves", "relearn", "tms", "daycare", "train", "expedition", "menu", "shop"].indexOf(root.mode) < 0
        width: parent.width
        height: Style.space(170)
        radius: Style.cornerRadius
        color: root.mode === "encounter" ? Qt.rgba(0.50, 0.75, 0.60, 0.10) : Qt.rgba(0.29, 0.53, 0.72, 0.10)
        clip: true

        // Your partner, hitting the Substitute doll while it trains
        readonly property bool partnerTraining: root.hasPet && !!root.pet.training && root.mode === "pet"

        Image {
          id: partnerDoll
          visible: scene.partnerTraining
          source: Qt.resolvedUrl("sprites/substitute.png")
          smooth: false
          width: implicitWidth * 1.6
          height: implicitHeight * 1.6
          x: parent.width * 0.1 + shift
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(16)
          property real shift: 0
        }

        SequentialAnimation {
          running: scene.partnerTraining && root.opened
          loops: Animation.Infinite
          onRunningChanged: if (!running) { bigSprite.lunge = 0; partnerDoll.shift = 0 }
          PauseAnimation { duration: 600 }
          NumberAnimation { target: bigSprite; property: "lunge"; to: -Style.space(36); duration: 160; easing.type: Easing.InQuad }
          ParallelAnimation {
            NumberAnimation { target: bigSprite; property: "lunge"; to: 0; duration: 260; easing.type: Easing.OutQuad }
            SequentialAnimation {
              NumberAnimation { target: partnerDoll; property: "shift"; to: -6; duration: 60 }
              NumberAnimation { target: partnerDoll; property: "shift"; to: 4; duration: 60 }
              NumberAnimation { target: partnerDoll; property: "shift"; to: 0; duration: 60 }
            }
          }
        }

        Text {
          visible: scene.partnerTraining
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.margins: Style.space(8)
          text: Pet.trainingText(root.pet) + " · " + Pet.trainingLeft(root.pet)
          color: root.gold
          font.family: Style.font.family
          font.pixelSize: Style.space(10)
        }

        // Your Pokémon
        PokeSprite {
          id: bigSprite
          visible: root.hasPet && root.mode !== "encounter" && root.mode !== "found"
          opacity: root.partnerAway && root.mode === "pet" ? 0.45 : 1
          property real lunge: 0
          slug: root.mode === "evolve" && root.evolvePet ? root.evolvePet.species : root.hasPet ? root.pet.species : ""
          shiny: root.mode === "evolve" && root.evolvePet ? root.evolvePet.shiny : root.hasPet && root.pet.shiny
          fitWidth: scene.partnerTraining ? parent.width * 0.5 : parent.width - Style.space(20)
          fitHeight: parent.height - Style.space(scene.partnerTraining ? 40 : 24)
          maxPixel: 7
          integerScale: true
          x: (scene.partnerTraining ? parent.width * 0.68 - width / 2 : (parent.width - width) / 2) + lunge
          y: (scene.partnerTraining ? parent.height - height - Style.space(12) : (parent.height - height) / 2) + bob
          property real bob: 0

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.mode === "pet") root.showInfo(root.view.current, "pet")
          }

          SequentialAnimation on bob {
            running: root.opened
            loops: Animation.Infinite
            NumberAnimation { to: -4; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0; duration: 700; easing.type: Easing.InOutSine }
          }

          transform: [
            Scale { id: squash; origin.x: bigSprite.width / 2; origin.y: bigSprite.height; xScale: 1; yScale: 1 },
            Translate { id: hop; y: 0 }
          ]
        }

        // Empty Poké Ball when you have nobody yet
        ItemSprite {
          visible: !root.hasPet && root.mode !== "encounter" && root.mode !== "found"
          anchors.centerIn: parent
          item: "poke-ball"
          scale_: 3
          opacity: 0.35
        }

        // Everything the search turned up
        Flow {
          visible: root.mode === "found"
          anchors.centerIn: parent
          width: Math.min(parent.width - Style.space(16), root.foundItems.length * Style.space(68))
          spacing: Style.space(4)

          Repeater {
            model: root.mode === "found" ? root.foundItems : []
            delegate: Column {
              required property var modelData
              width: Style.space(64)
              spacing: Style.space(2)

              Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: foundSprite.width
                height: foundSprite.height
                ItemSprite { id: foundSprite; item: modelData.id; scale_: 1.5 }
                Text {
                  visible: modelData.count > 1
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  text: "×" + modelData.count
                  color: root.gold
                  font.family: Style.font.family
                  font.pixelSize: Style.space(10)
                  font.bold: true
                }
              }
              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: Pet.itemName(modelData.id)
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.space(9)
              }
            }
          }
        }

        // Your partner is out exploring
        Rectangle {
          visible: root.partnerAway && root.mode === "pet"
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.margins: Style.space(8)
          width: awayLabel.implicitWidth + Style.space(14)
          height: Style.space(22)
          radius: height / 2
          color: Qt.rgba(0, 0, 0, 0.45)
          Text {
            id: awayLabel
            anchors.centerIn: parent
            text: "⛰ On an expedition"
            color: root.gold
            font.family: Style.font.family
            font.pixelSize: Style.space(11)
          }
        }

        // Wild Pokémon
        PokeSprite {
          id: wildSprite
          visible: root.mode === "encounter"
          slug: root.wildSlug
          shiny: root.wildShiny
          fitWidth: parent.width - Style.space(20)
          fitHeight: parent.height - Style.space(24)
          maxPixel: 6
          integerScale: true
          x: (parent.width - width) / 2 + wildShift
          y: (parent.height - height) / 2
          property real wildShift: 0
          transform: Scale { id: wildSquash; origin.x: wildSprite.width / 2; origin.y: wildSprite.height; yScale: 1 }
          Behavior on opacity { NumberAnimation { duration: 200 } }

          // Shiny logo, pinned to the sprite's top-right corner
          Rectangle {
            visible: root.wildShiny
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: -Style.space(4)
            width: Style.space(20)
            height: width
            radius: width / 2
            color: Qt.rgba(0.95, 0.72, 0.29, 0.25)
            border.width: 1
            border.color: root.gold

            Text {
              anchors.centerIn: parent
              text: "✦"
              color: root.gold
              font.pixelSize: Style.space(12)
              font.bold: true
            }
          }
        }

        // Shiny entrance: two waves of stars bursting out of the wild Pokémon
        Item {
          id: burst
          visible: root.mode === "encounter" && progress > 0 && progress < 1
          x: wildSprite.x + wildSprite.width / 2
          y: wildSprite.y + wildSprite.height / 2
          property real progress: 0
          readonly property real reach: Math.max(wildSprite.width, wildSprite.height) * 0.6 + Style.space(10)

          Repeater {
            model: 10
            Text {
              required property int index
              readonly property real angle: index * Math.PI * 2 / 10 + (index % 2 ? 0.2 : 0)
              readonly property real dist: burst.reach * (index % 2 ? 0.7 : 1) * burst.progress
              text: "✦"
              color: index % 3 === 0 ? "white" : root.gold
              font.pixelSize: Style.space(index % 2 ? 12 : 18)
              x: Math.cos(angle) * dist - width / 2
              y: Math.sin(angle) * dist - height / 2
              opacity: burst.progress < 0.2 ? burst.progress * 5 : 1 - (burst.progress - 0.2) / 0.8
              scale: 0.4 + burst.progress
              rotation: burst.progress * 180
            }
          }
        }

        SequentialAnimation {
          id: shinyBurst
          loops: 2
          NumberAnimation { target: burst; property: "progress"; from: 0; to: 1; duration: 650; easing.type: Easing.OutQuad }
          ScriptAction { script: burst.progress = 0 }
        }

        ItemSprite {
          id: ball
          visible: false
          anchors.centerIn: parent
          anchors.verticalCenterOffset: Style.space(20)
          item: root.ballItem
          scale_: 2
          transformOrigin: Item.Bottom
        }

        Text {
          visible: root.mode === "encounter" && !root.encounterOver && !!root.view.encounter
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.margins: Style.space(8)
          text: !root.view.encounter ? ""
              : root.view.encounter.angry > 0 ? "Angry!"
              : root.view.encounter.eating > 0 ? "Eating…" : ""
          color: root.view.encounter && root.view.encounter.angry > 0 ? root.accent : root.good
          font.family: Style.font.family
          font.pixelSize: Style.space(11)
          font.bold: true
        }

        SequentialAnimation {
          id: throwAnim
          ScriptAction { script: { ball.rotation = 0; ball.visible = true } }
          NumberAnimation { target: wildSprite; property: "opacity"; to: 0; duration: 200 }
          SequentialAnimation {
            loops: root.shakeLoops
            PauseAnimation { duration: 300 }
            NumberAnimation { target: ball; property: "rotation"; to: -25; duration: 110 }
            NumberAnimation { target: ball; property: "rotation"; to: 25; duration: 160 }
            NumberAnimation { target: ball; property: "rotation"; to: 0; duration: 110 }
          }
          PauseAnimation { duration: 350 }
          ScriptAction { script: root.finishThrow() }
        }

        SequentialAnimation {
          id: wildShake
          loops: 2
          NumberAnimation { target: wildSprite; property: "wildShift"; to: -6; duration: 60 }
          NumberAnimation { target: wildSprite; property: "wildShift"; to: 6; duration: 80 }
          NumberAnimation { target: wildSprite; property: "wildShift"; to: 0; duration: 60 }
        }

        SequentialAnimation {
          id: munchWild
          loops: 3
          NumberAnimation { target: wildSquash; property: "yScale"; to: 0.92; duration: 90 }
          NumberAnimation { target: wildSquash; property: "yScale"; to: 1; duration: 90 }
        }

        SequentialAnimation {
          id: jump
          NumberAnimation { target: hop; property: "y"; to: -30; duration: 180; easing.type: Easing.OutQuad }
          NumberAnimation { target: hop; property: "y"; to: 0; duration: 220; easing.type: Easing.OutBounce }
        }

        SequentialAnimation {
          id: munch
          loops: 3
          NumberAnimation { target: squash; property: "yScale"; to: 0.92; duration: 90 }
          NumberAnimation { target: squash; property: "yScale"; to: 1; duration: 90 }
        }

        Text {
          id: heartText
          text: "♥  ♥"
          color: root.accent
          font.pixelSize: Style.space(22)
          anchors.horizontalCenter: parent.horizontalCenter
          y: Style.space(20)
          opacity: 0
        }

        ParallelAnimation {
          id: hearts
          NumberAnimation { target: heartText; property: "opacity"; from: 1; to: 0; duration: 900 }
          NumberAnimation { target: heartText; property: "y"; from: Style.space(30); to: 0; duration: 900; easing.type: Easing.OutQuad }
        }

        Text {
          id: sparkleText
          text: "✦       ✦\n    ✦       ✦"
          color: root.gold
          font.pixelSize: Style.space(18)
          anchors.centerIn: parent
          horizontalAlignment: Text.AlignHCenter
          opacity: 0
        }

        SequentialAnimation {
          id: sparkle
          loops: 2
          NumberAnimation { target: sparkleText; property: "opacity"; to: 1; duration: 200 }
          NumberAnimation { target: sparkleText; property: "opacity"; to: 0; duration: 400 }
        }

        Rectangle {
          id: flashRect
          anchors.fill: parent
          color: "white"
          opacity: 0
        }

        SequentialAnimation {
          id: flash
          loops: 3
          NumberAnimation { target: flashRect; property: "opacity"; to: 0.9; duration: 150 }
          NumberAnimation { target: flashRect; property: "opacity"; to: 0; duration: 250 }
        }
      }

      Text {
        visible: ["picker", "box", "bag", "info", "moves", "relearn", "tms", "daycare", "train", "expedition", "menu", "shop"].indexOf(root.mode) < 0
        width: parent.width
        text: root.mode === "confirm"
          ? "Release " + root.speciesName + " and start over with a new " + Pet.name(root.view.current) + "?"
          : root.message
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.space(12)
      }

      // ---- Your Pokémon: stats ----
      Repeater {
        model: root.mode === "pet" && root.hasPet ? [
          { label: "Fullness", key: "satiety", color: "#f2b84b" },
          { label: "Happiness", key: "happiness", color: "#e23b44" },
          { label: "Evolution", key: "evo", color: "#4a86b8" }
        ] : []

        delegate: Column {
          required property var modelData
          width: content.width
          spacing: Style.space(3)

          readonly property real ratio: modelData.key === "evo"
            ? Pet.evoProgress(root.pet)
            : root.pet[modelData.key] / 100

          Caption {
            text: modelData.key !== "evo" ? modelData.label
              : root.nextLevel ? "Evolution (Lv. " + root.nextLevel + ")"
              : "Fully evolved"
          }

          Rectangle {
            width: parent.width
            height: Style.space(6)
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.08)

            Rectangle {
              width: parent.width * Math.max(0, Math.min(1, ratio))
              height: parent.height
              radius: parent.radius
              color: modelData.color
              Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            }
          }
        }
      }

      PetButton {
        visible: root.mode === "pet" && Pet.evolutionReady(root.view, root.now)
        width: parent.width
        highlight: true
        label: "✦ Evolve…"
        onClicked: root.openEvolve("")
      }

      Row {
        id: actions
        visible: root.mode === "pet" && root.hasPet
        width: parent.width
        spacing: Style.space(8)
        readonly property real third: (width - spacing * 2) / 3

        PetButton { width: actions.third; enabledLook: !root.partnerAway; label: "Feed"; onClicked: root.doAction("feed") }
        PetButton { width: actions.third; enabledLook: !root.partnerAway; label: "Pet"; onClicked: root.doAction("pet") }
        PetButton { width: actions.third; enabledLook: !root.partnerAway; label: "Play"; onClicked: root.doAction("play") }
      }

      // ---- Explore ----
      Row {
        id: explore
        visible: root.mode === "pet"
        width: parent.width
        spacing: Style.space(8)
        readonly property real third: (width - spacing * 2) / 3

        PetButton {
          width: explore.third
          highlight: !!root.view.encounter
          enabledLook: root.encountersLeft > 0 || !!root.view.encounter
          label: root.view.encounter ? "Wild ●"
               : root.encountersLeft > 0 ? (root.view.navdex ? "◎ " : "Wild ") + root.encountersLeft + "/" + root.encountersPerWindow
               : "Wild " + root.refillMinutes + "m"
          onClicked: root.startWild()
        }
        PetButton {
          width: explore.third
          enabledLook: root.searchesLeft > 0
          highlight: root.searchesLeft > 0
          label: root.searchesLeft > 0 ? "Search ●" : "Search " + root.refillMinutes + "m"
          onClicked: root.search()
        }
        PetButton { width: explore.third; label: "Bag"; onClicked: { root.message = ""; root.mode = "bag" } }
      }

      PetButton {
        visible: root.mode === "pet" && Pet.ownedCount(root.view) > 0
        width: parent.width
        highlight: root.expeditionNews
        label: "⛰ Plan an expedition"
        onClicked: root.openExpeditions()
      }

      // Teams out exploring (click to follow them)
      Repeater {
        model: root.mode === "pet" ? root.expeditions : []
        delegate: Rectangle {
          id: expLine
          required property var modelData
          readonly property var prog: Exp.progress(modelData, root.now)
          readonly property bool done: modelData.status === "done"
          width: content.width
          height: Style.space(30)
          radius: Style.cornerRadius
          color: expLineArea.containsMouse ? Qt.rgba(0.95, 0.72, 0.29, 0.14) : Qt.rgba(1, 1, 1, 0.04)
          border.width: 1
          border.color: done && !modelData.seen ? root.gold : Qt.rgba(1, 1, 1, 0.10)

          Row {
            id: expLineTeam
            anchors.left: parent.left
            anchors.leftMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            Repeater {
              model: expLine.modelData.team
              delegate: PokeSprite {
                required property var modelData
                slug: modelData.species
                shiny: modelData.shiny
                fitWidth: Style.space(26)
                fitHeight: Style.space(24)
              }
            }
          }
          Text {
            anchors.left: expLineTeam.right
            anchors.leftMargin: Style.space(6)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            // Status first, so a long place name is what gets cut
            text: (expLine.done ? (expLine.modelData.seen ? "" : "★ ") + Exp.OUTCOMES[expLine.modelData.report.outcome]
                   : expLine.modelData.status === "returning" ? "Home in " + Exp.timeText(expLine.prog.left)
                   : "B" + expLine.prog.floor + "F/" + expLine.modelData.floors + " · " + Exp.timeText(expLine.prog.left).replace(" min", "m"))
                  + " · " + Exp.title(expLine.modelData)
            color: expLine.done ? root.gold : Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.space(11)
          }
          MouseArea {
            id: expLineArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.followExpedition(expLine.modelData.id)
          }
        }
      }

      // Active Nav-Dex and Incense
      Item {
        visible: root.mode === "pet" && (!!root.view.navdex || root.incenseLeft !== "")
        width: parent.width
        height: Math.max(navStatus.implicitHeight, incenseStatus.implicitHeight)

        Text {
          id: navStatus
          visible: !!root.view.navdex
          anchors.left: parent.left
          text: "◎ Nav-Dex: " + Pet.name(root.view.navdex) + (navStopArea.containsMouse ? "  ✕ stop" : "")
          color: navStopArea.containsMouse ? root.accent : root.gold
          font.family: Style.font.family
          font.pixelSize: Style.space(11)

          MouseArea {
            id: navStopArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleNavdex(root.view.navdex)
          }
        }

        Text {
          id: incenseStatus
          visible: root.incenseLeft !== ""
          anchors.right: parent.right
          text: "Incense · " + root.incenseLeft
          color: "#d685ad"
          font.family: Style.font.family
          font.pixelSize: Style.space(11)
        }
      }

      // ---- Evolution choice ----
      Flickable {
        id: evoList
        visible: root.mode === "evolve"
        width: parent.width
        height: Math.min(contentHeight, Style.space(250))
        contentHeight: evoColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: evoColumn
          width: evoList.width
          spacing: Style.space(6)

          Repeater {
            model: root.mode === "evolve" ? Pet.evolutionOptions(root.view, root.now, root.evolveRoot || undefined) : []

            delegate: Rectangle {
              id: option
              required property var modelData
              width: evoColumn.width
              height: Style.space(48)
              radius: Style.cornerRadius
              color: optionArea.containsMouse && modelData.met ? Qt.rgba(0.95, 0.72, 0.29, 0.15) : Qt.rgba(1, 1, 1, 0.04)
              border.width: 1
              border.color: modelData.met ? root.gold : Qt.rgba(1, 1, 1, 0.10)
              opacity: modelData.met ? 1 : 0.55

              Item {
                id: optionSprite
                anchors.left: parent.left
                anchors.leftMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(48)
                height: Style.space(40)

                PokeSprite {
                  anchors.centerIn: parent
                  slug: option.modelData.slug
                  shiny: !!root.evolvePet && root.evolvePet.shiny
                  fitWidth: parent.width
                  fitHeight: parent.height
                }
              }

              Column {
                anchors.left: optionSprite.right
                anchors.leftMargin: Style.space(8)
                anchors.right: status.left
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  text: option.modelData.name
                  color: Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.space(12)
                  font.bold: true
                }
                Caption {
                  width: parent.width
                  elide: Text.ElideRight
                  text: option.modelData.text
                  font.pixelSize: Style.space(10)
                }
              }

              Text {
                id: status
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: option.modelData.met ? "✓" : "✗"
                color: option.modelData.met ? root.good : root.accent
                font.pixelSize: Style.space(14)
              }

              MouseArea {
                id: optionArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: option.modelData.met ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: if (option.modelData.met && root.loaded) root.evolveInto(option.modelData.slug)
              }
            }
          }
        }
      }

      PetButton {
        visible: root.mode === "evolve"
        width: parent.width
        label: "Not now"
        onClicked: root.notNow()
      }

      // ---- Safari encounter ----
      Column {
        id: safari
        visible: root.mode === "encounter" && !root.encounterOver
        width: parent.width
        spacing: Style.space(8)
        readonly property real quarter: (width - Style.space(8) * 3) / 4
        readonly property real third: (width - Style.space(8) * 2) / 3

        // One button per kind of ball, with how many you have
        Row {
          spacing: Style.space(8)
          Repeater {
            model: ["poke-ball", "great-ball", "ultra-ball", "master-ball"]
            delegate: PetButton {
              id: ballButton
              required property string modelData
              readonly property int count: root.view.bag[modelData] || 0
              width: safari.quarter
              highlight: count > 0 && modelData === "poke-ball"
              enabledLook: count > 0
              label: ""
              onClicked: root.throwBall(modelData)
              Row {
                anchors.centerIn: parent
                spacing: Style.space(2)
                ItemSprite { anchors.verticalCenter: parent.verticalCenter; item: ballButton.modelData; scale_: 0.8 }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "×" + ballButton.count
                  color: Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.space(11)
                }
              }
            }
          }
        }
        Row {
          spacing: Style.space(8)
          PetButton { width: safari.third; label: "Bait"; onClicked: root.throwBait() }
          PetButton { width: safari.third; label: "Rock"; onClicked: root.throwRock() }
          PetButton { width: safari.third; label: "Run"; onClicked: root.runAway() }
        }
      }

      Row {
        id: afterRow
        visible: (root.mode === "encounter" && root.encounterOver) || root.mode === "found"
        width: parent.width
        spacing: Style.space(8)
        readonly property bool caught: root.mode === "encounter" && root.caughtRef !== "" && !!Pet.specimen(root.view, root.caughtRef)

        PetButton {
          visible: afterRow.caught
          width: (afterRow.width - afterRow.spacing) / 2
          label: "Summary"
          onClicked: root.showInfo(root.caughtRef, Pet.isBoxed(root.caughtRef) ? "box" : "pet")
        }
        PetButton {
          width: afterRow.caught ? (afterRow.width - afterRow.spacing) / 2 : afterRow.width
          label: "Continue"
          onClicked: root.home()
        }
      }

      Row {
        id: confirmRow
        visible: root.mode === "confirm"
        width: parent.width
        spacing: Style.space(8)

        PetButton { width: (confirmRow.width - confirmRow.spacing) / 2; label: "Cancel"; onClicked: root.mode = "pet" }
        PetButton { width: (confirmRow.width - confirmRow.spacing) / 2; label: "Start over"; danger: true; onClicked: root.restart() }
      }

      // Footer links
      Item {
        visible: root.mode === "pet" && Pet.ownedCount(root.view) > 0
        width: parent.width
        height: footerLinks.implicitHeight

        Row {
          id: footerLinks
          spacing: Style.space(14)

          Repeater {
            model: [ { label: "◉ Summary", target: "info" }, { label: "⌂ Day Care", target: "daycare" } ]

            delegate: Text {
              required property var modelData
              visible: modelData.target !== "info" || root.hasPet
              text: modelData.label
              color: linkArea.containsMouse ? root.gold : Color.popups.text
              opacity: linkArea.containsMouse ? 1 : 0.5
              font.family: Style.font.family
              font.pixelSize: Style.space(11)

              MouseArea {
                id: linkArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (modelData.target === "info") root.showInfo(root.view.current, "pet")
                  else root.mode = "daycare"
                }
              }
            }
          }
        }

        Text {
          visible: root.hasPet
          anchors.right: parent.right
          text: "↺ Start over"
          color: restartArea.containsMouse ? root.accent : Color.popups.text
          opacity: restartArea.containsMouse ? 1 : 0.5
          font.family: Style.font.family
          font.pixelSize: Style.space(11)

          MouseArea {
            id: restartArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.loaded) root.mode = "confirm"
          }
        }
      }

    }
  }
}
