import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../slime.bar/ui"
import "../slime.bar/commandcenter"
import "../slime.bar/ui/WidgetSettings.js" as WidgetSettings

// A gap in the Slime bar. Settings (shell.json, also reachable by
// right-clicking the gap):
//   size   width in px (default 16), same key as Omarchy's spacer
//   deco   "gap"   plain ooze, no bulb
//          "lump"  the ooze sags into a bulb here, with drips
//          "eye"   a spare eyeball floats in the gap, looking around (default,
//                  so a freshly added spacer is visible)
//          any floating bit: "sword", "axe", "hat", "frog", "mug" (tankard),
//          "potion", "skull", "bone", "tooth", "bubble", "candle", "orb"
// Each spacer keeps its own choice (it lives in that spacer's entry).
// Hovering shows a dashed outline and the size, so plain gaps can be found.
// Scroll over the gap to resize it.
BarWidget {
  id: root
  moduleName: "slime.spacer"

  readonly property bool slime: !!bar && bar.slimeSkin === true
  readonly property int span: Math.max(4, Number(setting("size", 16)))
  readonly property string deco: setting("deco", "eye")
  // The bar skips bulbs for widgets that set this, so a plain gap is just ooze.
  readonly property bool slimeNoBulb: deco !== "lump"
  property bool menuOpen: false

  implicitWidth: vertical ? barSize : span
  implicitHeight: vertical ? span : barSize

  // Where this spacer sits in shell.json: { region, index }. Spacers can be on
  // the bar several times, so settings are written to this entry only (the
  // shell's usual updateEntryInline would rewrite every spacer at once).
  function place() {
    if (!bar || !bar.moduleSlots) return null
    var slots = bar.moduleSlots, mine = null
    for (var i = 0; i < slots.length; i++) if (slots[i] && slots[i].activeItem === root) mine = slots[i]
    if (!mine) return null
    // Slots hold copies of their layout entries, so find this spacer by
    // position: it's the k-th spacer (along the bar, on this monitor) in its
    // section, which is the k-th spacer entry in that section's layout.
    var win = bar.slotWindow(mine)
    var same = slots.filter(function(sl) {
      return sl && sl.region === mine.region && sl.moduleName === root.moduleName && bar.sameWindow(bar.slotWindow(sl), win)
    })
    function along(sl) { try { var p = sl.mapToItem(null, 0, 0); return bar.vertical ? p.y : p.x } catch (e) { return 0 } }
    same.sort(function(a, b) { return along(a) - along(b) })
    var k = same.indexOf(mine)
    var entries = bar.layoutEntries(mine.region)
    for (var j = 0, seen = 0; j < entries.length; j++) {
      if (!entries[j] || entries[j].id !== root.moduleName) continue
      if (seen === k) return { region: mine.region, index: j }
      seen++
    }
    return null
  }


  // (its own place: a spacer can be on the bar more than once)
  function saveSetting(key, value) { WidgetSettings.saveAt(root, WidgetSettings.one(key, value), place()) }

  // A new spacer right after this one, with the same size and contents.
  function addAnother() {
    var at = place()
    if (!at || !bar.shell || typeof bar.shell.mutateShellConfig !== "function") return
    var copy = { id: root.moduleName, size: root.span, deco: root.deco }
    bar.shell.mutateShellConfig(function(config) {
      var list = config.bar && config.bar.layout ? config.bar.layout[at.region] : null
      if (list) list.splice(at.index + 1, 0, copy)
    })
    menuOpen = false
  }
  function removeSelf() {
    var at = place()
    if (!at || !bar.shell || typeof bar.shell.mutateShellConfig !== "function") return
    menuOpen = false
    bar.shell.mutateShellConfig(function(config) {
      var list = config.bar && config.bar.layout ? config.bar.layout[at.region] : null
      if (list && list[at.index] && list[at.index].id === root.moduleName) list.splice(at.index, 1)
    })
  }
  function close() { menuOpen = false }

  // eyeball decoration
  Rectangle {
    visible: root.slime && root.deco === "eye"
    anchors.centerIn: parent
    readonly property real t: root.slime ? root.bar.animTime : 0
    anchors.verticalCenterOffset: Math.sin(t * 1.2 + root.x * 0.1) * 2
    width: Math.min(14, root.span - 2)
    height: width
    radius: width / 2
    color: root.slime ? root.bar.paperColor : "white"
    border.color: root.slime ? root.bar.slimeInk : "black"
    border.width: 1.2
    Rectangle {
      width: parent.width * 0.45; height: width; radius: width / 2
      x: parent.width * 0.28 + Math.sin(parent.t * 0.7 + root.x) * parent.width * 0.16
      y: parent.height * 0.28
      color: root.slime ? root.bar.slimeInk : "black"
    }
  }

  // a floating bit, bobbing in the gap
  readonly property var own: ["bone", "tooth", "bubble"]
  SlimeDebris {
    visible: root.slime && root.deco !== "eye" && root.deco !== "gap" && root.deco !== "lump"
    anchors.fill: parent
    bar: root.bar
    bitOpacity: 1
    growChance: 0          // the bit you picked, at its size
    bits: [{ kind: root.deco, x: 0.5, y: 0.5,
             s: Math.min(root.own.indexOf(root.deco) === -1 ? 22 : 14, root.span - 2, root.barSize - 8), sp: 0.5 }]
  }

  // hover hint: where the gap is and how big
  Rectangle {
    anchors.fill: parent
    anchors.margins: 3
    visible: root.slime && (spacerHover.hovered || root.menuOpen)
    radius: 6
    color: "transparent"
    border.color: root.bar ? root.bar.slimeInk : "black"
    border.width: 1.5
    opacity: 0.6
    Text {
      anchors.centerIn: parent
      visible: root.span >= 22
      text: root.span
      color: root.bar ? root.bar.slimeInk : "black"
      font.pixelSize: 9
      font.bold: true
    }
  }
  HoverHandler { id: spacerHover }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.RightButton
    onClicked: if (root.slime) root.menuOpen = !root.menuOpen
    onWheel: wheel => root.saveSetting("size", Math.max(4, Math.min(160, root.span + (wheel.angleDelta.y > 0 ? 4 : -4))))
  }

  SlimeLook { id: look; bar: root.bar; skin: root.slime }

  SlimePopupCard {
    id: menu
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.menuOpen
    contentWidth: Style.space(300)
    contentHeight: menu.fittedContentHeight(menuColumn.implicitHeight)

    Column {
      id: menuColumn
      anchors.fill: parent
      spacing: 8

      CcHeading { cc: look; text: "SPACER  ·  " + root.span + "px  (scroll to resize)" }
      Flow {
        width: parent.width
        spacing: 6
        Repeater {
          model: [["8", 8], ["16", 16], ["32", 32], ["64", 64], ["−", -8], ["+", 8]]
          CcButton {
            required property var modelData
            required property int index
            cc: look
            text: modelData[0]
            on: index < 4 && root.span === modelData[1]
            onClicked: root.saveSetting("size", index < 4 ? modelData[1] : Math.max(4, Math.min(160, root.span + modelData[1])))
          }
        }
      }
      CcHeading { cc: look; text: "IN THE GAP" }
      Flow {
        width: parent.width
        spacing: 6
        Repeater {
          model: [["plain ooze", "gap"], ["sagging lump", "lump"], ["eyeball", "eye"],
            ["sword", "sword"], ["axe", "axe"], ["wizard hat", "hat"], ["frog", "frog"], ["tankard", "mug"],
            ["potion", "potion"], ["skull", "skull"], ["bone", "bone"], ["tooth", "tooth"], ["bubble", "bubble"],
            ["candle", "candle"], ["orb", "orb"]]
          CcButton {
            required property var modelData
            cc: look
            text: modelData[0]
            on: root.deco === modelData[1]
            onClicked: root.saveSetting("deco", modelData[1])
          }
        }
      }
      Flow {
        width: parent.width
        spacing: 6
        CcButton { cc: look; icon: "\uf067"; text: "add another spacer"; onClicked: root.addAnother() }
        CcButton { cc: look; icon: "\uf1f8"; text: "remove"; onClicked: root.removeSelf() }
      }
    }
  }
}
