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

MouseArea {
  id: gestureArea
  // the bar (Bar.qml), which this used to sit inside
  property var root: null

  property bool dragging: false
  property bool suppressClick: false
  property real pressedX: 0
  property real pressedY: 0
  readonly property real dragThreshold: Style.space(4)

  acceptedButtons: Qt.LeftButton
  cursorShape: dragging ? Qt.ClosedHandCursor : Qt.ArrowCursor
  pressAndHoldInterval: 200

  function startDrag(x, y) {
    if (dragging) return
    dragging = true
    root.beginBarMove(root.targetWindow(gestureArea))
    var scenePoint = gestureArea.mapToItem(null, x, y)
    root.updateBarMove(root.windowScreenPoint(scenePoint, root.barMoveWindow))
  }

  onPressed: function(mouse) {
    dragging = false
    suppressClick = false
    pressedX = mouse.x
    pressedY = mouse.y
  }

  onPressAndHold: function(mouse) {
    // A widget above us propagates its composed press-and-hold down here without
    // ever handing over the grab, so we'd get no release or cancel to end the move.
    if (!gestureArea.pressed) return
    startDrag(mouse.x, mouse.y)
  }

  onPositionChanged: function(mouse) {
    if (!(mouse.buttons & Qt.LeftButton)) return

    if (!dragging) {
      var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
      if (distance < dragThreshold) return
      startDrag(mouse.x, mouse.y)
      return
    }

    var scenePoint = gestureArea.mapToItem(null, mouse.x, mouse.y)
    root.updateBarMove(root.windowScreenPoint(scenePoint, root.barMoveWindow))
  }

  onReleased: function(mouse) {
    if (!dragging) return
    dragging = false
    suppressClick = true
    root.finishBarMove()
    mouse.accepted = true
  }

  onCanceled: {
    dragging = false
    suppressClick = false
    root.clearBarMove()
  }

  onClicked: function(mouse) {
    if (suppressClick) {
      suppressClick = false
      mouse.accepted = true
    }
  }

  onDoubleClicked: function(mouse) {
    if (suppressClick) {
      suppressClick = false
      return
    }
    if (mouse.button === Qt.LeftButton) {
      root.toggleTransparency()
      mouse.accepted = true
    }
  }
}
