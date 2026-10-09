import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import "../../ui"
import ".."

// a barrel on its side, end-on: hoops, a mead mark, a tap
Item {
  id: mb
  // the Tasks tab (TasksTab.qml), which this used to sit inside
  property var tasks: null
  property real size: 54
  width: size; height: size
  Rectangle { anchors.fill: parent; radius: width / 2; color: tasks.wood; border.color: tasks.cc.ink; border.width: 1.8 }
  Rectangle { anchors.centerIn: parent; width: parent.width * 0.78; height: width; radius: width / 2; color: "transparent"; border.color: tasks.cc.ink; border.width: 1.2 }
  Rectangle { anchors.centerIn: parent; width: parent.width * 0.52; height: width; radius: width / 2; color: tasks.woodLight; border.color: tasks.cc.ink; border.width: 1 }
  Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: "M"; color: tasks.cc.ink; font.family: tasks.cc.displayFont; font.pixelSize: mb.size * 0.26 }
  Rectangle { x: parent.width / 2 - 3; y: parent.height * 0.86; width: 6; height: 9; radius: 2; color: tasks.cc.ink }
}
