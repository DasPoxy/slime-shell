import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../slime.bar/ui"

// Date & time settings for the clock-weather widget, dripping out of the bar
// on middle click. Every choice is written straight back to the widget's
// shell.json entry through `widget.saveSetting`, so it applies immediately and
// survives restarts.
SlimeKeyboardPanel {
  id: panel

  required property var widget
  property date now: new Date()

  readonly property color ink: bar && bar.slimeSkin ? bar.slimeInk : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string displayFamily: bar && bar.displayFontFamily ? bar.displayFontFamily : fontFamily

  // [label shown as a live preview, Qt date pattern ("" = no date)]
  readonly property var datePatterns: [
    ["ddd d MMM", "ddd d MMM"],
    ["dddd, d MMMM", "dddd, d MMMM"],
    ["MMM d", "MMM d"],
    ["MMMM d, yyyy", "MMMM d, yyyy"],
    ["dd/MM/yy", "dd/MM/yy"],
    ["MM/dd/yy", "MM/dd/yy"],
    ["yyyy-MM-dd", "yyyy-MM-dd"],
    ["@initial", "@initial"],
    ["", ""]
  ]
  readonly property var weights: [["Bold", Font.Bold], ["Heavy", Font.ExtraBold], ["Black", Font.Black]]

  contentWidth: fittedContentWidth(Style.space(360))
  contentHeight: fittedContentHeight(column.implicitHeight)

  onOpenChanged: if (open) now = new Date()

  component Choice: Rectangle {
    id: choice
    property string label
    property bool selected
    signal picked

    implicitWidth: choiceText.implicitWidth + 20
    implicitHeight: 26
    radius: 13
    color: selected ? panel.ink : (choiceHover.hovered ? Qt.rgba(1, 1, 1, 0.75) : Qt.rgba(1, 1, 1, 0.55))

    HoverHandler { id: choiceHover }

    Text {
      textFormat: Text.PlainText
      id: choiceText
      anchors.centerIn: parent
      text: choice.label
      color: choice.selected && panel.bar ? panel.bar.slimeColor : panel.ink
      font.family: panel.fontFamily
      font.pixelSize: 12
      font.bold: true
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: choice.picked()
    }
  }

  component Heading: Text {
    textFormat: Text.PlainText
    color: panel.ink
    font.family: panel.fontFamily
    font.pixelSize: 10
    font.bold: true
    opacity: 0.7
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(8)

    Text {
      textFormat: Text.PlainText
      text: "Date & Time"
      color: panel.ink
      font.family: panel.displayFamily
      font.pixelSize: 16
      font.weight: panel.bar && panel.bar.slimeFonts ? panel.bar.displayWeight : Font.Black
    }
    Text {
      textFormat: Text.PlainText
      text: panel.widget.timeText
      color: panel.ink
      font.family: panel.displayFamily
      font.pixelSize: panel.widget.fontSize
      font.weight: panel.bar && panel.bar.slimeFonts ? panel.bar.displayWeight : panel.widget.fontWeight
      opacity: 0.8
    }

    Heading { text: "CLOCK" }
    Flow {
      width: parent.width
      spacing: 6
      Choice {
        label: "24-hour  " + Qt.formatTime(panel.now, "HH:mm")
        selected: panel.widget.hour24
        onPicked: panel.widget.saveSetting("hour24", true)
      }
      Choice {
        label: "12-hour  " + Qt.formatTime(panel.now, "h:mm AP")
        selected: !panel.widget.hour24
        onPicked: panel.widget.saveSetting("hour24", false)
      }
    }

    Heading { text: "WEATHER" }
    Flow {
      width: parent.width
      spacing: 6
      Repeater {
        model: [["icon", "icon"], ["temperature", "temp"], ["icon + temperature (icon floats behind)", "both"]]
        Choice {
          required property var modelData
          label: modelData[0]
          selected: panel.widget.weatherShow === modelData[1]
          onPicked: panel.widget.saveSetting("weatherShow", modelData[1])
        }
      }
    }

    Heading { text: "EXTRAS" }
    Flow {
      width: parent.width
      spacing: 6
      Choice {
        label: "bubble round the weather"
        selected: panel.widget.weatherBubble
        onPicked: panel.widget.saveSetting("weatherBubble", !panel.widget.weatherBubble)
      }
      Choice {
        label: "goblins on the time"
        selected: panel.widget.goblins
        onPicked: panel.widget.saveSetting("goblins", !panel.widget.goblins)
      }
    }

    Heading { text: "ORDER" }
    Flow {
      width: parent.width
      spacing: 6
      Choice {
        label: "Date · time"
        selected: !!panel.bar && !panel.bar.clockTimeFirst
        onPicked: if (panel.bar) panel.bar.clockTimeFirst = false
      }
      Choice {
        label: "Time · date"
        selected: !!panel.bar && panel.bar.clockTimeFirst
        onPicked: if (panel.bar) panel.bar.clockTimeFirst = true
      }
    }

    Heading { text: "DATE" }
    Flow {
      width: parent.width
      spacing: 6
      Repeater {
        model: panel.datePatterns
        Choice {
          required property var modelData
          label: modelData[1] === "" ? "Time only" : modelData[1] === "@initial" ? panel.widget.initialText(panel.now) : Qt.formatDate(panel.now, modelData[0])
          selected: panel.widget.datePattern === modelData[1]
          onPicked: panel.widget.saveSetting("datePattern", modelData[1])
        }
      }
    }

    Heading { text: "WEIGHT" }
    Flow {
      width: parent.width
      spacing: 6
      Repeater {
        model: panel.weights
        Choice {
          required property var modelData
          label: modelData[0]
          selected: panel.widget.fontWeight === modelData[1]
          onPicked: panel.widget.saveSetting("fontWeight", modelData[1])
        }
      }
    }

    Heading {
      id: sizeHeading
      text: "SIZE  ·  " + panel.widget.fontSize + "px"
      // click the size to type it
      SlimeValueEdit { target: sizeHeading; slider: sizeSlider }
    }
    SlimePanelSlider {
      id: sizeSlider
      width: parent.width
      bar: panel.bar
      minimum: 11
      maximum: 32
      step: 1
      integer: true
      value: panel.widget.fontSize
      onReleased: value => panel.widget.saveSetting("fontSize", Math.round(value))
    }

  }

  // Held as a property: the panel's default children are its card content.
  property Timer nowTimer: Timer {
    interval: 30000
    repeat: true
    running: panel.open
    onTriggered: panel.now = new Date()
  }
}
