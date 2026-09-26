import QtQuick
import Quickshell.Io
import qs.Ui
import qs.Commons
import "../../slime.bar/ui"

BarIndicator {
  id: root

  // Slime Shell: on the slime bar this indicator is a trumpet floating in the ooze.
  readonly property bool slime: !!bar && bar.slimeSkin === true
  iconComponent: slime ? slimeIcon : null
  opticalSize: slime ? 22 : Style.bar.iconCanvas
  fixedWidth: vertical ? -1 : (slime ? 28 : Style.bar.statusSlot)

  Component {
    id: slimeIcon
    SlimeGear {
      kind: "trumpet"
      bar: root.bar
      size: parent ? parent.width : 22
      lit: root.effectiveActive
    }
  }

  property string state: "idle"
  property string icon: ""

  active: state === "recording"
  activeText: icon
  inactiveText: "󰍬"
  activeTooltipText: state
  inactiveTooltipText: "Dictate"

  function update(raw) {
    var data = extractData(raw)

    state = String(data.alt || data.class || "idle")
    if (state === "recording") icon = "󰍬"
    else if (state === "transcribing") icon = "󰔟"
    else icon = ""
  }

  Process {
    command: ["bash", "-c", "omarchy-voxtype-status"]
    running: true
    stdout: SplitParser {
      onRead: function(data) { root.update(data) }
    }
  }

  onPressed: function() {
    if (!root.bar) return
    root.bar.run("omarchy-voxtype-config")
  }
}
