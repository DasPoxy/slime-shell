import QtQuick
import QtQuick.Shapes

// A usage meter as a quest: a dirt road running to a dungeon mouth, with a
// little adventurer who has marched `fraction` of the way there (so a full
// disk is an adventurer at the dungeon door). The road they've walked is
// trodden dark. Label and value sit above the road, as with a plain meter.
Item {
  id: meter
  // the command centre's text size (Settings → Command centre → text size)
  readonly property real fs: cc && cc.fontScale ? cc.fontScale : 1

  required property var cc
  property string label: ""
  property string value: ""
  property real fraction: 0
  property string hero: "knight"    // knight, wizard, rogue

  readonly property real t: cc.bar ? cc.bar.animTime : 0
  readonly property color ink: cc.ink
  readonly property color paper: cc.paper
  readonly property var pal: cc.bar.slimePalette || ({})
  readonly property color dirt: Qt.tint(paper, Qt.rgba(0.55, 0.36, 0.2, 0.35))
  readonly property real roadY: 38
  readonly property real roadEnd: width - 30          // where the dungeon starts
  readonly property real shown: Math.max(0, Math.min(1, fraction))
  property real walked: shown
  Behavior on walked { NumberAnimation { duration: 900; easing.type: Easing.InOutQuad } }

  width: parent ? parent.width : 0
  height: 56

  Text {
    textFormat: Text.PlainText
    text: meter.label
    color: meter.ink
    font.family: meter.cc.font
    font.pixelSize: Math.round(12 * meter.fs)
    font.bold: true
  }
  Text {
    textFormat: Text.PlainText
    anchors.right: parent.right
    text: meter.value
    color: meter.ink
    font.family: meter.cc.font
    font.pixelSize: Math.round(12 * meter.fs)
    opacity: 0.85
  }

  // road, trodden part, and the dungeon mouth
  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {   // the road
      fillColor: meter.dirt
      strokeColor: meter.ink
      strokeWidth: 1.2
      PathSvg { path: "M 0 " + (meter.roadY - 3) + " L " + meter.roadEnd + " " + (meter.roadY - 4) + " L " + meter.roadEnd + " " + (meter.roadY + 6) + " L 0 " + (meter.roadY + 5) + " Z" }
    }
    ShapePath {   // trodden: footprints so far
      fillColor: "transparent"
      strokeColor: Qt.rgba(meter.ink.r, meter.ink.g, meter.ink.b, 0.7)
      strokeWidth: 2
      capStyle: ShapePath.RoundCap
      dashPattern: [1.5, 2.5]
      PathSvg { path: "M 2 " + (meter.roadY + 1) + " L " + Math.max(2, meter.walked * meter.roadEnd - 6) + " " + (meter.roadY + 1) }
    }
    ShapePath {   // dungeon: a rocky mound with a toothy dark doorway
      fillColor: Qt.tint(meter.paper, Qt.rgba(meter.ink.r, meter.ink.g, meter.ink.b, 0.4))
      strokeColor: meter.ink
      strokeWidth: 1.4
      joinStyle: ShapePath.RoundJoin
      PathSvg {
        path: {
          var x = meter.roadEnd - 6, y = meter.roadY + 6
          return "M " + x + " " + y + " L " + (x + 4) + " " + (y - 16) + " L " + (x + 12) + " " + (y - 24) + " L " + (x + 22) + " " + (y - 20)
            + " L " + (x + 30) + " " + (y - 26) + " L " + (x + 36) + " " + (y - 10) + " L " + (x + 36) + " " + y + " Z"
        }
      }
    }
    ShapePath {
      fillColor: meter.ink
      strokeColor: meter.ink
      strokeWidth: 1
      PathSvg {
        path: {
          var x = meter.roadEnd + 2, y = meter.roadY + 6
          return "M " + x + " " + y + " L " + x + " " + (y - 10) + " Q " + (x + 9) + " " + (y - 20) + " " + (x + 18) + " " + (y - 10) + " L " + (x + 18) + " " + y + " Z"
        }
      }
    }
    ShapePath {   // teeth round the doorway
      fillColor: meter.paper
      strokeColor: meter.ink
      strokeWidth: 0.6
      PathSvg {
        path: {
          var x = meter.roadEnd + 2, y = meter.roadY + 6
          return "M " + (x + 2) + " " + (y - 12) + " L " + (x + 4) + " " + (y - 8) + " L " + (x + 6) + " " + (y - 14) + " Z"
            + " M " + (x + 12) + " " + (y - 14) + " L " + (x + 14) + " " + (y - 8) + " L " + (x + 16) + " " + (y - 12) + " Z"
            + " M " + (x + 3) + " " + y + " L " + (x + 5) + " " + (y - 4) + " L " + (x + 7) + " " + y + " Z"
            + " M " + (x + 11) + " " + y + " L " + (x + 13) + " " + (y - 4) + " L " + (x + 15) + " " + y + " Z"
        }
      }
    }
  }

  // the adventurer, bobbing as they walk
  Item {
    id: hero
    width: 20
    height: 24
    x: Math.max(0, meter.walked * meter.roadEnd - 14)
    y: meter.roadY - height + 3 - Math.abs(Math.sin(meter.t * 5 + meter.label.length)) * 2
    rotation: Math.sin(meter.t * 5 + meter.label.length) * 4

    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      ShapePath {   // legs
        fillColor: "transparent"
        strokeColor: meter.ink
        strokeWidth: 1.6
        capStyle: ShapePath.RoundCap
        PathSvg {
          path: {
            var swing = Math.sin(meter.t * 10) * 2.5
            return "M 8 18 L " + (7 - swing) + " 23.5 M 12 18 L " + (13 + swing) + " 23.5"
          }
        }
      }
      ShapePath {   // body / cloak
        fillColor: meter.hero === "wizard" ? (meter.pal.magenta || "#f52e9b")
          : meter.hero === "rogue" ? (meter.pal.green || "#1be33a") : (meter.pal.blue || "#3f74ff")
        strokeColor: meter.ink
        strokeWidth: 1.2
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: "M 5 19 L 6.5 11 Q 10 9.5 13.5 11 L 15 19 Z" }
      }
      ShapePath {   // head
        fillColor: meter.paper
        strokeColor: meter.ink
        strokeWidth: 1.2
        PathAngleArc { centerX: 10; centerY: 7.5; radiusX: 3.4; radiusY: 3.4; startAngle: 0; sweepAngle: 360 }
      }
      ShapePath {   // headgear
        fillColor: meter.hero === "wizard" ? (meter.pal.magenta || "#f52e9b")
          : meter.hero === "rogue" ? (meter.pal.green || "#1be33a") : (meter.pal.yellow || "#d9b800")
        strokeColor: meter.ink
        strokeWidth: 1.1
        joinStyle: ShapePath.RoundJoin
        PathSvg {
          path: meter.hero === "wizard" ? "M 5.2 6.4 L 14.8 6.4 L 11.4 0.2 Z"              // pointy hat
            : meter.hero === "rogue" ? "M 6 8.6 Q 5.6 3.2 10 3 Q 14.4 3.2 14 8.6 Q 10 5.6 6 8.6 Z"   // hood
            : "M 6.4 7.4 Q 6.4 3.4 10 3.4 Q 13.6 3.4 13.6 7.4 Z M 9.4 3.6 L 10 0.8 L 10.6 3.6"        // helm + plume
        }
      }
      ShapePath {   // gear in hand: sword, staff or dagger
        fillColor: "transparent"
        strokeColor: meter.hero === "wizard" ? (meter.pal.brown || "#992327") : meter.ink
        strokeWidth: meter.hero === "wizard" ? 1.6 : 1.3
        capStyle: ShapePath.RoundCap
        PathSvg {
          path: meter.hero === "wizard" ? "M 16.5 5 L 15.5 20"
            : meter.hero === "rogue" ? "M 14.5 14 L 18.5 11 M 15.5 15 L 14 13"
            : "M 14.5 15 L 19.5 6 M 14 12.6 L 17 14.2"
        }
      }
    }
    Rectangle {   // wizard's glowing orb
      visible: meter.hero === "wizard"
      x: 14.4; y: 2.6; width: 4.4; height: 4.4; radius: 2.2
      color: meter.pal.bright_cyan || "#10ffd9"
      border.color: meter.ink; border.width: 0.8
      opacity: 0.7 + 0.3 * Math.sin(meter.t * 4)
    }
  }
}
