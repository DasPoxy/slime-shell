import QtQuick
import qs.Ui
import qs.Commons
import "../../slime.bar/ui"

BarIndicator {
  id: root

  // Slime Shell: on the slime bar this indicator is a mug floating in the ooze.
  readonly property bool slime: !!bar && bar.slimeSkin === true
  iconComponent: slime ? slimeIcon : null
  // (the slime icon set is drawn bigger: a whole slime, not just an object)
  readonly property bool slimeSet: !!indicatorHost && indicatorHost.iconSet === "slimes"
  opticalSize: slime ? (slimeSet ? 30 : 22) : Style.bar.iconCanvas
  fixedWidth: vertical ? -1 : (slime ? (slimeSet ? 34 : 28) : Style.bar.statusSlot)

  Component {
    id: slimeIcon
    SlimeIndicatorIcon {
      kind: "mug"
      bar: root.bar
      size: parent ? parent.width : 22
      lit: root.effectiveActive
      // plain objects, or slimes with the objects inside (right-click the indicators)
      iconSet: root.indicatorHost && root.indicatorHost.iconSet ? root.indicatorHost.iconSet : "gear"
      hue: 2
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

  onPressed: function(b) {
    // right-click: the indicators' drip menu (plain objects or slimes)
    if (b === Qt.RightButton && root.indicatorHost && root.indicatorHost.openIconMenu) { root.indicatorHost.openIconMenu(); return }
    root.toggle()
  }
}
