import QtQuick
import QtQuick.Shapes

// An indicator's icon: the object itself floating in the ooze ("gear"), or
// a little slime with the object suspended inside it ("slimes"). Lit, the
// slime perks up (eyes open, a hop, a glow round the object); unlit it dozes.
Item {
  id: icon

  property string kind: "candle"
  property var bar: null
  property bool lit: false
  property string iconSet: "gear"          // gear | slimes
  property real size: 22
  // each slime its own hue along the theme (hue), so a row of them differs
  property int hue: 0

  implicitWidth: size
  implicitHeight: size

  readonly property real t: bar ? bar.animTime : 0
  readonly property var pal: bar && bar.palette ? bar.palette : ({})
  readonly property color ink: bar ? bar.slimeInk : "#101315"
  readonly property var hues: [pal.green, pal.cyan, pal.magenta, pal.yellow, pal.blue, pal.red]
  readonly property color goo: hues[hue % hues.length] || (bar ? bar.slimeColor : "#5fd35f")

  SlimeGear {
    visible: icon.iconSet !== "slimes"
    anchors.fill: parent
    size: icon.size
    bar: icon.bar
    kind: icon.kind
    lit: icon.lit
  }

  Item {
    id: slimeBody
    visible: icon.iconSet === "slimes"
    anchors.fill: parent
    readonly property real hop: icon.lit ? Math.abs(Math.sin(icon.t * 3 + icon.hue)) * 1.2 : 0
    readonly property real squish: Math.sin(icon.t * (icon.lit ? 4 : 1.4) + icon.hue) * (icon.lit ? 0.5 : 0.3)
    transform: Translate { y: -slimeBody.hop }
    // the slime: a see-through dome of goo
    Item {
      width: 24; height: 24
      transform: Scale { xScale: icon.size / 24; yScale: icon.size / 24 }
      Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          fillColor: Qt.rgba(icon.goo.r, icon.goo.g, icon.goo.b, icon.lit ? 0.9 : 0.72)
          strokeColor: icon.ink
          strokeWidth: 1.2
          joinStyle: ShapePath.RoundJoin
          PathSvg {
            path: "M1.4 22.6 Q0.6 11.4 5.4 6.2 Q12 " + (0.8 + slimeBody.squish) + " 18.6 6.2 Q23.4 11.4 22.6 22.6 Q12 24.2 1.4 22.6 Z"
          }
        }
      }
      // a glow round the object when it's on
      Rectangle {
        visible: icon.lit
        x: 12 - width / 2; y: 15.6 - height / 2
        width: 14 + Math.sin(icon.t * 4) * 1.2; height: width; radius: width / 2
        color: Qt.rgba(1, 1, 1, 0.35)
      }
      // the object, suspended in the goo, bobbing and turning a little
      SlimeGear {
        x: 12 - width / 2; y: 15.6 - height / 2 + Math.sin(icon.t * 1.6 + icon.hue) * 0.6
        width: 12.5; height: 12.5; size: 12.5
        rotation: Math.sin(icon.t * 1.1 + icon.hue * 2) * 10
        bar: icon.bar
        kind: icon.kind
        lit: icon.lit
        opacity: 0.9
      }
      // sheen
      Rectangle { x: 4.4; y: 8.4; width: 4.6; height: 1.6; radius: 0.7; rotation: -30; color: Qt.rgba(1, 1, 1, 0.7) }
      // eyes on its brow: awake when on, sleepy lines when off
      Rectangle { x: 7.6; y: icon.lit ? 4.8 : 6; width: 2; height: icon.lit ? 2.6 : 0.7; radius: 0.8; color: icon.ink }
      Rectangle { x: 14.4; y: icon.lit ? 4.8 : 6; width: 2; height: icon.lit ? 2.6 : 0.7; radius: 0.8; color: icon.ink }
    }
  }
}
