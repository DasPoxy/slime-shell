import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import "../../ui"
import ".."

// ---- the tavern, deeper in: broken wall boards, a bar, a rack of mead -----
// All of it sits under a film of goo (below), so it reads as a tavern the
// slime has swallowed rather than a room you're standing in.
Shape {
  id: wp
  // the Tasks tab (TasksTab.qml), which this used to sit inside
  property var tasks: null
  property string d: ""
  property color fill: tasks.wood
  property real line: 1.4
  anchors.fill: parent
  preferredRendererType: Shape.CurveRenderer
  ShapePath {
    fillColor: wp.fill
    strokeColor: tasks.cc.ink
    strokeWidth: wp.line
    joinStyle: ShapePath.RoundJoin
    PathSvg { path: wp.d }
  }
}
