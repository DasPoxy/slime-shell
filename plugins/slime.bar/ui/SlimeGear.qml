import QtQuick
import QtQuick.Shapes

// Adventuring gear floating in the ooze, standing in for the stock status
// glyphs while keeping each widget readable. Drawn as vector paths on a 24×24
// grid and scaled to `size`; coloured from the bar's theme palette.
//
//   kind "backpack"   tray chevron (inventory)      state: open
//        "runestone"  bluetooth (the Bluetooth logo is a runic bind-rune)
//                                                    state: off / on / connected
//        "horn"       audio output                   level 0..1, muted
//        "mirror"     display                        multi (several screens)
//        "orb"        network                        net "wifi"/"ethernet"/"none", level 0..1
Item {
  id: root

  property string kind: "backpack"
  property var bar: null
  property real size: 24
  property real time: bar ? bar.animTime : 0

  property bool open: false
  property string state3: "on"         // runestone: off / on / connected
  property real level: 1               // horn volume, orb signal
  property bool muted: false
  property bool multi: false
  property string net: "wifi"

  // ---- palette ----
  readonly property var pal: bar && bar.palette ? bar.palette : ({})
  readonly property color ink: bar ? bar.slimeInk : "#101315"
  readonly property color paper: bar ? bar.paperColor : "#f3e9d2"
  readonly property color gold: pal.yellow || "#d9b800"
  readonly property color leather: pal.brown || Qt.darker(gold, 1.9)
  readonly property color leatherLight: Qt.lighter(leather, 1.35)
  readonly property color crystal: pal.bright_cyan || pal.cyan || "#10ffd9"
  readonly property color glass: Qt.tint(paper, Qt.rgba(crystal.r, crystal.g, crystal.b, 0.35))
  readonly property color stone: Qt.tint(paper, Qt.rgba(ink.r, ink.g, ink.b, 0.38))
  readonly property color glow: pal.bright_cyan || pal.cyan || "#10ffd9"
  readonly property real pulse: 0.75 + 0.25 * Math.sin(time * 3)

  implicitWidth: size
  implicitHeight: size

  component GearPath: Shape {
    id: p
    property string d: ""
    property color fill: "transparent"
    property color stroke: root.ink
    property real line: 1.3
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      fillColor: p.fill
      strokeColor: p.stroke
      strokeWidth: p.line
      joinStyle: ShapePath.RoundJoin
      capStyle: ShapePath.RoundCap
      PathSvg { path: p.d }
    }
  }

  Item {
    width: 24
    height: 24
    transform: Scale { xScale: root.size / 24; yScale: root.size / 24 }

    // ================================================================ backpack
    Item {
      anchors.fill: parent
      visible: root.kind === "backpack"

      GearPath { d: "M9 6.5 Q9 2.6 12 2.6 Q15 2.6 15 6.5"; line: 1.6 }                  // carry loop
      GearPath { d: "M5 10 Q5 6.5 8.5 6.5 L15.5 6.5 Q19 6.5 19 10 L19 19.5 Q19 21.5 17 21.5 L7 21.5 Q5 21.5 5 19.5 Z"; fill: root.leather }
      GearPath { d: "M8 15 L16 15 L16 19 Q16 20 15 20 L9 20 Q8 20 8 19 Z"; fill: root.leatherLight; line: 1.1 }   // pocket
      // flap: closed hangs down over the front; open flips up above the bag
      GearPath {
        d: root.open ? "M5.6 7 Q5 1.2 12 1 Q19 1.2 18.4 7 Z"
                     : "M5.2 9.5 Q5.2 6.8 8.5 6.8 L15.5 6.8 Q18.8 6.8 18.8 9.5 L18.8 11 Q12 14.5 5.2 11 Z"
        fill: root.leatherLight
      }
      Rectangle {   // buckle
        x: 10.6; y: root.open ? 5 : 10.7; width: 2.8; height: 2.4; radius: 0.6
        color: root.gold; border.color: root.ink; border.width: 0.8
      }
      GearPath { visible: root.open; d: "M9.5 7.5 L10.5 4.8 L12 7.2 L13.4 4.6 L14.5 7.5"; stroke: root.gold; line: 1.1 }  // loot peeking out
    }

    // =============================================================== runestone
    Item {
      anchors.fill: parent
      visible: root.kind === "runestone"

      GearPath { d: "M7.5 3 L16.5 2.5 L19.5 8 L18.5 21 L5.5 21.5 L4.5 9 Z"; fill: root.stone }
      GearPath { d: "M6.2 20 L8 17.5 M17.2 19.8 L16 17.6 M16 4 L17.4 7"; line: 0.8 }     // chips & cracks
      // the Bluetooth bind-rune, carved; glows when on
      GearPath {
        d: "M8.6 8.6 L15.2 14.6 L12 17.6 L12 5.6 L15.2 8.6 L8.6 14.6"
        stroke: root.state3 === "off" ? root.ink : root.glow
        line: root.state3 === "off" ? 1.5 : 2
        opacity: root.state3 === "off" ? 0.55 : root.pulse
      }
      GearPath {
        visible: root.state3 !== "off"
        d: "M8.6 8.6 L15.2 14.6 L12 17.6 L12 5.6 L15.2 8.6 L8.6 14.6"
        line: 0.7
      }
      Repeater {    // connected: sparks either side of the rune
        model: root.state3 === "connected" ? [[6.2, 11.4], [17.6, 11.4]] : []
        Rectangle {
          required property var modelData
          x: modelData[0] - 1; y: modelData[1] - 1; width: 2; height: 2; radius: 1
          color: root.glow; border.color: root.ink; border.width: 0.5
          opacity: root.pulse
        }
      }
    }

    // ==================================================================== horn
    Item {
      anchors.fill: parent
      visible: root.kind === "horn"

      GearPath { d: "M1.8 15.6 Q8 15.8 13.6 6.8 L16.4 19.6 Q8 19.2 1.8 17.8 Z"; fill: root.paper }   // ivory horn
      GearPath { d: "M6 15.4 L6.6 18.6 M9.4 14.2 L10.4 19"; stroke: root.gold; line: 1.6 }            // gold bands
      GearPath { d: "M6 15.4 L6.6 18.6 M9.4 14.2 L10.4 19"; line: 0.5 }
      GearPath { d: "M1.4 15.4 L1.4 18 L2.6 18 L2.6 15.4 Z"; fill: root.gold; line: 0.9 }              // mouthpiece
      // bell mouth
      GearPath { d: "M13.6 6.8 Q17.6 6.6 16.4 19.6 Q13.2 17 13.6 6.8 Z"; fill: root.muted ? root.leather : Qt.darker(root.paper, 1.35) }
      // sound waves by volume, or a cork when muted
      Repeater {
        model: root.muted ? 0 : (root.level >= 0.67 ? 3 : root.level >= 0.34 ? 2 : root.level > 0 ? 1 : 0)
        GearPath {
          required property int index
          d: {
            var r = 3 + index * 2.4
            return "M" + (16.4 + r * 0.45) + " " + (13.2 - r) + " Q" + (16.4 + r * 1.15) + " 13.2 " + (16.4 + r * 0.45) + " " + (13.2 + r)
          }
          line: 1.4
          opacity: 0.55 + 0.45 * Math.sin(root.time * 5 - index)
        }
      }
      GearPath { visible: root.muted; d: "M18.4 9.6 L22.4 16.6 M22.4 9.6 L18.4 16.6"; line: 1.6 }
    }

    // ================================================================== mirror
    Item {
      anchors.fill: parent
      visible: root.kind === "mirror"

      GearPath { visible: root.multi; d: "M7 2.5 L22 2.5 L22 13 L19 13 L19 5.5 L7 5.5 Z"; fill: root.gold; line: 1 }   // second mirror behind
      GearPath { d: "M9.5 17 L14.5 17 L16 21.5 L8 21.5 Z"; fill: root.gold }                          // pedestal
      GearPath { d: "M2.5 5.5 Q2.5 4 4 4 L20 4 Q21.5 4 21.5 5.5 L21.5 16 Q21.5 17.5 20 17.5 L4 17.5 Q2.5 17.5 2.5 16 Z"; fill: root.gold }  // frame
      GearPath { d: "M4.6 6.2 L19.4 6.2 L19.4 15.3 L4.6 15.3 Z"; fill: root.glass; line: 0.9 }         // glass
      GearPath { d: "M6.4 13.4 L11 7.6 M8.6 14 L12.2 9.6"; stroke: root.paper; line: 1.1 }            // shine
      Rectangle {   // crest gem
        x: 10.8; y: 1.8; width: 2.4; height: 2.4; radius: 1.2; rotation: 45
        color: root.crystal; border.color: root.ink; border.width: 0.8
      }
    }

    // ===================================================================== orb
    Item {
      anchors.fill: parent
      visible: root.kind === "orb"

      GearPath { d: "M7.5 17.2 L16.5 17.2 L18 21.5 L6 21.5 Z"; fill: root.gold }                      // stand
      GearPath { d: "M6.8 17.4 Q5.6 15 7 14 M17.2 17.4 Q18.4 15 17 14"; line: 1.1 }                   // claws
      Rectangle {
        x: 5; y: 3.2; width: 14; height: 14; radius: 7
        color: root.net === "none" ? root.stone : root.glass
        border.color: root.ink; border.width: 1.3
      }
      // wifi: arcs lit by signal strength
      Repeater {
        model: root.net === "wifi" ? 3 : 0
        GearPath {
          required property int index
          readonly property bool lit: root.level > index / 3
          d: {
            var r = 1.8 + index * 1.9
            return "M" + (12 - r) + " " + (13.4 - r * 0.2) + " Q12 " + (13.4 - r * 1.6) + " " + (12 + r) + " " + (13.4 - r * 0.2)
          }
          stroke: lit ? root.ink : root.stone
          line: 1.3
          opacity: lit ? 1 : 0.6
        }
      }
      Rectangle { visible: root.net === "wifi"; x: 11.1; y: 12.6; width: 1.8; height: 1.8; radius: 0.9; color: root.ink }
      // ethernet: a glowing core
      Rectangle {
        visible: root.net === "ethernet"
        x: 9; y: 7.2; width: 6; height: 6; radius: 3
        color: root.glow; border.color: root.ink; border.width: 0.8
        opacity: root.pulse
      }
      // offline: cracked
      GearPath { visible: root.net === "none"; d: "M9 5.4 L11.4 9 L9.8 11 L12.8 14.6 M11.4 9 L14.2 8"; line: 1 }
      GearPath { d: "M8 8.4 Q8.6 6 10.8 5.2"; stroke: root.paper; line: 1.1 }                       // shine
    }
  }
}
