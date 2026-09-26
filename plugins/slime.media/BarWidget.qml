import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "../slime.bar/ui"

// Slime Shell now-playing widget: a lich conjuring the music — the ooze
// visualizer pours out of his raised hand in the theme's colours while
// something plays — followed by previous / play / next as bobbing cream
// bubbles. Hover the lich for the track, click him for the command centre,
// scroll over him to skip tracks. Hidden when nothing is playing.
// Settings (shell.json):
//   visualizer  true/false (default true)
BarWidget {
  id: root
  moduleName: "slime.media"

  readonly property bool slime: !!bar && bar.slimeSkin === true
  readonly property var player: {
    var ps = Mpris.players.values
    for (var i = 0; i < ps.length; i++) if (ps[i].isPlaying) return ps[i]
    for (var j = 0; j < ps.length; j++) if (ps[j].trackTitle) return ps[j]
    return null
  }
  readonly property bool playing: !!player && player.isPlaying
  readonly property bool hasMedia: !!player && (player.trackTitle || player.trackArtist)
  readonly property string track: player ? (player.trackTitle || player.identity) + (player.trackArtist ? " — " + player.trackArtist : "") : ""
  readonly property bool showViz: setting("visualizer", true) === true
  readonly property var pal: slime && bar.palette ? bar.palette : ({})
  readonly property color ink: slime ? bar.slimeInk : (bar ? bar.barForeground : Color.foreground)
  readonly property color paper: slime ? bar.paperColor : "white"
  readonly property real t: slime ? bar.animTime : 0
  // the spell's colours, from the theme
  readonly property var spellColors: [pal.bright_magenta || "#ff69c1", pal.magenta || "#f52e9b",
    pal.bright_blue || "#6695ff", pal.bright_cyan || "#10ffd9", pal.bright_yellow || "#e4cc00"]

  visible: hasMedia
  implicitWidth: !hasMedia ? 0 : vertical ? barSize : row.implicitWidth + 14
  implicitHeight: !hasMedia ? 0 : vertical ? row.implicitHeight + 12 : barSize

  IpcHandler {
    target: "slime-media"
    function toggle(): void { if (root.player) root.player.togglePlaying() }
    function next(): void { if (root.player) root.player.next() }
    function previous(): void { if (root.player) root.player.previous() }
  }

  // a row on top/bottom bars, a column on side bars
  Grid {
    id: row
    anchors.centerIn: parent
    columns: root.vertical ? 1 : 4
    columnSpacing: 2
    rowSpacing: 6
    horizontalItemAlignment: Grid.AlignHCenter
    verticalItemAlignment: Grid.AlignVCenter

    // the lich, and the spell coming off his hand
    Item {
      width: 30
      height: 30
      SlimeGear {
        anchors.fill: parent
        size: 30
        bar: root.bar
        kind: "lich"
        lit: root.playing
        transform: Translate { y: Math.sin(root.t * 1.3) * 1.2 }
      }
      HoverHandler {
        onHoveredChanged: {
          if (!root.bar) return
          if (hovered) root.bar.showTooltip(root, root.track)
          else root.bar.hideTooltip(root)
        }
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.slime) { root.bar.ccTab = "home"; root.bar.commandCenterOpen = true }
        onWheel: wheel => { if (!root.player) return; if (wheel.angleDelta.y > 0) root.player.previous(); else root.player.next() }
      }
    }

    SlimeCava {
      visible: root.showViz && root.slime && !root.vertical
      active: root.playing
      width: 58
      height: 22
      bars: 10
      gap: 1.5
      colors: root.spellColors
      fill: root.ink
      outline: root.ink
      outlineWidth: 0.8
    }

    Item { width: root.vertical ? 1 : 8; height: 1; visible: !root.vertical }

    // controls: cream bubbles with ink symbols, bobbing like the bar's gear
    Grid {
      columns: root.vertical ? 1 : 3
      spacing: 5
      horizontalItemAlignment: Grid.AlignHCenter
      verticalItemAlignment: Grid.AlignVCenter
      Repeater {
        model: ["previous", "togglePlaying", "next"]
        Item {
          id: control
          required property string modelData
          required property int index
          readonly property bool main: modelData === "togglePlaying"
          width: main ? 22 : 18
          height: width
          transform: Translate { y: Math.sin(root.t * 1.3 + control.index * 1.1) * 1.3 }
          scale: controlHover.hovered ? 1.15 : 1
          Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
          HoverHandler { id: controlHover }

          Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: control.main && root.playing ? (root.pal.bright_magenta || "#ff69c1") : root.paper
            border.color: root.ink
            border.width: 1.6
          }
          Rectangle {   // gloss
            x: parent.width * 0.2; y: parent.height * 0.14
            width: parent.width * 0.26; height: width * 0.6; radius: height / 2
            rotation: -30
            color: Qt.rgba(1, 1, 1, 0.8)
          }
          Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
              fillColor: root.ink
              strokeColor: root.ink
              strokeWidth: 0.6
              joinStyle: ShapePath.RoundJoin
              PathSvg {
                path: {
                  var s = control.width, c = s / 2, u = s / 18
                  if (control.modelData === "previous")
                    return "M " + (c - 4 * u) + " " + (c - 4 * u) + " L " + (c - 2.6 * u) + " " + (c - 4 * u) + " L " + (c - 2.6 * u) + " " + (c + 4 * u) + " L " + (c - 4 * u) + " " + (c + 4 * u) + " Z"
                      + " M " + (c + 4 * u) + " " + (c - 4 * u) + " L " + (c - 2 * u) + " " + c + " L " + (c + 4 * u) + " " + (c + 4 * u) + " Z"
                  if (control.modelData === "next")
                    return "M " + (c + 4 * u) + " " + (c - 4 * u) + " L " + (c + 2.6 * u) + " " + (c - 4 * u) + " L " + (c + 2.6 * u) + " " + (c + 4 * u) + " L " + (c + 4 * u) + " " + (c + 4 * u) + " Z"
                      + " M " + (c - 4 * u) + " " + (c - 4 * u) + " L " + (c + 2 * u) + " " + c + " L " + (c - 4 * u) + " " + (c + 4 * u) + " Z"
                  if (root.playing)   // pause
                    return "M " + (c - 3.6 * u) + " " + (c - 4 * u) + " L " + (c - 1.2 * u) + " " + (c - 4 * u) + " L " + (c - 1.2 * u) + " " + (c + 4 * u) + " L " + (c - 3.6 * u) + " " + (c + 4 * u) + " Z"
                      + " M " + (c + 1.2 * u) + " " + (c - 4 * u) + " L " + (c + 3.6 * u) + " " + (c - 4 * u) + " L " + (c + 3.6 * u) + " " + (c + 4 * u) + " L " + (c + 1.2 * u) + " " + (c + 4 * u) + " Z"
                  return "M " + (c - 2.6 * u) + " " + (c - 4.4 * u) + " L " + (c + 4.4 * u) + " " + c + " L " + (c - 2.6 * u) + " " + (c + 4.4 * u) + " Z"   // play
                }
              }
            }
          }
          MouseArea {
            anchors.fill: parent
            anchors.margins: -2
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.player) root.player[control.modelData]()
          }
        }
      }
    }
  }
}
