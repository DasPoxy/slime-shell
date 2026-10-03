import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import "../../ui"
import ".."

Item {
  id: tavernDeep
  // the Tasks tab (TasksTab.qml), which this used to sit inside
  property var tasks: null
  anchors.fill: parent
  opacity: 0.5
  z: -1

  // broken wall boards: horizontal planks with snapped ends, nails, and
  // gaps where the goo shows through
  Repeater {
    model: [[0.02, 0.18, 0.30, 7], [0.36, 0.14, 0.22, 3], [0.64, 0.22, 0.33, 5], [0.05, 0.43, 0.20, 2],
            [0.30, 0.47, 0.28, 8], [0.72, 0.50, 0.24, 4], [0.12, 0.66, 0.26, 6], [0.58, 0.70, 0.18, 1]]
    Item {
      required property var modelData
      readonly property real bw: modelData[2] * tasks.width
      readonly property int seed: modelData[3]
      x: modelData[0] * tasks.width
      y: modelData[1] * tasks.height
      width: bw + 16; height: 22
      WoodPath {
        tasks: tavernDeep.tasks
        d: {
          var w = parent.bw, s = parent.seed
          // left end square, right end snapped into splinters
          return "M0 2 L" + w + " 2 L" + (w - 6 - s) + " 7 L" + (w + 6) + " 10 L" + (w - 4) + " 13 L" + (w + 2 - s % 3 * 3) + " 17 L0 18 Z"
        }
      }
      Rectangle { x: 6; y: 5; width: 3; height: 3; radius: 1.5; color: tasks.cc.ink }
      Rectangle { x: 6; y: 12; width: 3; height: 3; radius: 1.5; color: tasks.cc.ink }
      Rectangle { x: 14; y: 9; width: parent.bw * 0.5; height: 1; color: tasks.cc.ink; opacity: 0.35 }
    }
  }
  // holes knocked through the wall
  Repeater {
    model: [[0.48, 0.32, 46, 30], [0.20, 0.55, 34, 26], [0.84, 0.36, 40, 34]]
    WoodPath {
      tasks: tavernDeep.tasks
      required property var modelData
      anchors.fill: undefined
      x: modelData[0] * tasks.width; y: modelData[1] * tasks.height
      width: modelData[2]; height: modelData[3]
      fill: Qt.rgba(tasks.cc.ink.r, tasks.cc.ink.g, tasks.cc.ink.b, 0.55)
      line: 1.2
      d: {
        var w = modelData[2], h = modelData[3]
        return "M" + w * 0.1 + " " + h * 0.3 + " L" + w * 0.35 + " 0 L" + w * 0.5 + " " + h * 0.22 + " L" + w * 0.8 + " " + h * 0.05
          + " L" + w + " " + h * 0.55 + " L" + w * 0.75 + " " + h + " L" + w * 0.4 + " " + h * 0.8 + " L0 " + h * 0.9 + " Z"
      }
    }
  }

  // the bar: a counter along the floor with taps and tankards on it
  Item {
    id: barCounter
    x: tasks.width * 0.2
    y: tasks.height - 78
    width: tasks.width * 0.5
    height: 78
    // back shelf with bottles
    Rectangle { y: -64; width: parent.width; height: 6; radius: 2; color: tasks.woodLight; border.color: tasks.cc.ink; border.width: 1.2 }
    Repeater {
      model: 7
      Rectangle {
        required property int index
        x: 16 + index * (barCounter.width - 32) / 6
        y: -64 - height
        width: 9; height: 18 + (index * 7) % 9; radius: 3
        color: index % 3 === 0 ? tasks.cc.slime : index % 3 === 1 ? tasks.woodLight : tasks.cc.paper
        border.color: tasks.cc.ink; border.width: 1
        Rectangle { x: 2.5; y: -5; width: 4; height: 6; color: tasks.cc.ink }
      }
    }
    // counter top and front
    Rectangle { y: 10; width: parent.width; height: 12; radius: 4; color: tasks.woodLight; border.color: tasks.cc.ink; border.width: 1.6 }
    Rectangle { x: 6; y: 22; width: parent.width - 12; height: parent.height - 22; color: tasks.wood; border.color: tasks.cc.ink; border.width: 1.6 }
    Repeater {
      model: 6
      Rectangle {
        required property int index
        x: 6 + (index + 1) * (barCounter.width - 12) / 7
        y: 22; width: 1.5; height: barCounter.height - 22
        color: tasks.cc.ink; opacity: 0.45
      }
    }
    // taps
    Repeater {
      model: 3
      Item {
        required property int index
        x: barCounter.width * (0.15 + index * 0.1)
        y: -12
        width: 12; height: 24
        Rectangle { x: 4; width: 4; height: 16; radius: 2; color: tasks.cc.paper; border.color: tasks.cc.ink; border.width: 1 }
        Rectangle { x: 1; y: 14; width: 10; height: 8; radius: 2; color: tasks.woodLight; border.color: tasks.cc.ink; border.width: 1 }
      }
    }
    // tankards left on the bar
    Repeater {
      model: [0.52, 0.64, 0.83]
      SlimeGear {
        required property var modelData
        x: barCounter.width * modelData
        y: -12
        width: 24; height: 24; size: 24
        bar: tasks.bar
        kind: "mug"
      }
    }
  }

  // a rack of mead barrels on their sides, stacked three-two-one
  Item {
    id: meadRack
    x: 8
    y: tasks.height - height - 6
    width: 3 * 52 + 8
    height: 3 * 46 + 18
    Repeater {
      model: [[0, 2], [1, 2], [2, 2], [0.5, 1], [1.5, 1], [1, 0]]
      MeadBarrel {
        tasks: tavernDeep.tasks
        required property var modelData
        size: 50
        x: 4 + modelData[0] * 52
        y: modelData[1] * 44
      }
    }
    // the rack's legs
    Rectangle { x: 0; y: parent.height - 10; width: parent.width; height: 8; radius: 2; color: tasks.woodLight; border.color: tasks.cc.ink; border.width: 1.2 }
  }
}
