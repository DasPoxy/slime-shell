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
    SlimeIndicatorIcon {
      kind: "candle"
      bar: root.bar
      size: parent ? parent.width : 22
      lit: root.effectiveActive
      // plain objects, or slimes with the objects inside (right-click the indicators)
      iconSet: root.indicatorHost && root.indicatorHost.iconSet ? root.indicatorHost.iconSet : "gear"
      hue: 0
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

  onPressed: function(b) {
    // right-click: the indicators' drip menu (plain objects or slimes)
    if (b === Qt.RightButton && root.indicatorHost && root.indicatorHost.openIconMenu) { root.indicatorHost.openIconMenu(); return }
    root.toggle()
  }
}
