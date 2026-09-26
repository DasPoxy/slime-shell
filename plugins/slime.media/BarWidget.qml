import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "../slime.bar/ui"

// Slime Shell now-playing widget: the album art as a spinning record, a
// scrolling "title · artist", a little ooze visualizer, and previous / play /
// next. Click the record to play/pause, the title to open the command centre,
// scroll to skip tracks. Hidden when nothing is playing. Settings (shell.json):
//   visualizer  true/false (default true)
//   maxWidth    title width in px (default 180)
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
  readonly property string title: player ? (player.trackTitle || player.identity) : ""
  readonly property string artist: player ? (player.trackArtist || "") : ""
  readonly property bool showViz: setting("visualizer", true) === true
  readonly property real maxLabelWidth: Number(setting("maxWidth", 180))
  readonly property color ink: slime ? bar.slimeInk : (bar ? bar.barForeground : Color.foreground)
  readonly property real t: slime ? bar.animTime : 0

  visible: hasMedia
  implicitWidth: hasMedia ? row.implicitWidth + 16 : 0
  implicitHeight: barSize

  IpcHandler {
    target: "slime-media"
    function toggle(): void { if (root.player) root.player.togglePlaying() }
    function next(): void { if (root.player) root.player.next() }
    function previous(): void { if (root.player) root.player.previous() }
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: 8

    // the record: album art in an ink ring, spinning while it plays
    Item {
      width: 24
      height: 24
      anchors.verticalCenter: parent.verticalCenter
      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: root.ink
      }
      ClippingRectangle {
        id: disc
        anchors.centerIn: parent
        width: 20; height: 20; radius: 10
        color: root.slime ? root.bar.monsterBody : "grey"
        RotationAnimator on rotation {
          running: root.playing
          loops: Animation.Infinite
          from: 0; to: 360
          duration: 6000
        }
        Image {
          anchors.fill: parent
          source: root.player ? root.player.trackArtUrl : ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          sourceSize: Qt.size(48, 48)
        }
      }
      Rectangle {   // spindle hole
        anchors.centerIn: parent
        width: 5; height: 5; radius: 2.5
        color: root.slime ? root.bar.paperColor : "white"
        border.color: root.ink
        border.width: 1
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.player) root.player.togglePlaying()
      }
    }

    // scrolling title
    Item {
      id: clip
      width: Math.min(root.maxLabelWidth, label.implicitWidth)
      height: 20
      clip: true
      anchors.verticalCenter: parent.verticalCenter
      Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        text: root.title + (root.artist ? "  ·  " + root.artist : "")
        color: root.ink
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: 13
        font.bold: true
        readonly property bool needsScroll: implicitWidth > clip.width
        NumberAnimation on x {
          running: label.needsScroll && root.playing
          loops: Animation.Infinite
          duration: Math.max(6000, label.implicitWidth * 28)
          from: clip.width
          to: -label.implicitWidth
        }
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.bar && root.bar.slimeSkin) { root.bar.ccTab = "home"; root.bar.commandCenterOpen = true }
        onWheel: wheel => { if (!root.player) return; if (wheel.angleDelta.y > 0) root.player.previous(); else root.player.next() }
      }
    }

    SlimeCava {
      visible: root.showViz && root.slime
      active: root.playing
      anchors.verticalCenter: parent.verticalCenter
      width: 34
      height: 20
      bars: 7
      gap: 1.5
      fill: root.ink
    }

    Row {
      spacing: 10
      anchors.verticalCenter: parent.verticalCenter
      Repeater {
        model: [["", "previous"], [root.playing ? "" : "", "togglePlaying"], ["", "next"]]
        Text {
          required property var modelData
          text: modelData[0]
          color: root.ink
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: 12
          scale: controlHover.hovered ? 1.25 : 1
          Behavior on scale { NumberAnimation { duration: 140 } }
          HoverHandler { id: controlHover }
          MouseArea {
            anchors.fill: parent
            anchors.margins: -5
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.player) root.player[parent.modelData[1]]()
          }
        }
      }
    }
  }
}
