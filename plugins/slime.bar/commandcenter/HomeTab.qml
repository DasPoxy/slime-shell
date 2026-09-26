import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Ui
import "../SlimeHub.js" as SlimeHub

// Home: quick toggles across the top (the bar's gear icons), then clock,
// weather, sound and the media monster on the left; calendar and recent
// notifications on the right.
Item {
  id: home

  property var cc: null
  readonly property real colWidth: (width - 20) / 2
  readonly property var clockWidget: cc ? cc.widget("slime.clock-weather") : null
  readonly property var weather: clockWidget ? clockWidget.weatherPanel : null
  readonly property bool hour24: clockWidget ? clockWidget.hour24 : true

  implicitHeight: toggleRow.height + 16 + Math.max(leftColumn.implicitHeight, rightColumn.implicitHeight)

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

  // ---- quick toggles: the bar's own gear ------------------------------------
  Row {
    id: toggleRow
    width: parent.width
    readonly property real slot: width / 6
    Repeater {
      model: 6
      Item {
        id: slot
        required property int index
        width: toggleRow.slot
        height: toggle.implicitHeight
        readonly property var adapter: Bluetooth.defaultAdapter
        readonly property bool micMuted: !!home.source && !!home.source.audio && home.source.audio.muted
        readonly property var spec: [
          { kind: "orb", label: "Wi-Fi", on: home.wifiOn },
          { kind: "runestone", label: "Bluetooth", on: !!adapter && adapter.enabled },
          { kind: "candle", label: "Night light", on: home.nightOn },
          { kind: "bell", label: "Do not disturb", on: !!home.notif && home.notif.doNotDisturb },
          { kind: "mug", label: "Stay awake", on: home.awakeOn },
          { kind: "trumpet", label: micMuted ? "Mic muted" : "Mic on", on: !micMuted }
        ][index]

        function activate() {
          switch (index) {
          case 0: home.run(["nmcli", "radio", "wifi", home.wifiOn ? "off" : "on"], home.refresh); break
          case 1: if (adapter) adapter.enabled = !adapter.enabled; break
          case 2: home.run(["omarchy-toggle-nightlight"], function() { nightDelay.restart() }); break
          case 3: if (home.notif) home.notif.setDoNotDisturb(!home.notif.doNotDisturb); break
          case 4: home.run(["omarchy-toggle-idle"], home.refresh); break
          case 5: if (home.source && home.source.audio) home.source.audio.muted = !home.source.audio.muted; break
          }
        }

        CcGearButton {
          id: toggle
          anchors.horizontalCenter: parent.horizontalCenter
          cc: home.cc
          kind: slot.spec.kind
          label: slot.spec.label
          labelSide: "below"
          size: 30
          phase: slot.index * 0.9
          active: slot.spec.on
          lit: slot.spec.on
          opacity: slot.spec.on ? 1 : 0.55
          // gear state the orb and runestone read
          net: slot.spec.on ? "wifi" : "none"
          state3: slot.spec.on ? "on" : "off"
          onClicked: slot.activate()
        }
      }
    }
    Timer { id: nightDelay; interval: 700; onTriggered: home.refresh() }
  }

  // =========================================================================
  Column {
    id: leftColumn
    y: toggleRow.height + 16
    width: home.colWidth
    spacing: 12

    // clock: click the time to swap 12h / 24h; date and time order follows
    // the shared clock-order setting (Settings > Font & clock)
    Row {
      spacing: 8
      layoutDirection: home.cc.bar.clockTimeFirst ? Qt.LeftToRight : Qt.RightToLeft
      Text {
        text: home.hour24 ? Qt.formatTime(clock.date, "HH:mm") : Qt.formatTime(clock.date, "h:mm AP").replace(/\s*[AP]M$/i, "")
        color: home.cc.ink
        font.family: home.cc.font
        font.pixelSize: 46
        font.weight: Font.Black
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: if (home.clockWidget) home.clockWidget.toggleHour24()
        }
      }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0
        Text {
          anchors.right: home.cc.bar.clockTimeFirst ? undefined : parent.right
          text: Qt.formatDate(clock.date, "dddd") + (home.hour24 ? "" : "  " + Qt.formatTime(clock.date, "AP"))
          color: home.cc.ink
          font.family: home.cc.font
          font.pixelSize: 15
          font.bold: true
        }
        Text {
          anchors.right: home.cc.bar.clockTimeFirst ? undefined : parent.right
          text: Qt.formatDate(clock.date, "d MMMM yyyy")
          color: home.cc.ink
          font.family: home.cc.font
          font.pixelSize: 12
          opacity: 0.8
        }
      }
    }

    // weather: a cartoon cloud in the gear style, bobbing in the goo
    Item {
      id: cloud
      visible: !!home.weather && home.weather.reportTempNum !== ""
      width: home.colWidth
      height: weatherColumn.implicitHeight + 46
      readonly property real t: home.cc.bar.animTime
      readonly property string icon: home.weather ? home.weather.label : ""
      // weather glyphs from the Omarchy panel: nerd-font sun / moon / rain / snow
      readonly property bool wet: /[\uf73d\ue318\ue319\ue31a\ue31b\uf740\uf741\ue308]/.test(icon)
      transform: Translate { y: Math.sin(cloud.t * 0.9) * 1.5 }

      Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {   // the cloud: bumpy top, flat-ish rounded base
          fillColor: home.cc.bar.monsterBody
          strokeColor: home.cc.ink
          strokeWidth: 2
          joinStyle: ShapePath.RoundJoin
          PathSvg {
            path: {
              var w = cloud.width, h = cloud.height
              return "M 18 " + (h - 4)
                + " Q 2 " + (h - 4) + " 4 " + (h - 22)
                + " Q 4 34 26 30"
                + " Q 30 8 58 12"
                + " Q " + (w * 0.3) + " -4 " + (w * 0.46) + " 12"
                + " Q " + (w * 0.62) + " 0 " + (w * 0.72) + " 18"
                + " Q " + (w - 18) + " 12 " + (w - 16) + " 36"
                + " Q " + (w - 2) + " 44 " + (w - 4) + " " + (h - 22)
                + " Q " + (w - 4) + " " + (h - 4) + " " + (w - 20) + " " + (h - 4) + " Z"
            }
          }
        }
        ShapePath {   // gloss
          fillColor: Qt.rgba(1, 1, 1, 0.55)
          strokeColor: "transparent"
          PathSvg { path: "M 36 22 Q 44 13 58 16 Q 46 18 40 26 Z" }
        }
      }
      // raindrops under a wet cloud
      Repeater {
        model: cloud.wet ? 4 : 0
        Rectangle {
          required property int index
          x: cloud.width * (0.25 + index * 0.16)
          y: cloud.height - 2 + ((cloud.t * 30 + index * 11) % 14)
          width: 3; height: 7; radius: 1.5
          color: home.cc.ink
          opacity: 0.6
        }
      }

      Column {
        id: weatherColumn
        x: 18; y: 28
        width: parent.width - 36
        spacing: 8
        Row {
          spacing: 12
          Text {
            text: cloud.icon
            color: home.cc.ink
            font.family: home.cc.font
            font.pixelSize: 34
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: home.weather ? home.weather.reportTempNum + home.weather.tempUnit : ""
            color: home.cc.ink
            font.family: home.cc.font
            font.pixelSize: 28
            font.weight: Font.Black
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            Text {
              text: home.weather ? home.weather.reportLocation : ""
              color: home.cc.ink; font.family: home.cc.font; font.pixelSize: 12; font.bold: true
            }
            Text {
              text: home.weather ? "feels " + home.weather.reportFeels + " · " + home.weather.reportWind + " · " + home.weather.reportHumidity : ""
              color: home.cc.ink; font.family: home.cc.font; font.pixelSize: 10; opacity: 0.75
            }
          }
        }
        Row {
          width: parent.width
          Repeater {
            model: home.weather ? home.weather.forecastDays.slice(0, 3) : []
            Row {
              required property var modelData
              width: weatherColumn.width / 3
              spacing: 6
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: home.weather.dayIcon(modelData)
                color: home.cc.ink; font.family: home.cc.font; font.pixelSize: 16
              }
              Column {
                Text {
                  text: home.weather.dayName(modelData.date).toUpperCase()
                  color: home.cc.ink; font.family: home.cc.font; font.pixelSize: 9; font.bold: true; opacity: 0.7
                }
                Text {
                  text: home.weather.bareTempForDay(modelData, "max") + " " + home.weather.bareTempForDay(modelData, "min")
                  color: home.cc.ink; font.family: home.cc.font; font.pixelSize: 11; font.bold: true
                }
              }
            }
          }
        }
      }
    }

    CcHeading { cc: home.cc; text: "SOUND" }
    Repeater {
      model: [
        { node: home.sink, kind: "horn" },
        { node: home.source, kind: "trumpet" }
      ]
      Row {
        id: soundRow
        required property var modelData
        required property int index
        readonly property var audio: modelData.node ? modelData.node.audio : null
        visible: audio !== null
        spacing: 10
        // the bar's own gear: war horn for output, ear trumpet for the mic
        CcGearButton {
          anchors.verticalCenter: parent.verticalCenter
          cc: home.cc
          kind: soundRow.modelData.kind
          labelSide: "none"
          size: 28
          phase: soundRow.index * 2
          muted: !!soundRow.audio && soundRow.audio.muted
          level: soundRow.audio ? soundRow.audio.volume : 0
          lit: !!soundRow.audio && !soundRow.audio.muted
          opacity: lit ? 1 : 0.6
          onClicked: if (soundRow.audio) soundRow.audio.muted = !soundRow.audio.muted
        }
        SlimeSlider {
          anchors.verticalCenter: parent.verticalCenter
          width: home.colWidth - 28 - 50 - 20
          cc: home.cc
          maximum: 1
          value: soundRow.audio ? soundRow.audio.volume : 0
          onMoved: v => { if (soundRow.audio) soundRow.audio.volume = v }
        }
        Text {
          width: 50
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignRight
          text: soundRow.audio ? Math.round(soundRow.audio.volume * 100) + "%" : ""
          color: home.cc.ink
          font.family: home.cc.font
          font.pixelSize: 12
          font.bold: true
        }
      }
    }

    MediaMonster {
      visible: home.player !== null
      width: home.colWidth
      cc: home.cc
      player: home.player
    }
  }

  // =========================================================================
  Column {
    id: rightColumn
    x: home.colWidth + 20
    y: toggleRow.height + 16
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

      Item {
        id: calHeader
        width: parent.width
        height: 30
        CcGearButton {
          anchors.verticalCenter: parent.verticalCenter
          cc: home.cc; kind: "arrow"; flip: true; size: 26; labelSide: "none"
          onClicked: calendar.month = new Date(calendar.month.getFullYear(), calendar.month.getMonth() - 1, 1)
        }
        Text {
          anchors.centerIn: parent
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
        CcGearButton {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          cc: home.cc; kind: "arrow"; size: 26; labelSide: "none"; phase: 2
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
    Item {
      width: parent.width
      height: 44
      CcHeading {
        cc: home.cc
        anchors.verticalCenter: parent.verticalCenter
        text: "NOTIFICATIONS"
      }
      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14
        CcGearButton {
          cc: home.cc
          kind: "bell"; label: "DND"; labelSide: "below"; size: 24; phase: 1
          lit: !!home.notif && home.notif.doNotDisturb
          active: lit
          onClicked: if (home.notif) home.notif.setDoNotDisturb(!home.notif.doNotDisturb)
        }
        CcGearButton {
          cc: home.cc
          kind: "broom"; label: "Clear"; labelSide: "below"; size: 24; phase: 3
          lit: home.history.length > 0
          onClicked: if (home.notif) { home.notif.clearHistory(); clearDelay.restart() }
          Timer { id: clearDelay; interval: 400; onTriggered: home.refresh() }
        }
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
