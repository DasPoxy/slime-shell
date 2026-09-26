import QtQuick
import Quickshell
import Quickshell.Io

// Settings: the slime skin (colour, gradient, shading, animation, drips) and
// shortcuts to the widget settings that live elsewhere.
Item {
  id: settings

  property var cc: null
  readonly property var bar: cc ? cc.bar : null

  implicitHeight: column.implicitHeight

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
        options: [["slime", "slime"], ["sinew", "sinew"], ["bone", "bone"], ["plain", "plain"]]
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
        options: [["classic", "classic"], ["pills", "pills"], ["islands", "islands"], ["notch", "notch"]]
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
        title: "SHADING"
        options: [["soft", 0], ["anime", 1], ["manga", 2], ["print", 3]]
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
        options: [["system", "system"], ["blobby", "chewy"], ["drippy", "wetpaint"], ["bubble", "bubble"]]
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
        options: [["paused", 0], ["30 fps", 30], ["60 fps", 60], ["120 fps", 120]]
        current: settings.bar.slimeFps
        onPicked: value => settings.bar.slimeFps = value
      }
      ChoiceRow {
        title: "DRIP STYLE"
        options: [["drip", "drip"], ["honey", "honey"], ["rain", "rain"], ["tar", "tar"], ["frozen", "frozen"]]
        current: settings.bar.dripStyle
        onPicked: value => settings.bar.dripStyle = value
      }
      ChoiceRow {
        title: "DRIP AMOUNT"
        options: [["dry", 0.4], ["ooze", 1.0], ["gush", 1.7]]
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
        visible: !!settings.update
        width: parent.width
        wrapMode: Text.Wrap
        color: settings.cc.ink
        font.family: settings.cc.font
        font.pixelSize: 12
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
          required property string modelData
          width: parent.width
          elide: Text.ElideRight
          text: "•  " + modelData
          color: settings.cc.ink
          font.family: settings.cc.font
          font.pixelSize: 11
          opacity: 0.85
        }
      }
    }

    CcSection {
      cc: settings.cc
      title: "Widgets"
      kind: "anvil"
      Flow {
        width: parent.width
        spacing: 6
        // each opens that widget's own settings panel on the bar
        Repeater {
          model: [
            ["\uf017", "Date & time", "slime.clock-weather", "settingsOpen"],
            ["\uf1b0", "Launcher icon", "slime.menu", "pickerOpen"],
            ["\uf009", "Workspaces", "slime.workspaces", "menuOpen"],
            ["\uf001", "Media (lich)", "slime.media", "settingsOpen"],
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
    }
  }
}
