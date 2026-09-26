import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Hover-and-press keys for a media widget: rest the pointer on it and
//   Space  play / pause
//   M      mute / unmute the default output
// and a middle click plays / pauses too (no keyboard needed).
// Layer windows don't take the keyboard on their own, so after a short hover
// this asks the bar to give its window the keyboard (bar.hoverKeysWindow),
// and hands it straight back when the pointer leaves — nothing is grabbed
// while you're only passing over.
Item {
  id: keys

  required property var bar
  property var player: null
  property bool enabledKeys: true

  readonly property var sink: Pipewire.defaultAudioSink
  PwObjectTracker { objects: keys.sink ? [keys.sink] : [] }

  readonly property bool hovered: hover.hovered
  readonly property var ownWindow: QsWindow.window

  HoverHandler { id: hover }

  // middle click: play / pause. Only the middle button is taken, so left and
  // right clicks and the scroll wheel still reach the widget underneath.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.MiddleButton
    onClicked: if (keys.player) keys.player.togglePlaying()
  }

  Timer {
    id: grabDelay
    interval: 220
    onTriggered: {
      if (!keys.hovered || !keys.bar) return
      keys.bar.hoverKeysWindow = keys.ownWindow
      keys.forceActiveFocus()
    }
  }
  onHoveredChanged: {
    if (!enabledKeys || !bar) return
    if (hovered) grabDelay.restart()
    else {
      grabDelay.stop()
      if (bar.hoverKeysWindow === ownWindow) bar.hoverKeysWindow = null
      focus = false
    }
  }
  Component.onDestruction: if (bar && hovered && bar.hoverKeysWindow === ownWindow) bar.hoverKeysWindow = null

  Keys.onPressed: event => {
    if (event.key === Qt.Key_Space) {
      if (keys.player) keys.player.togglePlaying()
      event.accepted = true
    } else if (event.key === Qt.Key_M) {
      if (keys.sink && keys.sink.audio) keys.sink.audio.muted = !keys.sink.audio.muted
      event.accepted = true
    }
  }
}
