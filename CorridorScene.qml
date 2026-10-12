import QtQuick
import qs.Commons

// A Mystery Dungeon corridor: the team walks in single file in the middle while
// the dungeon scrolls past. Events of the floor wait along the way as "?" and
// the stairs show up at the end of each floor.
Item {
  id: root

  property var team: []               // Expedition.teamState()
  property var colors: ["#222222", "#444444", "#888888"]
  property int floor: 1
  property real frac: 0               // share of the current floor walked
  property real floorMs: 360000
  property var marks: []              // fractions of the floor where something happens
  property string status: "running"   // running | returning | done
  property real homeward: 0           // ms walked on the way home
  property string weather: ""
  property bool active: true          // run the animations

  // Walking speed on screen. The world is laid out in pixels: one floor is
  // `floorLength` wide, so what you see moves at the real pace of the team.
  readonly property real speed: 22                       // px per second
  readonly property real floorLength: speed * floorMs / 1000
  readonly property real target: status === "returning" ? floor * floorLength - homeward / 1000 * speed
                                : status === "done" ? floor * floorLength
                                : (floor - 1 + frac) * floorLength
  readonly property bool walking: active && status !== "done"
  readonly property real ground: height - Style.space(30)
  readonly property real front: width * 0.62

  // Smoothed position of the camera, so the corridor glides between refreshes.
  property real offset: target
  Behavior on offset { enabled: root.walking; NumberAnimation { duration: 1100 } }

  function screenX(worldX) { return front + worldX - offset }

  // Back wall
  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.0) }
      GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.25) }
    }
  }
  Rectangle {
    anchors.fill: parent
    color: root.colors[0]
    opacity: 0.55
  }

  // Rocks and pillars on the far wall (slower: parallax)
  Repeater {
    model: Math.ceil(root.width / 56) + 2
    delegate: Rectangle {
      required property int index
      readonly property real step: 56
      readonly property real shift: (root.offset * 0.5) % step
      x: index * step - shift - step
      y: Style.space(14) + (index * 37 % 5) * 3
      width: step - 14 - (index * 13 % 4) * 3
      height: root.ground - y - Style.space(6)
      radius: Style.space(6)
      color: root.colors[1]
      opacity: 0.28
    }
  }

  // Floor
  Rectangle {
    y: root.ground
    width: parent.width
    height: parent.height - y
    color: root.colors[1]
    opacity: 0.6
  }
  Rectangle {
    y: root.ground
    width: parent.width
    height: 2
    color: root.colors[2]
    opacity: 0.45
  }
  Repeater {
    model: Math.ceil(root.width / 34) + 2
    delegate: Rectangle {
      required property int index
      readonly property real step: 34
      x: index * step - root.offset % step - step
      y: root.ground + 2
      width: 2
      height: root.height - y
      color: root.colors[0]
      opacity: 0.35
    }
  }

  // Stairs at the end of the floor
  Item {
    visible: root.status === "running"
    x: root.screenX(root.floor * root.floorLength) - width / 2
    y: root.ground - height + 4
    width: Style.space(34)
    height: Style.space(30)
    Repeater {
      model: 4
      delegate: Rectangle {
        required property int index
        x: index * Style.space(5)
        y: index * Style.space(7)
        width: parent.width - index * Style.space(5)
        height: Style.space(6)
        radius: 2
        color: root.colors[2]
        opacity: 0.9 - index * 0.15
      }
    }
  }

  // What waits on this floor
  Repeater {
    model: root.status === "running" ? root.marks : []
    delegate: Text {
      required property var modelData
      readonly property real at: root.screenX((root.floor - 1 + modelData) * root.floorLength)
      visible: at > -20 && at < root.width + 20
      x: at - width / 2
      y: root.ground - height - Style.space(18)
      text: "?"
      color: "#f2b84b"
      font.family: Style.font.family
      font.pixelSize: Style.space(20)
      font.bold: true
      SequentialAnimation on opacity {
        running: root.active
        loops: Animation.Infinite
        NumberAnimation { to: 0.4; duration: 650 }
        NumberAnimation { to: 1; duration: 650 }
      }
    }
  }

  // The team, in single file. Sprites look left: flip them to walk right.
  Repeater {
    model: root.team
    delegate: Item {
      id: member
      required property var modelData
      required property int index
      readonly property bool down: modelData.hp <= 0
      readonly property real gap: Style.space(72)
      width: sprite.width
      height: sprite.height
      x: (root.status === "returning" ? root.front - Style.space(70) + index * gap : root.front - index * gap) - width / 2
      y: root.ground - height + Style.space(4) + (down ? Style.space(6) : 0)
      opacity: down ? 0.35 : 1
      z: 10 - index

      PokeSprite {
        id: sprite
        slug: member.modelData.species
        shiny: member.modelData.shiny
        fitWidth: Style.space(60)
        fitHeight: Style.space(54)
        maxPixel: 3
        y: hop
        property real hop: 0
        transform: Scale { origin.x: sprite.width / 2; xScale: root.status === "returning" ? 1 : -1 }
        SequentialAnimation on hop {
          running: root.walking && !member.down
          loops: Animation.Infinite
          PauseAnimation { duration: member.index * 110 }
          NumberAnimation { to: -4; duration: 170; easing.type: Easing.OutQuad }
          NumberAnimation { to: 0; duration: 170; easing.type: Easing.InQuad }
          PauseAnimation { duration: 240 - member.index * 110 }
        }
      }
    }
  }

  // Weather
  Rectangle {
    anchors.fill: parent
    visible: root.weather === "fog"
    color: "white"
    opacity: 0.12
  }
  Repeater {
    model: ["rain", "hail", "sand"].indexOf(root.weather) >= 0 ? 18 : 0
    delegate: Rectangle {
      required property int index
      readonly property real seed: (index * 53 % 17) / 17
      width: root.weather === "rain" ? 1 : 3
      height: root.weather === "rain" ? 9 : 3
      radius: root.weather === "rain" ? 0 : 2
      color: root.weather === "sand" ? "#d8b878" : "white"
      opacity: 0.5
      x: seed * root.width
      rotation: root.weather === "rain" ? 15 : 0
      NumberAnimation on y {
        running: root.active
        loops: Animation.Infinite
        from: -10 - seed * 40
        to: root.height
        duration: (root.weather === "rain" ? 700 : 1800) + seed * 600
      }
    }
  }
}
