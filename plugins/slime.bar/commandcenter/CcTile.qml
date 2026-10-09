import QtQuick

// Quick-toggle tile: a big glyph over a label, inked solid when on.
Rectangle {
  id: tile
  // the command centre's text size (Settings → Command centre → text size)
  readonly property real fs: cc && cc.fontScale ? cc.fontScale : 1
  required property var cc
  property string icon: ""
  property string label: ""
  property string detail: ""
  property bool on: false
  property bool busy: false
  signal clicked
  readonly property bool ccFocusable: true
  function ccActivate() { clicked() }

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
      textFormat: Text.PlainText
      anchors.horizontalCenter: parent.horizontalCenter
      text: tile.icon
      color: tile.on ? tile.cc.slime : tile.cc.ink
      font.family: tile.cc.font
      font.pixelSize: Math.round(18 * tile.fs) }
    Text {
      textFormat: Text.PlainText
      anchors.horizontalCenter: parent.horizontalCenter
      // shrinks to fit the tile at bigger text sizes
      width: Math.min(implicitWidth, tile.width - 4)
      horizontalAlignment: Text.AlignHCenter
      fontSizeMode: Text.HorizontalFit
      minimumPixelSize: 8
      text: tile.label
      color: tile.on ? tile.cc.slime : tile.cc.ink
      font.family: tile.cc.font
      font.pixelSize: Math.round(11 * tile.fs)
      font.bold: true
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: tile.clicked()
  }
}
