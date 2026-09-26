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
  // What the clock shows of the weather: "icon", "temp" or "both" (setting)
  readonly property string weatherShow: setting("weatherShow", "icon")
  readonly property string weatherIcon: panelLoader.item ? panelLoader.item.label : ""
  readonly property string weatherTemp: panelLoader.item && panelLoader.item.reportTempNum !== ""
    ? panelLoader.item.reportTempNum + "°" : ""
  readonly property string weatherText: weatherShow === "temp" ? (weatherTemp || weatherIcon)
    : weatherShow === "both" ? [weatherIcon, weatherTemp].filter(function(x) { return x !== "" }).join(" ")
    : weatherIcon
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
    // side bars stack everything: weather, hours over minutes, then the date
    // (date first when the clock order says so)
    fixedWidth: root.vertical ? -1 : Math.ceil(label.implicitWidth) + Style.space(18)
    fixedHeight: root.vertical ? Math.ceil(stack.implicitHeight) + 14 : -1

    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleWeatherPanel()
      else if (b === Qt.MiddleButton) root.settingsOpen = !root.settingsOpen
      else root.toggleCommandCenter()
    }

    Text {
      id: label
      visible: !root.vertical
      anchors.centerIn: parent
      text: root.weatherText !== "" ? root.weatherText + "   " + root.timeText : root.timeText
      color: button.foreground
      // the slime display face when one is picked (Settings > Font & clock)
      font.family: root.bar && root.bar.displayFontFamily ? root.bar.displayFontFamily : button.fontFamily
      font.pixelSize: root.fontSize
      font.weight: root.bar && root.bar.slimeFonts ? root.bar.displayWeight : root.fontWeight
    }

    Column {
      id: stack
      visible: root.vertical
      anchors.centerIn: parent
      spacing: 3
      readonly property bool dateFirst: !!root.bar && !root.bar.clockTimeFirst && root.datePattern !== ""
      readonly property string family: root.bar && root.bar.displayFontFamily ? root.bar.displayFontFamily : button.fontFamily
      readonly property int weight: root.bar && root.bar.slimeFonts ? root.bar.displayWeight : root.fontWeight

      component Small: Text {
        anchors.horizontalCenter: parent.horizontalCenter
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: 11
        font.bold: true
      }

      Small {
        visible: root.weatherText !== ""
        text: root.weatherText.replace(" ", "\n")
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: 13
      }
      Small { visible: stack.dateFirst; text: Qt.formatDate(clock.date, "ddd") }
      Small { visible: stack.dateFirst; text: Qt.formatDate(clock.date, "d MMM") }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatTime(clock.date, root.hour24 ? "HH" : "h") + "\n" + Qt.formatTime(clock.date, "mm")
        horizontalAlignment: Text.AlignHCenter
        lineHeight: 0.85
        color: button.foreground
        font.family: stack.family
        font.pixelSize: Math.min(root.fontSize, 20)
        font.weight: stack.weight
      }
      Small { visible: !root.hour24; text: Qt.formatTime(clock.date, "AP") }
      Small { visible: !stack.dateFirst && root.datePattern !== ""; text: Qt.formatDate(clock.date, "ddd") }
      Small { visible: !stack.dateFirst && root.datePattern !== ""; text: Qt.formatDate(clock.date, "d MMM") }
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
