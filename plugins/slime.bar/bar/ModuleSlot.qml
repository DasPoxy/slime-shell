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

Item {
  id: slot
  // the bar (Bar.qml), which this used to sit inside
  property var root: null

  required property var entry
  property string region: ""
  readonly property string moduleName: root.entryId(entry)
  readonly property var moduleSettings: root.entrySettings(entry)
  readonly property string customType: root.customModuleType(entry)
  readonly property var registryMetadata: root.barWidgetRegistry.metadataFor(root.canonicalWidgetId(moduleName))
  readonly property bool firstParty: registryMetadata && registryMetadata.firstParty === true
  readonly property string pluginApiId: registered ? root.canonicalWidgetId(moduleName) : "bar-entry:" + moduleName
  // Re-evaluate when the registry mutates (Component reference changes,
  // plugin enabled/disabled, etc.). Reading the `widgets` property creates
  // the binding dependency — the wrapped function call alone wouldn't.
  readonly property var registryComponent: {
    var w = root.barWidgetRegistry.widgets
    if (customType) return null
    var registryName = root.canonicalWidgetId(moduleName)
    return w[registryName] ? w[registryName].component : null
  }
  readonly property bool qmlCustom: customType === "qml"
  readonly property bool commandCustom: customType === "command"
  readonly property bool registered: registryComponent !== null
  readonly property var activeItem: {
    if (registered) return registryLoader.item
    if (qmlCustom) return qmlLoader.item
    return componentLoader.item
  }
  readonly property bool hovered: moduleHover.hovered
  readonly property real bobPhase: {
    var h = 0
    for (var i = 0; i < moduleName.length; i++) h = (h * 31 + moduleName.charCodeAt(i)) % 997
    return h / 997 * 6.283
  }
  readonly property bool dragSource: root.barDragSource === slot
  readonly property bool panelOpen: root.activePopout === slot.activeItem
  // Modules bigger than the mark they want (a text label in a padded slot,
  // a multi-line stack on a vertical bar) can say how long the open-panel
  // dot should be along the bar, so it tracks what the module paints
  // instead of a fraction of whatever slot it happens to fill.
  readonly property real panelIndicatorExtent: {
    var key = root.vertical ? "openPanelIndicatorHeight" : "openPanelIndicatorWidth"
    var hint = activeItem && key in activeItem ? activeItem[key] : undefined
    if (hint !== undefined && hint !== null && hint > 0) return Math.round(hint)
    return Math.max(Style.space(10), Math.round((root.vertical ? slot.height : slot.width) * 0.55))
  }
  implicitWidth: activeItem && activeItem.visible ? (root.vertical ? root.barSize : activeItem.implicitWidth) : 0
  implicitHeight: activeItem && activeItem.visible ? activeItem.implicitHeight : 0
  width: implicitWidth
  height: implicitHeight
  z: modulePointer.dragging ? 100 : 0

  Component.onCompleted: root.registerModuleSlot(slot)
  onXChanged: root.bulbsDirty()
  onYChanged: root.bulbsDirty()
  onWidthChanged: root.bulbsDirty()
  onHeightChanged: root.bulbsDirty()
  onVisibleChanged: root.bulbsDirty()
  Component.onDestruction: {
    if (root.barDragSource === slot) root.clearBarDrag()
    root.unregisterModuleSlot(slot)
  }

  HoverHandler { id: moduleHover }

  BorderSurface {
    visible: slot.dragSource
    anchors.fill: parent
    anchors.margins: Style.space(1)
    color: root.transparent ? "transparent" : root.background
    borderSpec: Border.flat(root.barForeground, 1)
    radius: Math.min(Style.cornerRadius, height / 2)
    opacity: root.transparent ? 0.22 : 0.32
  }

  Loader {
    id: componentLoader
    active: !slot.qmlCustom && !slot.registered
    sourceComponent: slot.commandCustom ? customCommandModuleComponent : emptyModuleComponent
    anchors.fill: parent
    opacity: slot.dragSource ? 0.22 : 1.0
    // Floating in the ooze: each widget bobs and sways on its own phase.
    transform: Translate { y: root.bob(slot.bobPhase) }
    rotation: root.sway(slot.bobPhase)
    onLoaded: {
      slot.injectProps()
      Qt.callLater(slot.injectProps)
    }
  }

  Loader {
    id: registryLoader
    active: slot.registered
    sourceComponent: slot.registered ? slot.registryComponent : null
    anchors.fill: parent
    opacity: slot.dragSource ? 0.22 : 1.0
    // Floating in the ooze: each widget bobs and sways on its own phase.
    transform: Translate { y: root.bob(slot.bobPhase) }
    rotation: root.sway(slot.bobPhase)
    onLoaded: {
      slot.injectProps()
      Qt.callLater(slot.injectProps)
    }
  }

  Loader {
    id: qmlLoader
    active: slot.qmlCustom
    source: slot.qmlCustom ? root.customModuleSource(slot.entry) : ""
    anchors.fill: parent
    opacity: slot.dragSource ? 0.22 : 1.0
    // Floating in the ooze: each widget bobs and sways on its own phase.
    transform: Translate { y: root.bob(slot.bobPhase) }
    rotation: root.sway(slot.bobPhase)
    onLoaded: {
      slot.injectProps()
      Qt.callLater(slot.injectProps)
    }
  }

  Rectangle {
    id: openPanelIndicator

    readonly property int inset: Style.space(2)

    visible: opacity > 0
    opacity: slot.panelOpen && !slot.dragSource ? 0.9 : 0
    color: Color.accent
    radius: Math.min(width, height) / 2
    width: root.vertical ? Style.space(2) : slot.panelIndicatorExtent
    height: root.vertical ? slot.panelIndicatorExtent : Style.space(2)
    // The mark sits on the module's inner edge — the one facing the
    // desktop — so it underlines a top bar, overlines a bottom one, and
    // points inward from a left or right one. It reads as pointing at the
    // panel that opens on that side.
    x: root.vertical
      ? (root.position === "left" ? parent.width - width - inset : inset)
      : Math.round((parent.width - width) / 2)
    y: root.vertical
      ? Math.round((parent.height - height) / 2)
      : (root.position === "top" ? parent.height - height - inset : inset)
    z: 50

    Behavior on opacity {
      NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
    }
  }

  MouseArea {
    id: modulePointer

    property bool dragging: false
    property bool suppressClick: false
    property real pressedX: 0
    property real pressedY: 0
    readonly property bool canReorder: root.shell && typeof root.shell.mutateShellConfig === "function"
    readonly property real dragThreshold: Style.space(4)

    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    enabled: slot.visible && slot.width > 0 && slot.height > 0
    propagateComposedEvents: true
    cursorShape: root.moduleClickTargetAt(slot, mouseX, mouseY) ? Qt.PointingHandCursor : Qt.ArrowCursor
    // Do not assign drag.target here: ModuleSlot is owned by Row/Column
    // positioners, and mutating slot.x/slot.y can leave stale offsets that
    // make neighboring modules overlap after a small aborted drag.

    onPressed: function(mouse) {
      dragging = false
      suppressClick = false
      pressedX = mouse.x
      pressedY = mouse.y
      root.clearBarDrag()
    }

    onPositionChanged: function(mouse) {
      if (!canReorder || !(mouse.buttons & Qt.LeftButton)) return

      var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
      if (distance >= dragThreshold) {
        if (!dragging) {
          root.barDragWindow = root.targetWindow(slot.activeItem) || root.targetWindow(slot)
          root.barDragScreen = root.barDragWindow ? root.barDragWindow.screen : null
          root.barDragOffsetX = pressedX
          root.barDragOffsetY = pressedY
          root.captureBarDragGhost(slot)
          root.barDragSource = slot
        }
        dragging = true
        root.hideTooltip(slot.activeItem)
      }

      if (dragging) {
        var scenePoint = slot.mapToItem(null, mouse.x, mouse.y)
        var screenPoint = root.barDragScreenPoint(scenePoint)
        root.barDragSceneX = scenePoint.x
        root.barDragSceneY = scenePoint.y
        root.barDragScreenX = screenPoint.x
        root.barDragScreenY = screenPoint.y

        var edge = root.pillEdgeDrop(slot, scenePoint)
        root.barDragEdge = edge
        var drop = edge ? { slot: edge.other, after: edge.side > 0 } : root.moduleDropAtScene(scenePoint, slot)
        root.barDragTarget = drop ? drop.slot : null
        root.barDragAfter = drop ? drop.after : false
        root.barDragMerge = !edge && !!drop && root.pillMergeAt(drop.slot, scenePoint)
        root.barDragTargetGeometry = edge ? edge.marker : !drop ? null
          : root.barDragMerge ? root.mergeMarkerRect(drop.slot) : root.dropMarkerRect(drop.slot, drop.after)
      }
    }

    onReleased: function(mouse) {
      var wasDragging = dragging
      var targetSlot = root.barDragTarget
      var afterTarget = root.barDragAfter
      var merge = root.barDragMerge
      var edge = root.barDragEdge

      if (wasDragging) suppressClick = true

      dragging = false
      root.clearBarDrag()

      if (wasDragging && edge) {
        if (edge.kind === "swap") root.mergePills(slot, edge.other)   // pill-mates: swaps them
        else root.splitFromPill(slot, edge.side)
        mouse.accepted = true
      } else if (wasDragging && targetSlot) {
        if (merge) root.mergePills(slot, targetSlot)
        else root.dropBarModuleAtTarget(slot, targetSlot, afterTarget)
        mouse.accepted = true
      } else if (!wasDragging) {
        mouse.accepted = false
      }
    }

    onCanceled: {
      dragging = false
      suppressClick = false
      root.clearBarDrag()
    }

    onClicked: function(mouse) {
      if (suppressClick) {
        suppressClick = false
        mouse.accepted = true
        return
      }

      if (!root.pressModuleClickTarget(slot, mouse.button, mouse.x, mouse.y)) mouse.accepted = false
    }
  }

  onActiveItemChanged: Qt.callLater(injectProps)
  onModuleSettingsChanged: injectProps()

  function injectProps() {
    var target = activeItem
    if (!target) return
    // a custom command module reads its own name and settings off its entry
    if (slot.commandCustom) return
    // Slime widgets are clones of the built-ins, so they get the full bar
    // host exactly like the originals do.
    var trusted = firstParty || moduleName.indexOf("slime.") === 0
    if ("bar" in target) target.bar = trusted
      ? root : root.pluginBarApiFor(pluginApiId, moduleName, registered)
    if ("moduleName" in target) target.moduleName = moduleName
    if ("settings" in target) target.settings = moduleSettings
  }

  Component { id: emptyModuleComponent; Item { implicitWidth: 0; implicitHeight: 0; visible: false } }

  Component {
    id: customCommandModuleComponent
    CustomCommandModule { root: slot.root; entry: slot.entry }
  }
}
