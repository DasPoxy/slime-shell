import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Wayland

// A motion wallpaper (the picked video / gif) over Omarchy's background, on
// one screen. Loaded by Bar.qml on demand, so a system without
// QtMultimedia (qt6-multimedia) only loses video wallpapers, not the bar.
PanelWindow {
  id: motionWindow
  required property var bar
  required property var panel      // the bar window (for its screen)
  screen: panel.screen
  visible: bar.motionWall !== ""
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "slime-wallpaper"
  WlrLayershell.layer: WlrLayer.Background
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  anchors { top: true; bottom: true; left: true; right: true }
  mask: Region {}
  AnimatedImage {
    anchors.fill: parent
    visible: bar.motionIsGif
    source: bar.motionIsGif ? "file://" + bar.motionWall : ""
    fillMode: Image.PreserveAspectCrop
    playing: !bar.motionPaused
    cache: false
    asynchronous: true
  }
  MediaPlayer {
    id: motionPlayer
    source: !bar.motionIsGif && bar.motionWall !== "" ? "file://" + bar.motionWall : ""
    loops: MediaPlayer.Infinite
    videoOutput: motionVideo
    // no audio output at all: wallpapers are silent
    onSourceChanged: if (source != "" && !bar.motionPaused) play()
    onMediaStatusChanged: if (mediaStatus === MediaPlayer.LoadedMedia && !bar.motionPaused) play()
  }
  Connections {
    target: root
    function onMotionPausedChanged() {
      if (bar.motionIsGif || bar.motionWall === "") return
      if (bar.motionPaused) motionPlayer.pause(); else motionPlayer.play()
    }
  }
  VideoOutput {
    id: motionVideo
    anchors.fill: parent
    visible: !bar.motionIsGif
    fillMode: VideoOutput.PreserveAspectCrop
    // the poster underneath shows until the first frame is up
    opacity: motionPlayer.playbackState !== MediaPlayer.StoppedState && motionPlayer.mediaStatus >= MediaPlayer.BufferedMedia ? 1 : 0
  }
}
