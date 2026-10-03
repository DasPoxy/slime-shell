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
  id: centerRoot
  // the bar (Bar.qml), which this used to sit inside
  property var root: null

  property var entries: root.layoutEntries("center")
  readonly property bool hasAnchor: root.entryIndex(entries, root.centerAnchor) !== -1
  readonly property var anchorEntry: root.findCenterAnchorEntry()

  Loader {
    anchors.fill: parent
    sourceComponent: root.vertical ? verticalCenterModules : horizontalCenterModules
  }

  Component {
    id: horizontalCenterModules

    Item {
      anchors.fill: parent

      CenterGestureArea { root: centerRoot.root; anchors.fill: parent }

      CenterRevealHover { root: centerRoot.root }

      ModuleList {
        root: centerRoot.root
        visible: !centerRoot.hasAnchor
        entries: centerRoot.entries
        region: "center"
        anchors.centerIn: parent
      }

      ModuleList {
        root: centerRoot.root
        visible: centerRoot.hasAnchor
        entries: root.entriesBefore(centerRoot.entries, root.centerAnchor)
        region: "center"
        anchors.right: centerAnchorModule.left
        anchors.verticalCenter: centerAnchorModule.verticalCenter
      }

      ModuleSlot {
        root: centerRoot.root
        id: centerAnchorModule
        visible: centerRoot.hasAnchor
        entry: centerRoot.anchorEntry
        region: "center"
        anchors.centerIn: parent
      }

      ModuleList {
        root: centerRoot.root
        visible: centerRoot.hasAnchor
        entries: root.entriesAfter(centerRoot.entries, root.centerAnchor)
        region: "center"
        anchors.left: centerAnchorModule.right
        anchors.verticalCenter: centerAnchorModule.verticalCenter
      }
    }
  }

  Component {
    id: verticalCenterModules

    Item {
      anchors.fill: parent

      CenterGestureArea { root: centerRoot.root; anchors.fill: parent }

      CenterRevealHover { root: centerRoot.root }

      ModuleList {
        root: centerRoot.root
        visible: !centerRoot.hasAnchor
        entries: centerRoot.entries
        region: "center"
        anchors.centerIn: parent
      }

      ModuleList {
        root: centerRoot.root
        visible: centerRoot.hasAnchor
        entries: root.entriesBefore(centerRoot.entries, root.centerAnchor)
        region: "center"
        anchors.bottom: centerAnchorModule.top
        anchors.horizontalCenter: centerAnchorModule.horizontalCenter
      }

      ModuleSlot {
        root: centerRoot.root
        id: centerAnchorModule
        visible: centerRoot.hasAnchor
        entry: centerRoot.anchorEntry
        region: "center"
        anchors.centerIn: parent
      }

      ModuleList {
        root: centerRoot.root
        visible: centerRoot.hasAnchor
        entries: root.entriesAfter(centerRoot.entries, root.centerAnchor)
        region: "center"
        anchors.top: centerAnchorModule.bottom
        anchors.horizontalCenter: centerAnchorModule.horizontalCenter
      }
    }
  }
}
