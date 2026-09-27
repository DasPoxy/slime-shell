import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

// Wallpapers: the current theme's backgrounds, then your own from
// ~/Pictures/SlimeS-Wallpapers, as thumbnail grids. Clicking one sets it
// through `omarchy-theme-bg-set` (so the Omarchy background plugin and
// anything else watching the current-background link follow along).
Item {
  id: walls
  // the command centre's text size (Settings → Command centre → text size)
  readonly property real fs: cc && cc.fontScale ? cc.fontScale : 1

  property var cc: null
  property string current: ""
  readonly property string themeDir: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/backgrounds"
  readonly property int columns: 3
  readonly property real thumbWidth: width / columns - 10
  readonly property real thumbHeight: Math.round(thumbWidth * 9 / 16)
  readonly property string myDir: Quickshell.env("HOME") + "/Pictures/SlimeS-Wallpapers"

  // the tab grows to fit; the command centre scrolls it (and follows the keyboard)
  implicitHeight: column.implicitHeight

  Process {
    id: currentProbe
    command: ["readlink", "-f", Quickshell.env("HOME") + "/.local/state/omarchy/current/background"]
    stdout: StdioCollector { onStreamFinished: walls.current = text.trim() }
  }
  // (the folder is made at shell start; again here in case it was removed since)
  Component.onCompleted: {
    currentProbe.running = true
    Quickshell.execDetached(["mkdir", "-p", walls.myDir])
  }

  // each section folds open and closed (remembered, like the other folds)
  readonly property var bar: cc ? cc.bar : null
  function shut(key) { return !!(bar && bar.ccSections && bar.ccSections["walls-shut:" + key]) }
  function toggle(key) {
    if (!bar) return
    var m = Object.assign({}, bar.ccSections)
    if (m["walls-shut:" + key]) delete m["walls-shut:" + key]; else m["walls-shut:" + key] = true
    bar.ccSections = m
  }
  // a section's heading: chevron + title, click (or Enter) folds it
  component FoldHead: Item {
    id: fh
    property string key
    property string title
    width: parent ? parent.width - (extra ? extra.width + 8 : 0) : 0
    property Item extra: null
    height: Math.max(26, headText.implicitHeight + 8)
    Rectangle {
      anchors.fill: parent
      radius: 9
      color: fhMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.3) : "transparent"
    }
    Row {
      x: 4; spacing: 8
      anchors.verticalCenter: parent.verticalCenter
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: walls.shut(fh.key) ? "\uf054" : "\uf078"
        color: walls.cc.ink; font.family: walls.cc.font; font.pixelSize: Math.round(9 * walls.fs)
      }
      CcHeading { id: headText; cc: walls.cc; anchors.verticalCenter: parent.verticalCenter; text: fh.title }
    }
    MouseArea { id: fhMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: walls.toggle(fh.key) }
    CcFocus { onActivate: walls.toggle(fh.key) }
  }

  function setWallpaper(path) {
    walls.current = path
    Quickshell.execDetached(["omarchy-theme-bg-set", path])
  }

  readonly property var filters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.PNG", "*.JPG", "*.JPEG", "*.WEBP"]
  FolderListModel {
    id: files
    folder: "file://" + walls.themeDir
    nameFilters: walls.filters
    showDirs: false
    sortField: FolderListModel.Name
  }
  FolderListModel {
    id: mine
    folder: "file://" + walls.myDir
    nameFilters: walls.filters
    showDirs: false
    sortField: FolderListModel.Name
  }

  // one wallpaper's thumbnail
  component Thumb: Item {
    id: thumb
    required property string filePath
    readonly property bool selected: walls.current === filePath
    width: walls.thumbWidth
    height: walls.thumbHeight

    ClippingRectangle {
      anchors.fill: parent
      radius: 14
      color: walls.cc.ink
      border.color: walls.cc.ink
      border.width: thumb.selected ? 4 : 0

      Image {
        anchors.fill: parent
        source: "file://" + thumb.filePath
        sourceSize: Qt.size(320, 180)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
      }
    }

    Rectangle {   // selected badge
      visible: thumb.selected
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 8
      width: 22; height: 22; radius: 11
      color: walls.cc.ink
      Text {
        anchors.centerIn: parent
        text: "\uf00c"
        color: walls.cc.slime
        font.family: walls.cc.font
        font.pixelSize: Math.round(11 * walls.fs) }
    }

    HoverHandler { id: hover }
    Rectangle {
      anchors.fill: parent
      radius: 14
      color: Qt.rgba(1, 1, 1, hover.hovered && !thumb.selected ? 0.18 : 0)
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: walls.setWallpaper(thumb.filePath)
    }
    CcFocus { onActivate: walls.setWallpaper(thumb.filePath) }
  }

  Column {
    id: column
    width: parent.width
    spacing: 10

    Row {
      id: header
      width: parent.width
      spacing: 8
      FoldHead {
        anchors.verticalCenter: parent.verticalCenter
        extra: nextButton
        key: "theme"
        title: files.count + " BACKGROUNDS IN THIS THEME"
      }
      CcButton {
        id: nextButton
        cc: walls.cc
        icon: "\uf061"; text: "Next"; fontSize: 11
        onClicked: {
          Quickshell.execDetached(["omarchy-theme-bg-next"])
          refreshDelay.restart()
        }
        Timer { id: refreshDelay; interval: 500; onTriggered: currentProbe.running = true }
      }
    }
    Flow {
      visible: !walls.shut("theme")
      width: parent.width
      spacing: 10
      Repeater {
        model: files
        Thumb {}
      }
    }

    // your own: whatever is in ~/Pictures/SlimeS-Wallpapers
    Row {
      width: parent.width
      spacing: 8
      FoldHead {
        anchors.verticalCenter: parent.verticalCenter
        extra: openButton
        key: "mine"
        title: mine.count + " OF YOUR OWN  ·  ~/PICTURES/SLIMES-WALLPAPERS"
      }
      CcButton {
        id: openButton
        cc: walls.cc
        icon: "\uf07c"; text: "Open folder"; fontSize: 11
        onClicked: Quickshell.execDetached(["xdg-open", walls.myDir])
      }
    }
    Flow {
      visible: !walls.shut("mine")
      width: parent.width
      spacing: 10
      Repeater {
        model: mine
        Thumb {}
      }
    }
    Text {
      visible: mine.count === 0 && !walls.shut("mine")
      width: parent.width
      wrapMode: Text.Wrap
      text: "Drop images into ~/Pictures/SlimeS-Wallpapers and they show up here, whatever the theme."
      color: walls.cc.ink; opacity: 0.7
      font.family: walls.cc.font; font.pixelSize: Math.round(11 * walls.fs)
    }
  }
}
