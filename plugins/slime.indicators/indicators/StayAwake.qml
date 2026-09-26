import QtQuick
import qs.Ui
import qs.Commons
import "../../slime.bar/ui"

BarIndicator {
  id: root

  // Slime Shell: on the slime bar this indicator is a mug floating in the ooze.
  readonly property bool slime: !!bar && bar.slimeSkin === true
  iconComponent: slime ? slimeIcon : null
  opticalSize: slime ? 22 : Style.bar.iconCanvas
  fixedWidth: vertical ? -1 : (slime ? 28 : Style.bar.statusSlot)

  Component {
    id: slimeIcon
    SlimeGear {
      kind: "mug"
      bar: root.bar
      size: parent ? parent.width : 22
      lit: root.effectiveActive
    }
  }

  readonly property var idleService: bar?.shell?.firstPartyServiceFor("omarchy.idle")

  active: idleService ? idleService.stayAwake : false
  activeText: "󰅶"
  inactiveText: "󰅶"
  activeTooltipText: "Allow Idle Lock & Screensaver"
  inactiveTooltipText: "Stay Awake"

  function toggle() {
    if (root.idleService) root.idleService.setIdleEnabled(root.active)
  }

  onPressed: function() { root.toggle() }
}
