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

PanelWindow {
  id: moveGhostWindow
  // the bar (Bar.qml), which this used to sit inside
  property var root: null

  required property var ghostScreen
  readonly property bool screenMatches: root.barMoveScreen === ghostScreen ||
    (root.barMoveScreen && ghostScreen && root.barMoveScreen.name && ghostScreen.name && root.barMoveScreen.name === ghostScreen.name)
  visible: root.barMoveActive && screenMatches
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "omarchy-bar-move-ghost"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  // Visual-only preview of the candidate edge. Keep the input region empty
  // so the overlay never steals the gesture area's active pointer grab.
  mask: Region {}

  // One fixed-geometry slab per edge, crossfaded on candidate changes.
  // Resizing a single slab between edges repaints mid-transition and
  // flickers; fading between static ones does not.
  Repeater {
    model: ["top", "bottom", "left", "right"]

    BorderSurface {
      id: edgeSlab

      required property string modelData
      readonly property bool edgeVertical: modelData === "left" || modelData === "right"
      readonly property int edgeSize: edgeVertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

      x: modelData === "right" ? parent.width - edgeSize : 0
      y: modelData === "bottom" ? parent.height - edgeSize : 0
      width: edgeVertical ? edgeSize : parent.width
      height: edgeVertical ? parent.height : edgeSize
      color: root.transparent ? "transparent" : root.background
      borderSpec: Border.flat(root.barForeground, 1)
      visible: opacity > 0
      opacity: root.barMoveCandidate === modelData ? (root.transparent ? 0.45 : 0.7) : 0

      Behavior on opacity {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }
    }
  }
}
