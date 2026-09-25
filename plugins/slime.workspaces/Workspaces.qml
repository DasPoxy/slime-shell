import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "../slime.bar/ui"

// Slime Shell: on the slime bar each workspace is a little slime monster
// instead of a number — asleep when empty, awake (and blinking) when it holds
// windows, and emoting when focused. Each workspace keeps its own monster.
// Off the slime bar it renders the stock numbered buttons.
BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)
  readonly property bool slime: !!root.bar && root.bar.slimeSkin === true

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

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
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        id: wsButton
        bar: root.bar
        text: root.slime ? "" : (focused ? "\uDB85\uDCFB" : (modelData === 10 ? "0" : String(modelData)))
        hasVisualContent: true
        opacity: root.slime || occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : (root.slime ? 28 : Style.space(20))
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }

        SlimeMonster {
          visible: root.slime
          anchors.centerIn: parent
          anchors.verticalCenterOffset: 1
          size: wsButton.focused ? 26 : 20
          variant: (wsButton.modelData - 1) % 5
          mood: wsButton.focused ? "emote" : (wsButton.occupied ? "idle" : "sleep")
          opacity: wsButton.focused || wsButton.occupied ? 1 : 0.6
          time: root.slime ? root.bar.animTime : 0
          body: root.slime ? root.bar.monsterBody : "transparent"
          ink: root.slime ? root.bar.slimeInk : "black"
          eye: root.slime ? root.bar.paperColor : "white"
          blush: root.slime ? root.bar.monsterBlush : "pink"
          Behavior on size { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
        }
      }
    }
  }
}
