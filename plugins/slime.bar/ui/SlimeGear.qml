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
//
//   indicators (all use `lit` for their active state):
//        "bell"       do not disturb (lit = silenced: strapped shut)
//        "candle"     night light (lit = burning)
//        "mug"        stay awake (lit = steaming coffee)
//        "hourglass"  reminders (lit = sand running)
//        "eye"        screen recording (lit = open, red iris pulsing)
//        "trumpet"    dictation (lit = listening, sound flowing in)
//
//   command centre:
//        "cottage" home · "shield" system · "painting" wallpapers ·
//        "scroll" tasks · "anvil" settings · "arrow" (flip = points left) ·
//        "broom" clear
//
//   widgets:
//        "chest"      plugin picker (lit = lid open, glowing loot)
//        "book"       spellbook (memory)       lit = glowing rune
//        "potion"     bubbling flask           lit = bubbling
//        "skull"      grinning skull           lit = glowing eyes
//        "sword" · "axe" · "hat" (wizard) · "frog" (lit = croaking) — floating bits
//        "lich"       crowned lich with a staff    lit = casting: arm raised,
//                     eyes and hand blazing (the media widget's spellcaster)
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
  property bool lit: true
  property bool flip: false

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
  readonly property color flame: pal.bright_yellow || pal.yellow || "#ffd000"
  readonly property color ember: pal.orange || pal.red || "#ff5a1f"
  readonly property color blood: pal.red || "#ff1720"
  readonly property color coffee: Qt.darker(leather, 1.6)

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
    Loader {
      anchors.fill: parent
      active: root.kind === "backpack"
      sourceComponent: Item {
        anchors.fill: parent

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
    }

    // =============================================================== runestone
    Loader {
      anchors.fill: parent
      active: root.kind === "runestone"
      sourceComponent: Item {
        anchors.fill: parent

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
    }

    // ==================================================================== horn
    Loader {
      anchors.fill: parent
      active: root.kind === "horn"
      sourceComponent: Item {
        anchors.fill: parent

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
    }

    // ================================================================== mirror
    Loader {
      anchors.fill: parent
      active: root.kind === "mirror"
      sourceComponent: Item {
        anchors.fill: parent

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
    }

    // ===================================================================== orb
    Loader {
      anchors.fill: parent
      active: root.kind === "orb"
      sourceComponent: Item {
        anchors.fill: parent

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

    // ==================================================================== bell
    Loader {
      anchors.fill: parent
      active: root.kind === "bell"
      sourceComponent: Item {
        anchors.fill: parent

        GearPath { d: "M12 2.2 Q13.6 2.2 13.6 3.8"; line: 1.2 }                                      // hanger
        GearPath { d: "M12 3.4 Q17.2 3.4 17.6 9.4 L18 14.6 L20.4 18.2 L3.6 18.2 L6 14.6 L6.4 9.4 Q6.8 3.4 12 3.4 Z"; fill: root.gold }
        GearPath { d: "M8.4 8 Q9 5.8 11 5.4"; stroke: root.paper; line: 1.1 }                     // shine
        Rectangle { x: 10.3; y: 18.4; width: 3.4; height: 3.4; radius: 1.7; color: root.gold; border.color: root.ink; border.width: 1 }
        // silenced: a leather strap cinched round the bell, and a snore
        GearPath { visible: root.lit; d: "M4.8 12.6 L19.2 9.6 L19.6 12.2 L5.2 15.2 Z"; fill: root.leather; line: 1.1 }
        Rectangle { visible: root.lit; x: 10.9; y: 10.6; width: 2.6; height: 2.8; radius: 0.5; color: root.gold; border.color: root.ink; border.width: 0.7; rotation: -12 }
        GearPath { visible: root.lit; d: "M19.6 2.4 L22.6 2.4 L19.6 5.4 L22.6 5.4"; line: 1.1; opacity: root.pulse }
      }
    }

    // ================================================================== candle
    Loader {
      anchors.fill: parent
      active: root.kind === "candle"
      sourceComponent: Item {
        anchors.fill: parent

        GearPath { d: "M3.8 20.2 Q12 23.8 20.2 20.2 Q12 18.2 3.8 20.2 Z"; fill: root.gold }         // dish
        GearPath { d: "M19.4 20 Q22.6 18.6 21.4 16.6"; line: 1.3 }                                  // handle
        GearPath { d: "M9.2 10.4 L14.8 10.4 L14.8 20.4 L9.2 20.4 Z"; fill: root.paper }              // wax
        GearPath { d: "M9.2 10.6 Q10.2 13.6 11 11 M13.4 10.6 Q14 14.6 14.8 12.2"; fill: root.paper; line: 1 }   // wax drips
        GearPath { d: "M12 10.4 L12 8.6"; line: 1.1 }                                               // wick
        // flame (flickers) when lit, a curl of smoke when out
        GearPath {
          visible: root.lit
          d: "M12 1.8 Q15.6 6.2 12.2 9.2 Q8.6 6.6 12 1.8 Z"
          fill: root.flame
          stroke: root.ember
          line: 1
          transform: Scale { origin.x: 12; origin.y: 9; yScale: 0.9 + 0.12 * Math.sin(root.time * 11); xScale: 1 - 0.06 * Math.sin(root.time * 7) }
        }
        GearPath { visible: root.lit; d: "M12 5.6 Q13.2 7.2 12.1 8.4 Q11 7.2 12 5.6 Z"; fill: root.paper; stroke: "transparent" }
        GearPath { visible: !root.lit; d: "M12 8 Q10.6 6.4 12.2 5 Q13.6 3.6 12.2 2"; line: 1; opacity: 0.6 }
      }
    }

    // ===================================================================== mug
    Loader {
      anchors.fill: parent
      active: root.kind === "mug"
      sourceComponent: Item {
        anchors.fill: parent

        GearPath { d: "M15.6 10.4 Q21 10.2 20.6 14.4 Q20.2 18 15.6 17.6"; line: 1.8 }                // handle
        GearPath { d: "M4.6 8.6 L15.8 8.6 L15.2 20.4 Q15.1 21.4 14 21.4 L6.4 21.4 Q5.3 21.4 5.2 20.4 Z"; fill: root.leather }
        GearPath { d: "M4.9 12.4 L15.6 12.4 M5.1 17.2 L15.3 17.2"; stroke: root.gold; line: 1.4 }   // bands
        GearPath { d: "M4.6 8.6 Q10.2 10.6 15.8 8.6 Q10.2 6.8 4.6 8.6 Z"; fill: root.coffee; line: 1 }  // coffee
        Repeater {    // steam while lit
          model: root.lit ? 2 : 0
          GearPath {
            required property int index
            readonly property real drift: Math.sin(root.time * 2.4 + index * 2) * 0.8
            d: {
              var x = 8 + index * 4 + drift
              return "M" + x + " 6.6 Q" + (x - 1.4) + " 4.8 " + x + " 3.4 Q" + (x + 1.4) + " 2 " + x + " 0.8"
            }
            line: 1.1
            opacity: 0.45 + 0.35 * Math.sin(root.time * 3 + index)
          }
        }
      }
    }

    // =============================================================== hourglass
    Loader {
      anchors.fill: parent
      active: root.kind === "hourglass"
      sourceComponent: Item {
        anchors.fill: parent

        readonly property real sand: root.lit ? (root.time * 0.08) % 1 : 0.4   // fraction fallen
        GearPath { d: "M7.2 4 L16.8 4 Q16.8 9.4 12.8 12 Q16.8 14.6 16.8 20 L7.2 20 Q7.2 14.6 11.2 12 Q7.2 9.4 7.2 4 Z"; fill: root.glass; line: 1.1 }
        // top sand shrinks, bottom grows
        GearPath {
          readonly property real sandTop: 6 + parent.sand * 5
          d: "M" + (8.2 + (sandTop - 6) * 0.5) + " " + sandTop + " L" + (15.8 - (sandTop - 6) * 0.5) + " " + sandTop + " Q14.6 10 12 11.6 Q9.4 10 " + (8.2 + (sandTop - 6) * 0.5) + " " + sandTop + " Z"
          fill: root.flame; line: 0.6
          visible: parent.sand < 0.97
        }
        GearPath {
          readonly property real sandTop: 19 - parent.sand * 5
          d: "M8 19.2 Q9 " + sandTop + " 12 " + sandTop + " Q15 " + sandTop + " 16 19.2 Z"
          fill: root.flame; line: 0.6
        }
        GearPath { visible: root.lit; d: "M12 11.8 L12 18.6"; stroke: root.flame; line: 1 }            // falling stream
        GearPath { d: "M5.4 2.6 L18.6 2.6 L18.6 4.4 L5.4 4.4 Z M5.4 19.6 L18.6 19.6 L18.6 21.4 L5.4 21.4 Z"; fill: root.leather; line: 1 }
      }
    }

    // ===================================================================== eye
    Loader {
      anchors.fill: parent
      active: root.kind === "eye"
      sourceComponent: Item {
        anchors.fill: parent

        GearPath { d: "M2 12 Q12 2.4 22 12 Q12 21.6 2 12 Z"; fill: root.paper }                        // eyeball
        GearPath { visible: root.lit; d: "M4.4 10.4 L6.6 11.2 M19.6 13.6 L17.2 12.8 M5.2 14 L7.2 13"; stroke: root.blood; line: 0.7 }   // veins
        Rectangle {
          visible: root.lit
          x: 12 - width / 2; y: 12 - height / 2
          width: 9 * (0.92 + 0.08 * root.pulse); height: width; radius: width / 2
          color: root.blood; border.color: root.ink; border.width: 1
          Rectangle { anchors.centerIn: parent; width: parent.width * 0.45; height: width; radius: width / 2; color: root.ink }
          Rectangle { x: parent.width * 0.2; y: parent.height * 0.18; width: 1.8; height: 1.8; radius: 0.9; color: root.paper }
        }
        // asleep: lid shut with lashes
        GearPath { visible: !root.lit; d: "M2 12 Q12 2.4 22 12 Q12 15.6 2 12 Z"; fill: root.leatherLight }
        GearPath { visible: !root.lit; d: "M6 14.4 L5.2 16.2 M12 15.2 L12 17.2 M18 14.4 L18.8 16.2"; line: 1 }
        GearPath { visible: root.lit; d: "M12 20.4 Q13 22 12 23 Q11 22 12 20.4 Z"; fill: root.blood; line: 0.7 }   // drip
      }
    }

    // ================================================================= trumpet
    Loader {
      anchors.fill: parent
      active: root.kind === "trumpet"
      sourceComponent: Item {
        anchors.fill: parent

        GearPath { d: "M9.6 7.6 Q15.2 11.2 21.2 11.2 L21.2 13.2 Q15.2 13.2 9.6 16.8 Z"; fill: root.gold }   // tube
        GearPath { d: "M9.6 5 Q6.2 12 9.6 19 Q13.2 12 9.6 5 Z"; fill: root.gold }                        // flared bell
        GearPath { d: "M9.6 7 Q7.6 12 9.6 17 Q11.6 12 9.6 7 Z"; fill: Qt.darker(root.gold, 1.5); line: 0.8 }
        GearPath { d: "M20.6 10.4 Q23.2 10.8 22.6 14.2"; line: 1.3 }                                       // earpiece curl
        Repeater {   // sound flowing in while listening
          model: root.lit ? 2 : 0
          GearPath {
            required property int index
            d: {
              var r = 2.6 + index * 2.2
              return "M" + (6 - r * 0.5) + " " + (12 - r) + " Q" + (6 - r * 1.1) + " 12 " + (6 - r * 0.5) + " " + (12 + r)
            }
            line: 1.3
            opacity: 0.5 + 0.5 * Math.sin(root.time * 5 + index)
          }
        }
      }
    }


    // ================================================================= cottage
    Loader {
      anchors.fill: parent
      active: root.kind === "cottage"
      sourceComponent: Item {
        anchors.fill: parent

        GearPath { d: "M16 5 L16 2.6 L18.4 2.6 L18.4 7.4"; fill: root.stone; line: 1.1 }                   // chimney
        GearPath { d: "M5 11 L5 21 L19 21 L19 11 Z"; fill: root.paper }                                     // walls
        GearPath { d: "M2.6 12 L12 3.4 L21.4 12 Z"; fill: root.leather }                                    // roof
        GearPath { d: "M5.4 9.4 L9.6 5.6 M8.6 10.6 L12 7.6 M15 9 L18.4 11.6"; line: 0.8; stroke: root.leatherLight }
        GearPath { d: "M10 21 L10 15.6 Q12 13.8 14 15.6 L14 21"; fill: root.leatherLight; line: 1.1 }     // door
        Rectangle { x: 15.2; y: 13.4; width: 2.6; height: 2.6; color: root.lit ? root.flame : root.glass; border.color: root.ink; border.width: 0.8 }
      }
    }

    // ================================================================== shield
    Loader {
      anchors.fill: parent
      active: root.kind === "shield"
      sourceComponent: Item {
        anchors.fill: parent

        GearPath { d: "M12 2.4 L20 5.2 Q20.4 15.4 12 21.6 Q3.6 15.4 4 5.2 Z"; fill: root.stone }
        GearPath { d: "M12 4.6 L17.8 6.6 Q18 14 12 19 Q6 14 6.2 6.6 Z"; fill: root.crystal; line: 0.9 }
        GearPath { d: "M12 5 L12 18.6 M6.4 10.8 L17.6 10.8"; stroke: root.gold; line: 1.4 }                  // cross
        GearPath { d: "M8 8 Q8.4 6.4 10 6"; stroke: root.paper; line: 1 }
      }
    }

    // ================================================================ painting
    Loader {
      anchors.fill: parent
      active: root.kind === "painting"
      sourceComponent: Item {
        anchors.fill: parent

        GearPath { d: "M2.6 4.6 L21.4 4.6 L21.4 19.4 L2.6 19.4 Z"; fill: root.gold }
        GearPath { d: "M4.8 6.8 L19.2 6.8 L19.2 17.2 L4.8 17.2 Z"; fill: root.glass; line: 0.9 }
        GearPath { d: "M4.8 17.2 L9.4 11.2 L12.4 14.6 L14.6 12.4 L19.2 17.2 Z"; fill: root.leatherLight; line: 0.8 }   // hills
        Rectangle { x: 14.6; y: 8.2; width: 2.6; height: 2.6; radius: 1.3; color: root.flame; border.color: root.ink; border.width: 0.6 }
        GearPath { d: "M12 4.6 L12 2 M10 2 L14 2"; line: 1 }                                                // hook
      }
    }

    // ================================================================== scroll
    Loader {
      anchors.fill: parent
      active: root.kind === "scroll"
      sourceComponent: Item {
        anchors.fill: parent

        GearPath { d: "M6 4.2 L18.6 4.2 L18.6 18.4 Q18.6 20.4 16.6 20.4 L4.6 20.4"; fill: root.paper }
        GearPath { d: "M4.6 20.4 Q2.4 20.4 2.6 18.4 Q2.8 16.6 4.6 16.6 L16.6 16.6 Q14.8 16.6 14.8 18.4 Q14.8 20.4 16.6 20.4"; fill: Qt.darker(root.paper, 1.15); line: 1.1 }
        GearPath { d: "M6 4.2 Q4 4.2 4 6.2 Q4 8 6 8 L8 8 L8 6.2 Q8 4.2 6 4.2 Z"; fill: Qt.darker(root.paper, 1.15); line: 1.1 }
        GearPath { d: "M10 9 L11 10 L13 7.8 M10 12.6 L11 13.6 L13 11.4"; line: 1.1 }                       // ticks
        GearPath { d: "M14.4 9 L16.6 9 M14.4 12.6 L16.6 12.6"; line: 1 }
        Rectangle { x: 15.6; y: 18.2; width: 3.4; height: 3.4; radius: 1.7; color: root.blood; border.color: root.ink; border.width: 0.7 }   // wax seal
      }
    }

    // =================================================================== anvil
    Loader {
      anchors.fill: parent
      active: root.kind === "anvil"
      sourceComponent: Item {
        anchors.fill: parent

        GearPath { d: "M3 9 L18.4 9 Q21.6 9 21.6 11 Q18 12 15.6 13.4 L15.6 16 L17.6 18.4 L6.4 18.4 L8.4 16 L8.4 13.4 Q5 12.6 3 9 Z"; fill: root.stone }
        GearPath { d: "M5.4 20.6 L18.6 20.6 L17.6 18.4 L6.4 18.4 Z"; fill: root.stone; line: 1 }
        GearPath { d: "M13 7.4 L20.2 1.8"; stroke: root.leather; line: 2 }                                   // hammer handle
        GearPath { d: "M9.6 3 L13.2 1.4 L15.6 6.4 L12 8 Z"; fill: root.gold; line: 1 }                       // hammer head
        GearPath { visible: root.lit; d: "M7.2 6.4 L6 5 M9 5.8 L8.6 4 M5.8 8 L4.2 7.4"; stroke: root.flame; line: 1; opacity: root.pulse }   // sparks
      }
    }

    // =================================================================== arrow
    Loader {
      anchors.fill: parent
      active: root.kind === "arrow"
      sourceComponent: Item {
        anchors.fill: parent
        transform: Scale { origin.x: 12; xScale: root.flip ? -1 : 1 }

        GearPath { d: "M11.4 16 L11.4 22 M13.4 16 L13.4 22"; line: 1.4 }                                   // post
        GearPath { d: "M3 6.6 L16 6.6 L21 11.4 L16 16.2 L3 16.2 Z"; fill: root.leather }                     // sign
        GearPath { d: "M5 9.4 L14.6 9.4 M5 13.2 L12.4 13.2"; stroke: root.leatherLight; line: 0.9 }
        Rectangle { x: 16.4; y: 10.4; width: 2; height: 2; radius: 1; color: root.gold; border.color: root.ink; border.width: 0.5 }
      }
    }

    // =================================================================== broom
    Loader {
      anchors.fill: parent
      active: root.kind === "broom"
      sourceComponent: Item {
        anchors.fill: parent

        GearPath { d: "M17.6 2 L10.8 13.4"; stroke: root.leather; line: 2.2 }                                // handle
        GearPath { d: "M9.2 12.2 L13.2 14.6 L12.4 16.2 L8 13.8 Z"; fill: root.gold; line: 1 }                // binding
        GearPath { d: "M8 13.8 L12.4 16.2 Q10.6 21.4 5 22.2 Q3 19.8 4.2 18.4 Q6 16.4 8 13.8 Z"; fill: root.flame }
        GearPath { d: "M8.6 16 L5.6 20.2 M10 16.8 L7.8 21 M7.4 15.2 L4.6 18.8"; line: 0.7 }
        GearPath { visible: root.lit; d: "M16 18.4 L17 17.4 M18.4 20.6 L19.8 20.2 M17.4 21.8 L17.8 23"; line: 1; opacity: root.pulse }   // dust
      }
    }


    // =================================================================== chest
    Loader {
      anchors.fill: parent
      active: root.kind === "chest"
      sourceComponent: Item {
        anchors.fill: parent

        // glow spilling out when open
        Rectangle {
          visible: root.lit
          x: 5; y: 5; width: 14; height: 6; radius: 3
          color: root.flame
          opacity: 0.5 * root.pulse
        }
        GearPath { d: "M3.6 11 L20.4 11 L19.6 20.6 Q19.5 21.4 18.6 21.4 L5.4 21.4 Q4.5 21.4 4.4 20.6 Z"; fill: root.leather }   // box
        GearPath { d: "M3.9 15 L20.1 15"; stroke: root.gold; line: 1.6 }                                                          // band
        GearPath { d: "M8 11.2 L8 21.2 M16 11.2 L16 21.2"; stroke: root.gold; line: 1.2 }
        // lid: closed arches over the box; open tips back
        GearPath {
          d: root.lit ? "M4.2 10.6 L6.6 3.2 Q12 1.6 17.4 3.2 L19.8 10.6 Z"
                      : "M3.6 11 Q3.6 5.2 12 5.2 Q20.4 5.2 20.4 11 Z"
          fill: root.leatherLight
        }
        GearPath { visible: !root.lit; d: "M8 5.8 L8 11 M16 5.8 L16 11"; stroke: root.gold; line: 1.2 }
        // loot: coins and a gem peeking over the rim
        Rectangle { visible: root.lit; x: 7.2; y: 8.6; width: 3.4; height: 3.4; radius: 1.7; color: root.gold; border.color: root.ink; border.width: 0.7 }
        Rectangle { visible: root.lit; x: 10.2; y: 7.6; width: 3.2; height: 3.2; rotation: 45; color: root.crystal; border.color: root.ink; border.width: 0.7 }
        Rectangle { visible: root.lit; x: 13.4; y: 8.8; width: 3.4; height: 3.4; radius: 1.7; color: root.gold; border.color: root.ink; border.width: 0.7 }
        Rectangle { x: 10.6; y: root.lit ? 11.6 : 9.6; width: 2.8; height: 3.2; radius: 0.6; color: root.gold; border.color: root.ink; border.width: 0.8 }   // lock
      }
    }


    // ==================================================================== book
    Loader {
      anchors.fill: parent
      active: root.kind === "book"
      sourceComponent: Item {
        anchors.fill: parent

        GearPath { d: "M4 5 Q4 3.2 5.8 3.2 L19.2 3.2 L19.2 18.6 L5.8 18.6 Q4 18.6 4 20.4 Z"; fill: root.leather }     // cover
        GearPath { d: "M4 20.4 Q4 22 5.8 22 L19.2 22 L19.2 18.6 L5.8 18.6 Q4 18.6 4 20.4 Z"; fill: root.paper; line: 1.1 }   // pages
        GearPath { d: "M6.2 20.3 L18.2 20.3"; line: 0.6 }
        GearPath { d: "M7.2 3.4 L7.2 18.4"; stroke: root.gold; line: 1.2 }                                                   // spine band
        GearPath { d: "M10 7 L16.4 7 L16.4 14.8 L10 14.8 Z"; fill: root.leatherLight; line: 0.9 }                              // plate
        GearPath {   // rune
          d: "M13.2 8.2 L13.2 13.6 M11.4 9.6 L15 12.2 M15 9.6 L11.4 12.2"
          stroke: root.lit ? root.glow : root.ink
          line: 1.2
          opacity: root.lit ? root.pulse : 0.8
        }
        Rectangle { x: 18.2; y: 9.4; width: 2.6; height: 3.4; radius: 0.8; color: root.gold; border.color: root.ink; border.width: 0.7 }   // clasp
      }
    }

    // ================================================================== potion
    Loader {
      anchors.fill: parent
      active: root.kind === "potion"
      sourceComponent: Item {
        anchors.fill: parent

        GearPath { d: "M9.6 2.4 L14.4 2.4 L14.4 5 L9.6 5 Z"; fill: root.leather; line: 1 }                                  // cork
        GearPath { d: "M10 5 L10 9 Q4.2 11 4.2 15.8 Q4.2 21.6 12 21.6 Q19.8 21.6 19.8 15.8 Q19.8 11 14 9 L14 5 Z"; fill: root.glass }
        GearPath { d: "M5.2 14.6 Q12 12.2 18.8 14.6 Q19.4 20.6 12 20.6 Q4.6 20.6 5.2 14.6 Z"; fill: root.pal.bright_magenta || root.blood; line: 0.9 }   // brew
        GearPath { d: "M7 12.8 Q7.6 10.6 9.4 10"; stroke: root.paper; line: 1.1 }                                            // shine
        Repeater {   // bubbles rising out of the brew
          model: root.lit ? 3 : 0
          Rectangle {
            required property int index
            readonly property real rise: (root.time * 0.6 + index / 3) % 1
            x: 9.6 + index * 2.2 - width / 2
            y: 16 - rise * 14
            width: 1.8 + index * 0.4; height: width; radius: width / 2
            color: "transparent"; border.color: root.ink; border.width: 0.6
            opacity: 1 - rise
          }
        }
      }
    }

    // =================================================================== skull
    Loader {
      anchors.fill: parent
      active: root.kind === "skull"
      sourceComponent: Item {
        anchors.fill: parent

        GearPath { d: "M12 2.4 Q20.4 2.4 20.4 10.4 Q20.4 14 17.6 15.4 L17.6 18.2 L6.4 18.2 L6.4 15.4 Q3.6 14 3.6 10.4 Q3.6 2.4 12 2.4 Z"; fill: root.paper }
        GearPath { d: "M8.2 18.2 L8.2 21.4 L15.8 21.4 L15.8 18.2 M10.8 18.4 L10.8 21.2 M13.2 18.4 L13.2 21.2"; fill: root.paper; line: 1.1 }   // jaw & teeth
        GearPath { d: "M6.8 10 Q6.8 7.4 9.4 7.8 Q10.6 8.4 10.4 10.8 Q10 13 8 12.6 Q6.8 12.2 6.8 10 Z M17.2 10 Q17.2 7.4 14.6 7.8 Q13.4 8.4 13.6 10.8 Q14 13 16 12.6 Q17.2 12.2 17.2 10 Z"; fill: root.ink }   // sockets
        GearPath { d: "M12 13 L11 15.2 L13 15.2 Z"; fill: root.ink; line: 0.6 }                                              // nose
        Rectangle { visible: root.lit; x: 8; y: 9.2; width: 1.8; height: 1.8; radius: 0.9; color: root.glow; opacity: root.pulse }
        Rectangle { visible: root.lit; x: 14.2; y: 9.2; width: 1.8; height: 1.8; radius: 0.9; color: root.glow; opacity: root.pulse }
        GearPath { d: "M16.2 4.4 L15 6.6 L16.4 7.4"; line: 0.7 }                                                              // crack
      }
    }


    // ==================================================================== lich
    Loader {
      anchors.fill: parent
      active: root.kind === "lich"
      sourceComponent: Item {
        id: lich
        anchors.fill: parent
        readonly property color robe: Qt.darker(root.pal.blue || "#3f74ff", 2.2)
        readonly property color robeLight: Qt.darker(root.pal.blue || "#3f74ff", 1.5)
        readonly property color spell: root.pal.bright_magenta || root.pal.magenta || "#ff69c1"
        // casting: the arm lifts and sways with the spell
        readonly property real lift: root.lit ? 2.6 + Math.sin(root.time * 5) * 0.8 : 0

        // staff with a crystal, behind the body
        GearPath { d: "M5.2 5.6 L3.6 22.6"; stroke: root.leather; line: 1.8 }
        GearPath { d: "M5.2 5.6 L3.8 3.4 M5.2 5.6 L6.8 3.6"; stroke: root.leather; line: 1 }
        Rectangle {
          x: 5.3 - 1.9; y: 3.6 - 1.9; width: 3.8; height: 3.8; radius: 1.9
          color: root.crystal; border.color: root.ink; border.width: 0.8
          opacity: root.lit ? root.pulse : 0.85
        }
        // robe and hood
        GearPath { d: "M12 2.6 Q17 3 17.6 8.4 L20.2 21.6 Q12 23.2 3.8 21.6 L6.4 8.4 Q7 3 12 2.6 Z"; fill: lich.robe }
        GearPath { d: "M7.6 21.4 L9 14.6 M16.4 21.4 L15 14.6 M12 22.1 L12 15.4"; stroke: lich.robeLight; line: 0.8 }   // folds
        GearPath { d: "M9 7.8 Q12 4.8 15 7.8 L14.6 12.6 Q12 13.8 9.4 12.6 Z"; fill: root.ink; line: 0.8 }             // hood shadow
        // skull face in the hood
        GearPath { d: "M12 6.8 Q14.2 6.8 14.2 9.3 Q14.2 11.2 13.2 11.6 L13.2 12.6 L10.8 12.6 L10.8 11.6 Q9.8 11.2 9.8 9.3 Q9.8 6.8 12 6.8 Z"; fill: root.paper; line: 0.7 }
        Rectangle { x: 10.6; y: 8.6; width: 1.4; height: 1.4; radius: 0.7; color: root.lit ? lich.spell : root.glow; opacity: root.pulse }
        Rectangle { x: 12.2; y: 8.6; width: 1.4; height: 1.4; radius: 0.7; color: root.lit ? lich.spell : root.glow; opacity: root.pulse }
        GearPath { d: "M11.4 11.8 L11.4 12.4 M12.6 11.8 L12.6 12.4"; line: 0.5 }                                        // teeth
        // crown
        GearPath { d: "M8.6 4.6 L9.2 1.8 L10.6 3.6 L12 1 L13.4 3.6 L14.8 1.8 L15.4 4.6 Q12 3.6 8.6 4.6 Z"; fill: root.gold; line: 0.9 }
        Rectangle { x: 11.4; y: 2.6; width: 1.2; height: 1.2; radius: 0.6; color: lich.spell; border.color: root.ink; border.width: 0.4 }
        // casting arm: sleeve out to a bony hand
        GearPath {
          d: "M15.4 11 Q18.4 " + (11.6 - lich.lift) + " 20.4 " + (10.2 - lich.lift) + " L21 " + (12.2 - lich.lift) + " Q18.6 " + (14 - lich.lift) + " 16 14.4 Z"
          fill: lich.robeLight
          line: 1
        }
        GearPath {   // bony fingers splayed
          d: "M20.8 " + (10.6 - lich.lift) + " L22.8 " + (9.2 - lich.lift) + " M21.2 " + (11.2 - lich.lift) + " L23.4 " + (10.8 - lich.lift) + " M20.8 " + (11.8 - lich.lift) + " L22.6 " + (12.6 - lich.lift)
          stroke: root.paper
          line: 0.9
        }
        // the spell gathering in his palm
        Rectangle {
          visible: root.lit
          x: 22.6 - width / 2; y: 10.6 - lich.lift - height / 2
          width: 3.6 + root.pulse * 1.6; height: width; radius: width / 2
          color: lich.spell
          opacity: 0.55 * root.pulse
        }
      }
    }


    // ================================================ wizard (a caster, like the lich)
    Loader {
      anchors.fill: parent
      active: root.kind === "wizard"
      sourceComponent: Item {
        id: wiz
        anchors.fill: parent
        readonly property color robe: Qt.darker(root.pal.magenta || "#8a4dff", 1.7)
        readonly property color robeLight: Qt.darker(root.pal.magenta || "#8a4dff", 1.2)
        readonly property color skin: "#f2c2a0"
        readonly property color spell: root.pal.bright_cyan || root.pal.cyan || "#10ffd9"
        readonly property real lift: root.lit ? 2.6 + Math.sin(root.time * 5) * 0.8 : 0

        // gnarled staff with a glowing orb
        GearPath { d: "M5.2 6 Q4.2 12 3.6 22.6"; stroke: root.leather; line: 1.8 }
        Rectangle {
          x: 5.2 - 2; y: 4.2 - 2; width: 4; height: 4; radius: 2
          color: root.flame; border.color: root.ink; border.width: 0.8
          opacity: root.lit ? root.pulse : 0.85
        }
        // robe, face, beard
        GearPath { d: "M12 5.6 Q17 6 17.6 10 L20.2 21.6 Q12 23.2 3.8 21.6 L6.4 10 Q7 6 12 5.6 Z"; fill: wiz.robe }
        GearPath { d: "M7.6 21.4 L9 15 M16.4 21.4 L15 15"; stroke: wiz.robeLight; line: 0.8 }
        GearPath { d: "M9.6 7.8 Q12 6.8 14.4 7.8 L14.2 10.8 Q12 11.8 9.8 10.8 Z"; fill: wiz.skin; line: 0.8 }
        Rectangle { x: 10.4; y: 8.4; width: 1.1; height: 1.1; radius: 0.55; color: root.ink }
        Rectangle { x: 12.5; y: 8.4; width: 1.1; height: 1.1; radius: 0.55; color: root.ink }
        GearPath { d: "M9.4 10.2 Q12 18.4 14.6 10.2 Q12 11.8 9.4 10.2 Z"; fill: root.paper; line: 0.8 }
        // the hat: a wide brim and a crooked cone with a star
        GearPath { d: "M6.4 7.6 Q12 5.6 17.6 7.6 Q12 9 6.4 7.6 Z"; fill: wiz.robe; line: 0.9 }
        GearPath { d: "M8.4 7 Q10.6 3.4 11.6 0.4 Q12.8 1.4 15.4 6.8 Z"; fill: wiz.robe; line: 0.9 }
        GearPath { d: "M12.4 3.2 l0.35 0.8 l0.85 0.1 l-0.6 0.55 l0.15 0.85 l-0.75 -0.45 l-0.75 0.45 l0.15 -0.85 l-0.6 -0.55 l0.85 -0.1 Z"; fill: root.gold; line: 0.4 }
        // casting arm
        GearPath {
          d: "M15.4 12 Q18.4 " + (11.6 - wiz.lift) + " 20.4 " + (10.2 - wiz.lift) + " L21 " + (12.2 - wiz.lift) + " Q18.6 " + (14 - wiz.lift) + " 16 15 Z"
          fill: wiz.robeLight; line: 1
        }
        Rectangle { x: 21.4 - 1.4; y: 11.2 - wiz.lift - 1.4; width: 2.8; height: 2.8; radius: 1.4; color: wiz.skin; border.color: root.ink; border.width: 0.6 }
        Rectangle {
          visible: root.lit
          x: 22.8 - width / 2; y: 10.2 - wiz.lift - height / 2
          width: 3.6 + root.pulse * 1.6; height: width; radius: width / 2
          color: wiz.spell; opacity: 0.55 * root.pulse
        }
      }
    }

    // ================================================ priest (a caster, like the lich)
    Loader {
      anchors.fill: parent
      active: root.kind === "priest"
      sourceComponent: Item {
        id: priest
        anchors.fill: parent
        readonly property color skin: "#f2c2a0"
        readonly property color spell: root.pal.bright_yellow || root.pal.yellow || "#ffd000"
        readonly property real lift: root.lit ? 2.6 + Math.sin(root.time * 5) * 0.8 : 0

        // crozier
        GearPath { d: "M5.2 7 L3.6 22.6"; stroke: root.gold; line: 1.6 }
        GearPath { d: "M5.2 7.2 Q4.6 3.4 7 3.2 Q9 3.4 8.4 5.6"; stroke: root.gold; line: 1.3 }
        // white robe with a gold stole
        GearPath { d: "M12 5.6 Q17 6 17.6 10 L20.2 21.6 Q12 23.2 3.8 21.6 L6.4 10 Q7 6 12 5.6 Z"; fill: root.paper }
        GearPath { d: "M10.4 11.4 L9.6 21.8 M13.6 11.4 L14.4 21.8"; stroke: root.gold; line: 1.4 }
        GearPath { d: "M12 14 L12 17.6 M10.6 15.2 L13.4 15.2"; stroke: root.gold; line: 0.9 }
        // face
        GearPath { d: "M9.6 7.8 Q12 6.8 14.4 7.8 L14.2 10.8 Q12 12.2 9.8 10.8 Z"; fill: priest.skin; line: 0.8 }
        Rectangle { x: 10.4; y: 8.4; width: 1.1; height: 1.1; radius: 0.55; color: root.ink }
        Rectangle { x: 12.5; y: 8.4; width: 1.1; height: 1.1; radius: 0.55; color: root.ink }
        GearPath { d: "M11.2 10.4 Q12 11 12.8 10.4"; line: 0.6 }
        // mitre with a gold cross
        GearPath { d: "M9 7.8 L9.2 3.6 Q12 0.6 14.8 3.6 L15 7.8 Q12 7 9 7.8 Z"; fill: root.paper; line: 0.9 }
        GearPath { d: "M12 2.4 L12 6.2 M10.8 3.8 L13.2 3.8"; stroke: root.gold; line: 0.9 }
        // casting arm, gold light in the palm
        GearPath {
          d: "M15.4 12 Q18.4 " + (11.6 - priest.lift) + " 20.4 " + (10.2 - priest.lift) + " L21 " + (12.2 - priest.lift) + " Q18.6 " + (14 - priest.lift) + " 16 15 Z"
          fill: root.paper; line: 1
        }
        Rectangle { x: 21.4 - 1.4; y: 11.2 - priest.lift - 1.4; width: 2.8; height: 2.8; radius: 1.4; color: priest.skin; border.color: root.ink; border.width: 0.6 }
        Rectangle {
          visible: root.lit
          x: 22.8 - width / 2; y: 10.2 - priest.lift - height / 2
          width: 3.8 + root.pulse * 1.8; height: width; radius: width / 2
          color: priest.spell; opacity: 0.6 * root.pulse
        }
      }
    }

    // =================================================================== sword
    Loader {
      anchors.fill: parent
      active: root.kind === "sword"
      sourceComponent: Item {
        anchors.fill: parent
        GearPath { d: "M12 1.6 L14 4 L14 15 L10 15 L10 4 Z"; fill: Qt.tint(root.paper, Qt.rgba(0.5, 0.6, 0.75, 0.35)) }   // blade
        GearPath { d: "M12 3 L12 14"; stroke: Qt.rgba(1, 1, 1, 0.8); line: 0.8 }                                          // fuller
        GearPath { d: "M6.4 15 L17.6 15 L17 17 L7 17 Z"; fill: root.gold; line: 1 }                                      // guard
        GearPath { d: "M10.8 17 L13.2 17 L13.2 21 L10.8 21 Z"; fill: root.leather; line: 1 }                              // grip
        Rectangle { x: 10.4; y: 20.6; width: 3.2; height: 3.2; radius: 1.6; color: root.gold; border.color: root.ink; border.width: 0.8 }  // pommel
      }
    }

    // ===================================================================== axe
    Loader {
      anchors.fill: parent
      active: root.kind === "axe"
      sourceComponent: Item {
        anchors.fill: parent
        GearPath { d: "M7.6 22.4 L14.2 3.2"; stroke: root.leather; line: 2.2 }                                             // haft
        GearPath { d: "M12.6 4.4 Q20.6 2.8 21.4 9.8 Q17.4 8.6 15 11.4 Z"; fill: Qt.tint(root.paper, Qt.rgba(0.5, 0.6, 0.75, 0.35)) }   // blade
        GearPath { d: "M13.6 6.2 Q18.4 5.2 20.2 8.4"; stroke: Qt.rgba(1, 1, 1, 0.8); line: 0.8 }
        GearPath { d: "M12.2 7.4 L15.4 8.6"; stroke: root.gold; line: 1.6 }                                                // binding
      }
    }

    // ===================================================================== hat
    Loader {
      anchors.fill: parent
      active: root.kind === "hat"
      sourceComponent: Item {
        anchors.fill: parent
        readonly property color cloth: root.pal.magenta || "#f52e9b"
        GearPath { d: "M2 19.4 Q12 22.8 22 19.4 Q18.6 16.8 12 17 Q5.4 16.8 2 19.4 Z"; fill: parent.cloth }             // brim
        GearPath { d: "M6.2 18.2 Q9 11 10.8 6 Q12.4 1.6 16.4 2.2 Q13.6 3.6 13.8 7.6 Q15.4 12.4 17.8 18.2 Q12 19.6 6.2 18.2 Z"; fill: parent.cloth }   // crooked cone
        GearPath { d: "M6.6 16.6 Q12 18 17.4 16.6"; stroke: root.gold; line: 1.6 }                                        // band
        GearPath { d: "M10.8 10.8 L11.4 12 L12.6 12.2 L11.7 13 L12 14.2 L10.8 13.6 L9.6 14.2 L9.9 13 L9 12.2 L10.2 12 Z"; fill: root.flame; line: 0.5 }  // star
      }
    }

    // ==================================================================== frog
    Loader {
      anchors.fill: parent
      active: root.kind === "frog"
      sourceComponent: Item {
        anchors.fill: parent
        readonly property color skin: root.pal.green || "#1be33a"
        readonly property real puff: root.lit ? 1 + 0.25 * Math.abs(Math.sin(root.time * 4)) : 1
        GearPath { d: "M4 16 Q2.6 11.4 7 9.4 Q12 7.8 17 9.4 Q21.4 11.4 20 16 Q19 19.6 12 19.8 Q5 19.6 4 16 Z"; fill: parent.skin }   // body
        GearPath { d: "M3.4 18.8 Q6 16.6 8.4 19.4 M20.6 18.8 Q18 16.6 15.6 19.4"; fill: parent.skin; line: 1.1 }                 // feet
        Rectangle { x: 5.4; y: 5.2; width: 5.4; height: 5.4; radius: 2.7; color: parent.skin; border.color: root.ink; border.width: 1 }
        Rectangle { x: 13.2; y: 5.2; width: 5.4; height: 5.4; radius: 2.7; color: parent.skin; border.color: root.ink; border.width: 1 }
        Rectangle { x: 6.6; y: 6.4; width: 3; height: 3; radius: 1.5; color: root.paper; border.color: root.ink; border.width: 0.6
          Rectangle { x: 0.9; y: 0.9; width: 1.4; height: 1.4; radius: 0.7; color: root.ink } }
        Rectangle { x: 14.4; y: 6.4; width: 3; height: 3; radius: 1.5; color: root.paper; border.color: root.ink; border.width: 0.6
          Rectangle { x: 0.9; y: 0.9; width: 1.4; height: 1.4; radius: 0.7; color: root.ink } }
        GearPath { d: "M8.4 13.6 Q12 15.8 15.6 13.6"; line: 1 }                                                            // smile
        Rectangle {   // throat pouch, puffing while croaking
          visible: root.lit
          x: 12 - width / 2; y: 15.2
          width: 5 * parent.puff; height: 3.2 * parent.puff; radius: height / 2
          color: Qt.lighter(parent.skin, 1.35); border.color: root.ink; border.width: 0.6
        }
      }
    }

  }
}
