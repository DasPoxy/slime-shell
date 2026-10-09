import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import "../../ui"
import ".."

// ---- shared bits ----------------------------------------------------------------------
Rectangle {
  id: field
  // the Tasks tab (TasksTab.qml), which this used to sit inside
  property var tasks: null
  property alias input: fieldInput
  property string placeholder: ""
  // stay in the box after Enter (for typing several in a row)
  property bool keepFocus: false
  property bool clearOnEnter: true
  signal accepted(string text)
  signal entered()
  height: 30
  radius: 15
  color: Qt.rgba(1, 1, 1, fieldInput.activeFocus ? 0.72 : 0.5)
  border.color: tasks.cc.ink
  border.width: fieldInput.activeFocus ? 2 : 1.2
  TextInput {
    id: fieldInput
    x: 12
    width: parent.width - 24
    anchors.verticalCenter: parent.verticalCenter
    color: tasks.cc.ink
    font.family: tasks.cc.font
    font.pixelSize: Math.round(12 * tasks.fs)
    clip: true
    function submit() {
      var t = text.trim()
      if (field.clearOnEnter) text = ""
      if (t !== "") field.accepted(t)
      if (!field.keepFocus) tasks.forceActiveFocus()
      field.entered()
    }
    // both Enter keys (the keypad one too), handled here so the key isn't
    // passed on to the tab (which would open the highlighted sub-todo)
    Keys.onReturnPressed: submit()
    Keys.onEnterPressed: submit()
    Keys.onEscapePressed: { text = ""; tasks.forceActiveFocus() }
    Text {
      textFormat: Text.PlainText
      visible: fieldInput.text === "" && !fieldInput.activeFocus
      text: field.placeholder
      color: tasks.cc.ink
      opacity: 0.5
      font: fieldInput.font
    }
  }
}
