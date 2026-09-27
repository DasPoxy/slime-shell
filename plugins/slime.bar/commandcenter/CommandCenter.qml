import QtQuick
import QtQuick.Shapes

// The Slime command centre: a column of tabs down the left (floating items,
// like the bar's widgets) beside the active tab's content, drawn
// on the ooze that drips out of the clock-weather widget. Tabs are loaded on
// demand (only the visible one polls anything) and share this item as `cc`
// for the theme ink, colours and font.
//
//   home        toggles, audio, media, calendar, notifications
//   system      CPU / memory / GPU / disks / top processes
//   wallpapers  the current theme's backgrounds
//   tasks       Envy note checkboxes
//   settings    slime skin, clock and launcher options
Item {
  id: center

  required property var bar
  property bool shown: false
  // Tallest the command centre may be on this screen; taller tab content
  // scrolls inside it (smaller screens, or every settings section open).
  property real maxHeight: 100000

  readonly property color ink: bar.slimeInk
  readonly property color slime: bar.slimeColor
  readonly property color paper: bar.paperColor
  readonly property string font: bar.fontFamily
  // decorative slime face for big text only (clocks, temperatures, headings)
  readonly property string displayFont: bar.displayFontFamily
  readonly property int displayWeight: bar.displayWeight
  // text size for the command centre and its tabs (the bar's clock keeps its own)
  readonly property real fontScale: bar.ccFontScale
  readonly property real fs: fontScale
  readonly property color wash: Qt.rgba(1, 1, 1, 0.45)

  // [id, gear kind, label, file]
  readonly property var tabs: [
    ["home", "cottage", "Home", "HomeTab.qml"],
    ["system", "shield", "System", "SystemTab.qml"],
    ["wallpapers", "painting", "Wallpapers", "WallpapersTab.qml"],
    ["tasks", "scroll", "Tasks", "TasksTab.qml"],
    ["startup", "potion", "Start-Up", "StartupTab.qml"],
    ["settings", "anvil", "Settings", "SettingsTab.qml"]
  ]
  // the tab sidebar folds down to just its icons (button at its top-right
  // corner, or t), handing the room to the tab; remembered
  readonly property bool sidebarCollapsed: bar.ccSidebarCollapsed === true
  property real sidebarWidth: sidebarCollapsed ? 50 : Math.round(128 + Math.max(0, fontScale - 1) * 150)   // wider for bigger text
  Behavior on sidebarWidth { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
  function toggleSidebar() { bar.ccSidebarCollapsed = !sidebarCollapsed }
  readonly property string tabSource: {
    for (var i = 0; i < tabs.length; i++) if (tabs[i][0] === bar.ccTab) return tabs[i][3]
    return tabs[0][3]
  }

  // The widget on the bar that owns something the command centre links to.
  function widget(moduleName) {
    var slots = bar.moduleSlots
    for (var i = 0; i < slots.length; i++)
      if (slots[i] && slots[i].moduleName === moduleName && slots[i].activeItem) return slots[i].activeItem
    return null
  }

  function formatBytes(bytes) {
    var units = ["B", "KB", "MB", "GB", "TB"]
    var i = 0
    while (bytes >= 1024 && i < units.length - 1) { bytes /= 1024; i++ }
    return (i >= 3 ? bytes.toFixed(1) : Math.round(bytes)) + " " + units[i]
  }

  // ---- keyboard: arrows move a highlight between controls (the nearest one
  // in that direction), Enter / Space press it, ← / → nudge a slider,
  // Ctrl+Tab · Alt+1…6 (and 1…6) switch tabs, ? shows the keys, Esc steps
  // back and then closes. The Tasks tab keeps its own keys. Off with
  // Settings → Command centre → Keyboard navigation.
  readonly property bool kbEnabled: bar.ccKeyboard !== false
  property Item kbItem: null
  property bool kbHelp: false
  property rect kbRect: Qt.rect(0, 0, 0, 0)
  focus: true
  function kbTabs() { return tabs.map(function(t) { return t[0] }) }
  function switchTab(i) {
    var t = kbTabs()
    bar.ccTab = t[(i + t.length) % t.length]
  }
  function walk(it, out) {
    if (!it || !it.visible || it.opacity <= 0.01) return
    if (it.ccFocusable === true && it.enabled !== false && it.width > 1 && it.height > 1) out.push(it)
    var ch = it.children
    for (var i = 0; i < ch.length; i++) walk(ch[i], out)
  }
  function focusables() { var out = []; walk(tabColumn, out); walk(scroller, out); return out }
  function rectOf(it) { var p = it.mapToItem(center, 0, 0); return Qt.rect(p.x, p.y, it.width, it.height) }
  function kbMove(dx, dy) {
    var all = focusables()
    if (!all.length) return
    if (!kbItem || all.indexOf(kbItem) < 0) {
      // first press: the top-left control in the tab's content
      var best = null, bs = 1e9
      all.forEach(function(it) {
        var r = rectOf(it)
        if (r.x < sidebarWidth) return
        var sc = r.y * 2 + r.x
        if (sc < bs) { bs = sc; best = it }
      })
      kbItem = best || all[0]
    } else {
      var c = rectOf(kbItem), cx = c.x + c.width / 2, cy = c.y + c.height / 2
      var pick = null, ps = 1e9
      all.forEach(function(it) {
        if (it === kbItem) return
        var r = rectOf(it), vx = r.x + r.width / 2 - cx, vy = r.y + r.height / 2 - cy
        var along = vx * dx + vy * dy, cross = Math.abs(vx * dy - vy * dx)
        if (along <= 4) return
        var sc = along + cross * 2.5
        if (sc < ps) { ps = sc; pick = it }
      })
      if (pick) kbItem = pick
    }
    kbSync()
    kbReveal()
  }
  function kbSync() { if (kbItem) kbRect = rectOf(kbItem) }
  // scroll the tab so the highlighted control is in view
  function kbReveal() {
    if (!kbItem || !scroller.interactive) return
    var p = kbItem.mapToItem(scroller.contentItem, 0, 0)
    if (p.x < 0) return                                    // (the sidebar)
    if (p.y < scroller.contentY) scroller.contentY = Math.max(0, p.y - 12)
    else if (p.y + kbItem.height > scroller.contentY + scroller.height)
      scroller.contentY = Math.min(scroller.contentHeight - scroller.height, p.y + kbItem.height - scroller.height + 12)
    kbSync()
  }
  Connections {
    target: center.bar
    function onAnimTimeChanged() { if (center.kbItem) center.kbSync() }       // controls bob
    function onCcTabChanged() { center.kbItem = null; center.kbHelp = false; center.kbTakeFocus() }
  }
  function kbTakeFocus() { if (shown && bar.ccTab !== "tasks") Qt.callLater(function() { center.forceActiveFocus() }) }
  onShownChanged: { kbItem = null; kbHelp = false; kbTakeFocus() }
  // hover keys on the media slime borrow the keyboard; take it back after
  Timer {
    interval: 600; repeat: true
    running: center.shown && center.bar.ccTab !== "tasks"
    onTriggered: if (!center.Window.activeFocusItem) center.forceActiveFocus()
  }
  Keys.onPressed: event => {
    var k = event.key, txt = event.text
    var ctrl = event.modifiers & Qt.ControlModifier, alt = event.modifiers & Qt.AltModifier
    var cur = kbTabs().indexOf(bar.ccTab)
    // tab switching works everywhere, the Tasks tab included
    if (ctrl && (k === Qt.Key_Tab || k === Qt.Key_Backtab)) { switchTab(cur + (k === Qt.Key_Backtab ? -1 : 1)); event.accepted = true; return }
    if (alt && k >= Qt.Key_1 && k < Qt.Key_1 + tabs.length) { switchTab(k - Qt.Key_1); event.accepted = true; return }
    // t folds the sidebar, from any tab (Tasks passes t through)
    if (txt === "t" && !ctrl && !alt) { toggleSidebar(); event.accepted = true; return }
    if (bar.ccTab === "tasks") return                     // its own keys (Esc closes there)
    if (k === Qt.Key_Escape) {
      if (kbHelp) kbHelp = false
      else if (kbItem) kbItem = null
      else bar.commandCenterOpen = false
      event.accepted = true; return
    }
    if (!kbEnabled) return
    var slider = kbItem && typeof kbItem.ccAdjust === "function"
    if (txt === "?") kbHelp = !kbHelp
    else if (k >= Qt.Key_1 && k < Qt.Key_1 + tabs.length && !ctrl) switchTab(k - Qt.Key_1)
    else if (slider && (k === Qt.Key_Left || txt === "h")) kbItem.ccAdjust(-1)
    else if (slider && (k === Qt.Key_Right || txt === "l")) kbItem.ccAdjust(1)
    else if (k === Qt.Key_Left || txt === "h") kbMove(-1, 0)
    else if (k === Qt.Key_Right || txt === "l") kbMove(1, 0)
    else if (k === Qt.Key_Up || txt === "k") kbMove(0, -1)
    else if (k === Qt.Key_Down || txt === "j") kbMove(0, 1)
    else if ((k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) && kbItem) { kbItem.ccActivate(); kbSync() }
    else return
    event.accepted = true
  }

  readonly property real contentHeight: loader.item ? loader.item.implicitHeight : 0
  implicitHeight: Math.min(maxHeight, Math.max(tabColumn.implicitHeight, contentHeight))

  Column {
    id: tabColumn
    width: center.sidebarWidth
    spacing: 14
    topPadding: 4
    Repeater {
      model: center.tabs
      CcGearButton {
        required property var modelData
        required property int index
        cc: center
        kind: modelData[1]
        label: modelData[2]
        size: 30
        labelSide: center.sidebarCollapsed ? "none" : "right"
        phase: index * 1.3
        active: center.bar.ccTab === modelData[0]
        lit: active
        onClicked: center.bar.ccTab = modelData[0]
      }
    }
  }

  // fold / unfold the sidebar: a little round button at its top-right corner
  // …drawn as a bubble trapped in the goo, with the arrow floating inside
  Item {
    id: sidebarToggle
    readonly property real t: center.bar ? center.bar.animTime : 0
    x: center.sidebarWidth - width - 5
    y: (center.sidebarCollapsed ? tabColumn.implicitHeight + 6 : 1) + Math.sin(t * 1.4) * 1.2
    width: 26; height: 26
    scale: toggleHover.hovered ? 1.12 : 1
    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
    Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    // the bubble wobbles very slightly, like it's squeezed by the ooze
    transform: Scale {
      origin.x: 13; origin.y: 13
      xScale: 1 + Math.sin(sidebarToggle.t * 2.3) * 0.035
      yScale: 1 - Math.sin(sidebarToggle.t * 2.3) * 0.035
    }
    // soft shadow the bubble casts into the slime below it
    Rectangle {
      x: 3; y: 5; width: parent.width - 4; height: parent.height - 4; radius: width / 2
      color: Qt.rgba(center.ink.r, center.ink.g, center.ink.b, 0.22)
    }
    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      // body: nearly clear in the middle, the slime's colour thickening to the
      // rim (light passing through more film at the edges)
      ShapePath {
        strokeColor: Qt.rgba(center.ink.r, center.ink.g, center.ink.b, 0.55)
        strokeWidth: 1.2
        fillGradient: RadialGradient {
          centerX: 11; centerY: 11; centerRadius: 15; focalX: 10; focalY: 10
          GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.28) }
          GradientStop { position: 0.55; color: Qt.rgba(center.slime.r, center.slime.g, center.slime.b, 0.25) }
          GradientStop { position: 0.85; color: Qt.rgba(center.slime.r * 0.7, center.slime.g * 0.7, center.slime.b * 0.8, 0.55) }
          GradientStop { position: 1.0; color: Qt.rgba(center.ink.r, center.ink.g, center.ink.b, 0.45) }
        }
        PathSvg { path: "M 13 1 A 12 12 0 1 1 12.99 1 Z" }
      }
      // bright film just inside the rim
      ShapePath {
        fillColor: "transparent"
        strokeColor: Qt.rgba(1, 1, 1, 0.55)
        strokeWidth: 0.9
        PathSvg { path: "M 13 2.4 A 10.6 10.6 0 1 1 12.99 2.4 Z" }
      }
      // reflected light pooling in the bottom-right of the bubble
      ShapePath {
        fillColor: "transparent"
        strokeColor: Qt.rgba(1, 1, 1, 0.45)
        strokeWidth: 1.6
        capStyle: ShapePath.RoundCap
        PathSvg { path: "M 20.5 17.5 A 9 9 0 0 1 14 22" }
      }
    }
    // the arrow, floating inside (it swings round as the sidebar flips)
    Shape {
      anchors.centerIn: parent
      width: 12; height: 12
      rotation: center.sidebarCollapsed ? 180 : 0
      Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        fillColor: "transparent"
        strokeColor: center.ink
        strokeWidth: 2
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: "M 10.5 6 L 1.5 6 M 5.5 1.5 L 1.2 6 L 5.5 10.5" }
      }
    }
    // glossy highlight over the top-left, and a sparkle — over the arrow, so
    // it reads as behind the bubble's skin
    Rectangle {
      x: 5; y: 6.5; width: 9; height: 3.6; radius: 1.8
      rotation: -38
      color: Qt.rgba(1, 1, 1, 0.78)
    }
    Rectangle { x: 16.2; y: 5.2; width: 2.6; height: 2.6; radius: 1.3; color: Qt.rgba(1, 1, 1, 0.9) }
    HoverHandler { id: toggleHover }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: center.toggleSidebar() }
    CcFocus { onActivate: center.toggleSidebar() }
  }

  // a faint divider between the tabs and the content
  Rectangle {
    x: center.sidebarWidth
    width: 3
    height: parent.height
    radius: 1.5
    color: Qt.rgba(center.ink.r, center.ink.g, center.ink.b, 0.18)
  }

  Flickable {
    id: scroller
    x: center.sidebarWidth + 20
    width: parent.width - x
    height: center.height
    contentWidth: width
    contentHeight: center.contentHeight
    interactive: contentHeight > height + 1
    boundsBehavior: Flickable.StopAtBounds
    clip: interactive
    // a new tab starts at the top
    Connections { target: center.bar; function onCcTabChanged() { scroller.contentY = 0 } }

    Loader {
      id: loader
      width: scroller.width - (scroller.interactive ? 10 : 0)
      active: center.shown
      source: center.tabSource
      onLoaded: {
        item.cc = center
        item.width = Qt.binding(function() { return loader.width })
      }
    }
  }
  // the keyboard's highlight ring
  Rectangle {
    z: 100
    visible: center.kbItem !== null && center.kbItem.visible && center.bar.ccTab !== "tasks"
    x: center.kbRect.x - 4; y: center.kbRect.y - 4
    width: center.kbRect.width + 8; height: center.kbRect.height + 8
    radius: Math.min(height / 2, 14)
    color: Qt.rgba(1, 1, 1, 0.14)
    border.color: center.ink
    border.width: 2.5
    Rectangle {
      anchors.fill: parent; anchors.margins: -3
      radius: parent.radius + 3
      color: "transparent"
      border.color: Qt.rgba(1, 1, 1, 0.7)
      border.width: 1.5
    }
  }
  // the keys, on ?
  Rectangle {
    z: 101
    visible: center.kbHelp
    anchors.centerIn: parent
    width: 460
    height: kbHelpText.implicitHeight + 28
    radius: 16
    color: center.paper
    border.color: center.ink
    border.width: 2
    Text {
      id: kbHelpText
      x: 16; y: 14
      width: parent.width - 32
      textFormat: Text.PlainText
      text: "Arrows / h j k l   move between controls\n"
          + "Enter / Space       press the highlighted control\n"
          + "← / → on a slider   turn it down / up\n"
          + "1 … 6, Alt+1 … 6    go to a tab\n"
          + "Ctrl+Tab            next tab (Shift: previous)\n"
          + "Esc                 clear the highlight, then close\n"
          + "t                   fold / unfold the tab sidebar\n"
          + "?                   these keys\n\n"
          + "The Tasks tab has its own keys (? there)."
      color: center.ink
      font.family: "monospace"
      font.pixelSize: Math.round(12 * center.fs) }
  }

  // scroll indicator, only when the tab doesn't fit
  Rectangle {
    visible: scroller.interactive
    x: parent.width - 4
    width: 4
    radius: 2
    readonly property real frac: scroller.height / Math.max(1, scroller.contentHeight)
    height: Math.max(24, scroller.height * frac)
    y: (scroller.height - height) * (scroller.contentY / Math.max(1, scroller.contentHeight - scroller.height))
    color: Qt.rgba(center.ink.r, center.ink.g, center.ink.b, 0.45)
  }
}
