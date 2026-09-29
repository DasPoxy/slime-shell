import QtQuick
import QtQuick.Shapes

// A little creature stuck in a drip (the bar's easter egg): a gnome, goblin,
// skeleton, knight, wizard or priest, flailing inside a see-through film of
// the slime colour.
// Drawn on a 24×24 grid scaled to `size`.
Item {
  id: root

  property string kind: "gnome"      // gnome, goblin, skeleton, knight, wizard, priest, bard, rogue, orc, king, queen, princess
  property real size: 24
  property real time: 0
  property color ink: "black"
  property color paper: "white"
  property color goo: "green"
  property var pal: ({})

  readonly property real flail: Math.sin(time * 9)
  readonly property color red: pal.red || "#ff1720"
  readonly property color green: pal.green || "#1be33a"
  readonly property color gold: pal.yellow || "#f5c518"
  readonly property color purple: pal.magenta || "#8a4dff"
  readonly property color steel: "#aeb6bf"
  readonly property color leather: "#8a5a2e"
  readonly property color skin: kind === "goblin" ? Qt.darker(green, 1.15) : kind === "orc" ? Qt.darker(green, 1.6)
    : kind === "skeleton" ? paper : kind === "knight" ? steel : "#f2c2a0"
  readonly property color cyan: pal.cyan || "#1fb5c9"
  readonly property var bodyFill: ({ gnome: "#3f74ff", goblin: "#7a5230", skeleton: paper, knight: steel, wizard: purple, priest: paper,
                                     bard: cyan, rogue: "#3b3b46", orc: "#6b4a2a",
                                     king: red, queen: purple, princess: pal.bright_magenta || "#ff8ad0" })
  // hand positions (the arms flail)
  readonly property real rhx: 20 + flail
  readonly property real rhy: 9 - flail * 2

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
        fill: root.bodyFill[root.kind] || root.paper }
    // knight: red tabard and a sword brandished in one hand
    P { visible: root.kind === "knight"; d: "M10.4 13.2 L13.6 13.2 L13.8 20.8 L10.2 20.8 Z"; fill: root.red; line: 0.8 }
    P { visible: root.kind === "knight"; d: "M" + root.rhx + " " + root.rhy + " L" + (root.rhx + 1.2) + " " + (root.rhy - 6); line: 1.3 }
    P { visible: root.kind === "knight"; d: "M" + (root.rhx - 1.3) + " " + (root.rhy - 1) + " L" + (root.rhx + 1.5) + " " + (root.rhy - 0.6); line: 1.1 }
    // wizard: a few stars on the robe
    P { visible: root.kind === "wizard"; d: "M10 16 l0.4 0.9 l0.9 0.1 l-0.7 0.6 l0.2 0.9 l-0.8 -0.5 l-0.8 0.5 l0.2 -0.9 l-0.7 -0.6 l0.9 -0.1 Z"; fill: root.gold; line: 0.5 }
    // priest: a gold stole
    P { visible: root.kind === "priest"; d: "M10.2 13 L10.8 20.8 M13.8 13 L13.2 20.8"; stroke: root.gold; line: 1.5 }
    P { visible: root.kind === "skeleton"; d: "M9 15 L15 15 M9 17 L15 17 M9.4 19 L14.6 19 M12 13 L12 20.4"; line: 0.8 }   // ribs
    // royalty: an ermine-trimmed robe (king), a long gown (queen, princess)
    P { visible: root.kind === "king"; d: "M7.6 20 Q12 21.6 16.4 20 L16.6 21.4 Q12 22.8 7.4 21.4 Z"; fill: root.paper; line: 0.7 }
    P { visible: root.kind === "king"; d: "M11.4 14 L12.6 14 L12.6 20.6 L11.4 20.6 Z"; fill: root.paper; line: 0.5 }
    P { visible: root.kind === "queen" || root.kind === "princess"; d: "M8 17 Q12 16 16 17 L18 23 Q12 24.4 6 23 Z"; fill: root.bodyFill[root.kind]; line: 1 }
    P { visible: root.kind === "queen" || root.kind === "princess"; d: "M9.6 13.4 L14.4 13.4"; stroke: root.gold; line: 0.8 }
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
    // knight's helm: a visor slit and a plume
    Rectangle { visible: root.kind === "knight"; x: 8.4; y: 9.2; width: 7.2; height: 1.5; radius: 0.6; color: root.ink }
    P { visible: root.kind === "knight"; d: "M12 11.4 L12 13.6"; line: 0.7 }
    P { visible: root.kind === "knight"; d: "M12 6.2 Q12.6 1.2 17.4 1.4 Q14.2 3 13.6 6.3 Z"; fill: root.red; line: 0.8 }
    // wizard: long beard and a crooked pointed hat with a star
    P { visible: root.kind === "wizard"; d: "M8.2 11.4 Q12 23 15.8 11.4 Q12 13.6 8.2 11.4 Z"; fill: root.paper }
    P { visible: root.kind === "wizard"; d: "M8 7.2 Q10.6 2.4 13 -1.2 Q13.2 0.6 16 7.2 Z"; fill: root.purple }
    P { visible: root.kind === "wizard"; d: "M4.8 7.6 Q12 5.2 19.2 7.6 Q12 9 4.8 7.6 Z"; fill: root.purple }
    P { visible: root.kind === "wizard"; d: "M12.6 3.2 l0.3 0.7 l0.7 0.1 l-0.5 0.5 l0.1 0.7 l-0.6 -0.4 l-0.6 0.4 l0.1 -0.7 l-0.5 -0.5 l0.7 -0.1 Z"; fill: root.gold; line: 0.4 }
    // priest: a mitre with a gold cross
    P { visible: root.kind === "priest"; d: "M8.4 7.6 L8.6 2.6 Q12 -0.8 15.4 2.6 L15.6 7.6 Q12 6.8 8.4 7.6 Z"; fill: root.paper }
    P { visible: root.kind === "priest"; d: "M12 1.6 L12 6.2 M10.6 3.4 L13.4 3.4"; stroke: root.gold; line: 1.1 }
    // bard: a lute held across the body, and a cap with a long feather
    P { visible: root.kind === "bard"; d: "M13 16 Q16.6 13.6 18.4 16.4 Q18.8 19.6 15.2 20 Q12.2 19.8 13 16 Z"; fill: root.leather; line: 0.8 }
    P { visible: root.kind === "bard"; d: "M14 17.4 L7.6 12.2"; stroke: root.leather; line: 1.3 }
    Rectangle { visible: root.kind === "bard"; x: 15.2; y: 16.8; width: 1.2; height: 1.2; radius: 0.6; color: root.ink }
    P { visible: root.kind === "bard"; d: "M7 8 Q12 3.4 17 8 Q12 6.6 7 8 Z"; fill: root.red }
    P { visible: root.kind === "bard"; d: "M15.4 6.4 Q20.6 1.6 22.4 2.4 Q19.4 4.4 16.2 7.2 Z"; fill: root.gold; line: 0.6 }
    // rogue: a deep hood and a dagger
    P { visible: root.kind === "rogue"; d: "M6.6 14 Q6 4.6 12 4.2 Q18 4.6 17.4 14 L15.6 11 Q16 7 12 6.8 Q8 7 8.4 11 Z"; fill: root.bodyFill.rogue }
    P { visible: root.kind === "rogue"; d: "M" + root.rhx + " " + root.rhy + " L" + (root.rhx + 0.8) + " " + (root.rhy - 3.6); stroke: root.steel; line: 1.2 }
    P { visible: root.kind === "rogue"; d: "M8.8 11.2 L15.2 11.2"; stroke: root.ink; line: 0.8 }
    // orc: tusks, heavy brow
    P { visible: root.kind === "orc"; d: "M10.4 12.6 L10.8 10.8 L11.4 12.6 Z M12.6 12.6 L13.2 10.8 L13.6 12.6 Z"; fill: root.paper; line: 0.5 }
    P { visible: root.kind === "orc"; d: "M8.6 8.2 L11.4 8.8 M12.6 8.8 L15.4 8.2"; line: 1.1 }
    // crowns: the king's and queen's tall and jewelled, the princess's a tiara over long hair
    P { visible: root.kind === "princess"; d: "M7.2 9 Q6.4 16 5.4 18.4 Q7.6 17 8.4 12 M16.8 9 Q17.6 16 18.6 18.4 Q16.4 17 15.6 12"; fill: root.gold; line: 0.8 }
    P { visible: root.kind === "king" || root.kind === "queen"; d: "M8 6.8 L7.6 2.2 L9.8 4.4 L12 1.2 L14.2 4.4 L16.4 2.2 L16 6.8 Z"; fill: root.gold; line: 0.8 }
    Rectangle { visible: root.kind === "king" || root.kind === "queen"; x: 11.3; y: 3.6; width: 1.4; height: 1.4; radius: 0.7; color: root.red; border.color: root.ink; border.width: 0.4 }
    P { visible: root.kind === "king"; d: "M8.4 11.6 Q12 17 15.6 11.6 Q12 13.2 8.4 11.6 Z"; fill: root.leather; line: 0.8 }   // beard
    P { visible: root.kind === "princess"; d: "M8.8 6.6 L9.6 4.8 L10.8 6 L12 3.8 L13.2 6 L14.4 4.8 L15.2 6.6 Z"; fill: root.gold; line: 0.6 }
    // eyes: wide with panic (sockets for the skeleton; hidden behind the knight's visor)
    Rectangle { visible: root.kind !== "knight"; x: 9.2; y: 8.6; width: 2.2; height: 2.4; radius: 1.1; color: root.kind === "skeleton" ? root.ink : root.paper; border.color: root.ink; border.width: 0.6
      Rectangle { visible: root.kind !== "skeleton"; x: 0.6; y: 0.7; width: 1; height: 1; radius: 0.5; color: root.ink } }
    Rectangle { visible: root.kind !== "knight"; x: 12.6; y: 8.6; width: 2.2; height: 2.4; radius: 1.1; color: root.kind === "skeleton" ? root.ink : root.paper; border.color: root.ink; border.width: 0.6
      Rectangle { visible: root.kind !== "skeleton"; x: 0.6; y: 0.7; width: 1; height: 1; radius: 0.5; color: root.ink } }
    // mouth: an "o" of alarm (or teeth)
    Rectangle { visible: ["goblin", "skeleton", "priest", "orc", "rogue"].indexOf(root.kind) >= 0; x: 11; y: 12; width: 2; height: 1.6 + Math.abs(root.flail); radius: 1; color: root.ink }
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
