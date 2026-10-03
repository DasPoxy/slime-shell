import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import "../../ui"
import ".."

Rectangle {
  id: helpCard
  // the Tasks tab (TasksTab.qml), which this used to sit inside
  property var tasks: null
  property alias helpFlick: helpFlick
  visible: tasks.showHelp
  z: 60
  anchors.centerIn: parent
  width: Math.min(parent.width - 40, 700)
  height: Math.min(parent.height - 40, helpHead.height + helpFlick.contentHeight + helpFoot.implicitHeight + 44)
  radius: 16
  color: tasks.cc.paper
  border.color: tasks.cc.ink
  border.width: 2
  MouseArea { anchors.fill: parent; onClicked: tasks.showHelp = false }
  Flow {
    id: helpHead
    x: 14; y: 12
    width: parent.width - 28
    spacing: 6
    Repeater {
      model: ["General", "Todo", "Sub-todos", "Task Log", "Progress", "Moving"]
      CcButton {
        required property string modelData
        required property int index
        cc: tasks.cc
        fontSize: 11
        text: modelData
        on: tasks.helpSection === helpIndex
        // sections: 0 general, 1 todo, 2 sub-todos, 3 everywhere, 4 log, 5 progress
        readonly property int helpIndex: [0, 1, 2, 4, 5, 3][index]
        onClicked: tasks.helpSection = helpIndex
      }
    }
  }
  Flickable {
    id: helpFlick
    x: 14; y: helpHead.y + helpHead.height + 10
    width: parent.width - 28
    height: Math.max(0, parent.height - y - helpFoot.implicitHeight - 20)
    contentHeight: helpGrid.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    // key | what it does, in two columns of pairs
    Grid {
      id: helpGrid
      width: helpFlick.width
      columns: width > 520 ? 2 : 1
      columnSpacing: 18
      rowSpacing: 5
      Repeater {
        model: (tasks.helpSections[tasks.helpSection] || ["", []])[1]
        Row {
          required property var modelData
          width: (helpGrid.width - (helpGrid.columns - 1) * helpGrid.columnSpacing) / helpGrid.columns
          spacing: 8
          Text {
            width: Math.min(130, parent.width * 0.42)
            wrapMode: Text.Wrap
            text: parent.modelData[0]
            color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(11 * tasks.fs); font.bold: true
          }
          Text {
            width: parent.width - Math.min(130, parent.width * 0.42) - 8
            wrapMode: Text.Wrap
            text: parent.modelData[1]
            color: tasks.cc.ink; opacity: 0.78; font.family: tasks.cc.font; font.pixelSize: Math.round(11 * tasks.fs)
          }
        }
      }
    }
  }
  Text {
    id: helpFoot
    x: 14
    anchors.bottom: parent.bottom; anchors.bottomMargin: 10
    width: parent.width - 28
    wrapMode: Text.Wrap
    text: "← → sections · Esc or ? closes · text boxes: Enter saves, Esc leaves · todos are plain markdown in " + tasks.folder.replace(/^\/home\/[^/]+/, "~")
    color: tasks.cc.ink; opacity: 0.6
    font.family: tasks.cc.font; font.pixelSize: Math.round(10 * tasks.fs)
  }
}
