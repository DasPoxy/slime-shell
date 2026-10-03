import QtQuick
import QtQuick.Shapes
import "../slime.bar/ui"

// The launcher's backdrop: a castle the slime has swallowed (as the tavern
// is Slime-Tasks'). Walls, towers and a gate sunk under a film of goo; the
// top of it broken off, with blocks of stone drifting away up into the slime;
// and the castle's people (knights and a horse, the king, queen and princess,
// the jester) and its monsters (goblins, skeletons, slimes, a witch, a lich)
// adrift in it. Faint, so the results over it stay easy to read.
Item {
  id: scene

  required property var bar
  readonly property real t: bar ? bar.animTime : 0
  readonly property color ink: bar ? bar.slimeInk : "black"
  readonly property color goo: bar ? bar.slimeColor : "green"
  readonly property color paper: bar ? bar.paperColor : "white"
  readonly property var pal: bar && bar.slimePalette ? bar.slimePalette : ({})
  readonly property color stone: Qt.tint(paper, Qt.rgba(ink.r, ink.g, ink.b, 0.45))
  readonly property color stoneDark: Qt.darker(stone, 1.25)
  readonly property color roof: pal.blue || "#3f74ff"
  readonly property color banner: pal.red || "#ff1720"

  component StonePath: Shape {
    id: sp
    property string d: ""
    property color fill: scene.stone
    property real line: 1.4
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      fillColor: sp.fill
      strokeColor: scene.ink
      strokeWidth: sp.line
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: sp.d }
    }
  }

  // ---- the castle, deep in the goo ----
  Item {
    id: castle
    anchors.fill: parent
    opacity: 0.4
    readonly property real w: width
    readonly property real h: height
    readonly property real base: h * 0.97          // the ground line
    readonly property real wallTop: h * 0.56

    // the curtain wall, its top broken away into a ragged edge
    StonePath {
      d: {
        var w = castle.w, b = castle.base, top = castle.wallTop, out = "M 0 " + b + " L 0 " + (top + 18)
        // ragged, broken top: bites taken out of it
        for (var x = 0; x <= w; x += 22) {
          var n = Math.abs(Math.sin(x * 0.173) * 43758.5453) % 1
          out += " L " + x + " " + (top + n * 26 + (n > 0.7 ? 18 : 0))
        }
        return out + " L " + w + " " + b + " Z"
      }
    }
    // courses of stone
    Repeater {
      model: 7
      Rectangle {
        required property int index
        y: castle.base - (index + 1) * 16
        width: castle.w; height: 1.2
        color: scene.ink; opacity: 0.35
        visible: y > castle.wallTop + 20
      }
    }
    // the gate: an arch with a portcullis
    StonePath {
      readonly property real gx: castle.w * 0.5
      d: "M " + (gx - 30) + " " + castle.base + " L " + (gx - 30) + " " + (castle.base - 50)
         + " Q " + gx + " " + (castle.base - 86) + " " + (gx + 30) + " " + (castle.base - 50) + " L " + (gx + 30) + " " + castle.base + " Z"
      fill: scene.stoneDark
    }
    Repeater {
      model: 5
      Rectangle {
        required property int index
        x: castle.w * 0.5 - 22 + index * 11; y: castle.base - 70 + (index === 0 || index === 4 ? 14 : index === 2 ? -4 : 4)
        width: 1.6; height: castle.base - y
        color: scene.ink; opacity: 0.8
      }
    }
    // towers: two whole-ish at the sides, one sheared off in the middle
    Repeater {
      model: [[0.08, 0.26, true], [0.92, 0.3, true], [0.28, 0.42, false], [0.72, 0.38, false]]
      Item {
        required property var modelData
        readonly property real cx: modelData[0] * castle.w
        readonly property real tw: 58
        readonly property real towerTop: castle.h * modelData[1]
        readonly property bool whole: modelData[2]
        anchors.fill: parent
        StonePath {
          d: {
            var l = parent.cx - parent.tw / 2, r = parent.cx + parent.tw / 2, t = parent.towerTop, b = castle.base
            if (parent.whole) {
              // crenellated top
              var out = "M " + l + " " + b + " L " + l + " " + t
              for (var i = 0; i < 5; i++) {
                var x0 = l + i * parent.tw / 5, x1 = x0 + parent.tw / 10
                out += " L " + x0 + " " + (t - 10) + " L " + x1 + " " + (t - 10) + " L " + x1 + " " + t
              }
              return out + " L " + r + " " + t + " L " + r + " " + b + " Z"
            }
            // sheared off at a slant, jagged
            return "M " + l + " " + b + " L " + l + " " + (t + 12) + " L " + (l + 12) + " " + (t + 4) + " L " + (l + 22) + " " + (t + 16)
              + " L " + (l + 34) + " " + t + " L " + (l + 46) + " " + (t + 22) + " L " + r + " " + (t + 14) + " L " + r + " " + b + " Z"
          }
        }
        // arrow slits, and a window with a light
        Rectangle { x: parent.cx - 2; y: parent.towerTop + 30; width: 4; height: 14; radius: 2; color: scene.ink }
        Rectangle { x: parent.cx - 2; y: parent.towerTop + 70; width: 4; height: 14; radius: 2; color: scene.ink }
        // conical roof on the whole towers, with a banner flying
        StonePath {
          visible: parent.whole
          d: "M " + (parent.cx - parent.tw / 2 - 6) + " " + (parent.towerTop - 10) + " L " + parent.cx + " " + (parent.towerTop - 70) + " L " + (parent.cx + parent.tw / 2 + 6) + " " + (parent.towerTop - 10) + " Z"
          fill: scene.roof
        }
        StonePath {
          visible: parent.whole
          readonly property real flap: Math.sin(scene.t * 3 + parent.cx) * 4
          d: "M " + parent.cx + " " + (parent.towerTop - 70) + " L " + parent.cx + " " + (parent.towerTop - 92)
             + " M " + parent.cx + " " + (parent.towerTop - 92) + " Q " + (parent.cx + 12) + " " + (parent.towerTop - 92 + flap) + " " + (parent.cx + 22) + " " + (parent.towerTop - 86 + flap)
             + " Q " + (parent.cx + 12) + " " + (parent.towerTop - 82 - flap) + " " + parent.cx + " " + (parent.towerTop - 80) + " Z"
          fill: scene.banner; line: 1.2
        }
      }
    }
  }

  // ---- the broken-off top: blocks of stone drifting up into the slime ----
  Repeater {
    model: 11
    Rectangle {
      required property int index
      readonly property real rise: ((scene.t * (0.012 + (index % 4) * 0.004)) + index * 0.091) % 1
      readonly property real sz: 10 + (index * 7) % 14
      x: ((index * 0.379 + 0.06) % 1) * scene.width + Math.sin(rise * 6 + index) * 16
      y: scene.height * (0.52 - rise * 0.62)
      width: sz; height: sz * 0.7
      radius: 2
      rotation: rise * 160 * (index % 2 ? 1 : -1) + index * 20
      color: scene.stone
      border.color: scene.ink; border.width: 1.2
      opacity: 0.3 * Math.sin(Math.min(1, rise * 1.2) * Math.PI)
      Rectangle { x: parent.width * 0.5; width: 1; height: parent.height; color: scene.ink; opacity: 0.5 }
    }
  }

  // ---- the castle's people and monsters, adrift in the goo ----
  Repeater {
    model: [["king", 0.12, 0.14], ["queen", 0.34, 0.08], ["princess", 0.58, 0.16], ["knight", 0.84, 0.1],
            ["goblin", 0.22, 0.44], ["skeleton", 0.66, 0.4], ["goblin", 0.9, 0.52], ["skeleton", 0.06, 0.66]]
    SlimeCaptive {
      required property var modelData
      required property int index
      readonly property real tt: scene.t * 0.17 + index * 1.9
      x: modelData[1] * (scene.width - width) + Math.sin(tt) * 16
      y: modelData[2] * (scene.height - height) + Math.cos(tt * 0.8) * 10
      size: 30
      opacity: 0.42
      kind: modelData[0]
      time: scene.t * 0.4
      ink: scene.ink
      paper: scene.paper
      goo: scene.goo
      pal: scene.pal
    }
  }
  Repeater {
    model: [["jester", 0.46, 0.3, true], ["horseknight", 0.76, 0.26, true], ["lich", 0.04, 0.34, true],
            ["witch", 0.54, 0.56, true], ["slimecaster", 0.28, 0.62, false], ["emoteslime", 0.94, 0.72, false]]
    SlimeGear {
      required property var modelData
      required property int index
      readonly property real tt: scene.t * 0.2 + index * 2.3
      x: modelData[1] * (scene.width - width) + Math.sin(tt) * 14
      y: modelData[2] * (scene.height - height) + Math.cos(tt * 0.7) * 9
      rotation: Math.sin(tt * 0.6) * 14
      width: 34; height: 34; size: 34
      opacity: 0.42
      bar: scene.bar
      kind: modelData[0]
      lit: modelData[3]
      open: true
    }
  }

  // the goo the castle is sunk in: a film of slime, darker below, bubbles rising
  Rectangle {
    anchors.fill: parent
    radius: 14
    gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.rgba(scene.goo.r, scene.goo.g, scene.goo.b, 0.08) }
      GradientStop { position: 1.0; color: Qt.rgba(scene.goo.r * 0.55, scene.goo.g * 0.55, scene.goo.b * 0.55, 0.28) }
    }
  }
  Repeater {
    model: 8
    Rectangle {
      required property int index
      readonly property real rise: (scene.t * (0.04 + (index % 3) * 0.012) + index * 0.137) % 1
      x: ((index * 0.43 + 0.1) % 1) * scene.width + Math.sin(rise * 8 + index) * 6
      y: scene.height * (1 - rise)
      width: 5 + (index % 3) * 4; height: width; radius: width / 2
      color: "transparent"
      border.color: scene.paper; border.width: 1.2
      opacity: 0.45 * Math.sin(rise * Math.PI)
    }
  }
}
