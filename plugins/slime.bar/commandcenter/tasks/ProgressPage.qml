import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import "../../ui"
import ".."

Item {
  id: progressTab
  // the Tasks tab (TasksTab.qml), which this used to sit inside
  property var tasks: null
  visible: tasks.tab === "progress"
  y: tasks.contentTop
  width: parent.width
  height: parent.height - y

  ListView {
    id: progressList
    width: parent.width
    height: parent.height - archiveBox.height - 10
    clip: true
    spacing: 4
    boundsBehavior: Flickable.StopAtBounds
    model: tasks.progressRows
    delegate: Rectangle {
      id: prow
      required property var modelData
      required property int index
      readonly property int navIndex: {
        var n = 0
        for (var i = 0; i < index; i++) if (tasks.progressRows[i].kind !== "sub") n++
        return n
      }
      readonly property bool sel: modelData.kind !== "sub" && navIndex === tasks.progressIndex && tasks.progressPane === "list"
      readonly property real indent: (modelData.kind === "super" ? 0 : modelData.kind === "group" ? 0 : modelData.kind === "todo" ? 18 : 44)
                                     + (modelData.depth || 0) * 16
      x: indent
      width: progressList.width - indent
      height: modelData.kind === "sub" ? 24 : 36
      radius: 12
      color: modelData.kind === "sub" ? "transparent"
        : modelData.kind === "group" && tasks.armedGroup !== "" && tasks.armedGroup === modelData.name ? Qt.rgba(1, 0.4, 0.4, 0.65)
        : modelData.kind === "super" ? tasks.superHeadColor(modelData.name, sel, false)
        : sel ? Qt.rgba(1, 1, 1, 0.72) : tasks.cc.wash
      border.color: tasks.cc.ink
      border.width: sel ? 2 : 0

      // super group
      Rectangle { visible: prow.modelData.kind === "super"; width: 7; height: parent.height; radius: 3.5; color: tasks.superColor(prow.modelData.name) }
      Row {
        visible: prow.modelData.kind === "super"
        x: 12; anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Text { text: prow.modelData.collapsed ? "\uf054" : "\uf078"; color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(10 * tasks.fs); anchors.verticalCenter: parent.verticalCenter }
        Text { text: "\uf247"; color: tasks.superColor(prow.modelData.name); style: Text.Outline; styleColor: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(14 * tasks.fs); anchors.verticalCenter: parent.verticalCenter }
        Text { text: prow.modelData.kind === "super" ? prow.modelData.name : ""; color: tasks.cc.ink; font.family: tasks.cc.displayFont; font.weight: tasks.cc.displayWeight; font.pixelSize: Math.round(16 * tasks.fs); anchors.verticalCenter: parent.verticalCenter }
        Text { text: prow.modelData.kind !== "super" ? "" : prow.modelData.count + (prow.modelData.count === 1 ? " todo" : " todos"); color: tasks.cc.ink; opacity: 0.6; font.family: tasks.cc.font; font.pixelSize: Math.round(11 * tasks.fs); anchors.verticalCenter: parent.verticalCenter }
      }
      // group
      Row {
        visible: prow.modelData.kind === "group"
        x: 10; anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Text { text: tasks.groupCollapsed(prow.modelData.name, "progress") ? "" : ""; color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(10 * tasks.fs); anchors.verticalCenter: parent.verticalCenter }
        Rectangle { width: 12; height: 12; radius: 6; anchors.verticalCenter: parent.verticalCenter; color: tasks.colorOf(prow.modelData.name); border.color: tasks.cc.ink; border.width: 1.2; visible: prow.modelData.name !== "" }
        Text { text: !prow.modelData.name ? "No group" : prow.modelData.name; color: tasks.cc.ink; font.family: tasks.cc.displayFont; font.weight: tasks.cc.displayWeight; font.pixelSize: Math.round(15 * tasks.fs); anchors.verticalCenter: parent.verticalCenter }
        Text { text: prow.modelData.kind !== "group" ? "" : prow.modelData.count + (prow.modelData.count === 1 ? " todo" : " todos"); color: tasks.cc.ink; opacity: 0.6; font.family: tasks.cc.font; font.pixelSize: Math.round(11 * tasks.fs); anchors.verticalCenter: parent.verticalCenter }
      }
      // todo
      Row {
        visible: prow.modelData.kind === "todo"
        x: 10; anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Text { text: prow.modelData.kind === "todo" && prow.modelData.t.subs.length ? (tasks.expanded["t:" + prow.modelData.t.id] ? "" : "") : " "; color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(9 * tasks.fs); anchors.verticalCenter: parent.verticalCenter }
        Text {
          width: prow.width * 0.4
          elide: Text.ElideRight
          text: prow.modelData.kind === "todo" ? prow.modelData.t.title : ""
          color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(12 * tasks.fs); font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }
      }
      // sub
      Row {
        visible: prow.modelData.kind === "sub"
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        StateBox { tasks: progressTab.tasks; state3: prow.modelData.kind === "sub" ? prow.modelData.s.state : "todo"; anchors.verticalCenter: parent.verticalCenter; scale: 0.8 }
        Text {
          text: prow.modelData.kind === "sub" ? tasks.brief(prow.modelData.s.text) : ""
          color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(11 * tasks.fs)
          opacity: prow.modelData.kind === "sub" && prow.modelData.s.state === "done" ? 0.55 : 1
          anchors.verticalCenter: parent.verticalCenter
        }
      }
      // progress bar and percentage (groups and todos)
      Meter {
        tasks: progressTab.tasks
        visible: prow.modelData.kind !== "sub"
        anchors.right: pctText.left; anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width * 0.3
        value: (prow.modelData.kind === "group" || prow.modelData.kind === "super") ? prow.modelData.pct : prow.modelData.kind === "todo" ? tasks.pct(prow.modelData.t) : 0
        fill: prow.modelData.kind === "group" && prow.modelData.name !== "" ? tasks.colorOf(prow.modelData.name) : tasks.cc.ink
      }
      Text {
        id: pctText
        visible: prow.modelData.kind !== "sub"
        anchors.right: archiveBtn.visible ? archiveBtn.left : parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: 38
        horizontalAlignment: Text.AlignRight
        text: Math.round(100 * ((prow.modelData.kind === "group" || prow.modelData.kind === "super") ? prow.modelData.pct : prow.modelData.kind === "todo" ? tasks.pct(prow.modelData.t) : 0)) + "%"
        color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(12 * tasks.fs); font.bold: true
      }
      CcButton {
        id: archiveBtn
        visible: prow.modelData.kind === "todo" && tasks.pct(prow.modelData.t) >= 1
        cc: tasks.cc
        anchors.right: parent.right; anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        icon: ""; text: "archive"; fontSize: 10
        onClicked: tasks.act(["archive", prow.modelData.t.id])
      }
      MouseArea {
        anchors.fill: parent
        anchors.rightMargin: archiveBtn.visible ? archiveBtn.width + 10 : 0
        enabled: prow.modelData.kind !== "sub"
        onClicked: { tasks.progressIndex = prow.navIndex; tasks.toggleExpand(prow.modelData); tasks.forceActiveFocus() }
      }
    }
  }

  // the archive: search it, bring lists back
  Rectangle {
    id: archiveBox
    y: parent.height - height
    width: parent.width
    height: 150
    radius: 16
    color: Qt.rgba(tasks.cc.paper.r, tasks.cc.paper.g, tasks.cc.paper.b, 0.5)
    border.color: tasks.cc.ink
    border.width: 1
    Row {
      x: 12; y: 10
      spacing: 10
      CcHeading { cc: tasks.cc; text: "  ARCHIVE (" + tasks.archivedTodos.length + ")"; anchors.verticalCenter: parent.verticalCenter }
      Field {
        tasks: progressTab.tasks
        id: archiveField
        width: 260
        placeholder: "search the archive…  (/)"
        clearOnEnter: false
        onEntered: if (tasks.archiveRows.length) {
          tasks.progressPane = "archive"
          var first = 0
          while (first < tasks.archiveRows.length - 1 && tasks.archiveRows[first].kind !== "todo") first++
          tasks.archiveIndex = first
        }
        input.onTextChanged: tasks.archiveQuery = input.text
        Component.onCompleted: tasks.archiveInput = archiveField.input
      }
    }
    ListView {
      id: archiveList
      x: 12; y: 48
      width: parent.width - 24
      height: parent.height - 56
      clip: true
      spacing: 4
      model: tasks.archiveRows
      currentIndex: tasks.progressPane === "archive" ? tasks.archiveIndex : -1
      onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
      delegate: Item {
        id: arow
        required property var modelData
        required property int index
        width: ListView.view.width
        height: modelData.kind === "head" ? 24 : modelData.kind === "shead" ? 28 : 28
        // a super group's heading: click folds it; restore all of it from here
        SuperHead {
          tasks: progressTab.tasks
          visible: arow.modelData.kind === "shead"
          anchors.fill: parent
          anchors.leftMargin: -6; anchors.rightMargin: -2
          name: arow.modelData.kind === "shead" ? arow.modelData.name : ""
          collapsed: !!arow.modelData.collapsed
          count: arow.modelData.count || 0
          here: arow.modelData.kind === "shead" && tasks.progressPane === "archive" && arow.index === tasks.archiveIndex
          onToggle: { tasks.progressPane = "archive"; tasks.archiveIndex = arow.index; tasks.setSuperCollapsed(name, !collapsed, "archive"); tasks.forceActiveFocus() }
          onMenu: (x, y) => { tasks.progressPane = "archive"; tasks.archiveIndex = arow.index; tasks.openSuperMenu(name, x, y) }
          CcButton {
            anchors.right: parent.right; anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            cc: tasks.cc
            icon: "\uf0e2"; text: "restore all  (r)"; fontSize: 10
            onClicked: tasks.restoreSuper(arow.modelData.name)
          }
        }
        // a group's heading: click (or the keys) folds it
        Rectangle {
          visible: arow.modelData.kind === "head"
          anchors.fill: parent
          anchors.leftMargin: -6; anchors.rightMargin: -2
          radius: 9
          readonly property bool here: tasks.progressPane === "archive" && arow.index === tasks.archiveIndex
          color: tasks.headColor(arow.modelData.name, here, archHeadMouse.containsMouse)
          border.color: tasks.cc.ink
          border.width: here ? 2 : 0
          MouseArea {
            id: archHeadMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: arow.modelData.kind === "head"
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              tasks.progressPane = "archive"
              tasks.archiveIndex = arow.index
              tasks.setGroupCollapsed(arow.modelData.name, !arow.modelData.collapsed, "archive")
              tasks.forceActiveFocus()
            }
          }
        }
        CcButton {
          visible: arow.modelData.kind === "head"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          cc: tasks.cc
          icon: "\uf0e2"; text: "restore all  (r)"; fontSize: 10
          onClicked: tasks.restoreGroup(arow.modelData.name)
        }
        Row {
          visible: arow.modelData.kind === "head"
          x: (arow.modelData.depth || 0) * 14
          spacing: 6
          anchors.verticalCenter: parent.verticalCenter
          Text { anchors.verticalCenter: parent.verticalCenter; text: arow.modelData.collapsed ? "\uf054" : "\uf078"; color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(9 * tasks.fs) }
          Rectangle { width: 10; height: 10; radius: 5; anchors.verticalCenter: parent.verticalCenter; color: tasks.colorOf(arow.modelData.name); border.color: tasks.cc.ink; border.width: 1; visible: !!arow.modelData.name }
          CcHeading { cc: tasks.cc; anchors.verticalCenter: parent.verticalCenter; text: arow.modelData.kind !== "head" ? "" : arow.modelData.name ? arow.modelData.name.toUpperCase() : "NO GROUP" }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !!arow.modelData.collapsed
            text: arow.modelData.count + (arow.modelData.count === 1 ? " todo" : " todos")
            color: tasks.cc.ink; opacity: 0.6; font.family: tasks.cc.font; font.pixelSize: Math.round(10 * tasks.fs) }
        }
        Item {
          visible: arow.modelData.kind === "todo"
          anchors.fill: parent
          anchors.leftMargin: (arow.modelData.depth || 0) * 14
          readonly property var t: arow.modelData.kind === "todo" ? arow.modelData.t : ({ id: "", title: "", group: "", counts: { done: 0 }, subs: [] })
          // d once: waiting for the second d
          readonly property bool armed: tasks.armedDelete !== "" && tasks.armedDelete === t.id
          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: -6; anchors.rightMargin: -2
            radius: 10
            visible: parent.armed || (tasks.progressPane === "archive" && arow.index === tasks.archiveIndex)
            color: parent.armed ? Qt.rgba(1, 0.4, 0.4, 0.6) : Qt.rgba(1, 1, 1, 0.7)
            border.color: tasks.cc.ink; border.width: tasks.progressPane === "archive" && arow.index === tasks.archiveIndex ? 2 : 0
          }
          Rectangle { x: 6; width: 6; height: 20; radius: 3; anchors.verticalCenter: parent.verticalCenter; color: tasks.colorOf(parent.t.group) }
          Text {
            x: 20; width: parent.width - restoreBtn.width - 30
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: parent.armed ? "d again: delete " + parent.t.title + " (it goes to the trash)"
              : parent.t.title + "  ·  " + parent.t.counts.done + "/" + parent.t.subs.length
            color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(12 * tasks.fs) }
          MouseArea {
            anchors.fill: parent
            anchors.rightMargin: restoreBtn.width + 8
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
              tasks.progressPane = "archive"
              tasks.archiveIndex = arow.index
              tasks.forceActiveFocus()
              if (mouse.button === Qt.RightButton) {
                var p = mapToItem(tasks, mouse.x, mouse.y)
                tasks.openMenu(parent.t, p.x, p.y, true)
              }
            }
          }
          CcButton {
            id: restoreBtn
            cc: tasks.cc
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            icon: "\uf0e2"; text: "restore"; fontSize: 10
            onClicked: tasks.restoreArchived(parent.t)
          }
        }
      }
    }
  }
}
