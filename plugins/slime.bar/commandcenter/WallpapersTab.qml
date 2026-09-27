import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

// Wallpapers: the current theme's backgrounds as a thumbnail grid. Clicking
// one sets it through `omarchy-theme-bg-set` (so the Omarchy background plugin
// and anything else watching the current-background link follow along).
Item {
  id: walls

  property var cc: null
  property string current: ""
  readonly property string themeDir: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/backgrounds"
  readonly property int columns: 3
  readonly property real thumbWidth: width / columns - 10
  readonly property real thumbHeight: Math.round(thumbWidth * 9 / 16)
  readonly property int visibleRows: 3

  implicitHeight: header.height + 10 + Math.min(grid.contentHeight, visibleRows * (thumbHeight + 10))

  Process {
    id: currentProbe
    command: ["readlink", "-f", Quickshell.env("HOME") + "/.local/state/omarchy/current/background"]
    stdout: StdioCollector { onStreamFinished: walls.current = text.trim() }
  }
  Component.onCompleted: currentProbe.running = true

  function setWallpaper(path) {
    walls.current = path
    Quickshell.execDetached(["omarchy-theme-bg-set", path])
  }

  FolderListModel {
    id: files
    folder: "file://" + walls.themeDir
    nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp"]
    showDirs: false
    sortField: FolderListModel.Name
  }

  Row {
    id: header
    width: parent.width
    spacing: 8
    CcHeading {
      cc: walls.cc
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - nextButton.width - 8
      text: files.count + " BACKGROUNDS IN THIS THEME"
    }
    CcButton {
      id: nextButton
      cc: walls.cc
      icon: ""; text: "Next"; fontSize: 11
      onClicked: {
        Quickshell.execDetached(["omarchy-theme-bg-next"])
        refreshDelay.restart()
      }
      Timer { id: refreshDelay; interval: 500; onTriggered: currentProbe.running = true }
    }
  }

  GridView {
    id: grid
    y: header.height + 10
    width: parent.width
    height: walls.implicitHeight - y
    clip: true
    cellWidth: walls.thumbWidth + 10
    cellHeight: walls.thumbHeight + 10
    model: files
    boundsBehavior: Flickable.StopAtBounds

    delegate: Item {
      id: thumb
      required property string filePath
      required property string fileBaseName
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
          text: ""
          color: walls.cc.slime
          font.family: walls.cc.font
          font.pixelSize: 11
        }
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
  }
}
