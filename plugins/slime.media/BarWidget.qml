import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "../slime.bar/ui"
import "../slime.bar/commandcenter"

// SlimeS-Karaoke (was SlimeS-Media): a caster conjuring the music — the ooze
// visualizer pours out of the raised hand in the theme's colours while
// something plays — followed by previous / play / next as bobbing cream
// bubbles. That's its idle form. Left-click the caster (or the visualizer) to
// wake the karaoke: each line of the song's lyrics drips out of the bar under
// the widget, hangs for as long as it's sung, then bursts as the next line
// drips down. Hover for a drip card with the track and a choice of media
// source, scroll to skip tracks, right-click for the characters, the
// visualizer and the lyrics (the whole song's, refresh). Hidden when nothing
// is playing. Lyrics come from LRCLIB (lyrics.py; cached).
// Settings (shell.json):
//   visualizer  true/false (default true)
//   caster      lich (default), wizard, priest, dryad, witch, slimecaster, wisp
//   follow      "" follows whatever's playing, or a player's name to stick to it
//   karaoke     true/false: the lyric drips (default false)
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
  readonly property var casters: [["lich", "lich"], ["wizard", "wizard"], ["priest", "priest"], ["dryad", "dryad"],
                                  ["witch", "witch"], ["slimecaster", "slime"], ["wisp", "wisp"]]
  readonly property string caster: casters.some(function(c) { return c[0] === setting("caster", "lich") }) ? setting("caster", "lich") : "lich"
  readonly property string casterName: casters.filter(function(c) { return c[0] === caster })[0][1]
  // the spell's colours, from the theme: each caster has its own magic
  readonly property var spellColors: caster === "wizard"
    ? [pal.bright_cyan || "#10ffd9", pal.cyan || "#00c2c7", pal.bright_blue || "#6695ff", pal.blue || "#3f74ff", pal.bright_magenta || "#ff69c1"]
    : caster === "priest"
    ? [pal.bright_yellow || "#ffe14d", pal.yellow || "#e4cc00", "#fff6d0", pal.bright_white || "#ffffff", pal.bright_yellow || "#ffe14d"]
    : caster === "dryad"
    ? [pal.bright_green || "#7dff6a", pal.green || "#3fb950", pal.bright_yellow || "#ffe14d", pal.bright_magenta || "#ff9ad5", pal.green || "#3fb950"]
    : caster === "witch"
    ? [pal.bright_green || "#7dff6a", pal.green || "#3fb950", pal.bright_magenta || "#ff69c1", pal.magenta || "#8a4dff", pal.bright_green || "#7dff6a"]
    : caster === "slimecaster"
    ? [slime ? bar.slimeColor : "#5fd35f", pal.bright_cyan || "#10ffd9", pal.bright_yellow || "#ffe14d", slime ? bar.slimeColor2 : "#5fd35f", pal.bright_magenta || "#ff69c1"]
    : caster === "wisp"
    ? [pal.bright_cyan || "#10ffd9", pal.bright_blue || "#6695ff", "#ffffff", pal.cyan || "#00c2c7", pal.bright_blue || "#6695ff"]
    : [pal.bright_magenta || "#ff69c1", pal.magenta || "#f52e9b",
       pal.bright_blue || "#6695ff", pal.bright_cyan || "#10ffd9", pal.bright_yellow || "#e4cc00"]

  property bool settingsOpen: false
  function close() { settingsOpen = false; lyricsOpen = false }

  // ================================================================ karaoke
  readonly property bool karaoke: setting("karaoke", false) === true
  function toggleKaraoke() { saveSetting("karaoke", !karaoke) }
  readonly property string lyricsScript: Qt.resolvedUrl("lyrics.py").toString().replace("file://", "")
  // the song, and its lyrics: {status: synced|plain|instrumental|none|error, lines, plain}
  readonly property string trackKey: player ? (player.trackArtist || "") + "\n" + (player.trackTitle || "") : ""
  property var lyrics: ({ status: "", lines: [], plain: "" })
  property string lyricsFor: ""
  property bool lyricsBusy: false
  readonly property bool lyricsWanted: (karaoke || lyricsOpen) && hasMedia
  function fetchLyrics(refresh) {
    if (!player || !player.trackTitle) return
    lyricsFor = trackKey
    lyricsBusy = true
    lyricsProc.command = ["python3", lyricsScript, player.trackArtist || "", player.trackTitle || "",
      player.trackAlbum || "", player.length > 0 ? String(Math.round(player.length)) : ""].concat(refresh ? ["--refresh"] : [])
    lyricsProc.running = true
  }
  onTrackKeyChanged: { lyrics = { status: "", lines: [], plain: "" }; lineIndex = -1; if (lyricsWanted) lyricsDelay.restart() }
  onLyricsWantedChanged: if (lyricsWanted && lyricsFor !== trackKey) lyricsDelay.restart()
  // metadata tends to arrive in pieces as a song changes: settle first
  Timer { id: lyricsDelay; interval: 600; onTriggered: if (!lyricsProc.running) root.fetchLyrics(false) }
  Process {
    id: lyricsProc
    stdout: StdioCollector {
      onStreamFinished: {
        root.lyricsBusy = false
        try { root.lyrics = JSON.parse(text) } catch (e) { root.lyrics = { status: "error", lines: [], plain: "" } }
        root.hintShown = true; hintTimer.restart()
      }
    }
  }
  // where the song is (MPRIS doesn't push position: ask a few times a second)
  property real pos: 0
  Timer {
    interval: 200; repeat: true
    running: root.lyricsWanted && root.playing
    onTriggered: if (root.player) { root.player.positionChanged(); root.pos = root.player.position }
  }
  // the line being sung (a hair early, so it drips in on the word)
  property int lineIndex: -1
  readonly property int lineNow: {
    var ls = lyrics.lines || [], p = pos + 0.25, i = -1
    for (var k = 0; k < ls.length; k++) { if (ls[k].t <= p) i = k; else break }
    return i
  }
  onLineNowChanged: if (karaoke && lyrics.status === "synced") showLine(lineNow >= 0 ? lyrics.lines[lineNow].text : "")
  onKaraokeChanged: {
    if (karaoke) { if (lyrics.status === "synced") showLine(lineNow >= 0 ? lyrics.lines[lineNow].text : ""); hintShown = true; hintTimer.restart() }
    else showLine("")
  }
  // a note when there's nothing to sing along to
  property bool hintShown: false
  Timer { id: hintTimer; interval: 4500; onTriggered: root.hintShown = false }
  readonly property string hint: !karaoke || !hasMedia ? ""
    : lyricsBusy || lyrics.status === "" ? "♪ finding the words…"
    : lyrics.status === "instrumental" ? "♪ instrumental — nothing to sing"
    : lyrics.status === "none" ? "♪ no lyrics found for this one"
    : lyrics.status === "error" ? "♪ couldn't reach the lyrics (offline?)"
    : lyrics.status === "plain" ? "♪ no timed lyrics — right-click → the whole song"
    : ""

  // two drips take turns: the new line drips down while the old one falls and bursts
  property int turn: 0
  property var currentDrip: null
  function showLine(text) {
    var old = turn === 0 ? dripA : dripB, next = turn === 0 ? dripB : dripA
    old.shown = false
    if (text !== "") { next.line = text; next.shown = true; currentDrip = next }
    else currentDrip = null
    turn = 1 - turn
  }
  // how far through the current line (to its next line, or a few seconds)
  readonly property real lineProgress: {
    var ls = lyrics.lines || [], i = lineNow
    if (i < 0 || i >= ls.length) return 0
    var t0 = ls[i].t, t1 = i + 1 < ls.length ? ls[i + 1].t : t0 + 5
    return Math.max(0, Math.min(1, (pos - t0) / Math.max(0.5, t1 - t0)))
  }
  onLineProgressChanged: if (currentDrip && currentDrip.shown) currentDrip.sink = lineProgress
  onPlayingChanged: if (!playing && karaoke) { dripA.shown = false; dripB.shown = false }
  onHasMediaChanged: if (!hasMedia) { dripA.shown = false; dripB.shown = false }
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
    function karaoke(): void { root.toggleKaraoke() }
    function lyrics(): void { root.lyricsOpen = !root.lyricsOpen }
    // which player to follow: its name, or "" for whatever's playing
    function follow(name: string): void { root.saveSetting("follow", name) }
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
      // karaoke on: a note bubble sings off the caster's shoulder (off: none)
      Rectangle {
        id: singing
        visible: root.karaoke
        x: -5; y: -3
        width: 13; height: 13; radius: 6.5
        color: root.paper
        border.color: root.ink; border.width: 1.2
        scale: 0.9 + 0.12 * Math.sin(root.t * 4)
        Text {
          anchors.centerIn: parent
          text: "♪"
          color: root.ink
          font.pixelSize: 10; font.bold: true
        }
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
          else root.toggleKaraoke()
        }
        onWheel: wheel => { if (!root.player) return; if (wheel.angleDelta.y > 0) root.player.previous(); else root.player.next() }
      }
    }

    SlimeCava {
      id: viz
      visible: root.showViz && root.slime && !root.vertical
      active: root.playing
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
          if (!root.slime) return
          if (mouse.button === Qt.RightButton) root.settingsOpen = !root.settingsOpen
          else root.toggleKaraoke()
        }
      }
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
          model: root.casters
          CcButton {
            required property var modelData
            cc: look
            text: modelData[1]
            on: root.caster === modelData[0]
            onClicked: root.saveSetting("caster", modelData[0])
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
      CcHeading { cc: look; text: "KARAOKE (LEFT-CLICK THE " + root.casterName.toUpperCase() + ")" }
      Flow {
        width: parent.width
        spacing: 6
        CcButton { cc: look; text: "singing"; on: root.karaoke; onClicked: if (!root.karaoke) root.toggleKaraoke() }
        CcButton { cc: look; text: "idle"; on: !root.karaoke; onClicked: if (root.karaoke) root.toggleKaraoke() }
        CcButton { cc: look; icon: "\uf15c"; text: "the whole song"; onClicked: { root.settingsOpen = false; root.lyricsOpen = true } }
        CcButton { cc: look; icon: "\uf021"; text: root.lyricsBusy ? "looking…" : "refresh lyrics"; onClicked: root.fetchLyrics(true) }
      }
      CcHeading { cc: look; text: "FOLLOW" }
      Flow {
        width: parent.width
        spacing: 6
        CcButton { cc: look; text: "auto"; on: root.source === ""; onClicked: root.saveSetting("follow", "") }
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
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "Left-click the " + root.casterName + " (or the visualizer) to start or stop the karaoke: the lyrics drip out of the bar line by line. Hover for what's playing (space or middle-click plays/pauses, m mutes); scroll to skip tracks. Lyrics from lrclib.net."
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

  // ---- the lyric drips: one line at a time, oozing out of the bar ----
  component LyricDrip: SlimePopupCard {
    id: drip
    property string line: ""
    property bool shown: false
    // how far through its line (0..1): the bead sinks as it's sung
    property real sink: 0
    Behavior on sink { enabled: drip.shown; NumberAnimation { duration: 220 } }
    // letting go: 0..1 — the neck snaps, it falls and bursts
    property real fall: 0
    property bool falling: false
    readonly property real wordBurst: Math.max(0, Math.min(1, (fall - 0.4) / 0.6))
    property NumberAnimation fallAnim: NumberAnimation {
      target: drip; property: "fall"; from: 0; to: 1; duration: 560; easing.type: Easing.InQuad
      onFinished: drip.falling = false
    }
    onShownChanged: {
      if (shown) { fallAnim.stop(); falling = false; fall = 0; sink = 0 }
      else if (open) { falling = true; fallAnim.restart() }
    }
    anchorItem: root
    owner: hoverOwner
    bar: root.bar
    triggerMode: "hover"
    clickThrough: true
    padding: 0
    open: (shown || falling) && root.karaoke && root.hasMedia
    // the bead: the line with room round it; below it, room to sink into
    readonly property real textW: Math.min(measure.implicitWidth + 2, 520)
    readonly property real textH: lineWords.implicitHeight
    readonly property real beadW: textW + 46
    readonly property real beadH: textH + 30
    readonly property real room: 84
    readonly property real sinkPx: room * sink
    dropShape: Qt.vector4d(1, sinkPx, fall, beadH)
    contentWidth: drip.fittedContentWidth(beadW, 600)
    contentHeight: beadH + room + 24
    // where the bead is in this card (the shader hangs it from the bar's edge)
    readonly property bool fromBottom: root.bar && root.bar.position === "bottom"
    readonly property real beadTop: 8 - drip.neck + sinkPx + fall * fall * 240
    Text {
      id: measure
      visible: false
      text: drip.line
      font.family: root.bar ? root.bar.displayFontFamily : look.font
      font.weight: root.bar ? root.bar.displayWeight : Font.Bold
      font.pixelSize: 17
      font.wordSpacing: 2
    }
    Flow {
      id: lineWords
      width: drip.textW
      x: (drip.contentWidth - width) / 2
      y: drip.fromBottom ? drip.contentHeight - drip.beadTop - drip.beadH + (drip.beadH - height) / 2
                         : drip.beadTop + (drip.beadH - height) / 2
      spacing: 6
      Repeater {
        model: drip.line.split(/\s+/).filter(function(w) { return w !== "" })
        Text {
          id: word
          required property string modelData
          required property int index
          readonly property real a: index * 2.4 + drip.line.length
          text: modelData
          color: look.ink
          font.family: root.bar ? root.bar.displayFontFamily : look.font
          font.weight: root.bar ? root.bar.displayWeight : Font.Bold
          font.pixelSize: 17
          opacity: 1 - drip.wordBurst
          transform: [
            Rotation { angle: Math.sin(word.a) * 70 * drip.wordBurst; origin.x: word.width / 2; origin.y: word.height / 2 },
            Translate { x: Math.cos(word.a) * 40 * drip.wordBurst; y: (Math.sin(word.a) * 22 + 10) * drip.wordBurst }
          ]
          scale: 1 + 0.4 * drip.wordBurst
        }
      }
    }
  }
  LyricDrip { id: dripA }
  LyricDrip { id: dripB }
  // a one-off note (finding the words, none found, …)
  SlimePopupCard {
    id: hintDrip
    anchorItem: root
    owner: hoverOwner
    bar: root.bar
    triggerMode: "hover"
    clickThrough: true
    open: root.hintShown && root.hint !== "" && !dripA.open && !dripB.open && !root.hoverOpen && !root.settingsOpen
    contentWidth: hintDrip.fittedContentWidth(hintText.implicitWidth + 2 * hintDrip.padding + 8, 420)
    contentHeight: hintDrip.fittedContentHeight(hintText.implicitHeight)
    Text {
      id: hintText
      anchors.centerIn: parent
      text: root.hint
      color: look.ink; font.family: look.font; font.pixelSize: 12; font.bold: true
    }
  }

  // ---- the whole song: a big drip with every line (right-click → the whole song) ----
  property bool lyricsOpen: false
  onLyricsOpenChanged: if (lyricsOpen) { settingsOpen = false; hoverOpen = false }
  QtObject { id: lyricsOwner; function close() { root.lyricsOpen = false } }
  SlimePopupCard {
    id: songCard
    anchorItem: root
    owner: lyricsOwner
    bar: root.bar
    open: root.lyricsOpen && root.hasMedia
    contentWidth: Style.space(420)
    contentHeight: songCard.fittedContentHeight(560, 620)
    Column {
      anchors.fill: parent
      spacing: 8
      Row {
        width: parent.width
        spacing: 6
        Column {
          width: parent.width - refreshBtn.width - closeBtn.width - 12
          Text {
            width: parent.width; elide: Text.ElideRight
            text: root.player ? (root.player.trackTitle || root.player.identity) : ""
            color: look.ink; font.family: root.bar ? root.bar.displayFontFamily : look.font; font.pixelSize: 16; font.bold: true
          }
          Text {
            width: parent.width; elide: Text.ElideRight
            text: root.player ? root.player.trackArtist : ""
            color: look.ink; font.family: look.font; font.pixelSize: 11; opacity: 0.75
          }
        }
        CcButton { id: refreshBtn; cc: look; icon: "\uf021"; text: root.lyricsBusy ? "…" : "refresh"; fontSize: 10; onClicked: root.fetchLyrics(true) }
        CcButton { id: closeBtn; cc: look; icon: "\uf00d"; fontSize: 10; onClicked: root.lyricsOpen = false }
      }
      Flow {
        width: parent.width
        spacing: 6
        CcButton { cc: look; text: "auto"; fontSize: 10; on: root.source === ""; onClicked: root.saveSetting("follow", "") }
        Repeater {
          model: root.players
          CcButton {
            required property var modelData
            cc: look; fontSize: 10
            text: modelData.identity || modelData.dbusName
            on: root.source !== "" && root.source === modelData.identity
            onClicked: root.saveSetting("follow", modelData.identity)
          }
        }
      }
      ListView {
        id: songLines
        width: parent.width
        height: parent.height - y
        clip: true
        spacing: 4
        boundsBehavior: Flickable.StopAtBounds
        readonly property bool synced: root.lyrics.status === "synced"
        model: synced ? root.lyrics.lines : (root.lyrics.plain || "").split("\n")
        currentIndex: synced ? root.lineNow : -1
        onCurrentIndexChanged: if (currentIndex >= 0 && !moving) positionViewAtIndex(currentIndex, ListView.Center)
        delegate: Text {
          required property var modelData
          required property int index
          readonly property bool now: songLines.synced && index === root.lineNow
          width: songLines.width
          wrapMode: Text.Wrap
          text: songLines.synced ? (modelData.text || "♪") : (modelData || " ")
          color: look.ink
          opacity: now ? 1 : songLines.synced && index < root.lineNow ? 0.45 : 0.75
          font.family: now && root.bar ? root.bar.displayFontFamily : look.font
          font.pixelSize: now ? 15 : 13
          font.bold: now
          // click a line to jump there (when the player can seek)
          MouseArea {
            anchors.fill: parent
            enabled: songLines.synced && !!root.player && root.player.canSeek
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.player.position = parent.modelData.t
          }
        }
        Text {
          anchors.centerIn: parent
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
          visible: songLines.count === 0 || (songLines.count === 1 && !songLines.synced && !root.lyrics.plain)
          text: root.lyricsBusy || root.lyrics.status === "" ? "finding the words…"
            : root.lyrics.status === "instrumental" ? "an instrumental — no words"
            : root.lyrics.status === "error" ? "couldn't reach the lyrics (offline?)"
            : "no lyrics found for this one"
          color: look.ink; font.family: look.font; font.pixelSize: 13; opacity: 0.7
        }
      }
    }
  }
}
