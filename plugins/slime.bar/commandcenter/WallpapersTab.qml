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
    posterKick.restart()
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

  // a still is set straight away; a video / gif plays through the bar's
  // motion wallpaper (which sets its poster as the background)
  function setWallpaper(path) {
    if (bar && bar.isMotion(path)) { bar.setMotionWall(path); return }
    if (bar) bar.clearMotionWall()
    walls.current = path
    Quickshell.execDetached(["omarchy-theme-bg-set", path])
  }
  function isCurrent(path) {
    return bar && bar.motionWall !== "" ? bar.motionWall === path : walls.current === path
  }
  // posters for the videos / gifs (made once, cached), for the thumbnails
  property int posterRev: 0
  Process {
    id: posterMaker
    command: ["bash", "-c",
      "mkdir -p \"$2\"; for f in \"$1\"/*; do case \"${f,,}\" in *.mp4|*.webm|*.mkv|*.mov|*.m4v|*.gif) ;; *) continue ;; esac; " +
      "p=\"$2/$(basename \"$f\" | sed 's/[^A-Za-z0-9._-]\\+/-/g').jpg\"; [ -s \"$p\" ] && continue; " +
      "case \"${f,,}\" in *.gif) magick \"$f[0]\" -resize 1920x \"$p\" ;; *) ffmpeg -y -loglevel error -ss 1 -i \"$f\" -frames:v 1 -vf scale=1920:-2 \"$p\" ;; esac 2>/dev/null; done",
      "_", walls.myDir, bar ? bar.posterDir : ""]
    onExited: walls.posterRev++
  }
  Timer { id: posterKick; interval: 300; onTriggered: if (!posterMaker.running) posterMaker.running = true }

  readonly property var filters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.PNG", "*.JPG", "*.JPEG", "*.WEBP"]
  FolderListModel {
    id: files
    folder: "file://" + walls.themeDir
    nameFilters: walls.filters
    showDirs: false
    sortField: walls.bar && walls.bar.wallSort === "type" ? FolderListModel.Type : FolderListModel.Name
  }
  FolderListModel {
    id: mine
    folder: "file://" + walls.myDir
    // stills, and motion: videos and gifs
    nameFilters: walls.filters.concat(["*.mp4", "*.webm", "*.mkv", "*.mov", "*.m4v", "*.gif",
                                       "*.MP4", "*.WEBM", "*.MKV", "*.MOV", "*.M4V", "*.GIF"])
    onCountChanged: posterKick.restart()
    showDirs: false
    sortField: walls.bar && walls.bar.wallSort === "type" ? FolderListModel.Type : FolderListModel.Name
  }

  // one wallpaper's thumbnail
  component Thumb: Item {
    id: thumb
    required property string filePath
    readonly property bool motion: walls.bar ? walls.bar.isMotion(filePath) : false
    readonly property bool selected: walls.isCurrent(filePath)
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
        // a video / gif shows its poster (once made)
        source: thumb.motion ? (walls.bar ? "file://" + walls.bar.posterFor(thumb.filePath) + "?" + walls.posterRev : "")
                             : "file://" + thumb.filePath
        sourceSize: Qt.size(320, 180)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
      }
    }

    Rectangle {   // motion badge: it plays
      visible: thumb.motion
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      anchors.margins: 8
      width: 26; height: 22; radius: 11
      color: Qt.rgba(0, 0, 0, 0.55)
      border.color: walls.cc.slime; border.width: 1.5
      Text {
        anchors.centerIn: parent
        text: /\.gif$/i.test(thumb.filePath) ? "GIF" : "\uf04b"
        color: walls.cc.slime
        font.family: walls.cc.font; font.bold: true
        font.pixelSize: Math.round((/\.gif$/i.test(thumb.filePath) ? 8 : 10) * walls.fs) }
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

  // a row of choices (CcButtons), for the options at the top
  component Choices: Row {
    id: ch
    property string title
    property var options: []      // [label, value]
    property var current
    signal picked(var value)
    spacing: 6
    CcHeading { cc: walls.cc; anchors.verticalCenter: parent.verticalCenter; text: ch.title }
    Repeater {
      model: ch.options
      CcButton {
        required property var modelData
        cc: walls.cc
        fontSize: 10
        text: modelData[0]
        on: ch.current === modelData[1]
        onClicked: ch.picked(modelData[1])
      }
    }
  }

  Column {
    id: column
    width: parent.width
    spacing: 10

    // sorting, and switching on a timer (these live only here, not in Settings)
    Flow {
      width: parent.width
      spacing: 14
      visible: !!walls.bar
      Choices {
        title: "SORT"
        options: [["name", "name"], ["type", "type"]]
        current: walls.bar ? walls.bar.wallSort : "name"
        onPicked: value => walls.bar.wallSort = value
      }
      Choices {
        title: "SWITCH EVERY"
        options: [["off", 0], ["5 min", 5], ["15 min", 15], ["30 min", 30], ["1 h", 60]]
        current: walls.bar ? walls.bar.wallAuto : 0
        onPicked: value => walls.bar.wallAuto = value
      }
      Choices {
        visible: walls.bar && walls.bar.wallAuto > 0
        title: "FROM"
        options: [["theme", "theme"], ["mine", "mine"], ["all", "all"]]
        current: walls.bar ? walls.bar.wallPool : "all"
        onPicked: value => walls.bar.wallPool = value
      }
      Choices {
        visible: walls.bar && walls.bar.wallAuto > 0
        title: "ORDER"
        options: [["in order", false], ["shuffle", true]]
        current: walls.bar ? walls.bar.wallShuffle : false
        onPicked: value => walls.bar.wallShuffle = value
      }
      CcButton {
        visible: walls.bar && walls.bar.wallAuto > 0
        cc: walls.cc
        fontSize: 10
        icon: "\uf074"
        text: "switch now"
        onClicked: { walls.bar.nextWallpaper(); refreshDelay.restart() }
      }
    }

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
      text: "Drop images, videos or gifs into ~/Pictures/SlimeS-Wallpapers and they show up here, whatever the theme."
      color: walls.cc.ink; opacity: 0.7
      font.family: walls.cc.font; font.pixelSize: Math.round(11 * walls.fs)
    }
  }
}
