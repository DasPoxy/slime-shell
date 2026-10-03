import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQml
import QtQuick.Shapes
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../BarModel.js" as BarModel
import "../SlimeHub.js" as SlimeHub
import "../commandcenter"
import "../ui"
import "../dock"

// The slime scene (one SDF shader for bar, drips, bulbs, command centre):
// the bar window draws the strip, the skin window everything past it. Both
// share every uniform, so the goo runs seamlessly across the seam.
ShaderEffect {
  id: slimeSceneRoot
  // the bar (Bar.qml), which this used to sit inside
  property var root: null
  required property var win
  fragmentShader: Qt.resolvedUrl("../shaders/slime.frag.qsb")
  // every shader uniform set explicitly: unset ones are not guaranteed to be 0
  property vector4d cullRect: Qt.vector4d(0, 0, 0, 0)
  property real clipTop: -100000
  property real poolDepth: 0
  property vector2d origin: Qt.vector2d(0, 0)
  property real blobMode: 0
  property real orient: root.orientId
  property vector2d screenSize: win.screen ? Qt.vector2d(win.screen.width, win.screen.height) : Qt.vector2d(0, 0)

  property real time: root.animTime
  property real barHeight: root.barSize
  property real openProgress: win.ccProgress
  property real dripAmount: root.dripLevel
  property real shadingStyle: root.shadingStyle
  property vector2d resolution: Qt.vector2d(width, height)
  property vector4d panelRect: Qt.vector4d(win.ccPanelX, 0, win.ccAlong, win.ccAway)
  property color slimeColor: root.slimeColor
  property color slimeColor2: root.slimeColor2
  property color paperColor: root.paperColor
  property real barShape: root.barShapeId
  property real material: root.materialId
  property vector4d dripStyle: root.dripStyleVec
  // drip-zone depth: falling goo shrinks away before it, and past it only
  // the command centre's column is drawn (the window is taller while it's open)
  property vector4d dripExtra: Qt.vector4d(root.dripExtraVec.x, root.dripExtraVec.y,
    root.barSize + win.dripRoom, root.barSize + win.dripRoom)
  property vector4d eggDrip: root.eggDrip
  property vector4d group0: win.groupRects[0] || win.noBulb
  property vector4d group1: win.groupRects[1] || win.noBulb
  property vector4d group2: win.groupRects[2] || win.noBulb
  property vector4d bulb0: win.bulbRects[0] || win.noBulb
  property vector4d bulb1: win.bulbRects[1] || win.noBulb
  property vector4d bulb2: win.bulbRects[2] || win.noBulb
  property vector4d bulb3: win.bulbRects[3] || win.noBulb
  property vector4d bulb4: win.bulbRects[4] || win.noBulb
  property vector4d bulb5: win.bulbRects[5] || win.noBulb
  property vector4d bulb6: win.bulbRects[6] || win.noBulb
  property vector4d bulb7: win.bulbRects[7] || win.noBulb
  property vector4d bulb8: win.bulbRects[8] || win.noBulb
  property vector4d bulb9: win.bulbRects[9] || win.noBulb
  property vector4d bulb10: win.bulbRects[10] || win.noBulb
  property vector4d bulb11: win.bulbRects[11] || win.noBulb
  property vector4d bulb12: win.bulbRects[12] || win.noBulb
  property vector4d bulb13: win.bulbRects[13] || win.noBulb
  property vector4d bulb14: win.bulbRects[14] || win.noBulb
  property vector4d bulb15: win.bulbRects[15] || win.noBulb
  property vector4d bulb16: win.bulbRects[16] || win.noBulb
  property vector4d bulb17: win.bulbRects[17] || win.noBulb
  property vector4d bulb18: win.bulbRects[18] || win.noBulb
  property vector4d bulb19: win.bulbRects[19] || win.noBulb
  property vector4d bulb20: win.bulbRects[20] || win.noBulb
  property vector4d bulb21: win.bulbRects[21] || win.noBulb
  property vector4d bulb22: win.bulbRects[22] || win.noBulb
  property vector4d bulb23: win.bulbRects[23] || win.noBulb
  property vector4d cava0: root.cava0
  property vector4d cava1: root.cava1
  property vector4d cava2: root.cava2
  property vector4d cava3: root.cava3
  property vector4d cavaOpts: root.cavaOpts
  property vector4d dockBracket: barShape < 3.5 ? root.dockBracketVec : Qt.vector4d(0, 0, 0, 0)
  property vector4d dropShape: Qt.vector4d(0, 0, 0, 0)
}
