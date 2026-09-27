import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Ui

// Drop-in replacement for Omarchy's PanelSlider (same properties and signals:
// bar, value, minimum, maximum, step, integer, tickCount, liveValue, dragging,
// moved / released / rightClicked) drawn like the command centre's sound
// sliders: a rippling ink track that fills as it rises, drips hanging off the
// filled part, and a slime-droplet knob. Off the slime bar it falls back to
// the stock PanelSlider look.
Item {
  id: root

  property QtObject bar: null
  property real value: 0
  property real minimum: 0
  property real maximum: 1
  property real step: 0.05
  property bool integer: false
  property int tickCount: 0
  property bool dragging: false
  property real liveValue: value
  onValueChanged: if (!dragging) liveValue = value

  signal moved(real value)
  signal released(real value)
  signal rightClicked()

  // a stop for the command centre's keyboard navigation: ← / → nudge it
  readonly property bool ccFocusable: slime
  function ccActivate() {}
  function ccAdjust(dir) {
    var next = Math.max(minimum, Math.min(maximum, liveValue + dir * step))
    if (integer) next = Math.round(next)
    liveValue = next
    moved(next)
    released(next)
  }

  readonly property bool slime: !!bar && bar.slimeSkin === true
  readonly property real range: Math.max(0.0001, maximum - minimum)
  readonly property real progress: Math.max(0, Math.min(1, (liveValue - minimum) / range))
  readonly property real t: slime ? bar.animTime : 0
  readonly property color ink: slime ? bar.slimeInk : Color.foreground
  readonly property real knobX: 8 + progress * (width - 16)
  readonly property real midY: height / 2 - 2

  implicitWidth: Style.space(200)
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
  function valueFromX(x) {
    var f = Math.max(0, Math.min(1, (x - 8) / Math.max(1, width - 16)))
    var raw = minimum + f * range
    if (integer) raw = Math.round(raw)
    return Math.max(minimum, Math.min(maximum, raw))
  }

  // ---- stock look off the slime bar -------------------------------------------
  PanelSlider {
    visible: !root.slime
    anchors.fill: parent
    bar: root.bar
    minimum: root.minimum; maximum: root.maximum; step: root.step
    integer: root.integer; tickCount: root.tickCount
    value: root.value
    onMoved: v => root.moved(v)
    onReleased: v => root.released(v)
    onRightClicked: root.rightClicked()
    onDraggingChanged: root.dragging = dragging
    onLiveValueChanged: if (!root.slime) root.liveValue = liveValue
  }

  // ---- goo ------------------------------------------------------------------
  Shape {
    visible: root.slime
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {   // empty track: a faint ripple
      fillColor: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.16)
      strokeColor: "transparent"
      PathSvg { path: root.trackPath(4, root.width - 4, 2, 3) }
    }
    ShapePath {   // filled goo
      fillColor: root.ink
      strokeColor: "transparent"
      PathSvg { path: root.progress > 0.01 ? root.trackPath(4, root.knobX, 2.4, 4) : "" }
    }
    ShapePath {   // drips off the filled part, longer the fuller it is
      fillColor: root.ink
      strokeColor: "transparent"
      PathSvg {
        path: {
          var d = "", n = Math.floor(root.knobX / 38)
          for (var i = 0; i < n; i++) {
            var x = 20 + i * 38 + (i % 2) * 9
            var len = (3 + (i * 7 % 5)) * (0.6 + root.progress) * (0.75 + 0.25 * Math.sin(root.t * 1.6 + i))
            var y = root.waveY(x, 2.4) + 3
            d += "M " + (x - 2.2) + " " + y + " Q " + x + " " + (y + len * 2) + " " + (x + 2.2) + " " + y + " Z "
          }
          return d
        }
      }
    }
  }

  // tick notches (e.g. text-size stops)
  Repeater {
    model: root.slime && root.tickCount > 1 ? root.tickCount : 0
    Rectangle {
      required property int index
      readonly property real tx: 8 + (root.width - 16) * index / (root.tickCount - 1)
      x: tx - 1.5
      y: root.waveY(tx, 2) - 7
      width: 3; height: 14; radius: 1.5
      color: root.slime ? root.bar.paperColor : "white"
      border.color: root.ink
      border.width: 0.8
    }
  }

  // the droplet knob
  Shape {
    visible: root.slime
    x: root.knobX - 9
    y: root.waveY(root.knobX, 2.4) - 12
    width: 18
    height: 22
    scale: root.dragging ? 1.2 : (area.containsMouse ? 1.1 : 1)
    Behavior on scale { NumberAnimation { duration: 140 } }
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      fillColor: root.slime ? root.bar.monsterBody : "white"
      strokeColor: root.ink
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
    enabled: root.slime && root.enabled
    anchors.fill: parent
    anchors.topMargin: -4
    anchors.bottomMargin: -4
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onPressed: mouse => {
      if (mouse.button !== Qt.LeftButton) return
      root.dragging = true
      root.liveValue = root.valueFromX(mouse.x)
      root.moved(root.liveValue)
    }
    onClicked: mouse => { if (mouse.button === Qt.RightButton) root.rightClicked() }
    onPositionChanged: mouse => {
      if (!root.dragging) return
      root.liveValue = root.valueFromX(mouse.x)
      root.moved(root.liveValue)
    }
    onReleased: mouse => {
      if (mouse.button !== Qt.LeftButton) return
      root.dragging = false
      root.released(root.liveValue)
      root.liveValue = root.value
    }
    onWheel: wheel => {
      var next = Math.max(root.minimum, Math.min(root.maximum, root.liveValue + (wheel.angleDelta.y > 0 ? root.step : -root.step)))
      if (root.integer) next = Math.round(next)
      root.liveValue = next
      root.moved(next)
      root.released(next)
    }
  }
}
