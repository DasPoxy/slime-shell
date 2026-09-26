import QtQuick
import QtQuick.Shapes
import Quickshell.Widgets

// The media player as a slime monster: a cyclops whose eye is the album art,
// with the track on its forehead, the controls beside it, and a mouth of
// pointed teeth that doubles as the playback timer — teeth turn white as the
// track plays. Click the mouth to seek. Players that don't report a track
// length (browsers, often) get a chomping wave instead of a fake progress.
Item {
  id: monster

  required property var cc
  property var player: null

  readonly property real t: cc.bar ? cc.bar.animTime : 0
  readonly property bool playing: !!player && player.isPlaying
  readonly property bool knownLength: !!player && player.lengthSupported && player.length > 1 && player.length >= player.position
  readonly property real progress: knownLength ? Math.max(0, Math.min(1, player.position / player.length)) : 0
  readonly property color body: cc.bar.monsterBody
  readonly property color ink: cc.ink
  readonly property color paper: cc.paper

  implicitHeight: 168

  function clockText(seconds) {
    seconds = Math.max(0, Math.floor(seconds || 0))
    return Math.floor(seconds / 60) + ":" + ("0" + seconds % 60).slice(-2)
  }

  // gentle breathing, livelier while music plays
  readonly property real breathe: Math.sin(t * (playing ? 4 : 1.4)) * (playing ? 0.012 : 0.006)

  Item {
    id: art
    anchors.fill: parent
    transform: Scale { origin.x: monster.width / 2; origin.y: monster.height; yScale: 1 + monster.breathe; xScale: 1 - monster.breathe * 0.5 }

    // ---- body -------------------------------------------------------------
    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        fillColor: monster.body
        strokeColor: monster.ink
        strokeWidth: 2
        joinStyle: ShapePath.RoundJoin
        PathSvg {
          path: {
            var w = monster.width, h = monster.height - 10
            var d = "M " + (0.04 * w) + " " + (0.86 * h)
              + " C " + (-0.01 * w) + " " + (0.4 * h) + " " + (0.1 * w) + " " + (0.04 * h) + " " + (0.5 * w) + " " + (0.04 * h)
              + " C " + (0.9 * w) + " " + (0.04 * h) + " " + (1.01 * w) + " " + (0.4 * h) + " " + (0.96 * w) + " " + (0.86 * h)
            // drippy underside: bumps with a few longer drips
            var feet = [[0.86, 1.0], [0.72, 1.12], [0.58, 0.98], [0.42, 1.1], [0.27, 1.0], [0.14, 1.06]]
            var x = 0.96
            for (var i = 0; i < feet.length; i++) {
              var fx = feet[i][0], fy = feet[i][1]
              d += " Q " + ((x + fx) / 2 * w) + " " + (fy * h + 4) + " " + (fx * w) + " " + (0.9 * h)
              x = fx
            }
            return d + " Q " + (0.08 * w) + " " + (0.96 * h) + " " + (0.04 * w) + " " + (0.86 * h) + " Z"
          }
        }
      }
      ShapePath {   // gloss
        fillColor: Qt.rgba(1, 1, 1, 0.5)
        strokeColor: "transparent"
        PathSvg {
          path: {
            var w = monster.width, h = monster.height
            return "M " + (0.1 * w) + " " + (0.42 * h) + " Q " + (0.12 * w) + " " + (0.12 * h) + " " + (0.34 * w) + " " + (0.08 * h)
              + " Q " + (0.16 * w) + " " + (0.18 * h) + " " + (0.13 * w) + " " + (0.42 * h) + " Z"
          }
        }
      }
    }

    // ---- the eye: album art iris --------------------------------------------
    Item {
      id: eye
      x: 22
      y: 18
      width: 70
      height: 70
      readonly property bool blink: !monster.playing && ((monster.t * 0.2) % 1) < 0.04

      Rectangle { anchors.fill: parent; radius: width / 2; color: monster.paper; border.color: monster.ink; border.width: 2 }
      ClippingRectangle {
        anchors.centerIn: parent
        width: 52
        height: 52
        radius: 26
        color: monster.ink
        // look around a little with the beat
        anchors.horizontalCenterOffset: Math.sin(monster.t * 1.1) * 3
        anchors.verticalCenterOffset: Math.cos(monster.t * 0.8) * 2
        Image {
          anchors.fill: parent
          source: monster.player ? monster.player.trackArtUrl : ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          sourceSize: Qt.size(104, 104)
        }
        Rectangle { x: 8; y: 7; width: 9; height: 9; radius: 4.5; color: Qt.rgba(1, 1, 1, 0.75) }   // catchlight
      }
      // eyelid for blinks
      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: monster.body
        border.color: monster.ink
        border.width: 2
        visible: eye.blink
      }
    }

    // ---- track + controls ----------------------------------------------------
    Column {
      x: eye.x + eye.width + 14
      y: 22
      width: monster.width - x - 22
      spacing: 3
      Text {
        width: parent.width
        text: monster.player ? (monster.player.trackTitle || monster.player.identity) : ""
        elide: Text.ElideRight
        color: monster.ink
        font.family: monster.cc.font
        font.pixelSize: 13
        font.weight: Font.Black
      }
      Text {
        width: parent.width
        text: monster.player ? (monster.player.trackArtist || monster.player.identity) : ""
        elide: Text.ElideRight
        color: monster.ink
        font.family: monster.cc.font
        font.pixelSize: 11
        opacity: 0.75
      }
      Row {
        spacing: 18
        topPadding: 6
        Repeater {
          model: [
            ["", "previous"],
            [monster.playing ? "" : "", "togglePlaying"],
            ["", "next"]
          ]
          Text {
            required property var modelData
            text: modelData[0]
            color: monster.ink
            font.family: monster.cc.font
            font.pixelSize: 17
            scale: controlHover.hovered ? 1.2 : 1
            Behavior on scale { NumberAnimation { duration: 150 } }
            HoverHandler { id: controlHover }
            MouseArea {
              anchors.fill: parent
              anchors.margins: -6
              cursorShape: Qt.PointingHandCursor
              onClicked: if (monster.player) monster.player[parent.modelData[1]]()
            }
          }
        }
      }
    }

    // ---- mouth: pointed teeth = playback timer ------------------------------
    Item {
      id: mouth
      x: 26
      y: 104
      width: monster.width - 52
      height: 26

      readonly property int teeth: Math.max(8, Math.floor(width / 11))
      readonly property real step: width / teeth
      // teeth up to this index have been "played"; with no known length a
      // three-tooth chomp sweeps across while playing
      readonly property int eaten: monster.knownLength ? Math.round(monster.progress * teeth) : 0
      readonly property int chomp: monster.playing && !monster.knownLength ? Math.floor(monster.t * 6) % (teeth + 3) : -10

      function jaw(upper, from, to) {
        var d = ""
        for (var i = from; i < to; i++) {
          var x0 = i * step, x1 = x0 + step, mid = x0 + step / 2
          if (upper) d += "M " + x0 + " 2 L " + mid + " " + (height * 0.52) + " L " + x1 + " 2 Z "
          else d += "M " + x0 + " " + (height - 2) + " L " + mid + " " + (height * 0.48) + " L " + x1 + " " + (height - 2) + " Z "
        }
        return d
      }

      Rectangle {   // the mouth hole
        anchors.fill: parent
        radius: height / 2
        color: monster.ink
      }
      Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {   // teeth still to come: dull
          fillColor: Qt.rgba(monster.paper.r, monster.paper.g, monster.paper.b, 0.28)
          strokeColor: monster.ink
          strokeWidth: 0.8
          PathSvg { path: mouth.jaw(true, mouth.eaten, mouth.teeth) + mouth.jaw(false, mouth.eaten, mouth.teeth) }
        }
        ShapePath {   // played teeth: bright
          fillColor: monster.paper
          strokeColor: monster.ink
          strokeWidth: 0.8
          PathSvg {
            path: {
              var a = Math.max(0, mouth.chomp - 3), b = Math.min(mouth.teeth, Math.max(0, mouth.chomp))
              return mouth.jaw(true, 0, mouth.eaten) + mouth.jaw(false, 0, mouth.eaten)
                + (b > a ? mouth.jaw(true, a, b) + mouth.jaw(false, a, b) : "")
            }
          }
        }
      }
      MouseArea {
        anchors.fill: parent
        enabled: monster.knownLength && monster.player.canSeek
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: mouse => monster.player.position = mouse.x / width * monster.player.length
      }
    }

    Text {
      x: mouth.x + 2
      y: mouth.y + mouth.height + 4
      text: monster.player ? monster.clockText(monster.player.position) : ""
      color: monster.ink
      font.family: monster.cc.font
      font.pixelSize: 10
      font.bold: true
    }
    Text {
      x: mouth.x + mouth.width - implicitWidth - 2
      y: mouth.y + mouth.height + 4
      text: monster.knownLength ? monster.clockText(monster.player.length) : ""
      color: monster.ink
      font.family: monster.cc.font
      font.pixelSize: 10
      font.bold: true
      opacity: 0.7
    }
  }
}
