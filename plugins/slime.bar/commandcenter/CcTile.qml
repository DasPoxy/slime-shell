import QtQuick

// Quick-toggle tile: a big glyph over a label, inked solid when on.
Rectangle {
  id: tile
  required property var cc
  property string icon: ""
  property string label: ""
  property string detail: ""
  property bool on: false
  property bool busy: false
  signal clicked

  implicitHeight: 58
  radius: 16
  color: on ? cc.ink : (hover.hovered ? Qt.rgba(1, 1, 1, 0.72) : Qt.rgba(1, 1, 1, 0.45))
  opacity: busy ? 0.6 : 1
  Behavior on color { ColorAnimation { duration: 160 } }

  HoverHandler { id: hover }

  Column {
    anchors.centerIn: parent
    spacing: 2
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: tile.icon
      color: tile.on ? tile.cc.slime : tile.cc.ink
      font.family: tile.cc.font
      font.pixelSize: 18
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: tile.label
      color: tile.on ? tile.cc.slime : tile.cc.ink
      font.family: tile.cc.font
      font.pixelSize: 11
      font.bold: true
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: tile.clicked()
  }
}
