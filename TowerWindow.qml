import QtQuick
import Quickshell
import qs.Commons
import "Pet.js" as Pet
import "Tower.js" as Tower

// The Battle Tower window: pick a tower, a tier and a battle team, build your
// teams, spend your BP, look at your records, and fight (BattleScene).
// Battles run in TowerWorker (Pokémon Showdown), loaded the first time the
// window opens.
FloatingWindow {
  id: win
  required property var host

  title: "Pokemagotchi – Battle Tower"
  color: "#1c2a3a"
  implicitWidth: 1040
  implicitHeight: 720
  minimumSize: Qt.size(900, 620)
  visible: false

  readonly property var view: host.view
  readonly property var run: Tower.run(view)
  readonly property var typeColors: host.typeColors
  readonly property string font: pixel.status === FontLoader.Ready ? pixel.name : Style.font.family

  readonly property color ink: "#383840"
  readonly property color paper: "#f8f8f0"
  readonly property color frame: "#5878a0"
  readonly property color accent: "#e23b44"
  readonly property color gold: "#f2b84b"
  readonly property color good: "#58a868"

  // "challenge" | "teams" | "counter" | "records" | "battle"
  property string screen: "challenge"
  property string towerId: "kanto"
  property string format: "singles"
  property int tier: 1
  property int teamIndex: 0
  property string notice: ""
  property real clock: Date.now()

  // Team editor
  property int editTeam: 0
  readonly property var editedTeam: Tower.teams(view)[editTeam] || null
  readonly property var shelves: Tower.counter(clock)
  property int itemSlot: -1          // the member whose item is being chosen
  // BP counter
  property int shelf: 0
  property string counterItem: ""

  FontLoader { id: pixel; source: "fonts/PixelifySans.ttf" }
  readonly property alias canvas: canvas
  readonly property alias scene: battleScene

  function open() {
    host.now = Date.now()
    clock = Date.now()
    notice = ""
    engineWanted = true
    var r = Tower.run(host.view)
    if (r) { towerId = r.tower; format = r.format; tier = r.tier; teamIndex = r.team }
    else pickDefaults()
    screen = "challenge"
    if (visible) visible = false
    visible = true
    if (r && r.battle) resumeBattle()
  }

  onClosed: { visible = false; stepTimer.stop() }

  function pickDefaults() {
    if (!Tower.tierOpen(view, towerId, format, tier)) tier = Math.min(Tower.tierCount(towerId), Tower.cleared(view, towerId, format) + 1)
    if (teamIndex >= Tower.teams(view).length) teamIndex = 0
  }

  function mutate(fn) { return host.mutate(fn) }

  // ---- Engine ----

  property bool engineWanted: false
  property int requestId: 0
  property var waiting: null          // what to do with the next answer

  Loader {
    id: engineLoader
    active: win.engineWanted
    sourceComponent: WorkerScript {
      source: "TowerWorker.mjs"
      onMessage: function(m) { win.onEngine(m) }
      onReadyChanged: if (ready) win.flushEngine()
    }
  }
  property var outbox: []

  function send(msg) {
    msg.id = ++requestId
    var w = engineLoader.item
    if (w && w.ready) w.sendMessage(msg)
    else outbox = outbox.concat([msg])
  }
  function flushEngine() {
    var w = engineLoader.item
    var list = outbox
    outbox = []
    list.forEach(function(m) { w.sendMessage(m) })
  }

  // ---- Battle ----

  property string battleKey: ""
  property var shown: null
  property var battleState: null
  property var request: null
  property var moveInfo: ({})
  property string boxText: ""
  property var queue: []
  property var reply: null
  property bool playing: false
  property bool loading: false
  property var result: null
  property string foeName: ""
  property bool fast: false

  function emptyShown(state) {
    var n = format === "doubles" ? 2 : 1
    function side() { var a = []; for (var i = 0; i < n; i++) a.push(null); return { active: a } }
    return { sides: [side(), side()], weather: state ? state.weather : "" }
  }

  // The state the simulator reports, as the scene shows it.
  function shownOf(state) {
    var sh = emptyShown(state)
    for (var s = 0; s < 2; s++) {
      var act = state.sides[s].active
      for (var i = 0; i < act.length && i < sh.sides[s].active.length; i++) {
        var p = act[i]
        sh.sides[s].active[i] = p ? { species: p.species, name: p.name, level: p.level, gender: p.gender, shiny: p.shiny,
                                     hp: p.hp, maxhp: p.maxhp, status: p.status } : null
      }
    }
    sh.weather = ({ sunnyday: "sun", desolateland: "sun", raindance: "rain", primordialsea: "rain", sandstorm: "sand", snow: "hail", hail: "hail", snowscape: "hail" })[state.weather] || ""
    return sh
  }

  // Starts the next battle of the challenge, or rebuilds the one in progress.
  function startBattle() {
    mutate(function(s) { Tower.battle(s) })
    resumeBattle()
  }

  function resumeBattle() {
    var opts = Tower.battleOptions(host.view, "You")
    if (!opts) { screen = "challenge"; return }
    var o = Tower.trainer(Tower.run(host.view).battle.opponent)
    foeName = o.cls + " " + o.name.toUpperCase()
    battleKey = opts.key
    format = opts.format
    shown = emptyShown(null)
    battleState = null
    request = null
    result = null
    queue = []
    stepTimer.stop()
    playing = false
    boxText = opts.input.length ? "" : "Loading…"
    loading = true
    screen = "battle"
    send({ op: "start", battle: opts })
    battleScene.forceActiveFocus()
  }

  function onEngine(m) {
    if (m.error === "lost" && screen === "battle") { resumeBattle(); return }
    if (m.op === "ping" || m.op === "pack" || m.op === "close") return
    if (m.key !== battleKey) return
    if (m.error && !(m.steps || []).length) {
      if (m.stack) console.warn("Battle Tower:", m.error, m.stack)
      battleScene.hint = m.error
      request = m.request || request
      return
    }
    loading = false
    if (m.input) mutate(function(s) { Tower.saveInput(s, m.input) })
    moveInfo = m.moveInfo || moveInfo
    var steps = (m.steps || []).slice()
    if (m.op === "start" && !steps.length && m.state && m.state.turn > 0) {
      // Rebuilt a battle in progress: show it as it is.
      shown = shownOf(m.state)
      battleState = m.state
      boxText = ""
    }
    if (m.op === "start" && m.request && m.request.teamPreview && !(Tower.run(host.view).battle.input || []).length)
      steps.unshift({ t: "text", text: foeName + " would like to battle!" })
    reply = m
    queue = queue.concat(steps)
    if (m.state && !battleState) battleState = m.state
    if (!playing) nextStep()
  }

  function choose(choice) {
    battleScene.hint = ""
    request = null
    boxText = ""
    send({ op: "choose", key: battleKey, choice: choice })
  }

  function forfeit() {
    request = null
    send({ op: "forfeit", key: battleKey })
  }

  Timer { id: stepTimer; onTriggered: win.nextStep() }

  function nextStep() {
    if (!queue.length) { playing = false; stepsDone(); return }
    playing = true
    var st = queue[0]
    queue = queue.slice(1)
    var delay = applyStep(st)
    stepTimer.interval = Math.max(60, delay * (fast ? 0.5 : 1))
    stepTimer.restart()
  }

  // Skips to the next line when you click or press A.
  function advance() {
    if (result && !playing) return
    if (playing) { stepTimer.stop(); nextStep() }
  }

  // Applies one step to what the scene shows; returns how long to wait after it.
  function applyStep(st) {
    var sh = JSON.parse(JSON.stringify(shown || emptyShown(null)))
    var act = st.side !== undefined && sh.sides[st.side] ? sh.sides[st.side].active : null
    var mon = act ? act[st.slot] : null
    var wait = 0
    if (st.t === "switch" && act) {
      act[st.slot] = st.mon
      wait = 650
    } else if (st.t === "hp" && mon) {
      var before = mon.hp
      mon.hp = st.hp
      if (st.maxhp) mon.maxhp = st.maxhp
      if (st.status !== undefined) mon.status = st.status === "fnt" ? "" : st.status
      if (st.hp < before && !st.text) battleScene.animate({ t: "hit", side: st.side, slot: st.slot })
      wait = 480
    } else if (st.t === "faint" && mon) {
      wait = 700
    } else if (st.t === "status" && mon) {
      mon.status = st.status
    } else if (st.t === "species" && mon && st.species) {
      mon.species = st.species
    } else if (st.t === "weather") {
      sh.weather = st.weather
    } else if (st.t === "move") {
      wait = 300
    }
    shown = sh
    if (st.t === "switch" || st.t === "move" || st.t === "faint") battleScene.animate(st)
    if (st.t === "faint" && act) {
      // Gone once it has dropped out of sight.
      var side = st.side, slot = st.slot
      Qt.callLater(function() { faintTimer.side = side; faintTimer.slot = slot; faintTimer.restart() })
    }
    if (st.text) {
      boxText = st.text
      wait = Math.max(wait, 650 + st.text.length * 18)
    }
    return wait
  }

  Timer {
    id: faintTimer
    property int side: 0
    property int slot: 0
    interval: 420
    onTriggered: {
      var sh = JSON.parse(JSON.stringify(win.shown))
      if (sh.sides[side] && sh.sides[side].active[slot] && sh.sides[side].active[slot].hp <= 0) {
        sh.sides[side].active[slot] = null
        win.shown = sh
      }
    }
  }

  function stepsDone() {
    var m = reply
    if (!m) return
    if (m.state) {
      battleState = m.state
      // Keep the scene in line with the simulator (fainted Pokémon gone, exact HP).
      if (m.state.turn > 0) shown = shownOf(m.state)
    }
    if (m.state && m.state.ended) { endBattle(m.state.winner); return }
    request = m.request
  }

  function endBattle(winner) {
    var won = winner === 0
    var res = mutate(function(s, t) { return Tower.finishBattle(s, won, t) })
    send({ op: "close", key: battleKey })
    if (!res) { screen = "challenge"; return }
    var lines = []
    if (won) {
      lines.push("You defeated " + res.trainer + "!")
      lines.push("+" + res.bp + " BP" + (res.firstWin ? " (first win bonus)" : ""))
      if (res.setDone) {
        lines.push("Challenge cleared: " + Tower.RUN_LENGTH + " wins in a row!")
        if (res.money) lines.push("+₽" + res.money)
        if (res.firstClear) lines.push("First clear of this tier!")
        if (res.unlocked) lines.push("Unlocked: " + res.unlocked + "!")
      } else lines.push("Win " + res.wins + " of " + Tower.RUN_LENGTH + ".")
    } else {
      lines.push(res.trainer + " won the battle.")
      lines.push("Your challenge ends with " + res.wins + (res.wins === 1 ? " win." : " wins."))
    }
    var actions = !won ? [{ id: "lobby", label: "BACK" }]
      : res.setDone ? [{ id: "continue", label: "KEEP GOING" }, { id: "leave", label: "CASH OUT" }]
      : [{ id: "next", label: "NEXT BATTLE" }, { id: "rest", label: "TAKE A BREAK" }]
    result = { won: won, lines: lines, actions: actions }
  }

  function resultAction(what) {
    result = null
    if (what === "next") { startBattle(); return }
    if (what === "continue") {
      mutate(function(s, t) { Tower.continueRun(s, t) })
      startBattle()
      return
    }
    if (what === "leave") mutate(function(s, t) { Tower.endRun(s, "cleared", t) })
    screen = "challenge"
  }

  function quitRun() {
    mutate(function(s, t) { Tower.quit(s, t) })
    notice = "You left the challenge."
  }

  // ---- Little building blocks ----

  component Label: Text {
    color: win.ink
    font.family: win.font
    font.pixelSize: 15
  }

  component Panel: Rectangle {
    color: win.paper
    radius: 8
    border.width: 3
    border.color: win.frame
  }

  component GButton: Rectangle {
    id: gb
    property string label: ""
    property bool on: false
    property bool enabledLook: true
    property color tint: win.frame
    signal clicked()
    implicitWidth: gbText.implicitWidth + 28
    height: 34
    radius: 6
    color: !enabledLook ? "#c8ccd0" : on ? Qt.lighter(tint, 1.55) : gbArea.containsMouse ? "#ffffff" : "#e8eef4"
    border.width: 2
    border.color: on ? win.accent : tint
    opacity: enabledLook ? 1 : 0.6
    Label { id: gbText; anchors.centerIn: parent; text: gb.label; font.pixelSize: 15 }
    MouseArea { id: gbArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: gb.clicked() }
  }

  component Stars: Label {
    property int count: 0
    property int max: 0
    text: Tower.starText(count) + (max > count ? "☆".repeat(max - count) : "")
    color: win.gold
    style: Text.Outline
    styleColor: "#806020"
  }

  component Mon: PokeSprite {
    fitWidth: 40
    fitHeight: 36
    maxPixel: 2
    integerScale: true
  }

  // Everything on screen (one item, so it can be grabbed in tests).
  Item {
    id: canvas
    anchors.fill: parent

    // ---- Screens ----

    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0; color: "#24384e" }
        GradientStop { position: 1; color: "#152230" }
      }
      visible: win.screen !== "battle"
    }

    // Header: title, tabs, BP and money
    Item {
      id: header
      visible: win.screen !== "battle"
      x: 20; y: 14
      width: parent.width - 40
      height: 44

      Label {
        id: titleText
        anchors.verticalCenter: parent.verticalCenter
        text: "BATTLE TOWER"
        color: "#f8f8f8"
        font.pixelSize: 26
        style: Text.Raised
        styleColor: "#0a1520"
      }
      Row {
        anchors.left: titleText.right
        anchors.leftMargin: 26
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Repeater {
          model: [{ id: "challenge", label: "Challenge" }, { id: "teams", label: "Teams" }, { id: "counter", label: "BP Counter" }, { id: "records", label: "Records" }]
          delegate: GButton {
            label: modelData.label
            on: win.screen === modelData.id
            onClicked: { win.screen = modelData.id; win.notice = ""; win.itemSlot = -1 }
          }
        }
      }
      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 16
        Label { text: Tower.bp(win.view) + " BP"; color: win.gold; font.pixelSize: 20 }
        Label { text: "₽" + Pet.money(win.view).toLocaleString(Qt.locale("en_US"), "f", 0); color: "#f8f8f8"; font.pixelSize: 20 }
      }
    }

    Label {
      visible: win.screen !== "battle" && win.notice !== ""
      x: 20; anchors.bottom: parent.bottom; anchors.bottomMargin: 10
      text: win.notice
      color: win.gold
    }

    // ---- Challenge ----
    Item {
      visible: win.screen === "challenge"
      x: 20; y: 72
      width: parent.width - 40
      height: parent.height - 112

      // A challenge in progress
      Panel {
        visible: !!win.run
        anchors.fill: parent
        Column {
          x: 28; y: 24
          width: parent.width - 56
          spacing: 14
          Label { text: "CHALLENGE IN PROGRESS"; color: win.accent; font.pixelSize: 22 }
          Label { text: win.run ? Tower.runTitle(win.run) + "  ·  " + win.run.name : ""; font.pixelSize: 18 }
          Label {
            readonly property var o: win.run ? Tower.opponent(win.view) : null
            text: !win.run ? "" : win.run.wins >= Tower.RUN_LENGTH ? "All " + Tower.RUN_LENGTH + " battles won!"
                : "Battle " + (win.run.wins + 1) + " of " + Tower.RUN_LENGTH
                  + (win.run.streak ? "  ·  streak: " + (win.run.streak * Tower.RUN_LENGTH + win.run.wins) + " wins" : "")
                  + (o ? "  ·  next: " + Tower.title(o) + (win.run.wins === Tower.RUN_LENGTH - 1 ? "  (boss)" : "") : "")
            font.pixelSize: 17
          }
          Row {
            spacing: 6
            Repeater {
              model: Tower.RUN_LENGTH
              delegate: Rectangle {
                width: 34; height: 34; radius: 17
                color: win.run && index < win.run.wins ? win.accent : "#d8dee6"
                border.width: 2; border.color: index === Tower.RUN_LENGTH - 1 ? win.gold : win.frame
                Label { anchors.centerIn: parent; text: index === Tower.RUN_LENGTH - 1 ? "★" : index + 1; color: win.run && index < win.run.wins ? "#ffffff" : win.ink }
              }
            }
          }
          Row {
            spacing: 6
            Repeater {
              model: win.run ? win.run.refs : []
              delegate: Mon { slug: win.view.pets[modelData] ? win.view.pets[modelData].species : ""; shiny: !!win.view.pets[modelData] && win.view.pets[modelData].shiny; fitWidth: 56; fitHeight: 48 }
            }
          }
          Label { text: win.run ? "Earned so far: " + win.run.earned.bp + " BP" + (win.run.earned.money ? " and ₽" + win.run.earned.money : "") : ""; opacity: 0.8 }
          Row {
            spacing: 12
            GButton {
              label: win.run && win.run.battle ? "Resume the battle" : "Next battle"
              tint: win.accent
              onClicked: win.run.battle ? win.resumeBattle() : win.startBattle()
            }
            GButton { label: "Give up"; onClicked: win.quitRun() }
          }
          Label {
            width: parent.width; wrapMode: Text.WordWrap; opacity: 0.7; font.pixelSize: 13
            text: "You can close this window at any time: the challenge, and the battle in progress, wait for you here."
          }
        }
      }

      // Choosing a challenge
      Row {
        visible: !win.run
        anchors.fill: parent
        spacing: 16

        // Towers
        Panel {
          width: 230
          height: parent.height
          Column {
            x: 12; y: 12
            width: parent.width - 24
            spacing: 6
            Label { text: "TOWERS"; color: win.frame; font.pixelSize: 17 }
            Repeater {
              model: Tower.towers()
              delegate: Rectangle {
                readonly property bool open: Tower.towerOpen(win.view, modelData.id, win.format)
                width: parent.width; height: 40; radius: 6
                color: win.towerId === modelData.id ? "#fff4d0" : towerArea.containsMouse ? "#eef2f6" : "transparent"
                border.width: win.towerId === modelData.id ? 2 : 0; border.color: win.gold
                Label { x: 10; anchors.verticalCenter: parent.verticalCenter; text: (open ? "" : "🔒 ") + modelData.region; opacity: open ? 1 : 0.5; font.pixelSize: 17 }
                Label {
                  anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                  text: Tower.cleared(win.view, modelData.id, win.format) + "/" + modelData.tiers.length; opacity: 0.6; font.pixelSize: 13
                }
                MouseArea { id: towerArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { win.towerId = modelData.id; win.tier = 1; win.pickDefaults(); win.notice = "" } }
              }
            }
          }
        }

        // Tiers of the chosen tower
        Panel {
          width: parent.width - 230 - 340 - 32
          height: parent.height
          Column {
            x: 16; y: 14
            width: parent.width - 32
            spacing: 10
            Label { text: Tower.towerTitle(win.towerId).toUpperCase(); font.pixelSize: 21; color: win.accent }
            Row {
              spacing: 8
              Repeater {
                model: Tower.FORMATS
                delegate: GButton { label: Tower.FORMAT_NAMES[modelData] + " (" + Tower.PICK[modelData] + " of 6)"; on: win.format === modelData
                                    onClicked: { win.format = modelData; win.tier = 1; win.pickDefaults() } }
              }
            }
            Label {
              visible: !Tower.towerOpen(win.view, win.towerId, win.format)
              width: parent.width; wrapMode: Text.WordWrap
              text: "Clear a Master tier in any other tower (" + Tower.FORMAT_NAMES[win.format] + ") to open this one. Its trainers come from Pokémon Radical Red, and they don't hold back."
            }
            Repeater {
              model: Tower.towerOpen(win.view, win.towerId, win.format) ? Tower.tower(win.towerId).tiers : []
              delegate: Rectangle {
                readonly property int t: index + 1
                readonly property bool open: Tower.tierOpen(win.view, win.towerId, win.format, t)
                readonly property bool done: Tower.cleared(win.view, win.towerId, win.format) >= t
                width: parent.width; height: 58; radius: 6
                color: win.tier === t ? "#fff4d0" : "#eef2f6"
                border.width: 2; border.color: win.tier === t ? win.gold : "#c8d0d8"
                opacity: open ? 1 : 0.5
                Column {
                  x: 12; anchors.verticalCenter: parent.verticalCenter
                  spacing: 2
                  Row {
                    spacing: 10
                    Label { text: modelData.name; font.pixelSize: 18 }
                    Stars { count: modelData.stars; font.pixelSize: 16 }
                  }
                  Label {
                    text: (done ? "Cleared ✓" : open ? "Open" : "🔒 Clear " + Tower.tierName(win.towerId, t - 1) + " first")
                          + "  ·  " + Tower.bpPerWin(win.towerId, t) + " BP per win"
                          + (Tower.bestStreak(win.view, win.towerId, win.format, t) ? "  ·  best: " + Tower.bestStreak(win.view, win.towerId, win.format, t) : "")
                    font.pixelSize: 13; opacity: 0.75
                  }
                }
                MouseArea { anchors.fill: parent; cursorShape: open ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: if (parent.open) win.tier = parent.t }
              }
            }
            Label {
              width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 13; opacity: 0.75
              visible: Tower.towerOpen(win.view, win.towerId, win.format)
              text: "7 battles, the last against a boss. Everybody fights at Lv. " + Tower.MIN_LEVEL + "; your Pokémon are healed between battles and no items can be used. "
                  + "Clearing a challenge pays " + Tower.SET_BONUS + "× the BP of a win and ₽" + Tower.MONEY_PER_SET * Tower.level(win.towerId, win.tier)
                  + ", and the first clear of a tier " + Tower.FIRST_CLEAR_BONUS + "× more."
            }
          }
        }

        // Team to bring
        Panel {
          width: 340
          height: parent.height
          Column {
            x: 14; y: 14
            width: parent.width - 28
            spacing: 8
            Label { text: "YOUR TEAM"; color: win.frame; font.pixelSize: 17 }
            Label {
              visible: Tower.teams(win.view).length === 0
              width: parent.width; wrapMode: Text.WordWrap
              text: "You don't have a battle team yet. Build one in the Teams tab with Pokémon at Lv. " + Tower.MIN_LEVEL + " or more."
            }
            Repeater {
              model: Tower.teams(win.view)
              delegate: Rectangle {
                width: parent.width; height: 70; radius: 6
                color: win.teamIndex === index ? "#fff4d0" : "#eef2f6"
                border.width: 2; border.color: win.teamIndex === index ? win.gold : "#c8d0d8"
                Label { x: 10; y: 6; text: modelData.name + "  (" + modelData.members.length + ")"; font.pixelSize: 15 }
                Row {
                  x: 8; y: 28
                  spacing: 2
                  Repeater {
                    model: modelData.members
                    delegate: Mon { slug: win.view.pets[modelData.ref] ? win.view.pets[modelData.ref].species : ""; fitWidth: 46; fitHeight: 36 }
                  }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.teamIndex = index }
              }
            }
            Label {
              readonly property string problem: Tower.teams(win.view).length ? Tower.teamProblem(win.view, win.teamIndex, win.format) : ""
              visible: problem !== ""
              width: parent.width; wrapMode: Text.WordWrap
              text: problem; color: win.accent; font.pixelSize: 14
            }
            GButton {
              width: parent.width
              label: "Start the challenge"
              tint: win.accent
              enabledLook: Tower.teams(win.view).length > 0 && Tower.teamProblem(win.view, win.teamIndex, win.format) === ""
                           && Tower.tierOpen(win.view, win.towerId, win.format, win.tier)
              onClicked: {
                var tw = win.towerId, f = win.format, t = win.tier, ti = win.teamIndex
                var err = win.mutate(function(s, now) { return Tower.start(s, tw, f, t, ti, now) })
                if (err) { win.notice = err; return }
                win.startBattle()
              }
            }
          }
        }
      }
    }

    // ---- Teams ----
    Row {
      visible: win.screen === "teams"
      x: 20; y: 72
      width: parent.width - 40
      height: parent.height - 112
      spacing: 16


      Panel {
        width: 190
        height: parent.height
        Column {
          x: 12; y: 12
          width: parent.width - 24
          spacing: 6
          Label { text: "TEAMS"; color: win.frame; font.pixelSize: 17 }
          Repeater {
            model: Tower.teams(win.view)
            delegate: Rectangle {
              width: parent.width; height: 38; radius: 6
              color: win.editTeam === index ? "#fff4d0" : teamArea.containsMouse ? "#eef2f6" : "transparent"
              border.width: win.editTeam === index ? 2 : 0; border.color: win.gold
              Label { x: 10; anchors.verticalCenter: parent.verticalCenter; text: modelData.name; font.pixelSize: 16 }
              Label { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: modelData.members.length + "/6"; opacity: 0.6; font.pixelSize: 13 }
              MouseArea { id: teamArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { win.editTeam = index; win.itemSlot = -1 } }
            }
          }
          GButton {
            width: parent.width
            visible: Tower.teams(win.view).length < Tower.TEAMS
            label: "+ New team"
            onClicked: { var i = win.mutate(function(s) { return Tower.newTeam(s) }); if (i >= 0) win.editTeam = i }
          }
        }
      }

      // The team: six slots
      Panel {
        width: parent.width - 190 - 320 - 32
        height: parent.height
        Column {
          visible: !!win.editedTeam
          x: 14; y: 12
          width: parent.width - 28
          spacing: 8
          Row {
            spacing: 8
            Rectangle {
              width: 220; height: 34; radius: 6; color: "#ffffff"; border.width: 2; border.color: win.frame
              TextInput {
                id: nameInput
                anchors.fill: parent; anchors.margins: 6
                text: win.editedTeam ? win.editedTeam.name : ""
                font.family: win.font; font.pixelSize: 17; color: win.ink
                maximumLength: 16
                selectByMouse: true
                onEditingFinished: { var i = win.editTeam, t = text; win.mutate(function(s) { Tower.renameTeam(s, i, t) }) }
              }
            }
            GButton {
              label: "Delete"
              onClicked: {
                var i = win.editTeam
                var ok = win.mutate(function(s) { return Tower.deleteTeam(s, i) })
                if (!ok) win.notice = "This team is in a challenge."
                win.editTeam = Math.max(0, i - 1)
              }
            }
          }
          Label { text: "Click a Pokémon on the right to add it. Order = the order shown at Team Preview."; font.pixelSize: 13; opacity: 0.7; width: parent.width; wrapMode: Text.WordWrap }
          Repeater {
            model: win.editedTeam ? win.editedTeam.members : []
            delegate: Rectangle {
              id: memberCard
              readonly property var pet: win.view.pets[modelData.ref]
              width: parent.width; height: 66; radius: 6
              color: "#eef2f6"; border.width: 2; border.color: win.itemSlot === index ? win.gold : "#c8d0d8"
              Mon { x: 6; anchors.verticalCenter: parent.verticalCenter; slug: memberCard.pet ? memberCard.pet.species : ""; shiny: !!memberCard.pet && memberCard.pet.shiny; fitWidth: 48; fitHeight: 44 }
              Label {
                x: 60; y: 9
                width: itemBox.x - x - 6; elide: Text.ElideRight
                text: memberCard.pet ? Pet.name(memberCard.pet.species) + "  Lv. " + Pet.level(memberCard.pet) : "?"
                font.pixelSize: 16
              }
              Label {
                x: 60; y: 42
                width: parent.width - x - 8; elide: Text.ElideRight
                text: memberCard.pet ? Pet.abilityName(Pet.abilityOf(memberCard.pet.species, memberCard.pet.ability)) + " · " + Pet.natureName(memberCard.pet.nature || 0)
                                       + " · " + (memberCard.pet.moves || []).map(Pet.moveName).join(", ") : ""
                font.pixelSize: 12; opacity: 0.7
              }
              // Held item
              Rectangle {
                id: itemBox
                anchors.right: moveButtons.left; anchors.rightMargin: 6; y: 5
                width: 136; height: 32; radius: 6; color: "#ffffff"; border.width: 1; border.color: win.frame
                ItemSprite { x: 2; anchors.verticalCenter: parent.verticalCenter; item: modelData.item; visible: modelData.item !== "" }
                Label { x: modelData.item ? 34 : 10; anchors.verticalCenter: parent.verticalCenter; width: parent.width - x - 6; elide: Text.ElideRight
                        text: modelData.item ? Pet.itemName(modelData.item) : "No item ▾"; font.pixelSize: 13; opacity: modelData.item ? 1 : 0.6 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.itemSlot = win.itemSlot === index ? -1 : index }
              }
              Row {
                id: moveButtons
                anchors.right: parent.right; anchors.rightMargin: 6; y: 5
                spacing: 3
                GButton { label: "▲"; width: 30; height: 32; onClicked: { var i = win.editTeam, k = index; win.mutate(function(s) { Tower.moveMember(s, i, k, k - 1) }) } }
                GButton { label: "▼"; width: 30; height: 32; onClicked: { var i = win.editTeam, k = index; win.mutate(function(s) { Tower.moveMember(s, i, k, k + 1) }) } }
                GButton { label: "✕"; width: 30; height: 32; onClicked: { var i = win.editTeam, r = modelData.ref; win.itemSlot = -1; win.mutate(function(s) { Tower.toggleMember(s, i, r) }) } }
              }
            }
          }
        }
        Label {
          visible: !win.editedTeam
          anchors.centerIn: parent
          text: "Create a team to begin."
        }
      }

      // Right: Pokémon that can enter, or items to hold
      Panel {
        width: 320
        height: parent.height
        Column {
          x: 12; y: 12
          width: parent.width - 24
          spacing: 6
          Label { text: win.itemSlot >= 0 ? "HOLD ITEM" : "LV. " + Tower.MIN_LEVEL + "+ POKéMON"; color: win.frame; font.pixelSize: 17 }
          Label {
            visible: win.itemSlot < 0 && Tower.candidates(win.view).length === 0
            width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 14
            text: "None of your Pokémon is Lv. " + Tower.MIN_LEVEL + " yet. Train them, feed them candies or send them on expeditions!"
          }
          Label {
            visible: win.itemSlot >= 0 && Tower.holdableItems(win.view).length === 0
            width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 14
            text: "You don't have any item to hold. Held items are sold at the BP Counter; berries and a few other items from your bag work too."
          }
        }
        Flickable {
          x: 12; y: 70
          width: parent.width - 24
          height: parent.height - 82
          contentHeight: pickGrid.height
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          Grid {
            id: pickGrid
            width: parent.width
            columns: win.itemSlot >= 0 ? 1 : 3
            spacing: 6
            Repeater {
              model: win.screen !== "teams" ? [] : win.itemSlot >= 0 ? [""].concat(Tower.holdableItems(win.view)) : Tower.candidates(win.view)
              delegate: Rectangle {
                readonly property bool items: win.itemSlot >= 0
                readonly property var team: Tower.teams(win.view)[win.editTeam]
                readonly property bool inTeam: !items && !!team && team.members.some(function(m) { return m.ref === modelData })
                width: items ? pickGrid.width : (pickGrid.width - 12) / 3
                height: items ? 40 : 86
                radius: 6
                color: inTeam ? "#fff4d0" : pickArea.containsMouse ? "#ffffff" : "#eef2f6"
                border.width: 2; border.color: inTeam ? win.gold : "#c8d0d8"
                Mon {
                  visible: !parent.items
                  anchors.horizontalCenter: parent.horizontalCenter; y: 6
                  slug: !parent.items && win.view.pets[modelData] ? win.view.pets[modelData].species : ""
                  shiny: !parent.items && !!win.view.pets[modelData] && win.view.pets[modelData].shiny
                  fitWidth: 64; fitHeight: 50
                }
                Label {
                  visible: !parent.items
                  anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                  width: parent.width - 6; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                  text: !parent.items && win.view.pets[modelData] ? Pet.name(win.view.pets[modelData].species) + " " + Pet.level(win.view.pets[modelData]) : ""
                  font.pixelSize: 12
                }
                ItemSprite { visible: parent.items && modelData !== ""; x: 6; anchors.verticalCenter: parent.verticalCenter; item: parent.items ? modelData : "" }
                Label {
                  visible: parent.items
                  x: 44; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 50; elide: Text.ElideRight
                  text: !parent.items ? "" : modelData === "" ? "No item" : Pet.itemName(modelData) + "  ×" + (win.view.bag[modelData] || 0)
                  font.pixelSize: 14
                }
                MouseArea {
                  id: pickArea
                  anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    var i = win.editTeam, v = modelData
                    if (parent.items) {
                      var slot = win.itemSlot
                      var e = win.mutate(function(s) { return Tower.setItem(s, i, slot, v) })
                      win.notice = e || ""
                      if (!e) win.itemSlot = -1
                    } else {
                      if (!Tower.teams(win.view)[i]) i = win.mutate(function(s) { return Tower.newTeam(s) })
                      win.editTeam = i
                      var err = win.mutate(function(s) { return Tower.toggleMember(s, i, v) })
                      win.notice = err || ""
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    // ---- BP Counter ----
    Row {
      visible: win.screen === "counter"
      x: 20; y: 72
      width: parent.width - 40
      height: parent.height - 112
      spacing: 16

      Panel {
        width: parent.width - 340 - 16
        height: parent.height
        Row {
          id: shelfTabs
          x: 12; y: 12
          spacing: 6
          Repeater {
            model: win.shelves
            delegate: GButton { label: modelData.name; on: win.shelf === index; onClicked: { win.shelf = index; win.counterItem = "" } }
          }
        }
        Flickable {
          x: 12; y: 58
          width: parent.width - 24
          height: parent.height - 70
          contentHeight: counterGrid.height
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          Grid {
            id: counterGrid
            width: parent.width
            columns: 4
            spacing: 6
            Repeater {
              model: win.screen === "counter" ? (win.shelves[win.shelf] || { items: [] }).items : []
              delegate: Rectangle {
                width: (counterGrid.width - 18) / 4; height: 64; radius: 6
                color: win.counterItem === modelData ? "#fff4d0" : cArea.containsMouse ? "#ffffff" : "#eef2f6"
                border.width: 2; border.color: win.counterItem === modelData ? win.gold : "#c8d0d8"
                ItemSprite { x: 6; y: 6; item: modelData }
                Label { x: 40; y: 6; width: parent.width - 46; elide: Text.ElideRight; text: Pet.itemName(modelData); font.pixelSize: 13 }
                Label { x: 40; y: 26; text: Tower.bpPrice(modelData) + " BP"; color: "#a07818"; font.pixelSize: 14 }
                Label { anchors.right: parent.right; anchors.rightMargin: 6; anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                        visible: (win.view.bag[modelData] || 0) > 0; text: "×" + (win.view.bag[modelData] || 0); font.pixelSize: 12; opacity: 0.6 }
                MouseArea { id: cArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.counterItem = modelData }
              }
            }
          }
        }
      }
      Panel {
        width: 340
        height: parent.height
        Column {
          x: 16; y: 16
          width: parent.width - 32
          spacing: 10
          Label { text: "BP COUNTER"; color: win.frame; font.pixelSize: 17 }
          Label {
            width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 14
            text: "Battle Points are won at the Tower. Held items are only found here; rare TMs and mints change every day."
            opacity: 0.75
          }
          ItemSprite { visible: win.counterItem !== ""; item: win.counterItem; scale_: 2 }
          Label { visible: win.counterItem !== ""; text: Pet.itemName(win.counterItem); font.pixelSize: 19 }
          Label { visible: win.counterItem !== ""; width: parent.width; wrapMode: Text.WordWrap; text: Pet.itemText(win.counterItem); font.pixelSize: 14 }
          Label { visible: win.counterItem !== ""; text: Tower.bpPrice(win.counterItem) + " BP  ·  you have " + (win.view.bag[win.counterItem] || 0); color: "#a07818" }
          GButton {
            visible: win.counterItem !== ""
            width: parent.width
            label: "Buy for " + Tower.bpPrice(win.counterItem) + " BP"
            tint: win.accent
            enabledLook: Tower.bp(win.view) >= Tower.bpPrice(win.counterItem)
            onClicked: {
              var id = win.counterItem
              var err = win.mutate(function(s, t) { return Tower.buy(s, id, 1, t) })
              win.notice = err || ("You got " + Pet.itemName(id) + "!")
            }
          }
        }
      }
    }

    // ---- Records ----
    Row {
      visible: win.screen === "records"
      x: 20; y: 72
      width: parent.width - 40
      height: parent.height - 112
      spacing: 16

      Panel {
        width: (parent.width - 16) / 2
        height: parent.height
        Flickable {
          x: 14; y: 12
          width: parent.width - 28
          height: parent.height - 24
          contentHeight: recordColumn.height
          clip: true
          Column {
            id: recordColumn
            width: parent.width
            spacing: 6
            Label { text: "TOWERS"; color: win.frame; font.pixelSize: 17 }
            Label { text: (win.view.tower ? win.view.tower.wins || 0 : 0) + " wins in " + (win.view.tower ? win.view.tower.battles || 0 : 0) + " battles"; opacity: 0.75 }
            Repeater {
              model: win.screen === "records" ? Tower.towers() : []
              delegate: Column {
                id: towerRecord
                required property var modelData
                width: recordColumn.width
                spacing: 2
                Label { text: towerRecord.modelData.name; font.pixelSize: 16; color: win.accent }
                Repeater {
                  model: Tower.FORMATS
                  delegate: Label {
                    readonly property string f: modelData
                    readonly property var tw: towerRecord.modelData
                    font.pixelSize: 13
                    text: Tower.FORMAT_NAMES[f] + ": " + Tower.cleared(win.view, tw.id, f) + "/" + tw.tiers.length + " tiers cleared"
                          + tw.tiers.map(function(t, i) { var b = Tower.bestStreak(win.view, tw.id, f, i + 1); return b ? "  ·  " + t.name + " best " + b : "" }).join("")
                  }
                }
              }
            }
          }
        }
      }
      Panel {
        width: (parent.width - 16) / 2
        height: parent.height
        Flickable {
          x: 14; y: 12
          width: parent.width - 28
          height: parent.height - 24
          contentHeight: historyColumn.height
          clip: true
          Column {
            id: historyColumn
            width: parent.width
            spacing: 6
            Label { text: "LAST CHALLENGES"; color: win.frame; font.pixelSize: 17 }
            Label { visible: !(win.view.tower && win.view.tower.history.length); text: "No challenge yet."; opacity: 0.7 }
            Repeater {
              model: win.screen === "records" && win.view.tower ? win.view.tower.history : []
              delegate: Rectangle {
                width: historyColumn.width; height: 50; radius: 6; color: "#eef2f6"
                Label { x: 10; y: 5; text: Tower.towerTitle(modelData.tower) + " · " + Tower.FORMAT_NAMES[modelData.format] + " · " + Tower.tierName(modelData.tower, modelData.tier); font.pixelSize: 14 }
                Label {
                  x: 10; y: 26; font.pixelSize: 12; opacity: 0.75
                  text: ({ cleared: "Cleared", lost: "Lost", quit: "Left" })[modelData.result] + " with " + modelData.wins + " wins · " + modelData.team
                        + " · +" + modelData.bp + " BP" + (modelData.money ? " · +₽" + modelData.money : "")
                        + " · " + new Date(modelData.at).toLocaleDateString(Qt.locale(), Locale.ShortFormat)
                }
              }
            }
          }
        }
      }
    }

    // ---- Battle ----
    BattleScene {
      id: battleScene
      visible: win.screen === "battle"
      anchors.fill: parent
      focus: visible
      host: win.host
      fontFamily: win.font
      shown: win.shown
      battleState: win.battleState
      request: win.request
      moveInfo: win.moveInfo
      boxText: win.boxText
      format: win.format
      foeName: win.foeName
      busy: win.playing || win.loading
      result: win.result
      onChoose: function(choice) { win.choose(choice) }
      onForfeit: win.forfeit()
      onAdvance: win.advance()
      onResultAction: function(what) { win.resultAction(what) }
    }

    // Speed toggle and a way back to the lobby while a battle waits for you
    Row {
      visible: win.screen === "battle"
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 8
      spacing: 6
      GButton { label: win.fast ? "Fast text" : "Normal text"; height: 28; onClicked: win.fast = !win.fast }
      GButton { label: "Lobby"; height: 28; enabledLook: !win.playing; onClicked: if (!win.playing) { win.result = null; win.screen = "challenge" } }
    }
  }
}
