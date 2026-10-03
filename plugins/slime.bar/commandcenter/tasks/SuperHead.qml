import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import "../../ui"
import ".."

// A super group's heading (Todo and Task Log lists)
Rectangle {
  id: sh
  // the Tasks tab (TasksTab.qml), which this used to sit inside
  property var tasks: null
  property string name: ""
  property bool collapsed: false
  property int count: 0
  property bool here: false
  signal toggle()
  signal menu(real x, real y)
  radius: 10
  color: tasks.superHeadColor(name, here, shMouse.containsMouse)
  border.color: tasks.cc.ink
  border.width: here ? 2 : 1
  Rectangle { width: 7; height: parent.height; radius: 3.5; color: tasks.superColor(sh.name) }
  Row {
    x: 12; spacing: 7
    anchors.verticalCenter: parent.verticalCenter
    Text { anchors.verticalCenter: parent.verticalCenter; text: sh.collapsed ? "\uf054" : "\uf078"; color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(9 * tasks.fs) }
    Text { anchors.verticalCenter: parent.verticalCenter; text: "\uf247"; color: tasks.superColor(sh.name); style: Text.Outline; styleColor: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(13 * tasks.fs) }
    Text { anchors.verticalCenter: parent.verticalCenter; text: sh.name; color: tasks.cc.ink; font.family: tasks.cc.displayFont; font.weight: tasks.cc.displayWeight; font.pixelSize: Math.round(14 * tasks.fs) }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: sh.collapsed
      text: sh.count + (sh.count === 1 ? " todo" : " todos")
      color: tasks.cc.ink; opacity: 0.6; font.family: tasks.cc.font; font.pixelSize: Math.round(10 * tasks.fs) }
  }
  MouseArea {
    id: shMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: mouse => {
      if (mouse.button === Qt.RightButton) { var p = mapToItem(tasks, mouse.x, mouse.y); sh.menu(p.x, p.y) }
      else sh.toggle()
    }
  }
}
