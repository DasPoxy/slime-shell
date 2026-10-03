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
  id: ghostWindow
  // the bar (Bar.qml), which this used to sit inside
  property var root: null

  required property var ghostScreen
  readonly property bool screenMatches: root.barDragScreen === ghostScreen ||
    (root.barDragScreen && ghostScreen && root.barDragScreen.name && ghostScreen.name && root.barDragScreen.name === ghostScreen.name)
  readonly property bool active: root.barDragSource && root.barDragScreen && screenMatches
  readonly property var sourceItem: root.barDragSource ? root.barDragSource.activeItem : null
  readonly property int ghostPadding: Style.space(1)
  readonly property int ghostWidth: sourceItem ? Math.max(1, Math.ceil(sourceItem.width)) : 1
  readonly property int ghostHeight: sourceItem ? Math.max(1, Math.ceil(sourceItem.height)) : 1

  visible: active && sourceItem !== null
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "omarchy-bar-drag-ghost"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  // Visual-only drag feedback. Keep the input region empty so the ghost can
  // sit under the cursor without stealing the MouseArea's active pointer grab.
  mask: Region {}

  Item {
    visible: ghostWindow.visible
    x: Math.round(root.barDragScreenX - root.barDragOffsetX - ghostWindow.ghostPadding)
    y: Math.round(root.barDragScreenY - root.barDragOffsetY - ghostWindow.ghostPadding)
    width: ghostWindow.ghostWidth + ghostWindow.ghostPadding * 2
    height: ghostWindow.ghostHeight + ghostWindow.ghostPadding * 2

    BorderSurface {
      anchors.fill: parent
      color: root.transparent ? "transparent" : root.background
      borderSpec: Border.flat(root.barForeground, 1)
      radius: Math.min(Style.cornerRadius, height / 2)
      opacity: root.transparent ? 0.45 : 0.94
    }

    Image {
      anchors.fill: parent
      anchors.margins: ghostWindow.ghostPadding
      source: root.barDragImageUrl
      fillMode: Image.Stretch
      smooth: true
      opacity: 0.84
    }
  }

  Rectangle {
    readonly property var targetRect: root.barDragTargetGeometry

    visible: ghostWindow.active && targetRect !== null
    x: targetRect ? Math.round(targetRect.x) : 0
    y: targetRect ? Math.round(targetRect.y) : 0
    width: targetRect ? targetRect.width : 0
    height: targetRect ? targetRect.height : 0
    color: Color.accent
    radius: Math.min(width, height) / 2
  }
}
