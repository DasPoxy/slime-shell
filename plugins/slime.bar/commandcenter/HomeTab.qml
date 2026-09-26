import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Ui
import "../SlimeHub.js" as SlimeHub

// Home: clock & weather, quick toggles, sound, media on the left; calendar and
// recent notifications on the right.
Item {
  id: home

  property var cc: null
  readonly property real colWidth: (width - 20) / 2

  implicitHeight: Math.max(leftColumn.implicitHeight, rightColumn.implicitHeight)

  // ---- state polled while the command centre is open ---------------------
  property bool wifiOn: false
  property bool nightOn: false
  property bool awakeOn: false
  property var notif: null   // slime.notifications service, via the hub
  property var history: []

  function run(argv, then) {
    var p = runner.createObject(home, { command: argv })
    p.exited.connect(function() { if (then) then(); p.destroy() })
    p.running = true
  }
  Component { id: runner; Process {} }

  Process {
    id: stateProbe
    command: ["sh", "-c",
      "nmcli radio wifi 2>/dev/null; " +
      "omarchy-toggle-nightlight --status 2>/dev/null | jq -r '.enabled' || echo false; " +
      "[ -f \"$HOME/.local/state/omarchy/indicators/stay-awake\" ] && echo true || echo false"]
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = text.trim().split("\n")
        home.wifiOn = lines[0] === "enabled"
        home.nightOn = lines[1] === "true"
        home.awakeOn = lines[2] === "true"
      }
    }
  }

  Process {
    id: historyProbe
    command: ["sh", "-c",
      "ls -t \"$HOME/.local/state/omarchy/notifications/history\"/*.json 2>/dev/null | head -5 " +
      "| xargs -r -d '\\n' jq -c '{app, summary, body, timestamp, urgency}' 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        var out = []
        var lines = text.trim().split("\n")
        for (var i = 0; i < lines.length; i++) {
          if (!lines[i]) continue
          try { out.push(JSON.parse(lines[i])) } catch (e) {}
        }
        home.history = out
      }
    }
  }

  function refresh() {
    stateProbe.running = true
    historyProbe.running = true
    if (notif !== SlimeHub.notifications) notif = SlimeHub.notifications
  }
  Timer { interval: 3000; repeat: true; running: true; triggeredOnStart: true; onTriggered: home.refresh() }

  // ---- audio / media -------------------------------------------------------
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var source: Pipewire.defaultAudioSource
  PwObjectTracker { objects: [home.sink, home.source] }

  readonly property var player: {
    var ps = Mpris.players.values
    for (var i = 0; i < ps.length; i++) if (ps[i].isPlaying) return ps[i]
    return ps.length ? ps[0] : null
  }
  Timer {   // MPRIS positions don't tick on their own
    interval: 1000; repeat: true
    running: home.player !== null && home.player.isPlaying
    onTriggered: home.player.positionChanged()
  }

  function clockText(seconds) {
    seconds = Math.max(0, Math.floor(seconds || 0))
    return Math.floor(seconds / 60) + ":" + ("0" + seconds % 60).slice(-2)
  }

  function ago(ms) {
    var s = Math.max(0, (Date.now() - ms) / 1000)
    if (s < 60) return "now"
    if (s < 3600) return Math.floor(s / 60) + "m"
    if (s < 86400) return Math.floor(s / 3600) + "h"
    return Math.floor(s / 86400) + "d"
  }

  SystemClock { id: clock; precision: SystemClock.Seconds }

  // =========================================================================
  Column {
    id: leftColumn
    width: home.colWidth
    spacing: 12

    // clock & weather
    Row {
      spacing: 14
      Text {
        text: Qt.formatTime(clock.date, "HH:mm")
        color: home.cc.ink
        font.family: home.cc.font
        font.pixelSize: 46
        font.weight: Font.Black
      }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text {
          text: Qt.formatDate(clock.date, "dddd")
          color: home.cc.ink
          font.family: home.cc.font
          font.pixelSize: 15
          font.bold: true
        }
        Text {
          readonly property var weather: home.cc.widget("slime.clock-weather")
          text: Qt.formatDate(clock.date, "d MMMM yyyy") + (weather && weather.weatherText ? "   " + weather.weatherText : "")
          color: home.cc.ink
          font.family: home.cc.font
          font.pixelSize: 12
          opacity: 0.8
        }
      }
    }

    CcHeading { cc: home.cc; text: "QUICK TOGGLES" }
    Grid {
      id: toggles
      columns: 3
      spacing: 8
      readonly property real tileWidth: (home.colWidth - 16) / 3

      CcTile {
        cc: home.cc; width: toggles.tileWidth
        icon: ""; label: "Wi-Fi"; on: home.wifiOn
        onClicked: home.run(["nmcli", "radio", "wifi", home.wifiOn ? "off" : "on"], home.refresh)
      }
      CcTile {
        readonly property var adapter: Bluetooth.defaultAdapter
        cc: home.cc; width: toggles.tileWidth
        icon: ""; label: "Bluetooth"; on: !!adapter && adapter.enabled
        onClicked: if (adapter) adapter.enabled = !adapter.enabled
      }
      CcTile {
        cc: home.cc; width: toggles.tileWidth
        icon: ""; label: "Night light"; on: home.nightOn
        onClicked: home.run(["omarchy-toggle-nightlight"], function() { nightDelay.restart() })
        Timer { id: nightDelay; interval: 700; onTriggered: home.refresh() }
      }
      CcTile {
        cc: home.cc; width: toggles.tileWidth
        icon: ""; label: "Do not disturb"; on: !!home.notif && home.notif.doNotDisturb
        onClicked: if (home.notif) home.notif.setDoNotDisturb(!home.notif.doNotDisturb)
      }
      CcTile {
        cc: home.cc; width: toggles.tileWidth
        icon: ""; label: "Stay awake"; on: home.awakeOn
        onClicked: home.run(["omarchy-toggle-idle"], home.refresh)
      }
      CcTile {
        readonly property bool muted: !!home.source && !!home.source.audio && home.source.audio.muted
        cc: home.cc; width: toggles.tileWidth
        icon: muted ? "" : ""; label: muted ? "Mic muted" : "Mic on"; on: !muted
        onClicked: if (home.source && home.source.audio) home.source.audio.muted = !home.source.audio.muted
      }
    }

    CcHeading { cc: home.cc; text: "SOUND" }
    Repeater {
      model: [
        { node: home.sink, icon: "", mutedIcon: "", label: "Output" },
        { node: home.source, icon: "", mutedIcon: "", label: "Input" }
      ]
      Row {
        required property var modelData
        readonly property var audio: modelData.node ? modelData.node.audio : null
        visible: audio !== null
        spacing: 10
        Text {
          width: 22
          anchors.verticalCenter: parent.verticalCenter
          text: parent.audio && parent.audio.muted ? parent.modelData.mutedIcon : parent.modelData.icon
          color: home.cc.ink
          font.family: home.cc.font
          font.pixelSize: 16
          MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.parent.audio.muted = !parent.parent.audio.muted
          }
        }
        PanelSlider {
          anchors.verticalCenter: parent.verticalCenter
          width: home.colWidth - 22 - 50 - 20
          bar: home.cc.bar
          minimum: 0
          maximum: 1
          value: parent.audio ? parent.audio.volume : 0
          onMoved: v => { if (parent.audio) parent.audio.volume = v }
        }
        Text {
          width: 50
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignRight
          text: parent.audio ? Math.round(parent.audio.volume * 100) + "%" : ""
          color: home.cc.ink
          font.family: home.cc.font
          font.pixelSize: 12
          font.bold: true
        }
      }
    }

    // media
    Rectangle {
      visible: home.player !== null
      width: home.colWidth
      height: 92
      radius: 16
      color: home.cc.wash

      Rectangle {
        id: art
        x: 10; y: 10
        width: 72; height: 72
        radius: 12
        color: home.cc.ink
        clip: true
        Image {
          anchors.fill: parent
          source: home.player ? home.player.trackArtUrl : ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          sourceSize: Qt.size(144, 144)
        }
      }
      Column {
        x: art.x + art.width + 12
        y: 10
        width: parent.width - x - 12
        spacing: 3
        Text {
          width: parent.width
          text: home.player ? (home.player.trackTitle || home.player.identity) : ""
          elide: Text.ElideRight
          color: home.cc.ink
          font.family: home.cc.font
          font.pixelSize: 13
          font.bold: true
        }
        Text {
          width: parent.width
          text: home.player ? (home.player.trackArtist || home.player.identity) : ""
          elide: Text.ElideRight
          color: home.cc.ink
          font.family: home.cc.font
          font.pixelSize: 11
          opacity: 0.75
        }
        Row {
          spacing: 16
          topPadding: 2
          Repeater {
            model: [
              ["", function(p) { p.previous() }],
              [home.player && home.player.isPlaying ? "" : "", function(p) { p.togglePlaying() }],
              ["", function(p) { p.next() }]
            ]
            Text {
              required property var modelData
              text: modelData[0]
              color: home.cc.ink
              font.family: home.cc.font
              font.pixelSize: 15
              MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: if (home.player) parent.modelData[1](home.player)
              }
            }
          }
        }
        Item {
          width: parent.width
          height: 14
          visible: home.player && home.player.lengthSupported && home.player.length > 0
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 44
            height: 4
            radius: 2
            color: Qt.rgba(home.cc.ink.r, home.cc.ink.g, home.cc.ink.b, 0.2)
            Rectangle {
              width: home.player && home.player.length > 0 ? parent.width * Math.min(1, home.player.position / home.player.length) : 0
              height: parent.height
              radius: 2
              color: home.cc.ink
            }
          }
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: home.player ? home.clockText(home.player.position) : ""
            color: home.cc.ink
            font.family: home.cc.font
            font.pixelSize: 10
          }
        }
      }
    }
  }

  // =========================================================================
  Column {
    id: rightColumn
    x: home.colWidth + 20
    width: home.colWidth
    spacing: 12

    // calendar
    Item {
      id: calendar
      width: parent.width
      height: calHeader.height + 8 + calGrid.height

      property date month: new Date(clock.date.getFullYear(), clock.date.getMonth(), 1)
      readonly property int firstDay: Qt.locale().firstDayOfWeek   // 0 = Sunday
      readonly property var cells: {
        var y = month.getFullYear(), m = month.getMonth()
        var lead = (new Date(y, m, 1).getDay() - firstDay + 7) % 7
        var out = []
        for (var i = 0; i < 42; i++) out.push(new Date(y, m, 1 - lead + i))
        return out
      }

      Row {
        id: calHeader
        width: parent.width
        CcButton {
          cc: home.cc; icon: ""; pad: 16
          onClicked: calendar.month = new Date(calendar.month.getFullYear(), calendar.month.getMonth() - 1, 1)
        }
        Text {
          width: parent.width - 2 * 32
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignHCenter
          text: Qt.formatDate(calendar.month, "MMMM yyyy")
          color: home.cc.ink
          font.family: home.cc.font
          font.pixelSize: 14
          font.weight: Font.Black
          MouseArea {   // click the title to jump back to today
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: calendar.month = new Date(clock.date.getFullYear(), clock.date.getMonth(), 1)
          }
        }
        CcButton {
          cc: home.cc; icon: ""; pad: 16
          onClicked: calendar.month = new Date(calendar.month.getFullYear(), calendar.month.getMonth() + 1, 1)
        }
      }

      Grid {
        id: calGrid
        y: calHeader.height + 8
        columns: 7
        readonly property real cell: calendar.width / 7

        Repeater {
          model: 7
          Text {
            required property int index
            width: calGrid.cell
            height: 20
            horizontalAlignment: Text.AlignHCenter
            text: Qt.locale().dayName((calendar.firstDay + index) % 7, Locale.ShortFormat).slice(0, 2)
            color: home.cc.ink
            font.family: home.cc.font
            font.pixelSize: 10
            font.bold: true
            opacity: 0.6
          }
        }
        Repeater {
          model: calendar.cells
          Item {
            required property var modelData
            readonly property bool inMonth: modelData.getMonth() === calendar.month.getMonth()
            readonly property bool today: modelData.toDateString() === clock.date.toDateString()
            width: calGrid.cell
            height: 28
            Rectangle {
              anchors.centerIn: parent
              width: 26; height: 26; radius: 13
              color: parent.today ? home.cc.ink : "transparent"
            }
            Text {
              anchors.centerIn: parent
              text: parent.modelData.getDate()
              color: parent.today ? home.cc.slime : home.cc.ink
              opacity: parent.inMonth ? 1 : 0.35
              font.family: home.cc.font
              font.pixelSize: 12
              font.bold: parent.today
            }
          }
        }
      }
    }

    // notifications
    Row {
      width: parent.width
      spacing: 8
      CcHeading {
        cc: home.cc
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - clearButton.width - dndButton.width - 16
        text: "NOTIFICATIONS"
      }
      CcButton {
        id: dndButton
        cc: home.cc
        icon: ""; text: "DND"; fontSize: 11
        on: !!home.notif && home.notif.doNotDisturb
        onClicked: if (home.notif) home.notif.setDoNotDisturb(!home.notif.doNotDisturb)
      }
      CcButton {
        id: clearButton
        cc: home.cc
        icon: ""; text: "Clear"; fontSize: 11
        onClicked: if (home.notif) { home.notif.clearHistory(); clearDelay.restart() }
        Timer { id: clearDelay; interval: 400; onTriggered: home.refresh() }
      }
    }
    Text {
      visible: home.history.length === 0
      text: "All quiet in the ooze."
      color: home.cc.ink
      font.family: home.cc.font
      font.pixelSize: 12
      opacity: 0.6
    }
    Repeater {
      model: home.history
      Rectangle {
        required property var modelData
        width: rightColumn.width
        height: noteText.implicitHeight + 16
        radius: 12
        color: home.cc.wash
        Column {
          id: noteText
          x: 12; y: 8
          width: parent.width - 24
          spacing: 1
          Row {
            width: parent.width
            Text {
              width: parent.width - when.width
              text: modelData.summary || modelData.app
              elide: Text.ElideRight
              color: home.cc.ink
              font.family: home.cc.font
              font.pixelSize: 12
              font.bold: true
            }
            Text {
              id: when
              text: home.ago(modelData.timestamp)
              color: home.cc.ink
              font.family: home.cc.font
              font.pixelSize: 10
              opacity: 0.6
            }
          }
          Text {
            visible: text !== ""
            width: parent.width
            text: modelData.body || ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.Wrap
            color: home.cc.ink
            font.family: home.cc.font
            font.pixelSize: 11
            opacity: 0.8
          }
        }
      }
    }
  }
}
