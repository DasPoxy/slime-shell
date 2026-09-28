import QtQuick
import QtQuick.Shapes

// Detritus adrift in the goo: spare eyeballs looking about, bones, teeth,
// bubbles, and any SlimeGear item (sword, axe, hat, frog, mug, potion, skull…),
// each bobbing and turning on its own slow drift. `bits` is a list of
// { kind, x, y (0..1 of this item), s (px), sp }
// and `avoid` a list of rects (x, y, w, h, in this item's coordinates) the
// bits fade out over, so they never sit behind text or widgets.
Item {
  id: debris

  required property var bar
  property var bits: []
  property var avoid: []
  // when set, bits only show inside these rects (e.g. the islands of a
  // shaped bar), so nothing floats in thin air
  property var within: []
  property real bitOpacity: 0.8
  // size variety: each bit has a chance to come out bigger than its base
  // size (never smaller), as much as the slime around it has room for
  property real growChance: 0.4
  property real maxGrow: 2.2
  // the biggest a bit may get (defaults to the slime's thickness here)
  property real room: Math.min(width, height) - 4
  function sizeOf(b, i) {
    // a fixed dice roll per bit (so it doesn't change size as it drifts)
    var h1 = Math.abs(Math.sin((i + 1) * 78.233 + b.x * 311.7 + b.y * 97.1) * 43758.5453) % 1
    var h2 = Math.abs(Math.sin((i + 1) * 12.989 + b.x * 43.7 + b.y * 191.3) * 24634.6345) % 1
    var grow = h1 < growChance ? 1 + (maxGrow - 1) * h2 * h2 : 1
    return Math.round(Math.max(b.s, Math.min(b.s * grow, room)))
  }
  // 0..1: the bits fly apart, spin and fade (a lyric drip bursting)
  property real burst: 0

  readonly property real t: bar ? bar.animTime : 0
  readonly property color ink: bar ? bar.slimeInk : "black"
  readonly property color paper: bar ? bar.paperColor : "white"

  function inside(cx, cy) {
    if (within.length === 0) return true
    for (var i = 0; i < within.length; i++) {
      var w = within[i]
      if (w && w.z > 0 && cx > w.x - 2 && cx < w.x + w.z + 2 && cy > w.y - 6 && cy < w.y + w.w + 6) return true
    }
    return false
  }

  function clearOf(cx, cy, r) {
    for (var i = 0; i < avoid.length; i++) {
      var a = avoid[i]
      if (!a || a.z <= 0) continue
      if (cx > a.x - r - 6 && cx < a.x + a.z + r + 6 && cy > a.y - r - 4 && cy < a.y + a.w + r + 4) return false
    }
    return true
  }

  Repeater {
    model: debris.bits
    Item {
      id: bit
      required property var modelData
      required property int index
      readonly property real drift: debris.t * modelData.sp + index * 1.9
      readonly property real cx: modelData.x * debris.width + Math.sin(drift) * 5
      readonly property real cy: modelData.y * debris.height + Math.cos(drift * 0.8) * 3
      // bursting: flung out from the middle (each its own way), falling a bit
      readonly property real fling: index * 2.39 + modelData.x * 5.1
      readonly property real bx: (modelData.x - 0.5) * 60 * debris.burst + Math.cos(fling) * 26 * debris.burst
      readonly property real by: (modelData.y - 0.5) * 40 * debris.burst + (Math.sin(fling) * 16 + 30 * debris.burst) * debris.burst
      readonly property real sz: debris.sizeOf(modelData, index)
      width: sz
      height: sz
      x: cx - width / 2 + bx
      y: cy - height / 2 + by
      rotation: Math.sin(drift * 0.6) * 40 + Math.sin(fling) * 240 * debris.burst
      scale: 1 + 0.35 * debris.burst
      property real shown: debris.clearOf(cx, cy, width / 2) && debris.inside(cx, cy) ? debris.bitOpacity : 0
      Behavior on shown { NumberAnimation { duration: 400 } }
      opacity: shown * (1 - debris.burst)

      Rectangle {   // spare eyeball, looking somewhere else
        visible: bit.modelData.kind === "eye"
        anchors.fill: parent
        radius: width / 2
        color: debris.paper
        border.color: debris.ink
        border.width: 1
        Rectangle {
          width: parent.width * 0.45; height: width; radius: width / 2
          x: parent.width * 0.3 + Math.sin(bit.drift * 1.7) * parent.width * 0.15
          y: parent.height * 0.28
          color: debris.ink
        }
      }
      readonly property bool own: ["eye", "bone", "tooth", "bubble"].indexOf(modelData.kind) !== -1
      SlimeGear {
        visible: !bit.own
        anchors.fill: parent
        size: bit.width
        bar: debris.bar
        kind: bit.own ? "chest" : bit.modelData.kind
        lit: true
        net: "ethernet"
      }
      Shape {
        visible: bit.own && bit.modelData.kind !== "eye"
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          fillColor: bit.modelData.kind === "bubble" ? Qt.rgba(1, 1, 1, 0.35) : debris.paper
          strokeColor: debris.ink
          strokeWidth: 1
          joinStyle: ShapePath.RoundJoin
          PathSvg {
            path: {
              var s = bit.width
              if (bit.modelData.kind === "bone")
                return "M " + s * 0.2 + " " + s * 0.42 + " L " + s * 0.8 + " " + s * 0.42 + " L " + s * 0.8 + " " + s * 0.58 + " L " + s * 0.2 + " " + s * 0.58 + " Z"
                  + " M " + s * 0.12 + " " + s * 0.5 + " m -" + s * 0.11 + " 0 a " + s * 0.11 + " " + s * 0.11 + " 0 1 0 " + s * 0.22 + " 0 a " + s * 0.11 + " " + s * 0.11 + " 0 1 0 -" + s * 0.22 + " 0"
                  + " M " + s * 0.88 + " " + s * 0.5 + " m -" + s * 0.11 + " 0 a " + s * 0.11 + " " + s * 0.11 + " 0 1 0 " + s * 0.22 + " 0 a " + s * 0.11 + " " + s * 0.11 + " 0 1 0 -" + s * 0.22 + " 0"
              if (bit.modelData.kind === "tooth")
                return "M " + s * 0.15 + " " + s * 0.1 + " L " + s * 0.85 + " " + s * 0.1 + " L " + s * 0.5 + " " + s * 0.95 + " Z"
              return "M 0 " + s / 2 + " a " + s / 2 + " " + s / 2 + " 0 1 0 " + s + " 0 a " + s / 2 + " " + s / 2 + " 0 1 0 -" + s + " 0"
            }
          }
        }
      }
    }
  }
}
