import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import "../../ui"
import ".."

Item {
  id: logTab
  // the Tasks tab (TasksTab.qml), which this used to sit inside
  property var tasks: null
  property alias logList: logList
  visible: tasks.tab === "log"
  y: tasks.contentTop
  width: parent.width
  height: parent.height - y

  ListView {
    id: logTodoList
    width: parent.width * 0.3
    height: parent.height
    clip: true
    spacing: 5
    model: tasks.logRows
    // keep the picked row (a heading, or the selected todo) in view as the
    // keyboard moves it, and when the list reloads
    readonly property int pickIndex: tasks.logNav.indexOf(tasks.logCursor !== "" ? tasks.logCursor : tasks.selectedId)
    onPickIndexChanged: if (pickIndex >= 0) positionViewAtIndex(pickIndex, ListView.Contain)
    onCountChanged: Qt.callLater(function() { if (logTodoList.pickIndex >= 0) logTodoList.positionViewAtIndex(logTodoList.pickIndex, ListView.Contain) })
    delegate: Item {
      id: logRow
      required property var modelData
      width: logTodoList.width
      height: modelData.kind === "group" ? 24 : modelData.kind === "super" ? 28 : 44
      SuperHead {
        tasks: logTab.tasks
        visible: logRow.modelData.kind === "super"
        anchors.fill: parent
        name: logRow.modelData.kind === "super" ? logRow.modelData.name : ""
        collapsed: !!logRow.modelData.collapsed
        count: logRow.modelData.count || 0
        here: logRow.modelData.kind === "super" && tasks.logCursor === "s:" + logRow.modelData.name && tasks.logPane === "list"
        onToggle: { tasks.logPane = "list"; tasks.logCursor = "s:" + name; tasks.setSuperCollapsed(name, !collapsed, "log"); tasks.forceActiveFocus() }
        onMenu: (x, y) => { tasks.logPane = "list"; tasks.logCursor = "s:" + name; tasks.openSuperMenu(name, x, y) }
      }
      // group heading: click (or the keyboard) folds it
      Rectangle {
        visible: logRow.modelData.kind === "group"
        anchors.fill: parent
        radius: 9
        readonly property bool here: logRow.modelData.kind === "group" && tasks.logCursor === "g:" + logRow.modelData.name && tasks.logPane === "list"
        color: tasks.headColor(logRow.modelData.name, here, logHeadMouse.containsMouse)
        border.color: tasks.cc.ink
        border.width: here ? 2 : 0
        Row {
          x: 6 + (logRow.modelData.depth || 0) * 16; spacing: 6
          anchors.verticalCenter: parent.verticalCenter
          Text { textFormat: Text.PlainText; anchors.verticalCenter: parent.verticalCenter; text: logRow.modelData.collapsed ? "\uf054" : "\uf078"; color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(9 * tasks.fs) }
          Rectangle { width: 12; height: 12; radius: 6; anchors.verticalCenter: parent.verticalCenter; color: tasks.colorOf(logRow.modelData.name); border.color: tasks.cc.ink; border.width: 1.2; visible: !!logRow.modelData.name }
          CcHeading { cc: tasks.cc; anchors.verticalCenter: parent.verticalCenter; text: !logRow.modelData.name ? "NO GROUP" : logRow.modelData.name.toUpperCase() }
          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            visible: !!logRow.modelData.collapsed
            text: logRow.modelData.count + (logRow.modelData.count === 1 ? " todo" : " todos")
            color: tasks.cc.ink; opacity: 0.6; font.family: tasks.cc.font; font.pixelSize: Math.round(10 * tasks.fs) }
        }
        MouseArea {
          id: logHeadMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          enabled: logRow.modelData.kind === "group"
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: mouse => {
            tasks.logPane = "list"; tasks.logCursor = "g:" + logRow.modelData.name; tasks.forceActiveFocus()
            if (mouse.button === Qt.RightButton) { var p = mapToItem(tasks, mouse.x, mouse.y); tasks.openGroupMenu(logRow.modelData.name, p.x, p.y) }
            else tasks.toggleLogGroup(logRow.modelData.name)
          }
        }
      }
      Rectangle {
      visible: logRow.modelData.kind === "todo"
      anchors.fill: parent
      anchors.leftMargin: (logRow.modelData.depth || 0) * 16
      readonly property var modelData: logRow.modelData.kind === "todo" ? logRow.modelData.t : ({ id: "", title: "", group: "", counts: { doing: 0 }, logCount: 0 })
      readonly property bool sel: modelData.id === tasks.selectedId
      radius: 12
      color: sel ? Qt.rgba(1, 1, 1, 0.72) : tasks.cc.wash
      border.color: tasks.cc.ink
      border.width: sel ? (tasks.logCursor === "" ? 2.2 : 1.2) : 0
      Rectangle { width: 6; height: parent.height; radius: 3; color: tasks.colorOf(parent.modelData.group) }
      Column {
        x: 14; anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 22
        Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: parent.parent.modelData.title; color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(12 * tasks.fs); font.bold: true }
        Text {
          textFormat: Text.PlainText
          width: parent.width; elide: Text.ElideRight
          text: (parent.parent.modelData.counts.doing ? " " + parent.parent.modelData.counts.doing + " in progress · " : "") + parent.parent.modelData.logCount + " log entries"
          color: tasks.cc.ink; opacity: 0.65; font.family: tasks.cc.font; font.pixelSize: Math.round(10 * tasks.fs) }
      }
      MouseArea { anchors.fill: parent; onClicked: { tasks.logCursor = ""; tasks.selectedId = parent.modelData.id; tasks.forceActiveFocus() } }
      }
    }
  }

  Item {
    x: logTodoList.width + 14
    width: parent.width - x
    height: parent.height
    visible: tasks.selected !== null

    // the sub-todos, shifting across as they're worked on
    Row {
      id: lanes
      width: parent.width
      height: 150
      spacing: 8
      Repeater {
        model: [["todo", "To do", ""], ["doing", "In progress", ""], ["done", "Done", ""]]
        Rectangle {
          required property var modelData
          width: (lanes.width - 16) / 3
          height: lanes.height
          radius: 14
          color: Qt.rgba(tasks.cc.paper.r, tasks.cc.paper.g, tasks.cc.paper.b, modelData[0] === "doing" ? 0.7 : 0.45)
          border.color: tasks.cc.ink
          border.width: modelData[0] === "doing" ? 1.8 : 1
          CcHeading { x: 10; y: 7; cc: tasks.cc; text: parent.modelData[2] + "  " + parent.modelData[1].toUpperCase() }
          ListView {
            x: 8; y: 26
            width: parent.width - 16
            height: parent.height - 32
            clip: true
            spacing: 3
            id: laneList
            model: tasks.selected ? tasks.selected.subs.filter(function(s) { return s.state === parent.modelData[0] }) : []
            // stay on the picked sub-todo when the lane reloads
            function keepPicked() {
              for (var i = 0; i < count; i++) if (model[i] && model[i].i === tasks.logSub) { positionViewAtIndex(i, ListView.Contain); return }
            }
            onModelChanged: keepLane.restart()
            Timer { id: keepLane; interval: 40; onTriggered: laneList.keepPicked() }
            // ...and as the keyboard moves the pick (up / down, lane to lane)
            Connections {
              target: tasks
              function onLogSubChanged() { laneList.keepPicked() }
              function onLogPaneChanged() { laneList.keepPicked() }
            }
            // click moves it a lane on, right-click a lane back
            delegate: Rectangle {
              id: laneItem
              required property var modelData
              readonly property bool sel: tasks.logPane === "lanes" && tasks.logSub === modelData.i
              width: ListView.view.width
              height: laneText.implicitHeight + 6
              radius: 6
              color: sel ? Qt.rgba(1, 1, 1, 0.8) : laneMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.45) : "transparent"
              border.color: tasks.cc.ink
              border.width: sel ? 1.6 : 0
              Text {
                id: laneText
                x: 4; y: 3
                width: parent.width - 8
                text: "• " + tasks.brief(laneItem.modelData.text)
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                textFormat: Text.PlainText
                color: tasks.cc.ink
                font.family: tasks.cc.font
                font.pixelSize: Math.round(11 * tasks.fs) }
              MouseArea {
                id: laneMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                  tasks.logPane = "lanes"
                  tasks.logSub = laneItem.modelData.i
                  tasks.shift(tasks.selected, laneItem.modelData.i, mouse.button === Qt.RightButton ? -1 : 1)
                  tasks.forceActiveFocus()
                }
              }
            }
          }
        }
      }
    }

    Field {
      tasks: logTab.tasks
      id: logField
      y: lanes.height + 10
      width: parent.width
      // in the lanes, a note is about the sub-todo you've picked there
      readonly property var about: tasks.logPane === "lanes" && tasks.selected && tasks.selected.subs[tasks.logSub] ? tasks.selected.subs[tasks.logSub] : null
      placeholder: about ? "write in the log about “" + tasks.brief(about.text) + "”  (w)" : "write in the log…  (w)"
      onAccepted: t => {
        if (!tasks.selected) return
        var args = ["log", tasks.selected.id, t, "--by", "you"]
        if (about) args = args.concat(["--sub", String(tasks.logSub)])
        tasks.act(args)
      }
      Component.onCompleted: tasks.logInput = logField.input
    }
    CcHeading {
      y: lanes.height + 50
      cc: tasks.cc
      text: "  LOG" + (tasks.logShown.length ? " — " + tasks.logShown.length + (tasks.logShown.length === 1 ? " ENTRY" : " ENTRIES") : "")
      font.underline: tasks.logPane === "entries"
    }
    CcButton {
      anchors.right: parent.right
      y: lanes.height + 44
      cc: tasks.cc
      icon: tasks.logModeIcons[tasks.logMode]
      text: tasks.logModeNames[tasks.logMode] + "  (s)"
      fontSize: 10
      onClicked: { tasks.toggleLogSort(); tasks.forceActiveFocus() }
    }
    ListView {
      id: logList
      y: lanes.height + 70
      width: parent.width
      height: parent.height - y
      clip: true
      spacing: 8
      boundsBehavior: Flickable.StopAtBounds
      model: tasks.logDisplay
      currentIndex: tasks.logPane === "entries" && tasks.logEntryRows.length ? tasks.logEntryRows[Math.min(tasks.logEntry, tasks.logEntryRows.length - 1)] : -1
      onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
      delegate: Item {
        id: logItem
        required property var modelData
        required property int index
        width: logList.width
        height: modelData.kind === "head" ? 26 : entryBox.height
        // a sub-todo's section heading (by sub-todo): click, or the keys, fold it
        Rectangle {
          visible: logItem.modelData.kind === "head"
          anchors.fill: parent
          anchors.leftMargin: -4
          radius: 9
          readonly property bool picked: tasks.logPane === "entries" && logList.currentIndex === logItem.index
          color: picked ? Qt.rgba(1, 1, 1, 0.6) : secMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.25) : "transparent"
          border.color: tasks.cc.ink
          border.width: picked ? 2 : 0
          MouseArea {
            id: secMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: logItem.modelData.kind === "head"
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              tasks.logPane = "entries"
              tasks.logEntry = logItem.index
              tasks.setSectionFolded(logItem.modelData.key, !logItem.modelData.collapsed)
              tasks.forceActiveFocus()
            }
          }
        }
        Row {
          id: headRow
          visible: logItem.modelData.kind === "head"
          x: 4 + (logItem.modelData.level || 0) * 14
          spacing: 8
          anchors.verticalCenter: parent.verticalCenter
          readonly property string what: logItem.modelData.what || ""
          Text { textFormat: Text.PlainText; anchors.verticalCenter: parent.verticalCenter; text: logItem.modelData.collapsed ? "\uf054" : "\uf078"; color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(9 * tasks.fs) }
          StateBox { tasks: logTab.tasks; anchors.verticalCenter: parent.verticalCenter; visible: !!logItem.modelData.sub; state3: logItem.modelData.sub ? logItem.modelData.sub.state : "todo" }
          // super group / group / todo headings in the "all" views
          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            visible: headRow.what === "super" || headRow.what === "todo"
            text: headRow.what === "super" ? "\uf247" : "\uf0ae"
            color: headRow.what === "super" ? tasks.superColor(logItem.modelData.name) : tasks.cc.ink
            style: Text.Outline; styleColor: tasks.cc.ink
            font.family: tasks.cc.font; font.pixelSize: Math.round(12 * tasks.fs)
          }
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: headRow.what === "group"
            width: 10; height: 10; radius: 5
            color: tasks.colorOf(logItem.modelData.group || "")
            border.color: tasks.cc.ink; border.width: 1
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: logList.width - 50 - headRow.x
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: logItem.modelData.kind !== "head" ? "" : logItem.modelData.label
              + (logItem.modelData.collapsed ? "   ·   " + logItem.modelData.count + (logItem.modelData.count === 1 ? " entry" : " entries") : "")
            color: tasks.cc.ink
            font.family: tasks.cc.displayFont; font.weight: tasks.cc.displayWeight; font.pixelSize: Math.round(13 * tasks.fs) }
        }
        Rectangle {
        id: entryBox
        visible: logItem.modelData.kind === "entry"
        readonly property var modelData: logItem.modelData.kind === "entry" ? logItem.modelData.e : ({ time: "", by: "", sub: "", text: "" })
        readonly property bool picked: tasks.logPane === "entries" && logList.currentIndex === logItem.index
        x: (logItem.modelData.level || 0) * 14
        width: logList.width - x
        height: entryText.implicitHeight + 54
        radius: 12
        color: Qt.rgba(1, 1, 1, picked ? 0.75 : 0.5)
        border.color: tasks.cc.ink
        border.width: picked ? 2 : 0
        Text {
          textFormat: Text.PlainText
          x: 10; y: 6
          text: parent.modelData.time + (parent.modelData.by ? "  ·  " + parent.modelData.by : "")
          color: tasks.cc.ink; opacity: 0.7
          font.family: tasks.cc.font; font.pixelSize: Math.round(10 * tasks.fs); font.bold: true
        }
        // what it's about: the todo, and the sub-todo if there is one
        Rectangle {
          x: 8; y: 21
          width: Math.min(parent.width - 16, aboutText.implicitWidth + 16)
          height: 18
          radius: 9
          color: Qt.rgba(tasks.cc.ink.r, tasks.cc.ink.g, tasks.cc.ink.b, 0.12)
          Rectangle { x: 0; width: 5; height: parent.height; radius: 2.5; color: tasks.colorOf(tasks.entryGroup(parent.parent.modelData)) }
          Text {
            id: aboutText
            x: 9; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 14
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: "\uf0ae  " + tasks.entryTag(parent.parent.modelData)
            color: tasks.cc.ink
            font.family: tasks.cc.font; font.pixelSize: Math.round(10 * tasks.fs); font.bold: true
          }
        }
        Text {
          id: entryText
          x: 10; y: 42
          width: parent.width - 20
          text: logTab.tasks ? logTab.tasks.safeMarkdown(parent.modelData.text) : parent.modelData.text
          wrapMode: Text.Wrap
          textFormat: Text.MarkdownText
          color: tasks.cc.ink
          font.family: tasks.cc.font
          font.pixelSize: Math.round(12 * tasks.fs) }
        MouseArea {
          anchors.fill: parent
          onClicked: { tasks.logPane = "entries"; tasks.logEntry = tasks.logEntryRows.indexOf(logItem.index); tasks.forceActiveFocus() }
          onDoubleClicked: tasks.openEntry(logItem.modelData.e, false)
        }
        }
      }
      Text {
        textFormat: Text.PlainText
        visible: tasks.logShown.length === 0
        width: parent.width
        wrapMode: Text.Wrap
        text: "Nothing logged yet. Agents and scripts add entries with\n  slime-tasks log <id> \"…\"   and move sub-todos with   slime-tasks start/finish <id> <n>."
        color: tasks.cc.ink; opacity: 0.65
        font.family: tasks.cc.font; font.pixelSize: Math.round(11 * tasks.fs) }
    }
  }
}
