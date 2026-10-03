import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import "../../ui"
import ".."

Rectangle {
  id: stateBox
  // the Tasks tab (TasksTab.qml), which this used to sit inside
  property var tasks: null
  property string state3: "todo"
  width: 16; height: 16; radius: 5
  color: state3 === "done" ? tasks.cc.ink : state3 === "doing" ? Qt.rgba(tasks.cc.ink.r, tasks.cc.ink.g, tasks.cc.ink.b, 0.35) : "transparent"
  border.color: tasks.cc.ink
  border.width: 2
  Text {
    anchors.centerIn: parent
    text: parent.state3 === "done" ? "" : parent.state3 === "doing" ? "" : ""
    color: parent.state3 === "done" ? tasks.cc.slime : tasks.cc.ink
    font.family: tasks.cc.font
    font.pixelSize: Math.round(8 * tasks.fs) }
}
