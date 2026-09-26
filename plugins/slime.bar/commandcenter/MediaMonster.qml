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

  implicitHeight: 180

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

    // ---- body: the bar's own slime shader as a free-standing blob -----------
    // Same shading style as the bar (print/anime/manga/soft), with the
    // gradient flipped so the monster stands out from the ooze it sits in.
    ShaderEffect {
      x: -20
      y: -10
      width: monster.width + 40
      height: monster.height + 90
      fragmentShader: Qt.resolvedUrl("../shaders/slime.frag.qsb")

      readonly property var bar: monster.cc.bar
      property real blobMode: 1
      property real time: bar.animTime
      property real barHeight: 10
      property real openProgress: 1
      property real dripAmount: bar.dripAmount
      property real shadingStyle: bar.shadingStyle
      property vector2d resolution: Qt.vector2d(width, height)
      property vector4d panelRect: Qt.vector4d(20, 10, monster.width, monster.height - 4)
      property color slimeColor: bar.slimeColor2
      property color slimeColor2: bar.slimeColor
      property color paperColor: bar.paperColor
    }

    // ---- debris adrift in the goo: spare eyes, bones, a tooth, bubbles -------
    // Kept to the margins and faint enough that the track text stays clear.
    Repeater {
      model: [
        { kind: "eye", x: 0.9, y: 0.2, s: 12, sp: 0.5 },
        { kind: "bone", x: 0.78, y: 0.08, s: 16, sp: 0.35 },
        { kind: "eye", x: 0.06, y: 0.62, s: 9, sp: 0.7 },
        { kind: "tooth", x: 0.93, y: 0.56, s: 9, sp: 0.6 },
        { kind: "bubble", x: 0.52, y: 0.06, s: 7, sp: 0.9 },
        { kind: "bubble", x: 0.66, y: 0.58, s: 5, sp: 1.2 },
        { kind: "eye", x: 0.42, y: 0.58, s: 7, sp: 0.8 },
        { kind: "bone", x: 0.2, y: 0.9, s: 13, sp: 0.45 }
      ]
      Item {
        id: bit
        required property var modelData
        required property int index
        readonly property real drift: monster.t * modelData.sp + index * 1.9
        width: modelData.s * 1.5
        height: modelData.s * 1.5
        x: modelData.x * monster.width - width / 2 + Math.sin(drift) * 5
        y: modelData.y * monster.height - height / 2 + Math.cos(drift * 0.8) * 4
        rotation: Math.sin(drift * 0.6) * 40
        opacity: 0.8

        // spare eyeball, looking somewhere else
        Rectangle {
          visible: bit.modelData.kind === "eye"
          anchors.fill: parent
          radius: width / 2
          color: monster.paper
          border.color: monster.ink
          border.width: 1
          Rectangle {
            width: parent.width * 0.45; height: width; radius: width / 2
            x: parent.width * 0.3 + Math.sin(bit.drift * 1.7) * parent.width * 0.15
            y: parent.height * 0.28
            color: monster.ink
          }
        }
        Shape {
          visible: bit.modelData.kind !== "eye"
          anchors.fill: parent
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            fillColor: bit.modelData.kind === "bubble" ? Qt.rgba(1, 1, 1, 0.35) : monster.paper
            strokeColor: monster.ink
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
      y: 98
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
