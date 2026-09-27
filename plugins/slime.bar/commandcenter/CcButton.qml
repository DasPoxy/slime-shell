import QtQuick

// Pill button used across the command centre: inked when on, a pale wash of
// the slime when off.
Rectangle {
  id: button
  required property var cc
  property string text: ""
  property string icon: ""
  property bool on: false
  property real pad: 18
  property real fontSize: 12
  signal clicked
  // a stop for the command centre's keyboard navigation
  readonly property bool ccFocusable: true
  function ccActivate() { clicked() }

  implicitWidth: row.implicitWidth + pad
  implicitHeight: 26
  radius: height / 2
  color: on ? cc.ink : (hover.hovered ? Qt.rgba(1, 1, 1, 0.75) : Qt.rgba(1, 1, 1, 0.5))

  HoverHandler { id: hover }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: 6
    Text {
      visible: button.icon !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: button.icon
      color: button.on ? button.cc.slime : button.cc.ink
      font.family: button.cc.font
      font.pixelSize: button.fontSize + 1
    }
    Text {
      visible: button.text !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: button.text
      color: button.on ? button.cc.slime : button.cc.ink
      font.family: button.cc.font
      font.pixelSize: button.fontSize
      font.bold: true
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: button.clicked()
  }
}
