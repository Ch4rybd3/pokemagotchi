import QtQuick
import "Pet.js" as Pet

// An item sprite (PokeAPI / pokesprite), scaled without smoothing.
Image {
  property string item: ""
  property real scale_: 1
  source: item ? Qt.resolvedUrl("sprites/items/" + Pet.itemSprite(item) + ".png") : ""
  width: implicitWidth * scale_
  height: implicitHeight * scale_
  smooth: false
}
