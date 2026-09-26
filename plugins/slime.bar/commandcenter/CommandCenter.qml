import QtQuick

// The Slime command centre: a tab strip over the active tab's content, drawn
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

  readonly property color ink: bar.slimeInk
  readonly property color slime: bar.slimeColor
  readonly property color paper: bar.paperColor
  readonly property string font: bar.fontFamily
  readonly property color wash: Qt.rgba(1, 1, 1, 0.45)

  readonly property var tabs: [
    ["home", "", "Home", "HomeTab.qml"],
    ["system", "", "System", "SystemTab.qml"],
    ["wallpapers", "", "Wallpapers", "WallpapersTab.qml"],
    ["tasks", "", "Tasks", "TasksTab.qml"],
    ["settings", "", "Settings", "SettingsTab.qml"]
  ]
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

  implicitHeight: tabRow.height + 16 + (loader.item ? loader.item.implicitHeight : 0)

  Row {
    id: tabRow
    spacing: 6
    Repeater {
      model: center.tabs
      CcButton {
        required property var modelData
        cc: center
        icon: modelData[1]
        text: modelData[2]
        on: center.bar.ccTab === modelData[0]
        onClicked: center.bar.ccTab = modelData[0]
      }
    }
  }

  Loader {
    id: loader
    y: tabRow.height + 16
    width: parent.width
    active: center.shown
    source: center.tabSource
    onLoaded: {
      item.cc = center
      item.width = Qt.binding(function() { return loader.width })
    }
  }
}
