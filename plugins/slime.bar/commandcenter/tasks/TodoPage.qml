import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import "../../ui"
import ".."

Item {
  id: todoTab
  // the Tasks tab (TasksTab.qml), which this used to sit inside
  property var tasks: null
  property alias renameInput: renameInput
  property alias subEdit: subEdit
  property alias newInput: newField.input
  visible: tasks.tab === "todo"
  y: tasks.contentTop
  width: parent.width
  height: parent.height - y

  // left: the todos
  Column {
    id: todoLeft
    width: parent.width * 0.46
    spacing: 8
    Row {
      width: parent.width
      spacing: 6
      Field {
        tasks: todoTab.tasks
        id: newField
        width: parent.width - hideDone.width - 6
        placeholder: "new todo…  (n)"
        onAccepted: t => tasks.act(["add", t], function(r) { tasks.selectedId = r.id })
      }
      CcButton {
        id: hideDone
        cc: tasks.cc
        anchors.verticalCenter: parent.verticalCenter
        icon: tasks.showDone ? "" : ""
        text: "finished"
        fontSize: 11
        on: tasks.showDone
        onClicked: tasks.showDone = !tasks.showDone
      }
    }
    ListView {
      id: todoList
      width: parent.width
      height: todoTab.height - newField.height - 8 - notesToggle.height - 8 - (tasks.showNotes ? notes.height + 8 : 0)
      clip: true
      spacing: 5
      boundsBehavior: Flickable.StopAtBounds
      model: tasks.todoRows
      currentIndex: {
        for (var i = 0; i < tasks.todoRows.length; i++)
          if (tasks.todoNav[i] === tasks.cursorKey) return i
        return -1
      }
      highlightFollowsCurrentItem: false
      onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
      Rectangle {
        z: 10
        visible: tasks.dragTodo !== "" && tasks.dropY >= 0
        y: tasks.dropY - 1.5
        width: parent.width; height: 3; radius: 1.5
        color: tasks.cc.ink
      }
      delegate: Item {
        id: row
        required property var modelData
        required property int index
        width: todoList.width
        height: modelData.kind === "group" ? 24 : modelData.kind === "super" ? 28 : 38
        SuperHead {
          tasks: todoTab.tasks
          visible: row.modelData.kind === "super"
          anchors.fill: parent
          name: row.modelData.kind === "super" ? row.modelData.name : ""
          collapsed: !!row.modelData.collapsed
          count: row.modelData.count || 0
          here: row.modelData.kind === "super" && tasks.cursor === "s:" + row.modelData.name && tasks.pane === "list"
          onToggle: { tasks.pane = "list"; tasks.cursor = "s:" + name; tasks.setSuperCollapsed(name, !collapsed, ""); tasks.forceActiveFocus() }
          onMenu: (x, y) => { tasks.pane = "list"; tasks.cursor = "s:" + name; tasks.openSuperMenu(name, x, y) }
        }
        // group header: click (or Enter / Space / ← → on it) folds it
        Rectangle {
          visible: row.modelData.kind === "group"
          anchors.fill: parent
          radius: 9
          readonly property bool here: row.modelData.kind === "group" && tasks.cursor === "g:" + row.modelData.name && tasks.pane === "list"
          color: tasks.headColor(row.modelData.name, here, headMouse.containsMouse)
          border.color: tasks.cc.ink
          border.width: here ? 2 : 0
          Row {
            x: 6 + (row.modelData.depth || 0) * 16
            spacing: 6
            anchors.verticalCenter: parent.verticalCenter
            Text { anchors.verticalCenter: parent.verticalCenter; text: row.modelData.collapsed ? "\uf054" : "\uf078"; color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(9 * tasks.fs) }
            Rectangle { width: 12; height: 12; radius: 6; anchors.verticalCenter: parent.verticalCenter; color: tasks.colorOf(row.modelData.name); border.color: tasks.cc.ink; border.width: 1.2; visible: !!row.modelData.name }
            CcHeading { cc: tasks.cc; anchors.verticalCenter: parent.verticalCenter; text: !row.modelData.name ? "NO GROUP" : row.modelData.name.toUpperCase() }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: !!row.modelData.collapsed
              text: row.modelData.count + (row.modelData.count === 1 ? " todo" : " todos")
              color: tasks.cc.ink; opacity: 0.6; font.family: tasks.cc.font; font.pixelSize: Math.round(10 * tasks.fs) }
          }
          MouseArea {
            id: headMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: row.modelData.kind === "group"
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
              tasks.pane = "list"; tasks.cursor = "g:" + row.modelData.name; tasks.forceActiveFocus()
              if (mouse.button === Qt.RightButton) { var p = mapToItem(tasks, mouse.x, mouse.y); tasks.openGroupMenu(row.modelData.name, p.x, p.y) }
              else tasks.toggleGroup(row.modelData.name)
            }
          }
        }
        // a todo
        Rectangle {
          visible: row.modelData.kind === "todo"
          anchors.fill: parent
          anchors.leftMargin: (row.modelData.depth || 0) * 16
          readonly property var t: row.modelData.t
          readonly property bool sel: !!t && t.id === tasks.selectedId
          opacity: t && tasks.dragTodo === t.id ? 0.45 : 1
          radius: 12
          color: tasks.armedDelete !== "" && t && tasks.armedDelete === t.id ? Qt.rgba(1, 0.4, 0.4, 0.6) : sel ? Qt.rgba(1, 1, 1, 0.72) : tasks.cc.wash
          border.color: tasks.cc.ink
          border.width: sel ? (tasks.pane === "list" && tasks.cursor === "" ? 2.4 : 1.4) : 0
          Rectangle { x: 0; width: 6; height: parent.height; radius: 3; color: parent.t ? tasks.colorOf(parent.t.group) : "transparent" }
          Rectangle {
            id: doneBox
            x: 14; anchors.verticalCenter: parent.verticalCenter
            width: 16; height: 16; radius: 8
            color: parent.t && parent.t.done ? tasks.cc.ink : "transparent"
            border.color: tasks.cc.ink; border.width: 2
            MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor
              onClicked: tasks.act(["done", parent.parent.t.id, parent.parent.t.done ? "false" : "true"]) }
          }
          Text {
            x: 40; width: parent.width - x - countText.width - 14
            anchors.verticalCenter: parent.verticalCenter
            text: parent.t ? parent.t.title : ""
            elide: Text.ElideRight
            color: tasks.cc.ink
            opacity: parent.t && parent.t.done ? 0.5 : 1
            font.strikeout: parent.t ? parent.t.done : false
            font.family: tasks.cc.font
            font.pixelSize: Math.round(13 * tasks.fs)
            font.bold: true
          }
          Text {
            id: countText
            anchors.right: parent.right; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: parent.t && parent.t.subs.length ? parent.t.counts.done + "/" + parent.t.subs.length : ""
            color: tasks.cc.ink; opacity: 0.7
            font.family: tasks.cc.font; font.pixelSize: Math.round(11 * tasks.fs) }
          MouseArea {
            id: todoMouse
            anchors.fill: parent
            anchors.leftMargin: 34
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: tasks.dragTodo !== "" ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            preventStealing: true
            property real pressY: 0
            property bool dragging: false
            onPressed: mouse => { pressY = mouse.y; dragging = false }
            onPositionChanged: mouse => {
              if (!(mouse.buttons & Qt.LeftButton)) return
              if (!dragging && Math.abs(mouse.y - pressY) > 6) { dragging = true; tasks.dragTodo = parent.t.id; tasks.selectedId = parent.t.id }
              if (dragging) {
                var p = mapToItem(todoList.contentItem, mouse.x, mouse.y)
                var i = todoList.indexAt(20, p.y)
                var it = i >= 0 ? todoList.itemAtIndex(i) : null
                tasks.dropY = it ? (tasks.todoRows[i].kind === "group" || p.y < it.y + it.height / 2 ? it.y - 3 : it.y + it.height + 2) - todoList.contentY : -1
              }
            }
            onReleased: mouse => {
              if (!dragging) return
              dragging = false
              var p = mapToItem(todoList.contentItem, mouse.x, mouse.y)
              var i = todoList.indexAt(20, p.y)
              var rows = tasks.todoRows
              if (i >= 0) {
                var r = rows[i], it = todoList.itemAtIndex(i)
                if (r.kind === "group") {
                  // on a group's heading: to the top of that group
                  var first = null
                  for (var q = 0; q < tasks.todos.length && !first; q++)
                    if ((tasks.todos[q].group || "") === r.name && tasks.todos[q].id !== tasks.dragTodo) first = tasks.todos[q]
                  if (first) tasks.placeTodo(tasks.dragTodo, first.id, false, r.name)
                } else {
                  tasks.placeTodo(tasks.dragTodo, r.t.id, p.y > it.y + it.height / 2, r.t.group || "")
                }
              }
              tasks.dragTodo = ""
              tasks.dropY = -1
            }
            onClicked: mouse => {
              tasks.cursor = ""
              tasks.selectedId = parent.t.id
              tasks.pane = "list"
              tasks.forceActiveFocus()
              if (mouse.button === Qt.RightButton) {
                var p = mapToItem(tasks, mouse.x, mouse.y)
                tasks.openMenu(parent.t, p.x, p.y)
              }
            }
            onDoubleClicked: { renameInput.text = parent.t.title; renameInput.forceActiveFocus() }
          }
        }
      }
    }
    // your own notes' checkboxes (Envy, ~/Notes …), as before
    CcButton {
      id: notesToggle
      cc: tasks.cc
      icon: tasks.showNotes ? "" : ""
      text: "From your notes"
      fontSize: 11
      on: tasks.showNotes
      onClicked: tasks.showNotes = !tasks.showNotes
    }
    NotesChecklist {
      id: notes
      visible: tasks.showNotes
      width: parent.width
      cc: tasks.cc
      listHeight: 160
    }
  }

  // right: the selected todo's sub-todos
  Rectangle {
    x: todoLeft.width + 14
    width: parent.width - x
    height: parent.height
    radius: 18
    color: Qt.rgba(tasks.cc.paper.r, tasks.cc.paper.g, tasks.cc.paper.b, 0.55)
    border.color: tasks.cc.ink
    border.width: tasks.pane === "subs" ? 2 : 1
    visible: tasks.selected !== null

    Column {
      x: 14; y: 12
      width: parent.width - 28
      spacing: 8
      Item {
        width: parent.width
        height: 26
        Text {
          visible: !renameInput.activeFocus
          width: parent.width
          anchors.verticalCenter: parent.verticalCenter
          text: tasks.selected ? tasks.selected.title : ""
          elide: Text.ElideRight
          color: tasks.cc.ink
          font.family: tasks.cc.displayFont
          font.weight: tasks.cc.displayWeight
          font.pixelSize: Math.round(18 * tasks.fs) }
        TextInput {
          id: renameInput
          visible: activeFocus
          width: parent.width
          anchors.verticalCenter: parent.verticalCenter
          color: tasks.cc.ink
          font.family: tasks.cc.font
          font.pixelSize: Math.round(16 * tasks.fs)
          font.bold: true
          Keys.onReturnPressed: { if (tasks.selected && text.trim() !== "") tasks.act(["rename", tasks.selected.id, text.trim()]); tasks.forceActiveFocus() }
          Keys.onEnterPressed: { if (tasks.selected && text.trim() !== "") tasks.act(["rename", tasks.selected.id, text.trim()]); tasks.forceActiveFocus() }
          Keys.onEscapePressed: tasks.forceActiveFocus()
        }
      }
      Row {
        spacing: 8
        visible: tasks.selected !== null
        Rectangle { width: 10; height: 10; radius: 5; anchors.verticalCenter: parent.verticalCenter; color: tasks.selected ? tasks.colorOf(tasks.selected.group) : "transparent"; visible: tasks.selected && tasks.selected.group !== "" }
        Text {
          text: tasks.selected ? (tasks.selected.group || "no group") + "  ·  " + tasks.selected.counts.done + " of " + tasks.selected.subs.length + " done" + (tasks.selected.counts.doing ? "  ·  " + tasks.selected.counts.doing + " in progress" : "") : ""
          color: tasks.cc.ink; opacity: 0.7
          font.family: tasks.cc.font; font.pixelSize: Math.round(11 * tasks.fs) }
      }
      Field {
        tasks: todoTab.tasks
        id: subField
        width: parent.width
        placeholder: "add a sub-todo…  (a)"
        keepFocus: true
        onAccepted: t => { if (tasks.selected) tasks.act(["sub-add", tasks.selected.id, t]) }
        Component.onCompleted: tasks.subInput = subField.input
      }
    }
    ListView {
      id: subList
      x: 14; y: 104
      width: parent.width - 28
      height: parent.height - y - 10
      clip: true
      spacing: 4
      boundsBehavior: Flickable.StopAtBounds
      model: tasks.selected ? tasks.selected.subs : []
      currentIndex: tasks.subIndex
      onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
      // a change reloads the list (which scrolls back to the top): stay on
      // the sub-todo you were on
      onModelChanged: keepSub.restart()
      // (the reload resets currentIndex and breaks its binding: put both back)
      Timer {
        id: keepSub; interval: 40
        onTriggered: {
          subList.currentIndex = Qt.binding(function() { return tasks.subIndex })
          if (tasks.subIndex >= 0 && tasks.subIndex < subList.count) subList.positionViewAtIndex(tasks.subIndex, ListView.Contain)
        }
      }
      Rectangle {
        z: 10
        visible: tasks.dragSub >= 0 && tasks.dropY >= 0
        y: tasks.dropY - 1.5
        width: parent.width; height: 3; radius: 1.5
        color: tasks.cc.ink
      }
      delegate: Rectangle {
        id: subRow
        required property var modelData
        required property int index
        readonly property bool sel: tasks.pane === "subs" && index === tasks.subIndex
        width: subList.width
        readonly property var pics: modelData.images || []
        readonly property bool picsShown: pics.length > 0 && tasks.picsOpen(tasks.selected, modelData)
        readonly property real textH: Math.max(30, subText.implicitHeight + 12)
        height: textH + (picsShown ? 72 : 0)
        radius: 10
        color: sel ? Qt.rgba(1, 1, 1, 0.7) : Qt.rgba(1, 1, 1, 0.3)
        border.color: tasks.cc.ink
        border.width: sel ? 2 : 0
        StateBox {
          tasks: todoTab.tasks
          x: 8; y: (subRow.textH - height) / 2
          state3: subRow.modelData.state
          MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor
            onClicked: tasks.cycle(tasks.selected, subRow.index) }
        }
        Text {
          id: subText
          visible: !(subEdit.activeFocus && subEdit.index === subRow.index)
          x: 32; width: parent.width - x - 8 - (subRow.pics.length ? picChip.width + 6 : 0)
          y: (subRow.textH - implicitHeight) / 2
          text: subRow.modelData.text
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          color: tasks.cc.ink
          opacity: subRow.modelData.state === "done" ? 0.5 : 1
          font.strikeout: subRow.modelData.state === "done"
          font.italic: subRow.modelData.state === "doing"
          font.family: tasks.cc.font
          font.pixelSize: Math.round(12 * tasks.fs) }
        opacity: tasks.dragSub === index ? 0.45 : 1
        // its pictures: a chip that folds them (i), and a strip of thumbnails
        Rectangle {
          id: picChip
          z: 2
          visible: subRow.pics.length > 0
          anchors.right: parent.right; anchors.rightMargin: 6
          y: (subRow.textH - height) / 2
          width: chipText.implicitWidth + 14; height: 20; radius: 10
          color: chipMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.85) : Qt.rgba(tasks.cc.ink.r, tasks.cc.ink.g, tasks.cc.ink.b, 0.12)
          border.color: tasks.cc.ink; border.width: 1
          Text {
            id: chipText
            anchors.centerIn: parent
            text: "\uf03e " + subRow.pics.length + "  " + (subRow.picsShown ? "\uf077" : "\uf078")
            color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(10 * tasks.fs); font.bold: true
          }
          MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: tasks.togglePics(tasks.selected, subRow.modelData) }
        }
        Row {
          z: 2
          visible: subRow.picsShown
          x: 32; y: subRow.textH
          width: parent.width - x - 8
          height: 64
          spacing: 6
          clip: true
          Repeater {
            model: subRow.picsShown ? subRow.pics : []
            Rectangle {
              required property var modelData
              height: 64; width: Math.max(40, Math.min(140, thumb.implicitWidth > 0 ? 64 * thumb.implicitWidth / Math.max(1, thumb.implicitHeight) : 64))
              radius: 8; clip: true
              color: Qt.rgba(1, 1, 1, 0.5); border.color: tasks.cc.ink; border.width: 1.5
              Image {
                id: thumb
                anchors.fill: parent; anchors.margins: 2
                source: "file://" + parent.modelData.file
                sourceSize.height: 128
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
              }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: tasks.zoomPic = parent.modelData.file }
            }
          }
        }
        MouseArea {
          anchors.fill: parent; anchors.leftMargin: 28
          anchors.bottomMargin: subRow.picsShown ? 72 : 0
          anchors.rightMargin: subRow.pics.length ? picChip.width + 8 : 0
          preventStealing: true
          cursorShape: tasks.dragSub >= 0 ? Qt.ClosedHandCursor : Qt.PointingHandCursor
          property real pressY: 0
          property bool dragging: false
          function target(mouse) {
            var p = mapToItem(subList.contentItem, mouse.x, mouse.y)
            var i = subList.indexAt(20, p.y)
            if (i < 0) i = p.y < 0 ? 0 : subList.count - 1
            return i
          }
          onPressed: mouse => { pressY = mouse.y; dragging = false }
          onPositionChanged: mouse => {
            if (!(mouse.buttons & Qt.LeftButton)) return
            if (!dragging && Math.abs(mouse.y - pressY) > 6) { dragging = true; tasks.dragSub = subRow.index; tasks.pane = "subs" }
            if (dragging) {
              var it = subList.itemAtIndex(target(mouse))
              var down = target(mouse) > subRow.index
              tasks.dropY = it ? (down ? it.y + it.height + 2 : it.y - 3) - subList.contentY : -1
            }
          }
          onReleased: mouse => {
            if (!dragging) return
            dragging = false
            var to = target(mouse)
            if (to !== subRow.index && tasks.selected) {
              tasks.act(["sub-move", tasks.selected.id, String(subRow.index), String(to)])
              tasks.subIndex = to
            }
            tasks.dragSub = -1
            tasks.dropY = -1
          }
          onClicked: { tasks.pane = "subs"; tasks.subIndex = subRow.index; tasks.forceActiveFocus() }
          onDoubleClicked: { subEdit.index = subRow.index; subEdit.text = subRow.modelData.text; subEdit.forceActiveFocus() }
        }
      }
    }
    // inline editor for a sub-todo (e / F2 / double-click)
    TextInput {
      id: subEdit
      property int index: -1
      visible: activeFocus
      x: subList.x + 32
      y: subList.y + (subList.itemAtIndex(index) ? subList.itemAtIndex(index).y - subList.contentY + 7 : 0)
      width: subList.width - 40
      color: tasks.cc.ink
      font.family: tasks.cc.font
      font.pixelSize: Math.round(12 * tasks.fs)
      Rectangle { anchors.fill: parent; anchors.margins: -4; z: -1; radius: 6; color: Qt.rgba(1, 1, 1, 0.9); border.color: tasks.cc.ink }
      Keys.onReturnPressed: { if (tasks.selected && text.trim() !== "") tasks.act(["sub-edit", tasks.selected.id, String(index), text.trim()]); tasks.forceActiveFocus() }
      Keys.onEnterPressed: { if (tasks.selected && text.trim() !== "") tasks.act(["sub-edit", tasks.selected.id, String(index), text.trim()]); tasks.forceActiveFocus() }
      Keys.onEscapePressed: tasks.forceActiveFocus()
    }
  }
  Text {
    visible: tasks.selected === null
    x: todoLeft.width + 24; y: 30
    width: parent.width - x
    wrapMode: Text.Wrap
    text: "No todos yet. Type one on the left and press Enter — each opens into its own list of sub-todos."
    color: tasks.cc.ink; opacity: 0.7
    font.family: tasks.cc.font; font.pixelSize: Math.round(12 * tasks.fs) }
}
