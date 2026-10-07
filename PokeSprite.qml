import QtQuick

// A pokemon-colorscripts sprite, scaled to fit a box without smoothing.
Image {
  id: root
  property string slug: ""
  property bool shiny: false
  property bool silhouette: false
  property real fitWidth: 64
  property real fitHeight: 64
  property real maxPixel: 1
  property bool integerScale: false

  readonly property real fit: implicitWidth > 0
    ? Math.min(maxPixel, fitWidth / implicitWidth, fitHeight / implicitHeight) : 1
  readonly property real pixel: integerScale && fit >= 1 ? Math.floor(fit) : fit

  source: slug ? Qt.resolvedUrl("sprites/" + (silhouette ? "silhouette" : shiny ? "shiny" : "regular") + "/" + slug + ".png") : ""
  width: implicitWidth * pixel
  height: implicitHeight * pixel
  smooth: pixel < 1
  mipmap: false
}
