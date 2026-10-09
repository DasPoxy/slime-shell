import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "../slime.bar/ui"
import "../slime.bar/commandcenter"
import "../slime.bar/ui/WidgetSettings.js" as WidgetSettings

// Slime Shell workspaces. Right-click for a slime menu that picks
//   count  "5" / "10" (always shown, 1..n) or "populated" (only workspaces
//          that exist, plus the focused one)
//   style  "slime" (a monster per workspace: asleep when empty, awake with
//          windows, emoting when focused), "pips", "numbers" or "stars"
// Both are stored in this widget's shell.json entry. Off the slime bar the
// stock numbered buttons render and right-click does nothing new.
BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  readonly property bool slime: !!root.bar && root.bar.slimeSkin === true
  readonly property string count: String(setting("count", "5"))
  readonly property string indicator: setting("style", "slime")
  property bool menuOpen: false

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  function workspaceIds() {
    var ids = []
    var values = Hyprland.workspaces.values
    if (count === "10") ids = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    else if (count !== "populated") ids = [1, 2, 3, 4, 5]
    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }
    var focused = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
    if (focused > 0 && focused <= 10 && ids.indexOf(focused) === -1) ids.push(focused)
    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  function saveSetting(key, value) { WidgetSettings.save(root, WidgetSettings.one(key, value)) }

  // popout contract so the bar closes this menu when another panel opens
  function close() { menuOpen = false }

  IpcHandler {
    target: "slime-workspaces"
    function menu(): void { root.menuOpen = root.slime && !root.menuOpen }
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  // ---- indicator drawings ----------------------------------------------------
  component Star: Shape {
    id: star
    property color fill: "white"
    property color ink: "black"
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      fillColor: star.fill
      strokeColor: star.ink
      strokeWidth: 1.4
      joinStyle: ShapePath.RoundJoin
      PathSvg {
        path: {
          var s = star.width, c = s / 2, d = ""
          for (var i = 0; i < 10; i++) {
            var r = i % 2 === 0 ? s * 0.5 : s * 0.22
            var a = -Math.PI / 2 + i * Math.PI / 5
            d += (i === 0 ? "M " : " L ") + (c + r * Math.cos(a)) + " " + (c + r * Math.sin(a))
          }
          return d + " Z"
        }
      }
    }
  }

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        id: wsButton
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
        readonly property string look: root.slime ? root.indicator : "stock"
        readonly property real t: root.slime ? root.bar.animTime : 0
        readonly property color ink: root.slime ? root.bar.slimeInk : "black"

        bar: root.bar
        text: look === "stock" ? (focused ? "󱓻" : (modelData === 10 ? "0" : String(modelData))) : ""
        hasVisualContent: true
        opacity: look !== "stock" || occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize
          : look === "slime" ? 28 : look === "pips" ? (focused ? 30 : 16) : look === "stock" ? Style.space(20) : 24
        fixedHeight: root.barSize
        Behavior on fixedWidth { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
        onPressed: function(b) {
          if (b === Qt.RightButton && root.slime) root.menuOpen = !root.menuOpen
          else root.focusWorkspace(modelData)
        }

        // slime monsters
        SlimeMonster {
          visible: wsButton.look === "slime"
          anchors.centerIn: parent
          anchors.verticalCenterOffset: 1
          size: wsButton.focused ? 26 : 20
          variant: (wsButton.modelData - 1) % 5
          mood: wsButton.focused ? "emote" : (wsButton.occupied ? "idle" : "sleep")
          opacity: wsButton.focused || wsButton.occupied ? 1 : 0.6
          time: wsButton.t
          body: root.slime ? root.bar.monsterBodyFor(wsButton.modelData - 1) : "transparent"
          body2: root.slime ? root.bar.monsterBody2For(wsButton.modelData - 1) : "transparent"
          ink: wsButton.ink
          eye: root.slime ? root.bar.paperColor : "white"
          blush: root.slime ? root.bar.monsterBlush : "pink"
          material: root.slime ? root.bar.material : "slime"
          Behavior on size { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
        }

        // pips: goo droplets, the focused one stretched into a pill
        Rectangle {
          visible: wsButton.look === "pips"
          anchors.centerIn: parent
          width: wsButton.focused ? 22 : 9
          height: 9
          radius: 4.5
          color: wsButton.focused || wsButton.occupied ? wsButton.ink : "transparent"
          border.color: wsButton.ink
          border.width: 2
          opacity: wsButton.focused || wsButton.occupied ? 1 : 0.6
          Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
        }

        // numbers: bold ink, the focused one in a cream bubble
        Rectangle {
          visible: wsButton.look === "numbers" && wsButton.focused
          anchors.centerIn: parent
          width: 20; height: 20; radius: 10
          color: root.slime ? root.bar.monsterBody : "white"
          border.color: wsButton.ink
          border.width: 1.5
        }
        Text {
          textFormat: Text.PlainText
          visible: wsButton.look === "numbers"
          anchors.centerIn: parent
          text: wsButton.modelData === 10 ? "0" : String(wsButton.modelData)
          color: wsButton.ink
          opacity: wsButton.focused || wsButton.occupied ? 1 : 0.5
          font.family: root.bar && root.bar.displayFontFamily ? root.bar.displayFontFamily : Style.font.family
          font.pixelSize: wsButton.focused ? 14 : 13
          font.weight: root.bar ? root.bar.displayWeight : Font.Black
        }

        // stars: hollow when empty, filled with windows, big and twinkling when focused
        Star {
          visible: wsButton.look === "stars"
          anchors.centerIn: parent
          width: wsButton.focused ? 22 : 15
          height: width
          rotation: wsButton.focused ? Math.sin(wsButton.t * 2) * 12 : 0
          fill: wsButton.focused ? (root.slime && root.bar.slimePalette.yellow ? root.bar.slimePalette.yellow : "#ffd000")
            : wsButton.occupied ? (root.slime ? root.bar.monsterBody : "white") : "transparent"
          ink: wsButton.ink
          opacity: wsButton.focused || wsButton.occupied ? 1 : 0.55
          Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
        }
      }
    }
  }

  // ---- right-click menu ---------------------------------------------------------
  QtObject {
    id: menuLook
    readonly property var bar: root.bar
    readonly property color ink: root.slime ? root.bar.slimeInk : Color.foreground
    readonly property color slime: root.slime ? root.bar.slimeColor : Color.accent
    readonly property string font: root.bar ? root.bar.fontFamily : Style.font.family
  }

  SlimePopupCard {
    id: menu
    anchorItem: grid
    owner: root
    bar: root.bar
    open: root.menuOpen
    contentWidth: Style.space(300)
    contentHeight: menu.fittedContentHeight(menuColumn.implicitHeight)

    Column {
      id: menuColumn
      anchors.fill: parent
      spacing: 8

      CcHeading { cc: menuLook; text: "SHOW" }
      Flow {
        width: parent.width
        spacing: 6
        Repeater {
          model: [["5", "5"], ["10", "10"], ["populated", "populated"]]
          CcButton {
            required property var modelData
            cc: menuLook
            text: modelData[0]
            on: root.count === modelData[1]
            onClicked: root.saveSetting("count", modelData[1])
          }
        }
      }

      CcHeading { cc: menuLook; text: "INDICATORS" }
      Flow {
        width: parent.width
        spacing: 6
        Repeater {
          model: [["", "slimes", "slime"], ["", "pips", "pips"], ["#", "numbers", "numbers"], ["", "stars", "stars"]]
          CcButton {
            required property var modelData
            cc: menuLook
            icon: modelData[0]
            text: modelData[1]
            on: root.indicator === modelData[2]
            onClicked: root.saveSetting("style", modelData[2])
          }
        }
      }

      // the same choice as Settings → Slime icons (the agents robot and the
      // launcher slime follow it too)
      CcHeading { cc: menuLook; text: "SLIME COLOURS (ALL SLIME ICONS)"; visible: root.indicator === "slime" }
      Flow {
        visible: root.indicator === "slime"
        width: parent.width
        spacing: 6
        Repeater {
          model: [["paper", "paper"], ["theme colours", "theme"], ["bar gradient", "gradient"]]
          CcButton {
            required property var modelData
            cc: menuLook
            text: modelData[0]
            on: root.bar && root.bar.monsterColor === modelData[1]
            onClicked: if (root.bar) root.bar.monsterColor = modelData[1]
          }
        }
      }
    }
  }
}
