import QtQuick

// Settings: the slime skin (colour, gradient, shading, animation, drips) and
// shortcuts to the widget settings that live elsewhere.
Item {
  id: settings

  property var cc: null
  readonly property var bar: cc ? cc.bar : null

  implicitHeight: column.implicitHeight

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
        title: "DRAW SLIME"
        options: [["above windows", "above"], ["behind windows", "behind"]]
        current: settings.bar.slimeLayer
        onPicked: value => settings.bar.slimeLayer = value
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
        options: [["system", "system"], ["Chewy (blobby)", "chewy"], ["Wet Paint (drippy)", "wetpaint"]]
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
        title: "DRIPS"
        options: [["dry", 0.4], ["ooze", 1.0], ["gush", 1.7]]
        current: settings.bar.dripAmount
        onPicked: value => settings.bar.dripAmount = value
      }
    }

    CcSection {
      cc: settings.cc
      title: "Widgets"
      kind: "anvil"
      Flow {
        width: parent.width
        spacing: 6
        CcButton {
          cc: settings.cc
          icon: "\uf017"; text: "Date & time"
          onClicked: {
            var clock = settings.cc.widget("slime.clock-weather")
            settings.bar.commandCenterOpen = false
            if (clock) clock.settingsOpen = true
          }
        }
        CcButton {
          cc: settings.cc
          icon: "\uf1b0"; text: "Launcher icon"
          onClicked: {
            var menu = settings.cc.widget("slime.menu")
            settings.bar.commandCenterOpen = false
            if (menu) menu.pickerOpen = true
          }
        }
      }
    }
  }
}
