import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "../../slime.bar/ui"

BarIndicator {
  id: root

  // Slime Shell: on the slime bar this indicator is a hourglass floating in the ooze.
  readonly property bool slime: !!bar && bar.slimeSkin === true
  iconComponent: slime ? slimeIcon : null
  opticalSize: slime ? 22 : Style.bar.iconCanvas
  fixedWidth: vertical ? -1 : (slime ? 28 : Style.bar.statusSlot)

  Component {
    id: slimeIcon
    SlimeIndicatorIcon {
      kind: "hourglass"
      bar: root.bar
      size: parent ? parent.width : 22
      lit: root.effectiveActive
      // plain objects, or slimes with the objects inside (right-click the indicators)
      iconSet: root.indicatorHost && root.indicatorHost.iconSet ? root.indicatorHost.iconSet : "gear"
      hue: 3
    }
  }

  property int reminderCount: 0
  property string tooltip: ""

  active: reminderCount > 0
  activeText: "󰢌"
  inactiveText: "󰢌"
  activeTooltipText: tooltip
  inactiveTooltipText: tooltip

  function refresh() {
    if (!jsonProc.running) jsonProc.running = true
  }

  function openReminderFlow() {
    Quickshell.execDetached(["omarchy-reminder", "-i"])
  }

  function update(raw) {
    var data = extractData(raw)
    reminderCount = Number(data.count || 0)
    tooltip = String(data.tooltip || "")
  }

  Component.onCompleted: refresh()

  Connections {
    target: root.indicatorHost
    ignoreUnknownSignals: true
    function onRefreshRequested() { root.refresh() }
  }

  Process {
    id: jsonProc
    command: ["omarchy-reminder", "show", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.update(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.reminderCount = 0
        root.tooltip = ""
      }
    }
  }

  onPressed: function(b) {
    // right-click: the indicators' drip menu (plain objects or slimes)
    if (b === Qt.RightButton && root.indicatorHost && root.indicatorHost.openIconMenu) { root.indicatorHost.openIconMenu(); return }
    if (root.reminderCount > 0) Quickshell.execDetached(["omarchy-reminder", "show"])
    else root.openReminderFlow()
  }
}
