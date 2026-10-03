import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import "../../ui"
import ".."

Item {
  id: sign
  // the Tasks tab (TasksTab.qml), which this used to sit inside
  property var tasks: null
  property string key: ""
  property string label: ""
  property string glyph: ""
  readonly property bool on: tasks.tab === key
  width: signBoard.width
  height: 46
  transformOrigin: Item.Top
  rotation: on ? Math.sin((tasks.bar ? tasks.bar.animTime : 0) * 2.2) * 2.5 : 0
  // chains
  Rectangle { x: 10; y: 0; width: 2; height: 10; color: tasks.cc.ink; opacity: 0.8 }
  Rectangle { x: parent.width - 12; y: 0; width: 2; height: 10; color: tasks.cc.ink; opacity: 0.8 }
  Rectangle {
    id: signBoard
    y: 9
    width: signText.implicitWidth + 30
    height: 32
    radius: 7
    color: sign.on ? tasks.woodLight : tasks.wood
    border.color: tasks.cc.ink
    border.width: sign.on ? 2.4 : 1.5
    // grain
    Rectangle { x: 6; y: 9; width: parent.width - 12; height: 1; color: tasks.cc.ink; opacity: 0.18 }
    Rectangle { x: 10; y: 21; width: parent.width - 24; height: 1; color: tasks.cc.ink; opacity: 0.14 }
    Text {
      id: signText
      anchors.centerIn: parent
      text: sign.glyph + "  " + sign.label
      color: sign.on ? tasks.cc.ink : Qt.rgba(tasks.cc.ink.r, tasks.cc.ink.g, tasks.cc.ink.b, 0.75)
      font.family: tasks.cc.displayFont
      font.weight: tasks.cc.displayWeight
      font.pixelSize: Math.round(15 * tasks.fs) }
  }
  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { tasks.tab = sign.key; tasks.forceActiveFocus() } }
}
