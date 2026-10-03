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

Loader {
  id: moduleListRoot
  // the bar (Bar.qml), which this used to sit inside
  property var root: null

  property var entries: []
  property string region: ""

  visible: entries.length > 0
  // A hidden list must not build its modules. The center section declares
  // both an anchored and an unanchored arrangement and shows whichever
  // fits, so leaving the other one loaded mounts every center module
  // twice — two IPC handlers registered for the same target, two clocks
  // ticking, two of every timer and fetch behind them.
  active: visible && entries.length > 0
  sourceComponent: root.vertical ? verticalModuleList : horizontalModuleList
  width: item ? item.implicitWidth : 0
  height: item ? item.implicitHeight : 0
  onXChanged: root.bulbsDirty()
  onYChanged: root.bulbsDirty()
  onWidthChanged: root.bulbsDirty()
  onVisibleChanged: root.bulbsDirty()

  Component {
    id: horizontalModuleList

    Row {
      spacing: 0

      Repeater {
        model: moduleListRoot.entries

        ModuleSlot {
          root: moduleListRoot.root
          required property var modelData
          entry: modelData
          region: moduleListRoot.region
        }
      }
    }
  }

  Component {
    id: verticalModuleList

    Column {
      spacing: 0

      Repeater {
        model: moduleListRoot.entries

        ModuleSlot {
          root: moduleListRoot.root
          required property var modelData
          entry: modelData
          region: moduleListRoot.region
        }
      }
    }
  }
}
