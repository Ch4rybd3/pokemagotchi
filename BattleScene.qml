import QtQuick
import "Tower.js" as Tower

// A Battle Tower battle, drawn like the Gen 3 games: a 240×160 scene scaled up,
// the HP boxes, the text box and the FIGHT / BAG / POKéMON / RUN menu.
// TowerWindow feeds it the battle as it plays (shown, boxText) and the requests
// of the simulator; the scene answers with choose(), forfeit() and so on.
FocusScope {
  id: scene

  required property var host            // the bar widget, for its type colors
  property string fontFamily: ""
  property var shown: null              // { sides: [{ active: [mon] }, { active: [mon] }], weather }
  property var battleState: null        // the simulator's last full state
  property var request: null            // what the simulator asks from you, or null
  property var moveInfo: ({})
  property string boxText: ""
  property string format: "singles"
  property string foeName: ""
  property bool busy: false             // steps still playing
  property var result: null             // the battle's outcome, once it is over
  property string error: ""

  signal choose(string choice)
  signal forfeit()
  signal advance()                      // the player wants the text to move on
  signal resultAction(string what)

  readonly property bool doubles: format === "doubles"
  readonly property int slots: doubles ? 2 : 1
  readonly property real u: Math.max(1, Math.min(width / 240, height / 160))
  function px(v) { return v * u }

  // ---- Colors (Emerald-ish) ----
  readonly property color ink: "#404048"
  readonly property color inkShadow: "#d0d0c8"
  readonly property color boxFill: "#f8f8f0"
  readonly property color boxFrame: "#506878"
  readonly property color textFill: "#284058"
  readonly property color textFrame: "#c8a050"

  // ---- Menus ----
  // "" | "preview" | "action" | "fight" | "target" | "party" | "run"
  property string menu: ""
  property int cursor: 0
  property int slot: 0                  // the Pokémon you choose for, in Doubles
  property var parts: []                // choices made so far this turn
  property int pendingMove: -1          // a move waiting for its target (Doubles)
  property bool forced: false           // a fainted Pokémon must be replaced
  property var picked: []               // Team Preview: your order
  property string hint: ""

  readonly property bool ready: !!request && !busy && !result
  onReadyChanged: if (ready) beginTurn()
  onBusyChanged: if (busy) menu = ""
  onResultChanged: if (result) menu = ""
  onRequestChanged: if (request && !busy && !result) beginTurn()

  function mon(side, i) {
    var s = shown && shown.sides ? shown.sides[side] : null
    return s && s.active ? s.active[i] || null : null
  }
  function party() { return request && request.side ? request.side.pokemon : [] }
  function fainted(p) { return !p || /fnt/.test(p.condition) }
  function hpOf(p) {
    var m = /^(\d+)\/(\d+)/.exec(p ? p.condition : "")
    return m ? { hp: Number(m[1]), max: Number(m[2]) } : { hp: 0, max: 1 }
  }
  function nameOf(p) { return p ? String(p.ident).replace(/^p\d[a-c]?:\s*/, "") : "" }
  // Item name of your index-th Pokémon (from the simulator's state, which has full names).
  function itemAt(i) {
    var p = battleState && battleState.sides ? battleState.sides[0].party[i] : null
    return p && p.item ? p.item : "No item"
  }
  function slugOfDetails(details) { return Tower.slugOf(String(details || "").split(",")[0]) }

  function needsAction(i) {
    if (!request || !request.active || !request.active[i]) return false
    var p = party()[i]
    return !!p && !fainted(p) && !request.active[i].commanding
  }

  function beginTurn() {
    if (!request) return
    parts = []
    pendingMove = -1
    hint = ""
    cursor = 0
    if (request.teamPreview) { picked = []; menu = "preview"; return }
    if (request.forceSwitch) {
      forced = true
      slot = request.forceSwitch.indexOf(true)
      parts = request.forceSwitch.map(function(f) { return f ? "" : "pass" })
      menu = "party"
      return
    }
    forced = false
    slot = 0
    while (slot < slots && !needsAction(slot)) { parts[slot] = "pass"; slot++ }
    menu = slot < slots ? "action" : ""
    if (!menu) submit()
    scene.forceActiveFocus()
  }

  // One more choice made: go on with the next Pokémon, or send the turn.
  function chosen(choice) {
    var p = parts.slice()
    p[slot] = choice
    parts = p
    pendingMove = -1
    cursor = 0
    if (forced) {
      var next = -1
      for (var k = slot + 1; k < request.forceSwitch.length; k++) if (request.forceSwitch[k] && !parts[k]) { next = k; break }
      if (next >= 0) { slot = next; menu = "party"; return }
    } else {
      var s = slot + 1
      while (s < slots && !needsAction(s)) { p = parts.slice(); p[s] = "pass"; parts = p; s++ }
      if (s < slots) { slot = s; menu = "action"; return }
    }
    submit()
  }

  function submit() {
    var out = []
    var n = forced ? request.forceSwitch.length : slots
    for (var i = 0; i < n; i++) out.push(parts[i] || "pass")
    menu = ""
    scene.choose(out.join(", "))
  }

  // Back one step (B button).
  function back() {
    if (menu === "fight" || menu === "run" || (menu === "party" && !forced)) { menu = "action"; cursor = 0; hint = ""; return }
    if (menu === "target") { menu = "fight"; cursor = Math.max(0, pendingMove); return }
    if (menu === "action" && slot > 0 && !forced) {
      var s = slot - 1
      while (s > 0 && parts[s] === "pass") s--
      if (parts[s] !== "pass") { slot = s; var p = parts.slice(); p[s] = ""; parts = p; menu = "action"; cursor = 0 }
    }
  }

  function pickAction(i) {
    if (i === 0) { menu = "fight"; cursor = 0; hint = ""; return }
    if (i === 1) { hint = "Items can't be used in the Battle Tower."; return }
    if (i === 2) {
      if (request.active[slot] && (request.active[slot].trapped || request.active[slot].maybeTrapped)) { hint = "It can't escape!"; return }
      menu = "party"; cursor = 0; hint = ""; return
    }
    menu = "run"; cursor = 1
  }

  function movesOf(i) { return request && request.active && request.active[i] ? request.active[i].moves : [] }

  function pickMove(i) {
    var m = movesOf(slot)[i]
    if (!m) return
    if (m.disabled || (m.pp !== undefined && m.pp <= 0 && m.id !== "struggle")) { hint = "There's no PP left for this move!"; return }
    if (doubles && ["normal", "any", "adjacentFoe", "adjacentAlly", "adjacentAllyOrSelf"].indexOf(m.target) >= 0) {
      pendingMove = i
      menu = "target"
      cursor = m.target === "adjacentAlly" ? 2 : m.target === "adjacentAllyOrSelf" ? 2 + slot : 0
      return
    }
    chosen("move " + (i + 1))
  }

  // Doubles targets: 0-1 the foes, 2-3 your side.
  function targets() {
    var m = movesOf(slot)[pendingMove]
    if (!m) return []
    var out = []
    if (m.target !== "adjacentAlly" && m.target !== "adjacentAllyOrSelf")
      for (var f = 0; f < 2; f++) { var foe = mon(1, f); out.push({ i: f, label: foe ? "Foe " + foe.name.toUpperCase() : "—", ok: !!foe, n: f + 1 }) }
    for (var a = 0; a < 2; a++) {
      var ally = mon(0, a)
      var ok = !!ally && (m.target === "adjacentAllyOrSelf" || (a !== slot && m.target !== "adjacentFoe"))
      if (m.target === "adjacentFoe") ok = false
      out.push({ i: 2 + a, label: ally ? ally.name.toUpperCase() : "—", ok: ok, n: -(a + 1) })
    }
    return out
  }

  function pickTarget(t) {
    if (!t || !t.ok) return
    chosen("move " + (pendingMove + 1) + " " + t.n)
  }

  function pickParty(i) {
    var p = party()[i]
    if (!p) return
    if (fainted(p)) { hint = nameOf(p).toUpperCase() + " has no energy left to battle!"; return }
    if (p.active) { hint = nameOf(p).toUpperCase() + " is already in battle!"; return }
    for (var k = 0; k < parts.length; k++) if (parts[k] === "switch " + (i + 1)) { hint = nameOf(p).toUpperCase() + " is already going in!"; return }
    chosen("switch " + (i + 1))
  }

  function togglePick(i) {
    var p = picked.slice(), at = p.indexOf(i)
    if (at >= 0) p.splice(at, 1)
    else if (p.length < (request.maxChosenTeamSize || 3)) p.push(i)
    picked = p
  }

  function confirmPreview() {
    if (picked.length < (request.maxChosenTeamSize || 3)) return
    menu = ""
    scene.choose("team " + picked.map(function(i) { return i + 1 }).join(""))
  }

  // ---- Keyboard: arrows, Z / Enter / Space = A, X / Backspace / Escape = B ----
  Keys.onPressed: function(event) {
    var k = event.key
    var a = k === Qt.Key_Z || k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space
    var b = k === Qt.Key_X || k === Qt.Key_Backspace || k === Qt.Key_Escape
    if (busy || result) {
      if (a || b) { scene.advance(); event.accepted = true }
      return
    }
    var cols = menu === "party" || menu === "preview" ? 1 : 2
    var count = menu === "action" ? 4 : menu === "fight" ? movesOf(slot).length : menu === "target" ? 4
              : menu === "party" ? party().length : menu === "run" ? 2 : menu === "preview" ? party().length : 0
    if (!count) return
    if (k === Qt.Key_Left && cols === 2 && cursor % 2 === 1) cursor -= 1
    else if (k === Qt.Key_Right && cols === 2 && cursor % 2 === 0 && cursor + 1 < count) cursor += 1
    else if (k === Qt.Key_Up && cursor - cols >= 0) cursor -= cols
    else if (k === Qt.Key_Down && cursor + cols < count) cursor += cols
    else if (a) {
      if (menu === "action") pickAction(cursor)
      else if (menu === "fight") pickMove(cursor)
      else if (menu === "target") pickTarget(targets().filter(function(t) { return t.i === cursor })[0])
      else if (menu === "party") pickParty(cursor)
      else if (menu === "run") { if (cursor === 0) scene.forfeit(); else back() }
      else if (menu === "preview") { if (picked.length >= (request.maxChosenTeamSize || 3)) confirmPreview(); else togglePick(cursor) }
    } else if (b) {
      if (menu === "preview") { if (picked.length) togglePick(picked[picked.length - 1]) }
      else back()
    } else return
    event.accepted = true
  }

  // ---- Pieces ----

  component PixelText: Text {
    property color shadow: scene.inkShadow
    color: scene.ink
    font.family: scene.fontFamily
    font.pixelSize: scene.px(10)
    style: Text.Raised
    styleColor: shadow
    renderType: Text.NativeRendering
  }

  // Gen 3 box: light fill, dark rounded frame.
  component Box: Rectangle {
    color: scene.boxFill
    border.color: scene.boxFrame
    border.width: scene.px(1)
    radius: scene.px(3)
  }

  component HpBar: Item {
    property real share: 1
    height: scene.px(4)
    Rectangle {
      id: hpTag
      width: scene.px(11); height: parent.height + scene.px(1)
      anchors.verticalCenter: parent.verticalCenter
      radius: scene.px(1)
      color: "#f8b030"
      PixelText { anchors.centerIn: parent; text: "HP"; font.pixelSize: scene.px(5); font.bold: true; color: "#f8f8f8"; shadow: "#a06018" }
    }
    Rectangle {
      anchors.left: hpTag.right; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
      height: parent.height; radius: scene.px(1); color: "#485860"
      Rectangle {
        x: scene.px(0.5); y: scene.px(0.5); height: parent.height - scene.px(1)
        width: Math.max(0, (parent.width - scene.px(1)) * Math.max(0, Math.min(1, share)))
        radius: scene.px(1)
        color: share > 0.5 ? "#70f8a8" : share > 0.2 ? "#f8e038" : "#f85838"
        Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
      }
    }
  }

  component StatusTag: Rectangle {
    property string status: ""
    visible: status !== ""
    width: scene.px(16); height: scene.px(7); radius: scene.px(2)
    color: ({ brn: "#e06030", par: "#d8b020", psn: "#a040a0", tox: "#802080", slp: "#8080a0", frz: "#60b0e0" })[status] || "#808080"
    PixelText { anchors.centerIn: parent; text: String(parent.status).toUpperCase(); font.pixelSize: scene.px(5); color: "#ffffff"; shadow: "#00000040" }
  }

  // One Pokémon's info box. `mine`: yours (with HP numbers), or the foe's.
  component InfoBox: Box {
    property var mon: null
    property bool mine: false
    property bool compact: false
    visible: !!mon
    width: scene.px(compact ? 98 : (mine ? 106 : 102))
    height: scene.px(compact ? 20 : (mine ? 36 : 28))
    PixelText {
      x: scene.px(6); y: scene.px(compact ? 1 : 3)
      text: parent.mon ? parent.mon.name.toUpperCase() : ""
      font.pixelSize: scene.px(compact ? 8 : 9)
      width: scene.px(compact ? 58 : 62); elide: Text.ElideRight
    }
    PixelText {
      x: scene.px(compact ? 60 : 66); y: scene.px(compact ? 1 : 3)
      visible: !!parent.mon && parent.mon.gender !== ""
      text: parent.mon && parent.mon.gender === "F" ? "♀" : "♂"
      color: parent.mon && parent.mon.gender === "F" ? "#f05060" : "#3878f0"
      font.pixelSize: scene.px(compact ? 8 : 9)
    }
    PixelText {
      anchors.right: parent.right; anchors.rightMargin: scene.px(5); y: scene.px(compact ? 1 : 3)
      text: "Lv" + (parent.mon ? parent.mon.level : "")
      font.pixelSize: scene.px(compact ? 7 : 8)
    }
    StatusTag {
      x: scene.px(6); y: scene.px(compact ? 12 : 15)
      status: parent.mon && parent.mon.status ? parent.mon.status : ""
    }
    HpBar {
      x: scene.px(compact ? 26 : 30); y: scene.px(compact ? 13 : 16)
      width: parent.width - x - scene.px(6)
      share: parent.mon && parent.mon.maxhp ? parent.mon.hp / parent.mon.maxhp : 0
    }
    PixelText {
      visible: parent.mine && !parent.compact
      anchors.right: parent.right; anchors.rightMargin: scene.px(6); y: scene.px(22)
      text: parent.mon ? Math.max(0, parent.mon.hp) + "/ " + parent.mon.maxhp : ""
      font.pixelSize: scene.px(9)
    }
  }

  // A Pokémon on the field. Yours face away (mirrored, a bit bigger).
  component Fighter: Item {
    id: fighter
    property int side: 0
    property int slotIndex: 0
    property real baseX: 0
    property real baseY: 0                 // bottom of the sprite
    property real box: 56
    readonly property var mon: scene.mon(side, slotIndex)
    property real dx: 0
    property real dy: 0
    property real alpha: 1
    x: scene.px(baseX) - width / 2 + dx
    y: scene.px(baseY) - height + dy
    width: sprite.width
    height: sprite.height
    opacity: mon ? alpha : 0

    function enter() { dx = (side === 0 ? -1 : 1) * scene.px(70); alpha = 1; dy = 0; enterAnim.restart() }
    function lunge() { lungeAnim.restart() }
    function hit() { hitAnim.restart() }
    function faint() { faintAnim.restart() }

    PokeSprite {
      id: sprite
      slug: fighter.mon ? Tower.slugOf(fighter.mon.species) : ""
      shiny: !!fighter.mon && fighter.mon.shiny
      fitWidth: scene.px(fighter.box)
      fitHeight: scene.px(fighter.box)
      maxPixel: scene.px(3)
      integerScale: true
      transform: Scale { origin.x: sprite.width / 2; xScale: fighter.side === 0 ? -1 : 1 }
    }

    NumberAnimation { id: enterAnim; target: fighter; property: "dx"; to: 0; duration: 380; easing.type: Easing.OutCubic }
    SequentialAnimation {
      id: lungeAnim
      NumberAnimation { target: fighter; property: "dx"; to: (fighter.side === 0 ? 1 : -1) * scene.px(8); duration: 90 }
      NumberAnimation { target: fighter; property: "dx"; to: 0; duration: 140 }
    }
    SequentialAnimation {
      id: hitAnim
      loops: 3
      NumberAnimation { target: fighter; property: "alpha"; to: 0.1; duration: 60 }
      NumberAnimation { target: fighter; property: "alpha"; to: 1; duration: 60 }
    }
    ParallelAnimation {
      id: faintAnim
      NumberAnimation { target: fighter; property: "dy"; to: scene.px(40); duration: 380; easing.type: Easing.InCubic }
      NumberAnimation { target: fighter; property: "alpha"; to: 0; duration: 380 }
    }
  }

  // Animations triggered by TowerWindow, one step at a time.
  function animate(step) {
    var f = fighterAt(step.side, step.slot)
    if (!f) return
    if (step.t === "switch") f.enter()
    else if (step.t === "move") f.lunge()
    else if (step.t === "hit") f.hit()
    else if (step.t === "faint") f.faint()
  }
  function fighterAt(side, i) {
    var rep = side === 0 ? mine : foes
    return rep.count > i ? rep.itemAt(i) : null
  }

  // ---- The scene ----

  Rectangle { anchors.fill: parent; color: "#101820" }

  Item {
    id: stage
    width: scene.px(240)
    height: scene.px(160)
    anchors.centerIn: parent
    clip: true

    // Sky and arena floor
    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0.0; color: scene.shown && scene.shown.weather === "rain" ? "#58708a" : scene.shown && scene.shown.weather === "sand" ? "#c8b080" : scene.shown && scene.shown.weather === "hail" ? "#b8d0e0" : scene.shown && scene.shown.weather === "sun" ? "#f8e0a0" : "#a8d0f0" }
        GradientStop { position: 0.45; color: "#e8f0f8" }
        GradientStop { position: 0.46; color: "#b8d8a8" }
        GradientStop { position: 1.0; color: "#88b878" }
      }
    }
    // The tower's back wall
    Row {
      y: scene.px(36)
      Repeater {
        model: 12
        Rectangle { width: scene.px(20); height: scene.px(32); color: index % 2 ? "#d8e0e8" : "#c8d0e0"; border.color: "#b0b8c8"; border.width: scene.px(0.5) }
      }
    }
    // Platforms
    Rectangle {
      x: scene.px(scene.doubles ? 132 : 128); y: scene.px(60); width: scene.px(scene.doubles ? 108 : 96); height: scene.px(18)
      radius: height / 2; color: "#98c088"; border.color: "#6a9860"; border.width: scene.px(1)
    }
    Rectangle {
      x: scene.px(scene.doubles ? -12 : 4); y: scene.px(100); width: scene.px(scene.doubles ? 150 : 120); height: scene.px(24)
      radius: height / 2; color: "#98c088"; border.color: "#6a9860"; border.width: scene.px(1)
    }

    Repeater {
      id: foes
      model: scene.slots
      delegate: Fighter {
        side: 1
        slotIndex: index
        baseX: scene.doubles ? (index === 0 ? 150 : 204) : 176
        baseY: scene.doubles ? (index === 0 ? 70 : 64) : 70
        box: scene.doubles ? 48 : 56
        z: scene.doubles && index === 0 ? 1 : 0
      }
    }
    Repeater {
      id: mine
      model: scene.slots
      delegate: Fighter {
        side: 0
        slotIndex: index
        baseX: scene.doubles ? (index === 0 ? 38 : 96) : 62
        baseY: 114
        box: scene.doubles ? 58 : 68
      }
    }

    // Info boxes
    Column {
      x: scene.px(scene.doubles ? 4 : 10); y: scene.px(scene.doubles ? 4 : 12)
      spacing: scene.px(2)
      Repeater {
        model: scene.slots
        delegate: InfoBox { mon: scene.mon(1, index); compact: scene.doubles }
      }
    }
    Column {
      x: scene.px(scene.doubles ? 138 : 128); y: scene.px(scene.doubles ? 68 : 72)
      spacing: scene.px(2)
      Repeater {
        model: scene.slots
        delegate: InfoBox { mon: scene.mon(0, index); mine: true; compact: scene.doubles }
      }
    }

    // Weather and field effects, top right
    PixelText {
      anchors.right: parent.right; anchors.rightMargin: scene.px(4); y: scene.px(2)
      visible: !!scene.shown && !!scene.shown.weather
      text: scene.shown ? ({ rain: "RAIN", sun: "SUN", sand: "SANDSTORM", hail: "SNOW", wind: "WINDS" })[scene.shown.weather] || "" : ""
      font.pixelSize: scene.px(6)
    }

    // ---- Text box (bottom) ----
    Rectangle {
      id: textBox
      x: 0; y: scene.px(112); width: parent.width; height: scene.px(48)
      color: "#e8d8a0"
      Rectangle {
        anchors.fill: parent; anchors.margins: scene.px(2)
        radius: scene.px(3)
        color: scene.textFill
        border.color: "#78a0c0"; border.width: scene.px(1)
      }
      PixelText {
        id: message
        x: scene.px(10); y: scene.px(8)
        width: (scene.menu === "action" || scene.menu === "target" ? scene.px(104) : parent.width - scene.px(20))
        height: scene.px(34)
        wrapMode: Text.WordWrap
        color: "#f8f8f8"
        shadow: "#506880"
        font.pixelSize: scene.px(10)
        lineHeight: 1.15
        text: scene.hint !== "" ? scene.hint
            : scene.menu === "action" ? "What will " + (scene.party()[scene.slot] ? scene.nameOf(scene.party()[scene.slot]).toUpperCase() : "") + " do?"
            : scene.menu === "target" ? "Use it on which Pokémon?"
            : scene.menu === "run" ? "Give up this battle? Your challenge will end."
            : scene.boxText
      }
      // Blinking arrow when the text waits for you
      PixelText {
        anchors.right: parent.right; anchors.rightMargin: scene.px(10); anchors.bottom: parent.bottom; anchors.bottomMargin: scene.px(6)
        visible: scene.busy && scene.boxText !== ""
        text: "▼"; color: "#f85838"; shadow: "#803020"; font.pixelSize: scene.px(7)
        SequentialAnimation on opacity { running: true; loops: Animation.Infinite
          NumberAnimation { to: 0.2; duration: 400 } NumberAnimation { to: 1; duration: 400 } }
      }
      MouseArea { anchors.fill: parent; enabled: scene.busy; onClicked: scene.advance() }
    }

    // ---- FIGHT / BAG / POKéMON / RUN ----
    Box {
      visible: scene.menu === "action"
      x: scene.px(120); y: scene.px(112); width: scene.px(120); height: scene.px(48)
      Grid {
        anchors.fill: parent; anchors.margins: scene.px(6)
        columns: 2
        Repeater {
          model: ["FIGHT", "BAG", "POKéMON", "RUN"]
          delegate: Item {
            width: scene.px(54); height: scene.px(18)
            PixelText { x: scene.px(2); anchors.verticalCenter: parent.verticalCenter; visible: scene.cursor === index; text: "▶"; font.pixelSize: scene.px(8) }
            PixelText { x: scene.px(11); anchors.verticalCenter: parent.verticalCenter; text: modelData; opacity: index === 1 ? 0.45 : 1; font.pixelSize: scene.px(10) }
            MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: scene.cursor = index; onClicked: scene.pickAction(index) }
          }
        }
      }
    }

    // ---- FIGHT: the moves, then PP and type ----
    Box {
      visible: scene.menu === "fight"
      x: 0; y: scene.px(112); width: scene.px(164); height: scene.px(48)
      Grid {
        anchors.fill: parent; anchors.margins: scene.px(6)
        columns: 2
        Repeater {
          model: scene.menu === "fight" ? scene.movesOf(scene.slot) : []
          delegate: Item {
            width: scene.px(76); height: scene.px(18)
            readonly property bool usable: !modelData.disabled && !(modelData.pp !== undefined && modelData.pp <= 0)
            PixelText { x: scene.px(1); anchors.verticalCenter: parent.verticalCenter; visible: scene.cursor === index; text: "▶"; font.pixelSize: scene.px(8) }
            PixelText {
              x: scene.px(10); anchors.verticalCenter: parent.verticalCenter
              width: scene.px(66); elide: Text.ElideRight
              text: String(modelData.move).toUpperCase(); opacity: parent.usable ? 1 : 0.4; font.pixelSize: scene.px(9)
            }
            MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: scene.cursor = index; onClicked: scene.pickMove(index) }
          }
        }
      }
    }
    Box {
      id: movePanel
      visible: scene.menu === "fight"
      readonly property var move: scene.movesOf(scene.slot)[scene.cursor] || null
      readonly property var info: move ? scene.moveInfo[move.id] || null : null
      x: scene.px(164); y: scene.px(112); width: scene.px(76); height: scene.px(48)
      PixelText { x: scene.px(8); y: scene.px(8); text: "PP"; font.pixelSize: scene.px(9) }
      PixelText {
        anchors.right: parent.right; anchors.rightMargin: scene.px(8); y: scene.px(8)
        text: movePanel.move && movePanel.move.maxpp ? movePanel.move.pp + "/" + movePanel.move.maxpp : "—"
        color: movePanel.move && movePanel.move.maxpp && movePanel.move.pp <= movePanel.move.maxpp / 4 ? "#e05030" : scene.ink
        font.pixelSize: scene.px(9)
      }
      Rectangle {
        x: scene.px(8); y: scene.px(25); width: scene.px(60); height: scene.px(12); radius: scene.px(2)
        readonly property string type: movePanel.info ? String(movePanel.info.type).toLowerCase() : "normal"
        color: scene.host.typeColors[type] || "#a8a878"
        PixelText { anchors.centerIn: parent; text: "TYPE/" + parent.type.toUpperCase(); color: "#ffffff"; shadow: "#00000060"; font.pixelSize: scene.px(7) }
      }
    }

    // ---- Doubles: target ----
    Box {
      visible: scene.menu === "target"
      x: scene.px(120); y: scene.px(112); width: scene.px(120); height: scene.px(48)
      Grid {
        anchors.fill: parent; anchors.margins: scene.px(5)
        columns: 2
        Repeater {
          model: scene.menu === "target" ? scene.targets() : []
          delegate: Item {
            width: scene.px(55); height: scene.px(19)
            PixelText { x: scene.px(1); anchors.verticalCenter: parent.verticalCenter; visible: scene.cursor === modelData.i; text: "▶"; font.pixelSize: scene.px(7) }
            PixelText {
              x: scene.px(8); anchors.verticalCenter: parent.verticalCenter; width: scene.px(47); elide: Text.ElideRight
              text: modelData.label; opacity: modelData.ok ? 1 : 0.35; font.pixelSize: scene.px(7)
            }
            MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: scene.cursor = modelData.i; onClicked: scene.pickTarget(modelData) }
          }
        }
      }
    }

    // ---- RUN: give up? ----
    Box {
      visible: scene.menu === "run"
      x: scene.px(176); y: scene.px(76); width: scene.px(60); height: scene.px(34)
      Column {
        anchors.fill: parent; anchors.margins: scene.px(5)
        Repeater {
          model: ["YES", "NO"]
          delegate: Item {
            width: scene.px(50); height: scene.px(12)
            PixelText { visible: scene.cursor === index; text: "▶"; font.pixelSize: scene.px(7); anchors.verticalCenter: parent.verticalCenter }
            PixelText { x: scene.px(9); text: modelData; font.pixelSize: scene.px(9); anchors.verticalCenter: parent.verticalCenter }
            MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: scene.cursor = index
                        onClicked: { if (index === 0) scene.forfeit(); else scene.back() } }
          }
        }
      }
    }

    // ---- POKéMON: your party ----
    Rectangle {
      visible: scene.menu === "party"
      anchors.fill: parent
      color: "#3870a8"
      Rectangle { anchors.fill: parent; anchors.margins: scene.px(3); color: "#5890c8"; radius: scene.px(4) }
      Column {
        x: scene.px(8); y: scene.px(8)
        spacing: scene.px(3)
        Repeater {
          model: scene.menu === "party" ? scene.party() : []
          delegate: Rectangle {
            readonly property var hp: scene.hpOf(modelData)
            readonly property bool out: scene.fainted(modelData)
            width: scene.px(224); height: scene.px(19)
            radius: scene.px(4)
            color: scene.cursor === index ? "#f8f8f8" : out ? "#c8a8a8" : modelData.active ? "#a8e0f8" : "#e0e8f0"
            border.color: scene.cursor === index ? "#f85838" : "#30486a"; border.width: scene.px(1)
            PokeSprite {
              x: scene.px(4); anchors.verticalCenter: parent.verticalCenter
              slug: scene.slugOfDetails(modelData.details)
              fitWidth: scene.px(16); fitHeight: scene.px(16); maxPixel: scene.px(1)
            }
            PixelText { x: scene.px(24); y: scene.px(2); text: scene.nameOf(modelData).toUpperCase(); font.pixelSize: scene.px(8) }
            PixelText { x: scene.px(24); y: scene.px(10); text: "Lv50" + (modelData.active ? "  · IN BATTLE" : ""); font.pixelSize: scene.px(6) }
            HpBar { x: scene.px(110); y: scene.px(5); width: scene.px(70); share: parent.hp.hp / Math.max(1, parent.hp.max) }
            PixelText { x: scene.px(184); y: scene.px(3); text: parent.hp.hp + "/" + parent.hp.max; font.pixelSize: scene.px(8) }
            MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: scene.cursor = index; onClicked: scene.pickParty(index) }
          }
        }
      }
      Box {
        x: scene.px(8); y: scene.px(134); width: scene.px(164); height: scene.px(20)
        PixelText {
          anchors.verticalCenter: parent.verticalCenter; x: scene.px(6); width: parent.width - scene.px(12); elide: Text.ElideRight
          text: scene.hint !== "" ? scene.hint : scene.forced ? "Choose a POKéMON to send out." : "Choose a POKéMON."
          font.pixelSize: scene.px(8)
        }
      }
      Box {
        visible: !scene.forced
        x: scene.px(178); y: scene.px(134); width: scene.px(54); height: scene.px(20)
        color: "#f8f8f8"
        PixelText { anchors.centerIn: parent; text: "CANCEL"; font.pixelSize: scene.px(8) }
        MouseArea { anchors.fill: parent; onClicked: scene.back() }
      }
    }

    // ---- Team Preview: their team, then pick yours ----
    Rectangle {
      visible: scene.menu === "preview"
      anchors.fill: parent
      color: "#284868"
      PixelText {
        x: scene.px(8); y: scene.px(5)
        text: scene.foeName.toUpperCase(); color: "#f8f8f8"; shadow: "#102030"; font.pixelSize: scene.px(10)
      }
      Row {
        x: scene.px(8); y: scene.px(18)
        spacing: scene.px(4)
        Repeater {
          model: scene.menu === "preview" && scene.battleState ? scene.battleState.preview : []
          delegate: Box {
            width: scene.px(34); height: scene.px(38)
            PokeSprite {
              anchors.centerIn: parent
              slug: Tower.slugOf(modelData.species); shiny: modelData.shiny
              fitWidth: scene.px(30); fitHeight: scene.px(30); maxPixel: scene.px(2); integerScale: true
            }
          }
        }
      }
      PixelText {
        x: scene.px(8); y: scene.px(60)
        text: "Choose " + (scene.request ? scene.request.maxChosenTeamSize || 3 : 3) + " POKéMON, in the order you'll send them."
        color: "#f8f8f8"; shadow: "#102030"; font.pixelSize: scene.px(8)
      }
      Grid {
        x: scene.px(8); y: scene.px(72)
        columns: 3
        spacing: scene.px(3)
        Repeater {
          model: scene.menu === "preview" ? scene.party() : []
          delegate: Rectangle {
            readonly property int order: scene.picked.indexOf(index)
            width: scene.px(73); height: scene.px(26); radius: scene.px(3)
            color: order >= 0 ? "#f8f0c0" : "#e0e8f0"
            border.color: scene.cursor === index ? "#f85838" : "#30486a"; border.width: scene.px(1)
            PokeSprite {
              x: scene.px(3); anchors.verticalCenter: parent.verticalCenter
              slug: scene.slugOfDetails(modelData.details)
              fitWidth: scene.px(22); fitHeight: scene.px(22); maxPixel: scene.px(1.5)
            }
            PixelText { x: scene.px(27); y: scene.px(4); width: scene.px(42); elide: Text.ElideRight; text: scene.nameOf(modelData).toUpperCase(); font.pixelSize: scene.px(7) }
            PixelText { x: scene.px(27); y: scene.px(14); width: scene.px(42); elide: Text.ElideRight
                        text: scene.itemAt(index); font.pixelSize: scene.px(5); opacity: 0.7 }
            Rectangle {
              visible: parent.order >= 0
              anchors.right: parent.right; anchors.top: parent.top; anchors.margins: scene.px(2)
              width: scene.px(9); height: scene.px(9); radius: width / 2; color: "#e23b44"
              PixelText { anchors.centerIn: parent; text: parent.parent.order + 1; color: "#ffffff"; shadow: "#80202000"; font.pixelSize: scene.px(6) }
            }
            MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: scene.cursor = index; onClicked: scene.togglePick(index) }
          }
        }
      }
      Box {
        readonly property bool full: !!scene.request && scene.picked.length >= (scene.request.maxChosenTeamSize || 3)
        x: scene.px(160); y: scene.px(134); width: scene.px(74); height: scene.px(20)
        color: full ? "#f8f8f8" : "#a8b0b8"
        PixelText { anchors.centerIn: parent; text: "BATTLE!"; font.pixelSize: scene.px(9); opacity: parent.full ? 1 : 0.5 }
        MouseArea { anchors.fill: parent; onClicked: scene.confirmPreview() }
      }
    }

    // ---- The outcome ----
    Rectangle {
      visible: !!scene.result && !scene.busy
      anchors.fill: parent
      color: "#c0101820"
      Box {
        anchors.centerIn: parent
        width: scene.px(180); height: resultColumn.implicitHeight + scene.px(16)
        Column {
          id: resultColumn
          x: scene.px(10); y: scene.px(8)
          width: parent.width - scene.px(20)
          spacing: scene.px(4)
          PixelText {
            width: parent.width; horizontalAlignment: Text.AlignHCenter
            text: !scene.result ? "" : scene.result.won ? "YOU WON!" : "YOU LOST…"
            color: scene.result && scene.result.won ? "#d83838" : scene.ink
            font.pixelSize: scene.px(12)
          }
          Repeater {
            model: scene.result ? scene.result.lines || [] : []
            delegate: PixelText { width: resultColumn.width; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter; text: modelData; font.pixelSize: scene.px(8) }
          }
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: scene.px(6)
            Repeater {
              model: scene.result ? scene.result.actions || [] : []
              delegate: Rectangle {
                width: actionLabel.implicitWidth + scene.px(14); height: scene.px(16); radius: scene.px(3)
                color: actionArea.containsMouse ? "#f8e8b0" : "#e0e8f0"
                border.color: scene.boxFrame; border.width: scene.px(1)
                PixelText { id: actionLabel; anchors.centerIn: parent; text: modelData.label; font.pixelSize: scene.px(8) }
                MouseArea { id: actionArea; anchors.fill: parent; hoverEnabled: true; onClicked: scene.resultAction(modelData.id) }
              }
            }
          }
        }
      }
    }
  }
}
