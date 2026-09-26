import QtQuick
import qs.Ui
import qs.Commons
import "../../slime.bar/ui"

BarIndicator {
  id: root

  // Slime Shell: on the slime bar this indicator is a candle floating in the ooze.
  readonly property bool slime: !!bar && bar.slimeSkin === true
  iconComponent: slime ? slimeIcon : null
  opticalSize: slime ? 22 : Style.bar.iconCanvas
  fixedWidth: vertical ? -1 : (slime ? 28 : Style.bar.statusSlot)

  Component {
    id: slimeIcon
    SlimeGear {
      kind: "candle"
      bar: root.bar
      size: parent ? parent.width : 22
      lit: root.effectiveActive
    }
  }

  readonly property var nightlightService: bar?.shell?.firstPartyServiceFor("omarchy.nightlight")

  active: nightlightService ? nightlightService.enabled : false
  activeText: "󰔎"
  inactiveText: "󰔎"
  activeTooltipText: "Day Light"
  inactiveTooltipText: "Night Light"

  function toggle() {
    if (root.nightlightService) root.nightlightService.setNightlight(!root.active)
  }

  onPressed: function() { root.toggle() }
}
