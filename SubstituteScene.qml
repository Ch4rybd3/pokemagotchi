import QtQuick
import qs.Commons

// A Pokémon hitting the Substitute doll (EV / XP training).
Item {
  id: root
  property string slug: ""
  property bool shiny: false
  property bool hitting: false
  property string label: "+EV"

  Image {
    id: doll
    source: Qt.resolvedUrl("sprites/substitute.png")
    smooth: false
    width: implicitWidth * 1.6
    height: implicitHeight * 1.6
    x: root.width * 0.12 + shift
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(14)
    property real shift: 0
  }

  PokeSprite {
    id: trainee
    slug: root.slug
    shiny: root.shiny
    fitWidth: root.width * 0.42
    fitHeight: root.height - Style.space(28)
    maxPixel: 4
    integerScale: true
    x: root.width * 0.88 - width + lunge
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(14)
    property real lunge: 0
  }

  Text {
    id: hitText
    text: root.label
    color: "#f2b84b"
    font.family: Style.font.family
    font.pixelSize: Style.space(12)
    font.bold: true
    x: doll.x + doll.width / 2 - width / 2
    y: Style.space(8)
    opacity: 0
  }

  SequentialAnimation {
    running: root.hitting
    loops: Animation.Infinite
    onRunningChanged: if (!running) { trainee.lunge = 0; doll.shift = 0; hitText.opacity = 0 }
    PauseAnimation { duration: 500 }
    NumberAnimation { target: trainee; property: "lunge"; to: -Style.space(40); duration: 160; easing.type: Easing.InQuad }
    ParallelAnimation {
      NumberAnimation { target: trainee; property: "lunge"; to: 0; duration: 260; easing.type: Easing.OutQuad }
      SequentialAnimation {
        NumberAnimation { target: doll; property: "shift"; to: -6; duration: 60 }
        NumberAnimation { target: doll; property: "shift"; to: 4; duration: 60 }
        NumberAnimation { target: doll; property: "shift"; to: 0; duration: 60 }
      }
      SequentialAnimation {
        NumberAnimation { target: hitText; property: "opacity"; to: 1; duration: 80 }
        NumberAnimation { target: hitText; property: "opacity"; to: 0; duration: 420 }
      }
    }
  }
}
