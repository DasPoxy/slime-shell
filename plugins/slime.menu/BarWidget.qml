import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../slime.bar/ui"

// Slime Shell launcher button. Left click drips open the Slime app launcher
// (AppDrawer.qml; it links to the Omarchy menu), middle click opens a
// terminal, and right click drips open a picker of themed icons. The choice is stored in this
// widget's shell.json entry as `icon`. Off the slime bar it shows the stock
// Omarchy glyph.
BarWidget {
  id: root
  moduleName: "omarchy.menu"

  readonly property bool slime: !!root.bar && root.bar.slimeSkin === true
  // [id, label, type, value]: type "monster" (SlimeMonster variant),
  // "gear" (SlimeGear kind) or "omarchy" (the stock glyph)
  readonly property var icons: [
    ["goober", "Goober", "monster", 0],
    ["cyclops", "Cyclops", "monster", 1],
    ["horned", "Horned", "monster", 2],
    ["drooler", "Drooler", "monster", 3],
    ["antenna", "Antenna", "monster", 4],
    ["robot", "Robot", "monster", 5],
    ["potion", "Potion", "gear", "potion"],
    ["skull", "Skull", "gear", "skull"],
    ["chest", "Chest", "gear", "chest"],
    ["orb", "Orb", "gear", "orb"],
    ["backpack", "Pack", "gear", "backpack"],
    ["candle", "Candle", "gear", "candle"],
    ["omarchy", "Omarchy", "omarchy", -1]
  ]
  readonly property string iconId: setting("icon", "goober")
  readonly property var current: {
    for (var i = 0; i < icons.length; i++) if (icons[i][0] === iconId) return icons[i]
    return icons[0]
  }
  readonly property bool showMonster: slime && current[2] === "monster"
  readonly property bool showGear: slime && current[2] === "gear"

  property bool pickerOpen: false
  property bool appsOpen: false
  // summoned by keybind: centred on screen instead of dripping from the bar
  property bool appsFloating: false
  onAppsOpenChanged: if (appsOpen) pickerOpen = false
  onPickerOpenChanged: if (pickerOpen) appsOpen = false
  IpcHandler {
    target: "slime-launcher"
    function icons(): void { root.pickerOpen = root.slime && !root.pickerOpen }
    // the app launcher (bind to e.g. Super+Space)
    function apps(): void {
      if (root.appsOpen) { root.appsOpen = false; return }
      root.appsFloating = true
      root.appsOpen = root.slime
    }
  }
  function close() { pickerOpen = false; appsOpen = false }

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
    text: root.showMonster || root.showGear ? "" : ""
    fontFamily: "omarchy"
    hasVisualContent: true
    fixedWidth: root.showMonster || root.showGear ? 34 : -1
    horizontalMargin: 7.5
    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton && root.slime) root.pickerOpen = !root.pickerOpen
      else if (b === Qt.RightButton || b === Qt.MiddleButton) root.bar.run("xdg-terminal-exec")
      else if (root.slime) { root.appsFloating = false; root.appsOpen = !root.appsOpen }
      else root.bar.run("omarchy-shell shell toggle omarchy.menu '{\"menu\":\"root\"}'")
    }

    HoverHandler { id: hover }

    SlimeGear {
      visible: root.showGear
      anchors.centerIn: parent
      size: 26
      bar: root.bar
      kind: root.showGear ? root.current[3] : "chest"
      lit: hover.hovered || root.pickerOpen
      net: "ethernet"
      rotation: hover.hovered && root.bar ? Math.sin(root.bar.animTime * 8) * 6 : 0
    }

    SlimeMonster {
      visible: root.showMonster
      anchors.centerIn: parent
      size: 26
      variant: root.showMonster ? root.current[3] : 0
      mood: hover.hovered || root.pickerOpen || root.appsOpen ? "emote" : "idle"
      time: root.slime ? root.bar.animTime : 0
      body: root.slime ? root.bar.monsterBodyFor(-1) : "transparent"
      body2: root.slime ? root.bar.monsterBody2For(-1) : "transparent"
      ink: root.slime ? root.bar.slimeInk : "black"
      eye: root.slime ? root.bar.paperColor : "white"
      blush: root.slime ? root.bar.monsterBlush : "pink"
      material: root.slime ? root.bar.material : "slime"
    }
  }

  AppDrawer {
    anchorItem: button
    owner: root
    bar: root.bar
    widget: root
    floating: root.appsFloating
    open: root.appsOpen
  }

  SlimePopupCard {
    id: picker
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.pickerOpen
    contentWidth: Style.space(12) * 2 + 7 * 62
    contentHeight: picker.fittedContentHeight(pickerColumn.implicitHeight)

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

      Flow {
        width: parent.width
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
              visible: choice.modelData[2] === "monster"
              anchors.horizontalCenter: parent.horizontalCenter
              y: 6
              size: 30
              variant: choice.modelData[2] === "monster" ? choice.modelData[3] : 0
              mood: choice.selected || choiceHover.hovered ? "emote" : "idle"
              time: root.slime ? root.bar.animTime : 0
              body: root.slime ? root.bar.monsterBodyFor(-1) : "transparent"
              body2: root.slime ? root.bar.monsterBody2For(-1) : "transparent"
              ink: root.slime ? root.bar.slimeInk : "black"
              eye: root.slime ? root.bar.paperColor : "white"
              blush: root.slime ? root.bar.monsterBlush : "pink"
              material: root.slime ? root.bar.material : "slime"
            }
            SlimeGear {
              visible: choice.modelData[2] === "gear"
              anchors.horizontalCenter: parent.horizontalCenter
              y: 6
              size: 30
              bar: root.bar
              kind: choice.modelData[2] === "gear" ? choice.modelData[3] : "chest"
              lit: choice.selected || choiceHover.hovered
              net: "ethernet"
            }
            Text {
              visible: choice.modelData[2] === "omarchy"
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
