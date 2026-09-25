// Slime Shell — step 1 spike.
// A standalone Quickshell config (not an Omarchy plugin) that tests the slime
// skin: a shader-drawn bar with live drips and a control-centre panel that
// drips open. Run with ./run.sh, stop with ./stop.sh.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Bluetooth
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray

ShellRoot {
  id: root

  readonly property real barHeight: 44
  readonly property real panelWidth: 380
  readonly property real panelHeight: 480
  readonly property double t0: Date.now()

  property var palette: ({})
  property color background: palette.background || "#101315"
  property string slimeRole: "accent"
  readonly property color slimeColor: palette[slimeRole] || "#5fd35f"
  // Lightest of the theme's two base tones: the "paper" showing through prints.
  readonly property color paperColor: {
    const fg = Qt.color(palette.foreground || "#f3e9d2"), bg = Qt.color(palette.background || "#101315")
    return fg.hslLightness >= bg.hslLightness ? fg : bg
  }
  // "auto" picks the palette colour whose hue sits roughly 100° away from the
  // slime colour, which gives an anime-style complementary sweep.
  property string gradientRole: "auto"
  readonly property var hueRoles: ["red", "yellow", "green", "cyan", "blue", "magenta",
    "bright_red", "bright_yellow", "bright_green", "bright_cyan", "bright_blue", "bright_magenta"]
  readonly property color slimeColor2: {
    if (gradientRole === "none") return slimeColor
    if (gradientRole !== "auto") return palette[gradientRole] || slimeColor
    const h1 = slimeColor.hsvHue
    if (h1 < 0) return palette.accent || slimeColor
    let best = slimeColor, bestScore = 1e9
    for (const role of hueRoles) {
      if (!palette[role]) continue
      const c = Qt.color(palette[role])
      if (c.hsvHue < 0 || c.hsvSaturation < 0.35) continue
      let diff = Math.abs(c.hsvHue - h1) * 360
      if (diff > 180) diff = 360 - diff
      const score = Math.abs(diff - 100)
      if (score < bestScore) { bestScore = score; best = c }
    }
    return best
  }

  // ---- animation clock shared by the shader and the floating widgets ----
  property real animTime: 0
  Timer {
    interval: root.fps > 0 ? Math.round(1000 / root.fps) : 1000
    repeat: true
    running: root.fps > 0
    onTriggered: root.animTime = (Date.now() - root.t0) / 1000
  }
  function bob(phase) { return Math.sin(animTime * 1.3 + phase) * 1.6 }
  function sway(phase) { return Math.sin(animTime * 0.9 + phase * 1.7) * 1.8 }

  readonly property real widgetHeight: 28
  readonly property string glyphFont: "JetBrainsMono Nerd Font"

  // ---- data sources (shared by every screen) ----
  property int agentPercent: -1
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/agents/usage/claude.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        const limits = JSON.parse(text()).limits || []
        root.agentPercent = limits.length ? Math.round(limits[0].percent * 100) : -1
      } catch (e) { root.agentPercent = -1 }
    }
  }

  property string weatherTemp: ""
  property string weatherGlyph: ""
  Process {
    id: weatherProc
    command: ["curl", "-s", "--max-time", "6", "wttr.in/?format=%t|%C"]
    stdout: StdioCollector {
      onStreamFinished: {
        const parts = text.trim().split("|")
        if (parts.length !== 2 || parts[0].length > 8) return
        const c = parts[1].toLowerCase()
        root.weatherTemp = parts[0].replace("+", "")
        root.weatherGlyph = c.includes("thunder") ? "\uf0e7" : c.includes("snow") ? "\uf2dc"
          : (c.includes("rain") || c.includes("drizzle") || c.includes("shower")) ? "\uf73d"
          : (c.includes("fog") || c.includes("mist")) ? "\uf75f"
          : (c.includes("cloud") || c.includes("overcast")) ? "\uf0c2" : "\uf185"
      }
    }
  }
  Timer { interval: 15 * 60 * 1000; repeat: true; running: true; triggeredOnStart: true; onTriggered: weatherProc.running = true }

  property string netGlyph: "\udb82\udd2d"
  Process {
    id: netProc
    command: ["nmcli", "-t", "-f", "TYPE,STATE", "device"]
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.split("\n")
        if (lines.some(l => l.startsWith("ethernet:connected"))) root.netGlyph = "\udb80\ude00"
        else if (lines.some(l => l.startsWith("wifi:connected"))) root.netGlyph = "\udb81\udda9"
        else root.netGlyph = "\udb81\uddaa"
      }
    }
  }
  Timer { interval: 10000; repeat: true; running: true; triggeredOnStart: true; onTriggered: netProc.running = true }

  readonly property var sink: Pipewire.defaultAudioSink
  PwObjectTracker { objects: [root.sink] }

  readonly property var player: {
    const ps = Mpris.players.values
    return ps.find(p => p.isPlaying) || ps[0] || null
  }

  // A widget floating in the ooze: its contents bob and sway, and `rect` tells
  // the shader where to sag a bulb of slime beneath it.
  component Blob: Item {
    id: blob
    property real phase: 0
    property bool clickable: false
    signal clicked(var mouse)
    signal wheeled(var wheel)
    default property alias content: inner.data
    readonly property vector4d rect: visible && width > 0
      ? Qt.vector4d(parent.x + x, parent.y + y, width, height) : Qt.vector4d(0, 0, 0, 0)
    implicitWidth: inner.childrenRect.width + 26
    implicitHeight: root.widgetHeight

    Item {
      id: inner
      anchors.centerIn: parent
      anchors.verticalCenterOffset: root.bob(blob.phase)
      rotation: root.sway(blob.phase)
      width: childrenRect.width
      height: childrenRect.height
    }

    MouseArea {
      anchors.fill: parent
      enabled: blob.clickable
      cursorShape: Qt.PointingHandCursor
      onClicked: mouse => blob.clicked(mouse)
      onWheel: wheel => blob.wheeled(wheel)
    }
  }

  component Glyph: Text {
    color: root.background
    font.family: root.glyphFont
    font.pixelSize: 16
    font.bold: true
  }

  component Label: Text {
    color: root.background
    font.pixelSize: 14
    font.bold: true
  }

  property int fps: 60          // 0 = paused
  property real dripAmount: 1.0
  property int shadingStyle: 3  // 0 soft, 1 anime, 2 manga, 3 print

  function parseColors(raw) {
    const out = {}
    for (const line of raw.split("\n")) {
      const m = line.match(/^\s*([a-z_]+)\s*=\s*"(#[0-9a-fA-F]{6,8})"/)
      if (m) out[m[1]] = m[2]
    }
    palette = out
  }

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.parseColors(text())
  }

  SystemClock {
    id: clock
    precision: SystemClock.Seconds
  }

  component Chip: Rectangle {
    id: chip
    property string label
    property bool selected
    signal clicked

    implicitWidth: chipText.implicitWidth + 18
    implicitHeight: 24
    radius: 12
    color: selected ? root.background : Qt.rgba(1, 1, 1, 0.6)

    Text {
      id: chipText
      anchors.centerIn: parent
      text: chip.label
      font.pixelSize: 12
      font.bold: true
      color: chip.selected ? root.slimeColor : root.background
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.clicked()
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData
      screen: modelData

      property bool open: false
      property real openProgress: 0
      readonly property real panelX: Math.min(width - root.panelWidth - 16,
        btnB.rect.x + btnB.width / 2 - root.panelWidth / 2)
      readonly property var blobs: [powerB, wsB, agentsB, weatherB, clockB, mediaB, trayB, netB, btB, audioB, btnB]

      anchors { top: true; left: true; right: true }
      // Only as tall as needed: the bar and its drips while closed, room for
      // the panel while it's open or animating. Fewer pixels to shade.
      implicitHeight: open || openProgress > 0 ? root.barHeight + root.panelHeight + 160 : root.barHeight + 170
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "slime-spike"

      // Only the bar (and the panel while open) takes input; drips and
      // falling droplets are click-through.
      mask: Region {
        item: barHit
        Region { item: panelHit }
      }

      Item { id: barHit; width: win.width; height: root.barHeight }
      Item {
        id: panelHit
        x: win.panelX
        y: root.barHeight
        width: root.panelWidth
        height: win.open ? root.panelHeight : 0
      }

      IpcHandler {
        target: "slime"
        function toggle(): void { win.open = !win.open }
        function shading(style: int): void { root.shadingStyle = style }
        function gradient(role: string): void { root.gradientRole = role }
        function fps(n: int): void { root.fps = n }
      }

      NumberAnimation on openProgress {
        id: openAnim
        running: false
      }
      onOpenChanged: {
        openAnim.stop()
        openAnim.to = open ? 1 : 0
        openAnim.duration = open ? 750 : 420
        openAnim.easing.type = open ? Easing.OutQuad : Easing.InQuad
        openAnim.start()
      }

      ShaderEffect {
        id: slime
        anchors.fill: parent
        fragmentShader: Qt.resolvedUrl("shaders/slime.frag.qsb")

        property real time: root.animTime
        property real barHeight: root.barHeight
        property real openProgress: win.openProgress
        property real dripAmount: root.dripAmount
        property real shadingStyle: root.shadingStyle
        property vector2d resolution: Qt.vector2d(width, height)
        property vector4d panelRect: Qt.vector4d(win.panelX, 0, root.panelWidth, root.panelHeight)
        property color slimeColor: root.slimeColor
        property color slimeColor2: root.slimeColor2
        property color paperColor: root.paperColor
        property vector4d bulb0: win.blobs[0] ? win.blobs[0].rect : Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb1: win.blobs[1] ? win.blobs[1].rect : Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb2: win.blobs[2] ? win.blobs[2].rect : Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb3: win.blobs[3] ? win.blobs[3].rect : Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb4: win.blobs[4] ? win.blobs[4].rect : Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb5: win.blobs[5] ? win.blobs[5].rect : Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb6: win.blobs[6] ? win.blobs[6].rect : Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb7: win.blobs[7] ? win.blobs[7].rect : Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb8: win.blobs[8] ? win.blobs[8].rect : Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb9: win.blobs[9] ? win.blobs[9].rect : Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb10: win.blobs[10] ? win.blobs[10].rect : Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb11: win.blobs[11] ? win.blobs[11].rect : Qt.vector4d(0, 0, 0, 0)
      }


      // ---- bar content ----
      // Left: power, workspaces, agents. Centre: weather, clock, media.
      // Right: tray, network, bluetooth, audio, control centre.
      Row {
        id: leftRow
        x: 12
        y: Math.round((root.barHeight - root.widgetHeight) / 2)
        spacing: 4

        Blob {
          id: powerB
          phase: 0.4
          Glyph { text: "\uf011" }
          clickable: true
          onClicked: Quickshell.execDetached(["omarchy-menu"])
        }

        Blob {
          id: wsB
          phase: 1.3
          Row {
            spacing: 7
            Repeater {
              model: Hyprland.workspaces
              delegate: Rectangle {
                required property var modelData
                readonly property bool active: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === modelData.id
                visible: modelData.id > 0
                width: active ? 26 : 12
                height: 12
                radius: 6
                color: root.background
                opacity: active ? 1 : 0.55
                Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -4
                  cursorShape: Qt.PointingHandCursor
                  onClicked: Hyprland.dispatch("workspace " + parent.modelData.id)
                }
              }
            }
          }
        }

        Blob {
          id: agentsB
          phase: 2.2
          visible: root.agentPercent >= 0
          Row {
            spacing: 5
            Glyph { text: "\uf005"; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
            Label { text: root.agentPercent + "%" }
          }
        }
      }

      Row {
        id: centerRow
        x: Math.round((win.width - clockB.width) / 2 - (weatherB.visible ? weatherB.width + spacing : 0))
        y: leftRow.y
        spacing: 4

        Blob {
          id: weatherB
          phase: 3.1
          visible: root.weatherTemp !== ""
          Row {
            spacing: 6
            Glyph { text: root.weatherGlyph; anchors.verticalCenter: parent.verticalCenter }
            Label { text: root.weatherTemp }
          }
        }

        Blob {
          id: clockB
          phase: 4.0
          Label {
            text: Qt.formatDateTime(clock.date, "ddd d MMM   HH:mm")
            font.pixelSize: 15
          }
        }

        Blob {
          id: mediaB
          phase: 4.9
          visible: root.player !== null
          Row {
            spacing: 8
            Glyph {
              text: "\uf048"; font.pixelSize: 13
              anchors.verticalCenter: parent.verticalCenter
              MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: root.player.previous() }
            }
            Glyph {
              text: root.player && root.player.isPlaying ? "\uf04c" : "\uf04b"; font.pixelSize: 13
              anchors.verticalCenter: parent.verticalCenter
              MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: root.player.togglePlaying() }
            }
            Glyph {
              text: "\uf051"; font.pixelSize: 13
              anchors.verticalCenter: parent.verticalCenter
              MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: root.player.next() }
            }
            Label {
              text: root.player ? (root.player.trackTitle || root.player.identity) : ""
              width: Math.min(implicitWidth, 200)
              elide: Text.ElideRight
            }
          }
        }
      }

      Row {
        id: rightRow
        x: win.width - width - 12
        y: leftRow.y
        spacing: 4

        Blob {
          id: trayB
          phase: 5.6
          visible: SystemTray.items.values.length > 0
          Row {
            spacing: 8
            Repeater {
              model: SystemTray.items
              delegate: IconImage {
                id: trayIcon
                required property var modelData
                source: modelData.icon
                implicitSize: 16
                MouseArea {
                  anchors.fill: parent
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  cursorShape: Qt.PointingHandCursor
                  onClicked: mouse => {
                    if (mouse.button === Qt.RightButton && trayIcon.modelData.hasMenu) {
                      const pos = trayIcon.mapToItem(win.contentItem, 0, trayIcon.height + 12)
                      trayIcon.modelData.display(win, pos.x, pos.y)
                    } else {
                      trayIcon.modelData.activate()
                    }
                  }
                }
              }
            }
          }
        }

        Blob {
          id: netB
          phase: 6.5
          Glyph { text: root.netGlyph }
          clickable: true
          onClicked: Quickshell.execDetached(["omarchy-launch-or-focus-tui", "nmtui"])
        }

        Blob {
          id: btB
          phase: 7.3
          visible: Bluetooth.defaultAdapter !== null
          Glyph {
            text: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled ? "\uf293" : "\udb80\udcb2"
            opacity: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled ? 1 : 0.55
          }
          clickable: true
          onClicked: Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled
        }

        Blob {
          id: audioB
          phase: 8.2
          visible: root.sink !== null
          Row {
            spacing: 5
            Glyph {
              anchors.verticalCenter: parent.verticalCenter
              text: !root.sink || !root.sink.audio ? "\uf026"
                : root.sink.audio.muted ? "\udb81\udf5f"
                : root.sink.audio.volume > 0.5 ? "\uf028" : "\uf027"
            }
            Label { text: root.sink && root.sink.audio ? Math.round(root.sink.audio.volume * 100) + "%" : "" }
          }
          clickable: true
          onClicked: root.sink.audio.muted = !root.sink.audio.muted
          onWheeled: wheel => {
            const a = root.sink.audio
            a.volume = Math.max(0, Math.min(1.5, a.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05)))
          }
        }

        Blob {
          id: btnB
          phase: 9.1
          Glyph {
            text: "◉"
            font.pixelSize: 17
            scale: win.open ? 1.25 : 1
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
          }
          clickable: true
          onClicked: win.open = !win.open
        }
      }

      // ---- panel content (fades in once the ooze has settled) ----
      Column {
        x: win.panelX + 24
        y: root.barHeight + 18
        width: root.panelWidth - 48
        spacing: 12
        opacity: Math.max(0, (win.openProgress - 0.8) / 0.2)
        visible: opacity > 0

        Text {
          text: Qt.formatDateTime(clock.date, "HH:mm:ss")
          color: root.background
          font.pixelSize: 40
          font.bold: true
        }
        Text {
          text: Qt.formatDateTime(clock.date, "dddd, d MMMM yyyy")
          color: root.background
          font.pixelSize: 14
          font.bold: true
        }

        Text { text: "SLIME COLOUR (theme role)"; color: root.background; font.pixelSize: 10; font.bold: true; opacity: 0.7 }
        Flow {
          width: parent.width
          spacing: 6
          Repeater {
            model: ["accent", "green", "cyan", "magenta", "red", "yellow", "foreground"]
            Chip {
              required property string modelData
              label: modelData
              selected: root.slimeRole === modelData
              onClicked: root.slimeRole = modelData
            }
          }
        }

        Text { text: "GRADIENT PARTNER"; color: root.background; font.pixelSize: 10; font.bold: true; opacity: 0.7 }
        Flow {
          width: parent.width
          spacing: 6
          Repeater {
            model: ["auto", "none", "magenta", "cyan", "green", "yellow", "red"]
            Chip {
              required property string modelData
              label: modelData
              selected: root.gradientRole === modelData
              onClicked: root.gradientRole = modelData
            }
          }
        }

        Text { text: "SHADING"; color: root.background; font.pixelSize: 10; font.bold: true; opacity: 0.7 }
        Flow {
          width: parent.width
          spacing: 6
          Repeater {
            model: [["soft", 0], ["anime", 1], ["manga", 2], ["print", 3]]
            Chip {
              required property var modelData
              label: modelData[0]
              selected: root.shadingStyle === modelData[1]
              onClicked: root.shadingStyle = modelData[1]
            }
          }
        }

        Text { text: "ANIMATION"; color: root.background; font.pixelSize: 10; font.bold: true; opacity: 0.7 }
        Flow {
          width: parent.width
          spacing: 6
          Repeater {
            model: [["paused", 0], ["30 fps", 30], ["60 fps", 60], ["120 fps", 120]]
            Chip {
              required property var modelData
              label: modelData[0]
              selected: root.fps === modelData[1]
              onClicked: root.fps = modelData[1]
            }
          }
          Repeater {
            model: [["dry", 0.4], ["ooze", 1.0], ["gush", 1.7]]
            Chip {
              required property var modelData
              label: modelData[0]
              selected: root.dripAmount === modelData[1]
              onClicked: root.dripAmount = modelData[1]
            }
          }
        }
      }
    }
  }
}
