import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../slime.bar/ui"

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
  // the date: a Qt pattern, or "@initial" for the day's initial and the
  // date, "M-28" (ST / SN for Saturday / Sunday)
  function dateText(d) {
    if (datePattern === "@initial") {
      var dow = d.getDay()
      return (["SN", "M", "T", "W", "T", "F", "ST"][dow]) + "-" + d.getDate()
    }
    return Qt.formatDate(d, datePattern)
  }
  readonly property string clockTime: Qt.formatTime(clock.date, hour24 ? "HH:mm" : "h:mm AP")
  readonly property string clockDate: datePattern === "" ? "" : dateText(clock.date)
  readonly property string timeText: clockDate === "" ? clockTime
    : root.bar && root.bar.clockTimeFirst ? clockTime + " " + clockDate : clockDate + " " + clockTime
  // extras: a bubble round the weather, goblins hanging off the time
  readonly property bool weatherBubble: setting("weatherBubble", false) === true
  readonly property bool goblins: setting("goblins", false) === true
  readonly property bool slime: !!bar && bar.slimeSkin === true

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
    // bubble | goblins on|off, weather icon|temp|both, date <pattern or @initial>
    function option(name: string, value: string): void {
      if (name === "bubble") root.saveSetting("weatherBubble", value === "on")
      else if (name === "goblins") root.saveSetting("goblins", value === "on")
      else if (name === "weather") root.saveSetting("weatherShow", value)
      else if (name === "date") root.saveSetting("datePattern", value)
    }
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

  readonly property real openPanelIndicatorWidth: line.implicitWidth

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
    fixedWidth: root.vertical ? -1 : Math.ceil(line.implicitWidth) + Style.space(18)
    fixedHeight: root.vertical ? Math.ceil(stack.implicitHeight) + 14 : -1

    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleWeatherPanel()
      else if (b === Qt.MiddleButton) root.settingsOpen = !root.settingsOpen
      else root.toggleCommandCenter()
    }

    // weather · date · time, in pieces (close together)
    Row {
      id: line
      visible: !root.vertical
      anchors.centerIn: parent
      spacing: Math.round(root.fontSize * 0.45)
      readonly property string family: root.bar && root.bar.displayFontFamily ? root.bar.displayFontFamily : button.fontFamily
      readonly property int weight: root.bar && root.bar.slimeFonts ? root.bar.displayWeight : root.fontWeight
      readonly property real t: root.bar ? root.bar.animTime : 0

      component Piece: Text {
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        color: button.foreground
        // the slime display face when one is picked (Settings > Font & clock)
        font.family: line.family
        font.pixelSize: root.fontSize
        font.weight: line.weight
      }

      // the weather: icon, temperature, or the temperature with the icon
      // floating big and faint behind it in the goo
      Item {
        id: weatherBit
        visible: root.weatherText !== ""
        anchors.verticalCenter: parent.verticalCenter
        readonly property bool behind: root.weatherShow === "both" && root.weatherTemp !== ""
        width: shown.implicitWidth + (root.weatherBubble ? root.fontSize * 0.8 : 0)
        height: Math.max(shown.implicitHeight, root.fontSize * 1.3)
        // a glossy bubble round it
        Rectangle {
          visible: root.weatherBubble
          anchors.centerIn: parent
          width: parent.width + 4; height: Math.max(parent.height, width * 0.62)
          radius: height / 2
          color: Qt.rgba(1, 1, 1, 0.18)
          border.color: Qt.rgba(1, 1, 1, 0.8); border.width: 1.2
          Rectangle { x: parent.height * 0.3; y: 3; width: parent.width * 0.3; height: 3; radius: 1.5; color: Qt.rgba(1, 1, 1, 0.85) }
          Rectangle { anchors.fill: parent; anchors.margins: -1.2; radius: height / 2; color: "transparent"; border.color: button.foreground; border.width: 0.8; opacity: 0.45 }
        }
        Piece {
          visible: weatherBit.behind
          anchors.centerIn: parent
          anchors.verticalCenterOffset: Math.sin(line.t * 1.2) * 1.5
          text: root.weatherIcon
          font.family: button.fontFamily
          font.pixelSize: root.fontSize * 1.9
          opacity: 0.3
          rotation: Math.sin(line.t * 0.7) * 8
        }
        Piece {
          id: shown
          anchors.centerIn: parent
          text: weatherBit.behind ? root.weatherTemp : root.weatherText
        }
      }
      Piece { visible: root.clockDate !== "" && !(root.bar && root.bar.clockTimeFirst); text: root.clockDate }
      Piece {
        id: timePiece
        text: root.clockTime
        // goblins hanging off the numbers, trying to make off with them
        Repeater {
          model: root.goblins && root.slime ? 3 : 0
          Item {
            required property int index
            readonly property real sway: Math.sin(line.t * (1.6 + index * 0.4) + index * 2.1)
            x: timePiece.width * (0.14 + index * 0.33)
            y: timePiece.height * 0.5
            width: 20; height: 24
            rotation: sway * 14
            transformOrigin: Item.Top
            SlimeCaptive {
              y: 1
              size: Math.round(root.fontSize * 0.8)
              kind: "goblin"
              time: line.t + index * 3
              ink: root.bar ? root.bar.slimeInk : "black"
              paper: root.bar ? root.bar.paperColor : "white"
              goo: root.bar ? root.bar.slimeColor : "green"
              pal: root.bar && root.bar.palette ? root.bar.palette : ({})
            }
          }
        }
      }
      Piece { visible: root.clockDate !== "" && !!(root.bar && root.bar.clockTimeFirst); text: root.clockDate }
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
      Small { visible: stack.dateFirst; text: root.datePattern === "@initial" ? root.clockDate : Qt.formatDate(clock.date, "ddd") }
      Small { visible: stack.dateFirst && root.datePattern !== "@initial"; text: Qt.formatDate(clock.date, "d MMM") }
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
      Small { visible: !stack.dateFirst && root.datePattern !== ""; text: root.datePattern === "@initial" ? root.clockDate : Qt.formatDate(clock.date, "ddd") }
      Small { visible: !stack.dateFirst && root.datePattern !== "" && root.datePattern !== "@initial"; text: Qt.formatDate(clock.date, "d MMM") }
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
