import QtQuick

// A collapsible command-centre section: click the header to fold it away or
// open it back up. Open/closed state is remembered per title on the bar
// (`bar.ccSections`), so it survives switching tabs and reopening the panel.
// Use this for every group of settings so the pattern stays consistent as
// options are added.
Column {
  id: section
  // the command centre's text size (Settings → Command centre → text size)
  readonly property real fs: cc && cc.fontScale ? cc.fontScale : 1

  required property var cc
  property string title: ""
  property string key: title            // what the open/closed state is saved under
  property string label: title          // header text (defaults to the title)
  property string kind: "scroll"        // gear shown in the header
  property bool defaultOpen: false
  default property alias content: body.data

  readonly property bool open: {
    var map = cc.bar.ccSections
    return map[key] === undefined ? defaultOpen : map[key]
  }

  function toggle() {
    var map = Object.assign({}, cc.bar.ccSections)
    map[key] = !open
    cc.bar.ccSections = map
  }

  width: parent ? parent.width : 0
  spacing: 8

  Rectangle {
    width: section.width
    height: 40
    radius: 14
    color: headerHover.hovered ? Qt.rgba(1, 1, 1, 0.6) : section.cc.wash

    HoverHandler { id: headerHover }

    CcGearButton {
      x: 10
      anchors.verticalCenter: parent.verticalCenter
      cc: section.cc
      kind: section.kind
      label: section.label
      size: 24
      active: section.open
      lit: section.open
    }
    // fold arrow: points down when open, right when closed
    Text {
      anchors.right: parent.right
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      text: ""
      color: section.cc.ink
      font.family: section.cc.font
      font.pixelSize: Math.round(12 * section.fs)
      rotation: section.open ? 90 : 0
      Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: section.toggle()
    }
    CcFocus { onActivate: section.toggle() }
  }

  Column {
    id: body
    x: 8
    width: section.width - 16
    spacing: 10
    visible: section.open
  }
}
