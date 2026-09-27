import QtQuick
import "../ui"

// A command-centre button styled like the bar widgets: a SlimeGear item
// floating (bobbing and swaying) in the ooze, with an optional label beside
// or below it. `active` makes it bigger and inks the label; `lit` and the
// other state properties pass straight through to the gear.
Item {
  id: button

  required property var cc
  property string kind: "cottage"
  property string label: ""
  property string labelSide: "right"   // right, below, none
  property real size: 26
  property bool active: false
  property real phase: 0

  // SlimeGear state passthrough
  property bool lit: true
  property bool flip: false
  property string state3: "on"
  property string net: "wifi"
  property real level: 1
  property bool muted: false

  signal clicked
  readonly property bool ccFocusable: true
  function ccActivate() { clicked() }

  readonly property real t: cc && cc.bar ? cc.bar.animTime : 0
  readonly property real grow: active ? 1.12 : (hover.hovered ? 1.06 : 1)

  implicitWidth: labelSide === "right" ? size + (label !== "" ? 8 + labelText.implicitWidth : 0)
    : Math.max(size, labelSide === "below" ? labelText.implicitWidth : 0)
  implicitHeight: labelSide === "below" ? size + 4 + labelText.implicitHeight : size

  HoverHandler { id: hover }

  Item {
    id: iconBox
    width: button.size
    height: button.size
    x: button.labelSide === "below" ? (button.width - width) / 2 : 0
    transform: Translate { y: Math.sin(button.t * 1.3 + button.phase) * 1.4 }
    rotation: Math.sin(button.t * 0.9 + button.phase * 1.7) * 3
    scale: button.grow
    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

    SlimeGear {
      anchors.fill: parent
      size: button.size
      bar: button.cc ? button.cc.bar : null
      kind: button.kind
      lit: button.lit
      flip: button.flip
      state3: button.state3
      net: button.net
      level: button.level
      muted: button.muted
    }
  }

  Text {
    id: labelText
    visible: button.label !== "" && button.labelSide !== "none"
    x: button.labelSide === "right" ? button.size + 8 : (button.width - implicitWidth) / 2
    y: button.labelSide === "right" ? (button.size - implicitHeight) / 2 : button.size + 4
    text: button.label
    color: button.cc.ink
    opacity: button.active || hover.hovered ? 1 : 0.72
    font.family: button.cc.font
    font.pixelSize: button.labelSide === "below" ? 10 : 13
    font.weight: button.active ? Font.Black : Font.Bold
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: button.clicked()
  }
}
