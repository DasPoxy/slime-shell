import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQml
import QtQuick.Shapes
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../BarModel.js" as BarModel
import "../SlimeHub.js" as SlimeHub
import "../commandcenter"
import "../ui"
import "../dock"

// Hovering the centre section near the indicators reveals them.
HoverHandler {
  id: crh
  // the bar (Bar.qml), which this used to sit inside
  property var root: null
  property bool near: false
  function check() {
    var n = hovered && root.pointerNearIndicators(crh.parent, point.position)
    if (n !== near) { near = n; root.setCenterSectionHovered(n) }
  }
  onHoveredChanged: check()
  onPointChanged: check()
}
