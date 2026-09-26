import QtQuick

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
  readonly property real sidebarWidth: 128
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
        phase: index * 1.3
        active: center.bar.ccTab === modelData[0]
        lit: active
        onClicked: center.bar.ccTab = modelData[0]
      }
    }
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
