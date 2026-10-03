import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../slime.bar/ui"
import "../slime.bar/commandcenter"

// The treasure chest: every installed plugin that provides a bar widget,
// grouped Slime / Omarchy / Community. Click an entry to add it to the bar or
// take it off (through `omarchy plugin enable/disable`, the same path the
// Omarchy menu uses). Right-click an entry that's on the bar to send its
// widget a right-click, opening that widget's own menu.
BarWidget {
  id: root
  moduleName: "slime.plugins"

  readonly property bool slime: !!bar && bar.slimeSkin === true
  property var plugins: []
  property string busyId: ""
  property string error: ""

  // ---- bar popout contract (shell.summon/hide/toggle, one-at-a-time) -------
  readonly property bool opened: panel.open
  property bool popoutSwitchClosing: false
  function open() { panel.open = true }
  function close() { panel.open = false }
  function closeForPopoutSwitch() { popoutSwitchClosing = true; close(); Qt.callLater(function() { popoutSwitchClosing = false }) }
  function toggle() { panel.open = !panel.open }

  IpcHandler {
    target: "slime-plugins"
    function toggle(): void { root.toggle() }
  }

  // ---- data ------------------------------------------------------------------
  Process {
    id: lister
    command: ["omarchy-plugin-list", "--json"]
    stdout: StdioCollector {
      onStreamFinished: {
        var all
        try { all = JSON.parse(text) } catch (e) { return }
        var out = []
        for (var i = 0; i < all.length; i++) {
          var p = all[i]
          if (!p.kinds || p.kinds.indexOf("bar-widget") === -1 || p.id === root.moduleName) continue
          out.push({
            id: p.id,
            name: String(p.name || p.id),
            on: p.enabled === true,
            group: p.id.indexOf("slime.") === 0 ? "Slime" : (p.firstParty ? "Omarchy" : "Community"),
            clone: String(p.clonedFrom || "")
          })
        }
        out.sort(function(a, b) {
          var order = { Slime: 0, Omarchy: 1, Community: 2 }
          return order[a.group] - order[b.group] || (b.on - a.on) || a.name.localeCompare(b.name)
        })
        root.plugins = out
      }
    }
  }
  function refresh() { lister.running = true }

  Process {
    id: toggler
    stderr: StdioCollector { onStreamFinished: root.error = text.trim().replace(/^omarchy-plugin-\w+: /, "") }
    onExited: { root.busyId = ""; root.refresh() }
  }
  function flip(plugin) {
    if (busyId !== "") return
    error = ""
    busyId = plugin.id
    toggler.command = plugin.on ? ["omarchy-plugin-disable", plugin.id] : ["omarchy-plugin-enable", plugin.id]
    toggler.running = true
  }

  // Send a right-click to the widget where it sits on the bar.
  function rightClickOnBar(plugin) {
    if (!plugin.on || !bar) return
    var slots = bar.moduleSlots
    for (var i = 0; i < slots.length; i++) {
      var slot = slots[i]
      if (!slot || slot.moduleName !== plugin.id || !slot.visible || slot.width <= 0) continue
      root.close()
      Qt.callLater(function() { bar.pressModuleClickTarget(slot, Qt.RightButton, slot.width / 2, slot.height / 2) })
      return
    }
    error = plugin.name + " isn't showing on the bar right now"
  }

  // ---- bar button ----------------------------------------------------------------
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    iconComponent: root.slime ? chestIcon : null
    opticalSize: root.slime ? 26 : Style.bar.iconCanvas
    slotSize: root.slime ? 32 : Style.bar.iconSlot
    tooltipText: panel.open ? "" : "Widgets"
    onPressed: function(b) { root.toggle() }
  }

  Component {
    id: chestIcon
    SlimeGear {
      kind: "chest"
      bar: root.bar
      size: parent ? parent.width : 24
      lit: panel.open
    }
  }

  // the command centre's look-and-feel helpers want a `cc`
  SlimeLook { id: look; bar: root.bar; skin: root.slime }

  // ---- the chest panel -------------------------------------------------------------
  SlimeKeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    contentWidth: fittedContentWidth(Style.space(420))
    contentHeight: fittedContentHeight(column.implicitHeight, Style.space(560))
    onOpenChanged: if (open) root.refresh()

    Flickable {
      anchors.fill: parent
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: column
        width: parent.width
        spacing: 8

        Row {
          spacing: 10
          SlimeGear { kind: "chest"; bar: root.bar; size: 30; lit: true }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            Text {
              text: "Treasure chest"
              color: look.ink
              font.family: look.displayFont
              font.pixelSize: 17
              font.weight: root.bar ? root.bar.displayWeight : Font.Black
            }
            Text {
              text: root.error !== "" ? root.error : "click to add or remove · right-click a widget that's on the bar for its menu"
              width: column.width - 40
              wrapMode: Text.Wrap
              color: look.ink
              font.family: look.font
              font.pixelSize: 10
              opacity: 0.75
            }
          }
        }

        // one collapsible section per group; open/closed is remembered
        // (skin.json) under "chest:<group>", apart from the Settings sections
        Repeater {
          model: [
            { group: "Slime", kind: "chest", open: true },
            { group: "Omarchy", kind: "anvil", open: false },
            { group: "Community", kind: "scroll", open: false }
          ]
          CcSection {
            id: section
            required property var modelData
            readonly property var items: root.plugins.filter(function(p) { return p.group === section.modelData.group })
            readonly property int onCount: items.filter(function(p) { return p.on }).length
            visible: items.length > 0
            width: column.width
            cc: look
            title: modelData.group
            key: "chest:" + modelData.group
            label: modelData.group + "  ·  " + onCount + "/" + items.length + " on the bar"
            kind: modelData.kind
            defaultOpen: modelData.open

            Repeater {
              model: section.items
              Rectangle {
                id: entry
                required property var modelData
                width: section.width - 16
                height: 34
                radius: 12
                color: rowHover.hovered ? Qt.rgba(1, 1, 1, 0.7) : look.wash
                opacity: root.busyId === entry.modelData.id ? 0.5 : 1

                HoverHandler { id: rowHover }

                // on/off: a gold coin in the chest, or an empty slot
                Rectangle {
                  id: coin
                  x: 10
                  anchors.verticalCenter: parent.verticalCenter
                  width: 16; height: 16; radius: 8
                  color: entry.modelData.on ? (root.bar && root.bar.slimePalette.yellow ? root.bar.slimePalette.yellow : "#d9b800") : "transparent"
                  border.color: look.ink
                  border.width: 2
                  Text {
                    anchors.centerIn: parent
                    visible: entry.modelData.on
                    text: "\uf00c"
                    color: look.ink
                    font.family: look.font
                    font.pixelSize: 8
                  }
                }
                Text {
                  x: coin.x + coin.width + 10
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - x - stateLabel.implicitWidth - 20
                  text: entry.modelData.name
                  elide: Text.ElideRight
                  color: look.ink
                  font.family: look.font
                  font.pixelSize: 12
                  font.bold: entry.modelData.on
                }
                Text {
                  id: stateLabel
                  anchors.right: parent.right
                  anchors.rightMargin: 12
                  anchors.verticalCenter: parent.verticalCenter
                  text: entry.modelData.on ? "on the bar" : ""
                  color: look.ink
                  font.family: look.font
                  font.pixelSize: 10
                  opacity: 0.6
                }
                MouseArea {
                  anchors.fill: parent
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  cursorShape: Qt.PointingHandCursor
                  onClicked: mouse => {
                    if (mouse.button === Qt.RightButton) root.rightClickOnBar(entry.modelData)
                    else root.flip(entry.modelData)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
