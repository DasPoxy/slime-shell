import QtQuick
import QtQuick.Shapes

// A little slime monster, drawn as vector paths on a 24×24 grid and scaled to
// `size`. Shared by the workspace and launcher widgets.
//
//   variant  0 goober (two eyes), 1 cyclops, 2 horned, 3 drooler, 4 antenna,
//            5 robot (the agents widget: boxy head, ear bolts, ^ ^ eyes;
//            "emote" turns them into > < for an alert)
//   mood     "sleep" (eyes shut), "idle" (awake, blinks now and then),
//            "emote" (happy eyes, big open grin, blush, sparkle, bouncing)
//
// Colours come from the caller so the monster follows the theme: `body` is the
// goo, `ink` the outline and features, `eye` the whites, `blush` the cheeks.
Item {
  id: root

  property int variant: 0
  property string mood: "idle"
  property real size: 22
  property real time: 0            // drive with the bar's animation clock
  property real seed: variant * 1.7
  property color body: "#9fe870"
  property color ink: "#101315"
  property color eye: "#ffffff"
  property color blush: "#ff6fa8"

  readonly property bool emote: mood === "emote"
  readonly property bool asleep: mood === "sleep"
  readonly property bool blinking: mood === "idle" && ((time * 0.23 + seed * 0.37) % 1) < 0.035
  readonly property real bounce: emote ? Math.abs(Math.sin(time * 4.2 + seed)) : 0

  implicitWidth: size
  implicitHeight: size

  Item {
    id: art
    width: 24
    height: 24
    // Bounce up and squash on landing while emoting.
    y: -root.bounce * 2.2 * (root.size / 24)
    transform: [
      Scale {
        origin.x: 12
        origin.y: 22
        xScale: root.size / 24 * (1 + (root.emote ? (1 - root.bounce) * 0.08 : 0))
        yScale: root.size / 24 * (1 - (root.emote ? (1 - root.bounce) * 0.08 : 0))
      }
    ]

    // ---- behind the body: horns / antenna ----
    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      visible: root.variant === 2
      ShapePath {
        fillColor: root.eye
        strokeColor: root.ink
        strokeWidth: 1.2
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: "M6.2 8.5 L4.2 2.2 L9.6 6.2 Z M17.8 8.5 L19.8 2.2 L14.4 6.2 Z" }
      }
    }
    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      visible: root.variant === 4 || root.variant === 5
      ShapePath {
        fillColor: "transparent"
        strokeColor: root.ink
        strokeWidth: 1.2
        capStyle: ShapePath.RoundCap
        PathSvg { path: root.variant === 5 ? "M12 5 L12 2.4" : "M12 4.5 Q13.5 2.5 12.5 1.2" }
      }
      ShapePath {
        fillColor: root.blush
        strokeColor: root.ink
        strokeWidth: 1
        PathAngleArc { centerX: root.variant === 5 ? 12 : 12.5; centerY: 1.4; radiusX: 1.3; radiusY: 1.3; startAngle: 0; sweepAngle: 360 }
      }
    }
    // robot ear bolts
    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      visible: root.variant === 5
      ShapePath {
        fillColor: root.body
        strokeColor: root.ink
        strokeWidth: 1.2
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: "M4.4 10.6 L2.2 10.6 Q1.5 10.6 1.5 11.3 L1.5 14.3 Q1.5 15 2.2 15 L4.4 15 Z M19.6 10.6 L21.8 10.6 Q22.5 10.6 22.5 11.3 L22.5 14.3 Q22.5 15 21.8 15 L19.6 15 Z" }
      }
    }

    // ---- body: a gooey dome with drippy feet ----
    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        fillColor: root.body
        strokeColor: root.ink
        strokeWidth: 1.4
        joinStyle: ShapePath.RoundJoin
        PathSvg {
          path: root.variant === 5
            // robot: a boxy head melting at the bottom
            ? "M4 9 Q4 5 8 5 L16 5 Q20 5 20 9 L20 18.6 Q20 20.6 18.7 20.2 C18.1 22.4 16.1 22.4 15.7 20.4 C14.5 21.2 13.1 21.2 12.1 20.4 C11.1 22.4 8.9 22.4 8.5 20.4 C7.1 21.2 5.7 21 5.2 20 Q4 19.9 4 18.6 Z"
            : root.variant === 3
            // drooler: longer drips
            ? "M3 18.5 C2 11.5 5 4 12 4 C19 4 22 11.5 21 18.5 C21 20.5 20 21 19.3 20.4 C18.8 23.6 16.4 23.6 16.1 20.6 C15 21.4 13.4 21.4 12.6 20.6 C12 24.2 9.4 24.2 9 20.6 C7.8 21.4 6.2 21.4 5 20.5 C4 21 3 20.2 3 18.5 Z"
            : "M3 18.5 C2 11.5 5 4 12 4 C19 4 22 11.5 21 18.5 C21 20.5 19.6 21.4 18.8 20.4 C17.9 22.2 16.2 22.2 15.6 20.6 C14.4 21.6 13 21.6 12 20.6 C11 22.6 8.8 22.6 8.2 20.6 C7 21.6 5.4 21.4 4.8 20.4 C3.8 20.8 3 20.2 3 18.5 Z"
        }
      }
      // glossy highlight
      ShapePath {
        fillColor: Qt.rgba(1, 1, 1, 0.55)
        strokeColor: "transparent"
        PathSvg { path: "M6.3 11 C6.3 8 8 6.2 10.2 5.8 C8.6 7 7.6 8.6 7.3 11 Z" }
      }
    }

    // ---- cheeks ----
    Repeater {
      model: root.emote ? [[6.2, 14.2], [17.8, 14.2]] : []
      Rectangle {
        required property var modelData
        x: modelData[0] - 1.4
        y: modelData[1] - 0.8
        width: 2.8
        height: 1.6
        radius: 0.8
        color: root.blush
        opacity: 0.85
      }
    }

    // ---- eyes ----
    readonly property var eyeSpots: root.variant === 1 ? [[12, 10.6, 3.4]] : [[9, 11, 2.3], [15, 11, 2.3]]

    Repeater {
      model: !root.asleep && !root.emote && root.variant !== 5 ? art.eyeSpots : []
      Item {
        required property var modelData
        x: modelData[0] - modelData[2]
        y: modelData[1] - modelData[2]
        width: modelData[2] * 2
        height: modelData[2] * 2
        transform: Scale { origin.y: height / 2; yScale: root.blinking ? 0.12 : 1 }

        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: root.eye
          border.color: root.ink
          border.width: 0.9
        }
        Rectangle {
          width: parent.width * 0.5
          height: width
          radius: width / 2
          x: parent.width * 0.3
          y: parent.height * 0.3
          color: root.ink
        }
      }
    }

    // closed (sleep) or happy ^ ^ (emote) eyes
    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      visible: root.asleep || root.emote || root.variant === 5
      ShapePath {
        fillColor: "transparent"
        strokeColor: root.ink
        strokeWidth: 1.3
        capStyle: ShapePath.RoundCap
        PathSvg {
          path: {
            if (root.variant === 5)   // robot: ^ ^ normally, > < when alerting
              return root.emote ? "M7.4 10 L10.2 11.8 L7.4 13.6 M16.6 10 L13.8 11.8 L16.6 13.6"
                                : "M7.4 12.6 L9 10.6 L10.6 12.6 M13.4 12.6 L15 10.6 L16.6 12.6"
            var up = root.emote   // happy eyes arch up, sleepy ones droop
            var cy = up ? 12 : 11
            var q = up ? 9.4 : 12.4
            var one = "M9.8 " + cy + " Q12 " + (up ? 8.4 : 13.2) + " 14.2 " + cy
            var two = "M7.3 " + cy + " Q9 " + q + " 10.7 " + cy + " M13.3 " + cy + " Q15 " + q + " 16.7 " + cy
            return root.variant === 1 ? one : two
          }
        }
      }
    }

    // ---- mouth ----
    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        fillColor: root.emote ? root.ink : "transparent"
        strokeColor: root.ink
        strokeWidth: 1.2
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg {
          path: root.variant === 5 && !root.emote ? "M9.4 16.2 L14.6 16.2 M11 15.2 L11 17.2 M13 15.2 L13 17.2"   // grille
            : root.emote ? "M8.3 14.6 Q12 20.4 15.7 14.6 Z"
            : root.asleep ? "M11.3 15.8 Q12 16.6 12.7 15.8 Q12 15 11.3 15.8 Z"
            : root.variant === 2 ? "M9.4 15.2 L10.6 16.4 L12 15.2 L13.4 16.4 L14.6 15.2"   // fangs
            : "M9.6 15.2 Q12 17.2 14.4 15.2"
        }
      }
      // tongue
      ShapePath {
        fillColor: root.emote || root.variant === 3 ? root.blush : "transparent"
        strokeColor: "transparent"
        PathSvg {
          path: root.emote ? "M10.4 17.2 Q12 15.6 13.6 17.2 Q12 18.6 10.4 17.2 Z"
            : root.variant === 3 && !root.asleep ? "M11.4 16.2 L12.6 16.2 L12.4 19.2 Q12 19.9 11.6 19.2 Z"
            : ""
        }
      }
    }

    // ---- sparkle while emoting ----
    Shape {
      x: 17.5
      y: 1.5
      width: 6
      height: 6
      visible: root.emote
      opacity: 0.5 + 0.5 * Math.sin(root.time * 6 + root.seed)
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        fillColor: root.eye
        strokeColor: root.ink
        strokeWidth: 0.6
        PathSvg { path: "M3 0 Q3.4 2.6 6 3 Q3.4 3.4 3 6 Q2.6 3.4 0 3 Q2.6 2.6 3 0 Z" }
      }
    }
  }
}
