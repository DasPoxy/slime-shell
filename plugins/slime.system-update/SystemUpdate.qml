import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../slime.bar/ui"
import "../slime.bar/commandcenter"
import "../slime.bar/ui/WidgetSettings.js" as WidgetSettings

// SlimeS-System Update: a little character in the bar that tells you when
// Omarchy has updates. It stays put while there's nothing new, and acts up
// when there is: the town crier rings his bell and yells, the bard strums,
// the knight kneels, the jester juggles, the candle lights, the slime
// emotes. Optionally trapped in a bubble in the slime.
// Left-click: a drip panel with what's pending, "update now" and "check
// again". Right-click: a drip menu to pick the character and the bubble.
// Settings (shell.json): character (crier), bubble (true)
BarWidget {
  id: root
  moduleName: "omarchy.system-update"

  readonly property string entryId: "slime.system-update"
  readonly property bool slime: !!bar && bar.slimeSkin === true
  readonly property var characters: [["crier", "town crier"], ["bard", "bard"], ["knight", "knight"],
                                     ["jester", "jester"], ["candle", "candle"], ["emoteslime", "slime"]]
  readonly property string character: characters.some(function(c) { return c[0] === setting("character", "crier") }) ? setting("character", "crier") : "crier"
  readonly property bool bubble: setting("bubble", true) === true
  // only on the bar while there are updates (menus open from Settings → Widgets)
  readonly property bool onlyWithUpdates: setting("onlyWithUpdates", false) === true
  readonly property bool shown: updateAvailable || !onlyWithUpdates
  function setOnlyWithUpdates(on) { saveSetting("onlyWithUpdates", on) }

  property bool updateAvailable: false
  property var pending: []                // what omarchy-update-available listed
  property string checkedAt: ""
  property bool checking: false
  property bool infoOpen: false
  property bool menuOpen: false
  function close() { infoOpen = false; menuOpen = false }
  onInfoOpenChanged: if (infoOpen) { menuOpen = false; refresh() }
  onMenuOpenChanged: if (menuOpen) infoOpen = false

  function refresh() {
    if (updateProc.running) return
    checking = true
    updateProc.running = true
  }
  function clear() { updateAvailable = false; pending = [] }
  function runUpdate() {
    close()
    if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation omarchy-update")
  }
  function saveSetting(key, value) { WidgetSettings.save(root, WidgetSettings.one(key, value), root.entryId) }

  visible: shown
  implicitWidth: !shown ? 0 : vertical ? barSize : 30
  implicitHeight: !shown ? 0 : vertical ? 30 : barSize

  IpcHandler {
    target: "omarchy.system-update"
    function refresh(): void { root.broadcast("refresh") }
    function clear(): void { root.broadcast("clear") }
    function toggle(): void { root.infoOpen = !root.infoOpen }
    function menu(): void { root.menuOpen = !root.menuOpen }
  }

  Process {
    id: updateProc
    command: ["omarchy-update-available"]
    stdout: StdioCollector {
      onStreamFinished: root.pending = text.split("\n").filter(function(l) { return l.trim() !== "" && l.indexOf("up to date") < 0 })
    }
    onExited: function(exitCode) {
      root.updateAvailable = exitCode === 0
      root.checking = false
      root.checkedAt = Qt.formatTime(new Date(), "h:mm AP")
    }
  }

  Timer {
    interval: 21600000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // ---- the character (in its bubble) ----
  Item {
    id: face
    anchors.centerIn: parent
    width: 26; height: 26
    readonly property real t: root.bar ? root.bar.animTime : 0
    transform: Translate { y: Math.sin(face.t * 1.3 + 2) * 1.2 }
    // trapped in a bubble: glossy, with a rim and a shine
    Rectangle {
      visible: root.bubble
      anchors.centerIn: parent
      width: 29; height: 29; radius: 14.5
      color: Qt.rgba(1, 1, 1, 0.16)
      border.color: Qt.rgba(1, 1, 1, 0.75)
      border.width: 1.2
      Rectangle { x: 5; y: 4; width: 8; height: 4; radius: 2; rotation: -30; color: Qt.rgba(1, 1, 1, 0.8) }
      Rectangle { anchors.fill: parent; anchors.margins: -1.2; radius: width / 2; color: "transparent"; border.color: root.bar ? root.bar.slimeInk : "black"; border.width: 0.8; opacity: 0.5 }
    }
    SlimeGear {
      anchors.centerIn: parent
      width: root.bubble ? 22 : 26; height: width; size: width
      bar: root.bar
      kind: root.character
      lit: root.updateAvailable
    }
    MouseArea {
      anchors.fill: parent
      anchors.margins: -2
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      hoverEnabled: true
      onClicked: mouse => {
        if (!root.slime) { if (root.updateAvailable) root.runUpdate(); return }
        if (mouse.button === Qt.RightButton) root.menuOpen = !root.menuOpen
        else root.infoOpen = !root.infoOpen
      }
      onContainsMouseChanged: {
        if (!root.bar || root.slime) return
        if (containsMouse) root.bar.showTooltip(root, root.updateAvailable ? "Pending Omarchy updates" : "Omarchy is up to date")
        else root.bar.hideTooltip(root)
      }
    }
  }

  SlimeLook { id: look; bar: root.bar }

  // ---- left-click: what's new ----
  SlimePopupCard {
    id: infoCard
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.infoOpen
    contentWidth: Style.space(320)
    contentHeight: infoCard.fittedContentHeight(infoCol.implicitHeight)
    Column {
      id: infoCol
      anchors.fill: parent
      spacing: 10
      bottomPadding: 4
      Row {
        spacing: 10
        width: parent.width
        SlimeGear {
          width: 40; height: 40; size: 40
          bar: root.bar
          kind: root.character
          lit: root.updateAvailable
        }
        Column {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - 50
          Text {
            width: parent.width; wrapMode: Text.Wrap
            text: root.checking ? "Checking…" : root.updateAvailable ? "Updates are ready!" : "Omarchy is up to date"
            color: look.ink; font.family: look.displayFont; font.weight: look.displayWeight; font.pixelSize: 16
          }
          Text {
            visible: root.checkedAt !== ""
            text: "checked at " + root.checkedAt
            color: look.ink; opacity: 0.6; font.family: look.font; font.pixelSize: 10
          }
        }
      }
      Repeater {
        model: root.pending
        Text {
          required property string modelData
          width: infoCol.width
          wrapMode: Text.Wrap
          text: "• " + modelData
          color: look.ink; font.family: look.font; font.pixelSize: 12
        }
      }
      Flow {
        width: parent.width
        spacing: 6
        CcButton { cc: look; visible: root.updateAvailable; on: true; icon: ""; text: "Update now"; onClicked: root.runUpdate() }
        CcButton { cc: look; icon: ""; text: root.checking ? "Checking…" : "Check again"; onClicked: root.refresh() }
      }
    }
  }

  // ---- right-click: who tells you ----
  SlimePopupCard {
    id: menuCard
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.menuOpen
    contentWidth: Style.space(260)
    contentHeight: menuCard.fittedContentHeight(menuCol.implicitHeight)
    Column {
      id: menuCol
      anchors.fill: parent
      spacing: 8
      bottomPadding: 4
      CcHeading { cc: look; text: "WHO BRINGS THE NEWS" }
      Flow {
        width: parent.width
        spacing: 6
        Repeater {
          model: root.characters
          CcButton {
            required property var modelData
            cc: look
            text: modelData[1]
            on: root.character === modelData[0]
            onClicked: root.saveSetting("character", modelData[0])
          }
        }
      }
      CcHeading { cc: look; text: "TRAPPED IN A BUBBLE" }
      Flow {
        width: parent.width
        spacing: 6
        CcButton { cc: look; text: "bubble"; on: root.bubble; onClicked: root.saveSetting("bubble", true) }
        CcButton { cc: look; text: "free"; on: !root.bubble; onClicked: root.saveSetting("bubble", false) }
      }
      CcHeading { cc: look; text: "ON THE BAR" }
      Flow {
        width: parent.width
        spacing: 6
        CcButton { cc: look; text: "always"; on: !root.onlyWithUpdates; onClicked: root.setOnlyWithUpdates(false) }
        CcButton { cc: look; text: "only with updates"; on: root.onlyWithUpdates; onClicked: root.setOnlyWithUpdates(true) }
      }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "It acts up when Omarchy has updates: left-click it to see them and update."
        color: look.ink; opacity: 0.7; font.family: look.font; font.pixelSize: 10
      }
    }
  }
}
