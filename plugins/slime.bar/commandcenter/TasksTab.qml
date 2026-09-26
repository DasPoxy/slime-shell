import QtQuick
import Quickshell
import Quickshell.Io

// Tasks: every "- [ ]" checkbox in the Envy vault, grouped by note (most
// recently edited notes first). Ticking one rewrites just that line through
// tasks.py, which refuses if the note changed on disk in the meantime.
Item {
  id: tasks

  property var cc: null
  property var all: []
  property bool showDone: false
  property string error: ""
  readonly property string script: Qt.resolvedUrl("tasks.py").toString().replace("file://", "")

  readonly property var groups: {
    var byNote = {}, order = []
    for (var i = 0; i < all.length; i++) {
      var t = all[i]
      if (t.done && !showDone) continue
      if (!byNote[t.note]) { byNote[t.note] = { note: t.note, file: t.file, mtime: t.mtime, items: [] }; order.push(t.note) }
      byNote[t.note].items.push(t)
    }
    var out = order.map(function(n) { return byNote[n] })
    out.sort(function(a, b) { return b.mtime - a.mtime })
    return out
  }
  readonly property int openCount: all.filter(function(t) { return !t.done }).length

  implicitHeight: header.height + 10 + Math.min(list.contentHeight, 440)

  Process {
    id: lister
    command: ["python3", tasks.script, "list"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { tasks.all = JSON.parse(text) } catch (e) { tasks.error = "Couldn't read the Envy vault" }
      }
    }
  }
  Process {
    id: toggler
    stderr: StdioCollector { onStreamFinished: tasks.error = text.trim() }
    onExited: lister.running = true
  }
  function toggle(task) {
    error = ""
    toggler.command = ["python3", script, "toggle", task.file, String(task.line), task.raw]
    toggler.running = true
  }
  Timer { interval: 5000; repeat: true; running: true; triggeredOnStart: true; onTriggered: lister.running = true }

  Row {
    id: header
    width: parent.width
    spacing: 8
    CcHeading {
      cc: tasks.cc
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - doneButton.width - 8
      text: tasks.error !== "" ? tasks.error.toUpperCase()
        : tasks.openCount + " OPEN TASKS IN ENVY"
    }
    CcButton {
      id: doneButton
      cc: tasks.cc
      icon: ""; text: "Show done"; fontSize: 11
      on: tasks.showDone
      onClicked: tasks.showDone = !tasks.showDone
    }
  }

  ListView {
    id: list
    y: header.height + 10
    width: parent.width
    height: tasks.implicitHeight - y
    clip: true
    spacing: 10
    boundsBehavior: Flickable.StopAtBounds
    model: tasks.groups

    delegate: Rectangle {
      id: group
      required property var modelData
      width: list.width
      height: groupColumn.implicitHeight + 20
      radius: 16
      color: tasks.cc.wash

      Column {
        id: groupColumn
        x: 12; y: 10
        width: parent.width - 24
        spacing: 4

        Text {
          text: "  " + group.modelData.note
          color: tasks.cc.ink
          font.family: tasks.cc.font
          font.pixelSize: 13
          font.weight: Font.Black
        }

        Repeater {
          model: group.modelData.items
          Item {
            id: task
            required property var modelData
            width: groupColumn.width
            height: Math.max(22, label.implicitHeight + 4)

            Rectangle {
              id: box
              y: 3
              width: 16; height: 16; radius: 5
              color: task.modelData.done ? tasks.cc.ink : "transparent"
              border.color: tasks.cc.ink
              border.width: 2
              Text {
                anchors.centerIn: parent
                visible: task.modelData.done
                text: ""
                color: tasks.cc.slime
                font.family: tasks.cc.font
                font.pixelSize: 9
              }
            }
            Text {
              id: label
              x: box.width + 10
              width: parent.width - x
              text: task.modelData.text
              wrapMode: Text.Wrap
              maximumLineCount: 3
              elide: Text.ElideRight
              textFormat: Text.PlainText
              color: tasks.cc.ink
              opacity: task.modelData.done ? 0.5 : 1
              font.family: tasks.cc.font
              font.pixelSize: 12
              font.strikeout: task.modelData.done
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: tasks.toggle(task.modelData)
            }
          }
        }
      }
    }
  }
}
