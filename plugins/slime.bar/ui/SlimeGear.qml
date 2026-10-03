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
//        "wizard" · "priest" · "dryad" · "witch" · "slimecaster" (a slime full of
//                     wands and staffs) · "wisp" (a flame in a flowing energy
//                     field) — the other casters, lit the same way
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
  readonly property var pal: bar && bar.slimePalette ? bar.slimePalette : ({})
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

    // ================================================ dryad (a caster, like the lich)
    Loader {
      anchors.fill: parent
      active: root.kind === "dryad"
      sourceComponent: Item {
        id: dryad
        anchors.fill: parent
        readonly property color leaf: root.pal.green || "#3fb950"
        readonly property color leafLight: root.pal.bright_green || Qt.lighter(dryad.leaf, 1.4)
        readonly property color bark: Qt.darker(root.leather, 1.1)
        readonly property color skin: Qt.tint("#d9c7a0", Qt.rgba(dryad.leaf.r, dryad.leaf.g, dryad.leaf.b, 0.35))
        readonly property color spell: root.pal.bright_green || "#7dff6a"
        readonly property real lift: root.lit ? 2.6 + Math.sin(root.time * 5) * 0.8 : 0

        // a flowering branch for a staff
        GearPath { d: "M5 5.4 Q3.8 9 4.4 13 Q3.4 17 3.6 22.6"; stroke: dryad.bark; line: 1.8 }
        GearPath { d: "M4.6 9 Q2.4 8 1.6 6.2 M4.4 13.4 Q6.4 12.8 7 11.2"; stroke: dryad.bark; line: 0.9 }
        Rectangle { x: 3.4; y: 2.8; width: 3.2; height: 3.2; radius: 1.6; color: root.pal.bright_magenta || "#ff9ad5"; border.color: root.ink; border.width: 0.6; opacity: root.lit ? root.pulse : 0.9 }
        Rectangle { x: 0.6; y: 5.2; width: 2; height: 2; radius: 1; color: dryad.leafLight; border.color: root.ink; border.width: 0.5 }
        // a body of bark, a skirt of leaves
        GearPath { d: "M12 6.2 Q16 6.6 16.6 10.6 L18.4 16.4 L5.6 16.4 L7.4 10.6 Q8 6.6 12 6.2 Z"; fill: dryad.bark }
        GearPath { d: "M9.6 9.6 Q10.2 12 9.4 15 M14.2 9.8 Q13.6 12.4 14.6 15"; stroke: Qt.lighter(dryad.bark, 1.5); line: 0.6 }
        GearPath { d: "M4.2 21.6 L5.8 15.6 L8 20.2 L9.6 15.8 L12 21.2 L14.4 15.8 L16 20.2 L18.2 15.6 L19.8 21.6 Q12 23.2 4.2 21.6 Z"; fill: dryad.leaf; line: 0.9 }
        // face, and hair of leaves
        GearPath { d: "M9.6 5.6 Q12 4.4 14.4 5.6 L14.2 8.8 Q12 10 9.8 8.8 Z"; fill: dryad.skin; line: 0.8 }
        Rectangle { x: 10.4; y: 6.4; width: 1.1; height: 1.1; radius: 0.55; color: root.ink }
        Rectangle { x: 12.5; y: 6.4; width: 1.1; height: 1.1; radius: 0.55; color: root.ink }
        GearPath { d: "M11.2 8.4 Q12 8.9 12.8 8.4"; line: 0.5 }
        GearPath { d: "M8.2 7 Q7.4 2.6 10 2.4 Q11 0.6 12.8 1.8 Q15.6 0.8 15.8 3.6 Q17.4 5 15.8 7.4 Q15 4.4 12 4.2 Q9 4.4 8.2 7 Z"; fill: dryad.leaf; line: 0.9 }
        GearPath { d: "M9.4 3.4 L10.4 4.6 M12 2.2 L12.2 3.8 M14.6 2.8 L13.8 4.4"; stroke: dryad.leafLight; line: 0.6 }
        // casting arm, a twig of a hand
        GearPath {
          d: "M15.6 10 Q18.4 " + (11 - dryad.lift) + " 20.4 " + (9.8 - dryad.lift) + " L20.8 " + (11.6 - dryad.lift) + " Q18.4 " + (13.2 - dryad.lift) + " 16.2 13.2 Z"
          fill: dryad.bark; line: 1
        }
        GearPath {
          d: "M20.6 " + (10.4 - dryad.lift) + " L22.6 " + (9.2 - dryad.lift) + " M20.8 " + (11 - dryad.lift) + " L23 " + (11 - dryad.lift)
          stroke: dryad.bark; line: 0.9
        }
        // sparks of green growth
        Repeater {
          model: root.lit ? 3 : 0
          Rectangle {
            required property int index
            readonly property real a: root.time * 2.4 + index * 2.1
            x: 22.4 + Math.cos(a) * 1.8 - width / 2; y: 10.4 - dryad.lift + Math.sin(a) * 1.8 - height / 2
            width: 1.6; height: 1.6; radius: 0.8
            color: dryad.spell; opacity: root.pulse
          }
        }
      }
    }

    // ================================================ witch (a caster, like the lich)
    Loader {
      anchors.fill: parent
      active: root.kind === "witch"
      sourceComponent: Item {
        id: witch
        anchors.fill: parent
        readonly property color robe: Qt.darker(root.pal.magenta || "#8a4dff", 2.4)
        readonly property color robeLight: Qt.darker(root.pal.magenta || "#8a4dff", 1.6)
        readonly property color skin: Qt.tint("#cfe8b0", Qt.rgba(0.3, 0.8, 0.3, 0.2))
        readonly property color spell: root.pal.bright_green || "#7dff6a"
        readonly property real lift: root.lit ? 2.6 + Math.sin(root.time * 5) * 0.8 : 0

        // a broom behind her
        GearPath { d: "M6.6 6 L3.4 20.6"; stroke: root.leather; line: 1.5 }
        GearPath { d: "M3.4 19.4 Q1 21.6 1.4 23.4 Q3.6 22.6 4.6 23.6 Q5.2 21.6 4.2 19.8 Z"; fill: root.gold; line: 0.8 }
        // robe with a ragged hem
        GearPath { d: "M12 7.4 Q16.6 7.8 17.4 11.4 L19.8 20.4 L18 21.8 L16.4 20.6 L14.6 22.2 L12.6 20.8 L10.6 22.2 L8.8 20.6 L7 21.8 L4.4 20.4 L6.6 11.4 Q7.4 7.8 12 7.4 Z"; fill: witch.robe }
        GearPath { d: "M9 13 L8.2 19.6 M15 13 L15.8 19.6"; stroke: witch.robeLight; line: 0.7 }
        // green face, crooked nose, a wicked grin
        GearPath { d: "M9.6 8.4 Q12 7.4 14.4 8.4 L14.2 11.4 Q12 12.6 9.8 11.4 Z"; fill: witch.skin; line: 0.8 }
        Rectangle { x: 10.3; y: 9; width: 1.1; height: 1.1; radius: 0.55; color: root.lit ? witch.spell : root.ink }
        Rectangle { x: 12.6; y: 9; width: 1.1; height: 1.1; radius: 0.55; color: root.lit ? witch.spell : root.ink }
        GearPath { d: "M12 9.6 L12.2 10.8 L11.5 10.9"; line: 0.6 }
        GearPath { d: "M10.8 11.2 Q12 11.9 13.2 11.1"; line: 0.5 }
        // hair spilling out, the pointed hat with a buckle, its tip flopping over
        GearPath { d: "M9.6 8.6 Q8.4 10.6 8.8 12.8 M14.4 8.6 Q15.6 10.6 15.2 12.8"; stroke: root.ink; line: 1 }
        GearPath { d: "M5.6 8.4 Q12 6 18.4 8.4 Q12 9.8 5.6 8.4 Z"; fill: witch.robe; line: 0.9 }
        GearPath { d: "M8.8 7.8 Q10.4 4.6 11.8 1.4 Q13.6 1.2 15.8 2.6 Q13.8 2.4 13.2 3.4 Q14 5.4 15.2 7.8 Z"; fill: witch.robe; line: 0.9 }
        GearPath { d: "M9.4 6.6 Q12 6 14.8 6.6 L14.9 7.6 Q12 7 9.2 7.6 Z"; fill: witch.robeLight; line: 0.5 }
        GearPath { d: "M11.2 6.3 L12.8 6.3 L12.8 7.4 L11.2 7.4 Z"; fill: root.gold; line: 0.5 }
        // casting arm, a bony green hand
        GearPath {
          d: "M15.4 12.4 Q18.4 " + (11.8 - witch.lift) + " 20.4 " + (10.4 - witch.lift) + " L21 " + (12.4 - witch.lift) + " Q18.6 " + (14.2 - witch.lift) + " 16 15.2 Z"
          fill: witch.robeLight; line: 1
        }
        GearPath {
          d: "M20.8 " + (10.8 - witch.lift) + " L22.6 " + (9.6 - witch.lift) + " M21 " + (11.4 - witch.lift) + " L23.2 " + (11.2 - witch.lift) + " M20.8 " + (12 - witch.lift) + " L22.4 " + (12.8 - witch.lift)
          stroke: witch.skin; line: 0.9
        }
        // a bubbling hex
        Rectangle {
          visible: root.lit
          x: 22.6 - width / 2; y: 10.8 - witch.lift - height / 2
          width: 3.4 + root.pulse * 1.6; height: width; radius: width / 2
          color: witch.spell; opacity: 0.55 * root.pulse
        }
        Rectangle {
          visible: root.lit
          x: 22 + Math.sin(root.time * 3) * 0.8; y: 7.4 - witch.lift - ((root.time * 3) % 3)
          width: 1.2; height: 1.2; radius: 0.6; color: witch.spell; opacity: 0.7
        }
      }
    }

    // ============================== slime (a caster: wands and staffs jutting out)
    Loader {
      anchors.fill: parent
      active: root.kind === "slimecaster"
      sourceComponent: Item {
        id: goo
        anchors.fill: parent
        readonly property color body: root.bar ? root.bar.slimeColor : (root.pal.green || "#5fd35f")
        readonly property color spell: root.pal.bright_cyan || root.pal.cyan || "#10ffd9"
        readonly property real squish: Math.sin(root.time * (root.lit ? 5 : 1.6)) * (root.lit ? 0.7 : 0.35)
        readonly property real glint: root.lit ? root.pulse : 0.35

        // wands and staffs swallowed at all angles, poking out
        GearPath { d: "M5.4 14 L1.4 4.2"; stroke: root.leather; line: 1.6 }
        Rectangle { x: 0.1; y: 2.6; width: 2.8; height: 2.8; radius: 1.4; color: root.crystal; border.color: root.ink; border.width: 0.6; opacity: 0.4 + 0.6 * goo.glint }
        GearPath { d: "M16.4 12 L21.8 3.6"; stroke: root.ink; line: 1.1 }
        GearPath { d: "M21.4 4.2 l0.4 -1.2 l0.4 1.2 l1.2 0.3 l-1.1 0.6 l0.1 1.2 l-0.8 -0.9 l-1.1 0.4 l0.5 -1.1 l-0.8 -0.9 Z"; fill: root.gold; line: 0.4 }
        GearPath { d: "M11.2 9.6 L10.4 1.6"; stroke: root.gold; line: 1.2 }
        Rectangle { x: 9.2; y: 0.4; width: 2.4; height: 2.4; radius: 1.2; color: root.flame; border.color: root.ink; border.width: 0.5; opacity: 0.4 + 0.6 * goo.glint }
        GearPath { d: "M19.2 17.6 L23.4 15.8"; stroke: root.leather; line: 1 }
        // the slime: a wobbling dome
        GearPath {
          d: "M2.6 21.8 Q2 14 6.4 10.6 Q12 " + (7.4 - goo.squish) + " 17.6 10.6 Q22 14 21.4 21.8 Q12 23.6 2.6 21.8 Z"
          fill: goo.body; line: 1.2
        }
        GearPath { d: "M6.4 13.4 Q8 11.4 10.4 11"; stroke: Qt.rgba(1, 1, 1, 0.75); line: 1 }   // sheen
        // eyes and a little mouth
        Rectangle { x: 8.2; y: 14.2; width: 2.4; height: 3; radius: 1.2; color: root.ink }
        Rectangle { x: 13.4; y: 14.2; width: 2.4; height: 3; radius: 1.2; color: root.ink }
        Rectangle { x: 8.8; y: 14.6; width: 0.9; height: 0.9; radius: 0.45; color: "white" }
        Rectangle { x: 14; y: 14.6; width: 0.9; height: 0.9; radius: 0.45; color: "white" }
        GearPath { d: root.lit ? "M10.6 18.6 Q12 20.4 13.4 18.6 Z" : "M10.8 18.8 Q12 19.6 13.2 18.8"; fill: root.lit ? root.ink : "transparent"; line: 0.6 }
        // sparks off the wand tips
        Rectangle {
          visible: root.lit
          x: 22 - width / 2; y: 3.6 - height / 2
          width: 3 + root.pulse * 1.4; height: width; radius: width / 2
          color: goo.spell; opacity: 0.55 * root.pulse
        }
      }
    }

    // ============================== wisp (a floating flame in a flowing energy field)
    Loader {
      anchors.fill: parent
      active: root.kind === "wisp"
      sourceComponent: Item {
        id: wisp
        anchors.fill: parent
        readonly property color core: root.pal.bright_cyan || root.pal.cyan || "#10ffd9"
        readonly property color field: root.pal.bright_blue || root.pal.blue || "#6695ff"
        readonly property real bob: Math.sin(root.time * 2) * 0.8
        readonly property real spin: root.time * (root.lit ? 2.6 : 0.8)
        readonly property real flick: Math.sin(root.time * 9) * 0.6

        // the energy field: two tilted rings flowing round it
        Repeater {
          model: 2
          Item {
            required property int index
            x: 12; y: 12.6 + wisp.bob
            rotation: (index ? -28 : 32) + Math.sin(root.time * 0.7 + index) * 8
            Repeater {
              model: 10
              Rectangle {
                required property int index
                readonly property real a: wisp.spin * (parent.index ? -1 : 1) + index * Math.PI / 5
                x: Math.cos(a) * 10 - width / 2
                y: Math.sin(a) * 3.4 - height / 2
                width: 1.4; height: 1.4; radius: 0.7
                color: parent.index ? wisp.core : wisp.field
                opacity: (0.45 + 0.4 * Math.sin(a)) * (root.lit ? 1 : 0.6)
              }
            }
          }
        }
        // the wisp: a teardrop of flame with a wavering tail
        GearPath {
          d: "M12 " + (4.6 + wisp.bob) + " Q" + (15.6 + wisp.flick) + " " + (10 + wisp.bob) + " 15.4 " + (14 + wisp.bob)
             + " Q15 " + (18.4 + wisp.bob) + " 12 " + (18.6 + wisp.bob) + " Q9 " + (18.4 + wisp.bob) + " 8.6 " + (14 + wisp.bob)
             + " Q" + (8.4 - wisp.flick) + " " + (10 + wisp.bob) + " 12 " + (4.6 + wisp.bob) + " Z"
          fill: Qt.rgba(wisp.core.r, wisp.core.g, wisp.core.b, 0.55)
          line: 1
        }
        GearPath {
          d: "M12 " + (8.6 + wisp.bob) + " Q14 " + (12 + wisp.bob) + " 13.6 " + (14.6 + wisp.bob) + " Q12 " + (16.6 + wisp.bob) + " 10.4 " + (14.6 + wisp.bob) + " Q10 " + (12 + wisp.bob) + " 12 " + (8.6 + wisp.bob) + " Z"
          fill: "white"; stroke: "transparent"; line: 0
          opacity: root.lit ? root.pulse : 0.7
        }
        Rectangle { x: 10.6; y: 12.6 + wisp.bob; width: 1; height: 1.4; radius: 0.5; color: root.ink }
        Rectangle { x: 12.4; y: 12.6 + wisp.bob; width: 1; height: 1.4; radius: 0.5; color: root.ink }
      }
    }

    // ============== town crier (system update): lit = updates! bell ringing, yelling
    Loader {
      anchors.fill: parent
      active: root.kind === "crier"
      sourceComponent: Item {
        id: crier
        anchors.fill: parent
        readonly property color coat: root.pal.red || "#c0392b"
        readonly property color skin: "#f2c2a0"
        readonly property real ring: root.lit ? Math.sin(root.time * 14) * 22 : 0
        // body in a red coat with gold buttons
        GearPath { d: "M12 9 Q16.6 9.4 17 13 L18.6 22 Q12 23.2 5.4 22 L7 13 Q7.4 9.4 12 9 Z"; fill: crier.coat }
        GearPath { d: "M12 11 L12 21.6"; stroke: Qt.darker(crier.coat, 1.4); line: 0.7 }
        Rectangle { x: 12.8; y: 13; width: 1; height: 1; radius: 0.5; color: root.gold }
        Rectangle { x: 12.8; y: 16; width: 1; height: 1; radius: 0.5; color: root.gold }
        // head, and a tricorn hat
        GearPath { d: "M9.6 5.4 Q12 4.2 14.4 5.4 L14.2 8.8 Q12 10.2 9.8 8.8 Z"; fill: crier.skin; line: 0.8 }
        Rectangle { x: 10.4; y: 6.2; width: 1; height: 1; radius: 0.5; color: root.ink }
        Rectangle { x: 12.6; y: 6.2; width: 1; height: 1; radius: 0.5; color: root.ink }
        // mouth: shut, or wide open, yelling
        GearPath {
          d: root.lit ? "M11 8 Q12 10.2 13 8 Z" : "M11.2 8.2 L12.8 8.2"
          fill: root.lit ? root.ink : "transparent"; line: 0.6
        }
        GearPath { d: "M7.4 5.2 Q12 1.6 16.6 5.2 Q12 3.8 7.4 5.2 Z"; fill: root.ink; line: 0.8 }
        GearPath { d: "M8.6 4.6 L12 2 L15.4 4.6"; stroke: root.gold; line: 0.5 }
        // the bell, raised and swinging when there's news
        Item {
          x: 17; y: root.lit ? 3.4 : 10
          width: 6; height: 7
          rotation: crier.ring
          transformOrigin: Item.Top
          GearPath { d: "M3 0.4 L3 1.6"; stroke: root.leather; line: 1 }
          GearPath { d: "M0.6 5.6 Q0.8 1.6 3 1.6 Q5.2 1.6 5.4 5.6 Z"; fill: root.gold; line: 0.8 }
          Rectangle { x: 2.4; y: 5.4; width: 1.2; height: 1.2; radius: 0.6; color: root.ink }
        }
        GearPath { d: root.lit ? "M16 12 L19.6 6.4" : "M16 13 L18.4 12"; stroke: crier.coat; line: 1.6 }
        // his cry: sound lines out of the open mouth
        GearPath {
          visible: root.lit
          d: "M3.6 6 Q2.4 7.4 3.6 8.8 M2 5 Q0.2 7.4 2 9.8"
          stroke: root.ink; line: 0.7
          opacity: root.pulse
        }
      }
    }

    // ============== bard (system update): lit = strumming, notes flying
    Loader {
      anchors.fill: parent
      active: root.kind === "bard"
      sourceComponent: Item {
        id: bard
        anchors.fill: parent
        readonly property color tunic: root.pal.green || "#3fb950"
        readonly property color skin: "#f2c2a0"
        readonly property real strum: root.lit ? Math.sin(root.time * 12) * 1.2 : 0
        GearPath { d: "M12 9 Q16.4 9.4 16.8 13 L18.2 22 Q12 23.2 5.8 22 L7.2 13 Q7.6 9.4 12 9 Z"; fill: bard.tunic }
        GearPath { d: "M9.6 5.4 Q12 4.2 14.4 5.4 L14.2 8.8 Q12 10.2 9.8 8.8 Z"; fill: bard.skin; line: 0.8 }
        Rectangle { x: 10.4; y: 6.2; width: 1; height: 1; radius: 0.5; color: root.ink }
        Rectangle { x: 12.6; y: 6.2; width: 1; height: 1; radius: 0.5; color: root.ink }
        GearPath { d: root.lit ? "M11 8.1 Q12 9.4 13 8.1 Z" : "M11.2 8.1 Q12 8.7 12.8 8.1"; fill: root.lit ? root.ink : "transparent"; line: 0.6 }
        // a floppy hat with a feather
        GearPath { d: "M8.2 5.6 Q9.4 2.2 13.4 2.6 Q16.4 3.2 16.2 5.8 Q12 4.4 8.2 5.6 Z"; fill: root.pal.red || "#c0392b"; line: 0.8 }
        GearPath { d: "M15.4 3.6 Q19.4 0.6 20.6 1.4 Q18.4 2.6 16 4.6"; fill: root.paper; line: 0.6 }
        // the lute across him
        GearPath { d: "M6.2 18.6 Q4.8 14.4 8.4 13.4 Q11.8 12.8 12.4 16 Q12.8 19.8 8.6 20 Q6.8 20 6.2 18.6 Z"; fill: root.leather; line: 0.9 }
        Rectangle { x: 8.4; y: 16; width: 1.8; height: 1.8; radius: 0.9; color: root.ink }
        GearPath { d: "M11.6 14.4 L19 8.6"; stroke: Qt.darker(root.leather, 1.3); line: 1.2 }
        GearPath { d: "M18.6 8.2 L20.4 7.2 L20 9.2 Z"; fill: Qt.darker(root.leather, 1.3); line: 0.5 }
        // strumming hand
        Rectangle { x: 10 + bard.strum; y: 15.8; width: 2.2; height: 2.2; radius: 1.1; color: bard.skin; border.color: root.ink; border.width: 0.5 }
        // notes drifting up
        Repeater {
          model: root.lit ? 2 : 0
          Text {
            required property int index
            readonly property real ph: (root.time * 0.8 + index * 0.5) % 1
            x: 17 + index * 3 + Math.sin(root.time * 3 + index) * 1.2; y: 10 - ph * 9
            text: index ? "♫" : "♪"
            font.pixelSize: 5
            color: root.ink
            opacity: 1 - ph
          }
        }
      }
    }

    // ============== knight (system update): lit = kneeling, sword planted
    Loader {
      anchors.fill: parent
      active: root.kind === "knight"
      sourceComponent: Item {
        id: kn
        anchors.fill: parent
        readonly property color steel: Qt.tint(root.paper, Qt.rgba(0.35, 0.4, 0.5, 0.5))
        property real k: root.lit ? 1 : 0
        Behavior on k { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }
        Item {
          anchors.fill: parent
          // kneeling lowers him
          transform: Translate { y: kn.k * 3.2 }
          // body in armour with a tabard
          GearPath { d: "M12 9.4 Q16 9.6 16.4 13 L17 " + (19 - kn.k * 2) + " L7 " + (19 - kn.k * 2) + " L7.6 13 Q8 9.6 12 9.4 Z"; fill: kn.steel }
          GearPath { d: "M10.4 11 L13.6 11 L13.2 " + (18.4 - kn.k * 2) + " L10.8 " + (18.4 - kn.k * 2) + " Z"; fill: root.pal.blue || "#3f74ff"; line: 0.6 }
          // legs: standing, or one knee down
          GearPath { d: kn.k > 0.5 ? "M8 17 L7.4 20.4 L10.6 20.4 M14 17 L17 17.6 L17.4 20.4" : "M9 19 L8.8 22.4 M15 19 L15.2 22.4"; stroke: root.ink; line: 1.8 }
          // helmet with a plume
          GearPath { d: "M8.8 5.6 Q12 2.2 15.2 5.6 L15 9.6 L9 9.6 Z"; fill: kn.steel; line: 0.9 }
          GearPath { d: "M9.6 7 L14.4 7"; stroke: root.ink; line: 0.9 }
          GearPath { d: "M12 3.4 Q15 0.6 17.2 2.2 Q14.4 2 12.6 4"; fill: root.pal.red || "#c0392b"; line: 0.6 }
        }
        // the sword: at his side, or planted point-down before him
        GearPath { d: kn.k > 0.5 ? "M19.4 10 L19.4 22.6 M17.6 12 L21.2 12" : "M18.4 9 L21 20.4 M17 11.6 L20.2 10.8"; stroke: root.ink; line: 1.1 }
        GearPath { d: kn.k > 0.5 ? "M19.4 12.6 L19.4 22.4" : "M18.9 11.4 L20.9 20.2"; stroke: kn.steel; line: 0.6 }
      }
    }

    // ============== jester (system update): lit = juggling
    Loader {
      anchors.fill: parent
      active: root.kind === "jester"
      sourceComponent: Item {
        id: jest
        anchors.fill: parent
        readonly property color a: root.pal.magenta || "#c21e8b"
        readonly property color b: root.pal.yellow || "#e4cc00"
        readonly property color skin: "#f2c2a0"
        // harlequin body
        GearPath { d: "M12 9.6 L12 22.4 Q6 22.8 5.6 22 L7 13 Q7.4 9.8 12 9.6 Z"; fill: jest.a }
        GearPath { d: "M12 9.6 Q16.6 9.8 17 13 L18.4 22 Q18 22.8 12 22.4 Z"; fill: jest.b }
        GearPath { d: "M9.6 6.4 Q12 5.2 14.4 6.4 L14.2 9.4 Q12 10.6 9.8 9.4 Z"; fill: jest.skin; line: 0.8 }
        Rectangle { x: 10.4; y: 7; width: 1; height: 1; radius: 0.5; color: root.ink }
        Rectangle { x: 12.6; y: 7; width: 1; height: 1; radius: 0.5; color: root.ink }
        GearPath { d: "M10.8 8.6 Q12 9.8 13.2 8.6"; line: 0.6 }
        // the three-pointed cap with bells
        GearPath { d: "M9 6.6 Q6.4 3 4.6 4.8 Q8 4.4 9.6 6 Z"; fill: jest.a; line: 0.7 }
        GearPath { d: "M10.6 6 Q12 0.8 13.4 6 Z"; fill: jest.b; line: 0.7 }
        GearPath { d: "M15 6.6 Q17.6 3 19.4 4.8 Q16 4.4 14.4 6 Z"; fill: jest.a; line: 0.7 }
        Rectangle { x: 4; y: 4.2; width: 1.4; height: 1.4; radius: 0.7; color: root.gold; border.color: root.ink; border.width: 0.4 }
        Rectangle { x: 11.3; y: 0.3; width: 1.4; height: 1.4; radius: 0.7; color: root.gold; border.color: root.ink; border.width: 0.4 }
        Rectangle { x: 18.8; y: 4.2; width: 1.4; height: 1.4; radius: 0.7; color: root.gold; border.color: root.ink; border.width: 0.4 }
        // arms: at his sides, or up juggling; hands as little skin circles
        GearPath { d: root.lit ? "M8 12.6 Q5.4 11 4.6 8.4" : "M7.8 12.6 Q6.4 15 6.8 17.4"; stroke: jest.a; line: 1.8 }
        GearPath { d: root.lit ? "M16 12.6 Q18.6 11 19.4 8.4" : "M16.2 12.6 Q17.6 15 17.2 17.4"; stroke: jest.b; line: 1.8 }
        GearPath { d: root.lit ? "M3.6 8.4 a1 1 0 1 0 2 0 a1 1 0 1 0 -2 0 M18.4 8.4 a1 1 0 1 0 2 0 a1 1 0 1 0 -2 0"
                               : "M5.8 17.8 a1 1 0 1 0 2 0 a1 1 0 1 0 -2 0 M16.2 17.8 a1 1 0 1 0 2 0 a1 1 0 1 0 -2 0"
                   fill: jest.skin; line: 0.6 }
        // three balls arcing over his head
        Repeater {
          model: root.lit ? 3 : 0
          GearPath {
            required property int index
            readonly property real ph: root.time * 2.6 + index * 2.094
            readonly property real bx: 12 + Math.cos(ph) * 7.4
            readonly property real by: 4.6 - Math.abs(Math.sin(ph)) * 4.2
            d: "M" + (bx - 1.5) + " " + by + " a1.5 1.5 0 1 0 3 0 a1.5 1.5 0 1 0 -3 0"
            fill: [root.pal.red || "#e33", root.pal.cyan || "#1cc", root.pal.green || "#3c3"][index]
            line: 0.6
          }
        }
      }
    }

    // ============== a slime that emotes (system update): lit = shocked, "!"
    Loader {
      anchors.fill: parent
      active: root.kind === "emoteslime"
      sourceComponent: Item {
        id: es
        anchors.fill: parent
        readonly property color body: root.bar ? root.bar.slimeColor : (root.pal.green || "#5fd35f")
        readonly property real hop: root.lit ? Math.abs(Math.sin(root.time * 6)) * 2.4 : 0
        Item {
          anchors.fill: parent
          transform: Translate { y: -es.hop }
          GearPath { d: "M3.4 21.8 Q2.8 14.4 7 11 Q12 8.2 17 11 Q21.2 14.4 20.6 21.8 Q12 23.4 3.4 21.8 Z"; fill: es.body; line: 1.2 }
          GearPath { d: "M6.8 13.6 Q8.2 11.8 10.4 11.4"; stroke: Qt.rgba(1, 1, 1, 0.75); line: 1 }
          // eyes: sleepy, or wide
          Rectangle { x: 8; y: root.lit ? 13.6 : 15.6; width: 2.6; height: root.lit ? 3.4 : 1.2; radius: 1.2; color: root.ink }
          Rectangle { x: 13.4; y: root.lit ? 13.6 : 15.6; width: 2.6; height: root.lit ? 3.4 : 1.2; radius: 1.2; color: root.ink }
          GearPath { d: root.lit ? "M11 18.4 Q12 20.4 13 18.4 Q12 17.6 11 18.4 Z" : "M10.8 18.6 Q12 19.4 13.2 18.6"; fill: root.lit ? root.ink : "transparent"; line: 0.6 }
        }
        // the emote
        Text {
          visible: root.lit
          x: 16.4; y: 1 - es.hop
          text: "!"
          color: root.pal.red || "#e33"
          font.pixelSize: 8; font.bold: true
          style: Text.Outline; styleColor: root.ink
        }
      }
    }

    // ============== tray: a slime stuffed with treasure (open = mouth wide, loot spilling)
    Loader {
      anchors.fill: parent
      active: root.kind === "treasureslime"
      sourceComponent: Item {
        id: ts
        anchors.fill: parent
        property real o: root.open ? 1 : 0
        Behavior on o { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
        readonly property color body: root.bar ? root.bar.slimeColor : (root.pal.green || "#5fd35f")
        // coins and a gem glinting inside the goo
        GearPath { d: "M3.4 21.8 Q2.8 13.8 7 10.4 Q12 " + (7.6 - ts.o * 1.4) + " 17 10.4 Q21.2 13.8 20.6 21.8 Q12 23.4 3.4 21.8 Z"; fill: Qt.rgba(ts.body.r, ts.body.g, ts.body.b, 0.8); line: 1.2 }
        Rectangle { x: 6; y: 17.6; width: 3.4; height: 1.6; radius: 0.8; color: root.gold; border.color: root.ink; border.width: 0.4 }
        Rectangle { x: 14.6; y: 18.4; width: 3.4; height: 1.6; radius: 0.8; color: root.gold; border.color: root.ink; border.width: 0.4 }
        GearPath { d: "M11 16.6 L12.6 15.2 L14.2 16.6 L12.6 18.8 Z"; fill: root.pal.bright_cyan || "#10ffd9"; line: 0.5 }
        GearPath { d: "M6.8 13.2 Q8.2 11.4 10.4 11"; stroke: Qt.rgba(1, 1, 1, 0.75); line: 1 }
        Rectangle { x: 8.4; y: 12.6; width: 1.8; height: 2.4; radius: 0.9; color: root.ink }
        Rectangle { x: 13.8; y: 12.6; width: 1.8; height: 2.4; radius: 0.9; color: root.ink }
        // mouth: a smile, or wide open with coins popping out
        GearPath { d: ts.o > 0.3 ? "M10 16 Q12 " + (16 + ts.o * 3) + " 14 16 Z" : "M10.4 16.2 Q12 17.2 13.6 16.2"; fill: ts.o > 0.3 ? root.ink : "transparent"; line: 0.7 }
        Repeater {
          model: ts.o > 0.05 ? 3 : 0
          Rectangle {
            required property int index
            x: 12 + (index - 1) * 3.2 * ts.o - 1.1; y: 14 - ts.o * (4 + index % 2 * 2.4)
            width: 2.2; height: 2.2; radius: 1.1
            color: root.gold; border.color: root.ink; border.width: 0.4
            opacity: ts.o
          }
        }
      }
    }

    // ============== tray: a pack mule with bags of loot (open = bags open, ears up)
    Loader {
      anchors.fill: parent
      active: root.kind === "mule"
      sourceComponent: Item {
        id: mule
        anchors.fill: parent
        property real o: root.open ? 1 : 0
        Behavior on o { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
        readonly property color coat: Qt.tint(root.leather, Qt.rgba(0.6, 0.6, 0.62, 0.45))
        // legs, body, neck and head
        GearPath { d: "M6 17 L5.6 22 M9 17 L9 22 M15 17 L15 22 M18 17 L18.4 22"; stroke: root.ink; line: 1.5 }
        GearPath { d: "M4 12 Q4 9.4 7 9.4 L17 9.4 Q19.6 9.4 19.6 12.4 L19.6 16 Q19.6 17.6 18 17.6 L5.6 17.6 Q4 17.6 4 16 Z"; fill: mule.coat }
        GearPath { d: "M17.6 10.4 L20.6 6 Q22.8 5.4 23.4 7.4 L22.6 10 Q21.6 11 20.4 11 Z"; fill: mule.coat; line: 1 }
        Rectangle { x: 21.4; y: 7.2; width: 0.9; height: 0.9; radius: 0.45; color: root.ink }
        // long ears: back, or pricked up
        GearPath { d: "M20.6 6.2 L" + (20 - 1.6 * (1 - mule.o)) + " " + (1.6 + 1.6 * (1 - mule.o)) + " L21.4 5.6 Z"; fill: mule.coat; line: 0.8 }
        GearPath { d: "M3.6 11 Q1.6 12 1.8 15"; stroke: root.ink; line: 0.9 }
        // saddlebags, flaps lifting as it opens, loot peeking out
        GearPath { d: "M6 9.6 L11 9.6 L11 15.4 Q8.5 16.4 6 15.4 Z"; fill: root.leather; line: 1 }
        GearPath { d: "M12.4 9.6 L17.4 9.6 L17.4 15.4 Q14.9 16.4 12.4 15.4 Z"; fill: root.leather; line: 1 }
        GearPath { d: "M6 9.6 L11 9.6 L11 " + (12 - mule.o * 3.4) + " Q8.5 " + (12.8 - mule.o * 3.4) + " 6 " + (12 - mule.o * 3.4) + " Z"; fill: root.leatherLight; line: 0.8 }
        GearPath { d: "M12.4 9.6 L17.4 9.6 L17.4 " + (12 - mule.o * 3.4) + " Q14.9 " + (12.8 - mule.o * 3.4) + " 12.4 " + (12 - mule.o * 3.4) + " Z"; fill: root.leatherLight; line: 0.8 }
        GearPath { visible: mule.o > 0.3; d: "M7 9.4 L8 7.2 L9.2 9.4 M13.4 9.4 L14.6 6.8 L15.8 9.4"; stroke: root.gold; line: 1.1 }
      }
    }

    // ============== tray: a goblin hauling a huge sack of gold (open = sack opens, gold glints)
    Loader {
      anchors.fill: parent
      active: root.kind === "goblinsack"
      sourceComponent: Item {
        id: gob
        anchors.fill: parent
        property real o: root.open ? 1 : 0
        Behavior on o { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
        readonly property color skin: root.pal.green || "#5fb34f"
        // the sack, bigger than him, over his shoulder
        GearPath { d: "M8.6 3.8 Q15.8 1.4 20.8 6.2 Q23.6 12.4 19.6 16.4 Q13.6 18.6 10.4 14 Q7.4 9.4 8.6 3.8 Z"; fill: Qt.tint(root.leather, Qt.rgba(1, 0.9, 0.7, 0.35)) }
        GearPath { d: "M9.4 5.2 Q" + (7 - gob.o * 2) + " " + (2.6 - gob.o * 1.4) + " 10.8 2.6"; stroke: root.ink; line: 1 }
        GearPath { visible: gob.o > 0.2; d: "M9.6 3.6 Q12 1.4 14.4 2.6 Q12.4 4 9.6 3.6 Z"; fill: root.gold; line: 0.6 }
        Rectangle { visible: gob.o > 0.2; x: 11.6; y: 0.6 - gob.o; width: 1.2; height: 1.2; radius: 0.6; color: "white"; opacity: root.pulse * gob.o }
        GearPath { d: "M15.4 10 L16.6 9 L17.8 10.2 L16.6 11.4 Z"; fill: root.gold; line: 0.4 }
        // the goblin, bent under it
        GearPath { d: "M5.4 13.6 Q9 12.6 10.4 15.4 L10.8 20.4 L4.6 20.4 Z"; fill: root.leather; line: 1 }
        GearPath { d: "M5.6 20.4 L4.8 23 M9.6 20.4 L10.6 23"; stroke: root.ink; line: 1.4 }
        GearPath { d: "M3.2 10.2 Q5.8 8.2 8 10.4 L7.6 13.2 Q5.4 14.4 3.6 13 Z"; fill: gob.skin; line: 0.9 }
        GearPath { d: "M3.4 10.6 L0.6 9.4 L3 11.8 M7.8 10.4 L9.6 8.6 L8.2 11.2"; fill: gob.skin; line: 0.7 }
        Rectangle { x: 4.2; y: 10.8; width: 1; height: 1; radius: 0.5; color: root.flame }
        Rectangle { x: 6.2; y: 10.8; width: 1; height: 1; radius: 0.5; color: root.flame }
        GearPath { d: "M4.6 12.6 L5.2 13 L5.8 12.6 L6.4 13"; line: 0.5 }
        GearPath { d: "M8 13 Q9.6 11.4 10.2 10"; stroke: gob.skin; line: 1.4 }
      }
    }

    // ============== tray: a knight on horseback (open = rearing, lance raised)
    Loader {
      anchors.fill: parent
      active: root.kind === "horseknight"
      sourceComponent: Item {
        id: hk
        anchors.fill: parent
        property real o: root.open ? 1 : 0
        Behavior on o { NumberAnimation { duration: 360; easing.type: Easing.OutBack } }
        readonly property color horse: Qt.tint(root.paper, Qt.rgba(0.55, 0.4, 0.25, 0.55))
        readonly property color steel: Qt.tint(root.paper, Qt.rgba(0.35, 0.4, 0.5, 0.5))
        Item {
          anchors.fill: parent
          rotation: -12 * hk.o
          transformOrigin: Item.BottomLeft
          // horse: legs, body, neck and head, with a caparison
          GearPath { d: "M6 17.4 L5.4 22 M9 17.4 L9.4 22 M15.6 17.4 L16 22 M18.4 17.4 L19 22"; stroke: root.ink; line: 1.4 }
          GearPath { d: "M4.4 13.6 Q4.4 11.2 7 11.2 L17.4 11.2 Q20 11.2 20 13.8 L20 16.4 Q20 18 18.4 18 L6 18 Q4.4 18 4.4 16.4 Z"; fill: hk.horse }
          GearPath { d: "M18 12 L20.4 7.2 Q22.8 6.2 23.6 8.4 L22.8 10.6 Q21.4 11.8 20.4 12 Z"; fill: hk.horse; line: 1 }
          Rectangle { x: 21.6; y: 8.2; width: 0.9; height: 0.9; radius: 0.45; color: root.ink }
          GearPath { d: "M6.4 11.4 L17.4 11.4 L16.6 16.6 L7.2 16.6 Z"; fill: root.pal.blue || "#3f74ff"; line: 0.8 }
          GearPath { d: "M8.4 16.6 L9.4 15 L10.4 16.6 L11.4 15 L12.4 16.6 L13.4 15 L14.4 16.6"; stroke: root.gold; line: 0.7 }
          // the knight: body, helm with a plume, shield
          GearPath { d: "M9.6 11.4 L10 6.8 Q12 5.6 14 6.8 L14.2 11.4 Z"; fill: hk.steel; line: 0.9 }
          GearPath { d: "M10.4 6.4 Q12 2.2 13.6 6.4 Z"; fill: hk.steel; line: 0.8 }
          GearPath { d: "M10.8 4.8 L13.2 4.8"; line: 0.7 }
          GearPath { d: "M12 2.8 Q14.6 0.4 16.4 1.6 Q13.8 1.8 12.4 3.4"; fill: root.pal.red || "#c0392b"; line: 0.5 }
          GearPath { d: "M8.6 8 L11 8 L11 10.6 Q9.8 11.8 8.6 10.6 Z"; fill: root.pal.red || "#c0392b"; line: 0.7 }
          // the lance: level, or raised with a pennant
          GearPath { d: hk.o > 0.5 ? "M14 9.4 L20.6 0.6" : "M14 9.6 L23.6 7.8"; stroke: root.leather; line: 1.1 }
          GearPath { visible: hk.o > 0.5; d: "M20.2 1.2 L22.8 1.6 L20.8 3 Z"; fill: root.gold; line: 0.5 }
        }
      }
    }

    // ============== tray: a mimic chest (open = the lid gapes, teeth and tongue)
    Loader {
      anchors.fill: parent
      active: root.kind === "mimic"
      sourceComponent: Item {
        id: mim
        anchors.fill: parent
        property real o: root.open ? 1 : 0
        Behavior on o { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
        // box
        GearPath { d: "M3.4 12.6 L20.6 12.6 L20.6 20.6 Q20.6 21.8 19.4 21.8 L4.6 21.8 Q3.4 21.8 3.4 20.6 Z"; fill: root.leather }
        GearPath { d: "M3.4 16.4 L20.6 16.4 M8 12.6 L8 21.8 M16 12.6 L16 21.8"; stroke: Qt.darker(root.leather, 1.4); line: 0.8 }
        // mouth: dark inside, lower teeth, a lolling tongue
        GearPath { visible: mim.o > 0.1; d: "M4 12.8 L20 12.8 L20 " + (12.8 - mim.o * 5) + " L4 " + (12.8 - mim.o * 5) + " Z"; fill: Qt.darker(root.blood, 2.2); line: 0 ; stroke: "transparent" }
        GearPath { visible: mim.o > 0.3; d: "M5 12.6 L6 10.8 L7 12.6 L8 10.8 L9 12.6 L10 10.8 L11 12.6 L13 12.6 L14 10.8 L15 12.6 L16 10.8 L17 12.6 L18 10.8 L19 12.6"; fill: root.paper; line: 0.5 }
        GearPath { visible: mim.o > 0.5; d: "M11 12.4 Q12.4 " + (14 + mim.o * 5) + " 15.6 " + (13.6 + mim.o * 4) + " Q14.6 12.6 13 12.4 Z"; fill: root.blood; line: 0.6 }
        // lid, hinged at the back, with upper teeth and an eye
        Item {
          anchors.fill: parent
          rotation: -32 * mim.o
          transform: Translate { x: 0 }
          transformOrigin: Item.Left
          GearPath { d: "M3 12.6 Q3 7.4 12 7.4 Q21 7.4 21 12.6 Z"; fill: root.leatherLight }
          GearPath { visible: mim.o > 0.3; d: "M5 12.6 L6 14.2 L7 12.6 L8 14.2 L9 12.6 L15 12.6 L16 14.2 L17 12.6 L18 14.2 L19 12.6"; fill: root.paper; line: 0.5 }
          Rectangle { x: 10.4; y: 8.8; width: 3.2; height: 2.4; radius: 1.2; color: mim.o > 0.2 ? root.flame : root.gold; border.color: root.ink; border.width: 0.7 }
          Rectangle { visible: mim.o > 0.2; x: 11.6; y: 9.3; width: 0.9; height: 1.4; radius: 0.45; color: root.ink }
        }
      }
    }

    // ============== tray: a bubbling cauldron (open = lid lifts, bubbles and steam)
    Loader {
      anchors.fill: parent
      active: root.kind === "cauldron"
      sourceComponent: Item {
        id: cau
        anchors.fill: parent
        property real o: root.open ? 1 : 0
        Behavior on o { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
        readonly property color brew: root.pal.bright_green || "#7dff6a"
        GearPath { d: "M5 22 L6.4 20 M19 22 L17.6 20"; stroke: root.ink; line: 1.4 }
        GearPath { d: "M3.6 12 L20.4 12 Q21.4 21 12 21.4 Q2.6 21 3.6 12 Z"; fill: Qt.darker(root.stone, 1.6) }
        GearPath { d: "M3 11.4 L21 11.4 L21 12.8 L3 12.8 Z"; fill: Qt.darker(root.stone, 1.3); line: 1 }
        // the brew, and bubbles rising once the lid's off
        GearPath { d: "M4 12.2 Q12 " + (10.6 - cau.o) + " 20 12.2 Z"; fill: cau.brew; line: 0.6 }
        Repeater {
          model: cau.o > 0.2 ? 3 : 0
          Rectangle {
            required property int index
            readonly property real ph: (root.time * 0.9 + index * 0.33) % 1
            x: 8 + index * 3.6; y: 10 - ph * 8
            width: 2 - ph; height: width; radius: width / 2
            color: cau.brew; border.color: root.ink; border.width: 0.4
            opacity: (1 - ph) * cau.o
          }
        }
        // the lid, lifted and tipped
        Item {
          anchors.fill: parent
          transform: [ Rotation { origin.x: 20; origin.y: 11; angle: 28 * cau.o }, Translate { y: -3 * cau.o } ]
          GearPath { d: "M4.6 11.2 Q12 7.6 19.4 11.2 Z"; fill: Qt.darker(root.stone, 1.3); line: 1 }
          Rectangle { x: 11; y: 7.6; width: 2; height: 1.6; radius: 0.8; color: Qt.darker(root.stone, 1.6); border.color: root.ink; border.width: 0.6 }
        }
      }
    }

    // ============== power: a glass jar of glowing slime. level = how full
    // (the battery); lit = charging (a bolt, bubbles rising); state3 "mains" =
    // no battery: full, with a cord plugged into the lid
    Loader {
      anchors.fill: parent
      active: root.kind === "energyjar"
      sourceComponent: Item {
        id: jar
        anchors.fill: parent
        readonly property bool mains: root.state3 === "mains"
        readonly property real lv: mains ? 1 : Math.max(0, Math.min(1, root.level))
        readonly property color goo: lv < 0.2 && !mains ? (root.pal.red || "#ff1720")
                                   : lv < 0.4 && !mains ? (root.pal.yellow || "#d9b800")
                                   : (root.bar ? root.bar.slimeColor : (root.pal.green || "#1be33a"))
        readonly property real surf: 21 - 13.4 * lv
        // the cord, curling off the lid (mains)
        GearPath { visible: jar.mains; d: "M14.4 4 Q18 1.6 20.2 4.4 Q22.4 7.6 20.8 12"; stroke: root.ink; line: 1.1 }
        Rectangle { visible: jar.mains; x: 19.6; y: 11.4; width: 2.6; height: 3; radius: 0.6; color: root.gold; border.color: root.ink; border.width: 0.6 }
        // the slime inside, its surface wobbling
        GearPath {
          visible: jar.lv > 0.02
          d: "M6.4 " + jar.surf + " Q9 " + (jar.surf - 0.9 + Math.sin(root.time * 2) * 0.6) + " 12 " + jar.surf
             + " Q15 " + (jar.surf + 0.9 - Math.sin(root.time * 2) * 0.6) + " 17.6 " + jar.surf + " L17.6 20.2 Q17.6 21.2 16.6 21.2 L7.4 21.2 Q6.4 21.2 6.4 20.2 Z"
          fill: jar.goo; stroke: "transparent"; line: 0
        }
        // bubbles while charging
        Repeater {
          model: root.lit ? 3 : 0
          Rectangle {
            required property int index
            readonly property real ph: (root.time * 0.8 + index * 0.33) % 1
            x: 8.6 + index * 2.8; y: 20 - ph * (20 - jar.surf - 1)
            width: 1.4; height: 1.4; radius: 0.7
            color: Qt.rgba(1, 1, 1, 0.8); opacity: 1 - ph
          }
        }
        // the glass: a jar with a shine, and a cork lid
        GearPath { d: "M6 7 L18 7 L18 20.2 Q18 21.8 16.4 21.8 L7.6 21.8 Q6 21.8 6 20.2 Z"; fill: Qt.rgba(1, 1, 1, 0.12); line: 1.2 }
        GearPath { d: "M8 9 L8 18"; stroke: Qt.rgba(1, 1, 1, 0.7); line: 1 }
        GearPath { d: "M7.4 3.6 L16.6 3.6 L16.2 7 L7.8 7 Z"; fill: root.leather; line: 1 }
        // a bolt on the glass while charging
        GearPath {
          visible: root.lit
          d: "M13 9.4 L10.2 14.4 L12.2 14.4 L11 18.6 L14.4 13 L12.4 13 Z"
          fill: root.flame; line: 0.6
          opacity: 0.6 + 0.4 * root.pulse
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
