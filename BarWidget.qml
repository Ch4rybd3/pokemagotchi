import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Pet.js" as Pet

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
  readonly property var view: Pet.tick(Pet.copy(save), now)
  readonly property var pet: Pet.current(view)
  readonly property bool hasPet: pet !== null
  readonly property string speciesName: hasPet ? Pet.name(pet.species) : ""
  readonly property int nextLevel: hasPet ? Pet.nextLevel(pet.species) : 0
  readonly property int encountersLeft: Pet.encountersLeft(view, now)
  readonly property int searchesLeft: Pet.searchesLeft(view, now)
  readonly property int encountersPerWindow: Pet.encountersPerWindow(view, now)
  readonly property string incenseLeft: Pet.incenseLeft(view, now)
  readonly property int refillMinutes: Pet.minutesToRefill(now)

  // "pet" | "picker" | "box" | "confirm" | "evolve" | "encounter" | "found" | "bag"
  // | "info" | "moves" | "relearn" | "daycare" | "train"
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
  property string foundItem: ""

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
  property int daycarePage: 0
  readonly property int daycareSize: 10
  readonly property var ownedRoots: Pet.ownedRoots(view)
  readonly property int daycarePages: Math.max(1, Math.ceil(ownedRoots.length / daycareSize))
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
    var s = Pet.tick(Pet.copy(save), t)
    var after = Pet.current(s)
    var learned = known && after && s.current === save.current
      ? after.moves.filter(function(m) { return known.indexOf(m) < 0 }) : []
    var result = fn(s, t)
    var evo = Pet.maybeEvolve(s, t)
    save = s
    now = t
    stateFile.setText(JSON.stringify(s) + "\n")
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
    var r = infoRef
    message = mutate(function(s) { return Pet.relearn(s, r, id, slot) })
    relearnId = 0
    moveSlot = -1
    mode = "moves"
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

  function throwBall() {
    if (busy || encounterOver) return
    var r = mutate(function(s, t) { return Pet.throwBall(s, t) })
    if (!r) return
    if (r.result === "full") {
      message = Pet.name(wildSlug) + "'s box is full (" + Pet.BOX_SIZE + "). Release one first."
      return
    }
    busy = true
    pendingThrow = r
    shakeLoops = Math.max(1, r.shakes)
    message = "You threw a Poké Ball!"
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
    var r = mutate(function(s, t) { return Pet.searchItem(s, t) })
    if (r === "") { message = "Nothing new around here… your bag already has every item!"; return }
    if (!r) return
    foundItem = r
    mode = "found"
    message = "You found a " + Pet.itemName(r) + "!"
    sparkle.restart()
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

  // Display-only refresh; nothing is written here.
  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.now = Date.now()
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
                                                     : ["info", "box", "moves", "relearn"].indexOf(root.mode) >= 0 ? 400
                                                     : root.mode === "bag" ? 340 : 300))
    contentHeight: popup.fittedContentHeight(content.implicitHeight)

    Column {
      id: content
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
          text: (root.mode === "picker" ? "POKÉDEX"
               : root.mode === "box" ? Pet.name(root.boxRoot).toUpperCase() + " BOX"
               : (root.mode === "moves" || root.mode === "relearn") && root.infoPet ? Pet.name(root.infoPet.species).toUpperCase()
               : root.mode === "bag" ? "BAG"
               : root.mode === "found" ? "EXPLORE"
               : root.mode === "encounter" ? Pet.name(root.wildSlug).toUpperCase()
               : root.mode === "daycare" ? "DAY CARE"
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
              if (root.mode === "picker") { root.home(); return }
              root.query = ""
              root.mode = "picker"
              searchField.forceActiveFocus()
            }
          }
        }

        Text {
          id: headerInfo
          anchors.right: shinyChip.visible ? shinyChip.left : parent.right
          anchors.rightMargin: shinyChip.visible ? Style.space(10) : 0
          anchors.verticalCenter: parent.verticalCenter
          text: root.mode === "picker" ? Pet.ownedCount(root.view) + " / " + Pet.familyTotal() + (Pet.hasCharm(root.view) ? "" : " caught")
              : root.mode === "box" ? Pet.familyCount(root.view, root.boxRoot) + " / " + Pet.BOX_SIZE
              : root.mode === "moves" ? "Moves"
              : root.mode === "relearn" ? "Move Reminder"
              : root.mode === "bag" ? Pet.bagItems(root.view).length + (Pet.bagItems(root.view).length === 1 ? " item" : " items")
              : root.mode === "encounter" ? "Lv. " + root.wildLevel
              : root.mode === "found" ? ""
              : root.mode === "daycare" ? "Box " + (root.daycarePage + 1) + " / " + root.daycarePages + "  ·  " + root.ownedRoots.length + " Pokémon"
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
          text: "⌂ plays at the Day Care, the others rest in the box. Click one to see its summary."
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
                  : root.infoRef === root.view.current ? "★ Your partner" : "⌂ At the Day Care"
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
          readonly property int count: root.infoBoxed ? 3 : partner ? 1 : 2
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
            visible: root.infoBoxed
            width: summaryButtons.cell
            highlight: true
            label: "⌂ To Day Care"
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
          text: "Boxed Pokémon rest: no XP or training. Send it to the Day Care to swap it with "
                + (Pet.specimen(root.view, Pet.refRoot(root.infoRef)) ? Pet.name(Pet.specimen(root.view, Pet.refRoot(root.infoRef)).species) : "the one there")
                + (Pet.refRoot(root.infoRef) === root.view.current ? ", your partner." : ".")
        }
      }

      // ---- Moves: the four it knows, and the Move Reminder ----
      Column {
        id: movesView
        visible: (root.mode === "moves" || root.mode === "relearn") && !!root.infoPet
        width: parent.width
        spacing: Style.space(6)
        readonly property var known: movesView.visible ? Pet.moves(root.infoPet) : []
        readonly property var others: movesView.visible ? Pet.relearnable(root.infoPet) : []
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
          readonly property real half: (width - spacing) / 2

          PetButton {
            width: movesButtons.half
            label: root.mode === "relearn" || root.relearnId > 0 ? "Cancel" : "Summary"
            onClicked: {
              if (root.mode === "relearn" || root.relearnId > 0) root.openMoves()
              else root.showInfo(root.infoRef, root.infoBack)
            }
          }
          PetButton {
            width: movesButtons.half
            highlight: root.mode === "moves"
            enabledLook: root.mode === "moves" && root.relearnId === 0
            label: "Move Reminder"
            onClicked: if (root.mode === "moves" && root.relearnId === 0) { root.message = ""; root.mode = "relearn" }
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
          height: Style.space(300)
          radius: Style.cornerRadius
          clip: true
          gradient: Gradient {
            GradientStop { position: 0.0; color: "#1d3a2a" }
            GradientStop { position: 1.0; color: "#2c5a36" }
          }

          // Scroll (wheel or touchpad, either axis) to switch boxes
          WheelHandler {
            property real acc: 0
            onWheel: function(event) {
              var d = event.angleDelta.x !== 0 ? -event.angleDelta.x : -event.angleDelta.y
              acc += d
              if (Math.abs(acc) < 120) return
              var step = acc > 0 ? 1 : -1
              acc = 0
              root.daycarePage = Math.max(0, Math.min(root.daycarePages - 1, root.daycarePage + step))
            }
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
            model: root.mode === "daycare"
                   ? root.ownedRoots.slice(root.daycarePage * root.daycareSize, (root.daycarePage + 1) * root.daycareSize) : []

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

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(10)

          PetButton {
            width: Style.space(36)
            label: "‹"
            enabledLook: root.daycarePage > 0
            onClicked: root.daycarePage = Math.max(0, root.daycarePage - 1)
          }

          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
            Repeater {
              model: root.daycarePages
              delegate: Rectangle {
                required property int index
                width: Style.space(8); height: width; radius: width / 2
                color: index === root.daycarePage ? root.accent : Qt.rgba(1, 1, 1, 0.2)
                MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: root.daycarePage = index }
              }
            }
          }

          PetButton {
            width: Style.space(36)
            label: "›"
            enabledLook: root.daycarePage < root.daycarePages - 1
            onClicked: root.daycarePage = Math.min(root.daycarePages - 1, root.daycarePage + 1)
          }
        }

        Caption {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: "10 Pokémon per box · scroll to switch boxes. They play here while you look after your partner (★) and slowly gain XP. Click one to see its summary."
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
          text: "Your bag is empty. Search around to find berries, candies, mints, bottle caps, incense and evolution items!"
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
              visible: itemPanel.shown && itemPanel.kind !== "evolution" && root.selectedItem !== "bottle-cap"
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
          text: (root.searchesLeft > 0 ? root.searchesLeft + " / " + Pet.SEARCHES_PER_WINDOW + " item searches left, refilled in " + root.refillMinutes + " min."
              : "Next item searches in " + root.refillMinutes + " min.")
              + (root.incenseLeft ? "  ·  Incense: " + root.incenseLeft : "")
        }

        PetButton { width: parent.width; label: "Back"; onClicked: root.home() }
      }

      // ---- Scene ----
      Rectangle {
        id: scene
        visible: ["picker", "box", "bag", "info", "moves", "relearn", "daycare", "train"].indexOf(root.mode) < 0
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

        // Empty Poké Ball when you have nobody yet, or the item you just found
        ItemSprite {
          visible: (!root.hasPet && root.mode !== "encounter") || root.mode === "found"
          anchors.centerIn: parent
          item: root.mode === "found" ? root.foundItem : "poke-ball"
          scale_: 3
          opacity: root.mode === "found" ? 1 : 0.35
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
          item: "poke-ball"
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
        visible: ["picker", "box", "bag", "info", "moves", "relearn", "daycare", "train"].indexOf(root.mode) < 0
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

        PetButton { width: actions.third; label: "Feed"; onClicked: root.doAction("feed") }
        PetButton { width: actions.third; label: "Pet"; onClicked: root.doAction("pet") }
        PetButton { width: actions.third; label: "Play"; onClicked: root.doAction("play") }
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
          label: root.searchesLeft > 0 ? "Search " + root.searchesLeft + "/" + Pet.SEARCHES_PER_WINDOW : "Search " + root.refillMinutes + "m"
          onClicked: root.search()
        }
        PetButton { width: explore.third; label: "Bag"; onClicked: { root.message = ""; root.mode = "bag" } }
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
      Grid {
        id: safari
        visible: root.mode === "encounter" && !root.encounterOver
        width: parent.width
        columns: 2
        spacing: Style.space(8)
        readonly property real half: (width - spacing) / 2

        PetButton { width: safari.half; highlight: true; label: "Poké Ball"; onClicked: root.throwBall() }
        PetButton { width: safari.half; label: "Bait"; onClicked: root.throwBait() }
        PetButton { width: safari.half; label: "Rock"; onClicked: root.throwRock() }
        PetButton { width: safari.half; label: "Run"; onClicked: root.runAway() }
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
