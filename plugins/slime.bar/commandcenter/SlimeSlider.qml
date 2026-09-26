import QtQuick
import QtQuick.Shapes

// A volume slider made of goo: a wavy track that ripples, fills with ink up to
// the value (drips hanging off the filled part, longer the louder it is), and a
// droplet for the knob. Drag or click to set, scroll to nudge.
Item {
  id: slider

  required property var cc
  property real value: 0          // 0..maximum
  property real maximum: 1
  signal moved(real value)

  readonly property real t: cc.bar ? cc.bar.animTime : 0
  readonly property real fraction: Math.max(0, Math.min(1, value / maximum))
  readonly property real knobX: 8 + fraction * (width - 16)
  readonly property real midY: 12
  readonly property color ink: cc.ink

  implicitHeight: 30

  function waveY(x, amp) { return midY + Math.sin(x * 0.09 + t * 2.2) * amp }

  function trackPath(x0, x1, amp, thick) {
    var top = "", bottom = ""
    var steps = Math.max(2, Math.ceil((x1 - x0) / 6))
    for (var i = 0; i <= steps; i++) {
      var x = x0 + (x1 - x0) * i / steps
      var y = waveY(x, amp)
      top += (i === 0 ? "M " : " L ") + x + " " + (y - thick)
      bottom = " L " + x + " " + (y + thick) + bottom
    }
    return top + bottom + " Z"
  }

  function setFromX(x) {
    var v = Math.max(0, Math.min(1, (x - 8) / (width - 16))) * maximum
    moved(v)
  }

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {   // empty track: a faint ripple
      fillColor: Qt.rgba(slider.ink.r, slider.ink.g, slider.ink.b, 0.16)
      strokeColor: "transparent"
      PathSvg { path: slider.trackPath(4, slider.width - 4, 2, 3) }
    }
    ShapePath {   // filled goo, thicker and wobblier
      fillColor: slider.ink
      strokeColor: "transparent"
      PathSvg { path: slider.fraction > 0.01 ? slider.trackPath(4, slider.knobX, 2.4, 4) : "" }
    }
    ShapePath {   // drips hanging off the filled part
      fillColor: slider.ink
      strokeColor: "transparent"
      PathSvg {
        path: {
          var d = "", n = Math.floor(slider.knobX / 38)
          for (var i = 0; i < n; i++) {
            var x = 20 + i * 38 + (i % 2) * 9
            var len = (3 + (i * 7 % 5)) * (0.6 + slider.fraction) * (0.75 + 0.25 * Math.sin(slider.t * 1.6 + i))
            var y = slider.waveY(x, 2.4) + 3
            d += "M " + (x - 2.2) + " " + y + " Q " + x + " " + (y + len * 2) + " " + (x + 2.2) + " " + y + " Z "
          }
          return d
        }
      }
    }
  }

  // the droplet knob
  Shape {
    x: slider.knobX - 9
    y: slider.waveY(slider.knobX, 2.4) - 12
    width: 18
    height: 22
    scale: area.pressed ? 1.2 : (area.containsMouse ? 1.1 : 1)
    Behavior on scale { NumberAnimation { duration: 140 } }
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      fillColor: slider.cc.bar.monsterBody
      strokeColor: slider.ink
      strokeWidth: 1.6
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: "M 9 1 Q 16 10 16 14 A 7 7 0 1 1 2 14 Q 2 10 9 1 Z" }
    }
    ShapePath {
      fillColor: Qt.rgba(1, 1, 1, 0.7)
      strokeColor: "transparent"
      PathSvg { path: "M 5.5 13 Q 5.5 9.5 8 7.5 Q 6.8 10.5 7 13 Z" }
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    anchors.topMargin: -4
    anchors.bottomMargin: -4
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onPressed: mouse => slider.setFromX(mouse.x)
    onPositionChanged: mouse => { if (pressed) slider.setFromX(mouse.x) }
    onWheel: wheel => slider.moved(Math.max(0, Math.min(slider.maximum, slider.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
  }
}
