import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Pet.js" as Pet
import "Expedition.js" as Exp

// The expedition window: plan a new expedition and look back at past ones.
// Teams out exploring are followed in the popup.
FloatingWindow {
  id: win
  required property var host

  title: "Pokemagotchi – Expeditions"
  color: Color.popups.background
  implicitWidth: 1040
  implicitHeight: 720
  minimumSize: Qt.size(860, 620)
  visible: false

  readonly property color accent: "#e23b44"
  readonly property color gold: "#f2b84b"
  readonly property color steel: "#4a86b8"
  readonly property color good: "#7fbf9a"
  readonly property color text: Color.popups.text
  readonly property var typeColors: host.typeColors

  readonly property var view: host.view
  readonly property var exps: view.expeditions || []
  readonly property var rec: view.expedition || Pet.freshRecord()
  property real clock: Date.now()
  property int ticks: 0

  property string tab: "new"         // "new" | "history"

  // New expedition
  property string biome: "forest"
  property string diff: "easy"
  property var team: []
  property var prov: ({})
  property string query: ""
  property string launchMessage: ""

  function open(which) {
    host.now = Date.now()
    clock = Date.now()
    tab = which === "history" ? "history" : "new"
    resetWizard()
    // Closed by the compositor (SUPER+W…), the window can still think it is
    // visible: hide it first so showing it creates a new one.
    if (visible) visible = false
    visible = true
  }

  onClosed: visible = false

  function selectTab(id) {
    tab = id
    if (id === "new") resetWizard()
  }

  function resetWizard() {
    var open = Exp.BIOME_ORDER.filter(function(b) { return Exp.biomeOpen(view, b) })
    if (!Exp.biomeOpen(view, biome)) biome = open[0] || "forest"
    if (!Exp.difficultyOpen(view, diff)) diff = "easy"
    team = team.filter(function(r) { return Exp.available(view).indexOf(r) >= 0 })
    if (!team.length && view.current && Exp.available(view).indexOf(view.current) >= 0) team = [view.current]
    prov = Exp.autoPack(view, diff, Math.max(1, team.length))
    launchMessage = ""
  }

  function toggleMember(r) {
    var t = team.slice(), i = t.indexOf(r)
    if (i >= 0) t.splice(i, 1)
    else if (t.length < Exp.TEAM_SIZE) t.push(r)
    else { launchMessage = "A team has " + Exp.TEAM_SIZE + " Pokémon at most."; return }
    team = t
    launchMessage = ""
  }

  function setProv(id, n) {
    var p = Object.assign({}, prov)
    var owned = view.bag[id] || 0
    var room = Exp.capacity(view) - Exp.provisionCount(prov) + (p[id] || 0)
    n = Math.max(0, Math.min(owned, room, n))
    if (n > 0) p[id] = n
    else delete p[id]
    prov = p
  }

  function launch() {
    var opts = { biome: biome, diff: diff, team: team.slice(), provisions: Object.assign({}, prov) }
    var err = host.mutate(function(s, t) { return Exp.launch(s, opts, t) })
    if (err === null || err === undefined) return
    if (err) { launchMessage = err; return }
    // Off they go: follow them from the popup
    var x = host.save.expeditions[host.save.expeditions.length - 1]
    team = []
    visible = false
    host.followExpedition(x.id)
  }

  Timer {
    interval: 1000
    running: win.visible
    repeat: true
    onTriggered: {
      win.clock = Date.now()
      win.ticks += 1
      if (win.ticks % 10 === 0) win.host.now = Date.now()
    }
  }

  // ---- Little building blocks ----

  component XButton: Rectangle {
    id: btn
    property string label: ""
    property bool danger: false
    property bool highlight: false
    property bool enabledLook: true
    property real fontSize: 12
    signal clicked()
    implicitWidth: btnLabel.implicitWidth + Style.space(22)
    height: Style.space(30)
    radius: Style.cornerRadius
    opacity: enabledLook ? 1 : 0.4
    readonly property color tint: danger ? win.accent : highlight ? win.gold : win.steel
    color: btnArea.pressed ? Qt.rgba(tint.r, tint.g, tint.b, 0.35)
         : btnArea.containsMouse ? Qt.rgba(tint.r, tint.g, tint.b, 0.18)
         : danger || highlight ? Qt.rgba(tint.r, tint.g, tint.b, 0.12) : Qt.rgba(1, 1, 1, 0.05)
    border.width: 1
    border.color: btnArea.containsMouse || danger || highlight ? tint : Qt.rgba(1, 1, 1, 0.12)
    Text {
      id: btnLabel
      anchors.centerIn: parent
      text: btn.label
      color: win.text
      font.family: Style.font.family
      font.pixelSize: Style.space(btn.fontSize)
    }
    MouseArea {
      id: btnArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.clicked()
    }
  }

  component Label: Text {
    color: win.text
    font.family: Style.font.family
    font.pixelSize: Style.space(12)
  }

  component Dim: Text {
    color: win.text
    opacity: 0.65
    font.family: Style.font.family
    font.pixelSize: Style.space(11)
  }

  component Heading: Text {
    color: win.accent
    font.family: Style.font.family
    font.pixelSize: Style.space(13)
    font.bold: true
    font.letterSpacing: 1.5
  }

  component Bar: Rectangle {
    property real ratio: 0
    property color fill: win.good
    height: Style.space(5)
    radius: height / 2
    color: Qt.rgba(1, 1, 1, 0.08)
    Rectangle {
      width: parent.width * Math.max(0, Math.min(1, parent.ratio))
      height: parent.height
      radius: parent.radius
      color: parent.fill
      Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
    }
  }

  component TypeChip: Rectangle {
    property string type: ""
    width: typeText.implicitWidth + Style.space(10)
    height: Style.space(16)
    radius: height / 2
    color: win.typeColors[type] || win.steel
    Text {
      id: typeText
      anchors.centerIn: parent
      text: parent.type.toUpperCase()
      color: "white"
      font.family: Style.font.family
      font.pixelSize: Style.space(8)
      font.bold: true
    }
  }

  component Tile: Rectangle {
    radius: Style.cornerRadius
    color: Qt.rgba(1, 1, 1, 0.035)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.08)
  }

  // ---- Layout ----

  readonly property Item page: page

  Item {
    id: page
    anchors.fill: parent
    anchors.margins: Style.space(16)

    // Header: title, rank, slots
    Item {
      id: header
      width: parent.width
      height: Style.space(34)

      Text {
        id: headerTitle
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "⛰  EXPEDITIONS"
        color: win.accent
        font.family: Style.font.family
        font.pixelSize: Style.space(18)
        font.bold: true
        font.letterSpacing: 2
      }

      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(14)

        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(3)
          readonly property var next: Exp.nextRank(win.view)
          Label {
            text: "Rank: " + Exp.rank(win.view).name + "  ·  " + win.rec.points + " pts"
                  + (parent.next ? "  (" + parent.next.name + " at " + parent.next.points + ")" : "")
            color: win.gold
            font.bold: true
          }
          Bar {
            width: Style.space(260)
            fill: win.gold
            ratio: !parent.next ? 1 : (win.rec.points - Exp.rank(win.view).points) / (parent.next.points - Exp.rank(win.view).points)
          }
        }
        Label {
          anchors.verticalCenter: parent.verticalCenter
          text: Exp.active(win.view).length + " / " + Exp.slots(win.view) + " teams out"
        }
      }
    }

    // Tabs
    Flow {
      id: tabs
      anchors.top: header.bottom
      anchors.topMargin: Style.space(10)
      width: parent.width
      spacing: Style.space(6)

      Repeater {
        model: [ { id: "new", label: "+  New expedition" }, { id: "history", label: "History" } ]
        delegate: Rectangle {
          required property var modelData
          readonly property bool selected: win.tab === modelData.id
          width: extraLabel.implicitWidth + Style.space(22)
          height: Style.space(32)
          radius: Style.cornerRadius
          color: selected ? Qt.rgba(0.95, 0.72, 0.29, 0.16) : extraArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
          border.width: 1
          border.color: selected ? win.gold : Qt.rgba(1, 1, 1, 0.1)
          Label { id: extraLabel; anchors.centerIn: parent; text: modelData.label; color: parent.selected ? win.gold : win.text }
          MouseArea { id: extraArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.selectTab(modelData.id) }
        }
      }
    }

    Item {
      id: body
      anchors.top: tabs.bottom
      anchors.topMargin: Style.space(12)
      anchors.bottom: parent.bottom
      width: parent.width

      // ================= New expedition =================
      Row {
        id: wizard
        visible: win.tab === "new"
        anchors.fill: parent
        spacing: Style.space(12)
        readonly property real col: (width - spacing * 2) / 3

        // ---- Where and how hard ----
        Tile {
          width: wizard.col
          height: parent.height

          Flickable {
            anchors.fill: parent
            anchors.margins: Style.space(10)
            contentHeight: whereColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: whereColumn
              width: parent.width
              spacing: Style.space(10)

              Heading { text: "1 · DESTINATION" }

              Grid {
                id: biomeGrid
                width: parent.width
                columns: 3
                spacing: Style.space(6)
                Repeater {
                  model: Exp.BIOME_ORDER
                  delegate: Rectangle {
                    id: biomeCard
                    required property string modelData
                    readonly property var b: Exp.BIOMES[modelData]
                    readonly property bool unlocked: Exp.biomeOpen(win.view, modelData)
                    readonly property bool selected: win.biome === modelData
                    width: (biomeGrid.width - biomeGrid.spacing * 2) / 3
                    height: Style.space(64)
                    radius: Style.cornerRadius
                    gradient: Gradient {
                      GradientStop { position: 0; color: biomeCard.b.colors[1] }
                      GradientStop { position: 1; color: biomeCard.b.colors[0] }
                    }
                    border.width: selected ? 2 : 0
                    border.color: win.gold
                    opacity: unlocked ? 1 : 0.4

                    Column {
                      anchors.left: parent.left
                      anchors.bottom: parent.bottom
                      anchors.margins: Style.space(6)
                      Text {
                        text: biomeCard.b.name
                        color: "white"
                        font.family: Style.font.family
                        font.pixelSize: Style.space(11)
                        font.bold: true
                      }
                      Text {
                        text: biomeCard.unlocked ? "" : "🔒 " + Exp.RANKS[biomeCard.b.rank].name + " rank"
                        visible: !biomeCard.unlocked
                        color: "white"
                        font.family: Style.font.family
                        font.pixelSize: Style.space(9)
                      }
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: biomeCard.unlocked ? Qt.PointingHandCursor : Qt.ArrowCursor
                      onClicked: if (biomeCard.unlocked) { win.biome = biomeCard.modelData; win.launchMessage = "" }
                    }
                  }
                }
              }

              Label {
                width: parent.width
                wrapMode: Text.WordWrap
                text: Exp.BIOMES[win.biome].text
              }
              Flow {
                width: parent.width
                spacing: Style.space(4)
                Dim { text: "Wild types:"; font.pixelSize: Style.space(10) }
                Repeater {
                  model: Object.keys(Exp.BIOMES[win.biome].types).sort(function(a, b) { return Exp.BIOMES[win.biome].types[b] - Exp.BIOMES[win.biome].types[a] })
                  delegate: TypeChip { required property string modelData; type: modelData }
                }
              }
              Dim {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Weather: " + Object.keys(Exp.BIOMES[win.biome].weather).map(function(w) { return Exp.WEATHER_ICONS[w] + " " + Exp.WEATHER_NAMES[w] }).join(", ")
                      + (Exp.BIOMES[win.biome].hunger > 1 ? "  ·  You get hungry faster here." : "")
              }
              Flow {
                width: parent.width
                spacing: Style.space(6)
                visible: Exp.sightings(win.view, win.biome).length > 0
                Dim { text: "Legends sighted:"; font.pixelSize: Style.space(10) }
                Repeater {
                  model: Exp.sightings(win.view, win.biome)
                  delegate: Row {
                    required property var modelData
                    spacing: Style.space(2)
                    PokeSprite { slug: modelData.slug; fitWidth: Style.space(28); fitHeight: Style.space(24) }
                    Dim { anchors.verticalCenter: parent.verticalCenter; text: Pet.name(modelData.slug) + " ×" + modelData.count; color: win.gold; opacity: 1 }
                  }
                }
              }

              Heading { text: "2 · DIFFICULTY" }
              Grid {
                id: diffGrid
                width: parent.width
                columns: 2
                spacing: Style.space(6)
                Repeater {
                  model: Exp.DIFFICULTY_ORDER
                  delegate: Rectangle {
                    id: diffCard
                    required property string modelData
                    readonly property var d: Exp.DIFFICULTIES[modelData]
                    readonly property bool unlocked: Exp.difficultyOpen(win.view, modelData)
                    readonly property bool selected: win.diff === modelData
                    width: (diffGrid.width - diffGrid.spacing) / 2
                    height: Style.space(48)
                    radius: Style.cornerRadius
                    color: selected ? Qt.rgba(0.95, 0.72, 0.29, 0.16) : diffArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.04)
                    border.width: 1
                    border.color: selected ? win.gold : Qt.rgba(1, 1, 1, 0.1)
                    opacity: unlocked ? 1 : 0.4
                    Column {
                      anchors.centerIn: parent
                      Label { anchors.horizontalCenter: parent.horizontalCenter; text: diffCard.d.name; font.bold: true }
                      Dim {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: diffCard.unlocked ? diffCard.d.floors + " floors · " + Exp.timeText(diffCard.d.minutes * 60000)
                                                : "🔒 " + Exp.RANKS[diffCard.d.rank].name + " rank"
                        font.pixelSize: Style.space(10)
                      }
                    }
                    MouseArea {
                      id: diffArea
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: diffCard.unlocked ? Qt.PointingHandCursor : Qt.ArrowCursor
                      onClicked: if (diffCard.unlocked) {
                        win.diff = diffCard.modelData
                        win.prov = Exp.autoPack(win.view, win.diff, Math.max(1, win.team.length))
                        win.launchMessage = ""
                      }
                    }
                  }
                }
              }
              Dim {
                width: parent.width
                wrapMode: Text.WordWrap
                readonly property var d: Exp.DIFFICULTIES[win.diff]
                text: "Wild Pokémon are 0 to 5 levels below your team"
                      + (d.boss.length ? ", with a boss on floor" + (d.boss.length > 1 ? "s " : " ") + d.boss.join(", ") : "")
                      + ". Up to " + d.recruits + " may want to join you."
                      + (d.tier >= 3 ? " Any legendary of the area can appear." : d.tier === 2 ? " Most legendaries of the area can appear." : d.tier === 1 ? " Young legendaries can appear." : "")
              }
            }
          }
        }

        // ---- Team ----
        Tile {
          width: wizard.col
          height: parent.height

          Column {
            id: teamPicker
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(8)

            Heading { text: "3 · TEAM  (" + win.team.length + " / " + Exp.TEAM_SIZE + ")" }

            Row {
              spacing: Style.space(6)
              Repeater {
                model: Exp.TEAM_SIZE
                delegate: Rectangle {
                  id: slot
                  required property int index
                  readonly property string ref: win.team[index] || ""
                  readonly property var p: ref ? win.view.pets[ref] : null
                  width: (teamPicker.width - Style.space(12)) / 3
                  height: Style.space(70)
                  radius: Style.cornerRadius
                  color: Qt.rgba(1, 1, 1, 0.04)
                  border.width: 1
                  border.color: p ? win.gold : Qt.rgba(1, 1, 1, 0.12)
                  PokeSprite {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: Style.space(4)
                    slug: slot.p ? slot.p.species : ""
                    shiny: !!slot.p && slot.p.shiny
                    fitWidth: parent.width - 8
                    fitHeight: Style.space(44)
                    maxPixel: 2
                  }
                  Dim {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Style.space(3)
                    text: slot.p ? (slot.index === 0 ? "Leader · " : "") + "Lv. " + Pet.level(slot.p) : "Empty"
                    font.pixelSize: Style.space(9)
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: slot.p ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (slot.p) win.toggleMember(slot.ref)
                  }
                }
              }
            }

            TextField {
              id: teamSearch
              width: parent.width
              placeholderText: "Search your Pokémon…"
              text: win.query
              onTextChanged: win.query = text
            }

            GridView {
              id: teamGrid
              width: parent.width
              height: parent.height - y - hintsBox.height - teamPicker.spacing
              clip: true
              cellWidth: width / 4
              cellHeight: Style.space(72)
              boundsBehavior: Flickable.StopAtBounds
              model: win.tab !== "new" ? [] : Exp.available(win.view).filter(function(r) {
                var q = win.query.trim().toLowerCase()
                return !q || Pet.name(win.view.pets[r].species).toLowerCase().indexOf(q) >= 0
              }).sort(function(a, b) { return Pet.level(win.view.pets[b]) - Pet.level(win.view.pets[a]) })

              delegate: Item {
                id: pick
                required property string modelData
                readonly property var p: win.view.pets[modelData]
                readonly property bool chosen: win.team.indexOf(modelData) >= 0
                width: teamGrid.cellWidth
                height: teamGrid.cellHeight
                Rectangle {
                  anchors.fill: parent
                  anchors.margins: Style.space(2)
                  radius: Style.cornerRadius
                  color: pick.chosen ? Qt.rgba(0.95, 0.72, 0.29, 0.16) : pickArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0.29, 0.53, 0.72, 0.08)
                  border.width: pick.chosen ? 1 : 0
                  border.color: win.gold
                  PokeSprite {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: Style.space(3)
                    slug: pick.p.species
                    shiny: pick.p.shiny
                    fitWidth: parent.width - 6
                    fitHeight: Style.space(40)
                    maxPixel: 2
                  }
                  Dim {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Style.space(3)
                    width: parent.width - 4
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: Pet.name(pick.p.species) + " " + Pet.level(pick.p)
                    font.pixelSize: Style.space(9)
                    opacity: 0.9
                  }
                  Text {
                    visible: pick.modelData === win.view.current
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: Style.space(3)
                    text: "★"
                    color: win.accent
                    font.pixelSize: Style.space(10)
                  }
                  MouseArea {
                    id: pickArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.toggleMember(pick.modelData)
                  }
                }
              }
            }

            Column {
              id: hintsBox
              width: parent.width
              spacing: Style.space(2)
              Repeater {
                model: win.tab === "new" ? Exp.hints(win.view, win.biome, win.team).slice(0, 6) : []
                delegate: Dim {
                  required property var modelData
                  width: hintsBox.width
                  wrapMode: Text.WordWrap
                  text: (modelData.bad ? "⚠ " : "✓ ") + modelData.text
                  color: modelData.bad ? "#e8903a" : win.good
                  opacity: 1
                  font.pixelSize: Style.space(10)
                }
              }
            }
          }
        }

        // ---- Provisions and launch ----
        Tile {
          width: wizard.col
          height: parent.height

          Column {
            id: provColumn
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(8)
            readonly property var items: Pet.bagItems(win.view).filter(Pet.isProvision)

            Item {
              width: parent.width
              height: Style.space(20)
              Heading { text: "4 · PROVISIONS" }
              Label {
                anchors.right: parent.right
                text: Exp.provisionCount(win.prov) + " / " + Exp.capacity(win.view)
                color: Exp.provisionCount(win.prov) >= Exp.capacity(win.view) ? win.gold : win.text
              }
            }
            Dim {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "The team eats, heals and restores PP on its own, using what you pack."
            }
            Row {
              spacing: Style.space(6)
              XButton { label: "Pack for me"; onClicked: win.prov = Exp.autoPack(win.view, win.diff, Math.max(1, win.team.length)) }
              XButton { label: "Empty"; onClicked: win.prov = ({}) }
            }

            ListView {
              id: provList
              width: parent.width
              height: parent.height - y - launchBox.height - provColumn.spacing
              clip: true
              spacing: Style.space(3)
              boundsBehavior: Flickable.StopAtBounds
              model: win.tab === "new" ? provColumn.items : []

              delegate: Rectangle {
                id: provRow
                required property string modelData
                readonly property int packed: win.prov[modelData] || 0
                width: provList.width
                height: Style.space(36)
                radius: Style.cornerRadius
                color: packed > 0 ? Qt.rgba(0.50, 0.75, 0.60, 0.10) : Qt.rgba(1, 1, 1, 0.03)

                ItemSprite { id: provSprite; anchors.left: parent.left; anchors.leftMargin: Style.space(4); anchors.verticalCenter: parent.verticalCenter; item: provRow.modelData; scale_: 1 }
                Column {
                  anchors.left: provSprite.right
                  anchors.leftMargin: Style.space(6)
                  anchors.right: provButtons.left
                  anchors.verticalCenter: parent.verticalCenter
                  Label { width: parent.width; elide: Text.ElideRight; text: Pet.itemName(provRow.modelData); font.pixelSize: Style.space(11) }
                  Dim { text: "In bag: " + (win.view.bag[provRow.modelData] || 0); font.pixelSize: Style.space(9) }
                }
                Row {
                  id: provButtons
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(4)
                  XButton { width: Style.space(26); height: Style.space(24); label: "−"; enabledLook: provRow.packed > 0; onClicked: win.setProv(provRow.modelData, provRow.packed - 1) }
                  Label { anchors.verticalCenter: parent.verticalCenter; width: Style.space(22); horizontalAlignment: Text.AlignHCenter; text: provRow.packed; font.bold: true }
                  XButton { width: Style.space(26); height: Style.space(24); label: "+"; onClicked: win.setProv(provRow.modelData, provRow.packed + 1) }
                }
              }
            }

            Column {
              id: launchBox
              width: parent.width
              spacing: Style.space(6)

              Dim {
                visible: provColumn.items.length === 0
                width: parent.width
                wrapMode: Text.WordWrap
                text: "No provisions in your bag yet. Search around to find potions, apples and more."
              }
              Text {
                visible: win.launchMessage !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                text: win.launchMessage
                color: win.accent
                font.family: Style.font.family
                font.pixelSize: Style.space(11)
              }
              Dim {
                visible: Exp.freeSlots(win.view) <= 0
                width: parent.width
                wrapMode: Text.WordWrap
                text: "All your teams are out (" + Exp.slots(win.view) + " at your rank). Wait for one to come back."
                color: win.accent
              }
              XButton {
                width: parent.width
                height: Style.space(38)
                highlight: true
                fontSize: 14
                enabledLook: win.team.length > 0 && Exp.freeSlots(win.view) > 0
                label: "Set off for " + Exp.BIOMES[win.biome].name + "!"
                onClicked: win.launch()
              }
            }
          }
        }
      }

      // ================= History =================
      Tile {
        visible: win.tab === "history"
        anchors.fill: parent

        ListView {
          anchors.fill: parent
          anchors.margins: Style.space(12)
          clip: true
          spacing: Style.space(6)
          model: win.rec.history
          header: Column {
            width: parent ? parent.width : 0
            spacing: Style.space(6)
            Heading { text: "PAST EXPEDITIONS" }
            Dim { text: win.rec.total + " expeditions so far · the last " + Exp.HISTORY_SIZE + " are kept here." }
            Item { width: 1; height: Style.space(6) }
          }
          delegate: Rectangle {
            id: hist
            required property var modelData
            width: ListView.view.width
            height: Style.space(52)
            radius: Style.cornerRadius
            color: Qt.rgba(1, 1, 1, 0.03)
            Row {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(12)
              Row {
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                  model: hist.modelData.team
                  delegate: PokeSprite { required property string modelData; slug: modelData; fitWidth: Style.space(34); fitHeight: Style.space(32) }
                }
              }
              Column {
                anchors.verticalCenter: parent.verticalCenter
                Label {
                  text: Exp.BIOMES[hist.modelData.biome].name + " · " + Exp.DIFFICULTIES[hist.modelData.diff].name + "  —  " + Exp.OUTCOMES[hist.modelData.outcome]
                  font.bold: true
                  color: hist.modelData.outcome === "failed" ? win.accent : win.text
                }
                Dim {
                  text: new Date(hist.modelData.start).toLocaleString(Qt.locale(), "ddd d MMM, HH:mm") + "  ·  B" + hist.modelData.floor + "F / " + hist.modelData.floors
                        + "  ·  " + hist.modelData.kos + " defeated  ·  +" + hist.modelData.points + " pts  ·  ₽" + (hist.modelData.money || 0)
                        + (hist.modelData.recruits.length ? "  ·  joined: " + hist.modelData.recruits.map(Pet.name).join(", ") : "")
                }
              }
            }
          }
        }
      }
    }
  }
}
