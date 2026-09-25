import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../slime.bar/ui"

// Slime Shell launcher button. Left click opens the Omarchy menu as before,
// middle click opens a terminal (the stock right-click action), and right
// click drips open a picker of themed icons. The choice is stored in this
// widget's shell.json entry as `icon`. Off the slime bar it shows the stock
// Omarchy glyph.
BarWidget {
  id: root
  moduleName: "omarchy.menu"

  readonly property bool slime: !!root.bar && root.bar.slimeSkin === true
  // [id, label, monster variant or -1 for the Omarchy glyph]
  readonly property var icons: [
    ["goober", "Goober", 0],
    ["cyclops", "Cyclops", 1],
    ["horned", "Horned", 2],
    ["drooler", "Drooler", 3],
    ["antenna", "Antenna", 4],
    ["omarchy", "Omarchy", -1]
  ]
  readonly property string iconId: setting("icon", "goober")
  readonly property int variant: {
    for (var i = 0; i < icons.length; i++) if (icons[i][0] === iconId) return icons[i][2]
    return 0
  }
  readonly property bool showMonster: slime && variant >= 0

  property bool pickerOpen: false
  IpcHandler {
    target: "slime-launcher"
    function icons(): void { root.pickerOpen = root.slime && !root.pickerOpen }
  }
  function close() { pickerOpen = false }

  function pickIcon(id) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.icon = id
    // Applied locally first so the icon changes on the click; the shell.json
    // write comes back through the bar as the same value.
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showMonster ? "" : ""
    fontFamily: "omarchy"
    hasVisualContent: true
    fixedWidth: root.showMonster ? 34 : -1
    horizontalMargin: 7.5
    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton && root.slime) root.pickerOpen = !root.pickerOpen
      else if (b === Qt.RightButton || b === Qt.MiddleButton) root.bar.run("xdg-terminal-exec")
      else root.bar.run("omarchy-shell shell toggle omarchy.menu '{\"menu\":\"root\"}'")
    }

    HoverHandler { id: hover }

    SlimeMonster {
      visible: root.showMonster
      anchors.centerIn: parent
      size: 26
      variant: Math.max(0, root.variant)
      mood: hover.hovered || root.pickerOpen ? "emote" : "idle"
      time: root.slime ? root.bar.animTime : 0
      body: root.slime ? root.bar.monsterBody : "transparent"
      ink: root.slime ? root.bar.slimeInk : "black"
      eye: root.slime ? root.bar.paperColor : "white"
      blush: root.slime ? root.bar.monsterBlush : "pink"
    }
  }

  SlimePopupCard {
    id: picker
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.pickerOpen
    contentWidth: Style.space(12) * 2 + root.icons.length * 62
    contentHeight: pickerColumn.implicitHeight + Style.space(12) * 2

    Column {
      id: pickerColumn
      anchors.fill: parent
      spacing: Style.space(8)

      Text {
        text: "LAUNCHER ICON"
        color: root.slime ? root.bar.slimeInk : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: 10
        font.bold: true
        opacity: 0.7
      }

      Row {
        spacing: 4
        Repeater {
          model: root.icons
          Rectangle {
            id: choice
            required property var modelData
            readonly property bool selected: root.iconId === modelData[0]
            width: 58
            height: 58
            radius: 12
            color: selected ? Qt.rgba(0, 0, 0, 0.18) : (choiceHover.hovered ? Qt.rgba(1, 1, 1, 0.3) : "transparent")
            border.color: selected && root.slime ? root.bar.slimeInk : "transparent"
            border.width: 2

            HoverHandler { id: choiceHover }

            SlimeMonster {
              visible: choice.modelData[2] >= 0
              anchors.horizontalCenter: parent.horizontalCenter
              y: 6
              size: 30
              variant: Math.max(0, choice.modelData[2])
              mood: choice.selected || choiceHover.hovered ? "emote" : "idle"
              time: root.slime ? root.bar.animTime : 0
              body: root.slime ? root.bar.monsterBody : "transparent"
              ink: root.slime ? root.bar.slimeInk : "black"
              eye: root.slime ? root.bar.paperColor : "white"
              blush: root.slime ? root.bar.monsterBlush : "pink"
            }
            Text {
              visible: choice.modelData[2] < 0
              anchors.horizontalCenter: parent.horizontalCenter
              y: 8
              text: ""
              font.family: "omarchy"
              font.pixelSize: 24
              color: root.slime ? root.bar.slimeInk : Color.foreground
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 4
              text: choice.modelData[1]
              color: root.slime ? root.bar.slimeInk : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: 9
              font.bold: true
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.pickIcon(choice.modelData[0])
            }
          }
        }
      }
    }
  }
}
