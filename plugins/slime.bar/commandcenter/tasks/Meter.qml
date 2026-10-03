import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import "../../ui"
import ".."

Rectangle {
  id: meter
  // the Tasks tab (TasksTab.qml), which this used to sit inside
  property var tasks: null
  property real value: 0
  property color fill: tasks.cc.ink
  height: 8
  radius: 4
  color: Qt.rgba(tasks.cc.ink.r, tasks.cc.ink.g, tasks.cc.ink.b, 0.15)
  Rectangle { width: parent.width * Math.max(0, Math.min(1, parent.value)); height: parent.height; radius: 4; color: parent.fill }
}
