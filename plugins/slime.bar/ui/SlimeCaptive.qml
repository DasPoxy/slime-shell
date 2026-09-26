import QtQuick
import QtQuick.Shapes

// A little creature stuck in a drip (the bar's easter egg): a gnome, a goblin
// or a skeleton, flailing inside a see-through film of the slime colour.
// Drawn on a 24×24 grid scaled to `size`.
Item {
  id: root

  property string kind: "gnome"      // gnome, goblin, skeleton
  property real size: 24
  property real time: 0
  property color ink: "black"
  property color paper: "white"
  property color goo: "green"
  property var pal: ({})

  readonly property real flail: Math.sin(time * 9)
  readonly property color red: pal.red || "#ff1720"
  readonly property color green: pal.green || "#1be33a"
  readonly property color skin: kind === "goblin" ? Qt.darker(green, 1.15) : kind === "skeleton" ? paper : "#f2c2a0"

  implicitWidth: size
  implicitHeight: size

  component P: Shape {
    id: p
    property string d: ""
    property color fill: "transparent"
    property color stroke: root.ink
    property real line: 1.1
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
    rotation: root.flail * 8
    transform: Scale { xScale: root.size / 24; yScale: root.size / 24 }

    // flailing arms
    P { d: "M8 14 L" + (4 - root.flail) + " " + (9 + root.flail * 2) + " M16 14 L" + (20 + root.flail) + " " + (9 - root.flail * 2); line: 1.4
        stroke: root.kind === "skeleton" ? root.ink : root.ink }
    // body
    P { d: "M8 13 Q12 11.4 16 13 L16.6 20 Q12 21.4 7.4 20 Z"
        fill: root.kind === "gnome" ? "#3f74ff" : root.kind === "goblin" ? "#7a5230" : root.paper }
    P { visible: root.kind === "skeleton"; d: "M9 15 L15 15 M9 17 L15 17 M9.4 19 L14.6 19 M12 13 L12 20.4"; line: 0.8 }   // ribs
    // head
    Rectangle {
      x: 7.4; y: 6; width: 9.2; height: 8.4; radius: 4.2
      color: root.skin; border.color: root.ink; border.width: 1
    }
    // goblin ears
    P { visible: root.kind === "goblin"; d: "M7.8 9 L3.4 6.4 L7.8 11.4 Z M16.2 9 L20.6 6.4 L16.2 11.4 Z"; fill: root.skin }
    // gnome beard and hat
    P { visible: root.kind === "gnome"; d: "M8 11.6 Q12 19 16 11.6 Q12 13.4 8 11.6 Z"; fill: root.paper }
    P { visible: root.kind === "gnome"; d: "M6.6 7.8 Q12 5.8 17.4 7.8 L13 0.6 Z"; fill: root.red }
    // eyes: wide with panic (sockets for the skeleton)
    Rectangle { x: 9.2; y: 8.6; width: 2.2; height: 2.4; radius: 1.1; color: root.kind === "skeleton" ? root.ink : root.paper; border.color: root.ink; border.width: 0.6
      Rectangle { visible: root.kind !== "skeleton"; x: 0.6; y: 0.7; width: 1; height: 1; radius: 0.5; color: root.ink } }
    Rectangle { x: 12.6; y: 8.6; width: 2.2; height: 2.4; radius: 1.1; color: root.kind === "skeleton" ? root.ink : root.paper; border.color: root.ink; border.width: 0.6
      Rectangle { visible: root.kind !== "skeleton"; x: 0.6; y: 0.7; width: 1; height: 1; radius: 0.5; color: root.ink } }
    // mouth: an "o" of alarm (or teeth)
    Rectangle { visible: root.kind !== "gnome"; x: 11; y: 12; width: 2; height: 1.6 + Math.abs(root.flail); radius: 1; color: root.ink }
  }

  // the goo film over them, so they read as *inside* the drip
  Rectangle {
    anchors.centerIn: parent
    width: root.size * 1.1
    height: width
    radius: width / 2
    color: Qt.rgba(root.goo.r, root.goo.g, root.goo.b, 0.28)
  }
  Rectangle {   // glint on the film
    x: root.size * 0.18; y: root.size * 0.1
    width: root.size * 0.22; height: width * 0.5; radius: height / 2
    rotation: -35
    color: Qt.rgba(1, 1, 1, 0.7)
  }
}
