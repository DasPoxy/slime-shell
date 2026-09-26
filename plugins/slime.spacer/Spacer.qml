import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../slime.bar/ui"
import "../slime.bar/commandcenter"

// A gap in the Slime bar. Settings (shell.json, also reachable by
// right-clicking the gap):
//   size   width in px (default 16), same key as Omarchy's spacer
//   deco   "gap"   plain ooze, no bulb
//          "lump"  the ooze sags into a bulb here, with drips
//          "eye"   a spare eyeball floats in the gap, looking around (default,
//                  so a freshly added spacer is visible)
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

  function saveSetting(key, value) {
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    entry[key] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
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

  QtObject {
    id: look
    readonly property var bar: root.bar
    readonly property color ink: root.slime ? root.bar.slimeInk : Color.foreground
    readonly property color slime: root.slime ? root.bar.slimeColor : Color.accent
    readonly property string font: root.bar ? root.bar.fontFamily : Style.font.family
  }

  SlimePopupCard {
    id: menu
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.menuOpen
    contentWidth: Style.space(250)
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
          model: [["plain ooze", "gap"], ["sagging lump", "lump"], ["eyeball", "eye"]]
          CcButton {
            required property var modelData
            cc: look
            text: modelData[0]
            on: root.deco === modelData[1]
            onClicked: root.saveSetting("deco", modelData[1])
          }
        }
      }
    }
  }
}
