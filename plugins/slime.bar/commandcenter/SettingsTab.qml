import QtQuick
import Quickshell
import Quickshell.Io
import "../ui"

// Settings: the slime skin (colour, gradient, shading, animation, drips) and
// shortcuts to the widget settings that live elsewhere.
Item {
  id: settings
  // the command centre's text size (Settings → Command centre → text size)
  readonly property real fs: cc && cc.fontScale ? cc.fontScale : 1

  property var cc: null
  readonly property var bar: cc ? cc.bar : null

  implicitHeight: column.implicitHeight

  // plugin id -> the name it goes by (same list the treasure chest reads)
  property var pluginNames: ({})
  Process {
    running: true
    command: ["omarchy-plugin-list", "--json"]
    stdout: StdioCollector {
      onStreamFinished: {
        var all
        try { all = JSON.parse(text) } catch (e) { return }
        var m = {}
        for (var i = 0; i < all.length; i++) if (all[i].id) m[all[i].id] = String(all[i].name || all[i].id)
        settings.pluginNames = m
      }
    }
  }

  // Every widget on the bar with a drip panel of its own (Slime's and any
  // other plugin's: they all offer open()/close()/opened), one per plugin,
  // named as the plugin names itself.
  readonly property var panelWidgets: {
    if (!bar) return []
    var slots = bar.moduleSlots, seen = {}, out = []
    var names = pluginNames
    for (var i = 0; i < slots.length; i++) {
      var sl = slots[i]
      if (!sl || !sl.visible || sl.width <= 0 || seen[sl.moduleName]) continue
      var it = sl.activeItem
      if (!it || typeof it.open !== "function" || typeof it.close !== "function" || it.opened === undefined) continue
      seen[sl.moduleName] = true
      var name = names[sl.moduleName] || sl.moduleName
      out.push({ id: sl.moduleName, name: String(name).replace(/^SlimeS-/, "") })
    }
    out.sort(function(a, b) { return a.name.localeCompare(b.name) })
    return out
  }

  // ---- updates (update.sh) ------------------------------------------------
  property var update: null        // last JSON from update.sh
  property bool updateBusy: false
  readonly property string updateScript: Qt.resolvedUrl("update.sh").toString().replace("file://", "")
  Process {
    id: updater
    stdout: StdioCollector {
      onStreamFinished: {
        try { settings.update = JSON.parse(text) } catch (e) { settings.update = { status: "error", message: "no answer from git" } }
        settings.updateBusy = false
        if (settings.update.status === "updated") Quickshell.execDetached(["omarchy", "restart", "shell"])
      }
    }
  }
  function runUpdate(mode) {
    if (updateBusy) return
    updateBusy = true
    updater.command = ["bash", updateScript, mode]
    updater.running = true
  }

  component ChoiceRow: Column {
    id: choiceRow
    property string title
    property var options: []      // [label, value] pairs
    property var current
    signal picked(var value)
    width: parent ? parent.width : 0
    spacing: 6
    CcHeading { cc: settings.cc; text: choiceRow.title }
    Flow {
      width: choiceRow.width
      spacing: 6
      Repeater {
        model: choiceRow.options
        CcButton {
          required property var modelData
          cc: settings.cc
          text: modelData[0]
          on: choiceRow.current === modelData[1]
          onClicked: choiceRow.picked(modelData[1])
        }
      }
    }
  }

  Column {
    id: column
    width: parent.width
    spacing: 10

    CcSection {
      cc: settings.cc
      title: "Command centre"
      kind: "cottage"
      ChoiceRow {
        title: "KEYBOARD NAVIGATION (ARROWS, ENTER, 1–6, ? FOR KEYS)"
        options: [["on", true], ["off", false]]
        current: settings.bar.ccKeyboard
        onPicked: value => settings.bar.ccKeyboard = value
      }
      Column {
        id: textSize
        width: parent ? parent.width : 0
        spacing: 2
        Row {
          spacing: 4
          CcHeading { cc: settings.cc; text: "TEXT SIZE ·" }
          CcHeading {
            id: sizeReadout
            cc: settings.cc
            text: Math.round(sizeSlider.liveValue * 100) + "%"
            // click it to type the size
            SlimeValueEdit { target: sizeReadout; slider: sizeSlider; unitScale: 100 }
          }
          CcHeading { cc: settings.cc; text: " (THE BAR'S CLOCK HAS ITS OWN, IN ITS MENU)" }
        }
        Row {
          spacing: 8
          SlimeSlider {
            id: sizeSlider
            anchors.verticalCenter: parent.verticalCenter
            width: textSize.width - resetSize.width - 8
            cc: settings.cc
            minimum: 0.8
            maximum: 1.4
            step: 0.05
            value: settings.bar.ccFontScale
            // applied on release: re-laying out every tab mid-drag is jumpy
            onReleased: v => settings.bar.ccFontScale = Math.round(v * 20) / 20
          }
          CcButton {
            id: resetSize
            anchors.verticalCenter: parent.verticalCenter
            cc: settings.cc
            text: "100%"
            on: settings.bar.ccFontScale === 1
            onClicked: settings.bar.ccFontScale = 1
          }
        }
      }
    }

    CcSection {
      cc: settings.cc
      title: "Desktop styling"
      kind: "mirror"
      ChoiceRow {
        title: "ROUNDED SCREEN CORNERS"
        options: [["off", 0], ["small", 12], ["medium", 20], ["large", 32]]
        current: settings.bar.desktopCorners
        onPicked: value => settings.bar.desktopCorners = value
      }
      ChoiceRow {
        title: "SLIME IN THE FAR CORNERS (MIRRORS THE BAR)"
        options: [["off", false], ["on", true]]
        current: settings.bar.cornerSlime
        onPicked: value => settings.bar.cornerSlime = value
      }
    }

    CcSection {
      cc: settings.cc
      title: "Dock"
      kind: "chest"
      ChoiceRow {
        title: "DOCK"
        options: [["on", true], ["off", false]]
        current: settings.bar.dockEnabled
        onPicked: value => settings.bar.dockEnabled = value
      }
      ChoiceRow {
        visible: settings.bar.dockEnabled
        title: "EDGE (NOT THE BAR'S; MOVING THE BAR ONTO IT SENDS THE DOCK ACROSS)"
        options: [["bottom", "bottom"], ["top", "top"], ["left", "left"], ["right", "right"]]
          .filter(function(o) { return o[1] !== settings.bar.position })
        current: settings.bar.dockEdgeEff
        onPicked: value => settings.bar.dockEdge = value
      }
      ChoiceRow {
        readonly property bool side: settings.bar.dockEdgeEff === "left" || settings.bar.dockEdgeEff === "right"
        visible: settings.bar.dockEnabled
        title: "ALONG THE EDGE" + (settings.bar.cornerSlime ? " (AT AN END IT MELTS INTO THE CORNER SLIME)" : "")
        options: [[side ? "top" : "left", "start"], ["centre", "center"], [side ? "bottom" : "right", "end"]]
        current: settings.bar.dockAlign
        onPicked: value => settings.bar.dockAlign = value
      }
      ChoiceRow {
        visible: settings.bar.dockEnabled
        title: "HIDE UNTIL HOVERED"
        options: [["no", false], ["yes", true]]
        current: settings.bar.dockAutoHide
        onPicked: value => settings.bar.dockAutoHide = value
      }
      ChoiceRow {
        visible: settings.bar.dockEnabled
        title: "ICON SIZE"
        options: [["small", 36], ["medium", 44], ["large", 56]]
        current: settings.bar.dockIconSize
        onPicked: value => settings.bar.dockIconSize = value
      }
      CcButton {
        cc: settings.cc
        icon: "\uf067"
        text: "add apps to the dock…"
        onClicked: { settings.bar.dockEnabled = true; settings.bar.dockPanelRequest++ }
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.Wrap
        text: "Drag folders or files onto the dock to pin them; right-click an icon to move or remove it. The + on the dock opens the same add-apps panel."
        color: settings.cc.ink; opacity: 0.7
        font.family: settings.cc.font; font.pixelSize: Math.round(11 * settings.fs)
      }
    }

    CcSection {
      cc: settings.cc
      title: "Slime"
      kind: "painting"
      defaultOpen: true
      ChoiceRow {
        title: "COLOUR"
        options: [["accent", "accent"], ["green", "green"], ["cyan", "cyan"], ["magenta", "magenta"],
          ["red", "red"], ["yellow", "yellow"], ["foreground", "foreground"]]
        current: settings.bar.slimeRole
        onPicked: value => settings.bar.slimeRole = value
      }
      ChoiceRow {
        title: "GRADIENT PARTNER"
        options: [["auto", "auto"], ["none", "none"], ["magenta", "magenta"], ["cyan", "cyan"],
          ["green", "green"], ["yellow", "yellow"], ["red", "red"]]
        current: settings.bar.gradientRole
        onPicked: value => settings.bar.gradientRole = value
      }
      ChoiceRow {
        title: "MATERIAL"
        options: [["slime", "slime"], ["sinew", "sinew"], ["bone", "bone"], ["plain", "plain"], ["muscle", "muscle"]]
        current: settings.bar.material
        onPicked: value => settings.bar.material = value
      }
      ChoiceRow {
        title: "BAR POSITION"
        options: [["top", "top"], ["bottom", "bottom"], ["left", "left"], ["right", "right"]]
        current: settings.bar.position
        // same path as `omarchy bar position`, so shell.json stays the source of truth
        onPicked: value => Quickshell.execDetached(["omarchy", "bar", "position", value])
      }
      ChoiceRow {
        title: "BAR SHAPE"
        options: [["classic", "classic"], ["pills", "pills"], ["islands", "islands"], ["notch", "notch"], ["blob", "blob"]]
        current: settings.bar.barShape
        onPicked: value => settings.bar.barShape = value
      }
      ChoiceRow {
        title: "DRAW SLIME"
        options: [["above windows", "above"], ["behind windows", "behind"]]
        current: settings.bar.slimeLayer
        onPicked: value => settings.bar.slimeLayer = value
      }
      ChoiceRow {
        title: "BAR DEBRIS"
        options: [["floating bits", true], ["clean", false]]
        current: settings.bar.barDebris
        onPicked: value => settings.bar.barDebris = value
      }
      ChoiceRow {
        title: "SLIME ICONS"
        options: [["paper", "paper"], ["theme colours", "theme"], ["bar gradient", "gradient"]]
        current: settings.bar.monsterColor
        onPicked: value => settings.bar.monsterColor = value
      }
      ChoiceRow {
        title: "SHADING"
        options: [["soft", 0], ["anime", 1], ["manga", 2], ["print", 3], ["cel", 4], ["sketch", 5]]
        current: settings.bar.shadingStyle
        onPicked: value => settings.bar.shadingStyle = value
      }
    }

    CcSection {
      cc: settings.cc
      title: "Font & clock"
      kind: "scroll"
      ChoiceRow {
        title: "FONT"
        // Styro, Nippo and Array show up once installed (free from fontshare.com)
        options: [["system", "system"], ["blobby", "chewy"], ["drippy", "wetpaint"], ["bubble", "bubble"], ["runic", "runic"]]
          .concat(settings.bar.installedFaces.map(function(k) { return [k, k] }))
        current: settings.bar.fontStyle
        onPicked: value => settings.bar.fontStyle = value
      }
      ChoiceRow {
        title: "CLOCK ORDER"
        options: [["date · time", false], ["time · date", true]]
        current: settings.bar.clockTimeFirst
        onPicked: value => settings.bar.clockTimeFirst = value
      }
    }

    CcSection {
      cc: settings.cc
      title: "Motion"
      kind: "hourglass"
      ChoiceRow {
        title: "ANIMATION"
        options: [["paused", 0], ["15 fps", 15], ["30 fps", 30], ["60 fps", 60], ["120 fps", 120]]
        current: settings.bar.slimeFps
        onPicked: value => settings.bar.slimeFps = value
      }
      ChoiceRow {
        title: "DRIP STYLE"
        options: [["drip", "drip"], ["honey", "honey"], ["rain", "rain"], ["tar", "tar"], ["frozen", "frozen"],
          ["stringy", "stringy"], ["lava lamp", "lava"], ["gelatinous", "gelatinous"], ["cava", "cava"]]
        current: settings.bar.dripStyle
        onPicked: value => settings.bar.dripStyle = value
      }
      // the cava drip style's own knobs (only while it's picked)
      ChoiceRow {
        visible: settings.bar.dripStyle === "cava"
        title: "CAVA · STYLE"
        options: [["drips", "drips"], ["ripple", "ripple"]]
        current: settings.bar.cavaStyle
        onPicked: value => settings.bar.cavaStyle = value
      }
      ChoiceRow {
        visible: settings.bar.dripStyle === "cava" && settings.bar.cavaStyle !== "ripple"
        title: "CAVA · BARS"
        options: [["24", 24], ["48", 48], ["80", 80], ["120", 120], ["160", 160]]
        current: settings.bar.cavaBars
        onPicked: value => settings.bar.cavaBars = value
      }
      ChoiceRow {
        visible: settings.bar.dripStyle === "cava"
        title: "CAVA · LAYOUT"
        options: [["bass → treble", false], ["mirrored (bass in the middle)", true]]
        current: settings.bar.cavaMirror
        onPicked: value => settings.bar.cavaMirror = value
      }
      ChoiceRow {
        visible: settings.bar.dripStyle === "cava"
        title: "CAVA · SENSITIVITY"
        options: [["auto", 0], ["low", 50], ["medium", 100], ["high", 180], ["max", 300]]
        current: settings.bar.cavaSens
        onPicked: value => settings.bar.cavaSens = value
      }
      ChoiceRow {
        visible: settings.bar.dripStyle === "cava"
        title: "CAVA · REACH"
        options: [["short", 0.55], ["medium", 1.0], ["long", 1.5], ["floor it", 2.1]]
        current: settings.bar.cavaReach
        onPicked: value => settings.bar.cavaReach = value
      }
      ChoiceRow {
        visible: settings.bar.dripStyle === "cava" && settings.bar.cavaStyle !== "ripple"
        title: "CAVA · THICKNESS"
        options: [["thin", 0.6], ["normal", 1.0], ["thick", 1.5], ["chunky", 2.2]]
        current: settings.bar.cavaWidth
        onPicked: value => settings.bar.cavaWidth = value
      }
      ChoiceRow {
        visible: settings.bar.dripStyle === "cava"
        title: "CAVA · SMOOTHING"
        options: [["snappy", 20], ["smooth", 55], ["syrupy", 85]]
        current: settings.bar.cavaSmooth
        onPicked: value => settings.bar.cavaSmooth = value
      }
      ChoiceRow {
        title: "DRIP AMOUNT"
        options: [["dry", 0.4], ["ooze", 1.0], ["gush", 1.7], ["torrent", 2.6], ["variable", -1]]
        current: settings.bar.dripAmount
        onPicked: value => settings.bar.dripAmount = value
      }
    }

    CcSection {
      cc: settings.cc
      title: "Updates"
      kind: "potion"
      Row {
        spacing: 8
        CcButton {
          cc: settings.cc
          icon: "\uf021"
          text: settings.updateBusy ? "Checking…" : "Check for updates"
          onClicked: settings.runUpdate("check")
        }
        CcButton {
          visible: !!settings.update && settings.update.status === "behind" && !settings.update.dirty
          cc: settings.cc
          on: true
          icon: "\uf019"
          text: "Update & restart"
          onClicked: settings.runUpdate("pull")
        }
      }
      Text {
        textFormat: Text.PlainText
        visible: !!settings.update
        width: parent.width
        wrapMode: Text.Wrap
        color: settings.cc.ink
        font.family: settings.cc.font
        font.pixelSize: Math.round(12 * settings.fs)
        text: {
          var u = settings.update
          if (!u) return ""
          if (u.status === "error") return "Couldn't check: " + u.message
          if (u.status === "updated") return "Updated to " + u.local + " — restarting the shell…"
          var head = u.status === "current" ? "Up to date on " + u.branch + " (" + u.local + ")."
            : u.status === "diverged" ? "Your copy and the remote have both moved on; update by hand."
            : u.behind + " update" + (u.behind === 1 ? "" : "s") + " available (" + u.local + " → " + u.remote + "):"
          if (u.dirty) head += "  You have uncommitted changes, so updating is off."
          return head
        }
      }
      Repeater {
        model: settings.update && settings.update.log ? settings.update.log : []
        Text {
          textFormat: Text.PlainText
          required property string modelData
          width: parent.width
          elide: Text.ElideRight
          text: "•  " + modelData
          color: settings.cc.ink
          font.family: settings.cc.font
          font.pixelSize: Math.round(11 * settings.fs)
          opacity: 0.85
        }
      }
    }

    CcSection {
      cc: settings.cc
      title: "Widgets"
      kind: "anvil"
      CcHeading { cc: settings.cc; text: "SLIME WIDGET SETTINGS" }
      Flow {
        width: parent.width
        spacing: 6
        // each opens that widget's own settings panel on the bar
        Repeater {
          model: [
            ["\uf017", "Date & time", "slime.clock-weather", "settingsOpen"],
            ["\uf1b0", "Launcher icon", "slime.menu", "pickerOpen"],
            ["\uf009", "Workspaces", "slime.workspaces", "menuOpen"],
            ["\uf001", "Karaoke", "slime.media", "settingsOpen"],
            ["\uf0a1", "System update", "slime.system-update", "menuOpen"],
            ["\uf07b", "Treasure chest", "slime.plugins", "open()"],
            ["\uf337", "Spacers", "slime.spacer", "menuOpen"]
          ]
          CcButton {
            required property var modelData
            readonly property var target: settings.cc.widget(modelData[2])
            visible: !!target && target.visible !== false
            cc: settings.cc
            icon: modelData[0]
            text: modelData[1]
            onClicked: {
              settings.bar.commandCenterOpen = false
              var t = target, prop = modelData[3]
              // after the command centre starts closing, so the panel isn't
              // closed again by the one-dropdown-at-a-time rule
              Qt.callLater(function() {
                if (prop === "open()") t.open()
                else t[prop] = true
              })
            }
          }
        }
      }
      // widgets that can keep off the bar until they're needed (set here,
      // since while they're hidden there's nothing on the bar to click)
      ChoiceRow {
        readonly property var w: settings.cc.widget("slime.power")
        visible: !!w
        title: "POWER ON THE BAR"
        options: [["always", false], ["only with a battery", true]]
        current: w ? w.batteryOnly : false
        onPicked: value => w.setBatteryOnly(value)
      }
      ChoiceRow {
        readonly property var w: settings.cc.widget("omarchy.system-update") || settings.cc.widget("slime.system-update")
        visible: !!w
        title: "SYSTEM UPDATE ON THE BAR"
        options: [["always", false], ["only with updates", true]]
        current: w ? w.onlyWithUpdates : false
        onPicked: value => w.setOnlyWithUpdates(value)
      }
      CcHeading { cc: settings.cc; text: "WIDGET PANELS" }
      Flow {
        width: parent.width
        spacing: 6
        // each drips open that widget's own panel, as if it were clicked
        Repeater {
          model: settings.panelWidgets
          CcButton {
            required property var modelData
            cc: settings.cc
            text: modelData.name
            onClicked: {
              settings.bar.commandCenterOpen = false
              var id = modelData.id
              Qt.callLater(function() { settings.bar.summonBarWidget(id) })
            }
          }
        }
      }
    }
  }
}
