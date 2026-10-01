import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../commandcenter"

// SlimeS-Dock's contents, over the dock's slime (drawn by the bar's shader in
// Bar.qml): the icons, a label while hovering one, the right-click menu, the
// add-apps panel that oozes out of the dock, drag-and-drop, and hiding until
// hovered. Positions are worked out in bar space (`along` the dock's edge,
// `away` from it) and mapped into this window with pt().
Item {
  id: dock

  required property var bar
  required property var geo        // Bar.qml's dockWin: sizes and positions
  required property var win        // the dock's PanelWindow

  readonly property string edge: geo.edge
  readonly property bool vert: geo.vert

  // ---- hiding until hovered ----
  property bool hovered: false
  property bool dragOver: false
  readonly property bool shown: !bar.dockAutoHide || hovered || dragOver || panelOpen || menuIndex >= 0 || linger.running
  property real reveal: shown ? 1 : 0
  Behavior on reveal { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
  readonly property real hideOffset: (1 - reveal) * (geo.thick + 30)
  Timer { id: linger; interval: 700 }                 // a moment's grace after the pointer leaves
  onHoveredChanged: if (!hovered) linger.restart()

  // bar space → this window (with the hide slide)
  function pt(a, w) { return ptAt(a, w, hideOffset) }
  function ptAt(a, w, off) {
    var al = a - geo.w0
    if (edge === "top") return Qt.point(al, w - off)
    if (edge === "bottom") return Qt.point(al, height - w + off)
    if (edge === "left") return Qt.point(w - off, al)
    return Qt.point(width - w + off, al)
  }
  // a bar-space box (along a0..a1, away w0..w1) as a window rect
  function box(a0, a1, w0, w1) {
    var p = pt(a0, w0), q = pt(a1, w1)
    return Qt.rect(Math.min(p.x, q.x), Math.min(p.y, q.y), Math.abs(q.x - p.x), Math.abs(q.y - p.y))
  }
  function itemAlong(i) { return geo.a0 + geo.gap + geo.s / 2 + i * (geo.s + geo.gap) }
  readonly property real iconAway: geo.s / 2 + 8

  // ---- the input region: the dock (or a thin strip at the edge while tucked
  // away); the whole window while the panel or menu is open ----
  readonly property rect hotRect: panelOpen || menuIndex >= 0 ? Qt.rect(0, 0, width, height)
    : reveal < 0.5 ? edgeStrip
    : box(geo.a0 - 6, geo.a0 + geo.dockLen + 6, 0, geo.thick)
  // tucked away: a thin strip right at the screen edge (not slid away with the dock)
  readonly property rect edgeStrip: {
    var p = ptAt(geo.a0, 0, 0), q = ptAt(geo.a0 + geo.dockLen, 6, 0)
    return Qt.rect(Math.min(p.x, q.x), Math.min(p.y, q.y), Math.max(1, Math.abs(q.x - p.x)), Math.max(1, Math.abs(q.y - p.y)))
  }
  property alias hotArea: hot
  Item {
    id: hot
    x: dock.hotRect.x; y: dock.hotRect.y
    width: dock.hotRect.width; height: dock.hotRect.height
    HoverHandler { onHoveredChanged: dock.hovered = hovered }
  }

  // a click on the dock window's empty air closes an open menu / panel
  MouseArea {
    anchors.fill: parent
    enabled: dock.menuIndex >= 0 || dock.panelOpen
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: dock.closeAll()
  }
  function closeAll() { if (menuIndex >= 0) closeMenu(); if (panelOpen) closePanel() }

  // ---- apps ----
  readonly property var allApps: DesktopEntries.applications.values
    .filter(function(e) { return !e.noDisplay })
    .sort(function(a, b) { return a.name.localeCompare(b.name) })
  function entryFor(id) {
    var e = DesktopEntries.byId(id)
    if (e) return e
    for (var i = 0; i < allApps.length; i++) if (allApps[i].id === id) return allApps[i]
    return null
  }
  function baseName(p) { return String(p).replace(/\/+$/, "").split("/").pop() || p }
  function nameOf(it) {
    if (it.kind === "app") { var e = entryFor(it.id); return e ? e.name : it.id }
    return it.path === Quickshell.env("HOME") ? "Home" : baseName(it.path)
  }
  function iconOf(it) {
    if (it.kind === "app") { var e = entryFor(it.id); return Quickshell.iconPath(e ? e.icon : "", "application-x-executable") }
    if (it.kind === "file") return Quickshell.iconPath("text-x-generic", "unknown")
    var special = { Documents: "folder-documents", Downloads: "folder-download", Pictures: "folder-pictures",
      Music: "folder-music", Videos: "folder-videos", Desktop: "user-desktop" }
    var n = it.path === Quickshell.env("HOME") ? "user-home" : special[baseName(it.path)] || "folder"
    return Quickshell.iconPath(n, "folder")
  }
  function launch(it) {
    if (it.kind === "app") { var e = entryFor(it.id); if (e) e.execute() }
    else Quickshell.execDetached(["xdg-open", it.path])
  }

  // ---- the icons ----
  Repeater {
    model: dock.bar.dockItems.length + 1
    Item {
      id: slot
      required property int index
      readonly property bool isAdd: index === dock.bar.dockItems.length
      readonly property var it: isAdd ? null : dock.bar.dockItems[index]
      readonly property point c: dock.pt(dock.itemAlong(index), dock.iconAway)
      width: dock.geo.s; height: dock.geo.s
      x: c.x - width / 2; y: c.y - height / 2
      opacity: dock.reveal
      scale: hov.hovered ? 1.16 : 1
      Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
      // a little bob, out of step with its neighbours
      transform: Translate {
        x: dock.vert ? Math.sin(dock.bar.animTime * 1.2 + slot.index) * 1.2 : 0
        y: dock.vert ? 0 : Math.sin(dock.bar.animTime * 1.2 + slot.index) * 1.2
      }
      Image {
        visible: !slot.isAdd
        anchors.fill: parent
        source: slot.it ? dock.iconOf(slot.it) : ""
        sourceSize.width: dock.geo.s * 2; sourceSize.height: dock.geo.s * 2
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: true
      }
      // the add button: a bubble of goo with a plus in it
      Rectangle {
        visible: slot.isAdd
        anchors.fill: parent; anchors.margins: dock.geo.s * 0.12
        radius: width / 2
        color: Qt.rgba(1, 1, 1, hov.hovered ? 0.5 : 0.28)
        border.color: dock.bar.slimeInk; border.width: 2
        Text {
          anchors.centerIn: parent
          text: ""
          color: dock.bar.slimeInk
          font.family: dock.bar.fontFamily; font.pixelSize: dock.geo.s * 0.38
        }
      }
      HoverHandler { id: hov }
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
          if (slot.isAdd) { dock.togglePanel(); return }
          if (mouse.button === Qt.RightButton) dock.openMenu(slot.index)
          else { dock.closeMenu(); dock.launch(slot.it) }
        }
      }
    }
  }

  // the hovered icon's name, just inside the dock
  Rectangle {
    id: label
    property int index: -1
    readonly property var target: index >= 0 && index <= dock.bar.dockItems.length ? index : -1
    visible: target >= 0 && dock.menuIndex < 0 && !dock.panelOpen && dock.reveal > 0.9
    readonly property point c: dock.pt(dock.itemAlong(Math.max(0, target)), dock.geo.thick + 22)
    width: labelText.implicitWidth + 18; height: 24; radius: 12
    x: Math.max(2, Math.min(dock.width - width - 2, c.x - width / 2))
    y: Math.max(2, Math.min(dock.height - height - 2, c.y - height / 2))
    color: Qt.rgba(1, 1, 1, 0.85)
    border.color: dock.bar.slimeInk; border.width: 1.5
    Text {
      id: labelText
      anchors.centerIn: parent
      text: label.target < 0 ? "" : label.target === dock.bar.dockItems.length ? "add apps…" : dock.nameOf(dock.bar.dockItems[label.target])
      color: dock.bar.slimeInk
      font.family: dock.bar.fontFamily; font.pixelSize: 12; font.bold: true
    }
  }
  // which icon the pointer is over (for the label)
  HoverHandler {
    id: dockHover
    onPointChanged: {
      var p = point.position, best = -1
      for (var i = 0; i <= dock.bar.dockItems.length; i++) {
        var c = dock.pt(dock.itemAlong(i), dock.iconAway)
        if (Math.abs(p.x - c.x) < dock.geo.s * 0.6 && Math.abs(p.y - c.y) < dock.geo.s * 0.6) best = i
      }
      label.index = best
    }
    onHoveredChanged: if (!hovered) label.index = -1
  }

  // ---- drag folders / files / .desktop files onto the dock ----
  DropArea {
    x: hot.x; y: hot.y; width: hot.width; height: hot.height
    keys: ["text/uri-list"]
    onEntered: dock.dragOver = true
    onExited: dock.dragOver = false
    onDropped: drop => {
      dock.dragOver = false
      if (!drop.hasUrls) return
      var paths = []
      for (var i = 0; i < drop.urls.length; i++) {
        var u = String(drop.urls[i])
        if (u.indexOf("file://") === 0) paths.push(decodeURIComponent(u.slice(7)))
      }
      if (!paths.length) return
      sorter.command = ["sh", "-c", "for p; do if [ -d \"$p\" ]; then echo \"folder\t$p\"; " +
        "elif [ \"${p##*.}\" = desktop ]; then echo \"app\t$p\"; else echo \"file\t$p\"; fi; done", "sort"].concat(paths)
      sorter.running = true
      drop.acceptProposedAction()
    }
  }
  Process {
    id: sorter
    stdout: SplitParser {
      onRead: line => {
        var tab = line.indexOf("\t")
        var kind = line.slice(0, tab), path = line.slice(tab + 1)
        if (kind === "app") dock.bar.dockAdd({ kind: "app", id: dock.baseName(path).replace(/\.desktop$/, "") })
        else dock.bar.dockAdd({ kind: kind, path: path })
      }
    }
  }

  // ---- right-click menu ----
  // the menu is a drip of the dock's slime like the add-apps panel (the
  // shader draws whichever `blob` is showing from geo.panelProgress)
  property int menuIndex: -1
  property int menuFor: -1          // the icon the menu blob hangs from (kept while it shrinks away)
  property string blob: "panel"
  property int menuRow: 0
  function openMenu(i) {
    if (panelOpen) { panelOpen = false; geo.panelProgress = 0 }
    if (menuIndex >= 0) geo.panelProgress = 0          // straight to the new icon's menu
    blob = "menu"
    menuFor = i
    menuIndex = i
    menuRow = 0
    grow(1, 450)
    menuKeys.forceActiveFocus()
  }
  function closeMenu() {
    if (menuIndex < 0) return
    menuIndex = -1
    grow(0, 280)
  }
  function grow(to, ms) {
    panelAnim.stop(); panelAnim.to = to; panelAnim.duration = ms
    panelAnim.easing.type = to > 0 ? Easing.OutQuad : Easing.InQuad
    panelAnim.start()
  }
  readonly property var menuItems: {
    if (menuIndex < 0 || menuIndex >= bar.dockItems.length) return []
    var it = bar.dockItems[menuIndex]
    var back = vert ? "up" : "left", on = vert ? "down" : "right"
    return [
      { act: "open", text: (it.kind === "app" ? "  launch " : "  open ") + nameOf(it) },
      { act: "back", text: "  move " + back, off: menuIndex === 0 },
      { act: "on", text: "  move " + on, off: menuIndex === bar.dockItems.length - 1 },
      { act: "remove", text: "  remove from the dock" }
    ]
  }
  function runMenu(act) {
    var i = menuIndex, it = bar.dockItems[i]
    if (act === "open") launch(it)
    else if (act === "back") { bar.dockMove(i, -1); menuIndex = i - 1; menuFor = i - 1; return }
    else if (act === "on") { bar.dockMove(i, 1); menuIndex = i + 1; menuFor = i + 1; return }
    else if (act === "remove") bar.dockRemove(i)
    closeMenu()
  }
  Item {
    id: menu
    readonly property rect r: dock.box(dock.geo.menuX + 10, dock.geo.menuX + dock.geo.menuW - 10,
                                       dock.geo.thick + 10, dock.geo.thick + dock.geo.menuH - 20)
    x: r.x; y: r.y; width: r.width; height: r.height
    visible: dock.menuIndex >= 0 && dock.geo.panelProgress > 0.55
    opacity: Math.max(0, (dock.geo.panelProgress - 0.55) / 0.45)
    // keys: ↑↓ pick, Enter runs it, Esc closes
    Item {
      id: menuKeys
      focus: dock.menuIndex >= 0
      Keys.onPressed: event => {
        var n = dock.menuItems.length
        if (event.key === Qt.Key_Escape) dock.closeMenu()
        else if (event.key === Qt.Key_Down || event.text === "j") dock.menuRow = Math.min(n - 1, dock.menuRow + 1)
        else if (event.key === Qt.Key_Up || event.text === "k") dock.menuRow = Math.max(0, dock.menuRow - 1)
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
                 && dock.menuItems[dock.menuRow] && !dock.menuItems[dock.menuRow].off) dock.runMenu(dock.menuItems[dock.menuRow].act)
        else return
        event.accepted = true
      }
    }
    Column {
      id: menuCol
      width: parent.width
      spacing: 2
      Text {
        width: parent.width
        elide: Text.ElideRight
        text: dock.menuIndex >= 0 && dock.menuIndex < dock.bar.dockItems.length ? dock.nameOf(dock.bar.dockItems[dock.menuIndex]).toUpperCase() : ""
        color: dock.bar.slimeInk; opacity: 0.7
        font.family: dock.bar.fontFamily; font.pixelSize: 10; font.bold: true; font.letterSpacing: 0.6
        bottomPadding: 2
      }
      Repeater {
        model: dock.menuItems
        Rectangle {
          required property var modelData
          required property int index
          readonly property bool here: dock.menuRow === index
          width: menuCol.width; height: 26; radius: 10
          opacity: modelData.off ? 0.4 : 1
          color: (here || rowMouse.containsMouse) && !modelData.off ? Qt.rgba(1, 1, 1, 0.6) : Qt.rgba(1, 1, 1, 0.15)
          border.color: dock.bar.slimeInk; border.width: here ? 1.5 : 0
          Text {
            x: 10; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 16; elide: Text.ElideRight
            text: parent.modelData.text
            color: dock.bar.slimeInk
            font.family: dock.bar.fontFamily; font.pixelSize: 12; font.bold: true
          }
          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: !parent.modelData.off
            cursorShape: Qt.PointingHandCursor
            onEntered: dock.menuRow = parent.index
            onClicked: dock.runMenu(parent.modelData.act)
          }
        }
      }
    }
  }

  // ---- the add-apps panel: oozes out of the dock (the shader draws it
  // from geo.panelProgress; this is what sits on it) ----
  property bool panelOpen: false
  function togglePanel() { if (panelOpen) closePanel(); else openPanel() }
  function openPanel() {
    if (menuIndex >= 0) { menuIndex = -1; geo.panelProgress = 0 }
    blob = "panel"
    panelOpen = true
    query.text = ""
    appList.currentIndex = 0
    grow(1, 600)
    query.forceActiveFocus()
  }
  function closePanel() {
    if (!panelOpen) return
    panelOpen = false
    grow(0, 360)
  }
  NumberAnimation { id: panelAnim; target: dock.geo; property: "panelProgress" }
  // Settings / IPC ask for the panel: open it on the focused screen's dock
  Connections {
    target: dock.bar
    function onDockPanelRequestChanged() {
      var fm = Hyprland.focusedMonitor
      if (!dock.win.screen || !fm || fm.name === dock.win.screen.name) Qt.callLater(dock.openPanel)
    }
  }
  // a click anywhere else closes the panel / menu
  // switched on a moment after opening: turned on in the same instant the
  // window grows, Hyprland clears the grab straight away
  readonly property bool wantGrab: panelOpen || menuIndex >= 0
  property bool grabReady: false
  onWantGrabChanged: { grabReady = false; if (wantGrab) grabDelay.restart() }
  Timer { id: grabDelay; interval: 250; onTriggered: dock.grabReady = dock.wantGrab }
  HyprlandFocusGrab {
    active: dock.grabReady
    windows: [dock.win]
    onCleared: dock.closeAll()
  }

  readonly property var shownApps: {
    var q = query.text.trim().toLowerCase()
    if (!q) return allApps
    return allApps.filter(function(e) {
      return e.name.toLowerCase().indexOf(q) >= 0 || (e.genericName || "").toLowerCase().indexOf(q) >= 0
        || e.id.toLowerCase().indexOf(q) >= 0
    })
  }
  function toggleApp(e) {
    if (!e) return
    var it = { kind: "app", id: e.id }
    if (bar.dockHas(it)) bar.dockRemoveItem(it); else bar.dockAdd(it)
  }
  // the cc look for CcButton / CcHeading on the panel
  QtObject {
    id: look
    readonly property var bar: dock.bar
    readonly property color ink: dock.bar.slimeInk
    readonly property color slime: dock.bar.slimeColor
    readonly property color paper: dock.bar.paperColor
    readonly property string font: dock.bar.fontFamily
    readonly property string displayFont: dock.bar.displayFontFamily
    readonly property int displayWeight: dock.bar.displayWeight
    readonly property real fontScale: 1
    readonly property color wash: Qt.rgba(1, 1, 1, 0.45)
  }
  Item {
    id: panel
    readonly property rect r: dock.box(dock.geo.panelX + 14, dock.geo.panelX + dock.geo.panelW - 14,
                                       dock.geo.thick + 16, dock.geo.thick + dock.geo.panelH - 12)
    x: r.x; y: r.y; width: r.width; height: r.height
    visible: dock.blob === "panel" && dock.geo.panelProgress > 0.6
    opacity: Math.max(0, (dock.geo.panelProgress - 0.6) / 0.4)
    FocusScope {
      anchors.fill: parent
      focus: dock.panelOpen
      Column {
        anchors.fill: parent
        spacing: 8
        Row {
          width: parent.width
          spacing: 8
          CcHeading { cc: look; anchors.verticalCenter: parent.verticalCenter; text: "ADD TO THE DOCK" }
          Item { width: parent.width - 150 - closeBtn.width; height: 1 }
          CcButton { id: closeBtn; cc: look; icon: ""; text: "Esc"; fontSize: 10; onClicked: dock.closePanel() }
        }
        Rectangle {
          width: parent.width; height: 30; radius: 15
          color: Qt.rgba(1, 1, 1, 0.6)
          border.color: dock.bar.slimeInk; border.width: 1.5
          TextInput {
            id: query
            x: 12; width: parent.width - 24
            anchors.verticalCenter: parent.verticalCenter
            color: dock.bar.slimeInk
            font.family: dock.bar.fontFamily; font.pixelSize: 13
            clip: true
            Text {
              visible: !parent.text
              text: "search apps…  (↑↓ pick · Enter adds / removes)"
              color: dock.bar.slimeInk; opacity: 0.5
              font: parent.font
            }
            onTextChanged: appList.currentIndex = 0
            Keys.onPressed: event => {
              if (event.key === Qt.Key_Escape) dock.closePanel()
              else if (event.key === Qt.Key_Down) appList.currentIndex = Math.min(appList.count - 1, appList.currentIndex + 1)
              else if (event.key === Qt.Key_Up) appList.currentIndex = Math.max(0, appList.currentIndex - 1)
              else if (event.key === Qt.Key_PageDown) appList.currentIndex = Math.min(appList.count - 1, appList.currentIndex + 8)
              else if (event.key === Qt.Key_PageUp) appList.currentIndex = Math.max(0, appList.currentIndex - 8)
              else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) dock.toggleApp(dock.shownApps[appList.currentIndex])
              else return
              event.accepted = true
            }
          }
        }
        ListView {
          id: appList
          width: parent.width
          height: parent.height - 30 - 30 - 24 - 24
          clip: true
          spacing: 3
          model: dock.shownApps
          boundsBehavior: Flickable.StopAtBounds
          onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
          delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool here: ListView.isCurrentItem
            readonly property bool pinned: dock.bar.dockHas({ kind: "app", id: modelData.id })
            width: appList.width; height: 34; radius: 12
            color: here ? Qt.rgba(1, 1, 1, 0.75) : rowHover.hovered ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(1, 1, 1, 0.2)
            border.color: dock.bar.slimeInk; border.width: here ? 2 : 0
            HoverHandler { id: rowHover }
            Image {
              x: 8; anchors.verticalCenter: parent.verticalCenter
              width: 24; height: 24
              source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
              sourceSize.width: 48; sourceSize.height: 48
              asynchronous: true
            }
            Text {
              x: 40; anchors.verticalCenter: parent.verticalCenter
              width: parent.width - x - pinBtn.width - 16
              elide: Text.ElideRight
              text: row.modelData.name
              textFormat: Text.PlainText
              color: dock.bar.slimeInk
              font.family: dock.bar.fontFamily; font.pixelSize: 13; font.bold: row.pinned
            }
            CcButton {
              id: pinBtn
              cc: look
              anchors.right: parent.right; anchors.rightMargin: 6
              anchors.verticalCenter: parent.verticalCenter
              icon: row.pinned ? "" : ""
              text: row.pinned ? "on the dock (remove)" : "add"
              on: row.pinned
              fontSize: 10
              onClicked: { appList.currentIndex = row.index; dock.toggleApp(row.modelData) }
            }
            MouseArea {
              anchors.fill: parent; anchors.rightMargin: pinBtn.width + 10
              onClicked: { appList.currentIndex = row.index; query.forceActiveFocus() }
              onDoubleClicked: dock.toggleApp(row.modelData)
            }
          }
        }
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: "Drag folders or files onto the dock to pin them · right-click an icon to move or remove it"
          color: dock.bar.slimeInk; opacity: 0.7
          font.family: dock.bar.fontFamily; font.pixelSize: 11
        }
      }
    }
  }
}
