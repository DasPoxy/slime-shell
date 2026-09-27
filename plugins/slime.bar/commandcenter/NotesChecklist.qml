import QtQuick
import Quickshell
import Quickshell.Io

// Checkboxes from your own notes (the Tasks tab's "From your notes" section):
// every "- [ ]" line in your notes folder, grouped by note (most recently
// edited first). The folder is Envy's vault if you use Envy, else ~/Notes or
// ~/Documents/Notes, or any folder you set here (tasks.py). Ticking one
// rewrites just that line, and refuses if the note changed meanwhile.
Item {
  id: tasks
  // the command centre's text size (Settings → Command centre → text size)
  readonly property real fs: cc && cc.fontScale ? cc.fontScale : 1

  property var cc: null
  property real listHeight: 300
  property var all: []
  property bool showDone: false
  property string error: ""
  property string folder: ""
  property string source: ""
  property bool editingFolder: false
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

  implicitHeight: header.height + 10 + folderRow.height + 10 + Math.min(Math.max(list.contentHeight, emptyNote.visible ? 60 : 0), listHeight)

  Process {
    id: folderSetter
    onExited: lister.running = true
  }
  function setFolder(path) {
    editingFolder = false
    folderSetter.command = ["python3", script, "set-folder", path]
    folderSetter.running = true
  }

  Process {
    id: lister
    command: ["python3", tasks.script, "list"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var r = JSON.parse(text)
          tasks.all = r.tasks
          tasks.folder = r.folder
          tasks.source = r.source
        } catch (e) { tasks.error = "Couldn't read the notes folder" }
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
        : tasks.openCount + " OPEN IN YOUR NOTES" + (tasks.source === "envy" ? " (ENVY)" : "")
    }
    CcButton {
      id: doneButton
      cc: tasks.cc
      icon: ""; text: "Show done"; fontSize: 11
      on: tasks.showDone
      onClicked: tasks.showDone = !tasks.showDone
    }
  }

  // which folder, and a way to change it
  Row {
    id: folderRow
    y: header.height + 8
    width: parent.width
    spacing: 8
    Text {
      visible: !tasks.editingFolder
      width: parent.width - changeButton.width - 8
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideMiddle
      text: tasks.folder === "" ? "No notes folder found — set one →"
        : "\uf07c  " + tasks.folder.replace(/^\/home\/[^/]+/, "~") + (tasks.source === "envy" ? "  (Envy vault)" : tasks.source === "default" ? "  (found automatically)" : "")
      color: tasks.cc.ink
      font.family: tasks.cc.font
      font.pixelSize: Math.round(11 * tasks.fs)
      opacity: 0.8
    }
    Rectangle {
      visible: tasks.editingFolder
      width: parent.width - changeButton.width - 8
      height: 26
      radius: 13
      color: Qt.rgba(1, 1, 1, 0.6)
      border.color: tasks.cc.ink
      border.width: 1.5
      TextInput {
        id: folderInput
        x: 10
        width: parent.width - 20
        anchors.verticalCenter: parent.verticalCenter
        color: tasks.cc.ink
        font.family: tasks.cc.font
        font.pixelSize: Math.round(12 * tasks.fs)
        clip: true
        Keys.onReturnPressed: tasks.setFolder(text)
        Keys.onEscapePressed: tasks.editingFolder = false
      }
    }
    CcButton {
      id: changeButton
      cc: tasks.cc
      icon: tasks.editingFolder ? "\uf00c" : "\uf044"
      text: tasks.editingFolder ? "use folder" : "change"
      fontSize: 11
      onClicked: {
        if (tasks.editingFolder) { tasks.setFolder(folderInput.text); return }
        folderInput.text = tasks.folder.replace(/^\/home\/[^/]+/, "~")
        tasks.editingFolder = true
        folderInput.forceActiveFocus()
      }
    }
  }

  Text {
    id: emptyNote
    visible: tasks.all.length === 0
    y: folderRow.y + folderRow.height + 12
    width: parent.width
    wrapMode: Text.Wrap
    text: "Tasks are \"- [ ]\" lines in any .md file in that folder. Leave the folder empty to go back to automatic (Envy, ~/Notes, ~/Documents/Notes)."
    color: tasks.cc.ink
    font.family: tasks.cc.font
    font.pixelSize: Math.round(12 * tasks.fs)
    opacity: 0.7
  }

  ListView {
    id: list
    y: folderRow.y + folderRow.height + 10
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
          font.pixelSize: Math.round(13 * tasks.fs)
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
                font.pixelSize: Math.round(9 * tasks.fs) }
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
              font.pixelSize: Math.round(12 * tasks.fs)
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
