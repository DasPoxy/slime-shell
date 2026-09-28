import QtQuick
import QtQuick.Shapes
import Quickshell.Widgets
import "../ui"

// The media player as a slime monster: a cyclops whose eye is the album art,
// with the track on its forehead, the controls beside it, and a mouth of
// pointed teeth that doubles as the playback timer — teeth turn white as the
// track plays. Click the mouth to seek. Players that don't report a track
// length (browsers, often) get a chomping wave instead of a fake progress.
Item {
  id: monster
  // the command centre's text size (Settings → Command centre → text size)
  readonly property real fs: cc && cc.fontScale ? cc.fontScale : 1

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
      // every shader uniform set explicitly: unset ones are not guaranteed to be 0
      property vector4d cullRect: Qt.vector4d(0, 0, 0, 0)
      property real clipTop: -100000
      property real poolDepth: 0
      property vector2d origin: Qt.vector2d(0, 0)
      property vector4d bulb0: Qt.vector4d(0, 0, 0, 0)
      property vector4d bulb1: Qt.vector4d(0, 0, 0, 0)
      property vector4d bulb2: Qt.vector4d(0, 0, 0, 0)
      property vector4d bulb3: Qt.vector4d(0, 0, 0, 0)
      property vector4d bulb4: Qt.vector4d(0, 0, 0, 0)
      property vector4d bulb5: Qt.vector4d(0, 0, 0, 0)
      property vector4d bulb6: Qt.vector4d(0, 0, 0, 0)
      property vector4d bulb7: Qt.vector4d(0, 0, 0, 0)
      property vector4d bulb8: Qt.vector4d(0, 0, 0, 0)
      property vector4d bulb9: Qt.vector4d(0, 0, 0, 0)
      property vector4d bulb10: Qt.vector4d(0, 0, 0, 0)
      property vector4d bulb11: Qt.vector4d(0, 0, 0, 0)
      property vector4d bulb12: Qt.vector4d(0, 0, 0, 0)
      property vector4d bulb13: Qt.vector4d(0, 0, 0, 0)
      property vector4d bulb14: Qt.vector4d(0, 0, 0, 0)
      property vector4d bulb15: Qt.vector4d(0, 0, 0, 0)
      property vector4d bulb16: Qt.vector4d(0, 0, 0, 0)
      property vector4d bulb17: Qt.vector4d(0, 0, 0, 0)
      property vector4d bulb18: Qt.vector4d(0, 0, 0, 0)
      property vector4d bulb19: Qt.vector4d(0, 0, 0, 0)
      property vector4d bulb20: Qt.vector4d(0, 0, 0, 0)
      property vector4d bulb21: Qt.vector4d(0, 0, 0, 0)
      property vector4d bulb22: Qt.vector4d(0, 0, 0, 0)
      property vector4d bulb23: Qt.vector4d(0, 0, 0, 0)

      readonly property var bar: monster.cc.bar
      property real blobMode: 1
      property real orient: 0
      property vector2d screenSize: Qt.vector2d(0, 0)
      property real barShape: 0
      property real material: bar.materialId   // the monster is made of the same stuff as the bar
      property vector4d dripStyle: bar.dripStyleVec
      property vector4d dripExtra: bar.dripExtraVec
      property vector4d cava0: bar ? bar.cava0 : Qt.vector4d(0, 0, 0, 0)
      property vector4d cava1: bar ? bar.cava1 : Qt.vector4d(0, 0, 0, 0)
      property vector4d cava2: bar ? bar.cava2 : Qt.vector4d(0, 0, 0, 0)
      property vector4d cava3: bar ? bar.cava3 : Qt.vector4d(0, 0, 0, 0)
      property vector4d cavaOpts: bar ? bar.cavaOpts : Qt.vector4d(0, 0, 0, 0)
      property vector4d dockBracket: Qt.vector4d(0, 0, 0, 0)
      property vector4d dropShape: Qt.vector4d(0, 0, 0, 0)
      property vector4d eggDrip: Qt.vector4d(0, 0, 0, 0)
      property vector4d group0: Qt.vector4d(0, 0, 0, 0)
      property vector4d group1: Qt.vector4d(0, 0, 0, 0)
      property vector4d group2: Qt.vector4d(0, 0, 0, 0)
      property real time: bar.animTime
      property real barHeight: 10
      property real openProgress: 1
      property real dripAmount: bar.dripLevel
      property real shadingStyle: bar.shadingStyle
      property vector2d resolution: Qt.vector2d(width, height)
      property vector4d panelRect: Qt.vector4d(20, 10, monster.width, monster.height - 4)
      property color slimeColor: bar.slimeColor2
      property color slimeColor2: bar.slimeColor
      property color paperColor: bar.paperColor
    }

    // ---- the music, as goo rising inside the monster -------------------------
    SlimeCava {
      x: 16
      y: 34
      width: monster.width - 32
      height: 64
      active: monster.playing
      bars: 24
      gap: 3
      fill: monster.ink
      // theme colours sweeping across the goo, bright but see-through so
      // the track text on top stays readable
      readonly property var pal: monster.cc.bar.palette || ({})
      colors: [pal.bright_magenta || "#ff69c1", pal.bright_blue || "#6695ff", pal.bright_cyan || "#10ffd9",
        pal.bright_green || "#3dff41", pal.bright_yellow || "#e4cc00", pal.bright_red || "#ff5155"]
      colorAlpha: 0.5
      opacity: monster.playing ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 500 } }
    }

    // ---- debris adrift in the goo, kept to the margins -----------------------
    SlimeDebris {
      anchors.fill: parent
      bar: monster.cc.bar
      maxGrow: 1.5
      bits: [
        { kind: "eye", x: 0.9, y: 0.2, s: 18, sp: 0.5 },
        { kind: "bone", x: 0.78, y: 0.08, s: 24, sp: 0.35 },
        { kind: "eye", x: 0.06, y: 0.62, s: 13, sp: 0.7 },
        { kind: "tooth", x: 0.93, y: 0.56, s: 13, sp: 0.6 },
        { kind: "bubble", x: 0.52, y: 0.06, s: 10, sp: 0.9 },
        { kind: "bubble", x: 0.66, y: 0.58, s: 8, sp: 1.2 },
        { kind: "eye", x: 0.42, y: 0.58, s: 10, sp: 0.8 },
        { kind: "bone", x: 0.2, y: 0.9, s: 19, sp: 0.45 }
      ]
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
        font.pixelSize: Math.round(13 * monster.fs)
        font.weight: Font.Black
      }
      Text {
        width: parent.width
        text: monster.player ? (monster.player.trackArtist || monster.player.identity) : ""
        elide: Text.ElideRight
        color: monster.ink
        font.family: monster.cc.font
        font.pixelSize: Math.round(11 * monster.fs)
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
            font.pixelSize: Math.round(17 * monster.fs)
            scale: controlHover.hovered ? 1.2 : 1
            Behavior on scale { NumberAnimation { duration: 150 } }
            HoverHandler { id: controlHover }
            MouseArea {
              anchors.fill: parent
              anchors.margins: -6
              cursorShape: Qt.PointingHandCursor
              onClicked: if (monster.player) monster.player[parent.modelData[1]]()
            }
            CcFocus { anchors.margins: -6; onActivate: if (monster.player) monster.player[parent.modelData[1]]() }
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
      font.pixelSize: Math.round(10 * monster.fs)
      font.bold: true
    }
    Text {
      x: mouth.x + mouth.width - implicitWidth - 2
      y: mouth.y + mouth.height + 4
      text: monster.knownLength ? monster.clockText(monster.player.length) : ""
      color: monster.ink
      font.family: monster.cc.font
      font.pixelSize: Math.round(10 * monster.fs)
      font.bold: true
      opacity: 0.7
    }
  }

  // rest the pointer on the monster: space plays/pauses, m mutes
  SlimeMediaKeys {
    anchors.fill: parent
    bar: monster.cc.bar
    player: monster.player
  }
}
