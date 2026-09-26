import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Slime Shell's centre widget: the clock and the weather in one label, and the
// source of the command centre. Left click drips the command centre open from
// this widget, right click shows the full weather panel, middle click opens the
// date & time settings (12/24h, date pattern, weight, size — ClockSettings.qml).
//
// Weather data still comes from the cloned Omarchy weather panel (Panel.qml),
// which stays loaded but hidden so its fetching, caching and settings work
// exactly as they do on the default bar.
BarWidget {
  id: root
  moduleName: "omarchy.weather"

  // Clock settings, stored in this widget's shell.json entry.
  readonly property bool hour24: setting("hour24", true)
  readonly property string datePattern: setting("datePattern", "ddd d MMM")
  readonly property int fontSize: setting("fontSize", 15)
  readonly property int fontWeight: setting("fontWeight", Font.Black)
  readonly property string timeText: {
    var time = Qt.formatTime(clock.date, hour24 ? "HH:mm" : "h:mm AP")
    if (datePattern === "") return time
    var date = Qt.formatDate(clock.date, datePattern)
    return root.bar && root.bar.clockTimeFirst ? time + "  " + date : date + "  " + time
  }

  function saveSetting(key, value) {
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    entry[key] = value
    // Applied locally first so the clock changes on the click; the shell.json
    // write comes back through the bar as the same value.
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function toggleHour24() { saveSetting("hour24", !hour24) }

  property bool settingsOpen: false
  IpcHandler {
    target: "slime-clock"
    function settings(): void { root.settingsOpen = !root.settingsOpen }
  }
  // Popout identity for the settings panel, so the bar's one-dropdown-at-a-time
  // coordination can close it like any other panel.
  QtObject {
    id: settingsOwner
    function close() { root.settingsOpen = false }
  }
  readonly property string weatherText: panelLoader.item ? panelLoader.item.label : ""
  // The hidden weather panel, for the command centre's weather card.
  readonly property var weatherPanel: panelLoader.item

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function toggleWeatherPanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  function toggleCommandCenter() {
    if (root.bar && typeof root.bar.toggleCommandCenter === "function") root.bar.toggleCommandCenter()
    else toggleWeatherPanel()
  }

  // Shape contract for shell.summon/hide/toggle routing (Bar.findPanelWidget
  // requires open/close/opened on the bar-widget root). These drive the
  // weather panel, so `omarchy-shell shell toggle omarchy.weather` still works.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  readonly property real openPanelIndicatorWidth: label.implicitWidth

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // The label is drawn below so it can take a heavier weight and the
    // user's size; the button keeps the click, hover and tooltip wiring.
    text: ""
    hasVisualContent: true
    fixedWidth: Math.ceil(label.implicitWidth) + Style.space(18)

    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleWeatherPanel()
      else if (b === Qt.MiddleButton) root.settingsOpen = !root.settingsOpen
      else root.toggleCommandCenter()
    }

    Text {
      id: label
      anchors.centerIn: parent
      text: root.weatherText !== "" ? root.weatherText + "   " + root.timeText : root.timeText
      color: button.foreground
      font.family: button.fontFamily
      font.pixelSize: root.fontSize
      font.weight: root.fontWeight
    }
  }

  ClockSettings {
    anchorItem: button
    bar: root.bar
    owner: settingsOwner
    widget: root
    open: root.settingsOpen
  }
}
