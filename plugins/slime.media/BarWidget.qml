import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "../slime.bar/ui"
import "../slime.bar/commandcenter"

// Slime Shell now-playing widget: a caster (lich, wizard or priest)
// conjuring the music — the ooze visualizer pours out of the raised hand in
// the theme's colours while something plays — followed by previous / play /
// next as bobbing cream bubbles. Hover the caster for a drip card with the
// track and a choice of media source, click for the command centre, scroll to
// skip tracks, right-click for settings. Hidden when nothing is playing.
// Settings (shell.json):
//   visualizer  true/false (default true)
//   caster      "lich" (default), "wizard" or "priest"
//   follow      "" follows whatever's playing, or a player's name to stick to it
BarWidget {
  id: root
  moduleName: "slime.media"

  readonly property bool slime: !!bar && bar.slimeSkin === true
  // the player to follow ("" = whatever's playing). Not "source": in
  // shell.json that key tells the bar to load the widget from a file.
  readonly property string source: setting("follow", "")
  readonly property var players: Mpris.players.values
  readonly property var player: {
    var ps = players
    // a chosen source (by name, which stays the same across restarts)
    if (source !== "") for (var k = 0; k < ps.length; k++) if (ps[k].identity === source) return ps[k]
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
  readonly property string caster: ["lich", "wizard", "priest"].indexOf(setting("caster", "lich")) >= 0 ? setting("caster", "lich") : "lich"
  // the spell's colours, from the theme: each caster has its own magic
  readonly property var spellColors: caster === "wizard"
    ? [pal.bright_cyan || "#10ffd9", pal.cyan || "#00c2c7", pal.bright_blue || "#6695ff", pal.blue || "#3f74ff", pal.bright_magenta || "#ff69c1"]
    : caster === "priest"
    ? [pal.bright_yellow || "#ffe14d", pal.yellow || "#e4cc00", "#fff6d0", pal.bright_white || "#ffffff", pal.bright_yellow || "#ffe14d"]
    : [pal.bright_magenta || "#ff69c1", pal.magenta || "#f52e9b",
       pal.bright_blue || "#6695ff", pal.bright_cyan || "#10ffd9", pal.bright_yellow || "#e4cc00"]

  property bool settingsOpen: false
  function close() { settingsOpen = false }
  onSettingsOpenChanged: if (settingsOpen) hoverOpen = false

  // ---- the hover card: opens after a moment over the caster, stays while the
  // pointer is on the caster or the card, closes a moment after it leaves
  property bool hoverOpen: false
  readonly property bool hoverWanted: casterHover.hovered || nowCard.containsMouse
  onHoverWantedChanged: {
    if (hoverWanted) { hoverClose.stop(); if (!hoverOpen) hoverDelay.restart() }
    else { hoverDelay.stop(); hoverClose.restart() }
  }
  Timer { id: hoverDelay; interval: 350; onTriggered: if (root.hasMedia && !root.settingsOpen && root.slime) root.hoverOpen = true }
  Timer { id: hoverClose; interval: 300; onTriggered: root.hoverOpen = false }
  QtObject { id: hoverOwner; function close() { root.hoverOpen = false } }
  // MPRIS doesn't push position updates; poll while the card shows
  Timer {
    interval: 1000; repeat: true
    running: root.hoverOpen && root.playing
    onTriggered: if (root.player) root.player.positionChanged()
  }
  function clock(sec) {
    if (!(sec > 0)) return "0:00"
    sec = Math.floor(sec)
    var m = Math.floor(sec / 60), s = sec % 60
    return m + ":" + (s < 10 ? "0" : "") + s
  }
  function saveSetting(key, value) {
    var entry = { id: root.moduleName }
    // (never "source": the bar would try to load the widget from it)
    for (var k in root.settings) if (k !== "id" && k !== "source") entry[k] = root.settings[k]
    entry[key] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

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

    // the caster, and the spell coming off the raised hand
    Item {
      width: 30
      height: 30
      SlimeGear {
        anchors.fill: parent
        size: 30
        bar: root.bar
        kind: root.caster
        lit: root.playing
        transform: Translate { y: Math.sin(root.t * 1.3) * 1.2 }
      }
      HoverHandler {
        id: casterHover
        // off the slime skin there's no drip card: fall back to the tooltip
        onHoveredChanged: {
          if (!root.bar || root.slime) return
          if (hovered) root.bar.showTooltip(root, root.track)
          else root.bar.hideTooltip(root)
        }
      }
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
          if (!root.slime) return
          if (mouse.button === Qt.RightButton) root.settingsOpen = !root.settingsOpen
          else { root.bar.ccTab = "home"; root.bar.commandCenterOpen = true }
        }
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

  QtObject {
    id: look
    readonly property var bar: root.bar
    readonly property color ink: root.ink
    readonly property color slime: root.slime ? root.bar.slimeColor : Color.accent
    readonly property string font: root.bar ? root.bar.fontFamily : Style.font.family
  }

  SlimePopupCard {
    id: settingsCard
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.settingsOpen
    contentWidth: Style.space(240)
    contentHeight: settingsCard.fittedContentHeight(settingsColumn.implicitHeight)

    Column {
      id: settingsColumn
      anchors.fill: parent
      spacing: 8
      bottomPadding: 6
      CcHeading { cc: look; text: "WHO CASTS THE SPELL" }
      Flow {
        width: parent.width
        spacing: 6
        Repeater {
          model: ["lich", "wizard", "priest"]
          CcButton {
            required property string modelData
            cc: look
            text: modelData
            on: root.caster === modelData
            onClicked: root.saveSetting("caster", modelData)
          }
        }
      }
      CcHeading { cc: look; text: "THE SPELL (VISUALIZER)" }
      Flow {
        width: parent.width
        spacing: 6
        CcButton { cc: look; text: "casting"; on: root.showViz; onClicked: root.saveSetting("visualizer", true) }
        CcButton { cc: look; text: "resting"; on: !root.showViz; onClicked: root.saveSetting("visualizer", false) }
      }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "Hover the " + root.caster + " for what's playing and which player to follow (while hovering: space or middle-click plays/pauses, m mutes); left-click for the command centre; scroll to skip tracks."
        color: look.ink
        font.family: look.font
        font.pixelSize: 10
        opacity: 0.7
      }
    }
  }

  // rest the pointer on the widget: space plays/pauses, m mutes
  SlimeMediaKeys {
    anchors.fill: parent
    bar: root.bar
    player: root.player
    enabledKeys: root.slime
  }

  // ---- now playing: a drip card on hover ----
  SlimePopupCard {
    id: nowCard
    anchorItem: root
    owner: hoverOwner
    bar: root.bar
    triggerMode: "hover"
    open: root.hoverOpen && root.hasMedia
    contentWidth: Style.space(290)
    contentHeight: nowCard.fittedContentHeight(nowColumn.implicitHeight)

    Column {
      id: nowColumn
      anchors.fill: parent
      spacing: 8

      Row {
        width: parent.width
        spacing: 10
        // album art in an ink ring (a spell sigil when there isn't any)
        Rectangle {
          width: 64; height: 64; radius: 12
          color: look.slime
          border.color: look.ink; border.width: 1.6
          clip: true
          Image {
            anchors.fill: parent
            anchors.margins: 1.6
            source: root.player && root.player.trackArtUrl ? root.player.trackArtUrl : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: status === Image.Ready
          }
          SlimeGear {
            anchors.centerIn: parent
            visible: !(root.player && root.player.trackArtUrl)
            width: 40; height: 40; size: 40
            bar: root.bar
            kind: root.caster
            lit: root.playing
          }
        }
        Column {
          width: parent.width - 74
          spacing: 2
          anchors.verticalCenter: parent.verticalCenter
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: root.player ? (root.player.trackTitle || root.player.identity) : ""
            color: look.ink; font.family: look.font; font.pixelSize: 14; font.bold: true
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            visible: text !== ""
            text: root.player ? root.player.trackArtist : ""
            color: look.ink; font.family: look.font; font.pixelSize: 12
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            visible: text !== ""
            text: root.player ? root.player.trackAlbum : ""
            color: look.ink; font.family: look.font; font.pixelSize: 11; opacity: 0.7
          }
          Text {
            text: root.player ? root.player.identity + (root.playing ? " · playing" : " · paused") : ""
            color: look.ink; font.family: look.font; font.pixelSize: 10; opacity: 0.55
          }
        }
      }

      // how far through: an ink track filling with goo
      Item {
        width: parent.width
        height: 16
        visible: !!root.player && root.player.lengthSupported && root.player.length > 0
        readonly property real frac: root.player && root.player.length > 0 ? Math.max(0, Math.min(1, root.player.position / root.player.length)) : 0
        Rectangle {
          y: 2; width: parent.width; height: 6; radius: 3
          color: Qt.rgba(look.ink.r, look.ink.g, look.ink.b, 0.16)
          Rectangle { width: parent.width * parent.parent.frac; height: parent.height; radius: 3; color: look.ink }
        }
        Text {
          y: 8; text: root.clock(root.player ? root.player.position : 0)
          color: look.ink; font.family: look.font; font.pixelSize: 9; opacity: 0.7
        }
        Text {
          y: 8; anchors.right: parent.right; text: root.clock(root.player ? root.player.length : 0)
          color: look.ink; font.family: look.font; font.pixelSize: 9; opacity: 0.7
        }
      }

      CcHeading { cc: look; text: "FOLLOW" }
      Flow {
        width: parent.width
        spacing: 6
        CcButton {
          cc: look
          text: "auto"
          on: root.source === ""
          onClicked: root.saveSetting("follow", "")
        }
        Repeater {
          model: root.players
          CcButton {
            required property var modelData
            cc: look
            text: modelData.identity || modelData.dbusName
            on: root.source !== "" && root.source === modelData.identity
            onClicked: root.saveSetting("follow", modelData.identity)
          }
        }
      }
    }
  }
}
